extends Node
## Cross-scene lifecycle events. Scene-local telemetry uses direct signals.

signal race_countdown_changed(value: int)
signal race_started()
signal checkpoint_passed(index: int, total: int, split_usec: int)
signal race_finished(time_usec: int, medal: StringName, is_new_best: bool)
signal race_results_ready(result: Dictionary)
signal race_reset()
signal game_paused(paused: bool)
signal activity_prepared(activity: StringName)
signal activity_started(activity: StringName)
signal freestyle_score_changed(score: int, combo: int, last_points: int)
signal discovery_progress_changed(current: int, total: int)
signal activity_completed(activity: StringName, result_value: int, medal: StringName, is_new_best: bool)
