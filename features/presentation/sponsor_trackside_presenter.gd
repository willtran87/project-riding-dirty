extends Node3D
class_name SponsorTracksidePresenter
## Lightweight, collision-free sponsor landmarks for the active event.
##
## Sponsor relationships already own Garage, HUD, result, audio, and rider-kit
## identity. This presenter carries the same authored identity into the physical
## event space without becoming track, checkpoint, or collision authority.

const SPONSOR_CATALOG := preload("res://features/career/sponsor_contract_catalog.gd")
const OPEN_AREA_ACTIVITIES: Array[StringName] = [&"FREESTYLE", &"DISCOVERY"]
const OPEN_AREA_SPAWN := Vector3(0.0, 1.4, 31.0)
const BOARD_SIZE := Vector3(7.4, 1.62, 0.14)
const BOARD_CLEARANCE_METERS := 5.8
const LANDMARK_HEIGHT_METERS := 2.72

var _activity_id: StringName = &""
var _sponsor_id: StringName = &""
var _sponsor_name: String = ""
var _identity: String = ""
var _accent: Color = Color.TRANSPARENT
var _landmark_positions: Array[Vector3] = []


func configure(
	activity_id: StringName,
	route: PackedVector3Array,
	track_width: float
) -> void:
	clear_presentation()
	_activity_id = activity_id
	if not SPONSOR_CATALOG.ACTIVITY_SPONSORS.has(activity_id):
		return
	_sponsor_id = SPONSOR_CATALOG.get_sponsor_id(activity_id)
	var sponsor: Dictionary = SPONSOR_CATALOG.SPONSORS.get(_sponsor_id, {})
	if sponsor.is_empty():
		clear_presentation()
		return
	_sponsor_name = str(sponsor.get(&"display_name", _sponsor_id)).to_upper()
	_identity = str(sponsor.get(&"identity", "RIDE PROGRAM")).to_upper()
	_accent = sponsor.get(&"accent", Color("ffb52d")) as Color

	var anchors := _activity_anchors(activity_id, route, maxf(track_width, 4.0))
	for index: int in anchors.size():
		var treatment := (
			_build_route_arch(index, anchors[index], maxf(track_width, 4.0))
			if activity_id not in OPEN_AREA_ACTIVITIES and index == 0
			else _build_treatment(index, anchors[index])
		)
		add_child(treatment)
		_landmark_positions.append(treatment.global_position)
	visible = not _landmark_positions.is_empty()


func clear_presentation() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_activity_id = &""
	_sponsor_id = &""
	_sponsor_name = ""
	_identity = ""
	_accent = Color.TRANSPARENT
	_landmark_positions.clear()
	visible = false


func get_presentation_snapshot() -> Dictionary:
	var positions: Array[Vector3] = []
	for position: Vector3 in _landmark_positions:
		positions.append(position)
	var collision_count := 0
	for child: Node in find_children("*", "CollisionObject3D", true, false):
		if child is CollisionObject3D:
			collision_count += 1
	return {
		&"visible": visible and not _landmark_positions.is_empty(),
		&"activity_id": _activity_id,
		&"sponsor_id": _sponsor_id,
		&"sponsor_name": _sponsor_name,
		&"identity": _identity,
		&"accent": _accent,
		&"accent_hex": _accent.to_html(false).to_upper() if _accent.a > 0.0 else "",
		&"landmark_count": _landmark_positions.size(),
		&"landmark_positions": positions,
		&"collision_count": collision_count,
	}


func _activity_anchors(
	activity_id: StringName,
	route: PackedVector3Array,
	track_width: float
) -> Array[Transform3D]:
	if activity_id in OPEN_AREA_ACTIVITIES:
		return [
			_trackside_transform(
				OPEN_AREA_SPAWN,
				Vector3.FORWARD,
				track_width,
				1.0,
				6.0
			),
			_trackside_transform(
				OPEN_AREA_SPAWN,
				Vector3.FORWARD,
				track_width,
				-1.0,
				28.0
			),
		]
	if route.size() < 2:
		return []
	var start_direction := _flat_direction(route[1] - route[0])
	var finish_direction := _flat_direction(route[-1] - route[-2])
	return [
		# Keep the opening landmark beyond the dense launch HUD. At this distance
		# the overhead arch reads as a destination in the world instead of sitting
		# beneath the minimap or classification card while the field is staged.
		_centerline_transform(route[0], start_direction, 34.0, 6.55),
		_trackside_transform(route[-1], finish_direction, track_width, -1.0, -14.0),
	]


func _centerline_transform(
	center: Vector3,
	direction: Vector3,
	forward_offset: float,
	height: float
) -> Transform3D:
	var flat_direction := _flat_direction(direction)
	var position := center + flat_direction * forward_offset + Vector3.UP * height
	var yaw := atan2(flat_direction.x, flat_direction.z)
	return Transform3D(Basis(Vector3.UP, yaw), position)


func _trackside_transform(
	center: Vector3,
	direction: Vector3,
	track_width: float,
	side: float,
	forward_offset: float
) -> Transform3D:
	var flat_direction := _flat_direction(direction)
	var right := flat_direction.cross(Vector3.UP).normalized()
	var position := (
		center
		+ flat_direction * forward_offset
		+ right * side * (track_width * 0.5 + BOARD_CLEARANCE_METERS)
		+ Vector3.UP * LANDMARK_HEIGHT_METERS
	)
	var yaw := atan2(flat_direction.x, flat_direction.z)
	return Transform3D(Basis(Vector3.UP, yaw), position)


func _flat_direction(direction: Vector3) -> Vector3:
	var flat := Vector3(direction.x, 0.0, direction.z)
	return flat.normalized() if flat.length_squared() > 0.0001 else Vector3.FORWARD


func _build_route_arch(
	index: int,
	anchor: Transform3D,
	track_width: float
) -> Node3D:
	var root := Node3D.new()
	root.name = "SponsorLandmark%02d" % (index + 1)
	root.transform = anchor
	root.add_to_group(&"sponsor_trackside_treatment")
	root.set_meta(&"sponsor_id", _sponsor_id)
	root.set_meta(&"activity_id", _activity_id)
	root.set_meta(&"layout", &"OVERHEAD_ARCH")

	var arch_width := track_width + 5.0
	var board_size := Vector3(arch_width, 1.48, 0.18)
	var board_material := _material(Color("11191d"), Color("11191d"), 0.0)
	var accent_material := _material(_accent.darkened(0.08), _accent, 2.35)
	var pole_material := _material(Color("3a4447"), Color("3a4447"), 0.0)
	_add_box(root, "Board", board_size, Vector3.ZERO, board_material)
	_add_box(
		root,
		"AccentTop",
		Vector3(arch_width, 0.13, board_size.z + 0.025),
		Vector3(0.0, board_size.y * 0.5 - 0.065, -0.015),
		accent_material
	)
	_add_box(
		root,
		"AccentFoot",
		Vector3(arch_width, 0.09, board_size.z + 0.025),
		Vector3(0.0, -board_size.y * 0.5 + 0.045, -0.015),
		accent_material
	)
	var pole_offset := track_width * 0.5 + 1.55
	for pole_x: float in [-pole_offset, pole_offset]:
		_add_box(
			root,
			"Pole%s" % ("Left" if pole_x < 0.0 else "Right"),
			Vector3(0.18, 6.5, 0.18),
			Vector3(pole_x, -3.25, 0.0),
			pole_material
		)
	_add_landmark_labels(root, "OFFICIAL ROUTE PARTNER", true)
	return root


func _build_treatment(index: int, anchor: Transform3D) -> Node3D:
	var root := Node3D.new()
	root.name = "SponsorLandmark%02d" % (index + 1)
	root.transform = anchor
	root.add_to_group(&"sponsor_trackside_treatment")
	root.set_meta(&"sponsor_id", _sponsor_id)
	root.set_meta(&"activity_id", _activity_id)
	root.set_meta(&"layout", &"TRACKSIDE_BOARD")

	var board_material := _material(Color("11191d"), Color("11191d"), 0.0)
	var accent_material := _material(_accent.darkened(0.08), _accent, 2.35)
	var pole_material := _material(Color("3a4447"), Color("3a4447"), 0.0)
	_add_box(root, "Board", BOARD_SIZE, Vector3.ZERO, board_material)
	_add_box(
		root,
		"AccentTop",
		Vector3(BOARD_SIZE.x, 0.12, BOARD_SIZE.z + 0.025),
		Vector3(0.0, BOARD_SIZE.y * 0.5 - 0.06, -0.015),
		accent_material
	)
	_add_box(
		root,
		"AccentFoot",
		Vector3(BOARD_SIZE.x, 0.08, BOARD_SIZE.z + 0.025),
		Vector3(0.0, -BOARD_SIZE.y * 0.5 + 0.04, -0.015),
		accent_material
	)
	for pole_x: float in [-2.72, 2.72]:
		_add_box(
			root,
			"Pole%s" % ("Left" if pole_x < 0.0 else "Right"),
			Vector3(0.13, 2.75, 0.13),
			Vector3(pole_x, -1.72, 0.0),
			pole_material
		)

	_add_landmark_labels(root, _landmark_role(index))
	return root


func _add_landmark_labels(root: Node3D, role: String, wide_arch: bool = false) -> void:
	var title := Label3D.new()
	title.name = "SponsorName"
	title.text = (
		"%s  //  %s" % [_sponsor_name, _identity]
		if wide_arch else _sponsor_name
	)
	title.position = Vector3(0.0, 0.18, -0.095)
	title.font_size = 70 if wide_arch else 66
	title.pixel_size = 0.0098 if wide_arch else 0.0082
	title.width = 2600.0 if wide_arch else 820.0
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.modulate = Color("f7e5b2")
	title.outline_modulate = Color("081014")
	title.outline_size = 12
	title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	title.no_depth_test = false
	root.add_child(title)

	var identity_label := Label3D.new()
	identity_label.name = "SponsorIdentity"
	identity_label.text = (
		"RACECRAFT TOUR  //  %s" % role
		if wide_arch
		else "%s  //  %s" % [_identity, role]
	)
	identity_label.position = Vector3(0.0, -0.42, -0.10)
	identity_label.font_size = 34
	identity_label.pixel_size = 0.0084 if wide_arch else 0.0076
	identity_label.width = 1800.0 if wide_arch else 880.0
	identity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	identity_label.modulate = _accent.lightened(0.18)
	identity_label.outline_modulate = Color("081014")
	identity_label.outline_size = 10
	identity_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	identity_label.no_depth_test = false
	root.add_child(identity_label)


func _landmark_role(index: int) -> String:
	if _activity_id in OPEN_AREA_ACTIVITIES:
		return "SESSION LINE" if index == 0 else "STYLE ZONE"
	return "START LINE" if index == 0 else "FINISH LINE"


func _material(albedo: Color, emission: Color, emission_energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = albedo
	material.roughness = 0.82
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if emission_energy > 0.0:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = emission_energy
	return material


func _add_box(
	parent: Node3D,
	node_name: String,
	size: Vector3,
	position: Vector3,
	material: Material
) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = position
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
