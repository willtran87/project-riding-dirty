extends Node
## Headless contract for critical save state, visible feedback, and settings writes.

const TEST_SETTINGS_PATH := "user://tests/save_lifecycle_feedback_settings.json"
const TEST_GHOST_PATH := "user://save_lifecycle_probe_best_run.dat"
const MAIN_SCRIPT := preload("res://scenes/main.gd")

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_cleanup()
	SaveLifecycle.reset_for_testing()
	var service := RaceServices.new()
	add_child(service)
	await get_tree().process_frame

	var career_token := SaveLifecycle.begin_save(&"CAREER", "Career Progress", true)
	var saving := SaveLifecycle.get_snapshot()
	_expect(StringName(saving.get(&"state", &"")) == &"SAVING", "critical write did not enter SAVING")
	_expect(SaveLifecycle.is_critical_save_active(), "critical write did not activate close guard")
	_expect(int(saving.get(&"critical_count", 0)) == 1, "critical write count was not one")
	var saving_badge := service.get_save_feedback_snapshot()
	_expect(bool(saving_badge.get(&"visible", false)), "SAVING badge was hidden")
	_expect(str(saving_badge.get(&"text", "")).contains("[SAVING]"), "SAVING badge lacked textual state")
	_expect(str(saving_badge.get(&"text", "")).contains("CAREER PROGRESS"), "SAVING badge lacked context")

	var background_token := SaveLifecycle.begin_save(&"GHOST", "Personal Best Ghost", false)
	_expect(int(SaveLifecycle.get_snapshot().get(&"active_count", 0)) == 2, "nested save count drifted")
	_expect(SaveLifecycle.finish_save(background_token, true), "nested noncritical save did not finish")
	_expect(StringName(SaveLifecycle.get_snapshot().get(&"state", &"")) == &"SAVING", "remaining write lost SAVING state")
	_expect(SaveLifecycle.is_critical_save_active(), "nested completion released critical guard early")
	_expect(SaveLifecycle.finish_save(career_token, true), "critical save did not finish")
	_expect(not SaveLifecycle.is_critical_save_active(), "critical guard remained active after completion")
	var saved_badge := service.get_save_feedback_snapshot()
	_expect(StringName(saved_badge.get(&"state", &"")) == &"SAVED", "badge did not enter SAVED")
	_expect(str(saved_badge.get(&"text", "")).contains("[SAVED]"), "SAVED badge lacked textual state")

	SaveLifecycle.report_recovered(&"CAREER", "Career Progress", true)
	var recovered_badge := service.get_save_feedback_snapshot()
	_expect(StringName(recovered_badge.get(&"state", &"")) == &"RECOVERED", "recovery was not surfaced")
	_expect(str(recovered_badge.get(&"text", "")).contains("[RECOVERED]"), "recovery badge lacked textual state")

	var failed_token := SaveLifecycle.begin_save(&"SETTINGS", "Rider Settings", true)
	_expect(not SaveLifecycle.finish_save(failed_token, false, "disk_full"), "failed write returned success")
	var failed := SaveLifecycle.get_snapshot()
	var failed_badge := service.get_save_feedback_snapshot()
	_expect(StringName(failed.get(&"state", &"")) == &"FAILED", "failed write did not enter FAILED")
	_expect(str(failed.get(&"error", "")) == "disk_full", "failed write lost its error identity")
	_expect(str(failed_badge.get(&"text", "")).contains("[SAVE FAILED]"), "failure badge lacked textual state")
	_expect(not SaveLifecycle.finish_save(999999, true), "unknown token was accepted")
	_expect(
		not MAIN_SCRIPT.should_release_pending_close_after_save({
			&"state": &"SAVING", &"critical_count": 1,
		}),
		"pending close released while a critical write remained active"
	)
	_expect(
		not MAIN_SCRIPT.should_release_pending_close_after_save({
			&"state": &"FAILED", &"critical_count": 0,
		}),
		"failed critical write allowed the application to close"
	)
	_expect(
		MAIN_SCRIPT.should_release_pending_close_after_save({
			&"state": &"SAVED", &"critical_count": 0,
		}),
		"successful critical write did not release pending close"
	)

	var viewport_rect := get_viewport().get_visible_rect()
	var panel_rect := failed_badge.get(&"panel_rect", Rect2()) as Rect2
	_expect(viewport_rect.encloses(panel_rect), "save badge escaped the visible viewport")
	_expect(panel_rect.size.x >= 420.0 and panel_rect.size.y >= 44.0, "save badge is not readable at reference size")

	SaveLifecycle.reset_for_testing()
	var settings := SettingsStore.new(TEST_SETTINGS_PATH)
	_expect(settings.set_value(&"audio", &"master_volume", 0.65), "settings fixture rejected valid value")
	_expect(settings.save_to_disk(), "verified settings write failed")
	var settings_state := SaveLifecycle.get_snapshot()
	_expect(StringName(settings_state.get(&"state", &"")) == &"SAVED", "settings write did not publish SAVED")
	_expect(StringName(settings_state.get(&"domain", &"")) == &"SETTINGS", "settings write used wrong domain")
	_expect(str(settings_state.get(&"context", "")) == "RIDER SETTINGS", "settings write used wrong context")
	_expect(FileAccess.file_exists(TEST_SETTINGS_PATH), "settings write did not create primary")
	service.settings = settings
	service.call(&"_apply_settings")
	var applied_settings_state := SaveLifecycle.get_snapshot()
	_expect(
		StringName(applied_settings_state.get(&"domain", &"")) == &"SETTINGS",
		"applying settings replaced honest feedback with a no-op career save"
	)

	var ghost := GhostController.new()
	ghost.set(&"_record_slot", &"save_lifecycle_probe")
	add_child(ghost)
	await get_tree().process_frame
	ghost.best_time_usec = 123_000
	var first_ghost_frames: Array[Dictionary] = [
		{&"time": 0.0, &"transform": Transform3D.IDENTITY},
	]
	ghost.set(&"_best_frames", first_ghost_frames)
	_expect(bool(ghost.call(&"_save_best_run")), "initial verified ghost write failed")
	ghost.best_time_usec = 110_000
	var replacement_ghost_frames: Array[Dictionary] = [
		{&"time": 0.0, &"transform": Transform3D(Basis.IDENTITY, Vector3.ONE)},
	]
	ghost.set(&"_best_frames", replacement_ghost_frames)
	_expect(bool(ghost.call(&"_save_best_run")), "replacement verified ghost write failed")
	_expect(FileAccess.file_exists(TEST_GHOST_PATH + ".bak"), "ghost write did not rotate a recovery copy")
	ghost.queue_free()
	await get_tree().process_frame
	var corrupt_ghost := FileAccess.open(TEST_GHOST_PATH, FileAccess.WRITE)
	_expect(corrupt_ghost != null, "ghost corruption fixture could not open primary")
	if corrupt_ghost != null:
		corrupt_ghost.store_string("[corrupt]\nvalue=false\n")
		corrupt_ghost.close()
	SaveLifecycle.reset_for_testing()
	var recovered_ghost := GhostController.new()
	recovered_ghost.set(&"_record_slot", &"save_lifecycle_probe")
	add_child(recovered_ghost)
	await get_tree().process_frame
	_expect(
		recovered_ghost.best_time_usec == 123_000,
		"ghost backup recovery restored wrong run (%dus)" % recovered_ghost.best_time_usec
	)
	var ghost_recovery := SaveLifecycle.get_snapshot()
	_expect(StringName(ghost_recovery.get(&"state", &"")) == &"RECOVERED", "ghost recovery was not published")
	_expect(StringName(ghost_recovery.get(&"domain", &"")) == &"GHOST", "ghost recovery used wrong domain")
	recovered_ghost.queue_free()

	_cleanup()
	SaveLifecycle.reset_for_testing()
	service.queue_free()
	var passed := _failures.is_empty()
	print("SAVE LIFECYCLE FEEDBACK PROBE: lifecycle=true nested=true feedback=true settings=true failures=%d passed=%s" % [
		_failures.size(), str(passed),
	])
	get_tree().quit(0 if passed else 1)


func _cleanup() -> void:
	for path: String in [
		TEST_SETTINGS_PATH,
		TEST_SETTINGS_PATH + SettingsStore.BACKUP_SUFFIX,
		TEST_SETTINGS_PATH + SettingsStore.TEMP_SUFFIX,
		TEST_SETTINGS_PATH + SettingsStore.BACKUP_TEMP_SUFFIX,
		TEST_GHOST_PATH,
		TEST_GHOST_PATH + ".bak",
		TEST_GHOST_PATH + ".tmp",
		TEST_GHOST_PATH + ".bak.tmp",
	]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
	push_error("SAVE LIFECYCLE FEEDBACK PROBE: %s" % message)
