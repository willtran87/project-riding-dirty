extends Node
## Deterministic contract for the optional Manual Shift Rhythm Academy lesson.

const TRACKER_SCRIPT := preload("res://features/career/academy_transmission_tracker.gd")
const ACADEMY_CATALOG_SCRIPT := preload("res://features/career/academy_lesson_catalog.gd")
const RACE_SERVICES_SCRIPT := preload("res://features/race/race_services.gd")

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_probe_authoritative_shift_grading()
	_probe_contextual_coach_states()
	_probe_lesson_and_temporary_override()
	_probe_competitive_record_separation()
	if _failures.is_empty():
		print("MANUAL TRANSMISSION ACADEMY PROBE: PASS  //  clean=2 mistimed=1 overrev=0.25s forced=MANUAL restored=AUTOMATIC signatures=separate")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("MANUAL TRANSMISSION ACADEMY PROBE: " + failure)
	get_tree().quit(1)


func _probe_authoritative_shift_grading() -> void:
	var tracker: Variant = TRACKER_SCRIPT.new()
	tracker.sample(0.50, _snapshot(&"AUTOMATIC", 1, 0.90, 1, &"AUTOMATIC_UP"))
	_check((tracker.get_metrics() as Dictionary).is_empty() == false, "tracker metrics contract is missing")
	var untouched := tracker.get_metrics() as Dictionary
	_check(
		int(untouched.get(&"clean_shifts", -1)) == 0
			and is_zero_approx(float(untouched.get(&"overrev_seconds", -1.0))),
		"automatic transmission contaminated manual lesson grading"
	)

	tracker.sample(0.016, _snapshot(&"MANUAL", 1, 0.10, 2, &"RESET"))
	var clean_up := _snapshot(&"MANUAL", 2, 0.55, 3, &"MANUAL_UP")
	clean_up[&"last_shift_rpm"] = 0.84
	tracker.sample(0.016, clean_up)
	tracker.sample(0.016, clean_up)
	tracker.sample(0.016, _snapshot(&"MANUAL", 3, 0.42, 4, &"MANUAL_UP"))
	tracker.sample(0.016, _snapshot(&"MANUAL", 2, 0.52, 5, &"MANUAL_DOWN"))
	tracker.sample(0.25, _snapshot(&"MANUAL", 2, 1.01, 5, &"MANUAL_DOWN"))
	var metrics := tracker.get_metrics() as Dictionary
	_check(int(metrics.get(&"clean_shifts", 0)) == 2, "clean up/down shifts were not graded exactly once")
	_check(int(metrics.get(&"mistimed_shifts", 0)) == 1, "mistimed shift was not distinguished")
	_check(int(metrics.get(&"manual_upshifts", 0)) == 2, "manual upshift count drifted")
	_check(int(metrics.get(&"manual_downshifts", 0)) == 1, "manual downshift count drifted")
	_check(
		is_equal_approx(float(metrics.get(&"overrev_seconds", 0.0)), 0.25),
		"redline exposure did not accumulate by deterministic simulation delta"
	)


func _probe_contextual_coach_states() -> void:
	_check(
		TRACKER_SCRIPT.get_coach_state(_snapshot(&"AUTOMATIC", 1, 0.20, 1, &"RESET"))
			== &"MANUAL_REQUIRED",
		"automatic state was presented as manual practice"
	)
	var shift_up := _snapshot(&"MANUAL", 2, 0.86, 2, &"MANUAL_UP")
	shift_up[&"suggested_gear"] = 3
	_check(TRACKER_SCRIPT.get_coach_state(shift_up) == &"SHIFT_UP", "high RPM omitted shift-up coaching")
	var shift_down := _snapshot(&"MANUAL", 3, 0.28, 3, &"MANUAL_DOWN")
	shift_down[&"suggested_gear"] = 2
	_check(TRACKER_SCRIPT.get_coach_state(shift_down) == &"SHIFT_DOWN", "bogging RPM omitted shift-down coaching")
	var hold := _snapshot(&"MANUAL", 2, 0.58, 4, &"MANUAL_UP")
	hold[&"suggested_gear"] = 2
	_check(TRACKER_SCRIPT.get_coach_state(hold) == &"HOLD_GEAR", "useful mid-band RPM did not coach holding the gear")


func _probe_lesson_and_temporary_override() -> void:
	var catalog: Variant = ACADEMY_CATALOG_SCRIPT.create_default()
	var lesson: Dictionary = catalog.get_lesson(&"MANUAL_SHIFTING")
	_check(not lesson.is_empty(), "Academy catalog omitted Manual Shift Rhythm")
	_check(
		StringName(lesson.get(&"forced_transmission_mode", &"")) == &"MANUAL",
		"lesson does not force its coached Manual configuration"
	)
	_check(
		(lesson.get(&"objectives", []) as Array).size() == 2,
		"lesson does not retain the compact two-objective contract"
	)

	var services: Variant = RACE_SERVICES_SCRIPT.new()
	add_child(services)
	services.settings.set_value(&"gameplay", &"transmission_mode", "AUTOMATIC")
	_check(services.get_preferred_transmission_mode() == &"AUTOMATIC", "test preference did not start in Automatic")
	_check(services.set_activity_transmission_override(&"MANUAL", true), "valid lesson override was rejected")
	_check(
		services.get_effective_transmission_mode() == &"MANUAL"
			and services.get_preferred_transmission_mode() == &"AUTOMATIC"
			and services.is_activity_transmission_forced(),
		"lesson override overwrote the player's persisted preference"
	)
	services.clear_activity_transmission_override()
	_check(
		services.get_effective_transmission_mode() == &"AUTOMATIC",
		"clearing the lesson override did not restore the player preference"
	)
	_check(
		services.set_activity_transmission_override(&"AUTOMATIC", false)
			and not services.is_activity_transmission_forced(),
		"ordinary activity transmission lock was mistaken for a forced lesson"
	)
	services.settings.set_value(&"gameplay", &"transmission_mode", "MANUAL")
	_check(
		services.get_preferred_transmission_mode() == &"MANUAL"
			and services.get_effective_transmission_mode() == &"AUTOMATIC",
		"mid-activity preference change altered the locked drivetrain"
	)
	services.clear_activity_transmission_override()
	_check(
		services.get_effective_transmission_mode() == &"MANUAL",
		"next activity did not receive the newly saved transmission preference"
	)
	services.queue_free()


func _probe_competitive_record_separation() -> void:
	var automatic := CompetitiveRunSignature.build(_signature_context(&"AUTOMATIC"))
	var manual := CompetitiveRunSignature.build(_signature_context(&"MANUAL"))
	_check(automatic != manual, "Automatic and Manual runs still share one competitive record")
	var normalized := CompetitiveRunSignature.normalize_context(_signature_context(&"MANUAL"))
	_check(
		StringName(normalized.get("transmission_mode", "")) == &"MANUAL",
		"normalized competitive signature omitted transmission mode"
	)


func _signature_context(mode: StringName) -> Dictionary:
	return {
		"event_id": &"CIRCUIT",
		"track_id": &"QUARRY",
		"route_version": 19,
		"format": &"SPRINT",
		"laps": 1,
		"bike_class": &"LITE_125",
		"difficulty": 1,
		"assist_mode": "S045_B045_L045_T045_R045",
		"transmission_mode": mode,
		"setup_id": &"BALANCED",
	}


func _snapshot(
	mode: StringName,
	gear: int,
	rpm: float,
	revision: int,
	reason: StringName
) -> Dictionary:
	return {
		&"mode": mode,
		&"gear": gear,
		&"gear_count": 5,
		&"rpm": rpm,
		&"suggested_gear": gear,
		&"revision": revision,
		&"last_shift_reason": reason,
	}


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
