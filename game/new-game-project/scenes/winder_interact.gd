extends Area3D

@export var zoom_target_path: NodePath

var zoom_target: Node3D


func _ready():
	zoom_target = get_node_or_null(zoom_target_path)


func get_zoom_target():
	return zoom_target
