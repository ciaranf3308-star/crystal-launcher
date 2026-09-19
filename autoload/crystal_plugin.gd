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


func _on_native_launch_failed(message: String) -> void:
	launch_failed.emit(str(message))
