extends "res://common/player_profile.gd"
## Fault-injection profile used only by the activity settlement integrity probe.

var fail_next_save: bool = false
var save_attempt_count: int = 0


func _save_profile() -> bool:
	save_attempt_count += 1
	if fail_next_save:
		fail_next_save = false
		return false
	return true
