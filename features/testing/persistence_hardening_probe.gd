extends Node
## Godot --headless --path . res://features/testing/persistence_hardening_probe.tscn -- --smoke-test

const CODEC := preload("res://common/verified_json_codec.gd")
const VISIBILITY_STATE := preload("res://common/web_visibility_state.gd")
const CONFIG_STORE := preload("res://common/atomic_config_store.gd")
const TEST_PATH: String = "user://tests/persistence_hardening_profile.cfg"

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_verified_json_round_trip()
	_test_verified_json_recovery()
	_test_visibility_lifecycle()
	_test_desktop_profile_recovery()
	_cleanup_profile_files()
	var passed := _failures.is_empty()
	print("PERSISTENCE HARDENING PROBE: codec=true recovery=true visibility=true desktop=true failures=%d passed=%s" % [
		_failures.size(), str(passed),
	])
	get_tree().quit(0 if passed else 1)


func _test_verified_json_round_trip() -> void:
	var payload := {
		"profile_schema_version": 2,
		"cash": 725,
		"setup": "BALANCED",
		"nested": {"wins": 3, "events": ["MESA_MX", "PINE_ENDURO"]},
	}
	var encoded: String = CODEC.encode(payload)
	var decoded: Dictionary = CODEC.decode(encoded, false)
	_check(bool(decoded.get("ok", false)), "verified envelope did not decode")
	_check(not bool(decoded.get("legacy", true)), "verified envelope was marked legacy")
	_check(_json_equivalent(decoded.get("value", null), payload), "verified envelope changed its payload")

	var envelope_parser := JSON.new()
	_check(envelope_parser.parse(encoded) == OK, "verified envelope was not JSON")
	var tampered := envelope_parser.data as Dictionary
	tampered["sha256"] = "0".repeat(64)
	var tampered_result: Dictionary = CODEC.decode(JSON.stringify(tampered), false)
	_check(not bool(tampered_result.get("ok", true)), "tampered envelope passed verification")
	_check(str(tampered_result.get("error", "")) == "checksum_mismatch", "tamper failure was not identified")


func _test_verified_json_recovery() -> void:
	var current_payload := {"cash": 900, "profile_schema_version": 2}
	var backup_payload := {"cash": 650, "profile_schema_version": 1}
	var primary_first: Dictionary = CODEC.recover(CODEC.encode(current_payload), CODEC.encode(backup_payload))
	_check(_json_equivalent(primary_first.get("value", null), current_payload), "valid primary did not win over backup")
	_check(str(primary_first.get("source", "")) == "primary", "primary recovery source was incorrect")

	var fallback: Dictionary = CODEC.recover("{corrupt", CODEC.encode(backup_payload))
	_check(bool(fallback.get("ok", false)), "valid backup did not recover a corrupt primary")
	_check(_json_equivalent(fallback.get("value", null), backup_payload), "backup recovery returned the wrong payload")
	_check(str(fallback.get("source", "")) == "backup", "backup recovery source was incorrect")

	var legacy_text := JSON.stringify({"cash": 425, "profile_schema_version": 1})
	var legacy: Dictionary = CODEC.recover(legacy_text, null)
	_check(bool(legacy.get("ok", false)) and bool(legacy.get("legacy", false)), "legacy JSON was not accepted")
	_check(int((legacy.get("value", {}) as Dictionary).get("cash", 0)) == 425, "legacy JSON payload changed")

	var no_candidate: Dictionary = CODEC.recover("{bad", "[also bad")
	_check(not bool(no_candidate.get("ok", true)), "two corrupt JSON slots produced a valid save")


func _test_visibility_lifecycle() -> void:
	var normal_state := VISIBILITY_STATE.new()
	var normal_runtime := {"tree_paused": false, "master_muted": false}
	var normal_hide := _apply_visibility(normal_state, true, normal_runtime)
	_check(bool(normal_hide.get("set_tree_paused", false)), "visibility did not pause an active tree")
	_check(bool(normal_runtime["tree_paused"]) and bool(normal_runtime["master_muted"]), "hidden active game was not paused and muted")
	_apply_visibility(normal_state, false, normal_runtime)
	_check(not bool(normal_runtime["tree_paused"]) and not bool(normal_runtime["master_muted"]), "visible active game did not restore pause/audio state")

	var manual_pause_state := VISIBILITY_STATE.new()
	var manual_pause_runtime := {"tree_paused": true, "master_muted": false}
	var manual_hide := _apply_visibility(manual_pause_state, true, manual_pause_runtime)
	_check(not bool(manual_hide.get("set_tree_paused", true)), "visibility claimed ownership of a manual pause")
	var manual_show := _apply_visibility(manual_pause_state, false, manual_pause_runtime)
	_check(not bool(manual_show.get("set_tree_paused", true)), "visibility resumed a manually paused tree")
	_check(bool(manual_pause_runtime["tree_paused"]), "manual pause was lost after returning to the tab")
	_check(not bool(manual_pause_runtime["master_muted"]), "manual pause hide/show left Master muted")

	var pre_muted_state := VISIBILITY_STATE.new()
	var pre_muted_runtime := {"tree_paused": true, "master_muted": true}
	_apply_visibility(pre_muted_state, true, pre_muted_runtime)
	_apply_visibility(pre_muted_state, false, pre_muted_runtime)
	_check(bool(pre_muted_runtime["tree_paused"]) and bool(pre_muted_runtime["master_muted"]), "pre-existing pause/mute state was not preserved")

	var repeat_state := VISIBILITY_STATE.new()
	var repeat_runtime := {"tree_paused": false, "master_muted": false}
	_apply_visibility(repeat_state, true, repeat_runtime)
	_apply_visibility(repeat_state, true, repeat_runtime)
	_apply_visibility(repeat_state, false, repeat_runtime)
	_check(not bool(repeat_runtime["master_muted"]), "duplicate hidden events overwrote the original mute state")


func _test_desktop_profile_recovery() -> void:
	_cleanup_profile_files()
	var first := {"profile_schema_version": 1, "cash": 300, "current_setup": "BALANCED"}
	var second := {"profile_schema_version": 2, "cash": 775, "current_setup": "GRIP"}
	var first_save: Dictionary = CONFIG_STORE.save_section(TEST_PATH, &"profile", first)
	_check(bool(first_save.get("ok", false)), "initial desktop profile save failed")
	var second_save: Dictionary = CONFIG_STORE.save_section(TEST_PATH, &"profile", second)
	_check(bool(second_save.get("ok", false)), "desktop profile replacement failed")
	_check(FileAccess.file_exists(TEST_PATH + CONFIG_STORE.BACKUP_SUFFIX), "desktop profile backup was not rotated")

	var corrupt_file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	_check(corrupt_file != null, "could not create corrupt-primary fixture")
	if corrupt_file != null:
		corrupt_file.store_string("[unrelated]\nvalue=1\n")
		corrupt_file.close()
	var recovered: Dictionary = CONFIG_STORE.load_section(TEST_PATH, &"profile", true)
	_check(bool(recovered.get("ok", false)), "desktop backup did not recover corrupt primary")
	_check(str(recovered.get("source", "")) == "backup", "desktop recovery source was not backup")
	_check(int((recovered.get("data", {}) as Dictionary).get("cash", 0)) == 300, "desktop recovery did not return the rotating backup")
	_check(bool(recovered.get("repaired", false)), "desktop recovery did not repair the primary slot")
	var repaired: Dictionary = CONFIG_STORE.load_section(TEST_PATH, &"profile", false)
	_check(str(repaired.get("source", "")) == "primary", "repaired desktop profile did not load from primary")
	_check(int((repaired.get("data", {}) as Dictionary).get("cash", 0)) == 300, "repaired desktop primary changed the backup payload")

	var complete_profile: Dictionary = Profile._profile_to_dictionary()
	var complete_save: Dictionary = CONFIG_STORE.save_section(TEST_PATH, &"profile", complete_profile)
	_check(bool(complete_save.get("ok", false)), "complete nested rider profile did not pass write verification")
	var complete_load: Dictionary = CONFIG_STORE.load_section(TEST_PATH, &"profile", false)
	_check(bool(complete_load.get("ok", false)), "complete nested rider profile did not reload")
	_check(
		int((complete_load.get("data", {}) as Dictionary).get("profile_schema_version", 0)) == Profile.PROFILE_SCHEMA_VERSION,
		"complete nested rider profile lost its schema version"
	)


func _apply_visibility(state: WebVisibilityState, hidden: bool, runtime: Dictionary) -> Dictionary:
	var transition: Dictionary = state.transition(
		hidden,
		bool(runtime.get("tree_paused", false)),
		bool(runtime.get("master_muted", false))
	)
	if bool(transition.get("set_master_mute", false)):
		runtime["master_muted"] = bool(transition.get("master_muted", false))
	if bool(transition.get("set_tree_paused", false)):
		runtime["tree_paused"] = bool(transition.get("tree_paused", false))
	return transition


func _json_equivalent(left: Variant, right: Variant) -> bool:
	if left is Dictionary and right is Dictionary:
		var left_dictionary := left as Dictionary
		var right_dictionary := right as Dictionary
		if left_dictionary.size() != right_dictionary.size():
			return false
		for raw_key: Variant in left_dictionary.keys():
			var key := str(raw_key)
			if not right_dictionary.has(key) or not _json_equivalent(left_dictionary[raw_key], right_dictionary[key]):
				return false
		return true
	if left is Array and right is Array:
		var left_array := left as Array
		var right_array := right as Array
		if left_array.size() != right_array.size():
			return false
		for index: int in left_array.size():
			if not _json_equivalent(left_array[index], right_array[index]):
				return false
		return true
	if typeof(left) in [TYPE_INT, TYPE_FLOAT] and typeof(right) in [TYPE_INT, TYPE_FLOAT]:
		return is_equal_approx(float(left), float(right))
	return left == right


func _cleanup_profile_files() -> void:
	for suffix: String in ["", CONFIG_STORE.TEMP_SUFFIX, CONFIG_STORE.BACKUP_SUFFIX, CONFIG_STORE.BACKUP_TEMP_SUFFIX]:
		var path := TEST_PATH + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
	push_error("PERSISTENCE HARDENING PROBE: %s" % message)
