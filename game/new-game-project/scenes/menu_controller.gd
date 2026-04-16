extends Node3D

const PAGE_MAIN := &"main"
const PAGE_HOW_TO_PLAY := &"how_to_play"
const PAGE_SETTINGS := &"settings"
const PAGE_CREDITS := &"credits"

@export_file("*.tscn") var gameplay_scene_path: String = "res://scenes/main.tscn"
@export var gameplay_time_scale_on_start: float = 1.0
@export var fade_duration: float = 0.55
@export var title_text: String = "Burn Window"
@export var subtitle_text: String = "Quiet orbital dread from outside the cockpit."
@export var loading_text: String = "Loading..."
@export var reference_viewport_size: Vector2 = Vector2(1920.0, 1080.0)
@export var compact_menu_position: Vector2 = Vector2(1232.0, 110.0)
@export var compact_menu_size: Vector2 = Vector2(524.0, 778.0)
@export var expanded_menu_position: Vector2 = Vector2(760.0, 72.0)
@export var expanded_menu_size: Vector2 = Vector2(820.0, 860.0)
@export var menu_resize_duration: float = 0.28
@export_multiline var intro_page_text: String = "Set the exterior scene here, assign menu audio in the inspector, and use Start to fade into the current cockpit gameplay."
@export_multiline var how_to_play_text: String = "Current controls:\n- Mouse: click menu buttons\n- Keyboard: arrows / Tab to move focus, Enter to activate\n- In game: E to interact, WASD / R / F / C / X for ship controls, Esc toggles mouse capture"
@export var tutorial_page_1_title: String = "Page 1"
@export_multiline var tutorial_page_1_text: String = "Replace this with the first page of your tutorial book."
@export var tutorial_page_2_title: String = "Page 2"
@export_multiline var tutorial_page_2_text: String = "Replace this with the second page of your tutorial book."
@export var tutorial_page_3_title: String = "Page 3"
@export_multiline var tutorial_page_3_text: String = "Replace this with the third page of your tutorial book."
@export var tutorial_page_4_title: String = "Page 4"
@export_multiline var tutorial_page_4_text: String = "Replace this with the fourth page of your tutorial book."
@export var tutorial_page_5_title: String = "Page 5"
@export_multiline var tutorial_page_5_text: String = "Replace this with the fifth page of your tutorial book."
@export var tutorial_page_6_title: String = "Page 6"
@export_multiline var tutorial_page_6_text: String = "Replace this with the sixth page of your tutorial book."
@export var tutorial_page_7_title: String = "Page 7"
@export_multiline var tutorial_page_7_text: String = "Replace this with the seventh page of your tutorial book."
@export var tutorial_page_8_title: String = "Page 8"
@export_multiline var tutorial_page_8_text: String = "Replace this with the eighth page of your tutorial book."
@export var tutorial_page_9_title: String = "Page 9"
@export_multiline var tutorial_page_9_text: String = "Replace this with the ninth page of your tutorial book."
@export var tutorial_page_10_title: String = "Page 10"
@export_multiline var tutorial_page_10_text: String = "Replace this with the tenth page of your tutorial book."
@export var tutorial_page_11_title: String = "Page 11"
@export_multiline var tutorial_page_11_text: String = "Replace this with the eleventh page of your tutorial book."
@export_multiline var settings_text: String = "Settings are a placeholder in this first pass.\n\nAssign your ambient loop to MenuAmbientPlayer and your click sound to MenuButtonPlayer in the inspector. Replace this page with real sliders and toggles when you are ready."
@export_multiline var credits_text: String = "Burn Window\n\nCreated by Logan Tullos.\n\nPlaytesting:\nChicksen\nJronz\nxXHOBOXx"

var _page_titles: Dictionary = {}
var _page_bodies: Dictionary = {}
var _how_to_play_pages: Array[Dictionary] = []
var _active_page: StringName = PAGE_MAIN
var _is_transitioning: bool = false
var _how_to_play_page_index: int = 0
var _menu_shell_tween: Tween
var _synchronizing_settings_ui: bool = false
var _menu_base_ambient_volume_db: float = 0.0
var _menu_base_button_volume_db: float = 0.0
var _details_body_default_minimum_size: Vector2 = Vector2.ZERO
var _selected_difficulty: StringName = &"easy"
var _pending_settings: Dictionary = {}
var _committed_settings: Dictionary = {}
var _has_unsaved_settings: bool = false
var _pending_page_after_settings_prompt: StringName = StringName()
var _pending_focus_button_after_settings_prompt: Button = null
var _pending_quit_after_settings_prompt: bool = false

@onready var ui_root: Control = $CanvasLayer/UIRoot
@onready var menu_shell: Control = $CanvasLayer/UIRoot/MenuShell
@onready var title_label: Label = $CanvasLayer/UIRoot/MenuShell/MenuMargin/MenuVBox/TitleLabel
@onready var subtitle_label: Label = $CanvasLayer/UIRoot/MenuShell/MenuMargin/MenuVBox/SubtitleLabel
@onready var start_button: Button = $CanvasLayer/UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/ButtonColumn/StartButton
@onready var how_to_play_button: Button = $CanvasLayer/UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/ButtonColumn/HowToPlayButton
@onready var settings_button: Button = $CanvasLayer/UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/ButtonColumn/SettingsButton
@onready var credits_button: Button = $CanvasLayer/UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/ButtonColumn/CreditsButton
@onready var quit_button: Button = $CanvasLayer/UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/ButtonColumn/QuitButton
@onready var details_title_label: Label = $CanvasLayer/UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/DetailsTitleLabel
@onready var details_body_label: Label = $CanvasLayer/UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/DetailsBodyLabel
@onready var start_options_panel: VBoxContainer = $CanvasLayer/UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/StartOptionsPanel
@onready var easy_difficulty_button: Button = $CanvasLayer/UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/StartOptionsPanel/StartOptionsColumn/EasyDifficultyButton
@onready var normal_difficulty_button: Button = $CanvasLayer/UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/StartOptionsPanel/StartOptionsColumn/NormalDifficultyButton
@onready var hard_difficulty_button: Button = $CanvasLayer/UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/StartOptionsPanel/StartOptionsColumn/HardDifficultyButton
@onready var locked_difficulty_button: Button = $CanvasLayer/UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/StartOptionsPanel/StartOptionsColumn/LockedDifficultyButton
@onready var how_to_play_book: VBoxContainer = $CanvasLayer/UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/HowToPlayBook
@onready var tutorial_page_title_label: Label = $CanvasLayer/UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/HowToPlayBook/PageTitleLabel
@onready var tutorial_page_body_label: RichTextLabel = $CanvasLayer/UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/HowToPlayBook/PageBodyLabel
@onready var previous_page_button: Button = $CanvasLayer/UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/HowToPlayBook/PageNavRow/PreviousPageButton
@onready var page_indicator_label: Label = $CanvasLayer/UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/HowToPlayBook/PageNavRow/PageIndicatorLabel
@onready var next_page_button: Button = $CanvasLayer/UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/HowToPlayBook/PageNavRow/NextPageButton
@onready var settings_panel: VBoxContainer = $CanvasLayer/UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/SettingsPanel
@onready var settings_intro_label: Label = $CanvasLayer/UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/SettingsPanel/SettingsIntroLabel
@onready var fullscreen_toggle: CheckButton = $CanvasLayer/UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/SettingsPanel/SettingsScroll/SettingsScrollContent/VideoGrid/FullscreenToggle
@onready var fullscreen_value_label: Label = $CanvasLayer/UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/SettingsPanel/SettingsScroll/SettingsScrollContent/VideoGrid/FullscreenValueLabel
@onready var resolution_option_button: OptionButton = $CanvasLayer/UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/SettingsPanel/SettingsScroll/SettingsScrollContent/VideoGrid/ResolutionOptionButton
@onready var resolution_value_label: Label = $CanvasLayer/UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/SettingsPanel/SettingsScroll/SettingsScrollContent/VideoGrid/ResolutionValueLabel
@onready var camera_fov_slider: HSlider = $CanvasLayer/UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/SettingsPanel/SettingsScroll/SettingsScrollContent/VideoGrid/CameraFovSlider
@onready var camera_fov_value_label: Label = $CanvasLayer/UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/SettingsPanel/SettingsScroll/SettingsScrollContent/VideoGrid/CameraFovValueLabel
@onready var planet_effects_toggle: CheckButton = $CanvasLayer/UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/SettingsPanel/SettingsScroll/SettingsScrollContent/VideoGrid/PlanetEffectsToggle
@onready var planet_effects_value_label: Label = $CanvasLayer/UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/SettingsPanel/SettingsScroll/SettingsScrollContent/VideoGrid/PlanetEffectsValueLabel
@onready var mouse_sensitivity_slider: HSlider = $CanvasLayer/UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/SettingsPanel/SettingsScroll/SettingsScrollContent/ControlsGrid/MouseSensitivitySlider
@onready var mouse_sensitivity_value_label: Label = $CanvasLayer/UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/SettingsPanel/SettingsScroll/SettingsScrollContent/ControlsGrid/MouseSensitivityValueLabel
@onready var invert_y_toggle: CheckButton = $CanvasLayer/UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/SettingsPanel/SettingsScroll/SettingsScrollContent/ControlsGrid/InvertYToggle
@onready var invert_y_value_label: Label = $CanvasLayer/UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/SettingsPanel/SettingsScroll/SettingsScrollContent/ControlsGrid/InvertYValueLabel
@onready var mouse_smoothing_toggle: CheckButton = $CanvasLayer/UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/SettingsPanel/SettingsScroll/SettingsScrollContent/ControlsGrid/MouseSmoothingToggle
@onready var mouse_smoothing_value_label: Label = $CanvasLayer/UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/SettingsPanel/SettingsScroll/SettingsScrollContent/ControlsGrid/MouseSmoothingValueLabel
@onready var mouse_smoothing_detail_margin: MarginContainer = $CanvasLayer/UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/SettingsPanel/SettingsScroll/SettingsScrollContent/MouseSmoothingDetailMargin
@onready var mouse_smoothing_slider: HSlider = $CanvasLayer/UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/SettingsPanel/SettingsScroll/SettingsScrollContent/MouseSmoothingDetailMargin/MouseSmoothingDetailGrid/MouseSmoothingSlider
@onready var mouse_smoothing_slider_value_label: Label = $CanvasLayer/UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/SettingsPanel/SettingsScroll/SettingsScrollContent/MouseSmoothingDetailMargin/MouseSmoothingDetailGrid/MouseSmoothingValueLabel
@onready var camera_shake_toggle: CheckButton = $CanvasLayer/UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/SettingsPanel/SettingsScroll/SettingsScrollContent/GameplayGrid/CameraShakeToggle
@onready var camera_shake_value_label: Label = $CanvasLayer/UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/SettingsPanel/SettingsScroll/SettingsScrollContent/GameplayGrid/CameraShakeValueLabel
@onready var engine_volume_slider: HSlider = $CanvasLayer/UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/SettingsPanel/SettingsScroll/SettingsScrollContent/AudioGrid/EngineVolumeSlider
@onready var engine_volume_value_label: Label = $CanvasLayer/UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/SettingsPanel/SettingsScroll/SettingsScrollContent/AudioGrid/EngineVolumeValueLabel
@onready var ambient_volume_slider: HSlider = $CanvasLayer/UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/SettingsPanel/SettingsScroll/SettingsScrollContent/AudioGrid/AmbientVolumeSlider
@onready var ambient_volume_value_label: Label = $CanvasLayer/UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/SettingsPanel/SettingsScroll/SettingsScrollContent/AudioGrid/AmbientVolumeValueLabel
@onready var ui_volume_slider: HSlider = $CanvasLayer/UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/SettingsPanel/SettingsScroll/SettingsScrollContent/AudioGrid/UiVolumeSlider
@onready var ui_volume_value_label: Label = $CanvasLayer/UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/SettingsPanel/SettingsScroll/SettingsScrollContent/AudioGrid/UiVolumeValueLabel
@onready var reset_settings_button: Button = $CanvasLayer/UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/SettingsPanel/SettingsButtonRow/ResetSettingsButton
@onready var apply_settings_button: Button = $CanvasLayer/UIRoot/MenuShell/MenuMargin/MenuVBox/MenuColumns/DetailsColumn/SettingsPanel/SettingsButtonRow/ApplySettingsButton
@onready var loading_overlay: ColorRect = $CanvasLayer/UIRoot/LoadingOverlay
@onready var loading_label: Label = $CanvasLayer/UIRoot/LoadingLabel
@onready var settings_prompt_overlay: ColorRect = $CanvasLayer/UIRoot/SettingsPromptOverlay
@onready var settings_prompt_panel: PanelContainer = $CanvasLayer/UIRoot/SettingsPromptOverlay/SettingsPromptPanel
@onready var settings_prompt_apply_button: Button = $CanvasLayer/UIRoot/SettingsPromptOverlay/SettingsPromptPanel/SettingsPromptMargin/SettingsPromptVBox/SettingsPromptButtonRow/SettingsPromptApplyButton
@onready var settings_prompt_discard_button: Button = $CanvasLayer/UIRoot/SettingsPromptOverlay/SettingsPromptPanel/SettingsPromptMargin/SettingsPromptVBox/SettingsPromptButtonRow/SettingsPromptDiscardButton
@onready var footer_label: Label = $CanvasLayer/UIRoot/MenuShell/MenuMargin/MenuVBox/FooterLabel
@onready var menu_ambient_player: AudioStreamPlayer = $MenuAmbientPlayer
@onready var button_click_player: AudioStreamPlayer = $MenuButtonPlayer


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_prepare_page_content()
	_bind_buttons()
	_bind_settings_controls()
	_freeze_simulation_for_menu()

	title_label.text = title_text
	subtitle_label.text = subtitle_text
	loading_label.text = loading_text
	footer_label.text = "WARNING: Game still under development, you may encounter bugs when playing."
	if not get_viewport().size_changed.is_connected(_on_viewport_size_changed):
		get_viewport().size_changed.connect(_on_viewport_size_changed)
	if menu_shell != null and not menu_shell.resized.is_connected(_on_menu_shell_resized):
		menu_shell.resized.connect(_on_menu_shell_resized)
	_apply_menu_shell_layout(false, false)
	if menu_ambient_player != null:
		var ambient_target: Variant = menu_ambient_player.get("target_volume_db")
		_menu_base_ambient_volume_db = float(ambient_target) if ambient_target != null else menu_ambient_player.volume_db
	else:
		_menu_base_ambient_volume_db = 0.0
	_menu_base_button_volume_db = button_click_player.volume_db if button_click_player != null else 0.0

	loading_overlay.color = Color(0.0, 0.0, 0.0, 0.0)
	loading_overlay.visible = false
	loading_label.visible = false
	settings_prompt_overlay.visible = false
	_details_body_default_minimum_size = details_body_label.custom_minimum_size
	_apply_difficulty_selection_visuals()

	_on_settings_changed()
	var settings = _settings()
	if settings != null and not settings.settings_changed.is_connected(_on_settings_changed):
		settings.settings_changed.connect(_on_settings_changed)
	_refresh_display_scale()

	_show_page(PAGE_MAIN)
	start_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if _is_transitioning or settings_prompt_overlay.visible:
		return

	if event.is_action_pressed("ui_cancel") and _active_page != PAGE_MAIN:
		_request_show_page(PAGE_MAIN, start_button)
		get_viewport().set_input_as_handled()


func _prepare_page_content() -> void:
	_page_titles = {
		PAGE_MAIN: "Start",
		PAGE_HOW_TO_PLAY: "How To Play",
		PAGE_SETTINGS: "Settings",
		PAGE_CREDITS: "Credits",
	}

	_page_bodies = {
		PAGE_MAIN: intro_page_text,
		PAGE_HOW_TO_PLAY: how_to_play_text,
		PAGE_SETTINGS: settings_text,
		PAGE_CREDITS: credits_text,
	}

	_how_to_play_pages = [
		{
			"title": tutorial_page_1_title,
			"body": tutorial_page_1_text,
		},
		{
			"title": tutorial_page_2_title,
			"body": tutorial_page_2_text,
		},
		{
			"title": tutorial_page_3_title,
			"body": tutorial_page_3_text,
		},
		{
			"title": tutorial_page_4_title,
			"body": tutorial_page_4_text,
		},
		{
			"title": tutorial_page_5_title,
			"body": tutorial_page_5_text,
		},
		{
			"title": tutorial_page_6_title,
			"body": tutorial_page_6_text,
		},
		{
			"title": tutorial_page_7_title,
			"body": tutorial_page_7_text,
		},
		{
			"title": tutorial_page_8_title,
			"body": tutorial_page_8_text,
		},
		{
			"title": tutorial_page_9_title,
			"body": tutorial_page_9_text,
		},
		{
			"title": tutorial_page_10_title,
			"body": tutorial_page_10_text,
		},
		{
			"title": tutorial_page_11_title,
			"body": tutorial_page_11_text,
		},
	]


func _bind_buttons() -> void:
	_connect_confirmed_press(start_button, _on_start_pressed)
	_connect_confirmed_press(how_to_play_button, func() -> void:
		_on_page_button_pressed(PAGE_HOW_TO_PLAY, how_to_play_button)
	)
	_connect_confirmed_press(settings_button, func() -> void:
		_on_page_button_pressed(PAGE_SETTINGS, settings_button)
	)
	_connect_confirmed_press(credits_button, func() -> void:
		_on_page_button_pressed(PAGE_CREDITS, credits_button)
	)
	_connect_confirmed_press(quit_button, _on_quit_pressed)
	_connect_confirmed_press(previous_page_button, _on_previous_page_pressed)
	_connect_confirmed_press(next_page_button, _on_next_page_pressed)
	_connect_confirmed_press(easy_difficulty_button, func() -> void:
		_on_difficulty_selected(&"easy", easy_difficulty_button)
	)
	_connect_confirmed_press(normal_difficulty_button, func() -> void:
		_on_difficulty_selected(&"normal", normal_difficulty_button)
	)
	_connect_confirmed_press(hard_difficulty_button, func() -> void:
		_on_difficulty_selected(&"hard", hard_difficulty_button)
	)


func _connect_confirmed_press(button: Button, callback: Callable) -> void:
	if button == null or not callback.is_valid():
		return

	if button.has_signal("confirmed_pressed"):
		button.connect("confirmed_pressed", callback)
	else:
		button.pressed.connect(callback)


func _freeze_simulation_for_menu() -> void:
	SimulationState.cancel_targeted_warp()
	SimulationState.celestial_time_scale = 0.0


func _show_page(page_key: StringName) -> void:
	_active_page = page_key
	_animate_menu_shell(page_key != PAGE_MAIN)
	details_title_label.text = _page_titles.get(page_key, "Menu")

	var showing_tutorial: bool = page_key == PAGE_HOW_TO_PLAY
	var showing_settings: bool = page_key == PAGE_SETTINGS
	var showing_start_options: bool = page_key == PAGE_MAIN
	how_to_play_book.visible = showing_tutorial
	settings_panel.visible = showing_settings
	start_options_panel.visible = showing_start_options
	details_body_label.visible = not showing_tutorial and not showing_settings
	details_body_label.custom_minimum_size = Vector2(_details_body_default_minimum_size.x, 110.0) if showing_start_options else _details_body_default_minimum_size
	if showing_start_options:
		_select_difficulty(_selected_difficulty, false)

	if showing_tutorial:
		_show_how_to_play_page(_how_to_play_page_index)
	else:
		details_body_label.text = _page_bodies.get(page_key, "")


func _on_page_button_pressed(page_key: StringName, source_button: Button) -> void:
	if _is_transitioning or settings_prompt_overlay.visible:
		return

	_play_button_click()

	if page_key == PAGE_HOW_TO_PLAY:
		_how_to_play_page_index = 0

	_request_show_page(page_key, source_button)


func _set_buttons_disabled(disabled: bool) -> void:
	start_button.disabled = disabled
	how_to_play_button.disabled = disabled
	settings_button.disabled = disabled
	credits_button.disabled = disabled
	quit_button.disabled = disabled
	previous_page_button.disabled = disabled or _how_to_play_page_index <= 0
	next_page_button.disabled = disabled or _how_to_play_page_index >= _how_to_play_pages.size() - 1
	easy_difficulty_button.disabled = disabled
	normal_difficulty_button.disabled = disabled
	hard_difficulty_button.disabled = disabled
	locked_difficulty_button.disabled = true
	reset_settings_button.disabled = disabled
	apply_settings_button.disabled = disabled
	settings_prompt_apply_button.disabled = disabled
	settings_prompt_discard_button.disabled = disabled


func _play_button_click() -> void:
	if button_click_player == null or button_click_player.stream == null:
		return
	button_click_player.stop()
	button_click_player.play()


func _on_start_pressed() -> void:
	if _is_transitioning:
		return

	if _active_page != PAGE_MAIN:
		_play_button_click()
		_request_show_page(PAGE_MAIN, start_button)
		return

	_play_button_click()
	_start_game_transition()


func _on_quit_pressed() -> void:
	if _is_transitioning:
		return

	_play_button_click()
	if _active_page == PAGE_SETTINGS and _has_unsaved_settings:
		_pending_quit_after_settings_prompt = true
		_show_settings_leave_prompt()
		return
	_quit_after_click()


func _on_difficulty_selected(difficulty: StringName, source_button: Button) -> void:
	if _is_transitioning or settings_prompt_overlay.visible:
		return
	_play_button_click()
	_select_difficulty(difficulty)
	if source_button != null:
		source_button.grab_focus()


func _select_difficulty(difficulty: StringName, update_focus: bool = true) -> void:
	if difficulty == StringName():
		difficulty = &"easy"
	_selected_difficulty = difficulty
	_apply_difficulty_selection_visuals()
	if update_focus:
		match _selected_difficulty:
			&"easy":
				easy_difficulty_button.grab_focus()
			&"normal":
				normal_difficulty_button.grab_focus()
			&"hard":
				hard_difficulty_button.grab_focus()


func _apply_difficulty_selection_visuals() -> void:
	easy_difficulty_button.button_pressed = _selected_difficulty == &"easy"
	normal_difficulty_button.button_pressed = _selected_difficulty == &"normal"
	hard_difficulty_button.button_pressed = _selected_difficulty == &"hard"


func _quit_after_click() -> void:
	await get_tree().create_timer(0.08).timeout
	get_tree().quit()


func _start_game_transition() -> void:
	if gameplay_scene_path.strip_edges().is_empty():
		push_error("MenuController: gameplay_scene_path is empty.")
		return

	_is_transitioning = true
	_set_buttons_disabled(true)
	loading_overlay.visible = true
	await _fade_loading_overlay_to(1.0)
	loading_label.visible = true

	var session = _game_session()
	if session != null and session.has_method("set_selected_difficulty"):
		session.set_selected_difficulty(_selected_difficulty)

	SimulationState.reset()
	SimulationState.celestial_time_scale = gameplay_time_scale_on_start

	var error: Error = get_tree().change_scene_to_file(gameplay_scene_path)
	if error != OK:
		push_error("MenuController: failed to change scene to '%s' (error %d)." % [gameplay_scene_path, error])
		loading_label.visible = false
		await _fade_loading_overlay_to(0.0)
		loading_overlay.visible = false
		_set_buttons_disabled(false)
		_is_transitioning = false


func _fade_loading_overlay_to(target_alpha: float) -> void:
	var tween: Tween = create_tween()
	tween.tween_property(loading_overlay, "color:a", target_alpha, max(fade_duration, 0.01))
	await tween.finished


func _show_how_to_play_page(page_index: int) -> void:
	if _how_to_play_pages.is_empty():
		tutorial_page_title_label.text = "Page 1"
		tutorial_page_body_label.text = how_to_play_text
		page_indicator_label.text = "1 / 1"
		previous_page_button.disabled = true
		next_page_button.disabled = true
		return

	_how_to_play_page_index = clampi(page_index, 0, _how_to_play_pages.size() - 1)
	var page_data: Dictionary = _how_to_play_pages[_how_to_play_page_index]
	tutorial_page_title_label.text = str(page_data.get("title", "Page"))
	tutorial_page_body_label.text = str(page_data.get("body", ""))
	tutorial_page_body_label.scroll_to_line(0)
	page_indicator_label.text = "%d / %d" % [_how_to_play_page_index + 1, _how_to_play_pages.size()]
	previous_page_button.disabled = _how_to_play_page_index <= 0
	next_page_button.disabled = _how_to_play_page_index >= _how_to_play_pages.size() - 1


func _on_previous_page_pressed() -> void:
	if _is_transitioning or _active_page != PAGE_HOW_TO_PLAY or _how_to_play_page_index <= 0:
		return

	_play_button_click()
	_show_how_to_play_page(_how_to_play_page_index - 1)
	previous_page_button.grab_focus()


func _on_next_page_pressed() -> void:
	if _is_transitioning or _active_page != PAGE_HOW_TO_PLAY or _how_to_play_page_index >= _how_to_play_pages.size() - 1:
		return

	_play_button_click()
	_show_how_to_play_page(_how_to_play_page_index + 1)
	next_page_button.grab_focus()


func _animate_menu_shell(expanded: bool) -> void:
	if menu_shell == null:
		return

	if _menu_shell_tween != null and _menu_shell_tween.is_running():
		_menu_shell_tween.kill()

	var target_layout: Dictionary = _get_menu_shell_layout(expanded)
	var target_position: Vector2 = target_layout.get("position", Vector2.ZERO)
	var target_size: Vector2 = target_layout.get("size", compact_menu_size)
	var target_scale: Vector2 = target_layout.get("scale", Vector2.ONE)

	_menu_shell_tween = create_tween()
	_menu_shell_tween.set_parallel(true)
	_menu_shell_tween.tween_property(menu_shell, "position", target_position, max(menu_resize_duration, 0.01))
	_menu_shell_tween.tween_property(menu_shell, "size", target_size, max(menu_resize_duration, 0.01))
	_menu_shell_tween.tween_property(menu_shell, "scale", target_scale, max(menu_resize_duration, 0.01))


func _bind_settings_controls() -> void:
	mouse_sensitivity_slider.value_changed.connect(_on_mouse_sensitivity_changed)
	mouse_smoothing_toggle.toggled.connect(_on_mouse_smoothing_toggled)
	mouse_smoothing_slider.value_changed.connect(_on_mouse_smoothing_slider_changed)
	camera_fov_slider.value_changed.connect(_on_camera_fov_changed)
	fullscreen_toggle.toggled.connect(_on_fullscreen_toggled)
	resolution_option_button.item_selected.connect(_on_resolution_selected)
	invert_y_toggle.toggled.connect(_on_invert_y_toggled)
	engine_volume_slider.value_changed.connect(_on_engine_volume_changed)
	ambient_volume_slider.value_changed.connect(_on_ambient_volume_changed)
	ui_volume_slider.value_changed.connect(_on_ui_volume_changed)
	camera_shake_toggle.toggled.connect(_on_camera_shake_toggled)
	planet_effects_toggle.toggled.connect(_on_planet_effects_toggled)
	_connect_confirmed_press(reset_settings_button, _on_reset_settings_pressed)
	_connect_confirmed_press(apply_settings_button, _on_apply_settings_pressed)
	_connect_confirmed_press(settings_prompt_apply_button, _on_settings_prompt_apply_pressed)
	_connect_confirmed_press(settings_prompt_discard_button, _on_settings_prompt_discard_pressed)


func _on_settings_changed() -> void:
	_load_committed_settings()
	if not _has_unsaved_settings:
		_pending_settings = _committed_settings.duplicate(true)
	_refresh_settings_controls()
	_apply_menu_audio_settings()
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


func _apply_menu_audio_settings() -> void:
	var settings = _settings()
	if settings == null:
		return

	if menu_ambient_player != null:
		var ambient_db: float = _menu_base_ambient_volume_db + settings.volume_scale_to_db_offset(settings.ambient_volume)
		if menu_ambient_player.has_method("set_target_volume_db"):
			menu_ambient_player.set_target_volume_db(ambient_db, true)
		else:
			menu_ambient_player.volume_db = ambient_db

	if button_click_player != null:
		var ui_button_db: float = _menu_base_button_volume_db + settings.volume_scale_to_db_offset(settings.ui_volume)
		button_click_player.volume_db = ui_button_db


func _on_mouse_sensitivity_changed(value: float) -> void:
	if _synchronizing_settings_ui:
		return
	var settings = _settings()
	if settings != null:
		_pending_settings["mouse_sensitivity"] = settings.display_level_to_mouse_sensitivity(value)
		mouse_sensitivity_value_label.text = "%d" % int(round(value))
		_mark_settings_dirty()


func _on_mouse_smoothing_toggled(value: bool) -> void:
	if _synchronizing_settings_ui:
		return
	var settings = _settings()
	if settings != null:
		_pending_settings["mouse_smoothing_enabled"] = value
		mouse_smoothing_value_label.text = "On" if value else "Off"
		mouse_smoothing_detail_margin.visible = value
		_mark_settings_dirty()


func _on_mouse_smoothing_slider_changed(value: float) -> void:
	if _synchronizing_settings_ui:
		return
	var settings = _settings()
	if settings != null:
		_pending_settings["mouse_smoothing_speed"] = settings.display_level_to_mouse_smoothing(value)
		mouse_smoothing_slider_value_label.text = "%d" % int(round(value))
		_mark_settings_dirty()


func _on_camera_fov_changed(value: float) -> void:
	if _synchronizing_settings_ui:
		return
	var settings = _settings()
	if settings != null:
		_pending_settings["camera_fov"] = value
		camera_fov_value_label.text = "%d" % int(round(value))
		_mark_settings_dirty()


func _on_invert_y_toggled(value: bool) -> void:
	if _synchronizing_settings_ui:
		return
	var settings = _settings()
	if settings != null:
		_pending_settings["invert_y_look"] = value
		invert_y_value_label.text = "On" if value else "Off"
		_mark_settings_dirty()


func _on_fullscreen_toggled(value: bool) -> void:
	if _synchronizing_settings_ui:
		return
	var settings = _settings()
	if settings != null:
		_pending_settings["fullscreen_enabled"] = value
		fullscreen_value_label.text = "On" if value else "Off"
		_mark_settings_dirty()


func _on_resolution_selected(index: int) -> void:
	if _synchronizing_settings_ui:
		return
	var settings = _settings()
	if settings != null:
		var resolution: Vector2i = settings.get_resolution_from_index(index)
		_pending_settings["resolution"] = resolution
		resolution_value_label.text = settings.resolution_to_string(resolution)
		_mark_settings_dirty()


func _on_engine_volume_changed(value: float) -> void:
	if _synchronizing_settings_ui:
		return
	var settings = _settings()
	if settings != null:
		_pending_settings["engine_volume"] = value
		engine_volume_value_label.text = "%d%%" % int(round(value * 100.0))
		_mark_settings_dirty()


func _on_ambient_volume_changed(value: float) -> void:
	if _synchronizing_settings_ui:
		return
	var settings = _settings()
	if settings != null:
		_pending_settings["ambient_volume"] = value
		ambient_volume_value_label.text = "%d%%" % int(round(value * 100.0))
		_mark_settings_dirty()


func _on_ui_volume_changed(value: float) -> void:
	if _synchronizing_settings_ui:
		return
	var settings = _settings()
	if settings != null:
		_pending_settings["ui_volume"] = value
		ui_volume_value_label.text = "%d%%" % int(round(value * 100.0))
		_mark_settings_dirty()


func _on_camera_shake_toggled(value: bool) -> void:
	if _synchronizing_settings_ui:
		return
	var settings = _settings()
	if settings != null:
		_pending_settings["camera_shake_enabled"] = value
		camera_shake_value_label.text = "On" if value else "Off"
		_mark_settings_dirty()


func _on_planet_effects_toggled(value: bool) -> void:
	if _synchronizing_settings_ui:
		return
	var settings = _settings()
	if settings != null:
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


func _request_show_page(page_key: StringName, focus_button: Button = null) -> void:
	if _active_page == PAGE_SETTINGS and page_key != PAGE_SETTINGS and _has_unsaved_settings:
		_pending_page_after_settings_prompt = page_key
		_pending_focus_button_after_settings_prompt = focus_button
		_pending_quit_after_settings_prompt = false
		_show_settings_leave_prompt()
		return

	_show_page(page_key)
	if focus_button != null:
		focus_button.grab_focus()


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


func _finish_pending_settings_exit() -> void:
	if _pending_quit_after_settings_prompt:
		_pending_quit_after_settings_prompt = false
		_quit_after_click()
		return

	if _pending_page_after_settings_prompt != StringName():
		var target_page := _pending_page_after_settings_prompt
		var target_focus := _pending_focus_button_after_settings_prompt
		_pending_page_after_settings_prompt = StringName()
		_pending_focus_button_after_settings_prompt = null
		_show_page(target_page)
		if target_focus != null:
			target_focus.grab_focus()


func _load_committed_settings() -> void:
	var settings = _settings()
	if settings == null:
		return
	_committed_settings = settings.to_dictionary()


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


func _set_settings_prompt_modal_state(active: bool) -> void:
	var locked_buttons: Array[Button] = [
		start_button,
		how_to_play_button,
		settings_button,
		credits_button,
		quit_button,
		previous_page_button,
		next_page_button,
	]
	for button in locked_buttons:
		if button != null:
			button.disabled = active
			button.focus_mode = Control.FOCUS_NONE if active else Control.FOCUS_ALL

	if reset_settings_button != null:
		reset_settings_button.disabled = active or reset_settings_button.disabled
		reset_settings_button.focus_mode = Control.FOCUS_NONE if active else Control.FOCUS_ALL

	if apply_settings_button != null:
		apply_settings_button.disabled = active or apply_settings_button.disabled
		apply_settings_button.focus_mode = Control.FOCUS_NONE if active else Control.FOCUS_ALL

	var locked_toggles: Array[CheckButton] = [
		fullscreen_toggle,
		invert_y_toggle,
		mouse_smoothing_toggle,
		camera_shake_toggle,
		planet_effects_toggle,
	]
	for toggle in locked_toggles:
		if toggle != null:
			toggle.disabled = active
			toggle.focus_mode = Control.FOCUS_NONE if active else Control.FOCUS_ALL

	var locked_sliders: Array[HSlider] = [
		mouse_sensitivity_slider,
		mouse_smoothing_slider,
		camera_fov_slider,
		engine_volume_slider,
		ambient_volume_slider,
		ui_volume_slider,
	]
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


func _game_session():
	return get_node_or_null("/root/GameSession")


func _refresh_resolution_options(settings) -> void:
	if settings == null or resolution_option_button == null:
		return

	resolution_option_button.clear()
	var options: Array[Dictionary] = settings.get_resolution_options()
	for option in options:
		resolution_option_button.add_item(str(option.get("label", "")))


func _on_viewport_size_changed() -> void:
	_apply_menu_shell_layout(_active_page != PAGE_MAIN, false)
	_refresh_display_scale()


func _on_menu_shell_resized() -> void:
	_refresh_display_scale()


func _apply_menu_shell_layout(expanded: bool, animate: bool) -> void:
	if animate:
		_animate_menu_shell(expanded)
		return

	var target_layout: Dictionary = _get_menu_shell_layout(expanded)
	menu_shell.pivot_offset = Vector2.ZERO
	menu_shell.position = target_layout.get("position", Vector2.ZERO)
	menu_shell.size = target_layout.get("size", compact_menu_size)
	menu_shell.scale = target_layout.get("scale", Vector2.ONE)


func _get_menu_shell_layout(expanded: bool) -> Dictionary:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var safe_reference: Vector2 = Vector2(
		maxf(reference_viewport_size.x, 1.0),
		maxf(reference_viewport_size.y, 1.0)
	)
	var ui_scale: float = _get_ui_compensation_scale()

	# Keep the shell right edge pinned to the compact (Start tab) reference edge.
	var compact_right_margin: float = safe_reference.x - (compact_menu_position.x + compact_menu_size.x)
	var compact_top_margin: float = compact_menu_position.y
	var compact_max_scale_x: float = viewport_size.x / maxf(compact_menu_size.x + maxf(compact_right_margin, 0.0), 1.0)
	var compact_max_scale_y: float = viewport_size.y / maxf(compact_menu_size.y + maxf(compact_top_margin, 0.0), 1.0)
	var compact_fit_scale: float = clampf(minf(compact_max_scale_x, compact_max_scale_y), 0.1, 8.0)
	var compact_layout_scale: float = minf(ui_scale, compact_fit_scale)
	var reference_right_edge: float = clampf(
		viewport_size.x - (compact_right_margin * compact_layout_scale),
		0.0,
		viewport_size.x
	)

	var base_position: Vector2 = compact_menu_position
	var base_size: Vector2 = compact_menu_size
	if expanded:
		base_position = expanded_menu_position
		base_size = expanded_menu_size

	var top_margin: float = base_position.y
	var max_scale_x: float = reference_right_edge / maxf(base_size.x, 1.0)
	var max_scale_y: float = viewport_size.y / maxf(base_size.y + maxf(top_margin, 0.0), 1.0)
	var fit_scale: float = clampf(minf(max_scale_x, max_scale_y), 0.1, 8.0)
	var layout_scale: float = minf(ui_scale, fit_scale)
	var scaled_size: Vector2 = base_size * layout_scale
	var scaled_top_margin: float = top_margin * layout_scale
	var target_position := Vector2(
		maxf(0.0, reference_right_edge - scaled_size.x),
		maxf(0.0, scaled_top_margin)
	)

	return {
		"position": target_position,
		"size": base_size,
		"scale": Vector2.ONE * layout_scale,
	}


func _refresh_display_scale() -> void:
	_reset_settings_prompt_layout()
	var ui_scale: float = _get_ui_compensation_scale()
	_apply_centered_scale(loading_label, ui_scale)


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
