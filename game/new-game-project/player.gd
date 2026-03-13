extends Node3D

@export var seat_root_path: NodePath
@export var camera_path: NodePath
@export var interact_ray_path: NodePath
@export var crosshair_ui_path: NodePath

@export var snap_speed: float = 7.5
@export var zoom_speed: float = 8.0
@export var mouse_sensitivity: float = 0.0025

@export var crosshair_rect_path: NodePath
@export var normal_crosshair_texture: Texture2D
@export var zoom_crosshair_texture: Texture2D
@export var interact_crosshair_texture: Texture2D

@export var max_free_yaw_degrees: float = 85.0
@export var max_free_pitch_degrees: float = 65.0

@export var enable_mouse_look: bool = true

@export var thrust_recoil_distance: float = 0.08
@export var thrust_recoil_lerp_speed: float = 10.0
@export var thrust_shake_x: float = 0.008
@export var thrust_shake_y: float = 0.006
@export var thrust_shake_rot_z_degrees: float = 0.5
@export var thrust_shake_frequency_1: float = 33.0
@export var thrust_shake_frequency_2: float = 47.0

var thrust_feedback_active: bool = false
var thrust_feedback_time: float = 0.0
var current_recoil_offset: Vector3 = Vector3.ZERO

var seat_root: Node3D
var camera_3d: Camera3D
var interact_ray: RayCast3D
var crosshair_ui: CanvasLayer

var held_interactable: Object = null
var current_highlighted: Object = null
var active_zoom_target: Node3D = null

var free_yaw: float = 0.0
var free_pitch: float = 0.0
var current_yaw: float = 0.0
var current_pitch: float = 0.0

var default_camera_local_transform: Transform3D
var crosshair_rect: TextureRect

func _ready() -> void:
	seat_root = get_node_or_null(seat_root_path) as Node3D
	camera_3d = get_node_or_null(camera_path) as Camera3D
	interact_ray = get_node_or_null(interact_ray_path) as RayCast3D
	crosshair_ui = get_node_or_null(crosshair_ui_path) as CanvasLayer
	crosshair_rect = get_node_or_null(crosshair_rect_path) as TextureRect
	if seat_root == null:
		push_warning("Player.gd: seat_root_path is not assigned or is not a Node3D.")
	if camera_3d == null:
		push_warning("Player.gd: camera_path is not assigned or is not a Camera3D.")
	if interact_ray == null:
		push_warning("Player.gd: interact_ray_path is not assigned or is not a RayCast3D.")

	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	default_camera_local_transform = camera_3d.transform
	_update_crosshair_visibility()
	_update_crosshair_icon("normal")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and enable_mouse_look and active_zoom_target == null:
		free_yaw -= event.relative.x * mouse_sensitivity
		free_pitch -= event.relative.y * mouse_sensitivity

		var max_yaw := deg_to_rad(max_free_yaw_degrees)
		var max_pitch := deg_to_rad(max_free_pitch_degrees)

		free_yaw = clamp(free_yaw, -max_yaw, max_yaw)
		free_pitch = clamp(free_pitch, -max_pitch, max_pitch)

	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _process(delta: float) -> void:
	if seat_root == null or camera_3d == null:
		return

	global_position = seat_root.global_position
	global_rotation = seat_root.global_rotation

	handle_interaction()

	if active_zoom_target != null:
		var desired_local: Transform3D = global_transform.affine_inverse() * active_zoom_target.global_transform
		desired_local = _apply_thrust_feedback_to_transform(desired_local, delta)
		camera_3d.transform = camera_3d.transform.interpolate_with(desired_local, delta * zoom_speed)
		return

	var desired_yaw: float = free_yaw
	var desired_pitch: float = free_pitch

	current_yaw = lerp_angle(current_yaw, desired_yaw, delta * snap_speed)
	current_pitch = lerp_angle(current_pitch, desired_pitch, delta * snap_speed)

	var desired_transform := default_camera_local_transform
	desired_transform.basis = Basis.from_euler(Vector3(current_pitch, current_yaw, 0.0))
	desired_transform = _apply_thrust_feedback_to_transform(desired_transform, delta)
	camera_3d.transform = camera_3d.transform.interpolate_with(desired_transform, delta * snap_speed)


func handle_interaction() -> void:
	if interact_ray == null:
		return

	# Exit zoom if already zoomed
	if active_zoom_target != null:
		if Input.is_action_just_pressed("interact"):
			active_zoom_target = null
			_update_crosshair_visibility()
			_update_crosshair_icon("normal")
		return

	var collider: Object = null
	if interact_ray.is_colliding():
		collider = interact_ray.get_collider()

	var hovering_zoomable := false
	var hovering_interactable := false

	if collider != null:
		if collider.has_method("get_zoom_target"):
			var zoom_target = collider.get_zoom_target()
			hovering_zoomable = (zoom_target != null)

		if collider.has_method("press"):
			hovering_interactable = true

	if active_zoom_target == null:
		if hovering_zoomable:
			_update_crosshair_icon("zoom")
		elif hovering_interactable:
			_update_crosshair_icon("interact")
		else:
			_update_crosshair_icon("normal")
	# Highlight logic
	if current_highlighted != null and current_highlighted != collider:
		if current_highlighted.has_method("set_highlight"):
			current_highlighted.set_highlight(false)
		current_highlighted = null

	if collider != null and collider.has_method("set_highlight"):
		collider.set_highlight(true)
		current_highlighted = collider

	# Zoom toggle with E
	if Input.is_action_just_pressed("interact"):
		if collider != null and collider.has_method("get_zoom_target"):
			var target = collider.get_zoom_target()
			if target != null:
				if current_highlighted != null and current_highlighted.has_method("set_highlight"):
					current_highlighted.set_highlight(false)
				current_highlighted = null

				active_zoom_target = target
				_update_crosshair_visibility()
				return

	# Existing button hold logic
	var interact_pressed: bool = Input.is_action_pressed("interact")

	if interact_pressed:
		var new_interactable: Object = collider

		if held_interactable != null and held_interactable != new_interactable:
			if held_interactable.has_method("release"):
				held_interactable.release()
			held_interactable = null

		if new_interactable != null:
			if held_interactable == null:
				if new_interactable.has_method("press"):
					new_interactable.press()
					held_interactable = new_interactable
	else:
		if held_interactable != null:
			if held_interactable.has_method("release"):
				held_interactable.release()
			held_interactable = null


func _update_crosshair_visibility() -> void:
	if crosshair_ui == null:
		return
	crosshair_ui.visible = (active_zoom_target == null)

func set_thrust_feedback_active(active: bool) -> void:
	thrust_feedback_active = active
	if not thrust_feedback_active:
		thrust_feedback_time = 0.0
		
func _update_crosshair_icon(mode: String) -> void:
	if crosshair_rect == null:
		return

	match mode:
		"zoom":
			crosshair_rect.texture = zoom_crosshair_texture
		"interact":
			crosshair_rect.texture = interact_crosshair_texture
		_:
			crosshair_rect.texture = normal_crosshair_texture

func _apply_thrust_feedback_to_transform(t: Transform3D, delta: float) -> Transform3D:
	var recoil_target := Vector3.ZERO

	if thrust_feedback_active:
		recoil_target = Vector3(0.0, 0.0, thrust_recoil_distance)
		thrust_feedback_time += delta
	else:
		thrust_feedback_time = 0.0

	current_recoil_offset = current_recoil_offset.lerp(
		recoil_target,
		delta * thrust_recoil_lerp_speed
	)

	var shake_pos := Vector3.ZERO
	var shake_rot := Vector3.ZERO

	if thrust_feedback_active:
		shake_pos.x = sin(thrust_feedback_time * thrust_shake_frequency_1) * thrust_shake_x
		shake_pos.y = cos(thrust_feedback_time * thrust_shake_frequency_2) * thrust_shake_y
		shake_rot.z = deg_to_rad(sin(thrust_feedback_time * 41.0) * thrust_shake_rot_z_degrees)

	t.origin += current_recoil_offset + shake_pos
	t.basis = t.basis * Basis.from_euler(shake_rot)

	return t
