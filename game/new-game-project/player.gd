extends Node3D

@export var seat_root_path: NodePath
@export var camera_path: NodePath
@export var interact_ray_path: NodePath
@export var crosshair_ui_path: NodePath

@export var snap_speed: float = 10.0
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
@export var warp_select_repeat_initial_delay: float = 0.35
@export var warp_select_repeat_interval: float = 0.08
@export var death_fade_out_duration: float = 0.6
@export var death_hold_duration: float = 0.9
@export var death_fade_in_duration: float = 0.8
@export var death_message: String = "YOU DIED"

var thrust_feedback_active: bool = false
var thrust_feedback_time: float = 0.0
var current_recoil_offset: Vector3 = Vector3.ZERO

var seat_root: Node3D
var camera_3d: Camera3D
var interact_ray: RayCast3D
var crosshair_ui: CanvasLayer
var ambience_player: AudioStreamPlayer
var shared_button_player: AudioStreamPlayer3D
var whirring_player: AudioStreamPlayer
var beep_player: AudioStreamPlayer3D

var _base_ambience_volume_db: float = -20.0
var _base_shared_button_volume_db: float = 0.0
var _base_whirring_volume_db: float = 0.0
var _base_beep_volume_db: float = 0.0
var _audio_base_levels_resolved: bool = false

var held_interactable: Object = null
var current_highlighted: Object = null
var active_zoom_target: Node3D = null
var trajectory_map: Node = null
var trajectory_screen_zoom_target: Node3D = null

var free_yaw: float = 0.0
var free_pitch: float = 0.0
var current_yaw: float = 0.0
var current_pitch: float = 0.0
var mouse_smoothing_enabled: bool = true
var active_mouse_smoothing_speed: float = 10.0
var warp_hold_direction: int = 0
var warp_hold_repeat_timer: float = 0.0
var warp_hold_repeat_started: bool = false
var death_overlay_layer: CanvasLayer
var death_overlay_rect: ColorRect
var death_overlay_label: Label
var death_sequence_active: bool = false
var death_phase: String = "idle"
var death_phase_elapsed: float = 0.0
var death_reset_triggered: bool = false

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

	active_mouse_smoothing_speed = snap_speed
	default_camera_local_transform = camera_3d.transform
	_resolve_audio_refs()
	_resolve_special_refs()
	_setup_death_overlay()
	if not SimulationState.ship_impacted.is_connected(_on_ship_impacted):
		SimulationState.ship_impacted.connect(_on_ship_impacted)
	_apply_settings()
	var settings = _settings()
	if settings != null and not settings.settings_changed.is_connected(_apply_settings):
		settings.settings_changed.connect(_apply_settings)
	_update_crosshair_visibility()
	_update_crosshair_icon("normal")


func _unhandled_input(event: InputEvent) -> void:
	if _handle_trajectory_timewarp_input(event):
		get_viewport().set_input_as_handled()
		return

	if death_sequence_active:
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion and enable_mouse_look and active_zoom_target == null:
		var settings = _settings()
		free_yaw -= event.relative.x * mouse_sensitivity
		var pitch_sign := 1.0 if settings != null and settings.invert_y_look else -1.0
		free_pitch += event.relative.y * mouse_sensitivity * pitch_sign

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

	_update_death_sequence(delta)

	global_position = seat_root.global_position
	global_rotation = seat_root.global_rotation

	handle_interaction()
	_process_trajectory_timewarp_hold(delta)

	if active_zoom_target != null:
		var desired_local: Transform3D = global_transform.affine_inverse() * active_zoom_target.global_transform
		desired_local = _apply_thrust_feedback_to_transform(desired_local, delta)
		camera_3d.transform = camera_3d.transform.interpolate_with(desired_local, delta * zoom_speed)
		return

	var desired_yaw: float = free_yaw
	var desired_pitch: float = free_pitch

	if mouse_smoothing_enabled:
		current_yaw = lerp_angle(current_yaw, desired_yaw, delta * active_mouse_smoothing_speed)
		current_pitch = lerp_angle(current_pitch, desired_pitch, delta * active_mouse_smoothing_speed)
	else:
		current_yaw = desired_yaw
		current_pitch = desired_pitch

	var desired_transform := default_camera_local_transform
	desired_transform.basis = Basis.from_euler(Vector3(current_pitch, current_yaw, 0.0))
	desired_transform = _apply_thrust_feedback_to_transform(desired_transform, delta)
	if mouse_smoothing_enabled:
		camera_3d.transform = camera_3d.transform.interpolate_with(desired_transform, delta * active_mouse_smoothing_speed)
	else:
		camera_3d.transform = desired_transform

func _setup_death_overlay() -> void:
	death_overlay_layer = CanvasLayer.new()
	death_overlay_layer.name = "DeathOverlay"
	death_overlay_layer.layer = 100
	add_child(death_overlay_layer)

	death_overlay_rect = ColorRect.new()
	death_overlay_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	death_overlay_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	death_overlay_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	death_overlay_layer.add_child(death_overlay_rect)

	death_overlay_label = Label.new()
	death_overlay_label.text = death_message
	death_overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	death_overlay_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	death_overlay_label.visible = false
	death_overlay_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	death_overlay_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	death_overlay_label.add_theme_font_size_override("font_size", 42)
	death_overlay_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.96))
	death_overlay_layer.add_child(death_overlay_label)

func _on_ship_impacted(_body_name: StringName) -> void:
	trigger_death()

func trigger_death(message_override: String = "") -> void:
	if death_sequence_active:
		return

	death_overlay_label.text = message_override if not message_override.is_empty() else death_message
	death_sequence_active = true
	death_phase = "fade_out"
	death_phase_elapsed = 0.0
	death_reset_triggered = false
	active_zoom_target = null
	_set_trajectory_focus_active(false)
	_clear_trajectory_timewarp_hold()
	_update_crosshair_visibility()
	_update_crosshair_icon("normal")

func _update_death_sequence(delta: float) -> void:
	if not death_sequence_active:
		return

	death_phase_elapsed += delta
	match death_phase:
		"fade_out":
			var fade_out_t: float = 1.0 if death_fade_out_duration <= 0.0 else clampf(death_phase_elapsed / death_fade_out_duration, 0.0, 1.0)
			death_overlay_rect.color = Color(0.0, 0.0, 0.0, fade_out_t)
			death_overlay_label.visible = fade_out_t >= 0.6
			if fade_out_t >= 1.0:
				death_phase = "hold"
				death_phase_elapsed = 0.0
		"hold":
			death_overlay_rect.color = Color(0.0, 0.0, 0.0, 1.0)
			death_overlay_label.visible = true
			if not death_reset_triggered:
				SimulationState.finish_impact_recovery_reset()
				_resolve_special_refs()
				if trajectory_map != null and trajectory_map.has_method("request_refresh"):
					trajectory_map.request_refresh()
				death_reset_triggered = true
			if death_phase_elapsed >= death_hold_duration:
				death_phase = "fade_in"
				death_phase_elapsed = 0.0
		"fade_in":
			var fade_in_t: float = 1.0 if death_fade_in_duration <= 0.0 else clampf(death_phase_elapsed / death_fade_in_duration, 0.0, 1.0)
			var alpha: float = 1.0 - fade_in_t
			death_overlay_rect.color = Color(0.0, 0.0, 0.0, alpha)
			death_overlay_label.visible = alpha > 0.4
			if fade_in_t >= 1.0:
				death_overlay_rect.color = Color(0.0, 0.0, 0.0, 0.0)
				death_overlay_label.visible = false
				death_overlay_label.text = death_message
				death_sequence_active = false
				death_phase = "idle"
				death_phase_elapsed = 0.0


func handle_interaction() -> void:
	if interact_ray == null:
		return

	# Exit zoom if already zoomed
	if active_zoom_target != null:
		if Input.is_action_just_pressed("interact"):
			_set_trajectory_focus_active(false)
			_clear_trajectory_timewarp_hold()
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
				_set_trajectory_focus_active(_is_zoom_target_trajectory_screen(target))
				if not _is_zoom_target_trajectory_screen(target):
					_clear_trajectory_timewarp_hold()
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
	var settings = _settings()
	var shake_strength := 1.0 if settings != null and settings.camera_shake_enabled else 0.0
	var recoil_target := Vector3.ZERO

	if thrust_feedback_active:
		recoil_target = Vector3(0.0, 0.0, thrust_recoil_distance * shake_strength)
		thrust_feedback_time += delta
	else:
		thrust_feedback_time = 0.0

	current_recoil_offset = current_recoil_offset.lerp(
		recoil_target,
		delta * thrust_recoil_lerp_speed
	)

	var shake_pos := Vector3.ZERO
	var shake_rot := Vector3.ZERO

	if thrust_feedback_active and shake_strength > 0.0:
		shake_pos.x = sin(thrust_feedback_time * thrust_shake_frequency_1) * thrust_shake_x * shake_strength
		shake_pos.y = cos(thrust_feedback_time * thrust_shake_frequency_2) * thrust_shake_y * shake_strength
		shake_rot.z = deg_to_rad(sin(thrust_feedback_time * 41.0) * thrust_shake_rot_z_degrees * shake_strength)

	t.origin += current_recoil_offset + shake_pos
	t.basis = t.basis * Basis.from_euler(shake_rot)

	return t

func _resolve_special_refs() -> void:
	if trajectory_map == null:
		trajectory_map = get_tree().root.find_child("TrajectoryMap", true, false)

	if trajectory_screen_zoom_target == null:
		trajectory_screen_zoom_target = get_tree().root.find_child("ScreenZoomTarget", true, false) as Node3D

func _is_zoom_target_trajectory_screen(target: Node3D) -> bool:
	_resolve_special_refs()
	return trajectory_screen_zoom_target != null and target == trajectory_screen_zoom_target

func _is_zoomed_to_trajectory_screen() -> bool:
	return _is_zoom_target_trajectory_screen(active_zoom_target)

func _set_trajectory_focus_active(active: bool) -> void:
	_resolve_special_refs()
	if trajectory_map != null and trajectory_map.has_method("set_focus_active"):
		trajectory_map.set_focus_active(active)

func _handle_trajectory_timewarp_input(event: InputEvent) -> bool:
	if not _is_zoomed_to_trajectory_screen():
		_clear_trajectory_timewarp_hold()
		return false

	if not (event is InputEventKey):
		return false

	var key_event := event as InputEventKey
	if key_event.echo:
		return false

	_resolve_special_refs()
	if trajectory_map == null:
		return false

	var timewarp_enabled: bool = true
	if trajectory_map.has_method("is_timewarp_enabled"):
		timewarp_enabled = trajectory_map.is_timewarp_enabled()

	var coarse: bool = key_event.shift_pressed

	match key_event.keycode:
		KEY_T:
			if key_event.pressed and trajectory_map.has_method("toggle_timewarp_enabled"):
				_clear_trajectory_timewarp_hold()
				trajectory_map.toggle_timewarp_enabled()
				return true
		KEY_BRACKETLEFT:
			if not timewarp_enabled:
				_clear_trajectory_timewarp_hold()
				return false
			if key_event.pressed:
				_begin_trajectory_timewarp_hold(-1)
				if trajectory_map.has_method("move_warp_selection"):
					return trajectory_map.move_warp_selection(-1, coarse)
			else:
				_end_trajectory_timewarp_hold(-1)
			return false
		KEY_BRACKETRIGHT:
			if not timewarp_enabled:
				_clear_trajectory_timewarp_hold()
				return false
			if key_event.pressed:
				_begin_trajectory_timewarp_hold(1)
				if trajectory_map.has_method("move_warp_selection"):
					return trajectory_map.move_warp_selection(1, coarse)
			else:
				_end_trajectory_timewarp_hold(1)
			return false
		KEY_ENTER, KEY_KP_ENTER:
			if not timewarp_enabled:
				return false
			if key_event.pressed and trajectory_map.has_method("confirm_warp_selection"):
				return trajectory_map.confirm_warp_selection()
		KEY_ESCAPE:
			if not timewarp_enabled:
				return false
			if key_event.pressed and trajectory_map.has_method("cancel_warp_selection"):
				_clear_trajectory_timewarp_hold()
				trajectory_map.cancel_warp_selection()
				return true

	return false

func _process_trajectory_timewarp_hold(delta: float) -> void:
	if warp_hold_direction == 0:
		return
	if not _is_zoomed_to_trajectory_screen():
		_clear_trajectory_timewarp_hold()
		return

	_resolve_special_refs()
	if trajectory_map == null or not trajectory_map.has_method("move_warp_selection"):
		return
	if trajectory_map.has_method("is_timewarp_enabled") and not trajectory_map.is_timewarp_enabled():
		_clear_trajectory_timewarp_hold()
		return

	warp_hold_repeat_timer -= delta

	if not warp_hold_repeat_started:
		if warp_hold_repeat_timer <= 0.0:
			warp_hold_repeat_started = true
			warp_hold_repeat_timer = warp_select_repeat_interval
			trajectory_map.move_warp_selection(warp_hold_direction, Input.is_key_pressed(KEY_SHIFT))
	else:
		if warp_hold_repeat_timer <= 0.0:
			warp_hold_repeat_timer = warp_select_repeat_interval
			trajectory_map.move_warp_selection(warp_hold_direction, Input.is_key_pressed(KEY_SHIFT))

func _begin_trajectory_timewarp_hold(direction: int) -> void:
	warp_hold_direction = direction
	warp_hold_repeat_started = false
	warp_hold_repeat_timer = warp_select_repeat_initial_delay

func _end_trajectory_timewarp_hold(direction: int) -> void:
	if warp_hold_direction == direction:
		_clear_trajectory_timewarp_hold()

func _clear_trajectory_timewarp_hold() -> void:
	warp_hold_direction = 0
	warp_hold_repeat_timer = 0.0
	warp_hold_repeat_started = false


func _resolve_audio_refs() -> void:
	if ambience_player == null:
		ambience_player = get_node_or_null(NodePath("AmbiencePlayer3D")) as AudioStreamPlayer
	if shared_button_player == null:
		shared_button_player = get_node_or_null(NodePath("SharedButtonClick3D")) as AudioStreamPlayer3D
	if whirring_player == null:
		whirring_player = get_node_or_null(NodePath("WhirringPlayer3D")) as AudioStreamPlayer
	if beep_player == null:
		beep_player = get_node_or_null(NodePath("../Cockpit/IBM_5155/BeepPlayer3D")) as AudioStreamPlayer3D

	if _audio_base_levels_resolved:
		return

	if ambience_player != null:
		var ambient_target: Variant = ambience_player.get("target_volume_db")
		_base_ambience_volume_db = float(ambient_target) if ambient_target != null else ambience_player.volume_db
	if shared_button_player != null:
		_base_shared_button_volume_db = shared_button_player.volume_db
	if whirring_player != null:
		_base_whirring_volume_db = whirring_player.volume_db
	if beep_player != null:
		_base_beep_volume_db = beep_player.volume_db

	_audio_base_levels_resolved = true


func _apply_settings() -> void:
	var settings = _settings()
	if settings == null:
		return

	mouse_sensitivity = settings.mouse_sensitivity
	mouse_smoothing_enabled = settings.mouse_smoothing_enabled
	active_mouse_smoothing_speed = settings.mouse_smoothing_speed

	if camera_3d != null:
		camera_3d.fov = settings.camera_fov

	_resolve_audio_refs()

	if ambience_player != null:
		var ambience_db: float = _base_ambience_volume_db + settings.volume_scale_to_db_offset(settings.ambient_volume)
		if ambience_player.has_method("set_target_volume_db"):
			ambience_player.set_target_volume_db(ambience_db, true)
		else:
			ambience_player.volume_db = ambience_db

	var ui_db_offset: float = settings.volume_scale_to_db_offset(settings.ui_volume)

	if shared_button_player != null:
		shared_button_player.volume_db = _base_shared_button_volume_db + ui_db_offset

	if whirring_player != null:
		whirring_player.volume_db = _base_whirring_volume_db + ui_db_offset

	if beep_player != null:
		beep_player.volume_db = _base_beep_volume_db + ui_db_offset


func _settings():
	return get_node_or_null("/root/GameSettings")
