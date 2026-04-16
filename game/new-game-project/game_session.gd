extends Node

signal difficulty_changed(difficulty: StringName)
signal mission_reset
signal mission_progress_changed
signal objective_completed(body_name: StringName)

const OrbitSolverModel := preload("res://trajectoryMath/orbit_solver.gd")

const DEFAULT_DIFFICULTY: StringName = &"easy"
const PLANET_DISPLAY_NAME := "Nacre"

const BODY_DISPLAY_NAMES := {
	&"planet": "Nacre",
	&"moon": "Cinder",
	&"moon2": "Veil",
}

const DIFFICULTY_SCENARIOS := {
	&"easy": {
		"label": "Easy",
		"summary": "Coplanar start, wider encounter windows, and the gentlest opening alignment.",
		"ship_start": {
			"position_offset": Vector3(920.0, 0.0, 0.0),
			"velocity": Vector3(0.0, 0.0, 4.18),
		},
		"resources": {
			"starting_fuel": 55.0,
			"max_fuel": 55.0,
			"fuel_burn_per_sim_second": 1.0,
			"starting_oxygen": 1600.0,
			"max_oxygen": 1600.0,
			"oxygen_burn_per_sim_second": 0.03,
			"oxygen_scales_with_timewarp": true,
		},
		"scoring": {
			"fuel_full_score_remaining": 16.0,
			"oxygen_full_score_remaining": 500.0,
			"fuel_weight": 50.0,
			"oxygen_weight": 50.0,
			"three_star_score": 75.0,
			"two_star_score": 40.0,
		},
		"body_overrides": {
			&"moon": {
				"center_distance": 4700.0,
				"phase": 0.45,
				"eccentricity": 0.0,
				"inclination_degrees": 0.0,
				"longitude_of_ascending_node_degrees": 0.0,
				"argument_of_periapsis_degrees": 0.0,
			},
			&"moon2": {
				"center_distance": 7600.0,
				"phase": 2.2,
				"eccentricity": 0.0,
				"inclination_degrees": 0.0,
				"longitude_of_ascending_node_degrees": 0.0,
				"argument_of_periapsis_degrees": 0.0,
			},
		},
		"objectives": [
			{
				"id": "cinder_easy",
				"type": "closest_approach",
				"body_name": &"moon",
				"closest_approach_nu": 120.0,
			},
			{
				"id": "veil_easy",
				"type": "closest_approach",
				"body_name": &"moon2",
				"closest_approach_nu": 180.0,
			},
		],
	},
	&"normal": {
		"label": "Normal",
		"summary": "Less favorable timing, a slightly skewed starting orbit, and tighter encounter windows.",
		"ship_start": {
			"position_offset": Vector3(940.0, 30.0, 0.0),
			"velocity": Vector3(0.0, 0.7, 4.02),
		},
		"resources": {
			"starting_fuel": 100.0,
			"max_fuel": 100.0,
			"fuel_burn_per_sim_second": 0.0,
			"starting_oxygen": 100.0,
			"max_oxygen": 100.0,
			"oxygen_burn_per_sim_second": 0.0,
			"oxygen_scales_with_timewarp": false,
		},
		"body_overrides": {
			&"moon": {
				"center_distance": 5100.0,
				"phase": 1.35,
				"eccentricity": 0.08,
				"inclination_degrees": 9.0,
				"longitude_of_ascending_node_degrees": 24.0,
				"argument_of_periapsis_degrees": 38.0,
			},
			&"moon2": {
				"center_distance": 8250.0,
				"phase": 4.05,
				"eccentricity": 0.12,
				"inclination_degrees": 14.0,
				"longitude_of_ascending_node_degrees": 138.0,
				"argument_of_periapsis_degrees": 62.0,
			},
		},
		"objectives": [
			{
				"id": "cinder_normal",
				"type": "captured_orbit",
				"body_name": &"moon",
				"hold_seconds": 10.0,
				"periapsis_min_nu": 18.0,
			},
			{
				"id": "veil_normal",
				"type": "closest_approach",
				"body_name": &"moon2",
				"closest_approach_nu": 95.0,
			},
		],
	},
	&"hard": {
		"label": "Hard",
		"summary": "The roughest available opening alignment, strongest plane mismatch, and narrow encounter windows.",
		"ship_start": {
			"position_offset": Vector3(980.0, 70.0, 0.0),
			"velocity": Vector3(0.0, 1.1, 3.92),
		},
		"resources": {
			"starting_fuel": 100.0,
			"max_fuel": 100.0,
			"fuel_burn_per_sim_second": 0.0,
			"starting_oxygen": 100.0,
			"max_oxygen": 100.0,
			"oxygen_burn_per_sim_second": 0.0,
			"oxygen_scales_with_timewarp": false,
		},
		"body_overrides": {
			&"moon": {
				"center_distance": 5550.0,
				"phase": 2.5,
				"eccentricity": 0.18,
				"inclination_degrees": 18.0,
				"longitude_of_ascending_node_degrees": 52.0,
				"argument_of_periapsis_degrees": 94.0,
			},
			&"moon2": {
				"center_distance": 9000.0,
				"phase": 5.05,
				"eccentricity": 0.22,
				"inclination_degrees": 27.0,
				"longitude_of_ascending_node_degrees": 168.0,
				"argument_of_periapsis_degrees": 134.0,
			},
		},
		"objectives": [
			{
				"id": "cinder_hard",
				"type": "low_orbit",
				"body_name": &"moon",
				"apoapsis_max_nu": 160.0,
				"periapsis_min_nu": 18.0,
				"hold_seconds": 10.0,
			},
			{
				"id": "veil_hard",
				"type": "low_orbit",
				"body_name": &"moon2",
				"apoapsis_max_nu": 120.0,
				"periapsis_min_nu": 14.0,
				"hold_seconds": 10.0,
			},
			{
				"id": "veil_hard_plane",
				"type": "inclination_limit",
				"body_name": &"moon2",
				"inclination_max_degrees": 12.0,
				"hold_seconds": 8.0,
				"require_dominance": true,
			},
		],
	},
}

var selected_difficulty: StringName = DEFAULT_DIFFICULTY
var mission_active: bool = false
var mission_objectives: Array[Dictionary] = []
var _orbit_solver := OrbitSolverModel.new()


func _ready() -> void:
	selected_difficulty = _normalize_difficulty(selected_difficulty)
	reset_mission_state()


func set_selected_difficulty(value: StringName) -> void:
	var normalized: StringName = _normalize_difficulty(value)
	if selected_difficulty == normalized:
		return
	selected_difficulty = normalized
	difficulty_changed.emit(selected_difficulty)


func get_selected_difficulty() -> StringName:
	return selected_difficulty


func get_active_scenario() -> Dictionary:
	return (DIFFICULTY_SCENARIOS.get(selected_difficulty, DIFFICULTY_SCENARIOS[DEFAULT_DIFFICULTY]) as Dictionary).duplicate(true)


func get_planet_display_name() -> String:
	return PLANET_DISPLAY_NAME


func get_body_display_name(body_name: StringName) -> String:
	return str(BODY_DISPLAY_NAMES.get(body_name, String(body_name).capitalize()))


func get_active_resource_settings() -> Dictionary:
	var scenario: Dictionary = get_active_scenario()
	return (scenario.get("resources", {}) as Dictionary).duplicate(true)


func get_active_scoring_settings() -> Dictionary:
	var scenario: Dictionary = get_active_scenario()
	return (scenario.get("scoring", {}) as Dictionary).duplicate(true)


func get_difficulty_label() -> String:
	var scenario: Dictionary = get_active_scenario()
	return str(scenario.get("label", "Easy"))


func begin_run() -> void:
	mission_active = true
	reset_mission_state()


func reset_mission_state() -> void:
	mission_objectives.clear()

	var scenario: Dictionary = get_active_scenario()
	var scenario_objectives: Array = scenario.get("objectives", [])
	for objective_variant in scenario_objectives:
		var objective: Dictionary = (objective_variant as Dictionary).duplicate(true)
		objective["type"] = str(objective.get("type", "closest_approach"))
		objective["display_name"] = get_body_display_name(objective.get("body_name", &""))
		objective["completed"] = false
		objective["best_altitude"] = INF
		objective["hold_elapsed"] = 0.0
		mission_objectives.append(objective)

	mission_reset.emit()
	mission_progress_changed.emit()


func get_current_objectives() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for objective in mission_objectives:
		result.append(objective.duplicate(true))
	return result


func register_closest_approach_sample(body_name: StringName, altitude: float) -> void:
	if not mission_active:
		return

	var clamped_altitude: float = maxf(altitude, 0.0)
	var changed: bool = false

	for index in range(mission_objectives.size()):
		var objective: Dictionary = mission_objectives[index]
		if objective.get("body_name", &"") != body_name:
			continue

		var best_altitude: float = float(objective.get("best_altitude", INF))
		if clamped_altitude < best_altitude:
			objective["best_altitude"] = clamped_altitude
			best_altitude = clamped_altitude
			changed = true

		var target_altitude: float = _get_objective_distance_value(objective, "closest_approach")
		if (
			str(objective.get("type", "closest_approach")) == "closest_approach"
			and not bool(objective.get("completed", false))
			and best_altitude <= target_altitude
		):
			objective["completed"] = true
			mission_objectives[index] = objective
			objective_completed.emit(body_name)
			changed = true
		else:
			mission_objectives[index] = objective

	if changed:
		mission_progress_changed.emit()


func update_live_objectives(delta: float) -> void:
	if not mission_active:
		return

	var changed: bool = false
	var completed_any: bool = false

	for index in range(mission_objectives.size()):
		var objective: Dictionary = mission_objectives[index]
		if bool(objective.get("completed", false)):
			continue

		var objective_type: String = str(objective.get("type", "closest_approach"))
		if objective_type == "closest_approach":
			continue

		var body_name: StringName = objective.get("body_name", &"")
		if body_name == &"" or not SimulationState.has_body(body_name):
			continue

		var condition_met: bool = false
		match objective_type:
			"captured_orbit":
				condition_met = _is_capture_condition_met(objective)
			"low_orbit":
				condition_met = _is_low_orbit_condition_met(objective)
			"inclination_limit":
				condition_met = _is_inclination_limit_condition_met(objective)

		var required_hold: float = maxf(float(objective.get("hold_seconds", 0.0)), 0.0)
		if condition_met:
			if required_hold > 0.0:
				objective["hold_elapsed"] = minf(float(objective.get("hold_elapsed", 0.0)) + delta, required_hold)
			if required_hold <= 0.0 or float(objective.get("hold_elapsed", 0.0)) >= required_hold - 0.0001:
				objective["completed"] = true
				objective["hold_elapsed"] = required_hold
				objective_completed.emit(body_name)
				completed_any = true
				changed = true
		elif float(objective.get("hold_elapsed", 0.0)) > 0.0:
			objective["hold_elapsed"] = 0.0

		mission_objectives[index] = objective

	if changed or completed_any:
		mission_progress_changed.emit()


func get_objective_title(objective: Dictionary) -> String:
	var body_display_name: String = str(objective.get("display_name", objective.get("body_name", &"")))
	match str(objective.get("type", "closest_approach")):
		"captured_orbit":
			return "%s - captured orbit" % body_display_name.to_upper()
		"low_orbit":
			return "%s - low orbit, AP %d NU" % [
				body_display_name.to_upper(),
				int(round(_get_objective_distance_value(objective, "apoapsis_max")))
			]
		"inclination_limit":
			return "%s - inclination below %.0f°" % [
				body_display_name.to_upper(),
				float(objective.get("inclination_max_degrees", 0.0))
			]
	return "%s - closest approach %d NU" % [
		body_display_name.to_upper(),
		int(round(_get_objective_distance_value(objective, "closest_approach")))
	]


func _is_capture_condition_met(objective: Dictionary) -> bool:
	var orbit: Dictionary = _get_body_local_orbit_solution(objective.get("body_name", &""))
	if orbit.is_empty():
		return false

	var periapsis_altitude: float = float(orbit.get("periapsis_altitude", -1.0))
	var required_periapsis: float = _get_objective_distance_value(objective, "periapsis_min", 0.0)
	return (
		bool(orbit.get("is_bound_orbit", false))
		and str(orbit.get("orbit_classification", "")) != "IMPACT"
		and float(orbit.get("apoapsis_distance", -1.0)) > 0.0
		and periapsis_altitude >= required_periapsis
	)


func _is_low_orbit_condition_met(objective: Dictionary) -> bool:
	var orbit: Dictionary = _get_body_local_orbit_solution(objective.get("body_name", &""))
	if orbit.is_empty():
		return false

	var apoapsis_altitude: float = float(orbit.get("apoapsis_altitude", INF))
	var periapsis_altitude: float = float(orbit.get("periapsis_altitude", -1.0))
	return (
		bool(orbit.get("is_bound_orbit", false))
		and str(orbit.get("orbit_classification", "")) != "IMPACT"
		and float(orbit.get("apoapsis_distance", -1.0)) > 0.0
		and apoapsis_altitude <= _get_objective_distance_value(objective, "apoapsis_max", INF)
		and periapsis_altitude >= _get_objective_distance_value(objective, "periapsis_min", 0.0)
	)


func _is_inclination_limit_condition_met(objective: Dictionary) -> bool:
	var body_name: StringName = objective.get("body_name", &"")
	if body_name == &"":
		return false
	if bool(objective.get("require_dominance", false)) and not SimulationState.is_body_dominant_at(body_name, SimulationState.ship_pos):
		return false

	var inclination_degrees: float = _get_inclination_relative_to_body_plane_degrees(body_name)
	if inclination_degrees < 0.0:
		return false
	return inclination_degrees <= float(objective.get("inclination_max_degrees", INF))


func _get_objective_distance_value(objective: Dictionary, key_stem: String, default_value: float = INF) -> float:
	var nu_key: String = "%s_nu" % key_stem
	if objective.has(nu_key):
		return float(objective.get(nu_key, default_value))

	# Backward compatibility with older mission dictionaries that still use
	# the old mislabeled *_km keys.
	var legacy_key: String = "%s_km" % key_stem
	return float(objective.get(legacy_key, default_value))


func _get_body_local_orbit_solution(body_name: StringName) -> Dictionary:
	if body_name == &"" or not SimulationState.has_body(body_name):
		return {}
	if not SimulationState.is_body_dominant_at(body_name, SimulationState.ship_pos):
		return {}

	var body_pos: Vector3 = SimulationState.get_body_position(body_name)
	var body_vel: Vector3 = SimulationState.get_body_velocity(body_name)
	var rel_pos: Vector3 = SimulationState.ship_pos - body_pos
	var rel_vel: Vector3 = SimulationState.ship_vel - body_vel
	var body_radius: float = SimulationState.get_body_radius(body_name)
	var orbit: Dictionary = _orbit_solver.solve_relative_orbit(rel_pos, rel_vel, SimulationState.get_body_mu(body_name), body_radius)
	orbit["periapsis_altitude"] = float(orbit.get("periapsis_distance", -1.0)) - body_radius
	orbit["apoapsis_altitude"] = float(orbit.get("apoapsis_distance", -1.0)) - body_radius
	return orbit


func _get_inclination_relative_to_body_plane_degrees(body_name: StringName) -> float:
	if body_name == &"" or not SimulationState.has_body(body_name):
		return -1.0

	var parent_body_name: StringName = SimulationState.get_body_parent(body_name)
	if parent_body_name == &"":
		var body_up: Vector3 = SimulationState.get_body_up(body_name)
		return _get_inclination_relative_to_plane_normal(body_up, SimulationState.ship_pos, SimulationState.ship_vel, SimulationState.get_body_position(body_name), SimulationState.get_body_velocity(body_name))

	var parent_pos: Vector3 = SimulationState.get_body_position(parent_body_name)
	var parent_vel: Vector3 = SimulationState.get_body_velocity(parent_body_name)
	var body_rel_pos: Vector3 = SimulationState.get_body_position(body_name) - parent_pos
	var body_rel_vel: Vector3 = SimulationState.get_body_velocity(body_name) - parent_vel
	var plane_normal: Vector3 = body_rel_pos.cross(body_rel_vel)
	if plane_normal.length_squared() <= 0.0001:
		plane_normal = SimulationState.get_body_up(body_name)
	return _get_inclination_relative_to_plane_normal(plane_normal, SimulationState.ship_pos, SimulationState.ship_vel, parent_pos, parent_vel)


func _get_inclination_relative_to_plane_normal(
	plane_normal: Vector3,
	ship_position: Vector3,
	ship_velocity: Vector3,
	frame_origin_position: Vector3,
	frame_origin_velocity: Vector3
) -> float:
	if plane_normal.length_squared() <= 0.0001:
		return -1.0

	var rel_pos: Vector3 = ship_position - frame_origin_position
	var rel_vel: Vector3 = ship_velocity - frame_origin_velocity
	var ship_plane_normal: Vector3 = rel_vel.cross(rel_pos)
	if ship_plane_normal.length_squared() <= 0.0001:
		return -1.0

	var dot_value: float = clampf(ship_plane_normal.normalized().dot(plane_normal.normalized()), -1.0, 1.0)
	return rad_to_deg(acos(abs(dot_value)))


func are_all_objectives_complete() -> bool:
	if mission_objectives.is_empty():
		return false

	for objective in mission_objectives:
		if not bool(objective.get("completed", false)):
			return false
	return true


func _normalize_difficulty(value: StringName) -> StringName:
	if DIFFICULTY_SCENARIOS.has(value):
		return value
	return DEFAULT_DIFFICULTY
