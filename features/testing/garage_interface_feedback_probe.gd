extends Node
## Real Garage/Workshop action feedback across success, navigation and refusal.

const GARAGE_SCENE := preload("res://features/garage/garage_ui.tscn")
const WEEKEND_DIRECTOR_SCRIPT := preload("res://features/career/race_weekend_director.gd")

var _failures: Array[String] = []
var _feedback: Array[Dictionary] = []
var _ride_requests: Array[Dictionary] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	Profile.persistence_enabled = false
	Profile.reset_profile_for_testing()
	var fresh_weekend: Variant = WEEKEND_DIRECTOR_SCRIPT.create(RaceEventCatalog.get_default_weekend_config())
	fresh_weekend.start_weekend()
	_check(Profile.set_race_weekend_snapshot(fresh_weekend.to_dictionary()), "Probe could not seed the production first-run weekend")
	EventBus.interface_feedback_requested.connect(_on_interface_feedback_requested)
	var garage := GARAGE_SCENE.instantiate() as GarageUi
	garage.ride_requested.connect(_on_ride_requested)
	add_child(garage)
	await get_tree().process_frame

	garage.show_garage()
	_check(
		StringName(garage.get_event_briefing_presentation_snapshot().get(&"event_id", &"")) == &"CIRCUIT",
		"Fresh Garage did not start at the first event"
	)
	var fresh_briefing_text := str(garage.get_event_briefing_presentation_snapshot().get(&"text", ""))
	_check(fresh_briefing_text.contains("FIRST ROUTE"), "Fresh competition briefing does not reinforce the first route")
	_check(not fresh_briefing_text.contains("NEXT RED MESA"), "Fresh competition briefing still leads toward a later district")
	var fresh_progression := garage.get_progression_presentation_snapshot()
	_check(bool(fresh_progression.get(&"first_run_path", false)), "Fresh Garage did not expose its first-run progression path")
	_check(str(fresh_progression.get(&"context", "")).contains("QUARRY TRAIL"), "Fresh Garage context still leads with a later district")
	var fresh_summary := str(fresh_progression.get(&"summary", ""))
	_check(fresh_summary.contains("FIRST ROUTE") and fresh_summary.contains("EVENT 01"), "Fresh Garage summary does not identify the first route")
	_check(fresh_summary.contains("CLEAR 2 QUARRY EVENTS"), "Fresh Garage summary omits the next concrete unlock goal")
	_check(not fresh_summary.contains("PHASE  PRACTICE"), "Fresh Garage summary still presents a later weekend as active")
	var fresh_strategy := garage.get_event_strategy_presentation_snapshot()
	_check(StringName(fresh_strategy.get(&"event_id", &"")) == &"CIRCUIT", "Fresh strategy guidance targets the wrong event")
	_check(StringName(fresh_strategy.get(&"recommended_setup", &"")) == &"BALANCED", "First event does not recommend the readable baseline kit")
	_check(StringName(fresh_strategy.get(&"recommended_tune", &"")) == &"BALANCED", "First event does not recommend the readable baseline tune")
	_check(bool(fresh_strategy.get(&"full_match", false)), "Fresh baseline build is not recognized as matching the first event plan")
	_check(
		str(fresh_strategy.get(&"label", "")).contains("EVENT PLAN")
		and str(fresh_strategy.get(&"label", "")).ends_with("MATCH")
		and not str(fresh_strategy.get(&"label", "")).ends_with("KIT MATCH"),
		"First event strategy is absent or does not present its complete ready state: %s" % str(fresh_strategy.get(&"label", ""))
	)
	var strategy_signature := str(Profile.get_active_bike_setup_snapshot().get(&"signature", ""))
	_check(garage.focus_event_briefing(&"PINE_ENDURO"), "Pine Enduro is absent from the Garage event list")
	var pine_strategy := garage.get_event_strategy_presentation_snapshot()
	_check(
		StringName(pine_strategy.get(&"recommended_setup", &"")) == &"TRAIL"
		and StringName(pine_strategy.get(&"recommended_tune", &"")) == &"ENDURO",
		"Pine strategy does not expose its traction and compliance tradeoff"
	)
	_check(not bool(pine_strategy.get(&"full_match", true)), "Baseline build is incorrectly presented as the Pine-specific plan")
	_check(
		str(garage.get_event_briefing_presentation_snapshot().get(&"event_meta", "")).contains("TWO QUARRY EVENTS"),
		"Pine unlock presentation does not name the authoritative Quarry-clear gate"
	)
	_check(
		not bool(pine_strategy.get(&"recommended_setup_owned", true))
		and int(pine_strategy.get(&"recommended_setup_price", -1)) == 750
		and int(pine_strategy.get(&"recommended_setup_shortfall", -1)) == 750
		and str(pine_strategy.get(&"label", "")).contains("KIT $750 AWAY"),
		"Pine strategy does not disclose the fresh profile's exact Trail-kit path"
	)
	_check(garage.focus_event_briefing(&"MESA_RHYTHM"), "Rhythm Attack is absent from the Garage event list")
	var rhythm_strategy := garage.get_event_strategy_presentation_snapshot()
	_check(
		StringName(rhythm_strategy.get(&"recommended_setup", &"")) == &"ATTACK"
		and StringName(rhythm_strategy.get(&"recommended_tune", &"")) == &"RHYTHM",
		"Rhythm strategy does not expose its jump-support tradeoff"
	)
	_check(
		int(rhythm_strategy.get(&"recommended_setup_price", -1)) == 1_500
		and int(rhythm_strategy.get(&"recommended_setup_shortfall", -1)) == 1_500
		and str(rhythm_strategy.get(&"label", "")).contains("KIT $1500 AWAY"),
		"Attack strategy does not disclose its exact progression price"
	)
	_check(str(Profile.get_active_bike_setup_snapshot().get(&"signature", "")) == strategy_signature, "Browsing strategy guidance mutated the active build")
	_check(garage.focus_event_briefing(&"CIRCUIT"), "Probe could not return to the first Garage event")
	var fresh_weekend_action := garage.get_continue_weekend_snapshot()
	var weekend_action_label := garage.get_node_or_null("GarageRoot/ContinueWeekendAction") as Label
	_check(not bool(fresh_weekend_action.get(&"available", true)), "Fresh profile unexpectedly unlocked the Red Mesa weekend")
	_check(str(fresh_weekend_action.get(&"action_text", "")).is_empty(), "Locked weekend still advertises a continue shortcut")
	_check(weekend_action_label != null and not weekend_action_label.visible, "Locked weekend continue label remains visible")
	_feedback.clear()
	var workshop_click := InputEventMouseButton.new()
	workshop_click.button_index = MOUSE_BUTTON_LEFT
	workshop_click.pressed = true
	garage.call(&"_on_workshop_summary_gui_input", workshop_click)
	_check(garage.is_workshop_open(), "Clickable Workshop summary did not open Workshop")
	_expect_feedback(&"CONFIRM", &"WORKSHOP_OPEN", "Opening Workshop")
	garage.cycle_workshop_category(1)
	_expect_feedback(&"NAVIGATE", &"WORKSHOP_CATEGORY", "Changing Workshop category")
	garage.cycle_workshop_item(1)
	_expect_feedback(&"NAVIGATE", &"WORKSHOP_ITEM", "Changing Workshop item")
	var workshop_success := garage.confirm_workshop_item()
	_expect_feedback(
		&"CONFIRM" if workshop_success else &"DENIED",
		&"WORKSHOP_ACTION",
		"Applying the selected Workshop item"
	)
	garage.hide_workshop()
	_expect_feedback(&"CANCEL", &"WORKSHOP_CLOSE", "Closing Workshop")

	# Saved builds reuse the same semantic category/item/confirm controls. Save a
	# named configuration, change its setup, reload it, then verify an empty load
	# is visibly and audibly denied without mutating the active build.
	Profile.unlocked_setups.append(&"TRAIL")
	garage.show_workshop()
	while StringName(garage.get_workshop_snapshot().get(&"category", &"")) != &"BUILD":
		garage.cycle_workshop_category(1)
	_check(int(garage.get_workshop_snapshot().get(&"item_index", -1)) == 1, "Build category did not focus SAVE BUILD A")
	var saved_build := garage.confirm_workshop_item()
	_expect_last_feedback(&"CONFIRM", &"WORKSHOP_ACTION", "Saving Build A")
	_check(saved_build, "Workshop could not save Build A")
	var saved_a := Profile.get_saved_bike_build_snapshot(&"BUILD_A")
	_check(not saved_a.is_empty(), "Workshop save did not reach Profile")
	_check(
		str(saved_a.get(&"display_name", "")) == "QUARRY TRAIL // LINE CONTROL",
		"A full event-plan match did not receive a memorable event-focused build name"
	)
	_check(Profile.set_current_setup(&"TRAIL"), "Probe could not change setup before build reload")
	garage.cycle_workshop_item(-1)
	var loaded_build := garage.confirm_workshop_item()
	_expect_last_feedback(&"CONFIRM", &"WORKSHOP_ACTION", "Loading Build A")
	_check(loaded_build and Profile.current_setup == &"BALANCED", "Workshop load did not restore Build A")
	var loaded_snapshot := garage.get_workshop_snapshot()
	_check(str(loaded_snapshot.get(&"workshop_status", "")).contains("BUILD A LOADED"), "Build-load status is not explicit")
	_check(
		str(loaded_snapshot.get(&"workshop_detail", "")).contains("QUARRY TRAIL // LINE CONTROL")
		and str(loaded_snapshot.get(&"workshop_detail", "")).contains("FULL PLAN MATCH"),
		"Saved-build review does not connect the named build to its selected-event fit"
	)
	var loaded_signature := str(Profile.get_active_bike_setup_snapshot().get(&"signature", ""))
	_check(garage.focus_event_briefing(&"PINE_ENDURO"), "Probe could not compare Build A against Pine")
	var pine_build_detail := str(garage.get_workshop_snapshot().get(&"workshop_detail", ""))
	_check(
		pine_build_detail.contains("PINE RIDGE ENDURO")
		and pine_build_detail.contains("ALTERNATE")
		and pine_build_detail.contains("TRAIL + TUNE ENDURO"),
		"Saved-build review does not expose the selected event's alternate plan"
	)
	_check(str(Profile.get_active_bike_setup_snapshot().get(&"signature", "")) == loaded_signature, "Saved-build comparison mutated the active setup")
	_check(garage.focus_event_briefing(&"CIRCUIT"), "Probe could not return saved-build comparison to Quarry")
	garage.cycle_workshop_item(1)
	garage.cycle_workshop_item(1)
	var before_empty_load := str(Profile.get_active_bike_setup_snapshot().get(&"signature", ""))
	var empty_load := garage.confirm_workshop_item()
	_expect_last_feedback(&"DENIED", &"WORKSHOP_ACTION", "Rejecting empty Build B")
	_check(not empty_load, "Empty Build B unexpectedly loaded")
	_check(str(Profile.get_active_bike_setup_snapshot().get(&"signature", "")) == before_empty_load, "Empty build load mutated the active setup")
	_check(str(garage.get_workshop_snapshot().get(&"workshop_status", "")).contains("EMPTY BUILD SLOT"), "Empty-slot refusal is not explicit")
	garage.hide_workshop()

	garage.call(&"_attempt_repair")
	_expect_feedback(&"DENIED", &"GARAGE_REPAIR", "Requesting an unnecessary repair")
	garage.call(&"_unhandled_input", _action_event(InputRouter.GARAGE_LEFT))
	_expect_feedback(&"NAVIGATE", &"GARAGE_SETUP", "Changing Garage setup")
	garage.call(&"_unhandled_input", _action_event(InputRouter.EVENT_NEXT))
	_expect_feedback(&"NAVIGATE", &"GARAGE_EVENT", "Changing Garage event")
	garage.call(&"_unhandled_input", _action_event(InputRouter.TOGGLE_ASSIST))
	_expect_feedback(&"CONFIRM", &"GARAGE_ASSIST", "Changing handling assist")

	# A fresh profile has no active weekend. The visible refusal and descending
	# audio meaning must agree instead of sounding like a successful launch.
	var continued := garage.continue_weekend()
	_check(not continued, "Fresh profile unexpectedly continued a race weekend")
	_expect_feedback(&"DENIED", &"WEEKEND_CONTINUE", "Rejecting unavailable weekend continuation")

	# Return to the authored first-ride Academy and verify that a real accepted
	# launch emits confirmation only after the Garage hands off the ride request.
	garage.show_garage()
	_check(garage.focus_event_briefing(&"ACADEMY"), "Academy is absent from the Garage event list")
	garage.call(&"_confirm_selection")
	_check(_ride_requests.size() == 1, "Accepted Garage confirmation emitted no ride request")
	_expect_feedback(&"CONFIRM", &"GARAGE_RIDE", "Launching the selected ride")

	print("GARAGE INTERFACE FEEDBACK PROBE: feedback=%d ride_requests=%d workshop_success=%s builds=save+load+deny passed=%s" % [
		_feedback.size(), _ride_requests.size(), str(workshop_success), str(_failures.is_empty()),
	])
	garage.queue_free()
	await get_tree().process_frame
	if _failures.is_empty():
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("GARAGE INTERFACE FEEDBACK PROBE: %s" % failure)
	get_tree().quit(1)


func _action_event(action: StringName) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


func _on_interface_feedback_requested(kind: StringName, context: StringName) -> void:
	_feedback.append({&"kind": kind, &"context": context})


func _on_ride_requested(setup: StringName, activity: StringName) -> void:
	_ride_requests.append({&"setup": setup, &"activity": activity})


func _expect_feedback(kind: StringName, context: StringName, action_label: String) -> void:
	for entry: Dictionary in _feedback:
		if StringName(entry.get(&"kind", &"")) == kind and StringName(entry.get(&"context", &"")) == context:
			return
	_failures.append("%s emitted no %s/%s feedback" % [action_label, String(kind), String(context)])


func _expect_last_feedback(kind: StringName, context: StringName, action_label: String) -> void:
	if _feedback.is_empty():
		_failures.append("%s emitted no feedback" % action_label)
		return
	var latest: Dictionary = _feedback.back()
	if StringName(latest.get(&"kind", &"")) != kind or StringName(latest.get(&"context", &"")) != context:
		_failures.append("%s emitted %s/%s instead of %s/%s" % [
			action_label,
			String(latest.get(&"kind", &"")), String(latest.get(&"context", &"")),
			String(kind), String(context),
		])


func _check(condition: bool, failure: String) -> void:
	if not condition:
		_failures.append(failure)
