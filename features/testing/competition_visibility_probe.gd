extends Node
## Deterministic presentation contract for local competition, rivals, tour stakes,
## ghosts, and replay discoverability. No network backend is implied or required.

const GARAGE_UI_SCRIPT := preload("res://features/garage/garage_ui.gd")
const HUD_SCENE := preload("res://features/hud/race_hud.tscn")

class FakeCompetitionSource:
	extends RefCounted
	var profile_id: String = "local_player"
	var last_signature: String = ""
	var board_enabled := true
	var replay_is_available := true
	var last_result: Dictionary = {&"event_id": &"CIRCUIT"}
	var daily_challenge: Dictionary = {}

	func get_local_board(run_signature: String, _limit: int = 8) -> Dictionary:
		last_signature = run_signature
		if not board_enabled:
			return {"ok": true, "total": 0, "entries": []}
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
			&"last_result": last_result.duplicate(true),
			&"replay_available": replay_is_available,
		}

	func get_daily_challenge() -> Dictionary:
		return daily_challenge.duplicate(true)


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
	source.last_result[&"signature"] = ""
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
	_check(garage_text.contains("REPLAY READY"), "Garage briefing does not expose the matching replay")
	_check(int(milestone_snapshot.get(&"total", 0)) == 8, "Garage does not project the complete milestone ladder")

	var schedule := ChallengeSchedule.new()
	var challenge_a := schedule.daily(1_900_000_000, 0)
	var challenge_b := schedule.daily(1_900_000_000, 5)
	var challenge_identity: Dictionary = Profile.begin_race_run(
		&"DAILY_CHALLENGE",
		str(challenge_a.get("run_signature", "")),
		{
			&"challenge_id": StringName(challenge_a.get("challenge_id", &"")),
			&"competition_id": StringName(challenge_a.get("competition_id", &"")),
		}
	)
	var challenge_result := {
		&"run_id": str(challenge_identity.get(&"run_id", "")),
		&"signature": str(challenge_identity.get(&"signature", "")),
		&"event_id": &"DAILY_CHALLENGE",
		&"challenge_id": StringName(challenge_a.get("challenge_id", &"")),
		&"competition_id": StringName(challenge_a.get("competition_id", &"")),
		&"valid": true,
		&"player_position": 1,
		&"player_time_usec": 90_000_000,
		&"player_penalty_usec": 0,
		&"fastest_lap_usec": 90_000_000,
		&"lap_times_usec": [90_000_000],
		&"medal": &"GOLD",
		&"classification": [{
			&"rider_id": &"PLAYER", &"display_name": "YOU", &"is_player": true,
			&"position": 1, &"status": &"FINISHED",
		}],
	}
	_check(bool(Profile.record_race_result(challenge_result).get(&"accepted", false)), "challenge A could not seed rotation progression")
	source.daily_challenge = challenge_b
	source.board_enabled = false
	source.last_result = {
		&"event_id": &"DAILY_CHALLENGE",
		&"signature": str(challenge_a.get("run_signature", "")),
		&"challenge_id": StringName(challenge_a.get("challenge_id", &"")),
		&"competition_id": StringName(challenge_a.get("competition_id", &"")),
	}
	garage.update_competition_context(
		&"DAILY_CHALLENGE",
		90_000_000,
		StringName(challenge_a.get("competition_id", &""))
	)
	_check(garage.focus_event_briefing(&"DAILY_CHALLENGE"), "Garage could not focus the daily challenge")
	var challenge_briefing := garage.get_event_competition_snapshot(&"DAILY_CHALLENGE")
	var challenge_presentation := garage.get_event_briefing_presentation_snapshot()
	_check(
		StringName(challenge_briefing.get(&"challenge_id", &"")) == StringName(challenge_b.get("challenge_id", &""))
		and StringName(challenge_briefing.get(&"competition_id", &"")) == StringName(challenge_b.get("competition_id", &"")),
		"Garage did not project the selected challenge identities"
	)
	_check(
		str(challenge_presentation.get(&"event_meta", "")).contains("MEDAL  GOLD")
		and str(challenge_presentation.get(&"event_meta", "")).contains("NEXT POST PB"),
		"same-rotation tier change hid bucket completion or advertised a nonexistent exact PB"
	)
	_check(
		int(challenge_briefing.get(&"personal_best_usec", -1)) < 0
		and not bool(challenge_briefing.get(&"ghost_available", true))
		and not bool(challenge_briefing.get(&"replay_available", true)),
		"challenge B inherited challenge A's exact PB, ghost, or replay"
	)

	var circuit_classification := _circuit_classification()
	_check(Profile.record_championship_round(&"QUARRY_SPRINT", circuit_classification), "test championship could not accept the quarry round")
	var hud := HUD_SCENE.instantiate() as RaceHud
	add_child(hud)
	await get_tree().process_frame
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
	hud.update_replay_available({&"duration_usec": 184_000_000, &"samples": 920})
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
	var replay_binding := InputRouter.get_action_label(InputRouter.TOGGLE_REPLAY, InputRouter.input_mode, 2)
	var garage_binding := InputRouter.get_action_label(InputRouter.OPEN_GARAGE, InputRouter.input_mode, 2)
	_check(
		footer.contains(replay_binding) and footer.contains("WATCH REPLAY")
		and footer.contains(garage_binding) and footer.contains("GARAGE"),
		"post-race replay action is not discoverable on the active device"
	)
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
