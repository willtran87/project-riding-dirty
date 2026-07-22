extends CanvasLayer
class_name GarageUi
## Setup selection and purchase surface projected from the persistent Profile autoload.

signal ride_requested(setup: StringName, activity: StringName)
signal workshop_visibility_changed(open: bool)
signal workshop_selection_changed(snapshot: Dictionary)
signal workshop_action_completed(category: StringName, item_id: StringName, success: bool)

const BIKE_CATALOG_SCRIPT := preload("res://features/career/racing_bike_catalog.gd")
const BIKE_BUILD_SCRIPT := preload("res://features/career/racing_bike_build.gd")
const ACADEMY_CATALOG_SCRIPT := preload("res://features/career/academy_lesson_catalog.gd")

const SETUPS: Array[StringName] = [&"TRAIL", &"BALANCED", &"ATTACK"]
const EVENTS: Array[StringName] = [
	&"CIRCUIT", &"PINE_ENDURO", &"MESA_PRACTICE", &"MESA_QUALIFYING", &"MESA_HEAT", &"MESA_LCQ",
	&"MESA_MX", &"MESA_ELIMINATION", &"MESA_RIVAL", &"MESA_ENDURANCE",
	&"QUARRY_HILLCLIMB", &"PINE_WET", &"MESA_RHYTHM", &"DAILY_CHALLENGE", &"WEEKLY_CHALLENGE",
	&"ACADEMY", &"FREESTYLE", &"DISCOVERY",
]
const INITIAL_EVENT: StringName = &"CIRCUIT"
const CREAM := Color("f7e5b2")
const AMBER := Color("ffb52d")
const CYAN := Color("56d6ff")
const MUTED := Color("8b989f")
const DARK := Color(0.025, 0.03, 0.036, 0.92)
const WORKSHOP_CATEGORIES: Array[StringName] = [&"BIKE", &"CLASS", &"TUNE", &"PART", &"STYLE", &"BUILD"]
const PART_SLOTS: Array[StringName] = [&"ENGINE", &"TIRES", &"SUSPENSION", &"BRAKES", &"CHASSIS"]
const TUNE_PRESETS: Array[Dictionary] = [
	{&"preset_id": &"BALANCED", &"display_name": "Balanced Baseline", &"description": "Neutral geometry and delivery. The clean comparison setup.", &"tune": {&"gearing": 0.0, &"tire_grip": 0.0, &"suspension_stiffness": 0.0, &"suspension_damping": 0.0, &"preload": 0.0, &"brake_bias": 0.0}},
	{&"preset_id": &"HOLESHOT", &"display_name": "Holeshot", &"description": "Short gearing and planted drive trade maximum speed for launch authority.", &"tune": {&"gearing": 0.65, &"tire_grip": 0.25, &"suspension_stiffness": 0.15, &"suspension_damping": 0.20, &"preload": 0.15, &"brake_bias": 0.0}},
	{&"preset_id": &"HARDPACK", &"display_name": "Hardpack Precision", &"description": "High tire support and a firmer chassis for fast, defined quarry lines.", &"tune": {&"gearing": -0.15, &"tire_grip": 0.80, &"suspension_stiffness": 0.45, &"suspension_damping": 0.35, &"preload": -0.15, &"brake_bias": 0.20}},
	{&"preset_id": &"RHYTHM", &"display_name": "Rhythm Attack", &"description": "Extra preload and damping make doubles and triples easier to connect.", &"tune": {&"gearing": 0.15, &"tire_grip": 0.15, &"suspension_stiffness": 0.30, &"suspension_damping": 0.45, &"preload": 0.80, &"brake_bias": -0.10}},
	{&"preset_id": &"ENDURO", &"display_name": "Enduro Control", &"description": "Plush damping, traction, and mild acceleration for long rough stages.", &"tune": {&"gearing": 0.25, &"tire_grip": 0.55, &"suspension_stiffness": -0.30, &"suspension_damping": 0.75, &"preload": 0.25, &"brake_bias": 0.25}},
]
const STYLE_PRESETS: Array[Dictionary] = [
	{&"style_id": &"FACTORY", &"display_name": "Factory Issue", &"required_tier": 0, &"description": "Classic white helmet, Mesa red kit, and factory number plate.", &"changes": {&"helmet": "CLASSIC_WHITE", &"jersey": "MESA_RED", &"pants": "CHARCOAL", &"boots": "BLACK", &"gloves": "BLACK", &"bike_livery": "FACTORY", &"number_plate": "WHITE", &"accent_color": "E25532"}},
	{&"style_id": &"DESERT", &"display_name": "Desert Works", &"required_tier": 1, &"description": "Sand, rust, and cream colors earned through riding feats.", &"changes": {&"helmet": "DESERT_CREAM", &"jersey": "MESA_SAND", &"pants": "RUST", &"boots": "BROWN", &"gloves": "CREAM", &"bike_livery": "DESERT_WORKS", &"number_plate": "CREAM", &"accent_color": "E58A3A"}},
	{&"style_id": &"NIGHT", &"display_name": "Night Race", &"required_tier": 2, &"description": "Dark racewear and electric cyan accents for the full gate.", &"changes": {&"helmet": "NIGHT_BLACK", &"jersey": "NIGHT_CYAN", &"pants": "BLACK", &"boots": "BLACK", &"gloves": "CYAN", &"bike_livery": "NIGHT_RACE", &"number_plate": "BLACK", &"accent_color": "56D6FF"}},
	{&"style_id": &"CHAMPION", &"display_name": "Tour Champion", &"required_tier": 3, &"description": "Gold-accented premier kit reserved for a decorated rider.", &"changes": {&"helmet": "CHAMPION_GOLD", &"jersey": "TOUR_CHAMPION", &"pants": "BLACK_GOLD", &"boots": "GOLD", &"gloves": "GOLD", &"bike_livery": "TOUR_CHAMPION", &"number_plate": "GOLD", &"accent_color": "FFB52D"}},
]

var _root: Control
var _profile_label: Label
var _setup_name: Label
var _tagline: Label
var _description: Label
var _strategy_label: Label
var _price_label: Label
var _status_label: Label
var _garage_context_label: Label
var _event_label: Label
var _event_description: Label
var _event_meta_label: Label
var _event_competition_label: Label
var _tour_label: Label
var _weekend_action_label: Label
var _event_accent: ColorRect
var _repair_label: Label
var _setup_left_hint: Label
var _setup_right_hint: Label
var _bars: Dictionary[StringName, ProgressBar] = {}
var _event_markers: Array[Label] = []
var _workshop_summary_panel: PanelContainer
var _workshop_summary_label: Label
var _workshop_meta_label: Label
var _workshop_overlay: PanelContainer
var _workshop_tabs_label: Label
var _workshop_title_label: Label
var _workshop_item_label: Label
var _workshop_detail_label: Label
var _workshop_build_label: Label
var _workshop_action_label: Label
var _workshop_status_label: Label
var _workshop_hint_label: Label
var _workshop_controls_label: Label
var _bike_catalog: Variant
var _selected_index: int = 1
var _event_index: int = 0
var _open: bool = false
var _workshop_open: bool = false
var _workshop_category_index: int = 0
var _workshop_item_indices: Dictionary[StringName, int] = {
	&"BIKE": 0, &"CLASS": 0, &"TUNE": 0, &"PART": 0, &"STYLE": 0, &"BUILD": 1,
}
var _competition_source: Object
var _active_competition_event: StringName = &"CIRCUIT"
var _active_competition_id: StringName = &""
var _active_ghost_best_usec: int = -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bike_catalog = BIKE_CATALOG_SCRIPT.create_default()
	_build_ui()
	visible = false
	Profile.profile_changed.connect(_on_profile_changed)
	Profile.meta_progress_changed.connect(_on_meta_progress_changed)
	InputRouter.input_mode_changed.connect(_on_input_mode_changed)
	InputRouter.bindings_changed.connect(_on_bindings_changed)
	_refresh_static_input_prompts()


func _unhandled_input(event: InputEvent) -> void:
	if not _open or event.is_echo():
		return
	if not _workshop_open and _is_continue_weekend_input(event):
		continue_weekend()
		get_viewport().set_input_as_handled()
		return
	if _is_workshop_toggle(event):
		toggle_workshop()
		get_viewport().set_input_as_handled()
		return
	if _workshop_open:
		if event.is_action_pressed(InputRouter.OPEN_GARAGE):
			hide_workshop()
		elif event.is_action_pressed(InputRouter.GARAGE_LEFT):
			cycle_workshop_category(-1)
		elif event.is_action_pressed(InputRouter.GARAGE_RIGHT):
			cycle_workshop_category(1)
		elif event.is_action_pressed(InputRouter.EVENT_PREVIOUS):
			cycle_workshop_item(-1)
		elif event.is_action_pressed(InputRouter.EVENT_NEXT):
			cycle_workshop_item(1)
		elif event.is_action_pressed(InputRouter.REPAIR_BIKE):
			_attempt_repair()
			_refresh_workshop()
		elif event.is_action_pressed(InputRouter.CONFIRM):
			confirm_workshop_item()
		else:
			return
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(InputRouter.GARAGE_LEFT):
		_selected_index = wrapi(_selected_index - 1, 0, SETUPS.size())
		_refresh()
		_emit_interface_feedback(&"NAVIGATE", &"GARAGE_SETUP")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(InputRouter.EVENT_PREVIOUS):
		_event_index = wrapi(_event_index - 1, 0, EVENTS.size())
		_refresh()
		_emit_interface_feedback(&"NAVIGATE", &"GARAGE_EVENT")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(InputRouter.EVENT_NEXT):
		_event_index = wrapi(_event_index + 1, 0, EVENTS.size())
		_refresh()
		_emit_interface_feedback(&"NAVIGATE", &"GARAGE_EVENT")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(InputRouter.REPAIR_BIKE):
		_attempt_repair()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(InputRouter.TOGGLE_ASSIST):
		Profile.cycle_assist_mode()
		_refresh()
		_status_label.text = "HANDLING ASSIST  //  %s" % String(Profile.assist_mode)
		_status_label.modulate = CYAN
		_emit_interface_feedback(&"CONFIRM", &"GARAGE_ASSIST")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(InputRouter.GARAGE_RIGHT):
		_selected_index = wrapi(_selected_index + 1, 0, SETUPS.size())
		_refresh()
		_emit_interface_feedback(&"NAVIGATE", &"GARAGE_SETUP")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(InputRouter.CONFIRM):
		_confirm_selection()
		get_viewport().set_input_as_handled()


func show_garage() -> void:
	_open = true
	visible = true
	_workshop_open = false
	_workshop_overlay.visible = false
	var current_index := SETUPS.find(Profile.current_setup)
	_selected_index = current_index if current_index >= 0 else 1
	_focus_continue_weekend_event()
	_refresh()


func hide_garage() -> void:
	_open = false
	_workshop_open = false
	_workshop_overlay.visible = false
	visible = false


func is_open() -> bool:
	return _open


func show_workshop() -> void:
	if not _open:
		return
	_workshop_open = true
	_workshop_overlay.visible = true
	_sync_workshop_selection()
	_workshop_status_label.text = ""
	_refresh_workshop()
	workshop_visibility_changed.emit(true)
	_emit_interface_feedback(&"CONFIRM", &"WORKSHOP_OPEN")


func hide_workshop() -> void:
	if not _workshop_open:
		return
	_workshop_open = false
	_workshop_overlay.visible = false
	workshop_visibility_changed.emit(false)
	_emit_interface_feedback(&"CANCEL", &"WORKSHOP_CLOSE")


func toggle_workshop() -> void:
	if _workshop_open:
		hide_workshop()
	else:
		show_workshop()


func is_workshop_open() -> bool:
	return _workshop_open


func cycle_workshop_category(direction: int) -> void:
	if not _workshop_open or direction == 0:
		return
	_workshop_category_index = wrapi(_workshop_category_index + signi(direction), 0, WORKSHOP_CATEGORIES.size())
	_workshop_status_label.text = ""
	_refresh_workshop()
	_emit_interface_feedback(&"NAVIGATE", &"WORKSHOP_CATEGORY")


func cycle_workshop_item(direction: int) -> void:
	if not _workshop_open or direction == 0:
		return
	var category := WORKSHOP_CATEGORIES[_workshop_category_index]
	var items := _get_workshop_items(category)
	if items.is_empty():
		_emit_interface_feedback(&"DENIED", &"WORKSHOP_ITEM")
		return
	_workshop_item_indices[category] = wrapi(int(_workshop_item_indices.get(category, 0)) + signi(direction), 0, items.size())
	_workshop_status_label.text = ""
	_refresh_workshop()
	_emit_interface_feedback(&"NAVIGATE", &"WORKSHOP_ITEM")


func confirm_workshop_item() -> bool:
	if not _workshop_open:
		return false
	var category := WORKSHOP_CATEGORIES[_workshop_category_index]
	var item := _get_selected_workshop_item(category)
	if item.is_empty():
		_set_workshop_status("NO ITEM AVAILABLE", false)
		return false
	var success := false
	match category:
		&"BIKE": success = _activate_or_purchase_bike(item)
		&"CLASS": success = _select_bike_class(item)
		&"TUNE": success = _apply_tune_preset(item)
		&"PART": success = _purchase_or_install_part(item)
		&"STYLE": success = _apply_style_preset(item)
		&"BUILD": success = _apply_saved_build_action(item)
	var item_id := _workshop_item_id(category, item)
	_refresh()
	_refresh_workshop()
	workshop_action_completed.emit(category, item_id, success)
	_emit_interface_feedback(&"CONFIRM" if success else &"DENIED", &"WORKSHOP_ACTION")
	return success


func get_workshop_snapshot() -> Dictionary:
	var category := WORKSHOP_CATEGORIES[_workshop_category_index]
	return {
		&"open": _workshop_open,
		&"category": category,
		&"category_index": _workshop_category_index,
		&"item_index": int(_workshop_item_indices.get(category, 0)),
		&"selected_item": _get_selected_workshop_item(category),
		&"active_bike_id": Profile.active_bike_id,
		&"selected_bike_class": Profile.selected_bike_class,
		&"active_setup": Profile.get_active_bike_setup_snapshot(),
		&"championship": Profile.championship_snapshot.duplicate(true),
		&"race_weekend": Profile.race_weekend_snapshot.duplicate(true),
		&"academy": Profile.get_academy_progress_snapshot(),
		&"academy_progression": get_academy_progression_snapshot(),
		&"achievements": Profile.get_achievement_progress_snapshot(),
		&"cosmetics": Profile.get_rider_cosmetics(),
		&"saved_builds": Profile.get_saved_bike_build_slots(),
		&"workshop_title": _workshop_title_label.text if _workshop_title_label != null else "",
		&"workshop_item": _workshop_item_label.text if _workshop_item_label != null else "",
		&"workshop_detail": _workshop_detail_label.text if _workshop_detail_label != null else "",
		&"workshop_build": _workshop_build_label.text if _workshop_build_label != null else "",
		&"workshop_action": _workshop_action_label.text if _workshop_action_label != null else "",
		&"workshop_status": _workshop_status_label.text if _workshop_status_label != null else "",
	}


func get_input_prompt_snapshot() -> Dictionary:
	return {
		&"input_mode": InputRouter.input_mode,
		&"binding_revision": InputRouter.binding_revision,
		&"setup_left": _setup_left_hint.text if _setup_left_hint != null else "",
		&"setup_right": _setup_right_hint.text if _setup_right_hint != null else "",
		&"status": _status_label.text if _status_label != null else "",
		&"repair": _repair_label.text if _repair_label != null else "",
		&"weekend_action": _weekend_action_label.text if _weekend_action_label != null else "",
		&"workshop_hint": _workshop_hint_label.text if _workshop_hint_label != null else "",
		&"workshop_controls": _workshop_controls_label.text if _workshop_controls_label != null else "",
		&"workshop_action": _workshop_action_label.text if _workshop_action_label != null else "",
	}


func get_progression_presentation_snapshot() -> Dictionary:
	return {
		&"first_run_path": _is_pristine_first_run_context(),
		&"context": _garage_context_label.text if _garage_context_label != null else "",
		&"summary": _workshop_meta_label.text if _workshop_meta_label != null else "",
	}


func get_event_strategy_presentation_snapshot() -> Dictionary:
	var activity := EVENTS[_event_index] if _event_index >= 0 and _event_index < EVENTS.size() else INITIAL_EVENT
	var selected_setup := SETUPS[_selected_index] if _selected_index >= 0 and _selected_index < SETUPS.size() else &"BALANCED"
	var active_tune := _active_tune_id()
	var snapshot := _event_strategy_fit(activity, selected_setup, active_tune)
	snapshot[&"label"] = _strategy_label.text if _strategy_label != null else ""
	return snapshot


func _event_strategy_fit(activity: StringName, setup_id: StringName, tune_id: StringName) -> Dictionary:
	var strategy := RaceEventCatalog.get_event_strategy(activity)
	var event_data := RaceEventCatalog.get_event(activity)
	var recommended_setup := StringName(strategy.get(&"setup_id", &"BALANCED"))
	var recommended_tune := StringName(strategy.get(&"tune_id", &"BALANCED"))
	var setup_match := setup_id == recommended_setup
	var tune_match := tune_id == recommended_tune
	var purchase: Dictionary = Profile.get_setup_purchase_snapshot(recommended_setup)
	var setup_owned := bool(purchase.get(&"owned", false))
	var fit_status := "FULL PLAN MATCH"
	if setup_match and tune_match and not setup_owned:
		fit_status = "PLAN CONFIGURED  //  KIT NOT OWNED"
	elif setup_match and not tune_match:
		fit_status = "KIT MATCH  //  TRY TUNE %s" % String(recommended_tune).replace("_", " ")
	elif tune_match and not setup_match:
		fit_status = "TUNE MATCH  //  TRY KIT %s" % String(recommended_setup).replace("_", " ")
	elif not setup_match and not tune_match:
		fit_status = "ALTERNATE  //  PLAN KIT %s + TUNE %s" % [
			String(recommended_setup).replace("_", " "), String(recommended_tune).replace("_", " "),
		]
	return {
		&"event_id": activity,
		&"event_name": str(event_data.get(&"display_name", String(activity))).to_upper(),
		&"recommended_setup": recommended_setup,
		&"recommended_tune": recommended_tune,
		&"selected_setup": setup_id,
		&"active_tune": tune_id,
		&"setup_match": setup_match,
		&"tune_match": tune_match,
		&"full_match": setup_match and tune_match,
		&"ready_to_ride": setup_owned and setup_match and tune_match,
		&"recommended_setup_owned": setup_owned,
		&"recommended_setup_price": int(purchase.get(&"price", 0)),
		&"recommended_setup_affordable": bool(purchase.get(&"affordable", false)),
		&"recommended_setup_shortfall": int(purchase.get(&"shortfall", 0)),
		&"fit_status": fit_status,
		&"focus": str(strategy.get(&"focus", "READABLE PACE")),
		&"why": str(strategy.get(&"why", "")),
		&"challenge_rule": bool(strategy.get(&"challenge_rule", false)),
	}


func bind_competition_source(source: Object) -> void:
	## RaceServices remains the authority for the local board and last replay. The
	## Garage only projects that data and stays usable in isolated/headless tests.
	_competition_source = source
	if _open:
		_refresh_event()


func update_competition_context(
	activity: StringName,
	ghost_best_usec: int = -1,
	competition_id: StringName = &""
) -> void:
	## GhostController exposes the record currently loaded by RaceController. Bind
	## it to its event so browsing another card never claims a ghost that may not
	## exist for that selected ruleset.
	_active_competition_event = activity
	_active_competition_id = competition_id
	_active_ghost_best_usec = ghost_best_usec
	if _open:
		_refresh_event()


func focus_event_briefing(activity: StringName) -> bool:
	var index := EVENTS.find(activity)
	if index < 0:
		return false
	_event_index = index
	if _open:
		_refresh()
	return true


func get_event_briefing_presentation_snapshot() -> Dictionary:
	var selected_event := EVENTS[_event_index] if _event_index >= 0 and _event_index < EVENTS.size() else &""
	return {
		&"event_id": selected_event,
		&"visible": _event_competition_label != null and _event_competition_label.visible,
		&"text": _event_competition_label.text if _event_competition_label != null else "",
		&"event_meta": _event_meta_label.text if _event_meta_label != null else "",
		&"competition": get_event_competition_snapshot(selected_event) if not selected_event.is_empty() else {},
	}


func get_event_competition_snapshot(activity: StringName) -> Dictionary:
	## Data-only production briefing composed from existing local authorities.
	var session := _competition_session(activity)
	var signature := _competition_signature(session)
	var challenge_id := _session_challenge_id(session)
	var competition_id := _session_competition_id(session)
	var is_challenge := not challenge_id.is_empty()
	var board: Dictionary = {}
	if _competition_source != null and not signature.is_empty() and _competition_source.has_method(&"get_local_board"):
		var board_value: Variant = _competition_source.call(&"get_local_board", signature, 8)
		if board_value is Dictionary:
			board = (board_value as Dictionary).duplicate(true)
	var profile_id := "local_player"
	if Profile.has_method(&"get_profile_id"):
		profile_id = str(Profile.call(&"get_profile_id"))
	var personal_entry: Dictionary = {}
	var entries_value: Variant = board.get("entries", [])
	if entries_value is Array:
		for raw_entry: Variant in entries_value:
			if raw_entry is Dictionary and str((raw_entry as Dictionary).get("profile_id", "")) == profile_id:
				personal_entry = (raw_entry as Dictionary).duplicate(true)
				break
	var summary: Dictionary = {}
	if Profile.has_method(&"get_leaderboard_summary") and not signature.is_empty():
		summary = Profile.call(&"get_leaderboard_summary", signature) as Dictionary
	var event_record: Dictionary = Profile.get_event_record(activity, challenge_id) if Profile.has_method(&"get_event_record") else {}
	var exact_best_usec := _entry_effective_time_usec(personal_entry)
	if exact_best_usec < 0:
		exact_best_usec = int(summary.get(&"time_usec", -1))
	var event_best_usec := -1 if is_challenge else int(event_record.get(&"best_time_usec", -1))
	var personal_best_usec := exact_best_usec if exact_best_usec >= 0 else event_best_usec
	var local_rank := int(personal_entry.get("rank", summary.get(&"rank", 0)))
	var competition_snapshot: Dictionary = {}
	if _competition_source != null and _competition_source.has_method(&"get_competitive_snapshot"):
		var source_snapshot: Variant = _competition_source.call(&"get_competitive_snapshot")
		if source_snapshot is Dictionary:
			competition_snapshot = (source_snapshot as Dictionary).duplicate(true)
	var last_result_value: Variant = competition_snapshot.get(&"last_result", {})
	var last_result: Dictionary = (last_result_value as Dictionary).duplicate(true) if last_result_value is Dictionary else {}
	var replay_identity_matches := (
		StringName(last_result.get(&"event_id", &"")) == activity
		and (
			not is_challenge
			or StringName(last_result.get(&"competition_id", &"")) == competition_id
		)
	)
	var replay_available := (
		bool(competition_snapshot.get(&"replay_available", false))
		and replay_identity_matches
	)
	var ghost_identity_matches := (
		activity == _active_competition_event
		and (
			not is_challenge
			or (not competition_id.is_empty() and competition_id == _active_competition_id)
		)
	)
	var championship := _championship_briefing(activity)
	var rival := _rival_briefing(activity, session, championship.get(&"standings", []) as Array)
	return {
		&"event_id": activity,
		&"challenge_id": challenge_id,
		&"competition_id": competition_id,
		&"run_signature": signature,
		&"medal_times_usec": session.medal_times_usec.duplicate(true) if session != null else {},
		&"local_board_total": maxi(int(board.get("total", 0)), 0),
		&"local_rank": maxi(local_rank, 0),
		&"personal_best_usec": personal_best_usec,
		&"exact_rules_best": exact_best_usec >= 0,
		&"personal_best": bool(summary.get(&"personal_best", false)),
		&"ghost_available": ghost_identity_matches and _active_ghost_best_usec >= 0,
		&"ghost_best_usec": _active_ghost_best_usec if ghost_identity_matches else -1,
		&"replay_available": replay_available,
		&"championship": championship,
		&"rival": rival,
	}


func get_academy_progression_snapshot() -> Dictionary:
	## Public Garage projection of the same authority that composes the session.
	## Keeping this query data-only makes progression easy to verify headlessly.
	var catalog: Variant = ACADEMY_CATALOG_SCRIPT.create_default()
	var lessons: Array[Dictionary] = catalog.get_lessons()
	var progress := Profile.get_academy_progress_snapshot()
	var completed := Profile.get_completed_academy_lessons()
	var active_lesson := RaceEventCatalog.get_active_academy_lesson()
	var active_id := StringName(active_lesson.get(&"lesson_id", &""))
	var override_id := RaceEventCatalog.get_academy_lesson_override()
	var all_complete := completed.size() >= lessons.size() and not lessons.is_empty()
	var mode := &"NEXT"
	if not override_id.is_empty():
		mode = &"REMATCH"
	elif all_complete:
		mode = &"REPLAY"
	elif int(progress.get(active_id, 0)) > 0:
		mode = &"PRACTICE"
	var total_stars := 0
	for raw_stars: Variant in progress.values():
		total_stars += clampi(int(raw_stars), 0, 3)
	return {
		&"active_lesson_id": active_id,
		&"active_lesson_name": str(active_lesson.get(&"display_name", active_id)),
		&"active_lesson": active_lesson.duplicate(true),
		&"mode": mode,
		&"completed": completed.size(),
		&"total": lessons.size(),
		&"stars": total_stars,
		&"all_complete": all_complete,
	}


func get_continue_weekend_snapshot() -> Dictionary:
	var championship: Variant = Profile.get_championship_service()
	if championship != null and championship.is_complete():
		return {
			&"phase": &"SEASON_COMPLETE",
			&"activity": &"",
			&"available": true,
			&"complete": true,
			&"start_next_season": true,
			&"action_text": "%s  START SEASON %d" % [_any_action_label(InputRouter.CONTINUE_WEEKEND), championship.season_number + 1],
		}
	var weekend: Variant = Profile.get_race_weekend_director()
	if weekend == null:
		return {}
	var phase := StringName(weekend.get_current_phase())
	var activity := RaceEventCatalog.get_weekend_event(phase)
	if activity.is_empty():
		return {
			&"weekend_id": StringName(weekend.weekend_id),
			&"phase": phase,
			&"activity": &"",
			&"available": false,
			&"complete": phase == &"RESULTS",
			&"action_text": "RED MESA WEEKEND COMPLETE" if phase == &"RESULTS" else "",
		}
	var pristine_first_run_weekend: bool = (
		_is_pristine_first_run_context()
		and phase == &"PRACTICE"
		and weekend.session_results.is_empty()
	)
	var available: bool = _is_event_unlocked(activity) and not pristine_first_run_weekend
	return {
		&"weekend_id": StringName(weekend.weekend_id),
		&"phase": phase,
		&"activity": activity,
		&"available": available,
		&"complete": false,
		# Never advertise a shortcut that the same screen will reject. First-run
		# riders start with event 1; the weekend remains visible as future context.
		&"action_text": (
			"%s  CONTINUE %s  //  %s" % [
				_any_action_label(InputRouter.CONTINUE_WEEKEND),
				str(weekend.display_name).to_upper(),
				String(phase),
			]
			if available else ""
		),
	}


func get_setup_runtime_snapshot(setup: StringName) -> Dictionary:
	var active: Dictionary = Profile.get_active_bike_setup_snapshot()
	var build := active.get(&"build", {}) as Dictionary
	return BIKE_BUILD_SCRIPT.runtime_projection(
		setup,
		active.get(&"stats", {}) as Dictionary,
		Profile.bike_condition,
		build.get(&"tune", {}) as Dictionary
	)


func continue_weekend() -> bool:
	if not _open or _workshop_open:
		return false
	var action := get_continue_weekend_snapshot()
	if bool(action.get(&"start_next_season", false)):
		if not Profile.start_next_championship_season():
			_status_label.text = "SEASON COULD NOT BE STARTED"
			_status_label.modulate = Color("ff6f5e")
			_emit_interface_feedback(&"DENIED", &"WEEKEND_CONTINUE")
			return false
		_focus_continue_weekend_event()
		_refresh()
		var championship: Variant = Profile.get_championship_service()
		_status_label.text = "DIRT TOUR SEASON %d READY" % int(championship.season_number)
		_status_label.modulate = CYAN
		_emit_interface_feedback(&"CONFIRM", &"WEEKEND_CONTINUE")
		return true
	var activity := StringName(action.get(&"activity", &""))
	if activity.is_empty():
		_status_label.text = "RED MESA WEEKEND COMPLETE" if bool(action.get(&"complete", false)) else "NO ACTIVE WEEKEND SESSION"
		_status_label.modulate = CYAN
		_emit_interface_feedback(&"DENIED", &"WEEKEND_CONTINUE")
		return false
	if not bool(action.get(&"available", false)):
		_status_label.text = "WEEKEND LOCKED  //  %s" % _event_unlock_hint(activity)
		_status_label.modulate = Color("ff6f5e")
		_emit_interface_feedback(&"DENIED", &"WEEKEND_CONTINUE")
		return false
	var setup := SETUPS[_selected_index]
	if not Profile.is_setup_unlocked(setup):
		_status_label.text = "INSTALL THIS KIT BEFORE CONTINUING THE WEEKEND"
		_status_label.modulate = Color("ff6f5e")
		_emit_interface_feedback(&"DENIED", &"WEEKEND_CONTINUE")
		return false
	Profile.set_current_setup(setup)
	_event_index = maxi(EVENTS.find(activity), 0)
	hide_garage()
	_emit_interface_feedback(&"CONFIRM", &"WEEKEND_CONTINUE")
	ride_requested.emit(setup, activity)
	return true


func _confirm_selection() -> void:
	var setup := SETUPS[_selected_index]
	if not Profile.is_setup_unlocked(setup):
		if not Profile.purchase_setup(setup):
			_status_label.text = "NOT ENOUGH CASH — WIN MEDALS TO FUND THE BUILD"
			_status_label.modulate = Color("ff6f5e")
			_emit_interface_feedback(&"DENIED", &"GARAGE_CONFIRM")
			return
		_status_label.text = "KIT INSTALLED — PRESS CONFIRM TO RIDE"
		_status_label.modulate = CYAN
		_refresh()
		_emit_interface_feedback(&"CONFIRM", &"GARAGE_PURCHASE")
		return
	var activity := EVENTS[_event_index]
	if not _is_event_unlocked(activity):
		_status_label.text = _event_unlock_hint(activity)
		_status_label.modulate = Color("ff6f5e")
		_emit_interface_feedback(&"DENIED", &"GARAGE_CONFIRM")
		return
	Profile.set_current_setup(setup)
	hide_garage()
	_emit_interface_feedback(&"CONFIRM", &"GARAGE_RIDE")
	ride_requested.emit(setup, activity)


func _build_ui() -> void:
	_root = Control.new()
	_root.name = "GarageRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var blackout := ColorRect.new()
	# The race HUD is hidden while the Garage is open, so the lightweight lit bike
	# preview can remain visible without sacrificing copy contrast.
	# Keep the controls readable while allowing the lit bike to function as the
	# Garage's visual hero instead of disappearing behind an opaque menu wall.
	blackout.color = Color(0.015, 0.02, 0.025, 0.60)
	blackout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(blackout)

	var amber_stripe := ColorRect.new()
	amber_stripe.color = AMBER
	_anchor_rect(amber_stripe, Vector2.ZERO, Rect2(0.0, 0.0, 18.0, 900.0))
	_root.add_child(amber_stripe)

	var title := _label("THE GARAGE", 58, CREAM)
	_anchor_rect(title, Vector2.ZERO, Rect2(82.0, 60.0, 620.0, 80.0))
	_root.add_child(title)
	_garage_context_label = _label("", 19, AMBER)
	_garage_context_label.name = "GarageContext"
	_garage_context_label.clip_text = true
	_garage_context_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_anchor_rect(_garage_context_label, Vector2.ZERO, Rect2(88.0, 137.0, 610.0, 40.0))
	_root.add_child(_garage_context_label)
	var build_label := _label("PACKAGE %s  //  TRACK-AUTHORITY" % _build_id().to_upper(), 13, CYAN)
	build_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_anchor_rect(build_label, Vector2(1.0, 1.0), Rect2(-470.0, -42.0, 390.0, 24.0))
	_root.add_child(build_label)

	_profile_label = _label("", 22, Color("b9c7cf"))
	_profile_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_anchor_rect(_profile_label, Vector2(1.0, 0.0), Rect2(-540.0, 82.0, 460.0, 48.0))
	_root.add_child(_profile_label)
	_event_label = _label("", 20, AMBER)
	_event_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_event_label.clip_text = true
	_event_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_anchor_rect(_event_label, Vector2(1.0, 0.0), Rect2(-900.0, 132.0, 820.0, 34.0))
	_root.add_child(_event_label)
	_event_description = _label("", 15, Color("9dadb6"))
	_event_description.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_anchor_rect(_event_description, Vector2(1.0, 0.0), Rect2(-840.0, 162.0, 760.0, 30.0))
	_root.add_child(_event_description)
	_event_meta_label = _label("", 13, CYAN)
	_event_meta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_anchor_rect(_event_meta_label, Vector2(1.0, 0.0), Rect2(-840.0, 190.0, 760.0, 28.0))
	_root.add_child(_event_meta_label)
	_event_competition_label = _label("", 11, CREAM)
	_event_competition_label.name = "EventCompetitionBriefing"
	_event_competition_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_event_competition_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_event_competition_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_event_competition_label.clip_text = true
	_event_competition_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_anchor_rect(_event_competition_label, Vector2(1.0, 0.0), Rect2(-840.0, 222.0, 590.0, 38.0))
	_root.add_child(_event_competition_label)
	_repair_label = _label("", 15, Color("9dadb6"))
	_anchor_rect(_repair_label, Vector2.ZERO, Rect2(88.0, 175.0, 620.0, 32.0))
	_root.add_child(_repair_label)
	_tour_label = _label("", 13, CREAM)
	_anchor_rect(_tour_label, Vector2.ZERO, Rect2(88.0, 202.0, 370.0, 28.0))
	_root.add_child(_tour_label)
	_weekend_action_label = _label("", 15, CYAN)
	_weekend_action_label.name = "ContinueWeekendAction"
	_weekend_action_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# The top briefing already carries competition and event context. Keep the
	# weekend CTA in the clear action band beneath the setup card so it never
	# collides with the setup title at laptop resolutions.
	_anchor_rect(_weekend_action_label, Vector2(0.5, 1.0), Rect2(-420.0, -188.0, 840.0, 30.0))
	_root.add_child(_weekend_action_label)
	_event_accent = ColorRect.new()
	_event_accent.color = AMBER
	_anchor_rect(_event_accent, Vector2(1.0, 0.0), Rect2(-840.0, 216.0, 760.0, 4.0))
	_root.add_child(_event_accent)
	for index: int in EVENTS.size():
		var marker := _label("%02d" % (index + 1), 13, Color("52616a"))
		marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_anchor_rect(marker, Vector2.ZERO, Rect2(88.0 + index * 34.0, 222.0, 28.0, 28.0))
		_root.add_child(marker)
		_event_markers.append(marker)

	var card := ColorRect.new()
	var card_color := DARK
	card_color.a = 0.82
	card.color = card_color
	# Reserve the left third for the bike hero. The chase camera composes the
	# stationary bike into that opening while all setup data stays in one compact
	# right-hand decision surface.
	_anchor_rect(card, Vector2(0.5, 0.5), Rect2(-260.0, -235.0, 820.0, 470.0))
	_root.add_child(card)

	_setup_left_hint = _label("", 18, Color("7e919d"))
	_anchor_rect(_setup_left_hint, Vector2(0.5, 0.5), Rect2(-220.0, -195.0, 160.0, 40.0))
	_root.add_child(_setup_left_hint)
	_setup_right_hint = _label("", 18, Color("7e919d"))
	_setup_right_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_anchor_rect(_setup_right_hint, Vector2(0.5, 0.5), Rect2(360.0, -195.0, 160.0, 40.0))
	_root.add_child(_setup_right_hint)

	_setup_name = _label("BALANCED", 52, AMBER)
	_setup_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_anchor_rect(_setup_name, Vector2(0.5, 0.5), Rect2(-110.0, -200.0, 600.0, 70.0))
	_root.add_child(_setup_name)
	_tagline = _label("", 22, CREAM)
	_tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_anchor_rect(_tagline, Vector2(0.5, 0.5), Rect2(-290.0, -132.0, 800.0, 46.0))
	_root.add_child(_tagline)
	_description = _label("", 18, Color("aab9c2"))
	_description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_anchor_rect(_description, Vector2(0.5, 0.5), Rect2(-290.0, -82.0, 800.0, 52.0))
	_root.add_child(_description)
	_strategy_label = _label("", 15, CYAN)
	_strategy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_strategy_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_anchor_rect(_strategy_label, Vector2(0.5, 0.5), Rect2(-290.0, -28.0, 800.0, 26.0))
	_root.add_child(_strategy_label)

	var stat_names: Array[StringName] = [&"POWER", &"GRIP", &"SUSPENSION", &"TOP SPEED"]
	for index: int in stat_names.size():
		var stat_name := stat_names[index]
		var label := _label(String(stat_name), 16, Color("8fa0aa"))
		_anchor_rect(label, Vector2(0.5, 0.5), Rect2(-200.0, 5.0 + index * 46.0, 150.0, 28.0))
		_root.add_child(label)
		var bar := ProgressBar.new()
		bar.min_value = 0.0
		bar.max_value = 10.0
		bar.show_percentage = false
		var background := StyleBoxFlat.new()
		background.bg_color = Color("202b32")
		background.corner_radius_top_left = 5
		background.corner_radius_top_right = 5
		background.corner_radius_bottom_left = 5
		background.corner_radius_bottom_right = 5
		var fill := StyleBoxFlat.new()
		fill.bg_color = AMBER
		fill.corner_radius_top_left = 5
		fill.corner_radius_top_right = 5
		fill.corner_radius_bottom_left = 5
		fill.corner_radius_bottom_right = 5
		bar.add_theme_stylebox_override(&"background", background)
		bar.add_theme_stylebox_override(&"fill", fill)
		_anchor_rect(bar, Vector2(0.5, 0.5), Rect2(-40.0, 8.0 + index * 46.0, 560.0, 19.0))
		_root.add_child(bar)
		_bars[stat_name] = bar

	_price_label = _label("", 24, CREAM)
	_price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_anchor_rect(_price_label, Vector2(0.5, 1.0), Rect2(-360.0, -150.0, 720.0, 44.0))
	_root.add_child(_price_label)
	_status_label = _label("", 17, Color("9dadb6"))
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_anchor_rect(_status_label, Vector2(0.5, 1.0), Rect2(-520.0, -102.0, 1040.0, 42.0))
	_root.add_child(_status_label)
	_root.move_child(_tour_label, _root.get_child_count() - 1)
	_root.move_child(_weekend_action_label, _root.get_child_count() - 1)
	_root.move_child(_event_accent, _root.get_child_count() - 1)
	_root.move_child(_event_competition_label, _root.get_child_count() - 1)
	for marker: Label in _event_markers:
		_root.move_child(marker, _root.get_child_count() - 1)
	_build_workshop_summary()
	_build_workshop_overlay()


func _build_workshop_summary() -> void:
	_workshop_summary_panel = PanelContainer.new()
	_workshop_summary_panel.name = "WorkshopSummary"
	_workshop_summary_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_workshop_summary_panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_workshop_summary_panel.gui_input.connect(_on_workshop_summary_gui_input)
	_workshop_summary_panel.mouse_entered.connect(_set_workshop_summary_hovered.bind(true))
	_workshop_summary_panel.mouse_exited.connect(_set_workshop_summary_hovered.bind(false))
	_set_workshop_summary_hovered(false)
	_anchor_rect(_workshop_summary_panel, Vector2(1.0, 0.0), Rect2(-228.0, 252.0, 200.0, 420.0))
	_root.add_child(_workshop_summary_panel)
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override(&"margin_left", 12)
	margin.add_theme_constant_override(&"margin_right", 12)
	margin.add_theme_constant_override(&"margin_top", 12)
	margin.add_theme_constant_override(&"margin_bottom", 12)
	_workshop_summary_panel.add_child(margin)
	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override(&"separation", 8)
	margin.add_child(stack)
	var title := _label("WORKSHOP", 20, AMBER)
	stack.add_child(title)
	_workshop_hint_label = _label("", 13, CYAN)
	stack.add_child(_workshop_hint_label)
	_workshop_summary_label = _label("", 13, CREAM)
	_workshop_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_workshop_summary_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(_workshop_summary_label)
	_workshop_meta_label = _label("", 12, Color("9dadb6"))
	_workshop_meta_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_workshop_meta_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(_workshop_meta_label)


func _build_workshop_overlay() -> void:
	_workshop_overlay = PanelContainer.new()
	_workshop_overlay.name = "WorkshopPanel"
	_workshop_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_workshop_overlay.add_theme_stylebox_override(&"panel", _panel_style(Color(0.018, 0.026, 0.032, 0.985), AMBER, 3))
	_anchor_rect(_workshop_overlay, Vector2(0.5, 0.5), Rect2(-550.0, -225.0, 1100.0, 450.0))
	_root.add_child(_workshop_overlay)
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override(&"margin_left", 34)
	margin.add_theme_constant_override(&"margin_right", 34)
	margin.add_theme_constant_override(&"margin_top", 24)
	margin.add_theme_constant_override(&"margin_bottom", 22)
	_workshop_overlay.add_child(margin)
	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override(&"separation", 7)
	margin.add_child(stack)
	_workshop_title_label = _label("RACE WORKSHOP", 18, CYAN)
	_workshop_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(_workshop_title_label)
	_workshop_tabs_label = _label("", 16, CREAM)
	_workshop_tabs_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(_workshop_tabs_label)
	_workshop_item_label = _label("", 38, AMBER)
	_workshop_item_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_workshop_item_label.custom_minimum_size.y = 52.0
	stack.add_child(_workshop_item_label)
	_workshop_detail_label = _label("", 17, Color("b9c7cf"))
	_workshop_detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_workshop_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_workshop_detail_label.custom_minimum_size.y = 58.0
	stack.add_child(_workshop_detail_label)
	_workshop_build_label = _label("", 15, CREAM)
	_workshop_build_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_workshop_build_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_workshop_build_label.custom_minimum_size.y = 58.0
	stack.add_child(_workshop_build_label)
	_workshop_action_label = _label("", 18, CYAN)
	_workshop_action_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(_workshop_action_label)
	_workshop_status_label = _label("", 15, Color("9dadb6"))
	_workshop_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_workshop_status_label.custom_minimum_size.y = 25.0
	stack.add_child(_workshop_status_label)
	_workshop_controls_label = _label("", 13, Color("8fa0aa"))
	_workshop_controls_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(_workshop_controls_label)
	_workshop_overlay.visible = false


func _panel_style(background: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = 7
	style.corner_radius_top_right = 7
	style.corner_radius_bottom_left = 7
	style.corner_radius_bottom_right = 7
	return style


func _refresh() -> void:
	var setup := SETUPS[_selected_index]
	var data := _setup_data(setup)
	var runtime := get_setup_runtime_snapshot(setup)
	_setup_name.text = str(data.get(&"name", setup))
	_tagline.text = str(data.get(&"tagline", ""))
	_description.text = "%s\nLIVE  %dN DRIVE  //  %d GRIP  //  %.1f M/S" % [
		str(data.get(&"description", "")),
		roundi(float(runtime.get(&"engine_force", 0.0))),
		roundi(float(runtime.get(&"lateral_grip", 0.0))),
		float(runtime.get(&"maximum_speed_mps", 0.0)),
	]
	_bars[&"POWER"].value = clampf(inverse_lerp(850.0, 1750.0, float(runtime.get(&"engine_force", 0.0))) * 10.0, 0.0, 10.0)
	_bars[&"GRIP"].value = clampf(inverse_lerp(450.0, 850.0, float(runtime.get(&"lateral_grip", 0.0))) * 10.0, 0.0, 10.0)
	_bars[&"SUSPENSION"].value = clampf(inverse_lerp(16_000.0, 24_000.0, float(runtime.get(&"spring_stiffness", 0.0))) * 10.0, 0.0, 10.0)
	_bars[&"TOP SPEED"].value = clampf(inverse_lerp(23.0, 43.0, float(runtime.get(&"maximum_speed_mps", 0.0))) * 10.0, 0.0, 10.0)
	_refresh_event_strategy()
	_profile_label.text = "$%06d     RACER REP  %04d" % [Profile.cash, Profile.racer_reputation]
	if Profile.is_setup_unlocked(setup):
		_price_label.text = "INSTALLED" if setup == Profile.current_setup else "OWNED"
		_price_label.modulate = CYAN
		_status_label.text = "%s EVENT   •   %s SETUP   •   %s WORKSHOP   •   %s ASSIST   •   %s RIDE" % [
			_any_action_pair_label(InputRouter.EVENT_PREVIOUS, InputRouter.EVENT_NEXT),
			_any_action_pair_label(InputRouter.GARAGE_LEFT, InputRouter.GARAGE_RIGHT),
			_any_action_label(InputRouter.OPEN_WORKSHOP),
			_any_action_label(InputRouter.TOGGLE_ASSIST),
			_any_action_label(InputRouter.CONFIRM),
		]
		_status_label.modulate = Color("9dadb6")
	else:
		_price_label.text = "$%d TO INSTALL" % Profile.get_setup_price(setup)
		_price_label.modulate = AMBER
		_status_label.text = "%s EVENT   •   %s WORKSHOP   •   %s PURCHASE KIT" % [
			_any_action_pair_label(InputRouter.EVENT_PREVIOUS, InputRouter.EVENT_NEXT),
			_any_action_label(InputRouter.OPEN_WORKSHOP),
			_any_action_label(InputRouter.CONFIRM),
		]
		_status_label.modulate = Color("9dadb6")
	_refresh_event()
	_refresh_weekend_action()
	var repair_price := Profile.get_repair_price()
	var condition_text := "READY" if repair_price <= 0 else "%s REPAIR $%d" % [_any_action_label(InputRouter.REPAIR_BIKE), repair_price]
	_repair_label.text = "BIKE %03d%%  •  %s  •  ASSIST %s  •  STYLE TOKENS %02d" % [Profile.bike_condition, condition_text, String(Profile.assist_mode), Profile.style_tokens]
	_refresh_workshop_summary()
	if _workshop_open:
		_refresh_workshop()


func _refresh_workshop_summary() -> void:
	if _workshop_summary_label == null or _bike_catalog == null:
		return
	var setup: Dictionary = Profile.get_active_bike_setup_snapshot()
	var build: Dictionary = setup.get(&"build", {}) as Dictionary
	var stats: Dictionary = setup.get(&"stats", {}) as Dictionary
	var bike_definition: Dictionary = _bike_catalog.get_bike(Profile.active_bike_id)
	var class_definition: Variant = _bike_catalog.get_class_definition(Profile.selected_bike_class)
	var selected_class_name := String(Profile.selected_bike_class)
	if class_definition != null:
		var class_data: Dictionary = class_definition.to_dictionary()
		selected_class_name = str(class_data.get(&"display_name", selected_class_name))
	var installed_parts: Dictionary = build.get(&"installed_parts", {}) as Dictionary
	var part_tokens := PackedStringArray()
	for slot: StringName in PART_SLOTS:
		var installed_id := StringName(installed_parts.get(slot, &""))
		if installed_id.is_empty():
			continue
		var part_definition: Dictionary = _bike_catalog.get_part(installed_id)
		part_tokens.append("%s: %s" % [String(slot).left(4), str(part_definition.get(&"display_name", installed_id))])
	var build_summary := "STOCK" if part_tokens.is_empty() else " / ".join(part_tokens)
	var condition := clampi(roundi(float(build.get(&"condition", float(Profile.bike_condition) / 100.0)) * 100.0), 0, 100)
	var runtime := get_setup_runtime_snapshot(Profile.current_setup)
	_workshop_summary_label.text = "%s\n%s  //  %dcc\nCLASS  %s\nBUILD  %s\nTUNE  %s\nCONDITION  %d%%\nOVERALL %02d  //  LIVE %dN  //  %.1fM/S" % [
		str(bike_definition.get(&"manufacturer", "REDLINE")).to_upper(),
		str(bike_definition.get(&"display_name", String(Profile.active_bike_id))).to_upper(),
		int(bike_definition.get(&"displacement_cc", 0)), selected_class_name.to_upper(),
		build_summary.to_upper(), _active_tune_name().to_upper(), condition,
		int(round(float(stats.get(&"overall", 0.0)))),
		roundi(float(runtime.get(&"engine_force", 0.0))),
		float(runtime.get(&"maximum_speed_mps", 0.0)),
	]

	var first_run_path: bool = _is_pristine_first_run_context()
	var championship: Variant = Profile.get_championship_service()
	var championship_text := "DIRT TOUR  //  NOT STARTED"
	if first_run_path:
		championship_text = "FIRST ROUTE\nQUARRY TRAIL  //  EVENT 01\nFINISH FOR REP + A PB"
	elif championship != null:
		var calendar: Array[Dictionary] = championship.get_calendar()
		var next_round: Dictionary = championship.get_next_round()
		var player_standing := "UNRANKED"
		var standings: Array[Dictionary] = championship.get_standings()
		for standing: Dictionary in standings:
			if StringName(standing.get(&"rider_id", &"")) == &"PLAYER":
				player_standing = "P%d / %dPTS" % [int(standing.get(&"championship_position", 0)), int(standing.get(&"points", 0))]
				break
		championship_text = "DIRT TOUR S%02d  %d/%d\n%s\nNEXT  %s" % [
			int(championship.season_number), championship.completed_round_count(), calendar.size(), player_standing,
			str(next_round.get(&"display_name", "SEASON COMPLETE")).to_upper(),
		]

	var weekend_text := "WEEKEND  //  NOT ENTERED"
	var weekend: Variant = Profile.get_race_weekend_director()
	if first_run_path:
		weekend_text = "TOUR PATH\nCLEAR 2 QUARRY EVENTS\nPINE, THEN RED MESA"
	elif weekend != null:
		weekend_text = "%s\nPHASE  %s  //  %d%%" % [
			str(weekend.display_name).to_upper(), String(weekend.get_current_phase()),
			int(round(weekend.get_progress_ratio() * 100.0)),
		]

	var academy := get_academy_progression_snapshot()
	var academy_mode := String(academy.get(&"mode", &"NEXT"))
	var academy_lesson := str(academy.get(&"active_lesson_name", "NO LESSON AVAILABLE")).to_upper()
	var milestones: Dictionary = Profile.get_achievement_progress_snapshot()
	var next_milestone: Dictionary = milestones.get(&"next", {}) as Dictionary
	var milestone_detail := "ALL MILESTONES COMPLETE"
	if not next_milestone.is_empty():
		milestone_detail = "NEXT  %s  %d/%d" % [
			str(next_milestone.get(&"title", "MILESTONE")).to_upper(),
			int(next_milestone.get(&"current", 0)),
			int(next_milestone.get(&"target", 1)),
		]
	_workshop_meta_label.text = "%s\n\n%s\n\nACADEMY  %d/%d  //  STARS %02d\n%s  %s\n\nMILESTONES  %d/%d\n%s" % [
		championship_text, weekend_text,
		int(academy.get(&"completed", 0)), int(academy.get(&"total", 0)), int(academy.get(&"stars", 0)),
		academy_mode, academy_lesson,
		int(milestones.get(&"unlocked", 0)), int(milestones.get(&"total", 0)), milestone_detail,
	]


func _on_workshop_summary_gui_input(event: InputEvent) -> void:
	var mouse_event := event as InputEventMouseButton
	if mouse_event == null or mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed:
		return
	show_workshop()
	_workshop_summary_panel.accept_event()


func _set_workshop_summary_hovered(hovered: bool) -> void:
	if _workshop_summary_panel == null:
		return
	_workshop_summary_panel.add_theme_stylebox_override(
		&"panel",
		_panel_style(
			Color(0.022, 0.035, 0.042, 0.97) if hovered else Color(0.018, 0.026, 0.032, 0.93),
			CYAN if hovered else Color("6d7d85"),
			2 if hovered else 1
		)
	)


func _refresh_workshop() -> void:
	if not _workshop_open:
		return
	var category := WORKSHOP_CATEGORIES[_workshop_category_index]
	var items := _get_workshop_items(category)
	var selected_index := clampi(int(_workshop_item_indices.get(category, 0)), 0, maxi(items.size() - 1, 0))
	_workshop_item_indices[category] = selected_index
	var tab_tokens := PackedStringArray()
	for tab: StringName in WORKSHOP_CATEGORIES:
		tab_tokens.append("[%s]" % String(tab) if tab == category else String(tab))
	_workshop_tabs_label.text = "     ".join(tab_tokens)
	if items.is_empty():
		_workshop_item_label.text = "NO ITEMS"
		_workshop_detail_label.text = "Nothing is available for the active bike and profile."
		_workshop_build_label.text = ""
		_workshop_action_label.text = "%s  CHANGE CATEGORY" % _any_action_pair_label(InputRouter.GARAGE_LEFT, InputRouter.GARAGE_RIGHT)
		return
	var item := items[selected_index]
	var projection := _workshop_item_projection(category, item)
	_workshop_title_label.text = "RACE WORKSHOP  //  %s  //  %d / %d" % [String(category), selected_index + 1, items.size()]
	_workshop_item_label.text = str(projection.get(&"title", "ITEM"))
	_workshop_detail_label.text = str(projection.get(&"detail", ""))
	_workshop_build_label.text = str(projection.get(&"build", ""))
	_workshop_action_label.text = str(projection.get(&"action", "%s  APPLY" % _any_action_label(InputRouter.CONFIRM)))
	_workshop_action_label.modulate = CYAN if bool(projection.get(&"available", true)) else Color("ff806b")
	workshop_selection_changed.emit(get_workshop_snapshot())


func _get_workshop_items(category: StringName) -> Array[Dictionary]:
	match category:
		&"BIKE":
			return _bike_catalog.get_bikes(Profile.racer_reputation, true)
		&"CLASS":
			var class_items: Array[Dictionary] = []
			var catalog_data: Dictionary = _bike_catalog.to_dictionary()
			var class_data: Dictionary = catalog_data.get(&"bike_classes", {}) as Dictionary
			for raw_value: Variant in class_data.values():
				if raw_value is Dictionary:
					class_items.append((raw_value as Dictionary).duplicate(true))
			class_items.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
				return int(first.get(&"sort_order", 0)) < int(second.get(&"sort_order", 0))
			)
			return class_items
		&"TUNE":
			return TUNE_PRESETS.duplicate(true)
		&"PART":
			var part_items: Array[Dictionary] = []
			for slot: StringName in PART_SLOTS:
				part_items.append_array(_bike_catalog.get_parts_for_slot(slot, Profile.active_bike_id, Profile.racer_reputation, true))
			return part_items
		&"STYLE":
			return STYLE_PRESETS.duplicate(true)
		&"BUILD":
			var build_items: Array[Dictionary] = []
			for slot: Dictionary in Profile.get_saved_bike_build_slots():
				var slot_id := StringName(slot.get(&"slot_id", &""))
				var slot_label := str(slot.get(&"slot_label", "?"))
				var occupied := bool(slot.get(&"occupied", false))
				var saved: Dictionary = slot.get(&"build", {}) as Dictionary
				build_items.append({
					&"slot_id": slot_id, &"slot_label": slot_label,
					&"action_id": &"LOAD", &"occupied": occupied,
					&"saved_build": saved.duplicate(true),
				})
				build_items.append({
					&"slot_id": slot_id, &"slot_label": slot_label,
					&"action_id": &"SAVE", &"occupied": occupied,
					&"saved_build": saved.duplicate(true),
				})
			return build_items
	return []


func _get_selected_workshop_item(category: StringName) -> Dictionary:
	var items := _get_workshop_items(category)
	if items.is_empty():
		return {}
	var index := clampi(int(_workshop_item_indices.get(category, 0)), 0, items.size() - 1)
	return items[index].duplicate(true)


func _workshop_item_projection(category: StringName, item: Dictionary) -> Dictionary:
	match category:
		&"BIKE": return _bike_projection(item)
		&"CLASS": return _class_projection(item)
		&"TUNE": return _tune_projection(item)
		&"PART": return _part_projection(item)
		&"STYLE": return _style_projection(item)
		&"BUILD": return _saved_build_projection(item)
	return {}


func _bike_projection(item: Dictionary) -> Dictionary:
	var bike_id := StringName(item.get(&"bike_id", &""))
	var owned := not Profile.get_bike_build_snapshot(bike_id).is_empty()
	var active := bike_id == Profile.active_bike_id
	var required_rep := int(item.get(&"required_reputation", 0))
	var price := int(item.get(&"price", 0))
	var base_stats: Dictionary = item.get(&"base_stats", {}) as Dictionary
	var available := Profile.racer_reputation >= required_rep and (owned or Profile.cash >= price)
	var confirm_label := _any_action_label(InputRouter.CONFIRM)
	var action := "ACTIVE BIKE" if active else "%s  SELECT OWNED BIKE" % confirm_label if owned else "%s  BUY  $%d" % [confirm_label, price]
	if Profile.racer_reputation < required_rep:
		action = "LOCKED  //  REQUIRES %d RACER REP" % required_rep
	elif not owned and Profile.cash < price:
		action = "NEED $%d MORE" % (price - Profile.cash)
	return {
		&"title": str(item.get(&"display_name", bike_id)).to_upper(),
		&"detail": "%s  //  %dcc  //  OWNED %s\nChoose the machine that defines your class eligibility and base handling envelope." % [str(item.get(&"manufacturer", "")).to_upper(), int(item.get(&"displacement_cc", 0)), "YES" if owned else "NO"],
		&"build": "POWER %02d   ACCEL %02d   SPEED %02d   GRIP %02d   SUSPENSION %02d   AIR %02d" % [int(base_stats.get(&"power", 0)), int(base_stats.get(&"acceleration", 0)), int(base_stats.get(&"top_speed", 0)), int(base_stats.get(&"grip", 0)), int(base_stats.get(&"suspension", 0)), int(base_stats.get(&"air_control", 0))],
		&"action": action, &"available": available or active,
	}


func _class_projection(item: Dictionary) -> Dictionary:
	var class_id := StringName(item.get(&"class_id", &""))
	var setup := Profile.get_active_bike_setup_snapshot()
	var eligible: Array[StringName] = setup.get(&"eligible_classes", []) as Array[StringName]
	var available := class_id in eligible
	var selected := class_id == Profile.selected_bike_class
	var action := "SELECTED CLASS" if selected else "%s  ENTER CLASS" % _any_action_label(InputRouter.CONFIRM) if available else "INELIGIBLE  //  CHECK BIKE, RATING, AND REP"
	return {
		&"title": str(item.get(&"display_name", class_id)).to_upper(),
		&"detail": str(item.get(&"description", "Race class.")).to_upper(),
		&"build": "ACTIVE BIKE  %s   //   DISPLACEMENT %d-%dcc   //   RATING %.0f-%.0f   //   REQUIRED REP %d" % [String(Profile.active_bike_id), int(item.get(&"min_displacement_cc", 0)), int(item.get(&"max_displacement_cc", 999)), float(item.get(&"min_overall_rating", 0.0)), float(item.get(&"max_overall_rating", 100.0)), int(item.get(&"required_reputation", 0))],
		&"action": action, &"available": available,
	}


func _tune_projection(item: Dictionary) -> Dictionary:
	var tune: Dictionary = item.get(&"tune", {}) as Dictionary
	var active := _tune_matches(Profile.get_active_bike_setup_snapshot().get(&"build", {}) as Dictionary, tune)
	return {
		&"title": str(item.get(&"display_name", "TUNE")).to_upper(),
		&"detail": str(item.get(&"description", "")).to_upper(),
		&"build": _format_tune(tune),
		&"action": "ACTIVE TUNE" if active else "%s  APPLY PRESET  //  NO COST" % _any_action_label(InputRouter.CONFIRM),
		&"available": true,
	}


func _part_projection(item: Dictionary) -> Dictionary:
	var part_id := StringName(item.get(&"part_id", &""))
	var slot := StringName(item.get(&"slot", &""))
	var build: Dictionary = Profile.get_bike_build_snapshot(Profile.active_bike_id)
	var installed_parts: Dictionary = build.get(&"installed_parts", {}) as Dictionary
	var installed := StringName(installed_parts.get(slot, &"")) == part_id
	var owned := part_id in Profile.owned_part_ids
	var required_rep := int(item.get(&"required_reputation", 0))
	var price := int(item.get(&"price", 0))
	var available := Profile.racer_reputation >= required_rep and (owned or Profile.cash >= price)
	var confirm_label := _any_action_label(InputRouter.CONFIRM)
	var action := "INSTALLED  //  %s" % String(slot) if installed else "%s  INSTALL OWNED PART" % confirm_label if owned else "%s  BUY + INSTALL  $%d" % [confirm_label, price]
	if Profile.racer_reputation < required_rep:
		action = "LOCKED  //  REQUIRES %d RACER REP" % required_rep
	elif not owned and Profile.cash < price:
		action = "NEED $%d MORE" % (price - Profile.cash)
	return {
		&"title": str(item.get(&"display_name", part_id)).to_upper(),
		&"detail": "%s SLOT  //  %s\nInstalled parts replace the current component in that slot." % [String(slot), "OWNED" if owned else "UNOWNED"],
		&"build": "STAT CHANGES  //  %s" % _format_modifiers(item.get(&"modifiers", {}) as Dictionary),
		&"action": action, &"available": available or installed,
	}


func _style_projection(item: Dictionary) -> Dictionary:
	var style_id := StringName(item.get(&"style_id", &""))
	var required_tier := int(item.get(&"required_tier", 0))
	var available := Profile.get_cosmetic_tier() >= required_tier
	var cosmetics := Profile.get_rider_cosmetics()
	var active := StringName(cosmetics.get(&"bike_livery", &"FACTORY")) == style_id or (style_id == &"DESERT" and StringName(cosmetics.get(&"bike_livery", &"")) == &"DESERT_WORKS") or (style_id == &"NIGHT" and StringName(cosmetics.get(&"bike_livery", &"")) == &"NIGHT_RACE") or (style_id == &"CHAMPION" and StringName(cosmetics.get(&"bike_livery", &"")) == &"TOUR_CHAMPION")
	var changes: Dictionary = item.get(&"changes", {}) as Dictionary
	return {
		&"title": str(item.get(&"display_name", style_id)).to_upper(),
		&"detail": str(item.get(&"description", "")).to_upper(),
		&"build": "HELMET %s   //   JERSEY %s   //   LIVERY %s   //   STYLE TIER %d / %d" % [str(changes.get(&"helmet", "")).replace("_", " "), str(changes.get(&"jersey", "")).replace("_", " "), str(changes.get(&"bike_livery", "")).replace("_", " "), Profile.get_cosmetic_tier(), required_tier],
		&"action": "ACTIVE STYLE" if active else "%s  EQUIP STYLE" % _any_action_label(InputRouter.CONFIRM) if available else "LOCKED  //  EARN RIDING FEATS FOR STYLE TIER %d" % required_tier,
		&"available": available,
	}


func _saved_build_projection(item: Dictionary) -> Dictionary:
	var action_id := StringName(item.get(&"action_id", &""))
	var slot_label := str(item.get(&"slot_label", "?"))
	var occupied := bool(item.get(&"occupied", false))
	var saved: Dictionary = item.get(&"saved_build", {}) as Dictionary
	var confirm_label := _any_action_label(InputRouter.CONFIRM)
	if action_id == &"LOAD":
		if not occupied or saved.is_empty():
			return {
				&"title": "LOAD BUILD %s" % slot_label,
				&"detail": "EMPTY SLOT  //  SAVE A CURRENT CONFIGURATION HERE FIRST.",
				&"build": "Saved builds restore bike, kit, class, parts, tune, and livery without restoring condition or odometer.",
				&"action": "EMPTY  //  SELECT SAVE BUILD %s" % slot_label,
				&"available": false,
			}
		var saved_fit := _saved_build_event_fit(saved)
		return {
			&"title": "LOAD BUILD %s" % slot_label,
			&"detail": "%s  //  READY TO APPLY\nSELECTED EVENT  //  %s  //  %s" % [
				str(saved.get(&"display_name", "SAVED BUILD")),
				str(saved_fit.get(&"event_name", "EVENT")), str(saved_fit.get(&"fit_status", "ALTERNATE")),
			],
			&"build": _saved_build_summary(saved),
			&"action": "%s  LOAD BUILD  //  CURRENT CONDITION IS PRESERVED" % confirm_label,
			&"available": true,
		}
	var active_name := _current_saved_build_name()
	var active_fit := _event_strategy_fit(EVENTS[_event_index], Profile.current_setup, _active_tune_id())
	return {
		&"title": "SAVE CURRENT  //  BUILD %s" % slot_label,
		&"detail": "%s\nSELECTED EVENT  //  %s  //  %s\n%s" % [
			active_name,
			str(active_fit.get(&"event_name", "EVENT")), str(active_fit.get(&"fit_status", "ALTERNATE")),
			"Replace this slot's configuration. Condition and odometer are never copied."
			if occupied else "Store this configuration for one-step reuse across events.",
		],
		&"build": _current_saved_build_summary(),
		&"action": "%s  %s BUILD %s" % [confirm_label, "OVERWRITE" if occupied else "SAVE", slot_label],
		&"available": true,
	}


func _activate_or_purchase_bike(item: Dictionary) -> bool:
	var bike_id := StringName(item.get(&"bike_id", &""))
	var owned := not Profile.get_bike_build_snapshot(bike_id).is_empty()
	if not owned:
		var required_rep := int(item.get(&"required_reputation", 0))
		var price := int(item.get(&"price", 0))
		if Profile.racer_reputation < required_rep:
			_set_workshop_status("BIKE LOCKED  //  NEED %d RACER REP" % required_rep, false)
			return false
		if Profile.cash < price:
			_set_workshop_status("NOT ENOUGH CASH  //  NEED $%d" % (price - Profile.cash), false)
			return false
		if not Profile.purchase_racing_bike(bike_id):
			_set_workshop_status("BIKE PURCHASE FAILED", false)
			return false
	if not Profile.set_active_bike(bike_id):
		_set_workshop_status("BIKE COULD NOT BE ACTIVATED", false)
		return false
	_set_workshop_status("%s READY  //  CLASS ELIGIBILITY UPDATED" % str(item.get(&"display_name", bike_id)).to_upper(), true)
	return true


func _select_bike_class(item: Dictionary) -> bool:
	var class_id := StringName(item.get(&"class_id", &""))
	if not Profile.set_selected_bike_class(class_id):
		_set_workshop_status("CLASS INELIGIBLE FOR THE ACTIVE BUILD", false)
		return false
	_set_workshop_status("%s SELECTED" % str(item.get(&"display_name", class_id)).to_upper(), true)
	return true


func _apply_tune_preset(item: Dictionary) -> bool:
	var tune: Dictionary = item.get(&"tune", {}) as Dictionary
	if not Profile.set_bike_tune(tune):
		_set_workshop_status("TUNE COULD NOT BE APPLIED", false)
		return false
	_set_workshop_status("%s APPLIED  //  BUILD STATS RECALCULATED" % str(item.get(&"display_name", "TUNE")).to_upper(), true)
	return true


func _purchase_or_install_part(item: Dictionary) -> bool:
	var part_id := StringName(item.get(&"part_id", &""))
	if part_id not in Profile.owned_part_ids:
		var required_rep := int(item.get(&"required_reputation", 0))
		var price := int(item.get(&"price", 0))
		if Profile.racer_reputation < required_rep:
			_set_workshop_status("PART LOCKED  //  NEED %d RACER REP" % required_rep, false)
			return false
		if Profile.cash < price:
			_set_workshop_status("NOT ENOUGH CASH  //  NEED $%d" % (price - Profile.cash), false)
			return false
		if not Profile.purchase_racing_part(part_id):
			_set_workshop_status("PART PURCHASE FAILED", false)
			return false
	if not Profile.install_racing_part(part_id):
		_set_workshop_status("PART IS NOT COMPATIBLE WITH THE ACTIVE BIKE", false)
		return false
	_set_workshop_status("%s INSTALLED  //  %s SLOT" % [str(item.get(&"display_name", part_id)).to_upper(), String(item.get(&"slot", &""))], true)
	return true


func _apply_style_preset(item: Dictionary) -> bool:
	var required_tier := int(item.get(&"required_tier", 0))
	if Profile.get_cosmetic_tier() < required_tier:
		_set_workshop_status("STYLE LOCKED  //  EARN MORE RIDING FEATS", false)
		return false
	var changes: Dictionary = item.get(&"changes", {}) as Dictionary
	if not Profile.set_rider_cosmetics(changes):
		_set_workshop_status("STYLE COULD NOT BE EQUIPPED", false)
		return false
	_set_workshop_status("%s EQUIPPED" % str(item.get(&"display_name", "STYLE")).to_upper(), true)
	return true


func _apply_saved_build_action(item: Dictionary) -> bool:
	var action_id := StringName(item.get(&"action_id", &""))
	var slot_id := StringName(item.get(&"slot_id", &""))
	var slot_label := str(item.get(&"slot_label", "?"))
	var result: Dictionary
	if action_id == &"SAVE":
		result = Profile.save_current_bike_build(slot_id, _current_saved_build_name())
		if bool(result.get(&"accepted", false)):
			_set_workshop_status("BUILD %s SAVED  //  %s" % [
				slot_label, str((result.get(&"build", {}) as Dictionary).get(&"display_name", "READY")),
			], true)
			return true
	else:
		result = Profile.load_saved_bike_build(slot_id)
		if bool(result.get(&"accepted", false)):
			var current_index := SETUPS.find(Profile.current_setup)
			_selected_index = current_index if current_index >= 0 else 1
			_sync_workshop_selection()
			_set_workshop_status("BUILD %s LOADED  //  %s" % [
				slot_label, str((result.get(&"build", {}) as Dictionary).get(&"display_name", "READY")),
			], true)
			return true
	var reason := StringName(result.get(&"reason", &"BUILD_UNAVAILABLE"))
	var failure_text := "EMPTY BUILD SLOT" if reason == &"EMPTY_SLOT" else (
		"BUILD SAVE FAILED" if reason == &"SAVE_FAILED" else "BUILD IS NO LONGER AVAILABLE"
	)
	_set_workshop_status("%s  //  NO CHANGES APPLIED" % failure_text, false)
	return false


func _set_workshop_status(message: String, success: bool) -> void:
	_workshop_status_label.text = message
	_workshop_status_label.modulate = CYAN if success else Color("ff806b")


func _sync_workshop_selection() -> void:
	_set_workshop_index_for_id(&"BIKE", &"bike_id", Profile.active_bike_id)
	_set_workshop_index_for_id(&"CLASS", &"class_id", Profile.selected_bike_class)
	var build: Dictionary = Profile.get_bike_build_snapshot(Profile.active_bike_id)
	var tune: Dictionary = build.get(&"tune", {}) as Dictionary
	for index: int in TUNE_PRESETS.size():
		if _tune_dictionaries_equal(TUNE_PRESETS[index].get(&"tune", {}) as Dictionary, tune):
			_workshop_item_indices[&"TUNE"] = index
			break
	var livery := StringName(Profile.get_rider_cosmetics().get(&"bike_livery", &"FACTORY"))
	for index: int in STYLE_PRESETS.size():
		var preset_livery := StringName((STYLE_PRESETS[index].get(&"changes", {}) as Dictionary).get(&"bike_livery", &""))
		if preset_livery == livery:
			_workshop_item_indices[&"STYLE"] = index
			break


func _set_workshop_index_for_id(category: StringName, key: StringName, target: StringName) -> void:
	var items := _get_workshop_items(category)
	for index: int in items.size():
		if StringName(items[index].get(key, &"")) == target:
			_workshop_item_indices[category] = index
			return


func _workshop_item_id(category: StringName, item: Dictionary) -> StringName:
	match category:
		&"BIKE": return StringName(item.get(&"bike_id", &""))
		&"CLASS": return StringName(item.get(&"class_id", &""))
		&"TUNE": return StringName(item.get(&"preset_id", &""))
		&"PART": return StringName(item.get(&"part_id", &""))
		&"STYLE": return StringName(item.get(&"style_id", &""))
		&"BUILD": return StringName("%s_%s" % [
			String(item.get(&"slot_id", &"")), String(item.get(&"action_id", &"")),
		])
	return &""


func _active_tune_name() -> String:
	var build: Dictionary = Profile.get_bike_build_snapshot(Profile.active_bike_id)
	var tune: Dictionary = build.get(&"tune", {}) as Dictionary
	for preset: Dictionary in TUNE_PRESETS:
		if _tune_dictionaries_equal(preset.get(&"tune", {}) as Dictionary, tune):
			return str(preset.get(&"display_name", "BALANCED"))
	return "CUSTOM"


func _active_tune_id() -> StringName:
	var build: Dictionary = Profile.get_bike_build_snapshot(Profile.active_bike_id)
	return _tune_id_for_dictionary(build.get(&"tune", {}) as Dictionary)


func _current_saved_build_name() -> String:
	var activity := EVENTS[_event_index]
	var fit := _event_strategy_fit(activity, Profile.current_setup, _active_tune_id())
	if _is_event_unlocked(activity) and bool(fit.get(&"full_match", false)):
		return ("%s // %s" % [str(fit.get(&"event_name", "EVENT")), str(fit.get(&"focus", "PLAN"))]).substr(0, 40)
	var definition: Dictionary = _bike_catalog.get_bike(Profile.active_bike_id)
	var bike_name := str(definition.get(&"display_name", String(Profile.active_bike_id))).replace("_", " ")
	return ("%s // %s" % [bike_name.to_upper(), _active_tune_name().to_upper()]).substr(0, 40)


func _current_saved_build_summary() -> String:
	var setup: Dictionary = Profile.get_active_bike_setup_snapshot()
	var build: Dictionary = setup.get(&"build", {}) as Dictionary
	return _saved_build_summary({
		&"bike_id": Profile.active_bike_id,
		&"setup_id": Profile.current_setup,
		&"selected_class": Profile.selected_bike_class,
		&"installed_parts": (build.get(&"installed_parts", {}) as Dictionary).duplicate(true),
		&"tune": (build.get(&"tune", {}) as Dictionary).duplicate(true),
		&"livery_id": StringName(Profile.get_rider_cosmetics().get(&"bike_livery", &"FACTORY")),
	})


func _saved_build_summary(saved: Dictionary) -> String:
	var installed_parts: Dictionary = saved.get(&"installed_parts", {}) as Dictionary
	var part_names := PackedStringArray()
	for slot: StringName in PART_SLOTS:
		var part_id := StringName(installed_parts.get(slot, &""))
		if part_id.is_empty():
			continue
		var definition: Dictionary = _bike_catalog.get_part(part_id)
		part_names.append(str(definition.get(&"display_name", part_id)).to_upper())
	var parts_text := "STOCK" if part_names.is_empty() else " / ".join(part_names)
	return "BIKE %s   //   KIT %s   //   CLASS %s\nPARTS %s\nTUNE %s   //   LIVERY %s" % [
		String(saved.get(&"bike_id", &"")).replace("_", " "),
		String(saved.get(&"setup_id", &"BALANCED")).replace("_", " "),
		String(saved.get(&"selected_class", &"")).replace("_", " "),
		parts_text,
		_tune_name_for_dictionary(saved.get(&"tune", {}) as Dictionary).to_upper(),
		String(saved.get(&"livery_id", &"FACTORY")).replace("_", " "),
	]


func _tune_name_for_dictionary(tune: Dictionary) -> String:
	for preset: Dictionary in TUNE_PRESETS:
		if _tune_dictionaries_equal(preset.get(&"tune", {}) as Dictionary, tune):
			return str(preset.get(&"display_name", "BALANCED"))
	return "CUSTOM"


func _tune_id_for_dictionary(tune: Dictionary) -> StringName:
	for preset: Dictionary in TUNE_PRESETS:
		if _tune_dictionaries_equal(preset.get(&"tune", {}) as Dictionary, tune):
			return StringName(preset.get(&"preset_id", &"BALANCED"))
	return &"CUSTOM"


func _saved_build_event_fit(saved: Dictionary) -> Dictionary:
	return _event_strategy_fit(
		EVENTS[_event_index],
		StringName(saved.get(&"setup_id", &"BALANCED")),
		_tune_id_for_dictionary(saved.get(&"tune", {}) as Dictionary)
	)


func _tune_matches(build: Dictionary, tune: Dictionary) -> bool:
	return _tune_dictionaries_equal(build.get(&"tune", {}) as Dictionary, tune)


func _tune_dictionaries_equal(first: Dictionary, second: Dictionary) -> bool:
	for key: StringName in [&"gearing", &"tire_grip", &"suspension_stiffness", &"suspension_damping", &"preload", &"brake_bias"]:
		if not is_equal_approx(float(first.get(key, 0.0)), float(second.get(key, 0.0))):
			return false
	return true


func _format_tune(tune: Dictionary) -> String:
	return "GEARING %+.0f%%   GRIP %+.0f%%   STIFFNESS %+.0f%%   DAMPING %+.0f%%   PRELOAD %+.0f%%   BRAKE %+.0f%%" % [
		float(tune.get(&"gearing", 0.0)) * 100.0, float(tune.get(&"tire_grip", 0.0)) * 100.0,
		float(tune.get(&"suspension_stiffness", 0.0)) * 100.0, float(tune.get(&"suspension_damping", 0.0)) * 100.0,
		float(tune.get(&"preload", 0.0)) * 100.0, float(tune.get(&"brake_bias", 0.0)) * 100.0,
	]


func _format_modifiers(modifiers: Dictionary) -> String:
	var tokens := PackedStringArray()
	for raw_key: Variant in modifiers:
		var value := float(modifiers.get(raw_key, 0.0))
		tokens.append("%s %+.1f" % [String(raw_key).replace("_", " ").to_upper(), value])
	return "   ".join(tokens)


func _on_input_mode_changed(_mode: StringName) -> void:
	_refresh_static_input_prompts()
	if _open:
		_refresh()


func _on_bindings_changed(_actions: Array[StringName]) -> void:
	_refresh_static_input_prompts()
	if _open:
		_refresh()


func _refresh_static_input_prompts() -> void:
	var mode := InputRouter.input_mode
	if _setup_left_hint != null:
		_setup_left_hint.text = "‹  %s" % InputRouter.get_action_label(InputRouter.GARAGE_LEFT, mode, 2)
	if _setup_right_hint != null:
		_setup_right_hint.text = "%s  ›" % InputRouter.get_action_label(InputRouter.GARAGE_RIGHT, mode, 2)
	if _workshop_hint_label != null:
		_workshop_hint_label.text = "%s  OPEN" % _any_action_label(InputRouter.OPEN_WORKSHOP)
	if _workshop_controls_label != null:
		_workshop_controls_label.text = "%s  CATEGORY     %s  ITEM     %s  APPLY     %s  REPAIR     %s  CLOSE" % [
			_any_action_pair_label(InputRouter.GARAGE_LEFT, InputRouter.GARAGE_RIGHT),
			_any_action_pair_label(InputRouter.EVENT_PREVIOUS, InputRouter.EVENT_NEXT),
			_any_action_label(InputRouter.CONFIRM),
			_any_action_label(InputRouter.REPAIR_BIKE),
			_workshop_close_label(),
		]


func _any_action_label(action: StringName) -> String:
	# Garage copy follows the active device; INPUT_MODE_ANY is reserved for the
	# Settings binding summary where showing every configured family is useful.
	return InputRouter.get_action_label(action, InputRouter.input_mode, 2)


func _any_action_pair_label(negative_action: StringName, positive_action: StringName) -> String:
	return InputRouter.get_action_pair_label(
		negative_action, positive_action, InputRouter.input_mode, 2
	)


func _workshop_close_label() -> String:
	var workshop_label := InputRouter.get_action_label(
		InputRouter.OPEN_WORKSHOP, InputRouter.input_mode, 2
	)
	var garage_label := InputRouter.get_action_label(
		InputRouter.OPEN_GARAGE, InputRouter.input_mode, 2
	)
	return workshop_label if workshop_label == garage_label else "%s / %s" % [workshop_label, garage_label]


func _is_workshop_toggle(event: InputEvent) -> bool:
	return event.is_action_pressed(InputRouter.OPEN_WORKSHOP)


func _is_continue_weekend_input(event: InputEvent) -> bool:
	return event.is_action_pressed(InputRouter.CONTINUE_WEEKEND)


func _focus_continue_weekend_event() -> void:
	if Profile.has_method(&"is_first_run_onboarding_active") and Profile.is_first_run_onboarding_active():
		# Recommendation and selection are separate concerns. Academy remains the
		# guided first-ride recommendation, but a fresh menu starts at level 1.
		_event_index = maxi(EVENTS.find(INITIAL_EVENT), 0)
		return
	var activity := StringName(get_continue_weekend_snapshot().get(&"activity", &""))
	var index := EVENTS.find(activity)
	if index >= 0:
		_event_index = index


func _refresh_weekend_action() -> void:
	if _weekend_action_label == null:
		return
	var action := get_continue_weekend_snapshot()
	var action_text := str(action.get(&"action_text", ""))
	_weekend_action_label.text = action_text
	_weekend_action_label.visible = not action_text.is_empty()
	_set_label_color(
		_weekend_action_label,
		CYAN if bool(action.get(&"available", false)) or bool(action.get(&"complete", false)) else Color("ff6f5e")
	)


func _attempt_repair() -> void:
	var repair_price := Profile.get_repair_price()
	if repair_price <= 0:
		_status_label.text = "THE BIKE IS ALREADY READY TO RIDE"
		_status_label.modulate = CYAN
		_emit_interface_feedback(&"DENIED", &"GARAGE_REPAIR")
		return
	if Profile.repair_bike():
		_refresh()
		_status_label.text = "BIKE RESTORED — POWER, GRIP, AND TOP SPEED RECOVERED"
		_status_label.modulate = CYAN
		_emit_interface_feedback(&"CONFIRM", &"GARAGE_REPAIR")
	else:
		_status_label.text = "NOT ENOUGH CASH FOR REPAIRS"
		_status_label.modulate = Color("ff6f5e")
		_emit_interface_feedback(&"DENIED", &"GARAGE_REPAIR")


func _emit_interface_feedback(kind: StringName, context: StringName) -> void:
	EventBus.interface_feedback_requested.emit(kind, context)


func _refresh_event() -> void:
	var activity := EVENTS[_event_index]
	var event_color := _event_color(activity)
	var challenge_id := _challenge_id_for_activity(activity)
	var medal := Profile.get_event_medal(activity, challenge_id)
	var is_unlocked := _is_event_unlocked(activity)
	var competition_briefing := (
		get_event_competition_snapshot(activity)
		if RaceEventCatalog.is_race_event(activity) and activity != &"ACADEMY"
		else {}
	)
	var exact_best_available := bool(competition_briefing.get(&"exact_rules_best", false))
	var medal_times := competition_briefing.get(&"medal_times_usec", {}) as Dictionary
	_event_accent.color = event_color if is_unlocked else Color("74413d")
	var recommended := RaceEventCatalog.get_recommended_event()
	var recommended_name := str(RaceEventCatalog.get_event(recommended).get(&"display_name", recommended)).to_upper()
	if Profile.has_method(&"is_first_run_onboarding_active") and Profile.is_first_run_onboarding_active():
		_tour_label.text = "FIRST RIDE  //  ACADEMY RECOMMENDED  //  QUARRY TRAIL ALSO OPEN"
	else:
		_tour_label.text = "NEXT EVENT  //  %s  //  %02d CLEARED" % [recommended_name, _completed_event_count()]
	for index: int in _event_markers.size():
		var marker_activity := EVENTS[index]
		var marker := _event_markers[index]
		if index == _event_index:
			marker.text = ">%d" % (index + 1)
			_set_label_color(marker, event_color if is_unlocked else Color("ff6f5e"))
		elif Profile.has_completed_event(marker_activity, _challenge_id_for_activity(marker_activity)):
			marker.text = "%02d" % (index + 1)
			_set_label_color(marker, AMBER)
		elif _is_event_unlocked(marker_activity):
			marker.text = "%02d" % (index + 1)
			_set_label_color(marker, Color("7e919d"))
		else:
			marker.text = "--"
			_set_label_color(marker, Color("74413d"))
	match activity:
		&"FREESTYLE":
			_profile_label.text = "$%06d     FREESTYLER REP  %04d" % [Profile.cash, Profile.freestyler_reputation]
		&"DISCOVERY":
			_profile_label.text = "$%06d     EXPLORER REP  %04d" % [Profile.cash, Profile.explorer_reputation]
		_:
			_profile_label.text = "$%06d     RACER REP  %04d" % [Profile.cash, Profile.racer_reputation]
	var data := RaceEventCatalog.get_event(activity)
	_refresh_garage_context(activity, data)
	_event_label.text = "%s   //   EVENT %02d / %02d   //   %s" % [
		str(data.get(&"display_name", String(activity))), _event_index + 1, EVENTS.size(),
		StringName(data.get(&"format", activity)),
	]
	_event_description.text = str(data.get(&"description", "Choose a line, commit, and finish the session."))
	if not is_unlocked:
		_event_meta_label.text = "LOCKED   //   %s" % _event_unlock_hint(activity)
	elif activity == &"FREESTYLE":
		_event_meta_label.text = "MEDAL  %s   //   BEST  %06d   //   %s" % [String(medal), Profile.best_freestyle_score, _next_event_target(activity, challenge_id, exact_best_available, medal_times)]
	elif activity == &"DISCOVERY":
		var best_text := "--:--.---" if Profile.best_discovery_usec < 0 else _format_usec(Profile.best_discovery_usec)
		_event_meta_label.text = "MEDAL  %s   //   BEST  %s   //   %s" % [String(medal), best_text, _next_event_target(activity, challenge_id, exact_best_available, medal_times)]
	else:
		_event_meta_label.text = "MEDAL  %s   //   %s   //   %s" % [String(medal), _next_event_target(activity, challenge_id, exact_best_available, medal_times), str(data.get(&"meta", "RACE SESSION"))]
	_set_label_color(_event_meta_label, event_color if is_unlocked else Color("ff6f5e"))
	_refresh_event_competition(activity, is_unlocked, competition_briefing)
	if not is_unlocked and Profile.is_setup_unlocked(SETUPS[_selected_index]):
		_status_label.text = "LOCKED   //   %s" % _event_unlock_hint(activity)
		_status_label.modulate = Color("ff6f5e")


func _refresh_event_strategy() -> void:
	if _strategy_label == null:
		return
	var snapshot := get_event_strategy_presentation_snapshot()
	var recommended_setup := String(snapshot.get(&"recommended_setup", &"BALANCED")).replace("_", " ")
	var recommended_tune := String(snapshot.get(&"recommended_tune", &"BALANCED")).replace("_", " ")
	var setup_owned := bool(snapshot.get(&"recommended_setup_owned", false))
	var setup_affordable := bool(snapshot.get(&"recommended_setup_affordable", false))
	var setup_price := int(snapshot.get(&"recommended_setup_price", 0))
	var setup_shortfall := int(snapshot.get(&"recommended_setup_shortfall", 0))
	var match_text := "MATCH" if bool(snapshot.get(&"ready_to_ride", false)) else "ALTERNATE BUILD"
	if not setup_owned:
		match_text = "KIT READY $%d" % setup_price if setup_affordable else "KIT $%d AWAY" % setup_shortfall
	elif bool(snapshot.get(&"setup_match", false)) and not bool(snapshot.get(&"tune_match", false)):
		match_text = "KIT MATCH"
	_strategy_label.text = "EVENT PLAN  //  KIT %s + TUNE %s  //  %s  //  %s" % [
		recommended_setup, recommended_tune, str(snapshot.get(&"focus", "READABLE PACE")), match_text,
	]
	_set_label_color(_strategy_label, CYAN if bool(snapshot.get(&"ready_to_ride", false)) else AMBER if setup_affordable and not setup_owned else CREAM)


func _refresh_garage_context(activity: StringName, event_data: Dictionary) -> void:
	if _garage_context_label == null:
		return
	if _is_pristine_first_run_context() and activity == INITIAL_EVENT:
		_garage_context_label.text = "QUARRY TRAIL  //  FIRST EVENT READY"
		return
	if activity == &"ACADEMY":
		_garage_context_label.text = "RIDING ACADEMY  //  OPTIONAL SKILLS COACHING"
		return
	var track_id := StringName(event_data.get(&"track_id", &""))
	var district_name := "BACKCOUNTRY TOUR"
	match track_id:
		&"QUARRY": district_name = "QUARRY DISTRICT"
		&"PINE": district_name = "PINE RIDGE"
		&"MESA_MX": district_name = "RED MESA"
	_garage_context_label.text = "%s  //  BUILD FOR THE SELECTED LINE" % district_name


func _is_pristine_first_run_context() -> bool:
	if not Profile.has_method(&"is_first_run_onboarding_active") or not Profile.is_first_run_onboarding_active():
		return false
	if _completed_event_count() > 0:
		return false
	var weekend: Variant = Profile.get_race_weekend_director()
	if weekend == null:
		return true
	return (
		StringName(weekend.get_current_phase()) == &"PRACTICE"
		and weekend.session_results.is_empty()
	)


func _competition_session(activity: StringName) -> RaceSessionConfig:
	if not RaceEventCatalog.is_race_event(activity):
		return null
	if RaceEventCatalog.is_challenge_event(activity) and _competition_source != null:
		var challenge_value: Variant = null
		if activity == &"WEEKLY_CHALLENGE" and _competition_source.has_method(&"get_weekly_challenge"):
			challenge_value = _competition_source.call(&"get_weekly_challenge")
		elif activity == &"DAILY_CHALLENGE" and _competition_source.has_method(&"get_daily_challenge"):
			challenge_value = _competition_source.call(&"get_daily_challenge")
		if challenge_value is Dictionary and not (challenge_value as Dictionary).is_empty():
			return RaceEventCatalog.get_challenge_session_config(activity, challenge_value as Dictionary)
	return RaceEventCatalog.get_session_config(activity)


func _competition_signature(session: RaceSessionConfig) -> String:
	if session == null:
		return ""
	var rules := session.rules
	var build_signature := ""
	if not rules.has(&"challenge_id") and Profile.has_method(&"get_active_bike_setup_snapshot"):
		var build := Profile.call(&"get_active_bike_setup_snapshot") as Dictionary
		build_signature = str(build.get(&"signature", ""))
	return CompetitiveRunSignature.build({
		"event_id": rules.get(&"competitive_event_id", session.event_id),
		"track_id": session.track_id,
		"route_version": session.route_version,
		"format": session.format,
		"laps": session.laps,
		"bike_class": rules.get(&"competitive_bike_class", session.bike_class),
		"difficulty": rules.get(&"competitive_difficulty", session.difficulty),
		"assist_mode": rules.get(&"competitive_assist_mode", Profile.assist_mode),
		"setup_id": rules.get(&"competitive_setup_id", Profile.current_setup),
		"tune_signature": build_signature,
		"weather": session.weather,
		"surface": session.surface_modifier,
		"challenge_id": rules.get(&"challenge_id", ""),
		"modifiers": rules.get(&"modifiers", []),
	})


func _session_challenge_id(session: RaceSessionConfig) -> StringName:
	return StringName(session.rules.get(&"challenge_id", &"")) if session != null else &""


func _session_competition_id(session: RaceSessionConfig) -> StringName:
	return StringName(session.rules.get(&"competition_id", &"")) if session != null else &""


func _challenge_id_for_activity(activity: StringName) -> StringName:
	return _session_challenge_id(_competition_session(activity)) if RaceEventCatalog.is_challenge_event(activity) else &""


func _championship_briefing(activity: StringName) -> Dictionary:
	var service: Variant = Profile.get_championship_service() if Profile.has_method(&"get_championship_service") else null
	if service == null:
		return {}
	var calendar: Array[Dictionary] = service.get_calendar()
	var standings: Array[Dictionary] = service.get_standings()
	var next_round: Dictionary = service.get_next_round()
	var event_round: Dictionary = {}
	for round_data: Dictionary in calendar:
		if StringName(round_data.get(&"event_id", &"")) == activity:
			event_round = round_data.duplicate(true)
			break
	var player: Dictionary = {}
	var leader: Dictionary = standings[0].duplicate(true) if not standings.is_empty() else {}
	for standing: Dictionary in standings:
		if StringName(standing.get(&"rider_id", &"")) == &"PLAYER":
			player = standing.duplicate(true)
			break
	var leader_points := int(leader.get(&"points", 0))
	var player_points := int(player.get(&"points", 0))
	return {
		&"championship_id": StringName(service.championship_id),
		&"display_name": str(service.display_name),
		&"season": int(service.season_number),
		&"complete": bool(service.is_complete()),
		&"completed_rounds": int(service.completed_round_count()),
		&"round_total": calendar.size(),
		&"event_round": event_round,
		&"event_round_number": int(event_round.get(&"round_number", 0)),
		&"is_active_round": (
			not next_round.is_empty()
			and StringName(next_round.get(&"event_id", &"")) == activity
		),
		&"next_round": next_round.duplicate(true),
		&"player_position": int(player.get(&"championship_position", 0)),
		&"player_points": player_points,
		&"leader_name": str(leader.get(&"display_name", "UNRANKED")),
		&"leader_points": leader_points,
		&"points_to_leader": maxi(leader_points - player_points, 0),
		&"standings": standings.duplicate(true),
	}


func _rival_briefing(activity: StringName, session: RaceSessionConfig, standings_value: Array) -> Dictionary:
	if session == null or activity == &"ACADEMY":
		return {}
	var rival_id := &""
	var standing_data: Dictionary = {}
	var standings: Array[Dictionary] = []
	for raw_standing: Variant in standings_value:
		if raw_standing is Dictionary:
			standings.append((raw_standing as Dictionary).duplicate(true))
	if activity == &"MESA_RIVAL":
		rival_id = &"ROOK"
	else:
		var player_index := -1
		for index: int in standings.size():
			if StringName(standings[index].get(&"rider_id", &"")) == &"PLAYER":
				player_index = index
				break
		var rival_index := -1
		if player_index > 0:
			rival_index = player_index - 1
		elif player_index == 0 and standings.size() > 1:
			rival_index = 1
		elif player_index < 0:
			for index: int in standings.size():
				if StringName(standings[index].get(&"rider_id", &"")) != &"PLAYER":
					rival_index = index
					break
		if rival_index >= 0:
			standing_data = standings[rival_index].duplicate(true)
			rival_id = StringName(standing_data.get(&"rider_id", &""))
	if rival_id.is_empty():
		var featured_value: Variant = session.rules.get(&"featured_rider_ids", [])
		if featured_value is Array and not (featured_value as Array).is_empty():
			rival_id = StringName((featured_value as Array)[0])
	if rival_id.is_empty():
		rival_id = &"ROOK"
	var profile := RiderRoster.get_rider(rival_id)
	if profile.is_empty():
		return {}
	var player_points := 0
	for standing: Dictionary in standings:
		if StringName(standing.get(&"rider_id", &"")) == &"PLAYER":
			player_points = int(standing.get(&"points", 0))
			break
	return {
		&"rider_id": rival_id,
		&"display_name": str(standing_data.get(&"display_name", profile.get(&"name", rival_id))),
		&"number": int(profile.get(&"number", 0)),
		&"signature_trait": str(profile.get(&"signature_trait", "RACE PACE")),
		&"championship_position": int(standing_data.get(&"championship_position", 0)),
		&"points": int(standing_data.get(&"points", 0)),
		&"points_delta": int(standing_data.get(&"points", 0)) - player_points,
	}


func _refresh_event_competition(
	activity: StringName,
	is_unlocked: bool,
	briefing: Dictionary = {}
) -> void:
	if _event_competition_label == null:
		return
	var should_show := RaceEventCatalog.is_race_event(activity) and activity != &"ACADEMY"
	_event_competition_label.visible = should_show
	if not should_show:
		_event_competition_label.text = ""
		return
	if briefing.is_empty():
		briefing = get_event_competition_snapshot(activity)
	var best_usec := int(briefing.get(&"personal_best_usec", -1))
	var board_total := int(briefing.get(&"local_board_total", 0))
	var local_rank := int(briefing.get(&"local_rank", 0))
	var board_text := "LOCAL --"
	if local_rank > 0:
		board_text = "LOCAL P%d/%d" % [local_rank, maxi(board_total, local_rank)]
	elif board_total > 0:
		board_text = "LOCAL --/%d" % board_total
	var best_prefix := "PB" if bool(briefing.get(&"exact_rules_best", false)) else "EVENT PB"
	var best_text := "%s %s" % [best_prefix, _format_usec(best_usec)] if best_usec >= 0 else "PB --:--.---"
	var availability := PackedStringArray()
	if bool(briefing.get(&"ghost_available", false)):
		availability.append("PB GHOST")
	if bool(briefing.get(&"replay_available", false)):
		availability.append("REPLAY READY")
	var first_line := "%s  //  %s" % [board_text, best_text]
	if not availability.is_empty():
		first_line += "  //  %s" % " + ".join(availability)

	var championship: Dictionary = briefing.get(&"championship", {}) as Dictionary
	var season := int(championship.get(&"season", 1))
	var round_total := int(championship.get(&"round_total", 0))
	var event_round_number := int(championship.get(&"event_round_number", 0))
	var player_position := int(championship.get(&"player_position", 0))
	var player_points := int(championship.get(&"player_points", 0))
	var table_text := "UNRANKED"
	if player_position > 0:
		table_text = "P%d  %dPTS" % [player_position, player_points]
	var tour_text := "TOUR S%02d  //  %s" % [season, table_text]
	if bool(championship.get(&"is_active_round", false)):
		tour_text = "TOUR S%02d R%d/%d LIVE  //  WIN 25PTS  //  %s" % [season, event_round_number, round_total, table_text]
	elif event_round_number > 0:
		var next_round: Dictionary = championship.get(&"next_round", {}) as Dictionary
		tour_text = "TOUR R%d/%d  //  %s  //  NEXT %s" % [
			event_round_number, round_total, table_text,
			str(next_round.get(&"display_name", "SEASON COMPLETE")).to_upper(),
		]
	if _is_pristine_first_run_context() and activity == INITIAL_EVENT:
		tour_text = "FIRST ROUTE  //  FINISH TO SET A PB"

	var rival: Dictionary = briefing.get(&"rival", {}) as Dictionary
	var rival_text := "TARGET --"
	if not rival.is_empty():
		var points_delta := int(rival.get(&"points_delta", 0))
		var points_text := "PACE TARGET"
		if int(rival.get(&"championship_position", 0)) > 0:
			if points_delta > 0:
				points_text = "%dPTS AHEAD" % points_delta
			elif points_delta < 0:
				points_text = "%dPTS BEHIND" % absi(points_delta)
			else:
				points_text = "TIED ON POINTS"
		rival_text = "TARGET %s #%02d  //  %s" % [
			str(rival.get(&"display_name", "RIDER")).to_upper(), int(rival.get(&"number", 0)),
			points_text,
		]
	_event_competition_label.text = "%s\n%s  //  %s" % [first_line, tour_text, rival_text]
	_set_label_color(_event_competition_label, CREAM if is_unlocked else MUTED)


func _entry_effective_time_usec(entry: Dictionary) -> int:
	var time_usec := int(entry.get("time_usec", -1))
	if time_usec < 0:
		return -1
	return time_usec + maxi(int(entry.get("penalty_usec", 0)), 0)


func _event_color(activity: StringName) -> Color:
	match activity:
		&"PINE_ENDURO", &"PINE_WET":
			return Color("9fc744")
		&"MESA_MX", &"MESA_PRACTICE", &"MESA_QUALIFYING", &"MESA_HEAT", &"MESA_LCQ", &"MESA_ELIMINATION", &"MESA_RIVAL", &"MESA_ENDURANCE", &"MESA_RHYTHM":
			return Color("ef6f42")
		&"FREESTYLE":
			return Color("56d6ff")
		&"DAILY_CHALLENGE":
			return Color("55e6b1")
		&"WEEKLY_CHALLENGE":
			return Color("b58cff")
		&"ACADEMY":
			return Color("7bd66f")
		&"DISCOVERY":
			return Color("d8b35a")
		_:
			return AMBER


func _next_event_target(
	activity: StringName,
	challenge_id: StringName = &"",
	exact_best_available: bool = false,
	session_medal_times: Dictionary = {}
) -> String:
	var medal := Profile.get_event_medal(activity, challenge_id)
	match activity:
		&"FREESTYLE":
			if medal in [&"UNRIDDEN", &"FINISHER"]:
				return "NEXT BRONZE 003500"
			if medal == &"BRONZE":
				return "NEXT SILVER 007000"
			if medal == &"SILVER":
				return "NEXT GOLD 012000"
			return "NEXT BEAT BEST"
		&"DISCOVERY":
			if medal in [&"UNRIDDEN", &"FINISHER"]:
				return "NEXT BRONZE 02:00.000"
			if medal == &"BRONZE":
				return "NEXT SILVER 01:20.000"
			if medal == &"SILVER":
				return "NEXT GOLD 00:50.000"
			return "NEXT BEAT BEST"
		&"PINE_ENDURO":
			if medal in [&"UNRIDDEN", &"FINISHER"]:
				return "NEXT BRONZE 07:20.000"
			if medal == &"BRONZE":
				return "NEXT SILVER 05:25.000"
			if medal == &"SILVER":
				return "NEXT GOLD 04:05.000"
			return "NEXT BEAT PB"
		_:
			var event := RaceEventCatalog.get_event(activity)
			var times := session_medal_times if not session_medal_times.is_empty() else event.get(&"medal_times_usec", {}) as Dictionary
			if medal in [&"UNRIDDEN", &"FINISHER"]:
				return "NEXT BRONZE %s" % _format_usec(int(times.get(&"bronze", 300_000_000)))
			if medal == &"BRONZE":
				return "NEXT SILVER %s" % _format_usec(int(times.get(&"silver", 220_000_000)))
			if medal == &"SILVER":
				return "NEXT GOLD %s" % _format_usec(int(times.get(&"gold", 165_000_000)))
			if not challenge_id.is_empty() and not exact_best_available:
				return "NEXT POST PB"
			return "NEXT BEAT PB"


func _is_event_unlocked(activity: StringName) -> bool:
	return RaceEventCatalog.is_available_to_profile(activity, Profile)


func _event_unlock_hint(activity: StringName) -> String:
	if not Profile.is_activity_unlocked(activity):
		return Profile.get_activity_unlock_hint(activity)
	return RaceEventCatalog.get_unlock_hint(activity)


func _completed_event_count() -> int:
	var completed := 0
	for event_id: StringName in EVENTS:
		if Profile.has_completed_event(event_id, _challenge_id_for_activity(event_id)):
			completed += 1
	return completed


func _set_label_color(label: Label, color: Color) -> void:
	label.modulate = Color.WHITE
	label.add_theme_color_override(&"font_color", color)


func _setup_data(setup: StringName) -> Dictionary:
	match setup:
		&"TRAIL":
			return {&"name": "TRAIL KIT", &"tagline": "SOFT, SURE-FOOTED, HARD TO RATTLE", &"description": "Forgiving grip and soft suspension trade straight-line speed for control.", &"power": 5.0, &"grip": 9.0, &"suspension": 9.0, &"speed": 5.0}
		&"ATTACK":
			return {&"name": "ATTACK KIT", &"tagline": "POWER FIRST. CONSEQUENCES LATER.", &"description": "Hard power and jump support trade lateral grip for expert pace.", &"power": 9.0, &"grip": 5.0, &"suspension": 7.0, &"speed": 10.0}
		_:
			return {&"name": "BALANCED", &"tagline": "THE BASELINE THAT NEVER MAKES EXCUSES", &"description": "Predictable power and grip make every Quarry line readable.", &"power": 7.0, &"grip": 7.0, &"suspension": 7.0, &"speed": 7.0}


func _on_profile_changed(_cash: int, _reputation: int, _setup: StringName) -> void:
	if _open:
		_refresh()


func _on_meta_progress_changed(_snapshot: Dictionary) -> void:
	if _open:
		_refresh()


func _format_usec(time_usec: int) -> String:
	var total_msec := maxi(time_usec / 1000, 0)
	return "%02d:%02d.%03d" % [total_msec / 60000, (total_msec / 1000) % 60, total_msec % 1000]


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", color)
	label.add_theme_color_override(&"font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	label.add_theme_constant_override(&"outline_size", maxi(2, int(font_size * 0.07)))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _anchor_rect(control: Control, anchor: Vector2, rect: Rect2) -> void:
	control.anchor_left = anchor.x
	control.anchor_right = anchor.x
	control.anchor_top = anchor.y
	control.anchor_bottom = anchor.y
	control.offset_left = rect.position.x
	control.offset_top = rect.position.y
	control.offset_right = rect.position.x + rect.size.x
	control.offset_bottom = rect.position.y + rect.size.y


func _build_id() -> String:
	var version := str(ProjectSettings.get_setting("application/config/version", "development"))
	return version.split("-", true, 1)[1] if "-" in version else version
