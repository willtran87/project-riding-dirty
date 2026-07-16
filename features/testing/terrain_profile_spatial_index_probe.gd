extends Node
## Verifies that Pine Ridge's terrain-profile grid selects the same coarse
## segment as the original full scan while materially reducing query cost.

const PineBuilder = preload("res://levels/pine_ridge/pine_ridge_builder.gd")
const QUERY_COUNT := 2400
const REPEAT_COUNT := 3


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var builder := PineBuilder.new()
	builder._ride_points = CourseCatalog.get_local_riding_points(CourseCatalog.PINE_ID)
	for alternate_index: int in builder._alternate_trails.size():
		builder._alternate_ride_trails.append(CourseSpline.bake_motocross(
			builder._alternate_trails[alternate_index],
			2.4,
			1.35,
			0.22,
			42017 + 47 + alternate_index * 19
		))
	var profiles: Array[Dictionary] = builder._build_terrain_surface_profiles()
	builder._terrain_surface_profiles = profiles
	var queries := _query_points(profiles)
	var mismatches := 0
	for profile: Dictionary in profiles:
		var frames: Array[Dictionary] = profile[&"frames"]
		var query_indices: PackedInt32Array = profile[&"query_indices"]
		for point: Vector2 in queries:
			var indexed := builder._nearest_terrain_query_segment(profile, point)
			var linear := builder._nearest_terrain_query_segment_linear(frames, query_indices, point)
			if indexed != linear:
				mismatches += 1

	var main_profile: Dictionary = profiles[0]
	var main_frames: Array[Dictionary] = main_profile[&"frames"]
	var main_indices: PackedInt32Array = main_profile[&"query_indices"]
	var accumulator := 0
	var linear_begin := Time.get_ticks_usec()
	for _repeat: int in REPEAT_COUNT:
		for point: Vector2 in queries:
			accumulator += builder._nearest_terrain_query_segment_linear(
				main_frames, main_indices, point
			)
	var linear_usec := Time.get_ticks_usec() - linear_begin
	var indexed_begin := Time.get_ticks_usec()
	for _repeat: int in REPEAT_COUNT:
		for point: Vector2 in queries:
			accumulator += builder._nearest_terrain_query_segment(main_profile, point)
	var indexed_usec := Time.get_ticks_usec() - indexed_begin
	var optimized_contexts: Array[Dictionary] = []
	var optimized_context_begin := Time.get_ticks_usec()
	for point: Vector2 in queries:
		optimized_contexts.append(builder._terrain_surface_context(point.x, point.y))
	var optimized_context_usec := Time.get_ticks_usec() - optimized_context_begin
	var context_mismatches := 0
	var exhaustive_context_begin := Time.get_ticks_usec()
	for query_index: int in queries.size():
		var exhaustive := _exhaustive_context(builder, profiles, queries[query_index])
		if not _contexts_match(optimized_contexts[query_index], exhaustive):
			context_mismatches += 1
	var exhaustive_context_usec := Time.get_ticks_usec() - exhaustive_context_begin
	var speedup := float(linear_usec) / maxf(float(indexed_usec), 1.0)
	var context_speedup := (
		float(exhaustive_context_usec) / maxf(float(optimized_context_usec), 1.0)
	)
	var passed := (
		mismatches == 0
		and context_mismatches == 0
		and indexed_usec < linear_usec
		and optimized_context_usec < exhaustive_context_usec
	)
	print((
		"TERRAIN PROFILE INDEX: profiles=%d queries=%d segment_mismatches=%d "
		+ "context_mismatches=%d linear_usec=%d indexed_usec=%d speedup=%.2fx "
		+ "exhaustive_context_usec=%d optimized_context_usec=%d context_speedup=%.2fx passed=%s"
		) % [
			profiles.size(),
			queries.size(),
			mismatches,
			context_mismatches,
			linear_usec,
			indexed_usec,
			speedup,
			exhaustive_context_usec,
			optimized_context_usec,
			context_speedup,
			str(passed),
		]
	)
	if accumulator < 0:
		push_error("TERRAIN PROFILE INDEX: impossible accumulator")
	if not passed:
		push_error("TERRAIN PROFILE INDEX: exactness or acceleration regression")
	builder.free()
	get_tree().quit(0 if passed else 1)


func _exhaustive_context(
	builder: Node,
	profiles: Array[Dictionary],
	point: Vector2
) -> Dictionary:
	# This is the pre-optimization contract: every profile is sampled before the
	# nearest ribbon and clearance ceiling are selected. It is intentionally kept
	# in the probe as an independent reference implementation.
	var nearest: Dictionary = {}
	var nearest_distance := INF
	var clearance_ceiling := INF
	for profile_index: int in profiles.size():
		var profile: Dictionary = profiles[profile_index]
		var sample: Dictionary = builder._nearest_terrain_profile_sample(profile, point)
		if sample.is_empty():
			continue
		var distance: float = sample[&"distance"]
		if distance < nearest_distance:
			nearest_distance = distance
			sample[&"profile_index"] = profile_index
			nearest = sample
		var frame_padding: float = profile[&"maximum_frame_span"]
		var influence_radius := PineBuilder.TERRAIN_CELL_DIAGONAL + frame_padding
		if float(sample[&"edge_distance"]) <= influence_radius:
			clearance_ceiling = minf(
				clearance_ceiling,
				builder._terrain_profile_clearance_ceiling(
					profile, sample, point, influence_radius
				)
			)
	return {&"nearest": nearest, &"clearance_ceiling": clearance_ceiling}


func _contexts_match(optimized: Dictionary, exhaustive: Dictionary) -> bool:
	var optimized_nearest: Dictionary = optimized.get(&"nearest", {})
	var exhaustive_nearest: Dictionary = exhaustive.get(&"nearest", {})
	if optimized_nearest.is_empty() != exhaustive_nearest.is_empty():
		return false
	if not optimized_nearest.is_empty():
		if int(optimized_nearest.get(&"profile_index", -1)) != int(exhaustive_nearest.get(&"profile_index", -1)):
			return false
		if not is_equal_approx(
			float(optimized_nearest[&"distance"]),
			float(exhaustive_nearest[&"distance"])
		):
			return false
		if not is_equal_approx(
			float(optimized_nearest[&"surface_height"]),
			float(exhaustive_nearest[&"surface_height"])
		):
			return false
	var optimized_ceiling := float(optimized.get(&"clearance_ceiling", INF))
	var exhaustive_ceiling := float(exhaustive.get(&"clearance_ceiling", INF))
	return (
		(is_inf(optimized_ceiling) and is_inf(exhaustive_ceiling))
		or is_equal_approx(optimized_ceiling, exhaustive_ceiling)
	)


func _query_points(profiles: Array[Dictionary]) -> Array[Vector2]:
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for profile: Dictionary in profiles:
		var frames: Array[Dictionary] = profile[&"frames"]
		for frame: Dictionary in frames:
			var position: Vector3 = frame[&"position"]
			minimum.x = minf(minimum.x, position.x)
			minimum.y = minf(minimum.y, position.z)
			maximum.x = maxf(maximum.x, position.x)
			maximum.y = maxf(maximum.y, position.z)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x51AEE
	var queries: Array[Vector2] = []
	for query_index: int in QUERY_COUNT:
		if query_index % 4 == 0:
			var profile: Dictionary = profiles[query_index % profiles.size()]
			var frames: Array[Dictionary] = profile[&"frames"]
			var frame: Dictionary = frames[(query_index * 17) % frames.size()]
			var position: Vector3 = frame[&"position"]
			var right: Vector3 = frame[&"right"]
			var offset := rng.randf_range(-96.0, 96.0)
			queries.append(Vector2(position.x + right.x * offset, position.z + right.z * offset))
		else:
			queries.append(Vector2(
				rng.randf_range(minimum.x - 180.0, maximum.x + 180.0),
				rng.randf_range(minimum.y - 180.0, maximum.y + 180.0)
			))
	return queries
