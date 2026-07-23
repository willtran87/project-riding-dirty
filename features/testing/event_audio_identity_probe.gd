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
	_expect(StringName(buses.get(&"feedback", &"")) == &"SFX", "Feedback bypasses the SFX bus")
	_expect(StringName(buses.get(&"engine", &"")) == &"Engine", "Engine/contact audio has no independent bus")
	var topology := GameplayAudio.ensure_audio_buses()
	_expect(int(topology.get(&"music", -1)) >= 0, "Music bus was not established")
	_expect(int(topology.get(&"feedback", -1)) >= 0, "SFX bus was not established")
	_expect(int(topology.get(&"engine", -1)) >= 0, "Engine bus was not established")
	_expect(
		int(topology.get(&"feedback", -1)) != int(topology.get(&"engine", -1)),
		"Engine and effects resolve to the same mixer bus"
	)
	var transition_contract := GameplayAudio.get_transition_contract()
	_expect(float(transition_contract.get(&"arrangement_crossfade_seconds", 0.0)) >= 0.35, "Arrangement crossfade is too short for click-free switching")
	_expect(float(transition_contract.get(&"minimum_stem_transition_seconds", 0.0)) >= 0.30, "Stem transition contract is too abrupt")
	var denial_contract := GameplayAudio.get_flow_denied_audio_contract()
	_expect(StringName(denial_contract.get(&"cue", &"")) == &"flow_denied", "Flow denial has no dedicated cue identity")
	_expect(StringName(denial_contract.get(&"bus", &"")) == &"SFX", "Flow denial bypasses the pooled SFX route")
	_expect(float(denial_contract.get(&"start_hz", 0.0)) > float(denial_contract.get(&"end_hz", 0.0)), "Flow denial cue does not descend")
	_expect(float(denial_contract.get(&"volume_db", 0.0)) < 0.0, "Flow denial cue is not restrained below success feedback")
	_expect(int(denial_contract.get(&"cooldown_usec", 0)) >= 200_000, "Flow denial cue can spam under repeated input")
	_expect(int(denial_contract.get(&"pooled_voices", 0)) >= 4, "Flow denial does not use the shared voice pool")
	var interface_contract := GameplayAudio.get_interface_feedback_contract()
	var interface_kinds := interface_contract.get(&"kinds", {}) as Dictionary
	_expect(StringName(interface_contract.get(&"bus", &"")) == &"SFX", "Interface feedback bypasses the SFX bus")
	_expect(int(interface_contract.get(&"pooled_voices", 0)) >= 4, "Interface feedback does not use pooled voices")
	_expect(int(interface_contract.get(&"cooldown_usec", 0)) >= 25_000, "Interface feedback has no anti-spam interval")
	_expect(interface_kinds.size() == 4, "Interface feedback does not define exactly navigate/confirm/cancel/denied")
	for required_kind: StringName in [&"NAVIGATE", &"CONFIRM", &"CANCEL", &"DENIED"]:
		_expect(interface_kinds.has(required_kind), "Interface feedback is missing %s" % String(required_kind))
	var navigate_spec := interface_kinds.get(&"NAVIGATE", {}) as Dictionary
	var confirm_spec := interface_kinds.get(&"CONFIRM", {}) as Dictionary
	var cancel_spec := interface_kinds.get(&"CANCEL", {}) as Dictionary
	var interface_denied_spec := interface_kinds.get(&"DENIED", {}) as Dictionary
	_expect(float(navigate_spec.get(&"end_hz", 0.0)) > float(navigate_spec.get(&"start_hz", 0.0)), "Navigation cue has no positive motion")
	_expect(float(confirm_spec.get(&"end_hz", 0.0)) > float(confirm_spec.get(&"start_hz", 0.0)), "Confirmation cue does not rise")
	_expect(float(cancel_spec.get(&"end_hz", 0.0)) < float(cancel_spec.get(&"start_hz", 0.0)), "Cancel cue does not descend")
	_expect(float(interface_denied_spec.get(&"end_hz", 0.0)) < float(interface_denied_spec.get(&"start_hz", 0.0)), "Denied cue does not descend")
	var interface_cues := PackedStringArray()
	for spec_value: Variant in interface_kinds.values():
		if spec_value is Dictionary:
			interface_cues.append(String((spec_value as Dictionary).get(&"cue", "")))
	_expect(interface_cues.size() == 4 and interface_cues[0] != interface_cues[1] and interface_cues[0] != interface_cues[2] and interface_cues[0] != interface_cues[3] and interface_cues[1] != interface_cues[2] and interface_cues[1] != interface_cues[3] and interface_cues[2] != interface_cues[3], "Interface meanings share an ambiguous cue identity")
	var sponsor_contract := GameplayAudio.get_sponsor_feedback_contract()
	var sponsor_identities := sponsor_contract.get(&"identities", {}) as Dictionary
	_expect(StringName(sponsor_contract.get(&"bus", &"")) == &"SFX", "Sponsor feedback bypasses the SFX bus")
	_expect(int(sponsor_contract.get(&"pooled_voices", 0)) >= 4, "Sponsor feedback bypasses the shared voice pool")
	_expect(sponsor_identities.size() == 4, "Sponsor feedback does not expose three identities plus fallback")
	var sponsor_cues := PackedStringArray()
	for sponsor_id: StringName in [&"DUSTLINE", &"WILDBRUSH", &"SUNDOWN"]:
		var sponsor_spec := sponsor_identities.get(sponsor_id, {}) as Dictionary
		var sponsor_cue := String(sponsor_spec.get(&"cue", ""))
		_expect(not sponsor_cue.is_empty(), "Sponsor feedback is missing %s" % String(sponsor_id))
		sponsor_cues.append(sponsor_cue)
	_expect(sponsor_cues[0] != sponsor_cues[1] and sponsor_cues[0] != sponsor_cues[2] and sponsor_cues[1] != sponsor_cues[2], "Sponsor identities share an ambiguous completion cue")

	var audio := GameplayAudio.new()
	add_child(audio)
	audio.call(&"_build_cues")
	for sponsor_title: String in [
		"DUSTLINE WORKS PROSPECT // LAND 2 CLEAN JUMPS",
		"WILDBRUSH OUTPOST PROSPECT // FIND 2 SECRET LINES",
		"SUNDOWN STATIC PROSPECT // CHAIN 4 MOVES",
	]:
		audio.set("_contract_cued", false)
		audio.call(&"_on_contract_updated", sponsor_title, 1, 1, true, 350, 35)
	var sponsor_snapshot := audio.get_sponsor_feedback_snapshot()
	var sponsor_ready := sponsor_snapshot.get(&"cue_ready", {}) as Dictionary
	_expect(int(sponsor_snapshot.get(&"count", 0)) == 3, "Sponsor completion feedback did not accept three distinct programs")
	_expect(StringName(sponsor_snapshot.get(&"last_sponsor_id", &"")) == &"SUNDOWN", "Sponsor completion feedback lost the selected program")
	_expect(StringName(sponsor_snapshot.get(&"last_cue", &"")) == &"sponsor_sundown", "Sponsor completion feedback selected the wrong motif")
	for sponsor_id: StringName in [&"DUSTLINE", &"WILDBRUSH", &"SUNDOWN", &"GENERIC"]:
		_expect(bool(sponsor_ready.get(sponsor_id, false)), "Sponsor cue was not built for %s" % String(sponsor_id))
	EventBus.interface_feedback_requested.emit(&"NAVIGATE", &"PROBE_NAV")
	EventBus.interface_feedback_requested.emit(&"CONFIRM", &"PROBE_CONFIRM")
	EventBus.interface_feedback_requested.emit(&"CANCEL", &"PROBE_CANCEL")
	EventBus.interface_feedback_requested.emit(&"DENIED", &"PROBE_DENIED")
	EventBus.interface_feedback_requested.emit(&"DENIED", &"PROBE_SPAM")
	var interface_snapshot := audio.get_interface_feedback_snapshot()
	_expect(int(interface_snapshot.get(&"count", 0)) == 4, "EventBus did not route all four interface meanings exactly once")
	_expect(int(interface_snapshot.get(&"suppressed_count", 0)) == 1, "Repeated interface feedback bypassed anti-spam suppression")
	_expect(StringName(interface_snapshot.get(&"last_kind", &"")) == &"DENIED", "Interface feedback lost its final semantic kind")
	_expect(StringName(interface_snapshot.get(&"last_context", &"")) == &"PROBE_DENIED", "Interface feedback lost its accepted source context")
	var cue_ready := interface_snapshot.get(&"cue_ready", {}) as Dictionary
	for required_kind: StringName in [&"NAVIGATE", &"CONFIRM", &"CANCEL", &"DENIED"]:
		_expect(bool(cue_ready.get(required_kind, false)), "Procedural interface cue was not built for %s" % String(required_kind))
	var denial_payload := {&"technique": &"SURGE", &"required": 35.0, &"available": 0.0}
	audio.call(&"_on_bike_racecraft_event", &"FLOW_DENIED", denial_payload)
	audio.call(&"_on_bike_racecraft_event", &"FLOW_DENIED", denial_payload)
	var denial_snapshot := audio.get_racecraft_audio_feedback_snapshot()
	_expect(bool(denial_snapshot.get(&"flow_denied_cue_ready", false)), "Procedural Flow denial cue was not built")
	_expect(int(denial_snapshot.get(&"flow_denied_cue_count", 0)) == 1, "First Flow denial was not accepted exactly once")
	_expect(int(denial_snapshot.get(&"flow_denied_suppressed_count", 0)) == 1, "Repeated Flow denial bypassed anti-spam suppression")
	_expect(
		StringName((denial_snapshot.get(&"last_flow_denied_payload", {}) as Dictionary).get(&"technique", &"")) == &"SURGE",
		"Flow denial audio lost its semantic payload"
	)
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
	engine.call(&"_assign_engine_bus")
	_expect(engine.bus == &"Engine", "EngineAudio did not bind to the independent Engine bus")
	engine.configure_class(&"450")
	var timbre_snapshot := engine.get_timbre_snapshot()
	_expect(StringName(timbre_snapshot.get(&"class_id", &"")) == &"OPEN", "configure_class did not select the 450/Open profile")
	_expect(float(timbre_snapshot.get(&"transition_hz", 0.0)) > 0.0, "Class changes are not smoothed")

	if _failures.is_empty():
		print("EVENT_AUDIO_IDENTITY_PROBE PASS quarry=%s pine=%s mesa=%s weekend=%s finale=%s challenge=%s transitions=%d flow_denied=%s interface=%d/%d" % [
			quarry_hash, pine_hash, mesa_hash,
			weekend.get(&"contract_hash", &""), finale.get(&"contract_hash", &""), challenge.get(&"contract_hash", &""),
			int(results_snapshot.get(&"transition_count", 0)),
			str(int(denial_snapshot.get(&"flow_denied_cue_count", 0)) == 1 and int(denial_snapshot.get(&"flow_denied_suppressed_count", 0)) == 1),
			int(interface_snapshot.get(&"count", 0)), int(interface_snapshot.get(&"suppressed_count", 0)),
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
