extends Node
## End-to-end contract for deliberate trick input, physical classification,
## safe-return landing skill, variety scoring, rider poses, and readable HUD
## receipts.

const RULES := preload("res://features/freestyle/freestyle_trick_rules.gd")
const BIKE_SCENE := preload("res://entities/bike/bike.tscn")
const BIKE_VISUAL_SCRIPT := preload("res://entities/bike/bike_visual.gd")
const HUD_SCENE := preload("res://features/hud/race_hud.tscn")
const AUDIO_SCRIPT := preload("res://features/audio/gameplay_audio.gd")

var _failures: Array[String] = []
var _last_event: Dictionary = {}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_verify_input_language()
	_verify_classification_and_score_rules()
	await _verify_production_observation()
	await _verify_rider_animation()
	await _verify_controller_and_hud_receipt()
	print("FREESTYLE TRICK DEPTH PROBE: failures=%s" % str(_failures))
	get_tree().quit(0 if _failures.is_empty() else 1)


func _verify_input_language() -> void:
	var neutral := RULES.pose_from_input(true, 0.0, 0.0)
	var forward := RULES.pose_from_input(true, 0.0, -1.0)
	var back := RULES.pose_from_input(true, 0.0, 1.0)
	var left := RULES.pose_from_input(true, -1.0, 0.0)
	var right := RULES.pose_from_input(true, 1.0, 0.0)
	var released := RULES.pose_from_input(false, 1.0, -1.0)
	_check(
		StringName(neutral.get(&"pose_id", &"")) == &"NO_HANDER"
		and StringName(forward.get(&"pose_id", &"")) == &"SUPERMAN"
		and StringName(back.get(&"pose_id", &"")) == &"SEAT_GRAB"
		and StringName(left.get(&"pose_id", &"")) == &"CAN_CAN_LEFT"
		and StringName(right.get(&"pose_id", &"")) == &"CAN_CAN_RIGHT"
		and StringName(released.get(&"pose_id", &"")) == &"NONE",
		"Modifier plus directional input does not map to five distinct intentional poses"
	)
	_check(
		InputMap.has_action(InputRouter.RACECRAFT)
		and not InputMap.action_get_events(InputRouter.RACECRAFT).is_empty(),
		"Airborne trick modifier is not a configurable semantic action"
	)


func _verify_classification_and_score_rules() -> void:
	var observation := _clean_observation()
	observation[&"pitch_rotation"] = TAU * 0.92
	observation[&"total_rotation"] = TAU * 1.08
	observation[&"modifier_time"] = 0.72
	observation[&"safe_return_time"] = 0.22
	observation[&"pose_times"] = {&"SUPERMAN": 0.72}
	var classification := RULES.classify(observation)
	_check(
		StringName(classification.get(&"trick_id", &"")) == &"BACKFLIP_SUPERMAN"
		and str(classification.get(&"trick_name", "")).contains("BACKFLIP")
		and str(classification.get(&"trick_name", "")).contains("SUPERMAN"),
		"Measured pitch plus a held pose did not classify as a combined trick"
	)
	var varied := RULES.evaluate(observation, {
		&"combo": 2,
		&"repeat_count": 0,
		&"recent_trick_ids": [&"NO_HANDER"],
	})
	var repeated := RULES.evaluate(observation, {
		&"combo": 2,
		&"repeat_count": 3,
		&"recent_trick_ids": [&"BACKFLIP_SUPERMAN"],
	})
	_check(
		float(varied.get(&"variety_multiplier", 1.0)) > 1.0
		and float(repeated.get(&"repetition_multiplier", 1.0)) <= 0.35
		and int(varied.get(&"awarded_points", 0)) > int(repeated.get(&"awarded_points", 0)),
		"Variety is not rewarded or repeated tricks are not transparently devalued"
	)
	var late := observation.duplicate(true)
	late[&"safe_return_time"] = 0.0
	late[&"modifier_held_at_landing"] = true
	var late_result := RULES.evaluate(late, {&"combo": 5})
	_check(
		StringName(late_result.get(&"landing_grade", &"")) == &"LATE_RETURN"
		and not bool(late_result.get(&"clean", true))
		and int(late_result.get(&"combo", 99)) == 1
		and int(late_result.get(&"awarded_points", 999999)) < int(varied.get(&"awarded_points", 0)),
		"Failing to return to the bike before landing has no execution or combo consequence"
	)
	var hard_landing := observation.duplicate(true)
	hard_landing[&"physical_clean"] = false
	hard_landing[&"landing_intensity"] = 1.0
	hard_landing[&"upright_alignment"] = 0.72
	var hard_result := RULES.evaluate(hard_landing, {&"combo": 3})
	hard_landing[&"upright_alignment"] = 0.1
	var crashed_result := RULES.evaluate(hard_landing, {&"combo": 3})
	_check(
		StringName(hard_result.get(&"landing_grade", &"")) == &"HARD_LANDING"
		and StringName(crashed_result.get(&"landing_grade", &"")) == &"CRASHED",
		"Upright over-impact landing is not distinguished from an actual crash"
	)
	_check(
		int(varied.get(&"base_points", 0)) > 0
		and int(varied.get(&"airtime_points", 0)) > 0
		and int(varied.get(&"rotation_points", 0)) > 0
		and int(varied.get(&"landing_points", 0)) > 0
		and float(varied.get(&"combo_multiplier", 0.0)) > 1.0,
		"Score receipt does not expose every major scoring component"
	)


func _verify_production_observation() -> void:
	var bike := BIKE_SCENE.instantiate() as DirtBikeController
	add_child(bike)
	bike.set_controls_enabled(true)
	bike.set(&"_grounded", false)
	bike.set(&"_airtime", 0.55)
	bike.set(&"_freestyle_takeoff_valid", true)
	bike.angular_velocity = Vector3(3.0, 1.0, 0.5)
	Input.action_press(InputRouter.RACECRAFT, 1.0)
	bike.call(&"_update_freestyle_observation", 0.0, -1.0, 0.24)
	Input.action_release(InputRouter.RACECRAFT)
	bike.call(&"_update_freestyle_observation", 0.0, 0.0, 0.16)
	var snapshot := bike.get_freestyle_trick_snapshot()
	var pose_times := snapshot.get(&"pose_times", {}) as Dictionary
	_check(
		float(snapshot.get(&"pitch_rotation", 0.0)) > 0.0
		and float(snapshot.get(&"modifier_time", 0.0)) >= 0.24
		and float(snapshot.get(&"safe_return_time", 0.0)) >= 0.16
		and float(pose_times.get(&"SUPERMAN", 0.0)) >= 0.24
		and not bool(snapshot.get(&"modifier_held_at_landing", true)),
		"Production bike does not measure rotation, held pose, and safe release timing"
	)
	bike.respawn_at(Transform3D.IDENTITY)
	var reset := bike.get_freestyle_trick_snapshot()
	_check(
		is_zero_approx(float(reset.get(&"modifier_time", -1.0)))
		and (reset.get(&"pose_times", {}) as Dictionary).is_empty()
		and not bool(reset.get(&"contact_observed_since_respawn", true)),
		"Respawn retains stale trick or takeoff-contact authority"
	)
	bike.queue_free()
	await get_tree().process_frame


func _verify_rider_animation() -> void:
	var visual := BIKE_VISUAL_SCRIPT.new() as Node3D
	add_child(visual)
	await get_tree().process_frame
	for _step: int in 16:
		visual.call(&"_update_trick_pose_state", {
			&"pose_id": &"SUPERMAN",
			&"strength": 1.0,
			&"side": 0.0,
		}, 1.0 / 60.0)
		visual.call(&"_update_rider_limbs", 0.0, -1.0, false)
	var extended := visual.call(&"get_trick_animation_snapshot") as Dictionary
	_check(
		StringName(extended.get(&"pose_id", &"")) == &"SUPERMAN"
		and float(extended.get(&"left_foot_displacement", 0.0)) > 0.35
		and float(extended.get(&"right_foot_displacement", 0.0)) > 0.35,
		"Superman identity does not produce a visible articulated two-leg extension"
	)
	for _step: int in 30:
		visual.call(&"_update_trick_pose_state", {}, 1.0 / 60.0)
		visual.call(&"_update_rider_limbs", 0.0, 0.0, false)
	var returned := visual.call(&"get_trick_animation_snapshot") as Dictionary
	_check(
		float(returned.get(&"blend", 1.0)) < 0.05
		and float(returned.get(&"left_foot_displacement", 1.0)) < 0.05
		and float(returned.get(&"right_foot_displacement", 1.0)) < 0.05,
		"Rider animation does not smoothly reconnect both feet to the bike"
	)
	visual.queue_free()
	await get_tree().process_frame


func _verify_controller_and_hud_receipt() -> void:
	var controller := FreestyleController.new()
	add_child(controller)
	controller.active = true
	controller.score = 0
	controller.combo = 1
	if not EventBus.freestyle_trick_scored.is_connected(_capture_event):
		EventBus.freestyle_trick_scored.connect(_capture_event)
	var hud := HUD_SCENE.instantiate() as RaceHud
	add_child(hud)
	var audio := AUDIO_SCRIPT.new() as GameplayAudio
	add_child(audio)
	await get_tree().process_frame
	EventBus.activity_prepared.emit(&"FREESTYLE")
	EventBus.activity_started.emit(&"FREESTYLE")
	var prompt := hud.get_freestyle_presentation_snapshot()
	_check(
		str(prompt.get(&"message", "")).contains(
			InputRouter.get_action_label(InputRouter.RACECRAFT)
		)
		and str(prompt.get(&"message", "")).contains("RELEASE"),
		"Freestyle onboarding does not teach the active binding and safe return"
	)
	_last_event.clear()
	var spawn_drop := _clean_observation()
	spawn_drop[&"airtime"] = 0.32
	spawn_drop[&"takeoff_valid"] = false
	controller.call(&"_on_trick_resolved", spawn_drop)
	_check(
		controller.score == 0 and _last_event.is_empty(),
		"Elevated spawn drop awards a free trick before a ground-to-air takeoff"
	)
	controller.call(&"_on_trick_resolved", _clean_observation())
	var scoring := controller.get_scoring_snapshot()
	var presentation := hud.get_freestyle_presentation_snapshot()
	var audio_feedback := audio.get_racecraft_audio_feedback_snapshot()
	var message := str(presentation.get(&"message", ""))
	_check(
		not _last_event.is_empty()
		and int(scoring.get(&"score", 0)) > 0
		and not (scoring.get(&"last_trick", {}) as Dictionary).is_empty(),
		"Freestyle controller did not settle a physical observation into an authoritative score"
	)
	_check(
		message.contains("STRAIGHT AIR")
		and message.contains("BASE")
		and message.contains("AIR")
		and message.contains("ROT")
		and message.contains("LAND")
		and message.contains("VAR")
		and message.contains("REPEAT")
		and message.contains("COMBO"),
		"HUD does not present trick identity, landing, score breakdown, variety, repetition, and combo"
	)
	_check(
		int(audio_feedback.get(&"freestyle_feedback_count", 0)) == 1
		and str(
			(audio_feedback.get(&"last_freestyle_feedback", {}) as Dictionary).get(
				&"trick_name", ""
			)
		) == "STRAIGHT AIR",
		"Authoritative trick result does not trigger identity-aware audio feedback"
	)
	if EventBus.freestyle_trick_scored.is_connected(_capture_event):
		EventBus.freestyle_trick_scored.disconnect(_capture_event)
	hud.queue_free()
	audio.queue_free()
	controller.queue_free()
	await get_tree().process_frame


func _clean_observation() -> Dictionary:
	return {
		&"airtime": 1.35,
		&"total_rotation": 1.1,
		&"pitch_rotation": 0.0,
		&"yaw_rotation": 0.0,
		&"roll_rotation": 0.0,
		&"steer_left_time": 0.0,
		&"steer_right_time": 0.0,
		&"scrub_time": 0.0,
		&"whip_time": 0.0,
		&"modifier_time": 0.0,
		&"safe_return_time": 0.0,
		&"modifier_held_at_landing": false,
		&"pose_times": {},
		&"landing_intensity": 0.24,
		&"upright_alignment": 0.92,
		&"physical_clean": true,
		&"takeoff_valid": true,
	}


func _capture_event(result: Dictionary) -> void:
	_last_event = result.duplicate(true)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
	push_error("FREESTYLE TRICK DEPTH PROBE: %s" % message)
