extends SceneTree
## Generates the small set of loops required before the first interactive frame.
## Event variations continue to render on the worker thread behind transitions.

const ENGINE_AUDIO := preload("res://entities/bike/engine_audio.gd")
const GAMEPLAY_AUDIO := preload("res://features/audio/gameplay_audio.gd")
const OUTPUT_DIR := "res://assets/generated/audio"


func _init() -> void:
	var absolute_dir := ProjectSettings.globalize_path(OUTPUT_DIR)
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute_dir)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		push_error("AUDIO BAKE: could not create %s (%d)" % [absolute_dir, directory_error])
		quit(1)
		return

	var failed := false
	for layer: StringName in [&"ENGINE", &"PACKED", &"MUD", &"GRAVEL", &"ROCK", &"LOOSE_DIRT"]:
		var file_name := "engine_%s.res" % String(layer).to_lower()
		failed = not _save_stream(ENGINE_AUDIO.build_baked_loop(layer), file_name) or failed

	var arrangement: Dictionary = GAMEPLAY_AUDIO.build_baked_arrangement(&"CIRCUIT", &"QUARRY")
	var streams := arrangement.get(&"streams", {}) as Dictionary
	for stem: StringName in GAMEPLAY_AUDIO.MUSIC_STEMS:
		var file_name := "music_quarry_standard_%s.res" % String(stem).to_lower()
		failed = not _save_stream(streams.get(stem) as AudioStreamWAV, file_name) or failed

	if failed:
		push_error("AUDIO BAKE: one or more resources failed")
		quit(1)
		return
	print("AUDIO BAKE PASS: engine_loops=6 music_stems=4")
	quit(0)


func _save_stream(stream: AudioStreamWAV, file_name: String) -> bool:
	if stream == null:
		push_error("AUDIO BAKE: null stream for %s" % file_name)
		return false
	var path := "%s/%s" % [OUTPUT_DIR, file_name]
	var error := ResourceSaver.save(stream, path, ResourceSaver.FLAG_COMPRESS)
	if error != OK:
		push_error("AUDIO BAKE: save failed for %s (%d)" % [path, error])
		return false
	return true
