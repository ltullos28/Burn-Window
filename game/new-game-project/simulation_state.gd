extends Node

signal ship_impacted(body_name: StringName)

const CelestialBodyDefinitionModel := preload("res://celestial_body_definition.gd")
const CelestialSystemDefinitionModel := preload("res://celestial_system_definition.gd")
const LEGACY_PRIMARY_BODY_NAME := &"planet"
const LEGACY_FOCUSED_CHILD_BODY_NAME := &"moon"
const DEFAULT_CELESTIAL_SYSTEM_DEFINITION_PATH := "res://data/default_celestial_system.tres"

@export var min_gravity_distance: float = 5.0
var body_definitions: Array[CelestialBodyDefinition] = []
var celestial_system_definition: CelestialSystemDefinition = null

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
@export var targeted_warp_scale: float = 20.0
@export var targeted_warp_short_threshold_seconds: float = 600.0
@export var targeted_warp_short_duration_seconds: float = 2.0
@export var targeted_warp_long_duration_seconds: float = 4.5
@export var planet_up: Vector3 = Vector3.UP
@export var moon_up: Vector3 = Vector3.UP

var bodies: Dictionary = {}

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
var trajectory_prediction_stale: bool = false

var targeted_warp_active: bool = false
var targeted_warp_target_sim_time: float = -1.0
var targeted_warp_previous_time_scale: float = 1.0
var targeted_warp_snap_ship_pos: Vector3 = Vector3.ZERO
var targeted_warp_snap_ship_vel: Vector3 = Vector3.ZERO
var targeted_warp_has_snap_state: bool = false
var targeted_warp_real_duration_seconds: float = 0.0
var targeted_warp_path_positions: Array[Vector3] = []
var targeted_warp_path_velocities: Array[Vector3] = []
var targeted_warp_path_step_seconds: float = 0.0
var targeted_warp_path_start_sim_time: float = -1.0
var impact_recovery_active: bool = false

var _prepared_physics_frame: int = -1
var _current_sim_delta: float = 0.0

# Temporary Warp
var warp_levels := [1.0, 2.0, 5.0, 10.0, 20.0, 50.0, 100.0]
var warp_index := 0

func _ready() -> void:
	_load_celestial_system_definition()
	_recompute_body_constants()
	reset()

func _physics_process(delta: float) -> void:
	if impact_recovery_active:
		return

	var sim_delta: float = get_current_sim_delta(delta)
	sim_time += sim_delta
	_update_rail_body_states()
	_apply_targeted_warp_path_state()

	if targeted_warp_active and sim_time >= targeted_warp_target_sim_time - 0.0001:
		sim_time = targeted_warp_target_sim_time
		_update_rail_body_states()
		_apply_targeted_warp_path_state()
		_finish_targeted_warp(true)

	var impacted_body: StringName = get_first_body_surface_contact(ship_pos)
	if impacted_body != &"":
		_begin_ship_impact_recovery(impacted_body)

func get_current_sim_delta(raw_delta: float) -> float:
	var frame: int = Engine.get_physics_frames()
	if frame != _prepared_physics_frame:
		_prepared_physics_frame = frame
		_current_sim_delta = raw_delta * celestial_time_scale

		if targeted_warp_active:
			var remaining: float = max(0.0, targeted_warp_target_sim_time - sim_time)
			_current_sim_delta = min(_current_sim_delta, remaining)

	return _current_sim_delta

func _recompute_body_constants() -> void:
	planet_mu = planet_surface_gravity * planet_radius * planet_radius
	moon_mu = moon_surface_gravity * moon_radius * moon_radius

	moon_orbit_radius = moon_center_distance_from_planet
	moon_orbit_speed = _compute_circular_orbit_angular_speed(planet_mu, moon_orbit_radius)
	moon_orbit_linear_speed = _compute_circular_orbit_linear_speed(planet_mu, moon_orbit_radius)

	_rebuild_body_registry()

func reset() -> void:
	cancel_targeted_warp()
	clear_trajectory_prediction_stale()
	impact_recovery_active = false

	sim_time = 0.0
	_apply_session_scenario()
	_rebuild_body_registry()
	_reset_non_rail_body_states()

	var ship_start: Dictionary = _get_session_ship_start_state()
	var ship_position_offset: Vector3 = ship_start.get("position_offset", Vector3(900.0, 0.0, 0.0))
	var ship_velocity: Vector3 = ship_start.get("velocity", Vector3(0.0, 0.0, 4.216))
	ship_pos = planet_pos + ship_position_offset
	ship_vel = ship_velocity
	_update_rail_body_states()

func get_first_body_surface_contact(position: Vector3) -> StringName:
	for body_name in get_body_names():
		var body_pos: Vector3 = get_body_position(body_name)
		var body_radius: float = get_body_radius(body_name)
		if body_radius <= 0.0:
			continue
		if position.distance_to(body_pos) <= body_radius:
			return body_name
	return &""

func _begin_ship_impact_recovery(body_name: StringName) -> void:
	if impact_recovery_active:
		return
	impact_recovery_active = true
	cancel_targeted_warp()
	celestial_time_scale = 1.0
	emit_signal("ship_impacted", body_name)

func is_impact_recovery_active() -> bool:
	return impact_recovery_active

func finish_impact_recovery_reset() -> void:
	reset()

func _update_rail_body_states() -> void:
	var rail_body_names: Array[StringName] = []
	for body_name in get_body_names():
		if is_body_on_rails(body_name):
			rail_body_names.append(body_name)

	rail_body_names.sort_custom(func(a: StringName, b: StringName) -> bool:
		return _get_body_depth(a) < _get_body_depth(b)
	)

	for body_name in rail_body_names:
		var state: Dictionary = get_body_state_at_time(body_name, sim_time)
		_set_body_state_raw(body_name, state.get("pos", Vector3.ZERO), state.get("vel", Vector3.ZERO))

	_sync_legacy_body_fields_from_registry()

func gravity_accel_at(position: Vector3) -> Vector3:
	var total := Vector3.ZERO
	for body_name in bodies.keys():
		var body_pos: Vector3 = get_body_position(StringName(body_name))
		var body_mu: float = get_body_mu(StringName(body_name))
		total += _gravity_from_body(position, body_pos, body_mu)
	return total

func is_moon_dominant_at(position: Vector3) -> bool:
	var to_planet: Vector3 = get_body_position(&"planet") - position
	var to_moon: Vector3 = get_body_position(&"moon") - position

	var d_planet: float = max(to_planet.length(), 0.001)
	var d_moon: float = max(to_moon.length(), 0.001)

	var g_planet: float = get_body_mu(&"planet") / (d_planet * d_planet)
	var g_moon: float = get_body_mu(&"moon") / (d_moon * d_moon)

	return g_moon > g_planet

func is_ship_in_moon_dominance() -> bool:
	return is_moon_dominant_at(ship_pos)

func is_body_dominant_at(body_name: StringName, position: Vector3) -> bool:
	return get_dominant_body_name_at(position) == body_name

func is_ship_in_body_dominance(body_name: StringName) -> bool:
	return is_body_dominant_at(body_name, ship_pos)

func has_body(body_name: StringName) -> bool:
	return bodies.has(_get_body_key(body_name))

func get_body_record(body_name: StringName) -> Dictionary:
	var body_key: String = _get_body_key(body_name)
	if not bodies.has(body_key):
		return {}
	return bodies[body_key]

func get_body_position(body_name: StringName) -> Vector3:
	var body: Dictionary = get_body_record(body_name)
	if body.has("pos"):
		return body["pos"]
	return Vector3.ZERO

func get_body_velocity(body_name: StringName) -> Vector3:
	var body: Dictionary = get_body_record(body_name)
	if body.has("vel"):
		return body["vel"]
	return Vector3.ZERO

func get_body_radius(body_name: StringName) -> float:
	var body: Dictionary = get_body_record(body_name)
	if body.has("radius"):
		return body["radius"]
	return 0.0

func get_body_surface_gravity(body_name: StringName) -> float:
	var body: Dictionary = get_body_record(body_name)
	if body.has("surface_gravity"):
		return body["surface_gravity"]
	return 0.0

func get_body_mu(body_name: StringName) -> float:
	var body: Dictionary = get_body_record(body_name)
	if body.has("mu"):
		return body["mu"]
	return 0.0

func get_body_up(body_name: StringName) -> Vector3:
	var body: Dictionary = get_body_record(body_name)
	if body.has("up"):
		var up: Vector3 = body["up"]
		if up.length_squared() > 0.0001:
			return up.normalized()
	return Vector3.UP

func get_body_parent(body_name: StringName) -> StringName:
	var body: Dictionary = get_body_record(body_name)
	if body.has("parent_body"):
		return body["parent_body"]
	return &""

func get_body_orbit_params(body_name: StringName) -> Dictionary:
	var body: Dictionary = get_body_record(body_name)
	if body.has("orbit"):
		return body["orbit"]
	return {}

func is_body_on_rails(body_name: StringName) -> bool:
	var body: Dictionary = get_body_record(body_name)
	if body.is_empty():
		return false
	var parent_body_name: StringName = body.get("parent_body", &"")
	return parent_body_name != &"" and not get_body_orbit_params(body_name).is_empty()

func get_body_state_at_time(body_name: StringName, query_time: float) -> Dictionary:
	var body: Dictionary = get_body_record(body_name)
	if body.is_empty():
		return {}

	if not is_body_on_rails(body_name):
		return {
			"pos": body.get("pos", Vector3.ZERO),
			"vel": body.get("vel", Vector3.ZERO)
		}

	var orbit: Dictionary = get_body_orbit_params(body_name)
	var parent_body_name: StringName = body.get("parent_body", &"")
	return _get_orbit_state_at_time(parent_body_name, orbit, query_time)

func get_body_names() -> Array[StringName]:
	var result: Array[StringName] = []
	for body_key in bodies.keys():
		result.append(StringName(body_key))
	return result

func get_body_definition(body_name: StringName) -> CelestialBodyDefinition:
	var body_key: String = _get_body_key(body_name)
	for definition in _get_active_body_definitions():
		if definition == null or not definition.enabled:
			continue
		if _get_body_key(definition.body_name) == body_key:
			return definition
	return null

func get_active_body_definitions() -> Array[CelestialBodyDefinition]:
	return _get_active_body_definitions()

func get_child_body_names(parent_body_name: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	for body_name in get_body_names():
		if get_body_parent(body_name) == parent_body_name:
			result.append(body_name)
	result.sort_custom(func(a: StringName, b: StringName) -> bool:
		return String(a) < String(b)
	)
	return result

func set_body_state(body_name: StringName, position: Vector3, velocity: Vector3) -> void:
	_set_body_state_raw(body_name, position, velocity)
	_sync_legacy_body_fields_from_registry()

func _set_body_state_raw(body_name: StringName, position: Vector3, velocity: Vector3) -> void:
	var body_key: String = _get_body_key(body_name)
	if not bodies.has(body_key):
		return

	var body: Dictionary = bodies[body_key]
	body["pos"] = position
	body["vel"] = velocity
	bodies[body_key] = body

func get_ship_reference_body_pos() -> Vector3:
	return get_body_position(get_ship_reference_body_name())

func get_ship_reference_body_vel() -> Vector3:
	return get_body_velocity(get_ship_reference_body_name())

func get_ship_reference_body_up() -> Vector3:
	return get_body_up(get_ship_reference_body_name())

func get_dominant_body_name_at(position: Vector3) -> StringName:
	var best_body_name: StringName = &""
	var best_gravity: float = -INF

	for body_name in get_body_names():
		var body_pos: Vector3 = get_body_position(body_name)
		var body_mu: float = get_body_mu(body_name)
		if body_mu <= 0.0:
			continue

		var distance: float = max((body_pos - position).length(), 0.001)
		var gravity: float = body_mu / (distance * distance)
		if gravity > best_gravity:
			best_gravity = gravity
			best_body_name = body_name

	return best_body_name

func get_ship_reference_body_name() -> StringName:
	return get_dominant_body_name_at(ship_pos)

func mark_trajectory_prediction_stale() -> void:
	trajectory_prediction_stale = true

func clear_trajectory_prediction_stale() -> void:
	trajectory_prediction_stale = false

func is_trajectory_prediction_stale() -> bool:
	return trajectory_prediction_stale

func _gravity_from_body(position: Vector3, body_pos: Vector3, mu: float) -> Vector3:
	var offset: Vector3 = body_pos - position
	var distance: float = offset.length()

	if distance < min_gravity_distance:
		distance = min_gravity_distance

	return offset * mu / pow(distance, 3.0)

func _get_body_key(body_name: StringName) -> String:
	return String(body_name).strip_edges().to_lower()

func _compute_circular_orbit_angular_speed(parent_mu: float, center_distance: float) -> float:
	if parent_mu <= 0.0 or center_distance <= 0.0:
		return 0.0
	return sqrt(parent_mu / pow(center_distance, 3.0))

func _compute_circular_orbit_linear_speed(parent_mu: float, center_distance: float) -> float:
	if parent_mu <= 0.0 or center_distance <= 0.0:
		return 0.0
	return sqrt(parent_mu / center_distance)

func get_orbital_plane_normal_from_relative_state(relative_pos: Vector3, relative_vel: Vector3) -> Vector3:
	if relative_pos.length_squared() <= 0.0001 or relative_vel.length_squared() <= 0.0001:
		return Vector3.ZERO
	var angular_momentum: Vector3 = relative_pos.cross(relative_vel)
	if angular_momentum.length_squared() <= 0.0001:
		return Vector3.ZERO
	return angular_momentum.normalized()

func get_orbital_plane_normal_from_state(
	body_pos: Vector3,
	body_vel: Vector3,
	frame_origin_pos: Vector3,
	frame_origin_vel: Vector3
) -> Vector3:
	return get_orbital_plane_normal_from_relative_state(
		body_pos - frame_origin_pos,
		body_vel - frame_origin_vel
	)

func build_orbit_basis_from_elements(
	ascending_node_radians: float,
	inclination_radians: float,
	argument_of_periapsis_radians: float
) -> Basis:
	var q_lan := Quaternion(Vector3.UP, ascending_node_radians)
	var node_axis: Vector3 = q_lan * Vector3.RIGHT
	if node_axis.length_squared() <= 0.000001:
		node_axis = Vector3.RIGHT
	else:
		node_axis = node_axis.normalized()

	var q_inc := Quaternion(node_axis, inclination_radians)
	# Our perifocal position/velocity basis lies in the XZ plane, so the
	# physically correct instantaneous plane normal under r x v points along
	# local DOWN rather than UP.
	var local_plane_normal: Vector3 = Vector3.DOWN
	var plane_normal: Vector3 = (q_inc * q_lan) * local_plane_normal
	if plane_normal.length_squared() <= 0.000001:
		plane_normal = local_plane_normal
	else:
		plane_normal = plane_normal.normalized()

	var q_arg := Quaternion(plane_normal, argument_of_periapsis_radians)
	return Basis(q_arg * q_inc * q_lan)

func get_orbit_plane_normal_from_elements(orbit: Dictionary) -> Vector3:
	if orbit.is_empty():
		return Vector3.ZERO
	var orbit_basis: Basis = build_orbit_basis_from_elements(
		float(orbit.get("ascending_node_radians", 0.0)),
		float(orbit.get("inclination_radians", 0.0)),
		float(orbit.get("argument_of_periapsis_radians", 0.0))
	)
	var plane_normal: Vector3 = orbit_basis * Vector3.DOWN
	if plane_normal.length_squared() <= 0.000001:
		return Vector3.ZERO
	return plane_normal.normalized()

func _get_orbit_state_at_time(parent_body_name: StringName, orbit: Dictionary, query_time: float) -> Dictionary:
	var parent_state: Dictionary = get_body_state_at_time(parent_body_name, query_time)
	var parent_pos: Vector3 = parent_state.get("pos", Vector3.ZERO)
	var parent_vel: Vector3 = parent_state.get("vel", Vector3.ZERO)

	var semi_major_axis: float = float(orbit.get("semi_major_axis", orbit.get("center_distance", 0.0)))
	var phase: float = float(orbit.get("phase", 0.0))
	var angular_speed: float = float(orbit.get("angular_speed", 0.0))
	var eccentricity: float = clampf(float(orbit.get("eccentricity", 0.0)), 0.0, 0.8)
	var inclination_radians: float = float(orbit.get("inclination_radians", 0.0))
	var ascending_node_radians: float = float(orbit.get("ascending_node_radians", 0.0))
	var argument_of_periapsis_radians: float = float(orbit.get("argument_of_periapsis_radians", 0.0))
	var mean_anomaly: float = phase + query_time * angular_speed
	var eccentric_anomaly: float = _solve_kepler_equation(mean_anomaly, eccentricity)
	var sqrt_term: float = sqrt(maxf(1.0 - eccentricity * eccentricity, 0.000001))
	var cos_e: float = cos(eccentric_anomaly)
	var sin_e: float = sin(eccentric_anomaly)
	var radius: float = maxf(semi_major_axis * (1.0 - eccentricity * cos_e), 0.001)

	var perifocal_position := Vector3(
		semi_major_axis * (cos_e - eccentricity),
		0.0,
		semi_major_axis * sqrt_term * sin_e
	)

	var parent_mu: float = get_body_mu(parent_body_name)
	var speed_scale: float = sqrt(maxf(parent_mu * semi_major_axis, 0.0)) / radius if parent_mu > 0.0 and semi_major_axis > 0.0 else float(orbit.get("linear_speed", 0.0))
	var perifocal_velocity := Vector3(
		-sin_e * speed_scale,
		0.0,
		sqrt_term * cos_e * speed_scale
	)

	# Build orbital orientation with the same r x v plane-normal convention that
	# the runtime EQUATOR instrument uses for instantaneous motion planes.
	var orbit_basis: Basis = build_orbit_basis_from_elements(
		ascending_node_radians,
		inclination_radians,
		argument_of_periapsis_radians
	)

	var local_offset: Vector3 = orbit_basis * perifocal_position
	var tangent: Vector3 = orbit_basis * perifocal_velocity

	return {
		"pos": parent_pos + local_offset,
		"vel": parent_vel + tangent
	}

func _build_circular_orbit_params_from_definition(definition: CelestialBodyDefinition) -> Dictionary:
	var parent_mu: float = get_body_mu(definition.parent_body_name)
	if parent_mu <= 0.0 and definition.parent_body_name == LEGACY_PRIMARY_BODY_NAME:
		parent_mu = planet_surface_gravity * planet_radius * planet_radius

	# Rail bodies should follow physically consistent conics around their parent.
	# We therefore derive mean motion from the parent body's mu and the orbit's
	# semi-major axis instead of trusting legacy speed overrides baked into data.
	var angular_speed: float = _compute_circular_orbit_angular_speed(parent_mu, definition.center_distance)
	var linear_speed: float = _compute_circular_orbit_linear_speed(parent_mu, definition.center_distance)

	return {
		"center_distance": definition.center_distance,
		"semi_major_axis": definition.center_distance,
		"phase": definition.phase,
		"angular_speed": angular_speed,
		"linear_speed": linear_speed,
		"eccentricity": clampf(definition.eccentricity, 0.0, 0.8),
		"inclination_radians": deg_to_rad(definition.inclination_degrees),
		"ascending_node_radians": deg_to_rad(definition.longitude_of_ascending_node_degrees),
		"argument_of_periapsis_radians": deg_to_rad(definition.argument_of_periapsis_degrees),
	}

func _solve_kepler_equation(mean_anomaly: float, eccentricity: float) -> float:
	var wrapped_mean_anomaly: float = wrapf(mean_anomaly, -PI, PI)
	if eccentricity <= 0.0001:
		return wrapped_mean_anomaly

	var eccentric_anomaly: float = wrapped_mean_anomaly
	for _i in range(8):
		var f: float = eccentric_anomaly - eccentricity * sin(eccentric_anomaly) - wrapped_mean_anomaly
		var derivative: float = 1.0 - eccentricity * cos(eccentric_anomaly)
		if absf(derivative) <= 0.000001:
			break
		eccentric_anomaly -= f / derivative
	return eccentric_anomaly

func _register_body(
	body_name: StringName,
	radius: float,
	surface_gravity: float,
	position: Vector3,
	velocity: Vector3,
	up: Vector3,
	parent_body_name: StringName = &"",
	orbit: Dictionary = {}
) -> void:
	bodies[_get_body_key(body_name)] = {
		"name": body_name,
		"radius": radius,
		"surface_gravity": surface_gravity,
		"mu": surface_gravity * radius * radius,
		"pos": position,
		"vel": velocity,
		"up": up,
		"parent_body": parent_body_name,
		"orbit": orbit.duplicate(true)
	}

func _register_body_from_definition(definition: CelestialBodyDefinition, query_time: float = 0.0) -> void:
	var orbit: Dictionary = {}
	var position: Vector3 = definition.initial_position
	var velocity: Vector3 = definition.initial_velocity

	if definition.orbit_mode == CelestialBodyDefinition.OrbitMode.CIRCULAR and definition.parent_body_name != &"":
		orbit = _build_circular_orbit_params_from_definition(definition)
		var orbit_state: Dictionary = _get_orbit_state_at_time(definition.parent_body_name, orbit, query_time)
		position = orbit_state.get("pos", position)
		velocity = orbit_state.get("vel", velocity)

	_register_body(
		definition.body_name,
		definition.radius,
		definition.surface_gravity,
		position,
		velocity,
		definition.up,
		definition.parent_body_name,
		orbit
	)

func _get_body_depth(body_name: StringName) -> int:
	var depth: int = 0
	var current: StringName = get_body_parent(body_name)
	while current != &"" and depth < 16:
		depth += 1
		current = get_body_parent(current)
	return depth

func _build_legacy_primary_body_definition() -> CelestialBodyDefinition:
	var definition := CelestialBodyDefinitionModel.new()
	definition.body_name = LEGACY_PRIMARY_BODY_NAME
	definition.radius = planet_radius
	definition.surface_gravity = planet_surface_gravity
	definition.up = planet_up
	definition.orbit_mode = CelestialBodyDefinition.OrbitMode.STATIC
	definition.initial_position = planet_pos
	definition.initial_velocity = planet_vel
	return definition

func _build_legacy_focused_child_body_definition() -> CelestialBodyDefinition:
	var definition := CelestialBodyDefinitionModel.new()
	definition.body_name = LEGACY_FOCUSED_CHILD_BODY_NAME
	definition.radius = moon_radius
	definition.surface_gravity = moon_surface_gravity
	definition.up = moon_up
	definition.parent_body_name = LEGACY_PRIMARY_BODY_NAME
	definition.orbit_mode = CelestialBodyDefinition.OrbitMode.CIRCULAR
	definition.center_distance = moon_center_distance_from_planet
	definition.phase = moon_orbit_phase
	definition.angular_speed_override = moon_orbit_speed
	definition.linear_speed_override = moon_orbit_linear_speed
	return definition

func _load_celestial_system_definition() -> void:
	celestial_system_definition = null
	body_definitions.clear()

	var loaded_resource: Resource = load(DEFAULT_CELESTIAL_SYSTEM_DEFINITION_PATH)
	if loaded_resource == null:
		return
	if not (loaded_resource is CelestialSystemDefinition):
		push_warning("Celestial system definition at %s is not a CelestialSystemDefinition resource." % DEFAULT_CELESTIAL_SYSTEM_DEFINITION_PATH)
		return

	celestial_system_definition = loaded_resource as CelestialSystemDefinition
	for definition in celestial_system_definition.body_definitions:
		if definition == null:
			continue
		body_definitions.append(definition.duplicate(true))

func _apply_session_scenario() -> void:
	_load_celestial_system_definition()

	var session = _game_session()
	if session == null:
		return

	if session.has_method("begin_run"):
		session.begin_run()

	if not session.has_method("get_active_scenario"):
		return

	var scenario: Dictionary = session.get_active_scenario()
	var body_overrides: Dictionary = scenario.get("body_overrides", {})
	for body_name_variant in body_overrides.keys():
		var body_name: StringName = StringName(str(body_name_variant))
		var definition: CelestialBodyDefinition = get_body_definition(body_name)
		if definition == null:
			continue

		var overrides: Dictionary = body_overrides.get(body_name_variant, {})
		if overrides.has("center_distance"):
			definition.center_distance = float(overrides.get("center_distance", definition.center_distance))
		if overrides.has("phase"):
			definition.phase = float(overrides.get("phase", definition.phase))
		if overrides.has("eccentricity"):
			definition.eccentricity = clampf(float(overrides.get("eccentricity", definition.eccentricity)), 0.0, 0.8)
		if overrides.has("inclination_degrees"):
			definition.inclination_degrees = float(overrides.get("inclination_degrees", definition.inclination_degrees))
		if overrides.has("longitude_of_ascending_node_degrees"):
			definition.longitude_of_ascending_node_degrees = float(overrides.get("longitude_of_ascending_node_degrees", definition.longitude_of_ascending_node_degrees))
		if overrides.has("argument_of_periapsis_degrees"):
			definition.argument_of_periapsis_degrees = float(overrides.get("argument_of_periapsis_degrees", definition.argument_of_periapsis_degrees))
		if overrides.has("angular_speed_override"):
			definition.angular_speed_override = float(overrides.get("angular_speed_override", definition.angular_speed_override))
		if overrides.has("linear_speed_override"):
			definition.linear_speed_override = float(overrides.get("linear_speed_override", definition.linear_speed_override))


func _get_session_ship_start_state() -> Dictionary:
	var default_start := {
		"position_offset": Vector3(900.0, 0.0, 0.0),
		"velocity": Vector3(0.0, 0.0, 4.216),
	}

	var session = _game_session()
	if session == null or not session.has_method("get_active_scenario"):
		return default_start

	var scenario: Dictionary = session.get_active_scenario()
	var ship_start: Dictionary = scenario.get("ship_start", {})
	if ship_start.is_empty():
		return default_start

	var coplanar_with_body_name: StringName = ship_start.get("coplanar_with_body_name", &"")
	if coplanar_with_body_name != &"" and has_body(coplanar_with_body_name):
		var parent_body_name: StringName = get_body_parent(coplanar_with_body_name)
		if parent_body_name != &"":
			var target_body_pos: Vector3 = get_body_position(coplanar_with_body_name)
			var target_body_vel: Vector3 = get_body_velocity(coplanar_with_body_name)
			var parent_body_pos: Vector3 = get_body_position(parent_body_name)
			var parent_body_vel: Vector3 = get_body_velocity(parent_body_name)
			var plane_normal: Vector3 = get_orbital_plane_normal_from_state(
				target_body_pos,
				target_body_vel,
				parent_body_pos,
				parent_body_vel
			)
			if plane_normal.length_squared() > 0.0001:
				var radial_dir: Vector3 = (target_body_pos - parent_body_pos).normalized()
				var orbit_radius: float = maxf(
					float(ship_start.get("orbit_radius", default_start["position_offset"].length())),
					1.0
				)
				var orbit_speed: float = maxf(
					float(ship_start.get("speed", default_start["velocity"].length())),
					0.001
				)
				var retrograde: bool = bool(ship_start.get("coplanar_retrograde", false))
				var tangential_dir: Vector3 = plane_normal.cross(radial_dir).normalized()
				if retrograde:
					tangential_dir = -tangential_dir
				var world_position: Vector3 = parent_body_pos + radial_dir * orbit_radius
				var world_velocity: Vector3 = parent_body_vel + tangential_dir * orbit_speed
				return {
					"position_offset": world_position - planet_pos,
					"velocity": world_velocity,
				}

	var position_offset: Vector3 = ship_start.get("position_offset", default_start["position_offset"])
	var velocity: Vector3 = ship_start.get("velocity", default_start["velocity"])
	return {
		"position_offset": position_offset,
		"velocity": velocity,
	}


func _game_session():
	return get_node_or_null("/root/GameSession")

func _get_active_body_definitions() -> Array[CelestialBodyDefinition]:
	var definitions: Array[CelestialBodyDefinition] = []
	var known_body_keys: Dictionary = {}

	for definition in body_definitions:
		if definition == null or not definition.enabled:
			continue
		var body_key: String = _get_body_key(definition.body_name)
		if body_key.is_empty() or known_body_keys.has(body_key):
			continue
		definitions.append(definition)
		known_body_keys[body_key] = true

	if not known_body_keys.has(_get_body_key(LEGACY_PRIMARY_BODY_NAME)):
		definitions.append(_build_legacy_primary_body_definition())
		known_body_keys[_get_body_key(LEGACY_PRIMARY_BODY_NAME)] = true

	if not known_body_keys.has(_get_body_key(LEGACY_FOCUSED_CHILD_BODY_NAME)):
		definitions.append(_build_legacy_focused_child_body_definition())

	return definitions

func _reset_non_rail_body_states() -> void:
	for definition in _get_active_body_definitions():
		if definition == null or not definition.enabled:
			continue
		var orbit_mode: int = definition.orbit_mode
		if definition.parent_body_name != &"" and orbit_mode != CelestialBodyDefinition.OrbitMode.STATIC:
			continue
		_set_body_state_raw(definition.body_name, definition.initial_position, definition.initial_velocity)
	_sync_legacy_body_fields_from_registry()

func _rebuild_body_registry() -> void:
	bodies.clear()
	var unresolved_definitions: Array[CelestialBodyDefinition] = _get_active_body_definitions()
	var unresolved_count_previous: int = unresolved_definitions.size()

	while not unresolved_definitions.is_empty():
		var next_unresolved: Array[CelestialBodyDefinition] = []
		var made_progress: bool = false

		for definition in unresolved_definitions:
			if definition == null or not definition.enabled:
				continue

			if definition.parent_body_name != &"" and not has_body(definition.parent_body_name):
				next_unresolved.append(definition)
				continue

			_register_body_from_definition(definition, sim_time)
			made_progress = true

		if not made_progress:
			for definition in next_unresolved:
				if definition == null or not definition.enabled:
					continue
				_register_body_from_definition(definition, sim_time)
			break

		unresolved_definitions = next_unresolved
		if unresolved_definitions.size() == unresolved_count_previous:
			break
		unresolved_count_previous = unresolved_definitions.size()

	_sync_legacy_body_fields_from_registry()

func _sync_legacy_body_fields_from_registry() -> void:
	var planet: Dictionary = get_body_record(&"planet")
	if not planet.is_empty():
		planet_radius = planet.get("radius", planet_radius)
		planet_surface_gravity = planet.get("surface_gravity", planet_surface_gravity)
		planet_mu = planet.get("mu", planet_mu)
		planet_pos = planet.get("pos", planet_pos)
		planet_vel = planet.get("vel", planet_vel)
		planet_up = planet.get("up", planet_up)

	var moon: Dictionary = get_body_record(&"moon")
	if not moon.is_empty():
		moon_radius = moon.get("radius", moon_radius)
		moon_surface_gravity = moon.get("surface_gravity", moon_surface_gravity)
		moon_mu = moon.get("mu", moon_mu)
		moon_pos = moon.get("pos", moon_pos)
		moon_vel = moon.get("vel", moon_vel)
		moon_up = moon.get("up", moon_up)

		var orbit: Dictionary = moon.get("orbit", {})
		moon_orbit_radius = orbit.get("center_distance", moon_orbit_radius)
		moon_orbit_phase = orbit.get("phase", moon_orbit_phase)
		moon_orbit_speed = orbit.get("angular_speed", moon_orbit_speed)
		moon_orbit_linear_speed = orbit.get("linear_speed", moon_orbit_linear_speed)

func increase_warp():
	warp_index = min(warp_index + 1, warp_levels.size() - 1)
	celestial_time_scale = warp_levels[warp_index]
	print("Time Warp:", celestial_time_scale, "x")

func decrease_warp():
	warp_index = max(warp_index - 1, 0)
	celestial_time_scale = warp_levels[warp_index]
	print("Time Warp:", celestial_time_scale, "x")

func begin_targeted_warp_to_sim_time(target_sim_time: float) -> bool:
	_clear_targeted_warp_path()
	return begin_targeted_warp_to_state(target_sim_time, ship_pos, ship_vel)

func begin_targeted_warp_to_state(target_sim_time: float, target_ship_pos: Vector3, target_ship_vel: Vector3) -> bool:
	if target_sim_time <= sim_time + 0.001:
		return false

	var sim_duration: float = target_sim_time - sim_time
	var desired_real_duration: float = _get_targeted_warp_duration_for_sim_duration(sim_duration)
	var required_scale: float = sim_duration / max(desired_real_duration, 0.001)

	targeted_warp_previous_time_scale = celestial_time_scale
	targeted_warp_target_sim_time = target_sim_time
	targeted_warp_snap_ship_pos = target_ship_pos
	targeted_warp_snap_ship_vel = target_ship_vel
	targeted_warp_has_snap_state = true
	targeted_warp_real_duration_seconds = desired_real_duration
	targeted_warp_active = true
	celestial_time_scale = max(required_scale, targeted_warp_scale, 1.0)
	return true

func begin_targeted_warp_to_path(
	target_sim_time: float,
	path_positions: Array[Vector3],
	path_velocities: Array[Vector3],
	path_step_seconds: float
) -> bool:
	if path_positions.is_empty():
		return false

	var final_velocity: Vector3 = ship_vel
	if not path_velocities.is_empty():
		final_velocity = path_velocities[min(path_velocities.size() - 1, path_positions.size() - 1)]

	if not begin_targeted_warp_to_state(target_sim_time, path_positions[path_positions.size() - 1], final_velocity):
		return false

	targeted_warp_path_positions = path_positions.duplicate()
	targeted_warp_path_velocities = path_velocities.duplicate()
	targeted_warp_path_step_seconds = max(path_step_seconds, 0.001)
	targeted_warp_path_start_sim_time = sim_time
	_apply_targeted_warp_path_state()
	return true

func cancel_targeted_warp() -> void:
	if not targeted_warp_active:
		targeted_warp_target_sim_time = -1.0
		return

	_finish_targeted_warp(false)

func _finish_targeted_warp(reached_target: bool) -> void:
	targeted_warp_active = false
	targeted_warp_target_sim_time = -1.0
	celestial_time_scale = targeted_warp_previous_time_scale
	_current_sim_delta = 0.0
	_prepared_physics_frame = Engine.get_physics_frames()

	if reached_target and targeted_warp_has_snap_state:
		ship_pos = targeted_warp_snap_ship_pos
		ship_vel = targeted_warp_snap_ship_vel

	targeted_warp_has_snap_state = false
	targeted_warp_real_duration_seconds = 0.0
	_clear_targeted_warp_path()

func is_targeted_warp_active() -> bool:
	return targeted_warp_active

func is_targeted_warp_path_active() -> bool:
	return targeted_warp_active and not targeted_warp_path_positions.is_empty() and targeted_warp_path_step_seconds > 0.0

func get_targeted_warp_target_sim_time() -> float:
	return targeted_warp_target_sim_time

func get_targeted_warp_remaining_time() -> float:
	if not targeted_warp_active:
		return 0.0
	return max(0.0, targeted_warp_target_sim_time - sim_time)

func get_targeted_warp_real_duration_seconds() -> float:
	return targeted_warp_real_duration_seconds

func _get_targeted_warp_duration_for_sim_duration(sim_duration: float) -> float:
	if sim_duration <= targeted_warp_short_threshold_seconds:
		return max(targeted_warp_short_duration_seconds, 0.1)
	return max(targeted_warp_long_duration_seconds, 0.1)

func _apply_targeted_warp_path_state() -> void:
	if not is_targeted_warp_path_active():
		return

	var elapsed_sim_time: float = max(0.0, sim_time - targeted_warp_path_start_sim_time)
	var sample_f: float = elapsed_sim_time / targeted_warp_path_step_seconds
	var last_index: int = targeted_warp_path_positions.size() - 1
	var base_index: int = clampi(int(floor(sample_f)), 0, last_index)
	var next_index: int = min(base_index + 1, last_index)
	var t: float = clampf(sample_f - float(base_index), 0.0, 1.0)

	ship_pos = targeted_warp_path_positions[base_index].lerp(targeted_warp_path_positions[next_index], t)

	if not targeted_warp_path_velocities.is_empty():
		var safe_base_velocity: Vector3 = targeted_warp_path_velocities[min(base_index, targeted_warp_path_velocities.size() - 1)]
		var safe_next_velocity: Vector3 = targeted_warp_path_velocities[min(next_index, targeted_warp_path_velocities.size() - 1)]
		ship_vel = safe_base_velocity.lerp(safe_next_velocity, t)

func _clear_targeted_warp_path() -> void:
	targeted_warp_path_positions.clear()
	targeted_warp_path_velocities.clear()
	targeted_warp_path_step_seconds = 0.0
	targeted_warp_path_start_sim_time = -1.0
