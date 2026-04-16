extends BodyRender
class_name GenericBodyRender

const HAZE_SHADER := preload("res://planetary_haze_shell.gdshader")

@export var body_color: Color = Color(0.82, 0.84, 0.9, 1.0)
@export var emission_strength: float = 0.0
@export var haze_enabled: bool = true
@export var haze_color: Color = Color(0.84, 0.88, 1.0, 1.0)
@export var haze_relative_scale: float = 1.015
@export var haze_alpha_scale: float = 0.12

var surface_material: StandardMaterial3D
var haze_material: ShaderMaterial
var sun_light: DirectionalLight3D

func _ready() -> void:
	_ensure_mesh_root()
	_apply_surface_material()
	super._ready()
	if haze_enabled:
		_setup_haze()
	_resolve_sun_light()
	_update_haze_light_dir()

func _process(delta: float) -> void:
	super._process(delta)
	_update_haze_light_dir()

func _ensure_mesh_root() -> void:
	var existing_root: Node3D = get_node_or_null(mesh_root_path) as Node3D if not mesh_root_path.is_empty() else null
	if existing_root != null:
		return

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "MeshInstance3D"
	mesh_instance.mesh = SphereMesh.new()
	mesh_instance.layers = 2
	add_child(mesh_instance)
	mesh_root_path = NodePath("MeshInstance3D")

func _apply_surface_material() -> void:
	var target_root: MeshInstance3D = get_node_or_null(mesh_root_path) as MeshInstance3D
	if target_root == null:
		return

	surface_material = StandardMaterial3D.new()
	surface_material.albedo_color = body_color
	surface_material.roughness = 0.95
	surface_material.metallic = 0.0
	surface_material.emission_enabled = emission_strength > 0.001
	if surface_material.emission_enabled:
		surface_material.emission = body_color
		surface_material.emission_energy_multiplier = emission_strength
	target_root.material_override = surface_material

func _setup_haze() -> void:
	haze_material = ShaderMaterial.new()
	haze_material.shader = HAZE_SHADER
	haze_material.set_shader_parameter("haze_color", haze_color)
	haze_material.set_shader_parameter("rim_exponent", 2.0)
	haze_material.set_shader_parameter("rim_strength", 0.58)
	haze_material.set_shader_parameter("alpha_scale", haze_alpha_scale)
	haze_material.set_shader_parameter("emission_strength", 0.02)
	haze_material.set_shader_parameter("terminator_softness", 0.16)
	haze_material.set_shader_parameter("terminator_bias", 0.02)
	haze_material.set_shader_parameter("night_floor", 0.0)
	haze_material.set_shader_parameter("radial_falloff", 1.7)
	ensure_visual_shell(&"HazeShell", haze_relative_scale, haze_material)

func _resolve_sun_light() -> void:
	if sun_light == null:
		sun_light = get_tree().root.find_child("DirectionalLight3D", true, false) as DirectionalLight3D

func _update_haze_light_dir() -> void:
	if haze_material == null:
		return
	_resolve_sun_light()
	if sun_light == null:
		return
	var light_dir: Vector3 = sun_light.global_transform.basis.z.normalized()
	haze_material.set_shader_parameter("light_dir_world", light_dir)
