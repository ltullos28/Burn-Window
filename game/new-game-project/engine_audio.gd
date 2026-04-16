extends Node3D

@export var engine_loop_player_path: NodePath
@export var rattle_player_path: NodePath

@export var rattle_sounds: Array[AudioStream] = []

@export var engine_volume_db: float = -14.0
@export var rattle_volume_db: float = -16.0

@export var min_rattle_wait: float = 0.35
@export var max_rattle_wait: float = 1.25

# Skip the startup portion after the first full play
@export var loop_restart_seconds: float = 1.0

var engine_loop_player: AudioStreamPlayer3D
var rattle_player: AudioStreamPlayer3D

var thrust_active: bool = false
var rattle_timer: float = 0.0
var _base_engine_volume_db: float = -14.0
var _base_rattle_volume_db: float = -16.0


func _ready() -> void:
	randomize()

	engine_loop_player = get_node_or_null(engine_loop_player_path) as AudioStreamPlayer3D
	rattle_player = get_node_or_null(rattle_player_path) as AudioStreamPlayer3D

	_base_engine_volume_db = engine_volume_db
	_base_rattle_volume_db = rattle_volume_db

	if engine_loop_player != null:
		if not engine_loop_player.finished.is_connected(_on_engine_loop_finished):
			engine_loop_player.finished.connect(_on_engine_loop_finished)

	_apply_settings()
	var settings = _settings()
	if settings != null and not settings.settings_changed.is_connected(_apply_settings):
		settings.settings_changed.connect(_apply_settings)

	_schedule_next_rattle()


func _process(delta: float) -> void:
	if not thrust_active:
		return

	rattle_timer -= delta
	if rattle_timer <= 0.0:
		_play_rattle()
		_schedule_next_rattle()


func set_thrust_audio_active(active: bool) -> void:
	if thrust_active == active:
		return

	thrust_active = active

	if thrust_active:
		if engine_loop_player != null and engine_loop_player.stream != null:
			# First time: play from the real start
			if not engine_loop_player.playing:
				engine_loop_player.play(0.0)
		_schedule_next_rattle()
	else:
		if engine_loop_player != null and engine_loop_player.playing:
			engine_loop_player.stop()


func _on_engine_loop_finished() -> void:
	if not thrust_active:
		return
	if engine_loop_player == null or engine_loop_player.stream == null:
		return

	# After the first pass, skip the startup transient
	engine_loop_player.play(loop_restart_seconds)


func _schedule_next_rattle() -> void:
	rattle_timer = randf_range(min_rattle_wait, max_rattle_wait)


func _play_rattle() -> void:
	if rattle_player == null:
		return

	if rattle_sounds.is_empty():
		return

	if rattle_player.playing:
		return

	rattle_player.stream = rattle_sounds[randi() % rattle_sounds.size()]
	rattle_player.play()


func _apply_settings() -> void:
	var settings = _settings()
	if settings == null:
		return

	if engine_loop_player != null:
		engine_loop_player.volume_db = _base_engine_volume_db + settings.volume_scale_to_db_offset(settings.engine_volume)

	if rattle_player != null:
		rattle_player.volume_db = _base_rattle_volume_db + settings.volume_scale_to_db_offset(settings.engine_volume)


func _settings():
	return get_node_or_null("/root/GameSettings")
