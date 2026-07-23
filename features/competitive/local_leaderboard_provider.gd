extends LeaderboardProvider
class_name LocalLeaderboardProvider
## Versioned local leaderboard with per-board ranking and personal-best retention.

const STORAGE_VERSION: int = 1
const DEFAULT_STORAGE_PATH: String = "user://competitive/leaderboards.json"

var storage_path: String = DEFAULT_STORAGE_PATH
var maximum_entries_per_board: int = 100
var best_per_profile: bool = true

var _boards: Dictionary = {}


func _init(custom_storage_path: String = DEFAULT_STORAGE_PATH) -> void:
	storage_path = custom_storage_path if custom_storage_path.begins_with("user://") else DEFAULT_STORAGE_PATH
	_load_from_disk()


func submit_run(entry: Dictionary) -> Dictionary:
	var validation := LeaderboardProvider.validate_entry(entry)
	if not bool(validation.get("ok", false)):
		var rejected := {"ok": false, "error": validation.get("error", "invalid_entry"), "queued": false}
		submission_completed.emit(rejected)
		return rejected
	var normalized := LeaderboardProvider.normalized_entry(entry)
	var board_key := str(normalized.get("run_signature", ""))
	var board: Array = (_boards.get(board_key, []) as Array).duplicate(true)
	for existing: Variant in board:
		if existing is Dictionary and str((existing as Dictionary).get("run_id", "")) == str(normalized.get("run_id", "")):
			var duplicate := {"ok": true, "accepted": false, "duplicate": true, "entry": existing}
			submission_completed.emit(duplicate)
			return duplicate
	if best_per_profile:
		var profile_id := str(normalized.get("profile_id", ""))
		for index in range(board.size() - 1, -1, -1):
			var prior: Variant = board[index]
			if prior is Dictionary and str((prior as Dictionary).get("profile_id", "")) == profile_id:
				if LeaderboardProvider.effective_time_usec(prior) <= LeaderboardProvider.effective_time_usec(normalized):
					var slower := {"ok": true, "accepted": false, "personal_best": false, "entry": prior}
					submission_completed.emit(slower)
					return slower
				board.remove_at(index)
	board.append(normalized)
	board.sort_custom(_entry_precedes)
	if board.size() > maximum_entries_per_board:
		board.resize(maximum_entries_per_board)
	_boards[board_key] = board
	var saved := _save_to_disk()
	var rank := _find_run_rank(board, str(normalized.get("run_id", "")))
	var result := {
		"ok": saved,
		"accepted": true,
		"personal_best": true,
		"rank": rank,
		"entry": normalized.duplicate(true),
		"error": "" if saved else "persistence_failed",
	}
	submission_completed.emit(result)
	return result


func fetch_board(run_signature: String, limit: int = 20, offset: int = 0) -> Dictionary:
	if not CompetitiveRunSignature.validate(run_signature):
		return {"ok": false, "error": "invalid_run_signature", "entries": []}
	var board: Array = (_boards.get(run_signature, []) as Array).duplicate(true)
	var safe_offset := clampi(offset, 0, board.size())
	var safe_limit := clampi(limit, 1, 100)
	var entries: Array[Dictionary] = []
	for index in range(safe_offset, mini(board.size(), safe_offset + safe_limit)):
		var entry := (board[index] as Dictionary).duplicate(true)
		entry["rank"] = index + 1
		entries.append(entry)
	var result := {"ok": true, "error": "", "total": board.size(), "offset": safe_offset, "entries": entries}
	board_received.emit(result)
	return result


func get_personal_best(run_signature: String, profile_id: String) -> Dictionary:
	var board: Array = _boards.get(run_signature, []) as Array
	for index in board.size():
		var entry: Variant = board[index]
		if entry is Dictionary and str((entry as Dictionary).get("profile_id", "")) == profile_id:
			var result := (entry as Dictionary).duplicate(true)
			result["rank"] = index + 1
			return result
	return {}


func clear_board(run_signature: String) -> bool:
	if not _boards.has(run_signature):
		return true
	_boards.erase(run_signature)
	return _save_to_disk()


func reload() -> bool:
	return _load_from_disk()


func _load_from_disk() -> bool:
	_boards.clear()
	if not FileAccess.file_exists(storage_path):
		return true
	var file := FileAccess.open(storage_path, FileAccess.READ)
	if file == null:
		return false
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return false
	var payload := parsed as Dictionary
	if int(payload.get("version", 0)) != STORAGE_VERSION:
		return false
	var raw_boards: Variant = payload.get("boards", {})
	if not raw_boards is Dictionary:
		return false
	for raw_signature: Variant in (raw_boards as Dictionary).keys():
		var signature := str(raw_signature)
		if not CompetitiveRunSignature.validate(signature):
			continue
		var raw_entries: Variant = (raw_boards as Dictionary).get(raw_signature, [])
		if not raw_entries is Array:
			continue
		var entries: Array = []
		for raw_entry: Variant in raw_entries:
			if raw_entry is Dictionary and bool(LeaderboardProvider.validate_entry(raw_entry).get("ok", false)):
				entries.append(LeaderboardProvider.normalized_entry(raw_entry))
		entries.sort_custom(_entry_precedes)
		if entries.size() > maximum_entries_per_board:
			entries.resize(maximum_entries_per_board)
		_boards[signature] = entries
	return true


func _save_to_disk() -> bool:
	var base_dir := storage_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(base_dir):
		var directory_error := DirAccess.make_dir_recursive_absolute(base_dir)
		if directory_error != OK:
			return false
	var temporary_path := storage_path + ".tmp"
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"version": STORAGE_VERSION, "boards": _boards}, "\t"))
	file.close()
	var absolute_target := ProjectSettings.globalize_path(storage_path)
	var absolute_temporary := ProjectSettings.globalize_path(temporary_path)
	var absolute_backup := absolute_target + ".bak"
	if FileAccess.file_exists(storage_path):
		DirAccess.copy_absolute(absolute_target, absolute_backup)
		var remove_error := DirAccess.remove_absolute(absolute_target)
		if remove_error != OK:
			DirAccess.remove_absolute(absolute_temporary)
			return false
	return DirAccess.rename_absolute(absolute_temporary, absolute_target) == OK


func _entry_precedes(a: Dictionary, b: Dictionary) -> bool:
	var a_time := LeaderboardProvider.effective_time_usec(a)
	var b_time := LeaderboardProvider.effective_time_usec(b)
	if a_time != b_time:
		return a_time < b_time
	var a_created := int(a.get("created_unix", 0))
	var b_created := int(b.get("created_unix", 0))
	if a_created != b_created:
		return a_created < b_created
	return str(a.get("run_id", "")) < str(b.get("run_id", ""))


func _find_run_rank(board: Array, run_id: String) -> int:
	for index in board.size():
		var entry: Variant = board[index]
		if entry is Dictionary and str((entry as Dictionary).get("run_id", "")) == run_id:
			return index + 1
	return 0
