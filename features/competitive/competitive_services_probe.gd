extends Node
## Deterministic headless contract probe for competitive, replay, ghost, and settings services.

const LEADERBOARD_PATH: String = "user://competitive_probe/leaderboards.json"
const QUEUE_PATH: String = "user://competitive_probe/offline_queue.json"
const SETTINGS_PATH: String = "user://competitive_probe/settings.json"

var _failures: Array[String] = []


func _ready() -> void:
	_cleanup_probe_files()
	_probe_signatures_and_challenges()
	_probe_local_and_http_leaderboards()
	_probe_hotseat()
	_probe_replay_and_ghost()
	_probe_settings()
	_cleanup_probe_files()
	if _failures.is_empty():
		print("COMPETITIVE_SERVICES_PROBE PASS")
		get_tree().quit(0)
	else:
		for failure: String in _failures:
			push_error("COMPETITIVE_SERVICES_PROBE: " + failure)
		get_tree().quit(1)


func _probe_signatures_and_challenges() -> void:
	var context_a := {
		"track_id": "QUARRY",
		"event_id": "DAILY",
		"route_version": 4,
		"format": "TIME_ATTACK",
		"laps": 1,
		"bike_class": "OPEN",
		"difficulty": 3,
		"assist_mode": "STANDARD",
		"setup_id": "BALANCED",
		"modifiers": ["CLEAN_RIDE", "NO_RESETS"],
	}
	var context_b := context_a.duplicate(true)
	context_b["modifiers"] = ["NO_RESETS", "CLEAN_RIDE"]
	_check(CompetitiveRunSignature.build(context_a) == CompetitiveRunSignature.build(context_b), "run signature was not canonical")
	var schedule := ChallengeSchedule.new()
	var daily_a := schedule.daily(1_750_000_000, 2)
	var daily_b := schedule.daily(1_750_000_100, 2)
	var weekly_a := schedule.weekly(1_750_000_000, 2)
	var weekly_b := schedule.weekly(1_750_000_100, 2)
	_check(daily_a == daily_b, "daily challenge changed inside one UTC day")
	_check(weekly_a == weekly_b, "weekly challenge changed inside one UTC week")
	_check(CompetitiveRunSignature.validate(str(daily_a.get("run_signature", ""))), "daily challenge signature invalid")
	_check(schedule.challenge_for_id(str(daily_a.get("challenge_id", "")), 2) == daily_a, "challenge ID did not reproduce its seed")
	_check(_challenge_schedule_is_traversable(schedule), "challenge schedule produced a multi-lap point-to-point route")


func _challenge_schedule_is_traversable(schedule: ChallengeSchedule) -> bool:
	# Sweep more than a full year plus weekly buckets so this protects the
	# generator contract instead of only the current live challenge.
	var start_unix := 1_700_000_000
	for day: int in 400:
		var daily_challenge := schedule.daily(start_unix + day * ChallengeSchedule.DAY_SECONDS, day % 6)
		if not ChallengeSchedule.is_track_format_compatible(
			str(daily_challenge.get("track_id", "")),
			str(daily_challenge.get("format", ""))
		):
			return false
		if str(daily_challenge.get("format", "")) != "CIRCUIT" and int(daily_challenge.get("laps", 0)) != 1:
			return false
	for week: int in 80:
		var weekly_challenge := schedule.weekly(start_unix + week * ChallengeSchedule.WEEK_SECONDS, week % 6)
		if not ChallengeSchedule.is_track_format_compatible(
			str(weekly_challenge.get("track_id", "")),
			str(weekly_challenge.get("format", ""))
		):
			return false
		if str(weekly_challenge.get("format", "")) != "CIRCUIT" and int(weekly_challenge.get("laps", 0)) != 1:
			return false
	return true


func _probe_local_and_http_leaderboards() -> void:
	var signature := _test_signature()
	var provider := LocalLeaderboardProvider.new(LEADERBOARD_PATH)
	var slow := LeaderboardProvider.create_entry(signature, "P1", "ALPHA", 70_000_000, {
		"run_id": "run_alpha_slow", "created_unix": 1_700_000_001,
	})
	var fast := LeaderboardProvider.create_entry(signature, "P2", "BRAVO", 65_000_000, {
		"run_id": "run_bravo_fast", "created_unix": 1_700_000_002,
	})
	var personal_best := LeaderboardProvider.create_entry(signature, "P1", "ALPHA", 62_000_000, {
		"run_id": "run_alpha_best", "created_unix": 1_700_000_003,
	})
	_check(bool(provider.submit_run(slow).get("ok", false)), "local leaderboard rejected valid first run")
	_check(bool(provider.submit_run(fast).get("ok", false)), "local leaderboard rejected valid second run")
	var pb_result := provider.submit_run(personal_best)
	_check(bool(pb_result.get("accepted", false)) and int(pb_result.get("rank", 0)) == 1, "local leaderboard did not replace personal best")
	var board := provider.fetch_board(signature, 10)
	_check(int(board.get("total", 0)) == 2, "local leaderboard did not retain one best run per profile")
	var reloaded := LocalLeaderboardProvider.new(LEADERBOARD_PATH)
	var reloaded_board := reloaded.fetch_board(signature, 10)
	_check(int(reloaded_board.get("total", 0)) == 2, "local leaderboard did not persist")

	var online := HttpLeaderboardProvider.new("", QUEUE_PATH)
	var queued := online.submit_run(fast)
	_check(bool(queued.get("queued", false)) and online.pending_count() == 1, "offline HTTP run was not queued")
	online.configure("https://leaderboards.invalid", _fake_transport)
	var flushed := online.flush_pending()
	_check(int(flushed.get("submitted", 0)) == 1 and online.pending_count() == 0, "HTTP queue did not flush through transport")


func _probe_hotseat() -> void:
	var schedule := ChallengeSchedule.new()
	var challenge := schedule.daily(1_750_000_000, 1)
	var hotseat := HotSeatChallengeState.new()
	var configured := hotseat.configure(challenge, [
		{"profile_id": "P1", "display_name": "ALPHA"},
		{"profile_id": "P2", "display_name": "BRAVO"},
	], 1)
	_check(bool(configured.get("ok", false)), "hot-seat setup failed")
	var signature := str(challenge.get("run_signature", ""))
	var first := LeaderboardProvider.create_entry(signature, "P1", "ALPHA", 70_000_000, {
		"run_id": "hotseat_alpha", "created_unix": 1_750_000_010,
		"challenge_id": challenge.get("challenge_id", ""),
	})
	var second := LeaderboardProvider.create_entry(signature, "P2", "BRAVO", 66_000_000, {
		"run_id": "hotseat_bravo", "created_unix": 1_750_000_020,
		"challenge_id": challenge.get("challenge_id", ""),
	})
	_check(bool(hotseat.submit_attempt(first).get("ok", false)), "hot-seat first attempt rejected")
	_check(bool(hotseat.submit_attempt(second).get("ok", false)) and hotseat.is_complete(), "hot-seat did not complete")
	var standings := hotseat.standings()
	_check(str(standings[0].get("profile_id", "")) == "P2", "hot-seat standings ranked incorrectly")
	var restored := HotSeatChallengeState.from_dictionary(hotseat.to_dictionary())
	_check(restored.is_complete() and restored.standings() == standings, "hot-seat state did not round-trip")


func _probe_replay_and_ghost() -> void:
	var recorder := ReplayRecorder.new()
	recorder.begin({"track_id": "QUARRY", "run_signature": _test_signature()}, 20_000)
	_check(recorder.capture(0.0, _bike_state(0.0)), "replay rejected initial state")
	for index in range(1, 6):
		_check(recorder.capture(0.02, _bike_state(float(index))), "replay rejected state %d" % index)
		if index == 3:
			recorder.mark_event(&"JUMP", {"height": 2.5})
	var model := recorder.finish()
	_check(model.is_valid() and model.samples.size() == 6 and model.duration_usec == 100_000, "fixed replay sampling invalid")
	var playback := ReplayPlayback.new()
	_check(playback.load_model(model), "replay playback rejected model")
	var midpoint := playback.seek_usec(50_000)
	_check(is_equal_approx((midpoint.get("position", Vector3.ZERO) as Vector3).x, 2.5), "replay interpolation incorrect")
	playback.reset()
	playback.play()
	var advanced := playback.advance(0.07)
	_check((advanced.get("events", []) as Array).size() == 1, "replay event marker was not emitted")

	var ghost := GhostPayload.build(
		_test_signature(), "QUARRY", 1, model.sample_interval_usec,
		model.ghost_samples(), model.events, {"rider": "ALPHA"}
	)
	var exported := GhostPayload.export_json(ghost)
	_check(bool(exported.get("ok", false)), "valid ghost did not export")
	var imported := GhostPayload.import_json(str(exported.get("json", "")))
	_check(bool(imported.get("ok", false)), "valid ghost did not import: %s" % str(imported.get("error", "unknown")))
	var tampered := ghost.duplicate(true)
	tampered["duration_usec"] = int(tampered.get("duration_usec", 0)) + 1
	_check(not bool(GhostPayload.validate(tampered).get("ok", false)), "tampered ghost passed validation")


func _probe_settings() -> void:
	var store := SettingsStore.new(SETTINGS_PATH)
	_check(store.set_value(&"camera", &"fov_degrees", 92.0), "valid FOV setting rejected")
	_check(store.set_value(&"controls", &"steering_deadzone", 0.2), "valid deadzone setting rejected")
	_check(not store.set_value(&"controls", &"steering_deadzone", 2.0), "invalid deadzone setting accepted")
	_check(store.set_value(&"feedback", &"haptics_enabled", false), "haptics setting rejected")
	_check(store.set_value(&"interface", &"text_scale", 1.25), "text scale setting rejected")
	_check(store.set_value(&"interface", &"high_contrast", true), "high contrast setting rejected")
	_check(store.set_value(&"interface", &"color_safe_mode", "DEUTERANOPIA"), "color-safe setting rejected")
	_check(store.set_value(&"interface", &"units", "METRIC"), "unit setting rejected")
	var throttle_key := InputEventKey.new()
	throttle_key.physical_keycode = KEY_W
	var throttle_events: Array[InputEvent] = [throttle_key]
	_check(bool(store.set_bindings(&"throttle", throttle_events).get("ok", false)), "binding serialization failed")
	var brake_key := InputEventKey.new()
	brake_key.physical_keycode = KEY_W
	var conflicts := store.find_conflicts(&"brake", brake_key)
	_check(conflicts.size() == 1 and str(conflicts[0].get("action", "")) == "throttle", "binding conflict was not detected")
	_check(store.save_to_disk(), "settings did not save")
	var restored := SettingsStore.new(SETTINGS_PATH)
	_check(bool(restored.load_from_disk().get("ok", false)), "settings did not load")
	_check(is_equal_approx(float(restored.get_value(&"camera", &"fov_degrees", 0.0)), 92.0), "FOV did not persist")
	_check(restored.bindings_for_action(&"throttle").size() == 1, "binding did not persist")


func _test_signature() -> String:
	return CompetitiveRunSignature.build({
		"event_id": "PROBE",
		"track_id": "QUARRY",
		"route_version": 1,
		"format": "TIME_ATTACK",
		"laps": 1,
		"bike_class": "OPEN",
		"difficulty": 2,
		"assist_mode": "STANDARD",
		"setup_id": "BALANCED",
	})


func _bike_state(x_position: float) -> Dictionary:
	return {
		"position": Vector3(x_position, 1.0, 0.0),
		"rotation": Quaternion.IDENTITY,
		"linear_velocity": Vector3(50.0, 0.0, 0.0),
		"angular_velocity": Vector3.ZERO,
		"speed_mps": 50.0,
		"progress": x_position / 5.0,
		"input": {"throttle": 1.0, "brake": 0.0, "steer": 0.1, "preload": 0.0},
	}


func _fake_transport(_method: String, _url: String, _payload: Dictionary) -> Dictionary:
	return {"ok": true, "accepted": true, "entries": []}


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _cleanup_probe_files() -> void:
	for path: String in [
		LEADERBOARD_PATH, LEADERBOARD_PATH + ".tmp", LEADERBOARD_PATH + ".bak", QUEUE_PATH,
		SETTINGS_PATH, SETTINGS_PATH + SettingsStore.TEMP_SUFFIX,
		SETTINGS_PATH + SettingsStore.BACKUP_SUFFIX, SETTINGS_PATH + SettingsStore.BACKUP_TEMP_SUFFIX,
	]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
