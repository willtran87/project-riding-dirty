extends Node
## Browser-only integration for input capture, visibility pausing, and localStorage.

const STORAGE_PREFIX: String = "riding_dirty."

var _visibility_callback: JavaScriptObject
var _paused_by_visibility: bool = false
var _master_was_muted: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.has_feature("web"):
		return
	_install_input_guard()
	_install_visibility_handler()


func save_json(key: String, value: Variant) -> bool:
	if not OS.has_feature("web"):
		return false
	var storage: JavaScriptObject = JavaScriptBridge.get_interface("localStorage")
	if storage == null:
		return false
	storage.setItem(STORAGE_PREFIX + key, JSON.stringify(value))
	return true


func load_json(key: String) -> Variant:
	if not OS.has_feature("web"):
		return null
	var storage: JavaScriptObject = JavaScriptBridge.get_interface("localStorage")
	if storage == null:
		return null
	var raw_value: Variant = storage.getItem(STORAGE_PREFIX + key)
	if raw_value == null or str(raw_value).is_empty():
		return null
	return JSON.parse_string(str(raw_value))


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
	if is_hidden:
		_master_was_muted = AudioServer.is_bus_mute(0)
		AudioServer.set_bus_mute(0, true)
		if not get_tree().paused:
			_paused_by_visibility = true
			get_tree().paused = true
	elif _paused_by_visibility:
		get_tree().paused = false
		_paused_by_visibility = false
		AudioServer.set_bus_mute(0, _master_was_muted)
