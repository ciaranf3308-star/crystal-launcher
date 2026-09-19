extends Node3D
## GameCarousel — POC 3D physical-media browser for ONE system.
##
## Proves the architecture end to end on real data:
##   real index.json + real media -> controller navigation ->
##   animated 3D selection (case + disc + logo + background layers) ->
##   real emulator launch via CrystalPlugin -> return to the same selection.
##
## Data-driven: one pooled slot design, skinned per game with the existing
## Crystal media slots. No bespoke scene per ROM.

const POOL_SIZE := 7
const SLOT_SPACING := 3.4
const MOVE_COOLDOWN := 0.18
const TEX_THUMB := 256
const TEX_HERO := 512
const SAVE_PATH := "user://crystal-launcher.cfg"

var _games: Array = []
var _system: String = ""
var _selected := 0

var _slots: Array = []  # Dictionaries: root, case_mat, disc_mat, game_idx, target_pos, target_rot, target_scale
var _cam: Camera3D
var _logo: Sprite3D
var _logo_target_alpha := 1.0
var _title_label: Label3D
var _bg_mats: Array = []  # [mat_a, mat_b]
var _bg_front := 0
var _bg_fade := 1.0
var _move_cd := 0.0
var _launch_t := -1.0
var _time := 0.0
var _initialized := false


func _ready() -> void:
	Navigator.attach(self)
	if OS.has_feature("android") and CrystalPlugin.is_available():
		# The launcher is a separate app from the Manager: it holds its own
		# persisted SAF grant to the Crystal data folder (one-time picker).
		# Raw /storage paths are unusable under scoped storage, so without
		# a grant the honest move is the setup screen — never POC data.
		if not (CrystalPlugin.has_data_access() and CrystalData.enable_saf()):
			Navigator.replace("res://scenes/setup_screen.tscn")
			return
	if not CrystalData.load_all():
		Navigator.replace("res://scenes/failure_screen.tscn",
			{"message": CrystalData.load_error, "fatal": true})
		return
	_system = _pick_system()
	_games = CrystalData.games_for_platform(_system)
	if _games.is_empty():
		Navigator.replace("res://scenes/failure_screen.tscn",
			{"message": "No games indexed for system '" + _system + "'.", "fatal": true})
		return
	_load_selection()
	_build_scene()
	CrystalPlugin.launch_failed.connect(_on_launch_failed)
	set_selection(_selected, true)
	_initialized = true


func _pick_system() -> String:
	var platforms: Array = CrystalData.platforms_present()
	if platforms.is_empty():
		return "ps2"
	if platforms.has("ps2"):
		return "ps2"
	return str(platforms[0])


func _build_scene() -> void:
	_cam = Camera3D.new()
	_cam.fov = 55.0
	add_child(_cam)
	_cam.position = Vector3(0, 1.9, 7.6)
	_cam.look_at(Vector3(0, 1.25, 0))

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, 28, 0)
	sun.light_energy = 1.15
	add_child(sun)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.02, 0.03, 0.09)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.35, 0.45, 0.65)
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)

	# Background: two crossfading quads showing screenshots.
	for i in 2:
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1, 1, 1, 0)
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		var quad := QuadMesh.new()
		quad.size = Vector2(20, 11.25)
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		mi.material_override = mat
		mi.position = Vector3(0, 2.2, -9)
		add_child(mi)
		_bg_mats.append(mat)

	# Floating logo above the selected case.
	_logo = Sprite3D.new()
	_logo.pixel_size = 0.0042
	_logo.position = Vector3(0, 3.35, 0.4)
	_logo.modulate = Color(1, 1, 1, 0)
	add_child(_logo)

	_title_label = Label3D.new()
	_title_label.pixel_size = 0.011
	_title_label.position = Vector3(0, -0.55, 0.6)
	_title_label.modulate = Color(0.92, 0.95, 1.0)
	_title_label.outline_size = 8
	_title_label.outline_modulate = Color(0.02, 0.03, 0.09, 0.9)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_title_label)

	# Pooled 3D slots: case (BoxMesh) + disc (thin CylinderMesh).
	for i in POOL_SIZE:
		var root := Node3D.new()
		add_child(root)
		var case_mat := StandardMaterial3D.new()
		case_mat.roughness = 0.55
		case_mat.albedo_color = Color(0.16, 0.19, 0.30)
		var box := BoxMesh.new()
		box.size = Vector3(1.7, 2.35, 0.28)
		var case_mi := MeshInstance3D.new()
		case_mi.mesh = box
		case_mi.material_override = case_mat
		case_mi.position = Vector3(0, 1.35, 0)
		root.add_child(case_mi)
		var disc_mat := StandardMaterial3D.new()
		disc_mat.roughness = 0.3
		disc_mat.albedo_color = Color(0.72, 0.76, 0.85)
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.78
		cyl.bottom_radius = 0.78
		cyl.height = 0.05
		var disc_mi := MeshInstance3D.new()
		disc_mi.mesh = cyl
		disc_mi.material_override = disc_mat
		disc_mi.rotation_degrees = Vector3(90, 0, 14)
		disc_mi.position = Vector3(1.3, 1.0, 0.4)
		root.add_child(disc_mi)
		_slots.append({
			"root": root, "case_mat": case_mat, "disc_mat": disc_mat,
			"game_idx": -1, "target_pos": Vector3.ZERO,
			"target_rot": 0.0, "target_scale": 1.0,
		})

	_build_hud()


func _build_hud() -> void:
	var hud := CanvasLayer.new()
	add_child(hud)
	var sys := Label.new()
	sys.text = _system.to_upper()
	sys.position = Vector2(24, 16)
	sys.add_theme_font_size_override("font_size", 28)
	sys.add_theme_color_override("font_color", Color(0.55, 0.9, 1.0))
	hud.add_child(sys)
	var count := Label.new()
	count.name = "CountLabel"
	count.position = Vector2(24, 52)
	count.add_theme_font_size_override("font_size", 18)
	count.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	hud.add_child(count)
	var hint := Label.new()
	hint.text = "D-PAD browse    A launch    B back"
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.position = Vector2(-260, -48)
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", Color(0.55, 0.6, 0.72))
	hud.add_child(hint)


func set_selection(idx: int, instant := false) -> void:
	_selected = clampi(idx, 0, _games.size() - 1)
	for s in POOL_SIZE:
		var slot: Dictionary = _slots[s]
		var gi := _selected + s - POOL_SIZE / 2
		slot["game_idx"] = gi
		var root: Node3D = slot["root"]
		var valid := gi >= 0 and gi < _games.size()
		root.visible = valid
		if not valid:
			continue
		var entry: Dictionary = _games[gi]
		var o := float(s - POOL_SIZE / 2)
		slot["target_pos"] = Vector3(o * SLOT_SPACING, 0.0, absf(o) * 1.4)
		slot["target_rot"] = -o * 0.30
		slot["target_scale"] = 1.30 if o == 0.0 else 1.0
		if instant:
			root.position = slot["target_pos"]
			root.rotation.y = slot["target_rot"]
			var sc: float = slot["target_scale"]
			root.scale = Vector3.ONE * sc
		_request_slot_textures(s, entry, o == 0.0)
	_update_chrome()
	_save_selection()


func _request_slot_textures(s: int, entry: Dictionary, is_selected: bool) -> void:
	var slot: Dictionary = _slots[s]
	var key_base: String = "%s/%s" % [str(entry.get("platform", "")), str(entry.get("gameId", ""))]
	if CrystalData.has_slot(entry, "front"):
		var key := "case:" + key_base
		TextureCache.request(key, CrystalData.media_path(entry, "front"), TEX_THUMB,
			func(_k: String, tex: Texture2D) -> void:
				if tex != null and is_instance_valid(slot["case_mat"]):
					(slot["case_mat"] as StandardMaterial3D).albedo_texture = tex)
	if CrystalData.has_slot(entry, "media"):
		var key := "disc:" + key_base
		TextureCache.request(key, CrystalData.media_path(entry, "media"), TEX_THUMB,
			func(_k: String, tex: Texture2D) -> void:
				if tex != null and is_instance_valid(slot["disc_mat"]):
					(slot["disc_mat"] as StandardMaterial3D).albedo_texture = tex)
	if is_selected:
		if CrystalData.has_slot(entry, "logo"):
			TextureCache.request("logo:" + key_base, CrystalData.media_path(entry, "logo"),
				TEX_HERO, _on_logo_ready.bind(key_base))
		else:
			_logo_target_alpha = 0.0
		if CrystalData.has_slot(entry, "screenshot"):
			_set_background(CrystalData.media_path(entry, "screenshot"))


func _on_logo_ready(key: String, tex: Texture2D, _bound_base: String) -> void:
	if tex == null or not is_instance_valid(_logo):
		return
	_logo.texture = tex
	var aspect := float(tex.get_width()) / maxf(1.0, float(tex.get_height()))
	_logo.scale = Vector3(aspect, 1.0, 1.0)
	_logo_target_alpha = 1.0


func _set_background(path: String) -> void:
	var back_idx := 1 - _bg_front
	var back_mat: StandardMaterial3D = _bg_mats[back_idx]
	TextureCache.request("bg:" + path, path, TEX_HERO,
		func(_k: String, tex: Texture2D) -> void:
			if tex == null or not is_instance_valid(back_mat):
				return
			back_mat.albedo_texture = tex
			back_mat.albedo_color.a = 0.0
			_bg_fade = 0.0
			_bg_front = back_idx)


func _update_chrome() -> void:
	var entry: Dictionary = _games[_selected]
	_title_label.text = str(entry.get("title", ""))
	var hud := get_node_or_null("CanvasLayer")
	if hud != null:
		var count: Label = hud.get_node_or_null("CountLabel")
		if count != null:
			count.text = "%d / %d" % [_selected + 1, _games.size()]


func _process(delta: float) -> void:
	if not _initialized:
		return
	_time += delta
	_move_cd = maxf(0.0, _move_cd - delta)

	if _launch_t >= 0.0:
		_launch_t += delta
		var k := clampf(_launch_t / 0.35, 0.0, 1.0)
		var slot: Dictionary = _slots[POOL_SIZE / 2]
		var root: Node3D = slot["root"]
		var tp: Vector3 = slot["target_pos"]
		root.position = Vector3(tp.x, tp.y, lerpf(tp.z, tp.z - 2.6, k))
		var sc := lerpf(float(slot["target_scale"]), 1.65, k)
		root.scale = Vector3.ONE * sc
		if _launch_t >= 0.40:
			_launch_t = -1.0
			_fire_launch()
		return

	if _move_cd <= 0.0:
		if Input.is_action_just_pressed("move_right"):
			if _selected < _games.size() - 1:
				set_selection(_selected + 1)
				_move_cd = MOVE_COOLDOWN
		elif Input.is_action_just_pressed("move_left"):
			if _selected > 0:
				set_selection(_selected - 1)
				_move_cd = MOVE_COOLDOWN
	if Input.is_action_just_pressed("confirm"):
		_launch_t = 0.0
		return

	var ease := minf(1.0, delta * 10.0)
	for s in POOL_SIZE:
		var slot: Dictionary = _slots[s]
		var root: Node3D = slot["root"]
		if not root.visible:
			continue
		var tp: Vector3 = slot["target_pos"]
		root.position = root.position.lerp(tp, ease)
		root.rotation.y = lerpf(root.rotation.y, float(slot["target_rot"]), ease)
		var ts := float(slot["target_scale"])
		root.scale = Vector3.ONE * lerpf(root.scale.x, ts, ease)

	# Camera parallax toward the focused slot.
	var mid: Dictionary = _slots[POOL_SIZE / 2]
	var mid_root: Node3D = mid["root"]
	if mid_root.visible:
		_cam.position.x = lerpf(_cam.position.x, mid_root.position.x * 0.22, minf(1.0, delta * 5.0))

	# Logo bob + fade.
	if is_instance_valid(_logo):
		_logo.position.y = 3.35 + sin(_time * 1.7) * 0.07
		var a := _logo.modulate.a
		_logo.modulate.a = lerpf(a, _logo_target_alpha, minf(1.0, delta * 6.0))

	# Background crossfade.
	if _bg_fade < 1.0:
		_bg_fade = minf(1.0, _bg_fade + delta * 1.4)
		var front_mat: StandardMaterial3D = _bg_mats[_bg_front]
		var back_mat: StandardMaterial3D = _bg_mats[1 - _bg_front]
		front_mat.albedo_color.a = _bg_fade * 0.55
		back_mat.albedo_color.a = (1.0 - _bg_fade) * 0.55


func _fire_launch() -> void:
	var entry: Dictionary = _games[_selected]
	var profile: Dictionary = CrystalData.profile_for(_system)
	CrystalPlugin.launch_game(profile, CrystalData.rom_path(entry))


func _on_launch_failed(message: String) -> void:
	Navigator.open("res://scenes/failure_screen.tscn", {"message": message})


func _save_selection() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("carousel", "system", _system)
	cfg.set_value("carousel", "index", _selected)
	cfg.save(SAVE_PATH)


func _load_selection() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		_selected = int(cfg.get_value("carousel", "index", 0))
