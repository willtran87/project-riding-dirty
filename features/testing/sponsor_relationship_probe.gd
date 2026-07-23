extends Node
## Deterministic sponsor-arc contract: authored identity, independent ranks,
## bounded difficulty, transparent rewards, and duplicate-safe persistence.

const PLAYER_PROFILE_SCRIPT := preload("res://common/player_profile.gd")
const SPONSOR_CATALOG_SCRIPT := preload("res://features/career/sponsor_contract_catalog.gd")
const RIDE_DIRECTOR_SCRIPT := preload("res://features/ride/ride_director.gd")

var _failures: PackedStringArray = []
var _director_emissions: Array[Dictionary] = []


func _ready() -> void:
	var profile: Variant = PLAYER_PROFILE_SCRIPT.new()
	profile.persistence_enabled = false
	profile._apply_profile_dictionary({
		"course_layout_version": profile.COURSE_LAYOUT_VERSION,
		"current_setup": "BALANCED",
		"unlocked_setups": ["BALANCED"],
	})
	profile._ensure_full_race_defaults()

	var opening := SPONSOR_CATALOG_SCRIPT.get_contract(&"CIRCUIT", profile.completed_contracts)
	_check(StringName(opening.get(&"sponsor_id", &"")) == &"DUSTLINE", "Quarry race lost Dustline identity")
	_check(str(opening.get(&"rank_title", "")) == "PROSPECT", "new relationship did not start at Prospect")
	_check(StringName(opening.get(&"kind", &"")) == &"CLEAN" and int(opening.get(&"target", 0)) == 2, "opening precision contract is not achievable")
	_check(int(opening.get(&"cash_reward", 0)) == 350 and int(opening.get(&"reputation_reward", 0)) == 35, "opening reward changed from the published fair baseline")
	_check(str(opening.get(&"relationship_progress", "")) == "2 RIDES TO SIGNED", "opening contract does not expose the next relationship milestone")
	_check(
		str(opening.get(&"briefing_line", "")).contains("PRECISION EARNS THE PATCH.")
		and str(opening.get(&"identity", "")) == "RACE PRECISION",
		"Dustline briefing lost its authored identity"
	)

	var starting_cash: int = profile.cash
	_settle(profile, "2026-07-22_CIRCUIT_CLEAN", &"CIRCUIT", opening)
	var second := SPONSOR_CATALOG_SCRIPT.get_contract(&"MESA_MX", profile.completed_contracts)
	_settle(profile, "2026-07-22_MESA_MX_CLEAN", &"MESA_MX", second)
	var signed := SPONSOR_CATALOG_SCRIPT.get_contract(&"MESA_HEAT", profile.completed_contracts)
	_check(str(signed.get(&"rank_title", "")) == "SIGNED", "two Dustline jobs did not earn Signed rank")
	_check(int(signed.get(&"cash_reward", 0)) == 425 and int(signed.get(&"reputation_reward", 0)) == 40, "Signed rewards are not transparent and bounded")
	_check(int(signed.get(&"target", 0)) == 2, "Signed contract increased difficulty before the rider learned the arc")

	_settle(profile, "2026-07-22_MESA_HEAT_CLEAN", &"MESA_HEAT", signed)
	var qualifying := SPONSOR_CATALOG_SCRIPT.get_contract(&"MESA_QUALIFYING", profile.completed_contracts)
	_settle(profile, "2026-07-23_MESA_QUALIFYING_CLEAN", &"MESA_QUALIFYING", qualifying)
	var rival := SPONSOR_CATALOG_SCRIPT.get_contract(&"MESA_RIVAL", profile.completed_contracts)
	_settle(profile, "2026-07-24_MESA_RIVAL_CLEAN", &"MESA_RIVAL", rival)
	var factory := SPONSOR_CATALOG_SCRIPT.get_contract(&"QUARRY_HILLCLIMB", profile.completed_contracts)
	_check(str(factory.get(&"rank_title", "")) == "FACTORY", "five Dustline jobs did not earn Factory rank")
	_check(int(factory.get(&"target", 0)) == 3 and int(factory.get(&"cash_reward", 0)) == 500, "Factory challenge/reward did not progress together")
	_check(str(factory.get(&"relationship_progress", "")) == "4 RIDES TO ICON", "Factory contract does not expose the final rank path")

	var wildbrush := SPONSOR_CATALOG_SCRIPT.get_contract(&"DISCOVERY", profile.completed_contracts)
	var sundown := SPONSOR_CATALOG_SCRIPT.get_contract(&"FREESTYLE", profile.completed_contracts)
	_check(StringName(wildbrush.get(&"sponsor_id", &"")) == &"WILDBRUSH" and str(wildbrush.get(&"rank_title", "")) == "PROSPECT", "Wildbrush relationship inherited unrelated Dustline progress")
	_check(StringName(wildbrush.get(&"kind", &"")) == &"ROUTE" and int(wildbrush.get(&"target", 0)) == 2, "Wildbrush advertised more routes than the authored activity contains")
	_check(StringName(sundown.get(&"sponsor_id", &"")) == &"SUNDOWN" and StringName(sundown.get(&"kind", &"")) == &"CHAIN" and int(sundown.get(&"target", 0)) == 4, "Sundown did not preserve the readable four-move opening chain")
	_check(
		wildbrush.get(&"sponsor_accent", Color.TRANSPARENT) != opening.get(&"sponsor_accent", Color.TRANSPARENT)
		and sundown.get(&"sponsor_accent", Color.TRANSPARENT) != opening.get(&"sponsor_accent", Color.TRANSPARENT)
		and sundown.get(&"sponsor_accent", Color.TRANSPARENT) != wildbrush.get(&"sponsor_accent", Color.TRANSPARENT),
		"sponsor programs do not retain distinct readable accents"
	)

	var cash_before_duplicate: int = profile.cash
	var contracts_before_duplicate: int = profile.contract_completions
	var duplicate: bool = profile.complete_contract(
		"2026-07-22_CIRCUIT_CLEAN", &"CIRCUIT",
		int(factory.get(&"cash_reward", 0)), int(factory.get(&"reputation_reward", 0))
	)
	_check(not duplicate and profile.cash == cash_before_duplicate and profile.contract_completions == contracts_before_duplicate, "duplicate contract paid twice after a relationship upgrade")
	_check(profile.cash - starting_cash == 1_975, "five published relationship rewards produced an unexpected economy delta")
	_check(profile.style_tokens == 5, "relationship jobs did not preserve one Style Token each")
	_probe_live_director_promotion()

	var passed := _failures.is_empty()
	print("SPONSOR RELATIONSHIP PROBE: dustline=%s cash=%d tokens=%d wildbrush=%s sundown=%s passed=%s" % [
		str(factory.get(&"rank_title", "")), profile.cash - starting_cash, profile.style_tokens,
		str(wildbrush.get(&"rank_title", "")), str(sundown.get(&"rank_title", "")), str(passed),
	])
	profile.free()
	get_tree().quit(0 if passed else 1)


func _probe_live_director_promotion() -> void:
	Profile.persistence_enabled = false
	Profile.reset_profile_for_testing()
	var director: Variant = RIDE_DIRECTOR_SCRIPT.new()
	director.contract_updated.connect(_on_director_contract_updated)
	for activity: StringName in [&"CIRCUIT", &"MESA_MX"]:
		director.set(&"_activity", activity)
		director.call(&"_select_contract")
		var selected: Dictionary = director.call(&"get_contract_snapshot")
		director.set(&"_contract_progress", int(selected.get(&"target", 0)))
		director.call(&"_update_contract")
	_check(_director_emissions.size() == 2, "live Ride Director did not emit both contract settlements")
	if _director_emissions.size() == 2:
		_check(int(_director_emissions[0].get(&"cash_reward", 0)) == 350, "live opening reward diverged from the catalog")
		_check(
			str(_director_emissions[1].get(&"title", "")).contains("DUSTLINE WORKS SIGNED")
			and str(_director_emissions[1].get(&"title", "")).contains("RELATIONSHIP UPGRADE"),
			"live second contract did not announce the Signed promotion"
		)
	_check(Profile.cash == 700 and Profile.racer_reputation == 70 and Profile.style_tokens == 2, "live Director settlement did not preserve exact Prospect rewards")
	director.free()
	Profile.reset_profile_for_testing()


func _on_director_contract_updated(
	title: String,
	current: int,
	target: int,
	completed: bool,
	cash_reward: int,
	reputation_reward: int
) -> void:
	_director_emissions.append({
		&"title": title,
		&"current": current,
		&"target": target,
		&"completed": completed,
		&"cash_reward": cash_reward,
		&"reputation_reward": reputation_reward,
	})


func _settle(profile: Variant, contract_id: String, activity: StringName, contract: Dictionary) -> void:
	_check(profile.complete_contract(
		contract_id,
		activity,
		int(contract.get(&"cash_reward", 350)),
		int(contract.get(&"reputation_reward", 35))
	), "contract %s failed to settle" % contract_id)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
	push_error("SPONSOR RELATIONSHIP PROBE: %s" % message)
