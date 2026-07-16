extends Node3D
## Read-only audit of player-blocking collision surfaces across the full route.
##
## Run against source or an exported PCK.  It reports the authored longitudinal
## and lateral footprint of every route-authored additive collision overlay;
## the separate freestyle arena is deliberately outside this audit, and the
## opponent pack itself has no PhysicsBody3D nodes.

const QUARRY_SCENE := preload("res://levels/quarry/quarry.tscn")


func _ready() -> void:
	var quarry := QUARRY_SCENE.instantiate() as Node3D
	add_child(quarry)
	for _frame: int in 3:
		await get_tree().physics_frame

	var route := CourseCatalog.get_local_riding_points(CourseCatalog.QUARRY_ID)
	var chainages := _route_chainages(route)
	var route_length := float(chainages[-1])
	var checkpoint_ratios := CourseCatalog.get_checkpoint_progress_ratios(CourseCatalog.QUARRY_ID)
	var checkpoint_chainages := PackedFloat32Array()
	for ratio: float in checkpoint_ratios:
		checkpoint_chainages.append(ratio * route_length)
	print("GATE8 COLLISION DIVERGENCE: route=%.3fm gate7=%.3fm gate8=%.3fm gate9=%.3fm gate10=%.3fm gate11=%.3fm" % [
		route_length,
		float(checkpoint_chainages[6]), float(checkpoint_chainages[7]),
		float(checkpoint_chainages[8]), float(checkpoint_chainages[9]),
		float(checkpoint_chainages[10]),
	])

	# Begin after the endpoint taper and stop just before the finish/apron join.
	# The previous Gate-8-only range could pass while all fourteen early Quarry
	# overlays still hid the road at the player's elapsed-time midpoint.
	var outgoing_start := 3.0
	var outgoing_end := route_length - 2.0
	var overlay_count := 0
	for candidate: Node in quarry.find_children("*", "StaticBody3D", true, false):
		var body := candidate as StaticBody3D
		# Official ribbon overlays carry a route index. Freestyle hub wedges only
		# share the generic ramp metadata and must not be mistaken for course hills.
		if not body.has_meta(&"ramp_height") or not body.has_meta(&"route_index"):
			continue
		var route_index := clampi(int(body.get_meta(&"route_index", -1)), 0, route.size() - 1)
		var center_chainage := float(chainages[route_index])
		var length := float(body.get_meta(&"ramp_length", 0.0))
		var width := float(body.get_meta(&"ramp_width", 0.0))
		var lateral_offset := float(body.get_meta(&"lateral_offset", 0.0))
		var start_chainage := center_chainage - length * 0.5
		var end_chainage := center_chainage + length * 0.5
		if end_chainage < outgoing_start or start_chainage > outgoing_end:
			continue
		overlay_count += 1
		print("GATE8 PLAYER COLLIDER: node=%s layer=%d mask=%d center=%.3fm extent=%.3f..%.3fm delta_after_gate8=%.3f..%.3fm lane=%.3f..%.3fm width=%.3fm height=%.3fm bypass=%.3fm" % [
			String(body.name), body.collision_layer, body.collision_mask,
			center_chainage, start_chainage, end_chainage,
			start_chainage - outgoing_start, end_chainage - outgoing_start,
			lateral_offset - width * 0.5, lateral_offset + width * 0.5,
			width, float(body.get_meta(&"ramp_height", 0.0)),
			float(body.get_meta(&"clear_bypass_width", 0.0)),
		])
	var topology_result := _audit_full_player_corridor(
		quarry, route, chainages, outgoing_start, outgoing_end
	)
	var presented_heading_result := _audit_hud_gate8_presented_heading(
		quarry, route, chainages, checkpoint_chainages
	)

	var race_pack := RacePack.new()
	add_child(race_pack)
	await get_tree().process_frame
	var physics_bodies := race_pack.find_children("*", "PhysicsBody3D", true, false)
	var collision_shapes := race_pack.find_children("*", "CollisionShape3D", true, false)
	print("GATE8 NPC COLLISION MODEL: physics_bodies=%d collision_shapes=%d root_type=%s surface_ray_height=%.1f surface_ray_depth=%.1f" % [
		physics_bodies.size(), collision_shapes.size(), race_pack.get_class(),
		RacePack.SURFACE_RAY_HEIGHT, RacePack.SURFACE_RAY_DEPTH,
	])
	var npc_is_collisionless := physics_bodies.is_empty() and collision_shapes.is_empty()
	var passed := (
		overlay_count == 0
		and bool(topology_result[&"passed"])
		and bool(presented_heading_result[&"passed"])
		and npc_is_collisionless
	)
	print("QUARRY FULL-ROUTE COLLISION RESULT: overlays=%d player_layer=1 player_mask=2 full_corridor_clear=%s gate8_heading_clear=%s npc_collisionless=%s passed=%s" % [
		overlay_count, str(topology_result[&"passed"]), str(presented_heading_result[&"passed"]),
		str(npc_is_collisionless), str(passed),
	])
	get_tree().quit(0 if passed else 1)


func _audit_full_player_corridor(
	quarry: Node3D,
	route: PackedVector3Array,
	chainages: PackedFloat32Array,
	start_chainage: float,
	end_chainage: float
) -> Dictionary:
	# Metadata-only checks missed legacy geometry when it was renamed or baked into
	# another collider. Sweep the actual topmost layer-2 body across the complete
	# 24 m player ribbon. Any hill, terrain slab, prop, or overlay above the welded
	# road becomes the first hit and fails closed.
	var expected_surface := quarry.find_child("ContinuousRideableCollision", true, false) as StaticBody3D
	if expected_surface == null:
		print("GATE8 FULL CORRIDOR: expected_surface_missing=true passed=false")
		return {&"passed": false}
	var space := get_world_3d().direct_space_state
	var lanes := PackedFloat32Array([-11.5, -8.0, -4.0, 0.0, 4.0, 8.0, 11.5])
	var samples := 0
	var missing := 0
	var unexpected := 0
	var unexpected_names := PackedStringArray()
	for route_index: int in route.size():
		var chainage := float(chainages[route_index])
		if chainage < start_chainage or chainage > end_chainage:
			continue
		var tangent := CourseSpline.tangent_at(route, route_index)
		var right := tangent.cross(Vector3.UP)
		if right.length_squared() <= 0.001:
			right = Vector3.RIGHT
		else:
			right = right.normalized()
		for lane: float in lanes:
			var sample := route[route_index] + right * lane
			var query := PhysicsRayQueryParameters3D.create(
				sample + Vector3.UP * 16.0,
				sample + Vector3.DOWN * 6.0,
				2
			)
			query.collide_with_areas = false
			query.collide_with_bodies = true
			query.hit_back_faces = true
			var hit := space.intersect_ray(query)
			samples += 1
			if hit.is_empty():
				missing += 1
				continue
			var collider := hit.get(&"collider") as CollisionObject3D
			if collider != expected_surface:
				unexpected += 1
				var collider_name := "<invalid>" if collider == null else String(collider.get_path())
				if collider_name not in unexpected_names:
					unexpected_names.append(collider_name)
	var passed := samples > 0 and missing == 0 and unexpected == 0
	print("GATE8 FULL CORRIDOR: chain=%.3f..%.3fm lanes=%d samples=%d missing=%d unexpected=%d bodies=%s passed=%s" % [
		start_chainage, end_chainage, lanes.size(), samples, missing, unexpected,
		str(unexpected_names), str(passed),
	])
	return {&"passed": passed, &"samples": samples, &"missing": missing, &"unexpected": unexpected}


func _audit_hud_gate8_presented_heading(
	quarry: Node3D,
	route: PackedVector3Array,
	chainages: PackedFloat32Array,
	checkpoint_chainages: PackedFloat32Array
) -> Dictionary:
	# The old downward-only audit accepted a perfectly valid ribbon even though
	# HUD Gate 8 began with a hidden 63-degree turn. A player maintaining the
	# presented heading hit the outside containment wall in 36-54 m while the
	# collisionless NPC pack snapped around the spline. Sweep the shipped chassis
	# envelope through the central pack lanes so this failure cannot return.
	const CLEAR_DISTANCE := 70.0
	const STEP := 0.5
	const MAXIMUM_CONTROL_TURN_DEGREES := 30.0
	var expected_surface := quarry.find_child("ContinuousRideableCollision", true, false) as StaticBody3D
	if expected_surface == null or checkpoint_chainages.size() < 7:
		print("GATE8 PRESENTED HEADING: required_geometry_missing=true passed=false")
		return {&"passed": false}
	var hud_gate8_chain := float(checkpoint_chainages[6])
	var route_index := _index_at_chain(chainages, hud_gate8_chain)
	var tangent := CourseSpline.tangent_at(route, route_index).normalized()
	var planar_forward := tangent.slide(Vector3.UP).normalized()
	var right := planar_forward.cross(Vector3.UP).normalized()
	var grade := tangent.y / maxf(tangent.slide(Vector3.UP).length(), 0.001)
	var controls := CourseCatalog.get_local_points(CourseCatalog.QUARRY_ID)
	var incoming := (controls[7] - controls[6]).slide(Vector3.UP).normalized()
	var outgoing := (controls[8] - controls[7]).slide(Vector3.UP).normalized()
	var control_turn_degrees := rad_to_deg(acos(clampf(incoming.dot(outgoing), -1.0, 1.0)))
	var chassis := CapsuleShape3D.new()
	chassis.radius = 0.31
	chassis.height = 1.197989
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = chassis
	query.collision_mask = 2
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.margin = 0.01
	query.exclude = [expected_surface.get_rid()]
	var bike_basis := Basis.looking_at(planar_forward, Vector3.UP) * Basis(Vector3.RIGHT, PI * 0.5)
	var hit_count := 0
	var minimum_clear_distance := CLEAR_DISTANCE
	var hit_names := PackedStringArray()
	for lane: float in [-3.0, 0.0, 3.0]:
		var distance := 0.0
		while distance < CLEAR_DISTANCE:
			var next_distance := minf(distance + STEP, CLEAR_DISTANCE)
			var from_ground := route[route_index] + right * lane + planar_forward * distance + Vector3.UP * (grade * distance)
			var to_ground := route[route_index] + right * lane + planar_forward * next_distance + Vector3.UP * (grade * next_distance)
			query.transform = Transform3D(
				bike_basis,
				from_ground + Vector3.UP * 0.83 - planar_forward * 0.13
			)
			query.motion = to_ground - from_ground
			var motion := get_world_3d().direct_space_state.cast_motion(query)
			if motion.size() >= 2 and float(motion[0]) < 0.999:
				var hit_distance := distance + STEP * float(motion[1])
				minimum_clear_distance = minf(minimum_clear_distance, hit_distance)
				hit_count += 1
				var collision_transform := query.transform.translated(query.motion * float(motion[1]))
				query.transform = collision_transform
				query.motion = Vector3.ZERO
				var rest := get_world_3d().direct_space_state.get_rest_info(query)
				var collider_id := int(rest.get(&"collider_id", 0))
				var collider := instance_from_id(collider_id) as CollisionObject3D if collider_id != 0 else null
				var collider_name := "<invalid>" if collider == null else String(collider.get_path())
				if collider_name not in hit_names:
					hit_names.append(collider_name)
				break
			distance = next_distance
	var passed := (
		control_turn_degrees <= MAXIMUM_CONTROL_TURN_DEGREES
		and hit_count == 0
	)
	print("GATE8 PRESENTED HEADING: chain=%.3fm route_index=%d turn=%.3fdeg lanes=3 clear_distance=%.1fm hits=%d bodies=%s passed=%s" % [
		hud_gate8_chain, route_index, control_turn_degrees, minimum_clear_distance,
		hit_count, str(hit_names), str(passed),
	])
	return {
		&"passed": passed,
		&"turn_degrees": control_turn_degrees,
		&"hits": hit_count,
		&"minimum_clear_distance": minimum_clear_distance,
	}


func _index_at_chain(chainages: PackedFloat32Array, target: float) -> int:
	var low := 0
	var high := chainages.size() - 1
	while low < high:
		var middle := (low + high) / 2
		if float(chainages[middle]) < target:
			low = middle + 1
		else:
			high = middle
	return clampi(low, 0, chainages.size() - 1)


func _route_chainages(route: PackedVector3Array) -> PackedFloat32Array:
	var chainages := PackedFloat32Array()
	chainages.resize(route.size())
	for index: int in range(1, route.size()):
		chainages[index] = chainages[index - 1] + route[index - 1].distance_to(route[index])
	return chainages
