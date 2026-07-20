extends Node3D
## Dense wooded enduro district using batched foliage and primitive collision landmarks.

const SurfaceTextureFactory = preload("res://features/environment/procedural_surface_texture.gd")

const TERRAIN_SIZE := Vector2(800.0, 700.0)
const TERRAIN_STEP: float = 12.0
const TERRAIN_SEED: int = 42017
const TRACK_THICKNESS: float = 0.34
const MAIN_SHOULDER_WIDTH: float = 3.5
const TERRAIN_SURFACE_GAP: float = 0.34
const TERRAIN_CELL_DIAGONAL: float = 16.97056275
const TERRAIN_PROFILE_QUERY_SPACING: float = 8.0
const TERRAIN_PROFILE_INDEX_CELL_SIZE: float = 32.0
const TERRAIN_PROFILE_LINEAR_SCAN_MAX_INDICES: int = 64
const ALTERNATE_WELD_CORE_LENGTH: float = 24.0
const ALTERNATE_WELD_BLEND_LENGTH: float = 13.0
const ALTERNATE_TRAIL_WIDTH: float = 4.8
const ALTERNATE_SHOULDER_MARGIN: float = 1.2
const MAIN_RIBBON_RUNOFF_LENGTH: float = 4.0
const PINE_SURFACE_ASSET_DIRECTORY := "res://assets/generated/pine_surfaces"
const PINE_COURSE_DRESSING_SCENE := preload("res://assets/generated/pine_course_dressing.scn")

var _track_points := PackedVector3Array()
var _ride_points := PackedVector3Array()
var _track_width: float = 22.0
var _alternate_trails: Array[PackedVector3Array] = [
	PackedVector3Array([
		Vector3(350.0, 26.0, 230.0),
		Vector3(385.0, 31.0, 195.0),
		Vector3(370.0, 38.0, 160.0),
		Vector3(320.0, 40.0, 150.0),
	]),
	PackedVector3Array([
		Vector3(-155.0, 88.0, 10.0),
		Vector3(-95.0, 98.0, 55.0),
		Vector3(-30.0, 108.0, 35.0),
		Vector3(10.0, 100.0, -30.0),
	]),
]
var _alternate_ride_trails: Array[PackedVector3Array] = []

var _main_route_surface: Node3D
var _materials: Dictionary[StringName, StandardMaterial3D] = {}
var _terrain_noise := FastNoiseLite.new()
var _terrain_query_paths: Array[PackedVector3Array] = []
var _terrain_surface_profiles: Array[Dictionary] = []


func _ready() -> void:
	var profile_build := OS.get_environment("RIDING_DIRTY_PROFILE_PINE") == "1"
	var phase_begin_usec := Time.get_ticks_usec()
	_ensure_course_routes()
	phase_begin_usec = _finish_profiled_phase(&"catalog_and_alternates", phase_begin_usec, profile_build)
	_terrain_surface_profiles = _build_terrain_surface_profiles()
	phase_begin_usec = _finish_profiled_phase(&"terrain_profiles", phase_begin_usec, profile_build)
	_configure_terrain_noise(_terrain_noise)
	_create_materials()
	phase_begin_usec = _finish_profiled_phase(&"materials", phase_begin_usec, profile_build)
	_build_environment()
	_build_ground()
	phase_begin_usec = _finish_profiled_phase(&"environment_and_ground", phase_begin_usec, profile_build)
	_start_terrain_build()
	phase_begin_usec = _finish_profiled_phase(&"terrain", phase_begin_usec, profile_build)
	_build_trail()
	phase_begin_usec = _finish_profiled_phase(&"trail", phase_begin_usec, profile_build)
	_build_creek_crossing()
	phase_begin_usec = _finish_profiled_phase(&"creek", phase_begin_usec, profile_build)
	_build_jumps()
	phase_begin_usec = _finish_profiled_phase(&"jumps", phase_begin_usec, profile_build)
	_build_forest()
	phase_begin_usec = _finish_profiled_phase(&"forest", phase_begin_usec, profile_build)
	_build_landmarks()
	_build_trail_spectators()
	phase_begin_usec = _finish_profiled_phase(&"landmarks_and_spectators", phase_begin_usec, profile_build)
	_attach_course_dressing()
	_finish_profiled_phase(&"course_dressing", phase_begin_usec, profile_build)


func _ensure_course_routes() -> void:
	if _track_points.is_empty():
		_track_points = CourseCatalog.get_local_points(CourseCatalog.PINE_ID)
	if _ride_points.is_empty():
		_ride_points = CourseCatalog.get_local_riding_points(CourseCatalog.PINE_ID)
	_track_width = CourseCatalog.get_track_width(CourseCatalog.PINE_ID)
	if _alternate_ride_trails.size() == _alternate_trails.size():
		return
	_alternate_ride_trails.clear()
	for index: int in _alternate_trails.size():
		var alternate_route := CourseSpline.bake_motocross(
			_alternate_trails[index], 2.4, 1.35, 0.22, TERRAIN_SEED + 47 + index * 19
		)
		_alternate_ride_trails.append(_weld_alternate_endpoints(alternate_route))


func _weld_alternate_endpoints(alternate_route: PackedVector3Array) -> PackedVector3Array:
	# Main and alternate splines use independent rhythm relief. Without a weld,
	# their shared control point can still diverge by almost a metre just inside
	# the tapered endpoint, leaving a narrow raised wedge across the race line.
	# Follow the main ribbon while their collision widths overlap, then blend back
	# to the authored branch height only after the paths have separated.
	if alternate_route.size() < 2 or _ride_points.size() < 2:
		return alternate_route
	var welded := alternate_route.duplicate()
	var distances := PackedFloat32Array()
	distances.resize(welded.size())
	for index: int in range(1, welded.size()):
		distances[index] = distances[index - 1] + welded[index - 1].distance_to(welded[index])
	var route_length := float(distances[-1])
	var weld_finish := ALTERNATE_WELD_CORE_LENGTH + ALTERNATE_WELD_BLEND_LENGTH
	for index: int in welded.size():
		var endpoint_distance := minf(float(distances[index]), route_length - float(distances[index]))
		if endpoint_distance >= weld_finish:
			continue
		var projection := CourseSpline.project_route(_ride_points, welded[index])
		if projection.is_empty():
			continue
		var main_weight := 1.0 - smoothstep(
			ALTERNATE_WELD_CORE_LENGTH, weld_finish, endpoint_distance
		)
		var point := welded[index]
		point.y = lerpf(point.y, (projection[&"position"] as Vector3).y, main_weight)
		welded[index] = point
	return welded


func _finish_profiled_phase(phase: StringName, begin_usec: int, enabled: bool) -> int:
	var finish_usec := Time.get_ticks_usec()
	if enabled:
		print("PINE BUILD PHASE: %s %.3fs" % [String(phase), float(finish_usec - begin_usec) / 1_000_000.0])
	return finish_usec


func _attach_course_dressing() -> void:
	var expected_signature := CourseDressingBuilder.build_signature(
		CourseCatalog.PINE_ID,
		_ride_points,
		_track_width
	)
	var force_live_build := OS.get_environment("RIDING_DIRTY_FORCE_LIVE_DRESSING") == "1"
	var baked: Node3D = null
	if not force_live_build:
		baked = PINE_COURSE_DRESSING_SCENE.instantiate() as Node3D
	if (
		baked != null
		and int(baked.get_meta(&"dressing_build_signature", -1)) == expected_signature
		and int(baked.get_meta(&"dressing_bake_schema", -1))
			== CourseDressingBuilder.BAKE_SCHEMA_VERSION
	):
		baked.set_meta(&"loaded_from_baked_asset", true)
		add_child(baked)
		return
	if baked != null:
		baked.free()
	if not force_live_build:
		push_warning(
			"Pine course-dressing bake is stale; rebuilding from the authoritative route. "
			+ "Run pine_dressing_asset_bake.tscn before release."
		)
	CourseDressingBuilder.build(
		self,
		CourseCatalog.PINE_ID,
		_ride_points,
		_track_width,
		Callable(self, &"_terrain_height_at")
	)


func get_authoritative_route_world() -> PackedVector3Array:
	var world_route := _ride_points.duplicate()
	for index: int in world_route.size():
		world_route[index] = _race_point_to_world(world_route[index])
	return world_route


func get_racecraft_network_world() -> Array[Dictionary]:
	## Returns defensive records for the two physical Pine skill lines. The main
	## spline remains authoritative; entry/exit chainage only describes how each
	## legal branch rejoins that timing line.
	_ensure_course_routes()
	var main_route := get_authoritative_route_world()
	var records: Array[Dictionary] = []
	for index: int in _alternate_ride_trails.size():
		var world_points := _alternate_ride_trails[index].duplicate()
		for point_index: int in world_points.size():
			world_points[point_index] = _race_point_to_world(world_points[point_index])
		if world_points.size() < 2:
			continue
		var entry_projection := CourseSpline.project_route(main_route, world_points[0])
		var exit_projection := CourseSpline.project_route(main_route, world_points[-1])
		if entry_projection.is_empty() or exit_projection.is_empty():
			continue
		var line_id := StringName("PINE_SKILL_%02d" % (index + 1))
		var entry := {
			&"main_chainage": float(entry_projection.get(&"chainage", 0.0)),
			&"main_segment": int(entry_projection.get(&"segment", -1)),
			&"main_fraction": float(entry_projection.get(&"fraction", 0.0)),
			&"main_position": entry_projection.get(&"position", world_points[0]),
			&"branch_position": world_points[0],
		}
		var exit := {
			&"main_chainage": float(exit_projection.get(&"chainage", 0.0)),
			&"main_segment": int(exit_projection.get(&"segment", -1)),
			&"main_fraction": float(exit_projection.get(&"fraction", 0.0)),
			&"main_position": exit_projection.get(&"position", world_points[-1]),
			&"branch_position": world_points[-1],
		}
		records.append({
			&"line_id": line_id,
			&"points": world_points,
			&"width": ALTERNATE_TRAIL_WIDTH,
			&"shoulder_margin": ALTERNATE_SHOULDER_MARGIN,
			&"warning_margin": 0.75,
			&"entry_main_chainage": float(entry[&"main_chainage"]),
			&"exit_main_chainage": float(exit[&"main_chainage"]),
			&"entry_main_segment": int(entry[&"main_segment"]),
			&"exit_main_segment": int(exit[&"main_segment"]),
			&"entry": entry,
			&"exit": exit,
		})
	return records


func _race_point_to_world(point: Vector3) -> Vector3:
	# Runtime callers use the complete inherited transform. Focused data probes can
	# also query an unattached builder without asking Node3D for an invalid global.
	return global_transform * point if is_inside_tree() else transform * point


func _physical_surface_centerline() -> PackedVector3Array:
	# The timed route remains the sole race/map authority. Extend only the welded
	# physical ribbon so both timed endpoints are interior rows with full-width
	# support, instead of numerically ambiguous open concave-mesh boundaries.
	var surface := _ride_points.duplicate()
	if surface.size() < 2 or _track_points.size() < 2:
		return surface
	var start_tangent := (_track_points[1] - _track_points[0]).normalized()
	var end_tangent := (_track_points[-1] - _track_points[-2]).normalized()
	surface.insert(0, surface[0] - start_tangent * MAIN_RIBBON_RUNOFF_LENGTH)
	surface.append(surface[-1] + end_tangent * MAIN_RIBBON_RUNOFF_LENGTH)
	return surface


func _create_materials() -> void:
	_materials[&"forest_floor"] = _material(Color("2d392a"), 1.0)
	_materials[&"terrain"] = _material(Color("354635"), 1.0)
	_materials[&"trail"] = _material(Color("39271e"), 1.0)
	_materials[&"trail_edge"] = _material(Color("75664f"), 0.98)
	_materials[&"rut"] = _material(Color("281d18"), 1.0)
	_materials[&"moss"] = _material(Color("40563b"), 0.98)
	_materials[&"bark"] = _material(Color("443126"), 1.0)
	_materials[&"pine"] = _material(Color("274a36"), 0.96)
	_materials[&"pine"].vertex_color_use_as_albedo = true
	_materials[&"pine_light"] = _material(Color("3d6745"), 0.95)
	_materials[&"wood"] = _material(Color("755037"), 0.9)
	_materials[&"roof"] = _material(Color("29343a"), 0.62, 0.35)
	_materials[&"water"] = _material(Color(0.12, 0.42, 0.5, 0.68), 0.18)
	_materials[&"marker"] = _material(Color("e6b23d"), 0.55)
	_apply_pine_surface(
		&"trail",
		_materials[&"trail"],
		PackedColorArray([Color("211713"), Color("39271e"), Color("59402f"), Color("2b2019")]),
		TERRAIN_SEED + 11,
		0.026,
		0.84
	)
	_apply_pine_surface(
		&"moss",
		_materials[&"moss"],
		PackedColorArray([Color("283827"), Color("40573a"), Color("61764c")]),
		TERRAIN_SEED + 17,
		0.03,
		0.72
	)
	_apply_pine_surface(
		&"trail_edge",
		_materials[&"trail_edge"],
		PackedColorArray([Color("574b3b"), Color("75664f"), Color("938064")]),
		TERRAIN_SEED + 19,
		0.035,
		0.76
	)
	_apply_pine_surface(
		&"terrain",
		_materials[&"terrain"],
		PackedColorArray([Color("223025"), Color("354936"), Color("526247"), Color("2b3c30")]),
		TERRAIN_SEED + 23,
		0.018,
		0.64
	)


func _apply_pine_surface(
	asset_name: StringName,
	material: StandardMaterial3D,
	colors: PackedColorArray,
	seed: int,
	frequency: float,
	uv_scale: float
) -> void:
	var textures: Dictionary = {}
	for map_name: StringName in [&"albedo", &"normal", &"roughness"]:
		var path := "%s/%s_%s.res" % [PINE_SURFACE_ASSET_DIRECTORY, String(asset_name), String(map_name)]
		var texture := load(path) as Texture2D
		if texture == null:
			SurfaceTextureFactory.apply(material, colors, seed, frequency, uv_scale)
			return
		textures[map_name] = texture
	SurfaceTextureFactory.apply_texture_set(material, textures, uv_scale)


func _build_environment() -> void:
	var world_environment := WorldEnvironment.new()
	world_environment.name = "PineWorldEnvironment"
	var environment := Environment.new()
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("163d56")
	sky_material.sky_horizon_color = Color("a4b9a7")
	sky_material.ground_bottom_color = Color("17251f")
	sky_material.ground_horizon_color = Color("4b654d")
	sky_material.sky_curve = 0.14
	sky_material.ground_curve = 0.1
	sky_material.sky_energy_multiplier = 0.96
	sky_material.ground_energy_multiplier = 0.54
	sky_material.sun_angle_max = 13.0
	sky_material.sun_curve = 0.095
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("4c665a")
	environment.ambient_light_energy = 0.4
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 0.96
	environment.fog_enabled = true
	environment.fog_light_color = Color("86a594")
	environment.fog_light_energy = 0.26
	environment.fog_density = 0.0023
	environment.fog_height = 4.0
	environment.fog_height_density = 0.05
	environment.fog_sky_affect = 0.34
	world_environment.environment = environment
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.name = "PineSun"
	sun.rotation_degrees = Vector3(-32.0, 28.0, 0.0)
	sun.light_color = Color("f0e6bf")
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_max_distance = 380.0
	add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.name = "PineSkyFill"
	fill.rotation_degrees = Vector3(36.0, 150.0, 0.0)
	fill.light_color = Color("55748f")
	fill.light_energy = 0.16
	fill.shadow_enabled = false
	add_child(fill)


func _build_ground() -> void:
	# A textured bedrock layer closes the entire district beneath the sculpted
	# terrain. It is normally hidden, but makes even a collision seam landable.
	var catch_floor := _add_static_box("PineCatchFloor", Vector3(920.0, 1.0, 820.0), Vector3(0.0, 0.0, 0.0), &"forest_floor")
	_tag_surface(catch_floor, &"LOAM", 1.08, 1.24)
	_add_static_box("NorthRidge", Vector3(800.0, 34.0, 14.0), Vector3(0.0, 14.0, -356.0), &"moss", Vector3(0.0, 0.0, -0.025))
	_add_static_box("SouthRidge", Vector3(800.0, 30.0, 14.0), Vector3(0.0, 12.0, 356.0), &"moss", Vector3(0.0, 0.0, 0.025))
	_add_static_box("EastRidge", Vector3(14.0, 38.0, 700.0), Vector3(406.0, 16.0, 0.0), &"moss", Vector3(0.0, 0.0, 0.025))
	_add_static_box("WestRidge", Vector3(14.0, 38.0, 700.0), Vector3(-406.0, 16.0, 0.0), &"moss", Vector3(0.0, 0.0, -0.025))


func _build_trail() -> void:
	_main_route_surface = CourseSurfaceBuilder.build(
		self,
		"PineEnduroRibbon",
		_physical_surface_centerline(),
		_track_width,
		_materials[&"trail"],
		_materials[&"trail_edge"],
		_materials[&"rut"],
		&"LOAM",
		1.08,
		1.38,
		_main_surface_config()
	)
	_mark_authoritative_track_surface(_main_route_surface, CourseCatalog.PINE_ID)
	_main_route_surface.set_meta(&"endpoint_runoff_length", MAIN_RIBBON_RUNOFF_LENGTH)
	for index: int in _alternate_ride_trails.size():
		var alternate_surface := CourseSurfaceBuilder.build(
			self,
			"PineAlternate%02d" % index,
			_alternate_ride_trails[index],
			ALTERNATE_TRAIL_WIDTH,
			_materials[&"trail"],
			_materials[&"trail_edge"],
			_materials[&"rut"],
			&"LOAM",
			1.16,
			1.45,
			_alternate_surface_config()
		)
		# Alternate ribbons are physical, authored branches of the same course.
		# Keeping them on the AI query layer without the matching authority tag made
		# a ray that touched a branch return no support at all, even where it merged
		# back across the official line.
		alternate_surface.set_meta(&"alternate_ride_surface", true)
		_mark_authoritative_track_surface(alternate_surface, CourseCatalog.PINE_ID)


func _main_surface_config() -> Dictionary:
	return {
		&"maximum_bank_degrees": 8.5,
		&"bank_strength": 0.5,
		&"berm_height": 1.85,
		&"shoulder_width": MAIN_SHOULDER_WIDTH,
		# Broad takeoffs retain full center height, then use four metres per side
		# to merge into the recovery lanes without a capsule-catching drop.
		&"overlay_lateral_blend_width": 4.0,
		&"rut_offset": 0.98,
		&"rut_depth": 0.065,
		&"casts_shadow": false,
	}


func _alternate_surface_config() -> Dictionary:
	return {
		&"maximum_bank_degrees": 10.0,
		&"bank_strength": 0.58,
		&"berm_height": 1.45,
		&"shoulder_width": ALTERNATE_SHOULDER_MARGIN,
		&"rut_offset": 0.72,
		&"rut_depth": 0.075,
		&"endpoint_taper_length": 10.0,
		&"endpoint_minimum_width_ratio": 0.06,
		&"endpoint_surface_lift": 0.055,
		&"casts_shadow": false,
	}


func _cached_main_surface_frames() -> Array[Dictionary]:
	if _terrain_surface_profiles.is_empty():
		return []
	var frames: Array[Dictionary] = _terrain_surface_profiles[0].get(&"frames", [])
	return frames


func _build_creek_crossing() -> void:
	var creek_start := Vector3(280.0, 28.6, 211.0)
	var creek_end := Vector3(390.0, 28.6, 169.0)
	var creek := BoxMesh.new()
	creek.size = Vector3(creek_start.distance_to(creek_end), 0.06, 10.0)
	var creek_mesh := MeshInstance3D.new()
	creek_mesh.name = "Creek"
	creek_mesh.mesh = creek
	creek_mesh.position = creek_start.lerp(creek_end, 0.5)
	creek_mesh.rotation.y = atan2(creek_start.z - creek_end.z, creek_end.x - creek_start.x)
	creek_mesh.material_override = _materials[&"water"]
	add_child(creek_mesh)

	var bridge_start_target := _track_points[5].lerp(_track_points[6], 0.34)
	var bridge_end_target := _track_points[5].lerp(_track_points[6], 0.66)
	var bridge_start_index := CourseSpline.closest_index(_ride_points, bridge_start_target)
	var bridge_end_index := CourseSpline.closest_index(_ride_points, bridge_end_target)
	if bridge_start_index > bridge_end_index:
		var swap := bridge_start_index
		bridge_start_index = bridge_end_index
		bridge_end_index = swap
	var bridge_center_index := floori(float(bridge_start_index + bridge_end_index) * 0.5)
	var bridge_length := 0.0
	for route_index: int in range(bridge_start_index, bridge_end_index):
		bridge_length += _ride_points[route_index].distance_to(_ride_points[route_index + 1])
	var bridge_width := _track_width - 2.0
	var bridge_frames := _cached_main_surface_frames()
	var bridge := CourseSurfaceBuilder.build_additive_overlay(
		self, "LogBridge", _ride_points, _track_width, bridge_width,
		bridge_center_index, bridge_length, 0.0, true,
		_materials[&"wood"], &"WOOD", 0.86, 0.12,
		_main_surface_config(), 0.10, bridge_frames
	)
	_mark_authoritative_track_surface(bridge, CourseCatalog.PINE_ID)
	bridge.set_meta(&"bridge_width", bridge_width)
	bridge.set_meta(&"route_index", bridge_center_index)
	var plank := BoxMesh.new()
	plank.size = Vector3(bridge_width + 0.4, 0.075, 0.34)
	plank.material = _materials[&"wood"]
	var plank_multimesh := MultiMesh.new()
	plank_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	plank_multimesh.mesh = plank
	plank_multimesh.instance_count = 11
	var bridge_plank_transforms: Array[Transform3D] = []
	var deck_start_index := int(bridge.get_meta(&"overlay_start_index", bridge_start_index))
	var deck_end_index := int(bridge.get_meta(&"overlay_end_index", bridge_end_index))
	for plank_index: int in 11:
		# Keep the plank box half-length inside the open deck ends.
		var route_weight := lerpf(0.04, 0.96, float(plank_index) / 10.0)
		var route_index := clampi(
			roundi(lerpf(float(deck_start_index), float(deck_end_index), route_weight)),
			deck_start_index,
			deck_end_index
		)
		var plank_transform := CourseSurfaceBuilder.overlay_surface_transform(
			_ride_points, _track_width, _main_surface_config(), route_index, 0.10, bridge_frames
		)
		plank_transform.origin += plank_transform.basis.y * 0.055
		plank_multimesh.set_instance_transform(plank_index, plank_transform)
		bridge_plank_transforms.append(plank_transform)
	bridge.set_meta(&"bridge_plank_transforms", bridge_plank_transforms)
	var planks := MultiMeshInstance3D.new()
	planks.name = "BridgePlanks"
	planks.multimesh = plank_multimesh
	bridge.add_child(planks)


func _build_jumps() -> void:
	# Every major control-point interval now carries a broad, paired flight line.
	# At this course scale that produces a readable 100-150 m major cadence with
	# full-width recovery lanes beside each face and a downhill receiver after it.
	var send_width := _track_width - 2.0
	var landing_width := _track_width - 1.0
	_add_trail_ramp("RootRise", _track_points[0], _track_points[1], 0.62, 10.0, send_width, 2.55, true)
	_add_trail_ramp("RootLanding", _track_points[0], _track_points[1], 0.76, 11.8, landing_width, 2.05, false)
	_add_trail_ramp("GraniteRiseSend", _track_points[1], _track_points[2], 0.32, 10.2, send_width, 2.55, true)
	_add_trail_ramp("GraniteRiseLanding", _track_points[1], _track_points[2], 0.53, 12.2, landing_width, 2.05, false)
	_add_trail_ramp("FernHollowSend", _track_points[2], _track_points[3], 0.28, 9.8, send_width, 2.4, true)
	_add_trail_ramp("FernHollowLanding", _track_points[2], _track_points[3], 0.5, 11.8, landing_width, 1.95, false)
	_add_trail_ramp("MeadowFlySend", _track_points[3], _track_points[4], 0.3, 10.4, send_width, 2.6, true)
	_add_trail_ramp("MeadowFlyLanding", _track_points[3], _track_points[4], 0.52, 12.4, landing_width, 2.1, false)
	_add_trail_ramp("MossBankSend", _track_points[4], _track_points[5], 0.31, 10.0, send_width, 2.45, true)
	_add_trail_ramp("MossBankLanding", _track_points[4], _track_points[5], 0.53, 12.0, landing_width, 2.0, false)
	_add_trail_ramp("ValleyKickerSend", _track_points[5], _track_points[6], 0.28, 10.2, send_width, 2.5, true)
	_add_trail_ramp("ValleyKickerLanding", _track_points[5], _track_points[6], 0.51, 12.2, landing_width, 2.05, false)
	_add_trail_ramp("PineNeedleSend", _track_points[6], _track_points[7], 0.29, 10.2, send_width, 2.5, true)
	_add_trail_ramp("PineNeedleLanding", _track_points[6], _track_points[7], 0.51, 12.0, landing_width, 2.0, false)
	_add_trail_ramp("HighCountrySend", _track_points[7], _track_points[8], 0.32, 10.5, send_width, 2.7, true)
	_add_trail_ramp("HighCountryLanding", _track_points[7], _track_points[8], 0.53, 12.5, landing_width, 2.2, false)
	_add_trail_ramp("CreekDoubleSend", _track_points[8], _track_points[9], 0.34, 10.5, send_width, 2.8, true)
	_add_trail_ramp("CreekDoubleLanding", _track_points[8], _track_points[9], 0.49, 12.0, landing_width, 2.2, false)
	_add_trail_ramp("RidgelineSend", _track_points[9], _track_points[10], 0.3, 10.4, send_width, 2.65, true)
	_add_trail_ramp("RidgelineLanding", _track_points[9], _track_points[10], 0.52, 12.4, landing_width, 2.15, false)
	_add_trail_ramp("CedarCrestSend", _track_points[10], _track_points[11], 0.3, 10.0, send_width, 2.45, true)
	_add_trail_ramp("CedarCrestLanding", _track_points[10], _track_points[11], 0.52, 12.0, landing_width, 2.0, false)
	_add_trail_ramp("RidgeTransferSend", _track_points[11], _track_points[12], 0.31, 10.5, send_width, 2.7, true)
	_add_trail_ramp("RidgeTransferLanding", _track_points[11], _track_points[12], 0.53, 12.5, landing_width, 2.2, false)
	_add_trail_ramp("FireRoadSend", _track_points[12], _track_points[13], 0.3, 10.2, send_width, 2.55, true)
	_add_trail_ramp("FireRoadLanding", _track_points[12], _track_points[13], 0.52, 12.2, landing_width, 2.05, false)
	_add_trail_ramp("SummitKick", _track_points[13], _track_points[14], 0.33, 11.0, send_width, 3.05, true)
	_add_trail_ramp("SummitLanding", _track_points[13], _track_points[14], 0.46, 12.5, landing_width, 2.4, false)
	_add_trail_ramp("LookoutFlightSend", _track_points[14], _track_points[15], 0.3, 10.6, send_width, 2.75, true)
	_add_trail_ramp("LookoutFlightLanding", _track_points[14], _track_points[15], 0.52, 12.6, landing_width, 2.25, false)
	_add_trail_ramp("AlpineDropSend", _track_points[15], _track_points[16], 0.28, 10.6, send_width, 2.7, true)
	_add_trail_ramp("AlpineDropLanding", _track_points[15], _track_points[16], 0.51, 12.4, landing_width, 2.2, false)
	_add_trail_ramp("AspenGapSend", _track_points[16], _track_points[17], 0.3, 10.5, send_width, 2.7, true)
	_add_trail_ramp("AspenGapLanding", _track_points[16], _track_points[17], 0.52, 12.5, landing_width, 2.2, false)
	_add_trail_ramp("RavineTakeoff", _track_points[17], _track_points[18], 0.26, 11.2, send_width, 3.15, true)
	_add_trail_ramp("RavineLanding", _track_points[17], _track_points[18], 0.52, 13.0, landing_width, 2.6, false)
	_add_trail_ramp("ShadowGapSend", _track_points[18], _track_points[19], 0.3, 10.6, send_width, 2.75, true)
	_add_trail_ramp("ShadowGapLanding", _track_points[18], _track_points[19], 0.52, 12.6, landing_width, 2.25, false)
	_add_trail_ramp("NorthSlopeSend", _track_points[19], _track_points[20], 0.3, 10.2, send_width, 2.55, true)
	_add_trail_ramp("NorthSlopeLanding", _track_points[19], _track_points[20], 0.52, 12.2, landing_width, 2.05, false)
	_add_trail_ramp("TimberlineSend", _track_points[20], _track_points[21], 0.34, 10.0, send_width, 2.65, true)
	_add_trail_ramp("TimberlineLanding", _track_points[20], _track_points[21], 0.48, 11.8, landing_width, 2.15, false)
	_add_trail_ramp("LoggingRoadSend", _track_points[21], _track_points[22], 0.31, 10.3, send_width, 2.6, true)
	_add_trail_ramp("LoggingRoadLanding", _track_points[21], _track_points[22], 0.53, 12.3, landing_width, 2.1, false)
	_add_trail_ramp("HomeRunSend", _track_points[22], _track_points[23], 0.27, 9.8, send_width, 2.4, true)
	_add_trail_ramp("HomeRunLanding", _track_points[22], _track_points[23], 0.5, 11.8, landing_width, 1.95, false)


func _build_forest() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42017
	var positions: Array[Vector3] = []
	var attempts := 0
	while positions.size() < 950 and attempts < 11000:
		attempts += 1
		var candidate := Vector3(rng.randf_range(-382.0, 382.0), 0.0, rng.randf_range(-332.0, 332.0))
		# Keep a full chase-camera corridor clear around main and alternate trails.
		if _distance_to_trail(candidate) < _track_width * 0.5 + 6.0:
			continue
		if candidate.distance_to(_track_points[0]) < 16.0:
			continue
		candidate.y = _terrain_height_at(candidate.x, candidate.z)
		positions.append(candidate)

	var trunk_mesh := _create_detailed_pine_trunk_mesh()
	var canopy_mesh := _create_detailed_pine_canopy_mesh()
	_add_multimesh_partitioned("ForestTrunks", trunk_mesh, positions, 2.5, false, rng)
	_add_multimesh_partitioned("ForestCanopies", canopy_mesh, positions, 6.7, true, rng)

	for collision_index: int in mini(positions.size(), 80):
		var tree_position := positions[collision_index * 11 % positions.size()]
		var body := StaticBody3D.new()
		body.name = "TreeCollision%02d" % collision_index
		body.collision_layer = 2
		body.collision_mask = 1
		body.position = tree_position + Vector3.UP * 2.5
		_tag_surface(body, &"BARK", 1.18, 0.04)
		add_child(body)
		var shape := CylinderShape3D.new()
		shape.radius = 0.48
		shape.height = 5.0
		var collision := CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)


func _create_detailed_pine_trunk_mesh() -> ArrayMesh:
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.27
	trunk.bottom_radius = 0.5
	trunk.height = 5.0
	trunk.radial_segments = 8
	surface_tool.append_from(trunk, 0, Transform3D.IDENTITY)
	for branch_index: int in 6:
		var angle := TAU * float(branch_index) / 6.0 + float(branch_index % 2) * 0.34
		var start := Vector3(0.0, -1.45 + branch_index * 0.48, 0.0)
		var end := start + Vector3(sin(angle), 0.14, cos(angle)) * (0.85 + float(branch_index % 3) * 0.12)
		_append_cylinder_between(surface_tool, start, end, 0.065, 6)
	var mesh := surface_tool.commit()
	mesh.surface_set_material(0, _materials[&"bark"])
	return mesh


func _create_detailed_pine_canopy_mesh() -> ArrayMesh:
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tier_data: Array[Dictionary] = [
		{&"bottom": 2.55, &"height": 3.8, &"y": -2.0},
		{&"bottom": 2.05, &"height": 3.4, &"y": -0.15},
		{&"bottom": 1.5, &"height": 3.0, &"y": 1.55},
	]
	for tier: Dictionary in tier_data:
		var canopy := CylinderMesh.new()
		canopy.top_radius = 0.08
		canopy.bottom_radius = float(tier[&"bottom"])
		canopy.height = float(tier[&"height"])
		canopy.radial_segments = 9
		surface_tool.append_from(canopy, 0, Transform3D(Basis.IDENTITY, Vector3(0.0, float(tier[&"y"]), 0.0)))
	var mesh := surface_tool.commit()
	mesh.surface_set_material(0, _materials[&"pine"])
	return mesh


func _append_cylinder_between(surface_tool: SurfaceTool, start: Vector3, end: Vector3, radius: float, segments: int) -> void:
	var direction := end - start
	if direction.length_squared() < 0.0001:
		return
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius * 0.72
	cylinder.bottom_radius = radius
	cylinder.height = direction.length()
	cylinder.radial_segments = segments
	var basis := Basis(Quaternion(Vector3.UP, direction.normalized()))
	surface_tool.append_from(cylinder, 0, Transform3D(basis, (start + end) * 0.5))


func _build_landmarks() -> void:
	# Ranger cabin creates a recognizable first-sector landmark.
	var cabin_ground := _terrain_height_at(-238.0, 252.0)
	_add_static_box("Cabin", Vector3(9.0, 4.5, 7.0), Vector3(-238.0, cabin_ground + 2.25, 252.0), &"wood")
	_add_visual_box("CabinRoof", Vector3(11.0, 0.55, 8.5), Vector3(-238.0, cabin_ground + 5.0, 252.0), &"roof", Vector3(0.0, 0.0, 0.13))
	_add_visual_box("CabinDoor", Vector3(2.0, 2.9, 0.12), Vector3(-238.0, cabin_ground + 1.5, 248.45), &"bark")
	_add_visual_box("CabinWindow", Vector3(2.2, 1.4, 0.12), Vector3(-234.8, cabin_ground + 2.6, 248.45), &"water")

	# Trailhead arch and timber stacks make the start area legible.
	var trailhead_ground := _terrain_height_at(-350.0, 309.0)
	_add_visual_box("TrailheadLeft", Vector3(0.5, 4.2, 0.5), Vector3(-355.2, trailhead_ground + 2.1, 309.0), &"wood")
	_add_visual_box("TrailheadRight", Vector3(0.5, 4.2, 0.5), Vector3(-344.8, trailhead_ground + 2.1, 309.0), &"wood")
	_add_visual_box("TrailheadTop", Vector3(10.9, 0.55, 0.55), Vector3(-350.0, trailhead_ground + 4.1, 309.0), &"marker")

	# A compact ranger lookout silhouettes the 100-meter summit.
	# Keep the whole structure beyond the recovery shoulder and containment line;
	# its old position consumed most of the otherwise-clear outside shoulder.
	var lookout_anchor := Vector3(24.0, 0.0, -11.0)
	var lookout_ground := _terrain_height_at(lookout_anchor.x, lookout_anchor.z)
	_add_static_box("SummitLookout", Vector3(5.5, 3.2, 5.5), lookout_anchor + Vector3.UP * (lookout_ground + 1.6), &"wood")
	_add_visual_box("LookoutRoof", Vector3(7.0, 0.45, 7.0), lookout_anchor + Vector3.UP * (lookout_ground + 3.5), &"roof")
	for log_index: int in 6:
		var log := CylinderMesh.new()
		log.top_radius = 0.42
		log.bottom_radius = 0.42
		log.height = 6.0
		log.radial_segments = 8
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = "Timber%d" % log_index
		mesh_instance.mesh = log
		var timber_x := -331.0 + float(log_index % 3) * 0.95
		var timber_z := -306.0
		mesh_instance.position = Vector3(timber_x, _terrain_height_at(timber_x, timber_z) + 0.5 + log_index / 3 * 0.72, timber_z)
		mesh_instance.rotation.z = PI * 0.5
		mesh_instance.material_override = _materials[&"wood"]
		add_child(mesh_instance)
	for prop_index: int in 7:
		var crate_x := -370.0 + float(prop_index % 4) * 1.35
		var crate_z := 286.0
		_add_breakaway_crate("BreakawayCrate%02d" % prop_index, Vector3(crate_x, _terrain_height_at(crate_x, crate_z) + 0.55 + float(prop_index / 4) * 1.1, crate_z))


func _build_trail_spectators() -> void:
	var positions: Array[Vector3] = [Vector3(-360.0, 0.0, 310.0), Vector3(-356.0, 0.0, 313.0), Vector3(-148.0, 0.0, 181.0), Vector3(-142.0, 0.0, 184.0), Vector3(360.0, 0.0, -134.0), Vector3(18.0, 0.0, -14.0)]
	for index: int in positions.size():
		positions[index].y = _terrain_height_at(positions[index].x, positions[index].z)
		var root := Node3D.new()
		root.name = "TrailSpectator%02d" % index
		root.position = positions[index]
		add_child(root)
		var jacket := StandardMaterial3D.new()
		jacket.albedo_color = Color.from_hsv(0.05 + index * 0.12, 0.58, 0.82)
		jacket.roughness = 0.9
		var torso := BoxMesh.new()
		torso.size = Vector3(0.5, 0.75, 0.32)
		var torso_mesh := MeshInstance3D.new()
		torso_mesh.mesh = torso
		torso_mesh.position.y = 1.08
		torso_mesh.material_override = jacket
		root.add_child(torso_mesh)
		var head := SphereMesh.new()
		head.radius = 0.22
		head.height = 0.44
		head.radial_segments = 8
		head.rings = 5
		var head_mesh := MeshInstance3D.new()
		head_mesh.mesh = head
		head_mesh.position.y = 1.69
		head_mesh.material_override = _materials[&"marker"]
		root.add_child(head_mesh)


func _add_multimesh_partitioned(
	node_name: String,
	mesh: Mesh,
	positions: Array[Vector3],
	height: float,
	vary_color: bool,
	rng: RandomNumberGenerator
) -> void:
	var buckets: Array[Array] = [[], [], [], []]
	for position: Vector3 in positions:
		var bucket_index := (1 if position.x >= 0.0 else 0) + (2 if position.z >= 0.0 else 0)
		buckets[bucket_index].append(position)
	for bucket_index: int in buckets.size():
		var bucket_positions: Array[Vector3] = []
		bucket_positions.assign(buckets[bucket_index])
		if not bucket_positions.is_empty():
			_add_multimesh("%s_%d" % [node_name, bucket_index], mesh, bucket_positions, height, vary_color, rng)


func _add_multimesh(
	node_name: String,
	mesh: Mesh,
	positions: Array[Vector3],
	height: float,
	vary_color: bool,
	rng: RandomNumberGenerator
) -> void:
	var bucket_center := Vector3.ZERO
	for position: Vector3 in positions:
		bucket_center += position
	bucket_center /= float(maxi(positions.size(), 1))
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = vary_color
	multimesh.mesh = mesh
	multimesh.instance_count = positions.size()
	for index: int in positions.size():
		var scale_value := rng.randf_range(0.78, 1.24)
		var basis := Basis.from_euler(Vector3(0.0, rng.randf_range(0.0, TAU), 0.0)).scaled(Vector3(scale_value, scale_value, scale_value))
		multimesh.set_instance_transform(index, Transform3D(basis, positions[index] - bucket_center + Vector3.UP * height * scale_value))
		if vary_color:
			multimesh.set_instance_color(index, Color(0.78 + rng.randf() * 0.18, 0.86 + rng.randf() * 0.12, 0.76 + rng.randf() * 0.16, 1.0))
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multimesh
	instance.position = bucket_center
	add_child(instance)


func _add_trail_segment(start: Vector3, end: Vector3, width: float) -> void:
	var delta := end - start
	if delta.length_squared() < 0.01:
		return
	var direction := delta.normalized()
	var basis := Basis.looking_at(direction, Vector3.UP)
	var body := StaticBody3D.new()
	body.name = "LoamTrailSegment"
	body.collision_layer = 2
	body.collision_mask = 1
	body.transform = Transform3D(basis, (start + end) * 0.5 - basis.y * (TRACK_THICKNESS * 0.5))
	_tag_surface(body, &"LOAM", 1.04, 1.34)
	add_child(body)

	var trail_mesh := BoxMesh.new()
	trail_mesh.size = Vector3(width, TRACK_THICKNESS, delta.length() + 1.3)
	var trail := MeshInstance3D.new()
	trail.name = "TrailSegment"
	trail.mesh = trail_mesh
	trail.material_override = _materials[&"trail"]
	body.add_child(trail)
	var shape := BoxShape3D.new()
	shape.size = trail_mesh.size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)

	for side: float in [-1.0, 1.0]:
		var rut_mesh := BoxMesh.new()
		rut_mesh.size = Vector3(0.28, 0.028, delta.length() * 0.95)
		var rut := MeshInstance3D.new()
		rut.name = "TrailRut"
		rut.mesh = rut_mesh
		rut.position = Vector3(side * minf(1.55, width * 0.3), TRACK_THICKNESS * 0.52, 0.0)
		rut.material_override = _materials[&"rut"]
		body.add_child(rut)


func _add_sloped_surface(
	body_name: String,
	start: Vector3,
	end: Vector3,
	width: float,
	thickness: float,
	material_key: StringName,
	surface: StringName,
	roughness: float,
	roost: float
) -> StaticBody3D:
	var delta := end - start
	var basis := Basis.looking_at(delta.normalized(), Vector3.UP)
	var body := StaticBody3D.new()
	body.name = body_name
	body.collision_layer = 2
	body.collision_mask = 1
	body.transform = Transform3D(basis, (start + end) * 0.5 - basis.y * (thickness * 0.5))
	_tag_surface(body, surface, roughness, roost)
	add_child(body)
	var box := BoxMesh.new()
	box.size = Vector3(width, thickness, delta.length() + 0.4)
	var visual := MeshInstance3D.new()
	visual.mesh = box
	visual.material_override = _materials[material_key]
	body.add_child(visual)
	var collision := CollisionShape3D.new()
	# Only the bridge deck is physical. The visible 0.26 m fascia has no front,
	# rear, side, or underside collision edge that could catch a wheel.
	var half_width := width * 0.5
	var half_length := (delta.length() + 0.4) * 0.5
	var top_y := thickness * 0.5
	var faces := PackedVector3Array([
		Vector3(-half_width, top_y, -half_length),
		Vector3(half_width, top_y, -half_length),
		Vector3(half_width, top_y, half_length),
		Vector3(-half_width, top_y, -half_length),
		Vector3(half_width, top_y, half_length),
		Vector3(-half_width, top_y, half_length),
	])
	var deck_shape := ConcavePolygonShape3D.new()
	deck_shape.backface_collision = false
	deck_shape.set_faces(faces)
	collision.shape = deck_shape
	body.add_child(collision)
	body.set_meta(&"collision_top_only", true)
	body.set_meta(&"open_ride_ends", true)
	body.set_meta(&"bridge_width", width)
	return body


func _distance_to_trail(point: Vector3) -> float:
	var nearest := INF
	var paths := _terrain_query_paths
	if paths.is_empty():
		paths = [_ride_points]
		paths.append_array(_alternate_ride_trails)
	for path: PackedVector3Array in paths:
		for index: int in path.size() - 1:
			nearest = minf(nearest, _distance_to_segment_2d(point, path[index], path[index + 1]))
	return nearest


func _distance_to_segment_2d(point: Vector3, start: Vector3, end: Vector3) -> float:
	var point_2d := Vector2(point.x, point.z)
	var start_2d := Vector2(start.x, start.z)
	var end_2d := Vector2(end.x, end.z)
	var segment := end_2d - start_2d
	var weight := clampf((point_2d - start_2d).dot(segment) / maxf(segment.length_squared(), 0.001), 0.0, 1.0)
	return point_2d.distance_to(start_2d + segment * weight)


func _add_static_box(body_name: String, size: Vector3, position: Vector3, material_key: StringName, rotation: Vector3 = Vector3.ZERO) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = body_name
	body.collision_layer = 2
	body.collision_mask = 1
	body.position = position
	body.rotation = rotation
	add_child(body)
	match material_key:
		&"trail", &"forest_floor", &"moss":
			_tag_surface(body, &"LOAM", 1.04, 1.08)
		&"bark", &"wood":
			_tag_surface(body, &"WOOD", 1.08, 0.08)
		_:
			_tag_surface(body, &"ROCK", 1.12, 0.18)
	var box := BoxMesh.new()
	box.size = size
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = box
	mesh_instance.material_override = _materials[material_key]
	body.add_child(mesh_instance)
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	return body


func _add_visual_box(mesh_name: String, size: Vector3, position: Vector3, material_key: StringName, rotation: Vector3 = Vector3.ZERO) -> void:
	var box := BoxMesh.new()
	box.size = size
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = mesh_name
	mesh_instance.mesh = box
	mesh_instance.position = position
	mesh_instance.rotation = rotation
	mesh_instance.material_override = _materials[material_key]
	add_child(mesh_instance)


func _add_breakaway_crate(body_name: String, position: Vector3) -> void:
	var body := DestructibleProp.new()
	body.name = body_name
	body.mass = 3.2
	body.collision_layer = 2
	body.collision_mask = 1 | 2
	body.position = position
	add_child(body)
	var box := BoxMesh.new()
	box.size = Vector3(1.05, 1.05, 1.05)
	var mesh := MeshInstance3D.new()
	mesh.mesh = box
	mesh.material_override = _materials[&"wood"]
	body.add_child(mesh)
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.05, 1.05, 1.05)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)


func _add_trail_ramp(
	body_name: String,
	segment_start: Vector3,
	segment_end: Vector3,
	weight: float,
	length: float,
	width: float,
	height: float,
	rises_with_travel: bool
) -> void:
	var target := segment_start.lerp(segment_end, weight)
	var route_index := CourseSpline.closest_index(_ride_points, target)
	var ramp := CourseSurfaceBuilder.build_additive_overlay(
		self,
		body_name,
		_ride_points,
		_track_width,
		width,
		route_index,
		length,
		height,
		rises_with_travel,
		_materials[&"trail"],
		&"LOAM",
		1.1,
		1.42,
		_main_surface_config(),
		0.008,
		_cached_main_surface_frames(),
		_materials[&"rut"]
	)
	_mark_authoritative_track_surface(ramp, CourseCatalog.PINE_ID)
	ramp.set_meta(&"route_index", route_index)
	ramp.set_meta(&"rhythm_role", &"TAKEOFF" if rises_with_travel else &"LANDING")
	ramp.set_meta(&"ramp_length", length)
	ramp.set_meta(&"ramp_width", width)
	ramp.set_meta(&"ramp_height", height)
	if rises_with_travel:
		ramp.set_meta(&"race_line_airtime", true)
		ramp.set_meta(&"airtime_takeoff", true)
		ramp.add_to_group(&"race_line_airtime")
		ramp.add_to_group(&"airtime_takeoff")
	else:
		ramp.set_meta(&"race_line_landing", true)


func _add_wedge_ramp(body_name: String, position: Vector3, yaw: float, length: float, width: float, height: float, high_negative_z: bool, alignment: Basis = Basis.IDENTITY) -> StaticBody3D:
	if alignment == Basis.IDENTITY:
		alignment = Basis.from_euler(Vector3(0.0, yaw, 0.0))
	var half_width := width * 0.5
	var half_length := length * 0.5
	var high_z := -half_length if high_negative_z else half_length
	var low_z := half_length if high_negative_z else -half_length
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
	# Leave both travel ends visually and physically open. A receiver's former
	# high fascia read as a full-lane wall even after its collision was removed,
	# making safe under-jumps look like the bike passed through solid terrain.
	surface_tool.generate_normals()
	var body := StaticBody3D.new()
	body.name = body_name
	body.collision_layer = 2
	body.collision_mask = 1
	body.transform = Transform3D(alignment, position)
	_tag_surface(body, &"LOAM", 1.02, 1.42)
	body.set_meta(&"ramp_length", length)
	body.set_meta(&"ramp_width", width)
	body.set_meta(&"ramp_height", height)
	body.set_meta(&"collision_top_only", true)
	body.set_meta(&"open_ride_ends", true)
	if high_negative_z:
		body.set_meta(&"airtime_takeoff", true)
	add_child(body)
	if high_negative_z:
		body.add_to_group(&"airtime_takeoff")
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = surface_tool.commit()
	mesh_instance.material_override = _materials[&"trail"]
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


func _build_terrain_surface_profiles() -> Array[Dictionary]:
	var profiles: Array[Dictionary] = []
	profiles.append(_make_terrain_surface_profile(_ride_points, _track_width, _main_surface_config()))
	# Carve beneath the short physical-only start/finish extensions too. Keep the
	# original race profile first so overlay frame caching and every route index
	# continue to address the unchanged authoritative 3,022-point centerline.
	var physical_surface := _physical_surface_centerline()
	if physical_surface.size() >= 4:
		profiles.append(_make_terrain_surface_profile(
			PackedVector3Array([physical_surface[0], physical_surface[1], physical_surface[2]]),
			_track_width,
			_main_surface_config()
		))
		profiles.append(_make_terrain_surface_profile(
			PackedVector3Array([
				physical_surface[-3], physical_surface[-2], physical_surface[-1]
			]),
			_track_width,
			_main_surface_config()
		))
	for alternate: PackedVector3Array in _alternate_ride_trails:
		profiles.append(_make_terrain_surface_profile(alternate, 4.8, _alternate_surface_config()))
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
	var minimum_xz := Vector2(INF, INF)
	var maximum_xz := Vector2(-INF, -INF)
	if not frames.is_empty():
		query_indices.append(0)
		var last_query_distance: float = frames[0][&"distance"]
		var first_position: Vector3 = frames[0][&"position"]
		minimum_xz = Vector2(first_position.x, first_position.z)
		maximum_xz = minimum_xz
		for index: int in range(1, frames.size()):
			var frame_distance: float = frames[index][&"distance"]
			var previous_position: Vector3 = frames[index - 1][&"position"]
			var frame_position: Vector3 = frames[index][&"position"]
			minimum_xz.x = minf(minimum_xz.x, frame_position.x)
			minimum_xz.y = minf(minimum_xz.y, frame_position.z)
			maximum_xz.x = maxf(maximum_xz.x, frame_position.x)
			maximum_xz.y = maxf(maximum_xz.y, frame_position.z)
			maximum_frame_span = maxf(maximum_frame_span, Vector2(previous_position.x, previous_position.z).distance_to(Vector2(frame_position.x, frame_position.z)))
			if frame_distance - last_query_distance >= TERRAIN_PROFILE_QUERY_SPACING or index == frames.size() - 1:
				query_indices.append(index)
				last_query_distance = frame_distance
	var query_spatial_index := _build_terrain_profile_query_index(frames, query_indices)
	var resolved_frame_span := maxf(maximum_frame_span, 0.1)
	var influence_radius := TERRAIN_CELL_DIAGONAL + resolved_frame_span
	var clearance_bounds_radius := half_width + shoulder_width + influence_radius
	return {
		&"frames": frames,
		&"query_indices": query_indices,
		&"query_spatial_index": query_spatial_index,
		&"width": width,
		&"outer_half_width": half_width + shoulder_width,
		&"offsets": offsets,
		&"heights": heights,
		&"maximum_frame_span": resolved_frame_span,
		# These radii are invariant for the profile. Terrain generation calls the
		# context query thousands of times, so avoid rebuilding them in that loop.
		&"terrain_influence_radius": influence_radius,
		&"clearance_bounds_radius_squared": clearance_bounds_radius * clearance_bounds_radius,
		# Exact centerline bounds let terrain queries reject a profile only when
		# the distance to this rectangle already proves it cannot be the nearest
		# route or influence the ribbon-clearance ceiling. This is especially
		# valuable for Pine's two short alternate trails: most landscape and
		# dressing samples no longer linearly scan both alternates.
		&"minimum_xz": minimum_xz,
		&"maximum_xz": maximum_xz,
	}


func _build_terrain_profile_query_index(
	frames: Array[Dictionary],
	query_indices: PackedInt32Array
) -> Dictionary:
	var buckets: Dictionary = {}
	if frames.size() < 2 or query_indices.size() < 2:
		return {
			&"buckets": buckets,
			&"cell_size": TERRAIN_PROFILE_INDEX_CELL_SIZE,
			&"minimum_cell": Vector2i.ZERO,
			&"maximum_cell": Vector2i.ZERO,
		}
	var minimum_cell := Vector2i(2147483647, 2147483647)
	var maximum_cell := Vector2i(-2147483648, -2147483648)
	for query_segment: int in query_indices.size() - 1:
		var start_position: Vector3 = frames[query_indices[query_segment]][&"position"]
		var end_position: Vector3 = frames[query_indices[query_segment + 1]][&"position"]
		var segment_minimum := Vector2i(
			floori(minf(start_position.x, end_position.x) / TERRAIN_PROFILE_INDEX_CELL_SIZE),
			floori(minf(start_position.z, end_position.z) / TERRAIN_PROFILE_INDEX_CELL_SIZE)
		)
		var segment_maximum := Vector2i(
			floori(maxf(start_position.x, end_position.x) / TERRAIN_PROFILE_INDEX_CELL_SIZE),
			floori(maxf(start_position.z, end_position.z) / TERRAIN_PROFILE_INDEX_CELL_SIZE)
		)
		minimum_cell.x = mini(minimum_cell.x, segment_minimum.x)
		minimum_cell.y = mini(minimum_cell.y, segment_minimum.y)
		maximum_cell.x = maxi(maximum_cell.x, segment_maximum.x)
		maximum_cell.y = maxi(maximum_cell.y, segment_maximum.y)
		for cell_x: int in range(segment_minimum.x, segment_maximum.x + 1):
			for cell_y: int in range(segment_minimum.y, segment_maximum.y + 1):
				var cell := Vector2i(cell_x, cell_y)
				if not buckets.has(cell):
					buckets[cell] = []
				var bucket: Array = buckets[cell]
				bucket.append(query_segment)
	return {
		&"buckets": buckets,
		&"cell_size": TERRAIN_PROFILE_INDEX_CELL_SIZE,
		&"minimum_cell": minimum_cell,
		&"maximum_cell": maximum_cell,
	}


func _terrain_surface_context(x: float, z: float) -> Dictionary:
	var point := Vector2(x, z)
	var nearest: Dictionary = {}
	var nearest_distance := INF
	var nearest_distance_squared := INF
	var clearance_ceiling := INF
	for profile_index: int in _terrain_surface_profiles.size():
		var profile := _terrain_surface_profiles[profile_index]
		var influence_radius: float = profile[&"terrain_influence_radius"]
		# Until a valid profile establishes a nearest distance, every profile can
		# still win. In the normal case the main route is first, which makes its
		# bounds calculation pure overhead. For later profiles, squared distances
		# preserve the exact rejection test without a square root per profile.
		if nearest_distance_squared < INF:
			var bounds_distance_squared := _distance_squared_to_profile_bounds(point, profile)
			var could_be_nearest := bounds_distance_squared < nearest_distance_squared
			var could_affect_clearance := (
				bounds_distance_squared
				<= float(profile[&"clearance_bounds_radius_squared"])
			)
			if not could_be_nearest and not could_affect_clearance:
				continue
		var sample := _nearest_terrain_profile_sample(profile, point)
		if sample.is_empty():
			continue
		var distance: float = sample[&"distance"]
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_distance_squared = float(sample[&"distance_squared"])
			sample[&"profile_index"] = profile_index
			nearest = sample
		if float(sample[&"edge_distance"]) <= influence_radius:
			clearance_ceiling = minf(
				clearance_ceiling,
				_terrain_profile_clearance_ceiling(profile, sample, point, influence_radius)
			)
	return {&"nearest": nearest, &"clearance_ceiling": clearance_ceiling}


func _distance_squared_to_profile_bounds(point: Vector2, profile: Dictionary) -> float:
	var minimum: Vector2 = profile.get(&"minimum_xz", Vector2(-INF, -INF))
	var maximum: Vector2 = profile.get(&"maximum_xz", Vector2(INF, INF))
	var dx := maxf(maxf(minimum.x - point.x, 0.0), point.x - maximum.x)
	var dz := maxf(maxf(minimum.y - point.y, 0.0), point.y - maximum.y)
	return dx * dx + dz * dz


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
		&"distance_squared": best_distance_squared,
		&"edge_distance": maxf(distance - outer_half_width, 0.0),
		&"center_height": center.y,
		&"surface_height": surface_height,
		&"signed_offset": signed_offset,
		&"segment_index": best_segment,
		&"segment_weight": best_weight,
		&"arc_distance": lerpf(float(frame_a[&"distance"]), float(frame_b[&"distance"]), best_weight),
	}


func _nearest_terrain_query_segment(profile: Dictionary, point: Vector2) -> int:
	var frames: Array[Dictionary] = profile[&"frames"]
	var query_indices: PackedInt32Array = profile[&"query_indices"]
	# Tiny optional trails are cheaper to scan directly, especially when the
	# terrain sample is far outside their compact index bounds.
	if query_indices.size() <= TERRAIN_PROFILE_LINEAR_SCAN_MAX_INDICES:
		return _nearest_terrain_query_segment_linear(frames, query_indices, point)
	var spatial_index: Dictionary = profile.get(&"query_spatial_index", {})
	var buckets: Dictionary = spatial_index.get(&"buckets", {})
	if buckets.is_empty():
		return _nearest_terrain_query_segment_linear(frames, query_indices, point)

	var cell_size := float(spatial_index.get(&"cell_size", TERRAIN_PROFILE_INDEX_CELL_SIZE))
	var point_cell := Vector2i(floori(point.x / cell_size), floori(point.y / cell_size))
	var minimum_cell: Vector2i = spatial_index.get(&"minimum_cell", point_cell)
	var maximum_cell: Vector2i = spatial_index.get(&"maximum_cell", point_cell)
	var maximum_radius := maxi(
		maxi(absi(point_cell.x - minimum_cell.x), absi(point_cell.x - maximum_cell.x)),
		maxi(absi(point_cell.y - minimum_cell.y), absi(point_cell.y - maximum_cell.y))
	)
	var visited_segments: Dictionary = {}
	var best_query_segment := 0
	var best_distance_squared := INF
	for radius: int in range(maximum_radius + 1):
		var ring_minimum := point_cell - Vector2i(radius, radius)
		var ring_maximum := point_cell + Vector2i(radius, radius)
		for cell_x: int in range(ring_minimum.x, ring_maximum.x + 1):
			for cell_y: int in range(ring_minimum.y, ring_maximum.y + 1):
				if (
					radius > 0
					and cell_x > ring_minimum.x
					and cell_x < ring_maximum.x
					and cell_y > ring_minimum.y
					and cell_y < ring_maximum.y
				):
					continue
				var cell := Vector2i(cell_x, cell_y)
				if not buckets.has(cell):
					continue
				var segment_indices: Array = buckets[cell]
				for raw_query_segment: Variant in segment_indices:
					var query_segment := int(raw_query_segment)
					if visited_segments.has(query_segment):
						continue
					visited_segments[query_segment] = true
					var distance_squared := _terrain_query_segment_distance_squared(
						frames, query_indices, query_segment, point
					)
					if (
						distance_squared < best_distance_squared
						or (
							distance_squared == best_distance_squared
							and query_segment < best_query_segment
						)
					):
						best_distance_squared = distance_squared
						best_query_segment = query_segment

		if best_distance_squared < INF:
			# Every unvisited segment lies outside this cell square because each
			# segment was indexed into every cell touched by its 2D bounding box.
			# A strict bound preserves the original earliest-segment tie behavior.
			var left := float(ring_minimum.x) * cell_size
			var right := float(ring_maximum.x + 1) * cell_size
			var bottom := float(ring_minimum.y) * cell_size
			var top := float(ring_maximum.y + 1) * cell_size
			var distance_to_unvisited := minf(
				minf(point.x - left, right - point.x),
				minf(point.y - bottom, top - point.y)
			)
			if best_distance_squared < distance_to_unvisited * distance_to_unvisited:
				return best_query_segment
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
	var paths: Array[PackedVector3Array] = [_ride_points.duplicate()]
	for alternate: PackedVector3Array in _alternate_ride_trails:
		paths.append(alternate.duplicate())
	paths = _decimate_terrain_paths(paths)
	_terrain_query_paths = paths
	# The district grid is intentionally coarse (roughly four thousand vertices),
	# so build it before gameplay can begin. Web threads can start successfully but
	# attach several frames later, which previously left the entire off-trail area
	# as empty space during the opening countdown.
	_attach_generated_terrain(_generate_terrain_data(paths))


func _decimate_terrain_paths(paths: Array[PackedVector3Array]) -> Array[PackedVector3Array]:
	# The riding spline is sampled near 1 m for wheel feel, while this landscape
	# grid is 12 m. Keeping every bike sample made each terrain vertex scan several
	# thousand near-identical segments. Preserve endpoints and one sample per grid
	# interval; straight interpolation still follows the course more accurately
	# than the terrain mesh itself can display.
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
			uvs[index] = Vector2(float(column) / float(columns - 1), float(row) / float(rows - 1)) * 20.0
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
		push_warning("Pine terrain generation returned no vertices.")
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
	visual.name = "GeneratedPineTerrain"
	visual.mesh = terrain_mesh
	add_child(visual)
	var body := StaticBody3D.new()
	body.name = "GeneratedPineTerrainCollision"
	body.collision_layer = 2
	body.collision_mask = 1
	_tag_surface(body, &"LOAM", 1.12, 1.38)
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
	noise.frequency = 0.007
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	noise.fractal_gain = 0.54
	noise.fractal_lacunarity = 2.0


func _terrain_height_at(x: float, z: float) -> float:
	var paths := _terrain_query_paths
	if paths.is_empty():
		paths = [_ride_points]
		paths.append_array(_alternate_ride_trails)
	return _terrain_height_with_noise(paths, _terrain_noise, x, z)


func _terrain_height_with_noise(_paths: Array[PackedVector3Array], noise: FastNoiseLite, x: float, z: float) -> float:
	var terrain_context := _terrain_surface_context(x, z)
	var route_sample: Dictionary = terrain_context[&"nearest"]
	if route_sample.is_empty():
		return 0.0
	var route_distance: float = route_sample[&"distance"]
	var route_surface_height: float = route_sample[&"surface_height"]
	var broad_noise := noise.get_noise_2d(x, z)
	var detail_noise := noise.get_noise_2d(x * 2.9 - 513.0, z * 2.9 + 911.0)
	var ridge_ratio := clampf((z + TERRAIN_SIZE.y * 0.5) / TERRAIN_SIZE.y, 0.0, 1.0)
	var base_height := 18.0 + broad_noise * 21.0 + detail_noise * 3.2 + sin(ridge_ratio * PI) * 14.0
	# Cut a shallow creek gully beneath the raised log bridge.
	var creek_distance := _distance_to_segment_2d(Vector3(x, 0.0, z), Vector3(280.0, 0.0, 211.0), Vector3(390.0, 0.0, 169.0))
	base_height -= (1.0 - smoothstep(4.0, 24.0, creek_distance)) * 5.5
	# Pull the landscape toward the actual signed cross-section rather than a
	# centerline-only plane. A little low-frequency relief remains outside the
	# shoulder, while the exact clearance ceiling below removes collision tongues.
	var shoulder_height := route_surface_height - TERRAIN_SURFACE_GAP + detail_noise * 0.45
	var shoulder_blend := 1.0 - smoothstep(18.0, 82.0, route_distance)
	var height := lerpf(base_height, shoulder_height, shoulder_blend)
	# Any terrain vertex that can feed a 12 m cell under the ribbon is capped by
	# the lowest banked/bermed shoulder sample inside one full cell diagonal.
	# Interpolated terrain triangles therefore remain below the rideable mesh.
	var clearance_ceiling: float = terrain_context[&"clearance_ceiling"]
	if is_finite(clearance_ceiling):
		height = minf(height, clearance_ceiling)
	return height


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
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material
