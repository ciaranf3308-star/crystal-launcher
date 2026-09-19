extends Node
## InputSetup — triple-redundant controller-first input map.
##
## Every logical action binds: (1) a keyboard key (dev fallback),
## (2) an any-device joypad button (device = -1, NEVER a hardcoded
## controller id), (3) where sensible, the Android dpad keycodes.
## Game code polls Input.is_action_pressed / is_action_just_pressed.

const ACTIONS := {
	"move_left": {
		"keys": [KEY_LEFT, KEY_A],
		"joy": [JOY_BUTTON_DPAD_LEFT],
	},
	"move_right": {
		"keys": [KEY_RIGHT, KEY_D],
		"joy": [JOY_BUTTON_DPAD_RIGHT],
	},
	"move_up": {
		"keys": [KEY_UP, KEY_W],
		"joy": [JOY_BUTTON_DPAD_UP],
	},
	"move_down": {
		"keys": [KEY_DOWN, KEY_S],
		"joy": [JOY_BUTTON_DPAD_DOWN],
	},
	"confirm": {
		"keys": [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE],
		"joy": [JOY_BUTTON_A],
	},
	"back": {
		"keys": [KEY_ESCAPE, KEY_BACKSPACE],
		"joy": [JOY_BUTTON_B],
	},
	"shoulder_l": {
		"keys": [KEY_Q],
		"joy": [JOY_BUTTON_LEFT_SHOULDER],
	},
	"shoulder_r": {
		"keys": [KEY_E],
		"joy": [JOY_BUTTON_RIGHT_SHOULDER],
	},
	"start": {
		"keys": [KEY_TAB],
		"joy": [JOY_BUTTON_START],
	},
}


func _ready() -> void:
	apply()


func apply() -> void:
	for action: String in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var spec: Dictionary = ACTIONS[action]
		for keycode: int in spec.get("keys", []):
			var ev := InputEventKey.new()
			ev.physical_keycode = keycode as Key
			if not _has_event(action, ev):
				InputMap.action_add_event(action, ev)
		for button: int in spec.get("joy", []):
			var jev := InputEventJoypadButton.new()
			jev.device = -1  # any controller
			jev.button_index = button as JoyButton
			if not _has_event(action, jev):
				InputMap.action_add_event(action, jev)


func _has_event(action: String, candidate: InputEvent) -> bool:
	for existing: InputEvent in InputMap.action_get_events(action):
		if existing.get_class() != candidate.get_class():
			continue
		if existing is InputEventKey and candidate is InputEventKey:
			if existing.physical_keycode == candidate.physical_keycode:
				return true
		elif existing is InputEventJoypadButton and candidate is InputEventJoypadButton:
			if existing.button_index == candidate.button_index and existing.device == candidate.device:
				return true
	return false


## Hold-to-repeat helper for shoulders / fast scrolling.
static func repeat_pressed(action: String, node: Node, state_key: String) -> bool:
	if Input.is_action_just_pressed(action):
		node.set(state_key, 0.0)
		return true
	if Input.is_action_pressed(action):
		var t: float = float(node.get(state_key)) + node.get_process_delta_time()
		node.set(state_key, t)
		if t > 0.45 and fmod(t, 0.12) < node.get_process_delta_time():
			return true
	return false
