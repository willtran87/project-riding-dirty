extends Node3D
## Deterministic production-world traversal proof for every authoritative course.
##
## A CharacterBody3D carries the player's exact chassis and handlebar collision
## envelopes along the production center line (with an optional three-line stress
## mode). Every raw route sample audits support/grade, while body advances combine
## no more than four metres into a continuous shape sweep. Real loaded collision
## supplies the support path, so
## terrain over the ribbon, containment crossing a lane, missing collision, and
## unsafe non-authored steps all fail the release probe.

signal lane_audit_finished(report: Dictionary)

const MAIN_SCENE := preload("res://scenes/main.tscn")
const TRACK_IDS: Array[StringName] = [
	CourseCatalog.QUARRY_ID,
	CourseCatalog.PINE_ID,
	CourseCatalog.MESA_MX_ID,
]
const LANE_RATIOS: Array[float] = [-0.32, 0.0, 0.32]
const DEFAULT_LANE_RATIOS: Array[float] = [0.0]
const STEPS_PER_PHYSICS_TICK := 32
const MAX_CONTINUOUS_SWEEP_CHAINAGE := 4.0
const OPEN_RIBBON_ENDPOINT_INSET := 0.02
const SUPPORT_RAY_UP := 35.0
const SUPPORT_RAY_DOWN := 18.0
const PLAYER_ROOT_CLEARANCE := 0.67
const PLAYER_CHASSIS_RADIUS := 0.31
const PLAYER_CHASSIS_HEIGHT := 1.197989
const PLAYER_CHASSIS_LOCAL_Y := 0.16
const PLAYER_CHASSIS_LOCAL_Z := 0.130365
const PLAYER_HANDLEBAR_RADIUS := 0.045
const PLAYER_HANDLEBAR_HEIGHT := 0.93
const PLAYER_HANDLEBAR_LOCAL := Vector3(0.0, 0.82, -0.371119)
const PROVEN_CHASSIS_BOTTOM_CLEARANCE := (
	PLAYER_ROOT_CLEARANCE + PLAYER_CHASSIS_LOCAL_Y - PLAYER_CHASSIS_RADIUS
)
const TRAVERSAL_SPEED_MPS := 18.0
const BIKE_GRAVITY_SCALE := 0.612245
# The spline is horizontally sampled at 0.72-1.05 m, but 3D spacing grows on
# jump faces and banked relief. A two-metre cap still catches a missing sample or
# broken seam without misclassifying intentional elevation within one sample.
const MAX_SAMPLE_GAP := 2.00
const MAX_ORDINARY_STEP := 0.82
const MAX_AUTHORED_STEP := 3.60
const MAX_ORDINARY_GRADE_DEGREES := 42.0
const MAX_AUTHORED_GRADE_DEGREES := 70.0
const MIN_ORDINARY_NORMAL_Y := 0.57
const MIN_AUTHORED_NORMAL_Y := 0.30
const MIN_POST_GATE_8_MOVES_PER_LANE := 40

var _main: Node3D
var _walker: CharacterBody3D
var _chassis_collision: CollisionShape3D
var _handlebar_collision: CollisionShape3D
var _audit_active := false
var _track_id: StringName = &""
var _route := PackedVector3Array()
var _chainages := PackedFloat32Array()
var _lane_offset := 0.0
var _sample_index := 0
var _lane_metrics: Dictionary = {}
var _previous_support := Vector3.ZERO
var _previous_root := Vector3.ZERO
var _previous_support_node: Node
var _previous_chainage := 0.0
var _previous_support_slope := 0.0
var _airborne := false
var _vertical_velocity := 0.0
var _gate_8_start_chainage := INF
var _gate_8_end_chainage := -INF
var _watchdog_stage := &"BOOT"
var _selected_track_ids: Array[StringName] = TRACK_IDS.duplicate()
var _selected_lane_ratios: Array[float] = DEFAULT_LANE_RATIOS.duplicate()
var _last_swept_sample_index := 0
var _last_sweep_chainage := 0.0
var _pending_post_gate_8_moves := 0


func _ready() -> void:
	Profile.persistence_enabled = false
	_parse_arguments()
	_create_player_envelope()
	get_tree().create_timer(240.0, true).timeout.connect(_on_watchdog_timeout)
	_run.call_deferred()


func _parse_arguments() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--track="):
			var requested := StringName(argument.trim_prefix("--track=").to_upper())
			if requested in TRACK_IDS:
				_selected_track_ids = [requested]
		elif argument == "--center-only":
			_selected_lane_ratios = DEFAULT_LANE_RATIOS.duplicate()
		elif argument == "--three-lines":
			_selected_lane_ratios = LANE_RATIOS.duplicate()


func _create_player_envelope() -> void:
	_walker = CharacterBody3D.new()
	_walker.name = "ContinuousPlayerEnvelope"
	# The envelope is represented by a body so its exact local transforms match
	# the player scene, but it remains outside the broadphase. Each accepted
	# advance is proven by direct continuous shape casts before the transform is
	# updated, avoiding thousands of costly body remove/reinsert operations.
	_walker.collision_layer = 0
	_walker.collision_mask = 0
	_walker.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	_walker.safe_margin = 0.001
	add_child(_walker)

	var chassis_shape := CapsuleShape3D.new()
	chassis_shape.radius = PLAYER_CHASSIS_RADIUS
	chassis_shape.height = PLAYER_CHASSIS_HEIGHT
	_chassis_collision = CollisionShape3D.new()
	_chassis_collision.name = "PlayerChassisEnvelope"
	_chassis_collision.position = Vector3(
		0.0, PLAYER_CHASSIS_LOCAL_Y, PLAYER_CHASSIS_LOCAL_Z
	)
	_chassis_collision.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	_chassis_collision.shape = chassis_shape
	_walker.add_child(_chassis_collision)

	var handlebar_shape := CapsuleShape3D.new()
	handlebar_shape.radius = PLAYER_HANDLEBAR_RADIUS
	handlebar_shape.height = PLAYER_HANDLEBAR_HEIGHT
	_handlebar_collision = CollisionShape3D.new()
	_handlebar_collision.name = "PlayerHandlebarEnvelope"
	_handlebar_collision.position = PLAYER_HANDLEBAR_LOCAL
	_handlebar_collision.rotation = Vector3(0.0, 0.0, PI * 0.5)
	_handlebar_collision.shape = handlebar_shape
	_walker.add_child(_handlebar_collision)


func _run() -> void:
	_watchdog_stage = &"INSTANTIATING_MAIN"
	_main = MAIN_SCENE.instantiate() as Node3D
	add_child(_main)
	for _frame: int in 3:
		await get_tree().physics_frame

	var passed := true
	var quarry_post_gate_8: Array[Dictionary] = []
	for track_id: StringName in _selected_track_ids:
		_watchdog_stage = StringName("STREAMING_%s" % String(track_id))
		_walker.collision_mask = 0
		_main.call(&"_ensure_track_loaded", track_id)
		for _frame: int in 3:
			await get_tree().physics_frame
		var route: PackedVector3Array = _main.call(&"get_authoritative_route", track_id)
		var route_chainages := _build_chainages(route)
		var gate_window := _quarry_gate_8_window(track_id, route, route_chainages)
		var lane_reports: Array[Dictionary] = []
		for lane_ratio: float in _selected_lane_ratios:
			_watchdog_stage = StringName(
				"TRAVERSING_%s_%+.2f" % [String(track_id), lane_ratio]
			)
			var lane_report := await _audit_lane(
				track_id,
				route,
				route_chainages,
				lane_ratio * CourseCatalog.get_track_width(track_id),
				gate_window
			) as Dictionary
			lane_reports.append(lane_report)
			passed = bool(lane_report.get(&"passed", false)) and passed
			if track_id == CourseCatalog.QUARRY_ID:
				quarry_post_gate_8.append(lane_report.get(&"post_gate_8", {}) as Dictionary)
		var track_report := _summarize_track(track_id, route, lane_reports)
		passed = bool(track_report.get(&"passed", false)) and passed

	var quarry_selected := CourseCatalog.QUARRY_ID in _selected_track_ids
	var post_gate_passed := (
		_print_quarry_post_gate_8(quarry_post_gate_8) if quarry_selected else true
	)
	passed = post_gate_passed and passed
	print("PHYSICAL ROUTE TRAVERSABILITY SUMMARY: tracks=%d lanes=%d exact_player_envelope=true continuous_moves=true teleports_after_start=0 post_gate_8=%s passed=%s" % [
		_selected_track_ids.size(),
		_selected_track_ids.size() * _selected_lane_ratios.size(),
		str(post_gate_passed), str(passed),
	])
	_walker.collision_mask = 0
	_main.queue_free()
	await get_tree().physics_frame
	get_tree().quit(0 if passed else 1)


func _physics_process(_delta: float) -> void:
	if not _audit_active:
		return
	for _step: int in STEPS_PER_PHYSICS_TICK:
		if _sample_index >= _route.size():
			_finish_lane(true)
			return
		if not _advance_one_sample():
			_finish_lane(false)
			return
		_sample_index += 1
		if (
			OS.get_environment("RIDING_DIRTY_PROFILE_TRAVERSABILITY") == "1"
			and _sample_index % 128 == 0
		):
			print("PHYSICAL ROUTE PROGRESS: track=%s lane=%+.2f sample=%d/%d sweeps=%d" % [
				String(_track_id), _lane_offset, _sample_index, _route.size(),
				int(_lane_metrics.get(&"continuous_sweeps", 0)),
			])


func _audit_lane(
	track_id: StringName,
	route: PackedVector3Array,
	chainages: PackedFloat32Array,
	lane_offset: float,
	gate_window: Vector2
) -> Dictionary:
	_track_id = track_id
	_route = route
	_chainages = chainages
	_lane_offset = lane_offset
	_sample_index = 0
	_previous_support = Vector3.ZERO
	_previous_root = Vector3.ZERO
	_previous_support_node = null
	_previous_chainage = 0.0
	_previous_support_slope = 0.0
	_airborne = false
	_vertical_velocity = 0.0
	_last_swept_sample_index = 0
	_last_sweep_chainage = 0.0
	_pending_post_gate_8_moves = 0
	_gate_8_start_chainage = gate_window.x
	_gate_8_end_chainage = gate_window.y
	_lane_metrics = {
		&"track_id": track_id,
		&"lane_offset": lane_offset,
		&"samples": 0,
		&"moves": 0,
		&"continuous_sweeps": 0,
		&"maximum_sweep_distance": 0.0,
		&"route_length": chainages[-1] if not chainages.is_empty() else 0.0,
		&"maximum_sample_gap": 0.0,
		&"maximum_support_step": 0.0,
		&"maximum_grade_degrees": 0.0,
		&"minimum_normal_y": 1.0,
		&"minimum_support_offset": INF,
		&"maximum_support_offset": -INF,
		&"authored_launches": 0,
		&"support_failures": 0,
		&"non_authoritative_support": 0,
		&"blocking_contacts": 0,
		&"containment_intrusions": 0,
		&"envelope_overlaps": 0,
		&"unsafe_steps": 0,
		&"first_failure": {},
		&"post_gate_8": {
			&"lane_offset": lane_offset,
			&"samples": 0,
			&"moves": 0,
			&"blocking_contacts": 0,
			&"containment_intrusions": 0,
			&"maximum_support_step": 0.0,
			&"maximum_grade_degrees": 0.0,
			&"minimum_normal_y": 1.0,
		},
	}
	_walker.collision_mask = 0
	_audit_active = true
	var report: Dictionary = await lane_audit_finished
	return report


func _advance_one_sample() -> bool:
	var route_point := _lane_route_point(_sample_index)
	# A ray cast exactly through the first or last vertex row of an open concave
	# mesh is numerically ambiguous at its outer lanes. Inset by two centimetres;
	# the 31 cm chassis radius still covers the complete authored endpoint while
	# support is sampled from a triangle interior on every lane.
	var support_query_point := route_point
	if _sample_index == 0:
		support_query_point += _route_tangent(_sample_index).normalized() * OPEN_RIBBON_ENDPOINT_INSET
	elif _sample_index == _route.size() - 1:
		support_query_point -= _route_tangent(_sample_index).normalized() * OPEN_RIBBON_ENDPOINT_INSET
	var support_hit := _sample_support(support_query_point)
	if support_hit.is_empty():
		_lane_metrics[&"support_failures"] = int(_lane_metrics[&"support_failures"]) + 1
		_record_failure(&"MISSING_SUPPORT", route_point, null)
		return false
	var support_node := support_hit.get(&"collider") as Node
	if not _node_has_authority(support_node, _track_id):
		_lane_metrics[&"non_authoritative_support"] = int(
			_lane_metrics[&"non_authoritative_support"]
		) + 1
		if _is_containment(support_node):
			_lane_metrics[&"containment_intrusions"] = int(
				_lane_metrics[&"containment_intrusions"]
			) + 1
		_record_failure(&"NON_AUTHORITATIVE_SUPPORT", route_point, support_node)
		var failure: Dictionary = _lane_metrics[&"first_failure"]
		failure[&"support_position"] = support_hit.get(&"position", Vector3.ZERO)
		failure[&"support_offset"] = (
			(support_hit.get(&"position", route_point) as Vector3).y - route_point.y
		)
		failure[&"collider_path"] = String(support_node.get_path()) if support_node != null else "NONE"
		return false

	var support: Vector3 = support_hit[&"position"]
	var normal: Vector3 = (support_hit[&"normal"] as Vector3).normalized()
	var chainage := float(_chainages[_sample_index])
	var support_offset := support.y - route_point.y
	_lane_metrics[&"samples"] = int(_lane_metrics[&"samples"]) + 1
	_lane_metrics[&"minimum_normal_y"] = minf(
		float(_lane_metrics[&"minimum_normal_y"]), normal.y
	)
	_lane_metrics[&"minimum_support_offset"] = minf(
		float(_lane_metrics[&"minimum_support_offset"]), support_offset
	)
	_lane_metrics[&"maximum_support_offset"] = maxf(
		float(_lane_metrics[&"maximum_support_offset"]), support_offset
	)
	var in_post_gate_8 := _is_in_post_gate_8(chainage)
	if in_post_gate_8:
		var post: Dictionary = _lane_metrics[&"post_gate_8"]
		post[&"samples"] = int(post[&"samples"]) + 1
		post[&"minimum_normal_y"] = minf(float(post[&"minimum_normal_y"]), normal.y)

	var tangent := _route_tangent(_sample_index)
	var basis := Basis.looking_at(tangent, normal).orthonormalized()
	var nominal_root := support + basis.y * PLAYER_ROOT_CLEARANCE
	if _sample_index == 0:
		_walker.global_transform = Transform3D(basis, nominal_root)
		_previous_support = support
		_previous_root = nominal_root
		_previous_support_node = support_node
		_previous_chainage = chainage
		if _player_envelope_overlaps_world():
			_lane_metrics[&"envelope_overlaps"] = int(_lane_metrics[&"envelope_overlaps"]) + 1
			_record_failure(&"START_ENVELOPE_OVERLAP", nominal_root, _first_overlap_collider())
			return false
		return true

	var route_gap := _route[_sample_index - 1].distance_to(_route[_sample_index])
	var horizontal_gap := Vector2(
		support.x - _previous_support.x, support.z - _previous_support.z
	).length()
	var support_delta := support.y - _previous_support.y
	var support_step := absf(support_delta)
	var grade_degrees := rad_to_deg(atan2(absf(support_delta), maxf(horizontal_gap, 0.001)))
	var authored_transition := _is_authored_transition(
		_previous_support_node, support_node, _previous_chainage, chainage
	)
	var maximum_step := MAX_AUTHORED_STEP if authored_transition else MAX_ORDINARY_STEP
	var maximum_grade := (
		MAX_AUTHORED_GRADE_DEGREES
		if authored_transition
		else MAX_ORDINARY_GRADE_DEGREES
	)
	var minimum_normal_y := (
		MIN_AUTHORED_NORMAL_Y if authored_transition else MIN_ORDINARY_NORMAL_Y
	)
	_lane_metrics[&"maximum_sample_gap"] = maxf(
		float(_lane_metrics[&"maximum_sample_gap"]), route_gap
	)
	_lane_metrics[&"maximum_support_step"] = maxf(
		float(_lane_metrics[&"maximum_support_step"]), support_step
	)
	_lane_metrics[&"maximum_grade_degrees"] = maxf(
		float(_lane_metrics[&"maximum_grade_degrees"]), grade_degrees
	)
	if in_post_gate_8:
		var post: Dictionary = _lane_metrics[&"post_gate_8"]
		post[&"maximum_support_step"] = maxf(
			float(post[&"maximum_support_step"]), support_step
		)
		post[&"maximum_grade_degrees"] = maxf(
			float(post[&"maximum_grade_degrees"]), grade_degrees
		)
	if (
		route_gap > MAX_SAMPLE_GAP
		or support_step > maximum_step
		or grade_degrees > maximum_grade
		or normal.y < minimum_normal_y
	):
		_lane_metrics[&"unsafe_steps"] = int(_lane_metrics[&"unsafe_steps"]) + 1
		_record_failure(&"UNSAFE_SUPPORT_TRANSITION", support, support_node)
		var failure: Dictionary = _lane_metrics[&"first_failure"]
		failure[&"route_gap"] = route_gap
		failure[&"horizontal_gap"] = horizontal_gap
		failure[&"support_delta"] = support_delta
		failure[&"support_step"] = support_step
		failure[&"grade_degrees"] = grade_degrees
		failure[&"normal_y"] = normal.y
		failure[&"authored_transition"] = authored_transition
		failure[&"previous_collider"] = (
			String(_previous_support_node.name) if _previous_support_node != null else "NONE"
		)
		return false

	var support_slope := support_delta / maxf(horizontal_gap, 0.001)
	var was_airborne := _airborne
	var launch_now := (
		not _airborne
		and authored_transition
		and support_slope < -0.16
		and (_previous_support_slope > 0.06 or support_step > 1.0)
	)
	if launch_now:
		_airborne = true
		_vertical_velocity = maxf(_previous_support_slope * TRAVERSAL_SPEED_MPS, 2.4)
		_lane_metrics[&"authored_launches"] = int(_lane_metrics[&"authored_launches"]) + 1

	var target_root := nominal_root
	var movement_up := normal
	if _airborne:
		var travel_time := horizontal_gap / TRAVERSAL_SPEED_MPS
		var gravity := float(ProjectSettings.get_setting(
			"physics/3d/default_gravity", 9.8
		)) * BIKE_GRAVITY_SCALE
		var ballistic_y := (
			_previous_root.y + _vertical_velocity * travel_time
			- 0.5 * gravity * travel_time * travel_time
		)
		_vertical_velocity -= gravity * travel_time
		if ballistic_y > nominal_root.y + 0.04:
			target_root.y = ballistic_y
			movement_up = Vector3.UP
		else:
			_airborne = false
			_vertical_velocity = 0.0
	var landed_now := was_airborne and not _airborne
	if in_post_gate_8:
		_pending_post_gate_8_moves += 1
	var should_sweep := (
		chainage - _last_sweep_chainage >= MAX_CONTINUOUS_SWEEP_CHAINAGE
		or authored_transition
		or launch_now
		or _airborne
		or landed_now
		or _sample_index == _route.size() - 1
	)
	if not should_sweep:
		_previous_support = support
		_previous_root = target_root
		_previous_support_node = support_node
		_previous_chainage = chainage
		_previous_support_slope = support_slope
		return true

	var motion := target_root - _walker.global_position
	var movement_tangent := motion.normalized() if motion.length_squared() > 0.000001 else tangent
	var target_basis := Basis.looking_at(movement_tangent, movement_up).orthonormalized()
	# Pitch the longitudinal capsule into the proven travel vector before casting,
	# as the real bike chassis does through its suspension attitude. Check that
	# rotation at the current endpoint independently so rotation cannot hide an
	# intrusion that the subsequent translational cast would miss.
	_walker.global_basis = target_basis
	if _player_envelope_overlaps_world():
		_lane_metrics[&"envelope_overlaps"] = int(_lane_metrics[&"envelope_overlaps"]) + 1
		var rotated_collider := _first_overlap_collider()
		if _is_containment(rotated_collider):
			_lane_metrics[&"containment_intrusions"] = int(
				_lane_metrics[&"containment_intrusions"]
			) + 1
		_record_failure(&"PRE_SWEEP_ROTATION_OVERLAP", _walker.global_position, rotated_collider)
		return false
	var sweep_hit := _sweep_player_envelope(motion)
	if not sweep_hit.is_empty():
		var collider := sweep_hit.get(&"collider") as Node
		_lane_metrics[&"blocking_contacts"] = int(_lane_metrics[&"blocking_contacts"]) + 1
		if in_post_gate_8:
			var post: Dictionary = _lane_metrics[&"post_gate_8"]
			post[&"blocking_contacts"] = int(post[&"blocking_contacts"]) + 1
		if _is_containment(collider):
			_lane_metrics[&"containment_intrusions"] = int(
				_lane_metrics[&"containment_intrusions"]
			) + 1
			if in_post_gate_8:
				var post: Dictionary = _lane_metrics[&"post_gate_8"]
				post[&"containment_intrusions"] = int(post[&"containment_intrusions"]) + 1
		_record_failure(
			&"BLOCKING_SWEEP",
			sweep_hit.get(&"position", _walker.global_position) as Vector3,
			collider
		)
		var failure: Dictionary = _lane_metrics[&"first_failure"]
		failure[&"shape"] = sweep_hit.get(&"shape", "UNKNOWN")
		failure[&"safe_fraction"] = sweep_hit.get(&"safe_fraction", -1.0)
		failure[&"motion"] = motion
		failure[&"authored_transition"] = authored_transition
		failure[&"airborne"] = _airborne
		failure[&"support_delta"] = support_delta
		return false
	# Advancing the transform is safe only after both player shapes returned a
	# complete [0, 1] motion fraction. This is an adjacent-sample sweep, never a
	# gate-to-gate teleport.
	_walker.global_position += motion
	if _player_envelope_overlaps_world():
		_lane_metrics[&"envelope_overlaps"] = int(_lane_metrics[&"envelope_overlaps"]) + 1
		var overlap_collider := _first_overlap_collider()
		if _is_containment(overlap_collider):
			_lane_metrics[&"containment_intrusions"] = int(
				_lane_metrics[&"containment_intrusions"]
			) + 1
		_record_failure(&"ROTATED_ENVELOPE_OVERLAP", _walker.global_position, overlap_collider)
		return false
	var covered_moves := _sample_index - _last_swept_sample_index
	_lane_metrics[&"moves"] = int(_lane_metrics[&"moves"]) + covered_moves
	_lane_metrics[&"continuous_sweeps"] = int(_lane_metrics[&"continuous_sweeps"]) + 1
	_lane_metrics[&"maximum_sweep_distance"] = maxf(
		float(_lane_metrics[&"maximum_sweep_distance"]), motion.length()
	)
	if _pending_post_gate_8_moves > 0:
		var post: Dictionary = _lane_metrics[&"post_gate_8"]
		post[&"moves"] = int(post[&"moves"]) + _pending_post_gate_8_moves
	_pending_post_gate_8_moves = 0
	_last_swept_sample_index = _sample_index
	_last_sweep_chainage = chainage
	_previous_support = support
	_previous_root = target_root
	_previous_support_node = support_node
	_previous_chainage = chainage
	_previous_support_slope = support_slope
	return true


func _sample_support(route_point: Vector3) -> Dictionary:
	var exclusions: Array[RID] = [_walker.get_rid()]
	var alternate_hit: Dictionary = {}
	for _depth: int in 4:
		var query := PhysicsRayQueryParameters3D.create(
			route_point + Vector3.UP * SUPPORT_RAY_UP,
			route_point - Vector3.UP * SUPPORT_RAY_DOWN,
			2
		)
		query.collide_with_areas = false
		query.collide_with_bodies = true
		query.exclude = exclusions
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty() or _node_has_authority(hit.get(&"collider") as Node, _track_id):
			if not alternate_hit.is_empty() and not hit.is_empty():
				# Alternate ribbons share the same physical collision world and can be
				# returned first at a coplanar branch seam. Accept only a genuinely
				# welded seam whose top differs from the authoritative main ribbon by
				# no more than 12 cm; a raised crossing still fails as an obstruction.
				var alternate_position: Vector3 = alternate_hit[&"position"]
				var authority_position: Vector3 = hit[&"position"]
				if absf(alternate_position.y - authority_position.y) <= 0.12:
					var welded_hit := alternate_hit.duplicate()
					welded_hit[&"physical_collider"] = alternate_hit.get(&"collider")
					welded_hit[&"collider"] = hit.get(&"collider")
					return welded_hit
				return alternate_hit
			return hit
		var collider := hit.get(&"collider") as Node
		if not _is_alternate_ribbon(collider):
			return hit
		if alternate_hit.is_empty():
			alternate_hit = hit
		if collider is CollisionObject3D:
			exclusions.append((collider as CollisionObject3D).get_rid())
		else:
			return hit
	return alternate_hit


func _is_alternate_ribbon(node: Node) -> bool:
	var current := node
	while current != null:
		if String(current.name).contains("Alternate"):
			return true
		current = current.get_parent()
	return false


func _sweep_player_envelope(motion: Vector3) -> Dictionary:
	var space_state := get_world_3d().direct_space_state
	for shape_node: CollisionShape3D in [_chassis_collision, _handlebar_collision]:
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape_node.shape
		query.transform = shape_node.global_transform
		query.motion = motion
		query.margin = 0.001
		query.collision_mask = 2
		query.collide_with_areas = false
		query.collide_with_bodies = true
		var fractions := space_state.cast_motion(query)
		if fractions.size() < 2 or fractions[0] >= 0.99999:
			continue
		var impact_query := PhysicsShapeQueryParameters3D.new()
		impact_query.shape = shape_node.shape
		var impact_transform := query.transform
		impact_transform.origin += motion * minf(fractions[1] + 0.0005, 1.0)
		impact_query.transform = impact_transform
		impact_query.margin = 0.002
		impact_query.collision_mask = 2
		impact_query.collide_with_areas = false
		impact_query.collide_with_bodies = true
		var overlaps := space_state.intersect_shape(impact_query, 8)
		var collider := overlaps[0].get(&"collider") as Node if not overlaps.is_empty() else null
		return {
			&"collider": collider,
			&"position": _walker.global_position + motion * fractions[0],
			&"safe_fraction": fractions[0],
			&"shape": String(shape_node.name),
		}
	return {}


func _player_envelope_overlaps_world() -> bool:
	return _first_overlap_collider() != null


func _first_overlap_collider() -> Node:
	for shape_node: CollisionShape3D in [_chassis_collision, _handlebar_collision]:
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape_node.shape
		query.transform = shape_node.global_transform
		query.collision_mask = 2
		query.collide_with_areas = false
		query.collide_with_bodies = true
		query.exclude = [_walker.get_rid()]
		var overlaps := get_world_3d().direct_space_state.intersect_shape(query, 8)
		if not overlaps.is_empty():
			return overlaps[0].get(&"collider") as Node
	return null


func _lane_route_point(index: int) -> Vector3:
	var tangent := _route_tangent(index)
	var flat_tangent := Vector3(tangent.x, 0.0, tangent.z).normalized()
	var right := flat_tangent.cross(Vector3.UP).normalized()
	return _route[index] + right * _lane_offset


func _route_tangent(index: int) -> Vector3:
	if _route.size() < 2:
		return Vector3.FORWARD
	var first := maxi(index - 1, 0)
	var second := mini(index + 1, _route.size() - 1)
	var tangent := (_route[second] - _route[first]).normalized()
	return tangent if tangent.length_squared() > 0.001 else Vector3.FORWARD


func _is_authored_transition(
	previous_node: Node,
	current_node: Node,
	previous_chainage: float,
	current_chainage: float
) -> bool:
	if _node_has_airtime_role(previous_node) or _node_has_airtime_role(current_node):
		return true
	for zone: Dictionary in CourseCatalog.get_welded_jump_zones(_track_id):
		var start := float(zone.get(&"start", INF)) - 2.0
		var finish := (
			float(zone.get(&"receiver_start", -INF))
			+ float(zone.get(&"receiver_length", 0.0))
			+ 2.0
		)
		if current_chainage >= start and previous_chainage <= finish:
			return true
	return false


func _node_has_airtime_role(node: Node) -> bool:
	var current := node
	while current != null:
		if (
			bool(current.get_meta(&"airtime_takeoff", false))
			or current.is_in_group(&"airtime_takeoff")
			or StringName(current.get_meta(&"rhythm_role", &"")) in [&"TAKEOFF", &"LANDING"]
		):
			return true
		current = current.get_parent()
	return false


func _node_has_authority(node: Node, track_id: StringName) -> bool:
	var current := node
	while current != null:
		if bool(current.get_meta(&"authoritative_track_surface", false)):
			return StringName(current.get_meta(&"authoritative_track_id", &"")) == track_id
		current = current.get_parent()
	return false


func _is_containment(node: Node) -> bool:
	var current := node
	while current != null:
		if (
			bool(current.get_meta(&"course_containment", false))
			or current.is_in_group(&"course_containment")
		):
			return true
		current = current.get_parent()
	return false


func _record_failure(reason: StringName, position: Vector3, collider: Node) -> void:
	if not (_lane_metrics[&"first_failure"] as Dictionary).is_empty():
		return
	_lane_metrics[&"first_failure"] = {
		&"reason": reason,
		&"sample_index": _sample_index,
		&"chainage": (
			float(_chainages[_sample_index])
			if _sample_index < _chainages.size()
			else -1.0
		),
		&"position": position,
		&"collider": String(collider.name) if collider != null else "NONE",
	}


func _finish_lane(completed: bool) -> void:
	_audit_active = false
	_walker.collision_mask = 0
	var expected_moves := maxi(_route.size() - 1, 0)
	var passed := (
		completed
		and int(_lane_metrics[&"samples"]) == _route.size()
		and int(_lane_metrics[&"moves"]) == expected_moves
		and int(_lane_metrics[&"support_failures"]) == 0
		and int(_lane_metrics[&"non_authoritative_support"]) == 0
		and int(_lane_metrics[&"blocking_contacts"]) == 0
		and int(_lane_metrics[&"containment_intrusions"]) == 0
		and int(_lane_metrics[&"envelope_overlaps"]) == 0
		and int(_lane_metrics[&"unsafe_steps"]) == 0
	)
	_lane_metrics[&"passed"] = passed
	print((
		"PHYSICAL ROUTE LANE: track=%s lane=%+.2fm samples=%d/%d moves=%d/%d "
		+ "distance=%.1fm max_gap=%.3fm max_step=%.3fm max_grade=%.2fdeg "
		+ "min_normal_y=%.3f support_offset=%.3f..%.3fm chassis_clearance=%.3fm "
		+ "sweeps=%d max_sweep=%.3fm launches=%d blockers=%d containment=%d overlaps=%d unsafe=%d failure=%s passed=%s"
		) % [
			String(_track_id), _lane_offset, int(_lane_metrics[&"samples"]), _route.size(),
			int(_lane_metrics[&"moves"]), expected_moves,
			float(_lane_metrics[&"route_length"]),
			float(_lane_metrics[&"maximum_sample_gap"]),
			float(_lane_metrics[&"maximum_support_step"]),
			float(_lane_metrics[&"maximum_grade_degrees"]),
			float(_lane_metrics[&"minimum_normal_y"]),
			float(_lane_metrics[&"minimum_support_offset"]),
			float(_lane_metrics[&"maximum_support_offset"]),
			PROVEN_CHASSIS_BOTTOM_CLEARANCE,
			int(_lane_metrics[&"continuous_sweeps"]),
			float(_lane_metrics[&"maximum_sweep_distance"]),
			int(_lane_metrics[&"authored_launches"]),
			int(_lane_metrics[&"blocking_contacts"]),
			int(_lane_metrics[&"containment_intrusions"]),
			int(_lane_metrics[&"envelope_overlaps"]),
			int(_lane_metrics[&"unsafe_steps"]),
			str(_lane_metrics[&"first_failure"]), str(passed),
		]
	)
	lane_audit_finished.emit(_lane_metrics.duplicate(true))


func _build_chainages(route: PackedVector3Array) -> PackedFloat32Array:
	var chainages := PackedFloat32Array()
	chainages.resize(route.size())
	for index: int in range(1, route.size()):
		chainages[index] = chainages[index - 1] + route[index - 1].distance_to(route[index])
	return chainages


func _quarry_gate_8_window(
	track_id: StringName,
	route: PackedVector3Array,
	chainages: PackedFloat32Array
) -> Vector2:
	if track_id != CourseCatalog.QUARRY_ID:
		return Vector2(INF, -INF)
	var indices := CourseCatalog.get_checkpoint_route_indices(track_id, route)
	if indices.size() < 9:
		return Vector2(INF, -INF)
	return Vector2(chainages[indices[7]], chainages[indices[8]])


func _is_in_post_gate_8(chainage: float) -> bool:
	return (
		_track_id == CourseCatalog.QUARRY_ID
		and chainage >= _gate_8_start_chainage
		and chainage <= _gate_8_end_chainage
	)


func _summarize_track(
	track_id: StringName,
	route: PackedVector3Array,
	lane_reports: Array[Dictionary]
) -> Dictionary:
	var passed := lane_reports.size() == _selected_lane_ratios.size()
	var moves := 0
	var blockers := 0
	var containment := 0
	var support_failures := 0
	var maximum_step := 0.0
	var maximum_grade := 0.0
	var minimum_normal_y := 1.0
	for report: Dictionary in lane_reports:
		passed = bool(report.get(&"passed", false)) and passed
		moves += int(report.get(&"moves", 0))
		blockers += int(report.get(&"blocking_contacts", 0))
		containment += int(report.get(&"containment_intrusions", 0))
		support_failures += int(report.get(&"support_failures", 0))
		maximum_step = maxf(maximum_step, float(report.get(&"maximum_support_step", 0.0)))
		maximum_grade = maxf(maximum_grade, float(report.get(&"maximum_grade_degrees", 0.0)))
		minimum_normal_y = minf(minimum_normal_y, float(report.get(&"minimum_normal_y", 1.0)))
	var expected_moves := maxi(route.size() - 1, 0) * _selected_lane_ratios.size()
	passed = moves == expected_moves and passed
	print("PHYSICAL ROUTE TRACK: track=%s route_points=%d lanes=%d moves=%d/%d blockers=%d containment=%d support_failures=%d max_step=%.3fm max_grade=%.2fdeg min_normal_y=%.3f passed=%s" % [
		String(track_id), route.size(), lane_reports.size(), moves, expected_moves,
		blockers, containment, support_failures, maximum_step, maximum_grade,
		minimum_normal_y, str(passed),
	])
	return {&"passed": passed}


func _print_quarry_post_gate_8(reports: Array[Dictionary]) -> bool:
	var passed := reports.size() == _selected_lane_ratios.size()
	var samples := 0
	var moves := 0
	var blockers := 0
	var containment := 0
	var maximum_step := 0.0
	var maximum_grade := 0.0
	var minimum_normal_y := 1.0
	for report: Dictionary in reports:
		var lane_moves := int(report.get(&"moves", 0))
		passed = lane_moves >= MIN_POST_GATE_8_MOVES_PER_LANE and passed
		samples += int(report.get(&"samples", 0))
		moves += lane_moves
		blockers += int(report.get(&"blocking_contacts", 0))
		containment += int(report.get(&"containment_intrusions", 0))
		maximum_step = maxf(maximum_step, float(report.get(&"maximum_support_step", 0.0)))
		maximum_grade = maxf(maximum_grade, float(report.get(&"maximum_grade_degrees", 0.0)))
		minimum_normal_y = minf(minimum_normal_y, float(report.get(&"minimum_normal_y", 1.0)))
	passed = blockers == 0 and containment == 0 and passed
	print("QUARRY POST-GATE-8 PHYSICAL: gate=8 through_gate=9 lanes=%d samples=%d moves=%d minimum_moves_per_lane=%d blockers=%d containment=%d max_step=%.3fm max_grade=%.2fdeg min_normal_y=%.3f passed=%s" % [
		reports.size(), samples, moves, MIN_POST_GATE_8_MOVES_PER_LANE,
		blockers, containment, maximum_step, maximum_grade, minimum_normal_y,
		str(passed),
	])
	return passed


func _on_watchdog_timeout() -> void:
	push_error("PHYSICAL ROUTE TRAVERSABILITY WATCHDOG: stage=%s" % String(_watchdog_stage))
	get_tree().quit(2)
