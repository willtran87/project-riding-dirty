extends Node
## Deterministic regression for Rook's start footprint and initial playback.

const BIKE_SCENE := preload("res://entities/bike/bike.tscn")
const START_WINDOW_SECONDS: float = 1.0
const SAMPLE_STEP_SECONDS: float = 1.0 / 120.0


func _ready() -> void:
	var player := BIKE_SCENE.instantiate() as RigidBody3D
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	var player_visual := player.get_node("BikeVisual") as Node3D

	var ghost := GhostController.new()
	ghost.persistence_enabled = false
	add_child(ghost)

	var passed := true
	for track_id: StringName in [CourseCatalog.QUARRY_ID, CourseCatalog.PINE_ID]:
		passed = _audit_track(ghost, player, player_visual, track_id) and passed

	print("GHOST START SPACING RESULT: tracks=2 actual_mesh_footprints=true countdown_hidden=true forward_playback=true passed=%s" % str(passed))
	get_tree().quit(0 if passed else 1)


func _audit_track(
	ghost: GhostController,
	player: RigidBody3D,
	player_visual: Node3D,
	track_id: StringName
) -> bool:
	ghost.cancel_run()
	player.global_transform = CourseCatalog.get_spawn_transform(track_id)
	var points: Array[Vector3] = []
	for point: Vector3 in CourseCatalog.get_world_riding_points(track_id):
		points.append(point)
	ghost.configure_rival(points, CourseCatalog.get_rival_target_usec(track_id))

	var rival_root := ghost.get("_rival_root") as Node3D
	var rival_curve := ghost.get("_rival_curve") as Curve3D
	var countdown_hidden := rival_root != null and not rival_root.visible
	var configured := ghost.is_rival_configured() and rival_curve != null and rival_curve.point_count >= 2
	ghost.start_run()

	var route := CourseCatalog.get_world_riding_points(track_id)
	var forward := CourseSpline.tangent_at(route, 1).normalized()
	var minimum_gap := INF
	var minimum_time := 0.0
	var previous_position := Vector3.ZERO
	var previous_forward := forward
	var maximum_step := 0.0
	var minimum_forward_step := INF
	var minimum_heading_dot := 1.0
	var samples := int(ceil(START_WINDOW_SECONDS / SAMPLE_STEP_SECONDS)) + 1
	for sample_index: int in samples:
		var elapsed := minf(float(sample_index) * SAMPLE_STEP_SECONDS, START_WINDOW_SECONDS)
		ghost.set("_elapsed", elapsed)
		ghost.call("_update_rival_playback")
		var player_bounds := _projected_mesh_bounds(player_visual, forward)
		var rival_bounds := _projected_mesh_bounds(rival_root, forward)
		var gap := rival_bounds.x - player_bounds.y
		if gap < minimum_gap:
			minimum_gap = gap
			minimum_time = elapsed
		var position := rival_root.global_position
		var rival_forward := -rival_root.global_basis.z
		if sample_index > 0:
			var step := position - previous_position
			maximum_step = maxf(maximum_step, step.length())
			minimum_forward_step = minf(minimum_forward_step, step.dot(forward))
			minimum_heading_dot = minf(minimum_heading_dot, rival_forward.dot(previous_forward))
		previous_position = position
		previous_forward = rival_forward

	var smooth := maximum_step <= 0.2 and minimum_forward_step >= -0.001 and minimum_heading_dot >= 0.995
	var track_passed := (
		configured
		and countdown_hidden
		and rival_root.visible
		and minimum_gap >= 1.0
		and smooth
	)
	print("GHOST START SPACING: track=%s configured=%s countdown_hidden=%s samples=%d window=%.1fs minimum_visual_gap=%.3fm at=%.3fs max_step=%.3fm min_forward_step=%.4fm min_heading_dot=%.5f passed=%s" % [
		String(track_id), str(configured), str(countdown_hidden), samples,
		START_WINDOW_SECONDS, minimum_gap, minimum_time, maximum_step,
		minimum_forward_step, minimum_heading_dot, str(track_passed),
	])
	return track_passed


func _projected_mesh_bounds(root: Node3D, axis: Vector3) -> Vector2:
	var minimum := INF
	var maximum := -INF
	for child: Node in root.find_children("*", "", true, false):
		if child is not MeshInstance3D and child is not MultiMeshInstance3D:
			continue
		var visual := child as VisualInstance3D
		if not visual.visible:
			continue
		var bounds: AABB = visual.call("get_aabb") as AABB
		for x: float in [bounds.position.x, bounds.end.x]:
			for y: float in [bounds.position.y, bounds.end.y]:
				for z: float in [bounds.position.z, bounds.end.z]:
					var world_corner := visual.global_transform * Vector3(x, y, z)
					var projection := world_corner.dot(axis)
					minimum = minf(minimum, projection)
					maximum = maxf(maximum, projection)
	return Vector2(minimum, maximum)
