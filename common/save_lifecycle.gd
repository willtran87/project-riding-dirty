extends Node
## Shared save-state authority for visible feedback and critical-write guards.

signal state_changed(snapshot: Dictionary)

const STATE_IDLE: StringName = &"IDLE"
const STATE_SAVING: StringName = &"SAVING"
const STATE_SAVED: StringName = &"SAVED"
const STATE_RECOVERED: StringName = &"RECOVERED"
const STATE_FAILED: StringName = &"FAILED"

var _next_token: int = 1
var _active_saves: Dictionary = {}
var _latest_snapshot: Dictionary = {
	&"state": STATE_IDLE,
	&"domain": &"",
	&"context": "",
	&"critical": false,
	&"critical_count": 0,
	&"active_count": 0,
	&"error": "",
	&"sequence": 0,
}
var _sequence: int = 0


func begin_save(domain: StringName, context: String, critical: bool = true) -> int:
	var token := _next_token
	_next_token += 1
	var entry := {
		&"domain": _safe_domain(domain),
		&"context": _safe_context(context),
		&"critical": critical,
	}
	_active_saves[token] = entry
	_publish(STATE_SAVING, entry, "")
	return token


func finish_save(token: int, succeeded: bool, error: String = "") -> bool:
	if not _active_saves.has(token):
		return false
	var entry := (_active_saves[token] as Dictionary).duplicate(true)
	_active_saves.erase(token)
	if succeeded and not _active_saves.is_empty():
		_publish(STATE_SAVING, _latest_active_entry(), "")
	else:
		_publish(STATE_SAVED if succeeded else STATE_FAILED, entry, "" if succeeded else _safe_error(error))
	return succeeded


func report_recovered(domain: StringName, context: String, repaired: bool = true) -> void:
	_publish(STATE_RECOVERED, {
		&"domain": _safe_domain(domain),
		&"context": _safe_context(context),
		&"critical": false,
		&"repaired": repaired,
	}, "")


func report_failure(domain: StringName, context: String, error: String) -> void:
	_publish(STATE_FAILED, {
		&"domain": _safe_domain(domain),
		&"context": _safe_context(context),
		&"critical": false,
	}, _safe_error(error))


func is_critical_save_active() -> bool:
	return _critical_count() > 0


func get_snapshot() -> Dictionary:
	return _latest_snapshot.duplicate(true)


func reset_for_testing() -> void:
	_active_saves.clear()
	_next_token = 1
	_sequence = 0
	_latest_snapshot = {
		&"state": STATE_IDLE,
		&"domain": &"",
		&"context": "",
		&"critical": false,
		&"critical_count": 0,
		&"active_count": 0,
		&"error": "",
		&"sequence": 0,
	}
	state_changed.emit(get_snapshot())


func _publish(state: StringName, entry: Dictionary, error: String) -> void:
	_sequence += 1
	_latest_snapshot = {
		&"state": state,
		&"domain": entry.get(&"domain", &"SYSTEM"),
		&"context": entry.get(&"context", "PROGRESS"),
		&"critical": bool(entry.get(&"critical", false)),
		&"critical_count": _critical_count(),
		&"active_count": _active_saves.size(),
		&"error": error,
		&"repaired": bool(entry.get(&"repaired", false)),
		&"sequence": _sequence,
	}
	state_changed.emit(get_snapshot())


func _critical_count() -> int:
	var count := 0
	for raw_entry: Variant in _active_saves.values():
		if raw_entry is Dictionary and bool((raw_entry as Dictionary).get(&"critical", false)):
			count += 1
	return count


func _latest_active_entry() -> Dictionary:
	var latest_token := -1
	for raw_token: Variant in _active_saves.keys():
		latest_token = maxi(latest_token, int(raw_token))
	return (_active_saves.get(latest_token, {}) as Dictionary).duplicate(true)


func _safe_domain(domain: StringName) -> StringName:
	var normalized := String(domain).strip_edges().to_upper()
	return StringName(normalized if not normalized.is_empty() else "SYSTEM")


func _safe_context(context: String) -> String:
	var normalized := context.strip_edges().to_upper()
	return normalized.left(56) if not normalized.is_empty() else "PROGRESS"


func _safe_error(error: String) -> String:
	var normalized := error.strip_edges().to_lower()
	return normalized.left(96) if not normalized.is_empty() else "write_failed"
