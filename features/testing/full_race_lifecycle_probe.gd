extends Node3D
## Focused headless integration probe for one complete competitive session.
##
## The probe uses the real bike, ghost, RaceController and RacePack.  It emits
## the actual checkpoint Area3D signals to exercise their ordered connection
## contract without teleporting through the integrity system.

const BIKE_SCENE := preload("res://entities/bike/bike.tscn")
const GHOST_SCENE := preload("res://features/race/ghost_controller.tscn")
const RACE_SCENE := preload("res://features/race/race_controller.tscn")

var _bike: DirtBikeController
var _ghost: GhostController
var _race: RaceController
var _passed := true
var _phase_events: Array[StringName] = []
var _flag_events: Array[StringName] = []
var _lap_events: Array[Dictionary] = []
var _classification_emissions := 0
var _result_emissions := 0
var _captured_result: Dictionary = {}


func _ready() -> void:
	Profile.persistence_enabled = false
	_run.call_deferred()


func _run() -> void:
	_bike = BIKE_SCENE.instantiate() as DirtBikeController
	_ghost = GHOST_SCENE.instantiate() as GhostController
	_race = RACE_SCENE.instantiate() as RaceController
	add_child(_bike)
	add_child(_ghost)
	add_child(_race)
	_ghost.persistence_enabled = false
	_connect_monitors()
	await _wait_physics_frames(2)

	var route := CourseCatalog.get_world_riding_points(CourseCatalog.MESA_MX_ID)
	_race.initialize(_bike, _ghost, CourseCatalog.MESA_MX_ID, route, null)
	var config := _make_session_config()
	_validate_session_round_trip(config)
	_race.configure_session(config, route, null)
	await _wait_physics_frames(2)

	var checkpoint_positions := _race.get_checkpoint_positions()
	_check(
		checkpoint_positions.size() == maxi(config.checkpoint_count, 6),
		"checkpoint catalog",
		"count=%d authored_request=%d" % [checkpoint_positions.size(), config.checkpoint_count]
	)
	_check(_checkpoint_nodes_are_wired(checkpoint_positions.size()), "checkpoint gates wired", "count=%d" % checkpoint_positions.size())
	_validate_named_field(6, &"RUNNING")

	_race.reset_run()
	var prestart := _race.get_session_snapshot()
	_check(_race.state == RaceController.State.COUNTDOWN, "restart enters countdown", "state=%d" % _race.state)
	_check(StringName(prestart.get(&"phase", &"")) in [&"STAGING", &"COUNTDOWN"], "staging presentation", "phase=%s" % String(prestart.get(&"phase", &"")))
	_check(int(prestart.get(&"current_checkpoint", -1)) == 0, "restart clears checkpoint progression")
	_check(int(prestart.get(&"current_lap", -1)) == 1, "restart begins lap one")

	var started := await _wait_for_state(RaceController.State.RACING, 30)
	_check(started, "countdown reaches racing", "state=%d" % _race.state)
	if not started:
		await _finish_probe()
		return
	_bike.set_motion_locked(true)
	_check(&"STAGING" in _phase_events and &"RACING" in _phase_events, "phase signals", "events=%s" % str(_phase_events))
	_check(&"YELLOW" in _flag_events and &"GREEN" in _flag_events, "start flags", "events=%s" % str(_flag_events))

	await _validate_rejoin_and_penalty(route, config)
	await _validate_ordered_multi_lap_checkpoints(checkpoint_positions.size())
	_validate_results(config)
	_validate_result_serialization()
	_validate_restart_after_results()

	print("FULL RACE LIFECYCLE PROBE: phases=%s flags=%s laps=%d classifications=%d results=%d passed=%s" % [
		str(_phase_events), str(_flag_events), _lap_events.size(), _classification_emissions,
		_result_emissions, str(_passed),
	])
	await _finish_probe()


func _make_session_config() -> RaceSessionConfig:
	return RaceSessionConfig.from_dictionary({
		&"event_id": &"MESA_MX",
		&"track_id": CourseCatalog.MESA_MX_ID,
		&"display_name": "RED MESA LIFECYCLE TEST",
		&"format": &"CIRCUIT",
		&"session_type": &"MAIN",
		&"championship_id": &"DIRT_TOUR",
		&"route_version": CourseCatalog.MESA_MX_ROUTE_VERSION,
		&"laps": 2,
		&"opponent_count": 5,
		&"checkpoint_count": 4,
		&"countdown_seconds": 0.1,
		&"staging_seconds": 0.0,
		&"finish_grace_seconds": 0.0,
		&"off_course_grace_seconds": 2.4,
		&"wrong_way_grace_seconds": 1.4,
		&"reset_penalty_usec": 2_000_000,
		&"cut_penalty_usec": 3_000_000,
		&"medal_times_usec": {
			&"gold": 30_000_000,
			&"silver": 45_000_000,
			&"bronze": 60_000_000,
		},
		&"weather": &"CLEAR",
		&"surface_modifier": &"PACKED",
	})


func _validate_session_round_trip(config: RaceSessionConfig) -> void:
	var clone := RaceSessionConfig.from_dictionary(config.to_dictionary())
	var signature := clone.run_signature(&"TRAIL", &"SPORT", "BASELINE")
	var passed := (
		clone.event_id == config.event_id
		and clone.track_id == config.track_id
		and clone.laps == 2
		and clone.field_size == 6
		and clone.checkpoint_count == 4
		and clone.reset_penalty_usec == 2_000_000
		and signature.contains("MESA_MX")
		and signature.contains("l2")
	)
	_check(passed, "session config round trip", "signature=%s field=%d" % [signature, clone.field_size])


func _checkpoint_nodes_are_wired(count: int) -> bool:
	for index: int in count:
		var gate := _race.get_node_or_null("Checkpoint%02d" % index) as Area3D
		if gate == null or not gate.body_entered.has_connections():
			return false
	return true


func _validate_named_field(expected_size: int, expected_status: StringName) -> void:
	var classification := _race.get_classification_snapshot()
	var rider_ids: Dictionary = {}
	var numbers: Dictionary = {}
	var named_opponents := 0
	var schema_complete := true
	for racer: Dictionary in classification:
		var rider_id := StringName(racer.get(&"rider_id", &""))
		var number := int(racer.get(&"number", 0))
		schema_complete = schema_complete and not rider_id.is_empty() and number > 0 and racer.get(&"color", null) is Color
		schema_complete = schema_complete and not rider_ids.has(rider_id) and not numbers.has(number)
		rider_ids[rider_id] = true
		numbers[number] = true
		if not bool(racer.get(&"is_player", false)):
			var display_name := str(racer.get(&"display_name", ""))
			named_opponents += int(not display_name.is_empty() and not display_name.begins_with("RIDER"))
			schema_complete = schema_complete and StringName(racer.get(&"status", &"")) == expected_status
	_check(classification.size() == expected_size, "field size", "size=%d expected=%d" % [classification.size(), expected_size])
	_check(named_opponents == expected_size - 1, "named opponent field", "named=%d" % named_opponents)
	_check(schema_complete, "classification identity schema", "ids=%s numbers=%s" % [str(rider_ids.keys()), str(numbers.keys())])


func _validate_rejoin_and_penalty(route: PackedVector3Array, config: RaceSessionConfig) -> void:
	# Advance far enough to prove that rejoin capture moves beyond the grid, but
	# remain inside the integrity tracker's legal single-update jump envelope.
	# Teleporting to a fixed sample index became invalid once route sampling grew
	# denser: index 24 can now correctly look like a course cut.
	var route_index := 1
	var spawn_origin := _race.get_spawn_transform().origin
	for candidate: int in range(1, route.size() - 1):
		var horizontal_distance := Vector2(route[candidate].x, route[candidate].z).distance_to(
			Vector2(spawn_origin.x, spawn_origin.z)
		)
		if horizontal_distance >= 8.0:
			route_index = candidate
			break
	var forward := (route[route_index + 1] - route[route_index]).normalized()
	var target := Transform3D(Basis.looking_at(forward, Vector3.UP), route[route_index] + Vector3.UP)
	_bike.respawn_at(target)
	await _wait_physics_frames(24)
	var before := _race.get_session_snapshot()
	var before_integrity := before.get(&"integrity", {}) as Dictionary
	var rejoin_variant: Variant = before_integrity.get(&"last_legal_rejoin_transform", _race.get_spawn_transform())
	var advertised_rejoin := rejoin_variant as Transform3D if rejoin_variant is Transform3D else _race.get_spawn_transform()
	var captured_forward := Vector2(advertised_rejoin.origin.x, advertised_rejoin.origin.z).distance_to(Vector2(target.origin.x, target.origin.z)) <= 2.0
	var advanced_from_spawn := Vector2(advertised_rejoin.origin.x, advertised_rejoin.origin.z).distance_to(Vector2(_race.get_spawn_transform().origin.x, _race.get_spawn_transform().origin.z)) >= 4.0
	_check(captured_forward and advanced_from_spawn, "last legal rejoin capture", "target=%s rejoin=%s" % [str(target.origin), str(advertised_rejoin.origin)])

	_race.request_player_reset()
	await get_tree().process_frame
	var after := _race.get_session_snapshot()
	var after_integrity := after.get(&"integrity", {}) as Dictionary
	var incidents := after_integrity.get(&"incidents", {}) as Dictionary
	var penalties := after_integrity.get(&"penalties", {}) as Dictionary
	var respawn_error := _bike.global_position.distance_to(advertised_rejoin.origin)
	var penalty_passed := (
		int(after.get(&"penalty_usec", -1)) == config.reset_penalty_usec
		and int(after_integrity.get(&"penalty_usec", -1)) == config.reset_penalty_usec
		and int(incidents.get(&"resets_consumed", 0)) == 1
		and int(penalties.get(&"MANUAL_RESET", 0)) == config.reset_penalty_usec
	)
	_check(respawn_error <= 0.05, "manual rejoin transform", "error=%.4fm" % respawn_error)
	_check(penalty_passed, "manual reset penalty", "session=%d integrity=%d incidents=%s penalties=%s" % [
		int(after.get(&"penalty_usec", -1)), int(after_integrity.get(&"penalty_usec", -1)),
		str(incidents), str(penalties),
	])


func _validate_ordered_multi_lap_checkpoints(checkpoint_count: int) -> void:
	var wrong_body := Node3D.new()
	wrong_body.name = "WrongCheckpointBody"
	add_child(wrong_body)
	var first_gate := _race.get_node("Checkpoint00") as Area3D
	var second_gate := _race.get_node("Checkpoint01") as Area3D
	second_gate.emit_signal(&"body_entered", _bike)
	first_gate.emit_signal(&"body_entered", wrong_body)
	_check(_race.get_expected_checkpoint() == 0, "out-of-order gates rejected", "expected=%d" % _race.get_expected_checkpoint())
	wrong_body.queue_free()

	for lap_number: int in range(1, 3):
		for checkpoint_index: int in checkpoint_count:
			var gate := _race.get_node("Checkpoint%02d" % checkpoint_index) as Area3D
			gate.emit_signal(&"body_entered", _bike)
			if checkpoint_index < checkpoint_count - 1:
				_check(
					_race.get_expected_checkpoint() == checkpoint_index + 1,
					"ordered checkpoint L%d C%d" % [lap_number, checkpoint_index + 1],
					"expected=%d" % _race.get_expected_checkpoint()
				)
			await get_tree().physics_frame
		if lap_number == 1:
			var lap_snapshot := _race.get_session_snapshot()
			var first_gate_rearmed := (_race.get_node("Checkpoint00") as Area3D).visible
			var finish_gate_staged := not (_race.get_node("Checkpoint%02d" % (checkpoint_count - 1)) as Area3D).visible
			_check(_race.state == RaceController.State.RACING, "first lap does not finish race", "state=%d" % _race.state)
			_check(
				int(lap_snapshot.get(&"laps_completed", -1)) == 1 and int(lap_snapshot.get(&"current_lap", -1)) == 2,
				"multi-lap progression",
				"completed=%d current=%d total=%d" % [
					int(lap_snapshot.get(&"laps_completed", -1)), int(lap_snapshot.get(&"current_lap", -1)),
					int(lap_snapshot.get(&"total_laps", -1)),
				]
			)
			_check(
				int(lap_snapshot.get(&"current_checkpoint", -1)) == 0 and first_gate_rearmed and finish_gate_staged,
				"checkpoint chain rearms",
				"expected=%d first=%s finish_staged=%s" % [_race.get_expected_checkpoint(), str(first_gate_rearmed), str(finish_gate_staged)]
			)
			_check(StringName(lap_snapshot.get(&"flag", &"")) == &"WHITE" and &"WHITE" in _flag_events, "white flag final lap", "flags=%s" % str(_flag_events))

	_check(_race.state == RaceController.State.RESULTS, "final lap reaches results", "state=%d" % _race.state)
	_check(_result_emissions == 1 and not _captured_result.is_empty(), "results signal emitted once", "count=%d" % _result_emissions)
	_check(_lap_events.size() == 2, "lap completion signals", "events=%s" % str(_lap_events))


func _validate_results(config: RaceSessionConfig) -> void:
	var result := _race.get_results_preview()
	var classification := result.get(&"classification", []) as Array
	var player: Dictionary = {}
	var dnf_count := 0
	var ordered_positions := true
	var dnf_schema := true
	for index: int in classification.size():
		var racer := classification[index] as Dictionary
		ordered_positions = ordered_positions and int(racer.get(&"position", 0)) == index + 1
		if bool(racer.get(&"is_player", false)):
			player = racer
		elif StringName(racer.get(&"status", &"")) == &"DNF":
			dnf_count += 1
			dnf_schema = dnf_schema and int(racer.get(&"finish_usec", 0)) == -1
			dnf_schema = dnf_schema and racer.has(&"penalty_usec") and racer.has(&"effective_time_usec")

	var schema_passed := (
		StringName(result.get(&"event_id", &"")) == config.event_id
		and StringName(result.get(&"track_id", &"")) == config.track_id
		and not str(result.get(&"run_id", "")).is_empty()
		and not str(result.get(&"signature", "")).is_empty()
		and classification.size() == config.field_size
		and ordered_positions
		and dnf_count == config.opponent_count
		and dnf_schema
	)
	var player_passed := (
		not player.is_empty()
		and StringName(player.get(&"status", &"")) == &"FINISHED"
		and int(player.get(&"laps_completed", -1)) == config.laps
		and int(player.get(&"penalty_usec", -1)) == config.reset_penalty_usec
		and int(player.get(&"effective_time_usec", -1))
			== int(player.get(&"finish_usec", -1)) + config.reset_penalty_usec
	)
	var summary_passed := (
		int(result.get(&"player_penalty_usec", -1)) == config.reset_penalty_usec
		and int(result.get(&"reset_count", 0)) == 1
		and int(result.get(&"recoveries", 0)) == 1
		and int(result.get(&"crashes", -1)) == 0
		and (result.get(&"lap_times_usec", []) as Array).size() == config.laps
		and (result.get(&"sector_times_usec", []) as Array).size() == config.laps * _race.get_checkpoint_positions().size()
		and result.get(&"rewards", {}) is Dictionary
		and int(result.get(&"championship_points", 0)) > 0
	)
	_check(schema_passed, "full classification and DNF schema", "size=%d dnf=%d ordered=%s" % [classification.size(), dnf_count, str(ordered_positions)])
	_check(player_passed, "player finish and penalty classification", "player=%s" % str(player))
	_check(summary_passed, "result statistics and rewards", "penalty=%d resets=%d recoveries=%d crashes=%d laps=%s sectors=%d" % [
		int(result.get(&"player_penalty_usec", -1)), int(result.get(&"reset_count", 0)),
		int(result.get(&"recoveries", -1)), int(result.get(&"crashes", -1)),
		str(result.get(&"lap_times_usec", [])), (result.get(&"sector_times_usec", []) as Array).size(),
	])
	_check(result == _captured_result, "results preview matches emitted payload")
	_validate_named_field(config.field_size, &"DNF")


func _validate_result_serialization() -> void:
	var json := JSON.stringify(_captured_result)
	var parsed_variant: Variant = JSON.parse_string(json)
	var parsed := parsed_variant as Dictionary if parsed_variant is Dictionary else {}
	var parsed_classification := parsed.get("classification", []) as Array
	var passed := (
		not json.is_empty()
		and not json.contains("<Object#")
		and not parsed.is_empty()
		and str(parsed.get("event_id", "")) == "MESA_MX"
		and parsed_classification.size() == 6
		and int(parsed.get("player_penalty_usec", -1)) == 2_000_000
		and (parsed.get("lap_times_usec", []) as Array).size() == 2
	)
	_check(passed, "result JSON round trip", "bytes=%d parsed_field=%d" % [json.length(), parsed_classification.size()])


func _validate_restart_after_results() -> void:
	_race.reset_run()
	var snapshot := _race.get_session_snapshot()
	var restart_classification := _race.get_classification_snapshot()
	var statuses_reset := true
	for racer: Dictionary in restart_classification:
		statuses_reset = statuses_reset and StringName(racer.get(&"status", &"")) == &"RUNNING"
	var passed := (
		_race.state == RaceController.State.COUNTDOWN
		and _race.get_expected_checkpoint() == 0
		and int(snapshot.get(&"current_lap", -1)) == 1
		and int(snapshot.get(&"laps_completed", -1)) == 0
		and int(snapshot.get(&"penalty_usec", -1)) == 0
		and _race.get_results_preview().is_empty()
		and statuses_reset
		and _bike.global_position.distance_to(_race.get_spawn_transform().origin) <= 0.05
	)
	_check(passed, "restart clears lifecycle state", "state=%d checkpoint=%d lap=%d penalty=%d statuses=%s" % [
		_race.state, _race.get_expected_checkpoint(), int(snapshot.get(&"current_lap", -1)),
		int(snapshot.get(&"penalty_usec", -1)), str(statuses_reset),
	])


func _connect_monitors() -> void:
	_race.phase_changed.connect(_on_phase_changed)
	_race.flag_changed.connect(_on_flag_changed)
	_race.lap_completed.connect(_on_lap_completed)
	_race.classification_updated.connect(_on_classification_updated)
	_race.results_ready.connect(_on_results_ready)


func _on_phase_changed(phase: StringName) -> void:
	_phase_events.append(phase)


func _on_flag_changed(flag: StringName) -> void:
	_flag_events.append(flag)


func _on_lap_completed(lap: int, total_laps: int, lap_usec: int, best_lap_usec: int) -> void:
	_lap_events.append({
		&"lap": lap,
		&"total_laps": total_laps,
		&"lap_usec": lap_usec,
		&"best_lap_usec": best_lap_usec,
	})


func _on_classification_updated(_classification: Array[Dictionary]) -> void:
	_classification_emissions += 1


func _on_results_ready(result: Dictionary) -> void:
	_result_emissions += 1
	_captured_result = result.duplicate(true)


func _wait_for_state(target: RaceController.State, maximum_frames: int) -> bool:
	for _frame: int in maximum_frames:
		if _race.state == target:
			return true
		await get_tree().physics_frame
	return _race.state == target


func _wait_physics_frames(frame_count: int) -> void:
	for _frame: int in frame_count:
		await get_tree().physics_frame


func _check(condition: bool, label: String, details: String = "") -> void:
	var suffix := "" if details.is_empty() else "  //  %s" % details
	print("FULL RACE CHECK: %s passed=%s%s" % [label, str(condition), suffix])
	if condition:
		return
	_passed = false
	push_error("FULL RACE LIFECYCLE: %s failed.%s" % [label, suffix])


func _finish_probe() -> void:
	if is_instance_valid(_race):
		_race.set_physics_process(false)
	if is_instance_valid(_bike):
		_bike.set_physics_process(false)
		_bike.shutdown_audio()
	if is_instance_valid(_ghost):
		_ghost.cancel_run()
	for _frame: int in 3:
		await get_tree().process_frame
	get_tree().quit(0 if _passed else 1)
