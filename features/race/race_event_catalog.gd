extends RefCounted
class_name RaceEventCatalog
## Data-driven event, format and weekend definitions used by garage and race systems.

const CHALLENGE_SCHEDULE_SCRIPT := preload("res://features/competitive/challenge_schedule.gd")
const ACADEMY_CATALOG_SCRIPT := preload("res://features/career/academy_lesson_catalog.gd")

static var _academy_lesson_override: StringName = &""
static var _player_difficulty_mode: StringName = &"STANDARD"

const PLAYER_DIFFICULTY_MODES: Array[StringName] = [&"RELAXED", &"STANDARD", &"EXPERT"]
const PLAYER_DIFFICULTY_OFFSETS: Dictionary = {
	&"RELAXED": -1,
	&"STANDARD": 0,
	&"EXPERT": 1,
}

const EVENT_ORDER: Array[StringName] = [
	&"CIRCUIT", &"PINE_ENDURO", &"MESA_PRACTICE", &"MESA_QUALIFYING",
	&"MESA_HEAT", &"MESA_LCQ", &"MESA_MX", &"MESA_ELIMINATION", &"MESA_RIVAL", &"MESA_ENDURANCE",
	&"QUARRY_HILLCLIMB", &"PINE_WET", &"MESA_RHYTHM", &"DAILY_CHALLENGE", &"WEEKLY_CHALLENGE",
	&"ACADEMY", &"FREESTYLE", &"DISCOVERY",
]

const RACE_EVENTS: Array[StringName] = [
	&"CIRCUIT", &"PINE_ENDURO", &"MESA_PRACTICE", &"MESA_QUALIFYING",
	&"MESA_HEAT", &"MESA_LCQ", &"MESA_MX", &"MESA_ELIMINATION", &"MESA_RIVAL", &"MESA_ENDURANCE",
	&"QUARRY_HILLCLIMB", &"PINE_WET", &"MESA_RHYTHM", &"DAILY_CHALLENGE", &"WEEKLY_CHALLENGE",
	&"ACADEMY",
]

# V24 measurable event-design contracts. They are projected into session rules
# so RacePack, results, and probes consume one deterministic authority instead
# of every full-field event silently falling back to difficulty two.
const RETENTION_CONTRACTS: Dictionary[StringName, Dictionary] = {
	&"CIRCUIT": {&"difficulty": 1, &"replay_hook": &"GHOST_CHASE", &"tension_strength": 0.78, &"leader_drag_mps": 1.25, &"trailer_boost_mps": 0.78, &"breakaway_distance_m": 48.0, &"close_gap_m": 8.0, &"pace_variance": 0.72, &"final_lap_scale": 0.48, &"jump_commitment": 1.00, &"airtime_opportunities": 7, &"airtime_bonus": true},
	&"PINE_ENDURO": {&"difficulty": 2, &"replay_hook": &"SECTOR_MASTERY", &"tension_strength": 0.58, &"leader_drag_mps": 1.00, &"trailer_boost_mps": 0.72, &"breakaway_distance_m": 62.0, &"close_gap_m": 10.0, &"pace_variance": 0.85, &"final_lap_scale": 0.42, &"jump_commitment": 0.92, &"airtime_opportunities": 15, &"airtime_bonus": true, &"featured_rider_ids": [&"DUST", &"SABLE", &"LARK", &"MICA", &"EMBER"]},
	&"MESA_PRACTICE": {&"difficulty": 0, &"replay_hook": &"LINE_DISCOVERY", &"tension_strength": 0.15, &"leader_drag_mps": 0.35, &"trailer_boost_mps": 0.25, &"breakaway_distance_m": 70.0, &"close_gap_m": 12.0, &"pace_variance": 0.45, &"final_lap_scale": 0.30, &"jump_commitment": 0.90, &"airtime_opportunities": 10, &"airtime_bonus": false, &"featured_rider_ids": [&"LARK", &"DUST", &"MICA"]},
	&"MESA_QUALIFYING": {&"difficulty": 1, &"replay_hook": &"GHOST_DELTA", &"tension_strength": 0.0, &"leader_drag_mps": 0.0, &"trailer_boost_mps": 0.0, &"breakaway_distance_m": 0.0, &"close_gap_m": 0.0, &"pace_variance": 0.0, &"final_lap_scale": 0.0, &"jump_commitment": 1.00, &"airtime_opportunities": 10, &"airtime_bonus": false},
	&"MESA_HEAT": {&"difficulty": 2, &"replay_hook": &"TRANSFER_CHASE", &"tension_strength": 0.95, &"leader_drag_mps": 1.25, &"trailer_boost_mps": 1.00, &"breakaway_distance_m": 44.0, &"close_gap_m": 8.0, &"pace_variance": 0.78, &"final_lap_scale": 0.50, &"jump_commitment": 1.00, &"airtime_opportunities": 15, &"airtime_bonus": true},
	&"MESA_LCQ": {&"difficulty": 2, &"replay_hook": &"TRANSFER_SURVIVAL", &"tension_strength": 1.08, &"leader_drag_mps": 1.30, &"trailer_boost_mps": 1.10, &"breakaway_distance_m": 38.0, &"close_gap_m": 7.0, &"pace_variance": 0.82, &"final_lap_scale": 0.52, &"jump_commitment": 1.03, &"airtime_opportunities": 10, &"airtime_bonus": true, &"featured_rider_ids": [&"BRICK", &"TANK", &"EMBER", &"AXLE", &"JETT"]},
	&"MESA_MX": {&"difficulty": 3, &"replay_hook": &"CHAMPIONSHIP_POINTS", &"tension_strength": 0.95, &"leader_drag_mps": 1.15, &"trailer_boost_mps": 1.18, &"breakaway_distance_m": 48.0, &"close_gap_m": 8.0, &"pace_variance": 0.88, &"final_lap_scale": 0.44, &"jump_commitment": 1.06, &"airtime_opportunities": 15, &"airtime_bonus": true},
	&"MESA_ELIMINATION": {&"difficulty": 3, &"replay_hook": &"SURVIVAL_STREAK", &"tension_strength": 1.12, &"leader_drag_mps": 1.25, &"trailer_boost_mps": 1.25, &"breakaway_distance_m": 36.0, &"close_gap_m": 6.0, &"pace_variance": 0.92, &"final_lap_scale": 0.52, &"jump_commitment": 1.06, &"airtime_opportunities": 20, &"airtime_bonus": true, &"featured_rider_ids": [&"TANK", &"BRICK", &"JETT", &"ROOK", &"EMBER", &"AXLE", &"NOVA"]},
	&"MESA_RIVAL": {&"difficulty": 3, &"replay_hook": &"RIVAL_REMATCH", &"tension_strength": 0.92, &"leader_drag_mps": 1.00, &"trailer_boost_mps": 1.15, &"breakaway_distance_m": 34.0, &"close_gap_m": 6.0, &"pace_variance": 0.50, &"final_lap_scale": 0.45, &"jump_commitment": 1.05, &"airtime_opportunities": 10, &"airtime_bonus": false, &"featured_rider_ids": [&"ROOK"]},
	&"MESA_ENDURANCE": {&"difficulty": 4, &"replay_hook": &"CONSISTENCY_STREAK", &"tension_strength": 0.62, &"leader_drag_mps": 0.82, &"trailer_boost_mps": 1.00, &"breakaway_distance_m": 68.0, &"close_gap_m": 12.0, &"pace_variance": 1.00, &"final_lap_scale": 0.32, &"jump_commitment": 0.96, &"airtime_opportunities": 30, &"airtime_bonus": true, &"featured_rider_ids": [&"DUST", &"SABLE", &"ROOK", &"NOVA", &"MICA"]},
	&"QUARRY_HILLCLIMB": {&"difficulty": 3, &"replay_hook": &"CLIMB_GHOST", &"tension_strength": 0.0, &"leader_drag_mps": 0.0, &"trailer_boost_mps": 0.0, &"breakaway_distance_m": 0.0, &"close_gap_m": 0.0, &"pace_variance": 0.0, &"final_lap_scale": 0.0, &"jump_commitment": 1.00, &"airtime_opportunities": 7, &"airtime_bonus": true},
	&"PINE_WET": {&"difficulty": 4, &"replay_hook": &"WET_SECTOR_GHOST", &"tension_strength": 0.70, &"leader_drag_mps": 0.90, &"trailer_boost_mps": 1.05, &"breakaway_distance_m": 62.0, &"close_gap_m": 10.0, &"pace_variance": 1.00, &"final_lap_scale": 0.35, &"jump_commitment": 0.88, &"airtime_opportunities": 15, &"airtime_bonus": true, &"featured_rider_ids": [&"DUST", &"SABLE", &"LARK", &"MICA", &"ROOK"]},
	&"MESA_RHYTHM": {&"difficulty": 3, &"replay_hook": &"RHYTHM_COMBOS", &"tension_strength": 0.88, &"leader_drag_mps": 1.05, &"trailer_boost_mps": 1.10, &"breakaway_distance_m": 36.0, &"close_gap_m": 7.0, &"pace_variance": 0.72, &"final_lap_scale": 0.48, &"jump_commitment": 1.15, &"airtime_opportunities": 5, &"airtime_bonus": true, &"featured_rider_ids": [&"BRICK", &"EMBER", &"AXLE", &"JETT", &"ROOK"]},
	&"DAILY_CHALLENGE": {&"difficulty": 2, &"replay_hook": &"ROTATING_SEED", &"tension_strength": 0.85, &"leader_drag_mps": 1.10, &"trailer_boost_mps": 1.05, &"breakaway_distance_m": 48.0, &"close_gap_m": 8.0, &"pace_variance": 0.82, &"final_lap_scale": 0.45, &"jump_commitment": 1.00, &"airtime_opportunities": 0, &"airtime_bonus": false},
	&"WEEKLY_CHALLENGE": {&"difficulty": 3, &"replay_hook": &"WEEKLY_RANK", &"tension_strength": 0.95, &"leader_drag_mps": 1.10, &"trailer_boost_mps": 1.15, &"breakaway_distance_m": 46.0, &"close_gap_m": 8.0, &"pace_variance": 0.88, &"final_lap_scale": 0.42, &"jump_commitment": 1.03, &"airtime_opportunities": 0, &"airtime_bonus": false},
	&"ACADEMY": {&"difficulty": 0, &"replay_hook": &"LESSON_STARS", &"tension_strength": 0.20, &"leader_drag_mps": 0.40, &"trailer_boost_mps": 0.30, &"breakaway_distance_m": 60.0, &"close_gap_m": 12.0, &"pace_variance": 0.45, &"final_lap_scale": 0.25, &"jump_commitment": 0.95, &"airtime_opportunities": 5, &"airtime_bonus": false, &"featured_rider_ids": [&"LARK", &"DUST", &"MICA", &"SABLE", &"EMBER", &"AXLE", &"NOVA"]},
	&"FREESTYLE": {&"difficulty": 2, &"replay_hook": &"SCORE_COMBOS", &"tension_strength": 0.0, &"leader_drag_mps": 0.0, &"trailer_boost_mps": 0.0, &"breakaway_distance_m": 0.0, &"close_gap_m": 0.0, &"pace_variance": 0.0, &"final_lap_scale": 0.0, &"jump_commitment": 1.15, &"airtime_opportunities": 7, &"airtime_bonus": true},
	&"DISCOVERY": {&"difficulty": 0, &"replay_hook": &"CACHE_ROUTE", &"tension_strength": 0.0, &"leader_drag_mps": 0.0, &"trailer_boost_mps": 0.0, &"breakaway_distance_m": 0.0, &"close_gap_m": 0.0, &"pace_variance": 0.0, &"final_lap_scale": 0.0, &"jump_commitment": 1.00, &"airtime_opportunities": 7, &"airtime_bonus": false},
}

const EVENTS: Dictionary = {
	&"CIRCUIT": {
		&"event_id": &"CIRCUIT", &"track_id": &"QUARRY", &"display_name": "QUARRY TRAIL",
		&"format": &"SPRINT", &"session_type": &"MAIN", &"laps": 1, &"opponent_count": 11,
		&"route_version": 19, &"checkpoint_count": 0, &"weather": &"CLEAR",
		&"medal_times_usec": {&"gold": 165_000_000, &"silver": 220_000_000, &"bronze": 300_000_000},
		&"description": "18-gate quarry sprint. Full field, alternate lines and a downhill finish.",
		&"meta": "1.8 KM  //  12 RIDERS  //  POINT TO POINT", &"unlock_rep": 0,
	},
	&"PINE_ENDURO": {
		&"event_id": &"PINE_ENDURO", &"track_id": &"PINE", &"display_name": "PINE RIDGE ENDURO",
		&"format": &"ENDURO", &"session_type": &"MAIN", &"laps": 1, &"opponent_count": 11,
		&"route_version": 4, &"checkpoint_count": 0, &"weather": &"MIST",
		&"medal_times_usec": {&"gold": 245_000_000, &"silver": 325_000_000, &"bronze": 440_000_000},
		&"description": "Long wooded enduro with creeks, ravines and technical rhythm.",
		# Pine's complete OR gate lives in PlayerProfile: two Quarry clears, a
		# Quarry Rook victory, or 80 total reputation. A second catalog threshold
		# would silently turn those first two routes into an AND condition.
		&"meta": "3.2 KM  //  12 RIDERS  //  ENDURANCE", &"unlock_rep": 0,
	},
	&"MESA_PRACTICE": {
		&"event_id": &"MESA_PRACTICE", &"track_id": &"MESA_MX", &"display_name": "MESA OPEN PRACTICE",
		&"format": &"PRACTICE", &"session_type": &"PRACTICE", &"championship_id": &"", &"laps": 2, &"opponent_count": 3,
		&"route_version": CourseCatalog.MESA_MX_ROUTE_VERSION, &"checkpoint_count": 8, &"weather": &"CLEAR", &"finish_grace_seconds": 5.0,
		&"rules": {&"weekend_session": true},
		&"medal_times_usec": {&"gold": 150_000_000, &"silver": 185_000_000, &"bronze": 230_000_000},
		&"description": "Learn the circuit, discover lines and set a gate-pick baseline.",
		&"meta": "2 LAPS  //  LIGHT TRAFFIC  //  NO POINTS", &"unlock_rep": 30,
	},
	&"MESA_QUALIFYING": {
		&"event_id": &"MESA_QUALIFYING", &"track_id": &"MESA_MX", &"display_name": "MESA QUALIFYING",
		&"format": &"QUALIFYING", &"session_type": &"QUALIFYING", &"championship_id": &"", &"laps": 2, &"opponent_count": 0,
		&"route_version": CourseCatalog.MESA_MX_ROUTE_VERSION, &"checkpoint_count": 8, &"weather": &"CLEAR", &"finish_grace_seconds": 0.0,
		&"rules": {&"weekend_session": true, &"deterministic_ai_times": true},
		&"medal_times_usec": {&"gold": 138_000_000, &"silver": 170_000_000, &"bronze": 215_000_000},
		&"description": "Two clean laps against the clock. Your result chooses the main-event gate.",
		&"meta": "2 LAPS  //  SOLO  //  GATE PICK", &"unlock_rep": 30,
	},
	&"MESA_HEAT": {
		&"event_id": &"MESA_HEAT", &"track_id": &"MESA_MX", &"display_name": "RED MESA HEAT",
		&"format": &"HEAT", &"session_type": &"HEAT", &"championship_id": &"", &"laps": 3, &"opponent_count": 11,
		&"route_version": CourseCatalog.MESA_MX_ROUTE_VERSION, &"checkpoint_count": 8, &"weather": &"CLEAR", &"finish_grace_seconds": 6.0,
		&"rules": {&"weekend_session": true, &"transfer_count": 6},
		&"medal_times_usec": {&"gold": 222_000_000, &"silver": 270_000_000, &"bronze": 335_000_000},
		&"description": "A seeded three-lap heat. The first six riders transfer directly to the main.",
		&"meta": "3 LAPS  //  SEEDED GATES  //  TOP 6 TRANSFER", &"unlock_rep": 30,
	},
	&"MESA_LCQ": {
		&"event_id": &"MESA_LCQ", &"track_id": &"MESA_MX", &"display_name": "RED MESA LCQ",
		&"format": &"LCQ", &"session_type": &"LCQ", &"championship_id": &"", &"laps": 2, &"opponent_count": 5,
		&"route_version": CourseCatalog.MESA_MX_ROUTE_VERSION, &"checkpoint_count": 8, &"weather": &"DUSK", &"finish_grace_seconds": 5.0,
		&"rules": {&"weekend_session": true, &"transfer_count": 4},
		&"medal_times_usec": {&"gold": 150_000_000, &"silver": 185_000_000, &"bronze": 230_000_000},
		&"description": "Two urgent laps for the final four transfer positions in the main event.",
		&"meta": "2 LAPS  //  LAST CHANCE  //  TOP 4 TRANSFER", &"unlock_rep": 30,
	},
	&"MESA_MX": {
		&"event_id": &"MESA_MX", &"track_id": &"MESA_MX", &"display_name": "RED MESA MX MAIN",
		&"format": &"CIRCUIT", &"session_type": &"MAIN", &"laps": 3, &"opponent_count": 11,
		&"route_version": CourseCatalog.MESA_MX_ROUTE_VERSION, &"checkpoint_count": 8, &"weather": &"CLEAR", &"finish_grace_seconds": 7.0,
		&"rules": {&"weekend_session": true, &"championship_round": &"MESA_OPENER"},
		&"medal_times_usec": {&"gold": 225_000_000, &"silver": 270_000_000, &"bronze": 330_000_000},
		&"description": "Three-lap motocross main with a gate drop, rhythm decisions and a full classification.",
		&"meta": "3 LAPS  //  12 RIDERS  //  CHAMPIONSHIP", &"unlock_rep": 30,
	},
	&"MESA_ELIMINATION": {
		&"event_id": &"MESA_ELIMINATION", &"track_id": &"MESA_MX", &"display_name": "LAST RIDER OUT",
		&"format": &"ELIMINATION", &"session_type": &"SPECIAL", &"laps": 4, &"opponent_count": 7,
		&"route_version": CourseCatalog.MESA_MX_ROUTE_VERSION, &"checkpoint_count": 8, &"weather": &"DUSK",
		&"medal_times_usec": {&"gold": 300_000_000, &"silver": 360_000_000, &"bronze": 430_000_000},
		&"rules": {&"eliminate_last_each_lap": true},
		&"description": "The last active rider is eliminated at every lap line.",
		&"meta": "4 LAPS  //  8 RIDERS  //  ELIMINATION", &"unlock_rep": 100,
	},
	&"MESA_RIVAL": {
		&"event_id": &"MESA_RIVAL", &"track_id": &"MESA_MX", &"display_name": "ROOK: HEAD TO HEAD",
		&"format": &"RIVAL", &"session_type": &"SPECIAL", &"laps": 2, &"opponent_count": 1,
		&"route_version": CourseCatalog.MESA_MX_ROUTE_VERSION, &"checkpoint_count": 8, &"weather": &"SUNSET",
		&"rules": {&"rival_only": true},
		&"medal_times_usec": {&"gold": 146_000_000, &"silver": 178_000_000, &"bronze": 220_000_000},
		&"description": "Two laps, two riders, no traffic to blame.",
		&"meta": "2 LAPS  //  HEAD TO HEAD  //  ROOK", &"unlock_rep": 120,
	},
	&"MESA_ENDURANCE": {
		&"event_id": &"MESA_ENDURANCE", &"track_id": &"MESA_MX", &"display_name": "MESA SIX-LAP",
		&"format": &"ENDURANCE", &"session_type": &"SPECIAL", &"laps": 6, &"opponent_count": 11,
		&"route_version": CourseCatalog.MESA_MX_ROUTE_VERSION, &"checkpoint_count": 8, &"weather": &"VARIABLE", &"finish_grace_seconds": 8.0,
		&"medal_times_usec": {&"gold": 445_000_000, &"silver": 525_000_000, &"bronze": 630_000_000},
		&"description": "A longer main where consistency, condition and changing grip matter.",
		&"meta": "6 LAPS  //  12 RIDERS  //  VARIABLE GRIP", &"unlock_rep": 170,
	},
	&"QUARRY_HILLCLIMB": {
		&"event_id": &"QUARRY_HILLCLIMB", &"track_id": &"QUARRY", &"display_name": "CRUSHER HILL CLIMB",
		&"format": &"HILLCLIMB", &"session_type": &"SPECIAL", &"laps": 1, &"opponent_count": 0,
		&"reverse_route": true, &"route_version": 19, &"checkpoint_count": 14, &"weather": &"DUSK",
		&"medal_times_usec": {&"gold": 175_000_000, &"silver": 235_000_000, &"bronze": 315_000_000},
		&"description": "Run Quarry Trail backward: steep power sections and precision crest control.",
		&"meta": "REVERSE  //  SOLO  //  HILL CLIMB", &"unlock_rep": 110,
	},
	&"PINE_WET": {
		&"event_id": &"PINE_WET", &"track_id": &"PINE", &"display_name": "PINE STORM STAGE",
		&"format": &"ENDURO", &"session_type": &"SPECIAL", &"laps": 1, &"opponent_count": 11,
		&"route_version": 4, &"checkpoint_count": 0, &"weather": &"STORM", &"surface_modifier": &"WET",
		&"medal_times_usec": {&"gold": 265_000_000, &"silver": 350_000_000, &"bronze": 470_000_000},
		&"description": "Wet roots, deeper creek crossings and a field searching for grip.",
		&"meta": "3.2 KM  //  WET  //  12 RIDERS", &"unlock_rep": 140,
	},
	&"MESA_RHYTHM": {
		&"event_id": &"MESA_RHYTHM", &"track_id": &"MESA_MX", &"display_name": "RHYTHM ATTACK",
		&"format": &"RHYTHM", &"session_type": &"SPECIAL", &"laps": 1, &"opponent_count": 5,
		&"route_version": CourseCatalog.MESA_MX_ROUTE_VERSION, &"checkpoint_count": 8, &"weather": &"NIGHT",
		&"rules": {&"airtime_bonus": true},
		&"medal_times_usec": {&"gold": 72_000_000, &"silver": 90_000_000, &"bronze": 115_000_000},
		&"description": "One lap. Chain the fastest jump combinations without throwing away landings.",
		&"meta": "1 LAP  //  RHYTHM  //  AIRTIME BONUS", &"unlock_rep": 90,
	},
	&"FREESTYLE": {
		&"event_id": &"FREESTYLE", &"track_id": &"QUARRY", &"display_name": "QUARRY FREESTYLE",
		&"format": &"FREESTYLE", &"description": "Sixty seconds to build physical airtime and rotation combos.",
		&"meta": "60 SEC  //  SCORE ATTACK", &"unlock_rep": 0,
	},
	&"DISCOVERY": {
		&"event_id": &"DISCOVERY", &"track_id": &"QUARRY", &"display_name": "SALVAGE HUNT",
		&"format": &"DISCOVERY", &"description": "Find six workshop caches across Red Mesa.",
		&"meta": "6 CACHES  //  EXPLORATION", &"unlock_rep": 0,
	},
}

const CHAMPIONSHIP_POINTS: Array[int] = [25, 22, 20, 18, 16, 15, 14, 13, 12, 11, 10, 9]
const WEEKEND_EVENT_PHASES: Dictionary[StringName, StringName] = {
	&"MESA_PRACTICE": &"PRACTICE",
	&"MESA_QUALIFYING": &"QUALIFYING",
	&"MESA_HEAT": &"HEAT",
	&"MESA_LCQ": &"LCQ",
	&"MESA_MX": &"MAIN",
}


static func has_event(event_id: StringName) -> bool:
	return EVENTS.has(event_id) or is_challenge_event(event_id) or event_id == &"ACADEMY"


static func is_race_event(event_id: StringName) -> bool:
	return event_id in RACE_EVENTS


static func get_event(event_id: StringName) -> Dictionary:
	var data: Dictionary
	if event_id == &"ACADEMY":
		data = _academy_to_event(get_active_academy_lesson())
	elif is_challenge_event(event_id):
		data = _challenge_to_event(event_id, get_active_challenge(event_id))
	else:
		var fallback: Dictionary = EVENTS[&"CIRCUIT"]
		data = (EVENTS.get(event_id, fallback) as Dictionary).duplicate(true)
	return _with_retention_contract(event_id, data)


static func get_session_config(event_id: StringName, difficulty: int = -1, bike_class: StringName = &"OPEN") -> RaceSessionConfig:
	var data := get_event(event_id)
	if not is_challenge_event(event_id):
		if difficulty >= 0:
			data[&"difficulty"] = difficulty
		elif _player_difficulty_applies(event_id, data):
			var authored_difficulty := clampi(int(data.get(&"difficulty", 2)), 0, 4)
			var offset := get_player_difficulty_offset()
			data[&"difficulty"] = clampi(authored_difficulty + offset, 0, 4)
			var rules := (data.get(&"rules", {}) as Dictionary).duplicate(true)
			rules[&"authored_difficulty"] = authored_difficulty
			rules[&"player_difficulty_mode"] = _player_difficulty_mode
			rules[&"player_difficulty_offset"] = offset
			rules[&"player_difficulty_applied"] = int(data[&"difficulty"]) != authored_difficulty
			var modifiers: Array = (rules.get(&"modifiers", []) as Array).duplicate()
			# STANDARD retains compatibility with the authored pre-setting board.
			# Non-standard modes always get a token, including at clamp boundaries.
			if _player_difficulty_mode != &"STANDARD":
				var difficulty_modifier := "PLAYER_DIFFICULTY_%s" % String(_player_difficulty_mode)
				if not modifiers.has(difficulty_modifier):
					modifiers.append(difficulty_modifier)
			rules[&"modifiers"] = modifiers
			data[&"rules"] = rules
		data[&"bike_class"] = bike_class
	return RaceSessionConfig.from_dictionary(data)


static func set_player_difficulty_mode(mode: Variant) -> StringName:
	var normalized := StringName(str(mode).strip_edges().to_upper())
	_player_difficulty_mode = normalized if normalized in PLAYER_DIFFICULTY_MODES else &"STANDARD"
	return _player_difficulty_mode


static func get_player_difficulty_mode() -> StringName:
	return _player_difficulty_mode


static func get_player_difficulty_offset() -> int:
	return int(PLAYER_DIFFICULTY_OFFSETS.get(_player_difficulty_mode, 0))


static func get_player_difficulty_snapshot(event_id: StringName = &"") -> Dictionary:
	var snapshot := {
		&"mode": _player_difficulty_mode,
		&"offset": get_player_difficulty_offset(),
		&"applicable": false,
		&"authored_difficulty": -1,
		&"effective_difficulty": -1,
	}
	if event_id.is_empty():
		return snapshot
	var data := get_event(event_id)
	var applicable := _player_difficulty_applies(event_id, data)
	var authored := clampi(int(data.get(&"difficulty", 2)), 0, 4)
	snapshot[&"applicable"] = applicable
	snapshot[&"authored_difficulty"] = authored
	snapshot[&"effective_difficulty"] = (
		clampi(authored + get_player_difficulty_offset(), 0, 4)
		if applicable
		else authored
	)
	return snapshot


static func _player_difficulty_applies(event_id: StringName, data: Dictionary) -> bool:
	return (
		is_race_event(event_id)
		and not is_challenge_event(event_id)
		and event_id != &"ACADEMY"
		and int(data.get(&"opponent_count", 0)) > 0
	)


static func get_challenge_session_config(event_id: StringName, challenge: Dictionary) -> RaceSessionConfig:
	if not is_challenge_event(event_id) or challenge.is_empty():
		return get_session_config(event_id)
	return RaceSessionConfig.from_dictionary(_with_retention_contract(event_id, _challenge_to_event(event_id, challenge)))


static func get_retention_contract(event_id: StringName) -> Dictionary:
	return (RETENTION_CONTRACTS.get(event_id, {}) as Dictionary).duplicate(true)


static func _with_retention_contract(event_id: StringName, source: Dictionary) -> Dictionary:
	var data := source.duplicate(true)
	var contract := get_retention_contract(event_id)
	if contract.is_empty():
		return data
	# Challenge schedule difficulty remains authoritative; fixed catalog events
	# inherit their authored tier unless a caller explicitly requests an override.
	if not data.has(&"difficulty"):
		data[&"difficulty"] = int(contract.get(&"difficulty", 2))
	data[&"replay_hook"] = StringName(contract.get(&"replay_hook", &""))
	var rules := (data.get(&"rules", {}) as Dictionary).duplicate(true)
	rules[&"retention"] = contract.duplicate(true)
	rules[&"replay_hook"] = data[&"replay_hook"]
	rules[&"airtime_opportunities"] = int(contract.get(&"airtime_opportunities", 0))
	if bool(contract.get(&"airtime_bonus", false)):
		rules[&"airtime_bonus"] = true
	if not rules.has(&"entrant_ids") and contract.has(&"featured_rider_ids"):
		rules[&"featured_rider_ids"] = (contract.get(&"featured_rider_ids", []) as Array).duplicate()
	data[&"rules"] = rules
	return data


static func get_track_id(event_id: StringName) -> StringName:
	return StringName(get_event(event_id).get(&"track_id", &"QUARRY"))


static func is_unlocked(event_id: StringName, total_reputation: int) -> bool:
	return total_reputation >= int(get_event(event_id).get(&"unlock_rep", 0))


static func is_available_to_profile(event_id: StringName, profile: Node) -> bool:
	if profile == null or not has_event(event_id):
		return false
	var activity_unlocked := (
		not profile.has_method(&"is_activity_unlocked")
		or bool(profile.call(&"is_activity_unlocked", event_id))
	)
	var reputation := (
		int(profile.call(&"get_total_reputation"))
		if profile.has_method(&"get_total_reputation") else 0
	)
	return activity_unlocked and is_unlocked(event_id, reputation)


static func get_unlock_hint(event_id: StringName) -> String:
	var required := int(get_event(event_id).get(&"unlock_rep", 0))
	return "EARN %d TOTAL REP" % required if required > 0 else "AVAILABLE"


static func points_for_position(position: int) -> int:
	return CHAMPIONSHIP_POINTS[position - 1] if position >= 1 and position <= CHAMPIONSHIP_POINTS.size() else 0


static func is_challenge_event(event_id: StringName) -> bool:
	return event_id in [&"DAILY_CHALLENGE", &"WEEKLY_CHALLENGE"]


static func get_active_challenge(event_id: StringName, player_tier: int = -1) -> Dictionary:
	var schedule: Variant = CHALLENGE_SCHEDULE_SCRIPT.new()
	var resolved_tier := player_tier
	if resolved_tier < 0 and Profile.has_method(&"get_total_reputation"):
		resolved_tier = clampi(Profile.get_total_reputation() / 100, 0, 5)
	if event_id == &"WEEKLY_CHALLENGE":
		return schedule.weekly(-1, clampi(resolved_tier, 0, 5))
	if event_id == &"DAILY_CHALLENGE":
		return schedule.daily(-1, clampi(resolved_tier, 0, 5))
	return {}


static func get_active_academy_lesson() -> Dictionary:
	## Single Academy selection authority used by the Garage, session composer,
	## results continuation, and tests. A lesson is complete after any passing
	## grade; higher-star attempts require an explicit rematch override.
	var catalog: Variant = ACADEMY_CATALOG_SCRIPT.create_default()
	var completed: Array[StringName] = Profile.get_completed_academy_lessons() if Profile.has_method(&"get_completed_academy_lessons") else []
	var reputation := Profile.racer_reputation if Profile != null else 0
	var available: Array[Dictionary] = catalog.get_available_lessons(completed, reputation)
	if available.is_empty():
		return catalog.get_lessons()[0] if not catalog.get_lessons().is_empty() else {}
	var progress := Profile.get_academy_progress_snapshot() if Profile.has_method(&"get_academy_progress_snapshot") else {}
	if not _academy_lesson_override.is_empty() and int(progress.get(_academy_lesson_override, 0)) > 0:
		for lesson: Dictionary in available:
			if StringName(lesson.get(&"lesson_id", &"")) == _academy_lesson_override:
				return lesson
	# Profile changes can invalidate a runtime override. Never let stale state
	# bypass completion, prerequisites, or reputation gates.
	if not _academy_lesson_override.is_empty():
		_academy_lesson_override = &""
	for lesson: Dictionary in available:
		if int(progress.get(StringName(lesson.get(&"lesson_id", &"")), 0)) <= 0:
			return lesson
	# When every currently available lesson is complete, keep Academy playable by
	# replaying the most advanced available lesson. The Garage labels this state as
	# a replay instead of incorrectly claiming that a new lesson is pending.
	return available.back()


static func request_academy_rematch(lesson_id: StringName) -> bool:
	## Explicit, runtime-only opt-in for improving a completed lesson's star grade.
	## Normal progression never sets this override.
	if lesson_id.is_empty():
		return false
	var progress := Profile.get_academy_progress_snapshot() if Profile.has_method(&"get_academy_progress_snapshot") else {}
	if int(progress.get(lesson_id, 0)) <= 0:
		return false
	var catalog: Variant = ACADEMY_CATALOG_SCRIPT.create_default()
	var completed: Array[StringName] = Profile.get_completed_academy_lessons() if Profile.has_method(&"get_completed_academy_lessons") else []
	var available: Array[Dictionary] = catalog.get_available_lessons(completed, Profile.racer_reputation)
	for lesson: Dictionary in available:
		if StringName(lesson.get(&"lesson_id", &"")) == lesson_id:
			_academy_lesson_override = lesson_id
			return true
	return false


static func clear_academy_lesson_override() -> void:
	_academy_lesson_override = &""


static func get_academy_lesson_override() -> StringName:
	return _academy_lesson_override


static func _academy_to_event(lesson: Dictionary) -> Dictionary:
	if lesson.is_empty():
		return EVENTS[&"MESA_PRACTICE"].duplicate(true)
	var lesson_id := StringName(lesson.get(&"lesson_id", &"CONTROL_BASICS"))
	var opponents := 0
	if lesson_id == &"GATE_DROP":
		opponents = 5
	elif lesson_id == &"SAFE_RECOVERY":
		opponents = 3
	elif lesson_id == &"PASSING_RACECRAFT":
		opponents = 7
	var lap_count := 2 if lesson_id in [&"PRELOAD_LANDING", &"RHYTHM_CHOICES", &"AIR_CONTROL", &"PASSING_RACECRAFT"] else 1
	var target_usec := 86_000_000 * lap_count
	var lesson_objectives := (lesson.get(&"objectives", []) as Array).duplicate(true)
	var lesson_presentation := (lesson.get(&"presentation", {}) as Dictionary).duplicate(true)
	return {
		&"event_id": &"ACADEMY",
		&"track_id": CourseCatalog.MESA_MX_ID,
		&"display_name": "ACADEMY: %s" % str(lesson.get(&"display_name", "RIDE LESSON")).to_upper(),
		&"format": &"ACADEMY",
		&"session_type": &"ACADEMY",
		&"championship_id": &"",
		&"laps": lap_count,
		&"opponent_count": opponents,
		&"route_version": CourseCatalog.MESA_MX_ROUTE_VERSION,
		&"checkpoint_count": 10,
		&"weather": &"CLEAR",
		&"surface_modifier": &"PACKED",
		&"finish_grace_seconds": 5.0 if opponents > 0 else 0.0,
		# Academy grades demonstrated skills and recovery counts, not elapsed
		# time. A safe rejoin remains visible in the objective but adds no
		# competitive time penalty.
		&"reset_penalty_usec": 0,
		&"rules": {
			&"academy": true,
			&"academy_lesson_id": lesson_id,
			&"academy_display_name": str(lesson.get(&"display_name", "RIDE LESSON")),
			&"academy_category": StringName(lesson.get(&"category", &"FOUNDATIONS")),
			&"academy_description": str(lesson.get(&"description", "Complete the marked riding lesson.")),
			&"academy_objectives": lesson_objectives,
			&"academy_presentation": lesson_presentation,
		},
		&"medal_times_usec": {
			&"gold": target_usec,
			&"silver": roundi(float(target_usec) * 1.28),
			&"bronze": roundi(float(target_usec) * 1.65),
		},
		&"description": str(lesson.get(&"description", "Complete the marked riding lesson.")),
		&"meta": "%s  //  %d LAP%s  //  METRIC-GRADED" % [str(lesson.get(&"category", &"FOUNDATIONS")), lap_count, "S" if lap_count > 1 else ""],
		&"unlock_rep": 0,
	}


static func is_weekend_event(event_id: StringName) -> bool:
	return WEEKEND_EVENT_PHASES.has(event_id)


static func get_weekend_phase(event_id: StringName) -> StringName:
	return WEEKEND_EVENT_PHASES.get(event_id, &"")


static func get_weekend_event(phase: StringName) -> StringName:
	for event_id: StringName in WEEKEND_EVENT_PHASES:
		if WEEKEND_EVENT_PHASES[event_id] == phase:
			return event_id
	return &""


static func get_recommended_event() -> StringName:
	## Non-blocking progression authority shared by Garage and results. Weekend
	## phases win because their transferred field is stateful and cannot be
	## replaced by a standalone event selection.
	if Profile.has_method(&"is_first_run_onboarding_active") and Profile.is_first_run_onboarding_active():
		return &"ACADEMY"
	if Profile.has_method(&"get_race_weekend_director"):
		var weekend: Variant = Profile.get_race_weekend_director()
		if weekend != null:
			var weekend_event := get_weekend_event(StringName(weekend.get_current_phase()))
			if not weekend_event.is_empty() and _profile_can_enter(weekend_event):
				return weekend_event
	if not Profile.has_completed_event(&"CIRCUIT"):
		return &"CIRCUIT"
	if Profile.has_method(&"get_championship_service"):
		var championship: Variant = Profile.get_championship_service()
		var next_round: Dictionary = championship.get_next_round() if championship != null else {}
		var round_event := StringName(next_round.get(&"event_id", &""))
		if has_event(round_event) and _profile_can_enter(round_event):
			return round_event
	for event_id: StringName in [&"PINE_ENDURO", &"MESA_ELIMINATION", &"MESA_RIVAL", &"MESA_ENDURANCE"]:
		if _profile_can_enter(event_id) and not Profile.has_completed_event(event_id):
			return event_id
	return &"CIRCUIT"


static func _profile_can_enter(event_id: StringName) -> bool:
	return is_available_to_profile(event_id, Profile)


static func get_default_weekend_config() -> Dictionary:
	var entrants: Array[Dictionary] = [{
		&"rider_id": &"PLAYER", &"display_name": "YOU", &"seed": 1, &"number": 1,
		&"color": Color("ffb52d"), &"is_player": true,
	}]
	var field := RiderRoster.get_field(11)
	for index: int in field.size():
		var rider: Dictionary = field[index]
		entrants.append({
			&"rider_id": StringName(rider.get(&"id", &"")),
			&"display_name": str(rider.get(&"name", "RIDER")),
			&"seed": index + 2,
			&"number": int(rider.get(&"number", index + 2)),
			&"color": rider.get(&"bike", Color.WHITE),
			&"pace": float(rider.get(&"pace", 0.82)),
			&"is_player": false,
		})
	return {
		&"weekend_id": &"RED_MESA_OPEN",
		&"event_id": &"MESA_MX",
		&"display_name": "RED MESA OPEN",
		&"entrants": entrants,
		&"heat_transfer_count": 6,
		&"lcq_transfer_count": 4,
		&"main_field_limit": 10,
	}


static func _challenge_to_event(event_id: StringName, challenge: Dictionary) -> Dictionary:
	if challenge.is_empty():
		return EVENTS[&"CIRCUIT"].duplicate(true)
	var track_id := StringName(str(challenge.get("track_id", "QUARRY")).to_upper())
	if track_id not in [CourseCatalog.QUARRY_ID, CourseCatalog.PINE_ID, CourseCatalog.MESA_MX_ID]:
		track_id = CourseCatalog.QUARRY_ID
	var format := StringName(str(challenge.get("format", "TIME_ATTACK")).to_upper())
	var bike_class_source := StringName(str(challenge.get("bike_class", "OPEN")).to_upper())
	var bike_class := &"OPEN"
	match bike_class_source:
		&"LIGHTWEIGHT": bike_class = &"LITE_125"
		&"MIDDLEWEIGHT": bike_class = &"SPORT_250"
	var opponent_count := 0 if format == &"TIME_ATTACK" else 1 if format == &"RIVAL_DUEL" else 11
	var modifiers: Array = (challenge.get("modifiers", []) as Array).duplicate()
	var modifier_labels := PackedStringArray()
	for raw_modifier: Variant in modifiers:
		modifier_labels.append(str(raw_modifier))
	var rules: Dictionary = {
		&"challenge_id": str(challenge.get("challenge_id", "")),
		&"competition_id": StringName(challenge.get("competition_id", &"")),
		&"challenge_kind": StringName(str(challenge.get("kind", "DAILY")).to_upper()),
		&"competitive_event_id": "%s_CHALLENGE" % String(format),
		&"competitive_bike_class": bike_class_source,
		&"competitive_difficulty": clampi(int(challenge.get("difficulty", 2)), 0, 10),
		&"competitive_assist_mode": StringName(str(challenge.get("assist_mode", "STANDARD")).to_upper()),
		&"competitive_setup_id": StringName(str(challenge.get("setup_id", "BALANCED")).to_upper()),
		&"starts_unix": int(challenge.get("starts_unix", 0)),
		&"ends_unix": int(challenge.get("ends_unix", 0)),
		&"seed": int(challenge.get("seed", 0)),
		&"modifiers": modifiers,
		&"reward_multiplier": float(challenge.get("reward_multiplier", 1.0)),
		&"run_signature": str(challenge.get("run_signature", "")),
	}
	for raw_modifier: Variant in modifiers:
		var modifier := StringName(str(raw_modifier).to_upper())
		rules[modifier] = true
	var lap_count := maxi(int(challenge.get("laps", 1)), 1)
	var base_lap_usec := 82_000_000 if track_id == CourseCatalog.MESA_MX_ID else 245_000_000 if track_id == CourseCatalog.PINE_ID else 165_000_000
	var target_usec := base_lap_usec * lap_count
	return {
		&"event_id": event_id,
		&"track_id": track_id,
		&"display_name": "WEEKLY CHALLENGE" if event_id == &"WEEKLY_CHALLENGE" else "DAILY CHALLENGE",
		&"format": format,
		&"session_type": &"CHALLENGE",
		&"championship_id": &"",
		&"laps": lap_count,
		&"opponent_count": opponent_count,
		&"route_version": maxi(int(challenge.get("route_version", 1)), 1),
		&"checkpoint_count": 8 if track_id == CourseCatalog.MESA_MX_ID else 0,
		&"difficulty": clampi(int(challenge.get("difficulty", 2)), 0, 4),
		&"bike_class": bike_class,
		&"weather": StringName(str(challenge.get("weather", "CLEAR")).to_upper()),
		&"surface_modifier": StringName(str(challenge.get("surface", "PACKED")).to_upper()),
		&"finish_grace_seconds": 0.0 if opponent_count == 0 else 5.0 if opponent_count <= 5 else 6.0,
		&"rules": rules,
		&"medal_times_usec": {
			&"gold": target_usec,
			&"silver": roundi(float(target_usec) * 1.25),
			&"bronze": roundi(float(target_usec) * 1.6),
		},
		&"description": "%s on %s. Active modifiers: %s." % [
			String(format).replace("_", " "), String(track_id).replace("_", " "),
			", ".join(modifier_labels) if not modifier_labels.is_empty() else "STANDARD RULES",
		],
		&"meta": "%s  //  %d LAP%s  //  %s" % [
			String(track_id).replace("_", " "), lap_count, "S" if lap_count != 1 else "", String(format).replace("_", " "),
		],
		&"unlock_rep": 0,
	}


static func prepare_route(config: RaceSessionConfig, authoritative_route: PackedVector3Array) -> PackedVector3Array:
	var route := authoritative_route.duplicate()
	if config.reverse_route:
		route.reverse()
	return route


static func checkpoint_data(config: RaceSessionConfig, route: PackedVector3Array) -> Array[Dictionary]:
	if config.checkpoint_count <= 0 and not config.reverse_route:
		return CourseCatalog.get_checkpoint_data(config.track_id, route)
	return _uniform_checkpoint_data(route, maxi(config.checkpoint_count, 6))


static func _uniform_checkpoint_data(route: PackedVector3Array, count: int) -> Array[Dictionary]:
	var checkpoints: Array[Dictionary] = []
	if route.size() < 2:
		return checkpoints
	var cumulative := PackedFloat32Array()
	cumulative.resize(route.size())
	var length := 0.0
	for index: int in range(1, route.size()):
		length += route[index - 1].distance_to(route[index])
		cumulative[index] = length
	for gate_index: int in count:
		# The first physical gate is placed after the grid. The final gate remains
		# exactly at the finish seam so lap validation cannot be short-cut.
		var ratio := float(gate_index + 1) / float(count)
		var distance := length * ratio
		var segment := 0
		while segment < cumulative.size() - 2 and cumulative[segment + 1] < distance:
			segment += 1
		var weight := inverse_lerp(cumulative[segment], cumulative[segment + 1], distance)
		var position := route[segment].lerp(route[segment + 1], weight)
		var tangent := (route[segment + 1] - route[segment]).normalized()
		checkpoints.append({&"position": position, &"yaw": atan2(-tangent.x, -tangent.z), &"ratio": ratio})
	return checkpoints
