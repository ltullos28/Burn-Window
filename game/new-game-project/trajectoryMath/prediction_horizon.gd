class_name PredictionHorizon
extends RefCounted

const PRIMARY_BODY_NAME := &"planet"

func get_broad_prediction_info(
	predictor: TrajectoryPredictor,
	orbit_solver: OrbitSolver,
	prediction_step_seconds: float,
	settings: Dictionary
) -> Dictionary:
	var focused_child_body_name: StringName = _get_focused_child_body_name(settings)
	if _is_ship_in_focused_child_dominance(focused_child_body_name):
		var focused_child_policy: Dictionary = _get_focused_child_policy(settings, focused_child_body_name)
		var local_steps: int = _get_period_based_prediction_steps(
			orbit_solver,
			prediction_step_seconds,
			settings,
			focused_child_body_name
		)
		var quick_prediction: Dictionary = predictor.compute(
			SimulationState.ship_pos,
			SimulationState.ship_vel,
			SimulationState.sim_time,
			prediction_step_seconds,
			local_steps,
			settings.get("extrema_window_radius", 4),
			settings.get("radial_extrema_tolerance", 4.0)
		)
		var local_bound_orbit: bool = _is_focused_child_bound_orbit(orbit_solver, focused_child_body_name)
		if not local_bound_orbit:
			var max_local_steps: int = focused_child_policy.get("local_max_prediction_steps", 1800)
			var escape_extension_steps: int = max(
				focused_child_policy.get("local_min_prediction_steps", 240),
				int(ceil(
					focused_child_policy.get("local_escape_prediction_seconds", 220.0) / max(prediction_step_seconds, 0.001)
				))
			)
			while local_steps < max_local_steps:
				var local_dominance: Array[bool] = _get_reference_dominance_mask(quick_prediction, focused_child_body_name)
				var entry_index: int = _find_first_true_index(local_dominance, local_dominance.size())
				var exit_index: int = -1
				if entry_index >= 0:
					exit_index = _find_first_false_index(local_dominance, entry_index + 1, local_dominance.size())
				if entry_index < 0 or exit_index >= 0:
					break

				var extended_steps: int = min(
					max_local_steps,
					max(
						local_steps + max(60, int(round(float(escape_extension_steps) * 0.50))),
						int(round(float(local_steps) * 1.60)),
						local_steps + max(120, int(round(90.0 / max(prediction_step_seconds, 0.001))))
					)
				)
				if extended_steps <= local_steps:
					break
				local_steps = extended_steps
				quick_prediction = predictor.compute(
					SimulationState.ship_pos,
					SimulationState.ship_vel,
					SimulationState.sim_time,
					prediction_step_seconds,
					local_steps,
					settings.get("extrema_window_radius", 4),
					settings.get("radial_extrema_tolerance", 4.0)
				)
		return {
			"steps": local_steps,
			"quick_prediction": quick_prediction,
		}

	var steps_from_zoom: int = _get_zoom_based_prediction_steps(settings)
	var steps_from_period: int = _get_period_based_prediction_steps(
		orbit_solver,
		prediction_step_seconds,
		settings,
		focused_child_body_name
	)
	var steps_to_use: int = max(steps_from_zoom, steps_from_period)

	var quick_prediction: Dictionary = predictor.compute(
		SimulationState.ship_pos,
		SimulationState.ship_vel,
		SimulationState.sim_time,
		prediction_step_seconds,
		steps_to_use,
		settings.get("extrema_window_radius", 4),
		settings.get("radial_extrema_tolerance", 4.0)
	)

	var child_prediction: Dictionary = _get_body_prediction(quick_prediction, focused_child_body_name)
	var child_closest_approach: Dictionary = child_prediction.get("closest_approach", {})
	var child_ca: float = child_closest_approach.get("distance", quick_prediction.get("moon_closest_approach_distance", -1.0))
	var child_tca: float = child_closest_approach.get("time", quick_prediction.get("moon_closest_approach_time", -1.0))
	var body_policy: Dictionary = _get_focused_child_policy(settings, focused_child_body_name)
	var strong_child_threshold: float = body_policy.get("strong_ca_distance", 0.0)

	if child_ca > 0.0 and child_ca <= strong_child_threshold and child_tca > 0.0:
		var encounter_steps: int = int(ceil((child_tca + body_policy.get("encounter_extra_time", 400.0)) / prediction_step_seconds))
		steps_to_use = max(steps_to_use, encounter_steps)

	steps_to_use = max(steps_to_use, settings.get("min_prediction_steps", 1200))
	steps_to_use = min(steps_to_use, settings.get("max_prediction_steps", 12000))

	var quick_matches_final_steps: bool = quick_prediction.get("ship_points", []).size() == steps_to_use
	return {
		"steps": steps_to_use,
		"quick_prediction": quick_prediction if quick_matches_final_steps else {},
	}

func get_continuity_trimmed_steps(
	prediction: Dictionary,
	reference_body_name: StringName,
	fallback_steps: int,
	settings: Dictionary
) -> int:
	var use_focused_child_reference: bool = reference_body_name != &""
	var relative_points: Array[Vector3] = _get_reference_relative_points(prediction, reference_body_name)
	var closure_index: int = _find_continuity_closure_index(relative_points, settings)
	if closure_index < 0:
		return fallback_steps

	if use_focused_child_reference:
		var body_dominance: Array[bool] = _get_reference_dominance_mask(prediction, reference_body_name)
		var dominance_limit: int = min(fallback_steps, body_dominance.size())
		var entry_index: int = _find_first_true_index(body_dominance, dominance_limit)
		var exit_index: int = -1
		if entry_index >= 0:
			exit_index = _find_first_false_index(body_dominance, entry_index + 1, dominance_limit)

		if entry_index >= 0:
			if exit_index >= 0 and closure_index < exit_index:
				return fallback_steps

			if exit_index < 0:
				var closure_segment_end: int = min(closure_index + 1, relative_points.size())
				var local_segment: Array[Vector3] = []
				for i in range(entry_index, closure_segment_end):
					local_segment.append(relative_points[i])

				var local_sweep: float = _compute_projected_angular_sweep(local_segment)
				if local_segment.size() < 12 or local_sweep < PI * 1.35:
					return fallback_steps

	var extra_steps: int = max(1, int(round(float(closure_index) / 6.0)))
	var trimmed_steps: int = closure_index + extra_steps
	if use_focused_child_reference:
		var body_policy: Dictionary = _get_focused_child_policy(settings, reference_body_name)
		return clampi(trimmed_steps, max(8, closure_index + 1), body_policy.get("local_max_prediction_steps", 1800))
	return clampi(trimmed_steps, max(8, closure_index + 1), settings.get("max_prediction_steps", 12000))

func _get_zoom_based_prediction_steps(settings: Dictionary) -> int:
	var zoom_alpha: float = inverse_lerp(
		settings.get("max_pixels_per_unit", 0.12),
		settings.get("min_pixels_per_unit", 0.0008),
		settings.get("pixels_per_unit", 0.046)
	)
	zoom_alpha = clampf(zoom_alpha, 0.0, 1.0)
	return int(round(lerpf(
		settings.get("min_prediction_steps", 1200),
		settings.get("max_prediction_steps", 12000),
		zoom_alpha
	)))

func _get_period_based_prediction_steps(
	orbit_solver: OrbitSolver,
	prediction_step_seconds: float,
	settings: Dictionary,
	focused_child_body_name: StringName
) -> int:
	if _is_ship_in_focused_child_dominance(focused_child_body_name):
		var child_body_pos: Vector3 = SimulationState.get_body_position(focused_child_body_name)
		var child_body_vel: Vector3 = SimulationState.get_body_velocity(focused_child_body_name)
		var body_policy: Dictionary = _get_focused_child_policy(settings, focused_child_body_name)
		var child_rel_pos: Vector3 = SimulationState.ship_pos - child_body_pos
		var child_rel_vel: Vector3 = SimulationState.ship_vel - child_body_vel
		var child_orbit: Dictionary = orbit_solver.solve_relative_orbit(
			child_rel_pos,
			child_rel_vel,
			SimulationState.get_body_mu(focused_child_body_name),
			SimulationState.get_body_radius(focused_child_body_name)
		)

		if child_orbit["is_bound_orbit"]:
			var child_period: float = child_orbit["orbital_period_value"]
			if child_period > 0.0:
				var child_needed_time: float = child_period * body_policy.get("local_period_margin", 1.15)
				var child_steps: int = int(ceil(child_needed_time / prediction_step_seconds))
				return clampi(
					child_steps,
					body_policy.get("local_min_prediction_steps", 240),
					body_policy.get("local_max_prediction_steps", 1800)
				)

		var child_escape_steps: int = int(ceil(body_policy.get("local_escape_prediction_seconds", 220.0) / prediction_step_seconds))
		return clampi(
			child_escape_steps,
			body_policy.get("local_min_prediction_steps", 240),
			body_policy.get("local_max_prediction_steps", 1800)
		)

	var orbit: Dictionary = orbit_solver.solve_planet_orbit(
		SimulationState.ship_pos,
		SimulationState.ship_vel,
		SimulationState.planet_pos,
		SimulationState.planet_mu,
		SimulationState.planet_radius
	)

	if not orbit["is_bound_orbit"]:
		return settings.get("prediction_steps", 4000)

	var period: float = orbit["orbital_period_value"]
	if period <= 0.0:
		return settings.get("prediction_steps", 4000)

	var needed_time: float = period * settings.get("period_prediction_margin", 1.0)
	return int(ceil(needed_time / prediction_step_seconds))

func _get_reference_relative_points(prediction: Dictionary, reference_body_name: StringName) -> Array[Vector3]:
	var result: Array[Vector3] = []
	var ship_points: Array[Vector3] = prediction.get("ship_points", [])
	if reference_body_name != &"":
		var body_prediction: Dictionary = _get_body_prediction(prediction, reference_body_name)
		var body_points: Array[Vector3] = _get_typed_vector3_array(
			body_prediction.get("relative_points", prediction.get("moon_points", []))
		)
		var point_count: int = min(ship_points.size(), body_points.size())
		for i in range(point_count):
			result.append(ship_points[i] - body_points[i])
		return result

	for point in ship_points:
		result.append(point)
	return result

func _get_focused_child_body_name(settings: Dictionary) -> StringName:
	var focused_child_body_name: StringName = settings.get("focused_child_body_name", &"")
	if focused_child_body_name != &"":
		return focused_child_body_name
	if SimulationState.has_method("get_child_body_names"):
		var child_body_names: Array[StringName] = SimulationState.get_child_body_names(PRIMARY_BODY_NAME)
		if child_body_names.size() > 0:
			return child_body_names[0]
	return &"moon" if SimulationState.has_body(&"moon") else &""

func _is_ship_in_focused_child_dominance(body_name: StringName) -> bool:
	if body_name == &"":
		return false
	if SimulationState.has_method("is_ship_in_body_dominance"):
		return SimulationState.is_ship_in_body_dominance(body_name)
	return body_name == &"moon" and SimulationState.is_ship_in_moon_dominance()

func _get_focused_child_policy(settings: Dictionary, body_name: StringName) -> Dictionary:
	var body_radius: float = max(SimulationState.get_body_radius(body_name), 1.0)
	var body_mu: float = max(SimulationState.get_body_mu(body_name), 0.0001)
	var characteristic_time: float = sqrt(pow(body_radius, 3.0) / body_mu)
	return {
		"strong_ca_distance": body_radius * settings.get("focused_child_strong_ca_body_radii", settings.get("strong_moon_ca_multiplier", 3.0)),
		"encounter_extra_time": characteristic_time * settings.get("focused_child_encounter_extra_characteristic_times", 7.2),
		"local_period_margin": settings.get("focused_child_local_period_margin", settings.get("moon_local_period_prediction_margin", 1.15)),
		"local_escape_prediction_seconds": characteristic_time * settings.get("focused_child_local_escape_characteristic_times", 3.5),
		"local_min_prediction_steps": settings.get("focused_child_local_min_prediction_steps", settings.get("moon_local_min_prediction_steps", 240)),
		"local_max_prediction_steps": settings.get("focused_child_local_max_prediction_steps", settings.get("moon_local_max_prediction_steps", 1800)),
	}

func _is_focused_child_bound_orbit(orbit_solver: OrbitSolver, body_name: StringName) -> bool:
	var body_pos: Vector3 = SimulationState.get_body_position(body_name)
	var body_vel: Vector3 = SimulationState.get_body_velocity(body_name)
	var local_orbit: Dictionary = orbit_solver.solve_relative_orbit(
		SimulationState.ship_pos - body_pos,
		SimulationState.ship_vel - body_vel,
		SimulationState.get_body_mu(body_name),
		SimulationState.get_body_radius(body_name)
	)
	return local_orbit.get("is_bound_orbit", false)

func _get_reference_dominance_mask(prediction: Dictionary, body_name: StringName) -> Array[bool]:
	var body_prediction: Dictionary = _get_body_prediction(prediction, body_name)
	var typed_values: Array[bool] = []
	for value in body_prediction.get("dominance_mask", prediction.get("moon_dominance", [])):
		typed_values.append(bool(value))
	return typed_values

func _get_body_prediction(prediction: Dictionary, body_name: StringName) -> Dictionary:
	var body_predictions: Dictionary = prediction.get("body_predictions", {})
	return body_predictions.get(String(body_name), {})

func _get_typed_vector3_array(values) -> Array[Vector3]:
	var typed_values: Array[Vector3] = []
	for value in values:
		typed_values.append(value)
	return typed_values

func _find_continuity_closure_index(relative_points: Array[Vector3], settings: Dictionary) -> int:
	if relative_points.size() < 8:
		return -1

	var start_point: Vector3 = relative_points[0]
	var start_radius: float = start_point.length()
	if start_radius <= 0.0001:
		return -1

	var mean_radius: float = 0.0
	for point in relative_points:
		mean_radius += point.length()
	mean_radius /= float(relative_points.size())

	var radius_scale: float = max(mean_radius, start_radius)
	if radius_scale <= 0.0001:
		return -1

	var mean_step_distance: float = 0.0
	var step_samples: int = 0
	var step_limit: int = min(relative_points.size() - 1, 24)
	for i in range(step_limit):
		mean_step_distance += relative_points[i + 1].distance_to(relative_points[i])
		step_samples += 1
	if step_samples > 0:
		mean_step_distance /= float(step_samples)

	var closure_threshold: float = max(
		radius_scale * settings.get("closure_distance_ratio_tolerance", 0.12),
		mean_step_distance * settings.get("closure_min_threshold_step_multiplier", 2.5)
	)
	var max_radius_threshold: float = max(
		mean_step_distance * 10.0,
		start_radius * 0.08
	)
	closure_threshold = min(closure_threshold, max_radius_threshold)
	var chunk_size: int = max(4, settings.get("closure_scan_chunk_steps", 24))
	var left_start_zone: bool = false
	var start_tangent: Vector3 = _get_local_tangent(relative_points, 0)

	for chunk_start in range(1, relative_points.size(), chunk_size):
		var chunk_end: int = min(chunk_start + chunk_size - 1, relative_points.size() - 1)
		var chunk_min_distance: float = INF
		var chunk_has_outside: bool = false

		for i in range(chunk_start, chunk_end + 1):
			var distance_to_start: float = relative_points[i].distance_to(start_point)
			chunk_min_distance = min(chunk_min_distance, distance_to_start)
			if distance_to_start > closure_threshold:
				chunk_has_outside = true

		if not left_start_zone:
			if chunk_has_outside:
				left_start_zone = true
			continue

		if chunk_min_distance > closure_threshold:
			continue

		var best_index: int = -1
		var best_distance: float = INF
		for i in range(chunk_start, chunk_end + 1):
			var point_distance: float = relative_points[i].distance_to(start_point)
			if point_distance > closure_threshold:
				continue
			if not _has_matching_closure_tangent(relative_points, i, start_tangent):
				continue
			if point_distance < best_distance:
				best_distance = point_distance
				best_index = i

		if best_index >= 0:
			return best_index

	return -1

func _get_local_tangent(points: Array[Vector3], index: int) -> Vector3:
	if points.size() < 2:
		return Vector3.ZERO

	var current_index: int = clampi(index, 0, points.size() - 1)
	var prev_index: int = max(current_index - 1, 0)
	var next_index: int = min(current_index + 1, points.size() - 1)
	var tangent: Vector3 = points[next_index] - points[prev_index]
	if tangent.length_squared() <= 0.0001 and current_index < points.size() - 1:
		tangent = points[current_index + 1] - points[current_index]
	if tangent.length_squared() <= 0.0001 and current_index > 0:
		tangent = points[current_index] - points[current_index - 1]
	return tangent.normalized()

func _find_first_true_index(values: Array[bool], max_count: int) -> int:
	var limit: int = min(values.size(), max_count)
	for i in range(limit):
		if values[i]:
			return i
	return -1

func _find_first_false_index(values: Array[bool], start_index: int, max_count: int) -> int:
	var limit: int = min(values.size(), max_count)
	for i in range(max(start_index, 0), limit):
		if not values[i]:
			return i
	return -1

func _compute_projected_angular_sweep(local_points: Array[Vector3]) -> float:
	if local_points.size() <= 1:
		return 0.0

	var cumulative_angle: float = 0.0
	var prev_angle: float = Vector2(local_points[0].x, -local_points[0].z).angle()

	for i in range(1, local_points.size()):
		var prev_proj: Vector2 = Vector2(local_points[i - 1].x, -local_points[i - 1].z)
		var curr_proj: Vector2 = Vector2(local_points[i].x, -local_points[i].z)
		if prev_proj.length_squared() < 0.0001 or curr_proj.length_squared() < 0.0001:
			continue

		var angle_i: float = curr_proj.angle()
		var dtheta: float = abs(wrapf(angle_i - prev_angle, -PI, PI))
		cumulative_angle += dtheta
		prev_angle = angle_i

	return cumulative_angle

func _has_matching_closure_tangent(points: Array[Vector3], candidate_index: int, start_tangent: Vector3) -> bool:
	if start_tangent.length_squared() <= 0.0001:
		return true

	var candidate_tangent: Vector3 = _get_local_tangent(points, candidate_index)
	if candidate_tangent.length_squared() <= 0.0001:
		return false

	return candidate_tangent.dot(start_tangent) >= 0.75
