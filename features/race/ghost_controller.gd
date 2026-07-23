extends Node3D
class_name GhostController
## Records transforms at 10 Hz, persists the best run, and interpolates a collision-free ghost.

const SAMPLE_INTERVAL: float = 0.1
const PLAYER_GRID_PROGRESS_METERS: float = 2.0
const RIVAL_START_LEAD_METERS: float = 4.5
const RIVAL_RIDE_HEIGHT_METERS: float = 0.75

var target: Node3D
var best_time_usec: int = -1
var persistence_enabled: bool = true

var _ghost_root: Node3D
var _recording: Array[Dictionary] = []
var _best_frames: Array[Dictionary] = []
var _is_running: bool = false
var _elapsed: float = 0.0
var _next_sample: float = 0.0
var _playback_index: int = 0
var _record_slot: StringName = &"quarry"
var _rival_root: Node3D
var _rival_curve: Curve3D
var _rival_target_seconds: float = 0.0
var _rival_source_points := PackedVector3Array()


func _ready() -> void:
	_build_ghost()
	_build_rival()
	_load_best_run()


func _physics_process(delta: float) -> void:
	if not _is_running or target == null:
		return
	_elapsed += delta
	if _elapsed >= _next_sample:
		_recording.append({&"time": _elapsed, &"transform": target.global_transform})
		_next_sample += SAMPLE_INTERVAL
	_update_playback()
	_update_rival_playback()


func start_run() -> void:
	_recording.clear()
	_elapsed = 0.0
	_next_sample = 0.0
	_playback_index = 0
	_is_running = true
	_ghost_root.visible = _best_frames.size() >= 2
	_rival_root.visible = _rival_curve != null and _rival_target_seconds > 0.0


func set_record_slot(slot: StringName) -> void:
	if slot == _record_slot:
		return
	cancel_run()
	_record_slot = slot
	best_time_usec = -1
	_best_frames.clear()
	_recording.clear()
	_load_best_run()


func finish_run(time_usec: int, is_new_best: bool) -> void:
	_is_running = false
	_ghost_root.visible = false
	_rival_root.visible = false
	if is_new_best and _recording.size() >= 2:
		best_time_usec = time_usec
		_best_frames = _recording.duplicate(true)
		if persistence_enabled:
			_save_best_run()


func cancel_run() -> void:
	_is_running = false
	_ghost_root.visible = false
	_rival_root.visible = false
	_elapsed = 0.0


func configure_rival(
	points: Array[Vector3],
	target_usec: int,
	laps: int = 1,
	closed_route: bool = false,
	enabled: bool = true
) -> void:
	_rival_curve = null
	_rival_source_points = PackedVector3Array(points)
	_rival_target_seconds = maxf(float(target_usec) / 1_000_000.0, 0.0)
	_rival_root.visible = false
	if not enabled or points.size() < 2 or target_usec <= 0:
		return
	var playback_points: Array[Vector3] = points.duplicate()
	if closed_route and laps > 1:
		for _lap: int in range(1, laps):
			if playback_points[-1].distance_to(points[0]) > 0.05:
				playback_points.append(points[0])
			for point_index: int in range(1, points.size()):
				playback_points.append(points[point_index])
	_rival_curve = Curve3D.new()
	_rival_curve.bake_interval = 1.6
	# Rook is non-physical, so allowing its translucent footprint to start behind
	# the grid makes it visibly sweep through the player's bike at GO. Start it a
	# full bike-length gap ahead of the player and discard the already-covered
	# route points. That preserves a forward-only playback curve with no launch
	# strafe or backtracking.
	var packed_points := PackedVector3Array(playback_points)
	var opening_direction := CourseSpline.tangent_at(packed_points, 1)
	var opening_normal := Basis.looking_at(opening_direction, Vector3.UP).y
	var rival_start_progress := PLAYER_GRID_PROGRESS_METERS + RIVAL_START_LEAD_METERS
	var rival_start := playback_points[0] + opening_direction * rival_start_progress
	_rival_curve.add_point(rival_start + opening_normal * RIVAL_RIDE_HEIGHT_METERS)
	var route_progress := 0.0
	for index: int in range(1, playback_points.size()):
		route_progress += playback_points[index - 1].distance_to(playback_points[index])
		if route_progress <= rival_start_progress:
			continue
		var previous := playback_points[maxi(index - 1, 0)]
		var following := playback_points[mini(index + 1, playback_points.size() - 1)]
		var direction := (following - previous).normalized()
		var trail_normal := Basis.looking_at(direction, Vector3.UP).y
		var rider_point := playback_points[index] + trail_normal * RIVAL_RIDE_HEIGHT_METERS
		_rival_curve.add_point(rider_point)


func get_rival_source_points() -> PackedVector3Array:
	return _rival_source_points.duplicate()


func is_rival_configured() -> bool:
	return _rival_curve != null and _rival_target_seconds > 0.0


func _update_playback() -> void:
	if _best_frames.size() < 2:
		return
	while _playback_index < _best_frames.size() - 2 and float(_best_frames[_playback_index + 1].get(&"time", 0.0)) <= _elapsed:
		_playback_index += 1
	var frame_a := _best_frames[_playback_index]
	var frame_b := _best_frames[mini(_playback_index + 1, _best_frames.size() - 1)]
	var time_a := float(frame_a.get(&"time", 0.0))
	var time_b := float(frame_b.get(&"time", time_a + SAMPLE_INTERVAL))
	var weight := clampf(inverse_lerp(time_a, time_b, _elapsed), 0.0, 1.0)
	var transform_a: Transform3D = frame_a.get(&"transform", Transform3D.IDENTITY)
	var transform_b: Transform3D = frame_b.get(&"transform", transform_a)
	var position := transform_a.origin.lerp(transform_b.origin, weight)
	var rotation_a := transform_a.basis.get_rotation_quaternion()
	var rotation_b := transform_b.basis.get_rotation_quaternion()
	_ghost_root.global_transform = Transform3D(Basis(rotation_a.slerp(rotation_b, weight)), position)


func _update_rival_playback() -> void:
	if _rival_curve == null or _rival_target_seconds <= 0.0:
		return
	var progress := clampf(_elapsed / _rival_target_seconds, 0.0, 1.0)
	var curve_length := _rival_curve.get_baked_length()
	var offset := progress * curve_length
	var position := _rival_curve.sample_baked(offset, true)
	var look_position := _rival_curve.sample_baked(minf(offset + 1.5, curve_length), true)
	var direction := look_position - position
	if direction.length_squared() < 0.05:
		direction = Vector3.FORWARD
	_rival_root.global_transform = Transform3D(Basis.looking_at(direction.normalized(), Vector3.UP), position)


func _build_ghost() -> void:
	_ghost_root = Node3D.new()
	_ghost_root.name = "PersonalBestGhost"
	_ghost_root.visible = false
	add_child(_ghost_root)

	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.2, 0.84, 1.0, 0.25)
	material.emission_enabled = true
	material.emission = Color(0.12, 0.65, 1.0)
	material.emission_energy_multiplier = 1.45

	_add_ghost_box(Vector3(0.48, 0.45, 1.25), Vector3(0.0, 0.24, 0.0), material)
	_add_ghost_box(Vector3(0.48, 0.65, 0.36), Vector3(0.0, 1.0, 0.1), material)
	_add_ghost_sphere(0.25, Vector3(0.0, 1.48, -0.1), material)
	_add_ghost_wheel(Vector3(0.0, -0.38, -1.18), material)
	_add_ghost_wheel(Vector3(0.0, -0.38, 1.05), material)


func _build_rival() -> void:
	_rival_root = Node3D.new()
	_rival_root.name = "RookGhost"
	_rival_root.visible = false
	add_child(_rival_root)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.42, 0.12, 0.48)
	material.emission_enabled = true
	material.emission = Color("ff6b2d")
	material.emission_energy_multiplier = 2.1
	_add_rival_box(Vector3(0.5, 0.44, 1.3), Vector3(0.0, 0.24, 0.0), material)
	_add_rival_box(Vector3(0.5, 0.68, 0.38), Vector3(0.0, 1.02, 0.1), material)
	_add_rival_sphere(0.25, Vector3(0.0, 1.49, -0.1), material)
	_add_rival_wheel(Vector3(0.0, -0.38, -1.18), material)
	_add_rival_wheel(Vector3(0.0, -0.38, 1.05), material)
	var label := Label3D.new()
	label.text = "ROOK"
	label.position = Vector3(0.0, 2.05, 0.0)
	label.font_size = 28
	label.outline_size = 8
	label.modulate = Color("ffb52d")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_rival_root.add_child(label)


func _add_rival_box(size: Vector3, position: Vector3, material: StandardMaterial3D) -> void:
	var box := BoxMesh.new()
	box.size = size
	var mesh := MeshInstance3D.new()
	mesh.mesh = box
	mesh.position = position
	mesh.material_override = material
	_rival_root.add_child(mesh)


func _add_rival_sphere(radius: float, position: Vector3, material: StandardMaterial3D) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 10
	sphere.rings = 6
	var mesh := MeshInstance3D.new()
	mesh.mesh = sphere
	mesh.position = position
	mesh.material_override = material
	_rival_root.add_child(mesh)


func _add_rival_wheel(position: Vector3, material: StandardMaterial3D) -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.24
	torus.outer_radius = 0.37
	torus.rings = 14
	torus.ring_segments = 8
	var mesh := MeshInstance3D.new()
	mesh.mesh = torus
	mesh.position = position
	mesh.rotation.z = PI * 0.5
	mesh.material_override = material
	_rival_root.add_child(mesh)


func _add_ghost_box(size: Vector3, position: Vector3, material: StandardMaterial3D) -> void:
	var box := BoxMesh.new()
	box.size = size
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = box
	mesh_instance.position = position
	mesh_instance.material_override = material
	_ghost_root.add_child(mesh_instance)


func _add_ghost_sphere(radius: float, position: Vector3, material: StandardMaterial3D) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 10
	sphere.rings = 6
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = sphere
	mesh_instance.position = position
	mesh_instance.material_override = material
	_ghost_root.add_child(mesh_instance)


func _add_ghost_wheel(position: Vector3, material: StandardMaterial3D) -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.24
	torus.outer_radius = 0.37
	torus.rings = 14
	torus.ring_segments = 8
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = torus
	mesh_instance.position = position
	mesh_instance.rotation.z = PI * 0.5
	mesh_instance.material_override = material
	_ghost_root.add_child(mesh_instance)


func _save_best_run() -> void:
	if OS.has_feature("web"):
		var payload := {
			"best_time_usec": best_time_usec,
			"frames": _serialize_frames(_best_frames),
		}
		if not WebPlatform.save_json(_get_web_save_key(), payload):
			push_warning("Unable to save the personal-best ghost to browser storage.")
		return
	var file := FileAccess.open(_get_save_path(), FileAccess.WRITE)
	if file == null:
		push_warning("Unable to save the personal-best ghost.")
		return
	file.store_var({&"best_time_usec": best_time_usec, &"frames": _best_frames}, true)
	file.close()


func _load_best_run() -> void:
	if OS.has_feature("web"):
		var web_payload: Variant = WebPlatform.load_json(_get_web_save_key())
		if web_payload is Dictionary:
			var saved_data := web_payload as Dictionary
			best_time_usec = int(saved_data.get("best_time_usec", -1))
			_best_frames = _deserialize_frames(saved_data.get("frames", []))
		return
	var save_path := _get_save_path()
	if not FileAccess.file_exists(save_path):
		return
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return
	var payload: Variant = file.get_var(true)
	file.close()
	if payload is not Dictionary:
		return
	var saved_data := payload as Dictionary
	best_time_usec = int(saved_data.get(&"best_time_usec", -1))
	var frames: Variant = saved_data.get(&"frames", [])
	if frames is Array:
		_best_frames.assign(frames)


func _get_save_path() -> String:
	if _record_slot == &"quarry":
		return "user://quarry_best_run.dat"
	return "user://%s_best_run.dat" % String(_record_slot).to_lower()


func _get_web_save_key() -> String:
	return "ghost_%s_v1" % String(_record_slot).to_lower()


func _serialize_frames(frames: Array[Dictionary]) -> Array[Array]:
	var serialized: Array[Array] = []
	for frame: Dictionary in frames:
		var transform: Transform3D = frame.get(&"transform", Transform3D.IDENTITY)
		var rotation := transform.basis.get_rotation_quaternion()
		serialized.append([
			float(frame.get(&"time", 0.0)),
			transform.origin.x, transform.origin.y, transform.origin.z,
			rotation.x, rotation.y, rotation.z, rotation.w,
		])
	return serialized


func _deserialize_frames(serialized: Variant) -> Array[Dictionary]:
	var frames: Array[Dictionary] = []
	if serialized is not Array:
		return frames
	for raw_frame: Variant in serialized:
		if raw_frame is not Array or raw_frame.size() < 8:
			continue
		var values := raw_frame as Array
		var position := Vector3(float(values[1]), float(values[2]), float(values[3]))
		var rotation := Quaternion(float(values[4]), float(values[5]), float(values[6]), float(values[7])).normalized()
		frames.append({&"time": float(values[0]), &"transform": Transform3D(Basis(rotation), position)})
	return frames
