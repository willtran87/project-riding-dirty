extends RefCounted
class_name RacingAcademyLessonCatalog
## Data-driven riding lessons with deterministic metric-based grading.

const DEFAULT_LESSONS: Array[Dictionary] = [
	{
		&"lesson_id": &"CONTROL_BASICS", &"display_name": "Throttle and Brake Control", &"category": &"FOUNDATIONS",
		&"description": "Hold a clean line through the marked gates without panic inputs.", &"sort_order": 0,
		&"presentation": {&"racecraft_focus": &"NONE", &"show_flow_meter": false},
		&"coach_template": "GATES: HOLD {THROTTLE}; GUIDE WITH {STEER}; {BRAKE} BEFORE EACH TURN, THEN RELEASE. USE {RESET} ONLY IF STRANDED.",
		&"coach_actions": [&"throttle", &"steer_left", &"steer_right", &"brake", &"reset_bike"],
		&"required_reputation": 0, &"prerequisites": [], &"rewards": {&"credits": 500, &"reputation": 5},
		&"objectives": [
			{&"metric": &"gates_completed", &"comparison": &"AT_LEAST", &"bronze": 6.0, &"silver": 8.0, &"gold": 10.0},
			{&"metric": &"resets", &"comparison": &"AT_MOST", &"bronze": 2.0, &"silver": 1.0, &"gold": 0.0},
		],
	},
	{
		&"lesson_id": &"GATE_DROP", &"display_name": "Gate Drop and Holeshot", &"category": &"STARTS",
		&"description": "Balance revs, reaction, and traction through the first turn.", &"sort_order": 1,
		&"presentation": {&"racecraft_focus": &"NONE", &"show_flow_meter": false},
		&"coach_template": "STAGE: HOLD {THROTTLE} + {BRAKE}. RELEASE {BRAKE} JUST BEFORE GREEN; KEEP {THROTTLE} PINNED FOR FOUR SECONDS.",
		&"coach_actions": [&"throttle", &"brake"],
		&"required_reputation": 0, &"prerequisites": [&"CONTROL_BASICS"], &"rewards": {&"credits": 650, &"reputation": 6},
		&"objectives": [
			{&"metric": &"reaction_seconds", &"comparison": &"AT_MOST", &"bronze": 0.55, &"silver": 0.38, &"gold": 0.26},
			{&"metric": &"launch_speed", &"comparison": &"AT_LEAST", &"bronze": 13.0, &"silver": 15.0, &"gold": 17.0},
		],
	},
	{
		&"lesson_id": &"BERM_LINES", &"display_name": "Inside and Outside Berms", &"category": &"CORNERING",
		&"description": "Capture the physical rut, then rear-brake slide into a supported berm exit.", &"sort_order": 2,
		&"presentation": {&"racecraft_focus": &"CORNERING", &"show_flow_meter": false},
		&"coach_template": "RUT: ENTER WITH {STEER} AND HOLD ALIGNMENT 0.6 SEC. SLIDE: ABOVE 6 M/S, HOLD {BRAKE} + {STEER} 0.4 SEC; FEED {THROTTLE} TO CATCH IT.",
		&"coach_actions": [&"steer_left", &"steer_right", &"brake", &"throttle"],
		&"required_reputation": 10, &"prerequisites": [&"CONTROL_BASICS"], &"rewards": {&"credits": 800, &"reputation": 8},
		&"objectives": [
			{&"metric": &"rut_rails", &"comparison": &"AT_LEAST", &"bronze": 1.0, &"silver": 2.0, &"gold": 3.0},
			{&"metric": &"controlled_slides", &"comparison": &"AT_LEAST", &"bronze": 1.0, &"silver": 2.0, &"gold": 3.0},
		],
	},
	{
		&"lesson_id": &"PRELOAD_LANDING", &"display_name": "Preload and Landing", &"category": &"JUMPING",
		&"description": "Load the suspension, press technique through compression, and match the receiver.", &"sort_order": 3,
		&"presentation": {&"racecraft_focus": &"JUMPING", &"show_flow_meter": false},
		&"coach_template": "JUMP: HOLD {PRELOAD}, RELEASE ON THE LOADED LIP; MATCH THE RECEIVER WITH {LEAN_STEER}. PUMP: TAP {TECHNIQUE} WITH BOTH WHEELS LOADED.",
		&"coach_actions": [&"preload", &"lean_forward", &"lean_back", &"steer_left", &"steer_right", &"racecraft_technique"],
		&"required_reputation": 20, &"prerequisites": [&"BERM_LINES"], &"rewards": {&"credits": 950, &"reputation": 10},
		&"objectives": [
			{&"metric": &"pumps", &"comparison": &"AT_LEAST", &"bronze": 1.0, &"silver": 2.0, &"gold": 3.0},
			{&"metric": &"clean_landings", &"comparison": &"AT_LEAST", &"bronze": 2.0, &"silver": 4.0, &"gold": 6.0},
		],
	},
	{
		&"lesson_id": &"RHYTHM_CHOICES", &"display_name": "Rhythm Combinations", &"category": &"JUMPING",
		&"description": "Read each highlighted inside, rut, or berm fork and commit before entry.", &"sort_order": 4,
		&"presentation": {&"racecraft_focus": &"FAST_LINE", &"show_flow_meter": false},
		&"coach_template": "FAST LINE: HOLD {STEER} TOWARD RUT / BERM BEFORE ACTIVE. FOR PUMP, TAP {TECHNIQUE} ON TWO-WHEEL COMPRESSION; MATCH LANDINGS WITH {LEAN}.",
		&"coach_actions": [&"steer_left", &"steer_right", &"racecraft_technique", &"lean_forward", &"lean_back"],
		&"required_reputation": 40, &"prerequisites": [&"PRELOAD_LANDING"], &"rewards": {&"credits": 1_200, &"reputation": 12},
		&"objectives": [
			{&"metric": &"clean_skill_lines", &"comparison": &"AT_LEAST", &"bronze": 2.0, &"silver": 3.0, &"gold": 4.0},
			{&"metric": &"cases", &"comparison": &"AT_MOST", &"bronze": 2.0, &"silver": 1.0, &"gold": 0.0},
		],
	},
	{
		&"lesson_id": &"AIR_CONTROL", &"display_name": "Scrub and Air Control", &"category": &"ADVANCED",
		&"description": "Lean forward to scrub excess height, then spend Context Flow to compose a receiver.", &"sort_order": 5,
		&"presentation": {&"racecraft_focus": &"AIR_FLOW", &"show_flow_meter": true},
		&"coach_template": "SCRUB: WHILE RISING, HOLD {LEAN_FORWARD} FOR 0.25 SEC. COMPOSE: BANK 24 FLOW, THEN TAP {FLOW} AIRBORNE NEAR THE RECEIVER.",
		&"coach_actions": [&"lean_forward", &"flow_boost"],
		&"required_reputation": 80, &"prerequisites": [&"RHYTHM_CHOICES"], &"rewards": {&"credits": 1_500, &"reputation": 15},
		&"objectives": [
			{&"metric": &"scrubs", &"comparison": &"AT_LEAST", &"bronze": 1.0, &"silver": 3.0, &"gold": 5.0},
			{&"metric": &"compose_saves", &"comparison": &"AT_LEAST", &"bronze": 1.0, &"silver": 2.0, &"gold": 3.0},
		],
	},
	{
		&"lesson_id": &"SAFE_RECOVERY", &"display_name": "Recovery and Rejoin", &"category": &"RACECRAFT",
		&"description": "Use a low-speed foot dab to catch the bike, then rejoin without contact.", &"sort_order": 6,
		&"presentation": {&"racecraft_focus": &"RECOVERY", &"show_flow_meter": false},
		&"coach_template": "DAB: {BRAKE} BELOW 5 M/S WITH BOTH WHEELS DOWN, THEN TAP {TECHNIQUE}. REJOIN WITH {STEER} + {THROTTLE}; {RESET} ONLY IF STRANDED.",
		&"coach_actions": [&"brake", &"racecraft_technique", &"steer_left", &"steer_right", &"throttle", &"reset_bike"],
		&"required_reputation": 55, &"prerequisites": [&"BERM_LINES"], &"rewards": {&"credits": 1_000, &"reputation": 10},
		&"objectives": [
			{&"metric": &"dabs", &"comparison": &"AT_LEAST", &"bronze": 1.0, &"silver": 2.0, &"gold": 3.0},
			{&"metric": &"rejoin_contacts", &"comparison": &"AT_MOST", &"bronze": 1.0, &"silver": 0.0, &"gold": 0.0},
		],
	},
	{
		&"lesson_id": &"PASSING_RACECRAFT", &"display_name": "Passing Racecraft", &"category": &"RACECRAFT",
		&"description": "Sit in clean air, pull from the roost, and slingshot past without contact.", &"sort_order": 7,
		&"presentation": {&"racecraft_focus": &"PASSING", &"show_flow_meter": false},
		&"coach_template": "DRAFT: TUCK DIRECTLY BEHIND TO 28%+. SLINGSHOT WITH {STEER} + {THROTTLE} WITHIN ONE SECOND; USE {BRAKE} TO ABORT CONTACT.",
		&"coach_actions": [&"steer_left", &"steer_right", &"throttle", &"brake"],
		&"required_reputation": 100, &"prerequisites": [&"GATE_DROP", &"RHYTHM_CHOICES"], &"rewards": {&"credits": 1_800, &"reputation": 18},
		&"objectives": [
			{&"metric": &"draft_slingshots", &"comparison": &"AT_LEAST", &"bronze": 1.0, &"silver": 2.0, &"gold": 3.0},
			{&"metric": &"contacts", &"comparison": &"AT_MOST", &"bronze": 3.0, &"silver": 1.0, &"gold": 0.0},
		],
	},
]

var lessons: Array[Dictionary] = []


static func create_default() -> RacingAcademyLessonCatalog:
	var catalog := RacingAcademyLessonCatalog.new()
	catalog.configure(DEFAULT_LESSONS)
	return catalog


static func from_dictionary(data: Dictionary) -> RacingAcademyLessonCatalog:
	var catalog := RacingAcademyLessonCatalog.new()
	catalog.configure(_dictionary_array(data.get(&"lessons", DEFAULT_LESSONS)))
	return catalog


func configure(source: Array[Dictionary]) -> void:
	lessons.clear()
	var seen: Dictionary = {}
	for source_index: int in source.size():
		var lesson := source[source_index].duplicate(true)
		var lesson_id := StringName(lesson.get(&"lesson_id", &""))
		if lesson_id.is_empty() or seen.has(lesson_id):
			continue
		seen[lesson_id] = true
		lesson[&"lesson_id"] = lesson_id
		lesson[&"display_name"] = str(lesson.get(&"display_name", String(lesson_id).capitalize()))
		lesson[&"category"] = StringName(lesson.get(&"category", &"FOUNDATIONS"))
		lesson[&"description"] = str(lesson.get(&"description", ""))
		lesson[&"coach_template"] = str(lesson.get(&"coach_template", "")).strip_edges().substr(0, 320)
		lesson[&"coach_actions"] = _unique_string_name_array(lesson.get(&"coach_actions", []), 10)
		lesson[&"presentation"] = _normalize_presentation(lesson.get(&"presentation", {}))
		lesson[&"sort_order"] = int(lesson.get(&"sort_order", source_index))
		lesson[&"required_reputation"] = maxi(int(lesson.get(&"required_reputation", 0)), 0)
		lesson[&"prerequisites"] = _string_name_array(lesson.get(&"prerequisites", []))
		lesson[&"objectives"] = _normalize_objectives(lesson.get(&"objectives", []))
		var rewards := lesson.get(&"rewards", {}) as Dictionary
		lesson[&"rewards"] = {
			&"credits": maxi(int(rewards.get(&"credits", 0)), 0),
			&"reputation": maxi(int(rewards.get(&"reputation", 0)), 0),
		}
		lessons.append(lesson)
	lessons.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		return int(first.get(&"sort_order", 0)) < int(second.get(&"sort_order", 0))
	)


func has_lesson(lesson_id: StringName) -> bool:
	return not get_lesson(lesson_id).is_empty()


func get_lesson(lesson_id: StringName) -> Dictionary:
	for lesson: Dictionary in lessons:
		if StringName(lesson.get(&"lesson_id", &"")) == lesson_id:
			return lesson.duplicate(true)
	return {}


func get_lessons() -> Array[Dictionary]:
	return lessons.duplicate(true)


func get_available_lessons(completed_lesson_ids: Array[StringName], reputation: int) -> Array[Dictionary]:
	var completed: Dictionary = {}
	for lesson_id: StringName in completed_lesson_ids:
		completed[lesson_id] = true
	var output: Array[Dictionary] = []
	for lesson: Dictionary in lessons:
		if reputation < int(lesson.get(&"required_reputation", 0)):
			continue
		var unlocked := true
		for prerequisite: StringName in _string_name_array(lesson.get(&"prerequisites", [])):
			if not completed.has(prerequisite):
				unlocked = false
				break
		if unlocked:
			output.append(lesson.duplicate(true))
	return output


func evaluate_lesson(lesson_id: StringName, metrics: Dictionary) -> Dictionary:
	var lesson := get_lesson(lesson_id)
	if lesson.is_empty():
		return {&"lesson_id": lesson_id, &"passed": false, &"stars": 0, &"objective_results": [], &"rewards": {}}
	var objective_results: Array[Dictionary] = []
	var stars := 3
	var objectives := _dictionary_array(lesson.get(&"objectives", []))
	if objectives.is_empty():
		stars = 0
	for objective: Dictionary in objectives:
		var metric := StringName(objective.get(&"metric", &""))
		var has_metric := metrics.has(metric) or metrics.has(String(metric))
		var value := float(metrics.get(metric, metrics.get(String(metric), 0.0)))
		var grade := _objective_grade(objective, value) if has_metric else 0
		stars = mini(stars, grade)
		objective_results.append({
			&"metric": metric,
			&"value": value,
			&"comparison": StringName(objective.get(&"comparison", &"AT_LEAST")),
			&"grade": grade,
			&"passed": grade > 0,
		})
	var passed := stars > 0
	return {
		&"lesson_id": lesson_id,
		&"passed": passed,
		&"stars": stars,
		&"objective_results": objective_results,
		&"rewards": (lesson.get(&"rewards", {}) as Dictionary).duplicate(true) if passed else {},
	}


func to_dictionary() -> Dictionary:
	return {&"lessons": lessons.duplicate(true)}


static func _objective_grade(objective: Dictionary, value: float) -> int:
	var comparison := StringName(objective.get(&"comparison", &"AT_LEAST"))
	var bronze := float(objective.get(&"bronze", 0.0))
	var silver := float(objective.get(&"silver", bronze))
	var gold := float(objective.get(&"gold", silver))
	match comparison:
		&"AT_MOST":
			if value <= gold: return 3
			if value <= silver: return 2
			if value <= bronze: return 1
		&"EQUAL":
			if is_equal_approx(value, gold): return 3
			if is_equal_approx(value, silver): return 2
			if is_equal_approx(value, bronze): return 1
		_:
			if value >= gold: return 3
			if value >= silver: return 2
			if value >= bronze: return 1
	return 0


static func _dictionary_array(value: Variant) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	if value is Array:
		for entry: Variant in value:
			if entry is Dictionary:
				output.append((entry as Dictionary).duplicate(true))
	return output


static func _normalize_objectives(value: Variant) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for objective: Dictionary in _dictionary_array(value):
		output.append({
			&"metric": StringName(objective.get(&"metric", &"")),
			&"comparison": StringName(objective.get(&"comparison", &"AT_LEAST")),
			&"bronze": float(objective.get(&"bronze", 0.0)),
			&"silver": float(objective.get(&"silver", objective.get(&"bronze", 0.0))),
			&"gold": float(objective.get(&"gold", objective.get(&"silver", objective.get(&"bronze", 0.0)))),
		})
	return output


static func _normalize_presentation(value: Variant) -> Dictionary:
	## Academy owns its goals, rewards, and coaching. Ordinary event overlays stay
	## opt-in so a lesson never teaches several unrelated systems at once.
	var source := value as Dictionary if value is Dictionary else {}
	var focus := StringName(source.get(&"racecraft_focus", &"NONE"))
	if focus not in [&"NONE", &"CORNERING", &"JUMPING", &"FAST_LINE", &"AIR_FLOW", &"RECOVERY", &"PASSING"]:
		focus = &"NONE"
	return {
		&"racecraft_focus": focus,
		&"show_flow_meter": bool(source.get(&"show_flow_meter", false)),
		&"show_line_feedback": bool(source.get(&"show_line_feedback", false)),
		&"show_sponsor_contract": bool(source.get(&"show_sponsor_contract", false)),
		&"show_daily_modifier": bool(source.get(&"show_daily_modifier", false)),
	}


static func _string_name_array(value: Variant) -> Array[StringName]:
	var output: Array[StringName] = []
	if value is Array or value is PackedStringArray:
		for entry: Variant in value:
			output.append(StringName(entry))
	return output


static func _unique_string_name_array(value: Variant, limit: int) -> Array[StringName]:
	var output: Array[StringName] = []
	for entry: StringName in _string_name_array(value):
		if entry.is_empty() or entry in output:
			continue
		output.append(entry)
		if output.size() >= limit:
			break
	return output
