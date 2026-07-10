extends Node3D
## Builds and animates a compact low-poly dirt bike and rider.

var _front_wheel_pivot: Node3D
var _rear_wheel_pivot: Node3D
var _front_assembly: Node3D
var _rider_root: Node3D
var _dust: GPUParticles3D
var _landing_dust: GPUParticles3D

var _materials: Dictionary[StringName, StandardMaterial3D] = {}


func _ready() -> void:
	_create_materials()
	_build_bike()
	_build_dust()


func update_pose(
	front_wheel_y: float,
	rear_wheel_y: float,
	wheel_spin: float,
	steer: float,
	lean: float,
	dust_amount: float
) -> void:
	_front_wheel_pivot.position.y = front_wheel_y
	_rear_wheel_pivot.position.y = rear_wheel_y
	_front_wheel_pivot.rotation.x = wheel_spin
	_rear_wheel_pivot.rotation.x = wheel_spin
	_front_assembly.rotation.y = steer * 0.42
	_rider_root.rotation.x = lerpf(_rider_root.rotation.x, lean * 0.16, 0.18)
	_dust.emitting = dust_amount > 0.08
	_dust.amount_ratio = clampf(dust_amount, 0.0, 1.0)


func burst_landing_dust(intensity: float) -> void:
	_landing_dust.amount_ratio = clampf(intensity, 0.25, 1.0)
	_landing_dust.restart()


func _create_materials() -> void:
	_materials[&"red"] = _material(Color("d93a2f"), 0.34, 0.05)
	_materials[&"cream"] = _material(Color("f5d67b"), 0.55, 0.0)
	_materials[&"rubber"] = _material(Color("111318"), 0.94, 0.0)
	_materials[&"metal"] = _material(Color("323842"), 0.28, 0.72)
	_materials[&"engine"] = _material(Color("171b20"), 0.42, 0.62)
	_materials[&"denim"] = _material(Color("1a365d"), 0.78, 0.0)
	_materials[&"helmet"] = _material(Color("f2b632"), 0.25, 0.12)
	_materials[&"visor"] = _material(Color("19232f"), 0.08, 0.55)


func _build_bike() -> void:
	_front_wheel_pivot = Node3D.new()
	_front_wheel_pivot.name = "FrontWheelPivot"
	_front_wheel_pivot.position = Vector3(0.0, -0.39, -1.18)
	add_child(_front_wheel_pivot)
	_add_wheel(_front_wheel_pivot)

	_rear_wheel_pivot = Node3D.new()
	_rear_wheel_pivot.name = "RearWheelPivot"
	_rear_wheel_pivot.position = Vector3(0.0, -0.39, 1.05)
	add_child(_rear_wheel_pivot)
	_add_wheel(_rear_wheel_pivot)

	_add_box("Engine", Vector3(0.48, 0.5, 0.65), Vector3(0.0, 0.12, 0.15), &"engine")
	_add_box("FuelTank", Vector3(0.52, 0.48, 0.84), Vector3(0.0, 0.52, -0.28), &"red", Vector3(-0.12, 0.0, 0.0))
	_add_box("Seat", Vector3(0.43, 0.18, 0.92), Vector3(0.0, 0.66, 0.48), &"rubber")
	_add_box("RearFender", Vector3(0.5, 0.1, 0.9), Vector3(0.0, 0.62, 0.92), &"red", Vector3(0.1, 0.0, 0.0))
	_add_box("FrontFender", Vector3(0.5, 0.09, 0.72), Vector3(0.0, 0.2, -1.18), &"cream", Vector3(-0.12, 0.0, 0.0))
	_add_box("NumberPlate", Vector3(0.5, 0.46, 0.08), Vector3(0.0, 0.55, -0.94), &"cream", Vector3(-0.18, 0.0, 0.0))

	_add_cylinder_between("FrameTop", Vector3(0.0, 0.52, -0.4), Vector3(0.0, 0.0, 0.48), 0.065, &"red")
	_add_cylinder_between("FrameRear", Vector3(0.0, 0.1, 0.28), Vector3(0.0, -0.27, 1.03), 0.055, &"metal")
	_add_cylinder_between("Exhaust", Vector3(-0.24, 0.12, 0.0), Vector3(-0.25, 0.45, 0.95), 0.07, &"metal")

	_front_assembly = Node3D.new()
	_front_assembly.name = "FrontAssembly"
	add_child(_front_assembly)
	_add_cylinder_between("ForkLeft", Vector3(-0.16, 0.65, -0.76), Vector3(-0.16, -0.32, -1.18), 0.045, &"metal", _front_assembly)
	_add_cylinder_between("ForkRight", Vector3(0.16, 0.65, -0.76), Vector3(0.16, -0.32, -1.18), 0.045, &"metal", _front_assembly)
	_add_box("Handlebar", Vector3(0.86, 0.055, 0.055), Vector3(0.0, 0.76, -0.82), &"metal", Vector3.ZERO, _front_assembly)

	_rider_root = Node3D.new()
	_rider_root.name = "RiderRoot"
	_rider_root.position = Vector3(0.0, 0.15, 0.15)
	add_child(_rider_root)
	_add_box("RiderTorso", Vector3(0.58, 0.72, 0.38), Vector3(0.0, 1.05, 0.05), &"red", Vector3(-0.2, 0.0, 0.0), _rider_root)
	_add_box("RiderHips", Vector3(0.48, 0.28, 0.38), Vector3(0.0, 0.72, 0.34), &"denim", Vector3(-0.1, 0.0, 0.0), _rider_root)
	_add_sphere("Helmet", 0.27, Vector3(0.0, 1.58, -0.16), &"helmet", _rider_root)
	_add_box("Visor", Vector3(0.36, 0.13, 0.12), Vector3(0.0, 1.59, -0.38), &"visor", Vector3(-0.1, 0.0, 0.0), _rider_root)
	_add_cylinder_between("LeftArm", Vector3(-0.25, 1.3, -0.02), Vector3(-0.37, 0.86, -0.72), 0.075, &"red", _rider_root)
	_add_cylinder_between("RightArm", Vector3(0.25, 1.3, -0.02), Vector3(0.37, 0.86, -0.72), 0.075, &"red", _rider_root)
	_add_cylinder_between("LeftLeg", Vector3(-0.2, 0.78, 0.28), Vector3(-0.22, 0.12, 0.48), 0.095, &"denim", _rider_root)
	_add_cylinder_between("RightLeg", Vector3(0.2, 0.78, 0.28), Vector3(0.22, 0.12, 0.48), 0.095, &"denim", _rider_root)


func _build_dust() -> void:
	_dust = _create_dust_emitter(false)
	_dust.name = "TrailDust"
	_dust.position = Vector3(0.0, -0.25, 1.12)
	add_child(_dust)

	_landing_dust = _create_dust_emitter(true)
	_landing_dust.name = "LandingDust"
	_landing_dust.position = Vector3(0.0, -0.35, 0.0)
	add_child(_landing_dust)


func _create_dust_emitter(one_shot: bool) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = 42 if one_shot else 58
	particles.lifetime = 0.72 if one_shot else 0.9
	particles.one_shot = one_shot
	particles.local_coords = false
	particles.explosiveness = 0.9 if one_shot else 0.15
	particles.visibility_aabb = AABB(Vector3(-5.0, -2.0, -5.0), Vector3(10.0, 7.0, 10.0))

	var process_material := ParticleProcessMaterial.new()
	process_material.direction = Vector3(0.0, 0.8, 1.0)
	process_material.spread = 52.0
	process_material.initial_velocity_min = 1.0
	process_material.initial_velocity_max = 3.8 if one_shot else 2.5
	process_material.gravity = Vector3(0.0, -1.2, 0.0)
	process_material.scale_min = 0.3
	process_material.scale_max = 0.95
	process_material.color = Color(0.44, 0.27, 0.14, 0.38)
	particles.process_material = process_material

	var puff := SphereMesh.new()
	puff.radius = 0.15
	puff.height = 0.24
	puff.radial_segments = 7
	puff.rings = 4
	var dust_material := StandardMaterial3D.new()
	dust_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dust_material.albedo_color = Color(0.58, 0.38, 0.2, 0.32)
	dust_material.roughness = 1.0
	puff.material = dust_material
	particles.draw_pass_1 = puff
	particles.emitting = false
	return particles


func _add_wheel(parent: Node3D) -> void:
	var tire := TorusMesh.new()
	tire.inner_radius = 0.245
	tire.outer_radius = 0.37
	tire.rings = 18
	tire.ring_segments = 10
	var tire_mesh := MeshInstance3D.new()
	tire_mesh.name = "Tire"
	tire_mesh.mesh = tire
	tire_mesh.material_override = _materials[&"rubber"]
	tire_mesh.rotation.z = PI * 0.5
	parent.add_child(tire_mesh)

	var hub := CylinderMesh.new()
	hub.height = 0.18
	hub.top_radius = 0.09
	hub.bottom_radius = 0.09
	var hub_mesh := MeshInstance3D.new()
	hub_mesh.name = "Hub"
	hub_mesh.mesh = hub
	hub_mesh.material_override = _materials[&"metal"]
	hub_mesh.rotation.z = PI * 0.5
	parent.add_child(hub_mesh)


func _add_box(
	mesh_name: String,
	size: Vector3,
	position: Vector3,
	material_key: StringName,
	rotation: Vector3 = Vector3.ZERO,
	parent: Node3D = self
) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = mesh_name
	mesh_instance.mesh = box
	mesh_instance.position = position
	mesh_instance.rotation = rotation
	mesh_instance.material_override = _materials[material_key]
	parent.add_child(mesh_instance)
	return mesh_instance


func _add_sphere(
	mesh_name: String,
	radius: float,
	position: Vector3,
	material_key: StringName,
	parent: Node3D = self
) -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 12
	sphere.rings = 7
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = mesh_name
	mesh_instance.mesh = sphere
	mesh_instance.position = position
	mesh_instance.material_override = _materials[material_key]
	parent.add_child(mesh_instance)
	return mesh_instance


func _add_cylinder_between(
	mesh_name: String,
	start: Vector3,
	end: Vector3,
	radius: float,
	material_key: StringName,
	parent: Node3D = self
) -> MeshInstance3D:
	var direction := end - start
	var cylinder := CylinderMesh.new()
	cylinder.height = direction.length()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.radial_segments = 8
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = mesh_name
	mesh_instance.mesh = cylinder
	mesh_instance.position = (start + end) * 0.5
	mesh_instance.quaternion = Quaternion(Vector3.UP, direction.normalized())
	mesh_instance.material_override = _materials[material_key]
	parent.add_child(mesh_instance)
	return mesh_instance


func _material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = roughness
	result.metallic = metallic
	return result
