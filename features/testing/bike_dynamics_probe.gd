extends Node
## Focused deterministic probe for support reach, suspension release, drive, and steer.
## Run with:
## Godot --headless --path . res://features/testing/bike_dynamics_probe.tscn -- --smoke-test


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var world := Node3D.new()
	add_child(world)
	var ground := StaticBody3D.new()
	ground.collision_layer = 2
	ground.collision_mask = 1
	ground.set_meta(&"surface", &"PACKED")
	ground.set_meta(&"roughness", 0.35)
	var ground_shape := BoxShape3D.new()
	ground_shape.size = Vector3(220.0, 0.5, 220.0)
	var ground_collision := CollisionShape3D.new()
	ground_collision.shape = ground_shape
	ground.position.y = -0.25
	ground.add_child(ground_collision)
	world.add_child(ground)
	var receiver: Dictionary = _add_receiver_slope(world)

	var bike_scene := load("res://entities/bike/bike.tscn") as PackedScene
	var bike := bike_scene.instantiate() as DirtBikeController
	world.add_child(bike)
	bike.set_controls_enabled(true)
	var camera_scene := load("res://features/camera/chase_camera.tscn") as PackedScene
	var chase_camera := camera_scene.instantiate() as ChaseCamera
	world.add_child(chase_camera)
	chase_camera.target = bike
	chase_camera.snap_to_target()
	var landing_query := bike.get("_landing_query") as PhysicsRayQueryParameters3D
	var camera_query := chase_camera.get("_obstruction_query") as PhysicsRayQueryParameters3D
	var landing_query_id := landing_query.get_instance_id() if landing_query != null else 0
	var camera_query_id := camera_query.get_instance_id() if camera_query != null else 0
	var front_ray := bike.get_node("FrontSuspension") as RayCast3D
	var rear_ray := bike.get_node("RearSuspension") as RayCast3D
	var reference_contract := (
		is_equal_approx(bike.mass, 200.0)
		and is_equal_approx(bike.gravity_scale * 19.6, 12.0)
		and is_equal_approx(absf(front_ray.position.z - rear_ray.position.z), 1.33729)
		and is_equal_approx(bike.wheel_radius, 0.307)
		and is_equal_approx(bike.spring_stiffness, 20000.0)
		and is_equal_approx(bike.spring_compression_damping, 380.0)
		and is_equal_approx(bike.spring_rebound_damping, 2400.0)
		and is_equal_approx(bike.rolling_drag, 0.0)
		and bike.rear_countersteer_ratio <= 0.05
		and bike.steering_input_rise_rate >= 4.5
		and bike.steering_input_release_rate >= 8.0
		and bike.steering_input_reversal_rate >= 10.0
		and bike.low_speed_turn_curvature > bike.high_speed_turn_curvature
		and bike.maximum_ground_yaw_rate <= 1.6
		and bike.upright_strength >= 8000.0
		and bike.chassis_lateral_stiffness >= 2200.0
		and bike.chassis_lateral_force_limit >= 11000.0
		and is_equal_approx(bike.front_longitudinal_grip_scale, 0.95)
		and is_equal_approx(bike.rear_longitudinal_grip_scale, 1.62)
		and bike.front_lateral_grip_scale >= 1.0
		and bike.rear_lateral_grip_scale >= 1.0
	)
	var opposed_normal_fallback: Dictionary = _measure_opposed_normal_fallback(bike)
	var fallback_normal := opposed_normal_fallback[&"normal"] as Vector3
	var opposed_normal_fallback_passed := (
		bool(opposed_normal_fallback[&"finite"])
		and fallback_normal.dot(Vector3.UP) >= 0.999
	)

	# Both rays hit at this height, but the wheels are beyond suspension reach.
	bike.respawn_at(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.18, 0.0)))
	await get_tree().physics_frame
	var phantom_contact_clear := not bike.is_grounded()

	# Settle at ride height before exercising drive and steering.
	bike.respawn_at(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.67, 0.0)))
	# Grid stability is part of the handling contract: a stationary bike must not
	# slowly pitch-loop while the countdown, camera, and web input focus settle.
	await _wait_physics_frames(300)
	var planted := bike.is_grounded() and is_finite(bike.global_position.y)
	var idle_upright := bike.global_transform.basis.y.normalized().dot(Vector3.UP) > 0.75
	var drive_start := bike.global_position
	Input.action_press(InputRouter.THROTTLE, 1.0)
	await _wait_physics_frames(150)
	var drive_distance := Vector2(drive_start.x, drive_start.z).distance_to(Vector2(bike.global_position.x, bike.global_position.z))
	Input.action_release(InputRouter.THROTTLE)

	# Exercise the actual live-course surfaces under every assist preset. The
	# controller's tire direction must stay planted even in PRO; assists may
	# change rider balance, but cannot be the source of basic cornering grip.
	var pro_dirt: Dictionary = await _measure_turn_case(bike, &"DIRT", &"PRO")
	var pro_loam: Dictionary = await _measure_turn_case(bike, &"LOAM", &"PRO")
	var pro_dirt_fast: Dictionary = await _measure_turn_case(bike, &"DIRT", &"PRO", 24.0)
	var pro_dirt_hard: Dictionary = await _measure_turn_case(bike, &"DIRT", &"PRO", 14.0, 0.9)
	var sport_dirt: Dictionary = await _measure_turn_case(bike, &"DIRT", &"SPORT")
	var assisted_dirt: Dictionary = await _measure_turn_case(bike, &"DIRT", &"ASSISTED")
	var keyboard_step: Dictionary = await _measure_keyboard_step_case(bike, chase_camera)
	var keyboard_alternating: Dictionary = await _measure_keyboard_alternating_case(bike)
	var keyboard_tap: Dictionary = await _measure_keyboard_tap_case(bike)
	var signed_forward_steering: Dictionary = await _measure_signed_forward_steering_case(bike)
	var reverse_steering: Dictionary = await _measure_reverse_steering_case(bike)
	var minimum_steer_up: float = float(pro_dirt[&"minimum_up"])
	var maximum_sideslip_angle: float = float(pro_dirt[&"peak_sideslip"])
	var maximum_lateral_speed: float = float(pro_dirt[&"peak_lateral_speed"])
	var steer_change: float = float(pro_dirt[&"heading_change"])
	var final_steer_up: float = float(pro_dirt[&"final_up"])
	var recovered_lateral_speed: float = float(pro_dirt[&"recovered_lateral_speed"])
	var recovered_sideslip_angle: float = float(pro_dirt[&"recovered_sideslip"])
	var remained_stable := minimum_steer_up > 0.55 and final_steer_up > 0.75
	var planted_grip_passed := (
		_turn_case_is_planted(pro_dirt)
		and _turn_case_is_planted(pro_loam)
		and _turn_case_is_planted(pro_dirt_fast)
		and _hard_turn_case_is_controlled(pro_dirt_hard)
		and _turn_case_is_planted(sport_dirt)
		and _turn_case_is_planted(assisted_dirt)
	)
	var steering_response_passed := (
		_keyboard_step_is_direct(keyboard_step)
		and _keyboard_alternating_is_direct(keyboard_alternating)
		and _keyboard_tap_is_direct(keyboard_tap)
	)
	var signed_steering_passed := _signed_forward_steering_is_correct(signed_forward_steering)
	var reverse_steering_passed := _reverse_steering_is_correct(reverse_steering)
	var contact_direction := bike.global_transform.basis.x.normalized()
	var velocity_before_contact := bike.linear_velocity
	var contact_applied := bike.apply_pack_contact(contact_direction, 6.0, bike.global_position)
	var repeat_contact_rejected := not bike.apply_pack_contact(-contact_direction, 6.0, bike.global_position)
	await get_tree().physics_frame
	var pack_contact_delta := (bike.linear_velocity - velocity_before_contact).length()
	await _wait_physics_frames(42)
	var post_contact_lateral := absf(bike.linear_velocity.dot(bike.global_transform.basis.x.normalized()))
	var pack_contact_passed := (
		contact_applied
		and repeat_contact_rejected
		and pack_contact_delta >= 0.35
		and pack_contact_delta <= 1.25
		and post_contact_lateral <= 1.0
	)

	# A clean upward impulse must release the wheel support rather than retain
	# minimum-load grip while the rays still see the ground below.
	bike.apply_central_impulse(Vector3.UP * bike.mass * 5.0)
	var released_support := false
	for _frame: int in 14:
		await get_tree().physics_frame
		released_support = released_support or not bike.is_grounded()
	var vertical_speed_before_pop := bike.linear_velocity.y
	Input.action_press(InputRouter.BRAKE, 1.0)
	await get_tree().physics_frame
	Input.action_release(InputRouter.BRAKE)
	var brake_pop_delta := bike.linear_velocity.y - vertical_speed_before_pop
	var brake_pop_passed := brake_pop_delta > 0.75
	Input.action_press(InputRouter.LEAN_FORWARD, 1.0)
	await _wait_physics_frames(24)
	Input.action_release(InputRouter.LEAN_FORWARD)
	var air_pitch := asin(clampf((-bike.global_transform.basis.z).normalized().y, -1.0, 1.0))
	var air_pitch_control_passed := air_pitch < -0.06
	var sustained_air_pitch: Dictionary = await _measure_sustained_air_forward_case(bike)
	var sustained_air_pitch_passed := _sustained_air_pitch_is_controlled(sustained_air_pitch)
	var landing_strength := bike.landing_alignment_strength
	var baseline_receiver: Dictionary = await _measure_receiver_alignment(
		bike,
		0.0,
		receiver
	)
	var assisted_receiver: Dictionary = await _measure_receiver_alignment(
		bike,
		landing_strength,
		receiver
	)
	bike.landing_alignment_strength = landing_strength
	var receiver_alignment_passed := (
		bool(baseline_receiver[&"landed"])
		and bool(assisted_receiver[&"landed"])
		and float(assisted_receiver[&"touchdown_error"]) <= float(baseline_receiver[&"touchdown_error"]) - deg_to_rad(2.0)
		and float(assisted_receiver[&"touchdown_error"]) <= deg_to_rad(13.0)
		and float(assisted_receiver[&"recovery_error"]) <= deg_to_rad(8.0)
		and float(assisted_receiver[&"peak_weight"]) >= 0.15
	)
	var camera_speed_feedback: Dictionary = await _measure_camera_speed_feedback(bike, chase_camera)
	var camera_speed_feedback_passed := (
		chase_camera.base_fov >= 76.0
		and chase_camera.base_fov <= 80.0
		and chase_camera.maximum_fov >= 90.0
		and chase_camera.maximum_fov <= 94.0
		and float(camera_speed_feedback[&"rest_fov"]) >= chase_camera.base_fov - 0.75
		and float(camera_speed_feedback[&"rest_fov"]) <= chase_camera.base_fov + 0.75
		and float(camera_speed_feedback[&"speed_fov"]) >= float(camera_speed_feedback[&"rest_fov"]) + 7.5
		and float(camera_speed_feedback[&"speed_fov"]) <= chase_camera.maximum_fov + 0.25
		and float(camera_speed_feedback[&"feedback_strength"]) >= 0.008
	)

	# Regression for the progressive race-line jump package. Start at a measured
	# 20 m/s so this probes face curvature and lip-speed retention independently
	# from the length of a particular in-world approach.
	_add_jump_ramp(world)
	bike.respawn_at(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.62, 5.0)))
	await _wait_physics_frames(60)
	bike.linear_velocity = Vector3(0.0, 0.0, -20.0)
	Input.action_press(InputRouter.THROTTLE, 1.0)
	var entry_speed := bike.get_speed_mps()
	var lip_speed := 0.0
	var takeoff_vertical_speed := 0.0
	var lip_sampled := false
	var jump_started := false
	var jump_landed := false
	var jump_airtime := 0.0
	var jump_distance := 0.0
	var jump_takeoff_position := Vector3.ZERO
	var jump_apex_y := -INF
	for _frame: int in 720:
		await get_tree().physics_frame
		if not lip_sampled and bike.global_position.z <= -15.0:
			lip_sampled = true
			lip_speed = bike.linear_velocity.length()
			takeoff_vertical_speed = bike.linear_velocity.y
		if not jump_started and bike.global_position.z < -14.0 and not bike.is_grounded():
			jump_started = true
			jump_takeoff_position = bike.global_position
			jump_apex_y = bike.global_position.y
			jump_airtime = 1.0 / 60.0
		elif jump_started and not jump_landed:
			jump_apex_y = maxf(jump_apex_y, bike.global_position.y)
			if not bike.is_grounded():
				jump_airtime += 1.0 / 60.0
			elif jump_airtime >= 0.2:
				jump_landed = true
				jump_distance = Vector2(jump_takeoff_position.x, jump_takeoff_position.z).distance_to(Vector2(bike.global_position.x, bike.global_position.z))
				break
	Input.action_release(InputRouter.THROTTLE)
	var jump_apex_gain := jump_apex_y - jump_takeoff_position.y if jump_started else 0.0
	var speed_retention := lip_speed / maxf(entry_speed, 0.001)
	var jump_passed := (
		jump_started
		and jump_landed
		and speed_retention >= 0.95
		and takeoff_vertical_speed >= 9.0
		and jump_airtime >= 1.9
		and jump_distance >= 30.0
		and jump_apex_gain >= 3.5
	)

	# A stopped bike that is knocked onto its side must not leave the player lying
	# on the terrain. Preserve an upright safe sample, tip the live body, and allow
	# the physical/self-recovery path to restore it.
	bike.respawn_at(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.67, 24.0)))
	await _wait_physics_frames(60)
	bike.set_motion_locked(true)
	bike.global_transform = Transform3D(Basis(Vector3.FORWARD, deg_to_rad(80.0)), Vector3(0.0, 0.67, 24.0))
	bike.set_motion_locked(false)
	await _wait_physics_frames(180)
	var recovery_up := bike.global_transform.basis.y.normalized().dot(Vector3.UP)
	var tipped_recovery_passed := recovery_up > 0.75

	# Garage sliders are part of the handling contract, not presentation-only
	# ratings. Exercise the public build entry point after the dynamics cases so
	# these deliberately strong settings cannot influence the baseline measures.
	var tuned_stats: Dictionary = {
		&"power": 70.0,
		&"acceleration": 72.0,
		&"top_speed": 63.0,
		&"grip": 78.0,
		&"braking": 74.0,
		&"suspension": 72.0,
		&"stability": 76.0,
		&"air_control": 86.0,
	}
	var tuned_build: Dictionary = {
		&"stats": tuned_stats,
		&"build": {
			&"tune": {
				&"suspension_stiffness": 0.8,
				&"suspension_damping": 0.75,
				&"brake_bias": 0.5,
				&"jump_preload": 0.8,
			},
		},
	}
	bike.apply_setup(&"BALANCED")
	bike.apply_racing_build(tuned_build)
	var tuning_snapshot: Dictionary = bike.get_build_tuning_snapshot()
	var physical_tune_passed := (
		float(tuning_snapshot.get(&"spring_stiffness", 0.0)) > 20_000.0
		and float(tuning_snapshot.get(&"spring_compression_damping", 0.0)) > 380.0
		and float(tuning_snapshot.get(&"spring_rebound_damping", 0.0)) > 2400.0
		and float(tuning_snapshot.get(&"front_brake_bias", 0.0)) > 0.333333
		and float(tuning_snapshot.get(&"preload_impulse", 0.0)) > 230.0
	)
	var final_landing_query := bike.get("_landing_query") as PhysicsRayQueryParameters3D
	var final_camera_query := chase_camera.get("_obstruction_query") as PhysicsRayQueryParameters3D
	var physics_query_pool_passed := (
		landing_query_id != 0
		and camera_query_id != 0
		and final_landing_query != null
		and final_camera_query != null
		and final_landing_query.get_instance_id() == landing_query_id
		and final_camera_query.get_instance_id() == camera_query_id
	)

	var passed := (
		reference_contract
		and opposed_normal_fallback_passed
		and phantom_contact_clear
		and planted
		and idle_upright
		and drive_distance > 10.0
		and steer_change > 0.08
		and steer_change < 2.6
		and remained_stable
		and planted_grip_passed
		and steering_response_passed
		and signed_steering_passed
		and reverse_steering_passed
		and pack_contact_passed
		and released_support
		and brake_pop_passed
		and air_pitch_control_passed
		and sustained_air_pitch_passed
		and receiver_alignment_passed
		and camera_speed_feedback_passed
		and jump_passed
		and tipped_recovery_passed
		and physical_tune_passed
		and physics_query_pool_passed
	)
	_print_turn_case(&"PRO_DIRT", pro_dirt)
	_print_turn_case(&"PRO_LOAM", pro_loam)
	_print_turn_case(&"PRO_DIRT_FAST", pro_dirt_fast)
	_print_turn_case(&"PRO_DIRT_HARD", pro_dirt_hard)
	_print_turn_case(&"SPORT_DIRT", sport_dirt)
	_print_turn_case(&"ASSISTED_DIRT", assisted_dirt)
	_print_keyboard_case(&"STEP", keyboard_step)
	_print_keyboard_case(&"ALTERNATING", keyboard_alternating)
	_print_keyboard_case(&"TAP_RELEASE", keyboard_tap)
	_print_signed_steering(signed_forward_steering, reverse_steering)
	_print_air_pitch_case(sustained_air_pitch)
	print(
		"RECEIVER ALIGNMENT: baseline_touch=%.1fdeg assisted_touch=%.1fdeg assisted_recovery=%.1fdeg peak_weight=%.3f landed=%s passed=%s"
		% [
			rad_to_deg(float(baseline_receiver[&"touchdown_error"])),
			rad_to_deg(float(assisted_receiver[&"touchdown_error"])),
			rad_to_deg(float(assisted_receiver[&"recovery_error"])),
			float(assisted_receiver[&"peak_weight"]),
			str(assisted_receiver[&"landed"]),
			str(receiver_alignment_passed),
		]
	)
	print(
		"CAMERA SPEED FEEDBACK: rest_fov=%.1f speed_fov=%.1f feedback=%.3f passed=%s"
		% [
			float(camera_speed_feedback[&"rest_fov"]),
			float(camera_speed_feedback[&"speed_fov"]),
			float(camera_speed_feedback[&"feedback_strength"]),
			str(camera_speed_feedback_passed),
		]
	)
	print(
		"PHYSICAL TUNE: stiffness=%.1f compression=%.1f rebound=%.1f front_bias=%.3f preload=%.1f passed=%s"
		% [
			float(tuning_snapshot.get(&"spring_stiffness", 0.0)),
			float(tuning_snapshot.get(&"spring_compression_damping", 0.0)),
			float(tuning_snapshot.get(&"spring_rebound_damping", 0.0)),
			float(tuning_snapshot.get(&"front_brake_bias", 0.0)),
			float(tuning_snapshot.get(&"preload_impulse", 0.0)),
			str(physical_tune_passed),
		]
	)
	print(
		"GROUND NORMAL FALLBACK: normal=%s finite=%s passed=%s"
		% [
			str(opposed_normal_fallback[&"normal"]),
			str(opposed_normal_fallback[&"finite"]),
			str(opposed_normal_fallback_passed),
		]
	)
	print(
		"PHYSICS QUERY POOL: landing_id=%d camera_id=%d stable=%s"
		% [landing_query_id, camera_query_id, str(physics_query_pool_passed)]
	)
	print(
		"BIKE DYNAMICS PROBE: reference_contract=%s phantom_clear=%s planted=%s idle_upright=%s drive=%.2fm steer=%.3frad bank=%.1fdeg lateral=%.2fm/s slip_angle=%.3frad recovered_lateral=%.2fm/s recovered_slip=%.3frad planted_grip=%s steering_response=%s contact_delta=%.2fm/s contact_settle=%.2fm/s contact_safe=%s min_up=%.3f final_up=%.3f stable=%s released=%s brake_pop=%.2f air_pitch=%.3f jump_started=%s landed=%s entry=%.2f lip=%.2f retention=%.3f vy=%.2f airtime=%.2fs distance=%.2fm apex_gain=%.2fm recovery_up=%.3f"
		% [
			str(reference_contract),
			str(phantom_contact_clear),
			str(planted),
			str(idle_upright),
			drive_distance,
			steer_change,
			rad_to_deg(float(pro_dirt[&"steady_bank"])),
			maximum_lateral_speed,
			maximum_sideslip_angle,
			recovered_lateral_speed,
			recovered_sideslip_angle,
			str(planted_grip_passed),
			str(steering_response_passed),
			pack_contact_delta,
			post_contact_lateral,
			str(pack_contact_passed),
			minimum_steer_up,
			final_steer_up,
			str(remained_stable),
			str(released_support),
			brake_pop_delta,
			air_pitch,
			str(jump_started),
			str(jump_landed),
			entry_speed,
			lip_speed,
			speed_retention,
			takeoff_vertical_speed,
			jump_airtime,
			jump_distance,
			jump_apex_gain,
			recovery_up,
		]
	)
	bike.shutdown_audio()
	await get_tree().process_frame
	get_tree().quit(0 if passed else 1)


func _measure_turn_case(
	bike: DirtBikeController,
	surface: StringName,
	assist_mode: StringName,
	entry_speed: float = 14.0,
	steer_strength: float = 0.55
) -> Dictionary:
	Input.action_release(InputRouter.THROTTLE)
	Input.action_release(InputRouter.BRAKE)
	Input.action_release(InputRouter.STEER_LEFT)
	Input.action_release(InputRouter.STEER_RIGHT)
	bike.set_surface(surface)
	bike.apply_assist_mode(assist_mode)
	bike.respawn_at(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.67, 0.0)))
	await _wait_physics_frames(90)
	bike.linear_velocity = Vector3(0.0, 0.0, -entry_speed)
	Input.action_press(InputRouter.THROTTLE, 1.0)
	await _wait_physics_frames(30)

	var start_forward := _flat_forward(bike)
	var previous_position := bike.global_position
	var path_length := 0.0
	var minimum_up := 1.0
	var peak_sideslip := 0.0
	var peak_lateral_speed := 0.0
	var peak_yaw_rate := 0.0
	var steady_yaw_sum := 0.0
	var steady_yaw_samples := 0
	var peak_bank := 0.0
	var steady_bank_sum := 0.0
	var peak_bank_target_error := 0.0
	var peak_yaw_target_error := 0.0
	Input.action_press(InputRouter.STEER_RIGHT, steer_strength)
	for frame: int in 90:
		await get_tree().physics_frame
		path_length += Vector2(
			bike.global_position.x - previous_position.x,
			bike.global_position.z - previous_position.z
		).length()
		previous_position = bike.global_position
		var body_forward := _flat_forward(bike)
		var body_right := body_forward.cross(Vector3.UP).normalized()
		var planar_velocity := Vector3(bike.linear_velocity.x, 0.0, bike.linear_velocity.z)
		var lateral_speed := absf(planar_velocity.dot(body_right))
		var forward_speed := absf(planar_velocity.dot(body_forward))
		var sideslip := absf(atan2(lateral_speed, maxf(forward_speed, 0.1)))
		var yaw_rate := absf(bike.angular_velocity.dot(Vector3.UP))
		var bank := absf(bike.get_current_bank_angle())
		var target_bank := absf(bike.get_target_bank_angle())
		var target_yaw_rate := absf(bike.get_target_ground_yaw_rate())
		minimum_up = minf(minimum_up, bike.global_transform.basis.y.normalized().dot(Vector3.UP))
		peak_lateral_speed = maxf(peak_lateral_speed, lateral_speed)
		peak_sideslip = maxf(peak_sideslip, sideslip)
		peak_yaw_rate = maxf(peak_yaw_rate, yaw_rate)
		peak_bank = maxf(peak_bank, bank)
		peak_bank_target_error = maxf(peak_bank_target_error, absf(target_bank - bank))
		peak_yaw_target_error = maxf(peak_yaw_target_error, absf(target_yaw_rate - yaw_rate))
		if frame >= 60:
			steady_yaw_sum += yaw_rate
			steady_bank_sum += bank
			steady_yaw_samples += 1
	Input.action_release(InputRouter.STEER_RIGHT)
	var release_forward := _flat_forward(bike)
	var heading_change := _heading_delta(start_forward, release_forward)
	var final_up := bike.global_transform.basis.y.normalized().dot(Vector3.UP)
	var turn_radius := path_length / maxf(heading_change, 0.001)
	await _wait_physics_frames(24)
	var recovered_forward := _flat_forward(bike)
	var recovered_right := recovered_forward.cross(Vector3.UP).normalized()
	var recovered_velocity := Vector3(bike.linear_velocity.x, 0.0, bike.linear_velocity.z)
	var recovered_lateral_speed := absf(recovered_velocity.dot(recovered_right))
	var recovered_forward_speed := absf(recovered_velocity.dot(recovered_forward))
	var recovered_sideslip := absf(atan2(recovered_lateral_speed, maxf(recovered_forward_speed, 0.1)))
	var recovered_yaw_rate := absf(bike.angular_velocity.dot(Vector3.UP))
	var recovered_bank := absf(bike.get_current_bank_angle())
	var release_heading_drift := _heading_delta(release_forward, recovered_forward)
	Input.action_release(InputRouter.THROTTLE)
	return {
		&"surface": surface,
		&"assist": assist_mode,
		&"entry_speed": entry_speed,
		&"steer_strength": steer_strength,
		&"heading_change": heading_change,
		&"turn_radius": turn_radius,
		&"peak_sideslip": peak_sideslip,
		&"peak_lateral_speed": peak_lateral_speed,
		&"peak_yaw_rate": peak_yaw_rate,
		&"steady_yaw_rate": steady_yaw_sum / maxf(float(steady_yaw_samples), 1.0),
		&"peak_bank": peak_bank,
		&"steady_bank": steady_bank_sum / maxf(float(steady_yaw_samples), 1.0),
		&"peak_bank_target_error": peak_bank_target_error,
		&"peak_yaw_target_error": peak_yaw_target_error,
		&"recovered_lateral_speed": recovered_lateral_speed,
		&"recovered_sideslip": recovered_sideslip,
		&"recovered_yaw_rate": recovered_yaw_rate,
		&"recovered_bank": recovered_bank,
		&"release_heading_drift": release_heading_drift,
		&"minimum_up": minimum_up,
		&"final_up": final_up,
	}


func _turn_case_is_planted(result: Dictionary) -> bool:
	return (
		float(result[&"heading_change"]) >= 0.85
		and float(result[&"heading_change"]) <= 1.8
		and float(result[&"turn_radius"]) >= 16.0
		and float(result[&"turn_radius"]) <= 36.0
		and float(result[&"peak_sideslip"]) <= 0.075
		and float(result[&"peak_lateral_speed"]) <= 1.3
		and float(result[&"peak_yaw_rate"]) >= 0.55
		and float(result[&"peak_yaw_rate"]) <= 1.5
		and float(result[&"steady_yaw_rate"]) >= 0.5
		and float(result[&"steady_yaw_rate"]) <= 1.3
		and rad_to_deg(float(result[&"peak_bank"])) >= 20.0
		and rad_to_deg(float(result[&"peak_bank"])) <= 38.0
		and rad_to_deg(float(result[&"steady_bank"])) >= 20.0
		and rad_to_deg(float(result[&"steady_bank"])) <= 36.0
		and float(result[&"recovered_sideslip"]) <= 0.015
		and float(result[&"recovered_lateral_speed"]) <= 0.2
		and float(result[&"recovered_yaw_rate"]) <= 0.08
		and rad_to_deg(float(result[&"recovered_bank"])) <= 8.0
		and float(result[&"release_heading_drift"]) <= 0.18
		and float(result[&"minimum_up"]) > 0.75
		and float(result[&"minimum_up"]) < 0.95
		and float(result[&"final_up"]) > 0.75
	)


func _hard_turn_case_is_controlled(result: Dictionary) -> bool:
	return (
		float(result[&"heading_change"]) >= 1.6
		and float(result[&"heading_change"]) <= 2.8
		and float(result[&"peak_sideslip"]) <= 0.09
		and float(result[&"peak_lateral_speed"]) <= 1.6
		and rad_to_deg(float(result[&"peak_bank"])) >= 28.0
		and rad_to_deg(float(result[&"peak_bank"])) <= 42.0
		and float(result[&"recovered_sideslip"]) <= 0.02
		and float(result[&"recovered_lateral_speed"]) <= 0.3
		and float(result[&"recovered_yaw_rate"]) <= 0.1
		and float(result[&"release_heading_drift"]) <= 0.22
		and float(result[&"minimum_up"]) > 0.72
	)


func _print_turn_case(label: StringName, result: Dictionary) -> void:
	print(
		"TURN CASE %s: heading=%.3frad radius=%.2fm peak_slip=%.3frad lateral=%.2fm/s peak_yaw=%.3frad/s steady_yaw=%.3frad/s peak_bank=%.1fdeg steady_bank=%.1fdeg recovered_bank=%.1fdeg recovered_slip=%.3frad recovered_lateral=%.2fm/s recovered_yaw=%.3frad/s release_drift=%.3frad min_up=%.3f"
		% [
			String(label),
			float(result[&"heading_change"]),
			float(result[&"turn_radius"]),
			float(result[&"peak_sideslip"]),
			float(result[&"peak_lateral_speed"]),
			float(result[&"peak_yaw_rate"]),
			float(result[&"steady_yaw_rate"]),
			rad_to_deg(float(result[&"peak_bank"])),
			rad_to_deg(float(result[&"steady_bank"])),
			rad_to_deg(float(result[&"recovered_bank"])),
			float(result[&"recovered_sideslip"]),
			float(result[&"recovered_lateral_speed"]),
			float(result[&"recovered_yaw_rate"]),
			float(result[&"release_heading_drift"]),
			float(result[&"minimum_up"]),
		]
	)


func _measure_opposed_normal_fallback(bike: DirtBikeController) -> Dictionary:
	# Directly exercise the degenerate branch: equally loaded contacts reporting
	# exactly opposed normals must never normalize a zero vector into NaNs. These
	# objects are replaced by the respawn immediately following this probe.
	var front_contact := bike.get("_front_contact") as Object
	var rear_contact := bike.get("_rear_contact") as Object
	if front_contact == null or rear_contact == null:
		return {&"normal": Vector3.ZERO, &"finite": false}
	front_contact.set("colliding", true)
	front_contact.set("load", 1800.0)
	front_contact.set("normal", Vector3.RIGHT)
	rear_contact.set("colliding", true)
	rear_contact.set("load", 1800.0)
	rear_contact.set("normal", Vector3.LEFT)
	var fallback_normal: Vector3 = bike.call("_get_ground_normal")
	return {
		&"normal": fallback_normal,
		&"finite": fallback_normal.is_finite(),
	}


func _prepare_keyboard_case(bike: DirtBikeController, entry_speed: float = 16.0) -> void:
	Input.action_release(InputRouter.THROTTLE)
	Input.action_release(InputRouter.BRAKE)
	Input.action_release(InputRouter.STEER_LEFT)
	Input.action_release(InputRouter.STEER_RIGHT)
	bike.set_surface(&"DIRT")
	bike.apply_assist_mode(&"PRO")
	bike.respawn_at(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.67, 0.0)))
	await _wait_physics_frames(75)
	bike.linear_velocity = Vector3(0.0, 0.0, -entry_speed)
	Input.action_press(InputRouter.THROTTLE, 1.0)
	await _wait_physics_frames(18)


func _measure_signed_forward_steering_case(bike: DirtBikeController) -> Dictionary:
	var right_case: Dictionary = await _measure_forward_direction(bike, InputRouter.STEER_RIGHT)
	var left_case: Dictionary = await _measure_forward_direction(bike, InputRouter.STEER_LEFT)
	return {
		&"right_target_yaw": right_case[&"target_yaw"],
		&"right_actual_yaw": right_case[&"actual_yaw"],
		&"right_lateral_offset": right_case[&"lateral_offset"],
		&"left_target_yaw": left_case[&"target_yaw"],
		&"left_actual_yaw": left_case[&"actual_yaw"],
		&"left_lateral_offset": left_case[&"lateral_offset"],
		&"right_error": right_case[&"yaw_error"],
		&"left_error": left_case[&"yaw_error"],
		&"finite": bool(right_case[&"finite"]) and bool(left_case[&"finite"]),
	}


func _measure_forward_direction(bike: DirtBikeController, action: StringName) -> Dictionary:
	await _prepare_keyboard_case(bike)
	var start_position := bike.global_position
	var yaw_sum := 0.0
	var target_sum := 0.0
	var sample_count := 0
	var finite := true
	Input.action_press(action, 1.0)
	for frame: int in 30:
		await get_tree().physics_frame
		var yaw_rate := bike.angular_velocity.dot(Vector3.UP)
		var target_yaw := bike.get_target_ground_yaw_rate()
		finite = finite and is_finite(yaw_rate) and is_finite(target_yaw) and bike.global_position.is_finite()
		if frame >= 18:
			yaw_sum += yaw_rate
			target_sum += target_yaw
			sample_count += 1
	Input.action_release(action)
	Input.action_release(InputRouter.THROTTLE)
	var actual_yaw := yaw_sum / maxf(float(sample_count), 1.0)
	var target_yaw := target_sum / maxf(float(sample_count), 1.0)
	return {
		&"target_yaw": target_yaw,
		&"actual_yaw": actual_yaw,
		&"yaw_error": absf(target_yaw - actual_yaw),
		&"lateral_offset": bike.global_position.x - start_position.x,
		&"finite": finite,
	}


func _measure_reverse_steering_case(bike: DirtBikeController) -> Dictionary:
	Input.action_release(InputRouter.THROTTLE)
	Input.action_release(InputRouter.BRAKE)
	Input.action_release(InputRouter.STEER_LEFT)
	Input.action_release(InputRouter.STEER_RIGHT)
	bike.set_surface(&"DIRT")
	bike.apply_assist_mode(&"PRO")
	bike.respawn_at(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.67, 0.0)))
	await _wait_physics_frames(75)
	bike.linear_velocity = Vector3(0.0, 0.0, 12.0)
	var start_position := bike.global_position
	var initial_error := 0.0
	var late_error_sum := 0.0
	var late_yaw_sum := 0.0
	var late_target_sum := 0.0
	var late_samples := 0
	var peak_sideslip := 0.0
	var finite := true
	Input.action_press(InputRouter.STEER_RIGHT, 1.0)
	for frame: int in 42:
		await get_tree().physics_frame
		var yaw_rate := bike.angular_velocity.dot(Vector3.UP)
		var target_yaw := bike.get_target_ground_yaw_rate()
		var yaw_error := absf(target_yaw - yaw_rate)
		finite = finite and is_finite(yaw_rate) and is_finite(target_yaw) and bike.global_position.is_finite()
		peak_sideslip = maxf(peak_sideslip, absf(bike.get_body_sideslip_angle()))
		if frame == 8:
			initial_error = yaw_error
		if frame >= 30:
			late_error_sum += yaw_error
			late_yaw_sum += yaw_rate
			late_target_sum += target_yaw
			late_samples += 1
	Input.action_release(InputRouter.STEER_RIGHT)
	await _wait_physics_frames(30)
	var late_error := late_error_sum / maxf(float(late_samples), 1.0)
	var late_target := late_target_sum / maxf(float(late_samples), 1.0)
	var late_actual := late_yaw_sum / maxf(float(late_samples), 1.0)
	return {
		&"target_yaw": late_target,
		&"actual_yaw": late_actual,
		&"initial_error": initial_error,
		&"late_error": late_error,
		&"convergence_ratio": late_error / maxf(absf(late_target), 0.001),
		&"release_yaw": absf(bike.angular_velocity.dot(Vector3.UP)),
		&"lateral_offset": bike.global_position.x - start_position.x,
		&"peak_sideslip": peak_sideslip,
		&"finite": finite,
	}


func _measure_keyboard_step_case(bike: DirtBikeController, camera: ChaseCamera) -> Dictionary:
	await _prepare_keyboard_case(bike)
	camera.snap_to_target()
	var start_forward := _flat_forward(bike)
	var previous_position := bike.global_position
	var path_length := 0.0
	var onset_input := 0.0
	var onset_yaw := 0.0
	var peak_input := 0.0
	var peak_yaw := 0.0
	var peak_bank := 0.0
	var peak_slip := 0.0
	var minimum_camera_travel_alignment := 1.0
	var minimum_camera_chassis_alignment := 1.0
	var minimum_actual_camera_alignment := 1.0
	var peak_camera_bank := 0.0
	Input.action_press(InputRouter.STEER_RIGHT, 1.0)
	for frame: int in 36:
		await get_tree().physics_frame
		path_length += Vector2(
			bike.global_position.x - previous_position.x,
			bike.global_position.z - previous_position.z
		).length()
		previous_position = bike.global_position
		var yaw_rate := absf(bike.angular_velocity.dot(Vector3.UP))
		var bank := absf(bike.get_current_bank_angle())
		peak_input = maxf(peak_input, absf(bike.get_steering_input()))
		peak_yaw = maxf(peak_yaw, yaw_rate)
		peak_bank = maxf(peak_bank, bank)
		peak_slip = maxf(peak_slip, absf(bike.get_body_sideslip_angle()))
		if frame == 5:
			onset_input = absf(bike.get_steering_input())
			onset_yaw = yaw_rate
		if frame >= 8:
			var tracking_forward := camera.get_tracking_forward().slide(Vector3.UP).normalized()
			var travel_forward := Vector3(bike.linear_velocity.x, 0.0, bike.linear_velocity.z).normalized()
			var chassis_forward := _flat_forward(bike)
			var actual_camera_forward := (-camera.global_transform.basis.z).slide(Vector3.UP).normalized()
			minimum_camera_travel_alignment = minf(
				minimum_camera_travel_alignment,
				tracking_forward.dot(travel_forward)
			)
			minimum_camera_chassis_alignment = minf(
				minimum_camera_chassis_alignment,
				tracking_forward.dot(chassis_forward)
			)
			minimum_actual_camera_alignment = minf(
				minimum_actual_camera_alignment,
				actual_camera_forward.dot(tracking_forward)
			)
			peak_camera_bank = maxf(peak_camera_bank, absf(camera.get_camera_bank_angle()))
	var release_forward := _flat_forward(bike)
	var release_yaw_sign := signf(bike.angular_velocity.dot(Vector3.UP))
	Input.action_release(InputRouter.STEER_RIGHT)
	var release_input := 1.0
	var opposite_overshoot := 0.0
	for frame: int in 30:
		await get_tree().physics_frame
		var signed_yaw := bike.angular_velocity.dot(Vector3.UP)
		if frame == 7:
			release_input = absf(bike.get_steering_input())
		if signed_yaw * release_yaw_sign < 0.0:
			opposite_overshoot = maxf(opposite_overshoot, absf(signed_yaw))
	var heading_change := _heading_delta(start_forward, release_forward)
	var final_yaw := absf(bike.angular_velocity.dot(Vector3.UP))
	var final_bank := absf(bike.get_current_bank_angle())
	Input.action_release(InputRouter.THROTTLE)
	return {
		&"onset_input": onset_input,
		&"onset_yaw": onset_yaw,
		&"peak_input": peak_input,
		&"release_input": release_input,
		&"peak_yaw": peak_yaw,
		&"peak_bank": peak_bank,
		&"peak_slip": peak_slip,
		&"final_yaw": final_yaw,
		&"final_bank": final_bank,
		&"opposite_overshoot": opposite_overshoot,
		&"heading_change": heading_change,
		&"curvature": heading_change / maxf(path_length, 0.001),
		&"reversal_frames": -1,
		&"bank_reversal_frames": -1,
		&"camera_travel_alignment": minimum_camera_travel_alignment,
		&"camera_chassis_alignment": minimum_camera_chassis_alignment,
		&"camera_actual_alignment": minimum_actual_camera_alignment,
		&"camera_bank": peak_camera_bank,
	}


func _measure_keyboard_alternating_case(bike: DirtBikeController) -> Dictionary:
	await _prepare_keyboard_case(bike)
	Input.action_press(InputRouter.STEER_RIGHT, 1.0)
	var peak_input := 0.0
	var peak_yaw := 0.0
	var peak_bank := 0.0
	var peak_slip := 0.0
	for _frame: int in 24:
		await get_tree().physics_frame
		peak_input = maxf(peak_input, absf(bike.get_steering_input()))
		peak_yaw = maxf(peak_yaw, absf(bike.angular_velocity.dot(Vector3.UP)))
		peak_bank = maxf(peak_bank, absf(bike.get_current_bank_angle()))
		peak_slip = maxf(peak_slip, absf(bike.get_body_sideslip_angle()))
	var first_yaw_sign := signf(bike.angular_velocity.dot(Vector3.UP))
	var first_bank_sign := signf(bike.get_current_bank_angle())
	Input.action_release(InputRouter.STEER_RIGHT)
	Input.action_press(InputRouter.STEER_LEFT, 1.0)
	var reversal_frames := -1
	var bank_reversal_frames := -1
	for frame: int in 36:
		await get_tree().physics_frame
		var signed_yaw := bike.angular_velocity.dot(Vector3.UP)
		var signed_bank := bike.get_current_bank_angle()
		peak_input = maxf(peak_input, absf(bike.get_steering_input()))
		peak_yaw = maxf(peak_yaw, absf(signed_yaw))
		peak_bank = maxf(peak_bank, absf(signed_bank))
		peak_slip = maxf(peak_slip, absf(bike.get_body_sideslip_angle()))
		if reversal_frames < 0 and signed_yaw * first_yaw_sign < 0.0:
			reversal_frames = frame + 1
		if bank_reversal_frames < 0 and signed_bank * first_bank_sign < 0.0:
			bank_reversal_frames = frame + 1
	var release_yaw_sign := signf(bike.angular_velocity.dot(Vector3.UP))
	Input.action_release(InputRouter.STEER_LEFT)
	var release_input := 1.0
	var opposite_overshoot := 0.0
	for frame: int in 30:
		await get_tree().physics_frame
		var signed_yaw := bike.angular_velocity.dot(Vector3.UP)
		if frame == 7:
			release_input = absf(bike.get_steering_input())
		if signed_yaw * release_yaw_sign < 0.0:
			opposite_overshoot = maxf(opposite_overshoot, absf(signed_yaw))
	var final_yaw := absf(bike.angular_velocity.dot(Vector3.UP))
	var final_bank := absf(bike.get_current_bank_angle())
	Input.action_release(InputRouter.THROTTLE)
	return {
		&"onset_input": 1.0,
		&"onset_yaw": peak_yaw,
		&"peak_input": peak_input,
		&"release_input": release_input,
		&"peak_yaw": peak_yaw,
		&"peak_bank": peak_bank,
		&"peak_slip": peak_slip,
		&"final_yaw": final_yaw,
		&"final_bank": final_bank,
		&"opposite_overshoot": opposite_overshoot,
		&"heading_change": 0.0,
		&"curvature": 0.0,
		&"reversal_frames": reversal_frames,
		&"bank_reversal_frames": bank_reversal_frames,
		&"camera_travel_alignment": 1.0,
		&"camera_chassis_alignment": 1.0,
		&"camera_actual_alignment": 1.0,
		&"camera_bank": 0.0,
	}


func _measure_keyboard_tap_case(bike: DirtBikeController) -> Dictionary:
	await _prepare_keyboard_case(bike)
	var start_forward := _flat_forward(bike)
	var previous_position := bike.global_position
	var path_length := 0.0
	var peak_input := 0.0
	var peak_yaw := 0.0
	var peak_bank := 0.0
	var peak_slip := 0.0
	Input.action_press(InputRouter.STEER_RIGHT, 1.0)
	for _frame: int in 9:
		await get_tree().physics_frame
		path_length += Vector2(
			bike.global_position.x - previous_position.x,
			bike.global_position.z - previous_position.z
		).length()
		previous_position = bike.global_position
		peak_input = maxf(peak_input, absf(bike.get_steering_input()))
		peak_yaw = maxf(peak_yaw, absf(bike.angular_velocity.dot(Vector3.UP)))
		peak_bank = maxf(peak_bank, absf(bike.get_current_bank_angle()))
		peak_slip = maxf(peak_slip, absf(bike.get_body_sideslip_angle()))
	var release_yaw_sign := signf(bike.angular_velocity.dot(Vector3.UP))
	Input.action_release(InputRouter.STEER_RIGHT)
	var release_input := 1.0
	var opposite_overshoot := 0.0
	for frame: int in 24:
		await get_tree().physics_frame
		var signed_yaw := bike.angular_velocity.dot(Vector3.UP)
		if frame == 7:
			release_input = absf(bike.get_steering_input())
		if signed_yaw * release_yaw_sign < 0.0:
			opposite_overshoot = maxf(opposite_overshoot, absf(signed_yaw))
	var final_forward := _flat_forward(bike)
	var heading_change := _heading_delta(start_forward, final_forward)
	var final_yaw := absf(bike.angular_velocity.dot(Vector3.UP))
	var final_bank := absf(bike.get_current_bank_angle())
	Input.action_release(InputRouter.THROTTLE)
	return {
		&"onset_input": peak_input,
		&"onset_yaw": peak_yaw,
		&"peak_input": peak_input,
		&"release_input": release_input,
		&"peak_yaw": peak_yaw,
		&"peak_bank": peak_bank,
		&"peak_slip": peak_slip,
		&"final_yaw": final_yaw,
		&"final_bank": final_bank,
		&"opposite_overshoot": opposite_overshoot,
		&"heading_change": heading_change,
		&"curvature": heading_change / maxf(path_length, 0.001),
		&"reversal_frames": -1,
		&"bank_reversal_frames": -1,
		&"camera_travel_alignment": 1.0,
		&"camera_chassis_alignment": 1.0,
		&"camera_actual_alignment": 1.0,
		&"camera_bank": 0.0,
	}


func _keyboard_step_is_direct(result: Dictionary) -> bool:
	return (
		float(result[&"onset_input"]) >= 0.42
		and float(result[&"onset_yaw"]) >= 0.22
		and float(result[&"peak_input"]) >= 0.99
		and float(result[&"release_input"]) <= 0.05
		and float(result[&"peak_yaw"]) >= 0.75
		and float(result[&"peak_yaw"]) <= 1.8
		and rad_to_deg(float(result[&"peak_bank"])) >= 22.0
		and rad_to_deg(float(result[&"peak_bank"])) <= 42.0
		and float(result[&"peak_slip"]) <= 0.075
		and float(result[&"curvature"]) >= 0.045
		and float(result[&"curvature"]) <= 0.1
		and float(result[&"final_yaw"]) <= 0.1
		and rad_to_deg(float(result[&"final_bank"])) <= 8.0
		and float(result[&"opposite_overshoot"]) <= 0.08
		and float(result[&"camera_travel_alignment"]) >= 0.985
		and float(result[&"camera_chassis_alignment"]) >= 0.985
		and float(result[&"camera_actual_alignment"]) >= 0.96
		and rad_to_deg(float(result[&"camera_bank"])) <= 4.1
	)


func _keyboard_alternating_is_direct(result: Dictionary) -> bool:
	return (
		int(result[&"reversal_frames"]) > 0
		and int(result[&"reversal_frames"]) <= 18
		and int(result[&"bank_reversal_frames"]) > 0
		and int(result[&"bank_reversal_frames"]) <= 28
		and float(result[&"release_input"]) <= 0.05
		and float(result[&"peak_slip"]) <= 0.085
		and float(result[&"final_yaw"]) <= 0.1
		and rad_to_deg(float(result[&"final_bank"])) <= 8.0
		and float(result[&"opposite_overshoot"]) <= 0.08
	)


func _keyboard_tap_is_direct(result: Dictionary) -> bool:
	return (
		float(result[&"peak_input"]) >= 0.68
		and float(result[&"release_input"]) <= 0.05
		and float(result[&"peak_yaw"]) >= 0.35
		and float(result[&"peak_slip"]) <= 0.075
		and float(result[&"heading_change"]) >= 0.08
		and float(result[&"heading_change"]) <= 0.5
		and float(result[&"final_yaw"]) <= 0.1
		and rad_to_deg(float(result[&"final_bank"])) <= 8.0
		and float(result[&"opposite_overshoot"]) <= 0.08
	)


func _print_keyboard_case(label: StringName, result: Dictionary) -> void:
	print(
		"KEYBOARD %s: onset_input=%.2f onset_yaw=%.3f peak_input=%.2f release_input=%.2f peak_yaw=%.3f peak_bank=%.1fdeg peak_slip=%.3f final_yaw=%.3f final_bank=%.1fdeg overshoot=%.3f heading=%.3f curvature=%.3f reversal=%d bank_reversal=%d camera_travel=%.3f camera_chassis=%.3f camera_actual=%.3f camera_bank=%.1fdeg"
		% [
			String(label),
			float(result[&"onset_input"]),
			float(result[&"onset_yaw"]),
			float(result[&"peak_input"]),
			float(result[&"release_input"]),
			float(result[&"peak_yaw"]),
			rad_to_deg(float(result[&"peak_bank"])),
			float(result[&"peak_slip"]),
			float(result[&"final_yaw"]),
			rad_to_deg(float(result[&"final_bank"])),
			float(result[&"opposite_overshoot"]),
			float(result[&"heading_change"]),
			float(result[&"curvature"]),
			int(result[&"reversal_frames"]),
			int(result[&"bank_reversal_frames"]),
			float(result[&"camera_travel_alignment"]),
			float(result[&"camera_chassis_alignment"]),
			float(result[&"camera_actual_alignment"]),
			rad_to_deg(float(result[&"camera_bank"])),
		]
	)


func _measure_sustained_air_forward_case(bike: DirtBikeController) -> Dictionary:
	Input.action_release(InputRouter.THROTTLE)
	Input.action_release(InputRouter.BRAKE)
	Input.action_release(InputRouter.STEER_LEFT)
	Input.action_release(InputRouter.STEER_RIGHT)
	Input.action_release(InputRouter.LEAN_BACK)
	Input.action_release(InputRouter.LEAN_FORWARD)
	bike.respawn_at(Transform3D(Basis.IDENTITY, Vector3(0.0, 180.0, 0.0)))
	await _wait_physics_frames(2)
	bike.linear_velocity = Vector3(0.0, 0.0, -12.0)
	var intended_target := -2.1
	var first_settling_error := 0.0
	var minimum_error := INF
	var trailing_error_sum := 0.0
	var trailing_samples := 0
	var maximum_large_same_sign_run := 0
	var current_large_same_sign_run := 0
	var previous_large_error_sign := 0.0
	var crossed_far_side := false
	var finite := true
	Input.action_press(InputRouter.LEAN_FORWARD, 1.0)
	for frame: int in 300:
		await get_tree().physics_frame
		var pitch := _full_range_pitch(bike)
		var error := wrapf(intended_target - pitch, -PI, PI)
		finite = finite and is_finite(pitch) and is_finite(error) and bike.global_position.is_finite()
		crossed_far_side = crossed_far_side or pitch < -PI * 0.5
		if frame == 60:
			first_settling_error = absf(error)
		if frame >= 90:
			minimum_error = minf(minimum_error, absf(error))
			if absf(error) > 0.18:
				var error_sign := signf(error)
				if is_equal_approx(error_sign, previous_large_error_sign):
					current_large_same_sign_run += 1
				else:
					current_large_same_sign_run = 1
					previous_large_error_sign = error_sign
				maximum_large_same_sign_run = maxi(maximum_large_same_sign_run, current_large_same_sign_run)
			else:
				current_large_same_sign_run = 0
				previous_large_error_sign = 0.0
		if frame >= 240:
			trailing_error_sum += absf(error)
			trailing_samples += 1
	Input.action_release(InputRouter.LEAN_FORWARD)
	var final_pitch := _full_range_pitch(bike)
	var final_error := absf(wrapf(intended_target - final_pitch, -PI, PI))
	var pitch_rate := absf(bike.angular_velocity.dot(bike.global_transform.basis.x.normalized()))
	return {
		&"target_pitch": intended_target,
		&"final_pitch": final_pitch,
		&"first_error": first_settling_error,
		&"minimum_error": minimum_error,
		&"final_error": final_error,
		&"trailing_error": trailing_error_sum / maxf(float(trailing_samples), 1.0),
		&"final_pitch_rate": pitch_rate,
		&"large_same_sign_run": maximum_large_same_sign_run,
		&"crossed_far_side": crossed_far_side,
		&"finite": finite and is_finite(final_pitch) and is_finite(pitch_rate),
	}


func _measure_receiver_alignment(
	bike: DirtBikeController,
	alignment_strength: float,
	receiver: Dictionary
) -> Dictionary:
	Input.action_release(InputRouter.THROTTLE)
	Input.action_release(InputRouter.BRAKE)
	Input.action_release(InputRouter.STEER_LEFT)
	Input.action_release(InputRouter.STEER_RIGHT)
	Input.action_release(InputRouter.LEAN_BACK)
	Input.action_release(InputRouter.LEAN_FORWARD)
	bike.landing_alignment_strength = alignment_strength
	var receiver_position: Vector3 = receiver[&"position"]
	var receiver_normal: Vector3 = receiver[&"normal"]
	var spawn_basis := Basis(Vector3.FORWARD, deg_to_rad(11.0))
	bike.respawn_at(Transform3D(spawn_basis, receiver_position + Vector3(0.0, 4.1, 5.5)))
	await _wait_physics_frames(3)
	bike.linear_velocity = Vector3(0.0, -6.0, -12.0)
	var was_airborne := false
	var landed := false
	var touchdown_error := PI
	var peak_weight := 0.0
	for _frame: int in 180:
		await get_tree().physics_frame
		if not bike.is_grounded():
			was_airborne = true
			peak_weight = maxf(peak_weight, bike.get_landing_alignment_weight())
		elif was_airborne:
			landed = true
			touchdown_error = acos(clampf(
				bike.global_transform.basis.y.normalized().dot(receiver_normal),
				-1.0,
				1.0
			))
			break
	await _wait_physics_frames(36)
	var recovery_error := acos(clampf(
		bike.global_transform.basis.y.normalized().dot(receiver_normal),
		-1.0,
		1.0
	))
	return {
		&"landed": landed,
		&"touchdown_error": touchdown_error,
		&"recovery_error": recovery_error,
		&"peak_weight": peak_weight,
	}


func _measure_camera_speed_feedback(
	bike: DirtBikeController,
	camera: ChaseCamera
) -> Dictionary:
	bike.respawn_at(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.67, 30.0)))
	await _wait_physics_frames(90)
	camera.snap_to_target()
	await _wait_physics_frames(45)
	var rest_fov := camera.get_camera_fov()
	bike.linear_velocity = Vector3(0.0, 0.0, -24.0)
	await _wait_physics_frames(45)
	return {
		&"rest_fov": rest_fov,
		&"speed_fov": camera.get_camera_fov(),
		&"feedback_strength": camera.get_speed_feedback_strength(),
	}


func _full_range_pitch(bike: DirtBikeController) -> float:
	var forward := -bike.global_transform.basis.z.normalized()
	var up := bike.global_transform.basis.y.normalized()
	var pitch_cosine := Vector2(forward.x, forward.z).length()
	if up.y < 0.0:
		pitch_cosine = -pitch_cosine
	return atan2(forward.y, pitch_cosine)


func _signed_forward_steering_is_correct(result: Dictionary) -> bool:
	var right_target := float(result[&"right_target_yaw"])
	var right_actual := float(result[&"right_actual_yaw"])
	var left_target := float(result[&"left_target_yaw"])
	var left_actual := float(result[&"left_actual_yaw"])
	var target_symmetry := absf(right_target) / maxf(absf(left_target), 0.001)
	var actual_symmetry := absf(right_actual) / maxf(absf(left_actual), 0.001)
	return (
		bool(result[&"finite"])
		and right_target < -0.35
		and right_actual < -0.25
		and left_target > 0.35
		and left_actual > 0.25
		and float(result[&"right_error"]) <= 0.35
		and float(result[&"left_error"]) <= 0.35
		and target_symmetry >= 0.8
		and target_symmetry <= 1.25
		and actual_symmetry >= 0.72
		and actual_symmetry <= 1.38
	)


func _reverse_steering_is_correct(result: Dictionary) -> bool:
	return (
		bool(result[&"finite"])
		and float(result[&"target_yaw"]) > 0.35
		and float(result[&"actual_yaw"]) > 0.25
		and float(result[&"late_error"]) <= 0.3
		and float(result[&"convergence_ratio"]) <= 0.25
		and float(result[&"release_yaw"]) <= 0.1
		and float(result[&"peak_sideslip"]) <= 0.1
	)


func _sustained_air_pitch_is_controlled(result: Dictionary) -> bool:
	return (
		bool(result[&"finite"])
		and bool(result[&"crossed_far_side"])
		and float(result[&"final_pitch"]) < -1.75
		and float(result[&"minimum_error"]) <= 0.12
		and float(result[&"final_error"]) <= 0.22
		and float(result[&"trailing_error"]) <= 0.25
		and float(result[&"final_pitch_rate"]) <= 0.25
		and int(result[&"large_same_sign_run"]) < 180
	)


func _print_signed_steering(forward: Dictionary, reverse: Dictionary) -> void:
	print(
		"SIGNED STEERING: forward_right target=%.3f actual=%.3f offset=%.2f forward_left target=%.3f actual=%.3f offset=%.2f reverse_right target=%.3f actual=%.3f initial_error=%.3f late_error=%.3f convergence=%.3f release=%.3f slip=%.3f finite=%s"
		% [
			float(forward[&"right_target_yaw"]),
			float(forward[&"right_actual_yaw"]),
			float(forward[&"right_lateral_offset"]),
			float(forward[&"left_target_yaw"]),
			float(forward[&"left_actual_yaw"]),
			float(forward[&"left_lateral_offset"]),
			float(reverse[&"target_yaw"]),
			float(reverse[&"actual_yaw"]),
			float(reverse[&"initial_error"]),
			float(reverse[&"late_error"]),
			float(reverse[&"convergence_ratio"]),
			float(reverse[&"release_yaw"]),
			float(reverse[&"peak_sideslip"]),
			str(bool(forward[&"finite"]) and bool(reverse[&"finite"])),
		]
	)


func _print_air_pitch_case(result: Dictionary) -> void:
	print(
		"SUSTAINED AIR PITCH: target=%.3f final=%.3f first_error=%.3f min_error=%.3f final_error=%.3f trailing_error=%.3f final_rate=%.3f large_same_sign_run=%d crossed_far_side=%s finite=%s"
		% [
			float(result[&"target_pitch"]),
			float(result[&"final_pitch"]),
			float(result[&"first_error"]),
			float(result[&"minimum_error"]),
			float(result[&"final_error"]),
			float(result[&"trailing_error"]),
			float(result[&"final_pitch_rate"]),
			int(result[&"large_same_sign_run"]),
			str(result[&"crossed_far_side"]),
			str(result[&"finite"]),
		]
	)


func _flat_forward(bike: DirtBikeController) -> Vector3:
	var forward := -bike.global_transform.basis.z
	forward.y = 0.0
	return forward.normalized()


func _heading_delta(from_forward: Vector3, to_forward: Vector3) -> float:
	return absf(atan2(from_forward.cross(to_forward).y, from_forward.dot(to_forward)))


func _wait_physics_frames(frame_count: int) -> void:
	for _frame: int in frame_count:
		await get_tree().physics_frame


func _add_jump_ramp(world: Node3D) -> void:
	var length := 10.5
	var width := 8.2
	var height := 2.8
	var half_width := width * 0.5
	var half_length := length * 0.5
	var station_count := int(ceil(length / 0.65)) + 1
	var left_points := PackedVector3Array()
	var right_points := PackedVector3Array()
	for station_index: int in station_count:
		var weight := float(station_index) / float(station_count - 1)
		var rise := pow(weight, 3.0)
		var settle := pow(1.0 - weight, 3.0)
		var progressive := rise / maxf(rise + settle, 0.0001)
		var height_ratio := lerpf(progressive, weight, 0.26)
		var station_z := lerpf(half_length, -half_length, weight)
		left_points.append(Vector3(-half_width, height * height_ratio, station_z))
		right_points.append(Vector3(half_width, height * height_ratio, station_z))
	var faces := PackedVector3Array()
	for station_index: int in station_count - 1:
		var next := station_index + 1
		_append_up_triangle(faces, left_points[next], right_points[next], right_points[station_index])
		_append_up_triangle(faces, left_points[next], right_points[station_index], left_points[station_index])
	var ramp := StaticBody3D.new()
	ramp.name = "JumpProbeTakeoff"
	ramp.collision_layer = 2
	ramp.collision_mask = 1
	ramp.position = Vector3(0.0, 0.0, -10.0)
	ramp.set_meta(&"surface", &"PACKED")
	ramp.set_meta(&"roughness", 0.72)
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	ramp.add_child(collision)
	world.add_child(ramp)


func _append_up_triangle(faces: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3) -> void:
	var second := b
	var third := c
	if (second - a).cross(third - a).dot(Vector3.UP) < 0.0:
		second = c
		third = b
	faces.append(a)
	faces.append(second)
	faces.append(third)


func _add_receiver_slope(world: Node3D) -> Dictionary:
	var receiver := StaticBody3D.new()
	receiver.name = "LandingReceiverProbe"
	receiver.collision_layer = 2
	receiver.collision_mask = 1
	receiver.position = Vector3(0.0, 20.0, 0.0)
	receiver.rotation.x = deg_to_rad(-15.0)
	receiver.set_meta(&"surface", &"PACKED")
	receiver.set_meta(&"roughness", 0.62)
	var shape := BoxShape3D.new()
	shape.size = Vector3(24.0, 0.5, 34.0)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	receiver.add_child(collision)
	world.add_child(receiver)
	return {
		&"position": receiver.position + receiver.basis.y.normalized() * 0.25,
		&"normal": receiver.basis.y.normalized(),
	}
