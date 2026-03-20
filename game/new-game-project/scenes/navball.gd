extends Node3D

@export var ship_path: NodePath
@export var ball_root_path: NodePath
@export var ball_skin_path: NodePath
@export var marker_root_path: NodePath

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

# Visual-only offset for the sphere texture/orientation
@export var skin_rotation_offset_degrees: Vector3 = Vector3.ZERO

var ship: Node3D
var ball_root: Node3D
var ball_skin: Node3D
var marker_root: Node3D

var prograde_marker: Node3D
var retrograde_marker: Node3D
var radial_in_marker: Node3D
var radial_out_marker: Node3D
var normal_marker: Node3D
var anti_normal_marker: Node3D
var nose_marker: Node3D

func _get_reference_body_name() -> StringName:
	return SimulationState.get_ship_reference_body_name()

func _get_reference_body_pos() -> Vector3:
	return SimulationState.get_body_position(_get_reference_body_name())

func _get_reference_body_vel() -> Vector3:
	return SimulationState.get_body_velocity(_get_reference_body_name())


func _ready() -> void:
	ship = get_node_or_null(ship_path) as Node3D
	ball_root = get_node_or_null(ball_root_path) as Node3D
	ball_skin = get_node_or_null(ball_skin_path) as Node3D
	marker_root = get_node_or_null(marker_root_path) as Node3D

	prograde_marker = get_node_or_null(prograde_path) as Node3D
	retrograde_marker = get_node_or_null(retrograde_path) as Node3D
	radial_in_marker = get_node_or_null(radial_in_path) as Node3D
	radial_out_marker = get_node_or_null(radial_out_path) as Node3D
	normal_marker = get_node_or_null(normal_path) as Node3D
	anti_normal_marker = get_node_or_null(anti_normal_path) as Node3D
	nose_marker = get_node_or_null(nose_path) as Node3D

	_apply_skin_rotation_offset()


func _process(_delta: float) -> void:
	if ship == null or ball_root == null or marker_root == null:
		return

	_update_ball_orientation()
	_apply_skin_rotation_offset()

	update_prograde_and_retrograde()
	update_radial_markers()
	update_normal_markers()
	update_nose_marker()


# ----------------------------
# BALL ROTATION
# ----------------------------


func _update_ball_orientation() -> void:
	var ship_basis: Basis = ship.global_transform.basis.orthonormalized()

	var current_scale: Vector3 = ball_root.transform.basis.get_scale()
	ball_root.transform.basis = ship_basis.inverse().scaled(current_scale)

func _apply_skin_rotation_offset() -> void:
	if ball_skin == null:
		return
	ball_skin.rotation_degrees = skin_rotation_offset_degrees


# ----------------------------
# STABLE SHIP-LOCAL FRAME
# ----------------------------

func _world_to_ship_local_dir(world_dir: Vector3) -> Vector3:
	if ship == null:
		return Vector3.ZERO
	return (ship.global_transform.basis.orthonormalized().inverse() * world_dir).normalized()


# ----------------------------
# MARKER UPDATES
# ----------------------------

func update_prograde_and_retrograde() -> void:
	if prograde_marker == null or retrograde_marker == null:
		return

	var vel: Vector3 = SimulationState.ship_vel - _get_reference_body_vel()
	var speed: float = vel.length()

	if speed < min_speed_to_show:
		prograde_marker.visible = false
		retrograde_marker.visible = false
		return

	prograde_marker.visible = true
	retrograde_marker.visible = true

	var ship_local_dir: Vector3 = _world_to_ship_local_dir(vel.normalized())

	place_marker(prograde_marker, ship_local_dir)
	place_marker(retrograde_marker, -ship_local_dir)


func update_radial_markers() -> void:
	if radial_in_marker == null or radial_out_marker == null:
		if radial_in_marker != null:
			radial_in_marker.visible = false
		if radial_out_marker != null:
			radial_out_marker.visible = false
		return

	var to_planet_world: Vector3 = _get_reference_body_pos() - SimulationState.ship_pos

	if to_planet_world.length() <= 0.0001:
		radial_in_marker.visible = false
		radial_out_marker.visible = false
		return

	radial_in_marker.visible = true
	radial_out_marker.visible = true

	var ship_local_dir: Vector3 = _world_to_ship_local_dir(to_planet_world.normalized())

	place_marker(radial_in_marker, ship_local_dir)
	place_marker(radial_out_marker, -ship_local_dir)


func update_normal_markers() -> void:
	if normal_marker == null or anti_normal_marker == null:
		if normal_marker != null:
			normal_marker.visible = false
		if anti_normal_marker != null:
			anti_normal_marker.visible = false
		return

	var r: Vector3 = SimulationState.ship_pos - _get_reference_body_pos()
	var v: Vector3 = SimulationState.ship_vel - _get_reference_body_vel()

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

	var ship_local_dir: Vector3 = _world_to_ship_local_dir(orbit_normal_world.normalized())

	place_marker(normal_marker, ship_local_dir)
	place_marker(anti_normal_marker, -ship_local_dir)


func update_nose_marker() -> void:
	if nose_marker == null or ship == null:
		return

	nose_marker.visible = true

	# In this project, ship forward / thrust direction is +Z
	var nose_world_dir: Vector3 = ship.global_transform.basis.z.normalized()
	var ship_local_dir: Vector3 = _world_to_ship_local_dir(nose_world_dir)

	place_marker(nose_marker, ship_local_dir)


# ----------------------------
# MARKER PLACEMENT
# ----------------------------

func place_marker(marker: Node3D, ship_local_dir: Vector3) -> void:
	if marker_root == null:
		return

	var dir: Vector3 = ship_local_dir.normalized()
	var inward: Vector3 = -dir

	# Markers live under MarkerRoot, not BallRoot, so they do not inherit ball rotation.
	marker.position = dir * marker_radius + inward * inward_offset
	orient_marker_inward(marker, dir)


func orient_marker_inward(marker: Node3D, local_dir: Vector3) -> void:
	var inward: Vector3 = -local_dir.normalized()

	var up: Vector3 = Vector3.UP
	if abs(inward.dot(up)) > 0.98:
		up = Vector3.RIGHT

	var right: Vector3 = up.cross(inward).normalized()
	var corrected_up: Vector3 = inward.cross(right).normalized()

	marker.transform.basis = Basis(right, -inward, corrected_up)
