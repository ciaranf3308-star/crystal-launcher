extends CanvasLayer
## FailureScreen — honest failure surface. Shows what went wrong and how to
## get back. Used for: bad config/index, empty library, launch failures.

var _message := "Something went wrong."
var _fatal := false


func setup(params: Dictionary) -> void:
	_message = str(params.get("message", _message))
	_fatal = bool(params.get("fatal", false))


func _ready() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.09, 0.93)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var title := Label.new()
	title.text = "CRYSTAL LAUNCHER"
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.position = Vector2(-200, 120)
	title.size = Vector2(400, 48)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(0.55, 0.9, 1.0))
	add_child(title)

	var msg := Label.new()
	msg.text = _message
	msg.set_anchors_preset(Control.PRESET_CENTER)
	msg.position = Vector2(-420, -60)
	msg.size = Vector2(840, 200)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.add_theme_font_size_override("font_size", 22)
	msg.add_theme_color_override("font_color", Color(0.92, 0.94, 0.98))
	add_child(msg)

	var hint := Label.new()
	hint.text = "Close and restart the app." if _fatal else "Press B / Esc to go back."
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.position = Vector2(-260, -80)
	hint.size = Vector2(520, 40)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", Color(0.55, 0.6, 0.72))
	add_child(hint)


func _process(_delta: float) -> void:
	if not _fatal and Input.is_action_just_pressed("back"):
		Navigator.back()
