extends Node
## Fast integration contract for the garage-facing full-game systems.

var _failures: Array[String] = []


func _ready() -> void:
	Profile.persistence_enabled = false
	Profile.reset_profile_for_testing()
	_probe_rotating_challenge_signature()
	_probe_academy_flow()
	_probe_garage_event_catalog()
	if _failures.is_empty():
		print("FULL GAME META PROBE: PASS  //  CHALLENGES + ACADEMY + 18 GARAGE EVENTS")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("FULL GAME META PROBE: " + failure)
	get_tree().quit(1)


func _probe_rotating_challenge_signature() -> void:
	var schedule := ChallengeSchedule.new()
	var challenge := schedule.daily(1_750_000_000, 3)
	var config := RaceEventCatalog.get_challenge_session_config(&"DAILY_CHALLENGE", challenge)
	var rules := config.rules
	var actual_signature := CompetitiveRunSignature.build({
		"event_id": rules.get(&"competitive_event_id", config.event_id),
		"track_id": config.track_id,
		"route_version": config.route_version,
		"format": config.format,
		"laps": config.laps,
		"bike_class": rules.get(&"competitive_bike_class", config.bike_class),
		"difficulty": rules.get(&"competitive_difficulty", config.difficulty),
		"assist_mode": rules.get(&"competitive_assist_mode", &"STANDARD"),
		"setup_id": rules.get(&"competitive_setup_id", &"BALANCED"),
		"tune_signature": "",
		"weather": config.weather,
		"surface": config.surface_modifier,
		"challenge_id": rules.get(&"challenge_id", ""),
		"modifiers": rules.get(&"modifiers", []),
	})
	_check(actual_signature == str(challenge.get("run_signature", "")), "challenge signature drifted from its playable session")
	_check(config.track_id in [CourseCatalog.QUARRY_ID, CourseCatalog.PINE_ID, CourseCatalog.MESA_MX_ID], "challenge selected an invalid track")
	_check(config.difficulty >= 1 and config.difficulty <= 4, "challenge difficulty exceeded the playable range")


func _probe_academy_flow() -> void:
	var academy_event := RaceEventCatalog.get_event(&"ACADEMY")
	var config := RaceEventCatalog.get_session_config(&"ACADEMY")
	_check(StringName(academy_event.get(&"event_id", &"")) == &"ACADEMY", "academy event was not generated")
	_check(config.track_id == CourseCatalog.MESA_MX_ID and config.checkpoint_count == 10, "academy did not configure its marked Mesa lesson")
	_check(StringName(config.rules.get(&"academy_lesson_id", &"")) == &"CONTROL_BASICS", "academy did not select the first available lesson")
	var grade := Profile.record_academy_result(&"CONTROL_BASICS", {&"gates_completed": 10, &"resets": 0})
	_check(bool(grade.get(&"passed", false)) and int(grade.get(&"stars", 0)) == 3, "academy ride metrics did not award a gold lesson grade")
	_check(int(Profile.get_academy_progress_snapshot().get(&"CONTROL_BASICS", 0)) == 3, "academy progress was not persisted in the profile model")


func _probe_garage_event_catalog() -> void:
	_check(GarageUi.EVENTS.size() == 18, "garage event roster is incomplete")
	for event_id: StringName in GarageUi.EVENTS:
		_check(RaceEventCatalog.has_event(event_id), "garage event %s has no catalog definition" % String(event_id))
		if RaceEventCatalog.is_race_event(event_id):
			var config := RaceEventCatalog.get_session_config(event_id)
			_check(config != null and config.laps >= 1 and config.field_size >= 1, "race event %s has an invalid session" % String(event_id))


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
