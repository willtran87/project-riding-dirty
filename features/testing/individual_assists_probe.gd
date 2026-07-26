extends Node
## Deterministic persistence, UI, physics-channel, HUD, and signature contract
## for five independently adjustable riding assists.

const PLAYER_PROFILE_SCRIPT := preload("res://common/player_profile.gd")
const FAILING_PROFILE_SCRIPT := preload("res://features/testing/failing_activity_settlement_profile.gd")
const ASSIST_CONFIG := preload("res://common/riding_assist_config.gd")
const BIKE_SCRIPT := preload("res://entities/bike/bike_controller.gd")
const HUD_SCENE := preload("res://features/hud/race_hud.tscn")

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var profile_snapshot := Profile._profile_to_dictionary()
	var prior_persistence := Profile.persistence_enabled
	Profile.persistence_enabled = false
	Profile.reset_profile_for_testing()

	_check(ASSIST_CONFIG.CHANNELS.size() == 5, "assist authority does not expose exactly five channels")
	for mode: StringName in ASSIST_CONFIG.PRESET_ORDER:
		var preset := ASSIST_CONFIG.preset(mode)
		_check(preset.size() == 5, "%s preset is incomplete" % mode)
		_check(ASSIST_CONFIG.matching_preset(preset) == mode, "%s preset does not self-identify" % mode)
		_check(ASSIST_CONFIG.signature(mode, preset) == String(mode), "%s preset signature is unstable" % mode)
		for channel: StringName in ASSIST_CONFIG.CHANNELS:
			_check(
				float(preset.get(channel, -1.0)) >= 0.0 and float(preset.get(channel, 2.0)) <= 1.0,
				"%s %s is outside bounded strength" % [mode, channel]
			)

	var profile: Variant = PLAYER_PROFILE_SCRIPT.new()
	profile.persistence_enabled = false
	profile.reset_profile_for_testing()
	_check(profile.PROFILE_SCHEMA_VERSION == 7, "Profile schema was not advanced for individual assists")
	_check(profile.set_assist_value(&"steering", 0.70), "Steering assist could not be customized")
	_check(profile.set_assist_value(&"landing", 0.20), "Landing assist could not be customized")
	_check(profile.assist_mode == &"CUSTOM", "Individual adjustment did not enter Custom mode")
	var custom_signature: String = profile.get_assist_signature()
	_check(
		custom_signature == "CUSTOM_S070_B045_L020_T045_R045",
		"Custom signature does not encode all exact assist strengths: %s" % custom_signature
	)
	_check(not profile.set_assist_value(&"unknown", 0.5), "Unknown assist channel was accepted")
	_check(not profile.set_assist_value(&"braking", 1.1), "Out-of-range assist strength was accepted")

	var serialized: Dictionary = profile._profile_to_dictionary()
	var restored: Variant = PLAYER_PROFILE_SCRIPT.new()
	restored.persistence_enabled = false
	restored._apply_profile_dictionary(serialized)
	_check(restored.assist_mode == &"CUSTOM", "Custom mode did not survive profile round-trip")
	_check(restored.get_assist_signature() == custom_signature, "Custom values changed across profile round-trip")

	var legacy: Variant = PLAYER_PROFILE_SCRIPT.new()
	legacy.persistence_enabled = false
	legacy._apply_profile_dictionary({
		"profile_schema_version": 6,
		"assist_mode": "ASSISTED",
	})
	_check(legacy.assist_mode == &"ASSISTED", "Legacy broad assist mode did not migrate")
	_check(
		ASSIST_CONFIG.matching_preset(legacy.get_assist_configuration()) == &"ASSISTED",
		"Legacy broad mode did not expand into five matching channels"
	)

	var failing: Variant = FAILING_PROFILE_SCRIPT.new()
	failing.reset_profile_for_testing()
	var failed_before: String = failing.get_assist_signature()
	failing.fail_next_save = true
	_check(not failing.set_assist_value(&"traction", 0.90), "Injected assist save failure was reported as success")
	_check(failing.get_assist_signature() == failed_before, "Failed assist save did not roll back memory")

	var bike: Variant = BIKE_SCRIPT.new()
	var baseline := ASSIST_CONFIG.preset(&"SPORT")
	bike.apply_assist_configuration(baseline, &"SPORT")
	var sport_physics: Dictionary = bike.get_assist_snapshot()
	var isolated := baseline.duplicate(true)
	isolated[&"traction"] = 1.0
	bike.apply_assist_configuration(isolated, &"CUSTOM")
	var traction_physics: Dictionary = bike.get_assist_snapshot()
	_check(
		float(traction_physics.get(&"traction_cut_max", 0.0)) > float(sport_physics.get(&"traction_cut_max", 1.0)),
		"Traction support does not independently change slip-based drive trimming"
	)
	_check(
		is_equal_approx(
			float(traction_physics.get(&"brake_release_max", -1.0)),
			float(sport_physics.get(&"brake_release_max", -2.0))
		)
		and is_equal_approx(
			float(traction_physics.get(&"landing_alignment_scale", -1.0)),
			float(sport_physics.get(&"landing_alignment_scale", -2.0))
		),
		"Changing Traction leaked into braking or landing physics"
	)
	isolated = baseline.duplicate(true)
	isolated[&"braking"] = 1.0
	bike.apply_assist_configuration(isolated, &"CUSTOM")
	var braking_physics: Dictionary = bike.get_assist_snapshot()
	_check(
		float(braking_physics.get(&"brake_release_max", 0.0)) > float(sport_physics.get(&"brake_release_max", 1.0)),
		"Braking support does not independently change anti-lock release"
	)
	isolated = baseline.duplicate(true)
	isolated[&"landing"] = 1.0
	bike.apply_assist_configuration(isolated, &"CUSTOM")
	var landing_physics: Dictionary = bike.get_assist_snapshot()
	_check(
		float(landing_physics.get(&"landing_alignment_scale", 0.0)) > float(sport_physics.get(&"landing_alignment_scale", 1.0)),
		"Landing support does not independently change receiver alignment"
	)
	isolated = baseline.duplicate(true)
	isolated[&"balance"] = 1.0
	bike.apply_assist_configuration(isolated, &"CUSTOM")
	var balance_physics: Dictionary = bike.get_assist_snapshot()
	_check(
		float(balance_physics.get(&"balance_scale", 0.0)) > float(sport_physics.get(&"balance_scale", 1.0)),
		"Rider Balance does not independently change upright support"
	)
	isolated = baseline.duplicate(true)
	isolated[&"steering"] = 1.0
	bike.apply_assist_configuration(isolated, &"CUSTOM")
	var steering_physics: Dictionary = bike.get_assist_snapshot()
	_check(
		float(steering_physics.get(&"steering_yaw_scale", 0.0)) > float(sport_physics.get(&"steering_yaw_scale", 1.0)),
		"Steering support does not independently change yaw response"
	)
	bike.free()

	Profile.set_assist_preset(&"SPORT")
	var service := RaceServices.new()
	add_child(service)
	await get_tree().process_frame
	service.set("_settings_page_index", RaceServices.SETTINGS_PAGE_IDS.find(&"ASSISTS"))
	service.call(&"_refresh_settings_text")
	var assist_items: Array = service.get("_settings_items") as Array
	_check(assist_items.size() == 6, "Assist settings page must expose one preset plus five channels")
	var expected_keys: Array[StringName] = [
		&"preset", &"steering", &"braking", &"landing", &"traction", &"balance",
	]
	for index: int in expected_keys.size():
		_check(
			StringName((assist_items[index] as Dictionary).get(&"key", &"")) == expected_keys[index],
			"Assist settings order is unstable at row %d" % index
		)
	service.set("_settings_index", 1)
	service.call(&"_adjust_setting", 1)
	_check(Profile.assist_mode == &"CUSTOM", "Settings adjustment did not create Custom mode")
	_check(is_equal_approx(Profile.get_assist_value(&"steering"), 0.50), "Settings adjustment did not use 5% steps")

	var hud := HUD_SCENE.instantiate() as RaceHud
	add_child(hud)
	await get_tree().process_frame
	hud.configure_assists(Profile.assist_mode, Profile.get_assist_configuration(), false)
	var hud_snapshot := hud.get_assist_presentation_snapshot()
	_check(
		str(hud_snapshot.get(&"text", "")).contains("ASSIST CUSTOM")
		and str(hud_snapshot.get(&"text", "")).contains("5 / 5"),
		"HUD does not clearly communicate the active Custom assist set"
	)
	hud.configure_assists(&"PRO", ASSIST_CONFIG.preset(&"PRO"), true)
	hud_snapshot = hud.get_assist_presentation_snapshot()
	_check(
		str(hud_snapshot.get(&"text", "")).contains("EQUALIZED")
		and str(hud_snapshot.get(&"text", "")).contains("PRO"),
		"HUD does not identify challenge-equalized assists"
	)

	var sport_signature := CompetitiveRunSignature.build(_run_context("SPORT"))
	var custom_run_signature := CompetitiveRunSignature.build(_run_context(custom_signature))
	var second_custom_signature := CompetitiveRunSignature.build(
		_run_context("CUSTOM_S075_B045_L020_T045_R045")
	)
	_check(sport_signature != custom_run_signature, "Custom assist runs share the Sport leaderboard")
	_check(custom_run_signature != second_custom_signature, "Distinct Custom assist sets share a leaderboard")
	_check(
		CompetitiveRunSignature.build(_run_context("LIMITED"))
		== CompetitiveRunSignature.build(_run_context("LIMITED")),
		"Equalized challenge signature is not deterministic"
	)

	hud.queue_free()
	service.queue_free()
	await get_tree().process_frame
	var schema_version: int = profile.PROFILE_SCHEMA_VERSION
	profile.free()
	restored.free()
	legacy.free()
	failing.free()
	Profile._apply_profile_dictionary(profile_snapshot)
	Profile.persistence_enabled = prior_persistence

	print(
		(
			"INDIVIDUAL ASSISTS PROBE: channels=5 presets=3 custom=%s schema=%d "
			+ "physics=steer+brake+landing+traction+balance settings=6 hud=true signatures=true passed=%s"
		)
		% [custom_signature, schema_version, str(_failures.is_empty())]
	)
	if _failures.is_empty():
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("INDIVIDUAL ASSISTS PROBE: " + failure)
	get_tree().quit(1)


func _run_context(assist_signature: String) -> Dictionary:
	return {
		"event_id": "ASSIST_PROBE",
		"track_id": "QUARRY",
		"route_version": 4,
		"format": "SPRINT",
		"laps": 2,
		"bike_class": "LITE_125",
		"difficulty": 2,
		"assist_mode": assist_signature,
		"setup_id": "BALANCED",
	}


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
