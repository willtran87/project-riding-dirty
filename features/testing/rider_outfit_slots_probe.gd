extends Node
## Independent, durable rider outfit slots and their Workshop/visual projection.

const PLAYER_PROFILE_SCRIPT := preload("res://common/player_profile.gd")
const FAILING_PROFILE_SCRIPT := preload("res://features/testing/failing_activity_settlement_profile.gd")
const GARAGE_SCENE := preload("res://features/garage/garage_ui.tscn")
const BIKE_SCENE := preload("res://entities/bike/bike.tscn")

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var profile: Variant = PLAYER_PROFILE_SCRIPT.new()
	profile.persistence_enabled = false
	profile._ensure_full_race_defaults()
	profile.cash = 4321
	profile.racer_reputation = 91
	profile.apply_bike_damage(23)
	var factory: Dictionary = profile.get_rider_cosmetics()
	factory[&"rider_number"] = 17
	_check(profile.set_rider_cosmetics(factory), "Factory identity could not be applied")
	var saved_a: Dictionary = profile.save_current_rider_outfit(&"OUTFIT_A", "Quarry\nClassic")
	_check(bool(saved_a.get(&"accepted", false)), "Outfit A was not saved")
	_check(
		str((saved_a.get(&"outfit", {}) as Dictionary).get(&"display_name", "")) == "QUARRY CLASSIC",
		"Outfit name was not normalized"
	)

	var night := {
		&"helmet": "NIGHT_BLACK", &"goggles": "CYAN_LENS",
		&"jersey": "NIGHT_CYAN", &"pants": "BLACK",
		&"boots": "BLACK", &"gloves": "CYAN",
		&"protection": "CHEST_PLATE", &"accessory": "HYDRATION_PACK",
		&"bike_livery": "NIGHT_RACE",
		&"number_plate": "BLACK", &"accent_color": "56D6FF", &"rider_number": 64,
		&"body_type": "ATHLETIC", &"skin_tone": "MEDIUM", &"voice": "FOCUSED",
	}
	_check(profile.set_rider_cosmetics(night), "Night identity could not be applied")
	var saved_b: Dictionary = profile.save_current_rider_outfit(&"OUTFIT_B")
	_check(bool(saved_b.get(&"accepted", false)), "Outfit B was not saved")
	var build_before: Dictionary = profile.get_bike_build_snapshot(profile.active_bike_id)
	var load_a: Dictionary = profile.load_saved_rider_outfit(&"OUTFIT_A")
	_check(bool(load_a.get(&"accepted", false)), "Outfit A was not loaded")
	_check(profile.get_rider_cosmetics() == factory, "Loading Outfit A did not restore every cosmetic field")
	var build_after: Dictionary = profile.get_bike_build_snapshot(profile.active_bike_id)
	_check(
		(build_after.get(&"tune", {}) as Dictionary) == (build_before.get(&"tune", {}) as Dictionary)
		and (build_after.get(&"installed_parts", {}) as Dictionary) == (build_before.get(&"installed_parts", {}) as Dictionary),
		"Loading an outfit changed performance configuration"
	)
	_check(
		profile.bike_condition == 77 and profile.cash == 4321 and profile.racer_reputation == 91,
		"Loading an outfit changed durability or career progression"
	)
	_check(
		StringName(build_after.get(&"livery_id", &"")) == &"FACTORY",
		"Loaded outfit livery did not reach the active bike"
	)
	var load_b: Dictionary = profile.load_saved_rider_outfit(&"OUTFIT_B")
	_check(
		bool(load_b.get(&"accepted", false))
		and int(profile.get_rider_cosmetics().get(&"rider_number", 0)) == 64,
		"Outfit B did not preserve its distinct rider number"
	)

	# The JSON trust boundary keeps only A-C, normalizes names, bounds numbers,
	# and does not invent slots for a legacy rider.
	var serialized: Dictionary = profile._profile_to_dictionary()
	var outfit_payload: Dictionary = serialized.get("saved_rider_outfits", {}) as Dictionary
	outfit_payload["OUTFIT_Z"] = (outfit_payload.get("OUTFIT_A", {}) as Dictionary).duplicate(true)
	outfit_payload["OUTFIT_C"] = {
		"slot_id": "OUTFIT_C", "display_name": "Tampered\tIdentity",
		"cosmetics": {
			"helmet": "DESERT_CREAM", "goggles": "AMBER",
			"jersey": "MESA_SAND", "pants": "RUST",
			"boots": "BROWN", "gloves": "CREAM",
			"protection": "ENDURO_VEST", "accessory": "NECK_ROLL",
			"bike_livery": "DESERT_WORKS",
			"number_plate": "CREAM", "accent_color": "E58A3A", "rider_number": 50_000,
		},
	}
	serialized["saved_rider_outfits"] = outfit_payload
	var json_round_trip: Variant = JSON.parse_string(JSON.stringify(serialized))
	var restored: Variant = PLAYER_PROFILE_SCRIPT.new()
	restored.persistence_enabled = false
	if json_round_trip is Dictionary:
		restored._apply_profile_dictionary(json_round_trip)
		restored._ensure_full_race_defaults()
	var restored_c: Dictionary = restored.get_saved_rider_outfit_snapshot(&"OUTFIT_C")
	_check(restored.PROFILE_SCHEMA_VERSION == 10, "Profile schema was not advanced for rider graphics")
	_check(restored.get_saved_rider_outfit_slots().size() == 3, "Outfit slots are not bounded to exactly three")
	_check(str(restored_c.get(&"display_name", "")) == "TAMPERED IDENTITY", "Outfit name controls survived sanitization")
	_check(
		int((restored_c.get(&"cosmetics", {}) as Dictionary).get(&"rider_number", 0)) == 999,
		"Tampered rider number was not clamped"
	)
	_check(
		str((restored_c.get(&"cosmetics", {}) as Dictionary).get(&"goggles", "")) == "AMBER"
		and str((restored_c.get(&"cosmetics", {}) as Dictionary).get(&"protection", "")) == "ENDURO_VEST"
		and str((restored_c.get(&"cosmetics", {}) as Dictionary).get(&"accessory", "")) == "NECK_ROLL",
		"Expanded equipment fields did not survive outfit sanitization"
	)
	_check(restored.get_saved_rider_outfit_snapshot(&"OUTFIT_Z").is_empty(), "Unbounded outfit slot survived sanitization")
	var legacy: Variant = PLAYER_PROFILE_SCRIPT.new()
	legacy.persistence_enabled = false
	legacy._apply_profile_dictionary({"profile_schema_version": 7})
	legacy._ensure_full_race_defaults()
	_check(legacy.saved_rider_outfits.is_empty(), "Legacy migration invented a saved outfit")
	_check(
		str(legacy.get_rider_cosmetics().get(&"goggles", "")) == "CLEAR"
		and str(legacy.get_rider_cosmetics().get(&"protection", "")) == "ROOST_GUARD"
		and str(legacy.get_rider_cosmetics().get(&"accessory", "")) == "NONE",
		"Legacy cosmetics did not receive safe equipment defaults"
	)
	_check(
		str(legacy.get_rider_cosmetics().get(&"body_type", "")) == "ATHLETIC"
		and str(legacy.get_rider_cosmetics().get(&"skin_tone", "")) == "MEDIUM"
		and str(legacy.get_rider_cosmetics().get(&"voice", "")) == "FOCUSED",
		"Legacy cosmetics did not receive safe rider identity defaults"
	)

	# Saving and loading are atomic when durable storage refuses a write.
	var failing: Variant = FAILING_PROFILE_SCRIPT.new()
	failing.persistence_enabled = true
	failing._ensure_full_race_defaults()
	_check(bool(failing.save_current_rider_outfit(&"OUTFIT_A").get(&"accepted", false)), "Fault profile could not seed Outfit A")
	_check(failing.set_rider_cosmetics(night), "Fault profile could not select a second identity")
	var before_failed_load: Dictionary = failing.get_rider_cosmetics()
	failing.fail_next_save = true
	var failed_load: Dictionary = failing.load_saved_rider_outfit(&"OUTFIT_A")
	_check(
		not bool(failed_load.get(&"accepted", false))
		and failing.get_rider_cosmetics() == before_failed_load,
		"Failed outfit load did not roll back atomically"
	)
	failing.fail_next_save = true
	var failed_save: Dictionary = failing.save_current_rider_outfit(&"OUTFIT_B")
	_check(
		not bool(failed_save.get(&"accepted", false))
		and failing.get_saved_rider_outfit_snapshot(&"OUTFIT_B").is_empty(),
		"Failed outfit save left an in-memory slot"
	)

	# The production Workshop exposes semantic load/save actions, and the actual
	# bike visual receives the complete identity including its number plate.
	Profile.persistence_enabled = false
	Profile.reset_profile_for_testing()
	var garage := GARAGE_SCENE.instantiate() as GarageUi
	add_child(garage)
	await get_tree().process_frame
	garage.show_garage()
	garage.show_workshop()
	for _step: int in 8:
		if StringName(garage.get_workshop_snapshot().get(&"category", &"")) == &"OUTFIT":
			break
		garage.cycle_workshop_category(1)
	_check(StringName(garage.get_workshop_snapshot().get(&"category", &"")) == &"OUTFIT", "Outfit category is missing from Workshop")
	_check(int(garage.get_workshop_snapshot().get(&"item_index", -1)) == 1, "Outfit category did not focus SAVE OUTFIT A")
	_check(garage.confirm_workshop_item(), "Workshop could not save Outfit A")
	_check(
		not Profile.get_saved_rider_outfit_snapshot(&"OUTFIT_A").is_empty()
		and str(garage.get_workshop_snapshot().get(&"workshop_status", "")).contains("OUTFIT A SAVED"),
		"Workshop save feedback or Profile handoff is missing"
	)
	_check(Profile.set_rider_cosmetics(night), "Workshop probe could not change current identity")
	garage.cycle_workshop_item(-1)
	_check(garage.confirm_workshop_item(), "Workshop could not load Outfit A")
	_check(
		str(garage.get_workshop_snapshot().get(&"workshop_status", "")).contains("OUTFIT A LOADED")
		and int(Profile.get_rider_cosmetics().get(&"rider_number", 0)) == 17,
		"Workshop load feedback or rider number restore is missing"
	)

	# The same Workshop offers a true 001-999 editor. Starting at 017, cycle
	# hundreds, tens and ones once to produce 128, reject 000, then prove the
	# applied number is captured and restored by an outfit slot.
	garage.cycle_workshop_category(-1)
	_check(StringName(garage.get_workshop_snapshot().get(&"category", &"")) == &"NUMBER", "Number editor is missing before Outfit")
	_check(garage.confirm_workshop_item(), "Hundreds digit could not be edited")
	garage.cycle_workshop_item(1)
	_check(garage.confirm_workshop_item(), "Tens digit could not be edited")
	garage.cycle_workshop_item(1)
	_check(garage.confirm_workshop_item(), "Ones digit could not be edited")
	_check(int(garage.get_workshop_snapshot().get(&"rider_number_draft", 0)) == 128, "Digit editor did not produce draft #128")
	garage.cycle_workshop_item(1)
	_check(garage.confirm_workshop_item(), "Custom rider number could not be applied")
	_check(
		int(Profile.get_rider_cosmetics().get(&"rider_number", 0)) == 128
		and str(garage.get_workshop_snapshot().get(&"workshop_status", "")).contains("#128 APPLIED"),
		"Applied custom number or feedback is incorrect"
	)
	garage.set(&"_rider_number_draft", 0)
	_check(not garage.confirm_workshop_item(), "Invalid rider number 000 was accepted")
	_check(int(Profile.get_rider_cosmetics().get(&"rider_number", 0)) == 128, "Invalid number attempt mutated the rider")
	garage.cycle_workshop_category(1)
	garage.cycle_workshop_item(1)
	_check(garage.confirm_workshop_item(), "Workshop could not overwrite Outfit A with custom #128")
	_check(
		int(((Profile.get_saved_rider_outfit_snapshot(&"OUTFIT_A").get(&"cosmetics", {}) as Dictionary).get(&"rider_number", 0))) == 128,
		"Saved outfit omitted the custom rider number"
	)
	_check(Profile.set_rider_cosmetics({&"rider_number": 9}), "Probe could not change number before outfit restore")
	garage.cycle_workshop_item(-1)
	_check(garage.confirm_workshop_item(), "Workshop could not restore Outfit A custom number")
	_check(int(Profile.get_rider_cosmetics().get(&"rider_number", 0)) == 128, "Outfit did not restore custom #128")
	var bike := BIKE_SCENE.instantiate() as DirtBikeController
	add_child(bike)
	await get_tree().process_frame
	bike.apply_rider_cosmetics(Profile.get_rider_cosmetics())
	var visual_cosmetics := bike.get_rider_cosmetics_snapshot()
	var equipment_presentation := bike.get_rider_equipment_presentation_snapshot()
	var equipment_colors: Dictionary = equipment_presentation.get(&"colors", {}) as Dictionary
	var equipment_visible: Dictionary = equipment_presentation.get(&"visible", {}) as Dictionary
	var equipment_surfaces: Dictionary = equipment_presentation.get(&"separate_surfaces", {}) as Dictionary
	var number_labels := bike.find_children("*", "Label3D", true, false)
	_check(visual_cosmetics == Profile.get_rider_cosmetics(), "Bike visual did not receive the loaded outfit")
	_check(
		not number_labels.is_empty() and str(number_labels[0].get(&"text")) == "128",
		"Loaded rider number did not reach the visible plate"
	)
	_check(
		bool(equipment_surfaces.get(&"gloves", false))
		and bool(equipment_surfaces.get(&"boots", false))
		and equipment_colors.get(&"gloves", "") != equipment_colors.get(&"jersey", "")
		and not str(equipment_colors.get(&"boots", "")).is_empty(),
		"Gloves or boots are not rendered on independent cosmetic surfaces"
	)
	_check(
		bool(equipment_visible.get(&"goggles", false))
		and bool(equipment_visible.get(&"protection", false))
		and not bool(equipment_visible.get(&"accessory", true)),
		"Factory goggles, armor, or no-accessory visibility is incorrect"
	)
	bike.apply_rider_cosmetics(night)
	var night_presentation := bike.get_rider_equipment_presentation_snapshot()
	var night_visible: Dictionary = night_presentation.get(&"visible", {}) as Dictionary
	_check(
		night_presentation.get(&"cosmetics", {}) == night
		and bool(night_visible.get(&"goggles", false))
		and bool(night_visible.get(&"protection", false))
		and bool(night_visible.get(&"accessory", false)),
		"Night equipment identity did not reach all visible rider meshes"
	)

	print("RIDER OUTFIT SLOTS PROBE: slots=3 identities=A+B gear=visible custom=#128 invalid=000 workshop=save+load visual=#128 rollback=true passed=%s" % str(_failures.is_empty()))
	bike.queue_free()
	garage.queue_free()
	profile.free()
	restored.free()
	legacy.free()
	failing.free()
	await get_tree().process_frame
	if _failures.is_empty():
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("RIDER OUTFIT SLOTS PROBE: %s" % failure)
	get_tree().quit(1)


func _check(condition: bool, failure: String) -> void:
	if not condition:
		_failures.append(failure)
