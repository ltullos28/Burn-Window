class_name TrajectoryPredictor
extends RefCounted

func _compute_inverse_square_gravity(mu: float, distance: float) -> float:
	if mu <= 0.0 or distance <= 0.0001:
		return 0.0
	return mu / (distance * distance)

func _compile_bodies() -> Array[Dictionary]:
	var unresolved: Dictionary = {}
	for body_name in SimulationState.get_body_names():
		var record: Dictionary = SimulationState.get_body_record(body_name)
		if record.is_empty():
			continue

		var orbit: Dictionary = record.get("orbit", {})
		var parent_body_name: StringName = record.get("parent_body", &"")
		unresolved[String(body_name)] = {
			"name": body_name,
			"mu": record.get("mu", 0.0),
			"parent_body": parent_body_name,
			"static_pos": record.get("pos", Vector3.ZERO),
			"static_vel": record.get("vel", Vector3.ZERO),
			"orbit_center_distance": orbit.get("center_distance", 0.0),
			"orbit_semi_major_axis": orbit.get("semi_major_axis", orbit.get("center_distance", 0.0)),
			"orbit_phase": orbit.get("phase", 0.0),
			"orbit_angular_speed": orbit.get("angular_speed", 0.0),
			"orbit_linear_speed": orbit.get("linear_speed", 0.0),
			"orbit_eccentricity": orbit.get("eccentricity", 0.0),
			"orbit_inclination_radians": orbit.get("inclination_radians", 0.0),
			"orbit_ascending_node_radians": orbit.get("ascending_node_radians", 0.0),
			"orbit_argument_of_periapsis_radians": orbit.get("argument_of_periapsis_radians", 0.0),
			"is_on_rails": parent_body_name != &"" and not orbit.is_empty(),
		}

	var compiled: Array[Dictionary] = []
	while not unresolved.is_empty():
		var resolved_one: bool = false
		for body_key in unresolved.keys():
			var body: Dictionary = unresolved[body_key]
			var parent_body_name: StringName = body.get("parent_body", &"")
			if parent_body_name == &"" or _find_compiled_body_index(compiled, parent_body_name) >= 0:
				body["parent_index"] = _find_compiled_body_index(compiled, parent_body_name)
				compiled.append(body)
				unresolved.erase(body_key)
				resolved_one = true
				break

		if resolved_one:
			continue

		# Fallback for unexpected cycles or bad data: append remaining bodies in arbitrary order.
		for body_key in unresolved.keys():
			var body: Dictionary = unresolved[body_key]
			body["parent_index"] = -1
			compiled.append(body)
		unresolved.clear()

	return compiled

func _find_compiled_body_index(compiled_bodies: Array[Dictionary], body_name: StringName) -> int:
	for i in range(compiled_bodies.size()):
		if compiled_bodies[i].get("name", &"") == body_name:
			return i
	return -1

func _evaluate_body_states_for_time(
	compiled_bodies: Array[Dictionary],
	query_time: float,
	body_positions: Array[Vector3],
	body_velocities: Array[Vector3]
) -> void:
	body_positions.clear()
	body_velocities.clear()

	for body in compiled_bodies:
		if not body.get("is_on_rails", false):
			body_positions.append(body.get("static_pos", Vector3.ZERO))
			body_velocities.append(body.get("static_vel", Vector3.ZERO))
			continue

		var parent_index: int = body.get("parent_index", -1)
		var parent_pos: Vector3 = Vector3.ZERO
		var parent_vel: Vector3 = Vector3.ZERO
		if parent_index >= 0 and parent_index < body_positions.size():
			parent_pos = body_positions[parent_index]
			parent_vel = body_velocities[parent_index]

		var semi_major_axis: float = float(body.get("orbit_semi_major_axis", body.get("orbit_center_distance", 0.0)))
		var orbit_phase: float = float(body.get("orbit_phase", 0.0))
		var orbit_angular_speed: float = float(body.get("orbit_angular_speed", 0.0))
		var orbit_linear_speed: float = float(body.get("orbit_linear_speed", 0.0))
		var eccentricity: float = clampf(float(body.get("orbit_eccentricity", 0.0)), 0.0, 0.8)
		var inclination_radians: float = float(body.get("orbit_inclination_radians", 0.0))
		var ascending_node_radians: float = float(body.get("orbit_ascending_node_radians", 0.0))
		var argument_of_periapsis_radians: float = float(body.get("orbit_argument_of_periapsis_radians", 0.0))
		var mean_anomaly: float = orbit_phase + query_time * orbit_angular_speed
		var eccentric_anomaly: float = _solve_kepler_equation(mean_anomaly, eccentricity)
		var sqrt_term: float = sqrt(maxf(1.0 - eccentricity * eccentricity, 0.000001))
		var cos_e: float = cos(eccentric_anomaly)
		var sin_e: float = sin(eccentric_anomaly)
		var radius: float = maxf(semi_major_axis * (1.0 - eccentricity * cos_e), 0.001)

		var perifocal_position: Vector3 = Vector3(
			semi_major_axis * (cos_e - eccentricity),
			0.0,
			semi_major_axis * sqrt_term * sin_e
		)

		var parent_mu: float = 0.0
		if parent_index >= 0 and parent_index < compiled_bodies.size():
			parent_mu = float(compiled_bodies[parent_index].get("mu", 0.0))
		var speed_scale: float = orbit_linear_speed
		if parent_mu > 0.0 and semi_major_axis > 0.0:
			speed_scale = sqrt(maxf(parent_mu * semi_major_axis, 0.0)) / radius

		var perifocal_velocity: Vector3 = Vector3(
			-sin_e * speed_scale,
			0.0,
			sqrt_term * cos_e * speed_scale
		)

		# Keep predictor body motion aligned with SimulationState's runtime orbit
		# convention so projected child ghost paths match live child-body positions.
		var orbit_basis: Basis = SimulationState.build_orbit_basis_from_elements(
			ascending_node_radians,
			inclination_radians,
			argument_of_periapsis_radians
		)

		var local_offset: Vector3 = orbit_basis * perifocal_position
		var tangent: Vector3 = orbit_basis * perifocal_velocity

		body_positions.append(parent_pos + local_offset)
		body_velocities.append(parent_vel + tangent)

func _solve_kepler_equation(mean_anomaly: float, eccentricity: float) -> float:
	var wrapped_mean_anomaly: float = wrapf(mean_anomaly, -PI, PI)
	if eccentricity <= 0.0001:
		return wrapped_mean_anomaly

	var eccentric_anomaly: float = wrapped_mean_anomaly
	for _i in range(8):
		var f: float = eccentric_anomaly - eccentricity * sin(eccentric_anomaly) - wrapped_mean_anomaly
		var derivative: float = 1.0 - eccentricity * cos(eccentric_anomaly)
		if absf(derivative) <= 0.000001:
			break
		eccentric_anomaly -= f / derivative
	return eccentric_anomaly

func _gravity_from_body(position: Vector3, body_pos: Vector3, mu: float, min_gravity_distance: float) -> Vector3:
	var offset: Vector3 = body_pos - position
	var distance: float = max(offset.length(), min_gravity_distance)
	return offset * mu / pow(distance, 3.0)

func _gravity_accel(position: Vector3, compiled_bodies: Array[Dictionary], body_positions: Array[Vector3]) -> Vector3:
	var accel: Vector3 = Vector3.ZERO
	var body_count: int = min(compiled_bodies.size(), body_positions.size())
	for i in range(body_count):
		var body_mu: float = compiled_bodies[i].get("mu", 0.0)
		if body_mu <= 0.0:
			continue
		accel += _gravity_from_body(position, body_positions[i], body_mu, SimulationState.min_gravity_distance)
	return accel

func _project_planet_frame(point: Vector3) -> Vector2:
	return Vector2(point.x, -point.z)

func _find_first_local_minimum_index(radii: Array[float], start_index: int) -> int:
	if radii.size() < 3:
		return -1

	var start_i: int = max(1, start_index)
	var end_i: int = radii.size() - 2

	for i in range(start_i, end_i + 1):
		if radii[i] <= radii[i - 1] and radii[i] <= radii[i + 1]:
			if radii[i] < radii[i - 1] or radii[i] < radii[i + 1]:
				return i

	return -1

func _find_first_local_maximum_index(radii: Array[float], start_index: int) -> int:
	if radii.size() < 3:
		return -1

	var start_i: int = max(1, start_index)
	var end_i: int = radii.size() - 2

	for i in range(start_i, end_i + 1):
		if radii[i] >= radii[i - 1] and radii[i] >= radii[i + 1]:
			if radii[i] > radii[i - 1] or radii[i] > radii[i + 1]:
				return i

	return -1

func _refine_extremum_to_local_best(
	radii: Array[float],
	center_index: int,
	search_radius: int,
	find_maximum: bool
) -> int:
	if radii.is_empty():
		return center_index

	var start_i: int = max(0, center_index - search_radius)
	var end_i: int = min(radii.size() - 1, center_index + search_radius)

	var best_index: int = center_index
	var best_value: float = radii[center_index]

	for i in range(start_i, end_i + 1):
		if find_maximum:
			if radii[i] > best_value:
				best_value = radii[i]
				best_index = i
		else:
			if radii[i] < best_value:
				best_value = radii[i]
				best_index = i

	return best_index

func _build_smoothed_radii(radii: Array[float], half_window: int) -> Array[float]:
	var smoothed: Array[float] = []

	if radii.is_empty():
		return smoothed

	var use_half_window: int = max(1, half_window)

	for i in range(radii.size()):
		var start_i: int = max(0, i - use_half_window)
		var end_i: int = min(radii.size() - 1, i + use_half_window)

		var sum: float = 0.0
		var count: int = 0

		for j in range(start_i, end_i + 1):
			sum += radii[j]
			count += 1

		smoothed.append(sum / float(count))

	return smoothed

func _find_closest_projected_index_to_point_in_range(
	points: Array[Vector3],
	target_point_proj: Vector2,
	start_index: int,
	end_index: int
) -> int:
	if points.is_empty():
		return -1

	var start_i: int = clampi(start_index, 0, points.size() - 1)
	var end_i: int = clampi(end_index, 0, points.size() - 1)

	if end_i < start_i:
		return -1

	var best_index: int = -1
	var best_dist_sq: float = INF

	for i in range(start_i, end_i + 1):
		var point_proj: Vector2 = _project_planet_frame(points[i])
		var dist_sq: float = point_proj.distance_squared_to(target_point_proj)
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best_index = i

	return best_index

func _find_local_chunk_end(ship_points: Array[Vector3], start_index: int) -> int:
	if ship_points.size() <= start_index + 1:
		return start_index

	var max_end: int = min(
		ship_points.size() - 1,
		start_index + max(180, int(ship_points.size() * 0.30))
	)

	var cumulative_angle: float = 0.0
	var prev_angle: float = _project_planet_frame(ship_points[start_index]).angle()

	for i in range(start_index + 1, max_end + 1):
		var prev_proj: Vector2 = _project_planet_frame(ship_points[i - 1])
		var curr_proj: Vector2 = _project_planet_frame(ship_points[i])

		if prev_proj.length_squared() < 0.0001 or curr_proj.length_squared() < 0.0001:
			continue

		var angle_i: float = curr_proj.angle()
		var dtheta: float = abs(wrapf(angle_i - prev_angle, -PI, PI))
		cumulative_angle += dtheta
		prev_angle = angle_i

		if cumulative_angle >= PI * 1.35:
			return i

	return max_end

func create_prediction_job(
	ship_pos: Vector3,
	ship_vel: Vector3,
	sim_time: float,
	prediction_step_seconds: float,
	prediction_steps: int,
	extrema_window_radius: int,
	radial_extrema_tolerance: float
) -> Dictionary:
	var compiled_bodies: Array[Dictionary] = _compile_bodies()
	var ship_points: Array[Vector3] = []
	var ship_velocities: Array[Vector3] = []
	var planet_radii: Array[float] = []
	var body_positions: Array[Vector3] = []
	var body_velocities: Array[Vector3] = []
	var planet_body_index: int = _find_compiled_body_index(compiled_bodies, &"planet")
	var child_body_infos: Array[Dictionary] = []
	var child_relative_points: Array = []
	var child_dominance_masks: Array = []
	var child_best_distances: Array[float] = []
	var child_best_times: Array[float] = []
	var child_best_relative_speeds: Array[float] = []
	var child_best_indices: Array[int] = []

	for i in range(compiled_bodies.size()):
		var body: Dictionary = compiled_bodies[i]
		var parent_index: int = body.get("parent_index", -1)
		if parent_index < 0 or parent_index >= compiled_bodies.size():
			continue
		var body_name: StringName = body.get("name", &"")
		var parent_body_name: StringName = compiled_bodies[parent_index].get("name", &"")
		child_body_infos.append({
			"body_name": body_name,
			"parent_body_name": parent_body_name,
			"body_index": i,
			"parent_index": parent_index,
		})
		child_relative_points.append([])
		child_dominance_masks.append([])
		child_best_distances.append(INF)
		child_best_times.append(-1.0)
		child_best_relative_speeds.append(-1.0)
		child_best_indices.append(-1)

	var initial_rel_ship_planet: Vector3 = ship_pos - SimulationState.planet_pos
	return {
		"prediction_step_seconds": prediction_step_seconds,
		"prediction_steps": max(prediction_steps, 0),
		"extrema_window_radius": extrema_window_radius,
		"radial_extrema_tolerance": radial_extrema_tolerance,
		"compiled_bodies": compiled_bodies,
		"planet_body_index": planet_body_index,
		"child_body_infos": child_body_infos,
		"child_relative_points": child_relative_points,
		"child_dominance_masks": child_dominance_masks,
		"child_best_distances": child_best_distances,
		"child_best_times": child_best_times,
		"child_best_relative_speeds": child_best_relative_speeds,
		"child_best_indices": child_best_indices,
		"ship_points": ship_points,
		"ship_velocities": ship_velocities,
		"planet_radii": planet_radii,
		"body_positions": body_positions,
		"body_velocities": body_velocities,
		"test_pos": ship_pos,
		"test_vel": ship_vel,
		"test_time": sim_time,
		"closest_approach_distance": initial_rel_ship_planet.length(),
		"closest_approach_time": 0.0,
		"step_index": 0,
	}

func get_prediction_job_total_steps(job: Dictionary) -> int:
	return int(job.get("prediction_steps", 0))

func get_prediction_job_completed_steps(job: Dictionary) -> int:
	return int(job.get("step_index", 0))

func get_prediction_job_progress(job: Dictionary) -> float:
	var total_steps: int = max(get_prediction_job_total_steps(job), 1)
	return clampf(float(get_prediction_job_completed_steps(job)) / float(total_steps), 0.0, 1.0)

func is_prediction_job_complete(job: Dictionary) -> bool:
	return get_prediction_job_completed_steps(job) >= get_prediction_job_total_steps(job)

func step_prediction_job(job: Dictionary, max_steps: int) -> void:
	var steps_to_run: int = max(max_steps, 0)
	if steps_to_run <= 0:
		return
	while steps_to_run > 0 and not is_prediction_job_complete(job):
		_step_prediction_job_once(job)
		job["step_index"] = get_prediction_job_completed_steps(job) + 1
		steps_to_run -= 1

func _step_prediction_job_once(job: Dictionary) -> void:
	var empty_compiled_bodies: Array[Dictionary] = []
	var empty_vector3_array: Array[Vector3] = []
	var empty_float_array: Array[float] = []
	var empty_int_array: Array[int] = []
	var compiled_bodies: Array[Dictionary] = job.get("compiled_bodies", empty_compiled_bodies)
	var body_positions: Array[Vector3] = job.get("body_positions", empty_vector3_array)
	var body_velocities: Array[Vector3] = job.get("body_velocities", empty_vector3_array)
	var planet_body_index: int = job.get("planet_body_index", -1)
	var child_body_infos: Array[Dictionary] = job.get("child_body_infos", empty_compiled_bodies)
	var child_relative_points: Array = job.get("child_relative_points", [])
	var child_dominance_masks: Array = job.get("child_dominance_masks", [])
	var child_best_distances: Array[float] = job.get("child_best_distances", empty_float_array)
	var child_best_times: Array[float] = job.get("child_best_times", empty_float_array)
	var child_best_relative_speeds: Array[float] = job.get("child_best_relative_speeds", empty_float_array)
	var child_best_indices: Array[int] = job.get("child_best_indices", empty_int_array)
	var ship_points: Array[Vector3] = job.get("ship_points", empty_vector3_array)
	var ship_velocities: Array[Vector3] = job.get("ship_velocities", empty_vector3_array)
	var planet_radii: Array[float] = job.get("planet_radii", empty_float_array)
	var test_pos: Vector3 = job.get("test_pos", Vector3.ZERO)
	var test_vel: Vector3 = job.get("test_vel", Vector3.ZERO)
	var test_time: float = job.get("test_time", 0.0)
	var prediction_step_seconds: float = job.get("prediction_step_seconds", 0.0)
	var closest_approach_distance: float = job.get("closest_approach_distance", INF)
	var closest_approach_time: float = job.get("closest_approach_time", -1.0)
	var step_index: int = get_prediction_job_completed_steps(job)

	_evaluate_body_states_for_time(compiled_bodies, test_time, body_positions, body_velocities)
	var predicted_planet_pos: Vector3 = SimulationState.planet_pos
	if planet_body_index >= 0 and planet_body_index < body_positions.size():
		predicted_planet_pos = body_positions[planet_body_index]
	var rel_ship_planet: Vector3 = test_pos - predicted_planet_pos

	ship_points.append(rel_ship_planet)
	ship_velocities.append(test_vel)

	var report_t: float = float(step_index) * prediction_step_seconds
	var true_radius: float = rel_ship_planet.length()
	planet_radii.append(true_radius)

	if true_radius < closest_approach_distance:
		closest_approach_distance = true_radius
		closest_approach_time = report_t

	for child_i in range(child_body_infos.size()):
		var body_info: Dictionary = child_body_infos[child_i]
		var body_index: int = body_info.get("body_index", -1)
		var parent_index: int = body_info.get("parent_index", -1)
		if body_index < 0 or parent_index < 0:
			continue
		if body_index >= body_positions.size() or parent_index >= body_positions.size():
			continue

		var predicted_body_pos: Vector3 = body_positions[body_index]
		var predicted_parent_pos: Vector3 = body_positions[parent_index]
		var predicted_body_vel: Vector3 = body_velocities[body_index] if body_index < body_velocities.size() else Vector3.ZERO
		var rel_body_parent: Vector3 = predicted_body_pos - predicted_parent_pos
		child_relative_points[child_i].append(rel_body_parent)

		var d_body: float = (test_pos - predicted_body_pos).length()
		if d_body < child_best_distances[child_i]:
			child_best_distances[child_i] = d_body
			child_best_times[child_i] = report_t
			child_best_relative_speeds[child_i] = (test_vel - predicted_body_vel).length()
			child_best_indices[child_i] = step_index

	var child_body_gravities: Array[float] = []
	var child_parent_gravities: Array[float] = []
	child_body_gravities.resize(child_body_infos.size())
	child_parent_gravities.resize(child_body_infos.size())
	var dominant_child_index_by_parent: Dictionary = {}
	var dominant_child_gravity_by_parent: Dictionary = {}

	for child_i in range(child_body_infos.size()):
		var body_info: Dictionary = child_body_infos[child_i]
		var body_index: int = body_info.get("body_index", -1)
		var parent_index: int = body_info.get("parent_index", -1)
		if body_index < 0 or parent_index < 0:
			child_body_gravities[child_i] = 0.0
			child_parent_gravities[child_i] = 0.0
			continue
		if body_index >= body_positions.size() or parent_index >= body_positions.size():
			child_body_gravities[child_i] = 0.0
			child_parent_gravities[child_i] = 0.0
			continue

		var body_mu: float = compiled_bodies[body_index].get("mu", 0.0)
		var parent_mu: float = compiled_bodies[parent_index].get("mu", 0.0)
		var d_body: float = (test_pos - body_positions[body_index]).length()
		var d_parent: float = (test_pos - body_positions[parent_index]).length()
		var g_body: float = _compute_inverse_square_gravity(body_mu, d_body)
		var g_parent: float = _compute_inverse_square_gravity(parent_mu, d_parent)
		child_body_gravities[child_i] = g_body
		child_parent_gravities[child_i] = g_parent

		if g_body <= g_parent:
			continue
		var current_best_child_index: int = int(dominant_child_index_by_parent.get(parent_index, -1))
		var current_best_gravity: float = float(dominant_child_gravity_by_parent.get(parent_index, -1.0))
		if current_best_child_index < 0 or g_body > current_best_gravity:
			dominant_child_index_by_parent[parent_index] = child_i
			dominant_child_gravity_by_parent[parent_index] = g_body

	for child_i in range(child_body_infos.size()):
		var body_info: Dictionary = child_body_infos[child_i]
		var parent_index: int = body_info.get("parent_index", -1)
		var dominant_child_index: int = int(dominant_child_index_by_parent.get(parent_index, -1))
		var g_body: float = child_body_gravities[child_i]
		var g_parent: float = child_parent_gravities[child_i]
		child_dominance_masks[child_i].append(g_body > g_parent and dominant_child_index == child_i)

	var accel: Vector3 = _gravity_accel(test_pos, compiled_bodies, body_positions)
	test_vel += accel * prediction_step_seconds
	test_pos += test_vel * prediction_step_seconds
	test_time += prediction_step_seconds

	job["test_pos"] = test_pos
	job["test_vel"] = test_vel
	job["test_time"] = test_time
	job["closest_approach_distance"] = closest_approach_distance
	job["closest_approach_time"] = closest_approach_time

func build_prediction_from_job(job: Dictionary) -> Dictionary:
	var empty_compiled_bodies: Array[Dictionary] = []
	var empty_vector3_array: Array[Vector3] = []
	var empty_float_array: Array[float] = []
	var empty_int_array: Array[int] = []
	var ship_points: Array[Vector3] = job.get("ship_points", empty_vector3_array)
	var ship_velocities: Array[Vector3] = job.get("ship_velocities", empty_vector3_array)
	var planet_radii: Array[float] = job.get("planet_radii", empty_float_array)
	var child_body_infos: Array[Dictionary] = job.get("child_body_infos", empty_compiled_bodies)
	var child_relative_points: Array = job.get("child_relative_points", [])
	var child_dominance_masks: Array = job.get("child_dominance_masks", [])
	var child_best_distances: Array[float] = job.get("child_best_distances", empty_float_array)
	var child_best_times: Array[float] = job.get("child_best_times", empty_float_array)
	var child_best_relative_speeds: Array[float] = job.get("child_best_relative_speeds", empty_float_array)
	var child_best_indices: Array[int] = job.get("child_best_indices", empty_int_array)
	var prediction_step_seconds: float = job.get("prediction_step_seconds", 0.0)
	var extrema_window_radius: int = job.get("extrema_window_radius", 4)
	var closest_approach_distance: float = job.get("closest_approach_distance", -1.0)
	var closest_approach_time: float = job.get("closest_approach_time", -1.0)

	var predicted_periapsis_distance: float = -1.0
	var predicted_apoapsis_distance: float = -1.0
	var predicted_periapsis_time: float = -1.0
	var predicted_apoapsis_time: float = -1.0
	var predicted_periapsis_index: int = -1
	var predicted_apoapsis_index: int = -1

	if planet_radii.size() >= 3:
		var smoothing_half_window: int = clampi(int(extrema_window_radius / 2) + 1, 2, 4)
		var smoothed_radii: Array[float] = _build_smoothed_radii(planet_radii, smoothing_half_window)
		var next_pe_index: int = _find_first_local_minimum_index(smoothed_radii, 1)
		var next_ap_index: int = _find_first_local_maximum_index(smoothed_radii, 1)

		if next_pe_index >= 0 and next_pe_index < ship_points.size():
			next_pe_index = _refine_extremum_to_local_best(planet_radii, next_pe_index, 4, false)
			predicted_periapsis_index = next_pe_index
			predicted_periapsis_distance = planet_radii[next_pe_index]
			predicted_periapsis_time = float(next_pe_index) * prediction_step_seconds

		if next_ap_index >= 0 and next_ap_index < ship_points.size():
			next_ap_index = _refine_extremum_to_local_best(planet_radii, next_ap_index, 4, true)
			predicted_apoapsis_index = next_ap_index
			predicted_apoapsis_distance = planet_radii[next_ap_index]
			predicted_apoapsis_time = float(next_ap_index) * prediction_step_seconds

		var chunk_start: int = 0
		var chunk_end: int = _find_local_chunk_end(ship_points, chunk_start)
		if chunk_end > chunk_start + 6:
			var local_min_r: float = INF
			var local_max_r: float = -INF
			var local_mean_r: float = 0.0
			var local_count: int = 0
			for i in range(chunk_start, chunk_end + 1):
				var r: float = smoothed_radii[i]
				local_min_r = min(local_min_r, r)
				local_max_r = max(local_max_r, r)
				local_mean_r += r
				local_count += 1
			if local_count > 0:
				local_mean_r /= float(local_count)
				var local_spread_ratio: float = 0.0
				if local_mean_r > 0.0001:
					local_spread_ratio = (local_max_r - local_min_r) / local_mean_r
				var looks_near_circular: bool = local_spread_ratio < 0.012
				var apsides_missing_or_collapsed: bool = false
				if predicted_periapsis_index < 0 or predicted_apoapsis_index < 0:
					apsides_missing_or_collapsed = true
				else:
					var pe_vec: Vector2 = _project_planet_frame(ship_points[predicted_periapsis_index])
					var ap_vec: Vector2 = _project_planet_frame(ship_points[predicted_apoapsis_index])
					if pe_vec.length_squared() <= 0.0001 or ap_vec.length_squared() <= 0.0001:
						apsides_missing_or_collapsed = true
					else:
						var angular_gap: float = abs(wrapf(ap_vec.angle() - pe_vec.angle(), -PI, PI))
						var opposite_error: float = abs(PI - angular_gap)
						var apsis_spatial_gap: float = pe_vec.distance_to(ap_vec)
						var projected_mean_radius: float = max(local_mean_r, 1.0)
						var apsides_too_close_together: bool = apsis_spatial_gap < projected_mean_radius * 1.20
						if opposite_error > PI * 0.18 or apsides_too_close_together:
							apsides_missing_or_collapsed = true
				if looks_near_circular and apsides_missing_or_collapsed:
					var pe_index: int = min(chunk_start + 8, chunk_end)
					var opposite_target: Vector2 = -_project_planet_frame(ship_points[pe_index])
					var ap_index: int = _find_closest_projected_index_to_point_in_range(
						ship_points,
						opposite_target,
						pe_index + 1,
						chunk_end,
					)
					predicted_periapsis_index = pe_index
					predicted_periapsis_distance = planet_radii[pe_index]
					predicted_periapsis_time = float(pe_index) * prediction_step_seconds
					if ap_index >= 0 and ap_index < ship_points.size():
						predicted_apoapsis_index = ap_index
						predicted_apoapsis_distance = planet_radii[ap_index]
						predicted_apoapsis_time = float(ap_index) * prediction_step_seconds

	var body_predictions: Dictionary = {}
	for child_i in range(child_body_infos.size()):
		var body_info: Dictionary = child_body_infos[child_i]
		var body_name: StringName = body_info.get("body_name", &"")
		body_predictions[String(body_name)] = {
			"body_name": body_name,
			"parent_body_name": body_info.get("parent_body_name", &""),
			"relative_points": child_relative_points[child_i],
			"dominance_mask": child_dominance_masks[child_i],
			"closest_approach": {
				"distance": child_best_distances[child_i],
				"time": child_best_times[child_i],
				"relative_speed": child_best_relative_speeds[child_i],
				"index": child_best_indices[child_i],
			},
		}

	var legacy_moon_prediction: Dictionary = body_predictions.get("moon", {
		"body_name": &"moon",
		"parent_body_name": &"planet",
		"relative_points": [],
		"dominance_mask": [],
		"closest_approach": {
			"distance": INF,
			"time": -1.0,
			"relative_speed": -1.0,
			"index": -1,
		},
	})
	var moon_points: Array[Vector3] = []
	for point in legacy_moon_prediction.get("relative_points", []):
		moon_points.append(point)
	var moon_dominance: Array[bool] = []
	for value in legacy_moon_prediction.get("dominance_mask", []):
		moon_dominance.append(bool(value))
	var moon_closest_approach: Dictionary = legacy_moon_prediction.get("closest_approach", {})
	var best_moon_ca: float = moon_closest_approach.get("distance", INF)
	var best_moon_tca: float = moon_closest_approach.get("time", -1.0)
	var best_moon_vrel: float = moon_closest_approach.get("relative_speed", -1.0)
	var best_moon_ca_index: int = moon_closest_approach.get("index", -1)

	return {
		"ship_points": ship_points,
		"ship_velocities": ship_velocities,
		"body_predictions": body_predictions,
		"moon_points": moon_points,
		"closest_approach_distance": closest_approach_distance,
		"closest_approach_time": closest_approach_time,
		"moon_closest_approach_distance": best_moon_ca,
		"moon_closest_approach_time": best_moon_tca,
		"moon_relative_speed_at_closest_approach": best_moon_vrel,
		"moon_closest_approach_index": best_moon_ca_index,
		"moon_dominance": moon_dominance,
		"predicted_periapsis_distance": predicted_periapsis_distance,
		"predicted_apoapsis_distance": predicted_apoapsis_distance,
		"predicted_periapsis_time": predicted_periapsis_time,
		"predicted_apoapsis_time": predicted_apoapsis_time,
		"predicted_periapsis_index": predicted_periapsis_index,
		"predicted_apoapsis_index": predicted_apoapsis_index
	}

func compute(
	ship_pos: Vector3,
	ship_vel: Vector3,
	sim_time: float,
	prediction_step_seconds: float,
	prediction_steps: int,
	extrema_window_radius: int,
	radial_extrema_tolerance: float
) -> Dictionary:
	var job: Dictionary = create_prediction_job(
		ship_pos,
		ship_vel,
		sim_time,
		prediction_step_seconds,
		prediction_steps,
		extrema_window_radius,
		radial_extrema_tolerance
	)
	step_prediction_job(job, prediction_steps)
	return build_prediction_from_job(job)
