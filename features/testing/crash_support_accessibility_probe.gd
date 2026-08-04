extends Node
## Headless contract for selectable, run-locked, competitively honest crash support.

const BIKE_SCRIPT := preload("res://entities/bike/bike_controller.gd")
const CRASH_SUPPORT_POLICY := preload("res://features/race/crash_support_policy.gd")
const CONDITION_FEEDBACK := preload("res://features/race/bike_condition_feedback.gd")
const COMPETITIVE_SIGNATURE := preload("res://features/competitive/competitive_run_signature.gd")
const TEST_PATH := "user://tests/crash_support_accessibility.json"

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_cleanup_test_files()
	var service := RaceServices.new()
	add_child(service)
	service.settings = SettingsStore.new(TEST_PATH)
	service.settings.reset_to_defaults()
	var bike: DirtBikeController = BIKE_SCRIPT.new()
	service.bike = bike

	_check(
		SettingsStore.CRASH_SUPPORT_MODES == ["STANDARD", "ASSISTED"]
		and service.get_preferred_crash_support_mode() == CRASH_SUPPORT_POLICY.STANDARD,
		"Crash support does not default to the unchanged standard experience"
	)

	var access_items: Array[Dictionary] = service.call(
		&"_settings_items_for_page",
		&"ACCESS"
	) as Array[Dictionary]
	var crash_support_index := -1
	for index: int in access_items.size():
		if StringName(access_items[index].get(&"key", &"")) == &"crash_support_mode":
			crash_support_index = index
			_check(
				str(access_items[index].get(&"label", "")) == "CRASH SUPPORT"
				and (access_items[index].get(&"options", []) as Array) == ["STANDARD", "ASSISTED"],
				"Access page does not present the exact Standard/Assisted choice"
			)
			break
	_check(crash_support_index >= 0, "Access page does not expose crash support")

	_check(
		service.set_activity_crash_support_override(&"STANDARD"),
		"An activity could not freeze its crash-support preference"
	)
	service.set("_settings_items", access_items)
	service.set("_settings_index", crash_support_index)
	service.call(&"_adjust_setting", 1)
	_check(
		service.get_preferred_crash_support_mode() == CRASH_SUPPORT_POLICY.ASSISTED
			and service.get_effective_crash_support_mode() == CRASH_SUPPORT_POLICY.STANDARD
			and String(service.get("_settings_message")).contains("APPLIES NEXT EVENT"),
		"A mid-activity choice did not save safely for the next event"
	)
	_check(
		StringName(bike.get_crash_support_snapshot().get(&"mode", &"")) == CRASH_SUPPORT_POLICY.STANDARD,
		"The physical bike changed crash support inside a frozen activity"
	)
	service.clear_activity_crash_support_override()
	var assisted_bike := bike.get_crash_support_snapshot()
	_check(
		service.get_effective_crash_support_mode() == CRASH_SUPPORT_POLICY.ASSISTED
			and StringName(assisted_bike.get(&"mode", &"")) == CRASH_SUPPORT_POLICY.ASSISTED
			and is_equal_approx(
				float(assisted_bike.get(&"tipped_recovery_delay_seconds", 0.0)),
				CRASH_SUPPORT_POLICY.tipped_recovery_delay(bike.tipped_recovery_delay, &"ASSISTED")
			),
		"The saved support mode did not reach authoritative recovery timing after the lock cleared"
	)

	_check(
		CONDITION_FEEDBACK.damage_for_landing(1.0, &"STANDARD") == 6
			and CONDITION_FEEDBACK.damage_for_landing(1.0, &"ASSISTED") == 3
			and CONDITION_FEEDBACK.damage_for_automatic_recovery(&"AUTO_WORLD_FALL", &"STANDARD") == 8
			and CONDITION_FEEDBACK.damage_for_automatic_recovery(&"AUTO_WORLD_FALL", &"ASSISTED") == 4
			and CONDITION_FEEDBACK.damage_for_automatic_recovery(&"MANUAL_RESET", &"ASSISTED") == 0,
		"Assisted support does not halve lasting crash damage while preserving free manual reset"
	)
	_check(
		bool(assisted_bike.get(&"reset_penalty_preserved", false))
			and bool(assisted_bike.get(&"competitive_identity_separated", false)),
		"Accessibility support does not disclose preserved penalties and separated records"
	)

	var standard_context := _signature_context(&"STANDARD")
	var assisted_context := _signature_context(&"ASSISTED")
	var standard_signature := COMPETITIVE_SIGNATURE.build(standard_context)
	var assisted_signature := COMPETITIVE_SIGNATURE.build(assisted_context)
	_check(
		COMPETITIVE_SIGNATURE.validate(standard_signature)
			and COMPETITIVE_SIGNATURE.validate(assisted_signature)
			and standard_signature != assisted_signature
			and StringName(
				COMPETITIVE_SIGNATURE.normalize_context(assisted_context).get(
					"crash_support_mode",
					""
				)
			) == &"ASSISTED",
		"Standard and Assisted runs are not separated by competitive identity"
	)

	_check(service.settings.save_to_disk(), "Assisted crash support did not save atomically")
	var reloaded := SettingsStore.new(TEST_PATH)
	_check(
		bool(reloaded.load_from_disk().get("ok", false))
			and StringName(reloaded.get_value(&"gameplay", &"crash_support_mode", &"")) == &"ASSISTED",
		"Assisted crash support did not survive verified settings reload"
	)

	print(
		"CRASH SUPPORT ACCESSIBILITY PROBE: standard_damage=8 assisted_damage=4 "
		+ "run_locked=true signatures_separated=true persisted=true passed=%s"
		% str(_failures.is_empty())
	)
	bike.free()
	service.queue_free()
	await get_tree().process_frame
	_cleanup_test_files()
	if _failures.is_empty():
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("CRASH SUPPORT ACCESSIBILITY PROBE: %s" % failure)
	get_tree().quit(1)


func _signature_context(crash_support_mode: StringName) -> Dictionary:
	return {
		&"event_id": &"CRASH_SUPPORT_TEST",
		&"track_id": &"QUARRY",
		&"route_version": 1,
		&"format": &"SPRINT",
		&"laps": 2,
		&"bike_class": &"MX2",
		&"difficulty": 2,
		&"assist_mode": &"SPORT",
		&"transmission_mode": &"AUTOMATIC",
		&"control_signature": &"DEFAULT",
		&"crash_support_mode": crash_support_mode,
		&"setup_id": &"BALANCED",
	}


func _cleanup_test_files() -> void:
	for suffix: String in [
		"",
		SettingsStore.TEMP_SUFFIX,
		SettingsStore.BACKUP_SUFFIX,
		SettingsStore.BACKUP_TEMP_SUFFIX,
	]:
		var path := TEST_PATH + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check(condition: bool, failure: String) -> void:
	if not condition:
		_failures.append(failure)
