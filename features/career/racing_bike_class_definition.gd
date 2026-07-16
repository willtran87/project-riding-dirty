extends Resource
class_name RacingBikeClassDefinition
## Serializable eligibility rules for a competitive motorcycle class.

@export var class_id: StringName = &"OPEN"
@export var display_name: String = "OPEN"
@export_multiline var description: String = "Any homologated bike may enter."
@export var min_displacement_cc: int = 0
@export var max_displacement_cc: int = 999
@export_range(0.0, 100.0, 0.1) var min_overall_rating: float = 0.0
@export_range(0.0, 100.0, 0.1) var max_overall_rating: float = 100.0
@export var required_reputation: int = 0
@export var sort_order: int = 0
@export var allowed_bike_ids: Array[StringName] = []


static func from_dictionary(data: Dictionary) -> RacingBikeClassDefinition:
	var definition := RacingBikeClassDefinition.new()
	definition.class_id = StringName(data.get(&"class_id", &"OPEN"))
	definition.display_name = str(data.get(&"display_name", String(definition.class_id)))
	definition.description = str(data.get(&"description", ""))
	definition.min_displacement_cc = maxi(int(data.get(&"min_displacement_cc", 0)), 0)
	definition.max_displacement_cc = maxi(int(data.get(&"max_displacement_cc", 999)), definition.min_displacement_cc)
	definition.min_overall_rating = clampf(float(data.get(&"min_overall_rating", 0.0)), 0.0, 100.0)
	definition.max_overall_rating = clampf(
		float(data.get(&"max_overall_rating", 100.0)),
		definition.min_overall_rating,
		100.0
	)
	definition.required_reputation = maxi(int(data.get(&"required_reputation", 0)), 0)
	definition.sort_order = int(data.get(&"sort_order", 0))
	definition.allowed_bike_ids = _string_name_array(data.get(&"allowed_bike_ids", []))
	return definition


func is_eligible(
	bike_id: StringName,
	displacement_cc: int,
	calculated_stats: Dictionary,
	reputation: int = 0
) -> bool:
	if reputation < required_reputation:
		return false
	if not allowed_bike_ids.is_empty() and bike_id not in allowed_bike_ids:
		return false
	if displacement_cc < min_displacement_cc or displacement_cc > max_displacement_cc:
		return false
	var overall := float(calculated_stats.get(&"overall", 0.0))
	return overall >= min_overall_rating and overall <= max_overall_rating


func to_dictionary() -> Dictionary:
	return {
		&"class_id": class_id,
		&"display_name": display_name,
		&"description": description,
		&"min_displacement_cc": min_displacement_cc,
		&"max_displacement_cc": max_displacement_cc,
		&"min_overall_rating": min_overall_rating,
		&"max_overall_rating": max_overall_rating,
		&"required_reputation": required_reputation,
		&"sort_order": sort_order,
		&"allowed_bike_ids": allowed_bike_ids.duplicate(),
	}


static func _string_name_array(value: Variant) -> Array[StringName]:
	var output: Array[StringName] = []
	if value is Array or value is PackedStringArray:
		for entry: Variant in value:
			output.append(StringName(entry))
	return output
