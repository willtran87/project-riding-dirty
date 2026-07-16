extends Node3D
## Live integration regression for closed-loop start/finish continuity.
##
## Definition of done:
## - the real Bike, GhostController and RaceController run a two-lap Mesa race;
## - live integrity observes legal, incremental movement around the full route;
## - the intermediate finish gate preserves nonzero bike motion and never causes
##   an integrity recovery, automatic recovery, respawn, or penalty;
## - the second finish gate still produces one clean, complete race result.

const BIKE_SCENE := preload("res://entities/bike/bike.tscn")
const GHOST_SCENE := preload("res://features/race/ghost_controller.tscn")
const RACE_SCENE := preload("res://features/race/race_controller.tscn")

const TRAVEL_STEP_METERS := 8.0
const CHASSIS_CLEARANCE_METERS := 1.25
const TEST_SPEED_MPS := 14.0
const TEST_ANGULAR_VELOCITY := Vector3(0.18, 0.42, -0.12)
const MOTION_TOLERANCE := 0.01

var _bike: DirtBikeController
var _ghost: GhostController
var _race: RaceController
var _route := PackedVector3Array()
var _route_distances := PackedFloat32Array()
var _route_length := 0.0

var _passed := true
var _lap_events: Array[Dictionary] = []
var _result_emissions := 0
var _captured_result: Dictionary = {}
var _integrity_events: Array[Dictionary] = []
var _respawn_count := 0
var _automatic_recovery_count := 0
var _run_respawn_baseline := 0
var _run_automatic_recovery_baseline := 0


func _ready() -> void:
	Profile.persistence_enabled = false
	_run.call_deferred()


func _run() -> void:
	_bike = BIKE_SCENE.instantiate() as DirtBikeController
	_ghost = GHOST_SCENE.instantiate() as GhostController
	_race = RACE_SCENE.instantiate() as RaceController
	_connect_monitors()
	add_child(_bike)
	add_child(_ghost)
	add_child(_race)
	_ghost.persistence_enabled = false
	await _settle_physics_frame()

	var source_route := CourseCatalog.get_world_riding_points(CourseCatalog.MESA_MX_ID)
	_race.initialize(_bike, _ghost, CourseCatalog.MESA_MX_ID, source_route, null)
	_race.configure_session(_make_session_config(), source_route, null)
	await _settle_physics_frame()

	_route = _race.get_authoritative_route_points()
	_build_route_distances()
	var checkpoint_count := _race.get_checkpoint_positions().size()
	_check(_route.size() >= 3 and _route_length > 100.0, "Mesa authoritative route available", "points=%d length=%.1f" % [_route.size(), _route_length])
	_check(checkpoint_count == 6, "two-lap test gate catalog", "count=%d" % checkpoint_count)
	_disable_automatic_gate_detection(checkpoint_count)

	_race.reset_run()
	var started := await _wait_for_state(RaceController.State.RACING, 30)
	_check(started, "countdown reaches live racing", "state=%d" % _race.state)
	if not started or checkpoint_count <= 0 or _route.size() < 3:
		await _finish_probe()
		return

	# Freeze only the physics body's integration. RaceController has already
	# released its motion lock, so the production race and bike state machines stay
	# live. Explicit velocity remains authoritative evidence for race integrity.
	_bike.freeze = true
	_bike.sleeping = false
	_run_respawn_baseline = _respawn_count
	_run_automatic_recovery_baseline = _automatic_recovery_count
	# The physical grid is already just inside the opening segment. Continue from
	# an opening sample instead of teleporting onto the duplicated distance-zero
	# alias, whose equally valid terminal projection is intentionally ambiguous.
	var opening_distance := minf(TRAVEL_STEP_METERS, _route_length * 0.05)
	_place_bike_at_distance(opening_distance)
	await _settle_physics_frame()

	await _traverse_lap(1, checkpoint_count, opening_distance)
	if _race.state != RaceController.State.RACING:
		_check(false, "intermediate gate keeps race active", "state=%d" % _race.state)
		await _finish_probe()
		return

	_place_bike_at_distance(opening_distance)
	await _settle_physics_frame()
	await _settle_physics_frame()
	_validate_clean_integrity("post-seam projection wrap")
	_check(
		_respawn_count == _run_respawn_baseline
		and _automatic_recovery_count == _run_automatic_recovery_baseline,
		"no deferred seam recovery",
		"respawns=%d recoveries=%d" % [
			_respawn_count - _run_respawn_baseline,
			_automatic_recovery_count - _run_automatic_recovery_baseline,
		]
	)

	await _traverse_lap(2, checkpoint_count, opening_distance)
	_validate_final_result()

	print("LAP CROSSING CONTINUITY PROBE: laps=%d results=%d respawns=%d automatic_recoveries=%d passed=%s" % [
		_lap_events.size(), _result_emissions, _respawn_count - _run_respawn_baseline,
		_automatic_recovery_count - _run_automatic_recovery_baseline, str(_passed),
	])
	await _finish_probe()


func _make_session_config() -> RaceSessionConfig:
	return RaceSessionConfig.from_dictionary({
		&"event_id": &"MESA_LAP_CONTINUITY_TEST",
		&"track_id": CourseCatalog.MESA_MX_ID,
		&"display_name": "MESA LAP CONTINUITY TEST",
		&"format": &"CIRCUIT",
		&"session_type": &"MAIN",
		&"championship_id": &"",
		&"route_version": CourseCatalog.MESA_MX_ROUTE_VERSION,
		&"laps": 2,
		&"opponent_count": 0,
		&"checkpoint_count": 6,
		&"countdown_seconds": 0.1,
		&"staging_seconds": 0.0,
		&"finish_grace_seconds": 0.0,
		&"off_course_grace_seconds": 2.4,
		&"wrong_way_grace_seconds": 1.4,
		&"reset_penalty_usec": 2_000_000,
		&"cut_penalty_usec": 3_000_000,
		&"weather": &"CLEAR",
		&"surface_modifier": &"PACKED",
	})


func _traverse_lap(lap_number: int, checkpoint_count: int, starting_distance: float) -> void:
	var current_distance := starting_distance
	for checkpoint_index: int in checkpoint_count:
		var target_distance := _route_length * float(checkpoint_index + 1) / float(checkpoint_count)
		await _advance_to_distance(current_distance, target_distance)
		current_distance = target_distance

		var gate := _race.get_node_or_null("Checkpoint%02d" % checkpoint_index) as Area3D
		if gate == null:
			_check(false, "lap %d gate %d exists" % [lap_number, checkpoint_index + 1])
			return
		if lap_number == 1 and checkpoint_index == checkpoint_count - 1:
			await _cross_intermediate_finish(gate, checkpoint_index)
		else:
			gate.emit_signal(&"body_entered", _bike)
			if checkpoint_index < checkpoint_count - 1:
				_check(
					_race.get_expected_checkpoint() == checkpoint_index + 1,
					"lap %d ordered gate %d" % [lap_number, checkpoint_index + 1],
					"expected=%d" % _race.get_expected_checkpoint()
				)


func _cross_intermediate_finish(final_gate: Area3D, gate_index: int) -> void:
	var pre_snapshot := _race.get_session_snapshot()
	var pre_integrity := pre_snapshot.get(&"integrity", {}) as Dictionary
	var integrity_events_before := _integrity_events.size()
	print("LAP CONTINUITY SEAM BEFORE: gate=%d authoritative_lap=%d integrity_lap=%d chainage=%.3f total=%.3f delta=%.3f allowed=%.3f penalty=%d incidents=%s reset=%s reason=%s" % [
		gate_index,
		int(pre_snapshot.get(&"current_lap", -1)),
		int(pre_integrity.get(&"lap", -1)),
		float(pre_integrity.get(&"chainage", -1.0)),
		float(pre_integrity.get(&"total_progress", -1.0)),
		float((pre_integrity.get(&"projection", {}) as Dictionary).get(&"progress_delta", 0.0)),
		float((pre_integrity.get(&"projection", {}) as Dictionary).get(&"allowed_progress_jump", 0.0)),
		int(pre_integrity.get(&"penalty_usec", -1)),
		str(pre_integrity.get(&"incidents", {})),
		str(pre_integrity.get(&"reset_requested", false)),
		String(pre_integrity.get(&"reset_reason", &"")),
	])
	_validate_clean_integrity("pre-intermediate finish approach")
	_check(
		int(pre_snapshot.get(&"current_lap", -1)) == 1
		and float(pre_integrity.get(&"chainage", 0.0)) >= _route_length * 0.90,
		"lap-one projection reaches finish alias",
		"lap=%d chainage=%.1f length=%.1f" % [
			int(pre_snapshot.get(&"current_lap", -1)),
			float(pre_integrity.get(&"chainage", 0.0)),
			_route_length,
		]
	)

	var before_transform := _bike.global_transform
	var before_linear_velocity := _bike.linear_velocity
	var before_angular_velocity := _bike.angular_velocity
	var respawns_before := _respawn_count
	var recoveries_before := _automatic_recovery_count
	var laps_before := _lap_events.size()

	final_gate.emit_signal(&"body_entered", _bike)

	var immediate_snapshot := _race.get_session_snapshot()
	var immediate_motion_preserved := (
		_bike.global_transform.is_equal_approx(before_transform)
		and _bike.linear_velocity.distance_to(before_linear_velocity) <= MOTION_TOLERANCE
		and _bike.angular_velocity.distance_to(before_angular_velocity) <= MOTION_TOLERANCE
		and _bike.linear_velocity.length() > 1.0
		and _bike.angular_velocity.length() > 0.1
	)
	_check(immediate_motion_preserved, "intermediate gate preserves live bike motion immediately", "linear=%s angular=%s" % [str(_bike.linear_velocity), str(_bike.angular_velocity)])
	_check(
		_race.state == RaceController.State.RACING
		and int(immediate_snapshot.get(&"laps_completed", -1)) == 1
		and int(immediate_snapshot.get(&"current_lap", -1)) == 2
		and _race.get_expected_checkpoint() == 0
		and _lap_events.size() == laps_before + 1,
		"intermediate gate advances exactly one lap",
		"state=%d completed=%d current=%d expected=%d lap_events=%d" % [
			_race.state,
			int(immediate_snapshot.get(&"laps_completed", -1)),
			int(immediate_snapshot.get(&"current_lap", -1)),
			_race.get_expected_checkpoint(),
			_lap_events.size(),
		]
	)
	_check(
		_respawn_count == respawns_before and _automatic_recovery_count == recoveries_before,
		"intermediate gate emits no synchronous recovery",
		"respawns=%d recoveries=%d" % [_respawn_count - respawns_before, _automatic_recovery_count - recoveries_before]
	)

	# Hold the bike on the final-segment alias for one real integrity update. This
	# is the ordering that previously interpreted the authoritative lap increment
	# as an entire-lap cut and respawned the bike on the same physics tick.
	await _settle_physics_frame()
	for event_index: int in range(integrity_events_before, _integrity_events.size()):
		var event := _integrity_events[event_index]
		var projection := event.get(&"projection", {}) as Dictionary
		print("LAP CONTINUITY SEAM AFTER: gate=%d event=%d integrity_lap=%d chainage=%.3f total=%.3f delta=%.3f allowed=%.3f segment=%d reset=%s reason=%s warning=%s" % [
			gate_index,
			event_index - integrity_events_before,
			int(event.get(&"lap", -1)),
			float(event.get(&"chainage", -1.0)),
			float(event.get(&"total_progress", -1.0)),
			float(projection.get(&"progress_delta", 0.0)),
			float(projection.get(&"allowed_progress_jump", 0.0)),
			int(event.get(&"segment", -1)),
			str(event.get(&"reset_requested", false)),
			String(event.get(&"reset_reason", &"")),
			String(event.get(&"warning", &"")),
		])
	var after_transform := _bike.global_transform
	var after_linear_velocity := _bike.linear_velocity
	var after_angular_velocity := _bike.angular_velocity
	var physical_travel := after_transform.origin.distance_to(before_transform.origin)
	var velocity_alignment := after_linear_velocity.normalized().dot(before_linear_velocity.normalized())
	var deferred_motion_preserved := (
		physical_travel <= 1.0
		and after_linear_velocity.length() > 1.0
		and velocity_alignment >= 0.75
	)
	_check(deferred_motion_preserved, "intermediate gate preserves motion through integrity tick", "travel=%.4f alignment=%.3f linear=%s angular=%s" % [
		physical_travel, velocity_alignment, str(after_linear_velocity), str(after_angular_velocity),
	])
	_check(
		_respawn_count == respawns_before and _automatic_recovery_count == recoveries_before,
		"intermediate gate causes no integrity respawn",
		"respawns=%d recoveries=%d" % [_respawn_count - respawns_before, _automatic_recovery_count - recoveries_before]
	)
	_validate_clean_integrity("intermediate finish integrity tick")


func _advance_to_distance(start_distance: float, finish_distance: float) -> void:
	var distance := clampf(start_distance, 0.0, _route_length)
	var target := clampf(finish_distance, distance, _route_length)
	while distance < target - 0.001:
		distance = minf(distance + TRAVEL_STEP_METERS, target)
		_place_bike_at_distance(distance)
		await _settle_physics_frame()


func _place_bike_at_distance(distance: float) -> void:
	var sample := _sample_route(distance)
	var position := sample.get(&"position", Vector3.ZERO) as Vector3
	var tangent := sample.get(&"tangent", Vector3.FORWARD) as Vector3
	var forward := Vector3(tangent.x, 0.0, tangent.z).normalized()
	if forward.length_squared() < 0.5:
		forward = Vector3.FORWARD
	_bike.global_transform = Transform3D(
		Basis.looking_at(forward, Vector3.UP),
		position + Vector3.UP * CHASSIS_CLEARANCE_METERS
	)
	_bike.linear_velocity = forward * TEST_SPEED_MPS
	_bike.angular_velocity = TEST_ANGULAR_VELOCITY
	_bike.sleeping = false


func _sample_route(distance: float) -> Dictionary:
	var target := clampf(distance, 0.0, _route_length)
	var low := 0
	var high := _route.size() - 2
	while low < high:
		var middle := (low + high) / 2
		if float(_route_distances[middle + 1]) < target:
			low = middle + 1
		else:
			high = middle
	var segment := clampi(low, 0, _route.size() - 2)
	var start := _route[segment]
	var finish := _route[segment + 1]
	var segment_length := maxf(start.distance_to(finish), 0.000001)
	var weight := clampf((target - float(_route_distances[segment])) / segment_length, 0.0, 1.0)
	return {
		&"position": start.lerp(finish, weight),
		&"tangent": (finish - start).normalized(),
	}


func _build_route_distances() -> void:
	_route_distances = PackedFloat32Array()
	_route_distances.resize(_route.size())
	_route_length = 0.0
	for index: int in range(1, _route.size()):
		_route_length += _route[index - 1].distance_to(_route[index])
		_route_distances[index] = _route_length


func _disable_automatic_gate_detection(checkpoint_count: int) -> void:
	for checkpoint_index: int in checkpoint_count:
		var gate := _race.get_node_or_null("Checkpoint%02d" % checkpoint_index) as Area3D
		if gate != null:
			gate.collision_mask = 0


func _validate_clean_integrity(label: String) -> void:
	var snapshot := _race.get_session_snapshot()
	var integrity := snapshot.get(&"integrity", {}) as Dictionary
	var incidents := integrity.get(&"incidents", {}) as Dictionary
	var metrics := _race.get_player_race_metrics_snapshot()
	var warning := StringName(integrity.get(&"warning", &""))
	var clean := (
		int(snapshot.get(&"penalty_usec", -1)) == 0
		and int(integrity.get(&"penalty_usec", -1)) == 0
		and not bool(integrity.get(&"reset_requested", false))
		and not bool(integrity.get(&"cut_detected", false))
		and warning in [&"", &"NONE", &"CLEAR"]
		and int(incidents.get(&"off_course", 0)) == 0
		and int(incidents.get(&"wrong_way", 0)) == 0
		and int(incidents.get(&"cuts", 0)) == 0
		and int(incidents.get(&"stuck", 0)) == 0
		and int(incidents.get(&"reset_requests", 0)) == 0
		and int(incidents.get(&"resets_consumed", 0)) == 0
		and int(metrics.get(&"recoveries", 0)) == 0
		and int(metrics.get(&"crashes", 0)) == 0
	)
	_check(clean, label, "warning=%s penalty=%d reset=%s incidents=%s metrics=%s" % [
		String(warning), int(integrity.get(&"penalty_usec", -1)),
		str(integrity.get(&"reset_requested", false)), str(incidents), str(metrics),
	])


func _validate_final_result() -> void:
	var result := _race.get_results_preview()
	var classification := result.get(&"classification", []) as Array
	var player: Dictionary = {}
	for racer_variant: Variant in classification:
		if racer_variant is Dictionary:
			var racer := racer_variant as Dictionary
			if bool(racer.get(&"is_player", false)):
				player = racer
				break

	var final_passed := (
		_race.state == RaceController.State.RESULTS
		and _lap_events.size() == 2
		and int(_lap_events[0].get(&"lap", -1)) == 1
		and int(_lap_events[1].get(&"lap", -1)) == 2
		and _result_emissions == 1
		and not result.is_empty()
		and result == _captured_result
		and not player.is_empty()
		and StringName(player.get(&"status", &"")) == &"FINISHED"
		and int(player.get(&"laps_completed", -1)) == 2
		and int(player.get(&"penalty_usec", -1)) == 0
		and int(result.get(&"player_penalty_usec", -1)) == 0
		and int(result.get(&"reset_count", -1)) == 0
		and int(result.get(&"recoveries", -1)) == 0
		and int(result.get(&"crashes", -1)) == 0
		and bool(result.get(&"valid", false))
		and (result.get(&"lap_times_usec", []) as Array).size() == 2
		and _respawn_count == _run_respawn_baseline
		and _automatic_recovery_count == _run_automatic_recovery_baseline
	)
	_check(final_passed, "final lap still produces one clean result", "state=%d laps=%s results=%d player=%s penalty=%d resets=%d recoveries=%d crashes=%d" % [
		_race.state, str(_lap_events), _result_emissions, str(player),
		int(result.get(&"player_penalty_usec", -1)), int(result.get(&"reset_count", -1)),
		int(result.get(&"recoveries", -1)), int(result.get(&"crashes", -1)),
	])


func _connect_monitors() -> void:
	_bike.respawned.connect(_on_bike_respawned)
	_bike.automatic_recovery_requested.connect(_on_automatic_recovery_requested)
	_race.lap_completed.connect(_on_lap_completed)
	_race.integrity_updated.connect(_on_integrity_updated)
	_race.results_ready.connect(_on_results_ready)


func _on_bike_respawned() -> void:
	_respawn_count += 1


func _on_automatic_recovery_requested(_reason: StringName) -> void:
	_automatic_recovery_count += 1


func _on_lap_completed(lap: int, total_laps: int, lap_usec: int, best_lap_usec: int) -> void:
	_lap_events.append({
		&"lap": lap,
		&"total_laps": total_laps,
		&"lap_usec": lap_usec,
		&"best_lap_usec": best_lap_usec,
	})


func _on_integrity_updated(snapshot: Dictionary) -> void:
	var event := snapshot.duplicate(true)
	var current_incidents := event.get(&"incidents", {}) as Dictionary
	var current_cuts := int(current_incidents.get(&"cuts", 0))
	var previous: Dictionary = _integrity_events[-1] if not _integrity_events.is_empty() else {}
	var previous_incidents := previous.get(&"incidents", {}) as Dictionary
	var previous_cuts := int(previous_incidents.get(&"cuts", 0))
	if current_cuts > previous_cuts or bool(event.get(&"reset_requested", false)):
		_print_integrity_transition("INCIDENT PREVIOUS", previous)
		_print_integrity_transition("INCIDENT CURRENT", event)
	_integrity_events.append(event)


func _print_integrity_transition(label: String, event: Dictionary) -> void:
	var projection := event.get(&"projection", {}) as Dictionary
	print("LAP CONTINUITY %s: lap=%d line=%s chainage=%.3f total=%.3f delta=%.3f allowed=%.3f segment=%d line_segment=%d reset=%s reason=%s incidents=%s" % [
		label,
		int(event.get(&"lap", -1)),
		String(event.get(&"route_line_id", &"")),
		float(event.get(&"chainage", -1.0)),
		float(event.get(&"total_progress", -1.0)),
		float(projection.get(&"progress_delta", 0.0)),
		float(projection.get(&"allowed_progress_jump", 0.0)),
		int(event.get(&"segment", -1)),
		int(event.get(&"route_line_segment", -1)),
		str(event.get(&"reset_requested", false)),
		String(event.get(&"reset_reason", &"")),
		str(event.get(&"incidents", {})),
	])


func _on_results_ready(result: Dictionary) -> void:
	_result_emissions += 1
	_captured_result = result.duplicate(true)


func _wait_for_state(target: RaceController.State, maximum_frames: int) -> bool:
	for _frame: int in maximum_frames:
		if _race.state == target:
			return true
		await get_tree().physics_frame
	return _race.state == target


func _settle_physics_frame() -> void:
	await get_tree().physics_frame
	# SceneTree.physics_frame is emitted before Node._physics_process. Waiting for
	# the following process frame guarantees RaceController consumed this sample.
	await get_tree().process_frame


func _check(condition: bool, label: String, details: String = "") -> void:
	var suffix := "" if details.is_empty() else "  //  %s" % details
	print("LAP CONTINUITY CHECK: %s passed=%s%s" % [label, str(condition), suffix])
	if condition:
		return
	_passed = false
	push_error("LAP CROSSING CONTINUITY: %s failed.%s" % [label, suffix])


func _finish_probe() -> void:
	if is_instance_valid(_race):
		_race.set_physics_process(false)
	if is_instance_valid(_bike):
		_bike.set_physics_process(false)
		_bike.shutdown_audio()
	if is_instance_valid(_ghost):
		_ghost.cancel_run()
	if is_instance_valid(_race):
		_race.queue_free()
	if is_instance_valid(_bike):
		_bike.queue_free()
	if is_instance_valid(_ghost):
		_ghost.queue_free()
	for _frame: int in 4:
		await get_tree().process_frame
	get_tree().quit(0 if _passed else 1)
