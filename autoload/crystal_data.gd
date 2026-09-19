extends Node
## CrystalData — reads the Manager-owned data layer per docs/contract.md.
##
## Presentation only: NEVER writes into crystal-nova-data/. The launcher keeps
## its own small state (thumbnails, last selection) under user://.

const CONTRACT_VERSION := 1

const SLOT_FILES := {
	"front": "front.png",
	"spine": "spine.png",
	"back": "back.png",
	"media": "media.png",
	"fullcover": "fullcover.png",
	"logo": "logo.png",
	"screenshot": "screenshot.png",
}

var config: Dictionary = {}
var rom_root: String = ""
var data_root: String = ""
var index_games: Dictionary = {}  # "<platform>/<gameId>" -> entry Dictionary
var profiles: Dictionary = {}     # "<platform>" -> profile Dictionary
var load_error: String = ""
var config_source: String = ""


func load_all() -> bool:
	load_error = ""
	var path := _resolve_config_path()
	if path == "":
		load_error = "no crystal config found (tried --crystal-config=, user://crystal-config.path, res://poc-config.json)"
		return false
	config_source = path
	var cfg_text := _read_text(path)
	if cfg_text == "":
		load_error = "config unreadable: " + path
		return false
	var cfg: Variant = JSON.parse_string(cfg_text)
	if typeof(cfg) != TYPE_DICTIONARY:
		load_error = "config is not a JSON object: " + path
		return false
	if int(cfg.get("version", 0)) != CONTRACT_VERSION:
		load_error = "unsupported contract version in " + path
		return false
	config = cfg
	rom_root = _rstrip_slash(str(cfg.get("romRoot", "")))
	data_root = _rstrip_slash(str(cfg.get("dataRoot", "")))
	if rom_root == "" or data_root == "":
		load_error = "config missing romRoot/dataRoot: " + path
		return false
	var index_path := str(cfg.get("indexPath", data_root + "/index.json"))
	if index_path == "":
		index_path = data_root + "/index.json"
	if not _load_index(index_path):
		return false
	_load_profiles(data_root + "/launcher/profiles.json")
	return true


func games_for_platform(platform: String) -> Array:
	var out: Array = []
	var prefix := platform + "/"
	for key: String in index_games:
		if key.begins_with(prefix):
			out.append(index_games[key])
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("title", "")) < str(b.get("title", "")))
	return out


func platforms_present() -> Array:
	var seen := {}
	for key: String in index_games:
		var slash := key.find("/")
		if slash > 0:
			seen[key.substr(0, slash)] = true
	var out: Array = seen.keys()
	out.sort()
	return out


func has_slot(entry: Dictionary, slot: String) -> bool:
	var assets: Array = entry.get("assets", [])
	return assets.has(slot)


func media_path(entry: Dictionary, slot: String) -> String:
	if not SLOT_FILES.has(slot):
		return ""
	return "%s/games/%s/%s/%s" % [data_root, str(entry.get("platform", "")),
		str(entry.get("gameId", "")), str(SLOT_FILES[slot])]


func media_exists(entry: Dictionary, slot: String) -> bool:
	var p := media_path(entry, slot)
	return p != "" and FileAccess.file_exists(p)


func rom_path(entry: Dictionary) -> String:
	var rel := str(entry.get("romRelativePath", ""))
	if rel == "":
		return ""
	return rom_root + "/" + rel.lstrip("/")


func profile_for(platform: String) -> Dictionary:
	return profiles.get(platform, {})


func load_manifest(entry: Dictionary) -> Dictionary:
	var p := "%s/games/%s/%s/manifest.json" % [data_root,
		str(entry.get("platform", "")), str(entry.get("gameId", ""))]
	var text := _read_text(p)
	if text == "":
		return {}
	var m: Variant = JSON.parse_string(text)
	return m if typeof(m) == TYPE_DICTIONARY else {}


func _resolve_config_path() -> String:
	for arg: String in OS.get_cmdline_args():
		if arg.begins_with("--crystal-config="):
			var p := arg.trim_prefix("--crystal-config=")
			if FileAccess.file_exists(p):
				return p
	var pointer := "user://crystal-config.path"
	if FileAccess.file_exists(pointer):
		var p := _read_text(pointer).strip_edges()
		if p != "" and FileAccess.file_exists(p):
			return p
	if FileAccess.file_exists("res://poc-config.json"):
		return "res://poc-config.json"
	return ""


func _load_index(index_path: String) -> bool:
	var text := _read_text(index_path)
	if text == "":
		load_error = "index.json unreadable: " + index_path
		return false
	var root: Variant = JSON.parse_string(text)
	if typeof(root) != TYPE_DICTIONARY:
		load_error = "index.json is not a JSON object: " + index_path
		return false
	if int(root.get("version", 0)) != CONTRACT_VERSION:
		load_error = "unsupported index version in " + index_path
		return false
	var games: Variant = root.get("games", {})
	if typeof(games) != TYPE_DICTIONARY:
		load_error = "index.json has no games object: " + index_path
		return false
	index_games = games
	return true


func _load_profiles(profiles_path: String) -> void:
	profiles = {}
	var text := _read_text(profiles_path)
	if text == "":
		return  # optional per contract; games simply show "not configured"
	var root: Variant = JSON.parse_string(text)
	if typeof(root) != TYPE_DICTIONARY:
		return
	if int(root.get("version", 0)) != CONTRACT_VERSION:
		return
	var p: Variant = root.get("profiles", {})
	if typeof(p) == TYPE_DICTIONARY:
		profiles = p


func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text := f.get_as_text()
	f.close()
	return text


func _rstrip_slash(s: String) -> String:
	while s.ends_with("/") and s.length() > 1:
		s = s.substr(0, s.length() - 1)
	return s
