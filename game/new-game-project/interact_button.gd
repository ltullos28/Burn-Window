extends Area3D

enum ActionType {
	LEVER,
	THRUST,
	TRAJECTORY_REFRESH,
	TRAJECTORY_ZOOM
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

var lever: Node
var ship: Node
var trajectory_map: Node

var shared_button_audio: AudioStreamPlayer3D
var rotation_whir: Node
var refresh_sound: Node

func _ready() -> void:
	_resolve_refs()

func _resolve_refs() -> void:
	lever = get_node_or_null(lever_path)
	ship = get_node_or_null(ship_path)
	trajectory_map = get_node_or_null(trajectory_map_path)

	shared_button_audio = get_node_or_null(shared_button_audio_path) as AudioStreamPlayer3D
	rotation_whir = get_node_or_null(rotation_whir_path)
	refresh_sound = get_node_or_null(refresh_sound_path)

func _play_shared_button_audio() -> void:
	if shared_button_audio == null:
		return
	if shared_button_audio.stream == null:
		return
	shared_button_audio.play()

func press() -> void:
	_resolve_refs()
	_play_shared_button_audio()

	match action_type:
		ActionType.LEVER:
			if lever == null:
				push_warning("%s: lever_path is null on press." % name)
				return

			if rotation_whir != null and rotation_whir.has_method("press_input"):
				rotation_whir.press_input()

			if mode == ButtonMode.PLUS:
				if lever.has_method("press_plus"):
					lever.press_plus()
				else:
					push_warning("%s: lever has no press_plus()." % name)
			else:
				if lever.has_method("press_minus"):
					lever.press_minus()
				else:
					push_warning("%s: lever has no press_minus()." % name)

		ActionType.THRUST:
			if ship == null:
				push_warning("%s: ship_path is null on press." % name)
				return

			if ship.has_method("set_thrust_held"):
				ship.set_thrust_held(true)
			else:
				push_warning("%s: ship has no set_thrust_held()." % name)

		ActionType.TRAJECTORY_REFRESH:
			if trajectory_map != null and trajectory_map.has_method("request_refresh"):
				trajectory_map.request_refresh()
			else:
				push_warning("%s: trajectory_map missing request_refresh()." % name)

			if refresh_sound != null and refresh_sound.has_method("start_refresh"):
				var duration: float = 1.8
				if trajectory_map != null and trajectory_map.has_method("get_reveal_duration"):
					duration = trajectory_map.get_reveal_duration()
				refresh_sound.start_refresh(duration)

		ActionType.TRAJECTORY_ZOOM:
			if trajectory_map == null:
				push_warning("%s: trajectory_map_path is null on press." % name)
				return

			if mode == ButtonMode.PLUS:
				if trajectory_map.has_method("zoom_in"):
					trajectory_map.zoom_in()
				else:
					push_warning("%s: trajectory_map has no zoom_in()." % name)
			else:
				if trajectory_map.has_method("zoom_out"):
					trajectory_map.zoom_out()
				else:
					push_warning("%s: trajectory_map has no zoom_out()." % name)

func release() -> void:
	_resolve_refs()

	match action_type:
		ActionType.LEVER:
			if lever == null:
				push_warning("%s: lever_path is null on release." % name)
				return

			if rotation_whir != null and rotation_whir.has_method("release_input"):
				rotation_whir.release_input()

			if mode == ButtonMode.PLUS:
				if lever.has_method("release_plus"):
					lever.release_plus()
				else:
					push_warning("%s: lever has no release_plus()." % name)
			else:
				if lever.has_method("release_minus"):
					lever.release_minus()
				else:
					push_warning("%s: lever has no release_minus()." % name)

		ActionType.THRUST:
			if ship == null:
				push_warning("%s: ship_path is null on release." % name)
				return

			if ship.has_method("set_thrust_held"):
				ship.set_thrust_held(false)

		ActionType.TRAJECTORY_REFRESH:
			pass

		ActionType.TRAJECTORY_ZOOM:
			pass
