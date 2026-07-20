extends Node
## Deterministic contract for structured race reputation, repeat pacing, cash
## preservation, competitive multipliers, duplicate protection, and disclosure.

const REPUTATION_POLICY_SCRIPT := preload("res://features/race/race_reputation_policy.gd")
const PLAYER_PROFILE_SCRIPT := preload("res://common/player_profile.gd")
const HUD_SCENE := preload("res://features/hud/race_hud.tscn")
const BIKE_SCENE := preload("res://entities/bike/bike.tscn")
const GHOST_SCENE := preload("res://features/race/ghost_controller.tscn")
const RACE_SCENE := preload("res://features/race/race_controller.tscn")

var _failures := PackedStringArray()


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var first_gold := _evaluate(&"GOLD", 1, true, true, true, 1.0)
	var first_gold_repeat := _evaluate(&"GOLD", 1, true, true, true, 1.0)
	var silver := _evaluate(&"SILVER", 6, true, false, false, 1.0)
	var bronze := _evaluate(&"BRONZE", 6, true, false, false, 1.0)
	var finisher := _evaluate(&"FINISHER", 6, true, false, false, 1.0)
	var first_win := _evaluate(&"GOLD", 1, false, true, false, 1.0)
	var improved_repeat := _evaluate(&"BRONZE", 6, false, false, true, 1.0)
	var ordinary_repeat := _evaluate(&"GOLD", 1, false, false, false, 1.0)
	var maximum_first := _evaluate(&"GOLD", 1, true, true, true, 3.0)
	var maximum_repeat := _evaluate(&"GOLD", 1, false, false, false, 3.0)
	var lower_clamp := REPUTATION_POLICY_SCRIPT.evaluate({
		&"eligible": true, &"medal": &"GOLD", &"position": 1,
		&"repeat_factor": -10.0,
	})
	var upper_clamp := REPUTATION_POLICY_SCRIPT.evaluate({
		&"eligible": true, &"medal": &"GOLD", &"position": 1,
		&"repeat_factor": 10.0,
	})
	var ineligible := REPUTATION_POLICY_SCRIPT.evaluate({&"eligible": false, &"medal": &"GOLD", &"position": 1})

	_assert(int(first_gold.get(&"reputation", -1)) == 43, "first gold/win/PB is not 43 rep")
	_assert(int(silver.get(&"reputation", -1)) == 22, "silver base is not 22 rep")
	_assert(int(bronze.get(&"reputation", -1)) == 16, "bronze base is not 16 rep")
	_assert(int(finisher.get(&"reputation", -1)) == 8, "finisher base is not 8 rep")
	_assert(int(first_win.get(&"reputation", -1)) == 38 and not bool(first_win.get(&"repeat_limited", true)), "first win was repeat-limited")
	_assert(int(improved_repeat.get(&"reputation", -1)) == 21 and is_equal_approx(float(improved_repeat.get(&"repeat_factor", 0.0)), 1.0), "new best lost full reward or PB bonus")
	_assert(int(ordinary_repeat.get(&"reputation", -1)) == 13, "ordinary repeat is not the bounded 35% award")
	_assert(bool(ordinary_repeat.get(&"repeat_limited", false)) and is_equal_approx(float(ordinary_repeat.get(&"repeat_factor", 0.0)), 0.35), "repeat factor is not disclosed")
	_assert(float(lower_clamp.get(&"repeat_factor", 0.0)) == 0.25 and float(upper_clamp.get(&"repeat_factor", 0.0)) == 0.50, "repeat factor bounds are not enforced")
	_assert(first_gold == first_gold_repeat, "policy evaluation is not deterministic")
	_assert(int(maximum_first.get(&"reputation", -1)) == 129, "3x competitive multiplier was not preserved")
	_assert(int(maximum_first.get(&"reputation", 0)) < 170, "one maximum-multiplier race unlocks the 170-rep ladder")
	_assert(int(maximum_first.get(&"reputation", 0)) + int(maximum_repeat.get(&"reputation", 0)) == 169, "first plus repeated 3x race no longer follows bounded pacing")
	_assert(int(ineligible.get(&"reputation", -1)) == 0 and float(ineligible.get(&"repeat_factor", -1.0)) == 0.0, "ineligible result earned reputation")
	var controller_contract := await _run_controller_integration()
	_assert(bool(controller_contract.get(&"passed", false)), "RaceController did not project the pure policy or preserved cash values")

	var profile: Variant = PLAYER_PROFILE_SCRIPT.new()
	profile.persistence_enabled = false
	profile._apply_profile_dictionary({
		"cash": 0,
		"racer_reputation": 0,
		"current_setup": "BALANCED",
		"unlocked_setups": ["BALANCED"],
		"course_layout_version": profile.COURSE_LAYOUT_VERSION,
	})
	profile._ensure_full_race_defaults()
	var first_rewards := maximum_first.duplicate(true)
	# Existing cash math: (900 GOLD + 250 PB + 150 CLEAN + 350 WIN) * 3.
	first_rewards[&"cash"] = 4_950
	first_rewards[&"base_cash"] = 1_150
	first_rewards[&"clean_race_bonus"] = 150
	first_rewards[&"placement_bonus"] = 350
	first_rewards[&"multiplier"] = 3.0
	var first_result := _authorized_result(profile, _result(first_rewards))
	var first_summary: Dictionary = profile.record_race_result(first_result, true)
	_assert(bool(first_summary.get(&"accepted", false)), "first structured result was rejected")
	_assert(profile.cash == 4_950, "first clear changed established cash bonuses or multiplier")
	_assert(profile.racer_reputation == 129, "first structured result credited incorrect reputation")

	var repeat_rewards := maximum_repeat.duplicate(true)
	# Repeat limiting is reputation-only: (900 GOLD + 150 CLEAN + 350 WIN) * 3.
	repeat_rewards[&"cash"] = 4_200
	repeat_rewards[&"base_cash"] = 900
	repeat_rewards[&"clean_race_bonus"] = 150
	repeat_rewards[&"placement_bonus"] = 350
	repeat_rewards[&"multiplier"] = 3.0
	var repeat_result := _authorized_result(profile, _result(repeat_rewards))
	var repeat_summary: Dictionary = profile.record_race_result(repeat_result, true)
	_assert(bool(repeat_summary.get(&"accepted", false)), "repeat structured result was rejected")
	_assert(profile.cash == 9_150, "repeat factor leaked into cash rewards")
	_assert(profile.racer_reputation == 169, "repeat result did not credit the bounded reputation")
	var duplicate_summary: Dictionary = profile.record_race_result(repeat_result, true)
	_assert(bool(duplicate_summary.get(&"duplicate", false)), "duplicate run ID was accepted")
	_assert(profile.cash == 9_150 and profile.racer_reputation == 169, "duplicate result paid twice")

	var hud := HUD_SCENE.instantiate() as RaceHud
	add_child(hud)
	await get_tree().process_frame
	hud.show_results(repeat_result)
	var presentation := hud.get_academy_presentation_snapshot()
	_assert(str(presentation.get(&"results_stats", "")).contains("REPEAT RUN REP x0.35"), "repeat factor is absent from result presentation")

	var passed := _failures.is_empty()
	print("RACE REPUTATION PACING PROBE: first=%d silver=%d bronze=%d finisher=%d repeat=%d max_first=%d max_pair=%d controller=%s cash=%d profile_rep=%d disclosed=%s passed=%s failures=%s" % [
		int(first_gold.get(&"reputation", -1)), int(silver.get(&"reputation", -1)),
		int(bronze.get(&"reputation", -1)), int(finisher.get(&"reputation", -1)),
		int(ordinary_repeat.get(&"reputation", -1)), int(maximum_first.get(&"reputation", -1)),
		int(maximum_first.get(&"reputation", 0)) + int(maximum_repeat.get(&"reputation", 0)),
		str(controller_contract),
		profile.cash, profile.racer_reputation,
		str(str(presentation.get(&"results_stats", "")).contains("REPEAT RUN REP x0.35")),
		str(passed), ", ".join(_failures),
	])
	hud.queue_free()
	profile.free()
	get_tree().quit(0 if passed else 1)


func _run_controller_integration() -> Dictionary:
	Profile.persistence_enabled = false
	Profile.reset_profile_for_testing()
	var bike := BIKE_SCENE.instantiate() as DirtBikeController
	var ghost := GHOST_SCENE.instantiate() as GhostController
	var race := RACE_SCENE.instantiate() as RaceController
	add_child(bike)
	add_child(ghost)
	add_child(race)
	ghost.persistence_enabled = false
	await get_tree().process_frame
	var route := CourseCatalog.get_world_riding_points(CourseCatalog.QUARRY_ID)
	race.initialize(bike, ghost, CourseCatalog.QUARRY_ID, route, null)
	var config := RaceSessionConfig.from_dictionary({
		&"event_id": &"CIRCUIT",
		&"track_id": CourseCatalog.QUARRY_ID,
		&"display_name": "REPUTATION CONTROLLER PROBE",
		&"countdown_seconds": 0.10,
		&"staging_seconds": 0.0,
		&"finish_grace_seconds": 0.0,
		&"opponent_count": 0,
		&"field_size": 1,
		&"checkpoint_count": 2,
	})
	race.configure_session(config, route, null)
	var first_result := await _finish_controller_race(race, bike)
	var first_rewards := first_result.get(&"rewards", {}) as Dictionary
	# Seed the next run's first-clear/first-win context without paying this
	# projected result; duplicate/reward crediting is validated on a local profile.
	var first_settlement := _authorized_result(Profile, first_result)
	Profile.record_race_result(first_settlement, false)
	ghost.best_time_usec = 1
	var repeat_result := await _finish_controller_race(race, bike)
	var repeat_rewards := repeat_result.get(&"rewards", {}) as Dictionary
	var passed := (
		int(first_rewards.get(&"cash", -1)) == 1_650
		and int(first_rewards.get(&"reputation", -1)) == 43
		and is_equal_approx(float(first_rewards.get(&"repeat_factor", 0.0)), 1.0)
		and int(first_rewards.get(&"clean_race_bonus", -1)) == 150
		and int(first_rewards.get(&"placement_bonus", -1)) == 350
		and int(repeat_rewards.get(&"cash", -1)) == 1_400
		and int(repeat_rewards.get(&"reputation", -1)) == 13
		and bool(repeat_rewards.get(&"repeat_limited", false))
		and is_equal_approx(float(repeat_rewards.get(&"repeat_factor", 0.0)), 0.35)
	)
	race.queue_free()
	ghost.queue_free()
	bike.queue_free()
	return {
		&"first_cash": int(first_rewards.get(&"cash", -1)),
		&"first_reputation": int(first_rewards.get(&"reputation", -1)),
		&"repeat_cash": int(repeat_rewards.get(&"cash", -1)),
		&"repeat_reputation": int(repeat_rewards.get(&"reputation", -1)),
		&"repeat_factor": float(repeat_rewards.get(&"repeat_factor", 0.0)),
		&"passed": passed,
	}


func _finish_controller_race(race: RaceController, bike: DirtBikeController) -> Dictionary:
	race.reset_run()
	for _frame: int in 30:
		if race.state == RaceController.State.RACING:
			break
		await get_tree().physics_frame
	if race.state != RaceController.State.RACING:
		return {}
	var gates: Array[Area3D] = []
	for child: Node in race.get_children():
		if child is Area3D and child.name.begins_with("Checkpoint"):
			gates.append(child as Area3D)
	gates.sort_custom(func(first: Area3D, second: Area3D) -> bool: return String(first.name).naturalnocasecmp_to(String(second.name)) < 0)
	for gate: Area3D in gates:
		gate.body_entered.emit(bike)
	await get_tree().process_frame
	return race.get_results_preview()


func _evaluate(
	medal: StringName,
	position: int,
	is_first_clear: bool,
	is_first_win: bool,
	is_new_best: bool,
	competitive_multiplier: float
) -> Dictionary:
	return REPUTATION_POLICY_SCRIPT.evaluate({
		&"eligible": true,
		&"medal": medal,
		&"position": position,
		&"is_first_clear": is_first_clear,
		&"is_first_win": is_first_win,
		&"is_new_best": is_new_best,
		&"competitive_multiplier": competitive_multiplier,
	})


func _result(rewards: Dictionary) -> Dictionary:
	return {
		&"signature": "REPUTATION_POLICY|PROBE",
		&"event_id": &"CIRCUIT",
		&"valid": true,
		&"player_position": 1,
		&"player_time_usec": 90_000_000,
		&"player_penalty_usec": 0,
		&"medal": &"GOLD",
		&"rewards": rewards.duplicate(true),
		&"classification": [
			{&"rider_id": &"PLAYER", &"display_name": "YOU", &"is_player": true, &"position": 1, &"status": &"FINISHED", &"finish_usec": 90_000_000},
			{&"rider_id": &"ROOK", &"display_name": "ROOK", &"position": 2, &"status": &"FINISHED", &"finish_usec": 91_000_000},
		],
	}


func _authorized_result(profile: Variant, source_result: Dictionary) -> Dictionary:
	var result := source_result.duplicate(true)
	var event_id := StringName(result.get(&"event_id", &""))
	var signature := str(result.get(&"signature", ""))
	var authority: Dictionary = profile.begin_race_run(event_id, signature)
	_assert(bool(authority.get(&"accepted", false)), "Profile refused race authority for %s" % String(event_id))
	result[&"run_id"] = str(authority.get(&"run_id", ""))
	result[&"signature"] = str(authority.get(&"signature", signature))
	return result


func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
