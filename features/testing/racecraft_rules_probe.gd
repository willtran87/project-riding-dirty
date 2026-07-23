extends Node
## Headless, main-scene-free contract for the deterministic racecraft rules.

const RULES := preload("res://features/race/racecraft_rules.gd")

var _passed := true


func _ready() -> void:
	var bounds := _verify_bounds()
	var deterministic := _verify_determinism()
	var surfaces := _verify_surface_ordering()
	var energy := _verify_energy_caps()
	var priority := _verify_flow_priority()
	var line_choices := _verify_skill_line_choices()
	var line_guidance := _verify_skill_line_guidance()
	_passed = bounds and deterministic and surfaces and energy and priority and line_choices and line_guidance
	print("RACECRAFT RULES PROBE: bounds=%s deterministic=%s surfaces=%s energy=%s priority=%s line_choices=%s line_guidance=%s passed=%s" % [
		str(bounds), str(deterministic), str(surfaces), str(energy), str(priority),
		str(line_choices), str(line_guidance), str(_passed),
	])
	if not _passed:
		push_error("RACECRAFT RULES PROBE: deterministic racecraft contract failed.")
	get_tree().quit(0 if _passed else 1)


func _verify_bounds() -> bool:
	var passed := true
	var extremes: Array[float] = [-10.0, -1.0, 0.0, 0.5, 1.0, 10.0]
	for a: float in extremes:
		for b: float in extremes:
			for c: float in extremes:
				var scrub: float = RULES.scrub_momentum_multiplier(a, b, c)
				var pump: float = RULES.pump_momentum_multiplier(a, b, c)
				var landing: float = RULES.landing_momentum_multiplier(a, b, c, a)
				var slide: Dictionary = RULES.rear_slide_factors(&"LOAM", a, b, c)
				var roost: Dictionary = RULES.evaluate_roost(&"MUD", a, b, 5.0, c, a)
				passed = passed and _in_range(scrub, RULES.SCRUB_MOMENTUM_MIN, RULES.SCRUB_MOMENTUM_MAX)
				passed = passed and _in_range(pump, RULES.PUMP_MOMENTUM_MIN, RULES.PUMP_MOMENTUM_MAX)
				passed = passed and _in_range(landing, RULES.LANDING_MOMENTUM_MIN, RULES.LANDING_MOMENTUM_MAX)
				passed = passed and _in_range(float(slide[&"grip_factor"]), 0.40, 1.0)
				passed = passed and _in_range(float(slide[&"exit_factor"]), RULES.REAR_SLIDE_EXIT_MIN, RULES.REAR_SLIDE_EXIT_MAX)
				passed = passed and _in_range(float(roost[&"pressure"]), 0.0, RULES.ROOST_PRESSURE_MAX)
				passed = passed and _in_range(float(roost[&"drive_cost_fraction"]), 0.0, RULES.ROOST_DRIVE_COST_MAX)
	var draft: float = RULES.draft_strength_from_dots(8.0, 0.0, 1.0, 1.0)
	var skill: Dictionary = RULES.evaluate_skill_line(10.0, 10.0, 10.0, 10.0, -10.0)
	var rut: Dictionary = RULES.evaluate_rut(&"DIRT", 10.0, 1.0, -10.0, 10.0)
	passed = passed and _in_range(draft, 0.0, RULES.DRAFT_STRENGTH_MAX)
	passed = passed and _in_range(float(skill[&"momentum_multiplier"]), RULES.SKILL_LINE_MOMENTUM_MIN, RULES.SKILL_LINE_MOMENTUM_MAX)
	passed = passed and _in_range(float(rut[&"momentum_multiplier"]), RULES.RUT_MOMENTUM_MIN, RULES.RUT_MOMENTUM_MAX)
	return passed


func _verify_determinism() -> bool:
	var first: Array[Variant] = [
		RULES.evaluate_flow_technique(42.0, true, 0.8, -0.7, 0.1, 0.1, 0.2),
		RULES.rear_slide_factors(&"LOAM", 0.84, 0.76, 0.91),
		RULES.evaluate_roost(&"DIRT", 0.72, 0.93, 6.5, 0.88, 0.77),
		RULES.evaluate_skill_line(0.78, 0.86, 0.74, 0.91, 0.62),
		RULES.evaluate_rut(&"LOOSE_DIRT", 0.91, 0.94, 0.22, 0.72),
	]
	var second: Array[Variant] = [
		RULES.evaluate_flow_technique(42.0, true, 0.8, -0.7, 0.1, 0.1, 0.2),
		RULES.rear_slide_factors(&"LOAM", 0.84, 0.76, 0.91),
		RULES.evaluate_roost(&"DIRT", 0.72, 0.93, 6.5, 0.88, 0.77),
		RULES.evaluate_skill_line(0.78, 0.86, 0.74, 0.91, 0.62),
		RULES.evaluate_rut(&"LOOSE_DIRT", 0.91, 0.94, 0.22, 0.72),
	]
	return first == second


func _verify_surface_ordering() -> bool:
	var packed: Dictionary = RULES.rear_slide_factors(&"PACKED", 1.0, 1.0, 1.0)
	var dirt: Dictionary = RULES.rear_slide_factors(&"DIRT", 1.0, 1.0, 1.0)
	var loam: Dictionary = RULES.rear_slide_factors(&"LOAM", 1.0, 1.0, 1.0)
	var gravel: Dictionary = RULES.rear_slide_factors(&"GRAVEL", 1.0, 1.0, 1.0)
	var mud: Dictionary = RULES.rear_slide_factors(&"MUD", 1.0, 1.0, 1.0)
	var grip_ordered := (
		float(packed[&"grip_factor"]) > float(dirt[&"grip_factor"])
		and float(dirt[&"grip_factor"]) > float(loam[&"grip_factor"])
		and float(loam[&"grip_factor"]) > float(gravel[&"grip_factor"])
		and float(gravel[&"grip_factor"]) > float(mud[&"grip_factor"])
	)
	var exit_ordered := (
		float(loam[&"exit_factor"]) > float(dirt[&"exit_factor"])
		and float(dirt[&"exit_factor"]) > float(gravel[&"exit_factor"])
		and float(gravel[&"exit_factor"]) > float(mud[&"exit_factor"])
	)
	var roost_mud: float = RULES.roost_pressure_factor(&"MUD", 1.0, 1.0, 5.0, 1.0)
	var roost_loam: float = RULES.roost_pressure_factor(&"LOAM", 1.0, 1.0, 5.0, 1.0)
	var roost_dirt: float = RULES.roost_pressure_factor(&"DIRT", 1.0, 1.0, 5.0, 1.0)
	var roost_rock: float = RULES.roost_pressure_factor(&"ROCK", 1.0, 1.0, 5.0, 1.0)
	var roost_ordered := roost_mud > roost_loam and roost_loam > roost_dirt and roost_dirt > roost_rock
	var fallback: Dictionary = RULES.rear_slide_factors(&"ALIEN_GOO", 1.0, 1.0, 1.0)
	var fallback_safe := StringName(fallback[&"surface"]) == &"PACKED" and is_equal_approx(
		float(fallback[&"grip_factor"]),
		float(packed[&"grip_factor"])
	)
	return grip_ordered and exit_ordered and roost_ordered and fallback_safe


func _verify_energy_caps() -> bool:
	var clean_scrub: float = RULES.scrub_momentum_multiplier(-1.0, 1.0, 1.0)
	var best_pump: float = RULES.pump_momentum_multiplier(1.0, 1.0, 1.0)
	var empty_pump: float = RULES.pump_momentum_multiplier(0.0, 1.0, 1.0)
	var perfect_landing: float = RULES.landing_momentum_multiplier(1.0, 1.0, 0.0, 1.0)
	var caught_slide: Dictionary = RULES.rear_slide_factors(&"LOAM", 1.0, 1.0, 1.0)
	var free_slide: Dictionary = RULES.rear_slide_factors(&"LOAM", 1.0, 0.0, 0.0)
	var mastered: Dictionary = RULES.evaluate_skill_line(1.0, 1.0, 1.0, 1.0, 0.0)
	var railed: Dictionary = RULES.evaluate_rut(&"LOAM", 1.0, 0.9, 0.0, 1.0)
	return (
		clean_scrub <= RULES.SCRUB_MOMENTUM_MAX
		and best_pump <= RULES.PUMP_MOMENTUM_MAX
		and is_equal_approx(empty_pump, 1.0)
		and perfect_landing <= RULES.LANDING_MOMENTUM_MAX
		and float(caught_slide[&"exit_factor"]) <= RULES.REAR_SLIDE_EXIT_MAX
		and float(free_slide[&"exit_factor"]) <= 1.0
		and float(mastered[&"momentum_multiplier"]) <= RULES.SKILL_LINE_MOMENTUM_MAX
		and float(railed[&"momentum_multiplier"]) <= RULES.RUT_MOMENTUM_MAX
		and RULES.roost_drive_cost_fraction(1.0, 1.0) <= RULES.ROOST_DRIVE_COST_MAX
		and RULES.draft_strength_from_dots(8.0, 0.0, 0.75, 1.0) == 0.0
		and RULES.draft_strength_from_dots(8.0, 0.0, 1.0, 0.81) == 0.0
		and RULES.draft_strength_from_dots(8.0, 0.0, 1.0, 1.0) > 0.0
	)


func _verify_flow_priority() -> bool:
	var compose_air: StringName = RULES.select_flow_technique(false, 1.0, 1.0, 0.0, 0.0, 1.0)
	var compose_save: StringName = RULES.select_flow_technique(true, 1.0, 1.0, 0.7, 0.0, 1.0)
	var brace: StringName = RULES.select_flow_technique(true, 1.0, 1.0, 0.0, 0.0, 0.8)
	var rail: StringName = RULES.select_flow_technique(true, 0.8, -0.7, 0.0, 0.0, 0.0)
	var surge: StringName = RULES.select_flow_technique(true, 0.0, 0.0, 0.0, 0.0, 0.0)
	var affordable: Dictionary = RULES.evaluate_flow_technique(18.0, true, 0.8, -0.7, 0.0, 0.0, 0.0)
	var denied: Dictionary = RULES.evaluate_flow_technique(17.99, true, 0.8, -0.7, 0.0, 0.0, 0.0)
	return (
		compose_air == RULES.FLOW_COMPOSE
		and compose_save == RULES.FLOW_COMPOSE
		and brace == RULES.FLOW_BRACE
		and rail == RULES.FLOW_RAIL
		and surge == RULES.FLOW_SURGE
		and RULES.flow_cost(RULES.FLOW_RAIL) < RULES.flow_cost(RULES.FLOW_SURGE)
		and bool(affordable[&"affordable"])
		and not bool(denied[&"affordable"])
		and is_equal_approx(float(denied[&"flow_remaining"]), 17.99)
	)


func _verify_skill_line_choices() -> bool:
	var bypassed: Dictionary = RULES.evaluate_skill_line_choice(
		false, 0.0, 0.0, 0.0, 0.0, 1.0
	)
	var mastered: Dictionary = RULES.evaluate_skill_line_choice(
		true, 1.0, 1.0, 1.0, 1.0, 0.0
	)
	var missed: Dictionary = RULES.evaluate_skill_line_choice(
		true, 0.0, 0.0, 0.0, 0.0, 1.0
	)
	var rut_correction := RULES.skill_line_commit_intent(&"RUT", 1.0, 0.8, &"NONE")
	var rut_wrong_way := RULES.skill_line_commit_intent(&"RUT", 1.0, -0.8, &"NONE")
	var berm_overshoot_correction := RULES.skill_line_commit_intent(&"BERM", -0.7, -0.5, &"NONE")
	var pump_steering_only := RULES.skill_line_commit_intent(&"PUMP", -1.0, -1.0, &"NONE")
	var pump_technique := RULES.skill_line_commit_intent(&"PUMP", -1.0, -1.0, &"PUMP")
	return (
		StringName(bypassed.get(&"outcome", &"")) == &"BYPASSED"
		and not bool(bypassed.get(&"committed", true))
		and is_equal_approx(float(bypassed.get(&"momentum_multiplier", 0.0)), 1.0)
		and is_equal_approx(float(bypassed.get(&"stability_factor", 0.0)), 1.0)
		and is_zero_approx(float(bypassed.get(&"flow_reward", -1.0)))
		and bool(mastered.get(&"committed", false))
		and StringName(mastered.get(&"outcome", &"")) == &"MASTERED"
		and float(mastered.get(&"momentum_multiplier", 1.0)) > 1.0
		and float(mastered.get(&"flow_reward", 0.0)) > 0.0
		and StringName(missed.get(&"outcome", &"")) == &"MISSED"
		and _in_range(
			float(missed.get(&"momentum_multiplier", 0.0)),
			RULES.SKILL_LINE_MOMENTUM_MIN,
			1.0
		)
		and rut_correction
		and not rut_wrong_way
		and berm_overshoot_correction
		and not pump_steering_only
		and pump_technique
	)


func _verify_skill_line_guidance() -> bool:
	var opening: Dictionary = RULES.skill_line_guidance(0.0, 650.0, 32.0, 10)
	var active: Dictionary = RULES.skill_line_guidance(0.06, 650.0, 32.0, 10)
	var cleared: Dictionary = RULES.skill_line_guidance(0.095, 650.0, 5.0, 10)
	var next_preview: Dictionary = RULES.skill_line_guidance(0.098, 650.0, 32.0, 10)
	var seam_preview: Dictionary = RULES.skill_line_guidance(0.999, 650.0, 40.0, 10)
	var opening_repeat: Dictionary = RULES.skill_line_guidance(0.0, 650.0, 32.0, 10)
	var left: Dictionary = RULES.skill_line_definition(0, 4.5, 1.25)
	var right: Dictionary = RULES.skill_line_definition(1, 4.5, 1.25)
	var center: Dictionary = RULES.skill_line_definition(2, 4.5, 1.25)
	var seam_before_key := RULES.skill_line_zone_key(&"MESA", &"MAIN", int(seam_preview.get(&"zone_index", -1)), &"RUT")
	var seam_after_guidance: Dictionary = RULES.skill_line_guidance(0.001, 650.0, 40.0, 10)
	var seam_after_key := RULES.skill_line_zone_key(&"MESA", &"MAIN", int(seam_after_guidance.get(&"zone_index", -1)), &"RUT")
	return (
		opening == opening_repeat
		and StringName(opening.get(&"phase", &"")) == &"PREVIEW"
		and int(opening.get(&"zone_index", -1)) == 0
		and float(opening.get(&"preview_seconds", 0.0)) >= 1.0
		and StringName(active.get(&"phase", &"")) == &"ACTIVE"
		and bool(active.get(&"active", false))
		and StringName(cleared.get(&"phase", &"INVALID")) == &"NONE"
		and int(cleared.get(&"zone_index", 0)) == -1
		and StringName(next_preview.get(&"phase", &"")) == &"PREVIEW"
		and int(next_preview.get(&"zone_index", -1)) == 1
		and float(next_preview.get(&"preview_seconds", 0.0)) >= 1.0
		and int(seam_preview.get(&"zone_index", -1)) == 0
		and int(seam_preview.get(&"lap_offset", 0)) == 1
		and StringName(left.get(&"direction", &"")) == &"LEFT"
		and StringName(right.get(&"direction", &"")) == &"RIGHT"
		and StringName(center.get(&"direction", &"")) == &"CENTER"
		and left == RULES.skill_line_definition(0, 4.5, 1.25)
		and not seam_before_key.is_empty()
		and seam_before_key == seam_after_key
		and not RULES.suppress_wrapped_preview(1, 0, 1, 1, 0, 6)
		and not RULES.suppress_wrapped_preview(0, 0, 2, 2, 1, 6)
		and not RULES.suppress_wrapped_preview(1, 0, 1, 2, 5, 6)
		and RULES.suppress_wrapped_preview(1, 0, 2, 2, 5, 6)
		and RULES.suppress_wrapped_preview(0, 0, 2, 2, 5, 6)
		and not RULES.suppress_wrapped_preview(0, 1, 2, 2, 5, 6)
	)


func _in_range(value: float, minimum: float, maximum: float) -> bool:
	return is_finite(value) and value >= minimum - 0.0001 and value <= maximum + 0.0001
