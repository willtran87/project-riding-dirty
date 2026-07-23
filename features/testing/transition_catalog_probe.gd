extends Node
## Confirms that every production activity receives an authoritative briefing.

const TRANSITION_SCENE := preload("res://features/tour/district_transition.tscn")
const SPONSOR_CONTRACT_CATALOG := preload("res://features/career/sponsor_contract_catalog.gd")


func _ready() -> void:
	var transition := TRANSITION_SCENE.instantiate() as DistrictTransition
	add_child(transition)
	var failures := PackedStringArray()
	for activity: StringName in RaceEventCatalog.EVENT_ORDER:
		var card := transition.get_briefing_snapshot(activity)
		var event := RaceEventCatalog.get_event(activity)
		if str(card.get(&"title", "")) != str(event.get(&"display_name", "")):
			failures.append("%s title" % String(activity))
		if StringName(card.get(&"event_id", &"")) != activity:
			failures.append("%s event id" % String(activity))
		if RaceEventCatalog.is_race_event(activity):
			var session := RaceEventCatalog.get_session_config(activity)
			if StringName(card.get(&"track_id", &"")) != session.track_id:
				failures.append("%s track" % String(activity))
			if StringName(card.get(&"format", &"")) != session.format:
				failures.append("%s format" % String(activity))
			if int(card.get(&"laps", 0)) != session.laps:
				failures.append("%s laps" % String(activity))
			if StringName(card.get(&"weather", &"")) != session.weather:
				failures.append("%s weather" % String(activity))
			if not str(card.get(&"route", "")).contains(String(session.format).replace("_", " ")):
				failures.append("%s route format" % String(activity))
			if not str(card.get(&"target", "")).contains(":"):
				failures.append("%s target" % String(activity))
		if str(card.get(&"description", "")).is_empty() or str(card.get(&"kicker", "")).is_empty():
			failures.append("%s objective" % String(activity))
		if activity == &"ACADEMY":
			if bool(card.get(&"sponsor_visible", true)) or not str(card.get(&"sponsor_text", "")).is_empty():
				failures.append("ACADEMY sponsor isolation")
		else:
			var expected_sponsor := SPONSOR_CONTRACT_CATALOG.get_contract(
				activity, Profile.completed_contracts
			)
			var sponsor := card.get(&"sponsor", {}) as Dictionary
			var sponsor_text := str(card.get(&"sponsor_text", ""))
			if (
				not bool(card.get(&"sponsor_visible", false))
				or StringName(sponsor.get(&"sponsor_id", &"")) != StringName(expected_sponsor.get(&"sponsor_id", &""))
				or not sponsor_text.contains(str(expected_sponsor.get(&"sponsor_name", "")))
				or not sponsor_text.contains(str(expected_sponsor.get(&"rank_title", "")))
				or not sponsor_text.contains(str(expected_sponsor.get(&"relationship_progress", "")))
				or not sponsor_text.contains(str(expected_sponsor.get(&"voice", "")))
			):
				failures.append("%s sponsor briefing" % String(activity))
	var dustline := transition.get_briefing_snapshot(&"CIRCUIT")
	var wildbrush := transition.get_briefing_snapshot(&"PINE_ENDURO")
	var sundown := transition.get_briefing_snapshot(&"FREESTYLE")
	var sponsor_accents := [
		dustline.get(&"sponsor_accent", Color.TRANSPARENT),
		wildbrush.get(&"sponsor_accent", Color.TRANSPARENT),
		sundown.get(&"sponsor_accent", Color.TRANSPARENT),
	]
	if sponsor_accents[0] == sponsor_accents[1] or sponsor_accents[0] == sponsor_accents[2] or sponsor_accents[1] == sponsor_accents[2]:
		failures.append("sponsor accents")
	var passed := failures.is_empty()
	print("TRANSITION CATALOG PROBE: activities=%d passed=%s failures=%s" % [
		RaceEventCatalog.EVENT_ORDER.size(), passed, ", ".join(failures),
	])
	transition.queue_free()
	get_tree().quit(0 if passed else 1)
