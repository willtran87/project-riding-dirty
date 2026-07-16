extends Node
## Focused deterministic regression for route integrity, resets and lap wraps.

const TRACKER_SCRIPT := preload("res://features/race/race_integrity_tracker.gd")


func _ready() -> void:
	var route := _build_closed_route()
	var spawn := _route_transform(route[0], route[1] - route[0])
	var passed := true
	passed = _test_normal_jump(route, spawn) and passed
	passed = _test_off_course(route, spawn) and passed
	passed = _test_wrong_way(route, spawn) and passed
	passed = _test_cut(route, spawn) and passed
	passed = _test_closed_seam_shortcut(route, spawn) and passed
	passed = _test_stuck(route, spawn) and passed
	passed = _test_lap_gate_projection_lag(route, spawn) and passed
	passed = _test_projection_wrap_before_lap_gate(route, spawn) and passed
	passed = _test_multi_lap_wrap(route, spawn) and passed
	print("RACE INTEGRITY TRACKER PROBE: passed=%s" % str(passed))
	get_tree().quit(0 if passed else 1)


func _test_normal_jump(route: PackedVector3Array, spawn: Transform3D) -> bool:
	var tracker := _new_tracker(route, spawn)
	for index: int in range(1, 9):
		var transform := _route_transform(route[index] + Vector3.UP * (10.0 if index in [4, 5] else 1.25), route[index + 1] - route[index])
		tracker.update(0.1, transform, (route[index + 1] - route[index]).normalized() * 18.0 + Vector3.UP * (5.0 if index == 4 else -2.0), 1)
	var snapshot: Dictionary = tracker.get_snapshot()
	var passed := not bool(snapshot[&"reset_requested"]) and int(snapshot[&"penalty_usec"]) == 0
	print("INTEGRITY NORMAL JUMP: reset=%s penalty=%d passed=%s" % [str(snapshot[&"reset_requested"]), int(snapshot[&"penalty_usec"]), str(passed)])
	return passed


func _test_off_course(route: PackedVector3Array, spawn: Transform3D) -> bool:
	var tracker := _new_tracker(route, spawn)
	tracker.update(0.1, _route_transform(route[10] + Vector3.UP * 1.25, route[11] - route[10]), Vector3(10.0, 0.0, 0.0), 1)
	var off_position := route[10] + Vector3(0.0, 1.25, 24.0)
	for _step: int in 4:
		tracker.update(0.2, _route_transform(off_position, route[11] - route[10]), Vector3.ZERO, 1)
	var snapshot: Dictionary = tracker.get_snapshot()
	var reset: Dictionary = tracker.consume_reset()
	var rejoin := reset.get(&"transform", Transform3D.IDENTITY) as Transform3D
	var passed := (
		bool(snapshot[&"reset_requested"])
		and StringName(snapshot[&"reset_reason"]) == &"OFF_COURSE"
		and int(snapshot[&"penalty_usec"]) == 1_000_000
		and bool(reset.get(&"requested", false))
		and rejoin.origin.distance_to(spawn.origin) > 1.0
	)
	print("INTEGRITY OFF COURSE: reason=%s penalty=%d rejoin=%s passed=%s" % [String(snapshot[&"reset_reason"]), int(snapshot[&"penalty_usec"]), str(rejoin.origin), str(passed)])
	return passed


func _test_wrong_way(route: PackedVector3Array, spawn: Transform3D) -> bool:
	var tracker := _new_tracker(route, spawn)
	var forward := (route[7] - route[6]).normalized()
	for _step: int in 4:
		tracker.update(0.2, _route_transform(route[6] + Vector3.UP * 1.25, forward), -forward * 12.0, 1)
	var snapshot: Dictionary = tracker.get_snapshot()
	var passed := (
		bool(snapshot[&"reset_requested"])
		and StringName(snapshot[&"reset_reason"]) == &"WRONG_WAY"
		and int(snapshot[&"penalty_usec"]) == 1_250_000
	)
	print("INTEGRITY WRONG WAY: reason=%s time=%.2f penalty=%d passed=%s" % [String(snapshot[&"reset_reason"]), float(snapshot[&"wrong_way_time"]), int(snapshot[&"penalty_usec"]), str(passed)])
	return passed


func _test_cut(route: PackedVector3Array, spawn: Transform3D) -> bool:
	var tracker := _new_tracker(route, spawn)
	var first_index := 2
	var second_index := 16
	tracker.update(0.1, _route_transform(route[first_index] + Vector3.UP * 1.25, route[first_index + 1] - route[first_index]), (route[first_index + 1] - route[first_index]).normalized() * 8.0, 1)
	tracker.update(0.1, _route_transform(route[second_index] + Vector3.UP * 1.25, route[second_index + 1] - route[second_index]), (route[second_index + 1] - route[second_index]).normalized() * 8.0, 1)
	var snapshot: Dictionary = tracker.get_snapshot()
	var passed := (
		bool(snapshot[&"cut_detected"])
		and StringName(snapshot[&"reset_reason"]) == &"CUT_DETECTED"
		and int(snapshot[&"penalty_usec"]) == 3_000_000
	)
	print("INTEGRITY CUT: delta=%.1f allowed=%.1f penalty=%d passed=%s" % [float((snapshot[&"projection"] as Dictionary).get(&"progress_delta", 0.0)), float((snapshot[&"projection"] as Dictionary).get(&"allowed_progress_jump", 0.0)), int(snapshot[&"penalty_usec"]), str(passed)])
	return passed


func _test_closed_seam_shortcut(route: PackedVector3Array, spawn: Transform3D) -> bool:
	var tracker := _new_tracker(route, spawn)
	var first_index := 2
	var final_index := route.size() - 3
	tracker.update(
		0.1,
		_route_transform(route[first_index] + Vector3.UP * 1.25, route[first_index + 1] - route[first_index]),
		(route[first_index + 1] - route[first_index]).normalized() * 8.0,
		1
	)
	var after: Dictionary = tracker.update(
		0.1,
		_route_transform(route[final_index] + Vector3.UP * 1.25, route[final_index + 1] - route[final_index]),
		(route[final_index + 1] - route[final_index]).normalized() * 8.0,
		1
	)
	var passed := (
		bool(after[&"cut_detected"])
		and bool(after[&"reset_requested"])
		and StringName(after[&"reset_reason"]) == &"CUT_DETECTED"
	)
	print("INTEGRITY CLOSED SEAM SHORTCUT: delta=%.1f reset=%s passed=%s" % [
		float((after[&"projection"] as Dictionary).get(&"progress_delta", 0.0)),
		str(after[&"reset_requested"]), str(passed),
	])
	return passed


func _test_stuck(route: PackedVector3Array, spawn: Transform3D) -> bool:
	var tracker := _new_tracker(route, spawn)
	var transform := _route_transform(route[9] + Vector3.UP * 1.25, route[10] - route[9])
	for _step: int in 5:
		tracker.update(0.2, transform, Vector3.ZERO, 1)
	var snapshot: Dictionary = tracker.get_snapshot()
	var passed := (
		bool(snapshot[&"stuck"])
		and StringName(snapshot[&"reset_reason"]) == &"STUCK"
		and int(snapshot[&"penalty_usec"]) == 750_000
	)
	print("INTEGRITY STUCK: time=%.2f penalty=%d passed=%s" % [float(snapshot[&"stuck_time"]), int(snapshot[&"penalty_usec"]), str(passed)])
	return passed


func _test_multi_lap_wrap(route: PackedVector3Array, spawn: Transform3D) -> bool:
	var tracker := _new_tracker(route, spawn)
	var last_index := route.size() - 2
	var before: Dictionary = tracker.update(
		0.1,
		_route_transform(route[last_index] + Vector3.UP * 1.25, route[last_index + 1] - route[last_index]),
		(route[last_index + 1] - route[last_index]).normalized() * 14.0,
		1
	)
	var after: Dictionary = tracker.update(
		0.1,
		_route_transform(route[1] + Vector3.UP * 1.25, route[2] - route[1]),
		(route[2] - route[1]).normalized() * 14.0,
		2
	)
	var passed := (
		int(after[&"lap"]) == 2
		and float(after[&"total_progress"]) > float(before[&"total_progress"])
		and not bool(after[&"cut_detected"])
		and not bool(after[&"reset_requested"])
	)
	print("INTEGRITY LAP WRAP: before=%.1f after=%.1f lap=%d passed=%s" % [float(before[&"total_progress"]), float(after[&"total_progress"]), int(after[&"lap"]), str(passed)])
	return passed


func _test_lap_gate_projection_lag(route: PackedVector3Array, spawn: Transform3D) -> bool:
	var tracker := _new_tracker(route, spawn)
	var last_index := route.size() - 2
	var finish_direction := route[last_index + 1] - route[last_index]
	var before: Dictionary = tracker.update(
		0.1,
		_route_transform(route[last_index] + Vector3.UP * 1.25, finish_direction),
		finish_direction.normalized() * 14.0,
		1
	)
	# The finish trigger advances the authoritative lap while the duplicated
	# start/finish anchor can still project onto the final segment for a frame.
	# That ambiguity must not look like a full-lap shortcut and request a reset.
	var seam: Dictionary = tracker.update(
		0.1,
		_route_transform(route[-1] + Vector3.UP * 1.25, finish_direction),
		finish_direction.normalized() * 14.0,
		2
	)
	var opening_direction := route[2] - route[1]
	var after: Dictionary = tracker.update(
		0.1,
		_route_transform(route[1] + Vector3.UP * 1.25, opening_direction),
		opening_direction.normalized() * 14.0,
		2
	)
	var seam_delta := float(seam[&"total_progress"]) - float(before[&"total_progress"])
	var passed := (
		seam_delta >= 0.0
		and seam_delta < 12.0
		and float(after[&"total_progress"]) > float(seam[&"total_progress"])
		and not bool(seam[&"cut_detected"])
		and not bool(seam[&"reset_requested"])
		and not bool(after[&"reset_requested"])
	)
	print("INTEGRITY LAP GATE LAG: before=%.1f seam=%.1f after=%.1f delta=%.1f reset=%s passed=%s" % [
		float(before[&"total_progress"]), float(seam[&"total_progress"]),
		float(after[&"total_progress"]), seam_delta, str(seam[&"reset_requested"]), str(passed),
	])
	return passed


func _test_projection_wrap_before_lap_gate(route: PackedVector3Array, spawn: Transform3D) -> bool:
	var tracker := _new_tracker(route, spawn)
	var last_index := route.size() - 2
	var finish_direction := route[last_index + 1] - route[last_index]
	var before: Dictionary = tracker.update(
		0.1,
		_route_transform(route[last_index] + Vector3.UP * 1.25, finish_direction),
		finish_direction.normalized() * 14.0,
		1
	)
	var opening_direction := route[2] - route[1]
	# Projection may choose the opening segment one tick before the Area3D gate
	# advances the authoritative lap. The next authority update must not create
	# the inverse whole-lap jump.
	var wrapped: Dictionary = tracker.update(
		0.1,
		_route_transform(route[1] + Vector3.UP * 1.25, opening_direction),
		opening_direction.normalized() * 14.0,
		1
	)
	var after: Dictionary = tracker.update(
		0.1,
		_route_transform(route[2] + Vector3.UP * 1.25, route[3] - route[2]),
		(route[3] - route[2]).normalized() * 14.0,
		2
	)
	var passed := (
		float(wrapped[&"total_progress"]) > float(before[&"total_progress"])
		and float(after[&"total_progress"]) > float(wrapped[&"total_progress"])
		and not bool(wrapped[&"reset_requested"])
		and not bool(after[&"reset_requested"])
	)
	print("INTEGRITY EARLY PROJECTION WRAP: before=%.1f wrapped=%.1f after=%.1f reset=%s passed=%s" % [
		float(before[&"total_progress"]), float(wrapped[&"total_progress"]),
		float(after[&"total_progress"]), str(after[&"reset_requested"]), str(passed),
	])
	return passed


func _new_tracker(route: PackedVector3Array, spawn: Transform3D) -> RefCounted:
	var tracker := TRACKER_SCRIPT.new()
	tracker.configure(route, 16.0, spawn, 3, {
		&"closed": true,
		&"search_window": 8,
		&"off_course_grace_seconds": 0.6,
		&"wrong_way_grace_seconds": 0.6,
		&"stuck_grace_seconds": 0.8,
		&"reset_penalty_usec": 1_000_000,
		&"wrong_way_penalty_usec": 1_250_000,
		&"stuck_penalty_usec": 750_000,
		&"cut_penalty_usec": 3_000_000,
		&"minimum_cut_jump": 24.0,
		&"rejoin_capture_interval": 0.1,
	})
	return tracker


func _build_closed_route() -> PackedVector3Array:
	var route := PackedVector3Array()
	for x: int in range(0, 101, 5):
		route.append(Vector3(float(x), 0.0, 0.0))
	for z: int in range(5, 61, 5):
		route.append(Vector3(100.0, 0.0, float(z)))
	for x: int in range(95, -1, -5):
		route.append(Vector3(float(x), 0.0, 60.0))
	for z: int in range(55, -1, -5):
		route.append(Vector3(0.0, 0.0, float(z)))
	return route


func _route_transform(position: Vector3, direction: Vector3) -> Transform3D:
	var forward := Vector3(direction.x, 0.0, direction.z).normalized()
	if forward.length_squared() < 0.5:
		forward = Vector3.FORWARD
	var right := forward.cross(Vector3.UP).normalized()
	return Transform3D(Basis(right, Vector3.UP, -forward).orthonormalized(), position)
