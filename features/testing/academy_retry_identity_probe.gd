extends Node
## Pending race save retries must retain their original immutable result identity.

const MAIN_HOST_SCRIPT := preload("res://features/testing/academy_retry_identity_main_host.gd")
const HUD_SINK_SCRIPT := preload("res://features/testing/academy_retry_identity_hud.gd")
const GARAGE_SINK_SCRIPT := preload("res://features/testing/academy_retry_identity_garage.gd")
const RACE_CONTROLLER_SCRIPT := preload("res://features/race/race_controller.gd")
const FREESTYLE_CONTROLLER_SCRIPT := preload("res://features/freestyle/freestyle_controller.gd")
const BIKE_CONTROLLER_SCRIPT := preload("res://entities/bike/bike_controller.gd")
const GHOST_CONTROLLER_SCRIPT := preload("res://features/race/ghost_controller.gd")
const FAILING_PROFILE_SCRIPT := preload("res://features/testing/failing_activity_settlement_profile.gd")

const ORIGINAL_LESSON_ID: StringName = &"CONTROL_BASICS"
const NEW_CURRENT_LESSON_ID: StringName = &"GATE_DROP"

var _failures: PackedStringArray = []
var _generic_summary: Dictionary = {}
var _academy_summary: Dictionary = {}
var _open_activity_summary: Dictionary = {}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	Profile.set_script(FAILING_PROFILE_SCRIPT)
	_check(Profile.get_script() == FAILING_PROFILE_SCRIPT, "probe could not install the save-failure profile double")
	_probe_generic_race_retry()
	_probe_academy_retry_during_ride_selection()
	_probe_freestyle_retry_during_cross_mode_selection()

	var passed := _failures.is_empty()
	print("RACE RETRY IDENTITY PROBE: generic_pending=%s generic_credit=%d/%d generic_runs=%d generic_duplicate=%s academy_pending=%s academy_current=%s academy_credited=%s academy_rebound=%s academy_reward=%d/%d academy_bindings=%d ride_intercepted=%s freestyle_pending=%s freestyle_credit=%d/%d freestyle_runs=%d freestyle_duplicate=%s cross_mode_intercepted=%s passed=%s failures=%s" % [
		str(_generic_summary.get(&"pending_retained", false)),
		int(_generic_summary.get(&"cash", -1)),
		int(_generic_summary.get(&"reputation", -1)),
		int(_generic_summary.get(&"runs", -1)),
		str(_generic_summary.get(&"duplicate", false)),
		String(_academy_summary.get(&"pending_lesson", &"")),
		String(_academy_summary.get(&"current_lesson", &"")),
		str(_academy_summary.get(&"credited_stars", 0)),
		str(_academy_summary.get(&"rebound", true)),
		int(_academy_summary.get(&"cash", -1)),
		int(_academy_summary.get(&"reputation", -1)),
		int(_academy_summary.get(&"bindings", -1)),
		str(_academy_summary.get(&"ride_intercepted", false)),
		str(_open_activity_summary.get(&"pending_retained", false)),
		int(_open_activity_summary.get(&"cash", -1)),
		int(_open_activity_summary.get(&"reputation", -1)),
		int(_open_activity_summary.get(&"runs", -1)),
		str(_open_activity_summary.get(&"duplicate", false)),
		str(_open_activity_summary.get(&"cross_mode_intercepted", false)),
		str(passed),
		", ".join(_failures),
	])
	get_tree().quit(0 if passed else 1)


func _probe_generic_race_retry() -> void:
	Profile.persistence_enabled = false
	Profile.reset_profile_for_testing()
	Profile.save_attempt_count = 0
	Profile.persistence_enabled = true

	var context := _create_main_context(&"CIRCUIT")
	var main: Variant = context.main
	var race_attempt: Dictionary = Profile.begin_race_run(
		&"CIRCUIT", "CIRCUIT|RETRY_IDENTITY_PROBE", {}
	)
	_check(bool(race_attempt.get(&"accepted", false)), "profile refused the generic race attempt")
	var immutable_result := _generic_route_result(race_attempt)
	var first_submission := immutable_result.duplicate(true)
	Profile.fail_next_save = true
	main.call(&"_on_race_results_ready", first_submission)

	var pending_value: Variant = main.get(&"_pending_race_settlement")
	var pending: Dictionary = pending_value as Dictionary if pending_value is Dictionary else {}
	var pending_result_value: Variant = pending.get(&"result", {})
	var pending_result: Dictionary = (
		(pending_result_value as Dictionary) if pending_result_value is Dictionary else {}
	)
	var first_payoff_value: Variant = first_submission.get(&"career_payoff", {})
	var first_payoff: Dictionary = (
		(first_payoff_value as Dictionary) if first_payoff_value is Dictionary else {}
	)
	_check(
		StringName(first_payoff.get(&"reason", &"")) == &"SAVE_FAILED"
			and not bool(first_payoff.get(&"durable", true)),
		"generic save failure did not surface as a non-durable SAVE_FAILED receipt"
	)
	_check(
		StringName(pending.get(&"event_id", &"")) == &"CIRCUIT"
			and str(pending_result.get(&"run_id", "")) == str(immutable_result.get(&"run_id", ""))
			and str(pending_result.get(&"signature", "")) == str(immutable_result.get(&"signature", "")),
		"generic SAVE_FAILED did not retain the exact immutable race identity"
	)
	_check(
		Profile.cash == 0
			and Profile.racer_reputation == 0
			and Profile.total_runs == 0
			and Profile.recent_result_ids.is_empty()
			and Profile.save_attempt_count == 1,
		"generic SAVE_FAILED leaked progression or lost its single save attempt"
	)
	var pending_retained := not pending.is_empty()

	main.call(&"_restart_current_activity")
	var settled_pending_value: Variant = main.get(&"_pending_race_settlement")
	var settled_pending: Dictionary = (
		(settled_pending_value as Dictionary) if settled_pending_value is Dictionary else {}
	)
	var hud: RaceHud = context.hud
	var retry_payoff_value: Variant = hud.shown_results.get(&"career_payoff", {})
	var retry_payoff: Dictionary = (
		(retry_payoff_value as Dictionary) if retry_payoff_value is Dictionary else {}
	)
	_check(settled_pending.is_empty(), "durably accepted generic retry remained pending")
	_check(
		bool(retry_payoff.get(&"accepted", false))
			and bool(retry_payoff.get(&"durable", false))
			and StringName(retry_payoff.get(&"reason", &"")) == &"SETTLED"
			and str(hud.shown_results.get(&"run_id", "")) == str(immutable_result.get(&"run_id", ""))
			and str(hud.shown_results.get(&"signature", "")) == str(immutable_result.get(&"signature", "")),
		"generic immutable retry did not settle durably through Main"
	)
	_check(
		Profile.cash == 275
			and Profile.racer_reputation == 9
			and Profile.total_runs == 1
			and Profile.recent_result_ids.size() == 1
			and Profile.save_attempt_count == 2,
		"generic immutable retry did not apply progression exactly once"
	)
	_check(hud.show_count == 1 and (context.garage as GarageUi).hide_count == 1, "generic retry did not restore its result presentation once")

	var replay_submission := immutable_result.duplicate(true)
	main.call(&"_on_race_results_ready", replay_submission)
	var replay_payoff_value: Variant = replay_submission.get(&"career_payoff", {})
	var replay_payoff: Dictionary = (
		(replay_payoff_value as Dictionary) if replay_payoff_value is Dictionary else {}
	)
	_check(
		bool(replay_payoff.get(&"duplicate", false))
			and bool(replay_payoff.get(&"durable", false))
			and StringName(replay_payoff.get(&"reason", &"")) == &"DUPLICATE",
		"exact generic replay was not rejected as a durable duplicate"
	)
	_check(
		Profile.cash == 275
			and Profile.racer_reputation == 9
			and Profile.total_runs == 1
			and Profile.recent_result_ids.size() == 1
			and Profile.save_attempt_count == 2,
		"exact generic replay duplicated progression or wrote the profile again"
	)
	var replay_pending_value: Variant = main.get(&"_pending_race_settlement")
	_check(
		not replay_pending_value is Dictionary or (replay_pending_value as Dictionary).is_empty(),
		"durable duplicate replay recreated a pending generic settlement"
	)
	_generic_summary = {
		&"pending_retained": pending_retained,
		&"cash": Profile.cash,
		&"reputation": Profile.racer_reputation,
		&"runs": Profile.total_runs,
		&"duplicate": bool(replay_payoff.get(&"duplicate", false)),
	}
	_free_main_context(context)


func _probe_academy_retry_during_ride_selection() -> void:
	Profile.persistence_enabled = false
	Profile.reset_profile_for_testing()
	RaceEventCatalog.clear_academy_lesson_override()

	var context := _create_main_context(&"ACADEMY")
	var main: Variant = context.main
	var race: RaceController = context.race
	var hud: RaceHud = context.hud
	var newly_current_session := RaceEventCatalog.get_session_config(&"ACADEMY")
	newly_current_session.rules[&"academy_lesson_id"] = NEW_CURRENT_LESSON_ID
	race.set(&"_session_config", newly_current_session)
	main.set(&"_current_activity", &"ACADEMY")

	var race_attempt: Dictionary = Profile.begin_race_run(
		&"ACADEMY",
		"ACADEMY|RETRY_IDENTITY_PROBE",
		{&"academy_lesson_id": ORIGINAL_LESSON_ID}
	)
	_check(bool(race_attempt.get(&"accepted", false)), "profile refused the original Academy attempt")
	var original_result := _academy_route_result(race_attempt)
	main.set(&"_pending_academy_settlement", {
		&"result": original_result.duplicate(true),
		&"lesson_id": ORIGINAL_LESSON_ID,
		&"metrics": {&"gates_completed": 10, &"resets": 0},
	})

	_check(
		StringName(race.get_session_config().rules.get(&"academy_lesson_id", &""))
			== NEW_CURRENT_LESSON_ID,
		"probe did not establish a newly current Academy lesson"
	)
	_check(Profile.get_academy_progress_snapshot().is_empty(), "profile was not clean before retry")

	main.call(&"_on_ride_requested", &"ATTACK", &"CIRCUIT")

	var progress: Dictionary = Profile.get_academy_progress_snapshot()
	var pending_value: Variant = main.get(&"_pending_academy_settlement")
	var pending: Dictionary = pending_value as Dictionary if pending_value is Dictionary else {}
	var shown: Dictionary = hud.shown_results
	_check(int(progress.get(ORIGINAL_LESSON_ID, 0)) == 3, "retry did not credit the original stored lesson")
	_check(not progress.has(NEW_CURRENT_LESSON_ID), "retry rebound credit to the newly current lesson")
	_check(Profile.cash == 500 and Profile.racer_reputation == 5, "retry did not grant the original lesson reward exactly once")
	_check(Profile.academy_result_bindings.size() == 1, "retry did not persist exactly one race-to-lesson binding")
	for bound_lesson_value: Variant in Profile.academy_result_bindings.values():
		_check(StringName(bound_lesson_value) == ORIGINAL_LESSON_ID, "durable binding used the newly current lesson")
	_check(pending.is_empty(), "durably accepted retry remained pending")
	_check(StringName(shown.get(&"academy_lesson_id", &"")) == ORIGINAL_LESSON_ID, "result presentation lost the stored lesson identity")
	_check(
		main.physical_run_prepare_count == 0
			and StringName(main.get(&"_current_activity")) == &"ACADEMY"
			and Profile.current_setup == &"BALANCED",
		"ride selection configured a new physical run before settling pending Academy progress"
	)
	_check(
		hud.show_count == 1 and (context.garage as GarageUi).hide_count == 1,
		"Academy ride-selection retry did not restore its result presentation once"
	)
	_check(
		StringName(race.get_session_config().rules.get(&"academy_lesson_id", &""))
			== NEW_CURRENT_LESSON_ID,
		"retry silently rewrote the live session identity"
	)

	_academy_summary = {
		&"pending_lesson": ORIGINAL_LESSON_ID,
		&"current_lesson": NEW_CURRENT_LESSON_ID,
		&"credited_stars": int(progress.get(ORIGINAL_LESSON_ID, 0)),
		&"rebound": progress.has(NEW_CURRENT_LESSON_ID),
		&"cash": Profile.cash,
		&"reputation": Profile.racer_reputation,
		&"bindings": Profile.academy_result_bindings.size(),
		&"ride_intercepted": main.physical_run_prepare_count == 0,
	}
	_free_main_context(context)
	RaceEventCatalog.clear_academy_lesson_override()


func _probe_freestyle_retry_during_cross_mode_selection() -> void:
	Profile.persistence_enabled = false
	Profile.reset_profile_for_testing()
	Profile.save_attempt_count = 0
	Profile.persistence_enabled = true

	var completion_receipts: Array[Dictionary] = []
	var completion_receiver := func(receipt: Dictionary) -> void:
		completion_receipts.append(receipt.duplicate(true))
	EventBus.activity_completed.connect(completion_receiver)

	var attempt: Dictionary = Profile.begin_activity_run(&"FREESTYLE")
	_check(bool(attempt.get(&"accepted", false)), "profile refused the Freestyle retry attempt")
	var immutable_submission := {
		&"schema_version": 1,
		&"activity_id": &"FREESTYLE",
		&"run_id": str(attempt.get(&"run_id", "")),
		&"result_value": 12_000,
	}
	var freestyle: FreestyleController = FREESTYLE_CONTROLLER_SCRIPT.new()
	var bike: DirtBikeController = BIKE_CONTROLLER_SCRIPT.new()
	var ghost: GhostController = GHOST_CONTROLLER_SCRIPT.new()
	freestyle.bike = bike
	freestyle.ghost = ghost
	freestyle.set(&"_attempt_context", attempt.duplicate(true))
	freestyle.set(&"_pending_submission", immutable_submission.duplicate(true))
	Profile.fail_next_save = true
	var failed_receipt: Dictionary = freestyle.call(&"_settle_pending_submission") as Dictionary
	_check(
		StringName(failed_receipt.get(&"reason", &"")) == &"SAVE_FAILED"
			and bool(failed_receipt.get(&"retryable", false))
			and not bool(failed_receipt.get(&"durable", true))
			and str(failed_receipt.get(&"run_id", "")) == str(immutable_submission.get(&"run_id", ""))
			and int(failed_receipt.get(&"result_value", -1)) == 12_000,
		"Freestyle controller did not retain the failed submission identity"
	)
	_check(
		freestyle.has_pending_settlement()
			and Profile.cash == 0
			and Profile.freestyler_reputation == 0
			and Profile.total_runs == 0
			and Profile.recent_activity_result_ids.is_empty()
			and Profile.save_attempt_count == 1,
		"Freestyle SAVE_FAILED leaked progression or discarded its pending token"
	)
	_check(
		completion_receipts.size() == 1
			and StringName(completion_receipts[0].get(&"reason", &"")) == &"SAVE_FAILED",
		"Freestyle SAVE_FAILED did not emit exactly one retryable completion receipt"
	)
	var pending_retained := freestyle.has_pending_settlement()

	var context := _create_main_context(&"FREESTYLE")
	var main: Variant = context.main
	main.set(&"_freestyle", freestyle)
	main.call(&"_on_ride_requested", &"ATTACK", &"CIRCUIT")
	var settled_receipt: Dictionary = (
		completion_receipts.back().duplicate(true) if not completion_receipts.is_empty() else {}
	)
	_check(
		bool(settled_receipt.get(&"accepted", false))
			and bool(settled_receipt.get(&"durable", false))
			and not bool(settled_receipt.get(&"duplicate", true))
			and StringName(settled_receipt.get(&"reason", &"")) == &"SETTLED"
			and str(settled_receipt.get(&"run_id", "")) == str(immutable_submission.get(&"run_id", ""))
			and int(settled_receipt.get(&"result_value", -1)) == 12_000,
		"Main did not settle the exact pending Freestyle token"
	)
	_check(
		not freestyle.has_pending_settlement()
			and Profile.cash == 850
			and Profile.freestyler_reputation == 35
			and Profile.best_freestyle_score == 12_000
			and Profile.total_runs == 1
			and Profile.recent_activity_result_ids.size() == 1
			and Profile.save_attempt_count == 2,
		"cross-mode Freestyle retry did not apply progression exactly once"
	)
	_check(
		main.physical_run_prepare_count == 0
			and StringName(main.get(&"_current_activity")) == &"FREESTYLE"
			and Profile.current_setup == &"BALANCED",
		"Circuit preparation started before the pending Freestyle result settled"
	)
	_check(completion_receipts.size() == 2, "Freestyle retry emitted more than one settlement receipt")

	freestyle.set(&"_pending_submission", immutable_submission.duplicate(true))
	main.call(&"_on_ride_requested", &"ATTACK", &"CIRCUIT")
	var duplicate_receipt: Dictionary = (
		completion_receipts.back().duplicate(true) if not completion_receipts.is_empty() else {}
	)
	_check(
		not bool(duplicate_receipt.get(&"accepted", true))
			and bool(duplicate_receipt.get(&"duplicate", false))
			and bool(duplicate_receipt.get(&"durable", false))
			and not bool(duplicate_receipt.get(&"retryable", true))
			and StringName(duplicate_receipt.get(&"reason", &"")) == &"DUPLICATE"
			and str(duplicate_receipt.get(&"run_id", "")) == str(immutable_submission.get(&"run_id", "")),
		"terminal Freestyle replay was not rejected as the same durable duplicate"
	)
	_check(
		not freestyle.has_pending_settlement()
			and Profile.cash == 850
			and Profile.freestyler_reputation == 35
			and Profile.best_freestyle_score == 12_000
			and Profile.total_runs == 1
			and Profile.recent_activity_result_ids.size() == 1
			and Profile.save_attempt_count == 2,
		"terminal Freestyle duplicate changed progression or wrote another save"
	)
	var garage: GarageUi = context.garage
	_check(
		main.physical_run_prepare_count == 0
			and garage.hide_count == 2
			and StringName(main.get(&"_current_activity")) == &"FREESTYLE",
		"cross-mode duplicate replay started or exposed the requested Circuit"
	)
	_check(completion_receipts.size() == 3, "Freestyle duplicate replay emitted more than one receipt")

	_open_activity_summary = {
		&"pending_retained": pending_retained,
		&"cash": Profile.cash,
		&"reputation": Profile.freestyler_reputation,
		&"runs": Profile.total_runs,
		&"duplicate": bool(duplicate_receipt.get(&"duplicate", false)),
		&"cross_mode_intercepted": main.physical_run_prepare_count == 0,
	}
	if EventBus.activity_completed.is_connected(completion_receiver):
		EventBus.activity_completed.disconnect(completion_receiver)
	_free_main_context(context)
	freestyle.free()
	bike.free()
	ghost.free()


func _create_main_context(activity: StringName) -> Dictionary:
	var main: Variant = MAIN_HOST_SCRIPT.new()
	var race: RaceController = RACE_CONTROLLER_SCRIPT.new()
	var hud: RaceHud = HUD_SINK_SCRIPT.new()
	var garage: GarageUi = GARAGE_SINK_SCRIPT.new()
	race.set(&"_session_config", RaceEventCatalog.get_session_config(activity))
	main.set(&"_race", race)
	main.set(&"_hud", hud)
	main.set(&"_garage", garage)
	main.set(&"_current_activity", activity)
	return {&"main": main, &"race": race, &"hud": hud, &"garage": garage}


func _free_main_context(context: Dictionary) -> void:
	(context.main as Node).free()
	(context.race as Node).free()
	(context.hud as Node).free()
	(context.garage as Node).free()


func _generic_route_result(race_attempt: Dictionary) -> Dictionary:
	return {
		&"run_id": str(race_attempt.get(&"run_id", "")),
		&"signature": str(race_attempt.get(&"signature", "")),
		&"event_id": &"CIRCUIT",
		&"valid": true,
		&"player_position": 1,
		&"player_time_usec": 68_000_000,
		&"player_penalty_usec": 0,
		&"medal": &"GOLD",
		&"rewards": {&"cash": 275, &"reputation": 9},
		&"lap_times_usec": [34_000_000, 34_000_000],
		&"classification": [{
			&"rider_id": &"PLAYER",
			&"display_name": "YOU",
			&"is_player": true,
			&"position": 1,
			&"status": &"FINISHED",
		}],
	}


func _academy_route_result(race_attempt: Dictionary) -> Dictionary:
	return {
		&"run_id": str(race_attempt.get(&"run_id", "")),
		&"signature": str(race_attempt.get(&"signature", "")),
		&"event_id": &"ACADEMY",
		&"academy_lesson_id": ORIGINAL_LESSON_ID,
		&"valid": true,
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
			&"status": &"FINISHED",
		}],
	}


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
