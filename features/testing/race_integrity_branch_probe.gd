extends Node
## Focused regression for legal skill-line projection and Pine network metadata.

const TRACKER_SCRIPT := preload("res://features/race/race_integrity_tracker.gd")
const PINE_BUILDER_SCRIPT := preload("res://levels/pine_ridge/pine_ridge_builder.gd")

const BRANCH_LINE_ID: StringName = &"TEST_SKILL_LINE"


func _ready() -> void:
	var main_route := _build_main_route()
	var branch_points := _build_branch_route()
	var spawn := _route_transform(main_route[0] + Vector3.UP * 1.25, Vector3.RIGHT)
	var passed := true
	passed = _test_main_contract(main_route, spawn) and passed
	passed = _test_legal_branch_progress(main_route, branch_points, spawn) and passed
	passed = _test_branch_wrong_way(main_route, branch_points, spawn) and passed
	passed = _test_branch_rejoin(main_route, branch_points, spawn) and passed
	passed = _test_pine_network_is_defensive() and passed
	print("RACE INTEGRITY BRANCH PROBE: passed=%s" % str(passed))
	get_tree().quit(0 if passed else 1)


func _test_main_contract(route: PackedVector3Array, spawn: Transform3D) -> bool:
	var tracker := TRACKER_SCRIPT.new()
	tracker.configure(route, 12.0, spawn, 1, _options([]))
	var snapshot: Dictionary = tracker.update(
		0.1,
		_route_transform(Vector3(35.0, 1.25, 0.0), Vector3.RIGHT),
		Vector3.RIGHT * 10.0,
		1
	)
	var passed := (
		StringName(snapshot[&"route_line_id"]) == &"MAIN"
		and int(snapshot[&"segment"]) == 6
		and int(snapshot[&"route_line_segment"]) == 6
		and is_equal_approx(float(snapshot[&"chainage"]), 35.0)
		and not bool(snapshot[&"reset_requested"])
	)
	print("BRANCH MAIN CONTRACT: segment=%d line=%s passed=%s" % [
		int(snapshot[&"segment"]), String(snapshot[&"route_line_id"]), str(passed)
	])
	return passed


func _test_legal_branch_progress(
		route: PackedVector3Array,
		branch_points: PackedVector3Array,
		spawn: Transform3D
	) -> bool:
	var tracker := _new_branch_tracker(route, branch_points, spawn)
	var previous_progress := -1.0
	var monotonic := true
	var used_branch := false
	var main_segment_contract := true
	var midpoint_snapshot: Dictionary = {}
	for index: int in branch_points.size():
		var direction := (
			branch_points[index + 1] - branch_points[index]
			if index + 1 < branch_points.size()
			else Vector3.RIGHT
		)
		var snapshot: Dictionary = tracker.update(
			0.1,
			_route_transform(branch_points[index] + Vector3.UP * 1.25, direction),
			direction.normalized() * 12.0,
			1
		)
		var progress := float(snapshot[&"chainage"])
		monotonic = monotonic and progress + 0.001 >= previous_progress
		previous_progress = progress
		if StringName(snapshot[&"route_line_id"]) == BRANCH_LINE_ID:
			used_branch = true
			var main_segment := int(snapshot[&"segment"])
			main_segment_contract = (
				main_segment_contract
				and main_segment >= 0
				and main_segment < route.size() - 1
				and progress + 0.001 >= float(main_segment) * 5.0
				and progress <= float(main_segment + 1) * 5.0 + 0.001
			)
			midpoint_snapshot = snapshot
	var exit_snapshot: Dictionary = tracker.update(
		0.1,
		_route_transform(Vector3(85.0, 1.25, 0.0), Vector3.RIGHT),
		Vector3.RIGHT * 12.0,
		1
	)
	var line_progress := float(midpoint_snapshot.get(&"route_line_progress", -1.0))
	var passed := (
		monotonic
		and used_branch
		and main_segment_contract
		and line_progress >= 0.0
		and line_progress <= 1.0
		and StringName(exit_snapshot[&"route_line_id"]) == &"MAIN"
		and not bool(exit_snapshot[&"cut_detected"])
		and not bool(exit_snapshot[&"reset_requested"])
		and int(exit_snapshot[&"penalty_usec"]) == 0
	)
	print("BRANCH LEGAL PROGRESS: monotonic=%s branch=%s exit=%s passed=%s" % [
		str(monotonic), str(used_branch), String(exit_snapshot[&"route_line_id"]), str(passed)
	])
	if not passed:
		print("BRANCH LEGAL DETAIL: segment_contract=%s line_progress=%.3f cut=%s reset=%s penalty=%d projection=%s" % [
			str(main_segment_contract), line_progress, str(exit_snapshot[&"cut_detected"]),
			str(exit_snapshot[&"reset_requested"]), int(exit_snapshot[&"penalty_usec"]),
			str(exit_snapshot[&"projection"])
		])
	return passed


func _test_branch_wrong_way(
		route: PackedVector3Array,
		branch_points: PackedVector3Array,
		spawn: Transform3D
	) -> bool:
	var tracker := _new_branch_tracker(route, branch_points, spawn)
	var branch_position := Vector3(20.0, 1.25, 10.0)
	var snapshot: Dictionary = {}
	for _step: int in 4:
		snapshot = tracker.update(
			0.15,
			_route_transform(branch_position, Vector3.FORWARD),
			Vector3.FORWARD * 10.0,
			1
		)
	var passed := (
		StringName(snapshot[&"route_line_id"]) == BRANCH_LINE_ID
		and bool(snapshot[&"wrong_way"])
		and StringName(snapshot[&"reset_reason"]) == &"WRONG_WAY"
		and bool(snapshot[&"reset_requested"])
	)
	print("BRANCH WRONG WAY: line=%s reason=%s passed=%s" % [
		String(snapshot[&"route_line_id"]), String(snapshot[&"reset_reason"]), str(passed)
	])
	return passed


func _test_branch_rejoin(
		route: PackedVector3Array,
		branch_points: PackedVector3Array,
		spawn: Transform3D
	) -> bool:
	var tracker := _new_branch_tracker(route, branch_points, spawn)
	var safe_position := Vector3(20.0, 1.25, 12.0)
	for _step: int in 2:
		tracker.update(
			0.1,
			_route_transform(safe_position, Vector3.FORWARD),
			Vector3.BACK * 8.0,
			1
		)
	var safe_snapshot: Dictionary = tracker.get_snapshot()
	var off_position := Vector3(5.0, 1.25, 12.0)
	for _step: int in 3:
		tracker.update(
			0.2,
			_route_transform(off_position, Vector3.FORWARD),
			Vector3.ZERO,
			1
		)
	var reset: Dictionary = tracker.consume_reset()
	var rejoin := reset.get(&"transform", Transform3D.IDENTITY) as Transform3D
	var passed := (
		StringName(safe_snapshot[&"route_line_id"]) == BRANCH_LINE_ID
		and bool(reset.get(&"requested", false))
		and rejoin.origin.distance_to(safe_position) < 1.0
		and rejoin.origin.z > 8.0
	)
	print("BRANCH REJOIN: line=%s origin=%s passed=%s" % [
		String(safe_snapshot[&"route_line_id"]), str(rejoin.origin), str(passed)
	])
	return passed


func _test_pine_network_is_defensive() -> bool:
	var builder := PINE_BUILDER_SCRIPT.new()
	builder.position = CourseCatalog.PINE_ORIGIN
	var first: Array[Dictionary] = builder.get_racecraft_network_world()
	var schema_valid := first.size() == 2
	var original_point := Vector3.ZERO
	if schema_valid:
		var first_points: PackedVector3Array = first[0].get(&"points", PackedVector3Array())
		schema_valid = (
			first_points.size() > 4
			and is_equal_approx(float(first[0].get(&"width", 0.0)), 4.8)
			and not StringName(first[0].get(&"line_id", &"")).is_empty()
			and float(first[0].get(&"entry_main_chainage", -1.0))
				< float(first[0].get(&"exit_main_chainage", -1.0))
			and typeof(first[0].get(&"entry", {})) == TYPE_DICTIONARY
			and typeof(first[0].get(&"exit", {})) == TYPE_DICTIONARY
		)
		if not first_points.is_empty():
			original_point = first_points[1]
			first_points[1] += Vector3(999.0, 0.0, 0.0)
			first[0][&"points"] = first_points
	var second: Array[Dictionary] = builder.get_racecraft_network_world()
	var defensive := (
		not second.is_empty()
		and (second[0].get(&"points", PackedVector3Array()) as PackedVector3Array).size() > 1
		and (second[0][&"points"] as PackedVector3Array)[1].is_equal_approx(original_point)
	)
	builder.free()
	var passed := schema_valid and defensive
	print("PINE BRANCH NETWORK: count=%d schema=%s defensive=%s passed=%s" % [
		first.size(), str(schema_valid), str(defensive), str(passed)
	])
	return passed


func _new_branch_tracker(
		route: PackedVector3Array,
		branch_points: PackedVector3Array,
		spawn: Transform3D
	) -> RefCounted:
	var tracker := TRACKER_SCRIPT.new()
	tracker.configure(route, 12.0, spawn, 1, _options([{
		&"line_id": BRANCH_LINE_ID,
		&"points": branch_points,
		&"width": 8.0,
		&"shoulder_margin": 2.0,
		&"warning_margin": 1.0,
		&"entry_main_chainage": 20.0,
		&"exit_main_chainage": 80.0,
	}]))
	return tracker


func _options(branch_routes: Array) -> Dictionary:
	return {
		&"closed": false,
		&"search_window": 8,
		&"branch_routes": branch_routes,
		&"off_course_grace_seconds": 0.4,
		&"wrong_way_grace_seconds": 0.4,
		&"stuck_grace_seconds": 1.2,
		&"reset_penalty_usec": 1_000_000,
		&"wrong_way_penalty_usec": 1_250_000,
		&"minimum_cut_jump": 18.0,
		&"rejoin_capture_interval": 0.1,
	}


func _build_main_route() -> PackedVector3Array:
	var route := PackedVector3Array()
	for x: int in range(0, 101, 5):
		route.append(Vector3(float(x), 0.0, 0.0))
	return route


func _build_branch_route() -> PackedVector3Array:
	return PackedVector3Array([
		Vector3(20.0, 0.0, 0.0),
		Vector3(20.0, 0.0, 8.0),
		Vector3(20.0, 0.0, 16.0),
		Vector3(30.0, 0.0, 22.0),
		Vector3(45.0, 0.0, 24.0),
		Vector3(60.0, 0.0, 22.0),
		Vector3(75.0, 0.0, 12.0),
		Vector3(80.0, 0.0, 0.0),
	])


func _route_transform(position: Vector3, direction: Vector3) -> Transform3D:
	var forward := Vector3(direction.x, 0.0, direction.z).normalized()
	if forward.length_squared() < 0.5:
		forward = Vector3.FORWARD
	var right := forward.cross(Vector3.UP).normalized()
	return Transform3D(Basis(right, Vector3.UP, -forward).orthonormalized(), position)
