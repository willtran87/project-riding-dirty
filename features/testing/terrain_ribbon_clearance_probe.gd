extends Node
## Exact deterministic audit for generated terrain intruding through rideable ribbons.
##
## This constructs only the production terrain and course-ribbon subsystems. It
## then intersects the real terrain and rideable-collision triangles in the XZ
## plane and evaluates every overlap-polygon vertex. The visual ribbon is checked
## independently at every real vertex, edge midpoint, and triangle centroid, and
## the terrain's visual mesh is required to match its collision faces exactly.
## Jump and bridge overlays are deliberately not treated as terrain support:
## their underlying base ribbon is audited normally.

const PineBuilderScript = preload("res://levels/pine_ridge/pine_ridge_builder.gd")
const QuarryBuilderScript = preload("res://levels/quarry/quarry_builder.gd")

const MINIMUM_CLEARANCE_METERS: float = 0.08
const GEOMETRY_EPSILON: float = 0.0001
const HEIGHT_EPSILON: float = 0.0005
const QUARRY_APPROACH_START_RATIO: float = 0.89
const QUARRY_APPROACH_END_RATIO: float = 0.96
const MAXIMUM_APPROACH_TERRAIN_SLOPE: float = 1.0
const QUARRY_MAIN_SHOULDER_WIDTH: float = 3.75
const QUARRY_BOULDER_ROUTE_BUFFER: float = 2.0
const FORBIDDEN_QUARRY_SLAB_NAMES := [
	&"NorthMesa", &"EastMesa", &"SouthMesa", &"WestMesa",
	&"NorthTerrace", &"EastTerrace", &"SouthTerrace", &"WestTerrace",
]


func _ready() -> void:
	var started_usec := Time.get_ticks_usec()
	var passed := true
	passed = _audit_track(CourseCatalog.QUARRY_ID) and passed
	passed = _audit_track(CourseCatalog.PINE_ID) and passed
	var runtime_seconds := float(Time.get_ticks_usec() - started_usec) / 1_000_000.0
	print("TERRAIN RIBBON CLEARANCE SUMMARY: runtime=%.3fs minimum_required=%.3fm passed=%s" % [
		runtime_seconds, MINIMUM_CLEARANCE_METERS, str(passed),
	])
	get_tree().quit(0 if passed else 1)


func _audit_track(track_id: StringName) -> bool:
	var track_started_usec := Time.get_ticks_usec()
	var builder := _construct_geometry(track_id)
	var construction_seconds := float(Time.get_ticks_usec() - track_started_usec) / 1_000_000.0
	if builder == null:
		push_error("TERRAIN CLEARANCE SETUP FAILED: track=%s" % String(track_id))
		return false

	var terrain_name := "GeneratedPineTerrain" if track_id == CourseCatalog.PINE_ID else "GeneratedQuarryTerrain"
	var terrain_collision_name := "%sCollision" % terrain_name
	var terrain_visual := builder.find_child(terrain_name, true, false) as MeshInstance3D
	var terrain_body := builder.find_child(terrain_collision_name, true, false) as StaticBody3D
	if terrain_visual == null or terrain_body == null:
		push_error("TERRAIN CLEARANCE MISSING GENERATED TERRAIN: track=%s visual=%s collision=%s" % [
			String(track_id), str(terrain_visual != null), str(terrain_body != null),
		])
		builder.free()
		return false

	var grid := _terrain_grid_from_visual(terrain_visual)
	var mesh_matches_collision := _terrain_mesh_matches_collision(terrain_visual, terrain_body)
	if grid.is_empty():
		push_error("TERRAIN CLEARANCE INVALID GRID: track=%s" % String(track_id))
		builder.free()
		return false

	var routes := _route_specs(builder, track_id)
	var audit_started_usec := Time.get_ticks_usec()
	var track_minimum := INF
	var track_worst: Dictionary = {}
	var total_source_triangles := 0
	var total_overlap_vertices := 0
	var total_visual_samples := 0
	var routes_passed := true
	for route_spec: Dictionary in routes:
		var result := _audit_route(builder, grid, route_spec)
		total_source_triangles += int(result.get(&"source_triangles", 0))
		total_overlap_vertices += int(result.get(&"overlap_vertices", 0))
		total_visual_samples += int(result.get(&"visual_samples", 0))
		var clearance := float(result.get(&"minimum_clearance", -INF))
		if clearance < track_minimum:
			track_minimum = clearance
			track_worst = result.duplicate()
		var route_passed := bool(result.get(&"passed", false))
		routes_passed = routes_passed and route_passed
		print("TERRAIN RIBBON ROUTE: track=%s route=%s collision_triangles=%d overlap_vertices=%d visual_samples=%d minimum_clearance=%.3fm surface=%s chainage=%.1fm lane=%+.2fm passed=%s" % [
			String(track_id), String(route_spec[&"label"]), int(result.get(&"source_triangles", 0)),
			int(result.get(&"overlap_vertices", 0)), int(result.get(&"visual_samples", 0)), clearance,
			String(result.get(&"surface", &"none")), float(result.get(&"chainage", -1.0)),
			float(result.get(&"lane", 0.0)), str(route_passed),
		])

	var approach_passed := true
	if track_id == CourseCatalog.QUARRY_ID:
		var approach_result := _audit_quarry_finish_approach(grid, builder)
		var runoff_result := _audit_quarry_finish_runoff(builder, grid)
		var slab_result := _audit_removed_quarry_slabs(builder)
		var boulder_result := _audit_quarry_boundary_boulders(builder)
		approach_passed = (
			bool(approach_result[&"passed"])
			and bool(runoff_result[&"passed"])
			and bool(slab_result[&"passed"])
			and bool(boulder_result[&"passed"])
		)
		print("QUARRY FINISH APPROACH TERRAIN: maximum_near_slope=%.3f maximum_off_route_height_above_eye=%.3fm near_point=%s sight_point=%s passed=%s" % [
			float(approach_result[&"maximum_near_slope"]),
			float(approach_result[&"maximum_off_route_height_above_eye"]),
			str(approach_result[&"near_point"]), str(approach_result[&"sight_point"]),
			str(approach_passed),
		])
		print("QUARRY FINISH RUNOFF: length=%.1fm east_clearance=%.1fm south_clearance=%.1fm end_tangent=%s passed=%s" % [
			float(runoff_result[&"length"]), float(runoff_result[&"east_clearance"]),
			float(runoff_result[&"south_clearance"]), str(runoff_result[&"end_tangent"]),
			str(runoff_result[&"passed"]),
		])
		print("QUARRY REMOVED SLAB BLOCKERS: ground_built=%s forbidden_found=%s passed=%s" % [
			str(slab_result[&"ground_built"]), str(slab_result[&"found"]),
			str(slab_result[&"passed"]),
		])
		print("QUARRY BOUNDARY BOULDER CLEARANCE: physical=%d visual=%d uninspectable=%d minimum_recovery_clearance=%.3fm required=%.3fm worst=%s passed=%s" % [
			int(boulder_result[&"physical_count"]), int(boulder_result[&"visual_count"]),
			int(boulder_result[&"uninspectable_count"]),
			float(boulder_result[&"minimum_recovery_clearance"]),
			float(boulder_result[&"required_recovery_clearance"]),
			String(boulder_result[&"worst"]), str(boulder_result[&"passed"]),
		])
	var required_route_count := 3 if track_id == CourseCatalog.PINE_ID else 1
	var passed := mesh_matches_collision and routes_passed and routes.size() == required_route_count and approach_passed
	var audit_seconds := float(Time.get_ticks_usec() - audit_started_usec) / 1_000_000.0
	print("TERRAIN RIBBON CLEARANCE RESULT: track=%s routes=%d collision_triangles=%d overlap_vertices=%d visual_samples=%d worst_clearance=%.3fm route=%s surface=%s chainage=%.1fm lane=%+.2fm construction=%.3fs audit=%.3fs terrain_visual_collision_match=%s full_ribbon_and_shoulders=true overlays_ignored=true passed=%s" % [
		String(track_id), routes.size(), total_source_triangles, total_overlap_vertices, total_visual_samples, track_minimum,
		String(track_worst.get(&"route", &"none")), String(track_worst.get(&"surface", &"none")),
		float(track_worst.get(&"chainage", -1.0)), float(track_worst.get(&"lane", 0.0)),
		construction_seconds, audit_seconds, str(mesh_matches_collision), str(passed),
	])
	builder.free()
	return passed


func _audit_removed_quarry_slabs(builder: Node3D) -> Dictionary:
	var found := PackedStringArray()
	for slab_name: StringName in FORBIDDEN_QUARRY_SLAB_NAMES:
		if builder.find_child(String(slab_name), true, false) != null:
			found.append(String(slab_name))
	# This witness makes the check fail closed if the lightweight probe ever
	# stops constructing the production ground-and-wall subsystem altogether.
	var ground_built := (
		builder.find_child("QuarryCatchFloor", true, false) != null
		and builder.find_child("QuarryFreestylePad", true, false) != null
	)
	return {
		&"ground_built": ground_built,
		&"found": found,
		&"passed": ground_built and found.is_empty(),
	}


func _audit_quarry_boundary_boulders(builder: Node3D) -> Dictionary:
	var race_route: PackedVector3Array = builder.get("_ride_points")
	var apron_route: PackedVector3Array = builder.get("_finish_apron_points")
	var track_width := float(builder.get("_track_width"))
	var race_outer_half_width := track_width * 0.5 + QUARRY_MAIN_SHOULDER_WIDTH
	var apron_outer_half_width := track_width * 0.5 + QUARRY_MAIN_SHOULDER_WIDTH
	var physical_count := 0
	var visual_count := 0
	var uninspectable_count := 0
	var minimum_recovery_clearance := INF
	var worst := &"none"

	for child: Node in builder.get_children():
		if not child is StaticBody3D or not child.name.begins_with("Boulder"):
			continue
		var body := child as StaticBody3D
		physical_count += 1
		var radius := -1.0
		for descendant: Node in body.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := descendant as MeshInstance3D
			if mesh_instance.mesh is SphereMesh:
				radius = (mesh_instance.mesh as SphereMesh).radius
				break
		if radius <= 0.0:
			uninspectable_count += 1
			continue
		var result := _minimum_boulder_recovery_clearance(
			Vector2(body.position.x, body.position.z),
			radius,
			race_route,
			race_outer_half_width,
			apron_route,
			apron_outer_half_width
		)
		if float(result[&"clearance"]) < minimum_recovery_clearance:
			minimum_recovery_clearance = float(result[&"clearance"])
			worst = StringName("physical:%s:%s" % [body.name, String(result[&"path"])])

	var visual_transforms: Array = builder.get("_visual_boulder_transforms")
	for index: int in visual_transforms.size():
		var boulder_transform: Transform3D = visual_transforms[index]
		var scale := boulder_transform.basis.get_scale()
		var radius := maxf(absf(scale.x), maxf(absf(scale.y), absf(scale.z)))
		var center := boulder_transform.origin
		visual_count += 1
		var result := _minimum_boulder_recovery_clearance(
			Vector2(center.x, center.z),
			radius,
			race_route,
			race_outer_half_width,
			apron_route,
			apron_outer_half_width
		)
		if float(result[&"clearance"]) < minimum_recovery_clearance:
			minimum_recovery_clearance = float(result[&"clearance"])
			worst = StringName("visual:%02d:%s" % [index, String(result[&"path"])])

	var has_witnesses := (
		physical_count > 0
		and visual_count > 0
		and minimum_recovery_clearance < INF
		and uninspectable_count == 0
	)
	return {
		&"physical_count": physical_count,
		&"visual_count": visual_count,
		&"uninspectable_count": uninspectable_count,
		&"minimum_recovery_clearance": minimum_recovery_clearance,
		&"required_recovery_clearance": QUARRY_BOULDER_ROUTE_BUFFER,
		&"worst": worst,
		&"passed": (
			has_witnesses
			and minimum_recovery_clearance + GEOMETRY_EPSILON >= QUARRY_BOULDER_ROUTE_BUFFER
		),
	}


func _minimum_boulder_recovery_clearance(
	point: Vector2,
	radius: float,
	race_route: PackedVector3Array,
	race_outer_half_width: float,
	apron_route: PackedVector3Array,
	apron_outer_half_width: float
) -> Dictionary:
	var race_location := _route_location(race_route, point)
	var apron_location := _route_location(apron_route, point)
	var race_clearance := float(race_location[&"distance"]) - radius - race_outer_half_width
	var apron_clearance := float(apron_location[&"distance"]) - radius - apron_outer_half_width
	if race_clearance <= apron_clearance:
		return {&"clearance": race_clearance, &"path": &"race"}
	return {&"clearance": apron_clearance, &"path": &"apron"}


func _audit_quarry_finish_approach(grid: Dictionary, builder: Node3D) -> Dictionary:
	# Guard the lower return line against the old nearest-XZ failure where a
	# nearby upper course pass pulled a 40 m wall directly against the shoulder.
	var route: PackedVector3Array = builder.get("_ride_points")
	var outer_half_width := CourseCatalog.get_track_width(CourseCatalog.QUARRY_ID) * 0.5 + 3.75
	var first_index := floori((route.size() - 1) * QUARRY_APPROACH_START_RATIO)
	var last_index := ceili((route.size() - 1) * QUARRY_APPROACH_END_RATIO)
	var maximum_near_slope := 0.0
	var maximum_off_route_height_above_eye := -INF
	var near_point := Vector3.ZERO
	var sight_point := Vector3.ZERO
	for index: int in range(first_index, last_index + 1, 3):
		var center := route[index]
		var tangent_3d := CourseSpline.tangent_at(route, index)
		var tangent := Vector2(tangent_3d.x, tangent_3d.z).normalized()
		var right := Vector2(-tangent.y, tangent.x)
		for side: float in [-1.0, 1.0]:
			for beyond_shoulder: float in [0.0, 6.0, 12.0]:
				var start_2d := Vector2(center.x, center.z) + right * side * (outer_half_width + beyond_shoulder)
				var finish_2d := start_2d + right * side * 12.0
				var rise := _terrain_height_at_grid(finish_2d, grid) - _terrain_height_at_grid(start_2d, grid)
				var slope := rise / 12.0
				if slope > maximum_near_slope:
					maximum_near_slope = slope
					near_point = Vector3(finish_2d.x, _terrain_height_at_grid(finish_2d, grid), finish_2d.y)
		for forward_distance: float in range(30, 91, 6):
			var sample_2d := Vector2(center.x, center.z) + tangent * forward_distance
			var route_location := _route_location(route, sample_2d)
			if float(route_location[&"distance"]) <= outer_half_width + 6.0:
				continue
			var above_eye := _terrain_height_at_grid(sample_2d, grid) - (center.y + 2.4)
			if above_eye > maximum_off_route_height_above_eye:
				maximum_off_route_height_above_eye = above_eye
				sight_point = Vector3(sample_2d.x, _terrain_height_at_grid(sample_2d, grid), sample_2d.y)
	return {
		&"maximum_near_slope": maximum_near_slope,
		&"maximum_off_route_height_above_eye": maximum_off_route_height_above_eye,
		&"near_point": near_point,
		&"sight_point": sight_point,
		&"passed": maximum_near_slope <= MAXIMUM_APPROACH_TERRAIN_SLOPE and maximum_off_route_height_above_eye <= 0.0,
	}


func _audit_quarry_finish_runoff(builder: Node3D, grid: Dictionary) -> Dictionary:
	var race_route: PackedVector3Array = builder.get("_ride_points")
	var surface_route: PackedVector3Array = builder.get("_surface_ride_points")
	var apron_route: PackedVector3Array = builder.get("_finish_apron_points")
	if race_route.is_empty() or surface_route.is_empty() or apron_route.size() < 2:
		return {
			&"length": 0.0, &"east_clearance": -INF, &"south_clearance": -INF,
			&"end_tangent": Vector3.ZERO, &"passed": false,
		}
	var runoff_length := 0.0
	var maximum_x := -INF
	var maximum_z := -INF
	for index: int in apron_route.size():
		maximum_x = maxf(maximum_x, apron_route[index].x)
		maximum_z = maxf(maximum_z, apron_route[index].z)
		if index > 0:
			runoff_length += apron_route[index - 1].distance_to(apron_route[index])
	var end_tangent := CourseSpline.tangent_at(apron_route, apron_route.size() - 1)
	var flat_tangent := Vector3(end_tangent.x, 0.0, end_tangent.z).normalized()
	var lateral := flat_tangent.cross(Vector3.UP).normalized()
	var grid_origin: Vector2 = grid[&"origin"]
	var grid_step: Vector2 = grid[&"step"]
	var terrain_maximum := grid_origin + Vector2(
		grid_step.x * float(int(grid[&"columns"]) - 1),
		grid_step.y * float(int(grid[&"rows"]) - 1)
	)
	var east_clearance := terrain_maximum.x - (maximum_x + absf(lateral.x) * 14.0)
	var south_clearance := terrain_maximum.y - (maximum_z + absf(lateral.z) * 14.0)
	var official_surface_matches_race := surface_route.size() == race_route.size()
	var main_ribbon := builder.find_child("QuarryRaceRibbon", true, false) as Node3D
	var catch_pad := builder.find_child("FinishCatchPad", true, false) as Node3D
	var stop_barrier := builder.find_child("FinishStopBarrier", true, false)
	var joins_finish := apron_route[0].distance_to(race_route[-1]) <= 0.001
	var expected_collision_points := surface_route.size() + apron_route.size() - 1
	var main_collision_shapes: Array[Node] = []
	if main_ribbon != null:
		main_collision_shapes = main_ribbon.find_children("*", "CollisionShape3D", true, false)
	var pad_is_aligned := (
		catch_pad != null
		and bool(catch_pad.get_meta(&"finish_safety_apron", false))
		and main_ribbon != null
		and main_collision_shapes.size() == 1
		and bool(main_ribbon.get_meta(&"welded_collision", false))
		and int(main_ribbon.get_meta(&"visual_centerline_size", 0)) == expected_collision_points
		and int(main_ribbon.get_meta(&"collision_centerline_size", 0)) == expected_collision_points
	)
	return {
		&"length": runoff_length,
		&"east_clearance": east_clearance,
		&"south_clearance": south_clearance,
		&"end_tangent": end_tangent,
		&"passed": (
			official_surface_matches_race
			and joins_finish
			and runoff_length >= 30.0
			and runoff_length <= 36.0
			and east_clearance >= 8.0
			and south_clearance >= 4.0
			and pad_is_aligned
			and stop_barrier != null
		),
	}


func _construct_geometry(track_id: StringName) -> Node3D:
	var builder: Node3D
	if track_id == CourseCatalog.PINE_ID:
		builder = PineBuilderScript.new()
	else:
		builder = QuarryBuilderScript.new()
	builder.set("_track_points", CourseCatalog.get_local_points(track_id))
	builder.set("_ride_points", CourseCatalog.get_local_riding_points(track_id))
	builder.set("_track_width", CourseCatalog.get_track_width(track_id))
	var alternate_ride_trails: Array = builder.get("_alternate_ride_trails")
	alternate_ride_trails.clear()
	var bake_step := 2.4 if track_id == CourseCatalog.PINE_ID else 2.5
	var roller_spacing := 1.35 if track_id == CourseCatalog.PINE_ID else 1.6
	var roller_height := 0.22 if track_id == CourseCatalog.PINE_ID else 0.26
	var seed_base := 42017 + 47 if track_id == CourseCatalog.PINE_ID else 1987 + 31
	var seed_stride := 19 if track_id == CourseCatalog.PINE_ID else 17
	var alternate_trails: Array = builder.get("_alternate_trails")
	for index: int in alternate_trails.size():
		alternate_ride_trails.append(CourseSpline.bake_motocross(
			alternate_trails[index], bake_step, roller_spacing, roller_height,
			seed_base + index * seed_stride
		))
	if builder.has_method("_build_terrain_surface_profiles"):
		builder.set("_terrain_surface_profiles", builder.call("_build_terrain_surface_profiles"))
	builder.call("_configure_terrain_noise", builder.get("_terrain_noise"))
	_install_probe_materials(builder, track_id)
	if track_id == CourseCatalog.QUARRY_ID:
		# Construct the same coarse ground/scenery subsystem as production so this
		# probe catches any return of the named Mesa/Terrace collision slabs.
		builder.call("_build_ground_and_walls")
	builder.call("_start_terrain_build")
	if track_id == CourseCatalog.PINE_ID:
		builder.call("_build_trail")
	else:
		builder.call("_build_track")
	return builder


func _install_probe_materials(builder: Node3D, track_id: StringName) -> void:
	# Geometry generation only reads these material slots. Plain resources avoid
	# spending probe time baking decorative procedural textures.
	var materials: Dictionary = builder.get("_materials")
	var keys: Array[StringName]
	if track_id == CourseCatalog.PINE_ID:
		keys = [&"terrain", &"trail", &"trail_edge", &"rut"]
	else:
		keys = [
			&"terrain", &"ground", &"track", &"track_edge", &"rut", &"runoff",
			&"red", &"cream", &"cliff", &"cliff_dark", &"rock",
		]
	for key: StringName in keys:
		materials[key] = StandardMaterial3D.new()


func _route_specs(builder: Node3D, track_id: StringName) -> Array[Dictionary]:
	var specs: Array[Dictionary] = []
	var main_name := "PineEnduroRibbon" if track_id == CourseCatalog.PINE_ID else "QuarryRaceRibbon"
	var main_route: PackedVector3Array = builder.get("_ride_points")
	if track_id == CourseCatalog.QUARRY_ID:
		var quarry_surface_route: PackedVector3Array = builder.get("_surface_ride_points")
		if not quarry_surface_route.is_empty():
			main_route = quarry_surface_route
	specs.append({
		&"label": &"main",
		&"root_name": main_name,
		&"route": main_route.duplicate(),
	})
	var alternate_prefix := "PineAlternate" if track_id == CourseCatalog.PINE_ID else "QuarryAlternate"
	var alternate_ride_trails: Array = builder.get("_alternate_ride_trails")
	for index: int in alternate_ride_trails.size():
		var alternate_route: PackedVector3Array = alternate_ride_trails[index]
		specs.append({
			&"label": StringName("alternate_%d" % index),
			&"root_name": "%s%02d" % [alternate_prefix, index],
			&"route": alternate_route.duplicate(),
		})
	return specs


func _terrain_grid_from_visual(visual: MeshInstance3D) -> Dictionary:
	if visual.mesh == null or visual.mesh.get_surface_count() != 1:
		return {}
	var arrays := visual.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if vertices.size() < 4:
		return {}
	var columns := 1
	var first_z := vertices[0].z
	while columns < vertices.size() and absf(vertices[columns].z - first_z) <= GEOMETRY_EPSILON:
		columns += 1
	if columns < 2 or vertices.size() % columns != 0:
		return {}
	var rows := int(vertices.size() / columns)
	if rows < 2:
		return {}
	var step_x := vertices[1].x - vertices[0].x
	var step_z := vertices[columns].z - vertices[0].z
	if step_x <= 0.0 or step_z <= 0.0:
		return {}
	return {
		&"vertices": vertices,
		&"columns": columns,
		&"rows": rows,
		&"origin": Vector2(vertices[0].x, vertices[0].z),
		&"step": Vector2(step_x, step_z),
	}


func _terrain_mesh_matches_collision(visual: MeshInstance3D, body: StaticBody3D) -> bool:
	var arrays := visual.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var collisions := body.find_children("*", "CollisionShape3D", true, false)
	if collisions.size() != 1:
		print("TERRAIN VISUAL/COLLISION MISMATCH: collision_shape_count=%d" % collisions.size())
		return false
	var collision := collisions[0] as CollisionShape3D
	if collision.shape == null or not collision.shape is ConcavePolygonShape3D:
		print("TERRAIN VISUAL/COLLISION MISMATCH: shape_is_concave=false")
		return false
	var faces := (collision.shape as ConcavePolygonShape3D).get_faces()
	if faces.size() != indices.size():
		print("TERRAIN VISUAL/COLLISION MISMATCH: visual_indices=%d collision_vertices=%d" % [indices.size(), faces.size()])
		return false
	for index: int in faces.size():
		if faces[index].distance_to(vertices[indices[index]]) > HEIGHT_EPSILON:
			print("TERRAIN VISUAL/COLLISION MISMATCH: face_index=%d visual=%s collision=%s" % [
				index, str(vertices[indices[index]]), str(faces[index]),
			])
			return false
	return true


func _audit_route(builder: Node3D, grid: Dictionary, route_spec: Dictionary) -> Dictionary:
	var ribbon_root := builder.find_child(String(route_spec[&"root_name"]), true, false) as Node3D
	if ribbon_root == null:
		return {
			&"route": route_spec[&"label"], &"minimum_clearance": -INF,
			&"source_triangles": 0, &"overlap_vertices": 0, &"passed": false,
		}
	var result := {
		&"route": route_spec[&"label"],
		&"minimum_clearance": INF,
		&"point": Vector2.ZERO,
		&"surface": &"none",
		&"source_triangles": 0,
		&"overlap_vertices": 0,
		&"visual_samples": 0,
	}
	var visual_nodes := ribbon_root.find_children("*", "MeshInstance3D", true, false)
	for node: Node in visual_nodes:
		var visual := node as MeshInstance3D
		if visual.name != &"RaceSurface" and visual.name != &"LeftShoulder" and visual.name != &"RightShoulder":
			continue
		var surface_label := StringName("visual_%s" % String(visual.name).to_snake_case())
		_sample_visual_mesh(visual, builder, grid, surface_label, result)
	var collision_nodes := ribbon_root.find_children("*", "CollisionShape3D", true, false)
	for node: Node in collision_nodes:
		var collision := node as CollisionShape3D
		if collision.shape is ConcavePolygonShape3D:
			_audit_faces(
				(collision.shape as ConcavePolygonShape3D).get_faces(),
				_transform_to_ancestor(collision, builder), grid, &"collision", result
			)
	var route: PackedVector3Array = route_spec[&"route"]
	var worst_point: Vector2 = result[&"point"]
	var location := _route_location(route, worst_point)
	result[&"chainage"] = location[&"chainage"]
	result[&"lane"] = location[&"lane"]
	result[&"passed"] = (
		int(result[&"source_triangles"]) > 0
		and int(result[&"overlap_vertices"]) > 0
		and int(result[&"visual_samples"]) > 0
		and float(result[&"minimum_clearance"]) >= MINIMUM_CLEARANCE_METERS
	)
	return result


func _sample_visual_mesh(
	visual: MeshInstance3D,
	ancestor: Node3D,
	grid: Dictionary,
	surface_label: StringName,
	result: Dictionary
) -> void:
	if visual.mesh == null:
		return
	var transform := _transform_to_ancestor(visual, ancestor)
	for surface: int in visual.mesh.get_surface_count():
		var arrays := visual.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			indices.resize(vertices.size())
			for index: int in indices.size():
				indices[index] = index
		var transformed := PackedVector3Array()
		transformed.resize(vertices.size())
		for index: int in vertices.size():
			transformed[index] = transform * vertices[index]
			_record_grid_clearance(transformed[index], grid, surface_label, result)
		for face_index: int in range(0, indices.size() - 2, 3):
			var a := transformed[indices[face_index]]
			var b := transformed[indices[face_index + 1]]
			var c := transformed[indices[face_index + 2]]
			_record_grid_clearance(a.lerp(b, 0.5), grid, surface_label, result)
			_record_grid_clearance(b.lerp(c, 0.5), grid, surface_label, result)
			_record_grid_clearance(c.lerp(a, 0.5), grid, surface_label, result)
			_record_grid_clearance((a + b + c) / 3.0, grid, surface_label, result)


func _record_grid_clearance(
	point: Vector3,
	grid: Dictionary,
	surface_label: StringName,
	result: Dictionary
) -> void:
	var terrain_height := _terrain_height_at_grid(Vector2(point.x, point.z), grid)
	var clearance := point.y - terrain_height
	result[&"visual_samples"] = int(result[&"visual_samples"]) + 1
	if clearance < float(result[&"minimum_clearance"]):
		result[&"minimum_clearance"] = clearance
		result[&"point"] = Vector2(point.x, point.z)
		result[&"surface"] = surface_label


func _terrain_height_at_grid(point: Vector2, grid: Dictionary) -> float:
	var vertices: PackedVector3Array = grid[&"vertices"]
	var columns: int = grid[&"columns"]
	var rows: int = grid[&"rows"]
	var origin: Vector2 = grid[&"origin"]
	var step: Vector2 = grid[&"step"]
	var column := clampi(int(floor((point.x - origin.x) / step.x)), 0, columns - 2)
	var row := clampi(int(floor((point.y - origin.y) / step.y)), 0, rows - 2)
	var local_x := clampf((point.x - (origin.x + column * step.x)) / step.x, 0.0, 1.0)
	var local_z := clampf((point.y - (origin.y + row * step.y)) / step.y, 0.0, 1.0)
	var top_left := row * columns + column
	var terrain_height: float
	if local_x + local_z <= 1.0:
		var a := vertices[top_left]
		var b := vertices[top_left + 1]
		var c := vertices[top_left + columns]
		terrain_height = a.y + (b.y - a.y) * local_x + (c.y - a.y) * local_z
	else:
		var a := vertices[top_left + columns + 1]
		var b := vertices[top_left + columns]
		var c := vertices[top_left + 1]
		terrain_height = a.y + (b.y - a.y) * (1.0 - local_x) + (c.y - a.y) * (1.0 - local_z)
	return terrain_height


func _audit_faces(
	faces: PackedVector3Array,
	transform: Transform3D,
	grid: Dictionary,
	surface_label: StringName,
	result: Dictionary
) -> void:
	for face_index: int in range(0, faces.size() - 2, 3):
		var triangle := PackedVector3Array([
			transform * faces[face_index],
			transform * faces[face_index + 1],
			transform * faces[face_index + 2],
		])
		if absf(_triangle_area_xz(triangle)) <= GEOMETRY_EPSILON:
			continue
		result[&"source_triangles"] = int(result[&"source_triangles"]) + 1
		_audit_triangle_against_grid(triangle, grid, surface_label, result)


func _audit_triangle_against_grid(
	ribbon: PackedVector3Array,
	grid: Dictionary,
	surface_label: StringName,
	result: Dictionary
) -> void:
	var vertices: PackedVector3Array = grid[&"vertices"]
	var columns: int = grid[&"columns"]
	var rows: int = grid[&"rows"]
	var origin: Vector2 = grid[&"origin"]
	var step: Vector2 = grid[&"step"]
	var minimum_x := minf(ribbon[0].x, minf(ribbon[1].x, ribbon[2].x))
	var maximum_x := maxf(ribbon[0].x, maxf(ribbon[1].x, ribbon[2].x))
	var minimum_z := minf(ribbon[0].z, minf(ribbon[1].z, ribbon[2].z))
	var maximum_z := maxf(ribbon[0].z, maxf(ribbon[1].z, ribbon[2].z))
	var first_column := clampi(int(floor((minimum_x - origin.x) / step.x)), 0, columns - 2)
	var last_column := clampi(int(floor((maximum_x - origin.x) / step.x)), 0, columns - 2)
	var first_row := clampi(int(floor((minimum_z - origin.y) / step.y)), 0, rows - 2)
	var last_row := clampi(int(floor((maximum_z - origin.y) / step.y)), 0, rows - 2)
	for row: int in range(first_row, last_row + 1):
		for column: int in range(first_column, last_column + 1):
			var top_left := row * columns + column
			var terrain_a := PackedVector3Array([
				vertices[top_left], vertices[top_left + 1], vertices[top_left + columns],
			])
			var terrain_b := PackedVector3Array([
				vertices[top_left + 1], vertices[top_left + columns + 1], vertices[top_left + columns],
			])
			_audit_triangle_pair(ribbon, terrain_a, surface_label, result)
			_audit_triangle_pair(ribbon, terrain_b, surface_label, result)


func _audit_triangle_pair(
	ribbon: PackedVector3Array,
	terrain: PackedVector3Array,
	surface_label: StringName,
	result: Dictionary
) -> void:
	var ribbon_2d := PackedVector2Array([
		Vector2(ribbon[0].x, ribbon[0].z), Vector2(ribbon[1].x, ribbon[1].z), Vector2(ribbon[2].x, ribbon[2].z),
	])
	var terrain_2d := PackedVector2Array([
		Vector2(terrain[0].x, terrain[0].z), Vector2(terrain[1].x, terrain[1].z), Vector2(terrain[2].x, terrain[2].z),
	])
	for point: Vector2 in ribbon_2d:
		if _point_in_triangle(point, terrain_2d):
			_record_clearance(point, ribbon, terrain, surface_label, result)
	for point: Vector2 in terrain_2d:
		if _point_in_triangle(point, ribbon_2d):
			_record_clearance(point, ribbon, terrain, surface_label, result)
	for ribbon_edge: int in 3:
		var ribbon_start := ribbon_2d[ribbon_edge]
		var ribbon_end := ribbon_2d[(ribbon_edge + 1) % 3]
		for terrain_edge: int in 3:
			var intersection := _segment_intersection(
				ribbon_start, ribbon_end,
				terrain_2d[terrain_edge], terrain_2d[(terrain_edge + 1) % 3]
			)
			if bool(intersection[&"hit"]):
				_record_clearance(intersection[&"point"], ribbon, terrain, surface_label, result)


func _record_clearance(
	point: Vector2,
	ribbon: PackedVector3Array,
	terrain: PackedVector3Array,
	surface_label: StringName,
	result: Dictionary
) -> void:
	var ribbon_height := _height_on_triangle(point, ribbon)
	var terrain_height := _height_on_triangle(point, terrain)
	var clearance := ribbon_height - terrain_height
	result[&"overlap_vertices"] = int(result[&"overlap_vertices"]) + 1
	if clearance < float(result[&"minimum_clearance"]):
		result[&"minimum_clearance"] = clearance
		result[&"point"] = point
		result[&"surface"] = surface_label


func _point_in_triangle(point: Vector2, triangle: PackedVector2Array) -> bool:
	var a := _cross_2d(triangle[1] - triangle[0], point - triangle[0])
	var b := _cross_2d(triangle[2] - triangle[1], point - triangle[1])
	var c := _cross_2d(triangle[0] - triangle[2], point - triangle[2])
	var has_negative := a < -GEOMETRY_EPSILON or b < -GEOMETRY_EPSILON or c < -GEOMETRY_EPSILON
	var has_positive := a > GEOMETRY_EPSILON or b > GEOMETRY_EPSILON or c > GEOMETRY_EPSILON
	return not (has_negative and has_positive)


func _segment_intersection(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> Dictionary:
	var r := b - a
	var s := d - c
	var denominator := _cross_2d(r, s)
	if absf(denominator) <= GEOMETRY_EPSILON:
		return {&"hit": false}
	var offset := c - a
	var along_a := _cross_2d(offset, s) / denominator
	var along_c := _cross_2d(offset, r) / denominator
	if along_a < -GEOMETRY_EPSILON or along_a > 1.0 + GEOMETRY_EPSILON:
		return {&"hit": false}
	if along_c < -GEOMETRY_EPSILON or along_c > 1.0 + GEOMETRY_EPSILON:
		return {&"hit": false}
	return {&"hit": true, &"point": a + r * clampf(along_a, 0.0, 1.0)}


func _height_on_triangle(point: Vector2, triangle: PackedVector3Array) -> float:
	var a := Vector2(triangle[0].x, triangle[0].z)
	var b := Vector2(triangle[1].x, triangle[1].z)
	var c := Vector2(triangle[2].x, triangle[2].z)
	var denominator := _cross_2d(b - a, c - a)
	if absf(denominator) <= GEOMETRY_EPSILON:
		return triangle[0].y
	var weight_b := _cross_2d(point - a, c - a) / denominator
	var weight_c := _cross_2d(b - a, point - a) / denominator
	return triangle[0].y + (triangle[1].y - triangle[0].y) * weight_b + (triangle[2].y - triangle[0].y) * weight_c


func _triangle_area_xz(triangle: PackedVector3Array) -> float:
	return _cross_2d(
		Vector2(triangle[1].x - triangle[0].x, triangle[1].z - triangle[0].z),
		Vector2(triangle[2].x - triangle[0].x, triangle[2].z - triangle[0].z)
	)


func _cross_2d(a: Vector2, b: Vector2) -> float:
	return a.x * b.y - a.y * b.x


func _transform_to_ancestor(node: Node3D, ancestor: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != ancestor:
		if current is Node3D:
			result = (current as Node3D).transform * result
		current = current.get_parent()
	return result


func _route_location(route: PackedVector3Array, point: Vector2) -> Dictionary:
	var nearest_distance := INF
	var nearest_chainage := 0.0
	var nearest_lane := 0.0
	var chainage := 0.0
	for index: int in route.size() - 1:
		var start_3d := route[index]
		var finish_3d := route[index + 1]
		var start := Vector2(start_3d.x, start_3d.z)
		var finish := Vector2(finish_3d.x, finish_3d.z)
		var segment := finish - start
		var segment_length := segment.length()
		if segment_length <= GEOMETRY_EPSILON:
			continue
		var weight := clampf((point - start).dot(segment) / segment.length_squared(), 0.0, 1.0)
		var nearest := start + segment * weight
		var distance := point.distance_to(nearest)
		if distance < nearest_distance:
			var tangent := segment / segment_length
			var right := Vector2(-tangent.y, tangent.x)
			nearest_distance = distance
			nearest_chainage = chainage + segment_length * weight
			nearest_lane = (point - nearest).dot(right)
		chainage += segment_length
	return {&"chainage": nearest_chainage, &"lane": nearest_lane, &"distance": nearest_distance}
