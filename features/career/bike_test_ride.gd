extends RefCounted
class_name BikeTestRide
## Non-persistent stock-bike preview policy shared by Workshop, Main, and probes.

const ACTIVITY_ID: StringName = &"TEST_RIDE"
const TRACK_ID: StringName = &"QUARRY"
const BIKE_BUILD_SCRIPT := preload("res://features/career/racing_bike_build.gd")


static func create_stock_build(
	bike_id: StringName,
	catalog: Variant,
	setup: StringName = &"BALANCED"
) -> Dictionary:
	if bike_id.is_empty() or catalog == null or catalog.get_bike(bike_id).is_empty():
		return {}
	var build: Variant = BIKE_BUILD_SCRIPT.new()
	build.bike_id = bike_id
	build.condition = 1.0
	var stats: Dictionary = build.calculate_stats(catalog)
	if stats.is_empty():
		return {}
	return {
		&"bike_id": bike_id,
		&"setup": setup,
		&"build": build.to_dictionary(),
		&"stats": stats,
		&"eligible_classes": build.eligible_classes(catalog, 0),
		&"selected_class": &"OPEN",
		&"signature": "TEST_RIDE|%s|%s|STOCK" % [String(bike_id), String(setup)],
		&"runtime": BIKE_BUILD_SCRIPT.runtime_projection(
			setup, stats, 100, (build.to_dictionary().get(&"tune", {}) as Dictionary)
		),
	}


static func create_session(bike_id: StringName, display_name: String) -> RaceSessionConfig:
	var safe_name := display_name.strip_edges()
	if safe_name.is_empty():
		safe_name = String(bike_id).replace("_", " ")
	return RaceSessionConfig.from_dictionary({
		&"event_id": ACTIVITY_ID,
		&"track_id": TRACK_ID,
		&"display_name": "TEST RIDE  //  %s" % safe_name.to_upper(),
		&"format": ACTIVITY_ID,
		&"session_type": &"PRACTICE",
		&"laps": 1,
		&"opponent_count": 0,
		&"difficulty": 1,
		&"bike_class": &"OPEN",
		&"weather": &"CLEAR",
		&"surface_modifier": &"PACKED",
		&"staging_seconds": 0.7,
		&"countdown_seconds": 1.8,
		&"finish_grace_seconds": 0.0,
		&"rules": {
			&"test_ride": true,
			&"test_bike_id": bike_id,
			&"record_eligible": false,
			&"ghost_enabled": false,
			&"reward_multiplier": 0.0,
		},
	})


static func sanitize_result(source: Dictionary, bike_id: StringName) -> Dictionary:
	var result := source.duplicate(true)
	result[&"event_id"] = ACTIVITY_ID
	result[&"format"] = ACTIVITY_ID
	result[&"session_type"] = &"PRACTICE"
	result[&"test_ride"] = true
	result[&"test_bike_id"] = bike_id
	result[&"medal"] = &"NO_AWARD"
	result[&"is_new_best"] = false
	result[&"championship_points"] = 0
	result[&"rewards"] = {
		&"cash": 0,
		&"reputation": 0,
		&"credited_cash": 0,
		&"credited_reputation": 0,
	}
	result[&"career_payoff"] = {
		&"accepted": false,
		&"duplicate": false,
		&"durable": true,
		&"reason": &"TEST_RIDE",
		&"valid": bool(result.get(&"valid", true)),
		&"status": &"PRACTICE",
		&"rewards_granted": {&"cash": 0, &"reputation": 0},
	}
	result[&"next_event_id"] = &""
	result[&"next_event_name"] = "RETURN TO WORKSHOP"
	return result
