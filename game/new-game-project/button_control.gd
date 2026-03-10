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
	_resolve_ship()

func _resolve_ship() -> void:
	ship = get_node_or_null(ship_path)
	if ship == null:
		push_warning("%s: ship_path did not resolve." % name)

func _apply_to_ship() -> void:
	if ship == null:
		_resolve_ship()
		if ship == null:
			return

	match axis:
		Axis.PITCH:
			if ship.has_method("set_pitch_control"):
				ship.set_pitch_control(input_value)
		Axis.YAW:
			if ship.has_method("set_yaw_control"):
				ship.set_yaw_control(input_value)
				print(name, " applied YAW = ", input_value)
		Axis.ROLL:
			if ship.has_method("set_roll_control"):
				ship.set_roll_control(input_value)

func press_plus() -> void:
	input_value = 1.0
	print(name, " press_plus")
	_apply_to_ship()

func release_plus() -> void:
	if input_value > 0.0:
		input_value = 0.0
		print(name, " release_plus")
		_apply_to_ship()

func press_minus() -> void:
	input_value = -1.0
	print(name, " press_minus")
	_apply_to_ship()

func release_minus() -> void:
	if input_value < 0.0:
		input_value = 0.0
		print(name, " release_minus")
		_apply_to_ship()
