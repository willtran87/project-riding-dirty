extends Node
class_name GameplayAudio
## Pooled, pre-rendered feedback cues that keep the browser build asset-light.

const MIX_RATE := 22050
const VOICE_COUNT := 5

var _voices: Array[AudioStreamPlayer] = []
var _voice_index: int = 0
var _cues: Dictionary[StringName, AudioStreamWAV] = {}


func _ready() -> void:
	_ensure_sfx_bus()
	for _index: int in VOICE_COUNT:
		var voice := AudioStreamPlayer.new()
		voice.bus = &"SFX"
		add_child(voice)
		_voices.append(voice)
	_build_cues()
	EventBus.race_countdown_changed.connect(_on_countdown_changed)
	EventBus.checkpoint_passed.connect(_on_checkpoint_passed)
	EventBus.race_finished.connect(_on_race_finished)
	EventBus.activity_completed.connect(_on_activity_completed)


func initialize(bike: DirtBikeController) -> void:
	if not bike.flow_gained.is_connected(_on_flow_gained):
		bike.flow_gained.connect(_on_flow_gained)
	if not bike.boost_activated.is_connected(_on_boost_activated):
		bike.boost_activated.connect(_on_boost_activated)


func _exit_tree() -> void:
	for voice: AudioStreamPlayer in _voices:
		voice.stop()
		voice.stream = null
	_voices.clear()
	_cues.clear()


func _build_cues() -> void:
	_cues[&"count"] = _make_sweep(390.0, 390.0, 0.09, 0.34, 0.12)
	_cues[&"go"] = _make_sweep(520.0, 880.0, 0.20, 0.38, 0.18)
	_cues[&"gate"] = _make_sweep(660.0, 920.0, 0.13, 0.32, 0.16)
	_cues[&"flow"] = _make_sweep(540.0, 760.0, 0.16, 0.30, 0.22)
	_cues[&"boost"] = _make_sweep(145.0, 510.0, 0.34, 0.42, 0.34)
	_cues[&"finish"] = _make_sweep(430.0, 860.0, 0.42, 0.38, 0.28)


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


func _ensure_sfx_bus() -> void:
	if AudioServer.get_bus_index(&"SFX") >= 0:
		return
	AudioServer.add_bus()
	var bus_index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(bus_index, &"SFX")
