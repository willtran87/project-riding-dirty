extends Node3D
## Fixed-step contract for interactive gate staging, bounded launch drive, input
## parity, pre-green immobility, and the opponent pack's straight formation.

const BIKE_SCENE := preload("res://entities/bike/bike.tscn")
const GHOST_SCENE := preload("res://features/race/ghost_controller.tscn")
const RACE_SCENE := preload("res://features/race/race_controller.tscn")
const HUD_SCENE := preload("res://features/hud/race_hud.tscn")
const GATE_LAUNCH_SCRIPT := preload("res://features/race/race_gate_launch.gd")
const STEP := 1.0 / 60.0

var _passed: bool = true


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var evaluator_contract := _run_evaluator_contract()
	var input_contract := _verify_input_map_contract()
	var integration_contract := await _run_race_integration()
	_passed = bool(evaluator_contract[&"passed"]) and input_contract and bool(integration_contract[&"passed"])
	print("RACE GATE LAUNCH PROBE: evaluator=%s input=%s integration=%s passed=%s" % [
		str(evaluator_contract), str(input_contract), str(integration_contract), str(_passed),
	])
	if not _passed:
		push_error("RACE GATE LAUNCH PROBE: staging/launch contract failed.")
	get_tree().quit(0 if _passed else 1)


func _run_evaluator_contract() -> Dictionary:
	var keyboard := _simulate_launch(&"KEYBOARD")
	var keyboard_repeat := _simulate_launch(&"KEYBOARD")
	var gamepad := _simulate_launch(&"GAMEPAD")
	var bogged := _simulate_launch(&"BRAKE_HELD")
	var asleep := _simulate_launch(&"NO_INPUT")
	var minimum := float(keyboard[&"minimum_multiplier"])
	var maximum := float(keyboard[&"maximum_multiplier"])
	var all_results: Array[Dictionary] = [keyboard, keyboard_repeat, gamepad, bogged, asleep]
	var bounded := true
	for result: Dictionary in all_results:
		var multiplier := float(result[&"drive_multiplier"])
		bounded = bounded and multiplier >= minimum and multiplier <= maximum
	var deterministic := (
		is_equal_approx(float(keyboard[&"quality"]), float(keyboard_repeat[&"quality"]))
		and is_equal_approx(float(keyboard[&"drive_multiplier"]), float(keyboard_repeat[&"drive_multiplier"]))
		and StringName(keyboard[&"outcome"]) == StringName(keyboard_repeat[&"outcome"])
	)
	var fair_ordering := (
		float(keyboard[&"drive_multiplier"]) >= 1.06
		and float(gamepad[&"drive_multiplier"]) >= 1.03
		and float(keyboard[&"drive_multiplier"]) > float(bogged[&"drive_multiplier"])
		and float(gamepad[&"drive_multiplier"]) > float(asleep[&"drive_multiplier"])
		and float(bogged[&"drive_multiplier"]) < 1.0
		and float(asleep[&"drive_multiplier"]) < 1.0
	)
	return {
		&"keyboard": float(keyboard[&"drive_multiplier"]),
		&"gamepad": float(gamepad[&"drive_multiplier"]),
		&"bogged": float(bogged[&"drive_multiplier"]),
		&"no_input": float(asleep[&"drive_multiplier"]),
		&"bounded": bounded,
		&"deterministic": deterministic,
		&"fair_ordering": fair_ordering,
		&"passed": bounded and deterministic and fair_ordering,
	}


func _simulate_launch(mode: StringName) -> Dictionary:
	var evaluator: RefCounted = GATE_LAUNCH_SCRIPT.new()
	evaluator.call(&"reset")
	var remaining := 1.90
	while remaining > 0.0:
		remaining = maxf(remaining - STEP, 0.0)
		var throttle := 0.0
		var brake := 0.0
		match mode:
			&"KEYBOARD":
				throttle = 1.0
				brake = 1.0 if remaining > 0.17 else 0.0
			&"GAMEPAD":
				throttle = 0.82
				brake = 0.74 if remaining > 0.14 else 0.0
			&"BRAKE_HELD":
				throttle = 1.0
				brake = 1.0
			&"NO_INPUT":
				pass
		evaluator.call(&"sample", STEP, remaining, throttle, brake)
	return evaluator.call(&"finalize") as Dictionary


func _verify_input_map_contract() -> bool:
	var has_keyboard_throttle := false
	var has_gamepad_throttle := false
	var has_keyboard_brake := false
	var has_gamepad_brake := false
	for event: InputEvent in InputMap.action_get_events(&"throttle"):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_W:
			has_keyboard_throttle = true
		if event is InputEventJoypadMotion and (event as InputEventJoypadMotion).axis == JOY_AXIS_TRIGGER_RIGHT:
			has_gamepad_throttle = true
	for event: InputEvent in InputMap.action_get_events(&"brake"):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_S:
			has_keyboard_brake = true
		if event is InputEventJoypadMotion and (event as InputEventJoypadMotion).axis == JOY_AXIS_TRIGGER_LEFT:
			has_gamepad_brake = true
	return has_keyboard_throttle and has_gamepad_throttle and has_keyboard_brake and has_gamepad_brake


func _run_race_integration() -> Dictionary:
	var bike := BIKE_SCENE.instantiate() as DirtBikeController
	var ghost := GHOST_SCENE.instantiate() as GhostController
	var race := RACE_SCENE.instantiate() as RaceController
	var hud := HUD_SCENE.instantiate() as RaceHud
	add_child(bike)
	add_child(ghost)
	add_child(race)
	add_child(hud)
	ghost.persistence_enabled = false
	await get_tree().process_frame
	await get_tree().physics_frame
	bike.set_physics_process(false)
	race.set_physics_process(false)
	var route := CourseCatalog.get_world_riding_points(CourseCatalog.QUARRY_ID)
	race.initialize(bike, ghost, CourseCatalog.QUARRY_ID, route, null)
	hud.initialize(bike, CourseCatalog.QUARRY_ID, route)
	hud.bind_race_source(race)
	var config := RaceSessionConfig.from_dictionary({
		&"event_id": &"GATE_LAUNCH_PROBE",
		&"track_id": CourseCatalog.QUARRY_ID,
		&"display_name": "GATE LAUNCH PROBE",
		&"countdown_seconds": 1.20,
		&"staging_seconds": 0.0,
		&"opponent_count": 3,
		&"field_size": 4,
		&"finish_grace_seconds": 0.0,
	})
	race.configure_session(config, route, null)
	race.reset_run()
	var pack := race.get_node("RacePack") as RacePack
	pack.set_physics_process(false)
	var start_transform := bike.global_transform
	var maximum_pre_green_drift := 0.0
	var remained_frozen := true
	var controls_remained_locked := true
	var staging_became_active := false
	var hud_showed_live_staging := false
	Input.action_press(&"throttle", 1.0)
	Input.action_press(&"brake", 1.0)
	for _frame: int in 90:
		var before := race.get_session_snapshot()
		if float(before.get(&"countdown", 0.0)) <= 0.17:
			Input.action_release(&"brake")
		race.call(&"_physics_process", STEP)
		if race.state == RaceController.State.RACING:
			break
		var drift := start_transform.origin.distance_to(bike.global_position)
		maximum_pre_green_drift = maxf(maximum_pre_green_drift, drift)
		remained_frozen = remained_frozen and bike.freeze and bike.get_speed_mps() <= 0.0001
		controls_remained_locked = controls_remained_locked and not bike.controls_enabled
		staging_became_active = staging_became_active or bool(bike.get_gate_staging_input_snapshot().get(&"enabled", false))
		var hud_feedback := hud.get_gate_launch_feedback_snapshot()
		hud_showed_live_staging = hud_showed_live_staging or (
			bool(hud_feedback.get(&"visible", false))
			and str(hud_feedback.get(&"text", "")).contains("THROTTLE")
		)
	Input.action_release(&"throttle")
	Input.action_release(&"brake")
	var gate := race.get_gate_launch_snapshot()
	var drive := bike.get_gate_launch_drive_snapshot()
	var launch := pack.get_launch_snapshot()
	var hud_result := hud.get_gate_launch_feedback_snapshot()
	var hud_showed_result := (
		bool(hud_result.get(&"visible", false))
		and str(hud_result.get(&"text", "")).contains("GATE")
		and str(hud_result.get(&"text", "")).contains("DRIVE")
	)
	var started := race.state == RaceController.State.RACING
	var bounded_drive := (
		float(drive.get(&"multiplier", 0.0)) >= float(gate.get(&"minimum_multiplier", 0.94))
		and float(drive.get(&"multiplier", 0.0)) <= float(gate.get(&"maximum_multiplier", 1.08))
		and is_equal_approx(float(drive.get(&"multiplier", 0.0)), float(gate.get(&"drive_multiplier", -1.0)))
	)
	var natural_field_launch := (
		float(launch.get(&"lock_seconds", 0.0)) >= 2.4
		and float(launch.get(&"max_lane_displacement", INF)) <= 0.001
		and float(launch.get(&"max_lateral_speed", INF)) <= 0.001
	)
	var passed := (
		started
		and staging_became_active
		and hud_showed_live_staging
		and hud_showed_result
		and remained_frozen
		and controls_remained_locked
		and maximum_pre_green_drift <= 0.0001
		and bool(gate.get(&"finalized", false))
		and float(gate.get(&"drive_multiplier", 0.0)) >= 1.06
		and bool(drive.get(&"active", false))
		and bounded_drive
		and natural_field_launch
	)
	race.queue_free()
	ghost.queue_free()
	bike.queue_free()
	hud.queue_free()
	return {
		&"started": started,
		&"staging_active": staging_became_active,
		&"hud_live": hud_showed_live_staging,
		&"hud_result": hud_showed_result,
		&"frozen": remained_frozen,
		&"controls_locked": controls_remained_locked,
		&"pre_green_drift": maximum_pre_green_drift,
		&"gate_multiplier": float(gate.get(&"drive_multiplier", 0.0)),
		&"bike_multiplier": float(drive.get(&"multiplier", 0.0)),
		&"natural_field_launch": natural_field_launch,
		&"passed": passed,
	}
