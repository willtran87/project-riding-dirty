extends Node
## Headless deterministic regression for the standalone career data services.

const CHAMPIONSHIP_SCRIPT := preload("res://features/career/championship_service.gd")
const WEEKEND_SCRIPT := preload("res://features/career/race_weekend_director.gd")
const BIKE_CLASS_SCRIPT := preload("res://features/career/racing_bike_class_definition.gd")
const BIKE_TUNE_SCRIPT := preload("res://features/career/racing_bike_tune.gd")
const BIKE_BUILD_SCRIPT := preload("res://features/career/racing_bike_build.gd")
const BIKE_CATALOG_SCRIPT := preload("res://features/career/racing_bike_catalog.gd")
const ACADEMY_SCRIPT := preload("res://features/career/academy_lesson_catalog.gd")

var _failures := PackedStringArray()


func _ready() -> void:
	_test_championship()
	_test_weekend()
	_test_bike_build()
	_test_academy()
	for failure: String in _failures:
		push_error("CAREER SYSTEMS PROBE FAILURE: %s" % failure)
	var passed := _failures.is_empty()
	print("CAREER SYSTEMS PROBE: suites=4 failures=%d passed=%s" % [_failures.size(), str(passed)])
	get_tree().quit(0 if passed else 1)


func _test_championship() -> void:
	var service := RacingChampionshipService.create_default()
	_check(service.get_calendar().size() == 6, "default championship calendar must contain six rounds")
	var first_round := StringName(service.get_calendar()[0].get(&"round_id", &""))
	var second_round := StringName(service.get_calendar()[1].get(&"round_id", &""))
	var first_classification := _classification([&"RIDER_A", &"RIDER_B", &"RIDER_C"])
	var second_classification := _classification([&"RIDER_B", &"RIDER_A", &"RIDER_C"])
	_check(service.record_round_result(first_round, first_classification), "first championship result must be accepted")
	_check(service.record_round_result(second_round, second_classification), "second championship result must be accepted")
	var standings := service.get_standings()
	_check(standings.size() == 3, "championship standings must include every classified rider")
	_check(StringName(standings[0].get(&"rider_id", &"")) == &"RIDER_B", "latest-result countback must resolve an exact points tie")
	_check(int(standings[0].get(&"points", 0)) == 47, "winner and runner-up points must total 47")
	var stable_snapshot := JSON.stringify(standings)
	service.record_round_result(second_round, second_classification)
	_check(JSON.stringify(service.get_standings()) == stable_snapshot, "reimporting a round must not double-award points")
	var restored := RacingChampionshipService.from_dictionary(_json_round_trip(service.to_dictionary()))
	_check(JSON.stringify(restored.get_standings()) == stable_snapshot, "championship serialization must preserve standings")
	_check(restored.completed_round_count() == 2, "championship serialization must preserve completed rounds")
	_check(not restored.start_next_season(), "an unfinished championship must not discard progress")
	for round_data: Dictionary in restored.get_calendar():
		var round_id := StringName(round_data.get(&"round_id", &""))
		if not bool(round_data.get(&"completed", false)):
			_check(restored.record_round_result(round_id, first_classification), "remaining championship rounds must accept results")
	_check(restored.is_complete(), "all six recorded rounds must complete the championship")
	var completed_season := restored.season_number
	_check(restored.start_next_season(), "a completed championship must start a new season")
	_check(restored.season_number == completed_season + 1, "new season must increment its persisted number")
	_check(restored.completed_round_count() == 0 and restored.get_standings().is_empty(), "new season must clear prior results without changing its calendar")
	var next_season := RacingChampionshipService.from_dictionary(_json_round_trip(restored.to_dictionary()))
	_check(next_season.season_number == completed_season + 1 and next_season.completed_round_count() == 0, "new-season state must survive serialization")


func _test_weekend() -> void:
	var entrants: Array[Dictionary] = []
	var entrant_ids: Array[StringName] = []
	for index: int in 12:
		var rider_id := StringName("RIDER_%02d" % (index + 1))
		entrant_ids.append(rider_id)
		entrants.append({&"rider_id": rider_id, &"display_name": "Rider %02d" % (index + 1), &"seed": index + 1})
	var director := RaceWeekendDirector.create({
		&"weekend_id": &"PROBE_WEEKEND", &"event_id": &"MESA_MX", &"entrants": entrants,
		&"heat_transfer_count": 6, &"lcq_transfer_count": 4, &"main_field_limit": 10,
	})
	director.start_weekend()
	_check(director.get_current_phase() == RaceWeekendDirector.PRACTICE, "weekend must begin in practice")
	director.submit_session_result(_classification(entrant_ids))
	_check(director.get_current_phase() == RaceWeekendDirector.QUALIFYING, "practice must advance to qualifying")
	var qualifying_ids := entrant_ids.duplicate()
	qualifying_ids.reverse()
	director.submit_session_result(_classification(qualifying_ids))
	_check(director.get_current_phase() == RaceWeekendDirector.HEAT, "qualifying must advance to heat")
	_check(director.get_gate_order()[0] == qualifying_ids[0], "qualifying result must become heat gate order")
	director.submit_session_result(_classification(qualifying_ids))
	_check(director.get_current_phase() == RaceWeekendDirector.LCQ, "heat must advance to LCQ")
	_check(director.heat_qualifiers.size() == 6 and director.lcq_candidates.size() == 6, "heat transfers must split the twelve-rider field 6/6")
	var lcq_ids := director.get_session_entrant_ids(RaceWeekendDirector.LCQ)
	director.submit_session_result(_classification(lcq_ids))
	_check(director.get_current_phase() == RaceWeekendDirector.MAIN, "LCQ must advance to main")
	_check(director.get_main_grid().size() == 10, "main grid must combine six heat and four LCQ transfers")
	var main_finish := director.get_main_grid()
	main_finish.reverse()
	director.submit_session_result(_classification(main_finish))
	_check(director.get_current_phase() == RaceWeekendDirector.RESULTS and director.is_complete(), "main must advance to terminal results")
	_check(director.get_final_classification().size() == 10, "final classification must include the full main field")
	var restored := RaceWeekendDirector.from_dictionary(_json_round_trip(director.to_dictionary()))
	_check(restored.is_complete() and restored.get_main_grid() == director.get_main_grid(), "weekend serialization must preserve terminal state and grid")


func _test_bike_build() -> void:
	var catalog := RacingBikeCatalog.create_default()
	var build := RacingBikeBuild.new()
	_check(build.install_part(catalog, &"HARDPACK_TIRES"), "compatible tire upgrade must install")
	_check(build.install_part(catalog, &"PROGRESSIVE_FORK"), "compatible suspension upgrade must install")
	_check(build.tune.set_adjustment(&"gearing", 0.5), "known tune adjustment must be accepted")
	_check(build.tune.set_adjustment(&"preload", 2.0) and is_equal_approx(build.tune.jump_preload, 1.0), "tune inputs must clamp to their safe range")
	_check(build.tune.set_adjustment(&"suspension_damping", 0.75), "damping tune adjustment must be accepted")
	_check(build.tune.set_adjustment(&"brake_bias", 0.5), "brake-bias tune adjustment must be accepted")
	var first_stats := build.calculate_stats(catalog)
	var second_stats := build.calculate_stats(catalog)
	_check(first_stats == second_stats, "bike stat calculation must be idempotent")
	var untouched_base := catalog.get_bike(&"TYKE_125").get(&"base_stats", {}) as Dictionary
	_check(is_equal_approx(float(untouched_base.get(&"grip", 0.0)), 75.0), "bike calculation must not mutate catalog base stats")
	_check(&"LITE_125" in build.eligible_classes(catalog, 0), "starter bike must remain eligible for the lite class")
	var restored_catalog := RacingBikeCatalog.from_dictionary(_json_round_trip(catalog.to_dictionary()))
	var restored := RacingBikeBuild.from_dictionary(_json_round_trip(build.to_dictionary()))
	_check(restored.signature() == build.signature(), "bike build serialization must preserve its deterministic signature")
	_check(restored.calculate_stats(restored_catalog) == first_stats, "bike build serialization must preserve calculated stats")
	var tuned_runtime := RacingBikeBuild.runtime_projection(&"BALANCED", first_stats, 100, build.tune.to_dictionary())
	var neutral_runtime := RacingBikeBuild.runtime_projection(&"BALANCED", first_stats, 100, {})
	_check(float(tuned_runtime.get(&"spring_rebound_damping", 0.0)) > float(neutral_runtime.get(&"spring_rebound_damping", 0.0)), "damping tune does not reach the physical rebound parameter")
	_check(float(tuned_runtime.get(&"front_brake_bias", 0.0)) > float(neutral_runtime.get(&"front_brake_bias", 0.0)), "brake-bias tune does not reach wheel force distribution")
	_check(float(tuned_runtime.get(&"preload_impulse", 0.0)) > float(neutral_runtime.get(&"preload_impulse", 0.0)), "preload tune does not reach launch impulse")
	var open_definition := restored_catalog.get_class_definition(&"OPEN")
	_check(open_definition.class_id == &"OPEN", "catalog must materialize serializable class definitions")
	var restored_definition := RacingBikeClassDefinition.from_dictionary(_json_round_trip(open_definition.to_dictionary()))
	_check(restored_definition.class_id == open_definition.class_id, "bike class definition must survive JSON serialization")


func _test_academy() -> void:
	var catalog := RacingAcademyLessonCatalog.create_default()
	_check(catalog.get_lessons().size() == 8, "academy must include the complete compact lesson chain")
	var available := catalog.get_available_lessons([], 0)
	_check(available.size() == 1 and StringName(available[0].get(&"lesson_id", &"")) == &"CONTROL_BASICS", "academy prerequisites must gate later lessons")
	var evaluation := catalog.evaluate_lesson(&"CONTROL_BASICS", {&"gates_completed": 10, &"resets": 0})
	_check(bool(evaluation.get(&"passed", false)) and int(evaluation.get(&"stars", 0)) == 3, "academy grading must award three stars for gold metrics")
	var missing_metric := catalog.evaluate_lesson(&"CONTROL_BASICS", {&"gates_completed": 10})
	_check(not bool(missing_metric.get(&"passed", true)), "academy grading must fail when a required metric is absent")
	var restored := RacingAcademyLessonCatalog.from_dictionary(_json_round_trip(catalog.to_dictionary()))
	_check(restored.get_lessons() == catalog.get_lessons(), "academy serialization must preserve lesson definitions")


func _classification(rider_ids: Array[StringName]) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for index: int in rider_ids.size():
		output.append({
			&"rider_id": rider_ids[index],
			&"display_name": String(rider_ids[index]),
			&"position": index + 1,
			&"status": &"FINISHED",
		})
	return output


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _json_round_trip(data: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(data))
	return parsed as Dictionary if parsed is Dictionary else {}
