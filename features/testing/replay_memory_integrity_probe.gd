extends Node
## Verifies that live replay capture stays packed and still materializes the
## stable public replay/ghost format at finish.


func _ready() -> void:
	var recorder := ReplayRecorder.new()
	recorder.begin({"event_id": "PROBE", "track_id": "QUARRY"})
	recorder.mark_event(&"START")
	var simulation_hz := 120
	var duration_seconds := 60
	for tick: int in simulation_hz * duration_seconds:
		var time := float(tick) / float(simulation_hz)
		var position := Vector3(time * 9.0, 3.0 + sin(time * 1.7), cos(time * 0.2) * 12.0)
		recorder.capture(1.0 / float(simulation_hz), {
			"position": position,
			"rotation": Quaternion(Vector3.UP, time * 0.12),
			"linear_velocity": Vector3(9.0, cos(time * 1.7) * 1.7, -sin(time * 0.2) * 2.4),
			"angular_velocity": Vector3(0.0, 0.12, 0.0),
			"speed_mps": 9.4,
			"progress": time * 9.0,
			"input": {"throttle": 0.86, "brake": 0.0, "steer": sin(time), "preload": 0.0},
		})
	recorder.mark_event(&"FINISH")
	var live_frames: Array = recorder.get("_sample_frames") as Array
	var packed_live := not live_frames.is_empty()
	for frame: Variant in live_frames:
		packed_live = packed_live and frame is PackedFloat32Array and (frame as PackedFloat32Array).size() == ReplayRecorder.FRAME_COMPONENT_COUNT
	var expected_samples := floori(float(duration_seconds * 1_000_000) / float(ReplayRecorder.DEFAULT_SAMPLE_INTERVAL_USEC)) + 1
	var captured_samples := recorder.sample_count()
	var fixed_rate := absi(captured_samples - expected_samples) <= 1
	var model := recorder.finish()
	var recorder_released := recorder.sample_count() == 0 and (recorder.get("_previous_state") as PackedFloat32Array).is_empty()
	var valid_model := model.is_valid() and model.samples.size() == captured_samples
	var playback := ReplayPlayback.new()
	var playback_loaded := playback.load_model(model)
	var midpoint := playback.sample_at_usec(model.duration_usec / 2) if playback_loaded else {}
	var interpolates := midpoint.get("position", null) is Vector3 and midpoint.get("rotation", null) is Quaternion
	var round_trip := ReplayModel.from_dictionary(model.to_dictionary())
	var serializable := round_trip.is_valid() and round_trip.samples.size() == model.samples.size()
	var passed := packed_live and fixed_rate and recorder_released and valid_model and playback_loaded and interpolates and serializable
	print("REPLAY MEMORY INTEGRITY: live_packed=%s samples=%d expected=%d released=%s valid=%s playback=%s round_trip=%s passed=%s" % [
		str(packed_live), model.samples.size(), expected_samples, str(recorder_released),
		str(valid_model), str(playback_loaded and interpolates), str(serializable), str(passed),
	])
	get_tree().quit(0 if passed else 1)
