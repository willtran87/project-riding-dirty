extends Node
## Deterministic presentation contract for local competition, rivals, tour stakes,
## ghosts, and replay discoverability. No network backend is implied or required.

const GARAGE_UI_SCRIPT := preload("res://features/garage/garage_ui.gd")
const HUD_SCENE := preload("res://features/hud/race_hud.tscn")

class FakeCompetitionSource:
	extends RefCounted
	var profile_id: String = "local_player"
	var last_signature: String = ""

	func get_local_board(run_signature: String, _limit: int = 8) -> Dictionary:
		last_signature = run_signature
		return {
			"ok": true,
			"total": 2,
			"entries": [
				{
					"rank": 1, "run_id": "player-pb", "run_signature": run_signature,
					"profile_id": profile_id, "display_name": "LOCAL RIDER",
					"time_usec": 184_000_000, "penalty_usec": 0,
				},
				{
					"rank": 2, "run_id": "guest-pb", "run_signature": run_signature,
					"profile_id": "guest", "display_name": "GARAGE GUEST",
					"time_usec": 188_000_000, "penalty_usec": 0,
				},
			],
		}

	func get_competitive_snapshot() -> Dictionary:
		return {
			&"last_result": {&"event_id": &"CIRCUIT", &"signature": last_signature},
			&"replay_available": true,
		}


var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	Profile.persistence_enabled = false
	Profile.reset_profile_for_testing()
	Profile.persistence_enabled = false
	Profile.first_run_onboarding_complete = true
	Profile.racer_reputation = 1_000
	_seed_championship_opener()
	Profile.event_records[&"CIRCUIT"] = {
		&"starts": 1, &"finishes": 1, &"wins": 0, &"podiums": 1, &"dnfs": 0,
		&"best_finish": 2, &"best_time_usec": 185_000_000, &"best_lap_usec": 185_000_000,
		&"total_time_usec": 185_000_000, &"last_position": 2, &"last_status": &"FINISHED",
		&"last_medal": &"SILVER",
	}

	var source := FakeCompetitionSource.new()
	if Profile.has_method(&"get_profile_id"):
		source.profile_id = str(Profile.call(&"get_profile_id"))
	var garage := GARAGE_UI_SCRIPT.new() as GarageUi
	add_child(garage)
	await get_tree().process_frame
	garage.bind_competition_source(source)
	garage.update_competition_context(&"CIRCUIT", 184_000_000)
	garage.show_garage()
	_check(garage.focus_event_briefing(&"CIRCUIT"), "Garage could not focus a valid race briefing")
	var briefing := garage.get_event_competition_snapshot(&"CIRCUIT")
	_check(CompetitiveRunSignature.validate(str(briefing.get(&"run_signature", ""))), "Garage did not derive the comparable local ruleset")
	_check(int(briefing.get(&"local_board_total", 0)) == 2 and int(briefing.get(&"local_rank", 0)) == 1, "Garage omitted local board rank or field size")
	_check(int(briefing.get(&"personal_best_usec", -1)) == 184_000_000, "Garage did not project the exact-rules personal best")
	_check(bool(briefing.get(&"ghost_available", false)), "Garage omitted the loaded personal-best ghost")
	_check(bool(briefing.get(&"replay_available", false)), "Garage omitted the existing last-run replay")
	var championship: Dictionary = briefing.get(&"championship", {}) as Dictionary
	_check(bool(championship.get(&"is_active_round", false)) and int(championship.get(&"event_round_number", 0)) == 2, "Garage did not expose the active championship round")
	var rival: Dictionary = briefing.get(&"rival", {}) as Dictionary
	_check(StringName(rival.get(&"rider_id", &"")) == &"ROOK" and str(rival.get(&"display_name", "")).contains("ROOK"), "Garage did not name the championship rival")
	var garage_presentation := garage.get_event_briefing_presentation_snapshot()
	var garage_text := str(garage_presentation.get(&"text", ""))
	var workshop_snapshot := garage.get_workshop_snapshot()
	var milestone_snapshot := workshop_snapshot.get(&"achievements", {}) as Dictionary
	_check(bool(garage_presentation.get(&"visible", false)), "Garage competition briefing is not rendered for the selected race")
	_check(garage_text.contains("LOCAL P1/2") and garage_text.contains("PB GHOST"), "Garage briefing omitted local PB or ghost state")
	_check(garage_text.contains("TOUR S01 R2/6 LIVE") and garage_text.contains("ROOK MERCER"), "Garage briefing omitted tour stakes or named rival")
	_check(garage_text.contains("REPLAY [V]"), "Garage briefing does not advertise the replay action")
	_check(int(milestone_snapshot.get(&"total", 0)) == 8, "Garage does not project the complete milestone ladder")

	var circuit_classification := _circuit_classification()
	_check(Profile.record_championship_round(&"QUARRY_SPRINT", circuit_classification), "test championship could not accept the quarry round")
	var hud := HUD_SCENE.instantiate() as RaceHud
	add_child(hud)
	await get_tree().process_frame
	hud.update_replay_available({&"duration_usec": 184_000_000, &"samples": 920})
	var result := {
		&"run_id": "competition-visibility-result",
		&"signature": str(briefing.get(&"run_signature", "")),
		&"event_id": &"CIRCUIT",
		&"valid": true,
		&"medal": &"SILVER",
		&"classification": circuit_classification,
		&"player_position": 2,
		&"player_time_usec": 184_000_000,
		&"player_penalty_usec": 0,
		&"fastest_lap_usec": 181_000_000,
		&"championship_points": 22,
		&"round_id": &"QUARRY_SPRINT",
		&"next_event_name": "PINE RIDGE ENDURO",
		&"rewards": {&"cash": 600, &"reputation": 80},
	}
	hud.show_results(result)
	hud.update_leaderboard_result({
		"ok": true, "accepted": true, "personal_best": true, "rank": 1,
		"entry": {
			"run_id": "competition-visibility-result",
			"run_signature": str(briefing.get(&"run_signature", "")),
			"profile_id": source.profile_id,
			"display_name": "LOCAL RIDER",
			"time_usec": 184_000_000,
			"penalty_usec": 0,
		},
	})
	var hud_presentation := hud.get_competition_presentation_snapshot()
	var hud_text := str(hud_presentation.get(&"text", ""))
	var footer := str(hud_presentation.get(&"footer", ""))
	_check(bool(hud_presentation.get(&"visible", false)), "post-race competition block is hidden")
	_check(hud_text.contains("LOCAL BOARD") and hud_text.contains("NEW PERSONAL BEST"), "post-race local rank or PB state is missing")
	_check(hud_text.contains("DIRT TOUR") and hud_text.contains("ROOK MERCER"), "post-race championship stakes are missing")
	_check(hud_text.contains("RACE RIVAL") and hud_text.contains("REPLAY READY"), "post-race rival or replay state is missing")
	_check(footer.contains("V  WATCH REPLAY") and footer.contains("G / B  GARAGE"), "post-race replay action is not discoverable")
	hud.update_replay_state(true)
	_check(not bool(hud.get_competition_presentation_snapshot().get(&"results_visible", true)), "replay remains hidden behind the official results panel")
	hud.update_replay_state(false)
	_check(bool(hud.get_competition_presentation_snapshot().get(&"results_visible", false)), "official results do not return after replay exit")

	hud.show_results({
		&"event_id": &"ACADEMY",
		&"valid": true,
		&"player_time_usec": 75_000_000,
		&"classification": [],
		&"academy_evaluation": {
			&"lesson_id": &"CONTROL_BASICS", &"display_name": "THROTTLE AND BRAKE CONTROL",
			&"stars": 1, &"best_stars": 1, &"passed": true, &"objective_results": [],
		},
		&"academy_next_lesson_id": &"GATE_DROP",
		&"academy_next_lesson_name": "GATE DROP AND HOLESHOT",
	})
	var academy_presentation := hud.get_competition_presentation_snapshot()
	_check(not bool(academy_presentation.get(&"visible", true)) and str(academy_presentation.get(&"text", "")).is_empty(), "competition block displaced Academy grading")

	garage.queue_free()
	hud.queue_free()
	await get_tree().process_frame
	if _failures.is_empty():
		print("COMPETITION VISIBILITY PROBE: PASS  //  garage=local+ghost+tour+rival  hud=board+pb+replay  academy=preserved")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("COMPETITION VISIBILITY PROBE: " + failure)
	get_tree().quit(1)


func _seed_championship_opener() -> void:
	var championship: Variant = RacingChampionshipService.create_default()
	var opener: Array[Dictionary] = [
		{&"rider_id": &"ROOK", &"display_name": "ROOK MERCER", &"position": 1, &"status": &"FINISHED"},
		{&"rider_id": &"PLAYER", &"display_name": "YOU", &"position": 2, &"status": &"FINISHED"},
		{&"rider_id": &"NOVA", &"display_name": "NOVA REYES", &"position": 3, &"status": &"FINISHED"},
	]
	championship.record_round_result(&"MESA_OPENER", opener)
	Profile.championship_snapshot = championship.to_dictionary()


func _circuit_classification() -> Array[Dictionary]:
	return [
		{
			&"rider_id": &"ROOK", &"display_name": "ROOK MERCER", &"number": 17,
			&"position": 1, &"status": &"FINISHED", &"finish_usec": 181_000_000,
			&"effective_time_usec": 181_000_000, &"penalty_usec": 0,
		},
		{
			&"rider_id": &"PLAYER", &"display_name": "YOU", &"number": 1, &"is_player": true,
			&"position": 2, &"status": &"FINISHED", &"finish_usec": 184_000_000,
			&"effective_time_usec": 184_000_000, &"penalty_usec": 0,
		},
		{
			&"rider_id": &"NOVA", &"display_name": "NOVA REYES", &"number": 24,
			&"position": 3, &"status": &"FINISHED", &"finish_usec": 187_000_000,
			&"effective_time_usec": 187_000_000, &"penalty_usec": 0,
		},
	]


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
