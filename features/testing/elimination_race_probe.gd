extends Node
## Deterministic public-contract regression for Last Rider Out. The probe uses
## the dedicated RacePack simulation path so it can exercise lap arbitration,
## classification, and signals without input, rendering, or wall-clock waits.

const STEP := 1.0 / 60.0
const MAX_SIMULATION_STEPS := 2400
const TEST_LAPS := 4
const TEST_OPPONENTS := 3
const BIKE_SCENE := preload("res://entities/bike/bike.tscn")
const GHOST_SCENE := preload("res://features/race/ghost_controller.tscn")
const RACE_SCENE := preload("res://features/race/race_controller.tscn")
const HUD_SCENE := preload("res://features/hud/race_hud.tscn")

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var player_out := _verify_player_can_be_eliminated_before_crossing()
	var npc_out := _verify_correct_npc_is_eliminated_with_player_ahead()
	var deterministic_tie := _verify_deterministic_tie_selection()
	var settlement := await _verify_controller_and_hud_settlement()
	var passed := player_out and npc_out and deterministic_tie and settlement and _failures.is_empty()
	print(
		"ELIMINATION RACE PROBE: player_out=%s npc_out=%s tie=%s settlement=%s failures=%d passed=%s"
		% [
			str(player_out), str(npc_out), str(deterministic_tie), str(settlement),
			_failures.size(), str(passed),
		]
	)
	if not passed:
		for failure: String in _failures:
			push_error("ELIMINATION RACE PROBE: " + failure)
	get_tree().quit(0 if passed else 1)


func _verify_player_can_be_eliminated_before_crossing() -> bool:
	var pack := _create_pack(&"PlayerOutPack")
	var eliminations: Array[Dictionary] = []
	pack.rider_eliminated.connect(_capture_elimination.bind(eliminations))
	pack.start_race()

	var first_elimination_reached := _step_until_elimination(pack, eliminations, 0.0)
	var first_event: Dictionary = eliminations[0] if not eliminations.is_empty() else {}
	var first_snapshot := pack.get_elimination_snapshot()
	var player_row := _racer_by_id(pack.get_classification_snapshot(), &"PLAYER")
	var rounds: Dictionary = first_snapshot.get(&"rounds", {}) as Dictionary
	var initial_contract := (
		first_elimination_reached
		and StringName(first_event.get(&"rider_id", &"")) == &"PLAYER"
		and int(first_event.get(&"lap", -1)) == 1
		and bool(first_snapshot.get(&"enabled", false))
		and int(first_snapshot.get(&"round_count", -1)) == 1
		and StringName(rounds.get(1, &"")) == &"PLAYER"
		and (first_snapshot.get(&"pending_laps", []) as Array).is_empty()
		and StringName(first_snapshot.get(&"last_rider_id", &"")) == &"PLAYER"
		and int(first_snapshot.get(&"player_elimination_lap", -1)) == 1
		and StringName(first_snapshot.get(&"player_status", &"")) == &"ELIMINATED"
		and StringName(player_row.get(&"status", &"")) == &"ELIMINATED"
		and int(player_row.get(&"elimination_lap", -1)) == 1
		and int(player_row.get(&"laps_completed", -1)) == 0
	)
	if not initial_contract:
		_failures.append(
			"stationary player was not eliminated exactly once on lap 1 before crossing: event=%s snapshot=%s player=%s"
			% [str(first_event), str(first_snapshot), str(player_row)]
		)

	# Let every surviving NPC cross the same lap line. Their crossings must not
	# resolve lap 1 again; a later lap may legitimately create its own round.
	var all_npcs_crossed_lap_one := false
	for _step: int in MAX_SIMULATION_STEPS:
		pack.simulate_competition_step(STEP, 0.0, 0.0, false)
		if _all_npcs_reached_lap(pack, 1):
			all_npcs_crossed_lap_one = true
			break
	var lap_one_eliminations := _count_eliminations_for_lap(eliminations, 1)
	var after_crossings := pack.get_elimination_snapshot()
	var after_rounds: Dictionary = after_crossings.get(&"rounds", {}) as Dictionary
	var no_duplicate := (
		all_npcs_crossed_lap_one
		and lap_one_eliminations == 1
		and StringName(after_rounds.get(1, &"")) == &"PLAYER"
	)
	if not no_duplicate:
		_failures.append(
			"lap 1 resolved more than once or surviving NPCs never crossed: events=%s snapshot=%s"
			% [str(eliminations), str(after_crossings)]
		)

	_destroy_pack(pack)
	return initial_contract and no_duplicate


func _verify_correct_npc_is_eliminated_with_player_ahead() -> bool:
	var pack := _create_pack(&"NpcOutPack")
	var eliminations: Array[Dictionary] = []
	pack.rider_eliminated.connect(_capture_elimination.bind(eliminations))
	pack.start_race()
	# Keep the player just before the timing line so the first NPC crossing owns
	# the lap trigger while the player is still ahead of every non-leader NPC.
	# A fixed eight-metre margin became pace-dependent once the field tightened.
	var player_progress := pack.get_track_length() - 0.001
	var reached := _step_until_elimination(pack, eliminations, player_progress)
	var event: Dictionary = eliminations[0] if not eliminations.is_empty() else {}
	var eliminated_id := StringName(event.get(&"rider_id", &""))
	var classification := pack.get_classification_snapshot()
	var player_row := _racer_by_id(classification, &"PLAYER")
	var eliminated_row := _racer_by_id(classification, eliminated_id)
	var eliminated_progress := float(eliminated_row.get(&"total_progress", INF))
	var every_survivor_ahead := true
	for racer: Dictionary in classification:
		if StringName(racer.get(&"status", &"")) != &"RUNNING":
			continue
		every_survivor_ahead = (
			every_survivor_ahead
			and float(racer.get(&"total_progress", -INF)) >= eliminated_progress - 0.001
		)
	var snapshot := pack.get_elimination_snapshot()
	var rounds: Dictionary = snapshot.get(&"rounds", {}) as Dictionary
	var correct_npc := (
		reached
		and not eliminated_id.is_empty()
		and eliminated_id != &"PLAYER"
		and int(event.get(&"lap", -1)) == 1
		and StringName(eliminated_row.get(&"status", &"")) == &"ELIMINATED"
		and int(eliminated_row.get(&"elimination_lap", -1)) == 1
		and StringName(player_row.get(&"status", &"")) == &"RUNNING"
		and float(player_row.get(&"total_progress", 0.0)) > eliminated_progress
		and every_survivor_ahead
		and StringName(rounds.get(1, &"")) == eliminated_id
		and StringName(snapshot.get(&"last_rider_id", &"")) == eliminated_id
		and int(snapshot.get(&"round_count", -1)) == 1
	)
	if not correct_npc:
		_failures.append(
			"leading player did not leave the least-progressed NPC as lap-1 elimination: event=%s snapshot=%s classification=%s"
			% [str(event), str(snapshot), str(classification)]
		)
	_destroy_pack(pack)
	return correct_npc


func _verify_deterministic_tie_selection() -> bool:
	var classification: Array[Dictionary] = [
		{&"rider_id": &"ALPHA", &"status": &"RUNNING", &"total_progress": 42.0},
		{&"rider_id": &"PLAYER", &"status": &"RUNNING", &"total_progress": 58.0},
		{&"rider_id": &"ZULU", &"status": &"RUNNING", &"total_progress": 42.0},
		{&"rider_id": &"OLD_OUT", &"status": &"ELIMINATED", &"total_progress": 1.0},
		{&"rider_id": &"WINNER", &"status": &"FINISHED", &"total_progress": 120.0},
	]
	var reversed_classification: Array[Dictionary] = classification.duplicate(true)
	reversed_classification.reverse()
	var selected := RacePack.select_elimination_candidate(classification)
	var selected_reversed := RacePack.select_elimination_candidate(reversed_classification)
	var passed := selected == &"ZULU" and selected_reversed == &"ZULU"
	if not passed:
		_failures.append(
			"equal-progress tie selection depended on input order: forward=%s reverse=%s"
			% [String(selected), String(selected_reversed)]
		)
	return passed


func _verify_controller_and_hud_settlement() -> bool:
	var previous_persistence := Profile.persistence_enabled
	Profile.persistence_enabled = false
	var bike := BIKE_SCENE.instantiate() as DirtBikeController
	var ghost := GHOST_SCENE.instantiate() as GhostController
	var race := RACE_SCENE.instantiate() as RaceController
	var hud := HUD_SCENE.instantiate() as RaceHud
	add_child(bike)
	add_child(ghost)
	add_child(race)
	add_child(hud)
	ghost.persistence_enabled = false
	var emitted_results: Array[Dictionary] = []
	race.results_ready.connect(_capture_result.bind(emitted_results))
	await _wait_physics_frames(2)

	var route := _controller_test_route()
	race.initialize(bike, ghost, CourseCatalog.MESA_MX_ID, route, null)
	race.configure_session(_controller_test_session(), route, null)
	await _wait_physics_frames(2)
	race.reset_run()
	var started := await _wait_for_race_state(race, RaceController.State.RACING, 60)
	var locked_position := bike.global_position
	if started:
		bike.set_motion_locked(true)
		locked_position = bike.global_position
	var reached_results := false
	if started:
		reached_results = await _wait_for_race_state(
			race,
			RaceController.State.RESULTS,
			600
		)
	var result: Dictionary = emitted_results[0] if not emitted_results.is_empty() else race.get_results_preview()
	var classification_value: Variant = result.get(&"classification", [])
	var classification: Array[Dictionary] = []
	if classification_value is Array:
		classification.assign(classification_value as Array)
	var player_row := _racer_by_id(classification, &"PLAYER")
	var npc_count := 0
	var all_survivors_classified := true
	var any_dnf := false
	for racer: Dictionary in classification:
		if bool(racer.get(&"is_player", false)):
			continue
		npc_count += 1
		var status := StringName(racer.get(&"status", &""))
		all_survivors_classified = all_survivors_classified and status == &"CLASSIFIED"
		any_dnf = any_dnf or status == &"DNF"
	var rewards: Dictionary = result.get(&"rewards", {}) as Dictionary
	var zero_rewards := (
		int(rewards.get(&"cash", -1)) == 0
		and int(rewards.get(&"reputation", -1)) == 0
		and int(rewards.get(&"base_cash", -1)) == 0
		and int(rewards.get(&"base_reputation", -1)) == 0
		and int(rewards.get(&"bonus_cash", -1)) == 0
		and int(rewards.get(&"bonus_reputation", -1)) == 0
		and int(rewards.get(&"placement_bonus", -1)) == 0
		and int(rewards.get(&"placement_reputation", -1)) == 0
	)
	var controller_contract := (
		started
		and reached_results
		and emitted_results.size() == 1
		and StringName(result.get(&"event_id", &"")) == &"MESA_ELIMINATION"
		and StringName(result.get(&"format", &"")) == &"ELIMINATION"
		and int(result.get(&"player_time_usec", 0)) == -1
		and int(result.get(&"player_elimination_lap", -1)) == 1
		and StringName(result.get(&"medal", &"")) == &"NO_AWARD"
		and int(result.get(&"championship_points", -1)) == 0
		and zero_rewards
		and not RaceServices.is_leaderboard_result_eligible(result)
		and StringName(player_row.get(&"status", &"")) == &"ELIMINATED"
		and int(player_row.get(&"elimination_lap", -1)) == 1
		and int(player_row.get(&"laps_completed", -1)) == 0
		and npc_count == TEST_OPPONENTS
		and all_survivors_classified
		and not any_dnf
		and not bike.controls_enabled
		and Vector2(bike.global_position.x, bike.global_position.z).distance_to(
			Vector2(locked_position.x, locked_position.z)
		) <= 0.05
	)
	if not controller_contract:
		_failures.append(
			"real controller did not settle a stationary player elimination correctly: started=%s results=%s emissions=%d controls=%s result=%s"
			% [
				str(started), str(reached_results), emitted_results.size(),
				str(bike.controls_enabled), str(result),
			]
		)

	var hud_contract := false
	if not result.is_empty():
		hud.show_results(result)
		await get_tree().process_frame
		var presentation := hud.get_competition_presentation_snapshot()
		var title := str(presentation.get(&"title", "")).to_upper()
		var summary := str(presentation.get(&"summary", "")).to_upper()
		var competition_text := str(presentation.get(&"text", "")).to_upper()
		hud_contract = (
			bool(presentation.get(&"results_visible", false))
			and title.contains("ELIMINATED")
			and summary.contains("ELIMINATED")
			and summary.contains("LAP 1")
			and competition_text.contains("LOCAL BOARD  //  NOT ELIGIBLE")
			and not competition_text.contains("RESULT PENDING")
		)
		if not hud_contract:
			_failures.append(
				"HUD did not explicitly present elimination, lap 1, and board ineligibility: title=%s summary=%s board=%s snapshot=%s"
				% [title, summary, competition_text, str(presentation)]
			)
	else:
		_failures.append("HUD settlement could not run because the controller emitted no result")

	race.set_physics_process(false)
	bike.set_physics_process(false)
	bike.shutdown_audio()
	ghost.cancel_run()
	hud.queue_free()
	race.queue_free()
	bike.queue_free()
	ghost.queue_free()
	for _frame: int in 4:
		await get_tree().process_frame
	Profile.persistence_enabled = previous_persistence
	return controller_contract and hud_contract


func _create_pack(node_name: StringName) -> RacePack:
	var pack := RacePack.new()
	pack.name = node_name
	pack.presentation_enabled = false
	pack.simulation_has_player = true
	add_child(pack)
	pack.set_process(false)
	pack.set_physics_process(false)
	pack.configure(CourseCatalog.MESA_MX_ID, _closed_test_route(), null, _test_session())
	return pack


func _test_session() -> RaceSessionConfig:
	var session := RaceEventCatalog.get_session_config(&"MESA_ELIMINATION")
	session.laps = TEST_LAPS
	session.opponent_count = TEST_OPPONENTS
	session.field_size = TEST_OPPONENTS + 1
	session.rules[&"eliminate_last_each_lap"] = true
	return session


func _controller_test_session() -> RaceSessionConfig:
	var session := RaceEventCatalog.get_session_config(&"MESA_ELIMINATION")
	session.opponent_count = TEST_OPPONENTS
	session.field_size = TEST_OPPONENTS + 1
	session.checkpoint_count = 6
	session.countdown_seconds = 0.1
	session.staging_seconds = 0.0
	session.finish_grace_seconds = 0.0
	return session


func _closed_test_route() -> PackedVector3Array:
	return PackedVector3Array([
		Vector3(0.0, 0.0, 0.0),
		Vector3(0.0, 0.0, 30.0),
		Vector3(30.0, 0.0, 30.0),
		Vector3(30.0, 0.0, 0.0),
		Vector3(0.0, 0.0, 0.0),
	])


func _controller_test_route() -> PackedVector3Array:
	return PackedVector3Array([
		Vector3(0.0, 0.0, 0.0),
		Vector3(0.0, 0.0, 6.0),
		Vector3(6.0, 0.0, 6.0),
		Vector3(6.0, 0.0, 0.0),
		Vector3(0.0, 0.0, 0.0),
	])


func _step_until_elimination(
	pack: RacePack,
	events: Array[Dictionary],
	player_total_progress: float
) -> bool:
	for _step: int in MAX_SIMULATION_STEPS:
		pack.simulate_competition_step(STEP, 0.0, player_total_progress, false)
		if not events.is_empty():
			return true
	return false


func _all_npcs_reached_lap(pack: RacePack, target_lap: int) -> bool:
	var npc_count := 0
	for racer: Dictionary in pack.get_classification_snapshot(false):
		npc_count += 1
		if int(racer.get(&"laps_completed", 0)) < target_lap:
			return false
	return npc_count == TEST_OPPONENTS


func _racer_by_id(classification: Array[Dictionary], rider_id: StringName) -> Dictionary:
	for racer: Dictionary in classification:
		if StringName(racer.get(&"rider_id", &"")) == rider_id:
			return racer
	return {}


func _capture_elimination(
	rider_id: StringName,
	elimination_lap: int,
	events: Array[Dictionary]
) -> void:
	events.append({&"rider_id": rider_id, &"lap": elimination_lap})


func _capture_result(result: Dictionary, events: Array[Dictionary]) -> void:
	events.append(result.duplicate(true))


func _count_eliminations_for_lap(events: Array[Dictionary], target_lap: int) -> int:
	var count := 0
	for event: Dictionary in events:
		if int(event.get(&"lap", -1)) == target_lap:
			count += 1
	return count


func _destroy_pack(pack: RacePack) -> void:
	pack.stop_race()
	remove_child(pack)
	pack.free()


func _wait_for_race_state(
	race: RaceController,
	target: RaceController.State,
	maximum_frames: int
) -> bool:
	for _frame: int in maximum_frames:
		if race.state == target:
			return true
		await get_tree().physics_frame
	return race.state == target


func _wait_physics_frames(frame_count: int) -> void:
	for _frame: int in frame_count:
		await get_tree().physics_frame
