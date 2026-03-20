extends Node3D
class_name BodyRender

@export var body_name: StringName = &"planet"
@export var mesh_root_path: NodePath
@export var mesh_base_radius: float = 0.0

@export var render_distance_scale: float = 1.0
@export var render_radius_scale: float = 1.0

var mesh_root: Node3D
var warned_missing_body: bool = false

func _ready() -> void:
	_sanitize_settings()
	mesh_root = _resolve_mesh_root()
	_apply_scale()
	_update_render_transform()

func _physics_process(_delta: float) -> void:
	_update_render_transform()

func _process(_delta: float) -> void:
	_update_render_transform()

func _update_render_transform() -> void:
	if not SimulationState.has_body(body_name):
		if not warned_missing_body:
			push_warning("BodyRender: unknown body '%s'." % String(body_name))
			warned_missing_body = true
		return

	warned_missing_body = false
	global_position = (SimulationState.get_body_position(body_name) - SimulationState.ship_pos) * render_distance_scale
	_apply_scale()

func _apply_scale() -> void:
	if mesh_root == null or not SimulationState.has_body(body_name):
		return

	# In the parent-Node3D + child-mesh setup, the parent owns orbital placement.
	# Keep the visual mesh centered so old baked local offsets do not shove the body away.
	mesh_root.position = Vector3.ZERO

	var target_radius: float = SimulationState.get_body_radius(body_name) * render_radius_scale
	var effective_base_radius: float = _get_effective_mesh_base_radius()
	var s: float = target_radius / max(effective_base_radius, 0.001)
	mesh_root.scale = Vector3.ONE * s

func _sanitize_settings() -> void:
	if mesh_base_radius < 0.0:
		mesh_base_radius = 0.0
	if render_distance_scale <= 0.0:
		render_distance_scale = 1.0
	if render_radius_scale <= 0.0:
		render_radius_scale = 1.0

func _get_effective_mesh_base_radius() -> float:
	if mesh_base_radius > 0.0:
		return mesh_base_radius
	if mesh_root is MeshInstance3D:
		var mesh_instance := mesh_root as MeshInstance3D
		if mesh_instance.mesh != null:
			var aabb: AABB = mesh_instance.get_aabb()
			return maxf(maxf(aabb.size.x, aabb.size.y), aabb.size.z) * 0.5
	return 1.0

func ensure_visual_shell(shell_name: StringName, relative_scale: float, material: Material) -> MeshInstance3D:
	if mesh_root == null or not (mesh_root is MeshInstance3D):
		return null

	var source_mesh := mesh_root as MeshInstance3D
	var shell := mesh_root.get_node_or_null(NodePath(String(shell_name))) as MeshInstance3D
	if shell == null:
		shell = MeshInstance3D.new()
		shell.name = String(shell_name)
		mesh_root.add_child(shell)
		shell.owner = get_tree().edited_scene_root if Engine.is_editor_hint() else null

	shell.mesh = source_mesh.mesh
	shell.material_override = material
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shell.layers = source_mesh.layers
	shell.position = Vector3.ZERO
	shell.scale = Vector3.ONE * relative_scale
	return shell

func _resolve_mesh_root() -> Node3D:
	if not mesh_root_path.is_empty():
		var configured_root: Node3D = get_node_or_null(mesh_root_path) as Node3D
		if configured_root != null:
			return configured_root

	return _find_first_mesh_node(self)

func _find_first_mesh_node(root: Node) -> Node3D:
	for child in root.get_children():
		if child is MeshInstance3D:
			return child

	for child in root.get_children():
		var nested_match: Node3D = _find_first_mesh_node(child)
		if nested_match != null:
			return nested_match

	return null
