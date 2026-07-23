extends RefCounted
class_name CourseDressingBuilder
## Performance-conscious event dressing layered around an authored race polyline.
## Visual-only props are partitioned into small MultiMeshes; hero landmarks remain
## deliberate nodes so racing collision and checkpoint behavior stay untouched.

# Keep enough spatial granularity for the 300 m near-visibility envelope while
# avoiding hundreds of mostly empty draw groups on the wide quarry footprint.
# Instance transforms, collision and authored visibility ranges are unchanged.
const CELL_SIZE := 300.0
const NEAR_VISIBILITY := 300.0
const FAR_VISIBILITY := 480.0
const POLYLINE_INDEX_CELL_SIZE := 48.0
const BARRIER_LOCAL_EXCLUSION_METERS := 22.0
const BARRIER_CROSS_ROUTE_TOLERANCE := 1.0
const BAKE_SCHEMA_VERSION := 1


static func build_signature(
	track_id: StringName,
	route: PackedVector3Array,
	track_width: float,
	clearance_paths: Array[PackedVector3Array] = []
) -> int:
	# The baked scene is accepted only for the exact route, width, authored
	# catalog, and bake schema that produced it. Hashing the complete data contract
	# keeps the route authoritative while avoiding a multi-second procedural pass
	# on every Pine load. Bump BAKE_SCHEMA_VERSION when output logic changes.
	return hash([
		BAKE_SCHEMA_VERSION,
		track_id,
		route,
		snappedf(track_width, 0.001),
		clearance_paths,
		CourseDressingCatalog.get_config(track_id),
	])


static func build(
	parent: Node3D,
	track_id: StringName,
	route: PackedVector3Array,
	track_width: float,
	height_at: Callable,
	clearance_paths: Array[PackedVector3Array] = []
) -> Node3D:
	var root := Node3D.new()
	root.name = "CourseDressing"
	root.set_meta(&"dressing_build_signature", build_signature(
		track_id, route, track_width, clearance_paths
	))
	root.set_meta(&"dressing_bake_schema", BAKE_SCHEMA_VERSION)
	parent.add_child(root)
	if route.size() < 2 or not height_at.is_valid():
		return root

	var config := CourseDressingCatalog.get_config(track_id)
	config[&"track_id"] = track_id
	config[&"clearance_paths"] = clearance_paths
	var materials := _create_materials(config)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(config[&"seed"])
	var profile_build := OS.get_environment("RIDING_DIRTY_PROFILE_DRESSING") == "1"
	var phase_begin_usec := Time.get_ticks_usec()
	# The physical riding spline is sampled near one metre for tire response. The
	# dressing pass only needs an eight-metre polyline; using the physics density
	# made every foliage candidate scan thousands of redundant tiny segments.
	var dressing_route := _decimate_polyline(route, 8.0)
	var samples := _resample_polyline(dressing_route, float(config[&"marker_spacing"]))
	phase_begin_usec = _finish_profiled_phase(track_id, &"prepare", phase_begin_usec, profile_build)
	_build_trackside_language(root, samples, dressing_route, track_width, height_at, config, materials, rng)
	phase_begin_usec = _finish_profiled_phase(track_id, &"trackside_language", phase_begin_usec, profile_build)
	_build_course_fencing(root, dressing_route, track_width, height_at, config, materials)
	phase_begin_usec = _finish_profiled_phase(track_id, &"course_fencing", phase_begin_usec, profile_build)
	_build_surface_debris(root, dressing_route, track_width, height_at, config, materials, rng)
	phase_begin_usec = _finish_profiled_phase(track_id, &"surface_debris", phase_begin_usec, profile_build)
	_build_natural_layers(root, dressing_route, track_width, height_at, config, materials, rng)
	phase_begin_usec = _finish_profiled_phase(track_id, &"natural_layers", phase_begin_usec, profile_build)
	_build_spectator_zones(root, dressing_route, track_width, height_at, config, materials, rng)
	phase_begin_usec = _finish_profiled_phase(track_id, &"spectator_zones", phase_begin_usec, profile_build)
	_build_start_paddock(root, dressing_route, track_width, height_at, config, materials, rng)
	phase_begin_usec = _finish_profiled_phase(track_id, &"start_paddock", phase_begin_usec, profile_build)
	if bool(config[&"central_venue"]):
		_build_quarry_event_village(root, height_at, config, materials, rng)
	phase_begin_usec = _finish_profiled_phase(track_id, &"event_village", phase_begin_usec, profile_build)
	_batch_static_box_decor(root)
	_finish_profiled_phase(track_id, &"decor_batch", phase_begin_usec, profile_build)
	return root


static func _finish_profiled_phase(
	track_id: StringName,
	phase: StringName,
	begin_usec: int,
	enabled: bool
) -> int:
	var finish_usec := Time.get_ticks_usec()
	if enabled:
		print("COURSE DRESSING PHASE: track=%s phase=%s %.3fs" % [
			String(track_id), String(phase), float(finish_usec - begin_usec) / 1_000_000.0
		])
	return finish_usec


static func _create_materials(config: Dictionary) -> Dictionary[StringName, StandardMaterial3D]:
	var materials: Dictionary[StringName, StandardMaterial3D] = {}
	materials[&"accent"] = _material(config[&"accent"], 0.62, true)
	materials[&"accent_secondary"] = _material(config[&"accent_secondary"], 0.68, true)
	materials[&"canvas"] = _material(config[&"canvas"], 0.86, true)
	materials[&"dark"] = _material(config[&"dark"], 0.94, true)
	materials[&"timber"] = _material(config[&"timber"], 0.96, true)
	materials[&"natural"] = _material(Color.WHITE, 0.98, true)
	materials[&"rock"] = _material(Color.WHITE, 1.0, true)
	materials[&"skin"] = _material(Color("d7a579"), 0.9, false)
	return materials


static func _build_trackside_language(
	root: Node3D,
	samples: Array[Dictionary],
	control_points: PackedVector3Array,
	track_width: float,
	height_at: Callable,
	config: Dictionary,
	materials: Dictionary[StringName, StandardMaterial3D],
	rng: RandomNumberGenerator
) -> void:
	var post_transforms: Array[Transform3D] = []
	var post_colors: Array[Color] = []
	var board_transforms: Array[Transform3D] = []
	var board_colors: Array[Color] = []
	var bale_transforms: Array[Transform3D] = []
	var bale_colors: Array[Color] = []
	var accent: Color = config[&"accent"]
	var secondary: Color = config[&"accent_secondary"]
	var trackside_offset := float(config.get(&"trackside_offset", 4.4))
	for index: int in samples.size():
		var sample: Dictionary = samples[index]
		var center: Vector3 = sample[&"position"]
		var tangent: Vector3 = sample[&"tangent"]
		var right := Vector3(tangent.z, 0.0, -tangent.x).normalized()
		var side := -1.0 if index % 2 == 0 else 1.0
		var position := center + right * side * (track_width * 0.5 + trackside_offset)
		position.y = float(height_at.call(position.x, position.z))
		post_transforms.append(_scaled_transform(position + Vector3.UP * 1.25, atan2(tangent.x, tangent.z), Vector3(1.0, 2.5, 1.0)))
		post_colors.append(accent if index % 4 < 2 else secondary)
		if index % 3 == 0:
			var board_position := position + right * side * 0.16 + Vector3.UP * 1.72
			board_transforms.append(_scaled_transform(board_position, atan2(tangent.x, tangent.z), Vector3(1.0, 1.0, 1.0)))
			board_colors.append(accent if index % 2 == 0 else secondary)

	for index: int in range(1, control_points.size() - 1):
		var incoming := (control_points[index] - control_points[index - 1]).normalized()
		var outgoing := (control_points[index + 1] - control_points[index]).normalized()
		var signed_turn := incoming.cross(outgoing).y
		if absf(signed_turn) < 0.12:
			continue
		var tangent := (incoming + outgoing).normalized()
		var right := Vector3(tangent.z, 0.0, -tangent.x).normalized()
		var outside := -signf(signed_turn)
		for bale_index: int in 3:
			var position := control_points[index] + right * outside * (track_width * 0.5 + trackside_offset + 0.75 + bale_index * 1.05)
			position.y = float(height_at.call(position.x, position.z)) + 0.48
			bale_transforms.append(_scaled_transform(position, atan2(tangent.x, tangent.z), Vector3(1.15, 0.92, 0.85)))
			bale_colors.append(Color("d7ad5e").lerp(Color("b9803f"), rng.randf() * 0.28))

	var post_mesh := CylinderMesh.new()
	post_mesh.top_radius = 0.055
	post_mesh.bottom_radius = 0.07
	post_mesh.height = 1.0
	post_mesh.radial_segments = 6
	post_mesh.material = materials[&"accent"]
	_add_partitioned_multimesh(root, "CourseStakes", post_mesh, post_transforms, post_colors, NEAR_VISIBILITY)
	var board_mesh := BoxMesh.new()
	board_mesh.size = Vector3(1.65, 0.62, 0.08)
	board_mesh.material = materials[&"accent"]
	_add_partitioned_multimesh(root, "DirectionBoards", board_mesh, board_transforms, board_colors, NEAR_VISIBILITY)
	var bale_mesh := BoxMesh.new()
	bale_mesh.size = Vector3(1.0, 0.8, 0.72)
	bale_mesh.material = materials[&"canvas"]
	_add_partitioned_multimesh(root, "CornerBales", bale_mesh, bale_transforms, bale_colors, NEAR_VISIBILITY)


static func _build_course_fencing(
	root: Node3D,
	route: PackedVector3Array,
	track_width: float,
	height_at: Callable,
	config: Dictionary,
	materials: Dictionary[StringName, StandardMaterial3D]
) -> void:
	var profile_build := OS.get_environment("RIDING_DIRTY_PROFILE_DRESSING") == "1"
	var phase_begin_usec := Time.get_ticks_usec()
	var track_id: StringName = config.get(&"track_id", &"UNKNOWN")
	# The reference courses are visually contained almost continuously. Low
	# flexible barriers make the racing corridor read at speed. Matching,
	# end-to-end BoxShape3D segments make that readable edge physical too without
	# coplanar overlap or scaled collision shapes.
	var barrier_spacing := float(config.get(&"barrier_spacing", 6.0))
	# Match the resample spacing exactly. The previous 0.72 m overlap put two
	# coplanar boxes and two collision faces on every fence joint, producing both
	# visible z-fighting and redundant contact normals. A bike cannot pass through
	# a zero-width joint between full-height boxes.
	var barrier_length := barrier_spacing
	var barrier_offset := float(config.get(&"barrier_offset", 2.2))
	var barrier_height := float(config.get(&"barrier_height", 1.08))
	var barrier_thickness := float(config.get(&"barrier_thickness", 0.42))
	var opening_radius := float(config.get(&"barrier_opening_radius", 0.0))
	var openings: PackedVector3Array = config.get(&"barrier_openings", PackedVector3Array())
	var opening_corridor := float(config.get(&"barrier_opening_corridor", 0.0))
	var opening_paths: Array = config.get(&"barrier_opening_paths", [])
	var samples := _resample_polyline(route, barrier_spacing)
	var barrier_route := PackedVector3Array()
	barrier_route.resize(samples.size())
	for sample_index: int in samples.size():
		barrier_route[sample_index] = samples[sample_index][&"position"]
	var barrier_spatial_index := _build_polyline_spatial_index(barrier_route)
	phase_begin_usec = _finish_profiled_phase(track_id, &"fencing_prepare", phase_begin_usec, profile_build)
	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	var post_transforms: Array[Transform3D] = []
	var post_colors: Array[Color] = []
	var joint_transforms: Array[Transform3D] = []
	var joint_colors: Array[Color] = []
	var containment_faces := PackedVector3Array()
	var containment := StaticBody3D.new()
	containment.name = "CourseContainment"
	containment.collision_layer = 2
	containment.collision_mask = 1
	containment.set_meta(&"course_containment", true)
	containment.set_meta(&"track_width", track_width)
	containment.set_meta(&"segment_spacing", barrier_spacing)
	containment.set_meta(&"barrier_offset", barrier_offset)
	containment.set_meta(&"barrier_height", barrier_height)
	containment.set_meta(&"barrier_thickness", barrier_thickness)
	containment.set_meta(&"opening_count", openings.size())
	containment.set_meta(&"opening_corridor", opening_corridor)
	var barrier_physics := PhysicsMaterial.new()
	barrier_physics.friction = 0.34
	barrier_physics.rough = false
	barrier_physics.bounce = 0.02
	containment.physics_material_override = barrier_physics
	root.add_child(containment)
	containment.add_to_group(&"course_containment", true)
	var opening_posts := StaticBody3D.new()
	opening_posts.name = "CourseContainmentOpeningPosts"
	opening_posts.collision_layer = 2
	opening_posts.collision_mask = 1
	opening_posts.physics_material_override = barrier_physics
	opening_posts.set_meta(&"visible_barrier_ends", true)
	root.add_child(opening_posts)
	var accent: Color = config[&"accent"]
	var secondary: Color = config[&"accent_secondary"]
	var dark: Color = config[&"dark"]
	var side_values := PackedFloat32Array([-1.0, 1.0])
	var open_flags := PackedByteArray()
	open_flags.resize(samples.size() * side_values.size())
	var safety_suppressed_flags := PackedByteArray()
	safety_suppressed_flags.resize(samples.size() * side_values.size())
	var local_exclusion_samples := maxi(ceili(BARRIER_LOCAL_EXCLUSION_METERS / barrier_spacing), 1)
	var intended_route_distance := track_width * 0.5 + barrier_offset
	var minimum_nonlocal_distance := intended_route_distance - BARRIER_CROSS_ROUTE_TOLERANCE
	# Open the actual place where each alternate ribbon crosses a side barrier,
	# not just a short interval around its centerline endpoint. This remains
	# correct even when a branch leaves the main trail at a shallow angle.
	for index: int in samples.size():
		var sample: Dictionary = samples[index]
		var center: Vector3 = sample[&"position"]
		var tangent: Vector3 = sample[&"tangent"]
		var flat_tangent := Vector3(tangent.x, 0.0, tangent.z).normalized()
		if flat_tangent.length_squared() < 0.1:
			for side_index: int in side_values.size():
				open_flags[index * side_values.size() + side_index] = 1
			continue
		var right := flat_tangent.cross(Vector3.UP).normalized()
		var endpoint_open := _is_barrier_opening(center, openings, opening_radius)
		for side_index: int in side_values.size():
			var barrier_position := center + right * side_values[side_index] * (track_width * 0.5 + barrier_offset)
			if endpoint_open or _is_barrier_path_opening(barrier_position, opening_paths, opening_corridor):
				open_flags[index * side_values.size() + side_index] = 1
			elif _barrier_intrudes_nonlocal_route(
				barrier_position,
				flat_tangent,
				barrier_length,
				samples,
				index,
				local_exclusion_samples,
				minimum_nonlocal_distance,
				barrier_spatial_index
			):
				# A fence authored for one bend must never cut across another
				# nearby piece of the course. This is an unmarked safety gap, so it
				# deliberately does not create the posts used at branch portals.
				safety_suppressed_flags[index * side_values.size() + side_index] = 1
	phase_begin_usec = _finish_profiled_phase(track_id, &"fencing_safety_flags", phase_begin_usec, profile_build)
	var collision_count := 0
	var safety_suppressed_count := 0
	var minimum_panel_length := INF
	var maximum_panel_length := 0.0
	for flag: int in safety_suppressed_flags:
		if flag != 0:
			safety_suppressed_count += 1
	phase_begin_usec = _finish_profiled_phase(track_id, &"fencing_count_flags", phase_begin_usec, profile_build)
	# Build each panel from two shared offset-path endpoints. The previous
	# center-and-fixed-length placement left gaps as large as eight metres where
	# the decimated polyline changed tangent, despite reporting zero overlap.
	for index: int in range(samples.size() - 1):
		var first_sample: Dictionary = samples[index]
		var second_sample: Dictionary = samples[index + 1]
		var first_center: Vector3 = first_sample[&"position"]
		var second_center: Vector3 = second_sample[&"position"]
		var first_tangent: Vector3 = first_sample[&"tangent"]
		var second_tangent: Vector3 = second_sample[&"tangent"]
		var first_flat := Vector3(first_tangent.x, 0.0, first_tangent.z).normalized()
		var second_flat := Vector3(second_tangent.x, 0.0, second_tangent.z).normalized()
		if first_flat.length_squared() < 0.1 or second_flat.length_squared() < 0.1:
			continue
		var first_right := first_flat.cross(Vector3.UP).normalized()
		var second_right := second_flat.cross(Vector3.UP).normalized()
		for side_index: int in side_values.size():
			var first_flag := index * side_values.size() + side_index
			var second_flag := (index + 1) * side_values.size() + side_index
			if (
				open_flags[first_flag] != 0 or open_flags[second_flag] != 0
				or safety_suppressed_flags[first_flag] != 0
				or safety_suppressed_flags[second_flag] != 0
			):
				continue
			var side := side_values[side_index]
			var first_position := first_center + first_right * side * intended_route_distance
			var second_position := second_center + second_right * side * intended_route_distance
			var panel_delta := second_position - first_position
			panel_delta.y = 0.0
			var panel_length := panel_delta.length()
			if panel_length < 0.2:
				continue
			minimum_panel_length = minf(minimum_panel_length, panel_length)
			maximum_panel_length = maxf(maximum_panel_length, panel_length)
			var panel_tangent := panel_delta / panel_length
			var position := first_position.lerp(second_position, 0.5)
			var terrain_height := float(height_at.call(position.x, position.z))
			var route_height := lerpf(first_center.y, second_center.y, 0.5)
			var barrier_ground := maxf(terrain_height, route_height - 0.52)
			position.y = barrier_ground + barrier_height * 0.5 - 0.08
			var yaw := atan2(panel_tangent.x, panel_tangent.z)
			transforms.append(_scaled_transform(position, yaw, Vector3(1.0, barrier_height, panel_length)))
			if index % 8 < 4:
				colors.append(accent if side < 0.0 else secondary)
			else:
				colors.append(dark)
			# A small visual cap at every shared closed endpoint hides the wedge
			# exposed by two finite-thickness boxes meeting on a bend. It is visual
			# only: the endpoint-welded panels remain the sole collision surface.
			if index > 0:
				var previous_flag := (index - 1) * side_values.size() + side_index
				if open_flags[previous_flag] == 0 and safety_suppressed_flags[previous_flag] == 0:
					var joint_position := first_position
					var joint_ground := maxf(
						float(height_at.call(joint_position.x, joint_position.z)),
						first_center.y - 0.52
					)
					joint_position.y = joint_ground + barrier_height * 0.5 - 0.08
					joint_transforms.append(_scaled_transform(
						joint_position, yaw, Vector3(1.35, barrier_height, 1.35)
					))
					joint_colors.append(accent if side < 0.0 else secondary)

			_append_box_collision_faces(
				containment_faces,
				Vector3(barrier_thickness, barrier_height, panel_length),
				Transform3D(Basis.from_euler(Vector3(0.0, yaw, 0.0)), position)
			)
			collision_count += 1

			# Portal posts close only explicitly authored opening ends. Safety gaps
			# near another loop remain completely clear.
			var previous_explicit_open := index > 0 and open_flags[(index - 1) * side_values.size() + side_index] != 0
			var next_explicit_open := index + 2 < samples.size() and open_flags[(index + 2) * side_values.size() + side_index] != 0
			for end_sign: float in [-1.0, 1.0]:
				if (end_sign < 0.0 and not previous_explicit_open) or (end_sign > 0.0 and not next_explicit_open):
					continue
				var post_size := Vector3(barrier_thickness * 1.7, barrier_height + 1.35, barrier_thickness * 1.7)
				var endpoint := first_position if end_sign < 0.0 else second_position
				var post_position := endpoint + panel_tangent * end_sign * post_size.z * 0.5
				post_position.y = position.y + (post_size.y - barrier_height) * 0.5
				if _barrier_intrudes_nonlocal_route(
					post_position, panel_tangent, post_size.z, samples, index,
					local_exclusion_samples, minimum_nonlocal_distance,
					barrier_spatial_index
				):
					continue
				post_transforms.append(_scaled_transform(post_position, yaw, post_size))
				post_colors.append(accent if side < 0.0 else secondary)
				var post_shape := BoxShape3D.new()
				post_shape.size = post_size
				var post_collision := CollisionShape3D.new()
				post_collision.name = "OpeningPost%04d" % post_transforms.size()
				post_collision.shape = post_shape
				post_collision.transform = Transform3D(Basis.from_euler(Vector3(0.0, yaw, 0.0)), post_position)
				opening_posts.add_child(post_collision)
	phase_begin_usec = _finish_profiled_phase(track_id, &"fencing_panels", phase_begin_usec, profile_build)
	if not containment_faces.is_empty():
		var compound_shape := ConcavePolygonShape3D.new()
		compound_shape.backface_collision = true
		compound_shape.set_faces(containment_faces)
		var compound_collision := CollisionShape3D.new()
		compound_collision.name = "CourseContainmentCompound"
		compound_collision.shape = compound_shape
		containment.add_child(compound_collision)
	phase_begin_usec = _finish_profiled_phase(track_id, &"fencing_compound", phase_begin_usec, profile_build)
	containment.set_meta(&"segment_count", collision_count)
	containment.set_meta(&"collision_shape_count", 1 if collision_count > 0 else 0)
	containment.set_meta(&"compound_collision", true)
	containment.set_meta(&"compound_face_count", containment_faces.size() / 3)
	containment.set_meta(&"safety_suppressed_count", safety_suppressed_count)
	containment.set_meta(&"shared_endpoint_panels", true)
	containment.set_meta(&"maximum_panel_joint_gap", 0.0)
	containment.set_meta(&"minimum_panel_length", minimum_panel_length if collision_count > 0 else 0.0)
	containment.set_meta(&"maximum_panel_length", maximum_panel_length)
	containment.set_meta(&"visual_joint_count", joint_transforms.size())
	opening_posts.set_meta(&"post_count", post_transforms.size())
	var panel_mesh := BoxMesh.new()
	panel_mesh.size = Vector3(barrier_thickness, 1.0, 1.0)
	panel_mesh.material = materials[&"accent"]
	_add_partitioned_multimesh(root, "CourseContainmentPanel", panel_mesh, transforms, colors, NEAR_VISIBILITY)
	var joint_mesh := BoxMesh.new()
	joint_mesh.size = Vector3(barrier_thickness, 1.0, barrier_thickness)
	joint_mesh.material = materials[&"accent"]
	_add_partitioned_multimesh(root, "CourseContainmentJoint", joint_mesh, joint_transforms, joint_colors, NEAR_VISIBILITY)
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3.ONE
	post_mesh.material = materials[&"accent"]
	_add_partitioned_multimesh(root, "CourseContainmentOpeningPost", post_mesh, post_transforms, post_colors, NEAR_VISIBILITY)
	_finish_profiled_phase(track_id, &"fencing_multimeshes", phase_begin_usec, profile_build)


static func _append_box_collision_faces(faces: PackedVector3Array, size: Vector3, transform: Transform3D) -> void:
	var half := size * 0.5
	var corners := PackedVector3Array([
		Vector3(-half.x, -half.y, -half.z), Vector3(half.x, -half.y, -half.z),
		Vector3(half.x, half.y, -half.z), Vector3(-half.x, half.y, -half.z),
		Vector3(-half.x, -half.y, half.z), Vector3(half.x, -half.y, half.z),
		Vector3(half.x, half.y, half.z), Vector3(-half.x, half.y, half.z),
	])
	for index: int in corners.size():
		corners[index] = transform * corners[index]
	var triangles := PackedInt32Array([
		0, 2, 1, 0, 3, 2,
		4, 5, 6, 4, 6, 7,
		0, 1, 5, 0, 5, 4,
		3, 7, 6, 3, 6, 2,
		0, 4, 7, 0, 7, 3,
		1, 2, 6, 1, 6, 5,
	])
	for corner_index: int in triangles:
		faces.append(corners[corner_index])


static func _is_barrier_opening(center: Vector3, openings: PackedVector3Array, radius: float) -> bool:
	if radius <= 0.0:
		return false
	var center_2d := Vector2(center.x, center.z)
	for opening: Vector3 in openings:
		if center_2d.distance_to(Vector2(opening.x, opening.z)) < radius:
			return true
	return false


static func _is_barrier_path_opening(position: Vector3, paths: Array, radius: float) -> bool:
	if radius <= 0.0:
		return false
	for path_value: Variant in paths:
		var path: PackedVector3Array = path_value
		for index: int in path.size() - 1:
			if _distance_to_segment_2d(position, path[index], path[index + 1]) < radius:
				return true
	return false


static func _barrier_intrudes_nonlocal_route(
	position: Vector3,
	tangent: Vector3,
	length: float,
	samples: Array[Dictionary],
	source_index: int,
	local_exclusion_samples: int,
	minimum_distance: float,
	spatial_index: Dictionary = {}
) -> bool:
	# Test the whole long axis, not only the panel center. On a folded course an
	# endpoint can cross the neighboring ribbon even when the center looks safe.
	var flat_tangent := Vector3(tangent.x, 0.0, tangent.z).normalized()
	var probes := PackedVector3Array([
		position,
		position - flat_tangent * length * 0.5,
		position + flat_tangent * length * 0.5,
	])
	for probe: Vector3 in probes:
		if not spatial_index.is_empty():
			if _polyline_has_nonlocal_segment_within(
				probe,
				spatial_index,
				minimum_distance,
				source_index,
				local_exclusion_samples
			):
				return true
			continue
		for segment_index: int in range(samples.size() - 1):
			if (
				segment_index >= source_index - local_exclusion_samples
				and segment_index <= source_index + local_exclusion_samples
			):
				continue
			var segment_start: Vector3 = samples[segment_index][&"position"]
			var segment_end: Vector3 = samples[segment_index + 1][&"position"]
			if _distance_to_segment_2d(probe, segment_start, segment_end) < minimum_distance:
				return true
	return false


static func _distance_to_segment_2d(point: Vector3, start: Vector3, end: Vector3) -> float:
	var point_2d := Vector2(point.x, point.z)
	var start_2d := Vector2(start.x, start.z)
	var end_2d := Vector2(end.x, end.z)
	var segment := end_2d - start_2d
	var weight := clampf((point_2d - start_2d).dot(segment) / maxf(segment.length_squared(), 0.001), 0.0, 1.0)
	return point_2d.distance_to(start_2d + segment * weight)


static func _build_surface_debris(
	root: Node3D,
	route: PackedVector3Array,
	track_width: float,
	height_at: Callable,
	config: Dictionary,
	materials: Dictionary[StringName, StandardMaterial3D],
	rng: RandomNumberGenerator
) -> void:
	var samples := _resample_polyline(route, 18.0)
	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	var rock_color: Color = config[&"rock"]
	var debris_inner_clearance := track_width * 0.5 + float(config.get(&"barrier_offset", 4.0)) + 1.0
	root.set_meta(&"surface_debris_minimum_route_clearance", debris_inner_clearance)
	for index: int in range(3, samples.size() - 2):
		if index % 3 == 0:
			continue
		var sample: Dictionary = samples[index]
		var center: Vector3 = sample[&"position"]
		var tangent: Vector3 = sample[&"tangent"]
		var flat_tangent := Vector3(tangent.x, 0.0, tangent.z).normalized()
		var right := flat_tangent.cross(Vector3.UP).normalized()
		var side := -1.0 if index % 2 == 0 else 1.0
		var cluster_count := 2 + index % 3
		for debris_index: int in cluster_count:
			# These small rocks are intentionally non-colliding dressing. They used
			# to occupy 28-47% of the track width, which put them directly in the
			# race lanes and made every bike visibly pass through them. Keep the
			# whole cluster behind the containment panels instead.
			var lateral := side * rng.randf_range(debris_inner_clearance, debris_inner_clearance + 2.2)
			var along := (float(debris_index) - float(cluster_count - 1) * 0.5) * rng.randf_range(0.65, 1.2)
			var position := center + right * lateral + flat_tangent * along
			position.y = float(height_at.call(position.x, position.z)) + 0.1
			var scale_value := rng.randf_range(0.16, 0.48)
			transforms.append(Transform3D(
				Basis.from_euler(Vector3(rng.randf_range(-0.35, 0.35), rng.randf_range(0.0, TAU), rng.randf_range(-0.35, 0.35))).scaled(
					Vector3(scale_value * 1.35, scale_value * 0.62, scale_value)
				),
				position
			))
			colors.append(rock_color.lerp(Color("2d241f"), rng.randf() * 0.42))
	var debris_mesh := SphereMesh.new()
	debris_mesh.radius = 0.72
	debris_mesh.height = 0.9
	debris_mesh.radial_segments = 5
	debris_mesh.rings = 3
	debris_mesh.material = materials[&"rock"]
	_add_partitioned_multimesh(root, "SurfaceChunks", debris_mesh, transforms, colors, NEAR_VISIBILITY)


static func _build_natural_layers(
	root: Node3D,
	route: PackedVector3Array,
	track_width: float,
	height_at: Callable,
	config: Dictionary,
	materials: Dictionary[StringName, StandardMaterial3D],
	rng: RandomNumberGenerator
) -> void:
	var bounds: Vector2 = config[&"bounds"]
	var near_band: Vector2 = config[&"readability_band"]
	var far_band: Vector2 = config[&"backdrop_band"]
	# Green ground-cover used to begin at 12 m in the quarry: exactly the edge
	# of its 24 m race surface and still inside the pale shoulder.  A rider using
	# the full road could therefore see scrub replace the authored dirt edge even
	# though the ribbon itself remained present.  Keep the complete ground-cover
	# mesh (maximum horizontal radius is about 1.5 m) behind containment.
	var minimum_natural_clearance := (
		track_width * 0.5 + float(config.get(&"barrier_offset", 4.0)) + 2.0
	)
	near_band.x = maxf(near_band.x, minimum_natural_clearance)
	far_band.x = maxf(far_band.x, near_band.x + 1.0)
	root.set_meta(&"natural_ground_cover_minimum_route_clearance", near_band.x)
	var central_venue := bool(config[&"central_venue"])
	var clearance_paths: Array[PackedVector3Array] = config.get(&"clearance_paths", [])
	# Scatter acceptance depends on exact distance to the route, but repeatedly
	# scanning every segment made long courses spend seconds rejecting foliage.
	# A segment grid narrows each bounded query while retaining the same exact
	# point-to-segment calculation and therefore the same deterministic layout.
	var route_spatial_index := _build_polyline_spatial_index(route)
	var clearance_spatial_indexes: Array[Dictionary] = []
	for clearance_path: PackedVector3Array in clearance_paths:
		clearance_spatial_indexes.append(_build_polyline_spatial_index(clearance_path))
	var natural_transforms: Array[Transform3D] = []
	var natural_colors: Array[Color] = []
	var backdrop_transforms: Array[Transform3D] = []
	var backdrop_colors: Array[Color] = []
	var rock_transforms: Array[Transform3D] = []
	var rock_colors: Array[Color] = []
	var deadfall_transforms: Array[Transform3D] = []
	var deadfall_colors: Array[Color] = []

	_scatter_band(
		natural_transforms,
		natural_colors,
		int(config[&"near_natural_count"]),
		bounds,
		near_band,
		route,
		height_at,
		config[&"natural_a"],
		config[&"natural_b"],
		rng,
		central_venue,
		Vector2(0.55, 1.65),
		false,
		clearance_paths,
		route_spatial_index,
		clearance_spatial_indexes
	)
	_scatter_band(
		backdrop_transforms,
		backdrop_colors,
		int(config[&"backdrop_natural_count"]),
		bounds,
		far_band,
		route,
		height_at,
		config[&"natural_a"],
		config[&"natural_b"],
		rng,
		central_venue,
		Vector2(0.85, 2.25),
		false,
		clearance_paths,
		route_spatial_index,
		clearance_spatial_indexes
	)
	_scatter_band(
		rock_transforms,
		rock_colors,
		int(config[&"rock_count"]),
		bounds,
		Vector2(near_band.x + 2.0, far_band.y),
		route,
		height_at,
		config[&"rock"],
		Color(config[&"rock"]).lightened(0.16),
		rng,
		central_venue,
		Vector2(0.45, 1.8),
		false,
		clearance_paths,
		route_spatial_index,
		clearance_spatial_indexes
	)
	var actual_minimum_clearance := INF
	for transform: Transform3D in natural_transforms:
		actual_minimum_clearance = minf(
			actual_minimum_clearance,
			_distance_to_polyline_bounded(transform.origin, route_spatial_index, far_band.y)
		)
	for transform: Transform3D in backdrop_transforms:
		actual_minimum_clearance = minf(
			actual_minimum_clearance,
			_distance_to_polyline_bounded(transform.origin, route_spatial_index, far_band.y)
		)
	root.set_meta(&"natural_ground_cover_actual_minimum_route_clearance", actual_minimum_clearance)
	root.set_meta(&"natural_ground_cover_instance_count", natural_transforms.size() + backdrop_transforms.size())

	var natural_mesh := SphereMesh.new()
	natural_mesh.radius = 0.7
	natural_mesh.height = 1.2
	natural_mesh.radial_segments = 6
	natural_mesh.rings = 3
	natural_mesh.material = materials[&"natural"]
	_add_partitioned_multimesh(root, "TracksideGroundCover", natural_mesh, natural_transforms, natural_colors, NEAR_VISIBILITY)
	_add_partitioned_multimesh(root, "BackdropGroundCover", natural_mesh, backdrop_transforms, backdrop_colors, FAR_VISIBILITY)
	var rock_mesh := SphereMesh.new()
	rock_mesh.radius = 0.72
	rock_mesh.height = 1.0
	rock_mesh.radial_segments = 7
	rock_mesh.rings = 4
	rock_mesh.material = materials[&"rock"]
	_add_partitioned_multimesh(root, "RockClusters", rock_mesh, rock_transforms, rock_colors, FAR_VISIBILITY)

	var deadfall_count := int(config[&"deadfall_count"])
	if deadfall_count > 0:
		_scatter_band(
			deadfall_transforms,
			deadfall_colors,
			deadfall_count,
			bounds,
			Vector2(near_band.y, far_band.y),
			route,
			height_at,
			config[&"timber"],
			Color(config[&"timber"]).darkened(0.18),
			rng,
			false,
			Vector2(0.8, 1.45),
			true,
			clearance_paths,
			route_spatial_index,
			clearance_spatial_indexes
		)
		var log_mesh := CylinderMesh.new()
		log_mesh.top_radius = 0.24
		log_mesh.bottom_radius = 0.32
		log_mesh.height = 3.8
		log_mesh.radial_segments = 7
		log_mesh.material = materials[&"timber"]
		_add_partitioned_multimesh(root, "Deadfall", log_mesh, deadfall_transforms, deadfall_colors, FAR_VISIBILITY)


static func _scatter_band(
	transforms: Array[Transform3D],
	colors: Array[Color],
	requested_count: int,
	bounds: Vector2,
	band: Vector2,
	route: PackedVector3Array,
	height_at: Callable,
	color_a: Color,
	color_b: Color,
	rng: RandomNumberGenerator,
	protect_center: bool,
	scale_range: Vector2,
	lay_flat: bool = false,
	clearance_paths: Array[PackedVector3Array] = [],
	route_spatial_index: Dictionary = {},
	clearance_spatial_indexes: Array[Dictionary] = []
) -> void:
	var attempts := 0
	while transforms.size() < requested_count and attempts < requested_count * 35:
		attempts += 1
		var position := Vector3(
			rng.randf_range(-bounds.x * 0.5, bounds.x * 0.5),
			0.0,
			rng.randf_range(-bounds.y * 0.5, bounds.y * 0.5)
		)
		if protect_center and Vector2(position.x, position.z).length() < 96.0:
			continue
		var inside_clearance := false
		for clearance_index: int in clearance_paths.size():
			var clearance_distance := (
				_distance_to_polyline_bounded(
					position, clearance_spatial_indexes[clearance_index], 19.0
				)
				if clearance_index < clearance_spatial_indexes.size()
				else _distance_to_polyline(position, clearance_paths[clearance_index])
			)
			if clearance_distance < 19.0:
				inside_clearance = true
				break
		if inside_clearance:
			continue
		var route_distance := (
			_distance_to_polyline_bounded(position, route_spatial_index, band.y)
			if not route_spatial_index.is_empty()
			else _distance_to_polyline(position, route)
		)
		if route_distance < band.x or route_distance > band.y:
			continue
		position.y = float(height_at.call(position.x, position.z))
		var scale_value := rng.randf_range(scale_range.x, scale_range.y)
		var scale_vector := Vector3(scale_value * rng.randf_range(0.72, 1.28), scale_value, scale_value * rng.randf_range(0.72, 1.28))
		var rotation := Vector3(PI * 0.5 if lay_flat else 0.0, rng.randf_range(0.0, TAU), rng.randf_range(-0.08, 0.08))
		transforms.append(Transform3D(Basis.from_euler(rotation).scaled(scale_vector), position + Vector3.UP * (0.2 if lay_flat else 0.48 * scale_value)))
		colors.append(color_a.lerp(color_b, rng.randf()))


static func _build_spectator_zones(
	root: Node3D,
	route: PackedVector3Array,
	track_width: float,
	height_at: Callable,
	config: Dictionary,
	materials: Dictionary[StringName, StandardMaterial3D],
	rng: RandomNumberGenerator
) -> void:
	var torso_transforms: Array[Transform3D] = []
	var torso_colors: Array[Color] = []
	var head_transforms: Array[Transform3D] = []
	var head_colors: Array[Color] = []
	var fractions: PackedFloat32Array = config[&"spectator_fractions"]
	var sides: PackedFloat32Array = config[&"spectator_sides"]
	for zone_index: int in fractions.size():
		var sample := _sample_polyline(route, fractions[zone_index])
		var center: Vector3 = sample[&"position"]
		var tangent: Vector3 = sample[&"tangent"]
		var right := Vector3(tangent.z, 0.0, -tangent.x).normalized()
		var side := sides[zone_index]
		var crowd_center := center + right * side * (track_width * 0.5 + 8.5)
		for person_index: int in 24:
			var row := person_index / 6
			var column := person_index % 6
			var position := crowd_center + tangent * (float(column) - 2.5) * 1.35 + right * side * float(row) * 1.45
			position.y = float(height_at.call(position.x, position.z))
			var yaw := atan2(-right.x * side, -right.z * side)
			torso_transforms.append(_scaled_transform(position + Vector3.UP * 1.08, yaw, Vector3.ONE))
			torso_colors.append(Color.from_hsv(fmod(0.04 + zone_index * 0.13 + person_index * 0.071, 1.0), 0.58, 0.86))
			head_transforms.append(_scaled_transform(position + Vector3.UP * 1.7, yaw, Vector3.ONE))
			head_colors.append(Color("d7a579").lerp(Color("8a5d43"), rng.randf() * 0.55))
		_build_bleacher(root, crowd_center + right * side * 1.8, tangent, right * side, height_at, materials, zone_index)

	var torso_mesh := BoxMesh.new()
	torso_mesh.size = Vector3(0.48, 0.72, 0.32)
	torso_mesh.material = materials[&"accent"]
	_add_partitioned_multimesh(root, "SpectatorTorsos", torso_mesh, torso_transforms, torso_colors, NEAR_VISIBILITY)
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.21
	head_mesh.height = 0.4
	head_mesh.radial_segments = 7
	head_mesh.rings = 4
	head_mesh.material = materials[&"skin"]
	_add_partitioned_multimesh(root, "SpectatorHeads", head_mesh, head_transforms, head_colors, NEAR_VISIBILITY)


static func _build_bleacher(
	root: Node3D,
	center: Vector3,
	tangent: Vector3,
	away: Vector3,
	height_at: Callable,
	materials: Dictionary[StringName, StandardMaterial3D],
	zone_index: int
) -> void:
	var yaw := atan2(tangent.x, tangent.z)
	for row: int in 4:
		var position := center + away * float(row) * 0.9
		position.y = float(height_at.call(position.x, position.z)) + 0.18 + row * 0.36
		_add_box(root, "Bleacher_%02d_%d" % [zone_index, row], Vector3(9.0, 0.28, 0.8), position, materials[&"timber"], Vector3(0.0, yaw, 0.0), false)


static func _build_start_paddock(
	root: Node3D,
	route: PackedVector3Array,
	track_width: float,
	height_at: Callable,
	config: Dictionary,
	materials: Dictionary[StringName, StandardMaterial3D],
	_rng: RandomNumberGenerator
) -> void:
	var start := route[0]
	var tangent := (route[1] - route[0]).normalized()
	var forward := Vector3(tangent.x, 0.0, tangent.z).normalized()
	var right := Vector3(forward.z, 0.0, -forward.x)
	var yaw := atan2(forward.x, forward.z)
	var start_ground := float(height_at.call(start.x, start.z))
	# Frame the complete 3x4 launch grid from the chase camera; the front row sits
	# around 10.4 m into the route with the gantry clearly beyond the full field.
	# Keep the header well above the complete chase-camera boom. At the old 4.75 m
	# height the camera crossed the visual-only header just after launch, filling
	# the view with its accent mesh even though the riding surface was clear.
	var arch_center := Vector3(start.x, start_ground, start.z) + forward * 13.5
	arch_center.y = float(height_at.call(arch_center.x, arch_center.z))
	var arch_post_height := 7.2
	var arch_header_height := 6.85
	for side: float in [-1.0, 1.0]:
		_add_box(root, "StartArchPost", Vector3(0.42, arch_post_height, 0.42), arch_center + right * side * (track_width * 0.5 + 0.8) + Vector3.UP * (arch_post_height * 0.5), materials[&"dark"], Vector3(0.0, yaw, 0.0))
	_add_box(root, "StartArchHeader", Vector3(track_width + 2.1, 0.7, 0.5), arch_center + Vector3.UP * arch_header_height, materials[&"accent"], Vector3(0.0, yaw, 0.0))

	for pit_index: int in 5:
		var z_offset := -8.0 - pit_index * 7.4
		var pit_center := start + right * (track_width * 0.5 + 9.0) + forward * z_offset
		pit_center.y = float(height_at.call(pit_center.x, pit_center.z))
		_build_tent(root, "PitTent%02d" % pit_index, pit_center, yaw, materials, pit_index)
		var trailer_center := start - right * (track_width * 0.5 + 11.5) + forward * z_offset
		trailer_center.y = float(height_at.call(trailer_center.x, trailer_center.z))
		_add_box(root, "TeamTrailer%02d" % pit_index, Vector3(4.3, 2.8, 6.0), trailer_center + Vector3.UP * 1.4, materials[&"canvas"], Vector3(0.0, yaw, 0.0), false)
		_add_box(root, "TrailerStripe%02d" % pit_index, Vector3(4.36, 0.42, 6.05), trailer_center + Vector3.UP * 1.65, materials[&"accent_secondary"], Vector3(0.0, yaw, 0.0), false)


static func _build_tent(
	root: Node3D,
	name_prefix: String,
	center: Vector3,
	yaw: float,
	materials: Dictionary[StringName, StandardMaterial3D],
	index: int
) -> void:
	var accent_key: StringName = &"accent" if index % 2 == 0 else &"accent_secondary"
	_add_box(root, name_prefix + "Canopy", Vector3(5.4, 0.32, 5.2), center + Vector3.UP * 3.1, materials[accent_key], Vector3(0.0, yaw, 0.0), false)
	for x_side: float in [-1.0, 1.0]:
		for z_side: float in [-1.0, 1.0]:
			var offset := Basis.from_euler(Vector3(0.0, yaw, 0.0)) * Vector3(x_side * 2.35, 1.55, z_side * 2.2)
			_add_box(root, name_prefix + "Pole", Vector3(0.12, 3.1, 0.12), center + offset, materials[&"dark"], Vector3(0.0, yaw, 0.0), false)


static func _build_quarry_event_village(
	root: Node3D,
	height_at: Callable,
	_config: Dictionary,
	materials: Dictionary[StringName, StandardMaterial3D],
	_rng: RandomNumberGenerator
) -> void:
	# Keep the central 62 m pickup/ramp envelope clear; place venue mass around its rim.
	for stand_index: int in 4:
		var angle := TAU * float(stand_index) / 4.0 + PI * 0.25
		var radial := Vector3(cos(angle), 0.0, sin(angle))
		var tangent := Vector3(-radial.z, 0.0, radial.x)
		var center := radial * 76.0
		center.y = float(height_at.call(center.x, center.z))
		var yaw := atan2(tangent.x, tangent.z)
		for row: int in 4:
			_add_box(root, "FreestyleStand_%d_%d" % [stand_index, row], Vector3(12.0, 0.34, 1.15), center + radial * row * 1.0 + Vector3.UP * (0.3 + row * 0.48), materials[&"timber"], Vector3(0.0, yaw, 0.0), false)
		for person_index: int in 10:
			var row := person_index / 5
			var column := person_index % 5
			var person_position := center + tangent * (float(column) - 2.0) * 1.55 + radial * (0.45 + row * 1.0)
			person_position.y += 1.15 + row * 0.48
			var shirt_key: StringName = &"accent" if (person_index + stand_index) % 2 == 0 else &"accent_secondary"
			_add_box(root, "FreestyleCrowdBody_%d_%02d" % [stand_index, person_index], Vector3(0.5, 0.72, 0.34), person_position, materials[shirt_key], Vector3(0.0, yaw + PI, 0.0), false)
			_add_box(root, "FreestyleCrowdHead_%d_%02d" % [stand_index, person_index], Vector3(0.36, 0.36, 0.36), person_position + Vector3.UP * 0.55, materials[&"skin"], Vector3(0.0, yaw + PI, 0.0), false)
		_add_box(root, "FreestyleBanner%02d" % stand_index, Vector3(8.0, 1.1, 0.16), center - radial * 1.6 + Vector3.UP * 3.0, materials[&"accent" if stand_index % 2 == 0 else &"accent_secondary"], Vector3(0.0, yaw, 0.0), false)

	# A non-colliding safety perimeter gives the bowl a venue edge without
	# stealing space from the six salvage pickups or the freestyle transfers.
	for barrier_index: int in 24:
		var angle := TAU * float(barrier_index) / 24.0
		var radial := Vector3(cos(angle), 0.0, sin(angle))
		var tangent := Vector3(-radial.z, 0.0, radial.x)
		var center := radial * 68.0
		center.y = float(height_at.call(center.x, center.z)) + 0.48
		var material_key: StringName = &"accent" if barrier_index % 2 == 0 else &"canvas"
		_add_box(root, "FreestyleBarrier%02d" % barrier_index, Vector3(5.8, 0.82, 0.7), center, materials[material_key], Vector3(0.0, atan2(tangent.x, tangent.z), 0.0), false)

	for tent_index: int in 6:
		var center := Vector3(-56.0 + tent_index * 22.0, 0.0, 79.0)
		center.y = float(height_at.call(center.x, center.z))
		_build_tent(root, "FreestyleVendor%02d" % tent_index, center, 0.0, materials, tent_index)
	for light_index: int in 8:
		var angle := TAU * float(light_index) / 8.0
		var center := Vector3(cos(angle) * 88.0, 0.0, sin(angle) * 88.0)
		center.y = float(height_at.call(center.x, center.z))
		_add_box(root, "VenueLightPole%02d" % light_index, Vector3(0.18, 8.0, 0.18), center + Vector3.UP * 4.0, materials[&"dark"], Vector3.ZERO, false)
		_add_box(root, "VenueLightBar%02d" % light_index, Vector3(2.4, 0.4, 0.45), center + Vector3.UP * 7.8, materials[&"canvas"], Vector3(0.0, -angle, 0.0), false)


static func _add_partitioned_multimesh(
	root: Node3D,
	name_prefix: String,
	mesh: Mesh,
	transforms: Array[Transform3D],
	colors: Array[Color],
	visibility_end: float
) -> void:
	var buckets: Dictionary[Vector2i, Array] = {}
	for index: int in transforms.size():
		var origin := transforms[index].origin
		var key := Vector2i(floori(origin.x / CELL_SIZE), floori(origin.z / CELL_SIZE))
		if not buckets.has(key):
			buckets[key] = []
		buckets[key].append(index)
	for key: Vector2i in buckets:
		var indices: Array = buckets[key]
		if indices.is_empty():
			continue
		var center := Vector3((key.x + 0.5) * CELL_SIZE, 0.0, (key.y + 0.5) * CELL_SIZE)
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.mesh = mesh
		multimesh.instance_count = indices.size()
		for local_index: int in indices.size():
			var source_index: int = indices[local_index]
			var transform := transforms[source_index]
			transform.origin -= center
			multimesh.set_instance_transform(local_index, transform)
			multimesh.set_instance_color(local_index, colors[source_index] if source_index < colors.size() else Color.WHITE)
		var instance := MultiMeshInstance3D.new()
		instance.name = "%s_%d_%d" % [name_prefix, key.x, key.y]
		instance.multimesh = multimesh
		instance.position = center
		instance.visibility_range_end = visibility_end
		instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(instance)


static func _batch_static_box_decor(root: Node3D) -> void:
	# Venue props are deliberately collision-free, but were previously hundreds
	# of individual BoxMesh draw submissions. Collapse direct decorative boxes
	# into spatial/material MultiMeshes while retaining their authored transforms,
	# color palette, shadows, and distance culling.
	var buckets: Dictionary = {}
	var originals: Array[MeshInstance3D] = []
	for child: Node in root.get_children():
		if not child is MeshInstance3D:
			continue
		var instance := child as MeshInstance3D
		var box := instance.mesh as BoxMesh
		if box == null or instance.material_override == null or instance.get_child_count() > 0:
			continue
		var cell := Vector2i(
			floori(instance.position.x / CELL_SIZE),
			floori(instance.position.z / CELL_SIZE)
		)
		var shadow_mode := int(instance.cast_shadow)
		var key := "%d:%d:%d:%d" % [
			instance.material_override.get_instance_id(), shadow_mode, cell.x, cell.y
		]
		if not buckets.has(key):
			buckets[key] = {
				&"material": instance.material_override,
				&"shadow_mode": shadow_mode,
				&"cell": cell,
			&"transforms": [],
		}
		var center := Vector3((cell.x + 0.5) * CELL_SIZE, 0.0, (cell.y + 0.5) * CELL_SIZE)
		var transform := instance.transform
		# Box dimensions are local to the authored rotation. Basis.scaled() applies
		# them in parent axes, which shears every rotated non-uniform box when it is
		# folded into a MultiMesh (the start gantry became a giant diagonal slab).
		transform.basis = transform.basis * Basis.from_scale(box.size)
		transform.origin -= center
		(buckets[key][&"transforms"] as Array).append(transform)
		originals.append(instance)
	for original: MeshInstance3D in originals:
		root.remove_child(original)
		original.free()
	var bucket_index := 0
	for key: String in buckets:
		var bucket: Dictionary = buckets[key]
		var transforms: Array = bucket[&"transforms"]
		if transforms.is_empty():
			continue
		var unit_box := BoxMesh.new()
		unit_box.size = Vector3.ONE
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = unit_box
		multimesh.instance_count = transforms.size()
		for index: int in transforms.size():
			multimesh.set_instance_transform(index, transforms[index] as Transform3D)
		var cell: Vector2i = bucket[&"cell"]
		var batched := MultiMeshInstance3D.new()
		batched.name = "VenueBoxBatch%03d" % bucket_index
		batched.multimesh = multimesh
		batched.material_override = bucket[&"material"] as Material
		batched.cast_shadow = int(bucket[&"shadow_mode"])
		batched.position = Vector3((cell.x + 0.5) * CELL_SIZE, 0.0, (cell.y + 0.5) * CELL_SIZE)
		batched.visibility_range_end = NEAR_VISIBILITY
		batched.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		root.add_child(batched)
		bucket_index += 1
	root.set_meta(&"batched_decor_source_count", originals.size())
	root.set_meta(&"batched_decor_draw_groups", bucket_index)


static func _resample_polyline(points: PackedVector3Array, spacing: float) -> Array[Dictionary]:
	var samples: Array[Dictionary] = []
	if points.size() < 2:
		return samples
	var safe_spacing := maxf(spacing, 1.0)
	var distance_until_sample := 0.0
	for segment_index: int in range(points.size() - 1):
		var cursor := points[segment_index]
		var end := points[segment_index + 1]
		var delta := end - cursor
		var segment_length := delta.length()
		if segment_length < 0.001:
			continue
		var tangent := delta / segment_length
		while segment_length + 0.0001 >= distance_until_sample:
			var position := cursor + tangent * distance_until_sample
			samples.append({&"position": position, &"tangent": tangent})
			cursor = position
			segment_length = cursor.distance_to(end)
			distance_until_sample = safe_spacing
		distance_until_sample -= segment_length
	var final_delta := points[-1] - points[-2]
	if samples.is_empty() or samples[-1][&"position"].distance_to(points[-1]) > safe_spacing * 0.35:
		samples.append({&"position": points[-1], &"tangent": final_delta.normalized()})
	return samples


static func _decimate_polyline(points: PackedVector3Array, spacing: float) -> PackedVector3Array:
	var result := PackedVector3Array()
	for sample: Dictionary in _resample_polyline(points, spacing):
		result.append(sample[&"position"])
	if result.size() == 1 and points.size() > 1:
		result.append(points[-1])
	return result


static func _sample_polyline(points: PackedVector3Array, ratio: float) -> Dictionary:
	var total_length := 0.0
	for index: int in range(points.size() - 1):
		total_length += points[index].distance_to(points[index + 1])
	var target := clampf(ratio, 0.0, 1.0) * total_length
	var traversed := 0.0
	for index: int in range(points.size() - 1):
		var start := points[index]
		var end := points[index + 1]
		var length := start.distance_to(end)
		if traversed + length >= target:
			var weight := (target - traversed) / maxf(length, 0.001)
			return {&"position": start.lerp(end, weight), &"tangent": (end - start).normalized()}
		traversed += length
	return {&"position": points[-1], &"tangent": (points[-1] - points[-2]).normalized()}


static func _distance_to_polyline(point: Vector3, points: PackedVector3Array) -> float:
	var nearest := INF
	for index: int in range(points.size() - 1):
		var start := Vector2(points[index].x, points[index].z)
		var end := Vector2(points[index + 1].x, points[index + 1].z)
		var target := Vector2(point.x, point.z)
		var segment := end - start
		var weight := clampf((target - start).dot(segment) / maxf(segment.length_squared(), 0.001), 0.0, 1.0)
		nearest = minf(nearest, target.distance_to(start + segment * weight))
	return nearest


static func _build_polyline_spatial_index(points: PackedVector3Array) -> Dictionary:
	var buckets: Dictionary[Vector2i, Array] = {}
	if points.size() < 2:
		return {&"points": points, &"buckets": buckets, &"cell_size": POLYLINE_INDEX_CELL_SIZE}
	for segment_index: int in range(points.size() - 1):
		var start := points[segment_index]
		var end := points[segment_index + 1]
		var minimum_cell := Vector2i(
			floori(minf(start.x, end.x) / POLYLINE_INDEX_CELL_SIZE),
			floori(minf(start.z, end.z) / POLYLINE_INDEX_CELL_SIZE)
		)
		var maximum_cell := Vector2i(
			floori(maxf(start.x, end.x) / POLYLINE_INDEX_CELL_SIZE),
			floori(maxf(start.z, end.z) / POLYLINE_INDEX_CELL_SIZE)
		)
		for cell_x: int in range(minimum_cell.x, maximum_cell.x + 1):
			for cell_y: int in range(minimum_cell.y, maximum_cell.y + 1):
				var cell := Vector2i(cell_x, cell_y)
				if not buckets.has(cell):
					buckets[cell] = []
				buckets[cell].append(segment_index)
	return {
		&"points": points,
		&"buckets": buckets,
		&"cell_size": POLYLINE_INDEX_CELL_SIZE,
	}


static func _distance_to_polyline_bounded(
	point: Vector3,
	spatial_index: Dictionary,
	maximum_distance: float
) -> float:
	if spatial_index.is_empty() or maximum_distance < 0.0:
		return INF
	var points: PackedVector3Array = spatial_index.get(&"points", PackedVector3Array())
	var buckets: Dictionary = spatial_index.get(&"buckets", {})
	if points.size() < 2 or buckets.is_empty():
		return INF
	var cell_size := float(spatial_index.get(&"cell_size", POLYLINE_INDEX_CELL_SIZE))
	var minimum_cell := Vector2i(
		floori((point.x - maximum_distance) / cell_size),
		floori((point.z - maximum_distance) / cell_size)
	)
	var maximum_cell := Vector2i(
		floori((point.x + maximum_distance) / cell_size),
		floori((point.z + maximum_distance) / cell_size)
	)
	var nearest := INF
	for cell_x: int in range(minimum_cell.x, maximum_cell.x + 1):
		for cell_y: int in range(minimum_cell.y, maximum_cell.y + 1):
			var cell := Vector2i(cell_x, cell_y)
			if not buckets.has(cell):
				continue
			var segment_indices: Array = buckets[cell]
			for raw_segment_index: Variant in segment_indices:
				var segment_index := int(raw_segment_index)
				nearest = minf(
					nearest,
					_distance_to_segment_2d(
						point, points[segment_index], points[segment_index + 1]
					)
				)
	return nearest if nearest <= maximum_distance else INF


static func _polyline_has_nonlocal_segment_within(
	point: Vector3,
	spatial_index: Dictionary,
	maximum_distance: float,
	source_index: int,
	local_exclusion_samples: int
) -> bool:
	var points: PackedVector3Array = spatial_index.get(&"points", PackedVector3Array())
	var buckets: Dictionary = spatial_index.get(&"buckets", {})
	if points.size() < 2 or buckets.is_empty():
		return false
	var cell_size := float(spatial_index.get(&"cell_size", POLYLINE_INDEX_CELL_SIZE))
	var minimum_cell := Vector2i(
		floori((point.x - maximum_distance) / cell_size),
		floori((point.z - maximum_distance) / cell_size)
	)
	var maximum_cell := Vector2i(
		floori((point.x + maximum_distance) / cell_size),
		floori((point.z + maximum_distance) / cell_size)
	)
	for cell_x: int in range(minimum_cell.x, maximum_cell.x + 1):
		for cell_y: int in range(minimum_cell.y, maximum_cell.y + 1):
			var cell := Vector2i(cell_x, cell_y)
			if not buckets.has(cell):
				continue
			var segment_indices: Array = buckets[cell]
			for raw_segment_index: Variant in segment_indices:
				var segment_index := int(raw_segment_index)
				if (
					segment_index >= source_index - local_exclusion_samples
					and segment_index <= source_index + local_exclusion_samples
				):
					continue
				if _distance_to_segment_2d(
					point, points[segment_index], points[segment_index + 1]
				) < maximum_distance:
					return true
	return false


static func _scaled_transform(position: Vector3, yaw: float, scale_value: Vector3) -> Transform3D:
	# Scale in the prop's local axes so long fence panels follow the course yaw
	# instead of stretching across it in parent/world axes.
	var rotation_basis := Basis.from_euler(Vector3(0.0, yaw, 0.0))
	return Transform3D(rotation_basis * Basis.from_scale(scale_value), position)


static func _add_box(
	parent: Node3D,
	node_name: String,
	size: Vector3,
	position: Vector3,
	material: StandardMaterial3D,
	rotation: Vector3 = Vector3.ZERO,
	cast_shadow: bool = true
) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = box
	instance.position = position
	instance.rotation = rotation
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance


static func _material(color: Color, roughness: float, vertex_color: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.vertex_color_use_as_albedo = vertex_color
	return material
