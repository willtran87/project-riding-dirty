extends Node
## Defines semantic controls and exposes normalized keyboard/gamepad state.

signal device_changed(using_gamepad: bool)

const THROTTLE: StringName = &"throttle"
const BRAKE: StringName = &"brake"
const STEER_LEFT: StringName = &"steer_left"
const STEER_RIGHT: StringName = &"steer_right"
const LEAN_FORWARD: StringName = &"lean_forward"
const LEAN_BACK: StringName = &"lean_back"
const PRELOAD: StringName = &"preload"
const FLOW_BOOST: StringName = &"flow_boost"
const RESET_BIKE: StringName = &"reset_bike"
const RESTART_RUN: StringName = &"restart_run"
const PAUSE: StringName = &"pause_game"
const GARAGE_LEFT: StringName = &"garage_left"
const GARAGE_RIGHT: StringName = &"garage_right"
const CONFIRM: StringName = &"confirm_selection"
const OPEN_GARAGE: StringName = &"open_garage"
const EVENT_PREVIOUS: StringName = &"event_previous"
const EVENT_NEXT: StringName = &"event_next"
const REPAIR_BIKE: StringName = &"repair_bike"
const TOGGLE_ASSIST: StringName = &"toggle_assist"

var using_gamepad: bool = false


func _ready() -> void:
	_register_actions()


func _input(event: InputEvent) -> void:
	var next_uses_gamepad := event is InputEventJoypadButton or event is InputEventJoypadMotion
	if event is InputEventKey or event is InputEventMouse:
		next_uses_gamepad = false
	if next_uses_gamepad != using_gamepad:
		using_gamepad = next_uses_gamepad
		device_changed.emit(using_gamepad)


func get_throttle() -> float:
	return Input.get_action_strength(THROTTLE)


func get_brake() -> float:
	return Input.get_action_strength(BRAKE)


func get_steer() -> float:
	return Input.get_axis(STEER_LEFT, STEER_RIGHT)


func get_lean() -> float:
	return Input.get_axis(LEAN_FORWARD, LEAN_BACK)


func is_preload_pressed() -> bool:
	return Input.is_action_pressed(PRELOAD)


func is_preload_just_released() -> bool:
	return Input.is_action_just_released(PRELOAD)


func is_flow_boost_just_pressed() -> bool:
	return Input.is_action_just_pressed(FLOW_BOOST)


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
