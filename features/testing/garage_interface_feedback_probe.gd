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
	_check(
		str(fresh_progression.get(&"tour", "")).contains("QUARRY TRAIL READY")
		and str(fresh_progression.get(&"tour", "")).contains("ACADEMY OPTIONAL")
		and not str(fresh_progression.get(&"tour", "")).contains("ACADEMY RECOMMENDED"),
		"Fresh Garage still gives optional Academy stronger priority than event one"
	)
	var fresh_sponsor: Dictionary = garage.get_event_briefing_presentation_snapshot().get(&"sponsor", {}) as Dictionary
	_check(
		StringName(fresh_sponsor.get(&"sponsor_id", &"")) == &"DUSTLINE"
		and str(fresh_sponsor.get(&"rank_title", "")) == "PROSPECT"
		and str(fresh_progression.get(&"context", "")).contains("DUSTLINE PROSPECT"),
		"Fresh Garage does not preview the first event's sponsor relationship"
	)
	var fresh_summary := str(fresh_progression.get(&"summary", ""))
	_check(fresh_summary.contains("FIRST ROUTE") and fresh_summary.contains("EVENT 01"), "Fresh Garage summary does not identify the first route")
	_check(fresh_summary.contains("CLEAR 2 QUARRY EVENTS"), "Fresh Garage summary omits the next concrete unlock goal")
	_check(not fresh_summary.contains("PHASE  PRACTICE"), "Fresh Garage summary still presents a later weekend as active")
	var fresh_strategy := garage.get_event_strategy_presentation_snapshot()
	var fresh_decision := fresh_strategy.get(&"setup_decision", {}) as Dictionary
	var fresh_metrics := fresh_decision.get(&"metrics", {}) as Dictionary
	_check(StringName(fresh_strategy.get(&"event_id", &"")) == &"CIRCUIT", "Fresh strategy guidance targets the wrong event")
	_check(StringName(fresh_strategy.get(&"recommended_setup", &"")) == &"BALANCED", "First event does not recommend the readable baseline kit")
	_check(StringName(fresh_strategy.get(&"recommended_tune", &"")) == &"BALANCED", "First event does not recommend the readable baseline tune")
	_check(bool(fresh_strategy.get(&"full_match", false)), "Fresh baseline build is not recognized as matching the first event plan")
	_check(
		StringName(fresh_decision.get(&"equipped_setup", &"")) == &"BALANCED"
		and StringName(fresh_decision.get(&"selected_setup", &"")) == &"BALANCED"
		and StringName(fresh_decision.get(&"recommended_setup", &"")) == &"BALANCED"
		and StringName(fresh_decision.get(&"state", &"")) == &"READY"
		and str(fresh_decision.get(&"label", "")).contains("EQUIPPED + EVENT PLAN"),
		"Fresh Garage does not unify equipped, viewed, and recommended setup roles"
	)
	_check(
		fresh_metrics.size() == 4
		and is_equal_approx(
			float((fresh_metrics.get(&"POWER", {}) as Dictionary).get(&"equipped", -1.0)),
			float((fresh_metrics.get(&"POWER", {}) as Dictionary).get(&"recommended", -2.0))
		),
		"Fresh full-match plan does not expose equivalent three-way runtime bars"
	)
	_check(
		str(fresh_strategy.get(&"label", "")).contains("EVENT PLAN")
		and str(fresh_strategy.get(&"label", "")).ends_with("MATCH")
		and not str(fresh_strategy.get(&"label", "")).ends_with("KIT MATCH"),
		"First event strategy is absent or does not present its complete ready state: %s" % str(fresh_strategy.get(&"label", ""))
	)
	var balanced_comparison := garage.get_setup_comparison_snapshot(&"BALANCED")
	var trail_comparison := garage.get_setup_comparison_snapshot(&"TRAIL")
	var attack_comparison := garage.get_setup_comparison_snapshot(&"ATTACK")
	var trail_deltas := trail_comparison.get(&"deltas", {}) as Dictionary
	var attack_deltas := attack_comparison.get(&"deltas", {}) as Dictionary
	_check(
		str(balanced_comparison.get(&"label", "")).contains("REFERENCE KIT")
		and int((balanced_comparison.get(&"deltas", {}) as Dictionary).get(&"drive_percent", 1)) == 0,
		"Balanced setup is not presented as the stable comparison reference"
	)
	_check(
		int(trail_deltas.get(&"drive_percent", 0)) == -15
		and int(trail_deltas.get(&"grip_percent", 0)) == 13
		and int(trail_deltas.get(&"speed_percent", 0)) == -8
		and str(trail_comparison.get(&"label", "")).contains("GRIP +13%"),
		"Trail comparison does not quantify its exact grip-for-speed tradeoff"
	)
	_check(
		int(attack_deltas.get(&"drive_percent", 0)) == 8
		and int(attack_deltas.get(&"grip_percent", 0)) == -10
		and int(attack_deltas.get(&"speed_percent", 0)) == 10
		and str(attack_comparison.get(&"label", "")).contains("SPEED +10%"),
		"Attack comparison does not quantify its exact pace-for-grip tradeoff"
	)
	var comparison_label := garage.get_node_or_null("GarageRoot/SetupComparison") as Label
	_check(
		comparison_label != null and comparison_label.text == str(balanced_comparison.get(&"label", "")),
		"The visible setup card does not use the authoritative comparison projection"
	)
	var strategy_signature := str(Profile.get_active_bike_setup_snapshot().get(&"signature", ""))
	_check(garage.focus_event_briefing(&"PINE_ENDURO"), "Pine Enduro is absent from the Garage event list")
	var pine_strategy := garage.get_event_strategy_presentation_snapshot()
	var pine_decision := pine_strategy.get(&"setup_decision", {}) as Dictionary
	var pine_recommended_delta := pine_decision.get(&"recommended_vs_equipped", {}) as Dictionary
	var pine_sponsor: Dictionary = garage.get_event_briefing_presentation_snapshot().get(&"sponsor", {}) as Dictionary
	_check(
		StringName(pine_strategy.get(&"recommended_setup", &"")) == &"TRAIL"
		and StringName(pine_strategy.get(&"recommended_tune", &"")) == &"ENDURO",
		"Pine strategy does not expose its traction and compliance tradeoff"
	)
	_check(not bool(pine_strategy.get(&"full_match", true)), "Baseline build is incorrectly presented as the Pine-specific plan")
	_check(
		StringName(pine_decision.get(&"equipped_setup", &"")) == &"BALANCED"
		and StringName(pine_decision.get(&"selected_setup", &"")) == &"BALANCED"
		and StringName(pine_decision.get(&"recommended_setup", &"")) == &"TRAIL"
		and str(pine_decision.get(&"label", "")).contains("EVENT TRAIL + ENDURO"),
		"Pine decision view does not distinguish the equipped alternate from the event plan"
	)
	_check(
		int(pine_recommended_delta.get(&"grip_percent", 0)) > 0
		and int(pine_recommended_delta.get(&"suspension_percent", 0)) < 0
		and str((pine_decision.get(&"sources", {}) as Dictionary).get(&"tune", "")).contains("SUSPENSION"),
		"Pine plan does not compare the complete Trail+Enduro runtime or explain tune ownership"
	)
	var decision_label := garage.get_node_or_null("GarageRoot/SetupDecision") as Label
	_check(
		decision_label != null and decision_label.text == str(pine_decision.get(&"label", "")),
		"Visible setup decision strip diverges from its authoritative snapshot"
	)
	_check(StringName(pine_sponsor.get(&"sponsor_id", &"")) == &"WILDBRUSH", "Pine does not introduce its terrain sponsor")
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
	var rhythm_sponsor: Dictionary = garage.get_event_briefing_presentation_snapshot().get(&"sponsor", {}) as Dictionary
	_check(
		StringName(rhythm_strategy.get(&"recommended_setup", &"")) == &"ATTACK"
		and StringName(rhythm_strategy.get(&"recommended_tune", &"")) == &"RHYTHM",
		"Rhythm strategy does not expose its jump-support tradeoff"
	)
	_check(StringName(rhythm_sponsor.get(&"sponsor_id", &"")) == &"SUNDOWN", "Rhythm does not introduce its style sponsor")
	_check(
		int(rhythm_strategy.get(&"recommended_setup_price", -1)) == 1_500
		and int(rhythm_strategy.get(&"recommended_setup_shortfall", -1)) == 1_500
		and str(rhythm_strategy.get(&"label", "")).contains("KIT $1500 AWAY"),
		"Attack strategy does not disclose its exact progression price"
	)
	Profile.cash = 750
	_check(Profile.purchase_setup(&"TRAIL"), "Probe could not unlock Trail for one-action event-plan coverage")
	_check(Profile.set_current_setup(&"BALANCED"), "Probe could not restore the pre-plan Balanced kit")
	_check(garage.focus_event_briefing(&"PINE_ENDURO"), "Probe could not revisit Pine for plan application")
	_check(garage.apply_recommended_event_plan(), "Owned Pine event plan was not applied in one action")
	_check(
		Profile.current_setup == &"TRAIL" and StringName(garage.get_event_strategy_presentation_snapshot().get(&"active_tune", &"")) == &"ENDURO",
		"One-action event plan did not apply both the recommended kit and tune"
	)
	_check(garage.undo_recommended_event_plan(), "Applied event plan could not be undone")
	_check(
		Profile.current_setup == &"BALANCED" and StringName(garage.get_event_strategy_presentation_snapshot().get(&"active_tune", &"")) == &"BALANCED",
		"Plan undo did not restore the complete prior configuration"
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

	# An official debrief routes the next Workshop visit to the exact last/PB
	# comparison. Applying it restores strategy only and keeps live bike wear.
	Profile.unlocked_setups.append(&"ATTACK")
	var history_plan := {
		&"version": 1, &"setup_id": &"ATTACK", &"bike_id": &"TYKE_125",
		&"selected_class": &"LITE_125", &"installed_parts": {},
		&"tune": {&"gearing": 0.65, &"tire_grip": 0.25, &"suspension_stiffness": 0.15, &"suspension_damping": 0.20, &"preload": 0.15, &"brake_bias": 0.0},
		&"livery_id": &"FACTORY", &"condition_percent": 100,
		&"assist_mode": &"SPORT", &"difficulty": 1, &"transmission_mode": &"AUTOMATIC",
		&"crash_support_mode": &"STANDARD", &"weather": &"CLEAR", &"surface": &"PACKED",
	}
	var history_run := {
		&"result_id": "garage-history-probe", &"position": 2, &"status": &"FINISHED", &"valid": true,
		&"effective_time_usec": 118_000_000, &"medal": &"GOLD", &"flow_uses": 3,
		&"sector_times_usec": [59_000_000, 59_000_000], &"plan": history_plan,
	}
	Profile.event_records[&"CIRCUIT"] = {&"recent_runs": [history_run], &"personal_best_run": history_run}
	var worn_build := Profile.get_bike_build_snapshot(&"TYKE_125")
	worn_build[&"condition"] = 0.61
	worn_build[&"odometer_meters"] = 55.0
	Profile.owned_bike_builds[&"TYKE_125"] = worn_build
	Profile.bike_condition = 61
	garage.set_rider_debrief({&"focus_id": &"SECTOR_PACE", &"next_objective": "GAIN THE COSTLIEST SPLIT"})
	garage.show_workshop()
	var history_workshop := garage.get_workshop_snapshot()
	_check(StringName(history_workshop.get(&"category", &"")) == &"HISTORY", "Debrief did not route Workshop to result history")
	_check(str(history_workshop.get(&"workshop_item", "")).contains("PREVIOUS RUN"), "History Workshop does not identify the previous run")
	_check(str(history_workshop.get(&"workshop_action", "")).contains("APPLY RECORDED PLAN"), "Available historical plan has no apply shortcut")
	_check(garage.confirm_workshop_item(), "Workshop could not apply the previous official plan")
	var history_applied := Profile.get_bike_build_snapshot(&"TYKE_125")
	_check(
		Profile.current_setup == &"ATTACK"
		and is_equal_approx(float(history_applied.get(&"condition", -1.0)), 0.61)
		and is_equal_approx(float(history_applied.get(&"odometer_meters", -1.0)), 55.0)
		and str(garage.get_workshop_snapshot().get(&"workshop_status", "")).contains("LIVE WEAR AND DISTANCE PRESERVED"),
		"History apply did not restore strategy while preserving and explaining live wear"
	)
	garage.cycle_workshop_item(1)
	garage.cycle_workshop_item(1)
	_check(
		str(garage.get_workshop_snapshot().get(&"workshop_item", "")).contains("PIN PREVIOUS"),
		"History Workshop does not expose a durable custom-reference action"
	)
	_check(garage.confirm_workshop_item(), "Workshop could not pin the previous official run")
	var pinned_history := garage.get_event_history_presentation_snapshot(&"CIRCUIT")
	_check(
		StringName(pinned_history.get(&"reference_kind", &"")) == &"PINNED"
		and str((pinned_history.get(&"pinned_run", {}) as Dictionary).get(&"result_id", "")) == "garage-history-probe",
		"Pinned Workshop result did not become the durable comparison reference"
	)
	garage.cycle_workshop_item(1)
	garage.cycle_workshop_item(1)
	garage.cycle_workshop_item(1)
	var sector_review := garage.get_workshop_snapshot()
	_check(
		str(sector_review.get(&"workshop_item", "")).contains("SECTOR 01")
		and str(sector_review.get(&"workshop_detail", "")).contains("LATEST")
		and str(sector_review.get(&"workshop_detail", "")).contains("REFERENCE")
		and str(sector_review.get(&"workshop_detail", "")).contains("DELTA")
		and str(sector_review.get(&"workshop_build", "")).contains("NEXT"),
		"History Workshop does not provide a complete, actionable sector drilldown"
	)
	var before_sector_read: Dictionary = Profile._profile_to_dictionary()
	_check(garage.confirm_workshop_item(), "Workshop could not acknowledge a sector review")
	_check(
		Profile._profile_to_dictionary() == before_sector_read
		and str(garage.get_workshop_snapshot().get(&"workshop_status", "")).contains("SECTOR 01 REVIEWED"),
		"Read-only sector review mutated the profile or failed to confirm"
	)
	garage.hide_workshop()
	_check(Profile.set_current_setup(&"BALANCED"), "Probe could not restore Balanced after history apply")
	_check(Profile.set_bike_tune({}), "Probe could not restore the baseline tune after history apply")

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
	_check(Profile.set_current_setup(&"TRAIL"), "Probe could not prepare a contrasting Build B")
	_check(
		bool(Profile.save_current_bike_build(&"BUILD_B", "TRAIL CONTROL").get(&"accepted", false)),
		"Probe could not save a contrasting Build B"
	)
	_check(bool(Profile.load_saved_bike_build(&"BUILD_A").get(&"accepted", false)), "Probe could not restore Build A before comparison")
	var build_items: Array = garage.call(&"_get_workshop_items", &"BUILD")
	var compare_ab: Dictionary = {}
	for candidate_value: Variant in build_items:
		var candidate := candidate_value as Dictionary
		if StringName(candidate.get(&"action_id", &"")) == &"COMPARE" and str(candidate.get(&"slot_label", "")) == "A / B":
			compare_ab = candidate
			break
	_check(not compare_ab.is_empty(), "Saved Build A/B comparison is not available")
	var compare_projection: Dictionary = garage.call(&"_saved_build_projection", compare_ab)
	_check(
		str(compare_projection.get(&"title", "")).contains("BUILD A / B")
		and str(compare_projection.get(&"detail", "")).contains("REFERENCE")
		and str(compare_projection.get(&"build", "")).contains("VS REFERENCE")
		and str(compare_projection.get(&"action", "")).contains("NEITHER BUILD IS APPLIED"),
		"Saved-build pair review does not quantify both configurations without ambiguity"
	)
	var before_build_compare: Dictionary = Profile._profile_to_dictionary()
	_check(garage.call(&"_apply_saved_build_action", compare_ab), "Saved-build pair review could not be acknowledged")
	_check(Profile._profile_to_dictionary() == before_build_compare, "Saved-build pair review mutated the active configuration")
	garage.hide_workshop()

	garage.call(&"_attempt_repair")
	_expect_feedback(&"DENIED", &"GARAGE_REPAIR", "Requesting an unnecessary repair")
	garage.call(&"_unhandled_input", _action_event(InputRouter.GARAGE_LEFT))
	_expect_feedback(&"NAVIGATE", &"GARAGE_SETUP", "Changing Garage setup")
	garage.call(&"_unhandled_input", _action_event(InputRouter.GARAGE_LEFT))
	var setup_name := garage.get_node_or_null("GarageRoot/SetupName") as Label
	_check(
		setup_name != null
		and setup_name.text == "ATTACK KIT"
		and is_equal_approx(setup_name.offset_left, -110.0)
		and is_equal_approx(setup_name.offset_top, -200.0),
		"Rapid setup paging did not preserve the fixed setup-title card rect"
	)
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
