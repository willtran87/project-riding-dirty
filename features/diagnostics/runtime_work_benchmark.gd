extends Node
## Opt-in diagnostic scene; never attached to normal gameplay. Run with the
## release template for comparable timings, rather than the editor debugger.
var subject: Node

func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	Profile.persistence_enabled = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var main := subject
	if main == null:
		main = load("res://scenes/main.tscn").instantiate()
		add_child(main)
	for frame: int in 8:
		await get_tree().process_frame
	var race := main.get("_race") as RaceController
	var results := {"release": not OS.is_debug_build(), "cases": {}}
	results.cases["recording_progress"] = _measure(func() -> void:
		if race.has_method(&"get_recording_progress"):
			race.call(&"get_recording_progress")
		else:
			var session := race.get_session_snapshot()
			float((session.get(&"integrity", {}) as Dictionary).get(&"total_progress", 0.0)), 1000)
	# These input fields force a racing projection without starting a simulation.
	# The diagnostic measures projection construction, not actual frame rate.
	var garage := main.get("_garage") as GarageUi
	garage.call(&"hide_garage")
	results.cases["web_racing_projection"] = _measure(func() -> void:
		main.call(&"get_web_game_text_state_snapshot"), 100)
	results.cases["binding_label"] = _measure(func() -> void:
		InputRouter.get_action_label(InputRouter.FLOW_BOOST, InputRouter.INPUT_MODE_KEYBOARD_MOUSE, 1), 10000)
	var recorder := ReplayRecorder.new()
	recorder.begin()
	for frame: int in 3601:
		recorder.capture(1.0 / 30.0, {"position": Vector3(frame, 0, 0), "rotation": Quaternion.IDENTITY})
	var model := recorder.finish()
	for index: int in 2048:
		model.events.append({"t_usec": index * 1000, "name": "PROBE"})
	results.cases["replay_load"] = _measure(func() -> void:
		var playback := ReplayPlayback.new()
		playback.load_model(model), 5)
	var playback := ReplayPlayback.new()
	playback.load_model(model)
	playback.seek_usec(3_000_000)
	playback.play()
	results.cases["replay_event_lookup"] = _measure(func() -> void:
		playback.advance(1.0 / 60.0), 1000)
	results["memory_static_bytes"] = Performance.get_monitor(Performance.MEMORY_STATIC)
	print("RUNTIME WORK BENCHMARK: " + JSON.stringify(results))
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__runtimeBenchmark = %s;" % JSON.stringify(results))
	else:
		get_tree().quit()
	if subject == null:
		main.queue_free()


func _measure(operation: Callable, count: int) -> Dictionary:
	for warmup: int in 3:
		operation.call()
	var samples: Array[float] = []
	for round_index: int in 7:
		var begin := Time.get_ticks_usec()
		for iteration: int in count:
			operation.call()
		samples.append(float(Time.get_ticks_usec() - begin) / count)
	samples.sort()
	return {"median_usec": samples[3], "max_batch_usec_per_call": samples[6], "iterations_per_batch": count}
