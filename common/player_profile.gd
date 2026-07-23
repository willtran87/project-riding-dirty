extends Node
## Owns persistent integer currency, racing reputation, setup unlocks, and transaction history.

signal profile_changed(cash: int, racer_reputation: int, current_setup: StringName)
signal reward_granted(cash_reward: int, reputation_reward: int)
signal meta_progress_changed(snapshot: Dictionary)
signal race_result_recorded(summary: Dictionary)
signal achievement_unlocked(achievement_id: StringName)

const SAVE_PATH: String = "user://rider_profile.cfg"
const WEB_SAVE_KEY: String = "rider_profile_v1"
const ATOMIC_CONFIG_STORE := preload("res://common/atomic_config_store.gd")
const PROFILE_SCHEMA_VERSION: int = 6
const COURSE_LAYOUT_VERSION: int = 4
const MAX_CASH: int = 999_999
const MAX_LOG_ENTRIES: int = 30
const MAX_RESULT_IDS: int = 64
const MAX_ACTIVITY_RESULT_IDS: int = 64
const MAX_ACADEMY_RESULT_BINDINGS: int = 128
const MAX_EVENT_RECORDS: int = 64
const MAX_CHALLENGE_RECORDS: int = 64
const MAX_LEADERBOARD_SUMMARIES: int = 48
const MAX_SAVED_BUILD_SLOTS: int = 3
const SAVED_BUILD_SLOT_IDS: Array[StringName] = [&"BUILD_A", &"BUILD_B", &"BUILD_C"]
## Setup prices follow the minimum no-medal progression path. Two distinct
## first-time Quarry activity clears fund Trail; Pine plus the two pre-Heat
## Mesa sessions fund Attack. Optional repairs and Workshop purchases can delay
## either unlock, but the authored route itself never advertises an impossible
## strategy.
const SETUP_PRICES: Dictionary[StringName, int] = {
	&"TRAIL": 750,
	&"ATTACK": 1_500,
}
const TOUR_EVENTS: Array[StringName] = [&"CIRCUIT", &"FREESTYLE", &"DISCOVERY", &"PINE_ENDURO"]
const QUARRY_EVENTS: Array[StringName] = [&"CIRCUIT", &"FREESTYLE", &"DISCOVERY"]
const RACE_EVENTS: Array[StringName] = [&"CIRCUIT", &"PINE_ENDURO"]
const ROOK_TARGETS_USEC: Dictionary[StringName, int] = {
	&"CIRCUIT": 190_000_000,
	&"PINE_ENDURO": 285_000_000,
}
const CHAMPIONSHIP_SERVICE_SCRIPT := preload("res://features/career/championship_service.gd")
const WEEKEND_DIRECTOR_SCRIPT := preload("res://features/career/race_weekend_director.gd")
const BIKE_BUILD_SCRIPT := preload("res://features/career/racing_bike_build.gd")
const BIKE_TUNE_SCRIPT := preload("res://features/career/racing_bike_tune.gd")
const BIKE_CATALOG_SCRIPT := preload("res://features/career/racing_bike_catalog.gd")
const ACADEMY_CATALOG_SCRIPT := preload("res://features/career/academy_lesson_catalog.gd")
const ACTIVITY_RUN_IDENTITY_SCRIPT := preload("res://common/activity_run_identity.gd")
const DEFAULT_SETTINGS_REFERENCE: String = "user://settings/riding_dirty_settings.json"
const ACHIEVEMENT_ORDER: Array[StringName] = [
	&"FIRST_FINISH", &"FIRST_WIN", &"PODIUM_REGULAR", &"HOLESHOT_HERO",
	&"CENTURY_LAPS", &"PASS_MASTER", &"ACADEMY_GRADUATE", &"DIRT_TOUR_CHAMPION",
]
const ACHIEVEMENT_DEFINITIONS: Dictionary = {
	&"FIRST_FINISH": {&"title": "First Dust", &"description": "Finish your first classified race.", &"source": &"STAT", &"key": &"finishes", &"target": 1},
	&"FIRST_WIN": {&"title": "Top Step", &"description": "Win a classified race.", &"source": &"STAT", &"key": &"wins", &"target": 1},
	&"PODIUM_REGULAR": {&"title": "Podium Regular", &"description": "Earn five podium finishes.", &"source": &"STAT", &"key": &"podiums", &"target": 5},
	&"HOLESHOT_HERO": {&"title": "Holeshot Hero", &"description": "Take five holeshots.", &"source": &"STAT", &"key": &"holeshots", &"target": 5},
	&"CENTURY_LAPS": {&"title": "Century Rider", &"description": "Complete one hundred race laps.", &"source": &"STAT", &"key": &"laps_completed", &"target": 100},
	&"PASS_MASTER": {&"title": "Pass Master", &"description": "Complete one hundred player overtakes.", &"source": &"STAT", &"key": &"overtakes", &"target": 100},
	&"ACADEMY_GRADUATE": {&"title": "Academy Graduate", &"description": "Pass every Riding Academy lesson.", &"source": &"ACADEMY", &"target": 8},
	&"DIRT_TOUR_CHAMPION": {&"title": "Dirt Tour Champion", &"description": "Win a complete Dirt Tour season.", &"source": &"UNLOCK", &"target": 1},
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
var contract_completions: int = 0
var style_tokens: int = 0
var completed_contracts: Array[String] = []
var assist_mode: StringName = &"SPORT"
var unlocked_feats: Array[String] = []
var legacy_pine_unlock: bool = false
var first_run_onboarding_complete: bool = false

# Versioned full-race meta state. These remain plain dictionaries at the
# persistence boundary so desktop ConfigFile and browser JSON saves share the
# exact same schema. Typed career services are reconstructed by the public APIs.
var profile_id: String = ""
var championship_snapshot: Dictionary = {}
var race_weekend_snapshot: Dictionary = {}
var owned_bike_builds: Dictionary = {}
var active_bike_id: StringName = &"TYKE_125"
var selected_bike_class: StringName = &"LITE_125"
var owned_part_ids: Array[StringName] = []
var saved_bike_builds: Dictionary = {}
var academy_progress: Dictionary[StringName, int] = {}
var rider_cosmetics: Dictionary = {}
var race_statistics: Dictionary = {}
var event_records: Dictionary = {}
var challenge_records: Dictionary = {}
var achievements: Array[StringName] = []
var leaderboard_summary: Dictionary = {}
var settings_reference: String = DEFAULT_SETTINGS_REFERENCE
var recent_result_ids: Array[String] = []
var recent_activity_result_ids: Array[String] = []
var academy_result_bindings: Dictionary[String, StringName] = {}

var _active_activity: StringName = &"CIRCUIT"
var _active_activity_runs: Dictionary[StringName, String] = {}
var _active_race_run: Dictionary = {}
var _profile_migration_pending: bool = false
var _settlement_signals_deferred: bool = false
var _deferred_reward_grants: Array[Dictionary] = []
var _deferred_achievements: Array[StringName] = []


func _ready() -> void:
	# Autoloads initialize before Main can isolate a command-line smoke run.
	# Disable persistence here as the first operation so test setup and schema
	# migration can never rewrite a real rider profile.
	if &"--smoke-test" in OS.get_cmdline_user_args():
		persistence_enabled = false
	_load_profile()
	_ensure_full_race_defaults()
	if _profile_migration_pending:
		if _save_profile():
			_profile_migration_pending = false
	EventBus.activity_started.connect(_on_activity_started)


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


func is_first_run_onboarding_active() -> bool:
	return not first_run_onboarding_complete


func complete_first_run_onboarding() -> bool:
	if first_run_onboarding_complete:
		return false
	first_run_onboarding_complete = true
	_emit_meta_and_save()
	return true


func get_event_medal_rank(activity: StringName, challenge_id: StringName = &"") -> int:
	# Academy's visible completion state comes from lesson grading, never from
	# the generic route-time medal stored by older profiles or race telemetry.
	if activity == &"ACADEMY":
		var best_lesson_stars := 0
		for raw_stars: Variant in academy_progress.values():
			best_lesson_stars = maxi(best_lesson_stars, clampi(int(raw_stars), 0, 3))
		return best_lesson_stars + 1 if best_lesson_stars > 0 else 0
	if not challenge_id.is_empty():
		var challenge_record := get_challenge_record(challenge_id, activity)
		return clampi(int(challenge_record.get(&"best_medal_rank", 0)), 0, 4)
	return best_medal_ranks.get(activity, 0)


func get_event_medal(activity: StringName, challenge_id: StringName = &"") -> StringName:
	match get_event_medal_rank(activity, challenge_id):
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


func has_completed_event(activity: StringName, challenge_id: StringName = &"") -> bool:
	return get_event_medal_rank(activity, challenge_id) > 0


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
	return legacy_pine_unlock or _meets_pine_unlock_requirements()


func _meets_pine_unlock_requirements() -> bool:
	return get_quarry_progress_count() >= 2 or has_beaten_rival(&"CIRCUIT") or get_total_reputation() >= 80


func get_activity_unlock_hint(activity: StringName) -> String:
	if is_activity_unlocked(activity):
		return ""
	if activity == &"PINE_ENDURO":
		return "COMPLETE ANY TWO QUARRY EVENTS OR BEAT ROOK'S QUARRY TIME"
	return "KEEP BUILDING YOUR TOUR REPUTATION"


func get_setup_price(setup: StringName) -> int:
	return int(SETUP_PRICES.get(setup, 0))


func get_setup_purchase_snapshot(setup: StringName) -> Dictionary:
	var owned := is_setup_unlocked(setup)
	var price := get_setup_price(setup)
	return {
		&"setup_id": setup,
		&"owned": owned,
		&"price": price,
		&"affordable": owned or (price > 0 and cash >= price),
		&"shortfall": 0 if owned else maxi(price - cash, 0),
	}


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
	var build_data := get_bike_build_snapshot(active_bike_id)
	if not build_data.is_empty():
		build_data[&"condition"] = float(bike_condition) / 100.0
		owned_bike_builds[active_bike_id] = build_data
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
	var build_data := get_bike_build_snapshot(active_bike_id)
	if not build_data.is_empty():
		build_data[&"condition"] = 1.0
		owned_bike_builds[active_bike_id] = build_data
	_emit_and_save()
	return true


func complete_contract(contract_id: String, activity: StringName, cash_reward: int = 350, reputation_reward: int = 35) -> bool:
	if contract_id.is_empty() or completed_contracts.has(contract_id):
		return false
	var rollback_profile := _profile_to_dictionary()
	var rollback_transactions := transaction_log.duplicate(true)
	var rollback_migration := _profile_migration_pending
	_begin_settlement_signal_batch()
	completed_contracts.append(contract_id)
	while completed_contracts.size() > 60:
		completed_contracts.pop_front()
	contract_completions += 1
	style_tokens += 1
	var old_cash := cash
	cash = mini(cash + maxi(cash_reward, 0), MAX_CASH)
	match activity:
		&"FREESTYLE":
			freestyler_reputation += reputation_reward
		&"DISCOVERY":
			explorer_reputation += reputation_reward
		_:
			racer_reputation += reputation_reward
	_record_transaction(cash - old_cash, &"sponsor_contract")
	_emit_or_defer_reward(cash - old_cash, reputation_reward)
	return _commit_profile_transaction(rollback_profile, rollback_transactions, rollback_migration)


func get_cosmetic_tier() -> int:
	return clampi(style_tokens / 2, 0, 3)


func unlock_feat(feat_id: String) -> bool:
	if feat_id.is_empty() or unlocked_feats.has(feat_id):
		return false
	var rollback_profile := _profile_to_dictionary()
	var rollback_transactions := transaction_log.duplicate(true)
	var rollback_migration := _profile_migration_pending
	_begin_settlement_signal_batch()
	unlocked_feats.append(feat_id)
	style_tokens += 1
	_record_transaction(0, &"riding_feat")
	return _commit_profile_transaction(rollback_profile, rollback_transactions, rollback_migration)


func cycle_assist_mode() -> StringName:
	match assist_mode:
		&"ASSISTED":
			assist_mode = &"SPORT"
		&"SPORT":
			assist_mode = &"PRO"
		_:
			assist_mode = &"ASSISTED"
	_emit_and_save()
	return assist_mode


func get_profile_id() -> String:
	_ensure_full_race_defaults()
	return profile_id


func get_meta_snapshot() -> Dictionary:
	_ensure_full_race_defaults()
	return {
		&"profile_schema_version": PROFILE_SCHEMA_VERSION,
		&"profile_id": profile_id,
		&"championship": championship_snapshot.duplicate(true),
		&"race_weekend": race_weekend_snapshot.duplicate(true),
		&"owned_bike_builds": owned_bike_builds.duplicate(true),
		&"active_bike_id": active_bike_id,
		&"selected_bike_class": selected_bike_class,
		&"owned_part_ids": owned_part_ids.duplicate(),
		&"saved_bike_builds": saved_bike_builds.duplicate(true),
		&"academy_progress": academy_progress.duplicate(true),
		&"rider_cosmetics": rider_cosmetics.duplicate(true),
		&"race_statistics": race_statistics.duplicate(true),
		&"event_records": event_records.duplicate(true),
		&"challenge_records": challenge_records.duplicate(true),
		&"achievements": achievements.duplicate(),
		&"leaderboard_summary": leaderboard_summary.duplicate(true),
		&"settings_reference": settings_reference,
		&"first_run_onboarding_complete": first_run_onboarding_complete,
	}


func get_championship_service() -> Variant:
	_ensure_full_race_defaults()
	return CHAMPIONSHIP_SERVICE_SCRIPT.from_dictionary(championship_snapshot)


func set_championship_snapshot(snapshot: Dictionary) -> bool:
	var service: Variant = CHAMPIONSHIP_SERVICE_SCRIPT.from_dictionary(snapshot)
	var sanitized: Dictionary = service.to_dictionary()
	if sanitized.is_empty():
		return false
	championship_snapshot = sanitized
	_emit_meta_and_save()
	return true


func record_championship_round(
	round_id: StringName,
	classification: Array[Dictionary],
	finalize: bool = true
) -> bool:
	var rollback_profile: Dictionary = {}
	var rollback_transactions: Array[Dictionary] = []
	var rollback_migration := false
	if finalize:
		rollback_profile = _profile_to_dictionary()
		rollback_transactions.assign(transaction_log.duplicate(true))
		rollback_migration = _profile_migration_pending
		_begin_settlement_signal_batch()
	var service: Variant = get_championship_service()
	if not service.record_round_result(round_id, classification):
		if finalize:
			_flush_settlement_signal_batch(false)
		return false
	championship_snapshot = service.to_dictionary()
	var champion: Dictionary = service.get_champion()
	if not champion.is_empty() and StringName(_dictionary_value(champion, "rider_id", &"")) == &"PLAYER":
		_unlock_achievement(&"DIRT_TOUR_CHAMPION")
	if finalize:
		return _commit_profile_transaction(rollback_profile, rollback_transactions, rollback_migration)
	return true


func start_next_championship_season() -> bool:
	var service: Variant = get_championship_service()
	if service == null or not service.start_next_season():
		return false
	championship_snapshot = service.to_dictionary()
	# A fresh season also needs a fresh Red Mesa weekend. Reuse the persisted
	# entrant configuration so player customization and roster identity survive.
	var weekend: Variant = get_race_weekend_director()
	if weekend != null:
		weekend.reset()
		weekend.start_weekend()
		race_weekend_snapshot = weekend.to_dictionary()
	else:
		race_weekend_snapshot.clear()
	_emit_meta_and_save()
	return true


func get_race_weekend_director() -> Variant:
	if race_weekend_snapshot.is_empty():
		return null
	return WEEKEND_DIRECTOR_SCRIPT.from_dictionary(race_weekend_snapshot)


func set_race_weekend_snapshot(snapshot: Dictionary) -> bool:
	if snapshot.is_empty():
		race_weekend_snapshot.clear()
		_emit_meta_and_save()
		return true
	var director: Variant = WEEKEND_DIRECTOR_SCRIPT.from_dictionary(snapshot)
	var sanitized: Dictionary = director.to_dictionary()
	if sanitized.is_empty():
		return false
	race_weekend_snapshot = sanitized
	_emit_meta_and_save()
	return true


func get_active_bike_build() -> Variant:
	_ensure_full_race_defaults()
	return BIKE_BUILD_SCRIPT.from_dictionary(get_bike_build_snapshot(active_bike_id))


func get_bike_build_snapshot(bike_id: StringName) -> Dictionary:
	var raw: Variant = owned_bike_builds.get(bike_id, owned_bike_builds.get(String(bike_id), {}))
	return (raw as Dictionary).duplicate(true) if raw is Dictionary else {}


func get_active_bike_setup_snapshot() -> Dictionary:
	var build: Variant = get_active_bike_build()
	var catalog: Variant = BIKE_CATALOG_SCRIPT.create_default()
	return {
		&"build": build.to_dictionary(),
		&"stats": build.calculate_stats(catalog),
		&"eligible_classes": build.eligible_classes(catalog, racer_reputation),
		&"selected_class": selected_bike_class,
		&"signature": build.signature(),
	}


func get_saved_bike_build_snapshot(slot_id: StringName) -> Dictionary:
	var normalized_slot := StringName(String(slot_id).strip_edges().to_upper())
	if normalized_slot not in SAVED_BUILD_SLOT_IDS:
		return {}
	var raw: Variant = saved_bike_builds.get(
		normalized_slot,
		saved_bike_builds.get(String(normalized_slot), {})
	)
	return (raw as Dictionary).duplicate(true) if raw is Dictionary else {}


func get_saved_bike_build_slots() -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for slot_index: int in SAVED_BUILD_SLOT_IDS.size():
		var slot_id := SAVED_BUILD_SLOT_IDS[slot_index]
		var snapshot := get_saved_bike_build_snapshot(slot_id)
		output.append({
			&"slot_id": slot_id,
			&"slot_label": String.chr(65 + slot_index),
			&"occupied": not snapshot.is_empty(),
			&"build": snapshot,
		})
	return output


func save_current_bike_build(slot_id: StringName, display_name: String = "") -> Dictionary:
	var normalized_slot := StringName(String(slot_id).strip_edges().to_upper())
	if normalized_slot not in SAVED_BUILD_SLOT_IDS:
		return {&"accepted": false, &"reason": &"INVALID_SLOT", &"slot_id": normalized_slot}
	var active_build := get_bike_build_snapshot(active_bike_id)
	if active_build.is_empty():
		return {&"accepted": false, &"reason": &"NO_ACTIVE_BUILD", &"slot_id": normalized_slot}
	var rollback_profile := _profile_to_dictionary()
	var rollback_transactions := transaction_log.duplicate(true)
	var rollback_migration := _profile_migration_pending
	_begin_settlement_signal_batch()
	var resolved_name := _sanitize_saved_build_name(display_name)
	if resolved_name.is_empty():
		resolved_name = _default_saved_build_name(active_bike_id, current_setup)
	var build: Variant = BIKE_BUILD_SCRIPT.from_dictionary(active_build)
	var snapshot := {
		&"slot_id": normalized_slot,
		&"display_name": resolved_name,
		&"bike_id": active_bike_id,
		&"setup_id": current_setup,
		&"selected_class": selected_bike_class,
		&"installed_parts": build.installed_parts.duplicate(true),
		&"tune": build.tune.to_dictionary(),
		&"livery_id": StringName(rider_cosmetics.get(&"bike_livery", build.livery_id)),
		&"saved_unix": int(Time.get_unix_time_from_system()),
	}
	var sanitized_snapshot := _sanitize_saved_build_entry(normalized_slot, snapshot)
	if sanitized_snapshot.is_empty():
		_flush_settlement_signal_batch(false)
		return {&"accepted": false, &"reason": &"BUILD_UNAVAILABLE", &"slot_id": normalized_slot}
	saved_bike_builds[normalized_slot] = sanitized_snapshot
	if not _commit_profile_transaction(rollback_profile, rollback_transactions, rollback_migration):
		return {&"accepted": false, &"reason": &"SAVE_FAILED", &"slot_id": normalized_slot}
	return {
		&"accepted": true,
		&"reason": &"SAVED",
		&"slot_id": normalized_slot,
		&"build": sanitized_snapshot.duplicate(true),
	}


func load_saved_bike_build(slot_id: StringName) -> Dictionary:
	var normalized_slot := StringName(String(slot_id).strip_edges().to_upper())
	if normalized_slot not in SAVED_BUILD_SLOT_IDS:
		return {&"accepted": false, &"reason": &"INVALID_SLOT", &"slot_id": normalized_slot}
	var stored := get_saved_bike_build_snapshot(normalized_slot)
	if stored.is_empty():
		return {&"accepted": false, &"reason": &"EMPTY_SLOT", &"slot_id": normalized_slot}
	var sanitized := _sanitize_saved_build_entry(normalized_slot, stored)
	if sanitized.is_empty():
		return {&"accepted": false, &"reason": &"BUILD_UNAVAILABLE", &"slot_id": normalized_slot}
	var target_bike := StringName(sanitized.get(&"bike_id", &""))
	var target_build_data := get_bike_build_snapshot(target_bike)
	if target_build_data.is_empty():
		return {&"accepted": false, &"reason": &"BIKE_UNAVAILABLE", &"slot_id": normalized_slot}
	var rollback_profile := _profile_to_dictionary()
	var rollback_transactions := transaction_log.duplicate(true)
	var rollback_migration := _profile_migration_pending
	_begin_settlement_signal_batch()
	# A saved build is a reusable configuration, not a durability rollback. Keep
	# the target bike's live condition and odometer while restoring its strategy.
	var target_build: Variant = BIKE_BUILD_SCRIPT.from_dictionary(target_build_data)
	target_build.installed_parts = (sanitized.get(&"installed_parts", {}) as Dictionary).duplicate(true)
	target_build.tune = BIKE_TUNE_SCRIPT.from_dictionary(sanitized.get(&"tune", {}) as Dictionary)
	target_build.livery_id = StringName(sanitized.get(&"livery_id", &"FACTORY"))
	owned_bike_builds[target_bike] = target_build.to_dictionary()
	active_bike_id = target_bike
	current_setup = StringName(sanitized.get(&"setup_id", &"BALANCED"))
	bike_condition = clampi(roundi(target_build.condition * 100.0), 0, 100)
	var eligible: Array[StringName] = target_build.eligible_classes(
		BIKE_CATALOG_SCRIPT.create_default(), racer_reputation
	)
	var saved_class := StringName(sanitized.get(&"selected_class", &""))
	selected_bike_class = saved_class if saved_class in eligible else (
		eligible[0] if not eligible.is_empty() else &"OPEN"
	)
	var proposed_cosmetics := rider_cosmetics.duplicate(true)
	proposed_cosmetics[&"bike_livery"] = String(target_build.livery_id)
	rider_cosmetics = _sanitize_cosmetics(proposed_cosmetics)
	if not _commit_profile_transaction(rollback_profile, rollback_transactions, rollback_migration):
		return {&"accepted": false, &"reason": &"SAVE_FAILED", &"slot_id": normalized_slot}
	return {
		&"accepted": true,
		&"reason": &"LOADED",
		&"slot_id": normalized_slot,
		&"build": sanitized.duplicate(true),
		&"active_setup": get_active_bike_setup_snapshot(),
	}


func upsert_bike_build(build_value: Variant) -> bool:
	var data: Dictionary = {}
	if build_value is Dictionary:
		data = (build_value as Dictionary).duplicate(true)
	elif build_value is Object and is_instance_valid(build_value) and build_value.has_method("to_dictionary"):
		data = build_value.to_dictionary()
	if data.is_empty():
		return false
	var build: Variant = BIKE_BUILD_SCRIPT.from_dictionary(data)
	var bike_id := StringName(build.bike_id)
	var catalog: Variant = BIKE_CATALOG_SCRIPT.create_default()
	if bike_id.is_empty() or not catalog.has_bike(bike_id):
		return false
	owned_bike_builds[bike_id] = build.to_dictionary()
	if active_bike_id.is_empty():
		active_bike_id = bike_id
	_emit_meta_and_save()
	return true


func set_active_bike(bike_id: StringName) -> bool:
	var target_build := get_bike_build_snapshot(bike_id)
	if target_build.is_empty():
		return false
	active_bike_id = bike_id
	bike_condition = clampi(roundi(float(target_build.get(&"condition", 1.0)) * 100.0), 0, 100)
	var eligible: Array[StringName] = get_active_bike_build().eligible_classes(BIKE_CATALOG_SCRIPT.create_default(), racer_reputation)
	if selected_bike_class not in eligible:
		selected_bike_class = eligible[0] if not eligible.is_empty() else &"OPEN"
	_emit_meta_and_save()
	return true


func purchase_racing_bike(bike_id: StringName) -> bool:
	if not get_bike_build_snapshot(bike_id).is_empty():
		return true
	var catalog: Variant = BIKE_CATALOG_SCRIPT.create_default()
	var definition: Dictionary = catalog.get_bike(bike_id)
	if definition.is_empty() or racer_reputation < int(definition.get(&"required_reputation", 0)):
		return false
	var price := maxi(int(definition.get(&"price", 0)), 0)
	if cash < price:
		return false
	cash -= price
	_record_transaction(-price, &"race_bike_purchase")
	var build: Variant = BIKE_BUILD_SCRIPT.new()
	build.bike_id = bike_id
	owned_bike_builds[bike_id] = build.to_dictionary()
	active_bike_id = bike_id
	bike_condition = 100
	_emit_and_save()
	return true


func purchase_racing_part(part_id: StringName) -> bool:
	if owned_part_ids.has(part_id):
		return true
	var catalog: Variant = BIKE_CATALOG_SCRIPT.create_default()
	var definition: Dictionary = catalog.get_part(part_id)
	if definition.is_empty() or racer_reputation < int(definition.get(&"required_reputation", 0)):
		return false
	var price := maxi(int(definition.get(&"price", 0)), 0)
	if cash < price:
		return false
	cash -= price
	_record_transaction(-price, &"race_part_purchase")
	owned_part_ids.append(part_id)
	_emit_and_save()
	return true


func install_racing_part(part_id: StringName, bike_id: StringName = &"") -> bool:
	if not owned_part_ids.has(part_id):
		return false
	var target_id := bike_id if not bike_id.is_empty() else active_bike_id
	var build_data := get_bike_build_snapshot(target_id)
	if build_data.is_empty():
		return false
	var build: Variant = BIKE_BUILD_SCRIPT.from_dictionary(build_data)
	if not build.install_part(BIKE_CATALOG_SCRIPT.create_default(), part_id):
		return false
	owned_bike_builds[target_id] = build.to_dictionary()
	_emit_meta_and_save()
	return true


func set_bike_tune(tune_data: Dictionary, bike_id: StringName = &"") -> bool:
	var target_id := bike_id if not bike_id.is_empty() else active_bike_id
	var build_data := get_bike_build_snapshot(target_id)
	if build_data.is_empty():
		return false
	var build: Variant = BIKE_BUILD_SCRIPT.from_dictionary(build_data)
	build.tune = BIKE_TUNE_SCRIPT.from_dictionary(tune_data)
	owned_bike_builds[target_id] = build.to_dictionary()
	_emit_meta_and_save()
	return true


func set_selected_bike_class(class_id: StringName) -> bool:
	var build: Variant = get_active_bike_build()
	var eligible: Array[StringName] = build.eligible_classes(BIKE_CATALOG_SCRIPT.create_default(), racer_reputation)
	if class_id not in eligible:
		return false
	selected_bike_class = class_id
	_emit_meta_and_save()
	return true


func get_completed_academy_lessons() -> Array[StringName]:
	var completed: Array[StringName] = []
	for lesson_id: StringName in academy_progress:
		if academy_progress[lesson_id] > 0:
			completed.append(lesson_id)
	completed.sort_custom(func(first: StringName, second: StringName) -> bool: return String(first) < String(second))
	return completed


func get_academy_progress_snapshot() -> Dictionary:
	return academy_progress.duplicate(true)


func get_race_statistics() -> Dictionary:
	_ensure_full_race_defaults()
	return race_statistics.duplicate(true)


func get_event_record(event_id: StringName, challenge_id: StringName = &"") -> Dictionary:
	if not challenge_id.is_empty():
		return get_challenge_record(challenge_id, event_id)
	var record: Variant = event_records.get(event_id, event_records.get(String(event_id), {}))
	return (record as Dictionary).duplicate(true) if record is Dictionary else {}


func get_challenge_record(challenge_id: StringName, event_id: StringName = &"") -> Dictionary:
	if challenge_id.is_empty():
		return {}
	var record_value: Variant = challenge_records.get(challenge_id, challenge_records.get(String(challenge_id), {}))
	if not record_value is Dictionary:
		return {}
	var record := (record_value as Dictionary).duplicate(true)
	if not event_id.is_empty() and StringName(record.get(&"event_id", &"")) != event_id:
		return {}
	return record


func get_achievement_ids() -> Array[StringName]:
	return achievements.duplicate()


func get_achievement_progress_snapshot() -> Dictionary:
	## Stable, presentation-ready milestone progress. This keeps the Garage from
	## reimplementing achievement criteria and gives locked goals visible context.
	_ensure_full_race_defaults()
	var academy_total := ACADEMY_CATALOG_SCRIPT.create_default().get_lessons().size()
	var academy_completed := get_completed_academy_lessons().size()
	var items: Array[Dictionary] = []
	var next_item: Dictionary = {}
	var next_ratio := -1.0
	var unlocked_count := 0
	for achievement_id: StringName in ACHIEVEMENT_ORDER:
		var definition := get_achievement_definition(achievement_id)
		var target := maxi(int(definition.get(&"target", 1)), 1)
		var unlocked := achievements.has(achievement_id)
		unlocked_count += int(unlocked)
		var current := 0
		match StringName(definition.get(&"source", &"UNLOCK")):
			&"STAT":
				current = maxi(int(race_statistics.get(StringName(definition.get(&"key", &"")), 0)), 0)
			&"ACADEMY":
				target = maxi(academy_total, 1)
				current = academy_completed
			_:
				current = target if unlocked else 0
		current = mini(current, target)
		var entry := definition.duplicate(true)
		entry[&"achievement_id"] = achievement_id
		entry[&"current"] = current
		entry[&"target"] = target
		entry[&"unlocked"] = unlocked
		entry[&"progress"] = 1.0 if unlocked else clampf(float(current) / float(target), 0.0, 1.0)
		items.append(entry)
		if not unlocked and float(entry[&"progress"]) > next_ratio:
			next_ratio = float(entry[&"progress"])
			next_item = entry.duplicate(true)
	return {
		&"unlocked": unlocked_count,
		&"total": ACHIEVEMENT_ORDER.size(),
		&"items": items,
		&"next": next_item,
		&"complete": unlocked_count >= ACHIEVEMENT_ORDER.size(),
	}


static func get_achievement_definition(achievement_id: StringName) -> Dictionary:
	var definition: Variant = ACHIEVEMENT_DEFINITIONS.get(achievement_id, {})
	if definition is Dictionary and not (definition as Dictionary).is_empty():
		return (definition as Dictionary).duplicate(true)
	return {
		&"title": String(achievement_id).replace("_", " ").capitalize(),
		&"description": "A new Riding Dirty milestone.",
	}


func record_academy_result(lesson_id: StringName, metrics: Dictionary, finalize: bool = true) -> Dictionary:
	var catalog: Variant = ACADEMY_CATALOG_SCRIPT.create_default()
	var lesson: Dictionary = catalog.get_lesson(lesson_id)
	var available: Array[Dictionary] = catalog.get_available_lessons(get_completed_academy_lessons(), racer_reputation)
	var is_available := false
	for available_lesson: Dictionary in available:
		if StringName(available_lesson.get(&"lesson_id", &"")) == lesson_id:
			is_available = true
			break
	if not is_available:
		return {
			&"lesson_id": lesson_id, &"passed": false, &"stars": 0, &"error": &"LOCKED",
			&"objective_results": [], &"credited_rewards": {&"cash": 0, &"credits": 0, &"reputation": 0},
		}
	var evaluation: Dictionary = catalog.evaluate_lesson(lesson_id, metrics)
	var objective_definitions := (lesson.get(&"objectives", []) as Array).duplicate(true)
	var raw_objective_results := evaluation.get(&"objective_results", []) as Array
	var enriched_objective_results: Array[Dictionary] = []
	for index: int in raw_objective_results.size():
		if not raw_objective_results[index] is Dictionary:
			continue
		var objective_result := (raw_objective_results[index] as Dictionary).duplicate(true)
		if index < objective_definitions.size() and objective_definitions[index] is Dictionary:
			var definition := objective_definitions[index] as Dictionary
			objective_result[&"bronze"] = float(definition.get(&"bronze", 0.0))
			objective_result[&"silver"] = float(definition.get(&"silver", definition.get(&"bronze", 0.0)))
			objective_result[&"gold"] = float(definition.get(&"gold", definition.get(&"silver", definition.get(&"bronze", 0.0))))
		enriched_objective_results.append(objective_result)
	evaluation[&"objective_results"] = enriched_objective_results
	evaluation[&"objectives"] = objective_definitions
	evaluation[&"display_name"] = str(lesson.get(&"display_name", lesson_id))
	evaluation[&"category"] = StringName(lesson.get(&"category", &"FOUNDATIONS"))
	evaluation[&"description"] = str(lesson.get(&"description", ""))
	var rollback_profile: Dictionary = {}
	var rollback_transactions: Array[Dictionary] = []
	var rollback_migration := false
	if finalize:
		rollback_profile = _profile_to_dictionary()
		rollback_transactions.assign(transaction_log.duplicate(true))
		rollback_migration = _profile_migration_pending
		_begin_settlement_signal_batch()
	var stars := clampi(int(evaluation.get(&"stars", 0)), 0, 3)
	var previous: int = int(academy_progress.get(lesson_id, 0))
	var improved: bool = stars > previous
	var first_completion: bool = previous == 0 and stars > 0
	var credited_cash := 0
	var credited_reputation := 0
	if improved:
		academy_progress[lesson_id] = stars
	if first_completion:
		first_run_onboarding_complete = true
		var rewards: Dictionary = evaluation.get(&"rewards", {}) as Dictionary
		var cash_reward := maxi(int(rewards.get(&"credits", 0)), 0)
		var reputation_reward := maxi(int(rewards.get(&"reputation", 0)), 0)
		var old_cash := cash
		cash = mini(cash + cash_reward, MAX_CASH)
		racer_reputation += reputation_reward
		credited_cash = cash - old_cash
		credited_reputation = reputation_reward
		_record_transaction(credited_cash, &"academy_reward")
		_emit_or_defer_reward(credited_cash, credited_reputation)
	evaluation[&"previous_stars"] = previous
	evaluation[&"best_stars"] = maxi(previous, stars)
	evaluation[&"new_best"] = improved
	evaluation[&"first_completion"] = first_completion
	evaluation[&"credited_rewards"] = {
		&"cash": credited_cash,
		&"credits": credited_cash,
		&"reputation": credited_reputation,
	}
	_evaluate_meta_achievements()
	if finalize:
		if not _commit_profile_transaction(rollback_profile, rollback_transactions, rollback_migration):
			evaluation[&"accepted"] = false
			evaluation[&"durable"] = false
			evaluation[&"retryable"] = true
			evaluation[&"error"] = &"SAVE_FAILED"
			evaluation[&"credited_rewards"] = {&"cash": 0, &"credits": 0, &"reputation": 0}
			return evaluation
		evaluation[&"accepted"] = true
		evaluation[&"durable"] = true
	return evaluation


func settle_academy_race_result(
	result: Dictionary,
	lesson_id: StringName,
	metrics: Dictionary
) -> Dictionary:
	var event_id := _safe_identifier(_dictionary_value(result, "event_id", &""), &"")
	var payload_lesson_id := _safe_identifier(
		_dictionary_value(result, "academy_lesson_id", &""), &""
	)
	if (
		event_id != &"ACADEMY"
		or lesson_id.is_empty()
		or not _is_safe_identifier(lesson_id)
		or payload_lesson_id != lesson_id
		or not ACADEMY_CATALOG_SCRIPT.create_default().has_lesson(lesson_id)
	):
		return {
			&"accepted": false, &"duplicate": false, &"durable": false,
			&"classified_eligible": false,
			&"reason": &"INVALID_ACADEMY_IDENTITY", &"race_summary": {},
			&"academy_evaluation": {}, &"academy_duplicate": false,
		}

	var classified_eligible := _academy_race_is_eligible(result)
	var expected_result_id := _race_result_fingerprint(result, event_id)
	var legacy_v1_result_id := _legacy_v1_race_result_fingerprint(result, event_id)
	var legacy_raw_result_id := _legacy_race_result_identity(result, event_id)
	var existing_lesson := StringName(academy_result_bindings.get(expected_result_id, &""))
	if existing_lesson.is_empty():
		existing_lesson = StringName(academy_result_bindings.get(legacy_v1_result_id, &""))
	if not existing_lesson.is_empty():
		var same_lesson: bool = existing_lesson == lesson_id
		return {
			&"accepted": false, &"duplicate": same_lesson, &"durable": true,
			&"classified_eligible": classified_eligible,
			&"reason": &"DUPLICATE" if same_lesson else &"ACADEMY_RACE_ALREADY_BOUND",
			&"race_summary": {
				&"accepted": false, &"duplicate": true, &"durable": true,
				&"reason": &"DUPLICATE", &"result_id": expected_result_id,
			},
			&"academy_evaluation": {}, &"academy_duplicate": same_lesson,
			&"academy_result_id": expected_result_id,
			&"bound_lesson_id": existing_lesson,
		}
	# Profiles written before the binding ledger cannot prove which lesson owned a
	# duplicate race. Refuse to guess: guessing would let one race pay every lesson.
	if (
		recent_result_ids.has(expected_result_id)
		or recent_result_ids.has(legacy_v1_result_id)
		or recent_result_ids.has(legacy_raw_result_id)
	):
		return {
			&"accepted": false, &"duplicate": true, &"durable": true,
			&"classified_eligible": classified_eligible,
			&"reason": &"LEGACY_UNBOUND_RACE",
			&"race_summary": {
				&"accepted": false, &"duplicate": true, &"durable": true,
				&"reason": &"DUPLICATE", &"result_id": expected_result_id,
			},
			&"academy_evaluation": {}, &"academy_duplicate": true,
			&"academy_result_id": expected_result_id,
		}

	var rollback_profile := _profile_to_dictionary()
	var rollback_transactions := transaction_log.duplicate(true)
	var rollback_migration := _profile_migration_pending
	_begin_settlement_signal_batch()
	var race_summary := record_race_result(result, false, false)
	var race_accepted := bool(race_summary.get(&"accepted", false))
	if not race_accepted:
		_flush_settlement_signal_batch(false)
		return {
			&"accepted": false,
			&"duplicate": bool(race_summary.get(&"duplicate", false)),
			&"classified_eligible": false,
			&"durable": bool(race_summary.get(&"durable", false)),
			&"reason": (
				&"LEGACY_UNBOUND_RACE"
				if bool(race_summary.get(&"duplicate", false))
				else StringName(race_summary.get(&"reason", &"RACE_REJECTED"))
			),
			&"race_summary": race_summary.duplicate(true),
			&"academy_evaluation": {}, &"academy_duplicate": false,
		}

	var race_result_id := str(race_summary.get(&"result_id", ""))
	if race_result_id != expected_result_id:
		_rollback_profile_transaction(rollback_profile, rollback_transactions, rollback_migration)
		return {
			&"accepted": false, &"duplicate": false, &"durable": false,
			&"classified_eligible": false, &"reason": &"RESULT_ID_MISMATCH",
			&"race_summary": {}, &"academy_evaluation": {}, &"academy_duplicate": false,
		}
	_bind_academy_result(race_result_id, lesson_id)
	var academy_evaluation: Dictionary = {}
	if classified_eligible:
		academy_evaluation = record_academy_result(lesson_id, metrics, false)
	else:
		academy_evaluation = {
			&"lesson_id": lesson_id, &"passed": false, &"stars": 0,
			&"error": &"INELIGIBLE_RACE", &"objective_results": [],
			&"credited_rewards": {&"cash": 0, &"credits": 0, &"reputation": 0},
		}

	if not _commit_profile_transaction(rollback_profile, rollback_transactions, rollback_migration):
		var failed_race_summary := race_summary.duplicate(true)
		failed_race_summary[&"accepted"] = false
		failed_race_summary[&"durable"] = false
		failed_race_summary[&"retryable"] = true
		failed_race_summary[&"reason"] = &"SAVE_FAILED"
		failed_race_summary[&"rewards_granted"] = {&"cash": 0, &"reputation": 0}
		failed_race_summary[&"stats"] = race_statistics.duplicate(true)
		failed_race_summary[&"event_record"] = get_event_record(event_id)
		return {
			&"accepted": false, &"duplicate": false, &"durable": false,
			&"classified_eligible": classified_eligible,
			&"retryable": true, &"reason": &"SAVE_FAILED",
			&"race_summary": failed_race_summary,
			&"academy_evaluation": {}, &"academy_duplicate": false,
			&"academy_result_id": race_result_id,
		}
	if str(_active_race_run.get(&"run_id", "")) == str(_dictionary_value(result, "run_id", "")):
		_active_race_run.clear()
	race_result_recorded.emit(race_summary.duplicate(true))
	return {
		&"accepted": true, &"duplicate": false, &"durable": true,
		&"classified_eligible": classified_eligible,
		&"reason": &"SETTLED",
		&"race_summary": race_summary.duplicate(true),
		&"academy_evaluation": academy_evaluation.duplicate(true),
		&"academy_duplicate": false,
		&"academy_result_id": race_result_id,
	}


func get_rider_cosmetics() -> Dictionary:
	_ensure_full_race_defaults()
	return rider_cosmetics.duplicate(true)


func set_rider_cosmetics(changes: Dictionary) -> bool:
	var proposed := rider_cosmetics.duplicate(true)
	var changed := false
	for key: StringName in [&"helmet", &"jersey", &"pants", &"boots", &"gloves", &"bike_livery", &"number_plate", &"accent_color"]:
		var value: Variant = _dictionary_value(changes, String(key), null)
		if value != null:
			proposed[key] = str(value).strip_edges().substr(0, 48)
			changed = true
	var number_value: Variant = _dictionary_value(changes, "rider_number", null)
	if number_value != null:
		proposed[&"rider_number"] = clampi(int(number_value), 1, 999)
		changed = true
	if not changed:
		return false
	rider_cosmetics = _sanitize_cosmetics(proposed)
	var build_data := get_bike_build_snapshot(active_bike_id)
	if not build_data.is_empty():
		build_data[&"livery_id"] = StringName(rider_cosmetics.get(&"bike_livery", &"FACTORY"))
		owned_bike_builds[active_bike_id] = build_data
	_emit_meta_and_save()
	return true


func record_leaderboard_summary(run_signature: String, submission: Dictionary) -> bool:
	var signature := run_signature.strip_edges().substr(0, 256)
	if signature.is_empty():
		return false
	var entry_value: Variant = _dictionary_value(submission, "entry", submission)
	var entry: Dictionary = entry_value as Dictionary if entry_value is Dictionary else {}
	var time_usec := int(_dictionary_value(entry, "time_usec", _dictionary_value(entry, "effective_time_usec", -1)))
	var rank := maxi(int(_dictionary_value(submission, "rank", _dictionary_value(entry, "rank", 0))), 0)
	leaderboard_summary[signature] = {
		&"rank": rank,
		&"time_usec": time_usec,
		&"personal_best": bool(_dictionary_value(submission, "personal_best", false)),
		&"accepted": bool(_dictionary_value(submission, "accepted", false)),
		&"updated_unix": int(Time.get_unix_time_from_system()),
	}
	_trim_oldest_leaderboard_summaries()
	_emit_meta_and_save()
	return true


func get_leaderboard_summary(run_signature: String = "") -> Dictionary:
	if run_signature.is_empty():
		return leaderboard_summary.duplicate(true)
	var result: Variant = leaderboard_summary.get(run_signature, {})
	return (result as Dictionary).duplicate(true) if result is Dictionary else {}


func set_settings_reference(path: String) -> bool:
	var normalized := path.strip_edges()
	if not normalized.begins_with("user://") or normalized.length() > 180:
		return false
	settings_reference = normalized
	_emit_meta_and_save()
	return true


func record_race_result(
	result: Dictionary,
	apply_result_rewards: bool = false,
	finalize: bool = true
) -> Dictionary:
	_ensure_full_race_defaults()
	var event_id := _safe_identifier(_dictionary_value(result, "event_id", _active_activity), _active_activity)
	if event_id not in RaceEventCatalog.RACE_EVENTS:
		return {
			&"accepted": false, &"duplicate": false, &"durable": false,
			&"reason": &"INVALID_RACE_EVENT", &"invalid_identity": true,
			&"event_id": event_id,
		}
	var is_challenge_event := event_id in [&"DAILY_CHALLENGE", &"WEEKLY_CHALLENGE"]
	var challenge_id := _safe_identifier(_dictionary_value(result, "challenge_id", &""), &"")
	var competition_id := _safe_identifier(_dictionary_value(result, "competition_id", &""), &"")
	var run_id := str(_dictionary_value(result, "run_id", "")).strip_edges()
	var signature := str(_dictionary_value(result, "signature", "")).strip_edges().substr(0, 256)
	var explicit_round := _safe_identifier(
		_dictionary_value(result, "round_id", _dictionary_value(result, "championship_round_id", &"")), &""
	)
	var weekend_phase := _safe_identifier(_dictionary_value(result, "weekend_phase", &""), &"")
	var weekend_id := _safe_identifier(_dictionary_value(result, "weekend_id", &""), &"")
	var weekend_managed := bool(_dictionary_value(result, "weekend_managed", false))
	if run_id.is_empty() or run_id.length() > 160:
		return {
			&"accepted": false, &"duplicate": false, &"durable": false,
			&"reason": &"INVALID_RUN_ID", &"invalid_identity": true,
			&"event_id": event_id,
		}
	var expected_competition_id := ChallengeSchedule.competition_id({
		"challenge_id": String(challenge_id),
		"run_signature": signature,
	})
	var challenge_identity_valid := (
		not is_challenge_event
		or (
			not challenge_id.is_empty()
			and String(challenge_id).begins_with("DAILY_" if event_id == &"DAILY_CHALLENGE" else "WEEKLY_")
			and CompetitiveRunSignature.validate(signature)
			and competition_id == expected_competition_id
		)
	)
	if not challenge_identity_valid:
		return {
			&"accepted": false,
			&"duplicate": false,
			&"durable": false,
			&"reason": &"INVALID_IDENTITY",
			&"invalid_identity": true,
			&"event_id": event_id,
			&"challenge_id": challenge_id,
			&"competition_id": competition_id,
		}
	if not is_challenge_event:
		challenge_id = &""
		competition_id = &""
	var player_time_usec := int(_dictionary_value(result, "player_time_usec", -1))
	var penalty_usec := maxi(int(_dictionary_value(result, "player_penalty_usec", 0)), 0)
	var player_position := maxi(int(_dictionary_value(result, "player_position", 0)), 0)
	var classification := _dictionary_array(_dictionary_value(result, "classification", []), 24)
	var player_entry := _find_player_classification_entry(classification)
	var player_entry_count := _count_player_classification_entries(classification)
	if player_position <= 0:
		player_position = maxi(int(_dictionary_value(player_entry, "position", 0)), 0)
	var status := _safe_identifier(_dictionary_value(player_entry, "status", &"NO_PLAYER"), &"NO_PLAYER")
	var result_valid := bool(_dictionary_value(result, "valid", true)) and player_entry_count == 1
	if player_entry_count != 1:
		status = &"DSQ"
	var fingerprint := _race_result_fingerprint(result, event_id)
	var legacy_v1_fingerprint := _legacy_v1_race_result_fingerprint(result, event_id)
	var legacy_fingerprint := _legacy_race_result_identity(result, event_id)
	if (
		recent_result_ids.has(fingerprint)
		or recent_result_ids.has(legacy_v1_fingerprint)
		or recent_result_ids.has(legacy_fingerprint)
	):
		return {
			&"accepted": false, &"duplicate": true, &"durable": true,
			&"reason": &"DUPLICATE", &"result_id": fingerprint,
		}
	var active_academy_lesson := StringName(_active_race_run.get(&"academy_lesson_id", &""))
	var active_challenge_id := StringName(_active_race_run.get(&"challenge_id", &""))
	var active_competition_id := StringName(_active_race_run.get(&"competition_id", &""))
	var active_round_id := StringName(_active_race_run.get(&"round_id", &""))
	var active_weekend_phase := StringName(_active_race_run.get(&"weekend_phase", &""))
	var active_weekend_id := StringName(_active_race_run.get(&"weekend_id", &""))
	var active_weekend_managed := bool(_active_race_run.get(&"weekend_managed", false))
	var current_round_matches := true
	if not explicit_round.is_empty():
		var championship: Variant = get_championship_service()
		var next_round: Dictionary = championship.get_next_round() if championship != null else {}
		current_round_matches = (
			explicit_round == active_round_id
			and StringName(next_round.get(&"round_id", &"")) == explicit_round
			and StringName(next_round.get(&"event_id", &"")) == event_id
		)
	var payload_academy_lesson := _safe_identifier(
		_dictionary_value(result, "academy_lesson_id", &""), &""
	)
	if (
		str(_active_race_run.get(&"run_id", "")) != run_id
		or StringName(_active_race_run.get(&"event_id", &"")) != event_id
		or str(_active_race_run.get(&"signature", "")) != signature
		or (
			event_id == &"ACADEMY"
			and (
				active_academy_lesson.is_empty()
				or payload_academy_lesson != active_academy_lesson
			)
		)
		or (is_challenge_event and (
			active_challenge_id != challenge_id
			or active_competition_id != competition_id
		))
		or not current_round_matches
		or active_weekend_managed != weekend_managed
		or active_weekend_phase != weekend_phase
		or active_weekend_id != weekend_id
	):
		return {
			&"accepted": false, &"duplicate": false, &"durable": false,
			&"reason": &"STALE_OR_ABANDONED_RUN", &"invalid_identity": true,
			&"event_id": event_id, &"result_id": fingerprint,
		}

	var rollback_profile: Dictionary = {}
	var rollback_transactions: Array[Dictionary] = []
	var rollback_migration := false
	if finalize:
		rollback_profile = _profile_to_dictionary()
		rollback_transactions.assign(transaction_log.duplicate(true))
		rollback_migration = _profile_migration_pending
		_begin_settlement_signal_batch()
	recent_result_ids.append(fingerprint)
	while recent_result_ids.size() > MAX_RESULT_IDS:
		recent_result_ids.pop_front()
	var finished := result_valid and status in [&"FINISHED", &"CLASSIFIED"] and player_time_usec >= 0
	if not result_valid and status in [&"FINISHED", &"CLASSIFIED"]:
		status = &"DSQ"
	# Academy owns its completion contract through metric grading below. A rider
	# who finishes the route but earns zero stars has not completed onboarding.
	# Other structured rides remain a deliberate implicit skip, but only after a
	# valid classified finish; invalid, DNF, and DSQ results must retain guidance.
	if finished and event_id != &"ACADEMY":
		first_run_onboarding_complete = true
	total_runs += 1
	var lap_times := _int_array(_dictionary_value(result, "lap_times_usec", []), 128)
	# Academy is training, not a competitive classification. Keep its route audit
	# and total ride count, but never farm race wins, podiums, laps, or achievements.
	if event_id != &"ACADEMY":
		_increment_stat(&"starts", 1)
		_increment_stat(&"finishes", 1 if finished else 0)
		_increment_stat(&"wins", 1 if finished and player_position == 1 else 0)
		_increment_stat(&"podiums", 1 if finished and player_position >= 1 and player_position <= 3 else 0)
		_increment_stat(&"top_five", 1 if finished and player_position >= 1 and player_position <= 5 else 0)
		_increment_stat(&"dnfs", 1 if status == &"DNF" else 0)
		_increment_stat(&"dsqs", 1 if status == &"DSQ" else 0)
		# Invalid runs remain in the audit trail, but their caller-supplied performance
		# telemetry is not trusted. Otherwise a cut/DSQ payload could award holeshot,
		# lap, or passing achievements despite being ineligible for settlement.
		if result_valid:
			_increment_stat(&"holeshots", 1 if StringName(_dictionary_value(result, "holeshot_rider_id", &"")) == &"PLAYER" else 0)
			_increment_stat(&"fastest_laps", 1 if StringName(_dictionary_value(result, "fastest_rider_id", &"")) == &"PLAYER" else 0)
			_increment_stat(&"overtakes", maxi(int(_dictionary_value(result, "overtakes", 0)), 0))
			_increment_stat(&"near_misses", maxi(int(_dictionary_value(result, "near_misses", 0)), 0))
		_increment_stat(&"contacts", maxi(int(_dictionary_value(result, "contacts", 0)), 0))
		_increment_stat(&"crashes", maxi(int(_dictionary_value(result, "crashes", 0)), 0))
		_increment_stat(&"resets", maxi(int(_dictionary_value(result, "reset_count", 0)), 0))
		_increment_stat(&"off_course", maxi(int(_dictionary_value(result, "off_course_count", 0)), 0))
		_increment_stat(&"wrong_way", maxi(int(_dictionary_value(result, "wrong_way_count", 0)), 0))
		_increment_stat(&"cuts", maxi(int(_dictionary_value(result, "cut_count", 0)), 0))
		_increment_stat(&"penalty_usec", penalty_usec)
		if result_valid:
			_increment_stat(&"race_time_usec", maxi(player_time_usec, 0))
			var completed_laps := 0
			for lap_time: int in lap_times:
				if lap_time > 0:
					completed_laps += 1
			_increment_stat(&"laps_completed", completed_laps)
		if finished and player_position > 0:
			var previous_best_finish := int(race_statistics.get(&"best_finish", 0))
			race_statistics[&"best_finish"] = player_position if previous_best_finish <= 0 else mini(previous_best_finish, player_position)
	_record_event_result(
		event_id, challenge_id, result, player_entry,
		result_valid, finished, status, player_position, player_time_usec, lap_times
	)
	var medal := _safe_identifier(_dictionary_value(result, "medal", &"UNRIDDEN"), &"UNRIDDEN")
	if finished and event_id != &"ACADEMY":
		_record_best_medal(event_id, medal, challenge_id)
	var rewards_granted := {&"cash": 0, &"reputation": 0}
	# Academy route telemetry is recorded above, but lesson grading is the sole
	# reward authority. This prevents Main's generic settlement from stacking a
	# race payout with the lesson's first-completion reward.
	if apply_result_rewards and finished and event_id != &"ACADEMY":
		rewards_granted = _apply_structured_rewards(_dictionary_value(result, "rewards", {}) as Dictionary)
	var weekend_result_recorded := false
	if finished and weekend_managed and not weekend_phase.is_empty() and not classification.is_empty():
		weekend_result_recorded = _record_weekend_result(weekend_phase, classification)
	# Red Mesa's championship opener is awarded only through the persisted weekend
	# state machine. A standalone MESA_MX result may retain its normal event medal
	# and rewards, but cannot masquerade as the tour round.
	if event_id == &"MESA_MX" and (
			not weekend_managed
			or weekend_phase != &"MAIN"
			or weekend_id != &"RED_MESA_OPEN"
			or not weekend_result_recorded
		):
		explicit_round = &""
	if finished and not explicit_round.is_empty() and not classification.is_empty():
		record_championship_round(explicit_round, classification, false)
	var rival_target: int = int(ROOK_TARGETS_USEC.get(event_id, -1))
	if finished and rival_target > 0 and player_time_usec + penalty_usec <= rival_target and not rival_victories.has(event_id):
		rival_victories.append(event_id)
	if result_valid and event_id != &"ACADEMY":
		_evaluate_meta_achievements()
	var summary := {
		&"accepted": true,
		&"duplicate": false,
		&"durable": true,
		&"reason": &"SETTLED",
		&"result_id": fingerprint,
		&"event_id": event_id,
		&"challenge_id": challenge_id,
		&"competition_id": competition_id,
		&"position": player_position,
		&"status": status,
		&"valid": result_valid,
		&"rewards_granted": rewards_granted.duplicate(),
		&"stats": race_statistics.duplicate(true),
		&"event_record": get_event_record(event_id, challenge_id),
	}
	if finalize:
		if not _commit_profile_transaction(rollback_profile, rollback_transactions, rollback_migration):
			summary[&"accepted"] = false
			summary[&"durable"] = false
			summary[&"reason"] = &"SAVE_FAILED"
			summary[&"retryable"] = true
			summary[&"rewards_granted"] = {&"cash": 0, &"reputation": 0}
			summary[&"stats"] = race_statistics.duplicate(true)
			summary[&"event_record"] = get_event_record(event_id, challenge_id)
		else:
			if str(_active_race_run.get(&"run_id", "")) == run_id:
				_active_race_run.clear()
			race_result_recorded.emit(summary.duplicate(true))
	return summary


func grant_race_bonus(cash_bonus: int, reputation_bonus: int, reason: StringName = &"structured_race_bonus") -> Dictionary:
	var safe_cash := maxi(cash_bonus, 0)
	var safe_reputation := maxi(reputation_bonus, 0)
	if safe_cash == 0 and safe_reputation == 0:
		return {&"cash": 0, &"reputation": 0}
	var old_cash := cash
	cash = mini(cash + safe_cash, MAX_CASH)
	var granted_cash := cash - old_cash
	racer_reputation += safe_reputation
	_record_transaction(granted_cash, reason)
	_emit_and_save()
	_emit_or_defer_reward(granted_cash, safe_reputation)
	return {&"cash": granted_cash, &"reputation": safe_reputation}


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
	contract_completions = 0
	style_tokens = 0
	completed_contracts.clear()
	assist_mode = &"SPORT"
	unlocked_feats.clear()
	legacy_pine_unlock = false
	first_run_onboarding_complete = false
	transaction_log.clear()
	profile_id = _generate_profile_id()
	championship_snapshot = CHAMPIONSHIP_SERVICE_SCRIPT.create_default().to_dictionary()
	race_weekend_snapshot.clear()
	owned_bike_builds.clear()
	var starter_build: Variant = BIKE_BUILD_SCRIPT.new()
	owned_bike_builds[&"TYKE_125"] = starter_build.to_dictionary()
	active_bike_id = &"TYKE_125"
	selected_bike_class = &"LITE_125"
	owned_part_ids.clear()
	saved_bike_builds.clear()
	academy_progress.clear()
	rider_cosmetics = _default_cosmetics()
	race_statistics = _default_race_statistics()
	event_records.clear()
	challenge_records.clear()
	achievements.clear()
	leaderboard_summary.clear()
	settings_reference = DEFAULT_SETTINGS_REFERENCE
	recent_result_ids.clear()
	recent_activity_result_ids.clear()
	academy_result_bindings.clear()
	_active_activity_runs.clear()
	_active_race_run.clear()
	_emit_and_save()


func _on_activity_started(activity: StringName) -> void:
	_active_activity = activity


func begin_activity_run(activity: StringName) -> Dictionary:
	var normalized_activity := StringName(String(activity).strip_edges().to_upper())
	if normalized_activity not in [&"FREESTYLE", &"DISCOVERY"]:
		return {&"accepted": false, &"reason": &"UNKNOWN_ACTIVITY", &"activity_id": normalized_activity}
	# A newly issued open-activity token abandons any unfinished structured race.
	# Main resolves completed pending race receipts before it can reach this call.
	_active_race_run.clear()
	var run_id: String = ACTIVITY_RUN_IDENTITY_SCRIPT.create(normalized_activity, profile_id)
	_active_activity = normalized_activity
	_active_activity_runs[normalized_activity] = run_id
	return {
		&"accepted": true,
		&"activity_id": normalized_activity,
		&"run_id": run_id,
		&"schema_version": 1,
	}


func begin_race_run(
	event_id: StringName,
	signature: String = "",
	settlement_context: Dictionary = {}
) -> Dictionary:
	var normalized_event := StringName(String(event_id).strip_edges().to_upper())
	var normalized_signature := signature.strip_edges()
	var academy_lesson_id := _safe_identifier(
		_dictionary_value(settlement_context, "academy_lesson_id", &""), &""
	)
	var challenge_id := _safe_identifier(
		_dictionary_value(settlement_context, "challenge_id", &""), &""
	)
	var competition_id := _safe_identifier(
		_dictionary_value(settlement_context, "competition_id", &""), &""
	)
	var weekend_id := _safe_identifier(
		_dictionary_value(settlement_context, "weekend_id", &""), &""
	)
	var weekend_phase := _safe_identifier(
		_dictionary_value(settlement_context, "weekend_phase", &""), &""
	)
	var weekend_managed := bool(_dictionary_value(settlement_context, "weekend_managed", false))
	if not weekend_managed:
		weekend_id = &""
		weekend_phase = &""
	var is_challenge_event := normalized_event in [&"DAILY_CHALLENGE", &"WEEKLY_CHALLENGE"]
	var expected_competition_id := ChallengeSchedule.competition_id({
		"challenge_id": String(challenge_id),
		"run_signature": normalized_signature,
	})
	var expected_round_id: StringName = &""
	var championship: Variant = get_championship_service()
	if championship != null:
		var next_round: Dictionary = championship.get_next_round()
		if StringName(next_round.get(&"event_id", &"")) == normalized_event:
			expected_round_id = StringName(next_round.get(&"round_id", &""))
	if (
		normalized_event.is_empty()
		or not _is_safe_identifier(normalized_event)
		or normalized_event not in RaceEventCatalog.RACE_EVENTS
		or normalized_signature.length() > 256
		or (
			normalized_event == &"ACADEMY"
			and not ACADEMY_CATALOG_SCRIPT.create_default().has_lesson(academy_lesson_id)
		)
		or (is_challenge_event and (
			challenge_id.is_empty()
			or not String(challenge_id).begins_with(
				"DAILY_" if normalized_event == &"DAILY_CHALLENGE" else "WEEKLY_"
			)
			or not CompetitiveRunSignature.validate(normalized_signature)
			or competition_id != expected_competition_id
		))
		or (weekend_managed and (
			not RaceEventCatalog.is_weekend_event(normalized_event)
			or weekend_id.is_empty()
			or weekend_phase != RaceEventCatalog.get_weekend_phase(normalized_event)
		))
	):
		return {
			&"accepted": false, &"reason": &"INVALID_RACE_CONTEXT",
			&"event_id": normalized_event,
		}
	# Starting a structured race abandons unfinished open-activity authority. Main
	# retries any durable pending activity receipt before it can reach this call.
	_active_activity_runs.clear()
	var run_id: String = ACTIVITY_RUN_IDENTITY_SCRIPT.create(normalized_event, profile_id)
	_active_activity = normalized_event
	_active_race_run = {
		&"event_id": normalized_event,
		&"run_id": run_id,
		&"signature": normalized_signature,
		&"academy_lesson_id": academy_lesson_id,
		&"challenge_id": challenge_id,
		&"competition_id": competition_id,
		&"round_id": expected_round_id,
		&"weekend_id": weekend_id,
		&"weekend_phase": weekend_phase,
		&"weekend_managed": weekend_managed,
	}
	return {
		&"accepted": true,
		&"event_id": normalized_event,
		&"run_id": run_id,
		&"signature": normalized_signature,
		&"academy_lesson_id": academy_lesson_id,
		&"challenge_id": challenge_id,
		&"competition_id": competition_id,
		&"round_id": expected_round_id,
		&"weekend_id": weekend_id,
		&"weekend_phase": weekend_phase,
		&"weekend_managed": weekend_managed,
		&"schema_version": 1,
	}


func abandon_activity_run(activity: StringName, run_id: String) -> bool:
	var normalized_activity := StringName(String(activity).strip_edges().to_upper())
	var normalized_run_id := run_id.strip_edges()
	if normalized_activity not in [&"FREESTYLE", &"DISCOVERY"] or normalized_run_id.is_empty():
		return false
	if str(_active_activity_runs.get(normalized_activity, "")) != normalized_run_id:
		return false
	_active_activity_runs.erase(normalized_activity)
	return true


func record_activity_result(submission: Dictionary) -> Dictionary:
	var activity := _safe_identifier(_dictionary_value(submission, "activity_id", &""), &"")
	var run_id := str(_dictionary_value(submission, "run_id", "")).strip_edges()
	var result_value := int(_dictionary_value(submission, "result_value", -1))
	if activity not in [&"FREESTYLE", &"DISCOVERY"]:
		return _activity_rejection(activity, run_id, &"UNKNOWN_ACTIVITY")
	if run_id.is_empty() or run_id.length() > 160:
		return _activity_rejection(activity, run_id, &"INVALID_RUN_ID")
	if (activity == &"FREESTYLE" and (result_value < 0 or result_value > 100_000_000)) or (
		activity == &"DISCOVERY" and (result_value <= 0 or result_value > 86_400_000_000)
	):
		return _activity_rejection(activity, run_id, &"INVALID_RESULT")
	var fingerprint := _activity_result_fingerprint(activity, run_id)
	if recent_activity_result_ids.has(fingerprint):
		return {
			&"accepted": false, &"duplicate": true, &"durable": true,
			&"reason": &"DUPLICATE", &"activity_id": activity, &"run_id": run_id,
			&"result_id": fingerprint, &"rewards_granted": {&"cash": 0, &"reputation": 0},
		}
	if str(_active_activity_runs.get(activity, "")) != run_id:
		return _activity_rejection(activity, run_id, &"STALE_OR_ABANDONED_RUN")

	var medal := _activity_medal_for_result(activity, result_value)
	var first_clear := not has_completed_event(activity)
	var is_new_best := (
		result_value > best_freestyle_score
		if activity == &"FREESTYLE"
		else best_discovery_usec < 0 or result_value < best_discovery_usec
	)
	var cash_reward := 175
	var reputation_reward := 8
	match medal:
		&"GOLD":
			cash_reward = 750 if activity == &"DISCOVERY" else 650
			reputation_reward = 30
		&"SILVER":
			cash_reward = 500
			reputation_reward = 22
		&"BRONZE":
			cash_reward = 300
			reputation_reward = 16
	if is_new_best:
		cash_reward += 200
		reputation_reward += 5
	var repeat_limited := not first_clear and not is_new_best
	if repeat_limited:
		reputation_reward = maxi(roundi(float(reputation_reward) * 0.35), 1)

	var rollback_profile := _profile_to_dictionary()
	var rollback_transactions := transaction_log.duplicate(true)
	var rollback_migration := _profile_migration_pending
	_begin_settlement_signal_batch()
	_append_activity_result_id(fingerprint)
	first_run_onboarding_complete = true
	if activity == &"FREESTYLE":
		if is_new_best:
			best_freestyle_score = result_value
		freestyler_reputation += reputation_reward
	else:
		if is_new_best:
			best_discovery_usec = result_value
		explorer_reputation += reputation_reward
	var old_cash := cash
	cash = mini(cash + cash_reward, MAX_CASH)
	var credited_cash := cash - old_cash
	total_runs += 1
	_record_best_medal(activity, medal)
	_record_transaction(credited_cash, &"activity_reward")
	_emit_or_defer_reward(credited_cash, reputation_reward)
	if not _commit_profile_transaction(rollback_profile, rollback_transactions, rollback_migration):
		return _activity_rejection(activity, run_id, &"SAVE_FAILED", true, result_value)
	if str(_active_activity_runs.get(activity, "")) == run_id:
		_active_activity_runs.erase(activity)
	return {
		&"accepted": true,
		&"duplicate": false,
		&"durable": true,
		&"reason": &"SETTLED",
		&"schema_version": 1,
		&"activity_id": activity,
		&"run_id": run_id,
		&"result_id": fingerprint,
		&"result_value": result_value,
		&"medal": medal,
		&"is_new_best": is_new_best,
		&"first_clear": first_clear,
		&"repeat_limited": repeat_limited,
		&"rewards_granted": {
			&"cash": credited_cash,
			&"reputation": reputation_reward,
			&"domain": &"FREESTYLER" if activity == &"FREESTYLE" else &"EXPLORER",
		},
		&"cash_after": cash,
		&"total_reputation_after": get_total_reputation(),
	}


func _activity_rejection(
	activity: StringName,
	run_id: String,
	reason: StringName,
	retryable: bool = false,
	result_value: int = -1
) -> Dictionary:
	return {
		&"accepted": false,
		&"duplicate": false,
		&"durable": false,
		&"retryable": retryable,
		&"reason": reason,
		&"schema_version": 1,
		&"activity_id": activity,
		&"run_id": run_id,
		&"result_value": result_value,
		&"medal": &"UNRIDDEN",
		&"is_new_best": false,
		&"first_clear": false,
		&"repeat_limited": false,
		&"rewards_granted": {&"cash": 0, &"reputation": 0},
	}


func _activity_result_fingerprint(activity: StringName, run_id: String) -> String:
	return ("ACTIVITY_V1|%s|%s" % [String(activity), run_id]).sha256_text()


func _race_result_fingerprint(result: Dictionary, event_id: StringName) -> String:
	var run_id := str(_dictionary_value(result, "run_id", "")).strip_edges().substr(0, 160)
	if not run_id.is_empty():
		return ("RACE_V2|%s" % run_id).sha256_text()
	return _legacy_race_result_identity(result, event_id).sha256_text()


func _legacy_v1_race_result_fingerprint(result: Dictionary, event_id: StringName) -> String:
	var run_id := str(_dictionary_value(result, "run_id", "")).strip_edges().substr(0, 160)
	var signature := str(_dictionary_value(result, "signature", "")).strip_edges().substr(0, 256)
	if not run_id.is_empty():
		return ("%s|%s" % [run_id, signature]).sha256_text()
	return _legacy_race_result_identity(result, event_id).sha256_text()


func _legacy_race_result_identity(result: Dictionary, event_id: StringName) -> String:
	var run_id := str(_dictionary_value(result, "run_id", "")).strip_edges().substr(0, 160)
	var signature := str(_dictionary_value(result, "signature", "")).strip_edges().substr(0, 256)
	if not run_id.is_empty():
		return run_id
	var player_position := maxi(int(_dictionary_value(result, "player_position", 0)), 0)
	if player_position <= 0:
		var classification := _dictionary_array(_dictionary_value(result, "classification", []), 24)
		player_position = maxi(int(_dictionary_value(
			_find_player_classification_entry(classification), "position", 0
		)), 0)
	return "%s|%s|%d|%d|%d" % [
		String(event_id), signature,
		int(_dictionary_value(result, "player_time_usec", -1)),
		player_position,
		maxi(int(_dictionary_value(result, "player_penalty_usec", 0)), 0),
	]


func _academy_race_is_eligible(result: Dictionary) -> bool:
	if _safe_identifier(_dictionary_value(result, "event_id", &""), &"") != &"ACADEMY":
		return false
	if not bool(_dictionary_value(result, "valid", true)):
		return false
	if int(_dictionary_value(result, "player_time_usec", -1)) < 0:
		return false
	var classification := _dictionary_array(_dictionary_value(result, "classification", []), 24)
	if _count_player_classification_entries(classification) != 1:
		return false
	var player_entry := _find_player_classification_entry(classification)
	if not player_entry.has(&"status") and not player_entry.has("status"):
		return false
	var status := _safe_identifier(_dictionary_value(player_entry, "status", &""), &"")
	return status in [&"FINISHED", &"CLASSIFIED"]


func _append_activity_result_id(fingerprint: String) -> void:
	if recent_activity_result_ids.has(fingerprint):
		recent_activity_result_ids.erase(fingerprint)
	recent_activity_result_ids.append(fingerprint)
	while recent_activity_result_ids.size() > MAX_ACTIVITY_RESULT_IDS:
		recent_activity_result_ids.pop_front()


func _activity_medal_for_result(activity: StringName, result_value: int) -> StringName:
	if activity == &"FREESTYLE":
		if result_value >= 12_000:
			return &"GOLD"
		if result_value >= 7_000:
			return &"SILVER"
		if result_value >= 3_500:
			return &"BRONZE"
		return &"FINISHER"
	if result_value <= 50_000_000:
		return &"GOLD"
	if result_value <= 80_000_000:
		return &"SILVER"
	if result_value <= 120_000_000:
		return &"BRONZE"
	return &"FINISHER"


func _record_transaction(delta: int, reason: StringName) -> void:
	transaction_log.append({
		&"timestamp_usec": Time.get_ticks_usec(),
		&"delta": delta,
		&"reason": reason,
		&"balance": cash,
	})
	while transaction_log.size() > MAX_LOG_ENTRIES:
		transaction_log.pop_front()


func _record_best_medal(activity: StringName, medal: StringName, challenge_id: StringName = &"") -> void:
	var rank := _medal_rank(medal)
	if not challenge_id.is_empty():
		var record_value: Variant = challenge_records.get(challenge_id, {})
		if not record_value is Dictionary:
			return
		var record := (record_value as Dictionary).duplicate(true)
		if StringName(record.get(&"event_id", &"")) != activity:
			return
		if rank > clampi(int(record.get(&"best_medal_rank", 0)), 0, 4):
			record[&"best_medal_rank"] = rank
			record[&"updated_unix"] = int(Time.get_unix_time_from_system())
			challenge_records[challenge_id] = record
		return
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


func _emit_profile_state() -> void:
	profile_changed.emit(cash, racer_reputation, current_setup)
	meta_progress_changed.emit(get_meta_snapshot())


func _begin_settlement_signal_batch() -> void:
	_settlement_signals_deferred = true
	_deferred_reward_grants.clear()
	_deferred_achievements.clear()


func _emit_or_defer_reward(cash_reward: int, reputation_reward: int) -> void:
	if _settlement_signals_deferred:
		_deferred_reward_grants.append({
			&"cash": cash_reward,
			&"reputation": reputation_reward,
		})
		return
	reward_granted.emit(cash_reward, reputation_reward)


func _emit_or_defer_achievement(achievement_id: StringName) -> void:
	if _settlement_signals_deferred:
		if not _deferred_achievements.has(achievement_id):
			_deferred_achievements.append(achievement_id)
		return
	achievement_unlocked.emit(achievement_id)


func _flush_settlement_signal_batch(committed: bool) -> void:
	var rewards := _deferred_reward_grants.duplicate(true)
	var unlocked := _deferred_achievements.duplicate()
	_deferred_reward_grants.clear()
	_deferred_achievements.clear()
	_settlement_signals_deferred = false
	if not committed:
		return
	for reward: Dictionary in rewards:
		reward_granted.emit(int(reward.get(&"cash", 0)), int(reward.get(&"reputation", 0)))
	for achievement_id: StringName in unlocked:
		achievement_unlocked.emit(achievement_id)


func _commit_profile_transaction(
	rollback_profile: Dictionary,
	rollback_transactions: Array[Dictionary],
	rollback_migration_pending: bool
) -> bool:
	if _save_profile():
		_profile_migration_pending = false
		_emit_profile_state()
		_flush_settlement_signal_batch(true)
		return true
	_rollback_profile_transaction(rollback_profile, rollback_transactions, rollback_migration_pending)
	return false


func _rollback_profile_transaction(
	rollback_profile: Dictionary,
	rollback_transactions: Array[Dictionary],
	rollback_migration_pending: bool
) -> void:
	var active_runs := _active_activity_runs.duplicate()
	var active_race_run := _active_race_run.duplicate(true)
	_apply_profile_dictionary(rollback_profile)
	transaction_log.assign(rollback_transactions)
	_profile_migration_pending = rollback_migration_pending
	_active_activity_runs.assign(active_runs)
	_active_race_run = active_race_run
	_flush_settlement_signal_batch(false)


func _emit_and_save() -> bool:
	if not _save_profile():
		return false
	_emit_profile_state()
	return true


func _emit_meta_and_save() -> bool:
	return _emit_and_save()


func _save_profile() -> bool:
	if not persistence_enabled:
		return true
	var profile_data := _profile_to_dictionary()
	if OS.has_feature("web"):
		if not WebPlatform.save_json(WEB_SAVE_KEY, profile_data):
			push_warning("Unable to save rider profile to browser storage.")
			return false
		return true
	var save_result := ATOMIC_CONFIG_STORE.save_section(SAVE_PATH, &"profile", profile_data)
	if not bool(save_result.get("ok", false)):
		push_warning("Unable to save rider profile: %s" % str(save_result.get("error", "unknown_error")))
		return false
	return true


func _load_profile() -> void:
	if OS.has_feature("web"):
		var web_data: Variant = WebPlatform.load_json(WEB_SAVE_KEY)
		if web_data is Dictionary:
			_apply_profile_dictionary(web_data as Dictionary)
		return
	var load_result := ATOMIC_CONFIG_STORE.load_section(SAVE_PATH, &"profile", persistence_enabled)
	if not bool(load_result.get("ok", false)):
		return
	var profile_data := load_result.get("data", {}) as Dictionary
	if str(load_result.get("source", "")) == "backup":
		push_warning("Recovered rider profile from backup after the primary save became unreadable.")
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
		"transaction_log": _json_safe_copy(transaction_log),
		"current_setup": String(current_setup),
		"best_freestyle_score": best_freestyle_score,
		"best_discovery_usec": best_discovery_usec,
		"bike_condition": bike_condition,
		"unlocked_setups": setup_names,
		"best_medal_ranks": _serialize_medal_ranks(),
		"rival_victories": _serialize_string_names(rival_victories),
		"course_layout_version": COURSE_LAYOUT_VERSION,
		"legacy_pine_unlock": legacy_pine_unlock,
		"contract_completions": contract_completions,
		"style_tokens": style_tokens,
		"completed_contracts": completed_contracts.duplicate(),
		"assist_mode": String(assist_mode),
		"unlocked_feats": unlocked_feats.duplicate(),
		"profile_schema_version": PROFILE_SCHEMA_VERSION,
		"profile_id": profile_id,
		"championship": _json_safe_copy(championship_snapshot),
		"race_weekend": _json_safe_copy(race_weekend_snapshot),
		"owned_bike_builds": _json_safe_copy(owned_bike_builds),
		"active_bike_id": String(active_bike_id),
		"selected_bike_class": String(selected_bike_class),
		"owned_part_ids": _serialize_string_names(owned_part_ids),
		"saved_bike_builds": _json_safe_copy(saved_bike_builds),
		"academy_progress": _serialize_int_dictionary(academy_progress),
		"rider_cosmetics": _json_safe_copy(rider_cosmetics),
		"race_statistics": _json_safe_copy(race_statistics),
		"event_records": _json_safe_copy(event_records),
		"challenge_records": _json_safe_copy(challenge_records),
		"achievements": _serialize_string_names(achievements),
		"leaderboard_summary": _json_safe_copy(leaderboard_summary),
		"settings_reference": settings_reference,
		"recent_result_ids": recent_result_ids.duplicate(),
		"recent_activity_result_ids": recent_activity_result_ids.duplicate(),
		"academy_result_bindings": _serialize_academy_result_bindings(),
		"first_run_onboarding_complete": first_run_onboarding_complete,
	}


func _apply_profile_dictionary(profile_data: Dictionary) -> void:
	var saved_profile_schema := maxi(int(_dictionary_value(profile_data, "profile_schema_version", 1)), 1)
	cash = clampi(int(profile_data.get("cash", 0)), 0, MAX_CASH)
	racer_reputation = maxi(int(profile_data.get("racer_reputation", 0)), 0)
	freestyler_reputation = maxi(int(profile_data.get("freestyler_reputation", 0)), 0)
	explorer_reputation = maxi(int(profile_data.get("explorer_reputation", 0)), 0)
	total_runs = maxi(int(profile_data.get("total_runs", 0)), 0)
	transaction_log = _sanitize_transaction_log(_dictionary_value(profile_data, "transaction_log", []))
	first_run_onboarding_complete = bool(_dictionary_value(
		profile_data,
		"first_run_onboarding_complete",
		total_runs > 0
	))
	current_setup = StringName(str(profile_data.get("current_setup", "BALANCED")))
	best_freestyle_score = maxi(int(profile_data.get("best_freestyle_score", 0)), 0)
	best_discovery_usec = int(profile_data.get("best_discovery_usec", -1))
	if best_discovery_usec <= 0:
		best_discovery_usec = -1
	bike_condition = clampi(int(profile_data.get("bike_condition", 100)), 0, 100)
	contract_completions = maxi(int(profile_data.get("contract_completions", 0)), 0)
	style_tokens = maxi(int(profile_data.get("style_tokens", 0)), 0)
	completed_contracts.clear()
	assist_mode = StringName(str(profile_data.get("assist_mode", "SPORT")).to_upper())
	if assist_mode not in [&"ASSISTED", &"SPORT", &"PRO"]:
		assist_mode = &"SPORT"
	unlocked_feats.clear()
	var loaded_feats: Variant = profile_data.get("unlocked_feats", [])
	if loaded_feats is Array or loaded_feats is PackedStringArray:
		for feat_id: Variant in loaded_feats:
			unlocked_feats.append(str(feat_id))
	var loaded_contracts: Variant = profile_data.get("completed_contracts", [])
	if loaded_contracts is Array or loaded_contracts is PackedStringArray:
		for contract_id: Variant in loaded_contracts:
			completed_contracts.append(str(contract_id))
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
			if (
				_is_safe_identifier(activity)
				and activity not in [&"DAILY_CHALLENGE", &"WEEKLY_CHALLENGE"]
				and best_medal_ranks.size() < MAX_EVENT_RECORDS
			):
				best_medal_ranks[activity] = clampi(int(loaded_medals[activity_key]), 0, 4)
	rival_victories.clear()
	var loaded_victories: Variant = profile_data.get("rival_victories", [])
	if loaded_victories is Array or loaded_victories is PackedStringArray:
		for activity_name: Variant in loaded_victories:
			var activity := StringName(str(activity_name).to_upper())
			if _is_safe_identifier(activity) and not rival_victories.has(activity) and rival_victories.size() < MAX_EVENT_RECORDS:
				rival_victories.append(activity)

	profile_id = _sanitize_profile_id(str(_dictionary_value(profile_data, "profile_id", "")))
	championship_snapshot = _sanitize_championship_snapshot(
		_dictionary_value(profile_data, "championship", {}) as Dictionary
		if _dictionary_value(profile_data, "championship", {}) is Dictionary else {}
	)
	var weekend_value: Variant = _dictionary_value(profile_data, "race_weekend", {})
	race_weekend_snapshot = _sanitize_weekend_snapshot(weekend_value as Dictionary) if weekend_value is Dictionary else {}
	owned_bike_builds = _sanitize_owned_bike_builds(_dictionary_value(profile_data, "owned_bike_builds", {}))
	active_bike_id = _safe_identifier(_dictionary_value(profile_data, "active_bike_id", &"TYKE_125"), &"TYKE_125")
	selected_bike_class = _safe_identifier(_dictionary_value(profile_data, "selected_bike_class", &"LITE_125"), &"LITE_125")
	owned_part_ids = _sanitize_string_name_array(_dictionary_value(profile_data, "owned_part_ids", []), 64)
	saved_bike_builds = _sanitize_saved_bike_builds(
		_dictionary_value(profile_data, "saved_bike_builds", {})
	)
	academy_progress = _sanitize_int_dictionary(_dictionary_value(profile_data, "academy_progress", {}), 64, 0, 3)
	var cosmetics_value: Variant = _dictionary_value(profile_data, "rider_cosmetics", {})
	rider_cosmetics = _sanitize_cosmetics(cosmetics_value as Dictionary if cosmetics_value is Dictionary else {})
	var statistics_value: Variant = _dictionary_value(profile_data, "race_statistics", {})
	race_statistics = _sanitize_statistics(statistics_value as Dictionary if statistics_value is Dictionary else {})
	event_records = _sanitize_event_records(_dictionary_value(profile_data, "event_records", {}))
	challenge_records = _sanitize_challenge_records(_dictionary_value(profile_data, "challenge_records", {}))
	achievements = _sanitize_string_name_array(_dictionary_value(profile_data, "achievements", []), 128)
	if saved_profile_schema < 5:
		_migrate_academy_out_of_competitive_stats()
	leaderboard_summary = _sanitize_leaderboard_summary(_dictionary_value(profile_data, "leaderboard_summary", {}))
	settings_reference = _sanitize_settings_reference(str(_dictionary_value(profile_data, "settings_reference", DEFAULT_SETTINGS_REFERENCE)))
	recent_result_ids = _sanitize_string_array(_dictionary_value(profile_data, "recent_result_ids", []), MAX_RESULT_IDS, 160)
	recent_activity_result_ids = _sanitize_fingerprint_ledger(
		_dictionary_value(profile_data, "recent_activity_result_ids", []),
		MAX_ACTIVITY_RESULT_IDS
	)
	academy_result_bindings = _sanitize_academy_result_bindings(
		_dictionary_value(profile_data, "academy_result_bindings", {})
	)
	_active_activity_runs.clear()
	_active_race_run.clear()
	if saved_profile_schema < PROFILE_SCHEMA_VERSION:
		_profile_migration_pending = true
	legacy_pine_unlock = bool(profile_data.get("legacy_pine_unlock", false))
	var saved_course_layout_version := int(profile_data.get("course_layout_version", 0))
	if saved_course_layout_version < COURSE_LAYOUT_VERSION:
		legacy_pine_unlock = (
			legacy_pine_unlock
			or _meets_pine_unlock_requirements()
			or total_runs >= 2
			or has_completed_event(&"PINE_ENDURO")
			or has_beaten_rival(&"PINE_ENDURO")
		)
		for race_activity: StringName in RACE_EVENTS:
			best_medal_ranks.erase(race_activity)
			rival_victories.erase(race_activity)
		_profile_migration_pending = true


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


func _ensure_full_race_defaults() -> void:
	var changed := false
	if profile_id.is_empty():
		profile_id = _generate_profile_id()
		changed = true
	if championship_snapshot.is_empty():
		championship_snapshot = CHAMPIONSHIP_SERVICE_SCRIPT.create_default().to_dictionary()
		changed = true
	if owned_bike_builds.is_empty():
		var starter_build: Variant = BIKE_BUILD_SCRIPT.new()
		starter_build.bike_id = &"TYKE_125"
		starter_build.condition = float(bike_condition) / 100.0
		owned_bike_builds[&"TYKE_125"] = starter_build.to_dictionary()
		changed = true
	if get_bike_build_snapshot(active_bike_id).is_empty():
		var ordered_ids: Array[StringName] = []
		for raw_id: Variant in owned_bike_builds:
			ordered_ids.append(StringName(raw_id))
		ordered_ids.sort_custom(func(first: StringName, second: StringName) -> bool: return String(first) < String(second))
		active_bike_id = ordered_ids[0] if not ordered_ids.is_empty() else &"TYKE_125"
		changed = true
	var default_cosmetics := _default_cosmetics()
	for cosmetic_key: Variant in default_cosmetics:
		if not rider_cosmetics.has(cosmetic_key):
			rider_cosmetics[cosmetic_key] = default_cosmetics[cosmetic_key]
			changed = true
	var default_stats := _default_race_statistics()
	for stat_key: Variant in default_stats:
		if not race_statistics.has(stat_key):
			race_statistics[stat_key] = default_stats[stat_key]
			changed = true
	if not settings_reference.begins_with("user://"):
		settings_reference = DEFAULT_SETTINGS_REFERENCE
		changed = true
	if changed:
		_profile_migration_pending = true


func _default_cosmetics() -> Dictionary:
	return {
		&"helmet": "CLASSIC_WHITE",
		&"jersey": "MESA_RED",
		&"pants": "CHARCOAL",
		&"boots": "BLACK",
		&"gloves": "BLACK",
		&"bike_livery": "FACTORY",
		&"number_plate": "WHITE",
		&"accent_color": "E25532",
		&"rider_number": 17,
	}


func _default_race_statistics() -> Dictionary:
	return {
		&"starts": 0,
		&"finishes": 0,
		&"wins": 0,
		&"podiums": 0,
		&"top_five": 0,
		&"dnfs": 0,
		&"dsqs": 0,
		&"best_finish": 0,
		&"laps_completed": 0,
		&"holeshots": 0,
		&"fastest_laps": 0,
		&"overtakes": 0,
		&"contacts": 0,
		&"crashes": 0,
		&"near_misses": 0,
		&"resets": 0,
		&"off_course": 0,
		&"wrong_way": 0,
		&"cuts": 0,
		&"penalty_usec": 0,
		&"race_time_usec": 0,
		&"distance_meters": 0,
		&"air_time_usec": 0,
		&"jumps": 0,
	}


func _sanitize_championship_snapshot(value: Dictionary) -> Dictionary:
	if value.is_empty():
		return {}
	var service: Variant = CHAMPIONSHIP_SERVICE_SCRIPT.from_dictionary(value)
	return service.to_dictionary()


func _sanitize_weekend_snapshot(value: Dictionary) -> Dictionary:
	if value.is_empty():
		return {}
	var director: Variant = WEEKEND_DIRECTOR_SCRIPT.from_dictionary(value)
	return director.to_dictionary()


func _sanitize_owned_bike_builds(value: Variant) -> Dictionary:
	var output: Dictionary = {}
	if not value is Dictionary:
		return output
	var catalog: Variant = BIKE_CATALOG_SCRIPT.create_default()
	for raw_key: Variant in (value as Dictionary):
		if output.size() >= 12:
			break
		var raw_build: Variant = (value as Dictionary).get(raw_key, {})
		if not raw_build is Dictionary:
			continue
		var build: Variant = BIKE_BUILD_SCRIPT.from_dictionary(raw_build)
		var bike_id := _safe_identifier(build.bike_id, &"")
		if bike_id.is_empty() or not catalog.has_bike(bike_id):
			continue
		build.bike_id = bike_id
		var installed: Dictionary = build.installed_parts.duplicate(true)
		for raw_slot: Variant in installed:
			var part_id := StringName(installed.get(raw_slot, &""))
			if not catalog.is_part_compatible(part_id, bike_id):
				build.installed_parts.erase(raw_slot)
		output[bike_id] = build.to_dictionary()
	return output


func _sanitize_saved_bike_builds(value: Variant) -> Dictionary:
	var output: Dictionary = {}
	if not value is Dictionary:
		return output
	for slot_id: StringName in SAVED_BUILD_SLOT_IDS:
		if output.size() >= MAX_SAVED_BUILD_SLOTS:
			break
		var raw: Variant = (value as Dictionary).get(
			slot_id,
			(value as Dictionary).get(String(slot_id), {})
		)
		var sanitized := _sanitize_saved_build_entry(slot_id, raw)
		if not sanitized.is_empty():
			output[slot_id] = sanitized
	return output


func _sanitize_saved_build_entry(slot_id: StringName, value: Variant) -> Dictionary:
	if slot_id not in SAVED_BUILD_SLOT_IDS or not value is Dictionary:
		return {}
	var data := value as Dictionary
	var bike_id := _safe_identifier(_dictionary_value(data, "bike_id", &""), &"")
	var catalog: Variant = BIKE_CATALOG_SCRIPT.create_default()
	if bike_id.is_empty() or not catalog.has_bike(bike_id) or get_bike_build_snapshot(bike_id).is_empty():
		return {}
	var setup_id := _safe_identifier(_dictionary_value(data, "setup_id", &"BALANCED"), &"BALANCED")
	if setup_id not in unlocked_setups:
		return {}
	var installed_parts: Dictionary = {}
	var raw_parts: Variant = _dictionary_value(data, "installed_parts", {})
	if raw_parts is Dictionary:
		for raw_slot: Variant in raw_parts:
			if installed_parts.size() >= 5:
				break
			var part_id := _safe_identifier((raw_parts as Dictionary).get(raw_slot, &""), &"")
			var slot := _safe_identifier(raw_slot, &"")
			if (
				not slot.is_empty()
				and not part_id.is_empty()
				and part_id in owned_part_ids
				and catalog.is_part_compatible(part_id, bike_id)
				and StringName(catalog.get_part(part_id).get(&"slot", &"")) == slot
			):
				installed_parts[slot] = part_id
	var raw_tune: Variant = _dictionary_value(data, "tune", {})
	var tune_data: Dictionary = raw_tune as Dictionary if raw_tune is Dictionary else {}
	var selected_class := _safe_identifier(
		_dictionary_value(data, "selected_class", &"LITE_125"), &"LITE_125"
	)
	var livery_id := _safe_identifier(
		_dictionary_value(data, "livery_id", &"FACTORY"), &"FACTORY"
	)
	return {
		&"slot_id": slot_id,
		&"display_name": _sanitize_saved_build_name(str(_dictionary_value(
			data, "display_name", _default_saved_build_name(bike_id, setup_id)
		))),
		&"bike_id": bike_id,
		&"setup_id": setup_id,
		&"selected_class": selected_class,
		&"installed_parts": installed_parts,
		&"tune": BIKE_TUNE_SCRIPT.from_dictionary(tune_data).to_dictionary(),
		&"livery_id": livery_id,
		&"saved_unix": maxi(int(_dictionary_value(data, "saved_unix", 0)), 0),
	}


func _sanitize_saved_build_name(value: String) -> String:
	var output := value.replace("\r", " ").replace("\n", " ").replace("\t", " ").strip_edges()
	while output.contains("  "):
		output = output.replace("  ", " ")
	return output.substr(0, 40).to_upper()


func _default_saved_build_name(bike_id: StringName, setup_id: StringName) -> String:
	var definition: Dictionary = BIKE_CATALOG_SCRIPT.create_default().get_bike(bike_id)
	var bike_name := str(definition.get(&"display_name", String(bike_id))).replace("_", " ")
	return _sanitize_saved_build_name("%s %s" % [bike_name, String(setup_id).replace("_", " ")])


func _sanitize_cosmetics(value: Dictionary) -> Dictionary:
	var output := _default_cosmetics()
	for key: StringName in [&"helmet", &"jersey", &"pants", &"boots", &"gloves", &"bike_livery", &"number_plate", &"accent_color"]:
		var loaded: Variant = _dictionary_value(value, String(key), null)
		if loaded != null:
			var text := str(loaded).strip_edges().substr(0, 48)
			if not text.is_empty():
				output[key] = text
	output[&"rider_number"] = clampi(int(_dictionary_value(value, "rider_number", 17)), 1, 999)
	return output


func _sanitize_statistics(value: Dictionary) -> Dictionary:
	var output := _default_race_statistics()
	for raw_key: Variant in output:
		var key := StringName(raw_key)
		output[key] = maxi(int(_dictionary_value(value, String(key), output[key])), 0)
	output[&"best_finish"] = clampi(int(_dictionary_value(value, "best_finish", 0)), 0, 99)
	return output


func _migrate_academy_out_of_competitive_stats() -> void:
	var academy_value: Variant = event_records.get(&"ACADEMY", {})
	if not academy_value is Dictionary:
		return
	var academy_record := academy_value as Dictionary
	var starts := maxi(int(academy_record.get(&"starts", 0)), 0)
	var finishes := maxi(int(academy_record.get(&"finishes", 0)), 0)
	var deductions := {
		&"starts": starts,
		&"finishes": finishes,
		&"wins": maxi(int(academy_record.get(&"wins", 0)), 0),
		&"podiums": maxi(int(academy_record.get(&"podiums", 0)), 0),
		# Academy classifications are solo and historically always top-five.
		&"top_five": finishes,
		&"dnfs": maxi(int(academy_record.get(&"dnfs", 0)), 0),
		&"race_time_usec": maxi(int(academy_record.get(&"total_time_usec", 0)), 0),
	}
	for stat: StringName in deductions:
		race_statistics[stat] = maxi(
			int(race_statistics.get(stat, 0)) - int(deductions[stat]), 0
		)
	if int(race_statistics.get(&"finishes", 0)) < 1:
		achievements.erase(&"FIRST_FINISH")
	if int(race_statistics.get(&"wins", 0)) < 1:
		achievements.erase(&"FIRST_WIN")
	if int(race_statistics.get(&"podiums", 0)) < 5:
		achievements.erase(&"PODIUM_REGULAR")


func _sanitize_event_records(value: Variant) -> Dictionary:
	var output: Dictionary = {}
	if not value is Dictionary:
		return output
	for raw_event_id: Variant in (value as Dictionary):
		if output.size() >= MAX_EVENT_RECORDS:
			break
		var event_id := _safe_identifier(raw_event_id, &"")
		var raw_record: Variant = (value as Dictionary).get(raw_event_id, {})
		if event_id.is_empty() or event_id in [&"DAILY_CHALLENGE", &"WEEKLY_CHALLENGE"] or not raw_record is Dictionary:
			continue
		var record := raw_record as Dictionary
		output[event_id] = {
			&"starts": maxi(int(_dictionary_value(record, "starts", 0)), 0),
			&"finishes": maxi(int(_dictionary_value(record, "finishes", 0)), 0),
			&"wins": maxi(int(_dictionary_value(record, "wins", 0)), 0),
			&"podiums": maxi(int(_dictionary_value(record, "podiums", 0)), 0),
			&"dnfs": maxi(int(_dictionary_value(record, "dnfs", 0)), 0),
			&"best_finish": clampi(int(_dictionary_value(record, "best_finish", 0)), 0, 99),
			&"best_time_usec": int(_dictionary_value(record, "best_time_usec", -1)),
			&"best_lap_usec": int(_dictionary_value(record, "best_lap_usec", -1)),
			&"total_time_usec": maxi(int(_dictionary_value(record, "total_time_usec", 0)), 0),
			&"last_position": clampi(int(_dictionary_value(record, "last_position", 0)), 0, 99),
			&"last_status": _safe_identifier(_dictionary_value(record, "last_status", &"UNRIDDEN"), &"UNRIDDEN"),
			&"last_medal": _safe_identifier(_dictionary_value(record, "last_medal", &"UNRIDDEN"), &"UNRIDDEN"),
		}
	return output


func _sanitize_challenge_records(value: Variant) -> Dictionary:
	var output: Dictionary = {}
	if not value is Dictionary:
		return output
	for raw_challenge_id: Variant in (value as Dictionary):
		if output.size() >= MAX_CHALLENGE_RECORDS:
			break
		var challenge_id := _safe_identifier(raw_challenge_id, &"")
		var raw_record: Variant = (value as Dictionary).get(raw_challenge_id, {})
		if challenge_id.is_empty() or not raw_record is Dictionary:
			continue
		var record := raw_record as Dictionary
		var event_id := _safe_identifier(_dictionary_value(record, "event_id", &""), &"")
		var stored_challenge_id := _safe_identifier(_dictionary_value(record, "challenge_id", &""), &"")
		var expected_prefix := "DAILY_" if event_id == &"DAILY_CHALLENGE" else "WEEKLY_"
		if (
			event_id not in [&"DAILY_CHALLENGE", &"WEEKLY_CHALLENGE"]
			or stored_challenge_id != challenge_id
			or not String(challenge_id).begins_with(expected_prefix)
		):
			continue
		output[challenge_id] = {
			&"event_id": event_id,
			&"challenge_id": challenge_id,
			&"starts": maxi(int(_dictionary_value(record, "starts", 0)), 0),
			&"finishes": maxi(int(_dictionary_value(record, "finishes", 0)), 0),
			&"wins": maxi(int(_dictionary_value(record, "wins", 0)), 0),
			&"podiums": maxi(int(_dictionary_value(record, "podiums", 0)), 0),
			&"dnfs": maxi(int(_dictionary_value(record, "dnfs", 0)), 0),
			&"best_finish": clampi(int(_dictionary_value(record, "best_finish", 0)), 0, 99),
			&"total_time_usec": maxi(int(_dictionary_value(record, "total_time_usec", 0)), 0),
			&"last_position": clampi(int(_dictionary_value(record, "last_position", 0)), 0, 99),
			&"last_status": _safe_identifier(_dictionary_value(record, "last_status", &"UNRIDDEN"), &"UNRIDDEN"),
			&"last_medal": _safe_identifier(_dictionary_value(record, "last_medal", &"UNRIDDEN"), &"UNRIDDEN"),
			&"best_medal_rank": clampi(int(_dictionary_value(record, "best_medal_rank", 0)), 0, 4),
			&"updated_unix": maxi(int(_dictionary_value(record, "updated_unix", 0)), 0),
		}
	return output


func _sanitize_leaderboard_summary(value: Variant) -> Dictionary:
	var output: Dictionary = {}
	if not value is Dictionary:
		return output
	for raw_signature: Variant in (value as Dictionary):
		if output.size() >= MAX_LEADERBOARD_SUMMARIES:
			break
		var signature := str(raw_signature).strip_edges().substr(0, 256)
		var raw_entry: Variant = (value as Dictionary).get(raw_signature, {})
		if signature.is_empty() or not raw_entry is Dictionary:
			continue
		var entry := raw_entry as Dictionary
		output[signature] = {
			&"rank": maxi(int(_dictionary_value(entry, "rank", 0)), 0),
			&"time_usec": int(_dictionary_value(entry, "time_usec", -1)),
			&"personal_best": bool(_dictionary_value(entry, "personal_best", false)),
			&"accepted": bool(_dictionary_value(entry, "accepted", false)),
			&"updated_unix": maxi(int(_dictionary_value(entry, "updated_unix", 0)), 0),
		}
	return output


func _record_event_result(
	event_id: StringName,
	challenge_id: StringName,
	result: Dictionary,
	_player_entry: Dictionary,
	result_valid: bool,
	finished: bool,
	status: StringName,
	position: int,
	time_usec: int,
	lap_times: Array[int]
) -> void:
	var scoped_challenge := not challenge_id.is_empty()
	var record_value: Variant = (
		challenge_records.get(challenge_id, {})
		if scoped_challenge
		else event_records.get(event_id, {})
	)
	var record: Dictionary = (record_value as Dictionary).duplicate(true) if record_value is Dictionary else {}
	if scoped_challenge:
		record[&"event_id"] = event_id
		record[&"challenge_id"] = challenge_id
	record[&"starts"] = int(record.get(&"starts", 0)) + 1
	record[&"finishes"] = int(record.get(&"finishes", 0)) + (1 if finished else 0)
	record[&"wins"] = int(record.get(&"wins", 0)) + (1 if finished and position == 1 else 0)
	record[&"podiums"] = int(record.get(&"podiums", 0)) + (1 if finished and position > 0 and position <= 3 else 0)
	record[&"dnfs"] = int(record.get(&"dnfs", 0)) + (1 if status == &"DNF" else 0)
	var prior_finish := int(record.get(&"best_finish", 0))
	if finished and position > 0:
		record[&"best_finish"] = position if prior_finish <= 0 else mini(prior_finish, position)
	var effective_time := time_usec + maxi(int(_dictionary_value(result, "player_penalty_usec", 0)), 0)
	if not scoped_challenge:
		var prior_time := int(record.get(&"best_time_usec", -1))
		if finished and effective_time >= 0 and (prior_time < 0 or effective_time < prior_time):
			record[&"best_time_usec"] = effective_time
	if result_valid and time_usec > 0:
		record[&"total_time_usec"] = int(record.get(&"total_time_usec", 0)) + time_usec
	var best_lap := int(_dictionary_value(result, "fastest_lap_usec", -1))
	if best_lap <= 0:
		for lap_time: int in lap_times:
			if lap_time > 0 and (best_lap <= 0 or lap_time < best_lap):
				best_lap = lap_time
	if result_valid and not scoped_challenge:
		var prior_lap := int(record.get(&"best_lap_usec", -1))
		if best_lap > 0 and (prior_lap < 0 or best_lap < prior_lap):
			record[&"best_lap_usec"] = best_lap
	record[&"last_position"] = position
	record[&"last_status"] = status
	record[&"last_medal"] = (
		_safe_identifier(_dictionary_value(result, "medal", &"UNRIDDEN"), &"UNRIDDEN")
		if result_valid else &"NO_AWARD"
	)
	if scoped_challenge:
		record[&"updated_unix"] = int(Time.get_unix_time_from_system())
		challenge_records[challenge_id] = record
		_trim_challenge_records()
	else:
		event_records[event_id] = record
		_trim_event_records()


func _record_weekend_result(phase: StringName, classification: Array[Dictionary]) -> bool:
	var director: Variant = get_race_weekend_director()
	if director == null or director.get_current_phase() != phase:
		return false
	# Bind the result to the phase that produced it. Without this boundary, a
	# delayed duplicate from the previous race could be consumed as the newly
	# advanced session and transfer the field twice.
	if not director.submit_session_result(classification, phase):
		return false
	race_weekend_snapshot = director.to_dictionary()
	# If the player misses the LCQ transfer, the director deterministically runs
	# the AI-only main and reaches RESULTS. Record that completed field as the
	# championship round without fabricating a player main-event start.
	if phase != &"MAIN" and director.is_complete():
		var service: Variant = get_championship_service()
		var next_round: Dictionary = service.get_next_round() if service != null else {}
		if (
				service != null
				and StringName(next_round.get(&"event_id", &"")) == StringName(director.event_id)
				and service.record_round_result(
					StringName(next_round.get(&"round_id", &"")),
					director.get_final_classification()
				)
			):
			championship_snapshot = service.to_dictionary()
	return true


func _apply_structured_rewards(rewards: Dictionary) -> Dictionary:
	var cash_reward := maxi(int(_dictionary_value(rewards, "cash", _dictionary_value(rewards, "credits", 0))), 0)
	var reputation_reward := maxi(int(_dictionary_value(rewards, "reputation", 0)), 0)
	var old_cash := cash
	cash = mini(cash + cash_reward, MAX_CASH)
	racer_reputation += reputation_reward
	if cash != old_cash:
		_record_transaction(cash - old_cash, &"structured_race_reward")
	if cash_reward > 0 or reputation_reward > 0:
		_emit_or_defer_reward(cash - old_cash, reputation_reward)
	return {&"cash": cash - old_cash, &"reputation": reputation_reward}


func _increment_stat(stat: StringName, amount: int) -> void:
	if amount <= 0:
		return
	race_statistics[stat] = maxi(int(race_statistics.get(stat, 0)) + amount, 0)


func _evaluate_meta_achievements() -> void:
	if int(race_statistics.get(&"finishes", 0)) >= 1: _unlock_achievement(&"FIRST_FINISH")
	if int(race_statistics.get(&"wins", 0)) >= 1: _unlock_achievement(&"FIRST_WIN")
	if int(race_statistics.get(&"podiums", 0)) >= 5: _unlock_achievement(&"PODIUM_REGULAR")
	if int(race_statistics.get(&"holeshots", 0)) >= 5: _unlock_achievement(&"HOLESHOT_HERO")
	if int(race_statistics.get(&"laps_completed", 0)) >= 100: _unlock_achievement(&"CENTURY_LAPS")
	if int(race_statistics.get(&"overtakes", 0)) >= 100: _unlock_achievement(&"PASS_MASTER")
	if get_completed_academy_lessons().size() >= ACADEMY_CATALOG_SCRIPT.create_default().get_lessons().size():
		_unlock_achievement(&"ACADEMY_GRADUATE")


func _unlock_achievement(achievement_id: StringName) -> bool:
	if achievement_id.is_empty() or achievements.has(achievement_id):
		return false
	achievements.append(achievement_id)
	_emit_or_defer_achievement(achievement_id)
	return true


func _find_player_classification_entry(classification: Array[Dictionary]) -> Dictionary:
	for entry: Dictionary in classification:
		if bool(_dictionary_value(entry, "is_player", false)) or StringName(_dictionary_value(entry, "rider_id", &"")) == &"PLAYER":
			return entry.duplicate(true)
	return {}


func _count_player_classification_entries(classification: Array[Dictionary]) -> int:
	var count := 0
	for entry: Dictionary in classification:
		if bool(_dictionary_value(entry, "is_player", false)) or StringName(_dictionary_value(entry, "rider_id", &"")) == &"PLAYER":
			count += 1
	return count


func _trim_event_records() -> void:
	while event_records.size() > MAX_EVENT_RECORDS:
		var first_key: Variant = event_records.keys()[0]
		event_records.erase(first_key)


func _trim_challenge_records() -> void:
	while challenge_records.size() > MAX_CHALLENGE_RECORDS:
		var oldest_key: Variant = null
		var oldest_timestamp := 9_223_372_036_854_775_000
		for raw_key: Variant in challenge_records:
			var raw_record: Variant = challenge_records.get(raw_key, {})
			var timestamp := int(_dictionary_value(raw_record as Dictionary, "updated_unix", 0)) if raw_record is Dictionary else 0
			if timestamp < oldest_timestamp:
				oldest_timestamp = timestamp
				oldest_key = raw_key
		if oldest_key == null:
			break
		challenge_records.erase(oldest_key)


func _trim_oldest_leaderboard_summaries() -> void:
	while leaderboard_summary.size() > MAX_LEADERBOARD_SUMMARIES:
		var oldest_key: Variant = null
		var oldest_timestamp := 9_223_372_036_854_775_000
		for raw_key: Variant in leaderboard_summary:
			var raw_entry: Variant = leaderboard_summary.get(raw_key, {})
			var timestamp := int(_dictionary_value(raw_entry as Dictionary, "updated_unix", 0)) if raw_entry is Dictionary else 0
			if timestamp < oldest_timestamp:
				oldest_timestamp = timestamp
				oldest_key = raw_key
		if oldest_key == null:
			break
		leaderboard_summary.erase(oldest_key)


func _dictionary_value(source: Dictionary, key: String, fallback: Variant = null) -> Variant:
	if source.has(key):
		return source[key]
	var named_key := StringName(key)
	return source[named_key] if source.has(named_key) else fallback


func _dictionary_array(value: Variant, maximum: int = 128) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	if not value is Array:
		return output
	for raw_entry: Variant in value:
		if output.size() >= maximum:
			break
		if raw_entry is Dictionary:
			output.append((raw_entry as Dictionary).duplicate(true))
	return output


func _int_array(value: Variant, maximum: int = 128) -> Array[int]:
	var output: Array[int] = []
	if value is Array or value is PackedInt32Array or value is PackedInt64Array:
		for raw_value: Variant in value:
			if output.size() >= maximum:
				break
			output.append(maxi(int(raw_value), 0))
	return output


func _sanitize_string_name_array(value: Variant, maximum: int) -> Array[StringName]:
	var output: Array[StringName] = []
	if value is Array or value is PackedStringArray:
		for raw_value: Variant in value:
			if output.size() >= maximum:
				break
			var identifier := _safe_identifier(raw_value, &"")
			if not identifier.is_empty() and not output.has(identifier):
				output.append(identifier)
	return output


func _sanitize_string_array(value: Variant, maximum: int, maximum_length: int) -> Array[String]:
	var output: Array[String] = []
	if value is Array or value is PackedStringArray:
		for raw_value: Variant in value:
			if output.size() >= maximum:
				break
			var text := str(raw_value).strip_edges().substr(0, maximum_length)
			if not text.is_empty() and not output.has(text):
				output.append(text)
	return output


func _sanitize_fingerprint_ledger(value: Variant, maximum: int) -> Array[String]:
	var newest_unique: Array[String] = []
	if not (value is Array or value is PackedStringArray):
		return newest_unique
	for index: int in range(value.size() - 1, -1, -1):
		if newest_unique.size() >= maximum:
			break
		var fingerprint := str(value[index]).strip_edges()
		if _is_sha256_fingerprint(fingerprint) and not newest_unique.has(fingerprint):
			newest_unique.push_front(fingerprint)
	return newest_unique


func _sanitize_transaction_log(value: Variant) -> Array[Dictionary]:
	var sanitized: Array[Dictionary] = []
	if not value is Array:
		return sanitized
	var first_index := maxi((value as Array).size() - MAX_LOG_ENTRIES, 0)
	for index: int in range(first_index, (value as Array).size()):
		var raw_entry: Variant = (value as Array)[index]
		if not raw_entry is Dictionary:
			continue
		var reason := _safe_identifier(_dictionary_value(raw_entry as Dictionary, "reason", &""), &"")
		if reason.is_empty():
			continue
		sanitized.append({
			&"timestamp_usec": maxi(int(_dictionary_value(raw_entry as Dictionary, "timestamp_usec", 0)), 0),
			&"delta": clampi(int(_dictionary_value(raw_entry as Dictionary, "delta", 0)), -MAX_CASH, MAX_CASH),
			&"reason": reason,
			&"balance": clampi(int(_dictionary_value(raw_entry as Dictionary, "balance", 0)), 0, MAX_CASH),
		})
	return sanitized


func _serialize_academy_result_bindings() -> Dictionary:
	var serialized: Dictionary = {}
	for result_id: String in academy_result_bindings:
		serialized[result_id] = String(academy_result_bindings[result_id])
	return serialized


func _sanitize_academy_result_bindings(value: Variant) -> Dictionary[String, StringName]:
	var sanitized: Dictionary[String, StringName] = {}
	if not value is Dictionary:
		return sanitized
	var keys: Array = (value as Dictionary).keys()
	var first_index := maxi(keys.size() - MAX_ACADEMY_RESULT_BINDINGS, 0)
	for index: int in range(first_index, keys.size()):
		var result_id := str(keys[index]).strip_edges()
		var lesson_id := _safe_identifier((value as Dictionary).get(keys[index], &""), &"")
		if _is_sha256_fingerprint(result_id) and not lesson_id.is_empty():
			sanitized[result_id] = lesson_id
	return sanitized


func _bind_academy_result(result_id: String, lesson_id: StringName) -> void:
	academy_result_bindings[result_id] = lesson_id
	while academy_result_bindings.size() > MAX_ACADEMY_RESULT_BINDINGS:
		academy_result_bindings.erase(academy_result_bindings.keys()[0])


func _is_sha256_fingerprint(value: String) -> bool:
	if value.length() != 64 or value != value.to_lower():
		return false
	for character: String in value:
		if character not in "0123456789abcdef":
			return false
	return true


func _sanitize_int_dictionary(value: Variant, maximum: int, minimum_value: int, maximum_value: int) -> Dictionary[StringName, int]:
	var output: Dictionary[StringName, int] = {}
	if not value is Dictionary:
		return output
	for raw_key: Variant in (value as Dictionary):
		if output.size() >= maximum:
			break
		var key := _safe_identifier(raw_key, &"")
		if not key.is_empty():
			output[key] = clampi(int((value as Dictionary).get(raw_key, minimum_value)), minimum_value, maximum_value)
	return output


func _serialize_int_dictionary(value: Dictionary[StringName, int]) -> Dictionary:
	var output: Dictionary = {}
	for key: StringName in value:
		output[String(key)] = value[key]
	return output


func _safe_identifier(value: Variant, fallback: StringName) -> StringName:
	var identifier := StringName(str(value).strip_edges().to_upper().substr(0, 64))
	return identifier if _is_safe_identifier(identifier) else fallback


func _is_safe_identifier(identifier: StringName) -> bool:
	var text := String(identifier)
	if text.is_empty() or text.length() > 64:
		return false
	for index: int in text.length():
		var code := text.unicode_at(index)
		var is_upper := code >= 65 and code <= 90
		var is_digit := code >= 48 and code <= 57
		if not is_upper and not is_digit and code != 95:
			return false
	return true


func _sanitize_profile_id(value: String) -> String:
	var text := value.strip_edges().substr(0, 80)
	for index: int in text.length():
		var code := text.unicode_at(index)
		var is_upper := code >= 65 and code <= 90
		var is_lower := code >= 97 and code <= 122
		var is_digit := code >= 48 and code <= 57
		if not is_upper and not is_lower and not is_digit and code not in [45, 46, 95]:
			return ""
	return text


func _generate_profile_id() -> String:
	return "local-%x-%x" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]


func _sanitize_settings_reference(path: String) -> String:
	var normalized := path.strip_edges().substr(0, 180)
	return normalized if normalized.begins_with("user://") else DEFAULT_SETTINGS_REFERENCE


func _json_safe_copy(value: Variant) -> Variant:
	var parsed: Variant = JSON.parse_string(JSON.stringify(value))
	return parsed if parsed != null else {}
