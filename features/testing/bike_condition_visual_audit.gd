extends Node
## Render-only layout audit for the damaged-bike HUD strip and warning receipt.


func _ready() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color("382317")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var horizon := ColorRect.new()
	horizon.color = Color("9c4c20")
	horizon.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	horizon.offset_top = -360.0
	horizon.offset_bottom = 0.0
	backdrop.add_child(horizon)

	var hud := preload("res://features/hud/race_hud.tscn").instantiate() as RaceHud
	add_child(hud)
	await get_tree().process_frame
	hud.update_telemetry(47.0, 0.8, true)
	hud.update_flow(62.0, false)
	hud.show_bike_damage(
		8,
		preload("res://features/race/bike_condition_feedback.gd").build(45)
	)
	for _frame: int in 8:
		await get_tree().process_frame

	var image := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path(
		"res://output/bike-condition-visual-audit.png"
	)
	var error := image.save_png(path)
	if error != OK:
		push_error("BIKE CONDITION VISUAL AUDIT: failed to save %s" % path)
		get_tree().quit(1)
		return
	print("BIKE CONDITION VISUAL AUDIT: condition=45 damage=8 capture=%s" % path)
	get_tree().quit(0)
