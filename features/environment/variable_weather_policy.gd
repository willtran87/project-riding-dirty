extends RefCounted
class_name VariableWeatherPolicy
## Deterministic lap forecast shared by handling, AI, presentation, and telemetry.
##
## Variable conditions are authored as a readable six-lap storm arc. Keeping
## this policy pure makes replays and competitive signatures stable while every
## runtime consumer receives the same effective weather and surface.

const VARIABLE_WEATHER: Array[StringName] = [
	&"CLEAR",
	&"WINDY",
	&"OVERCAST",
	&"WET",
	&"STORM",
	&"OVERCAST",
]
const VARIABLE_SURFACES: Array[StringName] = [
	&"PACKED",
	&"LOOSE_DIRT",
	&"PACKED",
	&"WET",
	&"RUTTED",
	&"PACKED",
]
const VARIABLE_LABELS: Array[String] = [
	"DRY START",
	"WIND RISING",
	"CLOUD BUILD",
	"RAIN ARRIVES",
	"STORM PEAK",
	"TRACK DRYING",
]


static func conditions_for_lap(
	configured_weather: StringName,
	configured_surface: StringName,
	lap: int,
	total_laps: int
) -> Dictionary:
	var safe_lap := maxi(lap, 1)
	var safe_total := maxi(total_laps, 1)
	if configured_weather != &"VARIABLE":
		return {
			&"variable": false,
			&"lap": mini(safe_lap, safe_total),
			&"weather": configured_weather if not configured_weather.is_empty() else &"CLEAR",
			&"surface": configured_surface if not configured_surface.is_empty() else &"PACKED",
			&"label": String(configured_weather).replace("_", " "),
			&"next_lap": 0,
			&"next_weather": &"",
			&"next_surface": &"",
			&"next_label": "",
		}

	var index := (safe_lap - 1) % VARIABLE_WEATHER.size()
	var has_next := safe_lap < safe_total
	var next_index := safe_lap % VARIABLE_WEATHER.size()
	return {
		&"variable": true,
		&"lap": mini(safe_lap, safe_total),
		&"weather": VARIABLE_WEATHER[index],
		&"surface": VARIABLE_SURFACES[index],
		&"label": VARIABLE_LABELS[index],
		&"next_lap": safe_lap + 1 if has_next else 0,
		&"next_weather": VARIABLE_WEATHER[next_index] if has_next else &"",
		&"next_surface": VARIABLE_SURFACES[next_index] if has_next else &"",
		&"next_label": VARIABLE_LABELS[next_index] if has_next else "",
	}


static func forecast(
	configured_weather: StringName,
	configured_surface: StringName,
	total_laps: int
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for lap: int in range(1, maxi(total_laps, 1) + 1):
		var conditions := conditions_for_lap(
			configured_weather,
			configured_surface,
			lap,
			total_laps
		)
		result.append({
			&"lap": lap,
			&"weather": conditions[&"weather"],
			&"surface": conditions[&"surface"],
			&"label": conditions[&"label"],
		})
	return result
