extends RefCounted
class_name LandingProjection
## Pure, deterministic landing-readability authority.
##
## Physics owns the observation. This rule only classifies the predicted
## receiver, confidence, and one corrective instruction so HUD, audio, haptics,
## testing, and future accessibility surfaces cannot disagree.

const STATE_IDLE: StringName = &"IDLE"
const STATE_SEARCH: StringName = &"SEARCH"
const STATE_SET: StringName = &"SET"
const STATE_ADJUST: StringName = &"ADJUST"
const STATE_DANGER: StringName = &"DANGER"


static func evaluate(observation: Dictionary) -> Dictionary:
	var grounded := bool(observation.get(&"grounded", true))
	var airborne_seconds := maxf(float(observation.get(&"airborne_seconds", 0.0)), 0.0)
	if grounded or airborne_seconds < 0.12:
		return _result(STATE_IDLE, false, false, 0, "", "LANDING COACH IDLE", observation)

	var target_valid := bool(observation.get(&"target_valid", false))
	if not target_valid:
		return _result(
			STATE_SEARCH,
			true,
			false,
			0,
			"SCAN RECEIVER",
			"LANDING // SCAN RECEIVER",
			observation
		)

	var orientation_alignment := clampf(
		float(observation.get(&"orientation_alignment", 0.0)),
		-1.0,
		1.0
	)
	var travel_alignment := clampf(
		float(observation.get(&"travel_alignment", 0.0)),
		-1.0,
		1.0
	)
	var pitch_error_degrees := clampf(
		float(observation.get(&"pitch_error_degrees", 0.0)),
		-180.0,
		180.0
	)
	var roll_error_degrees := clampf(
		float(observation.get(&"roll_error_degrees", 0.0)),
		-180.0,
		180.0
	)
	var impact_speed := maxf(float(observation.get(&"impact_speed_mps", 0.0)), 0.0)
	var angular_speed := maxf(float(observation.get(&"angular_speed_rps", 0.0)), 0.0)
	var distance := maxf(float(observation.get(&"target_distance_m", 0.0)), 0.0)
	var safe_return := bool(observation.get(&"safe_return", true))

	var orientation_score := smoothstep(0.25, 0.94, orientation_alignment)
	var travel_score := smoothstep(-0.10, 0.94, travel_alignment)
	var impact_score := 1.0 - smoothstep(5.0, 11.0, impact_speed)
	var rotation_score := 1.0 - smoothstep(1.6, 5.2, angular_speed)
	var return_score := 1.0 if safe_return else 0.0
	var confidence := clampf(
		orientation_score * 0.34
		+ travel_score * 0.19
		+ impact_score * 0.24
		+ rotation_score * 0.13
		+ return_score * 0.10,
		0.0,
		1.0
	)
	var confidence_percent := clampi(roundi(confidence * 100.0), 0, 100)

	var close_receiver := distance <= 3.8
	var severe_return := not safe_return and close_receiver
	var severe_orientation := orientation_alignment < 0.42
	var severe_pitch := absf(pitch_error_degrees) > 40.0
	var severe_roll := absf(roll_error_degrees) > 34.0
	var severe_impact := impact_speed > 10.5
	var severe_rotation := angular_speed > 5.2
	var danger := (
		severe_return
		or severe_orientation
		or severe_pitch
		or severe_roll
		or severe_impact
		or severe_rotation
	)
	var needs_adjustment := (
		not safe_return
		or orientation_alignment < 0.72
		or absf(pitch_error_degrees) > 16.0
		or absf(roll_error_degrees) > 15.0
		or impact_speed > 7.2
		or angular_speed > 3.2
		or travel_alignment < 0.45
	)
	var likely_safe := not needs_adjustment and confidence_percent >= 68
	var state := STATE_DANGER if danger else STATE_SET if likely_safe else STATE_ADJUST
	var cue := _correction_cue(
		safe_return,
		close_receiver,
		pitch_error_degrees,
		roll_error_degrees,
		impact_speed,
		angular_speed,
		travel_alignment
	)
	var status := (
		"LIKELY SAFE"
		if state == STATE_SET
		else "HIGH RISK"
		if state == STATE_DANGER
		else "ADJUST"
	)
	var text := "LANDING // %s // %02d%% // %s" % [status, confidence_percent, cue]
	var result := _result(
		state,
		true,
		likely_safe,
		confidence_percent,
		cue,
		text,
		observation
	)
	result[&"orientation_score"] = orientation_score
	result[&"travel_score"] = travel_score
	result[&"impact_score"] = impact_score
	result[&"rotation_score"] = rotation_score
	result[&"safe_return"] = safe_return
	result[&"eta_seconds"] = distance / maxf(impact_speed, 0.75)
	return result


static func _correction_cue(
	safe_return: bool,
	close_receiver: bool,
	pitch_error_degrees: float,
	roll_error_degrees: float,
	impact_speed: float,
	angular_speed: float,
	travel_alignment: float
) -> String:
	if not safe_return and close_receiver:
		return "RETURN TO BIKE"
	if absf(roll_error_degrees) > 15.0:
		return "LEVEL BIKE"
	if pitch_error_degrees < -16.0:
		return "LEAN FORWARD"
	if pitch_error_degrees > 16.0:
		return "LEAN BACK"
	if angular_speed > 3.2:
		return "STOP ROTATION"
	if travel_alignment < 0.45:
		return "STRAIGHTEN BIKE"
	if impact_speed > 7.2:
		return "MATCH SLOPE"
	return "HOLD"


static func _result(
	state: StringName,
	visible: bool,
	likely_safe: bool,
	confidence_percent: int,
	cue: String,
	text: String,
	observation: Dictionary
) -> Dictionary:
	return {
		&"state": state,
		&"visible": visible,
		&"likely_safe": likely_safe,
		&"confidence_percent": confidence_percent,
		&"cue": cue,
		&"text": text,
		&"target_valid": bool(observation.get(&"target_valid", false)),
		&"target_distance_m": maxf(
			float(observation.get(&"target_distance_m", 0.0)),
			0.0
		),
		&"impact_speed_mps": maxf(float(observation.get(&"impact_speed_mps", 0.0)), 0.0),
		&"pitch_error_degrees": float(observation.get(&"pitch_error_degrees", 0.0)),
		&"roll_error_degrees": float(observation.get(&"roll_error_degrees", 0.0)),
	}
