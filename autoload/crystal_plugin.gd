extends Node
## CrystalPlugin — GDScript side of the single Android native bridge.
##
## The whole native surface is one plugin singleton
## (Engine.get_singleton("CrystalPlugin")): intents, storage, permissions,
## installed-app list. All game logic stays in GDScript; the plugin stays
## thin. On desktop (no plugin) every call fails gracefully.

signal launch_failed(message: String)

var _plugin: Object = null


func _ready() -> void:
	if Engine.has_singleton("CrystalPlugin"):
		_plugin = Engine.get_singleton("CrystalPlugin")
		if _plugin != null and _plugin.has_signal("launch_failed"):
			_plugin.connect("launch_failed", _on_native_launch_failed)


func is_available() -> bool:
	return _plugin != null


## Fire an emulator launch for one game. The profile Dictionary comes from
## docs/contract.md §7 (profiles.json); rom_path is absolute.
## Returns false immediately when the plugin is absent; async failures
## arrive via the launch_failed signal.
func launch_game(profile: Dictionary, rom_path: String) -> bool:
	if _plugin == null:
		_on_native_launch_failed("CrystalPlugin unavailable (not on Android, or plugin not installed)")
		return false
	if profile.is_empty():
		_on_native_launch_failed("no launcher profile configured for this system")
		return false
	if rom_path == "" or not FileAccess.file_exists(rom_path):
		_on_native_launch_failed("ROM not found: " + rom_path)
		return false
	var payload := JSON.stringify({"profile": profile, "romPath": rom_path})
	_plugin.call("launchEmulator", payload)
	return true


func get_installed_packages() -> Array:
	if _plugin == null:
		return []
	var raw: Variant = _plugin.call("getInstalledPackages")
	if typeof(raw) != TYPE_STRING or raw == "":
		return []
	var parsed: Variant = JSON.parse_string(raw)
	return parsed if typeof(parsed) == TYPE_ARRAY else []


## --- Crystal library via the Manager's ContentProvider -------------------
## The Manager (io.crystalnova.manager) is the SOLE owner of storage
## permission. It exposes the Crystal data tree through a ContentProvider;
## the launcher reads config.json, index.json, profiles.json and all media
## as data-root-relative paths through this bridge. No SAF grant, no folder
## picker, no /storage paths on the launcher side — install Manager,
## BUILD, open Launcher, library appears.

## True when the Manager's provider answers with a readable config.json.
func is_provider_available() -> bool:
	if _plugin == null:
		return false
	return bool(_plugin.call("isProviderAvailable"))


## Fine-grained bridge status for the failure UI: no_plugin |
## no_activity | provider_missing | access_denied | config_missing |
## config_unreadable | ok. Shown verbatim in the error so a failed bridge
## names its stage instead of guessing.
func get_provider_diagnostic() -> String:
	if _plugin == null:
		return "no_plugin"
	return str(_plugin.call("providerDiagnostic"))


## The grantable content:// URI for a data-root-relative path
## ("rom/ps2/game.iso"). Reserved for the future emulator handoff (pass
## with FLAG_GRANT_READ_URI_PERMISSION instead of a raw /storage path).
func provider_content_uri(relative_path: String) -> String:
	if _plugin == null:
		return ""
	return str(_plugin.call("providerContentUri", relative_path))


func provider_exists(relative_path: String) -> bool:
	if _plugin == null:
		return false
	return bool(_plugin.call("providerExists", relative_path))


func provider_read_text(relative_path: String) -> String:
	if _plugin == null:
		return ""
	return str(_plugin.call("providerReadText", relative_path))


func provider_read_bytes(relative_path: String) -> PackedByteArray:
	if _plugin == null:
		return PackedByteArray()
	var raw: Variant = _plugin.call("providerReadBytes", relative_path)
	return raw if typeof(raw) == TYPE_PACKED_BYTE_ARRAY else PackedByteArray()


func _on_native_launch_failed(message: String) -> void:
	launch_failed.emit(str(message))
