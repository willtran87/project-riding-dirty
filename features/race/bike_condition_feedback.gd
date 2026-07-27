class_name BikeConditionFeedback
## Pure presentation authority for the physical bike-condition value.
##
## Condition already changes engine force, lateral grip, and maximum speed in
## DirtBikeController. This helper gives every presentation consumer the same
## semantic severity and truthful performance deltas without owning simulation.


static func build(condition_percent: int) -> Dictionary:
	var condition := clampi(condition_percent, 0, 100)
	var ratio := float(condition) / 100.0
	var status := &"READY"
	var label := "READY"
	if condition < 30:
		status = &"CRITICAL"
		label = "CRITICAL"
	elif condition < 60:
		status = &"DAMAGED"
		label = "DAMAGED"
	elif condition < 85:
		status = &"WORN"
		label = "WORN"
	elif condition < 100:
		status = &"LIGHT_WEAR"
		label = "LIGHT WEAR"
	return {
		&"condition_percent": condition,
		&"condition_ratio": ratio,
		&"status": status,
		&"label": label,
		&"visible": condition < 100,
		&"engine_factor": lerpf(0.94, 1.0, ratio),
		&"grip_factor": lerpf(0.96, 1.0, ratio),
		&"speed_factor": lerpf(0.97, 1.0, ratio),
	}


static func damage_for_landing(intensity: float) -> int:
	if intensity <= 0.72:
		return 0
	return maxi(int(ceil((intensity - 0.72) * 18.0)), 1)


static func damage_for_automatic_recovery(reason: StringName) -> int:
	match reason:
		&"AUTO_WORLD_FALL":
			return 8
		&"AUTO_TIPPED":
			return 5
		&"MANUAL_RESET":
			return 0
		_:
			return 4
