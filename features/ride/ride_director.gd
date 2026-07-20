extends Node3D
class_name RideDirector
## Owns run-scoped line chains, route mastery, daily modifiers, and sponsor contracts.

signal line_updated(label: String, chain: int, multiplier: float, score: int, time_left: float)
signal contract_updated(title: String, current: int, target: int, completed: bool)
signal modifier_updated(title: String, description: String)
signal route_discovered(title: String)
signal feat_unlocked(title: String)

const CHAIN_WINDOW := 4.5
const CONTRACT_RETRY_INTERVAL := 1.0
const ROUTES: Array[Dictionary] = [
	# Quarry route gates now reward committed main-line sections. Their former
	# locations sat on removed optional branches and visually instructed riders
	# to leave the contained course.
	{&"activity": &"CIRCUIT", &"name": "CANYON CUT", &"position": Vector3(-228.5, 41.7, 28.0), &"yaw": 2.970, &"color": Color("56d6ff")},
	{&"activity": &"CIRCUIT", &"name": "BENCH LINE", &"position": Vector3(77.5, 51.7, -217.5), &"yaw": 1.357, &"color": Color("ffb52d")},
	{&"activity": &"FREESTYLE", &"name": "EXCAVATOR GAP", &"position": Vector3(-24.0, 1.2, -39.0), &"color": Color("56d6ff")},
	{&"activity": &"FREESTYLE", &"name": "TABLE TRANSFER", &"position": Vector3(51.0, 1.2, 20.0), &"color": Color("ffb52d")},
	{&"activity": &"DISCOVERY", &"name": "CLIFF CUT", &"position": Vector3(-47.0, 1.2, 11.0), &"color": Color("56d6ff")},
	{&"activity": &"DISCOVERY", &"name": "SERVICE ROAD", &"position": Vector3(57.0, 1.2, -34.0), &"color": Color("ffb52d")},
	{&"activity": &"PINE_ENDURO", &"name": "CREEK SKIP", &"position": Vector3(1770.0, 39.2, 160.0), &"yaw": -2.737, &"color": Color("56d6ff")},
	{&"activity": &"PINE_ENDURO", &"name": "RIDGE THREAD", &"position": Vector3(1370.0, 109.2, 35.0), &"yaw": 1.869, &"color": Color("ffb52d")},
]

const NEAR_MISSES: Dictionary[StringName, Array] = {
	&"CIRCUIT": [Vector3(-222.0, 45.8, -10.0), Vector3(-98.0, 66.8, -143.0), Vector3(205.0, 40.3, -125.0)],
	&"FREESTYLE": [Vector3(-11.0, 0.8, -4.0), Vector3(53.0, 0.8, 11.0), Vector3(-31.0, 0.8, -55.0)],
	&"DISCOVERY": [Vector3(-56.0, 0.8, 25.0), Vector3(58.0, 0.8, 36.0), Vector3(4.0, 0.8, -64.0)],
	&"PINE_ENDURO": [Vector3(1575.0, 55.8, 170.0), Vector3(1410.0, 100.8, -30.0), Vector3(1085.0, 42.8, -220.0)],
}

const SURFACES: Array[Dictionary] = [
	{&"activity": &"FREESTYLE", &"surface": &"MUD", &"position": Vector3(-8.0, 0.12, -16.0), &"size": Vector3(18.0, 2.5, 18.0), &"color": Color(0.22, 0.13, 0.08, 0.52)},
	{&"activity": &"DISCOVERY", &"surface": &"GRAVEL", &"position": Vector3(-48.0, 0.12, 10.0), &"size": Vector3(16.0, 2.5, 22.0), &"color": Color(0.42, 0.4, 0.38, 0.42)},
]

var _bike: DirtBikeController
var _active: bool = false
var _activity: StringName = &"CIRCUIT"
var _chain: int = 0
var _line_score: int = 0
var _chain_time: float = 0.0
var _visited_routes: Dictionary[String, bool] = {}
var _near_miss_hits: Dictionary[int, bool] = {}
var _route_areas: Array[Area3D] = []
var _surface_areas: Array[Area3D] = []
var _modifier: StringName = &"TAILWIND"
var _contract_title: String = ""
var _contract_kind: StringName = &"CLEAN"
var _contract_progress: int = 0
var _contract_target: int = 2
var _contract_complete: bool = false
var _contract_id: String = ""
var _contract_retry_time: float = 0.0
var _pending_contracts: Dictionary[String, Dictionary] = {}
var _pending_feats: Dictionary[String, String] = {}
var _feat_retry_time: float = 0.0
var _no_reset: bool = true
var _initial_prompt_time: float = 0.0
var _line_enabled: bool = true
var _contract_enabled: bool = true
var _modifier_enabled: bool = true


func _ready() -> void:
	_build_route_gates()
	_build_surface_zones()
	EventBus.activity_started.connect(_on_activity_started)
	EventBus.race_reset.connect(_on_race_reset)
	EventBus.race_finished.connect(_on_run_finished)
	EventBus.race_results_ready.connect(_on_race_results_ready)
	EventBus.activity_completed.connect(_on_activity_completed)


func _physics_process(delta: float) -> void:
	_retry_pending_contract(delta)
	_retry_pending_feat(delta)
	if not _active or _bike == null:
		return
	if _line_enabled and _initial_prompt_time > 0.0:
		_initial_prompt_time = maxf(_initial_prompt_time - delta, 0.0)
		if _initial_prompt_time <= 0.0 and _chain == 0 and _line_score == 0:
			line_updated.emit("", 0, 1.0, 0, 0.0)
	if _chain_time > 0.0:
		_chain_time = maxf(_chain_time - delta, 0.0)
		if _chain_time <= 0.0:
			_chain = 0
			line_updated.emit("", 0, 1.0, _line_score, 0.0)
	_check_near_misses()


func initialize(bike: DirtBikeController) -> void:
	_bike = bike
	if not bike.style_event.is_connected(_on_style_event):
		bike.style_event.connect(_on_style_event)
	if not bike.respawned.is_connected(_on_bike_respawned):
		bike.respawned.connect(_on_bike_respawned)


func get_line_score() -> int:
	return _line_score


func get_contract_progress() -> int:
	return _contract_progress


func get_modifier() -> StringName:
	return _modifier


func get_presentation_snapshot() -> Dictionary:
	return {
		&"activity": _activity,
		&"line_enabled": _line_enabled,
		&"contract_enabled": _contract_enabled,
		&"modifier_enabled": _modifier_enabled,
		&"modifier": _modifier,
	}


func register_competition_event(label: String, base_points: int, positive: bool) -> void:
	if not _active or not _line_enabled or _activity not in RaceEventCatalog.RACE_EVENTS or not positive or base_points <= 0:
		return
	_register_line_event(label, base_points)


func get_route_positions(activity: StringName) -> Array[Vector3]:
	var positions: Array[Vector3] = []
	for route: Dictionary in ROUTES:
		if route.get(&"activity", &"NONE") == activity:
			positions.append(route.get(&"position", Vector3.ZERO))
	return positions


func get_first_route_transform(activity: StringName) -> Transform3D:
	for route: Dictionary in ROUTES:
		if route.get(&"activity", &"NONE") != activity:
			continue
		var yaw := float(route.get(&"yaw", 0.0))
		var direction := Vector3(sin(yaw), 0.0, cos(yaw)).normalized()
		return Transform3D(Basis.looking_at(direction, Vector3.UP), route.get(&"position", Vector3.ZERO))
	return Transform3D.IDENTITY


func _on_activity_started(activity: StringName) -> void:
	_activity = activity
	var presentation := get_activity_presentation_policy(activity)
	_line_enabled = bool(presentation.get(&"show_line_feedback", true))
	_contract_enabled = bool(presentation.get(&"show_sponsor_contract", true))
	_modifier_enabled = bool(presentation.get(&"show_daily_modifier", true))
	_active = true
	_chain = 0
	_line_score = 0
	_chain_time = 0.0
	_visited_routes.clear()
	_near_miss_hits.clear()
	_no_reset = true
	_initial_prompt_time = 3.0 if _line_enabled else 0.0
	if _modifier_enabled:
		_select_daily_modifier()
	else:
		_modifier = &"STANDARD"
		modifier_updated.emit("", "")
	if _contract_enabled:
		_select_contract()
	else:
		_disable_contract()
	_set_route_visibility()
	_set_surface_visibility()
	_bike.apply_run_modifier(_modifier)
	line_updated.emit("BUILD THE LINE" if _line_enabled else "", 0, 1.0, 0, 0.0)
	contract_updated.emit(_contract_title, 0, _contract_target, false)


func _on_race_reset() -> void:
	_active = false
	_chain = 0
	_chain_time = 0.0
	_initial_prompt_time = 0.0
	_set_route_visibility()
	_set_surface_visibility()
	if _bike != null:
		_bike.apply_run_modifier(&"STANDARD")
		_bike.set_surface(&"PACKED")


func _on_run_finished(_time_usec: int, _medal: StringName, _is_new_best: bool) -> void:
	if _active and _line_enabled and _no_reset:
		# Bank the flawless bonus silently: the finish card owns the screen now.
		_line_score += 500
		_award_feat("IRON_LINE", "IRON LINE  //  NO-RESET FINISH")
	_active = false
	_set_route_visibility()
	_set_surface_visibility()
	_bike.set_surface(&"PACKED")


func _on_race_results_ready(_result: Dictionary) -> void:
	# A classified finish already ended the director through race_finished. Loss
	# results such as elimination bypass that success signal and still need to
	# retire run-scoped routes, modifiers, and score processing.
	if not _active:
		return
	_active = false
	_set_route_visibility()
	_set_surface_visibility()
	if _bike != null:
		_bike.apply_run_modifier(&"STANDARD")
		_bike.set_surface(&"PACKED")


func _on_activity_completed(_summary: Dictionary) -> void:
	_active = false
	_set_route_visibility()
	_set_surface_visibility()
	if _bike != null:
		_bike.set_surface(&"PACKED")


func _on_bike_respawned() -> void:
	if not _active:
		return
	_no_reset = false
	_chain = 0
	_chain_time = 0.0
	if _line_enabled:
		line_updated.emit("LINE BROKEN", 0, 1.0, _line_score, 0.0)


func _on_style_event(label: StringName, base_points: int) -> void:
	if not _active:
		return
	if _line_enabled:
		_register_line_event(String(label), base_points)
	if _line_enabled and _chain >= 4:
		_award_feat("CHAIN_REACTION", "CHAIN REACTION  //  FOUR-MOVE LINE")
	if not _contract_enabled:
		return
	if _contract_kind == &"CLEAN" and label == &"CLEAN LANDING":
		_contract_progress += 1
	elif _contract_kind == &"CHAIN":
		_contract_progress = maxi(_contract_progress, _chain)
	_update_contract()


func _register_line_event(label: String, base_points: int) -> void:
	_chain = mini(_chain + 1, 12)
	_chain_time = CHAIN_WINDOW
	var multiplier := 1.0 + float(mini(_chain - 1, 6)) * 0.25
	_line_score += int(round(float(base_points) * multiplier))
	line_updated.emit(label, _chain, multiplier, _line_score, _chain_time)


func _update_contract() -> void:
	_contract_progress = mini(_contract_progress, _contract_target)
	if not _contract_complete and _contract_progress >= _contract_target:
		_contract_complete = (
			Profile.complete_contract(_contract_id, _activity)
			or Profile.completed_contracts.has(_contract_id)
		)
		_contract_retry_time = 0.0 if _contract_complete else CONTRACT_RETRY_INTERVAL
		if _contract_complete:
			_pending_contracts.erase(_contract_id)
		else:
			_pending_contracts[_contract_id] = {
				&"contract_id": _contract_id,
				&"activity": _activity,
				&"title": _contract_title,
				&"current": _contract_progress,
				&"target": _contract_target,
			}
	contract_updated.emit(_contract_title, _contract_progress, _contract_target, _contract_complete)


func _retry_pending_contract(delta: float) -> void:
	if _pending_contracts.is_empty():
		return
	_contract_retry_time = maxf(_contract_retry_time - delta, 0.0)
	if _contract_retry_time > 0.0:
		return
	var contract_id: String = _pending_contracts.keys()[0]
	var pending: Dictionary = _pending_contracts[contract_id]
	var activity := StringName(pending.get(&"activity", &""))
	var settled := (
		Profile.completed_contracts.has(contract_id)
		or Profile.complete_contract(contract_id, activity)
	)
	if not settled:
		_contract_retry_time = CONTRACT_RETRY_INTERVAL
		return
	var completed := pending.duplicate(true)
	_pending_contracts.erase(contract_id)
	_contract_retry_time = 0.0
	if contract_id == _contract_id:
		_contract_complete = true
		contract_updated.emit(
			str(completed.get(&"title", _contract_title)),
			int(completed.get(&"current", _contract_progress)),
			int(completed.get(&"target", _contract_target)),
			true
		)
	if not _pending_contracts.is_empty():
		_contract_retry_time = CONTRACT_RETRY_INTERVAL


func _select_daily_modifier() -> void:
	var date := Time.get_date_dict_from_system()
	var day_seed := int(date.get("year", 2026)) * 372 + int(date.get("month", 1)) * 31 + int(date.get("day", 1))
	match posmod(day_seed, 3):
		0:
			_modifier = &"TAILWIND"
			modifier_updated.emit("TAILWIND", "+12% drive force")
		1:
			_modifier = &"FLOW_SURGE"
			modifier_updated.emit("FLOW SURGE", "+28% Flow from clean landings")
		_:
			_modifier = &"LOOSE_DIRT"
			modifier_updated.emit("LOOSE DIRT", "Less lateral grip, richer style lines")


func _select_contract() -> void:
	match _activity:
		&"FREESTYLE":
			_contract_title = "SPONSOR: CHAIN 4 MOVES"
			_contract_kind = &"CHAIN"
			_contract_target = 4
		&"DISCOVERY":
			_contract_title = "SPONSOR: FIND 2 SECRET LINES"
			_contract_kind = &"ROUTE"
			_contract_target = 2
		_:
			_contract_title = "SPONSOR: LAND 2 CLEAN JUMPS"
			_contract_kind = &"CLEAN"
			_contract_target = 2
	_contract_progress = 0
	_contract_complete = false
	_contract_retry_time = 0.0
	var date := Time.get_date_dict_from_system()
	_contract_id = "%04d-%02d-%02d_%s_%s" % [int(date.get("year", 2026)), int(date.get("month", 1)), int(date.get("day", 1)), String(_activity), String(_contract_kind)]
	if Profile.completed_contracts.has(_contract_id):
		_contract_progress = _contract_target
		_contract_complete = true


func _disable_contract() -> void:
	_contract_title = ""
	_contract_kind = &"NONE"
	_contract_progress = 0
	_contract_target = 0
	_contract_complete = false
	_contract_id = ""
	_contract_retry_time = 0.0


static func get_activity_presentation_policy(activity: StringName) -> Dictionary:
	if activity != &"ACADEMY":
		return {
			&"show_line_feedback": true,
			&"show_sponsor_contract": true,
			&"show_daily_modifier": true,
		}
	var lesson := RaceEventCatalog.get_active_academy_lesson()
	var value: Variant = lesson.get(&"presentation", {})
	var source := value as Dictionary if value is Dictionary else {}
	return {
		&"show_line_feedback": bool(source.get(&"show_line_feedback", false)),
		&"show_sponsor_contract": bool(source.get(&"show_sponsor_contract", false)),
		&"show_daily_modifier": bool(source.get(&"show_daily_modifier", false)),
	}


func _check_near_misses() -> void:
	if not _line_enabled:
		return
	var positions: Array = NEAR_MISSES.get(_activity, [])
	if _bike.get_speed_mps() < 10.0:
		return
	for index: int in positions.size():
		if _near_miss_hits.has(index):
			continue
		var position: Vector3 = positions[index]
		if _bike.global_position.distance_squared_to(position) <= 5.3:
			_near_miss_hits[index] = true
			_register_line_event("NEAR MISS", 260)


func _build_route_gates() -> void:
	for route_index: int in ROUTES.size():
		var route: Dictionary = ROUTES[route_index]
		var area := Area3D.new()
		area.name = "RouteGate%02d" % route_index
		area.position = route.get(&"position", Vector3.ZERO)
		area.rotation.y = float(route.get(&"yaw", 0.0))
		area.collision_layer = 0
		area.collision_mask = 1
		area.monitoring = true
		area.set_meta(&"activity", route.get(&"activity", &"CIRCUIT"))
		area.set_meta(&"route_name", route.get(&"name", "SECRET LINE"))
		add_child(area)
		var shape := BoxShape3D.new()
		shape.size = Vector3(7.0, 5.0, 3.0)
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.position.y = 1.0
		area.add_child(collision)
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.emission_enabled = true
		material.albedo_color = route.get(&"color", Color("56d6ff"))
		material.emission = material.albedo_color
		material.emission_energy_multiplier = 2.2
		_add_gate_post(area, Vector3(-3.4, 1.0, 0.0), material)
		_add_gate_post(area, Vector3(3.4, 1.0, 0.0), material)
		var label := Label3D.new()
		label.text = String(route.get(&"name", "SECRET LINE"))
		label.position = Vector3(0.0, 3.5, 0.0)
		label.font_size = 30
		label.outline_size = 8
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = material.albedo_color
		area.add_child(label)
		area.body_entered.connect(_on_route_entered.bind(area))
		_route_areas.append(area)
	_set_route_visibility()


func _add_gate_post(parent: Node3D, position: Vector3, material: StandardMaterial3D) -> void:
	var box := BoxMesh.new()
	box.size = Vector3(0.16, 3.3, 0.16)
	var mesh := MeshInstance3D.new()
	mesh.mesh = box
	mesh.position = position
	mesh.material_override = material
	parent.add_child(mesh)


func _on_route_entered(body: Node3D, area: Area3D) -> void:
	if not _active or body != _bike or area.get_meta(&"activity", &"NONE") != _activity:
		return
	var route_name := String(area.get_meta(&"route_name", "SECRET LINE"))
	if _visited_routes.has(route_name):
		return
	_visited_routes[route_name] = true
	area.visible = false
	area.set_deferred(&"monitoring", false)
	_register_line_event("ROUTE: %s" % route_name, 340)
	route_discovered.emit(route_name)
	if _visited_routes.size() >= 2:
		_award_feat("PATHFINDER", "PATHFINDER  //  BOTH SECRET LINES")
	if _contract_kind == &"ROUTE":
		_contract_progress += 1
		_update_contract()


func _set_route_visibility() -> void:
	for area: Area3D in _route_areas:
		var route_name := String(area.get_meta(&"route_name", ""))
		var should_show: bool = _active and area.get_meta(&"activity", &"NONE") == _activity and not _visited_routes.has(route_name)
		area.visible = should_show
		area.set_deferred(&"monitoring", should_show)


func _build_surface_zones() -> void:
	for zone_index: int in SURFACES.size():
		var data: Dictionary = SURFACES[zone_index]
		var area := Area3D.new()
		area.name = "SurfaceZone%02d" % zone_index
		area.position = data.get(&"position", Vector3.ZERO)
		area.collision_layer = 0
		area.collision_mask = 1
		area.set_meta(&"activity", data.get(&"activity", &"CIRCUIT"))
		area.set_meta(&"surface", data.get(&"surface", &"PACKED"))
		add_child(area)
		var size: Vector3 = data.get(&"size", Vector3(10.0, 2.5, 10.0))
		var shape := BoxShape3D.new()
		shape.size = size
		var collision := CollisionShape3D.new()
		collision.shape = shape
		area.add_child(collision)
		var patch := BoxMesh.new()
		patch.size = Vector3(size.x, 0.025, size.z)
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = data.get(&"color", Color(0.3, 0.25, 0.2, 0.4))
		material.roughness = 1.0
		patch.material = material
		var mesh := MeshInstance3D.new()
		mesh.mesh = patch
		area.add_child(mesh)
		area.body_entered.connect(_on_surface_entered.bind(area))
		area.body_exited.connect(_on_surface_exited.bind(area))
		_surface_areas.append(area)
	_set_surface_visibility()


func _on_surface_entered(body: Node3D, area: Area3D) -> void:
	if _active and body == _bike and area.get_meta(&"activity", &"NONE") == _activity:
		_bike.set_surface(area.get_meta(&"surface", &"PACKED"))


func _on_surface_exited(body: Node3D, _area: Area3D) -> void:
	if body == _bike:
		_bike.set_surface(&"PACKED")


func _set_surface_visibility() -> void:
	for area: Area3D in _surface_areas:
		var should_show: bool = _active and area.get_meta(&"activity", &"NONE") == _activity
		area.visible = should_show
		area.set_deferred(&"monitoring", should_show)


func _award_feat(feat_id: String, title: String) -> void:
	if Profile.unlocked_feats.has(feat_id):
		_pending_feats.erase(feat_id)
		return
	if Profile.unlock_feat(feat_id):
		_pending_feats.erase(feat_id)
		feat_unlocked.emit(title)
		return
	_pending_feats[feat_id] = title
	_feat_retry_time = CONTRACT_RETRY_INTERVAL


func _retry_pending_feat(delta: float) -> void:
	if _pending_feats.is_empty():
		return
	_feat_retry_time = maxf(_feat_retry_time - delta, 0.0)
	if _feat_retry_time > 0.0:
		return
	var feat_id: String = _pending_feats.keys()[0]
	var title: String = _pending_feats[feat_id]
	if Profile.unlocked_feats.has(feat_id) or Profile.unlock_feat(feat_id):
		_pending_feats.erase(feat_id)
		feat_unlocked.emit(title)
	_feat_retry_time = CONTRACT_RETRY_INTERVAL if not _pending_feats.is_empty() else 0.0
