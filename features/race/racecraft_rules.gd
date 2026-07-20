extends RefCounted
class_name RacecraftRules
## Pure, deterministic racecraft calculations shared by the player bike and AI pack.
##
## All inputs are scalar snapshots from a single physics tick. The rules never read
## input, physics, random state, or the SceneTree, so replay and fixed-step callers
## receive identical results for identical inputs.

const FLOW_NONE: StringName = &"NONE"
const FLOW_SURGE: StringName = &"SURGE"
const FLOW_RAIL: StringName = &"RAIL"
const FLOW_COMPOSE: StringName = &"COMPOSE"
const FLOW_BRACE: StringName = &"BRACE"

const FLOW_SURGE_COST := 35.0
const FLOW_RAIL_COST := 18.0
const FLOW_COMPOSE_COST := 24.0
const FLOW_BRACE_COST := 20.0

const SCRUB_MOMENTUM_MIN := 0.92
const SCRUB_MOMENTUM_MAX := 1.0
const PUMP_MOMENTUM_MIN := 0.96
const PUMP_MOMENTUM_MAX := 1.06
const LANDING_MOMENTUM_MIN := 0.72
const LANDING_MOMENTUM_MAX := 1.0
const REAR_SLIDE_EXIT_MIN := 0.80
const REAR_SLIDE_EXIT_MAX := 1.06
const SKILL_LINE_MOMENTUM_MIN := 0.82
const SKILL_LINE_MOMENTUM_MAX := 1.06
const SKILL_LINE_ACTIVE_START := 0.55
const SKILL_LINE_ACTIVE_END := 0.93
const SKILL_LINE_PREVIEW_SECONDS := 1.25
const SKILL_LINE_MIN_PREVIEW_METERS := 24.0
const RUT_MOMENTUM_MIN := 0.80
const RUT_MOMENTUM_MAX := 1.04

const DRAFT_BEHIND_DOT_MIN := 0.76
const DRAFT_ALIGNMENT_DOT_MIN := 0.82
const DRAFT_MIN_DISTANCE := 2.5
const DRAFT_MAX_DISTANCE := 22.0
const DRAFT_MAX_LATERAL_OFFSET := 4.5
const DRAFT_STRENGTH_MAX := 1.0

const ROOST_MAX_DISTANCE := 15.0
const ROOST_ALIGNMENT_DOT_MIN := 0.55
const ROOST_PRESSURE_MAX := 1.0
const ROOST_DRIVE_COST_MAX := 0.06

const FLOW_COSTS: Dictionary = {
	FLOW_SURGE: FLOW_SURGE_COST,
	FLOW_RAIL: FLOW_RAIL_COST,
	FLOW_COMPOSE: FLOW_COMPOSE_COST,
	FLOW_BRACE: FLOW_BRACE_COST,
}

# grip is the deliberate-slide lateral grip floor; exit_cap is the strict best
# catch multiplier. Forgiveness shapes how much countersteer/throttle timing is
# converted into exit drive. Values preserve the existing uppercase surfaces.
const SLIDE_PROFILES: Dictionary = {
	&"PACKED": {&"grip": 0.72, &"rotation": 0.78, &"exit_cap": 1.030, &"forgiveness": 0.82},
	&"DIRT": {&"grip": 0.68, &"rotation": 0.88, &"exit_cap": 1.045, &"forgiveness": 0.86},
	&"LOAM": {&"grip": 0.62, &"rotation": 0.96, &"exit_cap": 1.060, &"forgiveness": 0.95},
	&"LOOSE_DIRT": {&"grip": 0.57, &"rotation": 1.04, &"exit_cap": 1.025, &"forgiveness": 0.76},
	&"GRAVEL": {&"grip": 0.52, &"rotation": 1.12, &"exit_cap": 0.990, &"forgiveness": 0.58},
	&"MUD": {&"grip": 0.44, &"rotation": 0.94, &"exit_cap": 0.920, &"forgiveness": 0.68},
	&"ROCK": {&"grip": 0.78, &"rotation": 0.66, &"exit_cap": 1.010, &"forgiveness": 0.62},
}

const ROOST_SURFACE_FACTORS: Dictionary = {
	&"PACKED": 0.52,
	&"DIRT": 0.78,
	&"LOAM": 0.92,
	&"LOOSE_DIRT": 0.90,
	&"GRAVEL": 0.66,
	&"MUD": 1.0,
	&"ROCK": 0.12,
}


static func select_flow_technique(
	grounded: bool,
	brake_strength: float,
	steer_strength: float,
	landing_risk: float,
	wobble_strength: float,
	pack_pressure: float
) -> StringName:
	## Selection priority is safety first: Compose, Brace, Rail, then Surge.
	## An airborne press always composes because Surge cannot apply in the air.
	var risk := maxf(clampf(landing_risk, 0.0, 1.0), clampf(wobble_strength, 0.0, 1.0))
	if not grounded or risk >= 0.30:
		return FLOW_COMPOSE
	if clampf(pack_pressure, 0.0, 1.0) >= 0.45:
		return FLOW_BRACE
	if clampf(brake_strength, 0.0, 1.0) >= 0.18 and absf(clampf(steer_strength, -1.0, 1.0)) >= 0.22:
		return FLOW_RAIL
	return FLOW_SURGE


static func flow_cost(technique: StringName) -> float:
	return float(FLOW_COSTS.get(technique, 0.0))


static func evaluate_flow_technique(
	available_flow: float,
	grounded: bool,
	brake_strength: float,
	steer_strength: float,
	landing_risk: float,
	wobble_strength: float,
	pack_pressure: float
) -> Dictionary:
	var technique := select_flow_technique(
		grounded,
		brake_strength,
		steer_strength,
		landing_risk,
		wobble_strength,
		pack_pressure
	)
	var cost := flow_cost(technique)
	var safe_available := maxf(available_flow, 0.0)
	return {
		&"technique": technique,
		&"cost": cost,
		&"affordable": safe_available + 0.0001 >= cost,
		&"flow_remaining": maxf(safe_available - cost, 0.0) if safe_available + 0.0001 >= cost else safe_available,
	}


static func scrub_strength_from_lean(lean_input: float) -> float:
	## InputRouter defines forward lean as negative. Positive lean never scrubs.
	return clampf(-lean_input, 0.0, 1.0)


static func scrub_momentum_multiplier(
	lean_input: float,
	scrub_seconds: float,
	takeoff_alignment: float
) -> float:
	var lean_strength := scrub_strength_from_lean(lean_input)
	if lean_strength < 0.50 or scrub_seconds < 0.12:
		return 1.0
	var lean_quality := smoothstep(0.50, 0.92, lean_strength)
	var hold_quality := smoothstep(0.12, 0.38, clampf(scrub_seconds, 0.0, 1.0))
	var alignment_quality := smoothstep(0.45, 0.96, clampf(takeoff_alignment, 0.0, 1.0))
	var execution := lean_quality * 0.38 + hold_quality * 0.24 + alignment_quality * 0.38
	return clampf(lerpf(SCRUB_MOMENTUM_MIN, SCRUB_MOMENTUM_MAX, execution), SCRUB_MOMENTUM_MIN, SCRUB_MOMENTUM_MAX)


static func pump_momentum_multiplier(
	suspension_load: float,
	release_timing: float,
	downhill_alignment: float
) -> float:
	var load := clampf(suspension_load, 0.0, 1.0)
	var timing := clampf(release_timing, 0.0, 1.0)
	var downhill := clampf(downhill_alignment, 0.0, 1.0)
	if load <= 0.0:
		return 1.0
	# Pumping can only add drive when the suspension actually has stored load.
	# Mistimed release dissipates momentum; a well-timed downhill release converts
	# at most six percent per evaluated feature.
	var captured_energy := load * timing * lerpf(0.35, 1.0, downhill)
	var mistiming_loss := load * (1.0 - timing) * 0.04
	return clampf(1.0 + captured_energy * 0.06 - mistiming_loss, PUMP_MOMENTUM_MIN, PUMP_MOMENTUM_MAX)


static func landing_momentum_multiplier(
	surface_alignment_dot: float,
	travel_alignment_dot: float,
	impact_intensity: float,
	compose_strength: float = 0.0
) -> float:
	var surface_quality := smoothstep(0.30, 0.96, clampf(surface_alignment_dot, -1.0, 1.0))
	var travel_quality := smoothstep(0.25, 0.98, clampf(travel_alignment_dot, -1.0, 1.0))
	var impact := clampf(impact_intensity, 0.0, 1.0)
	var compose := clampf(compose_strength, 0.0, 1.0)
	var alignment_quality := surface_quality * 0.58 + travel_quality * 0.42
	var impact_retention := 1.0 - impact * lerpf(0.24, 0.10, compose)
	var retention := lerpf(LANDING_MOMENTUM_MIN, LANDING_MOMENTUM_MAX, alignment_quality) * impact_retention
	return clampf(retention, LANDING_MOMENTUM_MIN, LANDING_MOMENTUM_MAX)


static func rear_slide_factors(
	surface: StringName,
	slide_input: float,
	countersteer_quality: float,
	throttle_catch_quality: float
) -> Dictionary:
	var canonical := _canonical_surface(surface)
	var profile: Dictionary = SLIDE_PROFILES.get(canonical, SLIDE_PROFILES[&"PACKED"])
	var slide := clampf(slide_input, 0.0, 1.0)
	var countersteer := clampf(countersteer_quality, 0.0, 1.0)
	var throttle_catch := clampf(throttle_catch_quality, 0.0, 1.0)
	var forgiveness := float(profile.get(&"forgiveness", 0.8))
	var catch_quality := (countersteer * 0.58 + throttle_catch * 0.42) * forgiveness
	var base_grip := float(profile.get(&"grip", 0.7))
	var exit_cap := float(profile.get(&"exit_cap", 1.0))
	var grip_factor := lerpf(1.0, base_grip, slide)
	var uncaught_loss := slide * (1.0 - catch_quality) * 0.16
	var caught_drive := (exit_cap - 1.0) * slide * catch_quality
	var exit_factor := clampf(1.0 - uncaught_loss + caught_drive, REAR_SLIDE_EXIT_MIN, REAR_SLIDE_EXIT_MAX)
	return {
		&"surface": canonical,
		&"grip_factor": clampf(grip_factor, 0.40, 1.0),
		&"rotation_factor": clampf(float(profile.get(&"rotation", 1.0)) * slide, 0.0, 1.2),
		&"exit_factor": exit_factor,
		&"catch_quality": clampf(catch_quality, 0.0, 1.0),
		&"forgiveness": forgiveness,
	}


static func draft_strength_from_dots(
	distance_m: float,
	lateral_offset_m: float,
	behind_dot: float,
	alignment_dot: float
) -> float:
	## behind_dot is follower-forward dot direction-to-leader. Both dots are hard
	## gates; proximity alone can never create a draft from beside or ahead.
	if distance_m < DRAFT_MIN_DISTANCE or distance_m > DRAFT_MAX_DISTANCE:
		return 0.0
	if absf(lateral_offset_m) > DRAFT_MAX_LATERAL_OFFSET:
		return 0.0
	if behind_dot < DRAFT_BEHIND_DOT_MIN or alignment_dot < DRAFT_ALIGNMENT_DOT_MIN:
		return 0.0
	var near_fade := smoothstep(DRAFT_MIN_DISTANCE, 5.0, distance_m)
	var far_fade := 1.0 - smoothstep(7.0, DRAFT_MAX_DISTANCE, distance_m)
	var lateral_quality := 1.0 - absf(lateral_offset_m) / DRAFT_MAX_LATERAL_OFFSET
	var behind_quality := inverse_lerp(DRAFT_BEHIND_DOT_MIN, 1.0, clampf(behind_dot, DRAFT_BEHIND_DOT_MIN, 1.0))
	var alignment_quality := inverse_lerp(DRAFT_ALIGNMENT_DOT_MIN, 1.0, clampf(alignment_dot, DRAFT_ALIGNMENT_DOT_MIN, 1.0))
	return clampf(
		near_fade * far_fade * lateral_quality * behind_quality * alignment_quality,
		0.0,
		DRAFT_STRENGTH_MAX
	)


static func draft_strength(
	follower_position: Vector3,
	follower_forward: Vector3,
	leader_position: Vector3,
	leader_forward: Vector3
) -> float:
	var safe_follower_forward := follower_forward.normalized()
	var safe_leader_forward := leader_forward.normalized()
	var separation := leader_position - follower_position
	var distance := separation.length()
	if distance <= 0.0001 or safe_follower_forward.length_squared() <= 0.5 or safe_leader_forward.length_squared() <= 0.5:
		return 0.0
	var direction_to_leader := separation / distance
	var longitudinal_distance := separation.dot(safe_follower_forward)
	var lateral_offset := (separation - safe_follower_forward * longitudinal_distance).length()
	return draft_strength_from_dots(
		distance,
		lateral_offset,
		safe_follower_forward.dot(direction_to_leader),
		safe_follower_forward.dot(safe_leader_forward)
	)


static func roost_pressure_factor(
	surface: StringName,
	rear_slip: float,
	throttle_strength: float,
	target_distance_m: float,
	target_alignment_dot: float
) -> float:
	if target_distance_m < 1.0 or target_distance_m > ROOST_MAX_DISTANCE:
		return 0.0
	if target_alignment_dot < ROOST_ALIGNMENT_DOT_MIN:
		return 0.0
	var canonical := _canonical_surface(surface)
	var surface_factor := float(ROOST_SURFACE_FACTORS.get(canonical, ROOST_SURFACE_FACTORS[&"PACKED"]))
	var slip_factor := smoothstep(0.16, 0.88, clampf(rear_slip, 0.0, 1.0))
	var throttle_factor := smoothstep(0.30, 0.95, clampf(throttle_strength, 0.0, 1.0))
	var distance_factor := 1.0 - smoothstep(3.0, ROOST_MAX_DISTANCE, target_distance_m)
	var alignment_factor := inverse_lerp(
		ROOST_ALIGNMENT_DOT_MIN,
		1.0,
		clampf(target_alignment_dot, ROOST_ALIGNMENT_DOT_MIN, 1.0)
	)
	return clampf(
		surface_factor * slip_factor * throttle_factor * distance_factor * alignment_factor,
		0.0,
		ROOST_PRESSURE_MAX
	)


static func roost_drive_cost_fraction(pressure: float, deliberate_input: float = 1.0) -> float:
	return clampf(
		clampf(pressure, 0.0, ROOST_PRESSURE_MAX) * clampf(deliberate_input, 0.0, 1.0) * ROOST_DRIVE_COST_MAX,
		0.0,
		ROOST_DRIVE_COST_MAX
	)


static func evaluate_roost(
	surface: StringName,
	rear_slip: float,
	throttle_strength: float,
	target_distance_m: float,
	target_alignment_dot: float,
	deliberate_input: float = 1.0
) -> Dictionary:
	var pressure := roost_pressure_factor(
		surface,
		rear_slip,
		throttle_strength,
		target_distance_m,
		target_alignment_dot
	)
	var cost := roost_drive_cost_fraction(pressure, deliberate_input)
	return {
		&"surface": _canonical_surface(surface),
		&"pressure": pressure,
		&"drive_cost_fraction": cost,
		&"drive_multiplier": 1.0 - cost,
	}


static func skill_line_guidance(
	lap_progress: float,
	route_length: float,
	speed_mps: float,
	zone_count: int
) -> Dictionary:
	## Returns the next readable decision window without consulting scene state.
	## A line is previewed early enough for a deliberate lane change, becomes live
	## for a bounded portion of its zone, then clears until the next cue is useful.
	var safe_length := maxf(route_length, 0.0)
	var safe_count := maxi(zone_count, 0)
	if safe_length <= 0.001 or safe_count <= 0:
		return {
			&"phase": &"NONE",
			&"zone_index": -1,
			&"lap_offset": 0,
			&"distance_m": 0.0,
			&"preview_seconds": 0.0,
			&"active": false,
		}
	var bounded_progress := clampf(lap_progress, 0.0, 0.999999)
	var scaled_progress := bounded_progress * float(safe_count)
	var current_zone := clampi(floori(scaled_progress), 0, safe_count - 1)
	var zone_phase := scaled_progress - floorf(scaled_progress)
	var zone_span := safe_length / float(safe_count)
	var safe_speed := maxf(speed_mps, 0.0)
	var preview_distance := maxf(
		SKILL_LINE_MIN_PREVIEW_METERS,
		safe_speed * SKILL_LINE_PREVIEW_SECONDS
	)
	var phase: StringName = &"NONE"
	var target_zone := -1
	var lap_offset := 0
	var distance_m := 0.0
	if zone_phase >= SKILL_LINE_ACTIVE_START and zone_phase <= SKILL_LINE_ACTIVE_END:
		phase = &"ACTIVE"
		target_zone = current_zone
	elif zone_phase < SKILL_LINE_ACTIVE_START:
		phase = &"PREVIEW"
		target_zone = current_zone
		distance_m = (SKILL_LINE_ACTIVE_START - zone_phase) * zone_span
	else:
		var next_distance := (1.0 - zone_phase + SKILL_LINE_ACTIVE_START) * zone_span
		if next_distance <= preview_distance:
			phase = &"PREVIEW"
			target_zone = posmod(current_zone + 1, safe_count)
			lap_offset = 1 if target_zone == 0 else 0
			distance_m = next_distance
	return {
		&"phase": phase,
		&"zone_index": target_zone,
		&"lap_offset": lap_offset,
		&"distance_m": maxf(distance_m, 0.0),
		&"preview_seconds": distance_m / maxf(safe_speed, 1.0) if phase == &"PREVIEW" else 0.0,
		&"active": phase == &"ACTIVE",
		&"zone_phase": zone_phase,
		&"zone_span_m": zone_span,
		&"preview_distance_m": preview_distance,
	}


static func skill_line_definition(
	zone_index: int,
	track_half_width: float,
	rut_offset: float
) -> Dictionary:
	## The line side is zone-authored rather than derived from a live tangent, so
	## the arrow can never reverse after the rider has committed to the choice.
	if zone_index < 0:
		return {&"kind": &"NONE", &"target_lane": 0.0, &"direction": &"CENTER"}
	var safe_half_width := maxf(track_half_width, 1.0)
	var safe_rut_offset := clampf(absf(rut_offset), 0.45, safe_half_width * 0.78)
	var side := -1.0 if posmod(zone_index, 2) == 0 else 1.0
	var kind: StringName
	var target_lane: float
	match posmod(zone_index, 3):
		0:
			kind = &"RUT"
			target_lane = safe_rut_offset * side
		1:
			kind = &"BERM"
			target_lane = safe_half_width * 0.72 * side
		_:
			kind = &"PUMP"
			target_lane = 0.0
	var direction: StringName = &"CENTER"
	if target_lane < -0.1:
		direction = &"LEFT"
	elif target_lane > 0.1:
		direction = &"RIGHT"
	return {
		&"kind": kind,
		&"target_lane": target_lane,
		&"direction": direction,
	}


static func skill_line_zone_key(
	track_id: StringName,
	route_line_id: StringName,
	zone_index: int,
	line_kind: StringName
) -> StringName:
	## The empty decision window resets bike state between occurrences, so a lap
	## number is unnecessary. Omitting it also makes the key immune to the two
	## equivalent projections at a closed spline's start/finish seam.
	if zone_index < 0 or line_kind == &"NONE":
		return &""
	return StringName("%s_%s_Z%02d_%s" % [
		String(track_id), String(route_line_id), zone_index, String(line_kind)
	])


static func suppress_wrapped_preview(
	lap_offset: int,
	zone_index: int,
	current_lap: int,
	total_laps: int,
	completed_checkpoint_count: int,
	checkpoint_count: int
) -> bool:
	## Grid staging sits just before the geometric seam and legitimately previews
	## zone zero of lap one. At the finish, projection may wrap to the start alias
	## one physics tick before the checkpoint Area reports the lap, changing the
	## guidance from lap_offset=1 to zone zero with lap_offset=0. Treat both forms
	## as beyond-finish only after the final checkpoint has armed the finish.
	if current_lap < maxi(total_laps, 1):
		return false
	var safe_checkpoint_count := maxi(checkpoint_count, 0)
	var finish_armed := (
		completed_checkpoint_count > 0
		if safe_checkpoint_count <= 1
		else completed_checkpoint_count >= safe_checkpoint_count - 1
	)
	return finish_armed and (lap_offset > 0 or zone_index == 0)


static func skill_line_commit_intent(
	line_kind: StringName,
	target_delta: float,
	steer_input: float,
	active_technique: StringName
) -> bool:
	## Lateral lines commit only while correcting toward the live target. Pump
	## lines are exclusive to the contextual Pump technique; ordinary course
	## steering can never opt the rider into their risk/reward grade.
	if line_kind == &"PUMP":
		return active_technique == &"PUMP"
	if line_kind not in [&"RUT", &"BERM"]:
		return false
	var safe_delta := target_delta
	var safe_steer := clampf(steer_input, -1.0, 1.0)
	return (
		absf(safe_delta) > 0.15
		and absf(safe_steer) >= 0.16
		and signf(safe_steer) == signf(safe_delta)
	)


static func evaluate_skill_line_choice(
	committed: bool,
	rider_skill: float,
	entry_alignment: float,
	timing_quality: float,
	commitment: float,
	difficulty: float
) -> Dictionary:
	## Fast lines are opt-in. Riding the normal course is always neutral; only a
	## deliberate attempt enters the existing bounded risk/reward calculation.
	if not committed:
		return {
			&"outcome": &"BYPASSED",
			&"committed": false,
			&"execution": 0.0,
			&"required": 0.0,
			&"margin": 0.0,
			&"momentum_multiplier": 1.0,
			&"stability_factor": 1.0,
			&"flow_reward": 0.0,
		}
	var result := evaluate_skill_line(
		rider_skill,
		entry_alignment,
		timing_quality,
		commitment,
		difficulty
	)
	result[&"committed"] = true
	return result


static func evaluate_skill_line(
	rider_skill: float,
	entry_alignment: float,
	timing_quality: float,
	commitment: float,
	difficulty: float
) -> Dictionary:
	var skill := clampf(rider_skill, 0.0, 1.0)
	var alignment := clampf(entry_alignment, 0.0, 1.0)
	var timing := clampf(timing_quality, 0.0, 1.0)
	var commit := clampf(commitment, 0.0, 1.0)
	var challenge := clampf(difficulty, 0.0, 1.0)
	var execution := skill * 0.28 + alignment * 0.32 + timing * 0.25 + commit * 0.15
	var required := 0.28 + challenge * 0.50
	var margin := execution - required
	var outcome: StringName
	var momentum: float
	var stability: float
	var flow_reward: float
	if margin >= 0.18:
		outcome = &"MASTERED"
		momentum = 1.03 + smoothstep(0.18, 0.50, margin) * 0.03
		stability = 1.0
		flow_reward = 5.0 + smoothstep(0.18, 0.50, margin) * 3.0
	elif margin >= 0.0:
		outcome = &"CLEAN"
		momentum = 1.0 + smoothstep(0.0, 0.18, margin) * 0.025
		stability = lerpf(0.88, 1.0, smoothstep(0.0, 0.18, margin))
		flow_reward = 2.0 + smoothstep(0.0, 0.18, margin) * 2.0
	elif margin >= -0.20:
		outcome = &"SCRAMBLED"
		momentum = lerpf(0.91, 0.98, smoothstep(-0.20, 0.0, margin))
		stability = lerpf(0.58, 0.82, smoothstep(-0.20, 0.0, margin))
		flow_reward = 0.0
	else:
		outcome = &"MISSED"
		momentum = lerpf(0.82, 0.90, smoothstep(-0.78, -0.20, margin))
		stability = lerpf(0.35, 0.55, smoothstep(-0.78, -0.20, margin))
		flow_reward = 0.0
	return {
		&"outcome": outcome,
		&"execution": execution,
		&"required": required,
		&"margin": margin,
		&"momentum_multiplier": clampf(momentum, SKILL_LINE_MOMENTUM_MIN, SKILL_LINE_MOMENTUM_MAX),
		&"stability_factor": clampf(stability, 0.0, 1.0),
		&"flow_reward": clampf(flow_reward, 0.0, 8.0),
	}


static func evaluate_rut(
	surface: StringName,
	entry_alignment_dot: float,
	entry_speed_ratio: float,
	steer_aggression: float,
	rut_depth: float
) -> Dictionary:
	var canonical := _canonical_surface(surface)
	var profile: Dictionary = SLIDE_PROFILES.get(canonical, SLIDE_PROFILES[&"PACKED"])
	var alignment := smoothstep(0.45, 0.98, clampf(entry_alignment_dot, -1.0, 1.0))
	var speed_ratio := clampf(entry_speed_ratio, 0.0, 2.0)
	var speed_quality := clampf(1.0 - absf(speed_ratio - 0.90) / 0.90, 0.0, 1.0)
	var steering_quality := 1.0 - clampf(steer_aggression, 0.0, 1.0)
	var depth := clampf(rut_depth, 0.0, 1.0)
	var forgiveness := float(profile.get(&"forgiveness", 0.8))
	var execution := alignment * 0.57 + speed_quality * 0.25 + steering_quality * 0.18
	var required := 0.48 + depth * 0.17 + (1.0 - forgiveness) * 0.14
	var margin := execution - required
	var outcome: StringName
	var momentum: float
	var stability: float
	var steering_assist: float
	if margin >= 0.16:
		outcome = &"RAILED"
		momentum = 1.015 + smoothstep(0.16, 0.40, margin) * 0.025
		stability = 0.96
		steering_assist = lerpf(0.34, 0.58, depth)
	elif margin >= -0.08:
		outcome = &"CAUGHT"
		momentum = lerpf(0.94, 1.0, smoothstep(-0.08, 0.16, margin))
		stability = 0.76
		steering_assist = lerpf(0.18, 0.34, depth)
	else:
		outcome = &"CLIMBED_OUT"
		momentum = lerpf(0.80, 0.92, smoothstep(-0.70, -0.08, margin))
		stability = lerpf(0.28, 0.55, smoothstep(-0.70, -0.08, margin))
		steering_assist = 0.0
	return {
		&"surface": canonical,
		&"outcome": outcome,
		&"execution": execution,
		&"required": required,
		&"margin": margin,
		&"momentum_multiplier": clampf(momentum, RUT_MOMENTUM_MIN, RUT_MOMENTUM_MAX),
		&"stability_factor": clampf(stability, 0.0, 1.0),
		&"steering_assist": clampf(steering_assist, 0.0, 0.58),
		&"capture_factor": clampf(alignment * depth * forgiveness, 0.0, 1.0),
	}


static func _canonical_surface(surface: StringName) -> StringName:
	var canonical := StringName(String(surface).strip_edges().to_upper())
	if SLIDE_PROFILES.has(canonical):
		return canonical
	return &"PACKED"
