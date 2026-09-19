package io.crystalnova.launcher.plugin

import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot
import org.json.JSONArray
import org.json.JSONObject

/**
 * CrystalPlugin — the single Android native bridge for Crystal Launcher.
 *
 * Thin by design: everything game-related lives in GDScript. This plugin
 * only does what GDScript cannot:
 *
 * 1. Build native Intents from the Manager's launcher profiles
 *    (docs/contract.md §7-8) and fire them.
 * 2. Hold the launcher's OWN persisted SAF grant to the Manager-owned
 *    Crystal data folder. The launcher is a separate app from the Manager
 *    (io.crystalnova.manager) and does not inherit the Manager's storage
 *    permission; raw /storage paths are unusable under scoped storage.
 *    First launch shows a one-time Android folder picker
 *    ("SELECT CRYSTAL DATA FOLDER"); the grant is persisted and never
 *    asked for again. All reads (config.json, index.json, profiles.json,
 *    artwork) go through the ContentResolver as paths relative to the
 *    granted tree. The launcher NEVER writes into the data folder.
 *
 * The `am start` command lines Pegasus uses today are serialized Intents;
 * this is the mechanical translation (-a -> setAction, -n -> setComponent,
 * -e -> putExtra, -d -> setData, --grant-read-uri-permission ->
 * FLAG_GRANT_READ_URI_PERMISSION, --activity-single-top ->
 * FLAG_ACTIVITY_SINGLE_TOP).
 */
class CrystalPlugin(godot: Godot) : GodotPlugin(godot) {

    companion object {
        private const val REQ_OPEN_DATA_TREE = 0xC451A1
        private const val PREFS = "crystal_launcher_prefs"
        private const val KEY_DATA_TREE_URI = "data_tree_uri"
    }

    override fun getPluginName(): String = "CrystalPlugin"

    override fun getPluginSignals(): Set<SignalInfo> =
        setOf(
            SignalInfo("launch_failed", String::class.java),
            SignalInfo("data_access_granted", String::class.java),
            SignalInfo("data_access_cancelled"),
        )

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
    // Crystal data folder: the launcher's own persisted SAF grant.
    // ------------------------------------------------------------------

    /**
     * True when we hold a live persisted read grant for the previously
     * picked data tree. A grant the user revoked in system settings, or a
     * tree on a removed SD card, reads back as false so the setup screen
     * can ask again exactly once.
     */
    @UsedByGodot
    fun hasDataAccess(): Boolean {
        val saved = prefs().getString(KEY_DATA_TREE_URI, null) ?: return false
        return godot.context.contentResolver.persistedUriPermissions.any {
            it.uri.toString() == saved && it.isReadPermission
        }
    }

    /** The persisted tree URI, or "" when none. */
    @UsedByGodot
    fun getDataTreeUri(): String =
        prefs().getString(KEY_DATA_TREE_URI, null) ?: ""

    /**
     * Opens the system folder picker so the user can grant the launcher
     * read access to the Crystal data folder. Read-only: the launcher is
     * presentation-only and never writes into Manager-owned data.
     * Result arrives via the data_access_granted / data_access_cancelled
     * signals.
     */
    @UsedByGodot
    fun requestDataAccess() {
        val host = activity ?: return
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PREFIX_URI_PERMISSION,
            )
        }
        host.startActivityForResult(intent, REQ_OPEN_DATA_TREE)
    }

    override fun onMainActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != REQ_OPEN_DATA_TREE) return
        val treeUri: Uri? = if (resultCode == Activity.RESULT_OK) data?.data else null
        if (treeUri == null) {
            emitSignal("data_access_cancelled")
            return
        }
        try {
            godot.context.contentResolver.takePersistableUriPermission(
                treeUri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
            prefs().edit().putString(KEY_DATA_TREE_URI, treeUri.toString()).apply()
            emitSignal("data_access_granted", treeUri.toString())
        } catch (t: Throwable) {
            emitSignal("data_access_cancelled")
        }
    }

    /** True when [relativePath] (e.g. "index.json", "games/ps2/x/front.png") exists. */
    @UsedByGodot
    fun safExists(relativePath: String): Boolean =
        findDocument(relativePath) != null

    /** File text as UTF-8, or "" when missing/unreadable. */
    @UsedByGodot
    fun safReadText(relativePath: String): String {
        val bytes = safReadBytes(relativePath)
        return if (bytes.isEmpty()) "" else String(bytes, Charsets.UTF_8)
    }

    /** Raw file bytes, or empty when missing/unreadable/a directory. */
    @UsedByGodot
    fun safReadBytes(relativePath: String): ByteArray {
        val doc = findDocument(relativePath) ?: return ByteArray(0)
        if (doc.isDirectory) return ByteArray(0)
        return try {
            godot.context.contentResolver.openInputStream(doc.uri)?.use { it.readBytes() }
                ?: ByteArray(0)
        } catch (t: Throwable) {
            ByteArray(0)
        }
    }

    /** JSON array of child display names under [relativePath] ("" = tree root). */
    @UsedByGodot
    fun safList(relativePath: String): String {
        val doc = findDocument(relativePath) ?: return "[]"
        if (!doc.isDirectory) return "[]"
        return try {
            JSONArray(doc.listFiles().mapNotNull { it.name }).toString()
        } catch (t: Throwable) {
            "[]"
        }
    }

    /**
     * content:// URI for a file under the granted tree, or "" when missing.
     * For the future emulator handoff: pass to the target app with
     * FLAG_GRANT_READ_URI_PERMISSION instead of a raw /storage path.
     */
    @UsedByGodot
    fun safContentUri(relativePath: String): String =
        findDocument(relativePath)?.uri?.toString() ?: ""

    private fun prefs() =
        godot.context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun findDocument(relativePath: String): DocumentFile? {
        val treeStr = prefs().getString(KEY_DATA_TREE_URI, null) ?: return null
        var current = DocumentFile.fromTreeUri(godot.context, Uri.parse(treeStr))
            ?: return null
        for (segment in relativePath.split("/")) {
            if (segment.isEmpty()) continue
            current = current.findFile(segment) ?: return null
        }
        return current
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
