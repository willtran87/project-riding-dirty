extends RefCounted
class_name ActivityRunIdentity
## Creates compact, process-unique activity attempt IDs at run start.

static var _sequence: int = 0


static func create(activity: StringName, profile_id: String = "") -> String:
	_sequence += 1
	var normalized_activity := String(activity).strip_edges().to_upper()
	var entropy := "%s|%s|%d|%d|%d" % [
		normalized_activity,
		profile_id.strip_edges(),
		int(Time.get_unix_time_from_system() * 1_000_000.0),
		Time.get_ticks_usec(),
		_sequence,
	]
	return "%s-%s" % [
		normalized_activity.to_lower(),
		entropy.sha256_text().substr(0, 32),
	]
