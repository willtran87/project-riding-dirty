extends Node
## Focused contract for WebGL rendering budgets and baked startup audio.

const BIKE_VISUAL := preload("res://entities/bike/bike_visual.gd")
const MUSIC_BASE: AudioStreamWAV = preload("res://assets/generated/audio/music_quarry_standard_base.wav")
const ENGINE_LOOP: AudioStreamWAV = preload("res://assets/generated/audio/engine_engine.res")

var _failed := false


func _ready() -> void:
	var root := Node3D.new()
	add_child(root)
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 460.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	root.add_child(sun)
	var particles := GPUParticles3D.new()
	particles.amount = 100
	root.add_child(particles)
	var weather_particles := GPUParticles3D.new()
	weather_particles.amount = 100
	weather_particles.add_to_group(&"weather_effects")
	root.add_child(weather_particles)

	var balanced := RaceServices.resolve_visual_quality_preset("BALANCED", true)
	RaceServices.apply_visual_quality_to_scene(root, balanced)
	_check(sun.shadow_enabled, "Balanced unexpectedly disabled the authored sun")
	_check(is_equal_approx(sun.directional_shadow_max_distance, 150.0), "Balanced shadow distance is not 150 m")
	_check(sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS, "Balanced does not use two shadow splits")
	_check(is_equal_approx(particles.amount_ratio, 0.62), "Balanced particle ratio is incorrect")
	_check(is_equal_approx(weather_particles.amount_ratio, 0.62), "Balanced weather ratio is incorrect")

	var performance := RaceServices.resolve_visual_quality_preset("PERFORMANCE", true)
	RaceServices.apply_visual_quality_to_scene(root, performance)
	_check(not sun.shadow_enabled, "Performance did not disable directional shadows")
	_check(is_equal_approx(particles.amount_ratio, 0.35), "Performance particle ratio is incorrect")

	var quality := RaceServices.resolve_visual_quality_preset("QUALITY", true)
	RaceServices.apply_visual_quality_to_scene(root, quality)
	_check(sun.shadow_enabled, "Quality did not restore the authored sun")
	_check(is_equal_approx(sun.directional_shadow_max_distance, 220.0), "Quality shadow distance is not capped")
	_check(is_equal_approx(particles.amount_ratio, 0.84), "Quality particle ratio is incorrect")

	var native := RaceServices.resolve_visual_quality_preset("QUALITY", false)
	RaceServices.apply_visual_quality_to_scene(root, native)
	_check(sun.shadow_enabled, "Native quality did not restore shadow enablement")
	_check(is_equal_approx(sun.directional_shadow_max_distance, 460.0), "Native quality did not restore authored distance")
	_check(sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS, "Native quality did not restore authored splits")
	_check(is_equal_approx(particles.amount_ratio, 1.0), "Native quality did not restore full particles")

	var accessible_quality := RaceServices.resolve_visual_quality_preset("QUALITY", true, true)
	RaceServices.apply_visual_quality_to_scene(root, accessible_quality)
	_check(
		is_equal_approx(
			float(accessible_quality.get(&"base_particle_ratio", 0.0)),
			0.84
		),
		"Reduced-particle accessibility lost the selected quality baseline"
	)
	_check(
		is_equal_approx(particles.amount_ratio, RaceServices.REDUCED_PARTICLE_RATIO),
		"Reduced-particle accessibility did not cap live effect density"
	)
	_check(
		bool(accessible_quality.get(&"reduced_particles", false)),
		"Reduced-particle accessibility is absent from the applied quality contract"
	)

	var custom := RaceServices.resolve_visual_quality_preset(
		"BALANCED",
		true,
		false,
		{
			"render_scale": "100%",
			"shadow_quality": "SHORT",
			"particle_density": "FULL",
			"weather_effects": "MINIMAL",
		}
	)
	RaceServices.apply_visual_quality_to_scene(root, custom)
	_check(is_equal_approx(float(custom.get(&"render_scale", 0.0)), 1.0), "100% render-resolution override was ignored")
	_check(StringName(custom.get(&"render_scale_mode", &"")) == &"100%", "Render-resolution override is absent from the snapshot")
	_check(sun.shadow_enabled, "Short shadows unexpectedly disabled the authored sun")
	_check(is_equal_approx(sun.directional_shadow_max_distance, RaceServices.SHORT_SHADOW_DISTANCE), "Short shadows did not cap distance")
	_check(is_equal_approx(particles.amount_ratio, 1.0), "Full effect density did not override the preset")
	_check(is_equal_approx(weather_particles.amount_ratio, 0.10), "Minimal weather did not independently reduce weather particles")

	var accessible_custom := RaceServices.resolve_visual_quality_preset(
		"QUALITY",
		true,
		true,
		{
			"particle_density": "FULL",
			"weather_effects": "FULL",
			"shadow_quality": "OFF",
		}
	)
	RaceServices.apply_visual_quality_to_scene(root, accessible_custom)
	_check(not sun.shadow_enabled, "Off shadow override did not disable the authored sun")
	_check(is_equal_approx(particles.amount_ratio, RaceServices.REDUCED_PARTICLE_RATIO), "Accessibility did not cap a full-density override")
	_check(is_equal_approx(weather_particles.amount_ratio, RaceServices.REDUCED_PARTICLE_RATIO), "Accessibility did not cap full weather effects")

	var restored_full := RaceServices.resolve_visual_quality_preset(
		"QUALITY",
		false,
		false,
		{"shadow_quality": "FULL"}
	)
	RaceServices.apply_visual_quality_to_scene(root, restored_full)
	_check(sun.shadow_enabled, "Full shadows did not restore the authored sun")
	_check(is_equal_approx(sun.directional_shadow_max_distance, 460.0), "Native full shadows did not restore authored distance")
	_check(sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS, "Native full shadows did not restore authored splits")

	_check(ENGINE_LOOP != null and ENGINE_LOOP.loop_mode == AudioStreamWAV.LOOP_FORWARD, "Baked engine loop is invalid")
	_check(MUSIC_BASE != null and MUSIC_BASE.get_length() > 6.0, "Baked Quarry music is invalid")

	var pack_visual := Node3D.new()
	pack_visual.set_script(BIKE_VISUAL)
	pack_visual.set(&"pack_variant", true)
	root.add_child(pack_visual)
	var proxy := pack_visual.find_child("PackShadowProxy", true, false) as MeshInstance3D
	_check(proxy != null, "Opponent shadow proxy was not created")
	if proxy != null:
		_check(proxy.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY, "Opponent proxy is not shadows-only")
	for raw_geometry: Node in pack_visual.find_children("*", "GeometryInstance3D", true, false):
		var geometry := raw_geometry as GeometryInstance3D
		if geometry != proxy:
			_check(geometry.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "Detailed opponent geometry still casts shadows")

	print("WEB RUNTIME BUDGET PROBE %s" % ("FAIL" if _failed else "PASS"))
	get_tree().quit(1 if _failed else 0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("WEB RUNTIME BUDGET: %s" % message)
