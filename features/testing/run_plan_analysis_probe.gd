extends Node
## Previous/PB analysis must be deterministic, honest about confounds, and actionable.

const ANALYSIS := preload("res://features/race/run_plan_analysis.gd")

var _failures := PackedStringArray()


func _ready() -> void:
	var baseline_plan := _plan(&"BALANCED", &"CLEAR", &"PACKED")
	var previous := _run(120_000_000, [39_000_000, 43_000_000, 38_000_000], 1, 2, 1, baseline_plan)
	var personal_best := _run(116_000_000, [40_000_000, 38_000_000, 38_000_000], 0, 1, 3, baseline_plan)
	var comparable: Dictionary = ANALYSIS.compare(previous, personal_best)
	_assert(int(comparable.get(&"previous_minus_pb_usec", 0)) == 4_000_000, "total PB delta is wrong")
	_assert(StringName(comparable.get(&"attribution", &"")) == &"EXECUTION_COMPARABLE", "matched evidence was not comparable")
	_assert(int(comparable.get(&"opportunity_sector", 0)) == 2, "costliest sector was not identified")
	_assert(int(comparable.get(&"latest_advantage_sector", 0)) == 1, "latest-run gain was not identified")
	_assert(int(comparable.get(&"crash_delta", 0)) == 1 and int(comparable.get(&"flow_delta", 0)) == -2, "execution metrics are wrong")
	_assert(str(comparable.get(&"recommendation", "")).contains("SECTOR 2"), "matched comparison did not coach the costliest sector")

	var changed_plan := baseline_plan.duplicate(true)
	changed_plan[&"setup_id"] = &"ATTACK"
	var confounded: Dictionary = ANALYSIS.compare(previous, _run(116_000_000, [40_000_000, 38_000_000, 38_000_000], 0, 1, 3, changed_plan))
	_assert(StringName(confounded.get(&"attribution", &"")) == &"PLAN_CHANGED", "setup change was falsely attributed to execution")
	_assert(not bool(confounded.get(&"comparable", true)), "confounded evidence was marked comparable")
	_assert(str(confounded.get(&"recommendation", "")).contains("ONE VARIABLE"), "confounded result lacks controlled-comparison guidance")

	var changed_conditions := changed_plan.duplicate(true)
	changed_conditions[&"weather"] = &"RAIN"
	var mixed: Dictionary = ANALYSIS.compare(previous, _run(116_000_000, [40_000_000, 38_000_000, 38_000_000], 0, 1, 3, changed_conditions))
	_assert(StringName(mixed.get(&"attribution", &"")) == &"MIXED_CHANGES", "mixed plan/conditions were not identified")
	_assert(str(mixed.get(&"recommendation", "")).contains("MATCHED CONDITIONS"), "mixed comparison lacks matched-condition guidance")

	var technique: Dictionary = ANALYSIS.compare(previous, personal_best, {&"focus_id": &"CRASH_CONTROL"})
	_assert(str(technique.get(&"recommendation", "")).contains("CRASH CONTROL"), "debrief technique priority was replaced by setup advice")
	_assert(ANALYSIS.compare({}, personal_best).is_empty(), "missing runs should not manufacture analysis")

	var passed := _failures.is_empty()
	print("RUN PLAN ANALYSIS PROBE: delta=%d sector=%d attribution=%s mixed=%s technique=%s passed=%s failures=%s" % [
		int(comparable.get(&"previous_minus_pb_usec", 0)),
		int(comparable.get(&"opportunity_sector", 0)),
		str(confounded.get(&"attribution", "")),
		str(mixed.get(&"attribution", "")),
		str(technique.get(&"recommendation", "")),
		str(passed), ", ".join(_failures),
	])
	get_tree().quit(0 if passed else 1)


func _plan(setup_id: StringName, weather: StringName, surface: StringName) -> Dictionary:
	return {
		&"bike_id": &"TYKE_125", &"selected_class": &"LITE_125", &"setup_id": setup_id,
		&"installed_parts": {}, &"tune": {&"gearing": 0.0}, &"assist_mode": &"SPORT",
		&"difficulty": 1, &"transmission_mode": &"AUTOMATIC", &"control_signature": "DEFAULT",
		&"crash_support_mode": &"STANDARD", &"weather": weather, &"surface": surface,
	}


func _run(time_usec: int, sectors: Array, crashes: int, contacts: int, flow: int, plan: Dictionary) -> Dictionary:
	return {
		&"effective_time_usec": time_usec, &"sector_times_usec": sectors,
		&"crashes": crashes, &"contacts": contacts, &"resets": 0, &"flow_uses": flow,
		&"plan": plan.duplicate(true),
	}


func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
