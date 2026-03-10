extends Control

@export var ship_path: NodePath

@export var planet_radius_sim: float = 120.0
@export var pixels_per_unit: float = 0.25
@export var min_pixels_per_unit: float = 0.05
@export var max_pixels_per_unit: float = 2.0
@export var zoom_step: float = 0.05

@export var prediction_step_seconds: float = 1.0
@export var prediction_steps: int = 1200

@export var reveal_duration: float = 1.8

var ship: Node3D
var predicted_rel_points: Array[Vector2] = []

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
	size = get_viewport_rect().size

	request_refresh()

func _process(delta: float) -> void:
	size = get_viewport_rect().size

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

func get_status_text() -> String:
	if predicted_rel_points.is_empty():
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

func _compute_prediction() -> void:
	predicted_rel_points.clear()

	var test_pos: Vector3 = SimulationState.ship_pos
	var test_vel: Vector3 = SimulationState.ship_vel

	var start_rel: Vector3 = test_pos - SimulationState.planet_pos
	closest_approach_distance = start_rel.length()
	closest_approach_time = 0.0

	for i in range(prediction_steps):
		var rel: Vector3 = test_pos - SimulationState.planet_pos
		predicted_rel_points.append(Vector2(rel.x, -rel.z))

		var d: float = rel.length()
		if d < closest_approach_distance:
			closest_approach_distance = d
			closest_approach_time = float(i) * prediction_step_seconds

		var accel: Vector3 = SimulationState.gravity_accel_at(test_pos)
		test_vel += accel * prediction_step_seconds
		test_pos += test_vel * prediction_step_seconds

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

		if periapsis_distance <= planet_radius_sim:
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

		if closest_approach_distance <= planet_radius_sim:
			orbit_classification = "IMPACT"
		else:
			orbit_classification = "ESCAPE"

func _draw() -> void:
	var rect_size: Vector2 = size
	if rect_size.x <= 0.0 or rect_size.y <= 0.0:
		rect_size = get_viewport_rect().size

	var center: Vector2 = rect_size * 0.5

	# Background
	draw_rect(Rect2(Vector2.ZERO, rect_size), Color(0.02, 0.04, 0.02), true)

	# Grid rings
	for r in [100.0, 250.0, 500.0, 1000.0]:
		draw_arc(
			center,
			r * pixels_per_unit,
			0.0,
			TAU,
			96,
			Color(0.1, 0.25, 0.1),
			1.0
		)

	# Axis lines
	draw_line(Vector2(center.x, 0.0), Vector2(center.x, rect_size.y), Color(0.1, 0.3, 0.1), 1.0)
	draw_line(Vector2(0.0, center.y), Vector2(rect_size.x, center.y), Color(0.1, 0.3, 0.1), 1.0)

	# Planet
	var planet_radius_px: float = planet_radius_sim * pixels_per_unit
	draw_arc(center, planet_radius_px, 0.0, TAU, 128, Color(0.2, 0.65, 1.0), 2.0)

	# Ship
	var ship_rel: Vector3 = SimulationState.ship_pos - SimulationState.planet_pos
	var ship_screen: Vector2 = center + Vector2(ship_rel.x, -ship_rel.z) * pixels_per_unit
	draw_circle(ship_screen, 4.0, Color.WHITE)

	# Velocity vector
	var vel_plan: Vector2 = Vector2(SimulationState.ship_vel.x, -SimulationState.ship_vel.z)
	if vel_plan.length() > 0.001:
		draw_line(
			ship_screen,
			ship_screen + vel_plan.normalized() * 40.0,
			Color.YELLOW,
			2.0
		)

	# Facing vector
	if ship != null:
		var facing_world: Vector3 = ship.global_transform.basis.z.normalized()
		var facing_plan: Vector2 = Vector2(facing_world.x, -facing_world.z)
		if facing_plan.length_squared() > 0.0001:
			draw_line(
				ship_screen,
				ship_screen + facing_plan.normalized() * 30.0,
				Color(0.75, 1.0, 1.0),
				2.0
			)

	# Trajectory
	if predicted_rel_points.size() > 1:
		var pts := PackedVector2Array()

		var ratio: float = 1.0
		if reveal_duration > 0.0:
			ratio = clampf(reveal_elapsed / reveal_duration, 0.0, 1.0)

		var visible_count: int = max(2, int(round((predicted_rel_points.size() - 1) * ratio)) + 1)
		visible_count = min(visible_count, predicted_rel_points.size())

		for i in range(visible_count):
			pts.append(center + predicted_rel_points[i] * pixels_per_unit)

		draw_polyline(pts, Color(0.6, 1.0, 0.7), 2.0)

		# Closest approach marker once finished
		if not is_revealing:
			var ca_index: int = 0
			var best_d: float = INF

			for i in range(predicted_rel_points.size()):
				var d: float = predicted_rel_points[i].length()
				if d < best_d:
					best_d = d
					ca_index = i

			var ca_screen: Vector2 = center + predicted_rel_points[ca_index] * pixels_per_unit
			draw_circle(ca_screen, 4.0, Color(1.0, 0.45, 0.2))
