extends Node
## Headless contract coverage for district arrangements, adaptive stems and class timbre.

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var quarry_hash := GameplayAudio.get_arrangement_hash(&"CIRCUIT", &"QUARRY")
	var pine_hash := GameplayAudio.get_arrangement_hash(&"PINE_ENDURO", &"PINE")
	var mesa_hash := GameplayAudio.get_arrangement_hash(&"MESA_RHYTHM", &"MESA_MX")
	_expect(not quarry_hash.is_empty(), "Quarry arrangement hash is empty")
	_expect(quarry_hash != pine_hash and quarry_hash != mesa_hash and pine_hash != mesa_hash, "District arrangement hashes are not distinct")
	_expect(quarry_hash == GameplayAudio.get_arrangement_hash(&"CIRCUIT", &"QUARRY"), "Arrangement hashing is not deterministic")

	var weekend := GameplayAudio.get_arrangement_contract(&"MESA_HEAT", &"MESA_MX")
	var finale := GameplayAudio.get_arrangement_contract(&"MESA_MX", &"MESA_MX")
	var challenge := GameplayAudio.get_arrangement_contract(&"DAILY_CHALLENGE", &"MESA_MX")
	_expect(StringName(weekend.get(&"variation", &"")) == &"WEEKEND", "Weekend variation was not selected")
	_expect(StringName(finale.get(&"variation", &"")) == &"FINALE", "Finale variation was not selected")
	_expect(StringName(challenge.get(&"variation", &"")) == &"CHALLENGE", "Challenge variation was not selected")
	var variant_hashes := [weekend.get(&"contract_hash", &""), finale.get(&"contract_hash", &""), challenge.get(&"contract_hash", &"")]
	_expect(variant_hashes[0] != variant_hashes[1] and variant_hashes[0] != variant_hashes[2] and variant_hashes[1] != variant_hashes[2], "Weekend/finale/challenge hashes are not distinct")

	var buses := GameplayAudio.get_bus_routing_contract()
	_expect(StringName(buses.get(&"music", &"")) == &"Music", "Music is not routed to the Music bus")
	_expect(StringName(buses.get(&"feedback", &"")) == &"SFX" and StringName(buses.get(&"engine", &"")) == &"SFX", "Feedback or engine routing bypasses SFX")
	var transition_contract := GameplayAudio.get_transition_contract()
	_expect(float(transition_contract.get(&"arrangement_crossfade_seconds", 0.0)) >= 0.35, "Arrangement crossfade is too short for click-free switching")
	_expect(float(transition_contract.get(&"minimum_stem_transition_seconds", 0.0)) >= 0.30, "Stem transition contract is too abrupt")

	var audio := GameplayAudio.new()
	add_child(audio)
	audio.call(&"_on_activity_prepared", &"MESA_HEAT")
	var staging_snapshot := audio.get_audio_contract_snapshot()
	_expect(StringName(staging_snapshot.get(&"music_state", &"")) == &"STAGING", "Activity preparation did not enter staging music")
	_expect(StringName(staging_snapshot.get(&"arrangement_hash", &"")) == StringName(weekend.get(&"contract_hash", &"")), "Activity preparation did not select its event identity")
	audio.call(&"_on_session_updated", {
		&"event_id": &"MESA_HEAT", &"track_id": &"MESA_MX", &"phase": &"RACING",
		&"current_lap": 1, &"total_laps": 3, &"current_checkpoint": 1, &"checkpoint_count": 8,
	})
	_expect(StringName(audio.get_audio_contract_snapshot().get(&"music_state", &"")) == &"RACING", "Racing snapshot did not select racing stems")
	for _sample: int in 3:
		audio.call(&"_on_field_updated", 4, 12, 4.5, 12.0)
	_expect(StringName(audio.get_audio_contract_snapshot().get(&"music_state", &"")) == &"CLOSE_BATTLE", "Stable close-field samples did not select close-battle stems")
	for _sample: int in 5:
		audio.call(&"_on_field_updated", 4, 12, 18.0, 16.0)
	audio.call(&"_on_session_updated", {
		&"event_id": &"MESA_HEAT", &"track_id": &"MESA_MX", &"phase": &"RACING",
		&"current_lap": 3, &"total_laps": 3, &"current_checkpoint": 1, &"checkpoint_count": 8,
	})
	_expect(StringName(audio.get_audio_contract_snapshot().get(&"music_state", &"")) == &"FINAL_LAP", "Final-lap snapshot did not select final-lap stems")
	audio.call(&"_on_race_results_ready", {})
	var results_snapshot := audio.get_audio_contract_snapshot()
	_expect(StringName(results_snapshot.get(&"music_state", &"")) == &"RESULTS", "Results signal did not select results stems")
	_expect(int(results_snapshot.get(&"transition_count", 0)) >= 5, "Adaptive state transitions did not respond to the complete session sequence")
	_expect(float((results_snapshot.get(&"state_mix", {}) as Dictionary).get(&"RESULTS", -80.0)) > -10.0, "Results stem is not audible in the results mix")

	var class_125 := EngineAudio.get_class_timbre_contract(&"125")
	var class_250 := EngineAudio.get_class_timbre_contract(&"250")
	var class_450 := EngineAudio.get_class_timbre_contract(&"450")
	var timbre_hashes := [class_125.get(&"contract_hash", &""), class_250.get(&"contract_hash", &""), class_450.get(&"contract_hash", &"")]
	_expect(timbre_hashes[0] != timbre_hashes[1] and timbre_hashes[0] != timbre_hashes[2] and timbre_hashes[1] != timbre_hashes[2], "125/250/450 timbre contracts are not distinct")
	_expect(int(class_125.get(&"displacement_cc", 0)) == 125 and int(class_250.get(&"displacement_cc", 0)) == 250 and int(class_450.get(&"displacement_cc", 0)) == 450, "Displacement aliases do not normalize correctly")
	var engine := EngineAudio.new()
	add_child(engine)
	engine.configure_class(&"450")
	var timbre_snapshot := engine.get_timbre_snapshot()
	_expect(StringName(timbre_snapshot.get(&"class_id", &"")) == &"OPEN", "configure_class did not select the 450/Open profile")
	_expect(float(timbre_snapshot.get(&"transition_hz", 0.0)) > 0.0, "Class changes are not smoothed")

	if _failures.is_empty():
		print("EVENT_AUDIO_IDENTITY_PROBE PASS quarry=%s pine=%s mesa=%s weekend=%s finale=%s challenge=%s transitions=%d" % [
			quarry_hash, pine_hash, mesa_hash,
			weekend.get(&"contract_hash", &""), finale.get(&"contract_hash", &""), challenge.get(&"contract_hash", &""),
			int(results_snapshot.get(&"transition_count", 0)),
		])
	else:
		for failure: String in _failures:
			push_error("EVENT_AUDIO_IDENTITY_PROBE: %s" % failure)
	engine.queue_free()
	audio.queue_free()
	get_tree().quit(0 if _failures.is_empty() else 1)


func _expect(condition: bool, failure: String) -> void:
	if not condition:
		_failures.append(failure)
