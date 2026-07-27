extends Node
## Deterministic contract for event-correct, collision-free sponsor landmarks.

const PRESENTER_SCRIPT := preload(
	"res://features/presentation/sponsor_trackside_presenter.gd"
)

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var presenter := PRESENTER_SCRIPT.new() as SponsorTracksidePresenter
	add_child(presenter)
	var route := PackedVector3Array([
		Vector3(0.0, 2.0, 0.0),
		Vector3(0.0, 2.0, -50.0),
		Vector3(0.0, 4.0, -100.0),
	])
	var expected := {
		&"CIRCUIT": {
			&"sponsor_id": &"DUSTLINE",
			&"name": "DUSTLINE WORKS",
			&"identity": "RACE PRECISION",
			&"accent": "FFB52D",
		},
		&"PINE_ENDURO": {
			&"sponsor_id": &"WILDBRUSH",
			&"name": "WILDBRUSH OUTPOST",
			&"identity": "TERRAIN READING",
			&"accent": "9FC744",
		},
		&"MESA_RHYTHM": {
			&"sponsor_id": &"SUNDOWN",
			&"name": "SUNDOWN STATIC",
			&"identity": "EXPRESSIVE LINES",
			&"accent": "FF6F91",
		},
	}
	for activity_id: StringName in expected:
		presenter.configure(activity_id, route, 10.0)
		var snapshot := presenter.get_presentation_snapshot()
		var contract := expected[activity_id] as Dictionary
		_check(
			bool(snapshot.get(&"visible", false))
				and StringName(snapshot.get(&"activity_id", &"")) == activity_id
				and StringName(snapshot.get(&"sponsor_id", &""))
					== StringName(contract.get(&"sponsor_id", &""))
				and str(snapshot.get(&"sponsor_name", "")) == str(contract.get(&"name", ""))
				and str(snapshot.get(&"identity", "")) == str(contract.get(&"identity", ""))
				and str(snapshot.get(&"accent_hex", "")) == str(contract.get(&"accent", ""))
				and int(snapshot.get(&"landmark_count", 0)) == 2,
			"%s omitted its authored sponsor identity" % String(activity_id)
		)
		_check(
			int(snapshot.get(&"collision_count", -1)) == 0,
			"%s sponsor treatment added gameplay collision" % String(activity_id)
		)
		_check_landmark_geometry(presenter, activity_id)
		_check_route_clearance(snapshot, activity_id, 10.0)

	presenter.configure(&"FREESTYLE", route, 12.0)
	var freestyle := presenter.get_presentation_snapshot()
	var freestyle_positions := freestyle.get(&"landmark_positions", []) as Array
	_check(
		StringName(freestyle.get(&"sponsor_id", &"")) == &"SUNDOWN"
			and freestyle_positions.size() == 2
			and absf((freestyle_positions[0] as Vector3).z - (freestyle_positions[1] as Vector3).z)
				>= 20.0,
		"Freestyle did not receive a bounded open-area Sundown treatment"
	)

	for isolated_activity: StringName in [&"ACADEMY", &"BIKE_TEST_RIDE"]:
		presenter.configure(isolated_activity, route, 10.0)
		var isolated := presenter.get_presentation_snapshot()
		_check(
			not bool(isolated.get(&"visible", true))
				and StringName(isolated.get(&"sponsor_id", &"INVALID")).is_empty()
				and int(isolated.get(&"landmark_count", -1)) == 0
				and presenter.get_child_count() == 0,
			"%s incorrectly received a commercial sponsor treatment"
				% String(isolated_activity)
		)

	var main_source := FileAccess.get_file_as_string("res://scenes/main.gd")
	var web_source := FileAccess.get_file_as_string("res://common/web_game_text_state.gd")
	_check(
		main_source.contains("_configure_sponsor_trackside(activity, hud_route, track_id)")
			and main_source.contains("&\"trackside_sponsor\": get_sponsor_trackside_snapshot()"),
		"Main activity composition omitted the trackside sponsor presenter"
	)
	_check(
		web_source.contains("_trackside_sponsor_projection")
			and web_source.contains("MAX_TRACKSIDE_LANDMARKS"),
		"Browser-readable state omitted bounded sponsor observability"
	)

	if _failures.is_empty():
		print(
			"SPONSOR TRACKSIDE PRESENTATION PROBE: PASS // "
			+ "dustline/wildbrush/sundown=2 landmarks open_area=true "
			+ "collision_free=true academy_isolated=true schema=5"
		)
	else:
		for failure: String in _failures:
			push_error("SPONSOR TRACKSIDE PRESENTATION PROBE: " + failure)
	presenter.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check_landmark_geometry(
	presenter: SponsorTracksidePresenter,
	activity_id: StringName
) -> void:
	var landmarks := presenter.find_children(
		"SponsorLandmark*", "Node3D", false, false
	)
	_check(
		landmarks.size() == 2,
		"%s created an unexpected number of landmark roots" % String(activity_id)
	)
	for index: int in landmarks.size():
		var landmark_value := landmarks[index]
		var landmark := landmark_value as Node3D
		var title := landmark.find_child("SponsorName", true, false) as Label3D
		var identity := landmark.find_child("SponsorIdentity", true, false) as Label3D
		var board := landmark.find_child("Board", true, false) as MeshInstance3D
		_check(
			title != null
				and not title.text.is_empty()
				and identity != null
				and identity.text.contains("//")
				and board != null
				and board.cast_shadow
					== GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"%s landmark omitted readable low-cost board geometry"
				% String(activity_id)
		)
		_check(
			StringName(landmark.get_meta(&"layout", &"")) == (
				&"OVERHEAD_ARCH" if index == 0 else &"TRACKSIDE_BOARD"
			),
			"%s landmark used the wrong route-safe layout" % String(activity_id)
		)


func _check_route_clearance(
	snapshot: Dictionary,
	activity_id: StringName,
	track_width: float
) -> void:
	var positions := snapshot.get(&"landmark_positions", []) as Array
	for index: int in positions.size():
		var raw_position: Variant = positions[index]
		var position := raw_position as Vector3
		_check(
			(
				absf(position.x) <= 0.01 and position.y >= 8.4
				if index == 0
				else absf(position.x) >= track_width * 0.5 + 5.0
					and position.y >= 4.6
			),
			"%s landmark intruded into the ride corridor" % String(activity_id)
		)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
