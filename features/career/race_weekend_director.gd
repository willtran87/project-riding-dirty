extends RefCounted
class_name RaceWeekendDirector
## Pure race-weekend state machine: practice, qualifying, heat, LCQ, main, and results.

signal phase_changed(previous_phase: StringName, current_phase: StringName)
signal session_completed(phase: StringName, classification: Array[Dictionary])

const IDLE: StringName = &"IDLE"
const PRACTICE: StringName = &"PRACTICE"
const QUALIFYING: StringName = &"QUALIFYING"
const HEAT: StringName = &"HEAT"
const LCQ: StringName = &"LCQ"
const MAIN: StringName = &"MAIN"
const RESULTS: StringName = &"RESULTS"
const SESSION_ORDER: Array[StringName] = [PRACTICE, QUALIFYING, HEAT, LCQ, MAIN, RESULTS]
const PLAYER_ID: StringName = &"PLAYER"
const QUALIFYING_REFERENCE_USEC: int = 140_000_000
const AI_LAP_REFERENCE_USEC: int = 72_000_000

var weekend_id: StringName = &"RED_MESA_OPEN"
var event_id: StringName = &"MESA_MX"
var display_name: String = "RED MESA OPEN"
var entrants: Array[Dictionary] = []
var heat_transfer_count: int = 6
var lcq_transfer_count: int = 4
var main_field_limit: int = 10
var current_session_index: int = -1
var session_results: Dictionary = {}
var qualifying_order: Array[StringName] = []
var heat_qualifiers: Array[StringName] = []
var lcq_candidates: Array[StringName] = []
var lcq_qualifiers: Array[StringName] = []
var main_grid: Array[StringName] = []


static func create(config: Dictionary) -> RaceWeekendDirector:
	var director := RaceWeekendDirector.new()
	director.configure(config)
	return director


static func from_dictionary(data: Dictionary) -> RaceWeekendDirector:
	var director := RaceWeekendDirector.new()
	director.configure(data)
	director.current_session_index = clampi(int(data.get(&"current_session_index", -1)), -1, SESSION_ORDER.size() - 1)
	director.session_results = (data.get(&"session_results", {}) as Dictionary).duplicate(true)
	director.qualifying_order = _string_name_array(data.get(&"qualifying_order", []))
	director.heat_qualifiers = _string_name_array(data.get(&"heat_qualifiers", []))
	director.lcq_candidates = _string_name_array(data.get(&"lcq_candidates", []))
	director.lcq_qualifiers = _string_name_array(data.get(&"lcq_qualifiers", []))
	director.main_grid = _string_name_array(data.get(&"main_grid", []))
	director._normalize_player_phase_after_restore()
	return director


func configure(config: Dictionary) -> void:
	weekend_id = StringName(config.get(&"weekend_id", &"RED_MESA_OPEN"))
	event_id = StringName(config.get(&"event_id", &"MESA_MX"))
	display_name = str(config.get(&"display_name", "RED MESA OPEN"))
	entrants = _normalize_entrants(_dictionary_array(config.get(&"entrants", [])))
	heat_transfer_count = clampi(int(config.get(&"heat_transfer_count", 6)), 0, entrants.size())
	lcq_transfer_count = clampi(int(config.get(&"lcq_transfer_count", 4)), 0, entrants.size())
	main_field_limit = clampi(int(config.get(&"main_field_limit", 10)), 1, maxi(entrants.size(), 1))
	reset()


func reset() -> void:
	current_session_index = -1
	session_results.clear()
	qualifying_order.clear()
	heat_qualifiers.clear()
	lcq_candidates.clear()
	lcq_qualifiers.clear()
	main_grid.clear()


func start_weekend() -> Dictionary:
	if entrants.is_empty():
		return {}
	if current_session_index < 0:
		_set_session_index(0)
	return get_current_session()


func get_current_phase() -> StringName:
	return SESSION_ORDER[current_session_index] if current_session_index >= 0 and current_session_index < SESSION_ORDER.size() else IDLE


func get_current_session() -> Dictionary:
	var phase := get_current_phase()
	if phase == IDLE:
		return {}
	return {
		&"weekend_id": weekend_id,
		&"event_id": event_id,
		&"phase": phase,
		&"session_number": current_session_index + 1,
		&"session_count": SESSION_ORDER.size() - 1,
		&"entrant_ids": get_session_entrant_ids(phase),
		&"gate_order": get_gate_order(),
		&"is_terminal": phase == RESULTS,
	}


func get_session_entrant_ids(phase: StringName) -> Array[StringName]:
	match phase:
		PRACTICE, QUALIFYING:
			return _all_entrant_ids()
		HEAT:
			return qualifying_order.duplicate() if not qualifying_order.is_empty() else _all_entrant_ids()
		LCQ:
			return lcq_candidates.duplicate()
		MAIN:
			return main_grid.duplicate()
		_:
			return []


func prepare_session_classification(phase: StringName, classification: Array[Dictionary]) -> Array[Dictionary]:
	var expected_riders := get_session_entrant_ids(phase)
	if phase == QUALIFYING and _has_player_entrant():
		return _build_deterministic_qualifying_classification(classification, expected_riders)
	return _normalize_classification(classification, expected_riders)


func submit_session_result(
		classification: Array[Dictionary],
		expected_phase: StringName = IDLE
	) -> bool:
	var phase := get_current_phase()
	if (
			phase == IDLE
			or phase == RESULTS
			or session_results.has(phase)
			or (expected_phase != IDLE and expected_phase != phase)
		):
		return false
	var expected_riders := get_session_entrant_ids(phase)
	var normalized := prepare_session_classification(phase, classification)
	if expected_riders.size() > 0 and normalized.is_empty():
		return false
	if not _store_session_result(phase, normalized):
		return false
	var next_index := mini(current_session_index + 1, SESSION_ORDER.size() - 1)
	match phase:
		QUALIFYING:
			qualifying_order = _rider_ids_from(normalized)
		HEAT:
			_resolve_heat(normalized)
			if _has_player_entrant() and heat_qualifiers.has(PLAYER_ID):
				_complete_ai_only_lcq()
				next_index = SESSION_ORDER.find(MAIN)
		LCQ:
			_resolve_lcq(normalized)
			if _has_player_entrant() and not main_grid.has(PLAYER_ID):
				_complete_ai_only_main()
				next_index = SESSION_ORDER.find(RESULTS)
		MAIN:
			pass
	_set_session_index(next_index)
	return true


func get_session_result(phase: StringName) -> Array[Dictionary]:
	return _dictionary_array(session_results.get(phase, []))


func get_gate_order() -> Array[StringName]:
	if get_current_phase() == MAIN and not main_grid.is_empty():
		return main_grid.duplicate()
	if not qualifying_order.is_empty():
		return qualifying_order.duplicate()
	return _all_entrant_ids()


func get_main_grid() -> Array[StringName]:
	return main_grid.duplicate()


func get_final_classification() -> Array[Dictionary]:
	return get_session_result(MAIN)


func is_complete() -> bool:
	return get_current_phase() == RESULTS and session_results.has(MAIN)


func is_player_eligible_for_phase(phase: StringName) -> bool:
	return get_session_entrant_ids(phase).has(PLAYER_ID)


func get_progress_ratio() -> float:
	if current_session_index < 0:
		return 0.0
	return clampf(float(current_session_index) / float(SESSION_ORDER.size() - 1), 0.0, 1.0)


func to_dictionary() -> Dictionary:
	return {
		&"weekend_id": weekend_id,
		&"event_id": event_id,
		&"display_name": display_name,
		&"entrants": entrants.duplicate(true),
		&"heat_transfer_count": heat_transfer_count,
		&"lcq_transfer_count": lcq_transfer_count,
		&"main_field_limit": main_field_limit,
		&"current_session_index": current_session_index,
		&"session_results": session_results.duplicate(true),
		&"qualifying_order": qualifying_order.duplicate(),
		&"heat_qualifiers": heat_qualifiers.duplicate(),
		&"lcq_candidates": lcq_candidates.duplicate(),
		&"lcq_qualifiers": lcq_qualifiers.duplicate(),
		&"main_grid": main_grid.duplicate(),
	}


func _set_session_index(new_index: int) -> void:
	var previous := get_current_phase()
	current_session_index = clampi(new_index, -1, SESSION_ORDER.size() - 1)
	var current := get_current_phase()
	if previous != current:
		phase_changed.emit(previous, current)


func _resolve_heat(classification: Array[Dictionary]) -> void:
	var ordered_ids := _rider_ids_from(classification)
	heat_qualifiers = ordered_ids.slice(0, mini(heat_transfer_count, ordered_ids.size()))
	lcq_candidates = ordered_ids.slice(heat_qualifiers.size())
	lcq_qualifiers.clear()
	main_grid = heat_qualifiers.slice(0, mini(main_field_limit, heat_qualifiers.size()))


func _resolve_lcq(classification: Array[Dictionary]) -> void:
	var ordered_ids := _rider_ids_from(classification)
	var available_slots := maxi(main_field_limit - heat_qualifiers.size(), 0)
	var transfer_count := mini(lcq_transfer_count, available_slots)
	lcq_qualifiers = ordered_ids.slice(0, mini(transfer_count, ordered_ids.size()))
	main_grid = heat_qualifiers.duplicate()
	main_grid.append_array(lcq_qualifiers)
	if main_grid.size() > main_field_limit:
		main_grid.resize(main_field_limit)


func _store_session_result(phase: StringName, classification: Array[Dictionary]) -> bool:
	if session_results.has(phase):
		return false
	session_results[phase] = classification.duplicate(true)
	session_completed.emit(phase, classification.duplicate(true))
	return true


func _complete_ai_only_lcq() -> void:
	if session_results.has(LCQ):
		return
	var classification := _simulate_ai_session(LCQ, lcq_candidates)
	_store_session_result(LCQ, classification)
	_resolve_lcq(classification)


func _complete_ai_only_main() -> void:
	if session_results.has(MAIN):
		return
	_store_session_result(MAIN, _simulate_ai_session(MAIN, main_grid))


func _normalize_player_phase_after_restore() -> void:
	if not _has_player_entrant():
		return
	var phase := get_current_phase()
	if phase == LCQ and heat_qualifiers.has(PLAYER_ID):
		_complete_ai_only_lcq()
		_set_session_index(SESSION_ORDER.find(MAIN))
	elif phase == MAIN and not main_grid.has(PLAYER_ID) and session_results.has(LCQ):
		_complete_ai_only_main()
		_set_session_index(SESSION_ORDER.find(RESULTS))


func _build_deterministic_qualifying_classification(
		classification: Array[Dictionary],
		expected_riders: Array[StringName]
	) -> Array[Dictionary]:
	var supplied: Dictionary = {}
	for raw_entry: Dictionary in classification:
		var supplied_id := StringName(raw_entry.get(&"rider_id", &""))
		if not supplied_id.is_empty() and not supplied.has(supplied_id):
			supplied[supplied_id] = raw_entry.duplicate(true)
	var output: Array[Dictionary] = []
	for rider_id: StringName in expected_riders:
		var entrant := _entrant_for(rider_id)
		if rider_id == PLAYER_ID:
			var player_entry := (supplied.get(PLAYER_ID, {}) as Dictionary).duplicate(true)
			player_entry[&"rider_id"] = PLAYER_ID
			player_entry[&"display_name"] = str(player_entry.get(&"display_name", entrant.get(&"display_name", "YOU")))
			player_entry[&"is_player"] = true
			var player_finish := int(player_entry.get(&"finish_usec", player_entry.get(&"effective_time_usec", -1)))
			var player_penalty := maxi(int(player_entry.get(&"penalty_usec", 0)), 0)
			player_entry[&"status"] = StringName(player_entry.get(&"status", &"FINISHED" if player_finish >= 0 else &"DNF"))
			player_entry[&"finish_usec"] = player_finish
			player_entry[&"penalty_usec"] = player_penalty
			player_entry[&"effective_time_usec"] = player_finish + player_penalty if player_finish >= 0 else -1
			output.append(player_entry)
		else:
			output.append(_build_ai_timing_entry(entrant, QUALIFYING, 2))
	_sort_timed_classification(output)
	return output


func _simulate_ai_session(phase: StringName, rider_ids: Array[StringName]) -> Array[Dictionary]:
	var laps := 3 if phase == MAIN else 2
	var output: Array[Dictionary] = []
	for rider_id: StringName in rider_ids:
		if rider_id == PLAYER_ID:
			continue
		output.append(_build_ai_timing_entry(_entrant_for(rider_id), phase, laps))
	_sort_timed_classification(output)
	return output


func _build_ai_timing_entry(entrant: Dictionary, phase: StringName, laps: int) -> Dictionary:
	var rider_id := StringName(entrant.get(&"rider_id", &""))
	var seed := maxi(int(entrant.get(&"seed", 1)), 1)
	var fallback_pace := 0.94 - float(maxi(seed - 2, 0)) * 0.012
	var pace := clampf(float(entrant.get(&"pace", fallback_pace)), 0.72, 1.0)
	var reference_usec := QUALIFYING_REFERENCE_USEC if phase == QUALIFYING else AI_LAP_REFERENCE_USEC * maxi(laps, 1)
	var time_usec := maxi(roundi(float(reference_usec) / pace) + _stable_time_variation(rider_id, phase), 1)
	var entry := entrant.duplicate(true)
	entry[&"rider_id"] = rider_id
	entry[&"display_name"] = str(entrant.get(&"display_name", String(rider_id)))
	entry[&"is_player"] = false
	entry[&"status"] = &"FINISHED"
	entry[&"finished"] = true
	entry[&"laps_completed"] = maxi(laps, 1)
	entry[&"total_laps"] = maxi(laps, 1)
	entry[&"finish_usec"] = time_usec
	entry[&"penalty_usec"] = 0
	entry[&"effective_time_usec"] = time_usec
	entry[&"best_lap_usec"] = maxi(time_usec / maxi(laps, 1) - abs(_stable_time_variation(rider_id, &"BEST_LAP")) / 4, 1)
	return entry


func _sort_timed_classification(classification: Array[Dictionary]) -> void:
	classification.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		var first_finished := StringName(first.get(&"status", &"DNF")) in [&"FINISHED", &"CLASSIFIED"]
		var second_finished := StringName(second.get(&"status", &"DNF")) in [&"FINISHED", &"CLASSIFIED"]
		if first_finished != second_finished:
			return first_finished
		var first_time := int(first.get(&"effective_time_usec", first.get(&"finish_usec", 9_223_372_036_854_775_000)))
		var second_time := int(second.get(&"effective_time_usec", second.get(&"finish_usec", 9_223_372_036_854_775_000)))
		if first_time != second_time:
			return first_time < second_time
		return String(first.get(&"rider_id", &"")) < String(second.get(&"rider_id", &""))
	)
	for index: int in classification.size():
		classification[index][&"position"] = index + 1


func _stable_time_variation(rider_id: StringName, phase: StringName) -> int:
	var token := "%s|%s|%s" % [String(weekend_id), String(phase), String(rider_id)]
	var accumulator := 17
	for index: int in token.length():
		accumulator = (accumulator * 131 + token.unicode_at(index)) % 2001
	return roundi((float(accumulator) - 1000.0) * 850.0)


func _entrant_for(rider_id: StringName) -> Dictionary:
	for entrant: Dictionary in entrants:
		if StringName(entrant.get(&"rider_id", &"")) == rider_id:
			return entrant.duplicate(true)
	return {&"rider_id": rider_id, &"display_name": String(rider_id), &"seed": entrants.size() + 1}


func _has_player_entrant() -> bool:
	return _all_entrant_ids().has(PLAYER_ID)


func _normalize_entrants(source: Array[Dictionary]) -> Array[Dictionary]:
	var normalized: Array[Dictionary] = []
	var seen: Dictionary = {}
	for index: int in source.size():
		var entrant := source[index].duplicate(true)
		var rider_id := StringName(entrant.get(&"rider_id", &""))
		if rider_id.is_empty() or seen.has(rider_id):
			continue
		seen[rider_id] = true
		entrant[&"rider_id"] = rider_id
		entrant[&"display_name"] = str(entrant.get(&"display_name", String(rider_id)))
		entrant[&"seed"] = maxi(int(entrant.get(&"seed", index + 1)), 1)
		normalized.append(entrant)
	normalized.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		var first_seed := int(first.get(&"seed", 999))
		var second_seed := int(second.get(&"seed", 999))
		if first_seed != second_seed:
			return first_seed < second_seed
		return String(first.get(&"rider_id", &"")) < String(second.get(&"rider_id", &""))
	)
	return normalized


func _normalize_classification(source: Array[Dictionary], expected_riders: Array[StringName]) -> Array[Dictionary]:
	var expected: Dictionary = {}
	for rider_id: StringName in expected_riders:
		expected[rider_id] = true
	var seen: Dictionary = {}
	var normalized: Array[Dictionary] = []
	for source_index: int in source.size():
		var entry := source[source_index].duplicate(true)
		var rider_id := StringName(entry.get(&"rider_id", &""))
		if rider_id.is_empty() or seen.has(rider_id) or (not expected.is_empty() and not expected.has(rider_id)):
			continue
		seen[rider_id] = true
		entry[&"rider_id"] = rider_id
		entry[&"position"] = maxi(int(entry.get(&"position", source_index + 1)), 1)
		entry[&"status"] = StringName(entry.get(&"status", &"FINISHED"))
		normalized.append(entry)
	normalized.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		var first_position := int(first.get(&"position", 999))
		var second_position := int(second.get(&"position", 999))
		if first_position != second_position:
			return first_position < second_position
		return String(first.get(&"rider_id", &"")) < String(second.get(&"rider_id", &""))
	)
	for rider_id: StringName in expected_riders:
		if not seen.has(rider_id):
			normalized.append({&"rider_id": rider_id, &"position": normalized.size() + 1, &"status": &"DNF"})
	for index: int in normalized.size():
		normalized[index][&"position"] = index + 1
	return normalized


func _all_entrant_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for entrant: Dictionary in entrants:
		ids.append(StringName(entrant.get(&"rider_id", &"")))
	return ids


static func _rider_ids_from(classification: Array[Dictionary]) -> Array[StringName]:
	var ids: Array[StringName] = []
	for entry: Dictionary in classification:
		ids.append(StringName(entry.get(&"rider_id", &"")))
	return ids


static func _dictionary_array(value: Variant) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	if value is Array:
		for entry: Variant in value:
			if entry is Dictionary:
				output.append((entry as Dictionary).duplicate(true))
	return output


static func _string_name_array(value: Variant) -> Array[StringName]:
	var output: Array[StringName] = []
	if value is Array or value is PackedStringArray:
		for entry: Variant in value:
			output.append(StringName(entry))
	return output
