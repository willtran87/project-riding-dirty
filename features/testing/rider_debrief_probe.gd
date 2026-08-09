extends Node
## Deterministic contract for actionable post-race coaching, racecraft evidence,
## official Results presentation, and browser-safe projection authority.

const RIDER_DEBRIEF_SCRIPT := preload("res://features/race/rider_debrief.gd")
const HUD_SCENE := preload("res://features/hud/race_hud.tscn")
const GARAGE_SCENE := preload("res://features/garage/garage_ui.tscn")

var _failures := PackedStringArray()


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	Profile.persistence_enabled = false
	Profile.reset_profile_for_testing()
	var result := _base_result()
	var context := {
		&"rival_target_usec": 100_000_000,
		&"laps": 2,
		&"checkpoint_count": 4,
		&"checkpoint_progress_ratios": [0.25, 0.50, 0.75, 1.0],
	}
	var sector_debrief := RIDER_DEBRIEF_SCRIPT.build(result, context)
	var repeated := RIDER_DEBRIEF_SCRIPT.build(result, context)
	_check(sector_debrief == repeated, "Identical official results produced different coaching")
	_check(
		StringName(sector_debrief.get(&"focus_id", &"")) == &"SECTOR_PACE"
		and int(sector_debrief.get(&"costliest_sector", 0)) == 3
		and int(sector_debrief.get(&"costliest_sector_delta_usec", 0)) == 2_500_000
		and str(sector_debrief.get(&"next_objective", "")).contains("S03"),
		"Sector authority did not identify and coach the costliest split"
	)
	_check(
		int(sector_debrief.get(&"best_sector", 0)) == 4
		and int(sector_debrief.get(&"best_sector_delta_usec", 0)) == -1_500_000,
		"Sector authority did not preserve the strongest split"
	)

	var crash_result := result.duplicate(true)
	crash_result[&"crashes"] = 2
	crash_result[&"recoveries"] = 2
	var crash_debrief := RIDER_DEBRIEF_SCRIPT.build(crash_result, context)
	_check(
		StringName(crash_debrief.get(&"focus_id", &"")) == &"CRASH_CONTROL"
		and str(crash_debrief.get(&"next_objective", "")).contains("COMPOSE OR BRACE"),
		"Crash recovery did not outrank pace as the next actionable focus"
	)
	var cleaner_result := result.duplicate(true)
	cleaner_result[&"player_position"] = 5
	var cleaner_debrief := RIDER_DEBRIEF_SCRIPT.build(cleaner_result, context)
	var crash_follow_up := RIDER_DEBRIEF_SCRIPT.evaluate_follow_up(crash_debrief, cleaner_debrief)
	cleaner_debrief[&"follow_up"] = crash_follow_up
	cleaner_debrief[&"summary"] = RIDER_DEBRIEF_SCRIPT.compose_summary(cleaner_debrief)
	_check(
		StringName(crash_follow_up.get(&"status", &"")) == &"CLEARED"
		and bool(crash_follow_up.get(&"achieved", false))
		and not bool(crash_follow_up.get(&"position_improved", true))
		and str(cleaner_debrief.get(&"summary", "")).contains("LAST GOAL CLEARED")
		and str(cleaner_debrief.get(&"summary", "")).contains("ZERO CRASHES"),
		"A safer ride was not celebrated independently of its worse finishing position"
	)
	var reduced_crash_result := result.duplicate(true)
	reduced_crash_result[&"crashes"] = 1
	var reduced_crash_debrief := RIDER_DEBRIEF_SCRIPT.build(reduced_crash_result, context)
	var crash_progress := RIDER_DEBRIEF_SCRIPT.evaluate_follow_up(crash_debrief, reduced_crash_debrief)
	_check(
		StringName(crash_progress.get(&"status", &"")) == &"PROGRESS"
		and bool(crash_progress.get(&"improved", false))
		and not bool(crash_progress.get(&"achieved", true)),
		"Partial objective improvement did not produce a progress receipt"
	)

	var flow_result := result.duplicate(true)
	flow_result[&"sector_times_usec"] = []
	flow_result[&"lap_times_usec"] = []
	flow_result[&"racecraft_metrics"] = {&"flow_uses": 0, &"flow_surges": 0}
	var flow_debrief := RIDER_DEBRIEF_SCRIPT.build(flow_result, {})
	_check(
		StringName(flow_debrief.get(&"focus_id", &"")) == &"FLOW_USAGE"
		and str(flow_debrief.get(&"next_objective", "")).contains("SURGE"),
		"A classified trailing rider with unused Flow received no Flow/boost objective"
	)
	var used_flow_result := flow_result.duplicate(true)
	used_flow_result[&"racecraft_metrics"] = {&"flow_uses": 2, &"flow_surges": 1}
	var used_flow_debrief := RIDER_DEBRIEF_SCRIPT.build(used_flow_result, {})
	var flow_follow_up := RIDER_DEBRIEF_SCRIPT.evaluate_follow_up(flow_debrief, used_flow_debrief)
	_check(
		StringName(flow_follow_up.get(&"status", &"")) == &"CLEARED"
		and str(flow_follow_up.get(&"receipt", "")).contains("1 SURGE"),
		"The next race did not resolve the prior Flow/Surge objective from official evidence"
	)

	var invalid_result := result.duplicate(true)
	invalid_result[&"valid"] = false
	invalid_result[&"validity_reason"] = "MISSED_GATE"
	var invalid_debrief := RIDER_DEBRIEF_SCRIPT.build(invalid_result, context)
	_check(
		StringName(invalid_debrief.get(&"focus_id", &"")) == &"CLASSIFICATION"
		and str(invalid_debrief.get(&"primary_insight", "")) == "MISSED GATE"
		and int(invalid_debrief.get(&"score", 100)) <= 54,
		"Invalid runs did not prioritize a classified finish or bound the grade"
	)

	result[&"rider_debrief"] = cleaner_debrief
	var hud := HUD_SCENE.instantiate() as RaceHud
	add_child(hud)
	await get_tree().process_frame
	hud.show_results(result)
	await get_tree().process_frame
	await get_tree().process_frame
	var presentation := hud.get_competition_presentation_snapshot()
	var projected := presentation.get(&"rider_debrief", {}) as Dictionary
	var navigation := hud.get_results_navigation_snapshot()
	_check(
		str(presentation.get(&"rider_debrief_text", "")).contains("RIDER DEBRIEF")
		and StringName(projected.get(&"focus_id", &"")) == &"SECTOR_PACE"
		and str(presentation.get(&"rider_debrief_text", "")).contains("LAST GOAL CLEARED"),
		"Official Results did not present the authoritative rider debrief"
	)
	_check(bool(navigation.get(&"content_fits", false)), "Rider debrief caused Results content clipping")
	var garage := GARAGE_SCENE.instantiate() as GarageUi
	add_child(garage)
	await get_tree().process_frame
	garage.show_garage()
	garage.set_rider_debrief(sector_debrief)
	var strategy := garage.get_event_strategy_presentation_snapshot()
	_check(
		str(strategy.get(&"label", "")).contains("RIDER FOCUS SECTOR PACE")
		and StringName((strategy.get(&"rider_debrief", {}) as Dictionary).get(&"focus_id", &"")) == &"SECTOR_PACE",
		"Garage did not carry the official lesson into the next setup decision"
	)

	var passed := _failures.is_empty()
	print("RIDER DEBRIEF PROBE: sector=%s crash=%s flow=%s follow_up=%s/%s invalid=%s grade=%s layout=%s garage=%s passed=%s failures=%s" % [
		str(sector_debrief.get(&"focus_id", &"")), str(crash_debrief.get(&"focus_id", &"")),
		str(flow_debrief.get(&"focus_id", &"")), str(crash_follow_up.get(&"status", &"")),
		str(flow_follow_up.get(&"status", &"")), str(invalid_debrief.get(&"focus_id", &"")),
		str(sector_debrief.get(&"grade", &"")), str(navigation.get(&"content_fits", false)),
		str(str(strategy.get(&"label", "")).contains("RIDER FOCUS")),
		str(passed), ", ".join(_failures),
	])
	garage.queue_free()
	hud.queue_free()
	await get_tree().process_frame
	if passed:
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("RIDER DEBRIEF PROBE: " + failure)
	get_tree().quit(1)


func _base_result() -> Dictionary:
	return {
		&"run_id": "rider-debrief-probe",
		&"signature": "rider-debrief-probe-signature",
		&"event_id": &"CIRCUIT",
		&"event_name": "QUARRY TRAIL",
		&"valid": true,
		&"medal": &"SILVER",
		&"classification": _classification(),
		&"player_position": 2,
		&"player_time_usec": 99_000_000,
		&"player_penalty_usec": 0,
		&"fastest_lap_usec": 48_500_000,
		&"fastest_rider_id": &"PLAYER",
		&"overtakes": 2,
		&"contacts": 0,
		&"crashes": 0,
		&"recoveries": 0,
		&"reset_count": 0,
		&"off_course_count": 0,
		&"wrong_way_count": 0,
		&"cut_count": 0,
		&"holeshot_rider_id": &"ROOK",
		&"sector_times_usec": [12_000_000, 12_000_000, 15_000_000, 11_000_000, 12_000_000, 12_000_000, 14_000_000, 11_000_000],
		&"lap_times_usec": [50_000_000, 49_000_000],
		&"racecraft_metrics": {&"flow_uses": 2, &"flow_surges": 1},
		&"rewards": {&"cash": 800, &"reputation": 28},
		&"next_event_name": "PINE RIDGE ENDURO",
	}


func _classification() -> Array[Dictionary]:
	var riders: Array[Dictionary] = []
	for index: int in 8:
		var is_player := index == 1
		riders.append({
			&"rider_id": &"PLAYER" if is_player else StringName("RIVAL_%d" % index),
			&"display_name": "YOU" if is_player else "RIVAL %d" % index,
			&"number": 17 if is_player else 20 + index,
			&"position": index + 1,
			&"status": &"FINISHED",
			&"finish_usec": 98_000_000 + index * 1_000_000,
			&"effective_time_usec": 98_000_000 + index * 1_000_000,
			&"penalty_usec": 0,
			&"is_player": is_player,
		})
	return riders


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
