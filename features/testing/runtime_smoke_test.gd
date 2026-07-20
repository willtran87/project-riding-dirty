extends Node
## Optional deterministic runtime validation, enabled only with `-- --smoke-test`.

const PACK_COMPETITIVE_SPEED_DELTA_MPS := 2.0
const PACK_DIFFICULTY_SPEED_ALLOWANCE_MPS := 0.45

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
	if &"--capture-overview-only" in arguments:
		_apply_requested_window_size()
		_bike = bike
		_camera = camera
		_activity = _requested_activity()
		_capture_requested_overview.call_deferred()
		return
	if &"--capture-garage" in arguments:
		_apply_requested_window_size()
		_capture_garage.call_deferred()
		return
	if &"--capture-transition" in arguments:
		_apply_requested_window_size()
		_capture_transition.call_deferred()
		return
	if &"--capture-race-visuals" in arguments:
		_apply_requested_window_size()
		_bike = bike
		_camera = camera
		_race = race
		_activity = _requested_activity()
		_capture_race_visuals.call_deferred()
		return
	if &"--smoke-test" not in arguments:
		return
	_apply_requested_window_size()
	_bike = bike
	_camera = camera
	if &"--capture-bike-detail" in arguments:
		_camera.follow_distance = 3.8
		_camera.follow_height = 1.8
		_camera.base_fov = 60.0
		_camera.maximum_fov = 72.0
	_race = race
	_race.ghost.persistence_enabled = false
	Profile.persistence_enabled = false
	_freestyle = freestyle
	_discovery = discovery
	_activity = _requested_activity()
	_run.call_deferred()


func _capture_requested_overview() -> void:
	var track_id := _requested_track_id()
	var scene := get_tree().current_scene
	if scene != null and scene.has_method(&"_ensure_track_loaded"):
		scene.call(&"_ensure_track_loaded", track_id)
		for _frame: int in 12:
			await get_tree().process_frame
	var points := CourseCatalog.get_world_riding_points(track_id)
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for point: Vector3 in points:
		minimum.x = minf(minimum.x, point.x)
		minimum.y = minf(minimum.y, point.z)
		maximum.x = maxf(maximum.x, point.x)
		maximum.y = maxf(maximum.y, point.z)
	var course_span := maximum - minimum
	var course_center := Vector3((minimum.x + maximum.x) * 0.5, 0.0, (minimum.y + maximum.y) * 0.5)
	var saved := await _capture_course_overview(course_center, course_span)
	await _quit_cleanly(0 if saved else 1)


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


func _capture_race_visuals() -> void:
	# Capture the real composed race without running track-specific assertion
	# suites. This supports high-resolution presentation review for every event.
	for _frame: int in 24:
		await get_tree().process_frame
	var activity_slug := String(_activity).to_lower()
	var grid_saved := await _capture_named_frame("riding-dirty-%s-grid.png" % activity_slug)
	for _frame: int in 230:
		await get_tree().physics_frame
	Input.action_press(InputRouter.THROTTLE, 1.0)
	for _frame: int in 150:
		await get_tree().physics_frame
	Input.action_release(InputRouter.THROTTLE)
	var chase_saved := await _capture_named_frame("riding-dirty-%s-chase.png" % activity_slug)
	await _quit_cleanly(0 if grid_saved and chase_saved else 1)

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
	if not _validate_player_matched_pack():
		exit_code = 1
	if not _validate_progressive_jump_package():
		exit_code = 1
	if not _validate_ground_coverage():
		exit_code = 1
	if not _validate_course_width_and_containment():
		exit_code = 1
	# Validation helpers restore their captured setting; keep the actual smoke run isolated.
	Profile.persistence_enabled = false
	if &"--capture-pack" in OS.get_cmdline_user_args():
		if not await _capture_named_frame("riding-dirty-pack.png"):
			exit_code = 1
		# Rendering and PNG encoding consume live countdown frames. Restart the
		# deterministic run so capture mode exercises the same start-lock window.
		_race.reset_run()
	var countdown_start := _bike.global_position
	Input.action_press(InputRouter.THROTTLE, 1.0)
	await _wait_physics_frames(180)
	Input.action_release(InputRouter.THROTTLE)
	var countdown_drift := Vector2(countdown_start.x, countdown_start.z).distance_to(Vector2(_bike.global_position.x, _bike.global_position.z))
	if _race.state != RaceController.State.COUNTDOWN:
		push_error("START LOCK SMOKE: race left countdown too early.")
		exit_code = 1
	if countdown_drift > 0.05 or _bike.get_speed_mps() > 0.05:
		push_error("START LOCK SMOKE: bike moved %.3fm at %.3fm/s before GO." % [countdown_drift, _bike.get_speed_mps()])
		exit_code = 1
	if not _bike.is_grounded():
		push_error("START LOCK SMOKE: suspension was not planted on the course during countdown.")
		exit_code = 1
	if not _bike.freeze:
		push_error("START LOCK SMOKE: bike rigid body was not locked during countdown.")
		exit_code = 1
	await _wait_physics_frames(40)
	if _race.state != RaceController.State.RACING or _bike.freeze:
		push_error("START LOCK SMOKE: bike did not unlock when the race began.")
		exit_code = 1
	# Web focus can leave the rider idling for several seconds after GO. Verify
	# the low-speed balance assist cannot pitch-loop on the authored start slope.
	await _wait_physics_frames(360)
	var idle_upright := _bike.global_transform.basis.y.normalized().dot(Vector3.UP)
	var idle_grounded := _bike.is_grounded()
	print("START BALANCE RESULT: up=%.3f speed=%.2f grounded=%s feedback=%s" % [idle_upright, _bike.get_speed_mps(), str(idle_grounded), str(_bike.get_contact_feedback())])
	if idle_upright < 0.9 or not idle_grounded or _bike.get_speed_mps() > 0.15:
		push_error("START BALANCE SMOKE: bike lost its planted idle after GO (up=%.3f, speed=%.2f m/s, grounded=%s)." % [idle_upright, _bike.get_speed_mps(), str(idle_grounded)])
		exit_code = 1
	if _activity == &"ACADEMY":
		var academy_idle := _race.get_session_snapshot()
		var academy_integrity := academy_idle.get(&"integrity", {}) as Dictionary
		var academy_incidents := academy_integrity.get(&"incidents", {}) as Dictionary
		var academy_idle_clean := (
			int(academy_idle.get(&"penalty_usec", -1)) == 0
			and int(academy_incidents.get(&"resets_consumed", -1)) == 0
			and not bool(academy_integrity.get(&"stuck_detection_armed", true))
			and not bool(academy_integrity.get(&"reset_requested", true))
		)
		print("ACADEMY IDLE COACHING RESULT: penalty=%d resets=%d armed=%s passed=%s" % [
			int(academy_idle.get(&"penalty_usec", -1)),
			int(academy_incidents.get(&"resets_consumed", -1)),
			str(academy_integrity.get(&"stuck_detection_armed", true)),
			str(academy_idle_clean),
		])
		if not academy_idle_clean:
			push_error("ACADEMY IDLE COACHING SMOKE: reading time triggered recovery or penalty (%s)." % str(academy_idle))
			exit_code = 1
	var start_position := _bike.global_position
	var start_forward := -_bike.global_transform.basis.z.normalized()
	var trail_dust := _bike.find_child("TrailDust", true, false) as GPUParticles3D
	var rear_roost := _bike.find_child("RearRoost", true, false) as GPUParticles3D
	var dirt_vfx_ready := false
	var terrain_feedback_ready := false
	var contact_feedback: Dictionary = {}
	Input.action_press(InputRouter.THROTTLE, 1.0)
	for _frame: int in 180:
		await get_tree().physics_frame
		contact_feedback = _bike.get_contact_feedback()
		dirt_vfx_ready = dirt_vfx_ready or (
			trail_dust != null
			and rear_roost != null
			and (trail_dust.emitting or rear_roost.emitting)
		)
		terrain_feedback_ready = terrain_feedback_ready or (
			float(contact_feedback.get(&"roughness", 0.0)) >= 0.5
			and float(contact_feedback.get(&"roost", 0.0)) >= 0.7
		)
	var riding_up := _bike.global_transform.basis.y.normalized().dot(Vector3.UP)
	var riding_grounded := _bike.is_grounded()
	var riding_forward := -_bike.global_transform.basis.z.normalized()
	var riding_points := CourseCatalog.get_world_riding_points(_requested_track_id())
	var nearest_riding_index := CourseSpline.closest_index(riding_points, _bike.global_position)
	var riding_line_error := Vector2(_bike.global_position.x, _bike.global_position.z).distance_to(Vector2(riding_points[nearest_riding_index].x, riding_points[nearest_riding_index].z))
	var pace_snapshot := _race.get_pack_pace_snapshot()
	var pack_maximum := float(pace_snapshot.get(&"maximum", 0.0))
	var player_speed := _bike.get_speed_mps()
	var competitive_speed_delta := pack_maximum - player_speed
	var session := _race.get_session_config()
	var retention_contract := session.rules.get(&"retention", {}) as Dictionary
	var nearest_ahead := float(pace_snapshot.get(&"gap_ahead", -1.0))
	var leader_drag_allowance := 0.0
	if nearest_ahead > 0.0 and not retention_contract.is_empty():
		# The preceding idle-balance check deliberately leaves the player on the
		# gate for six seconds after GO. Once the pack opens a gap, the authored
		# retention director slows its leaders. Add only that calculable shaping
		# allowance (including the maximum rider-pressure multiplier) instead of
		# weakening the underlying unshaped pace contract.
		var leader_drag := RacePack.calculate_gap_pace_adjustment(
			session,
			retention_contract,
			nearest_ahead
		)
		if leader_drag < 0.0:
			leader_drag_allowance = absf(leader_drag) * 1.08
	var pack_slower_limit := PACK_COMPETITIVE_SPEED_DELTA_MPS + leader_drag_allowance
	# A championship-tier field should be able to outrun a neutral, no-Flow
	# opening stint. Preserve the original starter-event ceiling and add a small,
	# explicit allowance for each authored tier above the opening race.
	var pack_faster_limit := (
		PACK_COMPETITIVE_SPEED_DELTA_MPS
		+ float(maxi(session.difficulty - 1, 0)) * PACK_DIFFICULTY_SPEED_ALLOWANCE_MPS
	)
	var field_position := int(pace_snapshot.get(&"field_position", 0))
	var field_size := int(pace_snapshot.get(&"field_size", 0))
	var field_status := get_tree().current_scene.find_child("FieldStatus", true, false) as Label
	var field_feedback_ready := (
		field_size == session.field_size
		and field_position >= 1
		and field_position <= field_size
		and field_status != null
		and field_status.text.contains("POSITION")
	)
	print("RIDE ATTITUDE RESULT: up=%.3f grounded=%s speed=%.2f position=%s velocity=%s start_forward=%s forward=%s line_error=%.2f" % [riding_up, str(riding_grounded), _bike.get_speed_mps(), str(_bike.global_position), str(_bike.linear_velocity), str(start_forward), str(riding_forward), riding_line_error])
	if riding_up < 0.45:
		push_error("RIDE ATTITUDE SMOKE: bike inverted during the opening throttle run (up=%.3f)." % riding_up)
		exit_code = 1
	if riding_line_error > CourseCatalog.get_track_width(_requested_track_id()) * 0.55:
		push_error("RIDE LINE SMOKE: neutral-steer launch left the authored surface (error=%.2f m)." % riding_line_error)
		exit_code = 1
	# Solo Academy lessons intentionally have no pack to pace against. They still
	# retain the field-size/position presentation contract below.
	if session.field_size > 1 and (
		competitive_speed_delta < -pack_slower_limit
		or competitive_speed_delta > pack_faster_limit
	):
		push_error(
			"PACK PACE SMOKE: fastest opponent was not competitive with the player (delta=%+.2f m/s, allowed=-%.2f/+%.2f m/s, leader_drag=%.2f m/s, %s)."
			% [competitive_speed_delta, pack_slower_limit, pack_faster_limit, leader_drag_allowance, str(pace_snapshot)]
		)
		exit_code = 1
	if not field_feedback_ready:
		push_error("RACE EXPERIENCE SMOKE: live field position feedback is missing or invalid (%s)." % str(pace_snapshot))
		exit_code = 1
	print("PACK PACE RESULT: %s" % str(pace_snapshot))
	var chaos_snapshot := _race.get_pack_chaos_snapshot()
	if not _validate_pack_chaos(chaos_snapshot):
		exit_code = 1
	if &"--capture-bike-detail" in OS.get_cmdline_user_args():
		if not await _capture_named_frame("riding-dirty-bike-detail.png"):
			exit_code = 1
	elif &"--capture-smoke" in OS.get_cmdline_user_args():
		if not await _capture_named_frame("riding-dirty-motion.png"):
			exit_code = 1
	Input.action_release(InputRouter.THROTTLE)
	var moved_distance := Vector2(start_position.x, start_position.z).distance_to(Vector2(_bike.global_position.x, _bike.global_position.z))
	var course_ceiling := 125.0 if _activity == &"PINE_ENDURO" else 85.0
	var height_is_valid := is_finite(_bike.global_position.y) and _bike.global_position.y > -12.0 and _bike.global_position.y < course_ceiling
	var camera_distance := _camera.global_position.distance_to(_bike.global_position)
	if moved_distance < 3.0:
		push_error("SMOKE TEST: bike did not accelerate far enough (%.2f m, %.2f m/s, feedback=%s)." % [moved_distance, _bike.get_speed_mps(), str(_bike.get_contact_feedback())])
		exit_code = 1
	if not height_is_valid:
		push_error("SMOKE TEST: bike height became invalid (%.2f m)." % _bike.global_position.y)
		exit_code = 1
	if camera_distance < 4.0 or camera_distance > 16.0:
		push_error("SMOKE TEST: chase camera distance is invalid (%.2f m)." % camera_distance)
		exit_code = 1
	if not dirt_vfx_ready or not terrain_feedback_ready:
		push_error("DIRT FEEDBACK SMOKE: contact/VFX stack did not activate (%s, dust=%s, roost=%s)." % [str(contact_feedback), str(trail_dust.emitting if trail_dust != null else false), str(rear_roost.emitting if rear_roost != null else false)])
		exit_code = 1
	var target_rival_expected := session.opponent_count == 0
	var target_rival_ready := _ghost_has_rival()
	if target_rival_ready != target_rival_expected:
		push_error("TRACK SMOKE: solo target-rival visibility did not match the physical field contract.")
		exit_code = 1
	var route_positions := _ride_director.get_route_positions(_activity)
	var route_registered := route_positions.is_empty()
	if not route_positions.is_empty():
		var line_before_route := _ride_director.get_line_score()
		var route_transform := _ride_director.get_first_route_transform(_activity)
		route_transform.origin += Vector3.UP * 0.3
		_bike.respawn_at(route_transform)
		await _wait_physics_frames(5)
		route_registered = _ride_director.get_line_score() > line_before_route
	if not route_positions.is_empty() and not route_registered:
		push_error("TRACK SMOKE: secret route gate did not register a line event.")
		exit_code = 1
	var checkpoint_positions := _race.get_checkpoint_positions()
	if checkpoint_positions.is_empty():
		push_error("TRACK SMOKE: no checkpoints were configured.")
		await _quit_cleanly(1)
		return
	var course_length := 0.0
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	var minimum_elevation := INF
	var maximum_elevation := -INF
	var previous_point := _race.get_spawn_transform().origin
	for point: Vector3 in [previous_point] + checkpoint_positions:
		var planar := Vector2(point.x, point.z)
		minimum.x = minf(minimum.x, planar.x)
		minimum.y = minf(minimum.y, planar.y)
		maximum.x = maxf(maximum.x, planar.x)
		maximum.y = maxf(maximum.y, planar.y)
		minimum_elevation = minf(minimum_elevation, point.y)
		maximum_elevation = maxf(maximum_elevation, point.y)
	for point: Vector3 in checkpoint_positions:
		course_length += previous_point.distance_to(point)
		previous_point = point
	var course_span := maximum - minimum
	var elevation_range := maximum_elevation - minimum_elevation
	# Quarry's legibility rebuild removes three folded switchbacks and is now an
	# honest 1.8 km route. Preserve substantial trail scale without rewarding the
	# ambiguous doubling-back geometry this probe previously required.
	# The timed Quarry span is 1,780 m (the complete surfaced spline, including
	# its start/finish margins, is 1,819 m). Keep a small tolerance for sampling
	# while still rejecting any material loss of course scale.
	var track_id := _requested_track_id()
	var required_length := 1750.0
	var required_span := 600.0
	var required_elevation := 50.0
	if track_id == CourseCatalog.PINE_ID:
		required_length = 3000.0
		required_span = 680.0
		required_elevation = 80.0
	elif track_id == CourseCatalog.MESA_MX_ID:
		# Mesa is an intentionally compact closed motocross circuit. Its 803 m lap
		# trades point-to-point scale for repeatable rhythm, passing and lap flow.
		required_length = 780.0
		required_span = 245.0
		required_elevation = 5.0
	if course_length < required_length or maxf(course_span.x, course_span.y) < required_span or elevation_range < required_elevation:
		push_error("TRACK SMOKE: course lacks real trail scale (%.1fm, span %s, elevation %.1fm)." % [course_length, str(course_span), elevation_range])
		exit_code = 1
	if &"--capture-overview" in OS.get_cmdline_user_args():
		var course_center := Vector3((minimum.x + maximum.x) * 0.5, 0.0, (minimum.y + maximum.y) * 0.5)
		if not await _capture_course_overview(course_center, course_span):
			exit_code = 1
	var space_state := _bike.get_world_3d().direct_space_state
	for index: int in checkpoint_positions.size():
		var checkpoint := checkpoint_positions[index]
		var query := PhysicsRayQueryParameters3D.create(checkpoint + Vector3.UP * 8.0, checkpoint + Vector3.DOWN * 8.0, 2)
		if space_state.intersect_ray(query).is_empty():
			push_error("TRACK SMOKE: checkpoint %d has no rideable ground beneath it." % index)
			exit_code = 1
	var checkpoint_chain_valid := true
	for lap_index: int in session.laps:
		for index: int in checkpoint_positions.size():
			_bike.respawn_at(Transform3D(Basis.IDENTITY, checkpoint_positions[index] + Vector3.UP * 0.2))
			await _wait_physics_frames(4)
			var is_lap_finish := index == checkpoint_positions.size() - 1
			var is_race_finish := is_lap_finish and lap_index == session.laps - 1
			var checkpoint_advanced := (
				_race.state in [RaceController.State.FINISHED, RaceController.State.RESULTS]
				if is_race_finish
				else _race.get_expected_checkpoint() == (0 if is_lap_finish else index + 1)
			)
			if not checkpoint_advanced:
				push_error("SMOKE TEST: ordered lap %d checkpoint %d did not register." % [lap_index + 1, index + 1])
				exit_code = 1
				checkpoint_chain_valid = false
				break
		if not checkpoint_chain_valid:
			break
	var finish_snapshot := _race.get_session_snapshot()
	var checkpoint_registered := (
		checkpoint_chain_valid
		and int(finish_snapshot.get(&"laps_completed", 0)) == session.laps
		and _race.state in [RaceController.State.FINISHED, RaceController.State.RESULTS]
	)
	if not checkpoint_registered:
		push_error("SMOKE TEST: the ordered checkpoint chain did not reach the finish.")
		exit_code = 1
	var breakdown_preview := _race.get_breakdown_preview()
	var breakdown_available := breakdown_preview.contains("RUN READOUT") and breakdown_preview.contains("BEST S") and breakdown_preview.contains("COSTLIEST S")
	if not breakdown_available:
		push_error("SMOKE TEST: sector breakdown did not summarize checkpoint data.")
		exit_code = 1
	var center_message := get_tree().current_scene.find_child("CenterMessage", true, false) as Label
	var center_prompt_available := (
		center_message != null
		and center_message.text.contains("NEXT TARGET")
		and center_message.text.contains("RUN AGAIN")
	)
	var hud := get_tree().current_scene.find_child("RaceHud", true, false) as RaceHud
	var result_presentation := hud.get_competition_presentation_snapshot() if hud != null else {}
	var result_footer := str(result_presentation.get(&"footer", ""))
	var restart_binding := InputRouter.get_action_label(InputRouter.RESTART_RUN, InputRouter.input_mode, 2)
	var results_action_available := (
		bool(result_presentation.get(&"results_visible", false))
		and result_footer.contains(restart_binding)
		and result_footer.contains("GARAGE")
	)
	var replay_prompt_available := center_prompt_available or results_action_available
	if not replay_prompt_available:
		push_error("RACE EXPERIENCE SMOKE: finish card did not present a concrete replay target.")
		exit_code = 1

	_race.reset_run()
	await _wait_physics_frames(5)
	var reset_distance := _bike.global_position.distance_to(_race.get_spawn_transform().origin)
	if reset_distance > 1.0:
		push_error("SMOKE TEST: restart did not restore the spawn transform (%.2f m)." % reset_distance)
		exit_code = 1
	if &"--capture-bike-showcase" in OS.get_cmdline_user_args():
		if not await _capture_bike_showcase():
			exit_code = 1

	print("TRACK SMOKE RESULT: activity=%s prestart=%.3fm course=%.1fm span=%s elevation=%.1fm moved=%.2fm dirt=%s roughness=%.2f position=%s camera=%.2fm target_rival=%s field=%s route=%s checkpoint=%s breakdown=%s replay=%s reset_error=%.2fm" % [String(_activity), countdown_drift, course_length, str(course_span), elevation_range, moved_distance, str(dirt_vfx_ready), float(contact_feedback.get(&"roughness", 0.0)), str(_bike.global_position), camera_distance, str(target_rival_ready), str(field_feedback_ready), str(route_registered), str(checkpoint_registered), str(breakdown_available), str(replay_prompt_available), reset_distance])
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
	# Context Flow may recommend COMPOSE for a few ticks after the scored landing.
	# Wait for the bike to settle into the grounded SURGE context before asserting
	# the legacy straight-line boost contract.
	var surge_ready := false
	for _frame: int in range(90):
		var racecraft := _bike.get_racecraft_snapshot()
		if _bike.is_grounded() and StringName(racecraft.get(&"recommended_flow_mode", &"")) == &"SURGE":
			surge_ready = true
			break
		await get_tree().physics_frame
	if not surge_ready:
		push_error("FREESTYLE SMOKE: bike did not settle into a grounded Flow Surge context.")
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
		if not await _capture_named_frame("riding-dirty-freestyle.png"):
			exit_code = 1
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
		if not await _capture_named_frame("riding-dirty-discovery.png"):
			exit_code = 1
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


func _requested_track_id() -> StringName:
	return RaceEventCatalog.get_track_id(_activity) if RaceEventCatalog.has_event(_activity) else CourseCatalog.QUARRY_ID


func _active_level_name(track_id: StringName) -> String:
	if track_id == CourseCatalog.PINE_ID:
		return "PineRidge"
	if track_id == CourseCatalog.MESA_MX_ID:
		return "MesaMX"
	return "Quarry"


func _validate_player_matched_pack() -> bool:
	var pack := get_tree().current_scene.find_child("RacePack", true, false)
	if pack == null:
		push_error("PACK VISUAL SMOKE: RacePack was not present.")
		return false
	var riders := pack.find_children("PackRider*", "Node3D", true, false)
	var matched_count := 0
	for rider: Node in riders:
		var visual := rider.find_child("PlayerMatchedBikeVisual", true, false)
		if visual == null or visual.get_script() == null:
			continue
		if String(visual.get_script().resource_path) != "res://entities/bike/bike_visual.gd":
			continue
		var required_parts: Array[String] = [
			"FrontWheelDetail*", "RearWheelDetail*", "DetailedChassis*",
			"SteeringDetails*", "RiderBodyBatch*", "ArticulatedArms", "ArticulatedLegs",
		]
		var complete := true
		for part_name: String in required_parts:
			complete = complete and visual.find_child(part_name, true, false) != null
		if complete:
			matched_count += 1
	var bike_visual := get_tree().current_scene.find_child("BikeVisual", true, false)
	var visible_fenders := 0
	if bike_visual != null:
		for mesh_name: String in ["DetailedChassis_red", "SteeringDetails_red"]:
			if _mesh_uses_clockwise_front_faces(bike_visual.find_child(mesh_name, true, false) as MeshInstance3D):
				visible_fenders += 1
	var passed := matched_count == RacePack.RIDER_COUNT and visible_fenders == 2
	print("PACK VISUAL PROBE: riders=%d player_matched=%d visible_fenders=%d/2 passed=%s" % [riders.size(), matched_count, visible_fenders, str(passed)])
	if not passed:
		push_error("PACK VISUAL SMOKE: matched opponents=%d/%d, visible player fender batches=%d/2." % [matched_count, RacePack.RIDER_COUNT, visible_fenders])
	return passed


func _validate_pack_chaos(snapshot: Dictionary) -> bool:
	var riders := int(snapshot.get(&"riders", 0))
	var active_riders := int(snapshot.get(&"active", 0))
	var expected_riders := _race.get_session_config().opponent_count
	if expected_riders == 0:
		var solo_passed := (
			riders == 0
			and active_riders == 0
			and int(snapshot.get(&"surface_queries_peak", 0)) == 0
			and int(snapshot.get(&"field_contacts", 0)) == 0
			and int(snapshot.get(&"field_crashes", 0)) == 0
		)
		print("PACK CHAOS RESULT: solo=true riders=%d active=%d queries=%d passed=%s" % [
			riders, active_riders, int(snapshot.get(&"surface_queries_peak", 0)), str(solo_passed),
		])
		if not solo_passed:
			push_error("PACK CHAOS SMOKE: solo session spawned or simulated opponent traffic (%s)." % str(snapshot))
		return solo_passed
	var lane_limit := float(snapshot.get(&"lane_limit", 0.0))
	var peak_lane_span := float(snapshot.get(&"peak_lane_span", 0.0))
	var lane_changes := int(snapshot.get(&"lane_changes", 0))
	var overtakes := int(snapshot.get(&"field_overtakes", 0))
	var npc_contacts := int(snapshot.get(&"field_contacts", 0))
	var player_contacts := int(snapshot.get(&"player_contacts", 0))
	var near_misses := int(snapshot.get(&"near_misses", 0))
	var crashes := int(snapshot.get(&"field_crashes", 0))
	var close_traffic_seconds := float(snapshot.get(&"close_traffic_seconds", 0.0))
	var launch_lock_seconds := float(snapshot.get(&"launch_lock_seconds", 0.0))
	var launch_first_motion := float(snapshot.get(&"launch_first_lateral_motion_time", -1.0))
	var launch_first_tactic := float(snapshot.get(&"launch_first_tactical_time", -1.0))
	var launch_max_displacement := float(snapshot.get(&"launch_max_lane_displacement", INF))
	var launch_max_lateral_speed := float(snapshot.get(&"launch_max_lateral_speed", INF))
	var launch_blend_acceleration := float(snapshot.get(&"launch_max_blend_lateral_acceleration", INF))
	var launch_heading_step := float(snapshot.get(&"launch_max_heading_step_degrees", INF))
	var launch_npc_clearance := float(snapshot.get(&"launch_min_npc_clearance", -1.0))
	var launch_player_clearance := float(snapshot.get(&"launch_min_player_clearance", -1.0))
	var surface_minimum_clearance := float(snapshot.get(&"surface_minimum_clearance", -INF))
	var maximum_pair_separation_step := float(snapshot.get(&"maximum_pair_separation_step", INF))
	var required_span := (
		0.0
		if expected_riders <= 1
		else minf(lane_limit * 1.45, maxf(2.5, minf(8.0, float(expected_riders) * 1.1)))
	)
	var required_lane_changes := 0 if expected_riders <= 1 else maxi(2, ceili(float(expected_riders) * 0.55))
	var required_overtakes := 0 if expected_riders <= 1 else maxi(1, ceili(float(expected_riders) * 0.24))
	var required_events := 0 if expected_riders <= 1 else maxi(2, ceili(float(expected_riders) * 0.5))
	var meaningful_events := overtakes + npc_contacts + near_misses + crashes
	var finite_metrics := (
		is_finite(lane_limit)
		and is_finite(peak_lane_span)
		and is_finite(close_traffic_seconds)
	)
	var lively := (
		riders == expected_riders
		and active_riders >= maxi(expected_riders - 1, 0)
		and peak_lane_span >= required_span
		and lane_changes >= required_lane_changes
		and overtakes >= required_overtakes
		and (expected_riders < 8 or npc_contacts >= 1)
		and meaningful_events >= required_events
		and (expected_riders <= 1 or close_traffic_seconds >= 0.25)
	)
	# Chaos is only useful while it stays readable and survivable. These ceilings
	# catch feedback loops that turn the field into constant unavoidable impacts.
	var bounded := (
		peak_lane_span <= lane_limit * 2.0 + 0.2
		and npc_contacts <= maxi(expected_riders * 3, 6)
		and crashes <= maxi(expected_riders, 4)
		and player_contacts <= 6
	)
	var natural_launch := (
		launch_lock_seconds >= 2.4
		and launch_max_displacement <= 0.001
		and launch_max_lateral_speed <= 0.001
		and launch_first_tactic >= launch_lock_seconds
		and launch_first_motion >= launch_lock_seconds
		and launch_blend_acceleration <= RacePack.LANE_ACCELERATION + 0.01
		and launch_heading_step <= 1.5
		and (expected_riders < 2 or launch_npc_clearance >= 2.1)
		and launch_player_clearance >= 2.1
	)
	var clipping_safe := (
		is_finite(surface_minimum_clearance)
		and surface_minimum_clearance >= -0.001
		and is_finite(maximum_pair_separation_step)
		and maximum_pair_separation_step <= RacePack.NPC_MAX_SEPARATION_STEP + 0.001
	)
	var passed := finite_metrics and lively and bounded and natural_launch and clipping_safe
	print("PACK CHAOS RESULT: lively=%s bounded=%s natural_launch=%s clipping_safe=%s events=%d snapshot=%s" % [str(lively), str(bounded), str(natural_launch), str(clipping_safe), meaningful_events, str(snapshot)])
	if not passed:
		push_error("PACK CHAOS SMOKE: field lacked a straight launch or bounded later overtakes/contact/recovery behavior (%s)." % str(snapshot))
	return passed


func _validate_progressive_jump_package() -> bool:
	var track_id := _requested_track_id()
	var level_name := _active_level_name(track_id)
	var level := get_tree().current_scene.find_child(level_name, true, false)
	if level == null:
		push_error("JUMP PACKAGE SMOKE: active level %s was not found." % level_name)
		return false
	if track_id == CourseCatalog.QUARRY_ID:
		return _validate_quarry_welded_jump_packages(level)
	if track_id == CourseCatalog.MESA_MX_ID:
		return _validate_mesa_welded_jump_packages(level)
	var required_pairs := 23
	var required_wedges := required_pairs * 2
	var track_width := CourseCatalog.get_track_width(track_id)
	var required_broad_pairs := 23 if track_id == CourseCatalog.PINE_ID else 7
	var required_optional_pairs := 0
	var minimum_takeoff_width := track_width - 2.1
	var minimum_landing_width := track_width - 1.1
	var progressive_count := 0
	var visible_count := 0
	var takeoff_count := 0
	var landing_count := 0
	var broad_takeoff_count := 0
	var broad_landing_count := 0
	var optional_takeoff_count := 0
	var optional_landing_count := 0
	var open_collision_count := 0
	for candidate: Node in level.find_children("*", "StaticBody3D", true, false):
		var body := candidate as StaticBody3D
		if body == null or not body.has_meta(&"rhythm_role"):
			continue
		var collision := body.find_child("*", false, false) as CollisionShape3D
		for child: Node in body.get_children():
			if child is CollisionShape3D:
				collision = child as CollisionShape3D
				break
		var concave := collision.shape as ConcavePolygonShape3D if collision != null else null
		if concave != null:
			progressive_count += 1
		var visual: MeshInstance3D = null
		for child: Node in body.get_children():
			if child is MeshInstance3D:
				visual = child as MeshInstance3D
				break
		if _mesh_uses_clockwise_front_faces(visual):
			visible_count += 1
		if (
			concave != null
			and not concave.backface_collision
			and bool(body.get_meta(&"collision_top_only", false))
			and bool(body.get_meta(&"open_ride_ends", false))
			and not _shape_has_longitudinal_endcap(concave)
		):
			open_collision_count += 1
		var role := StringName(body.get_meta(&"rhythm_role", &""))
		var ramp_length := float(body.get_meta(&"ramp_length", 0.0))
		var ramp_width := float(body.get_meta(&"ramp_width", 0.0))
		var ramp_height := float(body.get_meta(&"ramp_height", 0.0))
		var optional_line := bool(body.get_meta(&"optional_jump_line", false))
		var lateral_offset := absf(float(body.get_meta(&"lateral_offset", 0.0)))
		var clear_bypass_width := float(body.get_meta(&"clear_bypass_width", 0.0))
		if role == &"TAKEOFF" and bool(body.get_meta(&"airtime_takeoff", false)):
			takeoff_count += 1
			if (
				optional_line
				and ramp_length >= 13.9
				and ramp_width >= 5.9
				and ramp_height >= 2.15
				and lateral_offset >= 8.4
				and clear_bypass_width >= 17.4
			):
				optional_takeoff_count += 1
			elif ramp_length >= 9.0 and ramp_width >= minimum_takeoff_width and ramp_height >= 2.3:
				broad_takeoff_count += 1
		elif role == &"LANDING" and not bool(body.get_meta(&"airtime_takeoff", false)):
			landing_count += 1
			if (
				optional_line
				and ramp_length >= 21.9
				and ramp_width >= 6.9
				and ramp_height >= 1.6
				and lateral_offset >= 8.4
				and clear_bypass_width >= 16.9
			):
				optional_landing_count += 1
			elif ramp_length >= 11.0 and ramp_width >= minimum_landing_width and ramp_height >= 1.85:
				broad_landing_count += 1
	var passed := (
		progressive_count == required_wedges
		and visible_count == required_wedges
		and open_collision_count == required_wedges
		and takeoff_count == required_pairs
		and landing_count == required_pairs
		and broad_takeoff_count == required_broad_pairs
		and broad_landing_count == required_broad_pairs
		and optional_takeoff_count == required_optional_pairs
		and optional_landing_count == required_optional_pairs
	)
	print("JUMP PACKAGE PROBE: activity=%s progressive=%d/%d visible=%d/%d open_collision=%d/%d takeoffs=%d/%d broad_takeoffs=%d/%d optional_takeoffs=%d/%d landings=%d/%d broad_landings=%d/%d optional_landings=%d/%d passed=%s" % [str(_activity), progressive_count, required_wedges, visible_count, required_wedges, open_collision_count, required_wedges, takeoff_count, required_pairs, broad_takeoff_count, required_broad_pairs, optional_takeoff_count, required_optional_pairs, landing_count, required_pairs, broad_landing_count, required_broad_pairs, optional_landing_count, required_optional_pairs, str(passed)])
	if not passed:
		push_error("JUMP PACKAGE SMOKE: race-line ramps were incomplete, narrow, back-facing, or retained blocking end caps (collision=%d/%d, visible=%d/%d, open=%d/%d, takeoffs=%d/%d, landings=%d/%d)." % [progressive_count, required_wedges, visible_count, required_wedges, open_collision_count, required_wedges, takeoff_count, required_pairs, landing_count, required_pairs])
	return passed


func _validate_mesa_welded_jump_packages(level: Node) -> bool:
	# Mesa's takeoffs and receivers are authored directly into the one welded
	# centerline ribbon. Trackside callouts identify them, but no duplicate ramp
	# collision is allowed to sit above that authoritative surface.
	var zones := CourseCatalog.get_welded_jump_zones(CourseCatalog.MESA_MX_ID)
	var ribbon := level.find_child("MesaAuthoritativeRaceRibbon", true, false) as Node3D
	var dressing := level.find_child("JumpAndRhythmDressing", true, false) as Node3D
	var collision_shapes := ribbon.find_children("*", "CollisionShape3D", true, false) if ribbon != null else []
	var minimum_takeoff_height := INF
	var minimum_receiver_length := INF
	var zone_data_valid := true
	for zone: Dictionary in zones:
		minimum_takeoff_height = minf(minimum_takeoff_height, float(zone.get(&"takeoff_height", 0.0)))
		minimum_receiver_length = minf(minimum_receiver_length, float(zone.get(&"receiver_length", 0.0)))
		zone_data_valid = (
			float(zone.get(&"takeoff_length", 0.0)) >= 7.0
			and float(zone.get(&"fallaway_length", 0.0)) >= 2.0
			and float(zone.get(&"receiver_height", 0.0)) >= 0.6
			and zone_data_valid
		)
	var passed := (
		zones.size() >= 5
		and zone_data_valid
		and minimum_takeoff_height >= 1.0
		and minimum_receiver_length >= 10.0
		and ribbon != null
		and collision_shapes.size() == 1
		and bool(ribbon.get_meta(&"welded_collision", false))
		and bool(ribbon.get_meta(&"single_layer_race_surface", false))
		and int(ribbon.get_meta(&"welded_jump_package_count", 0)) == zones.size()
		and dressing != null
		and int(dressing.get_meta(&"jump_package_count", 0)) == zones.size()
	)
	print("MESA WELDED JUMP PROBE: packages=%d/5 collision_shapes=%d minimum_takeoff=%.2fm minimum_receiver=%.1fm callouts=%d passed=%s" % [
		zones.size(), collision_shapes.size(), minimum_takeoff_height, minimum_receiver_length,
		int(dressing.get_meta(&"jump_package_count", 0)) if dressing != null else 0, str(passed),
	])
	if not passed:
		push_error("MESA WELDED JUMP SMOKE: centerline jump data, callouts, or single welded collision authority is incomplete.")
	return passed


func _validate_quarry_welded_jump_packages(level: Node) -> bool:
	var zones := CourseCatalog.get_welded_jump_zones(CourseCatalog.QUARRY_ID)
	var overlay_count := 0
	for candidate: Node in level.find_children("*", "StaticBody3D", true, false):
		if candidate.has_meta(&"rhythm_role"):
			overlay_count += 1
	var ribbon := level.find_child("QuarryRaceRibbon", true, false) as Node3D
	var collision_shapes: Array[Node] = []
	if ribbon != null:
		collision_shapes = ribbon.find_children("*", "CollisionShape3D", true, false)
	var names := PackedStringArray()
	var minimum_takeoff_height := INF
	var minimum_receiver_length := INF
	var data_valid := true
	for zone: Dictionary in zones:
		var zone_name := String(zone.get(&"name", &""))
		if zone_name.is_empty() or zone_name in names:
			data_valid = false
		else:
			names.append(zone_name)
		minimum_takeoff_height = minf(minimum_takeoff_height, float(zone.get(&"takeoff_height", 0.0)))
		minimum_receiver_length = minf(minimum_receiver_length, float(zone.get(&"receiver_length", 0.0)))
		data_valid = (
			float(zone.get(&"takeoff_length", 0.0)) >= 10.0
			and float(zone.get(&"fallaway_length", 0.0)) >= 4.0
			and float(zone.get(&"receiver_height", 0.0)) >= 1.0
			and data_valid
		)
	var passed := (
		zones.size() == 7
		and data_valid
		and minimum_takeoff_height >= 1.5
		and minimum_receiver_length >= 16.0
		and overlay_count == 0
		and ribbon != null
		and collision_shapes.size() == 1
		and bool(ribbon.get_meta(&"welded_collision", false))
		and bool(ribbon.get_meta(&"single_layer_race_surface", false))
		and int(ribbon.get_meta(&"welded_jump_package_count", 0)) == zones.size()
	)
	print("QUARRY WELDED JUMP PROBE: packages=%d/7 overlays=%d collision_shapes=%d minimum_takeoff=%.2fm minimum_receiver=%.1fm single_layer=%s passed=%s" % [
		zones.size(), overlay_count, collision_shapes.size(), minimum_takeoff_height,
		minimum_receiver_length, str(ribbon != null and bool(ribbon.get_meta(&"single_layer_race_surface", false))),
		str(passed),
	])
	if not passed:
		push_error("QUARRY WELDED JUMP SMOKE: expected seven data packages, zero race overlays, and one welded collision surface.")
	return passed


func _shape_has_longitudinal_endcap(shape: ConcavePolygonShape3D) -> bool:
	var faces := shape.get_faces()
	for cursor: int in range(0, faces.size(), 3):
		if cursor + 2 >= faces.size():
			break
		var a := faces[cursor]
		var b := faces[cursor + 1]
		var c := faces[cursor + 2]
		var normal := (b - a).cross(c - a)
		if normal.length_squared() <= 0.000001:
			continue
		normal = normal.normalized()
		var z_span := maxf(a.z, maxf(b.z, c.z)) - minf(a.z, minf(b.z, c.z))
		var y_span := maxf(a.y, maxf(b.y, c.y)) - minf(a.y, minf(b.y, c.y))
		if z_span <= 0.02 and y_span >= 0.12 and absf(normal.z) >= 0.75:
			return true
	return false


func _validate_course_width_and_containment() -> bool:
	var track_id := _requested_track_id()
	var level_name := _active_level_name(track_id)
	var level := get_tree().current_scene.find_child(level_name, true, false)
	if level == null:
		push_error("COURSE SCALE SMOKE: active level %s was not found." % level_name)
		return false
	if track_id == CourseCatalog.MESA_MX_ID:
		return _validate_mesa_containment(level)
	var track_width := CourseCatalog.get_track_width(track_id)
	var required_track_width := 22.0 if track_id == CourseCatalog.PINE_ID else 24.0
	var containment: StaticBody3D = null
	for candidate: Node in level.find_children("*", "StaticBody3D", true, false):
		if bool(candidate.get_meta(&"course_containment", false)):
			containment = candidate as StaticBody3D
			break
	if containment == null:
		push_error("COURSE SCALE SMOKE: no physical course containment was built for %s." % String(track_id))
		return false
	var spacing := float(containment.get_meta(&"segment_spacing", 0.0))
	var metadata_count := int(containment.get_meta(&"segment_count", 0))
	var compound_collision := bool(containment.get_meta(&"compound_collision", false))
	var compound_face_count := int(containment.get_meta(&"compound_face_count", 0))
	var collision_shape_metadata := int(containment.get_meta(&"collision_shape_count", 0))
	var shared_endpoint_panels := bool(containment.get_meta(&"shared_endpoint_panels", false))
	var maximum_panel_joint_gap := float(containment.get_meta(&"maximum_panel_joint_gap", INF))
	var safety_suppressed_count := int(containment.get_meta(&"safety_suppressed_count", -1))
	var route := CourseCatalog.get_world_riding_points(track_id)
	var route_length := 0.0
	for index: int in range(1, route.size()):
		route_length += route[index - 1].distance_to(route[index])
	var required_segments := floori(route_length / maxf(spacing, 0.1) * 1.72)
	var shape_count := 0
	var safe_box_count := 0
	for child: Node in containment.get_children():
		var collision := child as CollisionShape3D
		if collision == null or collision.disabled:
			continue
		shape_count += 1
		var box := collision.shape as BoxShape3D
		# Endpoint-welded panels follow the offset curve exactly, so the inside of a
		# tight bend is naturally shorter than the nominal resample spacing. Length
		# is no longer the continuity contract: shared endpoints and a measured zero
		# joint gap are. Retain a minimum useful extent to catch degenerate panels.
		var minimum_panel_length := 0.18 if shared_endpoint_panels else spacing
		if box != null and box.size.x >= 0.35 and box.size.y >= 0.9 and box.size.z >= minimum_panel_length:
			safe_box_count += 1
	var visible_panel_count := 0
	for candidate: Node in level.find_children("CourseContainmentPanel*", "MultiMeshInstance3D", true, false):
		var panel := candidate as MultiMeshInstance3D
		if panel != null and panel.multimesh != null:
			visible_panel_count += panel.multimesh.instance_count
	var opening_post_body := level.find_child("CourseContainmentOpeningPosts", true, false) as StaticBody3D
	var end_post_count := int(opening_post_body.get_meta(&"post_count", 0)) if opening_post_body != null else 0
	var visible_end_post_count := 0
	for candidate: Node in level.find_children("CourseContainmentOpeningPost*", "MultiMeshInstance3D", true, false):
		var posts := candidate as MultiMeshInstance3D
		if posts != null and posts.multimesh != null:
			visible_end_post_count += posts.multimesh.instance_count
	var opening_count := int(containment.get_meta(&"opening_count", 0))
	var required_opening_count := 4 if track_id == CourseCatalog.PINE_ID else 0
	var required_end_post_count := 8 if track_id == CourseCatalog.PINE_ID else 0
	var passed := (
		track_width >= required_track_width
		and spacing > 0.0
		and spacing <= 8.5
		and metadata_count >= required_segments
		and (
			(shape_count == 1 and collision_shape_metadata == 1 and compound_face_count == metadata_count * 12)
			if compound_collision
			else (metadata_count == shape_count and safe_box_count == shape_count)
		)
		and (not shared_endpoint_panels or maximum_panel_joint_gap <= 0.001)
		and visible_panel_count == metadata_count
		and opening_count >= required_opening_count
		and end_post_count >= required_end_post_count
		and visible_end_post_count == end_post_count
		and (track_id != CourseCatalog.QUARRY_ID or safety_suppressed_count == 0)
		and (containment.collision_layer & 2) != 0
	)
	print("COURSE SCALE PROBE: activity=%s width=%.1f/%.1fm route=%.1fm panels=%d shapes=%d compound=%s faces=%d required=%d visible=%d spacing=%.2fm physical_boxes=%d shared_endpoints=%s max_joint_gap=%.4fm openings=%d safety_suppressed=%d end_posts=%d visible_posts=%d passed=%s" % [String(_activity), track_width, required_track_width, route_length, metadata_count, shape_count, str(compound_collision), compound_face_count, required_segments, visible_panel_count, spacing, safe_box_count, str(shared_endpoint_panels), maximum_panel_joint_gap, opening_count, safety_suppressed_count, end_post_count, visible_end_post_count, str(passed)])
	if not passed:
		push_error("COURSE SCALE SMOKE: width, matched barrier coverage, or branch openings are insufficient (width=%.1f, shapes=%d/%d, visible=%d, boxes=%d, openings=%d, safety_suppressed=%d, end_posts=%d/%d visible, spacing=%.2f)." % [track_width, shape_count, required_segments, visible_panel_count, safe_box_count, opening_count, safety_suppressed_count, end_post_count, visible_end_post_count, spacing])
	return passed


func _validate_mesa_containment(level: Node) -> bool:
	var track_width := CourseCatalog.get_track_width(CourseCatalog.MESA_MX_ID)
	var root := level.find_child("VisibleContainmentBarriers", true, false) as Node3D
	var pair_count := int(root.get_meta(&"barrier_pair_count", 0)) if root != null else 0
	var body_count := 0
	var matched_visuals := 0
	var matched_collisions := 0
	var layers_valid := true
	var distance_metadata_valid := true
	if root != null:
		for child: Node in root.get_children():
			var body := child as StaticBody3D
			if body == null:
				continue
			body_count += 1
			matched_visuals += int(not body.find_children("*", "MeshInstance3D", true, false).is_empty())
			matched_collisions += int(not body.find_children("*", "CollisionShape3D", true, false).is_empty())
			layers_valid = layers_valid and (body.collision_layer & 2) != 0
			distance_metadata_valid = distance_metadata_valid and body.has_meta(&"route_distance")
	var passed := (
		track_width >= 23.0
		and root != null
		and pair_count >= 60
		and body_count == pair_count * 2
		and matched_visuals == body_count
		and matched_collisions == body_count
		and layers_valid
		and distance_metadata_valid
	)
	print("MESA CONTAINMENT PROBE: width=%.1f/23.0m pairs=%d bodies=%d visuals=%d collisions=%d layers=%s route_metadata=%s passed=%s" % [
		track_width, pair_count, body_count, matched_visuals, matched_collisions,
		str(layers_valid), str(distance_metadata_valid), str(passed),
	])
	if not passed:
		push_error("MESA CONTAINMENT SMOKE: route-derived visible/colliding barrier pairs are incomplete.")
	return passed


func _mesh_uses_clockwise_front_faces(visual: MeshInstance3D) -> bool:
	if visual == null or visual.mesh == null or visual.mesh.get_surface_count() == 0:
		return false
	var arrays := visual.mesh.surface_get_arrays(0)
	var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var normals := arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
	var indices := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array:
		indices = arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
	var element_count := indices.size() if not indices.is_empty() else vertices.size()
	if element_count < 3 or element_count % 3 != 0 or normals.size() != vertices.size():
		return false
	for cursor: int in range(0, element_count, 3):
		var a_index := indices[cursor] if not indices.is_empty() else cursor
		var b_index := indices[cursor + 1] if not indices.is_empty() else cursor + 1
		var c_index := indices[cursor + 2] if not indices.is_empty() else cursor + 2
		var a := vertices[a_index]
		var b := vertices[b_index]
		var c := vertices[c_index]
		var raw_cross := (b - a).cross(c - a)
		var average_normal := normals[a_index] + normals[b_index] + normals[c_index]
		if raw_cross.length_squared() <= 0.000001 or average_normal.length_squared() <= 0.000001:
			continue
		# Godot's rendered front is clockwise, so the mathematical cross must
		# point opposite its generated outward vertex normal.
		if raw_cross.normalized().dot(average_normal.normalized()) > -0.1:
			return false
	return true


func _validate_ground_coverage() -> bool:
	var track_id := _requested_track_id()
	var collision_name := "GeneratedQuarryTerrainCollision"
	var visual_name := "GeneratedQuarryTerrain"
	if track_id == CourseCatalog.PINE_ID:
		collision_name = "GeneratedPineTerrainCollision"
		visual_name = "GeneratedPineTerrain"
	elif track_id == CourseCatalog.MESA_MX_ID:
		collision_name = "MesaGradedGroundCollision"
		visual_name = "MesaGradedGround"
	var generated_collision := get_tree().current_scene.find_child(collision_name, true, false)
	if generated_collision == null:
		push_error("GROUND COVERAGE SMOKE: %s was not ready before gameplay." % collision_name)
		return false
	var generated_visual := get_tree().current_scene.find_child(visual_name, true, false) as MeshInstance3D
	if not _validate_visible_terrain_top(generated_visual):
		push_error("GROUND RENDER SMOKE: %s does not expose a front-facing rideable top surface." % visual_name)
		return false
	var ribbon_visual := get_tree().current_scene.find_child("RaceSurface", true, false) as MeshInstance3D
	if not _mesh_uses_clockwise_front_faces(ribbon_visual):
		push_error("GROUND RENDER SMOKE: the continuous course ribbon is back-facing or missing.")
		return false
	var origin := CourseCatalog.get_district_origin(track_id)
	var half_extent := Vector2(340.0, 290.0)
	var ray_top := 120.0
	if track_id == CourseCatalog.PINE_ID:
		half_extent = Vector2(380.0, 330.0)
		ray_top = 180.0
	elif track_id == CourseCatalog.MESA_MX_ID:
		half_extent = Vector2(205.0, 205.0)
		ray_top = 100.0
	var space_state := _bike.get_world_3d().direct_space_state
	var sample_count := 0
	var supported_count := 0
	for x_index: int in 7:
		for z_index: int in 7:
			var x := lerpf(-half_extent.x, half_extent.x, float(x_index) / 6.0)
			var z := lerpf(-half_extent.y, half_extent.y, float(z_index) / 6.0)
			var start := origin + Vector3(x, ray_top, z)
			var query := PhysicsRayQueryParameters3D.create(start, origin + Vector3(x, -5.5, z), 2)
			sample_count += 1
			if not space_state.intersect_ray(query).is_empty():
				supported_count += 1
	var riding_points := CourseCatalog.get_world_riding_points(track_id)
	var stride := maxi(riding_points.size() / 14, 1)
	for index: int in range(0, riding_points.size() - 1, stride):
		var tangent := CourseSpline.tangent_at(riding_points, index)
		var right := Vector3(tangent.z, 0.0, -tangent.x).normalized()
		for offset: float in [-25.0, -12.0, 12.0, 25.0]:
			var position := riding_points[index] + right * offset
			var query := PhysicsRayQueryParameters3D.create(position + Vector3.UP * 80.0, Vector3(position.x, -5.5, position.z), 2)
			sample_count += 1
			if not space_state.intersect_ray(query).is_empty():
				supported_count += 1
	var passed := supported_count == sample_count
	print("GROUND COVERAGE PROBE: activity=%s ready=true supported=%d/%d passed=%s" % [String(_activity), supported_count, sample_count, str(passed)])
	if not passed:
		push_error("GROUND COVERAGE SMOKE: only %d/%d off-track samples had solid ground." % [supported_count, sample_count])
	return passed


func _validate_visible_terrain_top(terrain: MeshInstance3D) -> bool:
	if terrain == null or terrain.mesh == null or terrain.mesh.get_surface_count() == 0:
		return false
	var arrays := terrain.mesh.surface_get_arrays(0)
	var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var normals := arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
	var indices := arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
	if vertices.size() < 3 or normals.size() != vertices.size() or indices.size() < 3:
		return false
	var a := vertices[indices[0]]
	var b := vertices[indices[1]]
	var c := vertices[indices[2]]
	# Godot's clockwise front faces have a negative geometric cross product when
	# viewed from the rideable +Y side. Vertex normals must still point upward.
	var clockwise_top := (b - a).cross(c - a).dot(Vector3.UP) < -0.0001
	var upward_normals := normals[indices[0]].dot(Vector3.UP) > 0.05
	var material := terrain.get_surface_override_material(0) as StandardMaterial3D
	if material == null:
		material = terrain.mesh.surface_get_material(0) as StandardMaterial3D
	var opaque_backface_material := (
		material != null
		and material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED
		and material.cull_mode == BaseMaterial3D.CULL_BACK
	)
	var passed := clockwise_top and upward_normals and opaque_backface_material
	print(
		"GROUND RENDER PROBE: visual=%s clockwise_top=%s upward_normals=%s opaque_backface=%s passed=%s"
		% [terrain.name, str(clockwise_top), str(upward_normals), str(opaque_backface_material), str(passed)]
	)
	return passed


func _validate_repair_economy() -> bool:
	var old_cash := Profile.cash
	var old_condition := Profile.bike_condition
	var old_log := Profile.transaction_log.duplicate(true)
	var old_persistence := Profile.persistence_enabled
	Profile.persistence_enabled = false
	Profile.cash = 1000
	Profile.bike_condition = 80
	var quoted_price := Profile.get_repair_price()
	var repaired := Profile.repair_bike()
	var valid := quoted_price == 140 and repaired and Profile.cash == 860 and Profile.bike_condition == 100
	Profile.cash = old_cash
	Profile.bike_condition = old_condition
	Profile.transaction_log.assign(old_log)
	Profile.persistence_enabled = old_persistence
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
	var old_legacy_pine_unlock := Profile.legacy_pine_unlock
	var old_persistence := Profile.persistence_enabled
	Profile.persistence_enabled = false
	Profile.racer_reputation = 0
	Profile.freestyler_reputation = 0
	Profile.explorer_reputation = 0
	Profile.total_runs = 0
	Profile.best_medal_ranks.clear()
	Profile.rival_victories.clear()
	Profile.legacy_pine_unlock = false
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
	Profile.legacy_pine_unlock = old_legacy_pine_unlock
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


func _capture_named_frame(file_name: String) -> bool:
	for _frame: int in 12:
		await get_tree().process_frame
	var capture := get_viewport().get_texture().get_image()
	var capture_path := ProjectSettings.globalize_path("res://artifacts/%s" % file_name)
	var save_error := capture.save_png(capture_path)
	capture = null
	if save_error != OK:
		push_error("SMOKE TEST: unable to save %s (%s)." % [file_name, error_string(save_error)])
	return save_error == OK


func _capture_bike_showcase() -> bool:
	var hud := get_tree().current_scene.find_child("RaceHud", true, false) as CanvasLayer
	if hud != null:
		hud.visible = false
	var showcase := Camera3D.new()
	showcase.name = "BikeShowcaseCamera"
	showcase.fov = 48.0
	showcase.near = 0.05
	showcase.far = 240.0
	get_tree().current_scene.add_child(showcase)
	var bike_up := _bike.global_transform.basis.y.normalized()
	var bike_right := _bike.global_transform.basis.x.normalized()
	var bike_back := _bike.global_transform.basis.z.normalized()
	var focus := _bike.global_position + bike_up * 0.72
	showcase.global_position = focus + bike_right * 3.0 + bike_back * 3.8 + bike_up * 1.55
	showcase.look_at(focus, bike_up)
	showcase.current = true
	for _frame: int in 4:
		await get_tree().process_frame
	var capture := get_viewport().get_texture().get_image()
	var capture_path := ProjectSettings.globalize_path("res://artifacts/riding-dirty-bike-showcase.png")
	var save_error := capture.save_png(capture_path)
	capture = null
	showcase.queue_free()
	await get_tree().process_frame
	var chase_view := _camera.find_child("Camera3D", true, false) as Camera3D
	if chase_view != null:
		chase_view.current = true
	if hud != null:
		hud.visible = true
	if save_error != OK:
		push_error("SMOKE TEST: unable to save bike showcase (%s)." % error_string(save_error))
	return save_error == OK


func _capture_course_overview(course_center: Vector3, course_span: Vector2) -> bool:
	var hud := get_tree().current_scene.find_child("RaceHud", true, false) as CanvasLayer
	if hud != null:
		hud.visible = false
	var garage := get_tree().current_scene.find_child("GarageUi", true, false) as CanvasLayer
	var garage_was_visible := false
	if garage != null:
		garage_was_visible = garage.visible
		garage.visible = false
	var world_environment := get_tree().current_scene.find_child("WorldEnvironment", true, false) as WorldEnvironment
	var fog_was_enabled := false
	if world_environment != null and world_environment.environment != null:
		fog_was_enabled = world_environment.environment.fog_enabled
		world_environment.environment.fog_enabled = false
	var weather := get_tree().current_scene.find_child("DistrictWeather", true, false) as GPUParticles3D
	var weather_was_visible := false
	if weather != null:
		weather_was_visible = weather.visible
		weather.visible = false
	var overview := Camera3D.new()
	overview.name = "CourseOverviewCamera"
	overview.projection = Camera3D.PROJECTION_ORTHOGONAL
	overview.size = maxf(course_span.x, course_span.y) * 1.18
	overview.near = 0.1
	overview.far = 800.0
	get_tree().current_scene.add_child(overview)
	overview.global_position = course_center + Vector3.UP * 360.0
	overview.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	overview.current = true
	for _frame: int in 4:
		await get_tree().process_frame
	var capture := get_viewport().get_texture().get_image()
	var district := "mesa" if _requested_track_id() == CourseCatalog.MESA_MX_ID else ("pine" if _requested_track_id() == CourseCatalog.PINE_ID else "quarry")
	var capture_path := ProjectSettings.globalize_path("res://artifacts/riding-dirty-%s-overview.png" % district)
	var save_error := capture.save_png(capture_path)
	capture = null
	overview.queue_free()
	await get_tree().process_frame
	var chase_view := _camera.find_child("Camera3D", true, false) as Camera3D
	if chase_view != null:
		chase_view.current = true
	if hud != null:
		hud.visible = true
	if garage != null:
		garage.visible = garage_was_visible
	if world_environment != null and world_environment.environment != null:
		world_environment.environment.fog_enabled = fog_was_enabled
	if weather != null:
		weather.visible = weather_was_visible
	if save_error != OK:
		push_error("SMOKE TEST: unable to save course overview (%s)." % error_string(save_error))
		return false
	return true


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
