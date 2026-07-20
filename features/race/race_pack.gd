extends Node3D
class_name RacePack
## Deterministic lightweight motocross field. Opponents retain the player's
## visual silhouette while a compact progress/lane simulation supplies traffic,
## overtakes, near misses, bounded contact, and recoverable crashes.

const BIKE_VISUAL_SCRIPT = preload("res://entities/bike/bike_visual.gd")
const ENGINE_AUDIO_SCRIPT = preload("res://entities/bike/engine_audio.gd")
const RACECRAFT_RULES = preload("res://features/race/racecraft_rules.gd")

signal rider_finished(rider_id: StringName, finish_usec: int)
signal rider_lap_completed(rider_id: StringName, lap: int, total_laps: int)
signal rider_eliminated(rider_id: StringName, elimination_lap: int)
signal holeshot_decided(rider_id: StringName)
signal player_overtook(rider_id: StringName)
signal player_was_overtaken(rider_id: StringName)

const RIDER_COUNT := 11
const GRID_COLUMNS := 3
const GRID_ROWS := 4
const PLAYER_GRID_ROW := 0
const PLAYER_GRID_COLUMN := 1
const GRID_LANE_SPACING := 2.3
const GRID_ROW_SPACING := 2.8
const GRID_START_PROGRESS := 2.0

# Recovered reference behavior: 2.5 m lane slots, roughly 2.25 m/s lateral
# movement, 0.5 s tactical decisions, and speed changes every 1.5-2.5 seconds.
const LANE_SLOT_WIDTH := 2.5
const REFERENCE_PACK_HALF_WIDTH := 5.0
const LANE_CHANGE_SPEED := 2.25
const LANE_ACCELERATION := 7.5
const LINE_LOOK_AHEAD_METERS := 60.0
const FRONT_SENSOR_LENGTH := 10.0
const FRONT_SENSOR_HALF_WIDTH := 2.0
const SIDE_SENSOR_LENGTH := 1.15
const SIDE_SENSOR_WIDTH := 1.45
const DEFENSE_SENSOR_LENGTH := 12.0
const DEFENSE_MAX_LANE_MOVE := 1.35
const CLOSE_ATTACK_MAX_MPS := 1.15
const AI_DRAFT_MAX_MPS := 1.15
const PLAYER_ROOST_COOLDOWN_SECONDS := 0.90
const PLAYER_ROOST_MAX_DRIVE_COST := 0.025
const RACECRAFT_MAX_HALF_WIDTH := 8.4
const RUT_LANE_OFFSETS: Dictionary[StringName, float] = {
	CourseCatalog.QUARRY_ID: 1.15,
	CourseCatalog.PINE_ID: 0.98,
	CourseCatalog.MESA_MX_ID: 1.10,
}
const BERM_LANE_OFFSETS: Dictionary[StringName, float] = {
	CourseCatalog.QUARRY_ID: 7.80,
	CourseCatalog.PINE_ID: 7.25,
	CourseCatalog.MESA_MX_ID: 7.55,
}
const LATE_RACE_PRESSURE_MAX_MPS := 1.35
const PASS_INTENT_MIN_SECONDS := 0.90
const PASS_INTENT_MAX_SECONDS := 1.40
const DEFENSE_INTENT_SECONDS := 1.05
const DEFENSE_COOLDOWN_MIN_SECONDS := 3.4
const DEFENSE_COOLDOWN_MAX_SECONDS := 5.0
# Player-matched visuals occupy roughly 0.9 x 2.08 m at the tyre footprint.
# Detect bar/wheel contact before meshes interpenetrate, and resolve the tiny
# remaining overlap positionally instead of letting non-physical roots ghost.
const NPC_VISUAL_LENGTH := 2.08
const NPC_VISUAL_WIDTH := 0.9
const NPC_CONTACT_HALF_LENGTH := 2.18
const NPC_CONTACT_HALF_WIDTH := 0.96
const NPC_MAX_SEPARATION_STEP := 0.12
const PLAYER_CONTACT_HALF_WIDTH := 0.95
const PLAYER_CONTACT_HALF_LENGTH := 2.1
const PLAYER_CONTACT_HEIGHT := 1.5
const NEAR_MISS_DISTANCE := 1.85
const NEAR_MISS_EXIT_DISTANCE := 2.35
const PLAYER_CONTACT_COOLDOWN := 0.35
const GLOBAL_CONTACT_COOLDOWN := 0.22

# The old pack began making 2.25 m/s lane changes almost immediately while its
# forward launch was still heavily eased. That made the grid appear to strafe
# sideways and fan out from the gate. Hold each assigned grid lane through a
# short, purposeful launch, then ease tactical line choice in continuously.
const LAUNCH_LANE_LOCK_SECONDS := 2.5
const LAUNCH_TACTICS_BLEND_SECONDS := 1.25
const LAUNCH_FORWARD_RAMP_SECONDS := 1.05
const LAUNCH_ACCELERATION := 5.6
const ORIENTATION_FOLLOW_RATE := 14.0
const TANGENT_SAMPLE_METERS := 2.5
const SURFACE_RAY_HEIGHT := 8.0
const SURFACE_RAY_DEPTH := 5.0
const SURFACE_DROP_LAUNCH_THRESHOLD := 0.2
const SURFACE_CREST_LAUNCH_DROP := 0.035
const SURFACE_CREST_LAUNCH_SPEED := 2.0
const SURFACE_GRAVITY := 19.6
const SURFACE_MAX_FALL_SPEED := 12.0
const SURFACE_MAX_LAUNCH_SPEED := 9.0
const LEGACY_DIRECTOR_MAX_CORRECTION := 0.65
const DIRECTOR_MAX_CORRECTION := 2.75
const LEADER_DRAG_SCALE := 0.60
const FIELD_COMEBACK_SCALE := 1.65
const RACE_PACE_SCALE := 0.96
const ACADEMY_PACE_SCALE := 0.87
const HOLESHOT_DISTANCE := 48.0
const AUDIO_POOL_SIZE := 4
const PLAYER_MODE_PACE_SCALARS: Dictionary[StringName, float] = {
	&"RELAXED": 0.99,
	&"STANDARD": 1.08,
	&"EXPERT": 1.17,
}

enum RiderMode { RIDING, WOBBLE, CRASHED, RECOVERING }

var _track_id: StringName = CourseCatalog.QUARRY_ID
var _track_points := PackedVector3Array()
var _distances := PackedFloat32Array()
var _track_length: float = 0.0
var _lane_limit: float = 4.0
var _racecraft_lane_limit: float = 4.0
var _authoritative_surface_root: Node3D
var _riders: Array[Dictionary] = []
var _pair_orders: Dictionary = {}
var _player_pair_orders: Dictionary = {}
var _active: bool = false
var _race_elapsed: float = 0.0
var _player: DirtBikeController
var _player_progress: float = GRID_START_PROGRESS
var _player_total_progress_m: float = GRID_START_PROGRESS
var _player_lane: float = 0.0
var _player_sample_time: float = 0.0
var _global_contact_cooldown: float = 0.0
var _chaos_metrics: Dictionary = {}
var _session_config: RaceSessionConfig = RaceEventCatalog.get_session_config(&"CIRCUIT")
var _active_rider_count: int = RIDER_COUNT
var _total_laps: int = 1
var _player_laps_completed: int = 0
var _player_finish_usec: int = -1
var _player_penalty_usec: int = 0
var _player_status: StringName = &"RUNNING"
var _player_elimination_lap: int = -1
var _player_projection_segment: int = -1
var _closed_route: bool = false
var _pending_elimination_laps: Array[int] = []
var _elimination_rounds: Dictionary[int, StringName] = {}
var _last_eliminated_rider: StringName = &""
var _contact_immunity_time: float = 0.0
var _holeshot_rider_id: StringName = &""
var _audio_pool: Array[AudioStreamPlayer3D] = []
var _audio_update_time: float = 0.0
var _jump_zones: Array[Dictionary] = []
var _retention_contract: Dictionary = {}
var _surface_queries_this_tick: int = 0
var _surface_queries_peak: int = 0
var _surface_query := PhysicsRayQueryParameters3D.new()
## Dedicated simulations and server-side race adjudication can disable the
## expensive visual/audio shell while retaining the exact production race AI.
## Playable sessions leave this enabled.
var presentation_enabled: bool = true
var simulation_has_player: bool = false
var _authored_difficulty: int = 2
var _player_difficulty_mode: StringName = &"LOCKED"
var _mode_pace_scale: float = 1.0
var _build_match_scale: float = 1.0
var _skill_delta: float = 0.0
var _player_speed_snapshot: float = 0.0
var _player_racecraft_context: Dictionary = {}


func _ready() -> void:
	_ensure_riders()
	if presentation_enabled:
		_build_audio_pool()
	_surface_query.collide_with_areas = false
	_surface_query.collide_with_bodies = true
	set_process(false)
	set_physics_process(true)


func configure(
	track_id: StringName,
	authoritative_route: PackedVector3Array = PackedVector3Array(),
	authoritative_surface_root: Node3D = null,
	session_config: RaceSessionConfig = null
) -> void:
	_ensure_riders()
	_track_id = track_id if track_id in [CourseCatalog.QUARRY_ID, CourseCatalog.PINE_ID, CourseCatalog.MESA_MX_ID] else CourseCatalog.QUARRY_ID
	_session_config = session_config if session_config != null else RaceEventCatalog.get_session_config(CourseCatalog.get_activity_id(_track_id))
	_authored_difficulty = clampi(
		int(_session_config.rules.get(&"authored_difficulty", _session_config.difficulty)),
		0,
		4
	)
	_player_difficulty_mode = StringName(_session_config.rules.get(&"player_difficulty_mode", &"LOCKED"))
	_mode_pace_scale = float(PLAYER_MODE_PACE_SCALARS.get(_player_difficulty_mode, 1.0))
	_build_match_scale = clampf(float(_session_config.rules.get(&"opponent_build_match_scale", 1.0)), 0.94, 1.12)
	var skill_tier := _authored_difficulty if _session_config.rules.has(&"authored_difficulty") else _session_config.difficulty
	var mode_skill_delta := -0.03 if _player_difficulty_mode == &"RELAXED" else 0.04 if _player_difficulty_mode == &"EXPERT" else 0.0
	_skill_delta = clampf(float(skill_tier - 2) * 0.012 + mode_skill_delta, -0.07, 0.08)
	var configured_retention: Variant = _session_config.rules.get(&"retention", {})
	_retention_contract = configured_retention.duplicate(true) if configured_retention is Dictionary else {}
	if _retention_contract.is_empty():
		_retention_contract = RaceEventCatalog.get_retention_contract(_session_config.event_id)
	_active_rider_count = clampi(_session_config.opponent_count, 0, RIDER_COUNT)
	_total_laps = maxi(_session_config.laps, 1)
	_jump_zones = CourseCatalog.get_welded_jump_zones(_track_id)
	# The built ribbon is the production source of truth. The catalog fallback is
	# retained only so isolated probes can instantiate RacePack without a level.
	_track_points = (
		authoritative_route.duplicate()
		if authoritative_route.size() >= 2
		else CourseCatalog.get_world_riding_points(_track_id)
	)
	_closed_route = (
		_track_points.size() >= 4
		and _track_points[0].distance_to(_track_points[-1]) <= 0.02
	)
	_authoritative_surface_root = authoritative_surface_root
	# The recovered field races five 2.5 m slots centered at -5..+5 m. Wider
	# ribbons should provide recovery room for the player, not disperse opponents
	# so far across the shoulders that overtakes and bar contact disappear.
	_lane_limit = minf(
		maxf(CourseCatalog.get_track_width(_track_id) * 0.5 - 0.7, 1.8),
		REFERENCE_PACK_HALF_WIDTH
	)
	# The central pack envelope remains unchanged for launch, passing, defense,
	# and contact. Authored rut/berm choices may use more of the physical ribbon
	# once launch tactics are fully released.
	_racecraft_lane_limit = minf(
		maxf(CourseCatalog.get_track_width(_track_id) * 0.5 - 0.7, _lane_limit),
		RACECRAFT_MAX_HALF_WIDTH
	)
	_distances.resize(_track_points.size())
	_track_length = 0.0
	for index: int in range(1, _track_points.size()):
		_track_length += _track_points[index - 1].distance_to(_track_points[index])
		_distances[index] = _track_length
	reset_grid()


func get_authoritative_route_points() -> PackedVector3Array:
	return _track_points.duplicate()


func set_player(player: DirtBikeController) -> void:
	_player = player
	if is_instance_valid(_player):
		_update_player_progress()
	_clear_player_racecraft_context()
	_reset_player_pair_orders()


func reset_grid() -> void:
	_active = false
	_race_elapsed = 0.0
	_player_progress = GRID_START_PROGRESS
	_player_total_progress_m = clampf(
		GRID_START_PROGRESS,
		0.0,
		_track_length * float(_total_laps)
	)
	_player_lane = 0.0
	_player_sample_time = 0.0
	_player_projection_segment = -1
	_player_laps_completed = 0
	_player_finish_usec = -1
	_player_penalty_usec = 0
	_player_status = &"RUNNING"
	_player_elimination_lap = -1
	_player_speed_snapshot = 0.0
	_pending_elimination_laps.clear()
	_elimination_rounds.clear()
	_last_eliminated_rider = &""
	_clear_player_racecraft_context()
	_contact_immunity_time = 0.0
	_holeshot_rider_id = &""
	_global_contact_cooldown = 0.0
	_surface_queries_this_tick = 0
	_surface_queries_peak = 0
	_reset_chaos_metrics()
	visible = not _track_points.is_empty()
	var rival_only := bool(_session_config.rules.get(&"rival_only", false))
	var gate_order := _string_name_array(_session_config.rules.get(&"gate_order", []))
	var profiles := _profiles_for_session(_active_rider_count, rival_only, gate_order)
	var grid_slots: Array[Vector2] = []
	for row: int in GRID_ROWS:
		for column: int in GRID_COLUMNS:
			if row == PLAYER_GRID_ROW and column == PLAYER_GRID_COLUMN:
				continue
			var lane := clampf((float(column) - 1.0) * GRID_LANE_SPACING, -_lane_limit, _lane_limit)
			var progress := GRID_START_PROGRESS + float(row) * GRID_ROW_SPACING
			grid_slots.append(Vector2(progress, lane))
	# A qualifying result is a gate pick, not a pace multiplier. Seeded sessions
	# put the first named opponent in the foremost centre slot and fill outward;
	# unseeded events retain the legacy grid order byte-for-byte.
	if not gate_order.is_empty():
		grid_slots.sort_custom(func(first: Vector2, second: Vector2) -> bool:
			if not is_equal_approx(first.x, second.x):
				return first.x > second.x
			var first_center_distance := absf(first.y)
			var second_center_distance := absf(second.y)
			if not is_equal_approx(first_center_distance, second_center_distance):
				return first_center_distance < second_center_distance
			return first.y < second.y
		)
	for index: int in _riders.size():
		var state: Dictionary = _riders[index]
		var root := state[&"root"] as Node3D
		if index >= _active_rider_count:
			state[&"active"] = false
			state[&"finished"] = true
			state[&"status"] = &"DNS"
			root.visible = false
			_riders[index] = state
			continue
		var slot := grid_slots[index]
		var profile: Dictionary = profiles[index]
		state[&"active"] = true
		state[&"profile"] = profile
		state[&"rider_id"] = StringName(profile.get(&"id", "RIDER_%02d" % index))
		state[&"display_name"] = str(profile.get(&"name", "RIDER %02d" % (index + 2)))
		state[&"number"] = int(profile.get(&"number", index + 2))
		state[&"progress"] = slot.x
		state[&"lane"] = slot.y
		state[&"lane_target"] = slot.y
		state[&"launch_lane"] = slot.y
		state[&"lane_velocity"] = 0.0
		state[&"previous_lane_velocity"] = 0.0
		state[&"lane_change_active"] = false
		var difficulty_scale := 1.0 + float(_authored_difficulty - 2) * 0.045
		var class_scale := 0.94 if _session_config.bike_class == &"LITE_125" else 1.08 if _session_config.bike_class == &"OPEN" else 1.0
		var pace := clampf(float(profile.get(&"pace", 0.82)), 0.55, 1.05)
		state[&"base_speed"] = (13.0 + pace * 5.5) * difficulty_scale * _mode_pace_scale * class_scale * _build_match_scale
		state[&"speed"] = 0.0
		state[&"speed_bias"] = 0.0
		state[&"speed_event"] = 0
		state[&"speed_event_time"] = 1.5 + _event_unit(index, 0, 1.7)
		state[&"decision_event"] = 0
		state[&"decision_time"] = 0.55 + _event_unit(index, 0, 2.9) * 0.4
		state[&"traffic_plan_time"] = 0.0
		state[&"traffic_plan_kind"] = &""
		state[&"traffic_plan_target"] = slot.y
		var grid_row := roundi((slot.x - GRID_START_PROGRESS) / GRID_ROW_SPACING)
		# Front rows clear first and rear rows feed in behind them. Randomizing
		# this ordering let a rear rider launch into a delayed bike ahead.
		var start_skill := clampf(float(profile.get(&"start", 0.8)), 0.0, 1.0)
		state[&"launch_delay"] = float(GRID_ROWS - 1 - grid_row) * 0.04 + (1.0 - start_skill) * 0.12 + _event_unit(index, 0, 4.3) * 0.025
		state[&"aggression"] = clampf(float(profile.get(&"aggression", 0.6)) + _skill_delta * 0.45, 0.0, 1.0)
		state[&"corner_skill"] = clampf(float(profile.get(&"corner", 0.8)) + _skill_delta * 0.65, 0.0, 1.0)
		var jump_commitment := clampf(float(_retention_contract.get(&"jump_commitment", 1.0)), 0.65, 1.2)
		state[&"jump_confidence"] = clampf(float(profile.get(&"jump", 0.8)) * jump_commitment, 0.0, 1.0)
		state[&"consistency"] = clampf(float(profile.get(&"consistency", 0.8)) + _skill_delta, 0.0, 1.0)
		state[&"recovery_skill"] = clampf(float(profile.get(&"recovery", 0.8)) + _skill_delta * 1.2, 0.0, 1.0)
		state[&"pressure_skill"] = clampf(float(profile.get(&"pressure", 0.75)), 0.0, 1.0)
		state[&"comeback_skill"] = clampf(float(profile.get(&"comeback", 0.85)), 0.0, 1.0)
		state[&"tactical_reaction_scale"] = clampf(1.06 - float(state[&"aggression"]) * 0.10 - _skill_delta * 1.4, 0.78, 1.12)
		state[&"launch_acceleration_scale"] = lerpf(0.94, 1.08, start_skill) * clampf(1.0 + _skill_delta * 0.65, 0.95, 1.06)
		state[&"defense_cooldown"] = 0.0
		state[&"close_attack_mps"] = 0.0
		state[&"close_attack_active"] = false
		state[&"draft_strength"] = 0.0
		state[&"roost_pressure"] = 0.0
		state[&"roost_cooldown"] = 0.0
		state[&"roost_drive_multiplier"] = 1.0
		state[&"late_pressure_mps"] = 0.0
		state[&"section_speed_factor"] = 1.0
		state[&"line_factor"] = 1.0
		state[&"corner_factor"] = 1.0
		state[&"downhill_factor"] = 1.0
		state[&"wet_factor"] = 1.0
		state[&"jump_factor"] = 1.0
		state[&"skill_line_active"] = false
		state[&"skill_line_outcome"] = &"NONE"
		state[&"skill_line_factor"] = 1.0
		state[&"last_crash_duration"] = 0.0
		state[&"last_recovery_duration"] = 0.0
		_chaos_metrics[&"launch_min_acceleration_scale"] = minf(
			float(_chaos_metrics[&"launch_min_acceleration_scale"]),
			float(state[&"launch_acceleration_scale"])
		)
		_chaos_metrics[&"launch_max_acceleration_scale"] = maxf(
			float(_chaos_metrics[&"launch_max_acceleration_scale"]),
			float(state[&"launch_acceleration_scale"])
		)
		state[&"preferred_line"] = StringName(profile.get(&"line", &"SAFE"))
		state[&"phase"] = float(index) * 0.81
		state[&"mode"] = RiderMode.RIDING
		state[&"mode_time"] = 0.0
		state[&"pose_roll"] = 0.0
		state[&"crash_sign"] = -1.0 if index % 2 == 0 else 1.0
		state[&"contact_cooldown"] = 0.0
		state[&"near_miss_pending"] = false
		state[&"near_miss_closest"] = INF
		state[&"velocity"] = Vector3.ZERO
		state[&"previous_position"] = Vector3.ZERO
		state[&"surface_y"] = 0.0
		state[&"surface_vertical_speed"] = 0.0
		state[&"surface_supported"] = true
		state[&"surface_initialized"] = false
		state[&"finished"] = false
		state[&"status"] = &"RUNNING"
		state[&"elimination_lap"] = -1
		state[&"laps_completed"] = 0
		state[&"lap_start_elapsed"] = 0.0
		state[&"lap_times_usec"] = []
		state[&"best_lap_usec"] = -1
		state[&"last_lap_usec"] = -1
		state[&"finish_usec"] = -1
		state[&"penalty_usec"] = 0
		state[&"mistake_event"] = 0
		state[&"mistake_time"] = 1.4 + _event_unit(index, 0, 17.3) * 2.2
		state[&"mistake_factor"] = 1.0
		state[&"jump_plan"] = &"ROLL"
		state[&"preload"] = 0.0
		state[&"landing_quality"] = 1.0
		state[&"landing_event"] = false
		state[&"was_supported"] = true
		state[&"overtakes"] = 0
		state[&"contacts"] = 0
		state[&"crashes"] = 0
		root.visible = true
		var visual := state[&"visual"] as Node3D
		if presentation_enabled and visual.has_method(&"apply_pack_identity"):
			visual.call(&"apply_pack_identity", profile.get(&"bike", Color.WHITE), profile.get(&"helmet", Color.WHITE), int(profile.get(&"number", index + 2)))
		elif presentation_enabled and visual.has_method(&"apply_pack_colors"):
			visual.call(&"apply_pack_colors", profile.get(&"bike", Color.WHITE), profile.get(&"helmet", Color.WHITE))
		_riders[index] = state
		if presentation_enabled:
			_update_rider(index, 0.0)
	_reset_pair_orders()
	_reset_player_pair_orders()
	_update_launch_clearance_metrics()


func start_race() -> void:
	if _track_points.size() >= 2:
		visible = true
		_active = true
		_race_elapsed = 0.0


func stop_race() -> void:
	_active = false
	_clear_player_racecraft_context()


func simulate_competition_step(
	delta: float,
	player_speed: float,
	player_total_progress: float,
	resolve_traffic: bool = true
) -> void:
	## Fast deterministic race-logic path for dedicated simulation, balance
	## auditing, and server adjudication. It uses the same rider integration and
	## traffic code as gameplay without rendering, audio, or physics queries.
	if not _active or delta <= 0.0 or _track_length <= 0.0:
		return
	_race_elapsed += delta
	_player_speed_snapshot = maxf(player_speed, 0.0)
	if player_total_progress >= 0.0 and _player_status != &"ELIMINATED":
		var previous_player_laps := _player_laps_completed
		var total_distance := _track_length * float(_total_laps)
		var bounded_total := clampf(player_total_progress, 0.0, total_distance)
		_player_laps_completed = mini(
			floori(bounded_total / maxf(_track_length, 0.001)),
			_total_laps - 1
		)
		_player_progress = bounded_total - float(_player_laps_completed) * _track_length
		if bounded_total >= total_distance - 0.001:
			_player_laps_completed = _total_laps - 1
			_player_progress = _track_length
		_player_total_progress_m = bounded_total
		for completed_lap: int in range(previous_player_laps + 1, _player_laps_completed + 1):
			_record_rider_lap_completed(&"PLAYER", completed_lap)
	for rider_index: int in _riders.size():
		_integrate_rider_state(rider_index, player_speed, delta)
	_resolve_pending_eliminations()
	if resolve_traffic:
		_resolve_rider_pairs()
		_apply_player_traffic_plans()
	_update_player_racecraft_context(delta)


func hide_pack() -> void:
	_active = false
	visible = false
	_clear_player_racecraft_context()


func _physics_process(delta: float) -> void:
	if not _active:
		return
	_surface_queries_this_tick = 0
	_race_elapsed += delta
	_contact_immunity_time = maxf(_contact_immunity_time - delta, 0.0)
	_global_contact_cooldown = maxf(_global_contact_cooldown - delta, 0.0)
	_player_sample_time -= delta
	if _player_sample_time <= 0.0:
		_update_player_progress()
		_player_sample_time = 0.1
	var player_speed := _player.get_speed_mps() if is_instance_valid(_player) else 12.0
	_player_speed_snapshot = maxf(player_speed, 0.0)

	for index: int in _riders.size():
		_integrate_rider_state(index, player_speed, delta)
	_resolve_pending_eliminations()
	# Player elimination is settled synchronously by RaceController. Do not run
	# traffic, visual, or contact work after that callback has stopped the pack.
	if not _active:
		return
	_resolve_rider_pairs()
	_resolve_player_pair_orders()
	_apply_player_traffic_plans()
	for index: int in _riders.size():
		_update_rider(index, delta)
	_surface_queries_peak = maxi(_surface_queries_peak, _surface_queries_this_tick)
	_update_launch_clearance_metrics()
	_resolve_player_proximity(delta)
	_update_player_racecraft_context(delta)
	_update_density_metrics(delta)
	_update_holeshot()
	_update_audio_pool(delta)


func get_pace_snapshot() -> Dictionary:
	var minimum_speed := INF
	var maximum_speed := 0.0
	var field_position := 1
	var nearest_ahead := INF
	var nearest_behind := INF
	for state: Dictionary in _riders:
		if not bool(state.get(&"active", true)):
			continue
		minimum_speed = minf(minimum_speed, float(state.get(&"speed", 0.0)))
		maximum_speed = maxf(maximum_speed, float(state.get(&"speed", 0.0)))
		if bool(state.get(&"finished", false)):
			# A rider already across the line stays ahead in the classification.
			field_position += 1
			continue
		var progress_gap := _state_total_progress(state) - _player_total_progress()
		if progress_gap > 0.35:
			field_position += 1
			nearest_ahead = minf(nearest_ahead, progress_gap)
		elif progress_gap < -0.35:
			nearest_behind = minf(nearest_behind, -progress_gap)
	if minimum_speed == INF:
		minimum_speed = 0.0
	return {
		&"minimum": minimum_speed,
		&"maximum": maximum_speed,
		&"player": _player.get_speed_mps() if is_instance_valid(_player) else 0.0,
		&"player_progress": _player_progress,
		&"player_total_progress": _player_total_progress(),
		&"field_position": clampi(field_position, 1, _active_rider_count + 1),
		&"field_size": _active_rider_count + 1,
		&"gap_ahead": -1.0 if nearest_ahead == INF else nearest_ahead,
		&"gap_behind": -1.0 if nearest_behind == INF else nearest_behind,
	}


func get_chaos_snapshot() -> Dictionary:
	var current_min_lane := INF
	var current_max_lane := -INF
	var active_count := 0
	var wobbling_count := 0
	var crashed_count := 0
	var recovering_count := 0
	var passing_count := 0
	var defending_count := 0
	var close_attacking_count := 0
	for state: Dictionary in _riders:
		if not bool(state.get(&"active", true)) or bool(state.get(&"finished", false)):
			continue
		active_count += 1
		var lane := float(state.get(&"lane", 0.0))
		current_min_lane = minf(current_min_lane, lane)
		current_max_lane = maxf(current_max_lane, lane)
		match int(state.get(&"mode", RiderMode.RIDING)):
			RiderMode.WOBBLE:
				wobbling_count += 1
			RiderMode.CRASHED:
				crashed_count += 1
			RiderMode.RECOVERING:
				recovering_count += 1
		if float(state.get(&"traffic_plan_time", 0.0)) > 0.0:
			match StringName(state.get(&"traffic_plan_kind", &"")):
				&"PASS":
					passing_count += 1
				&"DEFEND":
					defending_count += 1
		if bool(state.get(&"close_attack_active", false)):
			close_attacking_count += 1
	var current_lane_span := 0.0 if active_count == 0 else current_max_lane - current_min_lane
	var minimum_clearance := float(_chaos_metrics.get(&"minimum_player_clearance", INF))
	if minimum_clearance == INF:
		minimum_clearance = -1.0
	var field_overtakes := int(_chaos_metrics.get(&"field_overtakes", 0))
	var field_contacts := int(_chaos_metrics.get(&"field_contacts", 0))
	var field_crashes := int(_chaos_metrics.get(&"field_crashes", 0))
	var field_recoveries := int(_chaos_metrics.get(&"field_recoveries", 0))
	var speed_bias_samples := int(_chaos_metrics.get(&"speed_bias_samples", 0))
	var recovery_minimum := float(_chaos_metrics.get(&"recovery_minimum_seconds", INF))
	var section_minimum := float(_chaos_metrics.get(&"section_minimum_factor", INF))
	return {
		&"riders": _active_rider_count,
		&"active": active_count,
		&"lane_limit": _racecraft_lane_limit,
		&"central_lane_limit": _lane_limit,
		&"racecraft_lane_limit": _racecraft_lane_limit,
		&"lane_span": current_lane_span,
		&"peak_lane_span": float(_chaos_metrics.get(&"peak_lane_span", 0.0)),
		&"lane_changes": int(_chaos_metrics.get(&"lane_changes", 0)),
		&"racecraft_line_commits": int(_chaos_metrics.get(&"racecraft_line_commits", 0)),
		&"field_overtakes": field_overtakes,
		&"field_contacts": field_contacts,
		&"field_crashes": field_crashes,
		&"field_recoveries": field_recoveries,
		# Transitional aliases remain for pack-presentation probes. Competitive
		# player results consume PlayerRaceMetrics and never read these counters.
		&"overtakes": field_overtakes,
		&"npc_contacts": field_contacts,
		&"player_contacts": int(_chaos_metrics.get(&"player_contacts", 0)),
		&"near_misses": int(_chaos_metrics.get(&"near_misses", 0)),
		&"player_near_misses": int(_chaos_metrics.get(&"near_misses", 0)),
		&"crashes": field_crashes,
		&"recoveries": field_recoveries,
		&"mistakes": int(_chaos_metrics.get(&"mistakes", 0)),
		&"cases": int(_chaos_metrics.get(&"cases", 0)),
		&"landing_errors": int(_chaos_metrics.get(&"landing_errors", 0)),
		&"passing": passing_count,
		&"defending": defending_count,
		&"close_attacking": close_attacking_count,
		&"pass_plans": int(_chaos_metrics.get(&"pass_plans", 0)),
		&"pass_plan_refreshes": int(_chaos_metrics.get(&"pass_plan_refreshes", 0)),
		&"passing_intent_seconds": float(_chaos_metrics.get(&"passing_intent_seconds", 0.0)),
		&"defensive_moves": int(_chaos_metrics.get(&"defensive_moves", 0)),
		&"defense_plan_refreshes": int(_chaos_metrics.get(&"defense_plan_refreshes", 0)),
		&"defense_intent_seconds": float(_chaos_metrics.get(&"defense_intent_seconds", 0.0)),
		&"close_attack_activations": int(_chaos_metrics.get(&"close_attack_activations", 0)),
		&"close_attack_seconds": float(_chaos_metrics.get(&"close_attack_seconds", 0.0)),
		&"close_attack_peak_mps": float(_chaos_metrics.get(&"close_attack_peak_mps", 0.0)),
		&"ai_draft_seconds": float(_chaos_metrics.get(&"ai_draft_seconds", 0.0)),
		&"ai_draft_peak": float(_chaos_metrics.get(&"ai_draft_peak", 0.0)),
		&"player_draft_seconds": float(_chaos_metrics.get(&"player_draft_seconds", 0.0)),
		&"player_draft_peak": float(_chaos_metrics.get(&"player_draft_peak", 0.0)),
		&"player_roost_pressure_peak": float(_chaos_metrics.get(&"player_roost_pressure_peak", 0.0)),
		&"player_roost_defense_peak": float(_chaos_metrics.get(&"player_roost_defense_peak", 0.0)),
		&"player_roost_hits": int(_chaos_metrics.get(&"player_roost_hits", 0)),
		&"player_roost_wobbles": int(_chaos_metrics.get(&"player_roost_wobbles", 0)),
		&"player_roost_drive_cost_sum": float(_chaos_metrics.get(&"player_roost_drive_cost_sum", 0.0)),
		&"late_pressure_seconds": float(_chaos_metrics.get(&"late_pressure_seconds", 0.0)),
		&"late_pressure_peak_mps": float(_chaos_metrics.get(&"late_pressure_peak_mps", 0.0)),
		&"speed_bias_samples": speed_bias_samples,
		&"speed_bias_mean_mps": (
			float(_chaos_metrics.get(&"speed_bias_signed_sum_mps", 0.0)) / float(speed_bias_samples)
			if speed_bias_samples > 0
			else 0.0
		),
		&"speed_bias_mean_absolute_mps": (
			float(_chaos_metrics.get(&"speed_bias_absolute_sum_mps", 0.0)) / float(speed_bias_samples)
			if speed_bias_samples > 0
			else 0.0
		),
		&"speed_bias_peak_absolute_mps": float(_chaos_metrics.get(&"speed_bias_peak_absolute_mps", 0.0)),
		&"line_advantage_seconds": float(_chaos_metrics.get(&"line_advantage_seconds", 0.0)),
		&"downhill_momentum_seconds": float(_chaos_metrics.get(&"downhill_momentum_seconds", 0.0)),
		&"wet_skill_seconds": float(_chaos_metrics.get(&"wet_skill_seconds", 0.0)),
		&"jump_attack_seconds": float(_chaos_metrics.get(&"jump_attack_seconds", 0.0)),
		&"skill_line_mastered_seconds": float(_chaos_metrics.get(&"skill_line_mastered_seconds", 0.0)),
		&"skill_line_clean_seconds": float(_chaos_metrics.get(&"skill_line_clean_seconds", 0.0)),
		&"skill_line_scrambled_seconds": float(_chaos_metrics.get(&"skill_line_scrambled_seconds", 0.0)),
		&"skill_line_missed_seconds": float(_chaos_metrics.get(&"skill_line_missed_seconds", 0.0)),
		&"section_minimum_factor": section_minimum if is_finite(section_minimum) else -1.0,
		&"section_maximum_factor": float(_chaos_metrics.get(&"section_maximum_factor", 0.0)),
		&"jump_safe_commits": int(_chaos_metrics.get(&"jump_safe_commits", 0)),
		&"jump_send_commits": int(_chaos_metrics.get(&"jump_send_commits", 0)),
		&"jump_scrub_commits": int(_chaos_metrics.get(&"jump_scrub_commits", 0)),
		&"crash_downtime_planned_seconds": float(_chaos_metrics.get(&"crash_downtime_planned_seconds", 0.0)),
		&"recovery_downtime_planned_seconds": float(_chaos_metrics.get(&"recovery_downtime_planned_seconds", 0.0)),
		&"recovery_minimum_seconds": recovery_minimum if is_finite(recovery_minimum) else -1.0,
		&"recovery_maximum_seconds": float(_chaos_metrics.get(&"recovery_maximum_seconds", 0.0)),
		&"recovery_lane_changes": int(_chaos_metrics.get(&"recovery_lane_changes", 0)),
		&"wobbling": wobbling_count,
		&"crashed": crashed_count,
		&"recovering": recovering_count,
		&"minimum_player_clearance": minimum_clearance,
		&"close_traffic_seconds": float(_chaos_metrics.get(&"close_traffic_seconds", 0.0)),
		&"launch_lock_seconds": LAUNCH_LANE_LOCK_SECONDS,
		&"launch_blend_seconds": LAUNCH_TACTICS_BLEND_SECONDS,
		&"launch_tactics_blend": _launch_tactics_blend(),
		&"launch_max_lane_displacement": float(_chaos_metrics.get(&"launch_max_lane_displacement", 0.0)),
		&"launch_max_lateral_speed": float(_chaos_metrics.get(&"launch_max_lateral_speed", 0.0)),
		&"launch_first_lateral_motion_time": float(_chaos_metrics.get(&"launch_first_lateral_motion_time", -1.0)),
		&"launch_first_tactical_time": float(_chaos_metrics.get(&"launch_first_tactical_time", -1.0)),
		&"launch_max_blend_lateral_acceleration": float(_chaos_metrics.get(&"launch_max_blend_lateral_acceleration", 0.0)),
		&"launch_min_acceleration_scale": _finite_clearance_metric(&"launch_min_acceleration_scale"),
		&"launch_max_acceleration_scale": float(_chaos_metrics.get(&"launch_max_acceleration_scale", 0.0)),
		&"launch_max_heading_error_degrees": float(_chaos_metrics.get(&"launch_max_heading_error_degrees", 0.0)),
		&"launch_max_heading_step_degrees": float(_chaos_metrics.get(&"launch_max_heading_step_degrees", 0.0)),
		&"launch_min_npc_clearance": _finite_clearance_metric(&"launch_min_npc_clearance"),
		&"launch_min_player_clearance": _finite_clearance_metric(&"launch_min_player_clearance"),
		&"surface_minimum_clearance": _finite_clearance_metric(&"surface_minimum_clearance"),
		&"surface_maximum_air_height": float(_chaos_metrics.get(&"surface_maximum_air_height", 0.0)),
		&"surface_launches": int(_chaos_metrics.get(&"surface_launches", 0)),
		&"surface_landings": int(_chaos_metrics.get(&"surface_landings", 0)),
		&"pair_separation_corrections": int(_chaos_metrics.get(&"pair_separation_corrections", 0)),
		&"maximum_pair_separation_step": float(_chaos_metrics.get(&"maximum_pair_separation_step", 0.0)),
		&"surface_queries_this_tick": _surface_queries_this_tick,
		&"surface_queries_peak": _surface_queries_peak,
	}


func get_player_interaction_snapshot() -> Dictionary:
	var snapshot := _player_racecraft_context.duplicate(true)
	snapshot.merge({
		&"contacts": int(_chaos_metrics.get(&"player_contacts", 0)),
		&"near_misses": int(_chaos_metrics.get(&"near_misses", 0)),
	}, true)
	return snapshot


func _empty_player_racecraft_context() -> Dictionary:
	return {
		&"draft_strength": 0.0,
		&"draft_target": &"",
		&"roost_pressure": 0.0,
		&"roost_source": &"",
		&"contact_pressure": 0.0,
		&"trailing_target": &"",
		&"trailing_distance_m": -1.0,
		&"roost_defense": 0.0,
		&"roost_defense_active": false,
	}


func _clear_player_racecraft_context() -> void:
	_player_racecraft_context = _empty_player_racecraft_context()
	if is_instance_valid(_player) and _player.has_method(&"set_pack_racecraft_context"):
		_player.call(&"set_pack_racecraft_context", _player_racecraft_context.duplicate(true))


func _update_player_racecraft_context(delta: float) -> void:
	var context := _empty_player_racecraft_context()
	if not is_instance_valid(_player) and not simulation_has_player:
		_player_racecraft_context = context
		return
	var player_pose := _player_racecraft_pose()
	var player_position: Vector3 = player_pose[&"position"]
	var player_forward: Vector3 = player_pose[&"forward"]
	var player_total := _player_total_progress()
	var player_snapshot := _read_player_racecraft_snapshot()
	var deliberate_roost := clampf(float(player_snapshot.get(&"deliberate_input", 0.0)), 0.0, 1.0)
	var best_draft := 0.0
	var best_roost_pressure := 0.0
	var best_trailing_draft := 0.0
	var trailing_index := -1
	var trailing_evaluation: Dictionary = {}

	for index: int in _riders.size():
		var state: Dictionary = _riders[index]
		if not bool(state.get(&"active", true)) or bool(state.get(&"finished", false)):
			continue
		var rider_total := _state_total_progress(state)
		var progress_gap := rider_total - player_total
		var rider_pose := _racecraft_pose_for_state(state)
		var rider_position: Vector3 = rider_pose[&"position"]
		var rider_forward: Vector3 = rider_pose[&"forward"]
		var lateral_gap := absf(float(state.get(&"lane", 0.0)) - _player_lane)
		var proximity_pressure := (
			(1.0 - smoothstep(1.2, 5.0, absf(progress_gap)))
			* (1.0 - smoothstep(0.7, 2.5, lateral_gap))
		)
		context[&"contact_pressure"] = maxf(float(context[&"contact_pressure"]), proximity_pressure)

		if progress_gap > 0.35 and progress_gap <= RACECRAFT_RULES.DRAFT_MAX_DISTANCE + 1.0:
			var draft_strength := RACECRAFT_RULES.draft_strength(
				player_position,
				player_forward,
				rider_position,
				rider_forward
			)
			if draft_strength > best_draft:
				best_draft = draft_strength
				context[&"draft_target"] = StringName(state.get(&"rider_id", &"NPC"))
			if draft_strength > 0.0:
				var separation := rider_position - player_position
				var distance := separation.length()
				var alignment := player_forward.dot(separation.normalized()) if distance > 0.001 else 0.0
				var npc_roost := _npc_roost_snapshot(state)
				var evaluation := RACECRAFT_RULES.evaluate_roost(
					StringName(npc_roost[&"surface"]),
					float(npc_roost[&"rear_slip"]),
					float(npc_roost[&"throttle"]),
					distance,
					alignment
				)
				var pressure := float(evaluation[&"pressure"])
				if pressure > best_roost_pressure:
					best_roost_pressure = pressure
					context[&"roost_source"] = StringName(state.get(&"rider_id", &"NPC"))
		elif progress_gap < -0.35 and -progress_gap <= RACECRAFT_RULES.DRAFT_MAX_DISTANCE + 1.0:
			var trailing_draft := RACECRAFT_RULES.draft_strength(
				rider_position,
				rider_forward,
				player_position,
				player_forward
			)
			if trailing_draft > best_trailing_draft:
				var separation_to_player := player_position - rider_position
				var trailing_distance := separation_to_player.length()
				var trailing_alignment := (
					rider_forward.dot(separation_to_player.normalized())
					if trailing_distance > 0.001
					else 0.0
				)
				best_trailing_draft = trailing_draft
				trailing_index = index
				context[&"trailing_target"] = StringName(state.get(&"rider_id", &"NPC"))
				context[&"trailing_distance_m"] = trailing_distance
				trailing_evaluation = RACECRAFT_RULES.evaluate_roost(
					StringName(player_snapshot.get(&"surface", &"DIRT")),
					float(player_snapshot.get(&"rear_slip", 0.0)),
					float(player_snapshot.get(&"throttle", 0.0)),
					trailing_distance,
					trailing_alignment,
					deliberate_roost
				)

	context[&"draft_strength"] = clampf(best_draft, 0.0, 1.0)
	context[&"roost_pressure"] = clampf(best_roost_pressure, 0.0, 1.0)
	if not trailing_evaluation.is_empty():
		context[&"roost_defense"] = clampf(
			float(trailing_evaluation.get(&"pressure", 0.0)) * deliberate_roost,
			0.0,
			1.0
		)
	context[&"roost_defense_active"] = float(context[&"roost_defense"]) > 0.08
	_apply_player_roost_to_trailer(trailing_index, trailing_evaluation, deliberate_roost)
	_player_racecraft_context = context

	if best_draft > 0.01:
		_chaos_metrics[&"player_draft_seconds"] = float(
			_chaos_metrics.get(&"player_draft_seconds", 0.0)
		) + maxf(delta, 0.0)
	_chaos_metrics[&"player_draft_peak"] = maxf(
		float(_chaos_metrics.get(&"player_draft_peak", 0.0)),
		best_draft
	)
	_chaos_metrics[&"player_roost_pressure_peak"] = maxf(
		float(_chaos_metrics.get(&"player_roost_pressure_peak", 0.0)),
		best_roost_pressure
	)
	_chaos_metrics[&"player_roost_defense_peak"] = maxf(
		float(_chaos_metrics.get(&"player_roost_defense_peak", 0.0)),
		float(context[&"roost_defense"])
	)
	if is_instance_valid(_player) and _player.has_method(&"set_pack_racecraft_context"):
		_player.call(&"set_pack_racecraft_context", context.duplicate(true))


func _apply_player_roost_to_trailer(
	rider_index: int,
	evaluation: Dictionary,
	deliberate_input: float
) -> void:
	if rider_index < 0 or rider_index >= _riders.size() or evaluation.is_empty():
		return
	var pressure := clampf(float(evaluation.get(&"pressure", 0.0)) * deliberate_input, 0.0, 1.0)
	if pressure <= 0.08:
		return
	var state: Dictionary = _riders[rider_index]
	state[&"roost_pressure"] = maxf(float(state.get(&"roost_pressure", 0.0)), pressure)
	if float(state.get(&"roost_cooldown", 0.0)) > 0.0:
		_riders[rider_index] = state
		return
	var drive_cost := minf(float(evaluation.get(&"drive_cost_fraction", 0.0)), PLAYER_ROOST_MAX_DRIVE_COST)
	state[&"speed"] = maxf(float(state.get(&"speed", 0.0)) * (1.0 - drive_cost), 2.0)
	state[&"roost_drive_multiplier"] = 1.0 - drive_cost
	state[&"roost_cooldown"] = PLAYER_ROOST_COOLDOWN_SECONDS
	_increment_metric(&"player_roost_hits")
	_chaos_metrics[&"player_roost_drive_cost_sum"] = float(
		_chaos_metrics.get(&"player_roost_drive_cost_sum", 0.0)
	) + drive_cost
	if is_instance_valid(_player) and _player.has_method(&"register_racecraft_success"):
		_player.call(&"register_racecraft_success", &"ROOST_DEFENSE", {
			&"rider_id": StringName(state.get(&"rider_id", &"NPC")),
			&"pressure": pressure,
			&"drive_cost_fraction": drive_cost,
		})
	var recovery_skill := clampf(float(state.get(&"recovery_skill", 0.8)), 0.0, 1.0)
	var wobble_threshold := lerpf(0.68, 0.90, recovery_skill)
	if pressure >= wobble_threshold and int(state.get(&"mode", RiderMode.RIDING)) == RiderMode.RIDING:
		var direction := -1.0 if rider_index % 2 == 0 else 1.0
		_enter_wobble(state, 1.0 + pressure * 1.4, direction)
		_increment_metric(&"player_roost_wobbles")
	_riders[rider_index] = state


func _read_player_racecraft_snapshot() -> Dictionary:
	var snapshot := {
		&"surface": &"DIRT",
		&"rear_slip": 0.0,
		&"throttle": 0.0,
		&"deliberate_input": 0.0,
	}
	if not is_instance_valid(_player):
		return snapshot
	var source: Dictionary = {}
	if _player.has_method(&"get_racecraft_snapshot"):
		var value: Variant = _player.call(&"get_racecraft_snapshot")
		if value is Dictionary:
			source = value
	elif _player.has_method(&"get_contact_feedback"):
		var feedback: Variant = _player.call(&"get_contact_feedback")
		if feedback is Dictionary:
			source = feedback
	if _player.has_method(&"get_active_surface"):
		snapshot[&"surface"] = StringName(_player.call(&"get_active_surface"))
	if _player.has_method(&"get_rear_slip"):
		snapshot[&"rear_slip"] = clampf(float(_player.call(&"get_rear_slip")), 0.0, 1.0)
	snapshot[&"surface"] = StringName(source.get(&"surface", snapshot[&"surface"]))
	snapshot[&"rear_slip"] = clampf(float(source.get(&"rear_slip", snapshot[&"rear_slip"])), 0.0, 1.0)
	snapshot[&"throttle"] = clampf(float(source.get(&"throttle", 0.0)), 0.0, 1.0)
	var deliberate := float(source.get(&"deliberate_input", source.get(&"slide_strength", 0.0)))
	if bool(source.get(&"slide_active", false)):
		deliberate = maxf(deliberate, 1.0)
	var sideslip := absf(float(source.get(&"body_sideslip_angle", 0.0)))
	deliberate = maxf(deliberate, smoothstep(0.14, 0.50, sideslip))
	snapshot[&"deliberate_input"] = clampf(deliberate, 0.0, 1.0)
	return snapshot


func _npc_roost_snapshot(state: Dictionary) -> Dictionary:
	var surface: StringName = &"DIRT"
	if _session_config.surface_modifier == &"MUD":
		surface = &"MUD"
	elif _session_config.surface_modifier == &"WET":
		surface = &"LOAM"
	var lateral_work := clampf(absf(float(state.get(&"lane_velocity", 0.0))) / LANE_CHANGE_SPEED, 0.0, 1.0)
	var landing_work := 1.0 - clampf(float(state.get(&"landing_quality", 1.0)), 0.0, 1.0)
	var wobble_work := 0.32 if int(state.get(&"mode", RiderMode.RIDING)) == RiderMode.WOBBLE else 0.0
	return {
		&"surface": surface,
		&"rear_slip": clampf(lateral_work * 0.72 + landing_work * 0.35 + wobble_work, 0.0, 1.0),
		&"throttle": smoothstep(4.0, 18.0, float(state.get(&"speed", 0.0))),
	}


func get_launch_snapshot() -> Dictionary:
	var chaos := get_chaos_snapshot()
	return {
		&"elapsed": _race_elapsed,
		&"lock_seconds": chaos[&"launch_lock_seconds"],
		&"blend_seconds": chaos[&"launch_blend_seconds"],
		&"tactics_blend": chaos[&"launch_tactics_blend"],
		&"max_lane_displacement": chaos[&"launch_max_lane_displacement"],
		&"max_lateral_speed": chaos[&"launch_max_lateral_speed"],
		&"first_lateral_motion_time": chaos[&"launch_first_lateral_motion_time"],
		&"first_tactical_time": chaos[&"launch_first_tactical_time"],
		&"max_blend_lateral_acceleration": chaos[&"launch_max_blend_lateral_acceleration"],
		&"minimum_acceleration_scale": chaos[&"launch_min_acceleration_scale"],
		&"maximum_acceleration_scale": chaos[&"launch_max_acceleration_scale"],
		&"max_heading_error_degrees": chaos[&"launch_max_heading_error_degrees"],
		&"max_heading_step_degrees": chaos[&"launch_max_heading_step_degrees"],
		&"minimum_npc_clearance": chaos[&"launch_min_npc_clearance"],
		&"minimum_player_clearance": chaos[&"launch_min_player_clearance"],
	}


func get_track_length() -> float:
	return _track_length


func get_grid_order_snapshot() -> Array[StringName]:
	var seeded: Array[Dictionary] = []
	for state: Dictionary in _riders:
		if bool(state.get(&"active", false)):
			seeded.append(state)
	seeded.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		var first_progress := float(first.get(&"progress", 0.0))
		var second_progress := float(second.get(&"progress", 0.0))
		if not is_equal_approx(first_progress, second_progress):
			return first_progress > second_progress
		return absf(float(first.get(&"lane", 0.0))) < absf(float(second.get(&"lane", 0.0)))
	)
	var order: Array[StringName] = []
	for state: Dictionary in seeded:
		order.append(StringName(state.get(&"rider_id", &"")))
	return order


func get_racer_snapshots() -> Array[Dictionary]:
	var snapshots: Array[Dictionary] = []
	for state: Dictionary in _riders:
		if not bool(state.get(&"active", true)):
			continue
		var root := state[&"root"] as Node3D
		var profile := state.get(&"profile", {}) as Dictionary
		var laps_completed := int(state.get(&"laps_completed", 0))
		var progress := float(state.get(&"progress", 0.0))
		snapshots.append({
			&"rider_id": StringName(state.get(&"rider_id", &"NPC")),
			&"display_name": str(state.get(&"display_name", "RIDER")),
			&"number": int(state.get(&"number", 0)),
			&"color": profile.get(&"bike", Color.WHITE),
			&"archetype": StringName(profile.get(&"archetype", &"ALL_ROUNDER")),
			&"signature_trait": str(profile.get(&"signature_trait", "CONSISTENT LAPS")),
			&"home_track": StringName(profile.get(&"home_track", &"MESA_MX")),
			&"is_player": false,
			&"status": StringName(state.get(&"status", &"RUNNING")),
			&"finished": bool(state.get(&"finished", false)),
			&"elimination_lap": int(state.get(&"elimination_lap", -1)),
			&"laps_completed": laps_completed,
			&"current_lap": mini(laps_completed + 1, _total_laps),
			&"total_laps": _total_laps,
			&"progress": progress,
			&"total_progress": _state_total_progress(state),
			&"finish_usec": int(state.get(&"finish_usec", -1)),
			&"penalty_usec": int(state.get(&"penalty_usec", 0)),
			&"best_lap_usec": int(state.get(&"best_lap_usec", -1)),
			&"last_lap_usec": int(state.get(&"last_lap_usec", -1)),
			&"speed_mps": float(state.get(&"speed", 0.0)),
			&"lane": float(state.get(&"lane", 0.0)),
			&"world_position": root.global_position,
			&"mode": int(state.get(&"mode", RiderMode.RIDING)),
			&"line": StringName(state.get(&"preferred_line", &"SAFE")),
			&"traffic_plan": StringName(state.get(&"traffic_plan_kind", &"")),
			&"traffic_plan_seconds": float(state.get(&"traffic_plan_time", 0.0)),
			&"speed_bias_mps": float(state.get(&"speed_bias", 0.0)),
			&"close_attack_mps": float(state.get(&"close_attack_mps", 0.0)),
			&"draft_strength": float(state.get(&"draft_strength", 0.0)),
			&"roost_pressure": float(state.get(&"roost_pressure", 0.0)),
			&"roost_drive_multiplier": float(state.get(&"roost_drive_multiplier", 1.0)),
			&"late_pressure_mps": float(state.get(&"late_pressure_mps", 0.0)),
			&"section_speed_factor": float(state.get(&"section_speed_factor", 1.0)),
			&"skill_line_outcome": StringName(state.get(&"skill_line_outcome", &"NONE")),
			&"skill_line_factor": float(state.get(&"skill_line_factor", 1.0)),
			&"launch_acceleration_scale": float(state.get(&"launch_acceleration_scale", 1.0)),
			&"recovery_skill": float(state.get(&"recovery_skill", 0.8)),
			&"last_crash_duration": float(state.get(&"last_crash_duration", 0.0)),
			&"last_recovery_duration": float(state.get(&"last_recovery_duration", 0.0)),
			&"jump_plan": StringName(state.get(&"jump_plan", &"ROLL")),
			&"landing_quality": float(state.get(&"landing_quality", 1.0)),
			&"overtakes": int(state.get(&"overtakes", 0)),
			&"contacts": int(state.get(&"contacts", 0)),
			&"crashes": int(state.get(&"crashes", 0)),
		})
	return snapshots


func get_classification_snapshot(include_player: bool = true) -> Array[Dictionary]:
	var classification := get_racer_snapshots()
	if include_player and (is_instance_valid(_player) or simulation_has_player):
		var player_world_position := Vector3.ZERO
		if is_instance_valid(_player):
			player_world_position = _player.global_position
		elif _track_points.size() >= 2:
			player_world_position = _track_position_for_distance(clampf(_player_progress, 0.0, _track_length))
		classification.append({
			&"rider_id": &"PLAYER",
			&"display_name": "YOU",
			&"number": 1,
			&"color": Color("ffb52d"),
			&"is_player": true,
			&"status": _player_status,
			&"finished": (
				_player_finish_usec >= 0
				or _player_status in [&"CLASSIFIED", &"DNF", &"DNS", &"ELIMINATED"]
			),
			&"elimination_lap": _player_elimination_lap,
			&"laps_completed": _player_laps_completed,
			&"current_lap": mini(_player_laps_completed + 1, _total_laps),
			&"total_laps": _total_laps,
			&"progress": _player_progress,
			&"total_progress": _player_total_progress(),
			&"finish_usec": _player_finish_usec,
			&"penalty_usec": _player_penalty_usec,
			&"best_lap_usec": -1,
			&"last_lap_usec": -1,
			&"speed_mps": _player.get_speed_mps() if is_instance_valid(_player) else _player_speed_snapshot,
			&"lane": _player_lane,
			&"world_position": player_world_position,
			&"mode": RiderMode.RIDING,
			&"line": &"PLAYER",
			&"jump_plan": &"PLAYER",
			&"landing_quality": 1.0,
		})
	classification.sort_custom(_classification_before)
	var leader_time := -1
	for index: int in classification.size():
		var racer: Dictionary = classification[index]
		racer[&"position"] = index + 1
		var finish_usec := int(racer.get(&"finish_usec", -1))
		var effective_usec := finish_usec + int(racer.get(&"penalty_usec", 0)) if finish_usec >= 0 else -1
		if leader_time < 0 and effective_usec >= 0:
			leader_time = effective_usec
		racer[&"effective_time_usec"] = effective_usec
		racer[&"gap_usec"] = maxi(effective_usec - leader_time, 0) if leader_time >= 0 and effective_usec >= 0 else -1
		classification[index] = racer
	return classification


func set_player_race_state(
	laps_completed: int,
	finish_usec: int = -1,
	penalty_usec: int = 0,
	status: StringName = &"RUNNING"
) -> void:
	# Once eliminated, the controller's normal per-frame RUNNING synchronization
	# must not resurrect the player before the synchronous result transition.
	if _player_status == &"ELIMINATED" and status != &"ELIMINATED":
		return
	var previous_laps := _player_laps_completed
	_player_laps_completed = clampi(laps_completed, 0, _total_laps)
	_player_finish_usec = finish_usec
	_player_penalty_usec = maxi(penalty_usec, 0)
	_player_status = status
	_player_total_progress_m = _resolve_player_total_progress(_player_progress)
	for completed_lap: int in range(previous_laps + 1, mini(_player_laps_completed, _total_laps - 1) + 1):
		_record_rider_lap_completed(&"PLAYER", completed_lap)


func record_player_finish(finish_usec: int, penalty_usec: int = 0) -> void:
	set_player_race_state(_total_laps, finish_usec, penalty_usec, &"FINISHED")


func all_riders_finished() -> bool:
	for state: Dictionary in _riders:
		if bool(state.get(&"active", true)) and not bool(state.get(&"finished", false)):
			return false
	return true


func mark_unfinished_dnf() -> void:
	for index: int in _riders.size():
		var state: Dictionary = _riders[index]
		if not bool(state.get(&"active", true)) or bool(state.get(&"finished", false)):
			continue
		state[&"finished"] = true
		state[&"status"] = &"DNF"
		state[&"speed"] = 0.0
		_riders[index] = state


func mark_running_classified() -> void:
	## Freeze surviving riders as legitimate classified finishers when the player
	## is knocked out. The ordinary timeout path remains DNF-only.
	for index: int in _riders.size():
		var state: Dictionary = _riders[index]
		if not bool(state.get(&"active", true)) or bool(state.get(&"finished", false)):
			continue
		state[&"finished"] = true
		state[&"status"] = &"CLASSIFIED"
		state[&"speed"] = 0.0
		_riders[index] = state
	if _player_status == &"RUNNING":
		_player_status = &"CLASSIFIED"


static func select_elimination_candidate(classification: Array[Dictionary]) -> StringName:
	## Pick the least-progressed active racer. Reverse rider-id ordering breaks an
	## exact progress tie because the normal classifier places the smaller id ahead.
	var candidate_id: StringName = &""
	var least_progress := INF
	for racer: Dictionary in classification:
		var status := StringName(racer.get(&"status", &"RUNNING"))
		if status in [&"FINISHED", &"CLASSIFIED", &"DNF", &"DNS", &"ELIMINATED"]:
			continue
		var rider_id := StringName(racer.get(&"rider_id", &""))
		if rider_id.is_empty():
			continue
		var progress := float(racer.get(&"total_progress", 0.0))
		if (
			progress < least_progress
			or (
				is_equal_approx(progress, least_progress)
				and String(rider_id) > String(candidate_id)
			)
		):
			least_progress = progress
			candidate_id = rider_id
	return candidate_id


func eliminate_rider(rider_id: StringName, elimination_lap: int) -> bool:
	var bounded_lap := clampi(elimination_lap, 1, maxi(_total_laps - 1, 1))
	if rider_id.is_empty() or _elimination_rounds.has(bounded_lap):
		return false
	if rider_id == &"PLAYER":
		if _player_status in [&"FINISHED", &"CLASSIFIED", &"DNF", &"DNS", &"ELIMINATED"]:
			return false
		_player_status = &"ELIMINATED"
		_player_finish_usec = -1
		_player_elimination_lap = bounded_lap
	else:
		var rider_index := -1
		for index: int in _riders.size():
			var state: Dictionary = _riders[index]
			if (
				bool(state.get(&"active", true))
				and not bool(state.get(&"finished", false))
				and StringName(state.get(&"rider_id", &"")) == rider_id
			):
				rider_index = index
				break
		if rider_index < 0:
			return false
		var eliminated: Dictionary = _riders[rider_index]
		eliminated[&"finished"] = true
		eliminated[&"status"] = &"ELIMINATED"
		eliminated[&"elimination_lap"] = bounded_lap
		eliminated[&"speed"] = 0.0
		_riders[rider_index] = eliminated
	_elimination_rounds[bounded_lap] = rider_id
	_last_eliminated_rider = rider_id
	rider_eliminated.emit(rider_id, bounded_lap)
	return true


func eliminate_last_rider() -> StringName:
	## Compatibility entry point. Production elimination rounds are queued from
	## lap crossings and resolved only after the complete field has integrated.
	var candidate := select_elimination_candidate(get_classification_snapshot())
	var round_lap := clampi(_highest_completed_lap(), 1, maxi(_total_laps - 1, 1))
	return candidate if eliminate_rider(candidate, round_lap) else &""


func get_elimination_snapshot() -> Dictionary:
	return {
		&"enabled": bool(_session_config.rules.get(&"eliminate_last_each_lap", false)),
		&"round_count": _elimination_rounds.size(),
		&"rounds": _elimination_rounds.duplicate(),
		&"pending_laps": _pending_elimination_laps.duplicate(),
		&"last_rider_id": _last_eliminated_rider,
		&"player_elimination_lap": _player_elimination_lap,
		&"player_status": _player_status,
	}


func _highest_completed_lap() -> int:
	var highest := _player_laps_completed
	for state: Dictionary in _riders:
		if bool(state.get(&"active", true)):
			highest = maxi(highest, int(state.get(&"laps_completed", 0)))
	return highest


func _record_rider_lap_completed(rider_id: StringName, completed_lap: int) -> void:
	if completed_lap <= 0 or completed_lap > _total_laps:
		return
	rider_lap_completed.emit(rider_id, completed_lap, _total_laps)
	if (
		bool(_session_config.rules.get(&"eliminate_last_each_lap", false))
		and completed_lap < _total_laps
		and not _elimination_rounds.has(completed_lap)
		and completed_lap not in _pending_elimination_laps
	):
		_pending_elimination_laps.append(completed_lap)


func _resolve_pending_eliminations() -> void:
	if _pending_elimination_laps.is_empty():
		return
	# NPC progress is integrated every physics tick, while the ordinary player
	# projection is intentionally sampled at 10 Hz. Refresh only at this rare
	# adjudication boundary so a close cutoff compares equally current positions.
	if is_instance_valid(_player):
		_update_player_progress()
	_pending_elimination_laps.sort()
	var rounds_to_resolve := _pending_elimination_laps.duplicate()
	_pending_elimination_laps.clear()
	for elimination_lap: int in rounds_to_resolve:
		if _elimination_rounds.has(elimination_lap):
			continue
		var candidate := select_elimination_candidate(get_classification_snapshot())
		if not candidate.is_empty():
			eliminate_rider(candidate, elimination_lap)
		if not _active:
			break


func set_contact_immunity(seconds: float) -> void:
	_contact_immunity_time = maxf(_contact_immunity_time, maxf(seconds, 0.0))


func resync_player_pass_tracking() -> void:
	if is_instance_valid(_player):
		_update_player_progress()
	_reset_player_pair_orders()


func get_holeshot_rider_id() -> StringName:
	return _holeshot_rider_id


func get_rider_roots() -> Array[Node3D]:
	var roots: Array[Node3D] = []
	for state: Dictionary in _riders:
		if bool(state.get(&"active", true)):
			roots.append(state[&"root"] as Node3D)
	return roots


func get_competition_snapshot() -> Dictionary:
	return {
		&"event_id": _session_config.event_id,
		&"format": _session_config.format,
		&"difficulty": _session_config.difficulty,
		&"replay_hook": StringName(_retention_contract.get(&"replay_hook", &"")),
		&"elapsed": _race_elapsed,
		&"total_laps": _total_laps,
		&"track_length": _track_length,
		&"holeshot_rider_id": _holeshot_rider_id,
		&"tension": get_tension_snapshot(),
		&"classification": get_classification_snapshot(),
	}


func get_tension_snapshot() -> Dictionary:
	return {
		&"event_id": _session_config.event_id,
		&"difficulty": _session_config.difficulty,
		&"contract": _retention_contract.duplicate(true),
		&"authored_difficulty": _authored_difficulty,
		&"player_difficulty_mode": _player_difficulty_mode,
		&"mode_pace_scale": _mode_pace_scale,
		&"opponent_build_match_scale": _build_match_scale,
		&"skill_delta": _skill_delta,
		&"director_max_correction_mps": DIRECTOR_MAX_CORRECTION,
		&"legacy_max_correction_mps": LEGACY_DIRECTOR_MAX_CORRECTION,
		&"player_chase_adjustment_mps": get_gap_pace_adjustment(60.0, 0.5),
		&"field_chase_adjustment_mps": get_gap_pace_adjustment(-60.0, 0.5),
		&"final_player_chase_adjustment_mps": get_gap_pace_adjustment(60.0, 1.0),
		&"final_field_chase_adjustment_mps": get_gap_pace_adjustment(-60.0, 1.0),
		&"roster": get_grid_order_snapshot(),
	}


func _classification_before(first: Dictionary, second: Dictionary) -> bool:
	var first_finish := int(first.get(&"finish_usec", -1))
	var second_finish := int(second.get(&"finish_usec", -1))
	if first_finish >= 0 and second_finish >= 0:
		var first_effective := first_finish + int(first.get(&"penalty_usec", 0))
		var second_effective := second_finish + int(second.get(&"penalty_usec", 0))
		if first_effective != second_effective:
			return first_effective < second_effective
		return String(first.get(&"rider_id", &"")) < String(second.get(&"rider_id", &""))
	if first_finish >= 0:
		return true
	if second_finish >= 0:
		return false
	var first_status := StringName(first.get(&"status", &"RUNNING"))
	var second_status := StringName(second.get(&"status", &"RUNNING"))
	var first_active := first_status not in [&"DNF", &"DNS", &"ELIMINATED"]
	var second_active := second_status not in [&"DNF", &"DNS", &"ELIMINATED"]
	if first_active != second_active:
		return first_active
	var first_progress := float(first.get(&"total_progress", 0.0))
	var second_progress := float(second.get(&"total_progress", 0.0))
	if not is_equal_approx(first_progress, second_progress):
		return first_progress > second_progress
	return String(first.get(&"rider_id", &"")) < String(second.get(&"rider_id", &""))


func _integrate_rider_state(index: int, player_speed: float, delta: float) -> void:
	var state: Dictionary = _riders[index]
	if not bool(state.get(&"active", true)) or bool(state[&"finished"]):
		return
	var tactics_blend := _launch_tactics_blend()
	_update_mistake_state(index, state, delta)
	_update_jump_plan(index, state)
	state[&"contact_cooldown"] = maxf(float(state[&"contact_cooldown"]) - delta, 0.0)
	state[&"roost_cooldown"] = maxf(float(state.get(&"roost_cooldown", 0.0)) - delta, 0.0)
	state[&"roost_pressure"] = move_toward(float(state.get(&"roost_pressure", 0.0)), 0.0, delta * 2.5)
	state[&"roost_drive_multiplier"] = move_toward(
		float(state.get(&"roost_drive_multiplier", 1.0)),
		1.0,
		delta * 0.35
	)
	state[&"speed_event_time"] = float(state[&"speed_event_time"]) - delta
	if float(state[&"speed_event_time"]) <= 0.0:
		var speed_event := int(state[&"speed_event"]) + 1
		state[&"speed_event"] = speed_event
		# Pace noise is centered on zero so variation adds race texture without
		# silently lowering the whole field. Consistent riders receive a narrower
		# envelope and therefore preserve their authored pace more often.
		var speed_unit := _event_unit(index, speed_event, 5.1)
		var consistency := clampf(float(state.get(&"consistency", 0.8)), 0.0, 1.0)
		var pace_variance := (
			clampf(float(_retention_contract.get(&"pace_variance", 1.0)), 0.0, 1.25)
			if is_instance_valid(_player) or simulation_has_player
			else 1.0
		)
		var speed_amplitude := lerpf(1.45, 0.52, consistency) * pace_variance
		state[&"speed_bias"] = (speed_unit * 2.0 - 1.0) * speed_amplitude
		_record_speed_bias_sample(float(state[&"speed_bias"]))
		state[&"speed_event_time"] = (
			1.5 + _event_unit(index, speed_event, 9.7)
		) * lerpf(0.90, 1.12, consistency)

	state[&"decision_time"] = float(state[&"decision_time"]) - delta
	state[&"defense_cooldown"] = maxf(float(state.get(&"defense_cooldown", 0.0)) - delta, 0.0)
	var previous_plan_time := float(state[&"traffic_plan_time"])
	state[&"traffic_plan_time"] = maxf(previous_plan_time - delta, 0.0)
	if previous_plan_time > 0.0 and float(state[&"traffic_plan_time"]) <= 0.0:
		state[&"traffic_plan_kind"] = &""
	_record_tactical_intent_time(state, delta)
	if tactics_blend > 0.0 and float(state[&"decision_time"]) <= 0.0:
		_plan_reference_line(index, state)

	_update_mode(state, index, delta)
	var progress_gap := _state_total_progress(state) - _player_total_progress()
	var late_pressure_mps := _late_race_pressure_mps(state, progress_gap)
	var close_attack_mps := _close_trailing_attack_mps(index, state, player_speed)
	state[&"late_pressure_mps"] = late_pressure_mps
	state[&"close_attack_mps"] = close_attack_mps
	_record_pressure_metrics(state, late_pressure_mps, close_attack_mps, delta)
	var dynamic_base_speed := (
		float(state[&"base_speed"])
		+ float(state[&"speed_bias"])
		+ late_pressure_mps
		+ close_attack_mps
	)
	var target_speed := _target_speed_for_gap(dynamic_base_speed, player_speed, progress_gap, state)
	var section_speed_factor := _section_speed_factor(state)
	state[&"section_speed_factor"] = section_speed_factor
	_record_section_consequences(state, section_speed_factor, delta)
	target_speed *= section_speed_factor
	target_speed *= clampf(float(state.get(&"roost_drive_multiplier", 1.0)), 1.0 - PLAYER_ROOST_MAX_DRIVE_COST, 1.0)
	target_speed *= float(state.get(&"mistake_factor", 1.0))
	var settled_pace_blend := smoothstep(
		LAUNCH_LANE_LOCK_SECONDS + LAUNCH_TACTICS_BLEND_SECONDS,
		LAUNCH_LANE_LOCK_SECONDS + LAUNCH_TACTICS_BLEND_SECONDS + 1.5,
		_race_elapsed
	)
	# Academy opponents retain the authored teaching pace. Competitive fields
	# carry enough sustained speed to remain relevant once the player has learned
	# lines, upgrades and repeatable Flow Surge use.
	var settled_pace_scale := (
		ACADEMY_PACE_SCALE
		if _session_config.event_id == &"ACADEMY"
		else RACE_PACE_SCALE
	)
	target_speed *= lerpf(1.0, settled_pace_scale, settled_pace_blend)
	var acceleration := (
		LAUNCH_ACCELERATION * float(state.get(&"launch_acceleration_scale", 1.0))
		if _race_elapsed < LAUNCH_LANE_LOCK_SECONDS
		else 4.1
	)
	match int(state[&"mode"]):
		RiderMode.WOBBLE:
			target_speed = maxf(target_speed - 1.2, 4.5)
			acceleration = 4.8
		RiderMode.CRASHED:
			target_speed = minf(target_speed, 2.2)
			acceleration = 8.5
		RiderMode.RECOVERING:
			var recovery_skill := clampf(float(state.get(&"recovery_skill", 0.8)), 0.0, 1.0)
			target_speed = minf(target_speed, lerpf(7.2, 11.4, recovery_skill))
			acceleration = lerpf(3.5, 6.2, recovery_skill)
	state[&"speed"] = move_toward(float(state[&"speed"]), target_speed, acceleration * delta)

	var lane := float(state[&"lane"])
	var lane_velocity := float(state[&"lane_velocity"])
	var previous_lane_velocity := float(state[&"previous_lane_velocity"])
	if tactics_blend <= 0.0:
		# This is an exact hold, rather than a spring back to the slot, so no
		# one-frame lateral twitch can occur when GO changes the race state.
		lane = float(state[&"launch_lane"])
		lane_velocity = 0.0
		state[&"lane_target"] = lane
		state[&"lane_change_active"] = false
	elif int(state[&"mode"]) == RiderMode.CRASHED:
		lane_velocity = move_toward(lane_velocity, 0.0, 0.9 * delta)
	else:
		var lane_error := float(state[&"lane_target"]) - lane
		# Keep the first tactical move visually continuous even when launch-skill
		# differences compress two rows at the end of the lock. Full 2.25 m/s race
		# movement releases shortly after the tactical blend, never at one frame.
		var lane_speed_release := smoothstep(
			LAUNCH_LANE_LOCK_SECONDS,
			LAUNCH_LANE_LOCK_SECONDS + LAUNCH_TACTICS_BLEND_SECONDS + 1.5,
			_race_elapsed
		)
		var lane_speed_limit := LANE_CHANGE_SPEED * lane_speed_release
		var target_lane_velocity := clampf(
			lane_error * 2.4,
			-lane_speed_limit,
			lane_speed_limit
		) * tactics_blend
		lane_velocity = move_toward(lane_velocity, target_lane_velocity, LANE_ACCELERATION * delta)
	var racecraft_envelope_blend := smoothstep(
		LAUNCH_LANE_LOCK_SECONDS + LAUNCH_TACTICS_BLEND_SECONDS,
		LAUNCH_LANE_LOCK_SECONDS + LAUNCH_TACTICS_BLEND_SECONDS + 1.2,
		_race_elapsed
	)
	var motion_lane_limit := lerpf(_lane_limit, _racecraft_lane_limit, racecraft_envelope_blend)
	lane = clampf(lane + lane_velocity * delta, -motion_lane_limit, motion_lane_limit)
	if absf(lane) >= motion_lane_limit - 0.001 and signf(lane_velocity) == signf(lane):
		lane_velocity = 0.0
	state[&"lane"] = lane
	state[&"lane_velocity"] = lane_velocity
	state[&"previous_lane_velocity"] = lane_velocity
	_update_launch_motion_metrics(state, previous_lane_velocity, delta)
	if (
		bool(state[&"lane_change_active"])
		and absf(float(state[&"lane_target"]) - lane) < 0.22
		and absf(lane_velocity) < 0.4
	):
		state[&"lane_change_active"] = false

	var launch_delay := float(state[&"launch_delay"])
	var launch_ratio := smoothstep(launch_delay, launch_delay + LAUNCH_FORWARD_RAMP_SECONDS, _race_elapsed)
	# Per-rider cadence variation is useful once racing, but applying it while
	# lanes are locked lets same-column rows visually compress into one another.
	var pace_wave := sin(_race_elapsed * 1.3 + float(state[&"phase"])) * 0.52 * tactics_blend
	state[&"progress"] = float(state[&"progress"]) + maxf(float(state[&"speed"]) + pace_wave, 0.0) * launch_ratio * delta
	var completed_lap := -1
	var finished_now := false
	if float(state[&"progress"]) >= _track_length - 0.05:
		state = _complete_rider_lap(index, state)
		completed_lap = int(state.get(&"laps_completed", 0))
		finished_now = bool(state.get(&"finished", false))
	_riders[index] = state
	# Store the completed lap before notifying observers so classification and
	# elimination always see one coherent full-field state.
	if completed_lap >= 0:
		var rider_id := StringName(state.get(&"rider_id", &"NPC"))
		_record_rider_lap_completed(rider_id, completed_lap)
		if finished_now:
			rider_finished.emit(rider_id, int(state.get(&"finish_usec", -1)))


func _plan_reference_line(index: int, state: Dictionary) -> void:
	if int(state[&"mode"]) in [RiderMode.CRASHED, RiderMode.RECOVERING]:
		state[&"decision_time"] = 0.5
		return
	if float(state[&"traffic_plan_time"]) > 0.0:
		state[&"decision_time"] = 0.18
		return
	var event_index := int(state[&"decision_event"]) + 1
	state[&"decision_event"] = event_index
	state[&"decision_time"] = (
		0.45 + _event_unit(index, event_index, 3.3) * 0.35
	) * float(state.get(&"tactical_reaction_scale", 1.0))
	var progress := clampf(float(state[&"progress"]), 0.0, _track_length)
	var current_segment := _segment_for_distance(progress)
	var future_segment := _segment_for_distance(minf(progress + LINE_LOOK_AHEAD_METERS, _track_length))
	var tangent := _flat_tangent_for_segment(current_segment)
	var future_tangent := _flat_tangent_for_segment(future_segment)
	var signed_turn := tangent.cross(future_tangent).dot(Vector3.UP)
	var target_slot := 0
	var uses_racecraft_target := false
	var racecraft_target := 0.0
	if absf(signed_turn) > 0.055:
		var inside_sign := -1 if signed_turn > 0.0 else 1
		match StringName(state.get(&"preferred_line", &"SAFE")):
			&"AGGRESSIVE":
				if _launch_tactics_blend() >= 1.0:
					uses_racecraft_target = true
					racecraft_target = float(inside_sign) * _rut_lane_offset()
				else:
					target_slot = inside_sign * 2
			&"INSIDE":
				if _launch_tactics_blend() >= 1.0:
					uses_racecraft_target = true
					racecraft_target = float(inside_sign) * _rut_lane_offset()
				else:
					target_slot = inside_sign
			&"OUTSIDE":
				if _launch_tactics_blend() >= 1.0:
					uses_racecraft_target = true
					racecraft_target = float(-inside_sign) * _berm_lane_offset()
				else:
					target_slot = -inside_sign * 2
			_:
				target_slot = 0 if absf(signed_turn) > 0.22 else inside_sign
	else:
		match StringName(state.get(&"preferred_line", &"SAFE")):
			&"AGGRESSIVE":
				target_slot = -1 if _event_unit(index, event_index, 12.8) < 0.5 else 1
			&"INSIDE":
				target_slot = -1
			&"OUTSIDE":
				target_slot = 1
			_:
				target_slot = 0
	var preferred_target := (
		clampf(racecraft_target, -_racecraft_lane_limit, _racecraft_lane_limit)
		if uses_racecraft_target
		else clampf(float(target_slot) * LANE_SLOT_WIDTH, -_lane_limit, _lane_limit)
	)
	# If the preferred lane is occupied, evaluate the adjacent lane instead of
	# strafing through another bike to honor a personality label.
	var adjacent_target := clampf(preferred_target + (-LANE_SLOT_WIDTH if preferred_target >= 0.0 else LANE_SLOT_WIDTH), -_lane_limit, _lane_limit)
	if _lane_candidate_score(index, progress, adjacent_target) > _lane_candidate_score(index, progress, preferred_target) + 0.9:
		preferred_target = adjacent_target
	if uses_racecraft_target:
		_set_racecraft_lane_target(state, preferred_target)
	else:
		_set_lane_target(state, preferred_target)


func _resolve_rider_pairs() -> void:
	var tactics_blend := _launch_tactics_blend()
	for first_index: int in range(_riders.size() - 1):
		for second_index: int in range(first_index + 1, _riders.size()):
			var first: Dictionary = _riders[first_index]
			var second: Dictionary = _riders[second_index]
			if (
				not bool(first.get(&"active", true))
				or not bool(second.get(&"active", true))
				or bool(first[&"finished"])
				or bool(second[&"finished"])
			):
				continue
			var progress_gap := _state_total_progress(second) - _state_total_progress(first)
			var pair_key := first_index * RIDER_COUNT + second_index
			var order := 1 if progress_gap > 0.08 else -1 if progress_gap < -0.08 else 0
			var previous_order := int(_pair_orders.get(pair_key, order))
			if order != 0 and previous_order != 0 and order != previous_order:
				_increment_metric(&"field_overtakes")
				if order > previous_order:
					second[&"overtakes"] = int(second.get(&"overtakes", 0)) + 1
				else:
					first[&"overtakes"] = int(first.get(&"overtakes", 0)) + 1
			if order != 0:
				_pair_orders[pair_key] = order

			var longitudinal_gap := absf(progress_gap)
			var lateral_gap := absf(float(second[&"lane"]) - float(first[&"lane"]))
			var rear_index := first_index if progress_gap > 0.0 else second_index
			var front_index := second_index if progress_gap > 0.0 else first_index
			var rear: Dictionary = _riders[rear_index]
			var front: Dictionary = _riders[front_index]
			if longitudinal_gap <= FRONT_SENSOR_LENGTH and lateral_gap < FRONT_SENSOR_HALF_WIDTH:
				if tactics_blend > 0.0:
					var pass_lane := _choose_pass_lane(
						rear_index,
						float(rear[&"progress"]),
						float(front[&"lane"]),
						float(rear[&"aggression"])
					)
					var pass_hold := lerpf(
						PASS_INTENT_MIN_SECONDS,
						PASS_INTENT_MAX_SECONDS,
						clampf(float(rear[&"aggression"]), 0.0, 1.0)
					)
					_set_traffic_lane_target(rear, pass_lane, pass_hold, &"PASS")
				if lateral_gap < 1.05:
					# Queue in-lane behind the row ahead during the launch lock. This
					# prevents overlap without manufacturing a sideways avoidance move.
					var follow_allowance := (
						0.0
						if tactics_blend < 1.0
						else lerpf(0.72, 1.22, clampf(float(rear[&"aggression"]), 0.0, 1.0))
					)
					rear[&"speed"] = minf(float(rear[&"speed"]), float(front[&"speed"]) + follow_allowance)
				_riders[rear_index] = rear

			if tactics_blend >= 1.0 and longitudinal_gap < SIDE_SENSOR_LENGTH and lateral_gap < SIDE_SENSOR_WIDTH:
				var separation_sign := signf(float(first[&"lane"]) - float(second[&"lane"]))
				if is_zero_approx(separation_sign):
					separation_sign = -1.0 if (first_index + second_index) % 2 == 0 else 1.0
				first[&"lane_velocity"] = float(first[&"lane_velocity"]) + separation_sign * 0.55
				second[&"lane_velocity"] = float(second[&"lane_velocity"]) - separation_sign * 0.55

			if tactics_blend >= 1.0 and longitudinal_gap < NPC_VISUAL_LENGTH and lateral_gap < NPC_VISUAL_WIDTH:
				_resolve_pair_visual_overlap(first, second, progress_gap, first_index, second_index)

			var can_contact := (
				tactics_blend >= 1.0
				and longitudinal_gap < NPC_CONTACT_HALF_LENGTH
				and lateral_gap < NPC_CONTACT_HALF_WIDTH
				and float(first[&"contact_cooldown"]) <= 0.0
				and float(second[&"contact_cooldown"]) <= 0.0
				and int(first[&"mode"]) in [RiderMode.RIDING, RiderMode.WOBBLE]
				and int(second[&"mode"]) in [RiderMode.RIDING, RiderMode.WOBBLE]
			)
			if can_contact:
				var first_was_wobbling := int(first[&"mode"]) == RiderMode.WOBBLE
				var second_was_wobbling := int(second[&"mode"]) == RiderMode.WOBBLE
				var impact := (
					absf(float(first[&"speed"]) - float(second[&"speed"]))
					+ absf(float(first[&"lane_velocity"]) - float(second[&"lane_velocity"])) * 0.5
					+ 0.8
				)
				var contact_sign := signf(float(first[&"lane"]) - float(second[&"lane"]))
				if is_zero_approx(contact_sign):
					contact_sign = -1.0 if (pair_key + int(_race_elapsed * 2.0)) % 2 == 0 else 1.0
				first[&"lane_velocity"] = float(first[&"lane_velocity"]) + contact_sign * minf(impact * 0.38, 1.5)
				second[&"lane_velocity"] = float(second[&"lane_velocity"]) - contact_sign * minf(impact * 0.38, 1.5)
				first[&"contact_cooldown"] = PLAYER_CONTACT_COOLDOWN
				second[&"contact_cooldown"] = PLAYER_CONTACT_COOLDOWN
				first[&"contacts"] = int(first.get(&"contacts", 0)) + 1
				second[&"contacts"] = int(second.get(&"contacts", 0)) + 1
				_enter_wobble(first, impact, contact_sign)
				_enter_wobble(second, impact, -contact_sign)
				_increment_metric(&"field_contacts")
				var crash_roll := _event_unit(pair_key, int(_chaos_metrics[&"field_contacts"]), 11.2)
				if impact > 4.0 or ((first_was_wobbling or second_was_wobbling) and crash_roll < 0.38):
					if float(first[&"speed"]) >= float(second[&"speed"]):
						_enter_crash(first, first_index, impact, contact_sign)
					else:
						_enter_crash(second, second_index, impact, -contact_sign)
			_riders[first_index] = first
			_riders[second_index] = second


func _apply_player_traffic_plans() -> void:
	if not is_instance_valid(_player) and not simulation_has_player:
		return
	var tactics_blend := _launch_tactics_blend()
	if tactics_blend <= 0.0:
		return
	var player_speed := _player.get_speed_mps() if is_instance_valid(_player) else _player_speed_snapshot
	for index: int in _riders.size():
		var state: Dictionary = _riders[index]
		if (
			not bool(state.get(&"active", true))
			or bool(state[&"finished"])
			or int(state[&"mode"]) in [RiderMode.CRASHED, RiderMode.RECOVERING]
		):
			continue
		var player_gap := _player_total_progress() - _state_total_progress(state)
		var lateral_gap := absf(_player_lane - float(state[&"lane"]))
		if player_gap > 0.0 and player_gap < FRONT_SENSOR_LENGTH and lateral_gap < FRONT_SENSOR_HALF_WIDTH:
			var pass_hold := lerpf(
				PASS_INTENT_MIN_SECONDS,
				PASS_INTENT_MAX_SECONDS,
				clampf(float(state[&"aggression"]), 0.0, 1.0)
			)
			_set_traffic_lane_target(
				state,
				_choose_pass_lane(index, float(state[&"progress"]), _player_lane, float(state[&"aggression"])),
				pass_hold,
				&"PASS"
			)
		elif (
			tactics_blend >= 1.0
			and player_gap < -1.4
			and player_gap > -DEFENSE_SENSOR_LENGTH
			and player_speed > float(state[&"speed"]) + 0.45
			and float(state.get(&"defense_cooldown", 0.0)) <= 0.0
			and lateral_gap > 0.55
			and lateral_gap < FRONT_SENSOR_HALF_WIDTH + 1.2
		):
			# One measured move toward the closing rider's line. The lane delta and
			# cooldown prevent reactive mirroring or a last-moment horizontal ram.
			var defense_direction := signf(_player_lane - float(state[&"lane"]))
			var defense_move := minf(lateral_gap - 0.42, DEFENSE_MAX_LANE_MOVE)
			var defense_target := float(state[&"lane"]) + defense_direction * defense_move
			if _set_traffic_lane_target(state, defense_target, DEFENSE_INTENT_SECONDS, &"DEFEND"):
				var aggression := clampf(float(state.get(&"aggression", 0.6)), 0.0, 1.0)
				state[&"defense_cooldown"] = lerpf(
					DEFENSE_COOLDOWN_MAX_SECONDS,
					DEFENSE_COOLDOWN_MIN_SECONDS,
					aggression
				) * float(state.get(&"tactical_reaction_scale", 1.0))
		elif tactics_blend >= 1.0 and absf(player_gap) < SIDE_SENSOR_LENGTH and lateral_gap < SIDE_SENSOR_WIDTH:
			var side := signf(float(state[&"lane"]) - _player_lane)
			if is_zero_approx(side):
				side = -1.0 if index % 2 == 0 else 1.0
			state[&"lane_velocity"] = float(state[&"lane_velocity"]) + side * 0.35
		_riders[index] = state


func _choose_pass_lane(rider_index: int, progress: float, obstacle_lane: float, aggression: float) -> float:
	var clearance := lerpf(2.4, 1.3, clampf(aggression, 0.0, 1.0))
	var left_candidate := clampf(obstacle_lane - clearance, -_lane_limit, _lane_limit)
	var right_candidate := clampf(obstacle_lane + clearance, -_lane_limit, _lane_limit)
	var left_score := _lane_candidate_score(rider_index, progress, left_candidate)
	var right_score := _lane_candidate_score(rider_index, progress, right_candidate)
	if is_equal_approx(left_score, right_score):
		return left_candidate if _event_unit(rider_index, int(progress * 0.2), 14.6) < 0.5 else right_candidate
	return left_candidate if left_score > right_score else right_candidate


func _resolve_pair_visual_overlap(
	first: Dictionary,
	second: Dictionary,
	progress_gap: float,
	first_index: int,
	second_index: int
) -> void:
	var longitudinal_penetration := NPC_VISUAL_LENGTH - absf(progress_gap)
	var lane_delta := float(second[&"lane"]) - float(first[&"lane"])
	var lateral_penetration := NPC_VISUAL_WIDTH - absf(lane_delta)
	if longitudinal_penetration <= 0.0 or lateral_penetration <= 0.0:
		return
	var applied_step := 0.0
	if longitudinal_penetration <= lateral_penetration:
		# Queue the rear tyre just behind the bike ahead. Contact is detected
		# slightly before this point, so the correction remains sub-frame small.
		applied_step = minf(longitudinal_penetration + 0.015, NPC_MAX_SEPARATION_STEP)
		if progress_gap > 0.0:
			first[&"progress"] = float(first[&"progress"]) - applied_step
			first[&"speed"] = minf(float(first[&"speed"]), float(second[&"speed"]))
		else:
			second[&"progress"] = float(second[&"progress"]) - applied_step
			second[&"speed"] = minf(float(second[&"speed"]), float(first[&"speed"]))
	else:
		var separation_sign := signf(lane_delta)
		if is_zero_approx(separation_sign):
			separation_sign = -1.0 if (first_index + second_index) % 2 == 0 else 1.0
		applied_step = minf((lateral_penetration + 0.015) * 0.5, NPC_MAX_SEPARATION_STEP)
		first[&"lane"] = clampf(float(first[&"lane"]) - separation_sign * applied_step, -_lane_limit, _lane_limit)
		second[&"lane"] = clampf(float(second[&"lane"]) + separation_sign * applied_step, -_lane_limit, _lane_limit)
	_increment_metric(&"pair_separation_corrections")
	_chaos_metrics[&"maximum_pair_separation_step"] = maxf(
		float(_chaos_metrics[&"maximum_pair_separation_step"]),
		applied_step
	)


func _lane_candidate_score(rider_index: int, progress: float, candidate: float) -> float:
	var score := (_lane_limit - absf(candidate)) * 0.12
	for other_index: int in _riders.size():
		if other_index == rider_index:
			continue
		var other: Dictionary = _riders[other_index]
		if not bool(other.get(&"active", true)) or bool(other[&"finished"]):
			continue
		var reference_lap := int(_riders[rider_index].get(&"laps_completed", 0)) if rider_index >= 0 and rider_index < _riders.size() else 0
		var candidate_total := float(reference_lap) * _track_length + progress
		var progress_gap := absf(_state_total_progress(other) - candidate_total)
		if progress_gap > FRONT_SENSOR_LENGTH:
			continue
		score += minf(absf(float(other[&"lane"]) - candidate), 3.0) * (1.0 - progress_gap / FRONT_SENSOR_LENGTH)
	return score


func _resolve_player_proximity(delta: float) -> void:
	if not is_instance_valid(_player):
		return
	var player_position := _player.global_position
	for index: int in _riders.size():
		var state: Dictionary = _riders[index]
		if not bool(state.get(&"active", true)) or bool(state[&"finished"]):
			continue
		var root := state[&"root"] as Node3D
		var offset := player_position - root.global_position
		var height_gap := absf(offset.y)
		var planar_offset := Vector3(offset.x, 0.0, offset.z)
		var planar_distance := planar_offset.length()
		var minimum_clearance := float(_chaos_metrics[&"minimum_player_clearance"])
		_chaos_metrics[&"minimum_player_clearance"] = minf(minimum_clearance, planar_distance)

		if height_gap < PLAYER_CONTACT_HEIGHT and planar_distance < NEAR_MISS_DISTANCE:
			state[&"near_miss_pending"] = true
			state[&"near_miss_closest"] = minf(float(state[&"near_miss_closest"]), planar_distance)
		elif bool(state[&"near_miss_pending"]) and planar_distance > NEAR_MISS_EXIT_DISTANCE:
			if float(state[&"near_miss_closest"]) <= NEAR_MISS_DISTANCE:
				_increment_metric(&"near_misses")
			state[&"near_miss_pending"] = false
			state[&"near_miss_closest"] = INF

		var local_right := root.global_transform.basis.x.normalized()
		var local_forward := -root.global_transform.basis.z.normalized()
		var lateral_distance := absf(offset.dot(local_right))
		var longitudinal_distance := absf(offset.dot(local_forward))
		var contact_allowed := (
			height_gap < PLAYER_CONTACT_HEIGHT
			and lateral_distance < PLAYER_CONTACT_HALF_WIDTH
			and longitudinal_distance < PLAYER_CONTACT_HALF_LENGTH
			and float(state[&"contact_cooldown"]) <= 0.0
			and _global_contact_cooldown <= 0.0
			and _contact_immunity_time <= 0.0
			and int(state[&"mode"]) in [RiderMode.RIDING, RiderMode.WOBBLE]
		)
		if contact_allowed:
			var push_direction := planar_offset.normalized() if planar_distance > 0.05 else local_right
			var npc_velocity: Vector3 = state[&"velocity"]
			var relative_velocity := _player.linear_velocity - npc_velocity
			var closing_speed := maxf(-relative_velocity.dot(push_direction), 1.2)
			var contact_offset := Vector3.UP * 0.18 - push_direction * 0.2
			var contact_applied := false
			if _player.has_method(&"apply_pack_contact"):
				contact_applied = bool(_player.call(&"apply_pack_contact", push_direction, closing_speed, contact_offset))
			if contact_applied:
				state[&"contact_cooldown"] = PLAYER_CONTACT_COOLDOWN
				_global_contact_cooldown = GLOBAL_CONTACT_COOLDOWN
				state[&"near_miss_pending"] = false
				state[&"near_miss_closest"] = INF
				state[&"speed"] = maxf(float(state[&"speed"]) - closing_speed * 0.18, 2.0)
				state[&"contacts"] = int(state.get(&"contacts", 0)) + 1
				var lateral_push := push_direction.dot(local_right)
				var was_wobbling := int(state[&"mode"]) == RiderMode.WOBBLE
				if _launch_tactics_blend() >= 1.0:
					state[&"lane_velocity"] = float(state[&"lane_velocity"]) - lateral_push * minf(closing_speed * 0.32, 1.6)
					_enter_wobble(state, closing_speed, -lateral_push)
				else:
					# Longitudinal contact still pushes the physical player out of an
					# overlap, but the visual NPC keeps its launch column.
					state[&"lane"] = float(state[&"launch_lane"])
					state[&"lane_target"] = float(state[&"launch_lane"])
					state[&"lane_velocity"] = 0.0
				_increment_metric(&"player_contacts")
				if _launch_tactics_blend() >= 1.0 and (closing_speed > 5.5 or (was_wobbling and closing_speed > 2.5)):
					_enter_crash(state, index, closing_speed, -lateral_push)
		_riders[index] = state
	# Keep a deterministic metric even when the caller advances with unusual
	# frame sizes in a headless probe.
	_chaos_metrics[&"simulated_seconds"] = float(_chaos_metrics[&"simulated_seconds"]) + delta


func _update_mode(state: Dictionary, index: int, delta: float) -> void:
	var mode := int(state[&"mode"])
	var recovery_skill := clampf(float(state.get(&"recovery_skill", 0.8)), 0.0, 1.0)
	var mode_time := maxf(float(state[&"mode_time"]) - delta, 0.0)
	state[&"mode_time"] = mode_time
	var target_roll := 0.0
	match mode:
		RiderMode.WOBBLE:
			target_roll = sin(_race_elapsed * 17.0 + float(state[&"phase"])) * 0.18
			if mode_time <= 0.0:
				state[&"mode"] = RiderMode.RIDING
		RiderMode.CRASHED:
			target_roll = float(state[&"crash_sign"]) * 1.18
			if mode_time <= 0.0:
				state[&"mode"] = RiderMode.RECOVERING
				var recovery_duration := (
					lerpf(1.30, 0.62, recovery_skill)
					+ _event_unit(index, int(_chaos_metrics[&"field_crashes"]), 6.6)
					* lerpf(0.38, 0.16, recovery_skill)
				)
				state[&"mode_time"] = recovery_duration
				state[&"last_recovery_duration"] = recovery_duration
				_chaos_metrics[&"recovery_downtime_planned_seconds"] = float(
					_chaos_metrics.get(&"recovery_downtime_planned_seconds", 0.0)
				) + recovery_duration
				_chaos_metrics[&"recovery_minimum_seconds"] = minf(
					float(_chaos_metrics.get(&"recovery_minimum_seconds", INF)),
					recovery_duration
				)
				_chaos_metrics[&"recovery_maximum_seconds"] = maxf(
					float(_chaos_metrics.get(&"recovery_maximum_seconds", 0.0)),
					recovery_duration
				)
				var recovery_lane := _choose_recovery_lane(index, state)
				if absf(recovery_lane - float(state[&"lane"])) > 0.55:
					_increment_metric(&"recovery_lane_changes")
				state[&"lane_target"] = recovery_lane
		RiderMode.RECOVERING:
			target_roll = 0.0
			if mode_time <= 0.0:
				state[&"mode"] = RiderMode.RIDING
				state[&"contact_cooldown"] = maxf(float(state.get(&"contact_cooldown", 0.0)), 0.45)
				_increment_metric(&"field_recoveries")
	state[&"pose_roll"] = move_toward(
		float(state[&"pose_roll"]),
		target_roll,
		(2.8 if mode == RiderMode.CRASHED else 4.5) * delta
	)


func _enter_wobble(state: Dictionary, impact: float, direction: float) -> void:
	if int(state[&"mode"]) != RiderMode.RIDING:
		return
	state[&"mode"] = RiderMode.WOBBLE
	var recovery_skill := clampf(float(state.get(&"recovery_skill", 0.8)), 0.0, 1.0)
	state[&"mode_time"] = (
		0.65 + clampf(impact / 8.0, 0.0, 0.45)
	) * lerpf(1.08, 0.80, recovery_skill)
	if not is_zero_approx(direction):
		state[&"crash_sign"] = signf(direction)


func _enter_crash(state: Dictionary, rider_index: int, impact: float, direction: float) -> void:
	if int(state[&"mode"]) in [RiderMode.CRASHED, RiderMode.RECOVERING]:
		return
	var recovery_skill := clampf(float(state.get(&"recovery_skill", 0.8)), 0.0, 1.0)
	var crash_duration := (
		lerpf(1.55, 0.92, recovery_skill)
		+ _event_unit(rider_index, int(_chaos_metrics[&"field_crashes"]), 10.4)
		* lerpf(0.55, 0.24, recovery_skill)
	)
	state[&"mode"] = RiderMode.CRASHED
	state[&"mode_time"] = crash_duration
	state[&"last_crash_duration"] = crash_duration
	state[&"crash_sign"] = signf(direction) if not is_zero_approx(direction) else (-1.0 if rider_index % 2 == 0 else 1.0)
	state[&"speed"] = maxf(float(state[&"speed"]) * lerpf(0.46, 0.68, recovery_skill), 1.5)
	state[&"lane_velocity"] = (
		float(state[&"lane_velocity"])
		+ float(state[&"crash_sign"])
		* minf(1.1 + impact * 0.12, 2.0)
		* lerpf(1.0, 0.72, recovery_skill)
	)
	state[&"traffic_plan_time"] = 0.0
	state[&"traffic_plan_kind"] = &""
	state[&"close_attack_active"] = false
	state[&"crashes"] = int(state.get(&"crashes", 0)) + 1
	_chaos_metrics[&"crash_downtime_planned_seconds"] = float(
		_chaos_metrics.get(&"crash_downtime_planned_seconds", 0.0)
	) + crash_duration
	_increment_metric(&"field_crashes")


func _choose_recovery_lane(rider_index: int, state: Dictionary) -> float:
	var progress := clampf(float(state.get(&"progress", 0.0)), 0.0, _track_length)
	var current_lane := float(state.get(&"lane", 0.0))
	var candidates: Array[float] = [0.0]
	for slot_index: int in range(-2, 3):
		var candidate := clampf(float(slot_index) * LANE_SLOT_WIDTH, -_lane_limit, _lane_limit)
		if not candidates.has(candidate):
			candidates.append(candidate)
	var best_lane := clampf(roundf(current_lane / LANE_SLOT_WIDTH) * LANE_SLOT_WIDTH, -_lane_limit, _lane_limit)
	var best_score := -INF
	for candidate: float in candidates:
		var score := _lane_candidate_score(rider_index, progress, candidate) - absf(candidate - current_lane) * 0.08
		if score > best_score:
			best_score = score
			best_lane = candidate
	return best_lane


func _set_lane_target(state: Dictionary, target: float) -> void:
	var clamped_target := clampf(target, -_lane_limit, _lane_limit)
	if absf(clamped_target - float(state[&"lane"])) > 0.55 and not bool(state[&"lane_change_active"]):
		_increment_metric(&"lane_changes")
		state[&"lane_change_active"] = true
		if float(_chaos_metrics.get(&"launch_first_tactical_time", -1.0)) < 0.0:
			_chaos_metrics[&"launch_first_tactical_time"] = _race_elapsed
	state[&"lane_target"] = clamped_target


func _set_racecraft_lane_target(state: Dictionary, target: float) -> void:
	# Authored rut/berm targets are only legal after the full launch release.
	# Traffic plans continue to call _set_lane_target and therefore return riders
	# to the central pack envelope before attempting a pass or defensive move.
	if _launch_tactics_blend() < 1.0:
		_set_lane_target(state, target)
		return
	var clamped_target := clampf(target, -_racecraft_lane_limit, _racecraft_lane_limit)
	if absf(clamped_target - float(state[&"lane"])) > 0.55 and not bool(state[&"lane_change_active"]):
		state[&"lane_change_active"] = true
		_increment_metric(&"racecraft_line_commits")
	state[&"lane_target"] = clamped_target


func _rut_lane_offset() -> float:
	return minf(float(RUT_LANE_OFFSETS.get(_track_id, 1.10)), _racecraft_lane_limit)


func _berm_lane_offset() -> float:
	return minf(float(BERM_LANE_OFFSETS.get(_track_id, 7.50)), _racecraft_lane_limit)


func _set_traffic_lane_target(
	state: Dictionary,
	target: float,
	hold_seconds: float = PASS_INTENT_MIN_SECONDS,
	plan_kind: StringName = &"PASS"
) -> bool:
	var clamped_target := clampf(target, -_lane_limit, _lane_limit)
	var active_time := float(state.get(&"traffic_plan_time", 0.0))
	var active_kind := StringName(state.get(&"traffic_plan_kind", &""))
	var active_target := float(state.get(&"traffic_plan_target", state.get(&"lane_target", 0.0)))
	var bounded_hold := clampf(hold_seconds, 0.45, PASS_INTENT_MAX_SECONDS)
	if active_time > 0.0:
		if active_kind == plan_kind and absf(active_target - clamped_target) < 0.45:
			state[&"traffic_plan_time"] = maxf(active_time, bounded_hold)
			_increment_metric(&"pass_plan_refreshes" if plan_kind == &"PASS" else &"defense_plan_refreshes")
		return false
	_set_lane_target(state, clamped_target)
	state[&"traffic_plan_time"] = bounded_hold
	state[&"traffic_plan_kind"] = plan_kind
	state[&"traffic_plan_target"] = clamped_target
	if plan_kind == &"DEFEND":
		_increment_metric(&"defensive_moves")
	else:
		_increment_metric(&"pass_plans")
	return true


func _update_player_progress() -> void:
	if not is_instance_valid(_player) or _track_points.size() < 2:
		return
	var projection := CourseSpline.project_route(
		_track_points,
		_player.global_position,
		_distances,
		_player_projection_segment,
		60,
		_closed_route
	)
	if projection.is_empty():
		return
	_player_projection_segment = int(projection[&"segment"])
	_player_progress = clampf(float(projection[&"chainage"]), 0.0, _track_length)
	_player_total_progress_m = _resolve_player_total_progress(_player_progress)
	_player_lane = clampf(float(projection[&"lateral"]), -_racecraft_lane_limit, _racecraft_lane_limit)


func get_gap_pace_adjustment(progress_gap: float, race_completion: float = 0.5) -> float:
	return calculate_gap_pace_adjustment(_session_config, _retention_contract, progress_gap, race_completion)


static func calculate_gap_pace_adjustment(
	session_config: RaceSessionConfig,
	retention_contract: Dictionary,
	progress_gap: float,
	race_completion: float = 0.5
) -> float:
	# Positive gap means the field rider is ahead; negative means the player has
	# escaped. This director shapes a race without copying player velocity, and
	# fades before the flag so a deserved final-lap pass is never erased.
	if session_config == null or session_config.opponent_count <= 0:
		return 0.0
	var strength := clampf(float(retention_contract.get(&"tension_strength", 0.0)), 0.0, 1.25)
	if strength <= 0.0:
		return 0.0
	var close_gap := maxf(float(retention_contract.get(&"close_gap_m", 8.0)), 0.0)
	var breakaway_distance := maxf(float(retention_contract.get(&"breakaway_distance_m", 48.0)), close_gap + 1.0)
	var distance_weight := smoothstep(close_gap, breakaway_distance, absf(progress_gap))
	if distance_weight <= 0.0:
		return 0.0
	var difficulty_unit := clampf(float(session_config.difficulty) / 4.0, 0.0, 1.0)
	var correction := 0.0
	if progress_gap > close_gap:
		var player_comeback_scale := lerpf(1.15, 0.82, difficulty_unit)
		correction = -float(retention_contract.get(&"leader_drag_mps", 0.0)) * strength * distance_weight * player_comeback_scale
	elif progress_gap < -close_gap:
		var field_comeback_scale := lerpf(0.78, 1.18, difficulty_unit)
		correction = float(retention_contract.get(&"trailer_boost_mps", 0.0)) * strength * distance_weight * field_comeback_scale
	if session_config.event_id != &"ACADEMY":
		# Competitive riders concede less pace while leading and can answer a
		# Flow-assisted breakaway with their own bounded attack reserve. This is
		# still gap-based rather than a copy of player velocity, and the existing
		# final-lap fade below returns the finish entirely to rider performance.
		correction *= LEADER_DRAG_SCALE if correction < 0.0 else FIELD_COMEBACK_SCALE
	var final_lap_scale := clampf(float(retention_contract.get(&"final_lap_scale", 0.45)), 0.0, 1.0)
	var safe_completion := clampf(race_completion, 0.0, 1.0)
	var final_lap_fade := smoothstep(0.72, 0.90, safe_completion)
	correction *= lerpf(1.0, final_lap_scale, final_lap_fade)
	# The final approach belongs entirely to the riders. Release the remaining
	# shaping over the last seven percent and reach exactly zero before the line.
	correction *= 1.0 - smoothstep(0.90, 0.97, safe_completion)
	return clampf(correction, -DIRECTOR_MAX_CORRECTION, DIRECTOR_MAX_CORRECTION)


func _target_speed_for_gap(base_speed: float, player_speed: float, progress_gap: float, state: Dictionary) -> float:
	# Pace belongs to the rider profile and terrain sector. Player velocity is an
	# intentionally unused input: gap, event tier, and identity are the only
	# director inputs, keeping the response deterministic and legible.
	var _unused_player_speed := player_speed
	var total_race_distance := maxf(_track_length * float(_total_laps), 1.0)
	var race_completion := clampf(_player_total_progress() / total_race_distance, 0.0, 1.0)
	# Isolated field simulations and pre-race presentation have no player to
	# create a meaningful gap against, so the director stays entirely dormant.
	var correction := get_gap_pace_adjustment(progress_gap, race_completion) if is_instance_valid(_player) or simulation_has_player else 0.0
	if correction > 0.0:
		correction *= lerpf(0.82, 1.12, clampf(float(state.get(&"comeback_skill", 0.85)), 0.0, 1.0))
	elif correction < 0.0:
		# High-pressure front-runners resist some leader drag; calmer riders invite
		# a slightly tighter chase. The final clamp preserves the event contract.
		correction *= lerpf(1.08, 0.86, clampf(float(state.get(&"pressure_skill", 0.75)), 0.0, 1.0))
	correction = clampf(correction, -DIRECTOR_MAX_CORRECTION, DIRECTOR_MAX_CORRECTION)
	return maxf(base_speed + correction, 5.5)


func _late_race_pressure_mps(state: Dictionary, progress_gap: float) -> float:
	var total_race_distance := maxf(_track_length * float(_total_laps), 1.0)
	var rider_completion := clampf(_state_total_progress(state) / total_race_distance, 0.0, 1.0)
	if rider_completion < 0.68:
		return 0.0
	var phase := smoothstep(0.68, 0.90, rider_completion)
	var pressure_skill := clampf(float(state.get(&"pressure_skill", 0.75)), 0.0, 1.0)
	var comeback_skill := clampf(float(state.get(&"comeback_skill", 0.85)), 0.0, 1.0)
	var racecraft_skill := comeback_skill if progress_gap < 0.0 else pressure_skill
	var difficulty_scale := 0.76 if _player_difficulty_mode == &"RELAXED" else 1.12 if _player_difficulty_mode == &"EXPERT" else 1.0
	var pressure_cap := 0.82 if _session_config.event_id == &"ACADEMY" else LATE_RACE_PRESSURE_MAX_MPS
	return clampf(
		pressure_cap * phase * lerpf(0.42, 1.0, racecraft_skill) * difficulty_scale,
		0.0,
		pressure_cap
	)


func _close_trailing_attack_mps(index: int, state: Dictionary, player_speed: float) -> float:
	if _launch_tactics_blend() < 1.0 or int(state[&"mode"]) not in [RiderMode.RIDING, RiderMode.WOBBLE]:
		state[&"draft_strength"] = 0.0
		return 0.0
	var rider_total := _state_total_progress(state)
	var follower_pose := _racecraft_pose_for_state(state)
	var follower_position: Vector3 = follower_pose[&"position"]
	var follower_forward: Vector3 = follower_pose[&"forward"]
	var best_draft := 0.0
	var nearest_speed := 0.0
	for other_index: int in _riders.size():
		if other_index == index:
			continue
		var other: Dictionary = _riders[other_index]
		if not bool(other.get(&"active", true)) or bool(other.get(&"finished", false)):
			continue
		var gap := _state_total_progress(other) - rider_total
		if gap <= 0.35 or gap > RACECRAFT_RULES.DRAFT_MAX_DISTANCE + 1.0:
			continue
		var leader_pose := _racecraft_pose_for_state(other)
		var strength := RACECRAFT_RULES.draft_strength(
			follower_position,
			follower_forward,
			leader_pose[&"position"],
			leader_pose[&"forward"]
		)
		if strength > best_draft:
			best_draft = strength
			nearest_speed = float(other.get(&"speed", 0.0))
	if is_instance_valid(_player) or simulation_has_player:
		var player_gap := _player_total_progress() - rider_total
		if player_gap > 0.35 and player_gap <= RACECRAFT_RULES.DRAFT_MAX_DISTANCE + 1.0:
			var player_pose := _player_racecraft_pose()
			var player_draft := RACECRAFT_RULES.draft_strength(
				follower_position,
				follower_forward,
				player_pose[&"position"],
				player_pose[&"forward"]
			)
			if player_draft > best_draft:
				best_draft = player_draft
				nearest_speed = maxf(player_speed, 0.0)
	state[&"draft_strength"] = best_draft
	if best_draft <= 0.0:
		return 0.0
	var closing_headroom := 1.0 - smoothstep(
		1.4,
		3.0,
		float(state.get(&"speed", 0.0)) - nearest_speed
	)
	var aggression := clampf(float(state.get(&"aggression", 0.6)), 0.0, 1.0)
	var pressure_skill := clampf(float(state.get(&"pressure_skill", 0.75)), 0.0, 1.0)
	var attack_skill := aggression * 0.55 + pressure_skill * 0.45
	var attack_cap := 0.72 if _session_config.event_id == &"ACADEMY" else CLOSE_ATTACK_MAX_MPS
	return clampf(
		attack_cap * best_draft * closing_headroom * lerpf(0.45, 1.0, attack_skill),
		0.0,
		attack_cap
	)


func _record_speed_bias_sample(speed_bias: float) -> void:
	_chaos_metrics[&"speed_bias_samples"] = int(_chaos_metrics.get(&"speed_bias_samples", 0)) + 1
	_chaos_metrics[&"speed_bias_signed_sum_mps"] = float(
		_chaos_metrics.get(&"speed_bias_signed_sum_mps", 0.0)
	) + speed_bias
	_chaos_metrics[&"speed_bias_absolute_sum_mps"] = float(
		_chaos_metrics.get(&"speed_bias_absolute_sum_mps", 0.0)
	) + absf(speed_bias)
	_chaos_metrics[&"speed_bias_peak_absolute_mps"] = maxf(
		float(_chaos_metrics.get(&"speed_bias_peak_absolute_mps", 0.0)),
		absf(speed_bias)
	)


func _record_tactical_intent_time(state: Dictionary, delta: float) -> void:
	if float(state.get(&"traffic_plan_time", 0.0)) <= 0.0:
		return
	match StringName(state.get(&"traffic_plan_kind", &"")):
		&"PASS":
			_chaos_metrics[&"passing_intent_seconds"] = float(
				_chaos_metrics.get(&"passing_intent_seconds", 0.0)
			) + delta
		&"DEFEND":
			_chaos_metrics[&"defense_intent_seconds"] = float(
				_chaos_metrics.get(&"defense_intent_seconds", 0.0)
			) + delta


func _record_pressure_metrics(
	state: Dictionary,
	late_pressure_mps: float,
	close_attack_mps: float,
	delta: float
) -> void:
	var attack_active := close_attack_mps > 0.02
	if attack_active and not bool(state.get(&"close_attack_active", false)):
		_increment_metric(&"close_attack_activations")
	state[&"close_attack_active"] = attack_active
	if attack_active:
		_chaos_metrics[&"close_attack_seconds"] = float(
			_chaos_metrics.get(&"close_attack_seconds", 0.0)
		) + delta
		_chaos_metrics[&"close_attack_peak_mps"] = maxf(
			float(_chaos_metrics.get(&"close_attack_peak_mps", 0.0)),
			close_attack_mps
		)
	var draft_strength := clampf(float(state.get(&"draft_strength", 0.0)), 0.0, 1.0)
	if draft_strength > 0.01:
		_chaos_metrics[&"ai_draft_seconds"] = float(
			_chaos_metrics.get(&"ai_draft_seconds", 0.0)
		) + delta
		_chaos_metrics[&"ai_draft_peak"] = maxf(
			float(_chaos_metrics.get(&"ai_draft_peak", 0.0)),
			draft_strength
		)
	if late_pressure_mps > 0.02:
		_chaos_metrics[&"late_pressure_seconds"] = float(
			_chaos_metrics.get(&"late_pressure_seconds", 0.0)
		) + delta
		_chaos_metrics[&"late_pressure_peak_mps"] = maxf(
			float(_chaos_metrics.get(&"late_pressure_peak_mps", 0.0)),
			late_pressure_mps
		)


func _state_total_progress(state: Dictionary) -> float:
	return clampf(
		float(int(state.get(&"laps_completed", 0))) * _track_length + float(state.get(&"progress", 0.0)),
		0.0,
		_track_length * float(_total_laps)
	)


func _player_total_progress() -> float:
	return clampf(_player_total_progress_m, 0.0, _track_length * float(_total_laps))


func _resolve_player_total_progress(chainage: float) -> float:
	var race_distance := _track_length * float(_total_laps)
	if race_distance <= 0.001:
		return 0.0
	if _player_finish_usec >= 0 or _player_laps_completed >= _total_laps:
		return race_distance
	var lap_chainage := clampf(chainage, 0.0, _track_length)
	var candidate := clampf(
		float(_player_laps_completed) * _track_length + lap_chainage,
		0.0,
		race_distance
	)
	if not _closed_route or _track_length <= 0.001:
		return candidate
	# The duplicated start/finish point can report either the terminal or opening
	# chainage while RaceController advances the authoritative lap on an adjacent
	# tick. Reconcile only inside that seam window, leaving real reversing and
	# recovery movement elsewhere untouched.
	var seam_window := minf(
		maxf(28.0, CourseCatalog.get_track_width(_track_id) * 1.25),
		_track_length * 0.15
	)
	var prior_mod := fposmod(_player_total_progress_m, _track_length)
	var current_near_seam := minf(lap_chainage, _track_length - lap_chainage) <= seam_window
	var prior_near_seam := minf(prior_mod, _track_length - prior_mod) <= seam_window
	if not current_near_seam or not prior_near_seam:
		return candidate
	var best := candidate
	var best_delta := absf(best - _player_total_progress_m)
	for alias: float in [candidate - _track_length, candidate + _track_length]:
		var bounded_alias := clampf(alias, 0.0, race_distance)
		var alias_delta := absf(bounded_alias - _player_total_progress_m)
		if alias_delta < best_delta:
			best = bounded_alias
			best_delta = alias_delta
	# Projection may flicker between the equivalent aliases for several samples.
	# Never let that forward crossing present as a whole-lap loss to gaps/AI.
	return maxf(best, _player_total_progress_m)


func _racecraft_pose_for_state(state: Dictionary) -> Dictionary:
	var progress := clampf(float(state.get(&"progress", 0.0)), 0.0, _track_length)
	var position := _track_position_for_distance(progress)
	var forward := _smoothed_tangent_for_distance(progress).normalized()
	if forward.length_squared() < 0.1:
		forward = Vector3.FORWARD
	var flat_forward := Vector3(forward.x, 0.0, forward.z).normalized()
	if flat_forward.length_squared() < 0.1:
		flat_forward = Vector3.FORWARD
	position += flat_forward.cross(Vector3.UP).normalized() * float(state.get(&"lane", 0.0))
	return {&"position": position, &"forward": forward}


func _player_racecraft_pose() -> Dictionary:
	if is_instance_valid(_player):
		var forward := -_player.global_transform.basis.z.normalized()
		if forward.length_squared() < 0.1:
			forward = _smoothed_tangent_for_distance(_player_progress).normalized()
		return {&"position": _player.global_position, &"forward": forward}
	var synthetic_state := {
		&"progress": _player_progress,
		&"lane": _player_lane,
	}
	return _racecraft_pose_for_state(synthetic_state)


func _section_speed_factor(state: Dictionary) -> float:
	if _track_length <= 0.001:
		return 1.0
	var progress := clampf(float(state.get(&"progress", 0.0)), 0.0, _track_length)
	var current_tangent := _smoothed_tangent_for_distance(progress)
	var future_tangent := _smoothed_tangent_for_distance(minf(progress + 22.0, _track_length))
	var current_flat := Vector3(current_tangent.x, 0.0, current_tangent.z).normalized()
	var future_flat := Vector3(future_tangent.x, 0.0, future_tangent.z).normalized()
	var signed_turn := current_flat.cross(future_flat).dot(Vector3.UP)
	var turn_amount := absf(signed_turn)
	var corner_skill := clampf(float(state.get(&"corner_skill", 0.8)), 0.0, 1.0)
	var consistency := clampf(float(state.get(&"consistency", 0.8)), 0.0, 1.0)
	var jump_confidence := clampf(float(state.get(&"jump_confidence", 0.8)), 0.0, 1.0)
	var corner_factor := 1.0 - turn_amount * lerpf(0.43, 0.145, corner_skill)

	# A chosen line now has a small, skill-readable consequence. Inside/aggressive
	# riders shorten the apex; outside riders preserve a wider flow line. Missing
	# the rider's intended lane costs more than selecting either valid style.
	var line_factor := 1.0
	var line_alignment := 1.0
	if turn_amount > 0.025:
		var inside_sign := -1.0 if signed_turn > 0.0 else 1.0
		var preferred_line := StringName(state.get(&"preferred_line", &"SAFE"))
		var ideal_lane := 0.0
		match preferred_line:
			&"AGGRESSIVE":
				ideal_lane = inside_sign * _rut_lane_offset()
			&"INSIDE":
				ideal_lane = inside_sign * _rut_lane_offset()
			&"OUTSIDE":
				ideal_lane = -inside_sign * _berm_lane_offset()
			_:
				ideal_lane = 0.0
		var lane_error := absf(float(state.get(&"lane", 0.0)) - ideal_lane)
		line_alignment = 1.0 - clampf(lane_error / maxf(_racecraft_lane_limit * 1.10, 1.0), 0.0, 1.0)
		var line_reward := turn_amount * lerpf(0.008, 0.038, corner_skill) * line_alignment
		var line_penalty := turn_amount * lerpf(0.032, 0.010, corner_skill) * (1.0 - line_alignment)
		line_factor = 1.0 + line_reward - line_penalty

	var uphill_amount := maxf(current_tangent.y, 0.0)
	var downhill_amount := maxf(-current_tangent.y, 0.0)
	var uphill_factor := 1.0 - uphill_amount * lerpf(0.38, 0.26, corner_skill)
	var downhill_factor := 1.0 + downhill_amount * lerpf(
		0.14,
		0.31,
		corner_skill * 0.55 + jump_confidence * 0.45
	)
	var grade_factor := uphill_factor * downhill_factor
	var wet_skill := corner_skill * 0.55 + consistency * 0.45
	var condition_factor := (
		lerpf(0.86, 0.96, wet_skill)
		if _session_config.surface_modifier in [&"WET", &"MUD"]
		else 1.0
	)
	var jump_plan := StringName(state.get(&"jump_plan", &"ROLL"))
	var jump_factor := lerpf(0.925, 0.970, jump_confidence)
	match jump_plan:
		&"SAFE_JUMP":
			jump_factor = lerpf(0.970, 1.0, jump_confidence)
		&"SEND":
			jump_factor = lerpf(0.990, 1.045, jump_confidence)
		&"SCRUB":
			jump_factor = lerpf(1.005, 1.055, jump_confidence)
	var feature_difficulty := clampf(
		turn_amount * 2.4
		+ absf(current_tangent.y) * 0.75
		+ (0.18 if jump_plan != &"ROLL" else 0.0),
		0.0,
		1.0
	)
	var skill_line_factor := 1.0
	var skill_line_outcome: StringName = &"NONE"
	var skill_line_active := feature_difficulty > 0.06 and _launch_tactics_blend() >= 1.0
	if skill_line_active:
		var rider_skill := clampf(corner_skill * 0.45 + jump_confidence * 0.30 + consistency * 0.25, 0.0, 1.0)
		var target_error := absf(float(state.get(&"lane_target", 0.0)) - float(state.get(&"lane", 0.0)))
		var timing_quality := 1.0 - clampf(target_error / maxf(_racecraft_lane_limit, 1.0), 0.0, 1.0)
		var commitment := clampf(
			float(state.get(&"aggression", 0.6)) * 0.62 + jump_confidence * 0.38,
			0.0,
			1.0
		)
		var skill_result := RACECRAFT_RULES.evaluate_skill_line(
			rider_skill,
			line_alignment,
			timing_quality,
			commitment,
			feature_difficulty
		)
		skill_line_outcome = StringName(skill_result[&"outcome"])
		# The simulated pack already carries corner, grade, jump, and line factors.
		# Apply a measured share of the common physical result so AI observes the
		# same success/failure rule without double-counting that terrain energy.
		# Upgraded-bike fields already inherit a capped build-match pace scalar.
		# Avoid stacking a second positive line bonus on that same advantage.
		var skill_line_bonus_cap := 0.997 if _build_match_scale > 1.05 else 1.012
		skill_line_factor = clampf(
			lerpf(1.0, float(skill_result[&"momentum_multiplier"]), 0.22),
			0.96,
			skill_line_bonus_cap
		)
	state[&"line_factor"] = line_factor
	state[&"corner_factor"] = corner_factor
	state[&"downhill_factor"] = downhill_factor
	state[&"wet_factor"] = condition_factor
	state[&"jump_factor"] = jump_factor
	state[&"skill_line_active"] = skill_line_active
	state[&"skill_line_outcome"] = skill_line_outcome
	state[&"skill_line_factor"] = skill_line_factor
	return clampf(
		corner_factor * line_factor * grade_factor * condition_factor * jump_factor * skill_line_factor,
		0.64,
		1.15
	)


func _record_section_consequences(state: Dictionary, section_factor: float, delta: float) -> void:
	_chaos_metrics[&"section_minimum_factor"] = minf(
		float(_chaos_metrics.get(&"section_minimum_factor", INF)),
		section_factor
	)
	_chaos_metrics[&"section_maximum_factor"] = maxf(
		float(_chaos_metrics.get(&"section_maximum_factor", 0.0)),
		section_factor
	)
	if float(state.get(&"line_factor", 1.0)) > 1.001:
		_chaos_metrics[&"line_advantage_seconds"] = float(
			_chaos_metrics.get(&"line_advantage_seconds", 0.0)
		) + delta
	if float(state.get(&"downhill_factor", 1.0)) > 1.001:
		_chaos_metrics[&"downhill_momentum_seconds"] = float(
			_chaos_metrics.get(&"downhill_momentum_seconds", 0.0)
		) + delta
	if float(state.get(&"wet_factor", 1.0)) < 0.999:
		_chaos_metrics[&"wet_skill_seconds"] = float(
			_chaos_metrics.get(&"wet_skill_seconds", 0.0)
		) + delta
	if float(state.get(&"jump_factor", 1.0)) > 1.001:
		_chaos_metrics[&"jump_attack_seconds"] = float(
			_chaos_metrics.get(&"jump_attack_seconds", 0.0)
		) + delta
	if bool(state.get(&"skill_line_active", false)):
		match StringName(state.get(&"skill_line_outcome", &"NONE")):
			&"MASTERED":
				_chaos_metrics[&"skill_line_mastered_seconds"] = float(
					_chaos_metrics.get(&"skill_line_mastered_seconds", 0.0)
				) + delta
			&"CLEAN":
				_chaos_metrics[&"skill_line_clean_seconds"] = float(
					_chaos_metrics.get(&"skill_line_clean_seconds", 0.0)
				) + delta
			&"SCRAMBLED":
				_chaos_metrics[&"skill_line_scrambled_seconds"] = float(
					_chaos_metrics.get(&"skill_line_scrambled_seconds", 0.0)
				) + delta
			&"MISSED":
				_chaos_metrics[&"skill_line_missed_seconds"] = float(
					_chaos_metrics.get(&"skill_line_missed_seconds", 0.0)
				) + delta


func _update_mistake_state(index: int, state: Dictionary, delta: float) -> void:
	state[&"mistake_time"] = float(state.get(&"mistake_time", 1.0)) - delta
	state[&"mistake_factor"] = move_toward(float(state.get(&"mistake_factor", 1.0)), 1.0, delta * 0.55)
	if float(state[&"mistake_time"]) > 0.0 or _race_elapsed < 3.5:
		return
	var event_index := int(state.get(&"mistake_event", 0)) + 1
	state[&"mistake_event"] = event_index
	var consistency := clampf(float(state.get(&"consistency", 0.8)), 0.0, 1.0)
	var mistake_roll := _event_unit(index, event_index, 21.7)
	if mistake_roll > consistency:
		var severity := inverse_lerp(consistency, 1.0, mistake_roll)
		state[&"mistake_factor"] = lerpf(0.88, 0.70, severity)
		_enter_wobble(state, 1.5 + severity * 3.0, -1.0 if index % 2 == 0 else 1.0)
		_increment_metric(&"mistakes")
	state[&"mistake_time"] = 2.4 + _event_unit(index, event_index, 24.1) * (2.2 + consistency * 1.8)


func _update_jump_plan(index: int, state: Dictionary) -> void:
	var progress := float(state.get(&"progress", 0.0))
	var previous_plan := StringName(state.get(&"jump_plan", &"ROLL"))
	var selected_plan: StringName = &"ROLL"
	var preload_amount := 0.0
	for zone: Dictionary in _jump_zones:
		var start := float(zone.get(&"start", 0.0))
		var receiver_end := float(zone.get(&"receiver_start", start)) + float(zone.get(&"receiver_length", 0.0))
		if progress < start - 24.0 or progress > receiver_end + 5.0:
			continue
		var confidence := clampf(float(state.get(&"jump_confidence", 0.8)), 0.0, 1.0)
		var required_speed := 12.8 + float(zone.get(&"takeoff_height", 1.5)) * 1.15
		if confidence > 0.72 and float(state.get(&"speed", 0.0)) >= required_speed:
			selected_plan = &"SCRUB" if StringName(state.get(&"preferred_line", &"SAFE")) == &"AGGRESSIVE" and confidence > 0.86 else &"SEND"
		elif confidence > 0.52:
			selected_plan = &"SAFE_JUMP"
		preload_amount = smoothstep(start - 20.0, start - 1.0, progress) * confidence
		break
	if selected_plan != previous_plan and selected_plan != &"ROLL":
		match selected_plan:
			&"SAFE_JUMP":
				_increment_metric(&"jump_safe_commits")
			&"SEND":
				_increment_metric(&"jump_send_commits")
			&"SCRUB":
				_increment_metric(&"jump_scrub_commits")
	state[&"jump_plan"] = selected_plan
	state[&"preload"] = preload_amount


func _complete_rider_lap(index: int, state: Dictionary) -> Dictionary:
	var lap_usec := maxi(int((_race_elapsed - float(state.get(&"lap_start_elapsed", 0.0))) * 1_000_000.0), 1)
	state[&"last_lap_usec"] = lap_usec
	var best_lap := int(state.get(&"best_lap_usec", -1))
	state[&"best_lap_usec"] = lap_usec if best_lap < 0 else mini(best_lap, lap_usec)
	var lap_times: Array = state.get(&"lap_times_usec", []) as Array
	lap_times.append(lap_usec)
	state[&"lap_times_usec"] = lap_times
	state[&"laps_completed"] = int(state.get(&"laps_completed", 0)) + 1
	state[&"lap_start_elapsed"] = _race_elapsed
	if int(state[&"laps_completed"]) >= _total_laps:
		state[&"progress"] = _track_length
		state[&"finished"] = true
		state[&"status"] = &"FINISHED"
		state[&"finish_usec"] = maxi(int(_race_elapsed * 1_000_000.0), 1)
		state[&"speed"] = maxf(float(state.get(&"speed", 0.0)) * 0.72, 0.0)
	else:
		state[&"progress"] = maxf(float(state.get(&"progress", 0.0)) - _track_length, 0.0)
	return state


func _update_rider(index: int, delta: float) -> void:
	if _track_points.size() < 2:
		return
	var state: Dictionary = _riders[index]
	var root := state[&"root"] as Node3D
	if not bool(state.get(&"active", true)) or bool(state[&"finished"]):
		return
	root.visible = true
	var progress := clampf(float(state[&"progress"]), 0.0, _track_length)
	var position := _track_position_for_distance(progress)
	var tangent := _smoothed_tangent_for_distance(progress)
	var flat_tangent := Vector3(tangent.x, 0.0, tangent.z).normalized()
	if flat_tangent.length_squared() < 0.1:
		flat_tangent = Vector3.FORWARD
	var right := flat_tangent.cross(Vector3.UP).normalized()
	var weave_scale := 0.12 if int(state[&"mode"]) == RiderMode.CRASHED else 0.22
	var weave := sin(progress * 0.036 + float(state[&"phase"])) * weave_scale * _launch_tactics_blend()
	position += right * (float(state[&"lane"]) + weave)
	var surface := _sample_ride_surface(position)
	var support_y := position.y
	var surface_normal := Vector3.UP
	if not surface.is_empty():
		var surface_position: Vector3 = surface[&"position"]
		support_y = surface_position.y
		var hit_normal: Vector3 = surface[&"normal"]
		if hit_normal.dot(Vector3.UP) > 0.35:
			surface_normal = hit_normal.normalized()
	_follow_ride_surface(state, support_y, delta, index)
	position.y = float(state[&"surface_y"])
	if bool(state[&"surface_supported"]):
		# Project the race direction into the actual ramp/deck plane. Roll and
		# tactical steer are composed later around this pitched heading.
		var surface_tangent := tangent - surface_normal * tangent.dot(surface_normal)
		if surface_tangent.length_squared() > 0.1:
			tangent = surface_tangent.normalized()
	else:
		# Keep takeoff pitch and transition into a shallow ballistic nose-down
		# arc instead of adopting the lower base ribbon's normal in mid-air.
		var planar_tangent := Vector3(tangent.x, 0.0, tangent.z).normalized()
		if planar_tangent.length_squared() < 0.1:
			planar_tangent = Vector3.FORWARD
		tangent = (
			planar_tangent * maxf(float(state[&"speed"]), 1.0)
			+ Vector3.UP * float(state[&"surface_vertical_speed"])
		).normalized()
	position.y += 0.02 + sin(progress * 0.18 + float(state[&"phase"])) * 0.015
	var future_tangent := _smoothed_tangent_for_distance(minf(progress + 8.0, _track_length))
	var signed_turn := tangent.cross(future_tangent).dot(Vector3.UP)
	var corner_lean := clampf(-signed_turn * 1.9, -0.46, 0.46)
	corner_lean *= smoothstep(0.45, 2.8, _race_elapsed) if _active else 0.0
	var body_roll := corner_lean + float(state[&"pose_roll"])
	var heading_tangent := (
		tangent * maxf(float(state[&"speed"]), 1.0)
		+ right * float(state[&"lane_velocity"])
	).normalized()
	var target_basis := Basis.looking_at(heading_tangent, Vector3.UP)
	target_basis = Basis(heading_tangent, body_roll) * target_basis
	var basis := target_basis.orthonormalized()
	if delta > 0.0001:
		var previous_rotation := root.global_transform.basis.orthonormalized().get_rotation_quaternion()
		var target_rotation := basis.get_rotation_quaternion()
		var follow_weight := 1.0 - exp(-ORIENTATION_FOLLOW_RATE * delta)
		basis = Basis(previous_rotation.slerp(target_rotation, follow_weight)).orthonormalized()
		_update_launch_heading_metrics(root.global_transform.basis, basis, heading_tangent)
	root.global_transform = Transform3D(basis, position)
	var previous_position: Vector3 = state[&"previous_position"]
	state[&"velocity"] = (position - previous_position) / delta if delta > 0.0001 and previous_position.length_squared() > 0.001 else Vector3.ZERO
	state[&"previous_position"] = position
	var visual := state[&"visual"] as Node3D
	var steer_pose := clampf(-signed_turn * 2.8 + float(state[&"lane_velocity"]) * 0.12, -0.7, 0.7)
	visual.call(
		&"update_pack_pose",
		float(state[&"speed"]),
		steer_pose,
		body_roll,
		progress * 0.43 + float(state[&"phase"]),
		delta,
		bool(state[&"surface_supported"]),
		absf(float(state[&"surface_vertical_speed"])) / SURFACE_MAX_FALL_SPEED,
		_session_config.surface_modifier,
		bool(state.get(&"landing_event", false)),
		float(state.get(&"landing_quality", 1.0))
	)
	state[&"landing_event"] = false
	_riders[index] = state


func _update_density_metrics(delta: float) -> void:
	var minimum_lane := INF
	var maximum_lane := -INF
	var active_count := 0
	var close_count := 0
	for state: Dictionary in _riders:
		if not bool(state.get(&"active", true)) or bool(state[&"finished"]):
			continue
		active_count += 1
		var lane := float(state[&"lane"])
		minimum_lane = minf(minimum_lane, lane)
		maximum_lane = maxf(maximum_lane, lane)
		if is_instance_valid(_player):
			var root := state[&"root"] as Node3D
			var planar_offset := root.global_position - _player.global_position
			planar_offset.y = 0.0
			if planar_offset.length() <= 15.0:
				close_count += 1
	if active_count > 0:
		_chaos_metrics[&"peak_lane_span"] = maxf(
			float(_chaos_metrics[&"peak_lane_span"]),
			maximum_lane - minimum_lane
		)
	if close_count >= 2:
		_chaos_metrics[&"close_traffic_seconds"] = float(_chaos_metrics[&"close_traffic_seconds"]) + delta


func _launch_tactics_blend() -> float:
	if not _active:
		return 0.0
	return smoothstep(
		LAUNCH_LANE_LOCK_SECONDS,
		LAUNCH_LANE_LOCK_SECONDS + LAUNCH_TACTICS_BLEND_SECONDS,
		_race_elapsed
	)


func _update_launch_motion_metrics(state: Dictionary, previous_lane_velocity: float, delta: float) -> void:
	var displacement := absf(float(state[&"lane"]) - float(state[&"launch_lane"]))
	var lateral_speed := absf(float(state[&"lane_velocity"]))
	if _race_elapsed <= LAUNCH_LANE_LOCK_SECONDS + 0.0001:
		_chaos_metrics[&"launch_max_lane_displacement"] = maxf(
			float(_chaos_metrics[&"launch_max_lane_displacement"]),
			displacement
		)
		_chaos_metrics[&"launch_max_lateral_speed"] = maxf(
			float(_chaos_metrics[&"launch_max_lateral_speed"]),
			lateral_speed
		)
	if (
		float(_chaos_metrics[&"launch_first_lateral_motion_time"]) < 0.0
		and (displacement > 0.01 or lateral_speed > 0.05)
	):
		_chaos_metrics[&"launch_first_lateral_motion_time"] = _race_elapsed
	var blend_end := LAUNCH_LANE_LOCK_SECONDS + LAUNCH_TACTICS_BLEND_SECONDS
	if delta > 0.0001 and _race_elapsed > LAUNCH_LANE_LOCK_SECONDS and _race_elapsed <= blend_end + 0.0001:
		var acceleration := absf(float(state[&"lane_velocity"]) - previous_lane_velocity) / delta
		_chaos_metrics[&"launch_max_blend_lateral_acceleration"] = maxf(
			float(_chaos_metrics[&"launch_max_blend_lateral_acceleration"]),
			acceleration
		)


func _update_launch_heading_metrics(previous_basis: Basis, current_basis: Basis, target_forward: Vector3) -> void:
	if _race_elapsed > LAUNCH_LANE_LOCK_SECONDS + LAUNCH_TACTICS_BLEND_SECONDS + 0.0001:
		return
	# The launch contract is about horizontal fan-out. Ramp pitch and bank can
	# legitimately change several degrees in one physics step and must not be
	# misreported as a steering snap.
	var previous_forward := -previous_basis.orthonormalized().z.normalized()
	var current_forward := -current_basis.orthonormalized().z.normalized()
	var normalized_target := target_forward.normalized()
	previous_forward = Vector3(previous_forward.x, 0.0, previous_forward.z).normalized()
	current_forward = Vector3(current_forward.x, 0.0, current_forward.z).normalized()
	normalized_target = Vector3(normalized_target.x, 0.0, normalized_target.z).normalized()
	var step_degrees := rad_to_deg(previous_forward.angle_to(current_forward))
	var error_degrees := rad_to_deg(current_forward.angle_to(normalized_target))
	_chaos_metrics[&"launch_max_heading_step_degrees"] = maxf(
		float(_chaos_metrics[&"launch_max_heading_step_degrees"]),
		step_degrees
	)
	_chaos_metrics[&"launch_max_heading_error_degrees"] = maxf(
		float(_chaos_metrics[&"launch_max_heading_error_degrees"]),
		error_degrees
	)


func _update_launch_clearance_metrics() -> void:
	if _race_elapsed > LAUNCH_LANE_LOCK_SECONDS + 0.0001:
		return
	for first_index: int in range(_riders.size() - 1):
		if not bool(_riders[first_index].get(&"active", true)):
			continue
		var first_root := _riders[first_index][&"root"] as Node3D
		if not first_root.visible:
			continue
		for second_index: int in range(first_index + 1, _riders.size()):
			if not bool(_riders[second_index].get(&"active", true)):
				continue
			var second_root := _riders[second_index][&"root"] as Node3D
			if not second_root.visible:
				continue
			var offset := second_root.global_position - first_root.global_position
			offset.y = 0.0
			_chaos_metrics[&"launch_min_npc_clearance"] = minf(
				float(_chaos_metrics[&"launch_min_npc_clearance"]),
				offset.length()
			)
	if is_instance_valid(_player):
		for state: Dictionary in _riders:
			if not bool(state.get(&"active", true)):
				continue
			var root := state[&"root"] as Node3D
			if not root.visible:
				continue
			var player_offset := root.global_position - _player.global_position
			player_offset.y = 0.0
			_chaos_metrics[&"launch_min_player_clearance"] = minf(
				float(_chaos_metrics[&"launch_min_player_clearance"]),
				player_offset.length()
			)


func _finite_clearance_metric(metric: StringName) -> float:
	var value := float(_chaos_metrics.get(metric, INF))
	return value if is_finite(value) else -1.0


func _build_audio_pool() -> void:
	if not _audio_pool.is_empty():
		return
	for index: int in AUDIO_POOL_SIZE:
		var engine := AudioStreamPlayer3D.new()
		engine.name = "OpponentEngine%02d" % (index + 1)
		engine.set_script(ENGINE_AUDIO_SCRIPT)
		add_child(engine)
		engine.volume_db = -80.0
		_audio_pool.append(engine)


func _update_audio_pool(delta: float) -> void:
	_audio_update_time -= delta
	if _audio_update_time > 0.0:
		return
	_audio_update_time = 0.08
	var listener_position := _player.global_position if is_instance_valid(_player) else global_position
	var used: Dictionary[int, bool] = {}
	var audio_surface: StringName = &"MUD" if _session_config.surface_modifier == &"WET" else &"LOOSE_DIRT"
	for engine: AudioStreamPlayer3D in _audio_pool:
		var chosen_index := -1
		var chosen_distance := INF
		for rider_index: int in _riders.size():
			if used.has(rider_index):
				continue
			var state: Dictionary = _riders[rider_index]
			if not bool(state.get(&"active", true)) or bool(state.get(&"finished", false)):
				continue
			var root := state[&"root"] as Node3D
			var distance := root.global_position.distance_squared_to(listener_position)
			if distance < chosen_distance:
				chosen_distance = distance
				chosen_index = rider_index
		if chosen_index < 0:
			engine.volume_db = -80.0
			engine.call(&"set_engine_state", 0.0, 0.0, true)
			continue
		used[chosen_index] = true
		var chosen: Dictionary = _riders[chosen_index]
		var chosen_root := chosen[&"root"] as Node3D
		engine.global_position = chosen_root.global_position + Vector3.UP * 0.45
		engine.volume_db = -15.0
		var speed := float(chosen.get(&"speed", 0.0))
		engine.call(
			&"set_engine_state",
			speed,
			clampf(speed / maxf(float(chosen.get(&"base_speed", 16.0)), 1.0), 0.15, 1.0),
			bool(chosen.get(&"surface_supported", true)),
			audio_surface,
			0.54,
			clampf(absf(float(chosen.get(&"lane_velocity", 0.0))) / LANE_CHANGE_SPEED, 0.0, 1.0),
			absf(float(chosen.get(&"surface_vertical_speed", 0.0))) / SURFACE_MAX_FALL_SPEED
		)
	# Reuse the same nearest-four decision for visual feedback. This keeps the
	# dense gate alive around the player without paying for 22 transparent GPU
	# particle systems across riders that are too far away to read.
	for rider_index: int in _riders.size():
		var visual := _riders[rider_index].get(&"visual") as Node3D
		if visual != null and visual.has_method(&"set_pack_effects_enabled"):
			visual.call(&"set_pack_effects_enabled", used.has(rider_index))


func _update_holeshot() -> void:
	if not _holeshot_rider_id.is_empty():
		return
	var leader_id: StringName = &"PLAYER"
	var leader_progress := _player_total_progress() if is_instance_valid(_player) else -INF
	for state: Dictionary in _riders:
		if not bool(state.get(&"active", true)):
			continue
		var progress := _state_total_progress(state)
		if progress > leader_progress:
			leader_progress = progress
			leader_id = StringName(state.get(&"rider_id", &"NPC"))
	if leader_progress < HOLESHOT_DISTANCE:
		return
	_holeshot_rider_id = leader_id
	holeshot_decided.emit(_holeshot_rider_id)


func _track_position_for_distance(distance: float) -> Vector3:
	var segment_index := _segment_for_distance(clampf(distance, 0.0, _track_length))
	var start_distance := _distances[segment_index]
	var end_distance := _distances[segment_index + 1]
	var weight := inverse_lerp(start_distance, end_distance, distance)
	return _track_points[segment_index].lerp(_track_points[segment_index + 1], weight)


func _smoothed_tangent_for_distance(distance: float) -> Vector3:
	var before_distance := maxf(distance - TANGENT_SAMPLE_METERS, 0.0)
	var after_distance := minf(distance + TANGENT_SAMPLE_METERS, _track_length)
	var tangent := _track_position_for_distance(after_distance) - _track_position_for_distance(before_distance)
	if tangent.length_squared() <= 0.01:
		return (_track_points[1] - _track_points[0]).normalized()
	return tangent.normalized()


func _sample_ride_surface(position: Vector3) -> Dictionary:
	var world := get_world_3d()
	if world == null:
		return {}
	var ray_start := position + Vector3.UP * SURFACE_RAY_HEIGHT
	var ray_end := position - Vector3.UP * SURFACE_RAY_DEPTH
	var query_mask := CourseSurfaceBuilder.AUTHORITATIVE_RIDE_LAYER if _authoritative_surface_root != null else 2
	# This path runs once per visible opponent per physics tick. Reusing the
	# synchronous query descriptor avoids hundreds of short-lived RefCounted
	# allocations per second without changing the ray or collision mask.
	_surface_query.from = ray_start
	_surface_query.to = ray_end
	_surface_query.collision_mask = query_mask
	_surface_queries_this_tick += 1
	var hit := world.direct_space_state.intersect_ray(_surface_query)
	if hit.is_empty():
		return {}
	if _authoritative_surface_root == null or _is_authoritative_track_surface(hit.get(&"collider")):
		return hit
	return {}


func _is_authoritative_track_surface(collider: Variant) -> bool:
	if not collider is Node:
		return false
	var node := collider as Node
	while node != null:
		if bool(node.get_meta(&"authoritative_track_surface", false)):
			return StringName(node.get_meta(&"authoritative_track_id", &"")) == _track_id
		if node == _authoritative_surface_root:
			break
		node = node.get_parent()
	return false


func _follow_ride_surface(state: Dictionary, support_y: float, delta: float, rider_index: int = 0) -> void:
	state[&"landing_event"] = false
	if not bool(state[&"surface_initialized"]) or delta <= 0.0001:
		state[&"surface_y"] = support_y
		state[&"surface_vertical_speed"] = 0.0
		state[&"surface_supported"] = true
		state[&"surface_initialized"] = true
		_record_surface_clearance(0.0)
		return

	var current_y := float(state[&"surface_y"])
	var vertical_speed := float(state[&"surface_vertical_speed"])
	var was_supported := bool(state[&"surface_supported"])
	var supported := was_supported
	var next_y := current_y
	# A welded lip has no literal deck edge, so its support may fall away by less
	# than 20 cm in one physics tick. Preserve the measured climb velocity when a
	# rising bike crosses that crest; otherwise visual opponents glue themselves
	# to the receiver while the physical player becomes airborne.
	var crossed_welded_crest := (
		was_supported
		and vertical_speed >= SURFACE_CREST_LAUNCH_SPEED
		and support_y <= current_y - SURFACE_CREST_LAUNCH_DROP
	)
	if (
		was_supported
		and not crossed_welded_crest
		and support_y >= current_y - SURFACE_DROP_LAUNCH_THRESHOLD
	):
		# Rising faces and continuous downhill surfaces are followed exactly.
		# The measured ascent rate becomes the launch velocity at a real lip.
		next_y = support_y
		vertical_speed = clampf((next_y - current_y) / delta, -SURFACE_MAX_FALL_SPEED, SURFACE_MAX_LAUNCH_SPEED)
	elif was_supported:
		# The support fell away by more than a normal per-tick grade change: this
		# is a lip or deck edge. Preserve ascent momentum, then apply gravity.
		supported = false
		var jump_plan := StringName(state.get(&"jump_plan", &"ROLL"))
		var plan_boost := 2.25 if jump_plan == &"SEND" else 1.3 if jump_plan == &"SAFE_JUMP" else 0.55 if jump_plan == &"SCRUB" else 0.0
		vertical_speed = clampf(
			maxf(vertical_speed, 0.0) + float(state.get(&"preload", 0.0)) * plan_boost - SURFACE_GRAVITY * delta,
			-SURFACE_MAX_FALL_SPEED,
			SURFACE_MAX_LAUNCH_SPEED
		)
		next_y = current_y + vertical_speed * delta
		_increment_metric(&"surface_launches")
	else:
		var impact_speed := absf(vertical_speed)
		vertical_speed = maxf(vertical_speed - SURFACE_GRAVITY * delta, -SURFACE_MAX_FALL_SPEED)
		next_y = current_y + vertical_speed * delta
		if next_y <= support_y and (vertical_speed <= 0.0 or support_y >= current_y):
			impact_speed = maxf(impact_speed, absf(vertical_speed))
			next_y = support_y
			vertical_speed = 0.0
			supported = true
			var confidence := clampf(float(state.get(&"jump_confidence", 0.8)), 0.0, 1.0)
			var landing_quality := clampf(1.18 - impact_speed / 12.5 + confidence * 0.16, 0.0, 1.0)
			state[&"landing_quality"] = landing_quality
			state[&"landing_event"] = true
			if landing_quality < 0.38:
				state[&"speed"] = maxf(float(state.get(&"speed", 0.0)) * lerpf(0.68, 0.88, landing_quality / 0.38), 3.0)
				_enter_wobble(state, 4.0 + impact_speed * 0.4, -1.0 if rider_index % 2 == 0 else 1.0)
				_increment_metric(&"cases")
				_increment_metric(&"landing_errors")
			_increment_metric(&"surface_landings")

	state[&"surface_y"] = next_y
	state[&"surface_vertical_speed"] = vertical_speed
	state[&"surface_supported"] = supported
	var clearance := next_y - support_y
	_record_surface_clearance(clearance)
	if not supported:
		_chaos_metrics[&"surface_maximum_air_height"] = maxf(
			float(_chaos_metrics[&"surface_maximum_air_height"]),
			clearance
		)


func _record_surface_clearance(clearance: float) -> void:
	_chaos_metrics[&"surface_minimum_clearance"] = minf(
		float(_chaos_metrics[&"surface_minimum_clearance"]),
		clearance
	)


func _segment_for_distance(distance: float) -> int:
	var low := 0
	var high := maxi(_distances.size() - 2, 0)
	while low < high:
		var middle := floori(float(low + high) * 0.5)
		if _distances[middle + 1] < distance:
			low = middle + 1
		else:
			high = middle
	return low


func _flat_tangent_for_segment(segment_index: int) -> Vector3:
	var safe_index := clampi(segment_index, 0, _track_points.size() - 2)
	var tangent := _track_points[safe_index + 1] - _track_points[safe_index]
	tangent.y = 0.0
	return tangent.normalized() if tangent.length_squared() > 0.01 else Vector3.FORWARD


func _event_unit(rider_index: int, event_index: int, salt: float) -> float:
	var raw := sin((float(rider_index) + 1.0) * 12.9898 + (float(event_index) + 1.0) * 78.233 + salt) * 43758.5453
	return raw - floor(raw)


func _reset_pair_orders() -> void:
	_pair_orders.clear()
	for first_index: int in range(_riders.size() - 1):
		if not bool(_riders[first_index].get(&"active", true)):
			continue
		for second_index: int in range(first_index + 1, _riders.size()):
			if not bool(_riders[second_index].get(&"active", true)):
				continue
			var gap := _state_total_progress(_riders[second_index]) - _state_total_progress(_riders[first_index])
			var order := 1 if gap > 0.08 else -1 if gap < -0.08 else 0
			_pair_orders[first_index * RIDER_COUNT + second_index] = order


func _reset_player_pair_orders() -> void:
	_player_pair_orders.clear()
	if not is_instance_valid(_player):
		return
	var player_progress := _player_total_progress()
	for index: int in _riders.size():
		var state: Dictionary = _riders[index]
		if not bool(state.get(&"active", true)) or bool(state.get(&"finished", false)):
			continue
		var gap := _state_total_progress(state) - player_progress
		var order := 1 if gap > 0.35 else -1 if gap < -0.35 else 0
		if order != 0:
			_player_pair_orders[index] = order


func _resolve_player_pair_orders() -> void:
	if not is_instance_valid(_player):
		return
	var player_progress := _player_total_progress()
	for index: int in _riders.size():
		var state: Dictionary = _riders[index]
		if not bool(state.get(&"active", true)) or bool(state.get(&"finished", false)):
			continue
		var gap := _state_total_progress(state) - player_progress
		var order := 1 if gap > 0.35 else -1 if gap < -0.35 else 0
		var previous_order := int(_player_pair_orders.get(index, order))
		if order != 0 and previous_order != 0 and order != previous_order:
			var rider_id := StringName(state.get(&"rider_id", &"NPC"))
			if previous_order > 0 and order < 0:
				player_overtook.emit(rider_id)
			elif previous_order < 0 and order > 0:
				player_was_overtaken.emit(rider_id)
		if order != 0:
			_player_pair_orders[index] = order


func _reset_chaos_metrics() -> void:
	_chaos_metrics = {
		&"lane_changes": 0,
		&"racecraft_line_commits": 0,
		&"field_overtakes": 0,
		&"field_contacts": 0,
		&"player_contacts": 0,
		&"near_misses": 0,
		&"field_crashes": 0,
		&"field_recoveries": 0,
		&"mistakes": 0,
		&"cases": 0,
		&"landing_errors": 0,
		&"speed_bias_samples": 0,
		&"speed_bias_signed_sum_mps": 0.0,
		&"speed_bias_absolute_sum_mps": 0.0,
		&"speed_bias_peak_absolute_mps": 0.0,
		&"pass_plans": 0,
		&"pass_plan_refreshes": 0,
		&"defense_plan_refreshes": 0,
		&"passing_intent_seconds": 0.0,
		&"defensive_moves": 0,
		&"defense_intent_seconds": 0.0,
		&"close_attack_activations": 0,
		&"close_attack_seconds": 0.0,
		&"close_attack_peak_mps": 0.0,
		&"ai_draft_seconds": 0.0,
		&"ai_draft_peak": 0.0,
		&"player_draft_seconds": 0.0,
		&"player_draft_peak": 0.0,
		&"player_roost_pressure_peak": 0.0,
		&"player_roost_defense_peak": 0.0,
		&"player_roost_hits": 0,
		&"player_roost_wobbles": 0,
		&"player_roost_drive_cost_sum": 0.0,
		&"late_pressure_seconds": 0.0,
		&"late_pressure_peak_mps": 0.0,
		&"line_advantage_seconds": 0.0,
		&"downhill_momentum_seconds": 0.0,
		&"wet_skill_seconds": 0.0,
		&"jump_attack_seconds": 0.0,
		&"skill_line_mastered_seconds": 0.0,
		&"skill_line_clean_seconds": 0.0,
		&"skill_line_scrambled_seconds": 0.0,
		&"skill_line_missed_seconds": 0.0,
		&"section_minimum_factor": INF,
		&"section_maximum_factor": 0.0,
		&"jump_safe_commits": 0,
		&"jump_send_commits": 0,
		&"jump_scrub_commits": 0,
		&"crash_downtime_planned_seconds": 0.0,
		&"recovery_downtime_planned_seconds": 0.0,
		&"recovery_minimum_seconds": INF,
		&"recovery_maximum_seconds": 0.0,
		&"recovery_lane_changes": 0,
		&"minimum_player_clearance": INF,
		&"peak_lane_span": 0.0,
		&"close_traffic_seconds": 0.0,
		&"simulated_seconds": 0.0,
		&"launch_max_lane_displacement": 0.0,
		&"launch_max_lateral_speed": 0.0,
		&"launch_first_lateral_motion_time": -1.0,
		&"launch_first_tactical_time": -1.0,
		&"launch_max_blend_lateral_acceleration": 0.0,
		&"launch_min_acceleration_scale": INF,
		&"launch_max_acceleration_scale": 0.0,
		&"launch_max_heading_error_degrees": 0.0,
		&"launch_max_heading_step_degrees": 0.0,
		&"launch_min_npc_clearance": INF,
		&"launch_min_player_clearance": INF,
		&"surface_minimum_clearance": INF,
		&"surface_maximum_air_height": 0.0,
		&"surface_launches": 0,
		&"surface_landings": 0,
		&"pair_separation_corrections": 0,
		&"maximum_pair_separation_step": 0.0,
	}


func _increment_metric(name: StringName) -> void:
	_chaos_metrics[name] = int(_chaos_metrics.get(name, 0)) + 1


func _profiles_for_session(count: int, rival_only: bool, gate_order: Array[StringName]) -> Array[Dictionary]:
	var entrant_ids := _string_name_array(_session_config.rules.get(&"entrant_ids", []))
	var featured_ids := _string_name_array(_session_config.rules.get(&"featured_rider_ids", []))
	var profiles := RiderRoster.get_session_field(count, rival_only, entrant_ids, featured_ids)
	if rival_only:
		return profiles
	if gate_order.is_empty():
		return profiles
	var gate_ranks: Dictionary[StringName, int] = {}
	for gate_index: int in gate_order.size():
		var rider_id := gate_order[gate_index]
		if rider_id != &"PLAYER" and not gate_ranks.has(rider_id):
			gate_ranks[rider_id] = gate_index
	profiles.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		var first_id := StringName(first.get(&"id", &""))
		var second_id := StringName(second.get(&"id", &""))
		var first_rank := int(gate_ranks.get(first_id, 10_000))
		var second_rank := int(gate_ranks.get(second_id, 10_000))
		if first_rank != second_rank:
			return first_rank < second_rank
		return String(first_id) < String(second_id)
	)
	return profiles


func _string_name_array(value: Variant) -> Array[StringName]:
	var output: Array[StringName] = []
	if value is Array or value is PackedStringArray:
		for raw_value: Variant in value:
			var rider_id := StringName(raw_value)
			if not rider_id.is_empty() and not output.has(rider_id):
				output.append(rider_id)
	return output


func _ensure_riders() -> void:
	if not _riders.is_empty():
		return
	_build_riders()


func _build_riders() -> void:
	var palette: Array[Color] = [
		Color("2f7de1"), Color("55bd4a"), Color("e34c38"), Color("9b56d8"),
		Color("f0a62f"), Color("23a7a1"), Color("db3f82"), Color("e5d43c"),
		Color("5e64d7"), Color("e36a2f"), Color("45b8e8"),
	]
	var helmet_palette: Array[Color] = [
		Color("f5d67b"), Color("f2f0df"), Color("ffb52d"), Color("56d6ff"),
		Color("e8edf2"), Color("f5d67b"), Color("f2f0df"), Color("ef5b43"),
		Color("ffb52d"), Color("56d6ff"), Color("f5d67b"),
	]
	for index: int in RIDER_COUNT:
		var root := Node3D.new()
		root.name = "PackRider%02d" % (index + 2)
		add_child(root)
		var visual := Node3D.new()
		visual.name = "PlayerMatchedBikeVisual"
		if presentation_enabled:
			visual.set_script(BIKE_VISUAL_SCRIPT)
			visual.set(&"pack_variant", true)
			visual.set(&"pack_bike_color", palette[index])
			visual.set(&"pack_helmet_color", helmet_palette[index])
		# Player chassis origin sits 0.76 m above the tyre contact patch.
		visual.position = Vector3(0.0, 0.76, 0.0)
		root.add_child(visual)
		_riders.append({
			&"root": root,
			&"visual": visual,
			&"progress": 0.0,
			&"lane": 0.0,
			&"speed": 0.0,
			&"base_speed": 0.0,
			&"phase": 0.0,
			&"finished": false,
		})
