extends Node3D
## Ensures green ground-cover remains behind the visible/physical race corridor.

const TRACKS: Array[Dictionary] = [
	{&"id": CourseCatalog.QUARRY_ID, &"scene": preload("res://levels/quarry/quarry.tscn")},
	{&"id": CourseCatalog.PINE_ID, &"scene": preload("res://levels/pine_ridge/pine_ridge.tscn")},
]


func _ready() -> void:
	var passed := true
	for track: Dictionary in TRACKS:
		var level := (track[&"scene"] as PackedScene).instantiate() as Node3D
		add_child(level)
		for _frame: int in 3:
			await get_tree().process_frame
		var track_id: StringName = track[&"id"]
		var dressing := level.find_child("CourseDressing", true, false) as Node3D
		if dressing == null:
			push_error("GROUND COVER CLEARANCE: track=%s dressing_missing=true" % track_id)
			passed = false
			level.queue_free()
			await get_tree().process_frame
			continue
		var required := float(dressing.get_meta(
			&"natural_ground_cover_minimum_route_clearance", -1.0
		))
		var minimum := float(dressing.get_meta(
			&"natural_ground_cover_actual_minimum_route_clearance", -1.0
		))
		var instance_count := int(dressing.get_meta(&"natural_ground_cover_instance_count", 0))
		var track_passed := required > 0.0 and instance_count > 0 and minimum + 0.01 >= required
		print("GROUND COVER CLEARANCE: track=%s instances=%d minimum=%.3fm required=%.3fm passed=%s" % [
			track_id, instance_count, minimum, required, str(track_passed),
		])
		passed = passed and track_passed
		level.queue_free()
		await get_tree().process_frame
	print("GROUND COVER CLEARANCE RESULT: passed=%s" % str(passed))
	get_tree().quit(0 if passed else 1)
