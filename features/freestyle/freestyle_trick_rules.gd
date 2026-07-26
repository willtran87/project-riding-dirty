extends RefCounted
class_name FreestyleTrickRules
## Pure freestyle classification and scoring rules.
##
## The bike owns physical observation. This module turns that observation into
## deterministic trick identity, landing quality, and a transparent score
## receipt that both gameplay and focused probes can consume.

const MIN_TRICK_HOLD_SECONDS: float = 0.18
const SAFE_RETURN_SECONDS: float = 0.14
const FULL_ROTATION_THRESHOLD: float = TAU * 0.72
const HALF_ROTATION_THRESHOLD: float = PI * 0.62
const REPEAT_MULTIPLIERS := [1.0, 0.72, 0.50, 0.35]

const BASE_POINTS: Dictionary[StringName, int] = {
	&"STRAIGHT_AIR": 120,
	&"SCRUB": 260,
	&"WHIP_LEFT": 300,
	&"WHIP_RIGHT": 300,
	&"NO_HANDER": 420,
	&"CAN_CAN_LEFT": 480,
	&"CAN_CAN_RIGHT": 480,
	&"SEAT_GRAB": 520,
	&"SUPERMAN": 620,
	&"BACKFLIP": 760,
	&"FRONTFLIP": 860,
	&"THREE_SIXTY": 900,
}

const DISPLAY_NAMES: Dictionary[StringName, String] = {
	&"STRAIGHT_AIR": "STRAIGHT AIR",
	&"SCRUB": "SCRUB",
	&"WHIP_LEFT": "LEFT WHIP",
	&"WHIP_RIGHT": "RIGHT WHIP",
	&"NO_HANDER": "NO-HANDER",
	&"CAN_CAN_LEFT": "LEFT CAN-CAN",
	&"CAN_CAN_RIGHT": "RIGHT CAN-CAN",
	&"SEAT_GRAB": "SEAT GRAB",
	&"SUPERMAN": "SUPERMAN",
	&"BACKFLIP": "BACKFLIP",
	&"FRONTFLIP": "FRONTFLIP",
	&"THREE_SIXTY": "360",
}


static func evaluate(observation: Dictionary, context: Dictionary = {}) -> Dictionary:
	var classification := classify(observation)
	var trick_id := StringName(classification.get(&"trick_id", &"STRAIGHT_AIR"))
	var trick_name := str(classification.get(&"trick_name", "STRAIGHT AIR"))
	var family_ids: Array[StringName] = classification.get(&"families", []) as Array[StringName]
	var landing := grade_landing(observation)
	var clean := bool(landing.get(&"clean", false))
	var current_combo := clampi(int(context.get(&"combo", 1)), 1, 6)
	var next_combo := mini(current_combo + 1, 6) if clean else 1
	var combo_multiplier := 1.0 + float(next_combo - 1) * 0.20

	var repeats := maxi(int(context.get(&"repeat_count", 0)), 0)
	var repetition_multiplier: float = float(
		REPEAT_MULTIPLIERS[mini(repeats, REPEAT_MULTIPLIERS.size() - 1)]
	)
	var recent_ids: Array = context.get(&"recent_trick_ids", []) as Array
	var variety_multiplier := 1.0
	if trick_id != &"STRAIGHT_AIR" and trick_id not in recent_ids:
		variety_multiplier = 1.15

	var base_points := int(classification.get(&"base_points", 120))
	var airtime := maxf(float(observation.get(&"airtime", 0.0)), 0.0)
	var rotation_amount := maxf(float(observation.get(&"total_rotation", 0.0)), 0.0)
	var airtime_points := int(airtime * 520.0)
	var rotation_points := int(rotation_amount / TAU * 430.0)
	var landing_points := int(landing.get(&"points", 0))
	var subtotal := maxi(base_points + airtime_points + rotation_points + landing_points, 100)
	var execution_multiplier := float(landing.get(&"multiplier", 1.0))
	var awarded_points := maxi(
		int(
			float(subtotal)
			* repetition_multiplier
			* variety_multiplier
			* combo_multiplier
			* execution_multiplier
		),
		40
	)

	return {
		&"trick_id": trick_id,
		&"trick_name": trick_name,
		&"families": family_ids.duplicate(),
		&"pose_id": StringName(classification.get(&"pose_id", &"NONE")),
		&"landing_grade": StringName(landing.get(&"grade", &"ROUGH")),
		&"landing_label": str(landing.get(&"label", "ROUGH")),
		&"clean": clean,
		&"safe_return": bool(landing.get(&"safe_return", true)),
		&"base_points": base_points,
		&"airtime_points": airtime_points,
		&"rotation_points": rotation_points,
		&"landing_points": landing_points,
		&"subtotal": subtotal,
		&"repeat_count": repeats,
		&"repetition_multiplier": repetition_multiplier,
		&"variety_multiplier": variety_multiplier,
		&"combo_before": current_combo,
		&"combo": next_combo,
		&"combo_multiplier": combo_multiplier,
		&"execution_multiplier": execution_multiplier,
		&"awarded_points": awarded_points,
		&"airtime": airtime,
		&"total_rotation": rotation_amount,
	}


static func classify(observation: Dictionary) -> Dictionary:
	var pitch_rotation := float(observation.get(&"pitch_rotation", 0.0))
	var yaw_rotation := float(observation.get(&"yaw_rotation", 0.0))
	var pose_id := _dominant_pose(observation)
	var families: Array[StringName] = []
	var primary_id: StringName = &"STRAIGHT_AIR"

	if absf(pitch_rotation) >= FULL_ROTATION_THRESHOLD:
		primary_id = &"BACKFLIP" if pitch_rotation > 0.0 else &"FRONTFLIP"
		families.append(&"FLIP")
	elif absf(yaw_rotation) >= FULL_ROTATION_THRESHOLD:
		primary_id = &"THREE_SIXTY"
		families.append(&"SPIN")
	elif float(observation.get(&"scrub_time", 0.0)) >= 0.24:
		primary_id = &"SCRUB"
		families.append(&"SCRUB")
	elif float(observation.get(&"steer_left_time", 0.0)) >= 0.24:
		primary_id = &"WHIP_LEFT"
		families.append(&"WHIP")
	elif float(observation.get(&"steer_right_time", 0.0)) >= 0.24:
		primary_id = &"WHIP_RIGHT"
		families.append(&"WHIP")

	if pose_id != &"NONE":
		families.append(&"EXTENSION")
		var combined_id := pose_id
		var combined_name := _display_name(pose_id)
		var combined_points := int(BASE_POINTS.get(pose_id, 420))
		if primary_id in [&"BACKFLIP", &"FRONTFLIP", &"THREE_SIXTY"]:
			combined_id = StringName("%s_%s" % [str(primary_id), str(pose_id)])
			combined_name = "%s %s" % [_display_name(primary_id), _display_name(pose_id)]
			combined_points += int(BASE_POINTS.get(primary_id, 120))
		return {
			&"trick_id": combined_id,
			&"trick_name": combined_name,
			&"base_points": combined_points,
			&"families": families,
			&"pose_id": pose_id,
		}

	return {
		&"trick_id": primary_id,
		&"trick_name": _display_name(primary_id),
		&"base_points": int(BASE_POINTS.get(primary_id, 120)),
		&"families": families,
		&"pose_id": pose_id,
	}


static func grade_landing(observation: Dictionary) -> Dictionary:
	var physical_clean := bool(observation.get(&"physical_clean", false))
	var pose_time := maxf(float(observation.get(&"modifier_time", 0.0)), 0.0)
	var return_time := maxf(float(observation.get(&"safe_return_time", 0.0)), 0.0)
	var modifier_held := bool(observation.get(&"modifier_held_at_landing", false))
	var safe_return := (
		pose_time < MIN_TRICK_HOLD_SECONDS
		or (not modifier_held and return_time >= SAFE_RETURN_SECONDS)
	)
	var intensity := clampf(float(observation.get(&"landing_intensity", 1.0)), 0.0, 1.0)

	if not physical_clean:
		var upright_alignment := float(observation.get(&"upright_alignment", 0.0))
		if upright_alignment >= 0.28:
			return {
				&"grade": &"HARD_LANDING",
				&"label": "HARD LANDING",
				&"clean": false,
				&"safe_return": safe_return,
				&"points": 0,
				&"multiplier": 0.34,
			}
		return {
			&"grade": &"CRASHED",
			&"label": "CRASHED",
			&"clean": false,
			&"safe_return": safe_return,
			&"points": 0,
			&"multiplier": 0.30,
		}
	if not safe_return:
		return {
			&"grade": &"LATE_RETURN",
			&"label": "LATE RETURN",
			&"clean": false,
			&"safe_return": false,
			&"points": 40,
			&"multiplier": 0.48,
		}
	if intensity <= 0.30:
		return {
			&"grade": &"PERFECT",
			&"label": "PERFECT",
			&"clean": true,
			&"safe_return": true,
			&"points": 420,
			&"multiplier": 1.10,
		}
	if intensity <= 0.62:
		return {
			&"grade": &"CLEAN",
			&"label": "CLEAN",
			&"clean": true,
			&"safe_return": true,
			&"points": 300,
			&"multiplier": 1.0,
		}
	return {
		&"grade": &"HEAVY",
		&"label": "HEAVY",
		&"clean": true,
		&"safe_return": true,
		&"points": 130,
		&"multiplier": 0.78,
	}


static func pose_from_input(modifier_pressed: bool, steer: float, lean: float) -> Dictionary:
	if not modifier_pressed:
		return {&"pose_id": &"NONE", &"strength": 0.0, &"side": 0.0}
	if lean <= -0.42:
		return {&"pose_id": &"SUPERMAN", &"strength": clampf(-lean, 0.0, 1.0), &"side": 0.0}
	if lean >= 0.42:
		return {&"pose_id": &"SEAT_GRAB", &"strength": clampf(lean, 0.0, 1.0), &"side": 0.0}
	if steer <= -0.38:
		return {&"pose_id": &"CAN_CAN_LEFT", &"strength": clampf(-steer, 0.0, 1.0), &"side": -1.0}
	if steer >= 0.38:
		return {&"pose_id": &"CAN_CAN_RIGHT", &"strength": clampf(steer, 0.0, 1.0), &"side": 1.0}
	return {&"pose_id": &"NO_HANDER", &"strength": 1.0, &"side": 0.0}


static func _dominant_pose(observation: Dictionary) -> StringName:
	var pose_times: Dictionary = observation.get(&"pose_times", {}) as Dictionary
	var best_id: StringName = &"NONE"
	var best_time := 0.0
	for pose_key: Variant in pose_times:
		var pose_id := StringName(pose_key)
		var pose_time := float(pose_times.get(pose_key, 0.0))
		if pose_time >= MIN_TRICK_HOLD_SECONDS and pose_time > best_time:
			best_id = pose_id
			best_time = pose_time
	return best_id


static func _display_name(trick_id: StringName) -> String:
	return DISPLAY_NAMES.get(trick_id, str(trick_id).replace("_", " "))
