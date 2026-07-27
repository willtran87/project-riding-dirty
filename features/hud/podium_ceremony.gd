extends Control
class_name PodiumCeremony
## Animated, data-driven top-three ceremony used by the official race results.

const CREAM := Color("f7e5b2")
const AMBER := Color("ffb52d")
const CYAN := Color("56d6ff")
const MUTED := Color("8b989f")
const DARK := Color("111820")
const RIDER_GRAPHICS_CATALOG := preload("res://features/career/rider_graphics_catalog.gd")
const POSITION_ORDER := [1, 0, 2]
const OPPONENT_COLORS := [
	Color("e05b45"), Color("77b65d"), Color("7f86d9"),
	Color("d06fa5"), Color("4fb6a8"), Color("cf9147"),
]

var _podium: Array[Dictionary] = []
var _event_name: String = ""
var _player_position: int = 0
var _cosmetics: Dictionary = {}
var _reveal: float = 1.0
var _idle_time: float = 0.0
var _reduced_motion: bool = false
var _compact: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	custom_minimum_size = Vector2(0.0, 150.0)
	resized.connect(queue_redraw)
	set_process(false)


func present(
	classification: Array[Dictionary],
	result: Dictionary,
	cosmetics: Dictionary
) -> void:
	_podium.clear()
	for position: int in range(1, 4):
		for racer: Dictionary in classification:
			if int(racer.get(&"position", 0)) != position:
				continue
			var entry := racer.duplicate(true)
			if bool(entry.get(&"is_player", false)):
				entry[&"number"] = clampi(int(cosmetics.get(&"rider_number", 17)), 1, 999)
				entry[&"accent"] = _player_accent(cosmetics)
				entry[&"body_type"] = StringName(cosmetics.get(&"body_type", &"ATHLETIC"))
				entry[&"team_palette"] = StringName(cosmetics.get(&"team_palette", &"STYLE"))
				entry[&"decal_id"] = StringName(cosmetics.get(&"decal_id", &"CLEAN"))
				entry[&"sponsor_id"] = StringName(cosmetics.get(&"sponsor_id", &"NONE"))
				entry[&"sponsor_placement"] = StringName(cosmetics.get(&"sponsor_placement", &"SHROUDS"))
			_podium.append(entry)
			break
	_event_name = str(result.get(
		&"event_name",
		result.get(&"display_name", result.get(&"event_id", "OFFICIAL EVENT"))
	)).replace("_", " ").to_upper()
	_player_position = int(result.get(&"player_position", _find_player_position(classification)))
	_cosmetics = cosmetics.duplicate(true)
	visible = not _podium.is_empty()
	_reveal = 1.0 if _reduced_motion else 0.0
	_idle_time = 0.0
	set_process(visible and not _reduced_motion)
	queue_redraw()


func clear() -> void:
	_podium.clear()
	_event_name = ""
	_player_position = 0
	_cosmetics.clear()
	visible = false
	set_process(false)
	queue_redraw()


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	if enabled:
		_reveal = 1.0
		set_process(false)
	elif visible:
		set_process(true)
	queue_redraw()


func set_compact(enabled: bool) -> void:
	if _compact == enabled:
		return
	_compact = enabled
	custom_minimum_size.y = 94.0 if _compact else 150.0
	queue_redraw()


func get_presentation_snapshot() -> Dictionary:
	var top_three: Array[Dictionary] = []
	for entry: Dictionary in _podium:
		top_three.append({
			&"position": int(entry.get(&"position", 0)),
			&"rider_id": StringName(entry.get(&"rider_id", &"")),
			&"display_name": str(entry.get(&"display_name", "")),
			&"number": int(entry.get(&"number", 0)),
			&"is_player": bool(entry.get(&"is_player", false)),
		})
	return {
		&"visible": visible and is_visible_in_tree(),
		&"event_name": _event_name,
		&"player_position": _player_position,
		&"player_on_podium": _player_position in [1, 2, 3],
		&"top_three": top_three,
		&"compact": _compact,
		&"reduced_motion": _reduced_motion,
		&"reveal": _reveal,
		&"rider_number": clampi(int(_cosmetics.get(&"rider_number", 17)), 1, 999),
		&"body_type": StringName(_cosmetics.get(&"body_type", &"ATHLETIC")),
		&"jersey": str(_cosmetics.get(&"jersey", "")),
			&"livery": str(_cosmetics.get(&"bike_livery", "")),
			&"team_palette": str(_cosmetics.get(&"team_palette", "STYLE")),
			&"decal_id": str(_cosmetics.get(&"decal_id", "CLEAN")),
			&"sponsor_id": str(_cosmetics.get(&"sponsor_id", "NONE")),
			&"sponsor_placement": str(_cosmetics.get(&"sponsor_placement", "SHROUDS")),
		&"rect": get_global_rect(),
	}


func _process(delta: float) -> void:
	_idle_time += delta
	if _reveal < 1.0:
		_reveal = minf(_reveal + delta * 2.7, 1.0)
	queue_redraw()


func _draw() -> void:
	if _podium.is_empty() or size.x < 1.0 or size.y < 1.0:
		return
	var width := size.x
	var height := size.y
	var header_height := 18.0 if _compact else 24.0
	draw_rect(Rect2(0.0, 0.0, width, height), Color(0.018, 0.027, 0.034, 0.92))
	draw_rect(Rect2(0.0, 0.0, width, 2.0), Color(AMBER, 0.85))
	draw_line(Vector2(width * 0.08, header_height), Vector2(width * 0.92, header_height), Color(AMBER, 0.28), 1.0)
	_draw_centered_text(
		"OFFICIAL PODIUM  //  %s" % _event_name,
		Vector2(0.0, 3.0), width, 11 if _compact else 13, AMBER
	)

	var stage_top := header_height + (5.0 if _compact else 8.0)
	var stage_bottom := height - (5.0 if _compact else 8.0)
	var slot_width := minf(width * 0.29, 285.0)
	var centers := [width * 0.23, width * 0.5, width * 0.77]
	var block_heights := [18.0, 30.0, 13.0] if _compact else [27.0, 46.0, 20.0]
	var reveal_delays := [0.16, 0.0, 0.30]
	for visual_index: int in POSITION_ORDER.size():
		var podium_index: int = POSITION_ORDER[visual_index]
		if podium_index >= _podium.size():
			continue
		var entry := _podium[podium_index]
		var reveal := clampf((_reveal - reveal_delays[visual_index]) / 0.70, 0.0, 1.0)
		var eased := 1.0 - pow(1.0 - reveal, 3.0)
		var center: float = centers[visual_index]
		var block_height: float = block_heights[visual_index]
		var block_top := stage_bottom - block_height
		var accent := _entry_accent(entry, podium_index)
		var is_player := bool(entry.get(&"is_player", false))
		var bob := 0.0
		if not _reduced_motion and reveal >= 1.0:
			bob = sin(_idle_time * 2.1 + float(visual_index)) * (0.8 if _compact else 1.6)
		var rider_bottom := block_top - (2.0 if _compact else 4.0)
		var rider_height := 31.0 if _compact else 53.0
		var rider_top := rider_bottom - rider_height
		var arrival_offset := (1.0 - eased) * (18.0 if _compact else 34.0)
		var rider_center := Vector2(center, rider_top + rider_height * 0.52 + arrival_offset + bob)
		if podium_index == 0:
			var beam_width := slot_width * 0.86
			draw_colored_polygon(PackedVector2Array([
				Vector2(center - beam_width * 0.18, stage_top),
				Vector2(center + beam_width * 0.18, stage_top),
				Vector2(center + beam_width * 0.48, block_top),
				Vector2(center - beam_width * 0.48, block_top),
			]), Color(accent, 0.055 + 0.05 * sin(_idle_time * 1.4) if not _reduced_motion else 0.07))
		_draw_rider(rider_center, rider_height, entry, accent, eased)
		var plate_size := Vector2(37.0, 15.0) if _compact else Vector2(52.0, 20.0)
		var plate_rect := Rect2(center - plate_size.x * 0.5, rider_bottom - plate_size.y * 0.62, plate_size.x, plate_size.y)
		draw_rect(plate_rect, Color(0.94, 0.92, 0.82, eased), true)
		draw_rect(plate_rect, Color(accent, eased), false, 2.0)
		var number := int(entry.get(&"number", podium_index + 1))
		_draw_centered_text(
			"%03d" % clampi(number, 0, 999),
			Vector2(plate_rect.position.x, plate_rect.position.y + (0.0 if _compact else 1.0)),
			plate_rect.size.x, 9 if _compact else 12, Color(DARK, eased)
		)
		var block_rect := Rect2(
			center - slot_width * 0.5, block_top + (1.0 - eased) * block_height,
			slot_width, block_height * eased
		)
		draw_rect(block_rect, Color(accent.darkened(0.68), 0.95))
		draw_rect(block_rect, Color(accent, 0.72), false, 2.0)
		_draw_centered_text(
			"P%d" % int(entry.get(&"position", podium_index + 1)),
			Vector2(block_rect.position.x, block_rect.position.y + 1.0),
			block_rect.size.x, 10 if _compact else 15, Color(accent, eased)
		)
		var name := str(entry.get(&"display_name", entry.get(&"rider_id", "RIDER"))).to_upper()
		var name_color := CREAM if is_player else Color("d8e0e3")
		_draw_centered_text(
			name,
			Vector2(center - slot_width * 0.55, rider_top - (1.0 if _compact else 4.0)),
			slot_width * 1.1, 9 if _compact else 12, Color(name_color, eased)
		)
		if is_player:
			draw_line(
				Vector2(center - slot_width * 0.30, rider_top - 5.0),
				Vector2(center + slot_width * 0.30, rider_top - 5.0),
				Color(CYAN, 0.9 * eased), 2.0
			)


func _draw_rider(
	center: Vector2,
	height: float,
	entry: Dictionary,
	accent: Color,
	reveal: float
) -> void:
	var is_player := bool(entry.get(&"is_player", false))
	var body_type := StringName(entry.get(&"body_type", &"ATHLETIC"))
	var width_scale := 0.82 if body_type == &"COMPACT" else 1.16 if body_type == &"POWERFUL" else 1.0
	if not is_player:
		width_scale = 0.92 + float(abs(hash(str(entry.get(&"rider_id", "")))) % 18) / 100.0
	var helmet_radius := height * 0.13
	var torso_width := height * 0.34 * width_scale
	var torso_top := center.y - height * 0.13
	var torso_bottom := center.y + height * 0.39
	var silhouette := Color(accent.darkened(0.48), reveal)
	draw_circle(Vector2(center.x, center.y - height * 0.31), helmet_radius, Color(accent, reveal))
	draw_arc(Vector2(center.x, center.y - height * 0.31), helmet_radius, 0.0, TAU, 18, Color(CREAM, 0.72 * reveal), 1.0)
	draw_colored_polygon(PackedVector2Array([
		Vector2(center.x - torso_width * 0.42, torso_top),
		Vector2(center.x + torso_width * 0.42, torso_top),
		Vector2(center.x + torso_width * 0.58, torso_bottom),
		Vector2(center.x - torso_width * 0.58, torso_bottom),
	]), silhouette)
	draw_line(
		Vector2(center.x - torso_width * 0.36, center.y + height * 0.02),
		Vector2(center.x - torso_width * 0.76, center.y + height * 0.29),
		Color(accent, reveal), maxf(2.0, height * 0.065)
	)
	draw_line(
		Vector2(center.x + torso_width * 0.36, center.y + height * 0.02),
		Vector2(center.x + torso_width * 0.76, center.y + height * 0.29),
		Color(accent, reveal), maxf(2.0, height * 0.065)
	)
	if is_player:
		draw_line(
			Vector2(center.x - torso_width * 0.40, center.y + height * 0.06),
			Vector2(center.x + torso_width * 0.40, center.y + height * 0.06),
			Color(CREAM, reveal), 2.0
		)


func _draw_centered_text(
	text: String,
	position: Vector2,
	width: float,
	font_size: int,
	color: Color
) -> void:
	draw_string(
		ThemeDB.fallback_font, position + Vector2(0.0, float(font_size)),
		text, HORIZONTAL_ALIGNMENT_CENTER, width, font_size, color
	)


func _entry_accent(entry: Dictionary, index: int) -> Color:
	var raw: Variant = entry.get(&"accent", null)
	if raw is Color:
		return raw as Color
	var rider_hash: int = absi(hash(str(entry.get(&"rider_id", index))))
	return OPPONENT_COLORS[rider_hash % OPPONENT_COLORS.size()]


func _player_accent(cosmetics: Dictionary) -> Color:
	var palette := RIDER_GRAPHICS_CATALOG.palette(cosmetics.get(&"team_palette", &"STYLE"))
	if StringName(palette.get(&"palette_id", &"STYLE")) != &"STYLE":
		return Color.from_string("#" + str(palette.get(&"primary", "56D6FF")), CYAN)
	var value := str(cosmetics.get(&"accent_color", "E25532")).strip_edges().trim_prefix("#")
	return Color(value) if value.length() in [6, 8] and value.is_valid_hex_number(false) else CYAN


func _find_player_position(classification: Array[Dictionary]) -> int:
	for racer: Dictionary in classification:
		if bool(racer.get(&"is_player", false)):
			return int(racer.get(&"position", 0))
	return 0
