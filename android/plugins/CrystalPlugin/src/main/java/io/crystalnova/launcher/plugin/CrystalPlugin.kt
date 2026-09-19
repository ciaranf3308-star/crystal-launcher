package io.crystalnova.launcher.plugin

import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot
import org.json.JSONObject

/**
 * CrystalPlugin — the single Android native bridge for Crystal Launcher.
 *
 * Thin by design: everything game-related lives in GDScript. This plugin
 * only does what GDScript cannot:
 *
 * 1. Build native Intents from the Manager's launcher profiles
 *    (docs/contract.md §7-8) and fire them.
 * 2. Read the Manager-owned Crystal library through the Manager's
 *    ContentProvider (authority below). The Manager is the SOLE owner of
 *    storage permission; the launcher never holds its own SAF grant, never
 *    asks the user to pick a folder, and never touches /storage paths.
 *    Godot's FileAccess cannot open content:// URIs, so every read goes
 *    through here as a data-root-relative path
 *    ("config.json", "index.json", "games/ps2/slug/front.png").
 *
 * The `am start` command lines Pegasus uses today are serialized Intents;
 * this is the mechanical translation (-a -> setAction, -n -> setComponent,
 * -e -> putExtra, -d -> setData, --grant-read-uri-permission ->
 * FLAG_GRANT_READ_URI_PERMISSION, --activity-single-top ->
 * FLAG_ACTIVITY_SINGLE_TOP).
 */
class CrystalPlugin(godot: Godot) : GodotPlugin(godot) {

    companion object {
        /** Authority of the Manager app's library ContentProvider. */
        const val PROVIDER_AUTHORITY = "io.crystalnova.manager.crystaldata"
    }

    override fun getPluginName(): String = "CrystalPlugin"

    override fun getPluginSignals(): Set<SignalInfo> =
        setOf(SignalInfo("launch_failed", String::class.java))

    // ------------------------------------------------------------------
    // Emulator launching (unchanged)
    // ------------------------------------------------------------------

    /**
     * payloadJson: {"profile": {...}, "romPath": "/storage/.../game.iso"}
     * profile follows docs/contract.md §7.
     */
    @UsedByGodot
    fun launchEmulator(payloadJson: String) {
        try {
            val payload = JSONObject(payloadJson)
            val profile = payload.getJSONObject("profile")
            val romPath = payload.getString("romPath")
            val intent = buildIntent(profile, romPath)
            val host = activity ?: throw IllegalStateException("no host activity")
            host.startActivity(intent)
        } catch (t: Throwable) {
            emitSignal("launch_failed", t.message ?: t.toString())
        }
    }

    /** JSON array of installed package names we are allowed to see. */
    @UsedByGodot
    fun getInstalledPackages(): String {
        return try {
            val pm = activity?.packageManager ?: return "[]"
            val pkgs = pm.getInstalledApplications(0).map { it.packageName }
            org.json.JSONArray(pkgs).toString()
        } catch (t: Throwable) {
            "[]"
        }
    }

    // ------------------------------------------------------------------
    // Crystal library: reads via the Manager's ContentProvider.
    // ------------------------------------------------------------------

    /**
     * True when the Manager's provider answers and the library config is
     * readable — i.e. the Manager is installed and its library is built.
     * False covers every other case (Manager missing, outdated, no BUILD
     * yet); the caller shows the honest "install Manager / run BUILD"
     * message instead of guessing.
     */
    @UsedByGodot
    fun isProviderAvailable(): Boolean = providerExists("config.json")

    /**
     * The grantable content:// URI for a data-root-relative path
     * ("rom/ps2/game.iso"). For the future emulator handoff: hand this URI
     * to the target app with FLAG_GRANT_READ_URI_PERMISSION instead of a
     * raw /storage path.
     */
    @UsedByGodot
    fun providerContentUri(relativePath: String): String =
        providerUri(relativePath).toString()

    /** True when [relativePath] exists in the Manager's library. */
    @UsedByGodot
    fun providerExists(relativePath: String): Boolean {
        return try {
            val fd = godot.context.contentResolver
                .openFileDescriptor(providerUri(relativePath), "r")
            fd?.close()
            fd != null
        } catch (t: Throwable) {
            false
        }
    }

    /** File text as UTF-8, or "" when missing/unreadable. */
    @UsedByGodot
    fun providerReadText(relativePath: String): String {
        val bytes = providerReadBytes(relativePath)
        return if (bytes.isEmpty()) "" else String(bytes, Charsets.UTF_8)
    }

    /** Raw file bytes, or empty when missing/unreadable. */
    @UsedByGodot
    fun providerReadBytes(relativePath: String): ByteArray {
        return try {
            godot.context.contentResolver
                .openInputStream(providerUri(relativePath))?.use { it.readBytes() }
                ?: ByteArray(0)
        } catch (t: Throwable) {
            ByteArray(0)
        }
    }

    private fun providerUri(relativePath: String): Uri {
        val b = Uri.Builder().scheme("content").authority(PROVIDER_AUTHORITY)
        for (segment in relativePath.split("/")) {
            if (segment.isNotEmpty()) b.appendPath(segment)
        }
        return b.build()
    }

    private fun buildIntent(profile: JSONObject, romPath: String): Intent {
        val type = profile.optString("type")
        val pkg = profile.getString("package")
        var activityName = profile.optString("activity")
        if (activityName.startsWith(".")) activityName = pkg + activityName
        val intent = Intent()
        val action = profile.optString("action")
        if (action.isNotEmpty()) intent.action = action
        if (pkg.isNotEmpty() && activityName.isNotEmpty()) {
            intent.component = ComponentName(pkg, activityName)
        }
        when (type) {
            "RETROARCH" -> {
                intent.putExtra("ROM", romPath)
                val core = profile.getString("core")
                intent.putExtra("LIBRETRO", "/data/data/$pkg/cores/$core")
                intent.putExtra(
                    "CONFIGFILE",
                    "/storage/emulated/0/Android/data/$pkg/files/retroarch.cfg"
                )
                intent.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            }
            "STANDALONE" -> {
                if (profile.optString("handoff") == "DATA") {
                    val prefix = profile.optString("dataPrefix")
                    intent.data = Uri.parse(prefix + romPath)
                } else {
                    intent.putExtra(profile.getString("extraKey"), romPath)
                }
            }
            "VIEW_INTENT" -> {
                // POC: file:// URI. The Manager's future content-URI conversion
                // for scoped storage plugs in here (profiles.json gains a
                // "uriStyle" field per contract).
                intent.data = Uri.parse("file://$romPath")
                if (profile.optBoolean("grantUriPermission")) {
                    intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
            }
            else -> throw IllegalArgumentException("unsupported profile type: $type")
        }
        return intent
    }
}
