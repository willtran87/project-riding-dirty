extends Node3D
class_name GhostController
## Records transforms at 10 Hz, persists the best run, and interpolates a collision-free ghost.

const SAMPLE_INTERVAL: float = 0.1

var target: Node3D
var best_time_usec: int = -1

var _ghost_root: Node3D
var _recording: Array[Dictionary] = []
var _best_frames: Array[Dictionary] = []
var _is_running: bool = false
var _elapsed: float = 0.0
var _next_sample: float = 0.0
var _playback_index: int = 0
var _record_slot: StringName = &"quarry"


func _ready() -> void:
	_build_ghost()
	_load_best_run()


func _physics_process(delta: float) -> void:
	if not _is_running or target == null:
		return
	_elapsed += delta
	if _elapsed >= _next_sample:
		_recording.append({&"time": _elapsed, &"transform": target.global_transform})
		_next_sample += SAMPLE_INTERVAL
	_update_playback()


func start_run() -> void:
	_recording.clear()
	_elapsed = 0.0
	_next_sample = 0.0
	_playback_index = 0
	_is_running = true
	_ghost_root.visible = _best_frames.size() >= 2


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
	if is_new_best and _recording.size() >= 2:
		best_time_usec = time_usec
		_best_frames = _recording.duplicate(true)
		_save_best_run()


func cancel_run() -> void:
	_is_running = false
	_ghost_root.visible = false
	_elapsed = 0.0


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
