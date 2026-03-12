class_name TrajectorySolution
extends RefCounted

var ship_points: Array[Vector3] = []
var moon_points: Array[Vector3] = []

var closest_approach_distance: float = -1.0
var closest_approach_time: float = -1.0

var orbit_classification: String = "UNRESOLVED"
var periapsis_distance: float = -1.0
var apoapsis_distance: float = -1.0
var eccentricity_value: float = -1.0
var semi_major_axis_value: float = -1.0
var orbital_period_value: float = -1.0

var moon_closest_approach_distance: float = -1.0
var moon_closest_approach_time: float = -1.0
var moon_relative_speed_at_closest_approach: float = -1.0
var moon_closest_approach_index: int = -1
var moon_dominance: Array[bool] = []

var is_bound_orbit: bool = false
var specific_energy: float = 0.0

var predicted_periapsis_distance: float = -1.0
var predicted_apoapsis_distance: float = -1.0
var predicted_periapsis_time: float = -1.0
var predicted_apoapsis_time: float = -1.0
var predicted_periapsis_index: int = -1
var predicted_apoapsis_index: int = -1

var prediction_steps_used: int = 0
var prediction_duration_used: float = 0.0
