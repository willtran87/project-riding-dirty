extends Node3D
class_name AtmosphereDirector
## Smooth district grading and lightweight bike-centered weather for the compatibility renderer.

var _bike: Node3D
var _environment: Environment
var _sun: DirectionalLight3D
var _weather: GPUParticles3D
var _target_ambient := Color("8092a2")
var _target_fog := Color("879ba5")
var _target_sun := Color("ffd09b")
var _target_fog_density: float = 0.0028
var _target_sun_energy: float = 1.28
var _target_sun_rotation := Vector3(-52.0, -34.0, 0.0)


func _ready() -> void:
	EventBus.activity_started.connect(_on_activity_started)
	_build_weather()


func initialize(bike: Node3D) -> void:
	_bike = bike
	var world_environment := get_tree().current_scene.find_child("WorldEnvironment", true, false) as WorldEnvironment
	if world_environment != null:
		_environment = world_environment.environment
	_sun = get_tree().current_scene.find_child("Sun", true, false) as DirectionalLight3D


func _process(delta: float) -> void:
	if _bike != null:
		global_position = _bike.global_position + Vector3.UP * 6.0
	if _environment != null:
		var weight := 1.0 - exp(-1.5 * delta)
		_environment.ambient_light_color = _environment.ambient_light_color.lerp(_target_ambient, weight)
		_environment.fog_light_color = _environment.fog_light_color.lerp(_target_fog, weight)
		_environment.fog_density = lerpf(_environment.fog_density, _target_fog_density, weight)
	if _sun != null:
		var light_weight := 1.0 - exp(-1.2 * delta)
		_sun.light_color = _sun.light_color.lerp(_target_sun, light_weight)
		_sun.light_energy = lerpf(_sun.light_energy, _target_sun_energy, light_weight)
		_sun.rotation_degrees = _sun.rotation_degrees.lerp(_target_sun_rotation, light_weight)


func _on_activity_started(activity: StringName) -> void:
	match activity:
		&"FREESTYLE":
			_target_ambient = Color("9a6e69")
			_target_fog = Color("c07b63")
			_target_sun = Color("ff9b62")
			_target_fog_density = 0.0042
			_target_sun_energy = 1.48
			_target_sun_rotation = Vector3(-28.0, -48.0, 0.0)
			_configure_weather(Color(1.0, 0.62, 0.28, 0.18), false)
		&"DISCOVERY":
			_target_ambient = Color("53697c")
			_target_fog = Color("657d8d")
			_target_sun = Color("adc9e8")
			_target_fog_density = 0.0062
			_target_sun_energy = 0.82
			_target_sun_rotation = Vector3(-15.0, -18.0, 0.0)
			_configure_weather(Color(0.5, 0.76, 1.0, 0.22), true)
		&"PINE_ENDURO":
			_target_ambient = Color("60766b")
			_target_fog = Color("8ba397")
			_target_sun = Color("d5e6c7")
			_target_fog_density = 0.009
			_target_sun_energy = 0.76
			_target_sun_rotation = Vector3(-38.0, 22.0, 0.0)
			_configure_weather(Color(0.68, 0.85, 0.76, 0.20), true)
		_:
			_target_ambient = Color("8092a2")
			_target_fog = Color("879ba5")
			_target_sun = Color("ffd09b")
			_target_fog_density = 0.0028
			_target_sun_energy = 1.28
			_target_sun_rotation = Vector3(-52.0, -34.0, 0.0)
			_configure_weather(Color(1.0, 0.72, 0.36, 0.14), false)


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
	var process_material := _weather.process_material as ParticleProcessMaterial
	process_material.color = color
	process_material.direction = Vector3(0.18, -1.0, 0.12) if rain_like else Vector3(0.1, -0.2, 0.1)
	process_material.initial_velocity_min = 4.0 if rain_like else 0.25
	process_material.initial_velocity_max = 8.0 if rain_like else 1.1
	_weather.amount = 140 if rain_like else 82
	_weather.restart()
