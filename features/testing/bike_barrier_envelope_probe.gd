extends Node
## Targeted visual-footprint regression for the player bike.
## Run with:
## Godot --headless --path . res://features/testing/bike_barrier_envelope_probe.tscn

const BIKE_SCENE := preload("res://entities/bike/bike.tscn")
const FRONT_AXLE_Z: float = -0.594
const REAR_AXLE_Z: float = 0.74329
# The suspension wheel radius is 0.307 m; the rendered tread blocks extend the
# silhouette another 27 mm and are the portion most likely to expose clipping.
const VISUAL_TYRE_RADIUS: float = 0.334
const VISUAL_HANDLEBAR_HALF_WIDTH: float = 0.465


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var world := Node3D.new()
	add_child(world)
	var ground := _add_box_body(
		world,
		"RideableGround",
		Vector3(80.0, 0.5, 80.0),
		Vector3(0.0, -0.25, 0.0)
	)
	ground.set_meta(&"surface", &"PACKED")
	ground.set_meta(&"collision_top_only", true)

	var bike := BIKE_SCENE.instantiate() as DirtBikeController
	world.add_child(bike)
	bike.respawn_at(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.67, 0.0)))
	await _wait_physics_frames(45)

	var chassis_collision := bike.get_node("CollisionShape3D") as CollisionShape3D
	var chassis_capsule := chassis_collision.shape as CapsuleShape3D
	var front_probe := bike.get_node("BarrierFrontEnvelope") as ShapeCast3D
	var rear_probe := bike.get_node("BarrierRearEnvelope") as ShapeCast3D
	var bar_probe := bike.get_node("BarrierHandlebarEnvelope") as ShapeCast3D
	var front_shape := front_probe.shape as SphereShape3D
	var rear_shape := rear_probe.shape as SphereShape3D
	var bar_shape := bar_probe.shape as CapsuleShape3D

	var chassis_half_length := chassis_capsule.height * 0.5
	var chassis_front := chassis_collision.position.z - chassis_half_length
	var chassis_rear := chassis_collision.position.z + chassis_half_length
	var envelope_front := front_probe.position.z - front_shape.radius
	var envelope_rear := rear_probe.position.z + rear_shape.radius
	var envelope_bar_half_width := bar_shape.height * 0.5
	var geometry_passed := (
		is_equal_approx(chassis_capsule.radius, 0.31)
		and is_equal_approx(chassis_capsule.height, 1.197989)
		and chassis_front > FRONT_AXLE_Z - VISUAL_TYRE_RADIUS + 0.40
		and chassis_rear < REAR_AXLE_Z + VISUAL_TYRE_RADIUS - 0.30
		and envelope_front <= FRONT_AXLE_Z - VISUAL_TYRE_RADIUS + 0.001
		and envelope_rear >= REAR_AXLE_Z + VISUAL_TYRE_RADIUS - 0.001
		and envelope_bar_half_width >= VISUAL_HANDLEBAR_HALF_WIDTH - 0.001
	)
	var rideables_ignored := (
		bike.get_barrier_envelope_contact_count() == 0
		and not bool(bike.call(&"_is_course_barrier", ground))
	)

	var barrier := _add_box_body(
		world,
		"CourseContainmentTest",
		Vector3(8.0, 2.4, 0.42),
		Vector3(0.0, 1.0, -5.0)
	)
	barrier.set_meta(&"course_containment", true)
	barrier.add_to_group(&"course_containment")
	var barrier_near_plane_z := barrier.position.z + 0.21
	var barrier_classified := bool(bike.call(&"_is_course_barrier", barrier))

	# Prove the regression is meaningful: the compact chassis capsule does stop
	# the bike, but only after the rendered front tyre has entered the barrier.
	bike.barrier_envelope_enabled = false
	bike.linear_velocity = Vector3(0.0, 0.0, -14.0)
	bike.sleeping = false
	var baseline_minimum_clearance := INF
	for _frame: int in 90:
		await get_tree().physics_frame
		var front_center := bike.global_transform * front_probe.position
		var visual_clearance := front_center.z - VISUAL_TYRE_RADIUS - barrier_near_plane_z
		baseline_minimum_clearance = minf(baseline_minimum_clearance, visual_clearance)

	bike.barrier_envelope_enabled = true
	bike.respawn_at(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.67, 0.0)))
	await _wait_physics_frames(30)
	bike.linear_velocity = Vector3(0.0, 0.0, -14.0)
	bike.sleeping = false
	var minimum_visual_clearance := INF
	var minimum_forward_speed := 14.0
	for _frame: int in 90:
		await get_tree().physics_frame
		var front_center := bike.global_transform * front_probe.position
		var visual_clearance := front_center.z - VISUAL_TYRE_RADIUS - barrier_near_plane_z
		minimum_visual_clearance = minf(minimum_visual_clearance, visual_clearance)
		minimum_forward_speed = minf(minimum_forward_speed, absf(bike.linear_velocity.z))

	var contact_count := bike.get_barrier_envelope_contact_count()
	var head_on_passed := (
		barrier_classified
		and baseline_minimum_clearance <= -0.25
		and contact_count > 0
		and minimum_visual_clearance >= -0.055
		and minimum_forward_speed < 1.5
	)

	# An angled side scrape must cancel only the component entering the wall. If
	# the response removed total velocity, containment would feel sticky and undo
	# the handling improvements this probe is intended to protect.
	var side_barrier := _add_box_body(
		world,
		"CourseContainmentSideTest",
		Vector3(0.42, 2.4, 20.0),
		Vector3(3.0, 1.0, 5.0)
	)
	side_barrier.set_meta(&"course_containment", true)
	side_barrier.add_to_group(&"course_containment")
	var approach_basis := Basis(Vector3.UP, -atan2(6.0, 12.0))
	bike.respawn_at(Transform3D(approach_basis, Vector3(0.0, 0.67, 5.0)))
	await _wait_physics_frames(30)
	bike.linear_velocity = -approach_basis.z * sqrt(180.0)
	bike.sleeping = false
	var side_minimum_clearance := INF
	var side_contact_count := 0
	for _frame: int in 40:
		await get_tree().physics_frame
		var outer_x := -INF
		for probe: ShapeCast3D in [front_probe, rear_probe, bar_probe]:
			outer_x = maxf(outer_x, probe.global_position.x + _shape_support_along(probe, Vector3.RIGHT))
		side_minimum_clearance = minf(side_minimum_clearance, 2.79 - outer_x)
		side_contact_count = bike.get_barrier_envelope_contact_count()
		if side_contact_count > 0 and absf(bike.linear_velocity.x) < 1.5:
			break
	var side_lateral_speed := absf(bike.linear_velocity.x)
	var side_forward_speed := absf(bike.linear_velocity.z)
	var side_scrape_passed := (
		side_contact_count > 0
		and side_minimum_clearance >= -0.055
		and side_lateral_speed < 1.5
		and side_forward_speed > 8.0
	)
	var dynamic_passed := head_on_passed and side_scrape_passed
	var passed := geometry_passed and rideables_ignored and dynamic_passed
	print(
		(
			"BIKE BARRIER ENVELOPE: chassis=%.3f..%.3fm visual=%.3f..%.3fm bars=%.3fm "
			+ "rideables_ignored=%s baseline_clip=%.3fm contacts=%d min_clearance=%.3fm min_forward_speed=%.2fm/s "
			+ "side_contacts=%d side_clearance=%.3fm side_velocity=(%.2f, %.2f)m/s passed=%s"
		)
		% [
			chassis_front,
			chassis_rear,
			envelope_front,
			envelope_rear,
			envelope_bar_half_width,
			str(rideables_ignored),
			baseline_minimum_clearance,
			contact_count,
			minimum_visual_clearance,
			minimum_forward_speed,
			side_contact_count,
			side_minimum_clearance,
			side_lateral_speed,
			side_forward_speed,
			str(passed),
		]
	)
	if not passed:
		push_error(
			"BIKE BARRIER ENVELOPE FAILED: geometry=%s rideables=%s dynamic=%s barrier=%s"
			% [str(geometry_passed), str(rideables_ignored), str(dynamic_passed), str(barrier_classified)]
		)
	world.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if passed else 1)


func _add_box_body(root: Node3D, body_name: String, size: Vector3, position: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = body_name
	body.collision_layer = 2
	body.collision_mask = 1
	body.position = position
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	root.add_child(body)
	return body


func _wait_physics_frames(count: int) -> void:
	for _frame: int in count:
		await get_tree().physics_frame


func _shape_support_along(probe: ShapeCast3D, axis: Vector3) -> float:
	if probe.shape is SphereShape3D:
		return (probe.shape as SphereShape3D).radius
	if probe.shape is CapsuleShape3D:
		var capsule := probe.shape as CapsuleShape3D
		var capsule_axis := probe.global_transform.basis.y.normalized()
		var segment_half_length := maxf(capsule.height * 0.5 - capsule.radius, 0.0)
		return capsule.radius + segment_half_length * absf(capsule_axis.dot(axis))
	return 0.0
