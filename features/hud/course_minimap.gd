extends Control
class_name CourseMinimap
## Original compact course diagram generated from the same baked riding line.

const MAP_LINE := Color(0.95, 0.91, 0.78, 0.92)
const MAP_SHADOW := Color(0.015, 0.02, 0.025, 0.86)
const MAP_ACCENT := Color("ffb52d")
const MARKER_REFRESH_SECONDS: float = 1.0 / 20.0
const MAX_STATIC_DRAW_POINTS: int = 300


class MarkerLayer extends Control:
	var draw_callback: Callable

	func _draw() -> void:
		if draw_callback.is_valid():
			draw_callback.call(self)

var player: Node3D
var _track_id: StringName = &""
var _track_points := PackedVector3Array()
var _map_points := PackedVector2Array()
var _static_draw_points := PackedVector2Array()
var _minimum := Vector2.ZERO
var _span := Vector2.ONE
var _racers: Array[Dictionary] = []
var _marker_layer: MarkerLayer
var _marker_refresh_elapsed: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker_layer = MarkerLayer.new()
	_marker_layer.name = "LiveMarkers"
	_marker_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_marker_layer.draw_callback = Callable(self, &"_draw_live_markers")
	add_child(_marker_layer)
	resized.connect(_on_resized)
	set_process(true)


func configure(track_id: StringName) -> void:
	# Compatibility fallback for callers that have not received the built ribbon.
	configure_route(track_id, CourseCatalog.get_world_riding_points(track_id))


func configure_route(track_id: StringName, authoritative_points: PackedVector3Array) -> void:
	_track_id = track_id
	_track_points = authoritative_points.duplicate()
	_rebuild_map_points()
	visible = not _track_points.is_empty()
	queue_redraw()


func get_track_id() -> StringName:
	return _track_id


func get_route_points() -> PackedVector3Array:
	return _track_points.duplicate()


func get_projected_points() -> PackedVector2Array:
	return _map_points.duplicate()


func project_world_position(world_position: Vector3) -> Vector2:
	return _world_to_map(world_position)


func set_racers(racers: Array) -> void:
	## Replaces the live field projected on the map. Each racer may provide a
	## world_position Vector3 or a Node3D in node/root, plus color and number.
	_racers.clear()
	for value: Variant in racers:
		if value is Dictionary:
			_racers.append((value as Dictionary).duplicate())
	_queue_marker_redraw()


func update_racers(racers: Array) -> void:
	# Semantic alias for sources that publish a fresh classification each tick.
	set_racers(racers)


func clear_racers() -> void:
	_racers.clear()
	_queue_marker_redraw()


func get_racer_snapshots() -> Array[Dictionary]:
	return _racers.duplicate(true)


func _process(delta: float) -> void:
	if not visible or (player == null and _racers.is_empty()):
		return
	_marker_refresh_elapsed += delta
	if _marker_refresh_elapsed >= MARKER_REFRESH_SECONDS:
		_marker_refresh_elapsed = fmod(_marker_refresh_elapsed, MARKER_REFRESH_SECONDS)
		_queue_marker_redraw()


func _on_resized() -> void:
	if _track_points.is_empty():
		return
	_rebuild_map_points()
	queue_redraw()
	_queue_marker_redraw()


func _draw() -> void:
	if _static_draw_points.size() < 2:
		return
	var panel := Rect2(Vector2.ZERO, size)
	draw_rect(panel, Color(0.02, 0.028, 0.034, 0.72), true)
	draw_rect(panel, Color(0.95, 0.71, 0.18, 0.42), false, 2.0)
	draw_polyline(_static_draw_points, MAP_SHADOW, 9.0, true)
	draw_polyline(_static_draw_points, MAP_LINE, 4.0, true)
	draw_circle(_map_points[0], 5.5, Color("56d6ff"))
	draw_circle(_map_points[-1], 5.5, Color("f7e5b2"))


func _draw_live_markers(canvas: CanvasItem) -> void:
	if _map_points.size() < 2:
		return
	var player_was_drawn := false
	for racer: Dictionary in _racers:
		if _is_player_racer(racer):
			continue
		_draw_racer(canvas, racer, false)
	for racer: Dictionary in _racers:
		if not _is_player_racer(racer):
			continue
		player_was_drawn = _draw_racer(canvas, racer, true) or player_was_drawn
	if player != null and not player_was_drawn:
		var player_map := _world_to_map(player.global_position)
		_draw_numbered_marker(canvas, player_map, MAP_ACCENT, 1, true)


func _queue_marker_redraw() -> void:
	if is_instance_valid(_marker_layer):
		_marker_layer.queue_redraw()


func _draw_racer(canvas: CanvasItem, racer: Dictionary, is_player: bool) -> bool:
	var world_position: Variant = _racer_world_position(racer)
	if world_position == null:
		return false
	var color_value: Variant = racer.get(&"color", MAP_ACCENT if is_player else MAP_LINE)
	var marker_color: Color = color_value if color_value is Color else Color.from_string(str(color_value), MAP_LINE)
	var number := int(racer.get(&"number", 1 if is_player else 0))
	_draw_numbered_marker(canvas, _world_to_map(world_position as Vector3), marker_color, number, is_player)
	return true


func _draw_numbered_marker(canvas: CanvasItem, map_position: Vector2, marker_color: Color, number: int, emphasized: bool) -> void:
	var shadow_radius := 7.2 if emphasized else 5.6
	var marker_radius := 5.2 if emphasized else 4.1
	canvas.draw_circle(map_position, shadow_radius, MAP_SHADOW)
	canvas.draw_circle(map_position, marker_radius, marker_color)
	if emphasized:
		canvas.draw_arc(map_position, 7.4, 0.0, TAU, 24, Color.WHITE, 1.5, true)
	var number_text := str(number) if number > 0 else "\u2022"
	var font := get_theme_default_font()
	var font_size := 8 if number < 10 else 7
	var text_size := font.get_string_size(number_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	var baseline := map_position + Vector2(-text_size.x * 0.5, text_size.y * 0.34)
	canvas.draw_string(font, baseline, number_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, _legible_text_color(marker_color))


func _racer_world_position(racer: Dictionary) -> Variant:
	var position_value: Variant = racer.get(&"world_position", null)
	if position_value is Vector3:
		return position_value
	for key: StringName in [&"node", &"root", &"bike"]:
		var node_value: Variant = racer.get(key, null)
		if node_value is Node3D and is_instance_valid(node_value):
			return (node_value as Node3D).global_position
	return null


func _is_player_racer(racer: Dictionary) -> bool:
	return bool(racer.get(&"is_player", false)) or StringName(racer.get(&"rider_id", &"")) == &"PLAYER"


func _legible_text_color(background: Color) -> Color:
	var luminance := background.r * 0.299 + background.g * 0.587 + background.b * 0.114
	return Color("10151a") if luminance > 0.58 else Color.WHITE


func _rebuild_map_points() -> void:
	_map_points.clear()
	_static_draw_points.clear()
	if _track_points.is_empty():
		return
	_minimum = Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for point: Vector3 in _track_points:
		var planar := Vector2(point.x, point.z)
		_minimum.x = minf(_minimum.x, planar.x)
		_minimum.y = minf(_minimum.y, planar.y)
		maximum.x = maxf(maximum.x, planar.x)
		maximum.y = maxf(maximum.y, planar.y)
	_span = maximum - _minimum
	_map_points.resize(_track_points.size())
	for index: int in _track_points.size():
		_map_points[index] = _world_to_map(_track_points[index])
	_static_draw_points = _sample_static_draw_points(_map_points)


func _sample_static_draw_points(source: PackedVector2Array) -> PackedVector2Array:
	if source.size() <= MAX_STATIC_DRAW_POINTS:
		return source.duplicate()
	var output := PackedVector2Array()
	var stride := ceili(float(source.size() - 1) / float(MAX_STATIC_DRAW_POINTS - 1))
	for index: int in range(0, source.size() - 1, stride):
		output.append(source[index])
	output.append(source[-1])
	return output


func _world_to_map(world_position: Vector3) -> Vector2:
	var padding := 16.0
	var available := Vector2(
		maxf(size.x - padding * 2.0, 1.0),
		maxf(size.y - padding * 2.0, 1.0)
	)
	var scale_value := minf(
		available.x / maxf(_span.x, 1.0),
		available.y / maxf(_span.y, 1.0)
	)
	var content_size := _span * scale_value
	var offset := (size - content_size) * 0.5
	var normalized := Vector2(world_position.x, world_position.z) - _minimum
	return offset + Vector2(normalized.x, normalized.y) * scale_value
