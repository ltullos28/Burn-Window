class_name TrajectorySolution
extends RefCounted

var ship_points: Array[Vector2] = []
var moon_points: Array[Vector2] = []

var closest_approach_distance: float = -1.0
var closest_approach_time: float = -1.0

var orbit_classification: String = "UNRESOLVED"
var periapsis_distance: float = -1.0
var apoapsis_distance: float = -1.0
var eccentricity_value: float = -1.0
var semi_major_axis_value: float = -1.0
var orbital_period_value: float = -1.0

var periapsis_marker_world: Vector2 = Vector2.ZERO
var apoapsis_marker_world: Vector2 = Vector2.ZERO
var has_periapsis_marker: bool = false
var has_apoapsis_marker: bool = false

var moon_closest_approach_distance: float = -1.0
var moon_closest_approach_time: float = -1.0
var moon_relative_speed_at_closest_approach: float = -1.0
