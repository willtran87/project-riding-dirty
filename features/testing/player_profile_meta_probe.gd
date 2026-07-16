extends Node
## Godot --headless --path . res://features/testing/player_profile_meta_probe.tscn -- --smoke-test

const PLAYER_PROFILE_SCRIPT := preload("res://common/player_profile.gd")
const WEEKEND_DIRECTOR_SCRIPT := preload("res://features/career/race_weekend_director.gd")


func _ready() -> void:
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
		bool(accepted.get(&"accepted", false))
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
	print("PLAYER PROFILE META PROBE: schema=%d wins=%d academy=%d championship_rounds=%d passed=%s" % [
		restored.PROFILE_SCHEMA_VERSION,
		int(restored.race_statistics.get(&"wins", 0)),
		int(restored.academy_progress.get(&"CONTROL_BASICS", 0)),
		championship.completed_round_count(),
		passed,
	])
	profile.free()
	restored.free()
	get_tree().quit(0 if passed else 1)


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
