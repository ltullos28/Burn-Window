class_name CelestialBodyDefinition
extends Resource

enum OrbitMode {
	STATIC,
	CIRCULAR
}

@export var enabled: bool = true
@export var body_name: StringName = &""
@export var radius: float = 100.0
@export var surface_gravity: float = 0.01
@export var up: Vector3 = Vector3.UP
@export var parent_body_name: StringName = &""
@export var orbit_mode: OrbitMode = OrbitMode.STATIC
@export var center_distance: float = 0.0
@export var phase: float = 0.0
@export var angular_speed_override: float = -1.0
@export var linear_speed_override: float = -1.0
@export var initial_position: Vector3 = Vector3.ZERO
@export var initial_velocity: Vector3 = Vector3.ZERO
