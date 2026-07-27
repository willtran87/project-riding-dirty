extends RefCounted
class_name CustomTourState
## Persistent player-authored championship playlist backed by the production
## points and deterministic countback service.

const CHAMPIONSHIP_SERVICE_SCRIPT := preload("res://features/career/championship_service.gd")
const VERSION: int = 1
const MIN_ROUNDS: int = 2
const MAX_ROUNDS: int = 5
const PHASE_EMPTY: StringName = &"EMPTY"
const PHASE_BUILDING: StringName = &"BUILDING"
const PHASE_ACTIVE: StringName = &"ACTIVE"
const PHASE_COMPLETE: StringName = &"COMPLETE"
const ALLOWED_EVENTS: Array[StringName] = [
	&"CIRCUIT",
	&"PINE_ENDURO",
	&"MESA_PRACTICE",
	&"MESA_MX",
	&"MESA_ELIMINATION",
	&"MESA_RIVAL",
	&"MESA_ENDURANCE",
	&"QUARRY_HILLCLIMB",
	&"PINE_WET",
	&"MESA_RHYTHM",
]

var phase: StringName = PHASE_EMPTY
var draft_events: Array[StringName] = []
var championship: RacingChampionshipService = RacingChampionshipService.new()
var last_result_event_id: StringName = &""


static func from_dictionary(data: Dictionary) -> CustomTourState:
	var state := CustomTourState.new()
	var draft_value: Variant = data.get(&"draft_events", [])
	if draft_value is Array or draft_value is PackedStringArray:
		for raw_event: Variant in draft_value:
			var event_id := StringName(raw_event)
			if (
				event_id in ALLOWED_EVENTS
				and not state.draft_events.has(event_id)
				and state.draft_events.size() < MAX_ROUNDS
			):
				state.draft_events.append(event_id)
	var requested_phase := StringName(data.get(&"phase", PHASE_EMPTY))
	var championship_value: Variant = data.get(&"championship", {})
	if championship_value is Dictionary and not (championship_value as Dictionary).is_empty():
		state.championship = CHAMPIONSHIP_SERVICE_SCRIPT.from_dictionary(
			championship_value as Dictionary
		)
	var calendar_valid := state._calendar_is_valid()
	if requested_phase in [PHASE_ACTIVE, PHASE_COMPLETE] and calendar_valid:
		state.phase = (
			PHASE_COMPLETE
			if state.championship.is_complete()
			else PHASE_ACTIVE
		)
		state.draft_events = state._calendar_event_ids()
	elif requested_phase == PHASE_BUILDING:
		state.phase = PHASE_BUILDING
		state.championship = RacingChampionshipService.new()
	elif not state.draft_events.is_empty():
		state.phase = PHASE_BUILDING
	else:
		state.phase = PHASE_EMPTY
		state.championship = RacingChampionshipService.new()
	state.last_result_event_id = StringName(data.get(&"last_result_event_id", &""))
	if state.last_result_event_id not in ALLOWED_EVENTS:
		state.last_result_event_id = &""
	return state


func begin_builder(clear_existing: bool = true) -> Dictionary:
	if phase == PHASE_ACTIVE:
		return {&"ok": false, &"error": &"TOUR_ACTIVE"}
	if clear_existing:
		draft_events.clear()
	phase = PHASE_BUILDING
	championship = RacingChampionshipService.new()
	last_result_event_id = &""
	return {&"ok": true, &"snapshot": presentation_snapshot()}


func toggle_event(event_id: StringName) -> Dictionary:
	if phase != PHASE_BUILDING:
		return {&"ok": false, &"error": &"NOT_BUILDING"}
	if event_id not in ALLOWED_EVENTS:
		return {&"ok": false, &"error": &"EVENT_UNSUPPORTED"}
	if draft_events.has(event_id):
		draft_events.erase(event_id)
		return {
			&"ok": true,
			&"added": false,
			&"event_id": event_id,
			&"snapshot": presentation_snapshot(),
		}
	if draft_events.size() >= MAX_ROUNDS:
		return {&"ok": false, &"error": &"TOUR_FULL"}
	draft_events.append(event_id)
	return {
		&"ok": true,
		&"added": true,
		&"event_id": event_id,
		&"snapshot": presentation_snapshot(),
	}


func start_tour() -> Dictionary:
	if phase != PHASE_BUILDING:
		return {&"ok": false, &"error": &"NOT_BUILDING"}
	if draft_events.size() < MIN_ROUNDS:
		return {&"ok": false, &"error": &"NEED_MORE_ROUNDS"}
	if draft_events.size() > MAX_ROUNDS:
		return {&"ok": false, &"error": &"TOO_MANY_ROUNDS"}
	var calendar: Array[Dictionary] = []
	for index: int in draft_events.size():
		var event_id := draft_events[index]
		var event := RaceEventCatalog.get_event(event_id)
		calendar.append({
			&"round_id": StringName("CUSTOM_%02d_%s" % [index + 1, String(event_id)]),
			&"event_id": event_id,
			&"track_id": StringName(event.get(&"track_id", &"QUARRY")),
			&"display_name": str(event.get(&"display_name", event_id)),
		})
	championship = RacingChampionshipService.new()
	championship.configure(
		&"CUSTOM_TOUR",
		"CUSTOM TOUR",
		calendar,
		PackedInt32Array(RacingChampionshipService.DEFAULT_POINTS),
		1
	)
	phase = PHASE_ACTIVE
	last_result_event_id = &""
	return {&"ok": true, &"snapshot": presentation_snapshot()}


func submit_round(event_id: StringName, classification: Array[Dictionary]) -> Dictionary:
	if phase != PHASE_ACTIVE:
		return {&"ok": false, &"error": &"TOUR_NOT_ACTIVE"}
	var next_round := championship.get_next_round()
	if next_round.is_empty():
		return {&"ok": false, &"error": &"NO_NEXT_ROUND"}
	if StringName(next_round.get(&"event_id", &"")) != event_id:
		return {&"ok": false, &"error": &"WRONG_EVENT"}
	var round_id := StringName(next_round.get(&"round_id", &""))
	if not championship.record_round_result(round_id, classification):
		return {&"ok": false, &"error": &"INVALID_CLASSIFICATION"}
	last_result_event_id = event_id
	phase = PHASE_COMPLETE if championship.is_complete() else PHASE_ACTIVE
	return {
		&"ok": true,
		&"round_id": round_id,
		&"completed": phase == PHASE_COMPLETE,
		&"snapshot": presentation_snapshot(),
	}


func clear() -> void:
	phase = PHASE_EMPTY
	draft_events.clear()
	championship = RacingChampionshipService.new()
	last_result_event_id = &""


func is_active() -> bool:
	return phase == PHASE_ACTIVE


func is_complete() -> bool:
	return phase == PHASE_COMPLETE


func current_event_id() -> StringName:
	if not is_active():
		return &""
	return StringName(championship.get_next_round().get(&"event_id", &""))


func presentation_snapshot() -> Dictionary:
	var calendar: Array[Dictionary] = []
	var standings: Array[Dictionary] = []
	var next_round: Dictionary = {}
	var champion: Dictionary = {}
	if phase in [PHASE_ACTIVE, PHASE_COMPLETE]:
		calendar = championship.get_calendar()
		standings = championship.get_standings()
	if phase == PHASE_ACTIVE:
		next_round = championship.get_next_round()
	elif phase == PHASE_COMPLETE:
		champion = championship.get_champion()
	var draft_items: Array[Dictionary] = []
	for event_id: StringName in draft_events:
		var event := RaceEventCatalog.get_event(event_id)
		draft_items.append({
			&"event_id": event_id,
			&"display_name": str(event.get(&"display_name", event_id)),
			&"track_id": StringName(event.get(&"track_id", &"QUARRY")),
		})
	return {
		&"configured": phase in [PHASE_ACTIVE, PHASE_COMPLETE],
		&"building": phase == PHASE_BUILDING,
		&"active": phase == PHASE_ACTIVE,
		&"completed": phase == PHASE_COMPLETE,
		&"phase": phase,
		&"draft_events": draft_events.duplicate(),
		&"draft_items": draft_items,
		&"round_count": (
			calendar.size()
			if phase in [PHASE_ACTIVE, PHASE_COMPLETE]
			else draft_events.size()
		),
		&"minimum_rounds": MIN_ROUNDS,
		&"maximum_rounds": MAX_ROUNDS,
		&"completed_rounds": championship.completed_round_count() if not calendar.is_empty() else 0,
		&"current_round": championship.completed_round_count() + 1 if phase == PHASE_ACTIVE else 0,
		&"next_event_id": StringName(next_round.get(&"event_id", &"")),
		&"next_event_name": str(next_round.get(&"display_name", "")),
		&"calendar": calendar,
		&"standings": standings,
		&"champion": champion,
		&"last_result_event_id": last_result_event_id,
	}


func to_dictionary() -> Dictionary:
	return {
		&"version": VERSION,
		&"phase": phase,
		&"draft_events": draft_events.duplicate(),
		&"championship": (
			championship.to_dictionary()
			if phase in [PHASE_ACTIVE, PHASE_COMPLETE]
			else {}
		),
		&"last_result_event_id": last_result_event_id,
	}


func _calendar_is_valid() -> bool:
	if championship.championship_id != &"CUSTOM_TOUR":
		return false
	if championship.calendar.size() < MIN_ROUNDS or championship.calendar.size() > MAX_ROUNDS:
		return false
	var seen: Dictionary = {}
	for entry: Dictionary in championship.calendar:
		var event_id := StringName(entry.get(&"event_id", &""))
		if event_id not in ALLOWED_EVENTS or seen.has(event_id):
			return false
		seen[event_id] = true
	return true


func _calendar_event_ids() -> Array[StringName]:
	var output: Array[StringName] = []
	for entry: Dictionary in championship.calendar:
		output.append(StringName(entry.get(&"event_id", &"")))
	return output
