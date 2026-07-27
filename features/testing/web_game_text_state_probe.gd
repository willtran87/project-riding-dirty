extends Node
## Deterministic contract for the compact browser-readable game projection.

const TEXT_STATE := preload("res://common/web_game_text_state.gd")
const MAIN_SCRIPT := preload("res://scenes/main.gd")

var _failures: Array[String] = []


func _ready() -> void:
	var classification: Array[Dictionary] = [{
		&"is_player": true,
		&"position": 3,
		&"display_name": "YOU",
	}]
	for index: int in 10:
		classification.append({
			&"is_player": false,
			&"position": index + 1,
			&"display_name": "RIVAL %02d" % index,
			&"status": &"RACING",
			&"current_lap": 2,
			&"speed_mps": 15.0 + index,
			&"world_position": Vector3(index, 1.0, -index * 2.0),
		})
	var state := TEXT_STATE.build({
		&"mode": &"RACE",
		&"activity": &"CIRCUIT",
		&"paused": false,
		&"player": {
			&"bike_id": &"ROOK_450",
			&"test_ride": true,
			&"position": Vector3(12.3456, 1.2345, -45.6789),
			&"velocity": Vector3(1.0, -2.0, -18.0),
			&"forward": Vector3(0.0, 0.0, -1.0),
			&"speed_mps": 18.0,
			&"grounded": true,
			&"flow": 46.0,
			&"boosting": true,
			&"transmission": {&"mode": &"MANUAL", &"gear": 4},
			&"controls": {
				&"enabled": true,
				&"throttle": 0.82,
				&"brake": 0.15,
				&"steer": -0.35,
				&"lean": 0.42,
			},
			&"contact": {
				&"surface": &"LOAM",
				&"front_slip": 0.08,
				&"rear_slip": 0.31,
			},
			&"cosmetics": {
				&"body_type": "POWERFUL",
				&"skin_tone": "DEEP",
				&"voice": "GROUNDED",
				&"helmet": "NIGHT_BLACK",
				&"goggles": "CYAN_LENS",
				&"jersey": "NIGHT_CYAN",
				&"pants": "BLACK",
				&"boots": "BLACK",
				&"gloves": "CYAN",
				&"protection": "CHEST_PLATE",
				&"accessory": "HYDRATION_PACK",
				&"bike_livery": "NIGHT_RACE",
				&"rider_number": 128,
			},
			&"equipment_wear": {
				&"status": &"MUDDY",
				&"dry_dust": 0.18,
				&"mud": 0.42,
				&"wetness": 0.67,
				&"crash_wear": 0.24,
			},
		},
		&"session": {
			&"phase": &"RACING",
			&"event_id": &"CIRCUIT",
			&"track_id": &"QUARRY",
			&"format": &"SPRINT",
			&"weather": &"CLEAR",
			&"surface": &"DIRT",
			&"conditions": {
				&"variable": true,
				&"label": "DRY START",
				&"weather": &"CLEAR",
				&"surface": &"DIRT",
				&"next_lap": 3,
				&"next_weather": &"WINDY",
				&"next_surface": &"LOOSE_DIRT",
				&"next_label": "WIND RISING",
			},
			&"elapsed_usec": 12_500_000,
			&"current_lap": 2,
			&"total_laps": 3,
			&"current_checkpoint": 5,
			&"checkpoint_count": 18,
			&"position": 3,
			&"field_size": 12,
			&"gap_ahead": 4.25,
			&"gap_behind": 2.75,
			&"flag": &"GREEN",
			&"classification": classification,
			&"integrity": {&"valid": true, &"reason": &"VALID"},
		},
		&"hud": {
			&"message": "STOPPIE",
			&"racecraft": "RACECRAFT // FAST LINE",
			&"controls": "W THROTTLE",
			&"line": "CLEAN LANDING",
			&"line_score": "LINE 000677  x1.50",
		},
		&"landing": {
			&"visible": false,
			&"projection": {&"state": &"IDLE"},
		},
		&"balance": {
			&"visible": true,
			&"text": "BALANCE // STOPPIE // 100% // LEAN BACK",
			&"progress": 1.0,
			&"projection": {&"state": &"STOPPIE"},
		},
		&"camera": {&"mode": &"CHASE", &"fov_degrees": 86.0},
		&"graphics": {
			&"mode": &"QUALITY",
			&"render_scale_mode": &"90%",
			&"viewport_render_scale": 0.90,
			&"shadow_quality": &"SHORT",
			&"particle_density": &"MEDIUM",
			&"particle_ratio": 0.55,
			&"weather_effects": &"MINIMAL",
			&"weather_particle_ratio": 0.10,
			&"reduced_particles": false,
			&"web_capped": true,
		},
		&"captions": {
			&"detail": &"ALL",
			&"scale": 1.5,
			&"style": &"HIGH_CONTRAST",
			&"effective_high_contrast": true,
			&"visible": true,
			&"source": &"COMMENTARY",
			&"text": "OVERTAKE // P3",
			&"display_text": "[COMMENTARY]  OVERTAKE // P3",
			&"priority": 2,
			&"repeat_count": 1,
		},
		&"trackside_sponsor": {
			&"visible": true,
			&"activity_id": &"CIRCUIT",
			&"sponsor_id": &"DUSTLINE",
			&"sponsor_name": "DUSTLINE WORKS",
			&"identity": "RACE PRECISION",
			&"accent_hex": "FFB52D",
			&"landmark_count": 2,
			&"landmark_positions": [
				Vector3(-14.0, 4.2, 8.0),
				Vector3(16.0, 4.6, -1810.0),
			],
		},
		&"track_evolution": {
			&"active": true,
			&"track_id": &"QUARRY",
			&"surface": &"DIRT",
			&"weather": &"CLEAR",
			&"sampled_passes": 24,
			&"visible_grooves": 7,
			&"maximum_wear": 0.48,
			&"player_line": {
				&"state": &"COMPACTED",
				&"wear": 0.42,
				&"lane_index": 2,
				&"lane_center": 0.0,
				&"grip_multiplier": 1.023,
				&"drive_multiplier": 1.011,
				&"wet_policy": false,
			},
		},
		&"garage": {&"open": false},
		&"local_duel": {
			&"configured": true,
			&"active": true,
			&"completed": false,
			&"event_id": &"DAILY_CHALLENGE",
			&"challenge_id": &"DAILY-2026-207",
			&"current_participant": {&"display_name": "RIDER 2"},
			&"current_attempt": 1,
			&"attempts_per_participant": 2,
			&"participant_count": 2,
			&"standings": [{
				&"position": 1,
				&"display_name": "RIDER 1",
				&"time_usec": 91_250_000,
				&"effective_time_usec": 91_250_000,
				&"attempts_completed": 1,
			}],
		},
		&"custom_tour": {
			&"configured": true,
			&"active": true,
			&"phase": &"ACTIVE",
			&"round_count": 3,
			&"completed_rounds": 1,
			&"current_round": 2,
			&"next_event_id": &"PINE_ENDURO",
			&"next_event_name": "PINE RIDGE ENDURO",
			&"draft_events": [&"CIRCUIT", &"PINE_ENDURO", &"MESA_MX"],
			&"standings": [{
				&"championship_position": 1,
				&"display_name": "YOU",
				&"points": 25,
				&"starts": 1,
			}],
		},
		&"results": {
			&"results_visible": true,
			&"title": "RACE COMPLETE // SILVER",
			&"summary": "P2 / 12 // 3:01.200",
			&"event_recap": "TEAM // DUSTLINE WORKS // #128 NIGHT CYAN",
			&"podium": {
				&"visible": true,
				&"event_name": "QUARRY TRAIL",
				&"player_position": 2,
				&"player_on_podium": true,
				&"compact": false,
				&"reduced_motion": false,
				&"rider_number": 128,
				&"body_type": &"POWERFUL",
				&"jersey": "NIGHT_CYAN",
				&"livery": "NIGHT_RACE",
				&"top_three": [
					{&"position": 1, &"display_name": "ROOK", &"number": 11, &"is_player": false},
					{&"position": 2, &"display_name": "YOU", &"number": 128, &"is_player": true},
					{&"position": 3, &"display_name": "VALE", &"number": 27, &"is_player": false},
				],
			},
		},
		&"save": {&"state": &"SAVED", &"domain": &"CAREER", &"critical_count": 0},
		&"input_mode": &"KEYBOARD_MOUSE",
		&"binding_revision": 7,
	})
	var encoded := JSON.stringify(state)
	var decoded: Variant = JSON.parse_string(encoded)
	var player := state.get(&"player", {}) as Dictionary
	var race := state.get(&"race", {}) as Dictionary
	var coaching := state.get(&"coaching", {}) as Dictionary
	var balance := coaching.get(&"balance", {}) as Dictionary
	var visible_riders := state.get(&"visible_riders", []) as Array
	var local_duel := state.get(&"local_duel", {}) as Dictionary
	var custom_tour := state.get(&"custom_tour", {}) as Dictionary
	var results := state.get(&"results", {}) as Dictionary
	var podium := results.get(&"podium", {}) as Dictionary
	var trackside_sponsor := state.get(&"trackside_sponsor", {}) as Dictionary
	var track_evolution := state.get(&"track_evolution", {}) as Dictionary
	var visible_riders_include_player := false
	for rider_value: Variant in visible_riders:
		var rider := rider_value as Dictionary
		visible_riders_include_player = (
			visible_riders_include_player
			or str(rider.get(&"name", "")) == "YOU"
		)
	_check(
		int(state.get(&"schema_version", 0)) == 7
		and str(state.get(&"mode", "")) == "RACE"
		and not str((state.get(&"coordinate_system", {}) as Dictionary).get(&"axes", "")).is_empty(),
		"State identifies schema, mode, and world coordinates"
	)
	var projected_conditions := race.get(&"conditions", {}) as Dictionary
	_check(
		bool(projected_conditions.get(&"variable", false))
			and str(projected_conditions.get(&"next_weather", "")) == "WINDY"
			and str(projected_conditions.get(&"next_surface", "")) == "LOOSE_DIRT",
		"Browser race projection omitted the deterministic weather forecast"
	)
	_check(
		MAIN_SCRIPT.resolve_web_game_mode(
			false, true, false, false, true, false, false, false, &"CIRCUIT"
		) == &"SETTINGS"
			and MAIN_SCRIPT.resolve_web_game_mode(
				false, false, false, false, true, true, false, false, &"CIRCUIT"
			) == &"WORKSHOP",
		"Visible modal state does not take precedence over its Garage background"
	)
	var graphics := state.get(&"graphics", {}) as Dictionary
	_check(
		str(graphics.get(&"preset", "")) == "QUALITY"
			and str(graphics.get(&"render_scale_mode", "")) == "90%"
			and is_equal_approx(float(graphics.get(&"render_scale", 0.0)), 0.90)
			and str(graphics.get(&"shadow_quality", "")) == "SHORT"
			and is_equal_approx(float(graphics.get(&"particle_ratio", 0.0)), 0.55)
			and str(graphics.get(&"weather_effects", "")) == "MINIMAL"
			and is_equal_approx(float(graphics.get(&"weather_particle_ratio", 0.0)), 0.10)
			and bool(graphics.get(&"web_capped", false)),
		"Browser projection omitted the applied graphics contract"
	)
	var captions := state.get(&"captions", {}) as Dictionary
	_check(
		str(captions.get(&"detail", "")) == "ALL"
			and is_equal_approx(float(captions.get(&"scale", 0.0)), 1.5)
			and str(captions.get(&"style", "")) == "HIGH_CONTRAST"
			and bool(captions.get(&"effective_high_contrast", false))
			and bool(captions.get(&"visible", false))
			and str(captions.get(&"source", "")) == "COMMENTARY"
			and str(captions.get(&"text", "")) == "OVERTAKE // P3"
			and int(captions.get(&"priority", 0)) == 2,
		"Browser projection omitted the visible semantic audio caption"
	)
	_check(
		bool(trackside_sponsor.get(&"visible", false))
		and str(trackside_sponsor.get(&"activity_id", "")) == "CIRCUIT"
		and str(trackside_sponsor.get(&"sponsor_id", "")) == "DUSTLINE"
		and str(trackside_sponsor.get(&"sponsor_name", "")) == "DUSTLINE WORKS"
		and str(trackside_sponsor.get(&"identity", "")) == "RACE PRECISION"
		and str(trackside_sponsor.get(&"accent_hex", "")) == "FFB52D"
		and int(trackside_sponsor.get(&"landmark_count", 0)) == 2
		and (trackside_sponsor.get(&"landmark_positions", []) as Array).size() == 2,
		"Browser projection omitted the visible event-correct trackside sponsor"
	)
	var evolved_line := track_evolution.get(&"player_line", {}) as Dictionary
	_check(
		bool(track_evolution.get(&"active", false))
			and str(track_evolution.get(&"track_id", "")) == "QUARRY"
			and int(track_evolution.get(&"sampled_passes", 0)) == 24
			and int(track_evolution.get(&"visible_grooves", 0)) == 7
			and is_equal_approx(float(track_evolution.get(&"maximum_wear", 0.0)), 0.48)
			and str(evolved_line.get(&"state", "")) == "COMPACTED"
			and is_equal_approx(float(evolved_line.get(&"wear", 0.0)), 0.42)
			and float(evolved_line.get(&"grip_multiplier", 1.0)) > 1.0,
		"Browser projection omitted bounded session-local track evolution"
	)
	_check(
		bool(results.get(&"visible", false))
		and bool(podium.get(&"visible", false))
		and bool(podium.get(&"player_on_podium", false))
		and int(podium.get(&"rider_number", 0)) == 128
		and str(podium.get(&"body_type", "")) == "POWERFUL"
		and (podium.get(&"top_three", []) as Array).size() == 3
		and str(results.get(&"event_recap", "")).contains("DUSTLINE"),
		"Official results and personalized podium are browser-observable"
	)
	_check(
		is_equal_approx(float(player.get(&"speed_mps", 0.0)), 18.0)
		and str(player.get(&"bike_id", "")) == "ROOK_450"
		and bool(player.get(&"test_ride", false))
		and str(player.get(&"surface", "")) == "LOAM"
		and int(player.get(&"gear", 0)) == 4
		and int(player.get(&"rider_number", 0)) == 128
		and str(player.get(&"body_type", "")) == "POWERFUL"
		and str(player.get(&"skin_tone", "")) == "DEEP"
		and str(player.get(&"voice", "")) == "GROUNDED"
		and str(player.get(&"jersey", "")) == "NIGHT_CYAN"
		and str(player.get(&"goggles", "")) == "CYAN_LENS"
		and str(player.get(&"boots", "")) == "BLACK"
		and str(player.get(&"gloves", "")) == "CYAN"
		and str(player.get(&"protection", "")) == "CHEST_PLATE"
		and str(player.get(&"accessory", "")) == "HYDRATION_PACK"
		and str((player.get(&"equipment_wear", {}) as Dictionary).get(&"status", "")) == "MUDDY"
		and is_equal_approx(
			float((player.get(&"equipment_wear", {}) as Dictionary).get(&"wetness", 0.0)),
			0.67
		)
		and is_equal_approx(
			float((player.get(&"controls", {}) as Dictionary).get(&"steer", 0.0)),
			-0.35
		),
		"Player projection retains physical, transmission, surface, and signed input state"
	)
	_check(
		int(race.get(&"lap", 0)) == 2
		and int(race.get(&"checkpoint", 0)) == 5
		and is_equal_approx(float(race.get(&"elapsed_seconds", 0.0)), 12.5)
		and bool(race.get(&"valid", false)),
		"Race projection retains current progress, timing, gaps, and integrity"
	)
	_check(
		visible_riders.size() == TEXT_STATE.MAX_VISIBLE_RIDERS
		and str((visible_riders[0] as Dictionary).get(&"name", "")) == "RIVAL 00"
		and not visible_riders_include_player,
		"Visible rider projection excludes the player and enforces its bounded cap"
	)
	_check(
		bool(balance.get(&"visible", false))
		and str(balance.get(&"state", "")) == "STOPPIE"
		and str(balance.get(&"text", "")).contains("LEAN BACK")
		and is_equal_approx(float(balance.get(&"progress", 0.0)), 1.0),
		"Semantic coaching mirrors visible one-wheel feedback"
	)
	_check(
		str(coaching.get(&"line", "")) == "CLEAN LANDING"
		and str(coaching.get(&"line_score", "")).contains("x1.50"),
		"Semantic coaching mirrors the visible line moment and score"
	)
	_check(
		bool(local_duel.get(&"active", false))
		and str(local_duel.get(&"event_id", "")) == "DAILY_CHALLENGE"
		and str(local_duel.get(&"current_rider", "")) == "RIDER 2"
		and int(local_duel.get(&"attempts_per_rider", 0)) == 2
		and is_equal_approx(
			float(((local_duel.get(&"standings", []) as Array)[0] as Dictionary).get(&"time_seconds", 0.0)),
			91.25
		),
		"Browser projection exposes Local Duel identity, handoff, rules, and standings"
	)
	_check(
		bool(custom_tour.get(&"active", false))
		and int(custom_tour.get(&"current_round", 0)) == 2
		and str(custom_tour.get(&"next_event_id", "")) == "PINE_ENDURO"
		and (custom_tour.get(&"draft_events", []) as Array).size() == 3
		and int(
			((custom_tour.get(&"standings", []) as Array)[0] as Dictionary).get(&"points", 0)
		) == 25,
		"Browser projection exposes Custom Tour calendar progress and standings"
	)
	_check(
		decoded is Dictionary
		and (decoded as Dictionary).has("player")
		and not encoded.contains("Vector3")
		and encoded.length() < 7000,
		"Published state is concise, JSON-safe, and free of engine-only values"
	)
	WebPlatform.publish_game_text_state(state)
	_check(
		WebPlatform.get_game_text_state_snapshot() == state,
		"WebPlatform preserves the latest projection outside the browser runtime"
	)
	var bridge_script := WebPlatform.get_game_test_bridge_script()
	_check(
		bridge_script.contains("window.render_game_to_text")
		and bridge_script.contains("window.advanceTime")
		and bridge_script.contains("requestAnimationFrame")
		and bridge_script.contains("__ridingDirtyStateJSON"),
		"Inner runtime bridge owns text rendering and a non-blocking time fallback"
	)
	var garage_state := TEXT_STATE.build({
		&"mode": &"GARAGE",
		&"session": {&"classification": classification},
		&"hud": {
			&"message": "HIDDEN RACE MOMENT",
			&"racecraft": "HIDDEN RACECRAFT",
			&"controls": "HIDDEN RIDE CONTROLS",
			&"line": "HIDDEN LANDING",
			&"line_score": "HIDDEN SCORE",
		},
		&"balance": {
			&"visible": true,
			&"text": "HIDDEN STOPPIE",
			&"projection": {&"state": &"STOPPIE"},
		},
		&"garage": {
			&"open": true,
			&"workshop_open": true,
			&"event": &"CIRCUIT",
			&"setup": &"BALANCED",
			&"status": "ENTER RIDE",
			&"workshop_category": &"NUMBER",
			&"workshop_item": "APPLY RIDER NUMBER // #128",
			&"workshop_action": "ENTER APPLY #128",
			&"workshop_status": "RIDER NUMBER #128 APPLIED",
			&"rider_number": 128,
			&"rider_number_draft": 128,
		},
	})
	var garage_coaching := garage_state.get(&"coaching", {}) as Dictionary
	var garage_menu := garage_state.get(&"menu", {}) as Dictionary
	_check(
		(garage_state.get(&"visible_riders", []) as Array).is_empty()
		and str(garage_coaching.get(&"message", "")).is_empty()
		and str(garage_coaching.get(&"line", "")).is_empty()
		and not bool(
			(garage_coaching.get(&"balance", {}) as Dictionary).get(&"visible", true)
		)
		and str(garage_menu.get(&"status", "")) == "ENTER RIDE"
		and str(garage_menu.get(&"workshop_category", "")) == "NUMBER"
		and int(garage_menu.get(&"rider_number", 0)) == 128
		and int(garage_menu.get(&"rider_number_draft", 0)) == 128
		and str(garage_menu.get(&"workshop_status", "")).contains("#128 APPLIED"),
		"Garage projection suppresses hidden race entities and coaching"
	)
	print("WEB GAME TEXT STATE PROBE: bytes=%d riders=%d failures=%s" % [
		encoded.length(),
		visible_riders.size(),
		str(_failures),
	])
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  PASS: %s" % message)
		return
	_failures.append(message)
	push_error("WEB GAME TEXT STATE PROBE: %s" % message)
