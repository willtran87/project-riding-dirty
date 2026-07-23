extends Node
## Focused end-to-end regression for the production Garage season action.

var _failures := PackedStringArray()


func _ready() -> void:
	Profile.persistence_enabled = false
	Profile.reset_profile_for_testing()
	Profile.persistence_enabled = false
	var weekend := RaceWeekendDirector.create(RaceEventCatalog.get_default_weekend_config())
	weekend.start_weekend()
	Profile.set_race_weekend_snapshot(weekend.to_dictionary())

	var championship: Variant = Profile.get_championship_service()
	var classification: Array[Dictionary] = [
		{&"rider_id": &"PLAYER", &"display_name": "YOU", &"position": 1, &"status": &"FINISHED"},
		{&"rider_id": &"ROOK", &"display_name": "ROOK", &"position": 2, &"status": &"FINISHED"},
	]
	for round_data: Dictionary in championship.get_calendar():
		_check(championship.record_round_result(StringName(round_data.get(&"round_id", &"")), classification), "round completes")
	_check(championship.is_complete(), "test championship reaches its terminal state")
	Profile.set_championship_snapshot(championship.to_dictionary())

	var garage := GarageUi.new()
	add_child(garage)
	await get_tree().process_frame
	garage.show_garage()
	var action := garage.get_continue_weekend_snapshot()
	var action_label := garage.get_node_or_null("GarageRoot/ContinueWeekendAction") as Label
	_check(bool(action.get(&"start_next_season", false)), "completed season projects a rollover action")
	_check(action_label != null and action_label.visible and action_label.text.contains("START SEASON 2"), "rollover action is visible and numbered")
	_check(garage.continue_weekend(), "rollover action executes")

	var next_championship: Variant = Profile.get_championship_service()
	var next_weekend: Variant = Profile.get_race_weekend_director()
	_check(next_championship.season_number == 2, "season number increments")
	_check(next_championship.completed_round_count() == 0, "new season starts with no classified rounds")
	_check(next_weekend != null and next_weekend.get_current_phase() == RaceWeekendDirector.PRACTICE, "managed weekend returns to practice")

	for failure: String in _failures:
		push_error("SEASON ROLLOVER PROBE FAILURE: %s" % failure)
	print("SEASON ROLLOVER PROBE: season=%d rounds=%d phase=%s failures=%d passed=%s" % [
		next_championship.season_number,
		next_championship.completed_round_count(),
		String(next_weekend.get_current_phase()) if next_weekend != null else "NONE",
		_failures.size(),
		str(_failures.is_empty()),
	])
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
