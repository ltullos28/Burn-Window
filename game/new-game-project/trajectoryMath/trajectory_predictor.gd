class_name TrajectoryPredictor
extends RefCounted

func _gravity_from_body(position: Vector3, body_pos: Vector3, mu: float, min_gravity_distance: float) -> Vector3:
	var offset: Vector3 = body_pos - position
	var distance: float = max(offset.length(), min_gravity_distance)
	return offset * mu / pow(distance, 3.0)

func _gravity_accel(position: Vector3, moon_pos: Vector3) -> Vector3:
	var accel: Vector3 = Vector3.ZERO
	accel += _gravity_from_body(position, SimulationState.planet_pos, SimulationState.planet_mu, SimulationState.min_gravity_distance)
	accel += _gravity_from_body(position, moon_pos, SimulationState.moon_mu, SimulationState.min_gravity_distance)
	return accel

func _moon_state_at_time(sim_time: float) -> Dictionary:
	var moon_angle: float = SimulationState.moon_orbit_phase + sim_time * SimulationState.moon_orbit_speed

	var moon_pos: Vector3 = SimulationState.planet_pos + Vector3(
		cos(moon_angle) * SimulationState.moon_orbit_radius,
		0.0,
		sin(moon_angle) * SimulationState.moon_orbit_radius
	)

	var moon_vel: Vector3 = Vector3(
		-sin(moon_angle),
		0.0,
		cos(moon_angle)
	) * SimulationState.moon_orbit_linear_speed

	return {
		"pos": moon_pos,
		"vel": moon_vel
	}

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

func compute(
	ship_pos: Vector3,
	ship_vel: Vector3,
	sim_time: float,
	prediction_step_seconds: float,
	prediction_steps: int,
	_extrema_window_radius: int,
	_radial_extrema_tolerance: float
) -> Dictionary:
	var ship_points: Array[Vector3] = []
	var moon_points: Array[Vector3] = []
	var planet_radii: Array[float] = []
	var moon_dominance: Array[bool] = []

	var test_pos: Vector3 = ship_pos
	var test_vel: Vector3 = ship_vel
	var test_time: float = sim_time

	var initial_rel_ship_planet: Vector3 = test_pos - SimulationState.planet_pos
	var closest_approach_distance: float = initial_rel_ship_planet.length()
	var closest_approach_time: float = 0.0

	var best_moon_ca: float = INF
	var best_moon_tca: float = -1.0
	var best_moon_vrel: float = -1.0
	var best_moon_ca_index: int = -1

	for i in range(prediction_steps):
		var moon_state: Dictionary = _moon_state_at_time(test_time)
		var predicted_moon_pos: Vector3 = moon_state["pos"]
		var predicted_moon_vel: Vector3 = moon_state["vel"]

		var rel_ship_planet: Vector3 = test_pos - SimulationState.planet_pos
		var rel_moon_planet: Vector3 = predicted_moon_pos - SimulationState.planet_pos

		ship_points.append(rel_ship_planet)
		moon_points.append(rel_moon_planet)

		var report_t: float = float(i) * prediction_step_seconds
		var true_radius: float = rel_ship_planet.length()
		planet_radii.append(true_radius)

		if true_radius < closest_approach_distance:
			closest_approach_distance = true_radius
			closest_approach_time = report_t

		var d_moon: float = (test_pos - predicted_moon_pos).length()
		if d_moon < best_moon_ca:
			best_moon_ca = d_moon
			best_moon_tca = report_t
			best_moon_vrel = (test_vel - predicted_moon_vel).length()
			best_moon_ca_index = i

		var d_planet_3d: float = rel_ship_planet.length()

		var g_planet: float = 0.0
		if d_planet_3d > 0.0001:
			g_planet = SimulationState.planet_mu / (d_planet_3d * d_planet_3d)

		var g_moon: float = 0.0
		if d_moon > 0.0001:
			g_moon = SimulationState.moon_mu / (d_moon * d_moon)

		moon_dominance.append(g_moon > g_planet)

		var accel: Vector3 = _gravity_accel(test_pos, predicted_moon_pos)
		test_vel += accel * prediction_step_seconds
		test_pos += test_vel * prediction_step_seconds
		test_time += prediction_step_seconds * SimulationState.celestial_time_scale

	var predicted_periapsis_distance: float = -1.0
	var predicted_apoapsis_distance: float = -1.0
	var predicted_periapsis_time: float = -1.0
	var predicted_apoapsis_time: float = -1.0
	var predicted_periapsis_index: int = -1
	var predicted_apoapsis_index: int = -1

	if planet_radii.size() >= 3:
		var smoothing_half_window: int = clampi(int(_extrema_window_radius / 2) + 1, 2, 4)
		var smoothed_radii: Array[float] = _build_smoothed_radii(planet_radii, smoothing_half_window)

		var next_pe_index: int = _find_first_local_minimum_index(smoothed_radii, 1)
		var next_ap_index: int = _find_first_local_maximum_index(smoothed_radii, 1)

		if next_pe_index >= 0 and next_pe_index < ship_points.size():
			next_pe_index = _refine_extremum_to_local_best(
				planet_radii,
				next_pe_index,
				4,
				false
			)

			predicted_periapsis_index = next_pe_index
			predicted_periapsis_distance = planet_radii[next_pe_index]
			predicted_periapsis_time = float(next_pe_index) * prediction_step_seconds

		if next_ap_index >= 0 and next_ap_index < ship_points.size():
			next_ap_index = _refine_extremum_to_local_best(
				planet_radii,
				next_ap_index,
				4,
				true
			)

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

					var angular_gap: float = abs(wrapf(ap_vec.angle() - pe_vec.angle(), -PI, PI))
					var opposite_error: float = abs(PI - angular_gap)

					if opposite_error > PI * 0.30:
						apsides_missing_or_collapsed = true

				if looks_near_circular and apsides_missing_or_collapsed:
					var pe_index: int = min(chunk_start + 8, chunk_end)

					var opposite_target: Vector2 = -_project_planet_frame(ship_points[pe_index])
					var ap_index: int = _find_closest_projected_index_to_point_in_range(
						ship_points,
						opposite_target,
						pe_index + 1,
						chunk_end
					)

					predicted_periapsis_index = pe_index
					predicted_periapsis_distance = planet_radii[pe_index]
					predicted_periapsis_time = float(pe_index) * prediction_step_seconds

					if ap_index >= 0 and ap_index < ship_points.size():
						predicted_apoapsis_index = ap_index
						predicted_apoapsis_distance = planet_radii[ap_index]
						predicted_apoapsis_time = float(ap_index) * prediction_step_seconds

	return {
		"ship_points": ship_points,
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
