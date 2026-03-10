extends Node3D

@export var mesh_root_path: NodePath
@export var mesh_base_radius: float = 1.0

@export var render_distance_scale: float = 1.0
@export var render_radius_scale: float = 1.0

var mesh_root: Node3D

func _ready() -> void:
	mesh_root = get_node_or_null(mesh_root_path) as Node3D
	_apply_scale()

func _process(_delta: float) -> void:
	global_position = (SimulationState.moon_pos - SimulationState.ship_pos) * render_distance_scale
	_apply_scale()

func _apply_scale() -> void:
	if mesh_root == null:
		return

	var target_radius: float = SimulationState.moon_radius * render_radius_scale
	var s: float = target_radius / max(mesh_base_radius, 0.001)
	mesh_root.scale = Vector3.ONE * s
