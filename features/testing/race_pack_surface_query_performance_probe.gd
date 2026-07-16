extends Node3D
## Microbenchmark and contract check for the pack's reusable support-ray
## descriptor. The physics query itself remains identical in both cases.

const ITERATIONS := 40000


func _ready() -> void:
	var surface := StaticBody3D.new()
	surface.collision_layer = 2
	surface.collision_mask = 0
	add_child(surface)
	var shape := BoxShape3D.new()
	shape.size = Vector3(8.0, 0.2, 8.0)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = -0.1
	surface.add_child(collision)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var world := get_world_3d()
	var space := world.direct_space_state
	var ray_start := Vector3.UP * RacePack.SURFACE_RAY_HEIGHT
	var ray_end := Vector3.DOWN * RacePack.SURFACE_RAY_DEPTH
	var reusable := PhysicsRayQueryParameters3D.create(ray_start, ray_end, 2)
	reusable.collide_with_areas = false
	reusable.collide_with_bodies = true

	var cached_hits := 0
	var cached_begin := Time.get_ticks_usec()
	for _iteration: int in ITERATIONS:
		reusable.from = ray_start
		reusable.to = ray_end
		reusable.collision_mask = 2
		if not space.intersect_ray(reusable).is_empty():
			cached_hits += 1
	var cached_usec := Time.get_ticks_usec() - cached_begin

	var fresh_hits := 0
	var fresh_begin := Time.get_ticks_usec()
	for _iteration: int in ITERATIONS:
		var fresh := PhysicsRayQueryParameters3D.create(ray_start, ray_end, 2)
		fresh.collide_with_areas = false
		fresh.collide_with_bodies = true
		if not space.intersect_ray(fresh).is_empty():
			fresh_hits += 1
	var fresh_usec := Time.get_ticks_usec() - fresh_begin

	var pack := RacePack.new()
	add_child(pack)
	pack.set_physics_process(false)
	var descriptor_before := (pack.get("_surface_query") as PhysicsRayQueryParameters3D).get_instance_id()
	for _iteration: int in 120:
		pack.call(&"_sample_ride_surface", Vector3.ZERO)
	var descriptor_after := (pack.get("_surface_query") as PhysicsRayQueryParameters3D).get_instance_id()
	var pack_queries := int(pack.get("_surface_queries_this_tick"))
	var passed := (
		cached_hits == ITERATIONS
		and fresh_hits == ITERATIONS
		and descriptor_before == descriptor_after
		and pack_queries == 120
		and cached_usec < fresh_usec
	)
	print("PACK SURFACE QUERY PERFORMANCE: rays=%d cached_usec=%d fresh_usec=%d speedup=%.2fx descriptor_stable=%s pack_queries=%d passed=%s" % [
		ITERATIONS,
		cached_usec,
		fresh_usec,
		float(fresh_usec) / maxf(float(cached_usec), 1.0),
		str(descriptor_before == descriptor_after),
		pack_queries,
		str(passed),
	])
	if not passed:
		push_error("PACK SURFACE QUERY PERFORMANCE: support-ray reuse contract failed.")
	get_tree().quit(0 if passed else 1)
