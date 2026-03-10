extends AudioStreamPlayer3D

@export var sounds: Array[AudioStream] = []
@export var autoplay_on_ready: bool = true

@export var min_wait: float = 8.0
@export var max_wait: float = 20.0

@export var min_volume_db: float = -18.0
@export var max_volume_db: float = -10.0

@export var min_pitch_scale: float = 0.96
@export var max_pitch_scale: float = 1.04

var timer: float = 0.0

func _ready() -> void:
	randomize()
	_schedule_next()

func _process(delta: float) -> void:
	if not autoplay_on_ready:
		return

	if playing:
		return

	timer -= delta
	if timer <= 0.0:
		_play_random()
		_schedule_next()

func _schedule_next() -> void:
	timer = randf_range(min_wait, max_wait)

func _play_random() -> void:
	if sounds.is_empty():
		return

	stream = sounds[randi() % sounds.size()]
	volume_db = randf_range(min_volume_db, max_volume_db)
	pitch_scale = randf_range(min_pitch_scale, max_pitch_scale)
	play()
