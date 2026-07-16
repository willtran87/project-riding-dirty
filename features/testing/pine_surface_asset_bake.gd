extends Node
## Development-only deterministic bake for Pine Ridge's runtime PBR sets.

const OUTPUT_DIRECTORY := "res://assets/generated/pine_surfaces"
const MAP_NAMES: Array[StringName] = [&"albedo", &"normal", &"roughness"]


func _ready() -> void:
	var absolute_directory := ProjectSettings.globalize_path(OUTPUT_DIRECTORY)
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute_directory)
	if directory_error != OK:
		push_error("PINE SURFACE BAKE: could not create %s" % absolute_directory)
		get_tree().quit(1)
		return
	var specs: Array[Dictionary] = [
		{
			&"name": &"trail",
			&"colors": PackedColorArray([Color("211713"), Color("39271e"), Color("59402f"), Color("2b2019")]),
			&"seed": 42028, &"frequency": 0.026, &"roughness": 1.0,
		},
		{
			&"name": &"moss",
			&"colors": PackedColorArray([Color("283827"), Color("40573a"), Color("61764c")]),
			&"seed": 42034, &"frequency": 0.03, &"roughness": 0.98,
		},
		{
			&"name": &"trail_edge",
			&"colors": PackedColorArray([Color("574b3b"), Color("75664f"), Color("938064")]),
			&"seed": 42036, &"frequency": 0.035, &"roughness": 0.98,
		},
		{
			&"name": &"terrain",
			&"colors": PackedColorArray([Color("223025"), Color("354936"), Color("526247"), Color("2b3c30")]),
			&"seed": 42040, &"frequency": 0.018, &"roughness": 1.0,
		},
	]
	var passed := true
	for spec: Dictionary in specs:
		var textures := ProceduralSurfaceTexture._build_surface_set(
			spec[&"colors"],
			int(spec[&"seed"]),
			float(spec[&"frequency"]),
			float(spec[&"roughness"])
		)
		for map_name: StringName in MAP_NAMES:
			var texture := textures.get(map_name) as ImageTexture
			var path := "%s/%s_%s.res" % [OUTPUT_DIRECTORY, String(spec[&"name"]), String(map_name)]
			var save_error := ResourceSaver.save(texture, path)
			if save_error != OK:
				passed = false
				push_error("PINE SURFACE BAKE: failed %s (%d)" % [path, save_error])
	print("PINE SURFACE BAKE: sets=%d resources=%d passed=%s" % [specs.size(), specs.size() * MAP_NAMES.size(), str(passed)])
	get_tree().quit(0 if passed else 1)
