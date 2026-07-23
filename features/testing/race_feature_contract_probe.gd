extends Node
## Regression for event promises that must materially affect a live race.


func _ready() -> void:
	var race := RaceController.new()
	var endurance := RaceEventCatalog.get_session_config(&"MESA_ENDURANCE")
	race.set("_session_config", endurance)
	var surfaces: Array[StringName] = []
	for lap: int in range(1, 7):
		surfaces.append(race.call("_surface_for_lap", lap) as StringName)
	var variable_grip := surfaces == [
		&"PACKED", &"LOOSE_DIRT", &"PACKED", &"WET", &"RUTTED", &"PACKED",
	]

	var rhythm := RaceEventCatalog.get_session_config(&"MESA_RHYTHM")
	race.set("_session_config", rhythm)
	race.state = RaceController.State.RACING
	var moments: Array[Dictionary] = []
	race.race_moment.connect(func(label: String, points: int, positive: bool) -> void:
		moments.append({&"label": label, &"points": points, &"positive": positive})
	)
	race.call("_on_academy_bike_landed", 0.3)
	race.call("_on_bike_trick_landed", 1.4, 0.2, 0.3, true)
	race.call("_on_bike_trick_landed", 0.8, 0.0, 0.9, false)
	var bonus := int(race.call("_airtime_reward_bonus"))
	var advertised_bonus_real := bonus == 140 and moments.size() == 2 and str(moments[0].get(&"label", "")).contains("AIRTIME 1.4s") and int(moments[0].get(&"points", 0)) == 168
	race.set("_race_clean_airtime_seconds", 100.0)
	race.set("_academy_clean_landings", 100)
	var capped_bonus := int(race.call("_airtime_reward_bonus"))
	var passed := variable_grip and advertised_bonus_real and capped_bonus == RaceController.AIRTIME_REWARD_CAP
	print("RACE FEATURE CONTRACT: variable_grip=%s surfaces=%s airtime_bonus=%d capped_bonus=%d moments=%d passed=%s" % [
		str(variable_grip), str(surfaces), bonus, capped_bonus, moments.size(), str(passed),
	])
	race.free()
	get_tree().quit(0 if passed else 1)
