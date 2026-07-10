extends Node3D
## Deterministic, asset-free vertical-slice quarry assembled from game-ready primitives.

var _track_points := PackedVector3Array([
	Vector3(0.0, 0.0, 38.0),
	Vector3(0.0, 0.0, -43.0),
	Vector3(20.0, 0.0, -51.0),
	Vector3(42.0, 0.0, -42.0),
	Vector3(55.0, 0.0, -10.0),
	Vector3(53.0, 0.0, 22.0),
	Vector3(39.0, 0.0, 45.0),
	Vector3(13.0, 0.0, 52.0),
	Vector3(0.0, 0.0, 38.0),
])

var _materials: Dictionary[StringName, StandardMaterial3D] = {}


func _ready() -> void:
	_create_materials()
	_build_environment()
	_build_ground_and_walls()
	_build_track()
	_build_jump_line()
	_build_quarry_props()
	_build_course_markers()


func _create_materials() -> void:
	_materials[&"ground"] = _material(Color("6d452d"), 0.96)
	_materials[&"track"] = _material(Color("3f291f"), 1.0)
	_materials[&"rut"] = _material(Color("281b18"), 1.0)
	_materials[&"track_edge"] = _material(Color("a86535"), 0.92)
	_materials[&"cliff"] = _material(Color("8d5c3d"), 0.94)
	_materials[&"cliff_dark"] = _material(Color("593728"), 0.97)
	_materials[&"rock"] = _material(Color("4c4541"), 0.98)
	_materials[&"metal"] = _material(Color("333b3f"), 0.38, 0.64)
	_materials[&"yellow"] = _material(Color("e8a62a"), 0.5, 0.12)
	_materials[&"red"] = _material(Color("c84434"), 0.48, 0.08)
	_materials[&"cream"] = _material(Color("f0d58b"), 0.7)
	_materials[&"tire"] = _material(Color("16191b"), 0.98)
	_materials[&"scrub"] = _material(Color("71824a"), 0.95)


func _build_environment() -> void:
	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	var environment := Environment.new()
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("183d59")
	sky_material.sky_horizon_color = Color("91a8b3")
	sky_material.ground_bottom_color = Color("36271f")
	sky_material.ground_horizon_color = Color("8f5c43")
	sky_material.sun_angle_max = 12.0
	sky_material.sun_curve = 0.08
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("8092a2")
	environment.ambient_light_energy = 0.58
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = Color("879ba5")
	environment.fog_light_energy = 0.38
	environment.fog_density = 0.0028
	environment.fog_height = -2.0
	environment.fog_height_density = 0.07
	world_environment.environment = environment
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-52.0, -34.0, 0.0)
	sun.light_color = Color("ffd09b")
	sun.light_energy = 1.28
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 180.0
	add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.name = "SkyFill"
	fill.rotation_degrees = Vector3(42.0, 140.0, 0.0)
	fill.light_color = Color("6d91b3")
	fill.light_energy = 0.32
	fill.shadow_enabled = false
	add_child(fill)


func _build_ground_and_walls() -> void:
	_add_static_box("QuarryFloor", Vector3(150.0, 1.0, 150.0), Vector3(0.0, -0.5, 0.0), &"ground")
	_add_static_box("NorthCliff", Vector3(150.0, 17.0, 10.0), Vector3(0.0, 8.0, -78.0), &"cliff")
	_add_static_box("EastCliff", Vector3(10.0, 15.0, 150.0), Vector3(78.0, 7.0, 0.0), &"cliff_dark")
	_add_static_box("SouthCliff", Vector3(150.0, 10.0, 10.0), Vector3(0.0, 4.5, 78.0), &"cliff")
	_add_static_box("WestCliff", Vector3(10.0, 13.0, 150.0), Vector3(-78.0, 6.0, 0.0), &"cliff_dark")

	_add_static_box("NorthTerrace", Vector3(105.0, 4.0, 12.0), Vector3(-15.0, 1.5, -68.0), &"cliff_dark")
	_add_static_box("EastTerrace", Vector3(12.0, 4.0, 80.0), Vector3(68.0, 1.5, 14.0), &"cliff")
	_add_static_box("WestTerrace", Vector3(12.0, 5.0, 62.0), Vector3(-68.0, 2.0, -8.0), &"cliff")

	var rng := RandomNumberGenerator.new()
	rng.seed = 1987
	for index: int in 30:
		var side := index % 4
		var position := Vector3.ZERO
		match side:
			0:
				position = Vector3(rng.randf_range(-63.0, 63.0), 0.0, rng.randf_range(-70.0, -61.0))
			1:
				position = Vector3(rng.randf_range(61.0, 70.0), 0.0, rng.randf_range(-58.0, 58.0))
			2:
				position = Vector3(rng.randf_range(-63.0, 63.0), 0.0, rng.randf_range(62.0, 70.0))
			_:
				position = Vector3(rng.randf_range(-70.0, -61.0), 0.0, rng.randf_range(-58.0, 58.0))
		_add_boulder("Boulder%02d" % index, position, rng.randf_range(0.7, 2.4), index % 5 == 0)


func _build_track() -> void:
	for index: int in _track_points.size() - 1:
		_add_track_segment(_track_points[index], _track_points[index + 1], 12.0)

	# Broad inside berms imply the fast line through the oval.
	_add_static_box("NorthBerm", Vector3(28.0, 1.3, 2.0), Vector3(25.0, 0.35, -54.0), &"track_edge", Vector3(0.0, -0.34, -0.18))
	_add_static_box("EastBerm", Vector3(2.0, 1.5, 22.0), Vector3(60.0, 0.42, 5.0), &"track_edge", Vector3(0.12, 0.0, 0.22))
	_add_static_box("SouthBerm", Vector3(28.0, 1.4, 2.0), Vector3(28.0, 0.38, 55.0), &"track_edge", Vector3(0.0, 0.2, 0.18))


func _build_jump_line() -> void:
	_add_wedge_ramp("NorthTakeoff", Vector3(0.0, 0.04, -3.0), 0.0, 10.0, 9.5, 2.25, true)
	_add_wedge_ramp("NorthLanding", Vector3(0.0, 0.04, -19.5), 0.0, 12.0, 10.5, 1.75, false)
	_add_wedge_ramp("EastTableFace", Vector3(54.0, 0.04, 12.0), PI, 8.0, 8.0, 1.15, true)
	_add_static_box("EastTableTop", Vector3(8.0, 1.15, 7.0), Vector3(54.0, 0.575, 19.2), &"track")
	_add_wedge_ramp("EastTableDown", Vector3(54.0, 0.04, 26.5), PI, 8.0, 8.0, 1.15, false)


func _build_quarry_props() -> void:
	# Stylized excavator landmark above the north turn.
	_add_static_box("ExcavatorDeck", Vector3(7.2, 1.0, 3.7), Vector3(-32.0, 4.6, -67.0), &"yellow")
	_add_visual_box("ExcavatorCab", Vector3(2.5, 2.8, 2.5), Vector3(-33.5, 6.3, -67.0), &"yellow")
	_add_visual_box("ExcavatorWindow", Vector3(2.0, 1.4, 0.08), Vector3(-33.5, 6.65, -65.72), &"metal")
	_add_visual_box("ExcavatorBoom", Vector3(0.65, 0.65, 10.0), Vector3(-28.0, 7.2, -63.0), &"yellow", Vector3(-0.35, -0.62, 0.0))
	_add_visual_box("ExcavatorArm", Vector3(0.58, 0.58, 7.0), Vector3(-22.0, 5.0, -57.5), &"yellow", Vector3(0.5, -0.78, 0.0))
	for tread_index: int in 5:
		_add_visual_cylinder("ExcavatorTreadL%d" % tread_index, 0.68, 0.5, Vector3(-35.0 + tread_index * 1.45, 3.8, -68.7), &"tire", Vector3(0.0, 0.0, PI * 0.5))
		_add_visual_cylinder("ExcavatorTreadR%d" % tread_index, 0.68, 0.5, Vector3(-35.0 + tread_index * 1.45, 3.8, -65.3), &"tire", Vector3(0.0, 0.0, PI * 0.5))

	# Floodlights and a small timing shack frame the start area.
	_add_static_box("TimingShack", Vector3(6.5, 3.2, 4.0), Vector3(-10.0, 1.6, 42.0), &"cliff_dark")
	_add_visual_box("TimingStripe", Vector3(6.6, 0.45, 4.05), Vector3(-10.0, 2.2, 42.0), &"red")
	_add_visual_box("TimingWindow", Vector3(3.8, 1.0, 0.08), Vector3(-10.0, 1.75, 39.96), &"metal")
	for x_position: float in [-18.0, 18.0, 48.0]:
		_add_visual_cylinder("LightPole%d" % int(x_position), 0.12, 9.0, Vector3(x_position, 4.5, 57.0), &"metal")
		_add_visual_box("LightBar%d" % int(x_position), Vector3(2.6, 0.4, 0.45), Vector3(x_position, 8.9, 57.0), &"cream")


func _build_course_markers() -> void:
	for index: int in _track_points.size() - 1:
		var start := _track_points[index]
		var end := _track_points[index + 1]
		var direction := (end - start).normalized()
		var right := Vector3(direction.z, 0.0, -direction.x)
		var segment_length := start.distance_to(end)
		var marker_count := maxi(int(segment_length / 9.0), 1)
		for marker_index: int in marker_count:
			var weight := float(marker_index + 1) / float(marker_count + 1)
			var center := start.lerp(end, weight)
			if (index + marker_index) % 2 == 0:
				_add_cone("Marker%d_%d" % [index, marker_index], center + right * 6.3 + Vector3.UP * 0.42)


func _add_track_segment(start: Vector3, end: Vector3, width: float) -> void:
	var delta := end - start
	var direction := delta.normalized()
	var right := Vector3(direction.z, 0.0, -direction.x)
	var yaw := atan2(delta.x, delta.z)
	var box := BoxMesh.new()
	box.size = Vector3(width, 0.08, delta.length())
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "TrackSegment"
	mesh_instance.mesh = box
	mesh_instance.material_override = _materials[&"track"]
	mesh_instance.position = (start + end) * 0.5 + Vector3.UP * 0.035
	mesh_instance.rotation.y = yaw
	add_child(mesh_instance)
	for side: float in [-1.0, 1.0]:
		var rut_mesh := BoxMesh.new()
		rut_mesh.size = Vector3(0.34, 0.035, delta.length() * 0.96)
		var rut := MeshInstance3D.new()
		rut.name = "TrackRut"
		rut.mesh = rut_mesh
		rut.material_override = _materials[&"rut"]
		rut.position = (start + end) * 0.5 + right * side * 2.0 + Vector3.UP * 0.085
		rut.rotation.y = yaw
		add_child(rut)


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


func _add_wedge_ramp(
	body_name: String,
	position: Vector3,
	yaw: float,
	length: float,
	width: float,
	height: float,
	high_toward_negative_z: bool
) -> void:
	var half_width := width * 0.5
	var half_length := length * 0.5
	var high_z := -half_length if high_toward_negative_z else half_length
	var low_z := half_length if high_toward_negative_z else -half_length
	var bottom_y := -0.18
	var points := PackedVector3Array([
		Vector3(-half_width, height, high_z),
		Vector3(half_width, height, high_z),
		Vector3(-half_width, 0.0, low_z),
		Vector3(half_width, 0.0, low_z),
		Vector3(-half_width, bottom_y, high_z),
		Vector3(half_width, bottom_y, high_z),
		Vector3(-half_width, bottom_y, low_z),
		Vector3(half_width, bottom_y, low_z),
	])

	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_triangle(surface_tool, points[0], points[1], points[3])
	_add_triangle(surface_tool, points[0], points[3], points[2])
	_add_triangle(surface_tool, points[4], points[7], points[5])
	_add_triangle(surface_tool, points[4], points[6], points[7])
	_add_triangle(surface_tool, points[0], points[5], points[1])
	_add_triangle(surface_tool, points[0], points[4], points[5])
	_add_triangle(surface_tool, points[2], points[3], points[7])
	_add_triangle(surface_tool, points[2], points[7], points[6])
	_add_triangle(surface_tool, points[0], points[2], points[6])
	_add_triangle(surface_tool, points[0], points[6], points[4])
	_add_triangle(surface_tool, points[1], points[5], points[7])
	_add_triangle(surface_tool, points[1], points[7], points[3])
	surface_tool.generate_normals()
	var ramp_mesh := surface_tool.commit()

	var body := StaticBody3D.new()
	body.name = body_name
	body.collision_layer = 2
	body.collision_mask = 1
	body.position = position
	body.rotation.y = yaw
	add_child(body)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = ramp_mesh
	mesh_instance.material_override = _materials[&"track"]
	body.add_child(mesh_instance)

	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)


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
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = body_name
		mesh_instance.mesh = sphere
		mesh_instance.material_override = _materials[&"rock"]
		mesh_instance.position = position + Vector3.UP * radius * 0.72
		mesh_instance.rotation = Vector3(radius * 0.17, radius * 0.31, radius * 0.11)
		add_child(mesh_instance)


func _add_cone(mesh_name: String, position: Vector3) -> void:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.05
	cone.bottom_radius = 0.34
	cone.height = 0.84
	cone.radial_segments = 8
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = mesh_name
	mesh_instance.mesh = cone
	mesh_instance.position = position
	mesh_instance.material_override = _materials[&"cream"]
	add_child(mesh_instance)


func _material(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = roughness
	result.metallic = metallic
	return result
