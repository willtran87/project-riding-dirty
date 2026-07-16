extends RefCounted
class_name WebVisibilityState
## Pure lifecycle state used by WebPlatform and deterministic headless probes.

var _is_hidden: bool = false
var _paused_by_visibility: bool = false
var _master_was_muted: bool = false


func transition(is_hidden: bool, tree_is_paused: bool, master_is_muted: bool) -> Dictionary:
	if is_hidden:
		if not _is_hidden:
			_is_hidden = true
			_master_was_muted = master_is_muted
			_paused_by_visibility = not tree_is_paused
		return {
			"set_tree_paused": _paused_by_visibility and not tree_is_paused,
			"tree_paused": true,
			"set_master_mute": true,
			"master_muted": true,
		}
	if not _is_hidden:
		return _no_change()
	_is_hidden = false
	var should_resume_tree := _paused_by_visibility
	_paused_by_visibility = false
	return {
		"set_tree_paused": should_resume_tree,
		"tree_paused": false,
		"set_master_mute": true,
		"master_muted": _master_was_muted,
	}


func was_paused_by_visibility() -> bool:
	return _paused_by_visibility


func _no_change() -> Dictionary:
	return {
		"set_tree_paused": false,
		"tree_paused": false,
		"set_master_mute": false,
		"master_muted": false,
	}
