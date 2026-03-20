class_name TimewarpSelector
extends RefCounted

var enabled: bool = false
var selection_index: int = -1
var reference_index: int = 0

func reset() -> void:
	enabled = false
	selection_index = -1
	reference_index = 0

func handle_prediction_refresh(point_count: int, is_prediction_stale: bool) -> void:
	reference_index = 0
	ensure_valid(point_count, is_prediction_stale)

func handle_warp_finished() -> void:
	reference_index = 0
	selection_index = 0 if enabled else -1

func collapse_if_stale(is_prediction_stale: bool) -> bool:
	if not enabled or not is_prediction_stale:
		return false

	reset()
	return true

func set_enabled(next_enabled: bool, point_count: int, is_prediction_stale: bool) -> bool:
	enabled = next_enabled and not is_prediction_stale
	reference_index = 0
	if enabled:
		ensure_valid(point_count, is_prediction_stale)
	else:
		selection_index = -1
	return enabled

func is_selection_available(
	is_prediction_stale: bool,
	is_focus_active: bool,
	is_trajectory_display: bool,
	has_solution_points: bool,
	is_revealing: bool
) -> bool:
	return (
		enabled
		and not is_prediction_stale
		and is_focus_active
		and is_trajectory_display
		and has_solution_points
		and not is_revealing
	)

func update_reference_index(
	ship_rel_planet: Vector3,
	ship_points: Array[Vector3],
	is_prediction_stale: bool,
	is_targeted_warp_active: bool
) -> void:
	if not enabled or is_prediction_stale or ship_points.size() <= 1:
		reference_index = 0
		return
	if is_targeted_warp_active:
		return

	var start_index: int = clampi(reference_index, 0, ship_points.size() - 1)
	var end_index: int = min(ship_points.size() - 1, start_index + 240)
	var best_index: int = start_index
	var best_distance_sq: float = ship_rel_planet.distance_squared_to(ship_points[start_index])

	for i in range(start_index + 1, end_index + 1):
		var dist_sq: float = ship_rel_planet.distance_squared_to(ship_points[i])
		if dist_sq < best_distance_sq:
			best_distance_sq = dist_sq
			best_index = i

	reference_index = best_index

func ensure_valid(point_count: int, is_prediction_stale: bool) -> void:
	if not enabled or is_prediction_stale:
		selection_index = -1
		return

	if point_count <= 1:
		reference_index = 0
		selection_index = -1
		return

	if selection_index < 0:
		selection_index = 0
		return

	var max_index: int = max(point_count - 1 - reference_index, 0)
	selection_index = clampi(selection_index, 0, max_index)

func move_selection(direction: int, point_count: int, step_size: int) -> bool:
	if point_count <= 1:
		return false

	var dir_sign: int = sign(direction)
	if dir_sign == 0:
		return false

	var max_index: int = max(point_count - 1 - reference_index, 0)
	selection_index = clampi(selection_index + dir_sign * step_size, 0, max_index)
	return true

func cancel_selection(point_count: int, is_prediction_stale: bool) -> void:
	ensure_valid(point_count, is_prediction_stale)
	if selection_index >= 0:
		selection_index = 0

func get_selection_step_size(
	display_duration_used: float,
	prediction_step_seconds: float,
	fine_step_fraction_of_horizon: float,
	coarse_step_fraction_of_horizon: float,
	coarse: bool
) -> int:
	var horizon_seconds: float = max(display_duration_used, prediction_step_seconds)
	var fraction: float = coarse_step_fraction_of_horizon if coarse else fine_step_fraction_of_horizon
	var step_seconds: float = max(prediction_step_seconds, horizon_seconds * fraction)
	return max(1, int(round(step_seconds / prediction_step_seconds)))

func get_selection_step_seconds(
	display_duration_used: float,
	prediction_step_seconds: float,
	fine_step_fraction_of_horizon: float,
	coarse_step_fraction_of_horizon: float,
	coarse: bool
) -> int:
	return get_selection_step_size(
		display_duration_used,
		prediction_step_seconds,
		fine_step_fraction_of_horizon,
		coarse_step_fraction_of_horizon,
		coarse
	) * int(prediction_step_seconds)

func get_target_index(point_count: int) -> int:
	if selection_index < 0 or point_count <= 0:
		return -1
	return clampi(reference_index + selection_index, 0, point_count - 1)

func get_selected_time_seconds(prediction_step_seconds: float) -> float:
	if selection_index <= 0:
		return 0.0
	return float(selection_index) * prediction_step_seconds
