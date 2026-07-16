extends Node
## Deterministic contract for a full 12-rider classification: mouse scrolling,
## initial player reveal, and keyboard/gamepad selection visibility.

const HUD_SCENE := preload("res://features/hud/race_hud.tscn")

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
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

	var keyboard_home := InputEventKey.new()
	keyboard_home.pressed = true
	keyboard_home.physical_keycode = KEY_HOME
	_check(bool(hud.call(&"_handle_results_navigation_input", keyboard_home)), "Keyboard Home was not handled")
	await get_tree().process_frame
	await get_tree().process_frame
	var keyboard := hud.get_results_navigation_snapshot()
	_check(int(keyboard.get(&"selected_index", -1)) == 0, "Keyboard Home did not select P1")
	_check(bool(keyboard.get(&"selected_visible", false)), "Keyboard-selected P1 row is outside the viewport")
	_check(
		float(keyboard.get(&"scroll_vertical", 0.0)) < float(initial.get(&"scroll_vertical", 0.0)),
		"Keyboard selection did not scroll toward P1"
	)

	var gamepad_page := InputEventJoypadButton.new()
	gamepad_page.pressed = true
	gamepad_page.button_index = JOY_BUTTON_RIGHT_SHOULDER
	_check(bool(hud.call(&"_handle_results_navigation_input", gamepad_page)), "Gamepad page navigation was not handled")
	_check(bool(hud.call(&"_handle_results_navigation_input", gamepad_page)), "Second gamepad page navigation was not handled")
	var gamepad_down := InputEventJoypadButton.new()
	gamepad_down.pressed = true
	gamepad_down.button_index = JOY_BUTTON_DPAD_DOWN
	_check(bool(hud.call(&"_handle_results_navigation_input", gamepad_down)), "Gamepad D-pad navigation was not handled")
	await get_tree().process_frame
	await get_tree().process_frame
	var gamepad := hud.get_results_navigation_snapshot()
	_check(int(gamepad.get(&"selected_index", -1)) == 11, "Gamepad navigation did not reach P12")
	_check(bool(gamepad.get(&"selected_visible", false)), "Gamepad-selected P12 row is outside the viewport")
	_check(float(gamepad.get(&"scroll_vertical", 0.0)) > float(keyboard.get(&"scroll_vertical", 0.0)), "Gamepad navigation did not scroll toward P12")

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

	print("RESULTS NAVIGATION PROBE: rows=%d player=P%d initial=%s keyboard=%s gamepad=%s max_scroll=%.0f passed=%s" % [
		int(initial.get(&"row_count", 0)),
		int(initial.get(&"player_index", -1)) + 1,
		str(bool(initial.get(&"selected_visible", false))),
		str(bool(keyboard.get(&"selected_visible", false))),
		str(bool(gamepad.get(&"selected_visible", false))),
		float(initial.get(&"maximum_scroll", 0.0)),
		str(_failures.is_empty()),
	])
	hud.queue_free()
	await get_tree().process_frame
	if _failures.is_empty():
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("RESULTS NAVIGATION PROBE: " + failure)
	get_tree().quit(1)


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


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
