extends Node3D
## Builds and animates a detailed, Web-friendly stylized dirt bike and rider.

const RIDER_TORSO_RESPONSE_HZ: float = 10.5
const RIDER_WOBBLE_ANGULAR_SPEED: float = 25.0
const RIDER_EQUIPMENT_WEAR := preload("res://features/race/rider_equipment_wear.gd")
const RIDER_GRAPHICS_CATALOG := preload("res://features/career/rider_graphics_catalog.gd")
const WEARABLE_MATERIAL_KEYS: Array[StringName] = [
	&"red", &"cream", &"jersey", &"denim", &"helmet", &"goggles",
	&"boots", &"gloves", &"protection", &"accessory", &"skin",
	&"decal_primary", &"decal_secondary",
]

@export var pack_variant: bool = false
@export var pack_bike_color: Color = Color("d93a2f")
@export var pack_helmet_color: Color = Color("f2b632")

static var _shared_pack_meshes: Dictionary = {}
static var _shared_pack_neutral_materials: Dictionary = {}
static var _shared_pack_shadow_mesh: ArrayMesh

var _front_wheel_pivot: Node3D
var _rear_wheel_pivot: Node3D
var _front_assembly: Node3D
var _front_lower_fork_root: Node3D
var _rear_linkage_root: Node3D
var _rear_shock_root: Node3D
var _rider_root: Node3D
var _left_grip_anchor: Node3D
var _right_grip_anchor: Node3D
var _left_foot_anchor: Node3D
var _right_foot_anchor: Node3D
var _arm_multimesh: MultiMesh
var _glove_multimesh: MultiMesh
var _leg_multimesh: MultiMesh
var _boot_multimesh: MultiMesh
var _rider_goggles_mesh: MeshInstance3D
var _rider_protection_mesh: MeshInstance3D
var _rider_accessory_mesh: MeshInstance3D
var _dust: GPUParticles3D
var _roost: GPUParticles3D
var _clods: GPUParticles3D
var _landing_dust: GPUParticles3D
var _boost_trail: GPUParticles3D
var _boost_burst: GPUParticles3D
var _rider_torso_root: Node3D
var _skid_marks: Array[MeshInstance3D] = []
var _skid_index: int = 0
var _skid_time: float = 0.0
var _was_boosting: bool = false
var _ride_phase: float = 0.0
var _wobble_phase: float = 0.0
var _current_surface: StringName = &"PACKED"
var _surface_tint: Color = Color(0.44, 0.27, 0.14, 1.0)
var _soft_particle_texture: Texture2D
var _number_labels: Array[Label3D] = []
var _active_trick_pose: StringName = &"NONE"
var _trick_pose_blend: float = 0.0
var _trick_pose_strength: float = 0.0
var _trick_pose_side: float = 0.0
var _trick_limb_targets: Dictionary = {}
var _rider_cosmetics: Dictionary = {}
var _equipment_weather: StringName = &"CLEAR"
var _equipment_wear: Dictionary = {}
var _equipment_wear_presentation_time: float = 0.0
var _clean_material_colors: Dictionary[StringName, Color] = {}
var _clean_material_roughness: Dictionary[StringName, float] = {}
var _wear_splats: Array[MeshInstance3D] = []
var _crash_scratches: Array[MeshInstance3D] = []
var _decal_roots: Dictionary[StringName, Node3D] = {}
var _sponsor_roots: Dictionary[StringName, Node3D] = {}
var _sponsor_labels: Array[Label3D] = []

var _materials: Dictionary[StringName, StandardMaterial3D] = {}


func _ready() -> void:
	_create_materials()
	_build_bike()
	if not pack_variant:
		_build_custom_graphics()
		_build_equipment_wear_overlays()
	_capture_clean_equipment_materials()
	reset_equipment_wear()
	if pack_variant:
		apply_pack_colors(pack_bike_color, pack_helmet_color)
		if &"--smoke-test" not in OS.get_cmdline_user_args():
			_build_pack_dust()
		_apply_pack_render_budget()
	else:
		_build_dust()


func _exit_tree() -> void:
	for mark: MeshInstance3D in _skid_marks:
		if is_instance_valid(mark):
			mark.queue_free()
	_skid_marks.clear()


func update_pose(
	front_wheel_y: float,
	rear_wheel_y: float,
	wheel_spin: float,
	speed_mps: float,
	steer: float,
	lean: float,
	dust_amount: float,
	boosting: bool = false,
	wobble: float = 0.0,
	lateral_slip: float = 0.0,
	delta: float = 1.0 / 60.0,
	rear_contact_point: Vector3 = Vector3.ZERO,
	rear_contact_normal: Vector3 = Vector3.UP,
	rear_contact_forward: Vector3 = Vector3.FORWARD,
	rear_contact_valid: bool = false,
	surface: StringName = &"PACKED",
	roughness: float = 0.35,
	roost_multiplier: float = 0.8,
	rear_slip: float = 0.0,
	front_compression: float = 0.0,
	rear_compression: float = 0.0,
	suspension_activity: float = 0.0,
	trick_pose: Dictionary = {}
) -> void:
	_front_wheel_pivot.position.y = front_wheel_y
	if _front_wheel_pivot.get_parent() == _front_assembly:
		_front_wheel_pivot.position.y = front_wheel_y - _front_assembly.position.y
	_rear_wheel_pivot.position.y = rear_wheel_y
	_front_wheel_pivot.rotation.x = wheel_spin
	_rear_wheel_pivot.rotation.x = wheel_spin
	_front_assembly.rotation.y = steer * 0.52
	_ride_phase = fmod(_ride_phase + speed_mps * delta * (0.82 + roughness * 0.36), TAU)
	var speed_bob := sin(_ride_phase) * clampf(speed_mps / 22.0, 0.0, 1.0) * (0.008 + roughness * 0.014)
	var suspension_squat := (front_compression + rear_compression) * 0.035
	_rider_root.position.y = 0.15 + speed_bob - suspension_squat + suspension_activity * 0.018
	var suspension_pitch := clampf((rear_compression - front_compression) * 0.18, -0.09, 0.09)
	_rider_root.rotation.x = lerpf(
		_rider_root.rotation.x,
		lean * 0.25 + suspension_pitch - (0.08 if boosting else 0.0),
		1.0 - exp(-11.0 * delta)
	)
	var counter_lean := -steer * clampf(speed_mps / 18.0, 0.0, 1.0) * 0.11
	_wobble_phase = advance_animation_phase(_wobble_phase, RIDER_WOBBLE_ANGULAR_SPEED, delta)
	var wobble_roll := sin(_wobble_phase) * wobble * 0.09
	_rider_root.rotation.z = lerpf(
		_rider_root.rotation.z,
		counter_lean + wobble_roll,
		animation_response_weight(9.0, delta)
	)
	_rider_torso_root.rotation.x = lerpf(
		_rider_torso_root.rotation.x,
		-0.12 - lean * 0.12 - (0.12 if boosting else 0.0),
		animation_response_weight(RIDER_TORSO_RESPONSE_HZ, delta)
	)
	_update_trick_pose_state(trick_pose, delta)
	_update_suspension_geometry(front_wheel_y, rear_wheel_y)
	_update_rider_limbs(steer, lean, boosting)
	if surface != _current_surface:
		set_surface(surface)
	var roost_intensity := clampf(
		(rear_slip * 0.95 + maxf(dust_amount - 0.15, 0.0) * 0.52 + clampf(lateral_slip / 9.0, 0.0, 0.5))
		* roost_multiplier,
		0.0,
		1.35
	)
	if rear_contact_valid:
		_set_dirt_emitter_transform(rear_contact_point, rear_contact_normal, rear_contact_forward)
	advance_equipment_wear_observation({
		&"surface": surface,
		&"weather": _equipment_weather,
		&"grounded": rear_contact_valid,
		&"dust_amount": dust_amount,
		&"roost_intensity": roost_intensity,
		&"speed_mps": speed_mps,
	}, delta)
	_update_dirt_intensity(dust_amount, roost_intensity, surface)
	_dust.emitting = rear_contact_valid and dust_amount > 0.07
	_roost.emitting = rear_contact_valid and roost_intensity > 0.14
	_clods.emitting = rear_contact_valid and roost_intensity > 0.2 and surface in [&"MUD", &"LOOSE_DIRT", &"GRAVEL"]
	_boost_trail.emitting = boosting
	if boosting and not _was_boosting:
		_boost_trail.restart()
	_was_boosting = boosting
	_skid_time += delta
	if rear_contact_valid and dust_amount > 0.18 and (lateral_slip > 2.4 or rear_slip > 0.58) and _skid_time >= 0.11:
		_drop_skid_mark(rear_contact_point, rear_contact_normal, rear_contact_forward)
		_skid_time = 0.0


static func animation_response_weight(response_hz: float, delta: float) -> float:
	return 1.0 - exp(-maxf(response_hz, 0.0) * maxf(delta, 0.0))


static func advance_animation_phase(phase: float, angular_speed: float, delta: float) -> float:
	return fposmod(phase + angular_speed * maxf(delta, 0.0), TAU)


func burst_landing_dust(
	intensity: float,
	contact_point: Vector3,
	contact_normal: Vector3,
	surface: StringName
) -> void:
	set_surface(surface)
	var forward := -global_transform.basis.z.slide(contact_normal).normalized()
	if pack_variant:
		_set_particle_transform(_roost, contact_point, contact_normal, forward)
		_set_particle_color(_roost, 0.34 + intensity * 0.34)
		_roost.restart()
		_roost.emitting = true
		return
	_set_particle_transform(_landing_dust, contact_point, contact_normal, forward)
	_set_particle_color(_landing_dust, 0.34 + intensity * 0.34)
	_landing_dust.restart()
	if surface in [&"MUD", &"LOOSE_DIRT"] and intensity > 0.42:
		_set_particle_transform(_clods, contact_point, contact_normal, forward)
		_clods.restart()


func burst_boost() -> void:
	if _boost_burst != null:
		_boost_burst.restart()
	elif pack_variant and _roost != null:
		# Pack bikes retain the two-emitter Web budget. A sharp roost restart,
		# followed by the sustained attack pose below, makes their spend readable
		# without allocating two more GPU systems to every opponent.
		_roost.restart()
		_roost.emitting = true


func reset_terrain_feedback() -> void:
	_ride_phase = 0.0
	for particles: GPUParticles3D in [_dust, _roost, _clods, _landing_dust]:
		if particles == null:
			continue
		particles.emitting = false
		particles.restart()
		particles.emitting = false
	_skid_time = 0.0


func reset_equipment_wear() -> void:
	_equipment_wear = RIDER_EQUIPMENT_WEAR.clean_state(_equipment_weather)
	_equipment_wear_presentation_time = 0.0
	_apply_equipment_wear_presentation()


func configure_equipment_weather(weather: StringName) -> void:
	_equipment_weather = StringName(String(weather).strip_edges().to_upper())
	if _equipment_wear.is_empty():
		_equipment_wear = RIDER_EQUIPMENT_WEAR.clean_state(_equipment_weather)
	else:
		_equipment_wear[&"weather"] = _equipment_weather
	_apply_equipment_wear_presentation()


func advance_equipment_wear_observation(observation: Dictionary, delta: float) -> void:
	if pack_variant:
		return
	var resolved := observation.duplicate(true)
	resolved[&"weather"] = resolved.get(&"weather", _equipment_weather)
	_equipment_wear = RIDER_EQUIPMENT_WEAR.advance(_equipment_wear, resolved, delta)
	_equipment_wear_presentation_time -= maxf(delta, 0.0)
	if _equipment_wear_presentation_time <= 0.0:
		_equipment_wear_presentation_time = 0.08
		_apply_equipment_wear_presentation()


func add_equipment_crash_wear(severity: float, surface: StringName) -> void:
	if pack_variant:
		return
	_equipment_wear = RIDER_EQUIPMENT_WEAR.add_crash(_equipment_wear, severity, surface)
	_equipment_wear_presentation_time = 0.08
	_apply_equipment_wear_presentation()


func get_equipment_wear_snapshot() -> Dictionary:
	return _equipment_wear.duplicate(true)


func apply_cosmetic_tier(tier: int) -> void:
	# Keep the emission shader variant warm and only change values at runtime.
	_restore_clean_equipment_materials()
	_materials[&"red"].albedo_color = Color("d93a2f")
	_materials[&"red"].emission = Color.BLACK
	_materials[&"red"].emission_energy_multiplier = 0.0
	_materials[&"helmet"].albedo_color = Color("f2b632")
	match clampi(tier, 0, 3):
		1:
			_materials[&"red"].albedo_color = Color("e34b31")
			_materials[&"helmet"].albedo_color = Color("56d6ff")
		2:
			_materials[&"red"].albedo_color = Color("f0642d")
			_materials[&"red"].emission = Color("6f1d10")
			_materials[&"red"].emission_energy_multiplier = 0.28
			_materials[&"helmet"].albedo_color = Color("f7e5b2")
		3:
			_materials[&"red"].albedo_color = Color("56d6ff")
			_materials[&"red"].emission = Color("174f61")
			_materials[&"red"].emission_energy_multiplier = 0.32
			_materials[&"helmet"].albedo_color = Color("ffb52d")
	_capture_clean_equipment_materials()
	_apply_equipment_wear_presentation()


func apply_pack_colors(bike_color: Color, helmet_color: Color) -> void:
	if _materials.is_empty():
		pack_bike_color = bike_color
		pack_helmet_color = helmet_color
		return
	_materials[&"red"].albedo_color = bike_color
	_materials[&"red"].emission = Color.BLACK
	_materials[&"red"].emission_energy_multiplier = 0.0
	_materials[&"helmet"].albedo_color = helmet_color
	_materials[&"jersey"].albedo_color = bike_color.lightened(0.08)
	_capture_clean_equipment_materials()
	_apply_equipment_wear_presentation()


func apply_rider_cosmetics(cosmetics: Dictionary) -> void:
	_rider_cosmetics = cosmetics.duplicate(true)
	if _materials.is_empty():
		return
	var body_type := StringName(cosmetics.get(&"body_type", &"ATHLETIC"))
	if _rider_torso_root != null:
		_rider_torso_root.scale = _body_type_scale(body_type)
	var accent_text := str(cosmetics.get(&"accent_color", "#FFB52D")).strip_edges()
	if not accent_text.begins_with("#"):
		accent_text = "#" + accent_text
	var accent := Color.from_string(accent_text, Color("ffb52d"))
	_materials[&"red"].albedo_color = _cosmetic_color(
		StringName(cosmetics.get(&"bike_livery", &"FACTORY")),
		accent,
		Color("d93a2f")
	)
	_materials[&"jersey"].albedo_color = _cosmetic_color(
		StringName(cosmetics.get(&"jersey", &"FACTORY_RED")),
		accent,
		Color("d93a2f")
	)
	_materials[&"denim"].albedo_color = _cosmetic_color(
		StringName(cosmetics.get(&"pants", &"DENIM")),
		accent,
		Color("1a365d")
	)
	_materials[&"helmet"].albedo_color = _cosmetic_color(
		StringName(cosmetics.get(&"helmet", &"CLASSIC_WHITE")),
		accent,
		Color("f2f0df")
	)
	_materials[&"goggles"].albedo_color = _cosmetic_color(
		StringName(cosmetics.get(&"goggles", &"CLEAR")),
		accent,
		Color("9fd7e5")
	)
	_materials[&"boots"].albedo_color = _cosmetic_color(
		StringName(cosmetics.get(&"boots", &"BLACK")),
		accent,
		Color("171d24")
	)
	_materials[&"gloves"].albedo_color = _cosmetic_color(
		StringName(cosmetics.get(&"gloves", &"BLACK")),
		accent,
		Color("171d24")
	)
	_materials[&"protection"].albedo_color = _cosmetic_color(
		StringName(cosmetics.get(&"protection", &"ROOST_GUARD")),
		accent,
		Color("e3e7e8")
	)
	_materials[&"accessory"].albedo_color = _cosmetic_color(
		StringName(cosmetics.get(&"accessory", &"NONE")),
		accent,
		Color("293842")
	)
	_materials[&"skin"].albedo_color = _skin_tone_color(
		StringName(cosmetics.get(&"skin_tone", &"MEDIUM"))
	)
	var palette := RIDER_GRAPHICS_CATALOG.palette(cosmetics.get(&"team_palette", &"STYLE"))
	var palette_id := StringName(palette.get(&"palette_id", &"STYLE"))
	var primary := accent
	var secondary := Color("f7e5b2")
	if palette_id != &"STYLE":
		primary = Color.from_string("#" + str(palette.get(&"primary", "E25532")), accent)
		secondary = Color.from_string("#" + str(palette.get(&"secondary", "F7E5B2")), Color("f7e5b2"))
		_materials[&"red"].albedo_color = primary
		_materials[&"jersey"].albedo_color = primary.lightened(0.05)
	_materials[&"decal_primary"].albedo_color = primary
	_materials[&"decal_secondary"].albedo_color = secondary
	if _rider_goggles_mesh != null:
		_rider_goggles_mesh.visible = StringName(cosmetics.get(&"goggles", &"CLEAR")) != &"NONE"
	if _rider_protection_mesh != null:
		_rider_protection_mesh.visible = StringName(cosmetics.get(&"protection", &"ROOST_GUARD")) != &"NONE"
	if _rider_accessory_mesh != null:
		_rider_accessory_mesh.visible = StringName(cosmetics.get(&"accessory", &"NONE")) != &"NONE"
	var plate_color := _cosmetic_color(
		StringName(cosmetics.get(&"number_plate", &"WHITE")),
		accent,
		Color("f7e5b2")
	)
	_materials[&"cream"].albedo_color = plate_color
	var number := clampi(int(cosmetics.get(&"rider_number", 17)), 1, 999)
	for label: Label3D in _number_labels:
		label.text = str(number)
		label.modulate = Color("10151b") if plate_color.get_luminance() > 0.45 else Color.WHITE
	_apply_custom_graphics(cosmetics)
	_capture_clean_equipment_materials()
	_apply_equipment_wear_presentation()


func get_rider_cosmetics_snapshot() -> Dictionary:
	return _rider_cosmetics.duplicate(true)


func get_rider_equipment_presentation_snapshot() -> Dictionary:
	var colors: Dictionary = {}
	for key: StringName in [
		&"red", &"jersey", &"denim", &"helmet", &"goggles", &"boots", &"gloves",
		&"protection", &"accessory", &"skin", &"decal_primary", &"decal_secondary",
	]:
		var material := _materials.get(key) as StandardMaterial3D
		colors[key] = material.albedo_color.to_html(false) if material != null else ""
	return {
		&"cosmetics": get_rider_cosmetics_snapshot(),
		&"wear": get_equipment_wear_snapshot(),
		&"colors": colors,
		&"visible": {
			&"goggles": _rider_goggles_mesh != null and _rider_goggles_mesh.visible,
			&"protection": _rider_protection_mesh != null and _rider_protection_mesh.visible,
			&"accessory": _rider_accessory_mesh != null and _rider_accessory_mesh.visible,
			&"decal_meshes": _visible_graphics_mesh_count(),
			&"sponsor_marks": _visible_sponsor_mark_count(),
		},
		&"identity": {
			&"body_type": str(_rider_cosmetics.get(&"body_type", "ATHLETIC")),
			&"skin_tone": str(_rider_cosmetics.get(&"skin_tone", "MEDIUM")),
			&"voice": str(_rider_cosmetics.get(&"voice", "FOCUSED")),
			&"body_scale": _rider_torso_root.scale if _rider_torso_root != null else Vector3.ONE,
		},
		&"graphics": {
			&"team_palette": str(_rider_cosmetics.get(&"team_palette", "STYLE")),
			&"decal_id": str(_rider_cosmetics.get(&"decal_id", "CLEAN")),
			&"sponsor_id": str(_rider_cosmetics.get(&"sponsor_id", "NONE")),
			&"sponsor_placement": str(_rider_cosmetics.get(&"sponsor_placement", "SHROUDS")),
		},
		&"separate_surfaces": {
			&"gloves": _glove_multimesh != null and _glove_multimesh.instance_count == 2,
			&"boots": _boot_multimesh != null and _boot_multimesh.instance_count == 2,
		},
		&"overlays": {
			&"soil_visible": _any_overlay_visible(_wear_splats),
			&"crash_visible": _any_overlay_visible(_crash_scratches),
		},
	}


func apply_pack_identity(bike_color: Color, helmet_color: Color, rider_number: int) -> void:
	apply_pack_colors(bike_color, helmet_color)
	for label: Label3D in _number_labels:
		label.text = str(clampi(rider_number, 1, 999))


func _cosmetic_color(cosmetic_id: StringName, accent: Color, fallback: Color) -> Color:
	match cosmetic_id:
		&"FACTORY", &"FACTORY_RED", &"MESA_RED": return Color("d93a2f")
		&"DESERT", &"DESERT_ORANGE", &"DESERT_WORKS", &"RUST": return Color("e06d35")
		&"DESERT_CREAM", &"MESA_SAND": return Color("d6ad6c")
		&"BROWN", &"NECK_ROLL": return Color("563624")
		&"AQUA", &"MESA_CYAN", &"MESA_BLUE", &"NIGHT_CYAN", &"CYAN", &"CYAN_LENS": return Color("279ec2")
		&"STEALTH", &"PRO_BLACK", &"NIGHT_BLACK", &"NIGHT_RACE", &"BLACK", &"CHARCOAL": return Color("171d24")
		&"TOUR_CHAMPION", &"CHAMPION_GOLD", &"GOLD", &"BLACK_GOLD", &"GOLD_MIRROR", &"CHAMPION_SASH": return Color("d8a52e")
		&"CLASSIC_WHITE", &"WHITE", &"ROOST_GUARD": return Color("f2f0df")
		&"CLEAR": return Color("9fd7e5")
		&"AMBER": return Color("e49a36")
		&"ENDURO_VEST": return Color("b47a43")
		&"CHEST_PLATE": return Color("263742")
		&"PRO_ARMOR": return Color("d8a52e")
		&"HYDRATION_PACK": return Color("1d6577")
		&"NONE": return fallback
		&"FACTORY_YELLOW", &"YELLOW": return Color("f2b632")
		&"DENIM": return Color("1a365d")
		&"CREAM": return Color("f7e5b2")
		&"ACCENT": return accent
	return accent if not str(cosmetic_id).is_empty() else fallback


func _body_type_scale(body_type: StringName) -> Vector3:
	match body_type:
		&"COMPACT": return Vector3(0.91, 0.98, 0.94)
		&"POWERFUL": return Vector3(1.11, 1.02, 1.06)
	return Vector3.ONE


func _skin_tone_color(skin_tone: StringName) -> Color:
	match skin_tone:
		&"LIGHT": return Color("f2c7a5")
		&"MEDIUM_LIGHT": return Color("dca47f")
		&"MEDIUM_DEEP": return Color("8e573e")
		&"DEEP": return Color("543224")
	return Color("b97856")


func update_pack_pose(
	speed_mps: float,
	steer: float,
	corner_lean: float,
	suspension_phase: float,
	delta: float,
	grounded: bool = true,
	suspension_activity: float = 0.0,
	surface: StringName = &"PACKED",
	landing_event: bool = false,
	landing_quality: float = 1.0,
	boosting: bool = false
) -> void:
	# Pack bikes use the exact player silhouette and articulated rider. Their
	# feedback emitters are deliberately smaller than the player's and omit the
	# persistent skid pool, so a full field still reads as physical on Web.
	if _front_wheel_pivot == null or _rear_wheel_pivot == null:
		return
	var safe_delta := maxf(delta, 0.0)
	var wheel_step := speed_mps / 0.307 * safe_delta
	_front_wheel_pivot.rotation.x = fmod(_front_wheel_pivot.rotation.x + wheel_step, TAU)
	_rear_wheel_pivot.rotation.x = fmod(_rear_wheel_pivot.rotation.x + wheel_step, TAU)
	_front_assembly.rotation.y = lerpf(_front_assembly.rotation.y, steer * 0.52, 1.0 - exp(-9.0 * safe_delta))

	var fork_chatter := sin(suspension_phase * 1.9) * 0.018 + sin(suspension_phase * 3.7) * 0.008
	var rear_chatter := sin(suspension_phase * 1.9 + 0.85) * 0.016
	fork_chatter -= suspension_activity * 0.035
	rear_chatter -= suspension_activity * 0.028
	_update_suspension_geometry(-0.39 + fork_chatter, -0.39 + rear_chatter)
	_rider_root.position.y = 0.15 + (fork_chatter + rear_chatter) * 0.32
	_rider_root.rotation.z = lerpf(_rider_root.rotation.z, -corner_lean * 0.16, 1.0 - exp(-8.0 * safe_delta))
	_rider_torso_root.rotation.x = lerpf(
		_rider_torso_root.rotation.x,
		-0.25 if boosting else -0.13,
		1.0 - exp(-8.0 * safe_delta)
	)
	_update_rider_limbs(steer, 0.08, boosting)
	if _dust == null:
		return
	if surface != _current_surface:
		set_surface(surface)
	var rear_forward := -global_transform.basis.z.normalized()
	var rear_point := global_position + global_transform.basis.z.normalized() * 0.88 - Vector3.UP * 0.31
	_set_dirt_emitter_transform(rear_point, Vector3.UP, rear_forward)
	var dust_amount := clampf(speed_mps / 22.0, 0.0, 0.9)
	var roost_intensity := clampf(
		dust_amount * 0.72 + absf(steer) * 0.38 + (0.28 if boosting else 0.0),
		0.0,
		1.0
	)
	_update_dirt_intensity(dust_amount, roost_intensity, surface)
	_dust.emitting = grounded and speed_mps > 4.0
	_roost.emitting = grounded and speed_mps > 8.0 and (
		boosting or absf(steer) > 0.12 or roost_intensity > 0.52
	)
	if not pack_variant:
		_clods.emitting = grounded and speed_mps > 9.0 and surface in [&"MUD", &"LOOSE_DIRT"] and roost_intensity > 0.62
	if landing_event:
		burst_landing_dust(clampf(1.15 - landing_quality, 0.25, 1.0), rear_point, Vector3.UP, surface)


func set_surface(surface: StringName) -> void:
	_current_surface = surface
	_surface_tint = surface_feedback_tint(surface)
	_set_particle_color(_dust, 0.36)
	_set_particle_color(_roost, 0.74)
	if not pack_variant:
		_set_particle_color(_clods, 1.0)
		_set_particle_color(_landing_dust, 0.58)


static func surface_feedback_tint(surface: Variant) -> Color:
	match StringName(str(surface).strip_edges().to_upper().replace(" ", "_").replace("-", "_")):
		&"MUD":
			return Color(0.19, 0.105, 0.055, 1.0)
		&"SAND":
			return Color(0.72, 0.57, 0.34, 1.0)
		&"GRASS":
			return Color(0.28, 0.38, 0.20, 1.0)
		&"GRAVEL":
			return Color(0.42, 0.38, 0.33, 1.0)
		&"ROCK":
			return Color(0.31, 0.30, 0.29, 1.0)
		&"LOOSE_DIRT":
			return Color(0.51, 0.285, 0.12, 1.0)
		&"LOAM":
			return Color(0.30, 0.205, 0.12, 1.0)
		&"DIRT":
			return Color(0.39, 0.225, 0.11, 1.0)
		_:
			return Color(0.44, 0.25, 0.12, 1.0)


func _build_equipment_wear_overlays() -> void:
	var splat_specs: Array = [
		["MudSplatBackA", 0.075, Vector3(-0.14, 1.09, 0.278), Vector3(1.35, 0.62, 0.22), _rider_torso_root],
		["MudSplatBackB", 0.052, Vector3(0.12, 1.22, 0.275), Vector3(1.0, 0.72, 0.20), _rider_torso_root],
		["MudSplatHelmet", 0.058, Vector3(0.13, 1.69, 0.015), Vector3(0.9, 1.3, 0.55), _rider_torso_root],
		["MudSplatHip", 0.064, Vector3(-0.16, 0.74, 0.52), Vector3(0.82, 1.25, 0.42), _rider_torso_root],
		["MudSplatFender", 0.07, Vector3(0.13, 0.73, 0.91), Vector3(1.2, 0.48, 1.7), self],
		["MudSplatPlate", 0.048, Vector3(-0.41, 0.49, 0.69), Vector3(0.25, 1.35, 0.8), self],
	]
	for spec: Array in splat_specs:
		var splat := _add_sphere(spec[0], spec[1], spec[2], &"wear", spec[4])
		splat.scale = spec[3]
		splat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		splat.visible = false
		_wear_splats.append(splat)
	var scratch_specs: Array = [
		["CrashScratchBackA", Vector3(0.24, 0.024, 0.014), Vector3(-0.055, 1.17, 0.274), Vector3(0.0, 0.0, -0.42), _rider_torso_root],
		["CrashScratchBackB", Vector3(0.18, 0.018, 0.014), Vector3(0.075, 1.08, 0.276), Vector3(0.0, 0.0, 0.36), _rider_torso_root],
		["CrashScratchHelmet", Vector3(0.16, 0.018, 0.014), Vector3(-0.08, 1.72, 0.012), Vector3(0.0, 0.0, -0.25), _rider_torso_root],
		["CrashScratchFender", Vector3(0.22, 0.018, 0.025), Vector3(-0.15, 0.735, 0.93), Vector3(0.0, 0.25, 0.0), self],
	]
	for spec: Array in scratch_specs:
		var scratch := _add_box(spec[0], spec[1], spec[2], &"scrape", spec[3], spec[4])
		scratch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		scratch.visible = false
		_crash_scratches.append(scratch)


func _capture_clean_equipment_materials() -> void:
	if pack_variant:
		return
	for key: StringName in WEARABLE_MATERIAL_KEYS:
		var material := _materials.get(key) as StandardMaterial3D
		if material == null:
			continue
		_clean_material_colors[key] = material.albedo_color
		_clean_material_roughness[key] = material.roughness


func _restore_clean_equipment_materials() -> void:
	if pack_variant:
		return
	for key: StringName in WEARABLE_MATERIAL_KEYS:
		var material := _materials.get(key) as StandardMaterial3D
		if material == null or not _clean_material_colors.has(key):
			continue
		material.albedo_color = _clean_material_colors[key]
		material.roughness = float(_clean_material_roughness.get(key, material.roughness))


func _apply_equipment_wear_presentation() -> void:
	if pack_variant or _materials.is_empty() or _clean_material_colors.is_empty():
		return
	var dry_dust := clampf(float(_equipment_wear.get(&"dry_dust", 0.0)), 0.0, 1.0)
	var mud := clampf(float(_equipment_wear.get(&"mud", 0.0)), 0.0, 1.0)
	var wetness := clampf(float(_equipment_wear.get(&"wetness", 0.0)), 0.0, 1.0)
	var crash_wear := clampf(float(_equipment_wear.get(&"crash_wear", 0.0)), 0.0, 1.0)
	var dust_color := Color("9b7045")
	var mud_color := Color("352116")
	var scrape_color := Color("161719")
	for key: StringName in WEARABLE_MATERIAL_KEYS:
		var material := _materials.get(key) as StandardMaterial3D
		if material == null or not _clean_material_colors.has(key):
			continue
		var clean_color: Color = _clean_material_colors[key]
		var worn_color := clean_color.lerp(dust_color, dry_dust * 0.28)
		worn_color = worn_color.lerp(mud_color, mud * 0.54)
		worn_color = worn_color.lerp(scrape_color, crash_wear * 0.16)
		worn_color = worn_color.darkened(wetness * 0.11)
		material.albedo_color = worn_color
		var clean_roughness := float(_clean_material_roughness.get(key, material.roughness))
		material.roughness = clampf(
			clean_roughness + dry_dust * 0.16 + mud * 0.08 - wetness * 0.34,
			0.08,
			1.0
		)
	var soil_strength := clampf(maxf(dry_dust * 0.86, mud), 0.0, 1.0)
	var wear_material := _materials.get(&"wear") as StandardMaterial3D
	if wear_material != null:
		var soil_color := dust_color.lerp(mud_color, mud / maxf(dry_dust + mud, 0.001))
		var overlay_alpha := (
			clampf(0.24 + soil_strength * 0.70, 0.0, 0.94)
			if soil_strength >= 0.085 else 0.0
		)
		wear_material.albedo_color = Color(soil_color.r, soil_color.g, soil_color.b, overlay_alpha)
	for splat: MeshInstance3D in _wear_splats:
		splat.visible = soil_strength >= 0.085
	var scrape_material := _materials.get(&"scrape") as StandardMaterial3D
	if scrape_material != null:
		scrape_material.albedo_color = Color(
			scrape_color.r, scrape_color.g, scrape_color.b, crash_wear * 0.94
		)
	for scratch: MeshInstance3D in _crash_scratches:
		scratch.visible = crash_wear >= 0.12


func _any_overlay_visible(overlays: Array[MeshInstance3D]) -> bool:
	for overlay: MeshInstance3D in overlays:
		if is_instance_valid(overlay) and overlay.visible:
			return true
	return false


func _create_materials() -> void:
	_materials[&"red"] = _material(Color("d93a2f"), 0.32, 0.0)
	_materials[&"cream"] = _material(Color("f5d67b"), 0.55, 0.0)
	_materials[&"rubber"] = _material(Color("111318"), 0.94, 0.0)
	_materials[&"metal"] = _material(Color("727b83"), 0.34, 1.0)
	_materials[&"engine"] = _material(Color("20262b"), 0.48, 1.0)
	_materials[&"denim"] = _material(Color("1a365d"), 0.78, 0.0)
	_materials[&"jersey"] = _material(Color("d93a2f"), 0.38, 0.0)
	_materials[&"helmet"] = _material(Color("f2b632"), 0.22, 0.0)
	_materials[&"visor"] = _material(Color("121c24"), 0.1, 1.0)
	_materials[&"goggles"] = _material(Color("9fd7e5"), 0.12, 0.65)
	_materials[&"boots"] = _material(Color("171d24"), 0.72, 0.0)
	_materials[&"gloves"] = _material(Color("171d24"), 0.56, 0.0)
	_materials[&"protection"] = _material(Color("f2f0df"), 0.34, 0.0)
	_materials[&"accessory"] = _material(Color("293842"), 0.62, 0.0)
	_materials[&"skin"] = _material(Color("b97856"), 0.64, 0.0)
	_materials[&"decal_primary"] = _material(Color("d93a2f"), 0.32, 0.0)
	_materials[&"decal_secondary"] = _material(Color("f7e5b2"), 0.38, 0.0)
	_materials[&"wear"] = _overlay_material(Color(0.25, 0.14, 0.07, 0.0))
	_materials[&"scrape"] = _overlay_material(Color(0.08, 0.08, 0.09, 0.0))
	if pack_variant:
		for neutral_key: StringName in [
			&"cream", &"rubber", &"metal", &"engine", &"denim", &"visor",
			&"goggles", &"boots", &"gloves", &"protection", &"accessory", &"skin",
		]:
			if not _shared_pack_neutral_materials.has(neutral_key):
				_shared_pack_neutral_materials[neutral_key] = _materials[neutral_key]
			else:
				_materials[neutral_key] = _shared_pack_neutral_materials[neutral_key] as StandardMaterial3D
	_materials[&"red"].emission_enabled = true
	_materials[&"red"].emission = Color.BLACK
	_materials[&"red"].emission_energy_multiplier = 0.0


func _build_bike() -> void:
	# Steering pivots around the head tube; the wheel now yaws with the bars and
	# still receives independent suspension travel and spin.
	_front_assembly = Node3D.new()
	_front_assembly.name = "FrontAssembly"
	_front_assembly.position = Vector3(0.0, 0.62, -0.301468)
	add_child(_front_assembly)

	_front_wheel_pivot = Node3D.new()
	_front_wheel_pivot.name = "FrontWheelPivot"
	_front_wheel_pivot.position = Vector3(0.0, -1.01, -0.292532)
	_front_wheel_pivot.scale = Vector3.ONE * 0.82973
	_front_assembly.add_child(_front_wheel_pivot)
	_add_wheel(_front_wheel_pivot, false)

	_rear_wheel_pivot = Node3D.new()
	_rear_wheel_pivot.name = "RearWheelPivot"
	_rear_wheel_pivot.position = Vector3(0.0, -0.39, 0.74329)
	_rear_wheel_pivot.scale = Vector3.ONE * 0.82973
	add_child(_rear_wheel_pivot)
	_add_wheel(_rear_wheel_pivot, true)

	var chassis_parts: Dictionary = {}
	_batch_box(chassis_parts, &"engine", Vector3(0.5, 0.4, 0.390043), Vector3(0.0, 0.11, 0.193051))
	_batch_cylinder(chassis_parts, &"engine", 0.23, 0.5, Vector3(0.0, 0.07, 0.241806), Vector3(0.0, 0.0, PI * 0.5), 14)
	_batch_cylinder(chassis_parts, &"engine", 0.18, 0.08, Vector3(0.29, 0.07, 0.241806), Vector3(0.0, 0.0, PI * 0.5), 14)
	_batch_box(chassis_parts, &"engine", Vector3(0.42, 0.34, 0.236812), Vector3(0.0, 0.36, 0.06768), Vector3(-0.14, 0.0, 0.0))
	for fin_index: int in 5:
		_batch_box(chassis_parts, &"metal", Vector3(0.56, 0.024, 0.285567), Vector3(0.0, 0.24 + fin_index * 0.062, 0.060715), Vector3(-0.14, 0.0, 0.0))
	_batch_box(chassis_parts, &"metal", Vector3(0.5, 0.075, 0.473624), Vector3(0.0, -0.2, 0.172156), Vector3(0.05, 0.0, 0.0))
	for side: float in [-1.0, 1.0]:
		_batch_cylinder_between(chassis_parts, &"metal", Vector3(side * 0.19, 0.58, -0.203957), Vector3(side * 0.18, 0.1, 0.353247), 0.045)
		_batch_cylinder_between(chassis_parts, &"metal", Vector3(side * 0.18, 0.53, -0.162167), Vector3(side * 0.2, -0.1, 0.186086), 0.04)
		_batch_cylinder_between(chassis_parts, &"metal", Vector3(side * 0.2, -0.1, 0.186086), Vector3(side * 0.18, 0.08, 0.436828), 0.04)
		_batch_cylinder_between(chassis_parts, &"metal", Vector3(side * 0.18, 0.25, 0.353247), Vector3(side * 0.18, 0.58, 0.74329), 0.038)
		_batch_box(chassis_parts, &"engine", Vector3(0.04, 0.4, 0.278602), Vector3(side * 0.29, 0.42, -0.099481))
		_batch_box(chassis_parts, &"metal", Vector3(0.22, 0.035, 0.111441), Vector3(side * 0.33, 0.02, 0.367177))
	_batch_cylinder_between(chassis_parts, &"metal", Vector3(-0.22, 0.3, -0.022866), Vector3(-0.29, 0.05, 0.213946), 0.045)
	_batch_cylinder_between(chassis_parts, &"metal", Vector3(-0.29, 0.05, 0.213946), Vector3(-0.31, 0.37, 0.534338), 0.05)
	_batch_capsule(chassis_parts, &"metal", 0.085, 0.403973, Vector3(-0.31, 0.45, 0.68757), Vector3(PI * 0.5, 0.0, 0.0))
	_batch_box(chassis_parts, &"cream", Vector3(0.04, 0.16, 0.292532), Vector3(-0.405, 0.46, 0.680605), Vector3(0.08, 0.0, 0.0))
	_batch_capsule(chassis_parts, &"red", 0.265, 0.531, Vector3(0.0, 0.55, -0.099481), Vector3(PI * 0.5, 0.0, 0.0), Vector3(1.0, 0.88, 1.0))
	for side: float in [-1.0, 1.0]:
		_batch_box(chassis_parts, &"red", Vector3(0.055, 0.38, 0.403973), Vector3(side * 0.275, 0.48, -0.078586), Vector3(-0.1, 0.0, side * 0.08))
		_batch_box(chassis_parts, &"cream", Vector3(0.052, 0.3, 0.320392), Vector3(side * 0.255, 0.5, 0.415933), Vector3(0.08, 0.0, side * 0.04))
	_batch_cylinder(chassis_parts, &"metal", 0.075, 0.035, Vector3(0.0, 0.79, -0.141272), Vector3.ZERO, 12)
	_batch_box(chassis_parts, &"rubber", Vector3(0.43, 0.18, 0.598994), Vector3(0.0, 0.66, 0.436828), Vector3(0.035, 0.0, 0.0))
	_batch_box(chassis_parts, &"rubber", Vector3(0.39, 0.055, 0.508449), Vector3(0.0, 0.77, 0.415933), Vector3(0.035, 0.0, 0.0))
	_batch_tapered_box(chassis_parts, &"red", 0.48, 0.22, 0.065, 0.626855, Vector3(0.0, 0.68, 0.854731), Vector3(0.16, 0.0, 0.0))
	_commit_mesh_batch("DetailedChassis", chassis_parts, self)

	var front_parts: Dictionary = {}
	for side: float in [-1.0, 1.0]:
		_batch_cylinder_between(front_parts, &"metal", Vector3(side * 0.15, 0.13, 0.020895), Vector3(side * 0.15, -0.28, -0.153231), 0.052)
		_batch_cylinder_between(front_parts, &"metal", Vector3(side * 0.1, 0.13, 0.0), Vector3(side * 0.1, 0.21, -0.05572), 0.027)
	_batch_box(front_parts, &"metal", Vector3(0.46, 0.055, 0.062685), Vector3(0.0, 0.11, 0.0))
	_batch_box(front_parts, &"metal", Vector3(0.42, 0.05, 0.05572), Vector3(0.0, -0.08, -0.02786))
	_batch_cylinder_between(front_parts, &"metal", Vector3(-0.44, 0.2, -0.069651), Vector3(0.44, 0.2, -0.069651), 0.025)
	_batch_cylinder_between(front_parts, &"cream", Vector3(-0.16, 0.21, -0.069651), Vector3(0.16, 0.21, -0.069651), 0.035)
	_batch_tapered_box(front_parts, &"red", 0.24, 0.48, 0.06, 0.626855, Vector3(0.0, -0.4, -0.334323), Vector3(-0.15, 0.0, 0.0))
	_batch_box(front_parts, &"cream", Vector3(0.49, 0.46, 0.038308), Vector3(0.0, -0.05, -0.174126), Vector3(-0.16, 0.0, 0.0))
	_commit_mesh_batch("SteeringDetails", front_parts, _front_assembly)
	_add_number_label(_front_assembly, Vector3(0.0, -0.05, -0.198), Vector3(0.0, PI, -0.16), 0.0026)

	_front_lower_fork_root = Node3D.new()
	_front_lower_fork_root.name = "TelescopingForkLowers"
	_front_assembly.add_child(_front_lower_fork_root)
	var lower_fork_parts: Dictionary = {}
	for side: float in [-1.0, 1.0]:
		_batch_cylinder(lower_fork_parts, &"metal", 0.042, 1.0, Vector3(side * 0.15, 0.0, -0.5), Vector3(PI * 0.5, 0.0, 0.0), 10)
	_batch_box(lower_fork_parts, &"metal", Vector3(0.11, 0.14, 0.16), Vector3(-0.18, 0.0, -0.88))
	_commit_mesh_batch("ForkLowerBatch", lower_fork_parts, _front_lower_fork_root)

	_left_grip_anchor = Node3D.new()
	_left_grip_anchor.position = Vector3(-0.4, 0.2, -0.069651)
	_front_assembly.add_child(_left_grip_anchor)
	_right_grip_anchor = Node3D.new()
	_right_grip_anchor.position = Vector3(0.4, 0.2, -0.069651)
	_front_assembly.add_child(_right_grip_anchor)

	_rear_linkage_root = Node3D.new()
	_rear_linkage_root.name = "RearSwingarmLinkage"
	add_child(_rear_linkage_root)
	var linkage_parts: Dictionary = {}
	for side: float in [-1.0, 1.0]:
		_batch_box(linkage_parts, &"metal", Vector3(0.07, 0.1, 1.0), Vector3(side * 0.17, 0.0, -0.5))
	_batch_box(linkage_parts, &"metal", Vector3(0.045, 0.1, 0.9), Vector3(-0.235, 0.075, -0.5))
	_commit_mesh_batch("SwingarmBatch", linkage_parts, _rear_linkage_root)

	_rear_shock_root = Node3D.new()
	_rear_shock_root.name = "RearShock"
	add_child(_rear_shock_root)
	var shock_parts: Dictionary = {}
	_batch_cylinder(shock_parts, &"metal", 0.05, 1.0, Vector3(0.0, 0.0, -0.5), Vector3(PI * 0.5, 0.0, 0.0), 10)
	for spring_index: int in 7:
		_batch_torus(shock_parts, &"metal", 0.075, 0.095, Vector3(0.0, 0.0, -0.14 - spring_index * 0.12), Vector3(PI * 0.5, 0.0, 0.0), 12, 5)
	_commit_mesh_batch("ShockBatch", shock_parts, _rear_shock_root)

	_left_foot_anchor = Node3D.new()
	_left_foot_anchor.position = Vector3(-0.31, 0.02, 0.381107)
	add_child(_left_foot_anchor)
	_right_foot_anchor = Node3D.new()
	_right_foot_anchor.position = Vector3(0.31, 0.02, 0.381107)
	add_child(_right_foot_anchor)

	_rider_root = Node3D.new()
	_rider_root.name = "RiderRoot"
	_rider_root.position = Vector3(0.0, 0.15, 0.206981)
	add_child(_rider_root)
	_rider_torso_root = Node3D.new()
	_rider_torso_root.name = "RiderTorsoRig"
	_rider_root.add_child(_rider_torso_root)
	var rider_parts: Dictionary = {}
	_batch_capsule(rider_parts, &"jersey", 0.265, 0.7, Vector3(0.0, 1.08, 0.04), Vector3(-0.18, 0.0, 0.0), Vector3(1.0, 1.0, 0.78))
	_batch_box(rider_parts, &"jersey", Vector3(0.5, 0.25, 0.34), Vector3(0.0, 0.82, 0.22), Vector3(-0.08, 0.0, 0.0))
	_batch_capsule(rider_parts, &"denim", 0.2, 0.54, Vector3(0.0, 0.72, 0.32), Vector3(0.0, 0.0, PI * 0.5), Vector3(1.0, 0.86, 1.0))
	_batch_box(rider_parts, &"jersey", Vector3(0.055, 0.24, 0.025), Vector3(-0.09, 1.08, 0.27), Vector3(-0.18, 0.0, 0.0))
	_batch_box(rider_parts, &"jersey", Vector3(0.055, 0.24, 0.025), Vector3(0.09, 1.08, 0.27), Vector3(-0.18, 0.0, 0.0))
	_batch_cylinder(rider_parts, &"skin", 0.095, 0.18, Vector3(0.0, 1.38, -0.03), Vector3.ZERO, 10)
	_batch_box(rider_parts, &"skin", Vector3(0.23, 0.10, 0.045), Vector3(0.0, 1.54, -0.405), Vector3(-0.08, 0.0, 0.0))
	_batch_sphere(rider_parts, &"helmet", 0.285, Vector3(0.0, 1.6, -0.17), Vector3.ONE)
	_batch_box(rider_parts, &"helmet", Vector3(0.36, 0.19, 0.22), Vector3(0.0, 1.52, -0.39), Vector3(-0.08, 0.0, 0.0))
	_batch_box(rider_parts, &"helmet", Vector3(0.43, 0.035, 0.28), Vector3(0.0, 1.82, -0.31), Vector3(-0.18, 0.0, 0.0))
	_batch_box(rider_parts, &"helmet", Vector3(0.065, 0.43, 0.22), Vector3(-0.24, 1.62, -0.15), Vector3(0.0, 0.0, 0.08))
	_commit_mesh_batch("RiderBodyBatch", rider_parts, _rider_torso_root)
	var goggles_parts: Dictionary = {}
	_batch_box(goggles_parts, &"goggles", Vector3(0.39, 0.13, 0.055), Vector3(0.0, 1.64, -0.445), Vector3(-0.08, 0.0, 0.0))
	_commit_mesh_batch("RiderGoggles", goggles_parts, _rider_torso_root)
	_rider_goggles_mesh = _rider_torso_root.get_node_or_null("RiderGoggles_goggles") as MeshInstance3D
	var protection_parts: Dictionary = {}
	_batch_box(protection_parts, &"protection", Vector3(0.48, 0.34, 0.07), Vector3(0.0, 1.12, -0.205), Vector3(-0.14, 0.0, 0.0))
	_batch_box(protection_parts, &"protection", Vector3(0.42, 0.36, 0.05), Vector3(0.0, 1.08, 0.235), Vector3(-0.18, 0.0, 0.0))
	_commit_mesh_batch("RiderProtection", protection_parts, _rider_torso_root)
	_rider_protection_mesh = _rider_torso_root.get_node_or_null("RiderProtection_protection") as MeshInstance3D
	var accessory_parts: Dictionary = {}
	_batch_box(accessory_parts, &"accessory", Vector3(0.32, 0.4, 0.13), Vector3(0.0, 1.06, 0.33), Vector3(-0.18, 0.0, 0.0))
	_batch_torus(accessory_parts, &"accessory", 0.16, 0.205, Vector3(0.0, 1.39, -0.02), Vector3(PI * 0.5, 0.0, 0.0), 12, 5)
	_commit_mesh_batch("RiderAccessory", accessory_parts, _rider_torso_root)
	_rider_accessory_mesh = _rider_torso_root.get_node_or_null("RiderAccessory_accessory") as MeshInstance3D
	_rider_accessory_mesh.visible = false
	_build_rider_limb_multimeshes()
	_update_suspension_geometry(-0.39, -0.39)
	_update_rider_limbs(0.0, 0.0, false)


func _build_custom_graphics() -> void:
	for decal_id: StringName in [&"CLEAN", &"SPEED_STRIPES", &"CHECKERED", &"TOPO_LINES", &"LIGHTNING"]:
		var root := Node3D.new()
		root.name = "Decal_%s" % String(decal_id)
		root.visible = false
		add_child(root)
		_decal_roots[decal_id] = root

	var stripes := _decal_roots[&"SPEED_STRIPES"]
	for side: float in [-1.0, 1.0]:
		for stripe_index: int in 2:
			_add_box(
				"SpeedStripe_%s_%d" % ["L" if side < 0.0 else "R", stripe_index],
				Vector3(0.014, 0.052, 0.29),
				Vector3(side * 0.306, 0.51 + stripe_index * 0.075, -0.105 + stripe_index * 0.025),
				&"decal_secondary",
				Vector3(-0.11, 0.0, side * 0.11),
				stripes
			)

	var checkers := _decal_roots[&"CHECKERED"]
	for side: float in [-1.0, 1.0]:
		for row: int in 2:
			for column: int in 3:
				if (row + column) % 2 == 0:
					_add_box(
						"Checker_%s_%d_%d" % ["L" if side < 0.0 else "R", row, column],
						Vector3(0.015, 0.074, 0.074),
						Vector3(side * 0.307, 0.45 + row * 0.077, -0.18 + column * 0.078),
						&"decal_secondary",
						Vector3(-0.1, 0.0, side * 0.08),
						checkers
					)

	var topo := _decal_roots[&"TOPO_LINES"]
	for side: float in [-1.0, 1.0]:
		for line_index: int in 4:
			_add_box(
				"Topo_%s_%d" % ["L" if side < 0.0 else "R", line_index],
				Vector3(0.014, 0.018, 0.27 - line_index * 0.025),
				Vector3(side * 0.307, 0.43 + line_index * 0.065, -0.09 + sin(float(line_index)) * 0.035),
				&"decal_secondary",
				Vector3(-0.1, 0.0, side * (0.05 + line_index * 0.025)),
				topo
			)

	var lightning := _decal_roots[&"LIGHTNING"]
	for side: float in [-1.0, 1.0]:
		for bolt_index: int in 3:
			_add_box(
				"Lightning_%s_%d" % ["L" if side < 0.0 else "R", bolt_index],
				Vector3(0.015, 0.052, 0.19),
				Vector3(side * 0.308, 0.58 - bolt_index * 0.075, -0.17 + bolt_index * 0.115),
				&"decal_secondary",
				Vector3(-0.1, 0.0, side * (-0.48 if bolt_index % 2 == 0 else 0.48)),
				lightning
			)

	for placement_id: StringName in [&"SHROUDS", &"FENDERS", &"RIDER_KIT"]:
		var root := Node3D.new()
		root.name = "Sponsor_%s" % String(placement_id)
		root.visible = false
		if placement_id == &"RIDER_KIT":
			_rider_torso_root.add_child(root)
		else:
			add_child(root)
		_sponsor_roots[placement_id] = root
	_add_sponsor_label(_sponsor_roots[&"SHROUDS"], Vector3(-0.312, 0.50, -0.08), Vector3(0.0, -PI * 0.5, 0.0), 0.0016)
	_add_sponsor_label(_sponsor_roots[&"SHROUDS"], Vector3(0.312, 0.50, -0.08), Vector3(0.0, PI * 0.5, 0.0), 0.0016)
	_add_sponsor_label(_sponsor_roots[&"FENDERS"], Vector3(0.0, 0.715, 0.88), Vector3(-PI * 0.5, 0.0, 0.0), 0.0018)
	_add_sponsor_label(_sponsor_roots[&"FENDERS"], Vector3(0.0, 0.45, -0.66), Vector3(-PI * 0.5, PI, 0.0), 0.0018)
	_add_sponsor_label(_sponsor_roots[&"RIDER_KIT"], Vector3(0.0, 1.10, -0.245), Vector3(0.0, PI, -0.14), 0.0018)
	_add_sponsor_label(_sponsor_roots[&"RIDER_KIT"], Vector3(0.0, 1.10, 0.278), Vector3(-0.18, 0.0, 0.0), 0.0018)


func _add_sponsor_label(
	parent: Node3D,
	position: Vector3,
	rotation: Vector3,
	pixel_size: float
) -> void:
	var label := Label3D.new()
	label.name = "SponsorMark"
	label.text = ""
	label.font_size = 84
	label.outline_size = 14
	label.pixel_size = pixel_size
	label.position = position
	label.rotation = rotation
	label.modulate = Color.WHITE
	label.outline_modulate = Color("12171b")
	label.no_depth_test = false
	parent.add_child(label)
	_sponsor_labels.append(label)


func _apply_custom_graphics(cosmetics: Dictionary) -> void:
	if pack_variant or _decal_roots.is_empty():
		return
	var decal_id := RIDER_GRAPHICS_CATALOG.sanitize_field(
		&"decal_id", cosmetics.get(&"decal_id", &"CLEAN")
	)
	for root: Node3D in _decal_roots.values():
		root.visible = root == _decal_roots.get(decal_id)

	var sponsor := RIDER_GRAPHICS_CATALOG.sponsor(cosmetics.get(&"sponsor_id", &"NONE"))
	var sponsor_id := StringName(sponsor.get(&"sponsor_id", &"NONE"))
	var placement := RIDER_GRAPHICS_CATALOG.sanitize_field(
		&"sponsor_placement", cosmetics.get(&"sponsor_placement", &"SHROUDS")
	)
	var has_sponsor := sponsor_id != &"NONE"
	for placement_id: StringName in _sponsor_roots:
		_sponsor_roots[placement_id].visible = has_sponsor and (
			placement == placement_id or placement == &"FULL_KIT"
		)
	var sponsor_color := Color.from_string("#" + str(sponsor.get(&"color", "FFFFFF")), Color.WHITE)
	var mark := str(sponsor.get(&"short_mark", ""))
	for label: Label3D in _sponsor_labels:
		label.text = mark
		label.modulate = sponsor_color


func _visible_graphics_mesh_count() -> int:
	var count := 0
	for root: Node3D in _decal_roots.values():
		if not root.visible:
			continue
		for child: Node in root.get_children():
			if child is MeshInstance3D and (child as MeshInstance3D).visible:
				count += 1
	return count


func _visible_sponsor_mark_count() -> int:
	var count := 0
	for label: Label3D in _sponsor_labels:
		if label.is_visible_in_tree() and not label.text.is_empty():
			count += 1
	return count


func _build_dust(include_player_feedback: bool = true) -> void:
	_dust = _create_dust_emitter(&"HAZE")
	_dust.name = "TrailDust"
	_dust.position = Vector3(0.0, -0.25, 0.882591)
	add_child(_dust)

	_roost = _create_dust_emitter(&"ROOST")
	_roost.name = "RearRoost"
	_roost.position = Vector3(0.0, -0.3, 0.882591)
	add_child(_roost)

	_clods = _create_dust_emitter(&"CLODS")
	_clods.name = "DirtClods"
	_clods.position = Vector3(0.0, -0.3, 0.882591)
	add_child(_clods)

	_landing_dust = _create_dust_emitter(&"LANDING")
	_landing_dust.name = "LandingDust"
	_landing_dust.position = Vector3(0.0, -0.35, 0.0)
	add_child(_landing_dust)

	if include_player_feedback:
		_boost_trail = _create_boost_emitter(false)
		_boost_trail.position = Vector3(0.0, 0.15, 0.903486)
		add_child(_boost_trail)
		_boost_burst = _create_boost_emitter(true)
		_boost_burst.position = Vector3(0.0, 0.2, 0.659709)
		add_child(_boost_burst)
		_build_skid_pool()
	set_surface(&"PACKED")


func _build_pack_dust() -> void:
	# A full gate previously allocated four separate GPU systems per opponent.
	# Two layered emitters retain continuous haze, roost and landing punches while
	# halving pack particle systems and their renderer/update overhead. The clod
	# and landing aliases intentionally reuse the short-lived roost system.
	_dust = _create_dust_emitter(&"HAZE")
	_dust.name = "TrailDust"
	_dust.position = Vector3(0.0, -0.25, 0.882591)
	add_child(_dust)
	_roost = _create_dust_emitter(&"ROOST")
	_roost.name = "RearRoost"
	_roost.position = Vector3(0.0, -0.3, 0.882591)
	add_child(_roost)
	_clods = _roost
	_landing_dust = _roost
	set_surface(&"PACKED")
	set_pack_effects_enabled(false)


func set_pack_effects_enabled(enabled: bool) -> void:
	## RacePack enables only the four nearest opponents, matching its spatial
	## engine-audio pool. Hidden emitters retain their resources but submit no
	## transparent draw work and do not simulate off-camera roost.
	if not pack_variant:
		return
	for particles: GPUParticles3D in [_dust, _roost]:
		if particles == null:
			continue
		particles.visible = enabled
		if not enabled:
			particles.emitting = false


func _apply_pack_render_budget() -> void:
	# Dozens of articulated parts produced dozens of cascade submissions per
	# opponent. Visible meshes now skip the shadow pass and one shared coarse
	# silhouette preserves contact with the ground at one shadow draw per bike.
	for raw_geometry: Node in find_children("*", "GeometryInstance3D", true, false):
		var geometry := raw_geometry as GeometryInstance3D
		if geometry != null:
			geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_build_pack_shadow_proxy()


func _build_pack_shadow_proxy() -> void:
	if _shared_pack_shadow_mesh == null:
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		var chassis := BoxMesh.new()
		chassis.size = Vector3(0.62, 0.56, 1.75)
		tool.append_from(chassis, 0, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.28, 0.12)))
		var rider := BoxMesh.new()
		rider.size = Vector3(0.58, 1.15, 0.62)
		tool.append_from(rider, 0, Transform3D(Basis.from_euler(Vector3(-0.16, 0.0, 0.0)), Vector3(0.0, 1.08, 0.0)))
		_shared_pack_shadow_mesh = tool.commit()
	var proxy := MeshInstance3D.new()
	proxy.name = "PackShadowProxy"
	proxy.mesh = _shared_pack_shadow_mesh
	proxy.material_override = _materials[&"rubber"]
	proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	add_child(proxy)


func _add_number_label(parent: Node3D, position: Vector3, rotation: Vector3, pixel_size: float) -> void:
	var label := Label3D.new()
	label.name = "RiderNumber"
	label.text = "17"
	label.font_size = 96
	label.outline_size = 12
	label.pixel_size = pixel_size
	label.position = position
	label.rotation = rotation
	label.modulate = Color("10151b")
	label.outline_modulate = Color(1.0, 1.0, 1.0, 0.24)
	label.no_depth_test = false
	parent.add_child(label)
	_number_labels.append(label)


func _create_dust_emitter(effect: StringName) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	var web_build := OS.has_feature("web")
	var one_shot := effect == &"LANDING"
	match effect:
		&"HAZE":
			particles.amount = (10 if web_build else 16) if pack_variant else (28 if web_build else 44)
			particles.lifetime = 1.08
		&"ROOST":
			particles.amount = (12 if web_build else 20) if pack_variant else (34 if web_build else 58)
			particles.lifetime = 0.72
		&"CLODS":
			particles.amount = (7 if web_build else 11) if pack_variant else (18 if web_build else 28)
			particles.lifetime = 0.66
		_:
			particles.amount = (14 if web_build else 22) if pack_variant else (40 if web_build else 64)
			particles.lifetime = 0.78
	particles.one_shot = one_shot
	particles.local_coords = false
	particles.explosiveness = 0.92 if one_shot else (0.2 if effect == &"ROOST" else 0.12)
	particles.fixed_fps = 30
	particles.interpolate = true
	particles.visibility_aabb = AABB(Vector3(-7.0, -3.0, -7.0), Vector3(14.0, 10.0, 16.0))

	var process_material := ParticleProcessMaterial.new()
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process_material.emission_box_extents = Vector3(0.2, 0.06, 0.12)
	match effect:
		&"HAZE":
			process_material.direction = Vector3(0.0, 0.42, 1.0)
			process_material.spread = 58.0
			process_material.initial_velocity_min = 0.9
			process_material.initial_velocity_max = 3.1
			process_material.gravity = Vector3(0.0, -0.75, 0.0)
			process_material.scale_min = 0.34
			process_material.scale_max = 1.0
		&"ROOST":
			process_material.direction = Vector3(0.0, 0.48, 1.0)
			process_material.spread = 30.0
			process_material.initial_velocity_min = 3.6
			process_material.initial_velocity_max = 8.4
			process_material.gravity = Vector3(0.0, -7.0, 0.0)
			process_material.scale_min = 0.24
			process_material.scale_max = 0.62
		&"CLODS":
			process_material.direction = Vector3(0.0, 0.62, 1.0)
			process_material.spread = 38.0
			process_material.initial_velocity_min = 3.2
			process_material.initial_velocity_max = 7.2
			process_material.gravity = Vector3(0.0, -11.0, 0.0)
			process_material.scale_min = 0.65
			process_material.scale_max = 1.55
		_:
			process_material.direction = Vector3(0.0, 0.82, 0.35)
			process_material.spread = 68.0
			process_material.initial_velocity_min = 2.4
			process_material.initial_velocity_max = 6.8
			process_material.gravity = Vector3(0.0, -4.5, 0.0)
			process_material.scale_min = 0.4
			process_material.scale_max = 1.2
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 0.94))
	gradient.add_point(0.62, Color(1.0, 1.0, 1.0, 0.52))
	gradient.set_color(gradient.get_point_count() - 1, Color(1.0, 1.0, 1.0, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	process_material.color_ramp = ramp
	particles.process_material = process_material
	particles.draw_pass_1 = _create_clod_mesh() if effect == &"CLODS" else _create_soft_particle_mesh(0.24 if effect == &"ROOST" else 0.52)
	particles.emitting = false
	return particles


func _create_soft_particle_mesh(size: float) -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * size
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = _get_soft_particle_texture()
	material.roughness = 1.0
	quad.material = material
	return quad


func _create_clod_mesh() -> SphereMesh:
	var clod := SphereMesh.new()
	clod.radius = 0.075
	clod.height = 0.12
	clod.radial_segments = 6
	clod.rings = 3
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color.WHITE
	material.roughness = 1.0
	clod.material = material
	return clod


func _get_soft_particle_texture() -> Texture2D:
	if _soft_particle_texture != null:
		return _soft_particle_texture
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y: int in 16:
		for x: int in 16:
			var uv := (Vector2(float(x), float(y)) + Vector2(0.5, 0.5)) / 16.0
			var distance_from_center := (uv - Vector2(0.5, 0.5)).length() * 2.0
			var alpha := pow(clampf(1.0 - distance_from_center, 0.0, 1.0), 1.7)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	_soft_particle_texture = ImageTexture.create_from_image(image)
	return _soft_particle_texture


func _set_dirt_emitter_transform(point: Vector3, normal: Vector3, forward: Vector3) -> void:
	for particles: GPUParticles3D in [_dust, _roost, _clods]:
		_set_particle_transform(particles, point, normal, forward)


func _set_particle_transform(
	particles: GPUParticles3D,
	point: Vector3,
	normal: Vector3,
	forward: Vector3
) -> void:
	var safe_normal := normal.normalized() if normal.length_squared() > 0.2 else Vector3.UP
	var tangent_forward := forward.slide(safe_normal)
	if tangent_forward.length_squared() < 0.2:
		tangent_forward = -global_transform.basis.z.slide(safe_normal)
	if tangent_forward.length_squared() < 0.2:
		tangent_forward = Vector3.FORWARD
	var basis := Basis.looking_at(tangent_forward.normalized(), safe_normal).orthonormalized()
	particles.global_transform = Transform3D(basis, point + safe_normal * 0.055)


func _update_dirt_intensity(dust_amount: float, roost_intensity: float, surface: StringName) -> void:
	_set_particle_color(_dust, clampf(dust_amount * 0.46, 0.0, 0.46))
	_set_particle_color(_roost, clampf(0.42 + roost_intensity * 0.42, 0.0, 0.9))
	var haze_material := _dust.process_material as ParticleProcessMaterial
	haze_material.initial_velocity_max = 2.0 + dust_amount * 2.6
	var roost_material := _roost.process_material as ParticleProcessMaterial
	roost_material.initial_velocity_min = 2.8 + roost_intensity * 1.8
	roost_material.initial_velocity_max = 5.8 + roost_intensity * 4.8
	if pack_variant:
		roost_material.gravity = Vector3(0.0, -7.0 if surface == &"MUD" else -5.5, 0.0)
		return
	_set_particle_color(_clods, clampf(0.72 + roost_intensity * 0.22, 0.0, 1.0))
	var clod_material := _clods.process_material as ParticleProcessMaterial
	clod_material.initial_velocity_max = 5.5 + roost_intensity * 3.5
	if surface == &"MUD":
		clod_material.gravity = Vector3(0.0, -13.0, 0.0)
	else:
		clod_material.gravity = Vector3(0.0, -10.0, 0.0)


func _set_particle_color(particles: GPUParticles3D, alpha: float) -> void:
	if particles == null:
		return
	var process_material := particles.process_material as ParticleProcessMaterial
	if process_material == null:
		return
	process_material.color = Color(_surface_tint.r, _surface_tint.g, _surface_tint.b, clampf(alpha, 0.0, 1.0))


func _create_boost_emitter(one_shot: bool) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "BoostBurst" if one_shot else "BoostTrail"
	particles.amount = 42 if one_shot else 24
	particles.lifetime = 0.48 if one_shot else 0.34
	particles.one_shot = one_shot
	particles.local_coords = false
	particles.explosiveness = 0.92 if one_shot else 0.18
	particles.visibility_aabb = AABB(Vector3(-5.0, -3.0, -5.0), Vector3(10.0, 8.0, 14.0))
	var process_material := ParticleProcessMaterial.new()
	process_material.direction = Vector3(0.0, 0.15, 1.0)
	process_material.spread = 20.0
	process_material.initial_velocity_min = 5.0
	process_material.initial_velocity_max = 10.0 if one_shot else 7.0
	process_material.gravity = Vector3(0.0, 0.35, 0.0)
	process_material.scale_min = 0.06
	process_material.scale_max = 0.18
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.34, 0.84, 1.0, 0.9))
	gradient.add_point(0.55, Color(1.0, 0.58, 0.12, 0.62))
	gradient.set_color(gradient.get_point_count() - 1, Color(1.0, 0.3, 0.05, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	process_material.color_ramp = ramp
	particles.process_material = process_material
	var streak := BoxMesh.new()
	streak.size = Vector3(0.045, 0.045, 0.72)
	var streak_material := StandardMaterial3D.new()
	streak_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	streak_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	streak_material.albedo_color = Color(0.34, 0.84, 1.0, 0.76)
	streak.material = streak_material
	particles.draw_pass_1 = streak
	particles.emitting = false
	return particles


func _build_skid_pool() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.055, 0.045, 0.04, 0.62)
	material.roughness = 1.0
	for index: int in 36:
		var strip := BoxMesh.new()
		strip.size = Vector3(0.18, 0.012, 1.15)
		var mark := MeshInstance3D.new()
		mark.name = "SkidMark%02d" % index
		mark.mesh = strip
		mark.material_override = material
		mark.visible = false
		get_tree().current_scene.add_child.call_deferred(mark)
		_skid_marks.append(mark)


func _drop_skid_mark(point: Vector3, normal: Vector3, forward: Vector3) -> void:
	if _skid_marks.is_empty():
		return
	var mark := _skid_marks[_skid_index]
	_skid_index = (_skid_index + 1) % _skid_marks.size()
	if not mark.is_inside_tree():
		return
	var safe_normal := normal.normalized() if normal.length_squared() > 0.2 else Vector3.UP
	var tangent_forward := forward.slide(safe_normal)
	if tangent_forward.length_squared() < 0.2:
		tangent_forward = -global_transform.basis.z.slide(safe_normal)
	var basis := Basis.looking_at(tangent_forward.normalized(), safe_normal).orthonormalized()
	mark.global_transform = Transform3D(basis, point + safe_normal * 0.012)
	mark.visible = true


func _add_wheel(parent: Node3D, rear: bool) -> void:
	var wheel_parts: Dictionary = {}
	_batch_torus(wheel_parts, &"rubber", 0.245, 0.37, Vector3.ZERO, Vector3(0.0, 0.0, PI * 0.5), 24, 12)
	# Three staggered rows of baked knobs read clearly from the chase camera
	# without creating dozens of individual draw calls.
	var knob := BoxMesh.new()
	knob.size = Vector3(0.085, 0.06, 0.115)
	for knob_index: int in 24:
		for row_index: int in 3:
			var angle := TAU * float(knob_index) / 24.0 + (float(row_index) - 1.0) * 0.055
			var x_offset := (float(row_index) - 1.0) * 0.105
			var radial := Vector3(0.0, cos(angle), sin(angle)) * 0.372
			var basis := Basis(Vector3.RIGHT, angle)
			_batch_mesh(wheel_parts, &"rubber", knob, Transform3D(basis, radial + Vector3.RIGHT * x_offset))

	_batch_torus(wheel_parts, &"metal", 0.202, 0.232, Vector3.ZERO, Vector3(0.0, 0.0, PI * 0.5), 24, 7)
	var spoke := CylinderMesh.new()
	spoke.height = 0.22
	spoke.top_radius = 0.008
	spoke.bottom_radius = 0.008
	spoke.radial_segments = 6
	for spoke_index: int in 14:
		for side: float in [-1.0, 1.0]:
			var angle := TAU * float(spoke_index) / 14.0 + side * 0.07
			var spoke_position := Vector3(side * 0.055, cos(angle) * 0.145, sin(angle) * 0.145)
			_batch_mesh(wheel_parts, &"metal", spoke, Transform3D(Basis(Vector3.RIGHT, angle), spoke_position))
	_batch_cylinder(wheel_parts, &"metal", 0.083, 0.22, Vector3.ZERO, Vector3(0.0, 0.0, PI * 0.5), 14)
	_batch_cylinder(wheel_parts, &"metal", 0.032, 0.34, Vector3.ZERO, Vector3(0.0, 0.0, PI * 0.5), 10)
	_batch_torus(wheel_parts, &"metal", 0.125, 0.185, Vector3(-0.12, 0.0, 0.0), Vector3(0.0, 0.0, PI * 0.5), 20, 5)
	if rear:
		_batch_torus(wheel_parts, &"metal", 0.115, 0.172, Vector3(0.12, 0.0, 0.0), Vector3(0.0, 0.0, PI * 0.5), 18, 5)
		var tooth := BoxMesh.new()
		tooth.size = Vector3(0.025, 0.025, 0.06)
		for tooth_index: int in 14:
			var angle := TAU * float(tooth_index) / 14.0
			var tooth_position := Vector3(0.12, cos(angle) * 0.173, sin(angle) * 0.173)
			_batch_mesh(wheel_parts, &"metal", tooth, Transform3D(Basis(Vector3.RIGHT, angle), tooth_position))
	_commit_mesh_batch("RearWheelDetail" if rear else "FrontWheelDetail", wheel_parts, parent)


func _build_rider_limb_multimeshes() -> void:
	var arm_mesh := CylinderMesh.new()
	arm_mesh.height = 1.0
	arm_mesh.top_radius = 1.0
	arm_mesh.bottom_radius = 1.0
	arm_mesh.radial_segments = 8
	arm_mesh.material = _materials[&"jersey"]
	_arm_multimesh = MultiMesh.new()
	_arm_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_arm_multimesh.mesh = arm_mesh
	_arm_multimesh.instance_count = 6
	var arms := MultiMeshInstance3D.new()
	arms.name = "ArticulatedArms"
	arms.multimesh = _arm_multimesh
	_rider_root.add_child(arms)

	var glove_mesh := CylinderMesh.new()
	glove_mesh.height = 1.0
	glove_mesh.top_radius = 1.0
	glove_mesh.bottom_radius = 1.0
	glove_mesh.radial_segments = 8
	glove_mesh.material = _materials[&"gloves"]
	_glove_multimesh = MultiMesh.new()
	_glove_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_glove_multimesh.mesh = glove_mesh
	_glove_multimesh.instance_count = 2
	var gloves := MultiMeshInstance3D.new()
	gloves.name = "ArticulatedGloves"
	gloves.multimesh = _glove_multimesh
	_rider_root.add_child(gloves)

	var leg_mesh := CylinderMesh.new()
	leg_mesh.height = 1.0
	leg_mesh.top_radius = 1.0
	leg_mesh.bottom_radius = 1.0
	leg_mesh.radial_segments = 8
	leg_mesh.material = _materials[&"denim"]
	_leg_multimesh = MultiMesh.new()
	_leg_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_leg_multimesh.mesh = leg_mesh
	_leg_multimesh.instance_count = 8
	var legs := MultiMeshInstance3D.new()
	legs.name = "ArticulatedLegs"
	legs.multimesh = _leg_multimesh
	_rider_root.add_child(legs)

	var boot_mesh := CylinderMesh.new()
	boot_mesh.height = 1.0
	boot_mesh.top_radius = 1.0
	boot_mesh.bottom_radius = 1.0
	boot_mesh.radial_segments = 8
	boot_mesh.material = _materials[&"boots"]
	_boot_multimesh = MultiMesh.new()
	_boot_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_boot_multimesh.mesh = boot_mesh
	_boot_multimesh.instance_count = 2
	var boots := MultiMeshInstance3D.new()
	boots.name = "ArticulatedBoots"
	boots.multimesh = _boot_multimesh
	_rider_root.add_child(boots)


func _update_suspension_geometry(front_wheel_y: float, rear_wheel_y: float) -> void:
	if _front_lower_fork_root == null or _rear_linkage_root == null or _rear_shock_root == null:
		return
	var front_axle := Vector3(0.0, front_wheel_y - _front_assembly.position.y, -0.292532)
	_front_wheel_pivot.position.y = front_axle.y
	_set_scaled_segment_root(_front_lower_fork_root, Vector3(0.0, -0.24, -0.146266), front_axle)
	var rear_axle := Vector3(0.0, rear_wheel_y, 0.74329)
	_set_scaled_segment_root(_rear_linkage_root, Vector3(0.0, 0.1, 0.318422), rear_axle)
	_set_scaled_segment_root(_rear_shock_root, Vector3(0.0, 0.53, 0.297527), Vector3(0.0, rear_wheel_y + 0.18, 0.673639))


func _update_rider_limbs(steer: float, lean: float, boosting: bool) -> void:
	if _arm_multimesh == null or _glove_multimesh == null or _leg_multimesh == null or _boot_multimesh == null:
		return
	var attack := 0.065 if boosting else 0.0
	var lean_shift := clampf(lean, -1.0, 1.0) * 0.035
	var torso_transform := _rider_torso_root.transform
	var left_hand := _rider_root.to_local(_left_grip_anchor.global_position)
	var right_hand := _rider_root.to_local(_right_grip_anchor.global_position)
	var left_foot := _rider_root.to_local(_left_foot_anchor.global_position)
	var right_foot := _rider_root.to_local(_right_foot_anchor.global_position)
	var neutral_left_hand := left_hand
	var neutral_right_hand := right_hand
	var neutral_left_foot := left_foot
	var neutral_right_foot := right_foot
	var pose_weight := _trick_pose_blend * _trick_pose_strength
	match _active_trick_pose:
		&"NO_HANDER":
			left_hand = left_hand.lerp(Vector3(-0.46, 1.48, 0.04), pose_weight)
			right_hand = right_hand.lerp(Vector3(0.46, 1.48, 0.04), pose_weight)
		&"SEAT_GRAB":
			right_hand = right_hand.lerp(Vector3(0.13, 0.82, 0.52), pose_weight)
		&"SUPERMAN":
			left_foot = left_foot.lerp(Vector3(-0.29, 0.49, 1.12), pose_weight)
			right_foot = right_foot.lerp(Vector3(0.29, 0.49, 1.12), pose_weight)
		&"CAN_CAN_LEFT":
			right_foot = right_foot.lerp(Vector3(-0.46, 0.43, 0.52), pose_weight)
		&"CAN_CAN_RIGHT":
			left_foot = left_foot.lerp(Vector3(0.46, 0.43, 0.52), pose_weight)

	var left_shoulder := torso_transform * Vector3(-0.245, 1.29 - attack, -0.015 - attack + lean_shift)
	var right_shoulder := torso_transform * Vector3(0.245, 1.29 - attack, -0.015 - attack + lean_shift)
	var left_elbow := left_shoulder.lerp(left_hand, 0.52) + Vector3(-0.11, 0.055, 0.035 + steer * 0.015)
	var right_elbow := right_shoulder.lerp(right_hand, 0.52) + Vector3(0.11, 0.055, 0.035 - steer * 0.015)
	_arm_multimesh.set_instance_transform(0, _segment_transform(left_shoulder, left_elbow, 0.087))
	_arm_multimesh.set_instance_transform(1, _segment_transform(left_elbow, left_hand, 0.072))
	_arm_multimesh.set_instance_transform(2, _segment_transform(right_shoulder, right_elbow, 0.087))
	_arm_multimesh.set_instance_transform(3, _segment_transform(right_elbow, right_hand, 0.072))
	_arm_multimesh.set_instance_transform(4, _segment_transform(left_shoulder + Vector3(0.0, -0.055, 0.0), left_shoulder + Vector3(0.0, 0.055, 0.0), 0.12))
	_arm_multimesh.set_instance_transform(5, _segment_transform(right_shoulder + Vector3(0.0, -0.055, 0.0), right_shoulder + Vector3(0.0, 0.055, 0.0), 0.12))
	_glove_multimesh.set_instance_transform(0, _segment_transform(left_hand + Vector3(-0.045, 0.0, 0.0), left_hand + Vector3(0.035, 0.0, 0.0), 0.1))
	_glove_multimesh.set_instance_transform(1, _segment_transform(right_hand + Vector3(-0.035, 0.0, 0.0), right_hand + Vector3(0.045, 0.0, 0.0), 0.1))

	_trick_limb_targets = {
		&"pose_id": _active_trick_pose,
		&"blend": _trick_pose_blend,
		&"strength": _trick_pose_strength,
		&"left_hand": left_hand,
		&"right_hand": right_hand,
		&"left_foot": left_foot,
		&"right_foot": right_foot,
		&"left_hand_displacement": left_hand.distance_to(neutral_left_hand),
		&"right_hand_displacement": right_hand.distance_to(neutral_right_hand),
		&"left_foot_displacement": left_foot.distance_to(neutral_left_foot),
		&"right_foot_displacement": right_foot.distance_to(neutral_right_foot),
	}
	var left_hip := torso_transform * Vector3(-0.19, 0.76 - attack * 0.45, 0.3 + attack * 0.3)
	var right_hip := torso_transform * Vector3(0.19, 0.76 - attack * 0.45, 0.3 + attack * 0.3)
	var left_knee := left_hip.lerp(left_foot, 0.52) + Vector3(-0.105, -0.025, -0.055)
	var right_knee := right_hip.lerp(right_foot, 0.52) + Vector3(0.105, -0.025, -0.055)
	_leg_multimesh.set_instance_transform(0, _segment_transform(left_hip, left_knee, 0.12))
	_leg_multimesh.set_instance_transform(1, _segment_transform(left_knee, left_foot, 0.1))
	_leg_multimesh.set_instance_transform(2, _segment_transform(right_hip, right_knee, 0.12))
	_leg_multimesh.set_instance_transform(3, _segment_transform(right_knee, right_foot, 0.1))
	_leg_multimesh.set_instance_transform(4, _segment_transform(left_knee + Vector3(0.0, -0.08, -0.015), left_knee + Vector3(0.0, 0.08, -0.015), 0.135))
	_leg_multimesh.set_instance_transform(5, _segment_transform(right_knee + Vector3(0.0, -0.08, -0.015), right_knee + Vector3(0.0, 0.08, -0.015), 0.135))
	_leg_multimesh.set_instance_transform(6, _segment_transform(left_hip + Vector3(0.0, -0.055, 0.0), left_hip + Vector3(0.0, 0.055, 0.0), 0.13))
	_leg_multimesh.set_instance_transform(7, _segment_transform(right_hip + Vector3(0.0, -0.055, 0.0), right_hip + Vector3(0.0, 0.055, 0.0), 0.13))
	_boot_multimesh.set_instance_transform(0, _segment_transform(left_foot + Vector3(0.0, 0.09, -0.11), left_foot + Vector3(0.0, -0.065, 0.11), 0.135))
	_boot_multimesh.set_instance_transform(1, _segment_transform(right_foot + Vector3(0.0, 0.09, -0.11), right_foot + Vector3(0.0, -0.065, 0.11), 0.135))


func get_trick_animation_snapshot() -> Dictionary:
	return _trick_limb_targets.duplicate(true)


func _update_trick_pose_state(trick_pose: Dictionary, delta: float) -> void:
	var requested_pose := StringName(trick_pose.get(&"pose_id", &"NONE"))
	var requested_strength := clampf(float(trick_pose.get(&"strength", 0.0)), 0.0, 1.0)
	var response := animation_response_weight(11.5, delta)
	if requested_pose != &"NONE":
		if requested_pose != _active_trick_pose:
			_active_trick_pose = requested_pose
			_trick_pose_blend = minf(_trick_pose_blend, 0.32)
		_trick_pose_strength = lerpf(_trick_pose_strength, requested_strength, response)
		_trick_pose_side = float(trick_pose.get(&"side", 0.0))
		_trick_pose_blend = lerpf(_trick_pose_blend, 1.0, response)
	else:
		_trick_pose_blend = lerpf(_trick_pose_blend, 0.0, response)
		_trick_pose_strength = lerpf(_trick_pose_strength, 0.0, response)
		if _trick_pose_blend <= 0.015:
			_active_trick_pose = &"NONE"
			_trick_pose_blend = 0.0
			_trick_pose_strength = 0.0
			_trick_pose_side = 0.0


func _set_scaled_segment_root(root: Node3D, start: Vector3, end: Vector3) -> void:
	var direction := end - start
	if direction.length_squared() < 0.0001:
		return
	var basis := Basis.looking_at(direction.normalized(), Vector3.UP)
	root.transform = Transform3D(basis * Basis.from_scale(Vector3(1.0, 1.0, direction.length())), start)


func _segment_transform(start: Vector3, end: Vector3, radius: float) -> Transform3D:
	var direction := end - start
	if direction.length_squared() < 0.0001:
		return Transform3D(Basis.from_scale(Vector3.ONE * 0.001), start)
	var rotation_basis := Basis(Quaternion(Vector3.UP, direction.normalized()))
	var scaled_basis := rotation_basis * Basis.from_scale(Vector3(radius, direction.length(), radius))
	return Transform3D(scaled_basis, (start + end) * 0.5)


func _batch_mesh(parts: Dictionary, material_key: StringName, mesh: Mesh, transform: Transform3D) -> void:
	if not parts.has(material_key):
		parts[material_key] = []
	var material_parts: Array = parts[material_key]
	material_parts.append({&"mesh": mesh, &"transform": transform})
	parts[material_key] = material_parts


func _batch_box(parts: Dictionary, material_key: StringName, size: Vector3, position: Vector3, rotation: Vector3 = Vector3.ZERO) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_batch_mesh(parts, material_key, mesh, Transform3D(Basis.from_euler(rotation), position))


func _batch_tapered_box(
	parts: Dictionary,
	material_key: StringName,
	front_width: float,
	back_width: float,
	height: float,
	length: float,
	position: Vector3,
	rotation: Vector3 = Vector3.ZERO
) -> void:
	var front_z := -length * 0.5
	var back_z := length * 0.5
	var bottom := -height * 0.5
	var top := height * 0.5
	var points := PackedVector3Array([
		Vector3(-front_width * 0.5, top, front_z), Vector3(front_width * 0.5, top, front_z),
		Vector3(-back_width * 0.5, top, back_z), Vector3(back_width * 0.5, top, back_z),
		Vector3(-front_width * 0.5, bottom, front_z), Vector3(front_width * 0.5, bottom, front_z),
		Vector3(-back_width * 0.5, bottom, back_z), Vector3(back_width * 0.5, bottom, back_z),
	])
	var faces := PackedInt32Array([
		0, 3, 2, 0, 1, 3,
		4, 7, 5, 4, 6, 7,
		0, 5, 1, 0, 4, 5,
		2, 7, 6, 2, 3, 7,
		0, 6, 4, 0, 2, 6,
		1, 7, 3, 1, 5, 7,
	])
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for point_index: int in faces:
		surface_tool.add_vertex(points[point_index])
	surface_tool.generate_normals()
	var mesh := surface_tool.commit()
	_batch_mesh(parts, material_key, mesh, Transform3D(Basis.from_euler(rotation), position))


func _batch_sphere(parts: Dictionary, material_key: StringName, radius: float, position: Vector3, scale_value: Vector3 = Vector3.ONE) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 14
	mesh.rings = 8
	_batch_mesh(parts, material_key, mesh, Transform3D(Basis.from_scale(scale_value), position))


func _batch_capsule(
	parts: Dictionary,
	material_key: StringName,
	radius: float,
	height: float,
	position: Vector3,
	rotation: Vector3 = Vector3.ZERO,
	scale_value: Vector3 = Vector3.ONE
) -> void:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 14
	mesh.rings = 6
	var basis := Basis.from_euler(rotation) * Basis.from_scale(scale_value)
	_batch_mesh(parts, material_key, mesh, Transform3D(basis, position))


func _batch_cylinder(
	parts: Dictionary,
	material_key: StringName,
	radius: float,
	height: float,
	position: Vector3,
	rotation: Vector3 = Vector3.ZERO,
	radial_segments: int = 10
) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = radial_segments
	_batch_mesh(parts, material_key, mesh, Transform3D(Basis.from_euler(rotation), position))


func _batch_cylinder_between(parts: Dictionary, material_key: StringName, start: Vector3, end: Vector3, radius: float) -> void:
	var direction := end - start
	if direction.length_squared() < 0.0001:
		return
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = direction.length()
	mesh.radial_segments = 9
	var basis := Basis(Quaternion(Vector3.UP, direction.normalized()))
	_batch_mesh(parts, material_key, mesh, Transform3D(basis, (start + end) * 0.5))


func _batch_torus(
	parts: Dictionary,
	material_key: StringName,
	inner_radius: float,
	outer_radius: float,
	position: Vector3,
	rotation: Vector3,
	rings: int,
	ring_segments: int
) -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner_radius
	mesh.outer_radius = outer_radius
	mesh.rings = rings
	mesh.ring_segments = ring_segments
	_batch_mesh(parts, material_key, mesh, Transform3D(Basis.from_euler(rotation), position))


func _commit_mesh_batch(batch_name: String, parts: Dictionary, parent: Node3D) -> void:
	for material_variant: Variant in parts:
		var material_key := StringName(material_variant)
		var cache_key := "%s:%s" % [batch_name, String(material_key)]
		var combined_mesh: ArrayMesh = _shared_pack_meshes.get(cache_key) as ArrayMesh if pack_variant else null
		if combined_mesh == null:
			var surface_tool := SurfaceTool.new()
			surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
			var material_parts: Array = parts[material_variant]
			for part_variant: Variant in material_parts:
				var part: Dictionary = part_variant
				var source_mesh := part.get(&"mesh") as Mesh
				var part_transform: Transform3D = part.get(&"transform", Transform3D.IDENTITY)
				if source_mesh == null:
					continue
				for surface_index: int in source_mesh.get_surface_count():
					surface_tool.append_from(source_mesh, surface_index, part_transform)
			combined_mesh = surface_tool.commit()
			if pack_variant and combined_mesh != null:
				_shared_pack_meshes[cache_key] = combined_mesh
		if combined_mesh == null or combined_mesh.get_surface_count() == 0:
			continue
		var instance := MeshInstance3D.new()
		instance.name = "%s_%s" % [batch_name, String(material_key)]
		instance.mesh = combined_mesh
		instance.material_override = _materials.get(material_key) as Material
		parent.add_child(instance)


func _add_box(
	mesh_name: String,
	size: Vector3,
	position: Vector3,
	material_key: StringName,
	rotation: Vector3 = Vector3.ZERO,
	parent: Node3D = self
) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = mesh_name
	mesh_instance.mesh = box
	mesh_instance.position = position
	mesh_instance.rotation = rotation
	mesh_instance.material_override = _materials[material_key]
	parent.add_child(mesh_instance)
	return mesh_instance


func _add_sphere(
	mesh_name: String,
	radius: float,
	position: Vector3,
	material_key: StringName,
	parent: Node3D = self
) -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 12
	sphere.rings = 7
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = mesh_name
	mesh_instance.mesh = sphere
	mesh_instance.position = position
	mesh_instance.material_override = _materials[material_key]
	parent.add_child(mesh_instance)
	return mesh_instance


func _add_cylinder_between(
	mesh_name: String,
	start: Vector3,
	end: Vector3,
	radius: float,
	material_key: StringName,
	parent: Node3D = self
) -> MeshInstance3D:
	var direction := end - start
	var cylinder := CylinderMesh.new()
	cylinder.height = direction.length()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.radial_segments = 8
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = mesh_name
	mesh_instance.mesh = cylinder
	mesh_instance.position = (start + end) * 0.5
	mesh_instance.quaternion = Quaternion(Vector3.UP, direction.normalized())
	mesh_instance.material_override = _materials[material_key]
	parent.add_child(mesh_instance)
	return mesh_instance


func _material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = roughness
	result.metallic = metallic
	return result


func _overlay_material(color: Color) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.92
	result.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	result.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	result.render_priority = 1
	return result
