extends Node3D
## Behavior equivalence and ownership contracts for the eight runtime fixes.
const VISUAL := preload("res://entities/bike/bike_visual.gd")
var _failures: Array[String] = []
var _sections_completed: Array[StringName] = []

class FullPoseVisual extends "res://entities/bike/bike_visual.gd":
	func _pack_detail_visible() -> bool:
		return true

class CountingHud extends RaceHud:
	var classification_updates := 0
	func update_classification(value: Array) -> void:
		classification_updates += 1
		super.update_classification(value)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	Profile.persistence_enabled = false
	_test_replay()
	_test_bindings()
	await _test_visuals()
	await _test_projection()
	_check(_sections_completed == [&"replay", &"bindings", &"visuals", &"projection"], "A regression section exited before completing")
	for failure: String in _failures:
		push_error(failure)
	print("RUNTIME OPTIMIZATION PROBE: replay_seek_loop_isolation=true binding_cache=true pose_equivalence=true disabled_effects=true projection=true passed=%s" % str(_failures.is_empty()))
	get_tree().quit(0 if _failures.is_empty() else 1)

func _test_replay() -> void:
	var recorder := ReplayRecorder.new()
	recorder.begin({}, 10000)
	for index: int in 4:
		recorder.capture(0.01, {"position": Vector3(index, 0, 0), "rotation": Quaternion.IDENTITY})
	var model := recorder.finish()
	model.events = [
		{"t_usec": 15000, "name": "B"}, {"t_usec": 10000, "name": "A"},
		{"t_usec": 10000, "name": "C"}, {"t_usec": 0, "name": "START"},
		{"t_usec": model.duration_usec, "name": "END"}]
	var playback := ReplayPlayback.new()
	_check(playback.load_model(model), "Valid unsorted replay was rejected")
	var first := playback.advance(0.0)
	_check(_names(first.events) == ["START"], "Initial replay event missing")
	_check((playback.advance(0.0).events as Array).is_empty(), "Pause duplicated a replay event")
	playback.play()
	_check(_names(playback.advance(0.016).events) == ["B", "A", "C"], "Unsorted import emission order changed")
	playback.seek_usec(10000)
	_check(_names(playback.advance(0.0).events) == ["A", "C"], "Seek lost equal-time markers")
	playback.seek_usec(model.duration_usec)
	_check(_names(playback.advance(0.0).events) == ["END"], "End seek lost final marker")
	playback.looping = true
	playback.play()
	_check(_names(playback.advance(0.001).events) == ["START"], "Loop did not restart event cursor")
	var position: Vector3 = playback.sample_at_usec(0).position
	model.samples[0]["position"][0] = 900.0
	model.events[3]["name"] = "MUTATED"
	_check(playback.sample_at_usec(0).position == position, "Replay retained mutable sample aliases")
	playback.seek_usec(0)
	_check(_names(playback.advance(0.0).events) == ["START"], "Replay retained mutable event aliases")
	var invalid := ReplayModel.new()
	_check(not playback.load_model(invalid), "Invalid replay accepted")
	_check(playback.sample_at_usec(0).position == position, "Invalid load destroyed existing playback")
	_sections_completed.append(&"replay")

func _names(events: Array) -> Array:
	var names: Array = []
	for event: Dictionary in events:
		names.append(event.name)
	return names

func _test_bindings() -> void:
	var original := InputMap.action_get_events(InputRouter.FLOW_BOOST)
	InputRouter.get_action_label(InputRouter.FLOW_BOOST)
	InputMap.action_erase_events(InputRouter.FLOW_BOOST)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_F10
	InputMap.action_add_event(InputRouter.FLOW_BOOST, key)
	InputRouter.notify_bindings_changed([InputRouter.FLOW_BOOST])
	_check(InputRouter.get_action_label(InputRouter.FLOW_BOOST, InputRouter.INPUT_MODE_KEYBOARD_MOUSE) == "F10", "Binding cache survived rebinding")
	_check(InputRouter.get_action_label(InputRouter.FLOW_BOOST, InputRouter.INPUT_MODE_GAMEPAD) == "UNBOUND", "Binding cache mixed input modes")
	InputMap.action_erase_events(InputRouter.FLOW_BOOST)
	for event: InputEvent in original:
		InputMap.action_add_event(InputRouter.FLOW_BOOST, event)
	InputRouter.notify_bindings_changed([InputRouter.FLOW_BOOST])
	_sections_completed.append(&"bindings")

func _test_visuals() -> void:
	var camera := Camera3D.new()
	add_child(camera)
	camera.make_current()
	var hidden: Node3D = VISUAL.new()
	var reference := FullPoseVisual.new()
	hidden.pack_variant = true
	reference.pack_variant = true
	add_child(hidden)
	add_child(reference)
	hidden.position.z = 20.0
	reference.position.z = 20.0
	for index: int in 120:
		var args := [17.0 + sin(index), sin(index * 0.12) * 0.6, 0.3, float(index) * 0.4, 1.0 / 60.0,
			true, 0.2, &"MUD", false, 1.0, index > 70]
		hidden.callv(&"update_pack_pose", args)
		reference.callv(&"update_pack_pose", args)
	var work: Dictionary = hidden.get_pack_work_snapshot()
	_check(int(work.articulation_updates) == 0 and int(work.effect_updates) == 0, "Invisible work was not skipped")
	camera.rotation.y = PI
	hidden.call(&"_process", 0.0)
	_compare_transforms(hidden, reference)
	_check(int(hidden.get_pack_work_snapshot().articulation_updates) == 1, "Camera cut did not immediately restore pose")
	hidden.set_pack_effects_enabled(true)
	hidden.update_pack_pose(20.0, 0.5, 0.3, 2.0, 1.0 / 60.0)
	_check(int(hidden.get_pack_work_snapshot().effect_updates) == 1, "Re-enabled particles did not update")
	hidden.set_pack_effects_enabled(false)
	hidden.burst_boost()
	hidden.update_pack_pose(20.0, 0.5, 0.3, 2.0, 1.0 / 60.0)
	_check(int(hidden.get_pack_work_snapshot().effect_updates) == 1, "Disabled particles resumed work")
	for node: Node in [hidden, reference, camera]:
		node.queue_free()
	await get_tree().process_frame
	_sections_completed.append(&"visuals")

func _compare_transforms(first: Node, second: Node) -> void:
	if first is Node3D and second is Node3D:
		_check((first as Node3D).transform.is_equal_approx((second as Node3D).transform), "Pose changed at " + String(first.name))
	if first is MultiMeshInstance3D and second is MultiMeshInstance3D:
		for index: int in first.multimesh.instance_count:
			_check(first.multimesh.get_instance_transform(index).is_equal_approx(second.multimesh.get_instance_transform(index)), "Limb pose changed")
	for index: int in mini(first.get_child_count(), second.get_child_count()):
		_compare_transforms(first.get_child(index), second.get_child(index))

func _test_projection() -> void:
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var garage := main.get_node("GarageUi") as GarageUi
	var race := main.get_node("RaceController") as RaceController
	_check(is_equal_approx(race.get_recording_progress(), float((race.get_session_snapshot().integrity as Dictionary).get(&"total_progress", 0.0))), "Recording progress differs from authoritative snapshot")
	var full := garage.get_workshop_snapshot()
	var lean := garage.get_web_workshop_snapshot()
	for key: Variant in lean:
		_check(lean[key] == full[key], "Lean workshop projection differs: " + str(key))
	var strategy := garage.get_web_event_strategy_snapshot()
	_check(strategy == garage.get_event_strategy_presentation_snapshot(), "Cached strategy differs from live menu")
	strategy[&"setup_comparison"] = {&"tampered": true}
	_check(garage.get_web_event_strategy_snapshot() == garage.get_event_strategy_presentation_snapshot(), "Menu cache exposed mutable data")
	_check(garage.focus_event_briefing(&"ACADEMY"), "Could not change the cached event")
	_check(garage.get_web_event_strategy_snapshot() == garage.get_event_strategy_presentation_snapshot(), "Event change retained stale strategy")
	garage.set_rider_debrief({&"summary": "CACHE REGRESSION"})
	_check(garage.get_web_event_strategy_snapshot() == garage.get_event_strategy_presentation_snapshot(), "Debrief change retained stale strategy")
	garage.call(&"_on_profile_changed", 0, 0, &"BALANCED")
	_check((garage.get(&"_web_strategy_cache") as Dictionary).is_empty(), "Profile change did not invalidate strategy")
	var browser: Dictionary = main.get_web_game_text_state_snapshot()
	_check(browser.mode == "GARAGE", "Open Garage missing from browser state")
	garage.hide_garage()
	browser = main.get_web_game_text_state_snapshot()
	_check(not bool(browser.menu.garage_open), "Closed Garage retained visible browser state")
	var hud := CountingHud.new()
	add_child(hud)
	hud.bind_race_source(race)
	var before := hud.classification_updates
	race.call(&"_update_field_feedback", 0.2)
	_check(hud.classification_updates == before + 1, "Field projection updates classification more than once")
	var gate := {&"active": true, &"throttle": 0.5, &"brake": 0.5, &"brake_staged": false}
	hud.call(&"_update_gate_launch_feedback", gate, &"STAGING")
	var gate_label := hud.get(&"_gate_launch_label") as Label
	var unstaged_color := gate_label.modulate
	gate[&"brake_staged"] = true
	hud.call(&"_update_gate_launch_feedback", gate, &"STAGING")
	_check(not gate_label.modulate.is_equal_approx(unstaged_color), "Text cache hid a changed brake-stage color")
	hud.update_racecraft_state({&"flow": 29.2, &"recommended_flow_cost": 30.0})
	hud.update_flow(29.3, false)
	_check(is_equal_approx((hud.get(&"_flow_bar") as ProgressBar).value, 29.3), "Text cache stopped continuous Flow meter updates")
	var session_only := CountingHud.new()
	add_child(session_only)
	var session := race.get_session_snapshot()
	session[&"classification_already_emitted"] = true
	session_only.update_session_snapshot(session)
	_check(session_only.classification_updates == 1, "Session-only HUD lost classification")
	session_only.queue_free()
	hud.queue_free()
	main.queue_free()
	await get_tree().process_frame
	_sections_completed.append(&"projection")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
