extends Node3D

enum FillAxis {
	X,
	Y,
	Z
}

enum AnchoredEdge {
	NEGATIVE,
	POSITIVE
}

@export var gauge_path: NodePath = NodePath("Gauge")
@export var fill_axis: FillAxis = FillAxis.Y
@export var anchored_edge: AnchoredEdge = AnchoredEdge.NEGATIVE
@export_range(2, 64, 1) var display_steps: int = 24
@export_range(0.0, 1.0, 0.001) var minimum_visible_ratio: float = 0.015
@export var hide_when_empty: bool = false

var _gauge: CSGBox3D
var _full_size: Vector3 = Vector3.ONE
var _full_position: Vector3 = Vector3.ZERO
var _dynamic_gauge_visual: MeshInstance3D
var _dynamic_gauge_mesh: BoxMesh
var _last_displayed_step: int = -1

func _ready() -> void:
	_resolve_gauge()
	if _gauge == null:
		return

	_full_size = _gauge.size
	_full_position = _gauge.position
	_build_dynamic_visual()
	set_fill_ratio(1.0)

func set_fill_ratio(value: float) -> void:
	_resolve_gauge()
	if _gauge == null:
		return
	_ensure_dynamic_visual()
	if _dynamic_gauge_visual == null or _dynamic_gauge_mesh == null:
		return

	var clamped_ratio: float = clampf(value, 0.0, 1.0)
	var step_count: int = max(display_steps, 2)
	var displayed_step: int = clampi(int(round(clamped_ratio * float(step_count))), 0, step_count)
	if displayed_step == _last_displayed_step:
		return
	_last_displayed_step = displayed_step

	var visible_ratio: float = float(displayed_step) / float(step_count)
	if clamped_ratio > 0.0:
		visible_ratio = max(visible_ratio, minimum_visible_ratio)

	var size := _full_size
	size[fill_axis] = _full_size[fill_axis] * visible_ratio

	var position := _full_position
	var missing_length: float = _full_size[fill_axis] - size[fill_axis]
	var center_offset: float = missing_length * 0.5
	if anchored_edge == AnchoredEdge.NEGATIVE:
		position[fill_axis] = _full_position[fill_axis] + center_offset
	else:
		position[fill_axis] = _full_position[fill_axis] - center_offset

	_dynamic_gauge_mesh.size = size
	_dynamic_gauge_visual.position = position
	_dynamic_gauge_visual.visible = not hide_when_empty or clamped_ratio > 0.0

func _resolve_gauge() -> void:
	if _gauge != null:
		return
	_gauge = get_node_or_null(gauge_path) as CSGBox3D
	if _gauge == null:
		push_warning("%s: gauge_path does not point to a CSGBox3D." % name)

func _ensure_dynamic_visual() -> void:
	if _dynamic_gauge_visual != null and _dynamic_gauge_mesh != null:
		return
	_build_dynamic_visual()

func _build_dynamic_visual() -> void:
	if _gauge == null:
		return

	_dynamic_gauge_visual = get_node_or_null("DynamicGaugeVisual") as MeshInstance3D
	if _dynamic_gauge_visual == null:
		_dynamic_gauge_visual = MeshInstance3D.new()
		_dynamic_gauge_visual.name = "DynamicGaugeVisual"
		add_child(_dynamic_gauge_visual)
		_dynamic_gauge_visual.owner = get_tree().edited_scene_root if Engine.is_editor_hint() else owner

	_dynamic_gauge_mesh = _dynamic_gauge_visual.mesh as BoxMesh
	if _dynamic_gauge_mesh == null:
		_dynamic_gauge_mesh = BoxMesh.new()
		_dynamic_gauge_visual.mesh = _dynamic_gauge_mesh

	_dynamic_gauge_visual.transform = _gauge.transform
	_dynamic_gauge_mesh.size = _gauge.size
	_dynamic_gauge_visual.material_override = _gauge.material
	_last_displayed_step = -1

	# Keep the original CSG gauge as an editor reference, but stop drawing it at runtime/editor playback
	# so we do not trigger expensive CSG rebuilds while animating the fill amount.
	_gauge.visible = false
