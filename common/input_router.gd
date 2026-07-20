extends Node
## Defines semantic controls and exposes normalized keyboard/gamepad state.

signal device_changed(using_gamepad: bool)
signal input_mode_changed(mode: StringName)
signal bindings_changed(actions: Array[StringName])

const INPUT_MODE_KEYBOARD_MOUSE: StringName = &"KEYBOARD_MOUSE"
const INPUT_MODE_GAMEPAD: StringName = &"GAMEPAD"
const INPUT_MODE_TOUCH: StringName = &"TOUCH"
const INPUT_MODE_ANY: StringName = &"ANY"
const MOUSE_AFTER_TOUCH_GUARD_USEC: int = 850_000

const THROTTLE: StringName = &"throttle"
const BRAKE: StringName = &"brake"
const STEER_LEFT: StringName = &"steer_left"
const STEER_RIGHT: StringName = &"steer_right"
const LEAN_FORWARD: StringName = &"lean_forward"
const LEAN_BACK: StringName = &"lean_back"
const PRELOAD: StringName = &"preload"
const FLOW_BOOST: StringName = &"flow_boost"
const RACECRAFT: StringName = &"racecraft_technique"
const RESET_BIKE: StringName = &"reset_bike"
const RESTART_RUN: StringName = &"restart_run"
const PAUSE: StringName = &"pause_game"
const GARAGE_LEFT: StringName = &"garage_left"
const GARAGE_RIGHT: StringName = &"garage_right"
const CONFIRM: StringName = &"confirm_selection"
const OPEN_GARAGE: StringName = &"open_garage"
const OPEN_WORKSHOP: StringName = &"open_workshop"
const CONTINUE_WEEKEND: StringName = &"continue_weekend"
const EVENT_PREVIOUS: StringName = &"event_previous"
const EVENT_NEXT: StringName = &"event_next"
const REPAIR_BIKE: StringName = &"repair_bike"
const TOGGLE_ASSIST: StringName = &"toggle_assist"
const OPEN_SETTINGS: StringName = &"open_settings"
const TOGGLE_REPLAY: StringName = &"toggle_replay"
const TOGGLE_PHOTO_MODE: StringName = &"toggle_photo_mode"
const SPECTATOR_NEXT: StringName = &"spectator_next"
const MENU_LEFT: StringName = &"menu_left"
const MENU_RIGHT: StringName = &"menu_right"
const PAGE_PREVIOUS: StringName = &"page_previous"
const PAGE_NEXT: StringName = &"page_next"
const RESET_SETTING: StringName = &"reset_setting"
const RESET_ALL_SETTINGS: StringName = &"reset_all_settings"
const RESULTS_FIRST: StringName = &"results_first"
const RESULTS_LAST: StringName = &"results_last"
const PHOTO_FORWARD: StringName = &"photo_forward"
const PHOTO_BACK: StringName = &"photo_back"
const PHOTO_LEFT: StringName = &"photo_left"
const PHOTO_RIGHT: StringName = &"photo_right"
const PHOTO_DOWN: StringName = &"photo_down"
const PHOTO_UP: StringName = &"photo_up"
const PHOTO_LOOK_LEFT: StringName = &"photo_look_left"
const PHOTO_LOOK_RIGHT: StringName = &"photo_look_right"
const PHOTO_LOOK_UP: StringName = &"photo_look_up"
const PHOTO_LOOK_DOWN: StringName = &"photo_look_down"

const CONTEXT_GLOBAL: StringName = &"GLOBAL"
const CONTEXT_RIDE: StringName = &"RIDE"
const CONTEXT_GARAGE: StringName = &"GARAGE"
const CONTEXT_WORKSHOP: StringName = &"WORKSHOP"
const CONTEXT_RESULTS: StringName = &"RESULTS"
const CONTEXT_SETTINGS: StringName = &"SETTINGS"
const CONTEXT_REPLAY: StringName = &"REPLAY"
const CONTEXT_PHOTO: StringName = &"PHOTO"

const ACTION_CONTEXTS: Dictionary = {
	THROTTLE: [CONTEXT_RIDE],
	BRAKE: [CONTEXT_RIDE],
	STEER_LEFT: [CONTEXT_RIDE],
	STEER_RIGHT: [CONTEXT_RIDE],
	LEAN_FORWARD: [CONTEXT_RIDE],
	LEAN_BACK: [CONTEXT_RIDE],
	PRELOAD: [CONTEXT_RIDE],
	FLOW_BOOST: [CONTEXT_RIDE],
	RACECRAFT: [CONTEXT_RIDE],
	RESET_BIKE: [CONTEXT_RIDE],
	RESTART_RUN: [CONTEXT_RIDE, CONTEXT_RESULTS, CONTEXT_REPLAY],
	PAUSE: [CONTEXT_GLOBAL],
	GARAGE_LEFT: [CONTEXT_GARAGE, CONTEXT_WORKSHOP],
	GARAGE_RIGHT: [CONTEXT_GARAGE, CONTEXT_WORKSHOP],
	CONFIRM: [CONTEXT_GARAGE, CONTEXT_WORKSHOP, CONTEXT_SETTINGS],
	OPEN_GARAGE: [CONTEXT_RIDE, CONTEXT_RESULTS, CONTEXT_REPLAY, CONTEXT_WORKSHOP],
	OPEN_WORKSHOP: [CONTEXT_GARAGE, CONTEXT_WORKSHOP],
	CONTINUE_WEEKEND: [CONTEXT_GARAGE],
	EVENT_PREVIOUS: [CONTEXT_GARAGE, CONTEXT_WORKSHOP, CONTEXT_RESULTS, CONTEXT_SETTINGS],
	EVENT_NEXT: [CONTEXT_GARAGE, CONTEXT_WORKSHOP, CONTEXT_RESULTS, CONTEXT_SETTINGS],
	REPAIR_BIKE: [CONTEXT_GARAGE, CONTEXT_WORKSHOP],
	TOGGLE_ASSIST: [CONTEXT_GARAGE],
	OPEN_SETTINGS: [CONTEXT_GLOBAL],
	TOGGLE_REPLAY: [CONTEXT_RESULTS, CONTEXT_REPLAY, CONTEXT_PHOTO],
	TOGGLE_PHOTO_MODE: [CONTEXT_RIDE, CONTEXT_RESULTS, CONTEXT_REPLAY, CONTEXT_PHOTO],
	SPECTATOR_NEXT: [CONTEXT_REPLAY, CONTEXT_PHOTO],
	MENU_LEFT: [CONTEXT_SETTINGS],
	MENU_RIGHT: [CONTEXT_SETTINGS],
	PAGE_PREVIOUS: [CONTEXT_RESULTS, CONTEXT_SETTINGS],
	PAGE_NEXT: [CONTEXT_RESULTS, CONTEXT_SETTINGS],
	RESET_SETTING: [CONTEXT_SETTINGS],
	RESET_ALL_SETTINGS: [CONTEXT_SETTINGS],
	RESULTS_FIRST: [CONTEXT_RESULTS],
	RESULTS_LAST: [CONTEXT_RESULTS],
	PHOTO_FORWARD: [CONTEXT_PHOTO],
	PHOTO_BACK: [CONTEXT_PHOTO],
	PHOTO_LEFT: [CONTEXT_PHOTO],
	PHOTO_RIGHT: [CONTEXT_PHOTO],
	PHOTO_DOWN: [CONTEXT_PHOTO],
	PHOTO_UP: [CONTEXT_PHOTO],
	PHOTO_LOOK_LEFT: [CONTEXT_PHOTO],
	PHOTO_LOOK_RIGHT: [CONTEXT_PHOTO],
	PHOTO_LOOK_UP: [CONTEXT_PHOTO],
	PHOTO_LOOK_DOWN: [CONTEXT_PHOTO],
}

var using_gamepad: bool = false
var using_touch: bool = false
var input_mode: StringName = INPUT_MODE_KEYBOARD_MOUSE
var binding_revision: int = 0
var _last_touch_input_usec: int = -MOUSE_AFTER_TOUCH_GUARD_USEC
var steering_deadzone: float = 0.12
var throttle_deadzone: float = 0.05
var brake_deadzone: float = 0.05
var steering_sensitivity: float = 1.0
var steering_curve: float = 1.35


func _ready() -> void:
	_register_actions()


func _input(event: InputEvent) -> void:
	var next_mode := input_mode
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		_last_touch_input_usec = Time.get_ticks_usec()
		next_mode = INPUT_MODE_TOUCH
	elif event is InputEventJoypadButton:
		if not (event as InputEventJoypadButton).pressed:
			return
		next_mode = INPUT_MODE_GAMEPAD
	elif event is InputEventJoypadMotion:
		# Ignore ordinary stick drift so a dormant controller cannot replace the
		# prompts while the rider is actively using keyboard or mouse.
		var motion := event as InputEventJoypadMotion
		var is_trigger := motion.axis in [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]
		var intentional_motion := motion.axis_value >= 0.35 if is_trigger else absf(motion.axis_value) >= 0.35
		if not intentional_motion:
			return
		next_mode = INPUT_MODE_GAMEPAD
	elif event is InputEventKey:
		if not (event as InputEventKey).pressed or (event as InputEventKey).echo:
			return
		next_mode = INPUT_MODE_KEYBOARD_MOUSE
	elif event is InputEventMouse:
		# Browsers and mobile platforms may synthesize a mouse event immediately
		# after each screen touch. Keep TOUCH authoritative through that companion
		# event while allowing a real mouse to take over after a short idle window.
		if event is InputEventMouse and Time.get_ticks_usec() - _last_touch_input_usec <= MOUSE_AFTER_TOUCH_GUARD_USEC:
			return
		next_mode = INPUT_MODE_KEYBOARD_MOUSE
	_set_input_mode(next_mode)


func note_touch_input() -> void:
	## Virtual controls inject semantic InputEventAction instances after the raw
	## screen event. Keep the originating device explicit so action injection can
	## never make the HUD fall back to keyboard prompts.
	_last_touch_input_usec = Time.get_ticks_usec()
	_set_input_mode(INPUT_MODE_TOUCH)


func _set_input_mode(next_mode: StringName) -> void:
	if next_mode == input_mode:
		return
	var previously_using_gamepad := using_gamepad
	input_mode = next_mode
	using_gamepad = input_mode == INPUT_MODE_GAMEPAD
	using_touch = input_mode == INPUT_MODE_TOUCH
	if using_gamepad != previously_using_gamepad:
		device_changed.emit(using_gamepad)
	input_mode_changed.emit(input_mode)


func notify_bindings_changed(actions: Array[StringName] = []) -> void:
	## InputMap does not expose a mutation signal. Runtime rebinding owners call
	## this after a successful, fully-applied change so every teaching surface can
	## refresh even when the rider keeps using the same device family.
	binding_revision += 1
	bindings_changed.emit(actions.duplicate())


func get_action_contexts(action: StringName) -> Array[StringName]:
	var contexts: Array[StringName] = []
	var raw_contexts: Variant = ACTION_CONTEXTS.get(action, [])
	if raw_contexts is Array:
		for raw_context: Variant in raw_contexts:
			contexts.append(StringName(raw_context))
	return contexts


func actions_share_context(first: StringName, second: StringName) -> bool:
	if first == second:
		return true
	var first_contexts := get_action_contexts(first)
	var second_contexts := get_action_contexts(second)
	# Unknown actions remain globally conflict-safe instead of silently allowing a
	# duplicate that a future consumer might activate beside a known action.
	if first_contexts.is_empty() or second_contexts.is_empty():
		return true
	if CONTEXT_GLOBAL in first_contexts or CONTEXT_GLOBAL in second_contexts:
		return true
	for context: StringName in first_contexts:
		if context in second_contexts:
			return true
	return false


func get_conflicting_actions(
	action: StringName,
	candidates: Array[StringName]
) -> Array[StringName]:
	var conflicts: Array[StringName] = []
	for candidate: StringName in candidates:
		if candidate != action and actions_share_context(action, candidate):
			conflicts.append(candidate)
	return conflicts


func get_action_label(
	action: StringName,
	mode: StringName = &"",
	max_labels: int = 1
) -> String:
	var requested_mode := input_mode if mode.is_empty() else mode
	if requested_mode == INPUT_MODE_TOUCH:
		return "TOUCH"
	if requested_mode == INPUT_MODE_ANY:
		var keyboard_label := get_action_label(
			action, INPUT_MODE_KEYBOARD_MOUSE, max_labels
		)
		var gamepad_label := get_action_label(action, INPUT_MODE_GAMEPAD, max_labels)
		return _join_device_labels(keyboard_label, gamepad_label)
	var labels := PackedStringArray()
	for event: InputEvent in InputMap.action_get_events(action):
		if not _event_matches_mode(event, requested_mode):
			continue
		var label := format_binding_event(event)
		if label.is_empty() or labels.has(label):
			continue
		labels.append(label)
		if max_labels > 0 and labels.size() >= max_labels:
			break
	return "UNBOUND" if labels.is_empty() else " / ".join(labels)


func get_action_pair_label(
	negative_action: StringName,
	positive_action: StringName,
	mode: StringName = &"",
	max_labels_per_action: int = 1
) -> String:
	var requested_mode := input_mode if mode.is_empty() else mode
	if requested_mode == INPUT_MODE_TOUCH:
		return "TOUCH"
	if requested_mode == INPUT_MODE_ANY:
		var keyboard_label := get_action_pair_label(
			negative_action, positive_action, INPUT_MODE_KEYBOARD_MOUSE, max_labels_per_action
		)
		var gamepad_label := get_action_pair_label(
			negative_action, positive_action, INPUT_MODE_GAMEPAD, max_labels_per_action
		)
		return _join_device_labels(keyboard_label, gamepad_label)
	var collapsed := _collapsed_pair_label(negative_action, positive_action, requested_mode)
	if not collapsed.is_empty():
		return collapsed
	var negative_label := get_action_label(negative_action, requested_mode, max_labels_per_action)
	var positive_label := get_action_label(positive_action, requested_mode, max_labels_per_action)
	if negative_label == positive_label:
		return negative_label
	return "%s / %s" % [negative_label, positive_label]


func format_binding_event(event: InputEvent) -> String:
	if event is InputEventKey:
		return _format_key_event(event as InputEventKey)
	if event is InputEventMouseButton:
		return _format_mouse_event(event as InputEventMouseButton)
	if event is InputEventJoypadButton:
		return _joy_button_label((event as InputEventJoypadButton).button_index)
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		return _joy_axis_label(motion.axis, motion.axis_value)
	return event.as_text().to_upper()


func _event_matches_mode(event: InputEvent, mode: StringName) -> bool:
	if mode == INPUT_MODE_ANY:
		return (
			event is InputEventKey
			or event is InputEventMouseButton
			or event is InputEventJoypadButton
			or event is InputEventJoypadMotion
		)
	if mode == INPUT_MODE_GAMEPAD:
		return event is InputEventJoypadButton or event is InputEventJoypadMotion
	return event is InputEventKey or event is InputEventMouseButton


func _collapsed_pair_label(
	negative_action: StringName,
	positive_action: StringName,
	mode: StringName
) -> String:
	if mode != INPUT_MODE_GAMEPAD:
		return ""
	for negative_event: InputEvent in InputMap.action_get_events(negative_action):
		if not _event_matches_mode(negative_event, mode):
			continue
		for positive_event: InputEvent in InputMap.action_get_events(positive_action):
			if negative_event is InputEventJoypadMotion and positive_event is InputEventJoypadMotion:
				var negative_motion := negative_event as InputEventJoypadMotion
				var positive_motion := positive_event as InputEventJoypadMotion
				if (
					negative_motion.axis == positive_motion.axis
					and signf(negative_motion.axis_value) == -signf(positive_motion.axis_value)
				):
					return _joy_axis_group_label(negative_motion.axis)
			elif negative_event is InputEventJoypadButton and positive_event is InputEventJoypadButton:
				var negative_button := (negative_event as InputEventJoypadButton).button_index
				var positive_button := (positive_event as InputEventJoypadButton).button_index
				if (
					[negative_button, positive_button] == [JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT]
					or [negative_button, positive_button] == [JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN]
				):
					return "DPAD"
	return ""


func _join_device_labels(first: String, second: String) -> String:
	if first == "UNBOUND":
		return second
	if second == "UNBOUND":
		return first
	if first == second:
		return first
	return "%s / %s" % [first, second]


func _format_key_event(event: InputEventKey) -> String:
	var keycode: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
	var key_label := OS.get_keycode_string(keycode).to_upper()
	if key_label.is_empty():
		key_label = event.as_text().replace(" (Physical)", "").to_upper()
	if key_label == "ESCAPE":
		key_label = "ESC"
	var parts := PackedStringArray()
	if event.ctrl_pressed and keycode != KEY_CTRL:
		parts.append("CTRL")
	if event.alt_pressed and keycode != KEY_ALT:
		parts.append("ALT")
	if event.shift_pressed and keycode != KEY_SHIFT:
		parts.append("SHIFT")
	if event.meta_pressed and keycode != KEY_META:
		parts.append("META")
	parts.append(key_label)
	return " + ".join(parts)


func _format_mouse_event(event: InputEventMouseButton) -> String:
	var label := "MOUSE %d" % int(event.button_index)
	match event.button_index:
		MOUSE_BUTTON_LEFT: label = "LMB"
		MOUSE_BUTTON_RIGHT: label = "RMB"
		MOUSE_BUTTON_MIDDLE: label = "MMB"
		MOUSE_BUTTON_WHEEL_UP: label = "WHEEL UP"
		MOUSE_BUTTON_WHEEL_DOWN: label = "WHEEL DOWN"
		MOUSE_BUTTON_WHEEL_LEFT: label = "WHEEL LEFT"
		MOUSE_BUTTON_WHEEL_RIGHT: label = "WHEEL RIGHT"
		MOUSE_BUTTON_XBUTTON1: label = "MOUSE 4"
		MOUSE_BUTTON_XBUTTON2: label = "MOUSE 5"
	var parts := PackedStringArray()
	if event.ctrl_pressed:
		parts.append("CTRL")
	if event.alt_pressed:
		parts.append("ALT")
	if event.shift_pressed:
		parts.append("SHIFT")
	if event.meta_pressed:
		parts.append("META")
	parts.append(label)
	return " + ".join(parts)


func _joy_button_label(button_index: JoyButton) -> String:
	match button_index:
		JOY_BUTTON_A: return "A"
		JOY_BUTTON_B: return "B"
		JOY_BUTTON_X: return "X"
		JOY_BUTTON_Y: return "Y"
		JOY_BUTTON_BACK: return "BACK"
		JOY_BUTTON_GUIDE: return "GUIDE"
		JOY_BUTTON_START: return "START"
		JOY_BUTTON_LEFT_STICK: return "LS CLICK"
		JOY_BUTTON_RIGHT_STICK: return "RS CLICK"
		JOY_BUTTON_LEFT_SHOULDER: return "LB"
		JOY_BUTTON_RIGHT_SHOULDER: return "RB"
		JOY_BUTTON_DPAD_UP: return "DPAD UP"
		JOY_BUTTON_DPAD_DOWN: return "DPAD DOWN"
		JOY_BUTTON_DPAD_LEFT: return "DPAD LEFT"
		JOY_BUTTON_DPAD_RIGHT: return "DPAD RIGHT"
		_: return "PAD %d" % int(button_index)


func _joy_axis_label(axis: JoyAxis, value: float) -> String:
	var direction := -1.0 if value < 0.0 else 1.0
	match axis:
		JOY_AXIS_LEFT_X: return "LS LEFT" if direction < 0.0 else "LS RIGHT"
		JOY_AXIS_LEFT_Y: return "LS UP" if direction < 0.0 else "LS DOWN"
		JOY_AXIS_RIGHT_X: return "RS LEFT" if direction < 0.0 else "RS RIGHT"
		JOY_AXIS_RIGHT_Y: return "RS UP" if direction < 0.0 else "RS DOWN"
		JOY_AXIS_TRIGGER_LEFT: return "LT"
		JOY_AXIS_TRIGGER_RIGHT: return "RT"
		_: return "PAD AXIS %d %s" % [int(axis), "-" if direction < 0.0 else "+"]


func _joy_axis_group_label(axis: JoyAxis) -> String:
	match axis:
		JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y: return "LS"
		JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y: return "RS"
		_: return "PAD AXIS %d" % int(axis)


func get_throttle() -> float:
	return _shape_trigger(Input.get_action_strength(THROTTLE), throttle_deadzone)


func get_brake() -> float:
	return _shape_trigger(Input.get_action_strength(BRAKE), brake_deadzone)


func get_steer() -> float:
	var raw := Input.get_axis(STEER_LEFT, STEER_RIGHT)
	var magnitude := _shape_trigger(absf(raw), steering_deadzone)
	return signf(raw) * clampf(pow(magnitude, steering_curve) * steering_sensitivity, 0.0, 1.0)


func configure_controls(values: Dictionary) -> void:
	steering_deadzone = clampf(float(values.get("steering_deadzone", steering_deadzone)), 0.0, 0.5)
	throttle_deadzone = clampf(float(values.get("throttle_deadzone", throttle_deadzone)), 0.0, 0.5)
	brake_deadzone = clampf(float(values.get("brake_deadzone", brake_deadzone)), 0.0, 0.5)
	steering_sensitivity = clampf(float(values.get("steering_sensitivity", steering_sensitivity)), 0.25, 3.0)
	steering_curve = clampf(float(values.get("steering_curve", steering_curve)), 0.5, 3.0)
	InputMap.action_set_deadzone(STEER_LEFT, steering_deadzone)
	InputMap.action_set_deadzone(STEER_RIGHT, steering_deadzone)
	InputMap.action_set_deadzone(THROTTLE, throttle_deadzone)
	InputMap.action_set_deadzone(BRAKE, brake_deadzone)


func get_lean() -> float:
	return Input.get_axis(LEAN_FORWARD, LEAN_BACK)


func is_preload_pressed() -> bool:
	return Input.is_action_pressed(PRELOAD)


func is_preload_just_released() -> bool:
	return Input.is_action_just_released(PRELOAD)


func is_flow_boost_just_pressed() -> bool:
	return Input.is_action_just_pressed(FLOW_BOOST)


func is_flow_boost_pressed() -> bool:
	return Input.is_action_pressed(FLOW_BOOST)


func is_racecraft_just_pressed() -> bool:
	return Input.is_action_just_pressed(RACECRAFT)


func is_racecraft_pressed() -> bool:
	return Input.is_action_pressed(RACECRAFT)


func _register_actions() -> void:
	_add_key(THROTTLE, KEY_W)
	_add_axis(THROTTLE, JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_add_key(BRAKE, KEY_S)
	_add_axis(BRAKE, JOY_AXIS_TRIGGER_LEFT, 1.0)

	_add_key(STEER_LEFT, KEY_A)
	_add_axis(STEER_LEFT, JOY_AXIS_LEFT_X, -1.0)
	_add_key(STEER_RIGHT, KEY_D)
	_add_axis(STEER_RIGHT, JOY_AXIS_LEFT_X, 1.0)

	_add_key(LEAN_FORWARD, KEY_UP)
	_add_axis(LEAN_FORWARD, JOY_AXIS_RIGHT_Y, -1.0)
	_add_key(LEAN_BACK, KEY_DOWN)
	_add_axis(LEAN_BACK, JOY_AXIS_RIGHT_Y, 1.0)

	_add_key(PRELOAD, KEY_SPACE)
	_add_button(PRELOAD, JOY_BUTTON_A)
	_add_key(FLOW_BOOST, KEY_SHIFT)
	_add_button(FLOW_BOOST, JOY_BUTTON_LEFT_SHOULDER)
	_add_key(RACECRAFT, KEY_C)
	_add_button(RACECRAFT, JOY_BUTTON_RIGHT_SHOULDER)
	_add_key(RESET_BIKE, KEY_R)
	_add_button(RESET_BIKE, JOY_BUTTON_Y)
	_add_key(RESTART_RUN, KEY_ENTER)
	_add_button(RESTART_RUN, JOY_BUTTON_X)
	_add_key(PAUSE, KEY_ESCAPE)
	_add_button(PAUSE, JOY_BUTTON_START)
	_add_key(GARAGE_LEFT, KEY_Q)
	_add_key(GARAGE_LEFT, KEY_LEFT)
	_add_button(GARAGE_LEFT, JOY_BUTTON_DPAD_LEFT)
	_add_key(GARAGE_RIGHT, KEY_E)
	_add_key(GARAGE_RIGHT, KEY_RIGHT)
	_add_button(GARAGE_RIGHT, JOY_BUTTON_DPAD_RIGHT)
	_add_key(CONFIRM, KEY_ENTER)
	_add_button(CONFIRM, JOY_BUTTON_A)
	_add_key(OPEN_GARAGE, KEY_G)
	_add_button(OPEN_GARAGE, JOY_BUTTON_B)
	_add_key(OPEN_WORKSHOP, KEY_TAB)
	_add_button(OPEN_WORKSHOP, JOY_BUTTON_X)
	_add_key(CONTINUE_WEEKEND, KEY_C)
	_add_button(CONTINUE_WEEKEND, JOY_BUTTON_Y)
	_add_key(EVENT_PREVIOUS, KEY_W)
	_add_key(EVENT_PREVIOUS, KEY_UP)
	_add_button(EVENT_PREVIOUS, JOY_BUTTON_DPAD_UP)
	_add_key(EVENT_NEXT, KEY_S)
	_add_key(EVENT_NEXT, KEY_DOWN)
	_add_button(EVENT_NEXT, JOY_BUTTON_DPAD_DOWN)
	_add_key(REPAIR_BIKE, KEY_F)
	_add_button(REPAIR_BIKE, JOY_BUTTON_RIGHT_SHOULDER)
	_add_key(TOGGLE_ASSIST, KEY_H)
	_add_button(TOGGLE_ASSIST, JOY_BUTTON_LEFT_STICK)
	_add_key(OPEN_SETTINGS, KEY_F1)
	_add_button(OPEN_SETTINGS, JOY_BUTTON_BACK)
	_add_key(TOGGLE_REPLAY, KEY_V)
	# Results use D-pad Up/Down to inspect the classification. A is already a
	# contextual confirm/preload button, so RaceServices can own it only when an
	# exact replay is actually startable without stealing Garage or riding input.
	_add_button(TOGGLE_REPLAY, JOY_BUTTON_A)
	_add_key(TOGGLE_PHOTO_MODE, KEY_P)
	_add_button(TOGGLE_PHOTO_MODE, JOY_BUTTON_LEFT_STICK)
	_add_key(SPECTATOR_NEXT, KEY_TAB)
	_add_button(SPECTATOR_NEXT, JOY_BUTTON_RIGHT_STICK)
	_add_key(MENU_LEFT, KEY_LEFT)
	_add_button(MENU_LEFT, JOY_BUTTON_DPAD_LEFT)
	_add_key(MENU_RIGHT, KEY_RIGHT)
	_add_button(MENU_RIGHT, JOY_BUTTON_DPAD_RIGHT)
	_add_key(PAGE_PREVIOUS, KEY_Q)
	_add_key(PAGE_PREVIOUS, KEY_PAGEUP)
	_add_button(PAGE_PREVIOUS, JOY_BUTTON_LEFT_SHOULDER)
	_add_key(PAGE_NEXT, KEY_E)
	_add_key(PAGE_NEXT, KEY_PAGEDOWN)
	_add_key(PAGE_NEXT, KEY_TAB)
	_add_button(PAGE_NEXT, JOY_BUTTON_RIGHT_SHOULDER)
	_add_key(RESET_SETTING, KEY_DELETE)
	_add_key(RESET_SETTING, KEY_BACKSPACE)
	_add_button(RESET_SETTING, JOY_BUTTON_X)
	_add_key(RESET_ALL_SETTINGS, KEY_HOME)
	_add_button(RESET_ALL_SETTINGS, JOY_BUTTON_Y)
	_add_key(RESULTS_FIRST, KEY_HOME)
	_add_key(RESULTS_LAST, KEY_END)
	_add_key(PHOTO_FORWARD, KEY_W)
	_add_axis(PHOTO_FORWARD, JOY_AXIS_LEFT_Y, -1.0)
	_add_key(PHOTO_BACK, KEY_S)
	_add_axis(PHOTO_BACK, JOY_AXIS_LEFT_Y, 1.0)
	_add_key(PHOTO_LEFT, KEY_A)
	_add_axis(PHOTO_LEFT, JOY_AXIS_LEFT_X, -1.0)
	_add_key(PHOTO_RIGHT, KEY_D)
	_add_axis(PHOTO_RIGHT, JOY_AXIS_LEFT_X, 1.0)
	_add_key(PHOTO_DOWN, KEY_Q)
	_add_axis(PHOTO_DOWN, JOY_AXIS_TRIGGER_LEFT, 1.0)
	_add_key(PHOTO_UP, KEY_E)
	_add_axis(PHOTO_UP, JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_add_key(PHOTO_LOOK_LEFT, KEY_LEFT)
	_add_axis(PHOTO_LOOK_LEFT, JOY_AXIS_RIGHT_X, -1.0)
	_add_key(PHOTO_LOOK_RIGHT, KEY_RIGHT)
	_add_axis(PHOTO_LOOK_RIGHT, JOY_AXIS_RIGHT_X, 1.0)
	_add_key(PHOTO_LOOK_UP, KEY_UP)
	_add_axis(PHOTO_LOOK_UP, JOY_AXIS_RIGHT_Y, -1.0)
	_add_key(PHOTO_LOOK_DOWN, KEY_DOWN)
	_add_axis(PHOTO_LOOK_DOWN, JOY_AXIS_RIGHT_Y, 1.0)


func _ensure_action(action: StringName, deadzone: float = 0.2) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, deadzone)


func _add_key(action: StringName, physical_keycode: Key) -> void:
	_ensure_action(action)
	var input_event := InputEventKey.new()
	input_event.physical_keycode = physical_keycode
	InputMap.action_add_event(action, input_event)


func _add_button(action: StringName, button_index: JoyButton) -> void:
	_ensure_action(action)
	var input_event := InputEventJoypadButton.new()
	input_event.button_index = button_index
	InputMap.action_add_event(action, input_event)


func _add_axis(action: StringName, axis: JoyAxis, axis_value: float) -> void:
	_ensure_action(action, 0.18)
	var input_event := InputEventJoypadMotion.new()
	input_event.axis = axis
	input_event.axis_value = axis_value
	InputMap.action_add_event(action, input_event)


func _shape_trigger(value: float, deadzone: float) -> float:
	var magnitude := clampf(value, 0.0, 1.0)
	if magnitude <= deadzone:
		return 0.0
	return clampf((magnitude - deadzone) / maxf(1.0 - deadzone, 0.001), 0.0, 1.0)
