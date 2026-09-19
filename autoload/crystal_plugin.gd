extends Node
## CrystalPlugin — GDScript side of the single Android native bridge.
##
## The whole native surface is one plugin singleton
## (Engine.get_singleton("CrystalPlugin")): intents, storage, permissions,
## installed-app list. All game logic stays in GDScript; the plugin stays
## thin. On desktop (no plugin) every call fails gracefully.

signal launch_failed(message: String)
signal data_access_granted(tree_uri: String)
signal data_access_cancelled

var _plugin: Object = null


func _ready() -> void:
	if Engine.has_singleton("CrystalPlugin"):
		_plugin = Engine.get_singleton("CrystalPlugin")
		if _plugin != null:
			if _plugin.has_signal("launch_failed"):
				_plugin.connect("launch_failed", _on_native_launch_failed)
			if _plugin.has_signal("data_access_granted"):
				_plugin.connect("data_access_granted", _on_native_data_access_granted)
			if _plugin.has_signal("data_access_cancelled"):
				_plugin.connect("data_access_cancelled", _on_native_data_access_cancelled)


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


## --- Crystal data folder (SAF) -------------------------------------------
## The launcher holds its OWN persisted SAF grant to the Manager-owned data
## folder. The Manager's storage permission does not transfer across apps,
## and raw /storage paths are unusable under scoped storage, so first launch
## presents a one-time system folder picker. The grant survives restarts and
## updates; the launcher never writes into the data folder.
##
## All paths here are relative to the granted tree, e.g. "config.json",
## "index.json", "games/ps2/slug/front.png".

## True when a live persisted grant exists (false when never granted, or
## when the user revoked it / the SD card is gone).
func has_data_access() -> bool:
	if _plugin == null:
		return false
	return bool(_plugin.call("hasDataAccess"))


## Opens the system folder picker. The result arrives asynchronously via
## data_access_granted / data_access_cancelled.
func request_data_access() -> void:
	if _plugin == null:
		return
	_plugin.call("requestDataAccess")


func saf_exists(relative_path: String) -> bool:
	if _plugin == null:
		return false
	return bool(_plugin.call("safExists", relative_path))


func saf_read_text(relative_path: String) -> String:
	if _plugin == null:
		return ""
	return str(_plugin.call("safReadText", relative_path))


func saf_read_bytes(relative_path: String) -> PackedByteArray:
	if _plugin == null:
		return PackedByteArray()
	var raw: Variant = _plugin.call("safReadBytes", relative_path)
	return raw if typeof(raw) == TYPE_PACKED_BYTE_ARRAY else PackedByteArray()


## Child display names under a tree-relative directory ("" = tree root).
## Used for diagnostics ("what did the Manager actually write?").
func saf_list(relative_path: String) -> Array:
	if _plugin == null:
		return []
	var parsed: Variant = JSON.parse_string(str(_plugin.call("safList", relative_path)))
	return parsed if typeof(parsed) == TYPE_ARRAY else []


## content:// URI for a tree-relative file ("" when missing). Reserved for
## the future emulator handoff (pass with FLAG_GRANT_READ_URI_PERMISSION).
func saf_content_uri(relative_path: String) -> String:
	if _plugin == null:
		return ""
	return str(_plugin.call("safContentUri", relative_path))


func _on_native_launch_failed(message: String) -> void:
	launch_failed.emit(str(message))


func _on_native_data_access_granted(tree_uri: String) -> void:
	data_access_granted.emit(str(tree_uri))


func _on_native_data_access_cancelled() -> void:
	data_access_cancelled.emit()
