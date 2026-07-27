extends Node
## Deterministic contract for the interactive Surface Reading Academy lesson.

const TRACKER_SCRIPT := preload("res://features/career/academy_surface_tracker.gd")
const CATALOG_SCRIPT := preload("res://features/career/academy_lesson_catalog.gd")
const BIKE_SCENE := preload("res://entities/bike/bike.tscn")

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_probe_lesson_and_event_contract()
	_probe_sector_projection()
	_probe_adaptation_grading()
	await _probe_physical_surface_override()
	if _failures.is_empty():
		print("ACADEMY SURFACE READING PROBE: PASS  //  sectors=PACKED>SAND>GRASS>MUD checkpoints=0/2/5/8 adaptation=4/4 physical=true grade=gold")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("ACADEMY SURFACE READING PROBE: " + failure)
	get_tree().quit(1)


func _probe_lesson_and_event_contract() -> void:
	var catalog: Variant = CATALOG_SCRIPT.create_default()
	var lesson := catalog.get_lesson(&"SURFACE_READING") as Dictionary
	_check(not lesson.is_empty(), "Academy catalog omitted Surface Reading")
	var training := lesson.get(&"surface_training", []) as Array
	_check(training.size() == 4, "surface lesson did not retain four compact sectors")
	_check(
		_surface_names(training) == [&"PACKED", &"SAND", &"GRASS", &"MUD"],
		"surface sector order drifted"
	)
	_check(
		_start_checkpoints(training) == [0, 2, 5, 8],
		"surface checkpoint boundaries drifted"
	)
	var event := RaceEventCatalog._academy_to_event(lesson)
	var rules := event.get(&"rules", {}) as Dictionary
	_check(
		(rules.get(&"surface_training", []) as Array) == training,
		"event/session projection omitted the authored surface contract"
	)
	_check(
		int(event.get(&"laps", 0)) == 1
			and int(event.get(&"checkpoint_count", 0)) == 10
			and int(event.get(&"opponent_count", -1)) == 0,
		"surface lesson stopped being a focused one-lap solo exercise"
	)


func _probe_sector_projection() -> void:
	var training := (
		CATALOG_SCRIPT.create_default().get_lesson(&"SURFACE_READING")
			.get(&"surface_training", []) as Array
	)
	var expected: Array[StringName] = [
		&"PACKED", &"PACKED", &"SAND", &"SAND", &"SAND",
		&"GRASS", &"GRASS", &"GRASS", &"MUD", &"MUD",
	]
	for checkpoint: int in expected.size():
		var sector := RaceController.academy_surface_sector_for_checkpoint(training, checkpoint)
		_check(
			StringName(sector.get(&"surface", &"")) == expected[checkpoint],
			"checkpoint %d projected the wrong physical surface" % checkpoint
		)
	var sand := RaceController.academy_surface_sector_for_checkpoint(training, 2)
	var mud := RaceController.academy_surface_sector_for_checkpoint(training, 9)
	_check(StringName(sand.get(&"next_surface", &"")) == &"GRASS", "sand did not preview grass")
	_check(StringName(mud.get(&"next_surface", &"X")).is_empty(), "final mud sector previewed a nonexistent surface")


func _probe_adaptation_grading() -> void:
	var tracker: Variant = TRACKER_SCRIPT.new()
	var sectors: Array[Dictionary] = [
		{&"surface": &"PACKED", &"next": &"SAND", &"controls": _controls(0.55, 0.0, 0.10)},
		{&"surface": &"SAND", &"next": &"GRASS", &"controls": _controls(0.65, 0.0, 0.20)},
		{&"surface": &"GRASS", &"next": &"MUD", &"controls": _controls(0.55, 0.0, 0.20)},
		{&"surface": &"MUD", &"next": &"", &"controls": _controls(0.45, 0.0, 0.20)},
	]
	for sector: Dictionary in sectors:
		_check(
			tracker.enter_surface(
				StringName(sector.get(&"surface", &"")),
				StringName(sector.get(&"next", &""))
			),
			"tracker rejected a new authored sector"
		)
		tracker.sample(0.20, _controls(1.0, 1.0, 1.0), 12.0)
		tracker.sample(0.25, sector.get(&"controls", {}) as Dictionary, 12.0)
		tracker.sample(0.25, sector.get(&"controls", {}) as Dictionary, 12.0)
	var metrics := tracker.get_metrics() as Dictionary
	_check(
		int(metrics.get(&"surface_sectors", 0)) == 4
			and int(metrics.get(&"adapted_entries", 0)) == 4,
		"safe control holds did not earn one adaptation per sector"
	)
	var catalog: Variant = CATALOG_SCRIPT.create_default()
	var grade: Dictionary = catalog.evaluate_lesson(&"SURFACE_READING", metrics)
	_check(
		bool(grade.get(&"passed", false)) and int(grade.get(&"stars", 0)) == 3,
		"four demonstrated adaptations did not produce the authored gold grade"
	)
	var failed: Dictionary = catalog.evaluate_lesson(
		&"SURFACE_READING", {&"surface_sectors": 4, &"adapted_entries": 1}
	)
	_check(not bool(failed.get(&"passed", true)), "surface exposure alone passed without control adaptation")


func _probe_physical_surface_override() -> void:
	var bike := BIKE_SCENE.instantiate() as DirtBikeController
	add_child(bike)
	await get_tree().process_frame
	for surface: StringName in [&"PACKED", &"SAND", &"GRASS", &"MUD"]:
		bike.set_training_surface_override(surface)
		_check(
			bike.get_training_surface_override() == surface
				and bike.get_active_surface() == surface,
			"%s coaching did not reach the physical bike surface" % String(surface)
		)
	bike.clear_training_surface_override()
	_check(bike.get_training_surface_override().is_empty(), "surface override leaked after lesson cleanup")
	bike.queue_free()
	await get_tree().process_frame


func _surface_names(training: Array) -> Array[StringName]:
	var output: Array[StringName] = []
	for entry: Dictionary in training:
		output.append(StringName(entry.get(&"surface", &"")))
	return output


func _start_checkpoints(training: Array) -> Array[int]:
	var output: Array[int] = []
	for entry: Dictionary in training:
		output.append(int(entry.get(&"start_checkpoint", -1)))
	return output


func _controls(throttle: float, brake: float, steer: float) -> Dictionary:
	return {&"throttle": throttle, &"brake": brake, &"steer": steer}


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
