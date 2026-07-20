extends RefCounted
class_name RaceIntegrityTracker
## Deterministic route-integrity service for races and time trials.
##
## The authoritative spline remains the sole source of timed progress. Legal
## skill branches map monotonically between their main-line entry and exit, while
## their own geometry supplies corridor, heading, and recovery evidence.

const COURSE_SPLINE_SCRIPT := preload("res://features/environment/course_spline.gd")

const WARNING_NONE: StringName = &"NONE"
const WARNING_OFF_COURSE: StringName = &"OFF_COURSE"
const WARNING_WRONG_WAY: StringName = &"WRONG_WAY"
const WARNING_CUT: StringName = &"CUT_DETECTED"
const WARNING_STUCK: StringName = &"STUCK"

const FLAG_CLEAR: StringName = &"CLEAR"
const FLAG_WARNING: StringName = &"WARNING"
const FLAG_RESET: StringName = &"RESET_REQUIRED"

const DEFAULT_SEARCH_WINDOW := 48
const DEFAULT_RESET_SUPPRESSION_SECONDS := 1.1
const MAIN_ROUTE_LINE_ID: StringName = &"MAIN"
const ROUTE_SELECTION_EPSILON := 0.05

var _configured := false
var _route := PackedVector3Array()
var _cumulative_distances := PackedFloat32Array()
var _route_length := 0.0
var _branch_routes: Array[Dictionary] = []
var _track_width := 18.0
var _half_width := 9.0
var _warning_limit := 10.0
var _legal_limit := 14.0
var _closed := false
var _total_laps := 1
var _spawn_transform := Transform3D.IDENTITY
var _spawn_clearance := 1.25

var _search_window := DEFAULT_SEARCH_WINDOW
var _off_course_grace_seconds := 2.4
var _wrong_way_grace_seconds := 1.4
var _stuck_grace_seconds := 5.5
var _reset_penalty_usec := 2_000_000
var _cut_penalty_usec := 3_000_000
var _wrong_way_penalty_usec := 2_000_000
var _stuck_penalty_usec := 2_000_000
var _minimum_wrong_way_speed := 4.0
var _minimum_stuck_speed := 0.8
var _stuck_arm_distance := 2.5
var _minimum_cut_jump := 28.0
var _rejoin_capture_interval := 0.3

var _projection_segment := -1
var _projection_line_id: StringName = MAIN_ROUTE_LINE_ID
var _projection_line_segment := -1
var _projection: Dictionary = {}
var _current_lap := 1
var _inferred_lap := 1
var _seam_transition_lap := 0
var _previous_chainage := -1.0
var _previous_total_progress := -1.0
var _previous_position := Vector3.ZERO
var _has_previous_position := false
var _suppress_validation_time := 0.0

var _off_course_time := 0.0
var _wrong_way_time := 0.0
var _stuck_time := 0.0
var _rejoin_capture_time := 0.0
var _is_off_course := false
var _is_wrong_way := false
var _is_stuck := false
var _stuck_detection_armed := false
var _cut_detected := false

var _warning_code: StringName = WARNING_NONE
var _flag: StringName = FLAG_CLEAR
var _reset_requested := false
var _reset_reason: StringName = &""
var _pending_penalty_usec := 0
var _penalty_usec := 0
var _run_valid := true
var _penalty_breakdown: Dictionary = {}
var _incident_counts: Dictionary = {}

var _last_legal_rejoin_transform := Transform3D.IDENTITY
var _last_legal_progress := 0.0


func configure(
		authoritative_route: PackedVector3Array,
		track_width: float,
		spawn_transform: Transform3D,
		total_laps: int = 1,
		options: Dictionary = {}
	) -> void:
	_route = authoritative_route.duplicate()
	_track_width = maxf(track_width, 4.0)
	_half_width = _track_width * 0.5
	_spawn_transform = spawn_transform
	_total_laps = maxi(total_laps, 1)
	_configured = _route.size() >= 2
	_cumulative_distances = PackedFloat32Array()
	_route_length = 0.0
	if _configured:
		_cumulative_distances.resize(_route.size())
		for index: int in range(1, _route.size()):
			_route_length += _route[index - 1].distance_to(_route[index])
			_cumulative_distances[index] = _route_length

	var shoulder_margin := maxf(float(options.get(&"shoulder_margin", maxf(4.0, _track_width * 0.30))), 1.0)
	var warning_margin := clampf(float(options.get(&"warning_margin", 1.25)), 0.25, shoulder_margin)
	_warning_limit = _half_width + warning_margin
	_legal_limit = _half_width + shoulder_margin
	_search_window = maxi(int(options.get(&"search_window", DEFAULT_SEARCH_WINDOW)), 8)
	_off_course_grace_seconds = maxf(float(options.get(&"off_course_grace_seconds", 2.4)), 0.2)
	_wrong_way_grace_seconds = maxf(float(options.get(&"wrong_way_grace_seconds", 1.4)), 0.2)
	_stuck_grace_seconds = maxf(float(options.get(&"stuck_grace_seconds", 5.5)), 0.5)
	_reset_penalty_usec = maxi(int(options.get(&"reset_penalty_usec", 2_000_000)), 0)
	_cut_penalty_usec = maxi(int(options.get(&"cut_penalty_usec", 3_000_000)), 0)
	_wrong_way_penalty_usec = maxi(int(options.get(&"wrong_way_penalty_usec", _reset_penalty_usec)), 0)
	_stuck_penalty_usec = maxi(int(options.get(&"stuck_penalty_usec", _reset_penalty_usec)), 0)
	_minimum_wrong_way_speed = maxf(float(options.get(&"minimum_wrong_way_speed", 4.0)), 1.0)
	_minimum_stuck_speed = maxf(float(options.get(&"minimum_stuck_speed", 0.8)), 0.1)
	_stuck_arm_distance = maxf(float(options.get(&"stuck_arm_distance", 2.5)), 0.5)
	_minimum_cut_jump = maxf(float(options.get(&"minimum_cut_jump", maxf(28.0, _track_width * 1.35))), 12.0)
	_rejoin_capture_interval = maxf(float(options.get(&"rejoin_capture_interval", 0.3)), 0.05)
	_closed = bool(options.get(&"closed", _detect_closed_route()))
	_configure_branch_routes(options.get(&"branch_routes", []))

	_spawn_clearance = 1.25
	if _configured:
		var spawn_projection: Dictionary = COURSE_SPLINE_SCRIPT.project_route(
			_route, _spawn_transform.origin, _cumulative_distances, -1, 0, _closed
		)
		if not spawn_projection.is_empty():
			_spawn_clearance = clampf(
				_spawn_transform.origin.y - (spawn_projection.get(&"position", _route[0]) as Vector3).y,
				1.0,
				3.0
			)
	reset(false)


func reset(keep_penalties: bool = false) -> void:
	_projection_segment = -1
	_projection_line_id = MAIN_ROUTE_LINE_ID
	_projection_line_segment = -1
	_projection = {}
	_current_lap = 1
	_inferred_lap = 1
	_seam_transition_lap = 0
	_previous_chainage = -1.0
	_previous_total_progress = -1.0
	_previous_position = Vector3.ZERO
	_has_previous_position = false
	_suppress_validation_time = 0.0
	_off_course_time = 0.0
	_wrong_way_time = 0.0
	_stuck_time = 0.0
	_rejoin_capture_time = 0.0
	_is_off_course = false
	_is_wrong_way = false
	_is_stuck = false
	_stuck_detection_armed = false
	_cut_detected = false
	_warning_code = WARNING_NONE
	_flag = FLAG_CLEAR
	_reset_requested = false
	_reset_reason = &""
	_pending_penalty_usec = 0
	_run_valid = true
	_last_legal_rejoin_transform = _spawn_transform
	_last_legal_progress = 0.0
	_incident_counts = {
		&"off_course": 0,
		&"wrong_way": 0,
		&"cuts": 0,
		&"stuck": 0,
		&"manual_resets": 0,
		&"reset_requests": 0,
		&"resets_consumed": 0,
	}
	if not keep_penalties:
		_penalty_usec = 0
		_penalty_breakdown = {}


func update(
		delta: float,
		vehicle_transform: Transform3D,
		linear_velocity: Vector3,
		lap_number: int = 0,
		active: bool = true
	) -> Dictionary:
	if not _configured:
		return get_snapshot()

	var safe_delta := clampf(delta, 0.0, 0.25)
	_suppress_validation_time = maxf(_suppress_validation_time - safe_delta, 0.0)
	if not active:
		_clear_transient_state()
		return get_snapshot()

	var position := vehicle_transform.origin
	var continuity_projection: Dictionary = COURSE_SPLINE_SCRIPT.project_route(
		_route,
		position,
		_cumulative_distances,
		_projection_segment,
		_search_window,
		_closed
	)
	if continuity_projection.is_empty():
		return get_snapshot()

	# Only escape the continuity window when the local answer is demonstrably off
	# the riding corridor.  A landing on a distant route segment then becomes a
	# measurable progression jump instead of silently changing route authority.
	var selected_projection := continuity_projection
	if float(continuity_projection.get(&"distance", INF)) > _legal_limit:
		var global_projection: Dictionary = COURSE_SPLINE_SCRIPT.project_route(
			_route, position, _cumulative_distances, -1, 0, _closed
		)
		if (
				not global_projection.is_empty()
				and float(global_projection.get(&"distance", INF)) <= _legal_limit
				and float(global_projection.get(&"distance", INF)) + 0.5
				< float(continuity_projection.get(&"distance", INF))
			):
			selected_projection = global_projection

	selected_projection = _decorate_main_projection(selected_projection)
	if not _branch_routes.is_empty():
		selected_projection = _select_route_projection(selected_projection, position)
	_projection = selected_projection.duplicate()
	_projection_segment = int(_projection.get(&"segment", _projection_segment))
	_projection_line_id = StringName(_projection.get(&"route_line_id", MAIN_ROUTE_LINE_ID))
	_projection_line_segment = int(_projection.get(&"route_line_segment", _projection_line_segment))
	var chainage := clampf(float(_projection.get(&"chainage", 0.0)), 0.0, _route_length)
	var tangent := _flat_direction(_projection.get(&"tangent", Vector3.FORWARD) as Vector3)
	var flat_velocity := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	var horizontal_speed := flat_velocity.length()
	var forward_speed := flat_velocity.dot(tangent)
	if not _stuck_detection_armed:
		var displacement_from_spawn := Vector2(position.x, position.z).distance_to(
			Vector2(_spawn_transform.origin.x, _spawn_transform.origin.z)
		)
		_stuck_detection_armed = (
			displacement_from_spawn >= _stuck_arm_distance
			or horizontal_speed >= _minimum_stuck_speed
		)

	var previous_lap := _current_lap
	_current_lap = _resolve_lap_number(lap_number, chainage, forward_speed)
	if _closed and _current_lap > previous_lap and _previous_total_progress >= 0.0:
		_seam_transition_lap = _current_lap
	elif _current_lap < previous_lap:
		_seam_transition_lap = 0
	var total_progress := _resolve_total_progress(chainage, forward_speed)
	var movement_distance := 0.0
	if _has_previous_position:
		movement_distance = Vector2(position.x, position.z).distance_to(
			Vector2(_previous_position.x, _previous_position.z)
		)

	var progress_delta := 0.0
	var allowed_progress_jump := _minimum_cut_jump
	var cut_this_update := false
	if _previous_total_progress >= 0.0 and _suppress_validation_time <= 0.0:
		progress_delta = total_progress - _previous_total_progress
		allowed_progress_jump = maxf(
			_minimum_cut_jump,
			horizontal_speed * safe_delta * 2.5 + _track_width * 0.9
		)
		cut_this_update = progress_delta > allowed_progress_jump
		if cut_this_update:
			_cut_detected = true
			_trigger_incident(WARNING_CUT, _cut_penalty_usec)

	var lateral_distance := absf(float(_projection.get(&"lateral", 0.0)))
	var route_distance := float(_projection.get(&"distance", lateral_distance))
	var active_legal_limit := float(_projection.get(&"course_limit", _legal_limit))
	_is_off_course = route_distance > active_legal_limit
	_is_wrong_way = horizontal_speed >= _minimum_wrong_way_speed and forward_speed < -_minimum_wrong_way_speed * 0.45

	if _suppress_validation_time > 0.0:
		_off_course_time = 0.0
		_wrong_way_time = 0.0
		_stuck_time = 0.0
	elif _reset_requested:
		# Freeze the evidence that caused the pending reset so HUD/results can
		# explain the ruling until the controller consumes it.
		pass
	else:
		_off_course_time = _off_course_time + safe_delta if _is_off_course else 0.0
		_wrong_way_time = _wrong_way_time + safe_delta if _is_wrong_way else 0.0
		var barely_moved := not _has_previous_position or movement_distance <= maxf(0.12, safe_delta * 0.75)
		var stuck_candidate := (
			_stuck_detection_armed
			and not _is_off_course
			and horizontal_speed < _minimum_stuck_speed
			and barely_moved
		)
		_stuck_time = _stuck_time + safe_delta if stuck_candidate else 0.0
		_is_stuck = _stuck_time >= _stuck_grace_seconds

		if _off_course_time >= _off_course_grace_seconds:
			_trigger_incident(WARNING_OFF_COURSE, _reset_penalty_usec)
		elif _wrong_way_time >= _wrong_way_grace_seconds:
			_trigger_incident(WARNING_WRONG_WAY, _wrong_way_penalty_usec)
		elif _is_stuck:
			_trigger_incident(WARNING_STUCK, _stuck_penalty_usec)

	_update_status(route_distance)
	if not cut_this_update and not _reset_requested:
		_update_last_legal_rejoin(safe_delta, position, linear_velocity, forward_speed, total_progress)

	_previous_chainage = chainage
	_previous_total_progress = total_progress
	_previous_position = position
	_has_previous_position = true
	_projection[&"total_progress"] = total_progress
	_projection[&"lap"] = _current_lap
	_projection[&"progress_delta"] = progress_delta
	_projection[&"allowed_progress_jump"] = allowed_progress_jump
	return get_snapshot()


func request_reset(reason: StringName = &"MANUAL_RESET", apply_penalty: bool = true) -> void:
	if _reset_requested:
		return
	var normalized_reason := reason if not reason.is_empty() else &"MANUAL_RESET"
	if normalized_reason == &"MANUAL_RESET":
		_increment_incident(&"manual_resets")
	_trigger_incident(normalized_reason, _reset_penalty_usec if apply_penalty else 0)


func has_reset_request() -> bool:
	return _reset_requested


func consume_reset() -> Dictionary:
	if not _reset_requested:
		return {&"requested": false}
	var response := {
		&"requested": true,
		&"transform": _last_legal_rejoin_transform,
		&"reason": _reset_reason,
		&"penalty_applied_usec": _pending_penalty_usec,
		&"total_penalty_usec": _penalty_usec,
		&"route_progress": _last_legal_progress,
	}
	_increment_incident(&"resets_consumed")
	_reset_requested = false
	_reset_reason = &""
	_pending_penalty_usec = 0
	_warning_code = WARNING_NONE
	_flag = FLAG_CLEAR
	_cut_detected = false
	_off_course_time = 0.0
	_wrong_way_time = 0.0
	_stuck_time = 0.0
	_is_off_course = false
	_is_wrong_way = false
	_is_stuck = false
	_projection_segment = -1
	_projection_line_id = MAIN_ROUTE_LINE_ID
	_projection_line_segment = -1
	_seam_transition_lap = 0
	_previous_chainage = -1.0
	_previous_total_progress = -1.0
	_has_previous_position = false
	_suppress_validation_time = DEFAULT_RESET_SUPPRESSION_SECONDS
	return response


func consume_reset_request() -> Dictionary:
	return consume_reset()


func get_snapshot() -> Dictionary:
	var chainage := float(_projection.get(&"chainage", 0.0))
	var total_progress := float(_projection.get(&"total_progress", float(_current_lap - 1) * _route_length + chainage))
	var route_line_id := StringName(_projection.get(&"route_line_id", MAIN_ROUTE_LINE_ID))
	var route_line_progress := float(_projection.get(&"route_line_progress", chainage / _route_length if _route_length > 0.0 else 0.0))
	return {
		&"configured": _configured,
		&"warning": _warning_code,
		&"message": _warning_message(),
		&"flag": _flag,
		&"race_flag": _flag,
		&"lap": _current_lap,
		&"total_laps": _total_laps,
		&"closed_route": _closed,
		&"chainage": chainage,
		&"lap_progress": chainage / _route_length if _route_length > 0.0 else 0.0,
		&"total_progress": total_progress,
		&"route_length": _route_length,
		&"segment": int(_projection.get(&"segment", -1)),
		&"route_line_id": route_line_id,
		&"route_line_progress": route_line_progress,
		&"route_line_chainage": float(_projection.get(&"route_line_chainage", chainage)),
		&"route_line_length": float(_projection.get(&"route_line_length", _route_length)),
		&"route_line_segment": int(_projection.get(&"route_line_segment", _projection.get(&"segment", -1))),
		&"route_line_position": _projection.get(&"position", Vector3.ZERO),
		&"route_line_tangent": _projection.get(&"tangent", Vector3.FORWARD),
		&"route_line_right": _projection.get(&"right", Vector3.RIGHT),
		&"lateral_distance": absf(float(_projection.get(&"lateral", 0.0))),
		&"signed_lateral": float(_projection.get(&"lateral", 0.0)),
		&"route_distance": float(_projection.get(&"distance", 0.0)),
		&"warning_limit": float(_projection.get(&"warning_limit", _warning_limit)),
		&"course_limit": float(_projection.get(&"course_limit", _legal_limit)),
		&"off_course": _is_off_course,
		&"wrong_way": _is_wrong_way,
		&"cut": _cut_detected,
		&"cut_detected": _cut_detected,
		&"stuck": _is_stuck,
		&"stuck_detection_armed": _stuck_detection_armed,
		&"off_course_time": _off_course_time,
		&"wrong_way_time": _wrong_way_time,
		&"stuck_time": _stuck_time,
		&"penalty_usec": _penalty_usec,
		&"total_penalty_usec": _penalty_usec,
		&"penalty_seconds": float(_penalty_usec) / 1_000_000.0,
		&"valid": _run_valid,
		&"run_valid": _run_valid,
		&"penalties": _penalty_breakdown.duplicate(true),
		&"incidents": _incident_counts.duplicate(true),
		&"reset_requested": _reset_requested,
		&"reset_reason": _reset_reason,
		&"pending_penalty_usec": _pending_penalty_usec,
		&"last_legal_rejoin_transform": _last_legal_rejoin_transform,
		&"last_legal_progress": _last_legal_progress,
		&"projection": _projection.duplicate(true),
	}


func get_last_legal_rejoin_transform() -> Transform3D:
	return _last_legal_rejoin_transform


func get_penalty_usec() -> int:
	return _penalty_usec


func get_projection() -> Dictionary:
	return _projection.duplicate(true)


func _configure_branch_routes(branch_value: Variant) -> void:
	_branch_routes.clear()
	if typeof(branch_value) != TYPE_ARRAY or not _configured:
		return
	var source_routes: Array = branch_value
	var used_line_ids: Dictionary = {MAIN_ROUTE_LINE_ID: true}
	for index: int in source_routes.size():
		var route_value: Variant = source_routes[index]
		if typeof(route_value) != TYPE_DICTIONARY:
			continue
		var source: Dictionary = route_value
		var points_value: Variant = source.get(&"points", PackedVector3Array())
		if typeof(points_value) != TYPE_PACKED_VECTOR3_ARRAY:
			continue
		var points: PackedVector3Array = points_value
		points = points.duplicate()
		if points.size() < 2:
			continue

		var fallback_line_id := StringName("BRANCH_%02d" % (index + 1))
		var line_id := StringName(str(source.get(&"line_id", fallback_line_id)))
		if line_id.is_empty() or used_line_ids.has(line_id):
			line_id = fallback_line_id
			while used_line_ids.has(line_id):
				line_id = StringName("%s_%02d" % [String(fallback_line_id), used_line_ids.size()])
		used_line_ids[line_id] = true

		var line_distances := _build_cumulative_distances(points)
		var line_length := float(line_distances[-1])
		if line_length <= 0.5:
			continue
		var entry_projection: Dictionary = COURSE_SPLINE_SCRIPT.project_route(
			_route, points[0], _cumulative_distances, -1, 0, _closed
		)
		var exit_projection: Dictionary = COURSE_SPLINE_SCRIPT.project_route(
			_route, points[-1], _cumulative_distances, -1, 0, _closed
		)
		if entry_projection.is_empty() or exit_projection.is_empty():
			continue
		var entry_chainage := clampf(
			float(source.get(&"entry_main_chainage", entry_projection.get(&"chainage", 0.0))),
			0.0,
			_route_length
		)
		var exit_chainage := clampf(
			float(source.get(&"exit_main_chainage", exit_projection.get(&"chainage", 0.0))),
			0.0,
			_route_length
		)
		# Racecraft branches are forward skill lines, not alternate timing loops.
		# Reject malformed/reversed records rather than making progress ambiguous.
		if exit_chainage <= entry_chainage + 0.5:
			continue
		var line_width := maxf(float(source.get(&"width", _track_width)), 2.0)
		var shoulder_margin := maxf(
			float(source.get(&"shoulder_margin", maxf(1.0, line_width * 0.25))),
			0.5
		)
		var warning_margin := clampf(
			float(source.get(&"warning_margin", minf(1.0, shoulder_margin))),
			0.25,
			shoulder_margin
		)
		_branch_routes.append({
			&"line_id": line_id,
			&"points": points,
			&"distances": line_distances,
			&"length": line_length,
			&"width": line_width,
			&"warning_limit": line_width * 0.5 + warning_margin,
			&"course_limit": line_width * 0.5 + shoulder_margin,
			&"entry_main_chainage": entry_chainage,
			&"exit_main_chainage": exit_chainage,
			&"entry_main_segment": int(source.get(&"entry_main_segment", entry_projection.get(&"segment", -1))),
			&"exit_main_segment": int(source.get(&"exit_main_segment", exit_projection.get(&"segment", -1))),
		})


func _build_cumulative_distances(points: PackedVector3Array) -> PackedFloat32Array:
	var distances := PackedFloat32Array()
	distances.resize(points.size())
	for index: int in range(1, points.size()):
		distances[index] = distances[index - 1] + points[index - 1].distance_to(points[index])
	return distances


func _decorate_main_projection(projection: Dictionary) -> Dictionary:
	var decorated := projection.duplicate()
	var chainage := clampf(float(decorated.get(&"chainage", 0.0)), 0.0, _route_length)
	decorated[&"route_line_id"] = MAIN_ROUTE_LINE_ID
	decorated[&"route_line_segment"] = int(decorated.get(&"segment", -1))
	decorated[&"route_line_fraction"] = float(decorated.get(&"fraction", 0.0))
	decorated[&"route_line_chainage"] = chainage
	decorated[&"route_line_length"] = _route_length
	decorated[&"route_line_progress"] = chainage / _route_length if _route_length > 0.0 else 0.0
	decorated[&"line_progress"] = decorated[&"route_line_progress"]
	decorated[&"route_line_width"] = _track_width
	decorated[&"warning_limit"] = _warning_limit
	decorated[&"course_limit"] = _legal_limit
	return decorated


func _select_route_projection(main_projection: Dictionary, position: Vector3) -> Dictionary:
	var best := main_projection
	var best_distance := float(best.get(&"distance", INF))
	var best_legal := best_distance <= float(best.get(&"course_limit", _legal_limit))
	for branch: Dictionary in _branch_routes:
		var line_id := StringName(branch[&"line_id"])
		var hint_segment := _projection_line_segment if _projection_line_id == line_id else -1
		var branch_projection: Dictionary = COURSE_SPLINE_SCRIPT.project_route(
			branch[&"points"] as PackedVector3Array,
			position,
			branch[&"distances"] as PackedFloat32Array,
			hint_segment,
			_search_window,
			false
		)
		if branch_projection.is_empty():
			continue
		var candidate := _decorate_branch_projection(branch_projection, branch)
		var candidate_distance := float(candidate.get(&"distance", INF))
		var candidate_legal := candidate_distance <= float(candidate[&"course_limit"])
		var replace := false
		if candidate_legal != best_legal:
			replace = candidate_legal
		elif candidate_distance < best_distance - ROUTE_SELECTION_EPSILON:
			replace = true
		elif absf(candidate_distance - best_distance) <= ROUTE_SELECTION_EPSILON:
			var best_line_id := StringName(best.get(&"route_line_id", MAIN_ROUTE_LINE_ID))
			replace = line_id == _projection_line_id and best_line_id != _projection_line_id
		if replace:
			best = candidate
			best_distance = candidate_distance
			best_legal = candidate_legal
	return best


func _decorate_branch_projection(projection: Dictionary, branch: Dictionary) -> Dictionary:
	var decorated := projection.duplicate()
	var line_length := maxf(float(branch[&"length"]), 0.001)
	var line_chainage := clampf(float(decorated.get(&"chainage", 0.0)), 0.0, line_length)
	var line_progress := clampf(line_chainage / line_length, 0.0, 1.0)
	var main_chainage := lerpf(
		float(branch[&"entry_main_chainage"]),
		float(branch[&"exit_main_chainage"]),
		line_progress
	)
	var main_sample := _sample_main_chainage(main_chainage)
	var line_segment := int(decorated.get(&"segment", -1))
	var line_fraction := float(decorated.get(&"fraction", 0.0))
	decorated[&"route_line_id"] = StringName(branch[&"line_id"])
	decorated[&"route_line_segment"] = line_segment
	decorated[&"route_line_fraction"] = line_fraction
	decorated[&"route_line_chainage"] = line_chainage
	decorated[&"route_line_length"] = line_length
	decorated[&"route_line_progress"] = line_progress
	decorated[&"line_progress"] = line_progress
	decorated[&"route_line_width"] = float(branch[&"width"])
	decorated[&"warning_limit"] = float(branch[&"warning_limit"])
	decorated[&"course_limit"] = float(branch[&"course_limit"])
	decorated[&"entry_main_chainage"] = float(branch[&"entry_main_chainage"])
	decorated[&"exit_main_chainage"] = float(branch[&"exit_main_chainage"])
	decorated[&"main_position"] = main_sample.get(&"position", decorated.get(&"position", Vector3.ZERO))
	decorated[&"main_tangent"] = main_sample.get(&"tangent", decorated.get(&"tangent", Vector3.FORWARD))
	decorated[&"main_right"] = main_sample.get(&"right", decorated.get(&"right", Vector3.RIGHT))
	# Keep the established segment/fraction contract in authoritative-main space.
	# Branch-local addressing remains available through route_line_* fields.
	decorated[&"segment"] = int(main_sample.get(&"segment", -1))
	decorated[&"fraction"] = float(main_sample.get(&"fraction", 0.0))
	decorated[&"chainage"] = main_chainage
	return decorated


func _sample_main_chainage(chainage: float) -> Dictionary:
	if _route.size() < 2:
		return {}
	var target := clampf(chainage, 0.0, _route_length)
	var low := 0
	var high := _route.size() - 2
	while low < high:
		var middle := (low + high) / 2
		if float(_cumulative_distances[middle + 1]) < target:
			low = middle + 1
		else:
			high = middle
	var segment := clampi(low, 0, _route.size() - 2)
	var start := _route[segment]
	var finish := _route[segment + 1]
	var segment_length := maxf(start.distance_to(finish), 0.000001)
	var fraction := clampf(
		(target - float(_cumulative_distances[segment])) / segment_length,
		0.0,
		1.0
	)
	var tangent := (finish - start).normalized()
	var flat_tangent := _flat_direction(tangent)
	var right := flat_tangent.cross(Vector3.UP).normalized()
	return {
		&"segment": segment,
		&"fraction": fraction,
		&"chainage": target,
		&"position": start.lerp(finish, fraction),
		&"tangent": tangent,
		&"right": right,
	}


func _resolve_lap_number(authoritative_lap: int, chainage: float, forward_speed: float) -> int:
	if authoritative_lap > 0:
		_inferred_lap = clampi(authoritative_lap, 1, _total_laps)
		return _inferred_lap
	if (
			_closed
			and _previous_chainage >= _route_length * 0.72
			and chainage <= _route_length * 0.28
			and forward_speed > -0.5
		):
		_inferred_lap = mini(_inferred_lap + 1, _total_laps)
	return _inferred_lap


func _resolve_total_progress(chainage: float, forward_speed: float) -> float:
	var lap_progress := float(_current_lap - 1) * _route_length + chainage
	if (
			not _closed
			or _previous_total_progress < 0.0
			or _route_length <= 0.001
		):
		return lap_progress

	# A closed spline represents the start/finish point twice: once at chainage
	# zero and once at route_length. The checkpoint trigger can advance the
	# authoritative lap while projection still resolves to the final segment (or
	# briefly flickers between the two aliases). Choose the seam-equivalent total
	# nearest the last physical sample so that crossing the line is continuous,
	# never an apparent whole-lap shortcut that requests a recovery.
	var seam_window := minf(
		maxf(_minimum_cut_jump, _track_width * 1.25),
		_route_length * 0.15
	)
	var wrapped_forward := (
		_previous_chainage >= _route_length - seam_window
		and chainage <= seam_window
		and forward_speed > -0.5
	)
	if _seam_transition_lap != _current_lap and not wrapped_forward:
		return lap_progress
	if wrapped_forward:
		# Projection is allowed to wrap one physics tick before the checkpoint Area
		# reports the new lap. Retain the continuous alias until authority catches up.
		_seam_transition_lap = _current_lap
	var current_near_seam := chainage <= seam_window or chainage >= _route_length - seam_window
	if not current_near_seam:
		_seam_transition_lap = 0
		return lap_progress
	var previous_near_seam := (
		_previous_chainage <= seam_window
		or _previous_chainage >= _route_length - seam_window
	)
	if not previous_near_seam:
		return lap_progress

	var best_progress := lap_progress
	var best_distance := absf(best_progress - _previous_total_progress)
	for candidate: float in [lap_progress - _route_length, lap_progress + _route_length]:
		var candidate_distance := absf(candidate - _previous_total_progress)
		if candidate_distance < best_distance:
			best_progress = candidate
			best_distance = candidate_distance
	return clampf(best_progress, 0.0, float(_total_laps) * _route_length)


func _update_last_legal_rejoin(
		delta: float,
		position: Vector3,
		linear_velocity: Vector3,
		forward_speed: float,
		total_progress: float
	) -> void:
	var route_position := _projection.get(&"position", position) as Vector3
	var vertical_separation := absf(position.y - route_position.y)
	var stable_corridor_limit := minf(
		float(_projection.get(&"course_limit", _legal_limit)),
		float(_projection.get(&"route_line_width", _track_width)) * 0.5 + 0.75
	)
	var stable_corridor := float(_projection.get(&"distance", INF)) <= stable_corridor_limit
	var stable_height := vertical_separation <= 2.75 and absf(linear_velocity.y) <= 4.5
	var stable_direction := forward_speed >= -0.5
	if not stable_corridor or not stable_height or not stable_direction:
		_rejoin_capture_time = 0.0
		return
	_rejoin_capture_time += delta
	if _rejoin_capture_time < _rejoin_capture_interval:
		return
	_rejoin_capture_time = 0.0
	_last_legal_rejoin_transform = _make_rejoin_transform(_projection)
	_last_legal_progress = total_progress


func _make_rejoin_transform(projection: Dictionary) -> Transform3D:
	var route_position := projection.get(&"position", _spawn_transform.origin) as Vector3
	var forward := _flat_direction(projection.get(&"tangent", Vector3.FORWARD) as Vector3)
	var right := forward.cross(Vector3.UP).normalized()
	if right.length_squared() < 0.5:
		right = Vector3.RIGHT
	var basis := Basis(right, Vector3.UP, -forward).orthonormalized()
	return Transform3D(basis, route_position + Vector3.UP * _spawn_clearance)


func _update_status(route_distance: float) -> void:
	if _reset_requested:
		_warning_code = _reset_reason
		_flag = FLAG_RESET
		return
	if _is_off_course:
		_warning_code = WARNING_OFF_COURSE
		_flag = FLAG_WARNING
	elif _is_wrong_way:
		_warning_code = WARNING_WRONG_WAY
		_flag = FLAG_WARNING
	elif _stuck_time >= _stuck_grace_seconds * 0.55:
		_warning_code = WARNING_STUCK
		_flag = FLAG_WARNING
	elif route_distance > float(_projection.get(&"warning_limit", _warning_limit)):
		_warning_code = WARNING_OFF_COURSE
		_flag = FLAG_WARNING
	else:
		_warning_code = WARNING_NONE
		_flag = FLAG_CLEAR


func _trigger_incident(reason: StringName, penalty: int) -> void:
	if _reset_requested:
		return
	_reset_requested = true
	_reset_reason = reason
	_pending_penalty_usec = maxi(penalty, 0)
	_warning_code = reason
	_flag = FLAG_RESET
	_increment_incident(&"reset_requests")
	match reason:
		WARNING_OFF_COURSE:
			_increment_incident(&"off_course")
		WARNING_WRONG_WAY:
			_increment_incident(&"wrong_way")
		WARNING_CUT:
			_increment_incident(&"cuts")
			_run_valid = false
		WARNING_STUCK:
			_increment_incident(&"stuck")
	if _pending_penalty_usec > 0:
		_penalty_usec += _pending_penalty_usec
		_penalty_breakdown[reason] = int(_penalty_breakdown.get(reason, 0)) + _pending_penalty_usec


func _clear_transient_state() -> void:
	_off_course_time = 0.0
	_wrong_way_time = 0.0
	_stuck_time = 0.0
	_is_off_course = false
	_is_wrong_way = false
	_is_stuck = false
	if not _reset_requested:
		_warning_code = WARNING_NONE
		_flag = FLAG_CLEAR


func _increment_incident(key: StringName) -> void:
	_incident_counts[key] = int(_incident_counts.get(key, 0)) + 1


func _warning_message() -> String:
	match _warning_code:
		WARNING_OFF_COURSE:
			return "RETURN TO COURSE"
		WARNING_WRONG_WAY:
			return "WRONG WAY"
		WARNING_CUT:
			return "COURSE CUT - RESET REQUIRED"
		WARNING_STUCK:
			return "BIKE STUCK - RESET AVAILABLE"
		&"MANUAL_RESET":
			return "RESETTING TO LAST SAFE POINT"
	return ""


func _detect_closed_route() -> bool:
	if _route.size() < 3:
		return false
	var first := Vector2(_route[0].x, _route[0].z)
	var last := Vector2(_route[_route.size() - 1].x, _route[_route.size() - 1].z)
	return first.distance_to(last) <= maxf(2.0, _track_width * 0.45)


func _flat_direction(direction: Vector3) -> Vector3:
	var flat := Vector3(direction.x, 0.0, direction.z)
	return flat.normalized() if flat.length_squared() > 0.0001 else Vector3.FORWARD
