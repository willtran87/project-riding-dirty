extends Node
## Deterministic contract for the production settings surface and dual-device rebinding.

const TEST_PATH := "user://tests/production_settings_probe.json"

var _passed := true


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_cleanup_test_file()
	var service := RaceServices.new()
	service.settings = SettingsStore.new(TEST_PATH)
	add_child(service)
	await get_tree().process_frame
	service.call(&"_snapshot_default_bindings")

	service.set("_settings_page_index", RaceServices.SETTINGS_PAGE_IDS.find(&"AUDIO"))
	service.call(&"_refresh_settings_text")
	var audio_items: Array = service.get("_settings_items") as Array
	_check(audio_items.size() == 3, "audio page must expose Master, Music, and Engine + Effects")
	service.set("_settings_index", 0)
	service.call(&"_adjust_setting", -1)
	_check(is_equal_approx(float(service.settings.get_value(&"audio", &"master_volume", 0.0)), 0.95), "master volume did not change in 5% steps")

	service.set("_settings_page_index", RaceServices.SETTINGS_PAGE_IDS.find(&"RIDE"))
	service.call(&"_refresh_settings_text")
	var ride_items: Array = service.get("_settings_items") as Array
	_check(ride_items.size() >= 7, "ride page is missing deadzones or feedback controls")
	_check(ride_items[0].get(&"key", &"") == &"steering_deadzone", "steering deadzone is not player-facing")
	var difficulty_index := -1
	for index: int in ride_items.size():
		if StringName((ride_items[index] as Dictionary).get(&"key", &"")) == &"race_difficulty":
			difficulty_index = index
			break
	_check(difficulty_index >= 0, "ride page is missing race difficulty")
	if difficulty_index >= 0:
		var active_race := RaceController.new()
		active_race.state = RaceController.State.RACING
		service.race = active_race
		service.set("_settings_index", difficulty_index)
		service.call(&"_adjust_setting", 1)
		_check(
			String(service.get("_settings_message")).contains("APPLIES NEXT EVENT"),
			"an in-race difficulty change did not explain its deferred activation"
		)
		service.race = null
		active_race.free()

	service.set("_settings_page_index", RaceServices.SETTINGS_PAGE_IDS.find(&"INPUT"))
	service.call(&"_refresh_settings_text")
	var input_items: Array = service.get("_settings_items") as Array
	var touch_setting_keys: Array[StringName] = [
		&"touch_controls", &"touch_handedness", &"touch_control_scale", &"touch_control_opacity",
	]
	_check(
		input_items.size() == RaceServices.REBINDABLE_ACTIONS.size() + touch_setting_keys.size(),
		"Input page does not expose touch settings and every remappable action"
	)
	for index: int in touch_setting_keys.size():
		_check(
			StringName(input_items[index].get(&"key", &"")) == touch_setting_keys[index],
			"Input page touch setting order is unstable"
		)
	var binding_count := 0
	for item: Dictionary in input_items:
		if StringName(item.get(&"kind", &"")) == &"BINDING":
			binding_count += 1
	_check(binding_count == RaceServices.REBINDABLE_ACTIONS.size(), "core race actions are not all remappable")

	var replacement := InputEventKey.new()
	replacement.physical_keycode = KEY_F10
	service.call(&"_commit_captured_binding", InputRouter.THROTTLE, replacement)
	var throttle_events := InputMap.action_get_events(InputRouter.THROTTLE)
	_check(_has_physical_key(throttle_events, KEY_F10), "keyboard throttle replacement was not applied")
	_check(not _has_physical_key(throttle_events, KEY_W), "keyboard rebind retained the replaced key")
	_check(_has_gamepad_axis(throttle_events), "keyboard rebind discarded the gamepad throttle binding")

	service.call(&"_restore_default_binding", InputRouter.THROTTLE)
	_check(_has_physical_key(InputMap.action_get_events(InputRouter.THROTTLE), KEY_W), "per-action reset did not restore the default key")
	service.call(&"_reset_all_settings")
	_check(is_equal_approx(float(service.settings.get_value(&"audio", &"master_volume", 0.0)), 1.0), "reset all did not restore audio defaults")

	var panel := service.get("_settings_panel") as PanelContainer
	var rows: Array = service.get("_settings_row_buttons") as Array
	_check(panel != null and panel.offset_right - panel.offset_left >= 1000.0, "settings panel is not production-sized")
	_check(not rows.is_empty(), "settings surface did not build mouse-selectable rows")
	_check(service.settings.save_to_disk(), "settings did not persist atomically")
	var restored := SettingsStore.new(TEST_PATH)
	_check(bool(restored.load_from_disk().get("ok", false)), "persisted settings did not reload")

	print("PRODUCTION SETTINGS PROBE: pages=%d bindings=%d dual_device=%s persisted=%s passed=%s" % [
		RaceServices.SETTINGS_PAGE_IDS.size(), binding_count, str(_has_gamepad_axis(InputMap.action_get_events(InputRouter.THROTTLE))),
		str(FileAccess.file_exists(TEST_PATH)), str(_passed),
	])
	service.queue_free()
	await get_tree().process_frame
	_cleanup_test_file()
	get_tree().quit(0 if _passed else 1)


func _has_physical_key(events: Array[InputEvent], keycode: Key) -> bool:
	for event: InputEvent in events:
		if event is InputEventKey and (event as InputEventKey).physical_keycode == keycode:
			return true
	return false


func _has_gamepad_axis(events: Array[InputEvent]) -> bool:
	for event: InputEvent in events:
		if event is InputEventJoypadMotion:
			return true
	return false


func _cleanup_test_file() -> void:
	for suffix: String in ["", SettingsStore.TEMP_SUFFIX, SettingsStore.BACKUP_SUFFIX, SettingsStore.BACKUP_TEMP_SUFFIX]:
		var path := TEST_PATH + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_passed = false
	push_error("PRODUCTION SETTINGS PROBE: %s" % message)
