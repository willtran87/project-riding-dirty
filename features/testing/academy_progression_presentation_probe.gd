extends Node
## Deterministic Academy contract: selection, grading, rematches, Garage, and HUD.

const ACADEMY_CATALOG_SCRIPT := preload("res://features/career/academy_lesson_catalog.gd")
const GARAGE_UI_SCRIPT := preload("res://features/garage/garage_ui.gd")
const HUD_SCENE := preload("res://features/hud/race_hud.tscn")
const RIDE_DIRECTOR_SCRIPT := preload("res://features/ride/ride_director.gd")
const LESSON_ORDER: Array[StringName] = [
	&"CONTROL_BASICS",
	&"GATE_DROP",
	&"BERM_LINES",
	&"PRELOAD_LANDING",
	&"RHYTHM_CHOICES",
	&"AIR_CONTROL",
	&"SAFE_RECOVERY",
	&"PASSING_RACECRAFT",
]
const EXPECTED_COACH_TOKENS: Dictionary = {
	&"CONTROL_BASICS": ["{THROTTLE}", "{STEER}", "{BRAKE}", "{RESET}"],
	&"GATE_DROP": ["{THROTTLE}", "{BRAKE}"],
	&"BERM_LINES": ["{STEER}", "{BRAKE}", "{THROTTLE}"],
	&"PRELOAD_LANDING": ["{PRELOAD}", "{LEAN_STEER}", "{TECHNIQUE}"],
	&"RHYTHM_CHOICES": ["{STEER}", "{TECHNIQUE}", "{LEAN}"],
	&"AIR_CONTROL": ["{LEAN_FORWARD}", "{FLOW}"],
	&"SAFE_RECOVERY": ["{BRAKE}", "{TECHNIQUE}", "{STEER}", "{THROTTLE}", "{RESET}"],
	&"PASSING_RACECRAFT": ["{STEER}", "{THROTTLE}", "{BRAKE}"],
}
const EXPECTED_COACH_ACTIONS: Dictionary = {
	&"CONTROL_BASICS": [&"throttle", &"steer_left", &"steer_right", &"brake", &"reset_bike"],
	&"GATE_DROP": [&"throttle", &"brake"],
	&"BERM_LINES": [&"steer_left", &"steer_right", &"brake", &"throttle"],
	&"PRELOAD_LANDING": [&"preload", &"lean_forward", &"lean_back", &"steer_left", &"steer_right", &"racecraft_technique"],
	&"RHYTHM_CHOICES": [&"steer_left", &"steer_right", &"racecraft_technique", &"lean_forward", &"lean_back"],
	&"AIR_CONTROL": [&"lean_forward", &"flow_boost"],
	&"SAFE_RECOVERY": [&"brake", &"racecraft_technique", &"steer_left", &"steer_right", &"throttle", &"reset_bike"],
	&"PASSING_RACECRAFT": [&"steer_left", &"steer_right", &"throttle", &"brake"],
}
const EXPECTED_RACECRAFT_FOCUS: Dictionary = {
	&"CONTROL_BASICS": &"NONE",
	&"GATE_DROP": &"NONE",
	&"BERM_LINES": &"CORNERING",
	&"PRELOAD_LANDING": &"JUMPING",
	&"RHYTHM_CHOICES": &"FAST_LINE",
	&"AIR_CONTROL": &"AIR_FLOW",
	&"SAFE_RECOVERY": &"RECOVERY",
	&"PASSING_RACECRAFT": &"PASSING",
}

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	Profile.persistence_enabled = false
	_probe_first_run_completion_contract()
	_probe_bronze_silver_gold_advancement()
	_probe_all_lessons_advance()
	_probe_academy_coach_catalog()
	_probe_explicit_rematch_authority()
	await _probe_live_and_result_presentation()
	RaceEventCatalog.clear_academy_lesson_override()
	if _failures.is_empty():
		print("ACADEMY PROGRESSION PRESENTATION PROBE: PASS  //  onboarding=failed+invalid+dnf+pass+skip grades=3 lessons=8 rematch=true garage=true hud_objectives=2 coach=8x3 focus=8 recovery=coached+zero-time ordinary_overlays=true rebind=true scale=1.75")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("ACADEMY PROGRESSION PRESENTATION PROBE: " + failure)
	get_tree().quit(1)


func _probe_first_run_completion_contract() -> void:
	# Main records the structured route result before it submits Academy metrics.
	# Reproduce that public ordering so a route finish cannot mask a zero-star lesson.
	_reset_profile()
	var zero_star_route := Profile.record_race_result(
		_first_run_result(&"ACADEMY", &"FINISHED", true, "academy-zero-star-route"), true
	)
	_check(bool(zero_star_route.get(&"accepted", false)), "zero-star Academy route result was not accepted")
	var zero_star_route_rewards := zero_star_route.get(&"rewards_granted", {}) as Dictionary
	var zero_star_event_record := Profile.get_event_record(&"ACADEMY")
	_check(
		int(zero_star_route_rewards.get(&"cash", -1)) == 0
			and int(zero_star_route_rewards.get(&"reputation", -1)) == 0,
		"zero-star Academy route received the generic race reward"
	)
	_check(Profile.cash == 0 and Profile.racer_reputation == 1_000, "zero-star Academy route changed progression currency")
	_check(
		int(zero_star_event_record.get(&"starts", 0)) == 1
			and int(zero_star_event_record.get(&"finishes", 0)) == 1,
		"Academy reward isolation discarded intentional route telemetry"
	)
	_check(
		Profile.get_event_medal(&"ACADEMY") == &"UNRIDDEN"
			and not Profile.has_completed_event(&"ACADEMY"),
		"zero-star Academy route appeared cleared in the Garage projection"
	)
	_check(Profile.is_first_run_onboarding_active(), "finishing the Academy route completed onboarding before grading")
	var zero_star := Profile.record_academy_result(
		&"CONTROL_BASICS", {&"gates_completed": 5, &"resets": 3}
	)
	_check(not bool(zero_star.get(&"passed", true)) and int(zero_star.get(&"stars", -1)) == 0, "failed Academy metrics did not produce zero stars")
	_check(not bool(zero_star.get(&"first_completion", true)), "zero-star Academy result claimed first completion")
	_check(Profile.get_event_medal(&"ACADEMY") == &"UNRIDDEN", "zero-star Academy grade produced a visible medal")
	Profile.best_medal_ranks[&"ACADEMY"] = 4
	_check(Profile.get_event_medal(&"ACADEMY") == &"UNRIDDEN", "legacy Academy time medal overrode the lesson-star projection")
	_check(Profile.is_first_run_onboarding_active(), "zero-star Academy result dismissed first-run guidance")
	_check(RaceEventCatalog.get_recommended_event() == &"ACADEMY", "zero-star Academy result stopped recommending the lesson")

	_reset_profile()
	var invalid_academy := Profile.record_race_result(
		_first_run_result(&"ACADEMY", &"FINISHED", false, "academy-invalid-dsq"), true
	)
	_check(bool(invalid_academy.get(&"accepted", false)), "invalid Academy result was not recorded")
	_check(StringName(invalid_academy.get(&"status", &"")) == &"DSQ", "invalid Academy finish was not normalized to DSQ")
	_check(Profile.cash == 0 and Profile.racer_reputation == 1_000, "invalid/DSQ Academy result changed progression currency")
	_check(Profile.get_event_medal(&"ACADEMY") == &"UNRIDDEN", "invalid/DSQ Academy result appeared cleared")
	_check(Profile.is_first_run_onboarding_active(), "invalid/DSQ Academy result dismissed first-run guidance")
	_check(RaceEventCatalog.get_recommended_event() == &"ACADEMY", "invalid/DSQ Academy result stopped recommending the lesson")

	_reset_profile()
	var dnf_race := Profile.record_race_result(
		_first_run_result(&"CIRCUIT", &"DNF", true, "circuit-first-run-dnf"), true
	)
	_check(bool(dnf_race.get(&"accepted", false)) and StringName(dnf_race.get(&"status", &"")) == &"DNF", "non-Academy DNF was not recorded")
	_check(Profile.cash == 0 and Profile.racer_reputation == 1_000, "non-Academy DNF received a finish reward")
	_check(Profile.is_first_run_onboarding_active(), "non-Academy DNF dismissed first-run guidance")
	_check(RaceEventCatalog.get_recommended_event() == &"ACADEMY", "non-Academy DNF stopped recommending Academy")

	_reset_profile()
	var academy_route := Profile.record_race_result(
		_first_run_result(&"ACADEMY", &"CLASSIFIED", true, "academy-first-pass-route"), true
	)
	_check(bool(academy_route.get(&"accepted", false)), "successful Academy route result was not accepted")
	var academy_route_rewards := academy_route.get(&"rewards_granted", {}) as Dictionary
	_check(
		int(academy_route_rewards.get(&"cash", -1)) == 0
			and int(academy_route_rewards.get(&"reputation", -1)) == 0,
		"successful Academy route received a generic reward before lesson grading"
	)
	_check(Profile.cash == 0 and Profile.racer_reputation == 1_000, "Academy route settlement stacked progression before grading")
	_check(Profile.is_first_run_onboarding_active(), "Academy route result bypassed lesson grading")
	var catalog: Variant = ACADEMY_CATALOG_SCRIPT.create_default()
	var lesson: Dictionary = catalog.get_lesson(&"CONTROL_BASICS")
	var first_pass := Profile.record_academy_result(
		&"CONTROL_BASICS", _metrics_for_grade(lesson, 1)
	)
	var repeated_pass := Profile.record_academy_result(
		&"CONTROL_BASICS", _metrics_for_grade(lesson, 1)
	)
	var first_credit := first_pass.get(&"credited_rewards", {}) as Dictionary
	var repeated_credit := repeated_pass.get(&"credited_rewards", {}) as Dictionary
	_check(bool(first_pass.get(&"passed", false)) and int(first_pass.get(&"stars", 0)) == 1, "bronze Academy pass did not meet onboarding authority")
	_check(bool(first_pass.get(&"first_completion", false)), "first successful Academy grade did not complete onboarding")
	_check(not Profile.is_first_run_onboarding_active(), "successful Academy grade left onboarding active")
	_check(
		Profile.get_event_medal(&"ACADEMY") == &"BRONZE"
			and Profile.has_completed_event(&"ACADEMY"),
		"successful Academy grade did not become the visible completion authority"
	)
	_check(int(first_credit.get(&"cash", 0)) == 500 and int(first_credit.get(&"reputation", 0)) == 5, "first Academy completion did not issue its exact lesson reward")
	_check(Profile.cash == 500 and Profile.racer_reputation == 1_005, "successful Academy settlement stacked or omitted rewards")
	_check(not bool(repeated_pass.get(&"first_completion", true)), "repeated Academy pass completed onboarding twice")
	_check(int(repeated_credit.get(&"cash", -1)) == 0 and int(repeated_credit.get(&"reputation", -1)) == 0, "repeated Academy pass duplicated completion rewards")
	_check(not Profile.complete_first_run_onboarding(), "completed Academy onboarding remained completable")

	for finish_status: StringName in [&"FINISHED", &"CLASSIFIED"]:
		_reset_profile()
		var implicit_skip := Profile.record_race_result(
			_first_run_result(
				&"CIRCUIT", finish_status, true,
				"circuit-implicit-skip-%s" % String(finish_status).to_lower()
			)
		)
		_check(bool(implicit_skip.get(&"accepted", false)), "%s non-Academy implicit skip was not accepted" % String(finish_status))
		_check(not Profile.is_first_run_onboarding_active(), "%s non-Academy finish did not complete the implicit skip" % String(finish_status))

	# Completed open activities are an intentional opt-out route and must remain
	# distinct from failed structured race results.
	_reset_profile()
	var freestyle_run: Dictionary = Profile.begin_activity_run(&"FREESTYLE")
	var freestyle_settlement: Dictionary = Profile.record_activity_result({
		&"activity_id": &"FREESTYLE",
		&"run_id": str(freestyle_run.get(&"run_id", "")),
		&"result_value": 1_000,
	})
	_check(bool(freestyle_settlement.get(&"accepted", false)), "completed Freestyle implicit skip was not durably settled")
	_check(not Profile.is_first_run_onboarding_active(), "completed Freestyle no longer provides the intentional implicit skip")


func _first_run_result(
	event_id: StringName,
	status: StringName,
	valid: bool,
	run_id: String
) -> Dictionary:
	var result := {
		&"run_id": run_id,
		&"signature": "%s|FIRST_RUN_PROBE" % String(event_id),
		&"event_id": event_id,
		&"valid": valid,
		&"player_position": 1,
		&"player_time_usec": 75_000_000,
		&"player_penalty_usec": 0,
		&"medal": &"BRONZE",
		&"rewards": {&"cash": 900, &"reputation": 30},
		&"classification": [{
			&"rider_id": &"PLAYER",
			&"display_name": "YOU",
			&"is_player": true,
			&"position": 1,
			&"status": status,
		}],
	}
	if event_id == &"ACADEMY":
		result[&"academy_lesson_id"] = &"CONTROL_BASICS"
	return _authorize_race_result(result)


func _authorize_race_result(result: Dictionary) -> Dictionary:
	var authorized := result.duplicate(true)
	var event_id := StringName(authorized.get(&"event_id", &""))
	var settlement_context: Dictionary = {}
	if event_id == &"ACADEMY":
		settlement_context[&"academy_lesson_id"] = StringName(
			authorized.get(&"academy_lesson_id", &"")
		)
	var run := Profile.begin_race_run(
		event_id, str(authorized.get(&"signature", "")), settlement_context
	)
	_check(bool(run.get(&"accepted", false)), "%s race authority was rejected" % String(event_id))
	authorized[&"run_id"] = str(run.get(&"run_id", ""))
	authorized[&"signature"] = str(run.get(&"signature", ""))
	if event_id == &"ACADEMY":
		authorized[&"academy_lesson_id"] = StringName(run.get(&"academy_lesson_id", &""))
	return authorized


func _probe_bronze_silver_gold_advancement() -> void:
	var catalog: Variant = ACADEMY_CATALOG_SCRIPT.create_default()
	var lesson: Dictionary = catalog.get_lesson(&"CONTROL_BASICS")
	for grade: int in range(1, 4):
		_reset_profile()
		_check_authority(&"CONTROL_BASICS", &"NEXT", "grade %d preflight" % grade)
		var evaluation := Profile.record_academy_result(
			&"CONTROL_BASICS", _metrics_for_grade(lesson, grade)
		)
		_check(int(evaluation.get(&"stars", 0)) == grade, "grade %d did not produce %d stars" % [grade, grade])
		_check(bool(evaluation.get(&"passed", false)), "grade %d did not count as a passing lesson" % grade)
		_check(bool(evaluation.get(&"new_best", false)), "grade %d first pass was not marked as a new best" % grade)
		_check(bool(evaluation.get(&"first_completion", false)), "grade %d first pass was not marked as first completion" % grade)
		_check((evaluation.get(&"objective_results", []) as Array).size() == 2, "grade %d omitted objective grading" % grade)
		_check_authority(&"GATE_DROP", &"NEXT", "grade %d advancement" % grade)


func _probe_all_lessons_advance() -> void:
	_reset_profile()
	var catalog: Variant = ACADEMY_CATALOG_SCRIPT.create_default()
	for index: int in LESSON_ORDER.size():
		var lesson_id := LESSON_ORDER[index]
		_check_authority(lesson_id, &"NEXT", "lesson %d preflight" % (index + 1))
		var lesson: Dictionary = catalog.get_lesson(lesson_id)
		var evaluation := Profile.record_academy_result(lesson_id, _metrics_for_grade(lesson, 1))
		_check(int(evaluation.get(&"stars", 0)) == 1, "%s did not accept an exact bronze pass" % String(lesson_id))
		_check(bool(evaluation.get(&"first_completion", false)), "%s was not credited as a first completion" % String(lesson_id))
		var credited := evaluation.get(&"credited_rewards", {}) as Dictionary
		_check(
			int(credited.get(&"cash", 0)) > 0 and int(credited.get(&"reputation", 0)) > 0,
			"%s did not report its credited lesson reward" % String(lesson_id)
		)
		if index + 1 < LESSON_ORDER.size():
			_check_authority(LESSON_ORDER[index + 1], &"NEXT", "%s advancement" % String(lesson_id))
	_check(Profile.get_completed_academy_lessons().size() == LESSON_ORDER.size(), "the full Academy did not retain all eight passed lessons")
	_check_authority(&"PASSING_RACECRAFT", &"REPLAY", "all-lessons-complete fallback")


func _probe_academy_coach_catalog() -> void:
	var catalog: Variant = ACADEMY_CATALOG_SCRIPT.create_default()
	for lesson_id: StringName in LESSON_ORDER:
		var lesson: Dictionary = catalog.get_lesson(lesson_id)
		var template := str(lesson.get(&"coach_template", ""))
		var actions := _as_name_array(lesson.get(&"coach_actions", []))
		var presentation := lesson.get(&"presentation", {}) as Dictionary
		_check(not template.is_empty(), "%s has no Academy coach template" % String(lesson_id))
		_check(
			actions == _as_name_array(EXPECTED_COACH_ACTIONS.get(lesson_id, [])),
			"%s coach action authority drifted: %s" % [lesson_id, actions]
		)
		_check(
			StringName(presentation.get(&"racecraft_focus", &"")) == StringName(EXPECTED_RACECRAFT_FOCUS.get(lesson_id, &"")),
			"%s racecraft focus drifted" % lesson_id
		)
		_check(
			bool(presentation.get(&"show_flow_meter", false)) == (lesson_id == &"AIR_CONTROL"),
			"%s Flow meter disclosure drifted" % lesson_id
		)
		for hidden_layer: StringName in [&"show_line_feedback", &"show_sponsor_contract", &"show_daily_modifier"]:
			_check(not bool(presentation.get(hidden_layer, true)), "%s enabled unrelated %s" % [lesson_id, hidden_layer])
		for raw_token: Variant in EXPECTED_COACH_TOKENS.get(lesson_id, []):
			var token := str(raw_token)
			_check(template.contains(token), "%s coach omitted semantic token %s" % [lesson_id, token])
		for action: StringName in actions:
			_check(InputMap.has_action(action), "%s coach references missing action %s" % [lesson_id, action])
			_check(
				InputRouter.CONTEXT_RIDE in InputRouter.get_action_contexts(action),
				"%s coach action %s is not a live Ride control" % [lesson_id, action]
			)
	var academy_director_scope: Dictionary = RIDE_DIRECTOR_SCRIPT.get_activity_presentation_policy(&"ACADEMY")
	_check(not bool(academy_director_scope.get(&"show_line_feedback", true)), "Ride Director retained Academy line scoring")
	_check(not bool(academy_director_scope.get(&"show_sponsor_contract", true)), "Ride Director retained Academy sponsor contracts")
	_check(not bool(academy_director_scope.get(&"show_daily_modifier", true)), "Ride Director retained Academy daily modifiers")
	var ordinary_director_scope: Dictionary = RIDE_DIRECTOR_SCRIPT.get_activity_presentation_policy(&"CIRCUIT")
	_check(bool(ordinary_director_scope.get(&"show_line_feedback", false)), "Ride Director disabled ordinary line scoring")
	_check(bool(ordinary_director_scope.get(&"show_sponsor_contract", false)), "Ride Director disabled ordinary sponsor contracts")
	_check(bool(ordinary_director_scope.get(&"show_daily_modifier", false)), "Ride Director disabled ordinary daily modifiers")


func _probe_explicit_rematch_authority() -> void:
	_reset_profile()
	var catalog: Variant = ACADEMY_CATALOG_SCRIPT.create_default()
	var lesson: Dictionary = catalog.get_lesson(&"CONTROL_BASICS")
	var bronze := Profile.record_academy_result(&"CONTROL_BASICS", _metrics_for_grade(lesson, 1))
	_check(int(bronze.get(&"stars", 0)) == 1, "rematch setup did not earn bronze")
	_check(not RaceEventCatalog.request_academy_rematch(&"GATE_DROP"), "an unpassed lesson was accepted as a rematch")
	_check(RaceEventCatalog.request_academy_rematch(&"CONTROL_BASICS"), "a passed lesson could not be selected for rematch")
	_check_authority(&"CONTROL_BASICS", &"REMATCH", "explicit rematch")

	var silver := Profile.record_academy_result(&"CONTROL_BASICS", _metrics_for_grade(lesson, 2))
	var silver_credit := silver.get(&"credited_rewards", {}) as Dictionary
	_check(int(silver.get(&"previous_stars", 0)) == 1 and int(silver.get(&"best_stars", 0)) == 2, "silver rematch did not preserve the star history")
	_check(bool(silver.get(&"new_best", false)) and not bool(silver.get(&"first_completion", true)), "silver rematch used first-completion semantics")
	_check(int(silver_credit.get(&"cash", -1)) == 0 and int(silver_credit.get(&"reputation", -1)) == 0, "silver rematch duplicated the lesson reward")
	_check_authority(&"CONTROL_BASICS", &"REMATCH", "rematch remains explicit")
	RaceEventCatalog.clear_academy_lesson_override()
	_check_authority(&"GATE_DROP", &"NEXT", "cleared rematch")

	_check(RaceEventCatalog.request_academy_rematch(&"CONTROL_BASICS"), "completed lesson could not be selected for gold rematch")
	var gold := Profile.record_academy_result(&"CONTROL_BASICS", _metrics_for_grade(lesson, 3))
	_check(int(gold.get(&"previous_stars", 0)) == 2 and int(gold.get(&"best_stars", 0)) == 3, "gold rematch did not advance the best grade")
	RaceEventCatalog.clear_academy_lesson_override()
	_check_authority(&"GATE_DROP", &"NEXT", "post-gold progression")

	_check(RaceEventCatalog.request_academy_rematch(&"CONTROL_BASICS"), "stale-rematch setup was rejected")
	Profile.reset_profile_for_testing()
	Profile.racer_reputation = 1_000
	_check_authority(&"CONTROL_BASICS", &"NEXT", "profile reset clears stale rematch")
	_check(RaceEventCatalog.get_academy_lesson_override().is_empty(), "profile reset left a stale runtime rematch active")


func _probe_live_and_result_presentation() -> void:
	_reset_profile()
	var catalog: Variant = ACADEMY_CATALOG_SCRIPT.create_default()
	var lesson: Dictionary = catalog.get_lesson(&"CONTROL_BASICS")
	var prior_input_mode := InputRouter.input_mode
	var throttle_bindings := _snapshot_action(InputRouter.THROTTLE)
	var flow_bindings := _snapshot_action(InputRouter.FLOW_BOOST)
	InputRouter.call(&"_set_input_mode", InputRouter.INPUT_MODE_KEYBOARD_MOUSE)
	var hud := HUD_SCENE.instantiate() as RaceHud
	add_child(hud)
	await get_tree().process_frame
	EventBus.activity_prepared.emit(&"ACADEMY")
	hud.update_session_snapshot({
		&"event_id": &"ACADEMY",
		&"display_name": "ACADEMY: THROTTLE AND BRAKE CONTROL",
		&"format": &"ACADEMY",
		&"checkpoint_count": 10,
		&"current_checkpoint": 6,
		&"laps_completed": 0,
		&"integrity": {
			&"incidents": {&"resets_consumed": 1},
			&"off_course_time": 0.25,
		},
	})
	var live := hud.get_academy_presentation_snapshot()
	var live_objectives := live.get(&"objectives", PackedStringArray()) as PackedStringArray
	_check(bool(live.get(&"visible", false)), "Academy objectives were not visible during the lesson")
	_check(StringName(live.get(&"lesson_id", &"")) == &"CONTROL_BASICS", "HUD did not use the active lesson authority")
	_check(str(live.get(&"title", "")).contains("THROTTLE AND BRAKE CONTROL"), "HUD omitted the live lesson title")
	_check(not str(live.get(&"description", "")).is_empty(), "HUD omitted the live lesson description")
	_check(str(live.get(&"coach", "")).contains("W") and str(live.get(&"coach", "")).contains("A / D"), "Academy coach did not resolve keyboard controls")
	_check(live_objectives.size() == 2, "HUD did not enforce the two-objective Academy limit")
	_check(live_objectives[0].contains("PASS") and live_objectives[1].contains("PASS"), "HUD objectives omitted their passing thresholds")
	_check(not bool(hud.get_control_hint_state().get(&"visible", true)), "Academy duplicated its focused coach with the generic control wall")
	hud.update_line("LINE BROKEN", 0, 1.0, 0, 0.0)
	hud.update_contract("SPONSOR: LAND 2 CLEAN JUMPS", 0, 2, false)
	hud.update_modifier("TAILWIND", "+12% drive force")
	hud.update_racecraft_state({
		&"flow": 0.0,
		&"skill_zone_phase": &"PREVIEW",
		&"skill_zone": &"RUT",
		&"skill_zone_kind": &"RUT",
		&"skill_line_direction": &"LEFT",
		&"skill_line_distance_m": 18.0,
	})
	var focused_control := hud.get_academy_presentation_snapshot()
	_check(not bool(focused_control.get(&"line_visible", true)) and str(focused_control.get(&"line_text", "")).is_empty(), "Control Basics exposed line-chain feedback")
	_check(not bool(focused_control.get(&"line_score_visible", true)) and str(focused_control.get(&"line_score_text", "")).is_empty(), "Control Basics exposed line score")
	_check(not bool(focused_control.get(&"contract_visible", true)) and str(focused_control.get(&"contract_text", "")).is_empty(), "Control Basics exposed a sponsor contract")
	_check(not bool(focused_control.get(&"modifier_visible", true)) and str(focused_control.get(&"modifier_text", "")).is_empty(), "Control Basics exposed a daily modifier")
	_check(not bool(focused_control.get(&"racecraft_visible", true)) and str(focused_control.get(&"racecraft_text", "")).is_empty(), "Control Basics exposed generic racecraft coaching")
	_check(not bool(focused_control.get(&"flow_meter_visible", true)), "Control Basics exposed the advanced Flow meter")
	hud.update_integrity({
		&"warning": &"STUCK",
		&"flag": &"RESET_REQUIRED",
		&"penalty_usec": 0,
		&"incidents": {&"stuck": 1, &"resets_consumed": 0},
	})
	var academy_recovery_warning := hud.get_academy_presentation_snapshot()
	_check(
		bool(academy_recovery_warning.get(&"integrity_visible", false))
			and str(academy_recovery_warning.get(&"integrity_text", "")).contains("RETURNING TO A SAFE GATE"),
		"Academy stuck recovery omitted contextual coaching"
	)
	_check(
		not str(academy_recovery_warning.get(&"integrity_text", "")).contains("PENALTY"),
		"Academy stuck recovery used punitive time feedback"
	)
	hud.update_integrity({&"warning": &"NONE", &"flag": &"CLEAR", &"penalty_usec": 0})

	hud.configure_academy_lesson(catalog.get_lesson(&"RHYTHM_CHOICES"))
	hud.update_racecraft_state({
		&"flow": 20.0,
		&"skill_zone_phase": &"ACTIVE",
		&"skill_zone": &"RUT",
		&"skill_zone_kind": &"RUT",
		&"skill_line_direction": &"LEFT",
		&"skill_line_alignment": 0.75,
		&"skill_line_committed": true,
	})
	var rhythm_focus := hud.get_academy_presentation_snapshot()
	_check(bool(rhythm_focus.get(&"racecraft_visible", false)) and str(rhythm_focus.get(&"racecraft_text", "")).contains("FAST LINE"), "Rhythm Choices omitted its live fast-line cue")
	_check(not bool(rhythm_focus.get(&"flow_meter_visible", true)), "Rhythm Choices exposed the unrelated Flow meter")
	hud.configure_academy_lesson(catalog.get_lesson(&"AIR_CONTROL"))
	var air_focus := hud.get_academy_presentation_snapshot()
	_check(bool(air_focus.get(&"racecraft_visible", false)) and bool(air_focus.get(&"flow_meter_visible", false)), "Air Control omitted its relevant Flow feedback")

	EventBus.activity_prepared.emit(&"CIRCUIT")
	hud.update_line("CLEAN LANDING", 2, 1.25, 400, 3.5)
	hud.update_contract("DUSTLINE WORKS SIGNED  //  LAND 2 CLEAN JUMPS", 1, 2, false, 425, 40)
	hud.update_modifier("TAILWIND", "+12% drive force")
	hud.update_integrity({
		&"warning": &"MANUAL_RESET",
		&"flag": &"RESET_REQUIRED",
		&"penalty_usec": 2_000_000,
	})
	var ordinary := hud.get_academy_presentation_snapshot()
	_check(bool(ordinary.get(&"line_visible", false)) and not str(ordinary.get(&"line_score_text", "")).is_empty(), "ordinary race lost line feedback")
	_check(bool(ordinary.get(&"contract_visible", false)) and not str(ordinary.get(&"contract_text", "")).is_empty(), "ordinary race lost sponsor feedback")
	_check(str(ordinary.get(&"contract_text", "")).contains("DUSTLINE WORKS SIGNED") and str(ordinary.get(&"contract_text", "")).contains("$425 +40REP +1 TOKEN"), "ordinary race hid sponsor identity or exact reward")
	_check(bool(ordinary.get(&"modifier_visible", false)) and not str(ordinary.get(&"modifier_text", "")).is_empty(), "ordinary race lost daily modifier feedback")
	_check(bool(ordinary.get(&"racecraft_visible", false)) and bool(ordinary.get(&"flow_meter_visible", false)), "ordinary race lost full racecraft feedback")
	_check(str(ordinary.get(&"integrity_text", "")).contains("PENALTY APPLIED"), "ordinary race lost competitive reset-penalty feedback")
	EventBus.activity_prepared.emit(&"ACADEMY")

	# Same-device rebinding must refresh a coach that is already visible, while a
	# raw InputMap mutation remains inert until the authoritative notification.
	var coach_before_rebind := str(live.get(&"coach", ""))
	_replace_keyboard_binding(InputRouter.THROTTLE, KEY_F10)
	_replace_keyboard_binding(InputRouter.FLOW_BOOST, KEY_F9)
	_check(
		str(hud.get_academy_presentation_snapshot().get(&"coach", "")) == coach_before_rebind,
		"Academy coach refreshed before binding invalidation"
	)
	var revision_before_notify := InputRouter.binding_revision
	InputRouter.notify_bindings_changed([InputRouter.THROTTLE, InputRouter.FLOW_BOOST])
	var rebound_control := hud.get_academy_presentation_snapshot()
	_check(str(rebound_control.get(&"coach", "")).contains("F10"), "Academy coach omitted rebound throttle")
	_check(not str(rebound_control.get(&"coach", "")).contains("HOLD W"), "Academy coach retained stale throttle")
	_check(int(rebound_control.get(&"binding_revision", -1)) == revision_before_notify + 1, "Academy coach binding revision is stale")
	hud.configure_academy_lesson(catalog.get_lesson(&"AIR_CONTROL"))
	var rebound_air := hud.get_academy_presentation_snapshot()
	_check(str(rebound_air.get(&"coach", "")).contains("F9"), "Academy coach omitted rebound Context Flow")
	_check(not str(rebound_air.get(&"coach", "")).contains("SHIFT"), "Academy coach retained stale Context Flow")
	var expected_gamepad_flow := InputRouter.get_action_label(
		InputRouter.FLOW_BOOST, InputRouter.INPUT_MODE_GAMEPAD, 2
	)
	InputRouter.call(&"_set_input_mode", InputRouter.INPUT_MODE_GAMEPAD)
	var gamepad_air := hud.get_academy_presentation_snapshot()
	_check(str(gamepad_air.get(&"coach", "")).contains(expected_gamepad_flow), "Academy coach omitted the active gamepad Flow binding")
	_check(not str(gamepad_air.get(&"coach", "")).contains("F9"), "Academy coach leaked keyboard input in gamepad mode")
	InputRouter.call(&"_set_input_mode", InputRouter.INPUT_MODE_TOUCH)
	var touch_air := hud.get_academy_presentation_snapshot()
	_check(str(touch_air.get(&"coach", "")).contains("STEER / LEAN UP") and str(touch_air.get(&"coach", "")).contains("FLOW"), "Academy coach omitted authored touch controls")
	_check(not str(touch_air.get(&"coach", "")).contains("TOUCH"), "Academy coach used the generic touch placeholder")

	_restore_action(InputRouter.THROTTLE, throttle_bindings)
	_restore_action(InputRouter.FLOW_BOOST, flow_bindings)
	InputRouter.notify_bindings_changed([InputRouter.THROTTLE, InputRouter.FLOW_BOOST])

	# Every lesson must remain actionable and unclipped across all active devices
	# at the maximum supported text scale.
	hud.apply_accessibility({&"text_scale": 1.75})
	for mode: StringName in [
		InputRouter.INPUT_MODE_KEYBOARD_MOUSE,
		InputRouter.INPUT_MODE_GAMEPAD,
		InputRouter.INPUT_MODE_TOUCH,
	]:
		InputRouter.call(&"_set_input_mode", mode)
		for lesson_id: StringName in LESSON_ORDER:
			var coached_lesson: Dictionary = catalog.get_lesson(lesson_id)
			hud.configure_academy_lesson(coached_lesson)
			await get_tree().process_frame
			await get_tree().process_frame
			await get_tree().process_frame
			var coached := hud.get_academy_presentation_snapshot()
			var coach := str(coached.get(&"coach", ""))
			_check(StringName(coached.get(&"lesson_id", &"")) == lesson_id, "%s coach used the wrong lesson" % lesson_id)
			_check(bool(coached.get(&"coach_visible", false)) and not coach.is_empty(), "%s coach is not persistently visible" % lesson_id)
			_check(StringName(coached.get(&"input_mode", &"")) == mode, "%s coach exposed stale device mode" % lesson_id)
			_check(not coach.contains("{") and not coach.contains("UNBOUND"), "%s coach leaked an unresolved control" % lesson_id)
			_assert_resolved_coach_tokens(coached_lesson, coach, mode)
			_check(bool(coached.get(&"content_fits", false)), "%s coach content clips at 175%% in %s mode" % [lesson_id, mode])
			var panel_rect := coached.get(&"panel_rect", Rect2()) as Rect2
			var content_rect := coached.get(&"content_rect", Rect2()) as Rect2
			var coach_rect := coached.get(&"coach_rect", Rect2()) as Rect2
			_check(panel_rect.grow(1.0).encloses(content_rect), "%s panel does not enclose its container content" % lesson_id)
			_check(panel_rect.grow(1.0).encloses(coach_rect) and coach_rect.has_area(), "%s coach rect escapes the Academy panel" % lesson_id)
			_check(get_viewport().get_visible_rect().grow(1.0).encloses(panel_rect), "%s Academy panel escapes the viewport" % lesson_id)
			for line_fit: Dictionary in coached.get(&"line_fit", []) as Array:
				if not bool(line_fit.get(&"visible", false)):
					continue
				_check(not bool(line_fit.get(&"clip_text", true)), "%s Academy label %s clips text" % [lesson_id, line_fit.get(&"name", "")])
				_check(
					int(line_fit.get(&"visible_line_count", 0)) >= int(line_fit.get(&"line_count", 0)),
					"%s Academy label %s hides wrapped lines" % [lesson_id, line_fit.get(&"name", "")]
				)

	InputRouter.call(&"_set_input_mode", InputRouter.INPUT_MODE_TOUCH)
	var shrink_lesson: Dictionary = catalog.get_lesson(&"CONTROL_BASICS")
	hud.configure_academy_lesson(shrink_lesson)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var expanded_panel := (
		hud.get_academy_presentation_snapshot().get(&"panel_rect", Rect2()) as Rect2
	)
	hud.apply_accessibility({&"text_scale": 1.0})
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var compact_presentation := hud.get_academy_presentation_snapshot()
	var compact_panel := compact_presentation.get(&"panel_rect", Rect2()) as Rect2
	_check(
		compact_panel.size.y < expanded_panel.size.y - 1.0,
		"Academy panel did not shrink after reducing accessibility text scale"
	)
	_check(bool(compact_presentation.get(&"content_fits", false)), "Academy panel clipped after reducing text scale")
	InputRouter.call(&"_set_input_mode", prior_input_mode)

	var evaluation := Profile.record_academy_result(&"CONTROL_BASICS", _metrics_for_grade(lesson, 1))
	var credited := evaluation.get(&"credited_rewards", {}) as Dictionary
	_check(int(credited.get(&"cash", 0)) == 500 and int(credited.get(&"reputation", 0)) == 5, "Academy evaluation did not expose the credited first-pass reward")
	hud.show_results({
		&"valid": true,
		&"player_time_usec": 75_000_000,
		&"classification": [],
		&"academy_evaluation": evaluation,
		&"academy_next_lesson_id": &"GATE_DROP",
		&"academy_next_lesson_name": "GATE DROP AND HOLESHOT",
		&"rewards": {&"cash": 500, &"reputation": 5},
	})
	var results := hud.get_academy_presentation_snapshot()
	_check((results.get(&"evaluation", {}) as Dictionary) == evaluation, "HUD did not preserve the Academy evaluation payload")
	_check(str(results.get(&"results_title", "")).contains("ACADEMY COMPLETE"), "Academy results used the generic race title")
	_check(str(results.get(&"results_summary", "")).contains("PASSED"), "Academy results omitted the lesson pass state")
	_check(str(results.get(&"results_heading", "")).contains("OBJECTIVE"), "Academy results used the generic classification heading")
	_check(int(results.get(&"result_row_count", 0)) == 2, "Academy results did not render exactly two objective grades")
	var stats := str(results.get(&"results_stats", ""))
	_check(stats.contains("NEW BEST") and stats.contains("CREDITED") and stats.contains("$500"), "Academy results omitted best-grade or credited-reward feedback")
	hud.queue_free()
	await get_tree().process_frame
	_check(_action_matches_snapshot(InputRouter.THROTTLE, throttle_bindings), "Academy probe did not restore throttle bindings")
	_check(_action_matches_snapshot(InputRouter.FLOW_BOOST, flow_bindings), "Academy probe did not restore Flow bindings")
	_check(InputRouter.input_mode == prior_input_mode, "Academy probe did not restore input mode")


func _check_authority(expected_lesson_id: StringName, expected_mode: StringName, context: String) -> void:
	var active := RaceEventCatalog.get_active_academy_lesson()
	var event := RaceEventCatalog.get_event(&"ACADEMY")
	var session := RaceEventCatalog.get_session_config(&"ACADEMY")
	var garage: Variant = GARAGE_UI_SCRIPT.new()
	var garage_snapshot: Dictionary = garage.get_academy_progression_snapshot()
	garage.free()
	_check(StringName(active.get(&"lesson_id", &"")) == expected_lesson_id, "%s: active lesson diverged" % context)
	_check(StringName((event.get(&"rules", {}) as Dictionary).get(&"academy_lesson_id", &"")) == expected_lesson_id, "%s: event lesson diverged" % context)
	_check(session != null and StringName(session.rules.get(&"academy_lesson_id", &"")) == expected_lesson_id, "%s: launch session lesson diverged" % context)
	_check(session != null and session.reset_penalty_usec == 0, "%s: Academy recovery retained a competitive time penalty" % context)
	var expected_presentation := active.get(&"presentation", {}) as Dictionary
	_check(
		(event.get(&"rules", {}) as Dictionary).get(&"academy_presentation", {}) == expected_presentation,
		"%s: event presentation scope diverged" % context
	)
	_check(
		session != null and session.rules.get(&"academy_presentation", {}) == expected_presentation,
		"%s: launch presentation scope diverged" % context
	)
	_check(StringName(garage_snapshot.get(&"active_lesson_id", &"")) == expected_lesson_id, "%s: Garage lesson diverged" % context)
	_check(StringName(garage_snapshot.get(&"mode", &"")) == expected_mode, "%s: Garage mode was not %s" % [context, String(expected_mode)])


func _metrics_for_grade(lesson: Dictionary, grade: int) -> Dictionary:
	var grade_key := &"bronze"
	if grade == 2:
		grade_key = &"silver"
	elif grade >= 3:
		grade_key = &"gold"
	var metrics: Dictionary = {}
	for objective: Dictionary in lesson.get(&"objectives", []) as Array:
		var metric := StringName(objective.get(&"metric", &""))
		metrics[metric] = float(objective.get(grade_key, objective.get(&"bronze", 0.0)))
	return metrics


func _assert_resolved_coach_tokens(lesson: Dictionary, coach: String, mode: StringName) -> void:
	var template := str(lesson.get(&"coach_template", ""))
	var expected_labels := PackedStringArray()
	if template.contains("{THROTTLE}"):
		expected_labels.append("THROTTLE" if mode == InputRouter.INPUT_MODE_TOUCH else InputRouter.get_action_label(InputRouter.THROTTLE, mode, 2))
	if template.contains("{BRAKE}"):
		expected_labels.append("BRAKE" if mode == InputRouter.INPUT_MODE_TOUCH else InputRouter.get_action_label(InputRouter.BRAKE, mode, 2))
	if template.contains("{PRELOAD}"):
		expected_labels.append("PRELOAD" if mode == InputRouter.INPUT_MODE_TOUCH else InputRouter.get_action_label(InputRouter.PRELOAD, mode, 2))
	if template.contains("{FLOW}"):
		expected_labels.append("FLOW" if mode == InputRouter.INPUT_MODE_TOUCH else InputRouter.get_action_label(InputRouter.FLOW_BOOST, mode, 2))
	if template.contains("{TECHNIQUE}"):
		expected_labels.append("TECHNIQUE" if mode == InputRouter.INPUT_MODE_TOUCH else InputRouter.get_action_label(InputRouter.RACECRAFT, mode, 2))
	if template.contains("{RESET}"):
		expected_labels.append("RESET" if mode == InputRouter.INPUT_MODE_TOUCH else InputRouter.get_action_label(InputRouter.RESET_BIKE, mode, 2))
	if template.contains("{LEAN_FORWARD}"):
		expected_labels.append("STEER / LEAN UP" if mode == InputRouter.INPUT_MODE_TOUCH else InputRouter.get_action_label(InputRouter.LEAN_FORWARD, mode, 2))
	if template.contains("{LEAN_STEER}"):
		expected_labels.append(
			"STEER / LEAN" if mode == InputRouter.INPUT_MODE_TOUCH else "%s + %s" % [
				InputRouter.get_action_pair_label(InputRouter.LEAN_FORWARD, InputRouter.LEAN_BACK, mode, 2),
				InputRouter.get_action_pair_label(InputRouter.STEER_LEFT, InputRouter.STEER_RIGHT, mode, 2),
			]
		)
	if template.contains("{STEER}"):
		expected_labels.append("STEER / LEAN" if mode == InputRouter.INPUT_MODE_TOUCH else InputRouter.get_action_pair_label(InputRouter.STEER_LEFT, InputRouter.STEER_RIGHT, mode, 2))
	if template.contains("{LEAN}"):
		expected_labels.append("STEER / LEAN" if mode == InputRouter.INPUT_MODE_TOUCH else InputRouter.get_action_pair_label(InputRouter.LEAN_FORWARD, InputRouter.LEAN_BACK, mode, 2))
	for label: String in expected_labels:
		_check(coach.contains(label), "%s coach omitted resolved %s control in %s mode" % [lesson.get(&"lesson_id", &""), label, mode])
	if mode == InputRouter.INPUT_MODE_TOUCH:
		_check(not coach.contains("TOUCH"), "%s coach used generic TOUCH text" % lesson.get(&"lesson_id", &""))
		if StringName(lesson.get(&"lesson_id", &"")) == &"PRELOAD_LANDING":
			_check(
				coach == "COACH  //  JUMP: HOLD PRELOAD, RELEASE ON THE LOADED LIP; MATCH THE RECEIVER WITH STEER / LEAN. PUMP: TAP TECHNIQUE WITH BOTH WHEELS LOADED.",
				"Preload touch coaching duplicated or altered the shared steering control"
			)


func _as_name_array(raw: Variant) -> Array[StringName]:
	var output: Array[StringName] = []
	if raw is Array:
		for value: Variant in raw:
			output.append(StringName(value))
	return output


func _snapshot_action(action: StringName) -> Array[InputEvent]:
	var snapshot: Array[InputEvent] = []
	for event: InputEvent in InputMap.action_get_events(action):
		snapshot.append(event.duplicate() as InputEvent)
	return snapshot


func _replace_keyboard_binding(action: StringName, keycode: Key) -> void:
	var replacement := InputEventKey.new()
	replacement.physical_keycode = keycode
	var replaced := false
	var events: Array[InputEvent] = []
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey and not replaced:
			events.append(replacement)
			replaced = true
		else:
			events.append(event.duplicate() as InputEvent)
	if not replaced:
		events.push_front(replacement)
	InputMap.action_erase_events(action)
	for event: InputEvent in events:
		InputMap.action_add_event(action, event)


func _restore_action(action: StringName, snapshot: Array[InputEvent]) -> void:
	InputMap.action_erase_events(action)
	for event: InputEvent in snapshot:
		InputMap.action_add_event(action, event.duplicate() as InputEvent)


func _action_matches_snapshot(action: StringName, snapshot: Array[InputEvent]) -> bool:
	var current := InputMap.action_get_events(action)
	if current.size() != snapshot.size():
		return false
	for index: int in current.size():
		if SettingsStore.serialize_binding(current[index]) != SettingsStore.serialize_binding(snapshot[index]):
			return false
	return true


func _reset_profile() -> void:
	RaceEventCatalog.clear_academy_lesson_override()
	Profile.reset_profile_for_testing()
	Profile.persistence_enabled = false
	# This probe isolates lesson ordering from the broader career reputation gate.
	Profile.racer_reputation = 1_000


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
