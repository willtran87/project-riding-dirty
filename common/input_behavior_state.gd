extends RefCounted
class_name InputBehaviorState
## Deterministic edge/state authority for accessible hold-or-toggle actions.

const MODE_HOLD: StringName = &"HOLD"
const MODE_TOGGLE: StringName = &"TOGGLE"
const MODES: Array[StringName] = [MODE_HOLD, MODE_TOGGLE]

var mode: StringName = MODE_HOLD
var _raw_was_pressed: bool = false
var _toggle_active: bool = false


func configure(requested_mode: Variant, raw_pressed: bool = false) -> bool:
	var normalized := normalize_mode(requested_mode)
	var changed := normalized != mode
	if changed:
		mode = normalized
		_toggle_active = false
	_raw_was_pressed = raw_pressed
	return changed


func sample(raw_pressed: bool) -> Dictionary:
	var raw_just_pressed := raw_pressed and not _raw_was_pressed
	var raw_just_released := not raw_pressed and _raw_was_pressed
	_raw_was_pressed = raw_pressed
	if mode == MODE_HOLD:
		return {
			&"mode": mode,
			&"pressed": raw_pressed,
			&"just_pressed": raw_just_pressed,
			&"just_released": raw_just_released,
			&"toggle_active": false,
			&"toggle_changed": false,
		}
	var toggle_changed := false
	var effective_just_pressed := false
	var effective_just_released := false
	if raw_just_pressed:
		_toggle_active = not _toggle_active
		toggle_changed = true
		effective_just_pressed = _toggle_active
		effective_just_released = not _toggle_active
	return {
		&"mode": mode,
		&"pressed": _toggle_active,
		&"just_pressed": effective_just_pressed,
		&"just_released": effective_just_released,
		&"toggle_active": _toggle_active,
		&"toggle_changed": toggle_changed,
	}


func reset(raw_pressed: bool = false) -> bool:
	var was_active := _toggle_active
	_toggle_active = false
	_raw_was_pressed = raw_pressed
	return was_active


func is_toggle_active() -> bool:
	return mode == MODE_TOGGLE and _toggle_active


static func normalize_mode(requested_mode: Variant) -> StringName:
	var normalized := StringName(str(requested_mode).strip_edges().to_upper())
	return normalized if normalized in MODES else MODE_HOLD
