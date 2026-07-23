extends Node
## Deterministic contract for authoritative career deltas and durable Results payoff.

const PAYOFF_SCRIPT := preload("res://features/career/progression_payoff.gd")
const HUD_SCENE := preload("res://features/hud/race_hud.tscn")

const FIRST_UNLOCK_IDS: Array[StringName] = [
	&"MESA_PRACTICE", &"MESA_QUALIFYING", &"MESA_HEAT", &"MESA_LCQ", &"MESA_MX",
	&"TORQUE_PIPE", &"WAVE_ROTOR", &"PROGRESSIVE_FORK",
]

var _failures: Array[String] = []
var _capture_requested: bool = false


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	Profile.persistence_enabled = false
	_capture_requested = &"--capture-progression-payoff" in OS.get_cmdline_user_args()
	var prior_input_mode := InputRouter.input_mode
	Profile.reset_profile_for_testing()
	var before := PAYOFF_SCRIPT.capture(Profile)
	var first_result := _authorize_race_result(
		_race_result("payoff-first-win", true, 1, 1_650, 43)
	)
	var first_summary: Dictionary = Profile.record_race_result(first_result, true)
	var first_payoff: Dictionary = PAYOFF_SCRIPT.diff(before, PAYOFF_SCRIPT.capture(Profile))
	first_payoff[&"accepted"] = bool(first_summary.get(&"accepted", false))
	first_payoff[&"duplicate"] = false
	first_payoff[&"valid"] = true
	first_payoff[&"status"] = &"FINISHED"
	_check(bool(first_summary.get(&"accepted", false)), "first classified result was rejected")
	_check(Profile.cash == 1_650 and Profile.racer_reputation == 43, "first payout did not settle exact balances")
	_check(_payoff_ids(first_payoff.get(&"unlocks", [])) == FIRST_UNLOCK_IDS, "first payoff unlock order or contents diverged")
	_check(
		_payoff_ids(first_payoff.get(&"milestones", [])) == [&"FIRST_FINISH", &"FIRST_WIN"],
		"first payoff omitted exact finish/win milestones"
	)
	_check(not _contains_kind(first_payoff, &"BIKE"), "43 racer rep announced a bike early")
	_check(not _payoff_ids(first_payoff.get(&"unlocks", [])).has(&"PINE_ENDURO"), "one Quarry clear announced Pine early")
	await _probe_results_presentation(first_result, first_payoff)

	var duplicate_before := PAYOFF_SCRIPT.capture(Profile)
	var duplicate_summary: Dictionary = Profile.record_race_result(first_result, true)
	var duplicate_payoff: Dictionary = PAYOFF_SCRIPT.diff(duplicate_before, PAYOFF_SCRIPT.capture(Profile))
	_check(bool(duplicate_summary.get(&"duplicate", false)), "duplicate result was not rejected by fingerprint")
	_check(
		_payoff_ids(duplicate_payoff.get(&"unlocks", [])).is_empty()
		and _payoff_ids(duplicate_payoff.get(&"milestones", [])).is_empty(),
		"duplicate result repeated a career unlock"
	)
	_check(Profile.cash == 1_650 and Profile.racer_reputation == 43, "duplicate result changed balances")

	Profile.reset_profile_for_testing()
	Profile.racer_reputation = 79
	Profile.race_statistics[&"holeshots"] = 4
	Profile.race_statistics[&"overtakes"] = 99
	Profile.race_statistics[&"laps_completed"] = 99
	var invalid_before := PAYOFF_SCRIPT.capture(Profile)
	var malicious_invalid := _authorize_race_result(
		_race_result("payoff-invalid", false, 1, 99_999, 999)
	)
	malicious_invalid[&"overtakes"] = 999
	var invalid_summary: Dictionary = Profile.record_race_result(malicious_invalid, true)
	var invalid_payoff: Dictionary = PAYOFF_SCRIPT.diff(invalid_before, PAYOFF_SCRIPT.capture(Profile))
	_check(bool(invalid_summary.get(&"accepted", false)), "invalid result did not enter the audit log")
	_check(Profile.racer_reputation == 79 and Profile.cash == 0, "invalid result changed economic state")
	_check(
		int(Profile.race_statistics.get(&"holeshots", 0)) == 4
		and int(Profile.race_statistics.get(&"overtakes", 0)) == 99
		and int(Profile.race_statistics.get(&"laps_completed", 0)) == 99,
		"invalid telemetry advanced achievement-bearing performance stats"
	)
	_check(
		not Profile.achievements.has(&"HOLESHOT_HERO")
		and not Profile.achievements.has(&"PASS_MASTER")
		and not Profile.achievements.has(&"CENTURY_LAPS"),
		"invalid telemetry permanently unlocked a performance milestone"
	)
	_check(
		_payoff_ids(invalid_payoff.get(&"unlocks", [])).is_empty()
		and _payoff_ids(invalid_payoff.get(&"milestones", [])).is_empty(),
		"invalid result fabricated progression"
	)

	Profile.reset_profile_for_testing()
	var sponsor_before := PAYOFF_SCRIPT.capture(Profile)
	_check(Profile.complete_contract("PAYOFF_DNF_CONTRACT", &"CIRCUIT"), "sponsor contract did not settle during the run")
	var sponsor_pre_settlement := PAYOFF_SCRIPT.capture(Profile)
	# A rejected final classification may not erase a contract that was already
	# awarded, nor may it expose later untrusted settlement mutations.
	Profile.racer_reputation += 100
	var sponsor_after_rejected_result := PAYOFF_SCRIPT.capture(Profile)
	var sponsor_payoff := PAYOFF_SCRIPT.resolve_run(
		sponsor_before, sponsor_pre_settlement, sponsor_after_rejected_result, false
	)
	_check(
		int(sponsor_payoff.get(&"cash_after", 0)) - int(sponsor_payoff.get(&"cash_before", 0)) == 350
		and int(sponsor_payoff.get(&"total_reputation_after", 0)) - int(sponsor_payoff.get(&"total_reputation_before", 0)) == 35,
		"rejected classification hid or inflated authoritative in-run earnings"
	)
	_check(bool(sponsor_payoff.get(&"run_earnings", false)), "authoritative sponsor earnings were not marked for Results")
	_check(not _payoff_ids(sponsor_payoff.get(&"unlocks", [])).is_empty(), "sponsor-earned access was hidden after a rejected finish")

	Profile.reset_profile_for_testing()
	Profile.racer_reputation = 5
	var academy_before := PAYOFF_SCRIPT.capture(Profile)
	var academy_evaluation: Dictionary = Profile.record_academy_result(
		&"CONTROL_BASICS", {&"gates_completed": 6.0, &"resets": 2.0}
	)
	var academy_payoff: Dictionary = PAYOFF_SCRIPT.diff(academy_before, PAYOFF_SCRIPT.capture(Profile))
	var academy_credit := academy_evaluation.get(&"credited_rewards", {}) as Dictionary
	_check(
		int(academy_credit.get(&"cash", 0)) == 500 and int(academy_credit.get(&"reputation", 0)) == 5,
		"Academy first pass did not credit its exact reward"
	)
	_check(
		_payoff_ids(academy_payoff.get(&"unlocks", [])) == [&"TORQUE_PIPE", &"GATE_DROP", &"BERM_LINES"],
		"Academy payoff did not expose the exact part and lesson access delta"
	)
	var academy_repeat_before := PAYOFF_SCRIPT.capture(Profile)
	var academy_repeat: Dictionary = Profile.record_academy_result(
		&"CONTROL_BASICS", {&"gates_completed": 10.0, &"resets": 0.0}
	)
	var academy_repeat_payoff := PAYOFF_SCRIPT.diff(academy_repeat_before, PAYOFF_SCRIPT.capture(Profile))
	_check(
		int((academy_repeat.get(&"credited_rewards", {}) as Dictionary).get(&"cash", -1)) == 0
		and _payoff_ids(academy_repeat_payoff.get(&"unlocks", [])).is_empty(),
		"Academy rematch repeated reward or unlock access"
	)

	Profile.reset_profile_for_testing()
	Profile.freestyler_reputation = 79
	var domain_before := PAYOFF_SCRIPT.capture(Profile)
	Profile.freestyler_reputation = 100
	var domain_payoff := PAYOFF_SCRIPT.diff(domain_before, PAYOFF_SCRIPT.capture(Profile))
	_check(
		_kind_ids(domain_payoff, &"EVENT") == [&"PINE_ENDURO", &"MESA_ELIMINATION", &"MESA_RHYTHM"],
		"total-reputation event access did not remain isolated and ordered"
	)
	_check(
		not _contains_kind(domain_payoff, &"BIKE")
		and not _contains_kind(domain_payoff, &"PART")
		and not _contains_kind(domain_payoff, &"ACADEMY_LESSON"),
		"freestyler reputation leaked into racer-only access"
	)

	Profile.reset_profile_for_testing()
	Profile.best_medal_ranks[&"CIRCUIT"] = 2
	_check(not Profile.is_activity_unlocked(&"PINE_ENDURO"), "one Quarry clear unlocked Pine")
	Profile.best_medal_ranks[&"FREESTYLE"] = 2
	_check(Profile.is_activity_unlocked(&"PINE_ENDURO"), "two Quarry clears did not satisfy Pine's profile gate")
	_check(
		RaceEventCatalog.is_available_to_profile(&"PINE_ENDURO", Profile),
		"two Quarry clears satisfied Profile but not the real Garage/catalog predicate"
	)

	InputRouter.call(&"_set_input_mode", prior_input_mode)
	if _failures.is_empty():
		print("PROGRESSION PAYOFF PROBE: PASS  //  first=8+2 duplicate=empty invalid=trusted sponsor=retained academy=3 domain=events-only pine=two-clears targets=next-event results=3x175%")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("PROGRESSION PAYOFF PROBE: " + failure)
	get_tree().quit(1)


func _probe_results_presentation(result: Dictionary, payoff: Dictionary) -> void:
	var hud := HUD_SCENE.instantiate() as RaceHud
	add_child(hud)
	await get_tree().process_frame
	hud.apply_accessibility({&"text_scale": 1.75, &"units": &"IMPERIAL"})
	var presented_result := result.duplicate(true)
	presented_result[&"classification"] = _classification(12)
	presented_result[&"player_position"] = 12
	presented_result[&"career_payoff"] = payoff.duplicate(true)
	presented_result[&"next_event_id"] = &"MESA_MX"
	presented_result[&"next_event_name"] = "RED MESA MX MAIN"
	presented_result[&"next_event_format"] = &"CIRCUIT"
	presented_result[&"next_event_laps"] = 3
	presented_result[&"next_event_medal_times_usec"] = CourseCatalog.get_medal_times_usec(CourseCatalog.MESA_MX_ID)
	hud.show_results(presented_result)
	for mode: StringName in [
		InputRouter.INPUT_MODE_KEYBOARD_MOUSE,
		InputRouter.INPUT_MODE_GAMEPAD,
		InputRouter.INPUT_MODE_TOUCH,
	]:
		InputRouter.call(&"_set_input_mode", mode)
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame
		var snapshot := hud.get_results_navigation_snapshot()
		var panel_rect := snapshot.get(&"panel_rect", Rect2()) as Rect2
		var viewport_rect := snapshot.get(&"viewport_rect", Rect2()) as Rect2
		var payoff_rect := snapshot.get(&"payoff_rect", Rect2()) as Rect2
		var classification_rect := snapshot.get(&"classification_rect", Rect2()) as Rect2
		_check(bool(snapshot.get(&"content_fits", false)), "Results content clipped at 175%% in %s mode" % mode)
		_check(viewport_rect.grow(1.0).encloses(panel_rect), "Results card escaped viewport in %s mode" % mode)
		_check(panel_rect.grow(1.0).encloses(payoff_rect) and payoff_rect.has_area(), "career payoff escaped Results card in %s mode" % mode)
		_check(panel_rect.grow(1.0).encloses(classification_rect) and classification_rect.has_area(), "classification lost its viewport in %s mode" % mode)
		_check(bool(snapshot.get(&"horizontal_scroll_disabled", false)), "Results enabled horizontal scrolling in %s mode" % mode)
		_check(int(snapshot.get(&"player_index", -1)) == 11 and bool(snapshot.get(&"selected_visible", false)), "P12 was not selected and visible in %s mode" % mode)
		_check(float(snapshot.get(&"maximum_scroll", 0.0)) > 0.0, "classification lost vertical scroll range in %s mode" % mode)
		_check(str(snapshot.get(&"payout_text", "")).contains("+$1650") and str(snapshot.get(&"payout_text", "")).contains("REP 43"), "Results omitted exact payout and balance in %s mode" % mode)
		_check(str(snapshot.get(&"career_text", "")).contains("MESA OPEN PRACTICE") and str(snapshot.get(&"career_text", "")).contains("+7 MORE IN GARAGE"), "Results did not summarize the full unlock cluster in %s mode" % mode)
		_check(
			str(snapshot.get(&"goal_text", "")).contains("RED MESA MX MAIN")
			and str(snapshot.get(&"goal_text", "")).contains("BRONZE TARGET")
			and str(snapshot.get(&"goal_text", "")).contains("05:30.000"),
			"Results reused the completed course target in %s mode" % mode
		)
		for line_fit: Dictionary in snapshot.get(&"line_fit", []) as Array:
			if not bool(line_fit.get(&"visible", false)):
				continue
			_check(not bool(line_fit.get(&"clip_text", true)), "Results label %s clips in %s mode" % [line_fit.get(&"name", ""), mode])
			_check(
				int(line_fit.get(&"visible_line_count", 0)) >= int(line_fit.get(&"line_count", 0)),
				"Results label %s hides lines in %s mode" % [line_fit.get(&"name", ""), mode]
			)
		if mode == InputRouter.INPUT_MODE_TOUCH:
			var footer := str(hud.get_competition_presentation_snapshot().get(&"footer", ""))
			_check(footer.contains("USE THE RESULTS BUTTONS BELOW") and not footer.contains("TOUCH"), "touch Results footer exposed a generic TOUCH prompt")
		if _capture_requested and mode in [InputRouter.INPUT_MODE_KEYBOARD_MOUSE, InputRouter.INPUT_MODE_TOUCH]:
			await _capture_results_frame(mode)

	var run_earnings_payoff := {
		&"accepted": false,
		&"duplicate": false,
		&"valid": true,
		&"status": &"DNF",
		&"run_earnings": true,
		&"cash_before": 0,
		&"cash_after": 350,
		&"total_reputation_before": 0,
		&"total_reputation_after": 35,
		&"unlocks": [{&"id": &"MESA_PRACTICE", &"display_name": "MESA OPEN PRACTICE"}],
		&"milestones": [],
		&"next_goal": {},
	}
	var dnf_result := presented_result.duplicate(true)
	dnf_result[&"run_id"] = "payoff-sponsor-dnf"
	dnf_result[&"career_payoff"] = run_earnings_payoff
	_set_player_status(dnf_result, &"DNF")
	hud.show_results(dnf_result)
	await _wait_layout_frames()
	var dnf_snapshot := hud.get_results_navigation_snapshot()
	_check(
		str(dnf_snapshot.get(&"payout_text", "")).contains("+$350")
		and not str(dnf_snapshot.get(&"payout_text", "")).contains("NO SETTLEMENT")
		and str(dnf_snapshot.get(&"career_text", "")).contains("MESA OPEN PRACTICE"),
		"DNF Results hid authoritative in-run sponsor earnings"
	)

	var eliminated_result := presented_result.duplicate(true)
	eliminated_result[&"run_id"] = "payoff-eliminated"
	eliminated_result[&"career_payoff"] = {
		&"accepted": false, &"duplicate": false, &"valid": true, &"status": &"ELIMINATED",
		&"run_earnings": false, &"cash_before": 350, &"cash_after": 350,
		&"total_reputation_before": 35, &"total_reputation_after": 35,
		&"unlocks": [], &"milestones": [], &"next_goal": {},
	}
	_set_player_status(eliminated_result, &"ELIMINATED")
	hud.show_results(eliminated_result)
	await _wait_layout_frames()
	var eliminated_goal := str(hud.get_results_navigation_snapshot().get(&"goal_text", ""))
	_check(eliminated_goal.contains("SURVIVE THE NEXT LAP"), "elimination Results advertised an unreachable clean-finish goal")
	hud.queue_free()
	await get_tree().process_frame


func _set_player_status(result: Dictionary, status: StringName) -> void:
	var classification := (result.get(&"classification", []) as Array).duplicate(true)
	for index: int in classification.size():
		if not classification[index] is Dictionary:
			continue
		var row := (classification[index] as Dictionary).duplicate(true)
		if bool(row.get(&"is_player", false)) or StringName(row.get(&"rider_id", &"")) == &"PLAYER":
			row[&"status"] = status
			row[&"finished"] = status in [&"FINISHED", &"CLASSIFIED"]
			classification[index] = row
			break
	result[&"classification"] = classification


func _wait_layout_frames() -> void:
	for _frame: int in 4:
		await get_tree().process_frame


func _capture_results_frame(mode: StringName) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var dimensions := image.get_size()
	var mode_slug := String(mode).to_lower()
	var path := "res://artifacts/riding-dirty-progression-results-%dx%d-%s.png" % [
		dimensions.x, dimensions.y, mode_slug,
	]
	var error := image.save_png(ProjectSettings.globalize_path(path))
	_check(error == OK, "could not save progression Results capture %s" % path)
	if error == OK:
		print("PROGRESSION PAYOFF CAPTURE: %s" % path)


func _race_result(run_id: String, valid: bool, position: int, cash_reward: int, reputation_reward: int) -> Dictionary:
	return {
		&"run_id": run_id,
		&"signature": "%s-signature" % run_id,
		&"event_id": &"CIRCUIT",
		&"valid": valid,
		&"medal": &"GOLD" if valid else &"NO_AWARD",
		&"classification": _classification(position),
		&"player_position": position,
		&"player_time_usec": 200_000_000,
		&"player_penalty_usec": 0,
		&"lap_times_usec": [200_000_000],
		&"holeshot_rider_id": &"PLAYER",
		&"rewards": {&"cash": cash_reward, &"reputation": reputation_reward},
	}


func _authorize_race_result(result: Dictionary) -> Dictionary:
	var authorized := result.duplicate(true)
	var event_id := StringName(authorized.get(&"event_id", &""))
	var run := Profile.begin_race_run(event_id, str(authorized.get(&"signature", "")))
	_check(bool(run.get(&"accepted", false)), "%s race authority was rejected" % String(event_id))
	authorized[&"run_id"] = str(run.get(&"run_id", ""))
	authorized[&"signature"] = str(run.get(&"signature", ""))
	return authorized


func _classification(player_position: int) -> Array[Dictionary]:
	var riders: Array[Dictionary] = []
	for index: int in 12:
		var position := index + 1
		var is_player := position == player_position
		riders.append({
			&"rider_id": &"PLAYER" if is_player else StringName("RIDER_%02d" % position),
			&"display_name": "YOU" if is_player else "RIDER %02d" % position,
			&"position": position,
			&"status": &"FINISHED",
			&"finish_usec": 200_000_000 + index * 1_000_000,
			&"effective_time_usec": 200_000_000 + index * 1_000_000,
			&"penalty_usec": 0,
			&"is_player": is_player,
		})
	return riders


func _kind_ids(payoff: Dictionary, kind: StringName) -> Array[StringName]:
	var output: Array[StringName] = []
	for item: Dictionary in payoff.get(&"unlocks", []) as Array:
		if StringName(item.get(&"kind", &"")) == kind:
			output.append(StringName(item.get(&"id", &"")))
	return output


func _contains_kind(payoff: Dictionary, kind: StringName) -> bool:
	return not _kind_ids(payoff, kind).is_empty()


func _payoff_ids(raw: Variant) -> Array[StringName]:
	var output: Array[StringName] = []
	if raw is Array:
		for value: Variant in raw:
			if value is Dictionary:
				output.append(StringName((value as Dictionary).get(&"id", &"")))
	return output


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
