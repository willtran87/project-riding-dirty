extends CanvasLayer
class_name RaceHud
## Responsive race presentation projected from bike and race signals.

signal results_presented(result: Dictionary)
signal results_dismissed
signal hud_action_requested(action: StringName)

const CourseMapControl = preload("res://features/hud/course_minimap.gd")

const CREAM := Color("f7e5b2")
const AMBER := Color("ffb52d")
const CYAN := Color("56d6ff")
const DARK := Color(0.035, 0.045, 0.055, 0.88)
const WARNING := Color("ff806b")
const MUTED := Color("8b989f")
const LIVE_STANDING_ROWS := 6
const ACADEMY_OBJECTIVE_LIMIT := 2
const CONTROL_HINT_STAGE_SECONDS := 8.0
const CONTROL_HINT_RACE_SECONDS := 4.5
const CONTROL_HINT_CONTEXT_SECONDS := 3.5
const CONTROL_HINT_FADE_SECONDS := 0.9

var _timer_label: Label
var _best_label: Label
var _checkpoint_label: Label
var _speed_label: Label
var _speed_units_label: Label
var _speed_bar: ProgressBar
var _flow_label: Label
var _flow_bar: ProgressBar
var _racecraft_label: Label
var _countdown_label: Label
var _message_label: Label
var _gate_launch_label: Label
var _controls_panel: ColorRect
var _controls_label: Label
var _paused_label: Label
var _title_label: Label
var _compass_label: Label
var _reward_label: Label
var _line_label: Label
var _line_score_label: Label
var _contract_label: Label
var _modifier_label: Label
var _breakdown_label: Label
var _highlight_overlay: ColorRect
var _highlight_tween: Tween
var _course_map: Control
var _field_label: Label
var _phase_label: Label
var _lap_label: Label
var _flag_label: Label
var _integrity_label: Label
var _standings_panel: Control
var _standings_title: Label
var _standings_rows: Array[Label] = []
var _academy_panel: PanelContainer
var _academy_title_label: Label
var _academy_description_label: Label
var _academy_objective_labels: Array[Label] = []
var _results_panel: PanelContainer
var _results_title: Label
var _results_summary: Label
var _results_competition: Label
var _results_heading_label: Label
var _results_scroll: ScrollContainer
var _results_rows: VBoxContainer
var _results_row_panels: Array[PanelContainer] = []
var _results_selected_index: int = -1
var _results_player_index: int = -1
var _results_visibility_request: int = 0
var _results_stats: Label
var _results_footer: Label
var _message_time: float = 0.0
var _reward_time: float = 0.0
var _reward_queue: Array[Dictionary] = []
var _activity: StringName = &"CIRCUIT"
var _track_id: StringName = CourseCatalog.QUARRY_ID
var _authoritative_route := PackedVector3Array()
var _rival_target_usec: int = 190_000_000
var _last_rival_delta_usec: int = 0
var _has_rival_split: bool = false
var _session_snapshot: Dictionary = {}
var _integrity_snapshot: Dictionary = {}
var _classification: Array[Dictionary] = []
var _holeshot_rider_id: StringName = &""
var _last_integrity_warning: String = ""
var _session_format: StringName = &"SPRINT"
var _session_weather: StringName = &"CLEAR"
var _race_source: Object
var _hud_root: Control
var _unit_mode: StringName = &"IMPERIAL"
var _high_contrast: bool = false
var _color_safe_mode: StringName = &"OFF"
var _text_scale: float = 1.0
var _control_hint_hold_time: float = 0.0
var _control_hint_opacity: float = 1.0
var _control_hint_pinned: bool = false
var _academy_lesson: Dictionary = {}
var _academy_live_metrics: Dictionary = {}
var _last_academy_evaluation: Dictionary = {}
var _last_result: Dictionary = {}
var _last_leaderboard_result: Dictionary = {}
var _replay_summary: Dictionary = {}
var _replay_available: bool = false
var _replay_hid_results: bool = false
var _gate_launch_feedback_time: float = 0.0
var _last_gate_launch_result_attempt: int = -1
var _racecraft_snapshot: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_hud()
	EventBus.race_countdown_changed.connect(_on_countdown_changed)
	EventBus.race_started.connect(_on_race_started)
	EventBus.checkpoint_passed.connect(_on_checkpoint_passed)
	EventBus.race_finished.connect(_on_race_finished)
	EventBus.race_reset.connect(_on_race_reset)
	EventBus.game_paused.connect(_on_game_paused)
	EventBus.activity_prepared.connect(_on_activity_prepared)
	EventBus.activity_started.connect(_on_activity_started)
	EventBus.freestyle_score_changed.connect(_on_freestyle_score_changed)
	EventBus.discovery_progress_changed.connect(_on_discovery_progress_changed)
	EventBus.activity_completed.connect(_on_activity_completed)
	Profile.reward_granted.connect(_on_reward_granted)
	Profile.achievement_unlocked.connect(_on_achievement_unlocked)
	InputRouter.device_changed.connect(_on_device_changed)
	_on_device_changed(InputRouter.using_gamepad)


func _exit_tree() -> void:
	_unbind_race_source()


func _unhandled_input(event: InputEvent) -> void:
	if _handle_results_navigation_input(event):
		get_viewport().set_input_as_handled()


func initialize(
	player_bike: Node3D,
	initial_track_id: StringName = CourseCatalog.QUARRY_ID,
	authoritative_route: PackedVector3Array = PackedVector3Array()
) -> void:
	_course_map.set(&"player", player_bike)
	configure_track(initial_track_id, authoritative_route)


func bind_race_source(source: Object) -> void:
	## Optional direct binding for a RaceController-like source. Existing callers
	## may continue pushing telemetry through the legacy update_* methods.
	_unbind_race_source()
	_race_source = source
	if _race_source == null:
		return
	_connect_source_signal(&"session_updated", _on_session_snapshot_received)
	_connect_source_signal(&"classification_updated", _on_classification_received)
	_connect_source_signal(&"integrity_updated", _on_integrity_received)
	_connect_source_signal(&"results_ready", _on_results_received)


func unbind_race_source() -> void:
	_unbind_race_source()


func update_session_snapshot(snapshot: Dictionary) -> void:
	## Consumes the canonical race projection. Unknown keys are deliberately
	## ignored so the HUD remains compatible with lean and extended controllers.
	_session_snapshot = snapshot.duplicate(true)
	if snapshot.has(&"event_id"):
		_activity = StringName(snapshot.get(&"event_id", _activity))
	_session_format = StringName(snapshot.get(&"format", _session_format))
	_session_weather = StringName(snapshot.get(&"weather", _session_weather))
	var display_name := str(snapshot.get(&"display_name", snapshot.get(&"event_name", "")))
	var phase := StringName(snapshot.get(&"phase", snapshot.get(&"state_name", &"RACING")))
	var current_lap := maxi(int(snapshot.get(&"current_lap", snapshot.get(&"lap", 1))), 1)
	var total_laps := maxi(int(snapshot.get(&"total_laps", snapshot.get(&"laps", 1))), 1)
	var position := maxi(int(snapshot.get(&"position", 1)), 1)
	var field_size := maxi(int(snapshot.get(&"field_size", snapshot.get(&"total_racers", 1))), 1)
	if not display_name.is_empty():
		_title_label.text = "RIDING DIRTY  //  %s" % display_name.to_upper()
	_phase_label.text = _phase_text(phase)
	_phase_label.modulate = _phase_color(phase)
	_lap_label.text = "LAP %d / %d" % [mini(current_lap, total_laps), total_laps]
	_standings_panel.visible = _activity not in [&"FREESTYLE", &"DISCOVERY", &"ACADEMY"]
	_phase_label.visible = _standings_panel.visible
	_lap_label.visible = _standings_panel.visible
	_flag_label.visible = _standings_panel.visible
	var elapsed_usec := int(snapshot.get(&"elapsed_usec", snapshot.get(&"race_time_usec", -1)))
	if elapsed_usec >= 0:
		_timer_label.text = _format_usec(elapsed_usec)
	var gap_ahead := float(snapshot.get(&"gap_ahead_m", snapshot.get(&"gap_ahead", -1.0)))
	var gap_behind := float(snapshot.get(&"gap_behind_m", snapshot.get(&"gap_behind", -1.0)))
	update_field(position, field_size, gap_ahead, gap_behind)
	if snapshot.has(&"checkpoint") or snapshot.has(&"checkpoint_index") or snapshot.has(&"current_checkpoint"):
		var checkpoint := int(snapshot.get(&"checkpoint", snapshot.get(&"checkpoint_index", snapshot.get(&"current_checkpoint", 0))))
		var checkpoint_total := int(snapshot.get(&"checkpoint_total", snapshot.get(&"total_checkpoints", snapshot.get(&"checkpoint_count", 0))))
		if checkpoint_total > 0:
			_checkpoint_label.text = "GATE  %02d / %02d" % [mini(checkpoint + 1, checkpoint_total), checkpoint_total]
	if snapshot.has(&"classification"):
		update_classification(snapshot.get(&"classification", []) as Array)
	if snapshot.has(&"integrity") and snapshot.get(&"integrity") is Dictionary:
		update_integrity(snapshot.get(&"integrity") as Dictionary)
	if snapshot.has(&"flag"):
		update_race_flag(StringName(snapshot.get(&"flag", &"GREEN")))
	_update_academy_live_metrics(snapshot)
	var holeshot_value := StringName(snapshot.get(&"holeshot_rider_id", &""))
	if not holeshot_value.is_empty():
		show_holeshot(holeshot_value, str(snapshot.get(&"holeshot_name", "")))
	if snapshot.has(&"gate_launch") and snapshot.get(&"gate_launch") is Dictionary:
		_update_gate_launch_feedback(snapshot.get(&"gate_launch") as Dictionary, phase)
	if snapshot.has(&"racecraft") and snapshot.get(&"racecraft") is Dictionary:
		update_racecraft_state(snapshot.get(&"racecraft") as Dictionary)


func apply_session_snapshot(snapshot: Dictionary) -> void:
	# Alias for presentation adapters that use apply_* naming.
	update_session_snapshot(snapshot)


func update_session(snapshot: Dictionary) -> void:
	# Main-scene integration alias.
	update_session_snapshot(snapshot)


func update_classification(classification: Array) -> void:
	_classification.clear()
	for value: Variant in classification:
		if value is Dictionary:
			_classification.append((value as Dictionary).duplicate())
	_course_map.call(&"set_racers", _classification)
	_refresh_live_standings()


func set_classification(classification: Array) -> void:
	update_classification(classification)


func update_race_phase(phase: StringName) -> void:
	_phase_label.text = _phase_text(phase)
	_phase_label.modulate = _phase_color(phase)


func update_lap_status(current_lap: int, total_laps: int) -> void:
	var safe_total := maxi(total_laps, 1)
	_lap_label.text = "LAP %d / %d" % [clampi(current_lap, 1, safe_total), safe_total]


func update_race_flag(flag: StringName) -> void:
	_set_flag(flag)


func update_integrity(snapshot: Dictionary) -> void:
	_integrity_snapshot = snapshot.duplicate(true)
	var flag := StringName(snapshot.get(&"flag", snapshot.get(&"race_flag", &"CLEAR")))
	if flag == &"WARNING":
		_set_flag(&"YELLOW")
	elif flag == &"RESET_REQUIRED":
		_set_flag(&"RED")
	elif flag not in [&"CLEAR", &"NONE", &""]:
		_set_flag(flag)
	var warning := str(snapshot.get(&"message", ""))
	if warning.is_empty():
		warning = str(snapshot.get(&"warning", ""))
	if warning in ["NONE", "CLEAR"]:
		warning = ""
	elif warning == "WRONG_WAY":
		warning = "WRONG WAY  //  TURN AROUND"
	elif warning == "OFF_COURSE":
		warning = "OFF COURSE  //  RETURN TO THE RIBBON"
	elif warning in ["CUT", "CUT_DETECTED"]:
		warning = "COURSE CUT  //  PENALTY APPLIED"
	elif warning == "STUCK":
		warning = "BIKE STUCK  //  RESET AVAILABLE"
	elif warning == "MANUAL_RESET":
		warning = "RESET  //  PENALTY APPLIED"
	if warning.is_empty():
		if bool(snapshot.get(&"wrong_way", false)):
			warning = "WRONG WAY  //  TURN AROUND"
		elif bool(snapshot.get(&"off_course", false)):
			warning = "OFF COURSE  //  RETURN TO THE RIBBON"
		elif bool(snapshot.get(&"cut_detected", snapshot.get(&"cut", false))):
			warning = "COURSE CUT  //  PENALTY APPLIED"
	var penalty_usec := int(snapshot.get(&"penalty_usec", snapshot.get(&"total_penalty_usec", 0)))
	if warning.is_empty() and penalty_usec > 0:
		warning = "PENALTY  +%.1fs" % (float(penalty_usec) / 1_000_000.0)
	_integrity_label.text = warning
	_integrity_label.visible = not warning.is_empty()
	_integrity_label.modulate = WARNING if bool(snapshot.get(&"run_valid", snapshot.get(&"valid", true))) else Color("ff4e45")
	if not warning.is_empty() and warning != _last_integrity_warning:
		_pulse_warning()
	_last_integrity_warning = warning


func set_integrity_snapshot(snapshot: Dictionary) -> void:
	update_integrity(snapshot)


func show_holeshot(rider_id: StringName, display_name: String = "") -> void:
	if rider_id.is_empty() or rider_id == _holeshot_rider_id:
		return
	_holeshot_rider_id = rider_id
	var rider_name := display_name
	if rider_name.is_empty():
		for racer: Dictionary in _classification:
			if StringName(racer.get(&"rider_id", &"")) == rider_id:
				rider_name = str(racer.get(&"display_name", rider_id))
				break
	if rider_name.is_empty():
		rider_name = "YOU" if rider_id == &"PLAYER" else String(rider_id).replace("_", " ")
	show_race_moment("HOLESHOT  //  %s" % rider_name.to_upper(), 0, rider_id == &"PLAYER")
	_refresh_live_standings()


func show_results(result: Dictionary) -> void:
	dismiss_control_hints()
	if str(_last_result.get(&"signature", "")) != str(result.get(&"signature", "")):
		_last_leaderboard_result.clear()
	_last_result = result.duplicate(true)
	var academy_value: Variant = result.get(&"academy_evaluation", {})
	_last_academy_evaluation = (academy_value as Dictionary).duplicate(true) if academy_value is Dictionary else {}
	_holeshot_rider_id = StringName(result.get(&"holeshot_rider_id", _holeshot_rider_id))
	var classification_value: Variant = result.get(&"classification", [])
	if classification_value is Array:
		update_classification(classification_value as Array)
	_results_title.text = _results_heading(result)
	_results_summary.text = _results_summary_text(result)
	_results_competition.visible = _last_academy_evaluation.is_empty()
	_refresh_results_competition()
	if not _last_academy_evaluation.is_empty():
		_results_heading_label.text = "OBJECTIVE  //  MEASURED RESULT  //  BRONZE / SILVER / GOLD"
		_populate_academy_results(_last_academy_evaluation)
	else:
		_results_heading_label.text = "POS     RIDER                         STATUS             TIME / GAP"
		_populate_results_rows(_classification)
	_results_stats.text = _results_stats_text(result)
	var next_event_name := str(result.get(&"next_event_name", "")).strip_edges()
	if not _last_academy_evaluation.is_empty():
		var lesson_id := StringName(_last_academy_evaluation.get(&"lesson_id", &""))
		var next_lesson_id := StringName(result.get(&"academy_next_lesson_id", lesson_id))
		var next_lesson_name := str(result.get(&"academy_next_lesson_name", "ACADEMY LESSON")).to_upper()
		var passed := bool(_last_academy_evaluation.get(&"passed", false))
		var action_text := "RETRY LESSON"
		if passed and next_lesson_id != lesson_id:
			action_text = "NEXT LESSON"
		elif passed:
			action_text = "REPLAY LESSON"
		_results_footer.text = "ACADEMY NEXT  %s     //     ENTER / X  %s     G / B  GARAGE" % [next_lesson_name, action_text]
	else:
		_refresh_results_footer(next_event_name)
	_results_panel.visible = true
	_queue_results_selection_visibility()
	if _academy_panel != null:
		_academy_panel.visible = false
	_phase_label.text = "OFFICIAL RESULTS"
	_phase_label.modulate = CYAN
	_set_flag(&"CHECKERED")
	_message_label.text = ""
	_message_time = 0.0
	results_presented.emit(result.duplicate(true))


func present_results(result: Dictionary) -> void:
	show_results(result)


func hide_results() -> void:
	if not _results_panel.visible:
		return
	_results_panel.visible = false
	_refresh_academy_panel()
	results_dismissed.emit()


func request_results_action(action: StringName) -> void:
	## Lets controller/input adapters route explicit UI actions without the HUD
	## owning gameplay input bindings.
	hud_action_requested.emit(action)


func get_session_snapshot() -> Dictionary:
	return _session_snapshot.duplicate(true)


func get_gate_launch_feedback_snapshot() -> Dictionary:
	return {
		&"text": _gate_launch_label.text if _gate_launch_label != null else "",
		&"visible": _gate_launch_label != null and _gate_launch_label.visible,
		&"seconds_remaining": _gate_launch_feedback_time,
		&"result_attempt": _last_gate_launch_result_attempt,
	}


func get_integrity_snapshot() -> Dictionary:
	return _integrity_snapshot.duplicate(true)


func get_displayed_classification() -> Array[Dictionary]:
	return _classification.duplicate(true)


func configure_academy_lesson(lesson: Dictionary) -> void:
	_academy_lesson = lesson.duplicate(true)
	_academy_live_metrics.clear()
	_refresh_academy_panel()


func get_academy_presentation_snapshot() -> Dictionary:
	var objective_texts := PackedStringArray()
	for label: Label in _academy_objective_labels:
		if not label.text.is_empty():
			objective_texts.append(label.text)
	return {
		&"lesson_id": StringName(_academy_lesson.get(&"lesson_id", &"")),
		&"title": _academy_title_label.text if _academy_title_label != null else "",
		&"description": _academy_description_label.text if _academy_description_label != null else "",
		&"objectives": objective_texts,
		&"visible": _academy_panel != null and _academy_panel.visible,
		&"live_metrics": _academy_live_metrics.duplicate(true),
		&"evaluation": _last_academy_evaluation.duplicate(true),
		&"results_title": _results_title.text if _results_title != null else "",
		&"results_summary": _results_summary.text if _results_summary != null else "",
		&"results_heading": _results_heading_label.text if _results_heading_label != null else "",
		&"results_stats": _results_stats.text if _results_stats != null else "",
		&"result_row_count": _results_rows.get_child_count() if _results_rows != null else 0,
	}


func update_leaderboard_result(result: Dictionary) -> void:
	## RaceServices emits this after the official result. Ignore hot-seat payloads
	## and stale boards so a prior event can never decorate the current result.
	if result.has("kind") or _last_result.is_empty():
		return
	var entry_value: Variant = result.get("entry", {})
	if not entry_value is Dictionary:
		return
	var entry := entry_value as Dictionary
	if str(entry.get("run_signature", "")) != str(_last_result.get(&"signature", "")):
		return
	_last_leaderboard_result = result.duplicate(true)
	_refresh_results_competition()
	_refresh_results_footer(str(_last_result.get(&"next_event_name", "")).strip_edges())


func update_replay_available(summary: Dictionary) -> void:
	_replay_summary = summary.duplicate(true)
	_replay_available = not summary.is_empty() and int(summary.get(&"samples", 0)) >= 2
	_refresh_results_competition()
	if not _last_result.is_empty():
		_refresh_results_footer(str(_last_result.get(&"next_event_name", "")).strip_edges())


func update_replay_state(active: bool) -> void:
	## A replay cannot be watched through an opaque classification panel. Preserve
	## the official card and restore it when the existing replay toggle exits.
	if active:
		_replay_hid_results = _results_panel != null and _results_panel.visible
		if _replay_hid_results:
			_results_panel.visible = false
		return
	if _replay_hid_results and _results_panel != null and not _last_result.is_empty():
		_results_panel.visible = true
		_queue_results_selection_visibility()
	_replay_hid_results = false


func get_competition_presentation_snapshot() -> Dictionary:
	return {
		&"visible": _results_competition != null and _results_competition.visible,
		&"text": _results_competition.text if _results_competition != null else "",
		&"footer": _results_footer.text if _results_footer != null else "",
		&"replay_available": _replay_available,
		&"replay": _replay_summary.duplicate(true),
		&"leaderboard": _last_leaderboard_result.duplicate(true),
		&"result_event": StringName(_last_result.get(&"event_id", &"")),
		&"results_visible": _results_panel != null and _results_panel.visible,
	}


func get_results_navigation_snapshot() -> Dictionary:
	var selected: Control
	if _results_selected_index >= 0 and _results_selected_index < _results_row_panels.size():
		selected = _results_row_panels[_results_selected_index]
	var selected_visible := false
	if _results_scroll != null and is_instance_valid(selected):
		var scroll_rect := _results_scroll.get_global_rect()
		var selected_rect := selected.get_global_rect()
		selected_visible = (
			selected_rect.position.y >= scroll_rect.position.y - 0.5
			and selected_rect.position.y + selected_rect.size.y <= scroll_rect.position.y + scroll_rect.size.y + 0.5
		)
	var maximum_scroll := 0.0
	if _results_scroll != null:
		var scroll_bar := _results_scroll.get_v_scroll_bar()
		maximum_scroll = maxf(scroll_bar.max_value - scroll_bar.page, 0.0)
	return {
		&"row_count": _results_row_panels.size(),
		&"selected_index": _results_selected_index,
		&"player_index": _results_player_index,
		&"selected_visible": selected_visible,
		&"scroll_vertical": _results_scroll.scroll_vertical if _results_scroll != null else 0,
		&"maximum_scroll": maximum_scroll,
		&"mouse_scroll_enabled": _results_scroll != null and _results_scroll.mouse_filter != Control.MOUSE_FILTER_IGNORE,
	}


func _handle_results_navigation_input(event: InputEvent) -> bool:
	if _results_panel == null or not _results_panel.visible:
		return false
	if not _last_academy_evaluation.is_empty() or _results_row_panels.is_empty():
		return false
	if event.is_echo():
		return false
	var command := &""
	if event is InputEventKey and (event as InputEventKey).pressed:
		var key := (event as InputEventKey).physical_keycode
		if key == KEY_NONE:
			key = (event as InputEventKey).keycode
		match key:
			KEY_UP, KEY_W: command = &"PREVIOUS"
			KEY_DOWN, KEY_S: command = &"NEXT"
			KEY_PAGEUP: command = &"PAGE_PREVIOUS"
			KEY_PAGEDOWN: command = &"PAGE_NEXT"
			KEY_HOME: command = &"FIRST"
			KEY_END: command = &"LAST"
	elif event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		match (event as InputEventJoypadButton).button_index:
			JOY_BUTTON_DPAD_UP: command = &"PREVIOUS"
			JOY_BUTTON_DPAD_DOWN: command = &"NEXT"
			JOY_BUTTON_LEFT_SHOULDER: command = &"PAGE_PREVIOUS"
			JOY_BUTTON_RIGHT_SHOULDER: command = &"PAGE_NEXT"
	if command.is_empty():
		return false
	match command:
		&"PREVIOUS": _move_results_selection(-1)
		&"NEXT": _move_results_selection(1)
		&"PAGE_PREVIOUS": _move_results_selection(-5)
		&"PAGE_NEXT": _move_results_selection(5)
		&"FIRST": _set_results_selection(0)
		&"LAST": _set_results_selection(_results_row_panels.size() - 1)
	return true


func _on_results_scroll_gui_input(event: InputEvent) -> void:
	if _handle_results_mouse_scroll(event):
		_results_scroll.accept_event()


func _handle_results_mouse_scroll(event: InputEvent) -> bool:
	if _results_scroll == null or _results_panel == null or not _results_panel.visible:
		return false
	if not event is InputEventMouseButton:
		return false
	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed or mouse_event.button_index not in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		return false
	var scroll_bar := _results_scroll.get_v_scroll_bar()
	var maximum_scroll := maxi(roundi(scroll_bar.max_value - scroll_bar.page), 0)
	if maximum_scroll <= 0:
		return false
	var direction := -1 if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP else 1
	var step := maxi(roundi(maxf(48.0, _results_scroll.size.y * 0.18) * maxf(mouse_event.factor, 1.0)), 1)
	_results_scroll.scroll_vertical = clampi(_results_scroll.scroll_vertical + direction * step, 0, maximum_scroll)
	return true


func _move_results_selection(direction: int) -> void:
	_set_results_selection(_results_selected_index + direction)


func _set_results_selection(index: int) -> void:
	if _results_row_panels.is_empty():
		_results_selected_index = -1
		return
	_results_selected_index = clampi(index, 0, _results_row_panels.size() - 1)
	_refresh_results_row_styles()
	_queue_results_selection_visibility()


func _queue_results_selection_visibility() -> void:
	_results_visibility_request += 1
	call_deferred(&"_scroll_results_selection_into_view", _results_visibility_request)


func _scroll_results_selection_into_view(request_id: int) -> void:
	await get_tree().process_frame
	if request_id != _results_visibility_request or _results_scroll == null:
		return
	if _results_selected_index < 0 or _results_selected_index >= _results_row_panels.size():
		return
	var selected := _results_row_panels[_results_selected_index]
	if is_instance_valid(selected):
		_results_scroll.ensure_control_visible(selected)


func is_results_visible() -> bool:
	return _results_panel.visible


func show_control_hints(duration: float = CONTROL_HINT_CONTEXT_SECONDS) -> void:
	## Presentation adapters can briefly re-stage the learned controls after a
	## device change or tutorial beat without making them a permanent HUD block.
	if _controls_panel == null or _controls_label == null:
		return
	_control_hint_hold_time = maxf(duration, 0.0)
	_set_control_hint_opacity(1.0)


func dismiss_control_hints(immediate: bool = false) -> void:
	_control_hint_hold_time = 0.0
	if immediate:
		_set_control_hint_opacity(0.0)


func get_control_hint_state() -> Dictionary:
	return {
		&"visible": _controls_panel != null and _controls_panel.visible,
		&"opacity": _control_hint_opacity,
		&"hold_seconds": _control_hint_hold_time,
		&"pinned": _control_hint_pinned,
		&"panel_size": _controls_panel.size if _controls_panel != null else Vector2.ZERO,
	}


func configure_track(track_id: StringName, authoritative_route: PackedVector3Array) -> void:
	_track_id = track_id
	_authoritative_route = authoritative_route.duplicate()
	_course_map.call(&"configure_route", track_id, authoritative_route)


func get_minimap_route_points() -> PackedVector3Array:
	return _course_map.call(&"get_route_points") as PackedVector3Array


func _update_gate_launch_feedback(snapshot: Dictionary, phase: StringName) -> void:
	if _gate_launch_label == null:
		return
	var active := bool(snapshot.get(&"active", false))
	var finalized := bool(snapshot.get(&"finalized", false))
	if active:
		_gate_launch_feedback_time = 0.0
		var prompt := str(snapshot.get(&"prompt", "STAGE  //  HOLD THROTTLE"))
		var throttle_percent := roundi(clampf(float(snapshot.get(&"throttle", 0.0)), 0.0, 1.0) * 100.0)
		var brake_percent := roundi(clampf(float(snapshot.get(&"brake", 0.0)), 0.0, 1.0) * 100.0)
		_gate_launch_label.text = "%s\nTHROTTLE %03d%%  //  BRAKE %03d%%" % [prompt, throttle_percent, brake_percent]
		_gate_launch_label.modulate = WARNING if prompt.begins_with("DROP BRAKE") else CYAN if bool(snapshot.get(&"brake_staged", false)) and throttle_percent >= 45 else AMBER
		_gate_launch_label.visible = true
		return
	if finalized and phase in [&"RACING", &"PRACTICE", &"QUALIFYING"]:
		var attempt_id := int(snapshot.get(&"attempt_id", -1))
		if attempt_id == _last_gate_launch_result_attempt:
			return
		_last_gate_launch_result_attempt = attempt_id
		var multiplier := clampf(float(snapshot.get(&"drive_multiplier", 1.0)), 0.94, 1.08)
		var drive_percent := roundi((multiplier - 1.0) * 100.0)
		var drive_text := "+%d%% DRIVE" % drive_percent if drive_percent > 0 else "%d%% DRIVE" % drive_percent if drive_percent < 0 else "NEUTRAL DRIVE"
		var outcome := str(snapshot.get(&"outcome", &"CLEAN_GATE")).replace("_", " ")
		_gate_launch_label.text = "%s  //  %s" % [outcome, drive_text]
		_gate_launch_label.modulate = CYAN if drive_percent > 0 else WARNING if drive_percent < 0 else CREAM
		_gate_launch_label.visible = true
		_gate_launch_feedback_time = 2.1
		return
	if phase in [&"WAITING", &"STAGING", &"COUNTDOWN"]:
		_gate_launch_feedback_time = 0.0
		_gate_launch_label.text = ""
		_gate_launch_label.visible = false


func _process(delta: float) -> void:
	_update_control_hints(delta)
	if _gate_launch_feedback_time > 0.0:
		_gate_launch_feedback_time = maxf(_gate_launch_feedback_time - delta, 0.0)
		if _gate_launch_feedback_time <= 0.0 and _gate_launch_label != null:
			_gate_launch_label.text = ""
			_gate_launch_label.visible = false
	if _message_time > 0.0:
		_message_time -= delta
		if _message_time <= 0.0:
			_message_label.text = ""
			if _countdown_label.text == "GO!":
				_countdown_label.text = ""
	if _reward_time > 0.0:
		_reward_time -= delta
		if _reward_time <= 0.0:
			_reward_label.text = ""
			_present_next_reward()


func update_telemetry(speed_mph: float, _throttle: float, grounded: bool) -> void:
	var display_speed := speed_mph * 1.609344 if _unit_mode == &"METRIC" else speed_mph
	_speed_label.text = "%03d" % int(round(display_speed))
	_speed_bar.value = clampf(display_speed, 0.0, 132.0 if _unit_mode == &"METRIC" else 82.0)
	_speed_label.modulate = AMBER if grounded else CYAN


func apply_accessibility(interface: Dictionary) -> void:
	## Applies presentation-only settings without changing race simulation or
	## leaderboard eligibility. Base font sizes are cached so repeated changes do
	## not compound.
	_unit_mode = StringName(str(interface.get("units", "IMPERIAL")).to_upper())
	if _unit_mode not in [&"IMPERIAL", &"METRIC"]:
		_unit_mode = &"IMPERIAL"
	_high_contrast = bool(interface.get("high_contrast", false))
	_color_safe_mode = StringName(str(interface.get("color_safe_mode", "OFF")).to_upper())
	_text_scale = clampf(float(interface.get("text_scale", 1.0)), 0.8, 1.75)
	_apply_text_scale(_hud_root, _text_scale)
	if _speed_units_label != null:
		_speed_units_label.text = "KPH" if _unit_mode == &"METRIC" else "MPH"
	if _speed_bar != null:
		_speed_bar.max_value = 132.0 if _unit_mode == &"METRIC" else 82.0
	if _hud_root != null:
		_hud_root.modulate = Color(1.12, 1.12, 1.12, 1.0) if _high_contrast else Color.WHITE
	_refresh_accessible_flag_color()
	if _results_panel != null and _results_panel.visible:
		_queue_results_selection_visibility()


func _apply_text_scale(node: Node, text_scale: float) -> void:
	if node == null:
		return
	if node is Label:
		var label := node as Label
		if not label.has_meta(&"accessibility_base_font_size"):
			label.set_meta(&"accessibility_base_font_size", label.get_theme_font_size(&"font_size"))
		var base_size := int(label.get_meta(&"accessibility_base_font_size", 16))
		label.add_theme_font_size_override(&"font_size", maxi(roundi(float(base_size) * text_scale), 10))
	for child: Node in node.get_children():
		_apply_text_scale(child, text_scale)


func _refresh_accessible_flag_color() -> void:
	if _flag_label == null:
		return
	if _color_safe_mode == &"OFF":
		return
	# Blue/orange/purple remain separable across the supported color-safe modes;
	# flag text always carries the semantic meaning as well.
	if _flag_label.text.begins_with("GREEN"):
		_flag_label.modulate = Color("4db7ff")
	elif _flag_label.text.begins_with("YELLOW"):
		_flag_label.modulate = Color("ff9f2f")
	elif _flag_label.text.begins_with("RUN INVALID"):
		_flag_label.modulate = Color("d277ff")


func update_flow(value: float, boosting: bool) -> void:
	_flow_bar.value = clampf(value, 0.0, 100.0)
	var active_mode := StringName(_racecraft_snapshot.get(&"active_flow_mode", &"NONE"))
	_flow_label.text = (
		"FLOW  %03d  //  %s" % [int(round(value)), String(active_mode)]
		if active_mode != &"NONE"
		else "FLOW  %03d" % int(round(value))
	)
	_flow_label.modulate = CYAN if boosting else CREAM


func update_racecraft_state(snapshot: Dictionary) -> void:
	_racecraft_snapshot = snapshot.duplicate(true)
	update_flow(float(snapshot.get(&"flow", _flow_bar.value)), StringName(snapshot.get(&"active_flow_mode", &"NONE")) == &"SURGE")
	if _racecraft_label == null:
		return
	var tokens: PackedStringArray = []
	var technique := StringName(snapshot.get(&"technique", &"NONE"))
	if technique != &"NONE":
		tokens.append(String(technique).replace("_", " "))
	if bool(snapshot.get(&"slide_active", false)):
		tokens.append("SLIDE")
	var rut_value: Variant = snapshot.get(&"rut", {})
	if rut_value is Dictionary and not (rut_value as Dictionary).is_empty():
		var rut_outcome := StringName((rut_value as Dictionary).get(&"outcome", &""))
		if not rut_outcome.is_empty():
			tokens.append(String(rut_outcome).replace("_", " "))
	var draft := clampf(float(snapshot.get(&"draft_strength", 0.0)), 0.0, 1.0)
	if draft >= 0.08:
		tokens.append("DRAFT %02d%%" % roundi(draft * 100.0))
	var roost := clampf(float(snapshot.get(&"roost_pressure", 0.0)), 0.0, 1.0)
	if roost >= 0.08:
		tokens.append("ROOST %02d%%" % roundi(roost * 100.0))
	if tokens.is_empty():
		var recommended := StringName(snapshot.get(&"recommended_flow_mode", &"SURGE"))
		var cost := roundi(float(snapshot.get(&"recommended_flow_cost", 0.0)))
		tokens.append("SHIFT: %s  %d FLOW" % [String(recommended), cost])
	_racecraft_label.text = "RACECRAFT  //  " + "  //  ".join(tokens)
	_racecraft_label.modulate = WARNING if roost >= 0.45 else CYAN if draft >= 0.35 or technique != &"NONE" else CREAM


func show_racecraft_event(kind: StringName, payload: Dictionary) -> void:
	if kind in [&"LANDING", &"FLOW_DENIED", &"SLIDE_EXIT"]:
		return
	var label := String(kind).replace("_", " ")
	if kind == &"SKILL_LINE":
		label = "%s SKILL LINE" % String(payload.get(&"outcome", &"MISSED")).replace("_", " ")
	show_race_moment(label, 0, kind not in [&"FLOW_DENIED"])


func update_line(label: String, chain: int, multiplier: float, score: int, time_left: float) -> void:
	_line_label.text = label
	_line_label.modulate = CYAN if chain >= 4 else AMBER
	var has_active_line := not label.strip_edges().is_empty() or chain > 1 or score > 0
	_line_score_label.text = (
		("LINE %06d" % score if chain <= 1 else "LINE %06d   x%.2f   CHAIN %02d   %.1fs" % [score, multiplier, chain, time_left])
		if has_active_line
		else ""
	)
	if chain == 4 or label.begins_with("ROUTE:"):
		_pulse_highlight()


func update_contract(title: String, current: int, target: int, completed: bool) -> void:
	_contract_label.text = "%s   //   %s" % [title, "COMPLETE +$350 +1 TOKEN" if completed else "%d / %d" % [current, target]]
	_contract_label.modulate = CYAN if completed else CREAM


func update_modifier(title: String, description: String) -> void:
	_modifier_label.text = "DAILY: %s   //   %s" % [title, description]


func show_breakdown(summary: String) -> void:
	_breakdown_label.text = summary


func show_feat(title: String) -> void:
	_queue_reward("FEAT UNLOCKED  //  %s  //  +1 STYLE TOKEN" % title, 4.0, CYAN)


func get_reward_notification_state() -> Dictionary:
	return {
		&"text": _reward_label.text if _reward_label != null else "",
		&"remaining_seconds": _reward_time,
		&"queued": _reward_queue.size(),
	}


func update_race_time(elapsed_usec: int, best_usec: int, checkpoint: int, total: int) -> void:
	_timer_label.text = _format_usec(elapsed_usec)
	var best_text := "--:--.---" if best_usec < 0 else _format_usec(best_usec)
	_best_label.text = "PB %s  //  ROOK %s" % [best_text, _format_usec(_rival_target_usec)] if _rival_target_usec > 0 else "BEST  %s" % best_text
	_checkpoint_label.text = "GATE  %02d / %02d" % [mini(checkpoint + 1, total), total]


func update_field(position: int, total: int, gap_ahead: float, gap_behind: float) -> void:
	if _activity in [&"FREESTYLE", &"DISCOVERY"]:
		return
	var gap_text := "PACK TIGHT"
	if position <= 1 and gap_behind >= 0.0:
		gap_text = "LEAD +%.1fm" % gap_behind
	elif gap_ahead >= 0.0:
		gap_text = "NEXT %.1fm" % gap_ahead
	_field_label.text = "POSITION  P%d / %d  //  %s" % [position, total, gap_text]
	_field_label.modulate = CYAN if position <= 1 else CREAM


func show_race_moment(label: String, _points: int, positive: bool) -> void:
	if _activity in [&"FREESTYLE", &"DISCOVERY"]:
		return
	_message_label.text = label
	_message_label.modulate = CYAN if positive else Color("ff806b")
	_message_time = 1.45
	if positive:
		_pulse_highlight()
	else:
		_pulse_warning()


func update_freestyle(time_left_usec: int, score: int, combo: int, last_airtime: float) -> void:
	_timer_label.text = _format_usec(time_left_usec)
	_best_label.text = "SCORE  %06d   BEST  %06d" % [score, Profile.best_freestyle_score]
	_checkpoint_label.text = "COMBO  x%d   AIR %.1fs" % [combo, last_airtime]
	_compass_label.visible = false


func update_discovery(elapsed_usec: int, current: int, total: int, compass_angle: float, distance: float) -> void:
	_timer_label.text = _format_usec(elapsed_usec)
	_best_label.text = "NEAREST  %03dm" % int(round(distance))
	_checkpoint_label.text = "SALVAGE  %02d / %02d" % [current, total]
	_compass_label.visible = current < total
	_compass_label.rotation = compass_angle


func _build_hud() -> void:
	var root := Control.new()
	_hud_root = root
	root.name = "HudRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var top_band := ColorRect.new()
	top_band.color = Color(0.02, 0.025, 0.03, 0.7)
	top_band.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_band.offset_bottom = 86.0
	top_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top_band)

	var accent := ColorRect.new()
	accent.color = AMBER
	accent.set_anchors_preset(Control.PRESET_TOP_WIDE)
	accent.offset_top = 82.0
	accent.offset_bottom = 86.0
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(accent)

	_title_label = _make_label(root, "RIDING DIRTY  //  %s" % _build_id().to_upper(), 22, CREAM)
	_anchor_rect(_title_label, Vector2.ZERO, Rect2(28.0, 23.0, 560.0, 44.0))

	_timer_label = _make_label(root, "00:00.000", 46, CREAM)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_anchor_rect(_timer_label, Vector2(0.5, 0.0), Rect2(-180.0, 10.0, 360.0, 64.0))

	_best_label = _make_label(root, "BEST  --:--.---", 18, Color("a8b4bd"))
	_best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_anchor_rect(_best_label, Vector2(1.0, 0.0), Rect2(-350.0, 18.0, 320.0, 28.0))

	_checkpoint_label = _make_label(root, "GATE  01 / 18", 19, AMBER)
	_checkpoint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_anchor_rect(_checkpoint_label, Vector2(1.0, 0.0), Rect2(-350.0, 46.0, 320.0, 28.0))

	var speed_panel := ColorRect.new()
	speed_panel.color = DARK
	_anchor_rect(speed_panel, Vector2.ONE, Rect2(-235.0, -202.0, 205.0, 168.0))
	speed_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(speed_panel)

	_speed_label = _make_label(root, "000", 64, AMBER)
	_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_anchor_rect(_speed_label, Vector2.ONE, Rect2(-230.0, -202.0, 155.0, 84.0))
	_speed_units_label = _make_label(root, "MPH", 18, CREAM)
	_anchor_rect(_speed_units_label, Vector2.ONE, Rect2(-74.0, -163.0, 50.0, 32.0))

	_speed_bar = ProgressBar.new()
	_speed_bar.min_value = 0.0
	_speed_bar.max_value = 82.0
	_speed_bar.value = 0.0
	_speed_bar.show_percentage = false
	_anchor_rect(_speed_bar, Vector2.ONE, Rect2(-220.0, -108.0, 180.0, 12.0))
	var bar_background := StyleBoxFlat.new()
	bar_background.bg_color = Color("263039")
	bar_background.corner_radius_top_left = 5
	bar_background.corner_radius_top_right = 5
	bar_background.corner_radius_bottom_left = 5
	bar_background.corner_radius_bottom_right = 5
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = AMBER
	bar_fill.corner_radius_top_left = 5
	bar_fill.corner_radius_top_right = 5
	bar_fill.corner_radius_bottom_left = 5
	bar_fill.corner_radius_bottom_right = 5
	_speed_bar.add_theme_stylebox_override(&"background", bar_background)
	_speed_bar.add_theme_stylebox_override(&"fill", bar_fill)
	root.add_child(_speed_bar)

	_flow_label = _make_label(root, "FLOW  000", 16, CREAM)
	_anchor_rect(_flow_label, Vector2.ONE, Rect2(-220.0, -88.0, 180.0, 25.0))
	_flow_bar = ProgressBar.new()
	_flow_bar.min_value = 0.0
	_flow_bar.max_value = 100.0
	_flow_bar.value = 0.0
	_flow_bar.show_percentage = false
	_anchor_rect(_flow_bar, Vector2.ONE, Rect2(-220.0, -55.0, 180.0, 10.0))
	_flow_bar.add_theme_stylebox_override(&"background", bar_background.duplicate())
	var flow_fill := bar_fill.duplicate() as StyleBoxFlat
	flow_fill.bg_color = CYAN
	_flow_bar.add_theme_stylebox_override(&"fill", flow_fill)
	root.add_child(_flow_bar)

	_racecraft_label = _make_label(root, "RACECRAFT  //  SHIFT: SURGE  35 FLOW", 14, CREAM)
	_racecraft_label.name = "RacecraftStatusLabel"
	_racecraft_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_racecraft_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_racecraft_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_anchor_rect(_racecraft_label, Vector2.ONE, Rect2(-560.0, -92.0, 315.0, 58.0))

	_controls_panel = ColorRect.new()
	_controls_panel.name = "ControlHintsPanel"
	_controls_panel.color = Color(0.035, 0.045, 0.055, 0.72)
	_anchor_rect(_controls_panel, Vector2(0.0, 1.0), Rect2(28.0, -104.0, 620.0, 70.0))
	_controls_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_controls_panel)
	_controls_label = _make_label(root, "", 14, Color("c7d0d5"))
	_controls_label.name = "ControlHintsLabel"
	_anchor_rect(_controls_label, Vector2(0.0, 1.0), Rect2(42.0, -98.0, 592.0, 56.0))
	_controls_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_controls_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	_countdown_label = _make_label(root, "", 132, AMBER)
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_anchor_rect(_countdown_label, Vector2(0.5, 0.5), Rect2(-260.0, -150.0, 520.0, 220.0))

	_gate_launch_label = _make_label(root, "", 22, AMBER)
	_gate_launch_label.name = "GateLaunchFeedback"
	_gate_launch_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gate_launch_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_gate_launch_label.visible = false
	_anchor_rect(_gate_launch_label, Vector2(0.5, 0.5), Rect2(-500.0, -225.0, 1000.0, 64.0))

	_message_label = _make_label(root, "", 27, CREAM)
	_message_label.name = "CenterMessage"
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_anchor_rect(_message_label, Vector2(0.5, 0.5), Rect2(-500.0, 70.0, 1000.0, 140.0))
	_compass_label = _make_label(root, "▲", 54, CYAN)
	_compass_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_compass_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_anchor_rect(_compass_label, Vector2(0.5, 0.0), Rect2(-60.0, 100.0, 120.0, 84.0))
	_compass_label.pivot_offset = Vector2(60.0, 42.0)
	_compass_label.visible = false
	_reward_label = _make_label(root, "", 22, CYAN)
	_reward_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_anchor_rect(_reward_label, Vector2(1.0, 0.0), Rect2(-410.0, 105.0, 380.0, 42.0))

	_contract_label = _make_label(root, "", 17, CREAM)
	_anchor_rect(_contract_label, Vector2.ZERO, Rect2(28.0, 100.0, 720.0, 32.0))
	_modifier_label = _make_label(root, "", 15, Color("a8b4bd"))
	_modifier_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_anchor_rect(_modifier_label, Vector2(1.0, 0.0), Rect2(-680.0, 148.0, 650.0, 30.0))
	_line_label = _make_label(root, "", 31, AMBER)
	_line_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_anchor_rect(_line_label, Vector2(0.5, 1.0), Rect2(-360.0, -276.0, 720.0, 42.0))
	_line_score_label = _make_label(root, "", 17, CREAM)
	_line_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_anchor_rect(_line_score_label, Vector2(0.5, 1.0), Rect2(-360.0, -236.0, 720.0, 30.0))
	_breakdown_label = _make_label(root, "", 19, CYAN)
	_breakdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_anchor_rect(_breakdown_label, Vector2(0.5, 0.5), Rect2(-520.0, 214.0, 1040.0, 38.0))

	_course_map = CourseMapControl.new()
	_course_map.name = "CourseMiniMap"
	_anchor_rect(_course_map, Vector2(1.0, 0.0), Rect2(-252.0, 192.0, 222.0, 174.0))
	root.add_child(_course_map)
	_field_label = _make_label(root, "FIELD 12  //  CLUB RACE", 16, CREAM)
	_field_label.name = "FieldStatus"
	_field_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_anchor_rect(_field_label, Vector2(1.0, 0.0), Rect2(-330.0, 370.0, 300.0, 28.0))

	_phase_label = _make_label(root, "STAGING", 15, AMBER)
	_phase_label.name = "RacePhase"
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_anchor_rect(_phase_label, Vector2(0.5, 0.0), Rect2(-110.0, 91.0, 220.0, 24.0))
	_lap_label = _make_label(root, "LAP 1 / 1", 22, CREAM)
	_lap_label.name = "LapStatus"
	_lap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_anchor_rect(_lap_label, Vector2(0.5, 0.0), Rect2(-110.0, 114.0, 220.0, 30.0))
	_flag_label = _make_label(root, "GREEN FLAG", 14, CYAN)
	_flag_label.name = "RaceFlag"
	_anchor_rect(_flag_label, Vector2.ZERO, Rect2(28.0, 144.0, 260.0, 25.0))
	_integrity_label = _make_label(root, "", 23, WARNING)
	_integrity_label.name = "IntegrityWarning"
	_integrity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_anchor_rect(_integrity_label, Vector2(0.5, 0.0), Rect2(-330.0, 154.0, 660.0, 36.0))
	_integrity_label.visible = false

	_build_live_standings(root)
	_build_academy_panel(root)
	_build_results_panel(root)

	_paused_label = _make_label(root, "PAUSED\nESC / START  RESUME\nF1 / BACK  SETTINGS", 48, CREAM)
	_paused_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_paused_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_paused_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_paused_label.visible = false

	_highlight_overlay = ColorRect.new()
	_highlight_overlay.color = Color.TRANSPARENT
	_highlight_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_highlight_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_highlight_overlay)


func _build_live_standings(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.name = "LiveStandings"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override(&"panel", _make_panel_style(Color(0.025, 0.034, 0.041, 0.82), AMBER, 2))
	_anchor_rect(panel, Vector2.ZERO, Rect2(28.0, 190.0, 286.0, 224.0))
	root.add_child(panel)
	_standings_panel = panel

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override(&"margin_left", 12)
	margin.add_theme_constant_override(&"margin_right", 12)
	margin.add_theme_constant_override(&"margin_top", 9)
	margin.add_theme_constant_override(&"margin_bottom", 9)
	panel.add_child(margin)
	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override(&"separation", 2)
	margin.add_child(stack)
	_standings_title = _make_label(stack, "LIVE  //  FIELD", 13, AMBER)
	_standings_title.clip_text = true
	_standings_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	for index: int in LIVE_STANDING_ROWS:
		var row := _make_label(stack, "P%02d  --" % (index + 1), 15, CREAM)
		row.name = "Standing%02d" % (index + 1)
		row.custom_minimum_size = Vector2(0.0, 26.0)
		_standings_rows.append(row)


func _build_academy_panel(root: Control) -> void:
	_academy_panel = PanelContainer.new()
	_academy_panel.name = "AcademyObjectives"
	_academy_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_academy_panel.add_theme_stylebox_override(&"panel", _make_panel_style(Color(0.025, 0.05, 0.035, 0.9), Color("7bd66f"), 2))
	_anchor_rect(_academy_panel, Vector2.ZERO, Rect2(28.0, 190.0, 390.0, 180.0))
	root.add_child(_academy_panel)
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override(&"margin_left", 14)
	margin.add_theme_constant_override(&"margin_right", 14)
	margin.add_theme_constant_override(&"margin_top", 10)
	margin.add_theme_constant_override(&"margin_bottom", 10)
	_academy_panel.add_child(margin)
	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override(&"separation", 5)
	margin.add_child(stack)
	_academy_title_label = _make_label(stack, "ACADEMY", 17, Color("7bd66f"))
	_academy_title_label.clip_text = true
	_academy_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_academy_description_label = _make_label(stack, "", 12, CREAM)
	_academy_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_academy_description_label.custom_minimum_size.y = 38.0
	for index: int in ACADEMY_OBJECTIVE_LIMIT:
		var objective_label := _make_label(stack, "", 14, CREAM)
		objective_label.name = "AcademyObjective%d" % (index + 1)
		objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		objective_label.custom_minimum_size.y = 30.0
		_academy_objective_labels.append(objective_label)
	_academy_panel.visible = false


func _build_results_panel(root: Control) -> void:
	_results_panel = PanelContainer.new()
	_results_panel.name = "FullRaceResults"
	_results_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_results_panel.add_theme_stylebox_override(&"panel", _make_panel_style(Color(0.018, 0.026, 0.032, 0.97), AMBER, 3))
	_anchor_rect(_results_panel, Vector2(0.5, 0.5), Rect2(-470.0, -315.0, 940.0, 630.0))
	root.add_child(_results_panel)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override(&"margin_left", 28)
	margin.add_theme_constant_override(&"margin_right", 28)
	margin.add_theme_constant_override(&"margin_top", 20)
	margin.add_theme_constant_override(&"margin_bottom", 18)
	_results_panel.add_child(margin)
	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override(&"separation", 6)
	margin.add_child(stack)

	_results_title = _make_label(stack, "RACE COMPLETE", 34, AMBER)
	_results_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_results_summary = _make_label(stack, "", 18, CREAM)
	_results_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_results_competition = _make_label(stack, "", 13, CYAN)
	_results_competition.name = "CompetitionSummary"
	_results_competition.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_results_competition.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_results_competition.custom_minimum_size = Vector2(0.0, 56.0)
	_results_heading_label = _make_label(stack, "POS     RIDER                         STATUS             TIME / GAP", 14, MUTED)
	_results_heading_label.add_theme_constant_override(&"outline_size", 1)

	_results_scroll = ScrollContainer.new()
	_results_scroll.name = "ClassificationScroll"
	_results_scroll.custom_minimum_size = Vector2(0.0, 288.0)
	_results_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_results_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_results_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	_results_scroll.gui_input.connect(_on_results_scroll_gui_input)
	stack.add_child(_results_scroll)
	_results_rows = VBoxContainer.new()
	_results_rows.name = "ClassificationRows"
	_results_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_results_rows.add_theme_constant_override(&"separation", 2)
	_results_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_results_scroll.add_child(_results_rows)

	_results_stats = _make_label(stack, "", 14, Color("b8c4ca"))
	_results_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_results_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_results_stats.custom_minimum_size = Vector2(0.0, 40.0)
	_results_footer = _make_label(stack, "ENTER / X  RUN AGAIN     G / B  GARAGE", 15, CYAN)
	_results_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_results_footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_results_footer.custom_minimum_size = Vector2(0.0, 38.0)
	_results_panel.visible = false


func _make_panel_style(background: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	return style


func _make_label(parent: Control, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.set_meta(&"accessibility_base_font_size", font_size)
	label.add_theme_font_size_override(&"font_size", maxi(roundi(float(font_size) * _text_scale), 10))
	label.add_theme_color_override(&"font_color", color)
	label.add_theme_color_override(&"font_outline_color", Color(0.01, 0.01, 0.015, 0.9))
	label.add_theme_constant_override(&"outline_size", maxi(2, int(font_size * 0.08)))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _anchor_rect(control: Control, anchor: Vector2, rect: Rect2) -> void:
	control.anchor_left = anchor.x
	control.anchor_right = anchor.x
	control.anchor_top = anchor.y
	control.anchor_bottom = anchor.y
	control.offset_left = rect.position.x
	control.offset_top = rect.position.y
	control.offset_right = rect.position.x + rect.size.x
	control.offset_bottom = rect.position.y + rect.size.y


func _build_id() -> String:
	var version := str(ProjectSettings.get_setting("application/config/version", "development"))
	return version.split("-", true, 1)[1] if "-" in version else version


func _update_control_hints(delta: float) -> void:
	if _controls_panel == null or _controls_label == null:
		return
	if _control_hint_pinned:
		_set_control_hint_opacity(move_toward(_control_hint_opacity, 1.0, delta * 6.0))
		return
	if _control_hint_hold_time > 0.0:
		_control_hint_hold_time = maxf(_control_hint_hold_time - delta, 0.0)
		_set_control_hint_opacity(move_toward(_control_hint_opacity, 1.0, delta * 6.0))
		return
	_set_control_hint_opacity(
		move_toward(_control_hint_opacity, 0.0, delta / CONTROL_HINT_FADE_SECONDS)
	)


func _set_control_hint_opacity(opacity: float) -> void:
	_control_hint_opacity = clampf(opacity, 0.0, 1.0)
	var visible := _control_hint_opacity > 0.01
	_controls_panel.visible = visible
	_controls_label.visible = visible
	_controls_panel.modulate = Color(1.0, 1.0, 1.0, _control_hint_opacity)
	_controls_label.modulate = Color(1.0, 1.0, 1.0, _control_hint_opacity)


func _refresh_academy_panel() -> void:
	if _academy_panel == null:
		return
	var active := _activity == &"ACADEMY" and not _academy_lesson.is_empty() and not is_results_visible()
	_academy_panel.visible = active
	if not active:
		return
	var lesson_name := str(_academy_lesson.get(&"display_name", "RIDE LESSON")).to_upper()
	var category := String(_academy_lesson.get(&"category", &"FOUNDATIONS")).replace("_", " ")
	_academy_title_label.text = "ACADEMY  //  %s  //  %s" % [category, lesson_name]
	_academy_description_label.text = str(_academy_lesson.get(&"description", "Complete the marked objectives."))
	var objectives := _academy_lesson.get(&"objectives", []) as Array
	for index: int in _academy_objective_labels.size():
		var label := _academy_objective_labels[index]
		if index >= objectives.size() or not objectives[index] is Dictionary:
			label.text = ""
			label.visible = false
			continue
		label.text = _academy_live_objective_text(objectives[index] as Dictionary, index)
		label.visible = true


func _academy_live_objective_text(objective: Dictionary, index: int) -> String:
	var metric := StringName(objective.get(&"metric", &""))
	var metric_name := String(metric).replace("_", " ").to_upper()
	var threshold := _academy_threshold_text(objective, &"bronze")
	var live_text := "LIVE --"
	if _academy_live_metrics.has(metric):
		var value := float(_academy_live_metrics.get(metric, 0.0))
		live_text = "LIVE %s" % _academy_metric_value(metric, value)
		if _academy_objective_met(objective, value, &"bronze"):
			live_text += "  PASS"
	return "%d  %s  //  %s  //  PASS %s" % [index + 1, metric_name, live_text, threshold]


func _update_academy_live_metrics(snapshot: Dictionary) -> void:
	if _activity != &"ACADEMY" or _academy_lesson.is_empty():
		return
	var checkpoint_count := maxi(int(snapshot.get(&"checkpoint_count", 0)), 0)
	var laps_completed := maxi(int(snapshot.get(&"laps_completed", 0)), 0)
	var current_checkpoint := maxi(int(snapshot.get(&"current_checkpoint", 0)), 0)
	var gates_completed := laps_completed * checkpoint_count + current_checkpoint
	_academy_live_metrics[&"gates_completed"] = maxf(
		float(_academy_live_metrics.get(&"gates_completed", 0.0)), float(gates_completed)
	)
	var integrity_value: Variant = snapshot.get(&"integrity", _integrity_snapshot)
	if integrity_value is Dictionary:
		var integrity := integrity_value as Dictionary
		var incidents := integrity.get(&"incidents", {}) as Dictionary
		var resets := int(incidents.get(&"resets_consumed", incidents.get(&"manual_resets", 0)))
		_academy_live_metrics[&"resets"] = resets
		_academy_live_metrics[&"successful_rejoins"] = resets
		_academy_live_metrics[&"off_course_seconds"] = float(integrity.get(&"off_course_time", 0.0))
	var racecraft_value: Variant = snapshot.get(&"racecraft", _racecraft_snapshot)
	if racecraft_value is Dictionary:
		var counters := (racecraft_value as Dictionary).get(&"counters", {}) as Dictionary
		var counter_metrics := {
			&"RUT_RAIL": &"rut_rails", &"CONTROLLED_SLIDE": &"controlled_slides",
			&"PUMP": &"pumps", &"SCRUB": &"scrubs", &"COMPOSE_SAVE": &"compose_saves",
			&"DAB": &"dabs", &"CLUTCH_POP": &"clutch_pops", &"DRAFT_SLINGSHOT": &"draft_slingshots",
			&"ROOST_DEFENSE": &"roost_defenses", &"FLOW_RAIL": &"rail_spends", &"BRACE_SAVE": &"brace_saves",
		}
		for raw_kind: Variant in counter_metrics.keys():
			_academy_live_metrics[counter_metrics[raw_kind]] = float(counters.get(raw_kind, 0))
	_refresh_academy_panel()


func _academy_objective_met(objective: Dictionary, value: float, grade_key: StringName) -> bool:
	var threshold := float(objective.get(grade_key, objective.get(&"bronze", 0.0)))
	match StringName(objective.get(&"comparison", &"AT_LEAST")):
		&"AT_MOST": return value <= threshold
		&"EQUAL": return is_equal_approx(value, threshold)
		_: return value >= threshold


func _academy_threshold_text(objective: Dictionary, grade_key: StringName) -> String:
	var metric := StringName(objective.get(&"metric", &""))
	var value := float(objective.get(grade_key, objective.get(&"bronze", 0.0)))
	var operator := ">="
	match StringName(objective.get(&"comparison", &"AT_LEAST")):
		&"AT_MOST": operator = "<="
		&"EQUAL": operator = "="
	return "%s %s" % [operator, _academy_metric_value(metric, value)]


func _academy_metric_value(metric: StringName, value: float) -> String:
	var metric_text := String(metric)
	if metric_text.contains("seconds"):
		return "%.2fs" % value
	if metric == &"launch_speed":
		return "%.1f m/s" % value
	if metric_text.contains("error"):
		return "%.2f" % value
	if is_equal_approx(value, roundf(value)):
		return "%d" % roundi(value)
	return "%.1f" % value


func _academy_grade_text(stars: int) -> String:
	var output := "["
	for index: int in 3:
		output += "*" if index < clampi(stars, 0, 3) else "-"
	return output + "]"


func _refresh_live_standings() -> void:
	if _standings_rows.is_empty():
		return
	var visible_racers: Array[Dictionary] = []
	var player_racer: Dictionary = {}
	for index: int in _classification.size():
		var racer := _classification[index]
		if _is_player_result(racer):
			player_racer = racer
		if visible_racers.size() < LIVE_STANDING_ROWS:
			visible_racers.append(racer)
	if not player_racer.is_empty() and not visible_racers.has(player_racer):
		visible_racers[LIVE_STANDING_ROWS - 1] = player_racer
	var total := _classification.size()
	var conditions := String(_session_format).replace("_", " ")
	if _session_weather not in [&"", &"CLEAR"]:
		conditions += " / %s" % String(_session_weather).replace("_", " ")
	_standings_title.text = "LIVE  //  %s  //  FIELD %d" % [conditions, total] if total > 0 else "LIVE  //  FIELD"
	for index: int in _standings_rows.size():
		var label := _standings_rows[index]
		if index >= visible_racers.size():
			label.text = ""
			continue
		var racer := visible_racers[index]
		label.text = _live_standing_text(racer, index)
		var position := int(racer.get(&"position", index + 1))
		var status := StringName(racer.get(&"status", &"RUNNING"))
		if _is_player_result(racer):
			label.modulate = AMBER
		elif status in [&"DNF", &"DNS", &"ELIMINATED"]:
			label.modulate = MUTED
		elif position == 1:
			label.modulate = CYAN
		else:
			label.modulate = CREAM


func _live_standing_text(racer: Dictionary, fallback_index: int) -> String:
	var position := int(racer.get(&"position", fallback_index + 1))
	var number := int(racer.get(&"number", 0))
	var rider_name := str(racer.get(&"display_name", racer.get(&"rider_id", "RIDER"))).to_upper()
	if rider_name.length() > 11:
		rider_name = rider_name.left(11)
	var status := StringName(racer.get(&"status", &"RUNNING"))
	var suffix := "LEADER" if position == 1 else ""
	var gap_usec := int(racer.get(&"gap_usec", -1))
	if status in [&"DNF", &"DNS", &"ELIMINATED"]:
		suffix = String(status)
	elif gap_usec > 0:
		suffix = "+%.1fs" % (float(gap_usec) / 1_000_000.0)
	elif racer.has(&"gap_m"):
		suffix = "+%.0fm" % float(racer.get(&"gap_m", 0.0))
	elif position > 1 and racer.has(&"total_progress") and not _classification.is_empty():
		var leader_progress := float(_classification[0].get(&"total_progress", 0.0))
		var racer_progress := float(racer.get(&"total_progress", 0.0))
		suffix = "+%.0fm" % maxf(leader_progress - racer_progress, 0.0)
	elif position > 1:
		suffix = "PUSH"
	var holeshot := "*" if StringName(racer.get(&"rider_id", &"")) == _holeshot_rider_id else " "
	return "P%02d%s #%02d %-11s %s" % [position, holeshot, number, rider_name, suffix]


func _populate_results_rows(classification: Array[Dictionary]) -> void:
	for child: Node in _results_rows.get_children():
		_results_rows.remove_child(child)
		child.queue_free()
	_results_row_panels.clear()
	_results_selected_index = -1
	_results_player_index = -1
	for index: int in classification.size():
		var racer := classification[index]
		var is_player := _is_player_result(racer)
		var row_panel := PanelContainer.new()
		row_panel.name = "ResultRow%02d" % index
		row_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row_panel.custom_minimum_size = Vector2(0.0, 31.0)
		_results_rows.add_child(row_panel)
		_results_row_panels.append(row_panel)
		if is_player and _results_player_index < 0:
			_results_player_index = index
		var columns := HBoxContainer.new()
		columns.mouse_filter = Control.MOUSE_FILTER_IGNORE
		columns.add_theme_constant_override(&"separation", 8)
		row_panel.add_child(columns)
		var position := int(racer.get(&"position", index + 1))
		var position_label := _make_label(columns, "P%02d" % position, 16, AMBER if is_player else CREAM)
		position_label.custom_minimum_size.x = 58.0
		var number := int(racer.get(&"number", 0))
		var rider_name := str(racer.get(&"display_name", racer.get(&"rider_id", "RIDER"))).to_upper()
		var rider_label := _make_label(columns, "#%02d  %s%s" % [number, rider_name, "  [HOLESHOT]" if StringName(racer.get(&"rider_id", &"")) == _holeshot_rider_id else ""], 16, AMBER if is_player else CREAM)
		rider_label.custom_minimum_size.x = 350.0
		rider_label.clip_text = true
		rider_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var status := StringName(racer.get(&"status", &"FINISHED"))
		var penalty_usec := int(racer.get(&"penalty_usec", 0))
		var status_text := String(status).replace("_", " ")
		if penalty_usec > 0:
			status_text += "  +%.1fs" % (float(penalty_usec) / 1_000_000.0)
		var status_label := _make_label(columns, status_text, 14, WARNING if penalty_usec > 0 else MUTED)
		status_label.custom_minimum_size.x = 176.0
		status_label.clip_text = true
		status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var time_label := _make_label(columns, _result_time_text(racer, position), 16, CYAN if position == 1 else CREAM)
		time_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_results_selected_index = _results_player_index if _results_player_index >= 0 else (0 if not _results_row_panels.is_empty() else -1)
	_refresh_results_row_styles()


func _refresh_results_row_styles() -> void:
	for index: int in _results_row_panels.size():
		var row_panel := _results_row_panels[index]
		if not is_instance_valid(row_panel):
			continue
		var is_player := index == _results_player_index
		var is_selected := index == _results_selected_index
		var background := Color(0.12, 0.16, 0.19, 0.44 if index % 2 == 0 else 0.22)
		var border := Color.TRANSPARENT
		var border_width := 0
		if is_player:
			background = Color(1.0, 0.71, 0.18, 0.22 if is_selected else 0.16)
			border = AMBER
			border_width = 2 if is_selected else 1
		elif is_selected:
			background = Color(0.10, 0.30, 0.38, 0.72)
			border = CYAN
			border_width = 2
		row_panel.add_theme_stylebox_override(&"panel", _make_panel_style(background, border, border_width))


func _populate_academy_results(evaluation: Dictionary) -> void:
	for child: Node in _results_rows.get_children():
		_results_rows.remove_child(child)
		child.queue_free()
	_results_row_panels.clear()
	_results_selected_index = -1
	_results_player_index = -1
	var objective_results := evaluation.get(&"objective_results", []) as Array
	for index: int in mini(objective_results.size(), ACADEMY_OBJECTIVE_LIMIT):
		if not objective_results[index] is Dictionary:
			continue
		var objective := objective_results[index] as Dictionary
		var metric := StringName(objective.get(&"metric", &""))
		var metric_name := String(metric).replace("_", " ").to_upper()
		var grade := clampi(int(objective.get(&"grade", 0)), 0, 3)
		var measured := _academy_metric_value(metric, float(objective.get(&"value", 0.0)))
		var row_panel := PanelContainer.new()
		row_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row_panel.custom_minimum_size = Vector2(0.0, 88.0)
		var passed := grade > 0
		row_panel.add_theme_stylebox_override(
			&"panel", _make_panel_style(
				Color(0.12, 0.24, 0.16, 0.48) if passed else Color(0.28, 0.11, 0.1, 0.48),
				Color("7bd66f") if passed else WARNING, 1
			)
		)
		_results_rows.add_child(row_panel)
		var margin := MarginContainer.new()
		margin.add_theme_constant_override(&"margin_left", 14)
		margin.add_theme_constant_override(&"margin_right", 14)
		margin.add_theme_constant_override(&"margin_top", 8)
		margin.add_theme_constant_override(&"margin_bottom", 8)
		row_panel.add_child(margin)
		var stack := VBoxContainer.new()
		stack.add_theme_constant_override(&"separation", 4)
		margin.add_child(stack)
		var measured_label := _make_label(
			stack,
			"%d  %s  //  RESULT %s  //  %s" % [index + 1, metric_name, measured, _academy_grade_text(grade)],
			18, Color("7bd66f") if passed else WARNING
		)
		measured_label.clip_text = true
		measured_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var thresholds := _make_label(
			stack,
			"BRONZE %s     SILVER %s     GOLD %s" % [
				_academy_threshold_text(objective, &"bronze"),
				_academy_threshold_text(objective, &"silver"),
				_academy_threshold_text(objective, &"gold"),
			],
			14, CREAM
		)
		thresholds.clip_text = true
		thresholds.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if _results_rows.get_child_count() == 0:
		var unavailable := _make_label(_results_rows, "NO ACADEMY GRADING DATA", 18, WARNING)
		unavailable.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _result_time_text(racer: Dictionary, position: int) -> String:
	var status := StringName(racer.get(&"status", &"FINISHED"))
	if status in [&"DNF", &"DNS", &"ELIMINATED"]:
		return String(status)
	var effective_usec := int(racer.get(&"effective_time_usec", -1))
	if effective_usec < 0:
		var finish_usec := int(racer.get(&"finish_usec", -1))
		if finish_usec >= 0:
			effective_usec = finish_usec + int(racer.get(&"penalty_usec", 0))
	if position == 1 and effective_usec >= 0:
		return _format_usec(effective_usec)
	var gap_usec := int(racer.get(&"gap_usec", -1))
	if gap_usec >= 0:
		return "+%s" % _format_gap_usec(gap_usec)
	return _format_usec(effective_usec) if effective_usec >= 0 else "--:--.---"


func _results_heading(result: Dictionary) -> String:
	var academy_value: Variant = result.get(&"academy_evaluation", {})
	if academy_value is Dictionary and not (academy_value as Dictionary).is_empty():
		var evaluation := academy_value as Dictionary
		var stars := clampi(int(evaluation.get(&"stars", 0)), 0, 3)
		return "ACADEMY COMPLETE  //  %s" % _academy_grade_text(stars)
	var medal := StringName(result.get(&"medal", &"FINISHER"))
	var valid := bool(result.get(&"valid", true))
	return "RACE COMPLETE  //  %s" % (String(medal) if valid else "UNCLASSIFIED")


func _results_summary_text(result: Dictionary) -> String:
	var academy_value: Variant = result.get(&"academy_evaluation", {})
	if academy_value is Dictionary and not (academy_value as Dictionary).is_empty():
		var evaluation := academy_value as Dictionary
		var lesson_name := str(evaluation.get(&"display_name", evaluation.get(&"lesson_id", "ACADEMY LESSON"))).to_upper()
		var status := "PASSED" if bool(evaluation.get(&"passed", false)) else "OBJECTIVES NOT MET"
		var time_usec := int(result.get(&"player_time_usec", -1))
		return "%s  //  %s%s" % [lesson_name, status, "  //  %s" % _format_usec(time_usec) if time_usec >= 0 else ""]
	var player_position := int(result.get(&"player_position", _find_player_position()))
	var field_size := maxi(_classification.size(), 1)
	var player_time_usec := int(result.get(&"player_time_usec", -1))
	var penalty_usec := int(result.get(&"player_penalty_usec", 0))
	var summary := "P%d / %d" % [maxi(player_position, 1), field_size]
	if player_time_usec >= 0:
		summary += "  //  %s" % _format_usec(player_time_usec + penalty_usec)
	if penalty_usec > 0:
		summary += "  //  PENALTY +%.1fs" % (float(penalty_usec) / 1_000_000.0)
	var fastest_lap := int(result.get(&"fastest_lap_usec", -1))
	if fastest_lap >= 0:
		summary += "  //  FASTEST LAP %s" % _format_usec(fastest_lap)
	if not bool(result.get(&"valid", true)):
		summary += "  //  %s" % str(result.get(&"validity_reason", "RUN INVALID")).to_upper()
	return summary


func _results_stats_text(result: Dictionary) -> String:
	var academy_value: Variant = result.get(&"academy_evaluation", {})
	if academy_value is Dictionary and not (academy_value as Dictionary).is_empty():
		var evaluation := academy_value as Dictionary
		var best_text := "NEW BEST  //  %d STAR%s" % [
			int(evaluation.get(&"best_stars", evaluation.get(&"stars", 0))),
			"S" if int(evaluation.get(&"best_stars", evaluation.get(&"stars", 0))) != 1 else "",
		] if bool(evaluation.get(&"new_best", false)) else "BEST HELD  //  %d STARS" % int(evaluation.get(&"best_stars", 0))
		var credited := evaluation.get(&"credited_rewards", {}) as Dictionary
		var credited_cash := int(credited.get(&"cash", credited.get(&"credits", 0)))
		var credited_reputation := int(credited.get(&"reputation", 0))
		var reward_text := "LESSON REWARD CREDITED  +$%d  //  +%d REP" % [credited_cash, credited_reputation]
		if credited_cash == 0 and credited_reputation == 0:
			reward_text = "LESSON REWARD  ALREADY CLAIMED" if bool(evaluation.get(&"passed", false)) else "LESSON REWARD  NOT EARNED"
		return "%s\n%s" % [best_text, reward_text]
	var stats := "OVERTAKES %d  //  CONTACTS %d  //  CRASHES %d  //  RESETS %d  //  OFF COURSE %d" % [
		int(result.get(&"overtakes", 0)), int(result.get(&"contacts", 0)),
		int(result.get(&"crashes", 0)), int(result.get(&"reset_count", 0)),
		int(result.get(&"off_course_count", 0)),
	]
	var rewards_value: Variant = result.get(&"rewards", {})
	if rewards_value is Dictionary:
		var rewards := rewards_value as Dictionary
		var cash := int(rewards.get(&"cash", rewards.get(&"cash_reward", 0)))
		var reputation := int(rewards.get(&"reputation", rewards.get(&"rep", 0)))
		if cash != 0 or reputation != 0:
			stats += "\nREWARDS  +$%d  //  +%d REP" % [cash, reputation]
			if bool(rewards.get(&"repeat_limited", false)):
				stats += "  //  REPEAT RUN REP x%.2f" % clampf(float(rewards.get(&"repeat_factor", 1.0)), 0.0, 1.0)
	var points := int(result.get(&"championship_points", 0))
	if points > 0:
		stats += "  //  +%d CHAMPIONSHIP POINTS" % points
	return stats


func _refresh_results_competition() -> void:
	if _results_competition == null or _last_result.is_empty():
		return
	if not _last_academy_evaluation.is_empty():
		_results_competition.text = ""
		_results_competition.visible = false
		return
	_results_competition.visible = true
	var event_id := StringName(_last_result.get(&"event_id", _activity))
	var valid := bool(_last_result.get(&"valid", true))
	var event_record: Dictionary = Profile.get_event_record(event_id) if Profile.has_method(&"get_event_record") else {}
	var event_best_usec := int(event_record.get(&"best_time_usec", -1))
	var board_text := "LOCAL BOARD  //  NOT ELIGIBLE" if not valid else "LOCAL BOARD  //  RESULT PENDING"
	if not _last_leaderboard_result.is_empty():
		var entry_value: Variant = _last_leaderboard_result.get("entry", {})
		var entry: Dictionary = (entry_value as Dictionary).duplicate(true) if entry_value is Dictionary else {}
		var rank := int(_last_leaderboard_result.get("rank", entry.get("rank", 0)))
		var effective_time := _result_entry_time_usec(entry)
		if effective_time >= 0:
			event_best_usec = effective_time
		var rank_text := "P%d" % rank if rank > 0 else "LOCAL PB"
		var pb_status := "NEW PERSONAL BEST" if bool(_last_leaderboard_result.get("personal_best", false)) else "PERSONAL BEST HELD"
		board_text = "LOCAL BOARD  //  %s  //  %s  %s" % [rank_text, pb_status, _format_usec(event_best_usec)]
	elif event_best_usec >= 0 and valid:
		board_text += "  //  EVENT PB %s" % _format_usec(event_best_usec)
	var tour_text := _championship_results_text(_last_result)
	var rival_text := _result_rival_text(_last_result)
	var replay_text := "REPLAY READY  //  V WATCH" if _replay_available else "REPLAY UNAVAILABLE"
	_results_competition.text = "%s\n%s\n%s  //  %s" % [board_text, tour_text, rival_text, replay_text]


func _refresh_results_footer(next_event_name: String) -> void:
	if _results_footer == null or not _last_academy_evaluation.is_empty():
		return
	var next_text := "NEXT  %s" % next_event_name.to_upper() if not next_event_name.is_empty() else "NEXT  CHASE A CLEANER RESULT"
	var replay_action := "     V  WATCH REPLAY" if _replay_available else ""
	_results_footer.text = "%s\nENTER / X  REMATCH%s     G / B  GARAGE" % [next_text, replay_action]


func _championship_results_text(result: Dictionary) -> String:
	var service: Variant = Profile.get_championship_service() if Profile.has_method(&"get_championship_service") else null
	if service == null:
		return "DIRT TOUR  //  STANDINGS UNAVAILABLE"
	var standings: Array[Dictionary] = service.get_standings()
	var player_index := -1
	for index: int in standings.size():
		if StringName(standings[index].get(&"rider_id", &"")) == &"PLAYER":
			player_index = index
			break
	var table_text := "UNRANKED"
	if player_index >= 0:
		var player := standings[player_index]
		var player_points := int(player.get(&"points", 0))
		table_text = "P%d  %dPTS" % [int(player.get(&"championship_position", player_index + 1)), player_points]
		if player_index > 0:
			var target := standings[player_index - 1]
			table_text += "  //  %dPTS TO %s" % [
				maxi(int(target.get(&"points", 0)) - player_points, 0),
				str(target.get(&"display_name", target.get(&"rider_id", "LEADER"))).to_upper(),
			]
		elif standings.size() > 1:
			var chaser := standings[1]
			table_text += "  //  LEADS %s BY %dPTS" % [
				str(chaser.get(&"display_name", chaser.get(&"rider_id", "P2"))).to_upper(),
				maxi(player_points - int(chaser.get(&"points", 0)), 0),
			]
	var next_round: Dictionary = service.get_next_round()
	var next_text := "SEASON COMPLETE" if next_round.is_empty() else "NEXT R%d  %s" % [
		int(next_round.get(&"round_number", service.completed_round_count() + 1)),
		str(next_round.get(&"display_name", "TOUR ROUND")).to_upper(),
	]
	var round_prefix := ""
	if not StringName(result.get(&"round_id", &"")).is_empty():
		round_prefix = "ROUND CLASSIFIED  +%dPTS  //  " % int(result.get(&"championship_points", 0))
	return "DIRT TOUR S%02d  //  %s%s  //  %s" % [int(service.season_number), round_prefix, table_text, next_text]


func _result_rival_text(result: Dictionary) -> String:
	var classification_value: Variant = result.get(&"classification", _classification)
	var classification: Array[Dictionary] = []
	if classification_value is Array:
		for raw_racer: Variant in classification_value:
			if raw_racer is Dictionary:
				classification.append((raw_racer as Dictionary).duplicate(true))
	var player_index := -1
	var rook_index := -1
	for index: int in classification.size():
		var rider_id := StringName(classification[index].get(&"rider_id", &""))
		if _is_player_result(classification[index]):
			player_index = index
		elif rider_id == &"ROOK":
			rook_index = index
	if player_index < 0:
		return "RACE RIVAL  //  CLASSIFICATION PENDING"
	var rival_index := rook_index if StringName(result.get(&"event_id", &"")) == &"MESA_RIVAL" else player_index - 1 if player_index > 0 else 1 if classification.size() > 1 else -1
	if rival_index < 0 or rival_index >= classification.size():
		return "RACE RIVAL  //  NO COMPARABLE RIDER"
	var player := classification[player_index]
	var rival := classification[rival_index]
	var rival_id := StringName(rival.get(&"rider_id", &""))
	var profile := RiderRoster.get_rider(rival_id)
	var rival_name := str(rival.get(&"display_name", profile.get(&"name", rival_id))).to_upper()
	var player_time := _classification_time_usec(player)
	var rival_time := _classification_time_usec(rival)
	var comparison := "P%d VS P%d" % [int(player.get(&"position", player_index + 1)), int(rival.get(&"position", rival_index + 1))]
	if player_time >= 0 and rival_time >= 0:
		var delta_usec := player_time - rival_time
		comparison = "BEAT BY %.2fs" % (absf(float(delta_usec)) / 1_000_000.0) if delta_usec <= 0 else "FIND %.2fs" % (float(delta_usec) / 1_000_000.0)
	return "RACE RIVAL  //  %s  //  %s" % [rival_name, comparison]


func _result_entry_time_usec(entry: Dictionary) -> int:
	var time_usec := int(entry.get("time_usec", -1))
	if time_usec < 0:
		return -1
	return time_usec + maxi(int(entry.get("penalty_usec", 0)), 0)


func _classification_time_usec(racer: Dictionary) -> int:
	var effective_usec := int(racer.get(&"effective_time_usec", -1))
	if effective_usec >= 0:
		return effective_usec
	var finish_usec := int(racer.get(&"finish_usec", -1))
	return finish_usec + maxi(int(racer.get(&"penalty_usec", 0)), 0) if finish_usec >= 0 else -1


func _find_player_position() -> int:
	for index: int in _classification.size():
		if _is_player_result(_classification[index]):
			return int(_classification[index].get(&"position", index + 1))
	return 1


func _is_player_result(racer: Dictionary) -> bool:
	return bool(racer.get(&"is_player", false)) or StringName(racer.get(&"rider_id", &"")) == &"PLAYER"


func _format_gap_usec(time_usec: int) -> String:
	var total_msec := maxi(time_usec / 1000, 0)
	return "%d:%02d.%03d" % [total_msec / 60000, (total_msec / 1000) % 60, total_msec % 1000]


func _phase_text(phase: StringName) -> String:
	match phase:
		&"WAITING": return "READY"
		&"STAGING": return "STAGING"
		&"COUNTDOWN": return "START SEQUENCE"
		&"PRACTICE": return "PRACTICE LIVE"
		&"QUALIFYING": return "QUALIFYING LIVE"
		&"RACING": return "RACE LIVE"
		&"FINISHED", &"FINISHING": return "FINISHING FIELD"
		&"RESULTS": return "OFFICIAL RESULTS"
		_: return String(phase).replace("_", " ")


func _phase_color(phase: StringName) -> Color:
	return CYAN if phase in [&"PRACTICE", &"QUALIFYING", &"RACING", &"RESULTS"] else AMBER if phase in [&"STAGING", &"COUNTDOWN"] else CREAM


func _set_flag(flag: StringName) -> void:
	match flag:
		&"YELLOW":
			_flag_label.text = "YELLOW FLAG"
			_flag_label.modulate = Color("ffd84a")
		&"WHITE":
			_flag_label.text = "WHITE FLAG  //  FINAL LAP"
			_flag_label.modulate = Color.WHITE
		&"CHECKERED":
			_flag_label.text = "CHECKERED FLAG"
			_flag_label.modulate = CREAM
		&"RED", &"INVALID":
			_flag_label.text = "RUN INVALID"
			_flag_label.modulate = WARNING
		_:
			_flag_label.text = "GREEN FLAG"
			_flag_label.modulate = CYAN
	_refresh_accessible_flag_color()


func _connect_source_signal(signal_name: StringName, callback: Callable) -> void:
	if _race_source.has_signal(signal_name) and not _race_source.is_connected(signal_name, callback):
		_race_source.connect(signal_name, callback)


func _unbind_race_source() -> void:
	if _race_source == null or not is_instance_valid(_race_source):
		_race_source = null
		return
	var bindings: Array = [
		[&"session_updated", Callable(self, &"_on_session_snapshot_received")],
		[&"classification_updated", Callable(self, &"_on_classification_received")],
		[&"integrity_updated", Callable(self, &"_on_integrity_received")],
		[&"results_ready", Callable(self, &"_on_results_received")],
	]
	for binding: Array in bindings:
		if _race_source.has_signal(binding[0]) and _race_source.is_connected(binding[0], binding[1]):
			_race_source.disconnect(binding[0], binding[1])
	_race_source = null


func _on_session_snapshot_received(snapshot: Dictionary) -> void:
	update_session_snapshot(snapshot)


func _on_classification_received(classification: Array) -> void:
	update_classification(classification)


func _on_integrity_received(snapshot: Dictionary) -> void:
	update_integrity(snapshot)


func _on_results_received(result: Dictionary) -> void:
	show_results(result)


func _on_countdown_changed(value: int) -> void:
	show_control_hints(CONTROL_HINT_CONTEXT_SECONDS)
	_countdown_label.text = str(value) if value > 0 else "GO!"
	_countdown_label.modulate = Color.WHITE
	_message_time = 0.8 if value == 0 else 0.0


func _on_race_started() -> void:
	_last_result.clear()
	_last_leaderboard_result.clear()
	_replay_summary.clear()
	_replay_available = false
	_replay_hid_results = false
	show_control_hints(CONTROL_HINT_RACE_SECONDS)
	_phase_label.text = "RACE LIVE"
	_phase_label.modulate = CYAN
	_set_flag(&"GREEN")
	if _activity == &"ACADEMY" and not _academy_lesson.is_empty():
		_message_label.text = "ACADEMY  //  %s  //  COMPLETE BOTH OBJECTIVES" % str(
			_academy_lesson.get(&"display_name", "RIDE LESSON")
		).to_upper()
	else:
		_message_label.text = "HIT EVERY GATE  •  FIND THE FAST LINE"
	_message_label.modulate = CREAM
	_message_time = 2.6


func _on_checkpoint_passed(index: int, total: int, split_usec: int) -> void:
	if _activity == &"ACADEMY":
		_academy_live_metrics[&"gates_completed"] = float(_academy_live_metrics.get(&"gates_completed", 0.0)) + 1.0
		if StringName(_integrity_snapshot.get(&"warning", &"")) in [&"", &"NONE", &"CLEAR"]:
			_academy_live_metrics[&"clean_corners"] = float(_academy_live_metrics.get(&"clean_corners", 0.0)) + 1.0
		_refresh_academy_panel()
	if _rival_target_usec > 0 and total > 0:
		var progress_ratios := CourseCatalog.get_checkpoint_progress_ratios(_track_id, _authoritative_route)
		var progress := progress_ratios[index] if index < progress_ratios.size() else float(index + 1) / float(total)
		var expected_split := int(float(_rival_target_usec) * progress)
		var delta_usec := split_usec - expected_split
		var comparison := "AHEAD OF ROOK" if delta_usec <= 0 else "BEHIND ROOK"
		var momentum := ""
		if _has_rival_split:
			var gained_usec := _last_rival_delta_usec - delta_usec
			if absi(gained_usec) >= 150_000:
				momentum = "  //  %s %.2fs" % ["GAINED" if gained_usec > 0 else "LOST", absf(float(gained_usec) / 1_000_000.0)]
		_last_rival_delta_usec = delta_usec
		_has_rival_split = true
		_message_label.text = "GATE %02d / %02d  //  %.2fs %s%s" % [index + 1, total, absf(float(delta_usec) / 1_000_000.0), comparison, momentum]
		_message_label.modulate = CYAN if delta_usec <= 0 else Color("ff806b")
	else:
		_message_label.text = "GATE %02d / %02d  —  CLEAN" % [index + 1, total]
		_message_label.modulate = CREAM
	_message_time = 1.2


func _on_race_finished(time_usec: int, medal: StringName, is_new_best: bool) -> void:
	dismiss_control_hints()
	_phase_label.text = "FINISHING FIELD"
	_phase_label.modulate = CREAM
	_set_flag(&"CHECKERED")
	_line_label.text = ""
	_line_score_label.text = ""
	_countdown_label.text = str(medal)
	_countdown_label.add_theme_color_override(&"font_color", AMBER if medal == &"GOLD" else CREAM)
	var record_text := "  •  NEW PERSONAL BEST" if is_new_best else ""
	var rival_text := ""
	if _rival_target_usec > 0:
		var rival_delta := time_usec - _rival_target_usec
		rival_text = "  •  ROOK BEATEN" if rival_delta <= 0 else "  •  %.2fs BEHIND ROOK" % (float(rival_delta) / 1_000_000.0)
	var rook_callout := "ROOK: CLEAN. DO IT AGAIN." if _rival_target_usec > 0 and time_usec <= _rival_target_usec else "ROOK: YOU LEFT TIME IN THE CORNERS."
	var next_goal := _race_next_goal(time_usec)
	_message_label.text = "%s%s%s\n%s\n%s\nENTER / X RUN AGAIN   //   G / B GARAGE" % [_format_usec(time_usec), record_text, rival_text, rook_callout, next_goal]
	_message_label.modulate = CYAN if _rival_target_usec > 0 and time_usec <= _rival_target_usec else CREAM
	_message_time = 9999.0


func _on_race_reset() -> void:
	show_control_hints(CONTROL_HINT_STAGE_SECONDS)
	hide_results()
	_gate_launch_feedback_time = 0.0
	_last_gate_launch_result_attempt = -1
	if _gate_launch_label != null:
		_gate_launch_label.text = ""
		_gate_launch_label.visible = false
	_countdown_label.add_theme_color_override(&"font_color", AMBER)
	_message_label.text = ""
	_message_label.modulate = CREAM
	_message_time = 0.0
	_compass_label.visible = false
	_breakdown_label.text = ""
	_has_rival_split = false
	_last_rival_delta_usec = 0
	_session_snapshot.clear()
	_integrity_snapshot.clear()
	_classification.clear()
	_holeshot_rider_id = &""
	_last_academy_evaluation.clear()
	_last_integrity_warning = ""
	_course_map.call(&"clear_racers")
	_refresh_live_standings()
	_phase_label.text = "STAGING"
	_phase_label.modulate = AMBER
	_lap_label.text = "LAP 1 / 1"
	_integrity_label.text = ""
	_integrity_label.visible = false
	_set_flag(&"GREEN")
	_field_label.text = "FIELD 12  //  GRID SET"
	_field_label.modulate = CREAM


func _on_game_paused(paused: bool) -> void:
	_paused_label.visible = paused
	_control_hint_pinned = paused
	if paused:
		show_control_hints(0.0)
	else:
		show_control_hints(1.25)


func _on_device_changed(using_gamepad: bool) -> void:
	if using_gamepad:
		_controls_label.text = "RT THROTTLE   LT BRAKE   LS STEER   RS LEAN\nA PRELOAD   LB CONTEXT FLOW   RB CLUTCH / DAB / PUMP   Y RESET   B GARAGE"
	else:
		_controls_label.text = "W THROTTLE   S BRAKE   A / D STEER   UP / DOWN LEAN\nSPACE PRELOAD   SHIFT CONTEXT FLOW   C CLUTCH / DAB / PUMP   R RESET   G GARAGE"
	show_control_hints(CONTROL_HINT_CONTEXT_SECONDS)


func _on_activity_started(activity: StringName) -> void:
	_activity = activity
	match activity:
		&"ACADEMY":
			show_control_hints(CONTROL_HINT_RACE_SECONDS)
			_message_label.text = "ACADEMY OBJECTIVES ARE LIVE  //  PASS BOTH TO ADVANCE"
			_message_time = 2.8
			_message_label.modulate = Color("7bd66f")
		&"FREESTYLE":
			show_control_hints(CONTROL_HINT_RACE_SECONDS)
			_message_label.text = "CHAIN AIRTIME, ROTATION, AND CLEAN LANDINGS"
			_message_time = 2.8
			_message_label.modulate = CREAM
		&"DISCOVERY":
			show_control_hints(CONTROL_HINT_RACE_SECONDS)
			_message_label.text = "FOLLOW THE COMPASS  •  FIND ALL SIX CACHES"
			_message_time = 2.8
			_message_label.modulate = CREAM


func _on_activity_prepared(activity: StringName) -> void:
	_activity = activity
	if activity == &"ACADEMY":
		configure_academy_lesson(RaceEventCatalog.get_active_academy_lesson())
	else:
		_academy_lesson.clear()
		_academy_live_metrics.clear()
		_refresh_academy_panel()
	show_control_hints(CONTROL_HINT_STAGE_SECONDS)
	_rival_target_usec = 285_000_000 if activity == &"PINE_ENDURO" else 190_000_000 if activity == &"CIRCUIT" else -1
	_countdown_label.text = ""
	_countdown_label.add_theme_color_override(&"font_color", AMBER)
	var is_race_activity := activity not in [&"FREESTYLE", &"DISCOVERY"]
	_standings_panel.visible = is_race_activity and activity != &"ACADEMY"
	_phase_label.visible = is_race_activity
	_lap_label.visible = is_race_activity
	_flag_label.visible = is_race_activity
	_integrity_label.visible = false
	match activity:
		&"ACADEMY":
			_title_label.text = "RIDING DIRTY  //  RIDING ACADEMY"
			_compass_label.visible = false
			_course_map.visible = true
			_field_label.visible = false
		&"PINE_ENDURO":
			_title_label.text = "RIDING DIRTY  //  PINE RIDGE ENDURO"
			_compass_label.visible = false
			_course_map.visible = true
			_field_label.visible = true
		&"FREESTYLE":
			_title_label.text = "RIDING DIRTY  //  QUARRY FREESTYLE"
			_compass_label.visible = false
			_course_map.visible = false
			_field_label.visible = false
		&"DISCOVERY":
			_title_label.text = "RIDING DIRTY  //  SALVAGE HUNT"
			_compass_label.visible = true
			_course_map.visible = false
			_field_label.visible = false
		_:
			_title_label.text = "RIDING DIRTY  //  RED MESA QUARRY TRAIL  //  %s" % _build_id().to_upper()
			_compass_label.visible = false
			_course_map.visible = true
			_field_label.visible = true


func _on_freestyle_score_changed(_score: int, combo: int, last_points: int) -> void:
	if _activity != &"FREESTYLE" or last_points <= 0:
		return
	_message_label.text = "+%d  •  COMBO x%d" % [last_points, combo]
	_message_time = 1.25


func _on_discovery_progress_changed(current: int, total: int) -> void:
	if _activity != &"DISCOVERY" or current <= 0:
		return
	_message_label.text = "SALVAGE SECURED  %02d / %02d" % [current, total]
	_message_time = 1.4


func _on_activity_completed(activity: StringName, result_value: int, medal: StringName, is_new_best: bool) -> void:
	if activity == &"CIRCUIT":
		return
	dismiss_control_hints()
	_line_label.text = ""
	_line_score_label.text = ""
	_countdown_label.text = str(medal)
	_countdown_label.add_theme_color_override(&"font_color", AMBER if medal == &"GOLD" else CREAM)
	_compass_label.visible = false
	var result_text := "%06d POINTS" % result_value if activity == &"FREESTYLE" else _format_usec(result_value)
	var record_text := "  •  NEW PERSONAL BEST" if is_new_best else ""
	var next_goal := _freestyle_next_goal(result_value) if activity == &"FREESTYLE" else _discovery_next_goal(result_value)
	_message_label.text = "%s%s\n%s\nENTER / X RUN AGAIN   //   G / B GARAGE" % [result_text, record_text, next_goal]
	_message_time = 9999.0


func _on_reward_granted(cash_reward: int, reputation_reward: int) -> void:
	_queue_reward("+$%d   +%d REP" % [cash_reward, reputation_reward], 3.0, CYAN)


func _on_achievement_unlocked(achievement_id: StringName) -> void:
	var definition := Profile.get_achievement_definition(achievement_id)
	var title := str(definition.get(&"title", String(achievement_id).replace("_", " "))).to_upper()
	var description := str(definition.get(&"description", "NEW RIDER MILESTONE"))
	_queue_reward("ACHIEVEMENT UNLOCKED  //  %s\n%s" % [title, description], 5.0, AMBER)


func _queue_reward(text: String, duration: float, color: Color) -> void:
	if text.strip_edges().is_empty():
		return
	_reward_queue.append({&"text": text, &"duration": maxf(duration, 0.1), &"color": color})
	if _reward_time <= 0.0:
		_present_next_reward()


func _present_next_reward() -> void:
	if _reward_label == null or _reward_queue.is_empty():
		return
	var notification: Dictionary = _reward_queue.pop_front() as Dictionary
	_reward_label.text = str(notification.get(&"text", ""))
	_reward_label.modulate = notification.get(&"color", CYAN) as Color
	_reward_time = maxf(float(notification.get(&"duration", 3.0)), 0.1)


func _format_usec(time_usec: int) -> String:
	var total_msec := maxi(time_usec / 1000, 0)
	var minutes := total_msec / 60000
	var seconds := (total_msec / 1000) % 60
	var milliseconds := total_msec % 1000
	return "%02d:%02d.%03d" % [minutes, seconds, milliseconds]


func _pulse_highlight() -> void:
	if _highlight_tween != null:
		_highlight_tween.kill()
	_highlight_overlay.color = Color(0.34, 0.84, 1.0, 0.12)
	_highlight_tween = create_tween()
	_highlight_tween.tween_property(_highlight_overlay, "color", Color.TRANSPARENT, 0.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)


func _pulse_warning() -> void:
	if _highlight_tween != null:
		_highlight_tween.kill()
	_highlight_overlay.color = Color(1.0, 0.2, 0.12, 0.08)
	_highlight_tween = create_tween()
	_highlight_tween.tween_property(_highlight_overlay, "color", Color.TRANSPARENT, 0.35).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)


func _race_next_goal(time_usec: int) -> String:
	var targets := CourseCatalog.get_medal_times_usec(_track_id)
	var bronze := int(targets.get(&"bronze", 0))
	var silver := int(targets.get(&"silver", 0))
	var gold := int(targets.get(&"gold", 0))
	if time_usec > bronze:
		return "NEXT TARGET  //  BRONZE  //  SHAVE %.2fs" % (float(time_usec - bronze) / 1_000_000.0)
	if time_usec > silver:
		return "NEXT TARGET  //  SILVER  //  SHAVE %.2fs" % (float(time_usec - silver) / 1_000_000.0)
	if time_usec > gold:
		return "NEXT TARGET  //  GOLD  //  SHAVE %.2fs" % (float(time_usec - gold) / 1_000_000.0)
	return "NEXT TARGET  //  LOWER THE PB WITH A CLEANER LINE"


func _freestyle_next_goal(score: int) -> String:
	if score < 3_500:
		return "NEXT TARGET  //  BRONZE  //  +%d POINTS" % (3_500 - score)
	if score < 7_000:
		return "NEXT TARGET  //  SILVER  //  +%d POINTS" % (7_000 - score)
	if score < 12_000:
		return "NEXT TARGET  //  GOLD  //  +%d POINTS" % (12_000 - score)
	return "NEXT TARGET  //  EXTEND THE CHAIN AND BEAT YOUR SCORE"


func _discovery_next_goal(time_usec: int) -> String:
	if time_usec > 120_000_000:
		return "NEXT TARGET  //  BRONZE  //  SHAVE %.2fs" % (float(time_usec - 120_000_000) / 1_000_000.0)
	if time_usec > 80_000_000:
		return "NEXT TARGET  //  SILVER  //  SHAVE %.2fs" % (float(time_usec - 80_000_000) / 1_000_000.0)
	if time_usec > 50_000_000:
		return "NEXT TARGET  //  GOLD  //  SHAVE %.2fs" % (float(time_usec - 50_000_000) / 1_000_000.0)
	return "NEXT TARGET  //  FIND A FASTER CACHE ROUTE"
