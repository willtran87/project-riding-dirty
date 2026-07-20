extends Node3D
## Real race/replay integration contract: RESULTS-only playback, idempotent start,
## photo freeze, and synchronous teardown on a restarted countdown.

const BIKE_SCENE := preload("res://entities/bike/bike.tscn")
const GHOST_SCENE := preload("res://features/race/ghost_controller.tscn")
const RACE_SCENE := preload("res://features/race/race_controller.tscn")
const CAMERA_SCENE := preload("res://features/camera/chase_camera.tscn")
const MUTATED_ACTIONS: Array[StringName] = [
	InputRouter.TOGGLE_REPLAY,
	InputRouter.TOGGLE_PHOTO_MODE,
	InputRouter.PHOTO_FORWARD,
	InputRouter.PHOTO_BACK,
	InputRouter.PHOTO_LEFT,
	InputRouter.PHOTO_RIGHT,
	InputRouter.PHOTO_DOWN,
	InputRouter.PHOTO_UP,
	InputRouter.PHOTO_LOOK_LEFT,
	InputRouter.PHOTO_LOOK_RIGHT,
	InputRouter.PHOTO_LOOK_UP,
	InputRouter.PHOTO_LOOK_DOWN,
]

var _failures := PackedStringArray()
var _replay_states: Array[bool] = []
var _race_moments: Array[String] = []
var _action_snapshots: Dictionary = {}
var _prior_input_mode: StringName = &""
var _modal_hud: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Profile.persistence_enabled = false
	_run.call_deferred()


func _run() -> void:
	_prior_input_mode = InputRouter.input_mode
	_snapshot_actions()
	var bike := BIKE_SCENE.instantiate() as DirtBikeController
	var ghost := GHOST_SCENE.instantiate() as GhostController
	var race := RACE_SCENE.instantiate() as RaceController
	race.process_mode = Node.PROCESS_MODE_PAUSABLE
	var camera := CAMERA_SCENE.instantiate() as ChaseCamera
	var services := RaceServices.new()
	_modal_hud = Node.new()
	_modal_hud.name = "ModalInputOwner"
	_modal_hud.set_process_unhandled_input(true)
	add_child(bike)
	add_child(ghost)
	add_child(race)
	add_child(camera)
	add_child(_modal_hud)
	add_child(services)
	ghost.persistence_enabled = false
	camera.target = bike
	await _wait_physics_frames(2)

	var route := CourseCatalog.get_world_riding_points(CourseCatalog.QUARRY_ID)
	race.initialize(bike, ghost, CourseCatalog.QUARRY_ID, route, null)
	var config := RaceSessionConfig.from_dictionary({
		&"event_id": &"REPLAY_LIFECYCLE_PROBE",
		&"track_id": CourseCatalog.QUARRY_ID,
		&"display_name": "REPLAY LIFECYCLE PROBE",
		&"format": &"TIME_ATTACK",
		&"session_type": &"MAIN",
		&"route_version": 19,
		&"laps": 1,
		&"opponent_count": 0,
		&"field_size": 1,
		&"checkpoint_count": 2,
		&"countdown_seconds": 0.1,
		&"staging_seconds": 0.0,
		&"finish_grace_seconds": 0.0,
	})
	race.configure_session(config, route, null)
	services.initialize(race, bike, camera, _modal_hud)
	services.replay_state_changed.connect(func(active: bool) -> void: _replay_states.append(active))
	race.race_moment.connect(func(label: String, _points: int, _positive: bool) -> void:
		_race_moments.append(label)
	)
	_apply_rebound_bindings()
	InputRouter.call(&"_set_input_mode", InputRouter.INPUT_MODE_KEYBOARD_MOUSE)
	InputRouter.notify_bindings_changed(MUTATED_ACTIONS)
	_assert(_modal_hud.is_processing_unhandled_input(), "fixture HUD did not begin with input ownership")

	_assert(not services.start_replay(), "replay started before a result existed")
	race.reset_run()
	_assert(not services.start_replay(), "replay started during countdown")
	if not await _wait_for_state(race, RaceController.State.RACING, 60):
		_failures.append("race never reached RACING")
		await _finish(services, race, ghost, bike, camera)
		return
	_assert(not services.start_replay(), "replay started during a live race")
	_assert(
		bool(services.get_replay_lifecycle_snapshot().get(&"recording", false)),
		"live race did not start the replay recorder"
	)
	var samples_before_pause := int(
		services.get_replay_lifecycle_snapshot().get(&"recording_samples", -1)
	)
	var elapsed_before_pause := int(race.get_session_snapshot().get(&"elapsed_usec", -1))
	get_tree().paused = true
	await _wait_physics_frames(12)
	var samples_during_pause := int(
		services.get_replay_lifecycle_snapshot().get(&"recording_samples", -2)
	)
	var elapsed_during_pause := int(race.get_session_snapshot().get(&"elapsed_usec", -2))
	get_tree().paused = false
	await _wait_physics_frames(2)
	var elapsed_after_resume := int(race.get_session_snapshot().get(&"elapsed_usec", -3))
	_assert(
		samples_during_pause == samples_before_pause,
		"paused race advanced replay recording samples"
	)
	_assert(elapsed_during_pause == elapsed_before_pause, "paused race advanced its official clock")
	_assert(
		elapsed_after_resume > elapsed_before_pause
		and elapsed_after_resume - elapsed_before_pause <= 50_000,
		"race clock charged paused wall time after resuming"
	)
	race.enter_waiting()
	var abandoned_snapshot := services.get_replay_lifecycle_snapshot()
	_assert(
		not bool(abandoned_snapshot.get(&"recording", true))
		and int(abandoned_snapshot.get(&"recording_samples", -1)) == 0,
		"abandoned live race retained replay recording state"
	)
	race.reset_run()
	if not await _wait_for_state(race, RaceController.State.RACING, 60):
		_failures.append("race never restarted after abandoned attempt")
		await _finish(services, race, ghost, bike, camera)
		return
	_assert(
		bool(services.get_replay_lifecycle_snapshot().get(&"recording", false)),
		"rematch did not start a fresh replay recorder"
	)
	await _wait_physics_frames(4)
	race.reset_run()
	var staging_abort_snapshot := services.get_replay_lifecycle_snapshot()
	_assert(
		race.state == RaceController.State.COUNTDOWN
		and not bool(staging_abort_snapshot.get(&"recording", true))
		and int(staging_abort_snapshot.get(&"recording_samples", -1)) == 0,
		"live reset to STAGING retained replay recording state"
	)
	if not await _wait_for_state(race, RaceController.State.RACING, 60):
		_failures.append("race never restarted after live STAGING abort")
		await _finish(services, race, ghost, bike, camera)
		return
	_assert(
		bool(services.get_replay_lifecycle_snapshot().get(&"recording", false)),
		"post-abort rematch did not start a fresh replay recorder"
	)
	bike.set_motion_locked(true)
	await _wait_physics_frames(12)
	var gates: Array[Area3D] = []
	for child: Node in race.get_children():
		if child is Area3D and child.name.begins_with("Checkpoint"):
			gates.append(child as Area3D)
	gates.sort_custom(func(first: Area3D, second: Area3D) -> bool:
		return String(first.name).naturalnocasecmp_to(String(second.name)) < 0
	)
	for gate: Area3D in gates:
		gate.body_entered.emit(bike)
		await get_tree().physics_frame
	await _wait_for_state(race, RaceController.State.RESULTS, 30)

	var ready_snapshot := services.get_replay_lifecycle_snapshot()
	_assert(
		race.state == RaceController.State.RESULTS
		and bool(ready_snapshot.get(&"recorded", false))
		and bool(ready_snapshot.get(&"eligible", false)),
		"completed result did not produce an eligible exact replay"
	)
	var complete_replay := services.get("_last_replay") as ReplayModel
	if complete_replay != null and not complete_replay.samples.is_empty():
		var one_sample := ReplayModel.new()
		one_sample.sample_interval_usec = complete_replay.sample_interval_usec
		one_sample.metadata = complete_replay.metadata.duplicate(true)
		one_sample.samples = [complete_replay.samples[0].duplicate(true)]
		one_sample.duration_usec = 0
		services.set("_last_replay", one_sample)
		var short_snapshot := services.get_replay_lifecycle_snapshot()
		_assert(
			not bool(short_snapshot.get(&"recorded", true))
			and not bool(short_snapshot.get(&"eligible", true)),
			"one-sample zero-duration replay was exposed as playable"
		)
		services.set("_last_replay", complete_replay)
	_dispatch_rebound_key(services, KEY_F6)
	_assert(services.is_replay_active(), "rebound replay control did not start the eligible replay")
	var replay_target := camera.target
	_assert(services.start_replay(), "idempotent replay start returned false")
	var active_snapshot := services.get_replay_lifecycle_snapshot()
	_assert(
		bool(active_snapshot.get(&"active", false))
		and bool(active_snapshot.get(&"camera_on_replay", false))
		and not bool(active_snapshot.get(&"bike_visible", true))
		and not _modal_hud.is_processing_unhandled_input()
		and camera.target == replay_target,
		"replay start did not preserve camera/bike/modal input ownership"
	)
	var replay_prompt := _latest_race_moment("REPLAY  //")
	_assert(
		replay_prompt.contains("F6 EXIT") and replay_prompt.contains("F5 PHOTO"),
		"active replay prompt omitted rebound replay/photo controls: %s" % replay_prompt
	)

	await _wait_physics_frames(4)
	_dispatch_rebound_key(services, KEY_F5)
	var frozen_time := int(services.get_replay_lifecycle_snapshot().get(&"playback_time_usec", -1))
	await _wait_process_frames(6)
	var photo_snapshot := services.get_replay_lifecycle_snapshot()
	_assert(
		bool(photo_snapshot.get(&"photo_mode", false))
		and not _modal_hud.is_processing_unhandled_input()
		and int(photo_snapshot.get(&"playback_time_usec", -2)) == frozen_time,
		"photo mode allowed replay playback or modal HUD input to advance"
	)
	var photo_prompt := _latest_race_moment("PHOTO MODE")
	_assert(
		photo_prompt.contains("I / K")
		and photo_prompt.contains("J / L")
		and photo_prompt.contains("U / O HEIGHT")
		and photo_prompt.contains("F2 / F3")
		and photo_prompt.contains("F4 / F10")
		and photo_prompt.contains("F5 EXIT"),
		"active photo prompt omitted rebound move/height/look/exit controls: %s" % photo_prompt
	)
	_probe_semantic_photo_camera(services, camera)
	InputRouter.call(&"_set_input_mode", InputRouter.INPUT_MODE_GAMEPAD)
	var gamepad_photo_prompt := _latest_race_moment("PHOTO MODE")
	_assert(
		gamepad_photo_prompt.contains("LS MOVE")
		and gamepad_photo_prompt.contains("LT / RT HEIGHT")
		and gamepad_photo_prompt.contains("RS LOOK")
		and not gamepad_photo_prompt.contains("LS + LS")
		and not gamepad_photo_prompt.contains("RS + RS"),
		"photo prompt did not collapse duplicate stick axes for gamepad: %s" % gamepad_photo_prompt
	)
	InputRouter.call(&"_set_input_mode", InputRouter.INPUT_MODE_KEYBOARD_MOUSE)
	_dispatch_rebound_key(services, KEY_F5)
	await _wait_physics_frames(4)
	_assert(
		int(services.get_replay_lifecycle_snapshot().get(&"playback_time_usec", -1)) > frozen_time,
		"replay did not resume after photo mode"
	)

	_dispatch_rebound_key(services, KEY_F5)
	services.stop_replay()
	var composite_stop := services.get_replay_lifecycle_snapshot()
	_assert(
		not bool(composite_stop.get(&"active", true))
		and not bool(composite_stop.get(&"photo_mode", true))
		and not get_tree().paused
		and camera.is_physics_processing()
		and bool(composite_stop.get(&"bike_visible", false))
		and not bool(composite_stop.get(&"bike_controls_enabled", true))
		and _modal_hud.is_processing_unhandled_input()
		and camera.target == bike,
		"stopping a replay from photo mode did not restore pause/camera/bike/modal input ownership"
	)
	_dispatch_rebound_key(services, KEY_F6)
	_assert(services.is_replay_active(), "rebound replay control could not restart after composite teardown")
	_dispatch_rebound_key(services, KEY_F5)
	race.reset_run()
	var reset_snapshot := services.get_replay_lifecycle_snapshot()
	_assert(
		race.state == RaceController.State.COUNTDOWN
		and not bool(reset_snapshot.get(&"active", true))
		and not bool(reset_snapshot.get(&"photo_mode", true))
		and not bool(reset_snapshot.get(&"recorded", true))
		and not bool(reset_snapshot.get(&"eligible", true))
		and not bool(reset_snapshot.get(&"recording", true))
		and not get_tree().paused
		and camera.is_physics_processing()
		and bool(reset_snapshot.get(&"bike_visible", false))
		and _modal_hud.is_processing_unhandled_input()
		and camera.target == bike,
		"rematch countdown retained replay/photo/recording/modal input ownership"
	)
	_assert(
		_replay_states == [true, false, true, false],
		"replay lifecycle emitted duplicate or missing state transitions: %s" % str(_replay_states)
	)
	if await _wait_for_state(race, RaceController.State.RACING, 60):
		_assert(not services.start_replay(), "cleared replay restarted during the next race")

	await _finish(services, race, ghost, bike, camera)


func _wait_for_state(race: RaceController, target: RaceController.State, maximum_frames: int) -> bool:
	for _frame: int in maximum_frames:
		if race.state == target:
			return true
		await get_tree().physics_frame
	return race.state == target


func _wait_physics_frames(count: int) -> void:
	for _frame: int in count:
		await get_tree().physics_frame


func _wait_process_frames(count: int) -> void:
	for _frame: int in count:
		await get_tree().process_frame


func _probe_semantic_photo_camera(services: RaceServices, camera: ChaseCamera) -> void:
	var initial_position := camera.global_position
	var forward_event := _key_event(KEY_I)
	var right_event := _key_event(KEY_L)
	var up_event := _key_event(KEY_O)
	_assert(forward_event.is_action_pressed(InputRouter.PHOTO_FORWARD), "rebound I key no longer maps to photo forward")
	_assert(right_event.is_action_pressed(InputRouter.PHOTO_RIGHT), "rebound L key no longer maps to photo right")
	_assert(up_event.is_action_pressed(InputRouter.PHOTO_UP), "rebound O key no longer maps to photo up")
	Input.action_press(InputRouter.PHOTO_FORWARD)
	Input.action_press(InputRouter.PHOTO_RIGHT)
	Input.action_press(InputRouter.PHOTO_UP)
	services.call(&"_physics_process", 0.25)
	Input.action_release(InputRouter.PHOTO_FORWARD)
	Input.action_release(InputRouter.PHOTO_RIGHT)
	Input.action_release(InputRouter.PHOTO_UP)
	_assert(
		camera.global_position.distance_to(initial_position) > 0.5,
		"semantic photo move actions did not move the free camera"
	)

	var initial_rotation := camera.global_transform.basis.get_rotation_quaternion()
	var look_right_event := _key_event(KEY_F3)
	var look_down_event := _key_event(KEY_F10)
	_assert(look_right_event.is_action_pressed(InputRouter.PHOTO_LOOK_RIGHT), "rebound F3 key no longer maps to photo look right")
	_assert(look_down_event.is_action_pressed(InputRouter.PHOTO_LOOK_DOWN), "rebound F10 key no longer maps to photo look down")
	Input.action_press(InputRouter.PHOTO_LOOK_RIGHT)
	Input.action_press(InputRouter.PHOTO_LOOK_DOWN)
	services.call(&"_physics_process", 0.25)
	Input.action_release(InputRouter.PHOTO_LOOK_RIGHT)
	Input.action_release(InputRouter.PHOTO_LOOK_DOWN)
	_assert(
		initial_rotation.angle_to(camera.global_transform.basis.get_rotation_quaternion()) > 0.05,
		"semantic photo look actions did not rotate the free camera"
	)


func _dispatch_rebound_key(services: RaceServices, keycode: Key) -> void:
	services.call(&"_unhandled_input", _key_event(keycode))


func _key_event(keycode: Key, pressed: bool = true) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = pressed
	return event


func _latest_race_moment(prefix: String) -> String:
	for index: int in range(_race_moments.size() - 1, -1, -1):
		if _race_moments[index].begins_with(prefix):
			return _race_moments[index]
	return ""


func _snapshot_actions() -> void:
	_action_snapshots.clear()
	for action: StringName in MUTATED_ACTIONS:
		var events: Array[InputEvent] = []
		if InputMap.has_action(action):
			for event: InputEvent in InputMap.action_get_events(action):
				events.append(event.duplicate() as InputEvent)
		_action_snapshots[action] = {
			&"existed": InputMap.has_action(action),
			&"deadzone": InputMap.action_get_deadzone(action) if InputMap.has_action(action) else 0.2,
			&"events": events,
			&"fingerprint": _binding_fingerprint(events),
		}


func _apply_rebound_bindings() -> void:
	_replace_keyboard_binding(InputRouter.TOGGLE_REPLAY, KEY_F6)
	_replace_keyboard_binding(InputRouter.TOGGLE_PHOTO_MODE, KEY_F5)
	_replace_keyboard_binding(InputRouter.PHOTO_FORWARD, KEY_I)
	_replace_keyboard_binding(InputRouter.PHOTO_BACK, KEY_K)
	_replace_keyboard_binding(InputRouter.PHOTO_LEFT, KEY_J)
	_replace_keyboard_binding(InputRouter.PHOTO_RIGHT, KEY_L)
	_replace_keyboard_binding(InputRouter.PHOTO_DOWN, KEY_U)
	_replace_keyboard_binding(InputRouter.PHOTO_UP, KEY_O)
	_replace_keyboard_binding(InputRouter.PHOTO_LOOK_LEFT, KEY_F2)
	_replace_keyboard_binding(InputRouter.PHOTO_LOOK_RIGHT, KEY_F3)
	_replace_keyboard_binding(InputRouter.PHOTO_LOOK_UP, KEY_F4)
	_replace_keyboard_binding(InputRouter.PHOTO_LOOK_DOWN, KEY_F10)


func _replace_keyboard_binding(action: StringName, keycode: Key) -> void:
	var preserved: Array[InputEvent] = []
	for event: InputEvent in InputMap.action_get_events(action):
		if not event is InputEventKey:
			preserved.append(event.duplicate() as InputEvent)
	InputMap.action_erase_events(action)
	for event: InputEvent in preserved:
		InputMap.action_add_event(action, event)
	var replacement := InputEventKey.new()
	replacement.physical_keycode = keycode
	replacement.device = -1
	InputMap.action_add_event(action, replacement)


func _restore_actions() -> void:
	for action: StringName in MUTATED_ACTIONS:
		Input.action_release(action)
		var snapshot := _action_snapshots.get(action, {}) as Dictionary
		if not bool(snapshot.get(&"existed", false)):
			if InputMap.has_action(action):
				InputMap.erase_action(action)
			continue
		if not InputMap.has_action(action):
			InputMap.add_action(action, float(snapshot.get(&"deadzone", 0.2)))
		InputMap.action_set_deadzone(action, float(snapshot.get(&"deadzone", 0.2)))
		InputMap.action_erase_events(action)
		for event: InputEvent in snapshot.get(&"events", []) as Array[InputEvent]:
			InputMap.action_add_event(action, event.duplicate() as InputEvent)


func _action_matches_snapshot(action: StringName) -> bool:
	var snapshot := _action_snapshots.get(action, {}) as Dictionary
	var existed := bool(snapshot.get(&"existed", false))
	if InputMap.has_action(action) != existed:
		return false
	if not existed:
		return true
	if not is_equal_approx(InputMap.action_get_deadzone(action), float(snapshot.get(&"deadzone", 0.2))):
		return false
	return _binding_fingerprint(InputMap.action_get_events(action)) == str(snapshot.get(&"fingerprint", ""))


func _binding_fingerprint(events: Array[InputEvent]) -> String:
	var serialized: Array[Dictionary] = []
	for event: InputEvent in events:
		serialized.append(SettingsStore.serialize_binding(event))
	return JSON.stringify(serialized)


func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish(
	services: RaceServices,
	race: RaceController,
	ghost: GhostController,
	bike: DirtBikeController,
	camera: ChaseCamera
) -> void:
	var snapshot := services.get_replay_lifecycle_snapshot()
	_restore_actions()
	InputRouter.notify_bindings_changed(MUTATED_ACTIONS)
	for action: StringName in MUTATED_ACTIONS:
		_assert(_action_matches_snapshot(action), "%s bindings were not restored exactly" % String(action))
	InputRouter.call(&"_set_input_mode", _prior_input_mode)
	_assert(InputRouter.input_mode == _prior_input_mode, "prior input mode was not restored")
	var passed := _failures.is_empty()
	print("REPLAY LIFECYCLE PROBE: state=%d recorded=%s eligible=%s active=%s transitions=%s passed=%s failures=%s" % [
		race.state,
		str(snapshot.get(&"recorded", false)),
		str(snapshot.get(&"eligible", false)),
		str(snapshot.get(&"active", false)),
		str(_replay_states),
		str(passed),
		", ".join(_failures),
	])
	services.queue_free()
	race.queue_free()
	ghost.queue_free()
	bike.queue_free()
	camera.queue_free()
	if is_instance_valid(_modal_hud):
		_modal_hud.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if passed else 1)
