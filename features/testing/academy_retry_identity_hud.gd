extends "res://features/hud/race_hud.gd"
## Result sink that keeps the probe headless and independent of HUD scene wiring.

var shown_results: Dictionary = {}
var show_count: int = 0


func show_results(result: Dictionary) -> void:
	show_count += 1
	shown_results = result.duplicate(true)
