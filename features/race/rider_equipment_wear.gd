class_name RiderEquipmentWear
## Pure, deterministic authority for cosmetic dirt, rain, and crash wear.
##
## This state never changes grip, bike condition, scoring, or career data. It
## exists only to make the rider and bike visibly agree with their environment.

const DRY_DUST_RATE: float = 0.090
const MUD_RATE: float = 0.115
const RAIN_DUST_WASH_RATE: float = 0.24
const RAIN_MUD_WASH_RATE: float = 0.018
const NATURAL_DRY_RATE: float = 0.032


static func clean_state(weather: StringName = &"CLEAR") -> Dictionary:
	return _present({
		&"dry_dust": 0.0,
		&"mud": 0.0,
		&"wetness": 0.0,
		&"crash_wear": 0.0,
		&"surface": &"PACKED",
		&"weather": weather,
	})


static func advance(current: Dictionary, observation: Dictionary, delta: float) -> Dictionary:
	var safe_delta := clampf(delta, 0.0, 0.25)
	var next := _sanitize(current)
	var surface := _canonical_surface(observation.get(&"surface", next.get(&"surface", &"PACKED")))
	var weather := StringName(str(observation.get(&"weather", next.get(&"weather", &"CLEAR"))).to_upper())
	var precipitation := _precipitation(weather)
	if surface in [&"WET", &"MUD"]:
		precipitation = maxf(precipitation, 0.72)
	var wetness := float(next[&"wetness"])
	if precipitation > 0.0:
		wetness = move_toward(wetness, precipitation, safe_delta * (0.15 + precipitation * 0.18))
	else:
		wetness = move_toward(wetness, 0.0, safe_delta * NATURAL_DRY_RATE)

	var dry_dust := float(next[&"dry_dust"])
	var mud := float(next[&"mud"])
	if precipitation > 0.0:
		dry_dust = maxf(dry_dust - safe_delta * RAIN_DUST_WASH_RATE * precipitation, 0.0)
		mud = maxf(mud - safe_delta * RAIN_MUD_WASH_RATE * precipitation, 0.0)

	var grounded := bool(observation.get(&"grounded", false))
	var dust_amount := clampf(float(observation.get(&"dust_amount", 0.0)), 0.0, 1.5)
	var roost := clampf(float(observation.get(&"roost_intensity", 0.0)), 0.0, 1.5)
	var speed_ratio := clampf(float(observation.get(&"speed_mps", 0.0)) / 30.0, 0.0, 1.0)
	var exposure := clampf(maxf(dust_amount, roost) * 0.82 + speed_ratio * 0.18, 0.0, 1.5)
	if grounded and exposure > 0.0:
		var dust_potential := _dust_potential(surface)
		var mud_potential := _mud_potential(surface, wetness)
		dry_dust = minf(
			dry_dust
			+ safe_delta * DRY_DUST_RATE * dust_potential * exposure * (1.0 - wetness * 0.82),
			1.0
		)
		mud = minf(
			mud
			+ safe_delta * MUD_RATE * mud_potential * exposure * (0.38 + wetness * 0.78),
			1.0
		)

	next[&"dry_dust"] = dry_dust
	next[&"mud"] = mud
	next[&"wetness"] = wetness
	next[&"surface"] = surface
	next[&"weather"] = weather
	return _present(next)


static func add_crash(current: Dictionary, severity: float, surface: StringName) -> Dictionary:
	var next := _sanitize(current)
	var bounded := clampf(severity, 0.0, 1.0)
	next[&"crash_wear"] = minf(float(next[&"crash_wear"]) + 0.24 + bounded * 0.62, 1.0)
	if surface in [&"MUD", &"WET"]:
		next[&"mud"] = minf(float(next[&"mud"]) + 0.16 + bounded * 0.34, 1.0)
	else:
		next[&"dry_dust"] = minf(float(next[&"dry_dust"]) + 0.10 + bounded * 0.24, 1.0)
	next[&"surface"] = _canonical_surface(surface)
	return _present(next)


static func _sanitize(value: Dictionary) -> Dictionary:
	return {
		&"dry_dust": clampf(float(value.get(&"dry_dust", 0.0)), 0.0, 1.0),
		&"mud": clampf(float(value.get(&"mud", 0.0)), 0.0, 1.0),
		&"wetness": clampf(float(value.get(&"wetness", 0.0)), 0.0, 1.0),
		&"crash_wear": clampf(float(value.get(&"crash_wear", 0.0)), 0.0, 1.0),
		&"surface": _canonical_surface(value.get(&"surface", &"PACKED")),
		&"weather": StringName(str(value.get(&"weather", &"CLEAR")).to_upper()),
	}


static func _present(value: Dictionary) -> Dictionary:
	var output := _sanitize(value)
	var dry_dust := float(output[&"dry_dust"])
	var mud := float(output[&"mud"])
	var wetness := float(output[&"wetness"])
	var crash_wear := float(output[&"crash_wear"])
	var status: StringName = &"CLEAN"
	if crash_wear >= 0.46:
		status = &"CRASH_WORN"
	elif mud >= 0.58:
		status = &"MUD_CAKED"
	elif mud >= 0.16:
		status = &"MUDDY"
	elif dry_dust >= 0.56:
		status = &"DUST_COATED"
	elif dry_dust >= 0.14:
		status = &"DUSTY"
	elif wetness >= 0.54:
		status = &"RAIN_SOAKED"
	elif wetness >= 0.14:
		status = &"DAMP"
	output[&"status"] = status
	output[&"soil"] = clampf(maxf(dry_dust, mud), 0.0, 1.0)
	return output


static func _canonical_surface(value: Variant) -> StringName:
	var surface := StringName(str(value).strip_edges().to_upper())
	match surface:
		&"LOOSE", &"RUTTED":
			return &"LOOSE_DIRT"
		&"WET":
			return &"WET"
		&"DIRT", &"LOAM", &"LOOSE_DIRT", &"GRAVEL", &"MUD", &"SAND", &"GRASS", &"ROCK", &"PACKED":
			return surface
	return &"PACKED"


static func _precipitation(weather: StringName) -> float:
	match weather:
		&"STORM", &"WET":
			return 1.0
		&"MIST", &"OVERCAST":
			return 0.32
	return 0.0


static func _dust_potential(surface: StringName) -> float:
	match surface:
		&"SAND":
			return 1.15
		&"LOOSE_DIRT":
			return 1.0
		&"DIRT":
			return 0.72
		&"LOAM":
			return 0.58
		&"GRAVEL":
			return 0.52
		&"PACKED":
			return 0.34
		&"ROCK":
			return 0.14
		&"GRASS":
			return 0.10
	return 0.05


static func _mud_potential(surface: StringName, wetness: float) -> float:
	match surface:
		&"MUD":
			return 1.0
		&"WET":
			return 0.82
		&"DIRT", &"LOAM", &"LOOSE_DIRT":
			return smoothstep(0.20, 0.72, wetness) * 0.62
		&"SAND":
			return smoothstep(0.32, 0.82, wetness) * 0.24
		&"GRASS":
			return smoothstep(0.28, 0.78, wetness) * 0.12
	return 0.0
