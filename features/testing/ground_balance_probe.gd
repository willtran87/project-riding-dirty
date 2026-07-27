extends Node
## End-to-end contract for front-brake load transfer, one-wheel recognition,
## semantic coaching, Flow/style rewards, haptics, and racecraft audio identity.

const RULES := preload("res://features/race/ground_balance_rules.gd")
const BIKE_SCENE := preload("res://entities/bike/bike.tscn")
const HUD_SCENE := preload("res://features/hud/race_hud.tscn")
const AUDIO_SCRIPT := preload("res://features/audio/gameplay_audio.gd")

var _failures: Array[String] = []
var _events: Array[Dictionary] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_verify_rule_language()
	await _verify_production_chain()
	await _verify_physical_stoppie()
	print("GROUND BALANCE PROBE: failures=%s" % str(_failures))
	get_tree().quit(0 if _failures.is_empty() else 1)


func _verify_rule_language() -> void:
	var idle := RULES.evaluate({})
	var setup := RULES.evaluate({
		&"front_contact": true,
		&"rear_contact": true,
		&"speed_mps": 14.0,
		&"brake": 1.0,
		&"lean": -1.0,
	})
	var wheelie := RULES.evaluate({
		&"front_contact": false,
		&"rear_contact": true,
		&"speed_mps": 12.0,
		&"pitch_degrees": 29.0,
		&"wheelie_seconds": RULES.WHEELIE_AWARD_SECONDS,
	})
	var stoppie := RULES.evaluate({
		&"front_contact": true,
		&"rear_contact": false,
		&"speed_mps": 10.0,
		&"brake": 1.0,
		&"lean": -1.0,
		&"pitch_degrees": -29.0,
		&"stoppie_seconds": RULES.STOPPIE_AWARD_SECONDS,
	})
	var baseline_bias := RULES.front_brake_bias(1.0 / 3.0, 1.0, 0.0, 14.0)
	var deliberate_bias := RULES.front_brake_bias(1.0 / 3.0, 1.0, -1.0, 14.0)
	_check(
		not bool(idle.get(&"active", true))
		and StringName(idle.get(&"state", &"")) == &"IDLE",
		"Neutral riding keeps the balance coach silent"
	)
	_check(
		StringName(setup.get(&"state", &"")) == &"LOAD_FRONT"
		and str(setup.get(&"text", "")).contains("HOLD BRAKE + LEAN FORWARD")
		and float(setup.get(&"progress", 0.0)) >= 0.99,
		"Deliberate stoppie setup has actionable load-transfer coaching"
	)
	_check(
		StringName(wheelie.get(&"state", &"")) == &"WHEELIE"
		and str(wheelie.get(&"cue", "")) == "LEAN FORWARD"
		and is_equal_approx(float(wheelie.get(&"progress", 0.0)), 1.0),
		"Wheelie projection has direction-aware balance coaching"
	)
	_check(
		StringName(stoppie.get(&"state", &"")) == &"STOPPIE"
		and str(stoppie.get(&"cue", "")) == "LEAN BACK"
		and is_equal_approx(float(stoppie.get(&"progress", 0.0)), 1.0),
		"Stoppie projection has direction-aware balance coaching"
	)
	_check(
		is_equal_approx(baseline_bias, 1.0 / 3.0)
		and deliberate_bias >= 0.70
		and deliberate_bias <= RULES.STOPPIE_FRONT_BIAS,
		"Neutral brake balance is preserved and deliberate stoppie bias is bounded"
	)


func _verify_production_chain() -> void:
	var bike := BIKE_SCENE.instantiate() as DirtBikeController
	bike.freeze = true
	add_child(bike)
	var hud := HUD_SCENE.instantiate() as RaceHud
	add_child(hud)
	hud.initialize(bike)
	var audio := AUDIO_SCRIPT.new() as GameplayAudio
	add_child(audio)
	audio.call(&"_build_cues")
	var audio_callback := Callable(audio, &"_on_bike_racecraft_event")
	if not bike.racecraft_event.is_connected(audio_callback):
		bike.racecraft_event.connect(audio_callback)
	bike.racecraft_event.connect(_capture_event)
	await get_tree().process_frame

	var front: Variant = bike.get("_front_contact")
	var rear: Variant = bike.get("_rear_contact")
	front.set("colliding", true)
	rear.set("colliding", false)
	bike.set("_last_brake", 1.0)
	bike.set("_last_lean", -1.0)
	bike.global_transform = Transform3D(
		Basis(Vector3.RIGHT, deg_to_rad(-29.0)),
		Vector3.ZERO
	)
	for _frame: int in 42:
		bike.call(&"_update_ground_balance", 1.0 / 60.0, 10.0)
	var stoppie_snapshot := bike.get_ground_balance_snapshot()
	var stoppie_hud := hud.get_ground_balance_presentation_snapshot()
	var stoppie_haptic := bike.get_haptic_feedback_snapshot()
	var stoppie_request := stoppie_haptic.get(&"last_request", {}) as Dictionary
	var racecraft := bike.get_racecraft_snapshot()
	var counters := racecraft.get(&"counters", {}) as Dictionary
	_check(
		StringName(stoppie_snapshot.get(&"state", &"")) == &"STOPPIE"
		and float(stoppie_snapshot.get(&"progress", 0.0)) >= 0.99
		and int(counters.get(&"STOPPIE", 0)) == 1
		and _event_count(&"STOPPIE") == 1
		and bike.get_flow() >= 4.99,
		"Production bike awards exactly one sustained stoppie"
	)
	_check(
		bool(stoppie_hud.get(&"visible", false))
		and str(stoppie_hud.get(&"text", "")).contains("STOPPIE")
		and str(stoppie_hud.get(&"text", "")).contains("LEAN BACK")
		and float(stoppie_hud.get(&"progress", 0.0)) >= 0.99,
		"Shared HUD meter presents semantic stoppie progress and correction"
	)
	_check(
		StringName(stoppie_request.get(&"kind", &"")) == &"STOPPIE"
		and float(stoppie_request.get(&"high_motor", 0.0)) > 0.0
		and int(audio.get("_last_racecraft_cue_usec")) > 0,
		"Stoppie success has distinct bounded haptic and audio feedback"
	)

	front.set("colliding", false)
	rear.set("colliding", true)
	bike.set("_last_brake", 0.0)
	bike.set("_last_lean", 1.0)
	bike.global_transform = Transform3D(
		Basis(Vector3.RIGHT, deg_to_rad(29.0)),
		Vector3.ZERO
	)
	for _frame: int in 51:
		bike.call(&"_update_ground_balance", 1.0 / 60.0, 12.0)
	var wheelie_snapshot := bike.get_ground_balance_snapshot()
	var wheelie_hud := hud.get_ground_balance_presentation_snapshot()
	counters = (bike.get_racecraft_snapshot().get(&"counters", {}) as Dictionary)
	_check(
		StringName(wheelie_snapshot.get(&"state", &"")) == &"WHEELIE"
		and int(counters.get(&"WHEELIE", 0)) == 1
		and _event_count(&"WHEELIE") == 1
		and str(wheelie_hud.get(&"text", "")).contains("LEAN FORWARD"),
		"Existing wheelie uses the same readable reward contract"
	)

	bike.respawn_at(Transform3D.IDENTITY)
	var reset := bike.get_ground_balance_snapshot()
	var reset_hud := hud.get_ground_balance_presentation_snapshot()
	var reset_counters := bike.get_racecraft_snapshot().get(&"counters", {}) as Dictionary
	_check(
		StringName(reset.get(&"state", &"")) == &"IDLE"
		and not bool(reset_hud.get(&"visible", true))
		and reset_counters.is_empty(),
		"Respawn clears one-wheel progress, presentation, and counters"
	)


func _verify_physical_stoppie() -> void:
	var ground := StaticBody3D.new()
	ground.collision_layer = 2
	ground.collision_mask = 1
	ground.set_meta(&"surface", &"PACKED")
	ground.set_meta(&"roughness", 0.35)
	var ground_shape := BoxShape3D.new()
	ground_shape.size = Vector3(120.0, 0.5, 120.0)
	var collision := CollisionShape3D.new()
	collision.shape = ground_shape
	ground.position.y = -0.25
	ground.add_child(collision)
	add_child(ground)
	var bike := BIKE_SCENE.instantiate() as DirtBikeController
	bike.position = Vector3(0.0, 0.67, 18.0)
	add_child(bike)
	bike.set_controls_enabled(true)
	bike.configure_feedback({&"haptics_enabled": false, &"haptics_intensity": 0.0})
	await _wait_physics_frames(90)
	bike.linear_velocity = Vector3(0.0, 0.0, -16.0)
	Input.action_press(InputRouter.BRAKE, 1.0)
	Input.action_press(InputRouter.LEAN_FORWARD, 1.0)
	var rear_lift_frames := 0
	var maximum_stoppie_progress := 0.0
	var saw_load_front := false
	var stopped_cleanly := true
	for _frame: int in 110:
		await get_tree().physics_frame
		var front: Variant = bike.get("_front_contact")
		var rear: Variant = bike.get("_rear_contact")
		if bool(front.get("colliding")) and not bool(rear.get("colliding")):
			rear_lift_frames += 1
		var snapshot := bike.get_ground_balance_snapshot()
		maximum_stoppie_progress = maxf(
			maximum_stoppie_progress,
			float(snapshot.get(&"progress", 0.0))
		)
		saw_load_front = saw_load_front or StringName(snapshot.get(&"state", &"")) == &"STOPPIE"
		stopped_cleanly = stopped_cleanly and bike.global_transform.basis.y.normalized().dot(Vector3.UP) > 0.35
	Input.action_release(InputRouter.BRAKE)
	Input.action_release(InputRouter.LEAN_FORWARD)
	var physical_counters := (
		bike.get_racecraft_snapshot().get(&"counters", {}) as Dictionary
	)
	print("  PHYSICS: rear_lift_frames=%d max_progress=%.3f awards=%d upright=%s" % [
		rear_lift_frames,
		maximum_stoppie_progress,
		int(physical_counters.get(&"STOPPIE", 0)),
		str(stopped_cleanly),
	])
	_check(
		rear_lift_frames >= 6
		and saw_load_front
		and maximum_stoppie_progress >= 0.10
		and int(physical_counters.get(&"STOPPIE", 0)) == 1
		and stopped_cleanly,
		"Hard braking plus forward weight transfer physically earns one stoppie without a forced crash"
	)
	bike.queue_free()
	ground.queue_free()


func _wait_physics_frames(count: int) -> void:
	for _frame: int in count:
		await get_tree().physics_frame


func _capture_event(kind: StringName, payload: Dictionary) -> void:
	_events.append({
		&"kind": kind,
		&"payload": payload.duplicate(true),
	})


func _event_count(kind: StringName) -> int:
	var count := 0
	for event: Dictionary in _events:
		if StringName(event.get(&"kind", &"")) == kind:
			count += 1
	return count


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  PASS: %s" % message)
		return
	_failures.append(message)
	push_error("GROUND BALANCE PROBE: %s" % message)
