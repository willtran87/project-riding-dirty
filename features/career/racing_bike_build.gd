extends RefCounted
class_name RacingBikeBuild
## Serializable owned-bike setup. Stat calculation always starts from catalog base values.

const PERFORMANCE_STATS: Array[StringName] = [
	&"power", &"acceleration", &"top_speed", &"grip", &"braking",
	&"stability", &"suspension", &"air_control", &"durability",
]
const OVERALL_STATS: Array[StringName] = [
	&"power", &"acceleration", &"top_speed", &"grip",
	&"braking", &"stability", &"suspension", &"air_control",
]

var bike_id: StringName = &"TYKE_125"
var installed_parts: Dictionary = {}
var tune: RacingBikeTune = RacingBikeTune.new()
var condition: float = 1.0
var odometer_meters: float = 0.0
var livery_id: StringName = &"FACTORY"


static func from_dictionary(data: Dictionary) -> RacingBikeBuild:
	var build := RacingBikeBuild.new()
	build.bike_id = StringName(data.get(&"bike_id", &"TYKE_125"))
	build.installed_parts = _parts_dictionary(data.get(&"installed_parts", {}))
	build.tune = RacingBikeTune.from_dictionary(data.get(&"tune", {}) as Dictionary)
	build.condition = clampf(float(data.get(&"condition", 1.0)), 0.0, 1.0)
	build.odometer_meters = maxf(float(data.get(&"odometer_meters", 0.0)), 0.0)
	build.livery_id = StringName(data.get(&"livery_id", &"FACTORY"))
	return build


func install_part(catalog: RacingBikeCatalog, part_id: StringName) -> bool:
	if not catalog.is_part_compatible(part_id, bike_id):
		return false
	var part := catalog.get_part(part_id)
	var slot := StringName(part.get(&"slot", &""))
	if slot.is_empty():
		return false
	installed_parts[slot] = part_id
	return true


func uninstall_slot(slot: StringName) -> bool:
	if not installed_parts.has(slot):
		return false
	installed_parts.erase(slot)
	return true


func repair(amount: float = 1.0) -> float:
	condition = clampf(condition + maxf(amount, 0.0), 0.0, 1.0)
	return condition


func apply_wear(amount: float) -> float:
	condition = clampf(condition - maxf(amount, 0.0), 0.0, 1.0)
	return condition


func calculate_stats(catalog: RacingBikeCatalog) -> Dictionary:
	var bike := catalog.get_bike(bike_id)
	if bike.is_empty():
		return {}
	var base_value: Variant = bike.get(&"base_stats", {})
	if not base_value is Dictionary:
		return {}
	var stats := (base_value as Dictionary).duplicate(true)
	var slots := _sorted_string_names(installed_parts.keys())
	for slot: StringName in slots:
		var part_id := StringName(installed_parts.get(slot, &""))
		if not catalog.is_part_compatible(part_id, bike_id):
			continue
		var modifiers := catalog.get_part(part_id).get(&"modifiers", {}) as Dictionary
		_apply_modifiers(stats, modifiers)
	_apply_modifiers(stats, tune.get_stat_modifiers())

	var engine_health := lerpf(0.82, 1.0, condition)
	var chassis_health := lerpf(0.86, 1.0, condition)
	for stat: StringName in [&"power", &"acceleration", &"top_speed"]:
		stats[stat] = float(stats.get(stat, 0.0)) * engine_health
	for stat: StringName in [&"grip", &"braking", &"stability", &"suspension"]:
		stats[stat] = float(stats.get(stat, 0.0)) * chassis_health

	for stat: StringName in PERFORMANCE_STATS:
		stats[stat] = snappedf(clampf(float(stats.get(stat, 0.0)), 0.0, 100.0), 0.001)
	stats[&"mass_kg"] = snappedf(maxf(float(stats.get(&"mass_kg", 100.0)), 50.0), 0.001)
	var total := 0.0
	for stat: StringName in OVERALL_STATS:
		total += float(stats.get(stat, 0.0))
	stats[&"overall"] = snappedf(total / float(OVERALL_STATS.size()), 0.001)
	stats[&"condition"] = snappedf(condition, 0.001)
	return stats


static func runtime_factors(stats: Dictionary) -> Dictionary:
	## Single authority for translating catalog/build/tune stats into the physical
	## multipliers consumed by DirtBikeController and previewed by the Garage.
	var drive_rating := (float(stats.get(&"power", 52.0)) + float(stats.get(&"acceleration", 68.0))) * 0.5
	return {
		&"drive": lerpf(0.86, 1.22, clampf(inverse_lerp(45.0, 95.0, drive_rating), 0.0, 1.0)),
		&"speed": clampf(float(stats.get(&"top_speed", 56.0)) / 56.0, 0.92, 1.28),
		&"grip": clampf(float(stats.get(&"grip", 75.0)) / 75.0, 0.84, 1.18),
		&"brake": clampf(float(stats.get(&"braking", 70.0)) / 70.0, 0.86, 1.22),
		&"suspension": clampf(float(stats.get(&"suspension", 68.0)) / 68.0, 0.88, 1.18),
		&"stability": clampf(float(stats.get(&"stability", 73.0)) / 73.0, 0.86, 1.16),
		&"air": clampf(float(stats.get(&"air_control", 82.0)) / 82.0, 0.78, 1.2),
	}


static func runtime_tune_projection(tune_data: Dictionary) -> Dictionary:
	## Preserve the physical meaning of the six garage adjustments. Aggregate
	## ratings remain useful for matchmaking and preview bars, but damping and
	## brake bias must reach their actual solver parameters to feel different.
	var tune := RacingBikeTune.from_dictionary(tune_data)
	return {
		&"spring_compression_damping": 380.0 * (1.0 + tune.suspension_damping * 0.28),
		&"spring_rebound_damping": 2400.0 * (1.0 + tune.suspension_damping * 0.35),
		&"front_brake_bias": clampf(0.333333 + tune.brake_bias * 0.12, 0.20, 0.52),
		&"preload_factor": 1.0 + tune.jump_preload * 0.18,
		&"stiffness_factor": 1.0 + tune.suspension_stiffness * 0.16,
	}


static func runtime_projection(
	setup: StringName,
	stats: Dictionary,
	condition_percent: int,
	tune_data: Dictionary = {}
) -> Dictionary:
	var baseline := {
		&"engine_force": 1300.0,
		&"lateral_grip": 620.0,
		&"spring_stiffness": 20_000.0,
		&"maximum_speed_mps": 30.0,
	}
	match setup:
		&"TRAIL":
			baseline[&"engine_force"] = 1100.0
			baseline[&"lateral_grip"] = 700.0
			baseline[&"maximum_speed_mps"] = 27.5
		&"ATTACK":
			baseline[&"engine_force"] = 1400.0
			baseline[&"lateral_grip"] = 560.0
			baseline[&"maximum_speed_mps"] = 33.0
	var factors := runtime_factors(stats)
	var physical_tune := runtime_tune_projection(tune_data)
	var condition := clampf(float(condition_percent) / 100.0, 0.0, 1.0)
	return {
		&"engine_force": float(baseline[&"engine_force"]) * float(factors[&"drive"]) * lerpf(0.94, 1.0, condition),
		&"lateral_grip": float(baseline[&"lateral_grip"]) * float(factors[&"grip"]) * lerpf(0.96, 1.0, condition),
		&"spring_stiffness": float(baseline[&"spring_stiffness"]) * float(factors[&"suspension"]) * float(physical_tune[&"stiffness_factor"]),
		&"spring_compression_damping": physical_tune[&"spring_compression_damping"],
		&"spring_rebound_damping": physical_tune[&"spring_rebound_damping"],
		&"front_brake_bias": physical_tune[&"front_brake_bias"],
		&"preload_impulse": 230.0 * float(physical_tune[&"preload_factor"]) * lerpf(0.92, 1.13, clampf((float(factors[&"air"]) - 0.78) / 0.42, 0.0, 1.0)),
		&"maximum_speed_mps": float(baseline[&"maximum_speed_mps"]) * float(factors[&"speed"]) * lerpf(0.97, 1.0, condition),
		&"brake_force": 2880.0 * float(factors[&"brake"]),
		&"upright_strength": 10_000.0 * float(factors[&"stability"]),
		&"air_factor": float(factors[&"air"]),
		&"factors": factors.duplicate(true),
		&"physical_tune": physical_tune.duplicate(true),
	}


func eligible_classes(catalog: RacingBikeCatalog, reputation: int = 0) -> Array[StringName]:
	return catalog.get_eligible_classes(bike_id, calculate_stats(catalog), reputation)


func signature() -> String:
	var part_tokens := PackedStringArray()
	for slot: StringName in _sorted_string_names(installed_parts.keys()):
		part_tokens.append("%s=%s" % [String(slot), String(installed_parts.get(slot, &""))])
	return "%s|%s|%s|c%.3f|%s" % [
		String(bike_id), ",".join(part_tokens), tune.signature(), condition, String(livery_id),
	]


func to_dictionary() -> Dictionary:
	return {
		&"bike_id": bike_id,
		&"installed_parts": installed_parts.duplicate(true),
		&"tune": tune.to_dictionary(),
		&"condition": condition,
		&"odometer_meters": odometer_meters,
		&"livery_id": livery_id,
	}


static func _apply_modifiers(stats: Dictionary, modifiers: Dictionary) -> void:
	for raw_stat: Variant in modifiers:
		var stat := StringName(raw_stat)
		stats[stat] = float(stats.get(stat, 0.0)) + float(modifiers.get(raw_stat, 0.0))


static func _parts_dictionary(value: Variant) -> Dictionary:
	var output: Dictionary = {}
	if value is Dictionary:
		for raw_slot: Variant in value:
			var slot := StringName(raw_slot)
			var part_id := StringName((value as Dictionary).get(raw_slot, &""))
			if not slot.is_empty() and not part_id.is_empty():
				output[slot] = part_id
	return output


static func _sorted_string_names(values: Array) -> Array[StringName]:
	var output: Array[StringName] = []
	for value: Variant in values:
		output.append(StringName(value))
	output.sort_custom(func(first: StringName, second: StringName) -> bool: return String(first) < String(second))
	return output
