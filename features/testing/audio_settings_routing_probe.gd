extends Node
## Headless contract for honest category controls, exact mute, and v3 cleanup.

const TEST_PATH := "user://tests/audio_settings_routing_probe.json"
const LEGACY_PATH := "user://tests/audio_settings_routing_v3_probe.json"

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_cleanup()
	var topology := GameplayAudio.ensure_audio_buses()
	_expect(int(topology.get(&"music", -1)) >= 0, "Music bus is missing")
	_expect(int(topology.get(&"feedback", -1)) >= 0, "SFX bus is missing")
	_expect(int(topology.get(&"engine", -1)) >= 0, "Engine bus is missing")
	_expect(
		int(topology.get(&"feedback", -1)) != int(topology.get(&"engine", -1)),
		"Engine and effects are still sharing one bus"
	)

	var service := RaceServices.new()
	service.settings = SettingsStore.new(TEST_PATH)
	add_child(service)
	await get_tree().process_frame
	_expect(service.settings.set_value(&"audio", &"master_volume", 0.60), "Master setting rejected a valid value")
	_expect(service.settings.set_value(&"audio", &"music_volume", 0.40), "Music setting rejected a valid value")
	_expect(service.settings.set_value(&"audio", &"engine_volume", 0.25), "Engine setting rejected a valid value")
	_expect(service.settings.set_value(&"audio", &"effects_volume", 0.80), "Effects setting rejected a valid value")
	service.call(&"_apply_settings")
	_expect(_bus_matches(&"Master", 0.60, false), "Master volume was not applied")
	_expect(_bus_matches(&"Music", 0.40, false), "Music volume was not applied")
	_expect(_bus_matches(&"Engine", 0.25, false), "Engine volume was not independently applied")
	_expect(_bus_matches(&"SFX", 0.80, false), "Effects volume was not independently applied")

	_expect(service.settings.set_value(&"audio", &"engine_volume", 0.0), "Engine setting rejected exact zero")
	service.call(&"_apply_settings")
	_expect(_bus_matches(&"Engine", 0.0, true), "0% Engine did not exactly mute its bus")
	_expect(_bus_matches(&"SFX", 0.80, false), "Muting Engine also muted Effects")
	_expect(service.settings.set_value(&"audio", &"engine_volume", 0.35), "Engine setting rejected unmute value")
	service.call(&"_apply_settings")
	_expect(_bus_matches(&"Engine", 0.35, false), "Raising Engine above 0% did not unmute it")

	_expect(not service.settings.set_value(&"audio", &"voice_volume", 0.5), "Dormant Voice preference is still writable")
	_expect(not service.settings.set_value(&"audio", &"crowd_volume", 0.5), "Dormant Crowd preference is still writable")
	_expect(service.settings.save_to_disk(), "Independent audio settings did not persist")
	var restored := SettingsStore.new(TEST_PATH)
	_expect(bool(restored.load_from_disk().get(&"ok", false)), "Independent audio settings did not reload")
	_expect(is_equal_approx(float(restored.get_value(&"audio", &"engine_volume", -1.0)), 0.35), "Engine volume changed on reload")
	_expect(is_equal_approx(float(restored.get_value(&"audio", &"effects_volume", -1.0)), 0.80), "Effects volume changed on reload")

	_write_v3_fixture()
	var migrated := SettingsStore.new(LEGACY_PATH)
	var migration := migrated.load_from_disk()
	var migrated_audio := migrated.values.get("audio", {}) as Dictionary
	_expect(bool(migration.get(&"ok", false)) and bool(migration.get(&"migrated", false)), "Version-3 audio settings were not migrated")
	_expect(is_equal_approx(float(migrated_audio.get("engine_volume", -1.0)), 0.31), "Migration lost Engine volume")
	_expect(is_equal_approx(float(migrated_audio.get("effects_volume", -1.0)), 0.63), "Migration lost Effects volume")
	_expect(not migrated_audio.has("voice_volume") and not migrated_audio.has("crowd_volume"), "Migration retained preferences with no sound sources")

	if _failures.is_empty():
		print("AUDIO_SETTINGS_ROUTING_PROBE PASS engine=Engine effects=SFX exact_mute=true migrated_v3=true")
	else:
		for failure: String in _failures:
			push_error("AUDIO_SETTINGS_ROUTING_PROBE: %s" % failure)
	service.queue_free()
	await get_tree().process_frame
	_cleanup()
	get_tree().quit(0 if _failures.is_empty() else 1)


func _bus_matches(bus_name: StringName, linear: float, muted: bool) -> bool:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0 or AudioServer.is_bus_mute(index) != muted:
		return false
	var expected_db := linear_to_db(maxf(linear, 0.0001))
	return is_equal_approx(AudioServer.get_bus_volume_db(index), expected_db)


func _write_v3_fixture() -> void:
	var legacy_values := SettingsStore.DEFAULTS.duplicate(true)
	var audio := legacy_values.get("audio", {}) as Dictionary
	audio["engine_volume"] = 0.31
	audio["effects_volume"] = 0.63
	audio["voice_volume"] = 0.44
	audio["crowd_volume"] = 0.27
	legacy_values["audio"] = audio
	var absolute := ProjectSettings.globalize_path(LEGACY_PATH)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var file := FileAccess.open(LEGACY_PATH, FileAccess.WRITE)
	if file == null:
		_expect(false, "Could not create the version-3 migration fixture")
		return
	file.store_string(JSON.stringify({"version": 3, "values": legacy_values}, "\t"))
	file.close()


func _cleanup() -> void:
	for base_path: String in [TEST_PATH, LEGACY_PATH]:
		for suffix: String in ["", SettingsStore.TEMP_SUFFIX, SettingsStore.BACKUP_SUFFIX, SettingsStore.BACKUP_TEMP_SUFFIX]:
			var path := base_path + suffix
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _expect(condition: bool, failure: String) -> void:
	if not condition:
		_failures.append(failure)
