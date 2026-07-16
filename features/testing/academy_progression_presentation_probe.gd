extends Node
## Deterministic Academy contract: selection, grading, rematches, Garage, and HUD.

const ACADEMY_CATALOG_SCRIPT := preload("res://features/career/academy_lesson_catalog.gd")
const GARAGE_UI_SCRIPT := preload("res://features/garage/garage_ui.gd")
const HUD_SCENE := preload("res://features/hud/race_hud.tscn")
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

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	Profile.persistence_enabled = false
	_probe_bronze_silver_gold_advancement()
	_probe_all_lessons_advance()
	_probe_explicit_rematch_authority()
	await _probe_live_and_result_presentation()
	RaceEventCatalog.clear_academy_lesson_override()
	if _failures.is_empty():
		print("ACADEMY PROGRESSION PRESENTATION PROBE: PASS  //  grades=3 lessons=8 rematch=true garage=true hud_objectives=2")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("ACADEMY PROGRESSION PRESENTATION PROBE: " + failure)
	get_tree().quit(1)


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
	_check(live_objectives.size() == 2, "HUD did not enforce the two-objective Academy limit")
	_check(live_objectives[0].contains("PASS") and live_objectives[1].contains("PASS"), "HUD objectives omitted their passing thresholds")

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


func _reset_profile() -> void:
	RaceEventCatalog.clear_academy_lesson_override()
	Profile.reset_profile_for_testing()
	Profile.persistence_enabled = false
	# This probe isolates lesson ordering from the broader career reputation gate.
	Profile.racer_reputation = 1_000


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
