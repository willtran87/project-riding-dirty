extends RigidBody3D
class_name DirtBikeController
## Two-point ray suspension with arcade balance, steering, air control, and recovery.

const RECOVERY_TIPPED: StringName = &"AUTO_TIPPED"
const RECOVERY_WORLD_FALL: StringName = &"AUTO_WORLD_FALL"
const BIKE_BUILD_SCRIPT := preload("res://features/career/racing_bike_build.gd")
const RACECRAFT_RULES := preload("res://features/race/racecraft_rules.gd")
const GATE_LAUNCH_MIN_MULTIPLIER := 0.94
const GATE_LAUNCH_MAX_MULTIPLIER := 1.08
const GATE_LAUNCH_DEFAULT_DURATION := 0.90

class WheelContact:
	var colliding: bool = false
	var point: Vector3 = Vector3.ZERO
	var normal: Vector3 = Vector3.UP
	var forward: Vector3 = Vector3.FORWARD
	var right: Vector3 = Vector3.RIGHT
	var raw_distance: float = 0.907
	var distance: float = 0.907
	var compression: float = 0.0
	var compression_velocity: float = 0.0
	var load: float = 0.0
	var longitudinal_speed: float = 0.0
	var lateral_speed: float = 0.0
	var slip: float = 0.0
	var grip_usage: float = 0.0
	var surface: StringName = &"PACKED"
	var roughness: float = 0.35
	var roost: float = 0.8
	var friction: float = 1.0
	var drag: float = 1.0
	var collider_id: int = 0


const SURFACE_FRICTION: Dictionary[StringName, float] = {
	&"PACKED": 1.0,
	&"DIRT": 0.98,
	&"LOAM": 0.95,
	&"LOOSE_DIRT": 0.88,
	&"GRAVEL": 0.9,
	&"MUD": 0.76,
	&"ROCK": 1.02,
}
const SURFACE_DRAG: Dictionary[StringName, float] = {
	&"PACKED": 1.0,
	&"DIRT": 1.05,
	&"LOAM": 1.08,
	&"LOOSE_DIRT": 1.18,
	&"GRAVEL": 1.12,
	&"MUD": 1.85,
	&"ROCK": 1.05,
}
const SURFACE_ROUGHNESS: Dictionary[StringName, float] = {
	&"PACKED": 0.35,
	&"DIRT": 0.62,
	&"LOAM": 0.72,
	&"LOOSE_DIRT": 0.65,
	&"GRAVEL": 0.8,
	&"MUD": 0.45,
	&"ROCK": 0.9,
}
const SURFACE_ROOST: Dictionary[StringName, float] = {
	&"PACKED": 0.8,
	&"DIRT": 1.22,
	&"LOAM": 1.38,
	&"LOOSE_DIRT": 1.35,
	&"GRAVEL": 1.0,
	&"MUD": 1.5,
	&"ROCK": 0.2,
}

signal telemetry_updated(speed_mph: float, throttle: float, grounded: bool)
signal landed(intensity: float)
signal airtime_started()
signal trick_landed(airtime: float, rotation_amount: float, landing_intensity: float, clean: bool)
signal flow_changed(value: float, boosting: bool)
signal flow_gained(amount: float)
signal boost_activated(flow_remaining: float)
signal style_event(label: StringName, base_points: int)
signal pack_contacted(intensity: float)
signal respawned()
signal racecraft_state_changed(snapshot: Dictionary)
signal racecraft_event(kind: StringName, payload: Dictionary)
## Emitted before an automatic recovery. A race controller can synchronously
## respawn the bike at its authoritative legal rejoin; otherwise the bike falls
## back to its locally sampled safe transform.
signal automatic_recovery_requested(reason: StringName)
signal terrain_feedback_updated(
	surface: StringName,
	roughness: float,
	rear_slip: float,
	front_compression: float,
	rear_compression: float,
	suspension_activity: float
)

@export_category("Drive")
@export var engine_force: float = 1200.0
@export var reverse_force: float = 1050.0
@export var brake_force: float = 2880.0
@export var lateral_grip: float = 620.0
@export var rolling_drag: float = 0.0
@export var grid_hold_grip: float = 900.0
@export var maximum_speed_mps: float = 30.0
@export var hill_assist_force: float = 1000.0

@export_category("Suspension")
@export var suspension_rest_length: float = 0.6
@export var wheel_radius: float = 0.307
@export var spring_stiffness: float = 20000.0
@export var spring_compression_damping: float = 380.0
@export var spring_rebound_damping: float = 2400.0
@export var bump_stop_force: float = 10800.0
@export var maximum_suspension_force: float = 20000.0
@export var support_tolerance: float = 0.05
@export var terrain_texture_depth: float = 0.018

@export_category("Handling")
@export var steering_torque: float = 980.0
@export var maximum_steer_degrees: float = 23.0
@export var steering_assist_ratio: float = 0.15
@export var steering_input_rise_rate: float = 5.4
@export var steering_input_release_rate: float = 9.5
@export var steering_input_reversal_rate: float = 12.5
@export var steering_angle_response: float = 60.0
@export var rear_countersteer_ratio: float = 0.0
@export var low_speed_turn_curvature: float = 0.125
@export var high_speed_turn_curvature: float = 0.062
@export var maximum_ground_yaw_rate: float = 1.55
@export var yaw_rate_response_strength: float = 2400.0
@export var yaw_rate_torque_limit: float = 5200.0
@export var turn_bank_ratio: float = 0.54
@export var upright_strength: float = 10000.0
@export var upright_damping: float = 1200.0
@export var ground_pitch_damping: float = 28.0
@export var low_speed_pitch_strength: float = 18000.0
@export var low_speed_pitch_damping: float = 1400.0
@export var low_speed_heading_strength: float = 2600.0
@export var low_speed_heading_damping: float = 420.0
@export var chassis_lateral_stiffness: float = 2400.0
@export var chassis_lateral_force_limit: float = 12000.0
@export var sideslip_alignment_strength: float = 1800.0
@export var ground_yaw_damping: float = 350.0
@export var maximum_lean_degrees: float = 40.0
@export var rider_weight_shift_torque: float = 1000.0
@export var longitudinal_center_of_mass_travel: float = 0.75
@export var tire_load_grip_scale: float = 1.65
@export var front_longitudinal_grip_scale: float = 0.95
@export var rear_longitudinal_grip_scale: float = 1.62
@export var front_lateral_grip_scale: float = 1.0
@export var rear_lateral_grip_scale: float = 1.05
@export var front_brake_bias: float = 0.333333
@export var air_pitch_stiffness: float = 2122.0
@export var air_pitch_damping: float = 2400.0
@export var air_roll_stiffness: float = 2653.0
@export var air_roll_damping: float = 1200.0
@export var air_yaw_torque: float = 1000.0
@export var air_yaw_damping: float = 2400.0
@export var air_emergency_pitch_torque: float = 2500.0
@export var air_brake_pop_velocity: float = 1.25
@export var air_weight_shift_response: float = 1.05
@export var landing_alignment_probe_distance: float = 5.0
@export var landing_alignment_strength: float = 1850.0
@export var landing_alignment_damping: float = 360.0
@export var landing_alignment_minimum_descent_speed: float = 1.2
@export var tipped_recovery_delay: float = 1.15
@export var preload_impulse: float = 230.0

@export_category("Barrier Visual Envelope")
@export var barrier_envelope_enabled: bool = true
@export var barrier_envelope_lookahead: float = 0.055
@export var barrier_envelope_response: float = 0.94
@export var barrier_envelope_minimum_speed: float = 0.35

@export_category("Flow Boost")
@export var flow_capacity: float = 100.0
@export var flow_boost_cost: float = 35.0
@export var flow_boost_duration: float = 1.15
@export var flow_boost_force: float = 2700.0
@export var flow_boost_impulse: float = 4.2

@export_category("Racecraft")
@export var draft_assist_force: float = 165.0
@export var clutch_pop_forward_velocity: float = 0.34
@export var clutch_pop_lift_velocity: float = 0.42
@export var pump_maximum_velocity_gain: float = 0.95
@export var scrub_downforce_ratio: float = 0.34
@export var racecraft_technique_cooldown: float = 0.85

@onready var _front_ray: RayCast3D = %FrontSuspension
@onready var _rear_ray: RayCast3D = %RearSuspension
@onready var _front_barrier_cast: ShapeCast3D = %BarrierFrontEnvelope
@onready var _rear_barrier_cast: ShapeCast3D = %BarrierRearEnvelope
@onready var _handlebar_barrier_cast: ShapeCast3D = %BarrierHandlebarEnvelope
@onready var _visual: Node3D = %BikeVisual
@onready var _engine_audio: AudioStreamPlayer3D = %EngineAudio

var controls_enabled: bool = false
var _motion_locked: bool = false
var _gate_staging_input_enabled: bool = false
var _gate_launch_drive_multiplier: float = 1.0
var _gate_launch_time: float = 0.0

var _front_distance: float = 0.907
var _rear_distance: float = 0.907
var _grounded: bool = false
var _was_grounded: bool = false
var _airborne_fall_speed: float = 0.0
var _wheel_spin: float = 0.0
var _preload_charge: float = 0.0
var _telemetry_time: float = 0.0
var _safe_sample_time: float = 0.0
var _last_safe_transform: Transform3D
var _respawn_generation: int = 0
var _airtime: float = 0.0
var _air_rotation: float = 0.0
var _base_engine_force: float = 1200.0
var _base_lateral_grip: float = 620.0
var _base_maximum_speed_mps: float = 30.0
var _flow: float = 0.0
var _boost_time: float = 0.0
var _active_flow_mode: StringName = &"NONE"
var _recommended_flow_mode: StringName = &"SURGE"
var _flow_mode_time: float = 0.0
var _compose_landing_charge: float = 0.0
var _wheelie_time: float = 0.0
var _wheelie_awarded: bool = false
var _scrub_time: float = 0.0
var _scrub_strength: float = 0.0
var _takeoff_speed_mps: float = 0.0
var _takeoff_alignment: float = 1.0
var _whip_time: float = 0.0
var _wobble_time: float = 0.0
var _run_engine_multiplier: float = 1.0
var _run_grip_multiplier: float = 1.0
var _session_grip_multiplier: float = 1.0
var _flow_gain_multiplier: float = 1.0
var _preload_buffer_time: float = 0.0
var _ground_coyote_time: float = 0.0
var _assist_strength: float = 0.45
var _front_contact := WheelContact.new()
var _rear_contact := WheelContact.new()
var _legacy_surface: StringName = &"PACKED"
var _surface_override: StringName = &""
var _active_surface: StringName = &"PACKED"
var _terrain_roughness: float = 0.35
var _terrain_roost: float = 0.8
var _suspension_activity: float = 0.0
var _feedback_time: float = 0.0
var _gravity_magnitude: float = 19.6
var _steer_angle: float = 0.0
var _steer_input: float = 0.0
var _target_ground_yaw_rate: float = 0.0
var _target_bank_angle: float = 0.0
var _priority_haptic_time: float = 0.0
var _haptics_enabled: bool = true
var _haptics_intensity: float = 0.8
var _base_center_of_mass: Vector3 = Vector3(0.0, -0.22, 0.1)
var _low_speed_forward: Vector3 = Vector3.FORWARD
var _weight_shift: float = 0.0
var _air_brake_pop_used: bool = false
var _landing_target_valid: bool = false
var _landing_target_normal: Vector3 = Vector3.UP
var _landing_target_distance: float = INF
var _landing_alignment_weight: float = 0.0
var _tipped_recovery_time: float = 0.0
var _brake_was_pressed: bool = false
var _pack_contact_cooldown: float = 0.0
var _technique_cooldown: float = 0.0
var _active_technique: StringName = &"NONE"
var _technique_display_time: float = 0.0
var _slide_active: bool = false
var _slide_time: float = 0.0
var _slide_awarded: bool = false
var _slide_factors: Dictionary = {}
var _rut_time: float = 0.0
var _rut_awarded: bool = false
var _rut_snapshot: Dictionary = {}
var _skill_zone_id: StringName = &""
var _skill_zone_time: float = 0.0
var _skill_zone_resolved: bool = false
var _skill_line_outcome: StringName = &"NONE"
var _course_racecraft_context: Dictionary = {}
var _pack_racecraft_context: Dictionary = {
	&"draft_strength": 0.0,
	&"roost_pressure": 0.0,
	&"contact_pressure": 0.0,
}
var _recent_draft_strength: float = 0.0
var _recent_draft_target: StringName = &""
var _recent_draft_time: float = 0.0
var _racecraft_counters: Dictionary = {}
var _racecraft_state_time: float = 0.0
var _last_throttle: float = 0.0
var _last_brake: float = 0.0
var _last_lean: float = 0.0
var _barrier_envelope_probes: Array[ShapeCast3D] = []
var _barrier_envelope_contact_count: int = 0


func _ready() -> void:
	_last_safe_transform = global_transform
	can_sleep = false
	_base_engine_force = engine_force
	_base_lateral_grip = lateral_grip
	_base_maximum_speed_mps = maximum_speed_mps
	_base_center_of_mass = center_of_mass
	_low_speed_forward = -global_transform.basis.z.slide(Vector3.UP).normalized()
	_gravity_magnitude = float(ProjectSettings.get_setting(&"physics/3d/default_gravity", 19.6)) * gravity_scale
	_barrier_envelope_probes.assign([
		_front_barrier_cast,
		_rear_barrier_cast,
		_handlebar_barrier_cast,
	])


func _physics_process(delta: float) -> void:
	_was_grounded = _grounded
	var accepts_gate_input := _motion_locked and _gate_staging_input_enabled
	var throttle := InputRouter.get_throttle() if controls_enabled or accepts_gate_input else 0.0
	var brake := InputRouter.get_brake() if controls_enabled or accepts_gate_input else 0.0
	var brake_just_pressed := brake > 0.18 and not _brake_was_pressed
	_brake_was_pressed = brake > 0.18
	var raw_steer := InputRouter.get_steer() if controls_enabled else 0.0
	var lean := InputRouter.get_lean() if controls_enabled else 0.0
	_last_throttle = throttle
	_last_brake = brake
	_last_lean = lean
	# Brake staging is presentation/evaluation only; it must not preload a hidden
	# center-of-mass shift before the rigid body is released.
	_update_center_of_mass(lean, brake if controls_enabled else 0.0, delta)
	_update_steering_input(raw_steer, delta)
	_priority_haptic_time = maxf(_priority_haptic_time - delta, 0.0)
	_pack_contact_cooldown = maxf(_pack_contact_cooldown - delta, 0.0)
	_technique_cooldown = maxf(_technique_cooldown - delta, 0.0)
	_recent_draft_time = maxf(_recent_draft_time - delta, 0.0)
	if _recent_draft_time <= 0.0:
		_recent_draft_strength = 0.0
		_recent_draft_target = &""
	_technique_display_time = maxf(_technique_display_time - delta, 0.0)
	if _technique_display_time <= 0.0:
		_active_technique = &"NONE"
	_compose_landing_charge = maxf(_compose_landing_charge - delta * 0.32, 0.0)
	_sample_wheel_contact(_front_ray, _front_contact, delta, not _motion_locked)
	_sample_wheel_contact(_rear_ray, _rear_contact, delta, not _motion_locked)
	_front_distance = _front_contact.distance
	_rear_distance = _rear_contact.distance
	_grounded = _front_contact.colliding or _rear_contact.colliding
	_ground_coyote_time = 0.12 if _grounded else maxf(_ground_coyote_time - delta, 0.0)
	_update_active_surface()
	_handle_flow_boost(delta, brake, raw_steer)
	_handle_racecraft_technique(throttle, brake, raw_steer)

	if _motion_locked:
		_airborne_fall_speed = 0.0
		_update_terrain_feedback(delta)
		# Staging input may rev the engine and animate the rider, but the frozen
		# rigid body remains the sole authority over pre-green motion.
		_update_visual_and_audio(delta, 0.0, _steer_input, lean, throttle)
		_update_telemetry(delta, 0.0, throttle)
		_emit_racecraft_state(delta)
		return
	_handle_barrier_visual_envelope(delta)

	if _grounded:
		_landing_target_valid = false
		_landing_alignment_weight = 0.0
		_apply_ground_drive(throttle, brake, _steer_input, lean, delta)
		_apply_balance(_steer_input)
		_update_wheelie(delta, get_speed_mps())
		_safe_sample_time += delta
		if _safe_sample_time >= 0.65 and global_transform.basis.y.dot(Vector3.UP) > 0.45:
			_update_safe_transform()
			_safe_sample_time = 0.0
	else:
		if _was_grounded:
			_airtime = 0.0
			_air_rotation = 0.0
			_air_brake_pop_used = false
			_takeoff_speed_mps = get_speed_mps()
			_takeoff_alignment = clampf((-global_transform.basis.z).normalized().dot(linear_velocity.normalized()), 0.0, 1.0) if linear_velocity.length_squared() > 0.1 else 1.0
			airtime_started.emit()
		_airtime += delta
		_air_rotation += angular_velocity.length() * delta
		_sample_landing_target()
		_apply_air_control(raw_steer)
		_apply_air_brake_pop(brake_just_pressed)
		_update_scrub(lean, delta)
		_whip_time += delta if absf(raw_steer) > 0.55 else 0.0
		_airborne_fall_speed = maxf(_airborne_fall_speed, -linear_velocity.y)

	if _grounded and not _was_grounded:
		_air_brake_pop_used = false
		var intensity := clampf((_airborne_fall_speed - 2.0) / 10.0, 0.0, 1.0)
		if intensity > 0.05:
			landed.emit(intensity)
			_visual.call(
				&"burst_landing_dust",
				intensity,
				_get_contact_midpoint(),
				_get_ground_normal(),
				_active_surface
			)
			_play_haptic(intensity * 0.28, intensity * 0.62, 0.12 + intensity * 0.12)
			_priority_haptic_time = 0.24
		if _airtime >= 0.12:
			var clean_landing := global_transform.basis.y.normalized().dot(_get_ground_normal()) > 0.48 and intensity < 0.9
			_apply_landing_momentum(intensity)
			trick_landed.emit(_airtime, _air_rotation, intensity, clean_landing)
			_award_landing_flow(_airtime, _air_rotation, clean_landing)
			if clean_landing and _scrub_time >= 0.24:
				style_event.emit(&"SCRUB", 240)
				_emit_racecraft_event(&"SCRUB", {
					&"seconds": _scrub_time,
					&"strength": _scrub_strength,
					&"takeoff_speed_mps": _takeoff_speed_mps,
				})
			if clean_landing and _whip_time >= 0.24:
				style_event.emit(&"WHIP", 280)
			if intensity >= 0.55 and intensity < 0.9:
				_wobble_time = maxf(_wobble_time, 1.1)
		_airtime = 0.0
		_air_rotation = 0.0
		_airborne_fall_speed = 0.0
		_scrub_time = 0.0
		_scrub_strength = 0.0
		_whip_time = 0.0

	_handle_preload(delta)
	var was_wobbling := _wobble_time > 0.0
	_wobble_time = maxf(_wobble_time - delta, 0.0)
	if was_wobbling and _wobble_time <= 0.0 and controls_enabled:
		style_event.emit(&"SAVE", 260)

	_update_terrain_feedback(delta)
	var speed_mps := get_speed_mps()
	_update_visual_and_audio(delta, speed_mps, _steer_input if _grounded else raw_steer, lean, throttle)
	_update_telemetry(delta, speed_mps, throttle)
	_update_skill_line(delta)
	_emit_racecraft_state(delta)
	_update_tipped_recovery(delta)
	_update_gate_launch_drive(delta)

	if global_position.y < -6.0:
		reset_to_safe_position(RECOVERY_WORLD_FALL)


func set_controls_enabled(enabled: bool) -> void:
	controls_enabled = enabled
	if not enabled and (is_boosting() or _active_flow_mode != &"NONE"):
		_boost_time = 0.0
		_active_flow_mode = &"NONE"
		_flow_mode_time = 0.0
		flow_changed.emit(_flow, false)


func set_gate_staging_input_enabled(enabled: bool) -> void:
	## Allows throttle/brake sampling and engine rev feedback on the frozen grid.
	## Steering, boost, preload, and every force-producing path remain disabled.
	_gate_staging_input_enabled = enabled and _motion_locked


func get_gate_staging_input_snapshot() -> Dictionary:
	var accepts_input := _motion_locked and _gate_staging_input_enabled
	return {
		&"enabled": accepts_input,
		&"throttle": InputRouter.get_throttle() if accepts_input else 0.0,
		&"brake": InputRouter.get_brake() if accepts_input else 0.0,
	}


func apply_gate_launch_drive(multiplier: float, duration: float = GATE_LAUNCH_DEFAULT_DURATION) -> void:
	_gate_launch_drive_multiplier = clampf(
		multiplier,
		GATE_LAUNCH_MIN_MULTIPLIER,
		GATE_LAUNCH_MAX_MULTIPLIER
	)
	_gate_launch_time = maxf(duration, 0.0)
	if _gate_launch_time <= 0.0:
		_gate_launch_drive_multiplier = 1.0
		return
	var launch_quality := inverse_lerp(
		GATE_LAUNCH_MIN_MULTIPLIER,
		GATE_LAUNCH_MAX_MULTIPLIER,
		_gate_launch_drive_multiplier
	)
	_play_haptic(0.10 + launch_quality * 0.12, 0.16 + launch_quality * 0.24, 0.12)
	_priority_haptic_time = maxf(_priority_haptic_time, 0.14)


func get_gate_launch_drive_snapshot() -> Dictionary:
	return {
		&"active": _gate_launch_time > 0.0,
		&"multiplier": _gate_launch_drive_multiplier,
		&"seconds_remaining": _gate_launch_time,
		&"minimum_multiplier": GATE_LAUNCH_MIN_MULTIPLIER,
		&"maximum_multiplier": GATE_LAUNCH_MAX_MULTIPLIER,
	}


func set_motion_locked(locked: bool) -> void:
	_motion_locked = locked
	freeze = locked
	if locked:
		_gate_launch_drive_multiplier = 1.0
		_gate_launch_time = 0.0
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
	else:
		_gate_staging_input_enabled = false
		sleeping = false


func reset_to_safe_position(reason: StringName = &"AUTO_RECOVERY") -> void:
	# Signal delivery is synchronous. If an active race handles the request it
	# calls respawn_at(), advancing the generation and preventing a second local
	# respawn. Freeride has no active handler and uses the forgiving local sample.
	var generation_before_request := _respawn_generation
	automatic_recovery_requested.emit(reason)
	if _respawn_generation == generation_before_request:
		respawn_at(_last_safe_transform)


func respawn_at(spawn_transform: Transform3D) -> void:
	_respawn_generation += 1
	freeze = true
	global_transform = spawn_transform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze = _motion_locked
	sleeping = _motion_locked
	_last_safe_transform = spawn_transform
	_airborne_fall_speed = 0.0
	_airtime = 0.0
	_air_rotation = 0.0
	_reset_flow()
	_wheelie_time = 0.0
	_wheelie_awarded = false
	_scrub_time = 0.0
	_scrub_strength = 0.0
	_takeoff_speed_mps = 0.0
	_takeoff_alignment = 1.0
	_whip_time = 0.0
	_wobble_time = 0.0
	_preload_buffer_time = 0.0
	_ground_coyote_time = 0.0
	_front_contact = WheelContact.new()
	_rear_contact = WheelContact.new()
	_low_speed_forward = -spawn_transform.basis.z.slide(Vector3.UP).normalized()
	_front_distance = suspension_rest_length + wheel_radius
	_rear_distance = suspension_rest_length + wheel_radius
	_active_surface = _legacy_surface
	_terrain_roughness = _surface_roughness(_active_surface)
	_terrain_roost = _surface_roost(_active_surface)
	_suspension_activity = 0.0
	_steer_angle = 0.0
	_steer_input = 0.0
	_target_ground_yaw_rate = 0.0
	_target_bank_angle = 0.0
	_priority_haptic_time = 0.0
	_weight_shift = 0.0
	_air_brake_pop_used = false
	_landing_target_valid = false
	_landing_target_normal = Vector3.UP
	_landing_target_distance = INF
	_landing_alignment_weight = 0.0
	_tipped_recovery_time = 0.0
	_brake_was_pressed = false
	_pack_contact_cooldown = 0.0
	_technique_cooldown = 0.0
	_active_technique = &"NONE"
	_technique_display_time = 0.0
	_slide_active = false
	_slide_time = 0.0
	_slide_awarded = false
	_slide_factors.clear()
	_rut_time = 0.0
	_rut_awarded = false
	_rut_snapshot.clear()
	_skill_zone_id = &""
	_skill_zone_time = 0.0
	_skill_zone_resolved = false
	_skill_line_outcome = &"NONE"
	_active_flow_mode = &"NONE"
	_recommended_flow_mode = &"SURGE"
	_flow_mode_time = 0.0
	_compose_landing_charge = 0.0
	_course_racecraft_context.clear()
	_pack_racecraft_context = {&"draft_strength": 0.0, &"roost_pressure": 0.0, &"contact_pressure": 0.0}
	_recent_draft_strength = 0.0
	_recent_draft_target = &""
	_recent_draft_time = 0.0
	_racecraft_counters.clear()
	_racecraft_state_time = 0.0
	_barrier_envelope_contact_count = 0
	center_of_mass = _base_center_of_mass
	_visual.call(&"reset_terrain_feedback")
	_engine_audio.call(&"reset_surface_feedback")
	respawned.emit()


func get_speed_mps() -> float:
	return Vector3(linear_velocity.x, 0.0, linear_velocity.z).length()


func get_barrier_envelope_contact_count() -> int:
	return _barrier_envelope_contact_count


func _handle_barrier_visual_envelope(delta: float) -> void:
	if not barrier_envelope_enabled or _barrier_envelope_probes.is_empty():
		return
	var planar_velocity := linear_velocity.slide(Vector3.UP)
	var planar_speed := planar_velocity.length()
	if planar_speed < barrier_envelope_minimum_speed:
		return

	# Follow the animated axle height, while keeping the probe shapes separate
	# from the body's capsule. The latter remains deliberately short so it cannot
	# snag the open ends or underside-free triangles of rideable jumps.
	_front_barrier_cast.position.y = _wheel_center_y(_front_ray, _front_distance)
	_rear_barrier_cast.position.y = _wheel_center_y(_rear_ray, _rear_distance)
	var safe_lookahead := maxf(barrier_envelope_lookahead, delta)
	var local_motion := global_transform.basis.inverse() * (planar_velocity * safe_lookahead)
	var best_delta_v: float = 0.0
	var best_normal := Vector3.ZERO

	for probe: ShapeCast3D in _barrier_envelope_probes:
		probe.target_position = local_motion
		probe.force_shapecast_update()
		for collision_index: int in probe.get_collision_count():
			var collider: Object = probe.get_collider(collision_index)
			if not _is_course_barrier(collider):
				continue
			var contact_point := probe.get_collision_point(collision_index)
			var contact_normal := probe.get_collision_normal(collision_index).normalized()
			if contact_normal.length_squared() < 0.25:
				continue
			# ShapeCast normals normally face the casting shape, but normalize their
			# orientation explicitly for barrier corners and opening posts.
			if contact_normal.dot(probe.global_position - contact_point) < 0.0:
				contact_normal = -contact_normal
			contact_normal = contact_normal.slide(Vector3.UP)
			if contact_normal.length_squared() < 0.16:
				continue
			contact_normal = contact_normal.normalized()
			var inward_speed := -planar_velocity.dot(contact_normal)
			if inward_speed <= 0.0:
				continue

			var support := _barrier_probe_support(probe, contact_normal)
			var clearance := maxf(
				(probe.global_position - contact_point).dot(contact_normal) - support,
				0.0
			)
			var time_to_contact := clearance / inward_speed
			if time_to_contact > safe_lookahead + delta:
				continue
			var proximity := 1.0 - clampf(time_to_contact / safe_lookahead, 0.0, 1.0)
			var response_ratio := clampf(
				proximity + delta / safe_lookahead,
				0.0,
				1.0
			) * barrier_envelope_response
			var requested_delta_v := inward_speed * response_ratio
			if requested_delta_v > best_delta_v:
				best_delta_v = requested_delta_v
				best_normal = contact_normal

	if best_delta_v <= 0.0 or best_normal.length_squared() < 0.25:
		return
	# Only remove velocity into the wall. Forward speed remains intact during a
	# side scrape, so containment feels like a firm berm rather than sticky glue.
	apply_central_impulse(best_normal * mass * best_delta_v)
	_barrier_envelope_contact_count += 1


func _is_course_barrier(collider: Object) -> bool:
	if collider == null or not collider is Node:
		return false
	var node := collider as Node
	return (
		bool(node.get_meta(&"course_containment", false))
		or bool(node.get_meta(&"visible_barrier_ends", false))
		or node.is_in_group(&"course_containment")
	)


func _barrier_probe_support(probe: ShapeCast3D, normal: Vector3) -> float:
	var probe_shape := probe.shape
	if probe_shape is SphereShape3D:
		return (probe_shape as SphereShape3D).radius
	if probe_shape is CapsuleShape3D:
		var capsule := probe_shape as CapsuleShape3D
		var axis := probe.global_transform.basis.y.normalized()
		var segment_half_length := maxf(capsule.height * 0.5 - capsule.radius, 0.0)
		return capsule.radius + segment_half_length * absf(axis.dot(normal))
	return 0.0


func apply_pack_contact(direction: Vector3, closing_speed: float, _contact_offset: Vector3 = Vector3.ZERO) -> bool:
	if _pack_contact_cooldown > 0.0 or not controls_enabled:
		return false
	var planar_direction := direction.slide(Vector3.UP)
	if planar_direction.length_squared() < 0.01:
		planar_direction = global_transform.basis.x
	planar_direction = planar_direction.normalized()
	var intensity := clampf((closing_speed - 0.5) / 8.5, 0.32, 1.0)
	var brace_scale := 0.48 if _active_flow_mode == RACECRAFT_RULES.FLOW_BRACE else 1.0
	var contact_delta_v := lerpf(0.42, 1.08, intensity) * brace_scale
	var grounded_scale := 1.0 if _grounded else 0.55
	apply_central_impulse(
		planar_direction * mass * contact_delta_v * grounded_scale
		+ Vector3.UP * mass * lerpf(0.015, 0.065, intensity) * grounded_scale
	)
	var side_sign := signf(planar_direction.dot(global_transform.basis.x))
	if is_zero_approx(side_sign):
		side_sign = 1.0
	var forward_axis := -global_transform.basis.z.normalized()
	apply_torque_impulse(forward_axis * side_sign * mass * lerpf(0.035, 0.075, intensity) * brace_scale)
	_pack_contact_cooldown = 0.2
	_priority_haptic_time = 0.28
	_play_haptic(0.32 * intensity, 0.68 * intensity, 0.16)
	pack_contacted.emit(intensity)
	if brace_scale < 1.0:
		_wobble_time *= 0.35
		_emit_racecraft_event(&"BRACE_SAVE", {&"intensity": intensity, &"mitigation": 1.0 - brace_scale})
		style_event.emit(&"BRACE SAVE", int(round(190.0 + intensity * 130.0)))
	else:
		style_event.emit(&"BAR BANG", int(round(150.0 + intensity * 110.0)))
	return true


func is_grounded() -> bool:
	return _grounded


func get_ground_normal() -> Vector3:
	return _get_ground_normal()


func get_active_surface() -> StringName:
	return _active_surface


func get_terrain_roughness() -> float:
	return _terrain_roughness


func get_terrain_roost() -> float:
	return _terrain_roost


func get_rear_slip() -> float:
	return _rear_contact.slip if _rear_contact.colliding else 0.0


func get_front_slip() -> float:
	return _front_contact.slip if _front_contact.colliding else 0.0


func get_body_sideslip_angle() -> float:
	var planar_velocity := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	if planar_velocity.length_squared() < 0.01:
		return 0.0
	var body_right := global_transform.basis.x.slide(Vector3.UP).normalized()
	var body_forward := -global_transform.basis.z.slide(Vector3.UP).normalized()
	return atan2(
		planar_velocity.dot(body_right),
		maxf(absf(planar_velocity.dot(body_forward)), 0.01)
	)


func get_steering_input() -> float:
	return _steer_input


func get_target_ground_yaw_rate() -> float:
	return _target_ground_yaw_rate


func get_target_bank_angle() -> float:
	return _target_bank_angle


func get_current_bank_angle() -> float:
	var ground_up := _get_ground_normal() if _grounded else Vector3.UP
	var forward := -global_transform.basis.z.slide(ground_up)
	if forward.length_squared() < 0.1:
		return 0.0
	forward = forward.normalized()
	var current_up := global_transform.basis.y.normalized()
	return atan2(ground_up.cross(current_up).dot(forward), ground_up.dot(current_up))


func get_suspension_activity() -> float:
	return _suspension_activity


func get_landing_alignment_weight() -> float:
	return _landing_alignment_weight


func get_landing_target_normal() -> Vector3:
	return _landing_target_normal if _landing_target_valid else Vector3.UP


func get_contact_feedback() -> Dictionary:
	return {
		&"surface": _active_surface,
		&"roughness": _terrain_roughness,
		&"roost": _terrain_roost,
		&"front_slip": get_front_slip(),
		&"rear_slip": get_rear_slip(),
		&"front_grip_usage": _front_contact.grip_usage,
		&"rear_grip_usage": _rear_contact.grip_usage,
		&"front_lateral_speed": _front_contact.lateral_speed,
		&"rear_lateral_speed": _rear_contact.lateral_speed,
		&"body_sideslip_angle": get_body_sideslip_angle(),
		&"front_compression": _front_contact.compression,
		&"rear_compression": _rear_contact.compression,
		&"suspension_activity": _suspension_activity,
		&"ground_normal": _get_ground_normal(),
	}


func set_course_racecraft_context(context: Dictionary) -> void:
	_course_racecraft_context = context.duplicate(true)


func set_pack_racecraft_context(context: Dictionary) -> void:
	_pack_racecraft_context = context.duplicate(true)
	_pack_racecraft_context[&"draft_strength"] = clampf(float(context.get(&"draft_strength", 0.0)), 0.0, 1.0)
	_pack_racecraft_context[&"roost_pressure"] = clampf(float(context.get(&"roost_pressure", 0.0)), 0.0, 1.0)
	_pack_racecraft_context[&"contact_pressure"] = clampf(float(context.get(&"contact_pressure", 0.0)), 0.0, 1.0)
	var current_draft := float(_pack_racecraft_context[&"draft_strength"])
	if current_draft >= 0.08:
		_recent_draft_strength = maxf(_recent_draft_strength, current_draft)
		_recent_draft_target = StringName(context.get(&"draft_target", &""))
		_recent_draft_time = 1.15


func get_racecraft_snapshot() -> Dictionary:
	var recommended_cost := RACECRAFT_RULES.flow_cost(_recommended_flow_mode)
	return {
		&"version": CompetitiveRunSignature.RACECRAFT_VERSION,
		&"active_flow_mode": _active_flow_mode,
		&"recommended_flow_mode": _recommended_flow_mode,
		&"recommended_flow_cost": recommended_cost,
		&"recommended_flow_affordable": _flow + 0.0001 >= recommended_cost,
		&"flow": _flow,
		&"technique": _active_technique,
		&"technique_cooldown": _technique_cooldown,
		&"slide_active": _slide_active,
		&"slide_seconds": _slide_time,
		&"scrub_strength": _scrub_strength,
		&"scrub_seconds": _scrub_time,
		&"rut": _rut_snapshot.duplicate(true),
		&"berm_strength": clampf(float(_course_racecraft_context.get(&"berm_strength", 0.0)), 0.0, 1.0),
		&"skill_zone": _skill_zone_id,
		&"skill_line_outcome": _skill_line_outcome,
		&"draft_strength": clampf(float(_pack_racecraft_context.get(&"draft_strength", 0.0)), 0.0, 1.0),
		&"recent_draft_strength": _recent_draft_strength,
		&"recent_draft_target": _recent_draft_target,
		&"recent_draft_seconds": _recent_draft_time,
		&"roost_pressure": clampf(float(_pack_racecraft_context.get(&"roost_pressure", 0.0)), 0.0, 1.0),
		&"contact_pressure": clampf(float(_pack_racecraft_context.get(&"contact_pressure", 0.0)), 0.0, 1.0),
		&"rear_slip": get_rear_slip(),
		&"throttle": _last_throttle,
		&"counters": _racecraft_counters.duplicate(true),
	}


func register_racecraft_success(kind: StringName, payload: Dictionary = {}) -> void:
	match kind:
		&"DRAFT_SLINGSHOT":
			_add_flow(6.0)
			style_event.emit(&"DRAFT SLINGSHOT", 260)
			_recent_draft_strength = 0.0
			_recent_draft_target = &""
			_recent_draft_time = 0.0
		&"ROOST_DEFENSE":
			_add_flow(3.0)
			style_event.emit(&"ROOST DEFENSE", 180)
	_emit_racecraft_event(kind, payload)


func get_flow() -> float:
	return _flow


func is_boosting() -> bool:
	return _boost_time > 0.0


func shutdown_audio() -> void:
	_engine_audio.call(&"shutdown")
	_engine_audio.queue_free()


func apply_setup(setup: StringName) -> void:
	match setup:
		&"TRAIL":
			engine_force = 1100.0
			reverse_force = 1120.0
			lateral_grip = 700.0
			spring_stiffness = 20000.0
			maximum_speed_mps = 27.5
			maximum_lean_degrees = 36.0
		&"ATTACK":
			engine_force = 1400.0
			reverse_force = 980.0
			lateral_grip = 560.0
			spring_stiffness = 20000.0
			maximum_speed_mps = 33.0
			maximum_lean_degrees = 44.0
		_:
			engine_force = 1200.0
			reverse_force = 1050.0
			lateral_grip = 620.0
			spring_stiffness = 20000.0
			maximum_speed_mps = 30.0
			maximum_lean_degrees = 40.0
	_base_engine_force = engine_force
	_base_lateral_grip = lateral_grip
	_base_maximum_speed_mps = maximum_speed_mps


func apply_condition(condition: int) -> void:
	var condition_ratio := clampf(float(condition) / 100.0, 0.0, 1.0)
	# Wear still matters, but it must not make a saved player bike dramatically
	# slower than the non-physical race pack.
	engine_force = _base_engine_force * lerpf(0.94, 1.0, condition_ratio)
	lateral_grip = _base_lateral_grip * lerpf(0.96, 1.0, condition_ratio)
	maximum_speed_mps = _base_maximum_speed_mps * lerpf(0.97, 1.0, condition_ratio)


func apply_racing_build(build_snapshot: Dictionary) -> void:
	## Applies catalog/tune output on top of the selected legacy kit. All factors
	## are recomputed from the kit baselines, so garage previews and restarts are idempotent.
	var stats := build_snapshot.get(&"stats", {}) as Dictionary
	if stats.is_empty():
		return
	var factors: Dictionary = BIKE_BUILD_SCRIPT.runtime_factors(stats)
	var drive_factor := float(factors.get(&"drive", 1.0))
	var speed_factor := float(factors.get(&"speed", 1.0))
	var grip_factor := float(factors.get(&"grip", 1.0))
	var brake_factor := float(factors.get(&"brake", 1.0))
	var suspension_factor := float(factors.get(&"suspension", 1.0))
	var stability_factor := float(factors.get(&"stability", 1.0))
	var air_factor := float(factors.get(&"air", 1.0))
	var build_data := build_snapshot.get(&"build", {}) as Dictionary
	var tune_data := build_data.get(&"tune", {}) as Dictionary
	var physical_tune: Dictionary = BIKE_BUILD_SCRIPT.runtime_tune_projection(tune_data)
	engine_force = _base_engine_force * drive_factor
	lateral_grip = _base_lateral_grip * grip_factor
	maximum_speed_mps = _base_maximum_speed_mps * speed_factor
	brake_force = 2880.0 * brake_factor
	spring_stiffness = 20000.0 * suspension_factor * float(physical_tune.get(&"stiffness_factor", 1.0))
	spring_compression_damping = float(physical_tune.get(&"spring_compression_damping", 380.0))
	spring_rebound_damping = float(physical_tune.get(&"spring_rebound_damping", 2400.0))
	front_brake_bias = float(physical_tune.get(&"front_brake_bias", 0.333333))
	upright_strength = 10000.0 * stability_factor
	air_pitch_stiffness = 2122.0 * air_factor
	air_roll_stiffness = 2653.0 * air_factor
	preload_impulse = 230.0 * float(physical_tune.get(&"preload_factor", 1.0)) * lerpf(0.92, 1.13, clampf((air_factor - 0.78) / 0.42, 0.0, 1.0))
	_base_engine_force = engine_force
	_base_lateral_grip = lateral_grip
	_base_maximum_speed_mps = maximum_speed_mps


func get_build_tuning_snapshot() -> Dictionary:
	return {
		&"spring_stiffness": spring_stiffness,
		&"spring_compression_damping": spring_compression_damping,
		&"spring_rebound_damping": spring_rebound_damping,
		&"front_brake_bias": front_brake_bias,
		&"preload_impulse": preload_impulse,
		&"brake_force": brake_force,
	}


func apply_equalized_race_class(class_id: StringName) -> void:
	## Stock competitive classes keep rotating/hot-seat boards comparable even
	## when the local career bike has upgraded parts. Career events still use the
	## complete owned build through apply_racing_build().
	var drive_factor := 1.0
	var speed_factor := 1.0
	var grip_factor := 1.0
	match class_id:
		&"LITE_125":
			drive_factor = 0.94
			speed_factor = 0.94
			grip_factor = 1.06
		&"OPEN":
			drive_factor = 1.1
			speed_factor = 1.08
			grip_factor = 0.97
	engine_force = _base_engine_force * drive_factor
	maximum_speed_mps = _base_maximum_speed_mps * speed_factor
	lateral_grip = _base_lateral_grip * grip_factor
	_base_engine_force = engine_force
	_base_maximum_speed_mps = maximum_speed_mps
	_base_lateral_grip = lateral_grip


func apply_session_surface(surface: StringName) -> void:
	match surface:
		&"WET", &"MUD":
			_session_grip_multiplier = 0.82
		&"LOOSE", &"LOOSE_DIRT", &"RUTTED":
			_session_grip_multiplier = 0.92
		_:
			_session_grip_multiplier = 1.0


func apply_run_modifier(modifier: StringName) -> void:
	_run_engine_multiplier = 1.0
	_run_grip_multiplier = 1.0
	_flow_gain_multiplier = 1.0
	match modifier:
		&"TAILWIND":
			_run_engine_multiplier = 1.12
		&"LOOSE_DIRT":
			_run_grip_multiplier = 0.94
		&"FLOW_SURGE":
			_flow_gain_multiplier = 1.28


func apply_cosmetic_tier(tier: int) -> void:
	_visual.call(&"apply_cosmetic_tier", tier)


func apply_rider_cosmetics(cosmetics: Dictionary) -> void:
	if _visual != null and _visual.has_method(&"apply_rider_cosmetics"):
		_visual.call(&"apply_rider_cosmetics", cosmetics)


func apply_assist_mode(mode: StringName) -> void:
	match mode:
		&"ASSISTED":
			_assist_strength = 0.78
		&"PRO":
			_assist_strength = 0.12
		_:
			_assist_strength = 0.45


func set_surface(surface: StringName) -> void:
	var canonical := _canonical_surface(surface)
	_surface_override = &"" if canonical == &"PACKED" else canonical
	_legacy_surface = canonical
	if not _front_contact.colliding and not _rear_contact.colliding:
		_set_active_surface(_legacy_surface, _surface_roughness(_legacy_surface))


func _update_steering_input(raw_steer: float, delta: float) -> void:
	var target := clampf(raw_steer, -1.0, 1.0)
	# Keyboard actions arrive as an immediate +/-1 step. Give that step a crisp,
	# finite rack response while preserving the exact magnitude of analogue input.
	# Reversals receive their own faster rate so alternating taps do not spend half
	# a corner unwinding the previous command.
	var reversing := (
		absf(target) > 0.04
		and absf(_steer_input) > 0.04
		and signf(target) != signf(_steer_input)
	)
	var rate := steering_input_release_rate
	if reversing:
		rate = steering_input_reversal_rate
	elif absf(target) > absf(_steer_input):
		rate = steering_input_rise_rate
	_steer_input = move_toward(_steer_input, target, rate * delta)
	if absf(target) < 0.001 and absf(_steer_input) < 0.001:
		_steer_input = 0.0


func _sample_wheel_contact(
	ray: RayCast3D,
	contact: WheelContact,
	delta: float,
	apply_suspension_force: bool
) -> void:
	ray.force_raycast_update()
	var previous_compression := contact.compression
	contact.raw_distance = ray.target_position.length()
	contact.distance = contact.raw_distance
	contact.load = 0.0
	contact.longitudinal_speed = 0.0
	contact.lateral_speed = 0.0
	contact.slip = 0.0
	contact.grip_usage = 0.0
	if not ray.is_colliding():
		contact.colliding = false
		contact.collider_id = 0
		contact.compression = 0.0
		contact.compression_velocity = (contact.compression - previous_compression) / maxf(delta, 0.0001)
		contact.surface = _legacy_surface
		contact.roughness = _surface_roughness(_legacy_surface)
		contact.roost = _surface_roost(_legacy_surface)
		contact.friction = _surface_friction(_legacy_surface)
		contact.drag = _surface_drag(_legacy_surface)
		return

	var collider: Object = ray.get_collider()
	var next_collider_id := collider.get_instance_id() if collider != null else 0
	var was_same_contact := contact.colliding and contact.collider_id == next_collider_id
	contact.point = ray.get_collision_point()
	contact.raw_distance = ray.global_position.distance_to(contact.point)
	var maximum_supported_distance := suspension_rest_length + wheel_radius + support_tolerance
	if contact.raw_distance > maximum_supported_distance:
		contact.colliding = false
		contact.collider_id = next_collider_id
		contact.compression = 0.0
		contact.compression_velocity = (contact.compression - previous_compression) / maxf(delta, 0.0001)
		contact.surface = _legacy_surface
		contact.roughness = _surface_roughness(_legacy_surface)
		contact.roost = _surface_roost(_legacy_surface)
		contact.friction = _surface_friction(_legacy_surface)
		contact.drag = _surface_drag(_legacy_surface)
		return
	contact.colliding = true
	contact.collider_id = next_collider_id
	var hit_normal := ray.get_collision_normal().normalized()
	var normal_weight := clampf(delta * 18.0, 0.0, 1.0)
	contact.normal = contact.normal.slerp(hit_normal, normal_weight).normalized() if was_same_contact else hit_normal
	contact.surface = _surface_from_ray(ray)
	if not _surface_override.is_empty():
		contact.roughness = _surface_roughness(contact.surface)
		contact.roost = _surface_roost(contact.surface)
		contact.friction = _surface_friction(contact.surface)
		contact.drag = _surface_drag(contact.surface)
	else:
		contact.roughness = _roughness_from_ray(ray, contact.surface)
		contact.roost = _metadata_float_from_ray(ray, &"roost", _surface_roost(contact.surface), 0.0, 2.5)
		contact.friction = _metadata_float_from_ray(ray, &"friction", _surface_friction(contact.surface), 0.25, 2.0)
		contact.drag = _metadata_float_from_ray(ray, &"drag", _surface_drag(contact.surface), 0.25, 3.0)

	var texture_height := _contact_texture_height(contact.point, contact.roughness)
	contact.distance = maxf(contact.raw_distance - texture_height, 0.0)
	var desired_distance := suspension_rest_length + wheel_radius
	contact.compression = clampf(desired_distance - contact.distance, 0.0, suspension_rest_length)
	contact.compression_velocity = (contact.compression - previous_compression) / maxf(delta, 0.0001)
	var force_offset := contact.point - global_position
	var point_velocity := linear_velocity + angular_velocity.cross(force_offset)
	var normal_velocity := point_velocity.dot(contact.normal)
	var damping := spring_compression_damping if normal_velocity < 0.0 else spring_rebound_damping
	var bump_ratio := clampf(inverse_lerp(suspension_rest_length * 0.76, suspension_rest_length, contact.compression), 0.0, 1.0)
	var spring_force := contact.compression * spring_stiffness + bump_ratio * bump_ratio * bump_stop_force
	contact.load = clampf(
		spring_force - normal_velocity * damping,
		0.0,
		maximum_suspension_force
	)
	if apply_suspension_force and contact.load > 0.0:
		apply_force(contact.normal * contact.load, force_offset)


func _contact_texture_height(point: Vector3, roughness: float) -> float:
	# Deterministic centimetre-scale collision texture: the suspension moves over
	# a repeatable surface profile without random forces that would desync ghosts.
	var wave := (
		sin(point.x * 0.83 + point.z * 0.41) * 0.52
		+ sin(point.x * 1.91 - point.z * 1.37) * 0.31
		+ sin(point.x * 3.47 + point.z * 2.23) * 0.17
	)
	return wave * terrain_texture_depth * clampf(roughness, 0.0, 1.5)


func _apply_ground_drive(throttle: float, brake: float, steer: float, lean: float, delta: float) -> void:
	var ground_up := _get_ground_normal()
	var planar_speed := get_speed_mps()
	var body_forward := -global_transform.basis.z.slide(ground_up)
	if body_forward.length_squared() < 0.1:
		body_forward = -global_transform.basis.z.slide(Vector3.UP)
	body_forward = body_forward.normalized()
	var signed_planar_speed := linear_velocity.dot(body_forward)
	_apply_low_speed_heading_hold(ground_up, steer, planar_speed)
	var speed_ratio := clampf(planar_speed / maxf(maximum_speed_mps, 1.0), 0.0, 1.0)
	var curvature_speed_ratio := smoothstep(4.0, 28.0, planar_speed)
	var target_curvature := lerpf(
		low_speed_turn_curvature,
		high_speed_turn_curvature,
		curvature_speed_ratio
	)
	_target_ground_yaw_rate = clampf(
		-steer * signed_planar_speed * target_curvature,
		-maximum_ground_yaw_rate,
		maximum_ground_yaw_rate
	)
	_update_slide_state(throttle, brake, steer, planar_speed, delta)
	_update_rut_state(steer, planar_speed, delta)
	if _slide_active:
		_target_ground_yaw_rate = clampf(
			_target_ground_yaw_rate * lerpf(1.0, 1.28, float(_slide_factors.get(&"rotation_factor", 0.0))),
			-maximum_ground_yaw_rate * 1.16,
			maximum_ground_yaw_rate * 1.16
		)
	# The visual bars still use the full command, but the physical contact patch
	# needs only a modest angle because the yaw servo and bank supply the rest of
	# the turn. Large ray-tire angles make the chassis snap ahead of its trajectory.
	var steering_geometry_taper := lerpf(0.45, 0.30, curvature_speed_ratio)
	var target_steer_angle := -steer * deg_to_rad(maximum_steer_degrees) * steering_geometry_taper
	_steer_angle = lerpf(_steer_angle, target_steer_angle, 1.0 - exp(-steering_angle_response * delta))
	_prepare_contact_basis(_front_contact, _steer_angle)
	# The recovered VehicleBody steers its rear VehicleWheel in opposition, but
	# applying that geometry directly to this force-projecting ray tire makes the
	# chassis rotate faster than its travel direction (the perceived ice slide).
	# Keep the rear contact nearly straight so it anchors the path while the front
	# tire and lean establish the turn.
	_prepare_contact_basis(_rear_contact, -_steer_angle * rear_countersteer_ratio)

	var speed_limit := maximum_speed_mps * (1.18 if is_boosting() else 1.0)
	var rear_longitudinal_request := 0.0
	if throttle > 0.0 and _rear_contact.colliding:
		# The reference bike holds full engine force through the approach and cuts it
		# only at the configured threshold. A small body-grade assist keeps the rear
		# wheel driving while the front is still planted on a jump face.
		if _rear_contact.longitudinal_speed < speed_limit:
			var uphill_component := clampf((-global_transform.basis.z).normalized().y, 0.0, 1.0)
			var hill_support := 0.0
			if _front_contact.colliding and uphill_component > 0.0:
				hill_support = rad_to_deg(uphill_component) / 90.0 * hill_assist_force
				rear_longitudinal_request += throttle * (
				engine_force * _run_engine_multiplier * _gate_launch_drive_multiplier + hill_support
			)
			var roost_cost := RACECRAFT_RULES.roost_drive_cost_fraction(
				float(_pack_racecraft_context.get(&"roost_pressure", 0.0)),
				1.0
			)
			rear_longitudinal_request *= 1.0 - roost_cost
			var draft_strength := clampf(float(_pack_racecraft_context.get(&"draft_strength", 0.0)), 0.0, 1.0)
			rear_longitudinal_request += throttle * draft_assist_force * draft_strength
	if is_boosting() and _rear_contact.colliding:
		var boost_falloff := clampf(_boost_time / 0.22, 0.15, 1.0)
		rear_longitudinal_request += flow_boost_force * boost_falloff

	var front_longitudinal_request := 0.0
	if brake > 0.0:
		var forward_speed := maxf(_front_contact.longitudinal_speed, _rear_contact.longitudinal_speed)
		if forward_speed > 0.8:
			front_longitudinal_request = -brake_force * brake * front_brake_bias
			rear_longitudinal_request -= brake_force * brake * (1.0 - front_brake_bias)
		elif _rear_contact.longitudinal_speed > -3.5:
			rear_longitudinal_request -= reverse_force * brake
	elif throttle <= 0.01:
		# A real rider holds the bike against a start-slope with tire pressure and a
		# planted boot. Model that static grip below jogging speed so an unattended
		# grid bike cannot roll beyond the beginning of the authored ribbon.
		var grid_hold_ratio := 1.0 - smoothstep(0.6, 3.0, planar_speed)
		var gravity_along_ground := (Vector3.DOWN * mass * _gravity_magnitude).slide(ground_up)
		apply_central_force(-gravity_along_ground * grid_hold_ratio)
		front_longitudinal_request -= _front_contact.longitudinal_speed * grid_hold_grip * grid_hold_ratio
		rear_longitudinal_request -= _rear_contact.longitudinal_speed * grid_hold_grip * grid_hold_ratio

	var wobble_grip := lerpf(0.88, 1.0, clampf(1.0 - _wobble_time / 1.1, 0.0, 1.0))
	var rail_grip := 1.16 if _active_flow_mode == RACECRAFT_RULES.FLOW_RAIL else 1.0
	var berm_grip := 1.0 + clampf(float(_course_racecraft_context.get(&"berm_strength", 0.0)), 0.0, 1.0) * 0.15
	var rut_grip := 1.0 + float(_rut_snapshot.get(&"capture_factor", 0.0)) * 0.10
	var slide_rear_grip := float(_slide_factors.get(&"grip_factor", 1.0)) if _slide_active else 1.0
	_apply_tire_force(
		_front_contact,
		front_longitudinal_request,
		wobble_grip,
		front_longitudinal_grip_scale,
		front_lateral_grip_scale * rail_grip * berm_grip * rut_grip
	)
	_apply_tire_force(
		_rear_contact,
		rear_longitudinal_request,
		wobble_grip,
		rear_longitudinal_grip_scale,
		rear_lateral_grip_scale * rail_grip * berm_grip * rut_grip * slide_rear_grip
	)
	var stability_scale := 0.36 if _slide_active else (1.24 if _active_flow_mode == RACECRAFT_RULES.FLOW_RAIL else 1.0)
	_apply_chassis_lateral_stability(ground_up, _target_ground_yaw_rate, stability_scale)

	var planar_velocity := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	if rolling_drag > 0.0:
		apply_central_force(-planar_velocity * rolling_drag * _average_contact_drag())
	var steer_authority := clampf(absf(_rear_contact.longitudinal_speed) / 4.0, 0.18, 1.0)
	var reverse_sign := -1.0 if _rear_contact.longitudinal_speed < -0.5 else 1.0
	var direct_assist_taper := lerpf(1.0, 0.54, pow(speed_ratio, 1.25))
	var slip_taper := lerpf(1.0, 0.85, maxf(_front_contact.slip, _rear_contact.slip))
	var normalized_steer_angle := clampf(_steer_angle / maxf(deg_to_rad(maximum_steer_degrees), 0.001), -1.0, 1.0)
	apply_torque(
		ground_up
		* normalized_steer_angle
		* steering_torque
		* steering_assist_ratio
		* steer_authority
		* direct_assist_taper
		* slip_taper
		* reverse_sign
	)
	var yaw_rate := angular_velocity.dot(ground_up)
	var yaw_rate_torque := clampf(
		(_target_ground_yaw_rate - yaw_rate) * yaw_rate_response_strength,
		-yaw_rate_torque_limit,
		yaw_rate_torque_limit
	)
	apply_torque(ground_up * yaw_rate_torque * steer_authority)

	var rider_right := (-global_transform.basis.z).slide(ground_up).normalized().cross(ground_up).normalized()
	if rider_right.length_squared() > 0.5:
		apply_torque(rider_right * _weight_shift * rider_weight_shift_torque)


func _apply_low_speed_heading_hold(ground_up: Vector3, steer: float, speed_mps: float) -> void:
	var current_forward := -global_transform.basis.z.slide(ground_up)
	if current_forward.length_squared() < 0.1:
		return
	current_forward = current_forward.normalized()
	if absf(steer) > 0.08 or speed_mps > 3.0:
		_low_speed_forward = current_forward
		return
	var target_forward := _low_speed_forward.slide(ground_up)
	if target_forward.length_squared() < 0.1:
		_low_speed_forward = current_forward
		return
	target_forward = target_forward.normalized()
	var heading_error := atan2(
		current_forward.cross(target_forward).dot(ground_up),
		current_forward.dot(target_forward)
	)
	var hold_ratio := (1.0 - smoothstep(0.7, 3.0, speed_mps)) * (1.0 - absf(steer))
	var yaw_velocity := angular_velocity.dot(ground_up)
	apply_torque(
		ground_up
		* (heading_error * low_speed_heading_strength - yaw_velocity * low_speed_heading_damping)
		* hold_ratio
	)


func _apply_chassis_lateral_stability(
	ground_up: Vector3,
	target_yaw_rate: float,
	stability_scale: float = 1.0
) -> void:
	var body_forward := -global_transform.basis.z.slide(ground_up)
	if body_forward.length_squared() < 0.1:
		return
	body_forward = body_forward.normalized()
	var body_right := body_forward.cross(ground_up).normalized()
	var lateral_speed := linear_velocity.dot(body_right)
	var signed_forward_speed := linear_velocity.dot(body_forward)
	var forward_speed := absf(signed_forward_speed)
	var total_load := _front_contact.load + _rear_contact.load
	var contact_friction := (
		_front_contact.friction + _rear_contact.friction
	) * 0.5 if _front_contact.colliding and _rear_contact.colliding else (
		_front_contact.friction if _front_contact.colliding else _rear_contact.friction
	)
	var load_limited_force := total_load * contact_friction * _run_grip_multiplier * _session_grip_multiplier * 1.5
	var force_limit := minf(chassis_lateral_force_limit, load_limited_force)
	var lateral_force := clampf(
		-lateral_speed * chassis_lateral_stiffness,
		-force_limit,
		force_limit
	)
	apply_central_force(body_right * lateral_force)
	# A real bike's bank and tire camber generate centripetal force before the
	# chassis has visibly accumulated a large body-frame slip angle. Supplying part
	# of that force at the centre of mass keeps trajectory and yaw connected while
	# the two ray tires still own bumps, braking, drive, and the remaining cornering
	# load. This is deliberately force-based; the rigid body is never teleported.
	var turn_support_force := -target_yaw_rate * signed_forward_speed * mass * 0.48
	apply_central_force(body_right * turn_support_force)

	# Align the chassis with its actual travel direction instead of letting the
	# high rear drive cap translate the whole bike sideways through a corner.
	var sideslip_angle := atan2(lateral_speed, maxf(forward_speed, 0.5))
	var speed_scale := smoothstep(2.5, 12.0, forward_speed)
	var yaw_rate := angular_velocity.dot(ground_up)
	var aligning_torque := (
		-sideslip_angle * sideslip_alignment_strength
		- yaw_rate * ground_yaw_damping * (1.0 - smoothstep(0.03, 0.3, absf(_steer_input)))
	) * speed_scale * clampf(stability_scale, 0.0, 1.5)
	apply_torque(ground_up * aligning_torque)


func _prepare_contact_basis(contact: WheelContact, steering_angle: float) -> void:
	if not contact.colliding:
		return
	var forward := -global_transform.basis.z.slide(contact.normal)
	if forward.length_squared() < 0.25:
		forward = Vector3.FORWARD.slide(contact.normal)
	forward = forward.normalized().rotated(contact.normal, steering_angle)
	contact.forward = forward
	contact.right = forward.cross(contact.normal).normalized()
	var force_offset := contact.point - global_position
	var point_velocity := linear_velocity + angular_velocity.cross(force_offset)
	contact.longitudinal_speed = point_velocity.dot(contact.forward)
	contact.lateral_speed = point_velocity.dot(contact.right)


func _apply_tire_force(
	contact: WheelContact,
	longitudinal_request: float,
	wobble_grip: float,
	longitudinal_grip_scale: float,
	lateral_grip_scale: float
) -> void:
	var minimum_supported_load := mass * _gravity_magnitude * 0.012
	if not contact.colliding or contact.load < minimum_supported_load:
		return
	var lateral_request := -contact.lateral_speed * lateral_grip
	var base_grip := (
		contact.load
		* contact.friction
		* _run_grip_multiplier
		* _session_grip_multiplier
		* wobble_grip
		* tire_load_grip_scale
	)
	var longitudinal_capacity := maxf(base_grip * longitudinal_grip_scale, 1.0)
	var lateral_capacity := maxf(base_grip * lateral_grip_scale, 1.0)
	var longitudinal_usage := longitudinal_request / longitudinal_capacity
	var lateral_usage := lateral_request / lateral_capacity
	contact.grip_usage = sqrt(longitudinal_usage * longitudinal_usage + lateral_usage * lateral_usage)
	var force_scale := 1.0 / contact.grip_usage if contact.grip_usage > 1.0 else 1.0
	var requested_force := (
		contact.forward * longitudinal_request
		+ contact.right * lateral_request
	) * force_scale
	apply_force(requested_force, contact.point - global_position)

	var demand_slip := clampf((contact.grip_usage - 0.82) / 0.72, 0.0, 1.0)
	var lateral_slip := clampf(absf(contact.lateral_speed) / 7.5, 0.0, 1.0)
	contact.slip = maxf(demand_slip, lateral_slip)


func _surface_from_ray(ray: RayCast3D) -> StringName:
	if not _surface_override.is_empty():
		return _surface_override
	var collider: Object = ray.get_collider()
	if collider == null:
		return _legacy_surface
	if collider.has_meta(&"surface"):
		return _canonical_surface(collider.get_meta(&"surface"))
	var collider_node := collider as Node
	if collider_node == null:
		return _legacy_surface
	for group_surface: Array in [
		[&"surface_mud", &"MUD"],
		[&"surface_gravel", &"GRAVEL"],
		[&"surface_rock", &"ROCK"],
		[&"surface_loose_dirt", &"LOOSE_DIRT"],
	]:
		if collider_node.is_in_group(group_surface[0]):
			return group_surface[1]
	return _legacy_surface


func _roughness_from_ray(ray: RayCast3D, surface: StringName) -> float:
	return _metadata_float_from_ray(ray, &"roughness", _surface_roughness(surface), 0.0, 1.5)


func _metadata_float_from_ray(
	ray: RayCast3D,
	key: StringName,
	fallback: float,
	minimum: float,
	maximum: float
) -> float:
	var collider: Object = ray.get_collider()
	if collider == null or not collider.has_meta(key):
		return fallback
	var value: Variant = collider.get_meta(key)
	if value is float or value is int:
		return clampf(float(value), minimum, maximum)
	return fallback


func _canonical_surface(value: Variant) -> StringName:
	var key := String(value).strip_edges().to_upper().replace(" ", "_").replace("-", "_")
	match key:
		"PACKED", "HARDPACK", "HARD_PACK":
			return &"PACKED"
		"DIRT":
			return &"DIRT"
		"LOAM":
			return &"LOAM"
		"MUD", "WET_MUD":
			return &"MUD"
		"GRAVEL", "PEBBLES":
			return &"GRAVEL"
		"ROCK", "STONE":
			return &"ROCK"
		"LOOSE", "LOOSE_DIRT", "SAND":
			return &"LOOSE_DIRT"
		_:
			return &"PACKED"


func _surface_friction(surface: StringName) -> float:
	return SURFACE_FRICTION.get(surface, 1.0)


func _surface_drag(surface: StringName) -> float:
	return SURFACE_DRAG.get(surface, 1.0)


func _surface_roughness(surface: StringName) -> float:
	return SURFACE_ROUGHNESS.get(surface, 0.35)


func _surface_roost(surface: StringName) -> float:
	return SURFACE_ROOST.get(surface, 0.8)


func _update_active_surface() -> void:
	var next_surface := _legacy_surface
	var next_roughness := _surface_roughness(next_surface)
	var next_roost := _surface_roost(next_surface)
	if _rear_contact.colliding:
		next_surface = _rear_contact.surface
		next_roughness = _rear_contact.roughness
		next_roost = _rear_contact.roost
	elif _front_contact.colliding:
		next_surface = _front_contact.surface
		next_roughness = _front_contact.roughness
		next_roost = _front_contact.roost
	if _front_contact.colliding and _rear_contact.colliding:
		next_roughness = (_front_contact.roughness + _rear_contact.roughness) * 0.5
		next_roost = (_front_contact.roost + _rear_contact.roost) * 0.5
	_set_active_surface(next_surface, next_roughness, next_roost)


func _set_active_surface(surface: StringName, roughness: float, roost: float = -1.0) -> void:
	var surface_changed := surface != _active_surface
	_active_surface = surface
	_terrain_roughness = clampf(roughness, 0.0, 1.5)
	_terrain_roost = _surface_roost(surface) if roost < 0.0 else clampf(roost, 0.0, 2.5)
	if surface_changed:
		_visual.call(&"set_surface", _active_surface)


func _average_contact_drag() -> float:
	var drag := 0.0
	var count := 0
	if _front_contact.colliding:
		drag += _front_contact.drag
		count += 1
	if _rear_contact.colliding:
		drag += _rear_contact.drag
		count += 1
	return drag / float(count) if count > 0 else _surface_drag(_legacy_surface)


func _update_terrain_feedback(delta: float) -> void:
	var raw_activity := maxf(
		absf(_front_contact.compression_velocity),
		absf(_rear_contact.compression_velocity)
	)
	var target_activity := clampf(raw_activity / 4.5, 0.0, 1.0) if _grounded else 0.0
	_suspension_activity = lerpf(
		_suspension_activity,
		target_activity,
		1.0 - exp(-9.0 * delta)
	)
	_feedback_time += delta
	if _feedback_time >= 0.08:
		terrain_feedback_updated.emit(
			_active_surface,
			_terrain_roughness,
			get_rear_slip(),
			_front_contact.compression,
			_rear_contact.compression,
			_suspension_activity
		)
		if controls_enabled and _grounded and _priority_haptic_time <= 0.0:
			var low_motor := clampf(0.012 + _terrain_roughness * 0.026 + _suspension_activity * 0.09, 0.0, 0.18)
			var high_motor := clampf(0.01 + _suspension_activity * 0.17 + get_rear_slip() * 0.13, 0.0, 0.28)
			_play_haptic(low_motor, high_motor, 0.09)
		_feedback_time = 0.0


func _update_visual_and_audio(
	delta: float,
	speed_mps: float,
	steer: float,
	lean: float,
	throttle: float = 0.0
) -> void:
	var wheel_speed := speed_mps
	if _rear_contact.colliding:
		wheel_speed = _rear_contact.longitudinal_speed
	elif _front_contact.colliding:
		wheel_speed = _front_contact.longitudinal_speed
	_wheel_spin = fmod(_wheel_spin + wheel_speed / maxf(wheel_radius, 0.01) * delta, TAU)
	var front_y := _wheel_center_y(_front_ray, _front_distance)
	var rear_y := _wheel_center_y(_rear_ray, _rear_distance)
	var speed_dust := clampf((speed_mps - 1.0) / 15.0, 0.0, 1.0)
	var dust_amount := clampf(
		speed_dust * (0.22 + _terrain_roughness * 0.55) + get_rear_slip() * 0.7,
		0.0,
		1.0
	) if _grounded else 0.0
	var lateral_slip := maxf(absf(_front_contact.lateral_speed), absf(_rear_contact.lateral_speed))
	_visual.call(
		&"update_pose",
		front_y,
		rear_y,
		_wheel_spin,
		speed_mps,
		steer,
		lean,
		dust_amount,
		is_boosting(),
		clampf(_wobble_time / 1.1, 0.0, 1.0),
		lateral_slip,
		delta,
		_rear_contact.point,
		_rear_contact.normal,
		_rear_contact.forward,
		_rear_contact.colliding,
		_active_surface,
		_terrain_roughness,
		_terrain_roost,
		get_rear_slip(),
		_front_contact.compression,
		_rear_contact.compression,
		_suspension_activity
	)
	_engine_audio.call(
		&"set_engine_state",
		speed_mps,
		throttle,
		_grounded,
		_active_surface,
		_terrain_roughness,
		get_rear_slip(),
		_suspension_activity
	)


func _update_telemetry(delta: float, speed_mps: float, throttle: float) -> void:
	_telemetry_time += delta
	if _telemetry_time >= 0.08:
		telemetry_updated.emit(speed_mps * 2.236936, throttle, _grounded)
		_telemetry_time = 0.0


func _get_contact_midpoint() -> Vector3:
	if _front_contact.colliding and _rear_contact.colliding:
		return (_front_contact.point + _rear_contact.point) * 0.5
	if _rear_contact.colliding:
		return _rear_contact.point
	if _front_contact.colliding:
		return _front_contact.point
	return global_position + Vector3.DOWN * 0.5


func _update_gate_launch_drive(delta: float) -> void:
	if _gate_launch_time <= 0.0:
		return
	_gate_launch_time = maxf(_gate_launch_time - delta, 0.0)
	if _gate_launch_time <= 0.0:
		_gate_launch_drive_multiplier = 1.0


func _handle_flow_boost(delta: float, brake: float, steer: float) -> void:
	var was_boosting := is_boosting()
	_boost_time = maxf(_boost_time - delta, 0.0)
	_flow_mode_time = maxf(_flow_mode_time - delta, 0.0)
	if _flow_mode_time <= 0.0:
		_active_flow_mode = &"NONE"
	var landing_risk := clampf(
		maxf(-linear_velocity.y / 9.0, _landing_alignment_weight * 0.65),
		0.0,
		1.0
	)
	var wobble_strength := clampf(_wobble_time / 1.1, 0.0, 1.0)
	var pack_pressure := maxf(
		float(_pack_racecraft_context.get(&"contact_pressure", 0.0)),
		float(_pack_racecraft_context.get(&"roost_pressure", 0.0)) * 0.55
	)
	var evaluation: Dictionary = RACECRAFT_RULES.evaluate_flow_technique(
		_flow,
		_grounded,
		brake,
		steer,
		landing_risk,
		wobble_strength,
		pack_pressure
	)
	_recommended_flow_mode = StringName(evaluation.get(&"technique", RACECRAFT_RULES.FLOW_SURGE))
	if controls_enabled and InputRouter.is_flow_boost_just_pressed():
		if not bool(evaluation.get(&"affordable", false)):
			_emit_racecraft_event(&"FLOW_DENIED", {
				&"technique": _recommended_flow_mode,
				&"required": float(evaluation.get(&"cost", 0.0)),
				&"available": _flow,
			})
		else:
			_activate_flow_technique(_recommended_flow_mode, float(evaluation.get(&"cost", 0.0)))
	if was_boosting and not is_boosting():
		flow_changed.emit(_flow, false)


func _activate_flow_technique(technique: StringName, cost: float) -> void:
	_flow = maxf(_flow - maxf(cost, 0.0), 0.0)
	_active_flow_mode = technique
	var points := 120
	var duration := 0.85
	match technique:
		RACECRAFT_RULES.FLOW_SURGE:
			_boost_time = flow_boost_duration
			duration = flow_boost_duration
			var forward := -global_transform.basis.z.slide(_get_ground_normal()).normalized()
			apply_central_impulse(forward * mass * flow_boost_impulse)
			boost_activated.emit(_flow)
			_visual.call(&"burst_boost")
			_play_haptic(0.32, 0.58, 0.22)
			points = 120
		RACECRAFT_RULES.FLOW_RAIL:
			duration = 1.05
			_play_haptic(0.18, 0.36, 0.16)
			points = 165
		RACECRAFT_RULES.FLOW_COMPOSE:
			duration = 1.20
			_compose_landing_charge = 1.0
			_play_haptic(0.10, 0.22, 0.14)
			points = 180
		RACECRAFT_RULES.FLOW_BRACE:
			duration = 0.95
			_wobble_time *= 0.42
			_play_haptic(0.24, 0.42, 0.18)
			points = 150
	_flow_mode_time = duration
	flow_changed.emit(_flow, technique == RACECRAFT_RULES.FLOW_SURGE)
	style_event.emit(StringName("FLOW %s" % String(technique)), points)
	_emit_racecraft_event(StringName("FLOW_%s" % String(technique)), {
		&"technique": technique,
		&"cost": cost,
		&"flow_remaining": _flow,
		&"duration": duration,
	})
	_priority_haptic_time = maxf(_priority_haptic_time, 0.24)


func _handle_racecraft_technique(throttle: float, _brake: float, _steer: float) -> void:
	if not controls_enabled or _motion_locked or _technique_cooldown > 0.0:
		return
	if not InputRouter.is_racecraft_just_pressed():
		return
	if not _grounded:
		# Airborne recovery is deliberately owned by Context Flow / COMPOSE. Keeping
		# the clutch button quiet in flight prevents two inputs from fighting over
		# the same angular state.
		return
	var speed := get_speed_mps()
	var upright := global_transform.basis.y.normalized().dot(_get_ground_normal())
	if speed < 4.8 or _wobble_time > 0.20 or upright < 0.58:
		_perform_dab()
	elif _suspension_activity > 0.24 and _front_contact.colliding and _rear_contact.colliding:
		_perform_pump()
	elif throttle > 0.12:
		_perform_clutch_pop()
	else:
		_perform_dab()
	_technique_cooldown = racecraft_technique_cooldown
	_technique_display_time = 1.0


func _perform_dab() -> void:
	_active_technique = &"DAB"
	var ground_up := _get_ground_normal()
	var current_up := global_transform.basis.y.normalized()
	var correction_axis := current_up.cross(ground_up)
	apply_torque_impulse(correction_axis * mass * 1.8)
	var forward := -global_transform.basis.z.slide(ground_up).normalized()
	var lateral_velocity := linear_velocity.slide(ground_up) - forward * linear_velocity.dot(forward)
	apply_central_impulse(-lateral_velocity * mass * 0.24)
	_wobble_time *= 0.18
	_play_haptic(0.16, 0.28, 0.13)
	_emit_racecraft_event(&"DAB", {&"speed_mps": get_speed_mps()})
	style_event.emit(&"FOOT DAB SAVE", 145)


func _perform_pump() -> void:
	_active_technique = &"PUMP"
	var load := clampf(maxf(_front_contact.compression, _rear_contact.compression) / maxf(suspension_rest_length, 0.01), 0.0, 1.0)
	var release_timing := clampf(1.0 - absf(_front_contact.compression - _rear_contact.compression) / maxf(suspension_rest_length, 0.01), 0.0, 1.0)
	var downhill := clampf(float(_course_racecraft_context.get(&"downhill_strength", 0.0)), 0.0, 1.0)
	var multiplier := RACECRAFT_RULES.pump_momentum_multiplier(load, release_timing, downhill)
	var velocity_gain := clampf(get_speed_mps() * (multiplier - 1.0), -0.45, pump_maximum_velocity_gain)
	var forward := -global_transform.basis.z.slide(_get_ground_normal()).normalized()
	apply_central_impulse(forward * mass * velocity_gain)
	_add_flow(4.0 * load * release_timing)
	_play_haptic(0.22, 0.40, 0.15)
	_emit_racecraft_event(&"PUMP", {
		&"load": load,
		&"timing": release_timing,
		&"momentum_multiplier": multiplier,
	})
	style_event.emit(&"PUMPED TERRAIN", int(round(135.0 + release_timing * 95.0)))


func _perform_clutch_pop() -> void:
	_active_technique = &"CLUTCH_POP"
	var ground_up := _get_ground_normal()
	var forward := -global_transform.basis.z.slide(ground_up).normalized()
	var rider_right := forward.cross(ground_up).normalized()
	apply_central_impulse(
		forward * mass * clutch_pop_forward_velocity
		+ ground_up * mass * clutch_pop_lift_velocity * 0.42
	)
	apply_torque_impulse(rider_right * mass * clutch_pop_lift_velocity * 0.22)
	_play_haptic(0.28, 0.48, 0.14)
	_emit_racecraft_event(&"CLUTCH_POP", {&"speed_mps": get_speed_mps()})
	style_event.emit(&"CLUTCH POP", 170)


func _update_slide_state(throttle: float, brake: float, steer: float, speed: float, delta: float) -> void:
	var slide_input := (
		smoothstep(0.24, 0.86, brake)
		* smoothstep(0.20, 0.78, absf(steer))
		* smoothstep(5.5, 13.5, speed)
	)
	var was_active := _slide_active
	_slide_active = slide_input > 0.045
	if not _slide_active:
		if was_active:
			_finish_slide()
		_slide_time = 0.0
		_slide_awarded = false
		_slide_factors.clear()
		return
	var sideslip := clampf(get_body_sideslip_angle() * 2.2, -1.0, 1.0)
	var countersteer_quality := clampf(1.0 - absf(steer + sideslip), 0.0, 1.0)
	var throttle_catch := smoothstep(0.20, 0.82, throttle)
	_slide_factors = RACECRAFT_RULES.rear_slide_factors(
		_active_surface,
		slide_input,
		countersteer_quality,
		throttle_catch
	)
	_slide_time += delta
	if _slide_time >= 0.42 and not _slide_awarded:
		_slide_awarded = true
		_add_flow(6.0 * float(_slide_factors.get(&"catch_quality", 0.0)))
		_emit_racecraft_event(&"CONTROLLED_SLIDE", {
			&"surface": _active_surface,
			&"catch_quality": float(_slide_factors.get(&"catch_quality", 0.0)),
			&"seconds": _slide_time,
		})
		style_event.emit(&"CONTROLLED SLIDE", 245)


func _finish_slide() -> void:
	if _slide_factors.is_empty():
		return
	var exit_factor := float(_slide_factors.get(&"exit_factor", 1.0))
	var planar := linear_velocity.slide(_get_ground_normal())
	if planar.length_squared() < 0.1:
		return
	var requested_delta_v := clampf(planar.length() * (exit_factor - 1.0), -1.2, 0.75)
	apply_central_impulse(planar.normalized() * mass * requested_delta_v)
	if _slide_awarded:
		_emit_racecraft_event(&"SLIDE_EXIT", {
			&"momentum_multiplier": exit_factor,
			&"caught": float(_slide_factors.get(&"catch_quality", 0.0)) >= 0.55,
		})


func _update_scrub(lean: float, delta: float) -> void:
	if _slide_active:
		_finish_slide()
		_slide_active = false
		_slide_time = 0.0
	_scrub_strength = RACECRAFT_RULES.scrub_strength_from_lean(lean)
	if _scrub_strength < 0.50:
		return
	_scrub_time += delta
	if linear_velocity.y > 0.15:
		apply_central_force(
			Vector3.DOWN * mass * _gravity_magnitude * scrub_downforce_ratio * _scrub_strength
		)


func _apply_landing_momentum(intensity: float) -> void:
	var ground_up := _get_ground_normal()
	var surface_alignment := global_transform.basis.y.normalized().dot(ground_up)
	var planar := linear_velocity.slide(ground_up)
	var forward := -global_transform.basis.z.slide(ground_up).normalized()
	var travel_alignment := planar.normalized().dot(forward) if planar.length_squared() > 0.1 else 1.0
	var landing_multiplier := RACECRAFT_RULES.landing_momentum_multiplier(
		surface_alignment,
		travel_alignment,
		intensity,
		_compose_landing_charge
	)
	if _scrub_time >= 0.12:
		landing_multiplier *= RACECRAFT_RULES.scrub_momentum_multiplier(
			-_scrub_strength,
			_scrub_time,
			_takeoff_alignment
		)
	landing_multiplier = clampf(landing_multiplier, RACECRAFT_RULES.LANDING_MOMENTUM_MIN, 1.0)
	if planar.length_squared() > 0.1:
		var momentum_loss := clampf(planar.length() * (1.0 - landing_multiplier), 0.0, 2.6)
		apply_central_impulse(-planar.normalized() * mass * momentum_loss)
	_emit_racecraft_event(&"LANDING", {
		&"momentum_multiplier": landing_multiplier,
		&"impact": intensity,
		&"composed": _compose_landing_charge > 0.15,
	})
	if _compose_landing_charge > 0.15 and intensity < 0.9:
		_emit_racecraft_event(&"COMPOSE_SAVE", {&"impact": intensity})
		style_event.emit(&"COMPOSED LANDING", 210)
	_compose_landing_charge = 0.0


func _update_rut_state(steer: float, speed: float, delta: float) -> void:
	var rut_strength := clampf(float(_course_racecraft_context.get(&"rut_strength", 0.0)), 0.0, 1.0)
	if rut_strength <= 0.08:
		_rut_time = 0.0
		_rut_awarded = false
		_rut_snapshot.clear()
		return
	var route_alignment := clampf(float(_course_racecraft_context.get(&"route_alignment", 1.0)), -1.0, 1.0)
	var speed_ratio := speed / maxf(maximum_speed_mps * 0.72, 1.0)
	_rut_snapshot = RACECRAFT_RULES.evaluate_rut(
		_active_surface,
		route_alignment,
		speed_ratio,
		absf(steer),
		rut_strength
	)
	_rut_snapshot[&"strength"] = rut_strength
	_rut_time += delta
	var steering_assist := float(_rut_snapshot.get(&"steering_assist", 0.0))
	var turn_sign := signf(float(_course_racecraft_context.get(&"turn_sign", 0.0)))
	if steering_assist > 0.0 and not is_zero_approx(turn_sign):
		apply_torque(_get_ground_normal() * turn_sign * steering_assist * 420.0)
	if _rut_time >= 0.58 and not _rut_awarded and StringName(_rut_snapshot.get(&"outcome", &"")) == &"RAILED":
		_rut_awarded = true
		_add_flow(4.0)
		_emit_racecraft_event(&"RUT_RAIL", _rut_snapshot)
		style_event.emit(&"RUT RAIL", 235)


func _update_skill_line(delta: float) -> void:
	var next_zone := StringName(_course_racecraft_context.get(&"skill_zone_id", &""))
	var active := bool(_course_racecraft_context.get(&"skill_zone_active", false)) and not next_zone.is_empty()
	if next_zone != _skill_zone_id:
		_skill_zone_id = next_zone
		_skill_zone_time = 0.0
		_skill_zone_resolved = false
		_skill_line_outcome = &"NONE"
	if not active or _skill_zone_resolved or not controls_enabled:
		return
	_skill_zone_time += delta
	if _skill_zone_time < 0.62:
		return
	var alignment := clampf(float(_course_racecraft_context.get(&"skill_line_alignment", 0.0)), 0.0, 1.0)
	var timing := clampf(maxf(
		_suspension_activity,
		maxf(
			float(_rut_snapshot.get(&"capture_factor", 0.0)),
			float(_slide_factors.get(&"catch_quality", 0.0))
		)
	), 0.0, 1.0)
	var commitment := clampf(maxf(_last_throttle, absf(_steer_input) * 0.72), 0.0, 1.0)
	var difficulty := clampf(float(_course_racecraft_context.get(&"skill_line_difficulty", 0.55)), 0.0, 1.0)
	var result: Dictionary = RACECRAFT_RULES.evaluate_skill_line(
		0.72 + _assist_strength * 0.12,
		alignment,
		timing,
		commitment,
		difficulty
	)
	_skill_zone_resolved = true
	_skill_line_outcome = StringName(result.get(&"outcome", &"MISSED"))
	var multiplier := float(result.get(&"momentum_multiplier", 1.0))
	var planar := linear_velocity.slide(_get_ground_normal())
	if planar.length_squared() > 0.1:
		var delta_v := clampf(planar.length() * (multiplier - 1.0), -1.8, 0.8)
		apply_central_impulse(planar.normalized() * mass * delta_v)
	_add_flow(float(result.get(&"flow_reward", 0.0)))
	var payload := result.duplicate(true)
	payload[&"zone_id"] = _skill_zone_id
	_emit_racecraft_event(&"SKILL_LINE", payload)
	style_event.emit(
		StringName("%s LINE" % String(_skill_line_outcome)),
		260 if _skill_line_outcome == &"MASTERED" else 180 if _skill_line_outcome == &"CLEAN" else 70
	)


func _add_flow(amount: float) -> void:
	var previous := _flow
	_flow = minf(_flow + maxf(amount, 0.0) * _flow_gain_multiplier, flow_capacity)
	var actual := _flow - previous
	if actual <= 0.01:
		return
	flow_gained.emit(actual)
	flow_changed.emit(_flow, is_boosting())


func _emit_racecraft_event(kind: StringName, payload: Dictionary = {}) -> void:
	if kind.is_empty():
		return
	_racecraft_counters[kind] = int(_racecraft_counters.get(kind, 0)) + 1
	var event_payload := payload.duplicate(true)
	event_payload[&"count"] = int(_racecraft_counters[kind])
	event_payload[&"surface"] = _active_surface
	racecraft_event.emit(kind, event_payload)


func _emit_racecraft_state(delta: float) -> void:
	_racecraft_state_time -= delta
	if _racecraft_state_time > 0.0:
		return
	_racecraft_state_time = 0.10
	racecraft_state_changed.emit(get_racecraft_snapshot())


func configure_feedback(values: Dictionary) -> void:
	_haptics_enabled = bool(values.get("haptics_enabled", true))
	_haptics_intensity = clampf(float(values.get("haptics_intensity", 0.8)), 0.0, 1.0)
	if not _haptics_enabled or _haptics_intensity <= 0.0:
		Input.stop_joy_vibration(0)


func _play_haptic(low_motor: float, high_motor: float, duration: float) -> void:
	if not _haptics_enabled or _haptics_intensity <= 0.0:
		return
	Input.start_joy_vibration(
		0,
		clampf(low_motor * _haptics_intensity, 0.0, 1.0),
		clampf(high_motor * _haptics_intensity, 0.0, 1.0),
		maxf(duration, 0.0)
	)


func _award_landing_flow(airtime: float, rotation_amount: float, clean: bool) -> void:
	if not controls_enabled or not clean or airtime < 0.45:
		return
	var rotation_turns := minf(rotation_amount / TAU, 2.0)
	var requested_gain := clampf((22.0 + airtime * 20.0 + rotation_turns * 12.0) * _flow_gain_multiplier, 14.0, 52.0)
	var previous_flow := _flow
	_flow = minf(_flow + requested_gain, flow_capacity)
	var actual_gain := _flow - previous_flow
	if actual_gain <= 0.01:
		return
	flow_gained.emit(actual_gain)
	flow_changed.emit(_flow, is_boosting())
	style_event.emit(&"CLEAN LANDING", int(round(160.0 + airtime * 80.0 + rotation_turns * 120.0)))


func _reset_flow() -> void:
	var had_flow := _flow > 0.01 or is_boosting() or _active_flow_mode != &"NONE"
	_flow = 0.0
	_boost_time = 0.0
	_active_flow_mode = &"NONE"
	_recommended_flow_mode = &"SURGE"
	_flow_mode_time = 0.0
	_compose_landing_charge = 0.0
	if had_flow:
		flow_changed.emit(_flow, false)


func _update_wheelie(delta: float, speed_mps: float) -> void:
	if _rear_ray.is_colliding() and not _front_ray.is_colliding() and speed_mps > 5.0:
		_wheelie_time += delta
		if _wheelie_time >= 0.8 and not _wheelie_awarded:
			_wheelie_awarded = true
			style_event.emit(&"WHEELIE", 220)
	elif _front_ray.is_colliding():
		_wheelie_time = 0.0
		_wheelie_awarded = false


func _apply_balance(steer: float) -> void:
	var ground_up := _get_ground_normal()
	var current_up := global_transform.basis.y.normalized()
	var forward := -global_transform.basis.z.slide(ground_up).normalized()
	if forward.length_squared() < 0.5:
		forward = Vector3.FORWARD
	var planar_speed := get_speed_mps()
	var commanded_bank := atan2(
		planar_speed * absf(_target_ground_yaw_rate),
		maxf(_gravity_magnitude, 0.1)
	) * turn_bank_ratio
	var minimum_readable_bank := (
		absf(steer)
		* deg_to_rad(maximum_lean_degrees)
		* 0.42
		* smoothstep(2.0, 8.0, planar_speed)
	)
	commanded_bank = maxf(commanded_bank, minimum_readable_bank)
	_target_bank_angle = signf(steer) * minf(commanded_bank, deg_to_rad(maximum_lean_degrees))
	var target_lean := _target_bank_angle
	var target_up := Basis(forward, target_lean) * ground_up
	var correction_axis := current_up.cross(target_up)
	var contact_count := int(_front_contact.colliding) + int(_rear_contact.colliding)
	# A rider retains roll control when bumps or a jump face unload one wheel.
	# The old 35% scale is what let Pine's opening rhythm tip the chassis over.
	var contact_scale := 1.0 if contact_count >= 2 else 0.86
	var assist_scale := lerpf(0.9, 1.12, _assist_strength)
	var roll_error := correction_axis.dot(forward)
	var roll_velocity := angular_velocity.dot(forward)
	var roll_torque := roll_error * upright_strength * assist_scale - roll_velocity * upright_damping
	apply_torque(forward * roll_torque * contact_scale)
	# A bike cannot balance fore/aft at walking pace through wheel geometry alone.
	# Give it strong, speed-gated rider support on the grid, then fade that support
	# away so launches, brake dive, wheelies, crests, and landings remain physical.
	var right := forward.cross(ground_up).normalized()
	var low_speed_pitch_support := 1.0 - smoothstep(2.5, 10.0, get_speed_mps())
	var pitch_error := correction_axis.dot(right)
	var pitch_velocity := angular_velocity.dot(right)
	var pitch_torque := (
		pitch_error * low_speed_pitch_strength * assist_scale * low_speed_pitch_support
		- pitch_velocity * (
			ground_pitch_damping
			+ low_speed_pitch_damping * low_speed_pitch_support
		)
	)
	# When the front unloads on launch, keep the virtual rider fully committed to
	# pitch control; above launch speed this returns to the natural one-wheel scale.
	var pitch_contact_scale := lerpf(contact_scale, 1.0, low_speed_pitch_support)
	apply_torque(right * pitch_torque * pitch_contact_scale)


func _apply_air_control(steer: float) -> void:
	var right := global_transform.basis.x.normalized()
	var forward := -global_transform.basis.z.normalized()
	var up := global_transform.basis.y.normalized()
	var pitch_rate := angular_velocity.dot(right)
	var roll_rate := angular_velocity.dot(forward)
	var yaw_rate := angular_velocity.dot(up)

	# Moto Tykes does not add a generic midair rotation impulse. It steers toward
	# persistent pitch and roll targets with strong, axis-specific PD control.
	# `asin(forward.y)` folds every pitch beyond 90 degrees back into the same
	# range, so the recovered controller's full forward target could never
	# converge. The sign of the bike's up axis disambiguates the far side of the
	# rotation while roll remains independently limited by its own controller.
	var pitch_cosine := Vector2(forward.x, forward.z).length()
	if up.y < 0.0:
		pitch_cosine = -pitch_cosine
	var current_pitch := atan2(forward.y, pitch_cosine)
	var target_pitch := _weight_shift * 3.0
	var pitch_error := wrapf(target_pitch - current_pitch, -PI, PI)
	apply_torque(right * (pitch_error * air_pitch_stiffness - pitch_rate * air_pitch_damping))

	var level_forward := forward.slide(Vector3.UP)
	if level_forward.length_squared() < 0.01:
		level_forward = -global_transform.basis.z.slide(Vector3.UP)
	if level_forward.length_squared() > 0.01:
		level_forward = level_forward.normalized()
		var target_roll := deg_to_rad(maximum_lean_degrees) * steer
		var target_up := Basis(level_forward, target_roll) * Vector3.UP
		var roll_error := up.cross(target_up).dot(forward)
		apply_torque(forward * (roll_error * air_roll_stiffness - roll_rate * air_roll_damping))
	else:
		apply_torque(forward * -roll_rate * air_roll_damping)

	apply_torque(up * (-steer * air_yaw_torque - yaw_rate * air_yaw_damping))
	if _active_flow_mode == RACECRAFT_RULES.FLOW_COMPOSE:
		# COMPOSE spends Flow on a short physical damping window. It reduces excess
		# angular energy but never writes orientation or steals deliberate input.
		var command_scale := 1.0 - clampf(absf(steer) * 0.45 + absf(_weight_shift) * 0.35, 0.0, 0.72)
		apply_torque(-angular_velocity * 520.0 * command_scale)
	_apply_landing_alignment(steer)
	if current_pitch > 1.2:
		apply_torque(right * -air_emergency_pitch_torque)


func _sample_landing_target() -> void:
	_landing_target_valid = false
	_landing_target_distance = INF
	_landing_alignment_weight = 0.0
	if linear_velocity.y > -landing_alignment_minimum_descent_speed:
		return
	var planar_velocity := linear_velocity.slide(Vector3.UP)
	var lead := Vector3.ZERO
	if planar_velocity.length_squared() > 1.0:
		lead = planar_velocity.normalized() * clampf(planar_velocity.length() * 0.085, 0.45, 1.7)
	var origin := global_position + Vector3.UP * 0.35
	var destination := origin + lead + Vector3.DOWN * landing_alignment_probe_distance
	var query := PhysicsRayQueryParameters3D.create(origin, destination)
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return
	var hit_normal: Vector3 = result.get(&"normal", Vector3.UP).normalized()
	if hit_normal.dot(Vector3.UP) < 0.32:
		return
	_landing_target_valid = true
	_landing_target_normal = hit_normal
	_landing_target_distance = origin.distance_to(result.get(&"position", destination))


func _apply_landing_alignment(steer: float) -> void:
	if not _landing_target_valid:
		_landing_alignment_weight = 0.0
		return
	var descent_ratio := smoothstep(
		landing_alignment_minimum_descent_speed,
		8.5,
		-linear_velocity.y
	)
	var proximity_ratio := 1.0 - smoothstep(
		1.0,
		landing_alignment_probe_distance,
		_landing_target_distance
	)
	# The assist prepares a neutral bike for the receiver, but it never steals a
	# deliberate whip or pitch command from the rider.
	var pitch_command := clampf(absf(_weight_shift) / 0.7, 0.0, 1.0)
	var command_override := clampf(absf(steer) * 0.72 + pitch_command * 0.78, 0.0, 1.0)
	_landing_alignment_weight = descent_ratio * proximity_ratio * (1.0 - command_override * 0.9)
	if _active_flow_mode == RACECRAFT_RULES.FLOW_COMPOSE or _compose_landing_charge > 0.15:
		_landing_alignment_weight = minf(_landing_alignment_weight * 1.42 + 0.08, 1.0)
	if _landing_alignment_weight <= 0.001:
		return
	var current_up := global_transform.basis.y.normalized()
	var correction_axis := current_up.cross(_landing_target_normal)
	var tilt_velocity := angular_velocity - _landing_target_normal * angular_velocity.dot(_landing_target_normal)
	apply_torque(
		(
			correction_axis * landing_alignment_strength
			- tilt_velocity * landing_alignment_damping
		) * _landing_alignment_weight
	)


func _apply_air_brake_pop(brake_just_pressed: bool) -> void:
	if _air_brake_pop_used or not controls_enabled or not brake_just_pressed:
		return
	_air_brake_pop_used = true
	if linear_velocity.y <= 0.0:
		return
	# Match the reference's subtle first-press airborne pop as a mass-scaled
	# impulse, producing the same +1.25 m/s response at any configured bike mass.
	apply_central_impulse(global_transform.basis.y.normalized() * mass * air_brake_pop_velocity)


func _update_center_of_mass(lean: float, brake: float, delta: float) -> void:
	# Store the recovered controller's actual lean state: -0.70 is fully forward,
	# +0.43 is fully rearward, and the 0.75 scale yields 0.8475 m of physical CoM
	# travel. The chosen position persists in flight.
	var effective_lean := lean
	if not _grounded and brake > 0.18 and lean < 0.04:
		effective_lean = -brake
	if absf(effective_lean) > 0.04:
		var shift_response := air_weight_shift_response if not _grounded else 0.8
		_weight_shift = clampf(
			_weight_shift + effective_lean * shift_response * delta,
			-0.7,
			0.43
		)
	elif _grounded:
		# The recovered script executes its grounded recenter block twice.
		_weight_shift = move_toward(_weight_shift, 0.0, delta * 3.2)
	var target := _base_center_of_mass
	target.z += _weight_shift * longitudinal_center_of_mass_travel
	center_of_mass = target


func _update_tipped_recovery(delta: float) -> void:
	var upright_dot := global_transform.basis.y.normalized().dot(Vector3.UP)
	var nearly_stopped := get_speed_mps() < 2.2 and absf(linear_velocity.y) < 1.4
	if upright_dot < 0.24 and nearly_stopped and _airtime > 0.55:
		_tipped_recovery_time += delta
		if _tipped_recovery_time >= tipped_recovery_delay:
			reset_to_safe_position(RECOVERY_TIPPED)
	else:
		_tipped_recovery_time = 0.0


func _handle_preload(delta: float) -> void:
	if not controls_enabled:
		_preload_charge = 0.0
		_preload_buffer_time = 0.0
		return
	if InputRouter.is_preload_pressed():
		_preload_charge = minf(_preload_charge + delta, 0.5)
	if InputRouter.is_preload_just_released():
		_preload_buffer_time = 0.14
	if _preload_buffer_time > 0.0 and _ground_coyote_time > 0.0 and _preload_charge > 0.08:
		var charge_ratio := _preload_charge / 0.5
		var ground_up := _get_ground_normal()
		var launch_up := (ground_up * 0.72 + global_transform.basis.y.normalized() * 0.28).normalized()
		var forward := -global_transform.basis.z.slide(ground_up).normalized()
		apply_central_impulse(launch_up * preload_impulse * charge_ratio + forward * preload_impulse * 0.24 * charge_ratio)
		_preload_charge = 0.0
		_preload_buffer_time = 0.0
	else:
		_preload_buffer_time = maxf(_preload_buffer_time - delta, 0.0)
		if _ground_coyote_time <= 0.0 and _preload_buffer_time <= 0.0 and not InputRouter.is_preload_pressed():
			_preload_charge = 0.0


func _get_ground_normal() -> Vector3:
	var normal := Vector3.ZERO
	var total_weight := 0.0
	if _front_contact.colliding:
		var front_weight := maxf(_front_contact.load, 1.0)
		normal += _front_contact.normal * front_weight
		total_weight += front_weight
	if _rear_contact.colliding:
		var rear_weight := maxf(_rear_contact.load, 1.0)
		normal += _rear_contact.normal * rear_weight
		total_weight += rear_weight
	if total_weight <= 0.0 or normal.length_squared() < 0.0001:
		return Vector3.UP
	normal = normal.normalized()
	return normal if normal.dot(Vector3.UP) > 0.08 else Vector3.UP


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
