extends RefCounted
class_name CompetitiveRunSignature
## Stable identifiers for comparable runs and lightweight payload integrity checks.

const SCHEMA_VERSION: int = 1
## Bumps whenever deterministic bike/racecraft rules change lap potential. It is
## part of the normalized payload while the rs1 envelope remains importable.
const RACECRAFT_VERSION: int = 3
const REQUIRED_CONTEXT_KEYS: Array[String] = [
	"event_id",
	"track_id",
	"route_version",
	"format",
	"laps",
	"bike_class",
	"difficulty",
	"assist_mode",
	"setup_id",
]


static func build(context: Dictionary) -> String:
	var normalized := normalize_context(context)
	var digest := canonical_string(normalized).sha256_text()
	return "rs%d_%s" % [SCHEMA_VERSION, digest]


static func normalize_context(context: Dictionary) -> Dictionary:
	return {
		"schema": SCHEMA_VERSION,
		"racecraft_version": RACECRAFT_VERSION,
		"event_id": _clean_token(context.get("event_id", "UNKNOWN")),
		"track_id": _clean_token(context.get("track_id", "UNKNOWN")),
		"route_version": maxi(int(context.get("route_version", 1)), 1),
		"format": _clean_token(context.get("format", "SPRINT")),
		"laps": clampi(int(context.get("laps", 1)), 1, 999),
		"bike_class": _clean_token(context.get("bike_class", "OPEN")),
		"difficulty": clampi(int(context.get("difficulty", 2)), 0, 10),
		"assist_mode": _clean_token(context.get("assist_mode", "STANDARD")),
		"setup_id": _clean_token(context.get("setup_id", "BALANCED")),
		"tune_signature": str(context.get("tune_signature", "")).strip_edges().substr(0, 256),
		"weather": _clean_token(context.get("weather", "CLEAR")),
		"surface": _clean_token(context.get("surface", "PACKED")),
		"challenge_id": _clean_token(context.get("challenge_id", "NONE")),
		"modifiers": _normalized_string_array(context.get("modifiers", [])),
	}


static func validate(signature: String) -> bool:
	if not signature.begins_with("rs%d_" % SCHEMA_VERSION):
		return false
	var digest := signature.trim_prefix("rs%d_" % SCHEMA_VERSION)
	if digest.length() != 64:
		return false
	for character in digest:
		if not character in "0123456789abcdef":
			return false
	return true


static func entry_checksum(entry: Dictionary) -> String:
	var signed_fields := {
		"run_id": str(entry.get("run_id", "")),
		"run_signature": str(entry.get("run_signature", "")),
		"profile_id": str(entry.get("profile_id", "")),
		"display_name": str(entry.get("display_name", "")),
		"time_usec": int(entry.get("time_usec", -1)),
		"penalty_usec": int(entry.get("penalty_usec", 0)),
		"created_unix": int(entry.get("created_unix", 0)),
		"challenge_id": str(entry.get("challenge_id", "")),
		"metrics": entry.get("metrics", {}),
	}
	return canonical_string(signed_fields).sha256_text()


static func canonical_string(value: Variant) -> String:
	match typeof(value):
		TYPE_NIL:
			return "null"
		TYPE_BOOL:
			return "true" if bool(value) else "false"
		TYPE_INT:
			return str(int(value))
		TYPE_FLOAT:
			var number := float(value)
			if is_nan(number) or is_inf(number):
				return "null"
			if absf(number) <= 9_007_199_254_740_991.0 and number == floor(number):
				return str(int(number))
			return String.num(number, 12)
		TYPE_STRING, TYPE_STRING_NAME:
			return JSON.stringify(str(value))
		TYPE_ARRAY:
			var parts: PackedStringArray = []
			for item: Variant in value:
				parts.append(canonical_string(item))
			return "[" + ",".join(parts) + "]"
		TYPE_DICTIONARY:
			var dictionary := value as Dictionary
			var keys: PackedStringArray = []
			for raw_key: Variant in dictionary.keys():
				keys.append(str(raw_key))
			keys.sort()
			var pairs: PackedStringArray = []
			for key: String in keys:
				var dictionary_key: Variant = key
				if not dictionary.has(dictionary_key):
					dictionary_key = StringName(key)
				pairs.append(JSON.stringify(key) + ":" + canonical_string(dictionary.get(dictionary_key)))
			return "{" + ",".join(pairs) + "}"
		_:
			return JSON.stringify(str(value))


static func _clean_token(value: Variant) -> String:
	var token := str(value).strip_edges().to_upper()
	var safe := ""
	for character in token:
		if character in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-":
			safe += character
	return safe.substr(0, 64) if not safe.is_empty() else "UNKNOWN"


static func _normalized_string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item: Variant in value:
			result.append(_clean_token(item))
	result.sort()
	return result
