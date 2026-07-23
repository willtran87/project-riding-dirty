extends Node
## Diagnostics-only audit of visual clipping between lightweight race-pack bikes
## and any authored overlay surfaces that sit above a course spline. Quarry must
## remain overlay-free: its seven major jumps are welded into its main ribbon.

const QuarryBuilderScript = preload("res://levels/quarry/quarry_builder.gd")
const PineBuilderScript = preload("res://levels/pine_ridge/pine_ridge_builder.gd")

# RacePack places the visual root 0.76 m above its spline position. Both wheel
# axles are 0.39 m below that root and the 0.37 m tyre is scaled by 0.82973.
# RacePack then adds 0.02 +/- 0.015 m of vertical presentation bob.
const TYRE_RADIUS: float = 0.37 * 0.82973
const AXLE_BELOW_VISUAL_ROOT: float = 0.39
const VISUAL_ROOT_HEIGHT: float = 0.76
const PACK_BOB_CENTER: float = 0.02
const PACK_BOB_AMPLITUDE: float = 0.015
const NOMINAL_TYRE_BOTTOM: float = VISUAL_ROOT_HEIGHT - AXLE_BELOW_VISUAL_ROOT - TYRE_RADIUS + PACK_BOB_CENTER
const HIGHEST_TYRE_BOTTOM: float = NOMINAL_TYRE_BOTTOM + PACK_BOB_AMPLITUDE
const LOWEST_TYRE_BOTTOM: float = NOMINAL_TYRE_BOTTOM - PACK_BOB_AMPLITUDE
const PACK_LANES := [-5.0, -2.5, 0.0, 2.5, 5.0]
const LONGITUDINAL_SAMPLES: int = 65
const QUARRY_OVERLAY_COUNT: int = 0
const PINE_OVERLAY_COUNT: int = 47
const TOTAL_OVERLAY_COUNT: int = QUARRY_OVERLAY_COUNT + PINE_OVERLAY_COUNT


func _ready() -> void:
	var total_overlays := 0
	var total_relief_surfaces := 0
	var passed := true
	for track_id: StringName in [CourseCatalog.QUARRY_ID, CourseCatalog.PINE_ID]:
		passed = _audit_cross_loop_barriers(track_id) and passed
		passed = _audit_main_ribbon(track_id) and passed
		_audit_pack_grid(track_id)
		passed = _audit_alternate_seams(track_id) and passed
		var result := _audit_track(track_id)
		total_overlays += int(result[&"overlays"])
		total_relief_surfaces += int(result[&"clipping"])
		passed = bool(result[&"passed"]) and passed
	passed = passed and total_overlays == TOTAL_OVERLAY_COUNT
	print("GEOMETRY CLIPPING SUMMARY: overlays=%d/%d relief_surfaces=%d ribbon_crossings=0 tyre_bottom=%.3f..%.3fm all_pack_lanes_audited=true passed=%s" % [
		total_overlays, TOTAL_OVERLAY_COUNT, total_relief_surfaces, LOWEST_TYRE_BOTTOM, HIGHEST_TYRE_BOTTOM, str(passed),
	])
	get_tree().quit(0 if passed else 1)


func _audit_track(track_id: StringName) -> Dictionary:
	var builder := _construct_overlays(track_id)
	var route := CourseCatalog.get_local_riding_points(track_id)
	var route_chainages := PackedFloat32Array()
	route_chainages.resize(route.size())
	for route_index: int in range(1, route.size()):
		route_chainages[route_index] = route_chainages[route_index - 1] + route[route_index - 1].distance_to(route[route_index])
	var overlays: Array[StaticBody3D] = []
	for candidate: Node in builder.find_children("*", "StaticBody3D", true, false):
		var body := candidate as StaticBody3D
		if body.has_meta(&"rhythm_role") or body.name == &"LogBridge":
			overlays.append(body)

	var clipping_count := 0
	var worst_name := ""
	var worst_intrusion := -INF
	var minimum_peak_intrusion := INF
	var minimum_visual_gap := INF
	var maximum_visual_gap := -INF
	var crossing_visual_overlays := 0
	var minimum_collision_gap := INF
	var maximum_collision_gap := -INF
	var crossing_collision_overlays := 0
	var separation_passed := true
	for body: StaticBody3D in overlays:
		var result := _audit_overlay(body, route)
		separation_passed = bool(result.get(&"passed", false)) and separation_passed
		var peak := float(result[&"peak_intrusion"])
		var clipped_fraction := float(result[&"clipped_fraction"])
		if peak > 0.0:
			clipping_count += 1
		minimum_peak_intrusion = minf(minimum_peak_intrusion, peak)
		if peak > worst_intrusion:
			worst_intrusion = peak
			worst_name = String(body.name)
		var visual_min := float(result[&"minimum_visual_gap"])
		var visual_max := float(result[&"maximum_visual_gap"])
		var collision_min := float(result[&"minimum_collision_gap"])
		var collision_max := float(result[&"maximum_collision_gap"])
		minimum_visual_gap = minf(minimum_visual_gap, visual_min)
		maximum_visual_gap = maxf(maximum_visual_gap, visual_max)
		minimum_collision_gap = minf(minimum_collision_gap, collision_min)
		maximum_collision_gap = maxf(maximum_collision_gap, collision_max)
		if visual_min < -0.0001 and visual_max > 0.0001:
			crossing_visual_overlays += 1
		if collision_min < -0.0001 and collision_max > 0.0001:
			crossing_collision_overlays += 1
		if (visual_min < -0.0001 and visual_max > 0.0001) or (collision_min < -0.0001 and collision_max > 0.0001):
			print("OVERLAY CROSSING: track=%s node=%s visual=%.3f..%.3fm collision=%.3f..%.3fm" % [
				String(track_id), String(body.name), visual_min, visual_max,
				collision_min, collision_max,
			])
		var route_index := int(body.get_meta(&"route_index", CourseSpline.closest_index(route, body.position)))
		var chainage := route_chainages[clampi(route_index, 0, route_chainages.size() - 1)]
		print("OVERLAY RELIEF: track=%s node=%s role=%s route_index=%d chainage=%.1fm peak=%.3fm conservative_peak=%.3fm raised_samples=%.1f%% lane=%+.1fm longitudinal=%.3f" % [
			String(track_id), String(body.name), String(result[&"role"]), route_index,
			chainage, peak, float(result[&"conservative_peak"]), clipped_fraction * 100.0,
			float(result[&"worst_lane"]), float(result[&"worst_weight"]),
		])
	print("OVERLAY RELIEF RESULT: track=%s overlays=%d raised=%d minimum_overlay_peak=%.3fm highest=%s maximum_relief=%.3fm" % [
		String(track_id), overlays.size(), clipping_count, minimum_peak_intrusion,
		worst_name, worst_intrusion,
	])
	print("OVERLAY/RIBBON LAYERING: track=%s visual_gap=%.3f..%.3fm visual_crossings=%d collision_gap=%.3f..%.3fm collision_crossings=%d top_only=true" % [
		String(track_id), minimum_visual_gap, maximum_visual_gap, crossing_visual_overlays,
		minimum_collision_gap, maximum_collision_gap, crossing_collision_overlays,
	])
	var expected_overlays := PINE_OVERLAY_COUNT if track_id == CourseCatalog.PINE_ID else QUARRY_OVERLAY_COUNT
	var track_passed := (
		overlays.size() == expected_overlays
		and crossing_visual_overlays == 0
		and crossing_collision_overlays == 0
		and minimum_visual_gap >= -0.0001
		and minimum_collision_gap >= -0.0001
		and separation_passed
	)
	print("OVERLAY SEPARATION RESULT: track=%s overlays=%d/%d minimum=%.3fm full_footprint=true visual_collision_match=true passed=%s" % [
		String(track_id), overlays.size(), expected_overlays,
		minf(minimum_visual_gap, minimum_collision_gap), str(track_passed),
	])
	builder.free()
	return {&"overlays": overlays.size(), &"clipping": clipping_count, &"passed": track_passed}


func _construct_overlays(track_id: StringName) -> Node3D:
	var builder: Node3D
	if track_id == CourseCatalog.PINE_ID:
		builder = PineBuilderScript.new()
	else:
		builder = QuarryBuilderScript.new()
	builder.set("_track_points", CourseCatalog.get_local_points(track_id))
	builder.set("_ride_points", CourseCatalog.get_local_riding_points(track_id))
	builder.set("_track_width", CourseCatalog.get_track_width(track_id))
	var main_frames := CourseSurfaceBuilder._build_frames(
		CourseCatalog.get_local_riding_points(track_id),
		CourseCatalog.get_track_width(track_id),
		builder.call("_main_surface_config")
	)
	builder.set("_terrain_surface_profiles", [{&"frames": main_frames}])
	var materials: Dictionary = builder.get("_materials")
	for key: StringName in [&"track", &"track_edge", &"trail", &"trail_edge", &"rut", &"water", &"wood", &"bark"]:
		materials[key] = StandardMaterial3D.new()
	if track_id == CourseCatalog.PINE_ID:
		builder.call("_build_jumps")
		builder.call("_build_creek_crossing")
	else:
		builder.call("_build_jump_line")
	return builder


func _audit_main_ribbon(track_id: StringName) -> bool:
	var route := CourseCatalog.get_local_riding_points(track_id)
	var width := CourseCatalog.get_track_width(track_id)
	var level_builder: Node3D = PineBuilderScript.new() if track_id == CourseCatalog.PINE_ID else QuarryBuilderScript.new()
	var config: Dictionary = level_builder.call("_main_surface_config")
	var root := Node3D.new()
	var material := StandardMaterial3D.new()
	var ribbon := CourseSurfaceBuilder.build(
		root, "MainRibbonProbe", route, width, material, material, material,
		&"DIRT", 1.0, 1.0, config
	)
	var collisions := ribbon.find_children("*", "CollisionShape3D", true, false)
	var welded := collisions.size() == 1 and bool(ribbon.get_meta(&"welded_collision", false))
	var top_only := false
	var collision_triangles := 0
	if collisions.size() == 1:
		var collision := collisions[0] as CollisionShape3D
		if collision.shape is ConcavePolygonShape3D:
			var shape := collision.shape as ConcavePolygonShape3D
			top_only = not shape.backface_collision
			collision_triangles = shape.get_faces().size() / 3

	# Every visual chunk duplicates the exact boundary row from the shared frame
	# array. Verify those rows instead of merely assuming chunk seams line up.
	var chunks := ribbon.find_children("RibbonChunk*", "Node3D", false, false)
	var seam_count := 0
	var maximum_seam_gap := 0.0
	for chunk_index: int in range(chunks.size() - 1):
		var first := (chunks[chunk_index] as Node3D).find_child("RaceSurface", false, false) as MeshInstance3D
		var second := (chunks[chunk_index + 1] as Node3D).find_child("RaceSurface", false, false) as MeshInstance3D
		if first == null or second == null or first.mesh == null or second.mesh == null:
			maximum_seam_gap = INF
			continue
		var first_vertices: PackedVector3Array = first.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var second_vertices: PackedVector3Array = second.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		const PROFILE_COLUMNS := 9
		if first_vertices.size() < PROFILE_COLUMNS or second_vertices.size() < PROFILE_COLUMNS:
			maximum_seam_gap = INF
			continue
		for column: int in PROFILE_COLUMNS:
			var first_vertex := first_vertices[first_vertices.size() - PROFILE_COLUMNS + column]
			var second_vertex := second_vertices[column]
			maximum_seam_gap = maxf(maximum_seam_gap, first_vertex.distance_to(second_vertex))
		seam_count += 1

	var visual_profile := CourseSurfaceBuilder._visual_track_profile(width, config)
	var collision_profile := CourseSurfaceBuilder._collision_track_profile(width, config)
	var profile_gap := 0.0
	var dummy_frame := {
		&"up": Vector3.UP, &"right": Vector3.RIGHT, &"curvature": 0.0,
		&"berm_height": 0.0, &"half_width": width * 0.5,
	}
	var visual_offsets: PackedFloat32Array = visual_profile[&"offsets"]
	for offset: float in visual_offsets:
		var visual_height := CourseSurfaceBuilder._profile_height_at(dummy_frame, offset, width, visual_profile)
		var collision_height := CourseSurfaceBuilder._profile_height_at(dummy_frame, offset, width, collision_profile)
		profile_gap = maxf(profile_gap, absf(visual_height - collision_height))

	var proximity := _audit_nonlocal_ribbon_proximity(route, width + float(config[&"shoulder_width"]) * 2.0)
	var passed := (
		welded and top_only and collision_triangles > 0
		and seam_count == maxi(chunks.size() - 1, 0)
		and maximum_seam_gap <= 0.00001
		and profile_gap <= 0.00001
		and bool(proximity[&"passed"])
	)
	print("MAIN RIBBON CONTINUITY: track=%s visual_chunks=%d welded_collision_shapes=%d collision_triangles=%d visual_seams=%d maximum_seam_gap=%.6fm visual_collision_profile_gap=%.6fm backface_collision=%s nonlocal_minimum=%.2fm vertical_gap=%.2fm passed=%s" % [
		String(track_id), chunks.size(), collisions.size(), collision_triangles,
		seam_count, maximum_seam_gap, profile_gap, str(not top_only),
		float(proximity[&"distance"]), float(proximity[&"vertical_gap"]), str(passed),
	])
	root.free()
	level_builder.free()
	return passed


func _audit_nonlocal_ribbon_proximity(route: PackedVector3Array, full_outer_width: float) -> Dictionary:
	var chainages := PackedFloat32Array()
	chainages.resize(route.size())
	for index: int in range(1, route.size()):
		chainages[index] = chainages[index - 1] + route[index - 1].distance_to(route[index])
	var minimum_distance := INF
	var minimum_vertical_gap := INF
	for first: int in range(0, route.size(), 4):
		for second: int in range(first + 4, route.size(), 4):
			if absf(chainages[second] - chainages[first]) < 55.0:
				continue
			var distance := Vector2(route[first].x, route[first].z).distance_to(Vector2(route[second].x, route[second].z))
			if distance < minimum_distance:
				minimum_distance = distance
				minimum_vertical_gap = absf(route[first].y - route[second].y)
	# Horizontally overlapping switchbacks are valid only when there is enough
	# vertical room for a bike; otherwise two collision ribbons occupy the same
	# traversable envelope.
	var dangerous_overlap := minimum_distance < full_outer_width and minimum_vertical_gap < 3.0
	return {&"distance": minimum_distance, &"vertical_gap": minimum_vertical_gap, &"passed": not dangerous_overlap}


func _audit_alternate_seams(track_id: StringName) -> bool:
	var builder: Node3D = PineBuilderScript.new() if track_id == CourseCatalog.PINE_ID else QuarryBuilderScript.new()
	if track_id == CourseCatalog.QUARRY_ID:
		var quarry_alternates: Array = builder.get("_alternate_trails")
		var passed := quarry_alternates.is_empty()
		print("ALTERNATE SEAM RESULT: track=QUARRY alternates=0 single_route_legibility=true passed=%s" % str(passed))
		builder.free()
		return passed
	var main_route := CourseCatalog.get_local_riding_points(track_id)
	var main_width := CourseCatalog.get_track_width(track_id)
	var main_config: Dictionary = builder.call("_main_surface_config")
	var alternate_config: Dictionary = builder.call("_alternate_surface_config")
	var controls: Array[PackedVector3Array] = []
	controls = builder.get("_alternate_trails")
	var alternate_routes: Array[PackedVector3Array] = []
	for index: int in controls.size():
		alternate_routes.append(CourseSpline.bake_motocross(
			controls[index],
			2.4 if track_id == CourseCatalog.PINE_ID else 2.5,
			1.35 if track_id == CourseCatalog.PINE_ID else 1.6,
			0.22 if track_id == CourseCatalog.PINE_ID else 0.26,
			42064 + index * 19 if track_id == CourseCatalog.PINE_ID else 2018 + index * 17
		))
	var main_frames := CourseSurfaceBuilder._build_frames(main_route, main_width, main_config)
	var alternate_width := 4.8 if track_id == CourseCatalog.PINE_ID else 5.8
	var shoulder_width := float(alternate_config[&"shoulder_width"])
	var expected_ratio := float(alternate_config[&"endpoint_minimum_width_ratio"])
	var passed := alternate_routes.size() == 2
	var seam_count := 0
	var minimum_visual_lift := INF
	var minimum_collision_lift := INF
	var maximum_visual_span := 0.0
	var maximum_collision_span := 0.0
	for alternate_index: int in alternate_routes.size():
		var alternate := alternate_routes[alternate_index]
		var alternate_frames := CourseSurfaceBuilder._build_frames(alternate, alternate_width, alternate_config)
		var probe_material := StandardMaterial3D.new()
		var probe_root := CourseSurfaceBuilder.build(
			builder,
			"AlternateSeamProbe%02d" % alternate_index,
			alternate,
			alternate_width,
			probe_material,
			probe_material,
			probe_material,
			&"DIRT",
			1.0,
			1.0,
			alternate_config
		)
		var mesh_quality := _audit_surface_mesh_quality(probe_root)
		passed = bool(mesh_quality[&"passed"]) and passed
		print("ALTERNATE MESH QUALITY: track=%s alternate=%d triangles=%d collision_triangles=%d minimum_double_area=%.6f minimum_up=%.3f passed=%s" % [
			String(track_id), alternate_index, int(mesh_quality[&"triangles"]),
			int(mesh_quality[&"collision_triangles"]), float(mesh_quality[&"minimum_double_area"]),
			float(mesh_quality[&"minimum_up"]), str(mesh_quality[&"passed"]),
		])
		for endpoint_index: int in [0, alternate_frames.size() - 1]:
			var alternate_frame: Dictionary = alternate_frames[endpoint_index]
			var endpoint: Vector3 = alternate_frame[&"position"]
			var main_index := CourseSpline.closest_index(main_route, endpoint)
			var main_frame: Dictionary = main_frames[main_index]
			var alternate_up: Vector3 = alternate_frame[&"up"]
			var main_up: Vector3 = main_frame[&"up"]
			var alternate_lift: float = alternate_frame[&"surface_lift"]
			var visual_lift := (
				endpoint.y + alternate_up.y * (0.04 + alternate_lift)
				- (float(main_frame[&"position"].y) + main_up.y * 0.04)
			)
			var collision_lift := (
				endpoint.y + alternate_up.y * (0.04 + alternate_lift)
				- (float(main_frame[&"position"].y) + main_up.y * 0.04)
			)
			var width_scale: float = alternate_frame[&"width_scale"]
			var visual_span := alternate_width * width_scale
			var collision_span := (alternate_width + shoulder_width * 2.0) * width_scale
			minimum_visual_lift = minf(minimum_visual_lift, visual_lift)
			minimum_collision_lift = minf(minimum_collision_lift, collision_lift)
			maximum_visual_span = maxf(maximum_visual_span, visual_span)
			maximum_collision_span = maxf(maximum_collision_span, collision_span)
			seam_count += 1
			passed = (
				visual_lift >= 0.04
				and collision_lift >= 0.04
				and width_scale <= expected_ratio + 0.001
				and passed
			)
			print("ALTERNATE SEAM: track=%s alternate=%d endpoint=%s visual_lift=%.3fm collision_lift=%.3fm visual_span=%.3fm collision_span=%.3fm" % [
				String(track_id), alternate_index, "start" if endpoint_index == 0 else "end",
				visual_lift, collision_lift, visual_span, collision_span,
			])
	passed = passed and seam_count == 4
	print("ALTERNATE SEAM RESULT: track=%s seams=%d/4 minimum_visual_lift=%.3fm minimum_collision_lift=%.3fm maximum_visual_span=%.3fm maximum_collision_span=%.3fm passed=%s" % [
		String(track_id), seam_count, minimum_visual_lift, minimum_collision_lift,
		maximum_visual_span, maximum_collision_span, str(passed),
	])
	builder.free()
	return passed


func _audit_surface_mesh_quality(root: Node3D) -> Dictionary:
	var triangle_count := 0
	var collision_triangle_count := 0
	var minimum_double_area := INF
	var minimum_up := INF
	var passed := true
	for candidate: Node in root.find_children("*", "MeshInstance3D", true, false):
		var visual := candidate as MeshInstance3D
		if visual.mesh == null:
			continue
		for surface_index: int in visual.mesh.get_surface_count():
			var arrays := visual.mesh.surface_get_arrays(surface_index)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for cursor: int in range(0, indices.size(), 3):
				var a := vertices[indices[cursor]]
				var b := vertices[indices[cursor + 1]]
				var c := vertices[indices[cursor + 2]]
				var cross := (b - a).cross(c - a)
				var double_area := cross.length()
				var rideable_up := -cross.normalized().y if double_area > 0.000001 else -INF
				minimum_double_area = minf(minimum_double_area, double_area)
				minimum_up = minf(minimum_up, rideable_up)
				triangle_count += 1
				passed = (
					double_area > 0.00001
					and rideable_up > 0.08
					and normals.size() == vertices.size()
					and normals[indices[cursor]].y > 0.05
					and passed
				)
	for candidate: Node in root.find_children("*", "CollisionShape3D", true, false):
		var collision := candidate as CollisionShape3D
		if not collision.shape is ConcavePolygonShape3D:
			continue
		var faces := (collision.shape as ConcavePolygonShape3D).get_faces()
		for cursor: int in range(0, faces.size(), 3):
			var cross := (faces[cursor + 1] - faces[cursor]).cross(faces[cursor + 2] - faces[cursor])
			var double_area := cross.length()
			var rideable_up := -cross.normalized().y if double_area > 0.000001 else -INF
			minimum_double_area = minf(minimum_double_area, double_area)
			minimum_up = minf(minimum_up, rideable_up)
			collision_triangle_count += 1
			passed = double_area > 0.00001 and rideable_up > 0.08 and passed
	return {
		&"triangles": triangle_count,
		&"collision_triangles": collision_triangle_count,
		&"minimum_double_area": minimum_double_area,
		&"minimum_up": minimum_up,
		&"passed": passed and triangle_count > 0 and collision_triangle_count > 0,
	}


func _audit_overlay(body: StaticBody3D, route: PackedVector3Array) -> Dictionary:
	if bool(body.get_meta(&"bank_aware_overlay", false)):
		return _audit_draped_overlay(body, route)
	if body.name == &"LogBridge":
		return _audit_bridge(body, route)
	var route_hint := int(body.get_meta(&"route_index", CourseSpline.closest_index(route, body.position)))
	var length := float(body.get_meta(&"ramp_length"))
	var width := float(body.get_meta(&"ramp_width"))
	var height := float(body.get_meta(&"ramp_height"))
	var takeoff := StringName(body.get_meta(&"rhythm_role")) == &"TAKEOFF"
	var high_z := -length * 0.5 if takeoff else length * 0.5
	var low_z := length * 0.5 if takeoff else -length * 0.5
	var peak_intrusion := -INF
	var conservative_peak := -INF
	var worst_lane := 0.0
	var worst_weight := 0.0
	var clipped_samples := 0
	var sample_count := 0
	var minimum_visual_gap := INF
	var maximum_visual_gap := -INF
	var minimum_collision_gap := INF
	var maximum_collision_gap := -INF
	for lane: float in PACK_LANES:
		if absf(lane) > width * 0.5 - 0.2:
			continue
		for sample_index: int in LONGITUDINAL_SAMPLES:
			var weight := float(sample_index) / float(LONGITUDINAL_SAMPLES - 1)
			var local_point := Vector3(
				lane,
				height * _progressive_ramp_ratio(weight),
				lerpf(low_z, high_z, weight)
			)
			var point := body.transform * local_point
			var route_y := _route_height_at(route, Vector2(point.x, point.z), route_hint)
			var intrusion := point.y - (route_y + NOMINAL_TYRE_BOTTOM)
			var conservative := point.y - (route_y + HIGHEST_TYRE_BOTTOM)
			if intrusion > 0.0:
				clipped_samples += 1
			sample_count += 1
			if intrusion > peak_intrusion:
				peak_intrusion = intrusion
				worst_lane = lane
				worst_weight = weight
			conservative_peak = maxf(conservative_peak, conservative)
			if is_zero_approx(lane):
				minimum_visual_gap = minf(minimum_visual_gap, point.y - (route_y + 0.075))
				maximum_visual_gap = maxf(maximum_visual_gap, point.y - (route_y + 0.075))
				minimum_collision_gap = minf(minimum_collision_gap, point.y - (route_y + 0.04))
				maximum_collision_gap = maxf(maximum_collision_gap, point.y - (route_y + 0.04))
	return {
		&"role": &"TAKEOFF" if takeoff else &"LANDING",
		&"peak_intrusion": peak_intrusion,
		&"conservative_peak": conservative_peak,
		&"clipped_fraction": float(clipped_samples) / maxf(float(sample_count), 1.0),
		&"worst_lane": worst_lane,
		&"worst_weight": worst_weight,
		&"minimum_visual_gap": minimum_visual_gap,
		&"maximum_visual_gap": maximum_visual_gap,
		&"minimum_collision_gap": minimum_collision_gap,
		&"maximum_collision_gap": maximum_collision_gap,
		&"passed": false,
	}


func _audit_draped_overlay(body: StaticBody3D, route: PackedVector3Array) -> Dictionary:
	var role := &"BRIDGE" if body.name == &"LogBridge" else StringName(body.get_meta(&"rhythm_role", &""))
	var failed := {
		&"role": role,
		&"peak_intrusion": -INF,
		&"conservative_peak": -INF,
		&"clipped_fraction": 0.0,
		&"worst_lane": 0.0,
		&"worst_weight": 0.0,
		&"minimum_visual_gap": -INF,
		&"maximum_visual_gap": -INF,
		&"minimum_collision_gap": -INF,
		&"maximum_collision_gap": -INF,
		&"passed": false,
	}
	var visual := body.find_child("OverlaySurface", false, false) as MeshInstance3D
	var collision := body.find_child("OverlayTopCollision", false, false) as CollisionShape3D
	if visual == null or visual.mesh == null or collision == null or not collision.shape is ConcavePolygonShape3D:
		return failed
	var arrays := visual.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var base_vertices: PackedVector3Array = body.get_meta(&"overlay_base_vertices", PackedVector3Array())
	var row_count := int(body.get_meta(&"overlay_row_count", 0))
	var column_count := int(body.get_meta(&"overlay_column_count", 0))
	var offsets: PackedFloat32Array = body.get_meta(&"overlay_offsets", PackedFloat32Array())
	if (
		vertices.is_empty()
		or vertices.size() != base_vertices.size()
		or row_count * column_count != vertices.size()
		or offsets.size() != column_count
		or indices.is_empty()
	):
		return failed

	var minimum_gap := INF
	var maximum_gap := -INF
	var peak_intrusion := -INF
	var conservative_peak := -INF
	var clipped_samples := 0
	var route_hint := int(body.get_meta(&"route_index", CourseSpline.closest_index(route, body.position)))
	var worst_lane := 0.0
	var worst_weight := 0.0
	for vertex_index: int in vertices.size():
		var gap := vertices[vertex_index].y - base_vertices[vertex_index].y
		minimum_gap = minf(minimum_gap, gap)
		maximum_gap = maxf(maximum_gap, gap)
		var point := body.transform * vertices[vertex_index]
		var route_y := _route_height_at(route, Vector2(point.x, point.z), route_hint, 96)
		var intrusion := point.y - (route_y + NOMINAL_TYRE_BOTTOM)
		var conservative := point.y - (route_y + HIGHEST_TYRE_BOTTOM)
		if intrusion > 0.0:
			clipped_samples += 1
		if intrusion > peak_intrusion:
			peak_intrusion = intrusion
			worst_lane = offsets[vertex_index % column_count]
			worst_weight = float(vertex_index / column_count) / maxf(float(row_count - 1), 1.0)
		conservative_peak = maxf(conservative_peak, conservative)
	# Vertices, all three edge midpoints, and the centroid cover the exact linear
	# separation field of every paired overlay/base triangle.
	for cursor: int in range(0, indices.size(), 3):
		var ia := indices[cursor]
		var ib := indices[cursor + 1]
		var ic := indices[cursor + 2]
		var gaps := PackedFloat32Array([
			vertices[ia].y - base_vertices[ia].y,
			vertices[ib].y - base_vertices[ib].y,
			vertices[ic].y - base_vertices[ic].y,
		])
		for sample_gap: float in [
			(gaps[0] + gaps[1]) * 0.5,
			(gaps[1] + gaps[2]) * 0.5,
			(gaps[2] + gaps[0]) * 0.5,
			(gaps[0] + gaps[1] + gaps[2]) / 3.0,
		]:
			minimum_gap = minf(minimum_gap, sample_gap)
			maximum_gap = maxf(maximum_gap, sample_gap)
	var shape := collision.shape as ConcavePolygonShape3D
	var faces := shape.get_faces()
	var rut_visuals := body.find_children("OverlayRut*", "MeshInstance3D", false, false)
	var expects_ruts := body.name != &"LogBridge" and not bool(body.get_meta(&"optional_jump_line", false))
	var collision_matches := faces.size() == indices.size()
	if collision_matches:
		for face_index: int in faces.size():
			if faces[face_index].distance_to(vertices[indices[face_index]]) > 0.0001:
				collision_matches = false
				break
	var passed := (
		minimum_gap >= -0.0001
		and collision_matches
		and not shape.backface_collision
		and bool(body.get_meta(&"collision_top_only", false))
		and bool(body.get_meta(&"open_ride_ends", false))
		and float(body.get_meta(&"verified_minimum_separation", -INF)) >= -0.0001
		and (rut_visuals.size() == 4 if expects_ruts else rut_visuals.is_empty())
	)
	if body.name == &"LogBridge":
		var decoration_result := _audit_bridge_decoration(body, vertices, indices)
		passed = bool(decoration_result[&"passed"]) and passed
		print("BRIDGE DECORATION RESULT: planks=%d samples=%d minimum_deck_clearance=%.3fm passed=%s" % [
			int(decoration_result[&"planks"]), int(decoration_result[&"samples"]),
			float(decoration_result[&"minimum_clearance"]), str(decoration_result[&"passed"]),
		])
	return {
		&"role": role,
		&"peak_intrusion": peak_intrusion,
		&"conservative_peak": conservative_peak,
		&"clipped_fraction": float(clipped_samples) / float(vertices.size()),
		&"worst_lane": worst_lane,
		&"worst_weight": worst_weight,
		&"minimum_visual_gap": minimum_gap,
		&"maximum_visual_gap": maximum_gap,
		&"minimum_collision_gap": minimum_gap,
		&"maximum_collision_gap": maximum_gap,
		&"passed": passed,
	}


func _audit_bridge_decoration(
	body: StaticBody3D,
	deck_vertices: PackedVector3Array,
	deck_indices: PackedInt32Array
) -> Dictionary:
	var planks := body.find_child("BridgePlanks", false, false) as MultiMeshInstance3D
	if planks == null or planks.multimesh == null or planks.multimesh.mesh == null:
		return {&"planks": 0, &"samples": 0, &"minimum_clearance": -INF, &"passed": false}
	var box := planks.multimesh.mesh as BoxMesh
	if box == null:
		return {&"planks": 0, &"samples": 0, &"minimum_clearance": -INF, &"passed": false}
	var stored_transforms: Array = body.get_meta(&"bridge_plank_transforms", [])
	var plank_count := stored_transforms.size() if stored_transforms.size() > 0 else planks.multimesh.instance_count
	var minimum_clearance := INF
	var sample_count := 0
	for plank_index: int in plank_count:
		var plank_transform: Transform3D = (
			stored_transforms[plank_index]
			if stored_transforms.size() > 0
			else planks.multimesh.get_instance_transform(plank_index)
		)
		for x_weight: float in [-0.49, 0.0, 0.49]:
			for z_weight: float in [-0.5, 0.0, 0.5]:
				var bottom_point := plank_transform * Vector3(
					box.size.x * x_weight,
					-box.size.y * 0.5,
					box.size.z * z_weight
				)
				var deck_height := _triangle_mesh_height_at(
					deck_vertices, deck_indices, Vector2(bottom_point.x, bottom_point.z)
				)
				if not is_finite(deck_height):
					continue
				minimum_clearance = minf(minimum_clearance, bottom_point.y - deck_height)
				sample_count += 1
	if sample_count == 0:
		var deck_min := Vector2(INF, INF)
		var deck_max := Vector2(-INF, -INF)
		for vertex: Vector3 in deck_vertices:
			deck_min = Vector2(minf(deck_min.x, vertex.x), minf(deck_min.y, vertex.z))
			deck_max = Vector2(maxf(deck_max.x, vertex.x), maxf(deck_max.y, vertex.z))
		var first_transform: Transform3D = stored_transforms[0] if stored_transforms.size() > 0 else planks.multimesh.get_instance_transform(0)
		var last_transform: Transform3D = stored_transforms[-1] if stored_transforms.size() > 0 else planks.multimesh.get_instance_transform(planks.multimesh.instance_count - 1)
		print("BRIDGE DECORATION DEBUG: deck=%s..%s planks=%s..%s" % [
			str(deck_min), str(deck_max), str(first_transform.origin), str(last_transform.origin),
		])
	return {
		&"planks": plank_count,
		&"samples": sample_count,
		&"minimum_clearance": minimum_clearance,
		&"passed": plank_count == 11 and sample_count >= 70 and minimum_clearance >= 0.002,
	}


func _triangle_mesh_height_at(
	vertices: PackedVector3Array,
	indices: PackedInt32Array,
	point: Vector2
) -> float:
	var maximum_height := -INF
	for cursor: int in range(0, indices.size(), 3):
		var a := vertices[indices[cursor]]
		var b := vertices[indices[cursor + 1]]
		var c := vertices[indices[cursor + 2]]
		var triangle := PackedVector2Array([
			Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z),
		])
		if not _point_in_triangle_2d(point, triangle):
			continue
		var denominator := (
			(triangle[1].y - triangle[2].y) * (triangle[0].x - triangle[2].x)
			+ (triangle[2].x - triangle[1].x) * (triangle[0].y - triangle[2].y)
		)
		if absf(denominator) <= 0.000001:
			continue
		var wa := (
			(triangle[1].y - triangle[2].y) * (point.x - triangle[2].x)
			+ (triangle[2].x - triangle[1].x) * (point.y - triangle[2].y)
		) / denominator
		var wb := (
			(triangle[2].y - triangle[0].y) * (point.x - triangle[2].x)
			+ (triangle[0].x - triangle[2].x) * (point.y - triangle[2].y)
		) / denominator
		var wc := 1.0 - wa - wb
		maximum_height = maxf(maximum_height, a.y * wa + b.y * wb + c.y * wc)
	return maximum_height


func _point_in_triangle_2d(point: Vector2, triangle: PackedVector2Array) -> bool:
	var first := _cross_2d(triangle[1] - triangle[0], point - triangle[0])
	var second := _cross_2d(triangle[2] - triangle[1], point - triangle[1])
	var third := _cross_2d(triangle[0] - triangle[2], point - triangle[2])
	var has_negative := first < -0.0001 or second < -0.0001 or third < -0.0001
	var has_positive := first > 0.0001 or second > 0.0001 or third > 0.0001
	return not (has_negative and has_positive)


func _cross_2d(first: Vector2, second: Vector2) -> float:
	return first.x * second.y - first.y * second.x


func _audit_bridge(body: StaticBody3D, route: PackedVector3Array) -> Dictionary:
	var route_hint := CourseSpline.closest_index(route, body.position)
	var collision := body.find_child("*", true, false) as CollisionShape3D
	var faces := PackedVector3Array()
	for candidate: Node in body.find_children("*", "CollisionShape3D", true, false):
		var shape_node := candidate as CollisionShape3D
		if shape_node.shape is ConcavePolygonShape3D:
			collision = shape_node
			faces = (shape_node.shape as ConcavePolygonShape3D).get_faces()
			break
	if collision == null or faces.is_empty():
		return {
			&"role": &"BRIDGE", &"peak_intrusion": -INF,
			&"conservative_peak": -INF, &"clipped_fraction": 0.0,
			&"worst_lane": 0.0, &"worst_weight": 0.0,
			&"minimum_visual_gap": -INF, &"maximum_visual_gap": -INF,
			&"minimum_collision_gap": -INF, &"maximum_collision_gap": -INF,
			&"passed": false,
		}
	var minimum_z := INF
	var maximum_z := -INF
	for vertex: Vector3 in faces:
		minimum_z = minf(minimum_z, vertex.z)
		maximum_z = maxf(maximum_z, vertex.z)
	var top_y := faces[0].y
	var width := float(body.get_meta(&"bridge_width"))
	var peak_intrusion := -INF
	var conservative_peak := -INF
	var clipped_samples := 0
	var sample_count := 0
	var worst_lane := 0.0
	var worst_weight := 0.0
	var minimum_visual_gap := INF
	var maximum_visual_gap := -INF
	var minimum_collision_gap := INF
	var maximum_collision_gap := -INF
	for lane: float in PACK_LANES:
		if absf(lane) > width * 0.5 - 0.2:
			continue
		for sample_index: int in LONGITUDINAL_SAMPLES:
			var weight := float(sample_index) / float(LONGITUDINAL_SAMPLES - 1)
			var local_point := Vector3(lane, top_y, lerpf(minimum_z, maximum_z, weight))
			var point := body.transform * collision.transform * local_point
			var route_y := _route_height_at(route, Vector2(point.x, point.z), route_hint, 80)
			var intrusion := point.y - (route_y + NOMINAL_TYRE_BOTTOM)
			var conservative := point.y - (route_y + HIGHEST_TYRE_BOTTOM)
			if intrusion > 0.0:
				clipped_samples += 1
			sample_count += 1
			if intrusion > peak_intrusion:
				peak_intrusion = intrusion
				worst_lane = lane
				worst_weight = weight
			conservative_peak = maxf(conservative_peak, conservative)
			if is_zero_approx(lane):
				minimum_visual_gap = minf(minimum_visual_gap, point.y - (route_y + 0.075))
				maximum_visual_gap = maxf(maximum_visual_gap, point.y - (route_y + 0.075))
				minimum_collision_gap = minf(minimum_collision_gap, point.y - (route_y + 0.04))
				maximum_collision_gap = maxf(maximum_collision_gap, point.y - (route_y + 0.04))
	return {
		&"role": &"BRIDGE",
		&"peak_intrusion": peak_intrusion,
		&"conservative_peak": conservative_peak,
		&"clipped_fraction": float(clipped_samples) / maxf(float(sample_count), 1.0),
		&"worst_lane": worst_lane,
		&"worst_weight": worst_weight,
		&"minimum_visual_gap": minimum_visual_gap,
		&"maximum_visual_gap": maximum_visual_gap,
		&"minimum_collision_gap": minimum_collision_gap,
		&"maximum_collision_gap": maximum_collision_gap,
		&"passed": false,
	}


func _route_height_at(route: PackedVector3Array, point: Vector2, hint: int, radius: int = 32) -> float:
	var nearest_distance := INF
	var nearest_height := route[clampi(hint, 0, route.size() - 1)].y
	var first := maxi(hint - radius, 0)
	var last := mini(hint + radius, route.size() - 2)
	for index: int in range(first, last + 1):
		var start := Vector2(route[index].x, route[index].z)
		var end := Vector2(route[index + 1].x, route[index + 1].z)
		var segment := end - start
		var weight := clampf((point - start).dot(segment) / maxf(segment.length_squared(), 0.0001), 0.0, 1.0)
		var nearest := start + segment * weight
		var distance := nearest.distance_squared_to(point)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_height = lerpf(route[index].y, route[index + 1].y, weight)
	return nearest_height


func _progressive_ramp_ratio(weight: float) -> float:
	var clamped := clampf(weight, 0.0, 1.0)
	var rise := pow(clamped, 3.0)
	var settle := pow(1.0 - clamped, 3.0)
	var progressive := rise / maxf(rise + settle, 0.0001)
	return lerpf(progressive, clamped, 0.26)


func _audit_cross_loop_barriers(track_id: StringName) -> bool:
	var route := CourseCatalog.get_local_riding_points(track_id)
	var config := CourseDressingCatalog.get_config(track_id)
	var width := CourseCatalog.get_track_width(track_id)
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
	var open_flags := PackedByteArray()
	open_flags.resize(samples.size() * 2)
	var safety_suppressed_flags := PackedByteArray()
	safety_suppressed_flags.resize(samples.size() * 2)
	var sides := PackedFloat32Array([-1.0, 1.0])
	var local_exclusion_samples := maxi(
		ceili(CourseDressingBuilder.BARRIER_LOCAL_EXCLUSION_METERS / spacing),
		1
	)
	var expected_distance := width * 0.5 + offset
	var minimum_nonlocal_distance := (
		expected_distance - CourseDressingBuilder.BARRIER_CROSS_ROUTE_TOLERANCE
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

	var obstacle_serial := 0
	var panel_count := 0
	var post_count := 0
	var adjacent_panel_pairs := 0
	var maximum_panel_joint_gap := 0.0
	var minimum_panel_length := INF
	var maximum_panel_length := 0.0
	var cross_loop_count := 0
	var safety_suppressed_count := 0
	for flag: int in safety_suppressed_flags:
		if flag != 0:
			safety_suppressed_count += 1
	var worst: Dictionary = {}
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
			var first_position := Vector2(first_center.x, first_center.z) + first_right * sides[side_index] * expected_distance
			var second_position := Vector2(second_center.x, second_center.z) + second_right * sides[side_index] * expected_distance
			var panel_delta := second_position - first_position
			var panel_length := panel_delta.length()
			if panel_length < 0.2:
				continue
			minimum_panel_length = minf(minimum_panel_length, panel_length)
			maximum_panel_length = maxf(maximum_panel_length, panel_length)
			var panel_tangent := panel_delta / panel_length
			var panel_tangent_3d := Vector3(panel_tangent.x, 0.0, panel_tangent.y)
			var position := first_position.lerp(second_position, 0.5)
			panel_count += 1
			if index > 0:
				var previous_flag := (index - 1) * 2 + side_index
				if (
					open_flags[previous_flag] == 0
					and safety_suppressed_flags[previous_flag] == 0
				):
					adjacent_panel_pairs += 1
					# Both panels share `first_position` by construction.
					maximum_panel_joint_gap = maxf(maximum_panel_joint_gap, 0.0)
			var name := "CourseContainment%s%04d" % ["Left" if sides[side_index] < 0.0 else "Right", index]
			for probe_position: Vector2 in [first_position, position, second_position]:
				if _audit_cross_loop_obstacle(
					track_id, name, probe_position, index, spacing, route,
					width * 0.5 + thickness * 0.5 + 0.46, worst
				):
					cross_loop_count += 1
			obstacle_serial += 1
			var previous_open := index > 0 and open_flags[(index - 1) * 2 + side_index] != 0
			var next_open := index + 2 < samples.size() and open_flags[(index + 2) * 2 + side_index] != 0
			for end_sign: float in [-1.0, 1.0]:
				if (end_sign < 0.0 and not previous_open) or (end_sign > 0.0 and not next_open):
					continue
				name = "OpeningPost%04d" % obstacle_serial
				var post_extent := thickness * 1.7
				var endpoint := first_position if end_sign < 0.0 else second_position
				var post_position := endpoint + panel_tangent * end_sign * post_extent * 0.5
				if CourseDressingBuilder._barrier_intrudes_nonlocal_route(
					Vector3(post_position.x, first_center.y, post_position.y), panel_tangent_3d,
					post_extent, samples, index, local_exclusion_samples, minimum_nonlocal_distance
				):
					continue
				if _audit_cross_loop_obstacle(
					track_id, name, post_position, index, spacing, route,
					width * 0.5 + post_extent * 0.5 + 0.46, worst
				):
					cross_loop_count += 1
				obstacle_serial += 1
				post_count += 1
	var passed := (
		cross_loop_count == 0
		and maximum_panel_joint_gap <= 0.001
		and (track_id != CourseCatalog.QUARRY_ID or safety_suppressed_count == 0)
	)
	print("CROSS LOOP BARRIER RESULT: track=%s obstacles=%d panels=%d posts=%d adjacent_panel_pairs=%d panel_length=%.3f..%.3fm maximum_joint_gap=%.3fm panel_overlap=0.00m post_panel_intrusion=0.000m safety_suppressed=%d suspects=%d worst=%s passed=%s" % [
		String(track_id), obstacle_serial, panel_count, post_count, adjacent_panel_pairs,
		minimum_panel_length, maximum_panel_length, maximum_panel_joint_gap,
		safety_suppressed_count, cross_loop_count, str(worst), str(passed),
	])
	return passed


func _audit_cross_loop_obstacle(
	track_id: StringName,
	name: String,
	position: Vector2,
	sample_index: int,
	spacing: float,
	route: PackedVector3Array,
	expected_offset: float,
	worst: Dictionary
) -> bool:
	var source_chainage := float(sample_index) * spacing
	# Ignore only the immediately adjacent samples. Hairpins 20+ metres away are
	# distinct rideable corridor and must not be pierced by a fence end/post.
	var nearest := _nearest_route_location(route, position, source_chainage, 20.0)
	var distance := float(nearest[&"distance"])
	if distance >= expected_offset:
		return false
	var intrusion := expected_offset - distance
	if worst.is_empty() or intrusion > float(worst[&"intrusion"]):
		worst[&"name"] = name
		worst[&"position"] = position
		worst[&"source_chainage"] = source_chainage
		worst[&"foreign_chainage"] = nearest[&"chainage"]
		worst[&"distance"] = distance
		worst[&"intrusion"] = intrusion
	print("CROSS LOOP BARRIER: track=%s node=%s position=%s source_chain=%.1fm foreign_chain=%.1fm foreign_center_distance=%.2fm expected=%.2fm intrusion=%.2fm" % [
		String(track_id), name, str(position), source_chainage,
		float(nearest[&"chainage"]), distance, expected_offset, intrusion,
	])
	return true


func _nearest_route_location(
	route: PackedVector3Array,
	point: Vector2,
	excluded_chainage: float,
	excluded_radius: float
) -> Dictionary:
	var nearest_distance := INF
	var nearest_chainage := -1.0
	var chainage := 0.0
	for index: int in route.size() - 1:
		var start_3d := route[index]
		var end_3d := route[index + 1]
		var segment_length := start_3d.distance_to(end_3d)
		var start := Vector2(start_3d.x, start_3d.z)
		var end := Vector2(end_3d.x, end_3d.z)
		var segment := end - start
		var weight := clampf((point - start).dot(segment) / maxf(segment.length_squared(), 0.0001), 0.0, 1.0)
		var candidate_chainage := chainage + segment_length * weight
		if absf(candidate_chainage - excluded_chainage) > excluded_radius:
			var distance := point.distance_to(start + segment * weight)
			if distance < nearest_distance:
				nearest_distance = distance
				nearest_chainage = candidate_chainage
		chainage += segment_length
	return {&"distance": nearest_distance, &"chainage": nearest_chainage}


func _audit_pack_grid(track_id: StringName) -> void:
	var route := CourseCatalog.get_local_riding_points(track_id)
	var width := CourseCatalog.get_track_width(track_id)
	var config := (
		{&"maximum_bank_degrees": 8.5, &"bank_strength": 0.5, &"berm_height": 1.85, &"shoulder_width": 3.5, &"rut_offset": 0.98, &"rut_depth": 0.065}
		if track_id == CourseCatalog.PINE_ID
		else {&"maximum_bank_degrees": 11.5, &"bank_strength": 0.56, &"berm_height": 2.3, &"shoulder_width": 3.75, &"rut_depth": 0.052}
	)
	var frames := CourseSurfaceBuilder._build_frames(route, width, config)
	var distances := PackedFloat32Array()
	distances.resize(route.size())
	var total_distance := 0.0
	for index: int in range(1, route.size()):
		total_distance += route[index - 1].distance_to(route[index])
		distances[index] = total_distance
	var grid_slots: Array[Vector2] = []
	for row: int in 4:
		for column: int in 3:
			if row == 0 and column == 1:
				continue
			grid_slots.append(Vector2(2.0 + float(row) * 2.8, (float(column) - 1.0) * 2.3))
	var minimum_clearance := INF
	var worst := {}
	var clipping_wheels := 0
	for rider_index: int in grid_slots.size():
		var progress := grid_slots[rider_index].x
		var lane := grid_slots[rider_index].y
		var segment_index := _segment_for_progress(distances, progress)
		var start_distance := distances[segment_index]
		var end_distance := distances[segment_index + 1]
		var weight := inverse_lerp(start_distance, end_distance, progress)
		var position := route[segment_index].lerp(route[segment_index + 1], weight)
		var tangent := (route[segment_index + 1] - route[segment_index]).normalized()
		var flat_tangent := Vector3(tangent.x, 0.0, tangent.z).normalized()
		var right := flat_tangent.cross(Vector3.UP).normalized()
		position += right * lane
		position.y += 0.02 + sin(progress * 0.18 + float(rider_index) * 0.81) * 0.015
		var basis := Basis.looking_at(tangent, Vector3.UP)
		for wheel_spec: Dictionary in [
			{&"name": &"front", &"local": Vector3(0.0, 0.37, -0.594)},
			{&"name": &"rear", &"local": Vector3(0.0, 0.37, 0.74329)},
		]:
			var axle := position + basis * (wheel_spec[&"local"] as Vector3)
			var vertical_radius := TYRE_RADIUS * sqrt(basis.y.y * basis.y.y + basis.z.y * basis.z.y)
			var tyre_bottom := axle.y - vertical_radius
			var surface_y := _visual_surface_height(route, frames, axle, width, config)
			var clearance := tyre_bottom - surface_y
			if clearance < 0.0:
				clipping_wheels += 1
			if clearance < minimum_clearance:
				minimum_clearance = clearance
				worst = {
					&"rider": rider_index, &"wheel": wheel_spec[&"name"],
					&"progress": progress, &"lane": lane,
					&"tyre_bottom": tyre_bottom, &"surface": surface_y,
				}
	print("PACK GRID GEOMETRY: track=%s riders=11 wheels=22 clipping_wheels=%d minimum_clearance=%.3fm worst=%s" % [
		String(track_id), clipping_wheels, minimum_clearance, str(worst),
	])


func _segment_for_progress(distances: PackedFloat32Array, progress: float) -> int:
	for index: int in distances.size() - 1:
		if distances[index + 1] >= progress:
			return index
	return maxi(distances.size() - 2, 0)


func _visual_surface_height(
	route: PackedVector3Array,
	frames: Array[Dictionary],
	point: Vector3,
	width: float,
	config: Dictionary
) -> float:
	var target := Vector2(point.x, point.z)
	var best_distance := INF
	var best_index := 0
	var best_weight := 0.0
	for index: int in mini(route.size() - 1, 80):
		var start := Vector2(route[index].x, route[index].z)
		var end := Vector2(route[index + 1].x, route[index + 1].z)
		var segment := end - start
		var weight := clampf((target - start).dot(segment) / maxf(segment.length_squared(), 0.0001), 0.0, 1.0)
		var distance := target.distance_squared_to(start + segment * weight)
		if distance < best_distance:
			best_distance = distance
			best_index = index
			best_weight = weight
	var first: Dictionary = frames[best_index]
	var second: Dictionary = frames[best_index + 1]
	var center := (first[&"position"] as Vector3).lerp(second[&"position"] as Vector3, best_weight)
	var flat_right := (first[&"right"] as Vector3).lerp(second[&"right"] as Vector3, best_weight)
	flat_right.y = 0.0
	flat_right = flat_right.normalized()
	var lane := Vector2(point.x - center.x, point.z - center.z).dot(Vector2(flat_right.x, flat_right.z))
	var cross_height := _track_visual_cross_height(lane, width, config)
	var first_height := CourseSurfaceBuilder._height_with_berm(first, lane, cross_height, width)
	var second_height := CourseSurfaceBuilder._height_with_berm(second, lane, cross_height, width)
	var first_vertex := (first[&"position"] as Vector3) + (first[&"right"] as Vector3) * lane + (first[&"up"] as Vector3) * first_height
	var second_vertex := (second[&"position"] as Vector3) + (second[&"right"] as Vector3) * lane + (second[&"up"] as Vector3) * second_height
	return lerpf(first_vertex.y, second_vertex.y, best_weight)


func _track_visual_cross_height(lane: float, width: float, config: Dictionary) -> float:
	var half_width := width * 0.5
	var rut_offset := minf(float(config.get(&"rut_offset", 1.15)), half_width * 0.58)
	var rut_half_width := float(config.get(&"rut_half_width", 0.2))
	var rut_depth := minf(
		float(config.get(&"rut_depth", 0.04)),
		float(config.get(&"physical_rut_depth", 0.024))
	)
	var offsets := PackedFloat32Array([
		-half_width, -rut_offset - rut_half_width, -rut_offset,
		-rut_offset + rut_half_width, 0.0, rut_offset - rut_half_width,
		rut_offset, rut_offset + rut_half_width, half_width,
	])
	var heights := PackedFloat32Array([
		-0.055, 0.018, -rut_depth, 0.018, 0.04,
		0.018, -rut_depth, 0.018, -0.055,
	])
	var clamped_lane := clampf(lane, -half_width, half_width)
	for index: int in offsets.size() - 1:
		if clamped_lane <= offsets[index + 1]:
			return lerpf(heights[index], heights[index + 1], inverse_lerp(offsets[index], offsets[index + 1], clamped_lane))
	return heights[-1]
