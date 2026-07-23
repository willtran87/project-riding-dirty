extends Node
## Proves the course-dressing segment grid is an exact bounded-query
## acceleration, not an approximation that can move or remove authored props.

const QUERY_COUNT := 900
const REPEAT_COUNT := 3
const TRACK_IDS: Array[StringName] = [CourseCatalog.QUARRY_ID, CourseCatalog.PINE_ID]


func _ready() -> void:
	var passed := true
	for track_id: StringName in TRACK_IDS:
		var route := CourseDressingBuilder._decimate_polyline(
			CourseCatalog.get_world_riding_points(track_id), 8.0
		)
		var index := CourseDressingBuilder._build_polyline_spatial_index(route)
		var queries := _query_points(route, track_id)
		var exact := _validate_exact_queries(route, index, queries)
		var timings := _benchmark_queries(route, index, queries)
		var track_passed := (
			bool(exact[&"passed"])
			and int(timings[&"indexed_usec"]) < int(timings[&"brute_usec"])
		)
		print("COURSE SPATIAL INDEX: track=%s segments=%d queries=%d mismatches=%d brute_usec=%d indexed_usec=%d speedup=%.2fx passed=%s" % [
			String(track_id),
			maxi(route.size() - 1, 0),
			queries.size(),
			int(exact[&"mismatches"]),
			int(timings[&"brute_usec"]),
			int(timings[&"indexed_usec"]),
			float(timings[&"speedup"]),
			str(track_passed),
		])
		passed = passed and track_passed
	print("COURSE SPATIAL INDEX RESULT: passed=%s" % str(passed))
	if not passed:
		push_error("COURSE SPATIAL INDEX: bounded query changed an exact distance or failed to accelerate it.")
	get_tree().quit(0 if passed else 1)


func _query_points(route: PackedVector3Array, track_id: StringName) -> Array[Dictionary]:
	var queries: Array[Dictionary] = []
	if route.is_empty():
		return queries
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for point: Vector3 in route:
		minimum.x = minf(minimum.x, point.x)
		minimum.y = minf(minimum.y, point.z)
		maximum.x = maxf(maximum.x, point.x)
		maximum.y = maxf(maximum.y, point.z)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x71A0 + (17 if track_id == CourseCatalog.PINE_ID else 3)
	var radii := PackedFloat32Array([19.0, 34.0, 145.0])
	for query_index: int in QUERY_COUNT:
		var margin := 170.0
		queries.append({
			&"point": Vector3(
				rng.randf_range(minimum.x - margin, maximum.x + margin),
				0.0,
				rng.randf_range(minimum.y - margin, maximum.y + margin)
			),
			&"radius": radii[query_index % radii.size()],
		})
	return queries


func _validate_exact_queries(
	route: PackedVector3Array,
	index: Dictionary,
	queries: Array[Dictionary]
) -> Dictionary:
	var mismatches := 0
	for query: Dictionary in queries:
		var point: Vector3 = query[&"point"]
		var radius := float(query[&"radius"])
		var brute := CourseDressingBuilder._distance_to_polyline(point, route)
		var indexed := CourseDressingBuilder._distance_to_polyline_bounded(point, index, radius)
		var expected_outside := brute > radius
		var actual_outside := is_inf(indexed)
		if expected_outside != actual_outside:
			mismatches += 1
		elif not expected_outside and absf(indexed - brute) > 0.0001:
			mismatches += 1
	return {&"mismatches": mismatches, &"passed": mismatches == 0}


func _benchmark_queries(
	route: PackedVector3Array,
	index: Dictionary,
	queries: Array[Dictionary]
) -> Dictionary:
	var accumulator := 0.0
	var brute_begin := Time.get_ticks_usec()
	for _repeat: int in REPEAT_COUNT:
		for query: Dictionary in queries:
			accumulator += CourseDressingBuilder._distance_to_polyline(query[&"point"], route)
	var brute_usec := Time.get_ticks_usec() - brute_begin
	var indexed_begin := Time.get_ticks_usec()
	for _repeat: int in REPEAT_COUNT:
		for query: Dictionary in queries:
			var distance := CourseDressingBuilder._distance_to_polyline_bounded(
				query[&"point"], index, float(query[&"radius"])
			)
			accumulator += 0.0 if is_inf(distance) else distance
	var indexed_usec := Time.get_ticks_usec() - indexed_begin
	# Keep the benchmark loops observable to the script runtime.
	if accumulator < 0.0:
		push_error("COURSE SPATIAL INDEX: impossible accumulator")
	return {
		&"brute_usec": brute_usec,
		&"indexed_usec": indexed_usec,
		&"speedup": float(brute_usec) / maxf(float(indexed_usec), 1.0),
	}
