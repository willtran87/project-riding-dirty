extends Node3D
## Focused headless regression for bike-owned automatic recovery integration.
##
## Definition of done:
## - tipped and world-fall recoveries enter race integrity once with a reason;
## - each active-race recovery consumes one reset and one configured penalty;
## - NO_RESETS rejects a result containing an automatic recovery;
## - an inactive RaceController leaves recovery immediate and penalty-free.

const BIKE_SCENE := preload("res://entities/bike/bike.tscn")
const GHOST_SCENE := preload("res://features/race/ghost_controller.tscn")
const RACE_SCENE := preload("res://features/race/race_controller.tscn")

const RESET_PENALTY_USEC := 2_000_000

var _bike: DirtBikeController
var _ghost: GhostController
var _race: RaceController
var _passed := true
var _automatic_request_count := 0
var _respawn_count := 0
var _automatic_reasons: Array[StringName] = []
var _race_moments: Array[Dictionary] = []
var _finished := false


func _ready() -> void:
	Profile.persistence_enabled = false
	get_tree().create_timer(20.0).timeout.connect(_on_probe_timeout)
	_run.call_deferred()


func _run() -> void:
	_bike = BIKE_SCENE.instantiate() as DirtBikeController
	_ghost = GHOST_SCENE.instantiate() as GhostController
	_race = RACE_SCENE.instantiate() as RaceController
	_race.race_moment.connect(_on_race_moment)
	_bike.automatic_recovery_requested.connect(_on_automatic_recovery_requested)
	_bike.respawned.connect(_on_bike_respawned)
	add_child(_bike)
	add_child(_ghost)
	add_child(_race)
	_ghost.persistence_enabled = false
	await _wait_physics_frames(2)

	var route := CourseCatalog.get_world_riding_points(CourseCatalog.QUARRY_ID)
	_race.initialize(_bike, _ghost, CourseCatalog.QUARRY_ID, route, null)
	_race.configure_session(_make_session_config(), route, null)

	await _validate_tipped_recovery_and_no_resets()
	await _validate_world_fall_recovery()
	await _validate_academy_recovery_coaching()
	await _validate_inactive_freeride_recovery()

	print("AUTOMATIC RECOVERY INTEGRITY PROBE: requests=%d respawns=%d reasons=%s passed=%s" % [
		_automatic_request_count, _respawn_count, str(_automatic_reasons), str(_passed),
	])
	await _finish_probe()


func _make_session_config() -> RaceSessionConfig:
	return RaceSessionConfig.from_dictionary({
		&"event_id": &"AUTO_RECOVERY_TEST",
		&"track_id": CourseCatalog.QUARRY_ID,
		&"display_name": "AUTOMATIC RECOVERY TEST",
		&"format": &"SPRINT",
		&"session_type": &"MAIN",
		&"championship_id": &"",
		&"laps": 1,
		&"opponent_count": 0,
		&"checkpoint_count": 4,
		&"countdown_seconds": 0.1,
		&"staging_seconds": 0.0,
		&"finish_grace_seconds": 0.0,
		&"reset_penalty_usec": RESET_PENALTY_USEC,
		&"rules": {&"modifiers": ["NO_RESETS"]},
	})


func _make_academy_session_config() -> RaceSessionConfig:
	return RaceSessionConfig.from_dictionary({
		&"event_id": &"ACADEMY",
		&"track_id": CourseCatalog.QUARRY_ID,
		&"display_name": "ACADEMY RECOVERY TEST",
		&"format": &"ACADEMY",
		&"session_type": &"ACADEMY",
		&"championship_id": &"",
		&"laps": 1,
		&"opponent_count": 0,
		&"checkpoint_count": 4,
		&"countdown_seconds": 0.1,
		&"staging_seconds": 0.0,
		&"finish_grace_seconds": 0.0,
		&"reset_penalty_usec": 0,
		&"rules": {
			&"academy": true,
			&"academy_lesson_id": &"CONTROL_BASICS",
			&"academy_objectives": [
				{&"metric": &"resets", &"comparison": &"AT_MOST", &"bronze": 2.0},
			],
		},
	})


func _validate_tipped_recovery_and_no_resets() -> void:
	await _start_race()
	_bike.set_motion_locked(true)
	var requests_before := _automatic_request_count
	var respawns_before := _respawn_count
	_bike.reset_to_safe_position(DirtBikeController.RECOVERY_TIPPED)
	await _wait_physics_frames(4)

	_check(
		_automatic_request_count - requests_before == 1,
		"tipped request emitted once",
		"delta=%d" % (_automatic_request_count - requests_before)
	)
	_check(
		_respawn_count - respawns_before == 1,
		"tipped recovery respawned once",
		"delta=%d" % (_respawn_count - respawns_before)
	)
	_validate_integrity_incident(DirtBikeController.RECOVERY_TIPPED)
	_validate_player_metrics(1, 1, 0, 0, "tipped player telemetry")

	for checkpoint_index: int in _race.get_checkpoint_positions().size():
		var gate := _race.get_node("Checkpoint%02d" % checkpoint_index) as Area3D
		gate.emit_signal(&"body_entered", _bike)
		await get_tree().physics_frame
	var result := _race.get_results_preview()
	var academy := result.get(&"academy_metrics", {}) as Dictionary
	_check(not result.is_empty(), "automatic recovery run produced results")
	_check(int(result.get(&"reset_count", 0)) == 1, "result records one automatic reset", "result=%s" % str(result))
	_check(
		int(result.get(&"recoveries", 0)) == 1 and int(result.get(&"crashes", 0)) == 1,
		"result records player recovery and crash only",
		"recoveries=%d crashes=%d" % [int(result.get(&"recoveries", 0)), int(result.get(&"crashes", 0))]
	)
	_check(
		int(academy.get(&"successful_rejoins", 0)) == 1 and int(academy.get(&"crashes", 0)) == 1,
		"academy consumes player recovery telemetry",
		"academy=%s" % str(academy)
	)
	_check(
		not bool(result.get(&"valid", true)) and str(result.get(&"validity_reason", "")).contains("NO_RESETS"),
		"NO_RESETS invalidates automatic recovery",
		"valid=%s reason=%s" % [str(result.get(&"valid", true)), str(result.get(&"validity_reason", ""))]
	)


func _validate_world_fall_recovery() -> void:
	await _start_race()
	var below_world := _race.get_spawn_transform()
	below_world.origin.y = -8.0
	_bike.respawn_at(below_world)
	var requests_before := _automatic_request_count
	var respawns_before := _respawn_count
	var recovered := await _wait_for_automatic_request(requests_before + 1, 8)
	_bike.set_motion_locked(true)

	_check(recovered, "world-fall recovery requested", "requests=%d" % _automatic_request_count)
	_check(
		_automatic_request_count - requests_before == 1,
		"world-fall request emitted once",
		"delta=%d" % (_automatic_request_count - requests_before)
	)
	_check(
		_respawn_count - respawns_before == 1,
		"world-fall recovery respawned once",
		"delta=%d" % (_respawn_count - respawns_before)
	)
	_check(
		not _automatic_reasons.is_empty() and _automatic_reasons.back() == DirtBikeController.RECOVERY_WORLD_FALL,
		"world-fall reason preserved",
		"reasons=%s" % str(_automatic_reasons)
	)
	_validate_integrity_incident(DirtBikeController.RECOVERY_WORLD_FALL)
	_validate_player_metrics(1, 1, 0, 0, "world-fall player telemetry")


func _validate_inactive_freeride_recovery() -> void:
	_race.enter_waiting()
	var requests_before := _automatic_request_count
	var respawns_before := _respawn_count
	_bike.reset_to_safe_position(DirtBikeController.RECOVERY_TIPPED)
	await get_tree().process_frame
	var snapshot := _race.get_session_snapshot()
	var integrity := snapshot.get(&"integrity", {}) as Dictionary
	var incidents := integrity.get(&"incidents", {}) as Dictionary

	_check(_automatic_request_count - requests_before == 1, "inactive recovery still immediate")
	_check(_respawn_count - respawns_before == 1, "inactive recovery uses one local respawn")
	_check(int(snapshot.get(&"penalty_usec", -1)) == 0, "inactive recovery has no race penalty")
	_check(int(incidents.get(&"resets_consumed", 0)) == 0, "inactive recovery does not consume race reset")
	_validate_player_metrics(0, 0, 0, 0, "inactive recovery excluded from race telemetry")


func _validate_academy_recovery_coaching() -> void:
	var route := CourseCatalog.get_world_riding_points(CourseCatalog.QUARRY_ID)
	_race.configure_session(_make_academy_session_config(), route, null)
	await _start_race()
	var moment_count_before := _race_moments.size()
	_bike.reset_to_safe_position(DirtBikeController.RECOVERY_TIPPED)
	await _wait_physics_frames(4)
	var snapshot := _race.get_session_snapshot()
	var integrity := snapshot.get(&"integrity", {}) as Dictionary
	var incidents := integrity.get(&"incidents", {}) as Dictionary
	var latest_moment: Dictionary = _race_moments.back() if not _race_moments.is_empty() else {}
	var moment_label := str(latest_moment.get(&"label", ""))
	_check(int(snapshot.get(&"penalty_usec", -1)) == 0, "Academy recovery has no time penalty")
	_check(int(incidents.get(&"resets_consumed", 0)) == 1, "Academy recovery still counts toward its objective")
	_check(_race_moments.size() == moment_count_before + 1, "Academy recovery emits one coaching moment")
	_check(
		moment_label.contains("COACH")
		and moment_label.contains("RESET 1 / 2")
		and moment_label.contains("KEEP GOING")
		and not moment_label.contains("+0.0"),
		"Academy recovery uses encouraging objective-aware text",
		"moment=%s" % moment_label
	)
	_check(bool(latest_moment.get(&"positive", false)), "Academy recovery feedback uses positive polarity")


func _start_race() -> void:
	_race.reset_run()
	var started := await _wait_for_state(RaceController.State.RACING, 30)
	_check(started, "countdown reaches racing", "state=%d" % _race.state)


func _validate_integrity_incident(reason: StringName) -> void:
	var snapshot := _race.get_session_snapshot()
	var integrity := snapshot.get(&"integrity", {}) as Dictionary
	var incidents := integrity.get(&"incidents", {}) as Dictionary
	var penalties := integrity.get(&"penalties", {}) as Dictionary
	_check(int(snapshot.get(&"penalty_usec", -1)) == RESET_PENALTY_USEC, "%s session penalty" % String(reason))
	_check(int(integrity.get(&"penalty_usec", -1)) == RESET_PENALTY_USEC, "%s integrity penalty" % String(reason))
	_check(int(incidents.get(&"reset_requests", 0)) == 1, "%s integrity request count" % String(reason))
	_check(int(incidents.get(&"resets_consumed", 0)) == 1, "%s integrity consumed count" % String(reason))
	_check(int(penalties.get(reason, 0)) == RESET_PENALTY_USEC, "%s reasoned penalty breakdown" % String(reason), "penalties=%s" % str(penalties))


func _validate_player_metrics(
	expected_recoveries: int,
	expected_crashes: int,
	expected_contacts: int,
	expected_overtakes: int,
	label: String
) -> void:
	var metrics := _race.get_player_race_metrics_snapshot()
	_check(
		int(metrics.get(&"recoveries", -1)) == expected_recoveries
		and int(metrics.get(&"crashes", -1)) == expected_crashes
		and int(metrics.get(&"contacts", -1)) == expected_contacts
		and int(metrics.get(&"overtakes", -1)) == expected_overtakes,
		label,
		"metrics=%s" % str(metrics)
	)


func _on_automatic_recovery_requested(reason: StringName) -> void:
	_automatic_request_count += 1
	_automatic_reasons.append(reason)


func _on_bike_respawned() -> void:
	_respawn_count += 1


func _on_race_moment(label: String, points: int, positive: bool) -> void:
	_race_moments.append({&"label": label, &"points": points, &"positive": positive})


func _wait_for_state(target: RaceController.State, maximum_frames: int) -> bool:
	for _frame: int in maximum_frames:
		if _race.state == target:
			return true
		await get_tree().physics_frame
	return _race.state == target


func _wait_for_automatic_request(target_count: int, maximum_frames: int) -> bool:
	for _frame: int in maximum_frames:
		if _automatic_request_count >= target_count:
			return true
		await get_tree().physics_frame
	return _automatic_request_count >= target_count


func _wait_physics_frames(frame_count: int) -> void:
	for _frame: int in frame_count:
		await get_tree().physics_frame


func _check(condition: bool, label: String, details: String = "") -> void:
	var suffix := "" if details.is_empty() else "  //  %s" % details
	print("AUTOMATIC RECOVERY CHECK: %s passed=%s%s" % [label, str(condition), suffix])
	if condition:
		return
	_passed = false
	push_error("AUTOMATIC RECOVERY INTEGRITY: %s failed.%s" % [label, suffix])


func _finish_probe() -> void:
	_finished = true
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


func _on_probe_timeout() -> void:
	if _finished:
		return
	push_error("AUTOMATIC RECOVERY INTEGRITY PROBE timed out in state=%s moments=%s" % [
		str(_race.state if is_instance_valid(_race) else -1),
		str(_race_moments),
	])
	get_tree().quit(1)
