extends RefCounted
class_name RacingChampionshipService
## Serializable championship calendar, results, points, and deterministic countback standings.

const DEFAULT_POINTS: Array[int] = [25, 22, 20, 18, 16, 15, 14, 13, 12, 11, 10, 9]
const DEFAULT_CALENDAR: Array[Dictionary] = [
	{&"round_id": &"MESA_OPENER", &"event_id": &"MESA_MX", &"track_id": &"MESA_MX", &"display_name": "Red Mesa Opener"},
	{&"round_id": &"QUARRY_SPRINT", &"event_id": &"CIRCUIT", &"track_id": &"QUARRY", &"display_name": "Quarry Trail Sprint"},
	{&"round_id": &"PINE_ENDURO", &"event_id": &"PINE_ENDURO", &"track_id": &"PINE", &"display_name": "Pine Ridge Enduro"},
	{&"round_id": &"MESA_RIVAL", &"event_id": &"MESA_RIVAL", &"track_id": &"MESA_MX", &"display_name": "Red Mesa Rival Round"},
	{&"round_id": &"PINE_STORM", &"event_id": &"PINE_WET", &"track_id": &"PINE", &"display_name": "Pine Storm Stage"},
	{&"round_id": &"MESA_FINALE", &"event_id": &"MESA_ENDURANCE", &"track_id": &"MESA_MX", &"display_name": "Red Mesa Finale"},
]

var championship_id: StringName = &"DIRT_TOUR"
var display_name: String = "DIRT TOUR"
var season_number: int = 1
var calendar: Array[Dictionary] = []
var points_table: PackedInt32Array = PackedInt32Array(DEFAULT_POINTS)
var round_results: Dictionary = {}


static func create_default() -> RacingChampionshipService:
	var service := RacingChampionshipService.new()
	service.configure(&"DIRT_TOUR", "DIRT TOUR", DEFAULT_CALENDAR, PackedInt32Array(DEFAULT_POINTS), 1)
	return service


static func from_dictionary(data: Dictionary) -> RacingChampionshipService:
	var service := RacingChampionshipService.new()
	var calendar_data := _dictionary_array(data.get(&"calendar", DEFAULT_CALENDAR))
	var serialized_points := _int_array(data.get(&"points_table", DEFAULT_POINTS))
	service.configure(
		StringName(data.get(&"championship_id", &"DIRT_TOUR")),
		str(data.get(&"display_name", "DIRT TOUR")),
		calendar_data,
		serialized_points,
		maxi(int(data.get(&"season_number", 1)), 1)
	)
	var serialized_results := data.get(&"round_results", {}) as Dictionary
	for raw_round_id: Variant in serialized_results:
		var round_id := StringName(raw_round_id)
		var classification := _dictionary_array(serialized_results.get(raw_round_id, []))
		service.record_round_result(round_id, classification)
	return service


func configure(
	new_championship_id: StringName,
	new_display_name: String,
	calendar_data: Array[Dictionary],
	custom_points: PackedInt32Array = PackedInt32Array(),
	new_season_number: int = 1
) -> void:
	championship_id = new_championship_id if not new_championship_id.is_empty() else &"DIRT_TOUR"
	display_name = new_display_name.strip_edges() if not new_display_name.strip_edges().is_empty() else "DIRT TOUR"
	season_number = maxi(new_season_number, 1)
	points_table = custom_points.duplicate() if not custom_points.is_empty() else PackedInt32Array(DEFAULT_POINTS)
	calendar.clear()
	round_results.clear()
	var seen_rounds: Dictionary = {}
	for source_index: int in calendar_data.size():
		var entry := calendar_data[source_index].duplicate(true)
		var round_id := StringName(entry.get(&"round_id", "ROUND_%02d" % (source_index + 1)))
		if round_id.is_empty() or seen_rounds.has(round_id):
			continue
		seen_rounds[round_id] = true
		entry[&"round_id"] = round_id
		entry[&"round_number"] = calendar.size() + 1
		entry[&"event_id"] = StringName(entry.get(&"event_id", round_id))
		entry[&"track_id"] = StringName(entry.get(&"track_id", &"QUARRY"))
		entry[&"display_name"] = str(entry.get(&"display_name", String(round_id).capitalize()))
		calendar.append(entry)


func record_round_result(round_id: StringName, classification: Array[Dictionary]) -> bool:
	if not has_round(round_id):
		return false
	var normalized := _normalize_classification(classification)
	if normalized.is_empty():
		return false
	# Replacing the round is intentional: imports and retries never double-award points.
	round_results[round_id] = normalized
	return true


func clear_round_result(round_id: StringName) -> bool:
	if not round_results.has(round_id):
		return false
	round_results.erase(round_id)
	return true


func has_round(round_id: StringName) -> bool:
	return get_round_index(round_id) >= 0


func get_round_index(round_id: StringName) -> int:
	for index: int in calendar.size():
		if StringName(calendar[index].get(&"round_id", &"")) == round_id:
			return index
	return -1


func get_points_for_position(position: int) -> int:
	return points_table[position - 1] if position >= 1 and position <= points_table.size() else 0


func get_calendar() -> Array[Dictionary]:
	var snapshot: Array[Dictionary] = []
	for entry: Dictionary in calendar:
		var item := entry.duplicate(true)
		var round_id := StringName(item.get(&"round_id", &""))
		item[&"completed"] = round_results.has(round_id)
		item[&"status"] = &"COMPLETE" if round_results.has(round_id) else &"UPCOMING"
		snapshot.append(item)
	return snapshot


func get_round_result(round_id: StringName) -> Array[Dictionary]:
	return _dictionary_array(round_results.get(round_id, []))


func get_next_round() -> Dictionary:
	for entry: Dictionary in calendar:
		var round_id := StringName(entry.get(&"round_id", &""))
		if not round_results.has(round_id):
			return entry.duplicate(true)
	return {}


func completed_round_count() -> int:
	var count := 0
	for entry: Dictionary in calendar:
		if round_results.has(StringName(entry.get(&"round_id", &""))):
			count += 1
	return count


func is_complete() -> bool:
	return not calendar.is_empty() and completed_round_count() == calendar.size()


func can_start_next_season() -> bool:
	return is_complete()


func start_next_season() -> bool:
	# Preserve the calendar and scoring contract while beginning a clean, numbered
	# season. Requiring a completed championship prevents accidental progress loss.
	if not can_start_next_season():
		return false
	season_number += 1
	round_results.clear()
	return true


func get_standings() -> Array[Dictionary]:
	var records: Dictionary = {}
	for round_index: int in calendar.size():
		var round_id := StringName(calendar[round_index].get(&"round_id", &""))
		if not round_results.has(round_id):
			continue
		var classification := round_results.get(round_id, []) as Array
		for raw_entry: Variant in classification:
			if not raw_entry is Dictionary:
				continue
			var entry := raw_entry as Dictionary
			var rider_id := StringName(entry.get(&"rider_id", &""))
			if rider_id.is_empty():
				continue
			if not records.has(rider_id):
				records[rider_id] = _new_standing_record(rider_id, str(entry.get(&"display_name", String(rider_id))))
			var record := records[rider_id] as Dictionary
			var position := maxi(int(entry.get(&"position", 999)), 1)
			var status := StringName(entry.get(&"status", &"FINISHED"))
			var classified := status == &"FINISHED" or status == &"CLASSIFIED"
			var awarded_points := get_points_for_position(position) if classified else 0
			awarded_points += maxi(int(entry.get(&"bonus_points", 0)), 0)
			record[&"points"] = int(record.get(&"points", 0)) + awarded_points
			record[&"starts"] = int(record.get(&"starts", 0)) + 1
			record[&"wins"] = int(record.get(&"wins", 0)) + (1 if classified and position == 1 else 0)
			record[&"podiums"] = int(record.get(&"podiums", 0)) + (1 if classified and position <= 3 else 0)
			record[&"fastest_laps"] = int(record.get(&"fastest_laps", 0)) + (1 if bool(entry.get(&"fastest_lap", false)) else 0)
			record[&"holeshots"] = int(record.get(&"holeshots", 0)) + (1 if bool(entry.get(&"holeshot", false)) else 0)
			var countback_position := position if classified else 999
			var finish_counts := record.get(&"finish_counts", {}) as Dictionary
			finish_counts[countback_position] = int(finish_counts.get(countback_position, 0)) + 1
			record[&"finish_counts"] = finish_counts
			var finishes := record.get(&"finishes", []) as Array
			finishes.append(countback_position)
			record[&"finishes"] = finishes
			record[&"best_finish"] = mini(int(record.get(&"best_finish", 999)), countback_position)
			record[&"last_round_index"] = round_index
			record[&"last_finish"] = countback_position
			records[rider_id] = record

	var standings: Array[Dictionary] = []
	for raw_record: Variant in records.values():
		standings.append((raw_record as Dictionary).duplicate(true))
	standings.sort_custom(_standing_precedes)
	for index: int in standings.size():
		standings[index][&"championship_position"] = index + 1
	return standings


func get_champion() -> Dictionary:
	if not is_complete():
		return {}
	var standings := get_standings()
	return standings[0].duplicate(true) if not standings.is_empty() else {}


func to_dictionary() -> Dictionary:
	return {
		&"championship_id": championship_id,
		&"display_name": display_name,
		&"season_number": season_number,
		&"calendar": calendar.duplicate(true),
		&"points_table": points_table.duplicate(),
		&"round_results": round_results.duplicate(true),
	}


func _normalize_classification(classification: Array[Dictionary]) -> Array[Dictionary]:
	var normalized: Array[Dictionary] = []
	var seen_riders: Dictionary = {}
	for source_index: int in classification.size():
		var entry := classification[source_index].duplicate(true)
		var rider_id := StringName(entry.get(&"rider_id", &""))
		if rider_id.is_empty() or seen_riders.has(rider_id):
			continue
		seen_riders[rider_id] = true
		entry[&"rider_id"] = rider_id
		entry[&"display_name"] = str(entry.get(&"display_name", String(rider_id)))
		entry[&"position"] = maxi(int(entry.get(&"position", source_index + 1)), 1)
		entry[&"status"] = StringName(entry.get(&"status", &"FINISHED"))
		normalized.append(entry)
	normalized.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		var first_position := int(first.get(&"position", 999))
		var second_position := int(second.get(&"position", 999))
		if first_position != second_position:
			return first_position < second_position
		return String(first.get(&"rider_id", &"")).naturalnocasecmp_to(String(second.get(&"rider_id", &""))) < 0
	)
	for index: int in normalized.size():
		normalized[index][&"position"] = index + 1
	return normalized


func _standing_precedes(first: Dictionary, second: Dictionary) -> bool:
	var first_points := int(first.get(&"points", 0))
	var second_points := int(second.get(&"points", 0))
	if first_points != second_points:
		return first_points > second_points
	var first_counts := first.get(&"finish_counts", {}) as Dictionary
	var second_counts := second.get(&"finish_counts", {}) as Dictionary
	var countback_limit := maxi(points_table.size(), calendar.size()) + 2
	for position: int in range(1, countback_limit):
		var first_count := int(first_counts.get(position, 0))
		var second_count := int(second_counts.get(position, 0))
		if first_count != second_count:
			return first_count > second_count
	var first_finishes := first.get(&"finishes", []) as Array
	var second_finishes := second.get(&"finishes", []) as Array
	for offset: int in mini(first_finishes.size(), second_finishes.size()):
		var first_recent := int(first_finishes[first_finishes.size() - 1 - offset])
		var second_recent := int(second_finishes[second_finishes.size() - 1 - offset])
		if first_recent != second_recent:
			return first_recent < second_recent
	var first_fastest := int(first.get(&"fastest_laps", 0))
	var second_fastest := int(second.get(&"fastest_laps", 0))
	if first_fastest != second_fastest:
		return first_fastest > second_fastest
	return String(first.get(&"rider_id", &"")).naturalnocasecmp_to(String(second.get(&"rider_id", &""))) < 0


static func _new_standing_record(rider_id: StringName, rider_name: String) -> Dictionary:
	return {
		&"rider_id": rider_id,
		&"display_name": rider_name,
		&"championship_position": 0,
		&"points": 0,
		&"starts": 0,
		&"wins": 0,
		&"podiums": 0,
		&"fastest_laps": 0,
		&"holeshots": 0,
		&"best_finish": 999,
		&"last_round_index": -1,
		&"last_finish": 999,
		&"finish_counts": {},
		&"finishes": [],
	}


static func _dictionary_array(value: Variant) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	if value is Array:
		for entry: Variant in value:
			if entry is Dictionary:
				output.append((entry as Dictionary).duplicate(true))
	return output


static func _int_array(value: Variant) -> PackedInt32Array:
	if value is PackedInt32Array:
		return (value as PackedInt32Array).duplicate()
	var output := PackedInt32Array()
	if value is Array:
		for entry: Variant in value:
			output.append(maxi(int(entry), 0))
	return output
