extends Node
## Start timing must be independent, Flow must explain affordability, and newer
## captions must supersede stale cues without hiding unrelated warnings.

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var hud := preload("res://features/hud/race_hud.tscn").instantiate() as RaceHud
	var feed := AudioCaptionFeed.new()
	add_child(hud)
	add_child(feed)
	await get_tree().process_frame
	hud.set_process(false)
	feed.set_process(false)
	EventBus.race_countdown_changed.emit(0)
	hud.show_race_moment("RIVAL FLOW // SURGE", 0, false)
	hud.show_race_moment("RUT RAIL", 0, true)
	_check(str(hud.get_control_prompt_snapshot().get(&"message", "")).contains("RIVAL FLOW"), "Technique receipt erased a live warning")
	hud.call(&"_process", 0.85)
	var prompt := hud.get_control_prompt_snapshot()
	_check(str(prompt.get(&"countdown", "")) == "", "GO persisted beyond its independent lifetime")
	_check(str(prompt.get(&"message", "")).contains("RIVAL FLOW"), "GO timeout erased a live race warning")
	for mode: StringName in [&"SURGE", &"RAIL", &"COMPOSE"]:
		hud.update_racecraft_state({&"flow": 20.0, &"recommended_flow_mode": mode, &"recommended_flow_cost": 30.0})
		prompt = hud.get_control_prompt_snapshot()
		_check(str(prompt.get(&"flow_hint", "")).contains("10 MORE FOR " + String(mode)), "Unaffordable Flow did not show the exact shortfall")
		hud.update_flow(30.0, false)
		prompt = hud.get_control_prompt_snapshot()
		_check(str(prompt.get(&"flow", "")).contains("READY"), "Flow did not become ready at its exact cost")
		_check(str(prompt.get(&"flow_hint", "")).contains(InputRouter.get_action_label(InputRouter.FLOW_BOOST, InputRouter.input_mode, 1)), "Ready Flow omitted its configured input")
	hud.update_racecraft_state({&"flow": 12.0, &"active_flow_mode": &"RAIL", &"recommended_flow_cost": 30.0})
	_check(str(hud.get_control_prompt_snapshot().get(&"flow_hint", "")) == "RAIL ACTIVE", "Active technique was presented as unavailable")
	hud.update_racecraft_state({&"technique": &"RAIL", &"slide_active": true, &"roost_pressure": 0.7})
	_check(str(hud.get_control_prompt_snapshot().get(&"racecraft", "")).begins_with("ROOST 70%"), "Bounded decision lane hid a handling hazard")
	EventBus.race_reset.emit()
	_check(str(hud.get_control_prompt_snapshot().get(&"countdown", "")) == "", "Reset retained countdown text")
	feed.clear()
	for number: String in ["3", "2", "1", "GO"]:
		feed.request_caption(&"RACE_CONTROL", number, 2)
	_check(int(feed.get_snapshot().get(&"queue_size", -1)) == 0, "Countdown queued obsolete captions")
	feed.call(&"_process", 3.0)
	_check(not bool(feed.get_snapshot().get(&"visible", true)), "Old countdown replayed after GO")
	feed.request_caption(&"ROUTE", "WRONG WAY", 2)
	feed.request_caption(&"RIVAL", "SURGE NEARBY", 2)
	_check(int(feed.get_snapshot().get(&"queue_size", 0)) == 1, "Unrelated important warning was discarded")
	feed.call(&"_process", 3.0)
	_check(str(feed.get_snapshot().get(&"text", "")) == "WRONG WAY", "Unrelated warning was not preserved")
	hud.queue_free()
	feed.queue_free()
	await get_tree().process_frame
	for failure: String in _failures:
		push_error(failure)
	print("HUD RACE READABILITY PROBE: independent_start=true flow_thresholds=3 caption_supersession=true passed=%s" % str(_failures.is_empty()))
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
