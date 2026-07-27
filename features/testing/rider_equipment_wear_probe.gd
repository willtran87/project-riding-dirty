extends Node
## Deterministic environmental wear and real renderer integration coverage.

const WEAR := preload("res://features/race/rider_equipment_wear.gd")
const BIKE_SCENE := preload("res://entities/bike/bike.tscn")

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var dry := WEAR.clean_state(&"CLEAR")
	for _frame: int in 720:
		dry = WEAR.advance(dry, {
			&"surface": &"LOOSE_DIRT",
			&"weather": &"CLEAR",
			&"grounded": true,
			&"dust_amount": 1.1,
			&"roost_intensity": 0.9,
			&"speed_mps": 24.0,
		}, 1.0 / 60.0)
	_check(
		float(dry.get(&"dry_dust", 0.0)) >= 0.80
		and float(dry.get(&"mud", 1.0)) <= 0.01
		and StringName(dry.get(&"status", &"")) == &"DUST_COATED",
		"Dry loose soil did not produce a strong dust coat"
	)
	var dry_replay := WEAR.clean_state(&"CLEAR")
	for _frame: int in 720:
		dry_replay = WEAR.advance(dry_replay, {
			&"surface": &"LOOSE_DIRT",
			&"weather": &"CLEAR",
			&"grounded": true,
			&"dust_amount": 1.1,
			&"roost_intensity": 0.9,
			&"speed_mps": 24.0,
		}, 1.0 / 60.0)
	_check(dry_replay == dry, "Wear accumulation is not deterministic")

	var storm := dry.duplicate(true)
	for _frame: int in 720:
		storm = WEAR.advance(storm, {
			&"surface": &"MUD",
			&"weather": &"STORM",
			&"grounded": true,
			&"dust_amount": 0.25,
			&"roost_intensity": 1.2,
			&"speed_mps": 18.0,
		}, 1.0 / 60.0)
	_check(
		float(storm.get(&"wetness", 0.0)) >= 0.94
		and float(storm.get(&"mud", 0.0)) >= 0.82
		and float(storm.get(&"dry_dust", 1.0)) <= 0.03
		and StringName(storm.get(&"status", &"")) == &"MUD_CAKED",
		"Storm riding did not soak gear, wash dust, and build mud"
	)
	var crashed := WEAR.add_crash(storm, 0.82, &"MUD")
	_check(
		float(crashed.get(&"crash_wear", 0.0)) >= 0.74
		and float(crashed.get(&"mud", 0.0)) >= float(storm.get(&"mud", 0.0))
		and StringName(crashed.get(&"status", &"")) == &"CRASH_WORN",
		"Crash wear did not add persistent scuffing and surface soil"
	)

	var bike := BIKE_SCENE.instantiate() as DirtBikeController
	add_child(bike)
	await get_tree().process_frame
	bike.apply_rider_cosmetics({
		&"helmet": "CLASSIC_WHITE", &"goggles": "CLEAR",
		&"jersey": "MESA_RED", &"pants": "CHARCOAL",
		&"boots": "BLACK", &"gloves": "BLACK",
		&"protection": "ROOST_GUARD", &"accessory": "NONE",
		&"bike_livery": "FACTORY", &"number_plate": "WHITE",
		&"accent_color": "E25532", &"rider_number": 17,
	})
	var visual := bike.get_node("BikeVisual")
	var clean_presentation := bike.get_rider_equipment_presentation_snapshot()
	var clean_colors: Dictionary = clean_presentation.get(&"colors", {}) as Dictionary
	var clean_roughness := float(
		((visual.get(&"_materials") as Dictionary).get(&"jersey") as StandardMaterial3D).roughness
	)
	for _frame: int in 360:
		visual.call(&"advance_equipment_wear_observation", {
			&"surface": &"LOOSE_DIRT",
			&"weather": &"CLEAR",
			&"grounded": true,
			&"dust_amount": 1.2,
			&"roost_intensity": 1.0,
			&"speed_mps": 23.0,
		}, 1.0 / 60.0)
	var dusty_presentation := bike.get_rider_equipment_presentation_snapshot()
	var dusty_overlays: Dictionary = dusty_presentation.get(&"overlays", {}) as Dictionary
	var dusty_colors: Dictionary = dusty_presentation.get(&"colors", {}) as Dictionary
	_check(
		bool(dusty_overlays.get(&"soil_visible", false))
		and dusty_colors.get(&"jersey", "") != clean_colors.get(&"jersey", ""),
		"Real rider renderer did not show dust tint and splatter"
	)

	bike.reset_equipment_wear()
	bike.apply_session_weather(&"STORM")
	for _frame: int in 240:
		visual.call(&"advance_equipment_wear_observation", {
			&"surface": &"WET",
			&"grounded": false,
			&"dust_amount": 0.0,
			&"roost_intensity": 0.0,
			&"speed_mps": 0.0,
		}, 1.0 / 60.0)
	var wet_presentation := bike.get_rider_equipment_presentation_snapshot()
	var wet_wear: Dictionary = wet_presentation.get(&"wear", {}) as Dictionary
	var wet_roughness := float(
		((visual.get(&"_materials") as Dictionary).get(&"jersey") as StandardMaterial3D).roughness
	)
	_check(
		float(wet_wear.get(&"wetness", 0.0)) >= 0.90
		and wet_roughness < clean_roughness,
		"Rain did not create a readable wet sheen on the real gear materials"
	)
	bike.set_surface(&"MUD")
	bike.reset_to_safe_position(DirtBikeController.RECOVERY_TIPPED)
	var crash_presentation := bike.get_rider_equipment_presentation_snapshot()
	var crash_overlays: Dictionary = crash_presentation.get(&"overlays", {}) as Dictionary
	var crash_before_respawn := bike.get_equipment_wear_snapshot()
	_check(
		bool(crash_overlays.get(&"soil_visible", false))
		and bool(crash_overlays.get(&"crash_visible", false))
		and StringName(crash_before_respawn.get(&"status", &"")) == &"CRASH_WORN",
		"Real renderer did not show both mud splatter and crash scratches"
	)
	bike.respawn_at(Transform3D.IDENTITY)
	_check(
		bike.get_equipment_wear_snapshot() == crash_before_respawn,
		"Respawn incorrectly washed away in-race environmental wear"
	)
	bike.reset_equipment_wear()
	var reset_presentation := bike.get_rider_equipment_presentation_snapshot()
	var reset_overlays: Dictionary = reset_presentation.get(&"overlays", {}) as Dictionary
	var reset_colors: Dictionary = reset_presentation.get(&"colors", {}) as Dictionary
	_check(
		StringName((reset_presentation.get(&"wear", {}) as Dictionary).get(&"status", &"")) == &"CLEAN"
		and not bool(reset_overlays.get(&"soil_visible", true))
		and not bool(reset_overlays.get(&"crash_visible", true))
		and reset_colors.get(&"jersey", "") == clean_colors.get(&"jersey", ""),
		"New-session reset did not restore clean gear exactly"
	)

	print("RIDER EQUIPMENT WEAR PROBE: dry=%.2f storm=%.2f/%.2f crash=%.2f overlays=soil+scratch passed=%s" % [
		float(dry.get(&"dry_dust", 0.0)),
		float(storm.get(&"wetness", 0.0)),
		float(storm.get(&"mud", 0.0)),
		float(crashed.get(&"crash_wear", 0.0)),
		str(_failures.is_empty()),
	])
	bike.queue_free()
	await get_tree().process_frame
	if _failures.is_empty():
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("RIDER EQUIPMENT WEAR PROBE: %s" % failure)
	get_tree().quit(1)


func _check(condition: bool, failure: String) -> void:
	if not condition:
		_failures.append(failure)
