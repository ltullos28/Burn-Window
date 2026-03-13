extends AudioStreamPlayer

@export var autoplay_on_ready: bool = true
@export var fade_in_time: float = 2.0
@export var target_volume_db: float = -20.0
@export var restart_if_finished: bool = true

var fading_in: bool = false

func _ready() -> void:
	if autoplay_on_ready and stream != null:
		volume_db = -60.0
		play()
		fading_in = true

func _process(delta: float) -> void:
	if restart_if_finished and autoplay_on_ready and stream != null and not playing:
		play()

	if fading_in:
		if fade_in_time <= 0.0:
			volume_db = target_volume_db
			fading_in = false
			return

		var step := (target_volume_db + 60.0) / fade_in_time
		volume_db += step * delta

		if volume_db >= target_volume_db:
			volume_db = target_volume_db
			fading_in = false
