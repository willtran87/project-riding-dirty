extends RefCounted
class_name CourseCatalog
## Shared authored course data used by world builders, race gates, and rival playback.

const QUARRY_ID: StringName = &"QUARRY"
const PINE_ID: StringName = &"PINE"
const MESA_MX_ID: StringName = &"MESA_MX"
const MESA_MX_ROUTE_VERSION := 2

const QUARRY_ORIGIN := Vector3.ZERO
const PINE_ORIGIN := Vector3(1400.0, 0.0, 0.0)
const MESA_MX_ORIGIN := Vector3(-1500.0, 0.0, 0.0)

static var _riding_cache: Dictionary[StringName, PackedVector3Array] = {}


static func get_local_points(track_id: StringName) -> PackedVector3Array:
	if track_id == MESA_MX_ID:
		# Closed, purpose-built motocross loop. Repeating the first anchor at the
		# end makes the rendered ribbon, checkpoints, pack and minimap share the
		# same physical start/finish seam.
		return PackedVector3Array([
			Vector3(-18.0, 4.0, 142.0),
			Vector3(-78.0, 5.0, 112.0),
			Vector3(-118.0, 7.0, 48.0),
			Vector3(-112.0, 9.0, -30.0),
			Vector3(-74.0, 8.0, -94.0),
			Vector3(-10.0, 6.0, -126.0),
			Vector3(64.0, 5.0, -118.0),
			Vector3(122.0, 7.0, -68.0),
			Vector3(136.0, 9.0, 6.0),
			Vector3(112.0, 10.0, 76.0),
			Vector3(52.0, 7.0, 126.0),
			Vector3(-18.0, 4.0, 142.0),
		])
	if track_id == PINE_ID:
		return PackedVector3Array([
			Vector3(-350.0, 8.0, 300.0),
			Vector3(-220.0, 18.0, 275.0),
			Vector3(-70.0, 30.0, 300.0),
			Vector3(90.0, 42.0, 265.0),
			Vector3(245.0, 34.0, 295.0),
			Vector3(350.0, 26.0, 230.0),
			Vector3(320.0, 40.0, 150.0),
			Vector3(175.0, 55.0, 170.0),
			Vector3(20.0, 72.0, 135.0),
			Vector3(-140.0, 84.0, 165.0),
			Vector3(-285.0, 70.0, 130.0),
			Vector3(-350.0, 58.0, 60.0),
			Vector3(-305.0, 72.0, -20.0),
			Vector3(-155.0, 88.0, 10.0),
			Vector3(10.0, 100.0, -30.0),
			Vector3(170.0, 86.0, 0.0),
			Vector3(310.0, 70.0, -40.0),
			Vector3(350.0, 54.0, -120.0),
			Vector3(295.0, 68.0, -195.0),
			Vector3(145.0, 82.0, -165.0),
			Vector3(-20.0, 70.0, -205.0),
			Vector3(-175.0, 58.0, -175.0),
			Vector3(-315.0, 42.0, -220.0),
			Vector3(-350.0, 28.0, -295.0),
		])
	return PackedVector3Array([
		Vector3(-315.0, 6.0, 265.0),
		# Keep the opening climb as one broad, continuously visible S. The former
		# left-right fold brought two full-width passes within six metres of each
		# other, forced a 35 m containment gap, and aimed the rider sightline into
		# the terrain bank between them. These anchors keep forward progress toward
		# decreasing Z while retaining gentle motocross direction changes.
		Vector3(-270.0, 12.0, 210.0),
		Vector3(-252.0, 24.0, 135.0),
		Vector3(-235.0, 36.0, 65.0),
		Vector3(-222.0, 45.0, -10.0),
		Vector3(-210.0, 58.0, -95.0),
		Vector3(-95.0, 66.0, -145.0),
		# The HUD advances to "GATE 08" at this checkpoint. Its former Z=-230
		# position created a hidden 63-degree turn: maintaining the visibly presented
		# heading drove every player lane into CourseContainmentLeft0140 while the
		# collisionless opponents snapped around the spline. Distribute that turn
		# across two broad anchors so the marked road itself presents the exit.
		Vector3(20.0, 58.0, -175.0),
		Vector3(120.0, 48.5, -160.0),
		# Gate 08 begins one unambiguous downhill corridor. Every remaining anchor
		# advances toward increasing Z and loses elevation, so a later ribbon can
		# never double back across the rider's view or masquerade as a fork. The
		# broad S still uses the east/south quarry and gives the 24 m road enough
		# radius for fast, readable direction changes.
		Vector3(205.0, 39.5, -125.0),
		Vector3(275.0, 36.0, -45.0),
		Vector3(310.0, 32.5, 35.0),
		Vector3(290.0, 29.0, 115.0),
		Vector3(230.0, 25.5, 195.0),
		Vector3(145.0, 22.0, 275.0),
		Vector3(75.0, 18.5, 355.0),
		Vector3(65.0, 15.0, 435.0),
		Vector3(135.0, 11.5, 515.0),
		Vector3(315.0, 8.0, 600.0),
	])


static func get_world_points(track_id: StringName) -> PackedVector3Array:
	var points := get_local_points(track_id)
	var origin := get_district_origin(track_id)
	for index: int in points.size():
		points[index] += origin
	return points


static func get_local_riding_points(track_id: StringName) -> PackedVector3Array:
	if _riding_cache.has(track_id):
		return _riding_cache[track_id].duplicate()
	var points := get_local_points(track_id)
	var baked := PackedVector3Array()
	if track_id == MESA_MX_ID:
		baked = CourseSpline.bake_motocross(points, 0.72, 2.0, 0.64, 7319, {
			&"jump_zones": get_welded_jump_zones(MESA_MX_ID),
			&"relief_suppression_zones": [
				{&"start": 52.0, &"length": 62.0, &"fade": 6.0, &"scale": 0.0},
				{&"start": 156.0, &"length": 70.0, &"fade": 6.0, &"scale": 0.0},
				{&"start": 278.0, &"length": 74.0, &"fade": 7.0, &"scale": 0.0},
				{&"start": 414.0, &"length": 72.0, &"fade": 7.0, &"scale": 0.0},
				{&"start": 540.0, &"length": 72.0, &"fade": 7.0, &"scale": 0.0},
			],
			&"zones": [
				{&"start": 18.0, &"length": 32.0, &"height": 0.22, &"spacing": 4.7, &"sharpness": 2.6},
				{&"start": 230.0, &"length": 42.0, &"height": 0.34, &"spacing": 6.4, &"sharpness": 2.1},
				{&"start": 354.0, &"length": 48.0, &"height": 0.25, &"spacing": 4.8, &"sharpness": 2.6},
				{&"start": 492.0, &"length": 40.0, &"height": 0.38, &"spacing": 6.5, &"sharpness": 2.0},
				{&"start": 616.0, &"length": 34.0, &"height": 0.22, &"spacing": 4.7, &"sharpness": 2.6},
			],
		})
	elif track_id == PINE_ID:
		baked = CourseSpline.bake_motocross(points, 1.05, 3.2, 0.58, 42017, {
			&"zones": [
				{&"start": 155.0, &"length": 58.0, &"height": 0.3, &"spacing": 7.4, &"sharpness": 2.0},
				{&"start": 325.0, &"length": 56.0, &"height": 0.42, &"spacing": 7.2, &"sharpness": 2.2},
				{&"start": 505.0, &"length": 50.0, &"height": 0.24, &"spacing": 5.3, &"sharpness": 2.5},
				{&"start": 650.0, &"length": 52.0, &"height": 0.35, &"spacing": 7.6, &"sharpness": 2.0},
				{&"start": 855.0, &"length": 58.0, &"height": 0.4, &"spacing": 7.4, &"sharpness": 2.0},
				{&"start": 1005.0, &"length": 52.0, &"height": 0.26, &"spacing": 5.5, &"sharpness": 2.6},
				{&"start": 1320.0, &"length": 56.0, &"height": 0.4, &"spacing": 7.2, &"sharpness": 2.1},
				{&"start": 1480.0, &"length": 52.0, &"height": 0.22, &"spacing": 5.0, &"sharpness": 2.7},
				{&"start": 1650.0, &"length": 55.0, &"height": 0.36, &"spacing": 7.5, &"sharpness": 2.0},
				{&"start": 1990.0, &"length": 56.0, &"height": 0.44, &"spacing": 7.2, &"sharpness": 2.0},
				{&"start": 2160.0, &"length": 50.0, &"height": 0.23, &"spacing": 5.2, &"sharpness": 2.6},
				{&"start": 2490.0, &"length": 56.0, &"height": 0.39, &"spacing": 7.6, &"sharpness": 2.0},
				{&"start": 2640.0, &"length": 50.0, &"height": 0.22, &"spacing": 5.4, &"sharpness": 2.6},
				{&"start": 2950.0, &"length": 55.0, &"height": 0.38, &"spacing": 7.4, &"sharpness": 2.0},
				{&"start": 3090.0, &"length": 38.0, &"height": 0.2, &"spacing": 5.0, &"sharpness": 2.5},
			],
		})
	else:
		baked = CourseSpline.bake_motocross(points, 1.05, 2.4, 0.72, 1987, {
			&"jump_zones": get_welded_jump_zones(QUARRY_ID),
			# Gate 8 starts the long downhill. Keep the complete Gate 8 -> 11
			# sightline free from stacked procedural crests: the old rhythm zone at
			# 930 m and the Crusher kicker combined into one dirt-colored horizon
			# that looked like the ribbon terminated in a hill.
			&"relief_suppression_zones": [
				# Ordinary procedural crests are suppressed around the seven authored
				# welded packages. Otherwise two independent height signals can combine
				# into the same wall-like silhouettes as the removed overlay bodies.
				{&"start": 26.0, &"length": 45.0, &"fade": 5.0, &"scale": 0.0},
				{&"start": 81.0, &"length": 52.0, &"fade": 5.0, &"scale": 0.0},
				{&"start": 158.0, &"length": 51.0, &"fade": 5.0, &"scale": 0.0},
				{&"start": 233.0, &"length": 51.0, &"fade": 5.0, &"scale": 0.0},
				{&"start": 311.0, &"length": 57.0, &"fade": 5.0, &"scale": 0.0},
				{&"start": 409.0, &"length": 63.0, &"fade": 5.0, &"scale": 0.0},
				{&"start": 542.0, &"length": 65.0, &"fade": 5.0, &"scale": 0.0},
				{&"start": 746.0, &"length": 332.0, &"fade": 14.0, &"scale": 0.0},
				{&"start": 1170.0, &"length": 65.0, &"fade": 9.0, &"scale": 0.0},
				{&"start": 1575.0, &"length": 68.0, &"fade": 9.0, &"scale": 0.0},
			],
			&"zones": [
				{&"start": 105.0, &"length": 54.0, &"height": 0.48, &"spacing": 6.6, &"sharpness": 2.0},
				{&"start": 225.0, &"length": 48.0, &"height": 0.26, &"spacing": 4.5, &"sharpness": 2.7},
				{&"start": 315.0, &"length": 52.0, &"height": 0.42, &"spacing": 6.8, &"sharpness": 2.0},
				{&"start": 545.0, &"length": 54.0, &"height": 0.5, &"spacing": 6.6, &"sharpness": 2.0},
				{&"start": 1160.0, &"length": 50.0, &"height": 0.45, &"spacing": 6.8, &"sharpness": 2.0},
				{&"start": 1285.0, &"length": 50.0, &"height": 0.24, &"spacing": 4.6, &"sharpness": 2.6},
				{&"start": 1460.0, &"length": 52.0, &"height": 0.4, &"spacing": 7.0, &"sharpness": 2.0},
				{&"start": 1545.0, &"length": 46.0, &"height": 0.2, &"spacing": 4.4, &"sharpness": 2.7},
				# The current route shortens the Gate-8 control chord by 44.03 m. Keep this final rhythm
				# set at its original finish-relative position so the last 60 m remain a
				# planted, readable run through the timed gate and braking apron.
				{&"start": 1716.0, &"length": 52.0, &"height": 0.46, &"spacing": 6.7, &"sharpness": 2.0},
				{&"start": 1900.0, &"length": 50.0, &"height": 0.24, &"spacing": 4.5, &"sharpness": 2.7},
			],
		})
	_riding_cache[track_id] = baked
	return baked.duplicate()


static func get_welded_jump_zones(track_id: StringName) -> Array[Dictionary]:
	if track_id == MESA_MX_ID:
		return [
			{&"name": &"GateDropDouble", &"start": 58.0, &"takeoff_length": 11.0, &"takeoff_height": 1.45, &"fallaway_length": 4.5, &"receiver_start": 77.0, &"receiver_length": 24.0, &"receiver_height": 1.05, &"receiver_crest": 0.38},
			{&"name": &"WestTriple", &"start": 162.0, &"takeoff_length": 12.0, &"takeoff_height": 1.75, &"fallaway_length": 5.0, &"receiver_start": 187.0, &"receiver_length": 33.0, &"receiver_height": 1.28, &"receiver_crest": 0.38},
			{&"name": &"BackTable", &"start": 286.0, &"takeoff_length": 13.0, &"takeoff_height": 1.85, &"fallaway_length": 5.0, &"receiver_start": 313.0, &"receiver_length": 34.0, &"receiver_height": 1.35, &"receiver_crest": 0.4},
			{&"name": &"EastTransfer", &"start": 422.0, &"takeoff_length": 12.0, &"takeoff_height": 1.65, &"fallaway_length": 5.0, &"receiver_start": 447.0, &"receiver_length": 32.0, &"receiver_height": 1.18, &"receiver_crest": 0.38},
			{&"name": &"FinishTable", &"start": 548.0, &"takeoff_length": 13.0, &"takeoff_height": 1.80, &"fallaway_length": 5.0, &"receiver_start": 576.0, &"receiver_length": 31.0, &"receiver_height": 1.28, &"receiver_crest": 0.38},
		]
	if track_id != QUARRY_ID:
		return []
	# These seven packages replace fourteen separate 22-23 m wide overlay bodies.
	# Heights are deliberately lower, while short fallaways preserve launch speed;
	# the following receiver stays part of the same marked, welded road.
	return [
		{&"name": &"LaunchMesa", &"start": 31.0, &"takeoff_length": 11.0, &"takeoff_height": 1.60, &"fallaway_length": 4.5, &"receiver_start": 49.0, &"receiver_length": 16.0, &"receiver_height": 1.05, &"receiver_crest": 0.42},
		{&"name": &"CanyonStepUp", &"start": 86.0, &"takeoff_length": 11.0, &"takeoff_height": 1.65, &"fallaway_length": 4.5, &"receiver_start": 105.0, &"receiver_length": 22.0, &"receiver_height": 1.20, &"receiver_crest": 0.38},
		{&"name": &"SwitchbackPop", &"start": 163.0, &"takeoff_length": 11.0, &"takeoff_height": 1.55, &"fallaway_length": 4.5, &"receiver_start": 182.0, &"receiver_length": 21.0, &"receiver_height": 1.10, &"receiver_crest": 0.38},
		{&"name": &"Cutback", &"start": 238.0, &"takeoff_length": 11.0, &"takeoff_height": 1.70, &"fallaway_length": 4.5, &"receiver_start": 257.0, &"receiver_length": 22.0, &"receiver_height": 1.20, &"receiver_crest": 0.38},
		{&"name": &"Bench", &"start": 316.0, &"takeoff_length": 12.0, &"takeoff_height": 1.85, &"fallaway_length": 5.0, &"receiver_start": 338.0, &"receiver_length": 24.0, &"receiver_height": 1.35, &"receiver_crest": 0.38},
		{&"name": &"Overburden", &"start": 414.0, &"takeoff_length": 12.0, &"takeoff_height": 1.80, &"fallaway_length": 5.0, &"receiver_start": 442.0, &"receiver_length": 24.0, &"receiver_height": 1.35, &"receiver_crest": 0.38},
		{&"name": &"Summit", &"start": 547.0, &"takeoff_length": 13.0, &"takeoff_height": 2.00, &"fallaway_length": 6.0, &"receiver_start": 574.0, &"receiver_length": 27.0, &"receiver_height": 1.50, &"receiver_crest": 0.38},
	]


static func get_world_riding_points(track_id: StringName) -> PackedVector3Array:
	var points := get_local_riding_points(track_id)
	var origin := get_district_origin(track_id)
	for index: int in points.size():
		points[index] += origin
	return points


static func get_district_origin(track_id: StringName) -> Vector3:
	if track_id == PINE_ID:
		return PINE_ORIGIN
	if track_id == MESA_MX_ID:
		return MESA_MX_ORIGIN
	return QUARRY_ORIGIN


static func get_track_width(track_id: StringName) -> float:
	# The visible race ribbon is deliberately broader than the five-slot pack.
	# NPCs keep their central lane cap while the player gets a genuine recovery
	# lane on either side instead of immediately reaching a shoulder or barrier.
	if track_id == PINE_ID:
		return 22.0
	if track_id == MESA_MX_ID:
		return 23.0
	return 24.0


static func get_spawn_transform(
	track_id: StringName,
	authoritative_route: PackedVector3Array = PackedVector3Array()
) -> Transform3D:
	var points := _resolve_world_route(track_id, authoritative_route)
	if points.size() < 2:
		return Transform3D.IDENTITY
	var direction := CourseSpline.tangent_at(points, 1)
	var basis := Basis.looking_at(direction, Vector3.UP)
	# Move the chassis just inside the first trail segment so both suspension
	# contacts sit on dirt at the line instead of leaving the driven rear wheel
	# hanging behind the authored endpoint. Offset along the trail normal so the
	# wheels remain planted on steep starts during the frozen countdown.
	# Keep both suspension contacts on the proven center line. The visual pack
	# reserves the nearest grid slot around this physical player position.
	return Transform3D(basis, points[0] + direction * 2.0 + basis.y * 0.67)


static func get_checkpoint_data(
	track_id: StringName,
	authoritative_route: PackedVector3Array = PackedVector3Array()
) -> Array[Dictionary]:
	var points := get_world_points(track_id)
	var riding_points := _resolve_world_route(track_id, authoritative_route)
	var checkpoints: Array[Dictionary] = []
	if riding_points.size() < 2:
		return checkpoints
	var route_indices := get_checkpoint_route_indices(track_id, riding_points)
	for index: int in range(1, points.size()):
		if index - 1 >= route_indices.size():
			break
		var riding_index := route_indices[index - 1]
		var direction := CourseSpline.tangent_at(riding_points, riding_index)
		checkpoints.append({
			# The rendered route owns the gate center. Authored control points only
			# select progress along that route; they may never pull a gate off-road.
			&"position": riding_points[riding_index] + Vector3.UP * 2.3,
			&"yaw": atan2(direction.x, direction.z),
		})
	return checkpoints


static func get_checkpoint_route_indices(
	track_id: StringName,
	authoritative_route: PackedVector3Array = PackedVector3Array()
) -> PackedInt32Array:
	var controls := get_world_points(track_id)
	var route := _resolve_world_route(track_id, authoritative_route)
	var indices := PackedInt32Array()
	if route.size() < 2 or controls.size() < 2:
		return indices
	# Project gates in authored order. An unrestricted nearest-point query can
	# choose an earlier pass when two parts of a trail run close together. Once a
	# gate advances, later gates may only select a strictly later route sample.
	var search_start := 1
	for control_index: int in range(1, controls.size()):
		var remaining_controls := controls.size() - control_index - 1
		var search_end := maxi(route.size() - remaining_controls - 1, search_start)
		var best_index := search_start
		var best_distance_squared := INF
		for route_index: int in range(search_start, mini(search_end + 1, route.size())):
			var distance_squared := route[route_index].distance_squared_to(controls[control_index])
			if distance_squared < best_distance_squared:
				best_distance_squared = distance_squared
				best_index = route_index
		indices.append(best_index)
		search_start = mini(best_index + 1, route.size() - 1)
	return indices


static func get_medal_times_usec(track_id: StringName) -> Dictionary:
	if track_id == MESA_MX_ID:
		return {&"gold": 225_000_000, &"silver": 270_000_000, &"bronze": 330_000_000}
	if track_id == PINE_ID:
		return {&"gold": 245_000_000, &"silver": 325_000_000, &"bronze": 440_000_000}
	return {&"gold": 165_000_000, &"silver": 220_000_000, &"bronze": 300_000_000}


static func get_rival_target_usec(track_id: StringName) -> int:
	if track_id == PINE_ID:
		return 285_000_000
	if track_id == MESA_MX_ID:
		return 245_000_000
	return 190_000_000


static func get_checkpoint_progress_ratios(
	track_id: StringName,
	authoritative_route: PackedVector3Array = PackedVector3Array()
) -> PackedFloat32Array:
	var riding_points := _resolve_world_route(track_id, authoritative_route)
	var cumulative_distance := PackedFloat32Array()
	cumulative_distance.resize(riding_points.size())
	var total_distance := 0.0
	for index: int in range(1, riding_points.size()):
		total_distance += riding_points[index - 1].distance_to(riding_points[index])
		cumulative_distance[index] = total_distance
	if total_distance <= 0.001:
		return PackedFloat32Array()
	var ratios := PackedFloat32Array()
	var route_indices := get_checkpoint_route_indices(track_id, riding_points)
	for riding_index: int in route_indices:
		ratios.append(cumulative_distance[riding_index] / total_distance)
	return ratios


static func _resolve_world_route(
	track_id: StringName,
	authoritative_route: PackedVector3Array
) -> PackedVector3Array:
	# Builders pass the exact centerline used to construct their visible and
	# physical ribbon. Catalog baking remains a compatibility fallback for
	# isolated tooling; production race systems receive the built route.
	if authoritative_route.size() >= 2:
		return authoritative_route.duplicate()
	return get_world_riding_points(track_id)


static func get_activity_id(track_id: StringName) -> StringName:
	if track_id == PINE_ID:
		return &"PINE_ENDURO"
	if track_id == MESA_MX_ID:
		return &"MESA_MX"
	return &"CIRCUIT"


static func get_record_slot(track_id: StringName) -> StringName:
	# The current Quarry route makes the HUD Gate-8 entry visibly readable in the player's
	# presented heading. Keep records from the hidden-turn V17 route separate.
	if track_id == PINE_ID:
		return &"pine_trail_v4"
	if track_id == MESA_MX_ID:
		return &"mesa_mx_v2"
	return &"quarry_trail_v19"
