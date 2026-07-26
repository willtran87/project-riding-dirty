extends Node
## Deterministic contract for physical automatic/manual transmission behavior.

var _passed: bool = true
var _shift_events: Array[Dictionary] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var transmission := BikeTransmission.new()
	transmission.shifted.connect(_on_shifted)

	_check(transmission.mode == BikeTransmission.MODE_AUTOMATIC, "automatic is not the approachable default")
	_check(transmission.current_gear == 1, "transmission did not initialize in first gear")
	var launch_multiplier := transmission.get_drive_multiplier()
	_check(launch_multiplier >= 1.0, "first gear does not preserve responsive launch drive")

	transmission.update(0.016, 8.6, 1.0, true, false, false, 30.0)
	_check(transmission.current_gear == 2, "automatic gearbox did not upshift through the first speed band")
	_check(transmission.shift_cut_remaining > 0.0, "upshift omitted the physical torque cut")
	_check(
		transmission.get_drive_multiplier() < launch_multiplier * 0.5,
		"shift cut does not materially interrupt rear-wheel drive"
	)
	transmission.update(0.04, 15.0, 1.0, true, false, false, 30.0)
	_check(transmission.current_gear == 2, "automatic gearbox hunted during the shift cut")
	transmission.update(0.20, 15.0, 1.0, true, false, false, 30.0)
	_check(transmission.current_gear == 3, "automatic gearbox did not continue into third gear")
	transmission.update(0.20, 20.0, 1.0, true, false, false, 30.0)
	_check(transmission.current_gear == 4, "automatic gearbox did not continue into fourth gear")
	transmission.update(0.20, 26.0, 1.0, true, false, false, 30.0)
	_check(transmission.current_gear == 5, "automatic gearbox did not reach top gear")
	transmission.update(0.20, 18.0, 0.0, true, false, false, 30.0)
	_check(transmission.current_gear == 3, "automatic gearbox did not synchronize into the lower speed band")

	_check(transmission.configure_mode(&"MANUAL"), "manual mode change was rejected")
	transmission.reset()
	_check(transmission.mode == BikeTransmission.MODE_MANUAL, "reset discarded the selected transmission mode")
	transmission.update(0.016, 0.0, 0.8, true, true, false, 30.0)
	_check(transmission.current_gear == 2, "manual shift-up request did not select second gear")
	transmission.update(0.016, 26.0, 1.0, true, false, false, 30.0)
	_check(transmission.current_gear == 2, "manual gearbox shifted without player input")
	transmission.update(0.20, 26.0, 1.0, true, true, false, 30.0)
	_check(transmission.current_gear == 3, "manual gearbox did not accept a post-cut upshift")
	transmission.update(0.20, 18.0, 0.5, true, false, true, 30.0)
	_check(transmission.current_gear == 2, "manual shift-down request did not select the lower gear")
	transmission.update(0.20, 18.0, 1.0, true, false, false, 30.0)
	_check(
		transmission.normalized_rpm >= 1.0 and transmission.get_drive_multiplier() <= 0.2,
		"holding an over-revved manual gear does not sacrifice propulsion"
	)

	var snapshot := transmission.get_snapshot()
	_check(StringName(snapshot.get(&"mode", &"")) == &"MANUAL", "snapshot omitted manual mode")
	_check(
		float(snapshot.get(&"last_shift_rpm", -1.0)) >= 0.10
			and float(snapshot.get(&"last_shift_rpm", 2.0)) <= 1.10,
		"snapshot omitted the authoritative RPM captured at shift acceptance"
	)
	_check(int(snapshot.get(&"gear_count", 0)) == 5, "snapshot omitted the five-speed contract")
	_check(int(snapshot.get(&"suggested_gear", 0)) > transmission.current_gear, "manual snapshot omitted an actionable suggested gear")
	_check(_shift_events.size() >= 7, "shift signal coverage missed automatic or manual changes")

	var engine_audio := EngineAudio.new()
	add_child(engine_audio)
	engine_audio.set_engine_state(
		18.0, 0.75, true, &"PACKED", 0.35, 0.0, 0.0,
		3, 0.72, BikeTransmission.SHIFT_DURATION_SECONDS * 0.5
	)
	_check(bool(engine_audio.get("_authoritative_transmission")), "engine audio ignored authoritative transmission state")
	_check(int(engine_audio.get("_gear")) == 3, "engine audio gear diverged from physics")
	_check(is_equal_approx(float(engine_audio.get("_authoritative_rpm")), 0.72), "engine audio RPM diverged from physics")
	engine_audio.reset_surface_feedback()
	_check(not bool(engine_audio.get("_authoritative_transmission")), "engine audio reset retained stale authoritative gearing")

	print(
		"TRANSMISSION SYSTEM PROBE: mode=%s gear=%d rpm=%.3f shifts=%d drive=%.3f passed=%s"
		% [
			String(transmission.mode),
			transmission.current_gear,
			transmission.normalized_rpm,
			_shift_events.size(),
			transmission.get_drive_multiplier(),
			str(_passed),
		]
	)
	engine_audio.queue_free()
	get_tree().quit(0 if _passed else 1)


func _on_shifted(from_gear: int, to_gear: int, mode: StringName) -> void:
	_shift_events.append({
		&"from": from_gear,
		&"to": to_gear,
		&"mode": mode,
	})


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_passed = false
	push_error("TRANSMISSION SYSTEM PROBE: " + message)
