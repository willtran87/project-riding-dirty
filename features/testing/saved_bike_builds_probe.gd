extends Node
## Persistent, bounded and non-exploitable named bike-build slots.

const PLAYER_PROFILE_SCRIPT := preload("res://common/player_profile.gd")
const FAILING_PROFILE_SCRIPT := preload("res://features/testing/failing_activity_settlement_profile.gd")

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var profile: Variant = PLAYER_PROFILE_SCRIPT.new()
	profile.persistence_enabled = false
	profile._ensure_full_race_defaults()
	profile.cash = 100_000
	profile.racer_reputation = 220
	profile.unlocked_setups.assign([&"BALANCED", &"TRAIL", &"ATTACK"])
	_check(profile.purchase_racing_part(&"TORQUE_PIPE"), "Torque Pipe could not be purchased")
	_check(profile.purchase_racing_part(&"HARDPACK_TIRES"), "Hardpack Tires could not be purchased")
	_check(profile.install_racing_part(&"TORQUE_PIPE"), "Torque Pipe could not be installed")
	_check(profile.install_racing_part(&"HARDPACK_TIRES"), "Hardpack Tires could not be installed")
	_check(profile.set_bike_tune({
		&"gearing": -0.15, &"tire_grip": 0.80,
		&"suspension_stiffness": 0.45, &"suspension_damping": 0.35,
		&"preload": -0.15, &"brake_bias": 0.20,
	}), "Hardpack tune could not be applied")
	_check(profile.set_current_setup(&"ATTACK"), "Attack setup could not be selected")
	_check(profile.set_rider_cosmetics({&"bike_livery": "NIGHT_RACE"}), "Night livery could not be selected")
	profile.apply_bike_damage(39)
	var saved: Dictionary = profile.save_current_bike_build(&"BUILD_A", "Tyke Hardpack Attack")
	_check(bool(saved.get(&"accepted", false)), "Build A was not saved")
	_check(str((saved.get(&"build", {}) as Dictionary).get(&"display_name", "")) == "TYKE HARDPACK ATTACK", "Saved build name was not normalized")

	# Change every restored dimension and add further wear. Loading must recover
	# the strategy while keeping the target bike's current 51% condition.
	_check(profile.purchase_racing_part(&"MUD_TIRES"), "Mud Tires could not be purchased")
	_check(profile.install_racing_part(&"MUD_TIRES"), "Mud Tires could not be installed")
	_check(profile.set_bike_tune({
		&"gearing": 0.25, &"tire_grip": 0.55,
		&"suspension_stiffness": -0.30, &"suspension_damping": 0.75,
		&"preload": 0.25, &"brake_bias": 0.25,
	}), "Enduro tune could not be applied")
	_check(profile.set_current_setup(&"TRAIL"), "Trail setup could not be selected")
	_check(profile.set_rider_cosmetics({&"bike_livery": "FACTORY"}), "Factory livery could not be selected")
	profile.apply_bike_damage(10)
	var loaded: Dictionary = profile.load_saved_bike_build(&"BUILD_A")
	var active: Dictionary = profile.get_active_bike_setup_snapshot()
	var build: Dictionary = active.get(&"build", {}) as Dictionary
	var parts: Dictionary = build.get(&"installed_parts", {}) as Dictionary
	var tune: Dictionary = build.get(&"tune", {}) as Dictionary
	_check(bool(loaded.get(&"accepted", false)), "Build A was not loaded")
	_check(profile.current_setup == &"ATTACK", "Saved setup kit was not restored")
	_check(profile.selected_bike_class == &"LITE_125", "Saved eligible class was not restored")
	_check(StringName(parts.get(&"ENGINE", &"")) == &"TORQUE_PIPE", "Saved engine part was not restored")
	_check(StringName(parts.get(&"TIRES", &"")) == &"HARDPACK_TIRES", "Saved tire part was not restored")
	_check(is_equal_approx(float(tune.get(&"tire_grip", 0.0)), 0.80), "Saved tune was not restored")
	_check(StringName(profile.rider_cosmetics.get(&"bike_livery", &"")) == &"NIGHT_RACE", "Saved livery was not restored")
	_check(profile.bike_condition == 51, "Loading a build restored old condition instead of preserving live wear")

	var before_invalid := str(active.get(&"signature", ""))
	var invalid: Dictionary = profile.load_saved_bike_build(&"BUILD_Z")
	_check(not bool(invalid.get(&"accepted", false)), "Invalid build slot was accepted")
	_check(str(profile.get_active_bike_setup_snapshot().get(&"signature", "")) == before_invalid, "Invalid load mutated the active build")

	# JSON persistence retains valid slots. Unrecognized slots, missing bikes and
	# unowned parts are stripped at the same trust boundary as owned builds.
	var serialized: Dictionary = profile._profile_to_dictionary()
	var saved_payload: Dictionary = serialized.get("saved_bike_builds", {}) as Dictionary
	saved_payload["BUILD_Z"] = (saved_payload.get("BUILD_A", {}) as Dictionary).duplicate(true)
	saved_payload["BUILD_B"] = {
		"slot_id": "BUILD_B", "display_name": "Tampered\nBuild",
		"bike_id": "TYKE_125", "setup_id": "BALANCED", "selected_class": "LITE_125",
		"installed_parts": {"ENGINE": "RACE_ECU", "TIRES": "HARDPACK_TIRES"},
		"tune": {"gearing": 99.0}, "livery_id": "FACTORY",
	}
	saved_payload["BUILD_C"] = {
		"slot_id": "BUILD_C", "display_name": "Missing Bike",
		"bike_id": "CHEAT_999", "setup_id": "ATTACK", "selected_class": "OPEN",
	}
	serialized["saved_bike_builds"] = saved_payload
	var json_round_trip: Variant = JSON.parse_string(JSON.stringify(serialized))
	var restored: Variant = PLAYER_PROFILE_SCRIPT.new()
	restored.persistence_enabled = false
	if json_round_trip is Dictionary:
		restored._apply_profile_dictionary(json_round_trip)
		restored._ensure_full_race_defaults()
	var restored_slots: Array[Dictionary] = restored.get_saved_bike_build_slots()
	var restored_a: Dictionary = restored.get_saved_bike_build_snapshot(&"BUILD_A")
	var restored_b: Dictionary = restored.get_saved_bike_build_snapshot(&"BUILD_B")
	var restored_b_parts: Dictionary = restored_b.get(&"installed_parts", {}) as Dictionary
	_check(restored.PROFILE_SCHEMA_VERSION == 6, "Profile schema was not advanced for saved builds")
	_check(restored_slots.size() == 3, "Saved-build projection does not expose exactly three bounded slots")
	_check(not restored_a.is_empty(), "Valid Build A did not survive JSON round-trip")
	_check(not restored_b.is_empty(), "Sanitizable Build B was discarded")
	_check(not restored_b_parts.has(&"ENGINE"), "Unowned tampered part survived saved-build sanitization")
	_check(StringName(restored_b_parts.get(&"TIRES", &"")) == &"HARDPACK_TIRES", "Owned valid part was lost during sanitization")
	_check(is_equal_approx(float((restored_b.get(&"tune", {}) as Dictionary).get(&"gearing", 0.0)), 1.0), "Saved tune was not clamped by RacingBikeTune")
	_check(str(restored_b.get(&"display_name", "")) == "TAMPERED BUILD", "Saved name control characters were not normalized")
	_check(restored.get_saved_bike_build_snapshot(&"BUILD_C").is_empty(), "Missing-bike build survived sanitization")
	_check(restored.get_saved_bike_build_snapshot(&"BUILD_Z").is_empty(), "Unbounded build slot survived sanitization")

	var legacy: Variant = PLAYER_PROFILE_SCRIPT.new()
	legacy.persistence_enabled = false
	legacy._apply_profile_dictionary({
		"profile_schema_version": 5,
		"current_setup": "BALANCED",
		"unlocked_setups": ["BALANCED"],
	})
	legacy._ensure_full_race_defaults()
	_check(legacy.saved_bike_builds.is_empty(), "Legacy profile migration invented a saved build")
	_check(int(legacy._profile_to_dictionary().get("profile_schema_version", 0)) == 6, "Legacy profile did not migrate to schema 6")

	var failing: Variant = FAILING_PROFILE_SCRIPT.new()
	failing.persistence_enabled = true
	failing._ensure_full_race_defaults()
	failing.unlocked_setups.assign([&"BALANCED", &"TRAIL"])
	_check(bool(failing.save_current_bike_build(&"BUILD_A", "Rollback Baseline").get(&"accepted", false)), "Fault profile could not seed Build A")
	_check(failing.set_current_setup(&"TRAIL"), "Fault profile could not select Trail")
	var trail_signature := str(failing.get_active_bike_setup_snapshot().get(&"signature", ""))
	failing.fail_next_save = true
	var failed_load: Dictionary = failing.load_saved_bike_build(&"BUILD_A")
	_check(not bool(failed_load.get(&"accepted", false)) and StringName(failed_load.get(&"reason", &"")) == &"SAVE_FAILED", "Failed build load did not report SAVE_FAILED")
	_check(failing.current_setup == &"TRAIL" and str(failing.get_active_bike_setup_snapshot().get(&"signature", "")) == trail_signature, "Failed build load did not roll back atomically")
	failing.fail_next_save = true
	var failed_save: Dictionary = failing.save_current_bike_build(&"BUILD_B", "Should Roll Back")
	_check(not bool(failed_save.get(&"accepted", false)) and failing.get_saved_bike_build_snapshot(&"BUILD_B").is_empty(), "Failed build save left an in-memory slot")

	print("SAVED BIKE BUILDS PROBE: saved=%s loaded=%s condition=%d slots=%d tamper=true legacy=true passed=%s" % [
		str(bool(saved.get(&"accepted", false))), str(bool(loaded.get(&"accepted", false))),
		profile.bike_condition, restored_slots.size(), str(_failures.is_empty()),
	])
	profile.free()
	restored.free()
	legacy.free()
	failing.free()
	if _failures.is_empty():
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("SAVED BIKE BUILDS PROBE: %s" % failure)
	get_tree().quit(1)


func _check(condition: bool, failure: String) -> void:
	if not condition:
		_failures.append(failure)
