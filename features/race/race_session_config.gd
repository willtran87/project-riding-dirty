extends Resource
class_name RaceSessionConfig
## Immutable-at-runtime description of one competitive session.

var event_id: StringName = &"CIRCUIT"
var track_id: StringName = &"QUARRY"
var display_name: String = "QUARRY TRAIL"
var format: StringName = &"SPRINT"
var session_type: StringName = &"MAIN"
var weekend_id: StringName = &"RED_MESA_OPEN"
var championship_id: StringName = &"DIRT_TOUR"
var route_version: int = 1
var laps: int = 1
var field_size: int = 12
var difficulty: int = 2
var bike_class: StringName = &"OPEN"
var reverse_route: bool = false
var practice_seconds: float = 0.0
var staging_seconds: float = 1.35
var countdown_seconds: float = 3.25
var finish_grace_seconds: float = 6.0
var off_course_grace_seconds: float = 2.4
var wrong_way_grace_seconds: float = 1.4
var reset_penalty_usec: int = 2_000_000
var cut_penalty_usec: int = 3_000_000
var opponent_count: int = 11
var checkpoint_count: int = 0
var medal_times_usec: Dictionary = {}
var weather: StringName = &"CLEAR"
var surface_modifier: StringName = &"PACKED"
var rules: Dictionary = {}


static func from_dictionary(data: Dictionary) -> RaceSessionConfig:
	var config := RaceSessionConfig.new()
	config.event_id = StringName(data.get(&"event_id", &"CIRCUIT"))
	config.track_id = StringName(data.get(&"track_id", &"QUARRY"))
	config.display_name = str(data.get(&"display_name", "QUARRY TRAIL"))
	config.format = StringName(data.get(&"format", &"SPRINT"))
	config.session_type = StringName(data.get(&"session_type", &"MAIN"))
	config.weekend_id = StringName(data.get(&"weekend_id", &"RED_MESA_OPEN"))
	config.championship_id = StringName(data.get(&"championship_id", &"DIRT_TOUR"))
	config.route_version = maxi(int(data.get(&"route_version", 1)), 1)
	config.laps = maxi(int(data.get(&"laps", 1)), 1)
	config.field_size = clampi(int(data.get(&"field_size", 12)), 1, 12)
	config.difficulty = clampi(int(data.get(&"difficulty", 2)), 0, 4)
	config.bike_class = StringName(data.get(&"bike_class", &"OPEN"))
	config.reverse_route = bool(data.get(&"reverse_route", false))
	config.practice_seconds = maxf(float(data.get(&"practice_seconds", 0.0)), 0.0)
	config.staging_seconds = maxf(float(data.get(&"staging_seconds", 1.35)), 0.0)
	config.countdown_seconds = maxf(float(data.get(&"countdown_seconds", 3.25)), 0.1)
	var configured_opponents := clampi(int(data.get(&"opponent_count", config.field_size - 1)), 0, 11)
	var default_finish_grace := 0.0 if configured_opponents == 0 else 6.0
	config.finish_grace_seconds = clampf(float(data.get(&"finish_grace_seconds", default_finish_grace)), 0.0, 8.0)
	config.off_course_grace_seconds = maxf(float(data.get(&"off_course_grace_seconds", 2.4)), 0.25)
	config.wrong_way_grace_seconds = maxf(float(data.get(&"wrong_way_grace_seconds", 1.4)), 0.25)
	config.reset_penalty_usec = maxi(int(data.get(&"reset_penalty_usec", 2_000_000)), 0)
	config.cut_penalty_usec = maxi(int(data.get(&"cut_penalty_usec", 3_000_000)), 0)
	config.opponent_count = configured_opponents
	config.field_size = config.opponent_count + 1
	config.checkpoint_count = maxi(int(data.get(&"checkpoint_count", 0)), 0)
	config.medal_times_usec = (data.get(&"medal_times_usec", {}) as Dictionary).duplicate(true)
	config.weather = StringName(data.get(&"weather", &"CLEAR"))
	config.surface_modifier = StringName(data.get(&"surface_modifier", &"PACKED"))
	config.rules = (data.get(&"rules", {}) as Dictionary).duplicate(true)
	return config


func to_dictionary() -> Dictionary:
	return {
		&"event_id": event_id,
		&"track_id": track_id,
		&"display_name": display_name,
		&"format": format,
		&"session_type": session_type,
		&"weekend_id": weekend_id,
		&"championship_id": championship_id,
		&"route_version": route_version,
		&"laps": laps,
		&"field_size": field_size,
		&"difficulty": difficulty,
		&"bike_class": bike_class,
		&"reverse_route": reverse_route,
		&"practice_seconds": practice_seconds,
		&"staging_seconds": staging_seconds,
		&"countdown_seconds": countdown_seconds,
		&"finish_grace_seconds": finish_grace_seconds,
		&"off_course_grace_seconds": off_course_grace_seconds,
		&"wrong_way_grace_seconds": wrong_way_grace_seconds,
		&"reset_penalty_usec": reset_penalty_usec,
		&"cut_penalty_usec": cut_penalty_usec,
		&"opponent_count": opponent_count,
		&"checkpoint_count": checkpoint_count,
		&"medal_times_usec": medal_times_usec.duplicate(true),
		&"weather": weather,
		&"surface_modifier": surface_modifier,
		&"rules": rules.duplicate(true),
	}


func run_signature(setup_id: StringName, assist_mode: StringName, tune_signature: String = "") -> String:
	return "%s|%s|r%d|%s|l%d|c%s|d%d|a%s|%s|%s" % [
		String(event_id), String(track_id), route_version, String(format), laps,
		String(bike_class), difficulty, String(assist_mode), String(setup_id), tune_signature,
	]
