extends RefCounted
class_name SettingsStore
## Versioned accessibility, controls, presentation, audio, and binding settings.

const VERIFIED_JSON_CODEC := preload("res://common/verified_json_codec.gd")
const SETTINGS_VERSION: int = 3
const DEFAULT_PATH: String = "user://settings/riding_dirty_settings.json"
const BACKUP_SUFFIX: String = ".bak"
const TEMP_SUFFIX: String = ".tmp"
const BACKUP_TEMP_SUFFIX: String = ".bak.tmp"
const COLOR_SAFE_MODES: Array[String] = ["OFF", "PROTANOPIA", "DEUTERANOPIA", "TRITANOPIA"]
const UNIT_MODES: Array[String] = ["IMPERIAL", "METRIC"]
const RACE_DIFFICULTY_MODES: Array[String] = ["RELAXED", "STANDARD", "EXPERT"]
const VISUAL_QUALITY_MODES: Array[String] = ["PERFORMANCE", "BALANCED", "QUALITY"]
const TOUCH_CONTROL_MODES: Array[String] = ["AUTO", "ON", "OFF"]
const TOUCH_HANDEDNESS_MODES: Array[String] = ["RIGHT", "LEFT"]

const DEFAULTS: Dictionary = {
	"controls": {
		"steering_deadzone": 0.12,
		"throttle_deadzone": 0.05,
		"brake_deadzone": 0.05,
		"steering_sensitivity": 1.0,
		"steering_curve": 1.35,
		"touch_controls": "AUTO",
		"touch_control_scale": 1.0,
		"touch_control_opacity": 0.72,
		"touch_handedness": "RIGHT",
	},
	"camera": {
		"fov_degrees": 78.0,
		"shake_intensity": 0.75,
	},
	"gameplay": {
		"race_difficulty": "STANDARD",
	},
	"graphics": {
		"visual_quality": "BALANCED",
	},
	"feedback": {
		"haptics_enabled": true,
		"haptics_intensity": 0.8,
	},
	"audio": {
		"master_volume": 1.0,
		"music_volume": 0.72,
		"engine_volume": 1.0,
		"effects_volume": 0.9,
		"voice_volume": 0.85,
		"crowd_volume": 0.8,
	},
	"interface": {
		"text_scale": 1.0,
		"reduced_motion": false,
		"high_contrast": false,
		"color_safe_mode": "OFF",
		"units": "IMPERIAL",
	},
	"bindings": {},
}

var storage_path: String = DEFAULT_PATH
var values: Dictionary = DEFAULTS.duplicate(true)


func _init(custom_storage_path: String = DEFAULT_PATH) -> void:
	storage_path = custom_storage_path if _is_safe_user_path(custom_storage_path) else DEFAULT_PATH


func reset_to_defaults() -> void:
	values = DEFAULTS.duplicate(true)


func load_from_disk() -> Dictionary:
	var backup_path := storage_path + BACKUP_SUFFIX
	if not FileAccess.file_exists(storage_path) and not FileAccess.file_exists(backup_path):
		reset_to_defaults()
		return {
			"ok": true, "created_defaults": true, "source": "defaults",
			"repaired": false, "migrated": false, "error": "",
		}
	var primary := _read_settings_candidate(storage_path)
	if bool(primary.get("ok", false)):
		return _adopt_settings_candidate(primary, "primary", false)
	var backup := _read_settings_candidate(backup_path)
	if bool(backup.get("ok", false)):
		var recovered := _adopt_settings_candidate(backup, "backup", true)
		recovered["primary_error"] = str(primary.get("error", "missing"))
		return recovered
	reset_to_defaults()
	return {
		"ok": false,
		"created_defaults": false,
		"source": "",
		"repaired": false,
		"migrated": false,
		"error": "no_valid_settings",
		"primary_error": str(primary.get("error", "missing")),
		"backup_error": str(backup.get("error", "missing")),
	}


func save_to_disk() -> bool:
	values = _sanitize_values(values)
	var base_dir := storage_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(base_dir):
		if DirAccess.make_dir_recursive_absolute(base_dir) != OK:
			return false
	var payload := {"version": SETTINGS_VERSION, "values": values}
	var encoded := VERIFIED_JSON_CODEC.encode(payload)
	var self_check := VERIFIED_JSON_CODEC.decode(encoded, false)
	if not bool(self_check.get("ok", false)) or not _variants_match(self_check.get("value", null), payload):
		return false
	var temporary_path := storage_path + TEMP_SUFFIX
	_remove_if_present(temporary_path)
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(encoded)
	file.flush()
	file.close()
	var temporary_check := _read_settings_candidate(temporary_path, false)
	if not bool(temporary_check.get("ok", false)) or not _variants_match(temporary_check.get("payload", null), payload):
		_remove_if_present(temporary_path)
		return false

	var primary_check := _read_settings_candidate(storage_path)
	if bool(primary_check.get("ok", false)) and not _rotate_primary_to_backup():
		_remove_if_present(temporary_path)
		return false
	var target_absolute := ProjectSettings.globalize_path(storage_path)
	var temporary_absolute := ProjectSettings.globalize_path(temporary_path)
	if FileAccess.file_exists(storage_path) and not _remove_if_present(storage_path):
		_remove_if_present(temporary_path)
		return false
	if DirAccess.rename_absolute(temporary_absolute, target_absolute) != OK:
		_restore_backup_to_primary()
		_remove_if_present(temporary_path)
		return false
	var final_check := _read_settings_candidate(storage_path, false)
	if not bool(final_check.get("ok", false)) or not _variants_match(final_check.get("payload", null), payload):
		_remove_if_present(storage_path)
		_restore_backup_to_primary()
		return false
	return true


func _adopt_settings_candidate(candidate: Dictionary, source: String, repair_primary: bool) -> Dictionary:
	values = (candidate.get("values", DEFAULTS) as Dictionary).duplicate(true)
	var migrated := bool(candidate.get("needs_migration", false))
	var repaired := false
	if repair_primary or migrated:
		repaired = save_to_disk()
	return {
		"ok": true,
		"created_defaults": false,
		"source": source,
		"repaired": repaired,
		"migrated": migrated,
		"legacy": bool(candidate.get("legacy", false)),
		"error": "",
	}


func _read_settings_candidate(path: String, allow_legacy: bool = true) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "missing"}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "file_open_failed"}
	var raw_text := file.get_as_text()
	file.close()
	var decoded := VERIFIED_JSON_CODEC.decode(raw_text, allow_legacy)
	if not bool(decoded.get("ok", false)):
		return {"ok": false, "error": str(decoded.get("error", "invalid_json"))}
	var payload_value: Variant = decoded.get("value", null)
	if not payload_value is Dictionary:
		return {"ok": false, "error": "invalid_payload"}
	var payload := payload_value as Dictionary
	var version := int(payload.get("version", 0))
	if version <= 0 or version > SETTINGS_VERSION:
		return {"ok": false, "error": "unsupported_version"}
	var raw_values: Variant = payload.get("values", null)
	if not raw_values is Dictionary:
		return {"ok": false, "error": "invalid_values"}
	var sanitized := _sanitize_values(raw_values)
	return {
		"ok": true,
		"payload": payload,
		"values": sanitized,
		"legacy": bool(decoded.get("legacy", false)),
		"needs_migration": (
			bool(decoded.get("legacy", false))
			or version < SETTINGS_VERSION
			or not _variants_match(raw_values, sanitized)
		),
		"error": "",
	}


func _rotate_primary_to_backup() -> bool:
	var backup_path := storage_path + BACKUP_SUFFIX
	var backup_temporary_path := storage_path + BACKUP_TEMP_SUFFIX
	_remove_if_present(backup_temporary_path)
	var copy_error := DirAccess.copy_absolute(
		ProjectSettings.globalize_path(storage_path),
		ProjectSettings.globalize_path(backup_temporary_path)
	)
	if copy_error != OK or not bool(_read_settings_candidate(backup_temporary_path).get("ok", false)):
		_remove_if_present(backup_temporary_path)
		return false
	if FileAccess.file_exists(backup_path) and not _remove_if_present(backup_path):
		_remove_if_present(backup_temporary_path)
		return false
	if DirAccess.rename_absolute(
		ProjectSettings.globalize_path(backup_temporary_path),
		ProjectSettings.globalize_path(backup_path)
	) != OK:
		_remove_if_present(backup_temporary_path)
		return false
	return true


func _restore_backup_to_primary() -> bool:
	var backup_path := storage_path + BACKUP_SUFFIX
	if not bool(_read_settings_candidate(backup_path).get("ok", false)):
		return false
	if FileAccess.file_exists(storage_path) and not _remove_if_present(storage_path):
		return false
	if DirAccess.copy_absolute(
		ProjectSettings.globalize_path(backup_path),
		ProjectSettings.globalize_path(storage_path)
	) != OK:
		return false
	return bool(_read_settings_candidate(storage_path).get("ok", false))


static func _variants_match(expected: Variant, actual: Variant) -> bool:
	if expected is Dictionary and actual is Dictionary:
		var expected_dictionary := expected as Dictionary
		var actual_dictionary := actual as Dictionary
		if expected_dictionary.size() != actual_dictionary.size():
			return false
		for raw_key: Variant in expected_dictionary.keys():
			var actual_key: Variant = raw_key
			if not actual_dictionary.has(actual_key):
				var string_key := str(raw_key)
				var named_key := StringName(string_key)
				if actual_dictionary.has(string_key):
					actual_key = string_key
				elif actual_dictionary.has(named_key):
					actual_key = named_key
				else:
					return false
			if not _variants_match(expected_dictionary[raw_key], actual_dictionary[actual_key]):
				return false
		return true
	if expected is Array and actual is Array:
		var expected_array := expected as Array
		var actual_array := actual as Array
		if expected_array.size() != actual_array.size():
			return false
		for index: int in expected_array.size():
			if not _variants_match(expected_array[index], actual_array[index]):
				return false
		return true
	if typeof(expected) in [TYPE_INT, TYPE_FLOAT] and typeof(actual) in [TYPE_INT, TYPE_FLOAT]:
		return is_equal_approx(float(expected), float(actual))
	if typeof(expected) in [TYPE_STRING, TYPE_STRING_NAME] and typeof(actual) in [TYPE_STRING, TYPE_STRING_NAME]:
		return str(expected) == str(actual)
	return expected == actual


static func _is_safe_user_path(path: String) -> bool:
	return path.begins_with("user://") and not path.contains("..")


static func _remove_if_present(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return true
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK


func get_value(section: StringName, key: StringName, fallback: Variant = null) -> Variant:
	var section_values: Variant = values.get(String(section), {})
	if not section_values is Dictionary:
		return fallback
	return (section_values as Dictionary).get(String(key), fallback)


func set_value(section: StringName, key: StringName, value: Variant) -> bool:
	var section_key := String(section)
	var setting_key := String(key)
	if section_key == "bindings":
		return false
	var defaults_section: Variant = DEFAULTS.get(section_key, {})
	if not defaults_section is Dictionary or not (defaults_section as Dictionary).has(setting_key):
		return false
	var proposed := values.duplicate(true)
	(proposed[section_key] as Dictionary)[setting_key] = value
	var sanitized := _sanitize_values(proposed)
	var sanitized_value: Variant = (sanitized.get(section_key, {}) as Dictionary).get(setting_key)
	if not _setting_value_equivalent(sanitized_value, value):
		return false
	values = sanitized
	return true


func set_bindings(action: StringName, events: Array[InputEvent], reject_conflicts: bool = true) -> Dictionary:
	var action_name := String(action).strip_edges()
	if action_name.is_empty() or events.size() > 8:
		return {"ok": false, "error": "invalid_action_or_binding_count", "conflicts": []}
	var serialized: Array[Dictionary] = []
	var all_conflicts: Array[Dictionary] = []
	for event: InputEvent in events:
		var binding := serialize_binding(event)
		if binding.is_empty():
			return {"ok": false, "error": "unsupported_input_event", "conflicts": []}
		var conflicts := find_conflicts(action, event)
		all_conflicts.append_array(conflicts)
		serialized.append(binding)
	if reject_conflicts and not all_conflicts.is_empty():
		return {"ok": false, "error": "binding_conflict", "conflicts": all_conflicts}
	var bindings := values.get("bindings", {}) as Dictionary
	bindings[action_name] = serialized
	values["bindings"] = bindings
	return {"ok": true, "error": "", "conflicts": all_conflicts}


func bindings_for_action(action: StringName) -> Array[InputEvent]:
	var result: Array[InputEvent] = []
	var bindings := values.get("bindings", {}) as Dictionary
	var serialized: Variant = bindings.get(String(action), [])
	if not serialized is Array:
		return result
	for raw_binding: Variant in serialized:
		if not raw_binding is Dictionary:
			continue
		var event := deserialize_binding(raw_binding)
		if event != null:
			result.append(event)
	return result


func find_conflicts(action: StringName, event: InputEvent) -> Array[Dictionary]:
	var conflicts: Array[Dictionary] = []
	var candidate := serialize_binding(event)
	if candidate.is_empty():
		return conflicts
	var bindings := values.get("bindings", {}) as Dictionary
	for raw_action: Variant in bindings.keys():
		var other_action := str(raw_action)
		if other_action == String(action):
			continue
		var slots: Variant = bindings.get(raw_action, [])
		if not slots is Array:
			continue
		for slot_index in (slots as Array).size():
			var raw_binding: Variant = (slots as Array)[slot_index]
			if raw_binding is Dictionary and bindings_conflict(candidate, raw_binding):
				conflicts.append({"action": other_action, "slot": slot_index, "binding": (raw_binding as Dictionary).duplicate(true)})
	return conflicts


func capture_input_map(action_names: Array[StringName]) -> void:
	var bindings: Dictionary = {}
	for action: StringName in action_names:
		if not InputMap.has_action(action):
			continue
		var serialized: Array[Dictionary] = []
		for event: InputEvent in InputMap.action_get_events(action):
			var binding := serialize_binding(event)
			if not binding.is_empty():
				serialized.append(binding)
		bindings[String(action)] = serialized
	values["bindings"] = bindings


func apply_to_input_map(clear_existing: bool = true) -> void:
	var bindings := values.get("bindings", {}) as Dictionary
	for raw_action: Variant in bindings.keys():
		var action := StringName(str(raw_action))
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		if clear_existing:
			InputMap.action_erase_events(action)
		var serialized: Variant = bindings.get(raw_action, [])
		if not serialized is Array:
			continue
		for raw_binding: Variant in serialized:
			if raw_binding is Dictionary:
				var event := deserialize_binding(raw_binding)
				if event != null:
					InputMap.action_add_event(action, event)


static func serialize_binding(event: InputEvent) -> Dictionary:
	var common := {"device": event.device}
	if event is InputEventKey:
		var key := event as InputEventKey
		common.merge({
			"type": "key",
			"keycode": int(key.keycode),
			"physical_keycode": int(key.physical_keycode),
			"location": int(key.location),
			"shift": key.shift_pressed,
			"alt": key.alt_pressed,
			"ctrl": key.ctrl_pressed,
			"meta": key.meta_pressed,
		})
		return common
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		common.merge({
			"type": "mouse_button",
			"button_index": int(mouse.button_index),
			"shift": mouse.shift_pressed,
			"alt": mouse.alt_pressed,
			"ctrl": mouse.ctrl_pressed,
			"meta": mouse.meta_pressed,
		})
		return common
	if event is InputEventJoypadButton:
		var button := event as InputEventJoypadButton
		common.merge({"type": "joypad_button", "button_index": int(button.button_index)})
		return common
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		common.merge({
			"type": "joypad_axis",
			"axis": int(motion.axis),
			"direction": -1 if motion.axis_value < 0.0 else 1,
		})
		return common
	return {}


static func deserialize_binding(data: Dictionary) -> InputEvent:
	var event_type := str(data.get("type", ""))
	var event: InputEvent
	match event_type:
		"key":
			var key := InputEventKey.new()
			key.keycode = int(data.get("keycode", 0)) as Key
			key.physical_keycode = int(data.get("physical_keycode", 0)) as Key
			key.location = int(data.get("location", 0)) as KeyLocation
			_set_modifiers(key, data)
			event = key
		"mouse_button":
			var mouse := InputEventMouseButton.new()
			mouse.button_index = int(data.get("button_index", 0)) as MouseButton
			_set_modifiers(mouse, data)
			event = mouse
		"joypad_button":
			var button := InputEventJoypadButton.new()
			button.button_index = int(data.get("button_index", 0)) as JoyButton
			event = button
		"joypad_axis":
			var motion := InputEventJoypadMotion.new()
			motion.axis = int(data.get("axis", 0)) as JoyAxis
			motion.axis_value = -1.0 if int(data.get("direction", 1)) < 0 else 1.0
			event = motion
		_:
			return null
	event.device = clampi(int(data.get("device", -1)), -1, 255)
	return event


static func bindings_conflict(a: Dictionary, b: Dictionary) -> bool:
	if str(a.get("type", "")) != str(b.get("type", "")):
		return false
	var a_device := int(a.get("device", -1))
	var b_device := int(b.get("device", -1))
	if a_device >= 0 and b_device >= 0 and a_device != b_device:
		return false
	match str(a.get("type", "")):
		"key":
			var a_code := int(a.get("physical_keycode", 0)) if int(a.get("physical_keycode", 0)) != 0 else int(a.get("keycode", 0))
			var b_code := int(b.get("physical_keycode", 0)) if int(b.get("physical_keycode", 0)) != 0 else int(b.get("keycode", 0))
			return a_code != 0 and a_code == b_code and _modifiers_match(a, b)
		"mouse_button":
			return int(a.get("button_index", 0)) == int(b.get("button_index", 0)) and _modifiers_match(a, b)
		"joypad_button":
			return int(a.get("button_index", -1)) == int(b.get("button_index", -2))
		"joypad_axis":
			return int(a.get("axis", -1)) == int(b.get("axis", -2)) and int(a.get("direction", 0)) == int(b.get("direction", 1))
	return false


static func _sanitize_values(raw_values: Variant) -> Dictionary:
	var raw := raw_values as Dictionary if raw_values is Dictionary else {}
	var controls := raw.get("controls", {}) as Dictionary if raw.get("controls", {}) is Dictionary else {}
	var camera := raw.get("camera", {}) as Dictionary if raw.get("camera", {}) is Dictionary else {}
	var gameplay := raw.get("gameplay", {}) as Dictionary if raw.get("gameplay", {}) is Dictionary else {}
	var graphics := raw.get("graphics", {}) as Dictionary if raw.get("graphics", {}) is Dictionary else {}
	var feedback := raw.get("feedback", {}) as Dictionary if raw.get("feedback", {}) is Dictionary else {}
	var audio := raw.get("audio", {}) as Dictionary if raw.get("audio", {}) is Dictionary else {}
	var interface := raw.get("interface", {}) as Dictionary if raw.get("interface", {}) is Dictionary else {}
	var color_mode := str(interface.get("color_safe_mode", "OFF")).to_upper()
	var unit_mode := str(interface.get("units", "IMPERIAL")).to_upper()
	var race_difficulty := str(gameplay.get("race_difficulty", "STANDARD")).to_upper()
	var visual_quality := str(graphics.get("visual_quality", "BALANCED")).to_upper()
	var touch_controls := str(controls.get("touch_controls", "AUTO")).to_upper()
	var touch_handedness := str(controls.get("touch_handedness", "RIGHT")).to_upper()
	var output := {
		"controls": {
			"steering_deadzone": clampf(float(controls.get("steering_deadzone", 0.12)), 0.0, 0.5),
			"throttle_deadzone": clampf(float(controls.get("throttle_deadzone", 0.05)), 0.0, 0.5),
			"brake_deadzone": clampf(float(controls.get("brake_deadzone", 0.05)), 0.0, 0.5),
			"steering_sensitivity": clampf(float(controls.get("steering_sensitivity", 1.0)), 0.25, 3.0),
			"steering_curve": clampf(float(controls.get("steering_curve", 1.35)), 0.5, 3.0),
			"touch_controls": touch_controls if touch_controls in TOUCH_CONTROL_MODES else "AUTO",
			"touch_control_scale": clampf(float(controls.get("touch_control_scale", 1.0)), 0.75, 1.4),
			"touch_control_opacity": clampf(float(controls.get("touch_control_opacity", 0.72)), 0.35, 1.0),
			"touch_handedness": touch_handedness if touch_handedness in TOUCH_HANDEDNESS_MODES else "RIGHT",
		},
		"camera": {
			"fov_degrees": clampf(float(camera.get("fov_degrees", 78.0)), 55.0, 110.0),
			"shake_intensity": clampf(float(camera.get("shake_intensity", 0.75)), 0.0, 1.0),
		},
		"gameplay": {
			"race_difficulty": race_difficulty if race_difficulty in RACE_DIFFICULTY_MODES else "STANDARD",
		},
		"graphics": {
			"visual_quality": visual_quality if visual_quality in VISUAL_QUALITY_MODES else "BALANCED",
		},
		"feedback": {
			"haptics_enabled": bool(feedback.get("haptics_enabled", true)),
			"haptics_intensity": clampf(float(feedback.get("haptics_intensity", 0.8)), 0.0, 1.0),
		},
		"audio": {
			"master_volume": clampf(float(audio.get("master_volume", 1.0)), 0.0, 1.0),
			"music_volume": clampf(float(audio.get("music_volume", 0.72)), 0.0, 1.0),
			"engine_volume": clampf(float(audio.get("engine_volume", 1.0)), 0.0, 1.0),
			"effects_volume": clampf(float(audio.get("effects_volume", 0.9)), 0.0, 1.0),
			"voice_volume": clampf(float(audio.get("voice_volume", 0.85)), 0.0, 1.0),
			"crowd_volume": clampf(float(audio.get("crowd_volume", 0.8)), 0.0, 1.0),
		},
		"interface": {
			"text_scale": clampf(float(interface.get("text_scale", 1.0)), 0.8, 1.75),
			# Version-1 settings files predate this option. Missing values remain
			# opt-in so existing riders keep the original presentation by default.
			"reduced_motion": bool(interface.get("reduced_motion", false)),
			"high_contrast": bool(interface.get("high_contrast", false)),
			"color_safe_mode": color_mode if color_mode in COLOR_SAFE_MODES else "OFF",
			"units": unit_mode if unit_mode in UNIT_MODES else "IMPERIAL",
		},
		"bindings": _sanitize_bindings(raw.get("bindings", {})),
	}
	return output


static func _sanitize_bindings(raw_bindings: Variant) -> Dictionary:
	var output: Dictionary = {}
	if not raw_bindings is Dictionary:
		return output
	for raw_action: Variant in (raw_bindings as Dictionary).keys():
		var action := str(raw_action).strip_edges().substr(0, 64)
		var raw_events: Variant = (raw_bindings as Dictionary).get(raw_action, [])
		if action.is_empty() or not raw_events is Array:
			continue
		var events: Array[Dictionary] = []
		for raw_event: Variant in raw_events:
			if events.size() >= 8:
				break
			if raw_event is Dictionary:
				var event := deserialize_binding(raw_event)
				if event != null:
					events.append(serialize_binding(event))
		output[action] = events
	return output


static func _set_modifiers(event: InputEventWithModifiers, data: Dictionary) -> void:
	event.shift_pressed = bool(data.get("shift", false))
	event.alt_pressed = bool(data.get("alt", false))
	event.ctrl_pressed = bool(data.get("ctrl", false))
	event.meta_pressed = bool(data.get("meta", false))


static func _modifiers_match(a: Dictionary, b: Dictionary) -> bool:
	return (
		bool(a.get("shift", false)) == bool(b.get("shift", false))
		and bool(a.get("alt", false)) == bool(b.get("alt", false))
		and bool(a.get("ctrl", false)) == bool(b.get("ctrl", false))
		and bool(a.get("meta", false)) == bool(b.get("meta", false))
	)


func _setting_value_equivalent(sanitized: Variant, proposed: Variant) -> bool:
	if typeof(sanitized) == TYPE_FLOAT and typeof(proposed) in [TYPE_INT, TYPE_FLOAT]:
		return is_equal_approx(float(sanitized), float(proposed))
	return sanitized == proposed
