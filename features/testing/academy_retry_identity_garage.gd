extends "res://features/garage/garage_ui.gd"
## Garage sink used by the headless Academy retry identity probe.

var hide_count: int = 0


func hide_garage() -> void:
	hide_count += 1
