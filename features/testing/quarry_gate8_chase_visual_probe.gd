extends Node3D
## Captures the real bike/chase-camera view from HUD Gate 8 through Gate 11.
##
## This guards against technically traversable geometry that still reads as a
## dead end from the player's camera. Checkpoint arches are the production race
## controller's own nodes, so the photographed gate numbering matches gameplay.
## Optional --chain-start, --chain-end, and --sample-spacing arguments allow a
## dense audit of any reported section without changing the production route.

const START_MARGIN_METERS: float = 20.0
const END_MARGIN_METERS: float = 25.0
const SAMPLE_SPACING_METERS: float = 10.0
const AUDIT_SPEED_MPS: float = 22.0


func _ready() -> void:
	var viewport_size := _requested_viewport_size()
	var capture_prefix := _requested_prefix()
	var render_viewport := SubViewport.new()
	render_viewport.name = "Gate8ChaseAuditViewport"
	render_viewport.size = viewport_size
	render_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	render_viewport.own_world_3d = true
	add_child(render_viewport)

	var quarry := preload("res://levels/quarry/quarry.tscn").instantiate()
	quarry.name = "Quarry"
	render_viewport.add_child(quarry)
	var bike: DirtBikeController = preload("res://entities/bike/bike.tscn").instantiate()
	render_viewport.add_child(bike)
	var chase_camera: ChaseCamera = preload("res://features/camera/chase_camera.tscn").instantiate()
	render_viewport.add_child(chase_camera)
	var race: RaceController = preload("res://features/race/race_controller.tscn").instantiate()
	render_viewport.add_child(race)

	for _frame: int in 10:
		await get_tree().process_frame
	var route: PackedVector3Array = quarry.call(&"get_authoritative_route_world")
	race.configure_track(CourseCatalog.QUARRY_ID, route, quarry)
	bike.set_controls_enabled(false)
	bike.set_motion_locked(true)
	chase_camera.target = bike
	race.call(&"_set_gates_visible", true)

	var cumulative := _cumulative_distances(route)
	var route_length := float(cumulative[-1])
	var checkpoint_ratios := CourseCatalog.get_checkpoint_progress_ratios(CourseCatalog.QUARRY_ID, route)
	var checkpoint_chains := PackedFloat32Array()
	for ratio: float in checkpoint_ratios:
		checkpoint_chains.append(ratio * route_length)
	# HUD Gate 8 begins after physical Gate 7 (checkpoint index 6), not after the
	# arch numbered 8. Include the complete displayed sector in every audit.
	var start_chain := maxf(float(checkpoint_chains[6]) - START_MARGIN_METERS, 0.0)
	var end_chain := minf(float(checkpoint_chains[10]) + END_MARGIN_METERS, route_length)
	var requested_start := _requested_float("--chain-start=", -1.0)
	var requested_end := _requested_float("--chain-end=", -1.0)
	var sample_spacing := maxf(_requested_float("--sample-spacing=", SAMPLE_SPACING_METERS), 1.0)
	if requested_start >= 0.0:
		start_chain = clampf(requested_start, 0.0, route_length)
	if requested_end >= 0.0:
		end_chain = clampf(requested_end, start_chain, route_length)
	var sample_count := ceili((end_chain - start_chain) / sample_spacing)
	var space: PhysicsDirectSpaceState3D = quarry.get_world_3d().direct_space_state
	print("GATE8 CHASE VISUAL: viewport=%s start=%.2f end=%.2f gate8=%.2f gate9=%.2f gate10=%.2f gate11=%.2f" % [
		str(viewport_size), start_chain, end_chain,
		float(checkpoint_chains[7]), float(checkpoint_chains[8]),
		float(checkpoint_chains[9]), float(checkpoint_chains[10]),
	])

	for sample_index: int in sample_count + 1:
		var chain := minf(start_chain + float(sample_index) * sample_spacing, end_chain)
		var route_index := _index_at_chain(cumulative, chain)
		var tangent := CourseSpline.tangent_at(route, route_index)
		var surface := _highest_rideable_surface(space, route[route_index])
		var bike_transform := Transform3D(
			Basis.looking_at(tangent, Vector3.UP),
			surface + Vector3.UP * 0.72
		)
		bike.respawn_at(bike_transform)
		# Frozen motion keeps every capture at its exact chainage while retaining
		# production speed-FOV and trajectory prediction in the chase camera.
		bike.linear_velocity = tangent * AUDIT_SPEED_MPS
		race.set("_expected_checkpoint", _expected_checkpoint_at(chain, checkpoint_chains))
		race.call(&"_update_gate_visuals")
		chase_camera.snap_to_target()
		for _frame: int in 4:
			await get_tree().physics_frame
			await get_tree().process_frame
		var texture := render_viewport.get_texture()
		if texture == null:
			push_error("GATE8 CHASE VISUAL: rendering is unavailable; run without --headless")
			get_tree().quit(1)
			return
		var image := texture.get_image()
		if image == null:
			push_error("GATE8 CHASE VISUAL: no rendered image; run without --headless")
			get_tree().quit(1)
			return
		var capture_path := ProjectSettings.globalize_path(
			"res://artifacts/%s-chain-%04d-%dx%d.png" % [
				capture_prefix, roundi(chain), viewport_size.x, viewport_size.y,
			]
		)
		var error := image.save_png(capture_path)
		if error != OK:
			push_error("GATE8 CHASE VISUAL: failed to save %s" % capture_path)
			get_tree().quit(1)
			return
		print("GATE8 CHASE VISUAL: chain=%.2f gate=%02d index=%d capture=%s" % [
			chain, _expected_checkpoint_at(chain, checkpoint_chains) + 1,
			route_index, capture_path,
		])
	get_tree().quit(0)


func _requested_viewport_size() -> Vector2i:
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--viewport=1920x1080":
			return Vector2i(1920, 1080)
	return Vector2i(2560, 1600)


func _requested_prefix() -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-prefix="):
			return argument.trim_prefix("--capture-prefix=").validate_filename()
	return "quarry-gate8-chase"


func _requested_float(prefix: String, fallback: float) -> float:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix).to_float()
	return fallback


func _cumulative_distances(route: PackedVector3Array) -> PackedFloat32Array:
	var cumulative := PackedFloat32Array()
	cumulative.resize(route.size())
	for index: int in range(1, route.size()):
		cumulative[index] = cumulative[index - 1] + route[index - 1].distance_to(route[index])
	return cumulative


func _index_at_chain(cumulative: PackedFloat32Array, chain: float) -> int:
	var low := 0
	var high := cumulative.size() - 1
	while low < high:
		var middle := (low + high) / 2
		if float(cumulative[middle]) < chain:
			low = middle + 1
		else:
			high = middle
	return clampi(low, 0, cumulative.size() - 1)


func _expected_checkpoint_at(chain: float, checkpoint_chains: PackedFloat32Array) -> int:
	var expected := 0
	while expected < checkpoint_chains.size() and chain >= float(checkpoint_chains[expected]):
		expected += 1
	return mini(expected, checkpoint_chains.size() - 1)


func _highest_rideable_surface(space: PhysicsDirectSpaceState3D, center: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(
		center + Vector3.UP * 20.0,
		center + Vector3.DOWN * 20.0,
		2
	)
	var hit: Dictionary = space.intersect_ray(query)
	return hit.get(&"position", center)
