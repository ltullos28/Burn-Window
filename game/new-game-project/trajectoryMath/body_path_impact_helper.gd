class_name BodyPathImpactHelper
extends RefCounted

func trim_path(points: Array[Vector3], body_radius: float, source_indices: Array[int] = []) -> Dictionary:
	var trimmed_points: Array[Vector3] = []
	var trimmed_source_indices: Array[int] = []
	var result: Dictionary = {
		"points": trimmed_points,
		"source_indices": trimmed_source_indices,
		"impact_found": false,
		"impact_index": -1,
		"impact_source_index": -1,
	}

	if points.is_empty() or body_radius <= 0.0:
		return result

	var indices: Array[int] = source_indices
	if indices.is_empty():
		for i in range(points.size()):
			indices.append(i)

	var first_point: Vector3 = points[0]
	var first_radius: float = first_point.length()
	if first_radius <= body_radius:
		var first_impact_point: Vector3 = _project_point_to_surface(first_point, body_radius)
		trimmed_points.append(first_impact_point)
		trimmed_source_indices.append(indices[0] if not indices.is_empty() else 0)
		result["impact_found"] = true
		result["impact_index"] = 0
		result["impact_source_index"] = trimmed_source_indices[0]
		return result

	trimmed_points.append(first_point)
	trimmed_source_indices.append(indices[0])

	for i in range(points.size() - 1):
		var start_point: Vector3 = points[i]
		var end_point: Vector3 = points[i + 1]
		var impact_t: float = _find_surface_intersection_fraction(start_point, end_point, body_radius)
		if impact_t < 0.0:
			trimmed_points.append(end_point)
			trimmed_source_indices.append(indices[min(i + 1, indices.size() - 1)])
			continue

		var impact_point: Vector3 = _find_surface_intersection(start_point, end_point, body_radius, impact_t)
		trimmed_points.append(impact_point)
		var impact_source_index: int = indices[min(i + 1, indices.size() - 1)]
		trimmed_source_indices.append(impact_source_index)
		result["impact_found"] = true
		result["impact_index"] = trimmed_points.size() - 1
		result["impact_source_index"] = impact_source_index
		return result

	return result

func _find_surface_intersection(start_point: Vector3, end_point: Vector3, body_radius: float, impact_t: float) -> Vector3:
	var midpoint: Vector3 = start_point.lerp(end_point, clampf(impact_t, 0.0, 1.0))
	return _project_point_to_surface(midpoint, body_radius)

func _find_surface_intersection_fraction(start_point: Vector3, end_point: Vector3, body_radius: float) -> float:
	var delta: Vector3 = end_point - start_point
	var a: float = delta.dot(delta)
	if a <= 0.0000001:
		return 0.0 if start_point.length() <= body_radius else -1.0

	var b: float = 2.0 * start_point.dot(delta)
	var c: float = start_point.dot(start_point) - body_radius * body_radius
	var discriminant: float = b * b - 4.0 * a * c
	if discriminant < 0.0:
		return -1.0

	var sqrt_discriminant: float = sqrt(max(discriminant, 0.0))
	var t0: float = (-b - sqrt_discriminant) / (2.0 * a)
	var t1: float = (-b + sqrt_discriminant) / (2.0 * a)
	var best_t: float = INF
	for candidate_t in [t0, t1]:
		if candidate_t >= 0.0 and candidate_t <= 1.0:
			best_t = min(best_t, candidate_t)

	return best_t if best_t != INF else -1.0

func _project_point_to_surface(point: Vector3, body_radius: float) -> Vector3:
	if point.length_squared() <= 0.0000001:
		return Vector3(body_radius, 0.0, 0.0)
	return point.normalized() * body_radius
