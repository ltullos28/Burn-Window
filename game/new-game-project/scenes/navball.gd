extends Node3D

@export var ship_path: NodePath
@export var ball_path: NodePath

@export var prograde_path: NodePath
@export var retrograde_path: NodePath
@export var radial_in_path: NodePath
@export var radial_out_path: NodePath
@export var nose_path: NodePath

@export var marker_radius: float = 0.55
@export var min_speed_to_show: float = 0.05
@export var inward_offset: float = 0.0

var ship: Node3D
var ball: Node3D

var prograde_marker: Node3D
var retrograde_marker: Node3D
var radial_in_marker: Node3D
var radial_out_marker: Node3D
var nose_marker: Node3D

func _ready() -> void:
	ship = get_node_or_null(ship_path) as Node3D
	ball = get_node_or_null(ball_path) as Node3D

	prograde_marker = get_node_or_null(prograde_path) as Node3D
	retrograde_marker = get_node_or_null(retrograde_path) as Node3D
	radial_in_marker = get_node_or_null(radial_in_path) as Node3D
	radial_out_marker = get_node_or_null(radial_out_path) as Node3D
	nose_marker = get_node_or_null(nose_path) as Node3D


func _process(_delta: float) -> void:
	if ship == null or ball == null:
		return

	# Counter-rotate the navball against ship orientation
	ball.quaternion = ship.global_transform.basis.get_rotation_quaternion().inverse()

	update_prograde_and_retrograde()
	update_radial_markers()
	update_nose_marker()


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
	var local_dir: Vector3 = (ball.global_transform.basis.inverse() * world_dir).normalized()

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

	var radial_in_local: Vector3 = (ball.global_transform.basis.inverse() * to_planet_world.normalized()).normalized()

	place_marker(radial_in_marker, radial_in_local)
	place_marker(radial_out_marker, -radial_in_local)


func update_nose_marker() -> void:
	if nose_marker == null or ship == null:
		return

	nose_marker.visible = true

	# Ship forward direction
	var world_dir: Vector3 = ship.global_transform.basis.z.normalized()

	var local_dir: Vector3 = (ball.global_transform.basis.inverse() * world_dir).normalized()

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
