extends RefCounted
class_name HotSeatChallengeState
## Serializable pass-the-controller competition with deterministic turn order.

const STATE_VERSION: int = 1
const MAX_PARTICIPANTS: int = 8
const MAX_ATTEMPTS_PER_PLAYER: int = 9

var challenge: Dictionary = {}
var participants: Array[Dictionary] = []
var attempts_per_participant: int = 1
var turn_index: int = 0
var attempts: Dictionary = {}
var completed: bool = false


func configure(challenge_data: Dictionary, participant_data: Array, attempt_count: int = 1) -> Dictionary:
	if str(challenge_data.get("challenge_id", "")).is_empty():
		return {"ok": false, "error": "missing_challenge_id"}
	if participant_data.size() < 2 or participant_data.size() > MAX_PARTICIPANTS:
		return {"ok": false, "error": "participant_count_out_of_range"}
	var normalized_participants: Array[Dictionary] = []
	var identifiers: Dictionary = {}
	for raw_participant: Variant in participant_data:
		if not raw_participant is Dictionary:
			return {"ok": false, "error": "invalid_participant"}
		var raw := raw_participant as Dictionary
		var participant_id := str(raw.get("profile_id", raw.get("id", ""))).strip_edges().substr(0, 64)
		var display_name := str(raw.get("display_name", raw.get("name", ""))).strip_edges().substr(0, 24)
		if participant_id.is_empty() or display_name.is_empty() or identifiers.has(participant_id):
			return {"ok": false, "error": "invalid_or_duplicate_participant"}
		identifiers[participant_id] = true
		normalized_participants.append({"profile_id": participant_id, "display_name": display_name})
	challenge = challenge_data.duplicate(true)
	participants = normalized_participants
	attempts_per_participant = clampi(attempt_count, 1, MAX_ATTEMPTS_PER_PLAYER)
	turn_index = 0
	attempts.clear()
	for participant: Dictionary in participants:
		attempts[str(participant.get("profile_id", ""))] = []
	completed = false
	return {"ok": true, "error": ""}


func current_participant() -> Dictionary:
	if completed or participants.is_empty():
		return {}
	return participants[turn_index % participants.size()].duplicate(true)


func current_attempt_number() -> int:
	if completed or participants.is_empty():
		return 0
	return floori(float(turn_index) / float(participants.size())) + 1


func submit_attempt(entry: Dictionary) -> Dictionary:
	if completed:
		return {"ok": false, "error": "challenge_complete"}
	var participant := current_participant()
	if str(entry.get("profile_id", "")) != str(participant.get("profile_id", "")):
		return {"ok": false, "error": "wrong_participant"}
	if str(entry.get("challenge_id", "")) != str(challenge.get("challenge_id", "")):
		return {"ok": false, "error": "challenge_id_mismatch"}
	var validation := LeaderboardProvider.validate_entry(entry)
	if not bool(validation.get("ok", false)):
		return validation
	var profile_id := str(participant.get("profile_id", ""))
	var player_attempts: Array = (attempts.get(profile_id, []) as Array).duplicate(true)
	player_attempts.append(LeaderboardProvider.normalized_entry(entry))
	attempts[profile_id] = player_attempts
	_advance_turn()
	return {
		"ok": true,
		"complete": completed,
		"next_participant": current_participant(),
		"standings": standings(),
	}


func skip_attempt(reason: String = "SKIPPED") -> Dictionary:
	if completed:
		return {"ok": false, "error": "challenge_complete"}
	var participant := current_participant()
	var profile_id := str(participant.get("profile_id", ""))
	var player_attempts: Array = (attempts.get(profile_id, []) as Array).duplicate(true)
	player_attempts.append({
		"version": LeaderboardProvider.ENTRY_VERSION,
		"profile_id": profile_id,
		"display_name": participant.get("display_name", ""),
		"status": reason.strip_edges().to_upper().substr(0, 32),
		"time_usec": -1,
	})
	attempts[profile_id] = player_attempts
	_advance_turn()
	return {"ok": true, "complete": completed, "next_participant": current_participant()}


func best_attempt(profile_id: String) -> Dictionary:
	var best: Dictionary = {}
	var player_attempts: Array = attempts.get(profile_id, []) as Array
	for raw_attempt: Variant in player_attempts:
		if not raw_attempt is Dictionary:
			continue
		var attempt := raw_attempt as Dictionary
		if int(attempt.get("time_usec", -1)) <= 0:
			continue
		if best.is_empty() or LeaderboardProvider.effective_time_usec(attempt) < LeaderboardProvider.effective_time_usec(best):
			best = attempt
	return best.duplicate(true)


func standings() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for participant: Dictionary in participants:
		var profile_id := str(participant.get("profile_id", ""))
		var best := best_attempt(profile_id)
		result.append({
			"profile_id": profile_id,
			"display_name": participant.get("display_name", ""),
			"time_usec": int(best.get("time_usec", -1)),
			"penalty_usec": int(best.get("penalty_usec", 0)),
			"effective_time_usec": LeaderboardProvider.effective_time_usec(best) if not best.is_empty() else 9_223_372_036_854_775_000,
			"attempts_completed": (attempts.get(profile_id, []) as Array).size(),
		})
	result.sort_custom(_standing_precedes)
	for index in result.size():
		result[index]["position"] = index + 1
	return result


func is_complete() -> bool:
	return completed


func to_dictionary() -> Dictionary:
	return {
		"version": STATE_VERSION,
		"challenge": challenge.duplicate(true),
		"participants": participants.duplicate(true),
		"attempts_per_participant": attempts_per_participant,
		"turn_index": turn_index,
		"attempts": attempts.duplicate(true),
		"completed": completed,
	}


static func from_dictionary(data: Dictionary) -> HotSeatChallengeState:
	var state := HotSeatChallengeState.new()
	if int(data.get("version", 0)) != STATE_VERSION:
		return state
	var challenge_data: Variant = data.get("challenge", {})
	var participant_data: Variant = data.get("participants", [])
	if not challenge_data is Dictionary or not participant_data is Array:
		return state
	var configuration := state.configure(
		challenge_data,
		participant_data,
		int(data.get("attempts_per_participant", 1))
	)
	if not bool(configuration.get("ok", false)):
		return HotSeatChallengeState.new()
	var loaded_attempts: Variant = data.get("attempts", {})
	if loaded_attempts is Dictionary:
		for participant: Dictionary in state.participants:
			var profile_id := str(participant.get("profile_id", ""))
			var raw_player_attempts: Variant = (loaded_attempts as Dictionary).get(profile_id, [])
			if raw_player_attempts is Array:
				state.attempts[profile_id] = (raw_player_attempts as Array).slice(0, MAX_ATTEMPTS_PER_PLAYER, 1, true)
	var maximum_turns := state.participants.size() * state.attempts_per_participant
	state.turn_index = clampi(int(data.get("turn_index", 0)), 0, maximum_turns)
	state.completed = bool(data.get("completed", false)) or state.turn_index >= maximum_turns
	return state


func _advance_turn() -> void:
	turn_index += 1
	completed = turn_index >= participants.size() * attempts_per_participant


func _standing_precedes(a: Dictionary, b: Dictionary) -> bool:
	var a_time := int(a.get("effective_time_usec", 9_223_372_036_854_775_000))
	var b_time := int(b.get("effective_time_usec", 9_223_372_036_854_775_000))
	if a_time != b_time:
		return a_time < b_time
	return str(a.get("display_name", "")) < str(b.get("display_name", ""))
