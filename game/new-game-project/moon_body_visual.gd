extends BodyRender
class_name MoonBodyVisual

const HAZE_SHADER := preload("res://planetary_haze_shell.gdshader")

@export var haze_color: Color = Color(0.95, 0.84, 0.58, 1.0)
@export var haze_relative_scale: float = 1.015

var haze_material: ShaderMaterial
var sun_light: DirectionalLight3D

func _ready() -> void:
	super._ready()
	_setup_haze()
	_resolve_sun_light()
	_update_haze_light_dir()

func _process(delta: float) -> void:
	super._process(delta)
	_update_haze_light_dir()

func _setup_haze() -> void:
	haze_material = ShaderMaterial.new()
	haze_material.shader = HAZE_SHADER
	haze_material.set_shader_parameter("haze_color", haze_color)
	haze_material.set_shader_parameter("rim_exponent", 2.0)
	haze_material.set_shader_parameter("rim_strength", 0.62)
	haze_material.set_shader_parameter("alpha_scale", 0.12)
	haze_material.set_shader_parameter("emission_strength", 0.04)
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
