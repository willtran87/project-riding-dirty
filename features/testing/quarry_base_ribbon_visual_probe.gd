extends Node3D
## High-resolution player-height audit of the complete HUD Gate 8 -> finish.
##
## Unlike the older Gate-8 probe, the bike is always anchored to the catalog's
## welded base-ribbon centerline. It never raycasts upward onto an additive jump
## overlay. This makes a jump that blocks the base line visible from the same
## approach height the player actually has.

const AUDIT_SPEED_MPS := 22.0
const APPROACH_OFFSETS_METERS: Array[float] = [-38.0, -20.0, -8.0]

# These were the player-blocking jump packages served by earlier 8777 entry
# points. Keep their exact locations in the regression probe even after removal
# so every formerly broken location continues to be photographed.
const LEGACY_POST_GATE8_OBSTACLES: Array[Dictionary] = [
	{&"name": &"HighBenchSend", &"center_chain": 698.649, &"length": 14.0},
	{&"name": &"HighBenchLanding", &"center_chain": 732.395, &"length": 22.0},
	{&"name": &"ConveyorFlySend", &"point_a": 12, &"point_b": 13, &"weight": 0.31, &"length": 14.0},
	{&"name": &"ConveyorFlyLanding", &"point_a": 12, &"point_b": 13, &"weight": 0.54, &"length": 22.0},
	{&"name": &"WashoutSend", &"point_a": 16, &"point_b": 17, &"weight": 0.30, &"length": 14.0},
	{&"name": &"WashoutLanding", &"point_a": 16, &"point_b": 17, &"weight": 0.54, &"length": 22.0},
]


func _ready() -> void:
	var viewport_size := _requested_viewport_size()
	var render_viewport := SubViewport.new()
	render_viewport.name = "QuarryBaseRibbonAuditViewport"
	render_viewport.size = viewport_size
	render_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	render_viewport.own_world_3d = true
	add_child(render_viewport)

	var quarry := preload("res://levels/quarry/quarry.tscn").instantiate() as Node3D
	quarry.name = "Quarry"
	render_viewport.add_child(quarry)
	var bike := preload("res://entities/bike/bike.tscn").instantiate() as DirtBikeController
	render_viewport.add_child(bike)
	var chase_camera := preload("res://features/camera/chase_camera.tscn").instantiate() as ChaseCamera
	render_viewport.add_child(chase_camera)
	var race := preload("res://features/race/race_controller.tscn").instantiate() as RaceController
	render_viewport.add_child(race)

	for _frame: int in 12:
		await get_tree().process_frame
	var route: PackedVector3Array = quarry.call(&"get_authoritative_route_world")
	race.configure_track(CourseCatalog.QUARRY_ID, route, quarry)
	bike.set_controls_enabled(false)
	bike.set_motion_locked(true)
	chase_camera.target = bike
	race.call(&"_set_gates_visible", true)

	var controls := CourseCatalog.get_local_points(CourseCatalog.QUARRY_ID)
	var cumulative := _cumulative_distances(route)
	var checkpoint_chains := _checkpoint_chains(float(cumulative[-1]), route)
	# The HUD changes to GATE 08 after physical Gate 7 is crossed.
	var gate8_chain := float(checkpoint_chains[6])
	var physical_gate8_chain := float(checkpoint_chains[7])
	var finish_chain := float(checkpoint_chains[-1])
	var obstacles := _legacy_obstacle_ranges(controls, route, cumulative)
	var live_names := _live_post_gate8_obstacle_names(quarry, gate8_chain, cumulative)

	print("BASE-RIBBON VISUAL: viewport=%s hud_gate08_start=%.2f physical_gate08=%.2f finish=%.2f live_post_gate8_ramps=%s" % [
		str(viewport_size), gate8_chain, physical_gate8_chain, finish_chain, str(live_names),
	])
	for obstacle: Dictionary in obstacles:
		var obstacle_name := StringName(obstacle[&"name"])
		print("BASE-RIBBON OBSTACLE SITE: name=%s start=%.2f center=%.2f end=%.2f gate_sector=%02d->%02d live_collision=%s" % [
			String(obstacle_name), float(obstacle[&"start_chain"]),
			float(obstacle[&"center_chain"]), float(obstacle[&"end_chain"]),
			_expected_checkpoint_at(float(obstacle[&"start_chain"]), checkpoint_chains),
			_expected_checkpoint_at(float(obstacle[&"end_chain"]), checkpoint_chains),
			str(obstacle_name in live_names),
		])

	var capture_requests: Array[Dictionary] = []
	_add_capture(capture_requests, gate8_chain - 12.0, "physical-gate07-approach")
	_add_capture(capture_requests, gate8_chain + 8.0, "hud-gate08-sector-entry")
	_add_capture(capture_requests, physical_gate8_chain - 12.0, "physical-gate08-approach")
	_add_capture(capture_requests, physical_gate8_chain + 8.0, "physical-gate08-exit")
	for obstacle: Dictionary in obstacles:
		for offset: float in APPROACH_OFFSETS_METERS:
			_add_capture(
				capture_requests,
				float(obstacle[&"start_chain"]) + offset,
				"%s-approach-%02dm" % [String(obstacle[&"name"]), absi(roundi(offset))]
			)
		_add_capture(
			capture_requests,
			float(obstacle[&"center_chain"]),
			"%s-center-base" % String(obstacle[&"name"])
		)
	# Photograph every remaining physical checkpoint from a short approach. This
	# closes the old Gate-11 cutoff and proves the visual audit reached the finish.
	for checkpoint_index: int in range(7, checkpoint_chains.size()):
		_add_capture(
			capture_requests,
			float(checkpoint_chains[checkpoint_index]) - 14.0,
			"physical-gate%02d-approach" % (checkpoint_index + 1)
		)
	_add_capture(capture_requests, finish_chain + 18.0, "finish-runoff")
	capture_requests.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a[&"chain"]) < float(b[&"chain"])
	)

	for request: Dictionary in capture_requests:
		var chain := clampf(float(request[&"chain"]), gate8_chain - 14.0, float(cumulative[-1]))
		var route_index := _index_at_chain(cumulative, chain)
		var tangent := CourseSpline.tangent_at(route, route_index)
		var basis := Basis.looking_at(tangent, Vector3.UP)
		# Intentionally use the base catalog position. Do not raycast to an overlay.
		var bike_transform := Transform3D(basis, route[route_index] + basis.y * 0.72)
		bike.respawn_at(bike_transform)
		bike.linear_velocity = tangent * AUDIT_SPEED_MPS
		race.set("_expected_checkpoint", _expected_checkpoint_at(chain, checkpoint_chains))
		race.call(&"_update_gate_visuals")
		chase_camera.snap_to_target()
		for _frame: int in 5:
			await get_tree().physics_frame
			await get_tree().process_frame
		var image := render_viewport.get_texture().get_image()
		if image == null:
			push_error("BASE-RIBBON VISUAL: rendering unavailable; run without --headless")
			get_tree().quit(1)
			return
		var safe_label := String(request[&"label"]).validate_filename()
		var capture_path := ProjectSettings.globalize_path(
			"res://artifacts/quarry-base-ribbon-%s-chain-%04d-%dx%d.png" % [
				safe_label, roundi(chain), viewport_size.x, viewport_size.y,
			]
		)
		var error := image.save_png(capture_path)
		if error != OK:
			push_error("BASE-RIBBON VISUAL: failed to save %s" % capture_path)
			get_tree().quit(1)
			return
		print("BASE-RIBBON CAPTURE: label=%s chain=%.2f gate=%02d index=%d base=%s capture=%s" % [
			safe_label, chain, _expected_checkpoint_at(chain, checkpoint_chains),
			route_index, str(route[route_index]), capture_path,
		])
	get_tree().quit(0)


func _requested_viewport_size() -> Vector2i:
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--viewport=1920x1080":
			return Vector2i(1920, 1080)
	return Vector2i(2560, 1600)


func _legacy_obstacle_ranges(
	controls: PackedVector3Array,
	route: PackedVector3Array,
	cumulative: PackedFloat32Array
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for spec: Dictionary in LEGACY_POST_GATE8_OBSTACLES:
		var center_index := 0
		if spec.has(&"center_chain"):
			center_index = _index_at_chain(cumulative, float(spec[&"center_chain"]))
		else:
			var target := controls[int(spec[&"point_a"])].lerp(
				controls[int(spec[&"point_b"])], float(spec[&"weight"])
			)
			center_index = CourseSpline.closest_index(route, target)
		var frame_range := _overlay_frame_range(cumulative, center_index, float(spec[&"length"]))
		result.append({
			&"name": spec[&"name"],
			&"start_chain": float(cumulative[frame_range.x]),
			&"center_chain": float(cumulative[center_index]),
			&"end_chain": float(cumulative[frame_range.y]),
		})
	return result


func _live_post_gate8_obstacle_names(
	quarry: Node3D,
	gate8_chain: float,
	cumulative: PackedFloat32Array
) -> Array[StringName]:
	var result: Array[StringName] = []
	for node: Node in quarry.find_children("*", "StaticBody3D", true, false):
		var body := node as StaticBody3D
		if body == null or not body.has_meta(&"ramp_length"):
			continue
		var route_index := int(body.get_meta(&"route_index", -1))
		if route_index >= 0 and route_index < cumulative.size() and float(cumulative[route_index]) >= gate8_chain:
			result.append(body.name)
	return result


func _checkpoint_chains(route_length: float, route: PackedVector3Array) -> PackedFloat32Array:
	var chains := PackedFloat32Array()
	for ratio: float in CourseCatalog.get_checkpoint_progress_ratios(CourseCatalog.QUARRY_ID, route):
		chains.append(ratio * route_length)
	return chains


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


func _overlay_frame_range(
	cumulative: PackedFloat32Array,
	center_index: int,
	requested_length: float
) -> Vector2i:
	var start_index := center_index
	var end_index := center_index
	var center_chain := float(cumulative[center_index])
	var half_length := maxf(requested_length, 2.0) * 0.5
	while start_index > 0 and center_chain - float(cumulative[start_index]) < half_length:
		start_index -= 1
	while end_index < cumulative.size() - 1 and float(cumulative[end_index]) - center_chain < half_length:
		end_index += 1
	return Vector2i(start_index, end_index)


func _expected_checkpoint_at(chain: float, checkpoint_chains: PackedFloat32Array) -> int:
	var expected := 0
	while expected < checkpoint_chains.size() and chain >= float(checkpoint_chains[expected]):
		expected += 1
	return mini(expected + 1, checkpoint_chains.size())


func _add_capture(requests: Array[Dictionary], chain: float, label: String) -> void:
	for request: Dictionary in requests:
		if absf(float(request[&"chain"]) - chain) < 0.35:
			return
	requests.append({&"chain": chain, &"label": label})
