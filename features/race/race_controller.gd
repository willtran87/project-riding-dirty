extends Node3D
class_name RaceController
## Authoritative race-session lifecycle: staged starts, ordered checkpoints,
## multi-lap timing, live classification, integrity, flags, and full results.

const RacePackController = preload("res://features/race/race_pack.gd")
const PLAYER_RACE_METRICS_SCRIPT := preload("res://features/race/player_race_metrics.gd")
const GATE_LAUNCH_SCRIPT := preload("res://features/race/race_gate_launch.gd")
const REPUTATION_POLICY_SCRIPT := preload("res://features/race/race_reputation_policy.gd")
const RACECRAFT_RULES := preload("res://features/race/racecraft_rules.gd")
const SIMULATION_CLOCK_SCRIPT := preload("res://common/simulation_clock.gd")
const AIRTIME_REWARD_CAP := 600

signal time_updated(elapsed_usec: int, best_usec: int, checkpoint: int, total: int)
signal breakdown_ready(summary: String)
signal field_updated(position: int, total: int, gap_ahead: float, gap_behind: float)
signal race_moment(label: String, points: int, positive: bool)
signal phase_changed(phase: StringName)
signal lap_completed(lap: int, total_laps: int, lap_usec: int, best_lap_usec: int)
signal flag_changed(flag: StringName)
signal classification_updated(classification: Array[Dictionary])
signal integrity_updated(snapshot: Dictionary)
signal session_updated(snapshot: Dictionary)
signal results_ready(result: Dictionary)

enum State { WAITING, STAGING, COUNTDOWN, RACING, FINISHED, RESULTS }

var state: State = State.WAITING
var bike: DirtBikeController
var ghost: GhostController

var _gates: Array[Area3D] = []
var _gate_materials: Array[StandardMaterial3D] = []
var _expected_checkpoint: int = 0
var _elapsed_usec: int = 0
var _run_clock: SimulationClock = SIMULATION_CLOCK_SCRIPT.new()
var _countdown_remaining: float = 0.0
var _last_countdown_value: int = -1
var _spawn_transform: Transform3D = Transform3D.IDENTITY
var _checkpoint_data: Array[Dictionary] = []
var _gold_usec: int = 165_000_000
var _silver_usec: int = 220_000_000
var _bronze_usec: int = 300_000_000
var _activity_id: StringName = &"CIRCUIT"
var _competitive_signature_cache := ""
var _track_id: StringName = &"QUARRY"
var _authoritative_route := PackedVector3Array()
var _authoritative_surface_root: Node3D
var _racecraft_branch_routes: Dictionary = {}
var _gates_enabled: bool = false
var _split_times: Array[int] = []
var _rival_target_usec: int = 190_000_000
var _race_pack: RacePack
var _session_config: RaceSessionConfig = RaceEventCatalog.get_session_config(&"CIRCUIT")
var _current_lap: int = 1
var _laps_completed: int = 0
var _lap_start_usec: int = 0
var _lap_times_usec: Array[int] = []
var _best_lap_usec: int = -1
var _flag: StringName = &"NONE"
var _player_finished: bool = false
var _player_finish_usec: int = -1
var _player_elimination_lap: int = -1
var _player_penalty_usec: int = 0
var _finish_grace_remaining: float = 0.0
var _last_result: Dictionary = {}
var _race_attempt_context: Dictionary = {}
var _is_new_best: bool = false
var _field_sample_remaining: float = 0.0
var _field_position: int = -1
var _field_candidate: int = -1
var _field_candidate_time: float = 0.0
var _last_pack_near_misses: int = 0
var _field_moment_cooldown: float = 0.0
var _player_race_metrics: PlayerRaceMetrics = PLAYER_RACE_METRICS_SCRIPT.new()
var _gate_launch_evaluator: RefCounted = GATE_LAUNCH_SCRIPT.new()
var _gate_launch_staging_active: bool = false
var _integrity_tracker: RefCounted
var _integrity_snapshot: Dictionary = {
	&"valid": true, &"warning": &"", &"flag": &"NONE", &"penalty_usec": 0,
	&"reset_count": 0, &"off_course_count": 0, &"wrong_way_count": 0, &"cut_count": 0,
}
var _academy_reaction_seconds: float = -1.0
var _academy_launch_speed: float = 0.0
var _academy_clean_landings: int = 0
var _academy_controlled_jumps: int = 0
var _academy_cases: int = 0
var _academy_landing_error_total: float = 0.0
var _academy_landing_samples: int = 0
var _academy_clean_checkpoints: int = 0
var _academy_racecraft_metrics: Dictionary = {}
var _race_airtime_seconds: float = 0.0
var _race_clean_airtime_seconds: float = 0.0
var _active_session_surface: StringName = &"PACKED"


func _ready() -> void:
	_race_pack = RacePackController.new()
	_race_pack.name = "RacePack"
	add_child(_race_pack)
	_race_pack.rider_finished.connect(_on_pack_rider_finished)
	_race_pack.rider_eliminated.connect(_on_pack_rider_eliminated)
	_race_pack.holeshot_decided.connect(_on_holeshot_decided)
	_race_pack.player_overtook.connect(_on_player_overtook)
	_race_pack.player_was_overtaken.connect(_on_player_was_overtaken)
	_race_pack.hide_pack()
	_create_integrity_tracker()


func _physics_process(delta: float) -> void:
	match state:
		State.COUNTDOWN, State.STAGING:
			_countdown_remaining -= delta
			_update_gate_launch_staging(delta)
			var display_value := maxi(int(ceil(_countdown_remaining)), 0)
			if display_value != _last_countdown_value:
				_last_countdown_value = display_value
				EventBus.race_countdown_changed.emit(display_value)
			_emit_session_snapshot()
			if _countdown_remaining <= 0.0:
				_start_race()
		State.RACING:
			_elapsed_usec = _run_clock.advance(delta)
			_update_academy_metrics()
			_update_integrity(delta)
			_race_pack.set_player_race_state(_laps_completed, -1, _player_penalty_usec, &"RUNNING")
			time_updated.emit(_elapsed_usec, ghost.best_time_usec, _expected_checkpoint, _checkpoint_data.size())
			_update_field_feedback(delta)
		State.FINISHED:
			_finish_grace_remaining = maxf(_finish_grace_remaining - delta, 0.0)
			_update_field_feedback(delta)
			if _race_pack.all_riders_finished() or _finish_grace_remaining <= 0.0:
				_finalize_results()


func initialize(
		player_bike: DirtBikeController,
	ghost_controller: GhostController,
	initial_track_id: StringName = CourseCatalog.QUARRY_ID,
	authoritative_route: PackedVector3Array = PackedVector3Array(),
		authoritative_surface_root: Node3D = null
) -> void:
	if bike != null and bike != player_bike and bike.automatic_recovery_requested.is_connected(_on_bike_automatic_recovery_requested):
		bike.automatic_recovery_requested.disconnect(_on_bike_automatic_recovery_requested)
	if bike != null and bike != player_bike and bike.pack_contacted.is_connected(_on_player_pack_contacted):
		bike.pack_contacted.disconnect(_on_player_pack_contacted)
	if bike != null and bike != player_bike and bike.racecraft_event.is_connected(_on_bike_racecraft_event):
		bike.racecraft_event.disconnect(_on_bike_racecraft_event)
	bike = player_bike
	if not bike.landed.is_connected(_on_academy_bike_landed):
		bike.landed.connect(_on_academy_bike_landed)
	if not bike.trick_landed.is_connected(_on_bike_trick_landed):
		bike.trick_landed.connect(_on_bike_trick_landed)
	if not bike.automatic_recovery_requested.is_connected(_on_bike_automatic_recovery_requested):
		bike.automatic_recovery_requested.connect(_on_bike_automatic_recovery_requested)
	if not bike.pack_contacted.is_connected(_on_player_pack_contacted):
		bike.pack_contacted.connect(_on_player_pack_contacted)
	if not bike.racecraft_event.is_connected(_on_bike_racecraft_event):
		bike.racecraft_event.connect(_on_bike_racecraft_event)
	ghost = ghost_controller
	ghost.target = bike
	_race_pack.set_player(bike)
	configure_track(initial_track_id, authoritative_route, authoritative_surface_root)
	enter_waiting()


func configure_track(
	track_id: StringName,
	authoritative_route: PackedVector3Array = PackedVector3Array(),
	authoritative_surface_root: Node3D = null
) -> void:
	var event_id: StringName = &"MESA_MX" if track_id == CourseCatalog.MESA_MX_ID else (&"PINE_ENDURO" if track_id == CourseCatalog.PINE_ID else &"CIRCUIT")
	configure_session(RaceEventCatalog.get_session_config(event_id), authoritative_route, authoritative_surface_root)


func configure_session(
	config: RaceSessionConfig,
	authoritative_route: PackedVector3Array = PackedVector3Array(),
	authoritative_surface_root: Node3D = null
) -> void:
	if config == null:
		config = RaceEventCatalog.get_session_config(&"CIRCUIT")
	_session_config = RaceSessionConfig.from_dictionary(config.to_dictionary())
	_track_id = _session_config.track_id
	var supplied_route := authoritative_route.duplicate() if authoritative_route.size() >= 2 else CourseCatalog.get_world_riding_points(_track_id)
	_authoritative_route = RaceEventCatalog.prepare_route(_session_config, supplied_route)
	_authoritative_surface_root = authoritative_surface_root
	_cleanup_checkpoint_gates()
	_spawn_transform = CourseCatalog.get_spawn_transform(_track_id, _authoritative_route)
	_checkpoint_data = RaceEventCatalog.checkpoint_data(_session_config, _authoritative_route)
	var medal_times := _session_config.medal_times_usec
	if medal_times.is_empty():
		medal_times = CourseCatalog.get_medal_times_usec(_track_id)
	_gold_usec = int(medal_times.get(&"gold", 165_000_000))
	_silver_usec = int(medal_times.get(&"silver", 220_000_000))
	_bronze_usec = int(medal_times.get(&"bronze", 300_000_000))
	_activity_id = _session_config.event_id
	_competitive_signature_cache = ""
	_competitive_signature_cache = _build_competitive_signature()
	_active_session_surface = _surface_for_lap(1)
	_rival_target_usec = CourseCatalog.get_rival_target_usec(_track_id)
	_race_pack.configure(_track_id, _authoritative_route, _authoritative_surface_root, _session_config)
	_build_checkpoint_gates()
	_set_gates_visible(false)
	_configure_integrity_tracker()
	if ghost != null:
		var record_slot := CourseCatalog.get_record_slot(_track_id)
		var competition_id := StringName(_session_config.rules.get(&"competition_id", &""))
		if not competition_id.is_empty():
			record_slot = StringName("%s_R%d_L%d" % [String(competition_id), _session_config.route_version, _session_config.laps])
		elif _activity_id not in [&"CIRCUIT", &"PINE_ENDURO"]:
			record_slot = StringName("%s_R%d_L%d" % [String(_activity_id), _session_config.route_version, _session_config.laps])
		record_slot = StringName("%s_RC%d" % [String(record_slot), CompetitiveRunSignature.RACECRAFT_VERSION])
		ghost.set_record_slot(record_slot)
		# A full race already contains a physical rostered Rook. The translucent
		# target is reserved for solo sessions so the same rival never appears
		# twice; closed multi-lap targets now traverse every lap instead of one
		# stretched circuit.
		var rival_session_target_usec := _rival_target_usec
		if _track_id == CourseCatalog.MESA_MX_ID:
			var baseline_laps := maxi(RaceEventCatalog.get_session_config(&"MESA_MX").laps, 1)
			rival_session_target_usec = roundi(
				float(_rival_target_usec) * float(_session_config.laps) / float(baseline_laps)
			)
		ghost.configure_rival(
			_get_rival_path(),
			rival_session_target_usec,
			_session_config.laps,
			_track_id == CourseCatalog.MESA_MX_ID,
			_session_config.opponent_count == 0
		)
	_emit_session_snapshot()


func enter_waiting() -> void:
	state = State.WAITING
	_run_clock.reset()
	_elapsed_usec = 0
	_expected_checkpoint = 0
	_current_lap = 1
	_laps_completed = 0
	_lap_start_usec = 0
	_lap_times_usec.clear()
	_best_lap_usec = -1
	_player_finished = false
	_player_finish_usec = -1
	_player_elimination_lap = -1
	_player_penalty_usec = 0
	_last_result.clear()
	_split_times.clear()
	_set_flag(&"NONE")
	_reset_field_feedback()
	_reset_integrity_tracker()
	_reset_academy_metrics()
	_gate_launch_evaluator.call(&"reset")
	_gate_launch_staging_active = false
	if bike != null:
		_set_session_surface(_surface_for_lap(1), false)
		bike.set_controls_enabled(false)
		bike.set_motion_locked(true)
		bike.set_gate_staging_input_enabled(false)
		bike.respawn_at(_spawn_transform)
	if ghost != null:
		ghost.cancel_run()
	if _race_pack != null:
		_race_pack.hide_pack()
	_set_gates_visible(false)
	_update_gate_visuals()
	phase_changed.emit(&"WAITING")
	_emit_session_snapshot()


func reset_run() -> void:
	if bike == null or ghost == null:
		return
	# COUNTDOWN remains immediate for the established restart contract. The first
	# portion is presented as staging in the session snapshot while controls stay locked.
	state = State.COUNTDOWN
	_expected_checkpoint = 0
	_current_lap = 1
	_laps_completed = 0
	_lap_start_usec = 0
	_lap_times_usec.clear()
	_best_lap_usec = -1
	_player_finished = false
	_player_finish_usec = -1
	_player_elimination_lap = -1
	_player_penalty_usec = 0
	_finish_grace_remaining = 0.0
	_last_result.clear()
	_split_times.clear()
	_run_clock.reset()
	_elapsed_usec = 0
	_reset_field_feedback()
	_reset_integrity_tracker()
	_reset_academy_metrics()
	_gate_launch_evaluator.call(&"reset")
	_gate_launch_staging_active = false
	if _activity_id in RaceEventCatalog.RACE_EVENTS:
		_race_attempt_context = Profile.begin_race_run(
			_activity_id,
			_competitive_signature_cache,
			{
				&"academy_lesson_id": StringName(_session_config.rules.get(&"academy_lesson_id", &"")),
				&"challenge_id": StringName(_session_config.rules.get(&"challenge_id", &"")),
				&"competition_id": StringName(_session_config.rules.get(&"competition_id", &"")),
				&"weekend_id": StringName(_session_config.rules.get(&"weekend_id", &"")),
				&"weekend_phase": StringName(_session_config.rules.get(&"weekend_phase", &"")),
				&"weekend_managed": bool(_session_config.rules.get(&"weekend_managed", false)),
			}
		)
	else:
		# Synthetic controller probes may use isolated event IDs, but their results
		# are intentionally untrusted by Profile and can never settle progression.
		_race_attempt_context = {
			&"accepted": false,
			&"reason": &"UNREGISTERED_EVENT",
			&"run_id": "untrusted-%s-%d" % [String(_activity_id).to_lower(), Time.get_ticks_usec()],
		}
	if _activity_id in RaceEventCatalog.RACE_EVENTS and not bool(_race_attempt_context.get(&"accepted", false)):
		push_error("Race run authority rejected %s: %s" % [
			String(_activity_id), String(_race_attempt_context.get(&"reason", &"UNKNOWN"))
		])
	_countdown_remaining = _session_config.countdown_seconds
	_last_countdown_value = -1
	_set_flag(&"YELLOW")
	bike.set_controls_enabled(false)
	bike.set_motion_locked(true)
	bike.set_gate_staging_input_enabled(false)
	_set_session_surface(_surface_for_lap(1), false)
	bike.respawn_at(_spawn_transform)
	ghost.cancel_run()
	_race_pack.reset_grid()
	_set_gates_visible(true)
	_update_gate_visuals()
	EventBus.race_reset.emit()
	phase_changed.emit(&"STAGING")
	time_updated.emit(0, ghost.best_time_usec, 0, _checkpoint_data.size())
	_emit_classification()
	_emit_session_snapshot()


func request_player_reset() -> bool:
	if bike == null:
		return false
	# The finish line freezes competitive evidence. A reset button pressed while
	# the field completes cannot alter the official result or PB eligibility.
	if state in [State.FINISHED, State.RESULTS]:
		return false
	_apply_player_recovery(&"MANUAL_RESET")
	return true


func _on_bike_automatic_recovery_requested(reason: StringName) -> void:
	# Outside a live race the bike observes that no respawn occurred during this
	# synchronous callback and performs its own penalty-free safe recovery.
	if state != State.RACING:
		return
	_apply_player_recovery(reason if not reason.is_empty() else &"AUTO_RECOVERY")


func _apply_player_recovery(reason: StringName) -> void:
	if bike == null:
		return
	var race_active := state == State.RACING
	var rejoin := _spawn_transform
	var incident_penalty_usec := _session_config.reset_penalty_usec if race_active else 0
	if _integrity_tracker != null and _integrity_tracker.has_method(&"request_reset"):
		_integrity_tracker.call(&"request_reset", reason, race_active)
		var reset_data: Dictionary = _integrity_tracker.call(&"consume_reset_request") as Dictionary
		var candidate: Variant = reset_data.get(&"transform", _spawn_transform)
		if candidate is Transform3D:
			rejoin = candidate
		incident_penalty_usec = int(reset_data.get(&"penalty_applied_usec", incident_penalty_usec))
		if _integrity_tracker.has_method(&"get_snapshot"):
			_integrity_snapshot = _integrity_tracker.call(&"get_snapshot") as Dictionary
		_player_penalty_usec = maxi(_player_penalty_usec, int(_integrity_snapshot.get(&"penalty_usec", 0)))
	elif race_active:
		_player_penalty_usec += _session_config.reset_penalty_usec
		_record_fallback_recovery(reason, _session_config.reset_penalty_usec)
	bike.respawn_at(rejoin)
	if _race_pack != null:
		_race_pack.set_contact_immunity(1.5)
		_race_pack.resync_player_pass_tracking()
	integrity_updated.emit(_integrity_snapshot.duplicate(true))
	if race_active:
		_player_race_metrics.record_recovery(reason)
		_emit_recovery_feedback(reason, incident_penalty_usec)
	_emit_session_snapshot()


func _emit_recovery_feedback(reason: StringName, incident_penalty_usec: int) -> void:
	if _session_config.format == &"ACADEMY":
		var incidents := _integrity_snapshot.get(&"incidents", {}) as Dictionary
		var reset_count := maxi(int(incidents.get(&"resets_consumed", 0)), 1)
		var reset_limit := _academy_reset_objective_limit()
		var recovery_kind := "SAFE REJOIN" if reason == &"MANUAL_RESET" else "AUTO RECOVERY"
		var label := "COACH  //  %s  //  KEEP GOING" % recovery_kind
		if reset_limit > 0:
			label = "COACH  //  %s  //  RESET %d / %d  //  KEEP GOING" % [
				recovery_kind, reset_count, reset_limit,
			]
		race_moment.emit(label, 0, true)
		return
	var recovery_label := "SAFE REJOIN" if reason == &"MANUAL_RESET" else "AUTO RECOVERY"
	race_moment.emit(
		"%s  //  +%.1fs" % [recovery_label, float(incident_penalty_usec) / 1_000_000.0],
		0,
		false
	)


func _academy_reset_objective_limit() -> int:
	for objective: Dictionary in _session_config.rules.get(&"academy_objectives", []) as Array:
		if StringName(objective.get(&"metric", &"")) == &"resets":
			return maxi(roundi(float(objective.get(&"bronze", 0.0))), 0)
	return 0


func _record_fallback_recovery(reason: StringName, penalty_usec: int) -> void:
	var incidents := (_integrity_snapshot.get(&"incidents", {}) as Dictionary).duplicate(true)
	incidents[&"reset_requests"] = int(incidents.get(&"reset_requests", 0)) + 1
	incidents[&"resets_consumed"] = int(incidents.get(&"resets_consumed", 0)) + 1
	if reason == &"MANUAL_RESET":
		incidents[&"manual_resets"] = int(incidents.get(&"manual_resets", 0)) + 1
	var penalties := (_integrity_snapshot.get(&"penalties", {}) as Dictionary).duplicate(true)
	penalties[reason] = int(penalties.get(reason, 0)) + maxi(penalty_usec, 0)
	_integrity_snapshot[&"incidents"] = incidents
	_integrity_snapshot[&"penalties"] = penalties
	_integrity_snapshot[&"penalty_usec"] = _player_penalty_usec
	_integrity_snapshot[&"total_penalty_usec"] = _player_penalty_usec


func get_expected_checkpoint() -> int:
	return _expected_checkpoint


func get_checkpoint_positions() -> Array[Vector3]:
	var positions: Array[Vector3] = []
	for checkpoint: Dictionary in _checkpoint_data:
		positions.append(checkpoint.get(&"position", Vector3.ZERO))
	return positions


func get_spawn_transform() -> Transform3D:
	return _spawn_transform


func get_authoritative_route_points() -> PackedVector3Array:
	return _authoritative_route.duplicate()


func get_pack_authoritative_route_points() -> PackedVector3Array:
	return _race_pack.get_authoritative_route_points() if _race_pack != null else PackedVector3Array()


func get_breakdown_preview() -> String:
	return _build_breakdown()


func get_pack_pace_snapshot() -> Dictionary:
	return _race_pack.get_pace_snapshot() if _race_pack != null else {}


func get_pack_chaos_snapshot() -> Dictionary:
	return _race_pack.get_chaos_snapshot() if _race_pack != null else {}


func get_pack_player_interaction_snapshot() -> Dictionary:
	return _race_pack.get_player_interaction_snapshot() if _race_pack != null else {}


func get_player_race_metrics_snapshot() -> Dictionary:
	return _player_race_metrics.get_snapshot()


func get_gate_launch_snapshot() -> Dictionary:
	return _gate_launch_evaluator.call(&"get_snapshot") as Dictionary


func get_elimination_snapshot() -> Dictionary:
	return _race_pack.get_elimination_snapshot() if _race_pack != null else {}


func get_classification_snapshot() -> Array[Dictionary]:
	var classification := _race_pack.get_classification_snapshot() if _race_pack != null else [] as Array[Dictionary]
	var player_metrics := _player_race_metrics.get_snapshot()
	for index: int in classification.size():
		var racer: Dictionary = classification[index]
		if bool(racer.get(&"is_player", false)):
			racer[&"best_lap_usec"] = _best_lap_usec
			racer[&"last_lap_usec"] = _lap_times_usec.back() if not _lap_times_usec.is_empty() else -1
			racer[&"lap_times_usec"] = _lap_times_usec.duplicate()
			racer[&"penalty_usec"] = _player_penalty_usec
			racer[&"overtakes"] = int(player_metrics.get(&"overtakes", 0))
			racer[&"contacts"] = int(player_metrics.get(&"contacts", 0))
			racer[&"crashes"] = int(player_metrics.get(&"crashes", 0))
			racer[&"recoveries"] = int(player_metrics.get(&"recoveries", 0))
			classification[index] = racer
	return classification


func get_session_config() -> RaceSessionConfig:
	return RaceSessionConfig.from_dictionary(_session_config.to_dictionary())


func get_session_snapshot() -> Dictionary:
	var pace := get_pack_pace_snapshot()
	var presentation_phase := _phase_name()
	return {
		&"state": state,
		&"phase": presentation_phase,
		&"event_id": _activity_id,
		&"challenge_id": str(_session_config.rules.get(&"challenge_id", "")),
		&"competition_id": StringName(_session_config.rules.get(&"competition_id", &"")),
		&"challenge_kind": StringName(_session_config.rules.get(&"challenge_kind", &"")),
		&"competitive_signature": _competitive_signature_cache,
		&"track_id": _track_id,
		&"route_version": _session_config.route_version,
		&"reverse_route": _session_config.reverse_route,
		&"display_name": _session_config.display_name,
		&"format": _session_config.format,
		&"session_type": _session_config.session_type,
		&"weather": _session_config.weather,
		&"surface": _active_session_surface,
		&"medal_times_usec": {
			&"gold": _gold_usec,
			&"silver": _silver_usec,
			&"bronze": _bronze_usec,
		},
		&"elapsed_usec": _elapsed_usec,
		&"countdown": maxf(_countdown_remaining, 0.0),
		&"current_lap": _current_lap,
		&"laps_completed": _laps_completed,
		&"total_laps": _session_config.laps,
		&"current_checkpoint": _expected_checkpoint,
		&"checkpoint_count": _checkpoint_data.size(),
		&"position": int(pace.get(&"field_position", 1)),
		&"field_size": int(pace.get(&"field_size", _session_config.field_size)),
		&"gap_ahead": float(pace.get(&"gap_ahead", -1.0)),
		&"gap_behind": float(pace.get(&"gap_behind", -1.0)),
		&"flag": _flag,
		&"penalty_usec": _player_penalty_usec,
		&"best_lap_usec": _best_lap_usec,
		&"lap_times_usec": _lap_times_usec.duplicate(),
		&"holeshot_rider_id": _race_pack.get_holeshot_rider_id() if _race_pack != null else &"",
		&"elimination": get_elimination_snapshot(),
		&"classification": get_classification_snapshot(),
		&"integrity": _integrity_snapshot.duplicate(true),
		&"player_metrics": _player_race_metrics.get_snapshot(),
		&"gate_launch": get_gate_launch_snapshot(),
		&"racecraft": bike.get_racecraft_snapshot() if bike != null else {},
	}


func get_results_preview() -> Dictionary:
	return _last_result.duplicate(true)


func get_spectator_targets() -> Array[Node3D]:
	var targets: Array[Node3D] = []
	if is_instance_valid(bike):
		targets.append(bike)
	if _race_pack != null:
		targets.append_array(_race_pack.get_rider_roots())
	return targets


func _update_gate_launch_staging(delta: float) -> void:
	if bike == null:
		return
	# The session's opening staging beat presents the grid. The remaining window
	# accepts semantic throttle/brake input, while DirtBikeController stays frozen.
	var final_countdown_window := clampf(
		_session_config.countdown_seconds - _session_config.staging_seconds,
		minf(_session_config.countdown_seconds, 0.75),
		_session_config.countdown_seconds
	)
	var should_accept_input := _countdown_remaining <= final_countdown_window + 0.0001
	if should_accept_input != _gate_launch_staging_active:
		_gate_launch_staging_active = should_accept_input
		bike.set_gate_staging_input_enabled(should_accept_input)
	if not should_accept_input:
		return
	var staging_input := bike.get_gate_staging_input_snapshot()
	_gate_launch_evaluator.call(
		&"sample",
		delta,
		maxf(_countdown_remaining, 0.0),
		float(staging_input.get(&"throttle", 0.0)),
		float(staging_input.get(&"brake", 0.0))
	)


func _start_race() -> void:
	var gate_launch := _gate_launch_evaluator.call(&"finalize") as Dictionary
	_gate_launch_staging_active = false
	bike.set_gate_staging_input_enabled(false)
	state = State.RACING
	_run_clock.reset()
	_elapsed_usec = 0
	_lap_start_usec = 0
	bike.set_motion_locked(false)
	bike.set_controls_enabled(true)
	bike.apply_gate_launch_drive(float(gate_launch.get(&"drive_multiplier", 1.0)))
	ghost.start_run()
	_race_pack.start_race()
	_seed_field_feedback()
	_set_flag(&"GREEN")
	phase_changed.emit(&"RACING")
	EventBus.activity_started.emit(_activity_id)
	EventBus.race_started.emit()
	_emit_session_snapshot()


func _begin_player_finish() -> void:
	if state != State.RACING:
		return
	# A synthetic/test-authority finish can legally emit every ordered gate in the
	# same physics frame as green. Keep the result nonzero and settlement-valid
	# using one simulation tick instead of leaking wall-clock scheduling into it.
	if _elapsed_usec <= 0:
		_elapsed_usec = _run_clock.advance(maxf(get_physics_process_delta_time(), 1.0 / 120.0))
	_player_finished = true
	_player_finish_usec = _elapsed_usec
	state = State.FINISHED
	bike.set_gate_staging_input_enabled(false)
	bike.set_controls_enabled(false)
	var finish_validity := _evaluate_finish_validity()
	var finish_record_eligible := bool(finish_validity.get(&"valid", false)) and _player_penalty_usec == 0
	_is_new_best = finish_record_eligible and (ghost.best_time_usec < 0 or _elapsed_usec < ghost.best_time_usec)
	var effective_time := _elapsed_usec + _player_penalty_usec
	var medal := _medal_for_time(effective_time)
	ghost.finish_run(_elapsed_usec, _is_new_best)
	_race_pack.record_player_finish(_elapsed_usec, _player_penalty_usec)
	_finish_grace_remaining = _session_config.finish_grace_seconds
	_set_flag(&"CHECKERED")
	phase_changed.emit(&"FINISHING")
	# Preserve the immediate finish contract for audio, progression and replay UI.
	EventBus.race_finished.emit(effective_time, medal, _is_new_best)
	breakdown_ready.emit(_build_breakdown())
	time_updated.emit(_elapsed_usec, ghost.best_time_usec, _checkpoint_data.size(), _checkpoint_data.size())
	_emit_classification()
	_emit_session_snapshot()
	if _race_pack.all_riders_finished() or _finish_grace_remaining <= 0.0:
		_finalize_results()


func _finalize_results(classify_survivors: bool = false) -> void:
	if state not in [State.FINISHED, State.RACING]:
		return
	if classify_survivors:
		_race_pack.mark_running_classified()
	else:
		_race_pack.mark_unfinished_dnf()
	_race_pack.stop_race()
	state = State.RESULTS
	_last_result = _build_race_result().to_dictionary()
	phase_changed.emit(&"RESULTS")
	classification_updated.emit(_last_result.get(&"classification", []) as Array[Dictionary])
	var emitted_result := _last_result.duplicate(true)
	results_ready.emit(emitted_result)
	_last_result = emitted_result.duplicate(true)
	if EventBus.has_signal(&"race_results_ready"):
		EventBus.emit_signal(&"race_results_ready", emitted_result.duplicate(true))
	_emit_session_snapshot()


func _complete_player_lap() -> void:
	var lap_usec := _elapsed_usec - _lap_start_usec
	_lap_start_usec = _elapsed_usec
	_lap_times_usec.append(lap_usec)
	_best_lap_usec = lap_usec if _best_lap_usec < 0 else mini(_best_lap_usec, lap_usec)
	_laps_completed += 1
	lap_completed.emit(_laps_completed, _session_config.laps, lap_usec, _best_lap_usec)
	if _laps_completed >= _session_config.laps:
		_current_lap = _session_config.laps
		_begin_player_finish()
		return
	_current_lap = _laps_completed + 1
	_set_session_surface(_surface_for_lap(_current_lap), true)
	_expected_checkpoint = 0
	_set_flag(&"WHITE" if _current_lap == _session_config.laps else &"GREEN")
	_set_gates_visible(true)
	_update_gate_visuals()
	race_moment.emit(
		"WHITE FLAG  //  FINAL LAP" if _flag == &"WHITE" else "LAP %d / %d" % [_current_lap, _session_config.laps],
		200,
		true
	)
	_race_pack.set_player_race_state(_laps_completed, -1, _player_penalty_usec, &"RUNNING")
	_emit_session_snapshot()


func _reset_field_feedback() -> void:
	_field_sample_remaining = 0.0
	_field_position = -1
	_field_candidate = -1
	_field_candidate_time = 0.0
	_last_pack_near_misses = 0
	_field_moment_cooldown = 0.0
	_player_race_metrics.reset()


func _seed_field_feedback() -> void:
	var pace := get_pack_pace_snapshot()
	_field_position = int(pace.get(&"field_position", 1))
	_field_candidate = _field_position
	_player_race_metrics.observe_position(_field_position)
	field_updated.emit(
		_field_position,
		int(pace.get(&"field_size", 1)),
		float(pace.get(&"gap_ahead", -1.0)),
		float(pace.get(&"gap_behind", -1.0))
	)
	_last_pack_near_misses = int(get_pack_player_interaction_snapshot().get(&"near_misses", 0))
	_emit_classification()


func _update_field_feedback(delta: float) -> void:
	_field_moment_cooldown = maxf(_field_moment_cooldown - delta, 0.0)
	_field_sample_remaining -= delta
	if _field_sample_remaining > 0.0:
		return
	var sample_step := 0.12
	_field_sample_remaining = sample_step
	var pace := get_pack_pace_snapshot()
	var sampled_position := int(pace.get(&"field_position", maxi(_field_position, 1)))
	var total := int(pace.get(&"field_size", 1))
	if sampled_position != _field_candidate:
		_field_candidate = sampled_position
		_field_candidate_time = 0.0
	else:
		_field_candidate_time += sample_step
	if _field_candidate_time >= 0.24 and sampled_position != _field_position:
		var previous_position := _field_position
		_field_position = sampled_position
		if state == State.RACING:
			_player_race_metrics.observe_position(_field_position)
		if _elapsed_usec >= 3_500_000 and previous_position > 0 and _field_moment_cooldown <= 0.0:
			var places_changed := absi(previous_position - _field_position)
			if _field_position < previous_position:
				race_moment.emit("OVERTAKE  //  P%d  //  +%d" % [_field_position, 180 * places_changed], 180 * places_changed, true)
				_field_moment_cooldown = 0.75
			else:
				race_moment.emit("POSITION LOST  //  P%d" % _field_position, 0, false)
				_field_moment_cooldown = 0.6
	field_updated.emit(maxi(_field_position, 1), total, float(pace.get(&"gap_ahead", -1.0)), float(pace.get(&"gap_behind", -1.0)))
	var near_misses := int(get_pack_player_interaction_snapshot().get(&"near_misses", 0))
	if near_misses > _last_pack_near_misses and _elapsed_usec >= 3_500_000 and _field_moment_cooldown <= 0.0:
		var new_misses := near_misses - _last_pack_near_misses
		race_moment.emit("BAR-TO-BAR  //  NEAR MISS  //  +%d" % (260 * new_misses), 260 * new_misses, true)
		_field_moment_cooldown = 0.75
	_last_pack_near_misses = near_misses
	_emit_classification()
	_emit_session_snapshot()


func _on_player_pack_contacted(_intensity: float) -> void:
	if state == State.RACING:
		_player_race_metrics.record_contact()


func _on_player_overtook(_rider_id: StringName) -> void:
	if state == State.RACING:
		_player_race_metrics.record_overtake()
		if bike != null:
			var racecraft := bike.get_racecraft_snapshot()
			var draft_strength := maxf(
				float(racecraft.get(&"draft_strength", 0.0)),
				float(racecraft.get(&"recent_draft_strength", 0.0))
			)
			var draft_target := StringName(racecraft.get(&"recent_draft_target", &""))
			if draft_strength >= 0.28 and (draft_target.is_empty() or draft_target == _rider_id):
				bike.register_racecraft_success(&"DRAFT_SLINGSHOT", {
					&"rider_id": _rider_id,
					&"draft_strength": draft_strength,
				})
				race_moment.emit("DRAFT SLINGSHOT  //  CLEAN PASS  //  +260", 260, true)


func _on_player_was_overtaken(_rider_id: StringName) -> void:
	if state == State.RACING:
		_player_race_metrics.record_position_lost()


func _on_gate_entered(body: Node3D, checkpoint_index: int) -> void:
	if state != State.RACING or body != bike or checkpoint_index != _expected_checkpoint:
		return
	_expected_checkpoint += 1
	_split_times.append(_elapsed_usec)
	if StringName(_integrity_snapshot.get(&"warning", &"")) in [&"", &"NONE", &"CLEAR"]:
		_academy_clean_checkpoints += 1
	EventBus.checkpoint_passed.emit(checkpoint_index, _checkpoint_data.size(), _elapsed_usec)
	_update_gate_visuals()
	if _expected_checkpoint >= _checkpoint_data.size():
		_complete_player_lap()


func _on_pack_rider_finished(_rider_id: StringName, _finish_usec: int) -> void:
	_emit_classification()


func _on_pack_rider_eliminated(rider_id: StringName, elimination_lap: int) -> void:
	var player_eliminated := rider_id == &"PLAYER"
	var display_name := "YOU"
	if not player_eliminated:
		display_name = String(rider_id).replace("_", " ")
		for racer: Dictionary in _race_pack.get_classification_snapshot(false):
			if StringName(racer.get(&"rider_id", &"")) == rider_id:
				display_name = str(racer.get(&"display_name", display_name))
				break
	race_moment.emit(
		"%s  //  ELIMINATED ON LAP %d" % [display_name.to_upper(), elimination_lap],
		0,
		not player_eliminated
	)
	_emit_classification()
	_emit_session_snapshot()
	if not player_eliminated or state != State.RACING:
		return

	# Elimination is a legitimate loss, not a finish or an invalid run. Cancel PB
	# capture, lock the bike, and classify the remaining field before results.
	_player_finished = false
	_player_finish_usec = -1
	_player_elimination_lap = elimination_lap
	_is_new_best = false
	state = State.FINISHED
	bike.set_gate_staging_input_enabled(false)
	bike.set_controls_enabled(false)
	bike.set_motion_locked(true)
	ghost.cancel_run()
	_set_gates_visible(false)
	_set_flag(&"CHECKERED")
	phase_changed.emit(&"FINISHING")
	time_updated.emit(_elapsed_usec, ghost.best_time_usec, _expected_checkpoint, _checkpoint_data.size())
	_finalize_results(true)


func _on_holeshot_decided(rider_id: StringName) -> void:
	var label := "HOLESHOT  //  +350" if rider_id == &"PLAYER" else "%s TAKES THE HOLESHOT" % String(rider_id)
	race_moment.emit(label, 350 if rider_id == &"PLAYER" else 0, rider_id == &"PLAYER")
	_emit_session_snapshot()


func _build_checkpoint_gates() -> void:
	var road_width := CourseCatalog.get_track_width(_track_id)
	var gate_half_width := road_width * 0.5 + 0.6
	var gate_span := gate_half_width * 2.0
	for index: int in _checkpoint_data.size():
		var gate_data := _checkpoint_data[index]
		var area := Area3D.new()
		area.name = "Checkpoint%02d" % index
		area.collision_layer = 0
		area.collision_mask = 1
		area.monitoring = true
		area.position = gate_data.get(&"position", Vector3.ZERO)
		area.rotation.y = float(gate_data.get(&"yaw", 0.0))
		add_child(area)
		var shape := BoxShape3D.new()
		shape.size = Vector3(gate_span, 10.0, 1.2)
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.position.y = 2.5
		area.add_child(collision)
		area.body_entered.connect(_on_gate_entered.bind(index))
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.emission_enabled = true
		_gate_materials.append(material)
		# Keep the race markers above the rider's sightline.  The old crossbar
		# was centred at two metres, so the closed-loop finish gate filled the
		# chase camera and looked like a solid obstacle even though its collision
		# shape was only a checkpoint trigger.
		_add_gate_box(area, Vector3(0.28, 5.4, 0.28), Vector3(-gate_half_width, 2.7, 0.0), material)
		_add_gate_box(area, Vector3(0.28, 5.4, 0.28), Vector3(gate_half_width, 2.7, 0.0), material)
		_add_gate_box(area, Vector3(gate_span, 0.34, 0.34), Vector3(0.0, 5.22, 0.0), material)
		var label := Label3D.new()
		label.text = "FINISH" if index == _checkpoint_data.size() - 1 else "%02d" % (index + 1)
		label.position = Vector3(0.0, 5.72, 0.0)
		label.font_size = 42
		label.outline_size = 10
		label.modulate = Color("f7e5b2")
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		area.add_child(label)
		_gates.append(area)
	_update_gate_visuals()


func _cleanup_checkpoint_gates() -> void:
	for gate: Area3D in _gates:
		if is_instance_valid(gate):
			remove_child(gate)
			gate.queue_free()
	_gates.clear()
	_gate_materials.clear()


func _add_gate_box(parent: Node3D, size: Vector3, position: Vector3, material: StandardMaterial3D) -> void:
	var box := BoxMesh.new()
	box.size = size
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = box
	mesh_instance.position = position
	mesh_instance.material_override = material
	parent.add_child(mesh_instance)


func _update_gate_visuals() -> void:
	for index: int in _gate_materials.size():
		var material := _gate_materials[index]
		var is_active := index == _expected_checkpoint and state not in [State.FINISHED, State.RESULTS]
		var is_passed := index < _expected_checkpoint
		var gate := _gates[index]
		# Red Mesa closes beside its final checkpoint.  Do not advertise that
		# finish structure at the start of every lap; reveal it only when it is
		# the next gate so the route remains visually unambiguous.
		var is_waiting_closed_loop_finish := (
			_track_id == CourseCatalog.MESA_MX_ID
			and index == _gate_materials.size() - 1
			and not is_active
		)
		gate.visible = _gates_enabled and not is_passed and not is_waiting_closed_loop_finish
		gate.set_deferred(&"monitoring", _gates_enabled and not is_passed)
		var color := Color("ffb52d") if is_active else Color("30404a")
		if is_passed:
			color = Color("42d39d")
		material.albedo_color = color
		material.emission = color
		material.emission_energy_multiplier = 2.7 if is_active else 0.45


func _set_gates_visible(visible_value: bool) -> void:
	_gates_enabled = visible_value
	_update_gate_visuals()


func _set_flag(new_flag: StringName) -> void:
	if _flag == new_flag:
		return
	_flag = new_flag
	flag_changed.emit(_flag)


func _medal_for_time(time_usec: int) -> StringName:
	if time_usec <= _gold_usec:
		return &"GOLD"
	if time_usec <= _silver_usec:
		return &"SILVER"
	if time_usec <= _bronze_usec:
		return &"BRONZE"
	return &"FINISHER"


func _get_rival_path() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for course_point: Vector3 in _authoritative_route:
		points.append(course_point)
	return points


func _build_breakdown() -> String:
	if _split_times.is_empty():
		return "RUN READOUT  //  NO SECTOR DATA"
	var best_delta: float = INF
	var worst_delta: float = -INF
	var best_sector := 1
	var worst_sector := 1
	var previous_split := 0
	var previous_progress := 0.0
	var progress_ratios := CourseCatalog.get_checkpoint_progress_ratios(_track_id, _authoritative_route)
	for index: int in _split_times.size():
		var sector_time := _split_times[index] - previous_split
		previous_split = _split_times[index]
		var lap_sector := index % maxi(_checkpoint_data.size(), 1)
		var progress := progress_ratios[lap_sector] if lap_sector < progress_ratios.size() else float(lap_sector + 1) / float(maxi(_checkpoint_data.size(), 1))
		if lap_sector == 0:
			previous_progress = 0.0
		var rival_sector := float(_rival_target_usec) * (progress - previous_progress) / float(maxi(_session_config.laps, 1))
		previous_progress = progress
		var delta := float(sector_time) - rival_sector
		if delta < best_delta:
			best_delta = delta
			best_sector = index + 1
		if delta > worst_delta:
			worst_delta = delta
			worst_sector = index + 1
	return "RUN READOUT  //  BEST S%02d %+.2fs  //  COSTLIEST S%02d %+.2fs" % [best_sector, best_delta / 1_000_000.0, worst_sector, worst_delta / 1_000_000.0]


func _build_race_result() -> RaceResult:
	var result := RaceResult.new()
	result.run_id = str(_race_attempt_context.get(&"run_id", ""))
	var competitive_rules := _session_config.rules
	result.signature = _competitive_signature_cache
	result.event_id = _activity_id
	result.challenge_id = str(competitive_rules.get(&"challenge_id", ""))
	result.competition_id = StringName(competitive_rules.get(&"competition_id", &""))
	result.challenge_kind = StringName(competitive_rules.get(&"challenge_kind", &""))
	result.track_id = _track_id
	result.format = _session_config.format
	result.session_type = _session_config.session_type
	result.championship_id = _session_config.championship_id
	var finish_validity := _evaluate_finish_validity()
	result.valid = bool(finish_validity.get(&"valid", false))
	var validity_reasons: PackedStringArray = finish_validity.get(&"reasons", PackedStringArray())
	result.player_time_usec = _player_finish_usec
	result.player_elimination_lap = _player_elimination_lap
	result.player_penalty_usec = _player_penalty_usec
	result.medal = _medal_for_time(_player_finish_usec + _player_penalty_usec)
	result.classification = get_classification_snapshot()
	result.player_position = result.classification.size()
	result.fastest_lap_usec = -1
	var player_classified := false
	for racer: Dictionary in result.classification:
		if bool(racer.get(&"is_player", false)):
			result.player_position = int(racer.get(&"position", result.player_position))
			player_classified = StringName(racer.get(&"status", &"FINISHED")) in [&"FINISHED", &"CLASSIFIED"]
		var best_lap := int(racer.get(&"best_lap_usec", -1))
		if best_lap >= 0 and (result.fastest_lap_usec < 0 or best_lap < result.fastest_lap_usec):
			result.fastest_lap_usec = best_lap
			result.fastest_rider_id = StringName(racer.get(&"rider_id", &""))
	var incidents := _integrity_snapshot.get(&"incidents", {}) as Dictionary
	result.reset_count = int(incidents.get(&"resets_consumed", 0))
	result.off_course_count = int(incidents.get(&"off_course", 0))
	result.wrong_way_count = int(incidents.get(&"wrong_way", 0))
	result.cut_count = int(incidents.get(&"cuts", 0))
	var player_metrics := _player_race_metrics.get_snapshot()
	var player_interactions := get_pack_player_interaction_snapshot()
	result.overtakes = int(player_metrics.get(&"overtakes", 0))
	result.contacts = int(player_metrics.get(&"contacts", 0))
	result.crashes = int(player_metrics.get(&"crashes", 0))
	result.recoveries = int(player_metrics.get(&"recoveries", 0))
	result.near_misses = int(player_interactions.get(&"near_misses", 0))
	result.holeshot_rider_id = _race_pack.get_holeshot_rider_id()
	result.sector_times_usec.clear()
	var previous_split_usec := 0
	for split_usec: int in _split_times:
		result.sector_times_usec.append(maxi(split_usec - previous_split_usec, 0))
		previous_split_usec = split_usec
	result.lap_times_usec = _lap_times_usec.duplicate()
	var point_eligible := result.valid and player_classified and result.session_type == &"MAIN"
	result.championship_points = RaceEventCatalog.points_for_position(result.player_position) if point_eligible else 0
	var modifier_names := _competitive_modifier_names()
	result.validity_reason = ", ".join(validity_reasons)
	var reward_eligible := result.valid and player_classified and result.player_time_usec >= 0
	if not reward_eligible:
		result.medal = &"NO_AWARD"
		result.championship_points = 0
	var base_cash := 200
	match result.medal:
		&"GOLD":
			base_cash = 900
		&"SILVER":
			base_cash = 600
		&"BRONZE":
			base_cash = 350
	if _is_new_best:
		base_cash += 250
	var clean_bonus := 150 if result.contacts == 0 and result.crashes == 0 and result.recoveries == 0 else 0
	var placement_bonus := 350 if result.player_position == 1 else 200 if result.player_position <= 3 else 100 if result.player_position <= 5 else 0
	var modifier_bonus := 0
	var airtime_bonus_enabled := bool(competitive_rules.get(&"airtime_bonus", false)) or "AIRTIME_BONUS" in modifier_names
	if airtime_bonus_enabled:
		modifier_bonus += _airtime_reward_bonus()
	if "FLOW_CHAIN" in modifier_names:
		modifier_bonus += _academy_controlled_jumps * 25
	if "HOLESHOT_BONUS" in modifier_names and result.holeshot_rider_id == &"PLAYER":
		modifier_bonus += 250
	var reward_multiplier := clampf(float(competitive_rules.get(&"reward_multiplier", 1.0)), 0.5, 3.0)
	var total_cash_reward := roundi(float(base_cash + clean_bonus + placement_bonus + modifier_bonus) * reward_multiplier) if reward_eligible else 0
	var prior_event_record: Dictionary = {}
	if Profile.has_method(&"get_event_record"):
		prior_event_record = Profile.call(&"get_event_record", result.event_id, StringName(result.challenge_id)) as Dictionary
	var is_first_clear := int(prior_event_record.get(&"finishes", 0)) <= 0
	var is_first_win := result.player_position == 1 and int(prior_event_record.get(&"wins", 0)) <= 0
	var reputation_policy := REPUTATION_POLICY_SCRIPT.evaluate({
		&"eligible": reward_eligible,
		&"medal": result.medal,
		&"position": result.player_position,
		&"is_first_clear": is_first_clear,
		&"is_first_win": is_first_win,
		&"is_new_best": _is_new_best,
		&"competitive_multiplier": reward_multiplier,
	})
	var total_reputation_reward := int(reputation_policy.get(&"reputation", 0))
	if not reward_eligible:
		base_cash = 0
		clean_bonus = 0
		placement_bonus = 0
		modifier_bonus = 0
	result.rewards = {
		&"cash": total_cash_reward,
		&"reputation": total_reputation_reward,
		&"base_cash": base_cash,
		&"base_reputation": int(reputation_policy.get(&"base_reputation", 0)),
		&"bonus_cash": maxi(total_cash_reward - base_cash, 0),
		&"bonus_reputation": int(reputation_policy.get(&"bonus_reputation", 0)),
		&"placement_reputation": int(reputation_policy.get(&"placement_reputation", 0)),
		&"personal_best_reputation": int(reputation_policy.get(&"personal_best_reputation", 0)),
		&"reputation_before_repeat": int(reputation_policy.get(&"reputation_before_repeat", 0)),
		&"reputation_after_repeat": int(reputation_policy.get(&"reputation_after_repeat", 0)),
		&"repeat_factor": float(reputation_policy.get(&"repeat_factor", 0.0)),
		&"repeat_limited": bool(reputation_policy.get(&"repeat_limited", false)),
		&"repeat_reason": StringName(reputation_policy.get(&"repeat_reason", &"INELIGIBLE")),
		&"reputation_policy_version": int(reputation_policy.get(&"policy_version", 0)),
		&"first_clear": bool(reputation_policy.get(&"is_first_clear", false)),
		&"first_win": bool(reputation_policy.get(&"is_first_win", false)),
		&"new_best": bool(reputation_policy.get(&"is_new_best", false)),
		&"clean_race_bonus": clean_bonus,
		&"placement_bonus": placement_bonus,
		&"modifier_bonus": modifier_bonus,
		&"multiplier": reward_multiplier,
	}
	result.academy_metrics = _get_academy_metrics(result)
	return result


func _build_competitive_signature() -> String:
	var competitive_rules := _session_config.rules
	var build_signature := ""
	if not competitive_rules.has(&"challenge_id") and Profile.has_method(&"get_active_bike_setup_snapshot"):
		build_signature = str((Profile.call(&"get_active_bike_setup_snapshot") as Dictionary).get(&"signature", ""))
	return CompetitiveRunSignature.build({
		"event_id": competitive_rules.get(&"competitive_event_id", _activity_id),
		"track_id": _track_id,
		"route_version": _session_config.route_version,
		"format": _session_config.format,
		"laps": _session_config.laps,
		"bike_class": competitive_rules.get(&"competitive_bike_class", _session_config.bike_class),
		"difficulty": competitive_rules.get(&"competitive_difficulty", _session_config.difficulty),
		"assist_mode": competitive_rules.get(&"competitive_assist_mode", Profile.assist_mode),
		"setup_id": competitive_rules.get(&"competitive_setup_id", Profile.current_setup),
		"tune_signature": build_signature,
		"weather": _session_config.weather,
		"surface": _session_config.surface_modifier,
		"challenge_id": competitive_rules.get(&"challenge_id", ""),
		"modifiers": competitive_rules.get(&"modifiers", []),
	})


func _competitive_modifier_names() -> PackedStringArray:
	var names := PackedStringArray()
	for raw_modifier: Variant in _session_config.rules.get(&"modifiers", []):
		names.append(str(raw_modifier).to_upper())
	return names


func _evaluate_finish_validity() -> Dictionary:
	## This is the single authority used both before GhostController commits a PB
	## and when the official RaceResult is built. A modifier-invalid finish must
	## never become the comparison ghost for later eligible attempts.
	var valid := bool(_integrity_snapshot.get(&"valid", true))
	var reasons := PackedStringArray()
	if not valid:
		var penalties := _integrity_snapshot.get(&"penalties", {}) as Dictionary
		for raw_reason: Variant in penalties.keys():
			var reason := str(raw_reason)
			if reason not in reasons:
				reasons.append(reason)
	var modifier_names := _competitive_modifier_names()
	var incidents := _integrity_snapshot.get(&"incidents", {}) as Dictionary
	var player_metrics := _player_race_metrics.get_snapshot()
	if "NO_RESETS" in modifier_names and int(incidents.get(&"resets_consumed", 0)) > 0:
		valid = false
		if "NO_RESETS" not in reasons:
			reasons.append("NO_RESETS")
	if "ZERO_PENALTIES" in modifier_names and _player_penalty_usec > 0:
		valid = false
		if "ZERO_PENALTIES" not in reasons:
			reasons.append("ZERO_PENALTIES")
	if (
			"CLEAN_RIDE" in modifier_names
			and (
				int(player_metrics.get(&"contacts", 0)) > 0
				or int(player_metrics.get(&"crashes", 0)) > 0
				or int(player_metrics.get(&"recoveries", 0)) > 0
				or int(incidents.get(&"off_course", 0)) > 0
			)
		):
		valid = false
		if "CLEAN_RIDE" not in reasons:
			reasons.append("CLEAN_RIDE")
	return {&"valid": valid, &"reasons": reasons}


func _reset_academy_metrics() -> void:
	_academy_reaction_seconds = -1.0
	_academy_launch_speed = 0.0
	_academy_clean_landings = 0
	_academy_controlled_jumps = 0
	_academy_cases = 0
	_academy_landing_error_total = 0.0
	_academy_landing_samples = 0
	_academy_clean_checkpoints = 0
	_race_airtime_seconds = 0.0
	_race_clean_airtime_seconds = 0.0
	_academy_racecraft_metrics = {
		&"rut_rails": 0,
		&"controlled_slides": 0,
		&"pumps": 0,
		&"scrubs": 0,
		&"compose_saves": 0,
		&"dabs": 0,
		&"clutch_pops": 0,
		&"clean_skill_lines": 0,
		&"draft_slingshots": 0,
		&"roost_defenses": 0,
		&"rail_spends": 0,
		&"brace_saves": 0,
	}


func _update_academy_metrics() -> void:
	if bike == null:
		return
	var elapsed_seconds := float(_elapsed_usec) / 1_000_000.0
	if elapsed_seconds <= 4.0:
		_academy_launch_speed = maxf(_academy_launch_speed, bike.get_speed_mps())
	if _academy_reaction_seconds < 0.0 and bike.get_speed_mps() >= 0.8:
		_academy_reaction_seconds = elapsed_seconds


func _on_academy_bike_landed(intensity: float) -> void:
	if state != State.RACING:
		return
	_academy_landing_error_total += clampf(intensity, 0.0, 2.0)
	_academy_landing_samples += 1
	if intensity <= 0.55:
		_academy_clean_landings += 1
		_academy_controlled_jumps += 1
	else:
		_academy_cases += 1


func _on_bike_trick_landed(airtime: float, _rotation_amount: float, _landing_intensity: float, clean: bool) -> void:
	if state != State.RACING or airtime < 0.12:
		return
	_race_airtime_seconds += airtime
	if clean:
		_race_clean_airtime_seconds += airtime
	if bool(_session_config.rules.get(&"airtime_bonus", false)):
		var points := roundi(airtime * (120.0 if clean else 45.0))
		race_moment.emit(
			"AIRTIME %.1fs  //  +%d%s" % [airtime, points, " CLEAN" if clean else ""],
			points,
			clean
		)


func _on_bike_racecraft_event(kind: StringName, payload: Dictionary) -> void:
	if state != State.RACING:
		return
	var metric: StringName = &""
	match kind:
		&"RUT_RAIL": metric = &"rut_rails"
		&"CONTROLLED_SLIDE": metric = &"controlled_slides"
		&"PUMP": metric = &"pumps"
		&"SCRUB": metric = &"scrubs"
		&"COMPOSE_SAVE": metric = &"compose_saves"
		&"DAB": metric = &"dabs"
		&"CLUTCH_POP": metric = &"clutch_pops"
		&"DRAFT_SLINGSHOT": metric = &"draft_slingshots"
		&"ROOST_DEFENSE": metric = &"roost_defenses"
		&"FLOW_RAIL": metric = &"rail_spends"
		&"BRACE_SAVE": metric = &"brace_saves"
		&"SKILL_LINE":
			if StringName(payload.get(&"outcome", &"MISSED")) in [&"CLEAN", &"MASTERED"]:
				metric = &"clean_skill_lines"
	if not metric.is_empty():
		_academy_racecraft_metrics[metric] = int(_academy_racecraft_metrics.get(metric, 0)) + 1


func _airtime_reward_bonus() -> int:
	# Airtime should improve the reward texture without allowing a long multi-lap
	# race to invalidate parts, repairs, and bike progression in one payout.
	return mini(roundi(_race_clean_airtime_seconds * 75.0) + _academy_clean_landings * 35, AIRTIME_REWARD_CAP)


func _get_academy_metrics(result: RaceResult) -> Dictionary:
	var landing_error := _academy_landing_error_total / float(_academy_landing_samples) if _academy_landing_samples > 0 else 1.0
	var off_course_seconds := float(result.off_course_count) * _session_config.off_course_grace_seconds
	var metrics := {
		&"gates_completed": _split_times.size(),
		&"resets": result.reset_count,
		&"reaction_seconds": _academy_reaction_seconds if _academy_reaction_seconds >= 0.0 else 9.0,
		&"launch_speed": _academy_launch_speed,
		&"clean_corners": _academy_clean_checkpoints,
		&"off_course_seconds": off_course_seconds,
		&"clean_landings": _academy_clean_landings,
		&"landing_error": landing_error,
		&"rhythm_chains": floori(float(_academy_clean_landings) / 2.0),
		&"cases": _academy_cases,
		&"controlled_jumps": _academy_controlled_jumps,
		&"airtime_seconds": _race_airtime_seconds,
		&"clean_airtime_seconds": _race_clean_airtime_seconds,
		&"crashes": result.crashes,
		&"successful_rejoins": result.recoveries,
		&"rejoin_contacts": result.contacts if result.reset_count > 0 else 0,
		&"clean_passes": maxi(result.overtakes - result.contacts, 0),
		&"contacts": result.contacts,
	}
	for raw_key: Variant in _academy_racecraft_metrics.keys():
		metrics[raw_key] = _academy_racecraft_metrics[raw_key]
	return metrics


func _surface_for_lap(lap: int) -> StringName:
	if _session_config.weather != &"VARIABLE":
		return _session_config.surface_modifier
	# A deterministic six-lap grip arc makes the endurance event genuinely
	# change under the rider while remaining replay- and competition-safe.
	var variable_surfaces: Array[StringName] = [
		&"PACKED", &"LOOSE_DIRT", &"PACKED", &"WET", &"RUTTED", &"PACKED",
	]
	return variable_surfaces[(maxi(lap, 1) - 1) % variable_surfaces.size()]


func _set_session_surface(surface: StringName, announce: bool) -> void:
	var next_surface := surface if not surface.is_empty() else &"PACKED"
	var changed := next_surface != _active_session_surface
	_active_session_surface = next_surface
	if bike != null:
		bike.apply_session_surface(_active_session_surface)
	if announce and changed:
		race_moment.emit("GRIP CHANGE  //  %s" % String(_active_session_surface).replace("_", " "), 0, false)


func _emit_classification() -> void:
	classification_updated.emit(get_classification_snapshot())


func _emit_session_snapshot() -> void:
	session_updated.emit(get_session_snapshot())


func _phase_name() -> StringName:
	match state:
		State.WAITING:
			return &"WAITING"
		State.STAGING:
			return &"STAGING"
		State.COUNTDOWN:
			return &"STAGING" if _countdown_remaining > _session_config.countdown_seconds - _session_config.staging_seconds else &"COUNTDOWN"
		State.RACING:
			return &"RACING"
		State.FINISHED:
			return &"FINISHING"
		State.RESULTS:
			return &"RESULTS"
	return &"WAITING"


func _create_integrity_tracker() -> void:
	var script_path := "res://features/race/race_integrity_tracker.gd"
	if not ResourceLoader.exists(script_path):
		return
	var script := load(script_path) as Script
	if script != null:
		_integrity_tracker = script.new()


func _configure_integrity_tracker() -> void:
	if _integrity_tracker == null:
		_create_integrity_tracker()
	if _integrity_tracker == null:
		return
	_racecraft_branch_routes.clear()
	if _integrity_tracker.has_method(&"configure"):
		var integrity_options := {
			&"off_course_grace_seconds": _session_config.off_course_grace_seconds,
			&"wrong_way_grace_seconds": _session_config.wrong_way_grace_seconds,
			&"reset_penalty_usec": _session_config.reset_penalty_usec,
			&"cut_penalty_usec": _session_config.cut_penalty_usec,
			&"closed": _track_id == CourseCatalog.MESA_MX_ID,
			&"shoulder_margin": 5.0,
		}
		if (
			_track_id == CourseCatalog.PINE_ID
			and not _session_config.reverse_route
			and _authoritative_surface_root != null
			and _authoritative_surface_root.has_method(&"get_racecraft_network_world")
		):
			var branch_value: Variant = _authoritative_surface_root.call(&"get_racecraft_network_world")
			if branch_value is Array:
				var branch_routes := (branch_value as Array).duplicate(true)
				integrity_options[&"branch_routes"] = branch_routes
				for raw_record: Variant in branch_routes:
					if raw_record is Dictionary:
						var record := raw_record as Dictionary
						var line_id := StringName(record.get(&"line_id", &""))
						if not line_id.is_empty():
							_racecraft_branch_routes[line_id] = record.duplicate(true)
		_integrity_tracker.call(
			&"configure",
			_authoritative_route,
			CourseCatalog.get_track_width(_track_id),
			_spawn_transform,
			_session_config.laps,
			integrity_options
		)
	_reset_integrity_tracker()


func _reset_integrity_tracker() -> void:
	_integrity_snapshot = {
		&"valid": true, &"warning": &"", &"flag": &"NONE", &"penalty_usec": 0,
		&"reset_count": 0, &"off_course_count": 0, &"wrong_way_count": 0, &"cut_count": 0,
	}
	if _integrity_tracker != null and _integrity_tracker.has_method(&"reset"):
		_integrity_tracker.call(&"reset", false)


func _update_integrity(delta: float) -> void:
	var arguments := OS.get_cmdline_user_args()
	# Normal smoke assertions isolate the expensive live tracker. Rendered race
	# captures opt back in so their HUD and handling feedback match real gameplay.
	if (
		&"--smoke-test" in arguments
		and &"--capture-race-visuals" not in arguments
		and (
			_session_config.format != &"ACADEMY"
			or bool(_integrity_snapshot.get(&"stuck_detection_armed", false))
		)
	):
		return
	if _integrity_tracker == null or bike == null or not _integrity_tracker.has_method(&"update"):
		return
	var snapshot: Variant = _integrity_tracker.call(&"update", delta, bike.global_transform, bike.linear_velocity, _current_lap, true)
	if snapshot is Dictionary:
		_integrity_snapshot = (snapshot as Dictionary).duplicate(true)
		bike.set_course_racecraft_context(_build_course_racecraft_context(_integrity_snapshot))
		_player_penalty_usec = maxi(_player_penalty_usec, int(_integrity_snapshot.get(&"penalty_usec", 0)))
		integrity_updated.emit(_integrity_snapshot.duplicate(true))
		var warning := StringName(_integrity_snapshot.get(&"warning", &""))
		if warning in [&"WRONG_WAY", &"OFF_COURSE", &"CUT"]:
			_set_flag(&"YELLOW")
		elif _flag == &"YELLOW" and state == State.RACING:
			_set_flag(&"GREEN")
		if _integrity_tracker.has_method(&"has_reset_request") and bool(_integrity_tracker.call(&"has_reset_request")):
			var reset_data := _integrity_tracker.call(&"consume_reset_request") as Dictionary
			var recovery_reason := StringName(reset_data.get(&"reason", &"INTEGRITY_RECOVERY"))
			var rejoin: Variant = reset_data.get(&"transform", _spawn_transform)
			if rejoin is Transform3D:
				bike.respawn_at(rejoin)
				_race_pack.set_contact_immunity(1.5)
				_race_pack.resync_player_pass_tracking()
				_player_race_metrics.record_recovery(recovery_reason)
				if _integrity_tracker.has_method(&"get_snapshot"):
					_integrity_snapshot = _integrity_tracker.call(&"get_snapshot") as Dictionary
					integrity_updated.emit(_integrity_snapshot.duplicate(true))
				_emit_recovery_feedback(
					recovery_reason,
					int(reset_data.get(&"penalty_applied_usec", 0))
				)


func _build_course_racecraft_context(integrity: Dictionary) -> Dictionary:
	if _authoritative_route.size() < 3 or bike == null:
		return {}
	var segment := clampi(int(integrity.get(&"segment", 0)), 0, _authoritative_route.size() - 2)
	var route_line_id := StringName(integrity.get(&"route_line_id", &"MAIN"))
	var branch_record: Dictionary = _racecraft_branch_routes.get(route_line_id, {})
	var current_tangent: Vector3
	var future_tangent: Vector3
	var track_half_width := CourseCatalog.get_track_width(_track_id) * 0.5
	if route_line_id != &"MAIN" and not branch_record.is_empty():
		var branch_points: PackedVector3Array = branch_record.get(&"points", PackedVector3Array())
		var branch_segment := clampi(
			int(integrity.get(&"route_line_segment", 0)),
			0,
			maxi(branch_points.size() - 2, 0)
		)
		if branch_points.size() >= 2:
			var branch_lookahead := mini(branch_segment + 14, branch_points.size() - 2)
			current_tangent = branch_points[branch_segment + 1] - branch_points[branch_segment]
			future_tangent = branch_points[branch_lookahead + 1] - branch_points[branch_lookahead]
			track_half_width = maxf(float(branch_record.get(&"width", track_half_width * 2.0)) * 0.5, 1.0)
		else:
			current_tangent = integrity.get(&"route_line_tangent", Vector3.FORWARD) as Vector3
			future_tangent = current_tangent
	else:
		var lookahead_index := mini(segment + 14, _authoritative_route.size() - 1)
		current_tangent = _authoritative_route[segment + 1] - _authoritative_route[segment]
		future_tangent = _authoritative_route[lookahead_index] - _authoritative_route[mini(segment + 2, _authoritative_route.size() - 1)]
	if current_tangent.length_squared() < 0.01:
		current_tangent = Vector3.FORWARD
	if future_tangent.length_squared() < 0.01:
		future_tangent = current_tangent
	current_tangent = current_tangent.normalized()
	future_tangent = future_tangent.normalized()
	var current_flat := current_tangent.slide(Vector3.UP).normalized()
	var future_flat := future_tangent.slide(Vector3.UP).normalized()
	var signed_turn := current_flat.cross(future_flat).dot(Vector3.UP)
	var corner_strength := clampf(absf(signed_turn) / 0.42, 0.0, 1.0)
	var signed_lateral := float(integrity.get(&"signed_lateral", 0.0))
	var rut_offset := 0.98 if _track_id == CourseCatalog.PINE_ID else 1.25 if _track_id == CourseCatalog.MESA_MX_ID else 1.15
	var rut_distance := absf(absf(signed_lateral) - rut_offset)
	var rut_strength := (1.0 - smoothstep(0.18, 0.82, rut_distance)) * lerpf(0.62, 1.0, corner_strength)
	var is_outside := (
		(signed_lateral > 0.0 and signed_turn > 0.0)
		or (signed_lateral < 0.0 and signed_turn < 0.0)
	)
	var berm_edge := smoothstep(track_half_width * 0.58, track_half_width * 0.92, absf(signed_lateral))
	var berm_strength := corner_strength * berm_edge if is_outside else 0.0
	var bike_forward := -bike.global_transform.basis.z.slide(Vector3.UP).normalized()
	var route_alignment := bike_forward.dot(current_flat)
	var lap_progress := clampf(float(integrity.get(&"lap_progress", 0.0)), 0.0, 1.0)
	var route_length := maxf(float(integrity.get(&"route_length", 0.0)), 0.0)
	var zone_count := 10 if _track_id == CourseCatalog.MESA_MX_ID else 18 if _track_id == CourseCatalog.PINE_ID else 14
	var guidance: Dictionary = RACECRAFT_RULES.skill_line_guidance(
		lap_progress,
		route_length,
		bike.get_speed_mps(),
		zone_count
	)
	var zone_index := int(guidance.get(&"zone_index", -1))
	var zone_phase := StringName(guidance.get(&"phase", &"NONE"))
	if zone_phase == &"PREVIEW" and RACECRAFT_RULES.suppress_wrapped_preview(
		int(guidance.get(&"lap_offset", 0)),
		zone_index,
		_current_lap,
		_session_config.laps,
		_expected_checkpoint,
		_checkpoint_data.size()
	):
		zone_index = -1
		zone_phase = &"NONE"
	var definition: Dictionary = RACECRAFT_RULES.skill_line_definition(
		zone_index,
		track_half_width,
		rut_offset
	)
	var zone_kind := StringName(definition.get(&"kind", &"NONE"))
	var target_lane := float(definition.get(&"target_lane", 0.0))
	var target_delta := target_lane - signed_lateral
	var alignment_width := maxf(track_half_width * 0.48, 1.5)
	var skill_alignment := (
		1.0 - clampf(absf(target_delta) / alignment_width, 0.0, 1.0)
		if zone_index >= 0
		else 0.0
	)
	var zone_id := RACECRAFT_RULES.skill_line_zone_key(
		_track_id,
		route_line_id,
		zone_index if zone_phase != &"NONE" else -1,
		zone_kind
	)
	return {
		&"segment": segment,
		&"route_line_id": route_line_id,
		&"route_line_progress": float(integrity.get(&"route_line_progress", lap_progress)),
		&"lap_progress": lap_progress,
		&"signed_lateral": signed_lateral,
		&"track_half_width": track_half_width,
		&"turn_sign": signf(signed_turn),
		&"corner_strength": corner_strength,
		&"downhill_strength": clampf(-current_tangent.y * 2.2, 0.0, 1.0),
		&"uphill_strength": clampf(current_tangent.y * 2.2, 0.0, 1.0),
		&"route_alignment": route_alignment,
		&"rut_strength": rut_strength,
		&"berm_strength": berm_strength,
		&"skill_zone_id": zone_id,
		&"skill_zone_kind": zone_kind,
		&"skill_zone_phase": zone_phase,
		&"skill_zone_preview": zone_phase == &"PREVIEW",
		&"skill_zone_active": bool(guidance.get(&"active", false)),
		&"skill_line_direction": StringName(definition.get(&"direction", &"CENTER")),
		&"skill_line_target": target_lane,
		&"skill_line_target_delta": target_delta,
		&"skill_line_distance_m": float(guidance.get(&"distance_m", 0.0)),
		&"skill_line_preview_seconds": float(guidance.get(&"preview_seconds", 0.0)),
		&"skill_line_alignment": skill_alignment,
		&"skill_line_difficulty": clampf(0.38 + corner_strength * 0.24 + absf(current_tangent.y) * 0.55, 0.35, 0.82),
	}
