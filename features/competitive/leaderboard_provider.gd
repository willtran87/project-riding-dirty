extends RefCounted
class_name LeaderboardProvider
## Provider contract shared by local and optional online leaderboard backends.

signal submission_completed(result: Dictionary)
signal board_received(result: Dictionary)
signal queue_changed(pending_count: int)

const ENTRY_VERSION: int = 1
const MAX_DISPLAY_NAME_LENGTH: int = 24
const MAX_METRIC_KEYS: int = 32


func submit_run(_entry: Dictionary) -> Dictionary:
	return {"ok": false, "error": "provider_does_not_support_submission"}


func fetch_board(_run_signature: String, _limit: int = 20, _offset: int = 0) -> Dictionary:
	return {"ok": false, "error": "provider_does_not_support_fetch", "entries": []}


func get_personal_best(_run_signature: String, _profile_id: String) -> Dictionary:
	return {}


func flush_pending() -> Dictionary:
	return {"ok": true, "submitted": 0, "remaining": 0}


static func create_entry(
		run_signature: String,
		profile_id: String,
		display_name: String,
		time_usec: int,
		options: Dictionary = {}
	) -> Dictionary:
	var created_unix := int(options.get("created_unix", Time.get_unix_time_from_system()))
	var supplied_run_id := str(options.get("run_id", "")).strip_edges()
	var entropy := "%s|%s|%d|%d|%s" % [
		run_signature, profile_id, time_usec, created_unix, str(options.get("nonce", Time.get_ticks_usec())),
	]
	var entry := {
		"version": ENTRY_VERSION,
		"run_id": supplied_run_id if not supplied_run_id.is_empty() else "run_" + entropy.sha256_text().substr(0, 24),
		"run_signature": run_signature,
		"profile_id": profile_id.strip_edges().substr(0, 64),
		"display_name": display_name.strip_edges().substr(0, MAX_DISPLAY_NAME_LENGTH),
		"time_usec": time_usec,
		"penalty_usec": maxi(int(options.get("penalty_usec", 0)), 0),
		"created_unix": maxi(created_unix, 0),
		"challenge_id": str(options.get("challenge_id", "")).strip_edges().substr(0, 96),
		"metrics": _sanitize_metrics(options.get("metrics", {})),
	}
	entry["checksum"] = CompetitiveRunSignature.entry_checksum(entry)
	return entry


static func validate_entry(entry: Dictionary, verify_checksum: bool = true) -> Dictionary:
	if int(entry.get("version", 0)) != ENTRY_VERSION:
		return {"ok": false, "error": "unsupported_entry_version"}
	if str(entry.get("run_id", "")).strip_edges().is_empty():
		return {"ok": false, "error": "missing_run_id"}
	var run_signature := str(entry.get("run_signature", ""))
	if not CompetitiveRunSignature.validate(run_signature):
		return {"ok": false, "error": "invalid_run_signature"}
	if str(entry.get("profile_id", "")).strip_edges().is_empty():
		return {"ok": false, "error": "missing_profile_id"}
	var display_name := str(entry.get("display_name", ""))
	if display_name.strip_edges().is_empty() or display_name.length() > MAX_DISPLAY_NAME_LENGTH:
		return {"ok": false, "error": "invalid_display_name"}
	var time_usec := int(entry.get("time_usec", -1))
	if time_usec <= 0 or time_usec > 86_400_000_000:
		return {"ok": false, "error": "invalid_time"}
	var penalty_usec := int(entry.get("penalty_usec", 0))
	if penalty_usec < 0 or penalty_usec > 86_400_000_000:
		return {"ok": false, "error": "invalid_penalty"}
	var metrics: Variant = entry.get("metrics", {})
	if not metrics is Dictionary or (metrics as Dictionary).size() > MAX_METRIC_KEYS:
		return {"ok": false, "error": "invalid_metrics"}
	if verify_checksum:
		var expected := CompetitiveRunSignature.entry_checksum(entry)
		if str(entry.get("checksum", "")) != expected:
			return {"ok": false, "error": "checksum_mismatch"}
	return {"ok": true, "error": ""}


static func normalized_entry(entry: Dictionary) -> Dictionary:
	var normalized := {
		"version": ENTRY_VERSION,
		"run_id": str(entry.get("run_id", "")).strip_edges().substr(0, 96),
		"run_signature": str(entry.get("run_signature", "")).strip_edges(),
		"profile_id": str(entry.get("profile_id", "")).strip_edges().substr(0, 64),
		"display_name": str(entry.get("display_name", "")).strip_edges().substr(0, MAX_DISPLAY_NAME_LENGTH),
		"time_usec": int(entry.get("time_usec", -1)),
		"penalty_usec": maxi(int(entry.get("penalty_usec", 0)), 0),
		"created_unix": maxi(int(entry.get("created_unix", 0)), 0),
		"challenge_id": str(entry.get("challenge_id", "")).strip_edges().substr(0, 96),
		"metrics": _sanitize_metrics(entry.get("metrics", {})),
	}
	normalized["checksum"] = CompetitiveRunSignature.entry_checksum(normalized)
	return normalized


static func effective_time_usec(entry: Dictionary) -> int:
	return int(entry.get("time_usec", 0)) + int(entry.get("penalty_usec", 0))


static func _sanitize_metrics(value: Variant) -> Dictionary:
	var output: Dictionary = {}
	if not value is Dictionary:
		return output
	var input := value as Dictionary
	var count := 0
	for raw_key: Variant in input.keys():
		if count >= MAX_METRIC_KEYS:
			break
		var key := str(raw_key).strip_edges().substr(0, 48)
		var metric: Variant = input.get(raw_key)
		if key.is_empty() or typeof(metric) not in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING]:
			continue
		if typeof(metric) == TYPE_FLOAT and (is_nan(float(metric)) or is_inf(float(metric))):
			continue
		output[key] = str(metric).substr(0, 128) if typeof(metric) == TYPE_STRING else metric
		count += 1
	return output
