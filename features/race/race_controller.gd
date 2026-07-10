extends Node3D
class_name RaceController
## Countdown, ordered checkpoint validation, microsecond timing, medals, and run lifecycle.

signal time_updated(elapsed_usec: int, best_usec: int, checkpoint: int, total: int)
signal breakdown_ready(summary: String)

enum State { WAITING, COUNTDOWN, RACING, FINISHED }

var state: State = State.WAITING
var bike: DirtBikeController
var ghost: GhostController

var _gates: Array[Area3D] = []
var _gate_materials: Array[StandardMaterial3D] = []
var _expected_checkpoint: int = 0
var _start_usec: int = 0
var _elapsed_usec: int = 0
var _countdown_remaining: float = 0.0
var _last_countdown_value: int = -1
var _spawn_transform: Transform3D = Transform3D(Basis.IDENTITY, Vector3(0.0, 1.4, 31.0))
var _checkpoint_data: Array[Dictionary] = []
var _gold_usec: int = 42_000_000
var _silver_usec: int = 55_000_000
var _bronze_usec: int = 75_000_000
var _activity_id: StringName = &"CIRCUIT"
var _track_id: StringName = &"QUARRY"
var _gates_enabled: bool = false
var _split_times: Array[int] = []
var _rival_target_usec: int = 52_000_000


func _ready() -> void:
	configure_track(&"QUARRY")


func _physics_process(delta: float) -> void:
	match state:
		State.COUNTDOWN:
			_countdown_remaining -= delta
			var display_value := maxi(int(ceil(_countdown_remaining)), 0)
			if display_value != _last_countdown_value:
				_last_countdown_value = display_value
				EventBus.race_countdown_changed.emit(display_value)
			if _countdown_remaining <= 0.0:
				_start_race()
		State.RACING:
			_elapsed_usec = Time.get_ticks_usec() - _start_usec
			time_updated.emit(_elapsed_usec, ghost.best_time_usec, _expected_checkpoint, _checkpoint_data.size())


func initialize(player_bike: DirtBikeController, ghost_controller: GhostController) -> void:
	bike = player_bike
	ghost = ghost_controller
	ghost.target = bike
	enter_waiting()


func get_expected_checkpoint() -> int:
	return _expected_checkpoint


func get_checkpoint_positions() -> Array[Vector3]:
	var positions: Array[Vector3] = []
	for checkpoint: Dictionary in _checkpoint_data:
		positions.append(checkpoint.get(&"position", Vector3.ZERO))
	return positions


func get_spawn_transform() -> Transform3D:
	return _spawn_transform


func get_breakdown_preview() -> String:
	return _build_breakdown()


func configure_track(track_id: StringName) -> void:
	_track_id = track_id
	_cleanup_checkpoint_gates()
	if track_id == &"PINE":
		var first_direction := Vector3(-12.0, 0.0, -30.0).normalized()
		_spawn_transform = Transform3D(Basis.looking_at(first_direction, Vector3.UP), Vector3(260.0, 1.4, 35.0))
		_checkpoint_data = [
			{&"position": Vector3(248.0, 2.3, 5.0), &"yaw": -0.58},
			{&"position": Vector3(230.0, 2.3, -22.0), &"yaw": -0.95},
			{&"position": Vector3(250.0, 2.3, -50.0), &"yaw": -2.15},
			{&"position": Vector3(284.0, 2.3, -42.0), &"yaw": 1.8},
			{&"position": Vector3(302.0, 2.3, -12.0), &"yaw": 0.56},
			{&"position": Vector3(290.0, 2.3, 20.0), &"yaw": -0.36},
			{&"position": Vector3(260.0, 2.3, 35.0), &"yaw": -1.1},
		]
		_gold_usec = 50_000_000
		_silver_usec = 68_000_000
		_bronze_usec = 92_000_000
		_activity_id = &"PINE_ENDURO"
		_rival_target_usec = 64_000_000
	else:
		_spawn_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 1.4, 31.0))
		_checkpoint_data = [
			{&"position": Vector3(0.0, 2.3, -31.0), &"yaw": 0.0},
			{&"position": Vector3(18.0, 2.3, -49.0), &"yaw": 0.78},
			{&"position": Vector3(40.0, 2.3, -43.0), &"yaw": 1.82},
			{&"position": Vector3(53.0, 2.3, 0.0), &"yaw": 0.0},
			{&"position": Vector3(38.0, 2.3, 44.0), &"yaw": 0.78},
			{&"position": Vector3(0.0, 2.3, 39.0), &"yaw": 0.75},
		]
		_gold_usec = 42_000_000
		_silver_usec = 55_000_000
		_bronze_usec = 75_000_000
		_activity_id = &"CIRCUIT"
		_rival_target_usec = 52_000_000
	_build_checkpoint_gates()
	_set_gates_visible(false)
	if ghost != null:
		ghost.set_record_slot(StringName(String(track_id).to_lower()))
		ghost.configure_rival(_get_rival_path(), _rival_target_usec)


func enter_waiting() -> void:
	state = State.WAITING
	_elapsed_usec = 0
	_expected_checkpoint = 0
	_split_times.clear()
	if bike != null:
		bike.set_controls_enabled(false)
		bike.respawn_at(_spawn_transform)
	if ghost != null:
		ghost.cancel_run()
	_set_gates_visible(false)
	_update_gate_visuals()


func reset_run() -> void:
	if bike == null or ghost == null:
		return
	state = State.COUNTDOWN
	_expected_checkpoint = 0
	_split_times.clear()
	_elapsed_usec = 0
	_countdown_remaining = 3.25
	_last_countdown_value = -1
	bike.set_controls_enabled(false)
	bike.respawn_at(_spawn_transform)
	ghost.cancel_run()
	_set_gates_visible(true)
	_update_gate_visuals()
	EventBus.race_reset.emit()
	time_updated.emit(0, ghost.best_time_usec, 0, _checkpoint_data.size())


func _start_race() -> void:
	state = State.RACING
	_start_usec = Time.get_ticks_usec()
	_elapsed_usec = 0
	bike.set_controls_enabled(true)
	ghost.start_run()
	EventBus.activity_started.emit(_activity_id)
	EventBus.race_started.emit()


func _finish_race() -> void:
	if state != State.RACING:
		return
	_elapsed_usec = Time.get_ticks_usec() - _start_usec
	state = State.FINISHED
	bike.set_controls_enabled(false)
	var is_new_best := ghost.best_time_usec < 0 or _elapsed_usec < ghost.best_time_usec
	var medal := _medal_for_time(_elapsed_usec)
	ghost.finish_run(_elapsed_usec, is_new_best)
	EventBus.race_finished.emit(_elapsed_usec, medal, is_new_best)
	breakdown_ready.emit(_build_breakdown())
	time_updated.emit(_elapsed_usec, ghost.best_time_usec, _checkpoint_data.size(), _checkpoint_data.size())


func _on_gate_entered(body: Node3D, checkpoint_index: int) -> void:
	if state != State.RACING or body != bike or checkpoint_index != _expected_checkpoint:
		return
	_expected_checkpoint += 1
	_split_times.append(_elapsed_usec)
	EventBus.checkpoint_passed.emit(checkpoint_index, _checkpoint_data.size(), _elapsed_usec)
	_update_gate_visuals()
	if _expected_checkpoint >= _checkpoint_data.size():
		_finish_race()


func _build_checkpoint_gates() -> void:
	for index: int in _checkpoint_data.size():
		var gate_data := _checkpoint_data[index]
		var area := Area3D.new()
		area.name = "Checkpoint%02d" % index
		area.collision_layer = 0
		area.collision_mask = 1
		area.monitoring = true
		area.position = gate_data.get(&"position", Vector3.ZERO)
		area.rotation.y = float(gate_data.get(&"yaw", 0.0))
		add_child(area)

		var shape := BoxShape3D.new()
		shape.size = Vector3(12.5, 10.0, 1.2)
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.position.y = 2.5
		area.add_child(collision)
		area.body_entered.connect(_on_gate_entered.bind(index))

		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.emission_enabled = true
		_gate_materials.append(material)
		_add_gate_box(area, Vector3(0.28, 4.25, 0.28), Vector3(-6.0, 0.0, 0.0), material)
		_add_gate_box(area, Vector3(0.28, 4.25, 0.28), Vector3(6.0, 0.0, 0.0), material)
		_add_gate_box(area, Vector3(12.3, 0.34, 0.34), Vector3(0.0, 2.0, 0.0), material)

		var label := Label3D.new()
		label.text = "FINISH" if index == _checkpoint_data.size() - 1 else "%02d" % (index + 1)
		label.position = Vector3(0.0, 2.55, 0.0)
		label.font_size = 42
		label.outline_size = 10
		label.modulate = Color("f7e5b2")
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		area.add_child(label)
		_gates.append(area)
	_update_gate_visuals()


func _cleanup_checkpoint_gates() -> void:
	for gate: Area3D in _gates:
		if is_instance_valid(gate):
			remove_child(gate)
			gate.queue_free()
	_gates.clear()
	_gate_materials.clear()


func _add_gate_box(parent: Node3D, size: Vector3, position: Vector3, material: StandardMaterial3D) -> void:
	var box := BoxMesh.new()
	box.size = size
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = box
	mesh_instance.position = position
	mesh_instance.material_override = material
	parent.add_child(mesh_instance)


func _update_gate_visuals() -> void:
	for index: int in _gate_materials.size():
		var material := _gate_materials[index]
		var is_active := index == _expected_checkpoint and state != State.FINISHED
		var is_passed := index < _expected_checkpoint
		var gate := _gates[index]
		gate.visible = _gates_enabled and not is_passed
		gate.set_deferred(&"monitoring", _gates_enabled and not is_passed)
		var color := Color("ffb52d") if is_active else Color("30404a")
		if is_passed:
			color = Color("42d39d")
		material.albedo_color = color
		material.emission = color
		material.emission_energy_multiplier = 2.7 if is_active else 0.45


func _set_gates_visible(visible: bool) -> void:
	_gates_enabled = visible
	_update_gate_visuals()


func _medal_for_time(time_usec: int) -> StringName:
	if time_usec <= _gold_usec:
		return &"GOLD"
	if time_usec <= _silver_usec:
		return &"SILVER"
	if time_usec <= _bronze_usec:
		return &"BRONZE"
	return &"FINISHER"


func _get_rival_path() -> Array[Vector3]:
	var points: Array[Vector3] = [_spawn_transform.origin]
	for checkpoint: Dictionary in _checkpoint_data:
		points.append(checkpoint.get(&"position", Vector3.ZERO))
	return points


func _build_breakdown() -> String:
	if _split_times.is_empty():
		return "RUN READOUT  //  NO SECTOR DATA"
	var best_delta: float = INF
	var worst_delta: float = -INF
	var best_sector := 1
	var worst_sector := 1
	var previous_split := 0
	var rival_sector := float(_rival_target_usec) / float(_split_times.size())
	for index: int in _split_times.size():
		var sector_time := _split_times[index] - previous_split
		previous_split = _split_times[index]
		var delta := float(sector_time) - rival_sector
		if delta < best_delta:
			best_delta = delta
			best_sector = index + 1
		if delta > worst_delta:
			worst_delta = delta
			worst_sector = index + 1
	return "RUN READOUT  //  BEST S%02d %+.2fs  //  COSTLIEST S%02d %+.2fs" % [best_sector, best_delta / 1_000_000.0, worst_sector, worst_delta / 1_000_000.0]
