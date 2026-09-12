extends Node
class_name AudioCaptionFeed
## Bounded semantic captions for accepted, non-continuous audio feedback.
##
## Continuous engine, tyre, surface, and music layers remain uncaptioned because
## they would overwhelm the rider. GameplayAudio requests captions only after an
## important semantic cue survives its own anti-spam rules.

const DETAIL_MODES: Array[StringName] = [&"OFF", &"IMPORTANT", &"ALL"]
const STYLE_MODES: Array[StringName] = [&"STANDARD", &"HIGH_CONTRAST"]
const PRIORITY_ALL: int = 1
const PRIORITY_IMPORTANT: int = 2
const MAX_QUEUE_SIZE: int = 3
const MAX_TEXT_LENGTH: int = 88
const ALL_DURATION: float = 1.8
const IMPORTANT_DURATION: float = 2.8
const FADE_DURATION: float = 0.35

var _detail: StringName = &"IMPORTANT"
var _caption_scale: float = 1.0
var _style: StringName = &"STANDARD"
var _global_high_contrast: bool = false
var _reduced_motion: bool = false
var _safe_area: float = 0.0
var _panel: PanelContainer
var _label: Label
var _current: Dictionary = {}
var _queue: Array[Dictionary] = []
var _remaining: float = 0.0
var _repeat_count: int = 1
var _accepted_count: int = 0
var _suppressed_count: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_overlay()
	if not EventBus.audio_caption_requested.is_connected(_on_audio_caption_requested):
		EventBus.audio_caption_requested.connect(_on_audio_caption_requested)


func configure(interface: Dictionary) -> void:
	var detail := StringName(str(interface.get("caption_detail", "IMPORTANT")).to_upper())
	_detail = detail if detail in DETAIL_MODES else &"IMPORTANT"
	_caption_scale = clampf(float(interface.get("caption_scale", 1.0)), 0.75, 1.75)
	var style := StringName(str(interface.get("caption_style", "STANDARD")).to_upper())
	_style = style if style in STYLE_MODES else &"STANDARD"
	_global_high_contrast = bool(interface.get("high_contrast", false))
	_reduced_motion = bool(interface.get("reduced_motion", false))
	_safe_area = clampf(float(interface.get("hud_safe_area", 0.0)), 0.0, 0.10)
	_apply_presentation()
	if _detail == &"OFF":
		clear()


func clear() -> void:
	_current.clear()
	_queue.clear()
	_remaining = 0.0
	_repeat_count = 1
	if is_instance_valid(_panel):
		_panel.visible = false
		_panel.modulate.a = 1.0


func request_caption(source: StringName, text: String, priority: int) -> bool:
	var normalized_source := _safe_source(source)
	var normalized_text := _safe_text(text)
	var normalized_priority := clampi(priority, PRIORITY_ALL, PRIORITY_IMPORTANT)
	if (
		_detail == &"OFF"
		or (_detail == &"IMPORTANT" and normalized_priority < PRIORITY_IMPORTANT)
		or normalized_text.is_empty()
	):
		_suppressed_count += 1
		return false
	var entry := {
		&"source": normalized_source,
		&"text": normalized_text,
		&"priority": normalized_priority,
	}
	if (
		not _current.is_empty()
		and StringName(_current.get(&"source", &"")) == normalized_source
		and str(_current.get(&"text", "")) == normalized_text
	):
		_repeat_count = mini(_repeat_count + 1, 9)
		_remaining = _duration_for_priority(normalized_priority)
		_render_current()
		_accepted_count += 1
		return true
	# New information from one source supersedes its old queued information.
	# In particular, never replay 3 / 2 / 1 after the green-light caption.
	for index: int in range(_queue.size() - 1, -1, -1):
		if StringName(_queue[index].get(&"source", &"")) == normalized_source:
			_queue.remove_at(index)
	if _current.is_empty() or normalized_priority >= int(_current.get(&"priority", PRIORITY_ALL)):
		if not _current.is_empty() and StringName(_current.get(&"source", &"")) != normalized_source and _queue.size() < MAX_QUEUE_SIZE:
			_queue.push_front(_current.duplicate(true))
		_show(entry)
	else:
		if _queue.size() >= MAX_QUEUE_SIZE:
			_queue.pop_back()
		_queue.append(entry)
	_accepted_count += 1
	return true


func _process(delta: float) -> void:
	if _current.is_empty() or not is_instance_valid(_panel) or not _panel.visible:
		return
	_remaining -= maxf(delta, 0.0)
	if _remaining <= 0.0:
		_show_next()
		return
	_panel.modulate.a = (
		1.0
		if _reduced_motion or _remaining >= FADE_DURATION
		else clampf(_remaining / FADE_DURATION, 0.0, 1.0)
	)


func get_snapshot() -> Dictionary:
	return {
		&"detail": _detail,
		&"scale": _caption_scale,
		&"style": _style,
		&"effective_high_contrast": _style == &"HIGH_CONTRAST" or _global_high_contrast,
		&"reduced_motion": _reduced_motion,
		&"visible": is_instance_valid(_panel) and _panel.visible,
		&"source": StringName(_current.get(&"source", &"")),
		&"text": str(_current.get(&"text", "")),
		&"display_text": _label.text if is_instance_valid(_label) else "",
		&"priority": int(_current.get(&"priority", 0)),
		&"repeat_count": _repeat_count,
		&"remaining": maxf(_remaining, 0.0),
		&"queue_size": _queue.size(),
		&"accepted_count": _accepted_count,
		&"suppressed_count": _suppressed_count,
		&"panel_rect": _panel.get_global_rect() if is_instance_valid(_panel) else Rect2(),
		&"font_size": _label.get_theme_font_size(&"font_size") if is_instance_valid(_label) else 0,
	}


func _on_audio_caption_requested(source: StringName, text: String, priority: int) -> void:
	request_caption(source, text, priority)


func _show(entry: Dictionary) -> void:
	_current = entry.duplicate(true)
	_repeat_count = 1
	_remaining = _duration_for_priority(int(_current.get(&"priority", PRIORITY_ALL)))
	_render_current()
	_panel.modulate.a = 1.0
	_panel.visible = true


func _show_next() -> void:
	if _queue.is_empty():
		clear()
		return
	_show(_queue.pop_front())


func _render_current() -> void:
	if not is_instance_valid(_label):
		return
	var prefix := String(_current.get(&"source", &"AUDIO")).replace("_", " ")
	var repeat_suffix := "  //  x%d" % _repeat_count if _repeat_count > 1 else ""
	_label.text = "[%s]  %s%s" % [prefix, str(_current.get(&"text", "")), repeat_suffix]


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.name = "AudioCaptionLayer"
	layer.layer = 92
	add_child(layer)
	_panel = PanelContainer.new()
	_panel.name = "AudioCaptionPanel"
	_panel.anchor_left = 0.18
	_panel.anchor_right = 0.82
	_panel.anchor_top = 0.87
	_panel.anchor_bottom = 0.87
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_panel)
	_label = Label.new()
	_label.name = "AudioCaptionText"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.max_lines_visible = 2
	_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_label.add_theme_color_override(&"font_color", Color("f7e5b2"))
	_panel.add_child(_label)
	_panel.visible = false
	_apply_presentation()


func _apply_presentation() -> void:
	if not is_instance_valid(_panel) or not is_instance_valid(_label):
		return
	_panel.anchor_left = 0.25 + _safe_area * 0.5
	_panel.anchor_right = 0.75 - _safe_area * 0.5
	# A dedicated two-line strip below line scoring, above the control/instrument
	# lane. Scale the strip with the text, not with the entire viewport height.
	_panel.offset_top = -ceilf(52.0 * _caption_scale + 20.0)
	_panel.offset_bottom = 0.0
	_label.add_theme_font_size_override(&"font_size", maxi(roundi(20.0 * _caption_scale), 15))
	var high_contrast := _style == &"HIGH_CONTRAST" or _global_high_contrast
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.0, 0.0, 0.0, 0.98 if high_contrast else 0.90)
	panel_style.border_color = Color("ffcf48") if high_contrast else Color("56d6ff")
	panel_style.set_border_width_all(3 if high_contrast else 2)
	panel_style.corner_radius_top_left = 7
	panel_style.corner_radius_top_right = 7
	panel_style.corner_radius_bottom_left = 7
	panel_style.corner_radius_bottom_right = 7
	panel_style.content_margin_left = 18.0
	panel_style.content_margin_right = 18.0
	panel_style.content_margin_top = 10.0
	panel_style.content_margin_bottom = 10.0
	_panel.add_theme_stylebox_override(&"panel", panel_style)
	_label.add_theme_color_override(&"font_color", Color.WHITE if high_contrast else Color("f7e5b2"))


func _duration_for_priority(priority: int) -> float:
	return IMPORTANT_DURATION if priority >= PRIORITY_IMPORTANT else ALL_DURATION


static func _safe_source(source: StringName) -> StringName:
	var normalized := String(source).strip_edges().to_upper()
	if normalized.is_empty():
		return &"AUDIO"
	return StringName(normalized.left(24))


static func _safe_text(text: String) -> String:
	var normalized := text.strip_edges().replace("\n", " ").replace("\r", " ")
	while normalized.contains("  "):
		normalized = normalized.replace("  ", " ")
	return normalized.left(MAX_TEXT_LENGTH)
