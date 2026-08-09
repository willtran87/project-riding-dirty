extends RefCounted
class_name RunPlanAnalysis
## Deterministic comparison of the latest official run against the event PB.
## This class only interprets frozen result evidence; it never changes gameplay.

const MAX_SECTORS := 32
const EVEN_SECTOR_USEC := 50_000
const TECHNIQUE_FOCUS := [
	"CRASH_CONTROL", "RECOVERY", "TRACK_DISCIPLINE", "CLEAN_PASSING",
	"RACECRAFT", "CONSISTENCY", "FLOW_USAGE",
]


static func compare(previous: Dictionary, personal_best: Dictionary, debrief: Dictionary = {}) -> Dictionary:
	if previous.is_empty() or personal_best.is_empty():
		return {}
	var previous_time := int(previous.get(&"effective_time_usec", -1))
	var best_time := int(personal_best.get(&"effective_time_usec", -1))
	if previous_time <= 0 or best_time <= 0:
		return {}

	var previous_plan := previous.get(&"plan", {}) as Dictionary
	var best_plan := personal_best.get(&"plan", {}) as Dictionary
	var changed_fields := _changed_plan_fields(previous_plan, best_plan)
	var conditions_changed := _conditions_changed(previous_plan, best_plan)
	var strategy_changed := _strategy_changed(previous_plan, best_plan)
	var attribution := &"EXECUTION_COMPARABLE"
	if conditions_changed and strategy_changed:
		attribution = &"MIXED_CHANGES"
	elif conditions_changed:
		attribution = &"CONDITIONS_CHANGED"
	elif strategy_changed:
		attribution = &"PLAN_CHANGED"

	var sectors := _sector_rows(
		previous.get(&"sector_times_usec", []) as Array,
		personal_best.get(&"sector_times_usec", []) as Array
	)
	var opportunity_sector := 0
	var opportunity_usec := 0
	var latest_advantage_sector := 0
	var latest_advantage_usec := 0
	for row: Dictionary in sectors:
		var delta := int(row.get(&"previous_minus_pb_usec", 0))
		if delta > opportunity_usec:
			opportunity_usec = delta
			opportunity_sector = int(row.get(&"sector", 0))
		elif delta < latest_advantage_usec:
			latest_advantage_usec = delta
			latest_advantage_sector = int(row.get(&"sector", 0))

	var total_delta := previous_time - best_time
	var focus := str(debrief.get(&"focus_id", debrief.get(&"focus", ""))).to_upper()
	var recommendation := _recommendation(
		attribution, focus, opportunity_sector, opportunity_usec, total_delta
	)
	return {
		&"previous_minus_pb_usec": total_delta,
		&"pace_state": _pace_state(total_delta),
		&"summary": _summary(total_delta, opportunity_sector, opportunity_usec),
		&"attribution": attribution,
		&"attribution_label": _attribution_label(attribution, changed_fields),
		&"comparable": attribution == &"EXECUTION_COMPARABLE",
		&"changed_fields": changed_fields,
		&"sector_rows": sectors,
		&"opportunity_sector": opportunity_sector,
		&"opportunity_usec": opportunity_usec,
		&"latest_advantage_sector": latest_advantage_sector,
		&"latest_advantage_usec": absi(latest_advantage_usec),
		&"crash_delta": int(previous.get(&"crashes", 0)) - int(personal_best.get(&"crashes", 0)),
		&"contact_delta": int(previous.get(&"contacts", 0)) - int(personal_best.get(&"contacts", 0)),
		&"reset_delta": int(previous.get(&"resets", 0)) - int(personal_best.get(&"resets", 0)),
		&"flow_delta": int(previous.get(&"flow_uses", 0)) - int(personal_best.get(&"flow_uses", 0)),
		&"recommendation": recommendation,
	}


static func _sector_rows(previous: Array, personal_best: Array) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var count := mini(mini(previous.size(), personal_best.size()), MAX_SECTORS)
	for index: int in count:
		var previous_usec := maxi(int(previous[index]), 0)
		var best_usec := maxi(int(personal_best[index]), 0)
		if previous_usec <= 0 or best_usec <= 0:
			continue
		var delta := previous_usec - best_usec
		var state := &"EVEN"
		if delta > EVEN_SECTOR_USEC:
			state = &"PB_FASTER"
		elif delta < -EVEN_SECTOR_USEC:
			state = &"LATEST_FASTER"
		output.append({
			&"sector": index + 1,
			&"previous_usec": previous_usec,
			&"personal_best_usec": best_usec,
			&"previous_minus_pb_usec": delta,
			&"state": state,
		})
	return output


static func _changed_plan_fields(previous: Dictionary, personal_best: Dictionary) -> PackedStringArray:
	var changed := PackedStringArray()
	var fields := [
		&"bike_id", &"selected_class", &"setup_id", &"installed_parts", &"tune",
		&"livery_id", &"assist_mode", &"difficulty", &"transmission_mode",
		&"control_signature", &"crash_support_mode", &"weather", &"surface",
	]
	for field: StringName in fields:
		if previous.get(field) != personal_best.get(field):
			changed.append(String(field).to_upper())
	return changed


static func _conditions_changed(previous: Dictionary, personal_best: Dictionary) -> bool:
	return (
		previous.get(&"weather") != personal_best.get(&"weather")
		or previous.get(&"surface") != personal_best.get(&"surface")
	)


static func _strategy_changed(previous: Dictionary, personal_best: Dictionary) -> bool:
	for field: StringName in [
		&"bike_id", &"selected_class", &"setup_id", &"installed_parts", &"tune",
		&"assist_mode", &"difficulty", &"transmission_mode", &"control_signature",
		&"crash_support_mode",
	]:
		if previous.get(field) != personal_best.get(field):
			return true
	return false


static func _pace_state(delta_usec: int) -> StringName:
	if delta_usec > EVEN_SECTOR_USEC:
		return &"PB_AHEAD"
	if delta_usec < -EVEN_SECTOR_USEC:
		return &"LATEST_AHEAD"
	return &"MATCHED"


static func _summary(total_delta: int, opportunity_sector: int, opportunity_usec: int) -> String:
	var absolute_seconds := float(absi(total_delta)) / 1_000_000.0
	var total_text := "MATCHED PB"
	if total_delta > EVEN_SECTOR_USEC:
		total_text = "PB AHEAD %.3fs" % absolute_seconds
	elif total_delta < -EVEN_SECTOR_USEC:
		total_text = "LATEST AHEAD %.3fs" % absolute_seconds
	if opportunity_sector > 0 and opportunity_usec > EVEN_SECTOR_USEC:
		return "%s  //  BIGGEST GAP S%d +%.3fs" % [
			total_text, opportunity_sector, float(opportunity_usec) / 1_000_000.0,
		]
	return total_text


static func _attribution_label(attribution: StringName, changed_fields: PackedStringArray) -> String:
	match attribution:
		&"EXECUTION_COMPARABLE":
			return "MATCHED PLAN + CONDITIONS  //  EXECUTION COMPARISON"
		&"CONDITIONS_CHANGED":
			return "CONDITIONS CHANGED  //  DO NOT ATTRIBUTE THE DELTA TO RIDING ALONE"
		&"PLAN_CHANGED":
			return "PLAN CHANGED: %s  //  RESULT IS CONFOUNDED" % ", ".join(changed_fields)
		_:
			return "PLAN + CONDITIONS CHANGED  //  RESULT IS CONFOUNDED"


static func _recommendation(
	attribution: StringName,
	focus: String,
	opportunity_sector: int,
	opportunity_usec: int,
	total_delta: int
) -> String:
	if focus in TECHNIQUE_FOCUS:
		return "NEXT: KEEP THE PLAN, WORK THE %s OBJECTIVE" % focus.replace("_", " ")
	if attribution == &"CONDITIONS_CHANGED" or attribution == &"MIXED_CHANGES":
		return "NEXT: REPEAT IN MATCHED CONDITIONS BEFORE CHANGING THE BIKE"
	if attribution == &"PLAN_CHANGED":
		return "NEXT: REPEAT ONE PLAN AND CHANGE ONE VARIABLE AT A TIME"
	if opportunity_sector > 0 and opportunity_usec > EVEN_SECTOR_USEC:
		return "NEXT: KEEP THIS PLAN AND CHASE SECTOR %d" % opportunity_sector
	if total_delta < -EVEN_SECTOR_USEC:
		return "NEXT: BANK THE CLEANER LATEST EXECUTION AND PUSH ONE SECTOR"
	return "NEXT: KEEP THE PLAN AND TARGET A CLEAN, REPEATABLE RUN"
