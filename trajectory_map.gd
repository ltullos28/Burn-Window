extends Control

enum CenterMode {
	PLANET,
	MOON,
	SHIP
}

@export var ship_path: NodePath

@export var pixels_per_unit: float = 0.010
@export var min_pixels_per_unit: float = 0.002
@export var max_pixels_per_unit: float = 0.12
@export var zoom_step: float = 0.0025

@export var prediction_step_seconds: float = 1.0
@export var prediction_steps: int = 600
@export var reveal_duration: float = 8

@export var center_mode: CenterMode = CenterMode.PLANET

@export var ghost_dash_length: int = 10
@export var ghost_gap_length: int = 6
@export var ship_mode_ghost_trail_steps: int = 220

var ship: Node3D
var predicted_ship_points: Array[Vector2] = []
var predicted_moon_points: Array[Vector2] = []

var is_revealing: bool = false
var reveal_elapsed: float = 0.0

var closest_approach_distance: float = 0.0
var closest_approach_time: float = 0.0

var orbit_classification: String = "UNRESOLVED"
var periapsis_distance: float = -1.0
var apoapsis_distance: float = -1.0

func _ready() -> void:
	ship = get_node_or_null(ship_path) as Node3D
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	request_refresh()

func _process(delta: float) -> void:
	if is_revealing:
		reveal_elapsed += delta
		if reveal_elapsed >= reveal_duration:
			reveal_elapsed = reveal_duration
			is_revealing = false

	queue_redraw()

func request_refresh() -> void:
	_compute_prediction()
	_compute_orbit_solution()
	reveal_elapsed = 0.0
	is_revealing = true

func zoom_in() -> void:
	pixels_per_unit = clampf(pixels_per_unit + zoom_step, min_pixels_per_unit, max_pixels_per_unit)

func zoom_out() -> void:
	pixels_per_unit = clampf(pixels_per_unit - zoom_step, min_pixels_per_unit, max_pixels_per_unit)

func set_center_planet() -> void:
	center_mode = CenterMode.PLANET

func set_center_moon() -> void:
	center_mode = CenterMode.MOON

func set_center_ship() -> void:
	center_mode = CenterMode.SHIP

func cycle_center_mode() -> void:
	center_mode = (center_mode + 1) % 3

func get_center_mode_text() -> String:
	match center_mode:
		CenterMode.PLANET:
			return "PLANET"
		CenterMode.MOON:
			return "MOON"
		CenterMode.SHIP:
			return "SHIP"
	return "UNKNOWN"

func get_status_text() -> String:
	if predicted_ship_points.is_empty():
		return "NO SOLUTION"
	if is_revealing:
		return "COMPUTING..."
	return "TRAJECTORY READY"

func get_closest_approach_distance() -> float:
	return closest_approach_distance

func get_closest_approach_time() -> float:
	return closest_approach_time

func get_classification() -> String:
	return orbit_classification

func get_periapsis() -> float:
	return periapsis_distance

func get_apoapsis() -> float:
	return apoapsis_distance

func get_zoom_value() -> float:
	return pixels_per_unit

func get_reveal_duration() -> float:
	return reveal_duration

func _compute_prediction() -> void:
	predicted_ship_points.clear()
	predicted_moon_points.clear()

	var test_pos: Vector3 = SimulationState.ship_pos
	var test_vel: Vector3 = SimulationState.ship_vel
	var test_time: float = SimulationState.sim_time

	var start_rel_planet: Vector3 = test_pos - SimulationState.planet_pos
	closest_approach_distance = start_rel_planet.length()
	closest_approach_time = 0.0

	for i in range(prediction_steps):
		var moon_angle: float = SimulationState.moon_orbit_phase + test_time * SimulationState.moon_orbit_speed
		var predicted_moon_pos := SimulationState.planet_pos + Vector3(
			cos(moon_angle) * SimulationState.moon_orbit_radius,
			0.0,
			sin(moon_angle) * SimulationState.moon_orbit_radius
		)

		# Always store everything in planet-centered coordinates
		var rel_ship_planet: Vector3 = test_pos - SimulationState.planet_pos
		var rel_moon_planet: Vector3 = predicted_moon_pos - SimulationState.planet_pos

		predicted_ship_points.append(Vector2(rel_ship_planet.x, -rel_ship_planet.z))
		predicted_moon_points.append(Vector2(rel_moon_planet.x, -rel_moon_planet.z))

		var d: float = rel_ship_planet.length()
		if d < closest_approach_distance:
			closest_approach_distance = d
			closest_approach_time = float(i) * prediction_step_seconds

		var accel := Vector3.ZERO
		accel += _gravity_from_body(test_pos, SimulationState.planet_pos, SimulationState.planet_mu)
		accel += _gravity_from_body(test_pos, predicted_moon_pos, SimulationState.moon_mu)

		test_vel += accel * prediction_step_seconds
		test_pos += test_vel * prediction_step_seconds
		test_time += prediction_step_seconds * SimulationState.celestial_time_scale

func _compute_orbit_solution() -> void:
	var rel: Vector3 = SimulationState.ship_pos - SimulationState.planet_pos
	var vel: Vector3 = SimulationState.ship_vel

	var r: float = rel.length()
	var v2: float = vel.length_squared()
	var mu: float = SimulationState.planet_mu

	if r <= 0.0001 or mu <= 0.0001:
		orbit_classification = "UNRESOLVED"
		periapsis_distance = -1.0
		apoapsis_distance = -1.0
		return

	var specific_energy: float = 0.5 * v2 - mu / r
	var h: Vector3 = rel.cross(vel)
	var e_vec: Vector3 = vel.cross(h) / mu - rel.normalized()
	var e: float = e_vec.length()

	if specific_energy < 0.0:
		var a: float = -mu / (2.0 * specific_energy)
		periapsis_distance = a * (1.0 - e)
		apoapsis_distance = a * (1.0 + e)

		if periapsis_distance <= SimulationState.planet_radius:
			orbit_classification = "IMPACT"
		elif e < 1.0:
			if abs(apoapsis_distance - periapsis_distance) < 0.5:
				orbit_classification = "CIRCULAR"
			else:
				orbit_classification = "ORBIT"
		else:
			orbit_classification = "UNRESOLVED"
	else:
		periapsis_distance = -1.0
		apoapsis_distance = -1.0

		if closest_approach_distance <= SimulationState.planet_radius:
			orbit_classification = "IMPACT"
		else:
			orbit_classification = "ESCAPE"

func _gravity_from_body(position: Vector3, body_pos: Vector3, mu: float) -> Vector3:
	var offset: Vector3 = body_pos - position
	var distance: float = offset.length()

	if distance < SimulationState.min_gravity_distance:
		distance = SimulationState.min_gravity_distance

	return offset * mu / pow(distance, 3.0)

func _draw_dashed_polyline(points: Array[Vector2], color: Color, width: float, dash_length: int, gap_length: int, max_count: int) -> void:
	if points.size() < 2:
		return

	var visible_count: int = min(max_count, points.size())

	var i: int = 0
	while i < visible_count - 1:
		var dash_end: int = min(i + dash_length, visible_count - 1)

		for j in range(i, dash_end):
			draw_line(points[j], points[j + 1], color, width)

		i += dash_length + gap_length

func _get_view_offset() -> Vector2:
	match center_mode:
		CenterMode.PLANET:
			return Vector2.ZERO

		CenterMode.MOON:
			var moon_rel_planet: Vector3 = SimulationState.moon_pos - SimulationState.planet_pos
			return Vector2(-moon_rel_planet.x, moon_rel_planet.z)

		CenterMode.SHIP:
			var ship_rel_planet: Vector3 = SimulationState.ship_pos - SimulationState.planet_pos
			return Vector2(-ship_rel_planet.x, ship_rel_planet.z)

	return Vector2.ZERO

func _to_screen(world_planet_frame: Vector2, center: Vector2, view_offset: Vector2) -> Vector2:
	return center + (world_planet_frame + view_offset) * pixels_per_unit

func _draw() -> void:
	var rect_size: Vector2 = get_viewport_rect().size
	var center: Vector2 = rect_size * 0.5
	var view_offset: Vector2 = _get_view_offset()

	draw_rect(Rect2(Vector2.ZERO, rect_size), Color(0.02, 0.04, 0.02), true)

	# Screen-center guide only
	draw_line(Vector2(center.x, 0.0), Vector2(center.x, rect_size.y), Color(0.05, 0.12, 0.05), 1.0)
	draw_line(Vector2(0.0, center.y), Vector2(rect_size.x, center.y), Color(0.05, 0.12, 0.05), 1.0)

	# Planet is always at world origin in the stored map
	var planet_world := Vector2.ZERO
	var planet_screen := _to_screen(planet_world, center, view_offset)

	# Planet-centered reference rings/crosshair always around planet
	for r in [100.0, 250.0, 500.0]:
		draw_arc(planet_screen, r * pixels_per_unit, 0.0, TAU, 96, Color(0.08, 0.22, 0.08), 1.0)

	draw_line(planet_screen + Vector2(-10.0, 0.0), planet_screen + Vector2(10.0, 0.0), Color(0.1, 0.45, 0.1), 1.0)
	draw_line(planet_screen + Vector2(0.0, -10.0), planet_screen + Vector2(0.0, 10.0), Color(0.1, 0.45, 0.1), 1.0)

	# Planet body
	draw_arc(planet_screen, SimulationState.planet_radius * pixels_per_unit, 0.0, TAU, 128, Color(0.2, 0.65, 1.0), 2.0)

	# Moon current position from planet-centered world
	var moon_rel_planet: Vector3 = SimulationState.moon_pos - SimulationState.planet_pos
	var moon_world := Vector2(moon_rel_planet.x, -moon_rel_planet.z)
	var moon_screen := _to_screen(moon_world, center, view_offset)

	# Moon orbit ring always planet-centered
	draw_arc(planet_screen, SimulationState.moon_orbit_radius * pixels_per_unit, 0.0, TAU, 128, Color(0.5, 0.5, 0.8), 1.0)

	draw_circle(moon_screen, max(3.0, SimulationState.moon_radius * pixels_per_unit), Color(0.8, 0.8, 0.95))

	# Ship current position from planet-centered world
	var ship_rel_planet: Vector3 = SimulationState.ship_pos - SimulationState.planet_pos
	var ship_world := Vector2(ship_rel_planet.x, -ship_rel_planet.z)
	var ship_screen := _to_screen(ship_world, center, view_offset)

	draw_circle(ship_screen, 4.0, Color.WHITE)

	# Velocity vector stays literal, only translated by view offset
	var vel_plan: Vector2 = Vector2(SimulationState.ship_vel.x, -SimulationState.ship_vel.z)
	if vel_plan.length() > 0.001:
		draw_line(ship_screen, ship_screen + vel_plan.normalized() * 40.0, Color.YELLOW, 2.0)

	# Facing vector
	if ship != null:
		var facing_world: Vector3 = ship.global_transform.basis.z.normalized()
		var facing_plan: Vector2 = Vector2(facing_world.x, -facing_world.z)
		if facing_plan.length_squared() > 0.0001:
			draw_line(ship_screen, ship_screen + facing_plan.normalized() * 30.0, Color(0.75, 1.0, 1.0), 2.0)

	if predicted_ship_points.size() > 1:
		var ratio: float = clampf(reveal_elapsed / reveal_duration, 0.0, 1.0) if reveal_duration > 0.0 else 1.0
		var visible_count: int = max(2, int(round((predicted_ship_points.size() - 1) * ratio)) + 1)
		visible_count = min(visible_count, predicted_ship_points.size())

		# Ship path always same shape, only shifted by view offset
		var ship_pts := PackedVector2Array()
		for i in range(visible_count):
			ship_pts.append(_to_screen(predicted_ship_points[i], center, view_offset))
		draw_polyline(ship_pts, Color(0.6, 1.0, 0.7), 2.0)

		# Moon future trail always same shape, only shifted by view offset
		var moon_draw_points: Array[Vector2] = []
		for i in range(visible_count):
			moon_draw_points.append(_to_screen(predicted_moon_points[i], center, view_offset))

		var ghost_count := visible_count
		if center_mode == CenterMode.SHIP:
			ghost_count = min(visible_count, ship_mode_ghost_trail_steps)

		_draw_dashed_polyline(moon_draw_points, Color(0.55, 0.55, 0.9), 1.0, ghost_dash_length, ghost_gap_length, ghost_count)

		if not is_revealing:
			var ca_index: int = 0
			var best_d: float = INF

			for i in range(predicted_ship_points.size()):
				var d: float = predicted_ship_points[i].length()
				if d < best_d:
					best_d = d
					ca_index = i

			var ca_screen: Vector2 = _to_screen(predicted_ship_points[ca_index], center, view_offset)
			draw_circle(ca_screen, 4.0, Color(1.0, 0.45, 0.2))
