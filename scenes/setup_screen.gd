extends CanvasLayer
## SetupScreen — first-launch SAF grant acquisition (Android only).
##
## The launcher is a separate app from the Manager and does not inherit the
## Manager's storage permission; raw /storage paths are unusable under
## scoped storage. This screen presents the one-time system folder picker
## ("SELECT CRYSTAL DATA FOLDER"). The plugin persists the grant and the
## user is never asked again (unless the grant is revoked or the SD card
## changes, in which case this screen simply reappears).

var _status: Label
var _button: Button


func _ready() -> void:
	_build_ui()
	CrystalPlugin.data_access_granted.connect(_on_granted)
	CrystalPlugin.data_access_cancelled.connect(_on_cancelled)


func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.09, 0.97)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 28)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(box)

	var title := Label.new()
	title.text = "CRYSTAL LAUNCHER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(0.55, 0.9, 1.0))
	box.add_child(title)

	var prompt := Label.new()
	prompt.text = "SELECT CRYSTAL DATA FOLDER"
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_font_size_override("font_size", 26)
	prompt.add_theme_color_override("font_color", Color(0.92, 0.94, 0.98))
	box.add_child(prompt)

	var body := Label.new()
	body.text = "Crystal Launcher needs access to the library folder created by Crystal Nova Manager (config.json, index.json and artwork).\n\nThis is a one-time step — the permission is kept, and you won't be asked again.\n\nIn the picker, choose the crystal-nova-data folder on your SD card."
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(640, 0)
	body.add_theme_font_size_override("font_size", 20)
	body.add_theme_color_override("font_color", Color(0.75, 0.8, 0.9))
	box.add_child(body)

	_button = Button.new()
	_button.text = "SELECT FOLDER"
	_button.custom_minimum_size = Vector2(340, 76)
	_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_button.add_theme_font_size_override("font_size", 24)
	_button.pressed.connect(_on_select_pressed)
	box.add_child(_button)

	_status = Label.new()
	_status.text = ""
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(640, 0)
	_status.add_theme_font_size_override("font_size", 18)
	_status.add_theme_color_override("font_color", Color(1.0, 0.75, 0.4))
	box.add_child(_status)

	_button.grab_focus()


func _on_select_pressed() -> void:
	_status.text = "Waiting for the Android folder picker…"
	CrystalPlugin.request_data_access()


func _on_granted(_tree_uri: String) -> void:
	if CrystalData.enable_saf():
		Navigator.replace("res://scenes/game_carousel.tscn")
	else:
		_status.text = "That folder doesn't contain config.json. Please select the crystal-nova-data folder and try again."
		_button.grab_focus()


func _on_cancelled() -> void:
	_status.text = "Folder access is required to load your library. Press SELECT FOLDER to try again."
	_button.grab_focus()
