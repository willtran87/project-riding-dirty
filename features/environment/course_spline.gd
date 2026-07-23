extends RefCounted
class_name CourseSpline
## Deterministic Catmull-Rom course baking with restrained motocross rhythm.
## The baked line passes through every authored checkpoint while replacing long
## straight chords with a continuous, densely sampled riding line.


static func bake_motocross(
	control_points: PackedVector3Array,
	spacing: float = 3.0,
	lateral_sway: float = 3.0,
	roller_height: float = 0.4,
	seed: int = 1,
	rhythm_profile: Dictionary = {}
) -> PackedVector3Array:
	if control_points.size() < 2:
		return control_points.duplicate()

	var baked := PackedVector3Array()
	var accumulated_distance := 0.0
	var safe_spacing := maxf(spacing, 1.0)
	var phase := fmod(float(abs(seed)) * 0.0174533, TAU)
	var rhythm_zones: Array = rhythm_profile.get(&"zones", [])
	var relief_suppression_zones: Array = rhythm_profile.get(&"relief_suppression_zones", [])
	var jump_zones: Array = rhythm_profile.get(&"jump_zones", [])
	var closed_loop := (
		control_points.size() >= 4
		and control_points[0].distance_to(control_points[-1]) <= 0.02
	)
	for segment_index: int in range(control_points.size() - 1):
		var p0 := control_points[maxi(segment_index - 1, 0)]
		var p1 := control_points[segment_index]
		var p2 := control_points[segment_index + 1]
		var chord_length := p1.distance_to(p2)
		var p3 := control_points[mini(segment_index + 2, control_points.size() - 1)]
		if closed_loop and segment_index == control_points.size() - 2:
			# Preserve the straight, stable launch chute while steering only the final
			# authored segment into that same heading. Catmull's endpoint derivative
			# is 0.5 * (p3 - p1), so this virtual neighbour makes the incoming finish
			# tangent parallel to the opening chord without moving either checkpoint.
			var opening_direction := (control_points[1] - control_points[0]).normalized()
			p3 = p1 + opening_direction * chord_length * 2.0
		var subdivisions := maxi(int(ceil(chord_length / safe_spacing)), 2)
		for sample_index: int in range(subdivisions + 1):
			if segment_index > 0 and sample_index == 0:
				continue
			var weight := float(sample_index) / float(subdivisions)
			var curved_position := _catmull_rom(p0, p1, p2, p3, weight)
			var launch_blend := smoothstep(0.38, 0.82, weight) if segment_index == 0 else 1.0
			# A motocross gate needs a readable launch chute. Keep the opening
			# linear long enough for a neutral full-throttle start, then ease into
			# the spline before the first authored corner.
			var position := p1.lerp(p2, weight).lerp(curved_position, launch_blend)
			# Fade procedural shape to zero at every authored point. Checkpoints,
			# landmark placement, and route timing therefore keep exact anchors.
			var envelope := pow(sin(weight * PI), 2.0)
			var curved_tangent := _catmull_tangent(p0, p1, p2, p3, weight)
			var tangent := (p2 - p1).normalized().lerp(curved_tangent, launch_blend).normalized()
			var flat_tangent := Vector3(tangent.x, 0.0, tangent.z)
			if flat_tangent.length_squared() < 0.01:
				flat_tangent = Vector3(p2.x - p1.x, 0.0, p2.z - p1.z)
			flat_tangent = flat_tangent.normalized()
			var right := flat_tangent.cross(Vector3.UP).normalized()
			var local_distance := chord_length * weight
			var course_distance := accumulated_distance + local_distance
			var segment_phase := phase + float(segment_index) * 1.731
			var launch_shape_scale := smoothstep(0.2, 0.55, weight) if segment_index == 0 else 1.0
			var sway := (
				sin(weight * TAU + segment_phase) * 0.68
				+ sin(weight * PI * 3.0 - segment_phase * 0.41) * 0.32
			) * lateral_sway * envelope * launch_shape_scale
			position += right * sway

			var rolling_wave := (
				sin(course_distance * 0.245 + segment_phase) * 0.54
				+ sin(course_distance * 0.425 - segment_phase * 0.73) * 0.22
			)
			var takeoff_wave := pow(maxf(sin(course_distance * 0.118 + segment_phase * 0.57), 0.0), 5.0) * 0.72
			# Named chainage zones create composed obstacle clusters. Each cluster
			# tapers its first and final crest, leaving deliberate recovery space
			# between whoops, rollers, braking bumps, and the major jump pairs.
			var rhythm_wave := 0.0
			for zone_value: Variant in rhythm_zones:
				var zone := zone_value as Dictionary
				var zone_start := float(zone.get(&"start", 0.0))
				var zone_length := maxf(float(zone.get(&"length", 0.0)), 0.0)
				var zone_distance := course_distance - zone_start
				if zone_distance < 0.0 or zone_distance > zone_length:
					continue
				var wavelength := maxf(float(zone.get(&"spacing", 8.0)), 3.0)
				var height := float(zone.get(&"height", 0.3))
				var sharpness := float(zone.get(&"sharpness", 2.0))
				var edge_length := minf(wavelength * 1.35, zone_length * 0.32)
				var zone_envelope := smoothstep(0.0, edge_length, zone_distance) * smoothstep(0.0, edge_length, zone_length - zone_distance)
				var crest := pow(maxf(sin(zone_distance * TAU / wavelength), 0.0), sharpness)
				rhythm_wave += crest * height * zone_envelope
			# Explicit jump packages and checkpoint approaches need a readable base
			# grade beneath them. Suppression zones feather procedural relief down
			# without changing the authored spline or producing a hard height seam.
			var relief_scale := 1.0
			for suppression_value: Variant in relief_suppression_zones:
				var suppression := suppression_value as Dictionary
				var suppression_start := float(suppression.get(&"start", 0.0))
				var suppression_length := maxf(float(suppression.get(&"length", 0.0)), 0.0)
				var suppression_distance := course_distance - suppression_start
				if suppression_distance < 0.0 or suppression_distance > suppression_length:
					continue
				var fade := clampf(
					float(suppression.get(&"fade", 10.0)),
					0.001,
					maxf(suppression_length * 0.5, 0.001)
				)
				var suppression_blend := minf(
					smoothstep(0.0, fade, suppression_distance),
					smoothstep(0.0, fade, suppression_length - suppression_distance)
				)
				var target_scale := clampf(float(suppression.get(&"scale", 0.0)), 0.0, 1.0)
				relief_scale = minf(relief_scale, lerpf(1.0, target_scale, suppression_blend))
			# Major race-line jumps belong to this same centerline. The former Quarry
			# implementation stacked separate, nearly full-width bodies over the road;
			# those bodies hid the continuing ribbon and let collision, opponents, and
			# scenery disagree about which surface was authoritative. A welded package
			# retains a definite lip and receiver while every consumer shares one path.
			var jump_relief := 0.0
			for jump_value: Variant in jump_zones:
				jump_relief += _jump_zone_relief(course_distance, jump_value as Dictionary)
			var procedural_relief := (
				((rolling_wave + takeoff_wave) * roller_height * envelope + rhythm_wave) * relief_scale
				+ jump_relief
			)
			position.y += procedural_relief * launch_shape_scale
			baked.append(position)
		accumulated_distance += chord_length

	# Avoid tiny floating-point offsets at the endpoints; these positions are
	# also used to place the start bike and final gate.
	baked[0] = control_points[0]
	baked[baked.size() - 1] = control_points[control_points.size() - 1]
	return baked


static func closest_index(points: PackedVector3Array, target: Vector3) -> int:
	if points.is_empty():
		return -1
	var closest := 0
	var closest_distance := INF
	var target_2d := Vector2(target.x, target.z)
	for index: int in points.size():
		var point_2d := Vector2(points[index].x, points[index].z)
		var distance := point_2d.distance_squared_to(target_2d)
		if distance < closest_distance:
			closest_distance = distance
			closest = index
	return closest


static func project_route(
	points: PackedVector3Array,
	target: Vector3,
	cumulative_distances: PackedFloat32Array = PackedFloat32Array(),
	hint_segment: int = -1,
	search_window: int = 48,
	closed: bool = false
) -> Dictionary:
	## Projects a world point onto a route segment and returns continuous chainage.
	## A prior segment hint prevents nearby switchbacks from stealing progress.
	if points.size() < 2:
		return {}
	var distances := cumulative_distances
	if distances.size() != points.size():
		distances = PackedFloat32Array()
		distances.resize(points.size())
		for index: int in range(1, points.size()):
			distances[index] = distances[index - 1] + points[index - 1].distance_to(points[index])
	var segment_count := points.size() - 1
	var candidates := PackedInt32Array()
	if hint_segment < 0 or search_window <= 0 or search_window * 2 + 1 >= segment_count:
		candidates.resize(segment_count)
		for index: int in segment_count:
			candidates[index] = index
	else:
		var seen: Dictionary[int, bool] = {}
		for offset: int in range(-search_window, search_window + 1):
			var index := hint_segment + offset
			if closed:
				index = posmod(index, segment_count)
			elif index < 0 or index >= segment_count:
				continue
			if not seen.has(index):
				seen[index] = true
				candidates.append(index)
	var target_2d := Vector2(target.x, target.z)
	var best_segment := 0
	var best_fraction := 0.0
	var best_distance_squared := INF
	for segment: int in candidates:
		var start_2d := Vector2(points[segment].x, points[segment].z)
		var end_2d := Vector2(points[segment + 1].x, points[segment + 1].z)
		var delta_2d := end_2d - start_2d
		var denominator := delta_2d.length_squared()
		var fraction := clampf((target_2d - start_2d).dot(delta_2d) / denominator, 0.0, 1.0) if denominator > 0.000001 else 0.0
		var projected_2d := start_2d + delta_2d * fraction
		var distance_squared := projected_2d.distance_squared_to(target_2d)
		if distance_squared < best_distance_squared:
			best_distance_squared = distance_squared
			best_segment = segment
			best_fraction = fraction
	var start := points[best_segment]
	var finish := points[best_segment + 1]
	var position := start.lerp(finish, best_fraction)
	var tangent := (finish - start).normalized()
	var flat_tangent := Vector3(tangent.x, 0.0, tangent.z).normalized()
	if flat_tangent.length_squared() < 0.01:
		flat_tangent = Vector3.FORWARD
	var right := flat_tangent.cross(Vector3.UP).normalized()
	var lateral := (target - position).dot(right)
	var segment_length := start.distance_to(finish)
	return {
		&"segment": best_segment,
		&"fraction": best_fraction,
		&"chainage": distances[best_segment] + segment_length * best_fraction,
		&"position": position,
		&"tangent": tangent,
		&"right": right,
		&"lateral": lateral,
		&"distance": sqrt(best_distance_squared),
	}


static func tangent_at(points: PackedVector3Array, index: int) -> Vector3:
	if points.size() < 2:
		return Vector3.FORWARD
	var previous := points[maxi(index - 2, 0)]
	var following := points[mini(index + 2, points.size() - 1)]
	var tangent := following - previous
	return tangent.normalized() if tangent.length_squared() > 0.001 else Vector3.FORWARD


static func _jump_zone_relief(course_distance: float, zone: Dictionary) -> float:
	var takeoff_start := float(zone.get(&"start", 0.0))
	var takeoff_length := maxf(float(zone.get(&"takeoff_length", 0.0)), 0.001)
	var takeoff_height := maxf(float(zone.get(&"takeoff_height", 0.0)), 0.0)
	var fallaway_length := maxf(float(zone.get(&"fallaway_length", 0.0)), 0.001)
	var receiver_start := float(zone.get(&"receiver_start", takeoff_start + takeoff_length + fallaway_length))
	var receiver_length := maxf(float(zone.get(&"receiver_length", 0.0)), 0.001)
	var receiver_height := maxf(float(zone.get(&"receiver_height", 0.0)), 0.0)
	var receiver_crest := clampf(float(zone.get(&"receiver_crest", 0.4)), 0.2, 0.7)
	var relief := 0.0

	var takeoff_distance := course_distance - takeoff_start
	if takeoff_distance >= 0.0 and takeoff_distance <= takeoff_length:
		# An ease-in power curve keeps the entry flush but preserves useful upward
		# velocity at the lip. This produces airtime without a raised end cap.
		var weight := clampf(takeoff_distance / takeoff_length, 0.0, 1.0)
		relief += takeoff_height * pow(weight, 1.5)
	elif takeoff_distance > takeoff_length and takeoff_distance <= takeoff_length + fallaway_length:
		var weight := (takeoff_distance - takeoff_length) / fallaway_length
		relief += takeoff_height * (1.0 - smoothstep(0.0, 1.0, weight))

	var receiver_distance := course_distance - receiver_start
	if receiver_distance >= 0.0 and receiver_distance <= receiver_length:
		var weight := clampf(receiver_distance / receiver_length, 0.0, 1.0)
		if weight <= receiver_crest:
			relief += receiver_height * smoothstep(0.0, 1.0, weight / receiver_crest)
		else:
			relief += receiver_height * (
				1.0 - smoothstep(0.0, 1.0, (weight - receiver_crest) / (1.0 - receiver_crest))
			)
	return relief


static func _catmull_rom(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, weight: float) -> Vector3:
	var weight_squared := weight * weight
	var weight_cubed := weight_squared * weight
	return 0.5 * (
		2.0 * p1
		+ (-p0 + p2) * weight
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * weight_squared
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * weight_cubed
	)


static func _catmull_tangent(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, weight: float) -> Vector3:
	var tangent := 0.5 * (
		(-p0 + p2)
		+ 2.0 * (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * weight
		+ 3.0 * (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * weight * weight
	)
	return tangent.normalized() if tangent.length_squared() > 0.001 else (p2 - p1).normalized()
