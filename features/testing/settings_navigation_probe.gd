extends Node
## Deterministic contract for bidirectional mouse adjustment and long-page
## keyboard/gamepad visibility at the largest supported interface scale.

const TEST_PATH := "user://tests/settings_navigation_probe.json"

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_cleanup_test_file()
	var service := RaceServices.new()
	service.settings = SettingsStore.new(TEST_PATH)
	add_child(service)
	await get_tree().process_frame
	var panel := service.get("_settings_panel") as PanelContainer
	var backdrop := service.get("_settings_backdrop") as ColorRect
	panel.visible = true
	backdrop.visible = true
	service.set("_settings_open", true)

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
	var keyboard_down := InputEventKey.new()
	keyboard_down.pressed = true
	keyboard_down.physical_keycode = KEY_DOWN
	service.call(&"_handle_settings_input", keyboard_down)
	await get_tree().process_frame
	await get_tree().process_frame
	var keyboard_navigation := service.get_settings_navigation_snapshot()
	_check(int(keyboard_navigation.get(&"row_count", 0)) == input_row_count, "Input page does not expose every remappable action")
	_check(int(keyboard_navigation.get(&"selected_index", -1)) == input_row_count - 1, "Keyboard Down did not select the final Input row")
	_check(bool(keyboard_navigation.get(&"selected_visible", false)), "Keyboard-selected final Input row is outside the viewport")
	_check(float(keyboard_navigation.get(&"scroll_vertical", 0.0)) > 0.0, "Keyboard navigation did not scroll the long Input page")
	_check(float(keyboard_navigation.get(&"selected_row_height", 0.0)) >= 52.0, "Rows are too short for 175% text")

	service.set("_settings_index", input_row_count - 2)
	service.call(&"_refresh_settings_text")
	var gamepad_down := InputEventJoypadButton.new()
	gamepad_down.pressed = true
	gamepad_down.button_index = JOY_BUTTON_DPAD_DOWN
	service.call(&"_handle_settings_input", gamepad_down)
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
		touch_decrement != null and touch_decrement.custom_minimum_size.x >= 112.0 and touch_decrement.custom_minimum_size.y >= 112.0,
		"Touch settings adjustment targets are below 112 authored pixels"
	)

	print("SETTINGS NAVIGATION PROBE: mouse=%s keyboard=%s gamepad=%s touch=%s rows=%d max_scroll=%.0f passed=%s" % [
		str(bool(audio_navigation.get(&"has_decrement", false)) and bool(audio_navigation.get(&"has_increment", false))),
		str(bool(keyboard_navigation.get(&"selected_visible", false))),
		str(bool(gamepad_navigation.get(&"selected_visible", false))),
		str(bool(touch_navigation.get(&"touch_sized", false))),
		int(keyboard_navigation.get(&"row_count", 0)),
		float(keyboard_navigation.get(&"maximum_scroll", 0.0)),
		str(_failures.is_empty()),
	])
	service.queue_free()
	await get_tree().process_frame
	_cleanup_test_file()
	if _failures.is_empty():
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("SETTINGS NAVIGATION PROBE: " + failure)
	get_tree().quit(1)


func _cleanup_test_file() -> void:
	for suffix: String in ["", SettingsStore.TEMP_SUFFIX, SettingsStore.BACKUP_SUFFIX, SettingsStore.BACKUP_TEMP_SUFFIX]:
		var path := TEST_PATH + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
