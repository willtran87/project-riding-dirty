extends RefCounted
class_name RiderGraphicsCatalog
## Authored, cosmetic-only bike/rider graphics. Every choice is bounded so save
## data and Web commands can never inject arbitrary labels, colors, or geometry.

const TEAM_PALETTES: Array[Dictionary] = [
	{
		&"palette_id": &"STYLE",
		&"display_name": "Match Equipped Style",
		&"description": "Keep the active livery and jersey colors as the team base.",
		&"primary": "",
		&"secondary": "",
	},
	{
		&"palette_id": &"DUSTLINE",
		&"display_name": "Dustline Amber",
		&"description": "Warm amber bodywork over a deep slate secondary.",
		&"primary": "E39A32",
		&"secondary": "26333B",
	},
	{
		&"palette_id": &"WILDBRUSH",
		&"display_name": "Wildbrush Forest",
		&"description": "Forest green and trail-cream for an enduro works identity.",
		&"primary": "397B55",
		&"secondary": "E8D8A8",
	},
	{
		&"palette_id": &"SUNDOWN",
		&"display_name": "Sundown Heat",
		&"description": "Sunset magenta against near-black race panels.",
		&"primary": "D94C72",
		&"secondary": "211D27",
	},
	{
		&"palette_id": &"NIGHTSHIFT",
		&"display_name": "Nightshift Cyan",
		&"description": "Electric cyan over graphite for high-contrast night racing.",
		&"primary": "35B8D4",
		&"secondary": "162128",
	},
	{
		&"palette_id": &"CHAMPION",
		&"display_name": "Champion Gold",
		&"description": "Tour gold and black reserved for a decorated-looking build.",
		&"primary": "D5A62F",
		&"secondary": "1D2025",
	},
]

const DECALS: Array[Dictionary] = [
	{&"decal_id": &"CLEAN", &"display_name": "Clean Panels", &"description": "Unmarked team panels with a restrained factory finish."},
	{&"decal_id": &"SPEED_STRIPES", &"display_name": "Speed Stripes", &"description": "Twin directional stripes across both shrouds and rear fender."},
	{&"decal_id": &"CHECKERED", &"display_name": "Gate Checkers", &"description": "Compact checker blocks inspired by a race-gate board."},
	{&"decal_id": &"TOPO_LINES", &"display_name": "Topo Lines", &"description": "Layered terrain lines that echo the trail map."},
	{&"decal_id": &"LIGHTNING", &"display_name": "Lightning Cut", &"description": "A sharp broken bolt for an aggressive sprint identity."},
]

const SPONSORS: Array[Dictionary] = [
	{&"sponsor_id": &"NONE", &"display_name": "Privateer", &"short_mark": "", &"color": "FFFFFF"},
	{&"sponsor_id": &"DUSTLINE", &"display_name": "Dustline Moto", &"short_mark": "DL", &"color": "FFB52D"},
	{&"sponsor_id": &"WILDBRUSH", &"display_name": "Wildbrush Supply", &"short_mark": "WB", &"color": "7DD28F"},
	{&"sponsor_id": &"SUNDOWN", &"display_name": "Sundown Racing", &"short_mark": "SR", &"color": "F3708E"},
]

const SPONSOR_PLACEMENTS: Array[Dictionary] = [
	{&"placement_id": &"SHROUDS", &"display_name": "Bike Shrouds", &"description": "Place the sponsor badge on both side shrouds."},
	{&"placement_id": &"FENDERS", &"display_name": "Bike Fenders", &"description": "Place the sponsor badge across the front and rear fenders."},
	{&"placement_id": &"RIDER_KIT", &"display_name": "Rider Kit", &"description": "Place the sponsor badge on the rider chest and back."},
	{&"placement_id": &"FULL_KIT", &"display_name": "Full Race Kit", &"description": "Carry the sponsor across shrouds, fenders, chest, and back."},
]


static func workshop_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for palette: Dictionary in TEAM_PALETTES:
		var item := palette.duplicate(true)
		item[&"graphics_field"] = &"team_palette"
		item[&"choice_id"] = item.get(&"palette_id", &"STYLE")
		items.append(item)
	for decal: Dictionary in DECALS:
		var item := decal.duplicate(true)
		item[&"graphics_field"] = &"decal_id"
		item[&"choice_id"] = item.get(&"decal_id", &"CLEAN")
		items.append(item)
	for sponsor: Dictionary in SPONSORS:
		var item := sponsor.duplicate(true)
		item[&"graphics_field"] = &"sponsor_id"
		item[&"choice_id"] = item.get(&"sponsor_id", &"NONE")
		item[&"description"] = (
			"Remove sponsor marks for a clean privateer identity."
			if StringName(item[&"choice_id"]) == &"NONE"
			else "Equip this authored sponsor identity on the selected placement."
		)
		items.append(item)
	for placement: Dictionary in SPONSOR_PLACEMENTS:
		var item := placement.duplicate(true)
		item[&"graphics_field"] = &"sponsor_placement"
		item[&"choice_id"] = item.get(&"placement_id", &"SHROUDS")
		items.append(item)
	return items


static func sanitize_field(field: StringName, value: Variant) -> StringName:
	var normalized := StringName(str(value).strip_edges().to_upper())
	match field:
		&"team_palette":
			return normalized if _has_choice(TEAM_PALETTES, &"palette_id", normalized) else &"STYLE"
		&"decal_id":
			return normalized if _has_choice(DECALS, &"decal_id", normalized) else &"CLEAN"
		&"sponsor_id":
			return normalized if _has_choice(SPONSORS, &"sponsor_id", normalized) else &"NONE"
		&"sponsor_placement":
			return normalized if _has_choice(SPONSOR_PLACEMENTS, &"placement_id", normalized) else &"SHROUDS"
	return &""


static func palette(palette_id: Variant) -> Dictionary:
	return _choice(TEAM_PALETTES, &"palette_id", sanitize_field(&"team_palette", palette_id))


static func sponsor(sponsor_id: Variant) -> Dictionary:
	return _choice(SPONSORS, &"sponsor_id", sanitize_field(&"sponsor_id", sponsor_id))


static func _has_choice(options: Array[Dictionary], key: StringName, target: StringName) -> bool:
	for option: Dictionary in options:
		if StringName(option.get(key, &"")) == target:
			return true
	return false


static func _choice(options: Array[Dictionary], key: StringName, target: StringName) -> Dictionary:
	for option: Dictionary in options:
		if StringName(option.get(key, &"")) == target:
			return option.duplicate(true)
	return options[0].duplicate(true) if not options.is_empty() else {}
