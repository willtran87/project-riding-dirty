extends Node
## Deterministic geometry regression for obstacle cadence on both main courses.


func _ready() -> void:
	var passed := _verify_quarry_post_gate_8()
	for track_id: StringName in [CourseCatalog.QUARRY_ID, CourseCatalog.PINE_ID]:
		var points := CourseCatalog.get_local_riding_points(track_id)
		var peak_count := 0
		var strong_peak_count := 0
		var maximum_relief := 0.0
		var last_peak_index := -10
		for index: int in range(4, points.size() - 4):
			var baseline := (points[index - 3].y + points[index + 3].y) * 0.5
			var relief := points[index].y - baseline
			var previous_baseline := (points[index - 4].y + points[index + 2].y) * 0.5
			var next_baseline := (points[index - 2].y + points[index + 4].y) * 0.5
			var previous_relief := points[index - 1].y - previous_baseline
			var next_relief := points[index + 1].y - next_baseline
			maximum_relief = maxf(maximum_relief, relief)
			if relief > 0.09 and relief >= previous_relief and relief > next_relief and index - last_peak_index >= 3:
				peak_count += 1
				last_peak_index = index
				if relief > 0.24:
					strong_peak_count += 1
		# Quarry's seven welded jump packages deliberately replace the former
		# stacked micro-relief. Keep the texture-density guard meaningful without
		# requiring a second surface layer over the race ribbon.
		var minimum_peaks := 105 if track_id == CourseCatalog.PINE_ID else 65
		var minimum_strong_peaks := 35 if track_id == CourseCatalog.PINE_ID else 28
		var track_passed := peak_count >= minimum_peaks and strong_peak_count >= minimum_strong_peaks and maximum_relief >= 0.5
		passed = passed and track_passed
		print("COURSE RHYTHM PROBE %s: samples=%d peaks=%d strong=%d max_relief=%.2fm passed=%s" % [str(track_id), points.size(), peak_count, strong_peak_count, maximum_relief, str(track_passed)])
	get_tree().quit(0 if passed else 1)


func _verify_quarry_post_gate_8() -> bool:
	const GATE_8_CONTROL_INDEX := 8
	const MAXIMUM_TURN_DEGREES := 55.0
	const MINIMUM_BAKED_RADIUS_METERS := 28.0
	const MAXIMUM_GATE_8_BLIND_RELIEF_METERS := 0.55
	const MAXIMUM_GATE_8_ENTRY_TANGENT_RELIEF_METERS := 0.75
	const GATE_8_SIGHTLINE_DISTANCE_METERS := 100.0
	var points := CourseCatalog.get_local_points(CourseCatalog.QUARRY_ID)
	var expected_segments := points.size() - GATE_8_CONTROL_INDEX - 1
	var forward_segments := 0
	var downhill_segments := 0
	var maximum_turn_degrees := 0.0
	for index: int in range(GATE_8_CONTROL_INDEX, points.size() - 1):
		var segment := points[index + 1] - points[index]
		if segment.z > 1.0:
			forward_segments += 1
		if segment.y <= 0.001:
			downhill_segments += 1
	# Include the incoming Gate 7 -> Gate 8 vector so the first post-gate turn is
	# constrained along with every later bend.
	for index: int in range(GATE_8_CONTROL_INDEX - 1, points.size() - 2):
		var incoming := points[index + 1] - points[index]
		var outgoing := points[index + 2] - points[index + 1]
		incoming.y = 0.0
		outgoing.y = 0.0
		if incoming.length_squared() <= 0.001 or outgoing.length_squared() <= 0.001:
			continue
		var turn_degrees := rad_to_deg(acos(clampf(
			incoming.normalized().dot(outgoing.normalized()), -1.0, 1.0
		)))
		maximum_turn_degrees = maxf(maximum_turn_degrees, turn_degrees)
	var radius_result := _minimum_post_gate_8_baked_radius(points[GATE_8_CONTROL_INDEX])
	var minimum_baked_radius: float = radius_result[&"radius"]
	var gate_8_relief_result := _maximum_relief_between_anchors(
		points[GATE_8_CONTROL_INDEX], points[GATE_8_CONTROL_INDEX + 1]
	)
	var maximum_gate_8_relief: float = gate_8_relief_result[&"relief"]
	# The endpoint chord alone missed the actual failure: the road could match the
	# Gate 8 -> 9 chord while still rising several metres above the rider's steep
	# incoming tangent. Guard the chase-camera sightline through the first 100 m.
	var entry_tangent_result := _maximum_relief_above_incoming_tangent(
		points[GATE_8_CONTROL_INDEX], GATE_8_SIGHTLINE_DISTANCE_METERS
	)
	var maximum_entry_tangent_relief: float = entry_tangent_result[&"relief"]
	var route_passed := (
		forward_segments == expected_segments
		and downhill_segments == expected_segments
		and maximum_turn_degrees <= MAXIMUM_TURN_DEGREES
		and minimum_baked_radius >= MINIMUM_BAKED_RADIUS_METERS
		and maximum_gate_8_relief <= MAXIMUM_GATE_8_BLIND_RELIEF_METERS
		and maximum_entry_tangent_relief <= MAXIMUM_GATE_8_ENTRY_TANGENT_RELIEF_METERS
	)
	print(
		"QUARRY POST-GATE8 LEGIBILITY: segments=%d forward=%d downhill=%d max_turn=%.1fdeg min_baked_radius=%.2fm radius_index=%d gate8_blind_relief=%.3fm relief_index=%d entry_tangent_relief=%.3fm tangent_index=%d incoming_grade=%.3f passed=%s"
		% [
			expected_segments, forward_segments, downhill_segments, maximum_turn_degrees,
			minimum_baked_radius, int(radius_result[&"index"]), maximum_gate_8_relief,
			int(gate_8_relief_result[&"index"]), maximum_entry_tangent_relief,
			int(entry_tangent_result[&"index"]), float(entry_tangent_result[&"incoming_grade"]),
			str(route_passed),
		]
	)
	return route_passed


func _minimum_post_gate_8_baked_radius(gate_8: Vector3) -> Dictionary:
	const SAMPLE_WINDOW := 4
	var route := CourseCatalog.get_local_riding_points(CourseCatalog.QUARRY_ID)
	var gate_8_index := CourseSpline.closest_index(route, gate_8)
	var minimum_radius := INF
	var minimum_index := -1
	for index: int in range(gate_8_index + SAMPLE_WINDOW, route.size() - SAMPLE_WINDOW):
		var a := Vector2(route[index - SAMPLE_WINDOW].x, route[index - SAMPLE_WINDOW].z)
		var b := Vector2(route[index].x, route[index].z)
		var c := Vector2(route[index + SAMPLE_WINDOW].x, route[index + SAMPLE_WINDOW].z)
		var twice_area := absf((b - a).cross(c - a))
		if twice_area <= 0.001:
			continue
		var radius := a.distance_to(b) * b.distance_to(c) * c.distance_to(a) / (2.0 * twice_area)
		if radius < minimum_radius:
			minimum_radius = radius
			minimum_index = index
	return {&"radius": minimum_radius, &"index": minimum_index}


func _maximum_relief_between_anchors(start_anchor: Vector3, end_anchor: Vector3) -> Dictionary:
	var route := CourseCatalog.get_local_riding_points(CourseCatalog.QUARRY_ID)
	var start_index := CourseSpline.closest_index(route, start_anchor)
	var end_index := CourseSpline.closest_index(route, end_anchor)
	var total_distance := 0.0
	for index: int in range(start_index + 1, end_index + 1):
		total_distance += route[index - 1].distance_to(route[index])
	var travelled := 0.0
	var maximum_relief := -INF
	var maximum_index := start_index
	for index: int in range(start_index, end_index + 1):
		if index > start_index:
			travelled += route[index - 1].distance_to(route[index])
		var weight := travelled / maxf(total_distance, 0.001)
		var baseline_y := lerpf(start_anchor.y, end_anchor.y, weight)
		var relief := route[index].y - baseline_y
		if relief > maximum_relief:
			maximum_relief = relief
			maximum_index = index
	return {&"relief": maximum_relief, &"index": maximum_index}


func _maximum_relief_above_incoming_tangent(gate_anchor: Vector3, lookahead_distance: float) -> Dictionary:
	const TANGENT_LOOKBACK_METERS := 24.0
	var route := CourseCatalog.get_local_riding_points(CourseCatalog.QUARRY_ID)
	var gate_index := CourseSpline.closest_index(route, gate_anchor)
	var lookback_index := gate_index
	var lookback_distance := 0.0
	while lookback_index > 0 and lookback_distance < TANGENT_LOOKBACK_METERS:
		var current := route[lookback_index]
		var previous := route[lookback_index - 1]
		lookback_distance += Vector2(current.x, current.z).distance_to(Vector2(previous.x, previous.z))
		lookback_index -= 1
	var incoming_grade := (
		(route[gate_index].y - route[lookback_index].y)
		/ maxf(lookback_distance, 0.001)
	)
	var travelled := 0.0
	var maximum_relief := 0.0
	var maximum_index := gate_index
	for index: int in range(gate_index + 1, route.size()):
		var previous := route[index - 1]
		var current := route[index]
		travelled += Vector2(previous.x, previous.z).distance_to(Vector2(current.x, current.z))
		if travelled > lookahead_distance:
			break
		var tangent_height := route[gate_index].y + incoming_grade * travelled
		var relief := current.y - tangent_height
		if relief > maximum_relief:
			maximum_relief = relief
			maximum_index = index
	return {
		&"relief": maximum_relief,
		&"index": maximum_index,
		&"incoming_grade": incoming_grade,
	}
