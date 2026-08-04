extends Node3D
## Deterministic one-hour ghost soak and hostile saved-data boundary contract.

const GHOST_SCENE := preload("res://features/race/ghost_controller.tscn")
const SOAK_SECONDS: float = 3_600.0
const SOAK_STEP: float = 0.1

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var target := Node3D.new()
	target.name = "SoakTarget"
	add_child(target)
	var ghost := GHOST_SCENE.instantiate() as GhostController
	ghost.persistence_enabled = false
	ghost.target = target
	add_child(ghost)
	await get_tree().process_frame
	ghost.process_mode = Node.PROCESS_MODE_DISABLED

	ghost.start_run()
	var soak_steps := roundi(SOAK_SECONDS / SOAK_STEP)
	for step: int in soak_steps:
		var phase := float(step) * 0.003
		target.global_transform = Transform3D(
			Basis(Vector3.UP, phase),
			Vector3(sin(phase) * 18.0, 1.0 + sin(phase * 0.3), -float(step) * 0.2)
		)
		ghost._physics_process(SOAK_STEP)
	var live := ghost.get_runtime_budget_snapshot()
	_check(
		bool(live.get(&"active", false))
			and bool(live.get(&"bounded", false))
			and int(live.get(&"recording_frames", 0)) <= GhostController.MAX_RECORDING_FRAMES,
		"One-hour capture exceeded its live frame budget"
	)
	_check(
		int(live.get(&"decimations", 0)) >= 1
			and float(live.get(&"effective_interval_seconds", 0.0))
				> GhostController.SAMPLE_INTERVAL,
		"One-hour capture never activated adaptive sampling"
	)
	_check(
		float(live.get(&"recording_span_seconds", 0.0)) >= SOAK_SECONDS - 5.0,
		"Adaptive capture did not retain start-to-finish coverage"
	)

	ghost.finish_run(roundi(SOAK_SECONDS * 1_000_000.0), true)
	var finished := ghost.get_runtime_budget_snapshot()
	_check(
		int(finished.get(&"recording_frames", -1)) == 0
			and int(finished.get(&"best_frames", 0))
				<= GhostController.MAX_RECORDING_FRAMES
			and float(finished.get(&"best_span_seconds", 0.0)) >= SOAK_SECONDS - 5.0
			and bool(finished.get(&"bounded", false)),
		"Finished PB retained duplicate memory or lost bounded full-run coverage"
	)

	ghost.start_run()
	for step: int in 2_000:
		target.position.z = -float(step)
		ghost._physics_process(SOAK_STEP)
	ghost.cancel_run()
	var cancelled := ghost.get_runtime_budget_snapshot()
	_check(
		not bool(cancelled.get(&"active", true))
			and int(cancelled.get(&"recording_frames", -1)) == 0
			and is_zero_approx(float(cancelled.get(&"elapsed_seconds", -1.0))),
		"Cancelled run retained its recording buffer"
	)

	var oversized: Array = []
	oversized.resize(GhostController.MAX_IMPORT_FRAMES + 1)
	var oversized_result := ghost._sanitize_loaded_frames(oversized)
	_check(
		oversized_result.is_empty(),
		"Oversized saved ghost crossed the import boundary"
	)
	var non_finite_result := ghost._deserialize_frames([[
		INF, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0,
	]])
	_check(
		non_finite_result.is_empty(),
		"Non-finite saved ghost data was accepted"
	)
	var reversed_result := ghost._deserialize_frames([
		[1.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0],
		[0.5, 0.0, 1.0, -1.0, 0.0, 0.0, 0.0, 1.0],
	])
	_check(
		reversed_result.is_empty(),
		"Non-monotonic saved ghost data was accepted"
	)

	var valid_long: Array = []
	for frame_index: int in 10_000:
		valid_long.append([
			float(frame_index) * 0.1,
			float(frame_index) * 0.01,
			1.0,
			-float(frame_index) * 0.02,
			0.0,
			0.0,
			0.0,
			1.0,
		])
	var bounded_import := ghost._deserialize_frames(valid_long)
	_check(
		bounded_import.size() == GhostController.MAX_RECORDING_FRAMES
			and is_zero_approx(float(bounded_import[0].get(&"time", -1.0)))
			and is_equal_approx(
				float(bounded_import[-1].get(&"time", -1.0)),
				999.9
			),
		"Valid long saved ghost was not bounded while preserving both endpoints"
	)

	var passed := _failures.is_empty()
	print(
		"LONG SESSION STABILITY PROBE: live=%s finished=%s passed=%s failures=%s"
		% [str(live), str(finished), str(passed), ", ".join(_failures)]
	)
	ghost.queue_free()
	target.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if passed else 1)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
	push_error("LONG SESSION STABILITY: %s" % message)
