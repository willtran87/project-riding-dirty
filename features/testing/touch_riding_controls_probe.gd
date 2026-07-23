extends Node
## Deterministic runtime contract for touch riding and Garage controls.
##
## Definition of done:
## - AUTO/ON/OFF, RIDE/GARAGE/HIDDEN, handedness, and portrait behavior agree;
## - every visible target preserves the 112 authored-pixel accessibility floor;
## - steering/lean are analog and every finger owns/releases only its action;
## - system and Garage buttons inject the expected semantic InputMap actions;
## - deactivation and explicit cleanup can never leave an action stuck.

const TOUCH_CONTROLS_SCRIPT := preload("res://features/input/touch_riding_controls.gd")

const FULL_LANDSCAPE := Vector2i(1600, 900)
const COMPACT_LANDSCAPE := Vector2i(844, 390)
const PORTRAIT := Vector2i(900, 1600)
const AUTHORED_MINIMUM_TARGET := 112.0
const GEOMETRY_EPSILON := 1.0

const RIDE_TARGETS: Array[StringName] = [
	&"joystick", &"throttle", &"brake", &"preload", &"flow", &"racecraft",
	&"reset", &"pause", &"garage",
]
const MIRRORED_RIDE_TARGETS: Array[StringName] = [
	&"joystick", &"throttle", &"brake", &"preload", &"flow", &"racecraft",
]
const GARAGE_TARGETS: Array[StringName] = [
	&"event_previous", &"event_next", &"setup_left", &"setup_right", &"confirm",
	&"continue", &"workshop", &"settings", &"repair", &"assist",
]
const RESULTS_TARGETS: Array[StringName] = [
	&"ride_again", &"results_garage", &"results_settings", &"replay",
]
const ALL_ACTIONS: Array[StringName] = [
	&"throttle", &"brake", &"steer_left", &"steer_right",
	&"lean_forward", &"lean_back", &"preload", &"flow_boost",
	&"racecraft_technique", &"reset_bike", &"pause_game", &"open_garage",
	&"event_previous", &"event_next", &"garage_left", &"garage_right",
	&"confirm_selection", &"open_workshop", &"open_settings", &"repair_bike",
	&"toggle_assist", &"restart_run", &"toggle_replay", &"continue_weekend",
]
const RIDE_SYSTEM_ACTIONS: Dictionary = {
	&"reset": &"reset_bike",
	&"pause": &"pause_game",
	&"garage": &"open_garage",
}
const GARAGE_ACTIONS: Dictionary = {
	&"event_previous": &"event_previous",
	&"event_next": &"event_next",
	&"setup_left": &"garage_left",
	&"setup_right": &"garage_right",
	&"confirm": &"confirm_selection",
	&"continue": &"continue_weekend",
	&"workshop": &"open_workshop",
	&"settings": &"open_settings",
	&"repair": &"repair_bike",
	&"assist": &"toggle_assist",
}
const RESULTS_ACTIONS: Dictionary = {
	&"ride_again": &"restart_run",
	&"results_garage": &"open_garage",
	&"results_settings": &"open_settings",
	&"replay": &"toggle_replay",
}


class ActionObserver:
	extends Node

	var events: Array[Dictionary] = []


	func _input(event: InputEvent) -> void:
		if event is not InputEventAction:
			return
		var action_event := event as InputEventAction
		events.append({
			&"action": action_event.action,
			&"pressed": action_event.pressed,
			&"strength": action_event.strength,
		})


	func clear_events() -> void:
		events.clear()


	func count(action: StringName, pressed: bool) -> int:
		var total := 0
		for event: Dictionary in events:
			if StringName(event.get(&"action", &"")) == action and bool(event.get(&"pressed", false)) == pressed:
				total += 1
		return total


var _host: SubViewport
var _controls: Node
var _observer: ActionObserver
var _failures: Array[String] = []
var _added_actions: Array[StringName] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_ensure_actions()
	_observer = ActionObserver.new()
	add_child(_observer)
	_observer.set_process_input(true)

	_host = SubViewport.new()
	_host.name = "DeterministicTouchViewport"
	_host.size = FULL_LANDSCAPE
	_host.disable_3d = true
	_host.handle_input_locally = true
	_host.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_host)

	_controls = TOUCH_CONTROLS_SCRIPT.new() as Node
	_host.add_child(_controls)
	await _settle_layout()

	await _probe_landscape_layout()
	_probe_touch_mouse_mode_handoff()
	_probe_analog_joystick()
	_probe_simultaneous_riding_inputs()
	_probe_riding_system_actions()
	await _probe_deactivation_and_modes()
	await _probe_handedness_mirroring()
	await _probe_compact_landscape()
	await _probe_garage_context()
	await _probe_results_context()
	await _probe_portrait_contract()

	var passed := _failures.is_empty()
	if passed:
		print(
			"TOUCH RIDING CONTROLS PROBE: PASS  //  ride=9 garage=10 minimum=112px "
			+ "results=4 multitouch=true analog=true modes=3 handedness=2 portrait=true"
		)
	else:
		for failure: String in _failures:
			push_error("TOUCH RIDING CONTROLS PROBE: " + failure)
	await _cleanup()
	get_tree().quit(0 if passed else 1)


func _probe_landscape_layout() -> void:
	await _set_host_size(FULL_LANDSCAPE)
	_configure(&"AUTO", &"RIGHT")
	_controls.call(&"set_touchscreen_override", 1)
	_controls.call(&"set_context", &"RIDE")
	await _settle_layout()
	var snapshot := _snapshot()
	_check_snapshot_authority(snapshot, FULL_LANDSCAPE, &"RIDE", &"LANDSCAPE", &"AUTO", &"RIGHT")
	_check(bool(snapshot.get(&"touchscreen_enabled", false)), "AUTO recognizes the touchscreen override")
	_check(bool(snapshot.get(&"controls_visible", false)), "landscape RIDE controls are visible")
	_check(not bool(snapshot.get(&"rotate_prompt_visible", true)), "landscape does not show the rotate prompt")
	_check_target_group(snapshot, RIDE_TARGETS, true, "landscape RIDE")
	_check_target_group(snapshot, GARAGE_TARGETS, false, "landscape RIDE hides Garage")
	_check_layout_geometry(snapshot, RIDE_TARGETS, "full landscape RIDE")
	for control_id: StringName in RIDE_SYSTEM_ACTIONS:
		_check_target_action(snapshot, control_id, RIDE_SYSTEM_ACTIONS[control_id], "RIDE system mapping")


func _probe_touch_mouse_mode_handoff() -> void:
	InputRouter.note_touch_input()
	_check(InputRouter.input_mode == InputRouter.INPUT_MODE_TOUCH, "raw touch selects touch HUD prompts")
	var emulated_mouse := InputEventMouseMotion.new()
	emulated_mouse.relative = Vector2.ONE
	InputRouter._input(emulated_mouse)
	_check(InputRouter.input_mode == InputRouter.INPUT_MODE_TOUCH, "companion mouse event cannot steal touch HUD prompts")
	InputRouter.set(
		"_last_touch_input_usec",
		Time.get_ticks_usec() - InputRouter.MOUSE_AFTER_TOUCH_GUARD_USEC - 1
	)
	InputRouter._input(emulated_mouse)
	_check(InputRouter.input_mode == InputRouter.INPUT_MODE_KEYBOARD_MOUSE, "real mouse input takes over after the touch guard")
	InputRouter.note_touch_input()


func _probe_analog_joystick() -> void:
	_release_everything()
	var snapshot := _snapshot()
	var joystick := snapshot.get(&"joystick", {}) as Dictionary
	var center: Vector2 = joystick.get(&"base_center", _target_center(snapshot, &"joystick"))
	var zone: Rect2 = joystick.get(&"zone_rect", Rect2(center - Vector2(112.0, 112.0), Vector2(224.0, 224.0)))
	var radius := maxf(float(joystick.get(&"radius", minf(zone.size.x, zone.size.y) * 0.2)), 44.0)

	_send_touch(10, center, true)
	_send_drag(10, center + Vector2(radius * 0.35, 0.0), Vector2(radius * 0.35, 0.0))
	var partial_right := Input.get_action_strength(&"steer_right")
	_check(partial_right > 0.12 and partial_right < 0.75, "partial joystick drag produces partial steering", "strength=%.3f" % partial_right)
	_send_drag(10, center + Vector2(radius, 0.0), Vector2(radius * 0.65, 0.0))
	var full_right := Input.get_action_strength(&"steer_right")
	_check(full_right > partial_right + 0.15 and full_right <= 1.0001, "farther joystick drag increases analog steering", "partial=%.3f full=%.3f" % [partial_right, full_right])
	_check(Input.get_action_strength(&"steer_left") <= 0.001, "right steering releases the opposite direction")
	_send_touch(10, center + Vector2(radius, 0.0), false)
	_check_actions_released([&"steer_left", &"steer_right", &"lean_forward", &"lean_back"], "right joystick release")

	_send_touch(11, center, true)
	_send_drag(11, center - Vector2(radius, 0.0), -Vector2(radius, 0.0))
	_check(Input.get_action_strength(&"steer_left") > 0.82, "left joystick drag reaches strong left steering")
	_check(Input.get_action_strength(&"steer_right") <= 0.001, "left steering releases the opposite direction")
	_send_touch(11, center - Vector2(radius, 0.0), false)
	_check_actions_released([&"steer_left", &"steer_right"], "left joystick release")

	_send_touch(12, center, true)
	_send_drag(12, center - Vector2(0.0, radius * 0.72), -Vector2(0.0, radius * 0.72))
	_check(Input.get_action_strength(&"lean_forward") > 0.55, "upward joystick drag produces analog forward lean")
	_check(Input.get_action_strength(&"lean_back") <= 0.001, "forward lean releases backward lean")
	_send_drag(12, center + Vector2(0.0, radius * 0.72), Vector2(0.0, radius * 1.44))
	_check(Input.get_action_strength(&"lean_back") > 0.55, "downward joystick drag produces analog backward lean")
	_check(Input.get_action_strength(&"lean_forward") <= 0.001, "backward lean releases forward lean")
	_send_touch(12, center + Vector2(0.0, radius * 0.72), false)
	_check_actions_released([&"lean_forward", &"lean_back"], "lean joystick release")


func _probe_simultaneous_riding_inputs() -> void:
	_release_everything()
	var snapshot := _snapshot()
	var joystick := snapshot.get(&"joystick", {}) as Dictionary
	var center: Vector2 = joystick.get(&"base_center", _target_center(snapshot, &"joystick"))
	var zone: Rect2 = joystick.get(&"zone_rect", Rect2(center - Vector2(112.0, 112.0), Vector2(224.0, 224.0)))
	var radius := maxf(float(joystick.get(&"radius", minf(zone.size.x, zone.size.y) * 0.2)), 40.0)

	_send_touch(20, center, true)
	_send_drag(20, center + Vector2(radius, -radius * 0.45), Vector2(radius, -radius * 0.45))
	_press_target(snapshot, &"throttle", 21)
	_press_target(snapshot, &"preload", 22)
	_press_target(snapshot, &"flow", 23)
	_press_target(snapshot, &"racecraft", 24)
	_check(Input.get_action_strength(&"steer_right") > 0.4, "joystick remains analog during five-finger input")
	_check(Input.get_action_strength(&"lean_forward") > 0.12, "diagonal joystick retains independent lean")
	_check(Input.is_action_pressed(&"throttle"), "throttle can be held beside joystick")
	_check(Input.is_action_pressed(&"preload"), "preload can be held beside throttle")
	_check(Input.is_action_pressed(&"flow_boost"), "Flow can be held beside riding inputs")
	_check(Input.is_action_pressed(&"racecraft_technique"), "racecraft can be held beside riding inputs")

	_release_target(snapshot, &"preload", 22)
	_check(not Input.is_action_pressed(&"preload"), "preload finger releases only preload")
	_check(Input.is_action_pressed(&"throttle") and Input.is_action_pressed(&"flow_boost") and Input.is_action_pressed(&"racecraft_technique"), "other fingers survive preload release")
	_send_touch(20, center + Vector2(radius, -radius * 0.45), false)
	_check_actions_released([&"steer_left", &"steer_right", &"lean_forward", &"lean_back"], "joystick finger releases only stick axes")
	_check(Input.is_action_pressed(&"throttle") and Input.is_action_pressed(&"flow_boost") and Input.is_action_pressed(&"racecraft_technique"), "button fingers survive joystick release")
	_release_target(snapshot, &"flow", 23)
	_check(not Input.is_action_pressed(&"flow_boost") and Input.is_action_pressed(&"racecraft_technique"), "Flow release does not cancel racecraft")
	_release_target(snapshot, &"racecraft", 24)
	_release_target(snapshot, &"throttle", 21)
	_check_actions_released([&"throttle", &"preload", &"flow_boost", &"racecraft_technique"], "multi-finger RIDE cleanup")


func _probe_riding_system_actions() -> void:
	_release_everything()
	var snapshot := _snapshot()
	for control_id: StringName in RIDE_SYSTEM_ACTIONS:
		_probe_semantic_button(snapshot, control_id, RIDE_SYSTEM_ACTIONS[control_id], 30 + RIDE_SYSTEM_ACTIONS.keys().find(control_id), "RIDE")


func _probe_deactivation_and_modes() -> void:
	_release_everything()
	_configure(&"AUTO", &"RIGHT")
	_controls.call(&"set_touchscreen_override", 1)
	_controls.call(&"set_gameplay_active", true)
	await _settle_layout()
	var snapshot := _snapshot()
	_press_target(snapshot, &"throttle", 40)
	_press_target(snapshot, &"preload", 41)
	_check(Input.is_action_pressed(&"throttle") and Input.is_action_pressed(&"preload"), "deactivation setup holds multiple actions")
	_controls.call(&"set_gameplay_active", false)
	await _settle_layout()
	snapshot = _snapshot()
	_check(StringName(snapshot.get(&"context", &"")) == &"HIDDEN", "set_gameplay_active(false) enters HIDDEN context")
	_check(not bool(snapshot.get(&"controls_visible", true)), "deactivation hides controls")
	_check_actions_released(ALL_ACTIONS, "deactivation releases every action")
	_check((snapshot.get(&"held_actions", {}) as Dictionary).is_empty(), "deactivation clears held-action ownership")

	_controls.call(&"set_gameplay_active", true)
	_configure(&"AUTO", &"RIGHT")
	await _settle_layout()
	snapshot = _snapshot()
	_press_target(snapshot, &"throttle", 42)
	_press_target(snapshot, &"brake", 43)
	_check(Input.is_action_pressed(&"throttle") and Input.is_action_pressed(&"brake"), "explicit-release setup owns throttle and brake independently")
	_controls.call(&"release_all_inputs")
	Input.flush_buffered_events()
	snapshot = _snapshot()
	_check_actions_released(ALL_ACTIONS, "release_all_inputs()")
	_check((snapshot.get(&"held_actions", {}) as Dictionary).is_empty(), "release_all_inputs() clears held-action snapshot")
	_check(not bool((snapshot.get(&"joystick", {}) as Dictionary).get(&"active", true)), "release_all_inputs() clears joystick ownership")

	_configure(&"OFF", &"RIGHT")
	await _settle_layout()
	snapshot = _snapshot()
	_check(StringName(snapshot.get(&"context", &"")) == &"RIDE", "set_gameplay_active(true) restores RIDE context")
	_check(not bool(snapshot.get(&"controls_visible", true)), "OFF hides RIDE controls despite a touchscreen")
	_check_target_group(snapshot, RIDE_TARGETS, false, "OFF")

	_configure(&"AUTO", &"RIGHT")
	_controls.call(&"set_touchscreen_override", 0)
	await _settle_layout()
	snapshot = _snapshot()
	_check(not bool(snapshot.get(&"touchscreen_enabled", true)) and not bool(snapshot.get(&"controls_visible", true)), "AUTO hides controls when no touchscreen is present")

	_configure(&"ON", &"RIGHT")
	await _settle_layout()
	snapshot = _snapshot()
	_check(bool(snapshot.get(&"touchscreen_enabled", false)), "ON forces touchscreen presentation without hardware")
	_check(bool(snapshot.get(&"controls_visible", false)), "ON forces landscape controls without touchscreen hardware")
	_check_target_group(snapshot, RIDE_TARGETS, true, "ON force")
	_controls.call(&"set_touchscreen_override", 1)


func _probe_handedness_mirroring() -> void:
	await _set_host_size(FULL_LANDSCAPE)
	_controls.call(&"set_context", &"RIDE")
	_configure(&"ON", &"RIGHT")
	await _settle_layout()
	var right_snapshot := _snapshot()
	_configure(&"ON", &"LEFT")
	await _settle_layout()
	var left_snapshot := _snapshot()
	_check(StringName(left_snapshot.get(&"handedness", &"")) == &"LEFT", "LEFT handedness is authoritative in snapshot")
	var safe: Rect2 = right_snapshot.get(&"safe_rect", Rect2())
	var mirror_axis := safe.position.x + safe.size.x * 0.5
	for control_id: StringName in MIRRORED_RIDE_TARGETS:
		var right_center := _target_center(right_snapshot, control_id)
		var left_center := _target_center(left_snapshot, control_id)
		_check(absf((right_center.x + left_center.x) - mirror_axis * 2.0) <= GEOMETRY_EPSILON, "%s mirrors across the safe-area center" % String(control_id), "right=%s left=%s axis=%.2f" % [str(right_center), str(left_center), mirror_axis])
		_check(absf(right_center.y - left_center.y) <= GEOMETRY_EPSILON, "%s keeps its vertical placement when mirrored" % String(control_id))
	_configure(&"ON", &"RIGHT")
	await _settle_layout()


func _probe_compact_landscape() -> void:
	await _set_host_size(COMPACT_LANDSCAPE)
	_configure(&"ON", &"RIGHT")
	_controls.call(&"set_context", &"RIDE")
	await _settle_layout()
	var snapshot := _snapshot()
	_check_snapshot_authority(snapshot, COMPACT_LANDSCAPE, &"RIDE", &"LANDSCAPE", &"ON", &"RIGHT")
	_check(bool(snapshot.get(&"controls_visible", false)), "844x390 landscape retains touch controls")
	_check_layout_geometry(snapshot, RIDE_TARGETS, "compact landscape RIDE")
	var expected_rendered_minimum := AUTHORED_MINIMUM_TARGET * (float(COMPACT_LANDSCAPE.y) / float(FULL_LANDSCAPE.y))
	var rendered_minimum := float(snapshot.get(&"rendered_minimum_target_size", 0.0))
	_check(absf(rendered_minimum - expected_rendered_minimum) <= 1.0, "compact target floor scales from authored coordinates", "expected=%.3f actual=%.3f" % [expected_rendered_minimum, rendered_minimum])
	var safe: Rect2 = snapshot.get(&"safe_rect", Rect2())
	_check(safe.size.x <= COMPACT_LANDSCAPE.x + GEOMETRY_EPSILON and safe.size.y <= COMPACT_LANDSCAPE.y + GEOMETRY_EPSILON, "compact safe rectangle stays inside its host", "safe=%s" % str(safe))


func _probe_garage_context() -> void:
	await _set_host_size(FULL_LANDSCAPE)
	_configure(&"ON", &"RIGHT")
	_controls.call(&"set_context", &"GARAGE")
	await _settle_layout()
	var snapshot := _snapshot()
	_check_snapshot_authority(snapshot, FULL_LANDSCAPE, &"GARAGE", &"LANDSCAPE", &"ON", &"RIGHT")
	_check(bool(snapshot.get(&"controls_visible", false)), "Garage controls are visible in landscape")
	_check_target_group(snapshot, RIDE_TARGETS, false, "Garage hides RIDE")
	_check_target_group(snapshot, GARAGE_TARGETS, true, "Garage")
	_check_layout_geometry(snapshot, GARAGE_TARGETS, "full landscape Garage")
	for control_id: StringName in GARAGE_ACTIONS:
		var expected_action: StringName = GARAGE_ACTIONS[control_id]
		_check_target_action(snapshot, control_id, expected_action, "Garage semantic mapping")
		_probe_semantic_button(snapshot, control_id, expected_action, 60 + GARAGE_ACTIONS.keys().find(control_id), "GARAGE")
	_check_target_action(snapshot, &"workshop", &"open_workshop", "Workshop semantic correction")


func _probe_results_context() -> void:
	_release_everything()
	await _set_host_size(FULL_LANDSCAPE)
	_configure(&"ON", &"RIGHT")
	_controls.call(&"set_context", &"RESULTS")
	await _settle_layout()
	var snapshot := _snapshot()
	_check_snapshot_authority(snapshot, FULL_LANDSCAPE, &"RESULTS", &"LANDSCAPE", &"ON", &"RIGHT")
	_check(bool(snapshot.get(&"controls_visible", false)), "Results controls are visible in landscape")
	_check_target_group(snapshot, RIDE_TARGETS, false, "Results hides RIDE")
	_check_target_group(snapshot, GARAGE_TARGETS, false, "Results hides Garage")
	_check_target_group(snapshot, RESULTS_TARGETS, true, "Results")
	_check_layout_geometry(snapshot, RESULTS_TARGETS, "full landscape Results")
	_check_actions_released(
		[&"throttle", &"brake", &"steer_left", &"steer_right", &"lean_forward", &"lean_back", &"preload", &"flow_boost", &"racecraft_technique"],
		"Results entry"
	)
	for control_id: StringName in RESULTS_ACTIONS:
		var expected_action: StringName = RESULTS_ACTIONS[control_id]
		_check_target_action(snapshot, control_id, expected_action, "Results semantic mapping")
		_probe_semantic_button(snapshot, control_id, expected_action, 80 + RESULTS_ACTIONS.keys().find(control_id), "RESULTS")


func _probe_portrait_contract() -> void:
	_release_everything()
	await _set_host_size(PORTRAIT)
	_configure(&"ON", &"RIGHT")
	_controls.call(&"set_context", &"RIDE")
	await _settle_layout()
	var snapshot := _snapshot()
	_check_snapshot_authority(snapshot, PORTRAIT, &"RIDE", &"PORTRAIT", &"ON", &"RIGHT")
	_check(not bool(snapshot.get(&"controls_visible", true)), "portrait hides RIDE pads")
	_check(bool(snapshot.get(&"rotate_prompt_visible", false)), "portrait shows the rotate-device prompt")
	_check_target_group(snapshot, RIDE_TARGETS, false, "portrait RIDE")
	_check_actions_released(ALL_ACTIONS, "portrait transition releases actions")

	_controls.call(&"set_context", &"GARAGE")
	await _settle_layout()
	snapshot = _snapshot()
	_check(not bool(snapshot.get(&"controls_visible", true)), "portrait hides Garage pads")
	_check(bool(snapshot.get(&"rotate_prompt_visible", false)), "portrait Garage retains the rotate-device prompt")
	_check_target_group(snapshot, GARAGE_TARGETS, false, "portrait Garage")

	_controls.call(&"set_context", &"HIDDEN")
	await _settle_layout()
	snapshot = _snapshot()
	_check(not bool(snapshot.get(&"controls_visible", true)), "HIDDEN context keeps portrait controls hidden")
	_check(not bool(snapshot.get(&"rotate_prompt_visible", true)), "HIDDEN context suppresses the rotate prompt")


func _probe_semantic_button(snapshot: Dictionary, control_id: StringName, action: StringName, finger: int, context_label: String) -> void:
	_release_everything()
	_observer.clear_events()
	_press_target(snapshot, control_id, finger)
	var pressed_snapshot := _snapshot()
	var control_pressed := bool(_target(pressed_snapshot, control_id).get(&"pressed", false))
	var parsed_press := _observer.count(action, true)
	var action_pressed := Input.is_action_pressed(action)
	_check(action_pressed or parsed_press > 0, "%s %s injects %s on press" % [context_label, String(control_id), String(action)], "held=%s parsed=%d snapshot=%s" % [str(action_pressed), parsed_press, str(control_pressed)])
	_release_target(snapshot, control_id, finger)
	var released_snapshot := _snapshot()
	var parsed_release := _observer.count(action, false)
	_check(not Input.is_action_pressed(action), "%s %s releases %s" % [context_label, String(control_id), String(action)])
	_check(not bool(_target(released_snapshot, control_id).get(&"pressed", false)), "%s %s clears its pressed presentation" % [context_label, String(control_id)])
	if parsed_press > 0:
		_check(parsed_press == 1, "%s %s emits one semantic press" % [context_label, String(control_id)], "count=%d" % parsed_press)
		_check(parsed_release == 1, "%s %s emits one matching semantic release" % [context_label, String(control_id)], "count=%d" % parsed_release)


func _check_snapshot_authority(snapshot: Dictionary, expected_size: Vector2i, expected_context: StringName, expected_orientation: StringName, expected_mode: StringName, expected_handedness: StringName) -> void:
	var viewport_size: Vector2 = snapshot.get(&"viewport_size", Vector2.ZERO)
	_check(viewport_size.is_equal_approx(Vector2(expected_size)), "snapshot reports %dx%d viewport" % [expected_size.x, expected_size.y], "actual=%s" % str(viewport_size))
	_check(StringName(snapshot.get(&"context", &"")) == expected_context, "snapshot reports %s context" % String(expected_context))
	_check(StringName(snapshot.get(&"orientation", &"")) == expected_orientation, "snapshot reports %s orientation" % String(expected_orientation))
	_check(StringName(snapshot.get(&"mode", &"")) == expected_mode, "snapshot reports %s touch mode" % String(expected_mode))
	_check(StringName(snapshot.get(&"handedness", &"")) == expected_handedness, "snapshot reports %s handedness" % String(expected_handedness))
	_check(is_equal_approx(float(snapshot.get(&"minimum_target_size", 0.0)), AUTHORED_MINIMUM_TARGET), "snapshot exposes the 112px authored target contract")
	_check(is_equal_approx(float(snapshot.get(&"authored_minimum_target_size", 0.0)), AUTHORED_MINIMUM_TARGET), "snapshot distinguishes authored target size")


func _check_layout_geometry(snapshot: Dictionary, target_ids: Array[StringName], label: String) -> void:
	var safe: Rect2 = snapshot.get(&"safe_rect", Rect2())
	var viewport_size: Vector2 = snapshot.get(&"viewport_size", Vector2.ZERO)
	_check(safe.size.x > 0.0 and safe.size.y > 0.0, "%s has a non-empty safe rectangle" % label, "safe=%s" % str(safe))
	_check(_rect_inside(Rect2(Vector2.ZERO, viewport_size), safe), "%s safe rectangle stays inside viewport" % label, "viewport=%s safe=%s" % [str(viewport_size), str(safe)])
	var rendered_minimum := float(snapshot.get(&"rendered_minimum_target_size", 0.0))
	_check(rendered_minimum > 0.0, "%s exposes a rendered target floor" % label)
	for control_id: StringName in target_ids:
		var control := _target(snapshot, control_id)
		var rect: Rect2 = control.get(&"rect", Rect2())
		var minimum_size: Vector2 = control.get(&"minimum_size", Vector2.ZERO)
		_check(minimum_size.x + 0.001 >= AUTHORED_MINIMUM_TARGET and minimum_size.y + 0.001 >= AUTHORED_MINIMUM_TARGET, "%s %s preserves >=112 authored pixels" % [label, String(control_id)], "minimum=%s" % str(minimum_size))
		_check(rect.size.x + GEOMETRY_EPSILON >= rendered_minimum and rect.size.y + GEOMETRY_EPSILON >= rendered_minimum, "%s %s preserves the rendered target floor" % [label, String(control_id)], "rect=%s floor=%.3f" % [str(rect), rendered_minimum])
		_check(_rect_inside(safe, rect), "%s %s stays inside the safe rectangle" % [label, String(control_id)], "rect=%s safe=%s" % [str(rect), str(safe)])


func _check_target_group(snapshot: Dictionary, target_ids: Array[StringName], expected_visible: bool, label: String) -> void:
	for control_id: StringName in target_ids:
		var control := _target(snapshot, control_id)
		_check(not control.is_empty(), "%s snapshot includes %s" % [label, String(control_id)])
		_check(bool(control.get(&"visible", not expected_visible)) == expected_visible, "%s %s visibility is %s" % [label, String(control_id), str(expected_visible)])


func _check_target_action(snapshot: Dictionary, control_id: StringName, expected_action: StringName, label: String) -> void:
	var actual := StringName(_target(snapshot, control_id).get(&"action", &""))
	_check(actual == expected_action, "%s maps %s to %s" % [label, String(control_id), String(expected_action)], "actual=%s" % String(actual))


func _target(snapshot: Dictionary, control_id: StringName) -> Dictionary:
	var controls := snapshot.get(&"controls", {}) as Dictionary
	return controls.get(control_id, {}) as Dictionary


func _target_center(snapshot: Dictionary, control_id: StringName) -> Vector2:
	var control := _target(snapshot, control_id)
	if control.has(&"center"):
		return control.get(&"center", Vector2.ZERO)
	var rect: Rect2 = control.get(&"rect", Rect2())
	return rect.get_center()


func _press_target(snapshot: Dictionary, control_id: StringName, finger: int) -> void:
	_send_touch(finger, _target_center(snapshot, control_id), true)


func _release_target(snapshot: Dictionary, control_id: StringName, finger: int) -> void:
	_send_touch(finger, _target_center(snapshot, control_id), false)


func _send_touch(finger: int, position: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = finger
	event.position = position
	event.pressed = pressed
	_controls.call(&"_input", event)
	# TouchRidingControls intentionally enters the same buffered event pipeline as
	# physical devices. Flush here so this headless probe can inspect that frame's
	# semantic action deterministically without a wall-clock wait.
	Input.flush_buffered_events()


func _send_drag(finger: int, position: Vector2, relative: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = finger
	event.position = position
	event.relative = relative
	_controls.call(&"_input", event)
	Input.flush_buffered_events()


func _snapshot() -> Dictionary:
	return _controls.call(&"get_touch_layout_snapshot") as Dictionary


func _configure(mode: StringName, handedness: StringName) -> void:
	_controls.call(&"configure_touch_controls", {
		"touch_controls": String(mode),
		"touch_control_scale": 1.0,
		"touch_control_opacity": 0.72,
		"touch_handedness": String(handedness),
	})


func _set_host_size(size: Vector2i) -> void:
	_host.size = size
	await _settle_layout()


func _settle_layout() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _ensure_actions() -> void:
	for action: StringName in ALL_ACTIONS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, 0.0)
		_added_actions.append(action)


func _release_everything() -> void:
	if is_instance_valid(_controls):
		_controls.call(&"release_all_inputs")
		Input.flush_buffered_events()
	for action: StringName in ALL_ACTIONS:
		Input.action_release(action)


func _check_actions_released(actions: Array[StringName], label: String) -> void:
	var stuck: Array[StringName] = []
	for action: StringName in actions:
		if Input.is_action_pressed(action) or Input.get_action_strength(action) > 0.001:
			stuck.append(action)
	_check(stuck.is_empty(), "%s leaves no stuck actions" % label, "stuck=%s" % str(stuck))


func _rect_inside(outer: Rect2, inner: Rect2) -> bool:
	return (
		inner.position.x >= outer.position.x - GEOMETRY_EPSILON
		and inner.position.y >= outer.position.y - GEOMETRY_EPSILON
		and inner.end.x <= outer.end.x + GEOMETRY_EPSILON
		and inner.end.y <= outer.end.y + GEOMETRY_EPSILON
	)


func _check(condition: bool, label: String, details: String = "") -> void:
	if condition:
		return
	var suffix := "" if details.is_empty() else "  //  " + details
	_failures.append(label + suffix)


func _cleanup() -> void:
	_release_everything()
	if is_instance_valid(_controls):
		_controls.queue_free()
	if is_instance_valid(_observer):
		_observer.queue_free()
	if is_instance_valid(_host):
		_host.queue_free()
	for action: StringName in _added_actions:
		if InputMap.has_action(action):
			InputMap.erase_action(action)
	await get_tree().process_frame
	await get_tree().process_frame
