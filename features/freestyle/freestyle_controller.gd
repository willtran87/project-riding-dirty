extends Node
class_name FreestyleController
## Timed jump session scoring airtime, rotation, landing quality, and clean combos.

signal hud_updated(time_left_usec: int, score: int, combo: int, last_airtime: float)

const SPAWN_TRANSFORM := Transform3D(Basis.IDENTITY, Vector3(0.0, 1.4, 31.0))
const SESSION_USEC: int = 60_000_000
const GOLD_SCORE: int = 12_000
const SILVER_SCORE: int = 7_000
const BRONZE_SCORE: int = 3_500

var bike: DirtBikeController
var ghost: GhostController
var active: bool = false
var score: int = 0
var combo: int = 1

var _start_usec: int = 0
var _last_airtime: float = 0.0


func _physics_process(_delta: float) -> void:
	if not active:
		return
	var elapsed_usec := Time.get_ticks_usec() - _start_usec
	var time_left_usec := maxi(SESSION_USEC - elapsed_usec, 0)
	hud_updated.emit(time_left_usec, score, combo, _last_airtime)
	if time_left_usec <= 0:
		_finish_session()


func initialize(player_bike: DirtBikeController, ghost_controller: GhostController) -> void:
	bike = player_bike
	ghost = ghost_controller
	if not bike.trick_landed.is_connected(_on_trick_landed):
		bike.trick_landed.connect(_on_trick_landed)
	enter_waiting()


func start_session() -> void:
	if bike == null or ghost == null:
		return
	active = true
	score = 0
	combo = 1
	_last_airtime = 0.0
	_start_usec = Time.get_ticks_usec()
	bike.respawn_at(SPAWN_TRANSFORM)
	bike.set_motion_locked(false)
	bike.set_controls_enabled(true)
	ghost.cancel_run()
	EventBus.activity_started.emit(&"FREESTYLE")
	EventBus.freestyle_score_changed.emit(0, 1, 0)
	hud_updated.emit(SESSION_USEC, 0, 1, 0.0)


func enter_waiting() -> void:
	active = false
	if bike != null:
		bike.set_controls_enabled(false)
	if ghost != null:
		ghost.cancel_run()


func _on_trick_landed(airtime: float, rotation_amount: float, landing_intensity: float, clean: bool) -> void:
	if not active or airtime < 0.28:
		return
	_last_airtime = airtime
	var airtime_points := int(airtime * 900.0)
	var rotation_points := int(rotation_amount / TAU * 1100.0)
	var landing_points := int(lerpf(350.0, 80.0, clampf(landing_intensity, 0.0, 1.0)))
	var raw_points := maxi(airtime_points + rotation_points + landing_points, 100)
	if clean:
		combo = mini(combo + 1, 6)
	else:
		combo = 1
		raw_points = int(raw_points * 0.4)
	var awarded_points := int(raw_points * (1.0 + float(combo - 1) * 0.22))
	score += awarded_points
	EventBus.freestyle_score_changed.emit(score, combo, awarded_points)


func _finish_session() -> void:
	if not active:
		return
	active = false
	bike.set_controls_enabled(false)
	var medal := _medal_for_score(score)
	var is_new_best := score > Profile.best_freestyle_score
	EventBus.activity_completed.emit(&"FREESTYLE", score, medal, is_new_best)
	hud_updated.emit(0, score, combo, _last_airtime)


func _medal_for_score(final_score: int) -> StringName:
	if final_score >= GOLD_SCORE:
		return &"GOLD"
	if final_score >= SILVER_SCORE:
		return &"SILVER"
	if final_score >= BRONZE_SCORE:
		return &"BRONZE"
	return &"FINISHER"
