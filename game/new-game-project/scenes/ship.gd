extends Node3D

# Translation
@export var main_thrust: float = 0.05
@export var max_speed: float = 200.0
@export var damping: float = 0.0

# Rotation
@export var max_rot_accel: float = 0.20
@export var angular_drag: float = 0.1
@export var navball_path: NodePath
@export var lock_to_vector_radius_m: float = 0.06
@export var lock_to_vector_max_angular_speed: float = 0.12
@export var lock_to_vector_strength: float = 6.0

@export var engine_audio_path: NodePath
@export var resource_controller_path: NodePath

var angular_velocity: Vector3 = Vector3.ZERO

var pitch_control: float = 0.0
var yaw_control: float = 0.0
var roll_control: float = 0.0

var thrust_held: bool = false

var engine_audio: Node
var resource_controller: Node
var navball: Node

func _ready() -> void:
	position = Vector3.ZERO
	engine_audio = get_node_or_null(engine_audio_path)
	resource_controller = get_node_or_null(resource_controller_path)
	navball = _resolve_navball_node()
	if not navball_path.is_empty() and navball == null:
		push_warning("%s: navball_path did not resolve; Lock To Vector assist will stay inactive." % name)

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

	if thrust_held and resource_controller != null and resource_controller.has_method("can_thrust"):
		if not resource_controller.can_thrust():
			set_thrust_held(false)

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

	var effective_pitch_control: float = pitch_control
	var effective_yaw_control: float = yaw_control
	var effective_roll_control: float = roll_control
	var lock_to_vector_state: Dictionary = _evaluate_lock_to_vector_assist()
	var lock_to_vector_assist: Vector2 = lock_to_vector_state.get("assist", Vector2.ZERO)

	effective_pitch_control = clampf(effective_pitch_control, -1.0, 1.0)
	effective_yaw_control = clampf(effective_yaw_control, -1.0, 1.0)

	angular_velocity = angular_velocity.move_toward(Vector3.ZERO, angular_drag * sim_delta)

	angular_velocity.x += effective_pitch_control * max_rot_accel * sim_delta
	angular_velocity.y += effective_yaw_control * max_rot_accel * sim_delta
	angular_velocity.z += effective_roll_control * max_rot_accel * sim_delta

	# Apply the alignment assist as a tiny extra pitch/yaw torque after drag so it can
	# still overcome damping once the nose is inside the visual capture radius.
	angular_velocity.x += lock_to_vector_assist.x * lock_to_vector_strength * sim_delta
	angular_velocity.y += lock_to_vector_assist.y * lock_to_vector_strength * sim_delta

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


func _evaluate_lock_to_vector_assist() -> Dictionary:
	var result: Dictionary = {
		"active": false,
		"reason": "unknown",
		"assist": Vector2.ZERO,
		"target_info": {},
		"angular_speed": angular_velocity.length(),
		"rotation_override": _has_rotation_override_input(),
		"navball_method_available": navball != null and navball.has_method("get_lock_to_vector_target_info"),
	}

	if not _is_lock_to_vector_enabled():
		result["reason"] = "setting_disabled"
		return result
	if SimulationState.is_targeted_warp_active() or SimulationState.is_targeted_warp_path_active():
		result["reason"] = "warp_active"
		return result
	if bool(result["rotation_override"]):
		result["reason"] = "rotation_input_override"
		return result
	if float(result["angular_speed"]) > lock_to_vector_max_angular_speed:
		result["reason"] = "angular_speed_cutoff"
		return result
	if navball == null:
		result["reason"] = "navball_missing"
		return result
	if not bool(result["navball_method_available"]):
		result["reason"] = "navball_method_missing"
		return result

	var target_info: Dictionary = navball.get_lock_to_vector_target_info()
	result["target_info"] = target_info
	if not bool(target_info.get("valid", false)):
		result["reason"] = "no_valid_target"
		return result

	var marker_distance: float = float(target_info.get("marker_distance", INF))
	if marker_distance > lock_to_vector_radius_m:
		result["reason"] = "outside_capture_radius"
		return result

	var target_local_direction: Vector3 = target_info.get("target_local_direction", Vector3.ZERO)
	if target_local_direction.length_squared() <= 0.00000001:
		result["reason"] = "zero_target_direction"
		return result

	# Positive pitch rotates the nose toward -Y, so the vertical correction must be inverted.
	var pitch_assist: float = clampf(-target_local_direction.y, -1.0, 1.0)
	var yaw_assist: float = clampf(target_local_direction.x, -1.0, 1.0)
	result["assist"] = Vector2(pitch_assist, yaw_assist)
	result["active"] = true
	result["reason"] = "active"
	return result


func _has_rotation_override_input() -> bool:
	return absf(pitch_control) > 0.001 or absf(yaw_control) > 0.001 or absf(roll_control) > 0.001


func _is_lock_to_vector_enabled() -> bool:
	var settings := get_node_or_null("/root/GameSettings")
	if settings == null:
		return false
	return bool(settings.get("lock_to_vector_enabled"))


func _resolve_navball_node() -> Node:
	var candidate: Node = null
	if not navball_path.is_empty():
		candidate = get_node_or_null(navball_path)
	candidate = _coerce_navball_candidate(candidate)
	if candidate != null:
		return candidate
	return _coerce_navball_candidate(get_node_or_null("NavballRig"))


func _coerce_navball_candidate(candidate: Node) -> Node:
	if candidate == null:
		return null
	if candidate.has_method("get_lock_to_vector_target_info"):
		return candidate
	var parent: Node = candidate.get_parent()
	if parent != null and parent.has_method("get_lock_to_vector_target_info"):
		return parent
	for child in candidate.get_children():
		if child is Node and (child as Node).has_method("get_lock_to_vector_target_info"):
			return child
	return null
