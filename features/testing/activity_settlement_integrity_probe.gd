extends Node
## Durable open-activity settlement contract: run authority, idempotency,
## rollback, bounded ledgers, and Academy composition when available.

const PLAYER_PROFILE_SCRIPT := preload("res://common/player_profile.gd")
const FAILING_PROFILE_SCRIPT := preload("res://features/testing/failing_activity_settlement_profile.gd")
const ACADEMY_CATALOG_SCRIPT := preload("res://features/career/academy_lesson_catalog.gd")

var _failures := PackedStringArray()
var _academy_combined_available: bool = false


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_probe_first_settlement_and_reload_duplicate()
	_probe_invalid_and_stale_run_ids()
	_probe_cash_cap_reports_actual_credit()
	_probe_save_failure_rolls_back_and_retries()
	_probe_race_run_authority()
	_probe_authority_domain_transitions()
	_probe_generic_race_save_failure_rolls_back_and_retries()
	_probe_contract_save_failure_rolls_back_and_retries()
	_probe_feat_unlock_save_failure_rolls_back_and_retries()
	_probe_standalone_academy_save_failure_rolls_back_and_retries()
	_probe_activity_success_reentrancy()
	_probe_v3_migration_and_ledger_sanitation()
	_probe_legacy_race_identity_dedupe()
	_probe_consumed_race_token_after_ledger_eviction()
	_probe_v4_academy_competitive_migration()
	_probe_runtime_ledger_capacity()
	_probe_academy_combined_settlement_if_available()

	var passed := _failures.is_empty()
	print("ACTIVITY SETTLEMENT INTEGRITY PROBE: durable=true duplicate=reload invalid=true cap=true rollback=true ledger=%d academy_combined=%s passed=%s failures=%s" % [
		PLAYER_PROFILE_SCRIPT.MAX_ACTIVITY_RESULT_IDS,
		str(_academy_combined_available),
		str(passed),
		", ".join(_failures),
	])
	get_tree().quit(0 if passed else 1)


func _probe_first_settlement_and_reload_duplicate() -> void:
	var profile: Variant = _new_profile()
	var reward_signals: Array[Vector2i] = []
	var profile_signal_count := [0]
	var meta_signal_count := [0]
	profile.reward_granted.connect(func(cash_reward: int, reputation_reward: int) -> void:
		reward_signals.append(Vector2i(cash_reward, reputation_reward))
	)
	profile.profile_changed.connect(func(_cash: int, _reputation: int, _setup: StringName) -> void:
		profile_signal_count[0] += 1
	)
	profile.meta_progress_changed.connect(func(_snapshot: Dictionary) -> void:
		meta_signal_count[0] += 1
	)

	var run: Dictionary = profile.begin_activity_run(&"FREESTYLE")
	var submission := _activity_submission(run, &"FREESTYLE", 12_000)
	var first: Dictionary = profile.record_activity_result(submission)
	_assert(
		bool(run.get(&"accepted", false))
		and bool(first.get(&"accepted", false))
		and bool(first.get(&"durable", false))
		and not bool(first.get(&"duplicate", true)),
		"first Freestyle result was not durably accepted"
	)
	var first_rewards := first.get(&"rewards_granted", {}) as Dictionary
	_assert(
		StringName(first.get(&"medal", &"")) == &"GOLD"
		and bool(first.get(&"is_new_best", false))
		and int(first_rewards.get(&"cash", -1)) == 850
		and int(first_rewards.get(&"reputation", -1)) == 35
		and profile.cash == 850
		and profile.freestyler_reputation == 35
		and profile.best_freestyle_score == 12_000
		and profile.total_runs == 1,
		"first Freestyle settlement did not apply its exact progression once"
	)
	_assert(
		reward_signals == [Vector2i(850, 35)]
		and profile_signal_count[0] == 1
		and meta_signal_count[0] == 1,
		"successful settlement did not publish one exact post-commit signal batch"
	)

	var state_after_first := _settlement_state(profile)
	var duplicate: Dictionary = profile.record_activity_result(submission)
	_assert(
		not bool(duplicate.get(&"accepted", true))
		and bool(duplicate.get(&"duplicate", false))
		and bool(duplicate.get(&"durable", false))
		and _settlement_state(profile) == state_after_first
		and reward_signals.size() == 1
		and profile_signal_count[0] == 1
		and meta_signal_count[0] == 1,
		"same-process duplicate mutated progression or emitted settlement signals"
	)

	var decoded: Variant = JSON.parse_string(JSON.stringify(profile._profile_to_dictionary()))
	var restored: Variant = _new_profile(false)
	if decoded is Dictionary:
		restored._apply_profile_dictionary(decoded)
	else:
		_assert(false, "settled profile did not survive JSON encoding")
	var restored_before := _settlement_state(restored)
	var restored_duplicate: Dictionary = restored.record_activity_result(submission)
	_assert(
		not bool(restored_duplicate.get(&"accepted", true))
		and bool(restored_duplicate.get(&"duplicate", false))
		and bool(restored_duplicate.get(&"durable", false))
		and _settlement_state(restored) == restored_before,
		"serialized duplicate was not rejected without mutation"
	)
	profile.free()
	restored.free()


func _probe_invalid_and_stale_run_ids() -> void:
	var profile: Variant = _new_profile()
	var baseline := _settlement_state(profile)
	var unknown_begin: Dictionary = profile.begin_activity_run(&"CIRCUIT")
	var empty_id: Dictionary = profile.record_activity_result({
		&"activity_id": &"FREESTYLE", &"run_id": "", &"result_value": 4_000,
	})
	var stale_id: Dictionary = profile.record_activity_result({
		&"activity_id": &"FREESTYLE", &"run_id": "freestyle-stale-attempt", &"result_value": 4_000,
	})
	var abandoned_run: Dictionary = profile.begin_activity_run(&"FREESTYLE")
	var current_run: Dictionary = profile.begin_activity_run(&"FREESTYLE")
	var abandoned_result: Dictionary = profile.record_activity_result(
		_activity_submission(abandoned_run, &"FREESTYLE", 4_000)
	)
	var invalid_result: Dictionary = profile.record_activity_result(
		_activity_submission(current_run, &"FREESTYLE", -1)
	)
	_assert(
		not bool(unknown_begin.get(&"accepted", true))
		and StringName(unknown_begin.get(&"reason", &"")) == &"UNKNOWN_ACTIVITY"
		and StringName(empty_id.get(&"reason", &"")) == &"INVALID_RUN_ID"
		and StringName(stale_id.get(&"reason", &"")) == &"STALE_OR_ABANDONED_RUN"
		and StringName(abandoned_result.get(&"reason", &"")) == &"STALE_OR_ABANDONED_RUN"
		and StringName(invalid_result.get(&"reason", &"")) == &"INVALID_RESULT"
		and _settlement_state(profile) == baseline,
		"invalid, stale, or superseded activity authority mutated progression"
	)
	var valid_retry: Dictionary = profile.record_activity_result(
		_activity_submission(current_run, &"FREESTYLE", 4_000)
	)
	_assert(bool(valid_retry.get(&"accepted", false)), "invalid result consumed the current activity run token")
	profile.free()


func _probe_cash_cap_reports_actual_credit() -> void:
	var profile: Variant = _new_profile()
	profile.cash = profile.MAX_CASH - 25
	var reward_signals: Array[Vector2i] = []
	profile.reward_granted.connect(func(cash_reward: int, reputation_reward: int) -> void:
		reward_signals.append(Vector2i(cash_reward, reputation_reward))
	)
	var run: Dictionary = profile.begin_activity_run(&"DISCOVERY")
	var summary: Dictionary = profile.record_activity_result(
		_activity_submission(run, &"DISCOVERY", 50_000_000)
	)
	var rewards := summary.get(&"rewards_granted", {}) as Dictionary
	var last_transaction := profile.transaction_log.back() as Dictionary if not profile.transaction_log.is_empty() else {}
	_assert(
		bool(summary.get(&"accepted", false))
		and profile.cash == profile.MAX_CASH
		and profile.explorer_reputation == 35
		and int(rewards.get(&"cash", -1)) == 25
		and int(rewards.get(&"reputation", -1)) == 35
		and reward_signals == [Vector2i(25, 35)]
		and int(last_transaction.get(&"delta", -1)) == 25,
		"cash-capped activity did not report and signal the actual credited amount"
	)
	profile.free()


func _probe_save_failure_rolls_back_and_retries() -> void:
	var profile: Variant = _new_profile(true, FAILING_PROFILE_SCRIPT)
	var reward_signal_count := [0]
	var profile_signal_count := [0]
	var meta_signal_count := [0]
	profile.reward_granted.connect(func(_cash: int, _reputation: int) -> void:
		reward_signal_count[0] += 1
	)
	profile.profile_changed.connect(func(_cash: int, _reputation: int, _setup: StringName) -> void:
		profile_signal_count[0] += 1
	)
	profile.meta_progress_changed.connect(func(_snapshot: Dictionary) -> void:
		meta_signal_count[0] += 1
	)
	var run: Dictionary = profile.begin_activity_run(&"FREESTYLE")
	var submission := _activity_submission(run, &"FREESTYLE", 12_000)
	var before := _settlement_state(profile)
	profile.fail_next_save = true
	var failed: Dictionary = profile.record_activity_result(submission)
	_assert(
		not bool(failed.get(&"accepted", true))
		and not bool(failed.get(&"durable", true))
		and StringName(failed.get(&"reason", &"")) == &"SAVE_FAILED"
		and _settlement_state(profile) == before
		and reward_signal_count[0] == 0
		and profile_signal_count[0] == 0
		and meta_signal_count[0] == 0,
		"failed persistence did not fully roll back progression and suppress signals"
	)
	var retry: Dictionary = profile.record_activity_result(submission)
	_assert(
		bool(retry.get(&"accepted", false))
		and bool(retry.get(&"durable", false))
		and profile.cash == 850
		and profile.freestyler_reputation == 35
		and profile.total_runs == 1
		and profile.recent_activity_result_ids.size() == 1
		and reward_signal_count[0] == 1
		and profile_signal_count[0] == 1
		and meta_signal_count[0] == 1
		and profile.save_attempt_count == 2,
		"same run token could not settle exactly once after persistence recovered"
	)
	var duplicate: Dictionary = profile.record_activity_result(submission)
	_assert(
		bool(duplicate.get(&"duplicate", false))
		and profile.cash == 850
		and profile.save_attempt_count == 2,
		"post-retry duplicate was persisted or rewarded again"
	)
	profile.free()


func _probe_race_run_authority() -> void:
	var profile: Variant = _new_profile()
	var baseline := _settlement_state(profile)
	var empty_run: Dictionary = profile.record_race_result(
		_generic_race_result("", "RACE_AUTHORITY_EMPTY"), false
	)
	var oversize_run: Dictionary = profile.record_race_result(
		_generic_race_result("x".repeat(161), "RACE_AUTHORITY_OVERSIZE"), false
	)
	var fabricated: Dictionary = profile.record_race_result(
		_generic_race_result("circuit-fabricated-fresh-run", "RACE_AUTHORITY_FABRICATED"), false
	)
	_assert(
		StringName(empty_run.get(&"reason", &"")) == &"INVALID_RUN_ID"
		and StringName(oversize_run.get(&"reason", &"")) == &"INVALID_RUN_ID"
		and StringName(fabricated.get(&"reason", &"")) == &"STALE_OR_ABANDONED_RUN"
		and not bool(fabricated.get(&"duplicate", true))
		and _settlement_state(profile) == baseline,
		"empty, oversized, or fabricated race run identity bypassed race authority"
	)

	var issued: Dictionary = profile.begin_race_run(&"CIRCUIT", "RACE_AUTHORITY_CANONICAL")
	var exact := _generic_race_result(
		str(issued.get(&"run_id", "")), str(issued.get(&"signature", ""))
	)
	var mutated := exact.duplicate(true)
	mutated[&"signature"] = "RACE_AUTHORITY_MUTATED"
	var before_mutation := _settlement_state(profile)
	var mutation_rejection: Dictionary = profile.record_race_result(mutated, false)
	_assert(
		bool(issued.get(&"accepted", false))
		and not bool(mutation_rejection.get(&"accepted", true))
		and not bool(mutation_rejection.get(&"duplicate", true))
		and StringName(mutation_rejection.get(&"reason", &"")) == &"STALE_OR_ABANDONED_RUN"
		and _settlement_state(profile) == before_mutation,
		"mutated signature was accepted for an issued race token"
	)
	var exact_retry: Dictionary = profile.record_race_result(exact, false)
	_assert(
		bool(exact_retry.get(&"accepted", false))
		and bool(exact_retry.get(&"durable", false))
		and profile.total_runs == 1,
		"signature rejection consumed the issued token before an exact retry"
	)
	profile.free()


func _probe_authority_domain_transitions() -> void:
	var race_to_activity: Variant = _new_profile()
	var abandoned_race_result := _issue_generic_race_result(
		race_to_activity, "DOMAIN_RACE_THEN_FREESTYLE"
	)
	var freestyle_after_race: Dictionary = race_to_activity.begin_activity_run(&"FREESTYLE")
	var before_abandoned_race := _settlement_state(race_to_activity)
	var abandoned_race: Dictionary = race_to_activity.record_race_result(
		abandoned_race_result, false
	)
	_assert(
		bool(freestyle_after_race.get(&"accepted", false))
		and not bool(abandoned_race.get(&"accepted", true))
		and not bool(abandoned_race.get(&"duplicate", true))
		and StringName(abandoned_race.get(&"reason", &"")) == &"STALE_OR_ABANDONED_RUN"
		and _settlement_state(race_to_activity) == before_abandoned_race,
		"starting Freestyle did not abandon the prior structured-race token"
	)
	var freestyle_after_stale_race: Dictionary = race_to_activity.record_activity_result(
		_activity_submission(freestyle_after_race, &"FREESTYLE", 4_000)
	)
	_assert(
		bool(freestyle_after_stale_race.get(&"accepted", false)),
		"stale structured-race payload consumed the newer Freestyle token"
	)
	race_to_activity.free()

	var exact_abandon: Variant = _new_profile()
	var abandoned_activity_run: Dictionary = exact_abandon.begin_activity_run(&"FREESTYLE")
	var exact_abandon_before := _settlement_state(exact_abandon)
	var abandoned_exactly: bool = exact_abandon.abandon_activity_run(
		&"FREESTYLE", str(abandoned_activity_run.get(&"run_id", ""))
	)
	var abandoned_submission: Dictionary = exact_abandon.record_activity_result(
		_activity_submission(abandoned_activity_run, &"FREESTYLE", 4_000)
	)
	_assert(
		abandoned_exactly
		and not bool(abandoned_submission.get(&"accepted", true))
		and StringName(abandoned_submission.get(&"reason", &"")) == &"STALE_OR_ABANDONED_RUN"
		and _settlement_state(exact_abandon) == exact_abandon_before,
		"exact activity abandonment left its run token settleable"
	)
	exact_abandon.free()

	var stale_abandon: Variant = _new_profile()
	var older_run: Dictionary = stale_abandon.begin_activity_run(&"FREESTYLE")
	var newer_run: Dictionary = stale_abandon.begin_activity_run(&"FREESTYLE")
	var stale_erased: bool = stale_abandon.abandon_activity_run(
		&"FREESTYLE", str(older_run.get(&"run_id", ""))
	)
	var mismatched_erased: bool = stale_abandon.abandon_activity_run(
		&"DISCOVERY", str(newer_run.get(&"run_id", ""))
	)
	var newer_submission: Dictionary = stale_abandon.record_activity_result(
		_activity_submission(newer_run, &"FREESTYLE", 4_000)
	)
	_assert(
		not stale_erased
		and not mismatched_erased
		and bool(newer_submission.get(&"accepted", false))
		and bool(newer_submission.get(&"durable", false)),
		"stale or mismatched abandon erased the newer activity token"
	)
	stale_abandon.free()

	var open_activity_race_api: Variant = _new_profile()
	var open_activity_race_baseline := _settlement_state(open_activity_race_api)
	var freestyle_begin: Dictionary = open_activity_race_api.begin_race_run(
		&"FREESTYLE", "INVALID_RACE_DOMAIN_FREESTYLE"
	)
	var discovery_begin: Dictionary = open_activity_race_api.begin_race_run(
		&"DISCOVERY", "INVALID_RACE_DOMAIN_DISCOVERY"
	)
	var freestyle_race_payload := _generic_race_result(
		"fabricated-freestyle-race-run", "INVALID_RACE_DOMAIN_FREESTYLE"
	)
	freestyle_race_payload[&"event_id"] = &"FREESTYLE"
	var discovery_race_payload := _generic_race_result(
		"fabricated-discovery-race-run", "INVALID_RACE_DOMAIN_DISCOVERY"
	)
	discovery_race_payload[&"event_id"] = &"DISCOVERY"
	var freestyle_race: Dictionary = open_activity_race_api.record_race_result(
		freestyle_race_payload, false
	)
	var discovery_race: Dictionary = open_activity_race_api.record_race_result(
		discovery_race_payload, false
	)
	_assert(
		not bool(freestyle_begin.get(&"accepted", true))
		and not bool(discovery_begin.get(&"accepted", true))
		and StringName(freestyle_begin.get(&"reason", &"")) == &"INVALID_RACE_CONTEXT"
		and StringName(discovery_begin.get(&"reason", &"")) == &"INVALID_RACE_CONTEXT"
		and StringName(freestyle_race.get(&"reason", &"")) == &"INVALID_RACE_EVENT"
		and StringName(discovery_race.get(&"reason", &"")) == &"INVALID_RACE_EVENT"
		and _settlement_state(open_activity_race_api) == open_activity_race_baseline,
		"open-activity event IDs crossed into structured-race authority"
	)
	open_activity_race_api.free()


func _probe_generic_race_save_failure_rolls_back_and_retries() -> void:
	var profile: Variant = _new_profile(true, FAILING_PROFILE_SCRIPT)
	var reward_signal_count := [0]
	var profile_signal_count := [0]
	var meta_signal_count := [0]
	var race_signal_count := [0]
	profile.reward_granted.connect(func(_cash: int, _reputation: int) -> void:
		reward_signal_count[0] += 1
	)
	profile.profile_changed.connect(func(_cash: int, _reputation: int, _setup: StringName) -> void:
		profile_signal_count[0] += 1
	)
	profile.meta_progress_changed.connect(func(_snapshot: Dictionary) -> void:
		meta_signal_count[0] += 1
	)
	profile.race_result_recorded.connect(func(_summary: Dictionary) -> void:
		race_signal_count[0] += 1
	)
	var result := _issue_generic_race_result(profile, "GENERIC_RACE_SAVE_FAILURE")
	var before := _settlement_state(profile)
	profile.fail_next_save = true
	var failed: Dictionary = profile.record_race_result(result, true)
	_assert(
		not bool(failed.get(&"accepted", true))
		and not bool(failed.get(&"durable", true))
		and bool(failed.get(&"retryable", false))
		and StringName(failed.get(&"reason", &"")) == &"SAVE_FAILED"
		and _settlement_state(profile) == before
		and profile.save_attempt_count == 1
		and reward_signal_count[0] == 0
		and profile_signal_count[0] == 0
		and meta_signal_count[0] == 0
		and race_signal_count[0] == 0,
		"generic race save failure did not fully roll back route progression"
	)
	var retry: Dictionary = profile.record_race_result(result, true)
	_assert(
		bool(retry.get(&"accepted", false))
		and bool(retry.get(&"durable", false))
		and profile.cash == 275
		and profile.racer_reputation == 9
		and profile.total_runs == 1
		and profile.recent_result_ids.size() == 1
		and profile.save_attempt_count == 2
		and reward_signal_count[0] == 1
		and profile_signal_count[0] == 1
		and meta_signal_count[0] == 1
		and race_signal_count[0] == 1,
		"exact generic race payload could not settle once after persistence recovered"
	)
	var after_retry := _settlement_state(profile)
	var duplicate: Dictionary = profile.record_race_result(result, true)
	_assert(
		not bool(duplicate.get(&"accepted", true))
		and bool(duplicate.get(&"duplicate", false))
		and bool(duplicate.get(&"durable", false))
		and _settlement_state(profile) == after_retry
		and profile.save_attempt_count == 2
		and reward_signal_count[0] == 1
		and profile_signal_count[0] == 1
		and meta_signal_count[0] == 1
		and race_signal_count[0] == 1,
		"generic race duplicate persisted, rewarded, or mutated after retry"
	)
	profile.free()


func _probe_contract_save_failure_rolls_back_and_retries() -> void:
	var profile: Variant = _new_profile(true, FAILING_PROFILE_SCRIPT)
	var reward_signal_count := [0]
	var profile_signal_count := [0]
	var meta_signal_count := [0]
	profile.reward_granted.connect(func(_cash: int, _reputation: int) -> void:
		reward_signal_count[0] += 1
	)
	profile.profile_changed.connect(func(_cash: int, _reputation: int, _setup: StringName) -> void:
		profile_signal_count[0] += 1
	)
	profile.meta_progress_changed.connect(func(_snapshot: Dictionary) -> void:
		meta_signal_count[0] += 1
	)
	var before := _settlement_state(profile)
	profile.fail_next_save = true
	var failed: bool = profile.complete_contract("settlement-probe-contract", &"DISCOVERY", 420, 17)
	_assert(
		not failed
		and _settlement_state(profile) == before
		and profile.save_attempt_count == 1
		and reward_signal_count[0] == 0
		and profile_signal_count[0] == 0
		and meta_signal_count[0] == 0,
		"contract save failure did not roll back its identity, rewards, and style token"
	)
	var retry: bool = profile.complete_contract("settlement-probe-contract", &"DISCOVERY", 420, 17)
	_assert(
		retry
		and profile.cash == 420
		and profile.explorer_reputation == 17
		and profile.contract_completions == 1
		and profile.completed_contracts == ["settlement-probe-contract"]
		and profile.style_tokens == 1
		and profile.transaction_log.size() == 1
		and profile.save_attempt_count == 2
		and reward_signal_count[0] == 1
		and profile_signal_count[0] == 1
		and meta_signal_count[0] == 1,
		"contract could not settle exactly once after persistence recovered"
	)
	var after_retry := _settlement_state(profile)
	var duplicate: bool = profile.complete_contract("settlement-probe-contract", &"DISCOVERY", 420, 17)
	_assert(
		not duplicate
		and _settlement_state(profile) == after_retry
		and profile.save_attempt_count == 2,
		"completed contract retried its durable payout"
	)
	profile.free()


func _probe_feat_unlock_save_failure_rolls_back_and_retries() -> void:
	var profile: Variant = _new_profile(true, FAILING_PROFILE_SCRIPT)
	var profile_signal_count := [0]
	var meta_signal_count := [0]
	profile.profile_changed.connect(func(_cash: int, _reputation: int, _setup: StringName) -> void:
		profile_signal_count[0] += 1
	)
	profile.meta_progress_changed.connect(func(_snapshot: Dictionary) -> void:
		meta_signal_count[0] += 1
	)
	var before := _settlement_state(profile)
	profile.fail_next_save = true
	var failed: bool = profile.unlock_feat("SETTLEMENT_PROBE_FEAT")
	_assert(
		not failed
		and _settlement_state(profile) == before
		and profile.save_attempt_count == 1
		and profile_signal_count[0] == 0
		and meta_signal_count[0] == 0,
		"feat unlock save failure did not roll back its identity, style token, and transaction"
	)
	var retry: bool = profile.unlock_feat("SETTLEMENT_PROBE_FEAT")
	_assert(
		retry
		and profile.unlocked_feats == ["SETTLEMENT_PROBE_FEAT"]
		and profile.style_tokens == 1
		and profile.transaction_log.size() == 1
		and StringName(profile.transaction_log[0].get(&"reason", &"")) == &"riding_feat"
		and profile.save_attempt_count == 2
		and profile_signal_count[0] == 1
		and meta_signal_count[0] == 1,
		"feat unlock could not settle exactly once after persistence recovered"
	)
	var after_retry := _settlement_state(profile)
	var duplicate: bool = profile.unlock_feat("SETTLEMENT_PROBE_FEAT")
	_assert(
		not duplicate
		and _settlement_state(profile) == after_retry
		and profile.save_attempt_count == 2,
		"durable feat unlock was persisted or awarded a second time"
	)
	profile.free()


func _probe_standalone_academy_save_failure_rolls_back_and_retries() -> void:
	var profile: Variant = _new_profile(true, FAILING_PROFILE_SCRIPT)
	var reward_signal_count := [0]
	var profile_signal_count := [0]
	var meta_signal_count := [0]
	profile.reward_granted.connect(func(_cash: int, _reputation: int) -> void:
		reward_signal_count[0] += 1
	)
	profile.profile_changed.connect(func(_cash: int, _reputation: int, _setup: StringName) -> void:
		profile_signal_count[0] += 1
	)
	profile.meta_progress_changed.connect(func(_snapshot: Dictionary) -> void:
		meta_signal_count[0] += 1
	)
	var metrics := {&"gates_completed": 10, &"resets": 0}
	var before := _academy_state(profile)
	profile.fail_next_save = true
	var failed: Dictionary = profile.record_academy_result(&"CONTROL_BASICS", metrics)
	var failed_rewards := failed.get(&"credited_rewards", {}) as Dictionary
	_assert(
		not bool(failed.get(&"accepted", true))
		and not bool(failed.get(&"durable", true))
		and bool(failed.get(&"retryable", false))
		and StringName(failed.get(&"error", &"")) == &"SAVE_FAILED"
		and int(failed_rewards.get(&"cash", -1)) == 0
		and int(failed_rewards.get(&"reputation", -1)) == 0
		and _academy_state(profile) == before
		and profile.save_attempt_count == 1
		and reward_signal_count[0] == 0
		and profile_signal_count[0] == 0
		and meta_signal_count[0] == 0,
		"standalone Academy save failure did not roll back lesson progress and rewards"
	)
	var retry: Dictionary = profile.record_academy_result(&"CONTROL_BASICS", metrics)
	_assert(
		bool(retry.get(&"accepted", false))
		and bool(retry.get(&"durable", false))
		and bool(retry.get(&"passed", false))
		and int(retry.get(&"stars", 0)) == 3
		and profile.cash == 500
		and profile.racer_reputation == 5
		and int(profile.academy_progress.get(&"CONTROL_BASICS", 0)) == 3
		and profile.transaction_log.size() == 1
		and profile.save_attempt_count == 2
		and reward_signal_count[0] == 1
		and profile_signal_count[0] == 1
		and meta_signal_count[0] == 1,
		"standalone Academy result could not settle after persistence recovered"
	)
	profile.free()


func _probe_activity_success_reentrancy() -> void:
	var profile: Variant = _new_profile(true, FAILING_PROFILE_SCRIPT)
	var reentrant_runs: Array[Dictionary] = []
	profile.reward_granted.connect(func(_cash: int, _reputation: int) -> void:
		if reentrant_runs.is_empty():
			reentrant_runs.append(profile.begin_activity_run(&"FREESTYLE"))
	)
	var first_run: Dictionary = profile.begin_activity_run(&"FREESTYLE")
	var first: Dictionary = profile.record_activity_result(
		_activity_submission(first_run, &"FREESTYLE", 12_000)
	)
	_assert(
		bool(first.get(&"accepted", false))
		and reentrant_runs.size() == 1
		and bool(reentrant_runs[0].get(&"accepted", false))
		and str(reentrant_runs[0].get(&"run_id", "")) != str(first_run.get(&"run_id", "")),
		"committed activity signals could not begin a distinct reentrant run"
	)
	if reentrant_runs.is_empty():
		profile.free()
		return
	var second: Dictionary = profile.record_activity_result(
		_activity_submission(reentrant_runs[0], &"FREESTYLE", 7_000)
	)
	_assert(
		bool(second.get(&"accepted", false))
		and bool(second.get(&"durable", false))
		and profile.total_runs == 2
		and profile.recent_activity_result_ids.size() == 2
		and profile.save_attempt_count == 2,
		"post-commit cleanup erased the activity token created by a signal listener"
	)
	profile.free()


func _probe_v3_migration_and_ledger_sanitation() -> void:
	var race_fingerprint := "legacy-race-result".sha256_text()
	var migrated: Variant = _new_profile(false)
	migrated._apply_profile_dictionary({
		"profile_schema_version": 3,
		"course_layout_version": migrated.COURSE_LAYOUT_VERSION,
		"recent_result_ids": [race_fingerprint],
	})
	var migrated_data: Dictionary = migrated._profile_to_dictionary()
	_assert(
		int(migrated_data.get("profile_schema_version", 0)) == migrated.PROFILE_SCHEMA_VERSION
		and migrated.recent_result_ids == [race_fingerprint]
		and migrated.recent_activity_result_ids.is_empty()
		and migrated_data.has("recent_activity_result_ids"),
		"V3 profile did not migrate to a separate empty current-schema activity ledger"
	)

	var valid_fingerprints: Array[String] = []
	for index: int in range(70):
		valid_fingerprints.append(("activity-ledger-%d" % index).sha256_text())
	var raw_ledger: Array = [
		valid_fingerprints[0],
		"",
		"not-a-fingerprint",
		"f".repeat(63),
		"g".repeat(64),
	]
	raw_ledger.append_array(valid_fingerprints)
	var sanitized: Variant = _new_profile(false)
	sanitized._apply_profile_dictionary({
		"profile_schema_version": sanitized.PROFILE_SCHEMA_VERSION,
		"course_layout_version": sanitized.COURSE_LAYOUT_VERSION,
		"recent_activity_result_ids": raw_ledger,
	})
	var expected: Array[String] = []
	for index: int in range(6, 70):
		expected.append(valid_fingerprints[index])
	_assert(
		sanitized.recent_activity_result_ids == expected
		and sanitized.recent_activity_result_ids.size() == sanitized.MAX_ACTIVITY_RESULT_IDS,
		"activity ledger sanitation did not retain the newest 64 unique SHA-256 fingerprints"
	)
	migrated.free()
	sanitized.free()


func _probe_legacy_race_identity_dedupe() -> void:
	var run_id := "legacy-raw-race-run-id"
	var result := _generic_race_result(run_id)
	var profile: Variant = _new_profile(true, FAILING_PROFILE_SCRIPT)
	profile._apply_profile_dictionary({
		"profile_schema_version": 4,
		"course_layout_version": profile.COURSE_LAYOUT_VERSION,
		"current_setup": "BALANCED",
		"unlocked_setups": ["BALANCED"],
		"recent_result_ids": [run_id],
	})
	profile._ensure_full_race_defaults()
	var before := _settlement_state(profile)
	var duplicate: Dictionary = profile.record_race_result(result, true)
	_assert(
		not bool(duplicate.get(&"accepted", true))
		and bool(duplicate.get(&"duplicate", false))
		and bool(duplicate.get(&"durable", false))
		and StringName(duplicate.get(&"reason", &"")) == &"DUPLICATE"
		and profile.recent_result_ids == [run_id]
		and _settlement_state(profile) == before
		and profile.save_attempt_count == 0,
		"raw legacy race run ID was rewarded again after fingerprint migration"
	)
	profile.free()


func _probe_consumed_race_token_after_ledger_eviction() -> void:
	var profile: Variant = _new_profile()
	var oldest_result := _issue_generic_race_result(profile, "EVICTION_OLDEST")
	var oldest_summary: Dictionary = profile.record_race_result(oldest_result, false)
	var oldest_result_id := str(oldest_summary.get(&"result_id", ""))
	_assert(
		bool(oldest_summary.get(&"accepted", false)) and not oldest_result_id.is_empty(),
		"oldest authorized race did not settle for the eviction probe"
	)
	for index: int in range(profile.MAX_RESULT_IDS + 1):
		var later_result := _issue_generic_race_result(profile, "EVICTION_LATER_%d" % index)
		var later_summary: Dictionary = profile.record_race_result(later_result, false)
		if not bool(later_summary.get(&"accepted", false)):
			_assert(false, "later authorized race %d failed before ledger eviction" % index)
			break
	_assert(
		profile.recent_result_ids.size() == profile.MAX_RESULT_IDS
		and not profile.recent_result_ids.has(oldest_result_id),
		"race ledger did not evict the oldest canonical result after capacity"
	)

	var current_result := _issue_generic_race_result(profile, "EVICTION_CURRENT_TOKEN")
	var before_replay := _settlement_state(profile)
	var replay: Dictionary = profile.record_race_result(oldest_result, false)
	_assert(
		not bool(replay.get(&"accepted", true))
		and not bool(replay.get(&"duplicate", true))
		and not bool(replay.get(&"durable", true))
		and StringName(replay.get(&"reason", &"")) == &"STALE_OR_ABANDONED_RUN"
		and _settlement_state(profile) == before_replay,
		"consumed oldest race token replayed after its result fingerprint was evicted"
	)
	var current_summary: Dictionary = profile.record_race_result(current_result, false)
	_assert(
		bool(current_summary.get(&"accepted", false))
		and bool(current_summary.get(&"durable", false))
		and profile.total_runs == profile.MAX_RESULT_IDS + 3,
		"evicted-token replay consumed the current authorized race token"
	)
	profile.free()


func _probe_v4_academy_competitive_migration() -> void:
	var migrated: Variant = _new_profile(false)
	migrated._apply_profile_dictionary({
		"profile_schema_version": 4,
		"course_layout_version": migrated.COURSE_LAYOUT_VERSION,
		"current_setup": "BALANCED",
		"unlocked_setups": ["BALANCED"],
		"race_statistics": {
			"starts": 4,
			"finishes": 2,
			"wins": 2,
			"podiums": 5,
			"top_five": 2,
			"dnfs": 1,
			"race_time_usec": 200_000_000,
		},
		"event_records": {
			"ACADEMY": {
				"starts": 2,
				"finishes": 2,
				"wins": 2,
				"podiums": 2,
				"dnfs": 1,
				"total_time_usec": 200_000_000,
			},
		},
		"achievements": ["FIRST_FINISH", "FIRST_WIN", "PODIUM_REGULAR"],
	})
	var stats: Dictionary = migrated.get_race_statistics()
	_assert(
		int(stats.get(&"starts", -1)) == 2
		and int(stats.get(&"finishes", -1)) == 0
		and int(stats.get(&"wins", -1)) == 0
		and int(stats.get(&"podiums", -1)) == 3
		and int(stats.get(&"top_five", -1)) == 0
		and int(stats.get(&"dnfs", -1)) == 0
		and int(stats.get(&"race_time_usec", -1)) == 0
		and not migrated.achievements.has(&"FIRST_FINISH")
		and not migrated.achievements.has(&"FIRST_WIN")
		and not migrated.achievements.has(&"PODIUM_REGULAR"),
		"V4 migration did not subtract Academy-only competitive statistics and achievements"
	)

	var zero_star_progress: Dictionary = {}
	for lesson: Dictionary in ACADEMY_CATALOG_SCRIPT.create_default().get_lessons():
		zero_star_progress[StringName(lesson.get(&"lesson_id", &""))] = 0
	var zero_star_profile: Variant = _new_profile(false)
	zero_star_profile._apply_profile_dictionary({
		"profile_schema_version": zero_star_profile.PROFILE_SCHEMA_VERSION,
		"course_layout_version": zero_star_profile.COURSE_LAYOUT_VERSION,
		"current_setup": "BALANCED",
		"unlocked_setups": ["BALANCED"],
		"academy_progress": zero_star_progress,
		"achievements": [],
	})
	var trigger_result := _issue_generic_race_result(
		zero_star_profile, "ZERO_STAR_GRADUATE_TRIGGER"
	)
	var trigger: Dictionary = zero_star_profile.record_race_result(trigger_result, false)
	_assert(
		bool(trigger.get(&"accepted", false))
		and zero_star_profile.get_completed_academy_lessons().is_empty()
		and not zero_star_profile.achievements.has(&"ACADEMY_GRADUATE"),
		"zero-star Academy entries counted toward Academy Graduate"
	)
	migrated.free()
	zero_star_profile.free()


func _probe_runtime_ledger_capacity() -> void:
	var profile: Variant = _new_profile()
	var settled_ids: Array[String] = []
	for index: int in range(profile.MAX_ACTIVITY_RESULT_IDS + 1):
		var run: Dictionary = profile.begin_activity_run(&"FREESTYLE")
		var summary: Dictionary = profile.record_activity_result(
			_activity_submission(run, &"FREESTYLE", 3_500 + index)
		)
		if not bool(summary.get(&"accepted", false)):
			_assert(false, "runtime activity ledger setup rejected run %d" % index)
			break
		settled_ids.append(str(summary.get(&"result_id", "")))
	_assert(
		settled_ids.size() == profile.MAX_ACTIVITY_RESULT_IDS + 1
		and profile.recent_activity_result_ids.size() == profile.MAX_ACTIVITY_RESULT_IDS
		and not profile.recent_activity_result_ids.has(settled_ids[0])
		and profile.recent_activity_result_ids.front() == settled_ids[1]
		and profile.recent_activity_result_ids.back() == settled_ids.back(),
		"runtime settlement ledger did not evict only its oldest fingerprint at capacity"
	)
	profile.free()


func _probe_academy_combined_settlement_if_available() -> void:
	var profile: Variant = _new_profile(true, FAILING_PROFILE_SCRIPT)
	_academy_combined_available = profile.has_method(&"settle_academy_race_result")
	if not _academy_combined_available:
		profile.free()
		return
	var reward_signal_count := [0]
	var profile_signal_count := [0]
	var meta_signal_count := [0]
	var race_signal_count := [0]
	profile.reward_granted.connect(func(_cash: int, _reputation: int) -> void:
		reward_signal_count[0] += 1
	)
	profile.profile_changed.connect(func(_cash: int, _reputation: int, _setup: StringName) -> void:
		profile_signal_count[0] += 1
	)
	profile.meta_progress_changed.connect(func(_snapshot: Dictionary) -> void:
		meta_signal_count[0] += 1
	)
	profile.race_result_recorded.connect(func(_summary: Dictionary) -> void:
		race_signal_count[0] += 1
	)
	var route_result := _issue_academy_route_result(
		profile, &"CONTROL_BASICS", "ACADEMY_COMBINED_DURABLE"
	)
	var precommit_cross_lesson := route_result.duplicate(true)
	precommit_cross_lesson[&"academy_lesson_id"] = &"GATE_DROP"
	var before_precommit_cross_lesson := _academy_state(profile)
	var precommit_cross_rejection: Dictionary = profile.call(
		&"settle_academy_race_result", precommit_cross_lesson, &"GATE_DROP",
		{&"reaction_seconds": 0.1, &"launch_speed": 99.0}
	) as Dictionary
	var precommit_cross_race := precommit_cross_rejection.get(&"race_summary", {}) as Dictionary
	_assert(
		not bool(precommit_cross_rejection.get(&"accepted", true))
		and not bool(precommit_cross_rejection.get(&"duplicate", true))
		and StringName(precommit_cross_rejection.get(&"reason", &"")) == &"STALE_OR_ABANDONED_RUN"
		and StringName(precommit_cross_race.get(&"reason", &"")) == &"STALE_OR_ABANDONED_RUN"
		and _academy_state(profile) == before_precommit_cross_lesson
		and profile.save_attempt_count == 0,
		"Academy token bound to one lesson accepted a different lesson before settlement"
	)
	var first: Dictionary = profile.call(
		&"settle_academy_race_result", route_result, &"CONTROL_BASICS",
		{&"gates_completed": 10, &"resets": 0}
	) as Dictionary
	var first_record: Dictionary = profile.get_event_record(&"ACADEMY")
	var competitive_stats: Dictionary = profile.get_race_statistics()
	_assert(
		bool(first.get(&"accepted", false))
		and bool(first.get(&"durable", false))
		and bool(first.get(&"classified_eligible", false))
		and profile.cash == 500
		and profile.racer_reputation == 5
		and int(profile.academy_progress.get(&"CONTROL_BASICS", 0)) == 3
		and profile.total_runs == 1
		and int(first_record.get(&"starts", 0)) == 1
		and int(first_record.get(&"finishes", 0)) == 1
		and not profile.is_first_run_onboarding_active()
		and profile.save_attempt_count == 1
		and reward_signal_count[0] == 1
		and profile_signal_count[0] == 1
		and meta_signal_count[0] == 1
		and race_signal_count[0] == 1,
		"combined Academy settlement stacked generic rewards or omitted lesson/route progress"
	)
	_assert(
		int(competitive_stats.get(&"starts", -1)) == 0
		and int(competitive_stats.get(&"finishes", -1)) == 0
		and int(competitive_stats.get(&"wins", -1)) == 0
		and int(competitive_stats.get(&"podiums", -1)) == 0
		and not profile.achievements.has(&"FIRST_FINISH")
		and not profile.achievements.has(&"FIRST_WIN"),
		"Academy route polluted competitive stats or achievements"
	)
	var after_first := _academy_state(profile)
	var duplicate: Dictionary = profile.call(
		&"settle_academy_race_result", route_result, &"CONTROL_BASICS",
		{&"gates_completed": 10, &"resets": 0}
	) as Dictionary
	_assert(
		bool(duplicate.get(&"duplicate", false))
		and _academy_state(profile) == after_first
		and profile.save_attempt_count == 1
		and reward_signal_count[0] == 1
		and profile_signal_count[0] == 1
		and meta_signal_count[0] == 1
		and race_signal_count[0] == 1,
		"combined Academy duplicate mutated, persisted, or signaled progression"
	)

	var decoded: Variant = JSON.parse_string(JSON.stringify(profile._profile_to_dictionary()))
	var restored: Variant = _new_profile(false)
	if decoded is Dictionary:
		restored._apply_profile_dictionary(decoded)
	var restored_before := _academy_state(restored)
	_assert(
		restored.transaction_log.size() == 1
		and int(restored.transaction_log[0].get(&"delta", -1)) == 500
		and StringName(restored.transaction_log[0].get(&"reason", &"")) == &"ACADEMY_REWARD"
		and restored.academy_result_bindings.size() == 1,
		"Academy transaction audit or race binding did not survive reload"
	)
	restored.call(
		&"settle_academy_race_result", route_result, &"CONTROL_BASICS",
		{&"gates_completed": 10, &"resets": 0}
	)
	_assert(_academy_state(restored) == restored_before, "serialized Academy duplicate mutated route or lesson progression")

	var failed_profile: Variant = _new_profile(true, FAILING_PROFILE_SCRIPT)
	var failed_reward_count := [0]
	var failed_profile_count := [0]
	var failed_meta_count := [0]
	var failed_race_count := [0]
	failed_profile.reward_granted.connect(func(_cash: int, _reputation: int) -> void:
		failed_reward_count[0] += 1
	)
	failed_profile.profile_changed.connect(func(_cash: int, _reputation: int, _setup: StringName) -> void:
		failed_profile_count[0] += 1
	)
	failed_profile.meta_progress_changed.connect(func(_snapshot: Dictionary) -> void:
		failed_meta_count[0] += 1
	)
	failed_profile.race_result_recorded.connect(func(_summary: Dictionary) -> void:
		failed_race_count[0] += 1
	)
	var failure_route := _issue_academy_route_result(
		failed_profile, &"CONTROL_BASICS", "ACADEMY_COMBINED_SAVE_FAILURE"
	)
	var before_failure := _academy_state(failed_profile)
	failed_profile.fail_next_save = true
	var failed: Dictionary = failed_profile.call(
		&"settle_academy_race_result", failure_route, &"CONTROL_BASICS",
		{&"gates_completed": 10, &"resets": 0}
	) as Dictionary
	var failed_race_summary := failed.get(&"race_summary", {}) as Dictionary
	_assert(
		not bool(failed.get(&"accepted", true))
		and not bool(failed.get(&"durable", true))
		and bool(failed.get(&"retryable", false))
		and StringName(failed.get(&"reason", &"")) == &"SAVE_FAILED"
		and not bool(failed_race_summary.get(&"accepted", true))
		and not bool(failed_race_summary.get(&"durable", true))
		and bool(failed_race_summary.get(&"retryable", false))
		and StringName(failed_race_summary.get(&"reason", &"")) == &"SAVE_FAILED"
		and _academy_state(failed_profile) == before_failure
		and failed_profile.save_attempt_count == 1
		and failed_reward_count[0] == 0
		and failed_profile_count[0] == 0
		and failed_meta_count[0] == 0
		and failed_race_count[0] == 0,
		"Academy save failure did not roll back both route and lesson settlement"
	)
	var recovered_retry: Dictionary = failed_profile.call(
		&"settle_academy_race_result", failure_route, &"CONTROL_BASICS",
		{&"gates_completed": 10, &"resets": 0}
	) as Dictionary
	_assert(
		bool(recovered_retry.get(&"accepted", false))
		and bool(recovered_retry.get(&"durable", false))
		and failed_profile.cash == 500
		and failed_profile.racer_reputation == 5
		and failed_profile.total_runs == 1
		and failed_profile.save_attempt_count == 2
		and failed_reward_count[0] == 1
		and failed_profile_count[0] == 1
		and failed_meta_count[0] == 1
		and failed_race_count[0] == 1,
		"Academy payload could not settle exactly once after persistence recovered"
	)

	var legacy_profile: Variant = _new_profile(true, FAILING_PROFILE_SCRIPT)
	var legacy_route := _issue_academy_route_result(
		legacy_profile, &"CONTROL_BASICS", "ACADEMY_LEGACY_HALF_SETTLEMENT"
	)
	var legacy_race: Dictionary = legacy_profile.record_race_result(legacy_route, false)
	var legacy_before := _academy_state(legacy_profile)
	var legacy_refusal: Dictionary = legacy_profile.call(
		&"settle_academy_race_result", legacy_route, &"CONTROL_BASICS",
		{&"gates_completed": 10, &"resets": 0}
	) as Dictionary
	_assert(
		bool(legacy_race.get(&"accepted", false))
		and legacy_before[&"academy_progress"].is_empty()
		and not bool(legacy_refusal.get(&"accepted", true))
		and bool(legacy_refusal.get(&"duplicate", false))
		and StringName(legacy_refusal.get(&"reason", &"")) == &"LEGACY_UNBOUND_RACE"
		and legacy_profile.academy_progress.is_empty()
		and legacy_profile.cash == 0
		and legacy_profile.total_runs == 1
		and legacy_profile.save_attempt_count == 1
		and _academy_state(legacy_profile) == legacy_before,
		"unbound legacy Academy race guessed a lesson or paid progression"
	)

	var cross_lesson_route := route_result.duplicate(true)
	cross_lesson_route[&"academy_lesson_id"] = &"GATE_DROP"
	var before_cross_lesson := _academy_state(profile)
	var cross_lesson: Dictionary = profile.call(
		&"settle_academy_race_result", cross_lesson_route, &"GATE_DROP",
		{&"reaction_seconds": 0.1, &"launch_speed": 99.0}
	) as Dictionary
	_assert(
		not bool(cross_lesson.get(&"accepted", true))
		and not bool(cross_lesson.get(&"duplicate", true))
		and StringName(cross_lesson.get(&"reason", &"")) == &"ACADEMY_RACE_ALREADY_BOUND"
		and _academy_state(profile) == before_cross_lesson
		and profile.save_attempt_count == 1,
		"one Academy race settled a second lesson"
	)
	var unknown_begin: Dictionary = profile.begin_race_run(
		&"ACADEMY", "ACADEMY_UNKNOWN_LESSON", {&"academy_lesson_id": &"FAKE_LESSON"}
	)
	var unknown_route := _academy_route_result(
		"academy-unknown-lesson", &"FAKE_LESSON", "ACADEMY_UNKNOWN_LESSON"
	)
	var unknown: Dictionary = profile.call(
		&"settle_academy_race_result", unknown_route, &"FAKE_LESSON", {}
	) as Dictionary
	_assert(
		not bool(unknown_begin.get(&"accepted", true))
		and StringName(unknown_begin.get(&"reason", &"")) == &"INVALID_RACE_CONTEXT"
		and not bool(unknown.get(&"accepted", true))
		and StringName(unknown.get(&"reason", &"")) == &"INVALID_ACADEMY_IDENTITY"
		and _academy_state(profile) == before_cross_lesson
		and profile.save_attempt_count == 1,
		"unknown Academy lesson consumed a result identity"
	)

	for invalid_kind: StringName in [
		&"MISSING_CLASSIFICATION",
		&"WRONG_RIDER",
		&"DUPLICATE_PLAYER",
		&"DNF",
		&"INVALID",
	]:
		var ineligible_profile: Variant = _new_profile(true, FAILING_PROFILE_SCRIPT)
		var ineligible_route := _issue_academy_route_result(
			ineligible_profile,
			&"CONTROL_BASICS",
			"ACADEMY_INELIGIBLE_%s" % String(invalid_kind)
		)
		match invalid_kind:
			&"MISSING_CLASSIFICATION":
				ineligible_route[&"classification"] = []
			&"WRONG_RIDER":
				ineligible_route[&"classification"] = [{
					&"rider_id": &"CPU_01",
					&"display_name": "RIVAL",
					&"is_player": false,
					&"position": 1,
					&"status": &"FINISHED",
				}]
			&"DUPLICATE_PLAYER":
				(ineligible_route[&"classification"] as Array).append({
					&"rider_id": &"PLAYER",
					&"display_name": "DUPLICATE YOU",
					&"is_player": false,
					&"position": 2,
					&"status": &"CLASSIFIED",
				})
			&"DNF":
				(ineligible_route[&"classification"] as Array)[0][&"status"] = &"DNF"
			&"INVALID":
				ineligible_route[&"valid"] = false
		var ineligible: Dictionary = ineligible_profile.call(
			&"settle_academy_race_result", ineligible_route, &"CONTROL_BASICS",
			{&"gates_completed": 10, &"resets": 0}
		) as Dictionary
		_assert(
			bool(ineligible.get(&"accepted", false))
			and bool(ineligible.get(&"durable", false))
			and not bool(ineligible.get(&"classified_eligible", true))
			and ineligible_profile.academy_progress.is_empty()
			and ineligible_profile.academy_result_bindings.size() == 1
			and ineligible_profile.cash == 0
			and ineligible_profile.racer_reputation == 0
			and ineligible_profile.first_run_onboarding_complete == false
			and ineligible_profile.total_runs == 1
			and ineligible_profile.save_attempt_count == 1,
			"%s Academy attempt awarded lesson progression" % String(invalid_kind)
		)
		ineligible_profile.free()
	profile.free()
	restored.free()
	failed_profile.free()
	legacy_profile.free()


func _new_profile(persistence_enabled: bool = false, script: Variant = PLAYER_PROFILE_SCRIPT) -> Variant:
	var profile: Variant = script.new()
	profile.persistence_enabled = false
	profile._apply_profile_dictionary({
		"profile_schema_version": profile.PROFILE_SCHEMA_VERSION,
		"course_layout_version": profile.COURSE_LAYOUT_VERSION,
		"current_setup": "BALANCED",
		"unlocked_setups": ["BALANCED"],
	})
	profile._ensure_full_race_defaults()
	profile.persistence_enabled = persistence_enabled
	return profile


func _activity_submission(run: Dictionary, activity: StringName, result_value: int) -> Dictionary:
	return {
		&"activity_id": activity,
		&"run_id": str(run.get(&"run_id", "")),
		&"result_value": result_value,
	}


func _settlement_state(profile: Variant) -> Dictionary:
	return {
		&"cash": profile.cash,
		&"racer_reputation": profile.racer_reputation,
		&"freestyler_reputation": profile.freestyler_reputation,
		&"explorer_reputation": profile.explorer_reputation,
		&"total_runs": profile.total_runs,
		&"best_freestyle_score": profile.best_freestyle_score,
		&"best_discovery_usec": profile.best_discovery_usec,
		&"best_medal_ranks": profile.best_medal_ranks.duplicate(true),
		&"rival_victories": profile.rival_victories.duplicate(),
		&"recent_result_ids": profile.recent_result_ids.duplicate(),
		&"recent_activity_result_ids": profile.recent_activity_result_ids.duplicate(),
		&"academy_result_bindings": profile.academy_result_bindings.duplicate(true),
		&"transaction_log": profile.transaction_log.duplicate(true),
		&"race_statistics": profile.race_statistics.duplicate(true),
		&"event_records": profile.event_records.duplicate(true),
		&"achievements": profile.achievements.duplicate(),
		&"contract_completions": profile.contract_completions,
		&"completed_contracts": profile.completed_contracts.duplicate(),
		&"style_tokens": profile.style_tokens,
		&"unlocked_feats": profile.unlocked_feats.duplicate(),
		&"first_run_onboarding_complete": profile.first_run_onboarding_complete,
	}


func _academy_state(profile: Variant) -> Dictionary:
	return {
		&"cash": profile.cash,
		&"racer_reputation": profile.racer_reputation,
		&"total_runs": profile.total_runs,
		&"academy_progress": profile.academy_progress.duplicate(true),
		&"event_record": profile.get_event_record(&"ACADEMY"),
		&"recent_result_ids": profile.recent_result_ids.duplicate(),
		&"recent_activity_result_ids": profile.recent_activity_result_ids.duplicate(),
		&"academy_result_bindings": profile.academy_result_bindings.duplicate(true),
		&"transaction_log": profile.transaction_log.duplicate(true),
		&"race_statistics": profile.race_statistics.duplicate(true),
		&"achievements": profile.achievements.duplicate(),
		&"first_run_onboarding_complete": profile.first_run_onboarding_complete,
	}


func _issue_generic_race_result(profile: Variant, signature: String) -> Dictionary:
	var run: Dictionary = profile.begin_race_run(&"CIRCUIT", signature)
	_assert(
		bool(run.get(&"accepted", false)),
		"profile refused a valid CIRCUIT race authority request for %s" % signature
	)
	return _generic_race_result(
		str(run.get(&"run_id", "")), str(run.get(&"signature", signature))
	)


func _generic_race_result(run_id: String, signature: String = "LEGACY_RACE_RESULT") -> Dictionary:
	return {
		&"run_id": run_id,
		&"signature": signature,
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


func _issue_academy_route_result(
	profile: Variant,
	lesson_id: StringName,
	signature: String
) -> Dictionary:
	var run: Dictionary = profile.begin_race_run(
		&"ACADEMY", signature, {&"academy_lesson_id": lesson_id}
	)
	_assert(
		bool(run.get(&"accepted", false)),
		"profile refused valid Academy race authority for %s" % String(lesson_id)
	)
	return _academy_route_result(
		str(run.get(&"run_id", "")),
		lesson_id,
		str(run.get(&"signature", signature))
	)


func _academy_route_result(
	run_id: String,
	lesson_id: StringName = &"CONTROL_BASICS",
	signature: String = "ACADEMY|ACTIVITY_SETTLEMENT_PROBE"
) -> Dictionary:
	return {
		&"run_id": run_id,
		&"signature": signature,
		&"event_id": &"ACADEMY",
		&"academy_lesson_id": lesson_id,
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


func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
