extends CanvasLayer

# TEMP DEBUG TOOL:
# This overlay is intentionally isolated so we can remove it later without
# touching the actual mission or failure flow.

@export var debug_enabled: bool = true
@export var fade_duration: float = 0.75
@export_file("*.tscn") var title_scene_path: String = "res://scenes/menu.tscn"
@export var ship_path: NodePath = NodePath("../Ship")
@export var ship_resources_path: NodePath = NodePath("../Ship/Cockpit/TankMaster")
@export var pause_menu_path: NodePath = NodePath("../PauseMenu")
@export var trajectory_map_path: NodePath = NodePath("../Ship/Cockpit/IBM_5155/TrajectoryViewport/TrajectoryMap")

@onready var fade_rect: ColorRect = $FadeRect
@onready var ui_root: Control = $UIRoot
@onready var title_label: Label = $UIRoot/CenterContainer/Panel/PanelMargin/VBox/TitleLabel
@onready var subtitle_label: Label = $UIRoot/CenterContainer/Panel/PanelMargin/VBox/SubtitleLabel
@onready var stats_label: Label = $UIRoot/CenterContainer/Panel/PanelMargin/VBox/StatsLabel
@onready var resource_label: Label = $UIRoot/CenterContainer/Panel/PanelMargin/VBox/ResourceLabel
@onready var score_label: Label = $UIRoot/CenterContainer/Panel/PanelMargin/VBox/ScoreLabel
@onready var stars_label: Label = $UIRoot/CenterContainer/Panel/PanelMargin/VBox/StarsLabel
@onready var restart_button: Button = $UIRoot/CenterContainer/Panel/PanelMargin/VBox/ButtonRow/RestartButton
@onready var menu_button: Button = $UIRoot/CenterContainer/Panel/PanelMargin/VBox/ButtonRow/MenuButton
@onready var hint_label: Label = $UIRoot/CenterContainer/Panel/PanelMargin/VBox/HintLabel

var _ship: Node = null
var _ship_resources: Node = null
var _pause_menu: Node = null
var _trajectory_map: Node = null
var _sequence_active: bool = false
var _fade_elapsed: float = 0.0
var _tracked_thrust_time_sim_seconds: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 110
	_resolve_refs()
	_bind_buttons()
	_connect_session_signals()
	if not get_viewport().size_changed.is_connected(_on_viewport_size_changed):
		get_viewport().size_changed.connect(_on_viewport_size_changed)
	var settings: Node = _settings()
	if settings != null and not settings.settings_changed.is_connected(_on_settings_changed):
		settings.settings_changed.connect(_on_settings_changed)
	_refresh_display_scale()
	_reset_overlay_state()


func _process(delta: float) -> void:
	if not _sequence_active:
		return

	_fade_elapsed = minf(_fade_elapsed + delta, maxf(fade_duration, 0.001))
	var progress: float = clampf(_fade_elapsed / maxf(fade_duration, 0.001), 0.0, 1.0)
	var eased: float = 1.0 - pow(1.0 - progress, 3.0)

	fade_rect.color.a = lerpf(0.0, 0.92, eased)
	ui_root.modulate.a = eased


func _physics_process(delta: float) -> void:
	if not debug_enabled or _sequence_active:
		return

	var session: Node = _session()
	if session == null or not bool(session.get("mission_active")):
		return

	_resolve_refs()

	var sim_delta: float = SimulationState.get_current_sim_delta(delta)
	if sim_delta <= 0.0:
		return

	if _ship != null and bool(_ship.get("thrust_held")):
		_tracked_thrust_time_sim_seconds += sim_delta


func _input(event: InputEvent) -> void:
	if not _sequence_active:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_R:
				_restart_run()
			KEY_M:
				_return_to_menu()
			KEY_ESCAPE:
				get_viewport().set_input_as_handled()
				return

	get_viewport().set_input_as_handled()


func _bind_buttons() -> void:
	if restart_button != null and not restart_button.pressed.is_connected(_restart_run):
		restart_button.pressed.connect(_restart_run)
	if menu_button != null and not menu_button.pressed.is_connected(_return_to_menu):
		menu_button.pressed.connect(_return_to_menu)


func _connect_session_signals() -> void:
	var session: Node = _session()
	if session == null:
		return

	if not session.mission_progress_changed.is_connected(_on_mission_progress_changed):
		session.mission_progress_changed.connect(_on_mission_progress_changed)
	if not session.mission_reset.is_connected(_on_mission_reset):
		session.mission_reset.connect(_on_mission_reset)


func _on_mission_progress_changed() -> void:
	if not debug_enabled or _sequence_active:
		return

	var session: Node = _session()
	if session == null or not session.are_all_objectives_complete():
		return

	_begin_sequence()


func _on_mission_reset() -> void:
	_reset_overlay_state()


func _begin_sequence() -> void:
	_resolve_refs()
	_sequence_active = true
	_fade_elapsed = 0.0
	_update_summary_text()
	fade_rect.visible = true
	ui_root.visible = true
	ui_root.modulate.a = 0.0
	_set_pause_menu_locked(true)
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	restart_button.grab_focus()


func _update_summary_text() -> void:
	var session: Node = _session()
	var difficulty_text: String = ""
	if session != null and session.has_method("get_difficulty_label"):
		difficulty_text = "Difficulty: %s" % session.get_difficulty_label()

	var mission_time_seconds: float = maxf(SimulationState.sim_time, 0.0)
	var thrust_time_seconds: float = maxf(_tracked_thrust_time_sim_seconds, 0.0)
	var fuel_left: float = 0.0
	var fuel_max: float = 0.0
	var oxygen_left: float = 0.0
	var oxygen_max: float = 0.0

	if _ship_resources != null:
		fuel_left = float(_ship_resources.get("fuel_current"))
		fuel_max = float(_ship_resources.get("max_fuel"))
		oxygen_left = float(_ship_resources.get("oxygen_current"))
		oxygen_max = float(_ship_resources.get("max_oxygen"))

	var score_summary: Dictionary = _compute_score_summary(fuel_left, oxygen_left)

	title_label.text = "Mission Complete"
	if difficulty_text.is_empty():
		subtitle_label.text = "Temporary balance readout."
	else:
		subtitle_label.text = "Temporary balance readout.\n%s" % difficulty_text
	stats_label.text = "Mission Time: %s\nThrust Time: %s" % [
		_format_sim_time(mission_time_seconds),
		_format_sim_time(thrust_time_seconds),
	]
	resource_label.text = "Fuel Left: %.1f / %.1f\nO2 Left: %.1f / %.1f" % [
		fuel_left,
		fuel_max,
		oxygen_left,
		oxygen_max,
	]
	score_label.text = "Score: %d / 100" % int(round(float(score_summary.get("score", 0.0))))
	stars_label.text = "Rating: %d Star%s" % [
		int(score_summary.get("stars", 1)),
		"s" if int(score_summary.get("stars", 1)) != 1 else "",
	]
	hint_label.text = "Press R to restart this run.\nPress M to return to the title screen."


func _restart_run() -> void:
	_set_pause_menu_locked(false)
	get_tree().paused = false
	_reset_overlay_state()
	SimulationState.reset()
	if _trajectory_map != null and _trajectory_map.has_method("request_refresh"):
		_trajectory_map.request_refresh()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _return_to_menu() -> void:
	_set_pause_menu_locked(false)
	get_tree().paused = false
	_reset_overlay_state()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().change_scene_to_file(title_scene_path)


func _reset_overlay_state() -> void:
	_sequence_active = false
	_fade_elapsed = 0.0
	_tracked_thrust_time_sim_seconds = 0.0
	fade_rect.visible = false
	fade_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	ui_root.visible = false
	ui_root.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_set_pause_menu_locked(false)


func _set_pause_menu_locked(locked: bool) -> void:
	if _pause_menu == null:
		return
	_pause_menu.set_process_unhandled_input(not locked)


func _resolve_refs() -> void:
	if _ship == null:
		_ship = get_node_or_null(ship_path)
	if _ship_resources == null:
		_ship_resources = get_node_or_null(ship_resources_path)
	if _pause_menu == null:
		_pause_menu = get_node_or_null(pause_menu_path)
	if _trajectory_map == null:
		_trajectory_map = get_node_or_null(trajectory_map_path)


func _session() -> Node:
	return get_node_or_null("/root/GameSession")


func _settings() -> Node:
	return get_node_or_null("/root/GameSettings")


func _format_sim_time(total_seconds: float) -> String:
	var clamped_seconds: float = maxf(total_seconds, 0.0)
	var minutes: int = int(floor(clamped_seconds / 60.0))
	var seconds: float = clamped_seconds - (float(minutes) * 60.0)
	return "%dm %.1fs" % [minutes, seconds]


func _compute_score_summary(fuel_left: float, oxygen_left: float) -> Dictionary:
	var fuel_full_score_remaining: float = 16.0
	var oxygen_full_score_remaining: float = 500.0
	var fuel_weight: float = 50.0
	var oxygen_weight: float = 50.0
	var three_star_score: float = 75.0
	var two_star_score: float = 40.0

	var session: Node = _session()
	if session != null and session.has_method("get_active_scoring_settings"):
		var scoring_settings: Dictionary = session.get_active_scoring_settings()
		if scoring_settings.has("fuel_full_score_remaining"):
			fuel_full_score_remaining = float(scoring_settings.get("fuel_full_score_remaining", fuel_full_score_remaining))
		if scoring_settings.has("oxygen_full_score_remaining"):
			oxygen_full_score_remaining = float(scoring_settings.get("oxygen_full_score_remaining", oxygen_full_score_remaining))
		if scoring_settings.has("fuel_weight"):
			fuel_weight = float(scoring_settings.get("fuel_weight", fuel_weight))
		if scoring_settings.has("oxygen_weight"):
			oxygen_weight = float(scoring_settings.get("oxygen_weight", oxygen_weight))
		if scoring_settings.has("three_star_score"):
			three_star_score = float(scoring_settings.get("three_star_score", three_star_score))
		if scoring_settings.has("two_star_score"):
			two_star_score = float(scoring_settings.get("two_star_score", two_star_score))

	var fuel_points: float = fuel_weight * clampf(fuel_left / maxf(fuel_full_score_remaining, 0.001), 0.0, 1.0)
	var oxygen_points: float = oxygen_weight * clampf(oxygen_left / maxf(oxygen_full_score_remaining, 0.001), 0.0, 1.0)
	var total_score: float = clampf(fuel_points + oxygen_points, 0.0, fuel_weight + oxygen_weight)

	var stars: int = 1
	if total_score >= three_star_score:
		stars = 3
	elif total_score >= two_star_score:
		stars = 2

	return {
		"score": total_score,
		"stars": stars,
	}


func _on_settings_changed() -> void:
	_refresh_display_scale()


func _on_viewport_size_changed() -> void:
	_refresh_display_scale()


func _refresh_display_scale() -> void:
	if ui_root == null:
		return

	var ui_scale: float = 1.0
	var settings: Node = _settings()
	if settings != null and settings.has_method("get_ui_compensation_scale"):
		ui_scale = float(settings.get_ui_compensation_scale())

	ui_root.scale = Vector2.ONE * ui_scale
	ui_root.pivot_offset = ui_root.size * 0.5
