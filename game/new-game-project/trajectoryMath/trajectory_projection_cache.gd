class_name TrajectoryProjectionCache
extends RefCounted

const CENTER_MODE_MOON := 1
const BodyPathImpactHelperModel := preload("res://trajectoryMath/body_path_impact_helper.gd")

var body_path_impact := BodyPathImpactHelperModel.new()

func build_cache(
	solution: TrajectorySolution,
	center_mode: int,
	focused_child_body_name: StringName,
	currently_in_focused_child_dominance: bool,
	local_orbit_markers: LocalOrbitMarkers,
	extrema_window_radius: int,
	closure_distance_ratio_tolerance: float,
	closure_scan_chunk_steps: int,
	closure_min_threshold_step_multiplier: float
) -> Dictionary:
	var cache: Dictionary = {
		"ship_source_points": [],
		"ship_runs": [],
		"main_visible_count": 0,
		"ship_impact_found": false,
		"ship_impact_index": -1,
		"focused_child_body_name": &"",
		"focused_child_draw_points": [],
		"focused_child_local_points": [],
		"focused_child_local_source_indices": [],
		"focused_child_local_ca_index": -1,
		"focused_child_local_pe_index": -1,
		"focused_child_local_ap_index": -1,
		"focused_child_local_impact_found": false,
		"focused_child_local_impact_index": -1,
		"focused_child_entry_index": -1,
		"focused_child_exit_index": -1,
		"show_focused_child_local_ca_marker": false,
		"show_focused_child_escape_marker": false,
		"focused_child_escape_marker_local_index": -1,
		"focused_child_encounter": {},
		"active_body_encounter": {},
		"currently_in_focused_child_dominance": currently_in_focused_child_dominance,
	}

	if solution.ship_points.size() <= 1:
		return cache

	cache["focused_child_body_name"] = focused_child_body_name
	if focused_child_body_name != &"":
		cache["focused_child_draw_points"] = solution.get_body_relative_points(focused_child_body_name)

	var visible_count: int = min(solution.ship_points.size(), max(2, solution.display_steps_used))
	if center_mode == CENTER_MODE_MOON and focused_child_body_name != &"":
		var focused_child_dominance: Array[bool] = solution.get_body_dominance_mask(focused_child_body_name)
		var focused_child_closest_approach: Dictionary = solution.get_body_closest_approach(focused_child_body_name)
		var local_analysis: Dictionary = local_orbit_markers.analyze(
			solution.ship_points,
			solution.get_body_relative_points(focused_child_body_name),
			focused_child_dominance,
			focused_child_closest_approach.get("index", -1),
			visible_count,
			extrema_window_radius,
			closure_distance_ratio_tolerance,
			closure_scan_chunk_steps,
			closure_min_threshold_step_multiplier
		)
		cache["focused_child_entry_index"] = local_analysis.get("entry_index", -1)
		cache["focused_child_exit_index"] = local_analysis.get("exit_index", -1)
		cache["focused_child_local_points"] = local_analysis.get("local_points", [])
		cache["focused_child_local_source_indices"] = local_analysis.get("local_source_indices", [])
		cache["focused_child_local_ca_index"] = local_analysis.get("local_ca_index", -1)
		cache["focused_child_local_pe_index"] = local_analysis.get("local_pe_index", -1)
		cache["focused_child_local_ap_index"] = local_analysis.get("local_ap_index", -1)
		cache["show_focused_child_local_ca_marker"] = local_analysis.get("show_local_ca_marker", false)
		cache["show_focused_child_escape_marker"] = local_analysis.get("show_escape_marker", false)
		cache["focused_child_escape_marker_local_index"] = local_analysis.get("escape_marker_local_index", -1)

		var focused_child_local_points: Array[Vector3] = []
		for point in cache["focused_child_local_points"]:
			focused_child_local_points.append(point)
		var focused_child_local_source_indices: Array[int] = []
		for source_index in cache["focused_child_local_source_indices"]:
			focused_child_local_source_indices.append(source_index)
		var focused_child_radius: float = SimulationState.get_body_radius(focused_child_body_name)
		var focused_child_local_trim: Dictionary = body_path_impact.trim_path(
			focused_child_local_points,
			focused_child_radius,
			focused_child_local_source_indices
		)
		cache["focused_child_local_points"] = focused_child_local_trim.get("points", [])
		cache["focused_child_local_source_indices"] = focused_child_local_trim.get("source_indices", [])
		cache["focused_child_local_impact_found"] = focused_child_local_trim.get("impact_found", false)
		cache["focused_child_local_impact_index"] = focused_child_local_trim.get("impact_index", -1)
		if cache["focused_child_local_impact_found"]:
			var trimmed_local_count: int = cache["focused_child_local_points"].size()
			if int(cache["focused_child_local_ca_index"]) >= trimmed_local_count:
				cache["focused_child_local_ca_index"] = -1
				cache["show_focused_child_local_ca_marker"] = false
			cache["focused_child_local_pe_index"] = -1
			cache["focused_child_local_ap_index"] = -1
			cache["show_focused_child_escape_marker"] = false
			cache["focused_child_escape_marker_local_index"] = -1

		var local_segment: Dictionary = {
			"entry_index": cache.get("focused_child_entry_index", -1),
			"exit_index": cache.get("focused_child_exit_index", -1),
			"points": cache.get("focused_child_local_points", []).duplicate(),
			"source_indices": cache.get("focused_child_local_source_indices", []).duplicate(),
		}
		var markers: Dictionary = {
			"local_ca_index": cache.get("focused_child_local_ca_index", -1),
			"local_pe_index": cache.get("focused_child_local_pe_index", -1),
			"local_ap_index": cache.get("focused_child_local_ap_index", -1),
			"show_local_ca_marker": cache.get("show_focused_child_local_ca_marker", false),
			"show_escape_marker": cache.get("show_focused_child_escape_marker", false),
			"escape_marker_local_index": cache.get("focused_child_escape_marker_local_index", -1),
		}
		var impact: Dictionary = {
			"found": cache.get("focused_child_local_impact_found", false),
			"index": cache.get("focused_child_local_impact_index", -1),
			"source_index": -1,
		}
		var impact_index: int = impact.get("index", -1)
		var local_source_indices_raw = local_segment.get("source_indices", [])
		if impact_index >= 0 and impact_index < local_source_indices_raw.size():
			impact["source_index"] = local_source_indices_raw[impact_index]
		solution.set_body_encounter_details(
			focused_child_body_name,
			local_segment,
			markers,
			impact,
			local_analysis.get("state", "NONE")
		)
		cache["focused_child_encounter"] = solution.get_body_encounter(focused_child_body_name)
		cache["active_body_encounter"] = cache["focused_child_encounter"]

	var main_visible_count: int = visible_count
	var focused_child_entry_index: int = cache.get("focused_child_entry_index", -1)
	if center_mode == CENTER_MODE_MOON and focused_child_entry_index >= 0:
		main_visible_count = max(2, focused_child_entry_index + 1)
	cache["main_visible_count"] = main_visible_count

	var ship_source_points: Array[Vector3] = []
	for i in range(main_visible_count):
		ship_source_points.append(solution.ship_points[i])
	var ship_trim: Dictionary = body_path_impact.trim_path(ship_source_points, SimulationState.planet_radius)
	var trimmed_ship_points: Array[Vector3] = []
	for point in ship_trim.get("points", []):
		trimmed_ship_points.append(point)
	cache["ship_source_points"] = trimmed_ship_points
	cache["ship_impact_found"] = ship_trim.get("impact_found", false)
	cache["ship_impact_index"] = ship_trim.get("impact_index", -1)
	cache["ship_runs"] = _build_main_ship_runs(trimmed_ship_points, solution.get_body_dominance_mask(focused_child_body_name), SimulationState.planet_radius)

	return cache

func _build_main_ship_runs(points: Array[Vector3], dominance_mask: Array[bool], occluder_radius: float) -> Array[Dictionary]:
	var runs: Array[Dictionary] = []
	if points.size() < 2:
		return runs

	var current_hidden: bool = false
	var current_color: Color = Color(0.6, 1.0, 0.7)
	var current_start: int = 0
	var initialized: bool = false

	for i in range(points.size() - 1):
		var seg_color := Color(0.6, 1.0, 0.7)
		if i < dominance_mask.size() and dominance_mask[i]:
			seg_color = Color(0.65, 0.75, 1.0)

		var mid_3d: Vector3 = (points[i] + points[i + 1]) * 0.5
		var projected_r: float = Vector2(mid_3d.x, mid_3d.z).length()
		var hidden: bool = projected_r < occluder_radius and mid_3d.y < 0.0

		if not initialized:
			current_hidden = hidden
			current_color = seg_color
			current_start = i
			initialized = true
			continue

		if hidden != current_hidden or seg_color != current_color:
			runs.append({
				"start": current_start,
				"end": i,
				"hidden": current_hidden,
				"color": current_color
			})
			current_start = i
			current_hidden = hidden
			current_color = seg_color

	if initialized:
		runs.append({
			"start": current_start,
			"end": points.size() - 1,
			"hidden": current_hidden,
			"color": current_color
		})

	return runs
