extends CanvasLayer
class_name GarageUi
## Setup selection and purchase surface projected from the persistent Profile autoload.

signal ride_requested(setup: StringName, activity: StringName)

const SETUPS: Array[StringName] = [&"TRAIL", &"BALANCED", &"ATTACK"]
const EVENTS: Array[StringName] = [&"CIRCUIT", &"FREESTYLE", &"DISCOVERY", &"PINE_ENDURO"]
const CREAM := Color("f7e5b2")
const AMBER := Color("ffb52d")
const CYAN := Color("56d6ff")
const DARK := Color(0.025, 0.03, 0.036, 0.96)

var _root: Control
var _profile_label: Label
var _setup_name: Label
var _tagline: Label
var _description: Label
var _price_label: Label
var _status_label: Label
var _event_label: Label
var _event_description: Label
var _event_meta_label: Label
var _tour_label: Label
var _event_accent: ColorRect
var _repair_label: Label
var _bars: Dictionary[StringName, ProgressBar] = {}
var _event_markers: Array[Label] = []
var _selected_index: int = 1
var _event_index: int = 0
var _open: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	visible = false
	Profile.profile_changed.connect(_on_profile_changed)


func _unhandled_input(event: InputEvent) -> void:
	if not _open or event.is_echo():
		return
	if event.is_action_pressed(InputRouter.GARAGE_LEFT):
		_selected_index = wrapi(_selected_index - 1, 0, SETUPS.size())
		_refresh()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(InputRouter.EVENT_PREVIOUS):
		_event_index = wrapi(_event_index - 1, 0, EVENTS.size())
		_refresh()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(InputRouter.EVENT_NEXT):
		_event_index = wrapi(_event_index + 1, 0, EVENTS.size())
		_refresh()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(InputRouter.REPAIR_BIKE):
		_attempt_repair()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(InputRouter.GARAGE_RIGHT):
		_selected_index = wrapi(_selected_index + 1, 0, SETUPS.size())
		_refresh()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(InputRouter.CONFIRM):
		_confirm_selection()
		get_viewport().set_input_as_handled()


func show_garage() -> void:
	_open = true
	visible = true
	var current_index := SETUPS.find(Profile.current_setup)
	_selected_index = current_index if current_index >= 0 else 1
	_refresh()


func hide_garage() -> void:
	_open = false
	visible = false


func is_open() -> bool:
	return _open


func _confirm_selection() -> void:
	var setup := SETUPS[_selected_index]
	if not Profile.is_setup_unlocked(setup):
		if not Profile.purchase_setup(setup):
			_status_label.text = "NOT ENOUGH CASH — WIN MEDALS TO FUND THE BUILD"
			_status_label.modulate = Color("ff6f5e")
			return
		_status_label.text = "KIT INSTALLED — PRESS CONFIRM TO RIDE"
		_status_label.modulate = CYAN
		_refresh()
		return
	var activity := EVENTS[_event_index]
	if not Profile.is_activity_unlocked(activity):
		_status_label.text = Profile.get_activity_unlock_hint(activity)
		_status_label.modulate = Color("ff6f5e")
		return
	Profile.set_current_setup(setup)
	hide_garage()
	ride_requested.emit(setup, activity)


func _build_ui() -> void:
	_root = Control.new()
	_root.name = "GarageRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var blackout := ColorRect.new()
	blackout.color = Color(0.015, 0.02, 0.025, 0.9)
	blackout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(blackout)

	var amber_stripe := ColorRect.new()
	amber_stripe.color = AMBER
	_anchor_rect(amber_stripe, Vector2.ZERO, Rect2(0.0, 0.0, 18.0, 900.0))
	_root.add_child(amber_stripe)

	var title := _label("THE GARAGE", 58, CREAM)
	_anchor_rect(title, Vector2.ZERO, Rect2(82.0, 60.0, 620.0, 80.0))
	_root.add_child(title)
	var subtitle := _label("RED MESA  //  BUILD FOR THE LINE AHEAD", 19, AMBER)
	_anchor_rect(subtitle, Vector2.ZERO, Rect2(88.0, 137.0, 610.0, 40.0))
	_root.add_child(subtitle)

	_profile_label = _label("", 22, Color("b9c7cf"))
	_profile_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_anchor_rect(_profile_label, Vector2(1.0, 0.0), Rect2(-540.0, 82.0, 460.0, 48.0))
	_root.add_child(_profile_label)
	_event_label = _label("", 21, AMBER)
	_event_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_anchor_rect(_event_label, Vector2(1.0, 0.0), Rect2(-760.0, 132.0, 680.0, 34.0))
	_root.add_child(_event_label)
	_event_description = _label("", 15, Color("9dadb6"))
	_event_description.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_anchor_rect(_event_description, Vector2(1.0, 0.0), Rect2(-840.0, 162.0, 760.0, 30.0))
	_root.add_child(_event_description)
	_event_meta_label = _label("", 13, CYAN)
	_event_meta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_anchor_rect(_event_meta_label, Vector2(1.0, 0.0), Rect2(-840.0, 190.0, 760.0, 28.0))
	_root.add_child(_event_meta_label)
	_repair_label = _label("", 15, Color("9dadb6"))
	_anchor_rect(_repair_label, Vector2.ZERO, Rect2(88.0, 175.0, 620.0, 32.0))
	_root.add_child(_repair_label)
	_tour_label = _label("", 13, CREAM)
	_anchor_rect(_tour_label, Vector2.ZERO, Rect2(88.0, 202.0, 370.0, 28.0))
	_root.add_child(_tour_label)
	_event_accent = ColorRect.new()
	_event_accent.color = AMBER
	_anchor_rect(_event_accent, Vector2(1.0, 0.0), Rect2(-840.0, 216.0, 760.0, 4.0))
	_root.add_child(_event_accent)
	for index: int in EVENTS.size():
		var marker := _label("%02d" % (index + 1), 13, Color("52616a"))
		marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_anchor_rect(marker, Vector2.ZERO, Rect2(88.0 + index * 34.0, 222.0, 28.0, 28.0))
		_root.add_child(marker)
		_event_markers.append(marker)

	var card := ColorRect.new()
	card.color = DARK
	_anchor_rect(card, Vector2(0.5, 0.5), Rect2(-560.0, -235.0, 1120.0, 470.0))
	_root.add_child(card)

	var left_hint := _label("‹  Q / LEFT", 18, Color("7e919d"))
	_anchor_rect(left_hint, Vector2(0.5, 0.5), Rect2(-520.0, -195.0, 160.0, 40.0))
	_root.add_child(left_hint)
	var right_hint := _label("E / RIGHT  ›", 18, Color("7e919d"))
	right_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_anchor_rect(right_hint, Vector2(0.5, 0.5), Rect2(360.0, -195.0, 160.0, 40.0))
	_root.add_child(right_hint)

	_setup_name = _label("BALANCED", 52, AMBER)
	_setup_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_anchor_rect(_setup_name, Vector2(0.5, 0.5), Rect2(-330.0, -200.0, 660.0, 70.0))
	_root.add_child(_setup_name)
	_tagline = _label("", 22, CREAM)
	_tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_anchor_rect(_tagline, Vector2(0.5, 0.5), Rect2(-420.0, -132.0, 840.0, 46.0))
	_root.add_child(_tagline)
	_description = _label("", 18, Color("aab9c2"))
	_description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_anchor_rect(_description, Vector2(0.5, 0.5), Rect2(-420.0, -82.0, 840.0, 64.0))
	_root.add_child(_description)

	var stat_names: Array[StringName] = [&"POWER", &"GRIP", &"SUSPENSION", &"TOP SPEED"]
	for index: int in stat_names.size():
		var stat_name := stat_names[index]
		var label := _label(String(stat_name), 16, Color("8fa0aa"))
		_anchor_rect(label, Vector2(0.5, 0.5), Rect2(-390.0, 5.0 + index * 46.0, 150.0, 28.0))
		_root.add_child(label)
		var bar := ProgressBar.new()
		bar.min_value = 0.0
		bar.max_value = 10.0
		bar.show_percentage = false
		var background := StyleBoxFlat.new()
		background.bg_color = Color("202b32")
		background.corner_radius_top_left = 5
		background.corner_radius_top_right = 5
		background.corner_radius_bottom_left = 5
		background.corner_radius_bottom_right = 5
		var fill := StyleBoxFlat.new()
		fill.bg_color = AMBER
		fill.corner_radius_top_left = 5
		fill.corner_radius_top_right = 5
		fill.corner_radius_bottom_left = 5
		fill.corner_radius_bottom_right = 5
		bar.add_theme_stylebox_override(&"background", background)
		bar.add_theme_stylebox_override(&"fill", fill)
		_anchor_rect(bar, Vector2(0.5, 0.5), Rect2(-210.0, 8.0 + index * 46.0, 600.0, 19.0))
		_root.add_child(bar)
		_bars[stat_name] = bar

	_price_label = _label("", 24, CREAM)
	_price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_anchor_rect(_price_label, Vector2(0.5, 1.0), Rect2(-360.0, -150.0, 720.0, 44.0))
	_root.add_child(_price_label)
	_status_label = _label("", 17, Color("9dadb6"))
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_anchor_rect(_status_label, Vector2(0.5, 1.0), Rect2(-520.0, -102.0, 1040.0, 42.0))
	_root.add_child(_status_label)
	_root.move_child(_tour_label, _root.get_child_count() - 1)
	_root.move_child(_event_accent, _root.get_child_count() - 1)
	for marker: Label in _event_markers:
		_root.move_child(marker, _root.get_child_count() - 1)


func _refresh() -> void:
	var setup := SETUPS[_selected_index]
	var data := _setup_data(setup)
	_setup_name.text = str(data.get(&"name", setup))
	_tagline.text = str(data.get(&"tagline", ""))
	_description.text = str(data.get(&"description", ""))
	_bars[&"POWER"].value = float(data.get(&"power", 5.0))
	_bars[&"GRIP"].value = float(data.get(&"grip", 5.0))
	_bars[&"SUSPENSION"].value = float(data.get(&"suspension", 5.0))
	_bars[&"TOP SPEED"].value = float(data.get(&"speed", 5.0))
	_profile_label.text = "$%06d     RACER REP  %04d" % [Profile.cash, Profile.racer_reputation]
	if Profile.is_setup_unlocked(setup):
		_price_label.text = "INSTALLED" if setup == Profile.current_setup else "OWNED"
		_price_label.modulate = CYAN
		_status_label.text = "W / S EVENT   •   Q / E SETUP   •   ENTER / A RIDE"
		_status_label.modulate = Color("9dadb6")
	else:
		_price_label.text = "$%d TO INSTALL" % Profile.get_setup_price(setup)
		_price_label.modulate = AMBER
		_status_label.text = "W / S EVENT   •   ENTER / A PURCHASE KIT"
		_status_label.modulate = Color("9dadb6")
	_refresh_event()
	var repair_price := Profile.get_repair_price()
	_repair_label.text = "BIKE CONDITION  %03d%%   •   READY" % Profile.bike_condition if repair_price <= 0 else "BIKE CONDITION  %03d%%   •   F / RB REPAIR  $%d" % [Profile.bike_condition, repair_price]


func _attempt_repair() -> void:
	var repair_price := Profile.get_repair_price()
	if repair_price <= 0:
		_status_label.text = "THE BIKE IS ALREADY READY TO RIDE"
		_status_label.modulate = CYAN
		return
	if Profile.repair_bike():
		_refresh()
		_status_label.text = "BIKE RESTORED — POWER, GRIP, AND TOP SPEED RECOVERED"
		_status_label.modulate = CYAN
	else:
		_status_label.text = "NOT ENOUGH CASH FOR REPAIRS"
		_status_label.modulate = Color("ff6f5e")


func _refresh_event() -> void:
	var activity := EVENTS[_event_index]
	var event_color := _event_color(activity)
	var medal := Profile.get_event_medal(activity)
	var is_unlocked := Profile.is_activity_unlocked(activity)
	_event_accent.color = event_color if is_unlocked else Color("74413d")
	_tour_label.text = "RED MESA TOUR   //   %02d / %02d EVENTS CLEARED" % [Profile.get_completed_event_count(), EVENTS.size()]
	for index: int in _event_markers.size():
		var marker_activity := EVENTS[index]
		var marker := _event_markers[index]
		if index == _event_index:
			marker.text = ">%d" % (index + 1)
			_set_label_color(marker, event_color if is_unlocked else Color("ff6f5e"))
		elif Profile.has_completed_event(marker_activity):
			marker.text = "%02d" % (index + 1)
			_set_label_color(marker, AMBER)
		elif Profile.is_activity_unlocked(marker_activity):
			marker.text = "%02d" % (index + 1)
			_set_label_color(marker, Color("7e919d"))
		else:
			marker.text = "--"
			_set_label_color(marker, Color("74413d"))
	match activity:
		&"PINE_ENDURO":
			_profile_label.text = "$%06d     RACER REP  %04d" % [Profile.cash, Profile.racer_reputation]
			_event_label.text = "PINE RIDGE   //   EVENT  04 / 04   //   ENDURO"
			_event_description.text = "Technical woodland loop across roots, ravine jumps, timber lanes, and creek water"
			_event_meta_label.text = "LOCKED   //   %s" % Profile.get_activity_unlock_hint(activity) if not is_unlocked else "MEDAL  %s   //   ROOK  01:04.000   //   %s" % [String(medal), "ROOK BEATEN" if Profile.has_beaten_rival(activity) else "RIVAL ACTIVE"]
		&"FREESTYLE":
			_profile_label.text = "$%06d     FREESTYLER REP  %04d" % [Profile.cash, Profile.freestyler_reputation]
			_event_label.text = "RED MESA   //   EVENT  02 / 04   //   FREESTYLE"
			_event_description.text = "60 seconds to chain airtime, rotation, clean landings, and a rising combo multiplier"
			_event_meta_label.text = "MEDAL  %s   //   BEST  %06d   //   TARGET  007000" % [String(medal), Profile.best_freestyle_score]
		&"DISCOVERY":
			_profile_label.text = "$%06d     EXPLORER REP  %04d" % [Profile.cash, Profile.explorer_reputation]
			_event_label.text = "RED MESA   //   EVENT  03 / 04   //   SALVAGE HUNT"
			var best_text := "--:--.---" if Profile.best_discovery_usec < 0 else _format_usec(Profile.best_discovery_usec)
			_event_description.text = "Find all six hidden workshop caches using only the directional compass and landmarks"
			_event_meta_label.text = "MEDAL  %s   //   BEST  %s   //   SILVER  01:20.000" % [String(medal), best_text]
		_:
			_profile_label.text = "$%06d     RACER REP  %04d" % [Profile.cash, Profile.racer_reputation]
			_event_label.text = "RED MESA   //   EVENT  01 / 04   //   QUARRY CIRCUIT"
			_event_description.text = "Ordered gates, one fast lap, a persistent personal-best ghost, and Rook on the clock"
			_event_meta_label.text = "MEDAL  %s   //   ROOK  00:52.000   //   %s" % [String(medal), "ROOK BEATEN" if Profile.has_beaten_rival(activity) else "RIVAL ACTIVE"]
	_set_label_color(_event_meta_label, event_color if is_unlocked else Color("ff6f5e"))
	if not is_unlocked and Profile.is_setup_unlocked(SETUPS[_selected_index]):
		_status_label.text = "LOCKED   //   %s" % Profile.get_activity_unlock_hint(activity)
		_status_label.modulate = Color("ff6f5e")


func _event_color(activity: StringName) -> Color:
	match activity:
		&"PINE_ENDURO":
			return Color("9fc744")
		&"FREESTYLE":
			return Color("56d6ff")
		&"DISCOVERY":
			return Color("d8b35a")
		_:
			return AMBER


func _set_label_color(label: Label, color: Color) -> void:
	label.modulate = Color.WHITE
	label.add_theme_color_override(&"font_color", color)


func _setup_data(setup: StringName) -> Dictionary:
	match setup:
		&"TRAIL":
			return {&"name": "TRAIL KIT", &"tagline": "SOFT, SURE-FOOTED, HARD TO RATTLE", &"description": "More grip and forgiving suspension for rough ground. Gives up outright speed on the long quarry straights.", &"power": 5.0, &"grip": 9.0, &"suspension": 9.0, &"speed": 5.0}
		&"ATTACK":
			return {&"name": "ATTACK KIT", &"tagline": "POWER FIRST. CONSEQUENCES LATER.", &"description": "A harder engine map and stiff jump setup with less lateral grip. Fast in expert hands and busy everywhere else.", &"power": 9.0, &"grip": 5.0, &"suspension": 7.0, &"speed": 10.0}
		_:
			return {&"name": "BALANCED", &"tagline": "THE BASELINE THAT NEVER MAKES EXCUSES", &"description": "Predictable power, useful grip, and enough suspension for every line in the quarry. The right setup for learning the course.", &"power": 7.0, &"grip": 7.0, &"suspension": 7.0, &"speed": 7.0}


func _on_profile_changed(_cash: int, _reputation: int, _setup: StringName) -> void:
	if _open:
		_refresh()


func _format_usec(time_usec: int) -> String:
	var total_msec := maxi(time_usec / 1000, 0)
	return "%02d:%02d.%03d" % [total_msec / 60000, (total_msec / 1000) % 60, total_msec % 1000]


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", color)
	label.add_theme_color_override(&"font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
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
