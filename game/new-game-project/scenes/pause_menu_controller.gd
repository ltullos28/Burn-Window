extends CanvasLayer

const PAGE_MAIN := &"main"
const PAGE_SETTINGS := &"settings"

@export_file("*.tscn") var title_scene_path: String = "res://scenes/menu.tscn"
@export var menu_title_text: String = "Paused"
@export_multiline var resume_text: String = "Simulation paused. Resume flight, adjust settings, or return to the title screen."

var _active_page: StringName = PAGE_MAIN
var _synchronizing_settings_ui: bool = false
var _pending_settings: Dictionary = {}
var _committed_settings: Dictionary = {}
var _has_unsaved_settings: bool = false
var _pending_resume_after_prompt: bool = false
var _pending_page_after_prompt: StringName = StringName()
var _pending_focus_after_prompt: Button = null
var _pending_return_to_menu_after_prompt: bool = false

@onready var overlay: ColorRect = $Overlay
@onready var menu_shell: PanelContainer = $UIRoot/MenuShell
@onready var title_label: Label = $UIRoot/MenuShell/MenuMargin/MenuVBox/TitleLabel
@onready var resume_button: Button = $UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/ButtonColumn/ResumeButton
@onready var settings_button: Button = $UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/ButtonColumn/SettingsButton
@onready var return_to_menu_button: Button = $UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/ButtonColumn/ReturnToMenuButton
@onready var quit_button: Button = $UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/ButtonColumn/QuitButton
@onready var details_title_label: Label = $UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/DetailsTitleLabel
@onready var details_body_label: Label = $UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/DetailsBodyLabel
@onready var settings_panel: VBoxContainer = $UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/SettingsPanel
@onready var settings_intro_label: Label = $UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/SettingsPanel/SettingsIntroLabel
@onready var fullscreen_toggle: CheckButton = $UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/SettingsPanel/SettingsScroll/SettingsScrollContent/VideoGrid/FullscreenToggle
@onready var fullscreen_value_label: Label = $UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/SettingsPanel/SettingsScroll/SettingsScrollContent/VideoGrid/FullscreenValueLabel
@onready var resolution_option_button: OptionButton = $UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/SettingsPanel/SettingsScroll/SettingsScrollContent/VideoGrid/ResolutionOptionButton
@onready var resolution_value_label: Label = $UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/SettingsPanel/SettingsScroll/SettingsScrollContent/VideoGrid/ResolutionValueLabel
@onready var camera_fov_slider: HSlider = $UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/SettingsPanel/SettingsScroll/SettingsScrollContent/VideoGrid/CameraFovSlider
@onready var camera_fov_value_label: Label = $UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/SettingsPanel/SettingsScroll/SettingsScrollContent/VideoGrid/CameraFovValueLabel
@onready var planet_effects_toggle: CheckButton = $UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/SettingsPanel/SettingsScroll/SettingsScrollContent/VideoGrid/PlanetEffectsToggle
@onready var planet_effects_value_label: Label = $UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/SettingsPanel/SettingsScroll/SettingsScrollContent/VideoGrid/PlanetEffectsValueLabel
@onready var mouse_sensitivity_slider: HSlider = $UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/SettingsPanel/SettingsScroll/SettingsScrollContent/ControlsGrid/MouseSensitivitySlider
@onready var mouse_sensitivity_value_label: Label = $UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/SettingsPanel/SettingsScroll/SettingsScrollContent/ControlsGrid/MouseSensitivityValueLabel
@onready var invert_y_toggle: CheckButton = $UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/SettingsPanel/SettingsScroll/SettingsScrollContent/ControlsGrid/InvertYToggle
@onready var invert_y_value_label: Label = $UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/SettingsPanel/SettingsScroll/SettingsScrollContent/ControlsGrid/InvertYValueLabel
@onready var mouse_smoothing_toggle: CheckButton = $UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/SettingsPanel/SettingsScroll/SettingsScrollContent/ControlsGrid/MouseSmoothingToggle
@onready var mouse_smoothing_value_label: Label = $UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/SettingsPanel/SettingsScroll/SettingsScrollContent/ControlsGrid/MouseSmoothingValueLabel
@onready var mouse_smoothing_detail_margin: MarginContainer = $UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/SettingsPanel/SettingsScroll/SettingsScrollContent/MouseSmoothingDetailMargin
@onready var mouse_smoothing_slider: HSlider = $UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/SettingsPanel/SettingsScroll/SettingsScrollContent/MouseSmoothingDetailMargin/MouseSmoothingDetailGrid/MouseSmoothingSlider
@onready var mouse_smoothing_slider_value_label: Label = $UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/SettingsPanel/SettingsScroll/SettingsScrollContent/MouseSmoothingDetailMargin/MouseSmoothingDetailGrid/MouseSmoothingValueLabel
@onready var camera_shake_toggle: CheckButton = $UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/SettingsPanel/SettingsScroll/SettingsScrollContent/GameplayGrid/CameraShakeToggle
@onready var camera_shake_value_label: Label = $UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/SettingsPanel/SettingsScroll/SettingsScrollContent/GameplayGrid/CameraShakeValueLabel
@onready var engine_volume_slider: HSlider = $UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/SettingsPanel/SettingsScroll/SettingsScrollContent/AudioGrid/EngineVolumeSlider
@onready var engine_volume_value_label: Label = $UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/SettingsPanel/SettingsScroll/SettingsScrollContent/AudioGrid/EngineVolumeValueLabel
@onready var ambient_volume_slider: HSlider = $UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/SettingsPanel/SettingsScroll/SettingsScrollContent/AudioGrid/AmbientVolumeSlider
@onready var ambient_volume_value_label: Label = $UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/SettingsPanel/SettingsScroll/SettingsScrollContent/AudioGrid/AmbientVolumeValueLabel
@onready var ui_volume_slider: HSlider = $UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/SettingsPanel/SettingsScroll/SettingsScrollContent/AudioGrid/UiVolumeSlider
@onready var ui_volume_value_label: Label = $UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/SettingsPanel/SettingsScroll/SettingsScrollContent/AudioGrid/UiVolumeValueLabel
@onready var reset_settings_button: Button = $UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/SettingsPanel/SettingsButtonRow/ResetSettingsButton
@onready var apply_settings_button: Button = $UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/SettingsPanel/SettingsButtonRow/ApplySettingsButton
@onready var settings_prompt_overlay: ColorRect = $UIRoot/SettingsPromptOverlay
@onready var settings_prompt_panel: PanelContainer = $UIRoot/SettingsPromptOverlay/SettingsPromptPanel
@onready var settings_prompt_apply_button: Button = $UIRoot/SettingsPromptOverlay/SettingsPromptPanel/SettingsPromptMargin/SettingsPromptVBox/SettingsPromptButtonRow/SettingsPromptApplyButton
@onready var settings_prompt_discard_button: Button = $UIRoot/SettingsPromptOverlay/SettingsPromptPanel/SettingsPromptMargin/SettingsPromptVBox/SettingsPromptButtonRow/SettingsPromptDiscardButton
@onready var button_click_player: AudioStreamPlayer = $PauseButtonPlayer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	title_label.text = menu_title_text
	_bind_buttons()
	_bind_settings_controls()
	_load_committed_settings()
	_pending_settings = _committed_settings.duplicate(true)
	_refresh_settings_controls()
	_show_page(PAGE_MAIN)
	if not get_viewport().size_changed.is_connected(_on_viewport_size_changed):
		get_viewport().size_changed.connect(_on_viewport_size_changed)
	if menu_shell != null and not menu_shell.resized.is_connected(_on_menu_shell_resized):
		menu_shell.resized.connect(_on_menu_shell_resized)
	var settings = _settings()
	if settings != null and not settings.settings_changed.is_connected(_on_settings_changed):
		settings.settings_changed.connect(_on_settings_changed)
	_refresh_display_scale()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		if event.is_action_pressed("ui_cancel"):
			_open_pause_menu()
			get_viewport().set_input_as_handled()
		return
	if settings_prompt_overlay.visible:
		return
	if event.is_action_pressed("ui_cancel"):
		if _active_page == PAGE_SETTINGS:
			_request_show_page(PAGE_MAIN, resume_button)
		else:
			_resume_game()
		get_viewport().set_input_as_handled()

func _open_pause_menu() -> void:
	get_tree().paused = true
	visible = true
	overlay.visible = true
	settings_prompt_overlay.visible = false
	settings_prompt_panel.scale = Vector2.ONE
	menu_shell.scale = Vector2.ONE
	_pending_resume_after_prompt = false
	_pending_page_after_prompt = StringName()
	_pending_focus_after_prompt = null
	_pending_return_to_menu_after_prompt = false
	_load_committed_settings()
	_pending_settings = _committed_settings.duplicate(true)
	_has_unsaved_settings = false
	_refresh_settings_controls()
	_show_page(PAGE_MAIN)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	call_deferred("_finalize_pause_menu_open")

func _resume_game() -> void:
	visible = false
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _show_page(page_key: StringName) -> void:
	_active_page = page_key
	details_title_label.text = "Resume" if page_key == PAGE_MAIN else "Settings"
	details_body_label.visible = page_key == PAGE_MAIN
	settings_panel.visible = page_key == PAGE_SETTINGS
	details_body_label.text = resume_text

func _bind_buttons() -> void:
	_connect_confirmed_press(resume_button, _on_resume_pressed)
	_connect_confirmed_press(settings_button, func() -> void:
		_on_page_button_pressed(PAGE_SETTINGS, settings_button)
	)
	_connect_confirmed_press(return_to_menu_button, _on_return_to_menu_pressed)
	_connect_confirmed_press(quit_button, _on_quit_pressed)

func _bind_settings_controls() -> void:
	mouse_sensitivity_slider.value_changed.connect(_on_mouse_sensitivity_changed)
	mouse_smoothing_toggle.toggled.connect(_on_mouse_smoothing_toggled)
	mouse_smoothing_slider.value_changed.connect(_on_mouse_smoothing_slider_changed)
	camera_fov_slider.value_changed.connect(_on_camera_fov_changed)
	fullscreen_toggle.toggled.connect(_on_fullscreen_toggled)
	resolution_option_button.item_selected.connect(_on_resolution_selected)
	engine_volume_slider.value_changed.connect(_on_engine_volume_changed)
	ambient_volume_slider.value_changed.connect(_on_ambient_volume_changed)
	ui_volume_slider.value_changed.connect(_on_ui_volume_changed)
	invert_y_toggle.toggled.connect(_on_invert_y_toggled)
	camera_shake_toggle.toggled.connect(_on_camera_shake_toggled)
	planet_effects_toggle.toggled.connect(_on_planet_effects_toggled)
	_connect_confirmed_press(reset_settings_button, _on_reset_settings_pressed)
	_connect_confirmed_press(apply_settings_button, _on_apply_settings_pressed)
	_connect_confirmed_press(settings_prompt_apply_button, _on_settings_prompt_apply_pressed)
	_connect_confirmed_press(settings_prompt_discard_button, _on_settings_prompt_discard_pressed)

func _connect_confirmed_press(button: Button, callback: Callable) -> void:
	if button == null or not callback.is_valid():
		return
	if button.has_signal("confirmed_pressed"):
		button.connect("confirmed_pressed", callback)
	else:
		button.pressed.connect(callback)

func _play_button_click() -> void:
	if button_click_player == null or button_click_player.stream == null:
		return
	button_click_player.stop()
	button_click_player.play()

func _on_resume_pressed() -> void:
	if _active_page == PAGE_SETTINGS and _has_unsaved_settings:
		_pending_resume_after_prompt = true
		_show_settings_leave_prompt()
		return
	_play_button_click()
	_resume_game()

func _on_page_button_pressed(page_key: StringName, source_button: Button) -> void:
	if settings_prompt_overlay.visible:
		return
	_play_button_click()
	_request_show_page(page_key, source_button)

func _request_show_page(page_key: StringName, focus_button: Button = null) -> void:
	if _active_page == PAGE_SETTINGS and page_key != PAGE_SETTINGS and _has_unsaved_settings:
		_pending_page_after_prompt = page_key
		_pending_focus_after_prompt = focus_button
		_show_settings_leave_prompt()
		return
	_show_page(page_key)
	if focus_button != null:
		focus_button.grab_focus()

func _on_return_to_menu_pressed() -> void:
	if _active_page == PAGE_SETTINGS and _has_unsaved_settings:
		_pending_return_to_menu_after_prompt = true
		_show_settings_leave_prompt()
		return
	_play_button_click()
	_return_to_menu()

func _return_to_menu() -> void:
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().change_scene_to_file(title_scene_path)

func _on_quit_pressed() -> void:
	_play_button_click()
	get_tree().paused = false
	get_tree().quit()

func _show_settings_leave_prompt() -> void:
	_set_settings_prompt_modal_state(true)
	_reset_settings_prompt_layout()
	settings_prompt_overlay.visible = true
	settings_prompt_panel.visible = true
	settings_prompt_overlay.move_to_front()
	settings_prompt_panel.move_to_front()
	get_viewport().gui_release_focus()
	call_deferred("_finalize_settings_prompt_open")

func _hide_settings_leave_prompt() -> void:
	settings_prompt_overlay.visible = false
	settings_prompt_panel.visible = false
	_set_settings_prompt_modal_state(false)

func _finish_pending_settings_exit() -> void:
	if _pending_resume_after_prompt:
		_pending_resume_after_prompt = false
		_resume_game()
		return
	if _pending_return_to_menu_after_prompt:
		_pending_return_to_menu_after_prompt = false
		_return_to_menu()
		return
	if _pending_page_after_prompt != StringName():
		var target_page := _pending_page_after_prompt
		var target_focus := _pending_focus_after_prompt
		_pending_page_after_prompt = StringName()
		_pending_focus_after_prompt = null
		_show_page(target_page)
		if target_focus != null:
			target_focus.grab_focus()

func _on_settings_prompt_apply_pressed() -> void:
	_play_button_click()
	_apply_pending_settings(false)
	_hide_settings_leave_prompt()
	_finish_pending_settings_exit()

func _on_settings_prompt_discard_pressed() -> void:
	_play_button_click()
	_pending_settings = _committed_settings.duplicate(true)
	_has_unsaved_settings = false
	_refresh_settings_controls()
	_hide_settings_leave_prompt()
	_finish_pending_settings_exit()

func _load_committed_settings() -> void:
	var settings = _settings()
	if settings == null:
		return
	_committed_settings = settings.to_dictionary()


func _on_settings_changed() -> void:
	_refresh_display_scale()

func _refresh_settings_controls() -> void:
	var settings = _settings()
	if settings == null or _pending_settings.is_empty():
		return
	_synchronizing_settings_ui = true
	mouse_sensitivity_slider.value = settings.mouse_sensitivity_to_display_level(float(_pending_settings.get("mouse_sensitivity", settings.mouse_sensitivity)))
	mouse_smoothing_toggle.button_pressed = bool(_pending_settings.get("mouse_smoothing_enabled", settings.mouse_smoothing_enabled))
	mouse_smoothing_slider.value = settings.mouse_smoothing_to_display_level(float(_pending_settings.get("mouse_smoothing_speed", settings.mouse_smoothing_speed)))
	camera_fov_slider.value = float(_pending_settings.get("camera_fov", settings.camera_fov))
	_refresh_resolution_options(settings)
	fullscreen_toggle.button_pressed = bool(_pending_settings.get("fullscreen_enabled", settings.fullscreen_enabled))
	resolution_option_button.select(settings.get_resolution_option_index(_pending_settings.get("resolution", settings.resolution)))
	engine_volume_slider.value = float(_pending_settings.get("engine_volume", settings.engine_volume))
	ambient_volume_slider.value = float(_pending_settings.get("ambient_volume", settings.ambient_volume))
	ui_volume_slider.value = float(_pending_settings.get("ui_volume", settings.ui_volume))
	invert_y_toggle.button_pressed = bool(_pending_settings.get("invert_y_look", settings.invert_y_look))
	camera_shake_toggle.button_pressed = bool(_pending_settings.get("camera_shake_enabled", settings.camera_shake_enabled))
	planet_effects_toggle.button_pressed = bool(_pending_settings.get("planet_effects_enabled", settings.planet_effects_enabled))
	mouse_sensitivity_value_label.text = "%d" % int(round(mouse_sensitivity_slider.value))
	mouse_smoothing_value_label.text = "On" if mouse_smoothing_toggle.button_pressed else "Off"
	mouse_smoothing_slider_value_label.text = "%d" % int(round(mouse_smoothing_slider.value))
	camera_fov_value_label.text = "%d" % int(round(camera_fov_slider.value))
	fullscreen_value_label.text = "On" if fullscreen_toggle.button_pressed else "Off"
	resolution_value_label.text = settings.resolution_to_string(_pending_settings.get("resolution", settings.resolution))
	engine_volume_value_label.text = "%d%%" % int(round(engine_volume_slider.value * 100.0))
	ambient_volume_value_label.text = "%d%%" % int(round(ambient_volume_slider.value * 100.0))
	ui_volume_value_label.text = "%d%%" % int(round(ui_volume_slider.value * 100.0))
	invert_y_value_label.text = "On" if invert_y_toggle.button_pressed else "Off"
	camera_shake_value_label.text = "On" if camera_shake_toggle.button_pressed else "Off"
	planet_effects_value_label.text = "On" if planet_effects_toggle.button_pressed else "Off"
	mouse_smoothing_detail_margin.visible = mouse_smoothing_toggle.button_pressed
	settings_intro_label.text = "Adjust your settings."
	apply_settings_button.disabled = not _has_unsaved_settings
	reset_settings_button.disabled = _pending_settings == settings.default_dictionary()
	_synchronizing_settings_ui = false

func _mark_settings_dirty() -> void:
	_has_unsaved_settings = _pending_settings != _committed_settings
	apply_settings_button.disabled = not _has_unsaved_settings
	var settings = _settings()
	if settings != null:
		reset_settings_button.disabled = _pending_settings == settings.default_dictionary()

func _apply_pending_settings(play_click: bool = true) -> void:
	var settings = _settings()
	if settings == null:
		return
	if play_click:
		_play_button_click()
	settings.apply_dictionary(_pending_settings, true)
	_committed_settings = _pending_settings.duplicate(true)
	_has_unsaved_settings = false
	_refresh_settings_controls()
	_refresh_display_scale()

func _on_mouse_sensitivity_changed(value: float) -> void:
	if _synchronizing_settings_ui:
		return
	var settings = _settings()
	if settings == null:
		return
	_pending_settings["mouse_sensitivity"] = settings.display_level_to_mouse_sensitivity(value)
	mouse_sensitivity_value_label.text = "%d" % int(round(value))
	_mark_settings_dirty()


func _on_mouse_smoothing_toggled(value: bool) -> void:
	if _synchronizing_settings_ui:
		return
	_pending_settings["mouse_smoothing_enabled"] = value
	mouse_smoothing_value_label.text = "On" if value else "Off"
	mouse_smoothing_detail_margin.visible = value
	_mark_settings_dirty()


func _on_mouse_smoothing_slider_changed(value: float) -> void:
	if _synchronizing_settings_ui:
		return
	var settings = _settings()
	if settings == null:
		return
	_pending_settings["mouse_smoothing_speed"] = settings.display_level_to_mouse_smoothing(value)
	mouse_smoothing_slider_value_label.text = "%d" % int(round(value))
	_mark_settings_dirty()

func _on_camera_fov_changed(value: float) -> void:
	if _synchronizing_settings_ui:
		return
	_pending_settings["camera_fov"] = value
	camera_fov_value_label.text = "%d" % int(round(value))
	_mark_settings_dirty()

func _on_engine_volume_changed(value: float) -> void:
	if _synchronizing_settings_ui:
		return
	_pending_settings["engine_volume"] = value
	engine_volume_value_label.text = "%d%%" % int(round(value * 100.0))
	_mark_settings_dirty()

func _on_fullscreen_toggled(value: bool) -> void:
	if _synchronizing_settings_ui:
		return
	_pending_settings["fullscreen_enabled"] = value
	fullscreen_value_label.text = "On" if value else "Off"
	_mark_settings_dirty()

func _on_resolution_selected(index: int) -> void:
	if _synchronizing_settings_ui:
		return
	var settings = _settings()
	if settings == null:
		return
	var resolution: Vector2i = settings.get_resolution_from_index(index)
	_pending_settings["resolution"] = resolution
	resolution_value_label.text = settings.resolution_to_string(resolution)
	_mark_settings_dirty()

func _on_ambient_volume_changed(value: float) -> void:
	if _synchronizing_settings_ui:
		return
	_pending_settings["ambient_volume"] = value
	ambient_volume_value_label.text = "%d%%" % int(round(value * 100.0))
	_mark_settings_dirty()

func _on_ui_volume_changed(value: float) -> void:
	if _synchronizing_settings_ui:
		return
	_pending_settings["ui_volume"] = value
	ui_volume_value_label.text = "%d%%" % int(round(value * 100.0))
	_mark_settings_dirty()

func _on_invert_y_toggled(value: bool) -> void:
	if _synchronizing_settings_ui:
		return
	_pending_settings["invert_y_look"] = value
	invert_y_value_label.text = "On" if value else "Off"
	_mark_settings_dirty()

func _on_camera_shake_toggled(value: bool) -> void:
	if _synchronizing_settings_ui:
		return
	_pending_settings["camera_shake_enabled"] = value
	camera_shake_value_label.text = "On" if value else "Off"
	_mark_settings_dirty()

func _on_planet_effects_toggled(value: bool) -> void:
	if _synchronizing_settings_ui:
		return
	_pending_settings["planet_effects_enabled"] = value
	planet_effects_value_label.text = "On" if value else "Off"
	_mark_settings_dirty()

func _on_reset_settings_pressed() -> void:
	var settings = _settings()
	if settings == null:
		return
	_play_button_click()
	var defaults: Dictionary = settings.default_dictionary()
	_has_unsaved_settings = false
	_pending_settings = defaults.duplicate(true)
	_committed_settings = defaults.duplicate(true)
	settings.apply_dictionary(defaults, true)
	_pending_settings = defaults.duplicate(true)
	_refresh_settings_controls()
	reset_settings_button.grab_focus()

func _on_apply_settings_pressed() -> void:
	if not _has_unsaved_settings:
		return
	_apply_pending_settings()
	apply_settings_button.grab_focus()

func _set_settings_prompt_modal_state(active: bool) -> void:
	var locked_buttons: Array[Button] = [resume_button, settings_button, return_to_menu_button, quit_button, reset_settings_button, apply_settings_button]
	for button in locked_buttons:
		if button != null:
			button.disabled = active
			button.focus_mode = Control.FOCUS_NONE if active else Control.FOCUS_ALL
	var locked_toggles: Array[CheckButton] = [invert_y_toggle, mouse_smoothing_toggle, camera_shake_toggle, planet_effects_toggle]
	locked_toggles.append(fullscreen_toggle)
	for toggle in locked_toggles:
		if toggle != null:
			toggle.disabled = active
			toggle.focus_mode = Control.FOCUS_NONE if active else Control.FOCUS_ALL
	var locked_sliders: Array[HSlider] = [mouse_sensitivity_slider, mouse_smoothing_slider, camera_fov_slider, engine_volume_slider, ambient_volume_slider, ui_volume_slider]
	for slider in locked_sliders:
		if slider != null:
			slider.editable = not active
			slider.focus_mode = Control.FOCUS_NONE if active else Control.FOCUS_ALL
			slider.mouse_filter = Control.MOUSE_FILTER_IGNORE if active else Control.MOUSE_FILTER_STOP
	if resolution_option_button != null:
		resolution_option_button.disabled = active
		resolution_option_button.focus_mode = Control.FOCUS_NONE if active else Control.FOCUS_ALL
		resolution_option_button.mouse_filter = Control.MOUSE_FILTER_IGNORE if active else Control.MOUSE_FILTER_STOP
	settings_prompt_apply_button.disabled = false
	settings_prompt_discard_button.disabled = false
	settings_prompt_apply_button.focus_mode = Control.FOCUS_ALL
	settings_prompt_discard_button.focus_mode = Control.FOCUS_ALL
	if not active:
		_refresh_settings_controls()

func _settings():
	return get_node_or_null("/root/GameSettings")

func _refresh_resolution_options(settings) -> void:
	if settings == null or resolution_option_button == null:
		return
	resolution_option_button.clear()
	var options: Array[Dictionary] = settings.get_resolution_options()
	for option in options:
		resolution_option_button.add_item(str(option.get("label", "")))


func _on_viewport_size_changed() -> void:
	_refresh_display_scale()


func _on_menu_shell_resized() -> void:
	_refresh_display_scale()


func _refresh_display_scale() -> void:
	var shell_scale: float = minf(
		_get_fit_scale_for_centered_control(menu_shell, 36.0),
		_get_fixed_screen_footprint_scale()
	)
	_apply_centered_scale(menu_shell, shell_scale)
	_reset_settings_prompt_layout()


func _finalize_pause_menu_open() -> void:
	_refresh_display_scale()
	resume_button.grab_focus()


func _finalize_settings_prompt_open() -> void:
	_reset_settings_prompt_layout()
	settings_prompt_panel.move_to_front()
	settings_prompt_apply_button.grab_focus()


func _apply_centered_scale(control: Control, ui_scale: float) -> void:
	if control == null:
		return

	control.scale = Vector2.ONE * ui_scale
	control.pivot_offset = control.size * 0.5


func _reset_settings_prompt_layout() -> void:
	if settings_prompt_panel == null:
		return

	var prompt_scale: float = _get_fixed_screen_footprint_scale()
	var half_size := Vector2(240.0, 110.0)

	settings_prompt_panel.anchor_left = 0.5
	settings_prompt_panel.anchor_top = 0.5
	settings_prompt_panel.anchor_right = 0.5
	settings_prompt_panel.anchor_bottom = 0.5
	settings_prompt_panel.offset_left = -half_size.x
	settings_prompt_panel.offset_top = -half_size.y
	settings_prompt_panel.offset_right = half_size.x
	settings_prompt_panel.offset_bottom = half_size.y
	settings_prompt_panel.scale = Vector2.ONE * prompt_scale
	settings_prompt_panel.pivot_offset = half_size


func _get_ui_compensation_scale() -> float:
	var settings = _settings()
	if settings != null and settings.has_method("get_ui_compensation_scale"):
		return float(settings.get_ui_compensation_scale())
	return 1.0


func _get_fixed_screen_footprint_scale() -> float:
	var settings = _settings()
	if settings == null:
		return 1.0

	if settings.has_method("get_fixed_footprint_scale"):
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
