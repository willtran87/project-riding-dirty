extends Node
## Proves procedural rider animation is consistent across supported update rates.

const BIKE_VISUAL_SCRIPT := preload("res://entities/bike/bike_visual.gd")
const TEST_RATES := [30, 60, 120]
const ROTATION_TOLERANCE: float = 0.012
const PHASE_TOLERANCE: float = 0.0001

var _passed: bool = true


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var snapshots: Array[Dictionary] = []
	for update_rate: int in TEST_RATES:
		snapshots.append(_simulate(update_rate))
	var reference: Dictionary = snapshots[1]
	for index: int in snapshots.size():
		var snapshot: Dictionary = snapshots[index]
		_check(
			absf(float(snapshot[&"rider_pitch"]) - float(reference[&"rider_pitch"])) <= ROTATION_TOLERANCE,
			"rider pitch changes with update rate %d Hz" % TEST_RATES[index]
		)
		_check(
			absf(float(snapshot[&"rider_roll"]) - float(reference[&"rider_roll"])) <= ROTATION_TOLERANCE,
			"rider roll changes with update rate %d Hz" % TEST_RATES[index]
		)
		_check(
			absf(float(snapshot[&"torso_pitch"]) - float(reference[&"torso_pitch"])) <= ROTATION_TOLERANCE,
			"torso response changes with update rate %d Hz" % TEST_RATES[index]
		)
		_check(
			absf(float(snapshot[&"ride_phase"]) - float(reference[&"ride_phase"])) <= PHASE_TOLERANCE,
			"ride animation phase changes with update rate %d Hz" % TEST_RATES[index]
		)
		_check(
			absf(float(snapshot[&"wobble_phase"]) - float(reference[&"wobble_phase"])) <= PHASE_TOLERANCE,
			"wobble animation phase changes with update rate %d Hz" % TEST_RATES[index]
		)

	print("BIKE ANIMATION TIMESTEP PROBE: snapshots=%s passed=%s" % [str(snapshots), str(_passed)])
	get_tree().quit(0 if _passed else 1)


func _simulate(update_rate: int) -> Dictionary:
	var delta := 1.0 / float(update_rate)
	var rider_pitch := 0.0
	var rider_roll := 0.0
	var torso_pitch := 0.0
	var ride_phase := 0.0
	var wobble_phase := 0.0
	for _step: int in update_rate:
		ride_phase = fmod(ride_phase + 17.0 * delta * (0.82 + 0.35 * 0.36), TAU)
		wobble_phase = BIKE_VISUAL_SCRIPT.advance_animation_phase(
			wobble_phase,
			BIKE_VISUAL_SCRIPT.RIDER_WOBBLE_ANGULAR_SPEED,
			delta
		)
		var rider_pitch_target := 0.64 * 0.25 - 0.08
		var rider_roll_target := -0.72 * clampf(17.0 / 18.0, 0.0, 1.0) * 0.11 + sin(wobble_phase) * 0.75 * 0.09
		var torso_pitch_target := -0.12 - 0.64 * 0.12 - 0.12
		rider_pitch = lerpf(
			rider_pitch,
			rider_pitch_target,
			BIKE_VISUAL_SCRIPT.animation_response_weight(11.0, delta)
		)
		rider_roll = lerpf(
			rider_roll,
			rider_roll_target,
			BIKE_VISUAL_SCRIPT.animation_response_weight(9.0, delta)
		)
		torso_pitch = lerpf(
			torso_pitch,
			torso_pitch_target,
			BIKE_VISUAL_SCRIPT.animation_response_weight(BIKE_VISUAL_SCRIPT.RIDER_TORSO_RESPONSE_HZ, delta)
		)
	return {
		&"rate": update_rate,
		&"rider_pitch": rider_pitch,
		&"rider_roll": rider_roll,
		&"torso_pitch": torso_pitch,
		&"ride_phase": ride_phase,
		&"wobble_phase": wobble_phase,
	}


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_passed = false
	push_error("BIKE ANIMATION TIMESTEP PROBE: %s" % message)
