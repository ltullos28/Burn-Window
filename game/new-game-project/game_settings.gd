extends Node

signal settings_changed

const SETTINGS_PATH := "user://settings.cfg"
const DISPLAY_SETTINGS_VERSION := 5

const DEFAULT_MOUSE_SENSITIVITY := 0.003
const DEFAULT_MOUSE_SMOOTHING_ENABLED := true
const DEFAULT_MOUSE_SMOOTHING_SPEED := 10.0
const DEFAULT_CAMERA_FOV := 75.0
const DEFAULT_INVERT_Y_LOOK := false
const DEFAULT_ENGINE_VOLUME := 1.0
const DEFAULT_AMBIENT_VOLUME := 1.0
const DEFAULT_UI_VOLUME := 1.0
const DEFAULT_CAMERA_SHAKE_ENABLED := true
const DEFAULT_PLANET_EFFECTS_ENABLED := true
const DEFAULT_FULLSCREEN_ENABLED := true
const DEFAULT_RESOLUTION := Vector2i(1920, 1080)
const DEFAULT_LOCK_TO_VECTOR_ENABLED := true

const MIN_MOUSE_SENSITIVITY := 0.001
const MAX_MOUSE_SENSITIVITY := 0.008
const MIN_MOUSE_DISPLAY_LEVEL := 1.0
const MAX_MOUSE_DISPLAY_LEVEL := 100.0
const DEFAULT_MOUSE_DISPLAY_LEVEL := 50.0
const MIN_MOUSE_SMOOTHING_SPEED := 3.0
const MAX_MOUSE_SMOOTHING_SPEED := 16.0
const MIN_CAMERA_FOV := 55.0
const MAX_CAMERA_FOV := 95.0
const MIN_VOLUME_SCALE := 0.0
const MAX_VOLUME_SCALE := 1.5

const RESOLUTION_OPTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3840, 2160),
]

var mouse_sensitivity: float = DEFAULT_MOUSE_SENSITIVITY
var mouse_smoothing_enabled: bool = DEFAULT_MOUSE_SMOOTHING_ENABLED
var mouse_smoothing_speed: float = DEFAULT_MOUSE_SMOOTHING_SPEED
var camera_fov: float = DEFAULT_CAMERA_FOV
var invert_y_look: bool = DEFAULT_INVERT_Y_LOOK
var engine_volume: float = DEFAULT_ENGINE_VOLUME
var ambient_volume: float = DEFAULT_AMBIENT_VOLUME
var ui_volume: float = DEFAULT_UI_VOLUME
var camera_shake_enabled: bool = DEFAULT_CAMERA_SHAKE_ENABLED
var planet_effects_enabled: bool = DEFAULT_PLANET_EFFECTS_ENABLED
var fullscreen_enabled: bool = DEFAULT_FULLSCREEN_ENABLED
var resolution: Vector2i = DEFAULT_RESOLUTION
var lock_to_vector_enabled: bool = DEFAULT_LOCK_TO_VECTOR_ENABLED


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	var config := ConfigFile.new()
	var error := config.load(SETTINGS_PATH)
	if error != OK:
		_apply_display_settings()
		_emit_changed()
		return

	mouse_sensitivity = clampf(
		float(config.get_value("controls", "mouse_sensitivity", DEFAULT_MOUSE_SENSITIVITY)),
		MIN_MOUSE_SENSITIVITY,
		MAX_MOUSE_SENSITIVITY
	)
	mouse_smoothing_enabled = bool(config.get_value("controls", "mouse_smoothing_enabled", DEFAULT_MOUSE_SMOOTHING_ENABLED))
	mouse_smoothing_speed = clampf(
		float(config.get_value("controls", "mouse_smoothing_speed", DEFAULT_MOUSE_SMOOTHING_SPEED)),
		MIN_MOUSE_SMOOTHING_SPEED,
		MAX_MOUSE_SMOOTHING_SPEED
	)
	camera_fov = clampf(
		float(config.get_value("controls", "camera_fov", DEFAULT_CAMERA_FOV)),
		MIN_CAMERA_FOV,
		MAX_CAMERA_FOV
	)
	invert_y_look = bool(config.get_value("controls", "invert_y_look", DEFAULT_INVERT_Y_LOOK))
	lock_to_vector_enabled = bool(config.get_value("controls", "lock_to_vector_enabled", DEFAULT_LOCK_TO_VECTOR_ENABLED))
	engine_volume = clampf(
		float(config.get_value("audio", "engine_volume", DEFAULT_ENGINE_VOLUME)),
		MIN_VOLUME_SCALE,
		MAX_VOLUME_SCALE
	)
	ambient_volume = clampf(
		float(config.get_value("audio", "ambient_volume", DEFAULT_AMBIENT_VOLUME)),
		MIN_VOLUME_SCALE,
		MAX_VOLUME_SCALE
	)
	ui_volume = clampf(
		float(config.get_value("audio", "ui_volume", DEFAULT_UI_VOLUME)),
		MIN_VOLUME_SCALE,
		MAX_VOLUME_SCALE
	)
	camera_shake_enabled = bool(config.get_value("camera", "camera_shake_enabled", DEFAULT_CAMERA_SHAKE_ENABLED))
	planet_effects_enabled = bool(config.get_value("graphics", "planet_effects_enabled", DEFAULT_PLANET_EFFECTS_ENABLED))
	fullscreen_enabled = bool(config.get_value("graphics", "fullscreen_enabled", DEFAULT_FULLSCREEN_ENABLED))
	resolution = _sanitize_resolution(
		Vector2i(
			int(config.get_value("graphics", "resolution_width", DEFAULT_RESOLUTION.x)),
			int(config.get_value("graphics", "resolution_height", DEFAULT_RESOLUTION.y))
		)
	)
	var loaded_display_settings_version: int = int(
		config.get_value("graphics", "display_settings_version", 0)
	)
	if loaded_display_settings_version != DISPLAY_SETTINGS_VERSION:
		fullscreen_enabled = DEFAULT_FULLSCREEN_ENABLED
		resolution = DEFAULT_RESOLUTION
		save_settings()

	_apply_display_settings()
	_emit_changed()


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	config.set_value("controls", "mouse_smoothing_enabled", mouse_smoothing_enabled)
	config.set_value("controls", "mouse_smoothing_speed", mouse_smoothing_speed)
	config.set_value("controls", "camera_fov", camera_fov)
	config.set_value("controls", "invert_y_look", invert_y_look)
	config.set_value("controls", "lock_to_vector_enabled", lock_to_vector_enabled)
	config.set_value("audio", "engine_volume", engine_volume)
	config.set_value("audio", "ambient_volume", ambient_volume)
	config.set_value("audio", "ui_volume", ui_volume)
	config.set_value("camera", "camera_shake_enabled", camera_shake_enabled)
	config.set_value("graphics", "planet_effects_enabled", planet_effects_enabled)
	config.set_value("graphics", "fullscreen_enabled", fullscreen_enabled)
	config.set_value("graphics", "resolution_width", resolution.x)
	config.set_value("graphics", "resolution_height", resolution.y)
	config.set_value("graphics", "display_settings_version", DISPLAY_SETTINGS_VERSION)
	config.save(SETTINGS_PATH)


func to_dictionary() -> Dictionary:
	return {
		"mouse_sensitivity": mouse_sensitivity,
		"mouse_smoothing_enabled": mouse_smoothing_enabled,
		"mouse_smoothing_speed": mouse_smoothing_speed,
		"camera_fov": camera_fov,
		"invert_y_look": invert_y_look,
		"lock_to_vector_enabled": lock_to_vector_enabled,
		"engine_volume": engine_volume,
		"ambient_volume": ambient_volume,
		"ui_volume": ui_volume,
		"camera_shake_enabled": camera_shake_enabled,
		"planet_effects_enabled": planet_effects_enabled,
		"fullscreen_enabled": fullscreen_enabled,
		"resolution": resolution,
	}


func default_dictionary() -> Dictionary:
	return {
		"mouse_sensitivity": DEFAULT_MOUSE_SENSITIVITY,
		"mouse_smoothing_enabled": DEFAULT_MOUSE_SMOOTHING_ENABLED,
		"mouse_smoothing_speed": DEFAULT_MOUSE_SMOOTHING_SPEED,
		"camera_fov": DEFAULT_CAMERA_FOV,
		"invert_y_look": DEFAULT_INVERT_Y_LOOK,
		"lock_to_vector_enabled": DEFAULT_LOCK_TO_VECTOR_ENABLED,
		"engine_volume": DEFAULT_ENGINE_VOLUME,
		"ambient_volume": DEFAULT_AMBIENT_VOLUME,
		"ui_volume": DEFAULT_UI_VOLUME,
		"camera_shake_enabled": DEFAULT_CAMERA_SHAKE_ENABLED,
		"planet_effects_enabled": DEFAULT_PLANET_EFFECTS_ENABLED,
		"fullscreen_enabled": DEFAULT_FULLSCREEN_ENABLED,
		"resolution": DEFAULT_RESOLUTION,
	}


func apply_dictionary(values: Dictionary, save_immediately: bool = true) -> void:
	mouse_sensitivity = clampf(
		float(values.get("mouse_sensitivity", mouse_sensitivity)),
		MIN_MOUSE_SENSITIVITY,
		MAX_MOUSE_SENSITIVITY
	)
	mouse_smoothing_enabled = bool(values.get("mouse_smoothing_enabled", mouse_smoothing_enabled))
	mouse_smoothing_speed = clampf(
		float(values.get("mouse_smoothing_speed", mouse_smoothing_speed)),
		MIN_MOUSE_SMOOTHING_SPEED,
		MAX_MOUSE_SMOOTHING_SPEED
	)
	camera_fov = clampf(
		float(values.get("camera_fov", camera_fov)),
		MIN_CAMERA_FOV,
		MAX_CAMERA_FOV
	)
	invert_y_look = bool(values.get("invert_y_look", invert_y_look))
	lock_to_vector_enabled = bool(values.get("lock_to_vector_enabled", lock_to_vector_enabled))
	engine_volume = clampf(
		float(values.get("engine_volume", engine_volume)),
		MIN_VOLUME_SCALE,
		MAX_VOLUME_SCALE
	)
	ambient_volume = clampf(
		float(values.get("ambient_volume", ambient_volume)),
		MIN_VOLUME_SCALE,
		MAX_VOLUME_SCALE
	)
	ui_volume = clampf(
		float(values.get("ui_volume", ui_volume)),
		MIN_VOLUME_SCALE,
		MAX_VOLUME_SCALE
	)
	camera_shake_enabled = bool(values.get("camera_shake_enabled", camera_shake_enabled))
	planet_effects_enabled = bool(values.get("planet_effects_enabled", planet_effects_enabled))
	fullscreen_enabled = bool(values.get("fullscreen_enabled", fullscreen_enabled))
	resolution = _sanitize_resolution(values.get("resolution", resolution))

	_apply_display_settings()

	if save_immediately:
		save_settings()

	_emit_changed()


func mouse_sensitivity_to_display_percent(value: float) -> float:
	return mouse_sensitivity_to_display_level(value)


func display_percent_to_mouse_sensitivity(value: float) -> float:
	return display_level_to_mouse_sensitivity(value)


func mouse_sensitivity_to_display_level(value: float) -> float:
	var clamped := clampf(value, MIN_MOUSE_SENSITIVITY, MAX_MOUSE_SENSITIVITY)
	if clamped <= DEFAULT_MOUSE_SENSITIVITY:
		var low_t: float = inverse_lerp(MIN_MOUSE_SENSITIVITY, DEFAULT_MOUSE_SENSITIVITY, clamped)
		return lerpf(MIN_MOUSE_DISPLAY_LEVEL, DEFAULT_MOUSE_DISPLAY_LEVEL, low_t)

	var high_t: float = inverse_lerp(DEFAULT_MOUSE_SENSITIVITY, MAX_MOUSE_SENSITIVITY, clamped)
	return lerpf(DEFAULT_MOUSE_DISPLAY_LEVEL, MAX_MOUSE_DISPLAY_LEVEL, high_t)


func display_level_to_mouse_sensitivity(value: float) -> float:
	var clamped := clampf(value, MIN_MOUSE_DISPLAY_LEVEL, MAX_MOUSE_DISPLAY_LEVEL)
	if clamped <= DEFAULT_MOUSE_DISPLAY_LEVEL:
		var low_t: float = inverse_lerp(MIN_MOUSE_DISPLAY_LEVEL, DEFAULT_MOUSE_DISPLAY_LEVEL, clamped)
		return lerpf(MIN_MOUSE_SENSITIVITY, DEFAULT_MOUSE_SENSITIVITY, low_t)

	var high_t: float = inverse_lerp(DEFAULT_MOUSE_DISPLAY_LEVEL, MAX_MOUSE_DISPLAY_LEVEL, clamped)
	return lerpf(DEFAULT_MOUSE_SENSITIVITY, MAX_MOUSE_SENSITIVITY, high_t)


func mouse_smoothing_to_display_level(value: float) -> float:
	var clamped := clampf(value, MIN_MOUSE_SMOOTHING_SPEED, MAX_MOUSE_SMOOTHING_SPEED)
	if clamped >= DEFAULT_MOUSE_SMOOTHING_SPEED:
		var low_t: float = inverse_lerp(MAX_MOUSE_SMOOTHING_SPEED, DEFAULT_MOUSE_SMOOTHING_SPEED, clamped)
		return lerpf(MIN_MOUSE_DISPLAY_LEVEL, DEFAULT_MOUSE_DISPLAY_LEVEL, low_t)

	var high_t: float = inverse_lerp(DEFAULT_MOUSE_SMOOTHING_SPEED, MIN_MOUSE_SMOOTHING_SPEED, clamped)
	return lerpf(DEFAULT_MOUSE_DISPLAY_LEVEL, MAX_MOUSE_DISPLAY_LEVEL, high_t)


func display_level_to_mouse_smoothing(value: float) -> float:
	var clamped := clampf(value, MIN_MOUSE_DISPLAY_LEVEL, MAX_MOUSE_DISPLAY_LEVEL)
	if clamped <= DEFAULT_MOUSE_DISPLAY_LEVEL:
		var low_t: float = inverse_lerp(MIN_MOUSE_DISPLAY_LEVEL, DEFAULT_MOUSE_DISPLAY_LEVEL, clamped)
		return lerpf(MAX_MOUSE_SMOOTHING_SPEED, DEFAULT_MOUSE_SMOOTHING_SPEED, low_t)

	var high_t: float = inverse_lerp(DEFAULT_MOUSE_DISPLAY_LEVEL, MAX_MOUSE_DISPLAY_LEVEL, clamped)
	return lerpf(DEFAULT_MOUSE_SMOOTHING_SPEED, MIN_MOUSE_SMOOTHING_SPEED, high_t)


func set_mouse_sensitivity_value(value: float) -> void:
	var clamped := clampf(value, MIN_MOUSE_SENSITIVITY, MAX_MOUSE_SENSITIVITY)
	if is_equal_approx(mouse_sensitivity, clamped):
		return
	mouse_sensitivity = clamped
	_save_and_emit()


func set_mouse_smoothing_enabled_value(value: bool) -> void:
	if mouse_smoothing_enabled == value:
		return
	mouse_smoothing_enabled = value
	_save_and_emit()


func set_mouse_smoothing_speed_value(value: float) -> void:
	var clamped := clampf(value, MIN_MOUSE_SMOOTHING_SPEED, MAX_MOUSE_SMOOTHING_SPEED)
	if is_equal_approx(mouse_smoothing_speed, clamped):
		return
	mouse_smoothing_speed = clamped
	_save_and_emit()


func set_camera_fov_value(value: float) -> void:
	var clamped := clampf(value, MIN_CAMERA_FOV, MAX_CAMERA_FOV)
	if is_equal_approx(camera_fov, clamped):
		return
	camera_fov = clamped
	_save_and_emit()


func set_invert_y_look_value(value: bool) -> void:
	if invert_y_look == value:
		return
	invert_y_look = value
	_save_and_emit()


# Expose this in the settings UI as a checkbox labeled "Lock To Vector".
func set_lock_to_vector_enabled_value(value: bool) -> void:
	if lock_to_vector_enabled == value:
		return
	lock_to_vector_enabled = value
	_save_and_emit()


func set_engine_volume_value(value: float) -> void:
	var clamped := clampf(value, MIN_VOLUME_SCALE, MAX_VOLUME_SCALE)
	if is_equal_approx(engine_volume, clamped):
		return
	engine_volume = clamped
	_save_and_emit()


func set_ambient_volume_value(value: float) -> void:
	var clamped := clampf(value, MIN_VOLUME_SCALE, MAX_VOLUME_SCALE)
	if is_equal_approx(ambient_volume, clamped):
		return
	ambient_volume = clamped
	_save_and_emit()


func set_ui_volume_value(value: float) -> void:
	var clamped := clampf(value, MIN_VOLUME_SCALE, MAX_VOLUME_SCALE)
	if is_equal_approx(ui_volume, clamped):
		return
	ui_volume = clamped
	_save_and_emit()


func set_camera_shake_enabled_value(value: bool) -> void:
	if camera_shake_enabled == value:
		return
	camera_shake_enabled = value
	_save_and_emit()


func set_planet_effects_enabled_value(value: bool) -> void:
	if planet_effects_enabled == value:
		return
	planet_effects_enabled = value
	_save_and_emit()


func set_fullscreen_enabled_value(value: bool) -> void:
	if fullscreen_enabled == value:
		return
	fullscreen_enabled = value
	_apply_display_settings()
	_save_and_emit()


func set_resolution_value(value: Variant) -> void:
	var sanitized: Vector2i = _sanitize_resolution(value)
	if resolution == sanitized:
		return
	resolution = sanitized
	_apply_display_settings()
	_save_and_emit()


func get_resolution_options() -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	for option in RESOLUTION_OPTIONS:
		options.append({
			"size": option,
			"label": resolution_to_string(option),
		})
	return options


func get_resolution_option_index(value: Variant) -> int:
	var sanitized: Vector2i = _sanitize_resolution(value)
	for index in range(RESOLUTION_OPTIONS.size()):
		if RESOLUTION_OPTIONS[index] == sanitized:
			return index
	return 0


func get_resolution_from_index(index: int) -> Vector2i:
	if index < 0 or index >= RESOLUTION_OPTIONS.size():
		return DEFAULT_RESOLUTION
	return RESOLUTION_OPTIONS[index]


func resolution_to_string(value: Variant) -> String:
	var sanitized: Vector2i = _sanitize_resolution(value)
	return "%d x %d" % [sanitized.x, sanitized.y]


func get_output_resolution() -> Vector2i:
	var window := get_window()
	if window == null:
		return resolution

	if fullscreen_enabled:
		var screen_index: int = DisplayServer.window_get_current_screen()
		return DisplayServer.screen_get_size(screen_index)

	return window.size


func get_ui_compensation_scale() -> float:
	var output_size: Vector2i = get_output_resolution()
	var internal_size: Vector2 = Vector2(float(resolution.x), float(resolution.y))
	var safe_output_size: Vector2 = Vector2(
		maxf(float(output_size.x), 1.0),
		maxf(float(output_size.y), 1.0)
	)
	var scale_x: float = internal_size.x / safe_output_size.x
	var scale_y: float = internal_size.y / safe_output_size.y
	return clampf(minf(scale_x, scale_y), 0.1, 8.0)


func get_fixed_footprint_scale() -> float:
	if not fullscreen_enabled:
		return 1.0

	return get_ui_compensation_scale()


func volume_scale_to_db_offset(scale: float) -> float:
	var clamped := clampf(scale, MIN_VOLUME_SCALE, MAX_VOLUME_SCALE)
	if clamped <= 0.0001:
		return -80.0
	return linear_to_db(clamped)


func _save_and_emit() -> void:
	save_settings()
	_emit_changed()


func _emit_changed() -> void:
	settings_changed.emit()


func _sanitize_resolution(value: Variant) -> Vector2i:
	var candidate: Vector2i = DEFAULT_RESOLUTION
	if value is Vector2i:
		candidate = value
	elif value is Vector2:
		candidate = Vector2i(roundi(value.x), roundi(value.y))
	elif value is Dictionary:
		candidate = Vector2i(
			int((value as Dictionary).get("x", DEFAULT_RESOLUTION.x)),
			int((value as Dictionary).get("y", DEFAULT_RESOLUTION.y))
		)

	for option in RESOLUTION_OPTIONS:
		if option == candidate:
			return option
	return DEFAULT_RESOLUTION


func _apply_display_settings() -> void:
	var window := get_window()
	if window == null:
		return

	resolution = _sanitize_resolution(resolution)
	window.borderless = false

	if fullscreen_enabled:
		window.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
		window.content_scale_size = resolution
		window.mode = Window.MODE_FULLSCREEN
		window.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		window.scaling_3d_scale = 1.0
	else:
		window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
		window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
		window.content_scale_size = Vector2i.ZERO
		window.mode = Window.MODE_WINDOWED
		window.size = resolution
		var usable_rect: Rect2i = DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
		var centered_position: Vector2i = usable_rect.position + (usable_rect.size - resolution) / 2
		window.position = centered_position
		window.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		window.scaling_3d_scale = 1.0
