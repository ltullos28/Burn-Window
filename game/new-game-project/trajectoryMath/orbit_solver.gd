class_name OrbitSolver
extends RefCounted

func solve_planet_orbit(ship_pos: Vector3, ship_vel: Vector3, planet_pos: Vector3, planet_mu: float, planet_radius: float) -> Dictionary:
	var result := {
		"orbit_classification": "UNRESOLVED",
		"periapsis_distance": -1.0,
		"apoapsis_distance": -1.0,
		"eccentricity_value": -1.0,
		"semi_major_axis_value": -1.0,
		"orbital_period_value": -1.0,
		"periapsis_marker_world": Vector2.ZERO,
		"apoapsis_marker_world": Vector2.ZERO,
		"has_periapsis_marker": false,
		"has_apoapsis_marker": false,
		"is_bound_orbit": false,
		"specific_energy": 0.0
	}

	var rel: Vector3 = ship_pos - planet_pos
	var vel: Vector3 = ship_vel

	var r: float = rel.length()
	var v2: float = vel.length_squared()
	var mu: float = planet_mu

	if r <= 0.0001 or mu <= 0.0001:
		return result

	var specific_energy: float = 0.5 * v2 - mu / r
	result["specific_energy"] = specific_energy

	var h: Vector3 = rel.cross(vel)
	var e_vec: Vector3 = vel.cross(h) / mu - rel.normalized()
	var e: float = e_vec.length()

	result["eccentricity_value"] = e

	if specific_energy < 0.0:
		result["is_bound_orbit"] = true

		var a: float = -mu / (2.0 * specific_energy)
		result["semi_major_axis_value"] = a

		var pe: float = a * (1.0 - e)
		var ap: float = a * (1.0 + e)

		result["periapsis_distance"] = pe
		result["apoapsis_distance"] = ap

		if a > 0.0:
			result["orbital_period_value"] = TAU * sqrt(pow(a, 3.0) / mu)

		if e_vec.length() > 0.0001:
			var peri_dir := Vector2(e_vec.x, -e_vec.z).normalized()
			result["periapsis_marker_world"] = peri_dir * pe
			result["has_periapsis_marker"] = true

			if e < 1.0:
				result["apoapsis_marker_world"] = -peri_dir * ap
				result["has_apoapsis_marker"] = true

		if pe <= planet_radius:
			result["orbit_classification"] = "IMPACT"
		elif e < 1.0:
			if abs(ap - pe) < 0.5:
				result["orbit_classification"] = "CIRCULAR"
			else:
				result["orbit_classification"] = "ORBIT"
		else:
			result["orbit_classification"] = "UNRESOLVED"
	else:
		result["periapsis_distance"] = -1.0
		result["apoapsis_distance"] = -1.0
		result["semi_major_axis_value"] = -1.0
		result["orbital_period_value"] = -1.0
		result["is_bound_orbit"] = false
		result["orbit_classification"] = "ESCAPE"

	return result
