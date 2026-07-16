extends RefCounted
class_name RacerResult
## Stable classification record for a human or computer rider.

var rider_id: StringName = &"PLAYER"
var display_name: String = "YOU"
var number: int = 1
var color: Color = Color.WHITE
var is_player: bool = false
var position: int = 0
var status: StringName = &"RUNNING"
var laps_completed: int = 0
var total_progress: float = 0.0
var finish_usec: int = -1
var penalty_usec: int = 0
var best_lap_usec: int = -1
var last_lap_usec: int = -1
var gap_usec: int = 0
var overtakes: int = 0
var contacts: int = 0
var crashes: int = 0
var resets: int = 0
var holeshot: bool = false


func effective_time_usec() -> int:
	return finish_usec + penalty_usec if finish_usec >= 0 else 9_223_372_036_854_775_000


func to_dictionary() -> Dictionary:
	return {
		&"rider_id": rider_id,
		&"display_name": display_name,
		&"number": number,
		&"color": color,
		&"is_player": is_player,
		&"position": position,
		&"status": status,
		&"laps_completed": laps_completed,
		&"total_progress": total_progress,
		&"finish_usec": finish_usec,
		&"penalty_usec": penalty_usec,
		&"effective_time_usec": effective_time_usec(),
		&"best_lap_usec": best_lap_usec,
		&"last_lap_usec": last_lap_usec,
		&"gap_usec": gap_usec,
		&"overtakes": overtakes,
		&"contacts": contacts,
		&"crashes": crashes,
		&"resets": resets,
		&"holeshot": holeshot,
	}
