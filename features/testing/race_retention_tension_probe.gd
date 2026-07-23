extends Node
## V24 deterministic race-retention audit. Covers the full 18-event ladder,
## gap-director fairness, final-lap fade, event casting, and airtime promises.

const LEGACY_UNIQUE_DIFFICULTY_LEVELS := 1
const LEGACY_MAX_DIRECTOR_CORRECTION_MPS := 0.65
const LEGACY_AIRTIME_BONUS_RACES := 1
const LEGACY_PRACTICE_FIELD: Array[StringName] = [&"ROOK", &"NOVA", &"BRICK"]


func _ready() -> void:
	var catalog := _audit_catalog()
	var tension := _audit_tension()
	var identity := _audit_identity()
	var passed := bool(catalog[&"passed"]) and bool(tension[&"passed"]) and bool(identity[&"passed"])
	print("RACE RETENTION V24 BEFORE: difficulty_levels=%d director_cap=%.2f airtime_bonus_races=%d practice_field=%s" % [
		LEGACY_UNIQUE_DIFFICULTY_LEVELS,
		LEGACY_MAX_DIRECTOR_CORRECTION_MPS,
		LEGACY_AIRTIME_BONUS_RACES,
		str(LEGACY_PRACTICE_FIELD),
	])
	print("RACE RETENTION V24 AFTER: catalog=%s tension=%s identity=%s passed=%s" % [
		str(catalog), str(tension), str(identity), str(passed),
	])
	if not passed:
		push_error("RACE RETENTION V24: event progression, fair tension, airtime, or opponent identity contract failed.")
	get_tree().quit(0 if passed else 1)


func _audit_catalog() -> Dictionary:
	var complete_contracts := true
	var default_tiers_match := true
	var unique_difficulties: Dictionary[int, bool] = {}
	var airtime_bonus_races := 0
	var total_airtime_opportunities := 0
	var replay_hooks: Dictionary[StringName, bool] = {}
	for event_id: StringName in RaceEventCatalog.EVENT_ORDER:
		var contract := RaceEventCatalog.get_retention_contract(event_id)
		var event := RaceEventCatalog.get_event(event_id)
		var rules := event.get(&"rules", {}) as Dictionary
		var difficulty := int(contract.get(&"difficulty", -1))
		var replay_hook := StringName(contract.get(&"replay_hook", &""))
		var opportunities := int(contract.get(&"airtime_opportunities", -1))
		complete_contracts = complete_contracts and (
			not contract.is_empty()
			and difficulty >= 0 and difficulty <= 4
			and not replay_hook.is_empty()
			and opportunities >= 0
			and rules.has(&"retention")
			and StringName(rules.get(&"replay_hook", &"")) == replay_hook
		)
		unique_difficulties[difficulty] = true
		replay_hooks[replay_hook] = true
		total_airtime_opportunities += maxi(opportunities, 0)
		if event_id in RaceEventCatalog.RACE_EVENTS and bool(rules.get(&"airtime_bonus", false)):
			airtime_bonus_races += 1
			complete_contracts = complete_contracts and opportunities > 0
		if event_id in RaceEventCatalog.RACE_EVENTS and not RaceEventCatalog.is_challenge_event(event_id):
			default_tiers_match = default_tiers_match and RaceEventCatalog.get_session_config(event_id).difficulty == difficulty

	var progression := (
		int(RaceEventCatalog.get_retention_contract(&"MESA_PRACTICE").get(&"difficulty", -1)) == 0
		and int(RaceEventCatalog.get_retention_contract(&"CIRCUIT").get(&"difficulty", -1)) == 1
		and int(RaceEventCatalog.get_retention_contract(&"MESA_MX").get(&"difficulty", -1)) == 3
		and int(RaceEventCatalog.get_retention_contract(&"MESA_ENDURANCE").get(&"difficulty", -1)) == 4
		and int(RaceEventCatalog.get_retention_contract(&"PINE_WET").get(&"difficulty", -1)) == 4
	)
	var passed := (
		RaceEventCatalog.EVENT_ORDER.size() == 18
		and complete_contracts
		and default_tiers_match
		and unique_difficulties.size() == 5
		and replay_hooks.size() >= 14
		and progression
		and airtime_bonus_races >= 10
		and total_airtime_opportunities >= 150
	)
	return {
		&"events": RaceEventCatalog.EVENT_ORDER.size(),
		&"difficulty_levels": unique_difficulties.size(),
		&"replay_hooks": replay_hooks.size(),
		&"airtime_bonus_races": airtime_bonus_races,
		&"airtime_opportunities": total_airtime_opportunities,
		&"default_tiers_match": default_tiers_match,
		&"passed": passed,
	}


func _audit_tension() -> Dictionary:
	var circuit_player_chase := _adjustment(&"CIRCUIT", 60.0, 0.5)
	var circuit_final_chase := _adjustment(&"CIRCUIT", 60.0, 1.0)
	var practice_player_chase := _adjustment(&"MESA_PRACTICE", 60.0, 0.5)
	var qualifying_adjustment := _adjustment(&"MESA_QUALIFYING", 60.0, 0.5)
	var main_field_chase := _adjustment(&"MESA_MX", -60.0, 0.5)
	var main_final_chase := _adjustment(&"MESA_MX", -60.0, 1.0)
	var lcq_player_chase := _adjustment(&"MESA_LCQ", 60.0, 0.5)
	var bounded := true
	for event_id: StringName in [&"CIRCUIT", &"MESA_PRACTICE", &"MESA_QUALIFYING", &"MESA_MX", &"MESA_LCQ"]:
		for gap: float in [-120.0, -60.0, -12.0, 0.0, 12.0, 60.0, 120.0]:
			bounded = bounded and absf(_adjustment(event_id, gap, 0.5)) <= RacePack.DIRECTOR_MAX_CORRECTION + 0.001
	var restrained_leader_drag := (
		circuit_player_chase < -0.50
		and absf(circuit_player_chase) <= RacePack.LEGACY_DIRECTOR_MAX_CORRECTION + 0.001
	)
	var comeback_outweighs_drag := main_field_chase > absf(circuit_player_chase) * 2.5
	var passed := (
		restrained_leader_drag
		and absf(practice_player_chase) < 0.10
		and is_zero_approx(qualifying_adjustment)
		and main_field_chase > RacePack.LEGACY_DIRECTOR_MAX_CORRECTION
		and comeback_outweighs_drag
		and absf(lcq_player_chase) > absf(circuit_player_chase)
		and absf(circuit_final_chase) < 0.10
		and absf(main_final_chase) < 0.10
		and bounded
	)
	var result := {
		&"cap_mps": RacePack.DIRECTOR_MAX_CORRECTION,
		&"circuit_player_chase": snappedf(circuit_player_chase, 0.001),
		&"circuit_final_chase": snappedf(circuit_final_chase, 0.001),
		&"practice_player_chase": snappedf(practice_player_chase, 0.001),
		&"qualifying_adjustment": qualifying_adjustment,
		&"main_field_chase": snappedf(main_field_chase, 0.001),
		&"main_final_chase": snappedf(main_final_chase, 0.001),
		&"lcq_player_chase": snappedf(lcq_player_chase, 0.001),
		&"restrained_leader_drag": restrained_leader_drag,
		&"comeback_outweighs_drag": comeback_outweighs_drag,
		&"bounded": bounded,
		&"passed": passed,
	}
	return result


func _audit_identity() -> Dictionary:
	var expected_practice: Array[StringName] = [&"LARK", &"DUST", &"MICA"]
	var expected_rhythm: Array[StringName] = [&"BRICK", &"EMBER", &"AXLE", &"JETT", &"ROOK"]
	var practice_profiles := _session_profiles(&"MESA_PRACTICE")
	var rhythm_profiles := _session_profiles(&"MESA_RHYTHM")
	var lcq_profiles := _session_profiles(&"MESA_LCQ")
	var practice_field := _profile_ids(practice_profiles)
	var rhythm_field := _profile_ids(rhythm_profiles)
	var archetypes: Dictionary[StringName, bool] = {}
	var trait_complete_count := 0
	var identity_complete := true
	for profile: Dictionary in lcq_profiles:
		var archetype := StringName(profile.get(&"archetype", &""))
		if _profile_identity_complete(profile):
			trait_complete_count += 1
		else:
			identity_complete = false
		archetypes[archetype] = true
	var explicit_entrants: Array[StringName] = [&"NOVA", &"SABLE", &"MICA"]
	var featured_ids: Array[StringName] = [&"BRICK", &"TANK", &"EMBER", &"AXLE", &"JETT"]
	var managed_profiles: Array[Dictionary] = RiderRoster.get_session_field(5, false, explicit_entrants, featured_ids)
	var managed_ids: Array[StringName] = _profile_ids(managed_profiles)
	var managed_authority := managed_ids.size() >= explicit_entrants.size()
	for index: int in explicit_entrants.size():
		managed_authority = managed_authority and managed_ids[index] == explicit_entrants[index]
	var passed := (
		_same_field(practice_field, expected_practice)
		and _same_field(rhythm_field, expected_rhythm)
		and not _same_field(practice_field, LEGACY_PRACTICE_FIELD)
		and identity_complete
		and archetypes.size() == 5
		and trait_complete_count == 5
		and managed_authority
	)
	var result := {
		&"practice_field": practice_field,
		&"rhythm_field": rhythm_field,
		&"lcq_archetypes": archetypes.size(),
		&"lcq_signature_traits": trait_complete_count,
		&"managed_entrant_authority": managed_authority,
		&"passed": passed,
	}
	return result


func _profile_identity_complete(profile: Dictionary) -> bool:
	var signature_trait := String(profile.get(&"signature_trait", ""))
	var home_track := StringName(profile.get(&"home_track", &""))
	return not signature_trait.is_empty() and not home_track.is_empty()


func _adjustment(event_id: StringName, progress_gap: float, completion: float) -> float:
	var config := RaceEventCatalog.get_session_config(event_id)
	return RacePack.calculate_gap_pace_adjustment(
		config,
		RaceEventCatalog.get_retention_contract(event_id),
		progress_gap,
		completion
	)


func _session_profiles(event_id: StringName) -> Array[Dictionary]:
	var config := RaceEventCatalog.get_session_config(event_id)
	var entrants := _string_name_array(config.rules.get(&"entrant_ids", []))
	var featured := _string_name_array(config.rules.get(&"featured_rider_ids", []))
	return RiderRoster.get_session_field(config.opponent_count, bool(config.rules.get(&"rival_only", false)), entrants, featured)


func _profile_ids(profiles: Array[Dictionary]) -> Array[StringName]:
	var ids: Array[StringName] = []
	for profile: Dictionary in profiles:
		ids.append(StringName(profile.get(&"id", &"")))
	return ids


func _string_name_array(value: Variant) -> Array[StringName]:
	var output: Array[StringName] = []
	if value is Array or value is PackedStringArray:
		for entry: Variant in value:
			var rider_id := StringName(entry)
			if not rider_id.is_empty() and not output.has(rider_id):
				output.append(rider_id)
	return output


func _same_field(actual: Array[StringName], expected: Array[StringName]) -> bool:
	if actual.size() != expected.size():
		return false
	for rider_id: StringName in expected:
		if rider_id not in actual:
			return false
	return true
