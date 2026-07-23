extends RefCounted
class_name ChallengeSchedule
## UTC-based deterministic daily and weekly competitive challenges.

const DAY_SECONDS: int = 86_400
const WEEK_SECONDS: int = 604_800
const TRACKS: Array[String] = ["QUARRY", "PINE", "MESA_MX"]
const FORMATS: Array[String] = ["SPRINT", "CIRCUIT", "TIME_ATTACK", "RIVAL_DUEL"]
const CLOSED_CIRCUIT_TRACKS: Array[String] = ["MESA_MX"]
const BIKE_CLASSES: Array[String] = ["LIGHTWEIGHT", "MIDDLEWEIGHT", "OPEN"]
const WEATHER: Array[String] = ["CLEAR", "OVERCAST", "WINDY", "WET"]
const SURFACES: Array[String] = ["PACKED", "LOOSE", "RUTTED", "MIXED"]
const MODIFIERS: Array[String] = [
	"NO_RESETS",
	"CLEAN_RIDE",
	"AIRTIME_BONUS",
	"HOLESHOT_BONUS",
	"LIMITED_ASSISTS",
	"ZERO_PENALTIES",
	"FLOW_CHAIN",
]

var season_key: String = "RIDING_DIRTY_PRESEASON"


func daily(unix_time: int = -1, player_tier: int = 0) -> Dictionary:
	var now := unix_time if unix_time >= 0 else int(Time.get_unix_time_from_system())
	var day_index := floori(float(now) / float(DAY_SECONDS))
	var start_unix := day_index * DAY_SECONDS
	return _generate("DAILY", start_unix, DAY_SECONDS, player_tier)


func weekly(unix_time: int = -1, player_tier: int = 0) -> Dictionary:
	var now := unix_time if unix_time >= 0 else int(Time.get_unix_time_from_system())
	var day_index := floori(float(now) / float(DAY_SECONDS))
	# Unix epoch was a Thursday; +3 makes Monday the start of each bucket.
	var monday_day := day_index - posmod(day_index + 3, 7)
	var start_unix := monday_day * DAY_SECONDS
	return _generate("WEEKLY", start_unix, WEEK_SECONDS, player_tier)


func challenge_for_id(challenge_id: String, player_tier: int = 0) -> Dictionary:
	var normalized_id := challenge_id.strip_edges().to_upper()
	var parts := normalized_id.split("_")
	if parts.size() != 3 or not str(parts[1]).is_valid_int():
		return {}
	var kind := str(parts[0]).to_upper()
	var start_unix := int(parts[1])
	var generated: Dictionary = {}
	if kind == "DAILY":
		generated = _generate(kind, start_unix, DAY_SECONDS, player_tier)
	elif kind == "WEEKLY":
		generated = _generate(kind, start_unix, WEEK_SECONDS, player_tier)
	if str(generated.get("challenge_id", "")) != normalized_id:
		return {}
	return generated


func run_context(challenge: Dictionary) -> Dictionary:
	return {
		"event_id": str(challenge.get("format", "TIME_ATTACK")) + "_CHALLENGE",
		"track_id": challenge.get("track_id", "QUARRY"),
		"route_version": int(challenge.get("route_version", 1)),
		"format": challenge.get("format", "TIME_ATTACK"),
		"laps": int(challenge.get("laps", 1)),
		"bike_class": challenge.get("bike_class", "OPEN"),
		"difficulty": int(challenge.get("difficulty", 2)),
		"assist_mode": challenge.get("assist_mode", "STANDARD"),
		"setup_id": challenge.get("setup_id", "BALANCED"),
		"weather": challenge.get("weather", "CLEAR"),
		"surface": challenge.get("surface", "PACKED"),
		"challenge_id": challenge.get("challenge_id", ""),
		"modifiers": challenge.get("modifiers", []),
	}


static func is_track_format_compatible(track_id: String, format: String) -> bool:
	## Quarry and Pine are point-to-point routes. Repeating their checkpoint
	## state without a physical return route strands the player at the finish
	## while path-driven opponents wrap to the start. Only authored closed loops
	## may therefore be scheduled as multi-lap circuits.
	return format != "CIRCUIT" or track_id in CLOSED_CIRCUIT_TRACKS


static func compatible_formats(track_id: String) -> Array[String]:
	var output: Array[String] = []
	for format: String in FORMATS:
		if is_track_format_compatible(track_id, format):
			output.append(format)
	return output


func validate_submission(challenge: Dictionary, entry: Dictionary, now_unix: int = -1) -> Dictionary:
	var current_time := now_unix if now_unix >= 0 else int(Time.get_unix_time_from_system())
	if str(entry.get("challenge_id", "")) != str(challenge.get("challenge_id", "")):
		return {"ok": false, "error": "challenge_id_mismatch"}
	if current_time < int(challenge.get("starts_unix", 0)) or current_time >= int(challenge.get("ends_unix", 0)):
		return {"ok": false, "error": "challenge_outside_active_window"}
	var expected_signature := CompetitiveRunSignature.build(run_context(challenge))
	if str(entry.get("run_signature", "")) != expected_signature:
		return {"ok": false, "error": "run_signature_mismatch"}
	return LeaderboardProvider.validate_entry(entry)


func _generate(kind: String, start_unix: int, duration_seconds: int, player_tier: int) -> Dictionary:
	var seed_key := "%s|%s|%d" % [season_key, kind, start_unix]
	var seed_value := _stable_seed(seed_key)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	# Resolve the route before the format so the scheduler can never construct an
	# impossible multi-lap point-to-point event. Keep the selection deterministic
	# for a given challenge bucket and player tier.
	var track_id := TRACKS[rng.randi_range(0, TRACKS.size() - 1)]
	var format_pool := compatible_formats(track_id)
	var format := format_pool[rng.randi_range(0, format_pool.size() - 1)]
	var laps := 1
	if format == "CIRCUIT":
		laps = rng.randi_range(2, 5) if kind == "DAILY" else rng.randi_range(4, 8)
	var modifier_count := 1 if kind == "DAILY" else 3
	var selected_modifiers: Array[String] = []
	var modifier_pool := MODIFIERS.duplicate()
	for index in range(modifier_pool.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var held: String = modifier_pool[index]
		modifier_pool[index] = modifier_pool[swap_index]
		modifier_pool[swap_index] = held
	for index in mini(modifier_count, modifier_pool.size()):
		selected_modifiers.append(modifier_pool[index])
	var challenge_id := ("%s_%d_%08x" % [kind, start_unix, seed_value]).to_upper()
	var route_version := 19 if track_id == "QUARRY" else (4 if track_id == "PINE" else CourseCatalog.MESA_MX_ROUTE_VERSION)
	var challenge := {
		"version": 3,
		"challenge_id": challenge_id,
		"kind": kind,
		"starts_unix": start_unix,
		"ends_unix": start_unix + duration_seconds,
		"seed": seed_value,
		"track_id": track_id,
		"route_version": route_version,
		"format": format,
		"laps": laps,
		"bike_class": BIKE_CLASSES[rng.randi_range(0, BIKE_CLASSES.size() - 1)],
		"difficulty": clampi(player_tier + rng.randi_range(1, 3), 1, 4),
		"assist_mode": "LIMITED" if "LIMITED_ASSISTS" in selected_modifiers else "STANDARD",
		"setup_id": "BALANCED",
		"weather": WEATHER[rng.randi_range(0, WEATHER.size() - 1)],
		"surface": SURFACES[rng.randi_range(0, SURFACES.size() - 1)],
		"modifiers": selected_modifiers,
		"reward_multiplier": 1.0 + 0.12 * float(modifier_count) + 0.05 * float(clampi(player_tier, 0, 5)),
	}
	challenge["run_signature"] = CompetitiveRunSignature.build(run_context(challenge))
	challenge["competition_id"] = competition_id(challenge)
	return challenge


static func competition_id(challenge: Dictionary) -> StringName:
	## The public challenge ID identifies the UTC bucket, while the signature also
	## captures the tier-adjusted difficulty and every comparable rule. Combining
	## them prevents a rider who changes tier inside one bucket from inheriting an
	## exact PB, replay, leaderboard, or ghost from a different ruleset. Rotation
	## completion and first-clear progression intentionally remain bucket-scoped.
	var challenge_id := str(challenge.get("challenge_id", "")).strip_edges().to_upper()
	var signature := str(challenge.get("run_signature", "")).strip_edges()
	if challenge_id.is_empty() or not CompetitiveRunSignature.validate(signature):
		return &""
	for character: String in challenge_id:
		if character not in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_":
			return &""
	return StringName(("%s_%s" % [challenge_id, signature.right(32).to_upper()]).substr(0, 64))


func _stable_seed(value: String) -> int:
	var bytes := value.sha256_buffer()
	var result := 0
	for index in 4:
		result = (result << 8) | int(bytes[index])
	return result
