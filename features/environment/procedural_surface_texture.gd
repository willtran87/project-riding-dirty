extends RefCounted
class_name ProceduralSurfaceTexture
## Runtime-generated PBR surface sets. The albedo, normal and roughness maps use
## one deterministic seamless height field, keeping the procedural levels
## coherent under changing light instead of reading as flat color wallpaper.

static var _surface_cache: Dictionary = {}

const TEXTURE_SIZE: int = 128
const CACHE_VERSION: int = 2


static func clear_cache() -> void:
	# Static resources otherwise outlive the scene tree and can reach graphics
	# teardown after the renderer, which produces false-positive GL leak reports.
	_surface_cache.clear()


static func apply(
	material: StandardMaterial3D,
	colors: PackedColorArray,
	seed: int,
	frequency: float,
	uv_scale: float = 1.0
) -> void:
	if colors.size() < 2:
		return
	var cache_key := "v%d|%d|%.5f|%.3f|%s" % [CACHE_VERSION, seed, frequency, material.roughness, str(colors)]
	var cached: Dictionary = _surface_cache.get(cache_key, {}) as Dictionary
	if cached.is_empty():
		cached = _build_surface_set(colors, seed, frequency, material.roughness)
		_surface_cache[cache_key] = cached
	apply_texture_set(material, cached, uv_scale)


static func apply_texture_set(
	material: StandardMaterial3D,
	textures: Dictionary,
	uv_scale: float = 1.0
) -> void:
	material.albedo_color = Color.WHITE
	material.albedo_texture = textures.get(&"albedo") as Texture2D
	material.normal_enabled = true
	material.normal_texture = textures.get(&"normal") as Texture2D
	material.normal_scale = 0.62
	material.roughness_texture = textures.get(&"roughness") as Texture2D
	material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	material.uv1_scale = Vector3.ONE * uv_scale
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.texture_repeat = true


static func _build_surface_set(
	colors: PackedColorArray,
	seed: int,
	frequency: float,
	base_roughness: float
) -> Dictionary:
	# The ribbon repeats UVs every few metres, so a single FBM field reads as
	# evenly distributed television noise at race-camera distance. A small
	# periodic value-noise bake gives every cached surface three useful scales:
	# broad patches for composition, clumps for material identity, and fine grain
	# for motion. It remains one opaque material and three compact 128px textures;
	# mipmapping and the authored high-resolution Mesa clay base supply close detail.
	var macro_cells := clampi(roundi(frequency * 96.0), 2, 5)
	var meso_cells := macro_cells * 3 + 1
	var detail_cells := meso_cells * 3 + 2
	var height_field := PackedFloat32Array()
	height_field.resize(TEXTURE_SIZE * TEXTURE_SIZE)
	var color_weights := PackedFloat32Array()
	color_weights.resize(TEXTURE_SIZE * TEXTURE_SIZE)
	var roughness_weights := PackedFloat32Array()
	roughness_weights.resize(TEXTURE_SIZE * TEXTURE_SIZE)

	for y: int in TEXTURE_SIZE:
		var v := float(y) / float(TEXTURE_SIZE)
		for x: int in TEXTURE_SIZE:
			var u := float(x) / float(TEXTURE_SIZE)
			var uv := Vector2(u, v)
			var macro := _tileable_value_noise(uv, macro_cells, seed + 101)
			var meso := _tileable_value_noise(uv, meso_cells, seed + 307)
			var detail := _tileable_value_noise(uv, detail_cells, seed + 911)
			var grain := _tileable_value_noise(uv, detail_cells * 2 + 1, seed + 1597)
			var ridged_detail := 1.0 - absf(detail * 2.0 - 1.0)
			var index := y * TEXTURE_SIZE + x
			height_field[index] = clampf(
				macro * 0.34 + meso * 0.38 + ridged_detail * 0.20 + grain * 0.08,
				0.0,
				1.0
			)
			# Let the macro band move through a meaningful part of the palette while
			# keeping high-frequency grain subtle enough not to shimmer in motion.
			color_weights[index] = clampf(
				macro * 0.50 + meso * 0.30 + detail * 0.14 + grain * 0.06,
				0.0,
				1.0
			)
			roughness_weights[index] = clampf(
				base_roughness * 0.78 + macro * 0.08 + (1.0 - ridged_detail) * 0.10 + grain * 0.04,
				0.48,
				1.0
			)

	var albedo_image := Image.create(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	var normal_image := Image.create(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	var roughness_image := Image.create(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	for y: int in TEXTURE_SIZE:
		var previous_y := wrapi(y - 1, 0, TEXTURE_SIZE)
		var next_y := wrapi(y + 1, 0, TEXTURE_SIZE)
		for x: int in TEXTURE_SIZE:
			var previous_x := wrapi(x - 1, 0, TEXTURE_SIZE)
			var next_x := wrapi(x + 1, 0, TEXTURE_SIZE)
			var index := y * TEXTURE_SIZE + x
			var color := _sample_palette(colors, color_weights[index])
			albedo_image.set_pixel(x, y, color)
			var left := height_field[y * TEXTURE_SIZE + previous_x]
			var right := height_field[y * TEXTURE_SIZE + next_x]
			var up := height_field[previous_y * TEXTURE_SIZE + x]
			var down := height_field[next_y * TEXTURE_SIZE + x]
			var surface_normal := Vector3((left - right) * 2.4, (up - down) * 2.4, 1.0).normalized()
			normal_image.set_pixel(x, y, Color(
				surface_normal.x * 0.5 + 0.5,
				surface_normal.y * 0.5 + 0.5,
				surface_normal.z * 0.5 + 0.5,
				1.0
			))
			var roughness_value := roughness_weights[index]
			roughness_image.set_pixel(x, y, Color(roughness_value, roughness_value, roughness_value, 1.0))

	# Mip generation is done once per cache entry and avoids sparkling detail in
	# the long chase-camera views. ImageTexture keeps this deterministic on native
	# and Web exports without a frame-delayed NoiseTexture2D bake.
	albedo_image.generate_mipmaps()
	normal_image.generate_mipmaps()
	roughness_image.generate_mipmaps()
	return {
		&"albedo": ImageTexture.create_from_image(albedo_image),
		&"normal": ImageTexture.create_from_image(normal_image),
		&"roughness": ImageTexture.create_from_image(roughness_image),
	}


static func _tileable_value_noise(uv: Vector2, cells: int, seed: int) -> float:
	var safe_cells := maxi(cells, 1)
	var position := uv * float(safe_cells)
	var cell_x := floori(position.x)
	var cell_y := floori(position.y)
	var fraction_x := position.x - float(cell_x)
	var fraction_y := position.y - float(cell_y)
	var smooth_x := fraction_x * fraction_x * (3.0 - 2.0 * fraction_x)
	var smooth_y := fraction_y * fraction_y * (3.0 - 2.0 * fraction_y)
	var x0 := posmod(cell_x, safe_cells)
	var y0 := posmod(cell_y, safe_cells)
	var x1 := (x0 + 1) % safe_cells
	var y1 := (y0 + 1) % safe_cells
	var top := lerpf(_hash_unit(x0, y0, seed), _hash_unit(x1, y0, seed), smooth_x)
	var bottom := lerpf(_hash_unit(x0, y1, seed), _hash_unit(x1, y1, seed), smooth_x)
	return lerpf(top, bottom, smooth_y)


static func _hash_unit(x: int, y: int, seed: int) -> float:
	# Integer-only hash keeps the bake stable across graphics backends. The
	# intermediate remains inside signed 64-bit range before the 31-bit mask.
	var value := (x * 374761393 + y * 668265263 + seed * 69069) & 0x7fffffff
	value = ((value ^ (value >> 13)) * 1274126177) & 0x7fffffff
	value = (value ^ (value >> 16)) & 0x7fffffff
	return float(value) / 2147483647.0


static func _sample_palette(colors: PackedColorArray, weight: float) -> Color:
	var scaled := clampf(weight, 0.0, 1.0) * float(colors.size() - 1)
	var first := mini(floori(scaled), colors.size() - 2)
	var blend := scaled - float(first)
	return colors[first].lerp(colors[first + 1], blend)
