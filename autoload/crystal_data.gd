extends Node
## CrystalData — reads the Manager-owned data layer per docs/contract.md.
##
## Presentation only: NEVER writes into crystal-nova-data/. The launcher keeps
## its own small state (thumbnails, last selection) under user://.
##
## Storage backends:
## - Desktop / raw: absolute filesystem paths via FileAccess (dev, POC).
## - Android provider: the Manager (io.crystalnova.manager) exposes its
##   data tree through a ContentProvider and remains the sole owner of
##   storage permission. All reads go through CrystalPlugin as
##   data-root-relative paths, marked with the "cp://" prefix. The launcher
##   holds no SAF grant, shows no folder picker, and never touches
##   /storage paths.

const CONTRACT_VERSION := 1
const CP_PREFIX := "cp://"

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
var use_provider := false


## Android: route every read through the Manager's ContentProvider.
## Returns false when the Manager isn't installed or its library isn't
## built — the caller shows the honest "install Manager / run BUILD"
## message instead of guessing.
func enable_provider() -> bool:
	use_provider = false
	load_error = ""
	if not CrystalPlugin.is_provider_available():
		var diag := CrystalPlugin.get_provider_diagnostic()
		load_error = "Crystal Nova Manager not found, or its library hasn't been built (bridge: %s). Install the Manager, run BUILD, then reopen Crystal Launcher." % diag
		return false
	use_provider = true
	return true


func load_all() -> bool:
	load_error = ""
	var path := _resolve_config_path()
	if path == "":
		if OS.has_feature("android"):
			var diag := CrystalPlugin.get_provider_diagnostic()
			load_error = "Crystal Nova Manager not found, or its library hasn't been built (bridge: %s). Install the Manager, run BUILD, then reopen Crystal Launcher." % diag
		else:
			load_error = "no crystal config found (tried --crystal-config=, user://crystal-config.path, shared-storage scan, res://poc-config.json)"
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
	if use_provider:
		index_path = CP_PREFIX + _provider_rel(index_path)
	if not _load_index(index_path):
		return false
	var profiles_path := data_root + "/launcher/profiles.json"
	if use_provider:
		profiles_path = CP_PREFIX + _provider_rel(profiles_path)
	_load_profiles(profiles_path)
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
	var abs := "%s/games/%s/%s/%s" % [data_root, str(entry.get("platform", "")),
		str(entry.get("gameId", "")), str(SLOT_FILES[slot])]
	if use_provider:
		return CP_PREFIX + _provider_rel(abs)
	return abs


func media_exists(entry: Dictionary, slot: String) -> bool:
	var p := media_path(entry, slot)
	if p == "":
		return false
	if p.begins_with(CP_PREFIX):
		return CrystalPlugin.provider_exists(p.trim_prefix(CP_PREFIX))
	return FileAccess.file_exists(p)


func rom_path(entry: Dictionary) -> String:
	var rel := str(entry.get("romRelativePath", ""))
	if rel == "":
		return ""
	return rom_root + "/" + rel.lstrip("/")


## Grantable content:// URI for a ROM, for the future emulator handoff
## (pass with FLAG_GRANT_READ_URI_PERMISSION instead of a raw path).
## Empty on desktop / when the provider is unavailable.
func rom_content_uri(entry: Dictionary) -> String:
	var rel := str(entry.get("romRelativePath", ""))
	if rel == "" or not use_provider:
		return ""
	return CrystalPlugin.provider_content_uri("rom/" + rel.lstrip("/"))


func profile_for(platform: String) -> Dictionary:
	return profiles.get(platform, {})


func load_manifest(entry: Dictionary) -> Dictionary:
	var p := "%s/games/%s/%s/manifest.json" % [data_root,
		str(entry.get("platform", "")), str(entry.get("gameId", ""))]
	if use_provider:
		p = CP_PREFIX + _provider_rel(p)
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
	if OS.has_feature("android"):
		# The Manager owns storage; the launcher reads through its
		# ContentProvider. No raw /storage scanning (blocked by scoped
		# storage), no folder picker, and the POC fixture must never stand
		# in for the real library on a device.
		if use_provider:
			return CP_PREFIX + "config.json"
		return ""
	var found := _discover_config()
	if found != "":
		return found
	if FileAccess.file_exists("res://poc-config.json"):
		return "res://poc-config.json"
	return ""


## Config auto-discovery (desktop dev only): the Manager writes config.json
## at the data root. Kept for desktop workflows; Android uses the Manager's
## ContentProvider instead (raw /storage access is blocked by scoped
## storage and the Manager's SAF grant does not transfer across apps).
func _discover_config() -> String:
	var volumes: Array[String] = []
	if DirAccess.dir_exists_absolute("/storage"):
		var d := DirAccess.open("/storage")
		if d != null:
			d.list_dir_begin()
			var e := d.get_next()
			while e != "":
				if d.current_is_dir() and e != "self" and not e.begins_with("."):
					volumes.append("/storage/" + e)
				e = d.get_next()
			d.list_dir_end()
	for v in ["/sdcard", "/storage/emulated/0"]:
		if not volumes.has(v):
			volumes.append(v)
	for v in volumes:
		var direct := v + "/crystal-nova-data/config.json"
		if _looks_like_crystal_config(direct):
			return direct
		var vd := DirAccess.open(v)
		if vd == null:
			continue
		vd.list_dir_begin()
		var child := vd.get_next()
		while child != "":
			if vd.current_is_dir() and not child.begins_with(".") and child != "Android":
				var p := v + "/" + child + "/config.json"
				if _looks_like_crystal_config(p):
					vd.list_dir_end()
					return p
			child = vd.get_next()
		vd.list_dir_end()
	return ""


func _looks_like_crystal_config(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var cfg: Variant = JSON.parse_string(_read_text(path))
	if typeof(cfg) != TYPE_DICTIONARY:
		return false
	return int(cfg.get("version", 0)) == CONTRACT_VERSION and str(cfg.get("dataRoot", "")) != ""


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
	if path.begins_with(CP_PREFIX):
		return CrystalPlugin.provider_read_text(path.trim_prefix(CP_PREFIX))
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text := f.get_as_text()
	f.close()
	return text


## Maps an absolute data-root path from config.json to a data-root-relative
## path for the Manager's ContentProvider (whose root IS the data root).
func _provider_rel(abs_path: String) -> String:
	var rel := abs_path
	if data_root != "" and rel.begins_with(data_root):
		rel = rel.substr(data_root.length()).lstrip("/")
	return rel


func _rstrip_slash(s: String) -> String:
	while s.ends_with("/") and s.length() > 1:
		s = s.substr(0, s.length() - 1)
	return s
