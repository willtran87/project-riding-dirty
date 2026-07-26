extends RefCounted
class_name BikeTransmission
## Deterministic five-speed motocross transmission shared by physics, audio, and HUD.

signal shifted(from_gear: int, to_gear: int, mode: StringName)
signal state_changed(snapshot: Dictionary)

const MODE_AUTOMATIC: StringName = &"AUTOMATIC"
const MODE_MANUAL: StringName = &"MANUAL"
const MODES: Array[String] = ["AUTOMATIC", "MANUAL"]
const GEAR_COUNT: int = 5
const SHIFT_DURATION_SECONDS: float = 0.09
const GEAR_SPEED_LIMIT_RATIOS := [0.30, 0.48, 0.66, 0.84, 1.10]
const GEAR_TORQUE_MULTIPLIERS := [1.16, 1.09, 1.03, 0.99, 0.96]
const AUTOMATIC_UPSHIFT_RATIOS := [0.25, 0.43, 0.61, 0.80]
const AUTOMATIC_DOWNSHIFT_RATIOS := [0.18, 0.34, 0.51, 0.69]

var mode: StringName = MODE_AUTOMATIC
var current_gear: int = 1
var normalized_rpm: float = 0.10
var shift_cut_remaining: float = 0.0
var revision: int = 0
var last_shift_reason: StringName = &"RESET"
var last_shift_rpm: float = 0.10
var _maximum_speed_mps: float = 30.0
var _last_speed_mps: float = 0.0
var _last_throttle: float = 0.0
var _grounded: bool = true


func configure_mode(requested_mode: Variant) -> bool:
	var normalized := normalize_mode(requested_mode)
	if normalized == mode:
		return false
	mode = normalized
	revision += 1
	last_shift_reason = &"MODE_CHANGE"
	state_changed.emit(get_snapshot())
	return true


func reset() -> void:
	current_gear = 1
	normalized_rpm = 0.10
	shift_cut_remaining = 0.0
	last_shift_reason = &"RESET"
	last_shift_rpm = normalized_rpm
	revision += 1
	state_changed.emit(get_snapshot())


func update(
	delta: float,
	speed_mps: float,
	throttle: float,
	grounded: bool,
	shift_up_requested: bool = false,
	shift_down_requested: bool = false,
	maximum_speed_mps: float = 30.0
) -> void:
	_maximum_speed_mps = maxf(maximum_speed_mps, 1.0)
	_last_speed_mps = maxf(speed_mps, 0.0)
	_last_throttle = clampf(throttle, 0.0, 1.0)
	_grounded = grounded
	shift_cut_remaining = maxf(shift_cut_remaining - maxf(delta, 0.0), 0.0)

	if mode == MODE_MANUAL:
		if shift_up_requested and not shift_down_requested:
			_request_shift(current_gear + 1, &"MANUAL_UP")
		elif shift_down_requested and not shift_up_requested:
			_request_shift(current_gear - 1, &"MANUAL_DOWN")
	elif shift_cut_remaining <= 0.0:
		_update_automatic_gear()

	normalized_rpm = calculate_normalized_rpm(
		current_gear,
		_last_speed_mps,
		_last_throttle,
		_grounded,
		_maximum_speed_mps
	)


func get_drive_multiplier() -> float:
	var torque := float(GEAR_TORQUE_MULTIPLIERS[current_gear - 1])
	var rpm_efficiency := 0.90
	if normalized_rpm < 0.64:
		rpm_efficiency = lerpf(0.90, 1.05, smoothstep(0.10, 0.64, normalized_rpm))
	else:
		rpm_efficiency = lerpf(1.05, 0.82, smoothstep(0.64, 1.0, normalized_rpm))
	var coupled_torque := torque * rpm_efficiency
	# Automatic is the baseline accessibility mode and must preserve the authored
	# bike's proven drive envelope between shifts. Manual deliberately retains
	# the full low-/high-RPM torque curve as its skill tradeoff.
	if mode == MODE_AUTOMATIC and normalized_rpm < 0.98:
		coupled_torque = maxf(coupled_torque, 1.04)
	var redline_falloff := 1.0 - smoothstep(0.98, 1.09, normalized_rpm)
	return coupled_torque * redline_falloff * get_shift_coupling()


func get_shift_coupling() -> float:
	if shift_cut_remaining <= 0.0:
		return 1.0
	var elapsed_ratio := 1.0 - shift_cut_remaining / SHIFT_DURATION_SECONDS
	return lerpf(0.18, 1.0, smoothstep(0.12, 1.0, elapsed_ratio))


func get_redline_speed_mps(gear: int = current_gear) -> float:
	var bounded_gear := clampi(gear, 1, GEAR_COUNT)
	return _maximum_speed_mps * float(GEAR_SPEED_LIMIT_RATIOS[bounded_gear - 1])


func get_suggested_gear() -> int:
	var speed_ratio := _last_speed_mps / _maximum_speed_mps
	var suggested := 1
	for threshold: float in AUTOMATIC_UPSHIFT_RATIOS:
		if speed_ratio >= threshold:
			suggested += 1
	return clampi(suggested, 1, GEAR_COUNT)


func get_snapshot() -> Dictionary:
	return {
		&"mode": mode,
		&"gear": current_gear,
		&"gear_count": GEAR_COUNT,
		&"rpm": normalized_rpm,
		&"shift_active": shift_cut_remaining > 0.0,
		&"shift_seconds_remaining": shift_cut_remaining,
		&"shift_coupling": get_shift_coupling(),
		&"drive_multiplier": get_drive_multiplier(),
		&"redline_speed_mps": get_redline_speed_mps(),
		&"suggested_gear": get_suggested_gear(),
		&"last_shift_reason": last_shift_reason,
		&"last_shift_rpm": last_shift_rpm,
		&"revision": revision,
	}


static func normalize_mode(requested_mode: Variant) -> StringName:
	return MODE_MANUAL if str(requested_mode).strip_edges().to_upper() == "MANUAL" else MODE_AUTOMATIC


static func calculate_normalized_rpm(
	gear: int,
	speed_mps: float,
	throttle: float,
	grounded: bool,
	maximum_speed_mps: float
) -> float:
	var bounded_gear := clampi(gear, 1, GEAR_COUNT)
	var redline_speed := (
		maxf(maximum_speed_mps, 1.0)
		* float(GEAR_SPEED_LIMIT_RATIOS[bounded_gear - 1])
	)
	var rpm := maxf(speed_mps, 0.0) / redline_speed * 0.92 + clampf(throttle, 0.0, 1.0) * 0.12
	if not grounded:
		rpm += clampf(throttle, 0.0, 1.0) * 0.10
	return clampf(rpm, 0.10, 1.10)


func _update_automatic_gear() -> void:
	var speed_ratio := _last_speed_mps / _maximum_speed_mps
	var suggested := get_suggested_gear()
	if absi(suggested - current_gear) > 1:
		_request_shift(suggested, &"AUTOMATIC_CATCH_UP" if suggested > current_gear else &"AUTOMATIC_CATCH_DOWN")
		return
	if current_gear < GEAR_COUNT:
		var upshift_threshold := float(AUTOMATIC_UPSHIFT_RATIOS[current_gear - 1])
		# Hold a loaded gear slightly longer; short-shift when the rider rolls out.
		upshift_threshold += lerpf(-0.018, 0.025, _last_throttle)
		if speed_ratio >= upshift_threshold:
			_request_shift(current_gear + 1, &"AUTOMATIC_UP")
			return
	if current_gear > 1:
		var downshift_threshold := float(AUTOMATIC_DOWNSHIFT_RATIOS[current_gear - 2])
		# An open throttle requests the lower gear earlier for stronger corner exit.
		downshift_threshold += _last_throttle * 0.018
		if speed_ratio <= downshift_threshold:
			_request_shift(current_gear - 1, &"AUTOMATIC_DOWN")


func _request_shift(next_gear: int, reason: StringName) -> bool:
	var bounded := clampi(next_gear, 1, GEAR_COUNT)
	if bounded == current_gear or shift_cut_remaining > 0.0:
		return false
	var previous := current_gear
	last_shift_rpm = normalized_rpm
	current_gear = bounded
	# A discontinuous external velocity change (checkpoint restore, replay seek,
	# deterministic fixture) needs gear synchronization, not a second torque cut.
	# Ordinary adjacent automatic and manual shifts retain the full interruption.
	shift_cut_remaining = (
		0.0
		if reason in [&"AUTOMATIC_CATCH_UP", &"AUTOMATIC_CATCH_DOWN"]
		else SHIFT_DURATION_SECONDS
	)
	last_shift_reason = reason
	revision += 1
	shifted.emit(previous, current_gear, mode)
	state_changed.emit(get_snapshot())
	return true
