extends Node
## Deterministic contract for persistent, live-switchable riding camera profiles.

const CAMERA_SCENE := preload("res://features/camera/chase_camera.tscn")
const BIKE_SCENE := preload("res://entities/bike/bike.tscn")
const TEST_PATH := "user://tests/camera_modes_probe.json"

var _passed := true


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_cleanup()
	var target := Node3D.new()
	target.name = "CameraProbeTarget"
	add_child(target)
	var camera := CAMERA_SCENE.instantiate() as ChaseCamera
	add_child(camera)
	camera.target = target
	await get_tree().process_frame

	_check(ChaseCamera.VIEW_MODES.size() == 5, "camera catalog does not expose five authored riding views")
	_check(camera.get_view_mode() == ChaseCamera.VIEW_CHASE, "camera does not start in the readable Chase view")
	var seen_positions: Dictionary = {}
	var previous_fov := 0.0
	for mode: StringName in ChaseCamera.VIEW_MODES:
		camera.set_view_preferences(mode)
		camera.snap_to_target()
		var snapshot := camera.get_view_preferences_snapshot()
		var position := camera.global_position
		_check(StringName(snapshot.get(&"effective_mode", &"")) == mode, "effective profile drifted for %s" % mode)
		_check(not str(snapshot.get(&"label", "")).is_empty(), "camera profile %s has no player-facing label" % mode)
		_check(_vector_is_finite(position), "camera profile %s produced a non-finite position" % mode)
		_check(float(snapshot.get(&"stiffness_scale", 0.0)) >= 0.60, "camera stiffness is outside its safe range")
		var fov := float(snapshot.get(&"base_fov", 0.0))
		_check(fov >= previous_fov, "camera profile FOV ordering is unstable at %s" % mode)
		previous_fov = fov
		seen_positions[str(position.snapped(Vector3.ONE * 0.01))] = true
	_check(seen_positions.size() == ChaseCamera.VIEW_MODES.size(), "authored camera views collapse to duplicate framing")

	camera.set_view_preferences(ChaseCamera.VIEW_CHASE, 1.35, 0.75, 1.50)
	var personalized := camera.get_view_preferences_snapshot()
	_check(is_equal_approx(float(personalized.get(&"follow_distance", 0.0)), 6.75), "distance preference does not reach framing")
	_check(is_equal_approx(float(personalized.get(&"follow_height", 0.0)), 1.5375), "height preference does not reach framing")
	_check(is_equal_approx(float(personalized.get(&"stiffness_scale", 0.0)), 1.50), "stiffness preference does not reach response")

	camera.set_view_preferences(ChaseCamera.VIEW_HANDLEBAR)
	camera.set_view_override(ChaseCamera.VIEW_CHASE)
	var garage_override := camera.get_view_preferences_snapshot()
	_check(StringName(garage_override.get(&"mode", &"")) == ChaseCamera.VIEW_HANDLEBAR, "Garage override destroyed the preferred view")
	_check(StringName(garage_override.get(&"effective_mode", &"")) == ChaseCamera.VIEW_CHASE, "Garage override did not restore chase framing")
	camera.set_view_override()
	_check(camera.get_effective_view_mode() == ChaseCamera.VIEW_HANDLEBAR, "riding view did not return after clearing the Garage override")
	_check(camera.cycle_view_mode() == ChaseCamera.VIEW_CHASE, "camera cycle does not wrap from Handlebar to Chase")

	var store := SettingsStore.new(TEST_PATH)
	_check(store.set_value(&"camera", &"mode", &"FIRST_PERSON"), "camera mode setting was rejected")
	_check(store.set_value(&"camera", &"distance_scale", 1.25), "camera distance setting was rejected")
	_check(store.set_value(&"camera", &"height_scale", 0.85), "camera height setting was rejected")
	_check(store.set_value(&"camera", &"stiffness_scale", 1.40), "camera stiffness setting was rejected")
	_check(store.save_to_disk(), "camera preferences did not save atomically")
	var restored := SettingsStore.new(TEST_PATH)
	_check(bool(restored.load_from_disk().get(&"ok", false)), "camera preferences did not reload")
	_check(StringName(restored.get_value(&"camera", &"mode", &"")) == ChaseCamera.VIEW_FIRST_PERSON, "camera mode did not persist")
	_check(is_equal_approx(float(restored.get_value(&"camera", &"distance_scale", 0.0)), 1.25), "camera distance did not persist")
	_check(is_equal_approx(float(restored.get_value(&"camera", &"height_scale", 0.0)), 0.85), "camera height did not persist")
	_check(is_equal_approx(float(restored.get_value(&"camera", &"stiffness_scale", 0.0)), 1.40), "camera stiffness did not persist")

	var service := RaceServices.new()
	service.settings = restored
	service.chase_camera = camera
	add_child(service)
	await get_tree().process_frame
	service.call(&"_apply_settings")
	var applied := camera.get_view_preferences_snapshot()
	_check(StringName(applied.get(&"mode", &"")) == ChaseCamera.VIEW_FIRST_PERSON, "Settings did not apply the persisted camera mode")
	_check(is_equal_approx(float(applied.get(&"distance_scale", 0.0)), 1.25), "Settings did not apply camera distance")
	service.set("_settings_page_index", RaceServices.SETTINGS_PAGE_IDS.find(&"CAMERA"))
	service.call(&"_refresh_settings_text")
	var camera_items: Array = service.get("_settings_items") as Array
	var expected_keys: Array[StringName] = [
		&"visual_quality", &"mode", &"distance_scale", &"height_scale",
		&"stiffness_scale", &"fov_degrees", &"shake_intensity",
	]
	_check(camera_items.size() == expected_keys.size(), "Camera page does not expose the complete preference set")
	for index: int in mini(camera_items.size(), expected_keys.size()):
		_check(StringName(camera_items[index].get(&"key", &"")) == expected_keys[index], "Camera page order drifted at row %d" % index)
	service.set_riding_camera_active(false)
	_check(camera.get_effective_view_mode() == ChaseCamera.VIEW_CHASE, "Garage-safe camera activation did not select Chase")
	service.set_riding_camera_active(true)
	_check(camera.get_effective_view_mode() == ChaseCamera.VIEW_FIRST_PERSON, "live riding camera activation did not restore preference")
	var bike := BIKE_SCENE.instantiate() as DirtBikeController
	add_child(bike)
	var race := RaceController.new()
	race.state = RaceController.State.RACING
	service.bike = bike
	service.race = race
	camera.target = bike
	_check(service.cycle_camera_view(), "live camera command was rejected during an active ride")
	_check(camera.get_view_mode() == ChaseCamera.VIEW_HANDLEBAR, "live camera command did not advance the view")
	_check(
		StringName(service.settings.get_value(&"camera", &"mode", &"")) == ChaseCamera.VIEW_HANDLEBAR,
		"live camera command did not persist its new view"
	)

	print(
		"CAMERA MODES PROBE: modes=%d distinct=%d persisted=%s personalized=%.2f/%.2f/%.2f passed=%s"
		% [
			ChaseCamera.VIEW_MODES.size(),
			seen_positions.size(),
			str(FileAccess.file_exists(TEST_PATH)),
			float(applied.get(&"distance_scale", 0.0)),
			float(applied.get(&"height_scale", 0.0)),
			float(applied.get(&"stiffness_scale", 0.0)),
			str(_passed),
		]
	)
	service.queue_free()
	bike.queue_free()
	race.free()
	camera.queue_free()
	target.queue_free()
	await get_tree().process_frame
	_cleanup()
	get_tree().quit(0 if _passed else 1)


func _vector_is_finite(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_passed = false
	push_error("CAMERA MODES PROBE: %s" % message)


func _cleanup() -> void:
	for suffix: String in ["", SettingsStore.BACKUP_SUFFIX, SettingsStore.TEMP_SUFFIX, SettingsStore.BACKUP_TEMP_SUFFIX]:
		var path := TEST_PATH + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
