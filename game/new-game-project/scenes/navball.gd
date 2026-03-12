extends Node3D

@export var ship_path: NodePath
@export var ball_path: NodePath
@export var ball_skin_path: NodePath

@export var prograde_path: NodePath
@export var retrograde_path: NodePath
@export var radial_in_path: NodePath
@export var radial_out_path: NodePath
@export var normal_path: NodePath
@export var anti_normal_path: NodePath
@export var nose_path: NodePath

@export var marker_radius: float = 0.55
@export var min_speed_to_show: float = 0.05
@export var inward_offset: float = 0.0

# This rotates ONLY the visible sphere/texture, not the marker math.
@export var skin_rotation_offset_degrees: Vector3 = Vector3.ZERO

var ship: Node3D
var ball: Node3D
var ball_skin: Node3D

var prograde_marker: Node3D
var retrograde_marker: Node3D
var radial_in_marker: Node3D
var radial_out_marker: Node3D
var normal_marker: Node3D
var anti_normal_marker: Node3D
var nose_marker: Node3D


func _ready() -> void:
	ship = get_node_or_null(ship_path) as Node3D
	ball = get_node_or_null(ball_path) as Node3D
	ball_skin = get_node_or_null(ball_skin_path) as Node3D

	prograde_marker = get_node_or_null(prograde_path) as Node3D
	retrograde_marker = get_node_or_null(retrograde_path) as Node3D
	radial_in_marker = get_node_or_null(radial_in_path) as Node3D
	radial_out_marker = get_node_or_null(radial_out_path) as Node3D
	normal_marker = get_node_or_null(normal_path) as Node3D
	anti_normal_marker = get_node_or_null(anti_normal_path) as Node3D
	nose_marker = get_node_or_null(nose_path) as Node3D

	_apply_skin_rotation_offset()


func _process(_delta: float) -> void:
	if ship == null or ball == null:
		return

	_update_ball_orientation()
	_apply_skin_rotation_offset()

	update_prograde_and_retrograde()
	update_radial_markers()
	update_normal_markers()
	update_nose_marker()


func _update_ball_orientation() -> void:
	var ship_basis: Basis = ship.global_transform.basis.orthonormalized()

	# Godot returns:
	# x = pitch
	# y = yaw
	# z = roll
	var ship_euler: Vector3 = ship_basis.get_euler(EULER_ORDER_YXZ)

	var ship_pitch: float = ship_euler.x
	var ship_yaw: float = ship_euler.y
	var ship_roll: float = ship_euler.z

	# Desired navball convention:
	# X = roll
	# Y = yaw
	# Z = pitch
	#
	# Negative signs because the ball counter-rotates against the ship.
	var navball_euler: Vector3 = Vector3(
		-ship_roll,
		-ship_yaw,
		-ship_pitch
	)

	ball.rotation = navball_euler


func _apply_skin_rotation_offset() -> void:
	if ball_skin == null:
		return

	ball_skin.rotation_degrees = skin_rotation_offset_degrees


func _ball_inverse_basis() -> Basis:
	return ball.global_transform.basis.orthonormalized().inverse()


func update_prograde_and_retrograde() -> void:
	if prograde_marker == null or retrograde_marker == null:
		return

	var vel: Vector3 = SimulationState.ship_vel
	var speed: float = vel.length()

	if speed < min_speed_to_show:
		prograde_marker.visible = false
		retrograde_marker.visible = false
		return

	prograde_marker.visible = true
	retrograde_marker.visible = true

	var world_dir: Vector3 = vel.normalized()
	var local_dir: Vector3 = (_ball_inverse_basis() * world_dir).normalized()

	place_marker(prograde_marker, local_dir)
	place_marker(retrograde_marker, -local_dir)


func update_radial_markers() -> void:
	if radial_in_marker == null or radial_out_marker == null:
		if radial_in_marker != null:
			radial_in_marker.visible = false
		if radial_out_marker != null:
			radial_out_marker.visible = false
		return

	var to_planet_world: Vector3 = SimulationState.planet_pos - SimulationState.ship_pos

	if to_planet_world.length() <= 0.0001:
		radial_in_marker.visible = false
		radial_out_marker.visible = false
		return

	radial_in_marker.visible = true
	radial_out_marker.visible = true

	var radial_in_local: Vector3 = (_ball_inverse_basis() * to_planet_world.normalized()).normalized()

	place_marker(radial_in_marker, radial_in_local)
	place_marker(radial_out_marker, -radial_in_local)


func update_normal_markers() -> void:
	if normal_marker == null or anti_normal_marker == null:
		if normal_marker != null:
			normal_marker.visible = false
		if anti_normal_marker != null:
			anti_normal_marker.visible = false
		return

	var r: Vector3 = SimulationState.ship_pos - SimulationState.planet_pos
	var v: Vector3 = SimulationState.ship_vel

	if r.length() <= 0.0001 or v.length() <= min_speed_to_show:
		normal_marker.visible = false
		anti_normal_marker.visible = false
		return

	var orbit_normal_world: Vector3 = r.cross(v)

	if orbit_normal_world.length() <= 0.0001:
		normal_marker.visible = false
		anti_normal_marker.visible = false
		return

	normal_marker.visible = true
	anti_normal_marker.visible = true

	var normal_local: Vector3 = (_ball_inverse_basis() * orbit_normal_world.normalized()).normalized()

	place_marker(normal_marker, normal_local)
	place_marker(anti_normal_marker, -normal_local)


func update_nose_marker() -> void:
	if nose_marker == null or ship == null:
		return

	nose_marker.visible = true

	# Godot forward is usually -Z.
	var world_dir: Vector3 = (ship.global_transform.basis.z).normalized()
	var local_dir: Vector3 = (_ball_inverse_basis() * world_dir).normalized()

	place_marker(nose_marker, local_dir)


func place_marker(marker: Node3D, local_dir: Vector3) -> void:
	var inward: Vector3 = -local_dir.normalized()

	marker.position = local_dir * marker_radius + inward * inward_offset
	orient_marker_inward(marker, local_dir)


func orient_marker_inward(marker: Node3D, local_dir: Vector3) -> void:
	var inward: Vector3 = -local_dir.normalized()

	var up: Vector3 = Vector3.UP
	if abs(inward.dot(up)) > 0.98:
		up = Vector3.RIGHT

	var right: Vector3 = up.cross(inward).normalized()
	var corrected_up: Vector3 = inward.cross(right).normalized()

	var marker_basis: Basis = Basis(right, -inward, corrected_up)
	marker.transform.basis = marker_basis
