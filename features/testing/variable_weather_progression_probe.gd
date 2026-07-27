extends Node
## Cross-system contract for deterministic, gradual variable race conditions.

const POLICY := preload("res://features/environment/variable_weather_policy.gd")


func _ready() -> void:
	var failures: Array[String] = []
	var forecast := POLICY.forecast(&"VARIABLE", &"PACKED", 6)
	var weather: Array[StringName] = []
	var surfaces: Array[StringName] = []
	for entry: Dictionary in forecast:
		weather.append(StringName(entry.get(&"weather", &"")))
		surfaces.append(StringName(entry.get(&"surface", &"")))
	_check(
		weather == [&"CLEAR", &"WINDY", &"OVERCAST", &"WET", &"STORM", &"OVERCAST"],
		"Variable weather arc drifted",
		failures
	)
	_check(
		surfaces == [&"PACKED", &"LOOSE_DIRT", &"PACKED", &"WET", &"RUTTED", &"PACKED"],
		"Variable surface arc drifted",
		failures
	)
	var lap_four := POLICY.conditions_for_lap(&"VARIABLE", &"PACKED", 4, 6)
	_check(
		StringName(lap_four.get(&"weather", &"")) == &"WET"
			and StringName(lap_four.get(&"surface", &"")) == &"WET"
			and StringName(lap_four.get(&"next_weather", &"")) == &"STORM"
			and StringName(lap_four.get(&"next_surface", &"")) == &"RUTTED",
		"Lap-four rain and storm warning are not coherent",
		failures
	)
	var static_conditions := POLICY.conditions_for_lap(&"DUSK", &"LOOSE", 2, 4)
	_check(
		not bool(static_conditions.get(&"variable", true))
			and StringName(static_conditions.get(&"weather", &"")) == &"DUSK"
			and StringName(static_conditions.get(&"surface", &"")) == &"LOOSE",
		"Static events were changed by the variable policy",
		failures
	)

	var race := RaceController.new()
	add_child(race)
	await get_tree().process_frame
	var condition_events: Array[Dictionary] = []
	var moments: Array[String] = []
	race.conditions_changed.connect(func(snapshot: Dictionary) -> void:
		condition_events.append(snapshot.duplicate(true))
	)
	race.race_moment.connect(func(label: String, _points: int, _positive: bool) -> void:
		moments.append(label)
	)
	race.configure_session(RaceEventCatalog.get_session_config(&"MESA_ENDURANCE"))
	race.set("_current_lap", 4)
	race.call("_set_session_conditions", lap_four, true)
	var session := race.get_session_snapshot()
	var pack := race.get("_race_pack") as RacePack
	_check(
		StringName(session.get(&"weather", &"")) == &"WET"
			and StringName(session.get(&"surface", &"")) == &"WET"
			and StringName(pack.get("_active_weather")) == &"WET"
			and StringName(pack.get("_active_surface_modifier")) == &"WET",
		"Controller and opponent pack did not share effective wet conditions",
		failures
	)
	_check(
		condition_events.size() >= 2
			and moments.any(func(value: String) -> bool: return value.contains("CONDITIONS"))
			and moments.any(func(value: String) -> bool: return value.contains("FORECAST L5")),
		"Condition transition did not publish readable live feedback",
		failures
	)

	var atmosphere := AtmosphereDirector.new()
	add_child(atmosphere)
	await get_tree().process_frame
	atmosphere.configure_session(&"STORM", CourseCatalog.MESA_MX_ID)
	var storm_before := atmosphere.get_snapshot()
	atmosphere.call("_process", 0.10)
	var storm_after := atmosphere.get_snapshot()
	atmosphere.call("_process", 2.0)
	atmosphere.configure_session(&"OVERCAST", CourseCatalog.MESA_MX_ID)
	var drying_before := atmosphere.get_snapshot()
	atmosphere.call("_process", 0.10)
	var drying_after := atmosphere.get_snapshot()
	_check(
		bool(storm_before.get(&"rain_like", false))
			and is_equal_approx(float(storm_before.get(&"target_particle_intensity", 0.0)), 1.0)
			and float(storm_after.get(&"particle_intensity", 0.0))
				> float(storm_before.get(&"particle_intensity", 0.0))
			and float(storm_after.get(&"particle_intensity", 0.0)) < 1.0,
		"Storm precipitation did not ease in gradually",
		failures
	)
	_check(
		float(drying_before.get(&"target_particle_intensity", 0.0)) < 1.0
			and float(drying_after.get(&"particle_intensity", 0.0))
				< float(drying_before.get(&"particle_intensity", 0.0)),
		"Post-storm precipitation did not ease out gradually",
		failures
	)

	print("VARIABLE WEATHER PROGRESSION: forecast=%s conditions=%d moments=%s storm=%s drying=%s failures=%s" % [
		str(forecast),
		condition_events.size(),
		str(moments),
		str(storm_after),
		str(drying_after),
		str(failures),
	])
	get_tree().quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
