extends Node
## End-to-end contract for deterministic receiver prediction, actionable landing
## coaching, semantic accessibility, haptics, and identity-aware audio.

const RULES := preload("res://features/race/landing_projection.gd")
const BIKE_SCENE := preload("res://entities/bike/bike.tscn")
const HUD_SCENE := preload("res://features/hud/race_hud.tscn")
const AUDIO_SCRIPT := preload("res://features/audio/gameplay_audio.gd")

var _failures: Array[String] = []
var _prediction_events: Array[Dictionary] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_verify_rule_language()
	await _verify_production_chain()
	print("LANDING READABILITY PROBE: failures=%s" % str(_failures))
	get_tree().quit(0 if _failures.is_empty() else 1)


func _verify_rule_language() -> void:
	var grounded := RULES.evaluate({
		&"grounded": true,
		&"airborne_seconds": 0.0,
	})
	var searching := RULES.evaluate({
		&"grounded": false,
		&"airborne_seconds": 0.5,
		&"target_valid": false,
	})
	var safe := RULES.evaluate(_safe_observation())
	var pitch := _safe_observation()
	pitch[&"pitch_error_degrees"] = -27.0
	var pitch_result := RULES.evaluate(pitch)
	var roll := _safe_observation()
	roll[&"roll_error_degrees"] = 24.0
	var roll_result := RULES.evaluate(roll)
	var trick := _safe_observation()
	trick[&"safe_return"] = false
	trick[&"target_distance_m"] = 2.4
	var trick_result := RULES.evaluate(trick)
	var hard := _safe_observation()
	hard[&"impact_speed_mps"] = 12.0
	var hard_result := RULES.evaluate(hard)
	_check(
		not bool(grounded.get(&"visible", true))
		and StringName(grounded.get(&"state", &"")) == RULES.STATE_IDLE,
		"Grounded riding does not hide the airborne-only coach"
	)
	_check(
		bool(searching.get(&"visible", false))
		and StringName(searching.get(&"state", &"")) == RULES.STATE_SEARCH
		and str(searching.get(&"text", "")).contains("SCAN RECEIVER"),
		"Missing receiver does not produce a readable search state"
	)
	_check(
		bool(safe.get(&"likely_safe", false))
		and StringName(safe.get(&"state", &"")) == RULES.STATE_SET
		and str(safe.get(&"text", "")).contains("LIKELY SAFE")
		and str(safe.get(&"text", "")).contains("HOLD"),
		"Aligned descent is not explicitly identified as likely safe"
	)
	_check(
		StringName(pitch_result.get(&"state", &"")) == RULES.STATE_ADJUST
		and str(pitch_result.get(&"cue", "")) == "LEAN FORWARD",
		"Signed pitch error does not produce the correct rider-weight instruction"
	)
	_check(
		StringName(roll_result.get(&"state", &"")) == RULES.STATE_ADJUST
		and str(roll_result.get(&"cue", "")) == "LEVEL BIKE",
		"Roll error does not take priority over generic landing advice"
	)
	_check(
		StringName(trick_result.get(&"state", &"")) == RULES.STATE_DANGER
		and str(trick_result.get(&"cue", "")) == "RETURN TO BIKE"
		and str(trick_result.get(&"text", "")).contains("HIGH RISK"),
		"Late trick return is not communicated as a semantic high-risk state"
	)
	_check(
		StringName(hard_result.get(&"state", &"")) == RULES.STATE_DANGER
		and int(hard_result.get(&"confidence_percent", 100))
			< int(safe.get(&"confidence_percent", 0)),
		"Hard impact does not lower confidence and escalate landing risk"
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
	var audio_callback := Callable(audio, &"_on_landing_projection_event")
	if not bike.landing_projection_event.is_connected(audio_callback):
		bike.landing_projection_event.connect(audio_callback)
	if not bike.landing_projection_event.is_connected(_capture_prediction_event):
		bike.landing_projection_event.connect(_capture_prediction_event)
	await get_tree().process_frame

	bike.set_controls_enabled(true)
	bike.set(&"_grounded", false)
	bike.set(&"_airtime", 0.9)
	bike.set(&"_landing_target_valid", true)
	bike.set(&"_landing_target_normal", Vector3.UP)
	bike.set(&"_landing_target_distance", 2.6)
	bike.global_transform = Transform3D(
		Basis(Vector3.FORWARD, deg_to_rad(55.0)),
		Vector3(0.0, 3.0, 0.0)
	)
	bike.linear_velocity = Vector3(0.0, -8.0, -14.0)
	bike.angular_velocity = Vector3(0.0, 0.0, 4.0)
	bike.call(&"_update_landing_projection")
	var danger := bike.get_landing_projection_snapshot()
	bike.landing_projection_changed.emit(danger)
	var danger_hud := hud.get_landing_projection_presentation_snapshot()
	var danger_haptic := bike.get_haptic_feedback_snapshot()
	var danger_request := danger_haptic.get(&"last_request", {}) as Dictionary
	_check(
		StringName(danger.get(&"state", &"")) == RULES.STATE_DANGER
		and not bool(danger.get(&"likely_safe", true))
		and not _prediction_events.is_empty()
		and StringName(_prediction_events[0].get(&"kind", &"")) == &"DANGER",
		"Production bike does not emit one authoritative close-range danger transition"
	)
	_check(
		bool(danger_hud.get(&"visible", false))
		and str(danger_hud.get(&"text", "")).contains("HIGH RISK")
		and float(danger_hud.get(&"confidence", 100.0)) < 68.0
		and _rect_inside_viewport(danger_hud.get(&"rect", Rect2()) as Rect2),
		"HUD does not show contained semantic risk text and matching confidence"
	)
	_check(
		StringName(danger_request.get(&"kind", &"")) == &"LANDING_DANGER"
		and float(danger_request.get(&"high_motor", 0.0)) > 0.0,
		"Close-range landing danger does not provide a bounded haptic warning"
	)

	bike.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 2.2, 0.0))
	bike.linear_velocity = Vector3(0.0, -6.0, -14.0)
	bike.angular_velocity = Vector3(0.15, 0.1, 0.0)
	bike.set(&"_landing_target_distance", 1.8)
	bike.call(&"_update_landing_projection")
	var recovered := bike.get_landing_projection_snapshot()
	bike.landing_projection_changed.emit(recovered)
	var recovered_hud := hud.get_landing_projection_presentation_snapshot()
	var audio_feedback := audio.get_racecraft_audio_feedback_snapshot()
	var cue_ready := audio_feedback.get(&"landing_prediction_cues_ready", {}) as Dictionary
	_check(
		StringName(recovered.get(&"state", &"")) == RULES.STATE_SET
		and bool(recovered.get(&"likely_safe", false))
		and _prediction_events.size() == 2
		and StringName(_prediction_events[1].get(&"kind", &"")) == &"RECOVERED",
		"Correcting the bike does not transition once from danger to likely-safe"
	)
	_check(
		str(recovered_hud.get(&"text", "")).contains("LIKELY SAFE")
		and str(recovered_hud.get(&"text", "")).contains("HOLD")
		and float(recovered_hud.get(&"confidence", 0.0)) >= 68.0,
		"HUD does not immediately acknowledge a successful landing correction"
	)
	_check(
		int(audio_feedback.get(&"landing_prediction_feedback_count", 0)) == 2
		and StringName(audio_feedback.get(&"last_landing_prediction_kind", &""))
			== &"RECOVERED"
		and bool(cue_ready.get(&"DANGER", false))
		and bool(cue_ready.get(&"RECOVERED", false)),
		"Landing danger and recovery do not own distinct ready SFX identities"
	)

	bike.set(&"_grounded", true)
	bike.call(&"_update_landing_projection")
	bike.landing_projection_changed.emit(bike.get_landing_projection_snapshot())
	var grounded_hud := hud.get_landing_projection_presentation_snapshot()
	_check(
		not bool(grounded_hud.get(&"visible", true)),
		"Landing coach remains visible after wheel contact"
	)
	if bike.landing_projection_event.is_connected(_capture_prediction_event):
		bike.landing_projection_event.disconnect(_capture_prediction_event)
	hud.queue_free()
	audio.queue_free()
	bike.queue_free()
	await get_tree().process_frame


func _safe_observation() -> Dictionary:
	return {
		&"grounded": false,
		&"airborne_seconds": 0.9,
		&"target_valid": true,
		&"target_distance_m": 2.8,
		&"orientation_alignment": 0.96,
		&"travel_alignment": 0.94,
		&"pitch_error_degrees": 3.0,
		&"roll_error_degrees": 2.0,
		&"impact_speed_mps": 5.8,
		&"angular_speed_rps": 0.8,
		&"safe_return": true,
	}


func _capture_prediction_event(kind: StringName, snapshot: Dictionary) -> void:
	var event := snapshot.duplicate(true)
	event[&"kind"] = kind
	_prediction_events.append(event)


func _rect_inside_viewport(rect: Rect2) -> bool:
	var viewport_rect := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	return rect.size.x > 0.0 and rect.size.y > 0.0 and viewport_rect.encloses(rect)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
	push_error("LANDING READABILITY PROBE: %s" % message)
