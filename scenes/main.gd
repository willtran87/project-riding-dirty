extends Node3D
## Composes the vertical slice and mediates scene-local systems.

@onready var _bike: DirtBikeController = %Bike
@onready var _camera: ChaseCamera = %ChaseCamera
@onready var _race: RaceController = %RaceController
@onready var _ghost: GhostController = %GhostController
@onready var _hud: RaceHud = %RaceHud
@onready var _smoke_test: Node = %RuntimeSmokeTest
@onready var _garage: GarageUi = %GarageUi
@onready var _freestyle: FreestyleController = %FreestyleController
@onready var _discovery: DiscoveryController = %DiscoveryController
@onready var _transition: DistrictTransition = %DistrictTransition
@onready var _gameplay_audio: GameplayAudio = %GameplayAudio
@onready var _ride_director: RideDirector = %RideDirector
@onready var _atmosphere: AtmosphereDirector = %AtmosphereDirector

var _paused: bool = false
var _current_activity: StringName = &"CIRCUIT"
var _transitioning: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_camera.target = _bike
	_camera.snap_to_target()
	_bike.telemetry_updated.connect(_hud.update_telemetry)
	_bike.flow_changed.connect(_hud.update_flow)
	_bike.landed.connect(_camera.apply_landing_kick)
	_bike.boost_activated.connect(_camera.apply_boost_punch)
	_bike.airtime_started.connect(_camera.begin_airtime)
	_bike.landed.connect(_on_bike_landed)
	_race.time_updated.connect(_hud.update_race_time)
	_race.breakdown_ready.connect(_hud.show_breakdown)
	_freestyle.hud_updated.connect(_hud.update_freestyle)
	_discovery.hud_updated.connect(_hud.update_discovery)
	_garage.ride_requested.connect(_on_ride_requested)
	_race.initialize(_bike, _ghost)
	_freestyle.initialize(_bike, _ghost)
	_discovery.initialize(_bike, _ghost)
	_gameplay_audio.initialize(_bike, _ride_director)
	_ride_director.initialize(_bike)
	_ride_director.line_updated.connect(_hud.update_line)
	_ride_director.contract_updated.connect(_hud.update_contract)
	_ride_director.modifier_updated.connect(_hud.update_modifier)
	_ride_director.route_discovered.connect(_camera.apply_route_highlight)
	_ride_director.feat_unlocked.connect(_hud.show_feat)
	_atmosphere.initialize(_bike)
	if &"--smoke-test" in OS.get_cmdline_user_args():
		_on_ride_requested(Profile.current_setup, _get_requested_test_activity())
	else:
		_garage.show_garage()
	_smoke_test.call(&"initialize", _bike, _camera, _race, _freestyle, _discovery, _transition, _ride_director, _gameplay_audio)


func _unhandled_input(event: InputEvent) -> void:
	if _transitioning:
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
		_stop_all_activities()
		_garage.show_garage()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(InputRouter.RESET_BIKE) and not event.is_echo():
		_bike.reset_to_safe_position()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(InputRouter.RESTART_RUN) and not event.is_echo():
		_restart_current_activity()
		get_viewport().set_input_as_handled()


func _toggle_pause() -> void:
	_paused = not _paused
	get_tree().paused = _paused
	EventBus.game_paused.emit(_paused)


func _on_ride_requested(setup: StringName, activity: StringName) -> void:
	if _transitioning:
		return
	_transitioning = true
	_stop_all_activities()
	var skip_transition := &"--smoke-test" in OS.get_cmdline_user_args()
	if not skip_transition:
		await _transition.cover(activity)
	_current_activity = activity
	Profile.set_current_setup(setup)
	_bike.apply_setup(setup)
	_bike.apply_condition(Profile.bike_condition)
	_bike.apply_cosmetic_tier(Profile.get_cosmetic_tier())
	_bike.apply_assist_mode(Profile.assist_mode)
	match activity:
		&"PINE_ENDURO":
			_race.configure_track(&"PINE")
			_race.reset_run()
		&"FREESTYLE":
			_freestyle.start_session()
		&"DISCOVERY":
			_discovery.start_hunt()
		_:
			_race.configure_track(&"QUARRY")
			_race.reset_run()
	_camera.snap_to_target()
	if not skip_transition:
		await _transition.reveal()
	_transitioning = false


func _restart_current_activity() -> void:
	match _current_activity:
		&"PINE_ENDURO":
			_race.reset_run()
		&"FREESTYLE":
			_freestyle.start_session()
		&"DISCOVERY":
			_discovery.start_hunt()
		_:
			_race.reset_run()
	_camera.snap_to_target()


func _stop_all_activities() -> void:
	_race.enter_waiting()
	_freestyle.enter_waiting()
	_discovery.enter_waiting()


func _get_requested_test_activity() -> StringName:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--activity="):
			var requested := StringName(argument.trim_prefix("--activity=").to_upper())
			if requested in [&"CIRCUIT", &"FREESTYLE", &"DISCOVERY", &"PINE_ENDURO"]:
				return requested
	return &"CIRCUIT"


func _on_bike_landed(intensity: float) -> void:
	if &"--smoke-test" in OS.get_cmdline_user_args() or intensity <= 0.72:
		return
	var damage := maxi(int(ceil((intensity - 0.72) * 18.0)), 1)
	Profile.apply_bike_damage(damage)
	_bike.apply_condition(Profile.bike_condition)
