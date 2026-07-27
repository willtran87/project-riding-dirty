extends Node
## Generates the small set of loops required before the first interactive frame.
## Event variations continue to render on the worker thread behind transitions.
## Run through bake_runtime_audio_assets.tscn so project autoloads and class
## registrations are available to both engine and adaptive-music generators.

const ENGINE_AUDIO := preload("res://entities/bike/engine_audio.gd")
const GAMEPLAY_AUDIO := preload("res://features/audio/gameplay_audio.gd")
const OUTPUT_DIR := "res://assets/generated/audio"


func _ready() -> void:
	var absolute_dir := ProjectSettings.globalize_path(OUTPUT_DIR)
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute_dir)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		push_error("AUDIO BAKE: could not create %s (%d)" % [absolute_dir, directory_error])
		get_tree().quit(1)
		return

	var failed := false
	for layer: StringName in [
		&"ENGINE", &"PACKED", &"MUD", &"SAND", &"GRAVEL", &"GRASS", &"ROCK", &"LOOSE_DIRT",
	]:
		var file_name := "engine_%s.res" % String(layer).to_lower()
		failed = not _save_stream(ENGINE_AUDIO.build_baked_loop(layer), file_name) or failed
	if &"--engine-only" in OS.get_cmdline_user_args():
		if failed:
			push_error("AUDIO BAKE: one or more engine resources failed")
			get_tree().quit(1)
			return
		print("AUDIO BAKE PASS: engine_loops=8 music_stems=unchanged")
		get_tree().quit(0)
		return

	var arrangement: Dictionary = GAMEPLAY_AUDIO.build_baked_arrangement(&"CIRCUIT", &"QUARRY")
	var streams := arrangement.get(&"streams", {}) as Dictionary
	for stem: StringName in GAMEPLAY_AUDIO.MUSIC_STEMS:
		var file_name := "music_quarry_standard_%s.res" % String(stem).to_lower()
		failed = not _save_stream(streams.get(stem) as AudioStreamWAV, file_name) or failed

	if failed:
		push_error("AUDIO BAKE: one or more resources failed")
		get_tree().quit(1)
		return
	print("AUDIO BAKE PASS: engine_loops=8 music_stems=4")
	get_tree().quit(0)


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
