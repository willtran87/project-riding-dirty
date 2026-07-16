extends RefCounted
class_name AtomicConfigStore
## Verified ConfigFile replacement with one rotating recovery copy.

const BACKUP_SUFFIX: String = ".bak"
const TEMP_SUFFIX: String = ".tmp"
const BACKUP_TEMP_SUFFIX: String = ".bak.tmp"


static func save_section(storage_path: String, section: StringName, values: Dictionary) -> Dictionary:
	if not _is_safe_user_path(storage_path) or String(section).is_empty() or values.is_empty():
		return _save_failure("invalid_arguments")
	if not _ensure_parent_directory(storage_path):
		return _save_failure("directory_failed")
	var temporary_path := storage_path + TEMP_SUFFIX
	_remove_if_present(temporary_path)
	var pending := ConfigFile.new()
	for raw_key: Variant in values.keys():
		pending.set_value(String(section), str(raw_key), values[raw_key])
	var write_error := pending.save(temporary_path)
	if write_error != OK:
		return _save_failure("temporary_write_failed")
	var pending_check := _read_section(temporary_path, section)
	if not bool(pending_check.get("ok", false)) or not _sections_match(values, pending_check.get("data", {}) as Dictionary):
		_remove_if_present(temporary_path)
		return _save_failure("temporary_verification_failed")

	var primary_check := _read_section(storage_path, section)
	var had_valid_primary := bool(primary_check.get("ok", false))
	if had_valid_primary and not _rotate_primary_to_backup(storage_path, section):
		_remove_if_present(temporary_path)
		return _save_failure("backup_rotation_failed")

	var target_absolute := ProjectSettings.globalize_path(storage_path)
	var temporary_absolute := ProjectSettings.globalize_path(temporary_path)
	if FileAccess.file_exists(storage_path) and DirAccess.remove_absolute(target_absolute) != OK:
		_remove_if_present(temporary_path)
		return _save_failure("primary_remove_failed")
	if DirAccess.rename_absolute(temporary_absolute, target_absolute) != OK:
		_restore_backup(storage_path)
		_remove_if_present(temporary_path)
		return _save_failure("primary_replace_failed")
	var final_check := _read_section(storage_path, section)
	if not bool(final_check.get("ok", false)) or not _sections_match(values, final_check.get("data", {}) as Dictionary):
		_remove_if_present(storage_path)
		_restore_backup(storage_path)
		return _save_failure("primary_verification_failed")
	return {"ok": true, "error": ""}


static func load_section(storage_path: String, section: StringName, repair_primary: bool = true) -> Dictionary:
	if not _is_safe_user_path(storage_path) or String(section).is_empty():
		return _load_failure("invalid_arguments")
	var primary := _read_section(storage_path, section)
	if bool(primary.get("ok", false)):
		primary["source"] = "primary"
		primary["repaired"] = false
		return primary
	var backup := _read_section(storage_path + BACKUP_SUFFIX, section)
	if not bool(backup.get("ok", false)):
		var failure := _load_failure("no_valid_profile")
		failure["primary_error"] = str(primary.get("error", "missing"))
		failure["backup_error"] = str(backup.get("error", "missing"))
		return failure
	backup["source"] = "backup"
	backup["repaired"] = repair_primary and _restore_backup(storage_path)
	backup["primary_error"] = str(primary.get("error", "missing"))
	return backup


static func _read_section(storage_path: String, section: StringName) -> Dictionary:
	if not FileAccess.file_exists(storage_path):
		return _load_failure("missing")
	var config := ConfigFile.new()
	var load_error := config.load(storage_path)
	if load_error != OK:
		return _load_failure("parse_failed")
	var section_name := String(section)
	if not config.has_section(section_name):
		return _load_failure("section_missing")
	var data: Dictionary = {}
	for key: String in config.get_section_keys(section_name):
		data[key] = config.get_value(section_name, key)
	if data.is_empty():
		return _load_failure("section_empty")
	return {"ok": true, "data": data, "error": ""}


static func _rotate_primary_to_backup(storage_path: String, section: StringName) -> bool:
	var backup_path := storage_path + BACKUP_SUFFIX
	var backup_temporary_path := storage_path + BACKUP_TEMP_SUFFIX
	_remove_if_present(backup_temporary_path)
	var copy_error := DirAccess.copy_absolute(
		ProjectSettings.globalize_path(storage_path),
		ProjectSettings.globalize_path(backup_temporary_path)
	)
	if copy_error != OK or not bool(_read_section(backup_temporary_path, section).get("ok", false)):
		_remove_if_present(backup_temporary_path)
		return false
	if FileAccess.file_exists(backup_path) and not _remove_if_present(backup_path):
		_remove_if_present(backup_temporary_path)
		return false
	var rename_error := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(backup_temporary_path),
		ProjectSettings.globalize_path(backup_path)
	)
	if rename_error != OK:
		_remove_if_present(backup_temporary_path)
		return false
	return true


static func _restore_backup(storage_path: String) -> bool:
	var backup_path := storage_path + BACKUP_SUFFIX
	if not FileAccess.file_exists(backup_path):
		return false
	if FileAccess.file_exists(storage_path) and not _remove_if_present(storage_path):
		return false
	return DirAccess.copy_absolute(
		ProjectSettings.globalize_path(backup_path),
		ProjectSettings.globalize_path(storage_path)
	) == OK


static func _ensure_parent_directory(storage_path: String) -> bool:
	var base_directory := storage_path.get_base_dir()
	if DirAccess.dir_exists_absolute(base_directory):
		return true
	return DirAccess.make_dir_recursive_absolute(base_directory) == OK


static func _sections_match(expected: Dictionary, actual: Dictionary) -> bool:
	if expected.size() != actual.size():
		return false
	for raw_key: Variant in expected.keys():
		var key := str(raw_key)
		if not actual.has(key) or not _values_match(expected[raw_key], actual[key]):
			return false
	return true


static func _values_match(expected: Variant, actual: Variant) -> bool:
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
			if not _values_match(expected_dictionary[raw_key], actual_dictionary[actual_key]):
				return false
		return true
	if expected is Array and actual is Array:
		var expected_array := expected as Array
		var actual_array := actual as Array
		if expected_array.size() != actual_array.size():
			return false
		for index: int in expected_array.size():
			if not _values_match(expected_array[index], actual_array[index]):
				return false
		return true
	if typeof(expected) in [TYPE_INT, TYPE_FLOAT] and typeof(actual) in [TYPE_INT, TYPE_FLOAT]:
		return is_equal_approx(float(expected), float(actual))
	if typeof(expected) in [TYPE_STRING, TYPE_STRING_NAME] and typeof(actual) in [TYPE_STRING, TYPE_STRING_NAME]:
		return str(expected) == str(actual)
	return expected == actual


static func _is_safe_user_path(storage_path: String) -> bool:
	return storage_path.begins_with("user://") and not storage_path.contains("..")


static func _remove_if_present(storage_path: String) -> bool:
	if not FileAccess.file_exists(storage_path):
		return true
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(storage_path)) == OK


static func _save_failure(error_code: String) -> Dictionary:
	return {"ok": false, "error": error_code}


static func _load_failure(error_code: String) -> Dictionary:
	return {"ok": false, "data": {}, "error": error_code}
