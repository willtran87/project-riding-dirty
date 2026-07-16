extends Node
## Verifies that competitive progression and rewards finalize atomically.
## Godot --headless --path . res://features/testing/race_reward_integrity_probe.tscn -- --smoke-test

const PLAYER_PROFILE_SCRIPT := preload("res://common/player_profile.gd")
const WEEKEND_DIRECTOR_SCRIPT := preload("res://features/career/race_weekend_director.gd")


func _ready() -> void:
	var profile: Variant = PLAYER_PROFILE_SCRIPT.new()
	profile.persistence_enabled = false
	profile._apply_profile_dictionary({
		"cash": 0,
		"racer_reputation": 0,
		"current_setup": "BALANCED",
		"unlocked_setups": ["BALANCED"],
		"course_layout_version": profile.COURSE_LAYOUT_VERSION,
	})
	profile._ensure_full_race_defaults()
	_prepare_managed_main(profile)
	var failures := PackedStringArray()

	var valid_result := _result("valid-finish", &"MESA_MX", true, &"FINISHED")
	valid_result[&"round_id"] = &"MESA_OPENER"
	valid_result[&"weekend_id"] = &"RED_MESA_OPEN"
	valid_result[&"weekend_phase"] = &"MAIN"
	valid_result[&"weekend_managed"] = true
	var valid_summary: Dictionary = profile.record_race_result(valid_result, true)
	_assert(bool(valid_summary.get(&"accepted", false)), "valid finish rejected", failures)
	_assert(profile.cash == 420, "valid cash reward was not credited exactly once", failures)
	_assert(profile.racer_reputation == 33, "valid reputation reward was not credited", failures)
	_assert(int((valid_summary.get(&"rewards_granted", {}) as Dictionary).get(&"cash", -1)) == 420, "valid summary cash delta mismatch", failures)
	_assert(profile.get_event_medal(&"MESA_MX") == &"GOLD", "valid medal was not recorded", failures)
	_assert(profile.get_championship_service().completed_round_count() == 1, "valid championship round was not recorded", failures)

	var balance_after_valid: int = profile.cash
	var reputation_after_valid: int = profile.racer_reputation
	var duplicate_summary: Dictionary = profile.record_race_result(valid_result, true)
	_assert(bool(duplicate_summary.get(&"duplicate", false)), "duplicate run ID was accepted", failures)
	_assert(profile.cash == balance_after_valid and profile.racer_reputation == reputation_after_valid, "duplicate run paid twice", failures)

	for invalid_case: String in ["COURSE_CUT", "OFF_COURSE", "CHALLENGE_SIGNATURE_MISMATCH", "RESTARTED_RUN"]:
		var invalid_result := _result("invalid-%s" % invalid_case.to_lower(), &"CIRCUIT", false, &"FINISHED")
		invalid_result[&"validity_reason"] = invalid_case
		invalid_result[&"round_id"] = &"QUARRY_SPRINT"
		var invalid_summary: Dictionary = profile.record_race_result(invalid_result, true)
		_assert(bool(invalid_summary.get(&"accepted", false)), "%s result was not recorded for audit stats" % invalid_case, failures)
		_assert(int((invalid_summary.get(&"rewards_granted", {}) as Dictionary).get(&"cash", -1)) == 0, "%s granted cash" % invalid_case, failures)
		_assert(int((invalid_summary.get(&"rewards_granted", {}) as Dictionary).get(&"reputation", -1)) == 0, "%s granted reputation" % invalid_case, failures)
	_assert(profile.cash == balance_after_valid and profile.racer_reputation == reputation_after_valid, "invalid cases changed progression currency", failures)
	_assert(profile.get_event_medal_rank(&"CIRCUIT") == 0, "invalid cases granted a medal", failures)
	_assert(profile.get_championship_service().completed_round_count() == 1, "invalid case advanced the championship", failures)

	var dnf_result := _result("dnf-finish", &"PINE_ENDURO", true, &"DNF")
	dnf_result[&"player_time_usec"] = -1
	var dnf_summary: Dictionary = profile.record_race_result(dnf_result, true)
	_assert(bool(dnf_summary.get(&"accepted", false)), "DNF was not recorded", failures)
	_assert(int((dnf_summary.get(&"rewards_granted", {}) as Dictionary).get(&"cash", -1)) == 0, "DNF granted cash", failures)
	_assert(profile.get_event_medal_rank(&"PINE_ENDURO") == 0, "DNF granted a medal", failures)

	profile.cash = profile.MAX_CASH - 25
	var capped_result := _result("cap-finish", &"CIRCUIT", true, &"FINISHED")
	var capped_summary: Dictionary = profile.record_race_result(capped_result, true)
	var capped_rewards := capped_summary.get(&"rewards_granted", {}) as Dictionary
	_assert(profile.cash == profile.MAX_CASH, "cash cap was not respected", failures)
	_assert(int(capped_rewards.get(&"cash", -1)) == 25, "displayable cash delta does not equal credited cap delta", failures)
	_assert(int(capped_rewards.get(&"reputation", -1)) == 33, "capped cash incorrectly capped reputation", failures)

	var passed := failures.is_empty()
	print("RACE REWARD INTEGRITY PROBE: accepted_runs=%d cash=%d reputation=%d invalid_dsqs=%d passed=%s failures=%s" % [
		profile.total_runs,
		profile.cash,
		profile.racer_reputation,
		int(profile.race_statistics.get(&"dsqs", 0)),
		passed,
		", ".join(failures),
	])
	profile.free()
	get_tree().quit(0 if passed else 1)


func _result(run_id: String, event_id: StringName, valid: bool, status: StringName) -> Dictionary:
	return {
		&"run_id": run_id,
		&"signature": "%s|PROBE" % String(event_id),
		&"event_id": event_id,
		&"valid": valid,
		&"player_position": 1,
		&"player_time_usec": 90_000_000,
		&"player_penalty_usec": 0,
		&"medal": &"GOLD",
		&"rewards": {&"cash": 420, &"reputation": 33},
		&"classification": [
			{&"rider_id": &"PLAYER", &"display_name": "YOU", &"is_player": true, &"position": 1, &"status": status},
			{&"rider_id": &"ROOK", &"display_name": "ROOK", &"position": 2, &"status": &"FINISHED"},
		],
	}


func _prepare_managed_main(profile: Variant) -> void:
	var director: Variant = WEEKEND_DIRECTOR_SCRIPT.create({
		&"weekend_id": &"RED_MESA_OPEN", &"event_id": &"MESA_MX",
		&"entrants": [
			{&"rider_id": &"PLAYER", &"display_name": "YOU", &"seed": 1},
			{&"rider_id": &"ROOK", &"display_name": "ROOK", &"seed": 2},
		],
		&"heat_transfer_count": 1, &"lcq_transfer_count": 1, &"main_field_limit": 2,
	})
	director.start_weekend()
	director.submit_session_result(_weekend_classification([&"PLAYER", &"ROOK"]))
	var player_qualifying: Array[Dictionary] = [{
		&"rider_id": &"PLAYER", &"position": 1, &"status": &"FINISHED", &"finish_usec": 90_000_000,
	}]
	director.submit_session_result(player_qualifying)
	director.submit_session_result(_weekend_classification([&"PLAYER", &"ROOK"]))
	profile.set_race_weekend_snapshot(director.to_dictionary())


func _weekend_classification(riders: Array[StringName]) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for index: int in riders.size():
		output.append({
			&"rider_id": riders[index], &"position": index + 1, &"status": &"FINISHED",
			&"finish_usec": 90_000_000 + index * 1_000_000,
		})
	return output


func _assert(condition: bool, message: String, failures: PackedStringArray) -> void:
	if not condition:
		failures.append(message)
