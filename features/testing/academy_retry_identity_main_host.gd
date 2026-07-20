extends "res://scenes/main.gd"
## Narrow Main host for the Academy retry identity regression probe.

var physical_run_prepare_count: int = 0


func _refresh_touch_context() -> void:
	pass


func _refresh_career_services() -> void:
	pass


func _stop_all_activities() -> void:
	physical_run_prepare_count += 1
