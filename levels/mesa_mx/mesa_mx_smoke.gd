extends Node
## Isolated structural regression for the generated Mesa MX level.

const MESA_SCENE := preload("res://levels/mesa_mx/mesa_mx.tscn")


func _ready() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var failures: Array[String] = []
	var level := MESA_SCENE.instantiate()
	add_child(level)
	await get_tree().process_frame

	var world_route: PackedVector3Array = level.get_authoritative_route_world()
	if world_route.size() < 500:
		failures.append("authoritative route is unexpectedly sparse (%d samples)" % world_route.size())
	if world_route.size() >= 2 and world_route[0].distance_to(world_route[-1]) > 0.02:
		failures.append("authoritative route is not closed")
	if level.global_position.distance_to(CourseCatalog.MESA_MX_ORIGIN) > 0.01:
		failures.append("scene origin does not match CourseCatalog.MESA_MX_ORIGIN")

	var ribbon := level.get_node_or_null("MesaAuthoritativeRaceRibbon")
	if ribbon == null:
		failures.append("authoritative ribbon is missing")
	else:
		if not bool(ribbon.get_meta(&"authoritative_track_surface", false)):
			failures.append("ribbon is not tagged authoritative")
		if StringName(ribbon.get_meta(&"authoritative_track_id", &"")) != CourseCatalog.MESA_MX_ID:
			failures.append("ribbon authoritative track id is wrong")
		if int(ribbon.get_meta(&"visual_centerline_size", 0)) != world_route.size():
			failures.append("rendered ribbon sample count differs from authoritative route")
		if int(ribbon.get_meta(&"collision_centerline_size", 0)) != world_route.size():
			failures.append("collision ribbon sample count differs from authoritative route")
		if int(ribbon.get_meta(&"collision_shape_count", 0)) != 1:
			failures.append("ribbon collision is not one welded shape")

	var barriers := level.get_node_or_null("VisibleContainmentBarriers")
	if barriers == null or int(barriers.get_meta(&"barrier_pair_count", 0)) < 60:
		failures.append("continuous visible containment was not generated")
	elif not _all_barriers_visible_and_colliding(barriers):
		failures.append("a containment collider has no matching visible mesh")

	var gates := level.get_node_or_null("RouteDerivedCheckpointGates")
	if gates == null or int(gates.get_meta(&"gate_count", 0)) != 10:
		failures.append("expected ten route-derived intermediate gates")

	var ground := level.get_node_or_null("MesaGradedGroundCollision")
	if ground == null or ground.find_children("*", "CollisionShape3D", true, false).is_empty():
		failures.append("graded surrounding ground has no collision")

	var minimum_centerline_clearance := INF
	for index: int in range(0, world_route.size(), 11):
		var local_point: Vector3 = level.to_local(world_route[index])
		var ground_height := float(level.call(&"_terrain_height_at", local_point.x, local_point.z))
		minimum_centerline_clearance = minf(minimum_centerline_clearance, local_point.y - ground_height)
	if minimum_centerline_clearance < 3.2:
		failures.append("terrain clearance under the route fell to %.3f m" % minimum_centerline_clearance)

	var local_route := CourseCatalog.get_local_riding_points(CourseCatalog.MESA_MX_ID)
	var track_width := CourseCatalog.get_track_width(CourseCatalog.MESA_MX_ID)
	var surface_config: Dictionary = level.call(&"_surface_config")
	var frames: Array[Dictionary] = CourseSurfaceBuilder._build_frames(local_route, track_width, surface_config)
	var collision_profile: Dictionary = CourseSurfaceBuilder._collision_track_profile(track_width, surface_config)
	var outer_offset := track_width * 0.5 + float(surface_config[&"shoulder_width"])
	var minimum_shoulder_clearance := INF
	var maximum_route_step := 0.0
	for index: int in range(0, frames.size(), 7):
		var frame: Dictionary = frames[index]
		for side: float in [-1.0, 1.0]:
			var offset := outer_offset * side
			var profile_height := CourseSurfaceBuilder._profile_height_at(frame, offset, track_width, collision_profile)
			var surface_point: Vector3 = frame[&"position"] + (frame[&"right"] as Vector3) * offset + (frame[&"up"] as Vector3) * profile_height
			var ground_height := float(level.call(&"_terrain_height_at", surface_point.x, surface_point.z))
			minimum_shoulder_clearance = minf(minimum_shoulder_clearance, surface_point.y - ground_height)
		if index + 1 < local_route.size():
			maximum_route_step = maxf(maximum_route_step, local_route[index].distance_to(local_route[index + 1]))
	if minimum_shoulder_clearance < 0.28:
		failures.append("terrain approaches a banked shoulder within %.3f m" % minimum_shoulder_clearance)
	if maximum_route_step > 2.25:
		failures.append("authoritative route has a %.3f m sampling gap" % maximum_route_step)

	if failures.is_empty():
		print(
			"MESA_MX_SMOKE PASS samples=%d barrier_pairs=%d gates=10 center_clearance=%.3f shoulder_clearance=%.3f max_route_step=%.3f" % [
				world_route.size(),
				int(barriers.get_meta(&"barrier_pair_count", 0)),
				minimum_centerline_clearance,
				minimum_shoulder_clearance,
				maximum_route_step,
			]
		)
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("MESA_MX_SMOKE: %s" % failure)
	get_tree().quit(1)


func _all_barriers_visible_and_colliding(barriers: Node) -> bool:
	for child: Node in barriers.get_children():
		if child is not StaticBody3D:
			continue
		if child.find_children("*", "MeshInstance3D", true, false).is_empty():
			return false
		if child.find_children("*", "CollisionShape3D", true, false).is_empty():
			return false
	return true
