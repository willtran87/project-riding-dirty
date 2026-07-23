extends Node3D
## Focused headless integration contract for the real bike racecraft layer.
##
## The deterministic rule math has its own probe. This scene deliberately uses
## the production bike, semantic InputMap actions, suspension contact, signals,
## snapshots, and respawn reset path so wiring regressions cannot pass on pure
## calculations alone.

const BIKE_SCENE := preload("res://entities/bike/bike.tscn")
const HUD_SCRIPT := preload("res://features/hud/race_hud.gd")

var _bike: DirtBikeController
var _passed := true
var _racecraft_events: Array[Dictionary] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_build_ground()
	_bike = BIKE_SCENE.instantiate() as DirtBikeController
	_bike.position = Vector3(0.0, 0.67, 0.0)
	add_child(_bike)
	_bike.configure_feedback({&"haptics_enabled": false, &"haptics_intensity": 0.0})
	_bike.racecraft_event.connect(_on_racecraft_event)
	await get_tree().physics_frame

	await _verify_prestart_motion_lock()
	_verify_semantic_technique_action()
	await _verify_flow_denied_feedback_contract()
	await _verify_contextual_flow_selection()
	await _verify_negative_forward_scrub()
	await _verify_technique_events_and_context_bounds()
	await _verify_fast_line_choice_contract()
	_verify_pack_racecraft_reward_window()
	_verify_respawn_reset_contract()

	print("RACECRAFT INTEGRATION PROBE: events=%d passed=%s snapshot=%s" % [
		_racecraft_events.size(), str(_passed), str(_bike.get_racecraft_snapshot()),
	])
	await _finish_probe()


func _build_ground() -> void:
	var ground := StaticBody3D.new()
	ground.name = "PackedTestGround"
	ground.collision_layer = 2
	ground.collision_mask = 1
	ground.set_meta(&"surface", &"PACKED")
	ground.set_meta(&"roughness", 0.35)
	ground.set_meta(&"roost", 0.8)
	var shape := BoxShape3D.new()
	shape.size = Vector3(80.0, 0.5, 80.0)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	ground.position.y = -0.25
	ground.add_child(collision)
	add_child(ground)


func _verify_prestart_motion_lock() -> void:
	_bike.set_controls_enabled(false)
	_bike.set_motion_locked(true)
	_bike.set_gate_staging_input_enabled(true)
	var start_transform := _bike.global_transform
	Input.action_press(InputRouter.THROTTLE, 1.0)
	Input.action_press(InputRouter.BRAKE, 0.72)
	await _wait_physics_frames(24)
	var staging := _bike.get_gate_staging_input_snapshot()
	var position_drift := _bike.global_position.distance_to(start_transform.origin)
	var basis_drift := _basis_max_axis_error(_bike.global_transform.basis, start_transform.basis)
	var locked := (
		_bike.freeze
		and position_drift <= 0.0001
		and basis_drift <= 0.0001
		and _bike.linear_velocity.length() <= 0.0001
		and _bike.angular_velocity.length() <= 0.0001
	)
	var staging_input_only := (
		bool(staging.get(&"enabled", false))
		and float(staging.get(&"throttle", 0.0)) >= 0.99
		and float(staging.get(&"brake", 0.0)) > 0.60
	)
	_check(locked, "pre-start rigid-body motion lock", "position=%.6f basis=%.6f" % [position_drift, basis_drift])
	_check(staging_input_only, "staging input remains presentation-only", "snapshot=%s" % str(staging))
	Input.action_release(InputRouter.THROTTLE)
	Input.action_release(InputRouter.BRAKE)
	_bike.set_gate_staging_input_enabled(false)
	_bike.set_motion_locked(false)
	_bike.set_controls_enabled(true)
	_bike.respawn_at(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.67, 0.0)))
	_check(await _wait_until_grounded(90), "real suspension acquires test ground")


func _verify_semantic_technique_action() -> void:
	var events := InputMap.action_get_events(InputRouter.RACECRAFT)
	var present := (
		InputRouter.RACECRAFT == &"racecraft_technique"
		and InputMap.has_action(InputRouter.RACECRAFT)
		and not events.is_empty()
	)
	_check(present, "semantic racecraft technique action", "bindings=%d" % events.size())


func _verify_flow_denied_feedback_contract() -> void:
	_release_riding_actions()
	_bike.set(&"_flow", 0.0)
	_racecraft_events.clear()
	var before := _bike.get_racecraft_snapshot()
	Input.action_press(InputRouter.FLOW_BOOST, 1.0)
	# Match the production one-shot path and hold long enough for either side of
	# the current physics boundary, as the successful Context Flow check does.
	await _wait_physics_frames(2)
	Input.action_release(InputRouter.FLOW_BOOST)
	var after := _bike.get_racecraft_snapshot()
	var denial_payload: Dictionary = {}
	var denial_count := 0
	for event: Dictionary in _racecraft_events:
		if StringName(event.get(&"kind", &"")) == &"FLOW_DENIED":
			denial_count += 1
			denial_payload = (event.get(&"payload", {}) as Dictionary).duplicate(true)
	var haptic := _bike.get_haptic_feedback_snapshot()
	var haptic_request := haptic.get(&"last_request", {}) as Dictionary
	var denied_without_side_effects := (
		is_zero_approx(float(before.get(&"flow", -1.0)))
		and denial_count == 1
		and StringName(denial_payload.get(&"technique", &"")) == &"SURGE"
		and float(denial_payload.get(&"required", 0.0)) > float(denial_payload.get(&"available", -1.0))
		and is_zero_approx(float(denial_payload.get(&"available", -1.0)))
		and StringName(after.get(&"active_flow_mode", &"INVALID")) == &"NONE"
		and is_zero_approx(float(after.get(&"flow", -1.0)))
		and int((after.get(&"counters", {}) as Dictionary).get(&"FLOW_DENIED", 0)) == 1
		and int((after.get(&"counters", {}) as Dictionary).get(&"FLOW_SURGE", 0)) == 0
	)
	var refusal_haptic := (
		StringName(haptic_request.get(&"kind", &"")) == &"FLOW_DENIED"
		and float(haptic_request.get(&"low_motor", 0.0)) > float(haptic_request.get(&"high_motor", 1.0))
		and float(haptic_request.get(&"duration", 0.0)) > 0.0
		and float(haptic.get(&"flow_denied_cooldown", 0.0)) > 0.0
	)
	_check(
		denied_without_side_effects and refusal_haptic,
		"unaffordable Context Flow has explicit side-effect-free refusal feedback",
		"events=%d payload=%s after=%s haptic=%s" % [denial_count, str(denial_payload), str(after), str(haptic)]
	)


func _verify_contextual_flow_selection() -> void:
	_release_riding_actions()
	await _wait_physics_frames(2)
	var surge_snapshot := _bike.get_racecraft_snapshot()
	var surge_selected := (
		_bike.is_grounded()
		and StringName(surge_snapshot.get(&"recommended_flow_mode", &"")) == &"SURGE"
		and float(surge_snapshot.get(&"recommended_flow_cost", -1.0)) > 0.0
	)
	_check(surge_selected, "grounded straight recommends SURGE", "snapshot=%s" % str(surge_snapshot))

	# Seed only the resource amount; selection and activation still travel through
	# real semantic input and the controller's production physics tick.
	_bike.set(&"_flow", 50.0)
	Input.action_press(InputRouter.BRAKE, 1.0)
	Input.action_press(InputRouter.STEER_RIGHT, 1.0)
	await _wait_physics_frames(2)
	var rail_recommendation := _bike.get_racecraft_snapshot()
	var rail_selected := StringName(rail_recommendation.get(&"recommended_flow_mode", &"")) == &"RAIL"
	_check(rail_selected, "brake plus steer recommends RAIL", "snapshot=%s" % str(rail_recommendation))
	Input.action_press(InputRouter.FLOW_BOOST, 1.0)
	# Hold across two ticks so the semantic one-shot is observed regardless of
	# whether this coroutine resumed before or after the current physics signal.
	await _wait_physics_frames(2)
	Input.action_release(InputRouter.FLOW_BOOST)
	var rail_activation := _bike.get_racecraft_snapshot()
	var rail_activated := (
		StringName(rail_activation.get(&"active_flow_mode", &"")) == &"RAIL"
		and float(rail_activation.get(&"flow", 50.0)) < 50.0
		and int((rail_activation.get(&"counters", {}) as Dictionary).get(&"FLOW_RAIL", 0)) == 1
	)
	_check(rail_activated, "RAIL activates through Context Flow input", "snapshot=%s" % str(rail_activation))
	Input.action_release(InputRouter.BRAKE)
	Input.action_release(InputRouter.STEER_RIGHT)
	await _wait_physics_frames(2)


func _verify_negative_forward_scrub() -> void:
	_bike.respawn_at(Transform3D(Basis.IDENTITY, Vector3(0.0, 4.0, 0.0)))
	_bike.set_controls_enabled(true)
	Input.action_press(InputRouter.LEAN_FORWARD, 1.0)
	await _wait_physics_frames(2)
	var snapshot := _bike.get_racecraft_snapshot()
	var forward_lean := InputRouter.get_lean()
	var compose_selected := (
		not _bike.is_grounded()
		and StringName(snapshot.get(&"recommended_flow_mode", &"")) == &"COMPOSE"
	)
	var scrub_contract := (
		forward_lean <= -0.99
		and float(snapshot.get(&"scrub_strength", 0.0)) >= 0.99
		and float(snapshot.get(&"scrub_seconds", 0.0)) > 0.0
	)
	_check(compose_selected, "airborne bike recommends COMPOSE", "snapshot=%s" % str(snapshot))
	_check(scrub_contract, "forward lean is negative and drives scrub", "lean=%.3f snapshot=%s" % [forward_lean, str(snapshot)])
	Input.action_release(InputRouter.LEAN_FORWARD)


func _verify_technique_events_and_context_bounds() -> void:
	_bike.respawn_at(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.67, 0.0)))
	_bike.set_controls_enabled(true)
	_check(await _wait_until_grounded(90), "technique setup is grounded")
	_racecraft_events.clear()
	Input.action_press(InputRouter.RACECRAFT, 1.0)
	await get_tree().physics_frame
	Input.action_release(InputRouter.RACECRAFT)
	await get_tree().physics_frame
	var live_snapshot := _bike.get_racecraft_snapshot()
	var live_counter := int((live_snapshot.get(&"counters", {}) as Dictionary).get(&"DAB", 0))
	var live_action := (
		StringName(live_snapshot.get(&"technique", &"")) == &"DAB"
		and live_counter == 1
		and float(live_snapshot.get(&"technique_cooldown", -1.0)) >= 0.0
		and float(live_snapshot.get(&"technique_cooldown", 99.0)) <= _bike.racecraft_technique_cooldown
	)
	_check(live_action, "semantic technique performs low-speed DAB", "snapshot=%s" % str(live_snapshot))

	_bike.register_racecraft_success(&"DAB", {&"intensity": 0.75})
	var counted_snapshot := _bike.get_racecraft_snapshot()
	var dab_payload_counts: Array[int] = []
	for event: Dictionary in _racecraft_events:
		if StringName(event.get(&"kind", &"")) == &"DAB":
			var payload := event.get(&"payload", {}) as Dictionary
			dab_payload_counts.append(int(payload.get(&"count", 0)))
	var counters := counted_snapshot.get(&"counters", {}) as Dictionary
	var counter_contract := (
		int(counters.get(&"DAB", 0)) == 2
		and dab_payload_counts == [1, 2]
	)
	_check(counter_contract, "racecraft signal and counter sequence", "counts=%s counters=%s" % [str(dab_payload_counts), str(counters)])

	_bike.set_course_racecraft_context({
		&"berm_strength": 7.5,
		&"rut_strength": -4.0,
		&"skill_zone_id": &"PROBE_LINE",
	})
	_bike.set_pack_racecraft_context({
		&"draft_strength": 8.0,
		&"roost_pressure": -3.0,
		&"contact_pressure": 0.55,
	})
	var bounded := _bike.get_racecraft_snapshot()
	var upper_bounds := (
		is_equal_approx(float(bounded.get(&"berm_strength", -1.0)), 1.0)
		and is_equal_approx(float(bounded.get(&"draft_strength", -1.0)), 1.0)
		and is_equal_approx(float(bounded.get(&"roost_pressure", -1.0)), 0.0)
		and is_equal_approx(float(bounded.get(&"contact_pressure", -1.0)), 0.55)
	)
	_bike.set_course_racecraft_context({&"berm_strength": -2.0})
	var lower_bounded := _bike.get_racecraft_snapshot()
	var course_lower_bound := is_equal_approx(float(lower_bounded.get(&"berm_strength", -1.0)), 0.0)
	_check(upper_bounds and course_lower_bound, "course and pack context clamps", "upper=%s lower=%s" % [str(bounded), str(lower_bounded)])


func _verify_fast_line_choice_contract() -> void:
	_release_riding_actions()
	_bike.respawn_at(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.67, 0.0)))
	_bike.set_controls_enabled(true)
	_check(await _wait_until_grounded(90), "fast-line setup is grounded")
	_racecraft_events.clear()
	_bike.set_course_racecraft_context({
		&"skill_zone_id": &"PROBE_FAST_LINE",
		&"skill_zone_kind": &"RUT",
		&"skill_zone_phase": &"PREVIEW",
		&"skill_zone_preview": true,
		&"skill_zone_active": false,
		&"skill_line_direction": &"LEFT",
		&"skill_line_target_delta": -2.0,
		&"skill_line_distance_m": 28.0,
		&"skill_line_preview_seconds": 1.25,
		&"skill_line_alignment": 0.20,
		&"skill_line_difficulty": 0.55,
	})
	await _wait_physics_frames(2)
	var preview := _bike.get_racecraft_snapshot()
	var preview_cue: String = HUD_SCRIPT.format_fast_line_cue(preview)
	var readable_preview := (
		StringName(preview.get(&"skill_zone", &"")) == &"PROBE_FAST_LINE"
		and StringName(preview.get(&"skill_zone_phase", &"")) == &"PREVIEW"
		and StringName(preview.get(&"skill_line_direction", &"")) == &"LEFT"
		and is_equal_approx(float(preview.get(&"skill_line_distance_m", 0.0)), 28.0)
		and not bool(preview.get(&"skill_line_committed", true))
		and preview_cue.contains("FAST LINE")
		and preview_cue.contains("RUT")
		and preview_cue.contains("28m")
	)
	_check(readable_preview, "fast line is telegraphed before grading", "cue=%s snapshot=%s" % [preview_cue, str(preview)])

	_bike.set_course_racecraft_context({
		&"skill_zone_id": &"PROBE_FAST_LINE",
		&"skill_zone_kind": &"RUT",
		&"skill_zone_phase": &"ACTIVE",
		&"skill_zone_preview": false,
		&"skill_zone_active": true,
		&"skill_line_direction": &"LEFT",
		&"skill_line_target_delta": -2.0,
		&"skill_line_distance_m": 0.0,
		&"skill_line_preview_seconds": 0.0,
		&"skill_line_alignment": 0.10,
		&"skill_line_difficulty": 0.55,
	})
	var flow_before := float(_bike.get_racecraft_snapshot().get(&"flow", 0.0))
	await _wait_physics_frames(45)
	var bypassed := _bike.get_racecraft_snapshot()
	var bypass_event_count := 0
	for event: Dictionary in _racecraft_events:
		if StringName(event.get(&"kind", &"")) == &"SKILL_LINE":
			bypass_event_count += 1
	var neutral_bypass := (
		StringName(bypassed.get(&"skill_line_outcome", &"")) == &"BYPASSED"
		and not bool(bypassed.get(&"skill_line_committed", true))
		and bypass_event_count == 0
		and is_equal_approx(float(bypassed.get(&"flow", 0.0)), flow_before)
	)
	_check(neutral_bypass, "uncommitted fast line bypass is exactly neutral", "events=%d snapshot=%s" % [bypass_event_count, str(bypassed)])

	_bike.set_course_racecraft_context({
		&"skill_zone_id": &"PROBE_PUMP_INTENT",
		&"skill_zone_kind": &"PUMP",
		&"skill_zone_phase": &"PREVIEW",
		&"skill_zone_preview": true,
		&"skill_zone_active": false,
		&"skill_line_direction": &"CENTER",
		&"skill_line_target_delta": -1.0,
		&"skill_line_distance_m": 20.0,
		&"skill_line_preview_seconds": 1.0,
		&"skill_line_alignment": 0.90,
		&"skill_line_difficulty": 0.35,
	})
	Input.action_press(InputRouter.STEER_LEFT, 1.0)
	await _wait_physics_frames(16)
	Input.action_release(InputRouter.STEER_LEFT)
	var steering_only_pump := _bike.get_racecraft_snapshot()
	_check(
		not bool(steering_only_pump.get(&"skill_line_committed", true)),
		"ordinary steering cannot opt into a PUMP fast line",
		"snapshot=%s" % str(steering_only_pump)
	)

	_bike.set_course_racecraft_context({
		&"skill_zone_id": &"PROBE_FAST_LINE_COMMIT",
		&"skill_zone_kind": &"BERM",
		&"skill_zone_phase": &"PREVIEW",
		&"skill_zone_preview": true,
		&"skill_zone_active": false,
		&"skill_line_direction": &"LEFT",
		# The rider has crossed the authored left lane; corrective right input is
		# still deliberate intent and must be judged from the live target delta.
		&"skill_line_target_delta": 1.0,
		&"skill_line_distance_m": 22.0,
		&"skill_line_preview_seconds": 1.1,
		&"skill_line_alignment": 0.90,
		&"skill_line_difficulty": 0.35,
	})
	Input.action_press(InputRouter.STEER_RIGHT, 1.0)
	await _wait_physics_frames(32)
	Input.action_release(InputRouter.STEER_RIGHT)
	var committed_preview := _bike.get_racecraft_snapshot()
	_bike.set_course_racecraft_context({
		&"skill_zone_id": &"PROBE_FAST_LINE_COMMIT",
		&"skill_zone_kind": &"BERM",
		&"skill_zone_phase": &"ACTIVE",
		&"skill_zone_preview": false,
		&"skill_zone_active": true,
		&"skill_line_direction": &"LEFT",
		&"skill_line_target_delta": 0.05,
		&"skill_line_distance_m": 0.0,
		&"skill_line_preview_seconds": 0.0,
		&"skill_line_alignment": 0.95,
		&"skill_line_difficulty": 0.35,
	})
	await _wait_physics_frames(45)
	var committed_result := _bike.get_racecraft_snapshot()
	var committed_event_count := 0
	for event: Dictionary in _racecraft_events:
		if StringName(event.get(&"kind", &"")) == &"SKILL_LINE":
			committed_event_count += 1
	var committed_attempt := (
		bool(committed_preview.get(&"skill_line_committed", false))
		and StringName(committed_result.get(&"skill_line_outcome", &"")) in [&"CLEAN", &"MASTERED"]
		and committed_event_count == 1
		and float(committed_result.get(&"flow", 0.0)) > flow_before
	)
	_check(committed_attempt, "deliberately steered fast line retains bounded reward path", "events=%d snapshot=%s" % [committed_event_count, str(committed_result)])

	_bike.set_course_racecraft_context({})
	await _wait_physics_frames(2)
	var cleared := _bike.get_racecraft_snapshot()
	_check(
		StringName(cleared.get(&"skill_zone", &"INVALID")).is_empty()
		and HUD_SCRIPT.format_fast_line_cue(cleared).is_empty(),
		"fast-line cue clears outside its decision window",
		"snapshot=%s" % str(cleared)
	)


func _verify_respawn_reset_contract() -> void:
	_bike.respawn_at(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.67, 0.0)))
	var snapshot := _bike.get_racecraft_snapshot()
	var reset := (
		int(snapshot.get(&"version", 0)) >= 1
		and StringName(snapshot.get(&"active_flow_mode", &"")) == &"NONE"
		and StringName(snapshot.get(&"recommended_flow_mode", &"")) == &"SURGE"
		and StringName(snapshot.get(&"technique", &"")) == &"NONE"
		and is_zero_approx(float(snapshot.get(&"flow", -1.0)))
		and is_zero_approx(float(snapshot.get(&"scrub_strength", -1.0)))
		and is_zero_approx(float(snapshot.get(&"scrub_seconds", -1.0)))
		and not bool(snapshot.get(&"slide_active", true))
		and StringName(snapshot.get(&"skill_zone", &"INVALID")).is_empty()
		and is_zero_approx(float(snapshot.get(&"berm_strength", -1.0)))
		and is_zero_approx(float(snapshot.get(&"draft_strength", -1.0)))
		and is_zero_approx(float(snapshot.get(&"roost_pressure", -1.0)))
		and is_zero_approx(float(snapshot.get(&"contact_pressure", -1.0)))
		and (snapshot.get(&"counters", {}) as Dictionary).is_empty()
	)
	_check(reset, "respawn clears bounded racecraft state", "snapshot=%s" % str(snapshot))


func _verify_pack_racecraft_reward_window() -> void:
	_bike.respawn_at(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.67, 0.0)))
	_bike.set_pack_racecraft_context({
		&"draft_strength": 0.66,
		&"draft_target": &"PROBE_RIVAL",
	})
	_bike.set_pack_racecraft_context({&"draft_strength": 0.0})
	var latched := _bike.get_racecraft_snapshot()
	var window_is_live := (
		is_equal_approx(float(latched.get(&"recent_draft_strength", 0.0)), 0.66)
		and StringName(latched.get(&"recent_draft_target", &"")) == &"PROBE_RIVAL"
		and float(latched.get(&"recent_draft_seconds", 0.0)) > 0.0
	)
	_bike.register_racecraft_success(&"DRAFT_SLINGSHOT", {&"rider_id": &"PROBE_RIVAL"})
	var slingshot := _bike.get_racecraft_snapshot()
	_bike.register_racecraft_success(&"ROOST_DEFENSE", {&"pressure": 0.72})
	var defended := _bike.get_racecraft_snapshot()
	var rewards_are_bounded := (
		is_equal_approx(float(slingshot.get(&"flow", 0.0)), 6.0)
		and is_zero_approx(float(slingshot.get(&"recent_draft_strength", -1.0)))
		and is_equal_approx(float(defended.get(&"flow", 0.0)), 9.0)
		and int((defended.get(&"counters", {}) as Dictionary).get(&"DRAFT_SLINGSHOT", 0)) == 1
		and int((defended.get(&"counters", {}) as Dictionary).get(&"ROOST_DEFENSE", 0)) == 1
	)
	_check(
		window_is_live and rewards_are_bounded,
		"draft slingshot window and defensive roost rewards",
		"latched=%s defended=%s" % [str(latched), str(defended)]
	)


func _wait_until_grounded(maximum_frames: int) -> bool:
	for _frame: int in maximum_frames:
		if _bike.is_grounded():
			return true
		await get_tree().physics_frame
	return _bike.is_grounded()


func _wait_physics_frames(frame_count: int) -> void:
	for _frame: int in frame_count:
		await get_tree().physics_frame


func _basis_max_axis_error(first: Basis, second: Basis) -> float:
	return maxf(
		first.x.distance_to(second.x),
		maxf(first.y.distance_to(second.y), first.z.distance_to(second.z))
	)


func _release_riding_actions() -> void:
	for action: StringName in [
		InputRouter.THROTTLE, InputRouter.BRAKE, InputRouter.STEER_LEFT,
		InputRouter.STEER_RIGHT, InputRouter.LEAN_FORWARD, InputRouter.LEAN_BACK,
		InputRouter.PRELOAD, InputRouter.FLOW_BOOST, InputRouter.RACECRAFT,
	]:
		Input.action_release(action)


func _on_racecraft_event(kind: StringName, payload: Dictionary) -> void:
	_racecraft_events.append({&"kind": kind, &"payload": payload.duplicate(true)})


func _check(condition: bool, label: String, details: String = "") -> void:
	var suffix := "" if details.is_empty() else "  //  %s" % details
	print("RACECRAFT INTEGRATION CHECK: %s passed=%s%s" % [label, str(condition), suffix])
	if condition:
		return
	_passed = false
	push_error("RACECRAFT INTEGRATION: %s failed.%s" % [label, suffix])


func _finish_probe() -> void:
	_release_riding_actions()
	if is_instance_valid(_bike):
		_bike.set_controls_enabled(false)
		_bike.set_motion_locked(true)
		_bike.set_physics_process(false)
		_bike.shutdown_audio()
	await get_tree().process_frame
	get_tree().quit(0 if _passed else 1)
