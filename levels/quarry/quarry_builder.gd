extends Node3D
## Deterministic, asset-free vertical-slice quarry assembled from game-ready primitives.

const SurfaceTextureFactory = preload("res://features/environment/procedural_surface_texture.gd")

const TERRAIN_SIZE := Vector2(840.0, 1360.0)
const TERRAIN_STEP: float = 12.0
const TERRAIN_SEED: int = 1987
const TRACK_THICKNESS: float = 0.36
const MAIN_SHOULDER_WIDTH: float = 3.75
const BOUNDARY_BOULDER_ROUTE_BUFFER: float = 2.0
const TERRAIN_SURFACE_GAP: float = 0.34
const TERRAIN_CELL_DIAGONAL: float = 16.97056275
const TERRAIN_PROFILE_QUERY_SPACING: float = 8.0

var _track_points := PackedVector3Array()
var _ride_points := PackedVector3Array()
var _surface_ride_points := PackedVector3Array()
var _finish_apron_points := PackedVector3Array()
var _track_width: float = 24.0
var _alternate_trails: Array[PackedVector3Array] = []
var _alternate_ride_trails: Array[PackedVector3Array] = []
var _main_route_surface: Node3D
var _materials: Dictionary[StringName, StandardMaterial3D] = {}
var _terrain_noise := FastNoiseLite.new()
var _marker_transforms: Array[Transform3D] = []
var _visual_boulder_transforms: Array[Transform3D] = []
var _terrain_query_paths: Array[PackedVector3Array] = []
var _terrain_surface_profiles: Array[Dictionary] = []


func _ready() -> void:
	var profile_build := OS.get_environment("RIDING_DIRTY_PROFILE_QUARRY") == "1"
	var phase_begin_usec := Time.get_ticks_usec()
	_track_points = CourseCatalog.get_local_points(CourseCatalog.QUARRY_ID)
	_ride_points = CourseCatalog.get_local_riding_points(CourseCatalog.QUARRY_ID)
	_surface_ride_points = _build_surface_ride_points(_ride_points)
	_finish_apron_points = _build_finish_apron_points(_ride_points)
	_track_width = CourseCatalog.get_track_width(CourseCatalog.QUARRY_ID)
	# Quarry Trail is a single readable race line. The former narrow alternates
	# looked like compulsory forks from riding height, then appeared to terminate
	# in terrain beneath the course's elevated switchbacks.
	_alternate_trails.clear()
	_alternate_ride_trails.clear()
	for index: int in _alternate_trails.size():
		_alternate_ride_trails.append(CourseSpline.bake_motocross(
			_alternate_trails[index], 2.5, 1.6, 0.26, TERRAIN_SEED + 31 + index * 17
		))
	phase_begin_usec = _finish_profiled_phase(&"catalog_and_route", phase_begin_usec, profile_build)
	_terrain_surface_profiles = _build_terrain_surface_profiles()
	phase_begin_usec = _finish_profiled_phase(&"terrain_profiles", phase_begin_usec, profile_build)
	_configure_terrain_noise(_terrain_noise)
	_create_materials()
	phase_begin_usec = _finish_profiled_phase(&"materials", phase_begin_usec, profile_build)
	_build_environment()
	_build_ground_and_walls()
	phase_begin_usec = _finish_profiled_phase(&"environment_and_ground", phase_begin_usec, profile_build)
	_start_terrain_build()
	phase_begin_usec = _finish_profiled_phase(&"terrain", phase_begin_usec, profile_build)
	_build_track()
	phase_begin_usec = _finish_profiled_phase(&"track", phase_begin_usec, profile_build)
	_build_jump_line()
	phase_begin_usec = _finish_profiled_phase(&"jumps", phase_begin_usec, profile_build)
	_build_quarry_props()
	_build_course_markers()
	_build_trackside_life()
	_flush_visual_boulders()
	phase_begin_usec = _finish_profiled_phase(&"props_markers_life", phase_begin_usec, profile_build)
	CourseDressingBuilder.build(
		self,
		CourseCatalog.QUARRY_ID,
		_surface_centerline(),
		_track_width,
		Callable(self, &"_terrain_height_at"),
		[_finish_apron_centerline()]
	)
	_finish_profiled_phase(&"course_dressing", phase_begin_usec, profile_build)


func _finish_profiled_phase(phase: StringName, begin_usec: int, enabled: bool) -> int:
	var finish_usec := Time.get_ticks_usec()
	if enabled:
		print("QUARRY BUILD PHASE: %s %.3fs" % [
			String(phase), float(finish_usec - begin_usec) / 1_000_000.0,
		])
	return finish_usec


func get_authoritative_route_world() -> PackedVector3Array:
	var world_route := _surface_centerline().duplicate()
	for index: int in world_route.size():
		world_route[index] = to_global(world_route[index])
	return world_route


func _create_materials() -> void:
	_materials[&"ground"] = _material(Color("594033"), 0.96)
	_materials[&"terrain"] = _material(Color("624431"), 1.0)
	_materials[&"track"] = _material(Color("35261f"), 1.0)
	_materials[&"rut"] = _material(Color("281b18"), 1.0)
	_materials[&"track_edge"] = _material(Color("806a54"), 0.94)
	# A muted gravel tone separates the post-finish braking pad from the dark
	# timed ribbon without turning it into a bright wall-like visual mass.
	_materials[&"runoff"] = _material(Color("52463e"), 1.0)
	_materials[&"cliff"] = _material(Color("8d5c3d"), 0.94)
	_materials[&"cliff_dark"] = _material(Color("593728"), 0.97)
	_materials[&"rock"] = _material(Color("4c4541"), 0.98)
	_materials[&"metal"] = _material(Color("333b3f"), 0.38, 0.64)
	_materials[&"yellow"] = _material(Color("e8a62a"), 0.5, 0.12)
	_materials[&"red"] = _material(Color("c84434"), 0.48, 0.08)
	_materials[&"cream"] = _material(Color("f0d58b"), 0.7)
	_materials[&"tire"] = _material(Color("16191b"), 0.98)
	_materials[&"scrub"] = _material(Color("71824a"), 0.95)
	SurfaceTextureFactory.apply(
		_materials[&"track"],
		PackedColorArray([Color("201613"), Color("39271f"), Color("60432f"), Color("2d1f19")]),
		TERRAIN_SEED + 11,
		0.024,
		0.86
	)
	SurfaceTextureFactory.apply(
		_materials[&"track_edge"],
		# Pale compacted shoulders separate the dark racing line the way a
		# groomed club-motocross circuit reads at speed.
		PackedColorArray([Color("5f5447"), Color("82715b"), Color("a08a6b")]),
		TERRAIN_SEED + 19,
		0.032,
		0.74
	)
	SurfaceTextureFactory.apply(
		_materials[&"runoff"],
		PackedColorArray([Color("332d2a"), Color("4b403a"), Color("655548"), Color("3e3631")]),
		TERRAIN_SEED + 21,
		0.045,
		0.82
	)
	SurfaceTextureFactory.apply(
		_materials[&"terrain"],
		PackedColorArray([Color("473126"), Color("654633"), Color("86583d"), Color("54382b")]),
		TERRAIN_SEED + 23,
		0.018,
		0.68
	)


func _build_environment() -> void:
	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	var environment := Environment.new()
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("0c3d66")
	sky_material.sky_horizon_color = Color("d5a073")
	sky_material.ground_bottom_color = Color("30231e")
	sky_material.ground_horizon_color = Color("905237")
	sky_material.sky_curve = 0.11
	sky_material.ground_curve = 0.09
	sky_material.sky_energy_multiplier = 1.08
	sky_material.ground_energy_multiplier = 0.62
	sky_material.sun_angle_max = 16.0
	sky_material.sun_curve = 0.075
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("516d7b")
	environment.ambient_light_energy = 0.38
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.02
	environment.fog_enabled = true
	environment.fog_light_color = Color("c29b80")
	environment.fog_light_energy = 0.22
	environment.fog_density = 0.00095
	environment.fog_height = -2.0
	environment.fog_height_density = 0.055
	environment.fog_sky_affect = 0.18
	world_environment.environment = environment
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-43.0, -48.0, 0.0)
	sun.light_color = Color("ffc57f")
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_max_distance = 460.0
	add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.name = "SkyFill"
	fill.rotation_degrees = Vector3(42.0, 140.0, 0.0)
	fill.light_color = Color("547894")
	fill.light_energy = 0.18
	fill.shadow_enabled = false
	add_child(fill)


func _build_ground_and_walls() -> void:
	# Continuous bedrock closes the district beneath the sculpted surface and the
	# freestyle pad. It is usually hidden, but any seam remains solid ground.
	var catch_floor := _add_static_box(
		"QuarryCatchFloor",
		Vector3(TERRAIN_SIZE.x + 120.0, 1.0, TERRAIN_SIZE.y + 120.0),
		Vector3(0.0, -1.0, 0.0),
		&"ground"
	)
	_tag_surface(catch_floor, &"HARDPACK", 0.92, 0.42)
	# Preserve the original central freestyle bowl while the race trail climbs around it.
	var freestyle_pad := _add_static_box("QuarryFreestylePad", Vector3(168.0, 0.6, 168.0), Vector3(0.0, -0.3, 0.0), &"track")
	_tag_surface(freestyle_pad, &"DIRT", 0.78, 1.08)

	# The generated terrain closes the entire expanded district around the long
	# post-gate-8 descent. Former hard-coded Mesa/Terrace boxes ignored the route
	# envelope and read as walls across the road. Keep the quarry boundary
	# terrain-shaped and obstacle-free.

	var rng := RandomNumberGenerator.new()
	rng.seed = 1987
	var half_terrain_x := TERRAIN_SIZE.x * 0.5
	var half_terrain_z := TERRAIN_SIZE.y * 0.5
	for index: int in 72:
		var side := index % 4
		var position := Vector3.ZERO
		match side:
			0:
				position = Vector3(
					rng.randf_range(-half_terrain_x + 25.0, half_terrain_x - 25.0),
					0.0,
					rng.randf_range(-half_terrain_z + 8.0, -half_terrain_z + 24.0)
				)
			1:
				position = Vector3(
					rng.randf_range(half_terrain_x - 18.0, half_terrain_x - 4.0),
					0.0,
					rng.randf_range(-half_terrain_z + 24.0, half_terrain_z - 24.0)
				)
			2:
				position = Vector3(
					rng.randf_range(-half_terrain_x + 25.0, half_terrain_x - 25.0),
					0.0,
					rng.randf_range(half_terrain_z - 24.0, half_terrain_z - 8.0)
				)
			_:
				position = Vector3(
					rng.randf_range(-half_terrain_x + 4.0, -half_terrain_x + 18.0),
					0.0,
					rng.randf_range(-half_terrain_z + 24.0, half_terrain_z - 24.0)
				)
		position.y = _terrain_height_at(position.x, position.z)
		if _inside_finish_safety_zone(position):
			continue
		var radius := rng.randf_range(0.7, 2.4)
		if not _boundary_boulder_clears_route(position, radius):
			continue
		_add_boulder("Boulder%02d" % index, position, radius, index % 6 == 0)


func _boundary_boulder_clears_route(position: Vector3, radius: float) -> bool:
	if _ride_points.size() < 2 or _finish_apron_points.size() < 2:
		return false
	return (
		_boulder_clears_path(
			position,
			radius,
			_ride_points,
			_track_width * 0.5 + MAIN_SHOULDER_WIDTH + BOUNDARY_BOULDER_ROUTE_BUFFER
		)
		and _boulder_clears_path(
			position,
			radius,
			_finish_apron_points,
			_track_width * 0.5 + MAIN_SHOULDER_WIDTH + BOUNDARY_BOULDER_ROUTE_BUFFER
		)
	)


func _boulder_clears_path(
	position: Vector3,
	radius: float,
	path: PackedVector3Array,
	required_edge_clearance: float
) -> bool:
	var point := Vector2(position.x, position.z)
	var required_centerline_distance := required_edge_clearance + radius
	var required_distance_squared := required_centerline_distance * required_centerline_distance
	for index: int in path.size() - 1:
		var start_3d := path[index]
		var finish_3d := path[index + 1]
		var start := Vector2(start_3d.x, start_3d.z)
		var segment := Vector2(finish_3d.x, finish_3d.z) - start
		var weight := clampf(
			(point - start).dot(segment) / maxf(segment.length_squared(), 0.001),
			0.0,
			1.0
		)
		if point.distance_squared_to(start + segment * weight) <= required_distance_squared:
			return false
	return true


func _inside_finish_safety_zone(position: Vector3) -> bool:
	var apron := _finish_apron_centerline()
	if apron.size() < 2:
		return false
	var forward := (apron[-1] - apron[0]).normalized()
	var right := forward.cross(Vector3.UP).normalized()
	var relative := position - apron[0]
	var along := relative.dot(forward)
	var lateral := absf(relative.dot(right))
	return along >= -4.0 and along <= apron[0].distance_to(apron[-1]) + 4.0 and lateral <= 19.0


func _build_track() -> void:
	# Carry one visual and physical ribbon through the timed finish and the entire
	# braking lane. Separate meshes sharing the finish row created both a dark
	# wall-like joint and an internal Jolt edge that could snag a wheel.
	var main_surface_config := _main_surface_config()
	var stitched_surface := _stitched_collision_centerline()
	_main_route_surface = CourseSurfaceBuilder.build(
		self,
		"QuarryRaceRibbon",
		stitched_surface,
		_track_width,
		_materials[&"track"],
		_materials[&"track_edge"],
		_materials[&"rut"],
		&"DIRT",
		0.8,
		1.22,
		main_surface_config
	)
	_mark_authoritative_track_surface(_main_route_surface, CourseCatalog.QUARRY_ID)
	_main_route_surface.set_meta(&"single_layer_race_surface", true)
	_main_route_surface.set_meta(
		&"welded_jump_package_count",
		CourseCatalog.get_welded_jump_zones(CourseCatalog.QUARRY_ID).size()
	)
	_build_finish_catch_pad()
	_build_finish_gate()
	# Narrow, more technical alternates stay between the same required gates.
	for index: int in _alternate_ride_trails.size():
		CourseSurfaceBuilder.build(
			self,
			"QuarryAlternate%02d" % index,
			_alternate_ride_trails[index],
			5.8,
			_materials[&"track"],
			_materials[&"track_edge"],
			_materials[&"rut"],
			&"DIRT",
			0.9,
			1.3,
			_alternate_surface_config()
		)


func _build_surface_ride_points(race_points: PackedVector3Array) -> PackedVector3Array:
	# Keep checkpoint, barrier, minimap, and timing data on the official route.
	# `_stitched_collision_centerline()` extends this centerline through the
	# braking apron when it builds the one continuous visual/physical ribbon.
	return race_points.duplicate()


func _build_finish_apron_points(race_points: PackedVector3Array) -> PackedVector3Array:
	if race_points.size() < 2:
		return PackedVector3Array()
	var finish := race_points[-1]
	var forward := CourseSpline.tangent_at(race_points, race_points.size() - 1)
	# Carry the incoming downhill grade through the safety lane. Clamp only the
	# extremes: forcing a steeper minimum fall created a visible/physical pitch
	# change at the finish even after the ribbon topology was welded.
	forward.y = clampf(forward.y, -0.045, -0.012)
	forward = forward.normalized()
	var apron := PackedVector3Array()
	for distance: int in 33:
		apron.append(finish + forward * float(distance))
	return apron


func _surface_centerline() -> PackedVector3Array:
	if _surface_ride_points.is_empty():
		_surface_ride_points = _build_surface_ride_points(_ride_points)
	return _surface_ride_points


func _stitched_collision_centerline() -> PackedVector3Array:
	var stitched := _surface_centerline().duplicate()
	var apron := _finish_apron_centerline()
	# Both paths deliberately share the timed-finish point. Append from index one
	# so the collision topology contains a single row there, not coincident edges.
	for index: int in range(1, apron.size()):
		stitched.append(apron[index])
	return stitched


func _finish_apron_centerline() -> PackedVector3Array:
	if _finish_apron_points.is_empty():
		_finish_apron_points = _build_finish_apron_points(_ride_points)
	return _finish_apron_points


func _main_surface_config() -> Dictionary:
	return {
		&"maximum_bank_degrees": 11.5,
		&"bank_strength": 0.56,
		# The old 2.3 m outside berm could merge with a full-width jump silhouette
		# and read as the road entering a wall. This still catches a sliding bike
		# while keeping the next barrier and road edge visible from rider height.
		&"berm_height": 1.55,
		&"shoulder_width": MAIN_SHOULDER_WIDTH,
		&"rut_depth": 0.052,
		&"casts_shadow": false,
	}


func _alternate_surface_config() -> Dictionary:
	return {
		&"maximum_bank_degrees": 12.5,
		&"bank_strength": 0.62,
		&"berm_height": 1.7,
		&"shoulder_width": 1.45,
		&"rut_offset": 0.82,
		&"rut_depth": 0.06,
		&"endpoint_taper_length": 10.0,
		&"endpoint_minimum_width_ratio": 0.06,
		&"endpoint_surface_lift": 0.055,
		&"casts_shadow": false,
	}


func _build_finish_catch_pad() -> void:
	var apron := _finish_apron_centerline()
	if apron.size() < 2:
		return
	var finish := apron[0]
	var forward := (apron[-1] - apron[0]).normalized()
	var pad_length := apron[0].distance_to(apron[-1])
	var basis := Basis.looking_at(forward, Vector3.UP)
	# QuarryRaceRibbon already owns the rendered and collidable apron. Keep a
	# semantic marker for validation and safety-zone discovery without adding a
	# second surface at the join.
	var pad := Node3D.new()
	pad.name = "FinishCatchPad"
	add_child(pad)
	pad.set_meta(&"finish_safety_apron", true)

	var stop := StaticBody3D.new()
	stop.name = "FinishStopBarrier"
	stop.collision_layer = 2
	stop.collision_mask = 1
	stop.transform = Transform3D(basis, finish + forward * pad_length + Vector3.UP * 0.72)
	_tag_surface(stop, &"BARRIER", 0.98, 0.0)
	add_child(stop)
	var stop_shape := BoxShape3D.new()
	stop_shape.size = Vector3(_track_width, 1.45, 0.72)
	var stop_collision := CollisionShape3D.new()
	stop_collision.shape = stop_shape
	stop.add_child(stop_collision)
	var panel_width := _track_width / 10.0
	for index: int in 10:
		var panel := BoxMesh.new()
		panel.size = Vector3(panel_width, 1.45, 0.72)
		panel.material = _materials[&"red"] if index % 2 == 0 else _materials[&"cliff_dark"]
		var panel_mesh := MeshInstance3D.new()
		panel_mesh.name = "StopPanel%02d" % index
		panel_mesh.mesh = panel
		panel_mesh.position.x = -_track_width * 0.5 + panel_width * 0.5 + float(index) * panel_width
		stop.add_child(panel_mesh)


func _build_finish_gate() -> void:
	if _ride_points.size() < 2:
		return
	var finish := _ride_points[-1]
	var forward := CourseSpline.tangent_at(_ride_points, _ride_points.size() - 1)
	forward.y = 0.0
	forward = forward.normalized()
	var root := Node3D.new()
	root.name = "QuarryFinishGate"
	root.transform = Transform3D(Basis.looking_at(forward, Vector3.UP), finish)
	add_child(root)
	_finish_gate_box(root, "LeftPost", Vector3(0.42, 6.2, 0.42), Vector3(-13.2, 3.1, 0.0), _materials[&"red"])
	_finish_gate_box(root, "RightPost", Vector3(0.42, 6.2, 0.42), Vector3(13.2, 3.1, 0.0), _materials[&"cream"])
	for index: int in 10:
		var material: Material = _materials[&"cream"] if index % 2 == 0 else _materials[&"cliff_dark"]
		_finish_gate_box(
			root, "FinishBar%02d" % index, Vector3(2.64, 0.62, 0.5),
			Vector3(-11.88 + float(index) * 2.64, 6.05, 0.0), material
		)


func _finish_gate_box(parent: Node3D, node_name: String, size: Vector3, position: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = position
	parent.add_child(instance)


func _build_jump_line() -> void:
	# All seven official race-line jump packages are now authored directly into
	# CourseCatalog's centerline. Do not add a second road-shaped body here: the
	# old 22-23 m overlays visually erased the 24 m ribbon and created a different
	# support surface for the physical player than for the opponent pack.
	# The central quarry remains a dedicated freestyle playground.
	_add_wedge_ramp("NorthTakeoff", Vector3(0.0, 0.04, -3.0), 0.0, 16.0, 9.5, 4.6, true)
	_add_wedge_ramp("NorthLanding", Vector3(0.0, 0.04, -27.0), 0.0, 17.0, 10.5, 3.2, false)
	_add_wedge_ramp("EastTableFace", Vector3(54.0, 0.04, 12.0), PI, 8.0, 8.0, 1.65, true)
	_add_static_box("EastTableTop", Vector3(8.0, 1.65, 7.0), Vector3(54.0, 0.825, 19.2), &"track")
	_add_wedge_ramp("EastTableDown", Vector3(54.0, 0.04, 26.5), PI, 8.0, 8.0, 1.65, false)
	_add_wedge_ramp("PipeCutSend", Vector3(-12.0, 0.04, -12.5), -0.9, 7.5, 5.8, 2.35, true)
	_add_wedge_ramp("HighLineKick", Vector3(38.0, 0.04, -27.0), -0.58, 7.0, 5.8, 2.15, true)


func _build_quarry_props() -> void:
	# Stylized excavator landmark on the high quarry bench.
	# Keep the landmark outside the race corridor so it reads as scenery rather
	# than becoming an accidental chicane.
	var excavator_anchor := Vector3(-247.0, 0.0, -99.0)
	var excavator_ground := _terrain_height_at(excavator_anchor.x, excavator_anchor.z)
	_add_static_box("ExcavatorDeck", Vector3(7.2, 1.0, 3.7), excavator_anchor + Vector3(0.0, excavator_ground + 0.5, 0.0), &"yellow")
	_add_visual_box("ExcavatorCab", Vector3(2.5, 2.8, 2.5), excavator_anchor + Vector3(-1.5, excavator_ground + 2.2, 0.0), &"yellow")
	_add_visual_box("ExcavatorWindow", Vector3(2.0, 1.4, 0.08), excavator_anchor + Vector3(-1.5, excavator_ground + 2.55, 1.28), &"metal")
	_add_visual_box("ExcavatorBoom", Vector3(0.65, 0.65, 10.0), excavator_anchor + Vector3(4.0, excavator_ground + 3.1, 4.0), &"yellow", Vector3(-0.35, -0.62, 0.0))
	_add_visual_box("ExcavatorArm", Vector3(0.58, 0.58, 7.0), excavator_anchor + Vector3(10.0, excavator_ground + 0.9, 9.5), &"yellow", Vector3(0.5, -0.78, 0.0))
	var excavator_detail_root := Node3D.new()
	excavator_detail_root.name = "ExcavatorDetail"
	excavator_detail_root.position = excavator_anchor + Vector3.UP * excavator_ground
	add_child(excavator_detail_root)
	var roller_transforms: Array[Transform3D] = []
	for side: float in [-1.0, 1.0]:
		for roller_index: int in 5:
			var basis := Basis.from_euler(Vector3(PI * 0.5, 0.0, 0.0)) * Basis.from_scale(Vector3(0.68, 0.5, 0.68))
			roller_transforms.append(Transform3D(basis, Vector3(-3.0 + roller_index * 1.45, -0.3, side * 1.7)))
	_add_cylinder_multimesh("ExcavatorRollers", roller_transforms, &"tire", excavator_detail_root, 10)
	var shoe_transforms: Array[Transform3D] = []
	for side: float in [-1.0, 1.0]:
		for shoe_index: int in 14:
			var shoe_x := -3.35 + shoe_index * 0.52
			for shoe_y: float in [-0.92, 0.3]:
				var basis := Basis.from_scale(Vector3(0.48, 0.14, 0.46))
				shoe_transforms.append(Transform3D(basis, Vector3(shoe_x, shoe_y, side * 1.7)))
	_add_box_multimesh("ExcavatorTrackShoes", shoe_transforms, &"tire", excavator_detail_root)
	var housing_transforms: Array[Transform3D] = [
		Transform3D(Basis.from_scale(Vector3(3.8, 1.5, 3.0)), Vector3(-1.35, 1.5, 0.0)),
		Transform3D(Basis.from_scale(Vector3(2.0, 1.35, 0.08)), Vector3(-1.55, 2.55, -1.3)),
		Transform3D(Basis.from_scale(Vector3(0.08, 1.35, 2.0)), Vector3(-2.82, 2.55, 0.0)),
		Transform3D(Basis.from_scale(Vector3(1.8, 0.65, 2.6)), Vector3(-3.0, 1.15, 0.0)),
		Transform3D(Basis.from_scale(Vector3(1.8, 0.45, 2.2)), Vector3(11.0, -0.05, 10.8)),
	]
	_add_box_multimesh("ExcavatorHousing", housing_transforms, &"yellow", excavator_detail_root)
	var hydraulic_transforms: Array[Transform3D] = []
	hydraulic_transforms.append(_cylinder_transform_between(Vector3(-0.2, 2.1, -0.35), Vector3(6.1, 3.25, 5.6), 0.13))
	hydraulic_transforms.append(_cylinder_transform_between(Vector3(0.2, 2.1, 0.35), Vector3(6.5, 3.25, 6.0), 0.085))
	hydraulic_transforms.append(_cylinder_transform_between(Vector3(6.3, 3.0, 5.8), Vector3(9.9, 1.0, 9.2), 0.11))
	hydraulic_transforms.append(_cylinder_transform_between(Vector3(9.8, 0.95, 9.25), Vector3(11.1, 0.2, 10.5), 0.075))
	_add_cylinder_multimesh("ExcavatorHydraulics", hydraulic_transforms, &"metal", excavator_detail_root, 9)
	_add_visual_cylinder("ExcavatorExhaust", 0.13, 2.1, excavator_anchor + Vector3(-2.7, excavator_ground + 3.5, -0.8), &"metal")

	# Floodlights and a timing shack frame the remote point-to-point trailhead.
	var timing_anchor := Vector3(-331.0, 0.0, 279.0)
	var start_ground := _terrain_height_at(timing_anchor.x, timing_anchor.z)
	_add_static_box("TimingShack", Vector3(6.5, 3.2, 4.0), timing_anchor + Vector3.UP * (start_ground + 1.6), &"cliff_dark")
	_add_visual_box("TimingStripe", Vector3(6.6, 0.45, 4.05), timing_anchor + Vector3.UP * (start_ground + 2.2), &"red")
	_add_visual_box("TimingWindow", Vector3(3.8, 1.0, 0.08), timing_anchor + Vector3(0.0, start_ground + 1.75, -2.04), &"metal")
	for x_position: float in [-344.0, -320.0, -296.0]:
		var pole_ground := _terrain_height_at(x_position, 286.0)
		_add_visual_cylinder("LightPole%d" % int(x_position), 0.12, 9.0, Vector3(x_position, pole_ground + 4.5, 286.0), &"metal")
		_add_visual_box("LightBar%d" % int(x_position), Vector3(2.6, 0.4, 0.45), Vector3(x_position, pole_ground + 8.9, 286.0), &"cream")

	# A crusher and conveyor silhouette breaks up the long eastern descent.
	# The downstream v5 corridor now uses the former east-wall pocket. Keep the
	# crusher beyond the outside containment line rather than turning the gate-10
	# approach into a hard chicane.
	var crusher_anchor := Vector3(350.0, 0.0, -165.0)
	var crusher_ground := _terrain_height_at(crusher_anchor.x, crusher_anchor.z)
	_add_static_box("CrusherBase", Vector3(12.0, 5.0, 9.0), crusher_anchor + Vector3(0.0, crusher_ground + 2.5, 0.0), &"cliff_dark")
	_add_visual_box("CrusherHopper", Vector3(8.0, 5.5, 7.0), crusher_anchor + Vector3(0.0, crusher_ground + 7.4, 0.0), &"metal", Vector3(0.0, 0.0, 0.12))
	_add_visual_box("Conveyor", Vector3(2.0, 1.0, 28.0), crusher_anchor + Vector3(14.0, crusher_ground + 8.0, 14.0), &"metal", Vector3(-0.24, -0.72, 0.0))
	for prop_index: int in 9:
		var row := prop_index / 3
		var column := prop_index % 3
		_add_destructible_barrel("BreakawayBarrel%02d" % prop_index, Vector3(-22.0 + column * 1.25, 0.65, 12.0 + row * 1.35))
	# Landmark rocks make the widely separated bends readable from long sightlines.
	for index: int in range(1, _track_points.size() - 1):
		var direction := (_track_points[index + 1] - _track_points[index - 1]).normalized()
		var right := Vector3(direction.z, 0.0, -direction.x)
		var side := -1.0 if index % 2 == 0 else 1.0
		var radius := 1.25 + float(index % 3) * 0.35
		var landmark_position := _track_points[index] + right * side * (_track_width * 0.5 + 7.0)
		landmark_position.y = _terrain_height_at(landmark_position.x, landmark_position.z)
		_add_boulder("TrailLandmark%02d" % index, landmark_position, radius, index % 4 == 0)


func _build_course_markers() -> void:
	var stride := maxi(int(round(11.0 / 1.05)), 1)
	for index: int in range(0, _ride_points.size() - 1, stride):
		var direction := CourseSpline.tangent_at(_ride_points, index)
		var right := direction.cross(Vector3.UP).normalized()
		var side := -1.0 if (index / stride) % 2 == 0 else 1.0
		_add_cone(
			"Marker%d" % index,
			# Course markers are visual-only, so keep them behind the containment
			# panels instead of inviting the player to visibly ride through them.
			_ride_points[index] + right * side * (_track_width * 0.5 + 5.25) + Vector3.UP * 0.42
		)
	_flush_course_markers()


func _build_trackside_life() -> void:
	var spectator_positions: Array[Vector3] = [
		Vector3(-326.0, 0.0, 278.0), Vector3(-322.0, 0.0, 281.0), Vector3(-318.0, 0.0, 283.0),
		Vector3(-105.0, 0.0, -161.0), Vector3(-99.0, 0.0, -164.0), Vector3(-93.0, 0.0, -163.0),
		Vector3(320.0, 0.0, 31.0), Vector3(325.0, 0.0, 26.0), Vector3(326.0, 0.0, 20.0),
	]
	for index: int in spectator_positions.size():
		spectator_positions[index].y = _terrain_height_at(spectator_positions[index].x, spectator_positions[index].z)
		_add_spectator("Spectator%02d" % index, spectator_positions[index], Color.from_hsv(float(index) / 9.0, 0.62, 0.88))
	for flag_index: int in 5:
		var flag_position := Vector3(-350.0 + flag_index * 12.0, 0.0, 292.0)
		flag_position.y = _terrain_height_at(flag_position.x, flag_position.z)
		_add_visual_cylinder("FlagPole%d" % flag_index, 0.055, 4.5, flag_position + Vector3.UP * 2.25, &"metal")
		_add_visual_box("Flag%d" % flag_index, Vector3(1.5, 0.72, 0.06), flag_position + Vector3(0.75, 3.85, 0.0), &"red")


func _add_spectator(node_name: String, position: Vector3, color: Color) -> void:
	var root := Node3D.new()
	root.name = node_name
	root.position = position
	root.rotation.y = position.angle_to(Vector3.ZERO)
	add_child(root)
	var shirt := StandardMaterial3D.new()
	shirt.albedo_color = color
	shirt.roughness = 0.85
	var torso := BoxMesh.new()
	torso.size = Vector3(0.48, 0.72, 0.3)
	var torso_mesh := MeshInstance3D.new()
	torso_mesh.mesh = torso
	torso_mesh.position.y = 1.05
	torso_mesh.material_override = shirt
	root.add_child(torso_mesh)
	var head := SphereMesh.new()
	head.radius = 0.21
	head.height = 0.42
	head.radial_segments = 8
	head.rings = 5
	var head_mesh := MeshInstance3D.new()
	head_mesh.mesh = head
	head_mesh.position.y = 1.65
	head_mesh.material_override = _materials[&"cream"]
	root.add_child(head_mesh)


func _add_track_segment(start: Vector3, end: Vector3, width: float) -> void:
	var delta := end - start
	if delta.length_squared() < 0.01:
		return
	var direction := delta.normalized()
	var basis := Basis.looking_at(direction, Vector3.UP)
	var body := StaticBody3D.new()
	body.name = "DirtTrackSegment"
	body.collision_layer = 2
	body.collision_mask = 1
	body.transform = Transform3D(basis, (start + end) * 0.5 - basis.y * (TRACK_THICKNESS * 0.5))
	_tag_surface(body, &"DIRT", 0.76, 1.16)
	add_child(body)

	var box := BoxMesh.new()
	box.size = Vector3(width, TRACK_THICKNESS, delta.length() + 1.4)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "TrackSegment"
	mesh_instance.mesh = box
	mesh_instance.material_override = _materials[&"track"]
	body.add_child(mesh_instance)

	var shape := BoxShape3D.new()
	shape.size = box.size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)

	for side: float in [-1.0, 1.0]:
		var rut_mesh := BoxMesh.new()
		rut_mesh.size = Vector3(0.34, 0.028, delta.length() * 0.96)
		var rut := MeshInstance3D.new()
		rut.name = "TrackRut"
		rut.mesh = rut_mesh
		rut.material_override = _materials[&"rut"]
		rut.position = Vector3(side * minf(2.0, width * 0.28), TRACK_THICKNESS * 0.52, 0.0)
		body.add_child(rut)


func _add_static_box(
	body_name: String,
	size: Vector3,
	position: Vector3,
	material_key: StringName,
	rotation: Vector3 = Vector3.ZERO
) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = body_name
	body.collision_layer = 2
	body.collision_mask = 1
	body.position = position
	body.rotation = rotation
	add_child(body)
	match material_key:
		&"track", &"track_edge", &"ground":
			_tag_surface(body, &"DIRT", 0.82, 0.92)
		&"cliff", &"cliff_dark", &"rock":
			_tag_surface(body, &"ROCK", 1.08, 0.24)
		_:
			_tag_surface(body, &"HARDPACK", 0.9, 0.38)

	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = box_mesh
	mesh_instance.material_override = _materials[material_key]
	body.add_child(mesh_instance)

	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	return body


func _add_visual_box(
	mesh_name: String,
	size: Vector3,
	position: Vector3,
	material_key: StringName,
	rotation: Vector3 = Vector3.ZERO
) -> MeshInstance3D:
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = mesh_name
	mesh_instance.mesh = box_mesh
	mesh_instance.position = position
	mesh_instance.rotation = rotation
	mesh_instance.material_override = _materials[material_key]
	add_child(mesh_instance)
	return mesh_instance


func _add_visual_cylinder(
	mesh_name: String,
	radius: float,
	height: float,
	position: Vector3,
	material_key: StringName,
	rotation: Vector3 = Vector3.ZERO
) -> MeshInstance3D:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = height
	cylinder.radial_segments = 10
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = mesh_name
	mesh_instance.mesh = cylinder
	mesh_instance.position = position
	mesh_instance.rotation = rotation
	mesh_instance.material_override = _materials[material_key]
	add_child(mesh_instance)
	return mesh_instance


func _add_box_multimesh(
	node_name: String,
	transforms: Array[Transform3D],
	material_key: StringName,
	parent: Node3D
) -> void:
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	box.material = _materials[material_key]
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = box
	multimesh.instance_count = transforms.size()
	for index: int in transforms.size():
		multimesh.set_instance_transform(index, transforms[index])
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multimesh
	parent.add_child(instance)


func _add_cylinder_multimesh(
	node_name: String,
	transforms: Array[Transform3D],
	material_key: StringName,
	parent: Node3D,
	radial_segments: int
) -> void:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 1.0
	cylinder.bottom_radius = 1.0
	cylinder.height = 1.0
	cylinder.radial_segments = radial_segments
	cylinder.material = _materials[material_key]
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = cylinder
	multimesh.instance_count = transforms.size()
	for index: int in transforms.size():
		multimesh.set_instance_transform(index, transforms[index])
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multimesh
	parent.add_child(instance)


func _cylinder_transform_between(start: Vector3, end: Vector3, radius: float) -> Transform3D:
	var direction := end - start
	if direction.length_squared() < 0.0001:
		return Transform3D(Basis.from_scale(Vector3.ONE * 0.001), start)
	var rotation_basis := Basis(Quaternion(Vector3.UP, direction.normalized()))
	var scaled_basis := rotation_basis * Basis.from_scale(Vector3(radius, direction.length(), radius))
	return Transform3D(scaled_basis, (start + end) * 0.5)


func _add_destructible_barrel(body_name: String, position: Vector3) -> void:
	var body := DestructibleProp.new()
	body.name = body_name
	body.mass = 4.0
	body.collision_layer = 2
	body.collision_mask = 1 | 2
	body.position = position
	add_child(body)
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.42
	cylinder.bottom_radius = 0.42
	cylinder.height = 1.3
	cylinder.radial_segments = 10
	var mesh := MeshInstance3D.new()
	mesh.mesh = cylinder
	mesh.material_override = _materials[&"red"]
	body.add_child(mesh)
	var stripe := TorusMesh.new()
	stripe.inner_radius = 0.38
	stripe.outer_radius = 0.44
	stripe.rings = 10
	stripe.ring_segments = 6
	var stripe_mesh := MeshInstance3D.new()
	stripe_mesh.mesh = stripe
	stripe_mesh.rotation.x = PI * 0.5
	stripe_mesh.material_override = _materials[&"cream"]
	body.add_child(stripe_mesh)
	var shape := CylinderShape3D.new()
	shape.radius = 0.42
	shape.height = 1.3
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)


func _add_wedge_ramp(
	body_name: String,
	position: Vector3,
	yaw: float,
	length: float,
	width: float,
	height: float,
	high_toward_negative_z: bool,
	alignment: Basis = Basis.IDENTITY
) -> StaticBody3D:
	if alignment == Basis.IDENTITY:
		alignment = Basis.from_euler(Vector3(0.0, yaw, 0.0))
	var half_width := width * 0.5
	var half_length := length * 0.5
	var high_z := -half_length if high_toward_negative_z else half_length
	var low_z := half_length if high_toward_negative_z else -half_length
	var bottom_y := -0.18
	var station_count := maxi(int(ceil(length / 0.65)) + 1, 10)
	var top_left := PackedVector3Array()
	var top_right := PackedVector3Array()
	var bottom_left := PackedVector3Array()
	var bottom_right := PackedVector3Array()
	for station_index: int in station_count:
		var weight := float(station_index) / float(station_count - 1)
		var station_z := lerpf(low_z, high_z, weight)
		var station_y := height * _progressive_ramp_ratio(weight)
		top_left.append(Vector3(-half_width, station_y, station_z))
		top_right.append(Vector3(half_width, station_y, station_z))
		bottom_left.append(Vector3(-half_width, bottom_y, station_z))
		bottom_right.append(Vector3(half_width, bottom_y, station_z))

	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var collision_faces := PackedVector3Array()
	for station_index: int in station_count - 1:
		var next := station_index + 1
		_add_ramp_triangle(surface_tool, collision_faces, top_left[next], top_right[next], top_right[station_index], Vector3.UP)
		_add_ramp_triangle(surface_tool, collision_faces, top_left[next], top_right[station_index], top_left[station_index], Vector3.UP)
		_add_ramp_triangle(surface_tool, collision_faces, top_left[station_index], top_left[next], bottom_left[next], Vector3.LEFT, false)
		_add_ramp_triangle(surface_tool, collision_faces, top_left[station_index], bottom_left[next], bottom_left[station_index], Vector3.LEFT, false)
		_add_ramp_triangle(surface_tool, collision_faces, top_right[station_index], bottom_right[next], top_right[next], Vector3.RIGHT, false)
		_add_ramp_triangle(surface_tool, collision_faces, top_right[station_index], bottom_right[station_index], bottom_right[next], Vector3.RIGHT, false)
		_add_ramp_triangle(surface_tool, collision_faces, bottom_left[station_index], bottom_right[next], bottom_right[station_index], Vector3.DOWN, false)
		_add_ramp_triangle(surface_tool, collision_faces, bottom_left[station_index], bottom_left[next], bottom_right[next], Vector3.DOWN, false)
	# Leave both travel ends visually and physically open. This removes the
	# misleading full-width wall at the upstream end of every receiver.
	surface_tool.generate_normals()
	var ramp_mesh := surface_tool.commit()

	var body := StaticBody3D.new()
	body.name = body_name
	body.collision_layer = 2
	body.collision_mask = 1
	body.transform = Transform3D(alignment, position)
	_tag_surface(body, &"DIRT", 0.84, 1.28)
	body.set_meta(&"ramp_length", length)
	body.set_meta(&"ramp_width", width)
	body.set_meta(&"ramp_height", height)
	body.set_meta(&"collision_top_only", true)
	body.set_meta(&"open_ride_ends", true)
	if high_toward_negative_z:
		body.set_meta(&"airtime_takeoff", true)
	add_child(body)
	if high_toward_negative_z:
		body.add_to_group(&"airtime_takeoff")

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = ramp_mesh
	mesh_instance.material_override = _materials[&"track"]
	body.add_child(mesh_instance)

	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = false
	shape.set_faces(collision_faces)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	return body


func _progressive_ramp_ratio(weight: float) -> float:
	var clamped := clampf(weight, 0.0, 1.0)
	var rise := pow(clamped, 3.0)
	var settle := pow(1.0 - clamped, 3.0)
	var progressive := rise / maxf(rise + settle, 0.0001)
	# Preserve a 4-6 degree entry/lip grade while keeping the load-bearing
	# middle near 30-34 degrees at the authored race-ramp aspect ratios.
	return lerpf(progressive, clamped, 0.26)


func _add_ramp_triangle(
	surface_tool: SurfaceTool,
	faces: PackedVector3Array,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	desired_normal: Vector3,
	include_collision: bool = true
) -> void:
	var second := b
	var third := c
	# Godot front faces are clockwise when viewed from outside, so their raw
	# mathematical cross points opposite the outward-facing normal.
	if (second - a).cross(third - a).dot(desired_normal) > 0.0:
		second = c
		third = b
	surface_tool.add_vertex(a)
	surface_tool.add_vertex(second)
	surface_tool.add_vertex(third)
	if include_collision:
		faces.append(a)
		faces.append(second)
		faces.append(third)


func _add_triangle(surface_tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	surface_tool.add_vertex(a)
	surface_tool.add_vertex(b)
	surface_tool.add_vertex(c)


func _add_boulder(body_name: String, position: Vector3, radius: float, has_collision: bool) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 1.65
	sphere.radial_segments = 9
	sphere.rings = 5
	if has_collision:
		var body := StaticBody3D.new()
		body.name = body_name
		body.collision_layer = 2
		body.collision_mask = 1
		body.position = position + Vector3.UP * radius * 0.72
		_tag_surface(body, &"ROCK", 1.12, 0.18)
		add_child(body)
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = sphere
		mesh_instance.material_override = _materials[&"rock"]
		body.add_child(mesh_instance)
		var shape := SphereShape3D.new()
		shape.radius = radius * 0.82
		var collision := CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)
	else:
		var basis := Basis.from_euler(Vector3(radius * 0.17, radius * 0.31, radius * 0.11)).scaled(Vector3(radius, radius, radius))
		_visual_boulder_transforms.append(Transform3D(basis, position + Vector3.UP * radius * 0.72))


func _add_cone(_mesh_name: String, position: Vector3) -> void:
	_marker_transforms.append(Transform3D(Basis.IDENTITY, position))


func _flush_course_markers() -> void:
	if _marker_transforms.is_empty():
		return
	var cone := CylinderMesh.new()
	cone.top_radius = 0.05
	cone.bottom_radius = 0.34
	cone.height = 0.84
	cone.radial_segments = 8
	cone.material = _materials[&"cream"]
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = cone
	multimesh.instance_count = _marker_transforms.size()
	for index: int in _marker_transforms.size():
		multimesh.set_instance_transform(index, _marker_transforms[index])
	var instance := MultiMeshInstance3D.new()
	instance.name = "CourseMarkers"
	instance.multimesh = multimesh
	add_child(instance)


func _flush_visual_boulders() -> void:
	if _visual_boulder_transforms.is_empty():
		return
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 1.65
	sphere.radial_segments = 9
	sphere.rings = 5
	sphere.material = _materials[&"rock"]
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = sphere
	multimesh.instance_count = _visual_boulder_transforms.size()
	for index: int in _visual_boulder_transforms.size():
		multimesh.set_instance_transform(index, _visual_boulder_transforms[index])
	var instance := MultiMeshInstance3D.new()
	instance.name = "ScenicBoulders"
	instance.multimesh = multimesh
	add_child(instance)


func _add_sloped_berm(body_name: String, start: Vector3, end: Vector3, weight: float, side: float) -> void:
	var delta := end - start
	if delta.length_squared() < 0.01:
		return
	var basis := Basis.looking_at(delta.normalized(), Vector3.UP)
	var center := start.lerp(end, weight) + basis.x * side * (_track_width * 0.5 + 0.6)
	var body := StaticBody3D.new()
	body.name = body_name
	body.collision_layer = 2
	body.collision_mask = 1
	body.transform = Transform3D(basis, center + basis.y * 0.35)
	_tag_surface(body, &"DIRT", 0.92, 1.0)
	add_child(body)
	var box := BoxMesh.new()
	box.size = Vector3(1.8, 1.35, minf(delta.length() * 0.3, 34.0))
	var mesh := MeshInstance3D.new()
	mesh.mesh = box
	mesh.material_override = _materials[&"track_edge"]
	body.add_child(mesh)
	var shape := BoxShape3D.new()
	shape.size = box.size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)


func _build_terrain_surface_profiles() -> Array[Dictionary]:
	var profiles: Array[Dictionary] = []
	profiles.append(_make_terrain_surface_profile(_surface_centerline(), _track_width, _main_surface_config()))
	# The apron is part of the same full-width ribbon, so terrain must clear the
	# main shoulders as well as the center braking lane.
	profiles.append(_make_terrain_surface_profile(_finish_apron_centerline(), _track_width, _main_surface_config()))
	for alternate: PackedVector3Array in _alternate_ride_trails:
		profiles.append(_make_terrain_surface_profile(alternate, 5.8, _alternate_surface_config()))
	return profiles


func _make_terrain_surface_profile(centerline: PackedVector3Array, width: float, config: Dictionary) -> Dictionary:
	# Reuse the exact frames that CourseSurfaceBuilder uses. Banking and berms are
	# sampled once instead of being approximated for every coarse terrain vertex.
	var frames: Array[Dictionary] = CourseSurfaceBuilder._build_frames(centerline, width, config)
	var half_width := width * 0.5
	var shoulder_width := float(config.get(&"shoulder_width", 2.0))
	var rut_offset := minf(float(config.get(&"rut_offset", 1.15)), half_width * 0.58)
	var rut_half_width := float(config.get(&"rut_half_width", 0.2))
	var collision_rut_depth := minf(float(config.get(&"physical_rut_depth", 0.024)), 0.028)
	var offsets := PackedFloat32Array([
		-half_width - shoulder_width, -half_width,
		-rut_offset - rut_half_width, -rut_offset, -rut_offset + rut_half_width,
		0.0,
		rut_offset - rut_half_width, rut_offset, rut_offset + rut_half_width,
		half_width, half_width + shoulder_width,
	])
	var heights := PackedFloat32Array([
		-0.5, -0.055, 0.018, -collision_rut_depth, 0.018, 0.04,
		0.018, -collision_rut_depth, 0.018, -0.055, -0.5,
	])
	var query_indices := PackedInt32Array()
	var maximum_frame_span := 0.0
	if not frames.is_empty():
		query_indices.append(0)
		var last_query_distance: float = frames[0][&"distance"]
		for index: int in range(1, frames.size()):
			var frame_distance: float = frames[index][&"distance"]
			var previous_position: Vector3 = frames[index - 1][&"position"]
			var frame_position: Vector3 = frames[index][&"position"]
			maximum_frame_span = maxf(maximum_frame_span, Vector2(previous_position.x, previous_position.z).distance_to(Vector2(frame_position.x, frame_position.z)))
			if frame_distance - last_query_distance >= TERRAIN_PROFILE_QUERY_SPACING or index == frames.size() - 1:
				query_indices.append(index)
				last_query_distance = frame_distance
	var query_cache := _build_terrain_profile_query_cache(frames, query_indices)
	return {
		&"frames": frames,
		&"query_indices": query_indices,
		&"query_cache": query_cache,
		&"width": width,
		&"outer_half_width": half_width + shoulder_width,
		&"offsets": offsets,
		&"heights": heights,
		&"maximum_frame_span": maxf(maximum_frame_span, 0.1),
	}


func _build_terrain_profile_query_cache(
	frames: Array[Dictionary],
	query_indices: PackedInt32Array
) -> Dictionary:
	var starts := PackedVector2Array()
	var deltas := PackedVector2Array()
	var length_squared := PackedFloat32Array()
	if frames.size() < 2 or query_indices.size() < 2:
		return {
			&"starts": starts,
			&"deltas": deltas,
			&"length_squared": length_squared,
		}
	for query_segment: int in query_indices.size() - 1:
		var start_position: Vector3 = frames[query_indices[query_segment]][&"position"]
		var end_position: Vector3 = frames[query_indices[query_segment + 1]][&"position"]
		var start := Vector2(start_position.x, start_position.z)
		var delta := Vector2(end_position.x, end_position.z) - start
		starts.append(start)
		deltas.append(delta)
		length_squared.append(maxf(delta.length_squared(), 0.001))
	return {
		&"starts": starts,
		&"deltas": deltas,
		&"length_squared": length_squared,
	}


func _terrain_surface_context(x: float, z: float) -> Dictionary:
	var point := Vector2(x, z)
	var nearest: Dictionary = {}
	var nearest_distance := INF
	var clearance_ceiling := INF
	for profile_index: int in _terrain_surface_profiles.size():
		var profile := _terrain_surface_profiles[profile_index]
		var sample := _nearest_terrain_profile_sample(profile, point)
		if sample.is_empty():
			continue
		var distance: float = sample[&"distance"]
		if distance < nearest_distance:
			nearest_distance = distance
			sample[&"profile_index"] = profile_index
			nearest = sample
		var frame_padding: float = profile[&"maximum_frame_span"]
		var influence_radius := TERRAIN_CELL_DIAGONAL + frame_padding
		if float(sample[&"edge_distance"]) <= influence_radius:
			clearance_ceiling = minf(
				clearance_ceiling,
				_terrain_profile_clearance_ceiling(profile, sample, point, influence_radius)
			)
	return {&"nearest": nearest, &"clearance_ceiling": clearance_ceiling}
func _nearest_terrain_profile_sample(profile: Dictionary, point: Vector2) -> Dictionary:
	var frames: Array[Dictionary] = profile[&"frames"]
	var query_indices: PackedInt32Array = profile[&"query_indices"]
	if frames.size() < 2 or query_indices.size() < 2:
		return {}
	var best_query_segment := _nearest_terrain_query_segment(profile, point)

	var query_start := maxi(best_query_segment - 1, 0)
	var query_end := mini(best_query_segment + 2, query_indices.size() - 1)
	var frame_start := maxi(query_indices[query_start] - 2, 0)
	var frame_end := mini(query_indices[query_end] + 2, frames.size() - 1)
	var best_segment := frame_start
	var best_weight := 0.0
	var best_distance_squared := INF
	for frame_index: int in range(frame_start, frame_end):
		var frame_start_position: Vector3 = frames[frame_index][&"position"]
		var frame_end_position: Vector3 = frames[frame_index + 1][&"position"]
		var start := Vector2(frame_start_position.x, frame_start_position.z)
		var segment := Vector2(frame_end_position.x, frame_end_position.z) - start
		var weight := clampf((point - start).dot(segment) / maxf(segment.length_squared(), 0.001), 0.0, 1.0)
		var distance_squared := point.distance_squared_to(start + segment * weight)
		if distance_squared < best_distance_squared:
			best_distance_squared = distance_squared
			best_segment = frame_index
			best_weight = weight

	var distance := sqrt(best_distance_squared)
	var frame_a: Dictionary = frames[best_segment]
	var frame_b: Dictionary = frames[best_segment + 1]
	var position_a: Vector3 = frame_a[&"position"]
	var position_b: Vector3 = frame_b[&"position"]
	var center := position_a.lerp(position_b, best_weight)
	var right_a: Vector3 = frame_a[&"right"]
	var right_b: Vector3 = frame_b[&"right"]
	var right := right_a.lerp(right_b, best_weight).normalized()
	var flat_right := Vector2(right.x, right.z)
	var relative := point - Vector2(center.x, center.z)
	var signed_offset := relative.dot(flat_right) / maxf(flat_right.length_squared(), 0.001)
	var outer_half_width: float = profile[&"outer_half_width"]
	var clamped_offset := clampf(signed_offset, -outer_half_width, outer_half_width)
	var surface_height := lerpf(
		_profile_surface_height_at_frame(frame_a, clamped_offset, profile),
		_profile_surface_height_at_frame(frame_b, clamped_offset, profile),
		best_weight
	)
	return {
		&"distance": distance,
		&"edge_distance": maxf(distance - outer_half_width, 0.0),
		&"center_height": center.y,
		&"surface_height": surface_height,
		&"signed_offset": signed_offset,
		&"segment_index": best_segment,
		&"segment_weight": best_weight,
		&"arc_distance": lerpf(float(frame_a[&"distance"]), float(frame_b[&"distance"]), best_weight),
	}


func _nearest_terrain_query_segment(profile: Dictionary, point: Vector2) -> int:
	var query_cache: Dictionary = profile.get(&"query_cache", {})
	var starts: PackedVector2Array = query_cache.get(&"starts", PackedVector2Array())
	var deltas: PackedVector2Array = query_cache.get(&"deltas", PackedVector2Array())
	var length_squared: PackedFloat32Array = query_cache.get(
		&"length_squared", PackedFloat32Array()
	)
	if (
		starts.is_empty()
		or starts.size() != deltas.size()
		or starts.size() != length_squared.size()
	):
		var frames: Array[Dictionary] = profile[&"frames"]
		var query_indices: PackedInt32Array = profile[&"query_indices"]
		return _nearest_terrain_query_segment_linear(frames, query_indices, point)

	var best_query_segment := 0
	var best_distance_squared := INF
	for query_segment: int in starts.size():
		var start := starts[query_segment]
		var delta := deltas[query_segment]
		var weight := clampf(
			(point - start).dot(delta) / maxf(float(length_squared[query_segment]), 0.001),
			0.0,
			1.0
		)
		var distance_squared := point.distance_squared_to(start + delta * weight)
		if distance_squared < best_distance_squared:
			best_distance_squared = distance_squared
			best_query_segment = query_segment
	return best_query_segment


func _nearest_terrain_query_segment_linear(
	frames: Array[Dictionary],
	query_indices: PackedInt32Array,
	point: Vector2
) -> int:
	var best_query_segment := 0
	var best_distance_squared := INF
	for query_segment: int in query_indices.size() - 1:
		var distance_squared := _terrain_query_segment_distance_squared(
			frames, query_indices, query_segment, point
		)
		if distance_squared < best_distance_squared:
			best_distance_squared = distance_squared
			best_query_segment = query_segment
	return best_query_segment


func _terrain_query_segment_distance_squared(
	frames: Array[Dictionary],
	query_indices: PackedInt32Array,
	query_segment: int,
	point: Vector2
) -> float:
	var start_position: Vector3 = frames[query_indices[query_segment]][&"position"]
	var end_position: Vector3 = frames[query_indices[query_segment + 1]][&"position"]
	var start := Vector2(start_position.x, start_position.z)
	var segment := Vector2(end_position.x, end_position.z) - start
	var weight := clampf(
		(point - start).dot(segment) / maxf(segment.length_squared(), 0.001),
		0.0,
		1.0
	)
	return point.distance_squared_to(start + segment * weight)


func _terrain_profile_clearance_ceiling(profile: Dictionary, sample: Dictionary, point: Vector2, influence_radius: float) -> float:
	var frames: Array[Dictionary] = profile[&"frames"]
	var outer_half_width: float = profile[&"outer_half_width"]
	var arc_distance: float = sample[&"arc_distance"]
	var scan_distance := influence_radius + outer_half_width + TERRAIN_PROFILE_QUERY_SPACING
	var start_index: int = sample[&"segment_index"]
	var end_index := mini(start_index + 1, frames.size() - 1)
	while start_index > 0 and arc_distance - float(frames[start_index - 1][&"distance"]) <= scan_distance:
		start_index -= 1
	while end_index < frames.size() - 1 and float(frames[end_index + 1][&"distance"]) - arc_distance <= scan_distance:
		end_index += 1

	var minimum_height := INF
	var influence_squared := influence_radius * influence_radius
	for frame_index: int in range(start_index, end_index + 1):
		var frame: Dictionary = frames[frame_index]
		var frame_position: Vector3 = frame[&"position"]
		var right: Vector3 = frame[&"right"]
		var flat_right := Vector2(right.x, right.z)
		var right_length_squared := maxf(flat_right.length_squared(), 0.001)
		var relative := point - Vector2(frame_position.x, frame_position.z)
		var signed_offset := relative.dot(flat_right) / right_length_squared
		var residual := relative - flat_right * signed_offset
		var residual_squared := residual.length_squared()
		if residual_squared > influence_squared:
			continue
		var lateral_reach := sqrt(maxf(influence_squared - residual_squared, 0.0) / right_length_squared)
		var minimum_offset := maxf(-outer_half_width, signed_offset - lateral_reach)
		var maximum_offset := minf(outer_half_width, signed_offset + lateral_reach)
		if minimum_offset > maximum_offset:
			continue
		minimum_height = minf(minimum_height, _profile_minimum_height_between(frame, minimum_offset, maximum_offset, profile))
	return minimum_height - TERRAIN_SURFACE_GAP


func _profile_minimum_height_between(frame: Dictionary, minimum_offset: float, maximum_offset: float, profile: Dictionary) -> float:
	var result := minf(
		_profile_surface_height_at_frame(frame, minimum_offset, profile),
		_profile_surface_height_at_frame(frame, maximum_offset, profile)
	)
	var offsets: PackedFloat32Array = profile[&"offsets"]
	for offset: float in offsets:
		if offset > minimum_offset and offset < maximum_offset:
			result = minf(result, _profile_surface_height_at_frame(frame, offset, profile))
	return result


func _profile_surface_height_at_frame(frame: Dictionary, offset: float, profile: Dictionary) -> float:
	var position: Vector3 = frame[&"position"]
	var right: Vector3 = frame[&"right"]
	var up: Vector3 = frame[&"up"]
	return position.y + right.y * offset + up.y * _profile_local_height(frame, offset, profile)


func _profile_local_height(frame: Dictionary, offset: float, profile: Dictionary) -> float:
	var offsets: PackedFloat32Array = profile[&"offsets"]
	var heights: PackedFloat32Array = profile[&"heights"]
	if offset <= offsets[0]:
		return _profile_vertex_height(frame, offsets[0], heights[0], profile)
	for index: int in offsets.size() - 1:
		if offset <= offsets[index + 1]:
			var weight := inverse_lerp(offsets[index], offsets[index + 1], offset)
			return lerpf(
				_profile_vertex_height(frame, offsets[index], heights[index], profile),
				_profile_vertex_height(frame, offsets[index + 1], heights[index + 1], profile),
				weight
			)
	return _profile_vertex_height(frame, offsets[-1], heights[-1], profile)


func _profile_vertex_height(frame: Dictionary, offset: float, base_height: float, profile: Dictionary) -> float:
	var half_width := float(profile[&"width"]) * 0.5
	var edge_ratio := smoothstep(half_width * 0.64, half_width, absf(offset))
	var curvature: float = frame[&"curvature"]
	var is_outside := (offset > 0.0 and curvature > 0.0) or (offset < 0.0 and curvature < 0.0)
	return base_height + (float(frame[&"berm_height"]) * edge_ratio if is_outside else 0.0)


func _start_terrain_build() -> void:
	var paths: Array[PackedVector3Array] = [_surface_centerline().duplicate()]
	paths.append(_finish_apron_centerline().duplicate())
	for alternate: PackedVector3Array in _alternate_ride_trails:
		paths.append(alternate.duplicate())
	paths = _decimate_terrain_paths(paths)
	_terrain_query_paths = paths
	# Collision must cover the whole quarry before the bike is released. This
	# mesh is small enough to build synchronously and avoids a web-only window in
	# which the track ribbon existed but all surrounding ground was still empty.
	_attach_generated_terrain(_generate_terrain_data(paths))


func _decimate_terrain_paths(paths: Array[PackedVector3Array]) -> Array[PackedVector3Array]:
	# Terrain vertices are twelve metres apart, so scanning the metre-spaced bike
	# spline for every vertex adds no geometric detail. A grid-scale path retains
	# the correct course envelope and makes complete ground collision available
	# synchronously at startup.
	var decimated: Array[PackedVector3Array] = []
	for path: PackedVector3Array in paths:
		if path.size() <= 2:
			decimated.append(path.duplicate())
			continue
		var result := PackedVector3Array([path[0]])
		var distance_since_sample := 0.0
		for index: int in range(1, path.size()):
			distance_since_sample += path[index - 1].distance_to(path[index])
			if distance_since_sample >= TERRAIN_STEP * 0.75 or index == path.size() - 1:
				result.append(path[index])
				distance_since_sample = 0.0
		decimated.append(result)
	return decimated


func _generate_terrain_data(paths: Array[PackedVector3Array]) -> Dictionary:
	var noise := FastNoiseLite.new()
	_configure_terrain_noise(noise)
	var columns := int(ceil(TERRAIN_SIZE.x / TERRAIN_STEP)) + 1
	var rows := int(ceil(TERRAIN_SIZE.y / TERRAIN_STEP)) + 1
	var step_x := TERRAIN_SIZE.x / float(columns - 1)
	var step_z := TERRAIN_SIZE.y / float(rows - 1)
	var heights := PackedFloat32Array()
	heights.resize(columns * rows)
	for row: int in rows:
		var z := -TERRAIN_SIZE.y * 0.5 + float(row) * step_z
		for column: int in columns:
			var x := -TERRAIN_SIZE.x * 0.5 + float(column) * step_x
			heights[row * columns + column] = _terrain_height_with_noise(paths, noise, x, z)

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	vertices.resize(columns * rows)
	normals.resize(columns * rows)
	uvs.resize(columns * rows)
	for row: int in rows:
		for column: int in columns:
			var index := row * columns + column
			var x := -TERRAIN_SIZE.x * 0.5 + float(column) * step_x
			var z := -TERRAIN_SIZE.y * 0.5 + float(row) * step_z
			vertices[index] = Vector3(x, heights[index], z)
			var left := heights[row * columns + maxi(column - 1, 0)]
			var right := heights[row * columns + mini(column + 1, columns - 1)]
			var back := heights[maxi(row - 1, 0) * columns + column]
			var front := heights[mini(row + 1, rows - 1) * columns + column]
			normals[index] = Vector3(left - right, step_x + step_z, back - front).normalized()
			uvs[index] = Vector2(float(column) / float(columns - 1), float(row) / float(rows - 1)) * 18.0

	var indices := PackedInt32Array()
	indices.resize((columns - 1) * (rows - 1) * 6)
	var cursor := 0
	for row: int in rows - 1:
		for column: int in columns - 1:
			var top_left := row * columns + column
			var bottom_left := (row + 1) * columns + column
			# Godot treats clockwise triangles as front-facing. Keep the terrain's
			# rideable +Y side visible instead of relying on double-sided materials.
			indices[cursor] = top_left
			indices[cursor + 1] = top_left + 1
			indices[cursor + 2] = bottom_left
			indices[cursor + 3] = top_left + 1
			indices[cursor + 4] = bottom_left + 1
			indices[cursor + 5] = bottom_left
			cursor += 6
	var faces := PackedVector3Array()
	faces.resize(indices.size())
	for index: int in indices.size():
		faces[index] = vertices[indices[index]]
	return {&"vertices": vertices, &"normals": normals, &"uvs": uvs, &"indices": indices, &"faces": faces}


func _attach_generated_terrain(data: Dictionary) -> void:
	var vertices: PackedVector3Array = data.get(&"vertices", PackedVector3Array())
	if vertices.is_empty():
		push_warning("Quarry terrain generation returned no vertices.")
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = data.get(&"normals", PackedVector3Array())
	arrays[Mesh.ARRAY_TEX_UV] = data.get(&"uvs", PackedVector2Array())
	arrays[Mesh.ARRAY_INDEX] = data.get(&"indices", PackedInt32Array())
	var terrain_mesh := ArrayMesh.new()
	terrain_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	terrain_mesh.surface_set_material(0, _materials[&"terrain"])
	var visual := MeshInstance3D.new()
	visual.name = "GeneratedQuarryTerrain"
	visual.mesh = terrain_mesh
	add_child(visual)

	var body := StaticBody3D.new()
	body.name = "GeneratedQuarryTerrainCollision"
	body.collision_layer = 2
	body.collision_mask = 1
	_tag_surface(body, &"HARDPACK", 0.94, 0.62)
	add_child(body)
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(data.get(&"faces", PackedVector3Array()))
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)


func _configure_terrain_noise(noise: FastNoiseLite) -> void:
	noise.seed = TERRAIN_SEED
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.0085
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	noise.fractal_gain = 0.52
	noise.fractal_lacunarity = 2.05


func _terrain_height_at(x: float, z: float) -> float:
	var paths := _terrain_query_paths
	if paths.is_empty():
		paths = [_surface_centerline()]
		paths.append(_finish_apron_centerline())
		paths.append_array(_alternate_ride_trails)
	return _terrain_height_with_noise(paths, _terrain_noise, x, z)


func _terrain_height_with_noise(_paths: Array[PackedVector3Array], noise: FastNoiseLite, x: float, z: float) -> float:
	var terrain_context := _terrain_surface_context(x, z)
	var route_sample: Dictionary = terrain_context[&"nearest"]
	if route_sample.is_empty():
		return 0.0
	var route_edge_distance: float = route_sample[&"edge_distance"]
	var route_surface_height: float = route_sample[&"surface_height"]
	var broad_noise := noise.get_noise_2d(x, z)
	var detail_noise := noise.get_noise_2d(x * 2.7 + 811.0, z * 2.7 - 437.0)
	var edge_ratio := maxf(absf(x) / (TERRAIN_SIZE.x * 0.5), absf(z) / (TERRAIN_SIZE.y * 0.5))
	var base_height := 7.0 + broad_noise * 18.0 + detail_noise * 3.5 + pow(edge_ratio, 3.0) * 16.0
	# Follow the signed banked cross-section all the way through the shoulder.
	# This fills the old five-metre trench without letting the terrain become a
	# second, invisible riding surface above the authored ribbon.
	var shoulder_height := route_surface_height - TERRAIN_SURFACE_GAP + detail_noise * 0.5
	# Keep a low recovery/sightline shelf beyond the full 15.75 m ribbon and
	# shoulder envelope. The previous centerline-based blend began rising only
	# ~4 m past the shoulder, so a curved road could visually aim into the terrain
	# bank even though collision clearance over the ribbon was technically valid.
	var shoulder_blend := 1.0 - smoothstep(18.0, 105.0, route_edge_distance)
	var height := lerpf(base_height, shoulder_height, shoulder_blend)
	var clearance_ceiling: float = terrain_context[&"clearance_ceiling"]
	if is_finite(clearance_ceiling):
		height = minf(height, clearance_ceiling)
	# Keep the original freestyle playground level while terrain rises around it.
	var center_distance := Vector2(x, z).length()
	var freestyle_blend := 1.0 - smoothstep(68.0, 94.0, center_distance)
	return lerpf(height, -0.34, freestyle_blend)
func _tag_surface(body: CollisionObject3D, surface: StringName, roughness: float, roost: float) -> void:
	body.set_meta(&"surface", surface)
	body.set_meta(&"roughness", roughness)
	body.set_meta(&"roost", roost)


func _mark_authoritative_track_surface(surface_root: Node, track_id: StringName) -> void:
	if surface_root == null:
		return
	surface_root.set_meta(&"authoritative_track_surface", true)
	surface_root.set_meta(&"authoritative_track_id", track_id)
	if surface_root is CollisionObject3D:
		(surface_root as CollisionObject3D).collision_layer |= CourseSurfaceBuilder.AUTHORITATIVE_RIDE_LAYER
	for collision_node: Node in surface_root.find_children("*", "CollisionObject3D", true, false):
		(collision_node as CollisionObject3D).collision_layer |= CourseSurfaceBuilder.AUTHORITATIVE_RIDE_LAYER
		collision_node.set_meta(&"authoritative_track_surface", true)
		collision_node.set_meta(&"authoritative_track_id", track_id)


func _material(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = roughness
	result.metallic = metallic
	return result
