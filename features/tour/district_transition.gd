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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	visible = false


func cover(activity: StringName) -> void:
	_kill_active_tween()
	_configure(activity)
	visible = true
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
	match activity:
		&"PINE_ENDURO":
			_kicker.text = "DISTRICT 02   //   PINE RIDGE"
			_title.text = "TIMBERLINE ENDURO"
			_description.text = "ROOTS, RAVINES, CREEK WATER — COMMIT EARLY AND KEEP THE BIKE LIGHT"
			_rival.text = "ROOK'S TARGET   01:04.000"
			_route.text = "7 GATES   •   TECHNICAL TRAIL   •   PERSONAL-BEST GHOST"
			_set_accent(Color("9fc744"))
		&"FREESTYLE":
			_kicker.text = "DISTRICT 01   //   RED MESA"
			_title.text = "QUARRY FREESTYLE"
			_description.text = "SIXTY SECONDS. LINK CLEAN AIR AND MAKE EVERY LANDING COUNT."
			_rival.text = "CREW TARGET   007000 POINTS"
			_route.text = "AIRTIME   •   ROTATION   •   CLEAN-LANDING COMBOS"
			_set_accent(Color("56d6ff"))
		&"DISCOVERY":
			_kicker.text = "DISTRICT 01   //   RED MESA"
			_title.text = "SALVAGE RUN"
			_description.text = "FOLLOW THE NEEDLE, READ THE LAND, BRING ALL SIX CACHES HOME."
			_rival.text = "CREW TARGET   01:20.000"
			_route.text = "6 CACHES   •   OPEN ROUTE   •   NO MAP"
			_set_accent(Color("d8b35a"))
		_:
			_kicker.text = "DISTRICT 01   //   RED MESA"
			_title.text = "QUARRY CIRCUIT"
			_description.text = "SIX GATES. ONE CLEAN LAP. FIND THE LINE THAT ROOK MISSED."
			_rival.text = "ROOK'S TARGET   00:52.000"
			_route.text = "6 GATES   •   SPRINT FORMAT   •   PERSONAL-BEST GHOST"
			_set_accent(AMBER)


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
