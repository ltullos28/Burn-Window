extends Control

enum CenterMode {
	PLANET,
	MOON,
	SHIP
}

@export var ship_path: NodePath
@export var min_prediction_steps: int = 1200
@export var max_prediction_steps: int = 12000
@export var pixels_per_unit: float = 0.046
@export var min_pixels_per_unit: float = 0.0008
@export var max_pixels_per_unit: float = 0.12
@export var zoom_step: float = 0.0025

@export var prediction_step_seconds: float = 2.0
@export var prediction_steps: int = 4000
@export var reveal_duration: float = 4.5

@export var center_mode: CenterMode = CenterMode.PLANET

@export var ghost_dash_length: int = 10
@export var ghost_gap_length: int = 6
@export var ship_mode_ghost_trail_steps: int = 220

@export var center_transition_duration: float = 0.65

var ship: Node3D

var predictor := TrajectoryPredictor.new()
var orbit_solver := OrbitSolver.new()
var solution := TrajectorySolution.new()

var is_revealing: bool = false
var reveal_elapsed: float = 0.0

var current_view_offset: Vector2 = Vector2.ZERO
var transition_start_offset: Vector2 = Vector2.ZERO
var transition_elapsed: float = 0.0
var transition_active: bool = false

func _ready() -> void:
	ship = get_node_or_null(ship_path) as Node3D
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	current_view_offset = _get_target_view_offset()
	transition_start_offset = current_view_offset

	request_refresh()

func _process(delta: float) -> void:
	if is_revealing:
		reveal_elapsed += delta
		if reveal_elapsed >= reveal_duration:
			reveal_elapsed = reveal_duration
			is_revealing = false

	_update_center_transition(delta)
	queue_redraw()

func _update_center_transition(delta: float) -> void:
	var target_offset: Vector2 = _get_target_view_offset()

	if not transition_active:
		current_view_offset = target_offset
		return

	transition_elapsed += delta

	if center_transition_duration <= 0.0:
		current_view_offset = target_offset
		transition_active = false
		return

	var t: float = clampf(transition_elapsed / center_transition_duration, 0.0, 1.0)

	var eased: float
	if t < 0.5:
		eased = 4.0 * t * t * t
	else:
		eased = 1.0 - pow(-2.0 * t + 2.0, 3.0) / 2.0

	current_view_offset = transition_start_offset.lerp(target_offset, eased)

	if t >= 1.0:
		current_view_offset = target_offset
		transition_active = false

func request_refresh() -> void:
	_compute_solution()
	reveal_elapsed = 0.0
	is_revealing = true

func _compute_solution() -> void:
	var steps_to_use := _get_dynamic_prediction_steps()
	var prediction := predictor.compute(
		SimulationState.ship_pos,
		SimulationState.ship_vel,
		SimulationState.sim_time,
		prediction_step_seconds,
		steps_to_use
)

	var orbit := orbit_solver.solve_planet_orbit(
		SimulationState.ship_pos,
		SimulationState.ship_vel,
		SimulationState.planet_pos,
		SimulationState.planet_mu,
		SimulationState.planet_radius
	)

	solution = TrajectorySolution.new()

	solution.ship_points = prediction["ship_points"]
	solution.moon_points = prediction["moon_points"]
	solution.closest_approach_distance = prediction["closest_approach_distance"]
	solution.closest_approach_time = prediction["closest_approach_time"]
	solution.moon_closest_approach_distance = prediction["moon_closest_approach_distance"]
	solution.moon_closest_approach_time = prediction["moon_closest_approach_time"]
	solution.moon_relative_speed_at_closest_approach = prediction["moon_relative_speed_at_closest_approach"]

	solution.orbit_classification = orbit["orbit_classification"]
	solution.periapsis_distance = orbit["periapsis_distance"]
	solution.apoapsis_distance = orbit["apoapsis_distance"]
	solution.eccentricity_value = orbit["eccentricity_value"]
	solution.semi_major_axis_value = orbit["semi_major_axis_value"]
	solution.orbital_period_value = orbit["orbital_period_value"]
	solution.periapsis_marker_world = orbit["periapsis_marker_world"]
	solution.apoapsis_marker_world = orbit["apoapsis_marker_world"]
	solution.has_periapsis_marker = orbit["has_periapsis_marker"]
	solution.has_apoapsis_marker = orbit["has_apoapsis_marker"]

func zoom_in() -> void:
	pixels_per_unit = clampf(pixels_per_unit + zoom_step, min_pixels_per_unit, max_pixels_per_unit)

func zoom_out() -> void:
	pixels_per_unit = clampf(pixels_per_unit - zoom_step, min_pixels_per_unit, max_pixels_per_unit)

func set_center_planet() -> void:
	_begin_center_transition(CenterMode.PLANET)

func set_center_moon() -> void:
	_begin_center_transition(CenterMode.MOON)

func set_center_ship() -> void:
	_begin_center_transition(CenterMode.SHIP)

func cycle_center_mode() -> void:
	var next_mode: CenterMode = (center_mode + 1) % 3
	_begin_center_transition(next_mode)
func _get_dynamic_prediction_steps() -> int:
	# pixels_per_unit:
	# higher = zoomed in
	# lower = zoomed out
	#
	# We invert that relationship so zooming out gives more steps.

	var zoom_alpha := inverse_lerp(max_pixels_per_unit, min_pixels_per_unit, pixels_per_unit)
	zoom_alpha = clampf(zoom_alpha, 0.0, 1.0)

	return int(round(lerpf(min_prediction_steps, max_prediction_steps, zoom_alpha)))
func _begin_center_transition(new_mode: CenterMode) -> void:
	transition_start_offset = current_view_offset
	transition_elapsed = 0.0
	transition_active = true
	center_mode = new_mode

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
	if solution.ship_points.is_empty():
		return "NO SOLUTION"
	if is_revealing:
		return "COMPUTING..."
	return "READY"

func get_reference_body_text() -> String:
	return "PLANET"

func get_closest_approach_distance() -> float:
	return solution.closest_approach_distance

func get_closest_approach_time() -> float:
	return solution.closest_approach_time

func get_classification() -> String:
	return solution.orbit_classification

func get_periapsis() -> float:
	return solution.periapsis_distance

func get_apoapsis() -> float:
	return solution.apoapsis_distance

func get_eccentricity() -> float:
	return solution.eccentricity_value

func get_semi_major_axis() -> float:
	return solution.semi_major_axis_value

func get_orbital_period() -> float:
	return solution.orbital_period_value

func get_zoom_value() -> float:
	return pixels_per_unit

func get_reveal_duration() -> float:
	return reveal_duration

func get_ship_altitude() -> float:
	var r: float = (SimulationState.ship_pos - SimulationState.planet_pos).length()
	return r - SimulationState.planet_radius

func get_ship_speed() -> float:
	return SimulationState.ship_vel.length()

func get_ship_radial_velocity() -> float:
	var rel: Vector3 = SimulationState.ship_pos - SimulationState.planet_pos
	var rhat: Vector3 = rel.normalized()
	return SimulationState.ship_vel.dot(rhat)

func get_ship_tangential_velocity() -> float:
	var rel: Vector3 = SimulationState.ship_pos - SimulationState.planet_pos
	var rhat: Vector3 = rel.normalized()
	var radial_v: float = SimulationState.ship_vel.dot(rhat)
	var radial_vec: Vector3 = rhat * radial_v
	return (SimulationState.ship_vel - radial_vec).length()

func get_moon_closest_approach_distance() -> float:
	return solution.moon_closest_approach_distance

func get_moon_closest_approach_time() -> float:
	return solution.moon_closest_approach_time

func get_moon_relative_speed_at_closest_approach() -> float:
	return solution.moon_relative_speed_at_closest_approach

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

func _get_target_view_offset() -> Vector2:
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

func _to_screen(world_planet_frame: Vector2, center: Vector2) -> Vector2:
	return center + (world_planet_frame + current_view_offset) * pixels_per_unit

func _draw_marker_square(pos: Vector2, size: float, color: Color) -> void:
	var half := size * 0.5
	draw_rect(
		Rect2(pos - Vector2(half, half), Vector2(size, size)),
		color,
		false,
		1.25
	)

func _draw_marker_label(pos: Vector2, text_value: String, color: Color, screen_center_x: float) -> void:
	var font := ThemeDB.fallback_font
	var font_size := 12

	if pos.x < screen_center_x:
		draw_string(
			font,
			pos + Vector2(-26.0, -6.0),
			text_value,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			color
		)
	else:
		draw_string(
			font,
			pos + Vector2(8.0, -6.0),
			text_value,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			color
		)

func _draw() -> void:
	var rect_size: Vector2 = get_viewport_rect().size
	var center: Vector2 = rect_size * 0.5

	draw_rect(Rect2(Vector2.ZERO, rect_size), Color(0.02, 0.04, 0.02), true)

	draw_line(Vector2(center.x, 0.0), Vector2(center.x, rect_size.y), Color(0.05, 0.12, 0.05), 1.0)
	draw_line(Vector2(0.0, center.y), Vector2(rect_size.x, center.y), Color(0.05, 0.12, 0.05), 1.0)

	var planet_world := Vector2.ZERO
	var planet_screen := _to_screen(planet_world, center)

	for r in [250.0, 1000.0, 2500.0]:
		draw_arc(planet_screen, r * pixels_per_unit, 0.0, TAU, 96, Color(0.08, 0.22, 0.08), 1.0)

	draw_line(planet_screen + Vector2(-10.0, 0.0), planet_screen + Vector2(10.0, 0.0), Color(0.1, 0.45, 0.1), 1.0)
	draw_line(planet_screen + Vector2(0.0, -10.0), planet_screen + Vector2(0.0, 10.0), Color(0.1, 0.45, 0.1), 1.0)

	draw_arc(planet_screen, SimulationState.planet_radius * pixels_per_unit, 0.0, TAU, 128, Color(0.2, 0.65, 1.0), 2.0)

	var moon_rel_planet: Vector3 = SimulationState.moon_pos - SimulationState.planet_pos
	var moon_world := Vector2(moon_rel_planet.x, -moon_rel_planet.z)
	var moon_screen := _to_screen(moon_world, center)

	draw_arc(planet_screen, SimulationState.moon_orbit_radius * pixels_per_unit, 0.0, TAU, 128, Color(0.5, 0.5, 0.8), 1.0)
	draw_circle(moon_screen, max(3.0, SimulationState.moon_radius * pixels_per_unit), Color(0.8, 0.8, 0.95))

	var ship_rel_planet: Vector3 = SimulationState.ship_pos - SimulationState.planet_pos
	var ship_world := Vector2(ship_rel_planet.x, -ship_rel_planet.z)
	var ship_screen := _to_screen(ship_world, center)

	draw_circle(ship_screen, 4.0, Color.WHITE)

	var vel_plan: Vector2 = Vector2(SimulationState.ship_vel.x, -SimulationState.ship_vel.z)
	if vel_plan.length() > 0.001:
		draw_line(ship_screen, ship_screen + vel_plan.normalized() * 40.0, Color.YELLOW, 2.0)

	if ship != null:
		var facing_world: Vector3 = ship.global_transform.basis.z.normalized()
		var facing_plan: Vector2 = Vector2(facing_world.x, -facing_world.z)
		if facing_plan.length_squared() > 0.0001:
			draw_line(ship_screen, ship_screen + facing_plan.normalized() * 30.0, Color(0.75, 1.0, 1.0), 2.0)

	if solution.ship_points.size() > 1:
		var ratio: float = clampf(reveal_elapsed / reveal_duration, 0.0, 1.0) if reveal_duration > 0.0 else 1.0
		var visible_count: int = max(2, int(round((solution.ship_points.size() - 1) * ratio)) + 1)
		visible_count = min(visible_count, solution.ship_points.size())

		var ship_pts := PackedVector2Array()
		for i in range(visible_count):
			ship_pts.append(_to_screen(solution.ship_points[i], center))
		draw_polyline(ship_pts, Color(0.6, 1.0, 0.7), 2.0)

		var moon_draw_points: Array[Vector2] = []
		for i in range(visible_count):
			moon_draw_points.append(_to_screen(solution.moon_points[i], center))

		var ghost_count := visible_count
		if center_mode == CenterMode.SHIP:
			ghost_count = min(ghost_count, ship_mode_ghost_trail_steps)

		_draw_dashed_polyline(moon_draw_points, Color(0.0, 0.0, 0.9, 1.0), 2.5, ghost_dash_length, ghost_gap_length, ghost_count)

		if not is_revealing:
			var ca_index: int = 0
			var best_d: float = INF

			for i in range(solution.ship_points.size()):
				var d: float = solution.ship_points[i].length()
				if d < best_d:
					best_d = d
					ca_index = i

			var ca_screen: Vector2 = _to_screen(solution.ship_points[ca_index], center)
			draw_circle(ca_screen, 4.0, Color(1.0, 0.45, 0.2))

	if solution.has_periapsis_marker:
		var pe_screen := _to_screen(solution.periapsis_marker_world, center)
		_draw_marker_square(pe_screen, 6.0, Color(0.35, 1.0, 0.35))
		_draw_marker_label(pe_screen, "PE", Color(0.35, 1.0, 0.35), center.x)

	if solution.has_apoapsis_marker and solution.orbit_classification != "ESCAPE" and solution.orbit_classification != "IMPACT":
		var ap_screen := _to_screen(solution.apoapsis_marker_world, center)
		_draw_marker_square(ap_screen, 6.0, Color(0.35, 0.75, 1.0))
		_draw_marker_label(ap_screen, "AP", Color(0.35, 0.75, 1.0), center.x)
