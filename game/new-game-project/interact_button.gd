extends Area3D

enum ButtonMode {
	PLUS,
	MINUS
}

@export var lever_path: NodePath
@export var mode: ButtonMode = ButtonMode.PLUS

var lever: Node

func _ready() -> void:
	lever = get_node_or_null(lever_path)

func press() -> void:
	if lever == null:
		return

	if mode == ButtonMode.PLUS:
		if lever.has_method("press_plus"):
			lever.press_plus()
	else:
		if lever.has_method("press_minus"):
			lever.press_minus()

func release() -> void:
	if lever == null:
		return

	if mode == ButtonMode.PLUS:
		if lever.has_method("release_plus"):
			lever.release_plus()
	else:
		if lever.has_method("release_minus"):
			lever.release_minus()
