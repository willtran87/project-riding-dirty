extends Node
## Deterministic production-path contract for Local Duel configuration, event
## identity, persistence, rider handoff, results presentation, and touch labels.

const STATE_PATH := "user://local_duel_flow_probe/local_duel.cfg"
const BOARD_PATH := "user://local_duel_flow_probe/leaderboard.json"
const GARAGE_UI_SCRIPT := preload("res://features/garage/garage_ui.gd")
const HUD_SCENE := preload("res://features/hud/race_hud.tscn")
const TOUCH_SCRIPT := preload("res://features/input/touch_riding_controls.gd")

var _failures: Array[String] = []
var _duel_requests: Array[bool] = []
var _rides: Array[StringName] = []
var _hotseat_payload: Dictionary = {}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_cleanup()
	Profile.persistence_enabled = false
	Profile.reset_profile_for_testing()
	Profile.persistence_enabled = false
	Profile.first_run_onboarding_complete = true
	Profile.racer_reputation = 1_000

	var service := RaceServices.new()
	service.hotseat_state_path = STATE_PATH
	service.local_leaderboard = LocalLeaderboardProvider.new(BOARD_PATH)
	add_child(service)
	service.leaderboard_updated.connect(_on_leaderboard_updated)
	var configured := service.configure_hotseat([
		{&"profile_id": "rider_1", &"display_name": "RIDER 1"},
		{&"profile_id": "rider_2", &"display_name": "RIDER 2"},
	], 2, false)
	_check(bool(configured.get("ok", false)), "production service configures a two-rider duel")
	var initial := service.get_hotseat_presentation_snapshot()
	_check(
		bool(initial.get(&"active", false))
		and StringName(initial.get(&"event_id", &"")) == &"DAILY_CHALLENGE"
		and int(initial.get(&"participant_count", 0)) == 2
		and int(initial.get(&"attempts_per_participant", 0)) == 2
		and str((initial.get(&"current_participant", {}) as Dictionary).get("display_name", "")) == "RIDER 1",
		"configured duel exposes its exact event, rules, and first rider"
	)
	_check(FileAccess.file_exists(STATE_PATH), "duel state is atomically persisted")

	var restored_service := RaceServices.new()
	restored_service.hotseat_state_path = STATE_PATH
	restored_service.call(&"_load_hotseat_state")
	var restored := restored_service.get_hotseat_presentation_snapshot()
	_check(
		bool(restored.get(&"active", false))
		and str(restored.get(&"challenge_id", "")) == str(initial.get(&"challenge_id", "")),
		"active duel recovers with the same rotating challenge identity"
	)

	var garage := GARAGE_UI_SCRIPT.new() as GarageUi
	add_child(garage)
	await get_tree().process_frame
	garage.bind_competition_source(service)
	garage.local_duel_requested.connect(_on_duel_requested)
	garage.ride_requested.connect(_on_ride_requested)
	garage.show_garage()
	_check(garage.focus_event_briefing(&"DAILY_CHALLENGE"), "Garage focuses the daily duel card")
	var garage_duel := garage.get_local_duel_presentation_snapshot()
	_check(
		str(garage_duel.get(&"action_text", "")).contains("PASS TO RIDER 1")
		and str(garage_duel.get(&"action_text", "")).contains("ATTEMPT 1 / 2"),
		"Garage renders the current handoff and attempt"
	)
	_check(
		garage.request_local_duel()
		and _duel_requests.is_empty()
		and _rides == [&"DAILY_CHALLENGE"],
		"an active Garage duel action launches the locked challenge"
	)
	garage.show_garage()

	var challenge := service.hotseat.challenge.duplicate(true)
	var matching_result := _eligible_result(challenge, "local-duel-run-1")
	var mismatched_result := matching_result.duplicate(true)
	mismatched_result[&"run_id"] = "local-duel-wrong-challenge"
	mismatched_result[&"challenge_id"] = &"DAILY-1999-001"
	service.call(&"_on_results_ready", mismatched_result)
	_check(
		int(service.get_hotseat_presentation_snapshot().get(&"turn_index", -1)) == 0,
		"another challenge cannot consume a duel attempt"
	)
	service.call(&"_on_results_ready", matching_result)
	var handoff := service.get_hotseat_presentation_snapshot()
	_check(
		int(handoff.get(&"turn_index", -1)) == 1
		and str((handoff.get(&"current_participant", {}) as Dictionary).get("display_name", "")) == "RIDER 2",
		"matching official result advances exactly once to rider two"
	)
	_check(
		not _hotseat_payload.is_empty()
		and StringName(_hotseat_payload.get("kind", &"")) == &"HOTSEAT",
		"race lifecycle emits the Local Duel presentation payload"
	)

	var hud := HUD_SCENE.instantiate() as RaceHud
	add_child(hud)
	await get_tree().process_frame
	hud.show_results(matching_result)
	hud.update_leaderboard_result(_hotseat_payload)
	var results := hud.get_competition_presentation_snapshot()
	_check(
		str(results.get(&"text", "")).contains("LOCAL DUEL")
		and str(results.get(&"text", "")).contains("RIDER 1")
		and str(results.get(&"footer", "")).contains("PASS CONTROLLER TO RIDER 2"),
		"results render standings and the next-rider handoff"
	)

	var touch := TOUCH_SCRIPT.new() as TouchRidingControls
	add_child(touch)
	await get_tree().process_frame
	touch.set_garage_continue_label("LOCAL\nDUEL")
	var controls := touch.get_touch_layout_snapshot().get(&"controls", {}) as Dictionary
	_check(
		str((controls.get(&"continue", {}) as Dictionary).get(&"label", "")) == "LOCAL\nDUEL",
		"touch Garage exposes a dedicated Local Duel action"
	)
	touch.set_workshop_open(true)
	touch.set_workshop_open(false)
	controls = touch.get_touch_layout_snapshot().get(&"controls", {}) as Dictionary
	_check(
		str((controls.get(&"continue", {}) as Dictionary).get(&"label", "")) == "LOCAL\nDUEL",
		"closing Workshop restores the contextual Local Duel label"
	)

	garage.queue_free()
	hud.queue_free()
	touch.queue_free()
	service.queue_free()
	await get_tree().process_frame
	_cleanup()
	if _failures.is_empty():
		print("LOCAL DUEL FLOW PROBE: PASS  //  configure+persist+identity+handoff+hud+touch")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("LOCAL DUEL FLOW PROBE: " + failure)
	get_tree().quit(1)


func _eligible_result(challenge: Dictionary, run_id: String) -> Dictionary:
	return {
		&"run_id": run_id,
		&"signature": str(challenge.get("run_signature", "")),
		&"event_id": &"DAILY_CHALLENGE",
		&"challenge_id": StringName(challenge.get("challenge_id", &"")),
		&"competition_id": StringName(challenge.get("competition_id", &"")),
		&"valid": true,
		&"player_position": 1,
		&"player_time_usec": 91_250_000,
		&"player_penalty_usec": 0,
		&"fastest_lap_usec": 91_250_000,
		&"classification": [{
			&"rider_id": &"PLAYER",
			&"display_name": "YOU",
			&"is_player": true,
			&"position": 1,
			&"status": &"FINISHED",
			&"finish_usec": 91_250_000,
			&"effective_time_usec": 91_250_000,
		}],
	}


func _on_duel_requested(weekly: bool) -> void:
	_duel_requests.append(weekly)


func _on_ride_requested(_setup: StringName, activity: StringName) -> void:
	_rides.append(activity)


func _on_leaderboard_updated(payload: Dictionary) -> void:
	if StringName(payload.get("kind", &"")) == &"HOTSEAT":
		_hotseat_payload = payload.duplicate(true)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _cleanup() -> void:
	for path: String in [
		STATE_PATH, STATE_PATH + ".tmp", STATE_PATH + ".bak",
		BOARD_PATH, BOARD_PATH + ".tmp", BOARD_PATH + ".bak",
	]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
