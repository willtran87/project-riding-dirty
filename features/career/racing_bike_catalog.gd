extends RefCounted
class_name RacingBikeCatalog
## Serializable definitions for bikes, upgrade parts, and homologated race classes.

const DEFAULT_BIKES: Dictionary = {
	&"TYKE_125": {
		&"bike_id": &"TYKE_125", &"display_name": "Tyke 125", &"manufacturer": "Redline",
		&"displacement_cc": 125, &"price": 0, &"required_reputation": 0, &"sort_order": 0,
		&"base_stats": {
			&"power": 52.0, &"acceleration": 68.0, &"top_speed": 56.0, &"grip": 75.0,
			&"braking": 70.0, &"stability": 73.0, &"suspension": 68.0,
			&"air_control": 82.0, &"durability": 80.0, &"mass_kg": 88.0,
		},
	},
	&"MESA_250": {
		&"bike_id": &"MESA_250", &"display_name": "Mesa 250", &"manufacturer": "Redline",
		&"displacement_cc": 250, &"price": 18_000, &"required_reputation": 80, &"sort_order": 1,
		&"base_stats": {
			&"power": 73.0, &"acceleration": 77.0, &"top_speed": 72.0, &"grip": 76.0,
			&"braking": 75.0, &"stability": 75.0, &"suspension": 77.0,
			&"air_control": 75.0, &"durability": 78.0, &"mass_kg": 101.0,
		},
	},
	&"ROOK_450": {
		&"bike_id": &"ROOK_450", &"display_name": "Rook 450", &"manufacturer": "Blackbird",
		&"displacement_cc": 450, &"price": 34_000, &"required_reputation": 220, &"sort_order": 2,
		&"base_stats": {
			&"power": 92.0, &"acceleration": 86.0, &"top_speed": 88.0, &"grip": 73.0,
			&"braking": 80.0, &"stability": 70.0, &"suspension": 82.0,
			&"air_control": 68.0, &"durability": 75.0, &"mass_kg": 111.0,
		},
	},
}

const DEFAULT_PARTS: Dictionary = {
	&"TORQUE_PIPE": {
		&"part_id": &"TORQUE_PIPE", &"display_name": "Torque Pipe", &"slot": &"ENGINE",
		&"price": 1_800, &"required_reputation": 10, &"compatible_bike_ids": [&"TYKE_125", &"MESA_250"],
		&"modifiers": {&"power": 4.0, &"acceleration": 3.0, &"top_speed": -1.0, &"durability": -1.0},
	},
	&"RACE_ECU": {
		&"part_id": &"RACE_ECU", &"display_name": "Race ECU", &"slot": &"ENGINE",
		&"price": 3_200, &"required_reputation": 90, &"compatible_bike_ids": [],
		&"modifiers": {&"power": 3.0, &"acceleration": 2.0, &"top_speed": 3.0, &"durability": -2.0},
	},
	&"HEAVY_FLYWHEEL": {
		&"part_id": &"HEAVY_FLYWHEEL", &"display_name": "Heavy Flywheel", &"slot": &"ENGINE",
		&"price": 2_400, &"required_reputation": 45, &"compatible_bike_ids": [],
		&"modifiers": {&"power": -1.0, &"acceleration": -1.0, &"grip": 2.5, &"stability": 3.0, &"mass_kg": 1.5},
	},
	&"HARDPACK_TIRES": {
		&"part_id": &"HARDPACK_TIRES", &"display_name": "Hardpack Tires", &"slot": &"TIRES",
		&"price": 1_250, &"required_reputation": 0, &"compatible_bike_ids": [],
		&"modifiers": {&"grip": 4.0, &"braking": 2.0, &"suspension": -1.0},
	},
	&"MUD_TIRES": {
		&"part_id": &"MUD_TIRES", &"display_name": "Deep-Lug Mud Tires", &"slot": &"TIRES",
		&"price": 1_500, &"required_reputation": 60, &"compatible_bike_ids": [],
		&"modifiers": {&"grip": 3.0, &"acceleration": 2.0, &"top_speed": -2.0, &"mass_kg": 0.8},
	},
	&"PROGRESSIVE_FORK": {
		&"part_id": &"PROGRESSIVE_FORK", &"display_name": "Progressive Fork", &"slot": &"SUSPENSION",
		&"price": 2_800, &"required_reputation": 35, &"compatible_bike_ids": [],
		&"modifiers": {&"suspension": 5.0, &"stability": 2.0, &"air_control": 1.5},
	},
	&"PLUSH_SHOCK": {
		&"part_id": &"PLUSH_SHOCK", &"display_name": "Plush Enduro Shock", &"slot": &"SUSPENSION",
		&"price": 3_100, &"required_reputation": 95, &"compatible_bike_ids": [],
		&"modifiers": {&"suspension": 6.0, &"grip": 2.0, &"stability": 1.0, &"air_control": -1.0},
	},
	&"WAVE_ROTOR": {
		&"part_id": &"WAVE_ROTOR", &"display_name": "Wave Rotor", &"slot": &"BRAKES",
		&"price": 1_700, &"required_reputation": 25, &"compatible_bike_ids": [],
		&"modifiers": {&"braking": 5.0, &"stability": 1.0, &"mass_kg": -0.4},
	},
	&"LIGHT_CHASSIS": {
		&"part_id": &"LIGHT_CHASSIS", &"display_name": "Lightweight Chassis", &"slot": &"CHASSIS",
		&"price": 4_200, &"required_reputation": 150, &"compatible_bike_ids": [],
		&"modifiers": {&"acceleration": 2.0, &"air_control": 4.0, &"stability": -2.5, &"durability": -3.0, &"mass_kg": -4.0},
	},
}

const DEFAULT_CLASSES: Dictionary = {
	&"LITE_125": {
		&"class_id": &"LITE_125", &"display_name": "125 LITE", &"description": "Lightweight development class.",
		&"min_displacement_cc": 0, &"max_displacement_cc": 150, &"min_overall_rating": 0.0,
		&"max_overall_rating": 82.0, &"required_reputation": 0, &"sort_order": 0,
		&"allowed_bike_ids": [&"TYKE_125"],
	},
	&"SPORT_250": {
		&"class_id": &"SPORT_250", &"display_name": "250 SPORT", &"description": "Balanced middleweight competition.",
		&"min_displacement_cc": 151, &"max_displacement_cc": 300, &"min_overall_rating": 0.0,
		&"max_overall_rating": 90.0, &"required_reputation": 80, &"sort_order": 1,
		&"allowed_bike_ids": [&"MESA_250"],
	},
	&"OPEN": {
		&"class_id": &"OPEN", &"display_name": "OPEN", &"description": "Unrestricted premier racing.",
		&"min_displacement_cc": 0, &"max_displacement_cc": 999, &"min_overall_rating": 0.0,
		&"max_overall_rating": 100.0, &"required_reputation": 160, &"sort_order": 2,
		&"allowed_bike_ids": [],
	},
}

var bikes: Dictionary = {}
var parts: Dictionary = {}
var bike_classes: Dictionary = {}


static func create_default() -> RacingBikeCatalog:
	var catalog := RacingBikeCatalog.new()
	catalog.configure(DEFAULT_BIKES, DEFAULT_PARTS, DEFAULT_CLASSES)
	return catalog


static func from_dictionary(data: Dictionary) -> RacingBikeCatalog:
	var catalog := RacingBikeCatalog.new()
	catalog.configure(
		data.get(&"bikes", DEFAULT_BIKES) as Dictionary,
		data.get(&"parts", DEFAULT_PARTS) as Dictionary,
		data.get(&"bike_classes", DEFAULT_CLASSES) as Dictionary
	)
	return catalog


func configure(bike_data: Dictionary, part_data: Dictionary, class_data: Dictionary) -> void:
	bikes = _normalize_definitions(bike_data, &"bike_id")
	parts = _normalize_definitions(part_data, &"part_id")
	bike_classes = _normalize_definitions(class_data, &"class_id")


func has_bike(bike_id: StringName) -> bool:
	return bikes.has(bike_id)


func has_part(part_id: StringName) -> bool:
	return parts.has(part_id)


func has_class(class_id: StringName) -> bool:
	return bike_classes.has(class_id)


func get_bike(bike_id: StringName) -> Dictionary:
	return (bikes.get(bike_id, {}) as Dictionary).duplicate(true)


func get_part(part_id: StringName) -> Dictionary:
	return (parts.get(part_id, {}) as Dictionary).duplicate(true)


func get_class_definition(class_id: StringName) -> RacingBikeClassDefinition:
	var data := bike_classes.get(class_id, {}) as Dictionary
	return RacingBikeClassDefinition.from_dictionary(data)


func get_bikes(reputation: int = 0, include_locked: bool = true) -> Array[Dictionary]:
	var output := _definition_values(bikes)
	if not include_locked:
		output = output.filter(func(entry: Dictionary) -> bool: return reputation >= int(entry.get(&"required_reputation", 0)))
	output.sort_custom(_definition_precedes)
	return output


func get_parts_for_slot(
	slot: StringName,
	bike_id: StringName = &"",
	reputation: int = 0,
	include_locked: bool = true
) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for entry: Dictionary in _definition_values(parts):
		if StringName(entry.get(&"slot", &"")) != slot:
			continue
		if not bike_id.is_empty() and not is_part_compatible(StringName(entry.get(&"part_id", &"")), bike_id):
			continue
		if not include_locked and reputation < int(entry.get(&"required_reputation", 0)):
			continue
		output.append(entry)
	output.sort_custom(_definition_precedes)
	return output


func is_part_compatible(part_id: StringName, bike_id: StringName) -> bool:
	if not has_part(part_id) or not has_bike(bike_id):
		return false
	var compatible := _string_name_array(get_part(part_id).get(&"compatible_bike_ids", []))
	return compatible.is_empty() or bike_id in compatible


func get_eligible_classes(
	bike_id: StringName,
	calculated_stats: Dictionary,
	reputation: int = 0
) -> Array[StringName]:
	if not has_bike(bike_id):
		return []
	var bike := get_bike(bike_id)
	var displacement := int(bike.get(&"displacement_cc", 0))
	var definitions := _definition_values(bike_classes)
	definitions.sort_custom(_definition_precedes)
	var output: Array[StringName] = []
	for data: Dictionary in definitions:
		var definition := RacingBikeClassDefinition.from_dictionary(data)
		if definition.is_eligible(bike_id, displacement, calculated_stats, reputation):
			output.append(definition.class_id)
	return output


func to_dictionary() -> Dictionary:
	return {
		&"bikes": bikes.duplicate(true),
		&"parts": parts.duplicate(true),
		&"bike_classes": bike_classes.duplicate(true),
	}


static func _normalize_definitions(source: Dictionary, id_key: StringName) -> Dictionary:
	var output: Dictionary = {}
	for raw_key: Variant in source:
		var entry_value: Variant = source.get(raw_key, {})
		if not entry_value is Dictionary:
			continue
		var entry := (entry_value as Dictionary).duplicate(true)
		var definition_id := StringName(entry.get(id_key, raw_key))
		if definition_id.is_empty():
			continue
		entry[id_key] = definition_id
		output[definition_id] = entry
	return output


static func _definition_values(source: Dictionary) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for entry: Variant in source.values():
		if entry is Dictionary:
			output.append((entry as Dictionary).duplicate(true))
	return output


static func _definition_precedes(first: Dictionary, second: Dictionary) -> bool:
	var first_order := int(first.get(&"sort_order", first.get(&"required_reputation", 0)))
	var second_order := int(second.get(&"sort_order", second.get(&"required_reputation", 0)))
	if first_order != second_order:
		return first_order < second_order
	var first_name := str(first.get(&"display_name", first.get(&"bike_id", first.get(&"part_id", &""))))
	var second_name := str(second.get(&"display_name", second.get(&"bike_id", second.get(&"part_id", &""))))
	return first_name.naturalnocasecmp_to(second_name) < 0


static func _string_name_array(value: Variant) -> Array[StringName]:
	var output: Array[StringName] = []
	if value is Array or value is PackedStringArray:
		for entry: Variant in value:
			output.append(StringName(entry))
	return output
