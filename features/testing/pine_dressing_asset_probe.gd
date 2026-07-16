extends Node
## Release contract for Pine's content-addressed procedural dressing bake.
## Proves the asset matches the current route/config schema and retains the
## complete visual-density and containment-collision contracts.

const PineDressingScene := preload("res://assets/generated/pine_course_dressing.scn")
const ASSET_PATH := "res://assets/generated/pine_course_dressing.scn"
const MAX_INSTANTIATE_USEC := 250_000


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var begin_usec := Time.get_ticks_usec()
	var dressing := PineDressingScene.instantiate() as Node3D
	add_child(dressing)
	var instantiate_usec := Time.get_ticks_usec() - begin_usec
	var route := CourseCatalog.get_local_riding_points(CourseCatalog.PINE_ID)
	var expected_signature := CourseDressingBuilder.build_signature(
		CourseCatalog.PINE_ID,
		route,
		CourseCatalog.get_track_width(CourseCatalog.PINE_ID)
	)
	var signature := int(dressing.get_meta(&"dressing_build_signature", -1))
	var containment := dressing.find_child("CourseContainment", true, false) as StaticBody3D
	var opening_posts := dressing.find_child(
		"CourseContainmentOpeningPosts", true, false
	) as StaticBody3D
	var multimesh_count := 0
	var visual_instance_count := 0
	for candidate: Node in dressing.find_children("*", "MultiMeshInstance3D", true, false):
		var instance := candidate as MultiMeshInstance3D
		if instance.multimesh == null:
			continue
		multimesh_count += 1
		visual_instance_count += instance.multimesh.instance_count
	var natural_count := int(dressing.get_meta(
		&"natural_ground_cover_instance_count", -1
	))
	var expected_natural_count := (
		int(CourseDressingCatalog.get_config(CourseCatalog.PINE_ID)[&"near_natural_count"])
		+ int(CourseDressingCatalog.get_config(CourseCatalog.PINE_ID)[&"backdrop_natural_count"])
	)
	var segment_count := int(containment.get_meta(&"segment_count", 0)) if containment else 0
	var collision_shape_count := (
		int(containment.get_meta(&"collision_shape_count", 0)) if containment else 0
	)
	var opening_post_count := (
		int(opening_posts.get_meta(&"post_count", 0)) if opening_posts else 0
	)
	var asset_size := FileAccess.get_file_as_bytes(ASSET_PATH).size()
	var passed := (
		dressing.name == "CourseDressing"
		and signature == expected_signature
		and int(dressing.get_meta(&"dressing_bake_schema", -1))
			== CourseDressingBuilder.BAKE_SCHEMA_VERSION
		and containment != null
		and containment.is_in_group(&"course_containment")
		and segment_count >= 700
		and collision_shape_count == 1
		and opening_post_count >= 8
		and natural_count == expected_natural_count
		and multimesh_count >= 35
		and visual_instance_count >= 3000
		and asset_size > 0
		and instantiate_usec <= MAX_INSTANTIATE_USEC
	)
	print((
		"PINE DRESSING ASSET: signature=%d size_bytes=%d instantiate=%.3fms "
		+ "multimeshes=%d visual_instances=%d natural=%d segments=%d opening_posts=%d passed=%s"
		) % [
			signature,
			asset_size,
			float(instantiate_usec) / 1000.0,
			multimesh_count,
			visual_instance_count,
			natural_count,
			segment_count,
			opening_post_count,
			str(passed),
		]
	)
	if not passed:
		push_error("PINE DRESSING ASSET: stale, incomplete, or too slow")
	dressing.queue_free()
	get_tree().quit(0 if passed else 1)
