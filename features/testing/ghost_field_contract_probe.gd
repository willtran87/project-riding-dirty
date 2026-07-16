extends Node
## Ensures physical race fields never duplicate Rook as a translucent target,
## while solo multi-lap sessions receive a correctly repeated target route.

func _ready() -> void:
	Profile.persistence_enabled = false
	var ghost := GhostController.new()
	ghost.persistence_enabled = false
	add_child(ghost)
	var route := CourseCatalog.get_world_riding_points(CourseCatalog.MESA_MX_ID)
	var points: Array[Vector3] = []
	points.assign(route)
	var baseline_target := CourseCatalog.get_rival_target_usec(CourseCatalog.MESA_MX_ID)
	var two_lap_target := roundi(float(baseline_target) * 2.0 / 3.0)

	ghost.configure_rival(points, two_lap_target, 2, true, false)
	var source_preserved := ghost.get_rival_source_points().size() == route.size()
	var physical_field_only := not ghost.is_rival_configured()

	ghost.configure_rival(points, two_lap_target, 2, true, true)
	var curve := ghost.get("_rival_curve") as Curve3D
	var source_length := 0.0
	for index: int in range(1, route.size()):
		source_length += route[index - 1].distance_to(route[index])
	var repeated_length := curve.get_baked_length() if curve != null else 0.0
	var solo_target_ready := ghost.is_rival_configured()
	var repeated_every_lap := repeated_length >= source_length * 1.72
	var target_seconds := float(ghost.get("_rival_target_seconds"))
	var target_covers_laps := absf(target_seconds - float(two_lap_target) / 1_000_000.0) <= 0.01

	var passed := source_preserved and physical_field_only and solo_target_ready and repeated_every_lap and target_covers_laps
	print("GHOST FIELD CONTRACT: field_duplicate=false source=%d/%d solo=%s curve=%.1f/%.1fm target=%.1fs passed=%s" % [
		ghost.get_rival_source_points().size(), route.size(), str(solo_target_ready), repeated_length,
		source_length, target_seconds, str(passed),
	])
	get_tree().quit(0 if passed else 1)
