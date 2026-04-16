extends Node3D

@export var bob_axis: Vector3 = Vector3.UP
@export var bob_distance: float = 0.18
@export var bob_cycles_per_second: float = 0.05
@export var rotation_sway_degrees: Vector3 = Vector3(0.4, 0.8, 0.2)
@export var rotation_sway_cycles_per_second: Vector3 = Vector3(0.03, 0.045, 0.025)
@export var phase_offset_seconds: float = 0.0

var _base_position: Vector3 = Vector3.ZERO
var _base_rotation: Vector3 = Vector3.ZERO
var _elapsed: float = 0.0


func _ready() -> void:
	_base_position = position
	_base_rotation = rotation


func _process(delta: float) -> void:
	_elapsed += delta

	var safe_axis: Vector3 = bob_axis
	if safe_axis.length_squared() <= 0.0001:
		safe_axis = Vector3.UP
	safe_axis = safe_axis.normalized()

	var t: float = _elapsed + phase_offset_seconds
	var bob_wave: float = sin(t * TAU * bob_cycles_per_second)

	position = _base_position + safe_axis * bob_distance * bob_wave
	rotation = _base_rotation + Vector3(
		deg_to_rad(rotation_sway_degrees.x) * sin(t * TAU * rotation_sway_cycles_per_second.x),
		deg_to_rad(rotation_sway_degrees.y) * sin(t * TAU * rotation_sway_cycles_per_second.y),
		deg_to_rad(rotation_sway_degrees.z) * sin(t * TAU * rotation_sway_cycles_per_second.z)
	)
