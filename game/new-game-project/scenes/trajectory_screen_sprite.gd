extends Sprite3D

@export var viewport_path: NodePath

var trajectory_viewport: SubViewport

func _ready() -> void:
	trajectory_viewport = get_node_or_null(viewport_path) as SubViewport

	if trajectory_viewport == null:
		push_warning("TrajectoryDisplay: viewport_path is not assigned correctly.")
		return

	texture = trajectory_viewport.get_texture()
	billboard = BaseMaterial3D.BILLBOARD_DISABLED
