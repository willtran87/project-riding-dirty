extends RefCounted
class_name ReplayModel
## Immutable-by-convention fixed-rate replay samples plus sparse event markers.

const FORMAT_VERSION: int = 1
const MIN_SAMPLE_INTERVAL_USEC: int = 8_000
const MAX_SAMPLE_INTERVAL_USEC: int = 250_000
const MAX_SAMPLES: int = 36_000
const MAX_EVENTS: int = 2_048

var sample_interval_usec: int = 33_333
var duration_usec: int = 0
var metadata: Dictionary = {}
var samples: Array[Dictionary] = []
var events: Array[Dictionary] = []


func to_dictionary() -> Dictionary:
	return {
		"format": "RIDING_DIRTY_REPLAY",
		"version": FORMAT_VERSION,
		"sample_interval_usec": sample_interval_usec,
		"duration_usec": duration_usec,
		"metadata": metadata.duplicate(true),
		"samples": samples.duplicate(true),
		"events": events.duplicate(true),
	}


func duplicate_model() -> ReplayModel:
	return ReplayModel.from_dictionary(to_dictionary())


func is_valid() -> bool:
	return bool(validate_dictionary(to_dictionary()).get("ok", false))


func ghost_samples() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for sample: Dictionary in samples:
		result.append({
			"t_usec": int(sample.get("t_usec", 0)),
			"position": (sample.get("position", []) as Array).duplicate(),
			"rotation": (sample.get("rotation", []) as Array).duplicate(),
			"linear_velocity": (sample.get("linear_velocity", []) as Array).duplicate(),
			"speed_mps": float(sample.get("speed_mps", 0.0)),
			"progress": float(sample.get("progress", 0.0)),
		})
	return result


static func from_dictionary(data: Dictionary) -> ReplayModel:
	var model := ReplayModel.new()
	var validation := validate_dictionary(data)
	if not bool(validation.get("ok", false)):
		return model
	model.sample_interval_usec = int(data.get("sample_interval_usec", 33_333))
	model.duration_usec = int(data.get("duration_usec", 0))
	model.metadata = (data.get("metadata", {}) as Dictionary).duplicate(true)
	for raw_sample: Variant in data.get("samples", []):
		model.samples.append((raw_sample as Dictionary).duplicate(true))
	for raw_event: Variant in data.get("events", []):
		model.events.append((raw_event as Dictionary).duplicate(true))
	return model


static func validate_dictionary(data: Dictionary) -> Dictionary:
	if str(data.get("format", "")) != "RIDING_DIRTY_REPLAY":
		return {"ok": false, "error": "invalid_format"}
	if int(data.get("version", 0)) != FORMAT_VERSION:
		return {"ok": false, "error": "unsupported_version"}
	var interval := int(data.get("sample_interval_usec", 0))
	if interval < MIN_SAMPLE_INTERVAL_USEC or interval > MAX_SAMPLE_INTERVAL_USEC:
		return {"ok": false, "error": "sample_interval_out_of_range"}
	if not data.get("metadata", {}) is Dictionary:
		return {"ok": false, "error": "metadata_not_dictionary"}
	var raw_samples: Variant = data.get("samples", [])
	if not raw_samples is Array or (raw_samples as Array).is_empty() or (raw_samples as Array).size() > MAX_SAMPLES:
		return {"ok": false, "error": "sample_count_out_of_range"}
	var prior_time := -1
	for index in (raw_samples as Array).size():
		var raw_sample: Variant = (raw_samples as Array)[index]
		if not raw_sample is Dictionary:
			return {"ok": false, "error": "sample_%d_not_dictionary" % index}
		var sample := raw_sample as Dictionary
		var time_usec := int(sample.get("t_usec", -1))
		if time_usec < 0 or time_usec <= prior_time or (index == 0 and time_usec != 0):
			return {"ok": false, "error": "sample_%d_time_invalid" % index}
		if index > 0 and absi(time_usec - prior_time - interval) > 1:
			return {"ok": false, "error": "sample_%d_interval_invalid" % index}
		if not _valid_array(sample.get("position", []), 3) or not _valid_array(sample.get("rotation", []), 4):
			return {"ok": false, "error": "sample_%d_transform_invalid" % index}
		if not _valid_array(sample.get("linear_velocity", []), 3) or not _valid_array(sample.get("angular_velocity", []), 3):
			return {"ok": false, "error": "sample_%d_velocity_invalid" % index}
		if not sample.get("input", {}) is Dictionary:
			return {"ok": false, "error": "sample_%d_input_invalid" % index}
		prior_time = time_usec
	if int(data.get("duration_usec", -1)) != prior_time:
		return {"ok": false, "error": "duration_mismatch"}
	var raw_events: Variant = data.get("events", [])
	if not raw_events is Array or (raw_events as Array).size() > MAX_EVENTS:
		return {"ok": false, "error": "events_invalid"}
	for raw_event: Variant in raw_events:
		if not raw_event is Dictionary:
			return {"ok": false, "error": "event_not_dictionary"}
		var event := raw_event as Dictionary
		if str(event.get("name", "")).is_empty():
			return {"ok": false, "error": "event_name_missing"}
		if int(event.get("t_usec", -1)) < 0 or int(event.get("t_usec", -1)) > prior_time:
			return {"ok": false, "error": "event_time_invalid"}
	return {"ok": true, "error": ""}


static func _valid_array(value: Variant, expected_size: int) -> bool:
	if not value is Array or (value as Array).size() != expected_size:
		return false
	for component: Variant in value:
		if typeof(component) not in [TYPE_INT, TYPE_FLOAT]:
			return false
		var number := float(component)
		if is_nan(number) or is_inf(number):
			return false
	return true
