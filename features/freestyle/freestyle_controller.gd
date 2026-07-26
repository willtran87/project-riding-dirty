extends Node
class_name FreestyleController
## Timed jump session scoring airtime, rotation, landing quality, and clean combos.

signal hud_updated(time_left_usec: int, score: int, combo: int, last_airtime: float)

const SPAWN_TRANSFORM := Transform3D(Basis.IDENTITY, Vector3(0.0, 1.4, 31.0))
const SESSION_USEC: int = 60_000_000
const SIMULATION_CLOCK_SCRIPT := preload("res://common/simulation_clock.gd")
const TRICK_RULES := preload("res://features/freestyle/freestyle_trick_rules.gd")
const RECENT_TRICK_LIMIT: int = 4

var bike: DirtBikeController
var ghost: GhostController
var active: bool = false
var score: int = 0
var combo: int = 1

var _run_clock: SimulationClock = SIMULATION_CLOCK_SCRIPT.new()
var _last_airtime: float = 0.0
var _attempt_context: Dictionary = {}
var _pending_submission: Dictionary = {}
var _trick_counts: Dictionary = {}
var _recent_trick_ids: Array[StringName] = []
var _last_trick_result: Dictionary = {}


func _physics_process(delta: float) -> void:
	if not active:
		return
	var elapsed_usec := _run_clock.advance(delta)
	var time_left_usec := maxi(SESSION_USEC - elapsed_usec, 0)
	hud_updated.emit(time_left_usec, score, combo, _last_airtime)
	if time_left_usec <= 0:
		_finish_session()


func initialize(player_bike: DirtBikeController, ghost_controller: GhostController) -> void:
	bike = player_bike
	ghost = ghost_controller
	if not bike.trick_resolved.is_connected(_on_trick_resolved):
		bike.trick_resolved.connect(_on_trick_resolved)
	enter_waiting()


func start_session() -> void:
	if bike == null or ghost == null:
		return
	# A failed durable write keeps the exact authoritative submission alive. The
	# first retry action replays that receipt instead of silently abandoning it by
	# issuing a different run ID; a second action can then begin a fresh attempt.
	if not _pending_submission.is_empty():
		# Main consumes attempt-keyed progression baselines. Reannounce only the
		# settlement context (not the physical activity start) before each retry.
		EventBus.activity_attempt_started.emit(_attempt_context.duplicate(true))
		_settle_pending_submission()
		return
	var attempt: Dictionary = Profile.begin_activity_run(&"FREESTYLE")
	_attempt_context = attempt.duplicate(true)
	if not bool(attempt.get(&"accepted", false)):
		active = false
		bike.set_controls_enabled(false)
		EventBus.activity_attempt_started.emit(_attempt_context.duplicate(true))
		EventBus.activity_completed.emit(_begin_failure_receipt(attempt))
		return
	active = true
	score = 0
	combo = 1
	_last_airtime = 0.0
	_trick_counts.clear()
	_recent_trick_ids.clear()
	_last_trick_result.clear()
	_run_clock.reset()
	bike.respawn_at(SPAWN_TRANSFORM)
	bike.set_motion_locked(false)
	bike.set_controls_enabled(true)
	ghost.cancel_run()
	EventBus.activity_started.emit(&"FREESTYLE")
	EventBus.activity_attempt_started.emit(_attempt_context.duplicate(true))
	EventBus.freestyle_score_changed.emit(0, 1, 0)
	hud_updated.emit(SESSION_USEC, 0, 1, 0.0)


func enter_waiting() -> void:
	active = false
	if _pending_submission.is_empty() and Profile.has_method(&"abandon_activity_run"):
		Profile.call(
			&"abandon_activity_run", &"FREESTYLE", str(_attempt_context.get(&"run_id", ""))
		)
	if bike != null:
		bike.set_controls_enabled(false)
	if ghost != null:
		ghost.cancel_run()


func get_activity_attempt_context() -> Dictionary:
	return _attempt_context.duplicate(true)


func has_pending_settlement() -> bool:
	return not _pending_submission.is_empty()


func get_elapsed_usec() -> int:
	return _run_clock.elapsed_usec


func get_scoring_snapshot() -> Dictionary:
	return {
		&"score": score,
		&"combo": combo,
		&"last_airtime": _last_airtime,
		&"trick_counts": _trick_counts.duplicate(true),
		&"recent_trick_ids": _recent_trick_ids.duplicate(),
		&"last_trick": _last_trick_result.duplicate(true),
	}


func _on_trick_resolved(observation: Dictionary) -> void:
	var airtime := float(observation.get(&"airtime", 0.0))
	if not active or airtime < 0.28 or not bool(observation.get(&"takeoff_valid", false)):
		return
	_last_airtime = airtime
	var provisional := TRICK_RULES.classify(observation)
	var trick_id := StringName(provisional.get(&"trick_id", &"STRAIGHT_AIR"))
	var result: Dictionary = TRICK_RULES.evaluate(observation, {
		&"combo": combo,
		&"repeat_count": int(_trick_counts.get(trick_id, 0)),
		&"recent_trick_ids": _recent_trick_ids.duplicate(),
	})
	combo = int(result.get(&"combo", 1))
	var awarded_points := int(result.get(&"awarded_points", 0))
	score += awarded_points
	result[&"score"] = score
	_trick_counts[trick_id] = int(_trick_counts.get(trick_id, 0)) + 1
	_recent_trick_ids.push_front(trick_id)
	if _recent_trick_ids.size() > RECENT_TRICK_LIMIT:
		_recent_trick_ids.resize(RECENT_TRICK_LIMIT)
	_last_trick_result = result.duplicate(true)
	EventBus.freestyle_score_changed.emit(score, combo, awarded_points)
	EventBus.freestyle_trick_scored.emit(result.duplicate(true))


func _finish_session() -> void:
	if not active:
		return
	active = false
	bike.set_controls_enabled(false)
	_pending_submission = {
		&"schema_version": 1,
		&"activity_id": &"FREESTYLE",
		&"run_id": str(_attempt_context.get(&"run_id", "")),
		&"result_value": score,
	}
	_settle_pending_submission()
	hud_updated.emit(0, score, combo, _last_airtime)


func _settle_pending_submission() -> Dictionary:
	if _pending_submission.is_empty():
		return {}
	var submission := _pending_submission.duplicate(true)
	var receipt: Dictionary = Profile.record_activity_result(submission)
	receipt = _normalize_receipt(receipt, submission)
	var terminal := (
		bool(receipt.get(&"accepted", false))
		or bool(receipt.get(&"duplicate", false))
		or not bool(receipt.get(&"retryable", false))
	)
	if terminal:
		_pending_submission.clear()
	EventBus.activity_completed.emit(receipt.duplicate(true))
	return receipt


func _normalize_receipt(receipt: Dictionary, submission: Dictionary) -> Dictionary:
	var normalized := receipt.duplicate(true)
	normalized[&"schema_version"] = int(normalized.get(&"schema_version", submission.get(&"schema_version", 1)))
	normalized[&"activity_id"] = StringName(normalized.get(
		&"activity_id", submission.get(&"activity_id", &"FREESTYLE")
	))
	normalized[&"run_id"] = str(normalized.get(&"run_id", submission.get(&"run_id", "")))
	normalized[&"result_value"] = int(normalized.get(&"result_value", submission.get(&"result_value", 0)))
	normalized[&"accepted"] = bool(normalized.get(&"accepted", false))
	normalized[&"duplicate"] = bool(normalized.get(&"duplicate", false))
	normalized[&"durable"] = bool(normalized.get(&"durable", false))
	normalized[&"retryable"] = bool(normalized.get(&"retryable", false))
	normalized[&"reason"] = StringName(normalized.get(&"reason", &"UNKNOWN"))
	var rewards_value: Variant = normalized.get(&"rewards_granted", {})
	normalized[&"rewards_granted"] = (
		(rewards_value as Dictionary).duplicate(true)
		if rewards_value is Dictionary
		else {&"cash": 0, &"reputation": 0}
	)
	return normalized


func _begin_failure_receipt(attempt: Dictionary) -> Dictionary:
	return {
		&"accepted": false,
		&"duplicate": false,
		&"durable": false,
		&"retryable": bool(attempt.get(&"retryable", false)),
		&"reason": StringName(attempt.get(&"reason", &"RUN_START_FAILED")),
		&"schema_version": int(attempt.get(&"schema_version", 1)),
		&"activity_id": &"FREESTYLE",
		&"run_id": str(attempt.get(&"run_id", "")),
		&"result_value": 0,
		&"rewards_granted": {&"cash": 0, &"reputation": 0},
	}
