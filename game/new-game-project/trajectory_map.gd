extends Control

enum CenterMode {
	PLANET,
	MOON,
	SHIP
}

enum DisplayMode {
	TRAJECTORY,
	INCLINATION
}

@export var ship_path: NodePath
@export var ghost_lifetime_seconds: float = 10.0
@export var pixels_per_unit: float = 0.046
@export var min_pixels_per_unit: float = 0.0008
@export var max_pixels_per_unit: float = 0.12
@export var zoom_step: float = 0.0025

@export var prediction_step_seconds: float = 2
@export var prediction_steps: int = 4000
@export var reveal_duration: float = 5

# Dynamic prediction control
@export var min_prediction_steps: int = 1200
@export var max_prediction_steps: int = 12000
@export var period_prediction_margin: float = 1.0
@export var moon_encounter_extra_time: float = 400.0
@export var strong_moon_ca_multiplier: float = 3.0
@export var extrema_window_radius: int = 4
@export var radial_extrema_tolerance: float = 4.0
@export var center_mode: CenterMode = CenterMode.PLANET
@export var display_mode: DisplayMode = DisplayMode.TRAJECTORY

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
var ghost_elapsed: float = 0.0

var current_view_offset: Vector2 = Vector2.ZERO
var transition_start_offset: Vector2 = Vector2.ZERO
var transition_elapsed: float = 0.0
var transition_active: bool = false

func _ready() -> void:
	ship = get_node_or_null(ship_path) as Node3D
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_sanitize_modes()

	current_view_offset = _get_target_view_offset()
	transition_start_offset = current_view_offset

func _process(delta: float) -> void:
	_sanitize_modes()

	if is_revealing:
		reveal_elapsed += delta
		if reveal_elapsed >= reveal_duration:
			reveal_elapsed = reveal_duration
			is_revealing = false

	ghost_elapsed += delta

	_update_center_transition(delta)
	queue_redraw()

func _sanitize_modes() -> void:
	if display_mode == DisplayMode.INCLINATION and center_mode == CenterMode.SHIP:
		center_mode = CenterMode.PLANET

func _update_center_transition(delta: float) -> void:
	var target_offset: Vector2 = _get_target_view_offset()

	if display_mode == DisplayMode.INCLINATION:
		current_view_offset = target_offset
		transition_active = false
		return

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
	ghost_elapsed = 0.0
	is_revealing = true

func cycle_display_mode() -> void:
	if display_mode == DisplayMode.TRAJECTORY:
		display_mode = DisplayMode.INCLINATION
		if center_mode == CenterMode.SHIP:
			center_mode = CenterMode.PLANET
	else:
		display_mode = DisplayMode.TRAJECTORY

	transition_active = false
	current_view_offset = _get_target_view_offset()
	queue_redraw()

func cycle_center_mode() -> void:
	if display_mode == DisplayMode.INCLINATION:
		if center_mode == CenterMode.SHIP:
			center_mode = CenterMode.PLANET
		elif center_mode == CenterMode.PLANET:
			center_mode = CenterMode.MOON
		else:
			center_mode = CenterMode.PLANET

		transition_active = false
		current_view_offset = _get_target_view_offset()
		queue_redraw()
		return

	match center_mode:
		CenterMode.PLANET:
			_begin_center_transition(CenterMode.MOON)
		CenterMode.MOON:
			_begin_center_transition(CenterMode.SHIP)
		CenterMode.SHIP:
			_begin_center_transition(CenterMode.PLANET)

func _get_zoom_based_prediction_steps() -> int:
	var zoom_alpha: float = inverse_lerp(max_pixels_per_unit, min_pixels_per_unit, pixels_per_unit)
	zoom_alpha = clampf(zoom_alpha, 0.0, 1.0)
	return int(round(lerpf(min_prediction_steps, max_prediction_steps, zoom_alpha)))

func _get_period_based_prediction_steps() -> int:
	var orbit: Dictionary = orbit_solver.solve_planet_orbit(
		SimulationState.ship_pos,
		SimulationState.ship_vel,
		SimulationState.planet_pos,
		SimulationState.planet_mu,
		SimulationState.planet_radius
	)

	var is_bound: bool = orbit["is_bound_orbit"]
	if not is_bound:
		return prediction_steps

	var period: float = orbit["orbital_period_value"]
	if period <= 0.0:
		return prediction_steps

	var needed_time: float = period * period_prediction_margin
	return int(ceil(needed_time / prediction_step_seconds))

func _get_dynamic_prediction_steps() -> int:
	var steps_from_zoom: int = _get_zoom_based_prediction_steps()
	var steps_from_period: int = _get_period_based_prediction_steps()

	var steps_to_use: int = max(steps_from_zoom, steps_from_period)

	var quick_prediction: Dictionary = predictor.compute(
		SimulationState.ship_pos,
		SimulationState.ship_vel,
		SimulationState.sim_time,
		prediction_step_seconds,
		steps_to_use,
		extrema_window_radius,
		radial_extrema_tolerance
	)

	var moon_ca: float = quick_prediction["moon_closest_approach_distance"]
	var moon_tca: float = quick_prediction["moon_closest_approach_time"]
	var strong_moon_threshold: float = SimulationState.moon_radius * strong_moon_ca_multiplier

	if moon_ca > 0.0 and moon_ca <= strong_moon_threshold and moon_tca > 0.0:
		var encounter_steps: int = int(ceil((moon_tca + moon_encounter_extra_time) / prediction_step_seconds))
		steps_to_use = max(steps_to_use, encounter_steps)

	steps_to_use = max(steps_to_use, min_prediction_steps)
	steps_to_use = min(steps_to_use, max_prediction_steps)

	return steps_to_use

func _compute_solution() -> void:
	var steps_to_use: int = _get_dynamic_prediction_steps()

	var prediction: Dictionary = predictor.compute(
		SimulationState.ship_pos,
		SimulationState.ship_vel,
		SimulationState.sim_time,
		prediction_step_seconds,
		steps_to_use,
		extrema_window_radius,
		radial_extrema_tolerance
	)

	var orbit: Dictionary = orbit_solver.solve_planet_orbit(
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
	solution.moon_closest_approach_index = prediction["moon_closest_approach_index"]
	solution.moon_dominance = prediction["moon_dominance"]

	solution.predicted_periapsis_distance = prediction["predicted_periapsis_distance"]
	solution.predicted_apoapsis_distance = prediction["predicted_apoapsis_distance"]
	solution.predicted_periapsis_time = prediction["predicted_periapsis_time"]
	solution.predicted_apoapsis_time = prediction["predicted_apoapsis_time"]
	solution.predicted_periapsis_index = prediction["predicted_periapsis_index"]
	solution.predicted_apoapsis_index = prediction["predicted_apoapsis_index"]

	solution.orbit_classification = orbit["orbit_classification"]
	solution.periapsis_distance = orbit["periapsis_distance"]
	solution.apoapsis_distance = orbit["apoapsis_distance"]
	solution.eccentricity_value = orbit["eccentricity_value"]
	solution.semi_major_axis_value = orbit["semi_major_axis_value"]
	solution.orbital_period_value = orbit["orbital_period_value"]
	solution.is_bound_orbit = orbit["is_bound_orbit"]
	solution.specific_energy = orbit["specific_energy"]

	solution.prediction_steps_used = steps_to_use
	solution.prediction_duration_used = float(steps_to_use) * prediction_step_seconds

func zoom_in() -> void:
	pixels_per_unit = min(max_pixels_per_unit, pixels_per_unit + zoom_step)

func zoom_out() -> void:
	pixels_per_unit = max(min_pixels_per_unit, pixels_per_unit - zoom_step)

func set_center_planet() -> void:
	_begin_center_transition(CenterMode.PLANET)

func set_center_moon() -> void:
	_begin_center_transition(CenterMode.MOON)

func set_center_ship() -> void:
	_begin_center_transition(CenterMode.SHIP)

func _begin_center_transition(new_mode: CenterMode) -> void:
	if display_mode == DisplayMode.INCLINATION and new_mode == CenterMode.SHIP:
		new_mode = CenterMode.PLANET

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

func get_display_mode_text() -> String:
	match display_mode:
		DisplayMode.TRAJECTORY:
			return "TRAJECTORY"
		DisplayMode.INCLINATION:
			return "PLANE"
	return "UNKNOWN"

func get_status_text() -> String:
	if display_mode == DisplayMode.INCLINATION:
		return "LIVE"

	if solution.ship_points.is_empty():
		return "NO SOLUTION"
	if is_revealing:
		return "COMPUTING..."
	return "READY"

func get_reference_body_text() -> String:
	if display_mode == DisplayMode.INCLINATION:
		match center_mode:
			CenterMode.PLANET:
				return "PLANET"
			CenterMode.MOON:
				return "MOON"
			CenterMode.SHIP:
				return "PLANET"
	return "PLANET"

func get_closest_approach_distance() -> float:
	return solution.closest_approach_distance

func get_closest_approach_time() -> float:
	return solution.closest_approach_time

func get_classification() -> String:
	return solution.orbit_classification

func get_periapsis() -> float:
	if solution.predicted_periapsis_distance > 0.0:
		return solution.predicted_periapsis_distance
	return solution.periapsis_distance

func get_apoapsis() -> float:
	if solution.predicted_apoapsis_distance > 0.0:
		return solution.predicted_apoapsis_distance
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

func get_prediction_steps_used() -> int:
	return solution.prediction_steps_used

func get_prediction_duration_used() -> float:
	return solution.prediction_duration_used

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

func _project_planet_frame(world_planet_frame: Vector3) -> Vector2:
	return Vector2(world_planet_frame.x, -world_planet_frame.z)

func _to_screen(world_planet_frame: Vector3, center: Vector2) -> Vector2:
	return center + (_project_planet_frame(world_planet_frame) + current_view_offset) * pixels_per_unit

func _draw_marker_square(pos: Vector2, marker_size: float, color: Color) -> void:
	var half := marker_size * 0.5
	draw_rect(
		Rect2(pos - Vector2(half, half), Vector2(marker_size, marker_size)),
		color,
		false,
		1.25
	)

func _draw_marker_label(pos: Vector2, text_value: String, color: Color, reference_screen: Vector2) -> void:
	var font := ThemeDB.fallback_font
	var font_size := 12

	var radial := pos - reference_screen
	if radial.length_squared() < 0.0001:
		radial = Vector2.RIGHT
	else:
		radial = radial.normalized()

	var text_size: Vector2 = font.get_string_size(text_value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)

	var label_distance := 16.0
	if text_value == "CA" or text_value == "PE":
		label_distance = 24.0

	var outward_offset := radial * label_distance
	var draw_pos := pos + outward_offset + Vector2(-text_size.x * 0.5, text_size.y * 0.35)

	draw_string(
		font,
		draw_pos,
		text_value,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		color
	)

func _get_reference_body_pos() -> Vector3:
	match center_mode:
		CenterMode.MOON:
			return SimulationState.moon_pos
		_:
			return SimulationState.planet_pos

func _get_reference_body_vel() -> Vector3:
	match center_mode:
		CenterMode.MOON:
			return SimulationState.moon_vel
		_:
			return SimulationState.planet_vel

func _get_reference_body_up() -> Vector3:
	match center_mode:
		CenterMode.MOON:
			if SimulationState.moon_up.length_squared() > 0.0001:
				return SimulationState.moon_up.normalized()
			return Vector3.UP
		_:
			if SimulationState.planet_up.length_squared() > 0.0001:
				return SimulationState.planet_up.normalized()
			return Vector3.UP

func _get_reference_body_radius() -> float:
	match center_mode:
		CenterMode.MOON:
			return SimulationState.moon_radius
		_:
			return SimulationState.planet_radius

func _draw_glow_line(a: Vector2, b: Vector2, color: Color, width: float) -> void:
	draw_line(a, b, Color(color.r, color.g, color.b, 0.12), width + 6.0)
	draw_line(a, b, Color(color.r, color.g, color.b, 0.22), width + 3.0)
	draw_line(a, b, color, width)

func _draw_angle_ticks(center: Vector2, radius: float, start_angle: float, end_angle: float, tick_step_deg: float, color: Color) -> void:
	if tick_step_deg <= 0.0:
		return

	var a0: float = start_angle
	var a1: float = end_angle

	if a1 < a0:
		var temp: float = a0
		a0 = a1
		a1 = temp

	var step: float = deg_to_rad(tick_step_deg)
	var angle: float = ceil(a0 / step) * step

	while angle < a1 - 0.0001:
		var outer: Vector2 = center + Vector2(cos(angle), sin(angle)) * radius
		var inner: Vector2 = center + Vector2(cos(angle), sin(angle)) * (radius - 6.0)
		draw_line(inner, outer, color, 1.0)
		angle += step

func _draw_inclination_instrument(rect_size: Vector2, center: Vector2) -> void:
	var side: float = rect_size.y * 0.985
	var inst_center: Vector2 = center

	var outer_radius: float = side * 0.43
	
	var line_half: float = outer_radius
	var body_radius_px: float = side * 0.085

	var equator_color: Color = Color(0.15, 0.45, 0.2)
	var body_color: Color = Color(0.2, 0.8, 0.35)
	var plane_color: Color = Color(0.4, 1.0, 0.6)
	var node_color: Color = Color(0.3, 0.9, 1.0)
	var theta_color: Color = Color(1.0, 0.8, 0.35)
	var ship_color: Color = Color(0.95, 0.95, 0.95)
	var text_green: Color = Color(0.75, 1.0, 0.2)
	var center_label_color: Color = Color.BLACK
	var outer_circle_color: Color = Color(0.75, 1.0, 0.2)

	var body_pos: Vector3 = _get_reference_body_pos()
	var body_vel: Vector3 = _get_reference_body_vel()
	var body_up: Vector3 = _get_reference_body_up()

	var r: Vector3 = SimulationState.ship_pos - body_pos
	var v: Vector3 = SimulationState.ship_vel - body_vel
	var h: Vector3 = v.cross(r)

	var font := ThemeDB.fallback_font
	var font_size := 14
	var big_font_size := 30
	var title_text: String = "EQUATOR"
	var title_size: Vector2 = font.get_string_size(title_text, HORIZONTAL_ALIGNMENT_LEFT, -1, big_font_size)
	draw_string(
		font,
		Vector2(inst_center.x - title_size.x * 0.5, 36.0),
		title_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		big_font_size,
		Color(0.35, 1.0, 0.35)
	)
	# Outer circle
	draw_arc(inst_center, outer_radius, 0.0, TAU, 128, outer_circle_color, 2.0)

	# Hash marks all around outer circle
	var tick_step_deg: float = 5.0
	var tick_step_rad: float = deg_to_rad(tick_step_deg)
	var tick_angle: float = 0.0
	while tick_angle < TAU - 0.0001:
		var outer: Vector2 = inst_center + Vector2(cos(tick_angle), sin(tick_angle)) * outer_radius
		var inner: Vector2 = inst_center + Vector2(cos(tick_angle), sin(tick_angle)) * (outer_radius - 7.0)
		draw_line(inner, outer, Color(0.35, 0.75, 0.2, 0.9), 1.0)
		tick_angle += tick_step_rad

	# Equator line
	var eq_a: Vector2 = inst_center + Vector2(-line_half, 0.0)
	var eq_b: Vector2 = inst_center + Vector2(line_half, 0.0)
	_draw_glow_line(eq_a, eq_b, equator_color, 2.0)

	# Body
	draw_circle(inst_center, body_radius_px, body_color)

	if r.length_squared() < 0.0001 or v.length_squared() < 0.0001 or h.length_squared() < 0.0001:
		var reference_text_empty: String = "Reference: " + get_reference_body_text().capitalize()
		var ref_size_empty: Vector2 = font.get_string_size(reference_text_empty, HORIZONTAL_ALIGNMENT_LEFT, -1, big_font_size)
		draw_string(
			font,
			Vector2(60.0, rect_size.y - 28.0),
			"ASCENDING...",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			big_font_size,
			text_green
		)

		draw_string(
			font,
			Vector2(rect_size.x - ref_size_empty.x - 60.0, rect_size.y - 28.0),
			reference_text_empty,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			big_font_size,
			text_green
		)
		return

	var hhat: Vector3 = h.normalized()
	var dot_val: float = clampf(hhat.dot(body_up), -1.0, 1.0)

	var inc_display_rad: float = acos(abs(dot_val))
	var inc_display_deg: float = rad_to_deg(inc_display_rad)

	# Plane indicator angle
	var plane_angle: float = -inc_display_rad
	var plane_dir: Vector2 = Vector2(cos(plane_angle), sin(plane_angle)).normalized()

	# Two connected half-segments
	var plane_end_pos: Vector2 = inst_center + plane_dir * (outer_radius - 6.0)
	var plane_end_neg: Vector2 = inst_center - plane_dir * (outer_radius - 6.0)

	_draw_glow_line(inst_center, plane_end_pos, plane_color, 2.5)
	_draw_glow_line(inst_center, plane_end_neg, plane_color, 2.5)

	# Node geometry
	var node_vec: Vector3 = body_up.cross(h)
	if node_vec.length_squared() < 0.0001:
		var fallback: Vector3 = Vector3.RIGHT
		if abs(body_up.dot(fallback)) > 0.95:
			fallback = Vector3.FORWARD
		node_vec = (fallback - body_up * body_up.dot(fallback)).normalized()

	var node_hat: Vector3 = node_vec.normalized()
	var q_hat: Vector3 = hhat.cross(node_hat).normalized()

	# Argument relative to ascending node, wrapped to [0, TAU)
	var u: float = atan2(r.dot(q_hat), r.dot(node_hat))
	if u < 0.0:
		u += TAU

	var vertical_rate: float = v.dot(body_up)

	var active_node_label: String = "AN"
	var motion_text: String = "Ascending..."
	if vertical_rate < 0.0:
		active_node_label = "DN"
		motion_text = "DESCENDING..."

	var flat_threshold_deg: float = 0.5
	var is_flat: bool = inc_display_deg < flat_threshold_deg
	if is_flat:
		motion_text = "FLAT"

	var handedness: float = sign(h.dot(body_up))
	if abs(handedness) < 0.001:
		handedness = 1.0

	var line_displacement: float = sin(u) * handedness * (outer_radius - 12.0)
	var ship_marker: Vector2 = inst_center + plane_dir * line_displacement

	# Center node marker and readable label
	draw_circle(inst_center, 4.5, node_color)

	var center_label_size: Vector2 = font.get_string_size(active_node_label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	draw_string(
		font,
		inst_center + Vector2(-center_label_size.x * 0.5, center_label_size.y * 0.35),
		active_node_label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		center_label_color
	)

	# Ship marker
	draw_circle(ship_marker, 6.5, Color(1,1,1,0.08))
	draw_circle(ship_marker, 5.0, Color(1,1,1,0.15))
	draw_circle(ship_marker, 3.5, Color.WHITE)

	# Theta arc moved outward near outer circle edge
	var arc_radius: float = outer_radius - 16.0
	draw_arc(inst_center, arc_radius, plane_angle, 0.0, 48, theta_color, 2.5)
	

	var mid_angle: float = plane_angle * 0.5
	var theta_text_pos: Vector2 = inst_center + Vector2(cos(mid_angle), sin(mid_angle)) * (arc_radius - 18.0)

	var theta_text := "%.1f°" % inc_display_deg
	var theta_text_size: Vector2 = font.get_string_size(theta_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	draw_string(
		font,
		theta_text_pos + Vector2(-theta_text_size.x * 0.5, theta_text_size.y * 0.35),
		theta_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		theta_color
	)

	# Bottom left status text
	draw_string(
		font,
		Vector2(60.0, rect_size.y - 28.0),
		motion_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		big_font_size,
		text_green
	)

	# Bottom right reference text
	var reference_text: String = "Reference: " + get_reference_body_text().capitalize()
	var ref_size: Vector2 = font.get_string_size(reference_text, HORIZONTAL_ALIGNMENT_LEFT, -1, big_font_size)
	draw_string(
		font,
		Vector2(rect_size.x - ref_size.x - 60.0, rect_size.y - 28.0),
		reference_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		big_font_size,
		text_green
	)

func _draw() -> void:
	var rect_size: Vector2 = get_viewport_rect().size
	var center: Vector2 = rect_size * 0.5
	var font := ThemeDB.fallback_font
	var big_font_size := 30
	var text_green := Color(0.35, 1.0, 0.35)
	
	draw_rect(Rect2(Vector2.ZERO, rect_size), Color(0.02, 0.04, 0.02), true)

	if display_mode == DisplayMode.INCLINATION:
		_draw_inclination_instrument(rect_size, center)
		return
	var plan_title: String = "PLAN"
	var plan_title_size: Vector2 = font.get_string_size(plan_title, HORIZONTAL_ALIGNMENT_LEFT, -1, big_font_size)
	draw_string(
		font,
		Vector2(center.x - plan_title_size.x * 0.5, 46.0),
		plan_title,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		big_font_size,
		text_green
	)
	draw_line(Vector2(center.x, 0.0), Vector2(center.x, rect_size.y), Color(0.05, 0.12, 0.05), 1.0)
	draw_line(Vector2(0.0, center.y), Vector2(rect_size.x, center.y), Color(0.05, 0.12, 0.05), 1.0)

	var planet_world := Vector3.ZERO
	var planet_screen := _to_screen(planet_world, center)
	var planet_radius_px: float = max(3.0, SimulationState.planet_radius * pixels_per_unit)

	for r in [250.0, 1000.0, 2500.0]:
		draw_arc(planet_screen, r * pixels_per_unit, 0.0, TAU, 96, Color(0.08, 0.22, 0.08), 1.0)

	draw_line(planet_screen + Vector2(-10.0, 0.0), planet_screen + Vector2(10.0, 0.0), Color(0.1, 0.45, 0.1), 1.0)
	draw_line(planet_screen + Vector2(0.0, -10.0), planet_screen + Vector2(0.0, 10.0), Color(0.1, 0.45, 0.1), 1.0)

	draw_circle(planet_screen, planet_radius_px, Color(0.2, 0.65, 1.0))

	var moon_rel_planet: Vector3 = SimulationState.moon_pos - SimulationState.planet_pos
	var moon_screen := _to_screen(moon_rel_planet, center)

	draw_arc(planet_screen, SimulationState.moon_orbit_radius * pixels_per_unit, 0.0, TAU, 128, Color(0.5, 0.5, 0.8), 1.0)
	draw_circle(moon_screen, max(3.0, SimulationState.moon_radius * pixels_per_unit), Color(0.8, 0.8, 0.95))

	var ship_rel_planet: Vector3 = SimulationState.ship_pos - SimulationState.planet_pos
	var ship_screen := _to_screen(ship_rel_planet, center)

	var r3: Vector3 = SimulationState.ship_pos - SimulationState.planet_pos
	var v3: Vector3 = SimulationState.ship_vel
	var body_up: Vector3 = SimulationState.planet_up.normalized()

	var vel: float = v3.length()
	var vel_text: String = "VEL: %.3f NU/s" % vel

	var radius: float = r3.length()
	var r_text: String = "ALT: %.3f NU" % radius

	var h3: Vector3 = r3.cross(v3)
	var inc: float = 0.0
	if h3.length_squared() > 0.0001:
		inc = rad_to_deg(acos(clamp(h3.normalized().dot(body_up), -1.0, 1.0)))

	var inc_text: String = "INC: %.2f°" % inc
	draw_string(
		font,
		Vector2(60.0, rect_size.y - 30.0),
		inc_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		big_font_size - 6,
		text_green
	)
	draw_string(
		font,
		Vector2(60.0, rect_size.y - 60.0),
		r_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		big_font_size - 6,
		text_green
	)
	draw_string(
		font,
		Vector2(60.0, rect_size.y - 90.0),
		vel_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		big_font_size - 6,
		text_green
	)
	draw_circle(ship_screen, 4.0, Color.WHITE)

	var vel_world: Vector3 = SimulationState.ship_vel
	if vel_world.length() > 0.001:
		var vel_tip_world: Vector3 = ship_rel_planet + vel_world.normalized() * (40.0 / pixels_per_unit)
		var vel_tip_screen: Vector2 = _to_screen(vel_tip_world, center)
		var vel_screen_delta: Vector2 = vel_tip_screen - ship_screen

		if vel_screen_delta.length_squared() > 0.0001:
			draw_line(ship_screen, vel_tip_screen, Color.YELLOW, 2.0)

	if ship != null:
		var facing_world: Vector3 = (ship.global_transform.basis.z).normalized()
		var facing_tip_world: Vector3 = ship_rel_planet + facing_world * (30.0 / pixels_per_unit)

		var facing_tip_screen: Vector2 = _to_screen(facing_tip_world, center)
		var facing_screen_delta: Vector2 = facing_tip_screen - ship_screen

		if facing_screen_delta.length_squared() > 0.0001:
			draw_line(ship_screen, facing_tip_screen, Color(0.75, 1.0, 1.0), 2.0)

	if solution.ship_points.size() > 1:
		var ratio: float = clampf(reveal_elapsed / reveal_duration, 0.0, 1.0) if reveal_duration > 0.0 else 1.0
		var visible_count: int = max(2, int(round((solution.ship_points.size() - 1) * ratio)) + 1)
		visible_count = min(visible_count, solution.ship_points.size())

		var ship_pts := PackedVector2Array()
		for i in range(visible_count):
			ship_pts.append(_to_screen(solution.ship_points[i], center))

		var traj_run_points: Array[Vector2] = []
		var traj_run_hidden: bool = false
		var traj_run_color: Color = Color(0.6, 1.0, 0.7)

		for i in range(visible_count - 1):
			var seg_color := Color(0.6, 1.0, 0.7)

			if i < solution.moon_dominance.size() and solution.moon_dominance[i]:
				seg_color = Color(0.65, 0.75, 1.0)

			var mid_3d: Vector3 = (solution.ship_points[i] + solution.ship_points[i + 1]) * 0.5
			var projected_r: float = Vector2(mid_3d.x, mid_3d.z).length()
			var behind_planet: bool = projected_r < SimulationState.planet_radius and mid_3d.y < 0.0

			if traj_run_points.is_empty():
				traj_run_hidden = behind_planet
				traj_run_color = seg_color
				traj_run_points.append(ship_pts[i])
				traj_run_points.append(ship_pts[i + 1])
			elif behind_planet == traj_run_hidden and seg_color == traj_run_color:
				traj_run_points.append(ship_pts[i + 1])
			else:
				if traj_run_hidden:
					_draw_dashed_polyline(traj_run_points, traj_run_color, 2.0, 8, 5, traj_run_points.size())
				else:
					draw_polyline(PackedVector2Array(traj_run_points), traj_run_color, 2.0)

				traj_run_points.clear()
				traj_run_hidden = behind_planet
				traj_run_color = seg_color
				traj_run_points.append(ship_pts[i])
				traj_run_points.append(ship_pts[i + 1])

		if not traj_run_points.is_empty():
			if traj_run_hidden:
				_draw_dashed_polyline(traj_run_points, traj_run_color, 2.0, 8, 5, traj_run_points.size())
			else:
				draw_polyline(PackedVector2Array(traj_run_points), traj_run_color, 2.0)

		if center_mode == CenterMode.MOON:
			var moon_pts := PackedVector2Array()
			var moon_world_pts: Array[Vector3] = []
			var copied_ca_screen: Vector2 = Vector2.ZERO
			var copied_ca_valid: bool = false

			for i in range(visible_count):
				if i >= solution.moon_dominance.size():
					break

				if solution.moon_dominance[i]:
					var rel_to_moon: Vector3 = solution.ship_points[i] - solution.moon_points[i]
					var copied_world: Vector3 = moon_rel_planet + rel_to_moon
					var copied_screen: Vector2 = _to_screen(copied_world, center)

					moon_pts.append(copied_screen)
					moon_world_pts.append(copied_world)

					if i == solution.moon_closest_approach_index:
						copied_ca_screen = copied_screen
						copied_ca_valid = true

			var moon_run_points: Array[Vector2] = []
			for i in range(moon_pts.size() - 1):
				var mid_3d: Vector3 = (moon_world_pts[i] + moon_world_pts[i + 1]) * 0.5
				var projected_r: float = Vector2(mid_3d.x, mid_3d.z).length()
				var behind_planet: bool = projected_r < SimulationState.planet_radius and mid_3d.y < 0.0

				if moon_run_points.is_empty():
					moon_run_points.append(moon_pts[i])
					moon_run_points.append(moon_pts[i + 1])
				elif behind_planet:
					moon_run_points.append(moon_pts[i + 1])
				else:
					if moon_run_points.size() > 1:
						_draw_dashed_polyline(moon_run_points, Color(1.0, 1.0, 1.0), 2.5, 8, 5, moon_run_points.size())
					moon_run_points.clear()

			if moon_run_points.size() > 1:
				_draw_dashed_polyline(moon_run_points, Color(1.0, 1.0, 1.0), 2.5, 8, 5, moon_run_points.size())

			var moon_visible_run: Array[Vector2] = []
			for i in range(moon_pts.size() - 1):
				var mid_3d: Vector3 = (moon_world_pts[i] + moon_world_pts[i + 1]) * 0.5
				var projected_r: float = Vector2(mid_3d.x, mid_3d.z).length()
				var behind_planet: bool = projected_r < SimulationState.planet_radius and mid_3d.y < 0.0

				if behind_planet:
					if moon_visible_run.size() > 1:
						draw_polyline(PackedVector2Array(moon_visible_run), Color(1.0, 1.0, 1.0), 2.5)
					moon_visible_run.clear()
				else:
					if moon_visible_run.is_empty():
						moon_visible_run.append(moon_pts[i])
					moon_visible_run.append(moon_pts[i + 1])

			if moon_visible_run.size() > 1:
				draw_polyline(PackedVector2Array(moon_visible_run), Color(1.0, 1.0, 1.0), 2.5)

			if not is_revealing and copied_ca_valid:
				draw_circle(copied_ca_screen, 4.0, Color(0.892, 1.0, 0.35))
				_draw_marker_label(copied_ca_screen, "PE", Color(0.892, 1.0, 0.35), moon_screen)

		var moon_draw_points: Array[Vector2] = []
		for i in range(visible_count):
			moon_draw_points.append(_to_screen(solution.moon_points[i], center))

		var ghost_alpha: float = 1.0
		if ghost_lifetime_seconds > 0.0:
			ghost_alpha = clampf(1.0 - (ghost_elapsed / ghost_lifetime_seconds), 0.0, 1.0)

		var dash_i: int = 0
		while dash_i < visible_count - 1:
			var dash_end: int = min(dash_i + ghost_dash_length, visible_count - 1)

			for j in range(dash_i, dash_end):
				var col := Color(0.0, 0.0, 0.9, ghost_alpha)
				draw_line(moon_draw_points[j], moon_draw_points[j + 1], col, 2.5)

			dash_i += ghost_dash_length + ghost_gap_length

		if visible_count > 0:
			var moving_moon_dot: Vector2 = moon_draw_points[visible_count - 1]
			draw_circle(moving_moon_dot, 8.0, Color(0.02, 0.02, 0.08, ghost_alpha * 0.9))
			draw_circle(moving_moon_dot, 5.0, Color(0.0, 0.0, 1.0, ghost_alpha))

		if not is_revealing:
			var moon_intercept: bool = false
			for i in range(min(visible_count, solution.moon_dominance.size())):
				if solution.moon_dominance[i]:
					moon_intercept = true
					break

			if moon_intercept and solution.moon_closest_approach_index >= 0 and solution.moon_closest_approach_index < visible_count:
				var ca_screen: Vector2 = ship_pts[solution.moon_closest_approach_index]
				draw_circle(ca_screen, 4.0, Color(1.0, 0.55, 0.15))
				_draw_marker_label(ca_screen, "CA", Color(1.0, 0.55, 0.15), moon_screen)

		if solution.predicted_periapsis_index >= 0 and solution.predicted_periapsis_index < visible_count:
			var pe_screen: Vector2 = ship_pts[solution.predicted_periapsis_index]
			var pe_point: Vector3 = solution.ship_points[solution.predicted_periapsis_index]
			var pe_proj_r: float = Vector2(pe_point.x, pe_point.z).length()
			var pe_hidden: bool = pe_proj_r < SimulationState.planet_radius and pe_point.y < 0.0

			if pe_hidden:
				var pe_dir: Vector2 = pe_screen - planet_screen
				if pe_dir.length_squared() < 0.0001:
					pe_dir = Vector2.RIGHT
				else:
					pe_dir = pe_dir.normalized()

				pe_screen = planet_screen + pe_dir * (planet_radius_px + 8.0)

			_draw_marker_square(pe_screen, 6.0, Color(0.892, 1.0, 0.35, 1.0))
			_draw_marker_label(pe_screen, "PE", Color(0.892, 1.0, 0.35), planet_screen)

		if solution.orbit_classification != "ESCAPE" and solution.orbit_classification != "IMPACT":
			if solution.predicted_apoapsis_index >= 0 and solution.predicted_apoapsis_index < visible_count:
				var ap_screen: Vector2 = ship_pts[solution.predicted_apoapsis_index]
				var ap_point: Vector3 = solution.ship_points[solution.predicted_apoapsis_index]
				var ap_proj_r: float = Vector2(ap_point.x, ap_point.z).length()
				var ap_hidden: bool = ap_proj_r < SimulationState.planet_radius and ap_point.y < 0.0

				if ap_hidden:
					var ap_dir: Vector2 = ap_screen - planet_screen
					if ap_dir.length_squared() < 0.0001:
						ap_dir = Vector2.LEFT
					else:
						ap_dir = ap_dir.normalized()

					ap_screen = planet_screen + ap_dir * (planet_radius_px + 8.0)

				_draw_marker_square(ap_screen, 6.0, Color(0.35, 0.75, 1.0))
				_draw_marker_label(ap_screen, "AP", Color(0.35, 0.75, 1.0), planet_screen)
