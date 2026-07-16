extends Node
## Confirms that every production activity receives an authoritative briefing.

const TRANSITION_SCENE := preload("res://features/tour/district_transition.tscn")


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
	var passed := failures.is_empty()
	print("TRANSITION CATALOG PROBE: activities=%d passed=%s failures=%s" % [
		RaceEventCatalog.EVENT_ORDER.size(), passed, ", ".join(failures),
	])
	transition.queue_free()
	get_tree().quit(0 if passed else 1)
