extends RefCounted
class_name RiderDebrief
## Deterministic post-race coaching derived only from the official result.
## The output is deliberately compact so UI, accessibility, tests, and future
## progression systems all share one explanation of what happened and what to do next.

const VERSION: int = 1


static func build(result: Dictionary, context: Dictionary = {}) -> Dictionary:
	var valid := bool(result.get(&"valid", true))
	var position := maxi(int(result.get(&"player_position", 1)), 1)
	var classification_value: Variant = result.get(&"classification", [])
	var field_size := maxi((classification_value as Array).size(), position) if classification_value is Array else position
	var crashes := maxi(int(result.get(&"crashes", 0)), 0)
	var recoveries := maxi(int(result.get(&"recoveries", 0)), 0)
	var resets := maxi(int(result.get(&"reset_count", 0)), 0)
	var contacts := maxi(int(result.get(&"contacts", 0)), 0)
	var off_course := maxi(int(result.get(&"off_course_count", 0)), 0)
	var wrong_way := maxi(int(result.get(&"wrong_way_count", 0)), 0)
	var cuts := maxi(int(result.get(&"cut_count", 0)), 0)
	var overtakes := maxi(int(result.get(&"overtakes", 0)), 0)
	var penalty_usec := maxi(int(result.get(&"player_penalty_usec", 0)), 0)
	var fastest_lap := StringName(result.get(&"fastest_rider_id", &"")) == &"PLAYER"
	var holeshot := StringName(result.get(&"holeshot_rider_id", &"")) == &"PLAYER"
	var racecraft := _dictionary(result.get(&"racecraft_metrics", {}))
	var flow_uses := maxi(int(racecraft.get(&"flow_uses", 0)), 0)
	var flow_surges := maxi(int(racecraft.get(&"flow_surges", 0)), 0)
	var sector_analysis := _sector_analysis(result, context)
	var lap_analysis := _lap_analysis(result)

	var score := 78.0
	if position == 1:
		score += 12.0
	elif position <= 3:
		score += 7.0
	else:
		score += clampf(float(field_size - position) * 0.8, 0.0, 5.0)
	if fastest_lap:
		score += 6.0
	if holeshot:
		score += 3.0
	score += minf(float(overtakes) * 1.5, 6.0)
	if crashes == 0 and resets == 0 and contacts == 0 and off_course == 0:
		score += 6.0
	score -= float(crashes) * 12.0
	score -= float(resets) * 9.0
	score -= float(contacts) * 2.0
	score -= float(off_course) * 4.0
	score -= float(wrong_way) * 7.0
	score -= float(cuts) * 8.0
	score -= minf(float(penalty_usec) / 1_000_000.0 * 1.5, 12.0)
	score -= clampf(float(lap_analysis.get(&"variation_ratio", 0.0)) * 80.0, 0.0, 12.0)
	if not valid:
		score = minf(score, 54.0)
	score = clampf(score, 0.0, 100.0)

	var grade := _grade_for_score(score)
	var focus := _select_focus({
		&"valid": valid,
		&"position": position,
		&"crashes": crashes,
		&"recoveries": recoveries,
		&"resets": resets,
		&"contacts": contacts,
		&"off_course": off_course,
		&"wrong_way": wrong_way,
		&"cuts": cuts,
		&"overtakes": overtakes,
		&"flow_uses": flow_uses,
		&"worst_delta_usec": int(sector_analysis.get(&"worst_delta_usec", 0)),
		&"worst_target_usec": int(sector_analysis.get(&"worst_target_usec", 0)),
		&"lap_variation_ratio": float(lap_analysis.get(&"variation_ratio", 0.0)),
	})
	var strength := _select_strength({
		&"position": position,
		&"fastest_lap": fastest_lap,
		&"holeshot": holeshot,
		&"overtakes": overtakes,
		&"flow_uses": flow_uses,
		&"flow_surges": flow_surges,
		&"clean": crashes == 0 and resets == 0 and contacts == 0 and off_course == 0,
		&"best_delta_usec": int(sector_analysis.get(&"best_delta_usec", 0)),
		&"best_sector": int(sector_analysis.get(&"best_sector", 0)),
	})
	var coaching := _coaching_for_focus(focus, result, sector_analysis, lap_analysis)
	var headline := str(coaching.get(&"headline", "BUILD THE NEXT LAP"))
	var primary := str(coaching.get(&"primary", "Review the run, then commit to one repeatable improvement."))
	var objective := str(coaching.get(&"objective", "Finish the next race with one cleaner, faster decision."))
	var strength_text := str(strength.get(&"text", "FINISH BANKED"))
	var debrief := {
		&"version": VERSION,
		&"grade": grade,
		&"score": roundi(score),
		&"focus_id": focus,
		&"headline": headline,
		&"strength": strength_text,
		&"primary_insight": primary,
		&"next_objective": objective,
		&"best_sector": int(sector_analysis.get(&"best_sector", 0)),
		&"best_sector_delta_usec": int(sector_analysis.get(&"best_delta_usec", 0)),
		&"costliest_sector": int(sector_analysis.get(&"worst_sector", 0)),
		&"costliest_sector_delta_usec": int(sector_analysis.get(&"worst_delta_usec", 0)),
		&"lap_spread_usec": int(lap_analysis.get(&"spread_usec", 0)),
		&"lap_variation_ratio": float(lap_analysis.get(&"variation_ratio", 0.0)),
		&"flow_uses": flow_uses,
		&"flow_surges": flow_surges,
		&"evidence": {
			&"valid": valid,
			&"position": position,
			&"crashes": crashes,
			&"recoveries": recoveries,
			&"resets": resets,
			&"contacts": contacts,
			&"off_course": off_course,
			&"wrong_way": wrong_way,
			&"cuts": cuts,
			&"overtakes": overtakes,
			&"costliest_sector_delta_usec": int(sector_analysis.get(&"worst_delta_usec", 0)),
			&"lap_variation_ratio": float(lap_analysis.get(&"variation_ratio", 0.0)),
			&"flow_uses": flow_uses,
			&"flow_surges": flow_surges,
		},
	}
	debrief[&"summary"] = compose_summary(debrief)
	return debrief


static func evaluate_follow_up(previous: Dictionary, current: Dictionary) -> Dictionary:
	## Resolve the previous measurable objective from official result evidence. The
	## receipt is intentionally independent of finishing position: a safer, cleaner
	## or more repeatable ride remains progress even if the field result is worse.
	var focus := StringName(previous.get(&"focus_id", &""))
	if focus.is_empty() or current.is_empty():
		return {}
	var before := _dictionary(previous.get(&"evidence", {}))
	var after := _dictionary(current.get(&"evidence", {}))
	if before.is_empty() or after.is_empty():
		return {}
	var achieved := false
	var improved := false
	var receipt := "OBJECTIVE STILL ACTIVE"
	match focus:
		&"CLASSIFICATION":
			achieved = bool(after.get(&"valid", false))
			improved = achieved
			receipt = "CLASSIFIED FINISH BANKED" if achieved else "COMPLETE EVERY GATE IN ORDER"
		&"CRASH_CONTROL":
			var before_crashes := int(before.get(&"crashes", 0))
			var after_crashes := int(after.get(&"crashes", 0))
			achieved = after_crashes == 0
			improved = after_crashes < before_crashes
			receipt = "ZERO CRASHES" if achieved else "%d FEWER CRASH%s" % [before_crashes - after_crashes, "ES" if before_crashes - after_crashes != 1 else ""] if improved else "%d CRASH%s REMAIN" % [after_crashes, "ES" if after_crashes != 1 else ""]
		&"RECOVERY":
			var before_resets := int(before.get(&"resets", 0))
			var after_resets := int(after.get(&"resets", 0))
			achieved = after_resets == 0
			improved = after_resets < before_resets
			receipt = "NO MANUAL RESETS" if achieved else "%d FEWER RESET%s" % [before_resets - after_resets, "S" if before_resets - after_resets != 1 else ""] if improved else "%d RESET%s REMAIN" % [after_resets, "S" if after_resets != 1 else ""]
		&"TRACK_DISCIPLINE":
			var before_route := _route_incidents(before)
			var after_route := _route_incidents(after)
			achieved = after_route == 0
			improved = after_route < before_route
			receipt = "CLEAN GATE ORDER" if achieved else "%d FEWER ROUTE WARNING%s" % [before_route - after_route, "S" if before_route - after_route != 1 else ""] if improved else "%d ROUTE WARNING%s REMAIN" % [after_route, "S" if after_route != 1 else ""]
		&"CLEAN_PASSING":
			var before_contacts := int(before.get(&"contacts", 0))
			var after_contacts := int(after.get(&"contacts", 0))
			var after_passes := int(after.get(&"overtakes", 0))
			achieved = after_contacts <= 1 and after_passes >= 2
			improved = after_contacts < before_contacts or after_passes > int(before.get(&"overtakes", 0))
			receipt = "%d CLEAN PASSES // %d CONTACT%s" % [after_passes, after_contacts, "S" if after_contacts != 1 else ""]
		&"SECTOR_PACE":
			var before_delta := int(before.get(&"costliest_sector_delta_usec", 0))
			var after_delta := int(after.get(&"costliest_sector_delta_usec", 0))
			var gain_usec := before_delta - after_delta
			achieved = gain_usec >= 500_000
			improved = gain_usec > 0
			receipt = "COSTLIEST SPLIT GAINED %.2fs" % (float(maxi(gain_usec, 0)) / 1_000_000.0) if improved else "COSTLIEST SPLIT DID NOT IMPROVE"
		&"CONSISTENCY":
			var before_variation := float(before.get(&"lap_variation_ratio", 0.0))
			var after_variation := float(after.get(&"lap_variation_ratio", 0.0))
			achieved = after_variation < 0.04
			improved = after_variation < before_variation
			receipt = "LAP SPREAD WITHIN 4%%" if achieved else "LAP VARIATION IMPROVED TO %.1f%%" % (after_variation * 100.0) if improved else "LAP VARIATION %.1f%%" % (after_variation * 100.0)
		&"FLOW_USAGE":
			var uses := int(after.get(&"flow_uses", 0))
			var surges := int(after.get(&"flow_surges", 0))
			achieved = uses > 0 and surges > 0
			improved = uses > int(before.get(&"flow_uses", 0)) or surges > int(before.get(&"flow_surges", 0))
			receipt = "%d FLOW USE%s // %d SURGE%s" % [uses, "S" if uses != 1 else "", surges, "S" if surges != 1 else ""]
		&"RACECRAFT":
			var passes := int(after.get(&"overtakes", 0))
			var contacts := int(after.get(&"contacts", 0))
			achieved = passes >= 2 and contacts <= 1
			improved = passes > int(before.get(&"overtakes", 0)) or contacts < int(before.get(&"contacts", 0))
			receipt = "%d PASSES // %d CONTACT%s" % [passes, contacts, "S" if contacts != 1 else ""]
		_:
			var before_score := int(previous.get(&"score", 0))
			var after_score := int(current.get(&"score", 0))
			var before_incidents := _total_incidents(before)
			var after_incidents := _total_incidents(after)
			achieved = after_score > before_score and after_incidents == 0
			improved = after_score > before_score or after_incidents < before_incidents
			receipt = "DEBRIEF SCORE %d  //  %d INCIDENT%s" % [after_score, after_incidents, "S" if after_incidents != 1 else ""]
	var status := &"CLEARED" if achieved else &"PROGRESS" if improved else &"ACTIVE"
	return {
		&"focus_id": focus,
		&"status": status,
		&"achieved": achieved,
		&"improved": improved,
		&"receipt": receipt,
		&"previous_objective": str(previous.get(&"next_objective", "")),
		&"position_improved": int(after.get(&"position", 99)) < int(before.get(&"position", 99)),
	}


static func compose_summary(debrief: Dictionary) -> String:
	var middle := "STRENGTH  %s  //  FOCUS  %s" % [
		str(debrief.get(&"strength", "FINISH BANKED")),
		str(debrief.get(&"primary_insight", "BUILD A CLEANER RUN")),
	]
	var follow_up := _dictionary(debrief.get(&"follow_up", {}))
	var status := StringName(follow_up.get(&"status", &""))
	if status in [&"CLEARED", &"PROGRESS"]:
		middle = "LAST GOAL %s  //  %s" % [String(status), str(follow_up.get(&"receipt", "PROGRESS BANKED"))]
	return "RIDER DEBRIEF  //  GRADE %s  //  %s\n%s\nNEXT RUN  %s" % [
		str(debrief.get(&"grade", "C")), str(debrief.get(&"headline", "BUILD THE NEXT LAP")), middle,
		str(debrief.get(&"next_objective", "FINISH THE NEXT RACE WITH ONE CLEANER DECISION")),
	]


static func _sector_analysis(result: Dictionary, context: Dictionary) -> Dictionary:
	var sectors := _int_array(result.get(&"sector_times_usec", []))
	if sectors.is_empty():
		return {}
	var ratios := _float_array(context.get(&"checkpoint_progress_ratios", []))
	var checkpoint_count := maxi(ratios.size(), int(context.get(&"checkpoint_count", 0)))
	if checkpoint_count <= 0:
		checkpoint_count = sectors.size()
	var laps := maxi(int(context.get(&"laps", 1)), 1)
	var target_total := maxi(int(context.get(&"rival_target_usec", 0)), 0)
	var best_delta := 9_223_372_036_854_775_000
	var worst_delta := -9_223_372_036_854_775_000
	var best_sector := 0
	var worst_sector := 0
	var worst_target := 0
	for index: int in sectors.size():
		var lap_sector := index % checkpoint_count
		var start_ratio := 0.0
		var end_ratio := float(lap_sector + 1) / float(checkpoint_count)
		if not ratios.is_empty():
			end_ratio = clampf(ratios[mini(lap_sector, ratios.size() - 1)], 0.0, 1.0)
			if lap_sector > 0:
				start_ratio = clampf(ratios[mini(lap_sector - 1, ratios.size() - 1)], 0.0, end_ratio)
		var target_sector := roundi(float(target_total) * maxf(end_ratio - start_ratio, 0.0) / float(laps))
		var delta := sectors[index] - target_sector if target_total > 0 else sectors[index]
		if delta < best_delta:
			best_delta = delta
			best_sector = index + 1
		if delta > worst_delta:
			worst_delta = delta
			worst_sector = index + 1
			worst_target = target_sector
	return {
		&"best_sector": best_sector,
		&"best_delta_usec": best_delta,
		&"worst_sector": worst_sector,
		&"worst_delta_usec": worst_delta,
		&"worst_target_usec": worst_target,
	}


static func _lap_analysis(result: Dictionary) -> Dictionary:
	var laps := _int_array(result.get(&"lap_times_usec", []))
	if laps.size() < 2:
		return {&"spread_usec": 0, &"variation_ratio": 0.0}
	var minimum := laps[0]
	var maximum := laps[0]
	var total := 0
	for lap_usec: int in laps:
		minimum = mini(minimum, lap_usec)
		maximum = maxi(maximum, lap_usec)
		total += lap_usec
	var average := float(total) / float(laps.size())
	return {
		&"spread_usec": maximum - minimum,
		&"variation_ratio": float(maximum - minimum) / average if average > 0.0 else 0.0,
	}


static func _select_focus(metrics: Dictionary) -> StringName:
	if not bool(metrics.get(&"valid", true)):
		return &"CLASSIFICATION"
	if int(metrics.get(&"crashes", 0)) > 0:
		return &"CRASH_CONTROL"
	if int(metrics.get(&"resets", 0)) > 0:
		return &"RECOVERY"
	if int(metrics.get(&"wrong_way", 0)) > 0 or int(metrics.get(&"cuts", 0)) > 0 or int(metrics.get(&"off_course", 0)) > 1:
		return &"TRACK_DISCIPLINE"
	if int(metrics.get(&"contacts", 0)) >= 3:
		return &"CLEAN_PASSING"
	var worst_delta := int(metrics.get(&"worst_delta_usec", 0))
	var worst_target := int(metrics.get(&"worst_target_usec", 0))
	if worst_delta > maxi(300_000, roundi(float(worst_target) * 0.06)):
		return &"SECTOR_PACE"
	if float(metrics.get(&"lap_variation_ratio", 0.0)) >= 0.04:
		return &"CONSISTENCY"
	if int(metrics.get(&"flow_uses", 0)) == 0 and int(metrics.get(&"position", 1)) > 1:
		return &"FLOW_USAGE"
	if int(metrics.get(&"position", 1)) > 3 and int(metrics.get(&"overtakes", 0)) < 2:
		return &"RACECRAFT"
	return &"PACE"


static func _select_strength(metrics: Dictionary) -> Dictionary:
	if bool(metrics.get(&"fastest_lap", false)):
		return {&"text": "FASTEST LAP PACE"}
	if int(metrics.get(&"position", 1)) == 1 and bool(metrics.get(&"holeshot", false)):
		return {&"text": "LIGHTS-TO-FLAG EXECUTION"}
	if bool(metrics.get(&"clean", false)):
		return {&"text": "CLEAN, CONTROLLED RIDE"}
	if int(metrics.get(&"overtakes", 0)) >= 2:
		return {&"text": "%d DECISIVE PASSES" % int(metrics.get(&"overtakes", 0))}
	if int(metrics.get(&"flow_uses", 0)) >= 2:
		return {&"text": "%d PURPOSEFUL FLOW USES" % int(metrics.get(&"flow_uses", 0))}
	if int(metrics.get(&"best_sector", 0)) > 0 and int(metrics.get(&"best_delta_usec", 0)) < 0:
		return {&"text": "S%02d AHEAD OF TARGET" % int(metrics.get(&"best_sector", 0))}
	return {&"text": "FINISH BANKED"}


static func _coaching_for_focus(
	focus: StringName,
	result: Dictionary,
	sector: Dictionary,
	laps: Dictionary
) -> Dictionary:
	match focus:
		&"CLASSIFICATION":
			return {
				&"headline": "MAKE THE RESULT COUNT",
				&"primary": str(result.get(&"validity_reason", "RUN UNCLASSIFIED")).replace("_", " ").to_upper(),
				&"objective": "COMPLETE EVERY GATE IN ORDER AND BANK A CLASSIFIED FINISH",
			}
		&"CRASH_CONTROL":
			return {
				&"headline": "TRADE ONE RISK FOR MOMENTUM",
				&"primary": "%d CRASH%s BROKE THE RUN RHYTHM" % [int(result.get(&"crashes", 0)), "ES" if int(result.get(&"crashes", 0)) != 1 else ""],
				&"objective": "USE COMPOSE OR BRACE BEFORE THE HIGHEST-RISK LANDING",
			}
		&"RECOVERY":
			return {
				&"headline": "KEEP THE BIKE MOVING",
				&"primary": "%d RESET%s COST MORE THAN A SAFE EXIT" % [int(result.get(&"reset_count", 0)), "S" if int(result.get(&"reset_count", 0)) != 1 else ""],
				&"objective": "FINISH THE NEXT RUN WITHOUT A MANUAL RESET",
			}
		&"TRACK_DISCIPLINE":
			return {
				&"headline": "PROTECT THE RACING LINE",
				&"primary": "OFF-LINE MOMENTS AND GATE RISK GAVE AWAY FREE TIME",
				&"objective": "CLEAR EVERY GATE WITH NO WRONG-WAY OR CUT WARNING",
			}
		&"CLEAN_PASSING":
			return {
				&"headline": "PASS WITH SPACE TO EXIT",
				&"primary": "%d CONTACTS TURNED BATTLES INTO LOST DRIVE" % int(result.get(&"contacts", 0)),
				&"objective": "USE DRAFT, THEN SURGE PAST BEFORE THE BRAKING ZONE",
			}
		&"SECTOR_PACE":
			var sector_id := int(sector.get(&"worst_sector", 0))
			var delta_seconds := float(sector.get(&"worst_delta_usec", 0)) / 1_000_000.0
			return {
				&"headline": "ONE SECTOR HOLDS THE NEXT RESULT",
				&"primary": "S%02d COST %+.2fs AGAINST THE RIVAL TARGET" % [sector_id, delta_seconds],
				&"objective": "REPLAY S%02d, THEN BEAT ITS SPLIT BY 0.50s" % sector_id,
			}
		&"CONSISTENCY":
			return {
				&"headline": "MAKE THE FAST LAP REPEATABLE",
				&"primary": "LAP SPREAD WAS %.2fs" % (float(laps.get(&"spread_usec", 0)) / 1_000_000.0),
				&"objective": "KEEP EVERY LAP WITHIN 4%% OF YOUR BEST",
			}
		&"FLOW_USAGE":
			return {
				&"headline": "TURN FLOW INTO TRACK POSITION",
				&"primary": "NO FLOW TECHNIQUE WAS COMMITTED THIS RUN",
				&"objective": "BANK FLOW, THEN USE SURGE ON THE LONGEST CLEAN EXIT",
			}
		&"RACECRAFT":
			return {
				&"headline": "CREATE THE PASS BEFORE THE CORNER",
				&"primary": "THE FIELD HELD POSITION THROUGH THE KEY BATTLES",
				&"objective": "DRAFT ONE RIVAL AND COMPLETE TWO CLEAN PASSES",
			}
		_:
			return {
				&"headline": "CONVERT CONTROL INTO PACE",
				&"primary": "THE RUN IS CLEAN ENOUGH TO ATTACK THE CLOCK",
				&"objective": "BEAT YOUR COSTLIEST SECTOR WITHOUT ADDING AN INCIDENT",
			}


static func _grade_for_score(score: float) -> StringName:
	if score >= 92.0:
		return &"S"
	if score >= 84.0:
		return &"A"
	if score >= 72.0:
		return &"B"
	if score >= 58.0:
		return &"C"
	return &"D"


static func _route_incidents(evidence: Dictionary) -> int:
	return (
		maxi(int(evidence.get(&"off_course", 0)), 0)
		+ maxi(int(evidence.get(&"wrong_way", 0)), 0)
		+ maxi(int(evidence.get(&"cuts", 0)), 0)
	)


static func _total_incidents(evidence: Dictionary) -> int:
	return (
		maxi(int(evidence.get(&"crashes", 0)), 0)
		+ maxi(int(evidence.get(&"resets", 0)), 0)
		+ maxi(int(evidence.get(&"contacts", 0)), 0)
		+ _route_incidents(evidence)
	)


static func _dictionary(value: Variant) -> Dictionary:
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


static func _int_array(value: Variant) -> Array[int]:
	var output: Array[int] = []
	if value is Array or value is PackedInt64Array or value is PackedInt32Array:
		for entry: Variant in value:
			output.append(maxi(int(entry), 0))
	return output


static func _float_array(value: Variant) -> Array[float]:
	var output: Array[float] = []
	if value is Array or value is PackedFloat32Array or value is PackedFloat64Array:
		for entry: Variant in value:
			output.append(float(entry))
	return output
