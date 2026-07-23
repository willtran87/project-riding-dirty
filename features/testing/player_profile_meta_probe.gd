extends Node
## Godot --headless --path . res://features/testing/player_profile_meta_probe.tscn -- --smoke-test

const PLAYER_PROFILE_SCRIPT := preload("res://common/player_profile.gd")
const WEEKEND_DIRECTOR_SCRIPT := preload("res://features/career/race_weekend_director.gd")


func _ready() -> void:
	var championship_authority_passed := _probe_championship_round_authority()
	var profile: Variant = PLAYER_PROFILE_SCRIPT.new()
	profile.persistence_enabled = false
	profile._apply_profile_dictionary({
		"cash": 2_000,
		"racer_reputation": 120,
		"current_setup": "BALANCED",
		"unlocked_setups": ["BALANCED"],
		"best_medal_ranks": {"CIRCUIT": 4, "MESA_MX": 2},
		"course_layout_version": profile.COURSE_LAYOUT_VERSION,
	})
	profile._ensure_full_race_defaults()
	var first_run_was_active: bool = profile.is_first_run_onboarding_active()
	_prepare_managed_main(profile)

	var result := {
		&"run_id": "profile-probe-run",
		&"signature": "MESA_MX|MESA_MX|r1|MAIN",
		&"event_id": &"MESA_MX",
		&"round_id": &"MESA_OPENER",
		&"weekend_id": &"RED_MESA_OPEN",
		&"weekend_phase": &"MAIN",
		&"weekend_managed": true,
		&"player_position": 1,
		&"player_time_usec": 92_000_000,
		&"player_penalty_usec": 500_000,
		&"fastest_lap_usec": 44_000_000,
		&"fastest_rider_id": &"PLAYER",
		&"holeshot_rider_id": &"PLAYER",
		&"lap_times_usec": [48_000_000, 44_000_000],
		&"overtakes": 7,
		&"contacts": 1,
		&"reset_count": 0,
		&"medal": &"GOLD",
		&"classification": [
			{&"rider_id": &"PLAYER", &"display_name": "YOU", &"is_player": true, &"position": 1, &"status": &"FINISHED"},
			{&"rider_id": &"ROOK", &"display_name": "ROOK", &"position": 2, &"status": &"FINISHED"},
		],
	}
	result = _authorize_race_result(profile, result)
	var accepted: Dictionary = profile.record_race_result(result)
	var duplicate: Dictionary = profile.record_race_result(result)
	var academy: Dictionary = profile.record_academy_result(&"CONTROL_BASICS", {&"gates_completed": 10, &"resets": 0})
	profile.set_bike_tune({&"gearing": 0.4, &"preload": 0.7})
	profile.set_rider_cosmetics({&"helmet": "PROBE_HELMET", &"rider_number": 42})
	profile.record_leaderboard_summary("MESA_MX|MESA_MX|r1|MAIN", {
		&"accepted": true, &"personal_best": true, &"rank": 3,
		&"entry": {&"time_usec": 92_500_000},
	})

	var serialized: Dictionary = profile._profile_to_dictionary()
	var json_round_trip: Variant = JSON.parse_string(JSON.stringify(serialized))
	var restored: Variant = PLAYER_PROFILE_SCRIPT.new()
	restored.persistence_enabled = false
	if json_round_trip is Dictionary:
		restored._apply_profile_dictionary(json_round_trip)
		restored._ensure_full_race_defaults()

	var championship: Variant = restored.get_championship_service()
	var setup: Dictionary = restored.get_active_bike_setup_snapshot()
	var milestone_progress: Dictionary = restored.get_achievement_progress_snapshot()
	var next_milestone: Dictionary = milestone_progress.get(&"next", {}) as Dictionary
	var passed: bool = (
		championship_authority_passed
		and bool(accepted.get(&"accepted", false))
		and bool(duplicate.get(&"duplicate", false))
		and int(restored.race_statistics.get(&"wins", 0)) == 1
		and int(restored.race_statistics.get(&"laps_completed", 0)) == 2
		and int((restored.event_records.get(&"MESA_MX", {}) as Dictionary).get(&"best_finish", 0)) == 1
		and restored.get_event_medal_rank(&"CIRCUIT") == 4
		and restored.get_event_medal_rank(&"MESA_MX") == 4
		and championship.completed_round_count() == 1
		and int(restored.academy_progress.get(&"CONTROL_BASICS", 0)) == 3
		and bool(academy.get(&"first_completion", false))
		and str(restored.rider_cosmetics.get(&"helmet", "")) == "PROBE_HELMET"
		and int(restored.rider_cosmetics.get(&"rider_number", 0)) == 42
		and not (setup.get(&"stats", {}) as Dictionary).is_empty()
		and not restored.get_leaderboard_summary("MESA_MX|MESA_MX|r1|MAIN").is_empty()
		and str(restored.get_achievement_definition(&"FIRST_WIN").get(&"title", "")) == "Top Step"
		and restored.get_achievement_ids().has(&"FIRST_FINISH")
		and restored.get_achievement_ids().has(&"FIRST_WIN")
		and int(milestone_progress.get(&"unlocked", 0)) >= 2
		and int(milestone_progress.get(&"total", 0)) == 8
		and StringName(next_milestone.get(&"achievement_id", &"")) == &"PODIUM_REGULAR"
		and int(next_milestone.get(&"current", 0)) == 1
		and int(next_milestone.get(&"target", 0)) == 5
		and str(serialized.get("profile_id", "")).begins_with("local-")
		and first_run_was_active
		and bool(serialized.get("first_run_onboarding_complete", false))
		and not restored.is_first_run_onboarding_active()
	)
	print("PLAYER PROFILE META PROBE: schema=%d wins=%d academy=%d championship_rounds=%d authority=%s passed=%s" % [
		restored.PROFILE_SCHEMA_VERSION,
		int(restored.race_statistics.get(&"wins", 0)),
		int(restored.academy_progress.get(&"CONTROL_BASICS", 0)),
		championship.completed_round_count(),
		championship_authority_passed,
		passed,
	])
	profile.free()
	restored.free()
	get_tree().quit(0 if passed else 1)


func _probe_championship_round_authority() -> bool:
	var profile: Variant = PLAYER_PROFILE_SCRIPT.new()
	profile.persistence_enabled = false
	profile._ensure_full_race_defaults()
	var initial_championship := JSON.stringify(profile.championship_snapshot)

	# QUARRY_SPRINT belongs to CIRCUIT, but it is not the current championship
	# round. Rejecting that claim must leave both the championship and race token
	# untouched so the exact non-championship result can still settle.
	var circuit_result := _authority_race_result(&"CIRCUIT", "AUTHORITY|CIRCUIT")
	var circuit_run: Dictionary = profile.begin_race_run(
		&"CIRCUIT", str(circuit_result.get(&"signature", ""))
	)
	_bind_race_receipt(circuit_result, circuit_run)
	circuit_result[&"round_id"] = &"QUARRY_SPRINT"
	var non_next_rejection: Dictionary = profile.record_race_result(circuit_result)
	var non_next_preserved := JSON.stringify(profile.championship_snapshot) == initial_championship
	var exact_circuit_result := circuit_result.duplicate(true)
	exact_circuit_result.erase(&"round_id")
	var circuit_settlement: Dictionary = profile.record_race_result(exact_circuit_result)
	var circuit_preserved := JSON.stringify(profile.championship_snapshot) == initial_championship

	# The next round is MESA_OPENER. A MESA token cannot be redirected to the
	# CIRCUIT-owned QUARRY_SPRINT round; after rejection, the receipt's exact round
	# remains authoritative and settleable with the same token.
	_prepare_managed_main(profile)
	var mesa_result := _authority_race_result(&"MESA_MX", "AUTHORITY|MESA|MAIN")
	mesa_result[&"weekend_id"] = &"RED_MESA_OPEN"
	mesa_result[&"weekend_phase"] = &"MAIN"
	mesa_result[&"weekend_managed"] = true
	var mesa_run: Dictionary = profile.begin_race_run(
		&"MESA_MX",
		str(mesa_result.get(&"signature", "")),
		{
			&"weekend_id": &"RED_MESA_OPEN",
			&"weekend_phase": &"MAIN",
			&"weekend_managed": true,
		}
	)
	_bind_race_receipt(mesa_result, mesa_run)
	mesa_result[&"round_id"] = &"QUARRY_SPRINT"
	var wrong_event_rejection: Dictionary = profile.record_race_result(mesa_result)
	var wrong_event_preserved := JSON.stringify(profile.championship_snapshot) == initial_championship
	var exact_mesa_result := mesa_result.duplicate(true)
	exact_mesa_result[&"round_id"] = StringName(mesa_run.get(&"round_id", &""))
	var mesa_settlement: Dictionary = profile.record_race_result(exact_mesa_result)
	var championship: Variant = profile.get_championship_service()
	var passed: bool = (
		bool(circuit_run.get(&"accepted", false))
		and StringName(circuit_run.get(&"round_id", &"")) == &""
		and not bool(non_next_rejection.get(&"accepted", false))
		and StringName(non_next_rejection.get(&"reason", &"")) == &"STALE_OR_ABANDONED_RUN"
		and non_next_preserved
		and bool(circuit_settlement.get(&"accepted", false))
		and circuit_preserved
		and bool(mesa_run.get(&"accepted", false))
		and StringName(mesa_run.get(&"round_id", &"")) == &"MESA_OPENER"
		and not bool(wrong_event_rejection.get(&"accepted", false))
		and StringName(wrong_event_rejection.get(&"reason", &"")) == &"STALE_OR_ABANDONED_RUN"
		and wrong_event_preserved
		and bool(mesa_settlement.get(&"accepted", false))
		and championship.completed_round_count() == 1
		and not championship.get_round_result(&"MESA_OPENER").is_empty()
	)
	profile.free()
	return passed


func _authority_race_result(event_id: StringName, signature: String) -> Dictionary:
	return {
		&"run_id": "",
		&"signature": signature,
		&"event_id": event_id,
		&"valid": true,
		&"player_position": 1,
		&"player_time_usec": 90_000_000,
		&"player_penalty_usec": 0,
		&"lap_times_usec": [45_000_000, 45_000_000],
		&"medal": &"GOLD",
		&"classification": [
			{&"rider_id": &"PLAYER", &"display_name": "YOU", &"is_player": true, &"position": 1, &"status": &"FINISHED"},
			{&"rider_id": &"ROOK", &"display_name": "ROOK", &"position": 2, &"status": &"FINISHED"},
		],
	}


func _bind_race_receipt(result: Dictionary, receipt: Dictionary) -> void:
	result[&"run_id"] = str(receipt.get(&"run_id", ""))
	result[&"signature"] = str(receipt.get(&"signature", ""))


func _authorize_race_result(profile: Variant, result: Dictionary) -> Dictionary:
	var authorized := result.duplicate(true)
	var event_id := StringName(authorized.get(&"event_id", &""))
	var settlement_context := {
		&"weekend_id": StringName(authorized.get(&"weekend_id", &"")),
		&"weekend_phase": StringName(authorized.get(&"weekend_phase", &"")),
		&"weekend_managed": bool(authorized.get(&"weekend_managed", false)),
	}
	var run: Dictionary = profile.begin_race_run(
		event_id, str(authorized.get(&"signature", "")), settlement_context
	)
	authorized[&"run_id"] = str(run.get(&"run_id", ""))
	authorized[&"signature"] = str(run.get(&"signature", ""))
	return authorized


func _prepare_managed_main(profile: Variant) -> void:
	var director: Variant = WEEKEND_DIRECTOR_SCRIPT.create({
		&"weekend_id": &"RED_MESA_OPEN",
		&"event_id": &"MESA_MX",
		&"entrants": [
			{&"rider_id": &"PLAYER", &"display_name": "YOU", &"seed": 1},
			{&"rider_id": &"ROOK", &"display_name": "ROOK", &"seed": 2},
		],
		&"heat_transfer_count": 1,
		&"lcq_transfer_count": 1,
		&"main_field_limit": 2,
	})
	director.start_weekend()
	director.submit_session_result(_weekend_classification([&"PLAYER", &"ROOK"]))
	var player_qualifying: Array[Dictionary] = [{
		&"rider_id": &"PLAYER", &"display_name": "YOU", &"position": 1,
		&"status": &"FINISHED", &"finish_usec": 90_000_000,
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
