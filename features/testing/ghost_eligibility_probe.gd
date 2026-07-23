extends Node3D
## Public integration regression for competitive PB ghost eligibility.
## A faster run that violates CLEAN_RIDE must remain an auditable result without
## replacing or announcing the eligible comparison ghost.

const BIKE_SCENE := preload("res://entities/bike/bike.tscn")
const GHOST_SCENE := preload("res://features/race/ghost_controller.tscn")
const RACE_SCENE := preload("res://features/race/race_controller.tscn")

var _failures := PackedStringArray()
var _finish_best_flags: Array[bool] = []
var _results: Array[Dictionary] = []


func _ready() -> void:
	Profile.persistence_enabled = false
	_run.call_deferred()


func _run() -> void:
	var bike := BIKE_SCENE.instantiate() as DirtBikeController
	var ghost := GHOST_SCENE.instantiate() as GhostController
	var race := RACE_SCENE.instantiate() as RaceController
	add_child(bike)
	add_child(ghost)
	add_child(race)
	ghost.persistence_enabled = false
	EventBus.race_finished.connect(_on_race_finished)
	race.results_ready.connect(_on_results_ready)
	await _wait_physics_frames(2)

	var route := CourseCatalog.get_world_riding_points(CourseCatalog.QUARRY_ID)
	race.initialize(bike, ghost, CourseCatalog.QUARRY_ID, route, null)
	race.configure_session(RaceSessionConfig.from_dictionary({
		&"event_id": &"GHOST_ELIGIBILITY_PROBE",
		&"track_id": CourseCatalog.QUARRY_ID,
		&"display_name": "GHOST ELIGIBILITY PROBE",
		&"format": &"TIME_ATTACK",
		&"session_type": &"MAIN",
		&"championship_id": &"",
		&"route_version": 19,
		&"laps": 1,
		&"opponent_count": 0,
		&"checkpoint_count": 1,
		&"countdown_seconds": 0.1,
		&"staging_seconds": 0.0,
		&"finish_grace_seconds": 0.0,
		&"rules": {&"modifiers": ["CLEAN_RIDE"]},
	}), route, null)
	_disable_automatic_gate_detection(race)

	await _complete_attempt(race, bike, false, 30)
	var baseline_best := ghost.best_time_usec
	_assert(_results.size() == 1 and bool(_results[0].get(&"valid", false)), "eligible baseline result was not valid")
	_assert(_finish_best_flags == [true], "eligible baseline did not announce a PB")
	_assert(baseline_best > 0, "eligible baseline did not persist its PB ghost")

	await _complete_attempt(race, bike, true, 8)
	var invalid_result: Dictionary = _results[1] if _results.size() >= 2 else {}
	_assert(
		not invalid_result.is_empty()
		and not bool(invalid_result.get(&"valid", true))
		and str(invalid_result.get(&"validity_reason", "")).contains("CLEAN_RIDE"),
		"contacting challenger was not rejected by CLEAN_RIDE"
	)
	_assert(
		int(invalid_result.get(&"player_time_usec", baseline_best + 1)) < baseline_best,
		"invalid challenger was not actually faster than the baseline"
	)
	_assert(_finish_best_flags == [true, false], "invalid challenger announced a PB")
	_assert(ghost.best_time_usec == baseline_best, "invalid challenger replaced the eligible PB ghost")
	_assert(
		not bool((invalid_result.get(&"rewards", {}) as Dictionary).get(&"new_best", true)),
		"invalid challenger exposed a PB reward"
	)

	var passed := _failures.is_empty()
	print("GHOST ELIGIBILITY PROBE: baseline=%dus challenger=%dus flags=%s ghost=%dus passed=%s failures=%s" % [
		baseline_best,
		int(invalid_result.get(&"player_time_usec", -1)),
		str(_finish_best_flags),
		ghost.best_time_usec,
		str(passed),
		", ".join(_failures),
	])
	if EventBus.race_finished.is_connected(_on_race_finished):
		EventBus.race_finished.disconnect(_on_race_finished)
	race.queue_free()
	ghost.queue_free()
	bike.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if passed else 1)


func _complete_attempt(race: RaceController, bike: DirtBikeController, violate_clean_ride: bool, live_frames: int) -> void:
	var results_before := _results.size()
	race.reset_run()
	if not await _wait_for_state(race, RaceController.State.RACING, 60):
		_failures.append("attempt never reached RACING")
		return
	bike.set_motion_locked(true)
	await _wait_physics_frames(live_frames)
	if violate_clean_ride:
		bike.pack_contacted.emit(1.0)
	var gates := _checkpoint_gates(race)
	if gates.is_empty():
		_failures.append("race checkpoints are missing")
		return
	for gate: Area3D in gates:
		gate.body_entered.emit(bike)
	await _wait_for_state(race, RaceController.State.RESULTS, 30)
	_assert(_results.size() == results_before + 1, "attempt did not emit exactly one official result")


func _disable_automatic_gate_detection(race: RaceController) -> void:
	for child: Node in race.get_children():
		if child is Area3D and child.name.begins_with("Checkpoint"):
			(child as Area3D).collision_mask = 0


func _checkpoint_gates(race: RaceController) -> Array[Area3D]:
	var gates: Array[Area3D] = []
	for child: Node in race.get_children():
		if child is Area3D and child.name.begins_with("Checkpoint"):
			gates.append(child as Area3D)
	gates.sort_custom(func(first: Area3D, second: Area3D) -> bool:
		return String(first.name).naturalnocasecmp_to(String(second.name)) < 0
	)
	return gates


func _on_race_finished(_time_usec: int, _medal: StringName, is_new_best: bool) -> void:
	_finish_best_flags.append(is_new_best)


func _on_results_ready(result: Dictionary) -> void:
	_results.append(result.duplicate(true))


func _wait_for_state(race: RaceController, target: RaceController.State, maximum_frames: int) -> bool:
	for _frame: int in maximum_frames:
		if race.state == target:
			return true
		await get_tree().physics_frame
	return race.state == target


func _wait_physics_frames(count: int) -> void:
	for _frame: int in count:
		await get_tree().physics_frame


func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
