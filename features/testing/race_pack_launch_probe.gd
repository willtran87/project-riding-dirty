extends Node
## Deterministic, fixed-step regression for the opponent grid launch. The pack
## runs without a player so launch-line behavior cannot be hidden by contact or
## input timing, then continues long enough to prove later race chaos survives.

const STEP := 1.0 / 60.0
const LAUNCH_SAMPLE_SECONDS := 2.5
const TOTAL_SAMPLE_SECONDS := 15.0


func _ready() -> void:
	var quarry := _run_case(CourseCatalog.QUARRY_ID)
	var pine := _run_case(CourseCatalog.PINE_ID)
	var passed := bool(quarry[&"passed"]) and bool(pine[&"passed"])
	print("PACK LAUNCH REGRESSION: quarry=%s pine=%s passed=%s" % [str(quarry), str(pine), str(passed)])
	if not passed:
		push_error("PACK LAUNCH REGRESSION: straight launch or later chaos contract failed.")
	get_tree().quit(0 if passed else 1)


func _run_case(track_id: StringName) -> Dictionary:
	var pack := RacePack.new()
	pack.name = "LaunchProbePack_%s" % String(track_id)
	add_child(pack)
	pack.configure(track_id)
	pack.set_physics_process(false)

	var initial_lanes: Array[float] = []
	for state: Dictionary in pack.get("_riders") as Array:
		initial_lanes.append(float(state[&"lane"]))

	pack.start_race()
	var independent_maximum_displacement := 0.0
	var independent_maximum_lateral_speed := 0.0
	var elapsed := 0.0
	for _frame: int in ceili(TOTAL_SAMPLE_SECONDS / STEP):
		pack.call(&"_physics_process", STEP)
		elapsed += STEP
		if elapsed <= LAUNCH_SAMPLE_SECONDS + 0.0001:
			var states: Array = pack.get("_riders") as Array
			for index: int in states.size():
				var state: Dictionary = states[index]
				independent_maximum_displacement = maxf(
					independent_maximum_displacement,
					absf(float(state[&"lane"]) - initial_lanes[index])
				)
				independent_maximum_lateral_speed = maxf(
					independent_maximum_lateral_speed,
					absf(float(state[&"lane_velocity"]))
				)

	var launch := pack.get_launch_snapshot()
	var chaos := pack.get_chaos_snapshot()
	var surface_arc := _run_surface_arc_case(pack)
	var lock_seconds := float(launch[&"lock_seconds"])
	var blend_seconds := float(launch[&"blend_seconds"])
	var first_motion := float(launch[&"first_lateral_motion_time"])
	var first_tactic := float(launch[&"first_tactical_time"])
	var straight_launch := (
		independent_maximum_displacement <= 0.001
		and independent_maximum_lateral_speed <= 0.001
		and float(launch[&"max_lane_displacement"]) <= 0.001
		and float(launch[&"max_lateral_speed"]) <= 0.001
		and first_tactic >= lock_seconds
		and first_motion >= lock_seconds
		and first_motion <= lock_seconds + blend_seconds + 0.1
		and float(launch[&"minimum_npc_clearance"]) >= 2.1
	)
	var continuous_blend := (
		is_equal_approx(float(launch[&"tactics_blend"]), 1.0)
		and float(launch[&"max_blend_lateral_acceleration"]) <= RacePack.LANE_ACCELERATION + 0.01
		and float(launch[&"max_heading_error_degrees"]) <= 4.0
		and float(launch[&"max_heading_step_degrees"]) <= 1.0
	)
	var later_chaos := (
		int(chaos[&"lane_changes"]) >= 20
		and int(chaos[&"field_overtakes"]) >= 5
		and int(chaos[&"field_contacts"]) >= 1
		and float(chaos[&"peak_lane_span"]) >= 7.0
		and float(chaos[&"maximum_pair_separation_step"]) <= RacePack.NPC_MAX_SEPARATION_STEP + 0.001
	)
	var support_query_budget := (
		int(chaos.get(&"surface_queries_peak", 999)) <= RacePack.RIDER_COUNT
		and int(chaos.get(&"surface_queries_this_tick", 999)) <= RacePack.RIDER_COUNT
	)
	var result := {
		&"track": track_id,
		&"lock_displacement": independent_maximum_displacement,
		&"lock_lateral_speed": independent_maximum_lateral_speed,
		&"first_tactic": first_tactic,
		&"first_motion": first_motion,
		&"blend_acceleration": float(launch[&"max_blend_lateral_acceleration"]),
		&"heading_error_degrees": float(launch[&"max_heading_error_degrees"]),
		&"heading_step_degrees": float(launch[&"max_heading_step_degrees"]),
		&"minimum_clearance": float(launch[&"minimum_npc_clearance"]),
		&"later_lane_changes": int(chaos[&"lane_changes"]),
		&"later_overtakes": int(chaos[&"field_overtakes"]),
		&"later_contacts": int(chaos[&"field_contacts"]),
		&"maximum_separation_step": float(chaos[&"maximum_pair_separation_step"]),
		&"surface_queries_peak": int(chaos.get(&"surface_queries_peak", -1)),
		&"surface_arc": surface_arc,
		&"straight": straight_launch,
		&"continuous": continuous_blend,
		&"chaos": later_chaos,
		&"support_query_budget": support_query_budget,
		&"passed": straight_launch and continuous_blend and later_chaos and support_query_budget and bool(surface_arc[&"passed"]),
	}
	remove_child(pack)
	pack.free()
	return result


func _run_surface_arc_case(pack: RacePack) -> Dictionary:
	var state := {
		&"surface_y": 0.0,
		&"surface_vertical_speed": 0.0,
		&"surface_supported": true,
		&"surface_initialized": false,
	}
	pack.call(&"_follow_ride_surface", state, 0.0, 0.0)
	var rising_immediate := true
	for support_y: float in [0.1, 0.2, 0.3, 0.4]:
		pack.call(&"_follow_ride_surface", state, support_y, STEP)
		rising_immediate = rising_immediate and is_equal_approx(float(state[&"surface_y"]), support_y)
	var lip_y := float(state[&"surface_y"])
	pack.call(&"_follow_ride_surface", state, 0.0, STEP)
	var preserved_takeoff := not bool(state[&"surface_supported"]) and float(state[&"surface_y"]) >= lip_y
	var minimum_clearance := float(state[&"surface_y"])
	var maximum_height := float(state[&"surface_y"])
	var maximum_fall_speed := 0.0
	var landed := false
	for _frame: int in 180:
		pack.call(&"_follow_ride_surface", state, 0.0, STEP)
		minimum_clearance = minf(minimum_clearance, float(state[&"surface_y"]))
		maximum_height = maxf(maximum_height, float(state[&"surface_y"]))
		maximum_fall_speed = maxf(maximum_fall_speed, -float(state[&"surface_vertical_speed"]))
		if bool(state[&"surface_supported"]):
			landed = true
			break
	var passed := (
		rising_immediate
		and preserved_takeoff
		and landed
		and minimum_clearance >= -0.001
		and maximum_height > lip_y + 0.2
		and maximum_fall_speed <= RacePack.SURFACE_MAX_FALL_SPEED + 0.001
	)
	return {
		&"rising_immediate": rising_immediate,
		&"preserved_takeoff": preserved_takeoff,
		&"landed": landed,
		&"minimum_clearance": minimum_clearance,
		&"maximum_height": maximum_height,
		&"maximum_fall_speed": maximum_fall_speed,
		&"passed": passed,
	}
