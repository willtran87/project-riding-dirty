extends Node
class_name GameplayAudio
## Pooled feedback cues and the original adaptive "Dust Circuit" chiptune.

const MIX_RATE := 22050
const VOICE_COUNT := 5
const MUSIC_BPM := 143.0
const MUSIC_BEATS := 16.0
const MUSIC_BASE_DB := -10.5
const MUSIC_MELODY_IDLE_DB := -12.0
const MUSIC_MELODY_FLOW_DB := -3.5

# Original D-minor patterns. The supplied reference informed the broad idea of a
# low minor-key hook; its pitches, rhythm, harmony, and contour were rewritten.
const BASS_PATTERN := [
	38, -1, 38, 45, 38, -1, 41, 38,
	36, -1, 43, 36, 36, 43, 41, -1,
	34, -1, 41, 34, 34, 41, 38, -1,
	33, -1, 40, 33, 36, 40, 45, -1,
]
const LEAD_PATTERN := [
	-1, 69, 74, 77, 76, 74, 69, 72, # D minor
	67, 72, 76, 79, 76, 74, 72, 67, # C major
	65, 70, 74, 77, 74, 72, 70, 65, # B-flat major
	64, 69, 73, 76, 73, 71, 69, -1, # A major, resolving to A
]
const CHORD_ROOTS := [50, 48, 46, 45] # Dm, C, Bb, A
const CHORD_QUALITIES := [&"MINOR", &"MAJOR", &"MAJOR", &"MAJOR"]

var _voices: Array[AudioStreamPlayer] = []
var _voice_index: int = 0
var _cues: Dictionary[StringName, AudioStreamWAV] = {}
var _music_base: AudioStreamPlayer
var _music_drive: AudioStreamPlayer
var _music_tween: Tween
var _contract_cued: bool = false
var _shut_down: bool = false


func _ready() -> void:
	if &"--smoke-test" in OS.get_cmdline_user_args():
		return
	_ensure_sfx_bus()
	_ensure_music_bus()
	for _index: int in VOICE_COUNT:
		var voice := AudioStreamPlayer.new()
		voice.bus = &"SFX"
		add_child(voice)
		_voices.append(voice)
	_build_cues()
	_build_music()
	EventBus.race_countdown_changed.connect(_on_countdown_changed)
	EventBus.checkpoint_passed.connect(_on_checkpoint_passed)
	EventBus.race_finished.connect(_on_race_finished)
	EventBus.activity_completed.connect(_on_activity_completed)
	EventBus.activity_started.connect(_on_activity_started)


func initialize(bike: DirtBikeController, ride_director: RideDirector) -> void:
	if not bike.flow_gained.is_connected(_on_flow_gained):
		bike.flow_gained.connect(_on_flow_gained)
	if not bike.boost_activated.is_connected(_on_boost_activated):
		bike.boost_activated.connect(_on_boost_activated)
	if not ride_director.line_updated.is_connected(_on_line_updated):
		ride_director.line_updated.connect(_on_line_updated)
	if not ride_director.route_discovered.is_connected(_on_route_discovered):
		ride_director.route_discovered.connect(_on_route_discovered)
	if not ride_director.contract_updated.is_connected(_on_contract_updated):
		ride_director.contract_updated.connect(_on_contract_updated)


func _exit_tree() -> void:
	shutdown()


func shutdown() -> void:
	if _shut_down:
		return
	_shut_down = true
	for voice: AudioStreamPlayer in _voices:
		voice.stop()
		voice.stream = null
		voice.queue_free()
	_voices.clear()
	if _music_tween != null:
		_music_tween.kill()
		_music_tween = null
	for player: AudioStreamPlayer in [_music_base, _music_drive]:
		if player != null:
			player.stop()
			player.stream = null
			player.queue_free()
	_music_base = null
	_music_drive = null
	_cues.clear()


func _build_cues() -> void:
	_cues[&"count"] = _make_sweep(390.0, 390.0, 0.09, 0.34, 0.12)
	_cues[&"go"] = _make_sweep(520.0, 880.0, 0.20, 0.38, 0.18)
	_cues[&"gate"] = _make_sweep(660.0, 920.0, 0.13, 0.32, 0.16)
	_cues[&"flow"] = _make_sweep(540.0, 760.0, 0.16, 0.30, 0.22)
	_cues[&"boost"] = _make_sweep(145.0, 510.0, 0.34, 0.42, 0.34)
	_cues[&"finish"] = _make_sweep(430.0, 860.0, 0.42, 0.38, 0.28)
	_cues[&"route"] = _make_sweep(310.0, 980.0, 0.30, 0.36, 0.25)
	_cues[&"contract"] = _make_sweep(440.0, 1180.0, 0.48, 0.38, 0.30)


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
		var release := pow(1.0 - progress, 1.7)
		var envelope := attack * release
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
	_music_base = AudioStreamPlayer.new()
	_music_base.name = "BaseMusic"
	_music_base.bus = &"Music"
	_music_base.stream = _make_music_loop(&"BASE")
	_music_base.volume_db = MUSIC_BASE_DB
	add_child(_music_base)
	_music_drive = AudioStreamPlayer.new()
	_music_drive.name = "DriveMusic"
	_music_drive.bus = &"Music"
	_music_drive.stream = _make_music_loop(&"DRIVE")
	_music_drive.volume_db = MUSIC_MELODY_IDLE_DB
	add_child(_music_drive)
	# Start in the garage so clicking the game provides an immediate audio check.
	# Both identically sized loops begin on the same frame and stay synchronized.
	_music_base.play()
	_music_drive.play()


func _make_music_loop(layer: StringName) -> AudioStreamWAV:
	var seconds_per_beat := 60.0 / MUSIC_BPM
	var duration := MUSIC_BEATS * seconds_per_beat
	var sample_count := int(duration * MIX_RATE)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for sample_index: int in sample_count:
		var time := float(sample_index) / float(MIX_RATE)
		var beat := time / seconds_per_beat
		var wave := _render_base_layer(beat, seconds_per_beat, sample_index) if layer == &"BASE" else _render_drive_layer(beat, seconds_per_beat)
		var signed_sample := clampi(int(tanh(wave * 1.18) * 32767.0), -32768, 32767)
		var encoded_sample := signed_sample if signed_sample >= 0 else 65536 + signed_sample
		data[sample_index * 2] = encoded_sample & 0xff
		data[sample_index * 2 + 1] = (encoded_sample >> 8) & 0xff
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = sample_count
	stream.data = data
	return stream


func _render_base_layer(beat: float, seconds_per_beat: float, sample_index: int) -> float:
	var half_step := posmod(int(floor(beat * 2.0)), BASS_PATTERN.size())
	var half_phase := fmod(beat * 2.0, 1.0)
	var bass_note: int = BASS_PATTERN[half_step]
	var bass := 0.0
	if bass_note >= 0:
		var bass_hz := _midi_to_hz(bass_note)
		var bass_time := half_phase * seconds_per_beat * 0.5
		var bass_envelope := minf(half_phase * 18.0, 1.0) * pow(1.0 - half_phase, 0.32)
		var bass_fundamental := sin(bass_time * bass_hz * TAU)
		var bass_sub := sin(bass_time * bass_hz * 0.5 * TAU)
		var bass_body := tanh(bass_fundamental * 1.8)
		bass = (bass_fundamental * 0.56 + bass_sub * 0.30 + bass_body * 0.14) * bass_envelope * 0.34

	var quarter_phase := fmod(beat * 4.0, 1.0)
	var eighth_index := posmod(int(floor(beat * 2.0)), 8)
	var eighth_phase := fmod(beat * 2.0, 1.0)
	var kick_pattern := eighth_index in [0, 3, 4, 7]
	var kick := 0.0
	if kick_pattern:
		var kick_time := eighth_phase * seconds_per_beat * 0.5
		var kick_phase := 42.0 * kick_time + 5.0 * (1.0 - exp(-kick_time * 18.0))
		kick = sin(kick_phase * TAU) * exp(-eighth_phase * 7.0) * 0.50

	var beat_index := posmod(int(floor(beat)), 4)
	var beat_phase := fmod(beat, 1.0)
	var snare := 0.0
	if beat_index in [1, 3]:
		var noise := _chip_noise(sample_index)
		snare = (noise * 0.52 + sin(beat_phase * seconds_per_beat * 142.0 * TAU) * 0.48) * exp(-beat_phase * 13.0) * 0.17

	var hat_noise := _chip_noise(sample_index / 3)
	var hat := hat_noise * exp(-quarter_phase * 24.0) * (0.028 if eighth_index % 2 == 0 else 0.018)
	return bass + kick + snare + hat


func _render_drive_layer(beat: float, seconds_per_beat: float) -> float:
	var half_step := posmod(int(floor(beat * 2.0)), LEAD_PATTERN.size())
	var half_phase := fmod(beat * 2.0, 1.0)
	var lead_note: int = LEAD_PATTERN[half_step]
	var lead := 0.0
	if lead_note >= 0:
		var lead_hz := _midi_to_hz(lead_note - 12)
		var lead_time := half_phase * seconds_per_beat * 0.5
		var lead_envelope := minf(half_phase * 24.0, 1.0) * pow(1.0 - half_phase, 0.6)
		var vibrato := sin(lead_time * 6.1 * TAU) * 0.0035
		var lead_phase := lead_time * lead_hz + vibrato
		lead = (sin(lead_phase * TAU) * 0.62 + _triangle(lead_phase) * 0.28 + _pulse(lead_phase, 0.5) * 0.10) * lead_envelope * 0.23

	var sixteenth_step := posmod(int(floor(beat * 4.0)), 16)
	var sixteenth_phase := fmod(beat * 4.0, 1.0)
	var bar_index := posmod(int(floor(beat / 4.0)), CHORD_ROOTS.size())
	var chord_root: int = CHORD_ROOTS[bar_index]
	var third := 3 if CHORD_QUALITIES[bar_index] == &"MINOR" else 4
	var chord_offsets := [0, third, 7, 12]
	var arp_note: int = chord_root + chord_offsets[posmod(sixteenth_step + bar_index, chord_offsets.size())]
	var arp_hz := _midi_to_hz(arp_note)
	var arp_time := sixteenth_phase * seconds_per_beat * 0.25
	var arp_envelope := pow(1.0 - sixteenth_phase, 1.5)
	var arp := (_triangle(arp_time * arp_hz) * 0.8 + sin(arp_time * arp_hz * TAU) * 0.2) * arp_envelope * 0.028
	return lead + arp


func _midi_to_hz(note: int) -> float:
	return 440.0 * pow(2.0, (float(note) - 69.0) / 12.0)


func _pulse(phase: float, duty: float) -> float:
	return 1.0 if fmod(phase, 1.0) < duty else -1.0


func _chip_noise(seed: int) -> float:
	var value := posmod(seed * 1103515245 + 12345, 2147483647)
	return float(value & 65535) / 32767.5 - 1.0
func _triangle(phase: float) -> float:
	return 1.0 - 4.0 * absf(fmod(phase, 1.0) - 0.5)




func _play(cue: StringName, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	if _voices.is_empty() or not _cues.has(cue):
		return
	var voice := _voices[_voice_index]
	_voice_index = (_voice_index + 1) % _voices.size()
	voice.stream = _cues[cue]
	voice.pitch_scale = pitch
	voice.volume_db = volume_db
	voice.play()


func _on_countdown_changed(value: int) -> void:
	_play(&"go" if value == 0 else &"count", 1.0 + float(3 - value) * 0.04)


func _on_checkpoint_passed(_index: int, _total: int, _split_usec: int) -> void:
	_play(&"gate")


func _on_race_finished(_time_usec: int, _medal: StringName, _is_new_best: bool) -> void:
	_play(&"finish")


func _on_activity_completed(_activity: StringName, _result_value: int, _medal: StringName, _is_new_best: bool) -> void:
	_play(&"finish")


func _on_flow_gained(amount: float) -> void:
	_play(&"flow", lerpf(0.92, 1.12, clampf(amount / 45.0, 0.0, 1.0)), -1.5)


func _on_boost_activated(_flow_remaining: float) -> void:
	_play(&"boost", 1.0, 1.5)


func _on_activity_started(_activity: StringName) -> void:
	_contract_cued = false
	if _music_base == null or _music_drive == null:
		return
	if not _music_base.playing:
		_music_base.play()
		_music_drive.play()


func _on_line_updated(_label: String, chain: int, _multiplier: float, _score: int, _time_left: float) -> void:
	if _music_drive == null:
		return
	var flow_mix := clampf(float(chain) / 6.0, 0.0, 1.0)
	var target_db := lerpf(MUSIC_MELODY_IDLE_DB, MUSIC_MELODY_FLOW_DB, flow_mix)
	if _music_tween != null:
		_music_tween.kill()
	_music_tween = create_tween()
	_music_tween.tween_property(_music_drive, "volume_db", target_db, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if chain >= 3:
		_play(&"flow", 0.9 + float(mini(chain, 8)) * 0.045, -5.0)


func _on_route_discovered(_title: String) -> void:
	_play(&"route", 1.0, 0.5)


func _on_contract_updated(_title: String, _current: int, _target: int, completed: bool) -> void:
	if completed and not _contract_cued:
		_contract_cued = true
		_play(&"contract", 1.0, 1.0)


func _ensure_sfx_bus() -> void:
	if AudioServer.get_bus_index(&"SFX") >= 0:
		return
	AudioServer.add_bus()
	var bus_index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(bus_index, &"SFX")


func _ensure_music_bus() -> void:
	if AudioServer.get_bus_index(&"Music") >= 0:
		return
	AudioServer.add_bus()
	var bus_index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(bus_index, &"Music")
	var low_pass := AudioEffectLowPassFilter.new()
	low_pass.cutoff_hz = 6200.0
	low_pass.resonance = 0.18
	AudioServer.add_bus_effect(bus_index, low_pass)
