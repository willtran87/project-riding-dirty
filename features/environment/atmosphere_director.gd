extends Node3D
class_name AtmosphereDirector
## Smooth district grading and lightweight bike-centered weather for the compatibility renderer.

var _bike: Node3D
var _environment: Environment
var _sun: DirectionalLight3D
var _weather: GPUParticles3D
var _sky_material: ProceduralSkyMaterial
var _district_id: StringName = CourseCatalog.QUARRY_ID
var _target_ambient := Color("516d7b")
var _target_ambient_energy: float = 0.38
var _target_fog := Color("c29b80")
var _target_fog_light_energy: float = 0.22
var _target_fog_density: float = 0.00095
var _target_fog_sky_affect: float = 0.18
var _target_sun := Color("ffc57f")
var _target_sun_energy: float = 1.5
var _target_sun_rotation := Vector3(-43.0, -48.0, 0.0)
var _target_sky_top := Color("0c3d66")
var _target_sky_horizon := Color("d5a073")
var _target_ground_bottom := Color("30231e")
var _target_ground_horizon := Color("905237")
var _target_sky_energy: float = 1.08


func _ready() -> void:
	EventBus.activity_prepared.connect(_on_activity_prepared)
	EventBus.activity_started.connect(_on_activity_started)
	_build_weather()


func initialize(bike: Node3D) -> void:
	_bike = bike
	bind_environment(get_tree().current_scene)


func bind_environment(scene_root: Node) -> void:
	_environment = null
	_sun = null
	_sky_material = null
	if scene_root == null:
		return
	var world_environment := scene_root.find_child("*", true, false) as WorldEnvironment
	if world_environment == null:
		var environments := scene_root.find_children("*", "WorldEnvironment", true, false)
		if not environments.is_empty():
			world_environment = environments[0] as WorldEnvironment
	if world_environment != null:
		_environment = world_environment.environment
		if _environment != null:
			_target_ambient = _environment.ambient_light_color
			_target_ambient_energy = _environment.ambient_light_energy
			_target_fog = _environment.fog_light_color
			_target_fog_light_energy = _environment.fog_light_energy
			_target_fog_density = _environment.fog_density
			_target_fog_sky_affect = _environment.fog_sky_affect
			if _environment.sky != null:
				_sky_material = _environment.sky.sky_material as ProceduralSkyMaterial
				if _sky_material != null:
					_target_sky_top = _sky_material.sky_top_color
					_target_sky_horizon = _sky_material.sky_horizon_color
					_target_ground_bottom = _sky_material.ground_bottom_color
					_target_ground_horizon = _sky_material.ground_horizon_color
					_target_sky_energy = _sky_material.sky_energy_multiplier
	var lights := scene_root.find_children("*", "DirectionalLight3D", true, false)
	for light_node: Node in lights:
		var light := light_node as DirectionalLight3D
		if light != null and light.shadow_enabled:
			_sun = light
			break
	if _sun == null and not lights.is_empty():
		_sun = lights[0] as DirectionalLight3D
	if _sun != null:
		_target_sun = _sun.light_color
		_target_sun_energy = _sun.light_energy
		_target_sun_rotation = _sun.rotation_degrees


func configure_session(weather: StringName, track_id: StringName = &"QUARRY") -> void:
	## RaceSessionConfig is authoritative for presentation as well as grip. This
	## keeps special events and rotating challenges visually consistent with the
	## conditions shown in the HUD. Weather modifies a district profile instead
	## of replacing it, so Quarry stays copper-blue, Pine stays cool evergreen,
	## and Mesa stays high-contrast red desert in every condition.
	_apply_weather_profile(weather, track_id)


func _apply_weather_profile(weather: StringName, track_id: StringName) -> void:
	_district_id = track_id if track_id in [CourseCatalog.QUARRY_ID, CourseCatalog.PINE_ID, CourseCatalog.MESA_MX_ID] else CourseCatalog.QUARRY_ID
	var profile := _district_profile(_district_id)
	var base_ambient: Color = profile[&"ambient"]
	var base_ambient_energy: float = profile[&"ambient_energy"]
	var base_fog: Color = profile[&"fog"]
	var base_fog_energy: float = profile[&"fog_energy"]
	var base_fog_density: float = profile[&"fog_density"]
	var base_fog_sky_affect: float = profile[&"fog_sky_affect"]
	var base_sun: Color = profile[&"sun"]
	var base_sun_energy: float = profile[&"sun_energy"]
	var base_sun_rotation: Vector3 = profile[&"sun_rotation"]
	var base_sky_top: Color = profile[&"sky_top"]
	var base_sky_horizon: Color = profile[&"sky_horizon"]
	var base_ground_bottom: Color = profile[&"ground_bottom"]
	var base_ground_horizon: Color = profile[&"ground_horizon"]
	var base_sky_energy: float = profile[&"sky_energy"]

	_target_ambient = base_ambient
	_target_ambient_energy = base_ambient_energy
	_target_fog = base_fog
	_target_fog_light_energy = base_fog_energy
	_target_fog_density = base_fog_density
	_target_fog_sky_affect = base_fog_sky_affect
	_target_sun = base_sun
	_target_sun_energy = base_sun_energy
	_target_sun_rotation = base_sun_rotation
	_target_sky_top = base_sky_top
	_target_sky_horizon = base_sky_horizon
	_target_ground_bottom = base_ground_bottom
	_target_ground_horizon = base_ground_horizon
	_target_sky_energy = base_sky_energy
	var particle_color := Color(base_sun.r, base_sun.g, base_sun.b, 0.11)
	var rain_like := false

	match weather:
		&"STORM", &"WET":
			_target_ambient = base_ambient.lerp(Color("405665"), 0.5).darkened(0.1)
			_target_ambient_energy = base_ambient_energy * 0.7
			_target_fog = base_fog.lerp(Color("637988"), 0.52)
			_target_fog_light_energy = base_fog_energy * 0.78
			_target_fog_density = maxf(base_fog_density * 3.2, 0.0034)
			_target_fog_sky_affect = minf(base_fog_sky_affect + 0.3, 0.66)
			_target_sun = base_sun.lerp(Color("a8bfcb"), 0.58)
			_target_sun_energy = base_sun_energy * 0.42
			_target_sun_rotation = base_sun_rotation.lerp(Vector3(-24.0, 18.0, 0.0), 0.35)
			_target_sky_top = base_sky_top.lerp(Color("263b50"), 0.48).darkened(0.14)
			_target_sky_horizon = base_sky_horizon.lerp(_target_fog, 0.68)
			_target_ground_horizon = base_ground_horizon.lerp(_target_fog, 0.36)
			_target_sky_energy = base_sky_energy * 0.68
			particle_color = Color(_target_fog.r, _target_fog.g, _target_fog.b, 0.36)
			rain_like = true
		&"MIST", &"OVERCAST":
			_target_ambient = base_ambient.lerp(base_fog, 0.2)
			_target_ambient_energy = base_ambient_energy * 0.84
			_target_fog = base_fog.lightened(0.05)
			_target_fog_light_energy = base_fog_energy * 0.92
			_target_fog_density = maxf(base_fog_density * 1.75, 0.0023)
			_target_fog_sky_affect = minf(base_fog_sky_affect + 0.2, 0.57)
			_target_sun = base_sun.lerp(Color("dcebcf"), 0.38)
			_target_sun_energy = base_sun_energy * 0.7
			_target_sky_top = base_sky_top.lerp(base_fog.darkened(0.34), 0.32)
			_target_sky_horizon = base_sky_horizon.lerp(_target_fog, 0.44)
			_target_sky_energy = base_sky_energy * 0.82
			particle_color = Color(_target_fog.r, _target_fog.g, _target_fog.b, 0.18)
			rain_like = true
		&"NIGHT":
			_target_ambient = base_ambient.lerp(Color("273b58"), 0.64).darkened(0.16)
			_target_ambient_energy = base_ambient_energy * 0.56
			_target_fog = base_fog.lerp(Color("374f69"), 0.68).darkened(0.12)
			_target_fog_light_energy = base_fog_energy * 0.5
			_target_fog_density = maxf(base_fog_density * 1.75, 0.0018)
			_target_fog_sky_affect = minf(base_fog_sky_affect + 0.12, 0.5)
			_target_sun = base_sun.lerp(Color("8db9ef"), 0.72)
			_target_sun_energy = base_sun_energy * 0.22
			_target_sun_rotation = Vector3(-10.0, base_sun_rotation.y, 0.0)
			_target_sky_top = base_sky_top.darkened(0.64)
			_target_sky_horizon = base_sky_horizon.lerp(Color("263d5e"), 0.78).darkened(0.34)
			_target_ground_bottom = base_ground_bottom.darkened(0.62)
			_target_ground_horizon = base_ground_horizon.lerp(Color("1e3048"), 0.68).darkened(0.38)
			_target_sky_energy = base_sky_energy * 0.4
			particle_color = Color(0.45, 0.7, 1.0, 0.13)
		&"DUSK", &"SUNSET":
			_target_ambient = base_ambient.lerp(Color("8b5260"), 0.4)
			_target_ambient_energy = base_ambient_energy * 0.88
			_target_fog = base_fog.lerp(Color("c76d4f"), 0.4)
			_target_fog_light_energy = base_fog_energy * 0.82
			_target_fog_density = base_fog_density * 1.18
			_target_sun = base_sun.lerp(Color("ff914e"), 0.62)
			_target_sun_energy = base_sun_energy * 1.04
			_target_sun_rotation = base_sun_rotation.lerp(Vector3(-21.0, -58.0, 0.0), 0.58)
			_target_sky_top = base_sky_top.darkened(0.22)
			_target_sky_horizon = base_sky_horizon.lerp(Color("f07846"), 0.48)
			_target_ground_horizon = base_ground_horizon.lerp(Color("a74331"), 0.35)
			_target_sky_energy = base_sky_energy * 0.94
			particle_color = Color(1.0, 0.55, 0.24, 0.16)
		&"VARIABLE", &"WINDY":
			_target_ambient = base_ambient.lerp(Color("687681"), 0.22)
			_target_ambient_energy = base_ambient_energy * 0.92
			_target_fog = base_fog.lerp(Color("788b96"), 0.24)
			_target_fog_density = base_fog_density * 1.28
			_target_fog_sky_affect = minf(base_fog_sky_affect + 0.08, 0.48)
			_target_sun = base_sun.lerp(Color("d7d7c4"), 0.25)
			_target_sun_energy = base_sun_energy * 0.84
			_target_sun_rotation = base_sun_rotation.lerp(Vector3(-34.0, 8.0, 0.0), 0.18)
			_target_sky_top = base_sky_top.lerp(Color("435b68"), 0.16)
			_target_sky_horizon = base_sky_horizon.lerp(base_fog, 0.16)
			particle_color = Color(_target_fog.r, _target_fog.g, _target_fog.b, 0.16)
		_:
			pass
	_configure_weather(particle_color, rain_like)


func _district_profile(track_id: StringName) -> Dictionary:
	if track_id == CourseCatalog.PINE_ID:
		return {
			&"ambient": Color("4c665a"), &"ambient_energy": 0.4,
			&"fog": Color("86a594"), &"fog_energy": 0.26,
			&"fog_density": 0.0023, &"fog_sky_affect": 0.34,
			&"sun": Color("f0e6bf"), &"sun_energy": 1.1,
			&"sun_rotation": Vector3(-32.0, 28.0, 0.0),
			&"sky_top": Color("163d56"), &"sky_horizon": Color("a4b9a7"),
			&"ground_bottom": Color("17251f"), &"ground_horizon": Color("4b654d"),
			&"sky_energy": 0.96,
		}
	if track_id == CourseCatalog.MESA_MX_ID:
		return {
			&"ambient": Color("76545a"), &"ambient_energy": 0.29,
			&"fog": Color("c9734e"), &"fog_energy": 0.18,
			&"fog_density": 0.00062, &"fog_sky_affect": 0.12,
			&"sun": Color("ffc477"), &"sun_energy": 1.58,
			&"sun_rotation": Vector3(-29.0, -62.0, 0.0),
			&"sky_top": Color("102f5b"), &"sky_horizon": Color("ed8750"),
			&"ground_bottom": Color("321918"), &"ground_horizon": Color("9f3e28"),
			&"sky_energy": 1.12,
		}
	return {
		&"ambient": Color("516d7b"), &"ambient_energy": 0.38,
		&"fog": Color("c29b80"), &"fog_energy": 0.22,
		&"fog_density": 0.00095, &"fog_sky_affect": 0.18,
		&"sun": Color("ffc57f"), &"sun_energy": 1.5,
		&"sun_rotation": Vector3(-43.0, -48.0, 0.0),
		&"sky_top": Color("0c3d66"), &"sky_horizon": Color("d5a073"),
		&"ground_bottom": Color("30231e"), &"ground_horizon": Color("905237"),
		&"sky_energy": 1.08,
	}


func _process(delta: float) -> void:
	if _bike != null:
		global_position = _bike.global_position + Vector3.UP * 6.0
	if _environment != null:
		var weight := 1.0 - exp(-1.5 * delta)
		_environment.ambient_light_color = _environment.ambient_light_color.lerp(_target_ambient, weight)
		_environment.ambient_light_energy = lerpf(_environment.ambient_light_energy, _target_ambient_energy, weight)
		_environment.fog_light_color = _environment.fog_light_color.lerp(_target_fog, weight)
		_environment.fog_light_energy = lerpf(_environment.fog_light_energy, _target_fog_light_energy, weight)
		_environment.fog_density = lerpf(_environment.fog_density, _target_fog_density, weight)
		_environment.fog_sky_affect = lerpf(_environment.fog_sky_affect, _target_fog_sky_affect, weight)
	if _sky_material != null:
		var sky_weight := 1.0 - exp(-1.0 * delta)
		_sky_material.sky_top_color = _sky_material.sky_top_color.lerp(_target_sky_top, sky_weight)
		_sky_material.sky_horizon_color = _sky_material.sky_horizon_color.lerp(_target_sky_horizon, sky_weight)
		_sky_material.ground_bottom_color = _sky_material.ground_bottom_color.lerp(_target_ground_bottom, sky_weight)
		_sky_material.ground_horizon_color = _sky_material.ground_horizon_color.lerp(_target_ground_horizon, sky_weight)
		_sky_material.sky_energy_multiplier = lerpf(_sky_material.sky_energy_multiplier, _target_sky_energy, sky_weight)
	if _sun != null:
		var light_weight := 1.0 - exp(-1.2 * delta)
		_sun.light_color = _sun.light_color.lerp(_target_sun, light_weight)
		_sun.light_energy = lerpf(_sun.light_energy, _target_sun_energy, light_weight)
		_sun.rotation_degrees = _sun.rotation_degrees.lerp(_target_sun_rotation, light_weight)


func _on_activity_prepared(activity: StringName) -> void:
	# RaceSessionConfig is applied immediately after this signal and remains the
	# authority through countdown and green. Only free-roam activities use their
	# own authored presentation preset here.
	if RaceEventCatalog.is_race_event(activity):
		return
	_configure_free_roam_activity(activity)


func _on_activity_started(activity: StringName) -> void:
	if RaceEventCatalog.is_race_event(activity):
		return
	_configure_free_roam_activity(activity)


func _configure_free_roam_activity(activity: StringName) -> void:
	match activity:
		&"FREESTYLE":
			_apply_weather_profile(&"SUNSET", CourseCatalog.MESA_MX_ID)
		&"DISCOVERY":
			_apply_weather_profile(&"OVERCAST", CourseCatalog.QUARRY_ID)
			_target_ambient = _target_ambient.lerp(Color("53697c"), 0.45)
			_target_sun = Color("adc9e8")
			_target_sun_rotation = Vector3(-15.0, -18.0, 0.0)
		&"PINE_ENDURO":
			_apply_weather_profile(&"MIST", CourseCatalog.PINE_ID)
		_:
			_apply_weather_profile(&"CLEAR", CourseCatalog.QUARRY_ID)


func _build_weather() -> void:
	_weather = GPUParticles3D.new()
	_weather.name = "DistrictWeather"
	_weather.amount = 92
	_weather.lifetime = 2.8
	_weather.local_coords = true
	_weather.preprocess = 1.2
	_weather.visibility_aabb = AABB(Vector3(-24.0, -12.0, -24.0), Vector3(48.0, 30.0, 48.0))
	var process_material := ParticleProcessMaterial.new()
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process_material.emission_box_extents = Vector3(18.0, 8.0, 18.0)
	process_material.direction = Vector3(0.2, -1.0, 0.15)
	process_material.spread = 18.0
	process_material.initial_velocity_min = 0.35
	process_material.initial_velocity_max = 1.4
	process_material.gravity = Vector3(0.0, -0.35, 0.0)
	process_material.scale_min = 0.05
	process_material.scale_max = 0.15
	_weather.process_material = process_material
	var mote := BoxMesh.new()
	mote.size = Vector3(0.025, 0.18, 0.025)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 0.72, 0.36, 0.14)
	mote.material = material
	_weather.draw_pass_1 = mote
	_weather.emitting = false
	add_child(_weather)


func _configure_weather(color: Color, rain_like: bool) -> void:
	if _weather == null:
		return
	var process_material := _weather.process_material as ParticleProcessMaterial
	process_material.color = color
	process_material.direction = Vector3(0.18, -1.0, 0.12) if rain_like else Vector3(0.1, -0.2, 0.1)
	process_material.initial_velocity_min = 4.0 if rain_like else 0.25
	process_material.initial_velocity_max = 8.0 if rain_like else 1.1
	_weather.amount = 140 if rain_like else 82
	_weather.restart()
