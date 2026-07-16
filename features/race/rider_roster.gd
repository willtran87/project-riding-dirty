extends RefCounted
class_name RiderRoster
## Persistent field identities and deterministic riding personalities.

const RIDERS: Array[Dictionary] = [
	{&"id": &"ROOK", &"name": "ROOK MERCER", &"number": 17, &"bike": Color("e5a126"), &"helmet": Color("f5d67b"), &"pace": 0.93, &"start": 0.88, &"corner": 0.91, &"jump": 0.90, &"aggression": 0.80, &"consistency": 0.90, &"recovery": 0.78, &"line": &"AGGRESSIVE", &"archetype": &"FRONT_RUNNER", &"signature_trait": "LATE-BRAKE PRESSURE", &"home_track": &"MESA_MX", &"pressure": 1.00, &"comeback": 0.82},
	{&"id": &"NOVA", &"name": "NOVA REYES", &"number": 24, &"bike": Color("2f7de1"), &"helmet": Color("f2f0df"), &"pace": 0.90, &"start": 0.94, &"corner": 0.88, &"jump": 0.82, &"aggression": 0.63, &"consistency": 0.94, &"recovery": 0.82, &"line": &"INSIDE", &"archetype": &"HOLESHOT_ACE", &"signature_trait": "GATE SNAP", &"home_track": &"MESA_MX", &"pressure": 0.88, &"comeback": 0.78},
	{&"id": &"BRICK", &"name": "BRICK DALTON", &"number": 88, &"bike": Color("e34c38"), &"helmet": Color("ffb52d"), &"pace": 0.86, &"start": 0.92, &"corner": 0.72, &"jump": 0.94, &"aggression": 0.92, &"consistency": 0.68, &"recovery": 0.72, &"line": &"OUTSIDE", &"archetype": &"BIG_AIR_BRAWLER", &"signature_trait": "SEND OR CASE", &"home_track": &"QUARRY", &"pressure": 0.90, &"comeback": 0.84},
	{&"id": &"SABLE", &"name": "SABLE KIM", &"number": 6, &"bike": Color("9b56d8"), &"helmet": Color("56d6ff"), &"pace": 0.88, &"start": 0.80, &"corner": 0.95, &"jump": 0.78, &"aggression": 0.54, &"consistency": 0.96, &"recovery": 0.90, &"line": &"SAFE", &"archetype": &"LINE_SURGEON", &"signature_trait": "INSIDE PRECISION", &"home_track": &"PINE", &"pressure": 0.76, &"comeback": 0.86},
	{&"id": &"TANK", &"name": "TANK MORROW", &"number": 51, &"bike": Color("55bd4a"), &"helmet": Color("e8edf2"), &"pace": 0.84, &"start": 0.96, &"corner": 0.70, &"jump": 0.88, &"aggression": 0.96, &"consistency": 0.66, &"recovery": 0.76, &"line": &"AGGRESSIVE", &"archetype": &"BLOCK_PASSER", &"signature_trait": "ELBOWS OUT", &"home_track": &"QUARRY", &"pressure": 0.92, &"comeback": 0.88},
	{&"id": &"EMBER", &"name": "EMBER VALE", &"number": 31, &"bike": Color("db3f82"), &"helmet": Color("f5d67b"), &"pace": 0.87, &"start": 0.83, &"corner": 0.87, &"jump": 0.93, &"aggression": 0.66, &"consistency": 0.84, &"recovery": 0.86, &"line": &"OUTSIDE", &"archetype": &"FLOW_RIDER", &"signature_trait": "OUTSIDE TRANSFERS", &"home_track": &"MESA_MX", &"pressure": 0.78, &"comeback": 0.90},
	{&"id": &"DUST", &"name": "DUSTY BELL", &"number": 72, &"bike": Color("23a7a1"), &"helmet": Color("f2f0df"), &"pace": 0.82, &"start": 0.76, &"corner": 0.84, &"jump": 0.76, &"aggression": 0.46, &"consistency": 0.92, &"recovery": 0.94, &"line": &"SAFE", &"archetype": &"ENDURO_VETERAN", &"signature_trait": "NO-MISTAKE PRESSURE", &"home_track": &"PINE", &"pressure": 0.65, &"comeback": 0.94},
	{&"id": &"AXLE", &"name": "AXLE HART", &"number": 43, &"bike": Color("e5d43c"), &"helmet": Color("ef5b43"), &"pace": 0.85, &"start": 0.86, &"corner": 0.78, &"jump": 0.91, &"aggression": 0.74, &"consistency": 0.75, &"recovery": 0.80, &"line": &"INSIDE", &"archetype": &"SCRUB_SPECIALIST", &"signature_trait": "LOW FAST FLIGHT", &"home_track": &"MESA_MX", &"pressure": 0.84, &"comeback": 0.91},
	{&"id": &"MICA", &"name": "MICA STONE", &"number": 9, &"bike": Color("5e64d7"), &"helmet": Color("ffb52d"), &"pace": 0.81, &"start": 0.79, &"corner": 0.82, &"jump": 0.83, &"aggression": 0.58, &"consistency": 0.88, &"recovery": 0.89, &"line": &"SAFE", &"archetype": &"COMEBACK_KID", &"signature_trait": "LATE-RACE CHARGE", &"home_track": &"PINE", &"pressure": 0.70, &"comeback": 1.00},
	{&"id": &"JETT", &"name": "JETT OKAFOR", &"number": 27, &"bike": Color("e36a2f"), &"helmet": Color("56d6ff"), &"pace": 0.89, &"start": 0.90, &"corner": 0.86, &"jump": 0.89, &"aggression": 0.84, &"consistency": 0.79, &"recovery": 0.74, &"line": &"AGGRESSIVE", &"archetype": &"RISK_TAKER", &"signature_trait": "LAST-LAP ATTACK", &"home_track": &"QUARRY", &"pressure": 0.95, &"comeback": 0.96},
	{&"id": &"LARK", &"name": "LARK FINCH", &"number": 64, &"bike": Color("45b8e8"), &"helmet": Color("f5d67b"), &"pace": 0.80, &"start": 0.74, &"corner": 0.89, &"jump": 0.72, &"aggression": 0.42, &"consistency": 0.95, &"recovery": 0.96, &"line": &"INSIDE", &"archetype": &"TECHNICIAN", &"signature_trait": "SAFE INSIDE EXIT", &"home_track": &"PINE", &"pressure": 0.55, &"comeback": 0.98},
]


static func get_field(count: int = 11, rival_only: bool = false) -> Array[Dictionary]:
	var field: Array[Dictionary] = []
	var requested := clampi(count, 0, RIDERS.size())
	if rival_only and requested > 0:
		field.append(RIDERS[0].duplicate(true))
		return field
	for index: int in requested:
		field.append(RIDERS[index].duplicate(true))
	return field


static func get_rider(rider_id: StringName) -> Dictionary:
	for rider: Dictionary in RIDERS:
		if StringName(rider.get(&"id", &"")) == rider_id:
			return rider.duplicate(true)
	return {}


static func get_session_field(
	count: int,
	rival_only: bool = false,
	entrant_ids: Array[StringName] = [],
	featured_ids: Array[StringName] = []
) -> Array[Dictionary]:
	var requested := clampi(count, 0, RIDERS.size())
	if rival_only:
		return get_field(requested, true)
	var profiles: Array[Dictionary] = []
	var included: Dictionary[StringName, bool] = {}
	# Managed-weekend entrants are authoritative. Standalone events use their
	# featured cast only when no saved entrant list exists.
	var preferred_ids: Array[StringName] = entrant_ids
	if preferred_ids.is_empty() and requested < RIDERS.size():
		preferred_ids = featured_ids
	for rider_id: StringName in preferred_ids:
		if rider_id == &"PLAYER" or included.has(rider_id) or profiles.size() >= requested:
			continue
		var profile := get_rider(rider_id)
		if profile.is_empty():
			continue
		profiles.append(profile)
		included[rider_id] = true
	for fallback: Dictionary in get_field(RIDERS.size()):
		if profiles.size() >= requested:
			break
		var fallback_id := StringName(fallback.get(&"id", &""))
		if included.has(fallback_id):
			continue
		profiles.append(fallback)
		included[fallback_id] = true
	return profiles
