extends Node3D

signal fuel_changed(current: float, maximum: float)
signal oxygen_changed(current: float, maximum: float)
signal fuel_depleted
signal oxygen_depleted

@export var ship_path: NodePath
@export var player_path: NodePath
@export var fuel_tank_path: NodePath
@export var oxygen_tank_path: NodePath

@export_group("Starting Amounts")
@export var starting_fuel: float = 100.0
@export var starting_oxygen: float = 100.0
@export var max_fuel: float = 100.0
@export var max_oxygen: float = 100.0

@export_group("Drain Rates")
@export var fuel_burn_per_sim_second: float = 2.5
@export var oxygen_burn_per_sim_second: float = 0.08
@export var oxygen_scales_with_timewarp: bool = true
@export var oxygen_death_message: String = "OXYGEN DEPLETED"

var fuel_current: float = 0.0
var oxygen_current: float = 0.0

var _ship: Node
var _player: Node
var _fuel_tank: Node
var _oxygen_tank: Node
var _last_sim_time: float = 0.0
var _oxygen_failure_triggered: bool = false
var _last_fuel_ratio: float = -1.0
var _last_oxygen_ratio: float = -1.0

func _ready() -> void:
	_resolve_refs()
	_apply_session_resource_settings()
	reset_resources()
	_last_sim_time = SimulationState.sim_time

func _physics_process(delta: float) -> void:
	_resolve_refs()

	# SimulationState.reset() rewinds sim_time to zero after death/restart.
	if SimulationState.sim_time + 0.0001 < _last_sim_time:
		_apply_session_resource_settings()
		reset_resources()

	_last_sim_time = SimulationState.sim_time

	var sim_delta: float = SimulationState.get_current_sim_delta(delta)
	if sim_delta <= 0.0:
		return

	_process_oxygen(delta, sim_delta)
	_process_fuel(sim_delta)

func can_thrust() -> bool:
	return fuel_current > 0.0

func get_fuel_ratio() -> float:
	if max_fuel <= 0.0:
		return 0.0
	return clampf(fuel_current / max_fuel, 0.0, 1.0)

func get_oxygen_ratio() -> float:
	if max_oxygen <= 0.0:
		return 0.0
	return clampf(oxygen_current / max_oxygen, 0.0, 1.0)

func reset_resources() -> void:
	fuel_current = clampf(starting_fuel, 0.0, max_fuel)
	oxygen_current = clampf(starting_oxygen, 0.0, max_oxygen)
	_oxygen_failure_triggered = false
	_last_fuel_ratio = -1.0
	_last_oxygen_ratio = -1.0
	_emit_resource_updates()
	_update_tank_visuals()

func set_fuel_fraction(value: float) -> void:
	_set_fuel(max_fuel * clampf(value, 0.0, 1.0))

func set_oxygen_fraction(value: float) -> void:
	_set_oxygen(max_oxygen * clampf(value, 0.0, 1.0))

func _process_fuel(sim_delta: float) -> void:
	if fuel_current <= 0.0:
		_stop_thrust_if_needed()
		return

	if _ship != null and bool(_ship.get("thrust_held")):
		_set_fuel(fuel_current - fuel_burn_per_sim_second * sim_delta)
		if fuel_current <= 0.0:
			_stop_thrust_if_needed()

func _process_oxygen(raw_delta: float, sim_delta: float) -> void:
	if oxygen_current <= 0.0:
		_trigger_oxygen_failure_if_needed()
		return

	var drain_delta: float = sim_delta if oxygen_scales_with_timewarp else raw_delta
	_set_oxygen(oxygen_current - oxygen_burn_per_sim_second * drain_delta)
	if oxygen_current <= 0.0:
		_trigger_oxygen_failure_if_needed()

func _stop_thrust_if_needed() -> void:
	if _ship != null and _ship.has_method("set_thrust_held"):
		_ship.set_thrust_held(false)
	if _player != null and _player.has_method("set_thrust_feedback_active"):
		_player.set_thrust_feedback_active(false)

func _trigger_oxygen_failure_if_needed() -> void:
	if _oxygen_failure_triggered:
		return
	_oxygen_failure_triggered = true
	if _player != null and _player.has_method("trigger_death"):
		_player.trigger_death(oxygen_death_message)

func _set_fuel(value: float) -> void:
	var clamped_value: float = clampf(value, 0.0, max_fuel)
	if is_equal_approx(clamped_value, fuel_current):
		return

	var was_above_zero: bool = fuel_current > 0.0
	fuel_current = clamped_value
	emit_signal("fuel_changed", fuel_current, max_fuel)
	_update_tank_visuals()
	if was_above_zero and fuel_current <= 0.0:
		emit_signal("fuel_depleted")

func _set_oxygen(value: float) -> void:
	var clamped_value: float = clampf(value, 0.0, max_oxygen)
	if is_equal_approx(clamped_value, oxygen_current):
		return

	var was_above_zero: bool = oxygen_current > 0.0
	oxygen_current = clamped_value
	emit_signal("oxygen_changed", oxygen_current, max_oxygen)
	_update_tank_visuals()
	if was_above_zero and oxygen_current <= 0.0:
		emit_signal("oxygen_depleted")

func _emit_resource_updates() -> void:
	emit_signal("fuel_changed", fuel_current, max_fuel)
	emit_signal("oxygen_changed", oxygen_current, max_oxygen)

func _update_tank_visuals() -> void:
	var fuel_ratio: float = get_fuel_ratio()
	var oxygen_ratio: float = get_oxygen_ratio()

	if not is_equal_approx(fuel_ratio, _last_fuel_ratio):
		if _fuel_tank != null and _fuel_tank.has_method("set_fill_ratio"):
			_fuel_tank.set_fill_ratio(fuel_ratio)
		_last_fuel_ratio = fuel_ratio

	if not is_equal_approx(oxygen_ratio, _last_oxygen_ratio):
		if _oxygen_tank != null and _oxygen_tank.has_method("set_fill_ratio"):
			_oxygen_tank.set_fill_ratio(oxygen_ratio)
		_last_oxygen_ratio = oxygen_ratio

func _resolve_refs() -> void:
	if _ship == null:
		_ship = get_node_or_null(ship_path)
	if _player == null:
		_player = get_node_or_null(player_path)
	if _fuel_tank == null:
		_fuel_tank = get_node_or_null(fuel_tank_path)
	if _oxygen_tank == null:
		_oxygen_tank = get_node_or_null(oxygen_tank_path)


func _apply_session_resource_settings() -> void:
	var session: Node = get_node_or_null("/root/GameSession")
	if session == null or not session.has_method("get_active_resource_settings"):
		return

	var resource_settings: Dictionary = session.get_active_resource_settings()
	if resource_settings.is_empty():
		return

	if resource_settings.has("starting_fuel"):
		starting_fuel = float(resource_settings.get("starting_fuel", starting_fuel))
	if resource_settings.has("max_fuel"):
		max_fuel = float(resource_settings.get("max_fuel", max_fuel))
	if resource_settings.has("fuel_burn_per_sim_second"):
		fuel_burn_per_sim_second = float(resource_settings.get("fuel_burn_per_sim_second", fuel_burn_per_sim_second))
	if resource_settings.has("starting_oxygen"):
		starting_oxygen = float(resource_settings.get("starting_oxygen", starting_oxygen))
	if resource_settings.has("max_oxygen"):
		max_oxygen = float(resource_settings.get("max_oxygen", max_oxygen))
	if resource_settings.has("oxygen_burn_per_sim_second"):
		oxygen_burn_per_sim_second = float(resource_settings.get("oxygen_burn_per_sim_second", oxygen_burn_per_sim_second))
	if resource_settings.has("oxygen_scales_with_timewarp"):
		oxygen_scales_with_timewarp = bool(resource_settings.get("oxygen_scales_with_timewarp", oxygen_scales_with_timewarp))
