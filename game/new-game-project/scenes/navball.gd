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

var _cached_ship_basis_inverse: Basis = Basis.IDENTITY
var _cached_reference_body_name: StringName = &""
var _cached_reference_body_pos: Vector3 = Vector3.ZERO
var _cached_reference_body_vel: Vector3 = Vector3.ZERO
var _last_applied_skin_rotation_offset_degrees: Vector3 = Vector3(1000000.0, 1000000.0, 1000000.0)
var _marker_ship_local_directions: Dictionary = {}


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
	_warn_if_missing_nodes()


func _process(_delta: float) -> void:
	if ship == null or ball_root == null or marker_root == null:
		return

	_refresh_frame_cache()
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
	var current_scale: Vector3 = ball_root.transform.basis.get_scale()
	ball_root.transform.basis = _cached_ship_basis_inverse.scaled(current_scale)


func _apply_skin_rotation_offset() -> void:
	if ball_skin == null:
		return
	if _last_applied_skin_rotation_offset_degrees == skin_rotation_offset_degrees:
		return
	ball_skin.rotation_degrees = skin_rotation_offset_degrees
	_last_applied_skin_rotation_offset_degrees = skin_rotation_offset_degrees


func _warn_if_missing_nodes() -> void:
	if ship == null:
		push_warning("%s: ship_path did not resolve." % name)
	if ball_root == null:
		push_warning("%s: ball_root_path did not resolve." % name)
	if marker_root == null:
		push_warning("%s: marker_root_path did not resolve." % name)
	if nose_marker == null:
		push_warning("%s: nose_path did not resolve; Lock To Vector assist will be unavailable." % name)


func _refresh_frame_cache() -> void:
	_cached_ship_basis_inverse = ship.global_transform.basis.orthonormalized().inverse()
	_cached_reference_body_name = SimulationState.get_ship_reference_body_name()
	_cached_reference_body_pos = SimulationState.get_body_position(_cached_reference_body_name)
	_cached_reference_body_vel = SimulationState.get_body_velocity(_cached_reference_body_name)


# ----------------------------
# STABLE SHIP-LOCAL FRAME
# ----------------------------


func _world_to_ship_local_dir(world_dir: Vector3) -> Vector3:
	if ship == null or world_dir.length_squared() <= 0.00000001:
		return Vector3.ZERO
	return (_cached_ship_basis_inverse * world_dir).normalized()


# ----------------------------
# MARKER UPDATES
# ----------------------------


func update_prograde_and_retrograde() -> void:
	var vel: Vector3 = SimulationState.ship_vel - _cached_reference_body_vel
	_update_opposed_markers(prograde_marker, retrograde_marker, vel, min_speed_to_show)


func update_radial_markers() -> void:
	var to_reference_world: Vector3 = _cached_reference_body_pos - SimulationState.ship_pos
	_update_opposed_markers(radial_in_marker, radial_out_marker, to_reference_world)


func update_normal_markers() -> void:
	var r: Vector3 = SimulationState.ship_pos - _cached_reference_body_pos
	var v: Vector3 = SimulationState.ship_vel - _cached_reference_body_vel

	if r.length() <= 0.0001 or v.length() <= min_speed_to_show:
		_hide_marker(normal_marker)
		_hide_marker(anti_normal_marker)
		return

	# Preserve the project's orbital convention: normal = r x v.
	var orbit_normal_world: Vector3 = r.cross(v)
	_update_opposed_markers(normal_marker, anti_normal_marker, orbit_normal_world)


func update_nose_marker() -> void:
	if nose_marker == null or ship == null:
		return

	# In this project, ship forward / thrust direction is +Z.
	var nose_world_dir: Vector3 = ship.global_transform.basis.z.normalized()
	var ship_local_dir: Vector3 = _world_to_ship_local_dir(nose_world_dir)
	_set_marker_direction(nose_marker, ship_local_dir)


func get_lock_to_vector_target_info() -> Dictionary:
	if nose_marker == null or not nose_marker.visible:
		return {"valid": false}

	var candidates: Array[Dictionary] = [
		{"name": "prograde", "marker": prograde_marker},
		{"name": "retrograde", "marker": retrograde_marker},
		{"name": "radial_in", "marker": radial_in_marker},
		{"name": "radial_out", "marker": radial_out_marker},
		{"name": "normal", "marker": normal_marker},
		{"name": "anti_normal", "marker": anti_normal_marker},
	]

	var nose_position: Vector3 = nose_marker.position
	var best_name: StringName = &""
	var best_marker_position: Vector3 = Vector3.ZERO
	var best_local_direction: Vector3 = Vector3.ZERO
	var best_distance: float = INF

	for candidate in candidates:
		var marker := candidate.get("marker") as Node3D
		if marker == null or not marker.visible:
			continue

		var candidate_position: Vector3 = marker.position
		var distance: float = nose_position.distance_to(candidate_position)
		if distance < best_distance:
			best_distance = distance
			best_name = StringName(candidate.get("name", ""))
			best_marker_position = candidate_position
			best_local_direction = _get_marker_ship_local_direction(marker)

	if best_name == StringName():
		return {"valid": false}

	return {
		"valid": true,
		"target_name": best_name,
		"target_marker_position": best_marker_position,
		"target_local_direction": best_local_direction,
		"nose_marker_position": nose_position,
		"marker_distance": best_distance,
	}


func get_lock_to_vector_debug_snapshot() -> Dictionary:
	var snapshot: Dictionary = {
		"ship_ready": ship != null,
		"ball_root_ready": ball_root != null,
		"marker_root_ready": marker_root != null,
		"nose_visible": nose_marker != null and nose_marker.visible,
		"reference_body_name": str(_cached_reference_body_name),
		"nearest_target": "",
		"nearest_distance": INF,
		"target_local_direction": Vector3.ZERO,
		"visible_marker_distances": {},
	}

	if nose_marker == null or not nose_marker.visible:
		return snapshot

	var candidates: Array[Dictionary] = [
		{"name": "prograde", "marker": prograde_marker},
		{"name": "retrograde", "marker": retrograde_marker},
		{"name": "radial_in", "marker": radial_in_marker},
		{"name": "radial_out", "marker": radial_out_marker},
		{"name": "normal", "marker": normal_marker},
		{"name": "anti_normal", "marker": anti_normal_marker},
	]

	var best_distance: float = INF
	var best_name: String = ""
	var best_direction: Vector3 = Vector3.ZERO
	var visible_distances: Dictionary = {}
	var nose_position: Vector3 = nose_marker.position

	for candidate in candidates:
		var marker := candidate.get("marker") as Node3D
		if marker == null or not marker.visible:
			continue

		var marker_name: String = str(candidate.get("name", ""))
		var distance: float = nose_position.distance_to(marker.position)
		visible_distances[marker_name] = snappedf(distance, 0.0001)
		if distance < best_distance:
			best_distance = distance
			best_name = marker_name
			best_direction = _get_marker_ship_local_direction(marker)

	snapshot["visible_marker_distances"] = visible_distances
	snapshot["nearest_target"] = best_name
	snapshot["nearest_distance"] = best_distance
	snapshot["target_local_direction"] = best_direction
	return snapshot


# ----------------------------
# MARKER PLACEMENT
# ----------------------------


func place_marker(marker: Node3D, ship_local_dir: Vector3) -> void:
	_set_marker_direction(marker, ship_local_dir)


func _update_opposed_markers(primary_marker: Node3D, opposite_marker: Node3D, world_dir: Vector3, min_length: float = 0.0001) -> void:
	if primary_marker == null or opposite_marker == null:
		_hide_marker(primary_marker)
		_hide_marker(opposite_marker)
		return
	if world_dir.length() <= min_length:
		_hide_marker(primary_marker)
		_hide_marker(opposite_marker)
		return

	var ship_local_dir: Vector3 = _world_to_ship_local_dir(world_dir)
	if ship_local_dir.length_squared() <= 0.00000001:
		_hide_marker(primary_marker)
		_hide_marker(opposite_marker)
		return

	_set_marker_direction(primary_marker, ship_local_dir)
	_set_marker_direction(opposite_marker, -ship_local_dir)


func _set_marker_direction(marker: Node3D, ship_local_dir: Vector3) -> void:
	if marker_root == null or marker == null:
		return

	var dir: Vector3 = ship_local_dir.normalized()
	if dir.length_squared() <= 0.00000001:
		_hide_marker(marker)
		return

	marker.visible = true
	_marker_ship_local_directions[marker] = dir
	marker.position = _direction_to_marker_position(dir)
	orient_marker_inward(marker, dir)


func _direction_to_marker_position(ship_local_dir: Vector3) -> Vector3:
	var dir: Vector3 = ship_local_dir.normalized()
	var inward: Vector3 = -dir
	return dir * marker_radius + inward * inward_offset


func _hide_marker(marker: Node3D) -> void:
	if marker != null:
		marker.visible = false
		_marker_ship_local_directions.erase(marker)


func _get_marker_ship_local_direction(marker: Node3D) -> Vector3:
	if marker == null:
		return Vector3.ZERO
	var cached_direction: Variant = _marker_ship_local_directions.get(marker, Vector3.ZERO)
	if cached_direction is Vector3:
		return cached_direction
	return Vector3.ZERO


func orient_marker_inward(marker: Node3D, local_dir: Vector3) -> void:
	if marker == null or local_dir.length_squared() <= 0.00000001:
		return

	var inward: Vector3 = -local_dir.normalized()
	var up: Vector3 = Vector3.UP
	if abs(inward.dot(up)) > 0.98:
		up = Vector3.RIGHT

	var right: Vector3 = up.cross(inward).normalized()
	var corrected_up: Vector3 = inward.cross(right).normalized()

	marker.transform.basis = Basis(right, -inward, corrected_up)
