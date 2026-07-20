extends RefCounted
class_name ProgressionPayoff
## Captures and diffs career availability around one run settlement.
##
## This service deliberately distinguishes access from ownership and affordability:
## reputation can make a bike or part available without silently purchasing it.

const EVENT_CATALOG_SCRIPT := preload("res://features/race/race_event_catalog.gd")
const BIKE_CATALOG_SCRIPT := preload("res://features/career/racing_bike_catalog.gd")
const ACADEMY_CATALOG_SCRIPT := preload("res://features/career/academy_lesson_catalog.gd")

const ACCESS_FIELDS: Array[StringName] = [
	&"event_access",
	&"bike_access",
	&"part_access",
	&"class_access",
	&"lesson_access",
]


static func capture(profile: Node) -> Dictionary:
	if profile == null:
		return {}
	var racer_reputation := maxi(int(profile.get(&"racer_reputation")), 0)
	var total_reputation := (
		maxi(int(profile.call(&"get_total_reputation")), 0)
		if profile.has_method(&"get_total_reputation") else racer_reputation
	)
	var bike_catalog: Variant = BIKE_CATALOG_SCRIPT.create_default()
	var locked_goals: Array[Dictionary] = []
	var event_access: Array[Dictionary] = []
	for event_id: StringName in EVENT_CATALOG_SCRIPT.EVENT_ORDER:
		if event_id in [&"ACADEMY", &"DAILY_CHALLENGE", &"WEEKLY_CHALLENGE"]:
			continue
		var event := EVENT_CATALOG_SCRIPT.get_event(event_id)
		if event.is_empty():
			continue
		var event_item := _access_item(
			&"EVENT", event_id, str(event.get(&"display_name", event_id)),
			int(event.get(&"unlock_rep", 0)), &"TOTAL"
		)
		if EVENT_CATALOG_SCRIPT.is_available_to_profile(event_id, profile):
			event_access.append(event_item)
		else:
			_add_reputation_goal(locked_goals, event_item, total_reputation)

	var bike_access: Array[Dictionary] = []
	for bike: Dictionary in bike_catalog.get_bikes(racer_reputation, true):
		var bike_item := _access_item(
			&"BIKE", StringName(bike.get(&"bike_id", &"")),
			str(bike.get(&"display_name", "BIKE")),
			int(bike.get(&"required_reputation", 0)), &"RACER",
			int(bike.get(&"price", 0))
		)
		if racer_reputation >= int(bike_item.get(&"required_reputation", 0)):
			bike_access.append(bike_item)
		else:
			_add_reputation_goal(locked_goals, bike_item, racer_reputation)

	var catalog_data: Dictionary = bike_catalog.to_dictionary()
	var part_definitions := _sorted_definitions(catalog_data.get(&"parts", {}) as Dictionary, &"part_id")
	var part_access: Array[Dictionary] = []
	for part: Dictionary in part_definitions:
		var part_item := _access_item(
			&"PART", StringName(part.get(&"part_id", &"")),
			str(part.get(&"display_name", "PART")),
			int(part.get(&"required_reputation", 0)), &"RACER",
			int(part.get(&"price", 0))
		)
		if racer_reputation >= int(part_item.get(&"required_reputation", 0)):
			part_access.append(part_item)
		else:
			_add_reputation_goal(locked_goals, part_item, racer_reputation)

	# Classes are tied to the active bike's homologation as well as reputation.
	# Announcing every reputation-qualified class would be false for an ineligible bike.
	var class_access: Array[Dictionary] = []
	var setup_snapshot: Dictionary = (
		profile.call(&"get_active_bike_setup_snapshot") as Dictionary
		if profile.has_method(&"get_active_bike_setup_snapshot") else {}
	)
	var active_build := setup_snapshot.get(&"build", {}) as Dictionary
	var active_bike_id := StringName(active_build.get(&"bike_id", profile.get(&"active_bike_id")))
	var active_stats := setup_snapshot.get(&"stats", {}) as Dictionary
	var eligible_now := _string_name_array(setup_snapshot.get(&"eligible_classes", []))
	var eligible_eventually: Array[StringName] = []
	if not active_bike_id.is_empty() and not active_stats.is_empty():
		eligible_eventually = bike_catalog.get_eligible_classes(active_bike_id, active_stats, 1_000_000)
	for class_id: StringName in eligible_eventually:
		var class_definition: Variant = bike_catalog.get_class_definition(class_id)
		var class_data: Dictionary = class_definition.to_dictionary()
		var class_item := _access_item(
			&"CLASS", class_id, str(class_data.get(&"display_name", class_id)),
			int(class_data.get(&"required_reputation", 0)), &"RACER"
		)
		if class_id in eligible_now:
			class_access.append(class_item)
		else:
			_add_reputation_goal(locked_goals, class_item, racer_reputation)

	var academy_catalog: Variant = ACADEMY_CATALOG_SCRIPT.create_default()
	var completed_lessons: Array[StringName] = (
		profile.call(&"get_completed_academy_lessons") as Array[StringName]
		if profile.has_method(&"get_completed_academy_lessons") else []
	)
	var lesson_access: Array[Dictionary] = []
	for lesson: Dictionary in academy_catalog.get_available_lessons(completed_lessons, racer_reputation):
		lesson_access.append(_access_item(
			&"ACADEMY_LESSON", StringName(lesson.get(&"lesson_id", &"")),
			str(lesson.get(&"display_name", "ACADEMY LESSON")),
			int(lesson.get(&"required_reputation", 0)), &"RACER"
		))

	var milestone_items: Array[Dictionary] = []
	var achievement_ids := _string_name_array(
		profile.call(&"get_achievement_ids") if profile.has_method(&"get_achievement_ids") else []
	)
	for achievement_id: StringName in achievement_ids:
		var definition: Dictionary = profile.call(&"get_achievement_definition", achievement_id) as Dictionary
		milestone_items.append({
			&"kind": &"ACHIEVEMENT",
			&"id": achievement_id,
			&"display_name": str(definition.get(&"title", achievement_id)),
			&"description": str(definition.get(&"description", "RIDER MILESTONE")),
		})
	var achievement_progress: Dictionary = (
		profile.call(&"get_achievement_progress_snapshot") as Dictionary
		if profile.has_method(&"get_achievement_progress_snapshot") else {}
	)

	return {
		&"cash": maxi(int(profile.get(&"cash")), 0),
		&"racer_reputation": racer_reputation,
		&"total_reputation": total_reputation,
		&"event_access": event_access,
		&"bike_access": bike_access,
		&"part_access": part_access,
		&"class_access": class_access,
		&"lesson_access": lesson_access,
		&"milestones": milestone_items,
		&"next_goal": _next_goal(locked_goals, achievement_progress),
	}


static func diff(before: Dictionary, after: Dictionary) -> Dictionary:
	if after.is_empty():
		return {}
	var unlocks: Array[Dictionary] = []
	for field: StringName in ACCESS_FIELDS:
		var prior_ids := _item_id_set(before.get(field, []))
		for item: Dictionary in _dictionary_array(after.get(field, [])):
			if not prior_ids.has(StringName(item.get(&"id", &""))):
				unlocks.append(item.duplicate(true))
	var prior_milestones := _item_id_set(before.get(&"milestones", []))
	var new_milestones: Array[Dictionary] = []
	for milestone: Dictionary in _dictionary_array(after.get(&"milestones", [])):
		if not prior_milestones.has(StringName(milestone.get(&"id", &""))):
			new_milestones.append(milestone.duplicate(true))
	var cash_before := maxi(int(before.get(&"cash", after.get(&"cash", 0))), 0)
	var cash_after := maxi(int(after.get(&"cash", 0)), 0)
	var racer_reputation_before := maxi(int(before.get(&"racer_reputation", after.get(&"racer_reputation", 0))), 0)
	var racer_reputation_after := maxi(int(after.get(&"racer_reputation", 0)), 0)
	var total_reputation_before := maxi(int(before.get(&"total_reputation", after.get(&"total_reputation", 0))), 0)
	var total_reputation_after := maxi(int(after.get(&"total_reputation", 0)), 0)
	var changed := (
		cash_after != cash_before
		or racer_reputation_after != racer_reputation_before
		or total_reputation_after != total_reputation_before
		or not unlocks.is_empty()
		or not new_milestones.is_empty()
	)
	return {
		&"cash_before": cash_before,
		&"cash_after": cash_after,
		&"racer_reputation_before": racer_reputation_before,
		&"racer_reputation_after": racer_reputation_after,
		&"total_reputation_before": total_reputation_before,
		&"total_reputation_after": total_reputation_after,
		&"unlocks": unlocks,
		&"milestones": new_milestones,
		&"next_goal": (after.get(&"next_goal", {}) as Dictionary).duplicate(true),
		&"changed": changed,
	}


static func resolve_run(
	before: Dictionary,
	pre_settlement: Dictionary,
	after: Dictionary,
	settlement_accepted: bool
) -> Dictionary:
	## A sponsor contract can settle while the bike is still on course. If the
	## final classification is rejected, retain only those already-authoritative
	## run earnings and exclude every mutation caused by result settlement.
	var trusted_after := after if settlement_accepted else pre_settlement
	if trusted_after.is_empty():
		trusted_after = before
	var payoff := diff(before, trusted_after)
	payoff[&"settlement_accepted"] = settlement_accepted
	payoff[&"run_earnings"] = has_authoritative_delta(payoff)
	return payoff


static func has_authoritative_delta(payoff: Dictionary) -> bool:
	return (
		int(payoff.get(&"cash_after", 0)) != int(payoff.get(&"cash_before", 0))
		or int(payoff.get(&"racer_reputation_after", 0)) != int(payoff.get(&"racer_reputation_before", 0))
		or int(payoff.get(&"total_reputation_after", 0)) != int(payoff.get(&"total_reputation_before", 0))
		or not _dictionary_array(payoff.get(&"unlocks", [])).is_empty()
		or not _dictionary_array(payoff.get(&"milestones", [])).is_empty()
	)


static func suppress_awards(payoff: Dictionary) -> Dictionary:
	var sanitized := payoff.duplicate(true)
	sanitized[&"unlocks"] = []
	sanitized[&"milestones"] = []
	sanitized[&"changed"] = false
	return sanitized


static func _access_item(
	kind: StringName,
	id: StringName,
	display_name: String,
	required_reputation: int,
	rep_scope: StringName,
	price: int = 0
) -> Dictionary:
	return {
		&"kind": kind,
		&"id": id,
		&"display_name": display_name.strip_edges().to_upper(),
		&"required_reputation": maxi(required_reputation, 0),
		&"reputation_scope": rep_scope,
		&"price": maxi(price, 0),
	}


static func _add_reputation_goal(goals: Array[Dictionary], item: Dictionary, current: int) -> void:
	var target := maxi(int(item.get(&"required_reputation", 0)), 0)
	if target <= current:
		return
	var goal := item.duplicate(true)
	goal[&"remaining"] = target - current
	goals.append(goal)


static func _next_goal(locked_goals: Array[Dictionary], progress: Dictionary) -> Dictionary:
	if not locked_goals.is_empty():
		locked_goals.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
			var first_remaining := int(first.get(&"remaining", 0))
			var second_remaining := int(second.get(&"remaining", 0))
			if first_remaining != second_remaining:
				return first_remaining < second_remaining
			var first_priority := _kind_priority(StringName(first.get(&"kind", &"")))
			var second_priority := _kind_priority(StringName(second.get(&"kind", &"")))
			if first_priority != second_priority:
				return first_priority < second_priority
			return str(first.get(&"display_name", "")) < str(second.get(&"display_name", ""))
		)
		var next_unlock: Dictionary = locked_goals.front().duplicate(true)
		next_unlock[&"goal_type"] = &"UNLOCK"
		return next_unlock
	var next_milestone := progress.get(&"next", {}) as Dictionary
	if not next_milestone.is_empty():
		return {
			&"goal_type": &"MILESTONE",
			&"kind": &"ACHIEVEMENT",
			&"id": StringName(next_milestone.get(&"achievement_id", &"")),
			&"display_name": str(next_milestone.get(&"title", "RIDER MILESTONE")).to_upper(),
			&"description": str(next_milestone.get(&"description", "KEEP RIDING")),
			&"current": int(next_milestone.get(&"current", 0)),
			&"target": maxi(int(next_milestone.get(&"target", 1)), 1),
		}
	return {&"goal_type": &"COMPLETE", &"display_name": "ALL CAREER MILESTONES COMPLETE"}


static func _kind_priority(kind: StringName) -> int:
	match kind:
		&"EVENT": return 0
		&"BIKE": return 1
		&"PART": return 2
		&"CLASS": return 3
		_: return 4


static func _sorted_definitions(source: Dictionary, id_key: StringName) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for value: Variant in source.values():
		if value is Dictionary:
			output.append((value as Dictionary).duplicate(true))
	output.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		var first_requirement := int(first.get(&"required_reputation", 0))
		var second_requirement := int(second.get(&"required_reputation", 0))
		if first_requirement != second_requirement:
			return first_requirement < second_requirement
		return str(first.get(id_key, "")) < str(second.get(id_key, ""))
	)
	return output


static func _item_id_set(raw: Variant) -> Dictionary:
	var output: Dictionary = {}
	for item: Dictionary in _dictionary_array(raw):
		var item_id := StringName(item.get(&"id", &""))
		if not item_id.is_empty():
			output[item_id] = true
	return output


static func _dictionary_array(raw: Variant) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	if raw is Array:
		for value: Variant in raw:
			if value is Dictionary:
				output.append((value as Dictionary).duplicate(true))
	return output


static func _string_name_array(raw: Variant) -> Array[StringName]:
	var output: Array[StringName] = []
	if raw is Array or raw is PackedStringArray:
		for value: Variant in raw:
			var item := StringName(value)
			if not item.is_empty() and not output.has(item):
				output.append(item)
	return output
