extends SceneTree
## High-resolution local overview/chase capture for visual topology checks.

const MESA_SCENE := preload("res://levels/mesa_mx/mesa_mx.tscn")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var shot := "overview"
	var route_ratio := 0.35
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--shot="):
			shot = argument.trim_prefix("--shot=")
		elif argument.begins_with("--route-ratio="):
			route_ratio = clampf(argument.trim_prefix("--route-ratio=").to_float(), 0.0, 1.0)

	var viewport := SubViewport.new()
	viewport.name = "MesaMXVisualProbeViewport"
	viewport.size = Vector2i(1920, 1080)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	get_root().add_child(viewport)
	var level := MESA_SCENE.instantiate()
	viewport.add_child(level)
	var points: PackedVector3Array = level.get_authoritative_route_world()

	var camera := Camera3D.new()
	camera.near = 0.1
	camera.far = 900.0
	level.add_child(camera)
	if shot == "overview":
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 360.0
		camera.global_position = CourseCatalog.MESA_MX_ORIGIN + Vector3(0.0, 330.0, 12.0)
		camera.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	else:
		var route_index := clampi(roundi(route_ratio * float(points.size() - 1)), 0, points.size() - 1)
		var target := points[route_index]
		var tangent := CourseSpline.tangent_at(points, route_index)
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.fov = 66.0
		camera.global_position = target - tangent * 22.0 + Vector3.UP * 7.2
		camera.look_at(target + tangent * 25.0 + Vector3.UP * 1.1, Vector3.UP)
	camera.current = true

	for _frame: int in 14:
		await process_frame
	RenderingServer.force_sync()
	var image := viewport.get_texture().get_image()
	if image == null:
		push_error("MESA_MX_VISUAL_PROBE: viewport image unavailable")
		quit(1)
		return
	var output_path := ProjectSettings.globalize_path("res://.codex_tmp/mesa_mx_%s.png" % shot)
	var result := image.save_png(output_path)
	print("MESA_MX_VISUAL_PROBE shot=%s path=%s result=%s" % [shot, output_path, error_string(result)])
	quit(0 if result == OK else 1)
