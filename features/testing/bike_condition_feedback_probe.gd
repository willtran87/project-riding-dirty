extends Node
## Headless contract for physical condition, semantic live status, and damage feedback.

const BIKE_SCRIPT := preload("res://entities/bike/bike_controller.gd")
const CONDITION_FEEDBACK := preload("res://features/race/bike_condition_feedback.gd")
const HUD_SCENE := preload("res://features/hud/race_hud.tscn")

var _failures: Array[String] = []
var _condition_signal: Dictionary = {}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var ready := CONDITION_FEEDBACK.build(100)
	var light := CONDITION_FEEDBACK.build(99)
	var worn := CONDITION_FEEDBACK.build(72)
	var damaged := CONDITION_FEEDBACK.build(45)
	var critical := CONDITION_FEEDBACK.build(12)
	_check(
		StringName(ready.get(&"status", &"")) == &"READY"
		and not bool(ready.get(&"visible", true))
		and StringName(light.get(&"status", &"")) == &"LIGHT_WEAR"
		and StringName(worn.get(&"status", &"")) == &"WORN"
		and StringName(damaged.get(&"status", &"")) == &"DAMAGED"
		and StringName(critical.get(&"status", &"")) == &"CRITICAL",
		"Condition thresholds do not produce stable semantic severity"
	)
	_check(
		is_equal_approx(float(damaged.get(&"engine_factor", 0.0)), lerpf(0.94, 1.0, 0.45))
		and is_equal_approx(float(damaged.get(&"grip_factor", 0.0)), lerpf(0.96, 1.0, 0.45))
		and is_equal_approx(float(damaged.get(&"speed_factor", 0.0)), lerpf(0.97, 1.0, 0.45)),
		"Condition presentation factors disagree with physical bike scaling"
	)
	_check(
		CONDITION_FEEDBACK.damage_for_landing(0.72) == 0
		and CONDITION_FEEDBACK.damage_for_landing(0.73) == 1
		and CONDITION_FEEDBACK.damage_for_automatic_recovery(
			DirtBikeController.RECOVERY_TIPPED
		) == 5
		and CONDITION_FEEDBACK.damage_for_automatic_recovery(
			DirtBikeController.RECOVERY_WORLD_FALL
		) == 8
		and CONDITION_FEEDBACK.damage_for_automatic_recovery(&"MANUAL_RESET") == 0,
		"Landing, crash, and manual-reset damage policy is inconsistent"
	)

	var bike: DirtBikeController = BIKE_SCRIPT.new()
	bike.condition_changed.connect(_on_condition_changed)
	bike.apply_condition(45)
	_check(
		int(_condition_signal.get(&"condition_percent", -1)) == 45
		and is_equal_approx(bike.engine_force, 1200.0 * lerpf(0.94, 1.0, 0.45))
		and is_equal_approx(bike.lateral_grip, 620.0 * lerpf(0.96, 1.0, 0.45))
		and is_equal_approx(bike.maximum_speed_mps, 30.0 * lerpf(0.97, 1.0, 0.45)),
		"Physical condition change did not publish the same authoritative snapshot"
	)

	var hud := HUD_SCENE.instantiate() as RaceHud
	add_child(hud)
	await get_tree().process_frame
	hud.update_bike_condition(worn)
	var worn_presentation := hud.get_bike_condition_presentation_snapshot()
	_check(
		bool(worn_presentation.get(&"visible", false))
		and str(worn_presentation.get(&"text", "")) == "BIKE WORN  //  72%",
		"Live HUD does not communicate worn condition textually"
	)
	hud.show_bike_damage(6, damaged)
	var damage_presentation := hud.get_bike_condition_presentation_snapshot()
	_check(
		str(damage_presentation.get(&"message", "")).contains("BIKE DAMAGE  -6")
		and str(damage_presentation.get(&"message", "")).contains("45%")
		and str(damage_presentation.get(&"message", "")).contains("DAMAGED")
		and bool(damage_presentation.get(&"warning_polarity", false)),
		"Crash damage lacks a clear semantic warning receipt"
	)
	hud.update_bike_condition(ready)
	_check(
		not bool(hud.get_bike_condition_presentation_snapshot().get(&"visible", true)),
		"Full-condition bikes retain unnecessary HUD clutter"
	)
	bike.free()
	hud.queue_free()
	await get_tree().process_frame

	print(
		"BIKE CONDITION FEEDBACK PROBE: physical=true statuses=5 damage_receipt=true passed=%s"
		% str(_failures.is_empty())
	)
	if _failures.is_empty():
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("BIKE CONDITION FEEDBACK PROBE: %s" % failure)
	get_tree().quit(1)


func _on_condition_changed(snapshot: Dictionary) -> void:
	_condition_signal = snapshot.duplicate(true)


func _check(condition: bool, failure: String) -> void:
	if not condition:
		_failures.append(failure)
