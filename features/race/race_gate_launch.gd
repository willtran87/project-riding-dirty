extends RefCounted
class_name RaceGateLaunchEvaluator
## Deterministic start-gate evaluator shared by the live race and headless probes.
## It observes semantic throttle/brake strengths while the bike is physically
## frozen, then returns a deliberately small, short-lived drive modifier.

const MIN_DRIVE_MULTIPLIER := 0.94
const MAX_DRIVE_MULTIPLIER := 1.08
const BRAKE_STAGED_THRESHOLD := 0.42
const BRAKE_RELEASED_THRESHOLD := 0.20
const THROTTLE_READY_THRESHOLD := 0.45

var _attempt_id: int = 0
var _active: bool = false
var _finalized: bool = false
var _sample_seconds: float = 0.0
var _weighted_seconds: float = 0.0
var _weighted_throttle: float = 0.0
var _last_seconds_to_green: float = 0.0
var _last_throttle: float = 0.0
var _last_brake: float = 0.0
var _previous_brake: float = 0.0
var _throttle_started_seconds_to_green: float = -1.0
var _brake_release_seconds_to_green: float = -1.0
var _brake_was_staged: bool = false
var _quality: float = 0.5
var _drive_multiplier: float = 1.0
var _outcome: StringName = &"WAITING"


func reset() -> void:
	_attempt_id += 1
	_active = false
	_finalized = false
	_sample_seconds = 0.0
	_weighted_seconds = 0.0
	_weighted_throttle = 0.0
	_last_seconds_to_green = 0.0
	_last_throttle = 0.0
	_last_brake = 0.0
	_previous_brake = 0.0
	_throttle_started_seconds_to_green = -1.0
	_brake_release_seconds_to_green = -1.0
	_brake_was_staged = false
	_quality = 0.5
	_drive_multiplier = 1.0
	_outcome = &"WAITING"


func sample(delta: float, seconds_to_green: float, throttle: float, brake: float) -> Dictionary:
	if _finalized:
		return get_snapshot()
	_active = true
	var step := clampf(delta, 0.0, 0.1)
	var remaining := maxf(seconds_to_green, 0.0)
	var sampled_throttle := clampf(throttle, 0.0, 1.0)
	var sampled_brake := clampf(brake, 0.0, 1.0)
	# Weight the final half-second more heavily without making one frame at the
	# drop dominate a consistently prepared launch.
	var recency_weight := lerpf(0.7, 1.45, 1.0 - clampf(remaining / 2.0, 0.0, 1.0))
	_sample_seconds += step
	_weighted_seconds += step * recency_weight
	_weighted_throttle += sampled_throttle * step * recency_weight
	if _throttle_started_seconds_to_green < 0.0 and sampled_throttle >= THROTTLE_READY_THRESHOLD:
		_throttle_started_seconds_to_green = remaining
	if sampled_brake >= BRAKE_STAGED_THRESHOLD:
		_brake_was_staged = true
	if _previous_brake >= BRAKE_STAGED_THRESHOLD and sampled_brake <= BRAKE_RELEASED_THRESHOLD:
		_brake_release_seconds_to_green = remaining
	_previous_brake = sampled_brake
	_last_seconds_to_green = remaining
	_last_throttle = sampled_throttle
	_last_brake = sampled_brake
	_quality = _calculate_quality()
	_drive_multiplier = lerpf(MIN_DRIVE_MULTIPLIER, MAX_DRIVE_MULTIPLIER, _quality)
	_outcome = _outcome_for_multiplier(_drive_multiplier)
	return get_snapshot()


func finalize() -> Dictionary:
	if _finalized:
		return get_snapshot()
	_active = false
	_finalized = true
	if _sample_seconds <= 0.0:
		# Extremely short test sessions and non-race callers get a neutral launch.
		_quality = (1.0 - MIN_DRIVE_MULTIPLIER) / (MAX_DRIVE_MULTIPLIER - MIN_DRIVE_MULTIPLIER)
	else:
		_quality = _calculate_quality()
	_drive_multiplier = clampf(
		lerpf(MIN_DRIVE_MULTIPLIER, MAX_DRIVE_MULTIPLIER, _quality),
		MIN_DRIVE_MULTIPLIER,
		MAX_DRIVE_MULTIPLIER
	)
	_outcome = _outcome_for_multiplier(_drive_multiplier)
	return get_snapshot()


func get_snapshot() -> Dictionary:
	return {
		&"attempt_id": _attempt_id,
		&"active": _active,
		&"finalized": _finalized,
		&"seconds_to_green": _last_seconds_to_green,
		&"throttle": _last_throttle,
		&"brake": _last_brake,
		&"brake_staged": _brake_was_staged,
		&"brake_release_seconds_to_green": _brake_release_seconds_to_green,
		&"throttle_started_seconds_to_green": _throttle_started_seconds_to_green,
		&"sample_seconds": _sample_seconds,
		&"quality": _quality,
		&"drive_multiplier": _drive_multiplier,
		&"outcome": _outcome,
		&"prompt": _live_prompt(),
		&"minimum_multiplier": MIN_DRIVE_MULTIPLIER,
		&"maximum_multiplier": MAX_DRIVE_MULTIPLIER,
	}


func _calculate_quality() -> float:
	if _weighted_seconds <= 0.0001:
		return 0.0
	var average_throttle := _weighted_throttle / _weighted_seconds
	var average_quality := smoothstep(0.30, 0.92, average_throttle)
	var final_quality := smoothstep(0.35, 0.90, _last_throttle)
	var throttle_quality := average_quality * 0.62 + final_quality * 0.38
	var timing_quality := 0.0
	if _throttle_started_seconds_to_green >= 0.0:
		timing_quality = smoothstep(0.10, 0.62, _throttle_started_seconds_to_green)
	var brake_quality := 0.55
	if _brake_was_staged:
		if _last_brake > BRAKE_RELEASED_THRESHOLD:
			brake_quality = 0.0
		elif _brake_release_seconds_to_green >= 0.0:
			# A release roughly one tenth before the deterministic drop is crisp but
			# the wide tolerance remains achievable on keyboard and at 60 Hz.
			brake_quality = clampf(1.0 - absf(_brake_release_seconds_to_green - 0.12) / 0.62, 0.0, 1.0)
		else:
			brake_quality = 0.65
	var result := throttle_quality * 0.55 + timing_quality * 0.20 + brake_quality * 0.25
	if _last_throttle < 0.20:
		result = minf(result, 0.18)
	if _last_brake > BRAKE_RELEASED_THRESHOLD:
		# Holding both controls through green is a bog, never a launch exploit.
		result = minf(result, 0.20)
	return clampf(result, 0.0, 1.0)


func _live_prompt() -> String:
	if not _active:
		return ""
	if _last_seconds_to_green <= 0.32 and _last_brake > BRAKE_RELEASED_THRESHOLD:
		return "DROP BRAKE  //  KEEP THROTTLE PINNED"
	if _last_throttle < THROTTLE_READY_THRESHOLD:
		return "STAGE  //  HOLD THROTTLE"
	if not _brake_was_staged and _last_seconds_to_green > 0.32:
		return "THROTTLE SET  //  ADD BRAKE FOR PERFECT GATE"
	if _last_brake >= BRAKE_STAGED_THRESHOLD:
		return "GATE READY  //  HOLD"
	return "READY  //  KEEP THROTTLE SET"


func _outcome_for_multiplier(multiplier: float) -> StringName:
	if multiplier >= 1.07:
		return &"PERFECT_GATE"
	if multiplier >= 1.035:
		return &"STRONG_GATE"
	if multiplier >= 0.995:
		return &"CLEAN_GATE"
	return &"BOGGED_GATE"
