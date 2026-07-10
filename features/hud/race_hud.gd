extends CanvasLayer
class_name RaceHud
## Responsive race presentation projected from bike and race signals.

const CREAM := Color("f7e5b2")
const AMBER := Color("ffb52d")
const CYAN := Color("56d6ff")
const DARK := Color(0.035, 0.045, 0.055, 0.88)

var _timer_label: Label
var _best_label: Label
var _checkpoint_label: Label
var _speed_label: Label
var _speed_bar: ProgressBar
var _flow_label: Label
var _flow_bar: ProgressBar
var _countdown_label: Label
var _message_label: Label
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
var _message_time: float = 0.0
var _reward_time: float = 0.0
var _activity: StringName = &"CIRCUIT"
var _rival_target_usec: int = 52_000_000


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_hud()
	EventBus.race_countdown_changed.connect(_on_countdown_changed)
	EventBus.race_started.connect(_on_race_started)
	EventBus.checkpoint_passed.connect(_on_checkpoint_passed)
	EventBus.race_finished.connect(_on_race_finished)
	EventBus.race_reset.connect(_on_race_reset)
	EventBus.game_paused.connect(_on_game_paused)
	EventBus.activity_started.connect(_on_activity_started)
	EventBus.freestyle_score_changed.connect(_on_freestyle_score_changed)
	EventBus.discovery_progress_changed.connect(_on_discovery_progress_changed)
	EventBus.activity_completed.connect(_on_activity_completed)
	Profile.reward_granted.connect(_on_reward_granted)
	InputRouter.device_changed.connect(_on_device_changed)
	_on_device_changed(InputRouter.using_gamepad)


func _process(delta: float) -> void:
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


func update_telemetry(speed_mph: float, _throttle: float, grounded: bool) -> void:
	_speed_label.text = "%03d" % int(round(speed_mph))
	_speed_bar.value = clampf(speed_mph, 0.0, 82.0)
	_speed_label.modulate = AMBER if grounded else CYAN


func update_flow(value: float, boosting: bool) -> void:
	_flow_bar.value = clampf(value, 0.0, 100.0)
	_flow_label.text = "BOOSTING" if boosting else "FLOW  %03d" % int(round(value))
	_flow_label.modulate = CYAN if boosting else CREAM


func update_line(label: String, chain: int, multiplier: float, score: int, time_left: float) -> void:
	_line_label.text = label
	_line_label.modulate = CYAN if chain >= 4 else AMBER
	_line_score_label.text = "LINE %06d" % score if chain <= 1 else "LINE %06d   x%.2f   CHAIN %02d   %.1fs" % [score, multiplier, chain, time_left]
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
	_reward_label.text = "FEAT UNLOCKED  //  %s  //  +1 STYLE TOKEN" % title
	_reward_time = 4.0


func update_race_time(elapsed_usec: int, best_usec: int, checkpoint: int, total: int) -> void:
	_timer_label.text = _format_usec(elapsed_usec)
	var best_text := "--:--.---" if best_usec < 0 else _format_usec(best_usec)
	_best_label.text = "PB %s  //  ROOK %s" % [best_text, _format_usec(_rival_target_usec)] if _rival_target_usec > 0 else "BEST  %s" % best_text
	_checkpoint_label.text = "GATE  %02d / %02d" % [mini(checkpoint + 1, total), total]


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

	_title_label = _make_label(root, "RIDING DIRTY  //  RED MESA QUARRY", 22, CREAM)
	_anchor_rect(_title_label, Vector2.ZERO, Rect2(28.0, 23.0, 560.0, 44.0))

	_timer_label = _make_label(root, "00:00.000", 46, CREAM)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_anchor_rect(_timer_label, Vector2(0.5, 0.0), Rect2(-180.0, 10.0, 360.0, 64.0))

	_best_label = _make_label(root, "BEST  --:--.---", 18, Color("a8b4bd"))
	_best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_anchor_rect(_best_label, Vector2(1.0, 0.0), Rect2(-350.0, 18.0, 320.0, 28.0))

	_checkpoint_label = _make_label(root, "GATE  01 / 06", 19, AMBER)
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
	var mph := _make_label(root, "MPH", 18, CREAM)
	_anchor_rect(mph, Vector2.ONE, Rect2(-74.0, -163.0, 50.0, 32.0))

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

	var controls_panel := ColorRect.new()
	controls_panel.color = DARK
	_anchor_rect(controls_panel, Vector2(0.0, 1.0), Rect2(28.0, -126.0, 700.0, 92.0))
	controls_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(controls_panel)
	_controls_label = _make_label(root, "", 17, Color("c7d0d5"))
	_anchor_rect(_controls_label, Vector2(0.0, 1.0), Rect2(46.0, -111.0, 670.0, 70.0))
	_controls_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_countdown_label = _make_label(root, "", 132, AMBER)
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_anchor_rect(_countdown_label, Vector2(0.5, 0.5), Rect2(-260.0, -150.0, 520.0, 220.0))

	_message_label = _make_label(root, "", 27, CREAM)
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

	_paused_label = _make_label(root, "PAUSED\nESC / START TO RIDE", 54, CREAM)
	_paused_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_paused_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_paused_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_paused_label.visible = false

	_highlight_overlay = ColorRect.new()
	_highlight_overlay.color = Color.TRANSPARENT
	_highlight_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_highlight_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_highlight_overlay)


func _make_label(parent: Control, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", font_size)
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


func _on_countdown_changed(value: int) -> void:
	_countdown_label.text = str(value) if value > 0 else "GO!"
	_countdown_label.modulate = Color.WHITE
	_message_time = 0.8 if value == 0 else 0.0


func _on_race_started() -> void:
	_message_label.text = "HIT EVERY GATE  •  FIND THE FAST LINE"
	_message_label.modulate = CREAM
	_message_time = 2.6


func _on_checkpoint_passed(index: int, total: int, split_usec: int) -> void:
	if _rival_target_usec > 0 and total > 0:
		var expected_split := int(float(_rival_target_usec) * float(index + 1) / float(total))
		var delta_usec := split_usec - expected_split
		var comparison := "AHEAD OF ROOK" if delta_usec <= 0 else "BEHIND ROOK"
		_message_label.text = "GATE %02d / %02d  •  %.2fs %s" % [index + 1, total, absf(float(delta_usec) / 1_000_000.0), comparison]
		_message_label.modulate = CYAN if delta_usec <= 0 else Color("ff806b")
	else:
		_message_label.text = "GATE %02d / %02d  —  CLEAN" % [index + 1, total]
		_message_label.modulate = CREAM
	_message_time = 1.2


func _on_race_finished(time_usec: int, medal: StringName, is_new_best: bool) -> void:
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
	_message_label.text = "%s%s%s\n%s\nENTER / X RUN AGAIN   •   G / B GARAGE" % [_format_usec(time_usec), record_text, rival_text, rook_callout]
	_message_label.modulate = CYAN if _rival_target_usec > 0 and time_usec <= _rival_target_usec else CREAM
	_message_time = 9999.0


func _on_race_reset() -> void:
	_countdown_label.add_theme_color_override(&"font_color", AMBER)
	_message_label.text = ""
	_message_label.modulate = CREAM
	_message_time = 0.0
	_compass_label.visible = false
	_breakdown_label.text = ""


func _on_game_paused(paused: bool) -> void:
	_paused_label.visible = paused


func _on_device_changed(using_gamepad: bool) -> void:
	if using_gamepad:
		_controls_label.text = "RT THROTTLE   LT BRAKE   LS STEER   RS LEAN\nA PRELOAD   LB BOOST   Y RESET   X RESTART   B GARAGE"
	else:
		_controls_label.text = "W THROTTLE   S BRAKE   A / D STEER   UP / DOWN LEAN\nSPACE PRELOAD   SHIFT BOOST   R RESET   ENTER RESTART   G GARAGE"


func _on_activity_started(activity: StringName) -> void:
	_activity = activity
	_rival_target_usec = 64_000_000 if activity == &"PINE_ENDURO" else 52_000_000 if activity == &"CIRCUIT" else -1
	_countdown_label.text = ""
	_countdown_label.add_theme_color_override(&"font_color", AMBER)
	match activity:
		&"PINE_ENDURO":
			_title_label.text = "RIDING DIRTY  //  PINE RIDGE ENDURO"
			_compass_label.visible = false
		&"FREESTYLE":
			_title_label.text = "RIDING DIRTY  //  QUARRY FREESTYLE"
			_message_label.text = "CHAIN AIRTIME, ROTATION, AND CLEAN LANDINGS"
			_message_time = 2.8
			_message_label.modulate = CREAM
			_compass_label.visible = false
		&"DISCOVERY":
			_title_label.text = "RIDING DIRTY  //  SALVAGE HUNT"
			_message_label.text = "FOLLOW THE COMPASS  •  FIND ALL SIX CACHES"
			_message_time = 2.8
			_message_label.modulate = CREAM
			_compass_label.visible = true
		_:
			_title_label.text = "RIDING DIRTY  //  RED MESA QUARRY"
			_compass_label.visible = false


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
	_line_label.text = ""
	_line_score_label.text = ""
	_countdown_label.text = str(medal)
	_countdown_label.add_theme_color_override(&"font_color", AMBER if medal == &"GOLD" else CREAM)
	_compass_label.visible = false
	var result_text := "%06d POINTS" % result_value if activity == &"FREESTYLE" else _format_usec(result_value)
	var record_text := "  •  NEW PERSONAL BEST" if is_new_best else ""
	_message_label.text = "%s%s\nENTER / X RUN AGAIN   •   G / B GARAGE" % [result_text, record_text]
	_message_time = 9999.0


func _on_reward_granted(cash_reward: int, reputation_reward: int) -> void:
	_reward_label.text = "+$%d   +%d REP" % [cash_reward, reputation_reward]
	_reward_time = 3.0


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
