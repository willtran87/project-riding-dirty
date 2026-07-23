extends Node3D
class_name DiscoveryController
## Local collection manager, elapsed-time medals, and nearest-salvage compass projection.

signal hud_updated(elapsed_usec: int, current: int, total: int, compass_angle: float, distance: float)

const SPAWN_TRANSFORM := Transform3D(Basis.IDENTITY, Vector3(0.0, 1.4, 31.0))
const SIMULATION_CLOCK_SCRIPT := preload("res://common/simulation_clock.gd")
const PICKUP_POSITIONS: Array[Vector3] = [
	Vector3(-38.0, 1.25, 23.0),
	Vector3(24.0, 1.25, 29.0),
	Vector3(47.0, 1.25, 30.0),
	Vector3(42.0, 1.25, -28.0),
	Vector3(12.0, 1.25, -57.0),
	Vector3(-42.0, 1.25, -28.0),
]

var bike: DirtBikeController
var ghost: GhostController
var active: bool = false
var collected_count: int = 0

var _run_clock: SimulationClock = SIMULATION_CLOCK_SCRIPT.new()
var _pickups: Array[Area3D] = []
var _attempt_context: Dictionary = {}
var _pending_submission: Dictionary = {}


func _physics_process(delta: float) -> void:
	if not active or bike == null:
		return
	var elapsed_usec := _run_clock.advance(delta)
	var nearest: Area3D = _find_nearest_pickup()
	var compass_angle := 0.0
	var distance := 0.0
	if nearest != null:
		var to_target: Vector3 = nearest.global_position - bike.global_position
		to_target.y = 0.0
		distance = to_target.length()
		var forward := -bike.global_transform.basis.z
		forward.y = 0.0
		if to_target.length_squared() > 0.01 and forward.length_squared() > 0.01:
			to_target = to_target.normalized()
			forward = forward.normalized()
			compass_angle = atan2(forward.cross(to_target).y, forward.dot(to_target))
	hud_updated.emit(elapsed_usec, collected_count, PICKUP_POSITIONS.size(), compass_angle, distance)


func initialize(player_bike: DirtBikeController, ghost_controller: GhostController) -> void:
	bike = player_bike
	ghost = ghost_controller
	enter_waiting()


func start_hunt() -> void:
	if bike == null or ghost == null:
		return
	# Preserve a failed durable settlement until the rider explicitly retries it.
	# Starting a new hunt first would overwrite the Profile run authority and turn
	# a recoverable save failure into permanent progress loss.
	if not _pending_submission.is_empty():
		# Re-establish Main's run-keyed settlement baseline without restarting the
		# physical hunt or its run-scoped RideDirector systems.
		EventBus.activity_attempt_started.emit(_attempt_context.duplicate(true))
		_settle_pending_submission()
		return
	var attempt: Dictionary = Profile.begin_activity_run(&"DISCOVERY")
	_attempt_context = attempt.duplicate(true)
	if not bool(attempt.get(&"accepted", false)):
		active = false
		bike.set_controls_enabled(false)
		EventBus.activity_attempt_started.emit(_attempt_context.duplicate(true))
		EventBus.activity_completed.emit(_begin_failure_receipt(attempt))
		return
	_cleanup_pickups()
	active = true
	collected_count = 0
	_run_clock.reset()
	bike.respawn_at(SPAWN_TRANSFORM)
	bike.set_motion_locked(false)
	bike.set_controls_enabled(true)
	ghost.cancel_run()
	_spawn_pickups()
	EventBus.activity_started.emit(&"DISCOVERY")
	EventBus.activity_attempt_started.emit(_attempt_context.duplicate(true))
	EventBus.discovery_progress_changed.emit(0, PICKUP_POSITIONS.size())


func enter_waiting() -> void:
	active = false
	if _pending_submission.is_empty() and Profile.has_method(&"abandon_activity_run"):
		Profile.call(
			&"abandon_activity_run", &"DISCOVERY", str(_attempt_context.get(&"run_id", ""))
		)
	_cleanup_pickups()
	if bike != null:
		bike.set_controls_enabled(false)
	if ghost != null:
		ghost.cancel_run()


func get_pickup_positions() -> Array[Vector3]:
	return PICKUP_POSITIONS.duplicate()


func get_active_pickup_count() -> int:
	var count := 0
	for pickup: Area3D in _pickups:
		if is_instance_valid(pickup) and not bool(pickup.get_meta(&"collected", false)):
			count += 1
	return count


func get_activity_attempt_context() -> Dictionary:
	return _attempt_context.duplicate(true)


func has_pending_settlement() -> bool:
	return not _pending_submission.is_empty()


func get_elapsed_usec() -> int:
	return _run_clock.elapsed_usec


func _spawn_pickups() -> void:
	for index: int in PICKUP_POSITIONS.size():
		var pickup := Area3D.new()
		pickup.name = "Salvage%02d" % index
		pickup.collision_layer = 0
		pickup.collision_mask = 1
		pickup.monitoring = true
		pickup.set_meta(&"collected", false)
		pickup.position = PICKUP_POSITIONS[index]
		pickup.add_to_group(&"discovery_pickup")
		_build_pickup(pickup)
		pickup.body_entered.connect(_on_pickup_body_entered.bind(index, pickup))
		add_child(pickup)
		_pickups.append(pickup)


func _cleanup_pickups() -> void:
	for pickup: Area3D in _pickups:
		if is_instance_valid(pickup):
			pickup.queue_free()
	_pickups.clear()


func _find_nearest_pickup() -> Area3D:
	var nearest: Area3D
	var nearest_distance := INF
	for pickup: Area3D in _pickups:
		if not is_instance_valid(pickup) or bool(pickup.get_meta(&"collected", false)):
			continue
		var distance := bike.global_position.distance_squared_to(pickup.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = pickup
	return nearest


func _on_pickup_body_entered(body: Node3D, _pickup_id: int, pickup: Area3D) -> void:
	if not active or not body.is_in_group(&"player") or bool(pickup.get_meta(&"collected", false)):
		return
	pickup.set_meta(&"collected", true)
	pickup.set_deferred(&"monitoring", false)
	_play_collection_juice(pickup)
	collected_count += 1
	EventBus.discovery_progress_changed.emit(collected_count, PICKUP_POSITIONS.size())
	if collected_count >= PICKUP_POSITIONS.size():
		_finish_hunt()


func _build_pickup(pickup: Area3D) -> void:
	var shape := SphereShape3D.new()
	shape.radius = 1.25
	var collision := CollisionShape3D.new()
	collision.shape = shape
	pickup.add_child(collision)

	var visual_root := Node3D.new()
	visual_root.name = "VisualRoot"
	pickup.add_child(visual_root)
	var amber := _pickup_material(Color("ffad2f"), Color("b95c12"), 1.4)
	var dark := _pickup_material(Color("20272b"), Color.BLACK, 0.0)
	dark.metallic = 0.55
	_add_pickup_box(visual_root, Vector3(0.72, 0.88, 0.42), Vector3.ZERO, amber)
	_add_pickup_box(visual_root, Vector3(0.38, 0.2, 0.45), Vector3(0.0, 0.52, 0.0), dark)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.72
	ring.outer_radius = 0.78
	ring.rings = 20
	ring.ring_segments = 6
	var ring_mesh := MeshInstance3D.new()
	ring_mesh.mesh = ring
	ring_mesh.rotation.x = PI * 0.5
	ring_mesh.material_override = _pickup_material(Color("60dbff"), Color("45cfff"), 2.8, true)
	visual_root.add_child(ring_mesh)
	var light := OmniLight3D.new()
	light.light_color = Color("51d5ff")
	light.light_energy = 1.8
	light.omni_range = 4.0
	light.shadow_enabled = false
	visual_root.add_child(light)


func _add_pickup_box(parent: Node3D, size: Vector3, position: Vector3, material: StandardMaterial3D) -> void:
	var box := BoxMesh.new()
	box.size = size
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = box
	mesh_instance.position = position
	mesh_instance.material_override = material
	parent.add_child(mesh_instance)


func _pickup_material(color: Color, emission: Color, energy: float, unshaded: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.42
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if unshaded else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	if energy > 0.0:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = energy
	return material


func _play_collection_juice(pickup: Area3D) -> void:
	var particles := GPUParticles3D.new()
	particles.amount = 22
	particles.lifetime = 0.55
	particles.one_shot = true
	particles.explosiveness = 0.95
	particles.local_coords = false
	var process_material := ParticleProcessMaterial.new()
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process_material.emission_sphere_radius = 0.25
	process_material.direction = Vector3.UP
	process_material.spread = 180.0
	process_material.initial_velocity_min = 2.0
	process_material.initial_velocity_max = 5.0
	process_material.gravity = Vector3(0.0, -5.0, 0.0)
	process_material.color = Color("5ee1ff")
	particles.process_material = process_material
	var spark := SphereMesh.new()
	spark.radius = 0.055
	spark.height = 0.11
	spark.radial_segments = 6
	spark.rings = 3
	spark.material = _pickup_material(Color("c6f6ff"), Color("60dbff"), 2.0, true)
	particles.draw_pass_1 = spark
	pickup.add_child(particles)
	particles.restart()
	var visual := pickup.get_node_or_null("VisualRoot") as Node3D
	if visual == null:
		pickup.queue_free()
		return
	var tween := pickup.create_tween()
	tween.set_parallel(true)
	tween.tween_property(visual, "scale", Vector3.ONE * 1.7, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(visual, "rotation:y", visual.rotation.y + TAU, 0.5)
	tween.chain().tween_property(visual, "scale", Vector3.ZERO, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(pickup.queue_free).set_delay(0.62)


func _finish_hunt() -> void:
	if not active:
		return
	active = false
	bike.set_controls_enabled(false)
	_pending_submission = {
		&"schema_version": 1,
		&"activity_id": &"DISCOVERY",
		&"run_id": str(_attempt_context.get(&"run_id", "")),
		&"result_value": _run_clock.elapsed_usec,
	}
	_settle_pending_submission()


func _settle_pending_submission() -> Dictionary:
	if _pending_submission.is_empty():
		return {}
	var submission := _pending_submission.duplicate(true)
	var receipt: Dictionary = Profile.record_activity_result(submission)
	receipt = _normalize_receipt(receipt, submission)
	var terminal := (
		bool(receipt.get(&"accepted", false))
		or bool(receipt.get(&"duplicate", false))
		or not bool(receipt.get(&"retryable", false))
	)
	if terminal:
		_pending_submission.clear()
	EventBus.activity_completed.emit(receipt.duplicate(true))
	return receipt


func _normalize_receipt(receipt: Dictionary, submission: Dictionary) -> Dictionary:
	var normalized := receipt.duplicate(true)
	normalized[&"schema_version"] = int(normalized.get(&"schema_version", submission.get(&"schema_version", 1)))
	normalized[&"activity_id"] = StringName(normalized.get(
		&"activity_id", submission.get(&"activity_id", &"DISCOVERY")
	))
	normalized[&"run_id"] = str(normalized.get(&"run_id", submission.get(&"run_id", "")))
	normalized[&"result_value"] = int(normalized.get(&"result_value", submission.get(&"result_value", 0)))
	normalized[&"accepted"] = bool(normalized.get(&"accepted", false))
	normalized[&"duplicate"] = bool(normalized.get(&"duplicate", false))
	normalized[&"durable"] = bool(normalized.get(&"durable", false))
	normalized[&"retryable"] = bool(normalized.get(&"retryable", false))
	normalized[&"reason"] = StringName(normalized.get(&"reason", &"UNKNOWN"))
	var rewards_value: Variant = normalized.get(&"rewards_granted", {})
	normalized[&"rewards_granted"] = (
		(rewards_value as Dictionary).duplicate(true)
		if rewards_value is Dictionary
		else {&"cash": 0, &"reputation": 0}
	)
	return normalized


func _begin_failure_receipt(attempt: Dictionary) -> Dictionary:
	return {
		&"accepted": false,
		&"duplicate": false,
		&"durable": false,
		&"retryable": bool(attempt.get(&"retryable", false)),
		&"reason": StringName(attempt.get(&"reason", &"RUN_START_FAILED")),
		&"schema_version": int(attempt.get(&"schema_version", 1)),
		&"activity_id": &"DISCOVERY",
		&"run_id": str(attempt.get(&"run_id", "")),
		&"result_value": 0,
		&"rewards_granted": {&"cash": 0, &"reputation": 0},
	}
