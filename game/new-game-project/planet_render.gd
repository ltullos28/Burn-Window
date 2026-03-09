extends Node3D

func _process(_delta: float) -> void:
	# Render the planet relative to the ship simulation position.
	global_position = SimulationState.planet_pos - SimulationState.ship_pos
