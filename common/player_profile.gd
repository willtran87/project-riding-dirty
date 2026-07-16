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
const PROFILE_SCHEMA_VERSION: int = 2
const COURSE_LAYOUT_VERSION: int = 4
const MAX_CASH: int = 999_999
const MAX_LOG_ENTRIES: int = 30
const MAX_RESULT_IDS: int = 64
const MAX_EVENT_RECORDS: int = 64
const MAX_LEADERBOARD_SUMMARIES: int = 48
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
var academy_progress: Dictionary[StringName, int] = {}
var rider_cosmetics: Dictionary = {}
var race_statistics: Dictionary = {}
var event_records: Dictionary = {}
var achievements: Array[StringName] = []
var leaderboard_summary: Dictionary = {}
var settings_reference: String = DEFAULT_SETTINGS_REFERENCE
var recent_result_ids: Array[String] = []

var _active_activity: StringName = &"CIRCUIT"
var _profile_migration_pending: bool = false


func _ready() -> void:
	# Autoloads initialize before Main can isolate a command-line smoke run.
	# Disable persistence here as the first operation so test setup and schema
	# migration can never rewrite a real rider profile.
	if &"--smoke-test" in OS.get_cmdline_user_args():
		persistence_enabled = false
	_load_profile()
	_ensure_full_race_defaults()
	if _profile_migration_pending:
		_save_profile()
		_profile_migration_pending = false
	EventBus.activity_started.connect(_on_activity_started)
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


func is_first_run_onboarding_active() -> bool:
	return not first_run_onboarding_complete


func complete_first_run_onboarding() -> bool:
	if first_run_onboarding_complete:
		return false
	first_run_onboarding_complete = true
	_emit_meta_and_save()
	return true


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
	return legacy_pine_unlock or _meets_pine_unlock_requirements()


func _meets_pine_unlock_requirements() -> bool:
	return get_quarry_progress_count() >= 2 or has_beaten_rival(&"CIRCUIT") or get_total_reputation() >= 80


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
	_emit_and_save()
	reward_granted.emit(cash - old_cash, reputation_reward)
	return true


func get_cosmetic_tier() -> int:
	return clampi(style_tokens / 2, 0, 3)


func unlock_feat(feat_id: String) -> bool:
	if feat_id.is_empty() or unlocked_feats.has(feat_id):
		return false
	unlocked_feats.append(feat_id)
	style_tokens += 1
	_record_transaction(0, &"riding_feat")
	_emit_and_save()
	return true


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
		&"academy_progress": academy_progress.duplicate(true),
		&"rider_cosmetics": rider_cosmetics.duplicate(true),
		&"race_statistics": race_statistics.duplicate(true),
		&"event_records": event_records.duplicate(true),
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


func record_championship_round(round_id: StringName, classification: Array[Dictionary]) -> bool:
	var service: Variant = get_championship_service()
	if not service.record_round_result(round_id, classification):
		return false
	championship_snapshot = service.to_dictionary()
	var champion: Dictionary = service.get_champion()
	if not champion.is_empty() and StringName(_dictionary_value(champion, "rider_id", &"")) == &"PLAYER":
		_unlock_achievement(&"DIRT_TOUR_CHAMPION")
	_emit_meta_and_save()
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


func get_event_record(event_id: StringName) -> Dictionary:
	var record: Variant = event_records.get(event_id, event_records.get(String(event_id), {}))
	return (record as Dictionary).duplicate(true) if record is Dictionary else {}


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


func record_academy_result(lesson_id: StringName, metrics: Dictionary) -> Dictionary:
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
		reward_granted.emit(credited_cash, credited_reputation)
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
	_emit_and_save()
	return evaluation


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


func record_race_result(result: Dictionary, apply_result_rewards: bool = false) -> Dictionary:
	_ensure_full_race_defaults()
	var event_id := _safe_identifier(_dictionary_value(result, "event_id", _active_activity), _active_activity)
	var run_id := str(_dictionary_value(result, "run_id", "")).strip_edges().substr(0, 160)
	var signature := str(_dictionary_value(result, "signature", "")).strip_edges().substr(0, 256)
	var player_time_usec := int(_dictionary_value(result, "player_time_usec", -1))
	var penalty_usec := maxi(int(_dictionary_value(result, "player_penalty_usec", 0)), 0)
	var player_position := maxi(int(_dictionary_value(result, "player_position", 0)), 0)
	var classification := _dictionary_array(_dictionary_value(result, "classification", []), 24)
	var player_entry := _find_player_classification_entry(classification)
	if player_position <= 0:
		player_position = maxi(int(_dictionary_value(player_entry, "position", 0)), 0)
	var status := _safe_identifier(_dictionary_value(player_entry, "status", &"FINISHED"), &"FINISHED")
	var result_valid := bool(_dictionary_value(result, "valid", true))
	var fingerprint := run_id
	if fingerprint.is_empty():
		fingerprint = "%s|%s|%d|%d|%d" % [String(event_id), signature, player_time_usec, player_position, penalty_usec]
	if recent_result_ids.has(fingerprint):
		return {&"accepted": false, &"duplicate": true, &"result_id": fingerprint}

	recent_result_ids.append(fingerprint)
	while recent_result_ids.size() > MAX_RESULT_IDS:
		recent_result_ids.pop_front()
	first_run_onboarding_complete = true
	var finished := result_valid and status in [&"FINISHED", &"CLASSIFIED"] and player_time_usec >= 0
	if not result_valid and status in [&"FINISHED", &"CLASSIFIED"]:
		status = &"DSQ"
	total_runs += 1
	_increment_stat(&"starts", 1)
	_increment_stat(&"finishes", 1 if finished else 0)
	_increment_stat(&"wins", 1 if finished and player_position == 1 else 0)
	_increment_stat(&"podiums", 1 if finished and player_position >= 1 and player_position <= 3 else 0)
	_increment_stat(&"top_five", 1 if finished and player_position >= 1 and player_position <= 5 else 0)
	_increment_stat(&"dnfs", 1 if status == &"DNF" else 0)
	_increment_stat(&"dsqs", 1 if status == &"DSQ" else 0)
	_increment_stat(&"holeshots", 1 if StringName(_dictionary_value(result, "holeshot_rider_id", &"")) == &"PLAYER" else 0)
	_increment_stat(&"fastest_laps", 1 if StringName(_dictionary_value(result, "fastest_rider_id", &"")) == &"PLAYER" else 0)
	_increment_stat(&"overtakes", maxi(int(_dictionary_value(result, "overtakes", 0)), 0))
	_increment_stat(&"contacts", maxi(int(_dictionary_value(result, "contacts", 0)), 0))
	_increment_stat(&"crashes", maxi(int(_dictionary_value(result, "crashes", 0)), 0))
	_increment_stat(&"near_misses", maxi(int(_dictionary_value(result, "near_misses", 0)), 0))
	_increment_stat(&"resets", maxi(int(_dictionary_value(result, "reset_count", 0)), 0))
	_increment_stat(&"off_course", maxi(int(_dictionary_value(result, "off_course_count", 0)), 0))
	_increment_stat(&"wrong_way", maxi(int(_dictionary_value(result, "wrong_way_count", 0)), 0))
	_increment_stat(&"cuts", maxi(int(_dictionary_value(result, "cut_count", 0)), 0))
	_increment_stat(&"penalty_usec", penalty_usec)
	_increment_stat(&"race_time_usec", maxi(player_time_usec, 0))
	var lap_times := _int_array(_dictionary_value(result, "lap_times_usec", []), 128)
	var completed_laps := 0
	for lap_time: int in lap_times:
		if lap_time > 0:
			completed_laps += 1
	_increment_stat(&"laps_completed", completed_laps)
	if finished and player_position > 0:
		var previous_best_finish := int(race_statistics.get(&"best_finish", 0))
		race_statistics[&"best_finish"] = player_position if previous_best_finish <= 0 else mini(previous_best_finish, player_position)
	_record_event_result(event_id, result, player_entry, finished, status, player_position, player_time_usec, lap_times)
	var medal := _safe_identifier(_dictionary_value(result, "medal", &"UNRIDDEN"), &"UNRIDDEN")
	if finished:
		_record_best_medal(event_id, medal)
	var rewards_granted := {&"cash": 0, &"reputation": 0}
	if apply_result_rewards and finished:
		rewards_granted = _apply_structured_rewards(_dictionary_value(result, "rewards", {}) as Dictionary)
	var explicit_round := _safe_identifier(
		_dictionary_value(result, "round_id", _dictionary_value(result, "championship_round_id", &"")), &""
	)
	var weekend_phase := _safe_identifier(_dictionary_value(result, "weekend_phase", &""), &"")
	var weekend_id := _safe_identifier(_dictionary_value(result, "weekend_id", &""), &"")
	var weekend_managed := bool(_dictionary_value(result, "weekend_managed", false))
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
		record_championship_round(explicit_round, classification)
	var rival_target: int = int(ROOK_TARGETS_USEC.get(event_id, -1))
	if finished and rival_target > 0 and player_time_usec + penalty_usec <= rival_target and not rival_victories.has(event_id):
		rival_victories.append(event_id)
	_evaluate_meta_achievements()
	var summary := {
		&"accepted": true,
		&"duplicate": false,
		&"result_id": fingerprint,
		&"event_id": event_id,
		&"position": player_position,
		&"status": status,
		&"valid": result_valid,
		&"rewards_granted": rewards_granted.duplicate(),
		&"stats": race_statistics.duplicate(true),
		&"event_record": (event_records.get(event_id, {}) as Dictionary).duplicate(true),
	}
	_emit_meta_and_save()
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
	reward_granted.emit(granted_cash, safe_reputation)
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
	academy_progress.clear()
	rider_cosmetics = _default_cosmetics()
	race_statistics = _default_race_statistics()
	event_records.clear()
	achievements.clear()
	leaderboard_summary.clear()
	settings_reference = DEFAULT_SETTINGS_REFERENCE
	recent_result_ids.clear()
	_emit_and_save()


func _on_activity_started(activity: StringName) -> void:
	_active_activity = activity


func _on_activity_completed(activity: StringName, result_value: int, medal: StringName, _reported_new_best: bool) -> void:
	first_run_onboarding_complete = true
	var first_clear := not has_completed_event(activity)
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
	# Replays remain a useful source of cash and skill practice, but reputation is
	# a progression signal. A non-improving repeat cannot outpace learning a new
	# event or setting a personal best.
	if not first_clear and not is_new_best:
		reputation_reward = maxi(roundi(float(reputation_reward) * 0.35), 1)
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
	meta_progress_changed.emit(get_meta_snapshot())
	_save_profile()


func _emit_meta_and_save() -> void:
	profile_changed.emit(cash, racer_reputation, current_setup)
	meta_progress_changed.emit(get_meta_snapshot())
	_save_profile()


func _save_profile() -> void:
	if not persistence_enabled:
		return
	var profile_data := _profile_to_dictionary()
	if OS.has_feature("web"):
		if not WebPlatform.save_json(WEB_SAVE_KEY, profile_data):
			push_warning("Unable to save rider profile to browser storage.")
		return
	var save_result := ATOMIC_CONFIG_STORE.save_section(SAVE_PATH, &"profile", profile_data)
	if not bool(save_result.get("ok", false)):
		push_warning("Unable to save rider profile: %s" % str(save_result.get("error", "unknown_error")))


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
		"academy_progress": _serialize_int_dictionary(academy_progress),
		"rider_cosmetics": _json_safe_copy(rider_cosmetics),
		"race_statistics": _json_safe_copy(race_statistics),
		"event_records": _json_safe_copy(event_records),
		"achievements": _serialize_string_names(achievements),
		"leaderboard_summary": _json_safe_copy(leaderboard_summary),
		"settings_reference": settings_reference,
		"recent_result_ids": recent_result_ids.duplicate(),
		"first_run_onboarding_complete": first_run_onboarding_complete,
	}


func _apply_profile_dictionary(profile_data: Dictionary) -> void:
	var saved_profile_schema := maxi(int(_dictionary_value(profile_data, "profile_schema_version", 1)), 1)
	cash = clampi(int(profile_data.get("cash", 0)), 0, MAX_CASH)
	racer_reputation = maxi(int(profile_data.get("racer_reputation", 0)), 0)
	freestyler_reputation = maxi(int(profile_data.get("freestyler_reputation", 0)), 0)
	explorer_reputation = maxi(int(profile_data.get("explorer_reputation", 0)), 0)
	total_runs = maxi(int(profile_data.get("total_runs", 0)), 0)
	first_run_onboarding_complete = bool(_dictionary_value(
		profile_data,
		"first_run_onboarding_complete",
		total_runs > 0
	))
	current_setup = StringName(str(profile_data.get("current_setup", "BALANCED")))
	best_freestyle_score = maxi(int(profile_data.get("best_freestyle_score", 0)), 0)
	best_discovery_usec = int(profile_data.get("best_discovery_usec", -1))
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
			if _is_safe_identifier(activity) and best_medal_ranks.size() < MAX_EVENT_RECORDS:
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
	academy_progress = _sanitize_int_dictionary(_dictionary_value(profile_data, "academy_progress", {}), 64, 0, 3)
	var cosmetics_value: Variant = _dictionary_value(profile_data, "rider_cosmetics", {})
	rider_cosmetics = _sanitize_cosmetics(cosmetics_value as Dictionary if cosmetics_value is Dictionary else {})
	var statistics_value: Variant = _dictionary_value(profile_data, "race_statistics", {})
	race_statistics = _sanitize_statistics(statistics_value as Dictionary if statistics_value is Dictionary else {})
	event_records = _sanitize_event_records(_dictionary_value(profile_data, "event_records", {}))
	achievements = _sanitize_string_name_array(_dictionary_value(profile_data, "achievements", []), 128)
	leaderboard_summary = _sanitize_leaderboard_summary(_dictionary_value(profile_data, "leaderboard_summary", {}))
	settings_reference = _sanitize_settings_reference(str(_dictionary_value(profile_data, "settings_reference", DEFAULT_SETTINGS_REFERENCE)))
	recent_result_ids = _sanitize_string_array(_dictionary_value(profile_data, "recent_result_ids", []), MAX_RESULT_IDS, 160)
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


func _sanitize_event_records(value: Variant) -> Dictionary:
	var output: Dictionary = {}
	if not value is Dictionary:
		return output
	for raw_event_id: Variant in (value as Dictionary):
		if output.size() >= MAX_EVENT_RECORDS:
			break
		var event_id := _safe_identifier(raw_event_id, &"")
		var raw_record: Variant = (value as Dictionary).get(raw_event_id, {})
		if event_id.is_empty() or not raw_record is Dictionary:
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
	result: Dictionary,
	_player_entry: Dictionary,
	finished: bool,
	status: StringName,
	position: int,
	time_usec: int,
	lap_times: Array[int]
) -> void:
	var record_value: Variant = event_records.get(event_id, {})
	var record: Dictionary = (record_value as Dictionary).duplicate(true) if record_value is Dictionary else {}
	record[&"starts"] = int(record.get(&"starts", 0)) + 1
	record[&"finishes"] = int(record.get(&"finishes", 0)) + (1 if finished else 0)
	record[&"wins"] = int(record.get(&"wins", 0)) + (1 if finished and position == 1 else 0)
	record[&"podiums"] = int(record.get(&"podiums", 0)) + (1 if finished and position > 0 and position <= 3 else 0)
	record[&"dnfs"] = int(record.get(&"dnfs", 0)) + (1 if status == &"DNF" else 0)
	var prior_finish := int(record.get(&"best_finish", 0))
	if finished and position > 0:
		record[&"best_finish"] = position if prior_finish <= 0 else mini(prior_finish, position)
	var effective_time := time_usec + maxi(int(_dictionary_value(result, "player_penalty_usec", 0)), 0)
	var prior_time := int(record.get(&"best_time_usec", -1))
	if finished and effective_time >= 0 and (prior_time < 0 or effective_time < prior_time):
		record[&"best_time_usec"] = effective_time
	if time_usec > 0:
		record[&"total_time_usec"] = int(record.get(&"total_time_usec", 0)) + time_usec
	var best_lap := int(_dictionary_value(result, "fastest_lap_usec", -1))
	if best_lap <= 0:
		for lap_time: int in lap_times:
			if lap_time > 0 and (best_lap <= 0 or lap_time < best_lap):
				best_lap = lap_time
	var prior_lap := int(record.get(&"best_lap_usec", -1))
	if best_lap > 0 and (prior_lap < 0 or best_lap < prior_lap):
		record[&"best_lap_usec"] = best_lap
	record[&"last_position"] = position
	record[&"last_status"] = status
	record[&"last_medal"] = _safe_identifier(_dictionary_value(result, "medal", &"UNRIDDEN"), &"UNRIDDEN")
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
		reward_granted.emit(cash - old_cash, reputation_reward)
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
	if academy_progress.size() >= ACADEMY_CATALOG_SCRIPT.create_default().get_lessons().size():
		_unlock_achievement(&"ACADEMY_GRADUATE")


func _unlock_achievement(achievement_id: StringName) -> bool:
	if achievement_id.is_empty() or achievements.has(achievement_id):
		return false
	achievements.append(achievement_id)
	achievement_unlocked.emit(achievement_id)
	return true


func _find_player_classification_entry(classification: Array[Dictionary]) -> Dictionary:
	for entry: Dictionary in classification:
		if bool(_dictionary_value(entry, "is_player", false)) or StringName(_dictionary_value(entry, "rider_id", &"")) == &"PLAYER":
			return entry.duplicate(true)
	return {}


func _trim_event_records() -> void:
	while event_records.size() > MAX_EVENT_RECORDS:
		var first_key: Variant = event_records.keys()[0]
		event_records.erase(first_key)


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
