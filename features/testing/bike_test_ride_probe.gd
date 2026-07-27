extends Node
## Workshop-to-practice contract for stock previews with zero career mutation.

const GARAGE_SCRIPT := preload("res://features/garage/garage_ui.gd")
const TOUCH_SCRIPT := preload("res://features/input/touch_riding_controls.gd")
const TEST_RIDE := preload("res://features/career/bike_test_ride.gd")
const BIKE_CATALOG := preload("res://features/career/racing_bike_catalog.gd")
const RIDE_DIRECTOR := preload("res://features/ride/ride_director.gd")

var _failures: Array[String] = []
var _requested_bike_id: StringName = &""
var _requested_setup: StringName = &""


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var profile_snapshot := Profile._profile_to_dictionary()
	var prior_persistence := Profile.persistence_enabled
	Profile.persistence_enabled = false
	Profile.reset_profile_for_testing()
	var career_before := JSON.stringify(Profile._profile_to_dictionary())

	var garage: GarageUi = GARAGE_SCRIPT.new()
	add_child(garage)
	garage.test_ride_requested.connect(_on_test_ride_requested)
	garage.show_garage()
	garage.show_workshop()
	for _index: int in 3:
		var selected: Dictionary = (
			garage.get_workshop_snapshot().get(&"selected_item", {}) as Dictionary
		)
		if StringName(selected.get(&"bike_id", &"")) == &"ROOK_450":
			break
		garage.cycle_workshop_item(1)
	var workshop := garage.get_workshop_snapshot()
	var selected_bike := workshop.get(&"selected_item", {}) as Dictionary
	_check(
		StringName(selected_bike.get(&"bike_id", &"")) == &"ROOK_450",
		"Workshop could not select the locked Rook preview"
	)
	_check(
		str(workshop.get(&"workshop_action", "")).contains("TEST RIDE STOCK")
		and str(workshop.get(&"workshop_action", "")).contains("NO PURCHASE"),
		"Bike projection does not expose the distinct no-purchase Test Ride action"
	)
	_check(garage.test_ride_selected_bike(), "Locked bike Test Ride request was rejected")
	_check(
		_requested_bike_id == &"ROOK_450" and _requested_setup == &"BALANCED",
		"Workshop emitted the wrong bike or handling kit"
	)
	_check(
		JSON.stringify(Profile._profile_to_dictionary()) == career_before,
		"Requesting a Test Ride mutated cash, reputation, ownership, setup, or progression"
	)

	var catalog: Variant = BIKE_CATALOG.create_default()
	var stock: Dictionary = TEST_RIDE.create_stock_build(&"ROOK_450", catalog, &"BALANCED")
	var tyke: Dictionary = TEST_RIDE.create_stock_build(&"TYKE_125", catalog, &"BALANCED")
	var stock_build := stock.get(&"build", {}) as Dictionary
	var stock_runtime := stock.get(&"runtime", {}) as Dictionary
	var tyke_runtime := tyke.get(&"runtime", {}) as Dictionary
	_check(
		StringName(stock.get(&"bike_id", &"")) == &"ROOK_450"
		and (stock_build.get(&"installed_parts", {}) as Dictionary).is_empty()
		and is_equal_approx(float(stock_build.get(&"condition", 0.0)), 1.0),
		"Test Ride build is not a full-condition stock Rook"
	)
	_check(
		float(stock_runtime.get(&"engine_force", 0.0))
			> float(tyke_runtime.get(&"engine_force", 0.0)),
		"Different stock bikes do not produce physically distinct runtime previews"
	)
	var session: RaceSessionConfig = TEST_RIDE.create_session(&"ROOK_450", "Rook 450")
	_check(
		session.event_id == &"TEST_RIDE"
		and session.track_id == &"QUARRY"
		and session.session_type == &"PRACTICE"
		and session.opponent_count == 0
		and bool(session.rules.get(&"test_ride", false))
		and not bool(session.rules.get(&"ghost_enabled", true))
		and not RaceController.is_session_record_eligible(session),
		"Test Ride session is not a solo Quarry practice with explicit policy"
	)
	var sanitized := TEST_RIDE.sanitize_result({
		&"valid": true,
		&"medal": &"GOLD",
		&"is_new_best": true,
		&"championship_points": 25,
		&"rewards": {&"cash": 9999, &"reputation": 999},
	}, &"ROOK_450")
	var rewards := sanitized.get(&"rewards", {}) as Dictionary
	var payoff := sanitized.get(&"career_payoff", {}) as Dictionary
	_check(
		StringName(sanitized.get(&"medal", &"")) == &"NO_AWARD"
		and not bool(sanitized.get(&"is_new_best", true))
		and int(sanitized.get(&"championship_points", -1)) == 0
		and int(rewards.get(&"cash", -1)) == 0
		and int(rewards.get(&"reputation", -1)) == 0
		and StringName(payoff.get(&"reason", &"")) == &"TEST_RIDE",
		"Test Ride result retained rewards, records, or championship authority"
	)
	var director_policy: Dictionary = RIDE_DIRECTOR.get_activity_presentation_policy(&"TEST_RIDE")
	_check(
		not bool(director_policy.get(&"show_line_feedback", true))
		and not bool(director_policy.get(&"show_sponsor_contract", true))
		and not bool(director_policy.get(&"show_daily_modifier", true)),
		"Test Ride still permits feat, contract, or daily-modifier career leaks"
	)
	_check(
		InputRouter.get_action_contexts(InputRouter.CONTINUE_WEEKEND).has(&"WORKSHOP"),
		"Keyboard/gamepad Test Ride action is unavailable in the Workshop context"
	)

	var touch: TouchRidingControls = TOUCH_SCRIPT.new()
	add_child(touch)
	touch.set_touchscreen_override(1)
	touch.set_context(&"GARAGE")
	touch.set_workshop_open(true)
	var touch_controls := (
		touch.get_touch_layout_snapshot().get(&"controls", {}) as Dictionary
	)
	_check(
		str((touch_controls.get(&"continue", {}) as Dictionary).get(&"label", ""))
			== "TEST\nRIDE",
		"Touch Workshop retains an ambiguous Continue caption"
	)
	touch.set_workshop_open(false)
	touch_controls = touch.get_touch_layout_snapshot().get(&"controls", {}) as Dictionary
	_check(
		str((touch_controls.get(&"continue", {}) as Dictionary).get(&"label", ""))
			== "CONTINUE",
		"Touch Continue caption did not restore after leaving Workshop"
	)

	print(
		"BIKE TEST RIDE PROBE: bike=%s setup=%s solo=%s mutation=false touch=true passed=%s" %
		[
			String(_requested_bike_id), String(_requested_setup),
			str(session.opponent_count == 0), str(_failures.is_empty()),
		]
	)
	garage.queue_free()
	touch.queue_free()
	Profile._apply_profile_dictionary(profile_snapshot)
	Profile.persistence_enabled = prior_persistence
	if _failures.is_empty():
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("BIKE TEST RIDE PROBE: %s" % failure)
	get_tree().quit(1)


func _on_test_ride_requested(bike_id: StringName, setup: StringName) -> void:
	_requested_bike_id = bike_id
	_requested_setup = setup


func _check(condition: bool, failure: String) -> void:
	if not condition:
		_failures.append(failure)
