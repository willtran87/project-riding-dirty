extends Node3D
## Purpose-built Red Mesa motocross stadium generated from the catalog route.
##
## Every gameplay-facing element samples `_ride_points`: the rendered/colliding
## ribbon, containment, gate gantries, jump callouts, staging marks, and the
## route returned to race systems. Terrain is deliberately only a catch surface;
## it is held below the entire ribbon envelope and can never become a second
## interpretation of the course.

const SurfaceTextureFactory = preload("res://features/environment/procedural_surface_texture.gd")
const RED_MESA_CLAY_ALBEDO = preload("res://assets/textures/red_mesa_clay_albedo.png")

const TERRAIN_SIZE := Vector2(440.0, 440.0)
const TERRAIN_STEP: float = 8.0
const TERRAIN_SEED: int = 7319
const TERRAIN_ROUTE_CLEARANCE: float = 3.35
const SHOULDER_WIDTH: float = 3.2
const BARRIER_SPACING: float = 7.8
const BARRIER_LENGTH: float = 7.35

# Decorative stakes only. The physical rhythm and jump relief is authored in
# CourseCatalog and therefore remains part of the authoritative centerline.
const RHYTHM_DRESSING := [
	{&"start": 18.0, &"length": 32.0, &"spacing": 9.4},
	{&"start": 230.0, &"length": 42.0, &"spacing": 9.6},
	{&"start": 354.0, &"length": 48.0, &"spacing": 9.6},
	{&"start": 492.0, &"length": 40.0, &"spacing": 9.8},
	{&"start": 616.0, &"length": 34.0, &"spacing": 9.4},
]

var _ride_points := PackedVector3Array()
var _frames: Array[Dictionary] = []
var _track_width: float = 23.0
var _main_route_surface: Node3D
var _materials: Dictionary[StringName, StandardMaterial3D] = {}
var _terrain_noise := FastNoiseLite.new()


func _ready() -> void:
	_ride_points = CourseCatalog.get_local_riding_points(CourseCatalog.MESA_MX_ID)
	_track_width = CourseCatalog.get_track_width(CourseCatalog.MESA_MX_ID)
	if _ride_points.size() < 3:
		push_error("Mesa MX requires at least three authoritative route samples.")
		return
	if _ride_points[0].distance_to(_ride_points[-1]) > 0.02:
		push_error("Mesa MX catalog route must be a closed loop.")
		return
	_frames = CourseSurfaceBuilder._build_frames(_ride_points, _track_width, _surface_config())
	_configure_noise()
	_create_materials()
	_build_environment()
	_build_ground()
	_build_race_ribbon()
	_build_containment()
	_build_start_compound()
	_build_checkpoint_gantries()
	_build_jump_and_rhythm_dressing()
	_build_spectator_zones()
	_build_landmarks()
	_build_event_paddock()
	_build_track_lighting()
	set_meta(&"track_id", CourseCatalog.MESA_MX_ID)
	set_meta(&"closed_loop", true)
	set_meta(&"authoritative_route_samples", _ride_points.size())


func get_authoritative_route_world() -> PackedVector3Array:
	var world_route := _ride_points.duplicate()
	for index: int in world_route.size():
		world_route[index] = to_global(world_route[index])
	return world_route


func _surface_config() -> Dictionary:
	return {
		&"maximum_bank_degrees": 9.5,
		&"bank_strength": 0.52,
		&"berm_height": 1.35,
		&"shoulder_width": SHOULDER_WIDTH,
		&"rut_offset": 1.25,
		&"rut_half_width": 0.22,
		&"rut_depth": 0.052,
		&"physical_rut_depth": 0.022,
		&"chunk_segments": 64,
		&"casts_shadow": false,
	}


func _create_materials() -> void:
	_materials[&"terrain"] = _material(Color("844931"), 1.0)
	_materials[&"track"] = _material(Color("48241c"), 1.0)
	_materials[&"shoulder"] = _material(Color("ad7550"), 0.98)
	_materials[&"rut"] = _material(Color("281713"), 1.0)
	_materials[&"rock"] = _material(Color("8f3f2c"), 0.97)
	_materials[&"rock_dark"] = _material(Color("5b2c26"), 0.99)
	_materials[&"cream"] = _material(Color("f2d7a0"), 0.72)
	_materials[&"red"] = _material(Color("d83a2e"), 0.58)
	_materials[&"yellow"] = _material(Color("f0a72d"), 0.54)
	_materials[&"blue"] = _material(Color("2c7095"), 0.55)
	_materials[&"black"] = _material(Color("17191b"), 0.92)
	_materials[&"metal"] = _material(Color("43494d"), 0.36, 0.58)
	_materials[&"wood"] = _material(Color("6b4430"), 0.92)
	_materials[&"glass"] = _material(Color("81b5c4"), 0.2, 0.12)
	_materials[&"cactus"] = _material(Color("416647"), 0.94)
	_materials[&"skin"] = _material(Color("bd7d5d"), 0.82)
	_materials[&"spectator_dark"] = _material(Color("23272b"), 0.88)
	SurfaceTextureFactory.apply(
		_materials[&"track"],
		# Neutral macro values multiply the authored clay photograph below. This
		# preserves its fine aggregate while adding broad damp/packed variation.
		PackedColorArray([Color("a79b91"), Color("d8d0c7"), Color("b7a79b"), Color("eee7de")]),
		TERRAIN_SEED + 11,
		0.022,
		0.72
	)
	# Original authored clay detail sits over the generated normal/roughness set.
	# Keeping geometry and collision procedural preserves the route authority.
	var clay_macro_texture := _materials[&"track"].albedo_texture
	_materials[&"track"].albedo_texture = RED_MESA_CLAY_ALBEDO
	_materials[&"track"].albedo_color = Color(0.9, 0.84, 0.78)
	_materials[&"track"].detail_enabled = true
	_materials[&"track"].detail_albedo = clay_macro_texture
	_materials[&"track"].detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
	SurfaceTextureFactory.apply(
		_materials[&"shoulder"],
		PackedColorArray([Color("76503c"), Color("a16c4c"), Color("c58b64")]),
		TERRAIN_SEED + 17,
		0.035,
		0.74
	)
	SurfaceTextureFactory.apply(
		_materials[&"terrain"],
		PackedColorArray([Color("5b342a"), Color("7d4934"), Color("a46142"), Color("6c3d30")]),
		TERRAIN_SEED + 23,
		0.018,
		0.66
	)
	_materials[&"terrain"].albedo_color = Color(0.78, 0.7, 0.64)
	_materials[&"shoulder"].albedo_color = Color(0.86, 0.78, 0.68)


func _build_environment() -> void:
	var world_environment := WorldEnvironment.new()
	world_environment.name = "MesaWorldEnvironment"
	var environment := Environment.new()
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("102f5b")
	sky_material.sky_horizon_color = Color("ed8750")
	sky_material.ground_bottom_color = Color("321918")
	sky_material.ground_horizon_color = Color("9f3e28")
	sky_material.sky_curve = 0.09
	sky_material.ground_curve = 0.075
	sky_material.sky_energy_multiplier = 1.12
	sky_material.ground_energy_multiplier = 0.68
	sky_material.sun_angle_max = 18.0
	sky_material.sun_curve = 0.055
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("76545a")
	environment.ambient_light_energy = 0.29
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.04
	environment.fog_enabled = true
	environment.fog_light_color = Color("c9734e")
	environment.fog_light_energy = 0.18
	environment.fog_density = 0.00062
	environment.fog_height = -3.0
	environment.fog_height_density = 0.045
	environment.fog_sky_affect = 0.12
	world_environment.environment = environment
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.name = "MesaSun"
	sun.rotation_degrees = Vector3(-29.0, -62.0, 0.0)
	sun.light_color = Color("ffc477")
	sun.light_energy = 1.58
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_max_distance = 430.0
	add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.name = "MesaSkyFill"
	fill.rotation_degrees = Vector3(38.0, 126.0, 0.0)
	fill.light_color = Color("3d638e")
	fill.light_energy = 0.1
	fill.shadow_enabled = false
	add_child(fill)


func _build_ground() -> void:
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
			heights[row * columns + column] = _terrain_height_at(x, z)

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
			uvs[index] = Vector2(float(column) / float(columns - 1), float(row) / float(rows - 1)) * 14.0

	var indices := PackedInt32Array()
	indices.resize((columns - 1) * (rows - 1) * 6)
	var cursor := 0
	for row: int in rows - 1:
		for column: int in columns - 1:
			var top_left := row * columns + column
			var bottom_left := (row + 1) * columns + column
			indices[cursor] = top_left
			indices[cursor + 1] = top_left + 1
			indices[cursor + 2] = bottom_left
			indices[cursor + 3] = top_left + 1
			indices[cursor + 4] = bottom_left + 1
			indices[cursor + 5] = bottom_left
			cursor += 6

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var terrain_mesh := ArrayMesh.new()
	terrain_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	terrain_mesh.surface_set_material(0, _materials[&"terrain"])
	var visual := MeshInstance3D.new()
	visual.name = "MesaGradedGround"
	visual.mesh = terrain_mesh
	add_child(visual)

	var body := StaticBody3D.new()
	body.name = "MesaGradedGroundCollision"
	body.collision_layer = 2
	body.collision_mask = 1
	_tag_surface(body, &"HARDPACK", 0.9, 0.7)
	add_child(body)
	var faces := PackedVector3Array()
	faces.resize(indices.size())
	for index: int in indices.size():
		faces[index] = vertices[indices[index]]
	var terrain_shape := ConcavePolygonShape3D.new()
	terrain_shape.backface_collision = true
	terrain_shape.set_faces(faces)
	var collision := CollisionShape3D.new()
	collision.shape = terrain_shape
	body.add_child(collision)

	# A hidden safety slab sits far below the visible ground. It only catches an
	# out-of-bounds bike if it somehow leaves the generated terrain entirely.
	var catch_floor := _add_static_box(
		self,
		"MesaSafetyCatchFloor",
		Vector3(TERRAIN_SIZE.x + 80.0, 1.0, TERRAIN_SIZE.y + 80.0),
		Transform3D(Basis.IDENTITY, Vector3(0.0, -8.0, 0.0)),
		_materials[&"rock_dark"],
		&"HARDPACK",
		0.94,
		0.35
	)
	catch_floor.set_meta(&"safety_catch_floor", true)


func _build_race_ribbon() -> void:
	_main_route_surface = CourseSurfaceBuilder.build(
		self,
		"MesaAuthoritativeRaceRibbon",
		_ride_points,
		_track_width,
		_materials[&"track"],
		_materials[&"shoulder"],
		_materials[&"rut"],
		&"DIRT",
		0.81,
		1.3,
		_surface_config()
	)
	_mark_authoritative_track_surface(_main_route_surface)
	_main_route_surface.set_meta(&"closed_loop", true)
	_main_route_surface.set_meta(&"single_layer_race_surface", true)
	_main_route_surface.set_meta(
		&"welded_jump_package_count",
		CourseCatalog.get_welded_jump_zones(CourseCatalog.MESA_MX_ID).size()
	)


func _build_containment() -> void:
	var root := Node3D.new()
	root.name = "VisibleContainmentBarriers"
	root.set_meta(&"route_derived", true)
	root.set_meta(&"visible_collision", true)
	add_child(root)
	var last_distance := -BARRIER_SPACING
	var barrier_index := 0
	var total_distance: float = _frames[-1][&"distance"]
	for frame_index: int in _frames.size() - 1:
		var frame: Dictionary = _frames[frame_index]
		var distance: float = frame[&"distance"]
		if distance - last_distance < BARRIER_SPACING:
			continue
		# Leave a small visual breathing space at the start/finish gantry while
		# retaining barriers along both sides of the launch chute.
		if distance < 18.0 or total_distance - distance < 18.0:
			continue
		last_distance = distance
		var tangent: Vector3 = frame[&"tangent"]
		var right: Vector3 = frame[&"right"]
		var up: Vector3 = frame[&"up"]
		var basis := Basis(right, up, -tangent).orthonormalized()
		for side: float in [-1.0, 1.0]:
			var material := (
				_materials[&"cream"]
				if (barrier_index + int(side > 0.0)) % 2 == 0
				else _materials[&"red"]
			)
			var offset := side * (_track_width * 0.5 + 1.65)
			var origin: Vector3 = frame[&"position"] + right * offset + up * 0.48
			var barrier := _add_static_box(
				root,
				"Barrier_%04d_%s" % [barrier_index, "R" if side > 0.0 else "L"],
				Vector3(0.82, 0.94, BARRIER_LENGTH),
				Transform3D(basis, origin),
				material,
				&"BARRIER",
				0.98,
				0.0
			)
			barrier.set_meta(&"route_distance", distance)
		barrier_index += 1
	root.set_meta(&"barrier_pair_count", barrier_index)


func _build_start_compound() -> void:
	var frame := _frame_at_distance(0.0)
	var root := StaticBody3D.new()
	root.name = "StartFinishGantry"
	root.collision_layer = 2
	root.collision_mask = 1
	root.transform = _frame_transform(frame)
	_tag_surface(root, &"BARRIER", 0.96, 0.0)
	add_child(root)
	var post_offset := _track_width * 0.5 + 2.0
	_add_body_box(root, "StartLeftPost", Vector3(0.58, 6.1, 0.58), Vector3(-post_offset, 3.05, 0.0), _materials[&"red"])
	_add_body_box(root, "StartRightPost", Vector3(0.58, 6.1, 0.58), Vector3(post_offset, 3.05, 0.0), _materials[&"cream"])
	_add_visual_box(root, "StartHeader", Vector3(post_offset * 2.0 + 0.6, 0.9, 0.74), Transform3D(Basis.IDENTITY, Vector3(0.0, 6.05, 0.0)), _materials[&"black"])
	_add_visual_box(root, "HeaderStripeLeft", Vector3(post_offset, 0.18, 0.77), Transform3D(Basis.IDENTITY, Vector3(-post_offset * 0.5, 6.28, 0.0)), _materials[&"red"])
	_add_visual_box(root, "HeaderStripeRight", Vector3(post_offset, 0.18, 0.77), Transform3D(Basis.IDENTITY, Vector3(post_offset * 0.5, 6.28, 0.0)), _materials[&"cream"])
	_add_gate_label(root, "RED MESA MX", Vector3(0.0, 6.1, -0.4), Color("ffd39a"), 70)

	var grid_root := Node3D.new()
	grid_root.name = "TwelveBikeStagingGrid"
	grid_root.set_meta(&"staging_slots", 12)
	add_child(grid_root)
	for row: int in 3:
		var row_frame := _frame_at_distance(4.5 + float(row) * 4.4)
		var row_transform := _frame_transform(row_frame)
		_add_visual_box(
			grid_root,
			"GridRow%02d" % row,
			Vector3(_track_width - 1.4, 0.022, 0.24),
			Transform3D(row_transform.basis, row_transform.origin + (row_frame[&"up"] as Vector3) * 0.095),
			_materials[&"cream"]
		)
		for divider: int in 5:
			var lateral := -(_track_width - 1.8) * 0.5 + float(divider) * (_track_width - 1.8) / 4.0
			var divider_origin: Vector3 = row_transform.origin + (row_frame[&"right"] as Vector3) * lateral + (row_frame[&"up"] as Vector3) * 0.095
			_add_visual_box(
				grid_root,
				"GridDivider_%02d_%02d" % [row, divider],
				Vector3(0.12, 0.024, 3.25),
				Transform3D(row_transform.basis, divider_origin + (row_frame[&"tangent"] as Vector3) * 1.5),
				_materials[&"cream"]
			)


func _build_checkpoint_gantries() -> void:
	var world_route := get_authoritative_route_world()
	var route_indices := CourseCatalog.get_checkpoint_route_indices(CourseCatalog.MESA_MX_ID, world_route)
	var root := Node3D.new()
	root.name = "RouteDerivedCheckpointGates"
	root.set_meta(&"route_derived", true)
	add_child(root)
	# The final catalog checkpoint is the repeated start anchor. The start/finish
	# gantry already marks that seam, so build numbered gates for the intervening
	# ten anchors only.
	for gate_index: int in maxi(route_indices.size() - 1, 0):
		var route_index := clampi(route_indices[gate_index], 0, _frames.size() - 1)
		var frame: Dictionary = _frames[route_index]
		var gate := StaticBody3D.new()
		gate.name = "Gate%02d" % (gate_index + 1)
		gate.collision_layer = 2
		gate.collision_mask = 1
		gate.transform = _frame_transform(frame)
		gate.set_meta(&"route_index", route_index)
		gate.set_meta(&"route_distance", float(frame[&"distance"]))
		_tag_surface(gate, &"BARRIER", 0.96, 0.0)
		root.add_child(gate)
		var post_offset := _track_width * 0.5 + 1.78
		var accent := _materials[&"yellow"] if gate_index % 2 == 0 else _materials[&"blue"]
		_add_body_box(gate, "LeftPost", Vector3(0.4, 4.8, 0.4), Vector3(-post_offset, 2.4, 0.0), accent)
		_add_body_box(gate, "RightPost", Vector3(0.4, 4.8, 0.4), Vector3(post_offset, 2.4, 0.0), accent)
		_add_visual_box(gate, "GateHeader", Vector3(post_offset * 2.0 + 0.4, 0.52, 0.5), Transform3D(Basis.IDENTITY, Vector3(0.0, 4.75, 0.0)), _materials[&"black"])
		_add_gate_label(gate, "GATE %02d" % (gate_index + 1), Vector3(0.0, 4.78, -0.28), Color("ffe1a8"), 48)
	root.set_meta(&"gate_count", maxi(route_indices.size() - 1, 0))


func _build_jump_and_rhythm_dressing() -> void:
	var root := Node3D.new()
	root.name = "JumpAndRhythmDressing"
	root.set_meta(&"physical_relief_source", "CourseCatalog authoritative route")
	add_child(root)
	var jump_zones := CourseCatalog.get_welded_jump_zones(CourseCatalog.MESA_MX_ID)
	for zone_index: int in jump_zones.size():
		var zone: Dictionary = jump_zones[zone_index]
		_build_jump_callout(root, zone_index, zone, float(zone.get(&"start", 0.0)), true)
		_build_jump_callout(root, zone_index, zone, float(zone.get(&"receiver_start", 0.0)), false)
	root.set_meta(&"jump_package_count", jump_zones.size())

	var stake_index := 0
	for zone_value: Variant in RHYTHM_DRESSING:
		var zone := zone_value as Dictionary
		var start := float(zone[&"start"])
		var length := float(zone[&"length"])
		var spacing := float(zone[&"spacing"])
		var distance := start
		while distance <= start + length:
			var frame := _frame_at_distance(distance)
			var basis_transform := _frame_transform(frame)
			for side: float in [-1.0, 1.0]:
				var offset := side * (_track_width * 0.5 + 1.25)
				var origin: Vector3 = frame[&"position"] + (frame[&"right"] as Vector3) * offset + (frame[&"up"] as Vector3) * 0.68
				_add_visual_box(
					root,
					"RhythmStake_%03d_%s" % [stake_index, "R" if side > 0.0 else "L"],
					Vector3(0.15, 1.25, 0.15),
					Transform3D(basis_transform.basis, origin),
					_materials[&"yellow"] if stake_index % 2 == 0 else _materials[&"cream"]
				)
			stake_index += 1
			distance += spacing
	root.set_meta(&"rhythm_stake_pair_count", stake_index)


func _build_jump_callout(parent: Node3D, zone_index: int, zone: Dictionary, distance: float, is_takeoff: bool) -> void:
	var frame := _frame_at_distance(distance)
	var marker := Node3D.new()
	marker.name = "%s_%s" % [String(zone.get(&"name", &"Jump")), "Takeoff" if is_takeoff else "Receiver"]
	marker.transform = _frame_transform(frame)
	marker.set_meta(&"route_distance", distance)
	marker.set_meta(&"jump_package_index", zone_index)
	parent.add_child(marker)
	var post_offset := _track_width * 0.5 + 1.42
	var accent := _materials[&"red"] if is_takeoff else _materials[&"blue"]
	for side: float in [-1.0, 1.0]:
		_add_visual_box(marker, "MarkerPost%s" % ("R" if side > 0.0 else "L"), Vector3(0.2, 2.8, 0.2), Transform3D(Basis.IDENTITY, Vector3(side * post_offset, 1.4, 0.0)), _materials[&"black"])
		_add_visual_box(marker, "MarkerFlag%s" % ("R" if side > 0.0 else "L"), Vector3(1.35, 0.72, 0.08), Transform3D(Basis.IDENTITY, Vector3(side * (post_offset - 0.58), 2.35, 0.0)), accent)
	if is_takeoff:
		_add_gate_label(marker, String(zone.get(&"name", &"JUMP")).to_upper(), Vector3(0.0, 3.05, -0.15), Color("ffd18a"), 34)


func _build_spectator_zones() -> void:
	var root := Node3D.new()
	root.name = "TracksideSpectators"
	add_child(root)
	var total_distance: float = _frames[-1][&"distance"]
	var ratios := PackedFloat32Array([0.045, 0.15, 0.29, 0.43, 0.58, 0.72, 0.86, 0.95])
	var palette := [Color("db4c3f"), Color("e9a73c"), Color("3f82a9"), Color("70a15a"), Color("d7d2ba"), Color("985ea6")]
	var spectator_index := 0
	for group_index: int in ratios.size():
		var frame := _frame_at_distance(total_distance * ratios[group_index])
		var side := -1.0 if group_index % 2 == 0 else 1.0
		var right: Vector3 = frame[&"right"]
		var tangent: Vector3 = frame[&"tangent"]
		for member_index: int in 6:
			var along := (float(member_index) - 2.5) * 1.45
			var outward := side * (_track_width * 0.5 + 7.3 + float(member_index % 2) * 1.2)
			var position: Vector3 = frame[&"position"] + right * outward + tangent * along
			position.y = _terrain_height_at(position.x, position.z)
			_add_spectator(
				root,
				"Spectator%03d" % spectator_index,
				position,
				frame[&"position"],
				palette[(spectator_index + group_index) % palette.size()]
			)
			spectator_index += 1
	root.set_meta(&"spectator_count", spectator_index)


func _build_landmarks() -> void:
	var root := Node3D.new()
	root.name = "MesaLandmarks"
	add_child(root)
	_build_grandstand(root)
	_build_timing_tower(root)
	_build_water_tower(root)

	var rock_positions := PackedVector3Array([
		Vector3(-194.0, 0.0, -120.0),
		Vector3(190.0, 0.0, -132.0),
		Vector3(188.0, 0.0, 166.0),
		Vector3(-182.0, 0.0, 176.0),
	])
	for index: int in rock_positions.size():
		_build_rock_stack(root, "MesaStack%02d" % index, rock_positions[index], 1.0 + float(index % 3) * 0.16)

	var rng := RandomNumberGenerator.new()
	rng.seed = TERRAIN_SEED + 401
	var cactus_index := 0
	var attempts := 0
	while cactus_index < 34 and attempts < 300:
		attempts += 1
		var position := Vector3(rng.randf_range(-203.0, 203.0), 0.0, rng.randf_range(-203.0, 203.0))
		var route_sample := _nearest_route_sample(position.x, position.z)
		if float(route_sample[&"distance"]) < _track_width * 0.5 + 8.0:
			continue
		position.y = _terrain_height_at(position.x, position.z)
		_build_cactus(root, "Cactus%02d" % cactus_index, position, rng.randf_range(0.78, 1.35))
		cactus_index += 1
	root.set_meta(&"cactus_count", cactus_index)


func _build_grandstand(parent: Node3D) -> void:
	var frame := _frame_at_distance(24.0)
	var right: Vector3 = frame[&"right"]
	var tangent: Vector3 = frame[&"tangent"]
	var side := -1.0
	var center: Vector3 = frame[&"position"] + right * side * (_track_width * 0.5 + 18.0)
	center.y = _terrain_height_at(center.x, center.z)
	var flat_tangent := Vector3(tangent.x, 0.0, tangent.z).normalized()
	var flat_right := flat_tangent.cross(Vector3.UP).normalized()
	var basis := Basis(flat_tangent, Vector3.UP, flat_right).orthonormalized()
	var stand := Node3D.new()
	stand.name = "RedMesaGrandstand"
	stand.transform = Transform3D(basis, center)
	parent.add_child(stand)
	for tier: int in 4:
		_add_static_box(
			stand,
			"BleacherTier%02d" % tier,
			Vector3(22.0, 0.48, 2.7),
			Transform3D(Basis.IDENTITY, Vector3(0.0, 0.32 + float(tier) * 0.72, float(tier) * 1.55)),
			_materials[&"metal"],
			&"METAL",
			1.0,
			0.0
		)
	_add_visual_box(stand, "GrandstandAwning", Vector3(24.0, 0.35, 8.5), Transform3D(Basis.IDENTITY, Vector3(0.0, 6.8, 2.2)), _materials[&"red"])
	for support_x: float in [-10.5, 10.5]:
		_add_visual_box(stand, "AwningSupport%d" % int(support_x), Vector3(0.25, 6.6, 0.25), Transform3D(Basis.IDENTITY, Vector3(support_x, 3.3, 4.6)), _materials[&"metal"])


func _build_timing_tower(parent: Node3D) -> void:
	var frame := _frame_at_distance(10.0)
	var right: Vector3 = frame[&"right"]
	var tangent: Vector3 = frame[&"tangent"]
	var position: Vector3 = frame[&"position"] + right * (_track_width * 0.5 + 20.0)
	position.y = _terrain_height_at(position.x, position.z)
	var flat_tangent := Vector3(tangent.x, 0.0, tangent.z).normalized()
	var flat_right := flat_tangent.cross(Vector3.UP).normalized()
	var basis := Basis(flat_right, Vector3.UP, -flat_tangent).orthonormalized()
	var tower := Node3D.new()
	tower.name = "TimingAndScoringTower"
	tower.transform = Transform3D(basis, position)
	parent.add_child(tower)
	_add_static_box(tower, "TowerCab", Vector3(6.0, 7.4, 5.0), Transform3D(Basis.IDENTITY, Vector3(0.0, 3.7, 0.0)), _materials[&"rock_dark"], &"BARRIER", 1.0, 0.0)
	_add_visual_box(tower, "TimingWindow", Vector3(4.7, 1.6, 0.1), Transform3D(Basis.IDENTITY, Vector3(0.0, 5.1, -2.54)), _materials[&"glass"])
	_add_visual_box(tower, "TimingBanner", Vector3(6.2, 0.85, 0.14), Transform3D(Basis.IDENTITY, Vector3(0.0, 7.0, -2.58)), _materials[&"yellow"])
	_add_gate_label(tower, "RED MESA", Vector3(0.0, 7.02, -2.68), Color("241712"), 34)


func _build_water_tower(parent: Node3D) -> void:
	var position := Vector3(0.0, _terrain_height_at(0.0, 0.0), 0.0)
	var tower := Node3D.new()
	tower.name = "MesaWaterTower"
	tower.position = position
	parent.add_child(tower)
	for x: float in [-2.4, 2.4]:
		for z: float in [-2.4, 2.4]:
			_add_visual_box(tower, "WaterTowerLeg_%d_%d" % [int(x), int(z)], Vector3(0.28, 11.0, 0.28), Transform3D(Basis.IDENTITY, Vector3(x, 5.5, z)), _materials[&"metal"])
	_add_visual_cylinder(tower, "WaterTank", 4.8, 4.2, Transform3D(Basis.IDENTITY, Vector3(0.0, 12.2, 0.0)), _materials[&"blue"], 20)
	_add_visual_cylinder(tower, "WaterTankCap", 2.0, 1.2, Transform3D(Basis.IDENTITY, Vector3(0.0, 14.85, 0.0)), _materials[&"cream"], 20, 4.8)
	_add_gate_label(tower, "MESA MX", Vector3(0.0, 12.4, -4.9), Color("f7dfb0"), 52)


func _build_event_paddock() -> void:
	# A compact pit village gives the opening straight a strong event identity
	# and readable mid-distance silhouettes without placing collision near the
	# race surface. It also fills the otherwise empty infield/start horizon.
	var root := Node3D.new()
	root.name = "RedMesaEventPaddock"
	add_child(root)
	var canopy_materials: Array[StandardMaterial3D] = [
		_materials[&"red"], _materials[&"blue"], _materials[&"yellow"],
	]
	for station_index: int in 5:
		var distance := 30.0 + float(station_index) * 13.5
		var frame := _frame_at_distance(distance)
		var side := 1.0 if station_index % 2 == 0 else -1.0
		var right: Vector3 = frame[&"right"]
		var tangent: Vector3 = frame[&"tangent"]
		var center: Vector3 = frame[&"position"] + right * side * (_track_width * 0.5 + 12.5)
		center.y = _terrain_height_at(center.x, center.z)
		var flat_tangent := Vector3(tangent.x, 0.0, tangent.z).normalized()
		var flat_right := flat_tangent.cross(Vector3.UP).normalized()
		var basis := Basis(flat_right, Vector3.UP, -flat_tangent).orthonormalized()
		var station := Node3D.new()
		station.name = "PaddockStation%02d" % station_index
		station.transform = Transform3D(basis, center)
		root.add_child(station)
		var canopy_material := canopy_materials[station_index % canopy_materials.size()]
		_add_visual_box(station, "Canopy", Vector3(8.6, 0.28, 5.8), Transform3D(Basis.IDENTITY, Vector3(0.0, 4.15, 0.0)), canopy_material)
		for x: float in [-3.9, 3.9]:
			for z: float in [-2.45, 2.45]:
				_add_visual_box(station, "CanopyPost_%d_%d" % [int(x), int(z)], Vector3(0.16, 4.1, 0.16), Transform3D(Basis.IDENTITY, Vector3(x, 2.05, z)), _materials[&"metal"])
		_add_visual_box(station, "ServiceVan", Vector3(5.4, 2.5, 2.8), Transform3D(Basis.IDENTITY, Vector3(side * -5.6, 1.25, 0.4)), _materials[&"cream"])
		_add_visual_box(station, "VanStripe", Vector3(5.48, 0.52, 2.86), Transform3D(Basis.IDENTITY, Vector3(side * -5.6, 1.5, 0.4)), canopy_material)
		_add_visual_box(station, "PitBoard", Vector3(2.4, 1.25, 0.12), Transform3D(Basis.IDENTITY, Vector3(0.0, 2.55, -3.0)), _materials[&"black"])
		_add_gate_label(station, "PIT %02d" % (station_index + 1), Vector3(0.0, 2.55, -3.08), Color("ffe1a6"), 24)
	root.set_meta(&"paddock_station_count", 5)


func _build_rock_stack(parent: Node3D, node_name: String, position: Vector3, scale_factor: float) -> void:
	var root := Node3D.new()
	root.name = node_name
	position.y = _terrain_height_at(position.x, position.z)
	root.position = position
	parent.add_child(root)
	var tier_data := [Vector3(14.0, 8.0, 0.0), Vector3(10.0, 7.0, 7.0), Vector3(6.5, 5.0, 12.0)]
	var height_cursor := 0.0
	for tier_index: int in tier_data.size():
		var data: Vector3 = tier_data[tier_index] * scale_factor
		var radius := data.x
		var height := data.y
		_add_static_cylinder(
			root,
			"RockTier%02d" % tier_index,
			radius,
			height,
			Transform3D(Basis.IDENTITY.rotated(Vector3.UP, float(tier_index) * 0.37), Vector3(data.z * 0.25, height_cursor + height * 0.5, data.z * 0.12)),
			_materials[&"rock"] if tier_index % 2 == 0 else _materials[&"rock_dark"],
			0.78
		)
		height_cursor += height * 0.72


func _build_cactus(parent: Node3D, node_name: String, position: Vector3, scale_factor: float) -> void:
	var cactus := StaticBody3D.new()
	cactus.name = node_name
	cactus.position = position
	cactus.collision_layer = 2
	cactus.collision_mask = 1
	_tag_surface(cactus, &"CACTUS", 1.0, 0.02)
	parent.add_child(cactus)
	var trunk_height := 3.2 * scale_factor
	_add_body_cylinder(cactus, "Trunk", 0.28 * scale_factor, trunk_height, Vector3(0.0, trunk_height * 0.5, 0.0), _materials[&"cactus"])
	for side: float in [-1.0, 1.0]:
		var arm_height := 1.35 * scale_factor
		var arm_x := side * 0.58 * scale_factor
		_add_visual_box(cactus, "ArmLink%s" % ("R" if side > 0.0 else "L"), Vector3(0.7 * scale_factor, 0.22 * scale_factor, 0.22 * scale_factor), Transform3D(Basis.IDENTITY, Vector3(side * 0.38 * scale_factor, trunk_height * 0.58, 0.0)), _materials[&"cactus"])
		_add_visual_cylinder(cactus, "Arm%s" % ("R" if side > 0.0 else "L"), 0.19 * scale_factor, arm_height, Transform3D(Basis.IDENTITY, Vector3(arm_x, trunk_height * 0.58 + arm_height * 0.5, 0.0)), _materials[&"cactus"], 8)


func _build_track_lighting() -> void:
	var root := Node3D.new()
	root.name = "TrackLighting"
	add_child(root)
	var total_distance: float = _frames[-1][&"distance"]
	var ratios := PackedFloat32Array([0.01, 0.19, 0.37, 0.55, 0.73, 0.91])
	for index: int in ratios.size():
		var frame := _frame_at_distance(total_distance * ratios[index])
		var side := -1.0 if index % 2 == 0 else 1.0
		var position: Vector3 = frame[&"position"] + (frame[&"right"] as Vector3) * side * (_track_width * 0.5 + 5.8)
		position.y = _terrain_height_at(position.x, position.z)
		_add_visual_cylinder(root, "LightPole%02d" % index, 0.14, 10.5, Transform3D(Basis.IDENTITY, position + Vector3.UP * 5.25), _materials[&"metal"], 10)
		_add_visual_box(root, "LightBar%02d" % index, Vector3(2.5, 0.38, 0.5), Transform3D(Basis.IDENTITY, position + Vector3.UP * 10.45), _materials[&"cream"])
		var light := OmniLight3D.new()
		light.name = "WarmTrackLight%02d" % index
		light.position = position + Vector3.UP * 10.1
		light.light_color = Color("ffc688")
		light.light_energy = 2.25
		light.omni_range = 24.0
		light.shadow_enabled = false
		root.add_child(light)


func _add_spectator(parent: Node3D, node_name: String, position: Vector3, target: Vector3, shirt_color: Color) -> void:
	var spectator := Node3D.new()
	spectator.name = node_name
	spectator.position = position
	var look_direction := target - position
	look_direction.y = 0.0
	if look_direction.length_squared() > 0.01:
		spectator.basis = Basis.looking_at(look_direction.normalized(), Vector3.UP)
	parent.add_child(spectator)
	var shirt := _material(shirt_color, 0.82)
	_add_visual_cylinder(spectator, "Body", 0.28, 1.15, Transform3D(Basis.IDENTITY, Vector3(0.0, 1.45, 0.0)), shirt, 8)
	_add_visual_sphere(spectator, "Head", 0.28, Vector3(0.0, 2.28, 0.0), _materials[&"skin"])
	_add_visual_box(spectator, "LeftLeg", Vector3(0.18, 0.9, 0.2), Transform3D(Basis.IDENTITY, Vector3(-0.14, 0.48, 0.0)), _materials[&"spectator_dark"])
	_add_visual_box(spectator, "RightLeg", Vector3(0.18, 0.9, 0.2), Transform3D(Basis.IDENTITY, Vector3(0.14, 0.48, 0.0)), _materials[&"spectator_dark"])


func _frame_at_distance(requested_distance: float) -> Dictionary:
	if _frames.is_empty():
		return {}
	var total_distance: float = _frames[-1][&"distance"]
	if total_distance <= 0.001:
		return _frames[0].duplicate()
	var distance := clampf(requested_distance, 0.0, total_distance)
	var low := 0
	var high := _frames.size() - 1
	while low + 1 < high:
		var midpoint := (low + high) / 2
		if float(_frames[midpoint][&"distance"]) < distance:
			low = midpoint
		else:
			high = midpoint
	var first: Dictionary = _frames[low]
	var second: Dictionary = _frames[high]
	var first_distance: float = first[&"distance"]
	var second_distance: float = second[&"distance"]
	var weight := inverse_lerp(first_distance, second_distance, distance) if second_distance > first_distance else 0.0
	var tangent := (first[&"tangent"] as Vector3).lerp(second[&"tangent"] as Vector3, weight).normalized()
	var right := (first[&"right"] as Vector3).lerp(second[&"right"] as Vector3, weight).normalized()
	var up := right.cross(tangent).normalized()
	return {
		&"position": (first[&"position"] as Vector3).lerp(second[&"position"] as Vector3, weight),
		&"tangent": tangent,
		&"right": right,
		&"up": up,
		&"distance": distance,
	}


func _frame_transform(frame: Dictionary) -> Transform3D:
	return Transform3D(
		Basis(frame[&"right"], frame[&"up"], -(frame[&"tangent"] as Vector3)).orthonormalized(),
		frame[&"position"]
	)


func _configure_noise() -> void:
	_terrain_noise.seed = TERRAIN_SEED
	_terrain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_terrain_noise.frequency = 0.012
	_terrain_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_terrain_noise.fractal_octaves = 4
	_terrain_noise.fractal_gain = 0.5
	_terrain_noise.fractal_lacunarity = 2.1


func _terrain_height_at(x: float, z: float) -> float:
	var broad_noise := _terrain_noise.get_noise_2d(x, z)
	var detail_noise := _terrain_noise.get_noise_2d(x * 3.1 + 481.0, z * 3.1 - 227.0)
	var base_height := 0.25 + broad_noise * 0.82 + detail_noise * 0.22 + z * 0.0016
	var radial_ratio := Vector2(x, z).length() / (TERRAIN_SIZE.x * 0.5)
	base_height += smoothstep(0.76, 1.0, radial_ratio) * 6.5
	var sample := _nearest_route_sample(x, z)
	var route_distance: float = sample[&"distance"]
	var route_height: float = sample[&"height"]
	var route_blend := 1.0 - smoothstep(18.0, 42.0, route_distance)
	var route_bed := route_height - TERRAIN_ROUTE_CLEARANCE
	var height := lerpf(base_height, route_bed, route_blend)
	# The hard ceiling protects every coarse terrain triangle that can feed the
	# shoulder envelope. Banking and welded jump relief remain safely above it.
	if route_distance <= _track_width * 0.5 + SHOULDER_WIDTH + TERRAIN_STEP * 1.5:
		height = minf(height, route_bed)
	return height


func _nearest_route_sample(x: float, z: float) -> Dictionary:
	var point := Vector2(x, z)
	var best_distance_squared := INF
	var best_height := 0.0
	for index: int in _ride_points.size() - 1:
		var start_3d := _ride_points[index]
		var finish_3d := _ride_points[index + 1]
		var start := Vector2(start_3d.x, start_3d.z)
		var segment := Vector2(finish_3d.x, finish_3d.z) - start
		var weight := clampf((point - start).dot(segment) / maxf(segment.length_squared(), 0.001), 0.0, 1.0)
		var distance_squared := point.distance_squared_to(start + segment * weight)
		if distance_squared < best_distance_squared:
			best_distance_squared = distance_squared
			best_height = lerpf(start_3d.y, finish_3d.y, weight)
	return {&"distance": sqrt(best_distance_squared), &"height": best_height}


func _add_static_box(
	parent: Node3D,
	node_name: String,
	size: Vector3,
	transform: Transform3D,
	material: Material,
	surface: StringName,
	roughness: float,
	roost: float
) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = 2
	body.collision_mask = 1
	body.transform = transform
	_tag_surface(body, surface, roughness, roost)
	parent.add_child(body)
	_add_body_box(body, "VisibleCollision", size, Vector3.ZERO, material)
	return body


func _add_static_cylinder(
	parent: Node3D,
	node_name: String,
	radius: float,
	height: float,
	transform: Transform3D,
	material: Material,
	collision_radius_ratio: float = 1.0
) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = 2
	body.collision_mask = 1
	body.transform = transform
	_tag_surface(body, &"ROCK", 1.08, 0.12)
	parent.add_child(body)
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.76
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 18
	mesh.material = material
	var visual := MeshInstance3D.new()
	visual.name = "VisibleCollision"
	visual.mesh = mesh
	body.add_child(visual)
	var shape := CylinderShape3D.new()
	shape.radius = radius * clampf(collision_radius_ratio, 0.1, 1.0)
	shape.height = height
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	return body


func _add_body_box(body: StaticBody3D, node_name: String, size: Vector3, position: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var visual := MeshInstance3D.new()
	visual.name = node_name
	visual.mesh = mesh
	visual.position = position
	body.add_child(visual)
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.name = "%sCollision" % node_name
	collision.shape = shape
	collision.position = position
	body.add_child(collision)


func _add_body_cylinder(body: StaticBody3D, node_name: String, radius: float, height: float, position: Vector3, material: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	mesh.material = material
	var visual := MeshInstance3D.new()
	visual.name = node_name
	visual.mesh = mesh
	visual.position = position
	body.add_child(visual)
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	var collision := CollisionShape3D.new()
	collision.name = "%sCollision" % node_name
	collision.shape = shape
	collision.position = position
	body.add_child(collision)


func _add_visual_box(parent: Node3D, node_name: String, size: Vector3, transform: Transform3D, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var visual := MeshInstance3D.new()
	visual.name = node_name
	visual.mesh = mesh
	visual.transform = transform
	parent.add_child(visual)
	return visual


func _add_visual_cylinder(
	parent: Node3D,
	node_name: String,
	radius: float,
	height: float,
	transform: Transform3D,
	material: Material,
	radial_segments: int = 12,
	bottom_radius: float = -1.0
) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius if bottom_radius < 0.0 else bottom_radius
	mesh.height = height
	mesh.radial_segments = radial_segments
	mesh.material = material
	var visual := MeshInstance3D.new()
	visual.name = node_name
	visual.mesh = mesh
	visual.transform = transform
	parent.add_child(visual)
	return visual


func _add_visual_sphere(parent: Node3D, node_name: String, radius: float, position: Vector3, material: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 7
	mesh.material = material
	var visual := MeshInstance3D.new()
	visual.name = node_name
	visual.mesh = mesh
	visual.position = position
	parent.add_child(visual)
	return visual


func _add_gate_label(parent: Node3D, text: String, position: Vector3, color: Color, font_size: int) -> void:
	var label := Label3D.new()
	label.name = "%sLabel" % text.replace(" ", "")
	label.text = text
	label.position = position
	label.font_size = font_size
	label.pixel_size = 0.007
	label.outline_size = 8
	label.modulate = color
	label.double_sided = true
	parent.add_child(label)


func _tag_surface(body: CollisionObject3D, surface: StringName, roughness: float, roost: float) -> void:
	body.set_meta(&"surface", surface)
	body.set_meta(&"roughness", roughness)
	body.set_meta(&"roost", roost)


func _mark_authoritative_track_surface(surface_root: Node) -> void:
	if surface_root == null:
		return
	surface_root.set_meta(&"authoritative_track_surface", true)
	surface_root.set_meta(&"authoritative_track_id", CourseCatalog.MESA_MX_ID)
	if surface_root is CollisionObject3D:
		(surface_root as CollisionObject3D).collision_layer |= CourseSurfaceBuilder.AUTHORITATIVE_RIDE_LAYER
	for collision_node: Node in surface_root.find_children("*", "CollisionObject3D", true, false):
		(collision_node as CollisionObject3D).collision_layer |= CourseSurfaceBuilder.AUTHORITATIVE_RIDE_LAYER
		collision_node.set_meta(&"authoritative_track_surface", true)
		collision_node.set_meta(&"authoritative_track_id", CourseCatalog.MESA_MX_ID)


func _material(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material
