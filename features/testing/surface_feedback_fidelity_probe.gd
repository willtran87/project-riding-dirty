extends Node
## Cross-system proof that sand and grass are authored surfaces with unique
## handling, session balance, roost color, equipment wear, and baked audio.

const BIKE_CONTROLLER := preload("res://entities/bike/bike_controller.gd")
const BIKE_VISUAL := preload("res://entities/bike/bike_visual.gd")
const ENGINE_AUDIO := preload("res://entities/bike/engine_audio.gd")
const WEAR := preload("res://features/race/rider_equipment_wear.gd")
const QUARRY_SCENE := preload("res://levels/quarry/quarry.tscn")
const PINE_SCENE := preload("res://levels/pine_ridge/pine_ridge.tscn")

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_validate_physics()
	_validate_audio()
	_validate_visual_feedback()
	_validate_wear()
	await _validate_authored_terrain()
	print(
		"SURFACE FEEDBACK FIDELITY PROBE: physical=%d audio=%d sand=QuarryFreestylePad grass=PineTerrain passed=%s"
		% [
			BIKE_CONTROLLER.get_surface_types().size(),
			ENGINE_AUDIO.get_surface_audio_keys().size(),
			str(_failures.is_empty()),
		]
	)
	if _failures.is_empty():
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("SURFACE FEEDBACK FIDELITY PROBE: %s" % failure)
	get_tree().quit(1)


func _validate_physics() -> void:
	var surfaces: Array[StringName] = BIKE_CONTROLLER.get_surface_types()
	var signatures := {}
	_check(surfaces.size() == 9, "The physical surface catalog does not contain nine identities")
	_check(&"SAND" in surfaces and &"GRASS" in surfaces, "Sand or grass is absent from physical authority")
	for surface: StringName in surfaces:
		var profile: Dictionary = BIKE_CONTROLLER.surface_profile(surface)
		var signature := "%.3f|%.3f|%.3f|%.3f" % [
			float(profile.get(&"friction", 0.0)),
			float(profile.get(&"drag", 0.0)),
			float(profile.get(&"roughness", 0.0)),
			float(profile.get(&"roost", 0.0)),
		]
		_check(not signatures.has(signature), "%s duplicates another complete physical profile" % String(surface))
		signatures[signature] = surface
	var loose := BIKE_CONTROLLER.surface_profile(&"LOOSE_DIRT")
	var sand := BIKE_CONTROLLER.surface_profile(&"SAND")
	var packed := BIKE_CONTROLLER.surface_profile(&"PACKED")
	var grass := BIKE_CONTROLLER.surface_profile(&"GRASS")
	_check(
		BIKE_CONTROLLER.canonical_surface(&"DUNES") == &"SAND"
		and BIKE_CONTROLLER.canonical_surface(&"TURF") == &"GRASS",
		"Authored sand or grass aliases do not preserve their identity"
	)
	_check(sand != loose and grass != packed, "Sand or grass still collapses to its legacy fallback profile")
	_check(
		float(sand[&"friction"]) < float(grass[&"friction"])
		and float(sand[&"drag"]) > float(grass[&"drag"])
		and float(sand[&"roost"]) > float(grass[&"roost"]) * 3.0,
		"Sand is not meaningfully looser, slower, and more expressive than grass"
	)
	_check(
		BIKE_CONTROLLER.session_surface_grip_multiplier(&"SAND")
		< BIKE_CONTROLLER.session_surface_grip_multiplier(&"GRASS")
		and BIKE_CONTROLLER.session_surface_grip_multiplier(&"GRASS") < 1.0,
		"Session sand and grass modifiers have no distinct bounded grip cost"
	)


func _validate_audio() -> void:
	var audio_keys: Array = ENGINE_AUDIO.get_surface_audio_keys()
	var hashes := {}
	_check(audio_keys.size() == 7, "Surface audio does not expose all seven production contact loops")
	_check(&"SAND" in audio_keys and &"GRASS" in audio_keys, "Sand or grass has no baked contact loop")
	_check(
		ENGINE_AUDIO.normalize_surface_audio_key(&"SAND") == &"SAND"
		and ENGINE_AUDIO.normalize_surface_audio_key(&"GRASS") == &"GRASS",
		"Sand or grass audio aliases collapse into another loop"
	)
	for surface: StringName in audio_keys:
		var contract: Dictionary = ENGINE_AUDIO.get_baked_surface_audio_contract(surface)
		var fingerprint := String(contract.get(&"sha256", ""))
		_check(int(contract.get(&"sample_bytes", 0)) >= 20_000, "%s contact loop is empty or truncated" % String(surface))
		_check(int(contract.get(&"mix_rate", 0)) == 22_050, "%s contact loop has an invalid sample rate" % String(surface))
		_check(
			int(contract.get(&"loop_end", 0)) > int(contract.get(&"loop_begin", -1)),
			"%s contact loop has invalid seamless-loop bounds" % String(surface)
		)
		_check(fingerprint.length() == 64, "%s contact loop has no SHA-256 identity" % String(surface))
		_check(not hashes.has(fingerprint), "%s contact loop duplicates another baked waveform" % String(surface))
		hashes[fingerprint] = surface


func _validate_visual_feedback() -> void:
	var sand_tint := BIKE_VISUAL.surface_feedback_tint(&"SAND")
	var grass_tint := BIKE_VISUAL.surface_feedback_tint(&"GRASS")
	var loose_tint := BIKE_VISUAL.surface_feedback_tint(&"LOOSE_DIRT")
	var packed_tint := BIKE_VISUAL.surface_feedback_tint(&"PACKED")
	_check(sand_tint != loose_tint, "Sand roost uses loose-dirt color")
	_check(grass_tint != packed_tint, "Grass contact feedback uses packed-ground color")
	_check(
		sand_tint.r > sand_tint.g and sand_tint.g > sand_tint.b,
		"Sand roost is not a readable warm mineral tint"
	)
	_check(
		grass_tint.g > grass_tint.r and grass_tint.g > grass_tint.b,
		"Grass contact feedback is not a readable vegetation tint"
	)


func _validate_wear() -> void:
	var sand := WEAR.clean_state(&"CLEAR")
	var grass := WEAR.clean_state(&"CLEAR")
	var observation := {
		&"weather": &"CLEAR",
		&"grounded": true,
		&"dust_amount": 1.0,
		&"roost_intensity": 1.0,
		&"speed_mps": 22.0,
	}
	for _frame: int in 360:
		observation[&"surface"] = &"SAND"
		sand = WEAR.advance(sand, observation, 1.0 / 60.0)
		observation[&"surface"] = &"GRASS"
		grass = WEAR.advance(grass, observation, 1.0 / 60.0)
	_check(StringName(sand.get(&"surface", &"")) == &"SAND", "Equipment wear sanitizes sand away")
	_check(StringName(grass.get(&"surface", &"")) == &"GRASS", "Equipment wear sanitizes grass away")
	_check(
		float(sand.get(&"dry_dust", 0.0)) > float(grass.get(&"dry_dust", 0.0)) * 4.0,
		"Sand and grass do not leave meaningfully different dry equipment wear"
	)


func _validate_authored_terrain() -> void:
	var quarry := QUARRY_SCENE.instantiate() as Node3D
	add_child(quarry)
	await get_tree().process_frame
	var sand_pad := quarry.find_child("QuarryFreestylePad", true, false) as CollisionObject3D
	_check(sand_pad != null, "Quarry Freestyle has no authored contact pad")
	if sand_pad != null:
		_check(StringName(sand_pad.get_meta(&"surface", &"")) == &"SAND", "Quarry Freestyle pad is not tagged SAND")
		_check(
			is_equal_approx(float(sand_pad.get_meta(&"roughness", 0.0)), 0.58)
			and is_equal_approx(float(sand_pad.get_meta(&"roost", 0.0)), 1.62),
			"Quarry Freestyle pad metadata disagrees with the sand physics profile"
		)
	var quarry_materials := quarry.get("_materials") as Dictionary
	var sand_material := quarry_materials.get(&"sand") as StandardMaterial3D
	var sand_color := _sample_material_color(sand_material)
	_check(
		sand_material != null
		and sand_color.r > sand_color.g
		and sand_color.g > sand_color.b,
		"Quarry sand has no authored warm mineral material"
	)
	quarry.queue_free()
	await get_tree().process_frame

	var pine := PINE_SCENE.instantiate() as Node3D
	add_child(pine)
	await get_tree().process_frame
	var terrain_body := pine.find_child("GeneratedPineTerrainCollision", true, false) as CollisionObject3D
	var catch_floor := pine.find_child("PineCatchFloor", true, false) as CollisionObject3D
	_check(terrain_body != null and catch_floor != null, "Pine Ridge is missing continuous off-trail collision")
	if terrain_body != null:
		_check(StringName(terrain_body.get_meta(&"surface", &"")) == &"GRASS", "Pine generated terrain is not tagged GRASS")
	if catch_floor != null:
		_check(StringName(catch_floor.get_meta(&"surface", &"")) == &"GRASS", "Pine catch floor is not tagged GRASS")
	var pine_materials := pine.get("_materials") as Dictionary
	var terrain_material := pine_materials.get(&"terrain") as StandardMaterial3D
	var terrain_color := _sample_material_color(terrain_material)
	_check(
		terrain_material != null
		and terrain_color.g > terrain_color.r
		and terrain_color.g >= terrain_color.b,
		"Pine grass terrain has no authored forest-green material"
	)
	pine.queue_free()
	await get_tree().process_frame


func _sample_material_color(material: StandardMaterial3D) -> Color:
	if material == null:
		return Color.BLACK
	if material.albedo_texture == null:
		return material.albedo_color
	var image := material.albedo_texture.get_image()
	if image == null or image.is_empty():
		return material.albedo_color
	var sum := Color(0.0, 0.0, 0.0, 0.0)
	var sample_count := 0
	for y_step: int in 8:
		for x_step: int in 8:
			var x := mini(image.get_width() - 1, x_step * image.get_width() / 8)
			var y := mini(image.get_height() - 1, y_step * image.get_height() / 8)
			sum += image.get_pixel(x, y)
			sample_count += 1
	return sum / float(maxi(sample_count, 1))


func _check(condition: bool, failure: String) -> void:
	if not condition:
		_failures.append(failure)
