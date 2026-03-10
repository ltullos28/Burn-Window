extends Node3D

@export var player_path: NodePath
@export var navball_path: NodePath

@export var orbit_radius: float = 1.91
@export var fixed_height: float = 0.256
@export var fixed_x_rotation_deg: float = 68.8

# Smooth only the angular motion between snap points
@export var theta_smoothing: float = 8.0

# If the player gets too close to the navball center,
# freeze snap evaluation so the plate does not whip around.
@export var inner_lock_radius: float = 2.15

# Extra protection around quadrant boundaries (in degrees).
# Larger = more stable / less twitchy when standing near a diagonal.
@export var boundary_margin_deg: float = 8.0

var player: Node3D
var navball: Node3D

# Snap points around the navball (4 quadrants)
var snap_thetas: Array[float] = [
	0.0,
	PI * 0.5,
	PI,
	-PI * 0.5
]

var current_theta: float = 0.0
var target_theta: float = 0.0
var current_snap_index: int = 0
var initialized: bool = false

func _ready() -> void:
	player = get_node_or_null(player_path) as Node3D
	navball = get_node_or_null(navball_path) as Node3D

	if player == null or navball == null:
		return

	var parent_node := get_parent() as Node3D
	if parent_node == null:
		return

	var player_local: Vector3 = parent_node.to_local(player.global_position)
	var navball_local: Vector3 = navball.position

	var to_player: Vector3 = player_local - navball_local
	to_player.y = 0.0

	if to_player.length_squared() < 0.0001:
		to_player = Vector3.FORWARD

	var theta: float = atan2(to_player.x, to_player.z)

	current_snap_index = _snap_index_for_theta(theta)
	target_theta = snap_thetas[current_snap_index]
	current_theta = target_theta

	initialized = true
	_apply_from_theta(current_theta)

func _physics_process(delta: float) -> void:
	if not initialized or player == null or navball == null:
		return

	var parent_node := get_parent() as Node3D
	if parent_node == null:
		return

	var player_local: Vector3 = parent_node.to_local(player.global_position)
	var navball_local: Vector3 = navball.position

	var to_player: Vector3 = player_local - navball_local
	to_player.y = 0.0

	var flat_dist: float = to_player.length()

	# Only evaluate snap switching if the player is outside the lock radius
	if flat_dist > inner_lock_radius and to_player.length_squared() > 0.0001:
		var player_theta: float = atan2(to_player.x, to_player.z)
		var maybe_new_index: int = _snap_index_with_hysteresis(player_theta, current_snap_index)

		if maybe_new_index != current_snap_index:
			current_snap_index = maybe_new_index
			target_theta = snap_thetas[current_snap_index]

	var t: float = clampf(theta_smoothing * delta, 0.0, 1.0)
	current_theta = lerp_angle(current_theta, target_theta, t)

	_apply_from_theta(current_theta)

func _apply_from_theta(theta: float) -> void:
	if navball == null:
		return

	var navball_local: Vector3 = navball.position

	# Position from snapped polar coordinates
	var offset: Vector3 = Vector3(
		sin(theta) * orbit_radius,
		0.0,
		cos(theta) * orbit_radius
	)

	position = navball_local + offset
	position.y = fixed_height

	# Rotation hard-locked to the same snapped polar angle
	rotation.x = deg_to_rad(fixed_x_rotation_deg)
	rotation.y = theta + PI
	rotation.z = 0.0

func _snap_index_for_theta(theta: float) -> int:
	# Find the closest of the 4 snap points
	var best_index: int = 0
	var best_abs_delta: float = INF

	for i in range(snap_thetas.size()):
		var d: float = abs(wrapf(theta - snap_thetas[i], -PI, PI))
		if d < best_abs_delta:
			best_abs_delta = d
			best_index = i

	return best_index

func _snap_index_with_hysteresis(theta: float, current_index: int) -> int:
	# Default behavior: stay where we are unless the player is clearly in another quadrant.
	# This prevents jitter when the player stands near a diagonal boundary.

	var current_center: float = snap_thetas[current_index]
	var sector_half: float = PI * 0.25
	var margin: float = deg_to_rad(boundary_margin_deg)

	var delta_from_current: float = wrapf(theta - current_center, -PI, PI)

	# Stay in current quadrant until the player pushes clearly beyond the normal boundary
	# plus a little extra margin.
	if abs(delta_from_current) <= sector_half + margin:
		return current_index

	# Once clearly beyond, choose the nearest snap point.
	return _snap_index_for_theta(theta)
