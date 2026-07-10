extends Node
## Optional deterministic runtime validation, enabled only with `-- --smoke-test`.

var _bike: DirtBikeController
var _camera: ChaseCamera
var _race: RaceController
var _freestyle: FreestyleController
var _discovery: DiscoveryController
var _transition: DistrictTransition
var _ride_director: RideDirector
var _gameplay_audio: GameplayAudio
var _activity: StringName = &"CIRCUIT"


func initialize(
	bike: DirtBikeController,
	camera: ChaseCamera,
	race: RaceController,
	freestyle: FreestyleController,
	discovery: DiscoveryController,
	transition: DistrictTransition,
	ride_director: RideDirector,
	gameplay_audio: GameplayAudio
) -> void:
	var arguments := OS.get_cmdline_user_args()
	_transition = transition
	_ride_director = ride_director
	_gameplay_audio = gameplay_audio
	if &"--capture-garage" in arguments:
		_apply_requested_window_size()
		_capture_garage.call_deferred()
		return
	if &"--capture-transition" in arguments:
		_apply_requested_window_size()
		_capture_transition.call_deferred()
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


func _capture_transition() -> void:
	await _transition.cover(_requested_activity())
	# Give the audio server enough main-thread ticks to release native playback
	# objects before headless teardown; otherwise the test can report false leaks.
	for _frame: int in 30:
		await get_tree().process_frame
	var capture := get_viewport().get_texture().get_image()
	var capture_path := ProjectSettings.globalize_path("res://artifacts/riding-dirty-transition.png")
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
	if not _validate_tour_progression():
		exit_code = 1
	if not _validate_progression_extensions():
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
	if not _ghost_has_rival():
		push_error("TRACK SMOKE: authored Rook ghost was not configured.")
		exit_code = 1
	var route_positions := _ride_director.get_route_positions(_activity)
	var route_registered := false
	if not route_positions.is_empty():
		var line_before_route := _ride_director.get_line_score()
		_bike.respawn_at(Transform3D(Basis.IDENTITY, route_positions[0] + Vector3.UP * 0.3))
		await _wait_physics_frames(5)
		route_registered = _ride_director.get_line_score() > line_before_route
	if not route_registered:
		push_error("TRACK SMOKE: secret route gate did not register a line event.")
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
		await _quit_cleanly(1)
		return
	_bike.respawn_at(Transform3D(Basis.IDENTITY, checkpoint_positions[0] + Vector3.UP * 0.2))
	await _wait_physics_frames(4)
	var checkpoint_registered := _race.get_expected_checkpoint() == 1
	if not checkpoint_registered:
		push_error("SMOKE TEST: the first ordered checkpoint did not register.")
		exit_code = 1
	var breakdown_available := _race.get_breakdown_preview().contains("S01")
	if not breakdown_available:
		push_error("SMOKE TEST: sector breakdown did not summarize checkpoint data.")
		exit_code = 1

	_race.reset_run()
	await _wait_physics_frames(5)
	var reset_distance := _bike.global_position.distance_to(_race.get_spawn_transform().origin)
	if reset_distance > 1.0:
		push_error("SMOKE TEST: restart did not restore the spawn transform (%.2f m)." % reset_distance)
		exit_code = 1

	print("TRACK SMOKE RESULT: activity=%s moved=%.2fm position=%s camera=%.2fm rival=true route=%s checkpoint=%s breakdown=%s reset_error=%.2fm" % [String(_activity), moved_distance, str(_bike.global_position), camera_distance, str(route_registered), str(checkpoint_registered), str(breakdown_available), reset_distance])
	await _quit_cleanly(exit_code)


func _run_freestyle() -> void:
	var exit_code := 0
	await _wait_physics_frames(12)
	_bike.respawn_at(Transform3D(Basis.IDENTITY, Vector3(0.0, 2.5, 12.0)))
	_bike.linear_velocity = Vector3(0.0, 5.0, -5.0)
	_bike.angular_velocity = Vector3(0.25, 0.0, 0.0)
	await _wait_physics_frames(100)
	if _freestyle.score <= 0:
		push_error("FREESTYLE SMOKE: physical airtime and landing did not award points.")
		exit_code = 1
	if _ride_director.get_line_score() <= 0 or _ride_director.get_contract_progress() <= 0:
		push_error("FREESTYLE SMOKE: Ride Director did not register the physical clean-landing line.")
		exit_code = 1
	if _ride_director.get_modifier() not in [&"TAILWIND", &"FLOW_SURGE", &"LOOSE_DIRT"]:
		push_error("FREESTYLE SMOKE: daily modifier selection was invalid.")
		exit_code = 1
	var earned_flow := _bike.get_flow()
	if earned_flow < _bike.flow_boost_cost:
		push_error("FREESTYLE SMOKE: clean physical landing awarded only %.1f Flow." % earned_flow)
		exit_code = 1
	var speed_before_boost := _bike.get_speed_mps()
	Input.action_press(InputRouter.FLOW_BOOST)
	await _wait_physics_frames(1)
	Input.action_release(InputRouter.FLOW_BOOST)
	await _wait_physics_frames(2)
	var flow_after_boost := _bike.get_flow()
	var speed_after_boost := _bike.get_speed_mps()
	if not _bike.is_boosting() or flow_after_boost > earned_flow - _bike.flow_boost_cost + 0.1:
		push_error("FREESTYLE SMOKE: Flow boost did not activate or spend its cost.")
		exit_code = 1
	if speed_after_boost < speed_before_boost + 1.0:
		push_error("FREESTYLE SMOKE: Flow boost did not produce a meaningful speed impulse (%.2f -> %.2f)." % [speed_before_boost, speed_after_boost])
		exit_code = 1
	if not _freestyle.active:
		push_error("FREESTYLE SMOKE: session ended before its 60-second duration.")
		exit_code = 1
	if &"--capture-smoke" in OS.get_cmdline_user_args():
		await _capture_named_frame("riding-dirty-freestyle.png")
	print("FREESTYLE SMOKE RESULT: score=%d combo=%d line=%d contract=%d modifier=%s flow=%.1f->%.1f boost_speed=%.2f->%.2f height=%.2f" % [_freestyle.score, _freestyle.combo, _ride_director.get_line_score(), _ride_director.get_contract_progress(), String(_ride_director.get_modifier()), earned_flow, flow_after_boost, speed_before_boost, speed_after_boost, _bike.global_position.y])
	_freestyle.enter_waiting()
	await _wait_physics_frames(60)
	await _quit_cleanly(exit_code)


func _run_discovery() -> void:
	var exit_code := 0
	await _wait_physics_frames(8)
	var positions := _discovery.get_pickup_positions()
	if positions.is_empty():
		push_error("DISCOVERY SMOKE: no pickup positions were configured.")
		await _quit_cleanly(1)
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
	await _quit_cleanly(exit_code)


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


func _validate_tour_progression() -> bool:
	var old_racer_rep := Profile.racer_reputation
	var old_freestyler_rep := Profile.freestyler_reputation
	var old_explorer_rep := Profile.explorer_reputation
	var old_total_runs := Profile.total_runs
	var old_medals := Profile.best_medal_ranks.duplicate(true)
	var old_victories := Profile.rival_victories.duplicate()
	var old_persistence := Profile.persistence_enabled
	Profile.persistence_enabled = false
	Profile.racer_reputation = 0
	Profile.freestyler_reputation = 0
	Profile.explorer_reputation = 0
	Profile.total_runs = 0
	Profile.best_medal_ranks.clear()
	Profile.rival_victories.clear()
	var starts_locked := not Profile.is_activity_unlocked(&"PINE_ENDURO")
	Profile.best_medal_ranks[&"CIRCUIT"] = 1
	Profile.best_medal_ranks[&"FREESTYLE"] = 2
	var two_events_unlock := Profile.is_activity_unlocked(&"PINE_ENDURO") and Profile.get_quarry_progress_count() == 2 and Profile.get_event_medal(&"FREESTYLE") == &"BRONZE"
	Profile.best_medal_ranks.clear()
	Profile.rival_victories.append(&"CIRCUIT")
	var rival_unlock := Profile.is_activity_unlocked(&"PINE_ENDURO")
	Profile.racer_reputation = old_racer_rep
	Profile.freestyler_reputation = old_freestyler_rep
	Profile.explorer_reputation = old_explorer_rep
	Profile.total_runs = old_total_runs
	Profile.best_medal_ranks.assign(old_medals)
	Profile.rival_victories.assign(old_victories)
	Profile.persistence_enabled = old_persistence
	var valid := starts_locked and two_events_unlock and rival_unlock
	if not valid:
		push_error("TOUR SMOKE: unlock rules or medal projection failed.")
	return valid


func _validate_progression_extensions() -> bool:
	var old_cash := Profile.cash
	var old_racer_rep := Profile.racer_reputation
	var old_style_tokens := Profile.style_tokens
	var old_completions := Profile.contract_completions
	var old_contracts := Profile.completed_contracts.duplicate()
	var old_feats := Profile.unlocked_feats.duplicate()
	var old_assist := Profile.assist_mode
	var old_persistence := Profile.persistence_enabled
	Profile.persistence_enabled = false
	Profile.cash = 0
	Profile.racer_reputation = 0
	Profile.style_tokens = 0
	Profile.contract_completions = 0
	Profile.completed_contracts.clear()
	Profile.unlocked_feats.clear()
	Profile.assist_mode = &"SPORT"
	var feat_awarded := Profile.unlock_feat("SMOKE_FEAT")
	var contract_awarded := Profile.complete_contract("SMOKE_CONTRACT", &"CIRCUIT", 350, 35)
	var assist_changed := Profile.cycle_assist_mode() == &"PRO"
	var valid := feat_awarded and contract_awarded and assist_changed and Profile.cash == 350 and Profile.racer_reputation == 35 and Profile.style_tokens == 2 and Profile.get_cosmetic_tier() == 1
	Profile.cash = old_cash
	Profile.racer_reputation = old_racer_rep
	Profile.style_tokens = old_style_tokens
	Profile.contract_completions = old_completions
	Profile.completed_contracts.assign(old_contracts)
	Profile.unlocked_feats.assign(old_feats)
	Profile.assist_mode = old_assist
	Profile.persistence_enabled = old_persistence
	if not valid:
		push_error("PROGRESSION SMOKE: contracts, feats, cosmetics, or assist persistence failed.")
	return valid


func _ghost_has_rival() -> bool:
	var ghost := _race.ghost
	return ghost != null and ghost.is_rival_configured()


func _capture_named_frame(file_name: String) -> void:
	for _frame: int in 12:
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


func _quit_cleanly(exit_code: int) -> void:
	_gameplay_audio.shutdown()
	_bike.set_physics_process(false)
	_bike.shutdown_audio()
	for _frame: int in 3:
		await get_tree().process_frame
	get_tree().quit(exit_code)
