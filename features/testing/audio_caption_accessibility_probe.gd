extends Node
## End-to-end contract for persistent, scalable captions of accepted semantic
## audio cues. Continuous ambience is deliberately outside this contract.

const TEST_PATH := "user://tests/audio_caption_accessibility_probe.json"
const LEGACY_VERSION := 14

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_cleanup()
	_write_legacy_settings()
	var store := SettingsStore.new(TEST_PATH)
	var load := store.load_from_disk()
	_check(bool(load.get(&"ok", false)), "Legacy settings did not load")
	_check(bool(load.get(&"migrated", false)), "Schema-14 settings did not migrate")
	_check(
		str(store.get_value(&"interface", &"caption_detail", "")) == "IMPORTANT"
			and is_equal_approx(float(store.get_value(&"interface", &"caption_scale", 0.0)), 1.0)
			and str(store.get_value(&"interface", &"caption_style", "")) == "STANDARD",
		"Legacy riders did not receive conservative caption defaults"
	)
	_check(
		not store.set_value(&"interface", &"caption_detail", "FABRICATED")
			and not store.set_value(&"interface", &"caption_scale", 4.0)
			and not store.set_value(&"interface", &"caption_style", "INVISIBLE"),
		"Caption settings accepted unbounded values"
	)
	var service := RaceServices.new()
	service.settings = store
	add_child(service)
	await get_tree().process_frame
	service.call(&"_apply_settings")
	service.set("_settings_page_index", RaceServices.SETTINGS_PAGE_IDS.find(&"ACCESS"))
	service.call(&"_refresh_settings_text")
	var access_items := service.get("_settings_items") as Array
	var detail_index := _find_setting_index(access_items, &"caption_detail")
	var scale_index := _find_setting_index(access_items, &"caption_scale")
	var style_index := _find_setting_index(access_items, &"caption_style")
	_check(
		detail_index >= 0 and scale_index == detail_index + 1 and style_index == scale_index + 1,
		"Access page does not expose the complete ordered caption controls"
	)

	var feed := service.get("_audio_caption_feed") as AudioCaptionFeed
	_check(feed != null, "Race services did not create the caption feed")
	if feed == null:
		await _finish(service)
		return
	feed.clear()
	EventBus.audio_caption_requested.emit(&"ROUTE", "HIDDEN LOW PRIORITY", 1)
	var important_only := feed.get_snapshot()
	_check(
		not bool(important_only.get(&"visible", true))
			and int(important_only.get(&"suppressed_count", 0)) == 1,
		"Important-only mode did not suppress low-priority captions"
	)
	EventBus.audio_caption_requested.emit(&"COMMENTARY", "WRONG WAY // REJOIN SAFELY", 2)
	var warning := feed.get_snapshot()
	_check(
		bool(warning.get(&"visible", false))
			and StringName(warning.get(&"source", &"")) == &"COMMENTARY"
			and str(warning.get(&"display_text", "")).contains("WRONG WAY")
			and int(warning.get(&"priority", 0)) == 2,
		"Important commentary did not produce a semantic caption"
	)
	EventBus.audio_caption_requested.emit(&"COMMENTARY", "WRONG WAY // REJOIN SAFELY", 2)
	var repeated := feed.get_snapshot()
	_check(
		int(repeated.get(&"repeat_count", 0)) == 2
			and str(repeated.get(&"display_text", "")).ends_with("x2"),
		"Repeated captions were not merged into a bounded receipt"
	)
	EventBus.audio_caption_requested.emit(&"ROUTE", "QUARRY RIDGELINE", 1)
	_check(
		int(feed.get_snapshot().get(&"queue_size", 0)) == 0,
		"Important-only mode queued a low-priority caption"
	)
	_check(store.set_value(&"interface", &"caption_detail", "ALL"), "ALL caption mode was rejected")
	_check(store.set_value(&"interface", &"caption_scale", 1.5), "Caption size was rejected")
	_check(store.set_value(&"interface", &"caption_style", "HIGH_CONTRAST"), "Caption background was rejected")
	service.call(&"_apply_settings")
	feed.clear()
	EventBus.audio_caption_requested.emit(&"ROUTE", "QUARRY RIDGELINE", 1)
	await get_tree().process_frame
	var all_mode := feed.get_snapshot()
	var panel_rect: Rect2 = all_mode.get(&"panel_rect", Rect2())
	var viewport_rect := Rect2(Vector2.ZERO, Vector2(get_viewport().get_visible_rect().size))
	_check(
		bool(all_mode.get(&"visible", false))
			and StringName(all_mode.get(&"source", &"")) == &"ROUTE"
			and int(all_mode.get(&"font_size", 0)) == 30
			and bool(all_mode.get(&"effective_high_contrast", false))
			and viewport_rect.encloses(panel_rect),
		"All-cue, size, contrast, or viewport containment did not apply"
	)
	var audio := GameplayAudio.new()
	add_child(audio)
	await get_tree().process_frame
	feed.clear()
	audio.set("_last_commentary_feedback_usec", -1_000_000)
	audio.call(&"_play_commentary_feedback", &"WARNING", "PENALTY // COURSE CUT")
	var audio_commentary := feed.get_snapshot()
	_check(
		StringName(audio_commentary.get(&"source", &"")) == &"COMMENTARY"
			and str(audio_commentary.get(&"text", "")).contains("PENALTY")
			and int(audio.get_competition_feedback_snapshot().get(&"commentary_count", 0)) >= 1,
		"Accepted GameplayAudio commentary did not request a matching caption"
	)
	feed.clear()
	audio.set("_last_commentary_feedback_usec", -1_000_000)
	audio.call(&"_on_integrity_updated", {&"warning": &"WRONG_WAY"})
	audio.call(&"_on_integrity_updated", {&"warning": &"WRONG_WAY"})
	var integrity_warning := feed.get_snapshot()
	_check(
		StringName(integrity_warning.get(&"source", &"")) == &"COMMENTARY"
			and str(integrity_warning.get(&"text", "")).contains("WRONG WAY")
			and str(integrity_warning.get(&"text", "")).contains("TURN AROUND")
			and int(integrity_warning.get(&"repeat_count", 0)) == 1,
		"Authoritative integrity state did not produce one exact, de-duplicated caption"
	)
	feed.clear()
	audio.call(&"_on_countdown_changed", 3)
	var countdown := feed.get_snapshot()
	_check(
		StringName(countdown.get(&"source", &"")) == &"RACE CONTROL"
			and str(countdown.get(&"text", "")) == "3",
		"Countdown audio did not produce an important race-control caption"
	)
	feed.clear()
	audio.set("_last_interface_feedback_usec", -1_000_000)
	audio.call(&"_on_interface_feedback_requested", &"NAVIGATE", &"SETTINGS_VALUE")
	_check(
		not bool(feed.get_snapshot().get(&"visible", true)),
		"Routine visible navigation produced a redundant caption that can obscure Settings"
	)
	feed.clear()
	audio.set("_last_interface_feedback_usec", -1_000_000)
	audio.call(&"_on_interface_feedback_requested", &"DENIED", &"LOCKED_BIKE")
	var denied := feed.get_snapshot()
	_check(
		StringName(denied.get(&"source", &"")) == &"INTERFACE"
			and str(denied.get(&"text", "")).contains("ACTION UNAVAILABLE")
			and str(denied.get(&"text", "")).contains("LOCKED BIKE"),
		"Denied interface audio did not explain the inaccessible action"
	)
	_check(store.save_to_disk(), "Caption preferences did not save")
	var restored := SettingsStore.new(TEST_PATH)
	_check(bool(restored.load_from_disk().get(&"ok", false)), "Caption preferences did not reload")
	_check(
		str(restored.get_value(&"interface", &"caption_detail", "")) == "ALL"
			and is_equal_approx(float(restored.get_value(&"interface", &"caption_scale", 0.0)), 1.5)
			and str(restored.get_value(&"interface", &"caption_style", "")) == "HIGH_CONTRAST",
		"Caption preferences changed on reload"
	)

	_check(store.set_value(&"interface", &"caption_detail", "OFF"), "Caption Off mode was rejected")
	service.call(&"_apply_settings")
	EventBus.audio_caption_requested.emit(&"COMMENTARY", "MUST STAY HIDDEN", 2)
	_check(not bool(feed.get_snapshot().get(&"visible", true)), "Off mode did not clear and suppress captions")
	audio.queue_free()
	await get_tree().process_frame
	print("AUDIO CAPTION ACCESSIBILITY PROBE: migrated=%s controls=%d/%d/%d important=true repeat=%d all=true font=%d commentary=true countdown=true denied=true persisted=true passed=%s" % [
		str(bool(load.get(&"migrated", false))),
		detail_index,
		scale_index,
		style_index,
		int(repeated.get(&"repeat_count", 0)),
		int(all_mode.get(&"font_size", 0)),
		str(_failures.is_empty()),
	])
	await _finish(service)


func _finish(service: RaceServices) -> void:
	service.queue_free()
	await get_tree().process_frame
	_cleanup()
	if _failures.is_empty():
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("AUDIO CAPTION ACCESSIBILITY PROBE: " + failure)
	get_tree().quit(1)


func _find_setting_index(items: Array, key: StringName) -> int:
	for index: int in items.size():
		if StringName((items[index] as Dictionary).get(&"key", &"")) == key:
			return index
	return -1


func _write_legacy_settings() -> void:
	var values := SettingsStore.DEFAULTS.duplicate(true)
	var interface := values.get("interface", {}) as Dictionary
	interface.erase("caption_detail")
	interface.erase("caption_scale")
	interface.erase("caption_style")
	var base_dir := TEST_PATH.get_base_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(base_dir))
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": LEGACY_VERSION, "values": values}))
	file.close()


func _cleanup() -> void:
	for suffix: String in ["", SettingsStore.BACKUP_SUFFIX, SettingsStore.TEMP_SUFFIX, SettingsStore.BACKUP_TEMP_SUFFIX]:
		var path := TEST_PATH + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
