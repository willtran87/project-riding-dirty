extends Node
## Deterministic contract for traffic-authored, bounded track evolution.

const EVOLUTION_SCRIPT := preload("res://features/environment/track_evolution.gd")

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var evolution := EVOLUTION_SCRIPT.new() as TrackEvolution
	add_child(evolution)
	var route := PackedVector3Array([
		Vector3(0.0, 2.0, 0.0),
		Vector3(0.0, 2.5, -60.0),
		Vector3(20.0, 3.0, -120.0),
		Vector3(55.0, 4.0, -170.0),
	])
	evolution.configure(route, 10.0, &"QUARRY", &"CLEAR", &"DIRT", true)
	var fresh := evolution.sample_line(18.0, 0.0)
	_check(
		bool(fresh.get(&"active", false))
			and StringName(fresh.get(&"state", &"INVALID")) == &"FRESH"
			and is_equal_approx(float(fresh.get(&"grip_multiplier", 0.0)), 1.0)
			and is_equal_approx(float(fresh.get(&"drive_multiplier", 0.0)), 1.0),
		"A fresh route did not preserve neutral handling"
	)

	var accepted_passes := 0
	for index: int in 6:
		if evolution.record_pass(
			StringName("RIDER_%02d" % index),
			18.0,
			0.0,
			12.0 + float(index) * 0.2,
			index == 0
		):
			accepted_passes += 1
	var duplicate_rejected := not evolution.record_pass(
		&"RIDER_00", 19.0, 0.0, 15.0, true
	)
	var compacted := evolution.sample_line(18.0, 0.0)
	var untouched := evolution.sample_line(18.0, -3.3, false)
	evolution.force_refresh_visual()
	var snapshot := evolution.get_snapshot()
	_check(
		accepted_passes == 6
			and duplicate_rejected
			and int(snapshot.get(&"sampled_passes", 0)) == 6,
		"Pass accounting was frame-dependent or accepted duplicate bin samples"
	)
	_check(
		StringName(compacted.get(&"state", &"")) in [&"COMPACTED", &"DEEP_RUT"]
			and float(compacted.get(&"wear", 0.0)) >= 0.30
			and float(compacted.get(&"grip_multiplier", 1.0)) > 1.0
			and float(compacted.get(&"drive_multiplier", 1.0)) > 1.0
			and float(compacted.get(&"rut_strength", 0.0)) > 0.0,
		"Repeated dry traffic did not create a modest faster, captured line"
	)
	_check(
		float(untouched.get(&"wear", 1.0)) < 0.01
			and is_equal_approx(float(untouched.get(&"grip_multiplier", 0.0)), 1.0),
		"Traffic wear leaked across unrelated lanes"
	)
	_check(
		int(snapshot.get(&"visible_grooves", 0)) >= 1
			and float(snapshot.get(&"maximum_wear", 0.0)) <= TrackEvolution.MAX_WEAR
			and int(snapshot.get(&"collision_count", -1)) == 0
			and evolution.find_children("*", "CollisionObject3D", true, false).is_empty(),
		"Evolved grooves were invisible, unbounded, or added collision geometry"
	)

	evolution.set_surface(&"WET", &"RAIN")
	var slick := evolution.sample_line(18.0, 0.0)
	_check(
		bool(slick.get(&"wet_policy", false))
			and StringName(slick.get(&"state", &"")) in [&"SLICK_GROOVE", &"DEEP_RUT"]
			and float(slick.get(&"grip_multiplier", 1.0)) < 1.0
			and float(slick.get(&"drive_multiplier", 1.0)) < 1.0,
		"Wet weather did not turn the same readable groove into a bounded risk"
	)

	evolution.reset_evolution()
	var reset := evolution.get_snapshot()
	var reset_line := reset.get(&"player_line", {}) as Dictionary
	_check(
		int(reset.get(&"sampled_passes", -1)) == 0
			and int(reset.get(&"visible_grooves", -1)) == 0
			and is_equal_approx(float(reset.get(&"maximum_wear", -1.0)), 0.0)
			and StringName(reset_line.get(&"state", &"")) == &"FRESH",
		"Race restart did not restore a fair fresh track"
	)

	evolution.configure(route, 10.0, &"QUARRY", &"CLEAR", &"PACKED", false)
	_check(
		not bool(evolution.get_snapshot().get(&"active", true))
			and not evolution.visible,
		"Academy/Test Ride isolation could not disable track evolution"
	)
	_check_source_integration()

	if _failures.is_empty():
		print(
			"TRACK EVOLUTION PROBE: PASS // traffic=6 compacted=true "
			+ "wet_risk=true lane_isolated=true collision_free=true schema=13"
		)
	else:
		for failure: String in _failures:
			push_error("TRACK EVOLUTION PROBE: " + failure)
	evolution.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check_source_integration() -> void:
	var race_source := FileAccess.get_file_as_string(
		"res://features/race/race_controller.gd"
	)
	var bike_source := FileAccess.get_file_as_string(
		"res://entities/bike/bike_controller.gd"
	)
	var hud_source := FileAccess.get_file_as_string(
		"res://features/hud/race_hud.gd"
	)
	var main_source := FileAccess.get_file_as_string("res://scenes/main.gd")
	var web_source := FileAccess.get_file_as_string(
		"res://common/web_game_text_state.gd"
	)
	_check(
		race_source.contains("_update_track_evolution(delta)")
			and race_source.contains("&\"track_evolution\": get_track_evolution_snapshot()")
			and race_source.contains("_track_evolution.sample_line("),
		"Race lifecycle omitted real player/opponent traffic or handling context"
	)
	_check(
		bike_source.contains("evolution_drive_multiplier")
			and bike_source.contains("evolution_grip_multiplier"),
		"Bike physics omitted bounded evolved-line drive or grip behavior"
	)
	_check(
		hud_source.contains("COMPACTED LINE +GRIP")
			and hud_source.contains("SLICK GROOVE"),
		"HUD omitted readable benefit/risk feedback for evolved lines"
	)
	_check(
		main_source.contains("&\"track_evolution\": _race.get_track_evolution_snapshot()")
			and web_source.contains("const SCHEMA_VERSION := 13")
			and web_source.contains("_track_evolution_projection"),
		"Browser-readable state omitted bounded track-evolution observability"
	)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
