extends Node3D
## Composes the vertical slice and mediates scene-local systems.

const WEEKEND_DIRECTOR_SCRIPT := preload("res://features/career/race_weekend_director.gd")
const CHAMPIONSHIP_SERVICE_SCRIPT := preload("res://features/career/championship_service.gd")
const BIKE_BUILD_SCRIPT := preload("res://features/career/racing_bike_build.gd")
const BIKE_CATALOG_SCRIPT := preload("res://features/career/racing_bike_catalog.gd")
const BIKE_TEST_RIDE_SCRIPT := preload("res://features/career/bike_test_ride.gd")
const PROGRESSION_PAYOFF_SCRIPT := preload("res://features/career/progression_payoff.gd")
const WEB_GAME_TEXT_STATE := preload("res://common/web_game_text_state.gd")
const BIKE_CONDITION_FEEDBACK := preload("res://features/race/bike_condition_feedback.gd")
const QUARRY_SCENE := preload("res://levels/quarry/quarry.tscn")
const PINE_RIDGE_SCENE := preload("res://levels/pine_ridge/pine_ridge.tscn")
const MESA_MX_SCENE := preload("res://levels/mesa_mx/mesa_mx.tscn")
const GARAGE_COMPOSITION_OFFSET_METERS: float = 2.35
const OPPONENT_BUILD_MATCH_WEIGHT: float = 0.65
const OPPONENT_BUILD_MATCH_MIN: float = 0.94
const OPPONENT_BUILD_MATCH_MAX: float = 1.12
const OPPONENT_BUILD_SETUP_FACTORS: Dictionary = {
	&"TRAIL": 0.97,
	&"BALANCED": 1.0,
	&"ATTACK": 1.04,
}

@onready var _bike: DirtBikeController = %Bike
@onready var _level_root: Node3D = %LevelRoot
@onready var _camera: ChaseCamera = %ChaseCamera
@onready var _race: RaceController = %RaceController
@onready var _ghost: GhostController = %GhostController
@onready var _hud: RaceHud = %RaceHud
@onready var _garage: GarageUi = %GarageUi
@onready var _freestyle: FreestyleController = %FreestyleController
@onready var _discovery: DiscoveryController = %DiscoveryController
@onready var _transition: DistrictTransition = %DistrictTransition
@onready var _gameplay_audio: GameplayAudio = %GameplayAudio
@onready var _ride_director: RideDirector = %RideDirector
@onready var _atmosphere: AtmosphereDirector = %AtmosphereDirector
@onready var _race_services: RaceServices = %RaceServices
@onready var _touch_controls: TouchRidingControls = %TouchRidingControls

var _paused: bool = false
var _current_activity: StringName = &"CIRCUIT"
var _transitioning: bool = false
var _smoke_test_enabled: bool = false
var _smoke_test: Node
var _weekend_director: Variant
var _championship_service: Variant
var _active_challenge: Dictionary = {}
var _active_level: Node3D
var _active_track_id: StringName = &""
var _garage_backdrop: Node3D
var _touch_modal_open: bool = false
var _settings_modal_open: bool = false
var _photo_modal_open: bool = false
var _replay_modal_open: bool = false
var _touch_results_visible: bool = false
var _saved_garage_unhandled_input: bool = true
var _progression_run_baseline: Dictionary = {}
var _activity_progression_baselines: Dictionary = {}
var _pending_garage_event: StringName = &""
var _pending_academy_settlement: Dictionary = {}
var _pending_race_settlement: Dictionary = {}
var _pending_close_after_save: bool = false
var _web_game_text_publish_time: float = 0.0
var _test_ride_bike_id: StringName = &""
var _test_ride_bike_name: String = ""
var _test_ride_build: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().auto_accept_quit = false
	if not SaveLifecycle.state_changed.is_connected(_on_save_lifecycle_for_pending_close):
		SaveLifecycle.state_changed.connect(_on_save_lifecycle_for_pending_close)
	if not Profile.meta_progress_changed.is_connected(_on_profile_meta_progress_changed):
		Profile.meta_progress_changed.connect(_on_profile_meta_progress_changed)
	_smoke_test_enabled = &"--smoke-test" in OS.get_cmdline_user_args()
	if _smoke_test_enabled:
		# Career initialization happens before the requested smoke activity. Disable
		# writes first so a weekend bootstrap can never touch the rider's real save.
		Profile.persistence_enabled = false
		# A release smoke must prove the authored starter experience, not whichever
		# bike, parts, tune, wear, or saved build happens to exist on this machine.
		# Reset only the isolated in-memory profile after writes are disabled.
		Profile.reset_profile_for_testing()
		# Build the editor-only path at runtime so the release pack contains neither
		# the excluded test resource nor a misleading embedded resource marker.
		var test_resource_root := "res://features/" + "test" + "ing/"
		var smoke_resource_name := "runtime_" + "smoke_" + "test.gd"
		var smoke_script := load(test_resource_root + smoke_resource_name) as Script
		if smoke_script == null:
			push_error("Smoke-test harness is unavailable in this build.")
			get_tree().quit(1)
			return
		_smoke_test = smoke_script.new() as Node
		_smoke_test.name = "RuntimeSmokeTest"
		add_child(_smoke_test)
	_initialize_career_services()
	# The garage is a fully covered front end, so constructing a complete district
	# here only delays first interaction. Seed route-dependent systems from catalog
	# data and stream the selected district after the ride transition has covered.
	var initial_route := CourseCatalog.get_world_riding_points(CourseCatalog.QUARRY_ID)
	var initial_surface_root: Node3D = null
	_build_garage_backdrop(initial_route)
	_camera.target = _bike
	_camera.set_composition_offset_right(0.0 if _smoke_test_enabled else GARAGE_COMPOSITION_OFFSET_METERS)
	_camera.snap_to_target()
	_hud.initialize(_bike, CourseCatalog.QUARRY_ID, initial_route)
	_bike.telemetry_updated.connect(_hud.update_telemetry)
	_bike.flow_changed.connect(_hud.update_flow)
	_bike.racecraft_state_changed.connect(_hud.update_racecraft_state)
	_bike.racecraft_event.connect(_hud.show_racecraft_event)
	_bike.racecraft_event.connect(_camera.apply_racecraft_feedback)
	_bike.landed.connect(_camera.apply_landing_kick)
	_bike.boost_activated.connect(_camera.apply_boost_punch)
	_bike.airtime_started.connect(_camera.begin_airtime)
	_bike.pack_contacted.connect(_camera.apply_contact_kick)
	_bike.landed.connect(_on_bike_landed)
	_bike.automatic_recovery_requested.connect(_on_bike_automatic_recovery_requested)
	_race.time_updated.connect(_hud.update_race_time)
	_race.breakdown_ready.connect(_hud.show_breakdown)
	_race.field_updated.connect(_hud.update_field)
	_race.race_moment.connect(_hud.show_race_moment)
	if _hud.has_method(&"update_session"):
		_race.session_updated.connect(_hud.update_session)
	if _hud.has_method(&"update_classification"):
		_race.classification_updated.connect(_hud.update_classification)
	if _hud.has_method(&"update_integrity"):
		_race.integrity_updated.connect(_hud.update_integrity)
	_race.results_ready.connect(_on_race_results_ready)
	if _hud.has_method(&"show_results"):
		_race.results_ready.connect(_hud.show_results)
	_freestyle.hud_updated.connect(_hud.update_freestyle)
	_discovery.hud_updated.connect(_hud.update_discovery)
	_garage.ride_requested.connect(_on_ride_requested)
	_garage.test_ride_requested.connect(_on_test_ride_requested)
	_garage.workshop_visibility_changed.connect(_on_workshop_visibility_changed)
	_garage.local_duel_requested.connect(_on_local_duel_requested)
	_garage.event_selection_changed.connect(_on_garage_event_selection_changed)
	_race.initialize(
		_bike,
		_ghost,
		CourseCatalog.QUARRY_ID,
		initial_route,
		initial_surface_root
	)
	_race_services.initialize(_race, _bike, _camera, _hud)
	_race_services.set_riding_camera_active(false)
	_race_services.leaderboard_updated.connect(_hud.update_leaderboard_result)
	_race_services.hotseat_state_changed.connect(_on_hotseat_state_changed)
	_race_services.custom_tour_state_changed.connect(_on_custom_tour_state_changed)
	_race_services.replay_available.connect(_hud.update_replay_available)
	_race_services.replay_state_changed.connect(_hud.update_replay_state)
	_race_services.replay_state_changed.connect(_on_replay_visibility_changed)
	_race_services.photo_mode_changed.connect(_on_photo_mode_changed)
	_race_services.settings_visibility_changed.connect(_on_settings_visibility_changed)
	if not EventBus.activity_completed.is_connected(_on_activity_completed_for_touch):
		EventBus.activity_completed.connect(_on_activity_completed_for_touch)
	if not EventBus.activity_started.is_connected(_on_activity_started_capture_progression):
		EventBus.activity_started.connect(_on_activity_started_capture_progression)
	if not EventBus.activity_attempt_started.is_connected(_on_activity_attempt_started_capture_progression):
		EventBus.activity_attempt_started.connect(_on_activity_attempt_started_capture_progression)
	_garage.bind_competition_source(_race_services)
	_garage.update_competition_context(_current_activity, _ghost.best_time_usec, _active_competition_id())
	_freestyle.initialize(_bike, _ghost)
	_discovery.initialize(_bike, _ghost)
	_gameplay_audio.initialize(_bike, _ride_director)
	_ride_director.initialize(_bike)
	if not EventBus.race_started.is_connected(_on_race_started_apply_session_rules):
		EventBus.race_started.connect(_on_race_started_apply_session_rules)
	_race.race_moment.connect(_ride_director.register_competition_event)
	_ride_director.line_updated.connect(_hud.update_line)
	_ride_director.contract_updated.connect(_hud.update_contract)
	_ride_director.modifier_updated.connect(_hud.update_modifier)
	_ride_director.route_discovered.connect(_camera.apply_route_highlight)
	_ride_director.feat_unlocked.connect(_hud.show_feat)
	_atmosphere.initialize(_bike)
	_atmosphere.bind_environment(initial_surface_root)
	if _smoke_test_enabled:
		_on_ride_requested(Profile.current_setup, _get_requested_test_activity())
		_smoke_test.call(&"initialize", _bike, _camera, _race, _freestyle, _discovery, _transition, _ride_director, _gameplay_audio)
	else:
		_hud.visible = false
		_garage.show_garage()
		_refresh_touch_context()


func _exit_tree() -> void:
	ProceduralSurfaceTexture.clear_cache()


func _on_profile_meta_progress_changed(_snapshot: Dictionary) -> void:
	if _bike == null or not is_instance_valid(_bike):
		return
	_bike.apply_rider_cosmetics(Profile.get_rider_cosmetics())


func _process(delta: float) -> void:
	if not OS.has_feature("web"):
		return
	_web_game_text_publish_time -= delta
	if _web_game_text_publish_time > 0.0:
		return
	_web_game_text_publish_time = 0.10
	WebPlatform.publish_game_text_state(get_web_game_text_state_snapshot())


func get_web_game_text_state_snapshot() -> Dictionary:
	var workshop := _garage.get_workshop_snapshot()
	var garage_prompts := _garage.get_input_prompt_snapshot()
	var garage_briefing := _garage.get_event_briefing_presentation_snapshot()
	var garage_strategy := _garage.get_event_strategy_presentation_snapshot()
	var hud_prompts := _hud.get_control_prompt_snapshot()
	var rider_cosmetics := Profile.get_rider_cosmetics()
	return WEB_GAME_TEXT_STATE.build({
		&"mode": _web_game_mode(),
		&"activity": _current_activity,
		&"paused": _paused,
		&"transitioning": _transitioning,
		&"player": {
			&"bike_id": _test_ride_bike_id if _is_test_ride_active() else Profile.active_bike_id,
			&"test_ride": _is_test_ride_active(),
			&"position": _bike.global_position,
			&"velocity": _bike.linear_velocity,
			&"forward": -_bike.global_transform.basis.z.normalized(),
			&"speed_mps": _bike.get_speed_mps(),
			&"grounded": _bike.is_grounded(),
			&"flow": _bike.get_flow(),
			&"boosting": _bike.is_boosting(),
			&"transmission": _bike.get_transmission_snapshot(),
			&"controls": _bike.get_live_control_snapshot(),
			&"contact": _bike.get_contact_feedback(),
			&"condition": _bike.get_condition_snapshot(),
			&"cosmetics": rider_cosmetics,
			&"equipment_wear": _bike.get_equipment_wear_snapshot(),
		},
		&"session": _race.get_session_snapshot(),
		&"hud": hud_prompts,
		&"landing": _hud.get_landing_projection_presentation_snapshot(),
		&"balance": _hud.get_ground_balance_presentation_snapshot(),
		&"bike_condition": _hud.get_bike_condition_presentation_snapshot(),
		&"camera": {
			&"mode": _camera.get_view_mode(),
			&"fov_degrees": _camera.get_camera_fov(),
		},
		&"graphics": _race_services.get_visual_quality_snapshot(),
		&"captions": _race_services.get_audio_caption_snapshot(),
		&"garage": {
			&"open": _garage.is_open(),
			&"workshop_open": bool(workshop.get(&"open", false)),
			&"event": garage_briefing.get(&"event_id", _current_activity),
			&"setup": garage_strategy.get(&"selected_setup", Profile.current_setup),
			&"status": garage_prompts.get(&"status", ""),
			&"workshop_category": workshop.get(&"category", ""),
			&"workshop_item": workshop.get(&"workshop_item", ""),
			&"workshop_action": workshop.get(&"workshop_action", ""),
			&"workshop_status": workshop.get(&"workshop_status", ""),
			&"rider_number": rider_cosmetics.get(&"rider_number", 17),
			&"rider_number_draft": workshop.get(&"rider_number_draft", 17),
		},
		&"local_duel": _race_services.get_hotseat_presentation_snapshot(),
		&"custom_tour": _race_services.get_custom_tour_presentation_snapshot(),
		&"results": _hud.get_competition_presentation_snapshot(),
		&"save": SaveLifecycle.get_snapshot(),
		&"input_mode": InputRouter.input_mode,
		&"binding_revision": InputRouter.binding_revision,
	})


func _web_game_mode() -> StringName:
	var workshop_open := false
	if _garage.is_open():
		workshop_open = bool(_garage.get_workshop_snapshot().get(&"open", false))
	return resolve_web_game_mode(
		_transitioning,
		_settings_modal_open,
		_photo_modal_open,
		_replay_modal_open,
		_garage.is_open(),
		workshop_open,
		_hud.is_results_visible(),
		_paused,
		_current_activity
	)


static func resolve_web_game_mode(
	transitioning: bool,
	settings_open: bool,
	photo_open: bool,
	replay_open: bool,
	garage_open: bool,
	workshop_open: bool,
	results_visible: bool,
	paused: bool,
	activity: StringName
) -> StringName:
	if transitioning:
		return &"TRANSITION"
	if settings_open:
		return &"SETTINGS"
	if photo_open:
		return &"PHOTO_MODE"
	if replay_open:
		return &"REPLAY"
	if garage_open:
		return &"WORKSHOP" if workshop_open else &"GARAGE"
	if results_visible:
		return &"RESULTS"
	if paused:
		return &"PAUSED"
	if activity == &"FREESTYLE":
		return &"FREESTYLE"
	if activity == &"DISCOVERY":
		return &"DISCOVERY"
	if activity == &"ACADEMY":
		return &"ACADEMY"
	return &"RACE"


func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_CLOSE_REQUEST:
		return
	if SaveLifecycle.is_critical_save_active():
		_pending_close_after_save = true
		return
	get_tree().quit()


func _on_save_lifecycle_for_pending_close(snapshot: Dictionary) -> void:
	if not _pending_close_after_save or int(snapshot.get(&"critical_count", 0)) > 0:
		return
	if StringName(snapshot.get(&"state", &"FAILED")) == &"FAILED":
		_pending_close_after_save = false
		return
	_pending_close_after_save = false
	get_tree().call_deferred(&"quit")


static func should_release_pending_close_after_save(snapshot: Dictionary) -> bool:
	return (
		int(snapshot.get(&"critical_count", 0)) <= 0
		and StringName(snapshot.get(&"state", &"FAILED")) != &"FAILED"
	)


func get_save_close_guard_snapshot() -> Dictionary:
	return {
		&"pending_close": _pending_close_after_save,
		&"critical_save_active": SaveLifecycle.is_critical_save_active(),
		&"auto_accept_quit": get_tree().auto_accept_quit,
	}


func _unhandled_input(event: InputEvent) -> void:
	if _transitioning or _settings_modal_open or _photo_modal_open:
		return
	if event.is_action_pressed(InputRouter.PAUSE) and not event.is_echo():
		_toggle_pause()
		get_viewport().set_input_as_handled()
		return
	if _garage.is_open():
		return
	if _paused:
		return
	if event.is_action_pressed(InputRouter.OPEN_GARAGE) and not event.is_echo():
		_return_to_garage()
		get_viewport().set_input_as_handled()
		return
	if (
		event.is_action_pressed(InputRouter.RESET_BIKE)
		and not event.is_echo()
		and not _replay_modal_open
	):
		var reset_accepted := true
		if RaceEventCatalog.is_race_event(_current_activity):
			reset_accepted = _race.request_player_reset()
		else:
			_bike.reset_to_safe_position()
		EventBus.interface_feedback_requested.emit(
			&"CONFIRM" if reset_accepted else &"DENIED", &"BIKE_RESET"
		)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(InputRouter.RESTART_RUN) and not event.is_echo():
		if _restart_current_activity():
			EventBus.interface_feedback_requested.emit(&"CONFIRM", &"ACTIVITY_RESTART")
		get_viewport().set_input_as_handled()


func _toggle_pause() -> void:
	_paused = not _paused
	get_tree().paused = _paused
	EventBus.game_paused.emit(_paused)
	EventBus.interface_feedback_requested.emit(
		&"CONFIRM" if _paused else &"CANCEL", &"PAUSE"
	)


func _on_ride_requested(setup: StringName, activity: StringName) -> void:
	if _transitioning:
		return
	if _retry_pending_race_settlement():
		return
	if _retry_pending_activity_settlement():
		return
	var profile_activity := OS.get_environment("RIDING_DIRTY_PROFILE_ACTIVITY") == "1"
	var phase_begin_usec := Time.get_ticks_usec()
	_transitioning = true
	_pending_garage_event = &""
	_progression_run_baseline.clear()
	var retrying_pending_activity := (
		activity == &"FREESTYLE"
		and _freestyle.has_method(&"has_pending_settlement")
		and bool(_freestyle.call(&"has_pending_settlement"))
	) or (
		activity == &"DISCOVERY"
		and _discovery.has_method(&"has_pending_settlement")
		and bool(_discovery.call(&"has_pending_settlement"))
	)
	if not retrying_pending_activity:
		_activity_progression_baselines.clear()
	_touch_results_visible = false
	_refresh_touch_context()
	_stop_all_activities()
	_camera.set_composition_offset_right(0.0)
	_race_services.set_riding_camera_active(true)
	# Garage actions can advance or roll over a season while this scene remains
	# alive; resolve the newly persisted services before deriving session rules.
	_refresh_career_services()
	_gameplay_audio.begin_arrangement_prepare(activity)
	var skip_transition := _smoke_test_enabled
	if not skip_transition:
		await _transition.cover(activity)
	phase_begin_usec = _finish_profiled_activity_phase(&"cover", phase_begin_usec, profile_activity)
	_current_activity = activity
	_active_challenge.clear()
	var session: RaceSessionConfig
	if RaceEventCatalog.is_challenge_event(activity):
		_active_challenge = (
			_race_services.get_weekly_challenge()
			if activity == &"WEEKLY_CHALLENGE"
			else _race_services.get_daily_challenge()
		)
		session = RaceEventCatalog.get_challenge_session_config(activity, _active_challenge)
		var local_duel := _race_services.get_hotseat_presentation_snapshot()
		if (
			session != null
			and bool(local_duel.get(&"active", false))
			and StringName(local_duel.get(&"event_id", &"")) == activity
			and str(local_duel.get(&"challenge_id", "")) == str(_active_challenge.get("challenge_id", ""))
		):
			var participant := local_duel.get(&"current_participant", {}) as Dictionary
			var rider_name := str(participant.get("display_name", "RIDER")).to_upper()
			session.display_name = "%s  //  %s" % [session.display_name, rider_name]
			session.rules[&"local_duel"] = true
			session.rules[&"local_duel_rider"] = rider_name
	elif RaceEventCatalog.is_race_event(activity):
		session = RaceEventCatalog.get_session_config(activity)
	elif activity == BIKE_TEST_RIDE_SCRIPT.ACTIVITY_ID and _is_test_ride_active():
		session = BIKE_TEST_RIDE_SCRIPT.create_session(_test_ride_bike_id, _test_ride_bike_name)
	var track_id := session.track_id if session != null else RaceEventCatalog.get_track_id(activity) if RaceEventCatalog.has_event(activity) else CourseCatalog.QUARRY_ID
	_ensure_track_loaded(track_id)
	_gameplay_audio.finish_arrangement_prepare(activity)
	phase_begin_usec = _finish_profiled_activity_phase(&"track_load", phase_begin_usec, profile_activity)
	if session != null:
		if not RaceEventCatalog.is_challenge_event(activity) and not _is_test_ride_active():
			session.bike_class = Profile.selected_bike_class
			_apply_career_session_rules(activity, session)
		var active_build: Dictionary = {}
		if _is_test_ride_active():
			active_build = _test_ride_build.duplicate(true)
		elif Profile.has_method(&"get_active_bike_setup_snapshot"):
			active_build = Profile.call(&"get_active_bike_setup_snapshot") as Dictionary
		apply_career_opponent_build_match(session, active_build, setup)
	_apply_session_transmission_rule(session)
	_apply_session_control_response_rule(session)
	var authoritative_route := get_authoritative_route(track_id)
	var authoritative_surface_root := _get_track_builder(track_id)
	# RaceController owns route preparation internally, so it still receives the
	# builder's untouched route below. The HUD must receive the same prepared
	# projection the controller will race on (notably for reverse events).
	var hud_route := (
		RaceEventCatalog.prepare_route(session, authoritative_route)
		if session != null
		else authoritative_route.duplicate()
	)
	_hud.configure_track(track_id, hud_route)
	phase_begin_usec = _finish_profiled_activity_phase(&"hud_route", phase_begin_usec, profile_activity)
	EventBus.activity_prepared.emit(activity)
	if session != null and _atmosphere.has_method(&"configure_session"):
		_atmosphere.call(&"configure_session", session.weather, session.track_id)
	phase_begin_usec = _finish_profiled_activity_phase(&"event_and_atmosphere", phase_begin_usec, profile_activity)
	if not _is_test_ride_active():
		Profile.set_current_setup(setup)
	var effective_setup := setup
	var effective_assist := Profile.assist_mode
	var effective_assist_configuration := Profile.get_assist_configuration()
	var equalized_challenge := session != null and RaceEventCatalog.is_challenge_event(activity)
	if equalized_challenge:
		effective_setup = StringName(session.rules.get(&"competitive_setup_id", &"BALANCED"))
		effective_assist = &"PRO" if StringName(session.rules.get(&"competitive_assist_mode", &"STANDARD")) == &"LIMITED" else &"SPORT"
		effective_assist_configuration = preload("res://common/riding_assist_config.gd").preset(effective_assist)
	_bike.apply_setup(effective_setup)
	if equalized_challenge:
		_bike.apply_equalized_race_class(session.bike_class)
		_bike.apply_condition(100)
	elif _is_test_ride_active():
		_bike.apply_racing_build(_test_ride_build)
		_bike.apply_condition(100)
	else:
		if Profile.has_method(&"get_active_bike_setup_snapshot"):
			_bike.apply_racing_build(Profile.call(&"get_active_bike_setup_snapshot") as Dictionary)
		_bike.apply_condition(Profile.bike_condition)
	_bike.reset_equipment_wear()
	_bike.apply_session_weather(session.weather if session != null else &"CLEAR")
	_bike.apply_session_surface(session.surface_modifier if session != null else &"PACKED")
	_bike.apply_cosmetic_tier(Profile.get_cosmetic_tier())
	if Profile.has_method(&"get_rider_cosmetics"):
		_bike.apply_rider_cosmetics(Profile.call(&"get_rider_cosmetics") as Dictionary)
	_bike.apply_assist_configuration(effective_assist_configuration, effective_assist)
	if _hud.has_method(&"configure_assists"):
		_hud.call(&"configure_assists", effective_assist, effective_assist_configuration, equalized_challenge)
	phase_begin_usec = _finish_profiled_activity_phase(&"bike_setup", phase_begin_usec, profile_activity)
	match activity:
		&"FREESTYLE":
			_freestyle.start_session()
		&"DISCOVERY":
			_discovery.start_hunt()
		_:
			_race.configure_session(session, authoritative_route, authoritative_surface_root)
			_race.reset_run()
	phase_begin_usec = _finish_profiled_activity_phase(&"activity_setup", phase_begin_usec, profile_activity)
	_camera.snap_to_target()
	_hud.visible = true
	if not skip_transition:
		await _transition.reveal()
	_finish_profiled_activity_phase(&"camera_and_reveal", phase_begin_usec, profile_activity)
	_transitioning = false
	_refresh_touch_context()


func _on_test_ride_requested(bike_id: StringName, setup: StringName) -> void:
	if _transitioning:
		return
	var catalog: Variant = BIKE_CATALOG_SCRIPT.create_default()
	var bike_definition: Dictionary = catalog.get_bike(bike_id)
	var stock_build: Dictionary = BIKE_TEST_RIDE_SCRIPT.create_stock_build(bike_id, catalog, setup)
	if bike_definition.is_empty() or stock_build.is_empty():
		EventBus.interface_feedback_requested.emit(&"DENIED", &"TEST_RIDE_UNAVAILABLE")
		return
	_test_ride_bike_id = bike_id
	_test_ride_bike_name = str(bike_definition.get(&"display_name", bike_id))
	_test_ride_build = stock_build
	_on_ride_requested(setup, BIKE_TEST_RIDE_SCRIPT.ACTIVITY_ID)


func _on_workshop_visibility_changed(open: bool) -> void:
	if is_instance_valid(_touch_controls) and _touch_controls.has_method(&"set_workshop_open"):
		_touch_controls.call(&"set_workshop_open", open)


func _on_local_duel_requested(weekly: bool) -> void:
	var result := _race_services.configure_hotseat([
		{&"profile_id": "local_duel_rider_1", &"display_name": "RIDER 1"},
		{&"profile_id": "local_duel_rider_2", &"display_name": "RIDER 2"},
	], 2, weekly)
	if not bool(result.get("ok", false)):
		EventBus.interface_feedback_requested.emit(&"DENIED", &"LOCAL_DUEL_SAVE")
		return
	var snapshot := result.get("snapshot", {}) as Dictionary
	var event_id := StringName(snapshot.get(&"event_id", &"WEEKLY_CHALLENGE" if weekly else &"DAILY_CHALLENGE"))
	_garage.focus_event_briefing(event_id)
	_garage.refresh_local_duel_state()
	_on_garage_event_selection_changed(event_id)
	_garage.start_selected_ride()


func _on_hotseat_state_changed(_snapshot: Dictionary) -> void:
	_garage.refresh_local_duel_state()
	if _garage.is_open():
		var event_id := StringName(_snapshot.get(&"event_id", &""))
		if not event_id.is_empty():
			_garage.focus_event_briefing(event_id)
			_on_garage_event_selection_changed(event_id)


func _on_custom_tour_state_changed(_snapshot: Dictionary) -> void:
	_garage.refresh_custom_tour_state()
	if _garage.is_open():
		_garage.focus_event_briefing(&"CUSTOM_TOUR")
		_on_garage_event_selection_changed(&"CUSTOM_TOUR")


func _on_garage_event_selection_changed(activity: StringName) -> void:
	if not is_instance_valid(_touch_controls) or not _touch_controls.has_method(&"set_garage_continue_label"):
		return
	var continue_label := "CONTINUE"
	if activity == &"CUSTOM_TOUR":
		var tour := _race_services.get_custom_tour_presentation_snapshot()
		continue_label = (
			"NEXT\nROUND" if bool(tour.get(&"active", false))
			else "NEW\nTOUR" if bool(tour.get(&"completed", false))
			else "START\nTOUR" if bool(tour.get(&"building", false))
			else "BUILD\nTOUR"
		)
	elif activity in [&"DAILY_CHALLENGE", &"WEEKLY_CHALLENGE"]:
		continue_label = "LOCAL\nDUEL"
	_touch_controls.call(
		&"set_garage_continue_label",
		continue_label
	)


func _is_test_ride_active() -> bool:
	return not _test_ride_bike_id.is_empty()


func _clear_test_ride() -> void:
	_test_ride_bike_id = &""
	_test_ride_bike_name = ""
	_test_ride_build.clear()


func _restore_career_bike_runtime() -> void:
	_bike.apply_setup(Profile.current_setup)
	if Profile.has_method(&"get_active_bike_setup_snapshot"):
		_bike.apply_racing_build(Profile.call(&"get_active_bike_setup_snapshot") as Dictionary)
	_bike.apply_condition(Profile.bike_condition)
	_bike.apply_cosmetic_tier(Profile.get_cosmetic_tier())
	if Profile.has_method(&"get_rider_cosmetics"):
		_bike.apply_rider_cosmetics(Profile.call(&"get_rider_cosmetics") as Dictionary)


func _finish_profiled_activity_phase(phase: StringName, begin_usec: int, enabled: bool) -> int:
	var finish_usec := Time.get_ticks_usec()
	if enabled:
		print("ACTIVITY PREPARE PHASE: %s %.3fs" % [String(phase), float(finish_usec - begin_usec) / 1_000_000.0])
	return finish_usec


func _restart_current_activity() -> bool:
	if _retry_pending_race_settlement():
		return false
	if _retry_pending_activity_settlement():
		return false
	if _hud.is_results_visible() and _current_activity in [&"DAILY_CHALLENGE", &"WEEKLY_CHALLENGE"]:
		var local_duel := _race_services.get_hotseat_presentation_snapshot()
		if (
			bool(local_duel.get(&"configured", false))
			and StringName(local_duel.get(&"event_id", &"")) == _current_activity
			and str(local_duel.get(&"challenge_id", "")) == str(_active_challenge.get("challenge_id", ""))
		):
			_return_to_garage()
			return false
	if (
		_hud.is_results_visible()
		and _race_services.get_custom_tour_last_result_event() == _current_activity
	):
		_return_to_garage()
		return false
	_touch_results_visible = false
	_refresh_touch_context()
	if is_instance_valid(_race_services):
		_race_services.stop_transient_presentation()
	match _current_activity:
		&"ACADEMY":
			# Recompose from the shared Academy authority. A plain reset would keep
			# the completed lesson's old RaceSessionConfig and silently rematch it.
			_restart_academy_progression()
			return true
		&"FREESTYLE":
			_freestyle.start_session()
		&"DISCOVERY":
			_discovery.start_hunt()
		_:
			_race.reset_run()
	_camera.snap_to_target()
	return true


func _return_to_garage() -> void:
	var completed_test_ride_name := _test_ride_bike_name
	_stop_all_activities()
	if _is_test_ride_active():
		_restore_career_bike_runtime()
		_clear_test_ride()
	_hud.visible = false
	_touch_results_visible = false
	_camera.set_composition_offset_right(GARAGE_COMPOSITION_OFFSET_METERS)
	_race_services.set_riding_camera_active(false)
	_camera.snap_to_target()
	_garage.update_competition_context(
		_current_activity, _ghost.best_time_usec, _active_competition_id()
	)
	_garage.show_garage()
	if not completed_test_ride_name.is_empty():
		_garage.show_test_ride_complete(completed_test_ride_name)
	if _race_services.get_custom_tour_last_result_event() == _current_activity:
		_garage.focus_event_briefing(&"CUSTOM_TOUR")
	elif not _pending_garage_event.is_empty():
		_garage.focus_event_briefing(_pending_garage_event)
	_refresh_touch_context()
	EventBus.interface_feedback_requested.emit(&"CANCEL", &"RETURN_GARAGE")


func _retry_pending_race_settlement() -> bool:
	var pending: Dictionary = {}
	var settlement_override: Dictionary = {}
	if not _pending_academy_settlement.is_empty():
		pending = _pending_academy_settlement.duplicate(true)
		var retry_lesson_id := StringName(pending.get(&"lesson_id", &""))
		var retry_metrics_value: Variant = pending.get(&"metrics", {})
		settlement_override = {
			&"lesson_id": retry_lesson_id,
			&"metrics": (
				(retry_metrics_value as Dictionary).duplicate(true)
				if retry_metrics_value is Dictionary else {}
			),
		}
	elif not _pending_race_settlement.is_empty():
		pending = _pending_race_settlement.duplicate(true)
	else:
		return false
	var retry_result_value: Variant = pending.get(&"result", {})
	if not retry_result_value is Dictionary:
		push_warning("Pending race settlement has no immutable result payload; retry refused.")
		return true
	var retry_result := (retry_result_value as Dictionary).duplicate(true)
	if not settlement_override.is_empty():
		var retry_lesson_id := StringName(settlement_override.get(&"lesson_id", &""))
		var payload_lesson_id := StringName(retry_result.get(&"academy_lesson_id", &""))
		var retry_metrics_value: Variant = settlement_override.get(&"metrics", {})
		if (
			retry_lesson_id.is_empty()
			or payload_lesson_id != retry_lesson_id
			or not retry_metrics_value is Dictionary
		):
			push_warning("Pending Academy settlement has an invalid immutable identity; retry refused.")
			return true
	if is_instance_valid(_race_services):
		_race_services.stop_transient_presentation()
	_garage.hide_garage()
	_hud.visible = true
	_on_race_results_ready(retry_result, settlement_override)
	if _hud.has_method(&"show_results"):
		_hud.show_results(retry_result)
	return true


func _retry_pending_activity_settlement() -> bool:
	if _freestyle.has_method(&"has_pending_settlement") and bool(_freestyle.call(&"has_pending_settlement")):
		_garage.hide_garage()
		_hud.visible = true
		_freestyle.start_session()
		return true
	if _discovery.has_method(&"has_pending_settlement") and bool(_discovery.call(&"has_pending_settlement")):
		_garage.hide_garage()
		_hud.visible = true
		_discovery.start_hunt()
		return true
	return false


func _restart_academy_progression() -> void:
	var session := RaceEventCatalog.get_session_config(&"ACADEMY")
	if session == null:
		return
	session.bike_class = Profile.selected_bike_class
	_apply_session_transmission_rule(session)
	_apply_session_control_response_rule(session)
	_ensure_track_loaded(session.track_id)
	var authoritative_route := get_authoritative_route(session.track_id)
	var authoritative_surface_root := _get_track_builder(session.track_id)
	_hud.configure_track(session.track_id, authoritative_route)
	_bike.reset_equipment_wear()
	_bike.apply_session_weather(session.weather)
	_bike.apply_session_surface(session.surface_modifier)
	_race.configure_session(session, authoritative_route, authoritative_surface_root)
	EventBus.activity_prepared.emit(&"ACADEMY")
	_race.reset_run()
	_camera.snap_to_target()


func _stop_all_activities() -> void:
	if is_instance_valid(_race_services):
		_race_services.stop_transient_presentation()
		_race_services.clear_activity_transmission_override()
		_race_services.clear_activity_control_response_override()
	_race.enter_waiting()
	_freestyle.enter_waiting()
	_discovery.enter_waiting()


func _apply_session_transmission_rule(session: RaceSessionConfig) -> void:
	if not is_instance_valid(_race_services):
		return
	var forced_mode := (
		StringName(session.rules.get(&"forced_transmission_mode", &""))
		if session != null else &""
	)
	if forced_mode in [&"AUTOMATIC", &"MANUAL"]:
		_race_services.set_activity_transmission_override(forced_mode, true)
	else:
		# Lock the rider's preference at activity composition so Settings cannot
		# mutate physics after the competitive signature and replay identity bind.
		_race_services.set_activity_transmission_override(
			_race_services.get_preferred_transmission_mode(), false
		)


func _apply_session_control_response_rule(session: RaceSessionConfig) -> void:
	if not is_instance_valid(_race_services):
		return
	# Deadzones, response curves, and riding sensitivities all change physical
	# lap potential. Freeze the exact preferred values at activity composition;
	# Settings can safely store a new preference for the next event.
	var forced_response: Dictionary = (
		(session.rules.get(&"forced_control_response", {}) as Dictionary).duplicate(true)
		if session != null else {}
	)
	_race_services.set_activity_control_response_override(
		forced_response
		if not forced_response.is_empty()
		else _race_services.get_preferred_control_response()
	)


func _get_requested_test_activity() -> StringName:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--activity="):
			var requested := StringName(argument.trim_prefix("--activity=").to_upper())
			if RaceEventCatalog.has_event(requested):
				return requested
	return &"CIRCUIT"


func get_authoritative_route(track_id: StringName) -> PackedVector3Array:
	var builder := _get_track_builder(track_id)
	if builder != null and builder.has_method(&"get_authoritative_route_world"):
		var route: PackedVector3Array = builder.call(&"get_authoritative_route_world")
		if route.size() >= 2:
			return route.duplicate()
	push_error("Built track did not provide an authoritative route for %s." % String(track_id))
	# Isolated/editor fallback. A normal Main scene always obtains the route from
	# the already-built level child before configuring HUD or opponents.
	return CourseCatalog.get_world_riding_points(track_id)


func _get_track_builder(track_id: StringName) -> Node3D:
	if _active_level != null and is_instance_valid(_active_level) and track_id == _active_track_id:
		return _active_level
	return null


func _ensure_track_loaded(track_id: StringName) -> void:
	if _active_level != null and is_instance_valid(_active_level) and track_id == _active_track_id:
		return
	_clear_garage_backdrop()
	if _active_level != null and is_instance_valid(_active_level):
		_level_root.remove_child(_active_level)
		_active_level.queue_free()
	_active_level = _track_scene(track_id).instantiate() as Node3D
	_active_track_id = track_id
	_active_level.set_meta(&"streamed_track_id", track_id)
	_level_root.add_child(_active_level)
	if is_instance_valid(_atmosphere):
		_atmosphere.bind_environment(_active_level)
	if is_instance_valid(_race_services):
		_race_services.refresh_visual_quality()


func _build_garage_backdrop(initial_route: PackedVector3Array) -> void:
	# Preserve the lit bike-and-dirt presentation behind the garage without paying
	# to construct a race district. This preview is render-only and is removed as
	# soon as the selected track begins streaming under the covered transition.
	_garage_backdrop = Node3D.new()
	_garage_backdrop.name = "GarageBackdrop"
	_level_root.add_child(_garage_backdrop)

	var world_environment := WorldEnvironment.new()
	world_environment.name = "GarageWorldEnvironment"
	var environment := Environment.new()
	# A flat preview background avoids allocating a second radiance cubemap that
	# would be discarded moments later when the full district environment arrives.
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("284858")
	environment.background_energy_multiplier = 0.72
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("8092a2")
	# The garage card darkens the 3D view heavily; a modest preview-only lift keeps
	# the bike silhouette and warm dirt recognizable without reducing UI contrast.
	environment.ambient_light_energy = 0.9
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = Color("879ba5")
	environment.fog_light_energy = 0.38
	environment.fog_density = 0.0028
	world_environment.environment = environment
	_garage_backdrop.add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.name = "GarageSun"
	sun.rotation_degrees = Vector3(-52.0, -34.0, 0.0)
	sun.light_color = Color("ffd09b")
	sun.light_energy = 1.28
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	_garage_backdrop.add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.name = "GarageSkyFill"
	fill.rotation_degrees = Vector3(42.0, 140.0, 0.0)
	fill.light_color = Color("6d91b3")
	fill.light_energy = 0.58
	fill.shadow_enabled = false
	_garage_backdrop.add_child(fill)

	var spawn := CourseCatalog.get_spawn_transform(CourseCatalog.QUARRY_ID, initial_route)
	var ground_mesh := BoxMesh.new()
	ground_mesh.size = Vector3(120.0, 1.0, 120.0)
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color("725744")
	ground_material.roughness = 1.0
	ground_mesh.material = ground_material
	var ground := MeshInstance3D.new()
	ground.name = "GarageDirtPreview"
	ground.mesh = ground_mesh
	ground.position = spawn.origin - Vector3.UP * 0.75
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_garage_backdrop.add_child(ground)


func _clear_garage_backdrop() -> void:
	if _garage_backdrop == null or not is_instance_valid(_garage_backdrop):
		return
	if _garage_backdrop.get_parent() != null:
		_garage_backdrop.get_parent().remove_child(_garage_backdrop)
	_garage_backdrop.queue_free()
	_garage_backdrop = null


func _track_scene(track_id: StringName) -> PackedScene:
	if track_id == CourseCatalog.PINE_ID:
		return PINE_RIDGE_SCENE
	if track_id == CourseCatalog.MESA_MX_ID:
		return MESA_MX_SCENE
	return QUARRY_SCENE


func _initialize_career_services() -> void:
	_championship_service = Profile.call(&"get_championship_service") if Profile.has_method(&"get_championship_service") else null
	if _championship_service == null:
		_championship_service = CHAMPIONSHIP_SERVICE_SCRIPT.create_default()
		if Profile.has_method(&"set_championship_snapshot"):
			Profile.call(&"set_championship_snapshot", _championship_service.to_dictionary())

	_weekend_director = Profile.call(&"get_race_weekend_director") if Profile.has_method(&"get_race_weekend_director") else null
	var weekend_changed := false
	if _weekend_director == null:
		_weekend_director = WEEKEND_DIRECTOR_SCRIPT.create(RaceEventCatalog.get_default_weekend_config())
		weekend_changed = true
	if _weekend_director.get_current_phase() == &"IDLE":
		_weekend_director.start_weekend()
		weekend_changed = true
	# Profile.persistence_enabled is already false for smoke runs, so this keeps
	# the in-memory smoke flow realistic without touching disk or localStorage.
	if weekend_changed and Profile.has_method(&"set_race_weekend_snapshot"):
		Profile.call(&"set_race_weekend_snapshot", _weekend_director.to_dictionary())


func _refresh_career_services() -> void:
	if Profile.has_method(&"get_championship_service"):
		var stored_championship: Variant = Profile.call(&"get_championship_service")
		if stored_championship != null:
			_championship_service = stored_championship
	if Profile.has_method(&"get_race_weekend_director"):
		var stored_weekend: Variant = Profile.call(&"get_race_weekend_director")
		if stored_weekend != null:
			_weekend_director = stored_weekend


func _apply_career_session_rules(activity: StringName, session: RaceSessionConfig) -> void:
	if session == null or _weekend_director == null or not RaceEventCatalog.is_weekend_event(activity):
		return
	var phase := RaceEventCatalog.get_weekend_phase(activity)
	var current_phase := StringName(_weekend_director.get_current_phase())
	var standalone_rules := session.rules.duplicate(true)
	standalone_rules[&"weekend_id"] = StringName(_weekend_director.weekend_id)
	standalone_rules[&"weekend_phase"] = phase
	standalone_rules[&"weekend_managed"] = false
	if current_phase != phase:
		session.rules = standalone_rules
		return
	var expected_entrant_ids := _string_name_array(_weekend_director.get_session_entrant_ids(phase))
	# A player-owned race session cannot represent an AI-only transfer race. The
	# director resolves those phases before exposing its next production action.
	if not expected_entrant_ids.has(&"PLAYER"):
		session.rules = standalone_rules
		return
	var entrant_ids := expected_entrant_ids.duplicate()
	var gate_order: Array[StringName] = []

	match phase:
		&"PRACTICE":
			entrant_ids = _limit_weekend_field(entrant_ids, session.opponent_count)
		&"QUALIFYING":
			entrant_ids.assign([&"PLAYER"])
			session.opponent_count = 0
			session.field_size = 1
		&"HEAT":
			entrant_ids = _limit_weekend_field(entrant_ids, session.opponent_count)
			gate_order = _string_name_array(_weekend_director.get_gate_order())
		&"LCQ":
			entrant_ids = _limit_weekend_field(entrant_ids, 5)
			gate_order = entrant_ids.duplicate()
		&"MAIN":
			entrant_ids = _limit_weekend_field(entrant_ids, 9)
			gate_order = entrant_ids.duplicate()

	if phase != &"QUALIFYING":
		session.opponent_count = clampi(_opponent_count(entrant_ids), 0, 11)
		session.field_size = session.opponent_count + 1
	var rules := session.rules.duplicate(true)
	rules[&"weekend_id"] = StringName(_weekend_director.weekend_id)
	rules[&"weekend_phase"] = phase
	rules[&"weekend_managed"] = true
	rules[&"entrant_ids"] = entrant_ids.duplicate()
	rules[&"weekend_expected_entrant_ids"] = expected_entrant_ids.duplicate()
	if not gate_order.is_empty():
		rules[&"gate_order"] = gate_order.duplicate()
	session.rules = rules


static func resolve_opponent_build_match_projection(
	build_snapshot: Dictionary,
	setup: StringName = &"BALANCED"
) -> Dictionary:
	## Career opponents inherit a bounded majority of the player's forward-performance
	## improvement, including part of the selected setup's pace envelope. Upgrades
	## therefore keep an advantage while the field does not become obsolete as the
	## owned bike develops. Missing legacy snapshots are
	## deliberately neutral instead of guessing from incomplete save data.
	var setup_id := StringName(String(setup).strip_edges().to_upper())
	if not OPPONENT_BUILD_SETUP_FACTORS.has(setup_id):
		setup_id = &"BALANCED"
	var setup_factor := float(OPPONENT_BUILD_SETUP_FACTORS.get(setup_id, 1.0))
	var neutral := {
		&"drive_factor": 1.0,
		&"speed_factor": 1.0,
		&"setup_id": setup_id,
		&"setup_factor": setup_factor,
		&"performance_scale": 1.0,
		&"match_scale": 1.0,
		&"match_weight": OPPONENT_BUILD_MATCH_WEIGHT,
	}
	var stats := build_snapshot.get(&"stats", {}) as Dictionary
	if stats.is_empty():
		return neutral
	var factors: Dictionary = BIKE_BUILD_SCRIPT.runtime_factors(stats)
	var drive_factor := clampf(float(factors.get(&"drive", 1.0)), 0.86, 1.22)
	var speed_factor := clampf(float(factors.get(&"speed", 1.0)), 0.92, 1.28)
	var performance_scale := (drive_factor * 0.45 + speed_factor * 0.55) * setup_factor
	var match_scale := clampf(
		lerpf(1.0, performance_scale, OPPONENT_BUILD_MATCH_WEIGHT),
		OPPONENT_BUILD_MATCH_MIN,
		OPPONENT_BUILD_MATCH_MAX
	)
	return {
		&"drive_factor": snappedf(drive_factor, 0.001),
		&"speed_factor": snappedf(speed_factor, 0.001),
		&"setup_id": setup_id,
		&"setup_factor": setup_factor,
		&"performance_scale": snappedf(performance_scale, 0.001),
		&"match_scale": snappedf(match_scale, 0.001),
		&"match_weight": OPPONENT_BUILD_MATCH_WEIGHT,
	}


static func apply_career_opponent_build_match(
	session: RaceSessionConfig,
	build_snapshot: Dictionary,
	setup: StringName = &"BALANCED"
) -> bool:
	## `player_difficulty_mode` is the ordinary career-race marker. Challenges are
	## equalized and Academy grading is fixed, so neither may inherit local upgrades.
	if session == null or not session.rules.has(&"player_difficulty_mode"):
		return false
	var projection := resolve_opponent_build_match_projection(build_snapshot, setup)
	var rules := session.rules.duplicate(true)
	rules[&"opponent_build_performance_scale"] = float(projection.get(&"performance_scale", 1.0))
	rules[&"opponent_build_match_scale"] = float(projection.get(&"match_scale", 1.0))
	rules[&"opponent_build_match_weight"] = float(projection.get(&"match_weight", OPPONENT_BUILD_MATCH_WEIGHT))
	rules[&"opponent_build_setup_id"] = StringName(projection.get(&"setup_id", &"BALANCED"))
	rules[&"opponent_build_setup_factor"] = float(projection.get(&"setup_factor", 1.0))
	session.rules = rules
	return true


func _default_weekend_order() -> Array[StringName]:
	var order: Array[StringName] = []
	var weekend_config := RaceEventCatalog.get_default_weekend_config()
	var entrants: Variant = weekend_config.get(&"entrants", [])
	if entrants is Array:
		for raw_entrant: Variant in entrants:
			if raw_entrant is Dictionary:
				var rider_id := StringName((raw_entrant as Dictionary).get(&"rider_id", &""))
				if not rider_id.is_empty():
					order.append(rider_id)
	return order


func _limit_weekend_field(entrant_ids: Array[StringName], opponent_limit: int) -> Array[StringName]:
	var limited: Array[StringName] = []
	if entrant_ids.has(&"PLAYER"):
		limited.append(&"PLAYER")
	for rider_id: StringName in entrant_ids:
		if rider_id == &"PLAYER" or limited.has(rider_id) or limited.size() >= opponent_limit + 1:
			continue
		limited.append(rider_id)
	return limited


func _opponent_count(entrant_ids: Array[StringName]) -> int:
	var count := 0
	for rider_id: StringName in entrant_ids:
		if rider_id != &"PLAYER":
			count += 1
	return count


func _string_name_array(value: Variant) -> Array[StringName]:
	var output: Array[StringName] = []
	if value is Array or value is PackedStringArray:
		for raw_value: Variant in value:
			var rider_id := StringName(raw_value)
			if not rider_id.is_empty() and not output.has(rider_id):
				output.append(rider_id)
	return output


func _dictionary_array(value: Variant) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	if value is Array:
		for raw_value: Variant in value:
			if raw_value is Dictionary:
				output.append((raw_value as Dictionary).duplicate(true))
	return output


func _on_race_results_ready(
	result: Dictionary,
	academy_settlement_override: Dictionary = {}
) -> void:
	_touch_results_visible = true
	_refresh_touch_context()
	if _current_activity == BIKE_TEST_RIDE_SCRIPT.ACTIVITY_ID and _is_test_ride_active():
		var practice_result: Dictionary = BIKE_TEST_RIDE_SCRIPT.sanitize_result(
			result, _test_ride_bike_id
		)
		_pending_garage_event = &""
		_progression_run_baseline.clear()
		result.clear()
		result.merge(practice_result, true)
		return
	if RaceEventCatalog.is_challenge_event(_current_activity):
		if _active_challenge.is_empty():
			_mark_result_invalid(result, "CHALLENGE_CONTEXT_MISSING")
		var expected_challenge_id := str(_active_challenge.get("challenge_id", ""))
		var expected_competition_id := StringName(_active_challenge.get("competition_id", &""))
		var actual_challenge_id := str(result.get(&"challenge_id", ""))
		var actual_competition_id := StringName(result.get(&"competition_id", &""))
		if (
			expected_challenge_id.is_empty()
			or expected_competition_id.is_empty()
			or actual_challenge_id != expected_challenge_id
			or actual_competition_id != expected_competition_id
		):
			_mark_result_invalid(result, "CHALLENGE_IDENTITY_MISMATCH")
		result[&"challenge_id"] = expected_challenge_id
		result[&"competition_id"] = expected_competition_id
		result[&"challenge_kind"] = StringName(str(_active_challenge.get("kind", "DAILY")).to_upper())
		result[&"modifiers"] = (_active_challenge.get("modifiers", []) as Array).duplicate()
		result[&"challenge_ends_unix"] = int(_active_challenge.get("ends_unix", 0))
		var expected_signature := str(_active_challenge.get("run_signature", ""))
		if expected_signature.is_empty() or str(result.get(&"signature", "")) != expected_signature:
			_mark_result_invalid(result, "CHALLENGE_SIGNATURE_MISMATCH")
	var progression_before := (
		_progression_run_baseline.duplicate(true)
		if not _progression_run_baseline.is_empty()
		else PROGRESSION_PAYOFF_SCRIPT.capture(Profile)
	)
	var structured_result := result.duplicate(true)
	if not bool(structured_result.get(&"valid", true)):
		structured_result[&"medal"] = &"NO_AWARD"
		structured_result[&"championship_points"] = 0
		structured_result[&"rewards"] = _zero_race_rewards(structured_result.get(&"rewards", {}) as Dictionary)
	var session_rules := _race.get_session_config().rules
	var weekend_managed := bool(session_rules.get(&"weekend_managed", false))
	if weekend_managed and _weekend_director != null and RaceEventCatalog.is_weekend_event(_current_activity):
		var weekend_phase := RaceEventCatalog.get_weekend_phase(_current_activity)
		if StringName(_weekend_director.get_current_phase()) == weekend_phase:
			if weekend_phase == &"QUALIFYING" and _weekend_director.has_method(&"prepare_session_classification"):
				var prepared_classification: Array[Dictionary] = _weekend_director.prepare_session_classification(
					weekend_phase,
					_dictionary_array(structured_result.get(&"classification", []))
				)
				structured_result[&"classification"] = prepared_classification
				for racer: Dictionary in prepared_classification:
					if StringName(racer.get(&"rider_id", &"")) == &"PLAYER":
						structured_result[&"player_position"] = int(racer.get(&"position", 0))
						break
			structured_result[&"weekend_id"] = StringName(_weekend_director.weekend_id)
			structured_result[&"weekend_phase"] = weekend_phase
			structured_result[&"weekend_managed"] = true
	if _championship_service != null:
		var next_round: Dictionary = _championship_service.get_next_round()
		var weekend_main_authorized := (
			_current_activity != &"MESA_MX"
			or (
				weekend_managed
				and StringName(session_rules.get(&"weekend_phase", &"")) == &"MAIN"
				and StringName(session_rules.get(&"weekend_id", &"")) == &"RED_MESA_OPEN"
			)
		)
		if weekend_main_authorized and StringName(next_round.get(&"event_id", &"")) == _current_activity:
			structured_result[&"round_id"] = StringName(next_round.get(&"round_id", &""))
	# Contracts settle during the ride, before the result authority runs. Keeping
	# this boundary lets a DNF truthfully retain a sponsor payout without also
	# exposing any progression mutation caused by an unclassified result.
	var progression_pre_settlement: Dictionary = PROGRESSION_PAYOFF_SCRIPT.capture(Profile)
	var profile_summary: Dictionary = {}
	var settlement_receipt: Dictionary = {}
	var academy_evaluation: Dictionary = {}
	var academy_lesson_id := StringName(session_rules.get(&"academy_lesson_id", &""))
	var academy_metrics_value: Variant = structured_result.get(&"academy_metrics", {})
	var academy_metrics: Dictionary = (
		(academy_metrics_value as Dictionary).duplicate(true)
		if academy_metrics_value is Dictionary else {}
	)
	if not academy_settlement_override.is_empty():
		academy_lesson_id = StringName(academy_settlement_override.get(&"lesson_id", &""))
		var override_metrics_value: Variant = academy_settlement_override.get(&"metrics", {})
		academy_metrics = (
			(override_metrics_value as Dictionary).duplicate(true)
			if override_metrics_value is Dictionary else {}
		)
	var is_academy_result := StringName(structured_result.get(&"event_id", _current_activity)) == &"ACADEMY"
	if is_academy_result:
		structured_result[&"academy_lesson_id"] = academy_lesson_id
		if academy_lesson_id.is_empty():
			settlement_receipt = {
				&"accepted": false, &"duplicate": false, &"durable": false,
				&"reason": &"MISSING_ACADEMY_LESSON",
			}
		elif Profile.has_method(&"settle_academy_race_result"):
			settlement_receipt = Profile.call(
				&"settle_academy_race_result",
				structured_result,
				academy_lesson_id,
				academy_metrics
			) as Dictionary
		else:
			settlement_receipt = {
				&"accepted": false, &"duplicate": false, &"durable": false,
				&"reason": &"SETTLEMENT_UNAVAILABLE",
			}
		var race_summary_value: Variant = settlement_receipt.get(&"race_summary", {})
		if race_summary_value is Dictionary:
			profile_summary = (race_summary_value as Dictionary).duplicate(true)
		var academy_evaluation_value: Variant = settlement_receipt.get(&"academy_evaluation", {})
		if academy_evaluation_value is Dictionary:
			academy_evaluation = (academy_evaluation_value as Dictionary).duplicate(true)
		structured_result[&"academy_lesson_id"] = academy_lesson_id
		if (
			StringName(settlement_receipt.get(&"reason", &"")) == &"SAVE_FAILED"
			and bool(settlement_receipt.get(&"retryable", false))
		):
			_pending_academy_settlement = {
				&"result": structured_result.duplicate(true),
				&"lesson_id": academy_lesson_id,
				&"metrics": academy_metrics.duplicate(true),
			}
		else:
			_pending_academy_settlement.clear()
		if not academy_evaluation.is_empty():
			structured_result[&"academy_evaluation"] = academy_evaluation.duplicate(true)
	else:
		if Profile.has_method(&"record_race_result"):
			profile_summary = Profile.call(&"record_race_result", structured_result, true) as Dictionary
			settlement_receipt = profile_summary.duplicate(true)
		else:
			settlement_receipt = {
				&"accepted": false, &"duplicate": false, &"durable": false,
				&"reason": &"SETTLEMENT_UNAVAILABLE",
			}
		if (
			StringName(settlement_receipt.get(&"reason", &"")) == &"SAVE_FAILED"
			and bool(settlement_receipt.get(&"retryable", false))
		):
			_pending_race_settlement = {
				&"result": structured_result.duplicate(true),
				&"event_id": StringName(structured_result.get(&"event_id", _current_activity)),
			}
		else:
			_pending_race_settlement.clear()
	var granted_rewards := profile_summary.get(&"rewards_granted", {&"cash": 0, &"reputation": 0}) as Dictionary
	var academy_credited := academy_evaluation.get(
		&"credited_rewards", {&"cash": 0, &"reputation": 0}
	) as Dictionary
	var academy_cash := int(academy_credited.get(&"cash", academy_credited.get(&"credits", 0)))
	var academy_reputation := int(academy_credited.get(&"reputation", 0))
	var credited_cash := int(granted_rewards.get(&"cash", 0)) + academy_cash
	var credited_reputation := int(granted_rewards.get(&"reputation", 0)) + academy_reputation
	var displayed_rewards := structured_result.get(&"rewards", {}) as Dictionary
	displayed_rewards[&"cash"] = credited_cash
	displayed_rewards[&"reputation"] = credited_reputation
	displayed_rewards[&"credited_cash"] = credited_cash
	displayed_rewards[&"credited_reputation"] = credited_reputation
	if is_academy_result:
		displayed_rewards[&"academy_cash"] = academy_cash
		displayed_rewards[&"academy_reputation"] = academy_reputation
	structured_result[&"rewards"] = displayed_rewards
	if is_academy_result and not academy_evaluation.is_empty():
		var next_academy_lesson := RaceEventCatalog.get_active_academy_lesson()
		structured_result[&"academy_next_lesson_id"] = StringName(next_academy_lesson.get(&"lesson_id", &""))
		structured_result[&"academy_next_lesson_name"] = str(
			next_academy_lesson.get(&"display_name", "ACADEMY COMPLETE")
		).to_upper()
	_refresh_career_services()
	var progression_after: Dictionary = PROGRESSION_PAYOFF_SCRIPT.capture(Profile)
	var result_status := StringName(profile_summary.get(&"status", &""))
	var receipt_accepted := bool(settlement_receipt.get(&"accepted", profile_summary.get(&"accepted", false)))
	var receipt_duplicate := bool(settlement_receipt.get(&"duplicate", profile_summary.get(&"duplicate", false)))
	var receipt_durable := bool(settlement_receipt.get(&"durable", receipt_accepted or receipt_duplicate))
	var receipt_reason := StringName(settlement_receipt.get(
		&"reason", &"DUPLICATE" if receipt_duplicate else (&"SETTLED" if receipt_accepted else &"REJECTED")
	))
	var result_valid := bool(profile_summary.get(&"valid", structured_result.get(&"valid", true)))
	var classified_eligible := bool(settlement_receipt.get(
		&"classified_eligible",
		result_valid and result_status in [&"FINISHED", &"CLASSIFIED"]
	))
	var settlement_accepted := (
		receipt_accepted
		and receipt_durable
		and (
			classified_eligible
			if is_academy_result
			else result_valid and result_status in [&"FINISHED", &"CLASSIFIED"]
		)
	)
	var career_payoff: Dictionary = PROGRESSION_PAYOFF_SCRIPT.resolve_run(
		progression_before,
		progression_pre_settlement,
		progression_after,
		settlement_accepted
	)
	career_payoff[&"accepted"] = settlement_accepted
	career_payoff[&"duplicate"] = receipt_duplicate
	career_payoff[&"durable"] = receipt_durable
	career_payoff[&"reason"] = receipt_reason
	career_payoff[&"valid"] = result_valid
	career_payoff[&"status"] = result_status
	career_payoff[&"classified_eligible"] = classified_eligible
	career_payoff[&"rewards_granted"] = {
		&"cash": credited_cash,
		&"reputation": credited_reputation,
	}
	structured_result[&"career_payoff"] = career_payoff
	var next_event := RaceEventCatalog.get_recommended_event()
	var next_event_data := RaceEventCatalog.get_event(next_event)
	structured_result[&"next_event_id"] = next_event
	structured_result[&"next_event_name"] = str(
		next_event_data.get(&"display_name", String(next_event))
	).to_upper()
	structured_result[&"next_event_track_id"] = StringName(next_event_data.get(&"track_id", &"QUARRY"))
	structured_result[&"next_event_format"] = StringName(next_event_data.get(&"format", &"CIRCUIT"))
	structured_result[&"next_event_laps"] = maxi(int(next_event_data.get(&"laps", 1)), 1)
	structured_result[&"next_event_medal_times_usec"] = (
		(next_event_data.get(&"medal_times_usec", {}) as Dictionary).duplicate(true)
	)
	_pending_garage_event = next_event
	if not bool(settlement_receipt.get(&"retryable", false)):
		_progression_run_baseline.clear()
	result.clear()
	result.merge(structured_result, true)


func _on_activity_completed_for_touch(summary: Dictionary) -> void:
	var activity := StringName(summary.get(&"activity_id", &""))
	var run_id := str(summary.get(&"run_id", "")).strip_edges()
	var receipt_accepted := bool(summary.get(&"accepted", false))
	var receipt_duplicate := bool(summary.get(&"duplicate", false))
	var receipt_retryable := bool(summary.get(&"retryable", false))
	var receipt_reason := StringName(summary.get(&"reason", &"UNKNOWN"))
	var has_baseline := not run_id.is_empty() and _activity_progression_baselines.has(run_id)
	var baseline_value: Variant = _activity_progression_baselines.get(run_id, {})
	if not has_baseline or not baseline_value is Dictionary:
		# A rejected begin has no progression baseline but still owns the activity's
		# failure card. A delayed abandoned-run receipt must not disturb a newer ride.
		if receipt_reason == &"STALE_OR_ABANDONED_RUN":
			return
		_touch_results_visible = true
		_refresh_touch_context()
		_pending_garage_event = RaceEventCatalog.get_recommended_event()
		return
	var baseline_entry := baseline_value as Dictionary
	if StringName(baseline_entry.get(&"activity_id", &"")) != activity:
		return
	if receipt_accepted or receipt_duplicate or not receipt_retryable:
		_activity_progression_baselines.erase(run_id)
	_touch_results_visible = true
	_refresh_touch_context()
	var progression_before_value: Variant = baseline_entry.get(&"progression", {})
	if progression_before_value is Dictionary and _hud.has_method(&"show_activity_progression_payoff"):
		var activity_payoff: Dictionary = PROGRESSION_PAYOFF_SCRIPT.diff(
			progression_before_value as Dictionary, PROGRESSION_PAYOFF_SCRIPT.capture(Profile)
		)
		activity_payoff[&"accepted"] = receipt_accepted
		activity_payoff[&"duplicate"] = receipt_duplicate
		activity_payoff[&"durable"] = bool(summary.get(
			&"durable", receipt_accepted or receipt_duplicate
		))
		activity_payoff[&"reason"] = receipt_reason
		activity_payoff[&"valid"] = bool(summary.get(&"valid", receipt_accepted))
		activity_payoff[&"activity_id"] = activity
		activity_payoff[&"run_id"] = run_id
		var rewards_value: Variant = summary.get(&"rewards_granted", {})
		activity_payoff[&"rewards_granted"] = (
			(rewards_value as Dictionary).duplicate(true) if rewards_value is Dictionary else {}
		)
		_hud.call(&"show_activity_progression_payoff", activity_payoff)
	var next_event := RaceEventCatalog.get_recommended_event()
	_pending_garage_event = next_event


func _on_activity_started_capture_progression(activity: StringName) -> void:
	if activity in [&"FREESTYLE", &"DISCOVERY", BIKE_TEST_RIDE_SCRIPT.ACTIVITY_ID]:
		return
	_progression_run_baseline = PROGRESSION_PAYOFF_SCRIPT.capture(Profile)


func _on_activity_attempt_started_capture_progression(context: Dictionary) -> void:
	if not bool(context.get(&"accepted", false)):
		return
	var activity := StringName(context.get(&"activity_id", &""))
	var run_id := str(context.get(&"run_id", "")).strip_edges()
	if activity not in [&"FREESTYLE", &"DISCOVERY"] or run_id.is_empty():
		return
	var existing_value: Variant = _activity_progression_baselines.get(run_id, {})
	if (
		existing_value is Dictionary
		and StringName((existing_value as Dictionary).get(&"activity_id", &"")) == activity
	):
		# A persistence retry re-announces the exact run authority. Preserve the
		# original pre-run snapshot so contract and activity deltas stay truthful.
		return
	# Only the newest attempt for an activity can settle. Removing an abandoned
	# attempt here means a delayed completion cannot consume the new run's baseline.
	for stale_run_id: Variant in _activity_progression_baselines.keys():
		var stale_value: Variant = _activity_progression_baselines.get(stale_run_id, {})
		if (
			stale_value is Dictionary
			and StringName((stale_value as Dictionary).get(&"activity_id", &"")) == activity
		):
			_activity_progression_baselines.erase(stale_run_id)
	_activity_progression_baselines[run_id] = {
		&"activity_id": activity,
		&"progression": PROGRESSION_PAYOFF_SCRIPT.capture(Profile),
	}


func _on_settings_visibility_changed(open: bool) -> void:
	_settings_modal_open = open
	_touch_modal_open = _settings_modal_open or _photo_modal_open
	if is_instance_valid(_garage):
		if open:
			_saved_garage_unhandled_input = _garage.is_processing_unhandled_input()
			_garage.set_process_unhandled_input(false)
		else:
			_garage.set_process_unhandled_input(_saved_garage_unhandled_input)
	_refresh_touch_context()


func _on_photo_mode_changed(active: bool) -> void:
	_photo_modal_open = active
	_touch_modal_open = _settings_modal_open or _photo_modal_open
	_refresh_touch_context()


func _on_replay_visibility_changed(active: bool) -> void:
	_replay_modal_open = active
	_touch_modal_open = _settings_modal_open or _photo_modal_open
	_refresh_touch_context()


func _refresh_touch_context() -> void:
	if not is_instance_valid(_touch_controls):
		return
	if _transitioning or _touch_modal_open:
		_touch_controls.set_context(&"HIDDEN")
	elif _touch_results_visible:
		_touch_controls.set_context(&"RESULTS")
	elif _garage.is_open():
		_touch_controls.set_context(&"GARAGE")
	elif _hud.visible:
		_touch_controls.set_context(&"RIDE")
	else:
		_touch_controls.set_context(&"HIDDEN")


func _zero_race_rewards(source: Dictionary) -> Dictionary:
	var zeroed := source.duplicate(true)
	for key: Variant in zeroed.keys():
		if zeroed[key] is int or zeroed[key] is float:
			zeroed[key] = 0
	zeroed[&"cash"] = 0
	zeroed[&"reputation"] = 0
	zeroed[&"credited_cash"] = 0
	zeroed[&"credited_reputation"] = 0
	return zeroed


func _active_competition_id() -> StringName:
	return StringName(_active_challenge.get("competition_id", &"")) if not _active_challenge.is_empty() else &""


func _mark_result_invalid(result: Dictionary, reason: String) -> void:
	result[&"valid"] = false
	var existing_reason := str(result.get(&"validity_reason", "")).strip_edges()
	if existing_reason.is_empty():
		result[&"validity_reason"] = reason
	elif reason not in existing_reason.split(", "):
		result[&"validity_reason"] = "%s, %s" % [existing_reason, reason]


func _on_race_started_apply_session_rules() -> void:
	# RideDirector supplies rotating flavor to career sessions. Competitive
	# challenges are stock/equalized, so remove that extra unsignatured modifier
	# after all race-start listeners have initialized.
	if RaceEventCatalog.is_challenge_event(_current_activity):
		_bike.apply_run_modifier(&"STANDARD")


func _on_bike_landed(intensity: float) -> void:
	if (
		&"--smoke-test" in OS.get_cmdline_user_args()
		or _is_test_ride_active()
		or intensity <= 0.72
	):
		return
	var damage := BIKE_CONDITION_FEEDBACK.damage_for_landing(intensity)
	_apply_live_bike_damage(damage)


func _on_bike_automatic_recovery_requested(reason: StringName) -> void:
	if (
		&"--smoke-test" in OS.get_cmdline_user_args()
		or _is_test_ride_active()
		or _current_activity == &"ACADEMY"
	):
		return
	_apply_live_bike_damage(
		BIKE_CONDITION_FEEDBACK.damage_for_automatic_recovery(reason)
	)


func _apply_live_bike_damage(damage: int) -> void:
	if damage <= 0:
		return
	Profile.apply_bike_damage(damage)
	_bike.apply_condition(Profile.bike_condition)
	_hud.show_bike_damage(damage, _bike.get_condition_snapshot())
