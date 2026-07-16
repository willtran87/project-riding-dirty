extends Node
## End-to-end contract for persisted race difficulty and presentation-only
## visual quality: UI reachability, authored AI offsets, competitive isolation,
## challenge/Academy locks, and viewport application.

const TEST_PATH := "user://tests/race_difficulty_quality_probe.json"
const LEGACY_SETTINGS_VERSION := 1
const MAIN_SCRIPT := preload("res://scenes/main.gd")

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	Profile.persistence_enabled = false
	_cleanup_test_file()
	_write_v1_settings_file()

	var legacy_store := SettingsStore.new(TEST_PATH)
	var legacy_load := legacy_store.load_from_disk()
	_check(bool(legacy_load.get(&"ok", false)), "Version-1 settings did not load")
	_check(bool(legacy_load.get(&"migrated", false)), "Version-1 settings were not migrated")
	_check(
		str(legacy_store.get_value(&"gameplay", &"race_difficulty", "")) == "STANDARD",
		"Existing riders did not default to STANDARD difficulty"
	)
	_check(
		str(legacy_store.get_value(&"graphics", &"visual_quality", "")) == "BALANCED",
		"Existing riders did not default to BALANCED visual quality"
	)

	var service := RaceServices.new()
	service.settings = legacy_store
	add_child(service)
	await get_tree().process_frame
	service.call(&"_apply_settings")
	var default_quality := service.get_visual_quality_snapshot()
	_check(RaceEventCatalog.get_player_difficulty_mode() == &"STANDARD", "STANDARD did not reach the race catalog")
	_check(StringName(default_quality.get(&"mode", &"")) == &"BALANCED", "BALANCED did not reach the viewport")

	var difficulty_inputs := _exercise_difficulty_inputs(service)
	var quality_inputs := _exercise_quality_inputs(service)

	var persisted := SettingsStore.new(TEST_PATH)
	var persisted_load := persisted.load_from_disk()
	_check(bool(persisted_load.get(&"ok", false)), "Changed settings did not reload")
	_check(
		str(persisted.get_value(&"gameplay", &"race_difficulty", "")) == "RELAXED",
		"Race difficulty did not persist"
	)
	_check(
		str(persisted.get_value(&"graphics", &"visual_quality", "")) == "PERFORMANCE",
		"Visual quality did not persist"
	)

	var sessions: Dictionary = {}
	var pace: Dictionary = {}
	for mode: StringName in RaceEventCatalog.PLAYER_DIFFICULTY_MODES:
		_set_setting(service, &"gameplay", &"race_difficulty", String(mode))
		var session := RaceEventCatalog.get_session_config(&"CIRCUIT")
		sessions[mode] = session
		pace[mode] = _ai_pace_snapshot(session)
		var expected_offset := int(RaceEventCatalog.PLAYER_DIFFICULTY_OFFSETS[mode])
		_check(int(session.rules.get(&"authored_difficulty", -1)) == 1, "%s lost authored CIRCUIT difficulty" % mode)
		_check(int(session.rules.get(&"player_difficulty_offset", 99)) == expected_offset, "%s stored the wrong offset" % mode)
		_check(StringName(session.rules.get(&"player_difficulty_mode", &"")) == mode, "%s mode did not reach the session" % mode)

	var relaxed := sessions[&"RELAXED"] as RaceSessionConfig
	var standard := sessions[&"STANDARD"] as RaceSessionConfig
	var expert := sessions[&"EXPERT"] as RaceSessionConfig
	_check(relaxed.difficulty == 0, "RELAXED did not offset CIRCUIT from 1 to 0")
	_check(standard.difficulty == 1, "STANDARD changed authored CIRCUIT difficulty")
	_check(expert.difficulty == 2, "EXPERT did not offset CIRCUIT from 1 to 2")
	_check(
		float((pace[&"RELAXED"] as Dictionary).get(&"average_base_speed", INF))
		< float((pace[&"STANDARD"] as Dictionary).get(&"average_base_speed", -INF)),
		"RELAXED AI pace is not below STANDARD"
	)
	_check(
		float((pace[&"STANDARD"] as Dictionary).get(&"average_base_speed", INF))
		< float((pace[&"EXPERT"] as Dictionary).get(&"average_base_speed", -INF)),
		"EXPERT AI pace is not above STANDARD"
	)

	_set_setting(service, &"gameplay", &"race_difficulty", "RELAXED")
	var relaxed_floor := RaceEventCatalog.get_session_config(&"MESA_PRACTICE")
	_check(relaxed_floor.difficulty == 0, "RELAXED underflowed authored difficulty zero")
	_set_setting(service, &"gameplay", &"race_difficulty", "EXPERT")
	var expert_ceiling := RaceEventCatalog.get_session_config(&"MESA_ENDURANCE")
	_check(expert_ceiling.difficulty == 4, "EXPERT overflowed authored difficulty four")
	var explicit_override := RaceEventCatalog.get_session_config(&"CIRCUIT", 4)
	_check(explicit_override.difficulty == 4, "Explicit session difficulty stopped being authoritative")
	_check(not explicit_override.rules.has(&"player_difficulty_mode"), "Player mode contaminated an explicit override")

	var ordinary_signatures: Dictionary = {}
	for mode: StringName in RaceEventCatalog.PLAYER_DIFFICULTY_MODES:
		var mode_session := sessions[mode] as RaceSessionConfig
		var mode_signature := _production_signature(mode_session)
		_check(CompetitiveRunSignature.validate(mode_signature), "%s produced an invalid run signature" % mode)
		ordinary_signatures[mode_signature] = true
	_check(ordinary_signatures.size() == 3, "Difficulty modes did not segregate ordinary run signatures")
	var authored_standard := RaceEventCatalog.get_session_config(&"CIRCUIT", 1)
	_check(
		_production_signature(standard) == _production_signature(authored_standard),
		"STANDARD no longer shares the authored pre-setting run signature"
	)

	var challenge_isolation := _verify_challenge_isolation()
	var academy_isolation := _verify_academy_isolation()
	var build_match_isolation := _verify_career_build_match_isolation()
	var briefing_isolation := _verify_briefing_isolation()
	var visual_signature_isolation := _verify_visual_signature_isolation(service)

	print("RACE DIFFICULTY + QUALITY PROBE: legacy=%s difficulty_ui=%s quality_ui=%s tiers=%d/%d/%d pace=%.2f/%.2f/%.2f signatures=%d challenges=%s academy=%s build_match=%s briefing=%s visual_isolation=%s persisted=%s passed=%s" % [
		str(bool(legacy_load.get(&"migrated", false))),
		str(difficulty_inputs),
		str(quality_inputs),
		relaxed.difficulty,
		standard.difficulty,
		expert.difficulty,
		float((pace[&"RELAXED"] as Dictionary).get(&"average_base_speed", 0.0)),
		float((pace[&"STANDARD"] as Dictionary).get(&"average_base_speed", 0.0)),
		float((pace[&"EXPERT"] as Dictionary).get(&"average_base_speed", 0.0)),
		ordinary_signatures.size(),
		str(challenge_isolation),
		str(academy_isolation),
		str(build_match_isolation),
		str(briefing_isolation),
		str(visual_signature_isolation),
		str(bool(persisted_load.get(&"ok", false))),
		str(_failures.is_empty()),
	])

	RaceEventCatalog.set_player_difficulty_mode(&"STANDARD")
	service.queue_free()
	await get_tree().process_frame
	_cleanup_test_file()
	if _failures.is_empty():
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("RACE DIFFICULTY + QUALITY PROBE: " + failure)
	get_tree().quit(1)


func _exercise_difficulty_inputs(service: RaceServices) -> Dictionary:
	service.set("_settings_page_index", RaceServices.SETTINGS_PAGE_IDS.find(&"RIDE"))
	service.set("_settings_index", 0)
	service.call(&"_refresh_settings_text")
	var items := service.get("_settings_items") as Array
	var index := _find_setting_index(items, &"race_difficulty")
	_check(index >= 0, "Race Difficulty is missing from the RIDE page")
	if index < 0:
		return {&"mouse": false, &"keyboard": false, &"gamepad": false}
	service.set("_settings_index", index)
	service.call(&"_refresh_settings_text")
	var row := service.find_child("SettingRow%02d" % index, true, false) as Button
	_check(row != null, "Race Difficulty has no mouse-selectable row")
	if row != null:
		row.pressed.emit()
	var mouse := str(service.settings.get_value(&"gameplay", &"race_difficulty", "")) == "EXPERT"
	_check(mouse, "Mouse did not cycle Race Difficulty to EXPERT")

	service.call(&"_handle_settings_input", _key_event(KEY_LEFT))
	var keyboard := str(service.settings.get_value(&"gameplay", &"race_difficulty", "")) == "STANDARD"
	_check(keyboard, "Keyboard did not cycle Race Difficulty to STANDARD")

	service.call(&"_handle_settings_input", _joy_event(JOY_BUTTON_DPAD_LEFT))
	var gamepad := str(service.settings.get_value(&"gameplay", &"race_difficulty", "")) == "RELAXED"
	_check(gamepad, "Gamepad did not cycle Race Difficulty to RELAXED")
	return {&"mouse": mouse, &"keyboard": keyboard, &"gamepad": gamepad}


func _exercise_quality_inputs(service: RaceServices) -> Dictionary:
	service.set("_settings_page_index", RaceServices.SETTINGS_PAGE_IDS.find(&"CAMERA"))
	service.set("_settings_index", 0)
	service.call(&"_refresh_settings_text")
	var items := service.get("_settings_items") as Array
	var index := _find_setting_index(items, &"visual_quality")
	_check(index >= 0, "Visual Quality is missing from the CAMERA page")
	if index < 0:
		return {&"mouse": false, &"keyboard": false, &"gamepad": false}
	service.set("_settings_index", index)
	service.call(&"_refresh_settings_text")
	var row := service.find_child("SettingRow%02d" % index, true, false) as Button
	_check(row != null, "Visual Quality has no mouse-selectable row")
	if row != null:
		row.pressed.emit()
	var quality_snapshot := service.get_visual_quality_snapshot()
	var mouse := (
		str(service.settings.get_value(&"graphics", &"visual_quality", "")) == "QUALITY"
		and StringName(quality_snapshot.get(&"mode", &"")) == &"QUALITY"
		and is_equal_approx(float(quality_snapshot.get(&"viewport_render_scale", 0.0)), 1.0)
		and int(quality_snapshot.get(&"viewport_msaa_3d", -1)) == int(quality_snapshot.get(&"effective_msaa_3d", -2))
	)
	_check(mouse, "Mouse QUALITY selection did not reach the viewport")

	service.call(&"_handle_settings_input", _key_event(KEY_LEFT))
	var balanced_snapshot := service.get_visual_quality_snapshot()
	var keyboard := (
		str(service.settings.get_value(&"graphics", &"visual_quality", "")) == "BALANCED"
		and is_equal_approx(float(balanced_snapshot.get(&"viewport_render_scale", 0.0)), 0.90)
		and int(balanced_snapshot.get(&"viewport_msaa_3d", -1)) == Viewport.MSAA_2X
	)
	_check(keyboard, "Keyboard BALANCED selection did not reach the viewport")

	service.call(&"_handle_settings_input", _joy_event(JOY_BUTTON_DPAD_LEFT))
	var performance_snapshot := service.get_visual_quality_snapshot()
	var gamepad := (
		str(service.settings.get_value(&"graphics", &"visual_quality", "")) == "PERFORMANCE"
		and is_equal_approx(float(performance_snapshot.get(&"viewport_render_scale", 0.0)), 0.75)
		and int(performance_snapshot.get(&"viewport_msaa_3d", -1)) == Viewport.MSAA_DISABLED
	)
	_check(gamepad, "Gamepad PERFORMANCE selection did not reach the viewport")
	var web_quality := RaceServices.resolve_visual_quality_preset("QUALITY", true)
	var browser_safe := (
		bool(web_quality.get(&"web_capped", false))
		and is_equal_approx(float(web_quality.get(&"render_scale", 0.0)), 0.90)
		and int(web_quality.get(&"requested_msaa_3d", -1)) == Viewport.MSAA_4X
		and int(web_quality.get(&"effective_msaa_3d", -1)) == Viewport.MSAA_2X
		and is_equal_approx(float(web_quality.get(&"shadow_distance", 0.0)), 220.0)
		and is_equal_approx(float(web_quality.get(&"particle_ratio", 0.0)), 0.84)
	)
	_check(browser_safe, "QUALITY is not safely capped for WebGL")
	return {&"mouse": mouse, &"keyboard": keyboard, &"gamepad": gamepad, &"browser_safe": browser_safe}


func _verify_challenge_isolation() -> bool:
	var schedule := ChallengeSchedule.new()
	var fixtures := {
		&"DAILY_CHALLENGE": schedule.daily(1_750_000_000, 2),
		&"WEEKLY_CHALLENGE": schedule.weekly(1_750_000_000, 2),
	}
	var passed := true
	for event_id: StringName in fixtures:
		var challenge := fixtures[event_id] as Dictionary
		RaceEventCatalog.set_player_difficulty_mode(&"STANDARD")
		var baseline := RaceEventCatalog.get_challenge_session_config(event_id, challenge)
		var baseline_canonical := CompetitiveRunSignature.canonical_string(baseline.to_dictionary())
		for mode: StringName in RaceEventCatalog.PLAYER_DIFFICULTY_MODES:
			RaceEventCatalog.set_player_difficulty_mode(mode)
			var session := RaceEventCatalog.get_challenge_session_config(event_id, challenge)
			var unchanged := CompetitiveRunSignature.canonical_string(session.to_dictionary()) == baseline_canonical
			var scheduled_signature := str(challenge.get("run_signature", ""))
			var production_signature := _production_signature(session)
			var isolated := (
				unchanged
				and session.difficulty == int(challenge.get("difficulty", -1))
				and int(session.rules.get(&"competitive_difficulty", -1)) == int(challenge.get("difficulty", -2))
				and not session.rules.has(&"player_difficulty_mode")
				and production_signature == scheduled_signature
				and CompetitiveRunSignature.validate(production_signature)
			)
			passed = passed and isolated
			_check(isolated, "%s changed under %s player difficulty" % [event_id, mode])
	return passed


func _verify_academy_isolation() -> bool:
	RaceEventCatalog.set_player_difficulty_mode(&"STANDARD")
	var baseline := RaceEventCatalog.get_session_config(&"ACADEMY")
	var canonical := CompetitiveRunSignature.canonical_string(baseline.to_dictionary())
	var passed := baseline.difficulty == 0
	for mode: StringName in RaceEventCatalog.PLAYER_DIFFICULTY_MODES:
		RaceEventCatalog.set_player_difficulty_mode(mode)
		var session := RaceEventCatalog.get_session_config(&"ACADEMY")
		var isolated := (
			session.difficulty == 0
			and not session.rules.has(&"player_difficulty_mode")
			and CompetitiveRunSignature.canonical_string(session.to_dictionary()) == canonical
		)
		passed = passed and isolated
		_check(isolated, "Academy grading changed under %s player difficulty" % mode)
	return passed


func _verify_career_build_match_isolation() -> bool:
	RaceEventCatalog.set_player_difficulty_mode(&"STANDARD")
	var legacy_projection: Dictionary = MAIN_SCRIPT.resolve_opponent_build_match_projection({})
	var legacy_attack_projection: Dictionary = MAIN_SCRIPT.resolve_opponent_build_match_projection({}, &"ATTACK")
	var upgraded_snapshot := {
		&"stats": {
			&"power": 80.0,
			&"acceleration": 85.0,
			&"top_speed": 65.0,
		}
	}
	var upgraded_projection: Dictionary = MAIN_SCRIPT.resolve_opponent_build_match_projection(upgraded_snapshot)
	var balanced_projection: Dictionary = MAIN_SCRIPT.resolve_opponent_build_match_projection(upgraded_snapshot, &"BALANCED")
	var trail_projection: Dictionary = MAIN_SCRIPT.resolve_opponent_build_match_projection(upgraded_snapshot, &"TRAIL")
	var attack_projection: Dictionary = MAIN_SCRIPT.resolve_opponent_build_match_projection(upgraded_snapshot, &"ATTACK")
	var unknown_projection: Dictionary = MAIN_SCRIPT.resolve_opponent_build_match_projection(upgraded_snapshot, &"UNKNOWN")
	var trail_performance := float(trail_projection.get(&"performance_scale", 1.0))
	var balanced_performance := float(balanced_projection.get(&"performance_scale", 1.0))
	var attack_performance := float(attack_projection.get(&"performance_scale", 1.0))
	var trail_match := float(trail_projection.get(&"match_scale", 1.0))
	var balanced_match := float(balanced_projection.get(&"match_scale", 1.0))
	var attack_match := float(attack_projection.get(&"match_scale", 1.0))
	var career := RaceEventCatalog.get_session_config(&"CIRCUIT")
	var challenge_data := ChallengeSchedule.new().daily(1_750_000_000, 2)
	var challenge := RaceEventCatalog.get_challenge_session_config(&"DAILY_CHALLENGE", challenge_data)
	var academy := RaceEventCatalog.get_session_config(&"ACADEMY")
	var challenge_before := CompetitiveRunSignature.canonical_string(challenge.to_dictionary())
	var academy_before := CompetitiveRunSignature.canonical_string(academy.to_dictionary())
	var career_applied: bool = MAIN_SCRIPT.apply_career_opponent_build_match(career, upgraded_snapshot, &"ATTACK")
	var challenge_applied: bool = MAIN_SCRIPT.apply_career_opponent_build_match(challenge, upgraded_snapshot, &"ATTACK")
	var academy_applied: bool = MAIN_SCRIPT.apply_career_opponent_build_match(academy, upgraded_snapshot, &"TRAIL")
	var passed := (
		is_equal_approx(float(legacy_projection.get(&"performance_scale", 0.0)), 1.0)
		and is_equal_approx(float(legacy_projection.get(&"match_scale", 0.0)), 1.0)
		and is_equal_approx(float(legacy_attack_projection.get(&"match_scale", 0.0)), 1.0)
		and is_equal_approx(
			float(upgraded_projection.get(&"match_scale", 0.0)),
			balanced_match
		)
		and is_equal_approx(
			float(unknown_projection.get(&"match_scale", 0.0)),
			balanced_match
		)
		and is_equal_approx(float(trail_projection.get(&"setup_factor", 0.0)), 0.97)
		and is_equal_approx(float(balanced_projection.get(&"setup_factor", 0.0)), 1.0)
		and is_equal_approx(float(attack_projection.get(&"setup_factor", 0.0)), 1.04)
		and trail_performance < balanced_performance
		and balanced_performance < attack_performance
		and trail_match < balanced_match
		and balanced_match < attack_match
		and attack_performance > attack_match
		and is_equal_approx(float(attack_projection.get(&"match_weight", 0.0)), 0.65)
		and trail_match >= 0.94
		and attack_match <= 1.12
		and career_applied
		and is_equal_approx(float(career.rules.get(&"opponent_build_performance_scale", 0.0)), attack_performance)
		and is_equal_approx(float(career.rules.get(&"opponent_build_match_scale", 0.0)), attack_match)
		and is_equal_approx(float(career.rules.get(&"opponent_build_match_weight", 0.0)), 0.65)
		and StringName(career.rules.get(&"opponent_build_setup_id", &"")) == &"ATTACK"
		and is_equal_approx(float(career.rules.get(&"opponent_build_setup_factor", 0.0)), 1.04)
		and not challenge_applied
		and not academy_applied
		and not challenge.rules.has(&"opponent_build_match_scale")
		and not academy.rules.has(&"opponent_build_match_scale")
		and not challenge.rules.has(&"opponent_build_setup_factor")
		and not academy.rules.has(&"opponent_build_setup_factor")
		and CompetitiveRunSignature.canonical_string(challenge.to_dictionary()) == challenge_before
		and CompetitiveRunSignature.canonical_string(academy.to_dictionary()) == academy_before
	)
	_check(passed, "Career build matching was not partial, bounded, diagnostic, or isolated")
	return passed


func _verify_briefing_isolation() -> bool:
	var transition := DistrictTransition.new()
	RaceEventCatalog.set_player_difficulty_mode(&"EXPERT")
	var ordinary := transition.get_briefing_snapshot(&"CIRCUIT")
	var challenge := transition.get_briefing_snapshot(&"DAILY_CHALLENGE")
	var academy := transition.get_briefing_snapshot(&"ACADEMY")
	var passed := (
		StringName(ordinary.get(&"difficulty_mode", &"")) == &"EXPERT"
		and int(ordinary.get(&"difficulty_offset", 0)) == 1
		and not bool(ordinary.get(&"difficulty_locked", true))
		and str(ordinary.get(&"route", "")).contains("RACE DIFFICULTY EXPERT")
		and bool(challenge.get(&"difficulty_locked", false))
		and str(challenge.get(&"route", "")).contains("CHALLENGE DIFFICULTY LOCKED")
		and not str(challenge.get(&"route", "")).contains("RACE DIFFICULTY EXPERT")
		and bool(academy.get(&"difficulty_locked", false))
		and str(academy.get(&"route", "")).contains("ACADEMY GRADING LOCKED")
	)
	_check(passed, "Pre-race briefing did not clearly distinguish active and locked difficulty")
	transition.free()
	return passed


func _verify_visual_signature_isolation(service: RaceServices) -> bool:
	_set_setting(service, &"gameplay", &"race_difficulty", "STANDARD")
	_set_setting(service, &"graphics", &"visual_quality", "PERFORMANCE")
	var performance_session := RaceEventCatalog.get_session_config(&"CIRCUIT")
	var performance_signature := _production_signature(performance_session)
	_set_setting(service, &"graphics", &"visual_quality", "QUALITY")
	var quality_session := RaceEventCatalog.get_session_config(&"CIRCUIT")
	var quality_signature := _production_signature(quality_session)
	var passed := (
		performance_signature == quality_signature
		and CompetitiveRunSignature.canonical_string(performance_session.to_dictionary())
		== CompetitiveRunSignature.canonical_string(quality_session.to_dictionary())
	)
	_check(passed, "Visual quality changed session data or a competitive signature")
	return passed


func _production_signature(session: RaceSessionConfig) -> String:
	var rules := session.rules
	return CompetitiveRunSignature.build({
		"event_id": rules.get(&"competitive_event_id", session.event_id),
		"track_id": session.track_id,
		"route_version": session.route_version,
		"format": session.format,
		"laps": session.laps,
		"bike_class": rules.get(&"competitive_bike_class", session.bike_class),
		"difficulty": rules.get(&"competitive_difficulty", session.difficulty),
		"assist_mode": rules.get(&"competitive_assist_mode", &"SPORT"),
		"setup_id": rules.get(&"competitive_setup_id", &"BALANCED"),
		"weather": session.weather,
		"surface": session.surface_modifier,
		"challenge_id": rules.get(&"challenge_id", ""),
		"modifiers": rules.get(&"modifiers", []),
	})


func _ai_pace_snapshot(session: RaceSessionConfig) -> Dictionary:
	var pack := RacePack.new()
	add_child(pack)
	pack.configure(session.track_id, PackedVector3Array(), null, session)
	var riders_value: Variant = pack.get("_riders")
	var count := 0
	var total := 0.0
	var minimum := INF
	var maximum := -INF
	if riders_value is Array:
		for raw_state: Variant in riders_value:
			if not raw_state is Dictionary or not bool((raw_state as Dictionary).get(&"active", false)):
				continue
			var speed := float((raw_state as Dictionary).get(&"base_speed", 0.0))
			count += 1
			total += speed
			minimum = minf(minimum, speed)
			maximum = maxf(maximum, speed)
	pack.free()
	return {
		&"count": count,
		&"average_base_speed": total / float(count) if count > 0 else 0.0,
		&"minimum_base_speed": minimum if count > 0 else 0.0,
		&"maximum_base_speed": maximum if count > 0 else 0.0,
	}


func _set_setting(service: RaceServices, section: StringName, key: StringName, value: Variant) -> void:
	_check(service.settings.set_value(section, key, value), "Could not set %s.%s to %s" % [section, key, value])
	service.call(&"_apply_settings")


func _find_setting_index(items: Array, key: StringName) -> int:
	for index: int in items.size():
		if items[index] is Dictionary and StringName((items[index] as Dictionary).get(&"key", &"")) == key:
			return index
	return -1


func _key_event(key: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.pressed = true
	event.physical_keycode = key
	return event


func _joy_event(button: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.pressed = true
	event.button_index = button
	return event


func _write_v1_settings_file() -> void:
	var absolute := ProjectSettings.globalize_path(TEST_PATH)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var legacy_values := SettingsStore.DEFAULTS.duplicate(true)
	legacy_values.erase("gameplay")
	legacy_values.erase("graphics")
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	if file == null:
		_failures.append("Could not create version-1 settings fixture")
		return
	file.store_string(JSON.stringify({"version": LEGACY_SETTINGS_VERSION, "values": legacy_values}, "\t"))
	file.close()


func _cleanup_test_file() -> void:
	for suffix: String in ["", SettingsStore.TEMP_SUFFIX, SettingsStore.BACKUP_SUFFIX, SettingsStore.BACKUP_TEMP_SUFFIX]:
		var path := TEST_PATH + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
