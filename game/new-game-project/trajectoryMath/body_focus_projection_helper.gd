class_name BodyFocusProjectionHelper
extends RefCounted

const CENTER_MODE_PLANET := 0
const CENTER_MODE_MOON := 1
const CENTER_MODE_SHIP := 2

const PRIMARY_BODY_NAME := &"planet"

func get_target_view_offset(center_mode: int, ship_pos: Vector3, focused_child_body_name: StringName) -> Vector2:
	var planet_pos: Vector3 = SimulationState.get_body_position(PRIMARY_BODY_NAME)

	match center_mode:
		CENTER_MODE_PLANET:
			return Vector2.ZERO
		CENTER_MODE_MOON:
			if focused_child_body_name == &"":
				return Vector2.ZERO
			var child_rel_planet: Vector3 = SimulationState.get_body_position(focused_child_body_name) - planet_pos
			return Vector2(-child_rel_planet.x, child_rel_planet.z)
		CENTER_MODE_SHIP:
			var ship_rel_planet: Vector3 = ship_pos - planet_pos
			return Vector2(-ship_rel_planet.x, ship_rel_planet.z)

	return Vector2.ZERO

func project_planet_frame(world_planet_frame: Vector3) -> Vector2:
	return Vector2(world_planet_frame.x, -world_planet_frame.z)

func to_screen(world_planet_frame: Vector3, screen_center: Vector2, view_offset: Vector2, pixels_per_unit: float) -> Vector2:
	return screen_center + (project_planet_frame(world_planet_frame) + view_offset) * pixels_per_unit

func get_inclination_reference_body_name(center_mode: int, focused_child_body_name: StringName) -> StringName:
	if center_mode == CENTER_MODE_MOON:
		return focused_child_body_name if focused_child_body_name != &"" else PRIMARY_BODY_NAME
	return PRIMARY_BODY_NAME

# EQUATOR compares the selected reference body's current motion plane against the
# ship's current motion plane in the same parent frame. For moon targets this
# means "moon orbit around parent", not moon spin/up/equator.
func get_equator_reference_context(reference_body_name: StringName) -> Dictionary:
	var body_name: StringName = reference_body_name if reference_body_name != &"" else PRIMARY_BODY_NAME
	var body_state := {
		"name": body_name,
		"pos": SimulationState.get_body_position(body_name),
		"vel": SimulationState.get_body_velocity(body_name),
		"up": SimulationState.get_body_up(body_name),
		"radius": SimulationState.get_body_radius(body_name),
		"frame_origin_pos": SimulationState.get_body_position(body_name),
		"frame_origin_vel": SimulationState.get_body_velocity(body_name),
		"frame_reference_body_name": body_name,
		"plane_normal": SimulationState.get_body_up(body_name),
		"plane_source": "body_up",
	}

	if body_name == PRIMARY_BODY_NAME:
		return body_state

	var parent_body_name: StringName = SimulationState.get_body_parent(body_name)
	if parent_body_name == &"":
		return body_state

	var parent_pos: Vector3 = SimulationState.get_body_position(parent_body_name)
	var parent_vel: Vector3 = SimulationState.get_body_velocity(parent_body_name)
	var orbital_plane_normal: Vector3 = SimulationState.get_orbital_plane_normal_from_state(
		body_state["pos"],
		body_state["vel"],
		parent_pos,
		parent_vel
	)
	var plane_source: String = "instantaneous_parent_orbit"
	if orbital_plane_normal.length_squared() <= 0.0001:
		orbital_plane_normal = SimulationState.get_orbit_plane_normal_from_elements(
			SimulationState.get_body_orbit_params(body_name)
		)
		plane_source = "authored_parent_orbit_fallback"
	if orbital_plane_normal.length_squared() <= 0.0001:
		orbital_plane_normal = SimulationState.get_body_up(parent_body_name)
		plane_source = "parent_up_fallback"
	if orbital_plane_normal.length_squared() <= 0.0001:
		orbital_plane_normal = Vector3.UP
		plane_source = "world_up_fallback"

	body_state["frame_origin_pos"] = parent_pos
	body_state["frame_origin_vel"] = parent_vel
	body_state["frame_reference_body_name"] = parent_body_name
	body_state["plane_normal"] = orbital_plane_normal.normalized()
	body_state["plane_source"] = plane_source
	return body_state

func get_inclination_reference_body_state(center_mode: int, focused_child_body_name: StringName) -> Dictionary:
	return get_equator_reference_context(
		get_inclination_reference_body_name(center_mode, focused_child_body_name)
	)
