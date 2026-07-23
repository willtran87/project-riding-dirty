extends Node
## Proves the pre-baked Pine PBR resources are byte-identical to the authored
## deterministic generator they replace during district preparation.

const DIRECTORY := "res://assets/generated/pine_surfaces"
const MAP_NAMES: Array[StringName] = [&"albedo", &"normal", &"roughness"]


func _ready() -> void:
	var specs: Array[Dictionary] = [
		{&"name": &"trail", &"colors": PackedColorArray([Color("211713"), Color("39271e"), Color("59402f"), Color("2b2019")]), &"seed": 42028, &"frequency": 0.026, &"roughness": 1.0},
		{&"name": &"moss", &"colors": PackedColorArray([Color("283827"), Color("40573a"), Color("61764c")]), &"seed": 42034, &"frequency": 0.03, &"roughness": 0.98},
		{&"name": &"trail_edge", &"colors": PackedColorArray([Color("574b3b"), Color("75664f"), Color("938064")]), &"seed": 42036, &"frequency": 0.035, &"roughness": 0.98},
		{&"name": &"terrain", &"colors": PackedColorArray([Color("223025"), Color("354936"), Color("526247"), Color("2b3c30")]), &"seed": 42040, &"frequency": 0.018, &"roughness": 1.0},
	]
	var mismatches := 0
	for spec: Dictionary in specs:
		var generated := ProceduralSurfaceTexture._build_surface_set(
			spec[&"colors"], int(spec[&"seed"]), float(spec[&"frequency"]), float(spec[&"roughness"])
		)
		for map_name: StringName in MAP_NAMES:
			var path := "%s/%s_%s.res" % [DIRECTORY, String(spec[&"name"]), String(map_name)]
			var baked := load(path) as ImageTexture
			var expected := generated.get(map_name) as ImageTexture
			if baked == null or expected == null or baked.get_image().get_data() != expected.get_image().get_data():
				mismatches += 1
	var passed := mismatches == 0
	print("PINE SURFACE ASSET PROBE: sets=%d maps=%d mismatches=%d passed=%s" % [specs.size(), specs.size() * MAP_NAMES.size(), mismatches, str(passed)])
	if not passed:
		push_error("PINE SURFACE ASSET PROBE: baked surface resources diverged from the authored generator")
	get_tree().quit(0 if passed else 1)
