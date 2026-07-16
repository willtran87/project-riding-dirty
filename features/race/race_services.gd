extends Node
class_name RaceServices
## Local-first competitive services, fixed-rate replay, settings/accessibility,
## photo mode, and spectator camera integration.

signal leaderboard_updated(result: Dictionary)
signal replay_available(summary: Dictionary)
signal replay_state_changed(active: bool)
signal settings_changed(values: Dictionary)
signal settings_visibility_changed(open: bool)
signal spectator_changed(label: String)

const BIKE_VISUAL_SCRIPT = preload("res://entities/bike/bike_visual.gd")
const SETTINGS_PAGE_IDS: Array[StringName] = [&"AUDIO", &"RIDE", &"CAMERA", &"ACCESS", &"INPUT"]
const VISUAL_QUALITY_PRESETS: Dictionary = {
	&"PERFORMANCE": {&"render_scale": 0.75, &"msaa_3d": Viewport.MSAA_DISABLED},
	&"BALANCED": {&"render_scale": 0.90, &"msaa_3d": Viewport.MSAA_2X},
	&"QUALITY": {&"render_scale": 1.00, &"msaa_3d": Viewport.MSAA_4X},
}
const WEB_VISUAL_QUALITY_OVERRIDES: Dictionary = {
	# WebGL pays a steep fill-rate and shadow-submission cost. UI stays native
	# resolution while only the 3D scene is scaled, preserving HUD readability.
	&"PERFORMANCE": {
		&"render_scale": 0.67, &"msaa_3d": Viewport.MSAA_DISABLED,
		&"shadow_distance": 0.0, &"particle_ratio": 0.35,
	},
	&"BALANCED": {
		&"render_scale": 0.80, &"msaa_3d": Viewport.MSAA_DISABLED,
		&"shadow_distance": 150.0, &"particle_ratio": 0.62,
	},
	&"QUALITY": {
		&"render_scale": 0.90, &"msaa_3d": Viewport.MSAA_2X,
		&"shadow_distance": 220.0, &"particle_ratio": 0.84,
	},
}
const QUALITY_BASE_SHADOW_ENABLED_META: StringName = &"rd_quality_base_shadow_enabled"
const QUALITY_BASE_SHADOW_DISTANCE_META: StringName = &"rd_quality_base_shadow_distance"
const QUALITY_BASE_SHADOW_MODE_META: StringName = &"rd_quality_base_shadow_mode"
const REBINDABLE_ACTIONS: Array[StringName] = [
	&"throttle", &"brake", &"steer_left", &"steer_right", &"lean_forward", &"lean_back",
	&"preload", &"flow_boost", &"racecraft_technique", &"reset_bike", &"restart_run", &"open_garage", &"pause_game",
	&"open_settings", &"toggle_replay", &"toggle_photo_mode", &"spectator_next",
]

var race: RaceController
var bike: DirtBikeController
var chase_camera: ChaseCamera
var hud: Node
var settings := SettingsStore.new()
var local_leaderboard := LocalLeaderboardProvider.new()
var online_leaderboard := HttpLeaderboardProvider.new()
var challenge_schedule := ChallengeSchedule.new()
var hotseat := HotSeatChallengeState.new()

var _recorder := ReplayRecorder.new()
var _playback := ReplayPlayback.new()
var _last_replay: ReplayModel
var _last_result: Dictionary = {}
var _replay_root: Node3D
var _replay_active := false
var _photo_mode := false
var _settings_open := false
var _settings_layer: CanvasLayer
var _settings_backdrop: ColorRect
var _settings_panel: PanelContainer
var _settings_title: Label
var _settings_page_label: Label
var _settings_close_button: Button
var _settings_status_label: Label
var _settings_footer_label: Label
var _settings_scroll: ScrollContainer
var _settings_rows: VBoxContainer
var _settings_tab_buttons: Array[Button] = []
var _settings_row_buttons: Array[Button] = []
var _settings_page_index := 0
var _settings_index := 0
var _capture_action: StringName = &""
var _settings_message := ""
var _settings_saved_tree_paused := false
var _settings_saved_controls_enabled := false
var _default_bindings: Dictionary = {}
var _spectator_index := 0
var _saved_camera_target: Node3D
var _saved_tree_paused := false
var _base_camera_shake := 0.018
var _settings_items: Array[Dictionary] = []
var _settings_visibility_request: int = 0
var _visual_quality_snapshot: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_settings_overlay()


func initialize(race_controller: RaceController, player_bike: DirtBikeController, camera: ChaseCamera, race_hud: Node) -> void:
	race = race_controller
	bike = player_bike
	chase_camera = camera
	hud = race_hud
	_base_camera_shake = chase_camera.smooth_track_speed_shake
	if not EventBus.race_started.is_connected(_on_race_started):
		EventBus.race_started.connect(_on_race_started)
	if not EventBus.race_finished.is_connected(_on_race_finished):
		EventBus.race_finished.connect(_on_race_finished)
	if not EventBus.checkpoint_passed.is_connected(_on_checkpoint_passed):
		EventBus.checkpoint_passed.connect(_on_checkpoint_passed)
	if not race.lap_completed.is_connected(_on_lap_completed):
		race.lap_completed.connect(_on_lap_completed)
	if not race.results_ready.is_connected(_on_results_ready):
		race.results_ready.connect(_on_results_ready)
	if not bike.racecraft_event.is_connected(_on_bike_racecraft_event):
		bike.racecraft_event.connect(_on_bike_racecraft_event)
	_snapshot_default_bindings()
	if &"--smoke-test" not in OS.get_cmdline_user_args():
		settings.load_from_disk()
	if (settings.values.get("bindings", {}) as Dictionary).is_empty():
		settings.capture_input_map(REBINDABLE_ACTIONS)
	else:
		_merge_missing_default_bindings()
	_apply_settings()
	_refresh_settings_text()


func _physics_process(delta: float) -> void:
	if _recorder.is_recording() and is_instance_valid(bike):
		var session := race.get_session_snapshot() if race != null else {}
		var integrity := session.get(&"integrity", {}) as Dictionary
		_recorder.capture(delta, {
			"position": bike.global_position,
			"rotation": bike.global_transform.basis.get_rotation_quaternion(),
			"linear_velocity": bike.linear_velocity,
			"angular_velocity": bike.angular_velocity,
			"speed_mps": bike.get_speed_mps(),
			"progress": float(integrity.get(&"total_progress", 0.0)),
			"input": {
				"throttle": InputRouter.get_throttle(),
				"brake": InputRouter.get_brake(),
				"steer": InputRouter.get_steer(),
				"preload": 1.0 if InputRouter.is_preload_pressed() else 0.0,
			},
		})
	if _replay_active:
		_update_replay(delta)


func _process(delta: float) -> void:
	if not _photo_mode or chase_camera == null:
		return
	var move := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		move.z -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		move.z += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		move.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		move.x += 1.0
	if Input.is_physical_key_pressed(KEY_Q):
		move.y -= 1.0
	if Input.is_physical_key_pressed(KEY_E):
		move.y += 1.0
	if move.length_squared() > 0.0:
		chase_camera.global_position += chase_camera.global_transform.basis * move.normalized() * delta * 9.0
	var yaw := Input.get_axis(InputRouter.STEER_LEFT, InputRouter.STEER_RIGHT)
	var pitch := Input.get_axis(InputRouter.LEAN_FORWARD, InputRouter.LEAN_BACK)
	chase_camera.rotate_y(-yaw * delta * 1.3)
	chase_camera.rotate_object_local(Vector3.RIGHT, -pitch * delta * 0.9)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(InputRouter.OPEN_SETTINGS) and not event.is_echo():
		_toggle_settings()
		get_viewport().set_input_as_handled()
		return
	if _settings_open:
		_handle_settings_input(event)
		return
	if event.is_action_pressed(InputRouter.TOGGLE_PHOTO_MODE) and not event.is_echo():
		toggle_photo_mode()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(InputRouter.TOGGLE_REPLAY) and not event.is_echo():
		if _replay_active:
			stop_replay()
		else:
			start_replay()
		get_viewport().set_input_as_handled()
	elif (_replay_active or _photo_mode) and event.is_action_pressed(InputRouter.SPECTATOR_NEXT) and not event.is_echo():
		cycle_spectator()
		get_viewport().set_input_as_handled()


func get_daily_challenge() -> Dictionary:
	return challenge_schedule.daily(-1, clampi(Profile.get_total_reputation() / 100, 0, 5))


func get_weekly_challenge() -> Dictionary:
	return challenge_schedule.weekly(-1, clampi(Profile.get_total_reputation() / 100, 0, 5))


func configure_hotseat(participants: Array, attempts_per_rider: int = 1, weekly: bool = false) -> Dictionary:
	var challenge := get_weekly_challenge() if weekly else get_daily_challenge()
	return hotseat.configure(challenge, participants, attempts_per_rider)


func skip_hotseat_attempt(reason: String = "SKIPPED") -> Dictionary:
	return hotseat.skip_attempt(reason)


func get_hotseat_snapshot() -> Dictionary:
	return hotseat.to_dictionary()


func get_local_board(run_signature: String, limit: int = 20) -> Dictionary:
	return local_leaderboard.fetch_board(run_signature, limit)


func configure_online_leaderboard(endpoint: String, transport: Callable, headers: Dictionary = {}) -> Dictionary:
	online_leaderboard.configure(endpoint, transport, headers)
	return online_leaderboard.flush_pending()


func get_competitive_snapshot() -> Dictionary:
	return {
		&"daily": get_daily_challenge(),
		&"weekly": get_weekly_challenge(),
		&"last_result": _last_result.duplicate(true),
		&"replay_available": _last_replay != null and _last_replay.is_valid(),
		&"settings": settings.values.duplicate(true),
		&"hotseat": hotseat.to_dictionary(),
	}


func start_replay() -> bool:
	if _last_replay == null or not _last_replay.is_valid() or chase_camera == null:
		return false
	if _photo_mode:
		toggle_photo_mode()
	_ensure_replay_root()
	if not _playback.load_model(_last_replay):
		return false
	_saved_camera_target = chase_camera.target
	if is_instance_valid(bike):
		bike.visible = false
	_replay_root.visible = true
	chase_camera.target = _replay_root
	chase_camera.snap_to_target()
	_playback.looping = true
	_playback.play()
	_replay_active = true
	replay_state_changed.emit(true)
	if race != null:
		race.race_moment.emit("REPLAY  //  V EXIT  //  P PHOTO", 0, true)
	return true


func stop_replay() -> void:
	_playback.pause()
	_replay_active = false
	if is_instance_valid(_replay_root):
		_replay_root.visible = false
	if is_instance_valid(bike):
		bike.visible = true
	if chase_camera != null:
		chase_camera.target = _saved_camera_target if is_instance_valid(_saved_camera_target) else bike
		chase_camera.snap_to_target()
	replay_state_changed.emit(false)


func stop_transient_presentation() -> void:
	## Garage and activity transitions must restore the real bike, camera, pause
	## ownership, and spectator bindings before another screen becomes interactive.
	if _replay_active:
		stop_replay()
	if _photo_mode:
		toggle_photo_mode()


func toggle_photo_mode() -> void:
	_photo_mode = not _photo_mode
	if _photo_mode:
		_saved_tree_paused = get_tree().paused
		get_tree().paused = true
		if chase_camera != null:
			chase_camera.set_physics_process(false)
		if is_instance_valid(bike):
			bike.set_controls_enabled(false)
		if race != null:
			race.race_moment.emit("PHOTO MODE  //  WASD MOVE  //  Q/E HEIGHT  //  P EXIT", 0, true)
	else:
		get_tree().paused = _saved_tree_paused
		if chase_camera != null:
			chase_camera.set_physics_process(true)
			chase_camera.snap_to_target()
		if is_instance_valid(bike) and race != null and race.state == RaceController.State.RACING:
			bike.set_controls_enabled(true)


func cycle_spectator() -> void:
	if race == null or chase_camera == null:
		return
	var targets := race.get_spectator_targets()
	if targets.is_empty():
		return
	_spectator_index = wrapi(_spectator_index + 1, 0, targets.size())
	chase_camera.target = targets[_spectator_index]
	chase_camera.snap_to_target()
	var label := "YOU" if _spectator_index == 0 else "RIDER %02d" % (_spectator_index + 1)
	spectator_changed.emit(label)
	race.race_moment.emit("SPECTATING  //  %s" % label, 0, true)


func export_last_ghost_json(pretty: bool = true) -> Dictionary:
	if _last_replay == null or _last_result.is_empty():
		return {"ok": false, "error": "no_replay", "json": ""}
	var payload := GhostPayload.build(
		str(_last_result.get(&"signature", "")),
		str(_last_result.get(&"track_id", "")),
		int(race.get_session_config().route_version) if race != null else 1,
		_last_replay.sample_interval_usec,
		_last_replay.ghost_samples(),
		_last_replay.events,
		_last_replay.metadata
	)
	return GhostPayload.export_json(payload, pretty)


func save_last_ghost(path: String = "user://competitive/last_ghost.json") -> Dictionary:
	if not path.begins_with("user://"):
		return {"ok": false, "error": "unsafe_path"}
	var exported := export_last_ghost_json(true)
	if not bool(exported.get("ok", false)):
		return exported
	var absolute_dir := ProjectSettings.globalize_path(path.get_base_dir())
	if DirAccess.make_dir_recursive_absolute(absolute_dir) != OK and not DirAccess.dir_exists_absolute(absolute_dir):
		return {"ok": false, "error": "directory_failed"}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "file_open_failed"}
	file.store_string(str(exported.get("json", "")))
	file.close()
	return {"ok": true, "error": "", "path": path}


func import_ghost_json(text: String) -> Dictionary:
	return GhostPayload.import_json(text)


func _on_race_started() -> void:
	if race == null:
		return
	var session := race.get_session_snapshot()
	_recorder.begin({
		"event_id": String(session.get(&"event_id", &"CIRCUIT")),
		"track_id": String(session.get(&"track_id", &"QUARRY")),
		"format": String(session.get(&"format", &"SPRINT")),
		"laps": int(session.get(&"total_laps", 1)),
	}, ReplayRecorder.DEFAULT_SAMPLE_INTERVAL_USEC)
	_recorder.mark_event(&"START")


func _on_race_finished(_time_usec: int, _medal: StringName, _is_new_best: bool) -> void:
	if not _recorder.is_recording():
		return
	_recorder.mark_event(&"FINISH")
	_last_replay = _recorder.finish()
	if _last_replay.is_valid():
		replay_available.emit({&"duration_usec": _last_replay.duration_usec, &"samples": _last_replay.samples.size()})


func _on_checkpoint_passed(index: int, total: int, split_usec: int) -> void:
	if _recorder.is_recording():
		_recorder.mark_event(&"CHECKPOINT", {"index": index, "total": total, "split_usec": split_usec})


func _on_lap_completed(lap: int, total: int, lap_usec: int, best_lap_usec: int) -> void:
	if _recorder.is_recording():
		_recorder.mark_event(&"LAP", {"lap": lap, "total": total, "lap_usec": lap_usec, "best_lap_usec": best_lap_usec})


func _on_bike_racecraft_event(kind: StringName, payload: Dictionary) -> void:
	if not _recorder.is_recording():
		return
	var marker := payload.duplicate(true)
	marker[&"kind"] = kind
	_recorder.mark_event(&"RACECRAFT", marker)


func _on_results_ready(result: Dictionary) -> void:
	_last_result = result.duplicate(true)
	if _recorder.is_recording():
		_last_replay = _recorder.finish()
	if not bool(result.get(&"valid", true)):
		return
	var profile_id := "local_player"
	if Profile.has_method(&"get_profile_id"):
		profile_id = str(Profile.call(&"get_profile_id"))
	var entry := LeaderboardProvider.create_entry(
		str(result.get(&"signature", "")),
		profile_id,
		"LOCAL RIDER",
		int(result.get(&"player_time_usec", -1)),
		{
			"run_id": str(result.get(&"run_id", "")),
			"penalty_usec": int(result.get(&"player_penalty_usec", 0)),
			"challenge_id": str(result.get(&"challenge_id", "")),
			"metrics": {
				"position": int(result.get(&"player_position", 0)),
				"fastest_lap_usec": int(result.get(&"fastest_lap_usec", -1)),
				"overtakes": int(result.get(&"overtakes", 0)),
				"contacts": int(result.get(&"contacts", 0)),
				"crashes": int(result.get(&"crashes", 0)),
				"recoveries": int(result.get(&"recoveries", 0)),
				"resets": int(result.get(&"reset_count", 0)),
			},
		}
	)
	var submission := local_leaderboard.submit_run(entry)
	leaderboard_updated.emit(submission)
	if Profile.has_method(&"record_leaderboard_summary"):
		Profile.call(&"record_leaderboard_summary", String(result.get("signature", "")), submission)
	if online_leaderboard.is_online_ready():
		online_leaderboard.submit_run(entry)
	var hotseat_rider := hotseat.current_participant()
	if not hotseat_rider.is_empty():
		var hotseat_entry := LeaderboardProvider.create_entry(
			str(result.get(&"signature", "")),
			str(hotseat_rider.get("profile_id", "")),
			str(hotseat_rider.get("display_name", "RIDER")),
			int(result.get(&"player_time_usec", -1)),
			{
				"run_id": "%s-%s" % [str(result.get(&"run_id", "run")), str(hotseat_rider.get("profile_id", "rider"))],
				"penalty_usec": int(result.get(&"player_penalty_usec", 0)),
				"challenge_id": str(hotseat.challenge.get("challenge_id", "")),
				"metrics": {"position": int(result.get(&"player_position", 0))},
			}
		)
		var hotseat_result := hotseat.submit_attempt(hotseat_entry)
		leaderboard_updated.emit({"kind": "HOTSEAT", "result": hotseat_result})


func _update_replay(delta: float) -> void:
	var frame := _playback.advance(delta)
	for event_value: Variant in frame.get("events", []):
		if not event_value is Dictionary:
			continue
		var replay_event := event_value as Dictionary
		if StringName(replay_event.get("name", &"")) != &"RACECRAFT":
			continue
		var payload := replay_event.get("payload", {}) as Dictionary
		var kind := StringName(payload.get(&"kind", &""))
		if hud != null and hud.has_method(&"show_racecraft_event"):
			hud.call(&"show_racecraft_event", kind, payload)
		if chase_camera != null and chase_camera.has_method(&"apply_racecraft_feedback"):
			chase_camera.call(&"apply_racecraft_feedback", kind, float(payload.get(&"intensity", 0.55)))
	var replay_state := frame.get("state", {}) as Dictionary
	if replay_state.is_empty() or not is_instance_valid(_replay_root):
		return
	var rotation := replay_state.get("rotation", Quaternion.IDENTITY) as Quaternion
	_replay_root.global_transform = Transform3D(Basis(rotation), replay_state.get("position", Vector3.ZERO) as Vector3)


func _ensure_replay_root() -> void:
	if is_instance_valid(_replay_root):
		return
	_replay_root = Node3D.new()
	_replay_root.name = "ReplayBike"
	get_tree().current_scene.add_child(_replay_root)
	var visual := Node3D.new()
	visual.set_script(BIKE_VISUAL_SCRIPT)
	visual.set(&"pack_variant", true)
	visual.set(&"pack_bike_color", Color("56d6ff"))
	visual.set(&"pack_helmet_color", Color("f7e5b2"))
	visual.position = Vector3(0.0, 0.76, 0.0)
	_replay_root.add_child(visual)
	_replay_root.visible = false


func _apply_settings() -> void:
	var controls := settings.values.get("controls", {}) as Dictionary
	var interface := settings.values.get("interface", {}) as Dictionary
	var gameplay := settings.values.get("gameplay", {}) as Dictionary
	InputRouter.configure_controls(controls)
	RaceEventCatalog.set_player_difficulty_mode(gameplay.get("race_difficulty", "STANDARD"))
	_apply_visual_quality(str(settings.get_value(&"graphics", &"visual_quality", "BALANCED")))
	var bindings := settings.values.get("bindings", {}) as Dictionary
	if not bindings.is_empty():
		settings.apply_to_input_map(true)
	if chase_camera != null:
		var camera_values := settings.values.get("camera", {}) as Dictionary
		chase_camera.base_fov = float(camera_values.get("fov_degrees", 78.0))
		chase_camera.maximum_fov = chase_camera.base_fov + 16.0
		chase_camera.smooth_track_speed_shake = _base_camera_shake * float(camera_values.get("shake_intensity", 0.75))
		chase_camera.set_reduced_motion(bool(interface.get("reduced_motion", false)))
	var audio := settings.values.get("audio", {}) as Dictionary
	_set_bus_volume(&"Master", float(audio.get("master_volume", 1.0)))
	_set_bus_volume(&"Music", float(audio.get("music_volume", 0.72)))
	_set_bus_volume(&"SFX", float(audio.get("effects_volume", 0.9)))
	if bike != null and bike.has_method(&"configure_feedback"):
		bike.call(&"configure_feedback", settings.values.get("feedback", {}) as Dictionary)
	if hud != null and hud.has_method(&"apply_accessibility"):
		hud.call(&"apply_accessibility", interface)
	get_tree().call_group(
		&"reduced_motion_consumers", &"set_reduced_motion",
		bool(interface.get("reduced_motion", false))
	)
	get_tree().call_group(&"touch_controls", &"configure_touch_controls", controls)
	if Profile.has_method(&"set_settings_reference"):
		Profile.call(&"set_settings_reference", SettingsStore.DEFAULT_PATH)
	settings_changed.emit(settings.values.duplicate(true))


func _apply_visual_quality(requested_mode: String) -> void:
	var resolved := resolve_visual_quality_preset(requested_mode, OS.has_feature("web"))
	var mode := StringName(resolved[&"mode"])
	var render_scale := float(resolved[&"render_scale"])
	var requested_msaa := int(resolved[&"requested_msaa_3d"])
	var effective_msaa := int(resolved[&"effective_msaa_3d"])
	var web_capped := bool(resolved[&"web_capped"])
	var viewport := get_viewport()
	if viewport != null:
		viewport.scaling_3d_scale = render_scale
		viewport.msaa_3d = effective_msaa as Viewport.MSAA
	_visual_quality_snapshot = resolved
	_visual_quality_snapshot[&"applied"] = viewport != null
	refresh_visual_quality()


static func resolve_visual_quality_preset(requested_mode: String, web_environment: bool = false) -> Dictionary:
	var mode := StringName(requested_mode.strip_edges().to_upper())
	if not VISUAL_QUALITY_PRESETS.has(mode):
		mode = &"BALANCED"
	var preset := (
		WEB_VISUAL_QUALITY_OVERRIDES[mode]
		if web_environment
		else VISUAL_QUALITY_PRESETS[mode]
	) as Dictionary
	var render_scale := clampf(float(preset.get(&"render_scale", 0.90)), 0.67, 1.0)
	var requested_msaa := clampi(int(preset.get(&"msaa_3d", Viewport.MSAA_2X)), Viewport.MSAA_DISABLED, Viewport.MSAA_4X)
	var native_requested_msaa := int((VISUAL_QUALITY_PRESETS[mode] as Dictionary).get(&"msaa_3d", requested_msaa))
	var web_capped := web_environment and (
		not is_equal_approx(render_scale, float((VISUAL_QUALITY_PRESETS[mode] as Dictionary).get(&"render_scale", render_scale)))
		or requested_msaa != native_requested_msaa
	)
	return {
		&"mode": mode,
		&"render_scale": render_scale,
		&"requested_msaa_3d": native_requested_msaa,
		&"effective_msaa_3d": requested_msaa,
		&"web_capped": web_capped,
		&"web_environment": web_environment,
		&"shadow_distance": float(preset.get(&"shadow_distance", -1.0)),
		&"particle_ratio": clampf(float(preset.get(&"particle_ratio", 1.0)), 0.0, 1.0),
	}


func refresh_visual_quality(scene_root: Node = null) -> void:
	## Reapply the current scene budget after a streamed district is attached.
	## Original authored values live in metadata, so switching presets is lossless.
	var root := scene_root if scene_root != null else get_tree().current_scene
	if root == null or _visual_quality_snapshot.is_empty():
		return
	apply_visual_quality_to_scene(root, _visual_quality_snapshot)


static func apply_visual_quality_to_scene(scene_root: Node, resolved: Dictionary) -> void:
	if scene_root == null:
		return
	var web_environment := bool(resolved.get(&"web_environment", false))
	var mode := StringName(resolved.get(&"mode", &"BALANCED"))
	var shadow_distance := float(resolved.get(&"shadow_distance", -1.0))
	for raw_light: Node in scene_root.find_children("*", "DirectionalLight3D", true, false):
		var light := raw_light as DirectionalLight3D
		if light == null:
			continue
		if not light.has_meta(QUALITY_BASE_SHADOW_ENABLED_META):
			light.set_meta(QUALITY_BASE_SHADOW_ENABLED_META, light.shadow_enabled)
			light.set_meta(QUALITY_BASE_SHADOW_DISTANCE_META, light.directional_shadow_max_distance)
			light.set_meta(QUALITY_BASE_SHADOW_MODE_META, int(light.directional_shadow_mode))
		var authored_enabled := bool(light.get_meta(QUALITY_BASE_SHADOW_ENABLED_META, false))
		var authored_distance := float(light.get_meta(QUALITY_BASE_SHADOW_DISTANCE_META, light.directional_shadow_max_distance))
		var authored_mode := int(light.get_meta(QUALITY_BASE_SHADOW_MODE_META, light.directional_shadow_mode))
		if web_environment:
			light.shadow_enabled = authored_enabled and mode != &"PERFORMANCE"
			if light.shadow_enabled:
				light.directional_shadow_max_distance = minf(authored_distance, shadow_distance)
				light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		else:
			light.shadow_enabled = authored_enabled
			light.directional_shadow_max_distance = authored_distance
			light.directional_shadow_mode = authored_mode as DirectionalLight3D.ShadowMode

	var particle_ratio := float(resolved.get(&"particle_ratio", 1.0)) if web_environment else 1.0
	for raw_particles: Node in scene_root.find_children("*", "GPUParticles3D", true, false):
		var particles := raw_particles as GPUParticles3D
		if particles != null:
			particles.amount_ratio = particle_ratio


func get_visual_quality_snapshot() -> Dictionary:
	var snapshot := _visual_quality_snapshot.duplicate(true)
	var viewport := get_viewport()
	if viewport != null:
		snapshot[&"viewport_render_scale"] = viewport.scaling_3d_scale
		snapshot[&"viewport_msaa_3d"] = int(viewport.msaa_3d)
	return snapshot


func _set_bus_volume(bus_name: StringName, linear: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index >= 0:
		AudioServer.set_bus_volume_db(index, linear_to_db(clampf(linear, 0.0001, 1.0)))


func _build_settings_overlay() -> void:
	_settings_layer = CanvasLayer.new()
	_settings_layer.layer = 80
	add_child(_settings_layer)
	_settings_backdrop = ColorRect.new()
	_settings_backdrop.color = Color(0.004, 0.008, 0.012, 0.78)
	_settings_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_settings_layer.add_child(_settings_backdrop)

	_settings_panel = PanelContainer.new()
	_settings_panel.name = "ProductionSettings"
	_settings_panel.add_theme_stylebox_override(&"panel", _settings_panel_style())
	_settings_panel.set_anchors_preset(Control.PRESET_CENTER)
	_settings_panel.offset_left = -540.0
	_settings_panel.offset_right = 540.0
	_settings_panel.offset_top = -380.0
	_settings_panel.offset_bottom = 380.0
	_settings_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_settings_layer.add_child(_settings_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override(&"margin_left", 34)
	margin.add_theme_constant_override(&"margin_right", 34)
	margin.add_theme_constant_override(&"margin_top", 26)
	margin.add_theme_constant_override(&"margin_bottom", 24)
	_settings_panel.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override(&"separation", 10)
	margin.add_child(stack)

	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 18)
	stack.add_child(header)
	_settings_title = Label.new()
	_settings_title.text = "RACE SETTINGS"
	_settings_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_settings_title.add_theme_font_size_override(&"font_size", 30)
	_settings_title.add_theme_color_override(&"font_color", Color("f7e5b2"))
	header.add_child(_settings_title)
	_settings_page_label = Label.new()
	_settings_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_settings_page_label.add_theme_font_size_override(&"font_size", 17)
	_settings_page_label.add_theme_color_override(&"font_color", Color("56d6ff"))
	header.add_child(_settings_page_label)
	_settings_close_button = Button.new()
	_settings_close_button.name = "SettingsCloseButton"
	_settings_close_button.text = "CLOSE  ×"
	_settings_close_button.custom_minimum_size = Vector2(112.0, 48.0)
	_settings_close_button.focus_mode = Control.FOCUS_NONE
	_settings_close_button.tooltip_text = "Close settings"
	_settings_close_button.add_theme_font_size_override(&"font_size", 16)
	_settings_close_button.add_theme_color_override(&"font_color", Color("f7e5b2"))
	_settings_close_button.add_theme_stylebox_override(&"normal", _settings_row_style(false))
	_settings_close_button.add_theme_stylebox_override(&"hover", _settings_row_style(true))
	_settings_close_button.add_theme_stylebox_override(&"pressed", _settings_row_style(true, true))
	_settings_close_button.pressed.connect(_toggle_settings)
	header.add_child(_settings_close_button)

	var rule := ColorRect.new()
	rule.color = Color("ffb52d")
	rule.custom_minimum_size = Vector2(0.0, 3.0)
	stack.add_child(rule)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override(&"separation", 8)
	stack.add_child(tabs)
	for page_index: int in SETTINGS_PAGE_IDS.size():
		var tab := Button.new()
		tab.text = String(SETTINGS_PAGE_IDS[page_index])
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.custom_minimum_size = Vector2(0.0, 42.0)
		tab.focus_mode = Control.FOCUS_NONE
		tab.pressed.connect(_on_settings_tab_pressed.bind(page_index))
		tabs.add_child(tab)
		_settings_tab_buttons.append(tab)

	_settings_scroll = ScrollContainer.new()
	_settings_scroll.name = "SettingsRowsScroll"
	_settings_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_settings_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_settings_scroll.custom_minimum_size = Vector2(0.0, 490.0)
	_settings_scroll.follow_focus = true
	stack.add_child(_settings_scroll)
	_settings_rows = VBoxContainer.new()
	_settings_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_settings_rows.add_theme_constant_override(&"separation", 5)
	_settings_scroll.add_child(_settings_rows)

	_settings_status_label = Label.new()
	_settings_status_label.custom_minimum_size = Vector2(0.0, 32.0)
	_settings_status_label.add_theme_font_size_override(&"font_size", 17)
	_settings_status_label.add_theme_color_override(&"font_color", Color("56d6ff"))
	stack.add_child(_settings_status_label)
	_settings_footer_label = Label.new()
	_settings_footer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_settings_footer_label.add_theme_font_size_override(&"font_size", 14)
	_settings_footer_label.add_theme_color_override(&"font_color", Color("9dabb4"))
	stack.add_child(_settings_footer_label)

	_settings_backdrop.visible = false
	_settings_panel.visible = false


func _toggle_settings() -> void:
	_settings_open = not _settings_open
	_settings_panel.visible = _settings_open
	_settings_backdrop.visible = _settings_open
	if _settings_open:
		_settings_saved_tree_paused = get_tree().paused
		_settings_saved_controls_enabled = is_instance_valid(bike) and bool(bike.controls_enabled)
		get_tree().paused = true
		if is_instance_valid(bike):
			bike.set_controls_enabled(false)
		_capture_action = &""
		_settings_message = ""
		_refresh_settings_text()
	else:
		get_tree().paused = _settings_saved_tree_paused
		if is_instance_valid(bike):
			bike.set_controls_enabled(_settings_saved_controls_enabled)
	settings_visibility_changed.emit(_settings_open)


func _handle_settings_input(event: InputEvent) -> void:
	if not _capture_action.is_empty():
		if _is_binding_capture_cancel(event):
			_capture_action = &""
			_settings_message = "BINDING CANCELLED"
			_refresh_settings_text()
			return
		var captured := _capturable_binding_event(event)
		if captured != null:
			_commit_captured_binding(_capture_action, captured)
		return
	if event.is_echo():
		return
	var navigation := &""
	if event is InputEventKey and (event as InputEventKey).pressed:
		var key := (event as InputEventKey).physical_keycode
		if key == KEY_NONE:
			key = (event as InputEventKey).keycode
		match key:
			KEY_UP: navigation = &"UP"
			KEY_DOWN: navigation = &"DOWN"
			KEY_LEFT: navigation = &"LEFT"
			KEY_RIGHT: navigation = &"RIGHT"
			KEY_ENTER: navigation = &"CONFIRM"
			KEY_Q, KEY_PAGEUP: navigation = &"PAGE_PREVIOUS"
			KEY_E, KEY_PAGEDOWN, KEY_TAB: navigation = &"PAGE_NEXT"
			KEY_DELETE, KEY_BACKSPACE: navigation = &"RESET_ITEM"
			KEY_HOME: navigation = &"RESET_ALL"
			KEY_ESCAPE, KEY_F1: navigation = &"CLOSE"
	elif event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		match (event as InputEventJoypadButton).button_index:
			JOY_BUTTON_DPAD_UP: navigation = &"UP"
			JOY_BUTTON_DPAD_DOWN: navigation = &"DOWN"
			JOY_BUTTON_DPAD_LEFT: navigation = &"LEFT"
			JOY_BUTTON_DPAD_RIGHT: navigation = &"RIGHT"
			JOY_BUTTON_A: navigation = &"CONFIRM"
			JOY_BUTTON_LEFT_SHOULDER: navigation = &"PAGE_PREVIOUS"
			JOY_BUTTON_RIGHT_SHOULDER: navigation = &"PAGE_NEXT"
			JOY_BUTTON_X: navigation = &"RESET_ITEM"
			JOY_BUTTON_Y: navigation = &"RESET_ALL"
			JOY_BUTTON_B, JOY_BUTTON_BACK: navigation = &"CLOSE"
	if navigation.is_empty():
		return
	match navigation:
		&"UP": _move_settings_selection(-1)
		&"DOWN": _move_settings_selection(1)
		&"LEFT": _adjust_setting(-1)
		&"RIGHT": _adjust_setting(1)
		&"CONFIRM": _activate_settings_item()
		&"PAGE_PREVIOUS": _change_settings_page(-1)
		&"PAGE_NEXT": _change_settings_page(1)
		&"RESET_ITEM": _reset_selected_setting()
		&"RESET_ALL": _reset_all_settings()
		&"CLOSE": _toggle_settings()
	_refresh_settings_text()
	get_viewport().set_input_as_handled()


func _adjust_setting(direction: int) -> void:
	if direction == 0 or _settings_items.is_empty():
		return
	var item := _settings_items[clampi(_settings_index, 0, _settings_items.size() - 1)]
	if StringName(item.get(&"kind", &"VALUE")) != &"VALUE":
		_settings_message = "PRESS ENTER / A TO CHANGE THIS ITEM"
		return
	var section := StringName(item.get(&"section", &""))
	var key := StringName(item.get(&"key", &""))
	var value_type := StringName(item.get(&"value_type", &"FLOAT"))
	var changed := false
	match value_type:
		&"BOOL":
			changed = settings.set_value(section, key, not bool(settings.get_value(section, key, false)))
		&"ENUM":
			var options: Array = item.get(&"options", []) as Array
			if not options.is_empty():
				var current_index := options.find(settings.get_value(section, key, options[0]))
				changed = settings.set_value(section, key, options[wrapi(current_index + direction, 0, options.size())])
		_:
			var current := float(settings.get_value(section, key, item.get(&"default", 0.0)))
			changed = settings.set_value(section, key, current + float(item.get(&"step", 0.1)) * direction)
	if changed:
		if section == &"gameplay" and key == &"race_difficulty" and _has_active_race_session():
			# RaceSessionConfig and its run signature are immutable once the event is
			# composed. Persist the selection now and state its safe activation point.
			_settings_message = "RACE DIFFICULTY SAVED  //  APPLIES NEXT EVENT"
		else:
			_settings_message = "%s UPDATED" % str(item.get(&"label", "SETTING"))
		settings.save_to_disk()
		_apply_settings()


func _has_active_race_session() -> bool:
	return race != null and race.state != RaceController.State.WAITING


func _refresh_settings_text() -> void:
	if _settings_rows == null:
		return
	_settings_items = _settings_items_for_page(SETTINGS_PAGE_IDS[_settings_page_index])
	_settings_index = clampi(_settings_index, 0, maxi(_settings_items.size() - 1, 0))
	for child: Node in _settings_rows.get_children():
		_settings_rows.remove_child(child)
		child.queue_free()
	_settings_row_buttons.clear()
	var text_scale := float(settings.get_value(&"interface", &"text_scale", 1.0))
	var touch_targets := _use_touch_settings_targets()
	var row_height := 112.0 if touch_targets else maxf(42.0, ceilf(28.0 + 14.0 * text_scale))
	var adjust_width := 112.0 if touch_targets else maxf(50.0, ceilf(38.0 * text_scale))
	_settings_scroll.custom_minimum_size.y = 300.0 if touch_targets else 490.0
	if is_instance_valid(_settings_close_button):
		_settings_close_button.custom_minimum_size = Vector2(176.0, 112.0) if touch_targets else Vector2(112.0, 48.0)
		_settings_close_button.add_theme_font_size_override(&"font_size", 24 if touch_targets else 16)
	for index: int in _settings_items.size():
		var item := _settings_items[index]
		var row_line := HBoxContainer.new()
		row_line.name = "SettingLine%02d" % index
		row_line.custom_minimum_size = Vector2(0.0, row_height)
		row_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row_line.add_theme_constant_override(&"separation", 6)
		_settings_rows.add_child(row_line)
		var kind := StringName(item.get(&"kind", &"VALUE"))
		var value_type := StringName(item.get(&"value_type", &"FLOAT"))
		var bidirectional := kind == &"VALUE" and value_type != &"BOOL"
		if bidirectional:
			var decrement := _make_settings_adjust_button("-", index, -1, row_height, adjust_width, text_scale)
			row_line.add_child(decrement)
		var row := Button.new()
		row.name = "SettingRow%02d" % index
		row.text = "%s    %s" % [str(item.get(&"label", "SETTING")), _setting_value_text(item)]
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.custom_minimum_size = Vector2(0.0, row_height)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.focus_mode = Control.FOCUS_NONE
		row.add_theme_font_size_override(&"font_size", maxi(roundi(17.0 * text_scale), 24 if touch_targets else 14))
		row.add_theme_color_override(&"font_color", Color("f7e5b2") if index == _settings_index else Color("b8c4ca"))
		row.add_theme_stylebox_override(&"normal", _settings_row_style(index == _settings_index))
		row.add_theme_stylebox_override(&"hover", _settings_row_style(true))
		row.add_theme_stylebox_override(&"pressed", _settings_row_style(true, true))
		row.pressed.connect(_on_settings_row_pressed.bind(index))
		row.mouse_entered.connect(_on_settings_row_hovered.bind(index))
		row_line.add_child(row)
		_settings_row_buttons.append(row)
		if bidirectional:
			var increment := _make_settings_adjust_button("+", index, 1, row_height, adjust_width, text_scale)
			row_line.add_child(increment)
	for page_index: int in _settings_tab_buttons.size():
		var active := page_index == _settings_page_index
		var tab := _settings_tab_buttons[page_index]
		tab.custom_minimum_size.y = 112.0 if touch_targets else 42.0
		tab.add_theme_font_size_override(&"font_size", 22 if touch_targets else 16)
		tab.add_theme_color_override(&"font_color", Color("16191b") if active else Color("9dabb4"))
		tab.add_theme_stylebox_override(&"normal", _settings_tab_style(active))
		tab.add_theme_stylebox_override(&"hover", _settings_tab_style(true))
	_settings_page_label.text = "%s  //  %d / %d" % [String(SETTINGS_PAGE_IDS[_settings_page_index]), _settings_page_index + 1, SETTINGS_PAGE_IDS.size()]
	var daily := get_daily_challenge()
	if not _capture_action.is_empty():
		_settings_status_label.text = "LISTENING FOR %s  //  PRESS A KEY, MOUSE BUTTON, OR GAMEPAD CONTROL  //  ESC / B CANCEL" % _action_display_name(_capture_action)
		_settings_status_label.add_theme_color_override(&"font_color", Color("ffb52d"))
	elif not _settings_message.is_empty():
		_settings_status_label.text = _settings_message
		_settings_status_label.add_theme_color_override(&"font_color", Color("56d6ff"))
	else:
		_settings_status_label.text = "DAILY  //  %s  //  %s  //  %s REMAINING" % [
			str(daily.get("track_id", "QUARRY")).replace("_", " "),
			str(daily.get("format", "SPRINT")).replace("_", " "),
			_format_challenge_remaining(int(daily.get("ends_unix", 0))),
		]
		_settings_status_label.add_theme_color_override(&"font_color", Color("56d6ff"))
	_settings_footer_label.text = "Q / E OR LB / RB  TABS    //    ARROWS  SELECT + ADJUST    //    MOUSE - / +  ADJUST    //    ENTER / A  CHANGE    //    DEL / X  RESET    //    F1 / B  CLOSE"
	_queue_settings_selection_visibility()


func _use_touch_settings_targets() -> bool:
	return InputRouter.input_mode == InputRouter.INPUT_MODE_TOUCH or DisplayServer.is_touchscreen_available()


func _make_settings_adjust_button(
	label: String,
	row_index: int,
	direction: int,
	row_height: float,
	button_width: float,
	text_scale: float
) -> Button:
	var button := Button.new()
	button.name = "%s%02d" % ["SettingDecrease" if direction < 0 else "SettingIncrease", row_index]
	button.text = label
	button.tooltip_text = "%s %s" % ["Decrease" if direction < 0 else "Increase", str(_settings_items[row_index].get(&"label", "setting")).to_lower()]
	button.custom_minimum_size = Vector2(button_width, row_height)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override(
		&"font_size",
		maxi(roundi(20.0 * text_scale), 28 if _use_touch_settings_targets() else 16)
	)
	button.add_theme_color_override(&"font_color", Color("f7e5b2"))
	button.add_theme_stylebox_override(&"normal", _settings_row_style(false))
	button.add_theme_stylebox_override(&"hover", _settings_row_style(true))
	button.add_theme_stylebox_override(&"pressed", _settings_row_style(true, true))
	button.pressed.connect(_on_settings_adjust_pressed.bind(row_index, direction))
	button.mouse_entered.connect(_on_settings_row_hovered.bind(row_index))
	return button


func _binding_text(action: StringName) -> String:
	var events := InputMap.action_get_events(action)
	if events.is_empty():
		return "UNBOUND"
	var labels := PackedStringArray()
	for index: int in mini(events.size(), 3):
		labels.append(_friendly_binding_text(events[index]))
	return " / ".join(labels)


func _settings_items_for_page(page_id: StringName) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	match page_id:
		&"AUDIO":
			items.assign([
				_value_item("MASTER VOLUME", &"audio", &"master_volume", &"PERCENT", 0.05, 1.0),
				_value_item("MUSIC VOLUME", &"audio", &"music_volume", &"PERCENT", 0.05, 0.72),
				_value_item("ENGINE + EFFECTS", &"audio", &"effects_volume", &"PERCENT", 0.05, 0.9),
			])
		&"RIDE":
			items.assign([
				_value_item("STEERING DEADZONE", &"controls", &"steering_deadzone", &"PERCENT", 0.01, 0.12),
				_value_item("THROTTLE DEADZONE", &"controls", &"throttle_deadzone", &"PERCENT", 0.01, 0.05),
				_value_item("BRAKE DEADZONE", &"controls", &"brake_deadzone", &"PERCENT", 0.01, 0.05),
				_value_item("STEERING SENSITIVITY", &"controls", &"steering_sensitivity", &"DECIMAL", 0.05, 1.0),
				_value_item("STEERING RESPONSE CURVE", &"controls", &"steering_curve", &"DECIMAL", 0.05, 1.35),
				_enum_item("RACE DIFFICULTY", &"gameplay", &"race_difficulty", SettingsStore.RACE_DIFFICULTY_MODES),
				_value_item("HAPTICS", &"feedback", &"haptics_enabled", &"BOOL", 1.0, true),
				_value_item("HAPTIC STRENGTH", &"feedback", &"haptics_intensity", &"PERCENT", 0.05, 0.8),
			])
		&"CAMERA":
			items.assign([
				_enum_item("VISUAL QUALITY", &"graphics", &"visual_quality", SettingsStore.VISUAL_QUALITY_MODES),
				_value_item("FIELD OF VIEW", &"camera", &"fov_degrees", &"DEGREES", 2.0, 78.0),
				_value_item("CAMERA IMPACT + SHAKE", &"camera", &"shake_intensity", &"PERCENT", 0.05, 0.75),
			])
		&"ACCESS":
			items.assign([
				_value_item("TEXT SCALE", &"interface", &"text_scale", &"PERCENT", 0.05, 1.0),
				_value_item("REDUCED MOTION", &"interface", &"reduced_motion", &"BOOL", 1.0, false),
				_value_item("HIGH CONTRAST HUD", &"interface", &"high_contrast", &"BOOL", 1.0, false),
				_enum_item("COLOR-SAFE MODE", &"interface", &"color_safe_mode", SettingsStore.COLOR_SAFE_MODES),
				_enum_item("SPEED UNITS", &"interface", &"units", SettingsStore.UNIT_MODES),
				{&"kind": &"COMMAND", &"command": &"RESET_ALL", &"label": "RESTORE ALL DEFAULTS"},
			])
		&"INPUT":
			items.assign([
				_enum_item("TOUCH CONTROLS", &"controls", &"touch_controls", SettingsStore.TOUCH_CONTROL_MODES),
				_enum_item("TOUCH HANDEDNESS", &"controls", &"touch_handedness", SettingsStore.TOUCH_HANDEDNESS_MODES),
				_value_item("TOUCH CONTROL SIZE", &"controls", &"touch_control_scale", &"PERCENT", 0.05, 1.0),
				_value_item("TOUCH CONTROL OPACITY", &"controls", &"touch_control_opacity", &"PERCENT", 0.05, 0.72),
			])
			var names := {
				&"throttle": "THROTTLE", &"brake": "BRAKE", &"steer_left": "STEER LEFT", &"steer_right": "STEER RIGHT",
				&"lean_forward": "LEAN FORWARD", &"lean_back": "LEAN BACK", &"preload": "PRELOAD / JUMP",
				&"flow_boost": "CONTEXT FLOW", &"racecraft_technique": "CLUTCH / DAB / PUMP", &"reset_bike": "RESET BIKE", &"restart_run": "RESTART RUN",
				&"open_garage": "RETURN TO GARAGE", &"pause_game": "PAUSE", &"open_settings": "OPEN SETTINGS",
				&"toggle_replay": "REPLAY", &"toggle_photo_mode": "PHOTO MODE", &"spectator_next": "NEXT SPECTATOR",
			}
			for action: StringName in REBINDABLE_ACTIONS:
				items.append({&"kind": &"BINDING", &"action": action, &"label": str(names.get(action, String(action).replace("_", " ").to_upper()))})
	return items


func _value_item(label: String, section: StringName, key: StringName, display: StringName, step: float, default_value: Variant) -> Dictionary:
	var value_type := display
	if display in [&"PERCENT", &"DECIMAL", &"DEGREES"]:
		value_type = &"FLOAT"
	return {
		&"kind": &"VALUE", &"label": label, &"section": section, &"key": key,
		&"display": display, &"value_type": value_type, &"step": step, &"default": default_value,
	}


func _enum_item(label: String, section: StringName, key: StringName, options: Array) -> Dictionary:
	return {&"kind": &"VALUE", &"label": label, &"section": section, &"key": key, &"display": &"ENUM", &"value_type": &"ENUM", &"options": options.duplicate()}


func _setting_value_text(item: Dictionary) -> String:
	var kind := StringName(item.get(&"kind", &"VALUE"))
	if kind == &"BINDING":
		return _binding_text(StringName(item.get(&"action", &"")))
	if kind == &"COMMAND":
		return "ENTER / A"
	var value: Variant = settings.get_value(StringName(item.get(&"section", &"")), StringName(item.get(&"key", &"")), item.get(&"default", null))
	match StringName(item.get(&"display", &"DECIMAL")):
		&"BOOL": return "ON" if bool(value) else "OFF"
		&"PERCENT": return "%d%%" % roundi(float(value) * 100.0)
		&"DEGREES": return "%.0f DEG" % float(value)
		&"ENUM": return str(value).replace("_", " ")
		_: return "%.2f" % float(value)


func _activate_settings_item() -> void:
	if _settings_items.is_empty():
		return
	var item := _settings_items[clampi(_settings_index, 0, _settings_items.size() - 1)]
	match StringName(item.get(&"kind", &"VALUE")):
		&"BINDING":
			_capture_action = StringName(item.get(&"action", &""))
			_settings_message = ""
		&"COMMAND":
			if StringName(item.get(&"command", &"")) == &"RESET_ALL":
				_reset_all_settings()
		_:
			_adjust_setting(1)


func _move_settings_selection(direction: int) -> void:
	if not _settings_items.is_empty():
		_settings_index = wrapi(_settings_index + direction, 0, _settings_items.size())
		_queue_settings_selection_visibility()


func _change_settings_page(direction: int) -> void:
	_settings_page_index = wrapi(_settings_page_index + direction, 0, SETTINGS_PAGE_IDS.size())
	_settings_index = 0
	_settings_message = ""
	_capture_action = &""
	if _settings_scroll != null:
		_settings_scroll.scroll_vertical = 0


func _on_settings_tab_pressed(page_index: int) -> void:
	_settings_page_index = clampi(page_index, 0, SETTINGS_PAGE_IDS.size() - 1)
	_settings_index = 0
	_settings_message = ""
	if _settings_scroll != null:
		_settings_scroll.scroll_vertical = 0
	_refresh_settings_text()


func _on_settings_row_pressed(row_index: int) -> void:
	_settings_index = clampi(row_index, 0, maxi(_settings_items.size() - 1, 0))
	_activate_settings_item()
	_refresh_settings_text()


func _on_settings_adjust_pressed(row_index: int, direction: int) -> void:
	_settings_index = clampi(row_index, 0, maxi(_settings_items.size() - 1, 0))
	_adjust_setting(signi(direction))
	_refresh_settings_text()


func _on_settings_row_hovered(row_index: int) -> void:
	_settings_index = clampi(row_index, 0, maxi(_settings_items.size() - 1, 0))
	_refresh_settings_selection_styles()


func _refresh_settings_selection_styles() -> void:
	for index: int in _settings_row_buttons.size():
		var selected := index == _settings_index
		var row := _settings_row_buttons[index]
		row.add_theme_color_override(&"font_color", Color("f7e5b2") if selected else Color("b8c4ca"))
		row.add_theme_stylebox_override(&"normal", _settings_row_style(selected))


func _queue_settings_selection_visibility() -> void:
	_settings_visibility_request += 1
	call_deferred(&"_scroll_settings_selection_into_view", _settings_visibility_request)


func _scroll_settings_selection_into_view(request_id: int) -> void:
	await get_tree().process_frame
	if request_id != _settings_visibility_request or _settings_scroll == null:
		return
	if _settings_index < 0 or _settings_index >= _settings_row_buttons.size():
		return
	var selected := _settings_row_buttons[_settings_index]
	if is_instance_valid(selected):
		_settings_scroll.ensure_control_visible(selected)


func get_settings_navigation_snapshot() -> Dictionary:
	var selected: Control
	if _settings_index >= 0 and _settings_index < _settings_row_buttons.size():
		selected = _settings_row_buttons[_settings_index]
	var selected_visible := false
	if _settings_scroll != null and is_instance_valid(selected):
		var scroll_rect := _settings_scroll.get_global_rect()
		var selected_rect := selected.get_global_rect()
		selected_visible = (
			selected_rect.position.y >= scroll_rect.position.y - 0.5
			and selected_rect.position.y + selected_rect.size.y <= scroll_rect.position.y + scroll_rect.size.y + 0.5
		)
	var maximum_scroll := 0.0
	if _settings_scroll != null:
		var scroll_bar := _settings_scroll.get_v_scroll_bar()
		maximum_scroll = maxf(scroll_bar.max_value - scroll_bar.page, 0.0)
	var selected_row_height := 0.0
	if is_instance_valid(selected):
		selected_row_height = maxf(selected.size.y, selected.custom_minimum_size.y)
	return {
		&"page": SETTINGS_PAGE_IDS[_settings_page_index] if not SETTINGS_PAGE_IDS.is_empty() else &"",
		&"row_count": _settings_row_buttons.size(),
		&"selected_index": _settings_index,
		&"selected_visible": selected_visible,
		&"selected_row_height": selected_row_height,
		&"touch_sized": _use_touch_settings_targets(),
		&"close_target_size": _settings_close_button.custom_minimum_size if is_instance_valid(_settings_close_button) else Vector2.ZERO,
		&"tab_target_size": _settings_tab_buttons[0].custom_minimum_size if not _settings_tab_buttons.is_empty() else Vector2.ZERO,
		&"scroll_vertical": _settings_scroll.scroll_vertical if _settings_scroll != null else 0,
		&"maximum_scroll": maximum_scroll,
		&"has_decrement": _settings_rows.find_child("SettingDecrease%02d" % _settings_index, true, false) != null if _settings_rows != null else false,
		&"has_increment": _settings_rows.find_child("SettingIncrease%02d" % _settings_index, true, false) != null if _settings_rows != null else false,
	}


func _reset_selected_setting() -> void:
	if _settings_items.is_empty():
		return
	var item := _settings_items[clampi(_settings_index, 0, _settings_items.size() - 1)]
	var kind := StringName(item.get(&"kind", &"VALUE"))
	if kind == &"BINDING":
		_restore_default_binding(StringName(item.get(&"action", &"")))
		_settings_message = "%s RESTORED" % str(item.get(&"label", "BINDING"))
	elif kind == &"VALUE":
		var section := StringName(item.get(&"section", &""))
		var key := StringName(item.get(&"key", &""))
		var default_section := SettingsStore.DEFAULTS.get(String(section), {}) as Dictionary
		if default_section.has(String(key)):
			settings.set_value(section, key, default_section[String(key)])
			_settings_message = "%s RESTORED" % str(item.get(&"label", "SETTING"))
	settings.capture_input_map(REBINDABLE_ACTIONS)
	settings.save_to_disk()
	_apply_settings()


func _reset_all_settings() -> void:
	settings.reset_to_defaults()
	for action: StringName in REBINDABLE_ACTIONS:
		_restore_default_binding(action, false)
	settings.capture_input_map(REBINDABLE_ACTIONS)
	settings.save_to_disk()
	_apply_settings()
	_settings_message = "ALL SETTINGS AND INPUTS RESTORED"


func _snapshot_default_bindings() -> void:
	if not _default_bindings.is_empty():
		return
	for action: StringName in REBINDABLE_ACTIONS:
		var copies: Array[InputEvent] = []
		for event: InputEvent in InputMap.action_get_events(action):
			copies.append(event.duplicate() as InputEvent)
		_default_bindings[action] = copies


func _merge_missing_default_bindings() -> void:
	## Settings V2 predates the contextual racecraft action. Preserve every saved
	## binding and only seed actions that do not exist in the persisted map. If a
	## default conflicts with a customized control, leave the new action unbound so
	## the Input settings page can resolve it explicitly instead of stealing input.
	var saved := (settings.values.get("bindings", {}) as Dictionary).duplicate(true)
	var changed := false
	for action: StringName in REBINDABLE_ACTIONS:
		var key := String(action)
		if saved.has(key):
			continue
		var serialized: Array[Dictionary] = []
		for raw_event: Variant in _default_bindings.get(action, []):
			if not raw_event is InputEvent:
				continue
			var event := raw_event as InputEvent
			var conflict := false
			for raw_saved_action: Variant in saved.keys():
				var slots: Variant = saved.get(raw_saved_action, [])
				if not slots is Array:
					continue
				for raw_binding: Variant in slots:
					if raw_binding is Dictionary and SettingsStore.bindings_conflict(
						SettingsStore.serialize_binding(event), raw_binding as Dictionary
					):
						conflict = true
						break
				if conflict:
					break
			if not conflict:
				var encoded := SettingsStore.serialize_binding(event)
				if not encoded.is_empty():
					serialized.append(encoded)
		saved[key] = serialized
		changed = true
	if changed:
		settings.values["bindings"] = saved
		settings.save_to_disk()


func _restore_default_binding(action: StringName, capture_after: bool = true) -> void:
	if action.is_empty() or not _default_bindings.has(action):
		return
	InputMap.action_erase_events(action)
	for raw_event: Variant in _default_bindings[action] as Array:
		if raw_event is InputEvent:
			InputMap.action_add_event(action, (raw_event as InputEvent).duplicate() as InputEvent)
	if capture_after:
		settings.capture_input_map(REBINDABLE_ACTIONS)


func _is_binding_capture_cancel(event: InputEvent) -> bool:
	if event is InputEventKey and (event as InputEventKey).pressed:
		return (event as InputEventKey).physical_keycode == KEY_ESCAPE or (event as InputEventKey).keycode == KEY_ESCAPE
	return event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed and (event as InputEventJoypadButton).button_index == JOY_BUTTON_B


func _capturable_binding_event(event: InputEvent) -> InputEvent:
	var accepted := false
	if event is InputEventKey:
		accepted = (event as InputEventKey).pressed and not (event as InputEventKey).echo
	elif event is InputEventMouseButton:
		accepted = (event as InputEventMouseButton).pressed
	elif event is InputEventJoypadButton:
		accepted = (event as InputEventJoypadButton).pressed
	elif event is InputEventJoypadMotion:
		accepted = absf((event as InputEventJoypadMotion).axis_value) >= 0.65
	if not accepted:
		return null
	var captured := event.duplicate() as InputEvent
	captured.device = -1
	if captured is InputEventKey:
		(captured as InputEventKey).pressed = false
	elif captured is InputEventMouseButton:
		(captured as InputEventMouseButton).pressed = false
	elif captured is InputEventJoypadButton:
		(captured as InputEventJoypadButton).pressed = false
	elif captured is InputEventJoypadMotion:
		(captured as InputEventJoypadMotion).axis_value = -1.0 if (captured as InputEventJoypadMotion).axis_value < 0.0 else 1.0
	return captured


func _commit_captured_binding(action: StringName, captured: InputEvent) -> void:
	var family := _binding_family(captured)
	var merged: Array[InputEvent] = []
	for existing: InputEvent in InputMap.action_get_events(action):
		if _binding_family(existing) != family:
			merged.append(existing.duplicate() as InputEvent)
	merged.append(captured)
	var result := settings.set_bindings(action, merged, true)
	if not bool(result.get("ok", false)):
		var conflicts: Array = result.get("conflicts", []) as Array
		var conflict_name := "ANOTHER ACTION"
		if not conflicts.is_empty() and conflicts[0] is Dictionary:
			conflict_name = _action_display_name(StringName((conflicts[0] as Dictionary).get("action", "")))
		_settings_message = "%s IS ALREADY ASSIGNED TO %s" % [_friendly_binding_text(captured), conflict_name]
		_capture_action = &""
		_refresh_settings_text()
		return
	InputMap.action_erase_events(action)
	for binding: InputEvent in merged:
		InputMap.action_add_event(action, binding)
	settings.save_to_disk()
	_apply_settings()
	_settings_message = "%s  //  %s" % [_action_display_name(action), _binding_text(action)]
	_capture_action = &""
	_refresh_settings_text()


func _binding_family(event: InputEvent) -> StringName:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		return &"GAMEPAD"
	if event is InputEventMouseButton:
		return &"MOUSE"
	return &"KEYBOARD"


func _friendly_binding_text(event: InputEvent) -> String:
	var label := event.as_text()
	label = label.replace(" (Physical)", "").replace("Joypad Button", "PAD").replace("Joypad Motion on Axis", "PAD AXIS")
	return label.to_upper()


func _action_display_name(action: StringName) -> String:
	return String(action).replace("_", " ").to_upper()


func _format_challenge_remaining(ends_unix: int) -> String:
	var remaining := maxi(ends_unix - int(Time.get_unix_time_from_system()), 0)
	var hours := remaining / 3600
	var minutes := (remaining / 60) % 60
	return "%02dH %02dM" % [hours, minutes]


func _settings_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.012, 0.018, 0.024, 0.985)
	style.border_color = Color("ffb52d")
	style.set_border_width_all(3)
	style.set_corner_radius_all(10)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.65)
	style.shadow_size = 18
	return style


func _settings_row_style(selected: bool, pressed: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.16, 0.19, 0.96) if selected else Color(0.035, 0.048, 0.058, 0.78)
	if pressed:
		style.bg_color = Color(0.18, 0.22, 0.24, 1.0)
	style.border_color = Color("ffb52d") if selected else Color(0.18, 0.24, 0.28, 0.8)
	style.set_border_width_all(2 if selected else 1)
	style.set_corner_radius_all(5)
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	return style


func _settings_tab_style(active: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("ffb52d") if active else Color(0.04, 0.055, 0.065, 0.9)
	style.border_color = Color("ffb52d") if active else Color(0.22, 0.28, 0.32, 0.8)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	return style
