extends Node
## Browser-only integration for input capture, visibility pausing, and localStorage.

const STORAGE_PREFIX: String = "riding_dirty."
const BACKUP_SUFFIX: String = ".backup"
const VERIFIED_JSON_CODEC := preload("res://common/verified_json_codec.gd")
const VISIBILITY_STATE := preload("res://common/web_visibility_state.gd")

var _visibility_callback: JavaScriptObject
var _visibility_state: WebVisibilityState = VISIBILITY_STATE.new()
var _last_game_text_state: Dictionary = {
	&"schema_version": 1,
	&"mode": "LOADING",
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.has_feature("web"):
		return
	_install_input_guard()
	_install_visibility_handler()
	_install_game_test_bridge()


func publish_game_text_state(snapshot: Dictionary) -> void:
	_last_game_text_state = snapshot.duplicate(true)
	if not OS.has_feature("web"):
		return
	var encoded := JSON.stringify(_last_game_text_state)
	JavaScriptBridge.eval(
		"window.__ridingDirtyStateJSON = %s;" % JSON.stringify(encoded)
	)


func get_game_text_state_snapshot() -> Dictionary:
	return _last_game_text_state.duplicate(true)


static func get_game_test_bridge_script() -> String:
	return """
		(function () {
			window.__ridingDirtyStateJSON = window.__ridingDirtyStateJSON
				|| '{"schema_version":1,"mode":"LOADING"}';
			window.render_game_to_text = function () {
				return window.__ridingDirtyStateJSON;
			};
			if (typeof window.advanceTime !== 'function') {
				window.advanceTime = function (milliseconds) {
					const duration = Math.max(0, Number(milliseconds) || 0);
					return new Promise(function (resolve) {
						const start = performance.now();
						function waitFrame(now) {
							if (now - start >= duration) {
								resolve();
								return;
							}
							window.requestAnimationFrame(waitFrame);
						}
						window.requestAnimationFrame(waitFrame);
					});
				};
			}
			window.__ridingDirtyTestBridge = {
				schemaVersion: 1,
				timeMode: window.__vt_pending ? 'injected' : 'requestAnimationFrame',
			};
		})();
	"""


func save_json(key: String, value: Variant) -> bool:
	if not OS.has_feature("web") or key.strip_edges().is_empty():
		return false
	var primary_key := STORAGE_PREFIX + key
	var backup_key := primary_key + BACKUP_SUFFIX
	var encoded := VERIFIED_JSON_CODEC.encode(value)
	var self_check := VERIFIED_JSON_CODEC.decode(encoded, false)
	if not bool(self_check.get("ok", false)):
		return false
	var existing_raw: Variant = _read_storage_item(primary_key)
	var existing_check := VERIFIED_JSON_CODEC.decode(str(existing_raw)) if existing_raw != null else {}
	var rotate_existing := bool(existing_check.get("ok", false))
	return _write_storage_item(primary_key, backup_key, encoded, rotate_existing)


func load_json(key: String) -> Variant:
	var result := load_json_result(key)
	return result.get(&"value", null) if bool(result.get(&"ok", false)) else null


func load_json_result(key: String) -> Dictionary:
	if not OS.has_feature("web") or key.strip_edges().is_empty():
		return {&"ok": false, &"value": null, &"source": "", &"repaired": false, &"error": "unavailable"}
	var primary_key := STORAGE_PREFIX + key
	var backup_key := primary_key + BACKUP_SUFFIX
	var recovered := VERIFIED_JSON_CODEC.recover(
		_read_storage_item(primary_key),
		_read_storage_item(backup_key)
	)
	if not bool(recovered.get("ok", false)):
		return {
			&"ok": false,
			&"value": null,
			&"source": "",
			&"repaired": false,
			&"error": str(recovered.get("error", "no_valid_data")),
		}
	var value: Variant = recovered.get("value", null)
	var source := str(recovered.get("source", "primary"))
	var repaired := false
	if str(recovered.get("source", "")) == "backup":
		repaired = _write_storage_item(
			primary_key,
			backup_key,
			VERIFIED_JSON_CODEC.encode(value),
			false
		)
		if not repaired:
			push_warning("Recovered browser data from backup but could not repair its primary slot.")
	return {
		&"ok": true,
		&"value": value,
		&"source": source,
		&"repaired": repaired,
		&"error": "",
	}


func _read_storage_item(storage_key: String) -> Variant:
	var key_literal := JSON.stringify(storage_key)
	return JavaScriptBridge.eval("""
		(function () {
			try {
				return window.localStorage.getItem(%s);
			} catch (error) {
				return null;
			}
		})()
	""" % key_literal)


func _write_storage_item(primary_key: String, backup_key: String, encoded: String, rotate_existing: bool) -> bool:
	var primary_literal := JSON.stringify(primary_key)
	var backup_literal := JSON.stringify(backup_key)
	var value_literal := JSON.stringify(encoded)
	var rotate_literal := "true" if rotate_existing else "false"
	var write_result: Variant = JavaScriptBridge.eval("""
		(function () {
			try {
				const primaryKey = %s;
				const backupKey = %s;
				const nextValue = %s;
				const previousValue = window.localStorage.getItem(primaryKey);
				if (%s && previousValue !== null) {
					window.localStorage.setItem(backupKey, previousValue);
				}
				window.localStorage.setItem(primaryKey, nextValue);
				return window.localStorage.getItem(primaryKey) === nextValue;
			} catch (error) {
				return false;
			}
		})()
	""" % [primary_literal, backup_literal, value_literal, rotate_literal])
	if not bool(write_result):
		return false
	var stored_raw: Variant = _read_storage_item(primary_key)
	if stored_raw == null or str(stored_raw) != encoded:
		return false
	return bool(VERIFIED_JSON_CODEC.decode(str(stored_raw), false).get("ok", false))


func _install_input_guard() -> void:
	JavaScriptBridge.eval("""
		document.addEventListener('contextmenu', function (event) {
			event.preventDefault();
		});
		document.addEventListener('keydown', function (event) {
			if (['Space', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight'].includes(event.code)) {
				event.preventDefault();
			}
		}, { passive: false });
	""")


func _install_game_test_bridge() -> void:
	JavaScriptBridge.eval(get_game_test_bridge_script())
	publish_game_text_state(_last_game_text_state)


func _install_visibility_handler() -> void:
	_visibility_callback = JavaScriptBridge.create_callback(_on_visibility_changed)
	var browser_window: JavaScriptObject = JavaScriptBridge.get_interface("window")
	if browser_window == null:
		return
	browser_window.ridingDirtyVisibilityChanged = _visibility_callback
	JavaScriptBridge.eval("""
		document.addEventListener('visibilitychange', function () {
			window.ridingDirtyVisibilityChanged(document.hidden);
		});
	""")


func _on_visibility_changed(arguments: Array) -> void:
	if arguments.is_empty():
		return
	var is_hidden := bool(arguments[0])
	var transition := _visibility_state.transition(
		is_hidden,
		get_tree().paused,
		AudioServer.is_bus_mute(0)
	)
	if bool(transition.get("set_master_mute", false)):
		AudioServer.set_bus_mute(0, bool(transition.get("master_muted", false)))
	if bool(transition.get("set_tree_paused", false)):
		get_tree().paused = bool(transition.get("tree_paused", false))
