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
 * only does what GDScript cannot: build native Intents from the Manager's
 * launcher profiles (docs/contract.md §7-8) and fire them.
 *
 * The `am start` command lines Pegasus uses today are serialized Intents;
 * this is the mechanical translation (-a -> setAction, -n -> setComponent,
 * -e -> putExtra, -d -> setData, --grant-read-uri-permission ->
 * FLAG_GRANT_READ_URI_PERMISSION, --activity-single-top ->
 * FLAG_ACTIVITY_SINGLE_TOP).
 */
class CrystalPlugin(godot: Godot) : GodotPlugin(godot) {

    override fun getPluginName(): String = "CrystalPlugin"

    override fun getPluginSignals(): Set<SignalInfo> =
        setOf(SignalInfo("launch_failed", String::class.java))

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
