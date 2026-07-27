extends Node
## Deterministic production-path contract for the player-authored Custom Tour:
## builder limits, exact round sequencing, persistence, standings, HUD, and touch.

const STATE_PATH := "user://custom_tour_flow_probe/custom_tour.cfg"
const BOARD_PATH := "user://custom_tour_flow_probe/leaderboard.json"
const GARAGE_UI_SCRIPT := preload("res://features/garage/garage_ui.gd")
const HUD_SCENE := preload("res://features/hud/race_hud.tscn")
const TOUCH_SCRIPT := preload("res://features/input/touch_riding_controls.gd")

var _failures: Array[String] = []
var _rides: Array[StringName] = []
var _tour_payload: Dictionary = {}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_cleanup()
	Profile.persistence_enabled = false
	Profile.reset_profile_for_testing()
	Profile.persistence_enabled = false
	Profile.first_run_onboarding_complete = true
	Profile.racer_reputation = 1_000

	_test_state_rules()

	var service := RaceServices.new()
	service.custom_tour_state_path = STATE_PATH
	service.local_leaderboard = LocalLeaderboardProvider.new(BOARD_PATH)
	add_child(service)
	service.leaderboard_updated.connect(_on_leaderboard_updated)

	var garage := GARAGE_UI_SCRIPT.new() as GarageUi
	add_child(garage)
	await get_tree().process_frame
	garage.bind_competition_source(service)
	garage.ride_requested.connect(_on_ride_requested)
	garage.show_garage()
	_check(garage.focus_event_briefing(&"CUSTOM_TOUR"), "Garage focuses the Custom Tour card")
	_check(garage.continue_custom_tour(), "Garage opens the persistent tour builder")
	var builder := garage.get_custom_tour_presentation_snapshot()
	_check(
		bool(builder.get(&"building", false))
		and bool(builder.get(&"builder_open", false))
		and str(builder.get(&"candidate_event_id", "")) == "CIRCUIT",
		"builder exposes phase, input ownership, and its first candidate"
	)
	_check(garage.confirm_custom_tour_selection(), "builder adds the first round")
	_check(garage.cycle_custom_tour_candidate(1), "builder cycles to another event")
	_check(garage.confirm_custom_tour_selection(), "builder adds the second round")
	var drafted := garage.get_custom_tour_presentation_snapshot()
	_check(
		int(drafted.get(&"round_count", 0)) == 2
		and str(drafted.get(&"action_text", "")).contains("START 2-ROUND TOUR"),
		"two selected rounds enable a clear start action"
	)
	_check(
		garage.continue_custom_tour()
		and _rides == [&"CIRCUIT"],
		"starting the tour immediately launches its exact first event"
	)
	_check(FileAccess.file_exists(STATE_PATH), "tour builder and start are atomically persisted")

	var restored := RaceServices.new()
	restored.custom_tour_state_path = STATE_PATH
	restored.call(&"_load_custom_tour_state")
	var restored_snapshot := restored.get_custom_tour_presentation_snapshot()
	_check(
		bool(restored_snapshot.get(&"active", false))
		and str(restored_snapshot.get(&"next_event_id", "")) == "CIRCUIT"
		and int(restored_snapshot.get(&"round_count", 0)) == 2,
		"active tour recovers with the exact authored calendar"
	)

	var first_result := _eligible_result(&"CIRCUIT", 2, "custom-tour-round-1")
	service.call(&"_on_results_ready", first_result)
	var after_first := service.get_custom_tour_presentation_snapshot()
	_check(
		int(after_first.get(&"completed_rounds", 0)) == 1
		and int(after_first.get(&"current_round", 0)) == 2
		and str(after_first.get(&"next_event_id", "")) == "PINE_ENDURO",
		"an eligible official result advances exactly to the second authored round"
	)
	_check(
		StringName(_tour_payload.get(&"kind", &"")) == &"CUSTOM_TOUR",
		"race lifecycle emits an identity-bound Custom Tour result payload"
	)

	garage.show_garage()
	garage.focus_event_briefing(&"CUSTOM_TOUR")
	var continuation := garage.get_custom_tour_presentation_snapshot()
	_check(
		str(continuation.get(&"action_text", "")).contains("NEXT ROUND")
		and garage.continue_custom_tour()
		and _rides == [&"CIRCUIT", &"PINE_ENDURO"],
		"Garage presents and launches the exact next round"
	)

	var second_result := _eligible_result(&"PINE_ENDURO", 1, "custom-tour-round-2")
	service.call(&"_on_results_ready", second_result)
	var completed := service.get_custom_tour_presentation_snapshot()
	var champion := completed.get(&"champion", {}) as Dictionary
	_check(
		bool(completed.get(&"completed", false))
		and int(completed.get(&"completed_rounds", 0)) == 2
		and str(champion.get(&"display_name", "")) == "YOU",
		"final round completes the tour and resolves the points champion"
	)

	var hud := HUD_SCENE.instantiate() as RaceHud
	add_child(hud)
	await get_tree().process_frame
	hud.show_results(second_result)
	hud.update_leaderboard_result(_tour_payload)
	var results := hud.get_competition_presentation_snapshot()
	_check(
		str(results.get(&"text", "")).contains("CUSTOM TOUR")
		and str(results.get(&"text", "")).contains("CHAMPION")
		and str(results.get(&"footer", "")).contains("TOUR COMPLETE"),
		"results render standings, champion, and completion guidance"
	)

	var touch := TOUCH_SCRIPT.new() as TouchRidingControls
	add_child(touch)
	await get_tree().process_frame
	touch.set_garage_continue_label("NEW\nTOUR")
	var controls := touch.get_touch_layout_snapshot().get(&"controls", {}) as Dictionary
	_check(
		str((controls.get(&"continue", {}) as Dictionary).get(&"label", "")) == "NEW\nTOUR",
		"touch Garage exposes the contextual tour action"
	)

	_test_backup_recovery(service)

	garage.queue_free()
	hud.queue_free()
	touch.queue_free()
	service.queue_free()
	await get_tree().process_frame
	_cleanup()
	if _failures.is_empty():
		print("CUSTOM TOUR FLOW PROBE: PASS  //  build+persist+sequence+points+hud+touch+recover")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("CUSTOM TOUR FLOW PROBE: " + failure)
	get_tree().quit(1)


func _test_state_rules() -> void:
	var state := CustomTourState.new()
	_check(bool(state.begin_builder().get(&"ok", false)), "state enters builder mode")
	_check(
		not bool(state.start_tour().get(&"ok", false)),
		"tour cannot start below its two-round minimum"
	)
	for event_id: StringName in [
		&"CIRCUIT", &"PINE_ENDURO", &"MESA_PRACTICE", &"MESA_MX", &"MESA_ELIMINATION",
	]:
		_check(bool(state.toggle_event(event_id).get(&"ok", false)), "builder accepts a unique event")
	_check(
		StringName(state.toggle_event(&"MESA_RIVAL").get(&"error", &"")) == &"TOUR_FULL",
		"builder enforces its five-round maximum"
	)
	_check(bool(state.start_tour().get(&"ok", false)), "five-round tour starts")
	_check(
		StringName(state.submit_round(&"PINE_ENDURO", _classification(1)).get(&"error", &""))
			== &"WRONG_EVENT",
		"only the exact next event can advance the tour"
	)


func _eligible_result(event_id: StringName, player_position: int, run_id: String) -> Dictionary:
	var classification := _classification(player_position)
	return {
		&"run_id": run_id,
		&"signature": "CUSTOM-%s" % event_id,
		&"event_id": event_id,
		&"competition_id": StringName("CUSTOM-%s" % event_id),
		&"valid": true,
		&"player_position": player_position,
		&"player_time_usec": 90_000_000 + player_position * 1_000_000,
		&"player_penalty_usec": 0,
		&"fastest_lap_usec": 44_000_000,
		&"classification": classification,
	}


func _classification(player_position: int) -> Array[Dictionary]:
	var player := {
		&"rider_id": &"PLAYER",
		&"display_name": "YOU",
		&"is_player": true,
		&"position": player_position,
		&"status": &"FINISHED",
	}
	var rival := {
		&"rider_id": &"RIVAL",
		&"display_name": "RIVAL",
		&"is_player": false,
		&"position": 2 if player_position == 1 else 1,
		&"status": &"FINISHED",
	}
	return [player, rival]


func _test_backup_recovery(service: RaceServices) -> void:
	# Re-save once so AtomicConfigStore has a known-good backup, then corrupt only
	# the primary. Loading must repair from the backup without losing the tour.
	service.call(&"_persist_custom_tour_state")
	var file := FileAccess.open(STATE_PATH, FileAccess.WRITE)
	if file == null:
		_check(false, "probe can open the tour primary for recovery simulation")
		return
	file.store_string("not a valid config")
	file.close()
	var recovered := RaceServices.new()
	recovered.custom_tour_state_path = STATE_PATH
	recovered.call(&"_load_custom_tour_state")
	var snapshot := recovered.get_custom_tour_presentation_snapshot()
	_check(
		bool(snapshot.get(&"completed", false))
		and int(snapshot.get(&"completed_rounds", 0)) == 2,
		"corrupt primary recovers the completed tour from its atomic backup"
	)


func _on_ride_requested(_setup: StringName, activity: StringName) -> void:
	_rides.append(activity)


func _on_leaderboard_updated(payload: Dictionary) -> void:
	if StringName(payload.get(&"kind", &"")) == &"CUSTOM_TOUR":
		_tour_payload = payload.duplicate(true)


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
