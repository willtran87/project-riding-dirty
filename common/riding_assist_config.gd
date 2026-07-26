extends RefCounted
class_name RidingAssistConfig
## One deterministic authority for player-owned riding-assist presets and channels.

const CHANNELS: Array[StringName] = [
	&"steering",
	&"braking",
	&"landing",
	&"traction",
	&"balance",
]
const CHANNEL_LABELS: Dictionary = {
	&"steering": "STEERING",
	&"braking": "BRAKING",
	&"landing": "LANDING",
	&"traction": "TRACTION",
	&"balance": "RIDER BALANCE",
}
const PRESET_ORDER: Array[StringName] = [&"ASSISTED", &"SPORT", &"PRO"]
const PRESETS: Dictionary = {
	&"ASSISTED": {
		&"steering": 0.78,
		&"braking": 0.78,
		&"landing": 0.84,
		&"traction": 0.78,
		&"balance": 0.78,
	},
	&"SPORT": {
		&"steering": 0.45,
		&"braking": 0.45,
		&"landing": 0.45,
		&"traction": 0.45,
		&"balance": 0.45,
	},
	&"PRO": {
		&"steering": 0.12,
		&"braking": 0.12,
		&"landing": 0.12,
		&"traction": 0.12,
		&"balance": 0.12,
	},
}


static func preset(mode: StringName) -> Dictionary:
	var canonical := mode if PRESETS.has(mode) else &"SPORT"
	return (PRESETS[canonical] as Dictionary).duplicate(true)


static func sanitize(raw: Variant, fallback_mode: StringName = &"SPORT") -> Dictionary:
	var source := raw as Dictionary if raw is Dictionary else {}
	var fallback := preset(fallback_mode)
	var output: Dictionary = {}
	for channel: StringName in CHANNELS:
		var raw_value: Variant = source.get(channel, source.get(String(channel), fallback[channel]))
		var value := clampf(float(raw_value), 0.0, 1.0)
		# Persist exact hundredths so signatures, Web JSON, and desktop ConfigFile
		# round-trip through one stable competitive contract.
		output[channel] = snappedf(value, 0.01)
	return output


static func matching_preset(configuration: Variant) -> StringName:
	var normalized := sanitize(configuration)
	for mode: StringName in PRESET_ORDER:
		var candidate := preset(mode)
		var matches := true
		for channel: StringName in CHANNELS:
			if not is_equal_approx(float(normalized[channel]), float(candidate[channel])):
				matches = false
				break
		if matches:
			return mode
	return &"CUSTOM"


static func signature(mode: StringName, configuration: Variant) -> String:
	var normalized := sanitize(configuration, mode)
	var matched := matching_preset(normalized)
	if mode != &"CUSTOM" and matched == mode:
		return String(mode)
	return "CUSTOM_S%03d_B%03d_L%03d_T%03d_R%03d" % [
		roundi(float(normalized[&"steering"]) * 100.0),
		roundi(float(normalized[&"braking"]) * 100.0),
		roundi(float(normalized[&"landing"]) * 100.0),
		roundi(float(normalized[&"traction"]) * 100.0),
		roundi(float(normalized[&"balance"]) * 100.0),
	]


static func active_count(configuration: Variant) -> int:
	var normalized := sanitize(configuration)
	var count := 0
	for channel: StringName in CHANNELS:
		if float(normalized[channel]) > 0.001:
			count += 1
	return count


static func compact_summary(mode: StringName, configuration: Variant) -> String:
	var normalized := sanitize(configuration, mode)
	return "%s  //  S%d B%d L%d T%d R%d" % [
		String(mode),
		roundi(float(normalized[&"steering"]) * 100.0),
		roundi(float(normalized[&"braking"]) * 100.0),
		roundi(float(normalized[&"landing"]) * 100.0),
		roundi(float(normalized[&"traction"]) * 100.0),
		roundi(float(normalized[&"balance"]) * 100.0),
	]
