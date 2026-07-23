extends Node
## Proves Quarry's packed terrain-query cache preserves the original exhaustive
## route sampling contract while materially reducing first-ride construction cost.

const QuarryBuilder = preload("res://levels/quarry/quarry_builder.gd")
const QUERY_COUNT := 2400
const TRIAL_COUNT := 3
const MINIMUM_SEGMENT_SPEEDUP := 1.15


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var builder := QuarryBuilder.new()
	builder._track_points = CourseCatalog.get_local_points(CourseCatalog.QUARRY_ID)
	builder._ride_points = CourseCatalog.get_local_riding_points(CourseCatalog.QUARRY_ID)
	builder._surface_ride_points = builder._build_surface_ride_points(builder._ride_points)
	builder._finish_apron_points = builder._build_finish_apron_points(builder._ride_points)
	builder._track_width = CourseCatalog.get_track_width(CourseCatalog.QUARRY_ID)
	var profiles: Array[Dictionary] = builder._build_terrain_surface_profiles()
	builder._terrain_surface_profiles = profiles
	var queries := _query_points(profiles)

	var cache_shape_errors := 0
	var segment_mismatches := 0
	for profile: Dictionary in profiles:
		var frames: Array[Dictionary] = profile[&"frames"]
		var query_indices: PackedInt32Array = profile[&"query_indices"]
		var cache: Dictionary = profile.get(&"query_cache", {})
		var starts: PackedVector2Array = cache.get(&"starts", PackedVector2Array())
		var deltas: PackedVector2Array = cache.get(&"deltas", PackedVector2Array())
		var length_squared: PackedFloat32Array = cache.get(
			&"length_squared", PackedFloat32Array()
		)
		var expected_size := maxi(query_indices.size() - 1, 0)
		if (
			starts.size() != expected_size
			or deltas.size() != expected_size
			or length_squared.size() != expected_size
		):
			cache_shape_errors += 1
		for point: Vector2 in queries:
			var cached := builder._nearest_terrain_query_segment(profile, point)
			var linear := builder._nearest_terrain_query_segment_linear(
				frames, query_indices, point
			)
			if cached != linear:
				segment_mismatches += 1

	var main_profile: Dictionary = profiles[0]
	var main_frames: Array[Dictionary] = main_profile[&"frames"]
	var main_indices: PackedInt32Array = main_profile[&"query_indices"]
	var segment_timings := _benchmark_segments(
		builder, main_profile, main_frames, main_indices, queries
	)

	var optimized_contexts: Array[Dictionary] = []
	for point: Vector2 in queries:
		optimized_contexts.append(builder._terrain_surface_context(point.x, point.y))
	var context_mismatches := 0
	for query_index: int in queries.size():
		var exhaustive := _exhaustive_context(builder, profiles, queries[query_index])
		if not _contexts_match(optimized_contexts[query_index], exhaustive):
			context_mismatches += 1
	var context_timings := _benchmark_contexts(builder, profiles, queries)

	var segment_speedup := float(segment_timings[&"speedup"])
	var context_speedup := float(context_timings[&"speedup"])
	var passed := (
		cache_shape_errors == 0
		and segment_mismatches == 0
		and context_mismatches == 0
		and segment_speedup >= MINIMUM_SEGMENT_SPEEDUP
	)
	print((
		"QUARRY TERRAIN CACHE: profiles=%d queries=%d cache_shape_errors=%d "
		+ "segment_mismatches=%d context_mismatches=%d linear_usec=%d cached_usec=%d "
		+ "segment_speedup=%.2fx exhaustive_context_usec=%d optimized_context_usec=%d "
		+ "context_speedup=%.2fx segment_trials=%s/%s context_trials=%s/%s passed=%s"
		) % [
			profiles.size(),
			queries.size(),
			cache_shape_errors,
			segment_mismatches,
			context_mismatches,
			int(segment_timings[&"linear_usec"]),
			int(segment_timings[&"cached_usec"]),
			segment_speedup,
			int(context_timings[&"exhaustive_usec"]),
			int(context_timings[&"optimized_usec"]),
			context_speedup,
			str(segment_timings[&"linear_trials"]),
			str(segment_timings[&"cached_trials"]),
			str(context_timings[&"exhaustive_trials"]),
			str(context_timings[&"optimized_trials"]),
			str(passed),
		]
	)
	if not passed:
		push_error("QUARRY TERRAIN CACHE: exactness or acceleration regression")
	builder.free()
	get_tree().quit(0 if passed else 1)


func _benchmark_segments(
	builder: Node,
	profile: Dictionary,
	frames: Array[Dictionary],
	query_indices: PackedInt32Array,
	queries: Array[Vector2]
) -> Dictionary:
	var linear_trials: Array[int] = []
	var cached_trials: Array[int] = []
	var speedup_trials: Array[float] = []
	var observable := 0
	for trial_index: int in TRIAL_COUNT:
		var linear: Dictionary
		var cached: Dictionary
		if trial_index % 2 == 0:
			linear = _time_linear_segments(builder, frames, query_indices, queries)
			cached = _time_cached_segments(builder, profile, queries)
		else:
			cached = _time_cached_segments(builder, profile, queries)
			linear = _time_linear_segments(builder, frames, query_indices, queries)
		observable += int(linear[&"observable"]) + int(cached[&"observable"])
		var linear_usec := int(linear[&"usec"])
		var cached_usec := int(cached[&"usec"])
		linear_trials.append(linear_usec)
		cached_trials.append(cached_usec)
		speedup_trials.append(float(linear_usec) / maxf(float(cached_usec), 1.0))
	if observable < 0:
		push_error("QUARRY TERRAIN CACHE: impossible segment accumulator")
	return {
		&"linear_usec": _median_int(linear_trials),
		&"cached_usec": _median_int(cached_trials),
		&"speedup": _median_float(speedup_trials),
		&"linear_trials": linear_trials,
		&"cached_trials": cached_trials,
	}


func _time_linear_segments(
	builder: Node,
	frames: Array[Dictionary],
	query_indices: PackedInt32Array,
	queries: Array[Vector2]
) -> Dictionary:
	var accumulator := 0
	var begin := Time.get_ticks_usec()
	for point: Vector2 in queries:
		accumulator += builder._nearest_terrain_query_segment_linear(
			frames, query_indices, point
		)
	return {&"usec": Time.get_ticks_usec() - begin, &"observable": accumulator}


func _time_cached_segments(
	builder: Node,
	profile: Dictionary,
	queries: Array[Vector2]
) -> Dictionary:
	var accumulator := 0
	var begin := Time.get_ticks_usec()
	for point: Vector2 in queries:
		accumulator += builder._nearest_terrain_query_segment(profile, point)
	return {&"usec": Time.get_ticks_usec() - begin, &"observable": accumulator}


func _benchmark_contexts(
	builder: Node,
	profiles: Array[Dictionary],
	queries: Array[Vector2]
) -> Dictionary:
	var exhaustive_trials: Array[int] = []
	var optimized_trials: Array[int] = []
	var speedup_trials: Array[float] = []
	var observable := 0
	for trial_index: int in TRIAL_COUNT:
		var exhaustive: Dictionary
		var optimized: Dictionary
		if trial_index % 2 == 0:
			exhaustive = _time_exhaustive_contexts(builder, profiles, queries)
			optimized = _time_optimized_contexts(builder, queries)
		else:
			optimized = _time_optimized_contexts(builder, queries)
			exhaustive = _time_exhaustive_contexts(builder, profiles, queries)
		observable += int(exhaustive[&"observable"]) + int(optimized[&"observable"])
		var exhaustive_usec := int(exhaustive[&"usec"])
		var optimized_usec := int(optimized[&"usec"])
		exhaustive_trials.append(exhaustive_usec)
		optimized_trials.append(optimized_usec)
		speedup_trials.append(float(exhaustive_usec) / maxf(float(optimized_usec), 1.0))
	if observable < 0:
		push_error("QUARRY TERRAIN CACHE: impossible context accumulator")
	return {
		&"exhaustive_usec": _median_int(exhaustive_trials),
		&"optimized_usec": _median_int(optimized_trials),
		&"speedup": _median_float(speedup_trials),
		&"exhaustive_trials": exhaustive_trials,
		&"optimized_trials": optimized_trials,
	}


func _time_exhaustive_contexts(
	builder: Node,
	profiles: Array[Dictionary],
	queries: Array[Vector2]
) -> Dictionary:
	var last_context: Dictionary = {}
	var begin := Time.get_ticks_usec()
	for point: Vector2 in queries:
		last_context = _exhaustive_context(builder, profiles, point)
	return {&"usec": Time.get_ticks_usec() - begin, &"observable": last_context.size()}


func _time_optimized_contexts(builder: Node, queries: Array[Vector2]) -> Dictionary:
	var last_context: Dictionary = {}
	var begin := Time.get_ticks_usec()
	for point: Vector2 in queries:
		last_context = builder._terrain_surface_context(point.x, point.y)
	return {&"usec": Time.get_ticks_usec() - begin, &"observable": last_context.size()}


func _exhaustive_context(
	builder: Node,
	profiles: Array[Dictionary],
	point: Vector2
) -> Dictionary:
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
		var influence_radius := (
			QuarryBuilder.TERRAIN_CELL_DIAGONAL
			+ float(profile[&"maximum_frame_span"])
		)
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
		if int(optimized_nearest.get(&"profile_index", -1)) != int(
			exhaustive_nearest.get(&"profile_index", -1)
		):
			return false
		for key: StringName in [&"distance", &"surface_height", &"arc_distance"]:
			if not is_equal_approx(
				float(optimized_nearest[key]), float(exhaustive_nearest[key])
			):
				return false
	var optimized_ceiling := float(optimized.get(&"clearance_ceiling", INF))
	var exhaustive_ceiling := float(exhaustive.get(&"clearance_ceiling", INF))
	return (
		(is_inf(optimized_ceiling) and is_inf(exhaustive_ceiling))
		or is_equal_approx(optimized_ceiling, exhaustive_ceiling)
	)


func _query_points(profiles: Array[Dictionary]) -> Array[Vector2]:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x0A771E
	var queries: Array[Vector2] = []
	for query_index: int in QUERY_COUNT:
		if query_index % 3 == 0:
			var profile: Dictionary = profiles[query_index % profiles.size()]
			var frames: Array[Dictionary] = profile[&"frames"]
			var frame: Dictionary = frames[(query_index * 17) % frames.size()]
			var position: Vector3 = frame[&"position"]
			var right: Vector3 = frame[&"right"]
			var offset := rng.randf_range(-72.0, 72.0)
			queries.append(Vector2(
				position.x + right.x * offset,
				position.z + right.z * offset
			))
		else:
			queries.append(Vector2(
				rng.randf_range(-QuarryBuilder.TERRAIN_SIZE.x * 0.5, QuarryBuilder.TERRAIN_SIZE.x * 0.5),
				rng.randf_range(-QuarryBuilder.TERRAIN_SIZE.y * 0.5, QuarryBuilder.TERRAIN_SIZE.y * 0.5)
			))
	return queries


func _median_int(values: Array[int]) -> int:
	var ordered := values.duplicate()
	ordered.sort()
	return ordered[floori(float(ordered.size()) * 0.5)]


func _median_float(values: Array[float]) -> float:
	var ordered := values.duplicate()
	ordered.sort()
	return ordered[floori(float(ordered.size()) * 0.5)]
