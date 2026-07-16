extends LeaderboardProvider
class_name HttpLeaderboardProvider
## Optional online provider adapter with a durable FIFO submission queue.
##
## Supply a transport Callable with this signature:
##   func(method: String, url: String, payload: Dictionary) -> Dictionary
## The returned Dictionary must contain `ok: bool`; fetch responses also contain
## `entries: Array`. This keeps authentication and HTTPRequest ownership in the
## platform layer while this class owns validation, retry, and offline behavior.

const QUEUE_VERSION: int = 1
const DEFAULT_QUEUE_PATH: String = "user://competitive/http_submission_queue.json"
const MAX_PENDING_RUNS: int = 256

var base_url: String = ""
var queue_path: String = DEFAULT_QUEUE_PATH
var transport: Callable = Callable()
var request_headers: Dictionary = {}

var _pending: Array[Dictionary] = []


func _init(endpoint: String = "", custom_queue_path: String = DEFAULT_QUEUE_PATH) -> void:
	base_url = endpoint.trim_suffix("/")
	queue_path = custom_queue_path if custom_queue_path.begins_with("user://") else DEFAULT_QUEUE_PATH
	_load_queue()


func configure(endpoint: String, transport_callable: Callable, headers: Dictionary = {}) -> void:
	base_url = endpoint.strip_edges().trim_suffix("/")
	transport = transport_callable
	request_headers = headers.duplicate(true)


func submit_run(entry: Dictionary) -> Dictionary:
	var validation := LeaderboardProvider.validate_entry(entry)
	if not bool(validation.get("ok", false)):
		var rejected := {"ok": false, "error": validation.get("error", "invalid_entry"), "queued": false}
		submission_completed.emit(rejected)
		return rejected
	var normalized := LeaderboardProvider.normalized_entry(entry)
	if is_online_ready():
		var response := _request("POST", "/v1/runs", {"entry": normalized})
		if bool(response.get("ok", false)):
			response["queued"] = false
			submission_completed.emit(response)
			return response
	var queued := _enqueue(normalized)
	var result := {
		"ok": queued,
		"accepted": queued,
		"queued": queued,
		"error": "offline_queued" if queued else "queue_full_or_unwritable",
		"pending": _pending.size(),
	}
	submission_completed.emit(result)
	return result


func fetch_board(run_signature: String, limit: int = 20, offset: int = 0) -> Dictionary:
	if not CompetitiveRunSignature.validate(run_signature):
		return {"ok": false, "error": "invalid_run_signature", "entries": []}
	if not is_online_ready():
		return {"ok": false, "error": "offline", "entries": []}
	var payload := {
		"run_signature": run_signature,
		"limit": clampi(limit, 1, 100),
		"offset": maxi(offset, 0),
	}
	var result := _request("GET", "/v1/leaderboards/query", payload)
	if not bool(result.get("ok", false)):
		result["entries"] = []
		return result
	var safe_entries: Array[Dictionary] = []
	var raw_entries: Variant = result.get("entries", [])
	if raw_entries is Array:
		for raw_entry: Variant in raw_entries:
			if raw_entry is Dictionary and bool(LeaderboardProvider.validate_entry(raw_entry).get("ok", false)):
				safe_entries.append(LeaderboardProvider.normalized_entry(raw_entry))
	result["entries"] = safe_entries
	board_received.emit(result)
	return result


func flush_pending() -> Dictionary:
	if not is_online_ready():
		return {"ok": false, "error": "offline", "submitted": 0, "remaining": _pending.size()}
	var submitted := 0
	var remaining: Array[Dictionary] = []
	for index in _pending.size():
		var entry := _pending[index]
		var response := _request("POST", "/v1/runs", {"entry": entry})
		if bool(response.get("ok", false)):
			submitted += 1
		else:
			for pending_index in range(index, _pending.size()):
				remaining.append(_pending[pending_index])
			break
	_pending = remaining
	var saved := _save_queue()
	queue_changed.emit(_pending.size())
	return {
		"ok": saved and _pending.is_empty(),
		"submitted": submitted,
		"remaining": _pending.size(),
		"error": "" if saved and _pending.is_empty() else "submission_or_persistence_failed",
	}


func pending_count() -> int:
	return _pending.size()


func pending_entries() -> Array[Dictionary]:
	return _pending.duplicate(true)


func is_online_ready() -> bool:
	return not base_url.is_empty() and transport.is_valid()


func _request(method: String, path: String, payload: Dictionary) -> Dictionary:
	if not is_online_ready():
		return {"ok": false, "error": "offline"}
	var envelope := payload.duplicate(true)
	envelope["headers"] = request_headers.duplicate(true)
	var raw_response: Variant = transport.call(method, base_url + path, envelope)
	if not raw_response is Dictionary:
		return {"ok": false, "error": "invalid_transport_response"}
	return (raw_response as Dictionary).duplicate(true)


func _enqueue(entry: Dictionary) -> bool:
	var run_id := str(entry.get("run_id", ""))
	for queued: Dictionary in _pending:
		if str(queued.get("run_id", "")) == run_id:
			return true
	if _pending.size() >= MAX_PENDING_RUNS:
		return false
	_pending.append(entry.duplicate(true))
	var saved := _save_queue()
	queue_changed.emit(_pending.size())
	return saved


func _load_queue() -> bool:
	_pending.clear()
	if not FileAccess.file_exists(queue_path):
		return true
	var file := FileAccess.open(queue_path, FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return false
	var payload := parsed as Dictionary
	if int(payload.get("version", 0)) != QUEUE_VERSION:
		return false
	var entries: Variant = payload.get("pending", [])
	if not entries is Array:
		return false
	for raw_entry: Variant in entries:
		if _pending.size() >= MAX_PENDING_RUNS:
			break
		if raw_entry is Dictionary and bool(LeaderboardProvider.validate_entry(raw_entry).get("ok", false)):
			_pending.append(LeaderboardProvider.normalized_entry(raw_entry))
	return true


func _save_queue() -> bool:
	var base_dir := queue_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(base_dir):
		if DirAccess.make_dir_recursive_absolute(base_dir) != OK:
			return false
	var file := FileAccess.open(queue_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"version": QUEUE_VERSION, "pending": _pending}, "\t"))
	file.close()
	return true
