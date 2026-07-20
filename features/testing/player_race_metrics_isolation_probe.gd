extends Node3D
## Deterministic ownership regression for field chaos versus player telemetry.
##
## Definition of done:
## - a chaotic NPC-only simulation cannot change player results, Academy metrics,
##   CLEAN_RIDE validity, profile statistics, or PASS_MASTER progress;
## - confirmed player position gains, contact, and crash recovery are retained by
##   those same consumers.

const BIKE_SCENE := preload("res://entities/bike/bike.tscn")
const GHOST_SCENE := preload("res://features/race/ghost_controller.tscn")
const RACE_SCENE := preload("res://features/race/race_controller.tscn")
const PLAYER_PROFILE_SCRIPT := preload("res://common/player_profile.gd")

const STEP := 1.0 / 60.0
const FIELD_SAMPLE_SECONDS := 15.0

var _bike: DirtBikeController
var _ghost: GhostController
var _race: RaceController
var _passed := true


func _ready() -> void:
	Profile.persistence_enabled = false
	print("PLAYER RACE METRICS ISOLATION PROBE: starting")
	_run.call_deferred()


func _run() -> void:
	_bike = BIKE_SCENE.instantiate() as DirtBikeController
	_ghost = GHOST_SCENE.instantiate() as GhostController
	_race = RACE_SCENE.instantiate() as RaceController
	add_child(_bike)
	add_child(_ghost)
	add_child(_race)
	_ghost.persistence_enabled = false
	await _wait_physics_frames(2)
	print("PLAYER RACE METRICS ISOLATION PROBE: runtime ready")

	var route := CourseCatalog.get_world_riding_points(CourseCatalog.QUARRY_ID)
	_race.initialize(_bike, _ghost, CourseCatalog.QUARRY_ID, route, null)
	var npc_case := await _run_npc_only_case(route)
	print("PLAYER RACE METRICS ISOLATION PROBE: NPC case complete")
	var player_case := await _run_player_event_case(route)
	print("PLAYER RACE METRICS ISOLATION PROBE: player case complete")
	_validate_profile_consumers(npc_case[&"result"], player_case[&"result"])

	var field := npc_case.get(&"field", {}) as Dictionary
	print("PLAYER RACE METRICS ISOLATION PROBE: field_overtakes=%d field_contacts=%d field_crashes=%d player=%s passed=%s" % [
		int(field.get(&"field_overtakes", 0)), int(field.get(&"field_contacts", 0)),
		int(field.get(&"field_crashes", 0)), str(player_case.get(&"metrics", {})), str(_passed),
	])
	await _finish_probe()


func _run_npc_only_case(route: PackedVector3Array) -> Dictionary:
	_race.configure_session(_make_session_config(&"NPC_METRIC_ISOLATION", 11), route, null)
	await _start_race()
	_bike.set_motion_locked(true)
	var pack := _race.get_node("RacePack") as RacePack
	# Keep the player registered so pass-order tracking remains live, but suspend
	# the physical bike above its unchanged chainage to remove contact variables.
	var isolated_transform := _bike.global_transform
	isolated_transform.origin.y += 1000.0
	_bike.respawn_at(isolated_transform)
	pack.set_contact_immunity(FIELD_SAMPLE_SECONDS + 1.0)
	pack.set_physics_process(false)
	for _frame: int in ceili(FIELD_SAMPLE_SECONDS / STEP):
		pack.call(&"_physics_process", STEP)
	var field := pack.get_chaos_snapshot()
	var before_finish := _race.get_player_race_metrics_snapshot()
	var field_is_chaotic := (
		int(field.get(&"field_overtakes", 0)) >= 5
		and int(field.get(&"field_contacts", 0)) >= 1
		and int(field.get(&"field_crashes", 0)) >= 1
	)
	var player_untouched := _player_metrics_equal(before_finish, 0, 0, 0, 0)
	_check(field_is_chaotic, "NPC-only field generated chaos", "field=%s" % str(field))
	_check(player_untouched, "NPC-only chaos left player metrics at zero", "metrics=%s" % str(before_finish))

	_finish_current_race()
	var result := _race.get_results_preview()
	var academy := result.get(&"academy_metrics", {}) as Dictionary
	var isolated_result := (
		bool(result.get(&"valid", false))
		and not str(result.get(&"validity_reason", "")).contains("CLEAN_RIDE")
		and int(result.get(&"overtakes", -1)) == 0
		and int(result.get(&"contacts", -1)) == 0
		and int(result.get(&"crashes", -1)) == 0
		and int(result.get(&"recoveries", -1)) == 0
		and int(academy.get(&"crashes", -1)) == 0
		and int(academy.get(&"successful_rejoins", -1)) == 0
		and int(academy.get(&"clean_passes", -1)) == 0
	)
	_check(
		isolated_result,
		"NPC-only chaos excluded from result, Academy, and CLEAN_RIDE",
		"valid=%s player=[o%d c%d x%d r%d] academy=%s" % [
			str(result.get(&"valid", false)), int(result.get(&"overtakes", -1)),
			int(result.get(&"contacts", -1)), int(result.get(&"crashes", -1)),
			int(result.get(&"recoveries", -1)), str(academy),
		]
	)
	return {&"field": field, &"metrics": before_finish, &"result": result, &"passed": field_is_chaotic and player_untouched and isolated_result}


func _run_player_event_case(route: PackedVector3Array) -> Dictionary:
	_race.configure_session(_make_session_config(&"PLAYER_METRIC_EVENTS", 5), route, null)
	var pack := _race.get_node("RacePack") as RacePack
	pack.set_physics_process(true)
	pack.set_player(_bike)
	await _start_race()
	pack.set_contact_immunity(30.0)
	_bike.set_motion_locked(true)
	await _wait_physics_frames(4)

	# Advance through the production route in bounded adjacent chunks.  The old
	# fixture jumped directly to 70% progress, which correctly trips the live cut
	# detector when focused probes run without the runtime-smoke suppression flag.
	# These <=16-sample steps stay inside the integrity envelope while still
	# crossing the field quickly enough to exercise real RacePack pass signals.
	await _advance_player_along_route(route, 0.7)
	await _wait_physics_frames(18)
	var after_pass := _race.get_player_race_metrics_snapshot()
	_check(int(after_pass.get(&"overtakes", 0)) >= 1, "player position gains record overtakes", "metrics=%s" % str(after_pass))

	var contact_applied := _bike.apply_pack_contact(Vector3.RIGHT, 5.0)
	_bike.reset_to_safe_position(DirtBikeController.RECOVERY_TIPPED)
	await _wait_physics_frames(2)
	var player_metrics := _race.get_player_race_metrics_snapshot()
	var player_events_recorded := (
		contact_applied
		and int(player_metrics.get(&"overtakes", 0)) >= 1
		and int(player_metrics.get(&"contacts", 0)) == 1
		and int(player_metrics.get(&"crashes", 0)) == 1
		and int(player_metrics.get(&"recoveries", 0)) == 1
	)
	_check(player_events_recorded, "player-owned events update player telemetry", "metrics=%s contact=%s" % [str(player_metrics), str(contact_applied)])

	_finish_current_race()
	var result := _race.get_results_preview()
	var academy := result.get(&"academy_metrics", {}) as Dictionary
	var result_matches := (
		not bool(result.get(&"valid", true))
		and str(result.get(&"validity_reason", "")).contains("CLEAN_RIDE")
		and int(result.get(&"overtakes", 0)) == int(player_metrics.get(&"overtakes", -1))
		and int(result.get(&"contacts", 0)) == 1
		and int(result.get(&"crashes", 0)) == 1
		and int(result.get(&"recoveries", 0)) == 1
		and int(academy.get(&"crashes", 0)) == 1
		and int(academy.get(&"successful_rejoins", 0)) == 1
		and int(academy.get(&"clean_passes", -1)) == maxi(int(result.get(&"overtakes", 0)) - 1, 0)
	)
	_check(
		result_matches,
		"player events reach result, Academy, and CLEAN_RIDE",
		"valid=%s reason=%s player=[o%d c%d x%d r%d] academy=%s" % [
			str(result.get(&"valid", true)), str(result.get(&"validity_reason", "")),
			int(result.get(&"overtakes", 0)), int(result.get(&"contacts", 0)),
			int(result.get(&"crashes", 0)), int(result.get(&"recoveries", 0)), str(academy),
		]
	)
	return {&"metrics": player_metrics, &"result": result, &"passed": player_events_recorded and result_matches}


func _validate_profile_consumers(npc_result: Dictionary, player_result: Dictionary) -> void:
	var profile: Variant = PLAYER_PROFILE_SCRIPT.new()
	profile.persistence_enabled = false
	profile._apply_profile_dictionary({
		"cash": 0,
		"racer_reputation": 0,
		"current_setup": "BALANCED",
		"unlocked_setups": ["BALANCED"],
		"course_layout_version": profile.COURSE_LAYOUT_VERSION,
	})
	profile._ensure_full_race_defaults()
	profile.race_statistics[&"overtakes"] = 99
	var authorized_npc_result := _authorize_profile_result(profile, npc_result)
	var npc_summary: Dictionary = profile.record_race_result(authorized_npc_result, false)
	_check(bool(npc_summary.get(&"accepted", false)), "NPC telemetry result settles through issued race authority", "summary=%s" % str(npc_summary))
	var after_npc: Dictionary = profile.get_race_statistics() as Dictionary
	var npc_excluded: bool = (
		int(after_npc.get(&"overtakes", -1)) == 99
		and int(after_npc.get(&"contacts", -1)) == 0
		and int(after_npc.get(&"crashes", -1)) == 0
		and not profile.get_achievement_ids().has(&"PASS_MASTER")
	)
	_check(npc_excluded, "NPC-only chaos cannot alter profile stats or PASS_MASTER", "stats=%s achievements=%s" % [str(after_npc), str(profile.get_achievement_ids())])

	var authorized_player_result := _authorize_profile_result(profile, player_result)
	var player_summary: Dictionary = profile.record_race_result(authorized_player_result, false)
	_check(bool(player_summary.get(&"accepted", false)), "invalid player result settles through issued race authority", "summary=%s" % str(player_summary))
	var after_player: Dictionary = profile.get_race_statistics() as Dictionary
	var player_included: bool = (
		# CLEAN_RIDE correctly invalidates this result. Real incidents remain useful
		# audit telemetry, while untrusted performance fields cannot cross an
		# achievement threshold after the classification has been rejected.
		int(after_player.get(&"overtakes", 0)) == 99
		and int(after_player.get(&"contacts", 0)) == 1
		and int(after_player.get(&"crashes", 0)) == 1
		and int(after_player.get(&"resets", 0)) == 1
		and int(after_player.get(&"dsqs", 0)) == 1
		and not profile.get_achievement_ids().has(&"PASS_MASTER")
	)
	_check(
		player_included,
		"invalid player incidents remain audited without performance awards",
		"stats=%s achievements=%s" % [str(after_player), str(profile.get_achievement_ids())]
	)
	profile.free()


func _authorize_profile_result(profile: Variant, source_result: Dictionary) -> Dictionary:
	# The race simulation uses descriptive probe-only session IDs. Profile authority
	# deliberately accepts production catalog events only, so settle the captured
	# telemetry as a CIRCUIT attempt without changing any result metrics.
	var result := source_result.duplicate(true)
	result[&"event_id"] = &"CIRCUIT"
	var signature := str(result.get(&"signature", ""))
	var authority: Dictionary = profile.begin_race_run(&"CIRCUIT", signature)
	_check(bool(authority.get(&"accepted", false)), "Profile issues race authority for captured telemetry", "authority=%s" % str(authority))
	result[&"run_id"] = str(authority.get(&"run_id", ""))
	result[&"signature"] = str(authority.get(&"signature", signature))
	return result


func _make_session_config(event_id: StringName, opponent_count: int) -> RaceSessionConfig:
	return RaceSessionConfig.from_dictionary({
		&"event_id": event_id,
		&"track_id": CourseCatalog.QUARRY_ID,
		&"display_name": "PLAYER METRIC OWNERSHIP",
		&"format": &"SPRINT",
		&"session_type": &"MAIN",
		&"championship_id": &"",
		&"laps": 1,
		&"opponent_count": opponent_count,
		&"checkpoint_count": 6,
		&"countdown_seconds": 0.1,
		&"staging_seconds": 0.0,
		&"finish_grace_seconds": 0.0,
		&"reset_penalty_usec": 2_000_000,
		&"medal_times_usec": {&"gold": 300_000_000, &"silver": 360_000_000, &"bronze": 420_000_000},
		&"rules": {&"modifiers": ["CLEAN_RIDE"]},
	})


func _start_race() -> void:
	_race.reset_run()
	var started := await _wait_for_state(RaceController.State.RACING, 30)
	_check(started, "countdown reaches racing", "state=%d" % _race.state)


func _finish_current_race() -> void:
	for checkpoint_index: int in _race.get_checkpoint_positions().size():
		var gate := _race.get_node("Checkpoint%02d" % checkpoint_index) as Area3D
		gate.emit_signal(&"body_entered", _bike)


func _advance_player_along_route(route: PackedVector3Array, target_ratio: float) -> void:
	if route.size() < 3:
		return
	var target_index := clampi(
		roundi(float(route.size() - 2) * clampf(target_ratio, 0.0, 1.0)),
		1,
		route.size() - 2
	)
	var route_index := 1
	while route_index <= target_index:
		var next_index := mini(route_index + 1, route.size() - 1)
		var forward := (route[next_index] - route[route_index]).normalized()
		_bike.respawn_at(Transform3D(
			Basis.looking_at(forward, Vector3.UP),
			route[route_index] + Vector3.UP
		))
		await get_tree().physics_frame
		route_index += 16


func _player_metrics_equal(metrics: Dictionary, overtakes: int, contacts: int, crashes: int, recoveries: int) -> bool:
	return (
		int(metrics.get(&"overtakes", -1)) == overtakes
		and int(metrics.get(&"contacts", -1)) == contacts
		and int(metrics.get(&"crashes", -1)) == crashes
		and int(metrics.get(&"recoveries", -1)) == recoveries
	)


func _wait_for_state(target: RaceController.State, maximum_frames: int) -> bool:
	for _frame: int in maximum_frames:
		if _race.state == target:
			return true
		await get_tree().physics_frame
	return _race.state == target


func _wait_physics_frames(frame_count: int) -> void:
	for _frame: int in frame_count:
		await get_tree().physics_frame


func _check(condition: bool, label: String, details: String = "") -> void:
	var suffix := "" if details.is_empty() else "  //  %s" % details
	print("PLAYER METRIC CHECK: %s passed=%s%s" % [label, str(condition), suffix])
	if condition:
		return
	_passed = false
	push_error("PLAYER RACE METRICS ISOLATION: %s failed.%s" % [label, suffix])


func _finish_probe() -> void:
	if is_instance_valid(_race):
		_race.set_physics_process(false)
	if is_instance_valid(_bike):
		_bike.set_physics_process(false)
		_bike.shutdown_audio()
	if is_instance_valid(_ghost):
		_ghost.cancel_run()
	if is_instance_valid(_race):
		_race.queue_free()
	if is_instance_valid(_bike):
		_bike.queue_free()
	if is_instance_valid(_ghost):
		_ghost.queue_free()
	for _frame: int in 4:
		await get_tree().process_frame
	get_tree().quit(0 if _passed else 1)
