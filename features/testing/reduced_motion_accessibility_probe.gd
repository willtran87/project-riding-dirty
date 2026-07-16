extends Node
## End-to-end reduced-motion contract: legacy defaults, persisted settings UI,
## camera envelope, and non-moving but fully informative district transitions.

const TEST_PATH := "user://tests/reduced_motion_accessibility_probe.json"
const CAMERA_SCENE := preload("res://features/camera/chase_camera.tscn")
const TRANSITION_SCENE := preload("res://features/tour/district_transition.tscn")
const VERIFIED_JSON_CODEC := preload("res://common/verified_json_codec.gd")

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	Profile.persistence_enabled = false
	_cleanup_test_file()
	_write_legacy_settings_file()
	var legacy_store := SettingsStore.new(TEST_PATH)
	var legacy_load := legacy_store.load_from_disk()
	_check(bool(legacy_load.get(&"ok", false)), "Legacy version-1 settings did not load")
	var legacy_default_off := not bool(legacy_store.get_value(&"interface", &"reduced_motion", true))
	_check(
		legacy_default_off,
		"Existing settings without the field did not default Reduced Motion to off"
	)
	_check(bool(legacy_load.get(&"migrated", false)), "Legacy settings were not migrated to the verified format")
	_check(bool(legacy_load.get(&"repaired", false)), "Legacy migration did not rewrite the primary slot")
	_check(FileAccess.file_exists(TEST_PATH + SettingsStore.BACKUP_SUFFIX), "Legacy migration did not retain a rotating backup")
	var migrated_decode := _decode_settings_file(TEST_PATH, false)
	_check(bool(migrated_decode.get(&"ok", false)), "Migrated primary is not a verified JSON envelope")

	var transition := TRANSITION_SCENE.instantiate() as DistrictTransition
	add_child(transition)
	var camera := CAMERA_SCENE.instantiate() as ChaseCamera
	add_child(camera)
	var service := RaceServices.new()
	service.settings = legacy_store
	service.chase_camera = camera
	add_child(service)
	await get_tree().process_frame
	service.call(&"_apply_settings")

	var normal_camera := camera.get_motion_accessibility_snapshot()
	_check(not bool(normal_camera.get(&"reduced_motion", true)), "Camera started in Reduced Motion")
	_check(float(normal_camera.get(&"speed_fov_delta", 0.0)) >= 10.0, "Normal camera lost its established speed-FOV envelope")
	_check(not transition.is_reduced_motion_enabled(), "Transition started in Reduced Motion")

	service.set("_settings_page_index", RaceServices.SETTINGS_PAGE_IDS.find(&"ACCESS"))
	service.set("_settings_index", 0)
	service.call(&"_refresh_settings_text")
	var access_items: Array = service.get("_settings_items") as Array
	var reduced_motion_index := _find_setting_index(access_items, &"reduced_motion")
	_check(access_items.size() == 6, "Accessibility page does not include the complete six-row option set")
	_check(reduced_motion_index >= 0, "Reduced Motion is missing from the Accessibility page")

	var camera_node := camera.get_node("Camera3D") as Camera3D
	camera.apply_landing_kick(1.0)
	camera.apply_boost_punch()
	camera.begin_airtime()
	camera.apply_route_highlight("PROBE")
	camera.apply_contact_kick(1.0)
	camera_node.position = Vector3(0.2, -0.1, 0.0)
	camera_node.rotation.z = 0.2
	service.set("_settings_index", reduced_motion_index)
	service.call(&"_refresh_settings_text")
	var mouse_row := service.find_child("SettingRow%02d" % reduced_motion_index, true, false) as Button
	_check(mouse_row != null, "Reduced Motion has no mouse-selectable row")
	if mouse_row != null:
		mouse_row.pressed.emit()
	var mouse_reached := bool(service.settings.get_value(&"interface", &"reduced_motion", false))
	_check(mouse_reached, "Mouse did not enable Reduced Motion")
	_check(camera.is_reduced_motion_enabled(), "Mouse setting change did not reach the chase camera")
	_check(transition.is_reduced_motion_enabled(), "Mouse setting change did not reach the district transition")

	var reduced_camera := camera.get_motion_accessibility_snapshot()
	_check(float(reduced_camera.get(&"shake_scale", 1.0)) <= 0.10, "Reduced Motion does not substantially suppress camera shake")
	_check(float(reduced_camera.get(&"bank_scale", 1.0)) <= 0.20, "Reduced Motion does not substantially suppress camera bank")
	_check(float(reduced_camera.get(&"speed_fov_delta", 99.0)) <= 1.51, "Reduced Motion FOV range exceeds 1.5 degrees")
	_check(
		float(reduced_camera.get(&"speed_fov_delta", 99.0)) <= float(normal_camera.get(&"speed_fov_delta", 0.0)) * 0.15,
		"Reduced Motion did not materially reduce the normal FOV response"
	)
	_check((reduced_camera.get(&"camera_offset", Vector3.ONE) as Vector3).is_zero_approx(), "Enabling Reduced Motion did not settle camera shake offset")
	_check(is_zero_approx(float(reduced_camera.get(&"camera_bank_radians", 1.0))), "Enabling Reduced Motion did not settle camera bank")
	_check(float(reduced_camera.get(&"dynamic_position_scale", 0.0)) > 0.0, "Reduced Motion removed essential chase framing")
	_check(float(reduced_camera.get(&"look_ahead_scale", 0.0)) > 0.0, "Reduced Motion removed essential route look-ahead")

	await transition.cover(&"CIRCUIT")
	var covered := transition.get_motion_accessibility_snapshot()
	_check(bool(covered.get(&"visible", false)), "Reduced transition did not cover the district swap")
	_check(not bool(covered.get(&"active_tween", true)), "Reduced transition still created a motion tween")
	_check(is_equal_approx(float(covered.get(&"sweep_x", -1.0)), 0.0), "Reduced transition left the cover offscreen")
	_check(bool(covered.get(&"briefing_visible", false)), "Reduced transition removed essential event briefing feedback")
	_check(not str(covered.get(&"title", "")).is_empty(), "Reduced transition has no event title")
	await transition.reveal()
	var revealed := transition.get_motion_accessibility_snapshot()
	_check(not bool(revealed.get(&"visible", true)), "Reduced transition did not reveal the loaded district")
	_check(not bool(revealed.get(&"active_tween", true)), "Reduced reveal created a motion tween")

	var persisted := SettingsStore.new(TEST_PATH)
	_check(bool(persisted.load_from_disk().get(&"ok", false)), "Reduced Motion setting did not persist")
	_check(bool(persisted.get_value(&"interface", &"reduced_motion", false)), "Persisted Reduced Motion value was not restored")

	service.set("_settings_index", reduced_motion_index)
	service.call(&"_refresh_settings_text")
	var keyboard_confirm := InputEventKey.new()
	keyboard_confirm.pressed = true
	keyboard_confirm.physical_keycode = KEY_ENTER
	service.call(&"_handle_settings_input", keyboard_confirm)
	var keyboard_reached := not bool(service.settings.get_value(&"interface", &"reduced_motion", true))
	_check(keyboard_reached, "Keyboard did not disable Reduced Motion")
	_check(not camera.is_reduced_motion_enabled() and not transition.is_reduced_motion_enabled(), "Keyboard setting change did not propagate")

	var gamepad_confirm := InputEventJoypadButton.new()
	gamepad_confirm.pressed = true
	gamepad_confirm.button_index = JOY_BUTTON_A
	service.call(&"_handle_settings_input", gamepad_confirm)
	var gamepad_reached := bool(service.settings.get_value(&"interface", &"reduced_motion", false))
	_check(gamepad_reached, "Gamepad did not enable Reduced Motion")
	_check(camera.is_reduced_motion_enabled() and transition.is_reduced_motion_enabled(), "Gamepad setting change did not propagate")
	# Rotate a second verified copy with the same enabled value, then prove a
	# corrupt primary recovers from it and repairs itself for the next launch.
	_check(service.settings.save_to_disk(), "Could not rotate the verified Reduced Motion setting")
	var corrupt_file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	_check(corrupt_file != null, "Could not create corrupt-primary settings fixture")
	if corrupt_file != null:
		corrupt_file.store_string("{corrupt-primary")
		corrupt_file.close()
	var recovered := SettingsStore.new(TEST_PATH)
	var recovery_result := recovered.load_from_disk()
	_check(bool(recovery_result.get(&"ok", false)), "Corrupt settings primary did not recover")
	_check(str(recovery_result.get(&"source", "")) == "backup", "Settings recovery did not select the backup")
	_check(bool(recovery_result.get(&"repaired", false)), "Backup recovery did not repair the primary")
	_check(bool(recovered.get_value(&"interface", &"reduced_motion", false)), "Recovered backup lost Reduced Motion")
	var repaired := SettingsStore.new(TEST_PATH)
	var repaired_result := repaired.load_from_disk()
	_check(str(repaired_result.get(&"source", "")) == "primary", "Repaired settings did not reload from primary")
	_check(bool(repaired.get_value(&"interface", &"reduced_motion", false)), "Repaired primary lost Reduced Motion")

	print("REDUCED MOTION ACCESSIBILITY PROBE: legacy_default=%s migrated=%s mouse=%s keyboard=%s gamepad=%s fov=%.1f->%.1f shake_scale=%.2f static_briefing=%s persisted=%s recovery=%s passed=%s" % [
		str(legacy_default_off),
		str(bool(legacy_load.get(&"migrated", false))),
		str(mouse_reached),
		str(keyboard_reached),
		str(gamepad_reached),
		float(normal_camera.get(&"speed_fov_delta", 0.0)),
		float(reduced_camera.get(&"speed_fov_delta", 0.0)),
		float(reduced_camera.get(&"shake_scale", 1.0)),
		str(bool(covered.get(&"briefing_visible", false))),
		str(bool(persisted.get_value(&"interface", &"reduced_motion", false))),
		str(str(recovery_result.get(&"source", "")) == "backup" and bool(recovery_result.get(&"repaired", false))),
		str(_failures.is_empty()),
	])

	service.queue_free()
	camera.queue_free()
	transition.queue_free()
	await get_tree().process_frame
	_cleanup_test_file()
	if _failures.is_empty():
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("REDUCED MOTION ACCESSIBILITY PROBE: " + failure)
	get_tree().quit(1)


func _find_setting_index(items: Array, key: StringName) -> int:
	for index: int in items.size():
		if items[index] is Dictionary and StringName((items[index] as Dictionary).get(&"key", &"")) == key:
			return index
	return -1


func _write_legacy_settings_file() -> void:
	var absolute := ProjectSettings.globalize_path(TEST_PATH)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var legacy_values := SettingsStore.DEFAULTS.duplicate(true)
	(legacy_values["interface"] as Dictionary).erase("reduced_motion")
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	if file == null:
		_failures.append("Could not create legacy settings fixture")
		return
	file.store_string(JSON.stringify({"version": SettingsStore.SETTINGS_VERSION, "values": legacy_values}, "\t"))
	file.close()


func _decode_settings_file(path: String, allow_legacy: bool) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "missing"}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "file_open_failed"}
	var raw := file.get_as_text()
	file.close()
	return VERIFIED_JSON_CODEC.decode(raw, allow_legacy)


func _cleanup_test_file() -> void:
	for suffix: String in ["", SettingsStore.TEMP_SUFFIX, SettingsStore.BACKUP_SUFFIX, SettingsStore.BACKUP_TEMP_SUFFIX]:
		var path := TEST_PATH + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
