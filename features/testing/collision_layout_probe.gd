extends SceneTree
## Fast deterministic geometry audit for course barriers and physical landmarks.
## This mirrors the production barrier placement without constructing terrain.

const BIKE_RADIUS := 0.31
const MINIMUM_ENVELOPE_BUFFER := 0.15
const OBSTACLE_CELL_SIZE := 24.0
const QUARRY_GATE_EIGHT_CONTROL_INDEX := 8
const MAXIMUM_QUARRY_POST_GATE_EIGHT_TURN_DEGREES := 68.0
const MAXIMUM_QUARRY_POST_GATE_EIGHT_TURN_REVERSALS := 2
const MINIMUM_QUARRY_POST_GATE_EIGHT_NONLOCAL_CLEARANCE := 48.0

var _obstacle_grid: Dictionary = {}


func _init() -> void:
	var passed := true
	for track_id: StringName in [CourseCatalog.QUARRY_ID, CourseCatalog.PINE_ID]:
		passed = _audit_layout(track_id) and passed
	quit(0 if passed else 1)


func _audit_layout(track_id: StringName) -> bool:
	var route := CourseCatalog.get_local_riding_points(track_id)
	var route_chainages := _route_chainages(route)
	var control_points := CourseCatalog.get_local_points(track_id)
	var config := CourseDressingCatalog.get_config(track_id)
	var width := CourseCatalog.get_track_width(track_id)
	var obstacles := _build_containment_obstacles(route, config, width)
	_obstacle_grid = _build_obstacle_grid(obstacles)
	var alternates := _alternate_paths(track_id, control_points)
	var main_hits := 0
	var minimum_main_clearance := INF
	var nearest_main := {}
	# Sweep the full visible track ribbon with a real bike envelope. Containment
	# intentionally occupies the outside of the recovery shoulder, but it must
	# never curl back into the authored racing surface. The old five-lane spot
	# check could miss a narrow post intrusion between its sparse samples.
	var safe_half_width := width * 0.5 - BIKE_RADIUS - MINIMUM_ENVELOPE_BUFFER
	var lane_offsets := PackedFloat32Array()
	var lateral_steps := maxi(ceili(safe_half_width * 2.0 / 0.4), 1)
	for lateral_step: int in lateral_steps + 1:
		lane_offsets.append(lerpf(-safe_half_width, safe_half_width, float(lateral_step) / float(lateral_steps)))
	for index: int in range(0, route.size(), 2):
		var tangent := CourseSpline.tangent_at(route, index)
		var right := Vector2(tangent.z, -tangent.x).normalized()
		for offset: float in lane_offsets:
			var point := Vector2(route[index].x, route[index].z) + right * offset
			var result := _nearest_obstacle(point, obstacles)
			if float(result[&"clearance"]) < minimum_main_clearance:
				minimum_main_clearance = float(result[&"clearance"])
				nearest_main = {&"index": index, &"chainage": route_chainages[index], &"offset": offset, &"name": result[&"name"], &"point": point}
			if float(result[&"clearance"]) < BIKE_RADIUS + MINIMUM_ENVELOPE_BUFFER:
				main_hits += 1
				print("LAYOUT MAIN HIT: track=%s chain_index=%d lane=%.1f obstacle=%s clearance=%.2f" % [String(track_id), index, offset, result[&"name"], result[&"clearance"]])

	var alternate_hits := 0
	var minimum_alternate_clearance := INF
	var nearest_alternate := {}
	for path_index: int in alternates.size():
		var path: PackedVector3Array = alternates[path_index]
		var chainage := 0.0
		for index: int in path.size() - 1:
			var start := path[index]
			var finish := path[index + 1]
			var length := start.distance_to(finish)
			var steps := maxi(int(ceil(length / 0.25)), 1)
			for step: int in steps + 1:
				var weight := float(step) / float(steps)
				var point_3d := start.lerp(finish, weight)
				var result := _nearest_obstacle(Vector2(point_3d.x, point_3d.z), obstacles)
				if float(result[&"clearance"]) < minimum_alternate_clearance:
					minimum_alternate_clearance = float(result[&"clearance"])
					nearest_alternate = {&"path": path_index, &"chainage": chainage + length * weight, &"name": result[&"name"], &"point": point_3d}
				if float(result[&"clearance"]) < BIKE_RADIUS + MINIMUM_ENVELOPE_BUFFER:
					alternate_hits += 1
					if alternate_hits <= 12:
						print("LAYOUT ALTERNATE HIT: track=%s alternate=%d chain=%.1f obstacle=%s clearance=%.2f point=%s" % [String(track_id), path_index, chainage + length * weight, result[&"name"], result[&"clearance"], str(point_3d)])
			chainage += length

	var props_clear := _validate_prop_clearances(track_id, route, control_points, width)
	var post_gate_eight_clear := true
	if track_id == CourseCatalog.QUARRY_ID:
		post_gate_eight_clear = _validate_quarry_post_gate_eight_route(control_points)
	var passed := main_hits == 0 and alternate_hits == 0 and props_clear and post_gate_eight_clear
	print("COLLISION LAYOUT RESULT: track=%s width=%.1f obstacles=%d main_hits=%d main_clearance=%.2fm nearest_main=%s alternate_hits=%d alternate_clearance=%.2fm nearest_alternate=%s props_clear=%s passed=%s" % [
		String(track_id), width, obstacles.size(), main_hits, minimum_main_clearance - BIKE_RADIUS,
		str(nearest_main), alternate_hits, minimum_alternate_clearance - BIKE_RADIUS, str(nearest_alternate), str(props_clear), str(passed),
	])
	return passed


func _validate_quarry_post_gate_eight_route(control_points: PackedVector3Array) -> bool:
	if control_points.size() <= QUARRY_GATE_EIGHT_CONTROL_INDEX + 2:
		print("QUARRY POST GATE 8 ROUTE: controls=%d passed=false reason=insufficient_controls" % control_points.size())
		return false

	var maximum_turn_degrees := 0.0
	var maximum_turn_control_index := -1
	var turn_reversals := 0
	var previous_turn_sign := 0.0
	for index: int in range(QUARRY_GATE_EIGHT_CONTROL_INDEX + 1, control_points.size() - 1):
		var incoming := Vector2(
			control_points[index].x - control_points[index - 1].x,
			control_points[index].z - control_points[index - 1].z
		).normalized()
		var outgoing := Vector2(
			control_points[index + 1].x - control_points[index].x,
			control_points[index + 1].z - control_points[index].z
		).normalized()
		if incoming.is_zero_approx() or outgoing.is_zero_approx():
			continue
		var signed_turn_degrees := rad_to_deg(atan2(
			incoming.x * outgoing.y - incoming.y * outgoing.x,
			incoming.dot(outgoing)
		))
		var absolute_turn_degrees := absf(signed_turn_degrees)
		if absolute_turn_degrees > maximum_turn_degrees:
			maximum_turn_degrees = absolute_turn_degrees
			maximum_turn_control_index = index
		# Tiny steering corrections do not constitute an authored direction change.
		# Alternating substantive turns are the reliable signature of the folded
		# route that previously made later ribbons read as forks after gate 8.
		if absolute_turn_degrees >= 8.0:
			var turn_sign := signf(signed_turn_degrees)
			if previous_turn_sign != 0.0 and turn_sign != previous_turn_sign:
				turn_reversals += 1
			previous_turn_sign = turn_sign

	var minimum_nonlocal_clearance := INF
	var nearest_segment_pair := Vector2i(-1, -1)
	for first_index: int in range(QUARRY_GATE_EIGHT_CONTROL_INDEX, control_points.size() - 1):
		var first_start := Vector2(control_points[first_index].x, control_points[first_index].z)
		var first_finish := Vector2(control_points[first_index + 1].x, control_points[first_index + 1].z)
		for second_index: int in range(first_index + 2, control_points.size() - 1):
			var second_start := Vector2(control_points[second_index].x, control_points[second_index].z)
			var second_finish := Vector2(control_points[second_index + 1].x, control_points[second_index + 1].z)
			var clearance := _segment_clearance(first_start, first_finish, second_start, second_finish)
			if clearance < minimum_nonlocal_clearance:
				minimum_nonlocal_clearance = clearance
				nearest_segment_pair = Vector2i(first_index, second_index)

	var passed := (
		maximum_turn_degrees <= MAXIMUM_QUARRY_POST_GATE_EIGHT_TURN_DEGREES
		and turn_reversals <= MAXIMUM_QUARRY_POST_GATE_EIGHT_TURN_REVERSALS
		and minimum_nonlocal_clearance >= MINIMUM_QUARRY_POST_GATE_EIGHT_NONLOCAL_CLEARANCE
	)
	print("QUARRY POST GATE 8 ROUTE: controls=%d maximum_turn=%.2fdeg control=%d limit=%.2fdeg turn_reversals=%d reversal_limit=%d minimum_nonlocal_clearance=%.2fm segments=%s minimum_required=%.2fm passed=%s" % [
		control_points.size(), maximum_turn_degrees, maximum_turn_control_index,
		MAXIMUM_QUARRY_POST_GATE_EIGHT_TURN_DEGREES, turn_reversals,
		MAXIMUM_QUARRY_POST_GATE_EIGHT_TURN_REVERSALS, minimum_nonlocal_clearance,
		str(nearest_segment_pair), MINIMUM_QUARRY_POST_GATE_EIGHT_NONLOCAL_CLEARANCE,
		str(passed),
	])
	return passed


func _segment_clearance(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> float:
	if Geometry2D.segment_intersects_segment(a, b, c, d) != null:
		return 0.0
	return minf(
		minf(_point_segment_clearance(a, c, d), _point_segment_clearance(b, c, d)),
		minf(_point_segment_clearance(c, a, b), _point_segment_clearance(d, a, b))
	)


func _point_segment_clearance(point: Vector2, start: Vector2, finish: Vector2) -> float:
	var segment := finish - start
	if segment.length_squared() <= 0.0001:
		return point.distance_to(start)
	var weight := clampf((point - start).dot(segment) / segment.length_squared(), 0.0, 1.0)
	return point.distance_to(start + segment * weight)


func _build_containment_obstacles(route: PackedVector3Array, config: Dictionary, width: float) -> Array[Dictionary]:
	var dressing_route := CourseDressingBuilder._decimate_polyline(route, 8.0)
	var spacing := float(config[&"barrier_spacing"])
	var length := spacing
	var offset := float(config[&"barrier_offset"])
	var thickness := float(config[&"barrier_thickness"])
	var opening_radius := float(config[&"barrier_opening_radius"])
	var openings: PackedVector3Array = config[&"barrier_openings"]
	var corridor := float(config[&"barrier_opening_corridor"])
	var opening_paths: Array = config[&"barrier_opening_paths"]
	var samples := CourseDressingBuilder._resample_polyline(dressing_route, spacing)
	var sides := PackedFloat32Array([-1.0, 1.0])
	var open_flags := PackedByteArray()
	open_flags.resize(samples.size() * 2)
	var safety_suppressed_flags := PackedByteArray()
	safety_suppressed_flags.resize(samples.size() * 2)
	var local_exclusion_samples := maxi(
		ceili(CourseDressingBuilder.BARRIER_LOCAL_EXCLUSION_METERS / spacing),
		1
	)
	var intended_route_distance := width * 0.5 + offset
	var minimum_nonlocal_distance := (
		intended_route_distance - CourseDressingBuilder.BARRIER_CROSS_ROUTE_TOLERANCE
	)
	for index: int in samples.size():
		var sample: Dictionary = samples[index]
		var center: Vector3 = sample[&"position"]
		var tangent_3d: Vector3 = sample[&"tangent"]
		var tangent := Vector2(tangent_3d.x, tangent_3d.z).normalized()
		var right := Vector2(tangent.y, -tangent.x)
		var endpoint_open := CourseDressingBuilder._is_barrier_opening(center, openings, opening_radius)
		for side_index: int in 2:
			var position_2d := Vector2(center.x, center.z) + right * sides[side_index] * (width * 0.5 + offset)
			var position := Vector3(position_2d.x, center.y, position_2d.y)
			if endpoint_open or CourseDressingBuilder._is_barrier_path_opening(position, opening_paths, corridor):
				open_flags[index * 2 + side_index] = 1
			elif CourseDressingBuilder._barrier_intrudes_nonlocal_route(
				position,
				tangent_3d,
				length,
				samples,
				index,
				local_exclusion_samples,
				minimum_nonlocal_distance
			):
				safety_suppressed_flags[index * 2 + side_index] = 1
	var obstacles: Array[Dictionary] = []
	for index: int in range(samples.size() - 1):
		var first_sample: Dictionary = samples[index]
		var second_sample: Dictionary = samples[index + 1]
		var first_center: Vector3 = first_sample[&"position"]
		var second_center: Vector3 = second_sample[&"position"]
		var first_tangent_3d: Vector3 = first_sample[&"tangent"]
		var second_tangent_3d: Vector3 = second_sample[&"tangent"]
		var first_tangent := Vector2(first_tangent_3d.x, first_tangent_3d.z).normalized()
		var second_tangent := Vector2(second_tangent_3d.x, second_tangent_3d.z).normalized()
		var first_right := Vector2(first_tangent.y, -first_tangent.x)
		var second_right := Vector2(second_tangent.y, -second_tangent.x)
		for side_index: int in 2:
			var first_flag := index * 2 + side_index
			var second_flag := (index + 1) * 2 + side_index
			if (
				open_flags[first_flag] != 0 or open_flags[second_flag] != 0
				or safety_suppressed_flags[first_flag] != 0
				or safety_suppressed_flags[second_flag] != 0
			):
				continue
			var first_position := Vector2(first_center.x, first_center.z) + first_right * sides[side_index] * intended_route_distance
			var second_position := Vector2(second_center.x, second_center.z) + second_right * sides[side_index] * intended_route_distance
			var delta := second_position - first_position
			var panel_length := delta.length()
			if panel_length < 0.2:
				continue
			var tangent := delta / panel_length
			var right := Vector2(tangent.y, -tangent.x)
			var position := first_position.lerp(second_position, 0.5)
			obstacles.append({
				&"name": "CourseContainment%s%04d" % ["Left" if sides[side_index] < 0.0 else "Right", index],
				&"position": position,
				&"tangent": tangent,
				&"right": right,
				&"half_length": panel_length * 0.5,
				&"half_width": thickness * 0.5,
			})
			var previous_open := index > 0 and open_flags[(index - 1) * 2 + side_index] != 0
			var next_open := index + 2 < samples.size() and open_flags[(index + 2) * 2 + side_index] != 0
			for end_sign: float in [-1.0, 1.0]:
				if (end_sign < 0.0 and not previous_open) or (end_sign > 0.0 and not next_open):
					continue
				var post_extent := thickness * 1.7
				var endpoint := first_position if end_sign < 0.0 else second_position
				var post_position := endpoint + tangent * end_sign * post_extent * 0.5
				if CourseDressingBuilder._barrier_intrudes_nonlocal_route(
					Vector3(post_position.x, first_center.y, post_position.y),
					Vector3(tangent.x, 0.0, tangent.y),
					post_extent,
					samples,
					index,
					local_exclusion_samples,
					minimum_nonlocal_distance
				):
					continue
				obstacles.append({
					&"name": "OpeningPost%04d" % obstacles.size(),
					&"position": post_position,
					&"tangent": tangent,
					&"right": right,
					&"half_length": thickness * 1.7 * 0.5,
					&"half_width": thickness * 1.7 * 0.5,
				})
	return obstacles


func _nearest_obstacle(point: Vector2, obstacles: Array[Dictionary]) -> Dictionary:
	var nearest := INF
	var nearest_name := "none"
	var candidate_indices: Dictionary = {}
	var cell := Vector2i(floori(point.x / OBSTACLE_CELL_SIZE), floori(point.y / OBSTACLE_CELL_SIZE))
	for x_offset: int in range(-2, 3):
		for y_offset: int in range(-2, 3):
			var key := cell + Vector2i(x_offset, y_offset)
			for obstacle_index: int in _obstacle_grid.get(key, PackedInt32Array()):
				candidate_indices[obstacle_index] = true
	var indices: Array = candidate_indices.keys()
	if indices.is_empty():
		indices.assign(range(obstacles.size()))
	for obstacle_index_variant: Variant in indices:
		var obstacle: Dictionary = obstacles[int(obstacle_index_variant)]
		var delta: Vector2 = point - (obstacle[&"position"] as Vector2)
		var along := absf(delta.dot(obstacle[&"tangent"] as Vector2)) - float(obstacle[&"half_length"])
		var across := absf(delta.dot(obstacle[&"right"] as Vector2)) - float(obstacle[&"half_width"])
		var clearance := Vector2(maxf(along, 0.0), maxf(across, 0.0)).length()
		if clearance < nearest:
			nearest = clearance
			nearest_name = String(obstacle[&"name"])
	return {&"clearance": nearest, &"name": nearest_name}


func _build_obstacle_grid(obstacles: Array[Dictionary]) -> Dictionary:
	var grid: Dictionary = {}
	for obstacle_index: int in obstacles.size():
		var position: Vector2 = obstacles[obstacle_index][&"position"]
		var key := Vector2i(
			floori(position.x / OBSTACLE_CELL_SIZE),
			floori(position.y / OBSTACLE_CELL_SIZE)
		)
		if not grid.has(key):
			grid[key] = PackedInt32Array()
		var bucket: PackedInt32Array = grid[key]
		bucket.append(obstacle_index)
		grid[key] = bucket
	return grid


func _alternate_paths(track_id: StringName, control_points: PackedVector3Array) -> Array[PackedVector3Array]:
	var controls: Array[PackedVector3Array] = []
	if track_id == CourseCatalog.PINE_ID:
		controls = [
			PackedVector3Array([Vector3(350, 26, 230), Vector3(385, 31, 195), Vector3(370, 38, 160), Vector3(320, 40, 150)]),
			PackedVector3Array([Vector3(-155, 88, 10), Vector3(-95, 98, 55), Vector3(-30, 108, 35), Vector3(10, 100, -30)]),
		]
		return [
			CourseSpline.bake_motocross(controls[0], 2.4, 1.35, 0.22, 42064),
			CourseSpline.bake_motocross(controls[1], 2.4, 1.35, 0.22, 42083),
		]
	return []


func _validate_prop_clearances(track_id: StringName, route: PackedVector3Array, control_points: PackedVector3Array, width: float) -> bool:
	var props: Array[Dictionary] = []
	var shoulder_width := 3.5 if track_id == CourseCatalog.PINE_ID else 3.75
	if track_id == CourseCatalog.PINE_ID:
		props = [
			{&"name": "Cabin", &"position": Vector2(-238, 252), &"half_size": Vector2(9, 7) * 0.5},
			{&"name": "SummitLookout", &"position": Vector2(24, -11), &"half_size": Vector2(5.5, 5.5) * 0.5},
		]
		print("PROP CLEARANCE INVARIANT: track=PINE TreeCollision center>=%.2fm collider_edge>=%.2fm track_edge=%.2fm shoulder_edge=%.2fm" % [width * 0.5 + 6.0, width * 0.5 + 6.0 - 0.48, width * 0.5, width * 0.5 + 3.5])
	else:
		props = [
			{&"name": "ExcavatorDeck", &"position": Vector2(-247, -99), &"half_size": Vector2(7.2, 3.7) * 0.5},
			{&"name": "TimingShack", &"position": Vector2(-331, 279), &"half_size": Vector2(6.5, 4) * 0.5},
			{&"name": "CrusherBase", &"position": Vector2(350, -165), &"half_size": Vector2(12, 9) * 0.5},
		]
		for index: int in range(1, control_points.size() - 1):
			if index % 4 != 0:
				continue
			var direction := (control_points[index + 1] - control_points[index - 1]).normalized()
			var right := Vector2(direction.z, -direction.x)
			var side := -1.0 if index % 2 == 0 else 1.0
			var radius := (1.25 + float(index % 3) * 0.35) * 0.82
			var point := Vector2(control_points[index].x, control_points[index].z) + right * side * (width * 0.5 + 7.0)
			props.append({&"name": "TrailLandmark%02d" % index, &"position": point, &"radius": radius})
	var passed := true
	for prop: Dictionary in props:
		var nearest := _nearest_route(route, prop[&"position"] as Vector2)
		var edge_clearance := 0.0
		var edge_chainage := float(nearest[&"chainage"])
		if prop.has(&"half_size"):
			var box_result := _nearest_route_to_box(route, prop[&"position"] as Vector2, prop[&"half_size"] as Vector2)
			edge_clearance = float(box_result[&"distance"])
			edge_chainage = float(box_result[&"chainage"])
		else:
			edge_clearance = float(nearest[&"distance"]) - float(prop[&"radius"])
		passed = passed and edge_clearance >= width * 0.5 + shoulder_width
		print("PROP CLEARANCE: track=%s node=%s chain=%.1fm center=%.2fm edge=%.2fm track_edge=%.2fm route_point=%s" % [String(track_id), prop[&"name"], nearest[&"chainage"], nearest[&"distance"], edge_clearance, width * 0.5, str(nearest[&"point"])])
		if edge_chainage != float(nearest[&"chainage"]):
			print("PROP EDGE LOCATION: track=%s node=%s edge_chain=%.1fm" % [String(track_id), prop[&"name"], edge_chainage])
	return passed


func _nearest_route(route: PackedVector3Array, point: Vector2) -> Dictionary:
	var nearest := INF
	var nearest_chainage := 0.0
	var nearest_point := Vector2.ZERO
	var chainage := 0.0
	for index: int in route.size() - 1:
		var start := Vector2(route[index].x, route[index].z)
		var finish := Vector2(route[index + 1].x, route[index + 1].z)
		var segment := finish - start
		var weight := clampf((point - start).dot(segment) / maxf(segment.length_squared(), 0.001), 0.0, 1.0)
		var distance := point.distance_to(start + segment * weight)
		if distance < nearest:
			nearest = distance
			nearest_chainage = chainage + route[index].distance_to(route[index + 1]) * weight
			nearest_point = start + segment * weight
		chainage += route[index].distance_to(route[index + 1])
	return {&"distance": nearest, &"chainage": nearest_chainage, &"point": nearest_point}


func _nearest_route_to_box(route: PackedVector3Array, center: Vector2, half_size: Vector2) -> Dictionary:
	var nearest := INF
	var nearest_chainage := 0.0
	var chainage := 0.0
	# The riding spline is spaced at roughly one metre. Quarter-metre stepping
	# gives a conservative, deterministic clearance for these large landmark boxes.
	for index: int in route.size() - 1:
		var start := Vector2(route[index].x, route[index].z)
		var finish := Vector2(route[index + 1].x, route[index + 1].z)
		var length := start.distance_to(finish)
		var steps := maxi(int(ceil(length / 0.25)), 1)
		for step: int in steps + 1:
			var weight := float(step) / float(steps)
			var point := start.lerp(finish, weight)
			var delta := (point - center).abs() - half_size
			var distance := Vector2(maxf(delta.x, 0.0), maxf(delta.y, 0.0)).length()
			if distance < nearest:
				nearest = distance
				nearest_chainage = chainage + length * weight
		chainage += route[index].distance_to(route[index + 1])
	return {&"distance": nearest, &"chainage": nearest_chainage}


func _route_chainages(route: PackedVector3Array) -> PackedFloat32Array:
	var chainages := PackedFloat32Array()
	chainages.resize(route.size())
	for index: int in range(1, route.size()):
		chainages[index] = chainages[index - 1] + route[index - 1].distance_to(route[index])
	return chainages
