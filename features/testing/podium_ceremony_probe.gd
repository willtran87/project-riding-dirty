extends Node
## Deterministic contract for official podium, rider identity, recap, and motion.

const HUD_SCENE := preload("res://features/hud/race_hud.tscn")

var _failures: Array[String] = []
var _prior_input_mode: StringName = &""


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	Profile.persistence_enabled = false
	Profile.reset_profile_for_testing()
	_check(Profile.set_rider_cosmetics({
		&"body_type": &"POWERFUL",
		&"skin_tone": &"DEEP",
		&"voice": &"GROUNDED",
		&"jersey": "NIGHT_CYAN",
		&"bike_livery": "NIGHT_RACE",
		&"accent_color": "56D6FF",
		&"rider_number": 314,
	}), "Probe rider identity could not be applied")
	_prior_input_mode = InputRouter.input_mode
	InputRouter.call(&"_set_input_mode", InputRouter.INPUT_MODE_KEYBOARD_MOUSE)
	var hud := HUD_SCENE.instantiate() as RaceHud
	add_child(hud)
	await get_tree().process_frame

	var result := _race_result()
	hud.show_results(result)
	await get_tree().process_frame
	await get_tree().process_frame
	var presentation := hud.get_competition_presentation_snapshot()
	var podium := presentation.get(&"podium", {}) as Dictionary
	var top_three := podium.get(&"top_three", []) as Array
	_check(bool(presentation.get(&"results_visible", false)), "Official Results card is not visible")
	_check(bool(podium.get(&"visible", false)), "Official podium did not appear for a classified race")
	_check(str(podium.get(&"event_name", "")).contains("QUARRY"), "Podium omitted the event identity")
	_check(int(podium.get(&"player_position", 0)) == 2, "Podium lost the player's official position")
	_check(bool(podium.get(&"player_on_podium", false)), "P2 player was not recognized as a podium finisher")
	_check(top_three.size() == 3, "Podium did not project the authoritative top three")
	_check(_top_three_is_ordered(top_three), "Podium top three are not ordered P1/P2/P3")
	_check(_player_entry_has_number(top_three, 314), "Custom rider number is absent from the podium")
	_check(
		StringName(podium.get(&"body_type", &"")) == &"POWERFUL"
		and str(podium.get(&"jersey", "")) == "NIGHT_CYAN"
		and str(podium.get(&"livery", "")) == "NIGHT_RACE",
		"Podium did not preserve the rider's visible identity"
	)
	var recap := str(presentation.get(&"event_recap", ""))
	_check(
		recap.contains("DUSTLINE WORKS")
		and recap.contains("#314 NIGHT CYAN")
		and recap.contains("RACE RIVAL")
		and recap.contains("PODIUM"),
		"Event recap omitted team, rider, rival, or signature-moment context"
	)
	var navigation := hud.get_results_navigation_snapshot()
	_check(bool(navigation.get(&"content_fits", false)), "Podium pushed Results content outside the desktop card")

	var ceremony := hud.get("_results_podium") as Control
	ceremony.call(&"present", _classification(), result, Profile.get_rider_cosmetics())
	var reveal_before := float(
		(ceremony.call(&"get_presentation_snapshot") as Dictionary).get(&"reveal", 1.0)
	)
	ceremony.call(&"_process", 0.20)
	var reveal_after := float(
		(ceremony.call(&"get_presentation_snapshot") as Dictionary).get(&"reveal", 0.0)
	)
	_check(
		reveal_before < reveal_after and reveal_after < 1.0,
		"Podium reveal is not progressive and frame-rate independent"
	)
	if "--capture" in OS.get_cmdline_user_args():
		ceremony.call(&"_process", 1.0)
		await RenderingServer.frame_post_draw
		var capture_error := get_viewport().get_texture().get_image().save_png(
			"res://output/podium-ceremony-probe.png"
		)
		_check(capture_error == OK, "Podium visual proof could not be captured")

	hud.apply_accessibility({
		&"text_scale": 1.0,
		&"units": &"IMPERIAL",
		&"high_contrast": false,
		&"color_safe_mode": &"OFF",
		&"reduced_flashes": true,
	})
	var reduced := (
		hud.get_competition_presentation_snapshot().get(&"podium", {}) as Dictionary
	)
	_check(
		bool(reduced.get(&"reduced_motion", false))
		and is_equal_approx(float(reduced.get(&"reveal", 0.0)), 1.0),
		"Reduced-motion mode did not remove the ceremony animation"
	)

	InputRouter.call(&"_set_input_mode", InputRouter.INPUT_MODE_TOUCH)
	await get_tree().process_frame
	await get_tree().process_frame
	var compact := (
		hud.get_competition_presentation_snapshot().get(&"podium", {}) as Dictionary
	)
	_check(bool(compact.get(&"compact", false)), "Touch Results did not use the compact podium")
	_check(
		(ceremony as Control).custom_minimum_size.y <= 94.5,
		"Compact podium retained the full desktop height"
	)

	hud.show_results({
		&"event_id": &"ACADEMY",
		&"valid": true,
		&"classification": _classification(),
		&"player_position": 2,
		&"academy_evaluation": {
			&"lesson_id": &"CONTROL_BASICS",
			&"display_name": "CONTROL BASICS",
			&"passed": true,
			&"stars": 2,
			&"best_stars": 2,
			&"objective_results": [],
		},
	})
	await get_tree().process_frame
	var academy := hud.get_competition_presentation_snapshot()
	var academy_podium := academy.get(&"podium", {}) as Dictionary
	_check(
		not bool(academy_podium.get(&"visible", true))
		and str(academy.get(&"event_recap", "")).is_empty(),
		"Race ceremony leaked into the authored Academy grading card"
	)

	print("PODIUM CEREMONY PROBE: top3=%d player=P%d number=%03d recap=%s motion=%s compact=%s academy_scoped=%s passed=%s" % [
		top_three.size(),
		int(podium.get(&"player_position", 0)),
		int(podium.get(&"rider_number", 0)),
		str(not recap.is_empty()),
		str(bool(reduced.get(&"reduced_motion", false))),
		str(bool(compact.get(&"compact", false))),
		str(not bool(academy_podium.get(&"visible", true))),
		str(_failures.is_empty()),
	])
	hud.queue_free()
	await get_tree().process_frame
	InputRouter.call(&"_set_input_mode", _prior_input_mode)
	if _failures.is_empty():
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("PODIUM CEREMONY PROBE: " + failure)
	get_tree().quit(1)


func _race_result() -> Dictionary:
	return {
		&"run_id": "podium-ceremony-probe",
		&"signature": "podium-ceremony-probe-signature",
		&"event_id": &"CIRCUIT",
		&"event_name": "QUARRY TRAIL",
		&"valid": true,
		&"medal": &"SILVER",
		&"classification": _classification(),
		&"player_position": 2,
		&"player_time_usec": 181_240_000,
		&"player_penalty_usec": 0,
		&"fastest_lap_usec": 58_200_000,
		&"overtakes": 5,
		&"contacts": 0,
		&"crashes": 0,
		&"reset_count": 0,
		&"off_course_count": 0,
		&"holeshot_rider_id": &"ROOK",
		&"rewards": {&"cash": 850, &"reputation": 28},
		&"next_event_name": "PINE RIDGE ENDURO",
	}


func _classification() -> Array[Dictionary]:
	var riders: Array[Dictionary] = []
	var names := ["ROOK", "YOU", "VALE", "MARA", "KITE", "BRIGGS", "SOL", "EMBER"]
	for index: int in names.size():
		var is_player := index == 1
		riders.append({
			&"rider_id": &"PLAYER" if is_player else StringName(names[index]),
			&"display_name": names[index],
			&"number": 17 if is_player else 11 + index * 8,
			&"position": index + 1,
			&"status": &"FINISHED",
			&"finish_usec": 180_000_000 + index * 1_240_000,
			&"effective_time_usec": 180_000_000 + index * 1_240_000,
			&"penalty_usec": 0,
			&"is_player": is_player,
		})
	return riders


func _top_three_is_ordered(entries: Array) -> bool:
	if entries.size() != 3:
		return false
	for index: int in 3:
		var entry := entries[index] as Dictionary
		if int(entry.get(&"position", 0)) != index + 1:
			return false
	return true


func _player_entry_has_number(entries: Array, expected_number: int) -> bool:
	for raw_entry: Variant in entries:
		if not raw_entry is Dictionary:
			continue
		var entry := raw_entry as Dictionary
		if bool(entry.get(&"is_player", false)):
			return int(entry.get(&"number", 0)) == expected_number
	return false


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
