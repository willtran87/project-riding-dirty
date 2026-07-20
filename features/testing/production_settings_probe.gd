extends Node
## Deterministic contract for the production settings surface and dual-device rebinding.

const TEST_PATH := "user://tests/production_settings_probe.json"

const EXPECTED_ACTIONS: Array[StringName] = [
	&"throttle", &"brake", &"steer_left", &"steer_right", &"lean_forward", &"lean_back",
	&"preload", &"flow_boost", &"racecraft_technique", &"reset_bike", &"restart_run", &"open_garage", &"pause_game",
	&"open_settings", &"toggle_replay", &"toggle_photo_mode", &"spectator_next",
	&"garage_left", &"garage_right", &"confirm_selection", &"open_workshop", &"continue_weekend",
	&"event_previous", &"event_next", &"repair_bike", &"toggle_assist",
	&"menu_left", &"menu_right", &"page_previous", &"page_next", &"reset_setting", &"reset_all_settings",
	&"results_first", &"results_last",
	&"photo_forward", &"photo_back", &"photo_left", &"photo_right", &"photo_down", &"photo_up",
	&"photo_look_left", &"photo_look_right", &"photo_look_up", &"photo_look_down",
]

const EXPECTED_CONTEXTS: Dictionary = {
	&"throttle": [&"RIDE"],
	&"brake": [&"RIDE"],
	&"steer_left": [&"RIDE"],
	&"steer_right": [&"RIDE"],
	&"lean_forward": [&"RIDE"],
	&"lean_back": [&"RIDE"],
	&"preload": [&"RIDE"],
	&"flow_boost": [&"RIDE"],
	&"racecraft_technique": [&"RIDE"],
	&"reset_bike": [&"RIDE"],
	&"restart_run": [&"RIDE", &"RESULTS", &"REPLAY"],
	&"open_garage": [&"RIDE", &"RESULTS", &"REPLAY", &"WORKSHOP"],
	&"pause_game": [&"GLOBAL"],
	&"open_settings": [&"GLOBAL"],
	&"toggle_replay": [&"RESULTS", &"REPLAY", &"PHOTO"],
	&"toggle_photo_mode": [&"RIDE", &"RESULTS", &"REPLAY", &"PHOTO"],
	&"spectator_next": [&"REPLAY", &"PHOTO"],
	&"garage_left": [&"GARAGE", &"WORKSHOP"],
	&"garage_right": [&"GARAGE", &"WORKSHOP"],
	&"confirm_selection": [&"GARAGE", &"WORKSHOP", &"SETTINGS"],
	&"open_workshop": [&"GARAGE", &"WORKSHOP"],
	&"continue_weekend": [&"GARAGE"],
	&"event_previous": [&"GARAGE", &"WORKSHOP", &"RESULTS", &"SETTINGS"],
	&"event_next": [&"GARAGE", &"WORKSHOP", &"RESULTS", &"SETTINGS"],
	&"repair_bike": [&"GARAGE", &"WORKSHOP"],
	&"toggle_assist": [&"GARAGE"],
	&"menu_left": [&"SETTINGS"],
	&"menu_right": [&"SETTINGS"],
	&"page_previous": [&"RESULTS", &"SETTINGS"],
	&"page_next": [&"RESULTS", &"SETTINGS"],
	&"reset_setting": [&"SETTINGS"],
	&"reset_all_settings": [&"SETTINGS"],
	&"results_first": [&"RESULTS"],
	&"results_last": [&"RESULTS"],
	&"photo_forward": [&"PHOTO"],
	&"photo_back": [&"PHOTO"],
	&"photo_left": [&"PHOTO"],
	&"photo_right": [&"PHOTO"],
	&"photo_down": [&"PHOTO"],
	&"photo_up": [&"PHOTO"],
	&"photo_look_left": [&"PHOTO"],
	&"photo_look_right": [&"PHOTO"],
	&"photo_look_up": [&"PHOTO"],
	&"photo_look_down": [&"PHOTO"],
}

# Descriptors are exact and ordered: KEY physical_keycode, BUTTON index, or
# AXIS index/direction. All defaults must use device -1 and no modifiers.
const EXPECTED_DEFAULT_BINDINGS: Dictionary = {
	&"throttle": [[&"KEY", KEY_W], [&"AXIS", JOY_AXIS_TRIGGER_RIGHT, 1]],
	&"brake": [[&"KEY", KEY_S], [&"AXIS", JOY_AXIS_TRIGGER_LEFT, 1]],
	&"steer_left": [[&"KEY", KEY_A], [&"AXIS", JOY_AXIS_LEFT_X, -1]],
	&"steer_right": [[&"KEY", KEY_D], [&"AXIS", JOY_AXIS_LEFT_X, 1]],
	&"lean_forward": [[&"KEY", KEY_UP], [&"AXIS", JOY_AXIS_RIGHT_Y, -1]],
	&"lean_back": [[&"KEY", KEY_DOWN], [&"AXIS", JOY_AXIS_RIGHT_Y, 1]],
	&"preload": [[&"KEY", KEY_SPACE], [&"BUTTON", JOY_BUTTON_A]],
	&"flow_boost": [[&"KEY", KEY_SHIFT], [&"BUTTON", JOY_BUTTON_LEFT_SHOULDER]],
	&"racecraft_technique": [[&"KEY", KEY_C], [&"BUTTON", JOY_BUTTON_RIGHT_SHOULDER]],
	&"reset_bike": [[&"KEY", KEY_R], [&"BUTTON", JOY_BUTTON_Y]],
	&"restart_run": [[&"KEY", KEY_ENTER], [&"BUTTON", JOY_BUTTON_X]],
	&"open_garage": [[&"KEY", KEY_G], [&"BUTTON", JOY_BUTTON_B]],
	&"pause_game": [[&"KEY", KEY_ESCAPE], [&"BUTTON", JOY_BUTTON_START]],
	&"open_settings": [[&"KEY", KEY_F1], [&"BUTTON", JOY_BUTTON_BACK]],
	&"toggle_replay": [[&"KEY", KEY_V], [&"BUTTON", JOY_BUTTON_A]],
	&"toggle_photo_mode": [[&"KEY", KEY_P], [&"BUTTON", JOY_BUTTON_LEFT_STICK]],
	&"spectator_next": [[&"KEY", KEY_TAB], [&"BUTTON", JOY_BUTTON_RIGHT_STICK]],
	&"garage_left": [[&"KEY", KEY_Q], [&"KEY", KEY_LEFT], [&"BUTTON", JOY_BUTTON_DPAD_LEFT]],
	&"garage_right": [[&"KEY", KEY_E], [&"KEY", KEY_RIGHT], [&"BUTTON", JOY_BUTTON_DPAD_RIGHT]],
	&"confirm_selection": [[&"KEY", KEY_ENTER], [&"BUTTON", JOY_BUTTON_A]],
	&"open_workshop": [[&"KEY", KEY_TAB], [&"BUTTON", JOY_BUTTON_X]],
	&"continue_weekend": [[&"KEY", KEY_C], [&"BUTTON", JOY_BUTTON_Y]],
	&"event_previous": [[&"KEY", KEY_W], [&"KEY", KEY_UP], [&"BUTTON", JOY_BUTTON_DPAD_UP]],
	&"event_next": [[&"KEY", KEY_S], [&"KEY", KEY_DOWN], [&"BUTTON", JOY_BUTTON_DPAD_DOWN]],
	&"repair_bike": [[&"KEY", KEY_F], [&"BUTTON", JOY_BUTTON_RIGHT_SHOULDER]],
	&"toggle_assist": [[&"KEY", KEY_H], [&"BUTTON", JOY_BUTTON_LEFT_STICK]],
	&"menu_left": [[&"KEY", KEY_LEFT], [&"BUTTON", JOY_BUTTON_DPAD_LEFT]],
	&"menu_right": [[&"KEY", KEY_RIGHT], [&"BUTTON", JOY_BUTTON_DPAD_RIGHT]],
	&"page_previous": [[&"KEY", KEY_Q], [&"KEY", KEY_PAGEUP], [&"BUTTON", JOY_BUTTON_LEFT_SHOULDER]],
	&"page_next": [[&"KEY", KEY_E], [&"KEY", KEY_PAGEDOWN], [&"KEY", KEY_TAB], [&"BUTTON", JOY_BUTTON_RIGHT_SHOULDER]],
	&"reset_setting": [[&"KEY", KEY_DELETE], [&"KEY", KEY_BACKSPACE], [&"BUTTON", JOY_BUTTON_X]],
	&"reset_all_settings": [[&"KEY", KEY_HOME], [&"BUTTON", JOY_BUTTON_Y]],
	&"results_first": [[&"KEY", KEY_HOME]],
	&"results_last": [[&"KEY", KEY_END]],
	&"photo_forward": [[&"KEY", KEY_W], [&"AXIS", JOY_AXIS_LEFT_Y, -1]],
	&"photo_back": [[&"KEY", KEY_S], [&"AXIS", JOY_AXIS_LEFT_Y, 1]],
	&"photo_left": [[&"KEY", KEY_A], [&"AXIS", JOY_AXIS_LEFT_X, -1]],
	&"photo_right": [[&"KEY", KEY_D], [&"AXIS", JOY_AXIS_LEFT_X, 1]],
	&"photo_down": [[&"KEY", KEY_Q], [&"AXIS", JOY_AXIS_TRIGGER_LEFT, 1]],
	&"photo_up": [[&"KEY", KEY_E], [&"AXIS", JOY_AXIS_TRIGGER_RIGHT, 1]],
	&"photo_look_left": [[&"KEY", KEY_LEFT], [&"AXIS", JOY_AXIS_RIGHT_X, -1]],
	&"photo_look_right": [[&"KEY", KEY_RIGHT], [&"AXIS", JOY_AXIS_RIGHT_X, 1]],
	&"photo_look_up": [[&"KEY", KEY_UP], [&"AXIS", JOY_AXIS_RIGHT_Y, -1]],
	&"photo_look_down": [[&"KEY", KEY_DOWN], [&"AXIS", JOY_AXIS_RIGHT_Y, 1]],
}

var _passed := true
var _binding_notification_count := 0
var _last_binding_actions: Array[StringName] = []
var _input_map_snapshot: Dictionary = {}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_cleanup_test_file()
	_input_map_snapshot = _snapshot_input_map(EXPECTED_ACTIONS)
	var service := RaceServices.new()
	service.settings = SettingsStore.new(TEST_PATH)
	add_child(service)
	await get_tree().process_frame
	service.call(&"_snapshot_default_bindings")
	_assert_exact_action_contract()
	_assert_exact_default_bindings()
	_assert_context_conflict_matrix()

	service.set("_settings_page_index", RaceServices.SETTINGS_PAGE_IDS.find(&"AUDIO"))
	service.call(&"_refresh_settings_text")
	var audio_items: Array = service.get("_settings_items") as Array
	_check(audio_items.size() == 4, "audio page must expose Master, Music, Engine, and Effects")
	var expected_audio_keys: Array[StringName] = [
		&"master_volume", &"music_volume", &"engine_volume", &"effects_volume",
	]
	var expected_audio_labels := [
		"MASTER VOLUME", "MUSIC VOLUME", "ENGINE VOLUME", "EFFECTS VOLUME",
	]
	for index: int in expected_audio_keys.size():
		_check(
			StringName((audio_items[index] as Dictionary).get(&"key", &"")) == expected_audio_keys[index],
			"audio setting order or category is dishonest at row %d" % index
		)
		_check(
			str((audio_items[index] as Dictionary).get(&"label", "")) == expected_audio_labels[index],
			"audio setting label is dishonest at row %d" % index
		)
	service.set("_settings_index", 0)
	service.call(&"_adjust_setting", -1)
	_check(is_equal_approx(float(service.settings.get_value(&"audio", &"master_volume", 0.0)), 0.95), "master volume did not change in 5% steps")
	service.set("_settings_index", 2)
	service.call(&"_adjust_setting", -1)
	_check(is_equal_approx(float(service.settings.get_value(&"audio", &"engine_volume", 0.0)), 0.95), "engine row did not adjust Engine in 5% steps")
	_check(is_equal_approx(float(service.settings.get_value(&"audio", &"effects_volume", 0.0)), 0.9), "engine row also changed Effects")
	service.set("_settings_index", 3)
	service.call(&"_adjust_setting", -1)
	_check(is_equal_approx(float(service.settings.get_value(&"audio", &"effects_volume", 0.0)), 0.85), "effects row did not adjust Effects in 5% steps")
	_check(is_equal_approx(float(service.settings.get_value(&"audio", &"engine_volume", 0.0)), 0.95), "effects row also changed Engine")

	service.set("_settings_page_index", RaceServices.SETTINGS_PAGE_IDS.find(&"RIDE"))
	service.call(&"_refresh_settings_text")
	var ride_items: Array = service.get("_settings_items") as Array
	_check(ride_items.size() >= 7, "ride page is missing deadzones or feedback controls")
	_check(ride_items[0].get(&"key", &"") == &"steering_deadzone", "steering deadzone is not player-facing")
	var difficulty_index := -1
	for index: int in ride_items.size():
		if StringName((ride_items[index] as Dictionary).get(&"key", &"")) == &"race_difficulty":
			difficulty_index = index
			break
	_check(difficulty_index >= 0, "ride page is missing race difficulty")
	if difficulty_index >= 0:
		var active_race := RaceController.new()
		active_race.state = RaceController.State.RACING
		service.race = active_race
		service.set("_settings_index", difficulty_index)
		service.call(&"_adjust_setting", 1)
		_check(
			String(service.get("_settings_message")).contains("APPLIES NEXT EVENT"),
			"an in-race difficulty change did not explain its deferred activation"
		)
		service.race = null
		active_race.free()

	service.set("_settings_page_index", RaceServices.SETTINGS_PAGE_IDS.find(&"INPUT"))
	service.call(&"_refresh_settings_text")
	var input_items: Array = service.get("_settings_items") as Array
	var touch_setting_keys: Array[StringName] = [
		&"touch_controls", &"touch_handedness", &"touch_control_scale", &"touch_control_opacity",
	]
	_check(
		input_items.size() == RaceServices.REBINDABLE_ACTIONS.size() + touch_setting_keys.size(),
		"Input page does not expose touch settings and every remappable action"
	)
	for index: int in touch_setting_keys.size():
		_check(
			StringName(input_items[index].get(&"key", &"")) == touch_setting_keys[index],
			"Input page touch setting order is unstable"
		)
	var binding_count := 0
	for item: Dictionary in input_items:
		if StringName(item.get(&"kind", &"")) == &"BINDING":
			binding_count += 1
	_check(binding_count == 44, "Input page must expose the exact 44-action semantic inventory")
	var replay_events := InputMap.action_get_events(InputRouter.TOGGLE_REPLAY)
	_check(_has_gamepad_button(replay_events, JOY_BUTTON_A), "default replay action has no contextual gamepad binding")
	_check(
		not _has_gamepad_button(replay_events, JOY_BUTTON_DPAD_UP),
		"default replay binding collides with Results/Garage D-pad navigation"
	)
	var photo_events := InputMap.action_get_events(InputRouter.TOGGLE_PHOTO_MODE)
	_check(_has_gamepad_button(photo_events, JOY_BUTTON_LEFT_STICK), "default photo action has no contextual stick-click binding")
	service.settings.capture_input_map(EXPECTED_ACTIONS)
	_check(service.settings.save_to_disk(), "exact default binding inventory did not save atomically")
	var persisted_defaults := SettingsStore.new(TEST_PATH)
	_check(bool(persisted_defaults.load_from_disk().get("ok", false)), "exact default binding inventory did not reload")
	_assert_persisted_default_bindings(persisted_defaults)
	var default_saved_bindings := (
		service.settings.values.get("bindings", {}) as Dictionary
	).duplicate(true)

	var legacy_bindings := default_saved_bindings.duplicate(true)
	var legacy_replay_key := InputEventKey.new()
	legacy_replay_key.physical_keycode = KEY_V
	legacy_bindings[String(InputRouter.TOGGLE_REPLAY)] = [SettingsStore.serialize_binding(legacy_replay_key)]
	_install_saved_bindings(service.settings, legacy_bindings, "legacy replay")
	service.call(&"_merge_missing_default_bindings")
	_check(
		_has_gamepad_button(service.settings.bindings_for_action(InputRouter.TOGGLE_REPLAY), JOY_BUTTON_A),
		"keyboard-only saved replay binding did not migrate to contextual gamepad A"
	)
	var custom_replay_key := InputEventKey.new()
	custom_replay_key.physical_keycode = KEY_F9
	legacy_bindings = default_saved_bindings.duplicate(true)
	legacy_bindings[String(InputRouter.TOGGLE_REPLAY)] = [SettingsStore.serialize_binding(custom_replay_key)]
	_install_saved_bindings(service.settings, legacy_bindings, "custom replay")
	service.call(&"_merge_missing_default_bindings")
	var custom_replay_events := service.settings.bindings_for_action(InputRouter.TOGGLE_REPLAY)
	_check(_has_physical_key(custom_replay_events, KEY_F9), "custom keyboard replay binding was replaced")
	_check(
		not _has_gamepad_button(custom_replay_events, JOY_BUTTON_A),
		"custom keyboard-only replay binding was force-migrated"
	)

	var legacy_photo_key := InputEventKey.new()
	legacy_photo_key.physical_keycode = KEY_P
	var legacy_photo_bindings := default_saved_bindings.duplicate(true)
	legacy_photo_bindings[String(InputRouter.TOGGLE_PHOTO_MODE)] = [SettingsStore.serialize_binding(legacy_photo_key)]
	_install_saved_bindings(service.settings, legacy_photo_bindings, "legacy photo")
	service.call(&"_merge_missing_default_bindings")
	var migrated_photo_events := service.settings.bindings_for_action(InputRouter.TOGGLE_PHOTO_MODE)
	_check(_has_physical_key(migrated_photo_events, KEY_P), "legacy photo P binding was not preserved")
	_check(
		_has_gamepad_button(migrated_photo_events, JOY_BUTTON_LEFT_STICK),
		"exact legacy photo P binding did not migrate to contextual L3"
	)
	_check(migrated_photo_events.size() == 2, "legacy photo migration did not produce exactly P plus L3")
	var migrated_photo_disk := SettingsStore.new(TEST_PATH)
	_check(bool(migrated_photo_disk.load_from_disk().get("ok", false)), "migrated photo binding did not reload")
	_check(
		_binding_descriptors(migrated_photo_disk.bindings_for_action(InputRouter.TOGGLE_PHOTO_MODE))
		== [[&"KEY", KEY_P], [&"BUTTON", JOY_BUTTON_LEFT_STICK]],
		"legacy photo migration was not persisted exactly"
	)

	var conflicting_photo_bindings := default_saved_bindings.duplicate(true)
	conflicting_photo_bindings[String(InputRouter.TOGGLE_PHOTO_MODE)] = [SettingsStore.serialize_binding(legacy_photo_key)]
	var conflicting_l3 := InputEventJoypadButton.new()
	conflicting_l3.button_index = JOY_BUTTON_LEFT_STICK
	var replay_with_conflict := (
		conflicting_photo_bindings[String(InputRouter.TOGGLE_REPLAY)] as Array
	).duplicate(true)
	replay_with_conflict.append(SettingsStore.serialize_binding(conflicting_l3))
	conflicting_photo_bindings[String(InputRouter.TOGGLE_REPLAY)] = replay_with_conflict
	_install_saved_bindings(service.settings, conflicting_photo_bindings, "photo migration conflict")
	service.call(&"_merge_missing_default_bindings")
	var blocked_photo_events := service.settings.bindings_for_action(InputRouter.TOGGLE_PHOTO_MODE)
	_check(
		_binding_descriptors(blocked_photo_events) == [[&"KEY", KEY_P]],
		"same-context L3 conflict did not preserve the exact legacy photo binding"
	)
	_check(
		_has_gamepad_button(service.settings.bindings_for_action(InputRouter.TOGGLE_REPLAY), JOY_BUTTON_LEFT_STICK),
		"photo migration conflict handling mutated the existing replay L3 binding"
	)
	var blocked_photo_disk := SettingsStore.new(TEST_PATH)
	_check(bool(blocked_photo_disk.load_from_disk().get("ok", false)), "conflict-preserved photo bindings did not reload")
	_check(
		_binding_descriptors(blocked_photo_disk.bindings_for_action(InputRouter.TOGGLE_PHOTO_MODE)) == [[&"KEY", KEY_P]],
		"conflict-preserved legacy photo binding changed on disk"
	)

	var custom_photo_key := InputEventKey.new()
	custom_photo_key.physical_keycode = KEY_F8
	var custom_photo_bindings := default_saved_bindings.duplicate(true)
	custom_photo_bindings[String(InputRouter.TOGGLE_PHOTO_MODE)] = [SettingsStore.serialize_binding(custom_photo_key)]
	_install_saved_bindings(service.settings, custom_photo_bindings, "custom photo")
	service.call(&"_merge_missing_default_bindings")
	var custom_photo_events := service.settings.bindings_for_action(InputRouter.TOGGLE_PHOTO_MODE)
	_check(
		_binding_descriptors(custom_photo_events) == [[&"KEY", KEY_F8]],
		"custom photo binding was replaced or force-migrated"
	)
	var custom_photo_disk := SettingsStore.new(TEST_PATH)
	_check(bool(custom_photo_disk.load_from_disk().get("ok", false)), "custom photo binding did not reload")
	_check(
		_binding_descriptors(custom_photo_disk.bindings_for_action(InputRouter.TOGGLE_PHOTO_MODE)) == [[&"KEY", KEY_F8]],
		"custom photo binding was not preserved exactly on disk"
	)

	# Return the isolated store to the exact live defaults before exercising the
	# production commit path. Migration tests intentionally never apply to InputMap.
	service.settings.capture_input_map(EXPECTED_ACTIONS)

	var cross_context_key := InputEventKey.new()
	cross_context_key.physical_keycode = KEY_SPACE
	var global_conflicts := service.settings.find_conflicts(InputRouter.CONFIRM, cross_context_key)
	_check(
		_conflicts_include(global_conflicts, InputRouter.PRELOAD),
		"backward-compatible global conflict lookup did not find Ride preload on Space"
	)
	var confirm_conflict_scope := InputRouter.get_conflicting_actions(
		InputRouter.CONFIRM, EXPECTED_ACTIONS
	)
	var scoped_conflicts := service.settings.find_conflicts(
		InputRouter.CONFIRM, cross_context_key, confirm_conflict_scope
	)
	_check(
		not _conflicts_include(scoped_conflicts, InputRouter.PRELOAD) and scoped_conflicts.is_empty(),
		"context-scoped conflict lookup rejected legal Ride/Garage Space reuse"
	)
	var same_context_key := InputEventKey.new()
	same_context_key.physical_keycode = KEY_UP
	var event_next_scope := InputRouter.get_conflicting_actions(
		InputRouter.EVENT_NEXT, EXPECTED_ACTIONS
	)
	var same_context_conflicts := service.settings.find_conflicts(
		InputRouter.EVENT_NEXT, same_context_key, event_next_scope
	)
	_check(
		_conflicts_include(same_context_conflicts, InputRouter.EVENT_PREVIOUS),
		"context-scoped conflict lookup missed Event Previous on Up"
	)
	_check(
		not _conflicts_include(same_context_conflicts, InputRouter.LEAN_FORWARD)
		and not _conflicts_include(same_context_conflicts, InputRouter.PHOTO_LOOK_UP),
		"context-scoped conflict lookup leaked disjoint Ride or Photo actions"
	)

	InputRouter.bindings_changed.connect(_on_bindings_changed)
	var notifications_before_cross_context := _binding_notification_count
	service.call(&"_commit_captured_binding", InputRouter.CONFIRM, cross_context_key)
	_check(
		_binding_descriptors(InputMap.action_get_events(InputRouter.CONFIRM))
		== [[&"BUTTON", JOY_BUTTON_A], [&"KEY", KEY_SPACE]],
		"production commit path rejected legal Ride/Garage Space reuse"
	)
	_check(
		_binding_descriptors(service.settings.bindings_for_action(InputRouter.CONFIRM))
		== [[&"BUTTON", JOY_BUTTON_A], [&"KEY", KEY_SPACE]],
		"legal cross-context commit did not persist the exact merged binding"
	)
	_check(
		_binding_notification_count == notifications_before_cross_context + 1
		and _last_binding_actions == [InputRouter.CONFIRM],
		"legal cross-context commit did not emit one exact binding notification"
	)

	var event_next_map_before := _binding_descriptors(InputMap.action_get_events(InputRouter.EVENT_NEXT))
	var event_next_store_before := _binding_descriptors(
		service.settings.bindings_for_action(InputRouter.EVENT_NEXT)
	)
	var notifications_before_rejection := _binding_notification_count
	service.call(&"_commit_captured_binding", InputRouter.EVENT_NEXT, same_context_key)
	_check(
		_binding_descriptors(InputMap.action_get_events(InputRouter.EVENT_NEXT)) == event_next_map_before,
		"same-context rejected commit partially mutated InputMap"
	)
	_check(
		_binding_descriptors(service.settings.bindings_for_action(InputRouter.EVENT_NEXT)) == event_next_store_before,
		"same-context rejected commit partially mutated persisted settings"
	)
	_check(
		_binding_notification_count == notifications_before_rejection,
		"same-context rejected commit emitted a false binding notification"
	)
	_check(
		String(service.get("_settings_message")).contains("EVENT PREVIOUS"),
		"same-context rejection did not identify the authoritative conflicting action"
	)

	var replacement := InputEventKey.new()
	replacement.physical_keycode = KEY_F10
	var notifications_before_commit := _binding_notification_count
	service.call(&"_commit_captured_binding", InputRouter.THROTTLE, replacement)
	var throttle_events := InputMap.action_get_events(InputRouter.THROTTLE)
	_check(_has_physical_key(throttle_events, KEY_F10), "keyboard throttle replacement was not applied")
	_check(not _has_physical_key(throttle_events, KEY_W), "keyboard rebind retained the replaced key")
	_check(_has_gamepad_axis(throttle_events), "keyboard rebind discarded the gamepad throttle binding")
	_check(
		_binding_notification_count == notifications_before_commit + 1
		and _last_binding_actions == [InputRouter.THROTTLE],
		"successful runtime rebind did not emit one exact prompt invalidation"
	)

	service.call(&"_restore_default_binding", InputRouter.THROTTLE)
	_check(_has_physical_key(InputMap.action_get_events(InputRouter.THROTTLE), KEY_W), "per-action reset did not restore the default key")
	service.call(&"_reset_all_settings")
	_check(is_equal_approx(float(service.settings.get_value(&"audio", &"master_volume", 0.0)), 1.0), "reset all did not restore audio defaults")
	_assert_exact_default_bindings()

	var panel := service.get("_settings_panel") as PanelContainer
	var rows: Array = service.get("_settings_row_buttons") as Array
	_check(panel != null and panel.offset_right - panel.offset_left >= 1000.0, "settings panel is not production-sized")
	_check(not rows.is_empty(), "settings surface did not build mouse-selectable rows")
	_check(service.settings.save_to_disk(), "settings did not persist atomically")
	var restored := SettingsStore.new(TEST_PATH)
	_check(bool(restored.load_from_disk().get("ok", false)), "persisted settings did not reload")

	service.queue_free()
	await get_tree().process_frame
	if InputRouter.bindings_changed.is_connected(_on_bindings_changed):
		InputRouter.bindings_changed.disconnect(_on_bindings_changed)
	_restore_input_map(_input_map_snapshot)
	_check(
		_input_map_matches_snapshot(_input_map_snapshot),
		"probe teardown did not restore the complete pre-test InputMap atomically"
	)
	print("PRODUCTION SETTINGS PROBE: pages=%d bindings=%d contexts=%d persisted=%s restored=%s passed=%s" % [
		RaceServices.SETTINGS_PAGE_IDS.size(), binding_count, EXPECTED_CONTEXTS.size(),
		str(FileAccess.file_exists(TEST_PATH)), str(_input_map_matches_snapshot(_input_map_snapshot)), str(_passed),
	])
	_cleanup_test_file()
	get_tree().quit(0 if _passed else 1)


func _assert_exact_action_contract() -> void:
	_check(EXPECTED_ACTIONS.size() == 44, "probe authority must enumerate exactly 44 actions")
	_check(
		_name_arrays_equal(RaceServices.REBINDABLE_ACTIONS, EXPECTED_ACTIONS),
		"RaceServices remappable action inventory or order drifted from the exact 44-action contract"
	)
	var unique_actions: Dictionary = {}
	for action: StringName in EXPECTED_ACTIONS:
		unique_actions[String(action)] = true
	_check(unique_actions.size() == 44, "44-action semantic inventory contains duplicate names")
	_check(
		_sorted_dictionary_keys(InputRouter.ACTION_CONTEXTS) == _sorted_name_strings(EXPECTED_ACTIONS),
		"context registry keys do not exactly match the remappable action inventory"
	)
	_check(
		_sorted_dictionary_keys(EXPECTED_DEFAULT_BINDINGS) == _sorted_name_strings(EXPECTED_ACTIONS),
		"default binding authority keys do not exactly match the remappable action inventory"
	)
	var known_contexts: Array[StringName] = [
		&"GLOBAL", &"RIDE", &"GARAGE", &"WORKSHOP", &"RESULTS", &"SETTINGS", &"REPLAY", &"PHOTO",
	]
	for action: StringName in EXPECTED_ACTIONS:
		_check(InputMap.has_action(action), "InputMap is missing semantic action %s" % action)
		var expected_contexts := _as_name_array(EXPECTED_CONTEXTS.get(action, []))
		var actual_contexts := InputRouter.get_action_contexts(action)
		_check(
			_name_arrays_equal(actual_contexts, expected_contexts),
			"context membership drifted for %s: expected %s, got %s" % [action, expected_contexts, actual_contexts]
		)
		_check(not actual_contexts.is_empty(), "semantic action %s has no live context" % action)
		var unique_contexts: Dictionary = {}
		for context: StringName in actual_contexts:
			unique_contexts[String(context)] = true
			_check(context in known_contexts, "semantic action %s has unknown context %s" % [action, context])
		_check(
			unique_contexts.size() == actual_contexts.size(),
			"semantic action %s repeats a context" % action
		)


func _assert_exact_default_bindings() -> void:
	for action: StringName in EXPECTED_ACTIONS:
		var expected: Array = EXPECTED_DEFAULT_BINDINGS.get(action, []) as Array
		var events := InputMap.action_get_events(action)
		var actual := _binding_descriptors(events)
		_check(
			actual == expected,
			"default bindings drifted for %s: expected %s, got %s" % [action, expected, actual]
		)
		var unique_descriptors: Dictionary = {}
		for descriptor: Variant in actual:
			unique_descriptors[JSON.stringify(descriptor)] = true
		_check(
			unique_descriptors.size() == actual.size(),
			"default bindings for %s contain duplicate events" % action
		)


func _assert_context_conflict_matrix() -> void:
	for first_index: int in EXPECTED_ACTIONS.size():
		var first := EXPECTED_ACTIONS[first_index]
		var expected_conflicts: Array[StringName] = []
		for second: StringName in EXPECTED_ACTIONS:
			if second != first and _expected_actions_share_context(first, second):
				expected_conflicts.append(second)
		_check(
			_name_arrays_equal(InputRouter.get_conflicting_actions(first, EXPECTED_ACTIONS), expected_conflicts),
			"context-scoped candidate inventory drifted for %s" % first
		)
		for second_index: int in EXPECTED_ACTIONS.size():
			var second := EXPECTED_ACTIONS[second_index]
			var expected_share := _expected_actions_share_context(first, second)
			_check(
				InputRouter.actions_share_context(first, second) == expected_share,
				"context relationship drifted for %s and %s" % [first, second]
			)
			_check(
				InputRouter.actions_share_context(first, second)
				== InputRouter.actions_share_context(second, first),
				"context relationship is asymmetric for %s and %s" % [first, second]
			)
			if second_index <= first_index or not expected_share:
				continue
			for first_event: InputEvent in InputMap.action_get_events(first):
				var first_binding := SettingsStore.serialize_binding(first_event)
				for second_event: InputEvent in InputMap.action_get_events(second):
					var second_binding := SettingsStore.serialize_binding(second_event)
					_check(
						not SettingsStore.bindings_conflict(first_binding, second_binding),
						"default %s/%s bindings collide inside a shared live context" % [first, second]
					)
	_check(
		not InputRouter.actions_share_context(InputRouter.PRELOAD, InputRouter.CONFIRM),
		"Ride preload and Garage/Settings confirm must permit contextual A reuse"
	)
	_check(
		InputRouter.actions_share_context(InputRouter.EVENT_PREVIOUS, InputRouter.EVENT_NEXT),
		"event navigation directions must conflict in their shared contexts"
	)
	_check(
		InputRouter.actions_share_context(InputRouter.PAUSE, InputRouter.PHOTO_FORWARD),
		"GLOBAL actions must conflict with every local context"
	)
	_check(
		InputRouter.actions_share_context(&"unknown_probe_action", InputRouter.THROTTLE),
		"unknown actions must remain conservatively conflict-safe"
	)


func _assert_persisted_default_bindings(store: SettingsStore) -> void:
	var persisted_bindings := store.values.get("bindings", {}) as Dictionary
	_check(
		_sorted_dictionary_keys(persisted_bindings) == _sorted_name_strings(EXPECTED_ACTIONS),
		"persisted binding inventory is not the exact 44-action contract"
	)
	for action: StringName in EXPECTED_ACTIONS:
		var expected: Array = EXPECTED_DEFAULT_BINDINGS.get(action, []) as Array
		_check(
			_binding_descriptors(store.bindings_for_action(action)) == expected,
			"persisted default bindings drifted for %s" % action
		)


func _install_saved_bindings(store: SettingsStore, bindings: Dictionary, label: String) -> void:
	store.values["bindings"] = bindings.duplicate(true)
	_check(store.save_to_disk(), "%s binding fixture did not save atomically" % label)


func _expected_actions_share_context(first: StringName, second: StringName) -> bool:
	if first == second:
		return true
	var first_contexts := _as_name_array(EXPECTED_CONTEXTS.get(first, []))
	var second_contexts := _as_name_array(EXPECTED_CONTEXTS.get(second, []))
	if first_contexts.is_empty() or second_contexts.is_empty():
		return true
	if &"GLOBAL" in first_contexts or &"GLOBAL" in second_contexts:
		return true
	for context: StringName in first_contexts:
		if context in second_contexts:
			return true
	return false


func _binding_descriptors(events: Array[InputEvent]) -> Array:
	var descriptors: Array = []
	for event: InputEvent in events:
		descriptors.append(_binding_descriptor(event))
	return descriptors


func _binding_descriptor(event: InputEvent) -> Array:
	if event is InputEventKey:
		var key := event as InputEventKey
		if (
			key.keycode == KEY_NONE
			and key.physical_keycode != KEY_NONE
			and key.location == KeyLocation.KEY_LOCATION_UNSPECIFIED
			and not key.shift_pressed
			and not key.alt_pressed
			and not key.ctrl_pressed
			and not key.meta_pressed
		):
			return [&"KEY", key.physical_keycode]
		return [
			&"KEY_FULL", key.physical_keycode, key.keycode, key.location,
			key.shift_pressed, key.alt_pressed, key.ctrl_pressed, key.meta_pressed, key.device,
		]
	if event is InputEventJoypadButton:
		var button := event as InputEventJoypadButton
		return [&"BUTTON", button.button_index]
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		if is_equal_approx(absf(motion.axis_value), 1.0):
			return [&"AXIS", motion.axis, -1 if motion.axis_value < 0.0 else 1]
		return [&"AXIS_FULL", motion.axis, motion.axis_value, motion.device]
	return [&"UNSUPPORTED", event.get_class(), event.as_text()]


func _conflicts_include(conflicts: Array, action: StringName) -> bool:
	for raw_conflict: Variant in conflicts:
		if raw_conflict is Dictionary and StringName((raw_conflict as Dictionary).get("action", "")) == action:
			return true
	return false


func _snapshot_input_map(actions: Array[StringName]) -> Dictionary:
	var snapshot: Dictionary = {}
	for action: StringName in actions:
		var entry := {
			"exists": InputMap.has_action(action),
			"deadzone": InputMap.action_get_deadzone(action) if InputMap.has_action(action) else 0.0,
			"events": [],
		}
		if InputMap.has_action(action):
			var event_copies: Array[InputEvent] = []
			for event: InputEvent in InputMap.action_get_events(action):
				event_copies.append(event.duplicate() as InputEvent)
			entry["events"] = event_copies
		snapshot[action] = entry
	return snapshot


func _restore_input_map(snapshot: Dictionary) -> void:
	for raw_action: Variant in snapshot.keys():
		var action := StringName(raw_action)
		var entry := snapshot[raw_action] as Dictionary
		if not bool(entry.get("exists", false)):
			if InputMap.has_action(action):
				InputMap.erase_action(action)
			continue
		if not InputMap.has_action(action):
			InputMap.add_action(action, float(entry.get("deadzone", 0.2)))
		InputMap.action_set_deadzone(action, float(entry.get("deadzone", 0.2)))
		InputMap.action_erase_events(action)
		for raw_event: Variant in entry.get("events", []):
			if raw_event is InputEvent:
				InputMap.action_add_event(action, (raw_event as InputEvent).duplicate() as InputEvent)


func _input_map_matches_snapshot(snapshot: Dictionary) -> bool:
	for raw_action: Variant in snapshot.keys():
		var action := StringName(raw_action)
		var entry := snapshot[raw_action] as Dictionary
		var expected_exists := bool(entry.get("exists", false))
		if InputMap.has_action(action) != expected_exists:
			return false
		if not expected_exists:
			continue
		if not is_equal_approx(
			InputMap.action_get_deadzone(action), float(entry.get("deadzone", 0.2))
		):
			return false
		var expected_serialized: Array = []
		for raw_event: Variant in entry.get("events", []):
			if raw_event is InputEvent:
				expected_serialized.append(SettingsStore.serialize_binding(raw_event as InputEvent))
		var actual_serialized: Array = []
		for event: InputEvent in InputMap.action_get_events(action):
			actual_serialized.append(SettingsStore.serialize_binding(event))
		if actual_serialized != expected_serialized:
			return false
	return true


func _as_name_array(raw_values: Variant) -> Array[StringName]:
	var names: Array[StringName] = []
	if raw_values is Array:
		for raw_value: Variant in raw_values:
			names.append(StringName(raw_value))
	return names


func _name_arrays_equal(first: Array[StringName], second: Array[StringName]) -> bool:
	if first.size() != second.size():
		return false
	for index: int in first.size():
		if first[index] != second[index]:
			return false
	return true


func _sorted_name_strings(names: Array[StringName]) -> PackedStringArray:
	var sorted := PackedStringArray()
	for name: StringName in names:
		sorted.append(String(name))
	sorted.sort()
	return sorted


func _sorted_dictionary_keys(values: Dictionary) -> PackedStringArray:
	var sorted := PackedStringArray()
	for raw_key: Variant in values.keys():
		sorted.append(str(raw_key))
	sorted.sort()
	return sorted


func _has_physical_key(events: Array[InputEvent], keycode: Key) -> bool:
	for event: InputEvent in events:
		if event is InputEventKey and (event as InputEventKey).physical_keycode == keycode:
			return true
	return false


func _has_gamepad_axis(events: Array[InputEvent]) -> bool:
	for event: InputEvent in events:
		if event is InputEventJoypadMotion:
			return true
	return false


func _has_gamepad_button(events: Array[InputEvent], button: JoyButton) -> bool:
	for event: InputEvent in events:
		if event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index == button:
			return true
	return false


func _on_bindings_changed(actions: Array[StringName]) -> void:
	_binding_notification_count += 1
	_last_binding_actions = actions.duplicate()


func _cleanup_test_file() -> void:
	for suffix: String in ["", SettingsStore.TEMP_SUFFIX, SettingsStore.BACKUP_SUFFIX, SettingsStore.BACKUP_TEMP_SUFFIX]:
		var path := TEST_PATH + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_passed = false
	push_error("PRODUCTION SETTINGS PROBE: %s" % message)
