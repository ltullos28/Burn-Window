extends Area3D

@export var screen_mesh_path: NodePath
@export var zoom_target_path: NodePath
@export var highlight_color: Color = Color(1.0, 1.0, 1.0, 0.18)
@export var highlight_emission_color: Color = Color(1.0, 1.0, 1.0)
@export var highlight_emission_energy: float = 1.2

var screen_mesh: MeshInstance3D
var overlay_material: StandardMaterial3D
var zoom_target: Node3D


func _ready() -> void:
	screen_mesh = get_node_or_null(screen_mesh_path) as MeshInstance3D
	zoom_target = get_node_or_null(zoom_target_path) as Node3D

	if screen_mesh != null:
		overlay_material = StandardMaterial3D.new()
		overlay_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		overlay_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		overlay_material.albedo_color = Color(highlight_color.r, highlight_color.g, highlight_color.b, 0.0)
		overlay_material.emission_enabled = true
		overlay_material.emission = highlight_emission_color
		overlay_material.emission_energy_multiplier = 0.0
		overlay_material.no_depth_test = false
		overlay_material.cull_mode = BaseMaterial3D.CULL_DISABLED

		screen_mesh.material_overlay = overlay_material


func set_highlight(active: bool) -> void:
	if overlay_material == null:
		return

	if active:
		overlay_material.albedo_color = highlight_color
		overlay_material.emission_energy_multiplier = highlight_emission_energy
	else:
		overlay_material.albedo_color = Color(highlight_color.r, highlight_color.g, highlight_color.b, 0.0)
		overlay_material.emission_energy_multiplier = 0.0


func get_zoom_target() -> Node3D:
	return zoom_target
