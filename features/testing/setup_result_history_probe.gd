extends Node
## Exact setup/result history must be bounded, durable, and safe to reapply.

const PLAYER_PROFILE_SCRIPT := preload("res://common/player_profile.gd")

var _failures := PackedStringArray()


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var profile: Variant = PLAYER_PROFILE_SCRIPT.new()
	profile.persistence_enabled = false
	profile.reset_profile_for_testing()
	profile.unlocked_setups.append(&"ATTACK")

	# Exercise eviction as well as serialization. Keep the fastest ATTACK run inside
	# the retained window and finish with an intentionally slower reference run.
	var times := [
		150_000_000, 148_000_000, 146_000_000, 144_000_000,
		142_000_000, 138_000_000, 134_000_000, 130_000_000,
		126_000_000, 122_000_000, 118_000_000, 110_000_000,
		145_000_000, 140_000_000,
	]
	var personal_best_index := 11
	for index: int in times.size():
		var setup_id: StringName = &"ATTACK" if index == personal_best_index else &"BALANCED"
		var tune_value := 0.7 if index == personal_best_index else float(index) * 0.05
		var plan := _plan(setup_id, tune_value, {&"TIRES": &"HARDPACK_TIRES"} if index == personal_best_index else {})
		var run: Dictionary = profile.begin_race_run(&"CIRCUIT", "SETUP_HISTORY_%d" % index)
		var result := _result(run, times[index], index + 1, plan)
		var receipt: Dictionary = profile.record_race_result(result, false)
		_assert(bool(receipt.get(&"accepted", false)), "history result %d was not accepted" % index)

	var history: Dictionary = profile.get_event_run_history_snapshot(&"CIRCUIT")
	var recent: Array = history.get(&"recent_runs", []) as Array
	var previous: Dictionary = history.get(&"previous_run", {}) as Dictionary
	var personal_best: Dictionary = history.get(&"personal_best_run", {}) as Dictionary
	var previous_plan: Dictionary = previous.get(&"plan", {}) as Dictionary
	var pb_plan: Dictionary = personal_best.get(&"plan", {}) as Dictionary
	_assert(recent.size() == profile.MAX_EVENT_RUN_HISTORY, "event run history did not enforce its exact capacity")
	_assert(
		int(previous.get(&"effective_time_usec", -1)) == 140_000_000
		and StringName(previous_plan.get(&"setup_id", &"")) == &"BALANCED",
		"previous-run history did not retain the latest exact plan"
	)
	_assert(
		int(personal_best.get(&"effective_time_usec", -1)) == 110_000_000
		and StringName(pb_plan.get(&"setup_id", &"")) == &"ATTACK"
		and StringName((pb_plan.get(&"installed_parts", {}) as Dictionary).get(&"TIRES", &"")) == &"HARDPACK_TIRES"
		and int(personal_best.get(&"flow_uses", -1)) == personal_best_index + 1
		and (personal_best.get(&"sector_times_usec", []) as Array).size() == 2,
		"personal-best history did not retain the fastest plan and run evidence"
	)
	var pin_receipt: Dictionary = profile.pin_event_run_reference(
		&"CIRCUIT", &"", str(previous.get(&"result_id", ""))
	)
	history = profile.get_event_run_history_snapshot(&"CIRCUIT")
	var pinned := history.get(&"pinned_run", {}) as Dictionary
	_assert(
		bool(pin_receipt.get(&"accepted", false))
		and int(pinned.get(&"effective_time_usec", -1)) == 140_000_000
		and str(pinned.get(&"result_id", "")) == str(previous.get(&"result_id", "")),
		"latest official result could not become a durable custom reference"
	)
	var before_missing_pin: Dictionary = profile._profile_to_dictionary()
	var missing_pin: Dictionary = profile.pin_event_run_reference(&"CIRCUIT", &"", "fabricated-result")
	_assert(
		not bool(missing_pin.get(&"accepted", true))
		and profile._profile_to_dictionary() == before_missing_pin,
		"fabricated pinned reference was not refused without mutation"
	)

	var decoded: Variant = JSON.parse_string(JSON.stringify(profile._profile_to_dictionary()))
	var restored: Variant = PLAYER_PROFILE_SCRIPT.new()
	restored.persistence_enabled = false
	if decoded is Dictionary:
		restored._apply_profile_dictionary(decoded)
	else:
		_assert(false, "setup history profile did not survive JSON encoding")
	var restored_history: Dictionary = restored.get_event_run_history_snapshot(&"CIRCUIT")
	_assert(
		(restored_history.get(&"recent_runs", []) as Array).size() == profile.MAX_EVENT_RUN_HISTORY
		and int((restored_history.get(&"personal_best_run", {}) as Dictionary).get(&"effective_time_usec", -1)) == 110_000_000
		and int((restored_history.get(&"pinned_run", {}) as Dictionary).get(&"effective_time_usec", -1)) == 140_000_000,
		"setup history did not survive profile serialization"
	)

	# Historical plans restore strategy, never wear or distance.
	restored.unlocked_setups.append(&"ATTACK")
	restored.owned_part_ids.append(&"HARDPACK_TIRES")
	var live_build: Dictionary = restored.get_bike_build_snapshot(&"TYKE_125")
	live_build[&"condition"] = 0.42
	live_build[&"odometer_meters"] = 777.0
	restored.owned_bike_builds[&"TYKE_125"] = live_build
	restored.bike_condition = 42
	var apply_receipt: Dictionary = restored.apply_recorded_race_plan(
		(restored_history.get(&"personal_best_run", {}) as Dictionary).get(&"plan", {})
	)
	var applied_build: Dictionary = restored.get_bike_build_snapshot(&"TYKE_125")
	_assert(
		bool(apply_receipt.get(&"accepted", false))
		and restored.current_setup == &"ATTACK"
		and StringName((applied_build.get(&"installed_parts", {}) as Dictionary).get(&"TIRES", &"")) == &"HARDPACK_TIRES"
		and is_equal_approx(float(applied_build.get(&"condition", -1.0)), 0.42)
		and is_equal_approx(float(applied_build.get(&"odometer_meters", -1.0)), 777.0)
		and restored.bike_condition == 42,
		"applying a PB plan did not restore strategy while preserving live wear and distance"
	)

	var unavailable_plan := pb_plan.duplicate(true)
	unavailable_plan[&"installed_parts"] = {&"ENGINE": &"RACE_ECU"}
	var before_refusal: Dictionary = restored._profile_to_dictionary()
	var refused: Dictionary = restored.apply_recorded_race_plan(unavailable_plan)
	_assert(
		not bool(refused.get(&"accepted", true))
		and StringName(refused.get(&"reason", &"")) == &"PART_UNAVAILABLE"
		and restored._profile_to_dictionary() == before_refusal,
		"unavailable historical equipment was not refused atomically"
	)

	var passed := _failures.is_empty()
	print("SETUP RESULT HISTORY PROBE: capacity=%d previous=%d pb=%d pinned=%d apply=%s wear=%.2f distance=%.1f passed=%s failures=%s" % [
		profile.MAX_EVENT_RUN_HISTORY,
		int(previous.get(&"effective_time_usec", -1)),
		int(personal_best.get(&"effective_time_usec", -1)),
		int(pinned.get(&"effective_time_usec", -1)),
		str(bool(apply_receipt.get(&"accepted", false))),
		float(applied_build.get(&"condition", -1.0)),
		float(applied_build.get(&"odometer_meters", -1.0)),
		str(passed),
		", ".join(_failures),
	])
	profile.free()
	restored.free()
	get_tree().quit(0 if passed else 1)


func _plan(setup_id: StringName, tune_value: float, parts: Dictionary) -> Dictionary:
	return {
		&"version": 1,
		&"setup_id": setup_id,
		&"bike_id": &"TYKE_125",
		&"selected_class": &"LITE_125",
		&"installed_parts": parts.duplicate(true),
		&"tune": {
			&"gearing": tune_value,
			&"tire_grip": tune_value,
			&"suspension_stiffness": tune_value,
			&"suspension_damping": tune_value,
			&"preload": tune_value,
			&"brake_bias": tune_value,
		},
		&"livery_id": &"FACTORY",
		&"condition_percent": 100,
		&"build_signature": "TYKE_125|SETUP_HISTORY",
		&"assist_mode": &"SPORT",
		&"assist_signature": "SPORT|SETUP_HISTORY",
		&"difficulty": 1,
		&"transmission_mode": &"AUTOMATIC",
		&"control_signature": "SETUP_HISTORY",
		&"crash_support_mode": &"STANDARD",
		&"weather": &"CLEAR",
		&"surface": &"PACKED",
	}


func _result(run: Dictionary, time_usec: int, sequence: int, plan: Dictionary) -> Dictionary:
	return {
		&"run_id": str(run.get(&"run_id", "")),
		&"signature": str(run.get(&"signature", "")),
		&"event_id": &"CIRCUIT",
		&"valid": true,
		&"player_position": clampi(sequence, 1, 8),
		&"player_time_usec": time_usec,
		&"player_penalty_usec": 0,
		&"medal": &"GOLD" if time_usec <= 110_000_000 else &"SILVER",
		&"rewards": {&"cash": 0, &"reputation": 0},
		&"lap_times_usec": [time_usec],
		&"sector_times_usec": [time_usec / 2, time_usec - (time_usec / 2)],
		&"crashes": sequence % 2,
		&"contacts": sequence % 3,
		&"reset_count": 0,
		&"racecraft_metrics": {&"flow_uses": sequence},
		&"run_plan": plan.duplicate(true),
		&"classification": [{
			&"rider_id": &"PLAYER",
			&"display_name": "YOU",
			&"is_player": true,
			&"position": clampi(sequence, 1, 8),
			&"status": &"FINISHED",
		}],
	}


func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
