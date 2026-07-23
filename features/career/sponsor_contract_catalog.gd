extends RefCounted
class_name SponsorContractCatalog
## Authored sponsor identities and fair relationship progression for ride contracts.
## Relationship rank is derived from durable contract identities, so existing
## profiles gain the arc without a new persistence field or lossy migration.

const SPONSORS: Dictionary[StringName, Dictionary] = {
	&"DUSTLINE": {
		&"display_name": "DUSTLINE WORKS",
		&"identity": "RACE PRECISION",
		&"voice": "PRECISION EARNS THE PATCH.",
		&"accent": Color("ffb52d"),
	},
	&"WILDBRUSH": {
		&"display_name": "WILDBRUSH OUTPOST",
		&"identity": "TERRAIN READING",
		&"voice": "READ THE GROUND. LEAVE NO TRACE.",
		&"accent": Color("9fc744"),
	},
	&"SUNDOWN": {
		&"display_name": "SUNDOWN STATIC",
		&"identity": "EXPRESSIVE LINES",
		&"voice": "MAKE THE LINE WORTH REPLAYING.",
		&"accent": Color("ff6f91"),
	},
}

const ACTIVITY_SPONSORS: Dictionary[StringName, StringName] = {
	&"CIRCUIT": &"DUSTLINE",
	&"MESA_PRACTICE": &"DUSTLINE",
	&"MESA_QUALIFYING": &"DUSTLINE",
	&"MESA_HEAT": &"DUSTLINE",
	&"MESA_LCQ": &"DUSTLINE",
	&"MESA_MX": &"DUSTLINE",
	&"MESA_ELIMINATION": &"DUSTLINE",
	&"MESA_RIVAL": &"DUSTLINE",
	&"QUARRY_HILLCLIMB": &"DUSTLINE",
	&"DAILY_CHALLENGE": &"DUSTLINE",
	&"WEEKLY_CHALLENGE": &"DUSTLINE",
	&"PINE_ENDURO": &"WILDBRUSH",
	&"PINE_WET": &"WILDBRUSH",
	&"MESA_ENDURANCE": &"WILDBRUSH",
	&"DISCOVERY": &"WILDBRUSH",
	&"FREESTYLE": &"SUNDOWN",
	&"MESA_RHYTHM": &"SUNDOWN",
}

const RELATIONSHIP_RANKS: Array[Dictionary] = [
	{&"title": "PROSPECT", &"threshold": 0, &"cash_reward": 350, &"reputation_reward": 35},
	{&"title": "SIGNED", &"threshold": 2, &"cash_reward": 425, &"reputation_reward": 40},
	{&"title": "FACTORY", &"threshold": 5, &"cash_reward": 500, &"reputation_reward": 50},
	{&"title": "ICON", &"threshold": 9, &"cash_reward": 600, &"reputation_reward": 60},
]


static func get_contract(activity: StringName, completed_contracts: Array) -> Dictionary:
	var sponsor_id := get_sponsor_id(activity)
	var sponsor: Dictionary = SPONSORS.get(sponsor_id, SPONSORS[&"DUSTLINE"])
	var relationship := get_relationship_snapshot(sponsor_id, completed_contracts)
	var rank_index := int(relationship.get(&"rank_index", 0))
	var kind := &"CLEAN"
	if activity in [&"FREESTYLE", &"MESA_RHYTHM"]:
		kind = &"CHAIN"
	elif activity in [&"DISCOVERY", &"PINE_ENDURO"]:
		kind = &"ROUTE"
	var target := _target_for_kind(kind, rank_index)
	var objective := _objective_for_kind(kind, target)
	var relationship_progress := _relationship_progress_label(relationship)
	var sponsor_name := str(sponsor.get(&"display_name", sponsor_id))
	var sponsor_voice := str(sponsor.get(&"voice", "EARN THE NEXT LINE."))
	var rank_title := str(relationship.get(&"rank_title", "PROSPECT"))
	return {
		&"sponsor_id": sponsor_id,
		&"sponsor_name": sponsor_name,
		&"identity": str(sponsor.get(&"identity", "RIDE PROGRAM")),
		&"voice": sponsor_voice,
		&"sponsor_accent": sponsor.get(&"accent", Color("ffb52d")) as Color,
		&"relationship": relationship,
		&"rank_index": rank_index,
		&"rank_title": rank_title,
		&"relationship_progress": relationship_progress,
		&"briefing_line": "%s  //  %s  //  %s  //  %s" % [
			sponsor_name, rank_title, relationship_progress, sponsor_voice,
		],
		&"kind": kind,
		&"target": target,
		&"objective": objective,
		&"cash_reward": int(relationship.get(&"cash_reward", 350)),
		&"reputation_reward": int(relationship.get(&"reputation_reward", 35)),
		&"title": "%s %s  //  %s" % [
			sponsor_name,
			rank_title,
			objective,
		],
	}


static func get_sponsor_id(activity: StringName) -> StringName:
	return StringName(ACTIVITY_SPONSORS.get(activity, &"DUSTLINE"))


static func get_relationship_snapshot(sponsor_id: StringName, completed_contracts: Array) -> Dictionary:
	var completions := _count_sponsor_contracts(sponsor_id, completed_contracts)
	var rank_index := 0
	for index: int in RELATIONSHIP_RANKS.size():
		if completions >= int(RELATIONSHIP_RANKS[index].get(&"threshold", 0)):
			rank_index = index
	var rank: Dictionary = RELATIONSHIP_RANKS[rank_index]
	var next_rank: Dictionary = {}
	if rank_index + 1 < RELATIONSHIP_RANKS.size():
		next_rank = RELATIONSHIP_RANKS[rank_index + 1]
	var next_threshold := int(next_rank.get(&"threshold", completions))
	var next_title := str(next_rank.get(&"title", "MAX RANK"))
	return {
		&"sponsor_id": sponsor_id,
		&"completions": completions,
		&"rank_index": rank_index,
		&"rank_title": str(rank.get(&"title", "PROSPECT")),
		&"cash_reward": int(rank.get(&"cash_reward", 350)),
		&"reputation_reward": int(rank.get(&"reputation_reward", 35)),
		&"next_rank_title": next_title,
		&"next_rank_threshold": next_threshold,
		&"remaining_to_next_rank": maxi(next_threshold - completions, 0) if not next_rank.is_empty() else 0,
		&"max_rank": next_rank.is_empty(),
	}


static func get_all_relationships(completed_contracts: Array) -> Array[Dictionary]:
	var relationships: Array[Dictionary] = []
	for sponsor_id: StringName in SPONSORS:
		var sponsor: Dictionary = SPONSORS[sponsor_id]
		var snapshot := get_relationship_snapshot(sponsor_id, completed_contracts)
		snapshot[&"sponsor_name"] = str(sponsor.get(&"display_name", sponsor_id))
		snapshot[&"voice"] = str(sponsor.get(&"voice", ""))
		relationships.append(snapshot)
	return relationships


static func _target_for_kind(kind: StringName, rank_index: int) -> int:
	match kind:
		&"CHAIN":
			return [4, 4, 5, 6][clampi(rank_index, 0, 3)]
		&"ROUTE":
			# Authored Discovery and Pine sessions each expose exactly two legal
			# route gates. Relationship rank must never advertise a third route.
			return 2
		_:
			return [2, 2, 3, 3][clampi(rank_index, 0, 3)]


static func _objective_for_kind(kind: StringName, target: int) -> String:
	match kind:
		&"CHAIN": return "CHAIN %d MOVES" % target
		&"ROUTE": return "FIND %d SECRET LINES" % target
		_: return "LAND %d CLEAN JUMPS" % target


static func _relationship_progress_label(relationship: Dictionary) -> String:
	if bool(relationship.get(&"max_rank", false)):
		return "MAX RELATIONSHIP"
	var remaining := maxi(int(relationship.get(&"remaining_to_next_rank", 0)), 0)
	return "%d RIDE%s TO %s" % [
		remaining,
		"" if remaining == 1 else "S",
		str(relationship.get(&"next_rank_title", "NEXT RANK")),
	]


static func _count_sponsor_contracts(sponsor_id: StringName, completed_contracts: Array) -> int:
	var count := 0
	for value: Variant in completed_contracts:
		var contract_id := str(value)
		for activity: StringName in ACTIVITY_SPONSORS:
			if StringName(ACTIVITY_SPONSORS[activity]) != sponsor_id:
				continue
			if contract_id.contains("_%s_" % String(activity)):
				count += 1
				break
	return count
