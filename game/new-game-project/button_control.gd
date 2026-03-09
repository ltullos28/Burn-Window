extends Node3D

enum Axis {
	PITCH,
	YAW,
	ROLL
}

@export var axis: Axis = Axis.PITCH
@export var ship_path: NodePath

var input_value: float = 0.0
var ship: Node

func _ready() -> void:
	ship = get_node_or_null(ship_path)

func _process(_delta: float) -> void:
	if ship == null:
		return

	match axis:
		Axis.PITCH:
			if ship.has_method("set_pitch_control"):
				ship.set_pitch_control(input_value)
		Axis.YAW:
			if ship.has_method("set_yaw_control"):
				ship.set_yaw_control(input_value)
		Axis.ROLL:
			if ship.has_method("set_roll_control"):
				ship.set_roll_control(input_value)

func press_plus() -> void:
	input_value = 1.0

func release_plus() -> void:
	if input_value > 0.0:
		input_value = 0.0

func press_minus() -> void:
	input_value = -1.0

func release_minus() -> void:
	if input_value < 0.0:
		input_value = 0.0
