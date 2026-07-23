extends Node3D
## Focused production regression for the duplicated Red Mesa start/finish seam.
##
## The closed route intentionally carries its first point twice. Both aliases must
## produce the same spline tangent, surface frame, visual row, and collision row;
## otherwise the lap transition becomes a gap/overlap wedge that can catch a bike.

const COURSE_CATALOG_SCRIPT := preload("res://features/race/course_catalog.gd")
const COURSE_SURFACE_BUILDER_SCRIPT := preload("res://features/environment/course_surface_builder.gd")
const MESA_BUILDER_SCRIPT := preload("res://levels/mesa_mx/mesa_mx_builder.gd")

const C1_MAX_ANGLE_DEGREES := 2.0
const POSITION_TOLERANCE := 0.002
const FRAME_TOLERANCE := 0.0001
const VERTEX_TOLERANCE := 0.0005
const PHYSICS_LANE_RATIOS := [-0.32, 0.0, 0.32]
const SUPPORT_RAY_HEIGHT := 2.5
const SWEEP_CLEARANCE := 0.82
const SWEEP_RADIUS := 0.28

var _failures: Array[String] = []


func _ready() -> void:
	print("CLOSED LOOP SEAM PROBE: loading production route")
	var mesa_builder := MESA_BUILDER_SCRIPT.new() as Node3D
	var surface_config := mesa_builder.call(&"_surface_config") as Dictionary
	mesa_builder.free()

	var route: PackedVector3Array = COURSE_CATALOG_SCRIPT.get_local_riding_points(
		COURSE_CATALOG_SCRIPT.MESA_MX_ID
	)
	var width: float = COURSE_CATALOG_SCRIPT.get_track_width(COURSE_CATALOG_SCRIPT.MESA_MX_ID)
	_check(route.size() >= 9, "Mesa route needs enough samples for a closed seam audit")
	if route.size() < 9:
		_finish(0.0, 0.0, 0.0, 0)
		return

	var closure_error := route[0].distance_to(route[-1])
	_check(
		closure_error <= POSITION_TOLERANCE,
		"baked route endpoints differ by %.6f m" % closure_error
	)

	# Adjacent segments are the discrete approximation of the analytic derivatives
	# on either side of the duplicated anchor. The finish-tangent steering keeps
	# them C1 while preserving the launch chute on the opening segment.
	var incoming := (route[-1] - route[-2]).normalized()
	var outgoing := (route[1] - route[0]).normalized()
	var c1_dot := clampf(incoming.dot(outgoing), -1.0, 1.0)
	var c1_angle := rad_to_deg(acos(c1_dot))
	_check(
		c1_angle <= C1_MAX_ANGLE_DEGREES,
		"baked seam is not C1-aligned: incoming/outgoing angle %.4f degrees" % c1_angle
	)

	var frames: Array[Dictionary] = COURSE_SURFACE_BUILDER_SCRIPT._build_frames(
		route, width, surface_config
	)
	_check(frames.size() == route.size(), "surface frame count does not match the production route")
	if frames.size() != route.size():
		_finish(closure_error, c1_angle, INF, 0)
		return

	var maximum_frame_error := _audit_frame_aliases(frames)
	print("CLOSED LOOP SEAM PROBE: frame aliases audited")
	var profile_report := _audit_profile_aliases(frames, width, surface_config)
	print("CLOSED LOOP SEAM PROBE: profile aliases audited")
	var maximum_vertex_error := float(profile_report.get(&"maximum_error", INF))
	var profile_checks := int(profile_report.get(&"checks", 0))

	var physics_report := await _audit_physics_transition(route, frames, width, surface_config)
	var physics_sweeps := int(physics_report.get(&"sweeps", 0))
	var physics_supports := int(physics_report.get(&"supports", 0))
	_finish(
		closure_error,
		c1_angle,
		maxf(maximum_frame_error, maximum_vertex_error),
		profile_checks,
		physics_sweeps,
		physics_supports
	)


func _audit_frame_aliases(frames: Array[Dictionary]) -> float:
	var first: Dictionary = frames[0]
	var last: Dictionary = frames[-1]
	var maximum_error := 0.0
	for key: StringName in [&"position", &"tangent", &"right", &"up"]:
		var first_vector := first[key] as Vector3
		var last_vector := last[key] as Vector3
		var error := first_vector.distance_to(last_vector)
		maximum_error = maxf(maximum_error, error)
		_check(error <= FRAME_TOLERANCE, "first/last frame %s differs by %.6f" % [String(key), error])
	var curvature_error := absf(float(first[&"curvature"]) - float(last[&"curvature"]))
	maximum_error = maxf(maximum_error, curvature_error)
	_check(
		curvature_error <= FRAME_TOLERANCE,
		"first/last frame curvature differs by %.6f" % curvature_error
	)
	return maximum_error


func _audit_profile_aliases(
	frames: Array[Dictionary],
	width: float,
	config: Dictionary
) -> Dictionary:
	var visual_profile := COURSE_SURFACE_BUILDER_SCRIPT._visual_track_profile(width, config) as Dictionary
	var collision_profile := COURSE_SURFACE_BUILDER_SCRIPT._collision_track_profile(width, config) as Dictionary
	var maximum_error := 0.0
	var checks := 0

	# Read the actual ArrayMesh vertex buffer so the regression covers the rendered
	# row, not merely a duplicate of its vertex formula in this probe.
	var visual_offsets: PackedFloat32Array = visual_profile[&"offsets"]
	var visual_heights: PackedFloat32Array = visual_profile[&"heights"]
	var visual_mesh: ArrayMesh = COURSE_SURFACE_BUILDER_SCRIPT._create_strip_mesh(
		frames,
		0,
		frames.size() - 1,
		visual_offsets,
		visual_heights,
		width,
		null
	)
	var visual_arrays: Array = visual_mesh.surface_get_arrays(0)
	var visual_vertices := visual_arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	for column: int in visual_offsets.size():
		var first_vertex := visual_vertices[column]
		var last_vertex := visual_vertices[(frames.size() - 1) * visual_offsets.size() + column]
		var error := first_vertex.distance_to(last_vertex)
		maximum_error = maxf(maximum_error, error)
		checks += 1
		_check(
			error <= VERTEX_TOLERANCE,
			"visual seam vertex at offset %+.3f m differs by %.6f m" % [visual_offsets[column], error]
		)

	# Collision is emitted as triangle faces, so use the production strip-vertex
	# helper for its logical first and terminal rows. This covers shoulders, edges,
	# ruts, lanes, and the crowned center point.
	var collision_offsets: PackedFloat32Array = collision_profile[&"offsets"]
	var collision_heights: PackedFloat32Array = collision_profile[&"heights"]
	var collapse_height := _maximum_value(collision_heights)
	for column: int in collision_offsets.size():
		var first_vertex: Vector3 = COURSE_SURFACE_BUILDER_SCRIPT._strip_vertex_for_frame(
			frames[0], collision_offsets[column], collision_heights[column], collapse_height, width
		)
		var last_vertex: Vector3 = COURSE_SURFACE_BUILDER_SCRIPT._strip_vertex_for_frame(
			frames[-1], collision_offsets[column], collision_heights[column], collapse_height, width
		)
		var error := first_vertex.distance_to(last_vertex)
		maximum_error = maxf(maximum_error, error)
		checks += 1
		_check(
			error <= VERTEX_TOLERANCE,
			"collision seam vertex at offset %+.3f m differs by %.6f m" % [collision_offsets[column], error]
		)

	# At every shared track offset, visible dirt and load-bearing collision must
	# agree at both aliases as well as agreeing across the seam.
	for visual_column: int in visual_offsets.size():
		var collision_column := _find_offset(collision_offsets, visual_offsets[visual_column])
		_check(collision_column >= 0, "collision profile omits visual offset %+.3f m" % visual_offsets[visual_column])
		if collision_column < 0:
			continue
		for frame_index: int in [0, frames.size() - 1]:
			var visual_vertex: Vector3 = COURSE_SURFACE_BUILDER_SCRIPT._strip_vertex_for_frame(
				frames[frame_index],
				visual_offsets[visual_column],
				visual_heights[visual_column],
				_maximum_value(visual_heights),
				width
			)
			var collision_vertex: Vector3 = COURSE_SURFACE_BUILDER_SCRIPT._strip_vertex_for_frame(
				frames[frame_index],
				collision_offsets[collision_column],
				collision_heights[collision_column],
				collapse_height,
				width
			)
			var error := visual_vertex.distance_to(collision_vertex)
			maximum_error = maxf(maximum_error, error)
			checks += 1
			_check(
				error <= VERTEX_TOLERANCE,
				"visual/collision seam profiles diverge at offset %+.3f m by %.6f m" % [
					visual_offsets[visual_column], error,
				]
			)
	return {&"maximum_error": maximum_error, &"checks": checks}


func _audit_physics_transition(
	route: PackedVector3Array,
	frames: Array[Dictionary],
	width: float,
	config: Dictionary
) -> Dictionary:
	print("CLOSED LOOP SEAM PROBE: building isolated physics ribbon")
	var material := StandardMaterial3D.new()
	var surface_root: Node3D = COURSE_SURFACE_BUILDER_SCRIPT.build(
		self,
		"ClosedLoopSeamPhysicsRibbon",
		route,
		width,
		material,
		material,
		material,
		&"DIRT",
		0.81,
		1.3,
		config
	)
	for _frame: int in 2:
		await get_tree().physics_frame
	print("CLOSED LOOP SEAM PROBE: physics ribbon active")

	var collision_body := surface_root.get_node_or_null("ContinuousRideableCollision") as StaticBody3D
	_check(collision_body != null, "production ribbon did not create its continuous collision body")
	if collision_body == null:
		return {&"sweeps": 0, &"supports": 0}

	var collision_profile := COURSE_SURFACE_BUILDER_SCRIPT._collision_track_profile(width, config) as Dictionary
	var space := get_world_3d().direct_space_state
	var sphere := SphereShape3D.new()
	sphere.radius = SWEEP_RADIUS
	var path_indices := PackedInt32Array()
	for index: int in range(route.size() - 6, route.size()):
		path_indices.append(index)
	# Include both seam aliases explicitly before entering the second lap.
	for index: int in range(0, 7):
		path_indices.append(index)

	var sweep_count := 0
	var support_count := 0
	for lane_ratio: float in PHYSICS_LANE_RATIOS:
		var lane_offset := lane_ratio * width
		var path := PackedVector3Array()
		for index: int in path_indices:
			var support := _profile_position(frames[index], lane_offset, width, collision_profile)
			path.append(support + Vector3.UP * SWEEP_CLEARANCE)
			var ray := PhysicsRayQueryParameters3D.create(
				support + Vector3.UP * SUPPORT_RAY_HEIGHT,
				support - Vector3.UP * SUPPORT_RAY_HEIGHT,
				2
			)
			var hit := space.intersect_ray(ray)
			var supported: bool = not hit.is_empty() and hit.get(&"collider") == collision_body
			_check(
				supported,
				"physics seam lost authoritative support at lane %+.2f, route index %d" % [lane_ratio, index]
			)
			if supported:
				support_count += 1
		for step: int in range(path.size() - 1):
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = sphere
			query.transform = Transform3D(Basis.IDENTITY, path[step])
			query.motion = path[step + 1] - path[step]
			query.collision_mask = 2
			query.collide_with_areas = false
			query.collide_with_bodies = true
			query.margin = 0.002
			var fractions: PackedFloat32Array = space.cast_motion(query)
			var safe_fraction := fractions[0] if not fractions.is_empty() else 0.0
			sweep_count += 1
			_check(
				safe_fraction >= 0.999,
				"physics seam blocked lane %+.2f between path samples %d and %d (safe %.4f)" % [
					lane_ratio, step, step + 1, safe_fraction,
				]
			)
	surface_root.queue_free()
	return {&"sweeps": sweep_count, &"supports": support_count}


func _profile_position(
	frame: Dictionary,
	offset: float,
	width: float,
	profile: Dictionary
) -> Vector3:
	var height: float = COURSE_SURFACE_BUILDER_SCRIPT._profile_height_at(frame, offset, width, profile)
	return (
		(frame[&"position"] as Vector3)
		+ (frame[&"right"] as Vector3) * offset
		+ (frame[&"up"] as Vector3) * height
	)


func _find_offset(offsets: PackedFloat32Array, requested: float) -> int:
	for index: int in offsets.size():
		if absf(offsets[index] - requested) <= 0.0001:
			return index
	return -1


func _maximum_value(values: PackedFloat32Array) -> float:
	var maximum := -INF
	for value: float in values:
		maximum = maxf(maximum, value)
	return maximum


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish(
	closure_error: float,
	c1_angle: float,
	maximum_alias_error: float,
	profile_checks: int,
	physics_sweeps: int = 0,
	physics_supports: int = 0
) -> void:
	if _failures.is_empty():
		print(
			"CLOSED LOOP SEAM PROBE PASS: samples=%d closure=%.6fm c1=%.4fdeg max_alias_error=%.6fm profile_checks=%d supports=%d sweeps=%d" % [
				COURSE_CATALOG_SCRIPT.get_local_riding_points(COURSE_CATALOG_SCRIPT.MESA_MX_ID).size(),
				closure_error,
				c1_angle,
				maximum_alias_error,
				profile_checks,
				physics_supports,
				physics_sweeps,
			]
		)
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("CLOSED LOOP SEAM PROBE: %s" % failure)
	print("CLOSED LOOP SEAM PROBE FAIL: failures=%d" % _failures.size())
	get_tree().quit(1)
