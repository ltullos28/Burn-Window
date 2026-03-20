extends Node3D

# Translation
@export var main_thrust: float = 0.05
@export var max_speed: float = 200.0
@export var damping: float = 0.0

# Rotation
@export var max_rot_accel: float = 0.20
@export var angular_drag: float = 0.1

@export var engine_audio_path: NodePath

var angular_velocity: Vector3 = Vector3.ZERO

var pitch_control: float = 0.0
var yaw_control: float = 0.0
var roll_control: float = 0.0

var thrust_held: bool = false

var engine_audio: Node

func _ready() -> void:
	position = Vector3.ZERO
	engine_audio = get_node_or_null(engine_audio_path)

func _physics_process(delta: float) -> void:
	var sim_delta: float = SimulationState.get_current_sim_delta(delta)
	if sim_delta <= 0.0:
		position = Vector3.ZERO
		return

	var controls_locked: bool = SimulationState.is_targeted_warp_active()
	var warp_path_active: bool = SimulationState.is_targeted_warp_path_active()
	if controls_locked:
		if thrust_held:
			set_thrust_held(false)
		pitch_control = 0.0
		yaw_control = 0.0
		roll_control = 0.0

	if thrust_held and not controls_locked:
		var world_accel: Vector3 = global_transform.basis * Vector3(0.0, 0.0, main_thrust)
		SimulationState.ship_vel += world_accel * sim_delta
		SimulationState.mark_trajectory_prediction_stale()

	if not controls_locked and Input.is_action_pressed("ship_damp"):
		SimulationState.ship_vel = SimulationState.ship_vel.move_toward(
			Vector3.ZERO,
			damping * 10.0 * sim_delta
		)

	if not controls_locked and Input.is_action_just_pressed("ship_kill_velocity"):
		SimulationState.ship_vel = Vector3.ZERO

	if not warp_path_active:
		SimulationState.ship_vel += SimulationState.gravity_accel_at(SimulationState.ship_pos) * sim_delta

	if not warp_path_active and SimulationState.ship_vel.length() > max_speed:
		SimulationState.ship_vel = SimulationState.ship_vel.normalized() * max_speed

	if not warp_path_active:
		SimulationState.ship_pos += SimulationState.ship_vel * sim_delta

	angular_velocity.x += pitch_control * max_rot_accel * sim_delta
	angular_velocity.y += yaw_control * max_rot_accel * sim_delta
	angular_velocity.z += roll_control * max_rot_accel * sim_delta

	angular_velocity = angular_velocity.move_toward(Vector3.ZERO, angular_drag * sim_delta)

	rotate_object_local(Vector3.RIGHT, angular_velocity.x * sim_delta)
	rotate_object_local(Vector3.UP, angular_velocity.y * sim_delta)
	rotate_object_local(Vector3.BACK, angular_velocity.z * sim_delta)

	position = Vector3.ZERO

func set_pitch_control(value: float) -> void:
	pitch_control = clampf(value, -1.0, 1.0)

func set_yaw_control(value: float) -> void:
	yaw_control = clampf(value, -1.0, 1.0)

func set_roll_control(value: float) -> void:
	roll_control = clampf(value, -1.0, 1.0)

func set_thrust_held(value: bool) -> void:
	thrust_held = value

	if engine_audio != null and engine_audio.has_method("set_thrust_audio_active"):
		engine_audio.set_thrust_audio_active(value)
