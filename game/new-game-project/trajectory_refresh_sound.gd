extends AudioStreamPlayer3D

@export var loop_while_computing: bool = true
@export var one_shot_duration: float = 1.8
@export var target_volume_db: float = -10.0

var remaining_time: float = 0.0
var active: bool = false

func _ready() -> void:
	volume_db = target_volume_db

func start_refresh(duration: float) -> void:
	remaining_time = max(duration, 0.01)
	active = true

	if stream == null:
		return

	if not playing:
		play()

func _process(delta: float) -> void:
	if not active:
		return

	remaining_time -= delta

	if remaining_time <= 0.0:
		active = false
		if playing:
			stop()

func stop_refresh() -> void:
	active = false
	remaining_time = 0.0
	if playing:
		stop()
