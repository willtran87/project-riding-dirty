extends Node
## Production-path proof that opponent Flow is mechanically active and that a
## nearby attack reaches sight, sound, captions, and rider identity together.

const STEP := 0.20
const MAX_STEPS := 900
const HUD_SCENE := preload("res://features/hud/race_hud.tscn")

var _failures: Array[String] = []
var _boost_payload: Dictionary = {}
var _race_message := ""
var _captions: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var previous_mode := RaceEventCatalog.get_player_difficulty_mode()
	RaceEventCatalog.set_player_difficulty_mode(&"STANDARD")
	var session := RaceEventCatalog.get_session_config(&"CIRCUIT")
	var pack := RacePack.new()
	pack.presentation_enabled = false
	pack.simulation_has_player = true
	pack.opponent_flow_boosted.connect(_on_pack_boost)
	add_child(pack)
	pack.configure(session.track_id, CourseCatalog.get_world_riding_points(session.track_id), null, session)
	pack.start_race()
	pack.set_physics_process(false)
	var total_distance := pack.get_track_length() * float(session.laps)
	var player_seconds := float(session.medal_times_usec.get(&"gold", 1)) / 1_000_000.0 * 0.71
	var player_speed := total_distance / maxf(player_seconds, 0.001)
	for step: int in MAX_STEPS:
		pack.simulate_competition_step(
			STEP,
			player_speed,
			minf(player_speed * float(step + 1) * STEP, total_distance),
			true
		)
		if not _boost_payload.is_empty():
			break
	_check(not _boost_payload.is_empty(), "production AI never emitted a Flow attack")
	_check(
		not StringName(_boost_payload.get(&"rider_id", &"")).is_empty()
		and not str(_boost_payload.get(&"display_name", "")).is_empty()
		and not str(_boost_payload.get(&"signature_trait", "")).is_empty(),
		"Flow attack omitted persistent rival identity"
	)

	var hud := HUD_SCENE.instantiate() as RaceHud
	add_child(hud)
	var audio := GameplayAudio.new()
	add_child(audio)
	var race := RaceController.new()
	add_child(race)
	await get_tree().process_frame
	race.set_physics_process(false)
	race.state = RaceController.State.RACING
	race.race_moment.connect(_on_race_message)
	race.race_moment.connect(hud.show_race_moment)
	race.race_moment.connect(Callable(audio, &"_on_race_moment"))
	if not EventBus.audio_caption_requested.is_connected(_on_audio_caption_requested):
		EventBus.audio_caption_requested.connect(_on_audio_caption_requested)
	race.call(&"_on_opponent_flow_boosted", &"ROOK", "ROOK MERCER", "LATE-BRAKE PRESSURE", -4.0)
	await get_tree().process_frame
	var hud_message := str(hud.get_control_prompt_snapshot().get(&"message", ""))
	var audio_feedback := audio.get_competition_feedback_snapshot()
	_check(
		_race_message.contains("RIVAL FLOW")
		and _race_message.contains("ROOK MERCER")
		and _race_message.contains("ATTACKING FROM BEHIND")
		and _race_message.contains("LATE-BRAKE PRESSURE"),
		"nearby rival attack did not explain identity, direction, and signature trait"
	)
	_check(hud_message == _race_message, "rival attack did not reach the visual HUD warning")
	_check(
		StringName(audio_feedback.get(&"last_commentary_kind", &"")) == &"WARNING"
		and str(audio_feedback.get(&"last_commentary_context", "")) == _race_message,
		"rival attack did not receive a dedicated warning audio classification"
	)
	_check(
		not _captions.is_empty() and _captions[-1].contains("RIVAL FLOW"),
		"rival attack warning did not request an accessible semantic caption"
	)
	var message_before_distant_attack := _race_message
	race.set("_field_moment_cooldown", 0.0)
	race.call(&"_on_opponent_flow_boosted", &"ROOK", "ROOK MERCER", "LATE-BRAKE PRESSURE", 40.0)
	_check(_race_message == message_before_distant_attack, "distant rival attack spammed the HUD")

	if EventBus.audio_caption_requested.is_connected(_on_audio_caption_requested):
		EventBus.audio_caption_requested.disconnect(_on_audio_caption_requested)
	RaceEventCatalog.set_player_difficulty_mode(previous_mode)
	pack.queue_free()
	hud.queue_free()
	audio.queue_free()
	race.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("RIVAL FLOW FEEDBACK PROBE: boost=%s hud=%s audio=%s caption=%s passed=%s" % [
		str(not _boost_payload.is_empty()), str(hud_message == _race_message),
		str(audio_feedback.get(&"last_commentary_kind", &"")), str(not _captions.is_empty()),
		str(_failures.is_empty()),
	])
	if _failures.is_empty():
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("RIVAL FLOW FEEDBACK PROBE: " + failure)
	get_tree().quit(1)


func _on_pack_boost(rider_id: StringName, display_name: String, signature_trait: String, gap_m: float) -> void:
	if _boost_payload.is_empty():
		_boost_payload = {
			&"rider_id": rider_id,
			&"display_name": display_name,
			&"signature_trait": signature_trait,
			&"gap_m": gap_m,
		}


func _on_race_message(label: String, _points: int, _positive: bool) -> void:
	_race_message = label


func _on_audio_caption_requested(_source: StringName, text: String, _priority: int) -> void:
	_captions.append(text)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
