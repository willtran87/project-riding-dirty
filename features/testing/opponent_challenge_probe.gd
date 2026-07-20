extends Node
## Fixed-step acceptance coverage for production opponent pacing. The probe
## advances RacePack without presentation or wall-clock waits, then validates
## full-race outcomes against deliberately broad balance envelopes.

const STEP := 0.20
const MAX_SIMULATION_SECONDS := 720.0
const AUDIT_EVENTS: Array[StringName] = [&"CIRCUIT", &"PINE_ENDURO", &"MESA_MX"]
const MAIN_SCRIPT := preload("res://scenes/main.gd")
const REPLAY_EVENT := &"CIRCUIT"
const STARTER_CLASS := &"LITE_125"
const UPGRADED_BUILD_ID := &"ROOK_450"
const UPGRADED_SETUP := &"ATTACK"
const UPGRADED_SETUP_FACTOR := 1.04
const GOLD_BENCHMARK_RATIO := 1.0
const FLOW_SURGE_BENCHMARK_RATIO := 0.710
const FLOW_SURGE_STATIC_MIN_PLACE := 1
const FLOW_SURGE_STATIC_MAX_PLACE := 4
const FLOW_SURGE_PRESSURE_MIN_PLACE := 4
const FLOW_SURGE_PRESSURE_MAX_PLACE := 10
const FLOW_SURGE_ELITE_RATIO := 0.670
const FLOW_SURGE_ELITE_MIN_PLACE := 1
const FLOW_SURGE_ELITE_MAX_PLACE := 3
const UPGRADED_MIDPOINT_RATIO := 0.555
const UPGRADED_MIDFIELD_MIN_PLACE := 4
const UPGRADED_MIDFIELD_MAX_PLACE := 9
const UPGRADED_ELITE_RATIO := 0.530
const DEFENSE_SETUP_SECONDS := 4.20
const DEFENSE_MAX_STEPS := 30
const DEFENSE_FOLLOW_THROUGH_STEPS := 2

# Adjacent tiers should be perceptible without becoming difficulty cliffs.
const MIN_ADJACENT_SEPARATION_RATIO := 0.020
const MAX_ADJACENT_SEPARATION_RATIO := 0.075
const MIN_FIELD_SPREAD_RATIO := 0.015
const MAX_FIELD_SPREAD_RATIO := 0.080
const MIN_LANE_CHANGES_PER_RIDER := 3
const MAX_LANE_CHANGES_PER_RIDER := 32
const MIN_MISTAKES_PER_RIDER := 1
const MAX_MISTAKES_PER_RIDER := 18
const MIN_UPGRADED_BUILD_GAIN_RATIO := 0.035
const MAX_UPGRADED_BUILD_GAIN_RATIO := 0.120
const MIN_STARTER_CLASS_PENALTY_RATIO := 0.060
const MAX_STARTER_CLASS_PENALTY_RATIO := 0.250

# Finish-time ratios are relative to the authored gold benchmark. These windows
# are intentionally wider than the deterministic samples: they catch a field
# that becomes irrelevant or impossible while leaving room for AI tuning.
const BENCHMARK_WINDOWS: Dictionary = {
	&"RELAXED": {
		&"leader_min": 0.55, &"leader_max": 0.82,
		&"median_min": 0.56, &"median_max": 0.84,
	},
	&"STANDARD": {
		&"leader_min": 0.49, &"leader_max": 0.75,
		&"median_min": 0.50, &"median_max": 0.78,
	},
	&"EXPERT": {
		&"leader_min": 0.45, &"leader_max": 0.68,
		&"median_min": 0.46, &"median_max": 0.72,
	},
}

var _failures: Array[String] = []
var _pack: RacePack
var _simulation_count := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var previous_persistence := Profile.persistence_enabled
	var previous_mode := RaceEventCatalog.get_player_difficulty_mode()
	Profile.persistence_enabled = false
	_pack = RacePack.new()
	_pack.presentation_enabled = false
	_pack.simulation_has_player = true
	add_child(_pack)
	_pack.set_process(false)
	_pack.set_physics_process(false)

	var audit_events: Array[StringName] = []
	audit_events.assign(AUDIT_EVENTS)
	if &"--single" in OS.get_cmdline_user_args():
		audit_events.assign([REPLAY_EVENT])
	var report: Dictionary = {}
	for event_id: StringName in audit_events:
		var tiers: Dictionary = {}
		for mode: StringName in RaceEventCatalog.PLAYER_DIFFICULTY_MODES:
			RaceEventCatalog.set_player_difficulty_mode(mode)
			var sample := _simulate_event(event_id)
			tiers[mode] = sample
			_validate_sample(event_id, mode, sample)
			_print_sample(event_id, mode, sample)
		report[event_id] = tiers
		_validate_event_separation(event_id, tiers)

	RaceEventCatalog.set_player_difficulty_mode(&"STANDARD")
	var replay_reference := (
		(report.get(REPLAY_EVENT, {}) as Dictionary).get(&"STANDARD", {}) as Dictionary
	)
	var replay_sample := _simulate_event(REPLAY_EVENT)
	_validate_deterministic_replay(replay_reference, replay_sample)

	var starter_sample := _simulate_session(
		RaceEventCatalog.get_session_config(REPLAY_EVENT, -1, STARTER_CLASS)
	)
	_validate_sample(&"CIRCUIT_STARTER", &"STANDARD", starter_sample)
	_print_sample(&"CIRCUIT_STARTER", &"STANDARD", starter_sample)
	_validate_starter_class(replay_reference, starter_sample)
	var starter_traffic_sample := _simulate_session(
		RaceEventCatalog.get_session_config(REPLAY_EVENT, -1, STARTER_CLASS),
		true
	)
	_validate_sample(&"CIRCUIT_STARTER_TRAFFIC", &"STANDARD", starter_traffic_sample)
	_print_sample(&"CIRCUIT_STARTER_TRAFFIC", &"STANDARD", starter_traffic_sample)
	_validate_starter_traffic(starter_sample, starter_traffic_sample)
	var flow_pressure_sample := _simulate_session(
		RaceEventCatalog.get_session_config(REPLAY_EVENT, -1, STARTER_CLASS),
		true,
		FLOW_SURGE_BENCHMARK_RATIO
	)
	_validate_sample(&"CIRCUIT_FLOW_SURGE", &"STANDARD", flow_pressure_sample)
	_print_sample(&"CIRCUIT_FLOW_SURGE", &"STANDARD", flow_pressure_sample)
	_validate_flow_surge_pressure(
		flow_pressure_sample,
		FLOW_SURGE_BENCHMARK_RATIO,
		FLOW_SURGE_PRESSURE_MIN_PLACE,
		FLOW_SURGE_PRESSURE_MAX_PLACE,
		&"STRONG"
	)
	var elite_flow_sample := _simulate_session(
		RaceEventCatalog.get_session_config(REPLAY_EVENT, -1, STARTER_CLASS),
		true,
		FLOW_SURGE_ELITE_RATIO
	)
	_validate_sample(&"CIRCUIT_FLOW_ELITE", &"STANDARD", elite_flow_sample)
	_print_sample(&"CIRCUIT_FLOW_ELITE", &"STANDARD", elite_flow_sample)
	_validate_flow_surge_pressure(
		elite_flow_sample,
		FLOW_SURGE_ELITE_RATIO,
		FLOW_SURGE_ELITE_MIN_PLACE,
		FLOW_SURGE_ELITE_MAX_PLACE,
		&"ELITE"
	)

	var upgraded_sample := _simulate_upgraded_build(REPLAY_EVENT)
	_validate_sample(&"CIRCUIT_UPGRADED", &"STANDARD", upgraded_sample)
	_print_sample(&"CIRCUIT_UPGRADED", &"STANDARD", upgraded_sample)
	_validate_upgraded_build(replay_reference, upgraded_sample)

	var defense_sample := _simulate_player_defense(REPLAY_EVENT)
	_validate_player_defense(defense_sample)

	_pack.stop_race()
	RaceEventCatalog.set_player_difficulty_mode(previous_mode)
	Profile.persistence_enabled = previous_persistence
	var passed := _failures.is_empty()
	print(
		"OPPONENT CHALLENGE PROBE: events=%d simulations=%d failures=%d passed=%s"
		% [audit_events.size(), _simulation_count, _failures.size(), str(passed)]
	)
	if passed:
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("OPPONENT CHALLENGE PROBE: " + failure)
	get_tree().quit(1)


func _simulate_event(event_id: StringName) -> Dictionary:
	return _simulate_session(RaceEventCatalog.get_session_config(event_id))


func _simulate_upgraded_build(event_id: StringName) -> Dictionary:
	var session := RaceEventCatalog.get_session_config(event_id)
	var build_snapshot := _create_realistic_upgraded_build_snapshot()
	var projection: Dictionary = MAIN_SCRIPT.resolve_opponent_build_match_projection(build_snapshot, UPGRADED_SETUP)
	var applied: bool = MAIN_SCRIPT.apply_career_opponent_build_match(session, build_snapshot, UPGRADED_SETUP)
	var sample := _simulate_session(session)
	sample[&"build_match_applied"] = applied
	sample[&"build_fixture_valid"] = bool(build_snapshot.get(&"fixture_valid", false))
	sample[&"build_id"] = StringName(build_snapshot.get(&"bike_id", &""))
	sample[&"build_signature"] = str(build_snapshot.get(&"signature", ""))
	sample[&"projected_performance_scale"] = float(projection.get(&"performance_scale", 1.0))
	sample[&"projected_match_scale"] = float(projection.get(&"match_scale", 1.0))
	sample[&"projected_setup_id"] = StringName(projection.get(&"setup_id", &""))
	sample[&"projected_setup_factor"] = float(projection.get(&"setup_factor", 0.0))
	sample[&"applied_setup_id"] = StringName(session.rules.get(&"opponent_build_setup_id", &""))
	sample[&"applied_setup_factor"] = float(session.rules.get(&"opponent_build_setup_factor", 0.0))
	return sample


func _create_realistic_upgraded_build_snapshot() -> Dictionary:
	var catalog := RacingBikeCatalog.create_default()
	var build := RacingBikeBuild.new()
	build.bike_id = UPGRADED_BUILD_ID
	var ecu_installed := build.install_part(catalog, &"RACE_ECU")
	var chassis_installed := build.install_part(catalog, &"LIGHT_CHASSIS")
	var stats := build.calculate_stats(catalog)
	return {
		&"bike_id": build.bike_id,
		&"stats": stats,
		&"build": build.to_dictionary(),
		&"signature": build.signature(),
		&"fixture_valid": ecu_installed and chassis_installed and not stats.is_empty(),
	}


func _simulate_player_defense(event_id: StringName) -> Dictionary:
	_simulation_count += 1
	var session := RaceEventCatalog.get_session_config(event_id)
	var route := CourseCatalog.get_world_riding_points(session.track_id)
	if route.size() < 2:
		return _invalid_result("%s defense route has fewer than two points" % String(session.track_id))
	_pack.configure(session.track_id, route, null, session)
	_pack.start_race()
	_pack.set_physics_process(false)
	var elapsed := 0.0
	while elapsed < DEFENSE_SETUP_SECONDS:
		elapsed += STEP
		_pack.simulate_competition_step(STEP, 0.0, 0.0, false)

	var defense_triggered := false
	var follow_through := 0
	var target_id: StringName = &""
	for _step: int in DEFENSE_MAX_STEPS:
		var target := _select_defense_target()
		if target.is_empty():
			break
		target_id = StringName(target.get(&"rider_id", &""))
		var target_progress := float(target.get(&"total_progress", 0.0))
		var target_speed := float(target.get(&"speed_mps", 0.0))
		# Place a materially faster player 4m behind an offset rider. Integration
		# advances the rider first, leaving a closing gap inside the 12m defense
		# sensor when the production traffic planner resolves this step.
		var player_progress := maxf(target_progress - 4.0, 0.0)
		var player_speed := maxf(target_speed + 4.0, 24.0)
		_pack.simulate_competition_step(STEP, player_speed, player_progress, true)
		var live_chaos := _pack.get_chaos_snapshot()
		if int(live_chaos.get(&"defensive_moves", 0)) > 0:
			defense_triggered = true
			follow_through += 1
			if follow_through >= DEFENSE_FOLLOW_THROUGH_STEPS:
				break
	var chaos := _pack.get_chaos_snapshot()
	return {
		&"valid": not target_id.is_empty(),
		&"error": "" if not target_id.is_empty() else "no offset defense target was available",
		&"target_id": target_id,
		&"defense_triggered": defense_triggered,
		&"defensive_moves": int(chaos.get(&"defensive_moves", 0)),
		&"defending": int(chaos.get(&"defending", 0)),
		&"defense_intent_seconds": float(chaos.get(&"defense_intent_seconds", 0.0)),
		&"lane_limit": float(chaos.get(&"lane_limit", 0.0)),
		&"peak_lane_span": float(chaos.get(&"peak_lane_span", 0.0)),
	}


func _select_defense_target() -> Dictionary:
	var selected: Dictionary = {}
	var selected_lane_error := INF
	for racer: Dictionary in _pack.get_racer_snapshots():
		if bool(racer.get(&"finished", false)):
			continue
		var lane_magnitude := absf(float(racer.get(&"lane", 0.0)))
		if lane_magnitude <= 0.65 or lane_magnitude >= 3.1:
			continue
		var lane_error := absf(lane_magnitude - 1.6)
		if lane_error < selected_lane_error:
			selected = racer
			selected_lane_error = lane_error
	return selected


func _simulate_session(
	session: RaceSessionConfig,
	resolve_traffic: bool = false,
	player_benchmark_ratio: float = 1.0
) -> Dictionary:
	_simulation_count += 1
	if session == null:
		return _invalid_result("session config is null")
	var route := CourseCatalog.get_world_riding_points(session.track_id)
	if route.size() < 2:
		return _invalid_result("%s route has fewer than two points" % String(session.track_id))
	_pack.configure(session.track_id, route, null, session)
	_pack.start_race()
	_pack.set_physics_process(false)

	var track_length := _pack.get_track_length()
	var total_distance := track_length * float(session.laps)
	var gold_usec := int(session.medal_times_usec.get(&"gold", 0))
	if track_length <= 0.0 or total_distance <= 0.0 or gold_usec <= 0:
		return _invalid_result(
			"%s has invalid distance/benchmark (track=%.2f total=%.2f gold=%d)"
			% [String(session.event_id), track_length, total_distance, gold_usec]
		)
	var gold_seconds := float(gold_usec) / 1_000_000.0
	var benchmark_speed := total_distance / gold_seconds
	var bounded_player_ratio := clampf(player_benchmark_ratio, 0.35, 1.5)
	var player_reference_seconds := gold_seconds * bounded_player_ratio
	var player_reference_speed := total_distance / player_reference_seconds
	var elapsed := 0.0
	while elapsed < MAX_SIMULATION_SECONDS and not _pack.all_riders_finished():
		elapsed += STEP
		var player_total := minf(player_reference_speed * elapsed, total_distance)
		# Most balance samples isolate rider pace from pair contacts. The explicit
		# starter-traffic case below runs this same path with full production traffic.
		_pack.simulate_competition_step(STEP, player_reference_speed, player_total, resolve_traffic)

	var finish_usecs: Array[int] = []
	var finished_statuses := 0
	for racer: Dictionary in _pack.get_racer_snapshots():
		var finish_usec := int(racer.get(&"finish_usec", -1))
		if finish_usec > 0:
			finish_usecs.append(finish_usec)
		if StringName(racer.get(&"status", &"RUNNING")) == &"FINISHED":
			finished_statuses += 1
	finish_usecs.sort()
	var finish_seconds: Array[float] = []
	var unique_finish_buckets: Dictionary = {}
	for finish_usec: int in finish_usecs:
		finish_seconds.append(float(finish_usec) / 1_000_000.0)
		unique_finish_buckets[finish_usec] = true
	var leader_seconds := INF
	var median_seconds := INF
	var tail_seconds := INF
	if not finish_seconds.is_empty():
		leader_seconds = finish_seconds[0]
		median_seconds = finish_seconds[floori(float(finish_seconds.size()) * 0.5)]
		tail_seconds = finish_seconds[-1]
	var chaos := _pack.get_chaos_snapshot()
	var tension := _pack.get_tension_snapshot()
	return {
		&"valid": true,
		&"error": "",
		&"event_id": session.event_id,
		&"difficulty": session.difficulty,
		&"bike_class": session.bike_class,
		&"gold_usec": gold_usec,
		&"gold_seconds": gold_seconds,
		&"benchmark_speed": benchmark_speed,
		&"player_benchmark_ratio": bounded_player_ratio,
		&"player_reference_seconds": player_reference_seconds,
		&"player_reference_speed": player_reference_speed,
		&"simulation_seconds": elapsed,
		&"resolve_traffic": resolve_traffic,
		&"timed_out": not _pack.all_riders_finished(),
		&"finished": finish_seconds.size(),
		&"finished_statuses": finished_statuses,
		&"expected": session.opponent_count,
		&"finish_usecs": finish_usecs,
		&"unique_finish_buckets": unique_finish_buckets.size(),
		&"leader_seconds": leader_seconds,
		&"median_seconds": median_seconds,
		&"tail_seconds": tail_seconds,
		&"field_spread_seconds": tail_seconds - leader_seconds if finish_seconds.size() >= 2 else 0.0,
		&"lane_changes": int(chaos.get(&"lane_changes", 0)),
		&"overtakes": int(chaos.get(&"field_overtakes", 0)),
		&"contacts": int(chaos.get(&"field_contacts", 0)),
		&"mistakes": int(chaos.get(&"mistakes", 0)),
		&"crashes": int(chaos.get(&"crashes", 0)),
		&"recoveries": int(chaos.get(&"recoveries", 0)),
		&"player_difficulty_mode": StringName(tension.get(&"player_difficulty_mode", &"LOCKED")),
		&"opponent_build_match_scale": float(tension.get(&"opponent_build_match_scale", 0.0)),
		&"field_chase_adjustment_mps": float(tension.get(&"field_chase_adjustment_mps", 0.0)),
	}


func _invalid_result(message: String) -> Dictionary:
	return {
		&"valid": false,
		&"error": message,
		&"bike_class": &"",
		&"gold_usec": 0,
		&"resolve_traffic": false,
		&"timed_out": true,
		&"finished": 0,
		&"finished_statuses": 0,
		&"expected": 0,
		&"finish_usecs": [],
		&"unique_finish_buckets": 0,
		&"leader_seconds": INF,
		&"median_seconds": INF,
		&"tail_seconds": INF,
		&"field_spread_seconds": 0.0,
		&"lane_changes": 0,
		&"overtakes": 0,
		&"contacts": 0,
		&"mistakes": 0,
		&"crashes": 0,
		&"recoveries": 0,
		&"player_difficulty_mode": &"LOCKED",
		&"opponent_build_match_scale": 0.0,
	}


func _validate_sample(event_id: StringName, mode: StringName, sample: Dictionary) -> void:
	var valid := bool(sample.get(&"valid", false))
	_check(valid, "%s %s simulation invalid: %s" % [event_id, mode, str(sample.get(&"error", "unknown error"))])
	if not valid:
		return
	var expected := int(sample.get(&"expected", -1))
	var finished := int(sample.get(&"finished", 0))
	var finished_statuses := int(sample.get(&"finished_statuses", 0))
	_check(not bool(sample.get(&"timed_out", true)), "%s %s exceeded the simulation budget" % [event_id, mode])
	_check(
		finished == expected and finished_statuses == expected,
		"%s %s did not produce a full FINISHED field (%d times, %d statuses, expected %d)"
		% [event_id, mode, finished, finished_statuses, expected]
	)
	var leader := float(sample.get(&"leader_seconds", INF))
	var median := float(sample.get(&"median_seconds", INF))
	var tail := float(sample.get(&"tail_seconds", INF))
	_check(
		is_finite(leader) and leader > 0.0 and leader <= median and median <= tail,
		"%s %s finish order is invalid (leader=%.2f median=%.2f tail=%.2f)"
		% [event_id, mode, leader, median, tail]
	)
	_check(
		StringName(sample.get(&"player_difficulty_mode", &"LOCKED")) == mode,
		"%s %s did not reach RacePack's mode contract (%s)"
		% [event_id, mode, str(sample.get(&"player_difficulty_mode", &"LOCKED"))]
	)

	var gold := maxf(float(sample.get(&"gold_seconds", 0.0)), 0.001)
	var windows := BENCHMARK_WINDOWS.get(mode, {}) as Dictionary
	_validate_window(event_id, mode, &"leader", leader / gold, windows)
	_validate_window(event_id, mode, &"median", median / gold, windows)
	var spread_ratio := float(sample.get(&"field_spread_seconds", 0.0)) / gold
	_check(
		spread_ratio >= MIN_FIELD_SPREAD_RATIO and spread_ratio <= MAX_FIELD_SPREAD_RATIO,
		"%s %s field spread ratio %.3f is outside [%.3f, %.3f]"
		% [event_id, mode, spread_ratio, MIN_FIELD_SPREAD_RATIO, MAX_FIELD_SPREAD_RATIO]
	)
	_check(
		int(sample.get(&"unique_finish_buckets", 0)) >= maxi(4, ceili(float(expected) * 0.35)),
		"%s %s field collapsed into too few finish buckets (%d/%d)"
		% [event_id, mode, int(sample.get(&"unique_finish_buckets", 0)), expected]
	)
	var lane_changes := int(sample.get(&"lane_changes", 0))
	var mistakes := int(sample.get(&"mistakes", 0))
	_check(
		lane_changes >= expected * MIN_LANE_CHANGES_PER_RIDER
		and lane_changes <= expected * MAX_LANE_CHANGES_PER_RIDER,
		"%s %s lane activity %d is outside [%d, %d]"
		% [event_id, mode, lane_changes, expected * MIN_LANE_CHANGES_PER_RIDER, expected * MAX_LANE_CHANGES_PER_RIDER]
	)
	_check(
		mistakes >= expected * MIN_MISTAKES_PER_RIDER
		and mistakes <= expected * MAX_MISTAKES_PER_RIDER,
		"%s %s mistake activity %d is outside [%d, %d]"
		% [event_id, mode, mistakes, expected * MIN_MISTAKES_PER_RIDER, expected * MAX_MISTAKES_PER_RIDER]
	)


func _validate_window(
	event_id: StringName,
	mode: StringName,
	metric: StringName,
	ratio: float,
	windows: Dictionary
) -> void:
	var minimum := float(windows.get(StringName("%s_min" % metric), -INF))
	var maximum := float(windows.get(StringName("%s_max" % metric), INF))
	_check(
		is_finite(ratio) and ratio >= minimum and ratio <= maximum,
		"%s %s %s/gold ratio %.3f is outside [%.3f, %.3f]"
		% [event_id, mode, metric, ratio, minimum, maximum]
	)


func _validate_event_separation(event_id: StringName, tiers: Dictionary) -> void:
	var relaxed := tiers.get(&"RELAXED", {}) as Dictionary
	var standard := tiers.get(&"STANDARD", {}) as Dictionary
	var expert := tiers.get(&"EXPERT", {}) as Dictionary
	if not bool(relaxed.get(&"valid", false)) or not bool(standard.get(&"valid", false)) or not bool(expert.get(&"valid", false)):
		return
	_check(
		int(relaxed.get(&"difficulty", -1)) < int(standard.get(&"difficulty", -1))
		and int(standard.get(&"difficulty", -1)) < int(expert.get(&"difficulty", -1)),
		"%s difficulty tiers are not strictly ordered" % event_id
	)
	for metric: StringName in [&"leader_seconds", &"median_seconds", &"tail_seconds"]:
		_validate_adjacent_gap(event_id, &"RELAXED_STANDARD", metric, relaxed, standard)
		_validate_adjacent_gap(event_id, &"STANDARD_EXPERT", metric, standard, expert)


func _validate_adjacent_gap(
	event_id: StringName,
	pair_name: StringName,
	metric: StringName,
	slower: Dictionary,
	faster: Dictionary
) -> void:
	var gold := maxf(float(slower.get(&"gold_seconds", 0.0)), 0.001)
	var separation := (
		float(slower.get(metric, 0.0)) - float(faster.get(metric, INF))
	) / gold
	_check(
		separation >= MIN_ADJACENT_SEPARATION_RATIO
		and separation <= MAX_ADJACENT_SEPARATION_RATIO,
		"%s %s %s separation %.3f is outside [%.3f, %.3f]"
		% [event_id, pair_name, metric, separation, MIN_ADJACENT_SEPARATION_RATIO, MAX_ADJACENT_SEPARATION_RATIO]
	)


func _validate_deterministic_replay(reference: Dictionary, replay: Dictionary) -> void:
	var deterministic := bool(reference.get(&"valid", false)) and bool(replay.get(&"valid", false))
	for key: StringName in [
		&"finish_usecs", &"finished_statuses", &"unique_finish_buckets",
		&"lane_changes", &"mistakes", &"crashes", &"difficulty",
		&"player_difficulty_mode", &"opponent_build_match_scale",
	]:
		var matches: bool = reference.get(key) == replay.get(key)
		deterministic = deterministic and matches
		_check(matches, "%s deterministic replay changed %s" % [REPLAY_EVENT, key])
	_check(deterministic, "%s deterministic replay was invalid" % REPLAY_EVENT)
	print(
		"OPPONENT CHALLENGE REPLAY: event=%s mode=STANDARD finish_signature=%s lane_changes=%d mistakes=%d passed=%s"
		% [
			REPLAY_EVENT, str(replay.get(&"finish_usecs", [])),
			int(replay.get(&"lane_changes", 0)), int(replay.get(&"mistakes", 0)),
			str(deterministic),
		]
	)


func _benchmark_finish_usec(sample: Dictionary, benchmark_ratio: float) -> int:
	var gold_usec := int(sample.get(&"gold_usec", 0))
	if gold_usec <= 0 or benchmark_ratio <= 0.0:
		return -1
	return roundi(float(gold_usec) * benchmark_ratio)


func _player_place_for_benchmark(sample: Dictionary, benchmark_ratio: float) -> int:
	return _player_place_from_opponent_finishes(
		sample.get(&"finish_usecs", []),
		_benchmark_finish_usec(sample, benchmark_ratio)
	)


func _player_place_from_opponent_finishes(
	opponent_finish_usecs: Variant,
	player_finish_usec: int
) -> int:
	if player_finish_usec <= 0 or not (opponent_finish_usecs is Array):
		return -1
	var placement := 1
	for raw_finish_usec: Variant in opponent_finish_usecs:
		var opponent_finish_usec := int(raw_finish_usec)
		if opponent_finish_usec <= 0:
			return -1
		# A benchmark player must be strictly quicker to take the place; an exact
		# tie is conservatively awarded to the recorded opponent in every scenario.
		if opponent_finish_usec <= player_finish_usec:
			placement += 1
	return placement


func _validate_starter_class(open_baseline: Dictionary, starter: Dictionary) -> void:
	var open_median := maxf(float(open_baseline.get(&"median_seconds", 0.0)), 0.001)
	var starter_median := float(starter.get(&"median_seconds", INF))
	var class_penalty := (starter_median - open_median) / open_median
	var gold := maxf(float(starter.get(&"gold_seconds", 0.0)), 0.001)
	var leader_ratio := float(starter.get(&"leader_seconds", INF)) / gold
	var median_ratio := starter_median / gold
	var class_valid := StringName(starter.get(&"bike_class", &"")) == STARTER_CLASS
	_check(class_valid, "starter outcome did not use %s: %s" % [STARTER_CLASS, str(starter)])
	_check(
		class_penalty >= MIN_STARTER_CLASS_PENALTY_RATIO
		and class_penalty <= MAX_STARTER_CLASS_PENALTY_RATIO,
		"starter-class median penalty %.3f is outside [%.3f, %.3f]"
		% [class_penalty, MIN_STARTER_CLASS_PENALTY_RATIO, MAX_STARTER_CLASS_PENALTY_RATIO]
	)
	print(
		"OPPONENT CHALLENGE STARTER: event=%s class=%s leader=%.2f(%.3fx gold) median=%.2f(%.3fx gold) open_penalty=%.3f passed=%s"
		% [
			REPLAY_EVENT, STARTER_CLASS, float(starter.get(&"leader_seconds", INF)), leader_ratio,
			starter_median, median_ratio, class_penalty,
			str(
				class_valid and class_penalty >= MIN_STARTER_CLASS_PENALTY_RATIO
				and class_penalty <= MAX_STARTER_CLASS_PENALTY_RATIO
			),
		]
	)


func _validate_starter_traffic(no_traffic: Dictionary, traffic: Dictionary) -> void:
	var expected := int(traffic.get(&"expected", 0))
	var contacts := int(traffic.get(&"contacts", 0))
	var crashes := int(traffic.get(&"crashes", 0))
	var recoveries := int(traffic.get(&"recoveries", 0))
	var overtakes := int(traffic.get(&"overtakes", 0))
	var baseline_median := maxf(float(no_traffic.get(&"median_seconds", 0.0)), 0.001)
	var traffic_median := float(traffic.get(&"median_seconds", INF))
	var median_slowdown := (traffic_median - baseline_median) / baseline_median
	var gold_place := _player_place_for_benchmark(traffic, GOLD_BENCHMARK_RATIO)
	var flow_benchmark_place := _player_place_for_benchmark(traffic, FLOW_SURGE_BENCHMARK_RATIO)
	var placement_valid := (
		gold_place == 12
		and flow_benchmark_place >= FLOW_SURGE_STATIC_MIN_PLACE
		and flow_benchmark_place <= FLOW_SURGE_STATIC_MAX_PLACE
	)
	var full_field := (
		int(traffic.get(&"finished", 0)) == expected
		and int(traffic.get(&"finished_statuses", 0)) == expected
		and not bool(traffic.get(&"timed_out", true))
	)
	var bounded_incidents := (
		contacts >= 1 and contacts <= expected * 30
		and crashes <= expected * 6
		and recoveries <= crashes
		and crashes - recoveries <= 2
	)
	_check(bool(traffic.get(&"resolve_traffic", false)), "starter traffic outcome did not enable production traffic")
	_check(StringName(traffic.get(&"bike_class", &"")) == STARTER_CLASS, "starter traffic outcome used the wrong bike class")
	_check(full_field, "starter traffic did not finish the full field: %s" % str(traffic))
	_check(overtakes >= 1, "starter traffic produced no field overtakes: %s" % str(traffic))
	_check(bounded_incidents, "starter traffic incidents were inactive or unbounded: %s" % str(traffic))
	_check(gold_place == 12, "LITE Standard gold benchmark placed P%d instead of P12" % gold_place)
	_check(
		flow_benchmark_place >= FLOW_SURGE_STATIC_MIN_PLACE
		and flow_benchmark_place <= FLOW_SURGE_STATIC_MAX_PLACE,
		"LITE Standard Flow benchmark %.3fx-gold placed P%d outside P%d-P%d"
		% [
			FLOW_SURGE_BENCHMARK_RATIO, flow_benchmark_place,
			FLOW_SURGE_STATIC_MIN_PLACE, FLOW_SURGE_STATIC_MAX_PLACE,
		]
	)
	_check(
		median_slowdown >= -0.15 and median_slowdown <= 0.30,
		"starter traffic median slowdown %.3f is outside [-0.150, 0.300]" % median_slowdown
	)
	print(
		"OPPONENT CHALLENGE STARTER TRAFFIC: median=%.2f baseline=%.2f slowdown=%+.3f gold=P%d flow=%.3fx/P%d overtakes=%d contacts=%d crashes=%d recoveries=%d passed=%s"
		% [
			traffic_median, baseline_median, median_slowdown, gold_place,
			FLOW_SURGE_BENCHMARK_RATIO, flow_benchmark_place, overtakes, contacts, crashes, recoveries,
			str(
				full_field and overtakes >= 1 and bounded_incidents and placement_valid
					and median_slowdown >= -0.15 and median_slowdown <= 0.30
			),
		]
	)


func _validate_flow_surge_pressure(
	sample: Dictionary,
	benchmark_ratio: float,
	minimum_place: int,
	maximum_place: int,
	label: StringName
) -> void:
	var player_finish_usec := roundi(float(sample.get(&"player_reference_seconds", 0.0)) * 1_000_000.0)
	var place := _player_place_from_opponent_finishes(sample.get(&"finish_usecs", []), player_finish_usec)
	var chase_adjustment := float(sample.get(&"field_chase_adjustment_mps", 0.0))
	var valid_place := place >= minimum_place and place <= maximum_place
	_check(
		is_equal_approx(float(sample.get(&"player_benchmark_ratio", 0.0)), benchmark_ratio),
		"Flow-pressure simulation did not use the requested %.3fx-gold player pace" % benchmark_ratio
	)
	_check(
		chase_adjustment >= 0.80,
		"Flow-pressure field chase reserve %.2f m/s was below 0.80 m/s" % chase_adjustment
	)
	_check(
		valid_place,
		"a sustained Flow benchmark at %.3fx gold placed P%d outside P%d-P%d"
		% [benchmark_ratio, place, minimum_place, maximum_place]
	)
	print(
		"OPPONENT CHALLENGE FLOW PRESSURE: tier=%s player=%.3fx/P%d chase=%.2fm/s leader=%.2f median=%.2f passed=%s"
		% [
			label, benchmark_ratio, place, chase_adjustment,
			float(sample.get(&"leader_seconds", INF)), float(sample.get(&"median_seconds", INF)),
			str(valid_place and chase_adjustment >= 0.80),
		]
	)


func _validate_upgraded_build(baseline: Dictionary, upgraded: Dictionary) -> void:
	var baseline_median := maxf(float(baseline.get(&"median_seconds", 0.0)), 0.001)
	var upgraded_median := float(upgraded.get(&"median_seconds", INF))
	var gain_ratio := (baseline_median - upgraded_median) / baseline_median
	var applied_scale := float(upgraded.get(&"opponent_build_match_scale", 0.0))
	var projected_scale := float(upgraded.get(&"projected_match_scale", 0.0))
	var performance_scale := float(upgraded.get(&"projected_performance_scale", 0.0))
	var gold_place := _player_place_for_benchmark(upgraded, GOLD_BENCHMARK_RATIO)
	var midpoint_place := _player_place_for_benchmark(upgraded, UPGRADED_MIDPOINT_RATIO)
	var elite_place := _player_place_for_benchmark(upgraded, UPGRADED_ELITE_RATIO)
	var placement_valid := (
		gold_place == 12
		and midpoint_place >= UPGRADED_MIDFIELD_MIN_PLACE
		and midpoint_place <= UPGRADED_MIDFIELD_MAX_PLACE
		and elite_place == 1
	)
	var projection_valid := (
		bool(upgraded.get(&"build_fixture_valid", false))
		and bool(upgraded.get(&"build_match_applied", false))
		and StringName(upgraded.get(&"build_id", &"")) == UPGRADED_BUILD_ID
		and performance_scale > projected_scale
		and projected_scale > 1.0
		and projected_scale <= 1.12
		and is_equal_approx(applied_scale, projected_scale)
		and StringName(upgraded.get(&"projected_setup_id", &"")) == UPGRADED_SETUP
		and StringName(upgraded.get(&"applied_setup_id", &"")) == UPGRADED_SETUP
		and is_equal_approx(float(upgraded.get(&"projected_setup_factor", 0.0)), UPGRADED_SETUP_FACTOR)
		and is_equal_approx(float(upgraded.get(&"applied_setup_factor", 0.0)), UPGRADED_SETUP_FACTOR)
	)
	_check(projection_valid, "upgraded build projection/application was invalid: %s" % str(upgraded))
	_check(gold_place == 12, "upgraded ATTACK gold benchmark placed P%d instead of P12" % gold_place)
	_check(
		midpoint_place >= UPGRADED_MIDFIELD_MIN_PLACE
		and midpoint_place <= UPGRADED_MIDFIELD_MAX_PLACE,
		"upgraded ATTACK fixed %.3fx-gold benchmark placed P%d outside P%d-P%d"
		% [
			UPGRADED_MIDPOINT_RATIO, midpoint_place,
			UPGRADED_MIDFIELD_MIN_PLACE, UPGRADED_MIDFIELD_MAX_PLACE,
		]
	)
	_check(
		elite_place == 1,
		"upgraded ATTACK elite %.3fx-gold benchmark placed P%d instead of P1"
		% [UPGRADED_ELITE_RATIO, elite_place]
	)
	_check(
		gain_ratio >= MIN_UPGRADED_BUILD_GAIN_RATIO and gain_ratio <= MAX_UPGRADED_BUILD_GAIN_RATIO,
		"upgraded build median gain %.3f is outside [%.3f, %.3f]"
		% [gain_ratio, MIN_UPGRADED_BUILD_GAIN_RATIO, MAX_UPGRADED_BUILD_GAIN_RATIO]
	)
	_check(
		baseline.get(&"finish_usecs", []) != upgraded.get(&"finish_usecs", []),
		"upgraded opponent build produced the baseline finish signature"
	)
	print(
		"OPPONENT CHALLENGE BUILD MATCH: event=%s build=%s setup=%s(%.2f) performance=%.3f match=%.3f baseline_median=%.2f upgraded_median=%.2f gain=%.3f placements=gold:P%d,midpoint:%.3fx/P%d,elite:%.3fx/P%d passed=%s"
		% [
			REPLAY_EVENT, str(upgraded.get(&"build_signature", "")), str(upgraded.get(&"applied_setup_id", &"")),
			float(upgraded.get(&"applied_setup_factor", 0.0)), performance_scale,
			applied_scale, baseline_median, upgraded_median, gain_ratio,
			gold_place, UPGRADED_MIDPOINT_RATIO, midpoint_place, UPGRADED_ELITE_RATIO, elite_place,
			str(
				projection_valid and placement_valid and gain_ratio >= MIN_UPGRADED_BUILD_GAIN_RATIO
				and gain_ratio <= MAX_UPGRADED_BUILD_GAIN_RATIO
			),
		]
	)


func _validate_player_defense(sample: Dictionary) -> void:
	var valid := bool(sample.get(&"valid", false))
	var defensive_moves := int(sample.get(&"defensive_moves", 0))
	var defending := int(sample.get(&"defending", 0))
	var intent_seconds := float(sample.get(&"defense_intent_seconds", 0.0))
	var lane_limit := float(sample.get(&"lane_limit", 0.0))
	var peak_lane_span := float(sample.get(&"peak_lane_span", INF))
	_check(valid, "player-defense scenario invalid: %s" % str(sample.get(&"error", "unknown error")))
	_check(
		bool(sample.get(&"defense_triggered", false)) and defensive_moves >= 1,
		"closing player did not trigger a defensive move: %s" % str(sample)
	)
	_check(defending >= 1, "defensive intent was not active after the triggered move: %s" % str(sample))
	_check(intent_seconds > 0.0, "defensive intent accumulated no activity time: %s" % str(sample))
	_check(
		lane_limit > 0.0 and peak_lane_span <= lane_limit * 2.0 + 0.05,
		"defensive move exceeded the lane envelope: %s" % str(sample)
	)
	print(
		"OPPONENT CHALLENGE DEFENSE: target=%s moves=%d defending=%d intent=%.2fs peak_span=%.2f/%.2f passed=%s"
		% [
			str(sample.get(&"target_id", &"")), defensive_moves, defending, intent_seconds,
			peak_lane_span, lane_limit * 2.0,
			str(
				valid and defensive_moves >= 1 and defending >= 1 and intent_seconds > 0.0
				and lane_limit > 0.0 and peak_lane_span <= lane_limit * 2.0 + 0.05
			),
		]
	)


func _print_sample(event_id: StringName, mode: StringName, sample: Dictionary) -> void:
	if not bool(sample.get(&"valid", false)):
		print("OPPONENT CHALLENGE SAMPLE: event=%s mode=%s invalid=%s" % [event_id, mode, str(sample.get(&"error", "unknown"))])
		return
	var gold := maxf(float(sample.get(&"gold_seconds", 0.0)), 0.001)
	print(
		"OPPONENT CHALLENGE SAMPLE: event=%s mode=%s class=%s traffic=%s finish=%d/%d leader=%.2f(%.3fx) median=%.2f(%.3fx) tail=%.2f spread=%.2f buckets=%d lanes=%d mistakes=%d"
		% [
			event_id, mode, str(sample.get(&"bike_class", &"")), str(sample.get(&"resolve_traffic", false)),
			int(sample.get(&"finished", 0)), int(sample.get(&"expected", 0)),
			float(sample.get(&"leader_seconds", INF)), float(sample.get(&"leader_seconds", INF)) / gold,
			float(sample.get(&"median_seconds", INF)), float(sample.get(&"median_seconds", INF)) / gold,
			float(sample.get(&"tail_seconds", INF)), float(sample.get(&"field_spread_seconds", 0.0)),
			int(sample.get(&"unique_finish_buckets", 0)), int(sample.get(&"lane_changes", 0)),
			int(sample.get(&"mistakes", 0)),
		]
	)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
