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

@export var lever_path: NodePath
@export var mode: ButtonMode = ButtonMode.PLUS

@export var ship_path: NodePath
@export var trajectory_map_path: NodePath

var lever: Node
var ship: Node
var trajectory_map: Node

func _ready() -> void:
	lever = get_node_or_null(lever_path)
	ship = get_node_or_null(ship_path)
	trajectory_map = get_node_or_null(trajectory_map_path)

func press() -> void:
	match action_type:
		ActionType.LEVER:
			if lever == null:
				return

			if mode == ButtonMode.PLUS:
				if lever.has_method("press_plus"):
					lever.press_plus()
			else:
				if lever.has_method("press_minus"):
					lever.press_minus()

		ActionType.THRUST:
			if ship == null:
				return

			if ship.has_method("set_thrust_held"):
				ship.set_thrust_held(true)

		ActionType.TRAJECTORY_REFRESH:
			if trajectory_map == null:
				return

			if trajectory_map.has_method("request_refresh"):
				trajectory_map.request_refresh()

		ActionType.TRAJECTORY_ZOOM:
			if trajectory_map == null:
				return

			if mode == ButtonMode.PLUS:
				if trajectory_map.has_method("zoom_in"):
					trajectory_map.zoom_in()
			else:
				if trajectory_map.has_method("zoom_out"):
					trajectory_map.zoom_out()

func release() -> void:
	match action_type:
		ActionType.LEVER:
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

		ActionType.TRAJECTORY_REFRESH:
			pass

		ActionType.TRAJECTORY_ZOOM:
			pass
