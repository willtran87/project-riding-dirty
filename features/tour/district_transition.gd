extends CanvasLayer
class_name DistrictTransition
## Short authored cover/reveal used while swapping activities and districts.

const CREAM := Color("f7e5b2")
const AMBER := Color("ffb52d")
const CANVAS_WIDTH: float = 1600.0

var _root: Control
var _blackout: ColorRect
var _sweep: ColorRect
var _accent: ColorRect
var _kicker: Label
var _title: Label
var _description: Label
var _rival: Label
var _route: Label
var _active_tween: Tween
var _reduced_motion: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(&"reduced_motion_consumers")
	_build_ui()
	visible = false


func cover(activity: StringName) -> void:
	_kill_active_tween()
	_configure(activity)
	visible = true
	if _reduced_motion:
		_apply_covered_state()
		# Give the static briefing one rendered frame before the caller starts
		# streaming the district behind its opaque cover.
		await get_tree().process_frame
		return
	_blackout.modulate.a = 0.0
	_sweep.position.x = -CANVAS_WIDTH
	_accent.scale.x = 0.0
	_kicker.modulate.a = 0.0
	_title.modulate.a = 0.0
	_description.modulate.a = 0.0
	_rival.modulate.a = 0.0
	_route.modulate.a = 0.0
	_title.position.y = 372.0
	_active_tween = create_tween().bind_node(self)
	_active_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_active_tween.set_parallel(true)
	_active_tween.tween_property(_blackout, "modulate:a", 1.0, 0.24).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_active_tween.tween_property(_sweep, "position:x", 0.0, 0.42).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_active_tween.tween_property(_accent, "scale:x", 1.0, 0.34).set_delay(0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_active_tween.tween_property(_kicker, "modulate:a", 1.0, 0.18).set_delay(0.16)
	_active_tween.tween_property(_title, "modulate:a", 1.0, 0.2).set_delay(0.18)
	_active_tween.tween_property(_title, "position:y", 350.0, 0.3).set_delay(0.14).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_active_tween.tween_property(_description, "modulate:a", 1.0, 0.2).set_delay(0.24)
	_active_tween.tween_property(_rival, "modulate:a", 1.0, 0.2).set_delay(0.28)
	_active_tween.tween_property(_route, "modulate:a", 1.0, 0.2).set_delay(0.3)
	await _active_tween.finished


func reveal() -> void:
	_kill_active_tween()
	if _reduced_motion:
		_apply_revealed_state()
		await get_tree().process_frame
		return
	_active_tween = create_tween().bind_node(self)
	_active_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_active_tween.set_parallel(true)
	_active_tween.tween_property(_kicker, "modulate:a", 0.0, 0.12)
	_active_tween.tween_property(_title, "modulate:a", 0.0, 0.14)
	_active_tween.tween_property(_description, "modulate:a", 0.0, 0.12)
	_active_tween.tween_property(_rival, "modulate:a", 0.0, 0.12)
	_active_tween.tween_property(_route, "modulate:a", 0.0, 0.12)
	_active_tween.tween_property(_sweep, "position:x", CANVAS_WIDTH, 0.46).set_delay(0.08).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_active_tween.tween_property(_blackout, "modulate:a", 0.0, 0.34).set_delay(0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await _active_tween.finished
	visible = false


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled


func is_reduced_motion_enabled() -> bool:
	return _reduced_motion


func get_motion_accessibility_snapshot() -> Dictionary:
	return {
		&"reduced_motion": _reduced_motion,
		&"visible": visible,
		&"active_tween": _active_tween != null and _active_tween.is_valid(),
		&"blackout_alpha": _blackout.modulate.a if _blackout != null else 0.0,
		&"sweep_x": _sweep.position.x if _sweep != null else 0.0,
		&"accent_scale_x": _accent.scale.x if _accent != null else 0.0,
		&"title_y": _title.position.y if _title != null else 0.0,
		&"title": _title.text if _title != null else "",
		&"briefing_visible": _title != null and _title.modulate.a >= 0.99,
	}


func _apply_covered_state() -> void:
	_blackout.modulate.a = 1.0
	_sweep.position.x = 0.0
	_accent.scale.x = 1.0
	_kicker.modulate.a = 1.0
	_title.modulate.a = 1.0
	_description.modulate.a = 1.0
	_rival.modulate.a = 1.0
	_route.modulate.a = 1.0
	_title.position.y = 350.0
	_active_tween = null


func _apply_revealed_state() -> void:
	_kicker.modulate.a = 0.0
	_title.modulate.a = 0.0
	_description.modulate.a = 0.0
	_rival.modulate.a = 0.0
	_route.modulate.a = 0.0
	_sweep.position.x = CANVAS_WIDTH
	_blackout.modulate.a = 0.0
	_active_tween = null
	visible = false


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	_blackout = ColorRect.new()
	_blackout.color = Color(0.006, 0.008, 0.01, 0.94)
	_blackout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_blackout)
	_sweep = ColorRect.new()
	_sweep.color = Color("151b1e")
	_sweep.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_sweep)
	var dark_band := ColorRect.new()
	dark_band.color = Color("0a0d0f")
	_anchor_rect(dark_band, Vector2(0.0, 0.5), Rect2(0.0, -142.0, CANVAS_WIDTH, 284.0))
	_sweep.add_child(dark_band)
	_accent = ColorRect.new()
	_accent.color = AMBER
	_accent.pivot_offset = Vector2.ZERO
	_anchor_rect(_accent, Vector2(0.0, 0.5), Rect2(0.0, -148.0, CANVAS_WIDTH, 6.0))
	_sweep.add_child(_accent)
	_kicker = _label("", 16, AMBER)
	_kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_anchor_rect(_kicker, Vector2(0.5, 0.5), Rect2(-500.0, -132.0, 1000.0, 32.0))
	_sweep.add_child(_kicker)
	_title = _label("", 76, CREAM)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_anchor_rect(_title, Vector2(0.5, 0.0), Rect2(-700.0, 350.0, 1400.0, 104.0))
	_sweep.add_child(_title)
	_description = _label("", 21, Color("aab9c2"))
	_description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_anchor_rect(_description, Vector2(0.5, 0.5), Rect2(-650.0, 22.0, 1300.0, 38.0))
	_sweep.add_child(_description)
	_rival = _label("", 18, Color("56d6ff"))
	_rival.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_anchor_rect(_rival, Vector2(0.5, 0.5), Rect2(-650.0, 70.0, 1300.0, 36.0))
	_sweep.add_child(_rival)
	_route = _label("", 13, Color("7e919d"))
	_route.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_anchor_rect(_route, Vector2(0.5, 0.5), Rect2(-500.0, 128.0, 1000.0, 28.0))
	_sweep.add_child(_route)


func _configure(activity: StringName) -> void:
	var briefing := get_briefing_snapshot(activity)
	_kicker.text = str(briefing[&"kicker"])
	_title.text = str(briefing[&"title"])
	_description.text = str(briefing[&"description"])
	_rival.text = str(briefing[&"target"])
	_route.text = str(briefing[&"route"])
	_set_accent(briefing[&"accent"] as Color)


func get_briefing_snapshot(activity: StringName) -> Dictionary:
	var event := RaceEventCatalog.get_event(activity)
	if activity == &"FREESTYLE":
		return {
			&"event_id": activity, &"track_id": CourseCatalog.QUARRY_ID,
			&"kicker": "DISTRICT 01   //   QUARRY WORKS",
			&"title": str(event.get(&"display_name", "QUARRY FREESTYLE")),
			&"description": str(event.get(&"description", "Link clean airtime and landings.")).to_upper(),
			&"target": "CREW TARGET   007000 POINTS",
			&"route": str(event.get(&"meta", "60 SEC  //  SCORE ATTACK")),
			&"format": &"FREESTYLE", &"laps": 0, &"weather": &"SUNSET",
			&"accent": Color("56d6ff"),
		}
	if activity == &"DISCOVERY":
		return {
			&"event_id": activity, &"track_id": CourseCatalog.QUARRY_ID,
			&"kicker": "DISTRICT 01   //   QUARRY WORKS",
			&"title": str(event.get(&"display_name", "SALVAGE HUNT")),
			&"description": str(event.get(&"description", "Bring all six caches home.")).to_upper(),
			&"target": "CREW TARGET   01:20.000",
			&"route": str(event.get(&"meta", "6 CACHES  //  EXPLORATION")),
			&"format": &"DISCOVERY", &"laps": 0, &"weather": &"MIST",
			&"accent": Color("d8b35a"),
		}

	var session := RaceEventCatalog.get_session_config(activity)
	var track_name := "QUARRY WORKS"
	var district_number := "01"
	var accent := AMBER
	if session.track_id == CourseCatalog.PINE_ID:
		track_name = "PINE RIDGE"
		district_number = "02"
		accent = Color("9fc744")
	elif session.track_id == CourseCatalog.MESA_MX_ID:
		track_name = "RED MESA MX"
		district_number = "03"
		accent = Color("e25532")
	if session.weather in [&"NIGHT", &"STORM", &"WET"]:
		accent = Color("56d6ff")
	elif session.weather in [&"DUSK", &"SUNSET"]:
		accent = Color("ff8d4a")
	var target_usec := int(session.medal_times_usec.get(&"gold", 0))
	var target_prefix := "ROOK TARGET" if bool(session.rules.get(&"rival_only", false)) or session.format == &"RIVAL" else "GOLD TARGET"
	var lap_label := "%d LAP%s" % [session.laps, "S" if session.laps != 1 else ""]
	var difficulty_mode := StringName(session.rules.get(&"player_difficulty_mode", &"LOCKED"))
	var difficulty_offset := int(session.rules.get(&"player_difficulty_offset", 0))
	var difficulty_locked := not session.rules.has(&"player_difficulty_mode")
	var difficulty_label := "RACE DIFFICULTY %s" % String(difficulty_mode)
	if RaceEventCatalog.is_challenge_event(activity):
		difficulty_label = "CHALLENGE DIFFICULTY LOCKED"
	elif activity == &"ACADEMY":
		difficulty_label = "ACADEMY GRADING LOCKED"
	elif difficulty_locked:
		difficulty_label = "AI DIFFICULTY FIXED"
	return {
		&"event_id": activity,
		&"track_id": session.track_id,
		&"kicker": "DISTRICT %s   //   %s" % [district_number, track_name],
		&"title": session.display_name,
		&"description": str(event.get(&"description", "Complete the marked race session.")).to_upper(),
		&"target": "%s   %s" % [target_prefix, _format_time_usec(target_usec)],
		&"route": "%s   //   %s   //   %s   //   %s   //   %s" % [
			lap_label, String(session.format).replace("_", " "),
			String(session.weather).replace("_", " "), str(event.get(&"meta", "FULL CLASSIFICATION")), difficulty_label,
		],
		&"format": session.format,
		&"laps": session.laps,
		&"weather": session.weather,
		&"difficulty": session.difficulty,
		&"difficulty_mode": difficulty_mode,
		&"difficulty_offset": difficulty_offset,
		&"difficulty_locked": difficulty_locked,
		&"accent": accent,
	}


func _format_time_usec(time_usec: int) -> String:
	if time_usec <= 0:
		return "--:--.---"
	var total_msec := time_usec / 1000
	var minutes := total_msec / 60000
	var seconds := (total_msec / 1000) % 60
	var milliseconds := total_msec % 1000
	return "%02d:%02d.%03d" % [minutes, seconds, milliseconds]


func _set_accent(color: Color) -> void:
	_accent.color = color
	_kicker.add_theme_color_override(&"font_color", color)


func _kill_active_tween() -> void:
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()
	_active_tween = null


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", color)
	label.add_theme_color_override(&"font_outline_color", Color(0.0, 0.0, 0.0, 0.92))
	label.add_theme_constant_override(&"outline_size", maxi(2, int(font_size * 0.07)))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
