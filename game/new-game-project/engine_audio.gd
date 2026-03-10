extends Node3D

@export var engine_loop_player_path: NodePath
@export var rattle_player_path: NodePath

@export var rattle_sounds: Array[AudioStream] = []

@export var engine_volume_db: float = -14.0
@export var rattle_volume_db: float = -16.0

@export var min_rattle_wait: float = 0.35
@export var max_rattle_wait: float = 1.25

var engine_loop_player: AudioStreamPlayer3D
var rattle_player: AudioStreamPlayer3D

var thrust_active: bool = false
var rattle_timer: float = 0.0

func _ready() -> void:
	randomize()

	engine_loop_player = get_node_or_null(engine_loop_player_path) as AudioStreamPlayer3D
	rattle_player = get_node_or_null(rattle_player_path) as AudioStreamPlayer3D

	if engine_loop_player != null:
		engine_loop_player.volume_db = engine_volume_db

	if rattle_player != null:
		rattle_player.volume_db = rattle_volume_db

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
		if engine_loop_player != null and engine_loop_player.stream != null and not engine_loop_player.playing:
			engine_loop_player.play()
		_schedule_next_rattle()
	else:
		if engine_loop_player != null and engine_loop_player.playing:
			engine_loop_player.stop()

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
