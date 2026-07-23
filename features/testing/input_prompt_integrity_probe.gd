extends Node
## Deterministic contract for binding labels and same-device prompt invalidation.

const HUD_SCENE := preload("res://features/hud/race_hud.tscn")
const GARAGE_UI_SCRIPT := preload("res://features/garage/garage_ui.gd")
const MUTATED_ACTIONS: Array[StringName] = [
	InputRouter.THROTTLE,
	InputRouter.FLOW_BOOST,
	InputRouter.CONFIRM,
	InputRouter.OPEN_WORKSHOP,
	InputRouter.TOGGLE_REPLAY,
	InputRouter.TOGGLE_PHOTO_MODE,
]

const PHOTO_ACTIONS: Array[StringName] = [
	InputRouter.PHOTO_FORWARD,
	InputRouter.PHOTO_BACK,
	InputRouter.PHOTO_LEFT,
	InputRouter.PHOTO_RIGHT,
	InputRouter.PHOTO_DOWN,
	InputRouter.PHOTO_UP,
	InputRouter.PHOTO_LOOK_LEFT,
	InputRouter.PHOTO_LOOK_RIGHT,
	InputRouter.PHOTO_LOOK_UP,
	InputRouter.PHOTO_LOOK_DOWN,
]

var _failures: Array[String] = []
var _action_snapshots: Dictionary = {}
var _prior_input_mode: StringName = &""
var _binding_signal_count: int = 0
var _input_mode_signal_count: int = 0
var _last_binding_actions: Array[StringName] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_prior_input_mode = InputRouter.input_mode
	_snapshot_actions()
	InputRouter.call(&"_set_input_mode", InputRouter.INPUT_MODE_KEYBOARD_MOUSE)

	var hud := HUD_SCENE.instantiate() as RaceHud
	var garage := GARAGE_UI_SCRIPT.new() as GarageUi
	add_child(hud)
	add_child(garage)
	await get_tree().process_frame
	garage.show_garage()

	var initial_hud := hud.get_control_prompt_snapshot()
	var initial_hint := hud.get_control_hint_state()
	var initial_garage := garage.get_input_prompt_snapshot()
	_check(str(initial_hud.get(&"controls", "")).contains("W THROTTLE"), "HUD test fixture did not begin with the authored throttle prompt")
	_check(str(initial_hint.get(&"text", "")) == str(initial_hud.get(&"controls", "")), "HUD public prompt snapshots disagree before rebinding")
	_check(str(initial_garage.get(&"workshop_hint", "")).contains("TAB"), "Garage test fixture did not begin with the authored workshop prompt")
	_check(str(initial_garage.get(&"workshop_controls", "")).contains("ENTER"), "Garage test fixture did not begin with the authored confirm prompt")

	_probe_binding_formatters()
	_probe_pair_labels()
	_probe_photo_semantic_registry()

	var preserved_gamepad_labels := {
		InputRouter.THROTTLE: InputRouter.get_action_label(InputRouter.THROTTLE, InputRouter.INPUT_MODE_GAMEPAD, 4),
		InputRouter.FLOW_BOOST: InputRouter.get_action_label(InputRouter.FLOW_BOOST, InputRouter.INPUT_MODE_GAMEPAD, 4),
		InputRouter.CONFIRM: InputRouter.get_action_label(InputRouter.CONFIRM, InputRouter.INPUT_MODE_GAMEPAD, 4),
		InputRouter.OPEN_WORKSHOP: InputRouter.get_action_label(InputRouter.OPEN_WORKSHOP, InputRouter.INPUT_MODE_GAMEPAD, 4),
		InputRouter.TOGGLE_REPLAY: InputRouter.get_action_label(InputRouter.TOGGLE_REPLAY, InputRouter.INPUT_MODE_GAMEPAD, 4),
		InputRouter.TOGGLE_PHOTO_MODE: InputRouter.get_action_label(InputRouter.TOGGLE_PHOTO_MODE, InputRouter.INPUT_MODE_GAMEPAD, 4),
	}

	InputRouter.bindings_changed.connect(_on_bindings_changed)
	InputRouter.input_mode_changed.connect(_on_input_mode_changed)
	_replace_keyboard_binding(InputRouter.THROTTLE, KEY_F10)
	_replace_keyboard_binding(InputRouter.FLOW_BOOST, KEY_F9)
	_replace_keyboard_binding(InputRouter.CONFIRM, KEY_F8)
	_replace_keyboard_binding(InputRouter.OPEN_WORKSHOP, KEY_F7)
	_replace_keyboard_binding(InputRouter.TOGGLE_REPLAY, KEY_F6)
	_replace_keyboard_binding(InputRouter.TOGGLE_PHOTO_MODE, KEY_F5)

	_check(_binding_signal_count == 0, "InputMap mutation emitted before the authoritative notification")
	_check(_input_mode_signal_count == 0, "same-device mutation changed input mode")
	_check(InputRouter.input_mode == InputRouter.INPUT_MODE_KEYBOARD_MOUSE, "same-device mutation left keyboard/mouse mode")
	_check(
		str(hud.get_control_prompt_snapshot().get(&"controls", "")) == str(initial_hud.get(&"controls", "")),
		"HUD refreshed without a binding invalidation"
	)
	_check(
		str(garage.get_input_prompt_snapshot().get(&"workshop_hint", "")) == str(initial_garage.get(&"workshop_hint", "")),
		"Garage refreshed without a binding invalidation"
	)

	var revision_before_notify := InputRouter.binding_revision
	InputRouter.notify_bindings_changed(MUTATED_ACTIONS)
	_check(_binding_signal_count == 1, "one batched binding notification did not emit exactly once")
	_check(InputRouter.binding_revision == revision_before_notify + 1, "binding revision did not advance exactly once")
	_check(_same_action_set(_last_binding_actions, MUTATED_ACTIONS), "binding notification omitted or added actions")
	_check(_input_mode_signal_count == 0, "same-device notification emitted an input-mode change")

	var hud_prompt := hud.get_control_prompt_snapshot()
	var hud_hint := hud.get_control_hint_state()
	var garage_prompt := garage.get_input_prompt_snapshot()
	var hud_controls := str(hud_prompt.get(&"controls", ""))
	var hud_racecraft := str(hud_prompt.get(&"racecraft", ""))
	var garage_status := str(garage_prompt.get(&"status", ""))
	var garage_workshop_hint := str(garage_prompt.get(&"workshop_hint", ""))
	var garage_workshop_controls := str(garage_prompt.get(&"workshop_controls", ""))

	_check(hud_controls.contains("F10 THROTTLE"), "live HUD omitted the rebound throttle key")
	_check(hud_controls.contains("F9 CONTEXT FLOW"), "live HUD omitted the rebound Flow key")
	_check(not hud_controls.contains("W THROTTLE"), "live HUD retained the old throttle key")
	_check(not hud_controls.contains("SHIFT CONTEXT FLOW"), "live HUD retained the old Flow key")
	_check(hud_racecraft.contains("F9: SURGE"), "HUD racecraft teaching prompt did not refresh")
	_check(str(hud_hint.get(&"text", "")) == hud_controls, "HUD hint state did not expose the refreshed prompt")
	_check(int(hud_prompt.get(&"binding_revision", -1)) == InputRouter.binding_revision, "HUD prompt revision is stale")
	_check(int(hud_hint.get(&"binding_revision", -1)) == InputRouter.binding_revision, "HUD hint revision is stale")

	_check(garage_status.contains("F7") and garage_status.contains("F8"), "live Garage status omitted rebound controls")
	_check(garage_workshop_hint.contains("F7"), "live Garage workshop hint omitted the rebound key")
	_check(not garage_workshop_hint.contains("TAB"), "live Garage workshop hint retained the old key")
	_check(garage_workshop_controls.contains("F8"), "live Garage controls omitted the rebound confirm key")
	_check(not garage_workshop_controls.contains("ENTER"), "live Garage controls retained the old confirm key")
	_check(int(garage_prompt.get(&"binding_revision", -1)) == InputRouter.binding_revision, "Garage prompt revision is stale")
	_check(
		InputRouter.get_action_label(InputRouter.TOGGLE_REPLAY, InputRouter.INPUT_MODE_KEYBOARD_MOUSE, 2) == "F6",
		"replay action resolver omitted its rebound keyboard control"
	)
	_check(
		InputRouter.get_action_label(InputRouter.TOGGLE_PHOTO_MODE, InputRouter.INPUT_MODE_KEYBOARD_MOUSE, 2) == "F5",
		"photo action resolver omitted its rebound keyboard control"
	)

	_probe_mode_filtering(preserved_gamepad_labels)
	InputRouter.call(&"_set_input_mode", InputRouter.INPUT_MODE_GAMEPAD)
	var gamepad_hud := hud.get_control_prompt_snapshot()
	var gamepad_garage := garage.get_input_prompt_snapshot()
	var gamepad_hud_controls := str(gamepad_hud.get(&"controls", ""))
	var gamepad_garage_status := str(gamepad_garage.get(&"status", ""))
	_check(
		gamepad_hud_controls.contains(str(preserved_gamepad_labels.get(InputRouter.THROTTLE, "")))
		and not gamepad_hud_controls.contains("F10") and not gamepad_hud_controls.contains("F9"),
		"live HUD advertised keyboard bindings in gamepad mode"
	)
	_check(
		gamepad_garage_status.contains(str(preserved_gamepad_labels.get(InputRouter.CONFIRM, "")))
		and not gamepad_garage_status.contains("F8") and not gamepad_garage_status.contains("F7"),
		"live Garage advertised keyboard bindings in gamepad mode"
	)
	_probe_device_intent_filtering()
	_restore_actions()
	var revision_before_cleanup := InputRouter.binding_revision
	InputRouter.notify_bindings_changed(MUTATED_ACTIONS)
	_check(_binding_signal_count == 2, "cleanup binding notification did not emit exactly once")
	_check(InputRouter.binding_revision == revision_before_cleanup + 1, "cleanup did not advance the binding revision exactly once")
	for action: StringName in MUTATED_ACTIONS:
		_check(_action_matches_snapshot(action), "%s bindings were not restored exactly" % String(action))

	if InputRouter.input_mode_changed.is_connected(_on_input_mode_changed):
		InputRouter.input_mode_changed.disconnect(_on_input_mode_changed)
	InputRouter.call(&"_set_input_mode", _prior_input_mode)
	_check(InputRouter.input_mode == _prior_input_mode, "prior input mode was not restored")
	if InputRouter.bindings_changed.is_connected(_on_bindings_changed):
		InputRouter.bindings_changed.disconnect(_on_bindings_changed)

	garage.queue_free()
	hud.queue_free()
	await get_tree().process_frame
	if _failures.is_empty():
		print("INPUT PROMPT INTEGRITY PROBE: PASS  //  same_mode=true signals=1 cleanup=restored hud=F10+F9 garage=F8+F7 replay=F6 photo=F5 labels=mouse+button+axis+LS+RS")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("INPUT PROMPT INTEGRITY PROBE: " + failure)
	print("INPUT PROMPT INTEGRITY PROBE: FAIL  //  failures=%d" % _failures.size())
	get_tree().quit(1)


func _probe_binding_formatters() -> void:
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.ctrl_pressed = true
	var button := InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_RIGHT_SHOULDER
	var axis := InputEventJoypadMotion.new()
	axis.axis = JOY_AXIS_TRIGGER_RIGHT
	axis.axis_value = 1.0
	_check(InputRouter.format_binding_event(mouse) == "CTRL + LMB", "mouse binding label is not player-readable")
	_check(InputRouter.format_binding_event(button) == "RB", "gamepad button label is not player-readable")
	_check(InputRouter.format_binding_event(axis) == "RT", "gamepad axis label is not player-readable")


func _probe_pair_labels() -> void:
	_check(
		InputRouter.get_action_pair_label(
			InputRouter.STEER_LEFT, InputRouter.STEER_RIGHT, InputRouter.INPUT_MODE_GAMEPAD
		) == "LS",
		"opposed stick axes did not collapse to one LS label"
	)
	_check(
		InputRouter.get_action_pair_label(
			InputRouter.GARAGE_LEFT, InputRouter.GARAGE_RIGHT, InputRouter.INPUT_MODE_GAMEPAD
		) == "DPAD",
		"opposed D-pad buttons did not collapse to one DPAD label"
	)
	_check(
		InputRouter.get_action_pair_label(
			InputRouter.PHOTO_FORWARD, InputRouter.PHOTO_BACK, InputRouter.INPUT_MODE_GAMEPAD
		) == "LS",
		"photo forward/back stick axes did not collapse to one LS label"
	)
	_check(
		InputRouter.get_action_pair_label(
			InputRouter.PHOTO_LEFT, InputRouter.PHOTO_RIGHT, InputRouter.INPUT_MODE_GAMEPAD
		) == "LS",
		"photo left/right stick axes did not collapse to one LS label"
	)
	_check(
		InputRouter.get_action_pair_label(
			InputRouter.PHOTO_LOOK_LEFT, InputRouter.PHOTO_LOOK_RIGHT, InputRouter.INPUT_MODE_GAMEPAD
		) == "RS",
		"photo horizontal look axes did not collapse to one RS label"
	)
	_check(
		InputRouter.get_action_pair_label(
			InputRouter.PHOTO_LOOK_UP, InputRouter.PHOTO_LOOK_DOWN, InputRouter.INPUT_MODE_GAMEPAD
		) == "RS",
		"photo vertical look axes did not collapse to one RS label"
	)
	_check(
		InputRouter.get_action_pair_label(
			InputRouter.PHOTO_DOWN, InputRouter.PHOTO_UP, InputRouter.INPUT_MODE_GAMEPAD
		) == "LT / RT",
		"photo height triggers did not expose their opposed LT / RT controls"
	)


func _probe_photo_semantic_registry() -> void:
	for action: StringName in PHOTO_ACTIONS:
		_check(InputMap.has_action(action), "%s semantic photo action is missing" % String(action))
		_check(
			InputRouter.get_action_label(action, InputRouter.INPUT_MODE_KEYBOARD_MOUSE, 2) != "UNBOUND",
			"%s has no keyboard photo binding" % String(action)
		)
		_check(
			InputRouter.get_action_label(action, InputRouter.INPUT_MODE_GAMEPAD, 2) != "UNBOUND",
			"%s has no gamepad photo binding" % String(action)
		)


func _probe_mode_filtering(preserved_gamepad_labels: Dictionary) -> void:
	var keyboard_throttle := InputRouter.get_action_label(
		InputRouter.THROTTLE, InputRouter.INPUT_MODE_KEYBOARD_MOUSE, 4
	)
	var gamepad_throttle := InputRouter.get_action_label(
		InputRouter.THROTTLE, InputRouter.INPUT_MODE_GAMEPAD, 4
	)
	var any_throttle := InputRouter.get_action_label(
		InputRouter.THROTTLE, InputRouter.INPUT_MODE_ANY, 4
	)
	_check(keyboard_throttle == "F10", "keyboard filtering included another device family")
	_check(gamepad_throttle == str(preserved_gamepad_labels.get(InputRouter.THROTTLE, "")), "throttle rebind discarded its gamepad family")
	_check(any_throttle.contains("F10") and any_throttle.contains(gamepad_throttle), "ANY filtering did not include keyboard and gamepad labels")
	_check(not keyboard_throttle.contains(gamepad_throttle), "keyboard label leaked the gamepad binding")
	for action: StringName in MUTATED_ACTIONS:
		_check(
			InputRouter.get_action_label(action, InputRouter.INPUT_MODE_GAMEPAD, 4)
				== str(preserved_gamepad_labels.get(action, "")),
			"%s rebind did not preserve its gamepad family" % String(action)
		)


func _probe_device_intent_filtering() -> void:
	InputRouter.call(&"_set_input_mode", InputRouter.INPUT_MODE_KEYBOARD_MOUSE)
	var drift := InputEventJoypadMotion.new()
	drift.axis = JOY_AXIS_LEFT_X
	drift.axis_value = 0.08
	InputRouter.call(&"_input", drift)
	_check(
		InputRouter.input_mode == InputRouter.INPUT_MODE_KEYBOARD_MOUSE,
		"ordinary controller drift replaced keyboard/mouse prompts"
	)
	var release := InputEventJoypadButton.new()
	release.button_index = JOY_BUTTON_A
	release.pressed = false
	InputRouter.call(&"_input", release)
	_check(
		InputRouter.input_mode == InputRouter.INPUT_MODE_KEYBOARD_MOUSE,
		"controller button release replaced keyboard/mouse prompts"
	)
	var intentional := InputEventJoypadMotion.new()
	intentional.axis = JOY_AXIS_LEFT_X
	intentional.axis_value = 0.8
	InputRouter.call(&"_input", intentional)
	_check(
		InputRouter.input_mode == InputRouter.INPUT_MODE_GAMEPAD,
		"intentional controller motion did not select gamepad prompts"
	)
	InputRouter.call(&"_set_input_mode", InputRouter.INPUT_MODE_KEYBOARD_MOUSE)


func _snapshot_actions() -> void:
	_action_snapshots.clear()
	for action: StringName in MUTATED_ACTIONS:
		var events: Array[InputEvent] = []
		if InputMap.has_action(action):
			for event: InputEvent in InputMap.action_get_events(action):
				events.append(event.duplicate() as InputEvent)
		_action_snapshots[action] = {
			&"existed": InputMap.has_action(action),
			&"deadzone": InputMap.action_get_deadzone(action) if InputMap.has_action(action) else 0.2,
			&"events": events,
			&"fingerprint": _binding_fingerprint(events),
		}


func _replace_keyboard_binding(action: StringName, keycode: Key) -> void:
	var preserved: Array[InputEvent] = []
	for event: InputEvent in InputMap.action_get_events(action):
		if not event is InputEventKey:
			preserved.append(event.duplicate() as InputEvent)
	InputMap.action_erase_events(action)
	for event: InputEvent in preserved:
		InputMap.action_add_event(action, event)
	var replacement := InputEventKey.new()
	replacement.physical_keycode = keycode
	replacement.device = -1
	InputMap.action_add_event(action, replacement)


func _restore_actions() -> void:
	for action: StringName in MUTATED_ACTIONS:
		var snapshot := _action_snapshots.get(action, {}) as Dictionary
		if not bool(snapshot.get(&"existed", false)):
			if InputMap.has_action(action):
				InputMap.erase_action(action)
			continue
		if not InputMap.has_action(action):
			InputMap.add_action(action, float(snapshot.get(&"deadzone", 0.2)))
		InputMap.action_set_deadzone(action, float(snapshot.get(&"deadzone", 0.2)))
		InputMap.action_erase_events(action)
		for event: InputEvent in snapshot.get(&"events", []) as Array[InputEvent]:
			InputMap.action_add_event(action, event.duplicate() as InputEvent)


func _action_matches_snapshot(action: StringName) -> bool:
	var snapshot := _action_snapshots.get(action, {}) as Dictionary
	var existed := bool(snapshot.get(&"existed", false))
	if InputMap.has_action(action) != existed:
		return false
	if not existed:
		return true
	if not is_equal_approx(
		InputMap.action_get_deadzone(action), float(snapshot.get(&"deadzone", 0.2))
	):
		return false
	return _binding_fingerprint(InputMap.action_get_events(action)) == str(snapshot.get(&"fingerprint", ""))


func _binding_fingerprint(events: Array[InputEvent]) -> String:
	var serialized: Array[Dictionary] = []
	for event: InputEvent in events:
		serialized.append(SettingsStore.serialize_binding(event))
	return JSON.stringify(serialized)


func _same_action_set(first: Array[StringName], second: Array[StringName]) -> bool:
	if first.size() != second.size():
		return false
	for action: StringName in first:
		if action not in second:
			return false
	return true


func _on_bindings_changed(actions: Array[StringName]) -> void:
	_binding_signal_count += 1
	_last_binding_actions = actions.duplicate()


func _on_input_mode_changed(_mode: StringName) -> void:
	_input_mode_signal_count += 1


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
