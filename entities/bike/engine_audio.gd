extends AudioStreamPlayer3D
class_name EngineAudio
## Shared cached engine and surface loops with lightweight runtime modulation.
##
## The previous implementation synthesized every PCM frame in GDScript for the
## player and four pooled opponent voices. These short, seamless WAV layers are
## rendered once per process and shared by every bike; runtime work is limited to
## virtual gearing, pitch, and volume updates.

const MIX_RATE: int = 22_050
const LOOP_SECONDS: float = 0.75
const ENGINE_BASE_HZ: float = 80.0
const SILENCE_DB: float = -80.0
const GEAR_RATIOS := [1.0, 0.78, 0.62, 0.5, 0.42]
const SURFACE_KEYS := [&"PACKED", &"MUD", &"GRAVEL", &"ROCK", &"LOOSE_DIRT"]
const DEFAULT_BIKE_CLASS: StringName = &"SPORT_250"
const TIMBRE_SMOOTHING_HZ: float = 5.8
const BAKED_ENGINE_LOOP: AudioStreamWAV = preload("res://assets/generated/audio/engine_engine.res")
const BAKED_SURFACE_LOOPS: Dictionary = {
	&"PACKED": preload("res://assets/generated/audio/engine_packed.res"),
	&"MUD": preload("res://assets/generated/audio/engine_mud.res"),
	&"GRAVEL": preload("res://assets/generated/audio/engine_gravel.res"),
	&"ROCK": preload("res://assets/generated/audio/engine_rock.res"),
	&"LOOSE_DIRT": preload("res://assets/generated/audio/engine_loose_dirt.res"),
}

# One shared phase-continuous loop remains cheap enough for the whole field.
# The player's selected displacement projects a different RPM span, pitch center,
# throttle bite and surface presence at runtime. All values are continuously
# smoothed, so changing class while a loop is playing cannot introduce a click.
const ENGINE_CLASS_PROFILES := {
	&"LITE_125": {
		&"displacement_cc": 125,
		&"pitch_bias": 1.18,
		&"rpm_span": 1.08,
		&"rpm_response_hz": 9.4,
		&"load_trim_db": -0.6,
		&"surface_mix": 0.90,
	},
	&"SPORT_250": {
		&"displacement_cc": 250,
		&"pitch_bias": 1.0,
		&"rpm_span": 1.0,
		&"rpm_response_hz": 7.5,
		&"load_trim_db": 0.0,
		&"surface_mix": 1.0,
	},
	&"OPEN": {
		&"displacement_cc": 450,
		&"pitch_bias": 0.82,
		&"rpm_span": 0.90,
		&"rpm_response_hz": 5.8,
		&"load_trim_db": 1.1,
		&"surface_mix": 1.12,
	},
}

static var _shared_engine_loop: AudioStreamWAV
static var _shared_surface_loops: Dictionary[StringName, AudioStreamWAV] = {}

var _surface_layer: AudioStreamPlayer3D
var _speed_mps: float = 0.0
var _throttle: float = 0.0
var _grounded: bool = true
var _surface: StringName = &"PACKED"
var _roughness: float = 0.35
var _rear_slip: float = 0.0
var _suspension_activity: float = 0.0
var _bus_assigned: bool = false
var _audio_enabled: bool = false
var _virtual_rpm: float = 0.12
var _gear: int = 1
var _shift_cut: float = 0.0
var _current_surface_key: StringName = &""
var _base_volume_db: float = -10.0
var _last_engine_volume_db: float = -10.0
var _configured_class: StringName = DEFAULT_BIKE_CLASS
var _class_pitch_bias: float = 1.0
var _class_rpm_span: float = 1.0
var _class_rpm_response_hz: float = 7.5
var _class_load_trim_db: float = 0.0
var _class_surface_mix: float = 1.0
var _target_pitch_bias: float = 1.0
var _target_rpm_span: float = 1.0
var _target_rpm_response_hz: float = 7.5
var _target_load_trim_db: float = 0.0
var _target_surface_mix: float = 1.0


func _ready() -> void:
	_snap_timbre_to_target()
	# A Dummy audio driver never reaches speakers and does not service playback
	# teardown like a real mixer. Avoid both wasted headless work and false-positive
	# playback retention in deterministic production soaks.
	if &"--smoke-test" in OS.get_cmdline_user_args() or AudioServer.get_driver_name() == "Dummy":
		set_process(false)
		return
	_audio_enabled = true
	_ensure_shared_loops()
	_configure_spatial_player(self)
	stream = _shared_engine_loop
	playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	volume_db = -10.0
	_base_volume_db = volume_db
	_last_engine_volume_db = volume_db

	_surface_layer = AudioStreamPlayer3D.new()
	_surface_layer.name = "EngineSurfaceLayer"
	_configure_spatial_player(_surface_layer)
	_surface_layer.stream = _shared_surface_loops[&"PACKED"]
	_surface_layer.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	_surface_layer.volume_db = SILENCE_DB
	add_child(_surface_layer)
	_current_surface_key = &"PACKED"
	_assign_sfx_bus()
	var loop_start := _loop_start_offset()
	play(loop_start)
	_surface_layer.play(loop_start)


func _process(delta: float) -> void:
	if not _audio_enabled or _surface_layer == null:
		return
	if not _bus_assigned:
		_assign_sfx_bus()
	_capture_external_volume()
	_update_class_timbre(delta)
	_update_virtual_gear()
	_shift_cut = maxf(_shift_cut - delta * 5.5, 0.0)
	var target_rpm := clampf(
		_speed_mps * float(GEAR_RATIOS[_gear - 1]) / 12.0 + _throttle * 0.22,
		0.1,
		1.0
	)
	if not _grounded:
		target_rpm = minf(target_rpm + _throttle * 0.16, 1.0)
	_virtual_rpm = lerpf(_virtual_rpm, target_rpm, 1.0 - exp(-_class_rpm_response_hz * delta))

	var frequency := (52.0 + _virtual_rpm * 148.0 * _class_rpm_span + _throttle * 18.0) * _class_pitch_bias
	pitch_scale = clampf(frequency / ENGINE_BASE_HZ, 0.6, 2.85)
	var load := clampf(0.12 + _throttle * 0.58 + _virtual_rpm * 0.3, 0.0, 1.0)
	var load_trim_db := lerpf(-3.5, 1.5, load) + _class_load_trim_db - _shift_cut * 3.2
	_last_engine_volume_db = (
		SILENCE_DB
		if _base_volume_db <= SILENCE_DB + 1.0
		else clampf(_base_volume_db + load_trim_db, SILENCE_DB, 4.0)
	)
	volume_db = _last_engine_volume_db

	_select_surface_loop(_normalized_surface(_surface))
	_surface_layer.pitch_scale = clampf(0.68 + _speed_mps / 28.0, 0.68, 1.9)
	var contact_gain := 0.0
	if _grounded:
		contact_gain = (
			0.008
			+ _virtual_rpm * 0.048
			+ _rear_slip * 0.065
			+ _suspension_activity * 0.06
		) * clampf(0.52 + _roughness * 0.7, 0.35, 1.45)
	var wind_gain := smoothstep(7.0, 32.0, _speed_mps) * 0.055
	var texture_mix := clampf((contact_gain * 3.2 + wind_gain * 2.2) * _class_surface_mix, 0.0001, 0.78)
	_surface_layer.volume_db = (
		SILENCE_DB
		if _base_volume_db <= SILENCE_DB + 1.0
		else clampf(_base_volume_db + linear_to_db(texture_mix), SILENCE_DB, 2.0)
	)


func configure_class(class_id: StringName) -> void:
	## Selects a deterministic 125/250/450 timbre projection. This API is safe
	## to call before or after _ready(); live changes glide instead of swapping PCM.
	_configured_class = normalize_class_id(class_id)
	var profile := get_class_timbre_contract(_configured_class)
	_target_pitch_bias = float(profile.get(&"pitch_bias", 1.0))
	_target_rpm_span = float(profile.get(&"rpm_span", 1.0))
	_target_rpm_response_hz = float(profile.get(&"rpm_response_hz", 7.5))
	_target_load_trim_db = float(profile.get(&"load_trim_db", 0.0))
	_target_surface_mix = float(profile.get(&"surface_mix", 1.0))


func get_timbre_snapshot() -> Dictionary:
	var contract := get_class_timbre_contract(_configured_class)
	return {
		&"class_id": _configured_class,
		&"contract_hash": StringName(contract.get(&"contract_hash", &"")),
		&"target_pitch_bias": _target_pitch_bias,
		&"target_rpm_span": _target_rpm_span,
		&"target_rpm_response_hz": _target_rpm_response_hz,
		&"target_load_trim_db": _target_load_trim_db,
		&"target_surface_mix": _target_surface_mix,
		&"transition_hz": TIMBRE_SMOOTHING_HZ,
	}


static func normalize_class_id(class_id: StringName) -> StringName:
	match String(class_id).to_upper():
		"125", "LITE", "LITE_125":
			return &"LITE_125"
		"450", "OPEN", "OPEN_450":
			return &"OPEN"
		_:
			return &"SPORT_250"


static func get_class_timbre_contract(class_id: StringName) -> Dictionary:
	var normalized := normalize_class_id(class_id)
	var contract := (ENGINE_CLASS_PROFILES[normalized] as Dictionary).duplicate(true)
	contract[&"class_id"] = normalized
	var canonical := "%s|%d|%.3f|%.3f|%.3f|%.3f|%.3f" % [
		String(normalized),
		int(contract.get(&"displacement_cc", 250)),
		float(contract.get(&"pitch_bias", 1.0)),
		float(contract.get(&"rpm_span", 1.0)),
		float(contract.get(&"rpm_response_hz", 7.5)),
		float(contract.get(&"load_trim_db", 0.0)),
		float(contract.get(&"surface_mix", 1.0)),
	]
	contract[&"contract_hash"] = StringName("%08x" % (canonical.hash() & 0xffffffff))
	return contract


func _update_class_timbre(delta: float) -> void:
	var blend := 1.0 - exp(-TIMBRE_SMOOTHING_HZ * maxf(delta, 0.0))
	_class_pitch_bias = lerpf(_class_pitch_bias, _target_pitch_bias, blend)
	_class_rpm_span = lerpf(_class_rpm_span, _target_rpm_span, blend)
	_class_rpm_response_hz = lerpf(_class_rpm_response_hz, _target_rpm_response_hz, blend)
	_class_load_trim_db = lerpf(_class_load_trim_db, _target_load_trim_db, blend)
	_class_surface_mix = lerpf(_class_surface_mix, _target_surface_mix, blend)


func _snap_timbre_to_target() -> void:
	_class_pitch_bias = _target_pitch_bias
	_class_rpm_span = _target_rpm_span
	_class_rpm_response_hz = _target_rpm_response_hz
	_class_load_trim_db = _target_load_trim_db
	_class_surface_mix = _target_surface_mix


func _update_virtual_gear() -> void:
	var next_gear := 1
	if _speed_mps >= 27.0:
		next_gear = 5
	elif _speed_mps >= 19.5:
		next_gear = 4
	elif _speed_mps >= 13.0:
		next_gear = 3
	elif _speed_mps >= 6.8:
		next_gear = 2
	if next_gear != _gear:
		_gear = next_gear
		_shift_cut = 1.0


func _capture_external_volume() -> void:
	# RacePack owns proximity attenuation through this node's volume_db. Preserve
	# that public contract while applying load modulation as a relative trim.
	if not is_equal_approx(volume_db, _last_engine_volume_db):
		_base_volume_db = volume_db


func _select_surface_loop(surface_key: StringName) -> void:
	if surface_key == _current_surface_key or _surface_layer == null:
		return
	var playback_position := _surface_layer.get_playback_position() if _surface_layer.playing else 0.0
	_surface_layer.stop()
	_surface_layer.stream = _shared_surface_loops[surface_key]
	_surface_layer.play(fmod(playback_position, LOOP_SECONDS))
	_current_surface_key = surface_key


func _normalized_surface(surface_key: StringName) -> StringName:
	return surface_key if surface_key in SURFACE_KEYS else &"PACKED"


func _configure_spatial_player(player: AudioStreamPlayer3D) -> void:
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
	player.unit_size = 18.0
	player.max_distance = 55.0


func _loop_start_offset() -> float:
	# Shared streams save memory; a stable per-node start prevents the player and
	# pooled rivals from phase-locking into a single comb-filtered engine voice.
	return float(posmod(String(name).hash(), 1000)) / 1000.0 * LOOP_SECONDS


func _exit_tree() -> void:
	shutdown()


func shutdown() -> void:
	set_process(false)
	_audio_enabled = false
	if _surface_layer != null and is_instance_valid(_surface_layer):
		_surface_layer.stop()
		_surface_layer.stream = null
	_surface_layer = null
	stop()
	stream = null
	_current_surface_key = &""


func set_engine_state(
	speed_mps: float,
	throttle: float,
	grounded: bool,
	surface: StringName = &"PACKED",
	roughness: float = 0.35,
	rear_slip: float = 0.0,
	suspension_activity: float = 0.0
) -> void:
	_speed_mps = speed_mps
	_throttle = throttle
	_grounded = grounded
	_surface = surface
	_roughness = roughness
	_rear_slip = rear_slip
	_suspension_activity = suspension_activity


func reset_surface_feedback() -> void:
	_speed_mps = 0.0
	_throttle = 0.0
	_rear_slip = 0.0
	_suspension_activity = 0.0
	_virtual_rpm = 0.12
	_gear = 1
	_shift_cut = 0.0
	if _surface_layer != null:
		_surface_layer.volume_db = SILENCE_DB


func _assign_sfx_bus() -> void:
	if AudioServer.get_bus_index(&"SFX") < 0:
		return
	bus = &"SFX"
	if _surface_layer != null:
		_surface_layer.bus = &"SFX"
	_bus_assigned = true


static func _ensure_shared_loops() -> void:
	if _shared_engine_loop != null and _shared_surface_loops.size() == SURFACE_KEYS.size():
		return
	_shared_engine_loop = BAKED_ENGINE_LOOP
	_shared_surface_loops.clear()
	for surface_key: StringName in SURFACE_KEYS:
		_shared_surface_loops[surface_key] = BAKED_SURFACE_LOOPS[surface_key] as AudioStreamWAV


static func build_baked_loop(layer: StringName) -> AudioStreamWAV:
	## Build-time entry point used by the audio asset baker. Runtime code loads the
	## resulting compressed resources instead of synthesizing PCM during startup.
	return _make_loop(layer)


static func _make_loop(layer: StringName) -> AudioStreamWAV:
	var sample_count := maxi(int(LOOP_SECONDS * float(MIX_RATE)), 1)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for sample_index: int in sample_count:
		var progress := float(sample_index) / float(sample_count)
		var sample := _engine_sample(progress) if layer == &"ENGINE" else _surface_sample(progress, layer)
		var signed_sample := clampi(roundi(sample * 32767.0), -32768, 32767)
		var encoded_sample := signed_sample if signed_sample >= 0 else 65536 + signed_sample
		data[sample_index * 2] = encoded_sample & 0xff
		data[sample_index * 2 + 1] = (encoded_sample >> 8) & 0xff
	var loop := AudioStreamWAV.new()
	loop.format = AudioStreamWAV.FORMAT_16_BITS
	loop.mix_rate = MIX_RATE
	loop.stereo = false
	loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
	loop.loop_begin = 0
	loop.loop_end = sample_count
	loop.data = data
	return loop


static func _engine_sample(progress: float) -> float:
	# 80 Hz * 0.75 seconds is exactly 60 cycles, so the loop boundary is phase
	# continuous even after runtime pitch modulation.
	var phase := progress * ENGINE_BASE_HZ * LOOP_SECONDS
	var wave := (
		sin(phase * TAU)
		+ sin(phase * TAU * 2.0) * 0.45
		+ sin(phase * TAU * 4.0) * 0.12
	)
	return tanh(wave * 0.72) * 0.5


static func _surface_sample(progress: float, surface_key: StringName) -> float:
	var seed := 17
	match surface_key:
		&"MUD":
			seed = 31
		&"GRAVEL":
			seed = 47
		&"ROCK":
			seed = 61
		&"LOOSE_DIRT":
			seed = 79
	var low_texture := _periodic_texture(progress, seed, 2)
	var high_texture := _periodic_texture(progress, seed + 37, 11)
	var tread_pulse := pow(maxf(sin(progress * TAU * 9.0), 0.0), 5.0)
	var wave := low_texture * 0.38 + high_texture * 0.08
	match surface_key:
		&"MUD":
			wave = low_texture * 0.72 + sin(progress * TAU * 4.0) * 0.24
		&"GRAVEL":
			wave = low_texture * 0.22 + high_texture * (0.22 + tread_pulse * 0.72)
		&"ROCK":
			wave = high_texture * (0.18 + tread_pulse * 0.9) + sin(progress * TAU * 18.0) * tread_pulse * 0.18
		&"LOOSE_DIRT":
			wave = low_texture * 0.66 + high_texture * 0.16
	return tanh(wave * 1.35) * 0.48


static func _periodic_texture(progress: float, seed: int, band_step: int) -> float:
	var value := 0.0
	var normalization := 0.0
	for index: int in 7:
		# Integer cycle counts keep every component seamless at the loop boundary.
		var cycles := 5 + posmod(seed * 3 + index * 11, 31) + index * band_step
		var phase_offset := deg_to_rad(float(posmod(seed * 97 + index * 53, 360)))
		var weight := 1.0 / (1.0 + float(index) * 0.34)
		value += sin(progress * TAU * float(cycles) + phase_offset) * weight
		normalization += weight
	return value / maxf(normalization, 0.001)
