extends Node
## Deterministic contract for independent riding and camera sensitivities.

const TEST_PATH := "user://tests/control_response_settings_probe.json"
const CAMERA_SCENE := preload("res://features/camera/chase_camera.tscn")
const INPUT_BEHAVIOR_STATE := preload("res://common/input_behavior_state.gd")

var _failures: Array[String] = []
var _prior_response: Dictionary = {}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_prior_response = InputRouter.get_control_response_snapshot()
	_cleanup_test_files()
	_probe_settings_schema_and_persistence()
	_probe_preload_behavior_state()
	_probe_independent_input_response()
	_probe_activity_lock_and_record_identity()
	_probe_photo_look_response()
	Input.action_release(InputRouter.STEER_RIGHT)
	Input.action_release(InputRouter.LEAN_BACK)
	Input.action_release(InputRouter.PHOTO_LOOK_RIGHT)
	InputRouter.configure_controls(_prior_response)
	_cleanup_test_files()
	if _failures.is_empty():
		print(
			"CONTROL RESPONSE SETTINGS PROBE: PASS  //  "
			+ "steer=0.30 lean=0.90 air=0.45 preload=hold/toggle lock=stable records=separate camera=3.0x"
		)
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("CONTROL RESPONSE SETTINGS PROBE: " + failure)
	get_tree().quit(1)


func _probe_settings_schema_and_persistence() -> void:
	var store := SettingsStore.new(TEST_PATH)
	_check(
		is_equal_approx(float(store.get_value(&"controls", &"lean_sensitivity", 0.0)), 1.0)
			and is_equal_approx(float(store.get_value(&"controls", &"air_control_sensitivity", 0.0)), 1.0)
			and StringName(store.get_value(&"controls", &"preload_behavior", &"")) == &"HOLD"
			and is_equal_approx(float(store.get_value(&"camera", &"look_sensitivity", 0.0)), 1.0),
		"new response defaults are not neutral"
	)
	_check(
		not store.set_value(&"controls", &"lean_sensitivity", 0.49)
			and not store.set_value(&"controls", &"air_control_sensitivity", 1.51)
			and not store.set_value(&"controls", &"preload_behavior", &"INVALID")
			and not store.set_value(&"camera", &"look_sensitivity", 0.49),
		"invalid response values were accepted"
	)
	_check(store.set_value(&"controls", &"steering_sensitivity", 0.80), "steering sensitivity was rejected")
	_check(store.set_value(&"controls", &"lean_sensitivity", 1.25), "lean sensitivity was rejected")
	_check(store.set_value(&"controls", &"air_control_sensitivity", 0.75), "air sensitivity was rejected")
	_check(store.set_value(&"controls", &"preload_behavior", &"TOGGLE"), "toggle preload was rejected")
	_check(store.set_value(&"camera", &"look_sensitivity", 1.40), "camera sensitivity was rejected")
	_check(store.save_to_disk(), "sensitivity settings did not save through the verified store")
	var reloaded := SettingsStore.new(TEST_PATH)
	_check(bool(reloaded.load_from_disk().get("ok", false)), "sensitivity settings did not reload")
	_check(
		is_equal_approx(float(reloaded.get_value(&"controls", &"steering_sensitivity", 0.0)), 0.80)
			and is_equal_approx(float(reloaded.get_value(&"controls", &"lean_sensitivity", 0.0)), 1.25)
			and is_equal_approx(float(reloaded.get_value(&"controls", &"air_control_sensitivity", 0.0)), 0.75)
			and StringName(reloaded.get_value(&"controls", &"preload_behavior", &"")) == &"TOGGLE"
			and is_equal_approx(float(reloaded.get_value(&"camera", &"look_sensitivity", 0.0)), 1.40),
		"verified persistence changed exact response values"
	)
	var legacy_values := SettingsStore.DEFAULTS.duplicate(true)
	(legacy_values["controls"] as Dictionary).erase("lean_sensitivity")
	(legacy_values["controls"] as Dictionary).erase("air_control_sensitivity")
	(legacy_values["controls"] as Dictionary).erase("preload_behavior")
	(legacy_values["camera"] as Dictionary).erase("look_sensitivity")
	var migrated := SettingsStore._sanitize_values(legacy_values)
	_check(
		is_equal_approx(float((migrated["controls"] as Dictionary)["lean_sensitivity"]), 1.0)
			and is_equal_approx(float((migrated["controls"] as Dictionary)["air_control_sensitivity"]), 1.0)
			and StringName((migrated["controls"] as Dictionary)["preload_behavior"]) == &"HOLD"
			and is_equal_approx(float((migrated["camera"] as Dictionary)["look_sensitivity"]), 1.0),
		"legacy settings did not migrate to neutral response defaults"
	)


func _probe_preload_behavior_state() -> void:
	var state := INPUT_BEHAVIOR_STATE.new()
	state.configure(&"HOLD")
	var hold_idle: Dictionary = state.sample(false)
	var hold_press: Dictionary = state.sample(true)
	var hold_repeat: Dictionary = state.sample(true)
	var hold_release: Dictionary = state.sample(false)
	_check(
		not bool(hold_idle.get("pressed", true))
			and bool(hold_press.get("pressed", false))
			and bool(hold_press.get("just_pressed", false))
			and bool(hold_repeat.get("pressed", false))
			and not bool(hold_repeat.get("just_pressed", true))
			and bool(hold_release.get("just_released", false)),
		"Hold preload did not preserve physical press/release edges"
	)
	state.configure(&"TOGGLE")
	var toggle_press: Dictionary = state.sample(true)
	var toggle_physical_release: Dictionary = state.sample(false)
	var toggle_second_press: Dictionary = state.sample(true)
	_check(
		bool(toggle_press.get("pressed", false))
			and bool(toggle_press.get("just_pressed", false))
			and bool(toggle_physical_release.get("pressed", false))
			and not bool(toggle_physical_release.get("just_released", true))
			and not bool(toggle_second_press.get("pressed", true))
			and bool(toggle_second_press.get("just_released", false)),
		"Toggle preload did not latch through release and discharge on the next press"
	)
	state.sample(false)
	state.sample(true)
	state.reset()
	_check(not state.is_toggle_active(), "preload latch survived an explicit activity reset")


func _probe_independent_input_response() -> void:
	InputRouter.configure_controls({
		"steering_deadzone": 0.0,
		"throttle_deadzone": 0.0,
		"brake_deadzone": 0.0,
		"steering_sensitivity": 0.50,
		"lean_sensitivity": 1.50,
		"air_control_sensitivity": 0.75,
		"steering_curve": 1.0,
		"preload_behavior": &"HOLD",
	})
	Input.action_press(InputRouter.STEER_RIGHT, 0.60)
	Input.action_press(InputRouter.LEAN_BACK, 0.60)
	_check(is_equal_approx(InputRouter.get_steer(), 0.30), "ground steering sensitivity is not isolated")
	_check(is_equal_approx(InputRouter.get_air_steer(), 0.45), "air steering sensitivity is not isolated")
	_check(is_equal_approx(InputRouter.get_lean(), 0.90), "ground rider-lean sensitivity is not isolated")
	_check(is_equal_approx(InputRouter.get_air_lean(), 0.45), "air pitch sensitivity is not isolated")
	Input.action_release(InputRouter.STEER_RIGHT)
	Input.action_release(InputRouter.LEAN_BACK)


func _probe_activity_lock_and_record_identity() -> void:
	var service := RaceServices.new()
	service.settings = SettingsStore.new(TEST_PATH)
	add_child(service)
	service.settings.set_value(&"controls", &"steering_sensitivity", 0.80)
	service.settings.set_value(&"controls", &"lean_sensitivity", 1.25)
	service.settings.set_value(&"controls", &"air_control_sensitivity", 0.75)
	service.settings.set_value(&"controls", &"preload_behavior", &"HOLD")
	service.call(&"_apply_settings")
	var preferred_before := service.get_preferred_control_response()
	var signature_before := service.get_preferred_control_response_signature()
	_check(
		service.set_activity_control_response_override(preferred_before),
		"valid activity control-response lock was rejected"
	)
	service.settings.set_value(&"controls", &"steering_sensitivity", 1.20)
	service.settings.set_value(&"controls", &"lean_sensitivity", 0.70)
	service.settings.set_value(&"controls", &"air_control_sensitivity", 1.30)
	service.settings.set_value(&"controls", &"preload_behavior", &"TOGGLE")
	service.call(&"_apply_settings")
	var effective_locked := InputRouter.get_control_response_snapshot()
	_check(
		is_equal_approx(float(effective_locked[&"steering_sensitivity"]), 0.80)
			and is_equal_approx(float(effective_locked[&"lean_sensitivity"]), 1.25)
			and is_equal_approx(float(effective_locked[&"air_control_sensitivity"]), 0.75)
			and StringName(effective_locked[&"preload_behavior"]) == &"HOLD",
		"mid-activity preferences mutated the effective signed response"
	)
	var signature_after_preference := service.get_preferred_control_response_signature()
	_check(signature_before != signature_after_preference, "changed sensitivity preference kept the old signature")
	service.clear_activity_control_response_override()
	var effective_next := InputRouter.get_control_response_snapshot()
	_check(
		is_equal_approx(float(effective_next[&"steering_sensitivity"]), 1.20)
			and is_equal_approx(float(effective_next[&"lean_sensitivity"]), 0.70)
			and is_equal_approx(float(effective_next[&"air_control_sensitivity"]), 1.30)
			and StringName(effective_next[&"preload_behavior"]) == &"TOGGLE",
		"next event did not receive the newly saved response"
	)
	var base_context := {
		"event_id": &"CIRCUIT",
		"track_id": &"QUARRY",
		"route_version": 19,
		"format": &"SPRINT",
		"laps": 1,
		"bike_class": &"LITE_125",
		"difficulty": 1,
		"assist_mode": "S045_B045_L045_T045_R045",
		"transmission_mode": &"AUTOMATIC",
		"setup_id": &"BALANCED",
	}
	var first_context := base_context.duplicate(true)
	first_context["control_signature"] = signature_before
	var second_context := base_context.duplicate(true)
	second_context["control_signature"] = signature_after_preference
	_check(
		CompetitiveRunSignature.build(first_context) != CompetitiveRunSignature.build(second_context),
		"physics-affecting sensitivities still share one competitive record"
	)
	var normalized := CompetitiveRunSignature.normalize_context(second_context)
	_check(
		str(normalized.get("control_signature", "")) == signature_after_preference,
		"normalized competitive identity omitted exact control response"
	)
	service.queue_free()


func _probe_photo_look_response() -> void:
	var service := RaceServices.new()
	var camera := CAMERA_SCENE.instantiate() as ChaseCamera
	add_child(service)
	add_child(camera)
	service.chase_camera = camera
	Input.action_press(InputRouter.PHOTO_LOOK_RIGHT, 1.0)
	service.settings.set_value(&"camera", &"look_sensitivity", 0.50)
	camera.rotation = Vector3.ZERO
	service.call(&"_update_photo_camera", 1.0)
	var slow_yaw := absf(camera.rotation.y)
	service.settings.set_value(&"camera", &"look_sensitivity", 1.50)
	camera.rotation = Vector3.ZERO
	service.call(&"_update_photo_camera", 1.0)
	var fast_yaw := absf(camera.rotation.y)
	Input.action_release(InputRouter.PHOTO_LOOK_RIGHT)
	_check(
		slow_yaw > 0.1 and is_equal_approx(fast_yaw / slow_yaw, 3.0),
		"photo-camera look sensitivity did not scale rotation independently"
	)
	camera.queue_free()
	service.queue_free()


func _cleanup_test_files() -> void:
	for suffix: String in ["", SettingsStore.BACKUP_SUFFIX, SettingsStore.TEMP_SUFFIX, SettingsStore.BACKUP_TEMP_SUFFIX]:
		var path := TEST_PATH + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
