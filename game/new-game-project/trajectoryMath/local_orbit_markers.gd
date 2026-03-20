class_name LocalOrbitMarkers
extends RefCounted

func analyze(
	ship_points: Array[Vector3],
	body_points: Array[Vector3],
	dominance: Array[bool],
	closest_approach_index: int,
	visible_count: int,
	extrema_window_radius: int,
	closure_distance_ratio_tolerance: float,
	closure_scan_chunk_steps: int,
	closure_min_threshold_step_multiplier: float
) -> Dictionary:
	var entry_index: int = _find_first_true_index(dominance, visible_count)
	var exit_index: int = -1
	if entry_index >= 0:
		exit_index = _find_first_false_index(dominance, entry_index + 1, visible_count)

	var local_points: Array[Vector3] = []
	var local_source_indices: Array[int] = []
	var local_ca_index: int = -1
	var local_pe_index: int = -1
	var local_ap_index: int = -1
	var show_local_ca_marker: bool = false
	var show_escape_marker: bool = false
	var escape_marker_local_index: int = -1
	var state: String = "NONE"

	if entry_index >= 0:
		var segment_end: int = visible_count
		if exit_index >= 0:
			segment_end = exit_index + 1

		var local_radii: Array[float] = []
		for i in range(entry_index, segment_end):
			if i >= dominance.size():
				break
			if not dominance[i]:
				break
			if i >= ship_points.size() or i >= body_points.size():
				break

			var rel_to_body: Vector3 = ship_points[i] - body_points[i]
			local_points.append(rel_to_body)
			local_source_indices.append(i)
			local_radii.append(rel_to_body.length())

			if i == closest_approach_index:
				local_ca_index = local_points.size() - 1

		var smoothing_half_window: int = clampi(int(extrema_window_radius / 2) + 1, 2, 4)
		var smoothed_radii: Array[float] = _build_smoothed_radii(local_radii, smoothing_half_window)
		var angular_sweep: float = _compute_projected_angular_sweep(local_points)
		var closure_index: int = _find_continuity_closure_index(
			local_points,
			closure_distance_ratio_tolerance,
			closure_scan_chunk_steps,
			closure_min_threshold_step_multiplier
		)
		var has_closure_evidence: bool = exit_index < 0 and closure_index > 6
		var has_mature_local_loop: bool = (
			(local_points.size() >= 18 and angular_sweep >= PI * 1.60) or
			(local_points.size() >= 12 and angular_sweep >= PI * 1.00 and has_closure_evidence)
		)
		var probable_escape_without_exit: bool = false

		local_pe_index = _find_first_local_minimum_index(smoothed_radii, 1)
		if local_pe_index >= 0:
			local_pe_index = _refine_extremum_to_local_best(local_radii, local_pe_index, 4, false)

		if local_pe_index >= 0:
			local_ap_index = _find_first_local_maximum_index(smoothed_radii, local_pe_index + 1)
			if local_ap_index >= 0:
				local_ap_index = _refine_extremum_to_local_best(local_radii, local_ap_index, 4, true)

		if has_closure_evidence and closure_index > 3:
			var loop_length: int = closure_index + 1
			if local_pe_index < 0:
				local_pe_index = _find_global_extremum_index(local_radii, loop_length, false)
			if local_ap_index < 0:
				local_ap_index = _find_global_extremum_index(local_radii, loop_length, true)

		var ap_collapsed: bool = _is_local_ap_collapsed(local_points, local_pe_index, local_ap_index)
		if ap_collapsed:
			local_ap_index = -1

		if local_pe_index >= 0 and local_points.size() > 6:
			var local_min_r: float = INF
			var local_max_r: float = -INF
			var local_mean_r: float = 0.0
			for radius in local_radii:
				local_min_r = min(local_min_r, radius)
				local_max_r = max(local_max_r, radius)
				local_mean_r += radius
			if not local_radii.is_empty():
				local_mean_r /= float(local_radii.size())

			var local_spread_ratio: float = 0.0
			if local_mean_r > 0.0001:
				local_spread_ratio = (local_max_r - local_min_r) / local_mean_r

			var looks_near_circular: bool = local_spread_ratio < 0.06
			var ap_not_opposite_enough: bool = false
			if local_ap_index >= 0:
				var pe_vec: Vector2 = _project_local_point(local_points[local_pe_index])
				var ap_vec: Vector2 = _project_local_point(local_points[local_ap_index])
				if pe_vec.length_squared() > 0.0001 and ap_vec.length_squared() > 0.0001:
					var angular_gap: float = abs(wrapf(ap_vec.angle() - pe_vec.angle(), -PI, PI))
					var opposite_error: float = abs(PI - angular_gap)
					if opposite_error > PI * 0.08:
						ap_not_opposite_enough = true

			if has_mature_local_loop and (local_ap_index < 0 or ap_collapsed or ap_not_opposite_enough or looks_near_circular):
				if closure_index > 3:
					var loop_length: int = closure_index + 1
					var pe_vec: Vector2 = _project_local_point(local_points[local_pe_index])
					var opposite_target: Vector2 = -pe_vec
					var exclusion_radius: int = max(2, int(round(float(loop_length) * 0.15)))
					var best_index: int = -1
					var best_dist_sq: float = INF

					for i in range(loop_length):
						var wrapped_delta: int = mini(
							absi(i - local_pe_index),
							loop_length - absi(i - local_pe_index)
						)
						if wrapped_delta <= exclusion_radius:
							continue

						var point_proj: Vector2 = _project_local_point(local_points[i])
						var dist_sq: float = point_proj.distance_squared_to(opposite_target)
						if dist_sq < best_dist_sq:
							best_dist_sq = dist_sq
							best_index = i

					if best_index >= 0 and best_index != local_pe_index:
						local_ap_index = best_index

			if has_closure_evidence and local_pe_index >= 0 and local_ap_index < 0:
				local_ap_index = _find_opposite_side_index(local_points, local_pe_index, closure_index + 1)

		var has_established_orbit_markers: bool = has_mature_local_loop and local_pe_index >= 0 and local_ap_index >= 0
		if not has_established_orbit_markers:
			local_pe_index = -1
			local_ap_index = -1

		if _is_local_ap_collapsed(local_points, local_pe_index, local_ap_index):
			local_ap_index = -1

		var has_orbit_markers: bool = local_pe_index >= 0 and local_ap_index >= 0
		show_local_ca_marker = local_ca_index >= 0 and not has_orbit_markers

		if not has_orbit_markers and exit_index < 0:
			probable_escape_without_exit = _looks_like_escape_transition(local_radii, local_ca_index)

		if not has_orbit_markers and (exit_index >= 0 or probable_escape_without_exit):
			show_escape_marker = true
			escape_marker_local_index = max(0, local_points.size() - 1)

		if has_orbit_markers:
			state = "LOCAL_ORBIT"
		elif show_escape_marker:
			state = "ESCAPE_TRANSITION"
		elif show_local_ca_marker:
			state = "CAPTURE_TRANSITION"

	return {
		"entry_index": entry_index,
		"exit_index": exit_index,
		"local_points": local_points,
		"local_source_indices": local_source_indices,
		"local_ca_index": local_ca_index,
		"local_pe_index": local_pe_index,
		"local_ap_index": local_ap_index,
		"show_local_ca_marker": show_local_ca_marker,
		"show_escape_marker": show_escape_marker,
		"escape_marker_local_index": escape_marker_local_index,
		"state": state,
	}

func _find_first_true_index(values: Array[bool], max_count: int) -> int:
	var limit: int = min(values.size(), max_count)
	for i in range(limit):
		if values[i]:
			return i
	return -1

func _find_first_false_index(values: Array[bool], start_index: int, max_count: int) -> int:
	var limit: int = min(values.size(), max_count)
	var start_i: int = max(start_index, 0)
	for i in range(start_i, limit):
		if not values[i]:
			return i
	return -1

func _find_first_local_minimum_index(values: Array[float], start_index: int) -> int:
	if values.size() < 3:
		return -1

	var start_i: int = max(1, start_index)
	var end_i: int = values.size() - 2
	for i in range(start_i, end_i + 1):
		if values[i] <= values[i - 1] and values[i] <= values[i + 1]:
			if values[i] < values[i - 1] or values[i] < values[i + 1]:
				return i
	return -1

func _find_first_local_maximum_index(values: Array[float], start_index: int) -> int:
	if values.size() < 3:
		return -1

	var start_i: int = max(1, start_index)
	var end_i: int = values.size() - 2
	for i in range(start_i, end_i + 1):
		if values[i] >= values[i - 1] and values[i] >= values[i + 1]:
			if values[i] > values[i - 1] or values[i] > values[i + 1]:
				return i
	return -1

func _refine_extremum_to_local_best(
	values: Array[float],
	center_index: int,
	search_radius: int,
	find_maximum: bool
) -> int:
	if values.is_empty():
		return center_index

	var start_i: int = max(0, center_index - search_radius)
	var end_i: int = min(values.size() - 1, center_index + search_radius)
	var best_index: int = center_index
	var best_value: float = values[center_index]

	for i in range(start_i, end_i + 1):
		if find_maximum:
			if values[i] > best_value:
				best_value = values[i]
				best_index = i
		else:
			if values[i] < best_value:
				best_value = values[i]
				best_index = i

	return best_index

func _find_global_extremum_index(values: Array[float], count: int, find_maximum: bool) -> int:
	if values.is_empty() or count <= 0:
		return -1

	var limit: int = min(count, values.size())
	var best_index: int = 0
	var best_value: float = values[0]
	for i in range(1, limit):
		if find_maximum:
			if values[i] > best_value:
				best_value = values[i]
				best_index = i
		else:
			if values[i] < best_value:
				best_value = values[i]
				best_index = i
	return best_index

func _find_opposite_side_index(local_points: Array[Vector3], anchor_index: int, count: int) -> int:
	if local_points.is_empty() or anchor_index < 0 or anchor_index >= local_points.size():
		return -1

	var limit: int = min(count, local_points.size())
	var anchor_vec: Vector2 = _project_local_point(local_points[anchor_index])
	if anchor_vec.length_squared() <= 0.0001:
		return -1

	var opposite_target: Vector2 = -anchor_vec
	var exclusion_radius: int = max(2, int(round(float(limit) * 0.15)))
	var best_index: int = -1
	var best_dist_sq: float = INF

	for i in range(limit):
		var wrapped_delta: int = mini(
			absi(i - anchor_index),
			limit - absi(i - anchor_index)
		)
		if wrapped_delta <= exclusion_radius:
			continue

		var point_proj: Vector2 = _project_local_point(local_points[i])
		var dist_sq: float = point_proj.distance_squared_to(opposite_target)
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best_index = i

	return best_index

func _looks_like_escape_transition(local_radii: Array[float], local_ca_index: int) -> bool:
	if local_radii.size() < 6 or local_ca_index < 0 or local_ca_index >= local_radii.size() - 3:
		return false

	var ca_radius: float = local_radii[local_ca_index]
	var end_radius: float = local_radii[local_radii.size() - 1]
	if end_radius <= ca_radius * 1.06:
		return false

	var positive_steps: int = 0
	var total_steps: int = 0
	var start_i: int = max(local_ca_index, 0)
	for i in range(start_i + 1, local_radii.size()):
		total_steps += 1
		if local_radii[i] > local_radii[i - 1]:
			positive_steps += 1

	if total_steps <= 0:
		return false

	return positive_steps >= max(3, int(ceil(float(total_steps) * 0.65)))

func _build_smoothed_radii(values: Array[float], half_window: int) -> Array[float]:
	var smoothed: Array[float] = []
	if values.is_empty():
		return smoothed

	var use_half_window: int = max(1, half_window)
	for i in range(values.size()):
		var start_i: int = max(0, i - use_half_window)
		var end_i: int = min(values.size() - 1, i + use_half_window)
		var sum: float = 0.0
		var count: int = 0
		for j in range(start_i, end_i + 1):
			sum += values[j]
			count += 1
		smoothed.append(sum / float(count))

	return smoothed

func _is_local_ap_collapsed(local_points: Array[Vector3], pe_index: int, ap_index: int) -> bool:
	if pe_index < 0 or ap_index < 0:
		return false
	if pe_index == ap_index:
		return true
	if pe_index >= local_points.size() or ap_index >= local_points.size():
		return true

	var pe_vec: Vector2 = _project_local_point(local_points[pe_index])
	var ap_vec: Vector2 = _project_local_point(local_points[ap_index])
	if pe_vec.length_squared() <= 0.0001 or ap_vec.length_squared() <= 0.0001:
		return true

	var angular_gap: float = abs(wrapf(ap_vec.angle() - pe_vec.angle(), -PI, PI))
	if angular_gap < PI * 0.20:
		return true

	var mean_radius: float = 0.0
	for point in local_points:
		mean_radius += _project_local_point(point).length()
	if not local_points.is_empty():
		mean_radius /= float(local_points.size())

	var spatial_gap: float = pe_vec.distance_to(ap_vec)
	return spatial_gap < max(1.0, mean_radius * 0.12)

func _find_continuity_closure_index(
	relative_points: Array[Vector3],
	closure_distance_ratio_tolerance: float,
	closure_scan_chunk_steps: int,
	closure_min_threshold_step_multiplier: float
) -> int:
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
		radius_scale * closure_distance_ratio_tolerance,
		mean_step_distance * closure_min_threshold_step_multiplier
	)
	var chunk_size: int = max(4, closure_scan_chunk_steps)
	var left_start_zone: bool = false

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
			if point_distance <= closure_threshold and point_distance < best_distance:
				best_distance = point_distance
				best_index = i

		if best_index >= 0:
			return best_index

	return -1

func _project_local_point(point: Vector3) -> Vector2:
	return Vector2(point.x, -point.z)

func _compute_projected_angular_sweep(local_points: Array[Vector3]) -> float:
	if local_points.size() <= 1:
		return 0.0

	var cumulative_angle: float = 0.0
	var prev_angle: float = _project_local_point(local_points[0]).angle()

	for i in range(1, local_points.size()):
		var prev_proj: Vector2 = _project_local_point(local_points[i - 1])
		var curr_proj: Vector2 = _project_local_point(local_points[i])
		if prev_proj.length_squared() < 0.0001 or curr_proj.length_squared() < 0.0001:
			continue

		var angle_i: float = curr_proj.angle()
		var dtheta: float = abs(wrapf(angle_i - prev_angle, -PI, PI))
		cumulative_angle += dtheta
		prev_angle = angle_i

	return cumulative_angle
