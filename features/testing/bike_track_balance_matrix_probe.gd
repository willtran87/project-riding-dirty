extends Node
## Cross-product compatibility and safety envelopes for every shipped bike,
## track, terrain surface, session surface modifier, handling kit, and required
## stock/max/extreme build state.

const BIKE_CATALOG := preload("res://features/career/racing_bike_catalog.gd")
const BIKE_BUILD := preload("res://features/career/racing_bike_build.gd")
const BIKE_CONTROLLER := preload("res://entities/bike/bike_controller.gd")

const TRACKS: Array[StringName] = [
	CourseCatalog.QUARRY_ID,
	CourseCatalog.PINE_ID,
	CourseCatalog.MESA_MX_ID,
]
const SETUPS: Array[StringName] = [&"TRAIL", &"BALANCED", &"ATTACK"]
const UPGRADE_SLOTS: Array[StringName] = [
	&"ENGINE", &"TIRES", &"SUSPENSION", &"BRAKES", &"CHASSIS",
]
const BUILD_VARIANTS: Array[StringName] = [
	&"STOCK", &"MAX_UPGRADES", &"EXTREME_NEGATIVE", &"EXTREME_POSITIVE",
]

var _failures: Array[String] = []
var _case_count := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var catalog: RacingBikeCatalog = BIKE_CATALOG.create_default()
	var bikes := catalog.get_bikes(0, true)
	var surfaces: Array[StringName] = BIKE_CONTROLLER.get_surface_types()
	var session_modifiers: Array[StringName] = BIKE_CONTROLLER.get_session_surface_modifiers()

	_check(bikes.size() == 3, "Expected all three production bikes")
	_check(surfaces.size() == 9, "Expected all nine mechanically distinct terrain surfaces")
	_check(session_modifiers.size() == 7, "Expected all seven production session surface modifiers")
	_check(_surface_profiles_are_distinct(surfaces), "Two terrain surfaces share an identical physical profile")
	_validate_surface_relationships()

	for track_id: StringName in TRACKS:
		var route := CourseCatalog.get_local_riding_points(track_id)
		_check(route.size() >= 12, "%s has no production riding route" % String(track_id))
		_check(_route_is_finite(route), "%s contains a non-finite route point" % String(track_id))
		_check(CourseCatalog.get_track_width(track_id) >= 12.0, "%s has an unsafe track width" % String(track_id))

	for bike_data: Dictionary in bikes:
		var bike_id := StringName(bike_data.get(&"bike_id", &""))
		var stock := _create_build(catalog, bike_id, &"STOCK")
		var upgraded := _create_build(catalog, bike_id, &"MAX_UPGRADES")
		_check(stock.installed_parts.is_empty(), "%s stock build contains installed parts" % String(bike_id))
		_check(
			upgraded.installed_parts.size() == UPGRADE_SLOTS.size(),
			"%s max build does not fill every compatible upgrade slot" % String(bike_id)
		)
		var stock_stats := stock.calculate_stats(catalog)
		var upgraded_stats := upgraded.calculate_stats(catalog)
		_check(
			float(upgraded_stats.get(&"overall", 0.0)) > float(stock_stats.get(&"overall", 0.0)),
			"%s maximum upgrades do not improve overall performance" % String(bike_id)
		)
		for track_id: StringName in TRACKS:
			for surface: StringName in surfaces:
				var profile: Dictionary = BIKE_CONTROLLER.surface_profile(surface)
				for session_modifier: StringName in session_modifiers:
					var session_grip := BIKE_CONTROLLER.session_surface_grip_multiplier(session_modifier)
					for setup: StringName in SETUPS:
						for variant: StringName in BUILD_VARIANTS:
							var build := _create_build(catalog, bike_id, variant)
							_validate_case(
								bike_id, track_id, surface, session_modifier, setup,
								variant, build, catalog, profile, session_grip
							)

	_validate_extreme_tune_tradeoffs(catalog)
	print(
		"BIKE TRACK BALANCE MATRIX PROBE: bikes=%d tracks=%d surfaces=%d session_modifiers=%d setups=%d builds=%d cases=%d passed=%s"
		% [
			bikes.size(), TRACKS.size(), surfaces.size(), session_modifiers.size(),
			SETUPS.size(), BUILD_VARIANTS.size(), _case_count, str(_failures.is_empty()),
		]
	)
	if _failures.is_empty():
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("BIKE TRACK BALANCE MATRIX PROBE: %s" % failure)
	get_tree().quit(1)


func _create_build(
	catalog: RacingBikeCatalog,
	bike_id: StringName,
	variant: StringName
) -> RacingBikeBuild:
	var build: RacingBikeBuild = BIKE_BUILD.new()
	build.bike_id = bike_id
	build.condition = 1.0
	if variant != &"STOCK":
		for slot: StringName in UPGRADE_SLOTS:
			var candidates := catalog.get_parts_for_slot(slot, bike_id, 9999, true)
			if candidates.is_empty():
				continue
			var selected := candidates[0]
			for candidate: Dictionary in candidates:
				if int(candidate.get(&"required_reputation", 0)) > int(selected.get(&"required_reputation", 0)):
					selected = candidate
			build.install_part(catalog, StringName(selected.get(&"part_id", &"")))
	if variant == &"EXTREME_NEGATIVE":
		build.tune = RacingBikeTune.from_dictionary(_extreme_tune(-1.0))
	elif variant == &"EXTREME_POSITIVE":
		build.tune = RacingBikeTune.from_dictionary(_extreme_tune(1.0))
	return build


func _validate_case(
	bike_id: StringName,
	track_id: StringName,
	surface: StringName,
	session_modifier: StringName,
	setup: StringName,
	variant: StringName,
	build: RacingBikeBuild,
	catalog: RacingBikeCatalog,
	profile: Dictionary,
	session_grip: float
) -> void:
	_case_count += 1
	var stats := build.calculate_stats(catalog)
	var runtime := BIKE_BUILD.runtime_projection(setup, stats, 100, build.tune.to_dictionary())
	var context := "%s/%s/%s/%s/%s/%s" % [
		String(bike_id), String(track_id), String(surface), String(session_modifier),
		String(setup), String(variant),
	]
	_check(not stats.is_empty(), "%s produced no calculated stats" % context)
	for stat: StringName in BIKE_BUILD.PERFORMANCE_STATS:
		var value := float(stats.get(stat, -1.0))
		_check(is_finite(value) and value >= 0.0 and value <= 100.0, "%s has unsafe %s stat" % [context, String(stat)])
	var friction := float(profile.get(&"friction", 0.0))
	var drag := float(profile.get(&"drag", 0.0))
	var effective_grip := float(runtime.get(&"lateral_grip", 0.0)) * friction * session_grip
	var effective_speed := float(runtime.get(&"maximum_speed_mps", 0.0)) / drag
	var envelope := {
		&"engine_force": [900.0, 1750.0],
		&"lateral_grip": [460.0, 840.0],
		&"spring_stiffness": [14_000.0, 28_000.0],
		&"spring_compression_damping": [270.0, 490.0],
		&"spring_rebound_damping": [1550.0, 3250.0],
		&"front_brake_bias": [0.20, 0.52],
		&"preload_impulse": [165.0, 315.0],
		&"maximum_speed_mps": [24.0, 43.0],
		&"brake_force": [2400.0, 3550.0],
		&"upright_strength": [8500.0, 11700.0],
		&"air_factor": [0.77, 1.21],
	}
	for raw_key: Variant in envelope:
		var key := StringName(raw_key)
		var bounds := envelope[key] as Array
		var value := float(runtime.get(key, NAN))
		_check(
			is_finite(value) and value >= float(bounds[0]) and value <= float(bounds[1]),
			"%s escapes the safe %s envelope (%s)" % [context, String(key), str(value)]
		)
	_check(
		is_finite(effective_grip) and effective_grip >= 285.0 and effective_grip <= 840.0,
		"%s produces unsafe effective surface grip (%s)" % [context, str(effective_grip)]
	)
	_check(
		is_finite(effective_speed) and effective_speed >= 12.5 and effective_speed <= 43.0,
		"%s produces unsafe drag-adjusted speed (%s)" % [context, str(effective_speed)]
	)


func _validate_extreme_tune_tradeoffs(catalog: RacingBikeCatalog) -> void:
	for bike_data: Dictionary in catalog.get_bikes(0, true):
		var bike_id := StringName(bike_data.get(&"bike_id", &""))
		var negative := _create_build(catalog, bike_id, &"EXTREME_NEGATIVE")
		var positive := _create_build(catalog, bike_id, &"EXTREME_POSITIVE")
		var negative_stats := negative.calculate_stats(catalog)
		var positive_stats := positive.calculate_stats(catalog)
		var negative_runtime := BIKE_BUILD.runtime_projection(
			&"BALANCED", negative_stats, 100, negative.tune.to_dictionary()
		)
		var positive_runtime := BIKE_BUILD.runtime_projection(
			&"BALANCED", positive_stats, 100, positive.tune.to_dictionary()
		)
		_check(
			float(positive_stats.get(&"acceleration", 0.0)) > float(negative_stats.get(&"acceleration", 0.0))
			and float(positive_stats.get(&"top_speed", 0.0)) < float(negative_stats.get(&"top_speed", 0.0)),
			"%s extreme gearing has no acceleration/top-speed tradeoff" % String(bike_id)
		)
		_check(
			float(positive_runtime.get(&"spring_stiffness", 0.0)) > float(negative_runtime.get(&"spring_stiffness", 0.0))
			and float(positive_runtime.get(&"spring_rebound_damping", 0.0)) > float(negative_runtime.get(&"spring_rebound_damping", 0.0))
			and float(positive_runtime.get(&"front_brake_bias", 0.0)) > float(negative_runtime.get(&"front_brake_bias", 0.0))
			and float(positive_runtime.get(&"preload_impulse", 0.0)) > float(negative_runtime.get(&"preload_impulse", 0.0)),
			"%s extreme chassis tuning does not reach each physical solver parameter" % String(bike_id)
		)


func _validate_surface_relationships() -> void:
	var packed := BIKE_CONTROLLER.surface_profile(&"PACKED")
	var loose := BIKE_CONTROLLER.surface_profile(&"LOOSE_DIRT")
	var sand := BIKE_CONTROLLER.surface_profile(&"SAND")
	var grass := BIKE_CONTROLLER.surface_profile(&"GRASS")
	_check(
		BIKE_CONTROLLER.canonical_surface(&"SAND") == &"SAND"
		and BIKE_CONTROLLER.canonical_surface(&"GRASS") == &"GRASS",
		"Sand or grass aliases collapse into an older terrain identity"
	)
	_check(
		sand != loose and grass != packed,
		"Sand or grass shares the complete physical profile of its former fallback"
	)
	_check(
		float(sand.get(&"friction", 0.0)) < float(grass.get(&"friction", 0.0))
		and float(sand.get(&"drag", 0.0)) > float(grass.get(&"drag", 0.0))
		and float(sand.get(&"roost", 0.0)) > float(grass.get(&"roost", 0.0)),
		"Sand does not preserve its intended low-grip, high-drag, high-roost tradeoff"
	)
	_check(
		BIKE_CONTROLLER.session_surface_grip_multiplier(&"SAND")
		< BIKE_CONTROLLER.session_surface_grip_multiplier(&"GRASS")
		and BIKE_CONTROLLER.session_surface_grip_multiplier(&"GRASS") < 1.0,
		"Sand and grass session modifiers are not ordered or physically meaningful"
	)


func _surface_profiles_are_distinct(surfaces: Array[StringName]) -> bool:
	var signatures := {}
	for surface: StringName in surfaces:
		var profile: Dictionary = BIKE_CONTROLLER.surface_profile(surface)
		var signature := "%.3f|%.3f|%.3f|%.3f" % [
			float(profile.get(&"friction", 0.0)),
			float(profile.get(&"drag", 0.0)),
			float(profile.get(&"roughness", 0.0)),
			float(profile.get(&"roost", 0.0)),
		]
		if signatures.has(signature):
			return false
		signatures[signature] = surface
	return true


func _route_is_finite(route: PackedVector3Array) -> bool:
	for point: Vector3 in route:
		if not point.is_finite():
			return false
	return true


func _extreme_tune(value: float) -> Dictionary:
	return {
		&"gearing": value,
		&"tire_grip": value,
		&"suspension_stiffness": value,
		&"suspension_damping": value,
		&"preload": value,
		&"brake_bias": value,
	}


func _check(condition: bool, failure: String) -> void:
	if not condition:
		_failures.append(failure)
