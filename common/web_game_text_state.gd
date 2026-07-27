class_name WebGameTextState
## Builds the compact, JSON-safe state exposed to browser automation and
## assistive diagnostics. Presentation nodes remain authoritative; this is only
## a current-state projection and never feeds gameplay decisions.

const SCHEMA_VERSION := 4
const MAX_VISIBLE_RIDERS := 8


static func build(raw: Dictionary) -> Dictionary:
	var player := _dictionary(raw.get(&"player", {}))
	var session := _dictionary(raw.get(&"session", {}))
	var hud := _dictionary(raw.get(&"hud", {}))
	var garage := _dictionary(raw.get(&"garage", {}))
	var local_duel := _dictionary(raw.get(&"local_duel", {}))
	var custom_tour := _dictionary(raw.get(&"custom_tour", {}))
	var results := _dictionary(raw.get(&"results", {}))
	var save := _dictionary(raw.get(&"save", {}))
	var mode := StringName(raw.get(&"mode", &"LOADING"))
	var live_presentation := mode not in [
		&"START", &"LOADING", &"GARAGE", &"WORKSHOP", &"TRANSITION",
	]
	return {
		&"schema_version": SCHEMA_VERSION,
		&"coordinate_system": {
			&"units": "meters",
			&"origin": "active track world origin",
			&"axes": "+x right/east, +y up, -z forward at identity",
		},
		&"mode": String(mode),
		&"activity": str(raw.get(&"activity", "")),
		&"paused": bool(raw.get(&"paused", false)),
		&"transitioning": bool(raw.get(&"transitioning", false)),
		&"player": _player_projection(player),
		&"race": _race_projection(session),
		&"visible_riders": (
			_rider_projection(session.get(&"classification", []))
			if live_presentation else [] as Array[Dictionary]
		),
		&"coaching": {
			&"message": str(hud.get(&"message", "")) if live_presentation else "",
			&"racecraft": str(hud.get(&"racecraft", "")) if live_presentation else "",
			&"controls": str(hud.get(&"controls", "")) if live_presentation else "",
			&"line": str(hud.get(&"line", "")) if live_presentation else "",
			&"line_score": str(hud.get(&"line_score", "")) if live_presentation else "",
			&"landing": (
				_feedback_projection(raw.get(&"landing", {}))
				if live_presentation else _feedback_projection({})
			),
			&"balance": (
				_feedback_projection(raw.get(&"balance", {}))
				if live_presentation else _feedback_projection({})
			),
		},
		&"camera": _camera_projection(raw.get(&"camera", {})),
		&"graphics": _graphics_projection(raw.get(&"graphics", {})),
		&"captions": _caption_projection(raw.get(&"captions", {})),
		&"menu": _menu_projection(garage),
		&"local_duel": _local_duel_projection(local_duel),
		&"custom_tour": _custom_tour_projection(custom_tour),
		&"results": _results_projection(results),
		&"save": {
			&"state": str(save.get(&"state", "")),
			&"domain": str(save.get(&"domain", "")),
			&"critical_count": maxi(int(save.get(&"critical_count", 0)), 0),
		},
		&"input": {
			&"mode": str(raw.get(&"input_mode", "")),
			&"binding_revision": maxi(int(raw.get(&"binding_revision", 0)), 0),
		},
	}


static func _results_projection(source: Dictionary) -> Dictionary:
	var podium := _dictionary(source.get(&"podium", {}))
	var top_three: Array[Dictionary] = []
	var raw_top_three: Variant = podium.get(&"top_three", [])
	if raw_top_three is Array:
		for raw_entry: Variant in raw_top_three:
			if not raw_entry is Dictionary:
				continue
			var entry := raw_entry as Dictionary
			top_three.append({
				&"position": maxi(int(entry.get(&"position", 0)), 0),
				&"name": str(entry.get(&"display_name", "")),
				&"number": maxi(int(entry.get(&"number", 0)), 0),
				&"is_player": bool(entry.get(&"is_player", false)),
			})
	return {
		&"visible": bool(source.get(&"results_visible", false)),
		&"title": str(source.get(&"title", "")),
		&"summary": str(source.get(&"summary", "")),
		&"event_recap": str(source.get(&"event_recap", "")),
		&"podium": {
			&"visible": bool(podium.get(&"visible", false)),
			&"event_name": str(podium.get(&"event_name", "")),
			&"player_position": maxi(int(podium.get(&"player_position", 0)), 0),
			&"player_on_podium": bool(podium.get(&"player_on_podium", false)),
			&"compact": bool(podium.get(&"compact", false)),
			&"reduced_motion": bool(podium.get(&"reduced_motion", false)),
			&"rider_number": maxi(int(podium.get(&"rider_number", 0)), 0),
			&"body_type": str(podium.get(&"body_type", "")),
				&"jersey": str(podium.get(&"jersey", "")),
				&"livery": str(podium.get(&"livery", "")),
				&"team_palette": str(podium.get(&"team_palette", "STYLE")),
				&"decal_id": str(podium.get(&"decal_id", "CLEAN")),
				&"sponsor_id": str(podium.get(&"sponsor_id", "NONE")),
				&"sponsor_placement": str(podium.get(&"sponsor_placement", "SHROUDS")),
				&"top_three": top_three,
		},
	}


static func _player_projection(player: Dictionary) -> Dictionary:
	var transmission := _dictionary(player.get(&"transmission", {}))
	var controls := _dictionary(player.get(&"controls", {}))
	var contact := _dictionary(player.get(&"contact", {}))
	var condition := _dictionary(player.get(&"condition", {}))
	var cosmetics := _dictionary(player.get(&"cosmetics", {}))
	var equipment_wear := _dictionary(player.get(&"equipment_wear", {}))
	return {
		&"bike_id": str(player.get(&"bike_id", "")),
		&"rider_number": clampi(int(cosmetics.get(&"rider_number", 17)), 1, 999),
		&"body_type": str(cosmetics.get(&"body_type", "")),
		&"skin_tone": str(cosmetics.get(&"skin_tone", "")),
		&"voice": str(cosmetics.get(&"voice", "")),
		&"helmet": str(cosmetics.get(&"helmet", "")),
		&"goggles": str(cosmetics.get(&"goggles", "")),
		&"jersey": str(cosmetics.get(&"jersey", "")),
		&"pants": str(cosmetics.get(&"pants", "")),
		&"boots": str(cosmetics.get(&"boots", "")),
		&"gloves": str(cosmetics.get(&"gloves", "")),
		&"protection": str(cosmetics.get(&"protection", "")),
		&"accessory": str(cosmetics.get(&"accessory", "")),
			&"bike_livery": str(cosmetics.get(&"bike_livery", "")),
			&"team_palette": str(cosmetics.get(&"team_palette", "STYLE")),
			&"decal_id": str(cosmetics.get(&"decal_id", "CLEAN")),
			&"sponsor_id": str(cosmetics.get(&"sponsor_id", "NONE")),
			&"sponsor_placement": str(cosmetics.get(&"sponsor_placement", "SHROUDS")),
		&"equipment_wear": {
			&"status": str(equipment_wear.get(&"status", "CLEAN")),
			&"dry_dust": clampf(float(equipment_wear.get(&"dry_dust", 0.0)), 0.0, 1.0),
			&"mud": clampf(float(equipment_wear.get(&"mud", 0.0)), 0.0, 1.0),
			&"wetness": clampf(float(equipment_wear.get(&"wetness", 0.0)), 0.0, 1.0),
			&"crash_wear": clampf(float(equipment_wear.get(&"crash_wear", 0.0)), 0.0, 1.0),
		},
		&"test_ride": bool(player.get(&"test_ride", false)),
		&"position": _vector_projection(player.get(&"position", Vector3.ZERO)),
		&"velocity": _vector_projection(player.get(&"velocity", Vector3.ZERO)),
		&"forward": _vector_projection(player.get(&"forward", Vector3.FORWARD)),
		&"speed_mps": maxf(float(player.get(&"speed_mps", 0.0)), 0.0),
		&"grounded": bool(player.get(&"grounded", false)),
		&"surface": str(contact.get(&"surface", "")),
		&"front_slip": maxf(float(contact.get(&"front_slip", 0.0)), 0.0),
		&"rear_slip": maxf(float(contact.get(&"rear_slip", 0.0)), 0.0),
		&"flow": maxf(float(player.get(&"flow", 0.0)), 0.0),
		&"boosting": bool(player.get(&"boosting", false)),
		&"bike_condition_percent": clampi(
			int(condition.get(&"condition_percent", 100)), 0, 100
		),
		&"bike_condition_status": str(condition.get(&"status", "READY")),
		&"gear": maxi(int(transmission.get(&"gear", 1)), 1),
		&"transmission_mode": str(transmission.get(&"mode", "AUTOMATIC")),
		&"controls": {
			&"enabled": bool(controls.get(&"enabled", false)),
			&"throttle": clampf(float(controls.get(&"throttle", 0.0)), 0.0, 1.0),
			&"brake": clampf(float(controls.get(&"brake", 0.0)), 0.0, 1.0),
			&"steer": clampf(float(controls.get(&"steer", 0.0)), -1.0, 1.0),
			&"lean": clampf(float(controls.get(&"lean", 0.0)), -1.0, 1.0),
		},
	}


static func _race_projection(session: Dictionary) -> Dictionary:
	var integrity := _dictionary(session.get(&"integrity", {}))
	return {
		&"phase": str(session.get(&"phase", "")),
		&"event_id": str(session.get(&"event_id", "")),
		&"track_id": str(session.get(&"track_id", "")),
		&"format": str(session.get(&"format", "")),
		&"weather": str(session.get(&"weather", "")),
		&"surface": str(session.get(&"surface", "")),
		&"elapsed_seconds": maxf(float(session.get(&"elapsed_usec", 0)) / 1_000_000.0, 0.0),
		&"countdown_seconds": maxf(float(session.get(&"countdown", 0.0)), 0.0),
		&"lap": maxi(int(session.get(&"current_lap", 0)), 0),
		&"total_laps": maxi(int(session.get(&"total_laps", 0)), 0),
		&"checkpoint": maxi(int(session.get(&"current_checkpoint", 0)), 0),
		&"checkpoint_count": maxi(int(session.get(&"checkpoint_count", 0)), 0),
		&"position": maxi(int(session.get(&"position", 0)), 0),
		&"field_size": maxi(int(session.get(&"field_size", 0)), 0),
		&"gap_ahead_m": float(session.get(&"gap_ahead", -1.0)),
		&"gap_behind_m": float(session.get(&"gap_behind", -1.0)),
		&"flag": str(session.get(&"flag", "")),
		&"penalty_seconds": maxf(float(session.get(&"penalty_usec", 0)) / 1_000_000.0, 0.0),
		&"valid": bool(integrity.get(&"valid", true)),
		&"validity_reason": str(integrity.get(&"reason", integrity.get(&"validity_reason", ""))),
	}


static func _rider_projection(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not value is Array:
		return result
	for item: Variant in value:
		if not item is Dictionary:
			continue
		var rider := item as Dictionary
		if bool(rider.get(&"is_player", false)):
			continue
		result.append({
			&"position": maxi(int(rider.get(&"position", 0)), 0),
			&"name": str(rider.get(&"display_name", rider.get(&"rider_id", ""))),
			&"status": str(rider.get(&"status", "")),
			&"lap": maxi(int(rider.get(&"current_lap", 0)), 0),
			&"speed_mps": maxf(float(rider.get(&"speed_mps", 0.0)), 0.0),
			&"world_position": _vector_projection(
				rider.get(&"world_position", Vector3.ZERO)
			),
		})
		if result.size() >= MAX_VISIBLE_RIDERS:
			break
	return result


static func _feedback_projection(value: Variant) -> Dictionary:
	var source := _dictionary(value)
	var projection := _dictionary(source.get(&"projection", source))
	return {
		&"visible": bool(source.get(&"visible", projection.get(&"active", false))),
		&"state": str(projection.get(&"state", "")),
		&"text": str(source.get(&"text", projection.get(&"text", ""))),
		&"progress": clampf(float(
			source.get(
				&"progress",
				float(source.get(&"confidence", 0.0)) / 100.0
			)
		), 0.0, 1.0),
	}


static func _camera_projection(value: Variant) -> Dictionary:
	var camera := _dictionary(value)
	return {
		&"mode": str(camera.get(&"mode", "")),
		&"fov_degrees": maxf(float(camera.get(&"fov_degrees", 0.0)), 0.0),
	}


static func _graphics_projection(value: Variant) -> Dictionary:
	var graphics := _dictionary(value)
	return {
		&"preset": str(graphics.get(&"mode", "BALANCED")),
		&"render_scale_mode": str(graphics.get(&"render_scale_mode", "AUTO")),
		&"render_scale": clampf(float(graphics.get(&"viewport_render_scale", graphics.get(&"render_scale", 1.0))), 0.67, 1.0),
		&"shadow_quality": str(graphics.get(&"shadow_quality", "AUTO")),
		&"particle_density": str(graphics.get(&"particle_density", "AUTO")),
		&"particle_ratio": clampf(float(graphics.get(&"particle_ratio", 1.0)), 0.0, 1.0),
		&"weather_effects": str(graphics.get(&"weather_effects", "AUTO")),
		&"weather_particle_ratio": clampf(float(graphics.get(&"weather_particle_ratio", 1.0)), 0.0, 1.0),
		&"reduced_particles": bool(graphics.get(&"reduced_particles", false)),
		&"web_capped": bool(graphics.get(&"web_capped", false)),
	}


static func _caption_projection(value: Variant) -> Dictionary:
	var captions := _dictionary(value)
	return {
		&"detail": str(captions.get(&"detail", "IMPORTANT")),
		&"scale": clampf(float(captions.get(&"scale", 1.0)), 0.75, 1.75),
		&"style": str(captions.get(&"style", "STANDARD")),
		&"effective_high_contrast": bool(captions.get(&"effective_high_contrast", false)),
		&"visible": bool(captions.get(&"visible", false)),
		&"source": str(captions.get(&"source", "")),
		&"text": str(captions.get(&"text", "")),
		&"display_text": str(captions.get(&"display_text", "")),
		&"priority": clampi(int(captions.get(&"priority", 0)), 0, 2),
		&"repeat_count": clampi(int(captions.get(&"repeat_count", 1)), 1, 9),
	}


static func _menu_projection(garage: Dictionary) -> Dictionary:
	return {
		&"garage_open": bool(garage.get(&"open", false)),
		&"workshop_open": bool(garage.get(&"workshop_open", false)),
		&"event": str(garage.get(&"event", "")),
		&"setup": str(garage.get(&"setup", "")),
		&"status": str(garage.get(&"status", "")),
		&"workshop_category": str(garage.get(&"workshop_category", "")),
		&"workshop_item": str(garage.get(&"workshop_item", "")),
		&"workshop_action": str(garage.get(&"workshop_action", "")),
		&"workshop_status": str(garage.get(&"workshop_status", "")),
		&"rider_number": clampi(int(garage.get(&"rider_number", 17)), 1, 999),
		&"rider_number_draft": clampi(int(garage.get(&"rider_number_draft", 17)), 0, 999),
	}


static func _local_duel_projection(source: Dictionary) -> Dictionary:
	var participant := _dictionary(source.get(&"current_participant", {}))
	var standings: Array[Dictionary] = []
	var raw_standings: Variant = source.get(&"standings", [])
	if raw_standings is Array:
		for raw_entry: Variant in raw_standings:
			if not raw_entry is Dictionary:
				continue
			var entry := raw_entry as Dictionary
			standings.append({
				&"position": maxi(int(entry.get(&"position", 0)), 0),
				&"name": str(entry.get(&"display_name", "")),
				&"time_seconds": (
					maxf(float(entry.get(&"effective_time_usec", 0)) / 1_000_000.0, 0.0)
					if int(entry.get(&"time_usec", -1)) > 0 else -1.0
				),
				&"attempts_completed": maxi(int(entry.get(&"attempts_completed", 0)), 0),
			})
	return {
		&"configured": bool(source.get(&"configured", false)),
		&"active": bool(source.get(&"active", false)),
		&"completed": bool(source.get(&"completed", false)),
		&"event_id": str(source.get(&"event_id", "")),
		&"challenge_id": str(source.get(&"challenge_id", "")),
		&"current_rider": str(participant.get(&"display_name", "")),
		&"current_attempt": maxi(int(source.get(&"current_attempt", 0)), 0),
		&"attempts_per_rider": maxi(int(source.get(&"attempts_per_participant", 0)), 0),
		&"rider_count": maxi(int(source.get(&"participant_count", 0)), 0),
		&"standings": standings,
	}


static func _custom_tour_projection(source: Dictionary) -> Dictionary:
	var next_event_id := StringName(source.get(&"next_event_id", &""))
	var standings: Array[Dictionary] = []
	var raw_standings: Variant = source.get(&"standings", [])
	if raw_standings is Array:
		for raw_entry: Variant in raw_standings:
			if not raw_entry is Dictionary:
				continue
			var entry := raw_entry as Dictionary
			standings.append({
				&"position": maxi(int(entry.get(&"championship_position", 0)), 0),
				&"name": str(entry.get(&"display_name", "")),
				&"points": maxi(int(entry.get(&"points", 0)), 0),
				&"starts": maxi(int(entry.get(&"starts", 0)), 0),
			})
			if standings.size() >= 6:
				break
	var draft_events: Array[String] = []
	var raw_draft: Variant = source.get(&"draft_events", [])
	if raw_draft is Array or raw_draft is PackedStringArray:
		for raw_event: Variant in raw_draft:
			draft_events.append(str(raw_event))
	var champion := _dictionary(source.get(&"champion", {}))
	return {
		&"configured": bool(source.get(&"configured", false)),
		&"building": bool(source.get(&"building", false)),
		&"active": bool(source.get(&"active", false)),
		&"completed": bool(source.get(&"completed", false)),
		&"phase": str(source.get(&"phase", "")),
		&"round_count": maxi(int(source.get(&"round_count", 0)), 0),
		&"completed_rounds": maxi(int(source.get(&"completed_rounds", 0)), 0),
		&"current_round": maxi(int(source.get(&"current_round", 0)), 0),
		&"next_event_id": str(next_event_id),
		&"next_event_name": str(source.get(&"next_event_name", "")),
		&"draft_events": draft_events,
		&"standings": standings,
		&"champion": str(champion.get(&"display_name", "")),
	}


static func _vector_projection(value: Variant) -> Dictionary:
	if value is Vector3:
		var vector := value as Vector3
		return {
			&"x": snappedf(vector.x, 0.001),
			&"y": snappedf(vector.y, 0.001),
			&"z": snappedf(vector.z, 0.001),
		}
	if value is Dictionary:
		var dictionary := value as Dictionary
		return {
			&"x": snappedf(float(dictionary.get(&"x", 0.0)), 0.001),
			&"y": snappedf(float(dictionary.get(&"y", 0.0)), 0.001),
			&"z": snappedf(float(dictionary.get(&"z", 0.0)), 0.001),
		}
	return {&"x": 0.0, &"y": 0.0, &"z": 0.0}


static func _dictionary(value: Variant) -> Dictionary:
	return value as Dictionary if value is Dictionary else {}
