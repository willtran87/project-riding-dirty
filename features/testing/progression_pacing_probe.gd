extends Node
## Verifies that current profiles earn districts through meaningful progress
## while the old two-run compatibility path remains migration-only.

const PLAYER_PROFILE_SCRIPT := preload("res://common/player_profile.gd")


func _ready() -> void:
	var profile: Variant = PLAYER_PROFILE_SCRIPT.new()
	profile.persistence_enabled = false
	profile._apply_profile_dictionary({
		"course_layout_version": profile.COURSE_LAYOUT_VERSION,
		"current_setup": "BALANCED",
		"unlocked_setups": ["BALANCED"],
	})
	profile._ensure_full_race_defaults()
	var first_discovery := _settle_activity(profile, &"DISCOVERY", 50_000_000)
	var first_discovery_accepted := bool(first_discovery.get(&"accepted", false))
	var first_gold_reward_is_bounded: bool = profile.explorer_reputation == 35
	var one_clear_stays_locked: bool = not profile.is_activity_unlocked(&"PINE_ENDURO")

	var starts_only: Variant = PLAYER_PROFILE_SCRIPT.new()
	starts_only.persistence_enabled = false
	starts_only._apply_profile_dictionary({
		"course_layout_version": starts_only.COURSE_LAYOUT_VERSION,
		"total_runs": 2,
		"current_setup": "BALANCED",
		"unlocked_setups": ["BALANCED"],
	})
	starts_only._ensure_full_race_defaults()
	var starts_do_not_unlock: bool = not starts_only.is_activity_unlocked(&"PINE_ENDURO")

	var first_freestyle := _settle_activity(profile, &"FREESTYLE", 4_000)
	var first_freestyle_accepted := bool(first_freestyle.get(&"accepted", false))
	var two_distinct_clears_unlock: bool = (
		profile.get_quarry_progress_count() == 2
		and profile.is_activity_unlocked(&"PINE_ENDURO")
		and profile.get_total_reputation() == 56
	)
	var repeated_freestyle := _settle_activity(profile, &"FREESTYLE", 3_500)
	var repeated_freestyle_accepted := bool(repeated_freestyle.get(&"accepted", false))
	var non_improving_repeat_is_limited: bool = (
		profile.freestyler_reputation == 27
		and profile.get_total_reputation() == 62
	)

	var legacy: Variant = PLAYER_PROFILE_SCRIPT.new()
	legacy.persistence_enabled = false
	legacy._apply_profile_dictionary({
		"course_layout_version": 0,
		"total_runs": 2,
		"current_setup": "BALANCED",
		"unlocked_setups": ["BALANCED"],
	})
	legacy._ensure_full_race_defaults()
	var legacy_migration_preserved: bool = legacy.legacy_pine_unlock and legacy.is_activity_unlocked(&"PINE_ENDURO")

	var passed: bool = (
		first_discovery_accepted
		and first_freestyle_accepted
		and repeated_freestyle_accepted
		and first_gold_reward_is_bounded
		and one_clear_stays_locked
		and starts_do_not_unlock
		and two_distinct_clears_unlock
		and non_improving_repeat_is_limited
		and legacy_migration_preserved
	)
	print(
		"PROGRESSION PACING PROBE: first_gold=%d starts_locked=%s clears=%d total_rep=%d repeat_limited=%s legacy=%s passed=%s"
		% [
			profile.explorer_reputation,
			str(starts_do_not_unlock),
			profile.get_quarry_progress_count(),
			profile.get_total_reputation(),
			str(non_improving_repeat_is_limited),
			str(legacy_migration_preserved),
			str(passed),
		]
	)
	profile.free()
	starts_only.free()
	legacy.free()
	get_tree().quit(0 if passed else 1)


func _settle_activity(profile: Variant, activity: StringName, result_value: int) -> Dictionary:
	var run: Dictionary = profile.begin_activity_run(activity)
	if not bool(run.get(&"accepted", false)):
		return run
	return profile.record_activity_result({
		&"activity_id": activity,
		&"run_id": str(run.get(&"run_id", "")),
		&"result_value": result_value,
	})
