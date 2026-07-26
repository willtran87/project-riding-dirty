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
	hud.show_camera_view("FIRST PERSON")
	var camera_feedback_label := hud.get("_message_label") as Label
	_check(
		camera_feedback_label != null and camera_feedback_label.text == "CAMERA  //  FIRST PERSON",
		"live camera changes have no clear visual confirmation"
	)

	var full_hud := hud.get_hud_customization_snapshot()
	var top_band_rect := full_hud.get(&"top_band_rect", Rect2()) as Rect2
	var standings_rect := full_hud.get(&"standings_rect", Rect2()) as Rect2
	_check(
		StringName(full_hud.get(&"detail", &"")) == &"FULL"
		and bool(full_hud.get(&"live_visible", false))
		and bool(full_hud.get(&"focused_visible", false))
		and bool(full_hud.get(&"full_visible", false)),
		"HUD does not begin in the complete presentation mode"
	)
	_check(
		top_band_rect.size.x >= 1279.0
		and top_band_rect.size.y <= 86.1
		and standings_rect.size.x <= 286.1
		and standings_rect.size.y <= 224.1,
		"HUD detail layers stretched or shifted anchored presentation controls"
	)
	hud.apply_accessibility({
		&"text_scale": 1.0,
		&"hud_detail": &"FOCUSED",
		&"hud_scale": 0.85,
	})
	var focused_hud := hud.get_hud_customization_snapshot()
	_check(
		bool(focused_hud.get(&"live_visible", false))
		and bool(focused_hud.get(&"focused_visible", false))
		and not bool(focused_hud.get(&"full_visible", true))
		and bool(focused_hud.get(&"timer_visible", false))
		and bool(focused_hud.get(&"speed_visible", false))
		and not bool(focused_hud.get(&"standings_visible", true)),
		"Focused HUD did not retain core telemetry while removing full-detail clutter"
	)
	_check(
		(focused_hud.get(&"live_scale", Vector2.ONE) as Vector2).is_equal_approx(Vector2(0.85, 0.85)),
		"Independent HUD sizing did not resize the live presentation"
	)
	hud.apply_accessibility({&"hud_detail": &"MINIMAL", &"hud_scale": 0.75})
	var minimal_hud := hud.get_hud_customization_snapshot()
	_check(
		bool(minimal_hud.get(&"live_visible", false))
		and not bool(minimal_hud.get(&"focused_visible", true))
		and not bool(minimal_hud.get(&"full_visible", true))
		and bool(minimal_hud.get(&"timer_visible", false))
		and bool(minimal_hud.get(&"speed_visible", false)),
		"Minimal HUD removed core race telemetry or retained secondary layers"
	)
	hud.apply_accessibility({&"hud_detail": &"OFF", &"hud_scale": 1.0})
	var hidden_hud := hud.get_hud_customization_snapshot()
	_check(
		not bool(hidden_hud.get(&"live_visible", true))
		and not bool(hidden_hud.get(&"timer_visible", true))
		and not bool(hidden_hud.get(&"speed_visible", true)),
		"Off mode did not disable the live HUD"
	)
	EventBus.game_paused.emit(true)
	await get_tree().process_frame
	var paused_label := hud.get("_paused_label") as Label
	_check(
		paused_label != null and paused_label.is_visible_in_tree(),
		"Disabling the live HUD also removed the pause safety overlay"
	)
	EventBus.game_paused.emit(false)
	var results_panel := hud.get("_results_panel") as PanelContainer
	results_panel.visible = true
	_check(
		bool(hud.get_hud_customization_snapshot().get(&"results_visible", false)),
		"Disabling the live HUD also removed official results"
	)
	results_panel.visible = false
	EventBus.activity_prepared.emit(&"FREESTYLE")
	await get_tree().process_frame
	hud.apply_accessibility({&"hud_detail": &"MINIMAL", &"hud_scale": 1.0})
	var freestyle_hud := hud.get_hud_customization_snapshot()
	_check(
		StringName(freestyle_hud.get(&"activity", &"")) == &"FREESTYLE"
		and bool(freestyle_hud.get(&"timer_visible", false))
		and not bool(freestyle_hud.get(&"course_map_visible", true)),
		"Minimal Freestyle HUD lost its timer or restored race-only navigation"
	)
	EventBus.activity_prepared.emit(&"DISCOVERY")
	await get_tree().process_frame
	var discovery_hud := hud.get_hud_customization_snapshot()
	_check(
		StringName(discovery_hud.get(&"activity", &"")) == &"DISCOVERY"
		and bool(discovery_hud.get(&"timer_visible", false))
		and bool(discovery_hud.get(&"compass_visible", false)),
		"Minimal Discovery HUD removed its essential timer or compass"
	)
	EventBus.activity_prepared.emit(&"ACADEMY")
	await get_tree().process_frame
	var academy_hud := hud.get_hud_customization_snapshot()
	_check(
		StringName(academy_hud.get(&"activity", &"")) == &"ACADEMY"
		and bool(academy_hud.get(&"academy_visible", false)),
		"Minimal Academy HUD removed its teaching objectives"
	)
	EventBus.activity_prepared.emit(&"CIRCUIT")
	await get_tree().process_frame
	hud.apply_accessibility({&"hud_detail": &"FULL", &"hud_scale": 1.0})

	var initial_hint := hud.get_control_hint_state()
	var panel_size: Vector2 = initial_hint.get(&"panel_size", Vector2.ZERO)
	_check(bool(initial_hint.get(&"visible", false)), "control hints are unavailable during staging")
	_check(float(initial_hint.get(&"opacity", 0.0)) >= 0.99, "staged control hints do not begin legibly")
	_check(panel_size.x <= 620.1 and panel_size.y <= 70.1, "control hints regained the oversized gameplay footprint")
	var transmission_label := hud.find_child("TransmissionLabel", true, false) as Label
	_check(
		transmission_label != null and transmission_label.text == "AUTO  //  G1",
		"HUD does not begin with a readable automatic first-gear state"
	)
	hud.update_transmission({
		&"mode": &"MANUAL",
		&"gear": 3,
		&"shift_active": true,
	})
	var manual_hint := hud.get_control_hint_state()
	_check(
		transmission_label != null and transmission_label.text == "MANUAL  //  G3",
		"HUD does not project the authoritative manual gear"
	)
	_check(
		str(manual_hint.get(&"text", "")).contains("Q SHIFT DOWN")
		and str(manual_hint.get(&"text", "")).contains("E SHIFT UP"),
		"manual mode does not teach its current shift bindings"
	)
	_check(
		(manual_hint.get(&"panel_size", Vector2.ZERO) as Vector2).y <= 90.1,
		"manual shift teaching expanded beyond the compact HUD envelope"
	)
	hud.update_transmission({&"mode": &"AUTOMATIC", &"gear": 1, &"shift_active": false})
	hud.configure_assists(
		&"CUSTOM",
		{&"steering": 0.70, &"braking": 0.35, &"landing": 0.20, &"traction": 0.45, &"balance": 0.60},
		false
	)
	var assist_presentation := hud.get_assist_presentation_snapshot()
	_check(
		str(assist_presentation.get(&"text", "")).contains("ASSIST CUSTOM")
		and str(assist_presentation.get(&"text", "")).contains("5 / 5"),
		"HUD does not communicate the active individual-assist configuration"
	)
	hud.configure_assists(
		&"PRO",
		{&"steering": 0.12, &"braking": 0.12, &"landing": 0.12, &"traction": 0.12, &"balance": 0.12},
		true
	)
	_check(
		str(hud.get_assist_presentation_snapshot().get(&"text", "")).contains("EQUALIZED"),
		"HUD does not disclose challenge-equalized assists"
	)

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
		"PRESENTATION CONTRACT: camera=%.1f-%.1f cruise_headroom=%.1f hint_size=%s race_hold=%.2fs pause_context=%s hud=%s/%s/%s/%s flow_denied=%s passed=%s"
		% [
			camera.base_fov,
			camera.maximum_fov,
			camera.dynamic_fov_headroom,
			str(panel_size),
			float(race_hint.get(&"hold_seconds", 0.0)),
			str(bool(paused_hint.get(&"pinned", false)) and not bool(resumed_hint.get(&"pinned", true))),
			String(full_hud.get(&"detail", &"")),
			String(focused_hud.get(&"detail", &"")),
			String(minimal_hud.get(&"detail", &"")),
			String(hidden_hud.get(&"detail", &"")),
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
