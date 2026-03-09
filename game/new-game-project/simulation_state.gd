extends Node

@export var planet_mu: float = 8000.0
@export var min_gravity_distance: float = 5.0

var ship_pos: Vector3 = Vector3.ZERO
var ship_vel: Vector3 = Vector3.ZERO

# Start the planet somewhere "far away" in simulation space.
# These are SIMULATION coordinates, not render coordinates.
var planet_pos: Vector3 = Vector3(0.0, 40.0, 700.0)
var planet_vel: Vector3 = Vector3.ZERO

func reset() -> void:
	ship_pos = Vector3.ZERO
	ship_vel = Vector3.ZERO
	planet_pos = Vector3(0.0, 40.0, 700.0)
	planet_vel = Vector3.ZERO

func gravity_accel_at(position: Vector3) -> Vector3:
	var to_planet: Vector3 = planet_pos - position
	var distance: float = to_planet.length()

	if distance < min_gravity_distance:
		distance = min_gravity_distance

	var direction: Vector3 = to_planet.normalized()
	var accel_mag: float = planet_mu / (distance * distance)

	return direction * accel_mag
