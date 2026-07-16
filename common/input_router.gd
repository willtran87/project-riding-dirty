extends Node
## Defines semantic controls and exposes normalized keyboard/gamepad state.

signal device_changed(using_gamepad: bool)
signal input_mode_changed(mode: StringName)

const INPUT_MODE_KEYBOARD_MOUSE: StringName = &"KEYBOARD_MOUSE"
const INPUT_MODE_GAMEPAD: StringName = &"GAMEPAD"
const INPUT_MODE_TOUCH: StringName = &"TOUCH"
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

var using_gamepad: bool = false
var using_touch: bool = false
var input_mode: StringName = INPUT_MODE_KEYBOARD_MOUSE
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
	elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
		next_mode = INPUT_MODE_GAMEPAD
	elif event is InputEventKey or event is InputEventMouse:
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
	_add_key(TOGGLE_PHOTO_MODE, KEY_P)
	_add_key(SPECTATOR_NEXT, KEY_TAB)
	_add_button(SPECTATOR_NEXT, JOY_BUTTON_RIGHT_STICK)


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
