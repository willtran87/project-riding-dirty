extends RefCounted
class_name RaceReputationPolicy
## Pure, deterministic reputation pacing for classified race results.
## Cash remains owned by RaceController's existing reward calculation.

const POLICY_VERSION := 1
const GOLD_REPUTATION := 30
const SILVER_REPUTATION := 22
const BRONZE_REPUTATION := 16
const FINISHER_REPUTATION := 8
const WIN_REPUTATION := 8
const PODIUM_REPUTATION := 5
const TOP_FIVE_REPUTATION := 2
const PERSONAL_BEST_REPUTATION := 5
const REPEAT_FACTOR := 0.35
const MINIMUM_REPEAT_FACTOR := 0.25
const MAXIMUM_REPEAT_FACTOR := 0.50
const MINIMUM_COMPETITIVE_MULTIPLIER := 0.5
const MAXIMUM_COMPETITIVE_MULTIPLIER := 3.0


static func evaluate(context: Dictionary) -> Dictionary:
	var eligible := bool(context.get(&"eligible", true))
	var medal := StringName(str(context.get(&"medal", &"FINISHER")).to_upper())
	var position := maxi(int(context.get(&"position", 0)), 0)
	var is_first_clear := bool(context.get(&"is_first_clear", false))
	var is_first_win := bool(context.get(&"is_first_win", false))
	var is_new_best := bool(context.get(&"is_new_best", false))
	var competitive_multiplier := clampf(
		float(context.get(&"competitive_multiplier", 1.0)),
		MINIMUM_COMPETITIVE_MULTIPLIER,
		MAXIMUM_COMPETITIVE_MULTIPLIER
	)
	if not eligible:
		return _empty_result(competitive_multiplier)

	var base_reputation := _base_for_medal(medal)
	var placement_reputation := _placement_for_position(position)
	var personal_best_reputation := PERSONAL_BEST_REPUTATION if is_new_best else 0
	var reputation_before_repeat := base_reputation + placement_reputation + personal_best_reputation
	var milestone_reward := is_first_clear or is_first_win or is_new_best
	var repeat_factor := 1.0 if milestone_reward else clampf(
		float(context.get(&"repeat_factor", REPEAT_FACTOR)),
		MINIMUM_REPEAT_FACTOR,
		MAXIMUM_REPEAT_FACTOR
	)
	var reputation_after_repeat := roundi(float(reputation_before_repeat) * repeat_factor)
	var total_reputation := roundi(float(reputation_before_repeat) * repeat_factor * competitive_multiplier)
	return {
		&"policy_version": POLICY_VERSION,
		&"reputation": maxi(total_reputation, 0),
		&"base_reputation": base_reputation,
		&"placement_reputation": placement_reputation,
		&"personal_best_reputation": personal_best_reputation,
		&"bonus_reputation": placement_reputation + personal_best_reputation,
		&"reputation_before_repeat": reputation_before_repeat,
		&"reputation_after_repeat": reputation_after_repeat,
		&"repeat_factor": repeat_factor,
		&"repeat_limited": not milestone_reward,
		&"repeat_reason": _reward_reason(is_first_clear, is_first_win, is_new_best),
		&"competitive_multiplier": competitive_multiplier,
		&"is_first_clear": is_first_clear,
		&"is_first_win": is_first_win,
		&"is_new_best": is_new_best,
	}


static func _base_for_medal(medal: StringName) -> int:
	match medal:
		&"GOLD":
			return GOLD_REPUTATION
		&"SILVER":
			return SILVER_REPUTATION
		&"BRONZE":
			return BRONZE_REPUTATION
		&"NO_AWARD", &"UNRIDDEN":
			return 0
		_:
			return FINISHER_REPUTATION


static func _placement_for_position(position: int) -> int:
	if position == 1:
		return WIN_REPUTATION
	if position > 1 and position <= 3:
		return PODIUM_REPUTATION
	if position > 3 and position <= 5:
		return TOP_FIVE_REPUTATION
	return 0


static func _reward_reason(is_first_clear: bool, is_first_win: bool, is_new_best: bool) -> StringName:
	if is_new_best:
		return &"NEW_BEST"
	if is_first_win:
		return &"FIRST_WIN"
	if is_first_clear:
		return &"FIRST_CLEAR"
	return &"REPEAT_FINISH"


static func _empty_result(competitive_multiplier: float) -> Dictionary:
	return {
		&"policy_version": POLICY_VERSION,
		&"reputation": 0,
		&"base_reputation": 0,
		&"placement_reputation": 0,
		&"personal_best_reputation": 0,
		&"bonus_reputation": 0,
		&"reputation_before_repeat": 0,
		&"reputation_after_repeat": 0,
		&"repeat_factor": 0.0,
		&"repeat_limited": false,
		&"repeat_reason": &"INELIGIBLE",
		&"competitive_multiplier": competitive_multiplier,
		&"is_first_clear": false,
		&"is_first_win": false,
		&"is_new_best": false,
	}
