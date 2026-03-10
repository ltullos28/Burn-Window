class_name TrajectoryPredictor
extends RefCounted

func _gravity_from_body(position: Vector3, body_pos: Vector3, mu: float, min_gravity_distance: float) -> Vector3:
	var offset: Vector3 = body_pos - position
	var distance: float = offset.length()

	if distance < min_gravity_distance:
		distance = min_gravity_distance

	return offset * mu / pow(distance, 3.0)

func compute(
	ship_pos: Vector3,
	ship_vel: Vector3,
	sim_time: float,
	prediction_step_seconds: float,
	prediction_steps: int
) -> Dictionary:
	var ship_points: Array[Vector2] = []
	var moon_points: Array[Vector2] = []

	var test_pos: Vector3 = ship_pos
	var test_vel: Vector3 = ship_vel
	var test_time: float = sim_time

	var closest_approach_distance: float = (test_pos - SimulationState.planet_pos).length()
	var closest_approach_time: float = 0.0

	var best_moon_ca := INF
	var best_moon_tca := -1.0
	var best_moon_vrel := -1.0

	for i in range(prediction_steps):
		var moon_angle: float = SimulationState.moon_orbit_phase + test_time * SimulationState.moon_orbit_speed
		var predicted_moon_pos := SimulationState.planet_pos + Vector3(
			cos(moon_angle) * SimulationState.moon_orbit_radius,
			0.0,
			sin(moon_angle) * SimulationState.moon_orbit_radius
		)

		var predicted_moon_vel := Vector3(
			-sin(moon_angle),
			0.0,
			cos(moon_angle)
		) * SimulationState.moon_orbit_linear_speed

		var rel_ship_planet: Vector3 = test_pos - SimulationState.planet_pos
		var rel_moon_planet: Vector3 = predicted_moon_pos - SimulationState.planet_pos

		ship_points.append(Vector2(rel_ship_planet.x, -rel_ship_planet.z))
		moon_points.append(Vector2(rel_moon_planet.x, -rel_moon_planet.z))

		var d_planet: float = rel_ship_planet.length()
		if d_planet < closest_approach_distance:
			closest_approach_distance = d_planet
			closest_approach_time = float(i) * prediction_step_seconds

		var d_moon: float = (test_pos - predicted_moon_pos).length()
		if d_moon < best_moon_ca:
			best_moon_ca = d_moon
			best_moon_tca = float(i) * prediction_step_seconds
			best_moon_vrel = (test_vel - predicted_moon_vel).length()

		var accel := Vector3.ZERO
		accel += _gravity_from_body(test_pos, SimulationState.planet_pos, SimulationState.planet_mu, SimulationState.min_gravity_distance)
		accel += _gravity_from_body(test_pos, predicted_moon_pos, SimulationState.moon_mu, SimulationState.min_gravity_distance)

		test_vel += accel * prediction_step_seconds
		test_pos += test_vel * prediction_step_seconds
		test_time += prediction_step_seconds * SimulationState.celestial_time_scale

	return {
		"ship_points": ship_points,
		"moon_points": moon_points,
		"closest_approach_distance": closest_approach_distance,
		"closest_approach_time": closest_approach_time,
		"moon_closest_approach_distance": best_moon_ca,
		"moon_closest_approach_time": best_moon_tca,
		"moon_relative_speed_at_closest_approach": best_moon_vrel
	}
