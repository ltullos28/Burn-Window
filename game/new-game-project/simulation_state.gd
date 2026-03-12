extends Node

@export var min_gravity_distance: float = 5.0

# -----------------------------
# PLANET
# -----------------------------
@export var planet_radius: float = 400.0
@export var planet_surface_gravity: float = 0.1

# -----------------------------
# MOON
# -----------------------------
@export var moon_radius: float = 120.0
@export var moon_surface_gravity: float = 0.03
@export var moon_center_distance_from_planet: float = 5000.0
@export var moon_orbit_phase: float = 0.0

@export var celestial_time_scale: float = 1.0
@export var planet_up: Vector3 = Vector3.UP
@export var moon_up: Vector3 = Vector3.UP

# Derived values
var planet_mu: float = 0.0
var moon_mu: float = 0.0
var moon_orbit_radius: float = 0.0
var moon_orbit_speed: float = 0.0
var moon_orbit_linear_speed: float = 0.0

# Ship sim state
var ship_pos: Vector3 = Vector3.ZERO
var ship_vel: Vector3 = Vector3.ZERO

# Body sim state
var planet_pos: Vector3 = Vector3(0.0, 40.0, 700.0)
var planet_vel: Vector3 = Vector3.ZERO

var moon_pos: Vector3 = Vector3.ZERO
var moon_vel: Vector3 = Vector3.ZERO

var sim_time: float = 0.0

# Temporary Warp
var warp_levels := [1.0, 2.0, 5.0, 10.0, 20.0, 50.0, 100.0]
var warp_index := 0

func _ready() -> void:
	_recompute_body_constants()
	reset()

func _physics_process(delta: float) -> void:
	sim_time += delta * celestial_time_scale
	_update_moon_state()

func _recompute_body_constants() -> void:
	planet_mu = planet_surface_gravity * planet_radius * planet_radius
	moon_mu = moon_surface_gravity * moon_radius * moon_radius

	moon_orbit_radius = moon_center_distance_from_planet

	# Circular orbit speed around planet
	moon_orbit_speed = sqrt(planet_mu / pow(moon_orbit_radius, 3.0))
	moon_orbit_linear_speed = sqrt(planet_mu / moon_orbit_radius)

func reset() -> void:
	# Planet fixed in sim space
	planet_pos = Vector3(0.0, 40.0, 700.0)
	planet_vel = Vector3.ZERO

	# Start ship in a circular POLAR orbit around the planet
	# Position stays on +X side of planet
	# Velocity goes in +Y so the orbit plane becomes X-Y

	ship_pos = planet_pos + Vector3(900.0, 0.0, 0.0)
	ship_vel = Vector3(0.0, 2.9811626, 2.9811626)

	sim_time = 0.0
	_update_moon_state()

func _update_moon_state() -> void:
	var angle: float = moon_orbit_phase + sim_time * moon_orbit_speed

	var local_offset := Vector3(
		cos(angle) * moon_orbit_radius,
		0.0,
		sin(angle) * moon_orbit_radius
	)

	moon_pos = planet_pos + local_offset

	var tangent := Vector3(
		-sin(angle),
		0.0,
		cos(angle)
	) * moon_orbit_linear_speed

	moon_vel = tangent

func gravity_accel_at(position: Vector3) -> Vector3:
	var total := Vector3.ZERO
	total += _gravity_from_body(position, planet_pos, planet_mu)
	total += _gravity_from_body(position, moon_pos, moon_mu)
	return total

func _gravity_from_body(position: Vector3, body_pos: Vector3, mu: float) -> Vector3:
	var offset: Vector3 = body_pos - position
	var distance: float = offset.length()

	if distance < min_gravity_distance:
		distance = min_gravity_distance

	return offset * mu / pow(distance, 3.0)
func increase_warp():
	warp_index = min(warp_index + 1, warp_levels.size() - 1)
	celestial_time_scale = warp_levels[warp_index]
	print("Time Warp:", celestial_time_scale, "x")

func decrease_warp():
	warp_index = max(warp_index - 1, 0)
	celestial_time_scale = warp_levels[warp_index]
	print("Time Warp:", celestial_time_scale, "x")
