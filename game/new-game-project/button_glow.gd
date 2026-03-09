extends Area3D

enum ButtonMode {
	PLUS,
	MINUS
}

@export var lever_path: NodePath
@export var mode: ButtonMode = ButtonMode.PLUS
@export var button_mesh_path: NodePath
@export var glow_strength: float = 4.0

var lever: Node
var mesh: MeshInstance3D
var base_emission: float = 0.0

func _ready() -> void:
	lever = get_node_or_null(lever_path)
	mesh = get_node_or_null(button_mesh_path) as MeshInstance3D

	if mesh != null and mesh.material_override != null:
		mesh.material_override = mesh.material_override.duplicate()
		var mat: StandardMaterial3D = mesh.material_override as StandardMaterial3D
		if mat != null:
			base_emission = mat.emission_energy_multiplier

func press() -> void:
	set_glow(true)

	if lever == null:
		return

	if mode == ButtonMode.PLUS:
		if lever.has_method("press_plus"):
			lever.press_plus()
	else:
		if lever.has_method("press_minus"):
			lever.press_minus()

func release() -> void:
	set_glow(false)

	if lever == null:
		return

	if mode == ButtonMode.PLUS:
		if lever.has_method("release_plus"):
			lever.release_plus()
	else:
		if lever.has_method("release_minus"):
			lever.release_minus()

func set_glow(active: bool) -> void:
	if mesh == null or mesh.material_override == null:
		return

	var mat: StandardMaterial3D = mesh.material_override as StandardMaterial3D
	if mat == null:
		return

	mat.emission_enabled = true

	if active:
		mat.emission_energy_multiplier = glow_strength
	else:
		mat.emission_energy_multiplier = base_emission
