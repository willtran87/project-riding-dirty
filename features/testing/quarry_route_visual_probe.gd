extends Node3D
## Captures rider-height sightlines across Quarry Trail for route-legibility audits.

const CAPTURE_RATIOS: Array[float] = [
	0.00, 0.04, 0.08, 0.12, 0.16, 0.20, 0.24, 0.28, 0.32,
	0.36, 0.40, 0.44, 0.48, 0.52, 0.56, 0.60, 0.64, 0.68,
	0.72, 0.76, 0.80, 0.84, 0.88, 0.92, 0.96, 0.99,
]
const CAPTURE_SIZE := Vector2i(2560, 1600)


func _ready() -> void:
	# Use a fixed render target instead of the desktop window. Windows can clamp
	# a 1600px-tall client area to a 1440px display while leaving the filename
	# unchanged, producing misleading high-resolution evidence.
	var render_viewport := SubViewport.new()
	render_viewport.name = "RouteLegibilityViewport"
	render_viewport.size = CAPTURE_SIZE
	render_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	render_viewport.own_world_3d = true
	add_child(render_viewport)
	var quarry_scene := preload("res://levels/quarry/quarry.tscn").instantiate()
	render_viewport.add_child(quarry_scene)
	var camera := Camera3D.new()
	camera.name = "RouteLegibilityCamera"
	camera.fov = 78.0
	camera.near = 0.08
	camera.far = 700.0
	render_viewport.add_child(camera)
	camera.current = true
	for _frame: int in 6:
		await get_tree().process_frame
	var route := CourseCatalog.get_local_riding_points(CourseCatalog.QUARRY_ID)
	var capture_ratios: Array[float] = CAPTURE_RATIOS
	if "--finish-only" in OS.get_cmdline_user_args():
		capture_ratios = [0.96, 0.99]
	elif "--washout-only" in OS.get_cmdline_user_args():
		capture_ratios = [0.80, 0.82, 0.84, 0.86, 0.88]
	elif "--gate8-onward" in OS.get_cmdline_user_args():
		capture_ratios = []
		var checkpoint_ratios := CourseCatalog.get_checkpoint_progress_ratios(CourseCatalog.QUARRY_ID)
		var start_ratio := maxf(checkpoint_ratios[7] - 0.02, 0.0)
		var sample_count := ceili((1.0 - start_ratio) / 0.02)
		for sample_index: int in sample_count + 1:
			capture_ratios.append(minf(start_ratio + float(sample_index) * 0.02, 0.99))
	var space: PhysicsDirectSpaceState3D = quarry_scene.get_world_3d().direct_space_state
	for ratio: float in capture_ratios:
		var index := clampi(roundi(ratio * float(route.size() - 1)), 0, route.size() - 2)
		var look_index := mini(index + 24, route.size() - 1)
		var tangent := CourseSpline.tangent_at(route, index)
		# Additive motocross relief sits above the catalog centerline. Anchor the
		# audit camera to the highest rideable surface so a tall send or receiver
		# cannot put the camera underneath its top-only mesh and masquerade as a
		# solid wall in the route-legibility captures.
		var camera_surface := _highest_rideable_surface(space, route[index])
		var look_surface := _highest_rideable_surface(space, route[look_index])
		camera.global_position = camera_surface + Vector3.UP * 2.45 - tangent * 0.8
		camera.look_at(look_surface + Vector3.UP * 0.85, Vector3.UP)
		for _frame: int in 3:
			await get_tree().process_frame
		var texture := render_viewport.get_texture()
		if texture == null:
			push_error("ROUTE VISUAL PROBE: rendering unavailable; run without --headless")
			get_tree().quit(1)
			return
		var image := texture.get_image()
		if image == null or image.get_size() != CAPTURE_SIZE:
			push_error("ROUTE VISUAL PROBE: expected %s, received %s" % [
				str(CAPTURE_SIZE), str(image.get_size() if image != null else Vector2i.ZERO),
			])
			get_tree().quit(1)
			return
		var percentage := roundi(ratio * 100.0)
		var capture_path := ProjectSettings.globalize_path(
			"res://artifacts/quarry-rider-route-%03d-%dx%d.png" % [
				percentage, CAPTURE_SIZE.x, CAPTURE_SIZE.y,
			]
		)
		var error := image.save_png(capture_path)
		if error != OK:
			push_error("ROUTE VISUAL PROBE: failed to save %s" % capture_path)
			get_tree().quit(1)
			return
		print("ROUTE VISUAL PROBE: ratio=%.2f index=%d position=%s capture=%s" % [
			ratio, index, str(route[index]), capture_path,
		])
	await get_tree().process_frame
	get_tree().quit(0)


func _highest_rideable_surface(space: PhysicsDirectSpaceState3D, center: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(
		center + Vector3.UP * 20.0,
		center + Vector3.DOWN * 20.0,
		2
	)
	var hit: Dictionary = space.intersect_ray(query)
	return hit.get(&"position", center)
