extends RigidBody3D
class_name DirtBikeController
## Two-point ray suspension with arcade balance, steering, air control, and recovery.

signal telemetry_updated(speed_mph: float, throttle: float, grounded: bool)
signal landed(intensity: float)
signal airtime_started()
signal trick_landed(airtime: float, rotation_amount: float, landing_intensity: float, clean: bool)
signal flow_changed(value: float, boosting: bool)
signal flow_gained(amount: float)
signal boost_activated(flow_remaining: float)

@export_category("Drive")
@export var engine_force: float = 3600.0
@export var reverse_force: float = 1050.0
@export var brake_drag: float = 520.0
@export var lateral_grip: float = 440.0
@export var rolling_drag: float = 24.0
@export var maximum_speed_mps: float = 34.0

@export_category("Suspension")
@export var suspension_rest_length: float = 0.55
@export var wheel_radius: float = 0.37
@export var spring_stiffness: float = 7200.0
@export var spring_damping: float = 760.0

@export_category("Handling")
@export var steering_torque: float = 980.0
@export var upright_strength: float = 1850.0
@export var upright_damping: float = 180.0
@export var maximum_lean_degrees: float = 24.0
@export var air_pitch_torque: float = 520.0
@export var air_roll_torque: float = 380.0
@export var preload_impulse: float = 230.0

@export_category("Flow Boost")
@export var flow_capacity: float = 100.0
@export var flow_boost_cost: float = 35.0
@export var flow_boost_duration: float = 1.15
@export var flow_boost_force: float = 2700.0
@export var flow_boost_impulse: float = 4.2

@onready var _front_ray: RayCast3D = %FrontSuspension
@onready var _rear_ray: RayCast3D = %RearSuspension
@onready var _visual: Node3D = %BikeVisual
@onready var _engine_audio: AudioStreamPlayer3D = %EngineAudio

var controls_enabled: bool = false

var _front_distance: float = 0.92
var _rear_distance: float = 0.92
var _grounded: bool = false
var _was_grounded: bool = false
var _airborne_fall_speed: float = 0.0
var _wheel_spin: float = 0.0
var _preload_charge: float = 0.0
var _telemetry_time: float = 0.0
var _safe_sample_time: float = 0.0
var _last_safe_transform: Transform3D
var _airtime: float = 0.0
var _air_rotation: float = 0.0
var _base_engine_force: float = 3600.0
var _base_lateral_grip: float = 440.0
var _base_maximum_speed_mps: float = 34.0
var _flow: float = 0.0
var _boost_time: float = 0.0


func _ready() -> void:
	_last_safe_transform = global_transform
	can_sleep = false
	_base_engine_force = engine_force
	_base_lateral_grip = lateral_grip
	_base_maximum_speed_mps = maximum_speed_mps


func _physics_process(delta: float) -> void:
	_front_distance = _apply_suspension(_front_ray, delta)
	_rear_distance = _apply_suspension(_rear_ray, delta)
	_was_grounded = _grounded
	_grounded = _front_ray.is_colliding() or _rear_ray.is_colliding()

	var throttle := InputRouter.get_throttle() if controls_enabled else 0.0
	var brake := InputRouter.get_brake() if controls_enabled else 1.0
	var steer := InputRouter.get_steer() if controls_enabled else 0.0
	var lean := InputRouter.get_lean() if controls_enabled else 0.0
	_handle_flow_boost(delta)

	if _grounded:
		_apply_ground_drive(throttle, brake, steer)
		_apply_balance(steer)
		_handle_preload(delta)
		_safe_sample_time += delta
		if _safe_sample_time >= 0.65 and global_transform.basis.y.dot(Vector3.UP) > 0.45:
			_update_safe_transform()
			_safe_sample_time = 0.0
	else:
		_preload_charge = 0.0
		if _was_grounded:
			_airtime = 0.0
			_air_rotation = 0.0
			airtime_started.emit()
		_airtime += delta
		_air_rotation += angular_velocity.length() * delta
		_apply_air_control(steer, lean)
		_airborne_fall_speed = maxf(_airborne_fall_speed, -linear_velocity.y)

	if _grounded and not _was_grounded:
		var intensity := clampf((_airborne_fall_speed - 2.0) / 10.0, 0.0, 1.0)
		if intensity > 0.05:
			landed.emit(intensity)
			_visual.call(&"burst_landing_dust", intensity)
		if _airtime >= 0.12:
			var clean_landing := global_transform.basis.y.normalized().dot(_get_ground_normal()) > 0.48 and intensity < 0.9
			trick_landed.emit(_airtime, _air_rotation, intensity, clean_landing)
			_award_landing_flow(_airtime, _air_rotation, clean_landing)
		_airtime = 0.0
		_air_rotation = 0.0
		_airborne_fall_speed = 0.0

	var planar_velocity := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	var speed_mps := planar_velocity.length()
	_wheel_spin = fmod(_wheel_spin + speed_mps / wheel_radius * delta, TAU)
	var front_y := _wheel_center_y(_front_ray, _front_distance)
	var rear_y := _wheel_center_y(_rear_ray, _rear_distance)
	var dust_amount := clampf((speed_mps - 2.0) / 16.0, 0.0, 1.0) * maxf(throttle, 0.22)
	_visual.call(&"update_pose", front_y, rear_y, _wheel_spin, steer, lean, dust_amount if _grounded else 0.0)
	_engine_audio.call(&"set_engine_state", speed_mps, throttle, _grounded)

	_telemetry_time += delta
	if _telemetry_time >= 0.08:
		telemetry_updated.emit(speed_mps * 2.236936, throttle, _grounded)
		_telemetry_time = 0.0

	if global_position.y < -12.0:
		reset_to_safe_position()


func set_controls_enabled(enabled: bool) -> void:
	controls_enabled = enabled
	if not enabled and is_boosting():
		_boost_time = 0.0
		flow_changed.emit(_flow, false)


func reset_to_safe_position() -> void:
	respawn_at(_last_safe_transform)


func respawn_at(spawn_transform: Transform3D) -> void:
	freeze = true
	global_transform = spawn_transform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze = false
	sleeping = false
	_last_safe_transform = spawn_transform
	_airborne_fall_speed = 0.0
	_airtime = 0.0
	_air_rotation = 0.0
	_reset_flow()


func get_speed_mps() -> float:
	return Vector3(linear_velocity.x, 0.0, linear_velocity.z).length()


func get_flow() -> float:
	return _flow


func is_boosting() -> bool:
	return _boost_time > 0.0


func apply_setup(setup: StringName) -> void:
	match setup:
		&"TRAIL":
			engine_force = 3300.0
			reverse_force = 1120.0
			lateral_grip = 520.0
			spring_stiffness = 6800.0
			maximum_speed_mps = 31.0
			maximum_lean_degrees = 21.0
		&"ATTACK":
			engine_force = 4200.0
			reverse_force = 980.0
			lateral_grip = 370.0
			spring_stiffness = 7900.0
			maximum_speed_mps = 38.0
			maximum_lean_degrees = 28.0
		_:
			engine_force = 3600.0
			reverse_force = 1050.0
			lateral_grip = 440.0
			spring_stiffness = 7200.0
			maximum_speed_mps = 34.0
			maximum_lean_degrees = 24.0
	_base_engine_force = engine_force
	_base_lateral_grip = lateral_grip
	_base_maximum_speed_mps = maximum_speed_mps


func apply_condition(condition: int) -> void:
	var condition_ratio := clampf(float(condition) / 100.0, 0.0, 1.0)
	engine_force = _base_engine_force * lerpf(0.82, 1.0, condition_ratio)
	lateral_grip = _base_lateral_grip * lerpf(0.9, 1.0, condition_ratio)
	maximum_speed_mps = _base_maximum_speed_mps * lerpf(0.9, 1.0, condition_ratio)


func _apply_suspension(ray: RayCast3D, delta: float) -> float:
	ray.force_raycast_update()
	if not ray.is_colliding():
		return ray.target_position.length()
	var contact_point := ray.get_collision_point()
	var contact_distance := ray.global_position.distance_to(contact_point)
	var desired_distance := suspension_rest_length + wheel_radius
	var compression := clampf(desired_distance - contact_distance, 0.0, suspension_rest_length)
	var force_offset := ray.global_position - global_position
	var point_velocity := linear_velocity + angular_velocity.cross(force_offset)
	var suspension_up := ray.global_transform.basis.y.normalized()
	var damping_force := point_velocity.dot(suspension_up) * spring_damping
	var spring_force := maxf(compression * spring_stiffness - damping_force, 0.0)
	apply_force(suspension_up * spring_force, force_offset)
	return contact_distance


func _apply_ground_drive(throttle: float, brake: float, steer: float) -> void:
	var ground_up := _get_ground_normal()
	var forward := -global_transform.basis.z
	forward = forward.slide(ground_up).normalized()
	var right := forward.cross(ground_up).normalized()
	var forward_speed := linear_velocity.dot(forward)
	var lateral_speed := linear_velocity.dot(right)

	var speed_limit := maximum_speed_mps * (1.18 if is_boosting() else 1.0)
	if throttle > 0.0:
		var speed_factor := 1.0 - clampf(maxf(forward_speed, 0.0) / speed_limit, 0.0, 0.94)
		apply_central_force(forward * throttle * engine_force * speed_factor)
	if is_boosting():
		var boost_falloff := clampf(_boost_time / 0.22, 0.15, 1.0)
		apply_central_force(forward * flow_boost_force * boost_falloff)
	if brake > 0.0:
		if forward_speed > 1.0:
			apply_central_force(-forward * forward_speed * brake_drag * brake)
		elif absf(forward_speed) < 3.5:
			apply_central_force(-forward * reverse_force * brake)

	apply_central_force(-right * lateral_speed * lateral_grip)
	var planar_velocity := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	apply_central_force(-planar_velocity * rolling_drag)
	var steer_authority := clampf(absf(forward_speed) / 4.0, 0.18, 1.0)
	var reverse_sign := -1.0 if forward_speed < -0.5 else 1.0
	apply_torque(ground_up * -steer * steering_torque * steer_authority * reverse_sign)

	if planar_velocity.length() > speed_limit:
		var excess := planar_velocity.length() - speed_limit
		apply_central_force(-planar_velocity.normalized() * excess * mass * 7.0)


func _handle_flow_boost(delta: float) -> void:
	var was_boosting := is_boosting()
	_boost_time = maxf(_boost_time - delta, 0.0)
	if controls_enabled and _grounded and InputRouter.is_flow_boost_just_pressed() and _flow >= flow_boost_cost:
		_flow -= flow_boost_cost
		_boost_time = flow_boost_duration
		var forward := -global_transform.basis.z.slide(_get_ground_normal()).normalized()
		apply_central_impulse(forward * mass * flow_boost_impulse)
		flow_changed.emit(_flow, true)
		boost_activated.emit(_flow)
	elif was_boosting and not is_boosting():
		flow_changed.emit(_flow, false)


func _award_landing_flow(airtime: float, rotation_amount: float, clean: bool) -> void:
	if not controls_enabled or not clean or airtime < 0.45:
		return
	var rotation_turns := minf(rotation_amount / TAU, 2.0)
	var requested_gain := clampf(22.0 + airtime * 20.0 + rotation_turns * 12.0, 14.0, 45.0)
	var previous_flow := _flow
	_flow = minf(_flow + requested_gain, flow_capacity)
	var actual_gain := _flow - previous_flow
	if actual_gain <= 0.01:
		return
	flow_gained.emit(actual_gain)
	flow_changed.emit(_flow, is_boosting())


func _reset_flow() -> void:
	var had_flow := _flow > 0.01 or is_boosting()
	_flow = 0.0
	_boost_time = 0.0
	if had_flow:
		flow_changed.emit(_flow, false)


func _apply_balance(steer: float) -> void:
	var ground_up := _get_ground_normal()
	var current_up := global_transform.basis.y.normalized()
	var forward := -global_transform.basis.z.slide(ground_up).normalized()
	if forward.length_squared() < 0.5:
		forward = Vector3.FORWARD
	var speed_factor := clampf(get_speed_mps() / 13.0, 0.0, 1.0)
	var target_lean := deg_to_rad(maximum_lean_degrees) * steer * speed_factor
	var target_up := Basis(forward, target_lean) * ground_up
	var correction_axis := current_up.cross(target_up)
	var corrective_torque := correction_axis * upright_strength - angular_velocity * upright_damping
	apply_torque(corrective_torque)


func _apply_air_control(steer: float, lean: float) -> void:
	var right := global_transform.basis.x.normalized()
	var forward := -global_transform.basis.z.normalized()
	apply_torque(right * lean * air_pitch_torque)
	apply_torque(forward * -steer * air_roll_torque)
	apply_torque(-angular_velocity * 18.0)


func _handle_preload(delta: float) -> void:
	if not controls_enabled:
		_preload_charge = 0.0
		return
	if InputRouter.is_preload_pressed():
		_preload_charge = minf(_preload_charge + delta, 0.5)
	elif InputRouter.is_preload_just_released() and _preload_charge > 0.08:
		var charge_ratio := _preload_charge / 0.5
		var forward := -global_transform.basis.z.slide(Vector3.UP).normalized()
		apply_central_impulse(Vector3.UP * preload_impulse * charge_ratio + forward * preload_impulse * 0.24 * charge_ratio)
		_preload_charge = 0.0


func _get_ground_normal() -> Vector3:
	var normal := Vector3.ZERO
	var count := 0
	if _front_ray.is_colliding():
		normal += _front_ray.get_collision_normal()
		count += 1
	if _rear_ray.is_colliding():
		normal += _rear_ray.get_collision_normal()
		count += 1
	return normal.normalized() if count > 0 else Vector3.UP


func _wheel_center_y(ray: RayCast3D, distance: float) -> float:
	if not ray.is_colliding():
		return ray.position.y - suspension_rest_length
	return ray.position.y - maxf(distance - wheel_radius, 0.0)


func _update_safe_transform() -> void:
	var flat_forward := -global_transform.basis.z
	flat_forward.y = 0.0
	if flat_forward.length_squared() < 0.2:
		return
	flat_forward = flat_forward.normalized()
	_last_safe_transform = Transform3D(Basis.looking_at(flat_forward, Vector3.UP), global_position + Vector3.UP * 0.65)
