extends Node
## Complete rider body, skin, and nonverbal voice identity production chain.

const PLAYER_PROFILE_SCRIPT := preload("res://common/player_profile.gd")
const GARAGE_SCENE := preload("res://features/garage/garage_ui.tscn")
const BIKE_SCENE := preload("res://entities/bike/bike.tscn")

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var profile: Variant = PLAYER_PROFILE_SCRIPT.new()
	profile.persistence_enabled = false
	profile._ensure_full_race_defaults()
	var defaults: Dictionary = profile.get_rider_cosmetics()
	_check(
		profile.PROFILE_SCHEMA_VERSION == 10
		and str(defaults.get(&"body_type", "")) == "ATHLETIC"
		and str(defaults.get(&"skin_tone", "")) == "MEDIUM"
		and str(defaults.get(&"voice", "")) == "FOCUSED",
		"New profiles do not receive the complete safe rider identity"
	)

	var tampered: Variant = PLAYER_PROFILE_SCRIPT.new()
	tampered.persistence_enabled = false
	tampered._apply_profile_dictionary({
		"profile_schema_version": 10,
		"rider_cosmetics": {
			"body_type": "GIANT_PHYSICS",
			"skin_tone": "INVISIBLE",
			"voice": "UNBOUNDED",
			"rider_number": 17,
		},
	})
	tampered._ensure_full_race_defaults()
	var sanitized: Dictionary = tampered.get_rider_cosmetics()
	_check(
		str(sanitized.get(&"body_type", "")) == "ATHLETIC"
		and str(sanitized.get(&"skin_tone", "")) == "MEDIUM"
		and str(sanitized.get(&"voice", "")) == "FOCUSED",
		"Untrusted identity choices survived the profile boundary"
	)
	var legacy: Variant = PLAYER_PROFILE_SCRIPT.new()
	legacy.persistence_enabled = false
	legacy._apply_profile_dictionary({"profile_schema_version": 8})
	legacy._ensure_full_race_defaults()
	_check(
		str(legacy.get_rider_cosmetics().get(&"body_type", "")) == "ATHLETIC"
		and str(legacy.get_rider_cosmetics().get(&"skin_tone", "")) == "MEDIUM"
		and str(legacy.get_rider_cosmetics().get(&"voice", "")) == "FOCUSED",
		"Schema-8 riders did not migrate to conservative identity defaults"
	)

	Profile.persistence_enabled = false
	Profile.reset_profile_for_testing()
	var audio := GameplayAudio.new()
	add_child(audio)
	audio.call(&"_build_cues")
	var garage := GARAGE_SCENE.instantiate() as GarageUi
	add_child(garage)
	await get_tree().process_frame
	garage.show_garage()
	garage.show_workshop()
	for _step: int in 12:
		if StringName(garage.get_workshop_snapshot().get(&"category", &"")) == &"RIDER":
			break
		garage.cycle_workshop_category(1)
	_check(
		StringName(garage.get_workshop_snapshot().get(&"category", &"")) == &"RIDER",
		"Workshop has no rider identity category"
	)
	_check(
		str((garage.get_workshop_snapshot().get(&"selected_item", {}) as Dictionary).get(
			&"choice_id", ""
		)) == "ATHLETIC",
		"Rider category did not focus the active body type"
	)
	_check(_select_and_apply(garage, &"body_type", &"POWERFUL"), "Powerful body type was not applied")
	_check(_select_and_apply(garage, &"skin_tone", &"DEEP"), "Deep skin tone was not applied")
	_check(_select_and_apply(garage, &"voice", &"GROUNDED"), "Grounded voice was not applied")
	var selected: Dictionary = Profile.get_rider_cosmetics()
	_check(
		str(selected.get(&"body_type", "")) == "POWERFUL"
		and str(selected.get(&"skin_tone", "")) == "DEEP"
		and str(selected.get(&"voice", "")) == "GROUNDED",
		"Workshop selections did not reach the authoritative profile"
	)
	_check(
		str(garage.get_workshop_snapshot().get(&"workshop_status", "")).contains("VOICE PREVIEW"),
		"Voice selection did not provide semantic preview feedback"
	)
	var preview_audio := audio.get_rider_voice_feedback_snapshot()
	_check(
		bool(preview_audio.get(&"cue_ready", false))
		and int(preview_audio.get(&"count", 0)) == 1
		and StringName(preview_audio.get(&"last_voice_id", &"")) == &"GROUNDED"
		and StringName(preview_audio.get(&"last_context", &"")) == &"PREVIEW"
		and is_equal_approx(float(preview_audio.get(&"last_pitch", 0.0)), 0.84),
		"Grounded voice preview did not reach its authored audio identity"
	)
	var voice_contract := GameplayAudio.get_rider_voice_audio_contract()
	var voice_profiles: Dictionary = voice_contract.get(&"profiles", {}) as Dictionary
	_check(
		StringName(voice_contract.get(&"bus", &"")) == &"Commentary"
		and voice_profiles.size() == 3
		and float((voice_profiles.get(&"BRIGHT", {}) as Dictionary).get(&"pitch", 0.0))
			> float((voice_profiles.get(&"GROUNDED", {}) as Dictionary).get(&"pitch", 1.0)),
		"Voice profiles do not expose three distinct, mixer-routed registers"
	)

	var performance_before := Profile.get_active_bike_setup_snapshot()
	var saved := Profile.save_current_rider_outfit(&"OUTFIT_A", "Powerful Grounded")
	_check(bool(saved.get(&"accepted", false)), "Complete identity could not be saved as an outfit")
	_check(
		Profile.set_rider_cosmetics({
			&"body_type": &"COMPACT", &"skin_tone": &"LIGHT", &"voice": &"BRIGHT",
		}),
		"Probe could not change away from the saved identity"
	)
	var loaded := Profile.load_saved_rider_outfit(&"OUTFIT_A")
	var restored: Dictionary = Profile.get_rider_cosmetics()
	_check(
		bool(loaded.get(&"accepted", false))
		and str(restored.get(&"body_type", "")) == "POWERFUL"
		and str(restored.get(&"skin_tone", "")) == "DEEP"
		and str(restored.get(&"voice", "")) == "GROUNDED",
		"Saved outfit did not restore body, skin, and voice together"
	)
	_check(
		Profile.get_active_bike_setup_snapshot() == performance_before,
		"Rider identity changed bike performance configuration"
	)

	var bike := BIKE_SCENE.instantiate() as DirtBikeController
	add_child(bike)
	await get_tree().process_frame
	bike.apply_rider_cosmetics(restored)
	var presentation := bike.get_rider_equipment_presentation_snapshot()
	var visual_identity: Dictionary = presentation.get(&"identity", {}) as Dictionary
	var colors: Dictionary = presentation.get(&"colors", {}) as Dictionary
	var body_scale: Vector3 = visual_identity.get(&"body_scale", Vector3.ONE)
	_check(
		StringName(visual_identity.get(&"body_type", &"")) == &"POWERFUL"
		and body_scale.x > 1.08
		and body_scale.y > 1.0,
		"Powerful body type did not alter the articulated rider silhouette"
	)
	_check(
		str(colors.get(&"skin", "")) == "543224"
		and not bike.find_children("*skin", "MeshInstance3D", true, false).is_empty(),
		"Deep skin tone did not reach a visible neck or helmet-opening surface"
	)

	audio.set(&"_last_rider_voice_usec", -2_000_000)
	audio.call(&"_on_boost_activated", 20.0)
	var riding_audio := audio.get_rider_voice_feedback_snapshot()
	audio.call(&"_on_bike_landed", 0.92)
	var suppressed_audio := audio.get_rider_voice_feedback_snapshot()
	_check(
		StringName(riding_audio.get(&"last_voice_id", &"")) == &"GROUNDED"
		and StringName(riding_audio.get(&"last_context", &"")) == &"BOOST"
		and int(suppressed_audio.get(&"suppressed_count", 0)) == 1,
		"Riding exertion ignored the selected voice or its anti-spam cooldown"
	)

	print(
		"RIDER IDENTITY OPTIONS PROBE: body=%s scale=%.2f skin=%s voice=%s pitch=%.2f outfit=restored audio=preview+ride passed=%s" % [
			str(restored.get(&"body_type", "")), body_scale.x,
			str(restored.get(&"skin_tone", "")), str(restored.get(&"voice", "")),
			float(riding_audio.get(&"last_pitch", 0.0)), str(_failures.is_empty()),
		]
	)
	bike.queue_free()
	garage.queue_free()
	audio.queue_free()
	profile.free()
	tampered.free()
	legacy.free()
	await get_tree().process_frame
	if _failures.is_empty():
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("RIDER IDENTITY OPTIONS PROBE: %s" % failure)
	get_tree().quit(1)


func _select_and_apply(
	garage: GarageUi,
	field: StringName,
	choice_id: StringName
) -> bool:
	for _step: int in GarageUi.RIDER_IDENTITY_OPTIONS.size():
		var selected_item := garage.get_workshop_snapshot().get(&"selected_item", {}) as Dictionary
		if (
			StringName(selected_item.get(&"field", &"")) == field
			and StringName(selected_item.get(&"choice_id", &"")) == choice_id
		):
			return garage.confirm_workshop_item()
		garage.cycle_workshop_item(1)
	return false


func _check(condition: bool, failure: String) -> void:
	if not condition:
		_failures.append(failure)
