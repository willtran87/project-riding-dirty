extends Node
class_name GameplayAudio
## Pooled feedback cues and deterministic district/session adaptive music.

const MIX_RATE := 22_050
const VOICE_COUNT := 5
const FLOW_DENIED_CUE_COOLDOWN_USEC := 280_000
const FLOW_DENIED_CUE_START_HZ := 420.0
const FLOW_DENIED_CUE_END_HZ := 155.0
const FLOW_DENIED_CUE_DURATION := 0.16
const FLOW_DENIED_CUE_VOLUME_DB := -3.5
const INTERFACE_FEEDBACK_COOLDOWN_USEC := 32_000
const MUSIC_BUS_NAME: StringName = &"Music"
const SFX_BUS_NAME: StringName = &"SFX"
const ENGINE_BUS_NAME: StringName = &"Engine"
const MUSIC_BEATS := 16.0
const MUSIC_SILENCE_DB := -80.0
const MUSIC_CROSSFADE_SECONDS := 0.72
const CLOSE_BATTLE_GAP_M := 8.5
const CLOSE_BATTLE_ENTER_SAMPLES := 3
const CLOSE_BATTLE_EXIT_SAMPLES := 5
const MAX_CACHED_ARRANGEMENTS := 6
const BAKED_QUARRY_STANDARD_BASE: AudioStreamWAV = preload("res://assets/generated/audio/music_quarry_standard_base.wav")
const BAKED_QUARRY_STANDARD_DRIVE: AudioStreamWAV = preload("res://assets/generated/audio/music_quarry_standard_drive.wav")
const BAKED_QUARRY_STANDARD_TENSION: AudioStreamWAV = preload("res://assets/generated/audio/music_quarry_standard_tension.wav")
const BAKED_QUARRY_STANDARD_RESULTS: AudioStreamWAV = preload("res://assets/generated/audio/music_quarry_standard_results.wav")

const STATE_GARAGE: StringName = &"GARAGE"
const STATE_STAGING: StringName = &"STAGING"
const STATE_RACING: StringName = &"RACING"
const STATE_FINAL_LAP: StringName = &"FINAL_LAP"
const STATE_CLOSE_BATTLE: StringName = &"CLOSE_BATTLE"
const STATE_RESULTS: StringName = &"RESULTS"

const INTERFACE_FEEDBACK_CONTRACT := {
	&"NAVIGATE": {
		&"cue": &"ui_navigate", &"start_hz": 620.0, &"end_hz": 760.0,
		&"duration": 0.055, &"amplitude": 0.18, &"harmonic": 0.10,
		&"pitch": 1.0, &"volume_db": -7.0,
	},
	&"CONFIRM": {
		&"cue": &"ui_confirm", &"start_hz": 470.0, &"end_hz": 920.0,
		&"duration": 0.105, &"amplitude": 0.24, &"harmonic": 0.18,
		&"pitch": 1.0, &"volume_db": -4.0,
	},
	&"CANCEL": {
		&"cue": &"ui_cancel", &"start_hz": 480.0, &"end_hz": 260.0,
		&"duration": 0.090, &"amplitude": 0.20, &"harmonic": 0.12,
		&"pitch": 1.0, &"volume_db": -5.5,
	},
	&"DENIED": {
		&"cue": &"ui_denied", &"start_hz": 230.0, &"end_hz": 125.0,
		&"duration": 0.135, &"amplitude": 0.22, &"harmonic": 0.08,
		&"pitch": 1.0, &"volume_db": -4.5,
	},
}

const MUSIC_STEMS: Array[StringName] = [&"BASE", &"DRIVE", &"TENSION", &"RESULTS"]
const MUSIC_STATE_MIXES := {
	STATE_GARAGE: {&"BASE": -12.0, &"DRIVE": -16.0, &"TENSION": MUSIC_SILENCE_DB, &"RESULTS": MUSIC_SILENCE_DB},
	STATE_STAGING: {&"BASE": -15.0, &"DRIVE": -24.0, &"TENSION": -18.0, &"RESULTS": MUSIC_SILENCE_DB},
	STATE_RACING: {&"BASE": -10.5, &"DRIVE": -11.0, &"TENSION": -28.0, &"RESULTS": MUSIC_SILENCE_DB},
	STATE_FINAL_LAP: {&"BASE": -9.5, &"DRIVE": -4.0, &"TENSION": -6.0, &"RESULTS": MUSIC_SILENCE_DB},
	STATE_CLOSE_BATTLE: {&"BASE": -9.0, &"DRIVE": -3.0, &"TENSION": -2.5, &"RESULTS": MUSIC_SILENCE_DB},
	STATE_RESULTS: {&"BASE": -17.0, &"DRIVE": -22.0, &"TENSION": MUSIC_SILENCE_DB, &"RESULTS": -4.5},
}
const STATE_TRANSITION_SECONDS := {
	STATE_GARAGE: 0.70,
	STATE_STAGING: 0.55,
	STATE_RACING: 0.55,
	STATE_FINAL_LAP: 0.70,
	STATE_CLOSE_BATTLE: 0.35,
	STATE_RESULTS: 0.90,
}

# These arrangements deliberately differ in tempo, contour, harmony and drum
# placement. They are authored for this project and resolved deterministically.
const DISTRICT_ARRANGEMENTS := {
	&"QUARRY": {
		&"bpm": 143.0, &"transpose": 0, &"rhythm_seed": 19,
		&"bass": [38, -1, 38, 45, 38, -1, 41, 38, 36, -1, 43, 36, 36, 43, 41, -1, 34, -1, 41, 34, 34, 41, 38, -1, 33, -1, 40, 33, 36, 40, 45, -1],
		&"lead": [-1, 69, 74, 77, 76, 74, 69, 72, 67, 72, 76, 79, 76, 74, 72, 67, 65, 70, 74, 77, 74, 72, 70, 65, 64, 69, 73, 76, 73, 71, 69, -1],
		&"chord_roots": [50, 48, 46, 45],
		&"chord_qualities": [&"MINOR", &"MAJOR", &"MAJOR", &"MAJOR"],
	},
	&"PINE": {
		&"bpm": 132.0, &"transpose": 0, &"rhythm_seed": 37,
		&"bass": [36, -1, 36, -1, 43, -1, 40, 36, 34, -1, 41, -1, 34, 41, -1, 29, 31, -1, 38, 31, -1, 38, 41, -1, 33, -1, 40, -1, 36, 40, 43, -1],
		&"lead": [-1, 67, -1, 72, 74, -1, 72, 67, -1, 65, 69, -1, 72, 69, -1, 65, -1, 62, 67, 70, -1, 67, 65, 62, -1, 64, 69, -1, 73, 69, 67, -1],
		&"chord_roots": [48, 46, 43, 45],
		&"chord_qualities": [&"MINOR", &"MAJOR", &"MINOR", &"MAJOR"],
	},
	&"MESA_MX": {
		&"bpm": 154.0, &"transpose": 0, &"rhythm_seed": 71,
		&"bass": [40, 40, -1, 47, 40, -1, 43, 47, 38, -1, 45, 38, 38, 45, 47, -1, 36, 36, -1, 43, 36, 43, 40, -1, 35, -1, 42, 47, 42, 38, 47, -1],
		&"lead": [-1, 71, 76, 79, 83, 79, 76, 74, 69, 74, 78, 81, 78, 74, 71, 69, 67, 72, 76, 79, 76, 72, 71, 67, 66, 71, 75, 78, 75, 71, 78, -1],
		&"chord_roots": [52, 50, 48, 47],
		&"chord_qualities": [&"MINOR", &"MAJOR", &"MAJOR", &"MAJOR"],
	},
}
const VARIATION_MODIFIERS := {
	&"STANDARD": {&"bpm_add": 0.0, &"transpose_add": 0, &"seed_add": 0, &"drive_density": 1.0, &"tension_bias": 0.78},
	&"WEEKEND": {&"bpm_add": 3.0, &"transpose_add": 0, &"seed_add": 101, &"drive_density": 1.08, &"tension_bias": 0.96},
	&"FINALE": {&"bpm_add": 7.0, &"transpose_add": 2, &"seed_add": 151, &"drive_density": 1.18, &"tension_bias": 1.12},
	&"CHALLENGE": {&"bpm_add": 5.0, &"transpose_add": -1, &"seed_add": 211, &"drive_density": 1.12, &"tension_bias": 1.02},
}

static var _music_stream_cache: Dictionary[StringName, Dictionary] = {}
static var _music_cache_order: Array[StringName] = []

var _voices: Array[AudioStreamPlayer] = []
var _voice_index: int = 0
var _cues: Dictionary[StringName, AudioStreamWAV] = {}
var _last_racecraft_cue_usec: int = -1_000_000
var _last_flow_denied_cue_usec: int = -1_000_000
var _flow_denied_cue_count: int = 0
var _flow_denied_suppressed_count: int = 0
var _last_flow_denied_payload: Dictionary = {}
var _interface_feedback_count: int = 0
var _interface_feedback_suppressed_count: int = 0
var _last_interface_feedback_usec: int = -1_000_000
var _last_interface_feedback_kind: StringName = &""
var _last_interface_feedback_context: StringName = &""
var _music_banks: Array[Dictionary] = []
var _active_music_bank: int = 0
var _active_arrangement_hash: StringName = &""
var _music_transition_tween: Tween
var _stem_tween: Tween
var _current_arrangement: Dictionary = {}
var _current_activity: StringName = &"CIRCUIT"
var _current_track: StringName = &"QUARRY"
var _music_state: StringName = STATE_GARAGE
var _session_phase: StringName = &"WAITING"
var _flow_mix: float = 0.0
var _is_final_lap: bool = false
var _close_battle: bool = false
var _close_enter_samples: int = 0
var _close_exit_samples: int = 0
var _state_transition_count: int = 0
var _last_transition_seconds: float = 0.0
var _contract_cued: bool = false
var _shut_down: bool = false
var _audio_enabled: bool = false
var _race_snapshot_source: Node
var _player_engine_audio: Node
var _music_prepare_thread: Thread
var _music_prepare_hash: StringName = &""
var _music_prepare_contract: Dictionary = {}


func _ready() -> void:
	ensure_audio_buses()
	_connect_event_bus()
	if &"--smoke-test" in OS.get_cmdline_user_args() or AudioServer.get_driver_name() == "Dummy":
		return
	_audio_enabled = true
	for _index: int in VOICE_COUNT:
		var voice := AudioStreamPlayer.new()
		voice.bus = SFX_BUS_NAME
		voice.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
		add_child(voice)
		_voices.append(voice)
	_build_cues()
	_build_music()


func initialize(bike: DirtBikeController, ride_director: RideDirector) -> void:
	if not _audio_enabled:
		return
	if not bike.flow_gained.is_connected(_on_flow_gained):
		bike.flow_gained.connect(_on_flow_gained)
	if not bike.boost_activated.is_connected(_on_boost_activated):
		bike.boost_activated.connect(_on_boost_activated)
	if not bike.landed.is_connected(_on_bike_landed):
		bike.landed.connect(_on_bike_landed)
	if not bike.racecraft_event.is_connected(_on_bike_racecraft_event):
		bike.racecraft_event.connect(_on_bike_racecraft_event)
	if not ride_director.line_updated.is_connected(_on_line_updated):
		ride_director.line_updated.connect(_on_line_updated)
	if not ride_director.route_discovered.is_connected(_on_route_discovered):
		ride_director.route_discovered.connect(_on_route_discovered)
	if not ride_director.contract_updated.is_connected(_on_contract_updated):
		ride_director.contract_updated.connect(_on_contract_updated)
	_player_engine_audio = bike.find_child("EngineAudio", true, false)
	configure_player_class(Profile.selected_bike_class)
	_connect_race_snapshot_source(bike)


func configure_player_class(class_id: StringName) -> void:
	if is_instance_valid(_player_engine_audio) and _player_engine_audio.has_method(&"configure_class"):
		_player_engine_audio.call(&"configure_class", class_id)


func begin_arrangement_prepare(activity: StringName, track_override: StringName = &"") -> void:
	if not _audio_enabled or _shut_down:
		return
	var contract := get_arrangement_contract(activity, track_override)
	var contract_hash := StringName(contract.get(&"contract_hash", &""))
	if _music_stream_cache.has(contract_hash) or contract_hash == _music_prepare_hash:
		return
	# A completed worker must be joined before Thread can be safely replaced.
	if _music_prepare_thread != null and _music_prepare_thread.is_started():
		if _music_prepare_thread.is_alive():
			return
		_finalize_prepared_arrangement()
	_music_prepare_hash = contract_hash
	_music_prepare_contract = contract.duplicate(true)
	_music_prepare_thread = Thread.new()
	var error := _music_prepare_thread.start(
		Callable(self, &"_render_prepared_arrangement").bind(_music_prepare_contract),
		Thread.PRIORITY_LOW
	)
	if error != OK:
		_music_prepare_thread = null
		_music_prepare_hash = &""
		_music_prepare_contract.clear()


func finish_arrangement_prepare(activity: StringName, track_override: StringName = &"") -> void:
	if not _audio_enabled or _shut_down:
		return
	var requested_hash := get_arrangement_hash(activity, track_override)
	if _music_stream_cache.has(requested_hash):
		return
	if (
		_music_prepare_thread != null
		and _music_prepare_thread.is_started()
		and _music_prepare_hash == requested_hash
	):
		_finalize_prepared_arrangement()


func _render_prepared_arrangement(contract: Dictionary) -> Dictionary:
	return _render_music_data_for_contract(contract)


func _finalize_prepared_arrangement() -> void:
	if _music_prepare_thread == null or not _music_prepare_thread.is_started():
		return
	var rendered_data: Variant = _music_prepare_thread.wait_to_finish()
	var completed_hash := _music_prepare_hash
	_music_prepare_thread = null
	_music_prepare_hash = &""
	_music_prepare_contract.clear()
	if not rendered_data is Dictionary or _music_stream_cache.has(completed_hash):
		return
	var streams: Dictionary = {}
	for stem: StringName in MUSIC_STEMS:
		var data: PackedByteArray = (rendered_data as Dictionary).get(stem, PackedByteArray())
		if data.is_empty():
			return
		streams[stem] = _music_stream_from_data(data)
	_cache_music_streams(completed_hash, streams)


func get_audio_contract_snapshot() -> Dictionary:
	return {
		&"activity": _current_activity,
		&"track_id": _current_track,
		&"district": StringName(_current_arrangement.get(&"district", &"QUARRY")),
		&"variation": StringName(_current_arrangement.get(&"variation", &"STANDARD")),
		&"arrangement_hash": StringName(_current_arrangement.get(&"contract_hash", &"")),
		&"music_state": _music_state,
		&"session_phase": _session_phase,
		&"close_battle": _close_battle,
		&"final_lap": _is_final_lap,
		&"transition_count": _state_transition_count,
		&"last_transition_seconds": _last_transition_seconds,
		&"state_mix": _target_mix_for_state(_music_state),
	}


static func get_arrangement_contract(activity: StringName, track_override: StringName = &"") -> Dictionary:
	var district := _district_for(activity, track_override)
	var variation := _variation_for(activity)
	var base := (DISTRICT_ARRANGEMENTS[district] as Dictionary).duplicate(true)
	var modifier := (VARIATION_MODIFIERS[variation] as Dictionary).duplicate(true)
	base[&"district"] = district
	base[&"variation"] = variation
	base[&"activity"] = activity
	base[&"bpm"] = float(base.get(&"bpm", 143.0)) + float(modifier.get(&"bpm_add", 0.0))
	base[&"transpose"] = int(base.get(&"transpose", 0)) + int(modifier.get(&"transpose_add", 0))
	base[&"rhythm_seed"] = int(base.get(&"rhythm_seed", 0)) + int(modifier.get(&"seed_add", 0))
	base[&"drive_density"] = float(modifier.get(&"drive_density", 1.0))
	base[&"tension_bias"] = float(modifier.get(&"tension_bias", 0.8))
	base[&"identity"] = StringName("%s_%s" % [String(district), String(variation)])
	base[&"contract_hash"] = _arrangement_hash(base)
	return base


static func get_arrangement_hash(activity: StringName, track_override: StringName = &"") -> StringName:
	return StringName(get_arrangement_contract(activity, track_override).get(&"contract_hash", &""))


static func get_music_state_mix(state: StringName) -> Dictionary:
	return (MUSIC_STATE_MIXES.get(state, MUSIC_STATE_MIXES[STATE_RACING]) as Dictionary).duplicate(true)


static func get_bus_routing_contract() -> Dictionary:
	return {
		&"music": MUSIC_BUS_NAME,
		&"feedback": SFX_BUS_NAME,
		&"engine": ENGINE_BUS_NAME,
	}


static func get_transition_contract() -> Dictionary:
	return {
		&"arrangement_crossfade_seconds": MUSIC_CROSSFADE_SECONDS,
		&"minimum_stem_transition_seconds": 0.35,
		&"close_battle_enter_samples": CLOSE_BATTLE_ENTER_SAMPLES,
		&"close_battle_exit_samples": CLOSE_BATTLE_EXIT_SAMPLES,
	}


static func get_flow_denied_audio_contract() -> Dictionary:
	return {
		&"cue": &"flow_denied",
		&"bus": SFX_BUS_NAME,
		&"start_hz": FLOW_DENIED_CUE_START_HZ,
		&"end_hz": FLOW_DENIED_CUE_END_HZ,
		&"duration": FLOW_DENIED_CUE_DURATION,
		&"volume_db": FLOW_DENIED_CUE_VOLUME_DB,
		&"cooldown_usec": FLOW_DENIED_CUE_COOLDOWN_USEC,
		&"pooled_voices": VOICE_COUNT,
	}


static func get_interface_feedback_contract() -> Dictionary:
	return {
		&"bus": SFX_BUS_NAME,
		&"cooldown_usec": INTERFACE_FEEDBACK_COOLDOWN_USEC,
		&"pooled_voices": VOICE_COUNT,
		&"kinds": INTERFACE_FEEDBACK_CONTRACT.duplicate(true),
	}


func get_racecraft_audio_feedback_snapshot() -> Dictionary:
	return {
		&"flow_denied_cue_count": _flow_denied_cue_count,
		&"flow_denied_suppressed_count": _flow_denied_suppressed_count,
		&"last_flow_denied_payload": _last_flow_denied_payload.duplicate(true),
		&"flow_denied_cue_ready": _cues.has(&"flow_denied"),
	}


func get_interface_feedback_snapshot() -> Dictionary:
	var cue_ready: Dictionary[StringName, bool] = {}
	for raw_kind: Variant in INTERFACE_FEEDBACK_CONTRACT:
		var spec := INTERFACE_FEEDBACK_CONTRACT[raw_kind] as Dictionary
		var cue := StringName(spec.get(&"cue", &""))
		cue_ready[StringName(raw_kind)] = not cue.is_empty() and _cues.has(cue)
	return {
		&"count": _interface_feedback_count,
		&"suppressed_count": _interface_feedback_suppressed_count,
		&"last_kind": _last_interface_feedback_kind,
		&"last_context": _last_interface_feedback_context,
		&"cue_ready": cue_ready,
		&"contract": get_interface_feedback_contract(),
	}


func _exit_tree() -> void:
	shutdown()


func shutdown() -> void:
	if _shut_down:
		return
	_shut_down = true
	_audio_enabled = false
	if _music_prepare_thread != null and _music_prepare_thread.is_started():
		_music_prepare_thread.wait_to_finish()
	_music_prepare_thread = null
	_music_prepare_hash = &""
	_music_prepare_contract.clear()
	for voice: AudioStreamPlayer in _voices:
		voice.stop()
		voice.stream = null
		voice.queue_free()
	_voices.clear()
	if _music_transition_tween != null:
		_music_transition_tween.kill()
		_music_transition_tween = null
	if _stem_tween != null:
		_stem_tween.kill()
		_stem_tween = null
	for bank: Dictionary in _music_banks:
		for stem: StringName in MUSIC_STEMS:
			var player := bank.get(stem) as AudioStreamPlayer
			if player != null:
				player.stop()
				player.stream = null
				player.queue_free()
	_music_banks.clear()
	_cues.clear()


func _connect_event_bus() -> void:
	if not EventBus.interface_feedback_requested.is_connected(_on_interface_feedback_requested):
		EventBus.interface_feedback_requested.connect(_on_interface_feedback_requested)
	if not EventBus.race_countdown_changed.is_connected(_on_countdown_changed):
		EventBus.race_countdown_changed.connect(_on_countdown_changed)
	if not EventBus.checkpoint_passed.is_connected(_on_checkpoint_passed):
		EventBus.checkpoint_passed.connect(_on_checkpoint_passed)
	if not EventBus.race_finished.is_connected(_on_race_finished):
		EventBus.race_finished.connect(_on_race_finished)
	if not EventBus.race_results_ready.is_connected(_on_race_results_ready):
		EventBus.race_results_ready.connect(_on_race_results_ready)
	if not EventBus.race_reset.is_connected(_on_race_reset):
		EventBus.race_reset.connect(_on_race_reset)
	if not EventBus.race_started.is_connected(_on_race_started):
		EventBus.race_started.connect(_on_race_started)
	if not EventBus.activity_prepared.is_connected(_on_activity_prepared):
		EventBus.activity_prepared.connect(_on_activity_prepared)
	if not EventBus.activity_completed.is_connected(_on_activity_completed):
		EventBus.activity_completed.connect(_on_activity_completed)
	if not EventBus.activity_started.is_connected(_on_activity_started):
		EventBus.activity_started.connect(_on_activity_started)


func _connect_race_snapshot_source(bike: Node) -> void:
	var parent := bike.get_parent()
	if parent == null:
		return
	var source := parent.find_child("RaceController", true, false)
	if source == null:
		return
	_race_snapshot_source = source
	_connect_source_signal(source, &"session_updated", Callable(self, &"_on_session_updated"))
	_connect_source_signal(source, &"field_updated", Callable(self, &"_on_field_updated"))
	_connect_source_signal(source, &"lap_completed", Callable(self, &"_on_lap_completed"))
	_connect_source_signal(source, &"results_ready", Callable(self, &"_on_source_results_ready"))


func _connect_source_signal(source: Node, signal_name: StringName, callable: Callable) -> void:
	if source.has_signal(signal_name) and not source.is_connected(signal_name, callable):
		source.connect(signal_name, callable)


func _build_cues() -> void:
	for raw_kind: Variant in INTERFACE_FEEDBACK_CONTRACT:
		var spec := INTERFACE_FEEDBACK_CONTRACT[raw_kind] as Dictionary
		_cues[StringName(spec.get(&"cue", &""))] = _make_sweep(
			float(spec.get(&"start_hz", 440.0)),
			float(spec.get(&"end_hz", 440.0)),
			float(spec.get(&"duration", 0.08)),
			float(spec.get(&"amplitude", 0.2)),
			float(spec.get(&"harmonic", 0.1))
		)
	_cues[&"count"] = _make_sweep(390.0, 390.0, 0.09, 0.34, 0.12)
	_cues[&"go"] = _make_sweep(520.0, 880.0, 0.20, 0.38, 0.18)
	_cues[&"gate"] = _make_sweep(660.0, 920.0, 0.13, 0.32, 0.16)
	_cues[&"flow"] = _make_sweep(540.0, 760.0, 0.16, 0.30, 0.22)
	_cues[&"boost"] = _make_sweep(145.0, 510.0, 0.34, 0.42, 0.34)
	_cues[&"finish"] = _make_sweep(430.0, 860.0, 0.42, 0.38, 0.28)
	_cues[&"route"] = _make_sweep(310.0, 980.0, 0.30, 0.36, 0.25)
	_cues[&"contract"] = _make_sweep(440.0, 1180.0, 0.48, 0.38, 0.30)
	_cues[&"landing"] = _make_sweep(118.0, 48.0, 0.24, 0.46, 0.42)
	_cues[&"racecraft"] = _make_sweep(185.0, 640.0, 0.18, 0.32, 0.28)
	# A brief descending, lower-level refusal cue. It is deliberately unlike the
	# rising racecraft success sound so an unaffordable press cannot read as a win.
	_cues[&"flow_denied"] = _make_sweep(
		FLOW_DENIED_CUE_START_HZ,
		FLOW_DENIED_CUE_END_HZ,
		FLOW_DENIED_CUE_DURATION,
		0.24,
		0.16
	)


func _make_sweep(start_hz: float, end_hz: float, duration: float, amplitude: float, harmonic: float) -> AudioStreamWAV:
	var sample_count := maxi(int(duration * MIX_RATE), 1)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var phase := 0.0
	for sample_index: int in sample_count:
		var progress := float(sample_index) / float(sample_count)
		var frequency := lerpf(start_hz, end_hz, progress * progress)
		phase = fmod(phase + frequency / float(MIX_RATE), 1.0)
		var attack := clampf(progress / 0.055, 0.0, 1.0)
		var envelope := attack * pow(1.0 - progress, 1.7)
		var wave := sin(phase * TAU) + sin(phase * TAU * 2.0) * harmonic
		var signed_sample := clampi(int(wave * amplitude * envelope * 32767.0), -32768, 32767)
		var encoded_sample := signed_sample if signed_sample >= 0 else 65536 + signed_sample
		data[sample_index * 2] = encoded_sample & 0xff
		data[sample_index * 2 + 1] = (encoded_sample >> 8) & 0xff
	var wave_stream := AudioStreamWAV.new()
	wave_stream.format = AudioStreamWAV.FORMAT_16_BITS
	wave_stream.mix_rate = MIX_RATE
	wave_stream.stereo = false
	wave_stream.data = data
	return wave_stream


func _build_music() -> void:
	for bank_index: int in 2:
		var bank: Dictionary = {}
		for stem: StringName in MUSIC_STEMS:
			var player := AudioStreamPlayer.new()
			player.name = "Music%s_%s" % ["A" if bank_index == 0 else "B", String(stem)]
			player.bus = MUSIC_BUS_NAME
			player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
			player.volume_db = MUSIC_SILENCE_DB
			add_child(player)
			bank[stem] = player
		_music_banks.append(bank)
	var garage_contract := get_arrangement_contract(&"CIRCUIT", &"QUARRY")
	var garage_hash := StringName(garage_contract.get(&"contract_hash", &""))
	_cache_music_streams(garage_hash, {
		&"BASE": _configure_baked_music_loop(BAKED_QUARRY_STANDARD_BASE),
		&"DRIVE": _configure_baked_music_loop(BAKED_QUARRY_STANDARD_DRIVE),
		&"TENSION": _configure_baked_music_loop(BAKED_QUARRY_STANDARD_TENSION),
		&"RESULTS": _configure_baked_music_loop(BAKED_QUARRY_STANDARD_RESULTS),
	})
	_select_arrangement(&"CIRCUIT", &"QUARRY", true)


static func _configure_baked_music_loop(source: AudioStreamWAV) -> AudioStreamWAV:
	var stream := source.duplicate() as AudioStreamWAV
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = roundi(stream.get_length() * float(stream.mix_rate))
	return stream


func _select_arrangement(activity: StringName, track_override: StringName = &"", immediate: bool = false) -> void:
	var contract := get_arrangement_contract(activity, track_override)
	var new_hash := StringName(contract.get(&"contract_hash", &""))
	var previous_hash := _active_arrangement_hash
	_current_activity = activity
	_current_track = StringName(contract.get(&"district", &"QUARRY"))
	_current_arrangement = contract
	_active_arrangement_hash = new_hash
	if not _audio_enabled or _music_banks.is_empty() or previous_hash == new_hash:
		return
	if immediate or previous_hash.is_empty():
		_assign_bank_streams(_active_music_bank, contract)
		_start_bank(_active_music_bank)
		_apply_stem_mix(true)
		return
	if _music_transition_tween != null:
		_music_transition_tween.kill()
	if _stem_tween != null:
		_stem_tween.kill()
		_stem_tween = null
	var old_bank := _active_music_bank
	var next_bank := 1 - old_bank
	_stop_bank(next_bank)
	_assign_bank_streams(next_bank, contract)
	_set_bank_silence(next_bank)
	_start_bank(next_bank)
	_active_music_bank = next_bank
	var target_mix := _target_mix_for_state(_music_state)
	_music_transition_tween = create_tween().set_parallel(true)
	for stem: StringName in MUSIC_STEMS:
		var old_player := _music_banks[old_bank].get(stem) as AudioStreamPlayer
		var new_player := _music_banks[next_bank].get(stem) as AudioStreamPlayer
		_music_transition_tween.tween_property(old_player, "volume_db", MUSIC_SILENCE_DB, MUSIC_CROSSFADE_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_music_transition_tween.tween_property(new_player, "volume_db", float(target_mix.get(stem, MUSIC_SILENCE_DB)), MUSIC_CROSSFADE_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_music_transition_tween.chain().tween_callback(Callable(self, &"_finish_arrangement_crossfade").bind(old_bank))


func _assign_bank_streams(bank_index: int, contract: Dictionary) -> void:
	var streams := _streams_for_contract(contract)
	for stem: StringName in MUSIC_STEMS:
		var player := _music_banks[bank_index].get(stem) as AudioStreamPlayer
		player.stream = streams.get(stem) as AudioStreamWAV


func _start_bank(bank_index: int) -> void:
	for stem: StringName in MUSIC_STEMS:
		var player := _music_banks[bank_index].get(stem) as AudioStreamPlayer
		if player.stream != null and not player.playing:
			player.play()


func _stop_bank(bank_index: int) -> void:
	if bank_index < 0 or bank_index >= _music_banks.size():
		return
	for stem: StringName in MUSIC_STEMS:
		var player := _music_banks[bank_index].get(stem) as AudioStreamPlayer
		player.stop()


func _set_bank_silence(bank_index: int) -> void:
	for stem: StringName in MUSIC_STEMS:
		var player := _music_banks[bank_index].get(stem) as AudioStreamPlayer
		player.volume_db = MUSIC_SILENCE_DB


func _finish_arrangement_crossfade(old_bank: int) -> void:
	if old_bank != _active_music_bank:
		_stop_bank(old_bank)
		_set_bank_silence(old_bank)
	_music_transition_tween = null
	_apply_stem_mix(false)


static func _streams_for_contract(contract: Dictionary) -> Dictionary:
	var contract_hash := StringName(contract.get(&"contract_hash", &""))
	if _music_stream_cache.has(contract_hash):
		return _music_stream_cache[contract_hash]
	var streams: Dictionary = {}
	for stem: StringName in MUSIC_STEMS:
		streams[stem] = _make_music_loop(stem, contract)
	_cache_music_streams(contract_hash, streams)
	return streams


static func _cache_music_streams(contract_hash: StringName, streams: Dictionary) -> void:
	if contract_hash.is_empty() or _music_stream_cache.has(contract_hash):
		return
	while _music_cache_order.size() >= MAX_CACHED_ARRANGEMENTS:
		var expired: StringName = _music_cache_order.pop_front()
		_music_stream_cache.erase(expired)
	_music_stream_cache[contract_hash] = streams
	_music_cache_order.append(contract_hash)


static func _render_music_data_for_contract(contract: Dictionary) -> Dictionary:
	var rendered_data: Dictionary = {}
	for stem: StringName in MUSIC_STEMS:
		rendered_data[stem] = _make_music_loop_data(stem, contract)
	return rendered_data


static func build_baked_arrangement(
	activity: StringName,
	track_override: StringName = &""
) -> Dictionary:
	## Build-time entry point used by the audio asset baker. Keeping synthesis in
	## one authority guarantees the baked garage mix matches adaptive race mixes.
	var contract := get_arrangement_contract(activity, track_override)
	var streams: Dictionary = {}
	for stem: StringName in MUSIC_STEMS:
		streams[stem] = _make_music_loop(stem, contract)
	return {
		&"contract": contract,
		&"streams": streams,
	}


static func _make_music_loop(layer: StringName, contract: Dictionary) -> AudioStreamWAV:
	return _music_stream_from_data(_make_music_loop_data(layer, contract))


static func _make_music_loop_data(layer: StringName, contract: Dictionary) -> PackedByteArray:
	var seconds_per_beat := 60.0 / float(contract.get(&"bpm", 143.0))
	var sample_count := int(MUSIC_BEATS * seconds_per_beat * MIX_RATE)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for sample_index: int in sample_count:
		var time := float(sample_index) / float(MIX_RATE)
		var beat := time / seconds_per_beat
		var wave := 0.0
		match layer:
			&"BASE":
				wave = _render_base_layer(beat, seconds_per_beat, sample_index, contract)
			&"DRIVE":
				wave = _render_drive_layer(beat, seconds_per_beat, contract)
			&"TENSION":
				wave = _render_tension_layer(beat, seconds_per_beat, sample_index, contract)
			&"RESULTS":
				wave = _render_results_layer(beat, seconds_per_beat, contract)
		var signed_sample := clampi(int(tanh(wave * 1.18) * 32767.0), -32768, 32767)
		var encoded_sample := signed_sample if signed_sample >= 0 else 65536 + signed_sample
		data[sample_index * 2] = encoded_sample & 0xff
		data[sample_index * 2 + 1] = (encoded_sample >> 8) & 0xff
	return data


static func _music_stream_from_data(data: PackedByteArray) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = data.size() / 2
	stream.data = data
	return stream


static func _render_base_layer(beat: float, seconds_per_beat: float, sample_index: int, contract: Dictionary) -> float:
	var pattern: Array = contract.get(&"bass", []) as Array
	var half_step := posmod(int(floor(beat * 2.0)), pattern.size())
	var half_phase := fmod(beat * 2.0, 1.0)
	var bass_note := int(pattern[half_step])
	var transpose := int(contract.get(&"transpose", 0))
	var bass := 0.0
	if bass_note >= 0:
		var bass_hz := _midi_to_hz(bass_note + transpose)
		var bass_time := half_phase * seconds_per_beat * 0.5
		var envelope := minf(half_phase * 18.0, 1.0) * pow(1.0 - half_phase, 0.32)
		var fundamental := sin(bass_time * bass_hz * TAU)
		bass = (fundamental * 0.56 + sin(bass_time * bass_hz * 0.5 * TAU) * 0.30 + tanh(fundamental * 1.8) * 0.14) * envelope * 0.34
	var district := StringName(contract.get(&"district", &"QUARRY"))
	var kick_steps := [0, 3, 4, 7]
	if district == &"PINE":
		kick_steps = [0, 4, 6]
	elif district == &"MESA_MX":
		kick_steps = [0, 2, 3, 5, 7]
	var eighth_index := posmod(int(floor(beat * 2.0)), 8)
	var eighth_phase := fmod(beat * 2.0, 1.0)
	var kick := 0.0
	if eighth_index in kick_steps:
		var kick_time := eighth_phase * seconds_per_beat * 0.5
		var kick_phase := 42.0 * kick_time + 5.0 * (1.0 - exp(-kick_time * 18.0))
		kick = sin(kick_phase * TAU) * exp(-eighth_phase * 7.0) * 0.50
	var beat_index := posmod(int(floor(beat)), 4)
	var beat_phase := fmod(beat, 1.0)
	var snare := 0.0
	if beat_index in [1, 3]:
		snare = (_chip_noise(sample_index + int(contract.get(&"rhythm_seed", 0))) * 0.52 + sin(beat_phase * seconds_per_beat * 142.0 * TAU) * 0.48) * exp(-beat_phase * 13.0) * 0.17
	var quarter_phase := fmod(beat * 4.0, 1.0)
	var hat := _chip_noise(sample_index / 3 + int(contract.get(&"rhythm_seed", 0))) * exp(-quarter_phase * 24.0) * (0.028 if eighth_index % 2 == 0 else 0.018)
	return bass + kick + snare + hat


static func _render_drive_layer(beat: float, seconds_per_beat: float, contract: Dictionary) -> float:
	var pattern: Array = contract.get(&"lead", []) as Array
	var half_step := posmod(int(floor(beat * 2.0)), pattern.size())
	var half_phase := fmod(beat * 2.0, 1.0)
	var lead_note := int(pattern[half_step])
	var transpose := int(contract.get(&"transpose", 0))
	var lead := 0.0
	if lead_note >= 0:
		var lead_hz := _midi_to_hz(lead_note - 12 + transpose)
		var lead_time := half_phase * seconds_per_beat * 0.5
		var envelope := minf(half_phase * 24.0, 1.0) * pow(1.0 - half_phase, 0.6)
		var phase := lead_time * lead_hz + sin(lead_time * 6.1 * TAU) * 0.0035
		lead = (sin(phase * TAU) * 0.62 + _triangle(phase) * 0.28 + _pulse(phase, 0.5) * 0.10) * envelope * 0.23
	var roots: Array = contract.get(&"chord_roots", []) as Array
	var qualities: Array = contract.get(&"chord_qualities", []) as Array
	var sixteenth_step := posmod(int(floor(beat * 4.0)), 16)
	var sixteenth_phase := fmod(beat * 4.0, 1.0)
	var bar_index := posmod(int(floor(beat / 4.0)), roots.size())
	var third := 3 if StringName(qualities[bar_index]) == &"MINOR" else 4
	var offsets := [0, third, 7, 12]
	var arp_note := int(roots[bar_index]) + int(offsets[posmod(sixteenth_step + bar_index, offsets.size())]) + transpose
	var arp_time := sixteenth_phase * seconds_per_beat * 0.25
	var arp := (_triangle(arp_time * _midi_to_hz(arp_note)) * 0.8 + sin(arp_time * _midi_to_hz(arp_note) * TAU) * 0.2) * pow(1.0 - sixteenth_phase, 1.5) * 0.028 * float(contract.get(&"drive_density", 1.0))
	return lead + arp


static func _render_tension_layer(beat: float, seconds_per_beat: float, sample_index: int, contract: Dictionary) -> float:
	var roots: Array = contract.get(&"chord_roots", []) as Array
	var bar_index := posmod(int(floor(beat / 4.0)), roots.size())
	var transpose := int(contract.get(&"transpose", 0))
	var step := posmod(int(floor(beat * 4.0)), 16)
	var step_phase := fmod(beat * 4.0, 1.0)
	var offsets := [12, 19, 15, 22]
	var note := int(roots[bar_index]) + int(offsets[posmod(step + int(contract.get(&"rhythm_seed", 0)), offsets.size())]) + transpose
	var local_time := step_phase * seconds_per_beat * 0.25
	var pulse_wave := _pulse(local_time * _midi_to_hz(note), 0.34) * pow(1.0 - step_phase, 1.1) * 0.052
	var noise_tick := _chip_noise(sample_index + int(contract.get(&"rhythm_seed", 0)) * 13) * exp(-step_phase * 18.0) * 0.018
	return (pulse_wave + noise_tick) * float(contract.get(&"tension_bias", 0.8))


static func _render_results_layer(beat: float, seconds_per_beat: float, contract: Dictionary) -> float:
	var roots: Array = contract.get(&"chord_roots", []) as Array
	var qualities: Array = contract.get(&"chord_qualities", []) as Array
	var bar_index := posmod(int(floor(beat / 4.0)), roots.size())
	var bar_phase := fmod(beat / 4.0, 1.0)
	var transpose := int(contract.get(&"transpose", 0))
	var root := int(roots[bar_index]) + transpose
	var third := 3 if StringName(qualities[bar_index]) == &"MINOR" else 4
	var bar_time := bar_phase * seconds_per_beat * 4.0
	var envelope := minf(bar_phase * 12.0, 1.0) * pow(1.0 - bar_phase, 0.42)
	var pad := (sin(bar_time * _midi_to_hz(root) * TAU) * 0.48 + sin(bar_time * _midi_to_hz(root + third) * TAU) * 0.28 + sin(bar_time * _midi_to_hz(root + 7) * TAU) * 0.24) * envelope * 0.12
	var half_phase := fmod(beat * 0.5, 1.0)
	var resolve_note := root + (12 if bar_index == roots.size() - 1 else 7)
	var resolve := sin(half_phase * seconds_per_beat * 2.0 * _midi_to_hz(resolve_note) * TAU) * minf(half_phase * 10.0, 1.0) * pow(1.0 - half_phase, 1.2) * 0.045
	return pad + resolve


static func _midi_to_hz(note: int) -> float:
	return 440.0 * pow(2.0, (float(note) - 69.0) / 12.0)


static func _pulse(phase: float, duty: float) -> float:
	return 1.0 if fmod(phase, 1.0) < duty else -1.0


static func _triangle(phase: float) -> float:
	return 1.0 - 4.0 * absf(fmod(phase, 1.0) - 0.5)


static func _chip_noise(seed: int) -> float:
	var value := posmod(seed * 1103515245 + 12345, 2147483647)
	return float(value & 65535) / 32767.5 - 1.0


static func _district_for(activity: StringName, track_override: StringName) -> StringName:
	var track := track_override
	if track.is_empty() and RaceEventCatalog.has_event(activity):
		track = RaceEventCatalog.get_track_id(activity)
	if track == &"PINE":
		return &"PINE"
	if track == &"MESA_MX":
		return &"MESA_MX"
	return &"QUARRY"


static func _variation_for(activity: StringName) -> StringName:
	if RaceEventCatalog.is_challenge_event(activity):
		return &"CHALLENGE"
	if activity == &"MESA_MX":
		return &"FINALE"
	if RaceEventCatalog.is_weekend_event(activity):
		return &"WEEKEND"
	return &"STANDARD"


static func _arrangement_hash(contract: Dictionary) -> StringName:
	var canonical := "%s|%s|%.3f|%d|%d|%.3f|%.3f|%s|%s|%s|%s" % [
		String(contract.get(&"district", &"QUARRY")),
		String(contract.get(&"variation", &"STANDARD")),
		float(contract.get(&"bpm", 143.0)),
		int(contract.get(&"transpose", 0)),
		int(contract.get(&"rhythm_seed", 0)),
		float(contract.get(&"drive_density", 1.0)),
		float(contract.get(&"tension_bias", 0.8)),
		str(contract.get(&"bass", [])),
		str(contract.get(&"lead", [])),
		str(contract.get(&"chord_roots", [])),
		str(contract.get(&"chord_qualities", [])),
	]
	return StringName("%08x" % (canonical.hash() & 0x7fffffff))


func _set_music_state(state: StringName, force: bool = false) -> void:
	var normalized := state if MUSIC_STATE_MIXES.has(state) else STATE_RACING
	var changed := normalized != _music_state
	if not changed and not force:
		return
	_music_state = normalized
	_last_transition_seconds = float(STATE_TRANSITION_SECONDS.get(normalized, 0.55))
	if changed:
		_state_transition_count += 1
	_apply_stem_mix(false)


func _apply_stem_mix(immediate: bool) -> void:
	if not _audio_enabled or _music_banks.is_empty():
		return
	if _music_transition_tween != null and _music_transition_tween.is_running():
		return
	if _stem_tween != null:
		_stem_tween.kill()
		_stem_tween = null
	var target_mix := _target_mix_for_state(_music_state)
	if immediate:
		for stem: StringName in MUSIC_STEMS:
			var immediate_player := _music_banks[_active_music_bank].get(stem) as AudioStreamPlayer
			immediate_player.volume_db = float(target_mix.get(stem, MUSIC_SILENCE_DB))
		return
	_stem_tween = create_tween().set_parallel(true)
	var transition_seconds := float(STATE_TRANSITION_SECONDS.get(_music_state, 0.55))
	for stem: StringName in MUSIC_STEMS:
		var player := _music_banks[_active_music_bank].get(stem) as AudioStreamPlayer
		_stem_tween.tween_property(player, "volume_db", float(target_mix.get(stem, MUSIC_SILENCE_DB)), transition_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _target_mix_for_state(state: StringName) -> Dictionary:
	var mix := get_music_state_mix(state)
	if state == STATE_RACING:
		mix[&"DRIVE"] = lerpf(-11.0, -4.0, _flow_mix)
	return mix


func _refresh_competition_state() -> void:
	if _session_phase in [&"RESULTS", &"FINISHING"]:
		_set_music_state(STATE_RESULTS)
	elif _session_phase in [&"STAGING", &"COUNTDOWN", &"WAITING"]:
		_set_music_state(STATE_STAGING)
	elif _session_phase == &"RACING":
		if _close_battle:
			_set_music_state(STATE_CLOSE_BATTLE)
		elif _is_final_lap:
			_set_music_state(STATE_FINAL_LAP)
		else:
			_set_music_state(STATE_RACING)


func _on_session_updated(snapshot: Dictionary) -> void:
	var activity := StringName(snapshot.get(&"event_id", _current_activity))
	var track_id := StringName(snapshot.get(&"track_id", _current_track))
	_select_arrangement(activity, track_id)
	_session_phase = StringName(snapshot.get(&"phase", &"WAITING"))
	var current_lap := maxi(int(snapshot.get(&"current_lap", 1)), 1)
	var total_laps := maxi(int(snapshot.get(&"total_laps", 1)), 1)
	var checkpoint := maxi(int(snapshot.get(&"current_checkpoint", 0)), 0)
	var checkpoint_count := maxi(int(snapshot.get(&"checkpoint_count", 0)), 0)
	_is_final_lap = total_laps > 1 and current_lap >= total_laps
	if total_laps == 1 and checkpoint_count > 0:
		_is_final_lap = float(checkpoint) / float(checkpoint_count) >= 0.72
	_refresh_competition_state()


func _on_field_updated(_position: int, total: int, gap_ahead: float, gap_behind: float) -> void:
	if total <= 1 or _session_phase != &"RACING":
		_close_battle = false
		_close_enter_samples = 0
		_close_exit_samples = 0
		_refresh_competition_state()
		return
	var close_sample := (gap_ahead >= 0.0 and gap_ahead <= CLOSE_BATTLE_GAP_M) or (gap_behind >= 0.0 and gap_behind <= CLOSE_BATTLE_GAP_M)
	if close_sample:
		_close_enter_samples += 1
		_close_exit_samples = 0
		if _close_enter_samples >= CLOSE_BATTLE_ENTER_SAMPLES:
			_close_battle = true
	else:
		_close_enter_samples = 0
		_close_exit_samples += 1
		if _close_exit_samples >= CLOSE_BATTLE_EXIT_SAMPLES:
			_close_battle = false
	_refresh_competition_state()


func _on_lap_completed(lap: int, total_laps: int, _lap_usec: int, _best_lap_usec: int) -> void:
	if total_laps > 1 and lap >= total_laps - 1:
		_is_final_lap = true
	_refresh_competition_state()


func _on_source_results_ready(_result: Dictionary) -> void:
	_session_phase = &"RESULTS"
	_set_music_state(STATE_RESULTS)


func _play(cue: StringName, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	if not _audio_enabled or _voices.is_empty() or not _cues.has(cue):
		return
	var voice := _voices[_voice_index]
	_voice_index = (_voice_index + 1) % _voices.size()
	voice.stream = _cues[cue]
	voice.pitch_scale = pitch
	voice.volume_db = volume_db
	voice.play()


func _on_interface_feedback_requested(kind: StringName, context: StringName) -> void:
	var normalized_kind := StringName(String(kind).to_upper())
	if not INTERFACE_FEEDBACK_CONTRACT.has(normalized_kind):
		return
	var now := Time.get_ticks_usec()
	if (
		normalized_kind == _last_interface_feedback_kind
		and now - _last_interface_feedback_usec < INTERFACE_FEEDBACK_COOLDOWN_USEC
	):
		_interface_feedback_suppressed_count += 1
		return
	_last_interface_feedback_usec = now
	_last_interface_feedback_kind = normalized_kind
	_last_interface_feedback_context = context
	_interface_feedback_count += 1
	var spec := INTERFACE_FEEDBACK_CONTRACT[normalized_kind] as Dictionary
	_play(
		StringName(spec.get(&"cue", &"")),
		float(spec.get(&"pitch", 1.0)),
		float(spec.get(&"volume_db", 0.0))
	)


func _on_activity_prepared(activity: StringName) -> void:
	_contract_cued = false
	_flow_mix = 0.0
	_close_battle = false
	_close_enter_samples = 0
	_close_exit_samples = 0
	_is_final_lap = false
	_session_phase = &"STAGING"
	_set_music_state(STATE_STAGING, true)
	_select_arrangement(activity)
	var runtime_class := Profile.selected_bike_class
	if RaceEventCatalog.is_challenge_event(activity):
		var challenge_session := RaceEventCatalog.get_session_config(activity)
		if challenge_session != null:
			runtime_class = challenge_session.bike_class
	configure_player_class(runtime_class)


func _on_countdown_changed(value: int) -> void:
	_session_phase = &"COUNTDOWN"
	_set_music_state(STATE_RACING if value == 0 else STATE_STAGING)
	_play(&"go" if value == 0 else &"count", 1.0 + float(3 - value) * 0.04)


func _on_checkpoint_passed(index: int, total: int, _split_usec: int) -> void:
	if total > 0 and float(index + 1) / float(total) >= 0.72:
		_is_final_lap = true
		_refresh_competition_state()
	_play(&"gate")


func _on_race_reset() -> void:
	_session_phase = &"STAGING"
	_close_battle = false
	_is_final_lap = false
	_set_music_state(STATE_STAGING)


func _on_race_started() -> void:
	_session_phase = &"RACING"
	_set_music_state(STATE_RACING)


func _on_race_finished(_time_usec: int, _medal: StringName, _is_new_best: bool) -> void:
	_session_phase = &"FINISHING"
	_set_music_state(STATE_RESULTS)
	_play(&"finish")


func _on_race_results_ready(_result: Dictionary) -> void:
	_session_phase = &"RESULTS"
	_set_music_state(STATE_RESULTS)


func _on_activity_completed(summary: Dictionary) -> void:
	_session_phase = &"RESULTS"
	_set_music_state(STATE_RESULTS)
	# The physical activity still ends when persistence is unavailable, but the
	# celebratory finish cue belongs only to a durable or already-settled result.
	if bool(summary.get(&"accepted", false)) or bool(summary.get(&"duplicate", false)):
		_play(&"finish")


func _on_activity_started(activity: StringName) -> void:
	_contract_cued = false
	_select_arrangement(activity)
	_session_phase = &"RACING"
	_set_music_state(STATE_RACING)
	if _audio_enabled and not _music_banks.is_empty():
		_start_bank(_active_music_bank)


func _on_flow_gained(amount: float) -> void:
	_play(&"flow", lerpf(0.92, 1.12, clampf(amount / 45.0, 0.0, 1.0)), -1.5)


func _on_boost_activated(_flow_remaining: float) -> void:
	_play(&"boost", 1.0, 1.5)


func _on_bike_racecraft_event(kind: StringName, payload: Dictionary) -> void:
	if kind == &"FLOW_DENIED":
		_on_flow_denied(payload)
		return
	if kind in [&"LANDING", &"SLIDE_EXIT"]:
		return
	var now := Time.get_ticks_usec()
	var high_priority := kind in [&"DRAFT_SLINGSHOT", &"BRACE_SAVE", &"COMPOSE_SAVE", &"SKILL_LINE"]
	if not high_priority and now - _last_racecraft_cue_usec < 180_000:
		return
	_last_racecraft_cue_usec = now
	var pitch := 1.0
	match kind:
		&"DAB", &"FLOW_BRACE": pitch = 0.78
		&"PUMP", &"RUT_RAIL": pitch = 0.94
		&"CLUTCH_POP", &"CONTROLLED_SLIDE": pitch = 1.08
		&"FLOW_RAIL", &"DRAFT_SLINGSHOT": pitch = 1.18
		&"FLOW_COMPOSE", &"COMPOSE_SAVE": pitch = 1.28
		&"SKILL_LINE": pitch = 1.36 if StringName(payload.get(&"outcome", &"")) == &"MASTERED" else 1.12
	_play(&"racecraft", pitch, 0.5 if high_priority else -1.5)


func _on_flow_denied(payload: Dictionary) -> void:
	var now := Time.get_ticks_usec()
	if now - _last_flow_denied_cue_usec < FLOW_DENIED_CUE_COOLDOWN_USEC:
		_flow_denied_suppressed_count += 1
		return
	_last_flow_denied_cue_usec = now
	_flow_denied_cue_count += 1
	_last_flow_denied_payload = payload.duplicate(true)
	var required := maxf(float(payload.get(&"required", 0.0)), 0.0)
	var available := maxf(float(payload.get(&"available", 0.0)), 0.0)
	var shortage_ratio := clampf((required - available) / maxf(required, 1.0), 0.0, 1.0)
	_play(&"flow_denied", lerpf(1.04, 0.90, shortage_ratio), FLOW_DENIED_CUE_VOLUME_DB)


func _on_bike_landed(intensity: float) -> void:
	var weight := clampf(intensity, 0.0, 1.0)
	_play(&"landing", lerpf(1.12, 0.72, weight), lerpf(-7.0, 1.5, weight))


func _on_line_updated(_label: String, chain: int, _multiplier: float, _score: int, _time_left: float) -> void:
	_flow_mix = clampf(float(chain) / 6.0, 0.0, 1.0)
	if _music_state == STATE_RACING:
		_set_music_state(STATE_RACING, true)
	if chain >= 3:
		_play(&"flow", 0.9 + float(mini(chain, 8)) * 0.045, -5.0)


func _on_route_discovered(_title: String) -> void:
	_play(&"route", 1.0, 0.5)


func _on_contract_updated(_title: String, _current: int, _target: int, completed: bool) -> void:
	if completed and not _contract_cued:
		_contract_cued = true
		_play(&"contract", 1.0, 1.0)


static func ensure_audio_buses() -> Dictionary:
	## Establish the complete runtime mixer before settings are applied. Keeping
	## engine/contact layers off SFX makes both player-facing sliders truthful.
	var sfx_index := _ensure_named_bus(SFX_BUS_NAME)
	var engine_index := _ensure_named_bus(ENGINE_BUS_NAME)
	var music_was_missing := AudioServer.get_bus_index(MUSIC_BUS_NAME) < 0
	var music_index := _ensure_named_bus(MUSIC_BUS_NAME)
	if music_was_missing and music_index >= 0:
		var low_pass := AudioEffectLowPassFilter.new()
		low_pass.cutoff_hz = 6200.0
		low_pass.resonance = 0.18
		AudioServer.add_bus_effect(music_index, low_pass)
	return {
		&"music": music_index,
		&"feedback": sfx_index,
		&"engine": engine_index,
	}


static func _ensure_named_bus(bus_name: StringName) -> int:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index >= 0:
		return bus_index
	AudioServer.add_bus()
	bus_index = AudioServer.bus_count - 1
	AudioServer.set_bus_name(bus_index, bus_name)
	return bus_index
