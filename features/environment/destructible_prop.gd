extends RigidBody3D
class_name DestructibleProp
## Reusable lightweight breakaway prop with pooled impact dust and run reset.

var _spawn_transform: Transform3D
var _impact_dust: GPUParticles3D
var _impact_cooldown: float = 0.0


func _ready() -> void:
	_spawn_transform = global_transform
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)
	EventBus.race_reset.connect(reset_prop)
	EventBus.activity_started.connect(_on_activity_started)
	_build_impact_dust()


func _physics_process(delta: float) -> void:
	_impact_cooldown = maxf(_impact_cooldown - delta, 0.0)
	if global_position.y < -5.0:
		reset_prop()


func reset_prop() -> void:
	freeze = true
	global_transform = _spawn_transform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze = false
	sleeping = false
	_impact_dust.restart()
	_impact_dust.emitting = false


func _on_activity_started(_activity: StringName) -> void:
	reset_prop()


func _on_body_entered(body: Node) -> void:
	if _impact_cooldown > 0.0 or body is not DirtBikeController:
		return
	_impact_cooldown = 0.25
	_impact_dust.restart()


func _build_impact_dust() -> void:
	_impact_dust = GPUParticles3D.new()
	_impact_dust.amount = 18
	_impact_dust.lifetime = 0.42
	_impact_dust.one_shot = true
	_impact_dust.explosiveness = 0.94
	_impact_dust.local_coords = false
	_impact_dust.emitting = false
	_impact_dust.visibility_aabb = AABB(Vector3(-3.0, -2.0, -3.0), Vector3(6.0, 6.0, 6.0))
	var process_material := ParticleProcessMaterial.new()
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process_material.emission_sphere_radius = 0.35
	process_material.direction = Vector3.UP
	process_material.spread = 65.0
	process_material.initial_velocity_min = 1.5
	process_material.initial_velocity_max = 4.0
	process_material.gravity = Vector3(0.0, -5.0, 0.0)
	process_material.scale_min = 0.08
	process_material.scale_max = 0.22
	process_material.color = Color(0.54, 0.34, 0.18, 0.66)
	_impact_dust.process_material = process_material
	var debris := BoxMesh.new()
	debris.size = Vector3(0.08, 0.08, 0.08)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("8c5930")
	material.roughness = 1.0
	debris.material = material
	_impact_dust.draw_pass_1 = debris
	add_child(_impact_dust)
