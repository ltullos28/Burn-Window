extends CanvasLayer

const CHECKBOX_SIZE := Vector2(18.0, 18.0)
const COMPLETE_COLOR := Color(0.98, 0.59, 0.17, 1.0)
const INCOMPLETE_COLOR := Color(0.05, 0.07, 0.1, 1.0)
const PANEL_WIDTH := 326.0
const EDGE_MARGIN := 44.0
const TAB_HANDLE_WIDTH := 76.0
const TAB_HANDLE_HEIGHT := 28.0
const TAB_TOGGLE_DURATION := 0.26

@onready var root_margin: Control = $RootMargin
@onready var checklist_panel: PanelContainer = $RootMargin/ChecklistPanel
@onready var tab_handle: PanelContainer = $RootMargin/TabHandle
@onready var tab_handle_label: Label = $RootMargin/TabHandle/Label
@onready var header_label: Label = $RootMargin/ChecklistPanel/PanelMargin/ChecklistVBox/HeaderLabel
@onready var subheader_label: Label = $RootMargin/ChecklistPanel/PanelMargin/ChecklistVBox/SubheaderLabel
@onready var difficulty_label: Label = $RootMargin/ChecklistPanel/PanelMargin/ChecklistVBox/DifficultyLabel
@onready var objectives_vbox: VBoxContainer = $RootMargin/ChecklistPanel/PanelMargin/ChecklistVBox/ObjectivesVBox
@onready var checklist_vbox: VBoxContainer = $RootMargin/ChecklistPanel/PanelMargin/ChecklistVBox

var _row_widgets: Dictionary = {}
var _collapsed: bool = false
var _panel_tween: Tween = null
var _expanded_offsets: Dictionary = {}
var _collapsed_offsets: Dictionary = {}


func _ready() -> void:
	tab_handle_label.text = "TAB"
	if not tab_handle.gui_input.is_connected(_on_tab_handle_gui_input):
		tab_handle.gui_input.connect(_on_tab_handle_gui_input)
	_connect_session_signals()
	if not get_viewport().size_changed.is_connected(_on_viewport_size_changed):
		get_viewport().size_changed.connect(_on_viewport_size_changed)
	var settings: Node = _settings()
	if settings != null and not settings.settings_changed.is_connected(_on_settings_changed):
		settings.settings_changed.connect(_on_settings_changed)
	_rebuild_rows()
	_refresh_display()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event: InputEventKey = event
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_TAB:
			_set_collapsed(not _collapsed, true)
			get_viewport().set_input_as_handled()


func _physics_process(_delta: float) -> void:
	var session: Node = _session()
	if session == null:
		return

	for objective in session.get_current_objectives():
		var body_name: StringName = objective.get("body_name", &"")
		if body_name == &"":
			continue

		var body_position: Vector3 = SimulationState.get_body_position(body_name)
		var body_radius: float = SimulationState.get_body_radius(body_name)
		var surface_altitude: float = maxf((SimulationState.ship_pos - body_position).length() - body_radius, 0.0)
		session.register_closest_approach_sample(body_name, surface_altitude)

	session.update_live_objectives(_delta)


func _connect_session_signals() -> void:
	var session: Node = _session()
	if session == null:
		return

	if not session.mission_reset.is_connected(_on_mission_reset):
		session.mission_reset.connect(_on_mission_reset)
	if not session.mission_progress_changed.is_connected(_on_mission_progress_changed):
		session.mission_progress_changed.connect(_on_mission_progress_changed)
	if not session.difficulty_changed.is_connected(_on_difficulty_changed):
		session.difficulty_changed.connect(_on_difficulty_changed)


func _on_mission_reset() -> void:
	_rebuild_rows()
	_refresh_display()


func _on_mission_progress_changed() -> void:
	_refresh_display()


func _on_difficulty_changed(_difficulty: StringName) -> void:
	_rebuild_rows()
	_refresh_display()


func _on_settings_changed() -> void:
	_refresh_layout()


func _on_viewport_size_changed() -> void:
	_refresh_layout()


func _on_tab_handle_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_button: InputEventMouseButton = event
		if mouse_button.button_index == MOUSE_BUTTON_LEFT and mouse_button.pressed:
			_set_collapsed(not _collapsed, true)
			get_viewport().set_input_as_handled()


func _rebuild_rows() -> void:
	_row_widgets.clear()

	for child in objectives_vbox.get_children():
		child.queue_free()

	var session: Node = _session()
	if session == null:
		return

	for objective in session.get_current_objectives():
		var objective_id: String = str(objective.get("id", ""))

		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.alignment = BoxContainer.ALIGNMENT_BEGIN
		row.add_theme_constant_override("separation", 10)

		var checkbox_panel := Panel.new()
		checkbox_panel.custom_minimum_size = CHECKBOX_SIZE
		checkbox_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER

		var checkbox_fill := ColorRect.new()
		checkbox_fill.name = "Fill"
		checkbox_fill.anchor_right = 1.0
		checkbox_fill.anchor_bottom = 1.0
		checkbox_fill.offset_left = 3.0
		checkbox_fill.offset_top = 3.0
		checkbox_fill.offset_right = -3.0
		checkbox_fill.offset_bottom = -3.0
		checkbox_fill.color = COMPLETE_COLOR
		checkbox_fill.visible = false
		checkbox_panel.add_child(checkbox_fill)

		var text_vbox := VBoxContainer.new()
		text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var title := Label.new()
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text_vbox.add_child(title)
		row.add_child(checkbox_panel)
		row.add_child(text_vbox)
		objectives_vbox.add_child(row)

		_row_widgets[objective_id] = {
			"fill": checkbox_fill,
			"title": title,
		}

	_refresh_layout()


func _refresh_display() -> void:
	var session: Node = _session()
	if session == null:
		return

	header_label.text = "Objectives"
	subheader_label.text = "Complete all objectives before fuel or oxygen run dry."
	difficulty_label.text = "Difficulty: %s" % session.get_difficulty_label()

	for objective in session.get_current_objectives():
		var objective_id: String = str(objective.get("id", ""))
		if not _row_widgets.has(objective_id):
			continue

		var row: Dictionary = _row_widgets[objective_id]
		var title: Label = row.get("title")
		var fill: ColorRect = row.get("fill")
		var completed: bool = bool(objective.get("completed", false))

		title.text = session.get_objective_title(objective)
		if completed:
			title.modulate = Color(0.96, 0.9, 0.77, 1.0)
		else:
			title.modulate = Color(0.92, 0.92, 0.92, 1.0)

		fill.visible = completed
		fill.color = COMPLETE_COLOR if completed else INCOMPLETE_COLOR

	if session.are_all_objectives_complete():
		header_label.text = "Objectives Complete"

	_refresh_layout()


func _refresh_layout() -> void:
	if root_margin == null or checklist_panel == null or checklist_vbox == null or tab_handle == null:
		return

	var ui_scale: float = maxf(_get_ui_surface_scale(), 0.0001)
	var anchored_margin: float = EDGE_MARGIN * ui_scale
	var content_size: Vector2 = checklist_vbox.get_combined_minimum_size()
	var panel_width: float = PANEL_WIDTH
	var panel_height: float = maxf(content_size.y + 28.0, 124.0)
	checklist_panel.custom_minimum_size = Vector2(panel_width, panel_height)

	root_margin.anchor_left = 0.0
	root_margin.anchor_right = 0.0
	root_margin.anchor_top = 1.0
	root_margin.anchor_bottom = 1.0
	var expanded_left: float = anchored_margin
	var expanded_right: float = expanded_left + panel_width
	var expanded_bottom: float = -anchored_margin
	var expanded_top: float = expanded_bottom - panel_height
	var collapse_shift: float = panel_height
	_expanded_offsets = {
		"left": expanded_left,
		"right": expanded_right,
		"top": expanded_top,
		"bottom": expanded_bottom,
	}
	_collapsed_offsets = {
		"left": expanded_left,
		"right": expanded_right,
		"top": expanded_top + collapse_shift,
		"bottom": expanded_bottom + collapse_shift,
	}
	if _panel_tween == null:
		_apply_root_offsets(_collapsed_offsets if _collapsed else _expanded_offsets)

	# Scale the checklist as one surface while preserving a stable bottom-left screen margin.
	root_margin.scale = Vector2.ONE * ui_scale
	root_margin.pivot_offset = Vector2(0.0, panel_height)

	tab_handle.anchor_left = 0.5
	tab_handle.anchor_right = 0.5
	tab_handle.anchor_top = 0.0
	tab_handle.anchor_bottom = 0.0
	tab_handle.custom_minimum_size = Vector2(TAB_HANDLE_WIDTH, TAB_HANDLE_HEIGHT)
	tab_handle.offset_left = -TAB_HANDLE_WIDTH * 0.5
	tab_handle.offset_right = TAB_HANDLE_WIDTH * 0.5
	tab_handle.offset_top = -TAB_HANDLE_HEIGHT
	tab_handle.offset_bottom = 0.0
	tab_handle.pivot_offset = Vector2(TAB_HANDLE_WIDTH * 0.5, TAB_HANDLE_HEIGHT)
	tab_handle.z_index = 1


func _set_collapsed(collapsed: bool, animate: bool) -> void:
	if _collapsed == collapsed and _panel_tween == null:
		return
	_collapsed = collapsed
	var target_offsets: Dictionary = _collapsed_offsets if _collapsed else _expanded_offsets
	if target_offsets.is_empty():
		return
	if _panel_tween != null:
		_panel_tween.kill()
		_panel_tween = null
	if not animate:
		_apply_root_offsets(target_offsets)
		return
	_panel_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_panel_tween.tween_property(root_margin, "offset_top", float(target_offsets.get("top", root_margin.offset_top)), TAB_TOGGLE_DURATION)
	_panel_tween.parallel().tween_property(root_margin, "offset_bottom", float(target_offsets.get("bottom", root_margin.offset_bottom)), TAB_TOGGLE_DURATION)
	_panel_tween.finished.connect(_on_panel_tween_finished, CONNECT_ONE_SHOT)


func _on_panel_tween_finished() -> void:
	_panel_tween = null


func _apply_root_offsets(offsets: Dictionary) -> void:
	root_margin.offset_left = float(offsets.get("left", root_margin.offset_left))
	root_margin.offset_right = float(offsets.get("right", root_margin.offset_right))
	root_margin.offset_top = float(offsets.get("top", root_margin.offset_top))
	root_margin.offset_bottom = float(offsets.get("bottom", root_margin.offset_bottom))


func _session() -> Node:
	return get_node_or_null("/root/GameSession")


func _settings() -> Node:
	return get_node_or_null("/root/GameSettings")


func _get_ui_compensation_scale() -> float:
	var settings: Node = _settings()
	if settings != null and settings.has_method("get_ui_compensation_scale"):
		return float(settings.get_ui_compensation_scale())
	return 1.0


func _get_ui_surface_scale() -> float:
	var settings: Node = _settings()
	if settings != null and settings.has_method("get_fixed_footprint_scale"):
		return float(settings.get_fixed_footprint_scale())
	return _get_ui_compensation_scale()
