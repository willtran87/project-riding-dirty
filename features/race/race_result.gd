extends RefCounted
class_name RaceResult
## Complete, serializable output from a competitive session.

var run_id: String = ""
var signature: String = ""
var event_id: StringName = &"CIRCUIT"
var track_id: StringName = &"QUARRY"
var format: StringName = &"SPRINT"
var session_type: StringName = &"MAIN"
var championship_id: StringName = &"DIRT_TOUR"
var valid: bool = true
var validity_reason: String = ""
var medal: StringName = &"FINISHER"
var classification: Array[Dictionary] = []
var player_position: int = 1
var player_time_usec: int = -1
var player_penalty_usec: int = 0
var fastest_lap_usec: int = -1
var fastest_rider_id: StringName = &""
var reset_count: int = 0
var off_course_count: int = 0
var wrong_way_count: int = 0
var cut_count: int = 0
var overtakes: int = 0
var contacts: int = 0
var crashes: int = 0
var recoveries: int = 0
var near_misses: int = 0
var holeshot_rider_id: StringName = &""
var sector_times_usec: Array[int] = []
var lap_times_usec: Array[int] = []
var rewards: Dictionary = {}
var championship_points: int = 0
var academy_metrics: Dictionary = {}


func to_dictionary() -> Dictionary:
	return {
		&"run_id": run_id,
		&"signature": signature,
		&"event_id": event_id,
		&"track_id": track_id,
		&"format": format,
		&"session_type": session_type,
		&"championship_id": championship_id,
		&"valid": valid,
		&"validity_reason": validity_reason,
		&"medal": medal,
		&"classification": classification.duplicate(true),
		&"player_position": player_position,
		&"player_time_usec": player_time_usec,
		&"player_penalty_usec": player_penalty_usec,
		&"fastest_lap_usec": fastest_lap_usec,
		&"fastest_rider_id": fastest_rider_id,
		&"reset_count": reset_count,
		&"off_course_count": off_course_count,
		&"wrong_way_count": wrong_way_count,
		&"cut_count": cut_count,
		&"overtakes": overtakes,
		&"contacts": contacts,
		&"crashes": crashes,
		&"recoveries": recoveries,
		&"near_misses": near_misses,
		&"holeshot_rider_id": holeshot_rider_id,
		&"sector_times_usec": sector_times_usec.duplicate(),
		&"lap_times_usec": lap_times_usec.duplicate(),
		&"rewards": rewards.duplicate(true),
		&"championship_points": championship_points,
		&"academy_metrics": academy_metrics.duplicate(true),
	}
