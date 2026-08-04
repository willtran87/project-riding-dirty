extends RefCounted
class_name CrashSupportPolicy
## Deterministic accessibility policy for crash damage and automatic recovery.
##
## The selected mode is frozen when an activity is composed and included in the
## competitive run signature. Assisted support reduces lasting condition damage
## and recognizes a tipped bike sooner without changing reset counts or penalties.

const STANDARD: StringName = &"STANDARD"
const ASSISTED: StringName = &"ASSISTED"
const MODES: Array[String] = ["STANDARD", "ASSISTED"]

const ASSISTED_DAMAGE_MULTIPLIER: float = 0.50
const ASSISTED_TIPPED_DELAY_MULTIPLIER: float = 0.57
const MINIMUM_ASSISTED_TIPPED_DELAY: float = 0.45


static func normalize(value: Variant) -> StringName:
	var mode := StringName(str(value).strip_edges().to_upper())
	return mode if mode in [STANDARD, ASSISTED] else STANDARD


static func scale_damage(base_damage: int, mode: Variant) -> int:
	var bounded_damage := maxi(base_damage, 0)
	if bounded_damage == 0 or normalize(mode) == STANDARD:
		return bounded_damage
	return maxi(int(ceil(float(bounded_damage) * ASSISTED_DAMAGE_MULTIPLIER)), 1)


static func tipped_recovery_delay(standard_delay: float, mode: Variant) -> float:
	var bounded_delay := maxf(standard_delay, 0.0)
	if normalize(mode) == STANDARD:
		return bounded_delay
	return maxf(
		bounded_delay * ASSISTED_TIPPED_DELAY_MULTIPLIER,
		MINIMUM_ASSISTED_TIPPED_DELAY
	)


static func snapshot(mode: Variant, standard_tipped_delay: float = 1.15) -> Dictionary:
	var normalized := normalize(mode)
	return {
		&"mode": normalized,
		&"label": "ASSISTED" if normalized == ASSISTED else "STANDARD",
		&"damage_multiplier": (
			ASSISTED_DAMAGE_MULTIPLIER if normalized == ASSISTED else 1.0
		),
		&"tipped_recovery_delay_seconds": tipped_recovery_delay(
			standard_tipped_delay,
			normalized
		),
		&"reset_penalty_preserved": true,
		&"competitive_identity_separated": true,
	}
