extends RefCounted
class_name CourseSurfaceBuilder
## Chunked continuous motocross ribbon with banking, shallow physical ruts,
## outside berm lift, tapered shoulders, and matching concave collision.

# Course ribbons are sampled close to one metre. A 224-row visual chunk remains
# comfortably below the camera's useful sight distance while halving the scene
# nodes and potential render submissions again. Collision stays one welded
# shape, and vertex/index topology is unchanged.
const DEFAULT_CHUNK_SEGMENTS := 224
const DEFAULT_OVERLAY_SEPARATION := 0.10
# Dedicated query bit for non-physical race agents. Player collision still uses
# layer 2; this extra bit lets opponents hit only the welded riding surface.
const AUTHORITATIVE_RIDE_LAYER: int = 1 << 7


static func build(
	parent: Node3D,
	node_name: String,
	centerline: PackedVector3Array,
	width: float,
	track_material: Material,
	shoulder_material: Material,
	rut_material: Material,
	surface: StringName,
	roughness: float,
	roost: float,
	config: Dictionary = {}
) -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	parent.add_child(root)
	if centerline.size() < 2:
		return root

	var frames := _build_frames(centerline, width, config)
	root.set_meta(&"surface_width", width)
	root.set_meta(&"endpoint_taper_length", float(config.get(&"endpoint_taper_length", 0.0)))
	root.set_meta(&"endpoint_minimum_width_ratio", float(config.get(&"endpoint_minimum_width_ratio", 1.0)))
	root.set_meta(&"endpoint_surface_lift", float(config.get(&"endpoint_surface_lift", 0.0)))
	root.set_meta(&"visual_centerline_size", frames.size())
	root.set_meta(&"collision_centerline_size", frames.size())
	var collision_body := StaticBody3D.new()
	collision_body.name = "ContinuousRideableCollision"
	collision_body.collision_layer = 2 | AUTHORITATIVE_RIDE_LAYER
	collision_body.collision_mask = 1
	collision_body.set_meta(&"surface", surface)
	collision_body.set_meta(&"roughness", roughness)
	collision_body.set_meta(&"roost", roost)
	root.add_child(collision_body)
	var chunk_segments := maxi(int(config.get(&"chunk_segments", DEFAULT_CHUNK_SEGMENTS)), 12)
	root.set_meta(&"chunk_segments", chunk_segments)
	var start_index := 0
	var chunk_index := 0
	while start_index < frames.size() - 1:
		var end_index := mini(start_index + chunk_segments, frames.size() - 1)
		_build_chunk(
			root,
			chunk_index,
			frames,
			start_index,
			end_index,
			width,
			track_material,
			shoulder_material,
			rut_material,
			config
		)
		start_index = end_index
		chunk_index += 1
	# Keep the rendered ribbon chunked for culling, but give physics one welded
	# concave surface. Separate shapes sharing a row produce internal edge
	# contacts in Jolt; at speed those contacts feel like an invisible curb even
	# though the vertices are numerically coincident.
	_build_continuous_collision(collision_body, frames, width, config)
	root.set_meta(&"visual_chunk_count", chunk_index)
	root.set_meta(&"collision_shape_count", 1)
	root.set_meta(&"welded_collision", true)
	return root


static func build_additive_overlay(
	parent: Node3D,
	node_name: String,
	centerline: PackedVector3Array,
	base_width: float,
	overlay_width: float,
	route_index: int,
	requested_length: float,
	relief_height: float,
	rises_with_travel: bool,
	material: Material,
	surface: StringName,
	roughness: float,
	roost: float,
	config: Dictionary,
	minimum_separation: float = DEFAULT_OVERLAY_SEPARATION,
	prebuilt_frames: Array[Dictionary] = [],
	rut_material: Material = null,
	lateral_offset: float = 0.0
) -> StaticBody3D:
	## Builds an open, top-only surface over the exact banked course profile.
	##
	## The overlay and its private base envelope use identical topology and XZ
	## coordinates. Relief is added in global +Y, so every point inside every
	## triangle retains at least `minimum_separation` from both the visible and
	## physical ribbon profiles; there is no wedge/ribbon intersection line.
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = 2 | AUTHORITATIVE_RIDE_LAYER
	body.collision_mask = 1
	body.set_meta(&"surface", surface)
	body.set_meta(&"roughness", roughness)
	body.set_meta(&"roost", roost)
	body.set_meta(&"collision_top_only", true)
	body.set_meta(&"open_ride_ends", true)
	body.set_meta(&"bank_aware_overlay", true)
	body.set_meta(&"minimum_base_separation", minimum_separation)
	parent.add_child(body)
	if centerline.size() < 2:
		return body

	var frames: Array[Dictionary]
	if prebuilt_frames.size() == centerline.size():
		frames = prebuilt_frames
	else:
		frames = _build_frames(centerline, base_width, config)
	var safe_route_index := clampi(route_index, 0, frames.size() - 1)
	var frame_range := _overlay_frame_range(frames, safe_route_index, requested_length)
	var start_index: int = frame_range.x
	var end_index: int = frame_range.y
	var half_base_width := maxf(base_width * 0.5, 0.5)
	var half_overlay_width := clampf(overlay_width * 0.5, 0.5, half_base_width)
	var overlay_center_offset := clampf(
		lateral_offset,
		-half_base_width + half_overlay_width,
		half_base_width - half_overlay_width
	)
	var overlay_min_offset := overlay_center_offset - half_overlay_width
	var overlay_max_offset := overlay_center_offset + half_overlay_width
	var offsets := _overlay_offsets(
		base_width, overlay_width, config, overlay_center_offset
	)
	var visual_profile := _visual_track_profile(base_width, config)
	var collision_profile := _collision_track_profile(base_width, config)
	var row_count := end_index - start_index + 1
	var column_count := offsets.size()
	var vertices := PackedVector3Array()
	var base_vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	vertices.resize(row_count * column_count)
	base_vertices.resize(row_count * column_count)
	normals.resize(row_count * column_count)
	uvs.resize(row_count * column_count)
	var start_distance: float = frames[start_index][&"distance"]
	var end_distance: float = frames[end_index][&"distance"]
	var actual_length := maxf(end_distance - start_distance, 0.001)
	var lateral_blend_width := _overlay_lateral_blend_width(half_overlay_width, config)
	var verified_minimum := INF
	for row: int in row_count:
		var frame: Dictionary = frames[start_index + row]
		var frame_distance: float = frame[&"distance"]
		var weight := clampf((frame_distance - start_distance) / actual_length, 0.0, 1.0)
		var relief_ratio := (
			_progressive_overlay_ratio(weight)
			if rises_with_travel
			else _receiver_overlay_ratio(weight)
		)
		var relief := maxf(relief_height, 0.0) * relief_ratio
		# The first/last rows need to be exactly flush with the ribbon. The old
		# 0.06 m minimum made every otherwise open ramp end a physical wheel lip.
		# Ease toward the requested interior render bias; broad dirt ramps request
		# 8 mm, while the timber deck retains its visibly raised interior.
		var endpoint_blend := minf(
			smoothstep(0.0, 0.14, weight),
			smoothstep(0.0, 0.14, 1.0 - weight)
		)
		var base_separation := maxf(minimum_separation, 0.0) * endpoint_blend
		var position: Vector3 = frame[&"position"]
		var right: Vector3 = frame[&"right"]
		var up: Vector3 = frame[&"up"]
		for column: int in column_count:
			var offset := offsets[column]
			var edge_distance := maxf(
				minf(offset - overlay_min_offset, overlay_max_offset - offset),
				0.0
			)
			var lateral_relief_blend := smoothstep(0.0, lateral_blend_width, edge_distance)
			var visual_height := _profile_height_at(frame, offset, base_width, visual_profile)
			var collision_height := _profile_height_at(frame, offset, base_width, collision_profile)
			var envelope_height := maxf(visual_height, collision_height)
			var base_vertex := position + right * offset + up * envelope_height
			# Feather jump relief into the surrounding ribbon at both side edges.
			# Full-width vertical cliffs looked like mesh cut-through from oblique
			# cameras; the central race lanes retain the complete authored height.
			# Both side boundaries share the exact base-ribbon vertices. Only the
			# dirt volume inside those boundaries rises, so there is no floating side
			# band or collision curb where a recovery line meets the jump.
			var separation := (base_separation + relief) * lateral_relief_blend
			var vertex_index := row * column_count + column
			base_vertices[vertex_index] = base_vertex
			vertices[vertex_index] = base_vertex + Vector3.UP * separation
			uvs[vertex_index] = Vector2(offset / maxf(base_width, 0.1) + 0.5, frame_distance / 7.0)
			verified_minimum = minf(verified_minimum, vertices[vertex_index].y - base_vertex.y)
	for row: int in row_count:
		var expected_up: Vector3 = frames[start_index + row][&"up"]
		for column: int in column_count:
			var previous_row := maxi(row - 1, 0)
			var next_row := mini(row + 1, row_count - 1)
			var previous_column := maxi(column - 1, 0)
			var next_column := mini(column + 1, column_count - 1)
			var along := vertices[next_row * column_count + column] - vertices[previous_row * column_count + column]
			var across := vertices[row * column_count + next_column] - vertices[row * column_count + previous_column]
			var normal := across.cross(along).normalized()
			if normal.dot(expected_up) < 0.0:
				normal = -normal
			normals[row * column_count + column] = normal if normal.length_squared() > 0.1 else expected_up
	var indices := _strip_indices(row_count, column_count)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	var visual := MeshInstance3D.new()
	visual.name = "OverlaySurface"
	visual.mesh = mesh
	body.add_child(visual)
	if rut_material != null:
		_add_overlay_rut_visuals(
			body, vertices, normals, offsets, row_count, column_count,
			base_width, config, rut_material, overlay_center_offset,
			half_overlay_width
		)

	var faces := PackedVector3Array()
	faces.resize(indices.size())
	for index: int in indices.size():
		faces[index] = vertices[indices[index]]
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = false
	shape.set_faces(faces)
	var collision := CollisionShape3D.new()
	collision.name = "OverlayTopCollision"
	collision.shape = shape
	body.add_child(collision)

	body.set_meta(&"overlay_start_index", start_index)
	body.set_meta(&"overlay_end_index", end_index)
	body.set_meta(&"overlay_row_count", row_count)
	body.set_meta(&"overlay_column_count", column_count)
	body.set_meta(&"overlay_offsets", offsets)
	body.set_meta(&"overlay_lateral_offset", overlay_center_offset)
	body.set_meta(&"overlay_min_offset", overlay_min_offset)
	body.set_meta(&"overlay_max_offset", overlay_max_offset)
	body.set_meta(&"overlay_base_vertices", base_vertices)
	body.set_meta(&"verified_minimum_separation", verified_minimum)
	body.set_meta(&"minimum_base_separation", verified_minimum)
	body.set_meta(&"actual_overlay_length", actual_length)
	return body


static func _add_overlay_rut_visuals(
	body: StaticBody3D,
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	offsets: PackedFloat32Array,
	row_count: int,
	column_count: int,
	base_width: float,
	config: Dictionary,
	material: Material,
	overlay_center_offset: float,
	overlay_half_width: float
) -> void:
	var half_width := base_width * 0.5
	var rut_offset := minf(float(config.get(&"rut_offset", 1.15)), half_width * 0.58)
	var rut_half_width := float(config.get(&"rut_half_width", 0.2)) * 0.72
	var inner_rut_offset := minf(rut_offset, overlay_half_width * 0.28)
	var outer_rut_offset := minf(2.15, overlay_half_width * 0.43)
	var centers: Array[float] = [
		overlay_center_offset - outer_rut_offset,
		overlay_center_offset - inner_rut_offset,
		overlay_center_offset + inner_rut_offset,
		overlay_center_offset + outer_rut_offset,
	]
	for rut_index: int in centers.size():
		var center := centers[rut_index]
		var strip_vertices := PackedVector3Array()
		var strip_normals := PackedVector3Array()
		var strip_uvs := PackedVector2Array()
		strip_vertices.resize(row_count * 2)
		strip_normals.resize(row_count * 2)
		strip_uvs.resize(row_count * 2)
		for row: int in row_count:
			for side: int in 2:
				var target_offset := center + (-rut_half_width if side == 0 else rut_half_width)
				var sample := _sample_overlay_row(
					vertices, normals, offsets, row, column_count, target_offset
				)
				var vertex_index := row * 2 + side
				var normal: Vector3 = sample[&"normal"]
				strip_vertices[vertex_index] = (sample[&"position"] as Vector3) + normal * 0.006
				strip_normals[vertex_index] = normal
				strip_uvs[vertex_index] = Vector2(float(side), float(row) * 0.15)
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = strip_vertices
		arrays[Mesh.ARRAY_NORMAL] = strip_normals
		arrays[Mesh.ARRAY_TEX_UV] = strip_uvs
		arrays[Mesh.ARRAY_INDEX] = _strip_indices(row_count, 2)
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, material)
		var visual := MeshInstance3D.new()
		visual.name = "OverlayRut%02d" % rut_index
		visual.mesh = mesh
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(visual)


static func _sample_overlay_row(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	offsets: PackedFloat32Array,
	row: int,
	column_count: int,
	target_offset: float
) -> Dictionary:
	var clamped := clampf(target_offset, offsets[0], offsets[-1])
	for column: int in range(column_count - 1):
		if clamped <= offsets[column + 1]:
			var weight := inverse_lerp(offsets[column], offsets[column + 1], clamped)
			var first := row * column_count + column
			var second := first + 1
			return {
				&"position": vertices[first].lerp(vertices[second], weight),
				&"normal": normals[first].lerp(normals[second], weight).normalized(),
			}
	var final := row * column_count + column_count - 1
	return {&"position": vertices[final], &"normal": normals[final]}


static func overlay_surface_transform(
	centerline: PackedVector3Array,
	base_width: float,
	config: Dictionary,
	route_index: int,
	vertical_separation: float = DEFAULT_OVERLAY_SEPARATION,
	prebuilt_frames: Array[Dictionary] = []
) -> Transform3D:
	## Centerline transform used by bridge planks and other matching decoration.
	var frames: Array[Dictionary]
	if prebuilt_frames.size() == centerline.size():
		frames = prebuilt_frames
	else:
		frames = _build_frames(centerline, base_width, config)
	if frames.is_empty():
		return Transform3D.IDENTITY
	var frame: Dictionary = frames[clampi(route_index, 0, frames.size() - 1)]
	var visual_profile := _visual_track_profile(base_width, config)
	var collision_profile := _collision_track_profile(base_width, config)
	var visual_height := _profile_height_at(frame, 0.0, base_width, visual_profile)
	var collision_height := _profile_height_at(frame, 0.0, base_width, collision_profile)
	var origin: Vector3 = frame[&"position"]
	var right: Vector3 = frame[&"right"]
	var up: Vector3 = frame[&"up"]
	var tangent: Vector3 = frame[&"tangent"]
	origin += up * maxf(visual_height, collision_height)
	origin += Vector3.UP * maxf(vertical_separation, 0.06)
	return Transform3D(Basis(right, up, -tangent).orthonormalized(), origin)


static func _overlay_frame_range(
	frames: Array[Dictionary],
	center_index: int,
	requested_length: float
) -> Vector2i:
	var safe_center := clampi(center_index, 0, frames.size() - 1)
	var half_length := maxf(requested_length, 2.0) * 0.5
	var center_distance: float = frames[safe_center][&"distance"]
	var start_index := safe_center
	var end_index := safe_center
	while start_index > 0 and center_distance - float(frames[start_index][&"distance"]) < half_length:
		start_index -= 1
	while end_index < frames.size() - 1 and float(frames[end_index][&"distance"]) - center_distance < half_length:
		end_index += 1
	while end_index - start_index < 2 and (start_index > 0 or end_index < frames.size() - 1):
		if start_index > 0:
			start_index -= 1
		if end_index < frames.size() - 1 and end_index - start_index < 2:
			end_index += 1
	return Vector2i(start_index, end_index)


static func _overlay_offsets(
	base_width: float,
	overlay_width: float,
	config: Dictionary,
	lateral_offset: float = 0.0
) -> PackedFloat32Array:
	var half_base := base_width * 0.5
	var half_overlay := clampf(overlay_width * 0.5, 0.5, half_base)
	var center_offset := clampf(
		lateral_offset,
		-half_base + half_overlay,
		half_base - half_overlay
	)
	var minimum_offset := center_offset - half_overlay
	var maximum_offset := center_offset + half_overlay
	var lateral_blend_width := _overlay_lateral_blend_width(half_overlay, config)
	# Relief is intended to stay full across the riding lanes and feather only in
	# the final side band. These boundary columns are structural: without them,
	# the mesh linearly interpolates from the last rut-profile column to the edge,
	# spreading a two-metre feather across most of a broad jump and leaving outer
	# race lines with a low, abrupt launch lip.
	var candidates: Array[float] = [
		minimum_offset,
		minimum_offset + lateral_blend_width,
		center_offset,
		maximum_offset - lateral_blend_width,
		maximum_offset,
	]
	var visual_profile := _visual_track_profile(base_width, config)
	var collision_profile := _collision_track_profile(base_width, config)
	for profile: Dictionary in [visual_profile, collision_profile]:
		var profile_offsets: PackedFloat32Array = profile[&"offsets"]
		for offset: float in profile_offsets:
			if offset > minimum_offset + 0.0001 and offset < maximum_offset - 0.0001:
				candidates.append(offset)
	candidates.sort()
	var offsets := PackedFloat32Array()
	for offset: float in candidates:
		if offsets.is_empty() or absf(offset - offsets[-1]) > 0.0001:
			offsets.append(offset)
	return offsets


static func _overlay_lateral_blend_width(half_overlay_width: float, config: Dictionary) -> float:
	var requested := maxf(float(config.get(&"overlay_lateral_blend_width", 2.0)), 0.1)
	return minf(requested, half_overlay_width * 0.8)


static func _visual_track_profile(width: float, config: Dictionary) -> Dictionary:
	var half_width := width * 0.5
	var rut_offset := minf(float(config.get(&"rut_offset", 1.15)), half_width * 0.58)
	var rut_half_width := float(config.get(&"rut_half_width", 0.2))
	# Cosmetic grooves used to sit as much as 37 mm below the physical ribbon,
	# while the crown sat 35 mm above it. That guaranteed visible tyre clipping
	# and an invisible lip across each rut. The load-bearing mesh is now the exact
	# visible profile; separate dark rut strips provide the extra visual depth.
	var rut_depth := minf(
		float(config.get(&"rut_depth", 0.04)),
		float(config.get(&"physical_rut_depth", 0.024))
	)
	return {
		&"offsets": PackedFloat32Array([
			-half_width,
			-rut_offset - rut_half_width,
			-rut_offset,
			-rut_offset + rut_half_width,
			0.0,
			rut_offset - rut_half_width,
			rut_offset,
			rut_offset + rut_half_width,
			half_width,
		]),
		&"heights": PackedFloat32Array([
			-0.055, 0.018, -rut_depth, 0.018, 0.04,
			0.018, -rut_depth, 0.018, -0.055,
		]),
	}


static func _collision_track_profile(width: float, config: Dictionary) -> Dictionary:
	var half_width := width * 0.5
	var shoulder_width := float(config.get(&"shoulder_width", 2.0))
	var rut_offset := minf(float(config.get(&"rut_offset", 1.15)), half_width * 0.58)
	var rut_half_width := float(config.get(&"rut_half_width", 0.2))
	var rut_depth := minf(float(config.get(&"physical_rut_depth", 0.024)), 0.028)
	return {
		&"offsets": PackedFloat32Array([
			-half_width - shoulder_width,
			-half_width,
			-rut_offset - rut_half_width,
			-rut_offset,
			-rut_offset + rut_half_width,
			0.0,
			rut_offset - rut_half_width,
			rut_offset,
			rut_offset + rut_half_width,
			half_width,
			half_width + shoulder_width,
		]),
		&"heights": PackedFloat32Array([
			-0.5, -0.055, 0.018, -rut_depth, 0.018, 0.04,
			0.018, -rut_depth, 0.018, -0.055, -0.5,
		]),
	}


static func _profile_height_at(
	frame: Dictionary,
	offset: float,
	width: float,
	profile: Dictionary
) -> float:
	var offsets: PackedFloat32Array = profile[&"offsets"]
	var heights: PackedFloat32Array = profile[&"heights"]
	if offset <= offsets[0]:
		return _height_with_berm(frame, offsets[0], heights[0], width)
	for index: int in offsets.size() - 1:
		if offset <= offsets[index + 1]:
			var weight := inverse_lerp(offsets[index], offsets[index + 1], offset)
			return lerpf(
				_height_with_berm(frame, offsets[index], heights[index], width),
				_height_with_berm(frame, offsets[index + 1], heights[index + 1], width),
				weight
			)
	return _height_with_berm(frame, offsets[-1], heights[-1], width)


static func _progressive_overlay_ratio(weight: float) -> float:
	var clamped := clampf(weight, 0.0, 1.0)
	var rise := pow(clamped, 3.0)
	var settle := pow(1.0 - clamped, 3.0)
	var progressive := rise / maxf(rise + settle, 0.0001)
	return lerpf(progressive, clamped, 0.26)


static func _receiver_overlay_ratio(weight: float) -> float:
	# A landing is a dirt receiver, not a one-sided floating shelf. Rise to an
	# early crest so an under-jump meets a visible, rideable catch face, then use
	# the longer downslope for the intended landing. A restrained smooth/linear
	# blend keeps both faces rollable after a short jump instead of presenting a
	# 50+ degree collision wall to the front wheel.
	const CREST_WEIGHT := 0.38
	var clamped := clampf(weight, 0.0, 1.0)
	if clamped <= CREST_WEIGHT:
		return _receiver_transition_ratio(clamped / CREST_WEIGHT)
	return _receiver_transition_ratio(1.0 - (clamped - CREST_WEIGHT) / (1.0 - CREST_WEIGHT))


static func _receiver_transition_ratio(weight: float) -> float:
	var clamped := clampf(weight, 0.0, 1.0)
	return lerpf(smoothstep(0.0, 1.0, clamped), clamped, 0.35)


static func _build_frames(centerline: PackedVector3Array, width: float, config: Dictionary) -> Array[Dictionary]:
	var frames: Array[Dictionary] = []
	var maximum_bank := deg_to_rad(float(config.get(&"maximum_bank_degrees", 14.0)))
	var bank_strength := float(config.get(&"bank_strength", 0.48))
	var berm_height := float(config.get(&"berm_height", 0.72))
	var distance := 0.0
	var closed_loop := (
		centerline.size() >= 4
		and centerline[0].distance_to(centerline[-1]) <= 0.02
	)
	var unique_point_count := centerline.size() - 1 if closed_loop else centerline.size()
	var closed_sample_offset := mini(4, maxi((unique_point_count - 1) / 2, 1))
	for index: int in centerline.size():
		if index > 0:
			distance += centerline[index - 1].distance_to(centerline[index])
		var sample_index := 0 if closed_loop and index == centerline.size() - 1 else index
		var previous_index := (
			posmod(sample_index - closed_sample_offset, unique_point_count)
			if closed_loop
			else maxi(index - 4, 0)
		)
		var next_index := (
			posmod(sample_index + closed_sample_offset, unique_point_count)
			if closed_loop
			else mini(index + 4, centerline.size() - 1)
		)
		var incoming := centerline[sample_index] - centerline[previous_index]
		var outgoing := centerline[next_index] - centerline[sample_index]
		if incoming.length_squared() < 0.001:
			incoming = outgoing
		if outgoing.length_squared() < 0.001:
			outgoing = incoming
		incoming = incoming.normalized()
		outgoing = outgoing.normalized()
		var signed_curvature := clampf(incoming.cross(outgoing).dot(Vector3.UP), -1.0, 1.0)
		var tangent := (outgoing + incoming).normalized()
		if tangent.length_squared() < 0.1:
			tangent = CourseSpline.tangent_at(centerline, index)
		var flat_tangent := Vector3(tangent.x, 0.0, tangent.z)
		if flat_tangent.length_squared() < 0.01:
			flat_tangent = Vector3.FORWARD
		flat_tangent = flat_tangent.normalized()
		# Retain most authored grade but keep the cross-section stable on steep runs.
		tangent = Vector3(flat_tangent.x, tangent.y, flat_tangent.z).normalized()
		var flat_right := tangent.cross(Vector3.UP).normalized()
		if flat_right.length_squared() < 0.1:
			flat_right = Vector3.RIGHT
		# Positive curvature is a left turn; negative roll raises the +right
		# (outside) edge and leans the surface into that corner.
		var bank_angle := clampf(-signed_curvature * bank_strength, -maximum_bank, maximum_bank)
		var right := flat_right.rotated(tangent, bank_angle).normalized()
		var up := right.cross(tangent).normalized()
		frames.append({
			&"position": centerline[index],
			&"tangent": tangent,
			&"right": right,
			&"up": up,
			&"distance": distance,
			&"curvature": signed_curvature,
			&"berm_height": berm_height * smoothstep(0.08, 0.62, absf(signed_curvature)),
			&"half_width": width * 0.5,
			&"width_scale": 1.0,
			&"surface_lift": 0.0,
			&"endpoint_blend": 1.0,
		})
	var endpoint_taper_length := maxf(float(config.get(&"endpoint_taper_length", 0.0)), 0.0)
	var endpoint_minimum_ratio := clampf(float(config.get(&"endpoint_minimum_width_ratio", 1.0)), 0.02, 1.0)
	var endpoint_surface_lift := maxf(float(config.get(&"endpoint_surface_lift", 0.0)), 0.0)
	if endpoint_taper_length > 0.0 and frames.size() >= 2 and not closed_loop:
		var total_distance: float = frames[-1][&"distance"]
		for index: int in frames.size():
			var frame: Dictionary = frames[index]
			var frame_distance: float = frame[&"distance"]
			var start_blend := smoothstep(0.0, endpoint_taper_length, frame_distance)
			var end_blend := smoothstep(0.0, endpoint_taper_length, total_distance - frame_distance)
			var endpoint_blend := minf(start_blend, end_blend)
			frame[&"width_scale"] = lerpf(endpoint_minimum_ratio, 1.0, endpoint_blend)
			frame[&"surface_lift"] = endpoint_surface_lift * (1.0 - endpoint_blend)
			frame[&"endpoint_blend"] = endpoint_blend
			frame[&"half_width"] = width * 0.5 * float(frame[&"width_scale"])
			frames[index] = frame
	return frames


static func _build_chunk(
	root: Node3D,
	chunk_index: int,
	frames: Array[Dictionary],
	start_index: int,
	end_index: int,
	width: float,
	track_material: Material,
	shoulder_material: Material,
	rut_material: Material,
	config: Dictionary
) -> void:
	var chunk := Node3D.new()
	chunk.name = "RibbonChunk%02d" % chunk_index
	root.add_child(chunk)

	var half_width := width * 0.5
	var rut_offset := minf(float(config.get(&"rut_offset", 1.15)), half_width * 0.58)
	var rut_half_width := float(config.get(&"rut_half_width", 0.2))
	var visual_rut_depth := float(config.get(&"rut_depth", 0.04))
	var collision_rut_depth := minf(float(config.get(&"physical_rut_depth", 0.024)), 0.028)
	visual_rut_depth = minf(visual_rut_depth, collision_rut_depth)
	var shoulder_width := float(config.get(&"shoulder_width", 2.0))
	# Near-coplanar road beds receive lighting and prop/bike shadows, but their own
	# shadow pass mostly redraws the same terrain footprint. Authored jump overlays
	# remain independent casters so raised features retain their depth cues.
	var casts_shadow := bool(config.get(&"casts_shadow", true))
	var track_offsets := PackedFloat32Array([
		-half_width,
		-rut_offset - rut_half_width,
		-rut_offset,
		-rut_offset + rut_half_width,
		0.0,
		rut_offset - rut_half_width,
		rut_offset,
		rut_offset + rut_half_width,
		half_width,
	])
	var track_heights := PackedFloat32Array([
		-0.055, 0.018, -visual_rut_depth, 0.018, 0.04, 0.018, -visual_rut_depth, 0.018, -0.055,
	])
	var track_mesh := _create_strip_mesh(frames, start_index, end_index, track_offsets, track_heights, width, track_material)
	_add_visual(chunk, "RaceSurface", track_mesh, casts_shadow)

	var left_offsets := PackedFloat32Array([-half_width - shoulder_width, -half_width])
	var left_heights := PackedFloat32Array([-0.5, -0.055])
	var left_mesh := _create_strip_mesh(frames, start_index, end_index, left_offsets, left_heights, width, shoulder_material)
	_add_visual(chunk, "LeftShoulder", left_mesh, casts_shadow)
	var right_offsets := PackedFloat32Array([half_width, half_width + shoulder_width])
	var right_heights := PackedFloat32Array([-0.055, -0.5])
	var right_mesh := _create_strip_mesh(frames, start_index, end_index, right_offsets, right_heights, width, shoulder_material)
	_add_visual(chunk, "RightShoulder", right_mesh, casts_shadow)

	# Physical grooves remain continuous, but the dark visual traces come and go
	# like real ridden lines. Two intermittent wheel tracks read naturally and
	# avoid the previous four unbroken stripes/wallpaper effect.
	var visual_rut_centers: Array[float] = []
	if chunk_index % 3 != 2:
		visual_rut_centers = [-rut_offset, rut_offset]
	for rut_index: int in visual_rut_centers.size():
		var center := visual_rut_centers[rut_index]
		var rut_offsets := PackedFloat32Array([center - rut_half_width * 0.72, center + rut_half_width * 0.72])
		var is_physical_lane := absf(absf(center) - rut_offset) < 0.05
		var visual_height := -visual_rut_depth + 0.009 if is_physical_lane else 0.022
		var rut_heights := PackedFloat32Array([visual_height, visual_height])
		var rut_mesh := _create_strip_mesh(frames, start_index, end_index, rut_offsets, rut_heights, width, rut_material)
		_add_visual(chunk, "Rut%02d" % rut_index, rut_mesh, false)

	# Collision is welded once across the full ribbon by
	# `_build_continuous_collision`; chunks remain visual-only.


static func _build_continuous_collision(
	collision_body: StaticBody3D,
	frames: Array[Dictionary],
	width: float,
	config: Dictionary
) -> void:
	var profile := _collision_track_profile(width, config)
	var offsets: PackedFloat32Array = profile[&"offsets"]
	var heights: PackedFloat32Array = profile[&"heights"]
	var faces := _create_collision_faces(frames, 0, frames.size() - 1, offsets, heights, width)
	var shape := ConcavePolygonShape3D.new()
	# Only the visible/upward face is rideable. Back-face collision could catch a
	# jumping rider on the underside of a nearby elevated switchback.
	shape.backface_collision = false
	shape.set_faces(faces)
	var collision := CollisionShape3D.new()
	collision.name = "WeldedRibbonShape"
	collision.shape = shape
	collision_body.add_child(collision)


static func _create_strip_mesh(
	frames: Array[Dictionary],
	start_index: int,
	end_index: int,
	offsets: PackedFloat32Array,
	heights: PackedFloat32Array,
	width: float,
	material: Material
) -> ArrayMesh:
	var row_count := end_index - start_index + 1
	var column_count := offsets.size()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	vertices.resize(row_count * column_count)
	normals.resize(row_count * column_count)
	uvs.resize(row_count * column_count)
	var collapse_height := heights[0]
	for base_height: float in heights:
		collapse_height = maxf(collapse_height, base_height)
	for row: int in row_count:
		var frame: Dictionary = frames[start_index + row]
		var position: Vector3 = frame[&"position"]
		var right: Vector3 = frame[&"right"]
		var up: Vector3 = frame[&"up"]
		var distance: float = frame[&"distance"]
		var width_scale: float = frame.get(&"width_scale", 1.0)
		var surface_lift: float = frame.get(&"surface_lift", 0.0)
		var endpoint_blend: float = frame.get(&"endpoint_blend", 1.0)
		for column: int in column_count:
			var vertex_index := row * column_count + column
			var scaled_offset := offsets[column] * width_scale
			var tapered_height := lerpf(collapse_height, heights[column], endpoint_blend)
			var height := _height_with_berm(frame, scaled_offset, tapered_height, width) + surface_lift
			vertices[vertex_index] = position + right * scaled_offset + up * height
			uvs[vertex_index] = Vector2(scaled_offset / maxf(width, 0.1) + 0.5, distance / 7.0)
	for row: int in row_count:
		var global_row := start_index + row
		var frame: Dictionary = frames[global_row]
		var expected_up: Vector3 = frame[&"up"]
		var previous_global_row := maxi(global_row - 1, 0)
		var next_global_row := mini(global_row + 1, frames.size() - 1)
		for column: int in column_count:
			var previous_row := maxi(row - 1, 0)
			var next_row := mini(row + 1, row_count - 1)
			var previous_column := maxi(column - 1, 0)
			var next_column := mini(column + 1, column_count - 1)
			var previous_position: Vector3
			var next_position: Vector3
			if previous_global_row == global_row:
				previous_position = vertices[previous_row * column_count + column]
			else:
				previous_position = _strip_vertex_for_frame(
					frames[previous_global_row], offsets[column], heights[column], collapse_height, width
				)
			if next_global_row == global_row:
				next_position = vertices[next_row * column_count + column]
			else:
				next_position = _strip_vertex_for_frame(
					frames[next_global_row], offsets[column], heights[column], collapse_height, width
				)
			var along := next_position - previous_position
			var across := vertices[row * column_count + next_column] - vertices[row * column_count + previous_column]
			var normal := across.cross(along).normalized()
			if normal.dot(expected_up) < 0.0:
				normal = -normal
			normals[row * column_count + column] = normal if normal.length_squared() > 0.1 else expected_up
	var indices := _strip_indices(row_count, column_count)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	return mesh


static func _strip_vertex_for_frame(
	frame: Dictionary,
	offset: float,
	base_height: float,
	collapse_height: float,
	width: float
) -> Vector3:
	var position: Vector3 = frame[&"position"]
	var right: Vector3 = frame[&"right"]
	var up: Vector3 = frame[&"up"]
	var width_scale: float = frame.get(&"width_scale", 1.0)
	var surface_lift: float = frame.get(&"surface_lift", 0.0)
	var endpoint_blend: float = frame.get(&"endpoint_blend", 1.0)
	var scaled_offset := offset * width_scale
	var tapered_height := lerpf(collapse_height, base_height, endpoint_blend)
	var height := _height_with_berm(frame, scaled_offset, tapered_height, width) + surface_lift
	return position + right * scaled_offset + up * height


static func _create_collision_faces(
	frames: Array[Dictionary],
	start_index: int,
	end_index: int,
	offsets: PackedFloat32Array,
	heights: PackedFloat32Array,
	width: float
) -> PackedVector3Array:
	var row_count := end_index - start_index + 1
	var column_count := offsets.size()
	var vertices := PackedVector3Array()
	vertices.resize(row_count * column_count)
	var collapse_height := heights[0]
	for base_height: float in heights:
		collapse_height = maxf(collapse_height, base_height)
	for row: int in row_count:
		var frame: Dictionary = frames[start_index + row]
		var position: Vector3 = frame[&"position"]
		var right: Vector3 = frame[&"right"]
		var up: Vector3 = frame[&"up"]
		var width_scale: float = frame.get(&"width_scale", 1.0)
		var surface_lift: float = frame.get(&"surface_lift", 0.0)
		var endpoint_blend: float = frame.get(&"endpoint_blend", 1.0)
		for column: int in column_count:
			var scaled_offset := offsets[column] * width_scale
			var tapered_height := lerpf(collapse_height, heights[column], endpoint_blend)
			var height := _height_with_berm(frame, scaled_offset, tapered_height, width) + surface_lift
			vertices[row * column_count + column] = position + right * scaled_offset + up * height
	var indices := _strip_indices(row_count, column_count)
	var faces := PackedVector3Array()
	faces.resize(indices.size())
	for index: int in indices.size():
		faces[index] = vertices[indices[index]]
	return faces


static func _strip_indices(row_count: int, column_count: int) -> PackedInt32Array:
	var indices := PackedInt32Array()
	indices.resize((row_count - 1) * (column_count - 1) * 6)
	var cursor := 0
	for row: int in range(row_count - 1):
		for column: int in range(column_count - 1):
			var a := row * column_count + column
			var b := (row + 1) * column_count + column
			var c := a + 1
			var d := b + 1
			# Godot treats clockwise triangles as front-facing. Viewed from above,
			# right-across followed by forward-along is counter-clockwise, so lead
			# with the along vertex to keep the rideable top visible.
			indices[cursor] = a
			indices[cursor + 1] = b
			indices[cursor + 2] = c
			indices[cursor + 3] = c
			indices[cursor + 4] = b
			indices[cursor + 5] = d
			cursor += 6
	return indices


static func _height_with_berm(frame: Dictionary, offset: float, base_height: float, width: float) -> float:
	var half_width := width * 0.5
	var edge_ratio := smoothstep(half_width * 0.64, half_width, absf(offset))
	var curvature: float = frame[&"curvature"]
	var is_outside := (offset > 0.0 and curvature > 0.0) or (offset < 0.0 and curvature < 0.0)
	return base_height + (float(frame[&"berm_height"]) * edge_ratio if is_outside else 0.0)


static func _add_visual(parent: Node3D, node_name: String, mesh: Mesh, casts_shadow: bool) -> void:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if casts_shadow
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	parent.add_child(instance)
