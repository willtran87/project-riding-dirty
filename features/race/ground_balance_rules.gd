class_name GroundBalanceRules
## Pure rules for deliberate one-wheel riding and its live coaching projection.

const WHEELIE_AWARD_SECONDS := 0.80
const STOPPIE_AWARD_SECONDS := 0.30
const MINIMUM_WHEELIE_SPEED_MPS := 5.0
const MINIMUM_STOPPIE_SPEED_MPS := 4.0
const STOPPIE_FRONT_BIAS := 0.72


static func stoppie_intent(brake: float, lean: float, speed_mps: float) -> float:
	return (
		smoothstep(0.52, 0.92, clampf(brake, 0.0, 1.0))
		* smoothstep(0.24, 0.72, clampf(-lean, 0.0, 1.0))
		* smoothstep(5.0, 11.0, maxf(speed_mps, 0.0))
	)


static func front_brake_bias(
	base_bias: float,
	brake: float,
	lean: float,
	speed_mps: float
) -> float:
	return lerpf(
		clampf(base_bias, 0.0, 1.0),
		STOPPIE_FRONT_BIAS,
		stoppie_intent(brake, lean, speed_mps)
	)


static func evaluate(context: Dictionary) -> Dictionary:
	var front_contact := bool(context.get(&"front_contact", false))
	var rear_contact := bool(context.get(&"rear_contact", false))
	var speed_mps := maxf(float(context.get(&"speed_mps", 0.0)), 0.0)
	var brake := clampf(float(context.get(&"brake", 0.0)), 0.0, 1.0)
	var lean := clampf(float(context.get(&"lean", 0.0)), -1.0, 1.0)
	var pitch_degrees := float(context.get(&"pitch_degrees", 0.0))
	var wheelie_seconds := maxf(float(context.get(&"wheelie_seconds", 0.0)), 0.0)
	var stoppie_seconds := maxf(float(context.get(&"stoppie_seconds", 0.0)), 0.0)

	if rear_contact and not front_contact and speed_mps >= MINIMUM_WHEELIE_SPEED_MPS:
		var wheelie_progress := clampf(wheelie_seconds / WHEELIE_AWARD_SECONDS, 0.0, 1.0)
		var wheelie_cue := "LEAN FORWARD" if pitch_degrees >= 24.0 else "LEAN BACK"
		return {
			&"state": &"WHEELIE",
			&"active": true,
			&"text": "BALANCE  //  WHEELIE  //  %02d%%  //  %s" % [
				roundi(wheelie_progress * 100.0),
				wheelie_cue,
			],
			&"cue": wheelie_cue,
			&"progress": wheelie_progress,
			&"seconds": wheelie_seconds,
			&"speed_mps": speed_mps,
			&"award_seconds": WHEELIE_AWARD_SECONDS,
		}

	if (
		front_contact
		and not rear_contact
		and speed_mps >= MINIMUM_STOPPIE_SPEED_MPS
		and brake >= 0.40
	):
		var stoppie_progress := clampf(stoppie_seconds / STOPPIE_AWARD_SECONDS, 0.0, 1.0)
		var stoppie_cue := "LEAN BACK" if pitch_degrees <= -24.0 else "LEAN FORWARD"
		return {
			&"state": &"STOPPIE",
			&"active": true,
			&"text": "BALANCE  //  STOPPIE  //  %02d%%  //  %s" % [
				roundi(stoppie_progress * 100.0),
				stoppie_cue,
			],
			&"cue": stoppie_cue,
			&"progress": stoppie_progress,
			&"seconds": stoppie_seconds,
			&"speed_mps": speed_mps,
			&"award_seconds": STOPPIE_AWARD_SECONDS,
		}

	var intent := stoppie_intent(brake, lean, speed_mps)
	if front_contact and rear_contact and intent >= 0.18:
		return {
			&"state": &"LOAD_FRONT",
			&"active": true,
			&"text": "BALANCE  //  LOAD FRONT  //  %02d%%  //  HOLD BRAKE + LEAN FORWARD" % [
				roundi(intent * 100.0),
			],
			&"cue": "HOLD BRAKE + LEAN FORWARD",
			&"progress": intent,
			&"seconds": 0.0,
			&"speed_mps": speed_mps,
			&"award_seconds": STOPPIE_AWARD_SECONDS,
		}

	return idle_snapshot()


static func idle_snapshot() -> Dictionary:
	return {
		&"state": &"IDLE",
		&"active": false,
		&"text": "",
		&"cue": "",
		&"progress": 0.0,
		&"seconds": 0.0,
		&"speed_mps": 0.0,
		&"award_seconds": 0.0,
	}
