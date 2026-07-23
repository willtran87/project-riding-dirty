extends Node
## Public contract for rotation-scoped challenge progression and exact-rules
## competitive artifacts.

const PLAYER_PROFILE_SCRIPT := preload("res://common/player_profile.gd")

var _failures := PackedStringArray()


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var schedule := ChallengeSchedule.new()
	var bucket_unix := 1_900_000_000
	var tier_zero := schedule.daily(bucket_unix, 0)
	var tier_five := schedule.daily(bucket_unix, 5)
	var next_rotation := schedule.daily(bucket_unix + ChallengeSchedule.DAY_SECONDS, 0)

	_assert(
		str(tier_zero.get("challenge_id", "")) == str(tier_five.get("challenge_id", "")),
		"one UTC bucket produced different rotation IDs"
	)
	_assert(
		str(tier_zero.get("run_signature", "")) != str(tier_five.get("run_signature", "")),
		"tier-adjusted rules reused one run signature"
	)
	_assert(
		StringName(tier_zero.get("competition_id", &"")) != StringName(tier_five.get("competition_id", &"")),
		"tier-adjusted rules reused one exact competition ID"
	)
	_assert(
		StringName(tier_zero.get("competition_id", &"")) == ChallengeSchedule.competition_id(tier_zero)
		and StringName(tier_five.get("competition_id", &"")) == ChallengeSchedule.competition_id(tier_five),
		"challenge competition IDs were not derived from their exact signatures"
	)
	_assert(
		str(next_rotation.get("challenge_id", "")) != str(tier_zero.get("challenge_id", "")),
		"the next daily rotation reused the prior rotation ID"
	)

	var tier_zero_config := RaceEventCatalog.get_challenge_session_config(&"DAILY_CHALLENGE", tier_zero)
	var tier_five_config := RaceEventCatalog.get_challenge_session_config(&"DAILY_CHALLENGE", tier_five)
	_assert(
		StringName(tier_zero_config.rules.get(&"competition_id", &"")) == StringName(tier_zero.get("competition_id", &""))
		and StringName(tier_five_config.rules.get(&"competition_id", &"")) == StringName(tier_five.get("competition_id", &"")),
		"challenge session composition dropped the exact competition ID"
	)

	var profile: Variant = PLAYER_PROFILE_SCRIPT.new()
	profile.persistence_enabled = false
	profile._apply_profile_dictionary({
		"cash": 0,
		"racer_reputation": 0,
		"current_setup": "BALANCED",
		"unlocked_setups": ["BALANCED"],
		"course_layout_version": profile.COURSE_LAYOUT_VERSION,
	})
	profile._ensure_full_race_defaults()

	var tier_zero_identity: Dictionary = profile.begin_race_run(
		&"DAILY_CHALLENGE",
		str(tier_zero.get("run_signature", "")),
		_challenge_settlement_context(tier_zero)
	)
	var tier_zero_result := _challenge_result(
		tier_zero,
		str(tier_zero_identity.get(&"run_id", "")),
		&"GOLD",
		90_000_000
	)
	var swapped_statistics_before: Dictionary = profile.get_race_statistics()
	var swapped_records_before := CompetitiveRunSignature.canonical_string(profile.challenge_records)
	var swapped_challenge_result := tier_zero_result.duplicate(true)
	var swapped_challenge_id := StringName(next_rotation.get("challenge_id", &""))
	var swapped_competition_id := ChallengeSchedule.competition_id({
		"challenge_id": String(swapped_challenge_id),
		"run_signature": str(tier_zero.get("run_signature", "")),
	})
	swapped_challenge_result[&"challenge_id"] = swapped_challenge_id
	swapped_challenge_result[&"competition_id"] = swapped_competition_id
	var swapped_challenge_summary: Dictionary = profile.record_race_result(swapped_challenge_result)
	_assert(
		StringName(swapped_challenge_summary.get(&"reason", &"")) == &"STALE_OR_ABANDONED_RUN"
		and bool(swapped_challenge_summary.get(&"invalid_identity", false))
		and CompetitiveRunSignature.canonical_string(profile.get_race_statistics())
			== CompetitiveRunSignature.canonical_string(swapped_statistics_before)
		and CompetitiveRunSignature.canonical_string(profile.challenge_records) == swapped_records_before,
		"one issued token accepted a recomputed but differently scoped challenge identity"
	)
	var tier_zero_summary: Dictionary = profile.record_race_result(
		tier_zero_result
	)
	var rotation_id := StringName(tier_zero.get("challenge_id", &""))
	_assert(bool(tier_zero_summary.get(&"accepted", false)), "first exact competition result was rejected")
	_assert(
		profile.get_event_medal_rank(&"DAILY_CHALLENGE", rotation_id) == 4
		and profile.has_completed_event(&"DAILY_CHALLENGE", rotation_id),
		"rotation completion and medal were not recorded"
	)
	_assert(
		profile.get_event_record(&"DAILY_CHALLENGE").is_empty(),
		"challenge result leaked into the generic event record"
	)
	var first_rotation_record: Dictionary = profile.get_event_record(&"DAILY_CHALLENGE", rotation_id)
	_assert(
		not first_rotation_record.has(&"best_time_usec")
		and not first_rotation_record.has(&"best_lap_usec"),
		"rotation progression stored an exact-rules PB"
	)
	_assert(
		profile.get_leaderboard_summary(str(tier_five.get("run_signature", ""))).is_empty(),
		"a different exact competition inherited a PB summary"
	)

	var tier_five_identity: Dictionary = profile.begin_race_run(
		&"DAILY_CHALLENGE",
		str(tier_five.get("run_signature", "")),
		_challenge_settlement_context(tier_five)
	)
	var tier_five_result := _challenge_result(
		tier_five,
		str(tier_five_identity.get(&"run_id", "")),
		&"SILVER",
		110_000_000
	)
	var tier_five_summary: Dictionary = profile.record_race_result(
		tier_five_result
	)
	var merged_rotation_record: Dictionary = profile.get_event_record(&"DAILY_CHALLENGE", rotation_id)
	_assert(
		bool(tier_five_summary.get(&"accepted", false))
		and int(merged_rotation_record.get(&"starts", 0)) == 2
		and int(merged_rotation_record.get(&"finishes", 0)) == 2,
		"same-rotation exact competitions did not share completion progression"
	)
	_assert(
		profile.get_event_medal_rank(&"DAILY_CHALLENGE", rotation_id) == 4
		and profile.get_event_medal_rank(&"DAILY_CHALLENGE") == 0,
		"rotation medal regressed or leaked into the generic challenge card"
	)
	var duplicate: Dictionary = profile.record_race_result(
		tier_five_result
	)
	_assert(bool(duplicate.get(&"duplicate", false)), "an exact duplicate challenge result was accepted")

	var statistics_before: Dictionary = profile.get_race_statistics()
	var records_before := CompetitiveRunSignature.canonical_string(profile.challenge_records)
	var malformed_identity: Dictionary = profile.begin_race_run(
		&"DAILY_CHALLENGE",
		str(tier_zero.get("run_signature", "")),
		_challenge_settlement_context(tier_zero)
	)
	_assert(
		bool(malformed_identity.get(&"accepted", false)),
		"malformed competition fixture did not receive an authoritative run token"
	)
	var malformed := _challenge_result(
		tier_zero,
		str(malformed_identity.get(&"run_id", "")),
		&"GOLD",
		80_000_000
	)
	malformed[&"competition_id"] = &"DAILY_TAMPERED"
	var rejected: Dictionary = profile.record_race_result(malformed)
	_assert(
		bool(rejected.get(&"invalid_identity", false))
		and CompetitiveRunSignature.canonical_string(profile.get_race_statistics()) == CompetitiveRunSignature.canonical_string(statistics_before)
		and CompetitiveRunSignature.canonical_string(profile.challenge_records) == records_before,
		"malformed challenge identity mutated progression or statistics"
	)

	var next_rotation_identity: Dictionary = profile.begin_race_run(
		&"DAILY_CHALLENGE",
		str(next_rotation.get("run_signature", "")),
		_challenge_settlement_context(next_rotation)
	)
	var next_rotation_result := _challenge_result(
		next_rotation,
		str(next_rotation_identity.get(&"run_id", "")),
		&"BRONZE",
		130_000_000
	)
	var next_rotation_summary: Dictionary = profile.record_race_result(
		next_rotation_result
	)
	var next_rotation_id := StringName(next_rotation.get("challenge_id", &""))
	_assert(
		bool(next_rotation_summary.get(&"accepted", false))
		and profile.get_event_medal_rank(&"DAILY_CHALLENGE", next_rotation_id) == 2
		and profile.get_event_medal_rank(&"DAILY_CHALLENGE", rotation_id) == 4,
		"a new rotation collided with the prior record or result fingerprint"
	)

	var serialized: Dictionary = profile._profile_to_dictionary()
	var decoded: Variant = JSON.parse_string(JSON.stringify(serialized))
	var restored: Variant = PLAYER_PROFILE_SCRIPT.new()
	restored.persistence_enabled = false
	if decoded is Dictionary:
		restored._apply_profile_dictionary(decoded)
		restored._ensure_full_race_defaults()
	_assert(
		restored.get_event_medal_rank(&"DAILY_CHALLENGE", rotation_id) == 4
		and restored.get_event_medal_rank(&"DAILY_CHALLENGE", next_rotation_id) == 2
		and restored.get_event_record(&"DAILY_CHALLENGE").is_empty(),
		"rotation isolation did not survive the profile round trip"
	)
	var migrated: Variant = PLAYER_PROFILE_SCRIPT.new()
	migrated.persistence_enabled = false
	migrated._apply_profile_dictionary({
		"profile_schema_version": 2,
		"best_medal_ranks": {"DAILY_CHALLENGE": 4, "CIRCUIT": 2},
		"event_records": {
			"DAILY_CHALLENGE": {"starts": 8, "finishes": 8, "best_time_usec": 1},
			"CIRCUIT": {"starts": 1, "finishes": 1, "best_time_usec": 150_000_000},
		},
		"course_layout_version": migrated.COURSE_LAYOUT_VERSION,
	})
	_assert(
		migrated.get_event_medal_rank(&"DAILY_CHALLENGE") == 0
		and migrated.get_event_record(&"DAILY_CHALLENGE").is_empty()
		and migrated.get_event_medal_rank(&"CIRCUIT") == 2
		and not migrated.get_event_record(&"CIRCUIT").is_empty(),
		"schema migration retained stale generic challenge progress or removed fixed-event progress"
	)

	var passed := _failures.is_empty()
	print("CHALLENGE ROTATION IDENTITY PROBE: rotation=%s exact_a=%s exact_b=%s next=%s records=%d passed=%s failures=%s" % [
		String(rotation_id),
		str(tier_zero.get("competition_id", "")),
		str(tier_five.get("competition_id", "")),
		String(next_rotation_id),
		profile.challenge_records.size(),
		str(passed),
		", ".join(_failures),
	])
	profile.free()
	restored.free()
	migrated.free()
	get_tree().quit(0 if passed else 1)


func _challenge_result(
	challenge: Dictionary,
	run_id: String,
	medal: StringName,
	time_usec: int
) -> Dictionary:
	return {
		&"run_id": run_id,
		&"signature": str(challenge.get("run_signature", "")),
		&"event_id": &"DAILY_CHALLENGE",
		&"challenge_id": StringName(challenge.get("challenge_id", &"")),
		&"competition_id": StringName(challenge.get("competition_id", &"")),
		&"track_id": StringName(challenge.get("track_id", &"QUARRY")),
		&"valid": true,
		&"player_position": 1,
		&"player_time_usec": time_usec,
		&"player_penalty_usec": 0,
		&"fastest_lap_usec": time_usec,
		&"lap_times_usec": [time_usec],
		&"medal": medal,
		&"classification": [{
			&"rider_id": &"PLAYER",
			&"display_name": "YOU",
			&"is_player": true,
			&"position": 1,
			&"status": &"FINISHED",
		}],
	}


func _challenge_settlement_context(challenge: Dictionary) -> Dictionary:
	return {
		&"challenge_id": StringName(challenge.get("challenge_id", &"")),
		&"competition_id": StringName(challenge.get("competition_id", &"")),
	}


func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
