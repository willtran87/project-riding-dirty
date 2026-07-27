extends Node
## End-to-end team palette, decal, sponsor placement, save, visual, podium, and Web proof.

const PLAYER_PROFILE_SCRIPT := preload("res://common/player_profile.gd")
const GRAPHICS_CATALOG := preload("res://features/career/rider_graphics_catalog.gd")
const GARAGE_SCENE := preload("res://features/garage/garage_ui.tscn")
const BIKE_SCENE := preload("res://entities/bike/bike.tscn")
const PODIUM_SCRIPT := preload("res://features/hud/podium_ceremony.gd")
const WEB_STATE := preload("res://common/web_game_text_state.gd")

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
		and str(defaults.get(&"team_palette", "")) == "STYLE"
		and str(defaults.get(&"decal_id", "")) == "CLEAN"
		and str(defaults.get(&"sponsor_id", "")) == "NONE"
		and str(defaults.get(&"sponsor_placement", "")) == "SHROUDS",
		"Schema-10 profiles do not receive conservative graphics defaults"
	)
	_check(
		GRAPHICS_CATALOG.workshop_items().size() == 19,
		"Graphics catalog does not expose every authored field and option"
	)

	var tampered: Variant = PLAYER_PROFILE_SCRIPT.new()
	tampered.persistence_enabled = false
	tampered._apply_profile_dictionary({
		"profile_schema_version": 10,
		"rider_cosmetics": {
			"team_palette": "INJECTED_COLOR",
			"decal_id": "ARBITRARY_GEOMETRY",
			"sponsor_id": "<script>",
			"sponsor_placement": "EVERYWHERE",
		},
	})
	var safe: Dictionary = tampered.get_rider_cosmetics()
	_check(
		str(safe.get(&"team_palette", "")) == "STYLE"
		and str(safe.get(&"decal_id", "")) == "CLEAN"
		and str(safe.get(&"sponsor_id", "")) == "NONE"
		and str(safe.get(&"sponsor_placement", "")) == "SHROUDS",
		"Untrusted graphics choices survived the profile boundary"
	)
	var legacy: Variant = PLAYER_PROFILE_SCRIPT.new()
	legacy.persistence_enabled = false
	legacy._apply_profile_dictionary({"profile_schema_version": 9})
	legacy._ensure_full_race_defaults()
	_check(
		legacy.get_rider_cosmetics().get(&"team_palette", "") == "STYLE"
		and legacy.get_rider_cosmetics().get(&"decal_id", "") == "CLEAN",
		"Schema-9 riders did not migrate without changing their prior appearance"
	)

	Profile.persistence_enabled = false
	Profile.reset_profile_for_testing()
	var performance_before := Profile.get_active_bike_setup_snapshot()
	var garage := GARAGE_SCENE.instantiate() as GarageUi
	add_child(garage)
	await get_tree().process_frame
	garage.show_garage()
	garage.show_workshop()
	for _step: int in GarageUi.WORKSHOP_CATEGORIES.size():
		if StringName(garage.get_workshop_snapshot().get(&"category", &"")) == &"GRAPHICS":
			break
		garage.cycle_workshop_category(1)
	_check(
		StringName(garage.get_workshop_snapshot().get(&"category", &"")) == &"GRAPHICS",
		"Workshop has no Graphics category"
	)
	_check(_select_and_apply(garage, &"team_palette", &"NIGHTSHIFT"), "Nightshift team palette was not applied")
	_check(_select_and_apply(garage, &"decal_id", &"LIGHTNING"), "Lightning decal was not applied")
	_check(_select_and_apply(garage, &"sponsor_id", &"DUSTLINE"), "Dustline sponsor was not applied")
	_check(_select_and_apply(garage, &"sponsor_placement", &"FULL_KIT"), "Full-kit placement was not applied")
	var equipped := Profile.get_rider_cosmetics()
	_check(
		str(equipped.get(&"team_palette", "")) == "NIGHTSHIFT"
		and str(equipped.get(&"decal_id", "")) == "LIGHTNING"
		and str(equipped.get(&"sponsor_id", "")) == "DUSTLINE"
		and str(equipped.get(&"sponsor_placement", "")) == "FULL_KIT",
		"Workshop graphics did not reach the authoritative profile"
	)
	_check(
		str(garage.get_workshop_snapshot().get(&"workshop_detail", "")).contains("COSMETIC ONLY"),
		"Graphics Workshop does not clearly disclose the zero-performance effect"
	)
	_check(
		Profile.get_active_bike_setup_snapshot() == performance_before,
		"Graphics customization changed bike performance"
	)

	var saved := Profile.save_current_rider_outfit(&"OUTFIT_A", "Nightshift Dustline")
	_check(bool(saved.get(&"accepted", false)), "Graphics identity could not be saved as an outfit")
	_check(Profile.set_rider_cosmetics({
		&"team_palette": &"STYLE", &"decal_id": &"CLEAN",
		&"sponsor_id": &"NONE", &"sponsor_placement": &"SHROUDS",
	}), "Probe could not change away from saved graphics")
	var loaded := Profile.load_saved_rider_outfit(&"OUTFIT_A")
	var restored := Profile.get_rider_cosmetics()
	_check(
		bool(loaded.get(&"accepted", false))
		and str(restored.get(&"team_palette", "")) == "NIGHTSHIFT"
		and str(restored.get(&"decal_id", "")) == "LIGHTNING"
		and str(restored.get(&"sponsor_id", "")) == "DUSTLINE"
		and str(restored.get(&"sponsor_placement", "")) == "FULL_KIT",
		"Saved outfit did not restore the complete graphics identity"
	)

	var bike := BIKE_SCENE.instantiate() as DirtBikeController
	add_child(bike)
	await get_tree().process_frame
	bike.apply_rider_cosmetics(restored)
	var presentation := bike.get_rider_equipment_presentation_snapshot()
	var graphics: Dictionary = presentation.get(&"graphics", {}) as Dictionary
	var visible: Dictionary = presentation.get(&"visible", {}) as Dictionary
	var colors: Dictionary = presentation.get(&"colors", {}) as Dictionary
	_check(
		str(graphics.get(&"team_palette", "")) == "NIGHTSHIFT"
		and str(colors.get(&"red", "")) == "35b8d4"
		and int(visible.get(&"decal_meshes", 0)) == 6
		and int(visible.get(&"sponsor_marks", 0)) == 6,
		"Selected graphics did not become real, distinct bike and rider surfaces"
	)
	var rider_kit := restored.duplicate(true)
	rider_kit[&"sponsor_placement"] = &"RIDER_KIT"
	bike.apply_rider_cosmetics(rider_kit)
	_check(
		int((bike.get_rider_equipment_presentation_snapshot().get(&"visible", {}) as Dictionary).get(
			&"sponsor_marks", 0
		)) == 2,
		"Rider-kit placement did not isolate sponsor marks to chest and back"
	)
	var privateer := rider_kit.duplicate(true)
	privateer[&"sponsor_id"] = &"NONE"
	bike.apply_rider_cosmetics(privateer)
	_check(
		int((bike.get_rider_equipment_presentation_snapshot().get(&"visible", {}) as Dictionary).get(
			&"sponsor_marks", -1
		)) == 0,
		"Privateer selection did not remove sponsor marks"
	)

	var podium := PODIUM_SCRIPT.new() as PodiumCeremony
	add_child(podium)
	podium.present([
		{&"position": 1, &"rider_id": &"PLAYER", &"display_name": "YOU", &"number": 17, &"is_player": true},
		{&"position": 2, &"rider_id": &"ROOK", &"display_name": "ROOK", &"number": 32, &"is_player": false},
		{&"position": 3, &"rider_id": &"JUNE", &"display_name": "JUNE", &"number": 8, &"is_player": false},
	], {&"event_name": "Mesa Main", &"player_position": 1}, restored)
	var podium_snapshot := podium.get_presentation_snapshot()
	_check(
		str(podium_snapshot.get(&"team_palette", "")) == "NIGHTSHIFT"
		and str(podium_snapshot.get(&"decal_id", "")) == "LIGHTNING"
		and str(podium_snapshot.get(&"sponsor_id", "")) == "DUSTLINE"
		and str(podium_snapshot.get(&"sponsor_placement", "")) == "FULL_KIT",
		"Official podium snapshot lost the player's graphics identity"
	)
	var web := WEB_STATE.build({
		&"mode": &"CIRCUIT",
		&"player": {&"cosmetics": restored},
		&"results": {&"results_visible": true, &"podium": podium_snapshot},
	})
	var web_player: Dictionary = web.get(&"player", {}) as Dictionary
	var web_podium: Dictionary = (web.get(&"results", {}) as Dictionary).get(&"podium", {}) as Dictionary
	_check(
		str(web_player.get(&"team_palette", "")) == "NIGHTSHIFT"
		and str(web_player.get(&"decal_id", "")) == "LIGHTNING"
		and str(web_player.get(&"sponsor_id", "")) == "DUSTLINE"
		and str(web_podium.get(&"sponsor_placement", "")) == "FULL_KIT",
		"Browser state lost live or podium graphics identity"
	)

	print(
		"RIDER GRAPHICS CUSTOMIZATION PROBE: palette=%s decal=%s sponsor=%s placement=%s meshes=%d marks=%d saved=restored web=projected passed=%s" % [
			restored.get(&"team_palette", ""), restored.get(&"decal_id", ""),
			restored.get(&"sponsor_id", ""), restored.get(&"sponsor_placement", ""),
			int(visible.get(&"decal_meshes", 0)), int(visible.get(&"sponsor_marks", 0)),
			str(_failures.is_empty()),
		]
	)
	podium.queue_free()
	bike.queue_free()
	garage.queue_free()
	profile.free()
	tampered.free()
	legacy.free()
	await get_tree().process_frame
	if _failures.is_empty():
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("RIDER GRAPHICS CUSTOMIZATION PROBE: %s" % failure)
	get_tree().quit(1)


func _select_and_apply(
	garage: GarageUi,
	field: StringName,
	choice_id: StringName
) -> bool:
	for _step: int in GRAPHICS_CATALOG.workshop_items().size():
		var selected := garage.get_workshop_snapshot().get(&"selected_item", {}) as Dictionary
		if (
			StringName(selected.get(&"graphics_field", &"")) == field
			and StringName(selected.get(&"choice_id", &"")) == choice_id
		):
			return garage.confirm_workshop_item()
		garage.cycle_workshop_item(1)
	return false


func _check(condition: bool, failure: String) -> void:
	if not condition:
		_failures.append(failure)
