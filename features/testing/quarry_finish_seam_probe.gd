extends Node
## Dynamic regression for the welded Quarry timed-finish/apron collision.
## Run with:
## Godot --headless --path . res://features/testing/quarry_finish_seam_probe.tscn

const BIKE_SCENE := preload("res://entities/bike/bike.tscn")
const QUARRY_SCENE := preload("res://levels/quarry/quarry.tscn")
const ENTRY_SPEED_MPS: float = 18.0
const START_BEFORE_FINISH_METERS: float = 20.0
const TARGET_AFTER_FINISH_METERS: float = 12.0
const PROFILE_BEFORE_FINISH_METERS: float = 40.0
const PROFILE_AFTER_FINISH_METERS: float = 12.0
const PROFILE_STEP_METERS: float = 1.0
const MAXIMUM_SIMULATION_FRAMES: int = 300


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var quarry := QUARRY_SCENE.instantiate() as Node3D
	add_child(quarry)
	for _frame: int in 8:
		await get_tree().physics_frame

	var race_route := CourseCatalog.get_local_riding_points(CourseCatalog.QUARRY_ID)
	var apron: PackedVector3Array = quarry.get("_finish_apron_points")
	var combined := race_route.duplicate()
	for index: int in range(1, apron.size()):
		combined.append(apron[index])
	var cumulative := _cumulative_distances(combined)
	var race_cumulative := _cumulative_distances(race_route)
	var race_length := float(race_cumulative[-1])
	var combined_length := float(cumulative[-1])
	var space := quarry.get_world_3d().direct_space_state

	var topology_passed := _audit_collision_topology(quarry, combined.size())
	var visual_boundary_passed := _audit_visual_chunk_boundary(quarry, race_route.size() - 1)
	var profile := _print_finish_profile(space, combined, cumulative, race_length)

	var spawn_chain := race_length - START_BEFORE_FINISH_METERS
	var spawn_center := _point_at_chain(combined, cumulative, spawn_chain)
	var spawn_surface := _surface_point(space, spawn_center)
	var spawn_tangent := _tangent_at_chain(combined, cumulative, spawn_chain)
	var spawn_basis := Basis.looking_at(spawn_tangent, Vector3.UP)
	var bike := BIKE_SCENE.instantiate() as DirtBikeController
	add_child(bike)
	bike.apply_assist_mode(&"SPORT")
	bike.set_controls_enabled(false)
	bike.set_motion_locked(true)
	bike.respawn_at(Transform3D(spawn_basis, spawn_surface + Vector3.UP * 0.68))
	for _frame: int in 4:
		await get_tree().physics_frame
	bike.set_motion_locked(false)
	await get_tree().physics_frame
	var planar_spawn_tangent := spawn_tangent.slide(Vector3.UP).normalized()
	bike.linear_velocity = planar_spawn_tangent * ENTRY_SPEED_MPS

	var initial_speed := bike.get_speed_mps()
	var previous_chain := spawn_chain
	var previous_speed := initial_speed
	var minimum_speed := initial_speed
	var minimum_seam_speed := INF
	var maximum_frame_speed_loss := 0.0
	var maximum_lateral_error := 0.0
	var minimum_up := 1.0
	var grounded_frames := 0
	var sampled_frames := 0
	var maximum_airborne_frames := 0
	var consecutive_airborne_frames := 0
	var maximum_stationary_frames := 0
	var consecutive_stationary_frames := 0
	var reverse_progress_frames := 0
	var reached_target := false
	var target_speed := 0.0
	var target_forward_speed := 0.0
	var final_chain := spawn_chain
	var final_up := 1.0
	for frame: int in MAXIMUM_SIMULATION_FRAMES:
		await get_tree().physics_frame
		var projection := _closest_chain(combined, cumulative, bike.global_position, previous_chain, 36.0)
		var chain := float(projection[&"chain"])
		var lateral_error := float(projection[&"distance"])
		var tangent := _tangent_at_chain(combined, cumulative, chain).slide(Vector3.UP).normalized()
		var speed := bike.get_speed_mps()
		var forward_speed := Vector3(bike.linear_velocity.x, 0.0, bike.linear_velocity.z).dot(tangent)
		var up := bike.global_transform.basis.y.normalized().dot(Vector3.UP)
		var offset := chain - race_length
		var progress := chain - previous_chain
		minimum_speed = minf(minimum_speed, speed)
		if absf(offset) <= 2.0:
			minimum_seam_speed = minf(minimum_seam_speed, speed)
		maximum_frame_speed_loss = maxf(maximum_frame_speed_loss, previous_speed - speed)
		maximum_lateral_error = maxf(maximum_lateral_error, lateral_error)
		minimum_up = minf(minimum_up, up)
		if bike.is_grounded():
			grounded_frames += 1
			consecutive_airborne_frames = 0
		else:
			consecutive_airborne_frames += 1
			maximum_airborne_frames = maxi(maximum_airborne_frames, consecutive_airborne_frames)
		if progress < -0.015:
			reverse_progress_frames += 1
		if progress < 0.01 and speed < ENTRY_SPEED_MPS * 0.72:
			consecutive_stationary_frames += 1
			maximum_stationary_frames = maxi(maximum_stationary_frames, consecutive_stationary_frames)
		else:
			consecutive_stationary_frames = 0
		if frame % 12 == 0 or absf(offset) <= 2.0 or offset >= TARGET_AFTER_FINISH_METERS:
			print("QUARRY FINISH DYNAMIC SAMPLE: frame=%d offset=%+.2fm speed=%.3f forward=%.3f vertical=%.3f grounded=%s up=%.4f lateral=%.3f y=%.3f" % [
				frame, offset, speed, forward_speed, bike.linear_velocity.y,
				str(bike.is_grounded()), up, lateral_error, bike.global_position.y,
			])
		sampled_frames += 1
		previous_chain = chain
		previous_speed = speed
		final_chain = chain
		final_up = up
		if offset >= TARGET_AFTER_FINISH_METERS:
			reached_target = true
			target_speed = speed
			target_forward_speed = forward_speed
			break

	var grounded_ratio := float(grounded_frames) / maxf(float(sampled_frames), 1.0)
	var speed_retention := target_speed / maxf(initial_speed, 0.001)
	if is_inf(minimum_seam_speed):
		minimum_seam_speed = 0.0
	var dynamic_passed := (
		reached_target
		and target_forward_speed >= ENTRY_SPEED_MPS * 0.72
		and minimum_seam_speed >= ENTRY_SPEED_MPS * 0.72
		and speed_retention >= 0.72
		and grounded_ratio >= 0.80
		and maximum_airborne_frames <= 12
		and minimum_up >= 0.62
		and final_up >= 0.80
		and maximum_lateral_error <= 2.5
		and maximum_stationary_frames <= 4
		and reverse_progress_frames <= 1
	)
	var profile_passed := bool(profile[&"continuous"])
	var passed := topology_passed and visual_boundary_passed and profile_passed and dynamic_passed
	print("QUARRY FINISH DYNAMIC RESULT: reached=%s final_offset=%+.2fm entry=%.3f seam_min=%.3f exit=%.3f exit_forward=%.3f retention=%.3f min_speed=%.3f max_frame_loss=%.3f grounded=%d/%d ratio=%.3f max_airborne_frames=%d min_up=%.4f final_up=%.4f lateral=%.3f stationary=%d reverse=%d topology=%s visual_boundary=%s profile=%s passed=%s" % [
		str(reached_target), final_chain - race_length, initial_speed, minimum_seam_speed,
		target_speed, target_forward_speed, speed_retention, minimum_speed,
		maximum_frame_speed_loss, grounded_frames, sampled_frames, grounded_ratio,
		maximum_airborne_frames, minimum_up, final_up, maximum_lateral_error,
		maximum_stationary_frames, reverse_progress_frames, str(topology_passed),
		str(visual_boundary_passed), str(profile_passed), str(passed),
	])
	bike.shutdown_audio()
	bike.queue_free()
	quarry.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0 if passed else 1)


func _audit_collision_topology(quarry: Node3D, expected_points: int) -> bool:
	var ribbon := quarry.find_child("QuarryRaceRibbon", true, false) as Node3D
	var catch_pad := quarry.find_child("FinishCatchPad", true, false) as Node3D
	var collision := ribbon.find_child("ContinuousRideableCollision", true, false) as StaticBody3D if ribbon != null else null
	var collision_shapes := collision.find_children("*", "CollisionShape3D", true, false) if collision != null else []
	var catch_shapes := catch_pad.find_children("*", "CollisionShape3D", true, false) if catch_pad != null else []
	var passed := (
		ribbon != null
		and collision != null
		and collision_shapes.size() == 1
		and bool(ribbon.get_meta(&"welded_collision", false))
		and int(ribbon.get_meta(&"collision_centerline_size", 0)) == expected_points
		and catch_pad != null
		and bool(catch_pad.get_meta(&"finish_safety_apron", false))
		and catch_shapes.is_empty()
	)
	print("QUARRY FINISH COLLISION TOPOLOGY: expected_points=%d actual_points=%d shapes=%d catch_shapes=%d welded=%s passed=%s" % [
		expected_points,
		int(ribbon.get_meta(&"collision_centerline_size", 0)) if ribbon != null else 0,
		collision_shapes.size(), catch_shapes.size(),
		str(bool(ribbon.get_meta(&"welded_collision", false)) if ribbon != null else false),
		str(passed),
	])
	return passed


func _audit_visual_chunk_boundary(quarry: Node3D, race_finish_index: int) -> bool:
	var ribbon := quarry.find_child("QuarryRaceRibbon", true, false) as Node3D
	var chunk_segments := int(ribbon.get_meta(&"chunk_segments", CourseSurfaceBuilder.DEFAULT_CHUNK_SEGMENTS)) if ribbon != null else CourseSurfaceBuilder.DEFAULT_CHUNK_SEGMENTS
	var boundary_index := ceili(float(race_finish_index) / float(chunk_segments)) * chunk_segments
	var visual_points := int(ribbon.get_meta(&"visual_centerline_size", 0)) if ribbon != null else 0
	if boundary_index >= visual_points:
		print("QUARRY FINISH VISUAL BOUNDARY RESULT: finish_index=%d next_boundary=%d visual_points=%d chunk_segments=%d boundary_in_runoff=false passed=true" % [
			race_finish_index, boundary_index, visual_points, chunk_segments,
		])
		return true
	var right_chunk_index: int = boundary_index / chunk_segments
	var left_chunk_index: int = right_chunk_index - 1
	var left_chunk := ribbon.find_child("RibbonChunk%02d" % left_chunk_index, false, false) as Node3D if ribbon != null else null
	var right_chunk := ribbon.find_child("RibbonChunk%02d" % right_chunk_index, false, false) as Node3D if ribbon != null else null
	var strip_columns := {
		"RaceSurface": 9,
		"LeftShoulder": 2,
		"RightShoulder": 2,
		"Rut00": 2,
		"Rut01": 2,
		"Rut02": 2,
		"Rut03": 2,
	}
	var maximum_vertex_delta := 0.0
	var maximum_normal_angle := 0.0
	var maximum_uv_delta := 0.0
	var compared_strips := 0
	if left_chunk != null and right_chunk != null:
		for strip_name: String in strip_columns:
			var left_visual := left_chunk.get_node_or_null(strip_name) as MeshInstance3D
			var right_visual := right_chunk.get_node_or_null(strip_name) as MeshInstance3D
			if left_visual == null or right_visual == null:
				continue
			var left_arrays := left_visual.mesh.surface_get_arrays(0)
			var right_arrays := right_visual.mesh.surface_get_arrays(0)
			var left_vertices: PackedVector3Array = left_arrays[Mesh.ARRAY_VERTEX]
			var right_vertices: PackedVector3Array = right_arrays[Mesh.ARRAY_VERTEX]
			var left_normals: PackedVector3Array = left_arrays[Mesh.ARRAY_NORMAL]
			var right_normals: PackedVector3Array = right_arrays[Mesh.ARRAY_NORMAL]
			var left_uvs: PackedVector2Array = left_arrays[Mesh.ARRAY_TEX_UV]
			var right_uvs: PackedVector2Array = right_arrays[Mesh.ARRAY_TEX_UV]
			var columns: int = strip_columns[strip_name]
			var strip_vertex_delta := 0.0
			var strip_normal_angle := 0.0
			var strip_uv_delta := 0.0
			for column: int in columns:
				var left_index := left_vertices.size() - columns + column
				strip_vertex_delta = maxf(strip_vertex_delta, left_vertices[left_index].distance_to(right_vertices[column]))
				strip_normal_angle = maxf(strip_normal_angle, rad_to_deg(acos(clampf(left_normals[left_index].dot(right_normals[column]), -1.0, 1.0))))
				strip_uv_delta = maxf(strip_uv_delta, left_uvs[left_index].distance_to(right_uvs[column]))
			maximum_vertex_delta = maxf(maximum_vertex_delta, strip_vertex_delta)
			maximum_normal_angle = maxf(maximum_normal_angle, strip_normal_angle)
			maximum_uv_delta = maxf(maximum_uv_delta, strip_uv_delta)
			compared_strips += 1
			print("QUARRY FINISH VISUAL BOUNDARY STRIP: boundary_index=%d offset_samples=%+d strip=%s vertex_delta=%.8f normal_angle=%.6fdeg uv_delta=%.8f" % [
				boundary_index, boundary_index - race_finish_index, strip_name,
				strip_vertex_delta, strip_normal_angle, strip_uv_delta,
			])
	var passed := (
		left_chunk != null
		and right_chunk != null
		and compared_strips == strip_columns.size()
		and maximum_vertex_delta <= 0.00001
		# Packed float normals can differ by a few hundredths of a degree after
		# serialization even when their global-neighbor construction is identical.
		and maximum_normal_angle <= 0.05
		and maximum_uv_delta <= 0.00001
	)
	print("QUARRY FINISH VISUAL BOUNDARY RESULT: finish_index=%d boundary_index=%d offset_samples=%+d chunks=%d/%d strips=%d vertex_delta=%.8f normal_angle=%.6fdeg uv_delta=%.8f passed=%s" % [
		race_finish_index, boundary_index, boundary_index - race_finish_index,
		left_chunk_index, right_chunk_index, compared_strips, maximum_vertex_delta,
		maximum_normal_angle, maximum_uv_delta, str(passed),
	])
	return passed


func _print_finish_profile(
	space: PhysicsDirectSpaceState3D,
	combined: PackedVector3Array,
	cumulative: PackedFloat32Array,
	race_length: float
) -> Dictionary:
	var start_chain := race_length - PROFILE_BEFORE_FINISH_METERS
	var end_chain := race_length + PROFILE_AFTER_FINISH_METERS
	var maximum_grade_degrees := 0.0
	var maximum_grade_offset := 0.0
	var maximum_height_step := 0.0
	var maximum_height_step_offset := 0.0
	var previous_center := _point_at_chain(combined, cumulative, start_chain)
	var previous_surface := _surface_point(space, previous_center)
	var sample_count := roundi((end_chain - start_chain) / PROFILE_STEP_METERS)
	print("QUARRY FINISH PROFILE BEGIN: finish_chain=%.3fm range=-%.1f..+%.1fm step=%.1fm" % [
		race_length, PROFILE_BEFORE_FINISH_METERS, PROFILE_AFTER_FINISH_METERS, PROFILE_STEP_METERS,
	])
	for sample_index: int in range(1, sample_count + 1):
		var chain := start_chain + float(sample_index) * PROFILE_STEP_METERS
		var center := _point_at_chain(combined, cumulative, chain)
		var surface := _surface_point(space, center)
		var planar_run := Vector2(center.x - previous_center.x, center.z - previous_center.z).length()
		var grade_degrees := rad_to_deg(atan2(center.y - previous_center.y, maxf(planar_run, 0.001)))
		var surface_step := surface.y - previous_surface.y
		if absf(grade_degrees) > absf(maximum_grade_degrees):
			maximum_grade_degrees = grade_degrees
			maximum_grade_offset = chain - race_length
		if absf(surface_step) > maximum_height_step:
			maximum_height_step = absf(surface_step)
			maximum_height_step_offset = chain - race_length
		if sample_index % 2 == 0 or absf(chain - race_length) <= 2.01:
			print("QUARRY FINISH PROFILE: offset=%+.1fm center_y=%.4f surface_y=%.4f grade=%+.3fdeg surface_step=%+.4fm" % [
				chain - race_length, center.y, surface.y, grade_degrees, surface_step,
			])
		previous_center = center
		previous_surface = surface
	var before := _surface_point(space, _point_at_chain(combined, cumulative, race_length - 0.25))
	var after := _surface_point(space, _point_at_chain(combined, cumulative, race_length + 0.25))
	var seam_half_meter_delta := after.y - before.y
	var continuous := absf(seam_half_meter_delta) <= 0.18 and maximum_height_step <= 0.40
	print("QUARRY FINISH PROFILE RESULT: max_grade=%+.3fdeg at=%+.1fm max_surface_step=%.4fm at=%+.1fm seam_delta_0.5m=%+.4fm continuous=%s" % [
		maximum_grade_degrees, maximum_grade_offset, maximum_height_step,
		maximum_height_step_offset, seam_half_meter_delta, str(continuous),
	])
	return {
		&"maximum_grade_degrees": maximum_grade_degrees,
		&"maximum_grade_offset": maximum_grade_offset,
		&"maximum_height_step": maximum_height_step,
		&"seam_half_meter_delta": seam_half_meter_delta,
		&"continuous": continuous,
	}


func _cumulative_distances(route: PackedVector3Array) -> PackedFloat32Array:
	var cumulative := PackedFloat32Array()
	cumulative.resize(route.size())
	for index: int in range(1, route.size()):
		cumulative[index] = cumulative[index - 1] + route[index - 1].distance_to(route[index])
	return cumulative


func _point_at_chain(route: PackedVector3Array, cumulative: PackedFloat32Array, chain: float) -> Vector3:
	var low := 0
	var high := cumulative.size() - 1
	while low < high:
		var middle := (low + high) / 2
		if float(cumulative[middle]) < chain:
			low = middle + 1
		else:
			high = middle
	var index := clampi(low, 1, route.size() - 1)
	var start_distance := float(cumulative[index - 1])
	var segment_length := maxf(float(cumulative[index]) - start_distance, 0.0001)
	return route[index - 1].lerp(route[index], clampf((chain - start_distance) / segment_length, 0.0, 1.0))


func _tangent_at_chain(route: PackedVector3Array, cumulative: PackedFloat32Array, chain: float) -> Vector3:
	var behind := _point_at_chain(route, cumulative, maxf(chain - 1.0, 0.0))
	var ahead := _point_at_chain(route, cumulative, minf(chain + 1.0, float(cumulative[-1])))
	return (ahead - behind).normalized()


func _surface_point(space: PhysicsDirectSpaceState3D, center: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(
		center + Vector3.UP * 20.0,
		center + Vector3.DOWN * 20.0,
		2
	)
	var hit := space.intersect_ray(query)
	return hit.get(&"position", center)


func _closest_chain(
	route: PackedVector3Array,
	cumulative: PackedFloat32Array,
	position: Vector3,
	hint_chain: float,
	window: float
) -> Dictionary:
	var start_chain := maxf(hint_chain - 3.0, 0.0)
	var end_chain := minf(hint_chain + window, float(cumulative[-1]))
	var best_chain := start_chain
	var best_distance_squared := INF
	var chain := start_chain
	while chain <= end_chain + 0.001:
		var point := _point_at_chain(route, cumulative, chain)
		var distance_squared := Vector2(position.x - point.x, position.z - point.z).length_squared()
		if distance_squared < best_distance_squared:
			best_distance_squared = distance_squared
			best_chain = chain
		chain += 0.20
	return {
		&"chain": best_chain,
		&"distance": sqrt(best_distance_squared),
	}
