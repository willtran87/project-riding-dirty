extends Node3D
class_name ChaseCamera
## Speed-reactive chase camera with smooth position, predictive look-ahead, and landing response.

@export var follow_distance: float = 6.5
@export var follow_height: float = 2.75
@export var position_smoothing: float = 6.8
@export var rotation_smoothing: float = 9.0
@export var base_fov: float = 68.0
@export var maximum_fov: float = 84.0

@onready var _camera: Camera3D = %Camera3D

var target: Node3D
var _landing_kick: float = 0.0
var _boost_punch: float = 0.0
var _noise_time: float = 0.0


func _ready() -> void:
	_camera.current = true


func _process(delta: float) -> void:
	if target == null:
		return
	var rigid_target := target as RigidBody3D
	var velocity := rigid_target.linear_velocity if rigid_target != null else Vector3.ZERO
	var planar_speed := Vector3(velocity.x, 0.0, velocity.z).length()
	var target_forward := -target.global_transform.basis.z
	target_forward.y = 0.0
	if target_forward.length_squared() < 0.1:
		target_forward = Vector3.FORWARD
	target_forward = target_forward.normalized()

	var speed_ratio := clampf(planar_speed / 32.0, 0.0, 1.0)
	var dynamic_distance := follow_distance + speed_ratio * 1.25
	var desired_position := target.global_position - target_forward * dynamic_distance + Vector3.UP * (follow_height + speed_ratio * 0.45)
	var position_weight := 1.0 - exp(-position_smoothing * delta)
	global_position = global_position.lerp(desired_position, position_weight)

	_noise_time += delta * (4.0 + speed_ratio * 13.0)
	_landing_kick = move_toward(_landing_kick, 0.0, delta * 3.6)
	_boost_punch = move_toward(_boost_punch, 0.0, delta * 1.8)
	var shake_strength := speed_ratio * speed_ratio * 0.035 + _landing_kick * 0.12 + _boost_punch * _boost_punch * 0.055
	var shake := Vector3(sin(_noise_time * 1.7), cos(_noise_time * 2.3), 0.0) * shake_strength
	var look_target := target.global_position + target_forward * (1.0 + speed_ratio * 3.3) + Vector3.UP * (0.92 - _landing_kick * 0.3)
	var desired_basis := Basis.looking_at((look_target - global_position).normalized(), Vector3.UP)
	var rotation_weight := 1.0 - exp(-rotation_smoothing * delta)
	global_transform.basis = global_transform.basis.slerp(desired_basis, rotation_weight)
	_camera.position = shake
	var target_fov := minf(lerpf(base_fov, maximum_fov, speed_ratio) + _boost_punch * 6.0, maximum_fov + 4.0)
	_camera.fov = lerpf(_camera.fov, target_fov, 1.0 - exp(-4.5 * delta))


func snap_to_target() -> void:
	if target == null:
		return
	var forward := -target.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	global_position = target.global_position - forward * follow_distance + Vector3.UP * follow_height
	look_at(target.global_position + forward * 2.0 + Vector3.UP * 0.7, Vector3.UP)


func apply_landing_kick(intensity: float) -> void:
	_landing_kick = maxf(_landing_kick, intensity)


func apply_boost_punch(_flow_remaining: float = 0.0) -> void:
	_boost_punch = 1.0
