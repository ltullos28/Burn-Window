extends Node3D

const GenericBodyRenderScript := preload("res://generic_body_render.gd")

func _ready() -> void:
	_sync_child_visuals()

func _sync_child_visuals() -> void:
	var desired_visual_names: Dictionary = {}
	for definition in SimulationState.get_active_body_definitions():
		if definition == null or not definition.enabled:
			continue
		if _has_external_visual_for_body(definition.body_name):
			continue

		var visual_name: String = "%sVisual" % String(definition.body_name).capitalize()
		desired_visual_names[visual_name] = true
		_ensure_body_visual(visual_name, definition)

	for child in get_children():
		if not desired_visual_names.has(child.name):
			child.queue_free()

func _ensure_body_visual(visual_name: String, definition: CelestialBodyDefinition) -> void:
	var visual_root: Node = get_node_or_null(NodePath(visual_name))
	var body_render: BodyRender = null

	if visual_root == null:
		visual_root = _instantiate_visual_root(definition)
		visual_root.name = visual_name

		body_render = _find_body_render_node(visual_root)
		if body_render == null:
			push_warning("ChildBodyVisuals: visual '%s' for body '%s' has no BodyRender." % [visual_name, String(definition.body_name)])
			return
		body_render.body_name = definition.body_name
		add_child(visual_root)
	else:
		body_render = _find_body_render_node(visual_root)

	if body_render == null:
		push_warning("ChildBodyVisuals: visual '%s' for body '%s' has no BodyRender." % [visual_name, String(definition.body_name)])
		return

	body_render.body_name = definition.body_name

func _instantiate_visual_root(definition: CelestialBodyDefinition) -> Node:
	if definition.visual_scene != null:
		var instantiated: Node = definition.visual_scene.instantiate()
		if instantiated != null:
			return instantiated

	var fallback := GenericBodyRenderScript.new() as GenericBodyRender
	if fallback != null:
		return fallback
	return Node3D.new()

func _has_external_visual_for_body(body_name: StringName) -> bool:
	var root: Node = get_tree().current_scene
	if root == null:
		root = get_tree().root
	return _find_external_body_render(root, body_name)

func _find_external_body_render(node: Node, body_name: StringName) -> bool:
	if node == self:
		return false

	if node is BodyRender:
		var body_render := node as BodyRender
		if body_render.body_name == body_name and not is_ancestor_of(node):
			return true

	for child in node.get_children():
		if _find_external_body_render(child, body_name):
			return true
	return false

func _find_body_render_node(node: Node) -> BodyRender:
	if node is BodyRender:
		return node as BodyRender
	for child in node.get_children():
		var found: BodyRender = _find_body_render_node(child)
		if found != null:
			return found
	return null
