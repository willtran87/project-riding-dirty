extends Node
## Controlled contact fixtures plus public telemetry assertions. These isolate
## vertical envelopes and tick-rate math from stochastic race outcomes.

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	Profile.persistence_enabled = false
	var pack := RacePack.new()
	pack.presentation_enabled = false
	pack.simulation_has_player = true
	add_child(pack)
	var session := RaceEventCatalog.get_session_config(&"CIRCUIT")
	pack.configure(session.track_id, CourseCatalog.get_world_riding_points(session.track_id), null, session)
	pack.start_race()
	pack.set_physics_process(false)
	# Author two bikes at the same route point. The upper bike passes over the
	# lower one, then lands into the contact envelope in the second scenario.
	var riders := pack.get("_riders") as Array
	for index: int in riders.size():
		riders[index][&"active"] = index < 2
	for index: int in 2:
		var rider: Dictionary = riders[index]
		rider[&"progress"] = 100.0
		rider[&"lane"] = float(index) * 0.3
		rider[&"lane_velocity"] = 0.0
		rider[&"speed"] = 20.0
		rider[&"contact_cooldown"] = 0.0
		rider[&"surface_initialized"] = true
		rider[&"surface_y"] = float(index) * 3.0
	pack.set("_race_elapsed", 10.0)
	pack.call(&"_resolve_rider_pairs", 1.0 / 60.0)
	var airborne := pack.get_chaos_snapshot()
	_check(int(airborne.get(&"field_contacts", -1)) == 0, "jump-over produced a phantom contact")
	_check(int(airborne.get(&"pair_separation_corrections", -1)) == 0, "jump-over produced a phantom shove")
	_check(is_zero_approx(float(riders[0][&"lane_velocity"])), "ground rider reacted to a vertically clear bike")
	riders[1][&"surface_y"] = 0.25
	pack.call(&"_resolve_rider_pairs", 1.0 / 60.0)
	_check(int(pack.get_chaos_snapshot().get(&"field_contacts", 0)) > 0, "landing into another bike lost physical contact")
	# Side-sensor fixture stays outside the physical overlap envelope.
	var velocities: Array[float] = []
	for hz: int in [30, 60, 120]:
		for index: int in 2:
			riders[index][&"lane"] = float(index) * 1.1
			riders[index][&"lane_velocity"] = 0.0
			riders[index][&"contact_cooldown"] = 10.0
		for tick: int in hz:
			pack.call(&"_resolve_rider_pairs", 1.0 / float(hz))
		velocities.append(absf(float(riders[0][&"lane_velocity"])))
	_check(absf(velocities[0] - velocities[1]) < 0.001 and absf(velocities[1] - velocities[2]) < 0.001, "side separation changes with physics frequency")
	# A decisive breakaway must expose the entire applied assistance, not just
	# its tactical component. Exercise all difficulty reserves at several gaps.
	for mode: StringName in RaceEventCatalog.PLAYER_DIFFICULTY_MODES:
		pack.set("_player_difficulty_mode", mode)
		for gap: float in [-80.0, -32.0, -4.0, 4.0, 80.0]:
			var tactical: float = pack.call(&"_bounded_tactical_pace", 4.0, 4.0, 4.0)
			var state := {&"tactical_pace_mps": tactical, &"tactical_pace_raw_mps": 12.0, &"comeback_skill": 1.0, &"pressure_skill": 1.0}
			var target: float = pack.call(&"_target_speed_for_gap", 20.0 + tactical, 20.0, gap, state)
			var telemetry := pack.get_chaos_snapshot()
			_check(float(telemetry.get(&"dynamic_pace_applied_peak_mps", 0.0)) + 0.001 >= target - 20.0, "%s assistance was missing from telemetry" % mode)
			_check(float(telemetry.get(&"dynamic_pace_budget_excess_peak_mps", INF)) <= 0.001, "%s combined assistance exceeded its cap" % mode)
	pack.queue_free()
	await get_tree().process_frame
	print("GAMEPLAY FAIRNESS PROBE: aerial/landing contact, 30/60/120Hz separation, five-mode pace caps passed=%s failures=%s" % [str(_failures.is_empty()), str(_failures)])
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
