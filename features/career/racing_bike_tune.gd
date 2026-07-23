extends RefCounted
class_name RacingBikeTune
## Bounded setup adjustments. Positive gearing favors acceleration; negative favors top speed.

var gearing: float = 0.0
var tire_grip: float = 0.0
var suspension_stiffness: float = 0.0
var suspension_damping: float = 0.0
var jump_preload: float = 0.0
var brake_bias: float = 0.0


static func from_dictionary(data: Dictionary) -> RacingBikeTune:
	var tune := RacingBikeTune.new()
	tune.gearing = _bounded(data.get(&"gearing", 0.0))
	tune.tire_grip = _bounded(data.get(&"tire_grip", 0.0))
	tune.suspension_stiffness = _bounded(data.get(&"suspension_stiffness", 0.0))
	tune.suspension_damping = _bounded(data.get(&"suspension_damping", 0.0))
	tune.jump_preload = _bounded(data.get(&"preload", data.get(&"jump_preload", 0.0)))
	tune.brake_bias = _bounded(data.get(&"brake_bias", 0.0))
	return tune


func set_adjustment(adjustment: StringName, value: float) -> bool:
	var bounded := clampf(value, -1.0, 1.0)
	match adjustment:
		&"gearing": gearing = bounded
		&"tire_grip": tire_grip = bounded
		&"suspension_stiffness": suspension_stiffness = bounded
		&"suspension_damping": suspension_damping = bounded
		&"preload", &"jump_preload": jump_preload = bounded
		&"brake_bias": brake_bias = bounded
		_: return false
	return true


func get_stat_modifiers() -> Dictionary:
	# Every gain carries an explicit tradeoff, so tuning changes character instead of
	# becoming a hidden upgrade. This function never mutates the tune or a base stat map.
	return {
		&"acceleration": gearing * 6.0 - absf(tire_grip) * 0.8,
		&"top_speed": gearing * -5.0,
		&"grip": tire_grip * 4.0 - absf(brake_bias) * 0.4,
		&"braking": brake_bias * 2.5,
		&"stability": suspension_stiffness * 1.8 + suspension_damping * 2.8 - absf(jump_preload) * 1.2,
		&"suspension": suspension_stiffness * 3.0 + suspension_damping * 2.2,
		&"air_control": jump_preload * 3.5 - absf(suspension_damping) * 0.7,
	}


func signature() -> String:
	return "g%+.3f|t%+.3f|s%+.3f|d%+.3f|p%+.3f|b%+.3f" % [
		gearing, tire_grip, suspension_stiffness, suspension_damping, jump_preload, brake_bias,
	]


func duplicate_tune() -> RacingBikeTune:
	return RacingBikeTune.from_dictionary(to_dictionary())


func to_dictionary() -> Dictionary:
	return {
		&"gearing": gearing,
		&"tire_grip": tire_grip,
		&"suspension_stiffness": suspension_stiffness,
		&"suspension_damping": suspension_damping,
		&"preload": jump_preload,
		&"brake_bias": brake_bias,
	}


static func _bounded(value: Variant) -> float:
	return clampf(float(value), -1.0, 1.0)
