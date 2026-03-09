extends Node3D

@export var player_path: NodePath

# Translation
@export var main_thrust: float = 12.0
@export var boost_multiplier: float = 2.0
@export var max_speed: float = 200.0
@export var damping: float = 0.4

# Rotation
@export var max_rot_accel: float = 1.8
@export var angular_drag: float = 0.5

var player: Node3D

# Simulation-space translational state lives in SimulationState
# Rotational state lives on the rendered ship
var angular_velocity: Vector3 = Vector3.ZERO

var pitch_control: float = 0.0
var yaw_control: float = 0.0
var roll_control: float = 0.0

func _ready() -> void:
	player = get_node_or_null(player_path) as Node3D
	position = Vector3.ZERO

func _process(delta: float) -> void:
	# ---- TRANSLATION ----
	if player != null and player.flight_mode:
		var thrust: float = main_thrust
		if Input.is_key_pressed(KEY_SHIFT):
			thrust *= boost_multiplier

		# One rear thruster:
		# Forward thrust is +Z relative to the ship node
		if Input.is_action_pressed("ship_forward"):
			var world_accel: Vector3 = transform.basis * Vector3(0.0, 0.0, thrust)
			SimulationState.ship_vel += world_accel * delta

		# Optional damping assist
		if Input.is_action_pressed("ship_damp"):
			SimulationState.ship_vel = SimulationState.ship_vel.move_toward(
				Vector3.ZERO,
				damping * 10.0 * delta
			)

		# Hard kill velocity
		if Input.is_action_just_pressed("ship_kill_velocity"):
			SimulationState.ship_vel = Vector3.ZERO

	# Gravity always acts
	SimulationState.ship_vel += SimulationState.gravity_accel_at(SimulationState.ship_pos) * delta

	# Clamp speed for prototype sanity
	if SimulationState.ship_vel.length() > max_speed:
		SimulationState.ship_vel = SimulationState.ship_vel.normalized() * max_speed

	# Advance simulation
	SimulationState.ship_pos += SimulationState.ship_vel * delta

	# ---- ROTATION ----
	angular_velocity.x += pitch_control * max_rot_accel * delta
	angular_velocity.y += yaw_control * max_rot_accel * delta
	angular_velocity.z += roll_control * max_rot_accel * delta

	angular_velocity = angular_velocity.move_toward(Vector3.ZERO, angular_drag * delta)

	# Apply local rotations
	rotate_object_local(Vector3.RIGHT, angular_velocity.x * delta)
	rotate_object_local(Vector3.UP, angular_velocity.y * delta)
	rotate_object_local(Vector3.BACK, angular_velocity.z * delta)

	# Keep rendered ship near origin
	position = Vector3.ZERO

func set_pitch_control(value: float) -> void:
	pitch_control = clampf(value, -1.0, 1.0)

func set_yaw_control(value: float) -> void:
	yaw_control = clampf(value, -1.0, 1.0)

func set_roll_control(value: float) -> void:
	roll_control = clampf(value, -1.0, 1.0)
