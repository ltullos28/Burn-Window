extends CanvasLayer

@export var panel_title: String = "Tester Notice"
@export_multiline var panel_body: String = "Thank you for testing the game!\n\nThe normal and hard difficulties currently have infinite resources because I need to gather play data.\n\nYou can help me by screenshotting the screen shown at the end of your run. o7"

@onready var overlay: ColorRect = $Overlay
@onready var center_container: CenterContainer = $CenterContainer
@onready var panel: PanelContainer = $CenterContainer/Panel
@onready var title_label: Label = $CenterContainer/Panel/PanelMargin/VBox/TitleLabel
@onready var body_label: Label = $CenterContainer/Panel/PanelMargin/VBox/BodyLabel
@onready var continue_button: Button = $CenterContainer/Panel/PanelMargin/VBox/ContinueButton

var _showing_notice: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 105
	visible = false

	# Make the popup UI remain interactive while the tree is paused.
	overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	center_container.process_mode = Node.PROCESS_MODE_ALWAYS
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	continue_button.process_mode = Node.PROCESS_MODE_ALWAYS

	title_label.text = panel_title
	body_label.text = panel_body

	if continue_button != null and not continue_button.pressed.is_connected(_dismiss_notice):
		continue_button.pressed.connect(_dismiss_notice)

	if not get_viewport().size_changed.is_connected(_on_viewport_size_changed):
		get_viewport().size_changed.connect(_on_viewport_size_changed)

	var settings: Node = _settings()
	if settings != null and not settings.settings_changed.is_connected(_on_settings_changed):
		settings.settings_changed.connect(_on_settings_changed)

	_refresh_display_scale()
	call_deferred("_evaluate_notice_visibility")


func _unhandled_input(event: InputEvent) -> void:
	if not _showing_notice:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_ESCAPE:
				_dismiss_notice()
				get_viewport().set_input_as_handled()
				return

	get_viewport().set_input_as_handled()


func _evaluate_notice_visibility() -> void:
	var session: Node = get_node_or_null("/root/GameSession")
	if session == null or not session.has_method("get_selected_difficulty"):
		return

	var difficulty: StringName = session.get_selected_difficulty()
	if difficulty != &"normal" and difficulty != &"hard":
		return

	_show_notice()


func _show_notice() -> void:
	_showing_notice = true
	visible = true
	overlay.visible = true
	panel.visible = true
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	continue_button.grab_focus()


func _dismiss_notice() -> void:
	if not _showing_notice:
		return

	_showing_notice = false
	visible = false
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _settings() -> Node:
	return get_node_or_null("/root/GameSettings")


func _on_settings_changed() -> void:
	_refresh_display_scale()


func _on_viewport_size_changed() -> void:
	_refresh_display_scale()


func _refresh_display_scale() -> void:
	if panel == null:
		return

	var panel_scale: float = minf(
		_get_fit_scale_for_centered_control(panel, 48.0),
		_get_fixed_screen_footprint_scale()
	)
	panel.scale = Vector2.ONE * panel_scale
	panel.pivot_offset = panel.size * 0.5


func _get_fixed_screen_footprint_scale() -> float:
	var settings: Node = _settings()
	if settings != null and settings.has_method("get_fixed_footprint_scale"):
		return float(settings.get_fixed_footprint_scale())
	return 1.0


func _get_fit_scale_for_centered_control(control: Control, padding: float = 48.0) -> float:
	if control == null:
		return 1.0

	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var available_size: Vector2 = Vector2(
		maxf(viewport_size.x - padding, 1.0),
		maxf(viewport_size.y - padding, 1.0)
	)
	var control_size: Vector2 = control.size
	if control_size.x <= 0.0 or control_size.y <= 0.0:
		control_size = control.get_combined_minimum_size()

	var fit_scale_x: float = available_size.x / maxf(control_size.x, 1.0)
	var fit_scale_y: float = available_size.y / maxf(control_size.y, 1.0)
	return clampf(minf(fit_scale_x, fit_scale_y), 0.1, 8.0)
