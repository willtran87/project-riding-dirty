extends Node
## End-to-end sensory-accessibility contract: legacy defaults, persisted
## settings UI, camera motion, HUD flashes, particle density, and informative
## static district transitions.

const TEST_PATH := "user://tests/reduced_motion_accessibility_probe.json"
const CAMERA_SCENE := preload("res://features/camera/chase_camera.tscn")
const TRANSITION_SCENE := preload("res://features/tour/district_transition.tscn")
const HUD_SCENE := preload("res://features/hud/race_hud.tscn")
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
	_check(
		not bool(legacy_store.get_value(&"interface", &"reduced_flashes", true))
		and not bool(legacy_store.get_value(&"interface", &"reduced_particles", true)),
		"Existing settings did not default optional sensory reductions to off"
	)
	_check(
		StringName(legacy_store.get_value(&"interface", &"hud_detail", &"")) == &"FULL"
		and is_equal_approx(float(legacy_store.get_value(&"interface", &"hud_scale", 0.0)), 1.0)
		and is_zero_approx(float(legacy_store.get_value(&"interface", &"hud_safe_area", -1.0))),
		"Existing settings did not migrate to the complete 100% edge-aligned HUD"
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
	var hud := HUD_SCENE.instantiate() as RaceHud
	add_child(hud)
	var particles := GPUParticles3D.new()
	particles.name = "SensoryAccessibilityParticles"
	particles.amount = 100
	add_child(particles)
	var service := RaceServices.new()
	service.settings = legacy_store
	service.chase_camera = camera
	service.hud = hud
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
	var reduced_flashes_index := _find_setting_index(access_items, &"reduced_flashes")
	var reduced_particles_index := _find_setting_index(access_items, &"reduced_particles")
	var crash_support_index := _find_setting_index(access_items, &"crash_support_mode")
	var hud_detail_index := _find_setting_index(access_items, &"hud_detail")
	var hud_scale_index := _find_setting_index(access_items, &"hud_scale")
	var hud_safe_area_index := _find_setting_index(access_items, &"hud_safe_area")
	_check(access_items.size() == 15, "Accessibility page does not include the complete fifteen-row option set")
	_check(
		crash_support_index == 0
		and hud_detail_index == 2
		and hud_scale_index == 3
		and hud_safe_area_index == 4,
		"Crash support and HUD customization are not presented in the stable Access order"
	)
	_check(
		reduced_motion_index == 5
		and reduced_flashes_index == 6
		and reduced_particles_index == 7,
		"Sensory reduction settings are missing or presented out of order"
	)
	service.set("_settings_index", hud_detail_index)
	service.call(&"_adjust_setting", 1)
	service.set("_settings_index", hud_scale_index)
	service.call(&"_adjust_setting", -1)
	service.set("_settings_index", hud_safe_area_index)
	service.call(&"_adjust_setting", 1)
	_check(
		StringName(service.settings.get_value(&"interface", &"hud_detail", &"")) == &"FOCUSED"
		and is_equal_approx(float(service.settings.get_value(&"interface", &"hud_scale", 0.0)), 0.95)
		and is_equal_approx(float(service.settings.get_value(&"interface", &"hud_safe_area", 0.0)), 0.05),
		"Accessibility UI did not adjust HUD detail, size, and safe area independently"
	)
	service.set("_settings_index", reduced_flashes_index)
	service.call(&"_adjust_setting", 1)
	var flash_setting_reached := bool(
		service.settings.get_value(&"interface", &"reduced_flashes", false)
	)
	var hud_preferences := hud.get_hud_customization_snapshot()
	hud.call(&"_pulse_highlight")
	var highlight_overlay := hud.get("_highlight_overlay") as ColorRect
	var highlight_suppressed := (
		flash_setting_reached
		and bool(hud_preferences.get(&"reduced_flashes", false))
		and highlight_overlay != null
		and is_zero_approx(highlight_overlay.color.a)
	)
	_check(highlight_suppressed, "Reduced Flashes did not suppress the full-screen HUD pulse")
	service.set("_settings_index", reduced_flashes_index)
	service.call(&"_adjust_setting", -1)
	hud.call(&"_pulse_highlight")
	var normal_highlight_visible := highlight_overlay != null and highlight_overlay.color.a > 0.1
	_check(normal_highlight_visible, "Disabling Reduced Flashes did not restore accepted-action feedback")
	service.set("_settings_index", reduced_flashes_index)
	service.call(&"_adjust_setting", 1)
	hud.set("_flow_denied_feedback_time", 1.0)
	hud.call(&"_update_flow_denied_feedback", 0.02)
	var flow_bar := hud.get("_flow_bar") as ProgressBar
	var static_flow_color := flow_bar.modulate if flow_bar != null else Color.TRANSPARENT
	hud.call(&"_update_flow_denied_feedback", 0.12)
	_check(
		flow_bar != null and flow_bar.modulate.is_equal_approx(static_flow_color),
		"Reduced Flashes left the Flow refusal meter oscillating"
	)
	hud.call(&"_clear_flow_denied_feedback")

	service.set("_settings_index", reduced_particles_index)
	service.call(&"_adjust_setting", 1)
	var particle_snapshot := service.get_visual_quality_snapshot()
	var particles_reduced := (
		bool(service.settings.get_value(&"interface", &"reduced_particles", false))
		and bool(particle_snapshot.get(&"reduced_particles", false))
		and is_equal_approx(
			float(particle_snapshot.get(&"particle_ratio", 1.0)),
			RaceServices.REDUCED_PARTICLE_RATIO
		)
		and is_equal_approx(particles.amount_ratio, RaceServices.REDUCED_PARTICLE_RATIO)
	)
	_check(particles_reduced, "Reduced Particles did not reach the live scene budget")
	var streamed_particles := GPUParticles3D.new()
	streamed_particles.name = "StreamedSensoryAccessibilityParticles"
	streamed_particles.amount = 100
	var streamed_root := Node3D.new()
	add_child(streamed_root)
	streamed_root.add_child(streamed_particles)
	service.refresh_visual_quality(streamed_root)
	_check(
		is_equal_approx(streamed_particles.amount_ratio, RaceServices.REDUCED_PARTICLE_RATIO),
		"Reduced Particles did not reach effects streamed after the setting changed"
	)

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
	_check(
		bool(covered.get(&"sponsor_visible", false))
		and str(covered.get(&"sponsor_text", "")).contains("DUSTLINE WORKS"),
		"Reduced transition removed the text-first sponsor briefing"
	)
	await transition.reveal()
	var revealed := transition.get_motion_accessibility_snapshot()
	_check(not bool(revealed.get(&"visible", true)), "Reduced transition did not reveal the loaded district")
	_check(not bool(revealed.get(&"active_tween", true)), "Reduced reveal created a motion tween")

	var persisted := SettingsStore.new(TEST_PATH)
	_check(bool(persisted.load_from_disk().get(&"ok", false)), "Reduced Motion setting did not persist")
	_check(bool(persisted.get_value(&"interface", &"reduced_motion", false)), "Persisted Reduced Motion value was not restored")
	_check(
		bool(persisted.get_value(&"interface", &"reduced_flashes", false))
		and bool(persisted.get_value(&"interface", &"reduced_particles", false)),
		"Persisted sensory reductions were not restored"
	)
	_check(
		StringName(persisted.get_value(&"interface", &"hud_detail", &"")) == &"FOCUSED"
		and is_equal_approx(float(persisted.get_value(&"interface", &"hud_scale", 0.0)), 0.95)
		and is_equal_approx(float(persisted.get_value(&"interface", &"hud_safe_area", 0.0)), 0.05),
		"Persisted HUD preferences were not restored"
	)

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
	_check(
		bool(recovered.get_value(&"interface", &"reduced_flashes", false))
		and bool(recovered.get_value(&"interface", &"reduced_particles", false)),
		"Recovered backup lost sensory reductions"
	)
	var repaired := SettingsStore.new(TEST_PATH)
	var repaired_result := repaired.load_from_disk()
	_check(str(repaired_result.get(&"source", "")) == "primary", "Repaired settings did not reload from primary")
	_check(bool(repaired.get_value(&"interface", &"reduced_motion", false)), "Repaired primary lost Reduced Motion")
	_check(
		bool(repaired.get_value(&"interface", &"reduced_flashes", false))
		and bool(repaired.get_value(&"interface", &"reduced_particles", false)),
		"Repaired primary lost sensory reductions"
	)

	print("SENSORY ACCESSIBILITY PROBE: legacy_default=%s migrated=%s mouse=%s keyboard=%s gamepad=%s flashes=%s particles=%.2f fov=%.1f->%.1f shake_scale=%.2f static_briefing=%s persisted=%s recovery=%s passed=%s" % [
		str(legacy_default_off),
		str(bool(legacy_load.get(&"migrated", false))),
		str(mouse_reached),
		str(keyboard_reached),
		str(gamepad_reached),
		str(highlight_suppressed and normal_highlight_visible),
		float(particle_snapshot.get(&"particle_ratio", 1.0)),
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
	hud.queue_free()
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
	var legacy_interface := legacy_values["interface"] as Dictionary
	legacy_interface.erase("reduced_motion")
	legacy_interface.erase("reduced_flashes")
	legacy_interface.erase("reduced_particles")
	legacy_interface.erase("hud_detail")
	legacy_interface.erase("hud_scale")
	legacy_interface.erase("hud_safe_area")
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
