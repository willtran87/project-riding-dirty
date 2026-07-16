extends RefCounted
class_name VerifiedJsonCodec
## Integrity envelope and deterministic primary/backup selection for JSON saves.

const FORMAT_MARKER: String = "__riding_dirty_verified_json"
const FORMAT_VERSION: int = 1


static func encode(value: Variant) -> String:
	var payload_json := JSON.stringify(value)
	return JSON.stringify({
		FORMAT_MARKER: FORMAT_VERSION,
		"payload_json": payload_json,
		"sha256": payload_json.sha256_text(),
	})


static func decode(raw_text: String, allow_legacy: bool = true) -> Dictionary:
	if raw_text.strip_edges().is_empty():
		return _failure("empty")
	var parser := JSON.new()
	var parse_error := parser.parse(raw_text)
	if parse_error != OK:
		return _failure("invalid_json")
	var parsed: Variant = parser.data
	if parsed is Dictionary and (parsed as Dictionary).has(FORMAT_MARKER):
		return _decode_envelope(parsed as Dictionary)
	if not allow_legacy:
		return _failure("legacy_not_allowed")
	return {
		"ok": true,
		"value": parsed,
		"legacy": true,
		"error": "",
	}


static func recover(primary_raw: Variant, backup_raw: Variant, allow_legacy: bool = true) -> Dictionary:
	var primary := _decode_candidate(primary_raw, allow_legacy)
	if bool(primary.get("ok", false)):
		primary["source"] = "primary"
		return primary
	var backup := _decode_candidate(backup_raw, allow_legacy)
	if bool(backup.get("ok", false)):
		backup["source"] = "backup"
		backup["primary_error"] = str(primary.get("error", "invalid_primary"))
		return backup
	return {
		"ok": false,
		"value": null,
		"legacy": false,
		"source": "",
		"error": "no_valid_candidate",
		"primary_error": str(primary.get("error", "missing")),
		"backup_error": str(backup.get("error", "missing")),
	}


static func _decode_candidate(raw_value: Variant, allow_legacy: bool) -> Dictionary:
	if raw_value == null:
		return _failure("missing")
	return decode(str(raw_value), allow_legacy)


static func _decode_envelope(envelope: Dictionary) -> Dictionary:
	if int(envelope.get(FORMAT_MARKER, 0)) != FORMAT_VERSION:
		return _failure("unsupported_format")
	var payload_value: Variant = envelope.get("payload_json", null)
	var checksum_value: Variant = envelope.get("sha256", null)
	if not payload_value is String or not checksum_value is String:
		return _failure("invalid_envelope")
	var payload_json := payload_value as String
	var expected_checksum := checksum_value as String
	if expected_checksum.length() != 64 or payload_json.sha256_text() != expected_checksum:
		return _failure("checksum_mismatch")
	var payload_parser := JSON.new()
	var payload_error := payload_parser.parse(payload_json)
	if payload_error != OK:
		return _failure("invalid_payload")
	return {
		"ok": true,
		"value": payload_parser.data,
		"legacy": false,
		"error": "",
	}


static func _failure(error_code: String) -> Dictionary:
	return {
		"ok": false,
		"value": null,
		"legacy": false,
		"error": error_code,
	}
