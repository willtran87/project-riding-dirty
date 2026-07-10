extends AudioStreamPlayer3D
## Lightweight synthesized engine loop; no external audio asset is required.

const MIX_RATE: float = 22050.0

var _playback: AudioStreamGeneratorPlayback
var _phase: float = 0.0
var _speed_mps: float = 0.0
var _throttle: float = 0.0
var _grounded: bool = true


func _ready() -> void:
	if &"--smoke-test" in OS.get_cmdline_user_args():
		return
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = MIX_RATE
	generator.buffer_length = 0.18
	stream = generator
	playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	unit_size = 18.0
	max_distance = 55.0
	volume_db = -10.0
	play()
	_playback = get_stream_playback() as AudioStreamGeneratorPlayback


func _process(_delta: float) -> void:
	if _playback == null:
		return
	var frame_count := _playback.get_frames_available()
	var rpm_factor := clampf(_speed_mps / 24.0, 0.0, 1.0)
	var frequency := 48.0 + rpm_factor * 105.0 + _throttle * 42.0
	if not _grounded:
		frequency += 18.0 * _throttle
	var amplitude := 0.07 + _throttle * 0.13 + rpm_factor * 0.06
	for _frame_index: int in frame_count:
		_phase = fmod(_phase + frequency / MIX_RATE, 1.0)
		var fundamental := sin(_phase * TAU)
		var harmonic := sin(_phase * TAU * 2.0) * 0.45
		var rasp := sin(_phase * TAU * 4.0) * 0.12
		var sample := clampf((fundamental + harmonic + rasp) * amplitude, -0.7, 0.7)
		_playback.push_frame(Vector2(sample, sample))


func _exit_tree() -> void:
	shutdown()


func shutdown() -> void:
	stop()
	_playback = null
	stream = null


func set_engine_state(speed_mps: float, throttle: float, grounded: bool) -> void:
	_speed_mps = speed_mps
	_throttle = throttle
	_grounded = grounded
