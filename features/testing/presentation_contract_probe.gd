extends Node
## Fast headless contract for the gameplay camera envelope and contextual HUD hints.

const CAMERA_SCENE := preload("res://features/camera/chase_camera.tscn")
const HUD_SCENE := preload("res://features/hud/race_hud.tscn")

var _passed: bool = true


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var camera := CAMERA_SCENE.instantiate() as ChaseCamera
	add_child(camera)
	var hud := HUD_SCENE.instantiate() as RaceHud
	add_child(hud)
	await get_tree().process_frame

	var camera_node := camera.get_node("Camera3D") as Camera3D
	_check(is_equal_approx(camera.base_fov, 78.0), "camera base FOV left the readable racing envelope")
	_check(is_equal_approx(camera.maximum_fov, 92.0), "camera maximum FOV left the readable racing envelope")
	_check(camera.dynamic_fov_headroom >= 2.0, "camera no longer reserves transient FOV headroom")
	_check(camera_node != null and is_equal_approx(camera_node.fov, camera.base_fov), "scene camera does not start at the scripted base FOV")
	camera.set_composition_offset_right(2.35)
	_check(is_equal_approx(camera.get_composition_offset_right(), 2.35), "Garage hero composition is unavailable")
	camera.set_composition_offset_right(8.0)
	_check(is_equal_approx(camera.get_composition_offset_right(), 4.0), "camera composition offset is not safety-clamped")
	camera.set_composition_offset_right(0.0)

	var initial_hint := hud.get_control_hint_state()
	var panel_size: Vector2 = initial_hint.get(&"panel_size", Vector2.ZERO)
	_check(bool(initial_hint.get(&"visible", false)), "control hints are unavailable during staging")
	_check(float(initial_hint.get(&"opacity", 0.0)) >= 0.99, "staged control hints do not begin legibly")
	_check(panel_size.x <= 620.1 and panel_size.y <= 70.1, "control hints regained the oversized gameplay footprint")

	EventBus.race_started.emit()
	await get_tree().process_frame
	var race_hint := hud.get_control_hint_state()
	_check(bool(race_hint.get(&"visible", false)), "control hints disappear immediately at green")
	_check(float(race_hint.get(&"hold_seconds", 0.0)) <= 4.5, "race hints remain staged for too long")

	EventBus.game_paused.emit(true)
	await get_tree().process_frame
	var paused_hint := hud.get_control_hint_state()
	_check(bool(paused_hint.get(&"pinned", false)), "pause does not restore the contextual controls")
	EventBus.game_paused.emit(false)
	await get_tree().process_frame
	var resumed_hint := hud.get_control_hint_state()
	_check(not bool(resumed_hint.get(&"pinned", true)), "control hints stay pinned after resuming")

	hud.dismiss_control_hints(true)
	var hidden_hint := hud.get_control_hint_state()
	_check(not bool(hidden_hint.get(&"visible", true)), "control hints cannot fully clear the racing view")
	hud.show_control_hints(2.0)
	var recalled_hint := hud.get_control_hint_state()
	_check(bool(recalled_hint.get(&"visible", false)), "contextual control hints cannot be recalled")
	_check(is_equal_approx(float(recalled_hint.get(&"hold_seconds", 0.0)), 2.0), "contextual hint duration is not deterministic")

	hud.update_line("", 1, 1.0, 0, 0.0)
	var line_score_label := hud.get("_line_score_label") as Label
	_check(line_score_label != null and line_score_label.text.is_empty(), "idle races expose a LINE 000000 placeholder")
	hud.update_line("CLEAN LANDING", 2, 1.25, 450, 2.0)
	_check(line_score_label != null and line_score_label.text.contains("LINE 000450"), "active line feedback is unavailable")

	var denial_payload := {&"technique": &"SURGE", &"required": 35.0, &"available": 0.0}
	hud.update_flow(0.0, false)
	hud.show_racecraft_event(&"FLOW_DENIED", denial_payload)
	var denial_feedback := hud.get_flow_denied_feedback_snapshot()
	_check(
		str(denial_feedback.get(&"text", "")) == "NEED 35 FLOW FOR SURGE  //  0 AVAILABLE",
		"Flow denial does not explain the required and available resource"
	)
	_check(
		bool(denial_feedback.get(&"active", false))
		and bool(denial_feedback.get(&"warning_polarity", false))
		and bool(denial_feedback.get(&"flow_meter_warning", false))
		and str(denial_feedback.get(&"racecraft_text", "")).contains("NEED 35 FLOW"),
		"Flow denial lacks warning polarity or meter emphasis"
	)
	var camera_before_denial := float(camera.get_motion_accessibility_snapshot().get(&"racecraft_kick", -1.0))
	camera.apply_racecraft_feedback(&"FLOW_DENIED", denial_payload)
	var camera_after_denial := float(camera.get_motion_accessibility_snapshot().get(&"racecraft_kick", -1.0))
	camera.apply_racecraft_feedback(&"FLOW_RAIL", {&"intensity": 0.8})
	var camera_after_success := float(camera.get_motion_accessibility_snapshot().get(&"racecraft_kick", 0.0))
	_check(
		is_equal_approx(camera_after_denial, camera_before_denial) and camera_after_success > camera_after_denial,
		"camera treats a denied Flow press like a successful physical technique"
	)

	Profile.reward_granted.emit(500, 50)
	Profile.achievement_unlocked.emit(&"FIRST_WIN")
	await get_tree().process_frame
	var reward_state := hud.get_reward_notification_state()
	_check(str(reward_state.get(&"text", "")).contains("+$500"), "cash/reputation feedback did not present first")
	_check(int(reward_state.get(&"queued", 0)) == 1, "achievement feedback overwrote a simultaneous reward")
	hud.set("_reward_time", 0.0)
	hud.call("_present_next_reward")
	var achievement_state := hud.get_reward_notification_state()
	_check(str(achievement_state.get(&"text", "")).contains("TOP STEP"), "achievement milestone has no named HUD feedback")
	_check(str(achievement_state.get(&"text", "")).contains("Win a classified race"), "achievement feedback has no goal context")

	print(
		"PRESENTATION CONTRACT: camera=%.1f-%.1f cruise_headroom=%.1f hint_size=%s race_hold=%.2fs pause_context=%s flow_denied=%s passed=%s"
		% [
			camera.base_fov,
			camera.maximum_fov,
			camera.dynamic_fov_headroom,
			str(panel_size),
			float(race_hint.get(&"hold_seconds", 0.0)),
			str(bool(paused_hint.get(&"pinned", false)) and not bool(resumed_hint.get(&"pinned", true))),
			str(bool(denial_feedback.get(&"active", false)) and camera_after_success > camera_after_denial),
			str(_passed),
		]
	)
	hud.queue_free()
	camera.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if _passed else 1)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_passed = false
	push_error("PRESENTATION CONTRACT: %s" % message)
