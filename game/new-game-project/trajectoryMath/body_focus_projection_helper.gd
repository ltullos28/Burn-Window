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

func get_inclination_reference_body_state(center_mode: int, focused_child_body_name: StringName) -> Dictionary:
	var body_name: StringName = get_inclination_reference_body_name(center_mode, focused_child_body_name)
	return {
		"name": body_name,
		"pos": SimulationState.get_body_position(body_name),
		"vel": SimulationState.get_body_velocity(body_name),
		"up": SimulationState.get_body_up(body_name),
		"radius": SimulationState.get_body_radius(body_name),
	}
