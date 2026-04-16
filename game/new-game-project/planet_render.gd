extends BodyRender

const HAZE_SHADER := preload("res://planetary_haze_shell.gdshader")

var atmosphere_material: ShaderMaterial
var sun_light: DirectionalLight3D
var atmosphere_shell: MeshInstance3D

func _ready() -> void:
	body_name = &"planet"
	super._ready()
	_setup_planet_atmosphere()
	_resolve_sun_light()
	_update_atmosphere_light_dir()
	_apply_planet_effects_setting()
	var settings = _settings()
	if settings != null and not settings.settings_changed.is_connected(_apply_planet_effects_setting):
		settings.settings_changed.connect(_apply_planet_effects_setting)

func _process(delta: float) -> void:
	super._process(delta)
	_update_atmosphere_light_dir()

func _setup_planet_atmosphere() -> void:
	atmosphere_material = ShaderMaterial.new()
	atmosphere_material.shader = HAZE_SHADER
	atmosphere_material.set_shader_parameter("haze_color", Color(0.96, 0.62, 0.42, 1.0))
	atmosphere_material.set_shader_parameter("rim_exponent", 2.3)
	atmosphere_material.set_shader_parameter("rim_strength", 1.0)
	atmosphere_material.set_shader_parameter("alpha_scale", 0.28)
	atmosphere_material.set_shader_parameter("emission_strength", 0.12)
	atmosphere_material.set_shader_parameter("terminator_softness", 0.08)
	atmosphere_material.set_shader_parameter("terminator_bias", 0.01)
	atmosphere_material.set_shader_parameter("night_floor", 0.0)
	atmosphere_material.set_shader_parameter("radial_falloff", 1.8)
	atmosphere_shell = ensure_visual_shell(&"AtmosphereShell", 1.012, atmosphere_material)

func _resolve_sun_light() -> void:
	if sun_light == null:
		sun_light = get_tree().root.find_child("DirectionalLight3D", true, false) as DirectionalLight3D

func _update_atmosphere_light_dir() -> void:
	if atmosphere_material == null:
		return
	_resolve_sun_light()
	if sun_light == null:
		return
	var light_dir: Vector3 = sun_light.global_transform.basis.z.normalized()
	atmosphere_material.set_shader_parameter("light_dir_world", light_dir)


func _apply_planet_effects_setting() -> void:
	var settings = _settings()
	if atmosphere_shell != null:
		atmosphere_shell.visible = settings == null or settings.planet_effects_enabled


func _settings():
	return get_node_or_null("/root/GameSettings")
