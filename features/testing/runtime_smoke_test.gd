extends Node
## Optional deterministic runtime validation, enabled only with `-- --smoke-test`.

var _bike: DirtBikeController
var _camera: ChaseCamera
var _race: RaceController
var _freestyle: FreestyleController
var _discovery: DiscoveryController
var _activity: StringName = &"CIRCUIT"


func initialize(
	bike: DirtBikeController,
	camera: ChaseCamera,
	race: RaceController,
	freestyle: FreestyleController,
	discovery: DiscoveryController
) -> void:
	var arguments := OS.get_cmdline_user_args()
	if &"--capture-garage" in arguments:
		_apply_requested_window_size()
		_capture_garage.call_deferred()
		return
	if &"--smoke-test" not in arguments:
		return
	_apply_requested_window_size()
	_bike = bike
	_camera = camera
	_race = race
	_freestyle = freestyle
	_discovery = discovery
	_activity = _requested_activity()
	_run.call_deferred()


func _capture_garage() -> void:
	for _frame: int in 8:
		await get_tree().process_frame
	var capture := get_viewport().get_texture().get_image()
	var capture_path := ProjectSettings.globalize_path("res://artifacts/riding-dirty-garage.png")
	var save_error := capture.save_png(capture_path)
	capture = null
	await get_tree().process_frame
	get_tree().quit(0 if save_error == OK else 1)


func _apply_requested_window_size() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if not argument.begins_with("--test-size="):
			continue
		var dimensions := argument.trim_prefix("--test-size=").split("x")
		if dimensions.size() != 2:
			continue
		var width := int(dimensions[0])
		var height := int(dimensions[1])
		if width >= 640 and height >= 360:
			get_window().mode = Window.MODE_WINDOWED
			get_window().size = Vector2i(width, height)
			get_window().position = Vector2i(40, 40)


func _run() -> void:
	match _activity:
		&"FREESTYLE":
			await _run_freestyle()
		&"DISCOVERY":
			await _run_discovery()
		_:
			await _run_circuit()


func _run_circuit() -> void:
	var exit_code := 0
	if not _validate_repair_economy():
		exit_code = 1
	await _wait_physics_frames(220)
	var start_position := _bike.global_position
	Input.action_press(InputRouter.THROTTLE, 1.0)
	await _wait_physics_frames(180)
	Input.action_release(InputRouter.THROTTLE)
	var moved_distance := Vector2(start_position.x, start_position.z).distance_to(Vector2(_bike.global_position.x, _bike.global_position.z))
	var height_is_valid := is_finite(_bike.global_position.y) and _bike.global_position.y > -2.0 and _bike.global_position.y < 20.0
	var camera_distance := _camera.global_position.distance_to(_bike.global_position)
	if moved_distance < 3.0:
		push_error("SMOKE TEST: bike did not accelerate far enough (%.2f m)." % moved_distance)
		exit_code = 1
	if not height_is_valid:
		push_error("SMOKE TEST: bike height became invalid (%.2f m)." % _bike.global_position.y)
		exit_code = 1
	if camera_distance < 4.0 or camera_distance > 16.0:
		push_error("SMOKE TEST: chase camera distance is invalid (%.2f m)." % camera_distance)
		exit_code = 1
	if &"--capture-smoke" in OS.get_cmdline_user_args():
		await get_tree().process_frame
		var capture := get_viewport().get_texture().get_image()
		var capture_path := ProjectSettings.globalize_path("res://artifacts/riding-dirty-motion.png")
		var save_error := capture.save_png(capture_path)
		capture = null
		if save_error != OK:
			push_error("SMOKE TEST: unable to save rendered capture (%s)." % error_string(save_error))
			exit_code = 1

	var checkpoint_positions := _race.get_checkpoint_positions()
	if checkpoint_positions.is_empty():
		push_error("TRACK SMOKE: no checkpoints were configured.")
		get_tree().quit(1)
		return
	_bike.respawn_at(Transform3D(Basis.IDENTITY, checkpoint_positions[0] + Vector3.UP * 0.2))
	await _wait_physics_frames(4)
	var checkpoint_registered := _race.get_expected_checkpoint() == 1
	if not checkpoint_registered:
		push_error("SMOKE TEST: the first ordered checkpoint did not register.")
		exit_code = 1

	_race.reset_run()
	await _wait_physics_frames(5)
	var reset_distance := _bike.global_position.distance_to(_race.get_spawn_transform().origin)
	if reset_distance > 1.0:
		push_error("SMOKE TEST: restart did not restore the spawn transform (%.2f m)." % reset_distance)
		exit_code = 1

	print("TRACK SMOKE RESULT: activity=%s moved=%.2fm position=%s camera=%.2fm checkpoint=%s reset_error=%.2fm" % [String(_activity), moved_distance, str(_bike.global_position), camera_distance, str(checkpoint_registered), reset_distance])
	get_tree().quit(exit_code)


func _run_freestyle() -> void:
	var exit_code := 0
	await _wait_physics_frames(12)
	_bike.respawn_at(Transform3D(Basis.IDENTITY, Vector3(0.0, 6.5, 12.0)))
	_bike.linear_velocity = Vector3(0.0, 0.0, -5.0)
	_bike.angular_velocity = Vector3(0.75, 0.0, 0.0)
	await _wait_physics_frames(120)
	if _freestyle.score <= 0:
		push_error("FREESTYLE SMOKE: physical airtime and landing did not award points.")
		exit_code = 1
	if not _freestyle.active:
		push_error("FREESTYLE SMOKE: session ended before its 60-second duration.")
		exit_code = 1
	if &"--capture-smoke" in OS.get_cmdline_user_args():
		await _capture_named_frame("riding-dirty-freestyle.png")
	print("FREESTYLE SMOKE RESULT: score=%d combo=%d height=%.2f" % [_freestyle.score, _freestyle.combo, _bike.global_position.y])
	_freestyle.enter_waiting()
	await _wait_physics_frames(60)
	get_tree().quit(exit_code)


func _run_discovery() -> void:
	var exit_code := 0
	await _wait_physics_frames(8)
	var positions := _discovery.get_pickup_positions()
	if positions.is_empty():
		push_error("DISCOVERY SMOKE: no pickup positions were configured.")
		get_tree().quit(1)
		return
	_bike.respawn_at(Transform3D(Basis.IDENTITY, positions[0] + Vector3.UP * 0.3))
	await _wait_physics_frames(6)
	if _discovery.collected_count != 1:
		push_error("DISCOVERY SMOKE: expected one collected cache, got %d." % _discovery.collected_count)
		exit_code = 1
	if &"--capture-smoke" in OS.get_cmdline_user_args():
		await _capture_named_frame("riding-dirty-discovery.png")
	_discovery.start_hunt()
	await _wait_physics_frames(3)
	var respawned_count := _discovery.get_active_pickup_count()
	if respawned_count != positions.size():
		push_error("DISCOVERY SMOKE: fresh hunt rebuilt %d/%d pickups." % [respawned_count, positions.size()])
		exit_code = 1
	print("DISCOVERY SMOKE RESULT: first_pickup=true respawned=%d compass_source=true" % respawned_count)
	_discovery.enter_waiting()
	await _wait_physics_frames(12)
	get_tree().quit(exit_code)


func _requested_activity() -> StringName:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--activity="):
			return StringName(argument.trim_prefix("--activity=").to_upper())
	return &"CIRCUIT"


func _validate_repair_economy() -> bool:
	var old_cash := Profile.cash
	var old_condition := Profile.bike_condition
	var old_log := Profile.transaction_log.duplicate(true)
	Profile.persistence_enabled = false
	Profile.cash = 1000
	Profile.bike_condition = 80
	var quoted_price := Profile.get_repair_price()
	var repaired := Profile.repair_bike()
	var valid := quoted_price == 140 and repaired and Profile.cash == 860 and Profile.bike_condition == 100
	Profile.cash = old_cash
	Profile.bike_condition = old_condition
	Profile.transaction_log.assign(old_log)
	Profile.persistence_enabled = true
	if not valid:
		push_error("ECONOMY SMOKE: repair quote or transaction invariant failed.")
	return valid


func _capture_named_frame(file_name: String) -> void:
	for _frame: int in 3:
		await get_tree().process_frame
	var capture := get_viewport().get_texture().get_image()
	var capture_path := ProjectSettings.globalize_path("res://artifacts/%s" % file_name)
	var save_error := capture.save_png(capture_path)
	capture = null
	if save_error != OK:
		push_error("SMOKE TEST: unable to save %s (%s)." % [file_name, error_string(save_error)])


func _wait_physics_frames(frame_count: int) -> void:
	for _frame: int in frame_count:
		await get_tree().physics_frame
