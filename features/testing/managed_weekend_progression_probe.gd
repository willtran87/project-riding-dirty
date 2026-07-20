extends Node
## End-to-end regression for the production Red Mesa weekend state flow.
##
## Definition of done:
## - solo qualifying expands to one deterministic timed result per entrant;
## - a heat qualifier advances directly to Main through an AI-only LCQ;
## - a non-qualifier's actual next playable phase is LCQ;
## - Main session rules never inject Player into an AI-only LCQ;
## - Garage exposes and dispatches the director's persisted next phase;
## - standalone MESA_MX cannot submit MESA_OPENER;
## - a managed Main transfers its classification and championship round once.

const MAIN_SCRIPT := preload("res://scenes/main.gd")
const BIKE_CONTROLLER_SCRIPT := preload("res://entities/bike/bike_controller.gd")
const PROFILE_RESULT_SIGNATURE := "MESA_MX|MESA_MX|r1|MAIN|WEEKEND_PROBE"

var _passed := true
var _garage_launch_activity: StringName = &""
var _garage_launch_count := 0


func _ready() -> void:
	Profile.persistence_enabled = false
	_run.call_deferred()


func _run() -> void:
	Profile.reset_profile_for_testing()
	Profile.persistence_enabled = false
	_validate_first_run_recommendation()
	Profile.reset_profile_for_testing()
	Profile.persistence_enabled = false
	Profile.racer_reputation = 100

	var qualified := _new_default_director()
	_advance_to_heat(qualified, 130_000_000)
	_validate_qualified_heat_skip(qualified)

	var non_qualified := _new_default_director()
	_advance_to_heat(non_qualified, 210_000_000)
	_validate_non_qualified_lcq(non_qualified)

	var main_composer := MAIN_SCRIPT.new()
	_validate_main_session_rules(main_composer, qualified, non_qualified)
	await _validate_garage_continue_action(qualified, non_qualified)
	_validate_profile_championship_boundary(qualified)
	_validate_finish_grace_pacing()
	_validate_garage_runtime_projection()
	main_composer.free()

	print("MANAGED WEEKEND PROGRESSION PROBE: garage_launches=%d final_phase=%s passed=%s" % [
		_garage_launch_count, String(Profile.get_race_weekend_director().get_current_phase()), str(_passed),
	])
	get_tree().quit(0 if _passed else 1)


func _validate_first_run_recommendation() -> void:
	_check(Profile.is_first_run_onboarding_active(), "fresh profile exposes first-run onboarding")
	_check(RaceEventCatalog.get_recommended_event() == &"ACADEMY", "first ride recommends the existing Academy")
	_check(Profile.complete_first_run_onboarding(), "first-run onboarding flag can complete without blocking play")
	_check(not Profile.is_first_run_onboarding_active(), "first-run completion persists in profile state")
	_check(RaceEventCatalog.get_recommended_event() == &"CIRCUIT", "post-onboarding progression recommends the first race")


func _new_default_director() -> RaceWeekendDirector:
	var director := RaceWeekendDirector.create(RaceEventCatalog.get_default_weekend_config())
	director.start_weekend()
	return director


func _advance_to_heat(director: RaceWeekendDirector, player_qualifying_usec: int) -> void:
	var all_ids := director.get_session_entrant_ids(RaceWeekendDirector.PRACTICE)
	_check(director.submit_session_result(_classification(all_ids)), "practice result accepted")
	_check(director.get_current_phase() == RaceWeekendDirector.QUALIFYING, "practice advances to qualifying")

	var player_qualifying: Array[Dictionary] = [{
		&"rider_id": &"PLAYER",
		&"display_name": "YOU",
		&"is_player": true,
		&"status": &"FINISHED",
		&"finish_usec": player_qualifying_usec,
		&"penalty_usec": 0,
		&"effective_time_usec": player_qualifying_usec,
		&"source_token": "PLAYER_SOLO_RUN",
	}]
	var first := director.prepare_session_classification(RaceWeekendDirector.QUALIFYING, player_qualifying)
	var second := director.prepare_session_classification(RaceWeekendDirector.QUALIFYING, player_qualifying)
	_check(first == second, "qualifying AI timing is deterministic")
	_check(first.size() == all_ids.size(), "qualifying contains the whole field", "size=%d expected=%d" % [first.size(), all_ids.size()])
	_check(_unique_rider_count(first) == all_ids.size(), "qualifying contains each entrant exactly once")
	_check(_all_entries_have_timing(first), "qualifying entries expose valid timing fields")
	var prepared_player := _entry_for(first, &"PLAYER")
	_check(str(prepared_player.get(&"source_token", "")) == "PLAYER_SOLO_RUN", "qualifying preserves player result fields")

	_check(director.submit_session_result(player_qualifying), "solo qualifying result accepted")
	_check(director.get_current_phase() == RaceWeekendDirector.HEAT, "qualifying advances to heat")
	var stored := director.get_session_result(RaceWeekendDirector.QUALIFYING)
	_check(stored == first, "stored qualifying exactly matches deterministic prepared field")


func _validate_qualified_heat_skip(director: RaceWeekendDirector) -> void:
	var heat_order := director.qualifying_order.duplicate()
	if heat_order.has(&"PLAYER"):
		heat_order.erase(&"PLAYER")
	heat_order.push_front(&"PLAYER")
	var result_count_before := director.session_results.size()
	_check(director.submit_session_result(_classification(heat_order)), "qualified heat accepted")
	_check(director.heat_qualifiers.has(&"PLAYER"), "player transfers from heat")
	_check(director.get_current_phase() == RaceWeekendDirector.MAIN, "heat qualifier skips playable LCQ and reaches Main")
	var ai_lcq := director.get_session_result(RaceWeekendDirector.LCQ)
	_check(ai_lcq.size() == director.lcq_candidates.size(), "AI-only LCQ resolves the full candidate field")
	_check(_entry_for(ai_lcq, &"PLAYER").is_empty(), "qualified player is absent from AI-only LCQ")
	_check(director.get_main_grid().has(&"PLAYER") and director.get_main_grid().size() == 10, "qualified player enters ten-rider Main grid")
	var result_count_after := director.session_results.size()
	_check(result_count_after == result_count_before + 2, "heat and auto-LCQ store exactly one result each")
	_check(
		not director.submit_session_result(_classification(heat_order), RaceWeekendDirector.HEAT),
		"completed heat cannot transfer twice"
	)
	_check(director.session_results.size() == result_count_after, "duplicate heat does not mutate session results")


func _validate_non_qualified_lcq(director: RaceWeekendDirector) -> void:
	var heat_order := director.qualifying_order.duplicate()
	heat_order.erase(&"PLAYER")
	heat_order.insert(mini(6, heat_order.size()), &"PLAYER")
	_check(director.submit_session_result(_classification(heat_order)), "non-qualified heat accepted")
	_check(not director.heat_qualifiers.has(&"PLAYER"), "seventh-place player misses heat transfer")
	_check(director.get_current_phase() == RaceWeekendDirector.LCQ, "non-qualifier's actual next phase is LCQ")
	var lcq_ids := director.get_session_entrant_ids(RaceWeekendDirector.LCQ)
	_check(lcq_ids.has(&"PLAYER"), "non-qualified player is in LCQ field")
	var lcq_finish := lcq_ids.duplicate()
	lcq_finish.erase(&"PLAYER")
	lcq_finish.push_front(&"PLAYER")
	_check(director.submit_session_result(_classification(lcq_finish)), "player LCQ result accepted")
	_check(director.lcq_qualifiers.has(&"PLAYER"), "top-four LCQ player transfers")
	_check(director.get_current_phase() == RaceWeekendDirector.MAIN, "successful LCQ advances to Main")
	_check(director.get_main_grid().has(&"PLAYER"), "LCQ transfer appears in Main grid")


func _validate_main_session_rules(main_composer: Node, qualified: RaceWeekendDirector, non_qualified_after_lcq: RaceWeekendDirector) -> void:
	main_composer.set("_weekend_director", qualified)
	var stale_lcq := RaceEventCatalog.get_session_config(&"MESA_LCQ")
	main_composer.call(&"_apply_career_session_rules", &"MESA_LCQ", stale_lcq)
	_check(not bool(stale_lcq.rules.get(&"weekend_managed", true)), "qualified player cannot launch stale managed LCQ")
	_check(not _string_name_array(stale_lcq.rules.get(&"entrant_ids", [])).has(&"PLAYER"), "Main does not reinsert qualified player into LCQ")

	var managed_main := RaceEventCatalog.get_session_config(&"MESA_MX")
	main_composer.call(&"_apply_career_session_rules", &"MESA_MX", managed_main)
	var main_ids := _string_name_array(managed_main.rules.get(&"entrant_ids", []))
	_check(bool(managed_main.rules.get(&"weekend_managed", false)), "director Main config is managed")
	_check(main_ids.count(&"PLAYER") == 1 and main_ids.size() == qualified.get_main_grid().size(), "managed Main receives exact transferred field")

	var fresh_non_qualified := _new_default_director()
	_advance_to_heat(fresh_non_qualified, 210_000_000)
	var heat_order := fresh_non_qualified.qualifying_order.duplicate()
	heat_order.erase(&"PLAYER")
	heat_order.insert(mini(6, heat_order.size()), &"PLAYER")
	fresh_non_qualified.submit_session_result(_classification(heat_order))
	main_composer.set("_weekend_director", fresh_non_qualified)
	var managed_lcq := RaceEventCatalog.get_session_config(&"MESA_LCQ")
	main_composer.call(&"_apply_career_session_rules", &"MESA_LCQ", managed_lcq)
	var lcq_ids := _string_name_array(managed_lcq.rules.get(&"entrant_ids", []))
	var expected_lcq_ids := fresh_non_qualified.get_session_entrant_ids(RaceWeekendDirector.LCQ)
	_check(bool(managed_lcq.rules.get(&"weekend_managed", false)), "non-qualifier receives managed LCQ")
	_check(lcq_ids.count(&"PLAYER") == 1 and _same_rider_set(lcq_ids, expected_lcq_ids), "managed LCQ contains the exact candidate field once")
	# Keep the already-completed non-qualified branch alive for serialization coverage.
	_check(non_qualified_after_lcq.get_current_phase() == RaceWeekendDirector.MAIN, "non-qualified branch remains at Main after LCQ transfer")


func _validate_garage_continue_action(qualified: RaceWeekendDirector, _non_qualified_after_lcq: RaceWeekendDirector) -> void:
	Profile.set_race_weekend_snapshot(qualified.to_dictionary())
	Profile.racer_reputation = 100
	var garage := GarageUi.new()
	garage.ride_requested.connect(_on_garage_ride_requested)
	add_child(garage)
	await get_tree().process_frame
	garage.show_garage()
	var action := garage.get_continue_weekend_snapshot()
	var action_label := garage.get_node_or_null("GarageRoot/ContinueWeekendAction") as Label
	_check(StringName(action.get(&"phase", &"")) == RaceWeekendDirector.MAIN, "Garage reads director's actual Main phase")
	_check(StringName(action.get(&"activity", &"")) == &"MESA_MX", "Garage maps Main phase to MESA_MX")
	_check(action_label != null and action_label.visible and action_label.text.contains("CONTINUE"), "Continue Weekend action is production-visible")
	_check(garage.continue_weekend(), "visible Continue Weekend action dispatches")
	_check(_garage_launch_activity == &"MESA_MX", "Continue Weekend launches director's actual event")

	var lcq_director := _new_default_director()
	_advance_to_heat(lcq_director, 210_000_000)
	var heat_order := lcq_director.qualifying_order.duplicate()
	heat_order.erase(&"PLAYER")
	heat_order.insert(mini(6, heat_order.size()), &"PLAYER")
	lcq_director.submit_session_result(_classification(heat_order))
	Profile.set_race_weekend_snapshot(lcq_director.to_dictionary())
	garage.show_garage()
	action = garage.get_continue_weekend_snapshot()
	_garage_launch_activity = &""
	_check(StringName(action.get(&"phase", &"")) == RaceWeekendDirector.LCQ, "Garage reads director's actual LCQ phase")
	_check(garage.continue_weekend() and _garage_launch_activity == &"MESA_LCQ", "Continue Weekend launches LCQ for non-qualifier")

	garage.queue_free()
	await get_tree().process_frame


func _validate_profile_championship_boundary(qualified: RaceWeekendDirector) -> void:
	Profile.reset_profile_for_testing()
	Profile.persistence_enabled = false
	var standalone_classification := _classification(qualified.get_main_grid())
	var standalone := _profile_result(standalone_classification, false)
	var standalone_identity := Profile.begin_race_run(
		&"MESA_MX",
		str(standalone.get(&"signature", "")),
		_weekend_settlement_context(standalone)
	)
	standalone[&"run_id"] = str(standalone_identity.get(&"run_id", ""))
	standalone[&"signature"] = str(standalone_identity.get(&"signature", ""))
	var standalone_statistics_before := CompetitiveRunSignature.canonical_string(
		Profile.get_race_statistics()
	)
	var standalone_event_before := CompetitiveRunSignature.canonical_string(
		Profile.get_event_record(&"MESA_MX")
	)
	var managed_token_spoof := standalone.duplicate(true)
	managed_token_spoof[&"weekend_id"] = &"RED_MESA_OPEN"
	managed_token_spoof[&"weekend_phase"] = &"MAIN"
	managed_token_spoof[&"weekend_managed"] = true
	var managed_token_rejection: Dictionary = Profile.record_race_result(managed_token_spoof, false)
	_check(
		StringName(managed_token_rejection.get(&"reason", &"")) == &"STALE_OR_ABANDONED_RUN"
		and bool(managed_token_rejection.get(&"invalid_identity", false))
		and CompetitiveRunSignature.canonical_string(Profile.get_race_statistics())
			== standalone_statistics_before
		and CompetitiveRunSignature.canonical_string(Profile.get_event_record(&"MESA_MX"))
			== standalone_event_before
		and Profile.get_championship_service().completed_round_count() == 0,
		"standalone MESA token cannot be promoted into managed Main authority"
	)
	var standalone_summary: Dictionary = Profile.record_race_result(standalone, false)
	_check(bool(standalone_summary.get(&"accepted", false)), "standalone MESA_MX still records normal event result")
	_check(Profile.get_championship_service().completed_round_count() == 0, "standalone MESA_MX cannot record MESA_OPENER")
	var spoofed_managed := _profile_result(standalone_classification, true)
	var spoofed_identity := Profile.begin_race_run(
		&"MESA_MX",
		str(spoofed_managed.get(&"signature", "")),
		_weekend_settlement_context(spoofed_managed)
	)
	spoofed_managed[&"run_id"] = str(spoofed_identity.get(&"run_id", ""))
	spoofed_managed[&"signature"] = str(spoofed_identity.get(&"signature", ""))
	Profile.record_race_result(spoofed_managed, false)
	_check(
		Profile.get_championship_service().completed_round_count() == 0,
		"managed metadata cannot bypass the persisted weekend director"
	)

	Profile.reset_profile_for_testing()
	Profile.persistence_enabled = false
	Profile.set_race_weekend_snapshot(qualified.to_dictionary())
	var managed_classification := _classification(qualified.get_main_grid(), true)
	var managed := _profile_result(managed_classification, true)
	var managed_identity := Profile.begin_race_run(
		&"MESA_MX",
		str(managed.get(&"signature", "")),
		_weekend_settlement_context(managed)
	)
	managed[&"run_id"] = str(managed_identity.get(&"run_id", ""))
	managed[&"signature"] = str(managed_identity.get(&"signature", ""))
	var accepted: Dictionary = Profile.record_race_result(managed, false)
	var duplicate: Dictionary = Profile.record_race_result(managed, false)
	var restored: Variant = Profile.get_race_weekend_director()
	var final_classification: Array[Dictionary] = restored.get_final_classification()
	_check(bool(accepted.get(&"accepted", false)), "managed Main result accepted")
	_check(bool(duplicate.get(&"duplicate", false)), "managed Main duplicate rejected")
	_check(Profile.get_championship_service().completed_round_count() == 1, "managed Main records championship round once")
	_check(restored.is_complete() and final_classification.size() == qualified.get_main_grid().size(), "managed Main completes persisted weekend once")
	_check(_unique_rider_count(final_classification) == final_classification.size(), "final transferred field has no duplicate riders")
	for racer: Dictionary in final_classification:
		_check(str(racer.get(&"transfer_token", "")) == String(racer.get(&"rider_id", &"")), "classification preserves transferred rider fields")


func _validate_finish_grace_pacing() -> void:
	var expected := {
		&"MESA_PRACTICE": 5.0,
		&"MESA_QUALIFYING": 0.0,
		&"MESA_HEAT": 6.0,
		&"MESA_LCQ": 5.0,
		&"MESA_MX": 7.0,
		&"MESA_ENDURANCE": 8.0,
		&"QUARRY_HILLCLIMB": 0.0,
	}
	for event_id: StringName in expected:
		var config := RaceEventCatalog.get_session_config(event_id)
		_check(
			is_equal_approx(config.finish_grace_seconds, float(expected[event_id])),
			"%s uses bounded post-finish pacing" % String(event_id),
			"actual=%.1f expected=%.1f" % [config.finish_grace_seconds, float(expected[event_id])]
		)
	var bounded_default := RaceSessionConfig.from_dictionary({&"opponent_count": 11})
	var bounded_legacy := RaceSessionConfig.from_dictionary({&"opponent_count": 11, &"finish_grace_seconds": 18.0})
	_check(is_equal_approx(bounded_default.finish_grace_seconds, 6.0), "unspecified field race uses six-second finish grace")
	_check(is_equal_approx(bounded_legacy.finish_grace_seconds, 8.0), "legacy finish grace is capped at eight seconds")


func _validate_garage_runtime_projection() -> void:
	Profile.set_bike_tune({
		&"gearing": 0.65, &"tire_grip": 0.25, &"suspension_stiffness": 0.15,
		&"suspension_damping": 0.20, &"preload": 0.15, &"brake_bias": 0.0,
	})
	var snapshot: Dictionary = Profile.get_active_bike_setup_snapshot()
	var garage := GarageUi.new()
	var projection: Dictionary = garage.get_setup_runtime_snapshot(&"ATTACK")
	var bike: Variant = BIKE_CONTROLLER_SCRIPT.new()
	bike.apply_setup(&"ATTACK")
	bike.apply_racing_build(snapshot)
	bike.apply_condition(Profile.bike_condition)
	for property_name: StringName in [&"engine_force", &"lateral_grip", &"spring_stiffness", &"maximum_speed_mps"]:
		_check(
			is_equal_approx(float(bike.get(property_name)), float(projection.get(property_name, -1.0))),
			"Garage %s derives from the live tuned-bike multiplier" % String(property_name)
		)
	bike.free()
	garage.free()


func _profile_result(classification: Array[Dictionary], managed: bool) -> Dictionary:
	var player := _entry_for(classification, &"PLAYER")
	return {
		&"run_id": "",
		&"signature": PROFILE_RESULT_SIGNATURE,
		&"event_id": &"MESA_MX",
		&"round_id": &"MESA_OPENER",
		&"valid": true,
		&"player_position": int(player.get(&"position", 1)),
		&"player_time_usec": int(player.get(&"finish_usec", 220_000_000)),
		&"player_penalty_usec": 0,
		&"medal": &"FINISHER",
		&"classification": classification,
		&"weekend_id": &"RED_MESA_OPEN" if managed else &"",
		&"weekend_phase": &"MAIN" if managed else &"",
		&"weekend_managed": managed,
	}


func _weekend_settlement_context(result: Dictionary) -> Dictionary:
	return {
		&"weekend_id": StringName(result.get(&"weekend_id", &"")),
		&"weekend_phase": StringName(result.get(&"weekend_phase", &"")),
		&"weekend_managed": bool(result.get(&"weekend_managed", false)),
	}


func _classification(rider_ids: Array[StringName], transfer_tokens: bool = false) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for index: int in rider_ids.size():
		var rider_id := rider_ids[index]
		var entry := {
			&"rider_id": rider_id,
			&"display_name": "YOU" if rider_id == &"PLAYER" else String(rider_id),
			&"is_player": rider_id == &"PLAYER",
			&"position": index + 1,
			&"status": &"FINISHED",
			&"finish_usec": 200_000_000 + index * 1_000_000,
			&"penalty_usec": 0,
			&"effective_time_usec": 200_000_000 + index * 1_000_000,
		}
		if transfer_tokens:
			entry[&"transfer_token"] = String(rider_id)
		output.append(entry)
	return output


func _entry_for(classification: Array[Dictionary], rider_id: StringName) -> Dictionary:
	for racer: Dictionary in classification:
		if StringName(racer.get(&"rider_id", &"")) == rider_id:
			return racer
	return {}


func _unique_rider_count(classification: Array[Dictionary]) -> int:
	var unique: Dictionary = {}
	for racer: Dictionary in classification:
		unique[StringName(racer.get(&"rider_id", &""))] = true
	return unique.size()


func _all_entries_have_timing(classification: Array[Dictionary]) -> bool:
	for racer: Dictionary in classification:
		if (
				StringName(racer.get(&"status", &"")) != &"FINISHED"
				or int(racer.get(&"finish_usec", -1)) <= 0
				or int(racer.get(&"effective_time_usec", -1)) <= 0
			):
			return false
	return true


func _same_rider_set(first: Array[StringName], second: Array[StringName]) -> bool:
	if first.size() != second.size():
		return false
	for rider_id: StringName in first:
		if not second.has(rider_id):
			return false
	return true


func _string_name_array(value: Variant) -> Array[StringName]:
	var output: Array[StringName] = []
	if value is Array or value is PackedStringArray:
		for entry: Variant in value:
			output.append(StringName(entry))
	return output


func _on_garage_ride_requested(_setup: StringName, activity: StringName) -> void:
	_garage_launch_activity = activity
	_garage_launch_count += 1


func _check(condition: bool, label: String, details: String = "") -> void:
	var suffix := "" if details.is_empty() else "  //  %s" % details
	print("MANAGED WEEKEND CHECK: %s passed=%s%s" % [label, str(condition), suffix])
	if condition:
		return
	_passed = false
	push_error("MANAGED WEEKEND PROGRESSION: %s failed.%s" % [label, suffix])
