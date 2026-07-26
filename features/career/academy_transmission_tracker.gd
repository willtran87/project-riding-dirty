extends RefCounted
class_name AcademyTransmissionTracker
## Deterministic grading state for the Riding Academy manual-transmission lesson.
##
## The tracker consumes the same BikeTransmission snapshot used by physics,
## engine audio, and the HUD. It never reads raw input, so a refused shift,
## automatic shift, replay restore, or reset cannot be mistaken for learned
## manual technique.

const CLEAN_UPSHIFT_MIN_RPM: float = 0.68
const CLEAN_UPSHIFT_MAX_RPM: float = 1.02
const CLEAN_DOWNSHIFT_MIN_RPM: float = 0.20
const CLEAN_DOWNSHIFT_MAX_RPM: float = 0.70
const OVERREV_RPM: float = 0.98

var clean_shifts: int = 0
var mistimed_shifts: int = 0
var upshifts: int = 0
var downshifts: int = 0
var overrev_seconds: float = 0.0
var _last_revision: int = -1


func reset() -> void:
	clean_shifts = 0
	mistimed_shifts = 0
	upshifts = 0
	downshifts = 0
	overrev_seconds = 0.0
	_last_revision = -1


func sample(delta: float, transmission: Dictionary) -> void:
	if StringName(transmission.get(&"mode", &"AUTOMATIC")) != &"MANUAL":
		return
	var rpm := clampf(float(transmission.get(&"rpm", 0.0)), 0.0, 1.10)
	if rpm >= OVERREV_RPM:
		overrev_seconds += maxf(delta, 0.0)

	var revision := int(transmission.get(&"revision", -1))
	if revision == _last_revision:
		return
	_last_revision = revision
	var reason := StringName(transmission.get(&"last_shift_reason", &""))
	var shift_rpm := clampf(float(transmission.get(&"last_shift_rpm", rpm)), 0.0, 1.10)
	var clean := false
	match reason:
		&"MANUAL_UP":
			upshifts += 1
			clean = (
				shift_rpm >= CLEAN_UPSHIFT_MIN_RPM
				and shift_rpm <= CLEAN_UPSHIFT_MAX_RPM
			)
		&"MANUAL_DOWN":
			downshifts += 1
			clean = (
				shift_rpm >= CLEAN_DOWNSHIFT_MIN_RPM
				and shift_rpm <= CLEAN_DOWNSHIFT_MAX_RPM
			)
		_:
			return
	if clean:
		clean_shifts += 1
	else:
		mistimed_shifts += 1


func get_metrics() -> Dictionary:
	return {
		&"clean_shifts": clean_shifts,
		&"mistimed_shifts": mistimed_shifts,
		&"manual_upshifts": upshifts,
		&"manual_downshifts": downshifts,
		&"overrev_seconds": overrev_seconds,
	}


static func get_coach_state(transmission: Dictionary) -> StringName:
	if StringName(transmission.get(&"mode", &"AUTOMATIC")) != &"MANUAL":
		return &"MANUAL_REQUIRED"
	var gear := clampi(int(transmission.get(&"gear", 1)), 1, 5)
	var gear_count := maxi(int(transmission.get(&"gear_count", 5)), 1)
	var rpm := clampf(float(transmission.get(&"rpm", 0.0)), 0.0, 1.10)
	var suggested := clampi(int(transmission.get(&"suggested_gear", gear)), 1, gear_count)
	if gear < gear_count and (rpm >= 0.82 or suggested > gear):
		return &"SHIFT_UP"
	if gear > 1 and (rpm <= 0.34 or suggested < gear):
		return &"SHIFT_DOWN"
	if rpm >= OVERREV_RPM:
		return &"REDLINE"
	return &"HOLD_GEAR"
