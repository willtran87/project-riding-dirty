extends Node
## Deterministic clock and timed-activity pause immunity contract.

const CLOCK_SCRIPT := preload("res://common/simulation_clock.gd")
const FREESTYLE_SCRIPT := preload("res://features/freestyle/freestyle_controller.gd")
const DISCOVERY_SCRIPT := preload("res://features/discovery/discovery_controller.gd")
const RACE_SCENE := preload("res://features/race/race_controller.tscn")
const TEST_RATES := [30, 60, 120]

var _passed: bool = true


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	for update_rate: int in TEST_RATES:
		var clock: SimulationClock = CLOCK_SCRIPT.new()
		for _step: int in update_rate * 10:
			clock.advance(1.0 / float(update_rate))
		_check(
			absi(clock.elapsed_usec - 10_000_000) <= 1,
			"%d Hz accumulated %d usec over ten seconds" % [update_rate, clock.elapsed_usec]
		)

	var freestyle := FREESTYLE_SCRIPT.new() as FreestyleController
	freestyle.active = true
	for _step: int in 60:
		freestyle._physics_process(1.0 / 60.0)
	var before_pause := freestyle.get_elapsed_usec()
	await get_tree().create_timer(0.18, true, false, true).timeout
	var during_pause := freestyle.get_elapsed_usec()
	for _step: int in 60:
		freestyle._physics_process(1.0 / 60.0)
	var after_resume := freestyle.get_elapsed_usec()
	_check(before_pause == 1_000_000, "freestyle first simulated second drifted")
	_check(during_pause == before_pause, "freestyle charged wall time without simulation")
	_check(after_resume == 2_000_000, "freestyle resume clock drifted")

	var discovery := DISCOVERY_SCRIPT.new() as DiscoveryController
	var race := RACE_SCENE.instantiate() as RaceController
	_check(discovery.get("_run_clock") is SimulationClock, "discovery is not wired to the shared simulation clock")
	_check(race.get("_run_clock") is SimulationClock, "race is not wired to the shared simulation clock")
	discovery.free()
	race.free()
	freestyle.free()

	print(
		"SIMULATION CLOCK PAUSE PROBE: before=%d during=%d after=%d rates=%s passed=%s"
		% [before_pause, during_pause, after_resume, str(TEST_RATES), str(_passed)]
	)
	get_tree().quit(0 if _passed else 1)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_passed = false
	push_error("SIMULATION CLOCK PAUSE PROBE: %s" % message)
