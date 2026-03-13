extends Area3D

enum ActionType {
	LEVER,
	THRUST,
	TRAJECTORY_REFRESH,
	TRAJECTORY_ZOOM,
	TRAJECTORY_CENTER_CYCLE,
	TRAJECTORY_DISPLAY_MODE_CYCLE
}

enum ButtonMode {
	PLUS,
	MINUS
}

@export var action_type: ActionType = ActionType.LEVER
@export var mode: ButtonMode = ButtonMode.PLUS

@export var lever_path: NodePath
@export var ship_path: NodePath
@export var trajectory_map_path: NodePath

@export var shared_button_audio_path: NodePath
@export var rotation_whir_path: NodePath
@export var refresh_sound_path: NodePath

@export var zoom_repeat_initial_delay: float = 0.35
@export var zoom_repeat_interval: float = 0.08

@export var player_path: NodePath

var player: Node
var lever: Node
var ship: Node
var trajectory_map: Node

var shared_button_audio: AudioStreamPlayer3D
var rotation_whir: AudioStreamPlayer
var refresh_sound: Node

var is_held: bool = false
var repeat_timer: float = 0.0
var repeat_started: bool = false


func _ready() -> void:
	_resolve_refs()


func _process(delta: float) -> void:
	if action_type != ActionType.TRAJECTORY_ZOOM:
		return
	if not is_held:
		return
	if trajectory_map == null:
		return

	repeat_timer -= delta

	if not repeat_started:
		if repeat_timer <= 0.0:
			repeat_started = true
			repeat_timer = zoom_repeat_interval
			_apply_zoom_step(false)
	else:
		if repeat_timer <= 0.0:
			repeat_timer = zoom_repeat_interval
			_apply_zoom_step(false)


func _resolve_refs() -> void:
	lever = get_node_or_null(lever_path)
	ship = get_node_or_null(ship_path)
	trajectory_map = get_node_or_null(trajectory_map_path)
	player = get_node_or_null(player_path)
	shared_button_audio = get_node_or_null(shared_button_audio_path) as AudioStreamPlayer3D
	rotation_whir = get_node_or_null(rotation_whir_path) as AudioStreamPlayer
	refresh_sound = get_node_or_null(refresh_sound_path)


func _play_shared_button_audio() -> void:
	if shared_button_audio == null:
		return
	if shared_button_audio.stream == null:
		return
	shared_button_audio.play()


func _start_rotation_whir() -> void:
	if rotation_whir == null:
		return
	if rotation_whir.stream == null:
		return
	if not rotation_whir.playing:
		rotation_whir.play()


func _stop_rotation_whir() -> void:
	if rotation_whir == null:
		return
	if rotation_whir.playing:
		rotation_whir.stop()


func _apply_zoom_step(play_click: bool) -> void:
	if trajectory_map == null:
		return

	if play_click:
		_play_shared_button_audio()

	if mode == ButtonMode.PLUS:
		if trajectory_map.has_method("zoom_in"):
			trajectory_map.zoom_in()
	else:
		if trajectory_map.has_method("zoom_out"):
			trajectory_map.zoom_out()


func press() -> void:
	_resolve_refs()

	match action_type:
		ActionType.LEVER:
			_play_shared_button_audio()
			_start_rotation_whir()

			if lever == null:
				return

			if mode == ButtonMode.PLUS:
				if lever.has_method("press_plus"):
					lever.press_plus()
			else:
				if lever.has_method("press_minus"):
					lever.press_minus()

		ActionType.THRUST:
			_play_shared_button_audio()

			if ship == null:
				return
			if ship.has_method("set_thrust_held"):
				ship.set_thrust_held(true)

			if player != null and player.has_method("set_thrust_feedback_active"):
				player.set_thrust_feedback_active(true)

		ActionType.TRAJECTORY_REFRESH:
			_play_shared_button_audio()

			if trajectory_map != null and trajectory_map.has_method("request_refresh"):
				trajectory_map.request_refresh()

			if refresh_sound != null and refresh_sound.has_method("start_refresh"):
				var duration: float = 1.8
				if trajectory_map != null and trajectory_map.has_method("get_reveal_duration"):
					duration = trajectory_map.get_reveal_duration()
				refresh_sound.start_refresh(duration)

		ActionType.TRAJECTORY_ZOOM:
			is_held = true
			repeat_started = false
			repeat_timer = zoom_repeat_initial_delay
			_apply_zoom_step(true)

		ActionType.TRAJECTORY_CENTER_CYCLE:
			_play_shared_button_audio()

			if trajectory_map != null and trajectory_map.has_method("cycle_center_mode"):
				trajectory_map.cycle_center_mode()
				
		ActionType.TRAJECTORY_DISPLAY_MODE_CYCLE:
			_play_shared_button_audio()

			if trajectory_map != null and trajectory_map.has_method("cycle_display_mode"):
				trajectory_map.cycle_display_mode()
				

func release() -> void:
	_resolve_refs()

	match action_type:
		ActionType.LEVER:
			_stop_rotation_whir()

			if lever == null:
				return

			if mode == ButtonMode.PLUS:
				if lever.has_method("release_plus"):
					lever.release_plus()
			else:
				if lever.has_method("release_minus"):
					lever.release_minus()

		ActionType.THRUST:
			if ship == null:
				return
			if ship.has_method("set_thrust_held"):
				ship.set_thrust_held(false)

			if player != null and player.has_method("set_thrust_feedback_active"):
				player.set_thrust_feedback_active(false)

		ActionType.TRAJECTORY_REFRESH:
			pass
			
		ActionType.TRAJECTORY_DISPLAY_MODE_CYCLE:
			pass
			
		ActionType.TRAJECTORY_ZOOM:
			is_held = false
			repeat_started = false
			repeat_timer = 0.0

		ActionType.TRAJECTORY_CENTER_CYCLE:
			pass
