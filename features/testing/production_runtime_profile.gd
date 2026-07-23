extends Node
## Release-style runtime sampler for startup, render, physics, and lifecycle costs.
##
## Run with a visible renderer for GPU/draw-call evidence:
## Godot --path . res://features/testing/production_runtime_profile.tscn -- --activity=CIRCUIT --frames=600

const MAIN_SCENE := preload("res://scenes/main.tscn")

var _activity: StringName = &"CIRCUIT"
var _sample_frames: int = 600


func _ready() -> void:
	_parse_arguments()
	_run.call_deferred()


func _parse_arguments() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--activity="):
			_activity = StringName(argument.trim_prefix("--activity=").to_upper())
		elif argument.begins_with("--frames="):
			_sample_frames = clampi(argument.trim_prefix("--frames=").to_int(), 180, 3600)


func _run() -> void:
	Profile.persistence_enabled = false
	var startup_begin_usec := Time.get_ticks_usec()
	var instantiate_begin_usec := Time.get_ticks_usec()
	var main := MAIN_SCENE.instantiate() as Node3D
	var instantiate_end_usec := Time.get_ticks_usec()
	var attach_begin_usec := Time.get_ticks_usec()
	add_child(main)
	var attach_end_usec := Time.get_ticks_usec()
	for _frame: int in 90:
		await get_tree().process_frame
	var startup_ready_usec := Time.get_ticks_usec()
	var startup_snapshot := _scene_snapshot(main)

	if not RaceEventCatalog.has_event(_activity):
		push_error("PRODUCTION PROFILE: unknown activity %s" % String(_activity))
		get_tree().quit(1)
		return
	var activity_prepare_begin_usec := Time.get_ticks_usec()
	await main.call(&"_on_ride_requested", Profile.current_setup, _activity)
	var activity_prepare_end_usec := Time.get_ticks_usec()
	for _frame: int in 120:
		await get_tree().process_frame
	Input.action_press(InputRouter.THROTTLE, 1.0)

	var sums: Dictionary[StringName, float] = {}
	var maxima: Dictionary[StringName, float] = {}
	var minima: Dictionary[StringName, float] = {}
	var monitor_map := _monitor_map()
	for monitor_name: StringName in monitor_map:
		sums[monitor_name] = 0.0
		maxima[monitor_name] = -INF
		minima[monitor_name] = INF

	for _frame: int in _sample_frames:
		await get_tree().process_frame
		for monitor_name: StringName in monitor_map:
			var value := float(Performance.get_monitor(int(monitor_map[monitor_name])))
			sums[monitor_name] += value
			maxima[monitor_name] = maxf(maxima[monitor_name], value)
			minima[monitor_name] = minf(minima[monitor_name], value)
	Input.action_release(InputRouter.THROTTLE)

	var averages: Dictionary[StringName, float] = {}
	for monitor_name: StringName in monitor_map:
		averages[monitor_name] = sums[monitor_name] / float(_sample_frames)
	var active_snapshot := _scene_snapshot(main)
	var report := {
		&"activity": _activity,
		&"sample_frames": _sample_frames,
		&"startup_seconds": float(startup_ready_usec - startup_begin_usec) / 1_000_000.0,
		&"startup_breakdown_seconds": {
			&"instantiate": float(instantiate_end_usec - instantiate_begin_usec) / 1_000_000.0,
			&"attach_and_ready": float(attach_end_usec - attach_begin_usec) / 1_000_000.0,
			&"settle_90_frames": float(startup_ready_usec - attach_end_usec) / 1_000_000.0,
		},
		&"startup_scene": startup_snapshot,
		&"activity_prepare_seconds": float(activity_prepare_end_usec - activity_prepare_begin_usec) / 1_000_000.0,
		&"active_scene": active_snapshot,
		&"render_breakdown": _render_breakdown(main),
		&"average": averages,
		&"maximum": maxima,
		&"minimum": minima,
	}
	print("PRODUCTION_RUNTIME_PROFILE %s" % JSON.stringify(report))

	var objects_before_cleanup := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	main.queue_free()
	for _frame: int in 8:
		await get_tree().process_frame
	var objects_after_cleanup := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var orphan_count := Node.get_orphan_node_ids().size()
	print(
		"PRODUCTION_RUNTIME_CLEANUP before=%d after=%d delta=%+d orphans=%d"
		% [objects_before_cleanup, objects_after_cleanup, objects_after_cleanup - objects_before_cleanup, orphan_count]
	)
	get_tree().quit(0 if orphan_count == 0 else 1)


func _monitor_map() -> Dictionary[StringName, int]:
	return {
		&"fps": Performance.TIME_FPS,
		&"process_seconds": Performance.TIME_PROCESS,
		&"physics_seconds": Performance.TIME_PHYSICS_PROCESS,
		&"static_memory_bytes": Performance.MEMORY_STATIC,
		&"object_count": Performance.OBJECT_COUNT,
		&"node_count": Performance.OBJECT_NODE_COUNT,
		&"resource_count": Performance.OBJECT_RESOURCE_COUNT,
		&"render_objects": Performance.RENDER_TOTAL_OBJECTS_IN_FRAME,
		&"render_primitives": Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME,
		&"draw_calls": Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME,
		&"video_memory_bytes": Performance.RENDER_VIDEO_MEM_USED,
		&"physics_active_objects": Performance.PHYSICS_3D_ACTIVE_OBJECTS,
		&"physics_collision_pairs": Performance.PHYSICS_3D_COLLISION_PAIRS,
		&"physics_islands": Performance.PHYSICS_3D_ISLAND_COUNT,
	}


func _scene_snapshot(main: Node) -> Dictionary:
	var multimeshes := main.find_children("*", "MultiMeshInstance3D", true, false)
	var rendered_multimesh_instances := 0
	var singleton_multimesh_groups := 0
	var small_multimesh_groups := 0
	for raw_instance: Node in multimeshes:
		var instance := raw_instance as MultiMeshInstance3D
		var instance_count := instance.multimesh.instance_count if instance.multimesh != null else 0
		rendered_multimesh_instances += instance_count
		if instance_count == 1:
			singleton_multimesh_groups += 1
		if instance_count < 4:
			small_multimesh_groups += 1
	return {
		&"nodes": main.find_children("*", "Node", true, false).size() + 1,
		&"mesh_instances": main.find_children("*", "MeshInstance3D", true, false).size(),
		&"multimesh_instances": multimeshes.size(),
		&"multimesh_rendered_instances": rendered_multimesh_instances,
		&"multimesh_singleton_groups": singleton_multimesh_groups,
		&"multimesh_groups_under_four": small_multimesh_groups,
		&"static_bodies": main.find_children("*", "StaticBody3D", true, false).size(),
		&"collision_shapes": main.find_children("*", "CollisionShape3D", true, false).size(),
		&"particle_systems": main.find_children("*", "GPUParticles3D", true, false).size(),
		&"audio_players": (
			main.find_children("*", "AudioStreamPlayer", true, false).size()
			+ main.find_children("*", "AudioStreamPlayer3D", true, false).size()
		),
	}


func _render_breakdown(main: Node) -> Dictionary:
	var branches: Dictionary = {}
	for child: Node in main.get_children():
		var snapshot := _scene_snapshot(child)
		if int(snapshot[&"mesh_instances"]) + int(snapshot[&"multimesh_instances"]) > 0:
			branches[child.name] = snapshot
	var level_root := main.find_child("LevelRoot", true, false)
	if level_root != null and level_root.get_child_count() > 0:
		var level := level_root.get_child(0)
		for child: Node in level.get_children():
			var snapshot := _scene_snapshot(child)
			if int(snapshot[&"mesh_instances"]) + int(snapshot[&"multimesh_instances"]) > 0:
				branches["LEVEL/%s" % child.name] = snapshot
	var meshes := main.find_children("*", "MeshInstance3D", true, false)
	var multimeshes := main.find_children("*", "MultiMeshInstance3D", true, false)
	var unique_meshes: Dictionary = {}
	var unique_materials: Dictionary = {}
	var shadow_casters := 0
	for raw_instance: Node in meshes:
		var instance := raw_instance as MeshInstance3D
		if instance.mesh != null:
			unique_meshes[instance.mesh.get_instance_id()] = true
		if instance.material_override != null:
			unique_materials[instance.material_override.get_instance_id()] = true
		if instance.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			shadow_casters += 1
	for raw_instance: Node in multimeshes:
		var instance := raw_instance as MultiMeshInstance3D
		if instance.multimesh != null and instance.multimesh.mesh != null:
			unique_meshes[instance.multimesh.mesh.get_instance_id()] = true
		if instance.material_override != null:
			unique_materials[instance.material_override.get_instance_id()] = true
		if instance.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			shadow_casters += 1
	branches[&"TOTALS"] = {
		&"unique_mesh_resources": unique_meshes.size(),
		&"unique_override_materials": unique_materials.size(),
		&"shadow_casting_instances": shadow_casters,
	}
	return branches
