extends Node3D
## Dense wooded enduro district using batched foliage and primitive collision landmarks.

var _track_points := PackedVector3Array([
	Vector3(0.0, 0.0, 35.0),
	Vector3(-12.0, 0.0, 5.0),
	Vector3(-30.0, 0.0, -22.0),
	Vector3(-10.0, 0.0, -50.0),
	Vector3(24.0, 0.0, -42.0),
	Vector3(42.0, 0.0, -12.0),
	Vector3(30.0, 0.0, 20.0),
	Vector3(0.0, 0.0, 35.0),
])

var _materials: Dictionary[StringName, StandardMaterial3D] = {}


func _ready() -> void:
	_create_materials()
	_build_ground()
	_build_trail()
	_build_creek_crossing()
	_build_jumps()
	_build_forest()
	_build_landmarks()


func _create_materials() -> void:
	_materials[&"forest_floor"] = _material(Color("38412b"), 1.0)
	_materials[&"trail"] = _material(Color("4d3324"), 1.0)
	_materials[&"rut"] = _material(Color("281d18"), 1.0)
	_materials[&"moss"] = _material(Color("53633b"), 0.98)
	_materials[&"bark"] = _material(Color("443126"), 1.0)
	_materials[&"pine"] = _material(Color("274a36"), 0.96)
	_materials[&"pine_light"] = _material(Color("3d6745"), 0.95)
	_materials[&"wood"] = _material(Color("755037"), 0.9)
	_materials[&"roof"] = _material(Color("29343a"), 0.62, 0.35)
	_materials[&"water"] = _material(Color(0.12, 0.42, 0.5, 0.68), 0.18)
	_materials[&"marker"] = _material(Color("e6b23d"), 0.55)


func _build_ground() -> void:
	_add_static_box("PineGround", Vector3(150.0, 1.0, 150.0), Vector3(0.0, -0.5, 0.0), &"forest_floor")
	_add_static_box("NorthRidge", Vector3(150.0, 8.0, 12.0), Vector3(0.0, 3.5, -78.0), &"moss", Vector3(0.0, 0.0, -0.04))
	_add_static_box("SouthRidge", Vector3(150.0, 7.0, 12.0), Vector3(0.0, 3.0, 78.0), &"moss", Vector3(0.0, 0.0, 0.04))
	_add_static_box("EastRidge", Vector3(12.0, 9.0, 150.0), Vector3(78.0, 4.0, 0.0), &"moss", Vector3(0.0, 0.0, 0.05))
	_add_static_box("WestRidge", Vector3(12.0, 9.0, 150.0), Vector3(-78.0, 4.0, 0.0), &"moss", Vector3(0.0, 0.0, -0.05))


func _build_trail() -> void:
	for index: int in _track_points.size() - 1:
		_add_trail_segment(_track_points[index], _track_points[index + 1], 9.0)


func _build_creek_crossing() -> void:
	var creek := BoxMesh.new()
	creek.size = Vector3(42.0, 0.06, 9.0)
	var creek_mesh := MeshInstance3D.new()
	creek_mesh.name = "Creek"
	creek_mesh.mesh = creek
	creek_mesh.position = Vector3(31.0, 0.04, 5.0)
	creek_mesh.rotation.y = -0.36
	creek_mesh.material_override = _materials[&"water"]
	add_child(creek_mesh)

	_add_static_box("LogBridge", Vector3(9.0, 0.28, 12.5), Vector3(36.0, 0.14, 4.0), &"wood", Vector3(0.0, -0.36, 0.0))
	for plank_index: int in 7:
		var local_offset := -5.0 + plank_index * 1.65
		var direction := Vector3(sin(-0.36), 0.0, cos(-0.36))
		var position := Vector3(36.0, 0.34, 4.0) + direction * local_offset
		_add_visual_box("BridgePlank%d" % plank_index, Vector3(9.4, 0.09, 0.45), position, &"wood", Vector3(0.0, -0.36, 0.0))


func _build_jumps() -> void:
	_add_wedge_ramp("RootRise", Vector3(-20.5, 0.04, -8.0), 0.588, 8.0, 7.0, 1.35, true)
	_add_wedge_ramp("RavineTakeoff", Vector3(-17.0, 0.04, -41.0), -0.62, 9.0, 7.5, 1.8, true)
	_add_wedge_ramp("RavineLanding", Vector3(-4.0, 0.04, -51.0), -0.62, 10.0, 8.5, 1.25, false)


func _build_forest() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42017
	var positions: Array[Vector3] = []
	var attempts := 0
	while positions.size() < 92 and attempts < 700:
		attempts += 1
		var candidate := Vector3(rng.randf_range(-68.0, 68.0), 0.0, rng.randf_range(-68.0, 68.0))
		if _distance_to_trail(candidate) < 8.5:
			continue
		if candidate.distance_to(Vector3(0.0, 0.0, 35.0)) < 12.0:
			continue
		positions.append(candidate)

	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.32
	trunk_mesh.bottom_radius = 0.48
	trunk_mesh.height = 5.0
	trunk_mesh.radial_segments = 7
	trunk_mesh.material = _materials[&"bark"]
	var canopy_mesh := CylinderMesh.new()
	canopy_mesh.top_radius = 0.15
	canopy_mesh.bottom_radius = 2.5
	canopy_mesh.height = 6.5
	canopy_mesh.radial_segments = 8
	canopy_mesh.material = _materials[&"pine"]
	_add_multimesh("ForestTrunks", trunk_mesh, positions, 2.5, false, rng)
	_add_multimesh("ForestCanopies", canopy_mesh, positions, 6.7, true, rng)

	for collision_index: int in mini(positions.size(), 18):
		var tree_position := positions[collision_index * 5 % positions.size()]
		var body := StaticBody3D.new()
		body.name = "TreeCollision%02d" % collision_index
		body.collision_layer = 2
		body.collision_mask = 1
		body.position = tree_position + Vector3.UP * 2.5
		add_child(body)
		var shape := CylinderShape3D.new()
		shape.radius = 0.48
		shape.height = 5.0
		var collision := CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)


func _build_landmarks() -> void:
	# Ranger cabin creates a recognizable final-sector landmark.
	_add_static_box("Cabin", Vector3(9.0, 4.5, 7.0), Vector3(-47.0, 2.25, 37.0), &"wood")
	_add_visual_box("CabinRoof", Vector3(11.0, 0.55, 8.5), Vector3(-47.0, 5.0, 37.0), &"roof", Vector3(0.0, 0.0, 0.13))
	_add_visual_box("CabinDoor", Vector3(2.0, 2.9, 0.12), Vector3(-47.0, 1.5, 33.45), &"bark")
	_add_visual_box("CabinWindow", Vector3(2.2, 1.4, 0.12), Vector3(-43.8, 2.6, 33.45), &"water")

	# Trailhead arch and timber stacks make the start area legible.
	_add_visual_box("TrailheadLeft", Vector3(0.5, 4.2, 0.5), Vector3(-5.2, 2.1, 39.0), &"wood")
	_add_visual_box("TrailheadRight", Vector3(0.5, 4.2, 0.5), Vector3(5.2, 2.1, 39.0), &"wood")
	_add_visual_box("TrailheadTop", Vector3(10.9, 0.55, 0.55), Vector3(0.0, 4.1, 39.0), &"marker")
	for log_index: int in 6:
		var log := CylinderMesh.new()
		log.top_radius = 0.42
		log.bottom_radius = 0.42
		log.height = 6.0
		log.radial_segments = 8
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = "Timber%d" % log_index
		mesh_instance.mesh = log
		mesh_instance.position = Vector3(51.0, 0.5 + log_index / 3 * 0.72, 40.0 + float(log_index % 3) * 0.95)
		mesh_instance.rotation.z = PI * 0.5
		mesh_instance.material_override = _materials[&"wood"]
		add_child(mesh_instance)


func _add_multimesh(
	node_name: String,
	mesh: Mesh,
	positions: Array[Vector3],
	height: float,
	vary_color: bool,
	rng: RandomNumberGenerator
) -> void:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = vary_color
	multimesh.mesh = mesh
	multimesh.instance_count = positions.size()
	for index: int in positions.size():
		var scale_value := rng.randf_range(0.78, 1.24)
		var basis := Basis.from_euler(Vector3(0.0, rng.randf_range(0.0, TAU), 0.0)).scaled(Vector3(scale_value, scale_value, scale_value))
		multimesh.set_instance_transform(index, Transform3D(basis, positions[index] + Vector3.UP * height * scale_value))
		if vary_color:
			multimesh.set_instance_color(index, Color(0.78 + rng.randf() * 0.18, 0.86 + rng.randf() * 0.12, 0.76 + rng.randf() * 0.16, 1.0))
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multimesh
	add_child(instance)


func _add_trail_segment(start: Vector3, end: Vector3, width: float) -> void:
	var delta := end - start
	var direction := delta.normalized()
	var right := Vector3(direction.z, 0.0, -direction.x)
	var yaw := atan2(delta.x, delta.z)
	var trail_mesh := BoxMesh.new()
	trail_mesh.size = Vector3(width, 0.08, delta.length())
	var trail := MeshInstance3D.new()
	trail.name = "TrailSegment"
	trail.mesh = trail_mesh
	trail.position = (start + end) * 0.5 + Vector3.UP * 0.04
	trail.rotation.y = yaw
	trail.material_override = _materials[&"trail"]
	add_child(trail)
	for side: float in [-1.0, 1.0]:
		var rut_mesh := BoxMesh.new()
		rut_mesh.size = Vector3(0.28, 0.035, delta.length() * 0.95)
		var rut := MeshInstance3D.new()
		rut.name = "TrailRut"
		rut.mesh = rut_mesh
		rut.position = (start + end) * 0.5 + right * side * 1.55 + Vector3.UP * 0.085
		rut.rotation.y = yaw
		rut.material_override = _materials[&"rut"]
		add_child(rut)


func _distance_to_trail(point: Vector3) -> float:
	var nearest := INF
	for index: int in _track_points.size() - 1:
		nearest = minf(nearest, _distance_to_segment_2d(point, _track_points[index], _track_points[index + 1]))
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


func _add_wedge_ramp(body_name: String, position: Vector3, yaw: float, length: float, width: float, height: float, high_negative_z: bool) -> void:
	var half_width := width * 0.5
	var half_length := length * 0.5
	var high_z := -half_length if high_negative_z else half_length
	var low_z := half_length if high_negative_z else -half_length
	var points := PackedVector3Array([
		Vector3(-half_width, height, high_z), Vector3(half_width, height, high_z),
		Vector3(-half_width, 0.0, low_z), Vector3(half_width, 0.0, low_z),
		Vector3(-half_width, -0.18, high_z), Vector3(half_width, -0.18, high_z),
		Vector3(-half_width, -0.18, low_z), Vector3(half_width, -0.18, low_z),
	])
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face: PackedInt32Array in [
		PackedInt32Array([0, 1, 3, 0, 3, 2]), PackedInt32Array([4, 7, 5, 4, 6, 7]),
		PackedInt32Array([0, 5, 1, 0, 4, 5]), PackedInt32Array([2, 3, 7, 2, 7, 6]),
		PackedInt32Array([0, 2, 6, 0, 6, 4]), PackedInt32Array([1, 5, 7, 1, 7, 3]),
	]:
		for point_index: int in face:
			surface_tool.add_vertex(points[point_index])
	surface_tool.generate_normals()
	var body := StaticBody3D.new()
	body.name = body_name
	body.collision_layer = 2
	body.collision_mask = 1
	body.position = position
	body.rotation.y = yaw
	add_child(body)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = surface_tool.commit()
	mesh_instance.material_override = _materials[&"trail"]
	body.add_child(mesh_instance)
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)


func _material(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material
