extends CanvasLayer
class_name TouchRidingControls
## Adaptive, asset-free multi-touch controls for riding and Garage navigation.
##
## Physical touches are translated into the same semantic InputMap actions used
## by keyboard and controller players. This keeps the bike, race, Garage, replay,
## and accessibility systems unaware of the input device that drove them.


class TouchSurface:
	extends Control

	var controller: Node

	func _draw() -> void:
		if is_instance_valid(controller):
			controller.call(&"_draw_touch_surface", self)


const MODE_AUTO: StringName = &"AUTO"
const MODE_ON: StringName = &"ON"
const MODE_OFF: StringName = &"OFF"

const CONTEXT_HIDDEN: StringName = &"HIDDEN"
const CONTEXT_RIDE: StringName = &"RIDE"
const CONTEXT_GARAGE: StringName = &"GARAGE"
const CONTEXT_RESULTS: StringName = &"RESULTS"

const HANDEDNESS_LEFT: StringName = &"LEFT"
const HANDEDNESS_RIGHT: StringName = &"RIGHT"

const ORIENTATION_LANDSCAPE: StringName = &"LANDSCAPE"
const ORIENTATION_PORTRAIT: StringName = &"PORTRAIT"

const ACTION_THROTTLE: StringName = &"throttle"
const ACTION_BRAKE: StringName = &"brake"
const ACTION_STEER_LEFT: StringName = &"steer_left"
const ACTION_STEER_RIGHT: StringName = &"steer_right"
const ACTION_LEAN_FORWARD: StringName = &"lean_forward"
const ACTION_LEAN_BACK: StringName = &"lean_back"
const ACTION_PRELOAD: StringName = &"preload"
const ACTION_FLOW: StringName = &"flow_boost"
const ACTION_RACECRAFT: StringName = &"racecraft_technique"
const ACTION_RESET: StringName = &"reset_bike"
const ACTION_PAUSE: StringName = &"pause_game"
const ACTION_OPEN_GARAGE: StringName = &"open_garage"
const ACTION_EVENT_PREVIOUS: StringName = &"event_previous"
const ACTION_EVENT_NEXT: StringName = &"event_next"
const ACTION_GARAGE_LEFT: StringName = &"garage_left"
const ACTION_GARAGE_RIGHT: StringName = &"garage_right"
const ACTION_CONFIRM: StringName = &"confirm_selection"
const ACTION_WORKSHOP: StringName = &"open_workshop"
const ACTION_OPEN_SETTINGS: StringName = &"open_settings"
const ACTION_REPAIR: StringName = &"repair_bike"
const ACTION_TOGGLE_ASSIST: StringName = &"toggle_assist"
const ACTION_RESTART_RUN: StringName = &"restart_run"
const ACTION_TOGGLE_REPLAY: StringName = &"toggle_replay"
const ACTION_CONTINUE_WEEKEND: StringName = &"continue_weekend"

const CONTROL_JOYSTICK: StringName = &"joystick"
const TARGET_AUTHORED_PIXELS: float = 112.0
const MINIMUM_COMPACT_TARGET_PIXELS: float = 48.0
const AUTHORED_VIEWPORT := Vector2(1600.0, 900.0)
const JOYSTICK_DEADZONE: float = 0.10

const CREAM := Color("f7e5b2")
const AMBER := Color("ffb52d")
const CYAN := Color("56d6ff")
const DARK := Color(0.025, 0.03, 0.036, 0.88)
const MUTED := Color("8b989f")
const WARNING := Color("ff806b")

const RIDE_BUTTON_ORDER: Array[StringName] = [
	&"pause", &"reset", &"garage", &"flow", &"racecraft",
	&"preload", &"brake", &"throttle",
]
const GARAGE_BUTTON_ORDER: Array[StringName] = [
	&"event_previous", &"event_next", &"setup_left", &"setup_right", &"confirm",
	&"continue", &"workshop", &"repair", &"assist", &"settings",
]
const RESULTS_BUTTON_ORDER: Array[StringName] = [
	&"ride_again", &"results_garage", &"results_settings", &"replay",
]

var _surface: TouchSurface
var _mode: StringName = MODE_AUTO
var _context: StringName = CONTEXT_HIDDEN
var _touchscreen_override: int = -1
var _runtime_touch_seen: bool = false
var _user_scale: float = 1.0
var _opacity: float = 0.82
var _handedness: StringName = HANDEDNESS_RIGHT

var _viewport_size := Vector2.ZERO
var _safe_rect := Rect2()
var _layout_rect := Rect2()
var _orientation: StringName = ORIENTATION_LANDSCAPE
var _authored_scale: float = 1.0
var _rendered_target_size: float = TARGET_AUTHORED_PIXELS
var _controls_visible: bool = false
var _rotate_prompt_visible: bool = false
var _tree_was_paused: bool = false

var _controls: Dictionary = {}
var _finger_roles: Dictionary = {}
var _role_fingers: Dictionary = {}
var _held_actions: Dictionary = {}

var _joystick_zone := Rect2()
var _joystick_default_center := Vector2.ZERO
var _joystick_base_center := Vector2.ZERO
var _joystick_knob_center := Vector2.ZERO
var _joystick_vector := Vector2.ZERO
var _joystick_radius: float = 72.0
var _joystick_finger: int = -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(&"touch_controls")
	_ensure_semantic_actions()
	_build_surface()
	_tree_was_paused = get_tree().paused
	if not get_viewport().size_changed.is_connected(_on_viewport_size_changed):
		get_viewport().size_changed.connect(_on_viewport_size_changed)
	if not visibility_changed.is_connected(_on_visibility_changed):
		visibility_changed.connect(_on_visibility_changed)
	_update_layout(true)


func _exit_tree() -> void:
	release_all_inputs()
	if get_viewport() != null and get_viewport().size_changed.is_connected(_on_viewport_size_changed):
		get_viewport().size_changed.disconnect(_on_viewport_size_changed)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT \
		or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT \
		or what == NOTIFICATION_APPLICATION_PAUSED:
		release_all_inputs()


func _process(_delta: float) -> void:
	if not is_inside_tree():
		return
	var paused_now := get_tree().paused
	if paused_now != _tree_was_paused:
		_tree_was_paused = paused_now
		release_all_inputs()


func _input(event: InputEvent) -> void:
	if not (event is InputEventScreenTouch or event is InputEventScreenDrag):
		return
	_note_raw_touch_input()
	_update_presentation(false)
	if not _should_capture_raw_touch():
		return
	if _rotate_prompt_visible:
		release_all_inputs()
		get_viewport().set_input_as_handled()
		return
	var consumed := false
	if event is InputEventScreenTouch:
		consumed = _handle_screen_touch(event as InputEventScreenTouch)
	else:
		consumed = _handle_screen_drag(event as InputEventScreenDrag)
	# Mark only the physical touch as consumed. Semantic action injection above
	# must remain observable by Garage/Race/Results listeners in _unhandled_input.
	if consumed:
		get_viewport().set_input_as_handled()


func configure_touch_controls(values: Dictionary) -> void:
	## Accept both concise component keys and settings-store-prefixed keys.
	var mode_value: Variant = _first_setting(
		values,
		["touch_controls", "touch_controls_mode", "touchscreen_mode", "touch_mode", "mode"],
		_mode
	)
	_mode = _normalize_mode(mode_value)
	var scale_value: Variant = _first_setting(
		values,
		["touch_controls_scale", "touch_control_scale", "touch_scale", "scale"],
		_user_scale
	)
	_user_scale = clampf(float(scale_value), 0.75, 1.4)
	var opacity_value: Variant = _first_setting(
		values,
		["touch_controls_opacity", "touch_control_opacity", "touch_opacity", "opacity"],
		_opacity
	)
	_opacity = clampf(float(opacity_value), 0.35, 1.0)
	var handedness_value: Variant = _first_setting(
		values,
		["touch_handedness", "touch_controls_handedness", "handedness"],
		_handedness
	)
	_handedness = _normalize_handedness(handedness_value)
	if _has_any_setting(values, ["touchscreen_override", "touch_override"]):
		set_touchscreen_override(int(_first_setting(
			values, ["touchscreen_override", "touch_override"], _touchscreen_override
		)))
	else:
		release_all_inputs()
		_update_layout(true)


func set_context(context: StringName) -> void:
	var normalized := StringName(String(context).strip_edges().to_upper())
	if normalized != CONTEXT_RIDE and normalized != CONTEXT_GARAGE and normalized != CONTEXT_RESULTS:
		normalized = CONTEXT_HIDDEN
	if normalized == _context:
		_update_presentation(false)
		return
	release_all_inputs()
	_context = normalized
	_update_layout(true)


func set_gameplay_active(active: bool) -> void:
	## Compatibility wrapper for callers that only distinguish racing from hidden.
	set_context(CONTEXT_RIDE if active else CONTEXT_HIDDEN)


func set_touchscreen_override(value: int) -> void:
	var bounded := clampi(value, -1, 1)
	if bounded == _touchscreen_override:
		_update_presentation(false)
		return
	release_all_inputs()
	_touchscreen_override = bounded
	_update_layout(true)


func release_all_inputs() -> void:
	var actions: Array = _held_actions.keys()
	# Clear ownership before dispatching releases. Parsed actions can synchronously
	# change the UI context, so release must remain idempotent under re-entry.
	_held_actions.clear()
	_finger_roles.clear()
	_role_fingers.clear()
	_joystick_finger = -1
	_joystick_vector = Vector2.ZERO
	_joystick_base_center = _joystick_default_center
	_joystick_knob_center = _joystick_default_center
	for raw_action: Variant in actions:
		_emit_action(StringName(raw_action), 0.0, true)
	_request_redraw()


func get_touch_layout_snapshot() -> Dictionary:
	var control_snapshot: Dictionary = {}
	for raw_id: Variant in _controls:
		var control_id := StringName(raw_id)
		var spec: Dictionary = _controls[control_id]
		var rect: Rect2 = spec.get(&"rect", Rect2())
		control_snapshot[control_id] = {
			&"rect": rect,
			&"center": rect.get_center(),
			&"visible": bool(spec.get(&"visible", false)),
			&"pressed": _role_fingers.has(control_id),
			&"action": StringName(spec.get(&"action", &"")),
			&"label": str(spec.get(&"label", "")),
			&"minimum_size": Vector2(TARGET_AUTHORED_PIXELS, TARGET_AUTHORED_PIXELS),
			&"rendered_size": rect.size,
		}
	return {
		&"viewport_size": _viewport_size,
		&"safe_rect": _safe_rect,
		&"layout_rect": _layout_rect,
		&"orientation": _orientation,
		&"mode": _mode,
		&"context": _context,
		&"touchscreen_override": _touchscreen_override,
		&"touchscreen_enabled": _is_touchscreen_enabled(),
		&"gameplay_active": _context == CONTEXT_RIDE,
		&"controls_visible": _controls_visible,
		&"rotate_prompt_visible": _rotate_prompt_visible,
		&"handedness": _handedness,
		&"authored_scale": _authored_scale,
		&"user_scale": _user_scale,
		&"opacity": _opacity,
		&"minimum_target_size": TARGET_AUTHORED_PIXELS,
		&"authored_minimum_target_size": TARGET_AUTHORED_PIXELS,
		&"rendered_minimum_target_size": _rendered_target_size,
		&"held_actions": _held_actions.duplicate(),
		&"joystick": {
			&"zone_rect": _joystick_zone,
			&"base_center": _joystick_base_center,
			&"knob_center": _joystick_knob_center,
			&"active": _joystick_finger >= 0,
			&"finger": _joystick_finger,
			&"vector": _joystick_vector,
			&"radius": _joystick_radius,
		},
		&"controls": control_snapshot,
	}


func _build_surface() -> void:
	_surface = TouchSurface.new()
	_surface.name = "TouchSurface"
	_surface.controller = self
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_surface)


func _ensure_semantic_actions() -> void:
	var actions: Array[StringName] = [
		ACTION_THROTTLE, ACTION_BRAKE, ACTION_STEER_LEFT, ACTION_STEER_RIGHT,
		ACTION_LEAN_FORWARD, ACTION_LEAN_BACK, ACTION_PRELOAD, ACTION_FLOW,
		ACTION_RACECRAFT, ACTION_RESET, ACTION_PAUSE, ACTION_OPEN_GARAGE,
		ACTION_EVENT_PREVIOUS, ACTION_EVENT_NEXT, ACTION_GARAGE_LEFT,
		ACTION_GARAGE_RIGHT, ACTION_CONFIRM, ACTION_WORKSHOP,
		ACTION_OPEN_SETTINGS, ACTION_REPAIR, ACTION_TOGGLE_ASSIST,
		ACTION_RESTART_RUN, ACTION_TOGGLE_REPLAY, ACTION_CONTINUE_WEEKEND,
	]
	for action: StringName in actions:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.12)


func _note_raw_touch_input() -> void:
	if not _runtime_touch_seen:
		_runtime_touch_seen = true
		_update_layout(true)
	if InputRouter.has_method(&"note_touch_input"):
		InputRouter.call(&"note_touch_input")


func _should_capture_raw_touch() -> bool:
	return (
		visible
		and _context != CONTEXT_HIDDEN
		and _is_touchscreen_enabled()
		and (_controls_visible or _rotate_prompt_visible)
	)


func _is_touchscreen_enabled() -> bool:
	match _mode:
		MODE_ON:
			return true
		MODE_OFF:
			return false
		_:
			if _touchscreen_override >= 0:
				return _touchscreen_override == 1
			return _runtime_touch_seen or DisplayServer.is_touchscreen_available()


func _update_layout(force: bool) -> void:
	if not is_inside_tree():
		return
	var next_viewport_size := get_viewport().get_visible_rect().size
	if next_viewport_size.x <= 0.0 or next_viewport_size.y <= 0.0:
		return
	if force or not next_viewport_size.is_equal_approx(_viewport_size):
		if _viewport_size != Vector2.ZERO:
			release_all_inputs()
		_viewport_size = next_viewport_size
		_safe_rect = _calculate_safe_rect(_viewport_size)
		_authored_scale = maxf(minf(
			_safe_rect.size.x / AUTHORED_VIEWPORT.x,
			_safe_rect.size.y / AUTHORED_VIEWPORT.y
		), 0.1)
		var gutter := maxf(24.0 * _authored_scale, 8.0)
		_layout_rect = _safe_rect.grow(-gutter)
		_rendered_target_size = maxf(
			TARGET_AUTHORED_PIXELS * _authored_scale * _user_scale,
			MINIMUM_COMPACT_TARGET_PIXELS
		)
		var maximum_target := minf(_layout_rect.size.y * 0.245, _layout_rect.size.x * 0.16)
		_rendered_target_size = minf(_rendered_target_size, maxf(maximum_target, 32.0))
		_orientation = (
			ORIENTATION_PORTRAIT
			if _viewport_size.y > _viewport_size.x
			else ORIENTATION_LANDSCAPE
		)
		_rebuild_control_specs()
	_update_presentation(true)


func _calculate_safe_rect(viewport_size: Vector2) -> Rect2:
	var full_rect := Rect2(Vector2.ZERO, viewport_size)
	var display_safe: Rect2i = DisplayServer.get_display_safe_area()
	var window_size_i: Vector2i = DisplayServer.window_get_size()
	if display_safe.size.x <= 0 or display_safe.size.y <= 0 \
		or window_size_i.x <= 0 or window_size_i.y <= 0:
		return full_rect
	var window_size := Vector2(window_size_i)
	var ratio := Vector2(viewport_size.x / window_size.x, viewport_size.y / window_size.y)
	var mapped := Rect2(Vector2(display_safe.position) * ratio, Vector2(display_safe.size) * ratio)
	var clipped := full_rect.intersection(mapped)
	if clipped.size.x < viewport_size.x * 0.5 or clipped.size.y < viewport_size.y * 0.5:
		return full_rect
	return clipped


func _rebuild_control_specs() -> void:
	_controls.clear()
	_add_control(CONTROL_JOYSTICK, &"steer_lean", "STEER / LEAN", CYAN)
	_add_control(&"throttle", ACTION_THROTTLE, "THROTTLE", AMBER)
	_add_control(&"brake", ACTION_BRAKE, "BRAKE", WARNING)
	_add_control(&"preload", ACTION_PRELOAD, "PRELOAD", CREAM)
	_add_control(&"flow", ACTION_FLOW, "FLOW", CYAN)
	_add_control(&"racecraft", ACTION_RACECRAFT, "TECHNIQUE", AMBER)
	_add_control(&"reset", ACTION_RESET, "RESET", CREAM)
	_add_control(&"pause", ACTION_PAUSE, "PAUSE", CREAM)
	_add_control(&"garage", ACTION_OPEN_GARAGE, "GARAGE", CREAM)

	_add_control(&"event_previous", ACTION_EVENT_PREVIOUS, "EVENT\nPREV", CYAN)
	_add_control(&"event_next", ACTION_EVENT_NEXT, "EVENT\nNEXT", CYAN)
	_add_control(&"setup_left", ACTION_GARAGE_LEFT, "SETUP\nPREV", AMBER)
	_add_control(&"setup_right", ACTION_GARAGE_RIGHT, "SETUP\nNEXT", AMBER)
	_add_control(&"confirm", ACTION_CONFIRM, "RIDE", AMBER)
	_add_control(&"continue", ACTION_CONTINUE_WEEKEND, "CONTINUE", CYAN)
	_add_control(&"workshop", ACTION_WORKSHOP, "WORKSHOP", AMBER)
	_add_control(&"repair", ACTION_REPAIR, "REPAIR", CREAM)
	_add_control(&"assist", ACTION_TOGGLE_ASSIST, "ASSIST", CREAM)
	_add_control(&"settings", ACTION_OPEN_SETTINGS, "SETTINGS", CREAM)
	_add_control(&"ride_again", ACTION_RESTART_RUN, "RIDE\nAGAIN", AMBER)
	_add_control(&"results_garage", ACTION_OPEN_GARAGE, "GARAGE", CYAN)
	_add_control(&"results_settings", ACTION_OPEN_SETTINGS, "SETTINGS", CREAM)
	_add_control(&"replay", ACTION_TOGGLE_REPLAY, "REPLAY", CREAM)

	_layout_ride_controls()
	_layout_garage_controls()
	_layout_results_controls()


func _add_control(control_id: StringName, action: StringName, label: String, accent: Color) -> void:
	_controls[control_id] = {
		&"action": action,
		&"label": label,
		&"accent": accent,
		&"rect": Rect2(),
		&"visible": false,
	}


func _layout_ride_controls() -> void:
	var target := _rendered_target_size
	var gap := maxf(20.0 * _authored_scale * _user_scale, 12.0)
	var right := _layout_rect.end.x
	var bottom := _layout_rect.end.y

	var throttle_size := Vector2(target * 1.16, target * 1.68)
	var throttle_rect := Rect2(Vector2(right - throttle_size.x, bottom - throttle_size.y), throttle_size)
	var brake_size := Vector2(target * 1.08, target * 1.34)
	var brake_rect := Rect2(
		Vector2(throttle_rect.position.x - gap - brake_size.x, bottom - brake_size.y),
		brake_size
	)
	var preload_size := Vector2(target * 1.16, target)
	var preload_rect := Rect2(
		Vector2(
			brake_rect.get_center().x - preload_size.x * 0.5,
			brake_rect.position.y - gap - preload_size.y
		),
		preload_size
	)
	var secondary_size := Vector2(target * 1.28, target)
	var secondary_y := minf(throttle_rect.position.y, preload_rect.position.y) - gap - target
	var flow_rect := Rect2(Vector2(right - secondary_size.x, secondary_y), secondary_size)
	var racecraft_rect := Rect2(
		Vector2(flow_rect.position.x - gap - secondary_size.x, secondary_y),
		secondary_size
	)

	var utility_y := _layout_rect.position.y
	var pause_rect := Rect2(Vector2(right - target, utility_y), Vector2.ONE * target)
	var reset_rect := Rect2(
		Vector2(pause_rect.position.x - gap - target, utility_y),
		Vector2.ONE * target
	)
	var garage_rect := Rect2(
		Vector2(reset_rect.position.x - gap - target, utility_y),
		Vector2.ONE * target
	)

	_joystick_zone = Rect2(
		Vector2(_layout_rect.position.x, _layout_rect.position.y + _layout_rect.size.y * 0.34),
		Vector2(_layout_rect.size.x * 0.43, _layout_rect.size.y * 0.66)
	)
	_joystick_radius = target * 0.68
	_joystick_default_center = Vector2(
		_joystick_zone.position.x + maxf(_joystick_radius + gap, _joystick_zone.size.x * 0.31),
		bottom - maxf(_joystick_radius + gap, target * 1.18)
	)
	_joystick_default_center.x = clampf(
		_joystick_default_center.x,
		_joystick_zone.position.x + _joystick_radius,
		_joystick_zone.end.x - _joystick_radius
	)
	_joystick_default_center.y = clampf(
		_joystick_default_center.y,
		_joystick_zone.position.y + _joystick_radius,
		_joystick_zone.end.y - _joystick_radius
	)

	var ride_rects: Dictionary = {
		&"throttle": throttle_rect,
		&"brake": brake_rect,
		&"preload": preload_rect,
		&"flow": flow_rect,
		&"racecraft": racecraft_rect,
		&"reset": reset_rect,
		&"pause": pause_rect,
		&"garage": garage_rect,
	}
	if _handedness == HANDEDNESS_LEFT:
		_joystick_zone = _mirror_rect(_joystick_zone)
		_joystick_default_center.x = _safe_rect.position.x + _safe_rect.end.x - _joystick_default_center.x
		for raw_id: Variant in ride_rects.keys():
			ride_rects[raw_id] = _mirror_rect(ride_rects[raw_id])
	for raw_id: Variant in ride_rects:
		var spec: Dictionary = _controls[raw_id]
		spec[&"rect"] = ride_rects[raw_id]
	var joystick_spec: Dictionary = _controls[CONTROL_JOYSTICK]
	joystick_spec[&"rect"] = _joystick_zone
	_joystick_base_center = _joystick_default_center
	_joystick_knob_center = _joystick_default_center


func _layout_garage_controls() -> void:
	var target := _rendered_target_size
	var gap := maxf(20.0 * _authored_scale * _user_scale, 12.0)
	var columns := 5
	var available_width := _layout_rect.size.x - gap * float(columns - 1)
	var button_width := minf(target * 1.58, available_width / float(columns))
	button_width = maxf(button_width, target)
	var group_width := button_width * float(columns) + gap * float(columns - 1)
	var start_x := _layout_rect.get_center().x - group_width * 0.5
	var row_height := target
	var second_y := _layout_rect.end.y - row_height
	var first_y := second_y - gap - row_height
	var first_row: Array[StringName] = [
		&"event_previous", &"event_next", &"setup_left", &"setup_right", &"confirm",
	]
	var second_row: Array[StringName] = [
		&"continue", &"workshop", &"repair", &"assist", &"settings",
	]
	for index: int in range(columns):
		var first_spec: Dictionary = _controls[first_row[index]]
		first_spec[&"rect"] = Rect2(
			Vector2(start_x + float(index) * (button_width + gap), first_y),
			Vector2(button_width, row_height)
		)
		var second_spec: Dictionary = _controls[second_row[index]]
		second_spec[&"rect"] = Rect2(
			Vector2(start_x + float(index) * (button_width + gap), second_y),
			Vector2(button_width, row_height)
		)


func _layout_results_controls() -> void:
	var target := _rendered_target_size
	var gap := maxf(24.0 * _authored_scale * _user_scale, 12.0)
	var columns := RESULTS_BUTTON_ORDER.size()
	var available_width := _layout_rect.size.x - gap * float(columns - 1)
	var button_width := minf(target * 1.72, available_width / float(columns))
	button_width = maxf(button_width, target)
	var button_height := target * 1.08
	var group_width := button_width * float(columns) + gap * float(columns - 1)
	var start_x := _layout_rect.get_center().x - group_width * 0.5
	var y := _layout_rect.end.y - button_height
	for index: int in range(columns):
		var spec: Dictionary = _controls[RESULTS_BUTTON_ORDER[index]]
		spec[&"rect"] = Rect2(
			Vector2(start_x + float(index) * (button_width + gap), y),
			Vector2(button_width, button_height)
		)


func _mirror_rect(rect: Rect2) -> Rect2:
	var mirrored_x := _safe_rect.position.x + _safe_rect.end.x - rect.end.x
	return Rect2(Vector2(mirrored_x, rect.position.y), rect.size)


func _update_presentation(rebuild_visibility: bool) -> void:
	if not is_inside_tree():
		return
	var enabled := _is_touchscreen_enabled()
	var should_present := visible and enabled and _context != CONTEXT_HIDDEN
	var next_controls_visible := should_present and _orientation == ORIENTATION_LANDSCAPE
	var next_rotate_visible := should_present and _orientation == ORIENTATION_PORTRAIT
	if (not next_controls_visible and _controls_visible) or next_rotate_visible:
		release_all_inputs()
	_controls_visible = next_controls_visible
	_rotate_prompt_visible = next_rotate_visible
	for raw_id: Variant in _controls:
		var control_id := StringName(raw_id)
		var spec: Dictionary = _controls[control_id]
		var in_context := false
		match _context:
			CONTEXT_RIDE:
				in_context = control_id == CONTROL_JOYSTICK or control_id in RIDE_BUTTON_ORDER
			CONTEXT_GARAGE:
				in_context = control_id in GARAGE_BUTTON_ORDER
			CONTEXT_RESULTS:
				in_context = control_id in RESULTS_BUTTON_ORDER
		spec[&"visible"] = _controls_visible and in_context
	if _surface != null:
		_surface.visible = _controls_visible or _rotate_prompt_visible
	if rebuild_visibility:
		_request_redraw()
	else:
		_request_redraw()


func _handle_screen_touch(event: InputEventScreenTouch) -> bool:
	if event.pressed:
		return _capture_finger(event.index, event.position)
	if not _finger_roles.has(event.index):
		return false
	_release_finger(event.index)
	return true


func _handle_screen_drag(event: InputEventScreenDrag) -> bool:
	if not _finger_roles.has(event.index):
		return false
	var role := StringName(_finger_roles[event.index])
	if role == CONTROL_JOYSTICK:
		_update_joystick(event.position)
	return true


func _capture_finger(finger: int, position: Vector2) -> bool:
	if _finger_roles.has(finger):
		_release_finger(finger)
	var control_id := _hit_test_button(position)
	if control_id == &"" and _context == CONTEXT_RIDE and _joystick_zone.has_point(position):
		control_id = CONTROL_JOYSTICK
	if control_id == &"" or _role_fingers.has(control_id):
		return false
	_finger_roles[finger] = control_id
	_role_fingers[control_id] = finger
	if control_id == CONTROL_JOYSTICK:
		_joystick_finger = finger
		_joystick_base_center = _clamp_joystick_origin(position)
		_joystick_knob_center = _joystick_base_center
		_update_joystick(position)
	else:
		var spec: Dictionary = _controls[control_id]
		_set_action_strength(StringName(spec.get(&"action", &"")), 1.0)
	_request_redraw()
	return true


func _release_finger(finger: int) -> void:
	if not _finger_roles.has(finger):
		return
	var control_id := StringName(_finger_roles[finger])
	_finger_roles.erase(finger)
	_role_fingers.erase(control_id)
	if control_id == CONTROL_JOYSTICK:
		_release_joystick()
	else:
		var spec: Dictionary = _controls.get(control_id, {})
		_set_action_strength(StringName(spec.get(&"action", &"")), 0.0)
	_request_redraw()


func _hit_test_button(position: Vector2) -> StringName:
	var order: Array[StringName] = []
	match _context:
		CONTEXT_RIDE:
			order = RIDE_BUTTON_ORDER
		CONTEXT_GARAGE:
			order = GARAGE_BUTTON_ORDER
		CONTEXT_RESULTS:
			order = RESULTS_BUTTON_ORDER
	for control_id: StringName in order:
		var spec: Dictionary = _controls.get(control_id, {})
		if bool(spec.get(&"visible", false)) and (spec.get(&"rect", Rect2()) as Rect2).has_point(position):
			return control_id
	return &""


func _clamp_joystick_origin(position: Vector2) -> Vector2:
	return Vector2(
		clampf(position.x, _joystick_zone.position.x + _joystick_radius, _joystick_zone.end.x - _joystick_radius),
		clampf(position.y, _joystick_zone.position.y + _joystick_radius, _joystick_zone.end.y - _joystick_radius)
	)


func _update_joystick(position: Vector2) -> void:
	var raw := (position - _joystick_base_center) / maxf(_joystick_radius, 1.0)
	if raw.length() > 1.0:
		raw = raw.normalized()
	var magnitude := raw.length()
	if magnitude <= JOYSTICK_DEADZONE:
		_joystick_vector = Vector2.ZERO
	else:
		var shaped_magnitude := (magnitude - JOYSTICK_DEADZONE) / (1.0 - JOYSTICK_DEADZONE)
		_joystick_vector = raw.normalized() * shaped_magnitude
	_joystick_knob_center = _joystick_base_center + _joystick_vector * _joystick_radius
	_set_action_strength(ACTION_STEER_LEFT, maxf(-_joystick_vector.x, 0.0))
	_set_action_strength(ACTION_STEER_RIGHT, maxf(_joystick_vector.x, 0.0))
	_set_action_strength(ACTION_LEAN_FORWARD, maxf(-_joystick_vector.y, 0.0))
	_set_action_strength(ACTION_LEAN_BACK, maxf(_joystick_vector.y, 0.0))
	_request_redraw()


func _release_joystick() -> void:
	_set_action_strength(ACTION_STEER_LEFT, 0.0)
	_set_action_strength(ACTION_STEER_RIGHT, 0.0)
	_set_action_strength(ACTION_LEAN_FORWARD, 0.0)
	_set_action_strength(ACTION_LEAN_BACK, 0.0)
	_joystick_finger = -1
	_joystick_vector = Vector2.ZERO
	_joystick_base_center = _joystick_default_center
	_joystick_knob_center = _joystick_default_center


func _set_action_strength(action: StringName, strength: float) -> void:
	if action == &"":
		return
	var bounded := clampf(strength, 0.0, 1.0)
	var previous := float(_held_actions.get(action, 0.0))
	if is_equal_approx(previous, bounded):
		return
	# Store state first because a semantic press can synchronously open Garage,
	# pause the tree, or start a race and re-enter release_all_inputs().
	if bounded > 0.0001:
		_held_actions[action] = bounded
	else:
		_held_actions.erase(action)
	_emit_action(action, bounded, false)


func _emit_action(action: StringName, strength: float, force_release: bool) -> void:
	var input_event := InputEventAction.new()
	input_event.action = action
	input_event.strength = clampf(strength, 0.0, 1.0)
	input_event.pressed = not force_release and input_event.strength > 0.0001
	# InputEventAction is the semantic event consumed by _input/_unhandled_input.
	# Mirror its state through Input so polling in the same physics tick observes
	# analog changes immediately, including in isolated SubViewport hosts.
	if input_event.pressed:
		Input.action_press(action, input_event.strength)
	else:
		Input.action_release(action)
	Input.parse_input_event(input_event)


func _draw_touch_surface(canvas: Control) -> void:
	if _rotate_prompt_visible:
		_draw_rotate_prompt(canvas)
		return
	if not _controls_visible:
		return
	if _context == CONTEXT_RIDE:
		_draw_joystick(canvas)
		for control_id: StringName in RIDE_BUTTON_ORDER:
			_draw_button(canvas, control_id)
	elif _context == CONTEXT_GARAGE:
		_draw_garage_caption(canvas)
		for control_id: StringName in GARAGE_BUTTON_ORDER:
			_draw_button(canvas, control_id)
	elif _context == CONTEXT_RESULTS:
		_draw_results_caption(canvas)
		for control_id: StringName in RESULTS_BUTTON_ORDER:
			_draw_button(canvas, control_id)


func _draw_joystick(canvas: Control) -> void:
	var active := _joystick_finger >= 0
	var base_alpha := 0.38 if active else 0.24
	canvas.draw_circle(_joystick_base_center, _joystick_radius, _alpha(DARK, base_alpha))
	canvas.draw_arc(
		_joystick_base_center, _joystick_radius, 0.0, TAU, 56,
		_alpha(CYAN, 0.90 if active else 0.58), maxf(3.0 * _authored_scale, 2.0), true
	)
	canvas.draw_line(
		_joystick_base_center, _joystick_knob_center,
		_alpha(CYAN, 0.72 if active else 0.25), maxf(5.0 * _authored_scale, 2.0), true
	)
	var knob_radius := _joystick_radius * (0.42 if active else 0.36)
	canvas.draw_circle(
		_joystick_knob_center, knob_radius,
		_alpha(CYAN if active else CREAM, 0.66 if active else 0.32)
	)
	canvas.draw_arc(
		_joystick_knob_center, knob_radius, 0.0, TAU, 40,
		_alpha(CREAM, 0.88), maxf(2.0 * _authored_scale, 1.5), true
	)
	var label_rect := Rect2(
		Vector2(_joystick_base_center.x - _joystick_radius * 1.3, _joystick_base_center.y - _joystick_radius - 34.0 * _authored_scale),
		Vector2(_joystick_radius * 2.6, 28.0 * _authored_scale)
	)
	_draw_centered_lines(canvas, label_rect, "STEER / LEAN", _label_font_size(label_rect, false), _alpha(CREAM, 0.82))


func _draw_button(canvas: Control, control_id: StringName) -> void:
	var spec: Dictionary = _controls.get(control_id, {})
	if not bool(spec.get(&"visible", false)):
		return
	var rect: Rect2 = spec.get(&"rect", Rect2())
	var accent: Color = spec.get(&"accent", CREAM)
	var pressed := _role_fingers.has(control_id)
	var corner := minf(rect.size.x, rect.size.y) * 0.14
	var points := PackedVector2Array([
		Vector2(rect.position.x + corner, rect.position.y),
		Vector2(rect.end.x, rect.position.y),
		Vector2(rect.end.x, rect.end.y - corner),
		Vector2(rect.end.x - corner, rect.end.y),
		Vector2(rect.position.x, rect.end.y),
		Vector2(rect.position.x, rect.position.y + corner),
	])
	canvas.draw_colored_polygon(points, _alpha(accent if pressed else DARK, 0.58 if pressed else 0.62))
	var outline := PackedVector2Array(points)
	outline.append(points[0])
	canvas.draw_polyline(
		outline, _alpha(CREAM if pressed else accent, 0.96 if pressed else 0.72),
		maxf((4.0 if pressed else 2.5) * _authored_scale, 1.5), true
	)
	if pressed:
		var inset := rect.grow(-maxf(8.0 * _authored_scale, 4.0))
		canvas.draw_rect(inset, _alpha(CREAM, 0.10), true)
	var text_color := DARK if pressed and accent == CREAM else CREAM
	_draw_centered_lines(
		canvas, rect.grow(-maxf(8.0 * _authored_scale, 4.0)), str(spec.get(&"label", "")),
		_label_font_size(rect, "\n" in str(spec.get(&"label", ""))), _alpha(text_color, 0.98)
	)


func _draw_garage_caption(canvas: Control) -> void:
	var caption_height := maxf(42.0 * _authored_scale, 24.0)
	var caption_rect := Rect2(
		Vector2(_layout_rect.position.x, _layout_rect.end.y - _rendered_target_size * 2.0 - maxf(54.0 * _authored_scale, 30.0)),
		Vector2(_layout_rect.size.x, caption_height)
	)
	_draw_centered_lines(
		canvas, caption_rect, "TOUCH GARAGE  //  BROWSE  //  BUILD  //  RIDE",
		maxi(roundi(22.0 * _authored_scale), 13), _alpha(CREAM, 0.82)
	)


func _draw_results_caption(canvas: Control) -> void:
	var caption_height := maxf(52.0 * _authored_scale, 28.0)
	var caption_rect := Rect2(
		Vector2(
			_layout_rect.position.x,
			_layout_rect.end.y - _rendered_target_size * 1.08 - maxf(64.0 * _authored_scale, 36.0)
		),
		Vector2(_layout_rect.size.x, caption_height)
	)
	_draw_centered_lines(
		canvas, caption_rect, "WHAT'S NEXT?",
		maxi(roundi(28.0 * _authored_scale), 16), _alpha(CREAM, 0.88)
	)


func _draw_rotate_prompt(canvas: Control) -> void:
	var scale := maxf(_authored_scale, 0.35)
	var panel_size := Vector2(
		minf(620.0 * scale, _safe_rect.size.x * 0.86),
		minf(270.0 * scale, _safe_rect.size.y * 0.52)
	)
	panel_size.x = maxf(panel_size.x, minf(_safe_rect.size.x * 0.86, 280.0))
	panel_size.y = maxf(panel_size.y, minf(_safe_rect.size.y * 0.52, 150.0))
	var panel := Rect2(_safe_rect.get_center() - panel_size * 0.5, panel_size)
	canvas.draw_rect(panel, _alpha(DARK, 0.92), true)
	canvas.draw_rect(panel, _alpha(AMBER, 0.92), false, maxf(4.0 * scale, 2.0), true)
	var title_rect := Rect2(
		Vector2(panel.position.x + panel.size.x * 0.08, panel.position.y + panel.size.y * 0.20),
		Vector2(panel.size.x * 0.84, panel.size.y * 0.26)
	)
	var detail_rect := Rect2(
		Vector2(panel.position.x + panel.size.x * 0.10, panel.position.y + panel.size.y * 0.55),
		Vector2(panel.size.x * 0.80, panel.size.y * 0.22)
	)
	_draw_centered_lines(canvas, title_rect, "ROTATE DEVICE", maxi(roundi(42.0 * scale), 22), _alpha(AMBER, 1.0))
	_draw_centered_lines(
		canvas, detail_rect, "Touch controls are ready in landscape.",
		maxi(roundi(23.0 * scale), 14), _alpha(CREAM, 0.94)
	)


func _draw_centered_lines(
	canvas: Control,
	rect: Rect2,
	text: String,
	font_size: int,
	color: Color
) -> void:
	var font := ThemeDB.fallback_font
	var lines := text.split("\n")
	var line_height := float(font_size) * 1.16
	var block_height := line_height * float(lines.size())
	var y := rect.get_center().y - block_height * 0.5 + float(font_size)
	for line: String in lines:
		var width := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var origin := Vector2(rect.get_center().x - width * 0.5, y)
		canvas.draw_string(font, origin, line, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)
		y += line_height


func _label_font_size(rect: Rect2, multiline: bool) -> int:
	var baseline := 20.0 * _authored_scale * minf(_user_scale, 1.18)
	var height_limit := rect.size.y * (0.27 if multiline else 0.31)
	return maxi(roundi(minf(baseline, height_limit)), 11)


func _alpha(color: Color, multiplier: float) -> Color:
	return Color(color.r, color.g, color.b, clampf(color.a * _opacity * multiplier, 0.0, 1.0))


func _request_redraw() -> void:
	if _surface != null:
		_surface.queue_redraw()


func _on_viewport_size_changed() -> void:
	release_all_inputs()
	_update_layout(true)


func _on_visibility_changed() -> void:
	if not visible:
		release_all_inputs()
	_update_presentation(false)


func _normalize_mode(value: Variant) -> StringName:
	if value is bool:
		return MODE_ON if bool(value) else MODE_OFF
	if value is int or value is float:
		var numeric := int(value)
		return MODE_AUTO if numeric < 0 else MODE_ON if numeric > 0 else MODE_OFF
	var normalized := String(value).strip_edges().to_upper()
	if normalized in ["ON", "YES", "ENABLED", "TRUE", "1"]:
		return MODE_ON
	if normalized in ["OFF", "NO", "DISABLED", "FALSE", "0"]:
		return MODE_OFF
	return MODE_AUTO


func _normalize_handedness(value: Variant) -> StringName:
	return HANDEDNESS_RIGHT if String(value).strip_edges().to_upper() == "RIGHT" else HANDEDNESS_LEFT


func _first_setting(values: Dictionary, keys: Array[String], fallback: Variant) -> Variant:
	for key: String in keys:
		if values.has(key):
			return values[key]
		var named_key := StringName(key)
		if values.has(named_key):
			return values[named_key]
	return fallback


func _has_any_setting(values: Dictionary, keys: Array[String]) -> bool:
	for key: String in keys:
		if values.has(key) or values.has(StringName(key)):
			return true
	return false
