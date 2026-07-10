extends Node
## Owns persistent integer currency, racing reputation, setup unlocks, and transaction history.

signal profile_changed(cash: int, racer_reputation: int, current_setup: StringName)
signal reward_granted(cash_reward: int, reputation_reward: int)

const SAVE_PATH: String = "user://rider_profile.cfg"
const WEB_SAVE_KEY: String = "rider_profile_v1"
const MAX_CASH: int = 999_999
const MAX_LOG_ENTRIES: int = 30
const TOUR_EVENTS: Array[StringName] = [&"CIRCUIT", &"FREESTYLE", &"DISCOVERY", &"PINE_ENDURO"]
const QUARRY_EVENTS: Array[StringName] = [&"CIRCUIT", &"FREESTYLE", &"DISCOVERY"]
const ROOK_TARGETS_USEC: Dictionary[StringName, int] = {
	&"CIRCUIT": 52_000_000,
	&"PINE_ENDURO": 64_000_000,
}

var cash: int = 0
var racer_reputation: int = 0
var freestyler_reputation: int = 0
var explorer_reputation: int = 0
var total_runs: int = 0
var current_setup: StringName = &"BALANCED"
var unlocked_setups: Array[StringName] = [&"BALANCED"]
var transaction_log: Array[Dictionary] = []
var best_freestyle_score: int = 0
var best_discovery_usec: int = -1
var bike_condition: int = 100
var persistence_enabled: bool = true
var best_medal_ranks: Dictionary[StringName, int] = {}
var rival_victories: Array[StringName] = []

var _active_activity: StringName = &"CIRCUIT"


func _ready() -> void:
	_load_profile()
	EventBus.activity_started.connect(_on_activity_started)
	EventBus.race_finished.connect(_on_race_finished)
	EventBus.activity_completed.connect(_on_activity_completed)


func add_cash(amount: int, reason: StringName) -> void:
	if amount <= 0:
		return
	var old_cash := cash
	cash = mini(cash + amount, MAX_CASH)
	_record_transaction(cash - old_cash, reason)
	_emit_and_save()


func spend_cash(amount: int, reason: StringName) -> bool:
	if amount <= 0 or cash < amount:
		return false
	cash -= amount
	_record_transaction(-amount, reason)
	_emit_and_save()
	return true


func is_setup_unlocked(setup: StringName) -> bool:
	return unlocked_setups.has(setup)


func get_total_reputation() -> int:
	return racer_reputation + freestyler_reputation + explorer_reputation


func get_event_medal_rank(activity: StringName) -> int:
	return best_medal_ranks.get(activity, 0)


func get_event_medal(activity: StringName) -> StringName:
	match get_event_medal_rank(activity):
		4:
			return &"GOLD"
		3:
			return &"SILVER"
		2:
			return &"BRONZE"
		1:
			return &"FINISHER"
		_:
			return &"UNRIDDEN"


func has_completed_event(activity: StringName) -> bool:
	return get_event_medal_rank(activity) > 0


func has_beaten_rival(activity: StringName) -> bool:
	return rival_victories.has(activity)


func get_completed_event_count() -> int:
	var completed := 0
	for activity: StringName in TOUR_EVENTS:
		if has_completed_event(activity):
			completed += 1
	return completed


func get_quarry_progress_count() -> int:
	var completed := 0
	for activity: StringName in QUARRY_EVENTS:
		if has_completed_event(activity):
			completed += 1
	return completed


func is_activity_unlocked(activity: StringName) -> bool:
	if activity != &"PINE_ENDURO":
		return true
	return get_quarry_progress_count() >= 2 or has_beaten_rival(&"CIRCUIT") or get_total_reputation() >= 80 or total_runs >= 2


func get_activity_unlock_hint(activity: StringName) -> String:
	if is_activity_unlocked(activity):
		return ""
	if activity == &"PINE_ENDURO":
		return "COMPLETE ANY TWO RED MESA EVENTS OR BEAT ROOK'S QUARRY TIME"
	return "KEEP BUILDING YOUR TOUR REPUTATION"


func get_setup_price(setup: StringName) -> int:
	match setup:
		&"TRAIL":
			return 800
		&"ATTACK":
			return 1500
		_:
			return 0


func purchase_setup(setup: StringName) -> bool:
	if is_setup_unlocked(setup):
		return true
	var price := get_setup_price(setup)
	if price <= 0 or not spend_cash(price, &"setup_purchase"):
		return false
	unlocked_setups.append(setup)
	current_setup = setup
	_emit_and_save()
	return true


func set_current_setup(setup: StringName) -> bool:
	if not is_setup_unlocked(setup):
		return false
	current_setup = setup
	_emit_and_save()
	return true


func apply_bike_damage(amount: int) -> void:
	if amount <= 0:
		return
	bike_condition = clampi(bike_condition - amount, 0, 100)
	_emit_and_save()


func get_repair_price() -> int:
	return (100 - bike_condition) * 7


func repair_bike() -> bool:
	var repair_price := get_repair_price()
	if repair_price <= 0:
		return true
	if cash < repair_price:
		return false
	cash -= repair_price
	_record_transaction(-repair_price, &"bike_repair")
	bike_condition = 100
	_emit_and_save()
	return true


func reset_profile_for_testing() -> void:
	cash = 0
	racer_reputation = 0
	freestyler_reputation = 0
	explorer_reputation = 0
	total_runs = 0
	current_setup = &"BALANCED"
	bike_condition = 100
	best_freestyle_score = 0
	best_discovery_usec = -1
	unlocked_setups.assign([&"BALANCED"])
	best_medal_ranks.clear()
	rival_victories.clear()
	transaction_log.clear()
	_emit_and_save()


func _on_activity_started(activity: StringName) -> void:
	_active_activity = activity


func _on_race_finished(time_usec: int, medal: StringName, is_new_best: bool) -> void:
	var cash_reward := 200
	var reputation_reward := 25
	match medal:
		&"GOLD":
			cash_reward = 900
			reputation_reward = 120
		&"SILVER":
			cash_reward = 600
			reputation_reward = 80
		&"BRONZE":
			cash_reward = 350
			reputation_reward = 50
	if is_new_best:
		cash_reward += 250
		reputation_reward += 25
	var old_cash := cash
	cash = mini(cash + cash_reward, MAX_CASH)
	racer_reputation += reputation_reward
	total_runs += 1
	_record_best_medal(_active_activity, medal)
	var rival_target: int = int(ROOK_TARGETS_USEC.get(_active_activity, -1))
	if rival_target > 0 and time_usec <= rival_target and not rival_victories.has(_active_activity):
		rival_victories.append(_active_activity)
	_record_transaction(cash - old_cash, &"race_reward")
	_emit_and_save()
	reward_granted.emit(cash_reward, reputation_reward)


func _on_activity_completed(activity: StringName, result_value: int, medal: StringName, _reported_new_best: bool) -> void:
	var is_new_best := false
	match activity:
		&"FREESTYLE":
			is_new_best = result_value > best_freestyle_score
			if is_new_best:
				best_freestyle_score = result_value
		&"DISCOVERY":
			is_new_best = best_discovery_usec < 0 or result_value < best_discovery_usec
			if is_new_best:
				best_discovery_usec = result_value

	var cash_reward := 175
	var reputation_reward := 20
	match medal:
		&"GOLD":
			cash_reward = 750 if activity == &"DISCOVERY" else 650
			reputation_reward = 110 if activity == &"DISCOVERY" else 90
		&"SILVER":
			cash_reward = 500
			reputation_reward = 65
		&"BRONZE":
			cash_reward = 300
			reputation_reward = 40
	if is_new_best:
		cash_reward += 200
		reputation_reward += 20
	var old_cash := cash
	cash = mini(cash + cash_reward, MAX_CASH)
	if activity == &"FREESTYLE":
		freestyler_reputation += reputation_reward
	elif activity == &"DISCOVERY":
		explorer_reputation += reputation_reward
	else:
		racer_reputation += reputation_reward
	total_runs += 1
	_record_best_medal(activity, medal)
	_record_transaction(cash - old_cash, &"activity_reward")
	_emit_and_save()
	reward_granted.emit(cash_reward, reputation_reward)


func _record_transaction(delta: int, reason: StringName) -> void:
	transaction_log.append({
		&"timestamp_usec": Time.get_ticks_usec(),
		&"delta": delta,
		&"reason": reason,
		&"balance": cash,
	})
	while transaction_log.size() > MAX_LOG_ENTRIES:
		transaction_log.pop_front()


func _record_best_medal(activity: StringName, medal: StringName) -> void:
	var rank := _medal_rank(medal)
	if rank > get_event_medal_rank(activity):
		best_medal_ranks[activity] = rank


func _medal_rank(medal: StringName) -> int:
	match medal:
		&"GOLD":
			return 4
		&"SILVER":
			return 3
		&"BRONZE":
			return 2
		&"FINISHER":
			return 1
		_:
			return 0


func _emit_and_save() -> void:
	profile_changed.emit(cash, racer_reputation, current_setup)
	_save_profile()


func _save_profile() -> void:
	if not persistence_enabled:
		return
	if OS.has_feature("web"):
		if not WebPlatform.save_json(WEB_SAVE_KEY, _profile_to_dictionary()):
			push_warning("Unable to save rider profile to browser storage.")
		return
	var config := ConfigFile.new()
	var profile_data := _profile_to_dictionary()
	for key: String in profile_data:
		config.set_value("profile", key, profile_data[key])
	var error := config.save(SAVE_PATH)
	if error != OK:
		push_warning("Unable to save rider profile: %s" % error_string(error))


func _load_profile() -> void:
	if OS.has_feature("web"):
		var web_data: Variant = WebPlatform.load_json(WEB_SAVE_KEY)
		if web_data is Dictionary:
			_apply_profile_dictionary(web_data as Dictionary)
		return
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	var profile_data: Dictionary = {
		"cash": config.get_value("profile", "cash", 0),
		"racer_reputation": config.get_value("profile", "racer_reputation", 0),
		"freestyler_reputation": config.get_value("profile", "freestyler_reputation", 0),
		"explorer_reputation": config.get_value("profile", "explorer_reputation", 0),
		"total_runs": config.get_value("profile", "total_runs", 0),
		"current_setup": config.get_value("profile", "current_setup", "BALANCED"),
		"best_freestyle_score": config.get_value("profile", "best_freestyle_score", 0),
		"best_discovery_usec": config.get_value("profile", "best_discovery_usec", -1),
		"bike_condition": config.get_value("profile", "bike_condition", 100),
		"unlocked_setups": config.get_value("profile", "unlocked_setups", PackedStringArray(["BALANCED"])),
		"best_medal_ranks": config.get_value("profile", "best_medal_ranks", {}),
		"rival_victories": config.get_value("profile", "rival_victories", PackedStringArray()),
	}
	_apply_profile_dictionary(profile_data)


func _profile_to_dictionary() -> Dictionary:
	var setup_names: Array[String] = []
	for setup: StringName in unlocked_setups:
		setup_names.append(String(setup))
	return {
		"cash": cash,
		"racer_reputation": racer_reputation,
		"freestyler_reputation": freestyler_reputation,
		"explorer_reputation": explorer_reputation,
		"total_runs": total_runs,
		"current_setup": String(current_setup),
		"best_freestyle_score": best_freestyle_score,
		"best_discovery_usec": best_discovery_usec,
		"bike_condition": bike_condition,
		"unlocked_setups": setup_names,
		"best_medal_ranks": _serialize_medal_ranks(),
		"rival_victories": _serialize_string_names(rival_victories),
	}


func _apply_profile_dictionary(profile_data: Dictionary) -> void:
	cash = clampi(int(profile_data.get("cash", 0)), 0, MAX_CASH)
	racer_reputation = maxi(int(profile_data.get("racer_reputation", 0)), 0)
	freestyler_reputation = maxi(int(profile_data.get("freestyler_reputation", 0)), 0)
	explorer_reputation = maxi(int(profile_data.get("explorer_reputation", 0)), 0)
	total_runs = maxi(int(profile_data.get("total_runs", 0)), 0)
	current_setup = StringName(str(profile_data.get("current_setup", "BALANCED")))
	best_freestyle_score = maxi(int(profile_data.get("best_freestyle_score", 0)), 0)
	best_discovery_usec = int(profile_data.get("best_discovery_usec", -1))
	bike_condition = clampi(int(profile_data.get("bike_condition", 100)), 0, 100)
	unlocked_setups.clear()
	var loaded_setups: Variant = profile_data.get("unlocked_setups", ["BALANCED"])
	if loaded_setups is Array or loaded_setups is PackedStringArray:
		for setup_name: Variant in loaded_setups:
			unlocked_setups.append(StringName(str(setup_name)))
	if not unlocked_setups.has(&"BALANCED"):
		unlocked_setups.push_front(&"BALANCED")
	if not unlocked_setups.has(current_setup):
		current_setup = &"BALANCED"
	best_medal_ranks.clear()
	var loaded_medals: Variant = profile_data.get("best_medal_ranks", {})
	if loaded_medals is Dictionary:
		for activity_key: Variant in loaded_medals:
			var activity := StringName(str(activity_key).to_upper())
			if activity in TOUR_EVENTS:
				best_medal_ranks[activity] = clampi(int(loaded_medals[activity_key]), 0, 4)
	rival_victories.clear()
	var loaded_victories: Variant = profile_data.get("rival_victories", [])
	if loaded_victories is Array or loaded_victories is PackedStringArray:
		for activity_name: Variant in loaded_victories:
			var activity := StringName(str(activity_name).to_upper())
			if activity in ROOK_TARGETS_USEC and not rival_victories.has(activity):
				rival_victories.append(activity)


func _serialize_medal_ranks() -> Dictionary:
	var serialized: Dictionary = {}
	for activity: StringName in best_medal_ranks:
		serialized[String(activity)] = best_medal_ranks[activity]
	return serialized


func _serialize_string_names(values: Array[StringName]) -> Array[String]:
	var serialized: Array[String] = []
	for value: StringName in values:
		serialized.append(String(value))
	return serialized
