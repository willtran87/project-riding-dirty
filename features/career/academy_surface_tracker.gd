extends RefCounted
class_name AcademySurfaceTracker
## Deterministic Academy surface-reading evaluator. A rider earns one adapted
## entry per sector by holding the safe control pattern long enough while moving.

const REQUIRED_HOLD_SECONDS := 0.45
const MINIMUM_SPEED_MPS := 3.0
const SUPPORTED_SURFACES: Array[StringName] = [
	&"PACKED", &"SAND", &"GRASS", &"MUD",
]

var _current_surface: StringName = &""
var _next_surface: StringName = &""
var _surface_sectors: int = 0
var _adapted_entries: int = 0
var _qualified_seconds: float = 0.0
var _current_sector_adapted: bool = false


func reset() -> void:
	_current_surface = &""
	_next_surface = &""
	_surface_sectors = 0
	_adapted_entries = 0
	_qualified_seconds = 0.0
	_current_sector_adapted = false


func enter_surface(surface: StringName, next_surface: StringName = &"") -> bool:
	var canonical := _canonical_surface(surface)
	if canonical == _current_surface:
		_next_surface = _canonical_surface(next_surface) if not next_surface.is_empty() else &""
		return false
	_current_surface = canonical
	_next_surface = _canonical_surface(next_surface) if not next_surface.is_empty() else &""
	_surface_sectors += 1
	_qualified_seconds = 0.0
	_current_sector_adapted = false
	return true


func sample(delta: float, controls: Dictionary, speed_mps: float) -> bool:
	if _current_surface.is_empty() or _current_sector_adapted:
		return false
	if _is_adapted_control(controls, speed_mps):
		_qualified_seconds += maxf(delta, 0.0)
	else:
		_qualified_seconds = maxf(_qualified_seconds - maxf(delta, 0.0) * 0.75, 0.0)
	if _qualified_seconds >= REQUIRED_HOLD_SECONDS:
		_current_sector_adapted = true
		_adapted_entries += 1
		return true
	return false


func get_metrics() -> Dictionary:
	return {
		&"surface_sectors": _surface_sectors,
		&"adapted_entries": _adapted_entries,
		&"current_surface": _current_surface,
		&"next_surface": _next_surface,
		&"surface_adapted": _current_sector_adapted,
		&"surface_hold_seconds": _qualified_seconds,
	}


static func get_advice(surface: StringName) -> String:
	match _canonical_surface(surface):
		&"SAND":
			return "KEEP MOMENTUM  //  STEER GENTLY"
		&"GRASS":
			return "ROLL OFF EARLY  //  KEEP THE BIKE CALM"
		&"MUD":
			return "STEADY THROTTLE  //  SMALL STEERING"
		_:
			return "BUILD SPEED SMOOTHLY  //  LOOK AHEAD"


func _is_adapted_control(controls: Dictionary, speed_mps: float) -> bool:
	if speed_mps < MINIMUM_SPEED_MPS:
		return false
	var throttle := clampf(float(controls.get(&"throttle", 0.0)), 0.0, 1.0)
	var brake := clampf(float(controls.get(&"brake", 0.0)), 0.0, 1.0)
	var steer := absf(clampf(float(controls.get(&"steer", 0.0)), -1.0, 1.0))
	match _current_surface:
		&"SAND":
			return throttle >= 0.50 and brake <= 0.20 and steer <= 0.55
		&"GRASS":
			return throttle <= 0.72 and brake <= 0.35 and steer <= 0.50
		&"MUD":
			return throttle >= 0.25 and throttle <= 0.68 and brake <= 0.25 and steer <= 0.45
		_:
			return throttle >= 0.35 and brake <= 0.25 and steer <= 0.75


static func _canonical_surface(surface: StringName) -> StringName:
	var normalized := StringName(String(surface).strip_edges().to_upper().replace(" ", "_"))
	return normalized if normalized in SUPPORTED_SURFACES else &"PACKED"
