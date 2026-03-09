extends Label3D

@export var player_path: NodePath

var player: Node

func _ready() -> void:
	player = get_node_or_null(player_path)

func _process(_delta: float) -> void:
	var vel: Vector3 = SimulationState.ship_vel
	var speed: float = vel.length()
	var pos: Vector3 = SimulationState.ship_pos

	var to_planet: Vector3 = SimulationState.planet_pos - SimulationState.ship_pos
	var distance_to_planet: float = to_planet.length()
	var gravity_accel: float = SimulationState.gravity_accel_at(SimulationState.ship_pos).length()

	var flight_mode_text: String = "UNKNOWN"
	if player != null:
		var fm_variant = player.get("flight_mode")
		if typeof(fm_variant) == TYPE_BOOL:
			flight_mode_text = "ON" if fm_variant else "OFF"

	text = ""
	text += "FLIGHT MODE: %s\n" % flight_mode_text
	text += "SPEED: %.2f\n" % speed
	text += "VEL: (%.2f, %.2f, %.2f)\n" % [vel.x, vel.y, vel.z]
	text += "POS: (%.2f, %.2f, %.2f)\n" % [pos.x, pos.y, pos.z]
	text += "DIST: %.2f\n" % distance_to_planet
	text += "GRAV: %.4f" % gravity_accel
