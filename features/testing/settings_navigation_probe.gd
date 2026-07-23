extends Node
## Deterministic contract for bidirectional mouse adjustment and long-page
## keyboard/gamepad visibility at the largest supported interface scale.

const TEST_PATH := "user://tests/settings_navigation_probe.json"
const REBOUND_ACTIONS: Array[StringName] = [
	InputRouter.EVENT_PREVIOUS,
	InputRouter.EVENT_NEXT,
	InputRouter.MENU_LEFT,
	InputRouter.MENU_RIGHT,
	InputRouter.PAGE_PREVIOUS,
	InputRouter.PAGE_NEXT,
	InputRouter.CONFIRM,
	InputRouter.RESET_SETTING,
	InputRouter.RESET_ALL_SETTINGS,
]
const REBOUND_KEYS: Dictionary = {
	InputRouter.EVENT_PREVIOUS: KEY_Z,
	InputRouter.EVENT_NEXT: KEY_X,
	InputRouter.MENU_LEFT: KEY_J,
	InputRouter.MENU_RIGHT: KEY_L,
	InputRouter.PAGE_PREVIOUS: KEY_U,
	InputRouter.PAGE_NEXT: KEY_O,
	InputRouter.CONFIRM: KEY_K,
	InputRouter.RESET_SETTING: KEY_N,
	InputRouter.RESET_ALL_SETTINGS: KEY_M,
}
const REBOUND_BUTTONS: Dictionary = {
	InputRouter.EVENT_PREVIOUS: JOY_BUTTON_LEFT_STICK,
	InputRouter.EVENT_NEXT: JOY_BUTTON_RIGHT_STICK,
	InputRouter.MENU_LEFT: JOY_BUTTON_LEFT_SHOULDER,
	InputRouter.MENU_RIGHT: JOY_BUTTON_RIGHT_SHOULDER,
	InputRouter.PAGE_PREVIOUS: JOY_BUTTON_X,
	InputRouter.PAGE_NEXT: JOY_BUTTON_Y,
	InputRouter.CONFIRM: JOY_BUTTON_START,
	InputRouter.RESET_SETTING: JOY_BUTTON_DPAD_LEFT,
	InputRouter.RESET_ALL_SETTINGS: JOY_BUTTON_DPAD_RIGHT,
}

var _failures: Array[String] = []
var _action_snapshots: Dictionary = {}
var _prior_input_mode: StringName = &""
var _interface_feedback: Array[Dictionary] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_cleanup_test_file()
	if not EventBus.interface_feedback_requested.is_connected(_on_interface_feedback_requested):
		EventBus.interface_feedback_requested.connect(_on_interface_feedback_requested)
	_prior_input_mode = InputRouter.input_mode
	_snapshot_actions()
	_apply_rebound_bindings()
	InputRouter.call(&"_set_input_mode", InputRouter.INPUT_MODE_KEYBOARD_MOUSE)
	var service := RaceServices.new()
	var modal_hud := Node.new()
	modal_hud.set_process_unhandled_input(true)
	service.settings = SettingsStore.new(TEST_PATH)
	add_child(modal_hud)
	add_child(service)
	service.hud = modal_hud
	await get_tree().process_frame
	var panel := service.get("_settings_panel") as PanelContainer
	var backdrop := service.get("_settings_backdrop") as ColorRect
	panel.visible = true
	backdrop.visible = true
	service.set("_settings_open", true)
	service.call(&"_refresh_hud_input_ownership")
	_check(not modal_hud.is_processing_unhandled_input(), "Settings overlay did not suspend underlying HUD input")

	service.set("_settings_page_index", RaceServices.SETTINGS_PAGE_IDS.find(&"AUDIO"))
	service.set("_settings_index", 0)
	service.call(&"_refresh_settings_text")
	await get_tree().process_frame
	var audio_navigation := service.get_settings_navigation_snapshot()
	_check(bool(audio_navigation.get(&"has_decrement", false)), "Master volume has no mouse decrement control")
	_check(bool(audio_navigation.get(&"has_increment", false)), "Master volume has no mouse increment control")
	var decrement := service.find_child("SettingDecrease00", true, false) as Button
	_check(decrement != null, "Master volume decrement button is not discoverable")
	if decrement != null:
		decrement.pressed.emit()
	_check(
		is_equal_approx(float(service.settings.get_value(&"audio", &"master_volume", 0.0)), 0.95),
		"Mouse decrement did not lower Master volume by 5%"
	)
	var increment := service.find_child("SettingIncrease00", true, false) as Button
	_check(increment != null, "Master volume increment button is not discoverable after refresh")
	if increment != null:
		increment.pressed.emit()
	_check(
		is_equal_approx(float(service.settings.get_value(&"audio", &"master_volume", 0.0)), 1.0),
		"Mouse increment did not restore Master volume"
	)

	service.set("_settings_index", 0)
	service.call(&"_refresh_settings_text")
	var keyboard_footer := service.get_settings_navigation_snapshot()
	_check_settings_footer(keyboard_footer, InputRouter.INPUT_MODE_KEYBOARD_MOUSE, "keyboard")
	var old_keyboard_down := _key_event(KEY_DOWN)
	service.call(&"_handle_settings_input", old_keyboard_down)
	_check(int(service.get("_settings_index")) == 0, "Removed keyboard Down default still moved the Settings selection")
	service.call(&"_handle_settings_input", _key_event(KEY_X))
	_check(int(service.get("_settings_index")) == 1, "Rebound keyboard Next action did not move the Settings selection")
	service.call(&"_handle_settings_input", _key_event(KEY_Z, true))
	_check(int(service.get("_settings_index")) == 0, "Echoed rebound Previous action did not repeat Settings navigation")

	service.set("_settings_index", 0)
	service.call(&"_refresh_settings_text")
	_check(service.settings.set_value(&"audio", &"master_volume", 0.55), "Could not stage Master volume for echo tests")
	service.call(&"_handle_settings_input", _key_event(KEY_J, true))
	_check(
		is_equal_approx(float(service.settings.get_value(&"audio", &"master_volume", 0.0)), 0.5),
		"Echoed rebound Decrease action did not repeat a safe value adjustment"
	)
	service.call(&"_handle_settings_input", _key_event(KEY_N, true))
	_check(
		is_equal_approx(float(service.settings.get_value(&"audio", &"master_volume", 0.0)), 0.5),
		"Echoed Reset Setting destructively changed the selected value"
	)
	service.call(&"_handle_settings_input", _key_event(KEY_N))
	_check(
		is_equal_approx(float(service.settings.get_value(&"audio", &"master_volume", 0.0)), 1.0),
		"Non-echo rebound Reset Setting did not restore the selected value"
	)
	service.call(&"_handle_settings_input", _key_event(KEY_O, true))
	_check(
		StringName(service.get_settings_navigation_snapshot().get(&"page", &"")) == &"RIDE",
		"Echoed rebound Next Page action did not repeat safe page navigation"
	)
	service.set("_settings_page_index", RaceServices.SETTINGS_PAGE_IDS.find(&"RIDE"))
	service.set("_settings_index", 0)
	service.call(&"_refresh_settings_text")
	service.call(&"_handle_settings_input", _key_event(KEY_U))
	_check(
		StringName(service.get_settings_navigation_snapshot().get(&"page", &"")) == &"AUDIO",
		"Rebound Previous Page action did not return to Audio"
	)

	_check(service.settings.set_value(&"interface", &"text_scale", 1.75), "Could not set maximum text scale")
	service.set("_settings_page_index", RaceServices.SETTINGS_PAGE_IDS.find(&"INPUT"))
	service.call(&"_refresh_settings_text")
	var input_items: Array = service.get("_settings_items") as Array
	var input_row_count := input_items.size()
	_check(
		input_row_count == RaceServices.REBINDABLE_ACTIONS.size() + 4,
		"Input page does not expose touch settings and every remappable action"
	)
	service.set("_settings_index", input_row_count - 2)
	service.call(&"_refresh_settings_text")
	service.call(&"_handle_settings_input", old_keyboard_down)
	_check(int(service.get("_settings_index")) == input_row_count - 2, "Removed keyboard Down default moved the long Input page")
	service.call(&"_handle_settings_input", _key_event(KEY_X))
	await get_tree().process_frame
	await get_tree().process_frame
	var keyboard_navigation := service.get_settings_navigation_snapshot()
	_check(int(keyboard_navigation.get(&"row_count", 0)) == input_row_count, "Input page does not expose every remappable action")
	_check(int(keyboard_navigation.get(&"selected_index", -1)) == input_row_count - 1, "Keyboard Down did not select the final Input row")
	_check(bool(keyboard_navigation.get(&"selected_visible", false)), "Keyboard-selected final Input row is outside the viewport")
	_check(float(keyboard_navigation.get(&"scroll_vertical", 0.0)) > 0.0, "Keyboard navigation did not scroll the long Input page")
	_check(float(keyboard_navigation.get(&"selected_row_height", 0.0)) >= 52.0, "Rows are too short for 175% text")
	_check(
		(keyboard_navigation.get(&"panel_size", Vector2.ZERO) as Vector2).x <= 1080.5,
		"Long Input bindings force the Settings panel wider than its authored 1080 pixels"
	)
	_check(bool(keyboard_navigation.get(&"close_inside_panel", false)), "Settings Close button escapes the panel at maximum text scale")

	service.set("_settings_index", input_row_count - 2)
	service.call(&"_refresh_settings_text")
	InputRouter.call(&"_set_input_mode", InputRouter.INPUT_MODE_GAMEPAD)
	service.call(&"_refresh_settings_text")
	var gamepad_footer := service.get_settings_navigation_snapshot()
	_check_settings_footer(gamepad_footer, InputRouter.INPUT_MODE_GAMEPAD, "gamepad")
	var old_gamepad_down := _button_event(JOY_BUTTON_DPAD_DOWN)
	service.call(&"_handle_settings_input", old_gamepad_down)
	_check(int(service.get("_settings_index")) == input_row_count - 2, "Removed D-pad Down default moved the Settings selection")
	service.call(&"_handle_settings_input", _button_event(JOY_BUTTON_RIGHT_STICK))
	await get_tree().process_frame
	await get_tree().process_frame
	var gamepad_navigation := service.get_settings_navigation_snapshot()
	_check(int(gamepad_navigation.get(&"selected_index", -1)) == input_row_count - 1, "Gamepad D-pad Down did not select the final Input row")
	_check(bool(gamepad_navigation.get(&"selected_visible", false)), "Gamepad-selected final Input row is outside the viewport")

	service.set("_settings_index", 0)
	service.call(&"_refresh_settings_text")
	await get_tree().process_frame
	await get_tree().process_frame
	var top_navigation := service.get_settings_navigation_snapshot()
	_check(bool(top_navigation.get(&"selected_visible", false)), "Returning to the first Input row did not reveal it")
	_check(
		float(top_navigation.get(&"scroll_vertical", 0.0)) < float(gamepad_navigation.get(&"scroll_vertical", 0.0)),
		"Selection visibility did not scroll back toward the top"
	)

	var confirm_index := 4 + RaceServices.REBINDABLE_ACTIONS.find(InputRouter.CONFIRM)
	_check(confirm_index >= 4, "Confirm action is absent from the Input settings page")
	if confirm_index >= 4:
		service.set("_settings_index", confirm_index)
		InputRouter.call(&"_set_input_mode", InputRouter.INPUT_MODE_KEYBOARD_MOUSE)
		service.call(&"_refresh_settings_text")
		var binding_row := service.get_settings_navigation_snapshot()
		var binding_text := str(binding_row.get(&"selected_row_text", ""))
		_check(binding_text.contains("K") and binding_text.contains("START"), "Input row omitted rebound keyboard/gamepad Confirm labels")
		service.call(&"_handle_settings_input", _key_event(KEY_K, true))
		_check(StringName(service.get("_capture_action")).is_empty(), "Echoed Confirm entered destructive binding capture")
		service.call(&"_handle_settings_input", _key_event(KEY_K))
		_check(StringName(service.get("_capture_action")) == InputRouter.CONFIRM, "Rebound keyboard Confirm did not enter binding capture")
		service.call(&"_handle_settings_input", _key_event(KEY_ESCAPE))
		_check(StringName(service.get("_capture_action")).is_empty(), "Escape did not cancel binding capture")
		_check(bool(service.get("_settings_open")), "Escape closed Settings instead of cancelling active capture")
		InputRouter.call(&"_set_input_mode", InputRouter.INPUT_MODE_GAMEPAD)
		service.call(&"_handle_settings_input", _button_event(JOY_BUTTON_START))
		_check(StringName(service.get("_capture_action")) == InputRouter.CONFIRM, "Rebound gamepad Confirm did not enter binding capture")
		service.call(&"_handle_settings_input", _button_event(JOY_BUTTON_B))
		_check(StringName(service.get("_capture_action")).is_empty(), "Gamepad B did not cancel binding capture")
		_check(bool(service.get("_settings_open")), "Gamepad B closed Settings instead of cancelling active capture")

	InputRouter.note_touch_input()
	service.set("_settings_page_index", RaceServices.SETTINGS_PAGE_IDS.find(&"AUDIO"))
	service.set("_settings_index", 0)
	service.call(&"_refresh_settings_text")
	await get_tree().process_frame
	var touch_navigation := service.get_settings_navigation_snapshot()
	var touch_decrement := service.find_child("SettingDecrease00", true, false) as Button
	_check(bool(touch_navigation.get(&"touch_sized", false)), "Touch input did not enable compact-stage settings targets")
	_check(float(touch_navigation.get(&"selected_row_height", 0.0)) >= 112.0, "Touch settings rows are below 112 authored pixels")
	_check((touch_navigation.get(&"close_target_size", Vector2.ZERO) as Vector2).y >= 112.0, "Touch settings Close target is below 112 authored pixels")
	_check((touch_navigation.get(&"tab_target_size", Vector2.ZERO) as Vector2).y >= 112.0, "Touch settings tabs are below 112 authored pixels")
	_check(
		(touch_navigation.get(&"panel_size", Vector2.ZERO) as Vector2).x <= 1080.5,
		"Touch settings force the Settings panel wider than its authored 1080 pixels"
	)
	_check(bool(touch_navigation.get(&"close_inside_panel", false)), "Touch-sized Close button escapes the Settings panel")
	_check(
		touch_decrement != null and touch_decrement.custom_minimum_size.x >= 112.0 and touch_decrement.custom_minimum_size.y >= 112.0,
		"Touch settings adjustment targets are below 112 authored pixels"
	)

	service.call(&"_handle_settings_input", _key_event(KEY_ESCAPE))
	_check(not bool(service.get("_settings_open")), "Escape safety fallback did not close Settings")
	_check(modal_hud.is_processing_unhandled_input(), "Settings close did not restore underlying HUD input")
	service.call(&"_toggle_settings")
	_check(not modal_hud.is_processing_unhandled_input(), "Reopened Settings did not reacquire modal HUD input")
	service.call(&"_handle_settings_input", _button_event(JOY_BUTTON_B))
	_check(not bool(service.get("_settings_open")), "Gamepad B safety fallback did not close Settings")
	_check(modal_hud.is_processing_unhandled_input(), "Gamepad Settings close did not restore HUD input")
	_check(_has_interface_feedback(&"NAVIGATE", &"SETTINGS_VALUE"), "Mouse/keyboard value adjustment emitted no navigation feedback")
	_check(_has_interface_feedback(&"NAVIGATE", &"SETTINGS_SELECTION"), "Keyboard/gamepad selection emitted no navigation feedback")
	_check(_has_interface_feedback(&"NAVIGATE", &"SETTINGS_PAGE"), "Settings page change emitted no navigation feedback")
	_check(_has_interface_feedback(&"CONFIRM", &"SETTINGS_RESET"), "Settings reset emitted no confirmation feedback")
	_check(_has_interface_feedback(&"CANCEL", &"SETTINGS_BINDING"), "Binding cancellation emitted no cancel feedback")
	_check(_has_interface_feedback(&"CONFIRM", &"SETTINGS_VISIBILITY"), "Opening Settings emitted no confirmation feedback")
	_check(_has_interface_feedback(&"CANCEL", &"SETTINGS_VISIBILITY"), "Closing Settings emitted no cancel feedback")

	print("SETTINGS NAVIGATION PROBE: mouse=%s keyboard=%s gamepad=%s touch=%s rows=%d max_scroll=%.0f feedback=%d passed=%s" % [
		str(bool(audio_navigation.get(&"has_decrement", false)) and bool(audio_navigation.get(&"has_increment", false))),
		str(bool(keyboard_navigation.get(&"selected_visible", false))),
		str(bool(gamepad_navigation.get(&"selected_visible", false))),
		str(bool(touch_navigation.get(&"touch_sized", false))),
		int(keyboard_navigation.get(&"row_count", 0)),
		float(keyboard_navigation.get(&"maximum_scroll", 0.0)),
		_interface_feedback.size(),
		str(_failures.is_empty()),
	])
	service.queue_free()
	modal_hud.queue_free()
	await get_tree().process_frame
	_restore_actions()
	for action: StringName in REBOUND_ACTIONS:
		_check(_action_matches_snapshot(action), "%s InputMap entry was not restored exactly" % String(action))
	InputRouter.call(&"_set_input_mode", _prior_input_mode)
	_check(InputRouter.input_mode == _prior_input_mode, "Prior input mode was not restored")
	_cleanup_test_file()
	if _failures.is_empty():
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("SETTINGS NAVIGATION PROBE: " + failure)
	get_tree().quit(1)


func _on_interface_feedback_requested(kind: StringName, context: StringName) -> void:
	_interface_feedback.append({&"kind": kind, &"context": context})


func _has_interface_feedback(kind: StringName, context: StringName) -> bool:
	for entry: Dictionary in _interface_feedback:
		if StringName(entry.get(&"kind", &"")) == kind and StringName(entry.get(&"context", &"")) == context:
			return true
	return false


func _cleanup_test_file() -> void:
	for suffix: String in ["", SettingsStore.TEMP_SUFFIX, SettingsStore.BACKUP_SUFFIX, SettingsStore.BACKUP_TEMP_SUFFIX]:
		var path := TEST_PATH + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


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


func _check_settings_footer(snapshot: Dictionary, mode: StringName, device_label: String) -> void:
	var footer := str(snapshot.get(&"footer_text", ""))
	var expected_labels: Array[String] = [
		InputRouter.get_action_pair_label(InputRouter.PAGE_PREVIOUS, InputRouter.PAGE_NEXT, mode),
		InputRouter.get_action_pair_label(InputRouter.EVENT_PREVIOUS, InputRouter.EVENT_NEXT, mode),
		InputRouter.get_action_pair_label(InputRouter.MENU_LEFT, InputRouter.MENU_RIGHT, mode),
		InputRouter.get_action_label(InputRouter.CONFIRM, mode, 2),
		InputRouter.get_action_label(InputRouter.RESET_SETTING, mode, 2),
		InputRouter.get_action_label(InputRouter.RESET_ALL_SETTINGS, mode, 2),
	]
	for expected: String in expected_labels:
		_check(
			footer.contains(expected),
			"Settings footer omitted rebound %s label %s" % [device_label, expected]
		)
	_check(
		StringName(snapshot.get(&"input_mode", &"")) == mode,
		"Settings snapshot did not report %s prompt mode" % device_label
	)


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
