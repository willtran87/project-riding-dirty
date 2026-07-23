extends RefCounted
class_name ReplayPlayback
## Seekable interpolation and marker delivery for ReplayModel data.

var playback_speed: float = 1.0
var looping: bool = false

var _model: ReplayModel
var _time_usec: int = 0
var _playing: bool = false
var _last_event_cursor_usec: int = -1


func load_model(model: ReplayModel) -> bool:
	if model == null or not model.is_valid():
		return false
	_model = model.duplicate_model()
	reset()
	return true


func play() -> void:
	if _model != null:
		_playing = true


func pause() -> void:
	_playing = false


func reset() -> void:
	_time_usec = 0
	_last_event_cursor_usec = -1
	_playing = false


func seek_usec(target_usec: int) -> Dictionary:
	if _model == null:
		return {}
	_time_usec = clampi(target_usec, 0, _model.duration_usec)
	_last_event_cursor_usec = _time_usec - 1
	return current_state()


func advance(delta_seconds: float) -> Dictionary:
	if _model == null:
		return {"state": {}, "events": [], "finished": true}
	var wrapped := false
	if _playing and delta_seconds > 0.0:
		_time_usec += maxi(roundi(delta_seconds * 1_000_000.0 * maxf(playback_speed, 0.0)), 0)
		if _time_usec > _model.duration_usec:
			if looping and _model.duration_usec > 0:
				_time_usec %= _model.duration_usec
				wrapped = true
			else:
				_time_usec = _model.duration_usec
				_playing = false
	var markers: Array[Dictionary] = []
	if wrapped:
		markers.append_array(_events_between(_last_event_cursor_usec, _model.duration_usec))
		markers.append_array(_events_between(-1, _time_usec))
	else:
		markers = _events_between(_last_event_cursor_usec, _time_usec)
	_last_event_cursor_usec = _time_usec
	return {
		"state": current_state(),
		"events": markers,
		"finished": not _playing and _time_usec >= _model.duration_usec,
		"time_usec": _time_usec,
	}


func current_state() -> Dictionary:
	if _model == null or _model.samples.is_empty():
		return {}
	return sample_at_usec(_time_usec)


func sample_at_usec(target_usec: int) -> Dictionary:
	if _model == null or _model.samples.is_empty():
		return {}
	var target := clampi(target_usec, 0, _model.duration_usec)
	var lower := 0
	var upper := _model.samples.size() - 1
	while lower <= upper:
		var middle := (lower + upper) >> 1
		var middle_time := int(_model.samples[middle].get("t_usec", 0))
		if middle_time < target:
			lower = middle + 1
		elif middle_time > target:
			upper = middle - 1
		else:
			return _decoded_state(_model.samples[middle])
	var right_index := clampi(lower, 0, _model.samples.size() - 1)
	var left_index := maxi(right_index - 1, 0)
	var left := _model.samples[left_index]
	var right := _model.samples[right_index]
	var left_time := int(left.get("t_usec", 0))
	var right_time := int(right.get("t_usec", left_time))
	var weight := 0.0 if right_time == left_time else float(target - left_time) / float(right_time - left_time)
	return _interpolated_decoded_state(left, right, clampf(weight, 0.0, 1.0))


func progress() -> float:
	if _model == null or _model.duration_usec <= 0:
		return 0.0
	return float(_time_usec) / float(_model.duration_usec)


func is_playing() -> bool:
	return _playing


func time_usec() -> int:
	return _time_usec


func _events_between(exclusive_start: int, inclusive_end: int) -> Array[Dictionary]:
	var markers: Array[Dictionary] = []
	if _model == null:
		return markers
	for event: Dictionary in _model.events:
		var event_time := int(event.get("t_usec", -1))
		if event_time > exclusive_start and event_time <= inclusive_end:
			markers.append(event.duplicate(true))
	return markers


func _decoded_state(sample: Dictionary) -> Dictionary:
	return {
		"t_usec": int(sample.get("t_usec", 0)),
		"position": _array_to_vector3(sample.get("position", [])),
		"rotation": _array_to_quaternion(sample.get("rotation", [])),
		"linear_velocity": _array_to_vector3(sample.get("linear_velocity", [])),
		"angular_velocity": _array_to_vector3(sample.get("angular_velocity", [])),
		"speed_mps": float(sample.get("speed_mps", 0.0)),
		"progress": float(sample.get("progress", 0.0)),
		"input": (sample.get("input", {}) as Dictionary).duplicate(true),
	}


func _interpolated_decoded_state(left: Dictionary, right: Dictionary, weight: float) -> Dictionary:
	var left_input := left.get("input", {}) as Dictionary
	var right_input := right.get("input", {}) as Dictionary
	return {
		"t_usec": roundi(lerpf(float(left.get("t_usec", 0)), float(right.get("t_usec", 0)), weight)),
		"position": _array_to_vector3(left.get("position", [])).lerp(_array_to_vector3(right.get("position", [])), weight),
		"rotation": _array_to_quaternion(left.get("rotation", [])).slerp(_array_to_quaternion(right.get("rotation", [])), weight).normalized(),
		"linear_velocity": _array_to_vector3(left.get("linear_velocity", [])).lerp(_array_to_vector3(right.get("linear_velocity", [])), weight),
		"angular_velocity": _array_to_vector3(left.get("angular_velocity", [])).lerp(_array_to_vector3(right.get("angular_velocity", [])), weight),
		"speed_mps": lerpf(float(left.get("speed_mps", 0.0)), float(right.get("speed_mps", 0.0)), weight),
		"progress": lerpf(float(left.get("progress", 0.0)), float(right.get("progress", 0.0)), weight),
		"input": {
			"throttle": lerpf(float(left_input.get("throttle", 0.0)), float(right_input.get("throttle", 0.0)), weight),
			"brake": lerpf(float(left_input.get("brake", 0.0)), float(right_input.get("brake", 0.0)), weight),
			"steer": lerpf(float(left_input.get("steer", 0.0)), float(right_input.get("steer", 0.0)), weight),
			"preload": lerpf(float(left_input.get("preload", 0.0)), float(right_input.get("preload", 0.0)), weight),
		},
	}


func _array_to_vector3(value: Variant) -> Vector3:
	var array := value as Array
	return Vector3(float(array[0]), float(array[1]), float(array[2]))


func _array_to_quaternion(value: Variant) -> Quaternion:
	var array := value as Array
	return Quaternion(float(array[0]), float(array[1]), float(array[2]), float(array[3])).normalized()
