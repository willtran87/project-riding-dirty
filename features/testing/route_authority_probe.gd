extends Node
## Regression: each streamed ribbon is the single source for HUD, gates, and rivals.

const MAIN_SCENE := preload("res://scenes/main.tscn")
const ROUTE_TOLERANCE := 0.00001
const MAP_PIXEL_TOLERANCE := 0.0001
const TRACK_IDS: Array[StringName] = [
	CourseCatalog.QUARRY_ID,
	CourseCatalog.PINE_ID,
	CourseCatalog.MESA_MX_ID,
]

var _stage := &"BOOT"


func _ready() -> void:
	# A structural probe must never persist career bootstrap state.
	Profile.persistence_enabled = false
	get_tree().create_timer(180.0, true).timeout.connect(_on_watchdog_timeout)
	_stage = &"INSTANTIATING_MAIN"
	var main := MAIN_SCENE.instantiate() as Node3D
	add_child(main)
	_stage = &"WAITING_FOR_MAIN_PHYSICS"
	for _frame: int in 3:
		await get_tree().physics_frame

	var passed := true
	for track_id: StringName in TRACK_IDS:
		passed = await _audit_track(main, track_id) and passed
	passed = await _audit_reverse_event(main) and passed

	print("ROUTE AUTHORITY PROBE: tracks=3 streamed_one_at_a_time=true map_resize=true tagged_surface_filter=true reverse_hud=true passed=%s" % str(passed))
	get_tree().quit(0 if passed else 1)


func _on_watchdog_timeout() -> void:
	push_error("ROUTE AUTHORITY PROBE WATCHDOG: stage=%s" % String(_stage))
	get_tree().quit(2)


func _audit_track(main: Node3D, track_id: StringName) -> bool:
	# Use Main's production streaming path, then allow queued old geometry and the
	# new track's physics bodies to synchronize before querying the world.
	_stage = StringName("STREAMING_%s" % String(track_id))
	main.call(&"_ensure_track_loaded", track_id)
	_stage = StringName("SYNCING_%s" % String(track_id))
	for _frame: int in 3:
		await get_tree().physics_frame

	_stage = StringName("AUDITING_%s" % String(track_id))
	var builder := main.call(&"_get_track_builder", track_id) as Node3D
	var level_root := main.get_node("LevelRoot") as Node3D
	var single_active := (
		builder != null
		and level_root.get_child_count() == 1
		and level_root.get_child(0) == builder
		and StringName(builder.get_meta(&"streamed_track_id", &"")) == track_id
	)
	if builder == null:
		print("ROUTE AUTHORITY TRACK: id=%s builder_missing=true passed=false" % String(track_id))
		return false

	var route: PackedVector3Array = main.call(&"get_authoritative_route", track_id)
	var hud := main.get_node("RaceHud")
	var race := main.get_node("RaceController")
	var ghost := main.get_node("GhostController")
	hud.call(&"configure_track", track_id, route)
	race.call(&"configure_track", track_id, route, builder)

	var controller_route: PackedVector3Array = race.call(&"get_authoritative_route_points")
	var pack_route: PackedVector3Array = race.call(&"get_pack_authoritative_route_points")
	var map_route: PackedVector3Array = hud.call(&"get_minimap_route_points")
	var rival_route: PackedVector3Array = ghost.call(&"get_rival_source_points")
	var maximum_delta := maxf(
		_maximum_route_delta(route, controller_route),
		maxf(
			_maximum_route_delta(route, pack_route),
			maxf(_maximum_route_delta(route, map_route), _maximum_route_delta(route, rival_route))
		)
	)

	var defensive_snapshot := race.call(&"get_authoritative_route_points") as PackedVector3Array
	defensive_snapshot[0] += Vector3(999.0, 999.0, 999.0)
	var defensive_copy := (
		(race.call(&"get_authoritative_route_points") as PackedVector3Array)[0]
		.distance_to(route[0]) <= ROUTE_TOLERANCE
	)

	var checkpoints: Array[Vector3] = race.call(&"get_checkpoint_positions")
	var event_id := (
		&"MESA_MX"
		if track_id == CourseCatalog.MESA_MX_ID
		else &"PINE_ENDURO"
		if track_id == CourseCatalog.PINE_ID
		else &"CIRCUIT"
	)
	var session := RaceEventCatalog.get_session_config(event_id)
	var expected_checkpoint_data := RaceEventCatalog.checkpoint_data(session, route)
	var maximum_gate_delta := 0.0
	for checkpoint_index: int in mini(checkpoints.size(), expected_checkpoint_data.size()):
		maximum_gate_delta = maxf(
			maximum_gate_delta,
			checkpoints[checkpoint_index].distance_to(
				expected_checkpoint_data[checkpoint_index].get(&"position", Vector3.ZERO)
			)
		)
	var monotonic := _checkpoints_are_monotonic(track_id, expected_checkpoint_data)
	var tagged := _has_authoritative_surface(builder, track_id)
	var map_resize_passed := await _audit_minimap_resize(hud, track_id, route)
	var surface_filter_passed := await _audit_surface_filter(main, race, track_id, route)

	var track_passed := (
		single_active
		and route.size() >= 2
		and controller_route.size() == route.size()
		and pack_route.size() == route.size()
		and map_route.size() == route.size()
		and rival_route.size() == route.size()
		and maximum_delta <= ROUTE_TOLERANCE
		and defensive_copy
		and checkpoints.size() == expected_checkpoint_data.size()
		and monotonic
		and maximum_gate_delta <= ROUTE_TOLERANCE
		and tagged
		and map_resize_passed
		and surface_filter_passed
	)
	print("ROUTE AUTHORITY TRACK: id=%s active_children=%d points=%d controller=%d pack=%d map=%d rival=%d max_delta=%.9fm gates=%d gate_delta=%.9fm monotonic=%s tagged=%s defensive=%s map_resize=%s surface_filter=%s passed=%s" % [
		String(track_id), level_root.get_child_count(), route.size(), controller_route.size(),
		pack_route.size(), map_route.size(), rival_route.size(), maximum_delta,
		checkpoints.size(), maximum_gate_delta, str(monotonic), str(tagged),
		str(defensive_copy), str(map_resize_passed), str(surface_filter_passed), str(track_passed),
	])
	return track_passed


func _audit_reverse_event(main: Node3D) -> bool:
	## Exercise Main's production launch path. RaceController prepares its own
	## defensive route copy, while the HUD must be handed the matching projection.
	_stage = &"LAUNCHING_REVERSE_EVENT"
	main.set("_smoke_test_enabled", true)
	main.call(&"_on_ride_requested", Profile.current_setup, &"QUARRY_HILLCLIMB")
	for _frame: int in 3:
		await get_tree().physics_frame
	_stage = &"AUDITING_REVERSE_EVENT"
	var raw_route: PackedVector3Array = main.call(&"get_authoritative_route", CourseCatalog.QUARRY_ID)
	var session := RaceEventCatalog.get_session_config(&"QUARRY_HILLCLIMB")
	var expected_route := RaceEventCatalog.prepare_route(session, raw_route)
	var hud := main.get_node("RaceHud")
	var race := main.get_node("RaceController")
	var hud_route: PackedVector3Array = hud.call(&"get_minimap_route_points")
	var controller_route: PackedVector3Array = race.call(&"get_authoritative_route_points")
	var reversed_endpoints := (
		raw_route.size() >= 2
		and expected_route.size() == raw_route.size()
		and expected_route[0].distance_to(raw_route[raw_route.size() - 1]) <= ROUTE_TOLERANCE
		and expected_route[expected_route.size() - 1].distance_to(raw_route[0]) <= ROUTE_TOLERANCE
	)
	var hud_delta := _maximum_route_delta(expected_route, hud_route)
	var controller_delta := _maximum_route_delta(expected_route, controller_route)
	var passed := (
		session != null
		and session.reverse_route
		and reversed_endpoints
		and hud_route.size() == expected_route.size()
		and controller_route.size() == expected_route.size()
		and hud_delta <= ROUTE_TOLERANCE
		and controller_delta <= ROUTE_TOLERANCE
	)
	print("ROUTE AUTHORITY REVERSE: event=QUARRY_HILLCLIMB raw=%d expected=%d hud=%d controller=%d hud_delta=%.9fm controller_delta=%.9fm endpoints=%s passed=%s" % [
		raw_route.size(), expected_route.size(), hud_route.size(), controller_route.size(),
		hud_delta, controller_delta, str(reversed_endpoints), str(passed),
	])
	return passed


func _audit_minimap_resize(
	hud: Node,
	track_id: StringName,
	route: PackedVector3Array
) -> bool:
	var course_map := hud.get("_course_map") as Control
	var original_size := course_map.size
	hud.call(&"configure_track", track_id, route)
	course_map.size = Vector2(222.0, 174.0)
	await get_tree().process_frame
	var small_points: PackedVector2Array = course_map.call(&"get_projected_points")
	course_map.size = Vector2(444.0, 348.0)
	await get_tree().process_frame
	var large_points: PackedVector2Array = course_map.call(&"get_projected_points")
	var static_draw_points: PackedVector2Array = course_map.get("_static_draw_points") as PackedVector2Array
	var maximum_pixel_delta := 0.0
	var maximum_resize_delta := 0.0
	for index: int in mini(route.size(), large_points.size()):
		var projected: Vector2 = course_map.call(&"project_world_position", route[index])
		maximum_pixel_delta = maxf(maximum_pixel_delta, large_points[index].distance_to(projected))
		if index < small_points.size():
			maximum_resize_delta = maxf(maximum_resize_delta, small_points[index].distance_to(large_points[index]))
	var layout_changed := maximum_resize_delta > 8.0
	var passed := (
		small_points.size() == route.size()
		and large_points.size() == route.size()
		and static_draw_points.size() <= CourseMinimap.MAX_STATIC_DRAW_POINTS
		and maximum_pixel_delta <= MAP_PIXEL_TOLERANCE
		and layout_changed
	)
	print("ROUTE AUTHORITY MAP RESIZE: id=%s route=%d small=%d large=%d static_draw=%d max_pixel_delta=%.9fpx resize_delta=%.3fpx layout_changed=%s passed=%s" % [
		String(track_id), route.size(), small_points.size(), large_points.size(),
		static_draw_points.size(), maximum_pixel_delta, maximum_resize_delta, str(layout_changed), str(passed),
	])
	course_map.size = original_size
	await get_tree().process_frame
	return passed


func _audit_surface_filter(
	main: Node3D,
	race: Node,
	track_id: StringName,
	route: PackedVector3Array
) -> bool:
	var pack := race.get("_race_pack") as Node3D
	var sample_index := mini(240, route.size() - 1)
	var nuisance := StaticBody3D.new()
	nuisance.name = "RouteAuthorityNuisance_%s" % String(track_id)
	nuisance.collision_layer = 2
	nuisance.collision_mask = 0
	nuisance.position = route[sample_index] + Vector3.UP * 2.4
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.4, 0.5, 1.4)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	nuisance.add_child(collision)
	main.add_child(nuisance)
	for _frame: int in 2:
		await get_tree().physics_frame

	var query := PhysicsRayQueryParameters3D.create(
		route[sample_index] + Vector3.UP * 8.0,
		route[sample_index] - Vector3.UP * 5.0,
		2
	)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var raw_hit: Dictionary = main.get_world_3d().direct_space_state.intersect_ray(query)
	var nuisance_exercised: bool = raw_hit.get(&"collider") == nuisance
	var hit: Dictionary = pack.call(&"_sample_ride_surface", route[sample_index])
	var collider := hit.get(&"collider") as Node
	var selected_authority := _node_has_authority(collider, track_id)
	var nuisance_skipped := collider != nuisance
	nuisance.queue_free()
	await get_tree().physics_frame
	var passed: bool = (
		nuisance_exercised
		and not hit.is_empty()
		and selected_authority
		and nuisance_skipped
	)
	print("ROUTE AUTHORITY SURFACE FILTER: id=%s raw_nuisance=%s collider=%s selected_authority=%s nuisance_skipped=%s passed=%s" % [
		String(track_id), str(nuisance_exercised),
		String(collider.name) if collider != null else "NONE", str(selected_authority),
		str(nuisance_skipped), str(passed),
	])
	return passed


func _checkpoints_are_monotonic(track_id: StringName, checkpoints: Array[Dictionary]) -> bool:
	if checkpoints.is_empty():
		return false
	if checkpoints[0].has(&"ratio"):
		var previous_ratio := -1.0
		for checkpoint: Dictionary in checkpoints:
			var ratio := float(checkpoint.get(&"ratio", -1.0))
			if ratio <= previous_ratio:
				return false
			previous_ratio = ratio
		return true
	var route_indices := CourseCatalog.get_checkpoint_route_indices(track_id)
	if route_indices.size() != checkpoints.size():
		return false
	var previous_index := -1
	for route_index: int in route_indices:
		if route_index <= previous_index:
			return false
		previous_index = route_index
	return true


func _has_authoritative_surface(root: Node, track_id: StringName) -> bool:
	if _node_has_authority(root, track_id):
		return true
	for child: Node in root.get_children():
		if _has_authoritative_surface(child, track_id):
			return true
	return false


func _node_has_authority(node: Node, track_id: StringName) -> bool:
	var current := node
	while current != null:
		if bool(current.get_meta(&"authoritative_track_surface", false)):
			return StringName(current.get_meta(&"authoritative_track_id", &"")) == track_id
		current = current.get_parent()
	return false


func _maximum_route_delta(first: PackedVector3Array, second: PackedVector3Array) -> float:
	if first.size() != second.size():
		return INF
	var maximum := 0.0
	for index: int in first.size():
		maximum = maxf(maximum, first[index].distance_to(second[index]))
	return maximum
