extends RefCounted
class_name PlayerRaceMetrics
## Player-owned competitive telemetry. Field chaos never writes to this object.

const CRASH_RECOVERY_REASONS: Array[StringName] = [
	&"AUTO_TIPPED",
	&"AUTO_WORLD_FALL",
]

var _last_position: int = -1
var _overtakes: int = 0
var _positions_lost: int = 0
var _contacts: int = 0
var _crashes: int = 0
var _recoveries: int = 0
var _recovery_reasons: Dictionary[StringName, int] = {}


func reset() -> void:
	_last_position = -1
	_overtakes = 0
	_positions_lost = 0
	_contacts = 0
	_crashes = 0
	_recoveries = 0
	_recovery_reasons.clear()


func observe_position(position: int) -> Dictionary:
	var normalized_position := maxi(position, 1)
	var previous_position := _last_position
	_last_position = normalized_position
	return {
		&"previous_position": previous_position,
		&"position": normalized_position,
		&"places_gained": maxi(previous_position - normalized_position, 0) if previous_position > 0 else 0,
		&"places_lost": maxi(normalized_position - previous_position, 0) if previous_position > 0 else 0,
	}


func record_overtake(count: int = 1) -> void:
	_overtakes += maxi(count, 0)


func record_position_lost(count: int = 1) -> void:
	_positions_lost += maxi(count, 0)


func record_contact() -> void:
	_contacts += 1


func record_recovery(reason: StringName) -> void:
	var normalized_reason := reason if not reason.is_empty() else &"RECOVERY"
	_recoveries += 1
	_recovery_reasons[normalized_reason] = int(_recovery_reasons.get(normalized_reason, 0)) + 1
	if normalized_reason in CRASH_RECOVERY_REASONS:
		_crashes += 1


func get_snapshot() -> Dictionary:
	return {
		&"last_position": _last_position,
		&"overtakes": _overtakes,
		&"positions_lost": _positions_lost,
		&"contacts": _contacts,
		&"crashes": _crashes,
		&"recoveries": _recoveries,
		&"recovery_reasons": _recovery_reasons.duplicate(),
	}
