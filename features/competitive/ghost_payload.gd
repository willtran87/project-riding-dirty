extends RefCounted
class_name GhostPayload
## Portable, checksummed ghost format. Only primitive JSON data is accepted.

const FORMAT_VERSION: int = 1
const MAX_JSON_BYTES: int = 16 * 1024 * 1024
const MAX_SAMPLES: int = 36_000
const MAX_EVENTS: int = 2_048
const MIN_SAMPLE_INTERVAL_USEC: int = 8_000
const MAX_SAMPLE_INTERVAL_USEC: int = 250_000
const MAX_DURATION_USEC: int = 7_200_000_000
const MAX_WORLD_COORDINATE: float = 1_000_000.0


static func build(
		run_signature: String,
		track_id: String,
		route_version: int,
		sample_interval_usec: int,
		samples: Array,
		events: Array = [],
		metadata: Dictionary = {}
	) -> Dictionary:
	var payload := {
		"format": "RIDING_DIRTY_GHOST",
		"version": FORMAT_VERSION,
		"run_signature": run_signature,
		"track_id": track_id.strip_edges().to_upper().substr(0, 64),
		"route_version": maxi(route_version, 1),
		"sample_interval_usec": sample_interval_usec,
		"duration_usec": int((samples.back() as Dictionary).get("t_usec", 0)) if not samples.is_empty() and samples.back() is Dictionary else 0,
		"samples": samples.duplicate(true),
		"events": events.duplicate(true),
		"metadata": _sanitize_metadata(metadata),
	}
	payload["checksum"] = compute_checksum(payload)
	return payload


static func export_json(payload: Dictionary, pretty: bool = false) -> Dictionary:
	var validation := validate(payload)
	if not bool(validation.get("ok", false)):
		return {"ok": false, "error": validation.get("error", "invalid_payload"), "json": ""}
	# Full precision is required so the checksum survives a JSON round trip.
	var text := JSON.stringify(payload, "\t" if pretty else "", true, true)
	if text.to_utf8_buffer().size() > MAX_JSON_BYTES:
		return {"ok": false, "error": "payload_too_large", "json": ""}
	return {"ok": true, "error": "", "json": text}


static func import_json(text: String) -> Dictionary:
	if text.to_utf8_buffer().size() > MAX_JSON_BYTES:
		return {"ok": false, "error": "payload_too_large", "payload": {}}
	var json := JSON.new()
	if json.parse(text) != OK:
		return {"ok": false, "error": "json_parse_error_at_line_%d" % json.get_error_line(), "payload": {}}
	if not json.data is Dictionary:
		return {"ok": false, "error": "payload_must_be_dictionary", "payload": {}}
	var payload := json.data as Dictionary
	var validation := validate(payload)
	if not bool(validation.get("ok", false)):
		return {"ok": false, "error": validation.get("error", "invalid_payload"), "payload": {}}
	return {"ok": true, "error": "", "payload": payload.duplicate(true)}


static func validate(payload: Dictionary) -> Dictionary:
	var allowed_keys: Array[String] = [
		"format", "version", "run_signature", "track_id", "route_version",
		"sample_interval_usec", "duration_usec", "samples", "events", "metadata", "checksum",
	]
	if payload.size() > allowed_keys.size():
		return _invalid("unsafe_or_oversized_payload")
	for raw_key: Variant in payload.keys():
		if str(raw_key) not in allowed_keys:
			return _invalid("unexpected_payload_field")
	if str(payload.get("format", "")) != "RIDING_DIRTY_GHOST":
		return _invalid("invalid_format")
	if int(payload.get("version", 0)) != FORMAT_VERSION:
		return _invalid("unsupported_version")
	if not CompetitiveRunSignature.validate(str(payload.get("run_signature", ""))):
		return _invalid("invalid_run_signature")
	if str(payload.get("track_id", "")).strip_edges().is_empty():
		return _invalid("missing_track_id")
	if int(payload.get("route_version", 0)) < 1:
		return _invalid("invalid_route_version")
	var interval := int(payload.get("sample_interval_usec", 0))
	if interval < MIN_SAMPLE_INTERVAL_USEC or interval > MAX_SAMPLE_INTERVAL_USEC:
		return _invalid("sample_interval_out_of_range")
	var raw_samples: Variant = payload.get("samples", [])
	if not raw_samples is Array:
		return _invalid("samples_must_be_array")
	var samples := raw_samples as Array
	if samples.is_empty() or samples.size() > MAX_SAMPLES:
		return _invalid("sample_count_out_of_range")
	var prior_time := -1
	for index in samples.size():
		var raw_sample: Variant = samples[index]
		if not raw_sample is Dictionary:
			return _invalid("sample_%d_not_dictionary" % index)
		var sample := raw_sample as Dictionary
		var sample_validation := _validate_sample(sample, prior_time, interval, index)
		if not bool(sample_validation.get("ok", false)):
			return sample_validation
		prior_time = int(sample.get("t_usec", -1))
	if prior_time > MAX_DURATION_USEC or int(payload.get("duration_usec", -1)) != prior_time:
		return _invalid("duration_mismatch_or_out_of_range")
	var raw_events: Variant = payload.get("events", [])
	if not raw_events is Array or (raw_events as Array).size() > MAX_EVENTS:
		return _invalid("events_out_of_range")
	for index in (raw_events as Array).size():
		var raw_event: Variant = (raw_events as Array)[index]
		if not raw_event is Dictionary:
			return _invalid("event_%d_not_dictionary" % index)
		var event := raw_event as Dictionary
		var event_time := int(event.get("t_usec", -1))
		if event_time < 0 or event_time > prior_time:
			return _invalid("event_%d_time_out_of_range" % index)
		var event_name := str(event.get("name", ""))
		if event_name.is_empty() or event_name.length() > 64:
			return _invalid("event_%d_name_invalid" % index)
		var event_payload: Variant = event.get("payload", {})
		if not event_payload is Dictionary or not _is_safe_json_variant(event_payload):
			return _invalid("event_%d_payload_invalid" % index)
	var raw_metadata: Variant = payload.get("metadata", {})
	if not raw_metadata is Dictionary or (raw_metadata as Dictionary).size() > 32:
		return _invalid("metadata_must_be_dictionary")
	if not _is_safe_json_variant(raw_metadata):
		return _invalid("metadata_contains_unsafe_value")
	var expected_checksum := compute_checksum(payload)
	if str(payload.get("checksum", "")) != expected_checksum:
		return _invalid("checksum_mismatch")
	return {"ok": true, "error": ""}


static func compute_checksum(payload: Dictionary) -> String:
	var unsigned := payload.duplicate(true)
	unsigned.erase("checksum")
	return CompetitiveRunSignature.canonical_string(unsigned).sha256_text()


static func _validate_sample(sample: Dictionary, prior_time: int, interval: int, index: int) -> Dictionary:
	if sample.size() > 12 or not _is_safe_json_variant(sample):
		return _invalid("sample_%d_contains_unsafe_value" % index)
	var sample_time := int(sample.get("t_usec", -1))
	if sample_time < 0 or sample_time <= prior_time:
		return _invalid("sample_%d_time_not_increasing" % index)
	if index == 0 and sample_time != 0:
		return _invalid("first_sample_must_start_at_zero")
	if index > 0:
		var step := sample_time - prior_time
		if absi(step - interval) > 1:
			return _invalid("sample_%d_not_fixed_interval" % index)
	if not _valid_numeric_array(sample.get("position", []), 3, MAX_WORLD_COORDINATE):
		return _invalid("sample_%d_position_invalid" % index)
	if not _valid_numeric_array(sample.get("rotation", []), 4, 1.001):
		return _invalid("sample_%d_rotation_invalid" % index)
	var rotation := sample.get("rotation", []) as Array
	var norm_squared := 0.0
	for component: Variant in rotation:
		norm_squared += float(component) * float(component)
	if norm_squared < 0.8 or norm_squared > 1.2:
		return _invalid("sample_%d_rotation_not_normalized" % index)
	if sample.has("linear_velocity") and not _valid_numeric_array(sample.get("linear_velocity", []), 3, 500.0):
		return _invalid("sample_%d_velocity_invalid" % index)
	var speed := float(sample.get("speed_mps", 0.0))
	if is_nan(speed) or is_inf(speed) or speed < 0.0 or speed > 500.0:
		return _invalid("sample_%d_speed_invalid" % index)
	var progress := float(sample.get("progress", 0.0))
	if is_nan(progress) or is_inf(progress) or progress < -0.05 or progress > MAX_WORLD_COORDINATE:
		return _invalid("sample_%d_progress_invalid" % index)
	return {"ok": true, "error": ""}


static func _valid_numeric_array(value: Variant, expected_size: int, magnitude_limit: float) -> bool:
	if not value is Array or (value as Array).size() != expected_size:
		return false
	for component: Variant in value:
		if typeof(component) not in [TYPE_INT, TYPE_FLOAT]:
			return false
		var number := float(component)
		if is_nan(number) or is_inf(number) or absf(number) > magnitude_limit:
			return false
	return true


static func _sanitize_metadata(metadata: Dictionary) -> Dictionary:
	var output: Dictionary = {}
	var count := 0
	for raw_key: Variant in metadata.keys():
		if count >= 32:
			break
		var key := str(raw_key).strip_edges().substr(0, 48)
		var value: Variant = metadata.get(raw_key)
		if key.is_empty() or typeof(value) not in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING]:
			continue
		if typeof(value) == TYPE_FLOAT and (is_nan(float(value)) or is_inf(float(value))):
			continue
		output[key] = str(value).substr(0, 256) if typeof(value) == TYPE_STRING else value
		count += 1
	return output


static func _is_safe_json_variant(value: Variant, depth: int = 0) -> bool:
	if depth > 8:
		return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT:
			return true
		TYPE_FLOAT:
			return not is_nan(float(value)) and not is_inf(float(value))
		TYPE_STRING, TYPE_STRING_NAME:
			return str(value).length() <= 4_096
		TYPE_ARRAY:
			var array := value as Array
			if array.size() > 512:
				return false
			for item: Variant in array:
				if not _is_safe_json_variant(item, depth + 1):
					return false
			return true
		TYPE_DICTIONARY:
			var dictionary := value as Dictionary
			if dictionary.size() > 128:
				return false
			for key: Variant in dictionary.keys():
				if typeof(key) not in [TYPE_STRING, TYPE_STRING_NAME] or str(key).length() > 128:
					return false
				if not _is_safe_json_variant(dictionary.get(key), depth + 1):
					return false
			return true
	return false


static func _invalid(error: String) -> Dictionary:
	return {"ok": false, "error": error}
