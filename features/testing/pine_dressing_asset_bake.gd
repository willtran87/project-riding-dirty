extends Node
## Development-only deterministic bake for Pine Ridge's complete course-dressing
## subtree. Runtime validates the embedded route/config signature before using it.

const PineScene := preload("res://levels/pine_ridge/pine_ridge.tscn")
const OUTPUT_PATH := "res://assets/generated/pine_course_dressing.scn"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var begin_usec := Time.get_ticks_usec()
	# A bake must execute the source builder even when a valid previous bake is
	# present; otherwise an intentional visual algorithm update could just repack
	# the old scene. The runtime path never sets this development-only override.
	OS.set_environment("RIDING_DIRTY_FORCE_LIVE_DRESSING", "1")
	var level := PineScene.instantiate() as Node3D
	add_child(level)
	OS.set_environment("RIDING_DIRTY_FORCE_LIVE_DRESSING", "")
	var dressing := level.find_child("CourseDressing", true, false) as Node3D
	if dressing == null:
		push_error("PINE DRESSING BAKE: generated dressing root is missing")
		get_tree().quit(1)
		return
	level.remove_child(dressing)
	_make_packable(dressing, dressing)
	var packed := PackedScene.new()
	var pack_error := packed.pack(dressing)
	if pack_error != OK:
		push_error("PINE DRESSING BAKE: pack failed (%d)" % pack_error)
		dressing.free()
		level.queue_free()
		get_tree().quit(1)
		return
	# Keep the generated artifact byte-stable across routine release builds. A
	# matching signature means the existing asset was produced from this exact
	# route/catalog/schema contract, so rewriting it would only churn opaque
	# PackedScene resource IDs. Intentional output changes require a schema bump.
	var unchanged := _existing_signature() == int(dressing.get_meta(
		&"dressing_build_signature", -1
	))
	var save_error := OK
	if not unchanged:
		save_error = ResourceSaver.save(packed, OUTPUT_PATH)
	var elapsed_usec := Time.get_ticks_usec() - begin_usec
	var passed := save_error == OK
	print("PINE DRESSING BAKE: signature=%d elapsed=%.3fs output=%s unchanged=%s passed=%s" % [
		int(dressing.get_meta(&"dressing_build_signature", -1)),
		float(elapsed_usec) / 1_000_000.0,
		OUTPUT_PATH,
		str(unchanged),
		str(passed),
	])
	dressing.free()
	level.queue_free()
	if not passed:
		push_error("PINE DRESSING BAKE: save failed (%d)" % save_error)
	get_tree().quit(0 if passed else 1)


func _existing_signature() -> int:
	if not ResourceLoader.exists(OUTPUT_PATH):
		return -1
	var existing_scene := ResourceLoader.load(OUTPUT_PATH, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if existing_scene == null:
		return -1
	var existing := existing_scene.instantiate()
	var signature := int(existing.get_meta(&"dressing_build_signature", -1))
	existing.free()
	return signature


func _make_packable(node: Node, scene_owner: Node) -> void:
	for group: StringName in node.get_groups():
		node.remove_from_group(group)
		node.add_to_group(group, true)
	for child: Node in node.get_children():
		child.owner = scene_owner
		_make_packable(child, scene_owner)
