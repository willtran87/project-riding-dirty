extends RefCounted
class_name ReplayRecorder
## Records interpolated bike state at an exact fixed interval independent of FPS.

const DEFAULT_SAMPLE_INTERVAL_USEC: int = 33_333
const FRAME_COMPONENT_COUNT: int = 19

var sample_interval_usec: int = DEFAULT_SAMPLE_INTERVAL_USEC
var maximum_samples: int = ReplayModel.MAX_SAMPLES

var _recording: bool = false
var _elapsed_usec: int = 0
var _next_sample_usec: int = 0
var _metadata: Dictionary = {}
var _sample_times_usec := PackedInt64Array()
var _sample_frames: Array[PackedFloat32Array] = []
var _events: Array[Dictionary] = []
var _previous_state := PackedFloat32Array()


func begin(metadata: Dictionary = {}, interval_usec: int = DEFAULT_SAMPLE_INTERVAL_USEC) -> void:
	sample_interval_usec = clampi(
		interval_usec,
		ReplayModel.MIN_SAMPLE_INTERVAL_USEC,
		ReplayModel.MAX_SAMPLE_INTERVAL_USEC
	)
	_metadata = metadata.duplicate(true)
	_sample_times_usec.clear()
	_sample_frames.clear()
	_events.clear()
	_previous_state.clear()
	_elapsed_usec = 0
	_next_sample_usec = 0
	_recording = true


func capture(delta_seconds: float, raw_state: Dictionary) -> bool:
	if not _recording or delta_seconds < 0.0:
		return false
	var state := _normalize_state(raw_state)
	if state.is_empty():
		return false
	if _previous_state.is_empty():
		_previous_state = state
		_append_sample(0, state)
		_next_sample_usec = sample_interval_usec
		_elapsed_usec = maxi(roundi(delta_seconds * 1_000_000.0), 0)
		while _next_sample_usec <= _elapsed_usec and _sample_frames.size() < maximum_samples:
			_append_sample(_next_sample_usec, state)
			_next_sample_usec += sample_interval_usec
		return true
	var frame_start := _elapsed_usec
	var frame_delta := maxi(roundi(delta_seconds * 1_000_000.0), 0)
	var frame_end := frame_start + frame_delta
	while _next_sample_usec <= frame_end and _sample_frames.size() < maximum_samples:
		var blend := 1.0
		if frame_delta > 0:
			blend = clampf(float(_next_sample_usec - frame_start) / float(frame_delta), 0.0, 1.0)
		_append_sample(_next_sample_usec, _interpolate_state(_previous_state, state, blend))
		_next_sample_usec += sample_interval_usec
	_elapsed_usec = frame_end
	_previous_state = state
	return true


func mark_event(name: StringName, payload: Dictionary = {}, at_usec: int = -1) -> bool:
	if not _recording or name.is_empty() or _events.size() >= ReplayModel.MAX_EVENTS:
		return false
	_events.append({
		"t_usec": clampi(at_usec if at_usec >= 0 else _elapsed_usec, 0, _elapsed_usec),
		"name": String(name).substr(0, 64),
		"payload": payload.duplicate(true),
	})
	return true


func finish() -> ReplayModel:
	_recording = false
	var model := ReplayModel.new()
	model.sample_interval_usec = sample_interval_usec
	model.metadata = _metadata.duplicate(true)
	model.samples.clear()
	for index: int in _sample_frames.size():
		model.samples.append(_frame_to_dictionary(_sample_times_usec[index], _sample_frames[index]))
	model.events = _events.duplicate(true)
	model.duration_usec = int(model.samples.back().get("t_usec", 0)) if not model.samples.is_empty() else 0
	for event: Dictionary in model.events:
		event["t_usec"] = clampi(int(event.get("t_usec", 0)), 0, model.duration_usec)
	model.events.sort_custom(_event_precedes)
	# The live recorder uses tightly packed numeric frames. Release those frames
	# once the public replay model has been materialized so a finished race does
	# not retain two copies of the entire run.
	_sample_times_usec.clear()
	_sample_frames.clear()
	_previous_state.clear()
	return model


func cancel() -> void:
	## Abandoned attempts must release their packed frames immediately. Keeping an
	## unfinished recorder alive would capture Garage/countdown motion into a later
	## run and retain the maximum replay allocation until another race starts.
	_recording = false
	_elapsed_usec = 0
	_next_sample_usec = 0
	_metadata.clear()
	_sample_times_usec.clear()
	_sample_frames.clear()
	_events.clear()
	_previous_state.clear()


func is_recording() -> bool:
	return _recording


func sample_count() -> int:
	return _sample_frames.size()


func elapsed_usec() -> int:
	return _elapsed_usec


func _append_sample(time_usec: int, state: PackedFloat32Array) -> void:
	if _sample_frames.size() >= maximum_samples:
		return
	_sample_times_usec.append(time_usec)
	_sample_frames.append(state.duplicate())


func _normalize_state(raw_state: Dictionary) -> PackedFloat32Array:
	var position_variant: Variant = raw_state.get("position", Vector3.ZERO)
	var rotation_variant: Variant = raw_state.get("rotation", Quaternion.IDENTITY)
	var linear_variant: Variant = raw_state.get("linear_velocity", Vector3.ZERO)
	var angular_variant: Variant = raw_state.get("angular_velocity", Vector3.ZERO)
	if not position_variant is Vector3 or not rotation_variant is Quaternion:
		return PackedFloat32Array()
	if not linear_variant is Vector3 or not angular_variant is Vector3:
		return PackedFloat32Array()
	var position := position_variant as Vector3
	var rotation := (rotation_variant as Quaternion).normalized()
	var linear_velocity := linear_variant as Vector3
	var angular_velocity := angular_variant as Vector3
	if not position.is_finite() or not rotation.is_finite() or not linear_velocity.is_finite() or not angular_velocity.is_finite():
		return PackedFloat32Array()
	var input_state: Variant = raw_state.get("input", {})
	var input := _normalize_input(input_state as Dictionary if input_state is Dictionary else {})
	return PackedFloat32Array([
		position.x, position.y, position.z,
		rotation.x, rotation.y, rotation.z, rotation.w,
		linear_velocity.x, linear_velocity.y, linear_velocity.z,
		angular_velocity.x, angular_velocity.y, angular_velocity.z,
		clampf(float(raw_state.get("speed_mps", linear_velocity.length())), 0.0, 500.0),
		maxf(float(raw_state.get("progress", 0.0)), 0.0),
		float(input.get("throttle", 0.0)), float(input.get("brake", 0.0)),
		float(input.get("steer", 0.0)), float(input.get("preload", 0.0)),
	])


func _interpolate_state(from: PackedFloat32Array, to: PackedFloat32Array, weight: float) -> PackedFloat32Array:
	if from.size() != FRAME_COMPONENT_COUNT or to.size() != FRAME_COMPONENT_COUNT:
		return to.duplicate()
	var result := PackedFloat32Array()
	result.resize(FRAME_COMPONENT_COUNT)
	for index: int in FRAME_COMPONENT_COUNT:
		result[index] = lerpf(from[index], to[index], weight)
	var from_rotation := Quaternion(from[3], from[4], from[5], from[6]).normalized()
	var to_rotation := Quaternion(to[3], to[4], to[5], to[6]).normalized()
	var rotation := from_rotation.slerp(to_rotation, weight).normalized()
	result[3] = rotation.x
	result[4] = rotation.y
	result[5] = rotation.z
	result[6] = rotation.w
	return result


func _normalize_input(input_state: Dictionary) -> Dictionary:
	return {
		"throttle": clampf(float(input_state.get("throttle", 0.0)), 0.0, 1.0),
		"brake": clampf(float(input_state.get("brake", 0.0)), 0.0, 1.0),
		"steer": clampf(float(input_state.get("steer", 0.0)), -1.0, 1.0),
		"preload": clampf(float(input_state.get("preload", 0.0)), 0.0, 1.0),
	}


func _frame_to_dictionary(time_usec: int, frame: PackedFloat32Array) -> Dictionary:
	if frame.size() != FRAME_COMPONENT_COUNT:
		return {}
	return {
		"t_usec": time_usec,
		"position": [frame[0], frame[1], frame[2]],
		"rotation": [frame[3], frame[4], frame[5], frame[6]],
		"linear_velocity": [frame[7], frame[8], frame[9]],
		"angular_velocity": [frame[10], frame[11], frame[12]],
		"speed_mps": frame[13],
		"progress": frame[14],
		"input": {
			"throttle": frame[15],
			"brake": frame[16],
			"steer": frame[17],
			"preload": frame[18],
		},
	}


func _event_precedes(a: Dictionary, b: Dictionary) -> bool:
	return int(a.get("t_usec", 0)) < int(b.get("t_usec", 0))
