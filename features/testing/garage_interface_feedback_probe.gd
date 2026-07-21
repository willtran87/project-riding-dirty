extends Node
## Real Garage/Workshop action feedback across success, navigation and refusal.

const GARAGE_SCENE := preload("res://features/garage/garage_ui.tscn")

var _failures: Array[String] = []
var _feedback: Array[Dictionary] = []
var _ride_requests: Array[Dictionary] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	Profile.persistence_enabled = false
	Profile.reset_profile_for_testing()
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
	_check(not Profile.get_saved_bike_build_snapshot(&"BUILD_A").is_empty(), "Workshop save did not reach Profile")
	_check(Profile.set_current_setup(&"TRAIL"), "Probe could not change setup before build reload")
	garage.cycle_workshop_item(-1)
	var loaded_build := garage.confirm_workshop_item()
	_expect_last_feedback(&"CONFIRM", &"WORKSHOP_ACTION", "Loading Build A")
	_check(loaded_build and Profile.current_setup == &"BALANCED", "Workshop load did not restore Build A")
	var loaded_snapshot := garage.get_workshop_snapshot()
	_check(str(loaded_snapshot.get(&"workshop_status", "")).contains("BUILD A LOADED"), "Build-load status is not explicit")
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
