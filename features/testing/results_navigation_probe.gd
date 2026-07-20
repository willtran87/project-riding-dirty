extends Node
## Deterministic contract for a full 12-rider classification: mouse scrolling,
## initial player reveal, and keyboard/gamepad selection visibility.

const HUD_SCENE := preload("res://features/hud/race_hud.tscn")
const REBOUND_ACTIONS: Array[StringName] = [
	InputRouter.EVENT_PREVIOUS,
	InputRouter.EVENT_NEXT,
	InputRouter.PAGE_PREVIOUS,
	InputRouter.PAGE_NEXT,
	InputRouter.RESULTS_FIRST,
	InputRouter.RESULTS_LAST,
]
const REBOUND_KEYS: Dictionary = {
	InputRouter.EVENT_PREVIOUS: KEY_Z,
	InputRouter.EVENT_NEXT: KEY_X,
	InputRouter.PAGE_PREVIOUS: KEY_U,
	InputRouter.PAGE_NEXT: KEY_O,
	InputRouter.RESULTS_FIRST: KEY_N,
	InputRouter.RESULTS_LAST: KEY_M,
}
const REBOUND_BUTTONS: Dictionary = {
	InputRouter.EVENT_PREVIOUS: JOY_BUTTON_DPAD_LEFT,
	InputRouter.EVENT_NEXT: JOY_BUTTON_DPAD_RIGHT,
	InputRouter.PAGE_PREVIOUS: JOY_BUTTON_X,
	InputRouter.PAGE_NEXT: JOY_BUTTON_Y,
	InputRouter.RESULTS_FIRST: JOY_BUTTON_LEFT_STICK,
	InputRouter.RESULTS_LAST: JOY_BUTTON_RIGHT_STICK,
}

var _failures: Array[String] = []
var _action_snapshots: Dictionary = {}
var _prior_input_mode: StringName = &""
var _interface_feedback: Array[Dictionary] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_prior_input_mode = InputRouter.input_mode
	EventBus.interface_feedback_requested.connect(_on_interface_feedback_requested)
	_snapshot_actions()
	_apply_rebound_bindings()
	InputRouter.call(&"_set_input_mode", InputRouter.INPUT_MODE_KEYBOARD_MOUSE)
	var hud := HUD_SCENE.instantiate() as RaceHud
	add_child(hud)
	await get_tree().process_frame
	hud.apply_accessibility({&"text_scale": 1.75, &"units": &"IMPERIAL", &"high_contrast": false, &"color_safe_mode": &"OFF"})
	hud.show_results({
		&"run_id": "results-navigation-probe",
		&"signature": "results-navigation-probe-signature",
		&"event_id": &"CIRCUIT",
		&"valid": true,
		&"medal": &"BRONZE",
		&"classification": _classification(),
		&"player_position": 12,
		&"player_time_usec": 191_000_000,
		&"player_penalty_usec": 0,
		&"fastest_lap_usec": 172_000_000,
		&"rewards": {&"cash": 100, &"reputation": 10},
	})
	await get_tree().process_frame
	await get_tree().process_frame
	var initial := hud.get_results_navigation_snapshot()
	_check(int(initial.get(&"row_count", 0)) == 12, "Results omitted riders from the 12-bike field")
	_check(int(initial.get(&"player_index", -1)) == 11, "Player row was not identified at P12")
	_check(int(initial.get(&"selected_index", -1)) == 11, "Results did not initially select the player row")
	_check(bool(initial.get(&"selected_visible", false)), "P12 player row was not initially revealed")
	_check(float(initial.get(&"maximum_scroll", 0.0)) > 0.0, "12-rider results do not have a vertical scroll range")
	_check(bool(initial.get(&"mouse_scroll_enabled", false)), "Classification ignores mouse wheel input")
	_check_results_prompt(hud, initial, InputRouter.INPUT_MODE_KEYBOARD_MOUSE, "keyboard")

	_check(
		not bool(hud.call(&"_handle_results_navigation_input", _key_event(KEY_HOME))),
		"Removed Keyboard Home default was still handled"
	)
	_check(int(hud.get_results_navigation_snapshot().get(&"selected_index", -1)) == 11, "Removed Home default changed the Results selection")
	_check(bool(hud.call(&"_handle_results_navigation_input", _key_event(KEY_N))), "Rebound keyboard First Result was not handled")
	await get_tree().process_frame
	await get_tree().process_frame
	var keyboard := hud.get_results_navigation_snapshot()
	_check(int(keyboard.get(&"selected_index", -1)) == 0, "Rebound keyboard First Result did not select P1")
	_check(bool(keyboard.get(&"selected_visible", false)), "Keyboard-selected P1 row is outside the viewport")
	_check(
		float(keyboard.get(&"scroll_vertical", 0.0)) < float(initial.get(&"scroll_vertical", 0.0)),
		"Keyboard selection did not scroll toward P1"
	)
	_check(
		not bool(hud.call(&"_handle_results_navigation_input", _key_event(KEY_M, true))),
		"Echoed Last Result triggered a destructive edge jump"
	)
	_check(int(hud.get_results_navigation_snapshot().get(&"selected_index", -1)) == 0, "Echoed Last Result moved the Results selection")

	InputRouter.call(&"_set_input_mode", InputRouter.INPUT_MODE_GAMEPAD)
	var gamepad_prompt := hud.get_results_navigation_snapshot()
	_check_results_prompt(hud, gamepad_prompt, InputRouter.INPUT_MODE_GAMEPAD, "gamepad")
	_check(
		not bool(hud.call(&"_handle_results_navigation_input", _button_event(JOY_BUTTON_RIGHT_SHOULDER))),
		"Removed gamepad Right Shoulder page default was still handled"
	)
	_check(
		not bool(hud.call(&"_handle_results_navigation_input", _button_event(JOY_BUTTON_DPAD_DOWN))),
		"Removed gamepad D-pad Down row default was still handled"
	)
	_check(bool(hud.call(&"_handle_results_navigation_input", _key_event(KEY_O, true))), "Echoed rebound Page Next was not repeat-safe")
	_check(bool(hud.call(&"_handle_results_navigation_input", _key_event(KEY_O, true))), "Second echoed rebound Page Next was not repeat-safe")
	_check(bool(hud.call(&"_handle_results_navigation_input", _button_event(JOY_BUTTON_DPAD_RIGHT))), "Rebound gamepad Next Result was not handled")
	await get_tree().process_frame
	await get_tree().process_frame
	var gamepad := hud.get_results_navigation_snapshot()
	_check(int(gamepad.get(&"selected_index", -1)) == 11, "Gamepad navigation did not reach P12")
	_check(bool(gamepad.get(&"selected_visible", false)), "Gamepad-selected P12 row is outside the viewport")
	_check(float(gamepad.get(&"scroll_vertical", 0.0)) > float(keyboard.get(&"scroll_vertical", 0.0)), "Gamepad navigation did not scroll toward P12")
	_check(bool(hud.call(&"_handle_results_navigation_input", _button_event(JOY_BUTTON_LEFT_STICK))), "Rebound gamepad First Result was not handled")
	_check(int(hud.get_results_navigation_snapshot().get(&"selected_index", -1)) == 0, "Rebound gamepad First Result did not select P1")
	_check(bool(hud.call(&"_handle_results_navigation_input", _button_event(JOY_BUTTON_RIGHT_STICK))), "Rebound gamepad Last Result was not handled")
	_check(int(hud.get_results_navigation_snapshot().get(&"selected_index", -1)) == 11, "Rebound gamepad Last Result did not select P12")

	var scroll := hud.get("_results_scroll") as ScrollContainer
	if scroll != null:
		scroll.scroll_vertical = 0
		await get_tree().process_frame
		var wheel := InputEventMouseButton.new()
		wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
		wheel.pressed = true
		wheel.factor = 3.0
		wheel.position = scroll.get_global_rect().get_center()
		wheel.global_position = wheel.position
		_check(bool(hud.call(&"_handle_results_mouse_scroll", wheel)), "Mouse wheel event was not handled")
		await get_tree().process_frame
		await get_tree().process_frame
		_check(scroll.scroll_vertical > 0, "Mouse wheel did not move the classification scroll surface")
	_check(_has_interface_feedback(&"NAVIGATE", &"RESULTS_SELECTION"), "Keyboard/gamepad Results navigation emitted no audio feedback")
	_check(_has_interface_feedback(&"NAVIGATE", &"RESULTS_SCROLL"), "Mouse Results scrolling emitted no audio feedback")

	# A direct public race reset arrives before replay teardown. The stale replay
	# state must not restore the just-dismissed official Results card afterward.
	hud.update_replay_state(true)
	_check(
		not bool(hud.get_competition_presentation_snapshot().get(&"results_visible", true)),
		"Replay start did not hide the Results card"
	)
	EventBus.race_reset.emit()
	hud.update_replay_state(false)
	var reset_presentation := hud.get_competition_presentation_snapshot()
	_check(
		not bool(reset_presentation.get(&"results_visible", true))
		and StringName(reset_presentation.get(&"result_event", &"")) == &"",
		"Replay teardown resurrected stale Results after a race reset"
	)

	print("RESULTS NAVIGATION PROBE: rows=%d player=P%d initial=%s keyboard=%s gamepad=%s max_scroll=%.0f feedback=%d passed=%s" % [
		int(initial.get(&"row_count", 0)),
		int(initial.get(&"player_index", -1)) + 1,
		str(bool(initial.get(&"selected_visible", false))),
		str(bool(keyboard.get(&"selected_visible", false))),
		str(bool(gamepad.get(&"selected_visible", false))),
		float(initial.get(&"maximum_scroll", 0.0)),
		_interface_feedback.size(),
		str(_failures.is_empty()),
	])
	hud.queue_free()
	await get_tree().process_frame
	_restore_actions()
	for action: StringName in REBOUND_ACTIONS:
		_check(_action_matches_snapshot(action), "%s InputMap entry was not restored exactly" % String(action))
	InputRouter.call(&"_set_input_mode", _prior_input_mode)
	_check(InputRouter.input_mode == _prior_input_mode, "Prior input mode was not restored")
	if _failures.is_empty():
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("RESULTS NAVIGATION PROBE: " + failure)
	get_tree().quit(1)


func _on_interface_feedback_requested(kind: StringName, context: StringName) -> void:
	_interface_feedback.append({&"kind": kind, &"context": context})


func _has_interface_feedback(kind: StringName, context: StringName) -> bool:
	for entry: Dictionary in _interface_feedback:
		if StringName(entry.get(&"kind", &"")) == kind and StringName(entry.get(&"context", &"")) == context:
			return true
	return false


func _classification() -> Array[Dictionary]:
	var riders: Array[Dictionary] = []
	for index: int in 12:
		var is_player := index == 11
		riders.append({
			&"rider_id": &"PLAYER" if is_player else StringName("RIDER_%02d" % (index + 1)),
			&"display_name": "YOU" if is_player else "RIDER %02d" % (index + 1),
			&"number": 1 if is_player else index + 11,
			&"position": index + 1,
			&"status": &"FINISHED",
			&"finish_usec": 180_000_000 + index * 1_000_000,
			&"effective_time_usec": 180_000_000 + index * 1_000_000,
			&"penalty_usec": 0,
			&"is_player": is_player,
		})
	return riders


func _key_event(keycode: Key, echo: bool = false) -> InputEventKey:
	var event := InputEventKey.new()
	event.pressed = true
	event.physical_keycode = keycode
	event.echo = echo
	event.device = -1
	return event


func _button_event(button_index: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.pressed = true
	event.button_index = button_index
	event.device = -1
	return event


func _check_results_prompt(hud: RaceHud, snapshot: Dictionary, mode: StringName, device_label: String) -> void:
	var prompt := str(snapshot.get(&"navigation_prompt", ""))
	var expected_labels: Array[String] = [
		InputRouter.get_action_pair_label(InputRouter.EVENT_PREVIOUS, InputRouter.EVENT_NEXT, mode),
		InputRouter.get_action_pair_label(InputRouter.PAGE_PREVIOUS, InputRouter.PAGE_NEXT, mode),
		InputRouter.get_action_label(InputRouter.RESULTS_FIRST, mode, 1),
		InputRouter.get_action_label(InputRouter.RESULTS_LAST, mode, 1),
	]
	for expected: String in expected_labels:
		_check(prompt.contains(expected), "Results prompt omitted rebound %s label %s" % [device_label, expected])
	var footer := str(hud.get_competition_presentation_snapshot().get(&"footer", ""))
	_check(footer.contains(prompt), "Results footer did not expose the live %s navigation prompt" % device_label)
	_check(StringName(snapshot.get(&"input_mode", &"")) == mode, "Results snapshot did not report %s prompt mode" % device_label)


func _snapshot_actions() -> void:
	_action_snapshots.clear()
	for action: StringName in REBOUND_ACTIONS:
		var events: Array[InputEvent] = []
		if InputMap.has_action(action):
			for event: InputEvent in InputMap.action_get_events(action):
				events.append(event.duplicate() as InputEvent)
		_action_snapshots[action] = {
			&"existed": InputMap.has_action(action),
			&"deadzone": InputMap.action_get_deadzone(action) if InputMap.has_action(action) else 0.2,
			&"events": events,
			&"fingerprint": _binding_fingerprint(events),
		}


func _apply_rebound_bindings() -> void:
	for action: StringName in REBOUND_ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		var keycode: Key = REBOUND_KEYS[action]
		var button_index: JoyButton = REBOUND_BUTTONS[action]
		InputMap.action_add_event(action, _key_event(keycode))
		InputMap.action_add_event(action, _button_event(button_index))


func _restore_actions() -> void:
	for action: StringName in REBOUND_ACTIONS:
		var snapshot := _action_snapshots.get(action, {}) as Dictionary
		if not bool(snapshot.get(&"existed", false)):
			if InputMap.has_action(action):
				InputMap.erase_action(action)
			continue
		if not InputMap.has_action(action):
			InputMap.add_action(action, float(snapshot.get(&"deadzone", 0.2)))
		InputMap.action_set_deadzone(action, float(snapshot.get(&"deadzone", 0.2)))
		InputMap.action_erase_events(action)
		for event: InputEvent in snapshot.get(&"events", []) as Array[InputEvent]:
			InputMap.action_add_event(action, event.duplicate() as InputEvent)


func _action_matches_snapshot(action: StringName) -> bool:
	var snapshot := _action_snapshots.get(action, {}) as Dictionary
	var existed := bool(snapshot.get(&"existed", false))
	if InputMap.has_action(action) != existed:
		return false
	if not existed:
		return true
	if not is_equal_approx(
		InputMap.action_get_deadzone(action), float(snapshot.get(&"deadzone", 0.2))
	):
		return false
	return _binding_fingerprint(InputMap.action_get_events(action)) == str(snapshot.get(&"fingerprint", ""))


func _binding_fingerprint(events: Array[InputEvent]) -> String:
	var serialized: Array[Dictionary] = []
	for event: InputEvent in events:
		serialized.append(SettingsStore.serialize_binding(event))
	return JSON.stringify(serialized)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
