extends Node3D

@export var star_count: int = 450
@export var radius: float = 6000.0
@export var min_scale: float = 0.025
@export var max_scale: float = 0.07
@export var bright_star_chance: float = 0.08
@export var bright_scale_multiplier: float = 1.8
@export var target_path: NodePath

var target: Node3D

func _ready() -> void:
	target = get_node_or_null(target_path) as Node3D

	var multimesh_instance: MultiMeshInstance3D = get_node("MultiMeshInstance3D") as MultiMeshInstance3D
	if multimesh_instance == null:
		push_error("Starfield: Missing child node named MultiMeshInstance3D")
		return

	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.instance_count = star_count

	# Tiny spheres instead of billboards to avoid flicker/pop/sorting issues
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 6
	sphere.rings = 4
	multimesh.mesh = sphere

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()

	for i: int in range(star_count):
		var dir: Vector3 = Vector3(
			rng.randf_range(-1.0, 1.0),
			rng.randf_range(-1.0, 1.0),
			rng.randf_range(-1.0, 1.0)
		).normalized()

		var pos: Vector3 = dir * radius

		# Bias sizes toward smaller stars without making them microscopic
		var t: float = rng.randf()
		t = t * t
		var scale_amount: float = lerpf(min_scale, max_scale, t)

		var is_bright: bool = rng.randf() < bright_star_chance
		if is_bright:
			scale_amount *= bright_scale_multiplier

		var star_basis: Basis = Basis().scaled(Vector3.ONE * scale_amount)
		var star_transform: Transform3D = Transform3D(star_basis, pos)
		multimesh.set_instance_transform(i, star_transform)

		var color: Color = Color(1.0, 1.0, 1.0, 1.0)

		var tint_roll: float = rng.randf()
		if tint_roll < 0.08:
			color = Color(1.0, 0.95, 0.85, 1.0)
		elif tint_roll < 0.14:
			color = Color(0.85, 0.92, 1.0, 1.0)

		if is_bright:
			color = color.lerp(Color.WHITE, 0.35)

		multimesh.set_instance_color(i, color)

	multimesh_instance.multimesh = multimesh

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.no_depth_test = false
	mat.disable_receive_shadows = true
	mat.disable_ambient_light = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	multimesh_instance.material_override = mat


func _process(_delta: float) -> void:
	if target != null:
		global_position = target.global_position
