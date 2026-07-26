extends Node3D
class_name ChaseCamera
## Multi-view riding camera with predictive framing, collision safety, and tactile response.

const REDUCED_SHAKE_SCALE: float = 0.08
const REDUCED_BANK_SCALE: float = 0.15
const REDUCED_IMPULSE_SCALE: float = 0.10
const REDUCED_DYNAMIC_POSITION_SCALE: float = 0.25
const REDUCED_LOOK_AHEAD_SCALE: float = 0.35
const REDUCED_SPEED_FOV_DELTA: float = 1.5
const VIEW_CHASE: StringName = &"CHASE"
const VIEW_CLOSE_CHASE: StringName = &"CLOSE_CHASE"
const VIEW_HELMET: StringName = &"HELMET"
const VIEW_FIRST_PERSON: StringName = &"FIRST_PERSON"
const VIEW_HANDLEBAR: StringName = &"HANDLEBAR"
const VIEW_MODES: Array[StringName] = [
	VIEW_CHASE, VIEW_CLOSE_CHASE, VIEW_HELMET, VIEW_FIRST_PERSON, VIEW_HANDLEBAR,
]
const VIEW_PROFILES: Dictionary = {
	VIEW_CHASE: {
		&"label": "CHASE",
		&"distance": 5.0,
		&"height": 2.05,
		&"look_height": 1.32,
		&"base_look_ahead": 0.85,
		&"speed_look_ahead": 2.25,
		&"position_response": 1.0,
		&"rotation_response": 1.0,
		&"dynamic_scale": 1.0,
		&"bank_scale": 1.0,
		&"fov_offset": 0.0,
	},
	VIEW_CLOSE_CHASE: {
		&"label": "CLOSE CHASE",
		&"distance": 3.35,
		&"height": 1.72,
		&"look_height": 1.28,
		&"base_look_ahead": 1.15,
		&"speed_look_ahead": 2.55,
		&"position_response": 1.12,
		&"rotation_response": 1.08,
		&"dynamic_scale": 0.82,
		&"bank_scale": 0.92,
		&"fov_offset": 1.0,
	},
	VIEW_HELMET: {
		&"label": "HELMET",
		# The optical point sits just ahead of the opaque procedural visor. Keeping
		# it inside the helmet mesh would hide the course on Web and low-end GPUs.
		&"distance": -0.62,
		&"height": 1.74,
		&"look_height": 1.68,
		&"base_look_ahead": 3.0,
		&"speed_look_ahead": 3.25,
		&"position_response": 1.65,
		&"rotation_response": 1.42,
		&"dynamic_scale": 0.34,
		&"bank_scale": 0.72,
		&"fov_offset": 2.0,
	},
	VIEW_FIRST_PERSON: {
		&"label": "FIRST PERSON",
		&"distance": -0.82,
		&"height": 1.62,
		&"look_height": 1.55,
		&"base_look_ahead": 3.5,
		&"speed_look_ahead": 3.7,
		&"position_response": 1.85,
		&"rotation_response": 1.58,
		&"dynamic_scale": 0.24,
		&"bank_scale": 0.58,
		&"fov_offset": 3.0,
	},
	VIEW_HANDLEBAR: {
		&"label": "HANDLEBAR",
		&"distance": -0.72,
		&"height": 1.08,
		&"look_height": 1.34,
		&"base_look_ahead": 3.85,
		&"speed_look_ahead": 4.0,
		&"position_response": 1.95,
		&"rotation_response": 1.68,
		&"dynamic_scale": 0.20,
		&"bank_scale": 0.82,
		&"fov_offset": 4.0,
	},
}

@export var follow_distance: float = 5.0
@export var follow_height: float = 2.05
@export var position_smoothing: float = 18.0
@export var rotation_smoothing: float = 18.0
@export var base_fov: float = 78.0
@export var maximum_fov: float = 92.0
@export var speed_fov_curve_power: float = 0.82
@export var dynamic_fov_headroom: float = 3.0
@export var look_height: float = 1.32
@export var base_look_ahead: float = 0.85
@export var speed_look_ahead: float = 2.25
@export var smooth_track_speed_shake: float = 0.018
@export var acceleration_punch_gain: float = 0.075
@export var velocity_feed_forward: float = 0.06
@export var trajectory_heading_weight: float = 0.68
@export var bank_roll_scale: float = 0.11
@export var maximum_camera_bank_degrees: float = 4.0
@export var obstruction_mask: int = 2
@export var obstruction_margin: float = 0.28

@onready var _camera: Camera3D = %Camera3D

var target: Node3D
var _landing_kick: float = 0.0
var _boost_punch: float = 0.0
var _air_emphasis: float = 0.0
var _route_punch: float = 0.0
var _contact_kick: float = 0.0
var _racecraft_kick: float = 0.0
var _noise_time: float = 0.0
var _noise := FastNoiseLite.new()
var _obstruction_query := PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.ZERO)
var _obstruction_target_rid := RID()
var _obstruction_position: Vector3 = Vector3.ZERO
var _has_obstruction: bool = false
var _tracking_forward: Vector3 = Vector3.FORWARD
var _previous_planar_speed: float = 0.0
var _acceleration_punch: float = 0.0
var _last_shake_strength: float = 0.0
var _composition_offset_right: float = 0.0
var _reduced_motion: bool = false
var _view_mode: StringName = VIEW_CHASE
var _view_override: StringName = &""
var _distance_scale: float = 1.0
var _height_scale: float = 1.0
var _stiffness_scale: float = 1.0


func _ready() -> void:
	_camera.current = true
	_noise.seed = 7319
	_noise.frequency = 0.72
	_obstruction_query.collision_mask = obstruction_mask


func _physics_process(_delta: float) -> void:
	if target == null:
		return
	var desired_position := _compute_desired_position()
	var ground_up := _get_ground_up()
	var focus_position := target.global_position + ground_up * 1.42
	_obstruction_query.from = focus_position
	_obstruction_query.to = desired_position
	_obstruction_query.collision_mask = obstruction_mask
	var target_body := target as CollisionObject3D
	var target_rid := target_body.get_rid() if target_body != null else RID()
	if target_rid != _obstruction_target_rid:
		_obstruction_target_rid = target_rid
		_obstruction_query.exclude = [target_rid] if target_rid.is_valid() else []
	var result := get_world_3d().direct_space_state.intersect_ray(_obstruction_query)
	_has_obstruction = not result.is_empty()
	if _has_obstruction:
		var hit_position: Vector3 = result.get(&"position", desired_position)
		var hit_normal: Vector3 = result.get(&"normal", Vector3.UP).normalized()
		var obstruction_ray := desired_position - focus_position
		var hit_distance := focus_position.distance_to(hit_position)
		# Ignore only the upward-facing trail immediately beneath the focus point.
		# Nearby rocks, trees, and walls still shorten the camera boom.
		var near_ground_hit := hit_distance < 3.2 and hit_normal.dot(Vector3.UP) > 0.58 and hit_position.y <= focus_position.y + 0.12
		if near_ground_hit or obstruction_ray.length_squared() < 0.01:
			_has_obstruction = false
		else:
			# For very close geometry, scale the clearance down instead of enforcing
			# a boom minimum that could put the camera on the far side of the hit.
			var safe_distance := maxf(hit_distance - minf(obstruction_margin, hit_distance * 0.5), 0.0)
			_obstruction_position = focus_position + obstruction_ray.normalized() * safe_distance


func _process(delta: float) -> void:
	if target == null:
		return
	var rigid_target := target as RigidBody3D
	var velocity := rigid_target.linear_velocity if rigid_target != null else Vector3.ZERO
	var planar_speed := Vector3(velocity.x, 0.0, velocity.z).length()
	var ground_up := _get_ground_up()
	var target_forward := _get_terrain_forward(ground_up, velocity)
	_tracking_forward = target_forward

	var speed_ratio := clampf(planar_speed / 32.0, 0.0, 1.0)
	var forward_acceleration := maxf((planar_speed - _previous_planar_speed) / maxf(delta, 0.0001), 0.0)
	var acceleration_target := clampf(forward_acceleration * acceleration_punch_gain, 0.0, 1.0)
	_acceleration_punch = maxf(
		move_toward(_acceleration_punch, 0.0, delta * 2.8),
		acceleration_target
	)
	_previous_planar_speed = planar_speed
	var desired_position := _obstruction_position if _has_obstruction else _compute_desired_position()
	var position_speed := (
		position_smoothing
		* _profile_float(&"position_response", 1.0)
		* _stiffness_scale
		* (2.8 if _has_obstruction else 1.0)
	)
	var position_weight := 1.0 - exp(-position_speed * delta)
	global_position = global_position.lerp(desired_position, position_weight)

	var bike := target as DirtBikeController
	var terrain_roughness := bike.get_terrain_roughness() if bike != null else 0.0
	var suspension_activity := bike.get_suspension_activity() if bike != null else 0.0
	var rear_slip := bike.get_rear_slip() if bike != null else 0.0
	var grounded := bike.is_grounded() if bike != null else true
	_noise_time += delta * (4.0 + speed_ratio * 15.0 + terrain_roughness * 3.0)
	_landing_kick = move_toward(_landing_kick, 0.0, delta * 3.6)
	_boost_punch = move_toward(_boost_punch, 0.0, delta * 1.8)
	_air_emphasis = move_toward(_air_emphasis, 0.0, delta * 0.42)
	_route_punch = move_toward(_route_punch, 0.0, delta * 1.15)
	_contact_kick = move_toward(_contact_kick, 0.0, delta * 4.8)
	_racecraft_kick = move_toward(_racecraft_kick, 0.0, delta * 3.6)
	var terrain_energy := (
		terrain_roughness * (suspension_activity * 0.72 + speed_ratio * 0.12)
		+ rear_slip * 0.16
	) if grounded else 0.0
	var shake_strength := (
		terrain_energy * 0.065
		+ speed_ratio * speed_ratio * smooth_track_speed_shake
		+ _landing_kick * 0.14
		+ _boost_punch * _boost_punch * 0.06
		+ _contact_kick * 0.11
		+ _racecraft_kick * 0.065
	)
	if _reduced_motion:
		shake_strength *= REDUCED_SHAKE_SCALE
	_last_shake_strength = shake_strength
	var shake := Vector3(
		_noise.get_noise_1d(_noise_time) * shake_strength,
		_noise.get_noise_1d(_noise_time + 37.0) * shake_strength,
		0.0
	)
	var look_target := _compute_look_target(target_forward, ground_up, speed_ratio)
	var desired_basis := Basis.looking_at((look_target - global_position).normalized(), Vector3.UP)
	var rotation_weight := 1.0 - exp(
		-rotation_smoothing
		* _profile_float(&"rotation_response", 1.0)
		* _stiffness_scale
		* delta
	)
	global_transform.basis = global_transform.basis.slerp(desired_basis, rotation_weight)
	_camera.position = shake
	var lean_roll := 0.0
	if bike != null and grounded:
		var maximum_camera_bank := (
			deg_to_rad(maximum_camera_bank_degrees)
			* _profile_float(&"bank_scale", 1.0)
		)
		lean_roll = clampf(
			bike.global_transform.basis.x.normalized().dot(ground_up) * bank_roll_scale,
			-maximum_camera_bank,
			maximum_camera_bank
		)
	if _reduced_motion:
		lean_roll *= REDUCED_BANK_SCALE
	var noise_roll := _noise.get_noise_1d(_noise_time + 71.0) * shake_strength * 0.12
	_camera.rotation.z = lerpf(_camera.rotation.z, lean_roll + noise_roll, 1.0 - exp(-8.0 * delta))
	var target_fov := _compute_target_fov(speed_ratio)
	_camera.fov = lerpf(_camera.fov, target_fov, 1.0 - exp(-4.5 * delta))


func snap_to_target() -> void:
	if target == null:
		return
	var ground_up := _get_ground_up()
	var rigid_target := target as RigidBody3D
	var velocity := rigid_target.linear_velocity if rigid_target != null else Vector3.ZERO
	_previous_planar_speed = velocity.slide(Vector3.UP).length()
	_acceleration_punch = 0.0
	_landing_kick = 0.0
	_contact_kick = 0.0
	_racecraft_kick = 0.0
	_camera.position = Vector3.ZERO
	_camera.fov = _effective_base_fov()
	var forward := _get_terrain_forward(ground_up, velocity)
	global_position = _compute_desired_position()
	var speed_ratio := clampf(velocity.slide(Vector3.UP).length() / 32.0, 0.0, 1.0)
	look_at(_compute_look_target(forward, ground_up, speed_ratio), Vector3.UP)


func set_composition_offset_right(meters: float) -> void:
	## Shifts the optical focus without moving the bike or changing its physics.
	## The Garage uses this to give the bike a dedicated hero column; racing uses
	## zero so steering, trajectory look-ahead, and obstruction behavior stay exact.
	_composition_offset_right = clampf(meters, -4.0, 4.0)


func get_composition_offset_right() -> float:
	return _composition_offset_right


func set_view_preferences(
	mode: Variant,
	distance_scale: float = 1.0,
	height_scale: float = 1.0,
	stiffness_scale: float = 1.0,
	snap: bool = true
) -> void:
	var normalized_mode := _normalize_view_mode(mode)
	var next_distance := clampf(distance_scale, 0.75, 1.35)
	var next_height := clampf(height_scale, 0.75, 1.25)
	var next_stiffness := clampf(stiffness_scale, 0.60, 1.50)
	var changed := (
		normalized_mode != _view_mode
		or not is_equal_approx(next_distance, _distance_scale)
		or not is_equal_approx(next_height, _height_scale)
		or not is_equal_approx(next_stiffness, _stiffness_scale)
	)
	_view_mode = normalized_mode
	_distance_scale = next_distance
	_height_scale = next_height
	_stiffness_scale = next_stiffness
	if changed and snap and is_inside_tree() and target != null:
		snap_to_target()


func set_view_override(mode: Variant = &"", snap: bool = true) -> void:
	var raw := String(mode).strip_edges().to_upper()
	var next_override := &"" if raw.is_empty() else _normalize_view_mode(raw)
	if next_override == _view_override:
		return
	_view_override = next_override
	if snap and is_inside_tree() and target != null:
		snap_to_target()


func cycle_view_mode() -> StringName:
	var index := VIEW_MODES.find(_view_mode)
	_view_mode = VIEW_MODES[(maxi(index, 0) + 1) % VIEW_MODES.size()]
	_view_override = &""
	if is_inside_tree() and target != null:
		snap_to_target()
	return _view_mode


func get_view_mode() -> StringName:
	return _view_mode


func get_effective_view_mode() -> StringName:
	return _view_override if not _view_override.is_empty() else _view_mode


func get_view_label() -> String:
	return str(_active_profile().get(&"label", "CHASE"))


func get_view_preferences_snapshot() -> Dictionary:
	return {
		&"mode": _view_mode,
		&"effective_mode": get_effective_view_mode(),
		&"label": get_view_label(),
		&"override": _view_override,
		&"distance_scale": _distance_scale,
		&"height_scale": _height_scale,
		&"stiffness_scale": _stiffness_scale,
		&"follow_distance": _effective_follow_distance(),
		&"follow_height": _effective_follow_height(),
		&"look_height": _profile_float(&"look_height", look_height),
		&"base_fov": _effective_base_fov(),
		&"maximum_fov": _effective_maximum_fov(),
	}


func set_reduced_motion(enabled: bool) -> void:
	if _reduced_motion == enabled:
		return
	_reduced_motion = enabled
	if not _reduced_motion:
		return
	# Applying the preference must settle any already-running impulse instead of
	# waiting for its normal decay. Core framing and obstruction avoidance remain.
	_landing_kick = 0.0
	_boost_punch = 0.0
	_air_emphasis = 0.0
	_route_punch = 0.0
	_contact_kick = 0.0
	_racecraft_kick = 0.0
	_acceleration_punch = 0.0
	_last_shake_strength = 0.0
	if _camera != null:
		_camera.position = Vector3.ZERO
		_camera.rotation.z = 0.0
		var effective_base := _effective_base_fov()
		_camera.fov = clampf(_camera.fov, effective_base, effective_base + REDUCED_SPEED_FOV_DELTA)


func is_reduced_motion_enabled() -> bool:
	return _reduced_motion


func get_motion_accessibility_snapshot() -> Dictionary:
	var high_speed_fov := _compute_target_fov(1.0)
	return {
		&"reduced_motion": _reduced_motion,
		&"shake_scale": REDUCED_SHAKE_SCALE if _reduced_motion else 1.0,
		&"bank_scale": REDUCED_BANK_SCALE if _reduced_motion else 1.0,
		&"impulse_scale": REDUCED_IMPULSE_SCALE if _reduced_motion else 1.0,
		&"dynamic_position_scale": REDUCED_DYNAMIC_POSITION_SCALE if _reduced_motion else 1.0,
		&"look_ahead_scale": REDUCED_LOOK_AHEAD_SCALE if _reduced_motion else 1.0,
		&"high_speed_fov": high_speed_fov,
		&"speed_fov_delta": maxf(high_speed_fov - _effective_base_fov(), 0.0),
		&"camera_offset": _camera.position if _camera != null else Vector3.ZERO,
		&"camera_bank_radians": _camera.rotation.z if _camera != null else 0.0,
		&"last_shake_strength": _last_shake_strength,
		&"racecraft_kick": _racecraft_kick,
	}


func _compute_look_target(target_forward: Vector3, ground_up: Vector3, speed_ratio: float) -> Vector3:
	var composition_right := target_forward.cross(ground_up).normalized()
	var look_ahead_scale := REDUCED_LOOK_AHEAD_SCALE if _reduced_motion else 1.0
	var impulse_scale := REDUCED_IMPULSE_SCALE if _reduced_motion else 1.0
	return (
		target.global_position
		+ target_forward * (
			_profile_float(&"base_look_ahead", base_look_ahead)
			+ clampf(speed_ratio, 0.0, 1.0)
			* _profile_float(&"speed_look_ahead", speed_look_ahead)
			* look_ahead_scale
		)
		+ ground_up * (_profile_float(&"look_height", look_height) - _landing_kick * 0.3 * impulse_scale)
		+ composition_right * _composition_offset_right
	)


func _compute_target_fov(speed_ratio: float) -> float:
	var effective_base := _effective_base_fov()
	var effective_maximum := _effective_maximum_fov()
	if _reduced_motion:
		var reduced_ceiling := minf(maxf(effective_maximum, effective_base), effective_base + REDUCED_SPEED_FOV_DELTA)
		return lerpf(effective_base, reduced_ceiling, smoothstep(0.0, 1.0, clampf(speed_ratio, 0.0, 1.0)))
	# Normal speed uses most of the optical range while reserving a narrow band
	# for acceleration, boost, and route punches. This keeps those tactile cues
	# without returning to the distorted 100+ degree presentation.
	var safe_maximum := maxf(effective_maximum, effective_base)
	var safe_headroom := clampf(dynamic_fov_headroom, 0.0, safe_maximum - effective_base)
	var cruise_ceiling := safe_maximum - safe_headroom
	var fov_speed_ratio := pow(clampf(speed_ratio, 0.0, 1.0), speed_fov_curve_power)
	return clampf(
		lerpf(effective_base, cruise_ceiling, fov_speed_ratio)
		+ _acceleration_punch * 1.4
		+ _boost_punch * 3.0
		+ _route_punch * 1.5
		- _air_emphasis * 1.4,
		maxf(effective_base - 2.0, 1.0),
		safe_maximum
	)


func _compute_desired_position() -> Vector3:
	if target == null:
		return global_position
	var rigid_target := target as RigidBody3D
	var velocity := rigid_target.linear_velocity if rigid_target != null else Vector3.ZERO
	var planar_speed := Vector3(velocity.x, 0.0, velocity.z).length()
	var speed_ratio := clampf(planar_speed / 32.0, 0.0, 1.0)
	var ground_up := _get_ground_up()
	var terrain_forward := _get_terrain_forward(ground_up, velocity)
	var flat_forward := terrain_forward
	flat_forward.y = 0.0
	if flat_forward.length_squared() < 0.1:
		flat_forward = Vector3.FORWARD
	flat_forward = flat_forward.normalized()
	var chase_forward := (flat_forward * 0.62 + terrain_forward * 0.38).normalized()
	var camera_up := Vector3.UP.slerp(ground_up, 0.22).normalized()
	var mode_dynamic_scale := _profile_float(&"dynamic_scale", 1.0)
	var dynamic_scale := (
		REDUCED_DYNAMIC_POSITION_SCALE * mode_dynamic_scale
		if _reduced_motion else mode_dynamic_scale
	)
	var impulse_scale := REDUCED_IMPULSE_SCALE if _reduced_motion else 1.0
	var dynamic_distance := (
		_effective_follow_distance()
		+ speed_ratio * 0.35 * dynamic_scale
		+ (_acceleration_punch * 0.22 + _air_emphasis * 0.55 + _route_punch * 0.35) * impulse_scale
	)
	var feed_forward_scale := REDUCED_LOOK_AHEAD_SCALE if _reduced_motion else 1.0
	var predicted_target := target.global_position + velocity * velocity_feed_forward * lerpf(0.35, 1.0, speed_ratio) * feed_forward_scale
	return (
		predicted_target
		- chase_forward * dynamic_distance
		+ camera_up * (_effective_follow_height() + speed_ratio * 0.25 * dynamic_scale + _air_emphasis * 0.28 * impulse_scale)
	)


func _normalize_view_mode(value: Variant) -> StringName:
	var normalized := StringName(String(value).strip_edges().to_upper())
	return normalized if normalized in VIEW_MODES else VIEW_CHASE


func _active_profile() -> Dictionary:
	return VIEW_PROFILES.get(get_effective_view_mode(), VIEW_PROFILES[VIEW_CHASE]) as Dictionary


func _profile_float(key: StringName, fallback: float) -> float:
	return float(_active_profile().get(key, fallback))


func _effective_follow_distance() -> float:
	return _profile_float(&"distance", follow_distance) * _distance_scale


func _effective_follow_height() -> float:
	return _profile_float(&"height", follow_height) * _height_scale


func _effective_base_fov() -> float:
	return clampf(base_fov + _profile_float(&"fov_offset", 0.0), 45.0, 115.0)


func _effective_maximum_fov() -> float:
	return clampf(maximum_fov + _profile_float(&"fov_offset", 0.0), _effective_base_fov(), 120.0)


func _get_ground_up() -> Vector3:
	var bike := target as DirtBikeController
	if bike == null or not bike.is_grounded():
		return Vector3.UP
	var normal := bike.get_ground_normal()
	return normal.normalized() if normal.length_squared() > 0.2 else Vector3.UP


func _get_terrain_forward(ground_up: Vector3, velocity: Vector3) -> Vector3:
	var chassis_forward := -target.global_transform.basis.z
	var terrain_forward := chassis_forward.slide(ground_up)
	if terrain_forward.length_squared() < 0.1:
		terrain_forward = Vector3.FORWARD.slide(ground_up)
	terrain_forward = terrain_forward.normalized()
	var bike := target as DirtBikeController
	if bike != null and bike.is_grounded():
		var travel_forward := velocity.slide(ground_up)
		if travel_forward.length_squared() > 4.0:
			travel_forward = travel_forward.normalized()
			if travel_forward.dot(terrain_forward) > 0.2:
				var planar_speed := velocity.slide(ground_up).length()
				var trajectory_weight := trajectory_heading_weight * smoothstep(3.0, 11.0, planar_speed)
				return terrain_forward.slerp(travel_forward, trajectory_weight).normalized()
		return terrain_forward
	if bike == null or velocity.length_squared() < 4.0:
		return terrain_forward
	var flight_forward := velocity.normalized()
	return (terrain_forward * 0.68 + flight_forward * 0.32).normalized()


func get_tracking_forward() -> Vector3:
	if target == null:
		return _tracking_forward
	var rigid_target := target as RigidBody3D
	var velocity := rigid_target.linear_velocity if rigid_target != null else Vector3.ZERO
	_tracking_forward = _get_terrain_forward(_get_ground_up(), velocity)
	return _tracking_forward


func get_tracking_alignment() -> float:
	if target == null:
		return 1.0
	var ground_up := _get_ground_up()
	var chassis_forward := (-target.global_transform.basis.z).slide(ground_up)
	if chassis_forward.length_squared() < 0.1:
		return 1.0
	return get_tracking_forward().dot(chassis_forward.normalized())


func get_camera_bank_angle() -> float:
	return _camera.rotation.z


func get_camera_fov() -> float:
	return _camera.fov


func get_speed_feedback_strength() -> float:
	return _last_shake_strength


func apply_landing_kick(intensity: float) -> void:
	_landing_kick = maxf(_landing_kick, intensity)


func apply_boost_punch(_flow_remaining: float = 0.0) -> void:
	_boost_punch = 1.0


func begin_airtime() -> void:
	_air_emphasis = 1.0


func apply_route_highlight(_route_name: String) -> void:
	_route_punch = 1.0


func apply_contact_kick(intensity: float) -> void:
	_contact_kick = maxf(_contact_kick, clampf(intensity, 0.0, 1.0))


func apply_racecraft_feedback(kind: StringName, payload: Variant = {}) -> void:
	if kind == &"FLOW_DENIED":
		# Insufficient resource is an input refusal, not a physical bike event.
		# A camera punch here falsely reads as a successful technique activation.
		return
	var intensity := 0.55
	if payload is Dictionary:
		intensity = float((payload as Dictionary).get(&"intensity", (payload as Dictionary).get(&"catch_quality", 0.55)))
	elif payload is float or payload is int:
		intensity = float(payload)
	var kind_scale := 1.0
	match kind:
		&"DAB", &"FLOW_COMPOSE": kind_scale = 0.40
		&"PUMP", &"CLUTCH_POP", &"DRAFT_SLINGSHOT": kind_scale = 0.82
		&"CONTROLLED_SLIDE", &"RUT_RAIL", &"SKILL_LINE": kind_scale = 0.62
		&"BRACE_SAVE", &"ROOST_DEFENSE": kind_scale = 0.72
		_: kind_scale = 0.45
	var reduced_scale := REDUCED_IMPULSE_SCALE if _reduced_motion else 1.0
	_racecraft_kick = maxf(_racecraft_kick, clampf(intensity * kind_scale * reduced_scale, 0.0, 1.0))
