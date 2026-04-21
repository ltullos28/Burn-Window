extends Control

const BodyFocusProjectionHelperModel := preload("res://trajectoryMath/body_focus_projection_helper.gd")
const LocalOrbitMarkersModel := preload("res://trajectoryMath/local_orbit_markers.gd")
const PredictionHorizonModel := preload("res://trajectoryMath/prediction_horizon.gd")
const TimewarpSelectorModel := preload("res://trajectoryMath/timewarp_selector.gd")
const TrajectoryProjectionCacheModel := preload("res://trajectoryMath/trajectory_projection_cache.gd")
const PRIMARY_BODY_NAME := &"planet"
const MOON_BODY_NAME := &"moon"
const MAX_DISPLAY_SHIP_POINTS := 1600
const REVEAL_FRONTIER_DENSE_STEPS := 140

enum CenterMode {
	PLANET,
	MOON,
	SHIP
}

enum DisplayMode {
	TRAJECTORY,
	INCLINATION
}

enum RefreshFlowState {
	IDLE,
	CALCULATING,
	DRAWING
}

enum RefreshCalcPhase {
	PREPARE,
	PREDICT,
	ANALYZE,
	BUILD_SOLUTION,
	BUILD_CACHE,
	READY
}

@export var ship_path: NodePath
@export var impact_sound_player_path: NodePath
@export var ghost_lifetime_seconds: float = 10.0
@export var pixels_per_unit: float = 0.046
@export var min_pixels_per_unit: float = 0.0008
@export var max_pixels_per_unit: float = 0.12
@export var moon_max_pixels_per_unit: float = 0.24
@export var zoom_step: float = 0.0025

@export var prediction_step_seconds: float = 2
@export var prediction_steps: int = 4000
@export var reveal_duration: float = 5
@export_range(3.0, 5.0, 0.1) var refresh_target_duration_seconds: float = 4.0
@export var refresh_max_prediction_steps_per_frame: int = 96
@export var calculating_dot_interval_seconds: float = 1.0
@export var calculating_max_dots: int = 5
@export var show_calculating_status_box: bool = true
@export var calculating_status_box_size: Vector2 = Vector2(380.0, 96.0)
@export var calculating_status_box_offset: Vector2 = Vector2(0.0, 112.0)
@export var refresh_audio_player_path: NodePath
@export var reveal_sweep_player_path: NodePath
@export var reveal_sweep_low_pitch_scale: float = 0.2
@export var reveal_sweep_high_pitch_scale: float = 0.8

# Dynamic prediction control
@export var min_prediction_steps: int = 1200
@export var max_prediction_steps: int = 12000
@export var period_prediction_margin: float = 1.0
@export var moon_encounter_extra_time: float = 400.0
@export var strong_moon_ca_multiplier: float = 3.0
@export var moon_local_period_prediction_margin: float = 1.15
@export var moon_local_escape_prediction_seconds: float = 220.0
@export var moon_local_min_prediction_steps: int = 240
@export var moon_local_max_prediction_steps: int = 1800
@export var focused_child_encounter_extra_characteristic_times: float = 7.2
@export var focused_child_strong_ca_body_radii: float = 2.5
@export var focused_child_local_period_margin: float = 1.15
@export var focused_child_local_escape_characteristic_times: float = 3.5
@export var focused_child_local_min_prediction_steps: int = 240
@export var focused_child_local_max_prediction_steps: int = 1800
@export var closure_distance_ratio_tolerance: float = 0.12
@export var closure_scan_chunk_steps: int = 24
@export var closure_min_threshold_step_multiplier: float = 2.5
@export var extrema_window_radius: int = 4
@export var radial_extrema_tolerance: float = 4.0
@export var center_mode: CenterMode = CenterMode.PLANET
@export var display_mode: DisplayMode = DisplayMode.TRAJECTORY

@export var ghost_dash_length: int = 10
@export var ghost_gap_length: int = 6
@export var ship_mode_ghost_trail_steps: int = 220
@export var moon_escape_tail_steps: int = 52
@export var timewarp_fine_step_fraction_of_horizon: float = 1.0 / 120.0
@export var timewarp_coarse_step_fraction_of_horizon: float = 1.0 / 24.0

@export var center_transition_duration: float = 0.65
@export var debug_render_instrumentation: bool = false
@export var debug_timewarp_selector: bool = false
@export var debug_equator_instrument: bool = false
@export var equator_coplanar_threshold_degrees: float = 0.5
@export var show_marker_distance_labels: bool = false

var ship: Node3D

var predictor := TrajectoryPredictor.new()
var orbit_solver := OrbitSolver.new()
var solution := TrajectorySolution.new()
var refresh_flow_state: RefreshFlowState = RefreshFlowState.IDLE
var refresh_calc_phase: RefreshCalcPhase = RefreshCalcPhase.PREPARE
var refresh_calc_elapsed: float = 0.0
var refresh_calc_prediction_steps_to_use: int = 0
var refresh_calc_prediction_job: Dictionary = {}
var refresh_calc_prediction: Dictionary = {}
var refresh_calc_orbit: Dictionary = {}
var refresh_calc_prebuilt_cache: Dictionary = {}
var refresh_calc_pending_solution: TrajectorySolution = null
var refresh_calc_ship_pos: Vector3 = Vector3.ZERO
var refresh_calc_ship_vel: Vector3 = Vector3.ZERO
var refresh_calc_sim_time: float = 0.0
var timewarp_solution_start_sim_time: float = 0.0

var is_revealing: bool = false
var reveal_elapsed: float = 0.0
var ghost_elapsed: float = 0.0

var current_view_offset: Vector2 = Vector2.ZERO
var transition_start_offset: Vector2 = Vector2.ZERO
var transition_elapsed: float = 0.0
var transition_active: bool = false

var focus_active: bool = false
var body_focus_projection := BodyFocusProjectionHelperModel.new()
var local_orbit_markers := LocalOrbitMarkersModel.new()
var prediction_horizon := PredictionHorizonModel.new()
var timewarp_selector := TimewarpSelectorModel.new()
var trajectory_projection_cache := TrajectoryProjectionCacheModel.new()
var previous_targeted_warp_active: bool = false
var refresh_sound_player: Node = null
var reveal_sweep_player: Node = null
var impact_sound_player: Node = null

var geometry_cache_dirty: bool = true
var cached_ship_source_points: Array[Vector3] = []
var cached_ship_display_points: Array[Vector3] = []
var cached_ship_display_source_indices: Array[int] = []
var cached_ship_display_runs: Array[Dictionary] = []
var cached_ship_runs: Array[Dictionary] = []
var cached_main_visible_count: int = 0
var cached_ship_impact_found: bool = false
var cached_ship_impact_index: int = -1
var cached_focused_child_body_name: StringName = &""
var cached_focused_child_draw_points: Array[Vector3] = []
var cached_focused_child_local_points: Array[Vector3] = []
var cached_focused_child_local_source_indices: Array[int] = []
var cached_focused_child_local_ca_index: int = -1
var cached_focused_child_local_pe_index: int = -1
var cached_focused_child_local_ap_index: int = -1
var cached_focused_child_local_impact_found: bool = false
var cached_focused_child_local_impact_index: int = -1
var cached_show_focused_child_local_ca_marker: bool = false
var cached_show_focused_child_escape_marker: bool = false
var cached_focused_child_escape_marker_local_index: int = -1
var cached_focused_child_entry_index: int = -1
var cached_focused_child_exit_index: int = -1
var cached_currently_in_focused_child_dominance: bool = false
var cached_focused_child_encounter: Dictionary = {}
var cached_active_body_encounter: Dictionary = {}
var impact_sound_pending: bool = false
var impact_sound_played: bool = false
var focused_child_body_name: StringName = MOON_BODY_NAME
var equator_reference_body_name: StringName = PRIMARY_BODY_NAME
var equator_last_stable_line_basis: Dictionary = {}
var equator_last_stable_basis_signature: String = ""
var visual_dirty: bool = true
var projected_render_dirty: bool = true
var last_draw_visible_count: int = -1
var last_draw_main_visible_count: int = -1
var last_draw_ghost_alpha: float = -1.0
var last_draw_view_offset: Vector2 = Vector2(1e20, 1e20)
var last_draw_ship_pos: Vector3 = Vector3(1e20, 1e20, 1e20)
var last_draw_ship_vel: Vector3 = Vector3(1e20, 1e20, 1e20)
var last_draw_center_mode: int = -1
var last_draw_display_mode: int = -1
var last_draw_pixels_per_unit: float = -1.0
var last_draw_focused_child_body_name: StringName = &""
var last_draw_child_positions_signature: int = 0
var cached_projected_center: Vector2 = Vector2.ZERO
var cached_projected_view_offset: Vector2 = Vector2(1e20, 1e20)
var cached_projected_pixels_per_unit: float = -1.0
var cached_projected_visible_count: int = -1
var cached_projected_main_visible_count: int = -1
var cached_projected_center_mode: int = -1
var cached_projected_focused_child_body_name: StringName = &""
var cached_projected_local_anchor: Vector3 = Vector3(1e20, 1e20, 1e20)
var cached_projected_ship_points: PackedVector2Array = PackedVector2Array()
var cached_projected_ship_run_draws: Array[Dictionary] = []
var cached_projected_local_points: PackedVector2Array = PackedVector2Array()
var cached_projected_local_run_draws: Array[Dictionary] = []
var cached_projected_child_ghosts: Dictionary = {}
var cached_child_orbit_track_data: Dictionary = {}
var cached_child_orbit_projected_points: Dictionary = {}
var cached_child_orbit_projected_center: Vector2 = Vector2(1e20, 1e20)
var cached_child_orbit_projected_view_offset: Vector2 = Vector2(1e20, 1e20)
var cached_child_orbit_projected_pixels_per_unit: float = -1.0
var debug_draw_calls_since_log: int = 0
var debug_projection_cache_hits_since_log: int = 0
var debug_projection_cache_rebuilds_since_log: int = 0
var debug_last_projected_points_built: int = 0
var marker_toggle_key_was_down: bool = false

func _unhandled_input(event: InputEvent) -> void:
	return

func _is_marker_distance_toggle_pressed() -> bool:
	if InputMap.has_action("toggle_marker_distance_labels"):
		return Input.is_action_just_pressed("toggle_marker_distance_labels")
	var key_down: bool = Input.is_physical_key_pressed(KEY_R)
	var just_pressed: bool = key_down and not marker_toggle_key_was_down
	marker_toggle_key_was_down = key_down
	return just_pressed

func _get_body_prediction(prediction: Dictionary, body_name: StringName) -> Dictionary:
	var body_predictions: Dictionary = prediction.get("body_predictions", {})
	return body_predictions.get(String(body_name), {})

func _get_body_prediction_relative_points(prediction: Dictionary, body_name: StringName) -> Array[Vector3]:
	var body_prediction: Dictionary = _get_body_prediction(prediction, body_name)
	if body_prediction.is_empty():
		return []
	return _get_typed_vector3_array(body_prediction.get("relative_points", []))

func _get_body_prediction_dominance_mask(prediction: Dictionary, body_name: StringName) -> Array[bool]:
	var body_prediction: Dictionary = _get_body_prediction(prediction, body_name)
	var typed_values: Array[bool] = []
	for value in body_prediction.get("dominance_mask", []):
		typed_values.append(bool(value))
	return typed_values

func _get_body_prediction_closest_approach(prediction: Dictionary, body_name: StringName) -> Dictionary:
	var body_prediction: Dictionary = _get_body_prediction(prediction, body_name)
	return body_prediction.get("closest_approach", {})

func _mark_visual_dirty() -> void:
	visual_dirty = true

func _invalidate_projected_render_cache() -> void:
	projected_render_dirty = true
	cached_projected_ship_points = PackedVector2Array()
	cached_projected_ship_run_draws.clear()
	cached_projected_local_points = PackedVector2Array()
	cached_projected_local_run_draws.clear()
	cached_projected_child_ghosts.clear()
	_invalidate_child_orbit_projected_cache()

func _invalidate_child_orbit_track_cache() -> void:
	cached_child_orbit_track_data.clear()
	_invalidate_child_orbit_projected_cache()

func _invalidate_child_orbit_projected_cache() -> void:
	cached_child_orbit_projected_points.clear()
	cached_child_orbit_projected_center = Vector2(1e20, 1e20)
	cached_child_orbit_projected_view_offset = Vector2(1e20, 1e20)
	cached_child_orbit_projected_pixels_per_unit = -1.0

func _get_child_positions_signature() -> int:
	var signature: int = 17
	for body_name in _get_available_focused_child_body_names():
		var pos: Vector3 = SimulationState.get_body_position(body_name)
		signature = signature * 31 + hash(body_name)
		signature = signature * 31 + int(round(pos.x * 1000.0))
		signature = signature * 31 + int(round(pos.y * 1000.0))
		signature = signature * 31 + int(round(pos.z * 1000.0))
	return signature

func _get_current_visible_count() -> int:
	if solution.ship_points.size() <= 1:
		return 0
	var ratio: float = clampf(reveal_elapsed / reveal_duration, 0.0, 1.0) if reveal_duration > 0.0 else 1.0
	var display_step_cap: int = min(solution.ship_points.size(), max(2, solution.display_steps_used))
	var visible_count: int = max(2, int(round((display_step_cap - 1) * ratio)) + 1)
	return min(visible_count, display_step_cap)

func _get_current_main_visible_count(visible_count: int) -> int:
	if visible_count <= 0:
		return 0
	var active_local_segment: Dictionary = _get_active_local_segment()
	var entry_index: int = active_local_segment.get("entry_index", cached_focused_child_entry_index)
	var main_visible_count: int = visible_count
	if center_mode == CenterMode.MOON and entry_index >= 0 and entry_index < visible_count:
		main_visible_count = max(2, entry_index + 1)
	return min(main_visible_count, cached_ship_source_points.size())

func _get_current_ghost_alpha() -> float:
	if ghost_lifetime_seconds <= 0.0:
		return 1.0
	return clampf(1.0 - (ghost_elapsed / ghost_lifetime_seconds), 0.0, 1.0)

func _should_redraw_this_frame() -> bool:
	if visual_dirty:
		return true

	var visible_count: int = _get_current_visible_count()
	var main_visible_count: int = _get_current_main_visible_count(visible_count)
	var ghost_alpha: float = _get_current_ghost_alpha()
	var focused_child_name: StringName = _get_selected_focused_child_body_name()
	var child_signature: int = _get_child_positions_signature()

	if visible_count != last_draw_visible_count:
		return true
	if main_visible_count != last_draw_main_visible_count:
		return true
	if absf(ghost_alpha - last_draw_ghost_alpha) > 0.002:
		return true
	if current_view_offset.distance_squared_to(last_draw_view_offset) > 0.000001:
		return true
	if SimulationState.ship_pos != last_draw_ship_pos:
		return true
	if SimulationState.ship_vel != last_draw_ship_vel:
		return true
	if center_mode != last_draw_center_mode or display_mode != last_draw_display_mode:
		return true
	if absf(pixels_per_unit - last_draw_pixels_per_unit) > 0.000001:
		return true
	if focused_child_name != last_draw_focused_child_body_name:
		return true
	if child_signature != last_draw_child_positions_signature:
		return true
	return false

func _record_draw_state(visible_count: int, main_visible_count: int, ghost_alpha: float) -> void:
	last_draw_visible_count = visible_count
	last_draw_main_visible_count = main_visible_count
	last_draw_ghost_alpha = ghost_alpha
	last_draw_view_offset = current_view_offset
	last_draw_ship_pos = SimulationState.ship_pos
	last_draw_ship_vel = SimulationState.ship_vel
	last_draw_center_mode = center_mode
	last_draw_display_mode = display_mode
	last_draw_pixels_per_unit = pixels_per_unit
	last_draw_focused_child_body_name = _get_selected_focused_child_body_name()
	last_draw_child_positions_signature = _get_child_positions_signature()

func _log_render_instrumentation_if_needed() -> void:
	if not debug_render_instrumentation:
		return
	var frame_count: int = Engine.get_process_frames()
	if frame_count % 120 != 0:
		return
	print(
		"TrajectoryMap render stats | draws=%d | projection_cache_hits=%d | projection_cache_rebuilds=%d | last_projected_points=%d"
		% [
			debug_draw_calls_since_log,
			debug_projection_cache_hits_since_log,
			debug_projection_cache_rebuilds_since_log,
			debug_last_projected_points_built
		]
	)
	debug_draw_calls_since_log = 0
	debug_projection_cache_hits_since_log = 0
	debug_projection_cache_rebuilds_since_log = 0

func _ready() -> void:
	ship = get_node_or_null(ship_path) as Node3D
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	timewarp_solution_start_sim_time = SimulationState.sim_time

	_sanitize_modes()
	_ensure_focused_child_body_valid()

	current_view_offset = _get_target_view_offset()
	transition_start_offset = current_view_offset
	previous_targeted_warp_active = SimulationState.is_targeted_warp_active()
	_resolve_refresh_sound_player()
	_resolve_reveal_sweep_player()
	_resolve_impact_sound_player()
	_mark_visual_dirty()

func _process(delta: float) -> void:
	_sanitize_modes()
	_collapse_timewarp_if_stale()
	if focus_active and _is_marker_distance_toggle_pressed():
		toggle_marker_distance_labels()

	if refresh_flow_state == RefreshFlowState.CALCULATING:
		refresh_calc_elapsed += delta
		_update_refresh_calculation()
		_mark_visual_dirty()

	if is_revealing:
		reveal_elapsed += delta
		if reveal_elapsed >= reveal_duration:
			reveal_elapsed = reveal_duration
			is_revealing = false
			if refresh_flow_state == RefreshFlowState.DRAWING:
				refresh_flow_state = RefreshFlowState.IDLE
				_stop_reveal_sweep_sound()
		_mark_visual_dirty()
		_update_reveal_sweep_pitch()

	ghost_elapsed += delta

	_update_center_transition(delta)
	_update_timewarp_selector()

	var targeted_warp_active_now: bool = SimulationState.is_targeted_warp_active()
	if not previous_targeted_warp_active and targeted_warp_active_now:
		_play_timewarp_sound()
	if previous_targeted_warp_active and not targeted_warp_active_now:
		_stop_timewarp_sound()
		timewarp_selector.handle_warp_finished()
		request_refresh()
	previous_targeted_warp_active = targeted_warp_active_now

	_rebuild_geometry_cache_if_needed()
	_update_impact_sound_trigger()
	if _should_redraw_this_frame():
		queue_redraw()
		visual_dirty = false
	_log_render_instrumentation_if_needed()

func _sanitize_modes() -> void:
	var previous_center_mode: int = center_mode
	var previous_focused_child_body_name: StringName = focused_child_body_name
	var previous_equator_reference_body_name: StringName = equator_reference_body_name
	_ensure_focused_child_body_valid()
	_ensure_equator_reference_body_valid()
	if center_mode == CenterMode.MOON and _get_selected_focused_child_body_name() == &"":
		center_mode = CenterMode.PLANET
	if (
		previous_center_mode != center_mode
		or previous_focused_child_body_name != focused_child_body_name
		or previous_equator_reference_body_name != equator_reference_body_name
	):
		_mark_visual_dirty()
		_invalidate_projected_render_cache()

func _get_available_focused_child_body_names() -> Array[StringName]:
	if SimulationState.has_method("get_child_body_names"):
		return SimulationState.get_child_body_names(PRIMARY_BODY_NAME)
	var result: Array[StringName] = []
	if SimulationState.has_body(MOON_BODY_NAME):
		result.append(MOON_BODY_NAME)
	return result

func _get_default_focused_child_body_name() -> StringName:
	var child_body_names: Array[StringName] = _get_available_focused_child_body_names()
	if child_body_names.is_empty():
		return &""
	if child_body_names.find(MOON_BODY_NAME) >= 0:
		return MOON_BODY_NAME
	return child_body_names[0]

func _select_default_focused_child_body() -> bool:
	var default_body_name: StringName = _get_default_focused_child_body_name()
	if default_body_name == &"":
		focused_child_body_name = &""
		return false
	focused_child_body_name = default_body_name
	return true

func _ensure_focused_child_body_valid() -> void:
	var child_body_names: Array[StringName] = _get_available_focused_child_body_names()
	if child_body_names.is_empty():
		focused_child_body_name = &""
		return
	if child_body_names.find(focused_child_body_name) >= 0:
		return
	focused_child_body_name = _get_default_focused_child_body_name()

func _get_selected_focused_child_body_name() -> StringName:
	_ensure_focused_child_body_valid()
	return focused_child_body_name

func _set_focused_child_body_name(body_name: StringName) -> bool:
	var child_body_names: Array[StringName] = _get_available_focused_child_body_names()
	if child_body_names.find(body_name) < 0:
		return false
	focused_child_body_name = body_name
	return true

func _advance_focused_child_selection(direction: int = 1) -> bool:
	var child_body_names: Array[StringName] = _get_available_focused_child_body_names()
	if child_body_names.is_empty():
		focused_child_body_name = &""
		return false
	_ensure_focused_child_body_valid()
	var current_index: int = child_body_names.find(focused_child_body_name)
	if current_index < 0:
		focused_child_body_name = _get_default_focused_child_body_name()
		return true
	var target_index: int = current_index + direction
	if target_index < 0 or target_index >= child_body_names.size():
		return false
	focused_child_body_name = child_body_names[target_index]
	return true

func _get_equator_reference_cycle_list() -> Array[StringName]:
	var body_names: Array[StringName] = [PRIMARY_BODY_NAME]
	for child_body_name in _get_available_focused_child_body_names():
		body_names.append(child_body_name)
	return body_names

func _ensure_equator_reference_body_valid() -> void:
	var valid_bodies: Array[StringName] = _get_equator_reference_cycle_list()
	if valid_bodies.find(equator_reference_body_name) >= 0:
		return
	equator_reference_body_name = PRIMARY_BODY_NAME

func _get_equator_reference_body_name() -> StringName:
	_ensure_equator_reference_body_valid()
	return equator_reference_body_name

func _advance_equator_reference_selection(direction: int = 1) -> bool:
	var valid_bodies: Array[StringName] = _get_equator_reference_cycle_list()
	if valid_bodies.is_empty():
		equator_reference_body_name = PRIMARY_BODY_NAME
		return false
	_ensure_equator_reference_body_valid()
	var current_index: int = valid_bodies.find(equator_reference_body_name)
	if current_index < 0:
		equator_reference_body_name = PRIMARY_BODY_NAME
		return true
	var next_index: int = current_index + direction
	if next_index < 0 or next_index >= valid_bodies.size():
		return false
	equator_reference_body_name = valid_bodies[next_index]
	return true

func _get_equator_reference_context() -> Dictionary:
	return body_focus_projection.get_equator_reference_context(_get_equator_reference_body_name())

func _get_equator_reference_signature(reference_context: Dictionary) -> String:
	var reference_body_name: StringName = reference_context.get("name", PRIMARY_BODY_NAME)
	var frame_body_name: StringName = reference_context.get("frame_reference_body_name", reference_body_name)
	return "%s|%s" % [String(reference_body_name), String(frame_body_name)]

func _get_equator_stable_phase_basis(reference_context: Dictionary) -> Dictionary:
	var signature: String = _get_equator_reference_signature(reference_context)
	if signature != equator_last_stable_basis_signature:
		return {}
	return equator_last_stable_line_basis

func _store_equator_stable_phase_basis(reference_context: Dictionary, line_basis: Dictionary) -> void:
	if not bool(line_basis.get("node_defined", false)):
		return
	equator_last_stable_basis_signature = _get_equator_reference_signature(reference_context)
	equator_last_stable_line_basis = {
		"valid": true,
		"node_hat": line_basis.get("node_hat", Vector3.ZERO),
		"q_hat": line_basis.get("q_hat", Vector3.ZERO),
	}

func _get_body_display_text(body_name: StringName) -> String:
	if body_name == &"":
		return "CHILD"
	var session: Node = get_node_or_null("/root/GameSession")
	if session != null and session.has_method("get_body_display_name"):
		return String(session.get_body_display_name(body_name)).to_upper()
	return String(body_name).replace("_", " ").to_upper()

func _build_child_orbit_track_data(child_body_name: StringName) -> Dictionary:
	var orbit: Dictionary = SimulationState.get_body_orbit_params(child_body_name)
	var angular_speed: float = absf(float(orbit.get("angular_speed", 0.0)))
	if orbit.is_empty() or angular_speed <= 0.000001:
		var child_rel_planet: Vector3 = SimulationState.get_body_position(child_body_name) - SimulationState.get_body_position(PRIMARY_BODY_NAME)
		var child_orbit_radius: float = child_rel_planet.length()
		if child_orbit_radius > 0.0001:
			var relative_points: Array[Vector3] = []
			var sample_count_fallback: int = 128
			for sample_index in range(sample_count_fallback + 1):
				var angle: float = TAU * (float(sample_index) / float(sample_count_fallback))
				var point := Vector3(cos(angle) * child_orbit_radius, 0.0, sin(angle) * child_orbit_radius)
				relative_points.append(point)
			return {
				"relative_points": relative_points,
				"periapsis_index": -1,
				"apoapsis_index": -1,
			}
		return {
			"relative_points": [],
			"periapsis_index": -1,
			"apoapsis_index": -1,
		}

	var orbit_period: float = TAU / angular_speed
	var parent_body_name: StringName = SimulationState.get_body_parent(child_body_name)
	var relative_points: Array[Vector3] = []
	var sample_count: int = 160
	for sample_index in range(sample_count + 1):
		var t: float = orbit_period * (float(sample_index) / float(sample_count))
		var child_state: Dictionary = SimulationState.get_body_state_at_time(child_body_name, t)
		var parent_state: Dictionary = SimulationState.get_body_state_at_time(parent_body_name, t)
		var child_position: Vector3 = child_state.get("pos", Vector3.ZERO)
		var parent_position: Vector3 = parent_state.get("pos", Vector3.ZERO)
		var child_relative_position: Vector3 = child_position - parent_position
		relative_points.append(child_relative_position)

	var periapsis_index: int = -1
	var apoapsis_index: int = -1
	var min_radius: float = INF
	var max_radius: float = -INF
	var mean_radius: float = 0.0
	for index in range(relative_points.size()):
		var radius: float = relative_points[index].length()
		mean_radius += radius
		if radius < min_radius:
			min_radius = radius
			periapsis_index = index
		if radius > max_radius:
			max_radius = radius
			apoapsis_index = index
	if not relative_points.is_empty():
		mean_radius /= float(relative_points.size())
	if mean_radius > 0.0001 and (max_radius - min_radius) / mean_radius < 0.01:
		# Keep stable AP/PE reference markers even for near-circular child orbits.
		periapsis_index = 0
		apoapsis_index = int(floor(float(sample_count) * 0.5))

	return {
		"relative_points": relative_points,
		"periapsis_index": periapsis_index,
		"apoapsis_index": apoapsis_index,
	}

func _sample_child_orbit_track_data(projection_center: Vector2, child_body_name: StringName) -> Dictionary:
	if not cached_child_orbit_track_data.has(child_body_name):
		cached_child_orbit_track_data[child_body_name] = _build_child_orbit_track_data(child_body_name)

	if (
		cached_child_orbit_projected_center != projection_center
		or cached_child_orbit_projected_view_offset != current_view_offset
		or absf(cached_child_orbit_projected_pixels_per_unit - pixels_per_unit) > 0.000001
	):
		cached_child_orbit_projected_points.clear()
		cached_child_orbit_projected_center = projection_center
		cached_child_orbit_projected_view_offset = current_view_offset
		cached_child_orbit_projected_pixels_per_unit = pixels_per_unit

	var track_data: Dictionary = cached_child_orbit_track_data.get(child_body_name, {})
	var relative_points: Array[Vector3] = _get_typed_vector3_array(track_data.get("relative_points", []))
	if not cached_child_orbit_projected_points.has(child_body_name):
		var projected_points := PackedVector2Array()
		for relative_point in relative_points:
			projected_points.append(_to_screen(relative_point, projection_center))
		cached_child_orbit_projected_points[child_body_name] = projected_points

	return {
		"projected_points": cached_child_orbit_projected_points.get(child_body_name, PackedVector2Array()),
		"relative_points": relative_points,
		"periapsis_index": int(track_data.get("periapsis_index", -1)),
		"apoapsis_index": int(track_data.get("apoapsis_index", -1)),
	}

func _draw_child_orbit_track(track_data: Dictionary, orbit_color: Color) -> void:
	var orbit_points: PackedVector2Array = track_data.get("projected_points", PackedVector2Array())
	if orbit_points.size() > 1:
		draw_polyline(orbit_points, orbit_color, 1.0)

func _draw_selected_child_plan_markers(
	track_data: Dictionary,
	planet_screen: Vector2,
	planet_radius_px: float
) -> void:
	var orbit_points: PackedVector2Array = track_data.get("projected_points", PackedVector2Array())
	var relative_points: Array[Vector3] = _get_typed_vector3_array(track_data.get("relative_points", []))
	if orbit_points.size() <= 1 or relative_points.is_empty():
		return

	var periapsis_index: int = int(track_data.get("periapsis_index", -1))
	var apoapsis_index: int = int(track_data.get("apoapsis_index", -1))

	if periapsis_index >= 0 and periapsis_index < orbit_points.size() and periapsis_index < relative_points.size():
		var pe_screen: Vector2 = orbit_points[periapsis_index]
		var pe_point: Vector3 = relative_points[periapsis_index]
		var pe_hidden: bool = Vector2(pe_point.x, pe_point.z).length() < SimulationState.planet_radius and pe_point.y < 0.0
		if pe_hidden:
			var pe_dir: Vector2 = pe_screen - planet_screen
			if pe_dir.length_squared() <= 0.0001:
				pe_dir = Vector2.RIGHT
			else:
				pe_dir = pe_dir.normalized()
			pe_screen = planet_screen + pe_dir * (planet_radius_px + 8.0)
		var pe_color: Color = Color(0.82, 0.95, 0.45, 0.85)
		_draw_marker_square(pe_screen, 5.0, pe_color)
		_draw_marker_label(pe_screen, "PE", pe_color, planet_screen, -1.0, false)

	if apoapsis_index >= 0 and apoapsis_index < orbit_points.size() and apoapsis_index < relative_points.size():
		var ap_screen: Vector2 = orbit_points[apoapsis_index]
		var ap_point: Vector3 = relative_points[apoapsis_index]
		var ap_hidden: bool = Vector2(ap_point.x, ap_point.z).length() < SimulationState.planet_radius and ap_point.y < 0.0
		if ap_hidden:
			var ap_dir: Vector2 = ap_screen - planet_screen
			if ap_dir.length_squared() <= 0.0001:
				ap_dir = Vector2.LEFT
			else:
				ap_dir = ap_dir.normalized()
			ap_screen = planet_screen + ap_dir * (planet_radius_px + 8.0)
		var ap_color: Color = Color(0.45, 0.75, 0.95, 0.85)
		_draw_marker_square(ap_screen, 5.0, ap_color)
		_draw_marker_label(ap_screen, "AP", ap_color, planet_screen, -1.0, false)

func _get_child_ghost_color(index: int, count: int, is_selected: bool) -> Color:
	var use_count: int = max(count, 1)
	var hue: float = fposmod((float(index) / float(use_count)) + 0.58, 1.0)
	var saturation: float = 0.78 if is_selected else 0.62
	var value: float = 1.0 if is_selected else 0.9
	return Color.from_hsv(hue, saturation, value, 1.0)

func _update_center_transition(delta: float) -> void:
	var target_offset: Vector2 = _get_target_view_offset()

	if display_mode == DisplayMode.INCLINATION:
		current_view_offset = target_offset
		transition_active = false
		return

	if not transition_active:
		current_view_offset = target_offset
		return

	transition_elapsed += delta

	if center_transition_duration <= 0.0:
		current_view_offset = target_offset
		transition_active = false
		return

	var t: float = clampf(transition_elapsed / center_transition_duration, 0.0, 1.0)

	var eased: float
	if t < 0.5:
		eased = 4.0 * t * t * t
	else:
		eased = 1.0 - pow(-2.0 * t + 2.0, 3.0) / 2.0

	current_view_offset = transition_start_offset.lerp(target_offset, eased)

	if t >= 1.0:
		current_view_offset = target_offset
		transition_active = false

func request_refresh() -> bool:
	if refresh_flow_state == RefreshFlowState.CALCULATING or refresh_flow_state == RefreshFlowState.DRAWING:
		return false

	refresh_flow_state = RefreshFlowState.CALCULATING
	refresh_calc_phase = RefreshCalcPhase.PREPARE
	refresh_calc_elapsed = 0.0
	refresh_calc_ship_pos = SimulationState.ship_pos
	refresh_calc_ship_vel = SimulationState.ship_vel
	refresh_calc_sim_time = SimulationState.sim_time
	_clear_refresh_calculation_buffers()
	_start_calculating_sound()
	_mark_visual_dirty()
	return true

func cycle_display_mode() -> void:
	if display_mode == DisplayMode.TRAJECTORY:
		if refresh_flow_state == RefreshFlowState.DRAWING or is_revealing:
			_complete_plan_reveal_immediately()
		display_mode = DisplayMode.INCLINATION
	else:
		display_mode = DisplayMode.TRAJECTORY

	transition_active = false
	current_view_offset = _get_target_view_offset()
	_invalidate_geometry_cache()
	_mark_visual_dirty()

func _complete_plan_reveal_immediately() -> void:
	if not is_revealing and refresh_flow_state != RefreshFlowState.DRAWING:
		return
	is_revealing = false
	reveal_elapsed = reveal_duration
	if refresh_flow_state == RefreshFlowState.DRAWING:
		refresh_flow_state = RefreshFlowState.IDLE
	_stop_reveal_sweep_sound()
	_mark_visual_dirty()

func cycle_center_mode() -> void:
	var child_body_names: Array[StringName] = _get_available_focused_child_body_names()
	if display_mode == DisplayMode.INCLINATION:
		if child_body_names.is_empty():
			equator_reference_body_name = PRIMARY_BODY_NAME
		else:
			if not _advance_equator_reference_selection(1):
				equator_reference_body_name = PRIMARY_BODY_NAME
		transition_active = false
		current_view_offset = _get_target_view_offset()
		_invalidate_geometry_cache()
		_mark_visual_dirty()
		return

	match center_mode:
		CenterMode.PLANET:
			if child_body_names.is_empty():
				_begin_center_transition(CenterMode.SHIP)
			else:
				_select_default_focused_child_body()
				_begin_center_transition(CenterMode.MOON)
		CenterMode.MOON:
			if _advance_focused_child_selection(1):
				_begin_center_transition(CenterMode.MOON)
			else:
				_begin_center_transition(CenterMode.SHIP)
		CenterMode.SHIP:
			_begin_center_transition(CenterMode.PLANET)

func _compute_solution() -> void:
	solution = _compute_solution_sync()
	timewarp_solution_start_sim_time = SimulationState.sim_time

func _compute_solution_sync() -> TrajectorySolution:
	var broad_prediction_info: Dictionary = prediction_horizon.get_broad_prediction_info(
		predictor,
		orbit_solver,
		prediction_step_seconds,
		_get_prediction_horizon_settings()
	)
	var steps_to_use: int = broad_prediction_info.get("steps", prediction_steps)
	var prediction: Dictionary = broad_prediction_info.get("quick_prediction", {})
	if prediction.is_empty():
		prediction = predictor.compute(
			SimulationState.ship_pos,
			SimulationState.ship_vel,
			SimulationState.sim_time,
			prediction_step_seconds,
			steps_to_use,
			extrema_window_radius,
			radial_extrema_tolerance
		)

	var orbit: Dictionary = orbit_solver.solve_planet_orbit(
		SimulationState.ship_pos,
		SimulationState.ship_vel,
		SimulationState.planet_pos,
		SimulationState.planet_mu,
		SimulationState.planet_radius
	)
	return _build_solution_from_prediction(prediction, steps_to_use, orbit)

func _build_solution_from_prediction(prediction: Dictionary, steps_to_use: int, orbit: Dictionary) -> TrajectorySolution:
	var built_solution := TrajectorySolution.new()

	built_solution.ship_points = prediction["ship_points"]
	built_solution.ship_velocities = prediction["ship_velocities"]
	built_solution.closest_approach_distance = prediction["closest_approach_distance"]
	built_solution.closest_approach_time = prediction["closest_approach_time"]
	var body_predictions: Dictionary = prediction.get("body_predictions", {})
	if not body_predictions.is_empty():
		for body_key in body_predictions.keys():
			var body_name: StringName = StringName(String(body_key))
			var body_prediction: Dictionary = body_predictions.get(body_key, {})
			built_solution.set_body_parent_name(body_name, body_prediction.get("parent_body_name", &""))
			built_solution.set_body_relative_points(body_name, _get_typed_vector3_array(body_prediction.get("relative_points", [])))
			var body_closest_approach: Dictionary = body_prediction.get("closest_approach", {})
			built_solution.set_body_closest_approach(
				body_name,
				body_closest_approach.get("distance", -1.0),
				body_closest_approach.get("time", -1.0),
				body_closest_approach.get("relative_speed", -1.0),
				body_closest_approach.get("index", -1)
			)
			var body_dominance_mask: Array[bool] = []
			for value in body_prediction.get("dominance_mask", []):
				body_dominance_mask.append(bool(value))
			built_solution.set_body_dominance_mask(body_name, body_dominance_mask)
	elif prediction.has("moon_points"):
		var moon_prediction: Dictionary = _get_body_prediction(prediction, MOON_BODY_NAME)
		var moon_relative_points: Array[Vector3] = _get_body_prediction_relative_points(prediction, MOON_BODY_NAME)
		if moon_relative_points.is_empty():
			moon_relative_points = prediction["moon_points"]
		var moon_closest_approach: Dictionary = _get_body_prediction_closest_approach(prediction, MOON_BODY_NAME)
		if moon_closest_approach.is_empty():
			moon_closest_approach = {
				"distance": prediction["moon_closest_approach_distance"],
				"time": prediction["moon_closest_approach_time"],
				"relative_speed": prediction["moon_relative_speed_at_closest_approach"],
				"index": prediction["moon_closest_approach_index"],
			}
		var moon_dominance_mask: Array[bool] = _get_body_prediction_dominance_mask(prediction, MOON_BODY_NAME)
		if moon_dominance_mask.is_empty():
			moon_dominance_mask = prediction["moon_dominance"]
		built_solution.set_body_parent_name(MOON_BODY_NAME, PRIMARY_BODY_NAME)
		if not moon_prediction.is_empty():
			built_solution.set_body_parent_name(MOON_BODY_NAME, moon_prediction.get("parent_body_name", PRIMARY_BODY_NAME))
		built_solution.set_body_relative_points(MOON_BODY_NAME, moon_relative_points)
		built_solution.set_body_closest_approach(
			MOON_BODY_NAME,
			moon_closest_approach.get("distance", -1.0),
			moon_closest_approach.get("time", -1.0),
			moon_closest_approach.get("relative_speed", -1.0),
			moon_closest_approach.get("index", -1)
		)
		built_solution.set_body_dominance_mask(MOON_BODY_NAME, moon_dominance_mask)

	built_solution.predicted_periapsis_distance = prediction["predicted_periapsis_distance"]
	built_solution.predicted_apoapsis_distance = prediction["predicted_apoapsis_distance"]
	built_solution.predicted_periapsis_time = prediction["predicted_periapsis_time"]
	built_solution.predicted_apoapsis_time = prediction["predicted_apoapsis_time"]
	built_solution.predicted_periapsis_index = prediction["predicted_periapsis_index"]
	built_solution.predicted_apoapsis_index = prediction["predicted_apoapsis_index"]

	built_solution.orbit_classification = orbit["orbit_classification"]
	built_solution.periapsis_distance = orbit["periapsis_distance"]
	built_solution.apoapsis_distance = orbit["apoapsis_distance"]
	built_solution.eccentricity_value = orbit["eccentricity_value"]
	built_solution.semi_major_axis_value = orbit["semi_major_axis_value"]
	built_solution.orbital_period_value = orbit["orbital_period_value"]
	built_solution.is_bound_orbit = orbit["is_bound_orbit"]
	built_solution.specific_energy = orbit["specific_energy"]

	built_solution.prediction_steps_used = steps_to_use
	built_solution.prediction_duration_used = float(steps_to_use) * prediction_step_seconds
	var ship_reference_body_name: StringName = SimulationState.get_ship_reference_body_name()
	var trim_reference_body_name: StringName = ship_reference_body_name if ship_reference_body_name != PRIMARY_BODY_NAME else &""
	var display_steps_to_use: int = prediction_horizon.get_continuity_trimmed_steps(
		prediction,
		trim_reference_body_name,
		steps_to_use,
		_get_prediction_horizon_settings()
	)
	built_solution.display_steps_used = clampi(display_steps_to_use, 2, built_solution.ship_points.size())
	built_solution.display_duration_used = float(built_solution.display_steps_used) * prediction_step_seconds
	return built_solution

func _update_refresh_calculation() -> void:
	match refresh_calc_phase:
		RefreshCalcPhase.PREPARE:
			var horizon_settings: Dictionary = _get_prediction_horizon_settings()
			if prediction_horizon.has_method("get_refresh_prediction_steps"):
				refresh_calc_prediction_steps_to_use = prediction_horizon.get_refresh_prediction_steps(
					orbit_solver,
					prediction_step_seconds,
					horizon_settings
				)
			else:
				refresh_calc_prediction_steps_to_use = prediction_steps
			refresh_calc_prediction_steps_to_use = clampi(
				refresh_calc_prediction_steps_to_use,
				2,
				max(max_prediction_steps, 2)
			)
			refresh_calc_prediction_job = predictor.create_prediction_job(
				refresh_calc_ship_pos,
				refresh_calc_ship_vel,
				refresh_calc_sim_time,
				prediction_step_seconds,
				refresh_calc_prediction_steps_to_use,
				extrema_window_radius,
				radial_extrema_tolerance
			)
			refresh_calc_phase = RefreshCalcPhase.PREDICT
		RefreshCalcPhase.PREDICT:
			if refresh_calc_prediction_job.is_empty():
				refresh_calc_phase = RefreshCalcPhase.PREPARE
				return
			var target_duration: float = clampf(refresh_target_duration_seconds, 3.0, 5.0)
			var total_steps: int = max(predictor.get_prediction_job_total_steps(refresh_calc_prediction_job), 1)
			var completed_steps: int = predictor.get_prediction_job_completed_steps(refresh_calc_prediction_job)
			var expected_ratio: float = clampf(refresh_calc_elapsed / maxf(target_duration, 0.01), 0.0, 1.0)
			var expected_completed_steps: int = int(floor(float(total_steps) * expected_ratio))
			if expected_ratio >= 1.0:
				expected_completed_steps = total_steps
			var steps_to_run: int = expected_completed_steps - completed_steps
			if steps_to_run > 0:
				var per_frame_cap: int = max(1, refresh_max_prediction_steps_per_frame)
				predictor.step_prediction_job(refresh_calc_prediction_job, min(steps_to_run, per_frame_cap))
			if predictor.is_prediction_job_complete(refresh_calc_prediction_job):
				if refresh_calc_elapsed < target_duration:
					return
				refresh_calc_phase = RefreshCalcPhase.ANALYZE
		RefreshCalcPhase.ANALYZE:
			refresh_calc_prediction = predictor.build_prediction_from_job(refresh_calc_prediction_job)
			refresh_calc_phase = RefreshCalcPhase.BUILD_SOLUTION
		RefreshCalcPhase.BUILD_SOLUTION:
			refresh_calc_orbit = orbit_solver.solve_planet_orbit(
				refresh_calc_ship_pos,
				refresh_calc_ship_vel,
				SimulationState.planet_pos,
				SimulationState.planet_mu,
				SimulationState.planet_radius
			)
			refresh_calc_pending_solution = _build_solution_from_prediction(
				refresh_calc_prediction,
				refresh_calc_prediction_steps_to_use,
				refresh_calc_orbit
			)
			refresh_calc_phase = RefreshCalcPhase.BUILD_CACHE
		RefreshCalcPhase.BUILD_CACHE:
			if refresh_calc_pending_solution == null:
				refresh_calc_phase = RefreshCalcPhase.READY
				return
			var focused_child_body: StringName = _get_selected_focused_child_body_name()
			var in_child_dominance: bool = _is_currently_in_focused_child_dominance_for_solution(refresh_calc_pending_solution, focused_child_body)
			refresh_calc_prebuilt_cache = trajectory_projection_cache.build_cache(
				refresh_calc_pending_solution,
				center_mode,
				focused_child_body,
				in_child_dominance,
				local_orbit_markers,
				extrema_window_radius,
				closure_distance_ratio_tolerance,
				closure_scan_chunk_steps,
				closure_min_threshold_step_multiplier
			)
			refresh_calc_phase = RefreshCalcPhase.READY
		RefreshCalcPhase.READY:
			_finalize_refresh_calculation()

func _finalize_refresh_calculation() -> void:
	if refresh_calc_pending_solution != null:
		solution = refresh_calc_pending_solution
		timewarp_solution_start_sim_time = refresh_calc_sim_time
	SimulationState.clear_trajectory_prediction_stale()
	if refresh_calc_prebuilt_cache.is_empty():
		_invalidate_geometry_cache()
	else:
		geometry_cache_dirty = false
		_apply_geometry_cache_dictionary(refresh_calc_prebuilt_cache, _is_currently_in_focused_child_dominance())
		_invalidate_projected_render_cache()
	impact_sound_pending = false
	impact_sound_played = false
	timewarp_selector.handle_prediction_refresh(_get_timewarp_point_limit(), is_timewarp_prediction_stale())
	ghost_elapsed = 0.0
	_clear_refresh_calculation_buffers()
	_stop_calculating_sound()
	if display_mode == DisplayMode.TRAJECTORY:
		reveal_elapsed = 0.0
		is_revealing = true
		refresh_flow_state = RefreshFlowState.DRAWING
		_start_reveal_sweep_sound()
	else:
		reveal_elapsed = reveal_duration
		is_revealing = false
		refresh_flow_state = RefreshFlowState.IDLE
		_stop_reveal_sweep_sound()
	_mark_visual_dirty()

func _clear_refresh_calculation_buffers() -> void:
	refresh_calc_phase = RefreshCalcPhase.PREPARE
	refresh_calc_elapsed = 0.0
	refresh_calc_prediction_steps_to_use = 0
	refresh_calc_prediction_job.clear()
	refresh_calc_prediction.clear()
	refresh_calc_orbit.clear()
	refresh_calc_prebuilt_cache.clear()
	refresh_calc_pending_solution = null

func _is_currently_in_focused_child_dominance_for_solution(
	target_solution: TrajectorySolution,
	focused_child_body_name: StringName
) -> bool:
	if target_solution == null or focused_child_body_name == &"":
		return false
	var dominance_mask: Array[bool] = target_solution.get_body_dominance_mask(focused_child_body_name)
	if dominance_mask.is_empty():
		return false
	return bool(dominance_mask[0])

func _get_prediction_horizon_settings() -> Dictionary:
	return {
		"pixels_per_unit": pixels_per_unit,
		"min_pixels_per_unit": min_pixels_per_unit,
		"max_pixels_per_unit": max_pixels_per_unit,
		"prediction_steps": prediction_steps,
		"min_prediction_steps": min_prediction_steps,
		"max_prediction_steps": max_prediction_steps,
		"period_prediction_margin": period_prediction_margin,
		"focused_child_body_name": _get_selected_focused_child_body_name(),
		"focused_child_encounter_extra_characteristic_times": focused_child_encounter_extra_characteristic_times,
		"focused_child_strong_ca_body_radii": focused_child_strong_ca_body_radii,
		"focused_child_local_period_margin": focused_child_local_period_margin,
		"focused_child_local_escape_characteristic_times": focused_child_local_escape_characteristic_times,
		"focused_child_local_min_prediction_steps": focused_child_local_min_prediction_steps,
		"focused_child_local_max_prediction_steps": focused_child_local_max_prediction_steps,
		"moon_encounter_extra_time": moon_encounter_extra_time,
		"strong_moon_ca_multiplier": strong_moon_ca_multiplier,
		"moon_local_period_prediction_margin": moon_local_period_prediction_margin,
		"moon_local_escape_prediction_seconds": moon_local_escape_prediction_seconds,
		"moon_local_min_prediction_steps": moon_local_min_prediction_steps,
		"moon_local_max_prediction_steps": moon_local_max_prediction_steps,
		"closure_distance_ratio_tolerance": closure_distance_ratio_tolerance,
		"closure_scan_chunk_steps": closure_scan_chunk_steps,
		"closure_min_threshold_step_multiplier": closure_min_threshold_step_multiplier,
		"extrema_window_radius": extrema_window_radius,
		"radial_extrema_tolerance": radial_extrema_tolerance,
	}

func zoom_in() -> void:
	var current_max_zoom: float = moon_max_pixels_per_unit if center_mode == CenterMode.MOON else max_pixels_per_unit
	pixels_per_unit = min(current_max_zoom, pixels_per_unit + zoom_step)
	_invalidate_geometry_cache()

func zoom_out() -> void:
	pixels_per_unit = max(min_pixels_per_unit, pixels_per_unit - zoom_step)
	_invalidate_geometry_cache()

func set_center_planet() -> void:
	_begin_center_transition(CenterMode.PLANET)

func set_center_moon() -> void:
	_set_focused_child_body_name(MOON_BODY_NAME)
	_begin_center_transition(CenterMode.MOON)

func set_center_child_body(body_name: StringName) -> void:
	if not _set_focused_child_body_name(body_name):
		return
	_begin_center_transition(CenterMode.MOON)

func set_center_child_body_by_name(body_name: String) -> void:
	set_center_child_body(StringName(body_name))

func get_available_child_view_targets() -> PackedStringArray:
	var result := PackedStringArray()
	for body_name in _get_available_focused_child_body_names():
		result.append(String(body_name))
	return result

func get_selected_child_view_target() -> String:
	return String(_get_selected_focused_child_body_name())

func set_center_ship() -> void:
	_begin_center_transition(CenterMode.SHIP)

func _begin_center_transition(new_mode: CenterMode) -> void:
	if display_mode == DisplayMode.INCLINATION and new_mode == CenterMode.SHIP:
		new_mode = CenterMode.PLANET
	if new_mode != CenterMode.MOON and pixels_per_unit > max_pixels_per_unit:
		pixels_per_unit = max_pixels_per_unit

	transition_start_offset = current_view_offset
	transition_elapsed = 0.0
	transition_active = true
	center_mode = new_mode
	_invalidate_geometry_cache()

func get_center_mode_text() -> String:
	match center_mode:
		CenterMode.PLANET:
			return _get_body_display_text(PRIMARY_BODY_NAME)
		CenterMode.MOON:
			return _get_body_display_text(_get_selected_focused_child_body_name())
		CenterMode.SHIP:
			return "SHIP"
	return "UNKNOWN"

func get_primary_body_label_text() -> String:
	return _get_body_display_text(PRIMARY_BODY_NAME)

func get_display_mode_text() -> String:
	match display_mode:
		DisplayMode.TRAJECTORY:
			return "TRAJECTORY"
		DisplayMode.INCLINATION:
			return "PLANE"
	return "UNKNOWN"

func get_status_text() -> String:
	if display_mode == DisplayMode.INCLINATION:
		return "LIVE"

	if refresh_flow_state == RefreshFlowState.CALCULATING:
		return "CALCULATING"
	if refresh_flow_state == RefreshFlowState.DRAWING or is_revealing:
		return "DRAWING"
	if solution.ship_points.is_empty():
		return "NO SOLUTION"
	return "READY"

func get_reference_body_text() -> String:
	if display_mode == DisplayMode.INCLINATION:
		var body_name: StringName = _get_equator_reference_body_name()
		return _get_body_display_text(body_name)
	return _get_body_display_text(PRIMARY_BODY_NAME)

func get_closest_approach_distance() -> float:
	return solution.closest_approach_distance

func get_closest_approach_time() -> float:
	return solution.closest_approach_time

func get_classification() -> String:
	return solution.orbit_classification

func get_periapsis() -> float:
	if solution.predicted_periapsis_distance > 0.0:
		return solution.predicted_periapsis_distance
	return solution.periapsis_distance

func get_apoapsis() -> float:
	if solution.predicted_apoapsis_distance > 0.0:
		return solution.predicted_apoapsis_distance
	return solution.apoapsis_distance

func get_eccentricity() -> float:
	return solution.eccentricity_value

func get_semi_major_axis() -> float:
	return solution.semi_major_axis_value

func get_orbital_period() -> float:
	return solution.orbital_period_value

func get_zoom_value() -> float:
	return pixels_per_unit

func get_reveal_duration() -> float:
	return reveal_duration

func get_prediction_steps_used() -> int:
	return solution.prediction_steps_used

func get_prediction_duration_used() -> float:
	return solution.prediction_duration_used

func get_ship_altitude() -> float:
	var reference_body_name: StringName = SimulationState.get_ship_reference_body_name()
	var r: float = (SimulationState.ship_pos - SimulationState.get_body_position(reference_body_name)).length()
	return r - SimulationState.get_body_radius(reference_body_name)

func get_ship_speed() -> float:
	return SimulationState.ship_vel.length()

func get_ship_radial_velocity() -> float:
	var rel: Vector3 = SimulationState.ship_pos - SimulationState.get_ship_reference_body_pos()
	var rhat: Vector3 = rel.normalized()
	return (SimulationState.ship_vel - SimulationState.get_ship_reference_body_vel()).dot(rhat)

func get_ship_tangential_velocity() -> float:
	var rel: Vector3 = SimulationState.ship_pos - SimulationState.get_ship_reference_body_pos()
	var rhat: Vector3 = rel.normalized()
	var rel_vel: Vector3 = SimulationState.ship_vel - SimulationState.get_ship_reference_body_vel()
	var radial_v: float = rel_vel.dot(rhat)
	var radial_vec: Vector3 = rhat * radial_v
	return (rel_vel - radial_vec).length()

func get_focused_child_label_text() -> String:
	return _get_body_display_text(_get_selected_focused_child_body_name())

func get_focused_child_closest_approach_distance() -> float:
	return _get_focused_child_closest_approach().get("distance", -1.0)

func get_focused_child_closest_approach_time() -> float:
	return _get_focused_child_closest_approach().get("time", -1.0)

func get_focused_child_relative_speed_at_closest_approach() -> float:
	return _get_focused_child_closest_approach().get("relative_speed", -1.0)

func get_moon_closest_approach_distance() -> float:
	return _get_moon_closest_approach().get("distance", -1.0)

func get_moon_closest_approach_time() -> float:
	return _get_moon_closest_approach().get("time", -1.0)

func get_moon_relative_speed_at_closest_approach() -> float:
	return _get_moon_closest_approach().get("relative_speed", -1.0)

func _get_moon_relative_points() -> Array[Vector3]:
	return solution.get_body_relative_points(MOON_BODY_NAME)

func _get_moon_dominance_mask() -> Array[bool]:
	return solution.get_body_dominance_mask(MOON_BODY_NAME)

func _get_moon_closest_approach() -> Dictionary:
	return solution.get_body_closest_approach(MOON_BODY_NAME)

func _get_active_body_encounter() -> Dictionary:
	if not cached_focused_child_encounter.is_empty():
		return cached_focused_child_encounter
	if not cached_active_body_encounter.is_empty():
		return cached_active_body_encounter
	var body_name: StringName = _get_selected_focused_child_body_name()
	if body_name != &"":
		return solution.get_body_encounter(body_name)
	return {}

func _get_focused_child_body_name() -> StringName:
	return cached_focused_child_body_name if cached_focused_child_body_name != &"" else _get_selected_focused_child_body_name()

func _get_focused_child_draw_points() -> Array[Vector3]:
	return cached_focused_child_draw_points

func _get_focused_child_relative_points() -> Array[Vector3]:
	var encounter: Dictionary = _get_active_body_encounter()
	if not encounter.is_empty():
		return _get_typed_vector3_array(encounter.get("relative_points", []))
	var body_name: StringName = _get_focused_child_body_name()
	if body_name != &"":
		return solution.get_body_relative_points(body_name)
	return []

func _get_focused_child_closest_approach() -> Dictionary:
	var encounter: Dictionary = _get_active_body_encounter()
	if not encounter.is_empty():
		return encounter.get("closest_approach", {})
	var body_name: StringName = _get_focused_child_body_name()
	if body_name != &"":
		return solution.get_body_closest_approach(body_name)
	return {}

func _is_currently_in_focused_child_dominance() -> bool:
	var body_name: StringName = _get_focused_child_body_name()
	if body_name == &"":
		return false
	if SimulationState.has_method("is_ship_in_body_dominance"):
		return SimulationState.is_ship_in_body_dominance(body_name)
	return false

func _get_active_local_segment() -> Dictionary:
	var encounter_segment: Dictionary = _get_active_body_encounter().get("local_segment", {})
	if not encounter_segment.is_empty():
		return encounter_segment
	return {
		"entry_index": cached_focused_child_entry_index,
		"exit_index": cached_focused_child_exit_index,
		"points": cached_focused_child_local_points.duplicate(),
		"source_indices": cached_focused_child_local_source_indices.duplicate(),
	}

func _get_active_markers() -> Dictionary:
	var encounter_markers: Dictionary = _get_active_body_encounter().get("markers", {})
	if not encounter_markers.is_empty():
		return encounter_markers
	return {
		"local_ca_index": cached_focused_child_local_ca_index,
		"local_pe_index": cached_focused_child_local_pe_index,
		"local_ap_index": cached_focused_child_local_ap_index,
		"show_local_ca_marker": cached_show_focused_child_local_ca_marker,
		"show_escape_marker": cached_show_focused_child_escape_marker,
		"escape_marker_local_index": cached_focused_child_escape_marker_local_index,
	}

func _get_active_impact() -> Dictionary:
	var encounter_impact: Dictionary = _get_active_body_encounter().get("impact", {})
	if not encounter_impact.is_empty():
		return encounter_impact
	var impact_source_index: int = -1
	if cached_focused_child_local_impact_found and cached_focused_child_local_impact_index >= 0 and cached_focused_child_local_impact_index < cached_focused_child_local_source_indices.size():
		impact_source_index = cached_focused_child_local_source_indices[cached_focused_child_local_impact_index]
	return {
		"found": cached_focused_child_local_impact_found,
		"index": cached_focused_child_local_impact_index,
		"source_index": impact_source_index,
	}

func _get_active_local_points() -> Array[Vector3]:
	return _get_typed_vector3_array(_get_active_local_segment().get("points", []))

func _get_active_local_source_indices() -> Array[int]:
	return _get_typed_int_array(_get_active_local_segment().get("source_indices", []))

func _get_typed_vector3_array(values) -> Array[Vector3]:
	var typed_values: Array[Vector3] = []
	for value in values:
		typed_values.append(value)
	return typed_values

func _get_typed_int_array(values) -> Array[int]:
	var typed_values: Array[int] = []
	for value in values:
		typed_values.append(int(value))
	return typed_values

func set_focus_active(active: bool) -> void:
	focus_active = active
	timewarp_selector.ensure_valid(_get_timewarp_point_limit(), is_timewarp_prediction_stale())
	_mark_visual_dirty()

func toggle_marker_distance_labels() -> bool:
	show_marker_distance_labels = not show_marker_distance_labels
	_mark_visual_dirty()
	return show_marker_distance_labels

func _supports_timewarp_display_mode() -> bool:
	return display_mode == DisplayMode.TRAJECTORY or display_mode == DisplayMode.INCLINATION

func is_timewarp_enabled() -> bool:
	return timewarp_selector.enabled

func is_timewarp_prediction_stale() -> bool:
	return SimulationState.is_trajectory_prediction_stale()

func toggle_timewarp_enabled() -> bool:
	if is_timewarp_prediction_stale():
		timewarp_selector.reset()
		_mark_visual_dirty()
		return false

	var enabled_now: bool = timewarp_selector.set_enabled(
		not timewarp_selector.enabled,
		_get_timewarp_point_limit(),
		is_timewarp_prediction_stale()
	)
	if not enabled_now:
		if SimulationState.is_targeted_warp_active():
			SimulationState.cancel_targeted_warp()
	_mark_visual_dirty()
	return enabled_now

func is_timewarp_selection_available() -> bool:
	var presentation_locked: bool = (
		refresh_flow_state == RefreshFlowState.CALCULATING
		or (
			display_mode == DisplayMode.TRAJECTORY
			and (is_revealing or refresh_flow_state == RefreshFlowState.DRAWING)
		)
	)
	return timewarp_selector.is_selection_available(
		is_timewarp_prediction_stale(),
		focus_active,
		_supports_timewarp_display_mode(),
		not solution.ship_points.is_empty(),
		presentation_locked
	)

func move_warp_selection(direction: int, coarse: bool = false) -> bool:
	if not is_timewarp_selection_available():
		return false
	if SimulationState.is_targeted_warp_active():
		return false

	var step: int = _get_selection_step_size(coarse)
	var point_limit: int = _get_timewarp_point_limit()
	_clamp_timewarp_selector_indices(point_limit)
	timewarp_selector.ensure_valid(point_limit, is_timewarp_prediction_stale())
	var previous_target_index: int = timewarp_selector.get_target_index(point_limit)
	var previous_selection_index: int = timewarp_selector.selection_index
	if not timewarp_selector.move_selection(direction, point_limit, step):
		return false
	if debug_timewarp_selector:
		var next_target_index: int = timewarp_selector.get_target_index(point_limit)
		var selected_time_seconds: float = timewarp_selector.get_selected_time_seconds(prediction_step_seconds)
		var dir_sign: int = sign(direction)
		var monotonic_ok: bool = true
		if previous_target_index >= 0 and next_target_index >= 0:
			if dir_sign > 0:
				monotonic_ok = next_target_index >= previous_target_index
			elif dir_sign < 0:
				monotonic_ok = next_target_index <= previous_target_index
		print(
			"[TW DEBUG] mode=%s ref=%d sel:%d->%d tgt:%d->%d time=T+%.0fs monotonic=%s"
			% [
				"EQUATOR" if display_mode == DisplayMode.INCLINATION else "PLAN",
				timewarp_selector.reference_index,
				previous_selection_index,
				timewarp_selector.selection_index,
				previous_target_index,
				next_target_index,
				selected_time_seconds,
				"yes" if monotonic_ok else "NO"
			]
		)
	_mark_visual_dirty()
	return true

func confirm_warp_selection() -> bool:
	if not is_timewarp_selection_available():
		return false
	if SimulationState.is_targeted_warp_active():
		return false

	var point_limit: int = _get_timewarp_point_limit()
	_clamp_timewarp_selector_indices(point_limit)
	timewarp_selector.ensure_valid(point_limit, is_timewarp_prediction_stale())
	if timewarp_selector.selection_index <= 0:
		return false

	var target_index: int = timewarp_selector.get_target_index(point_limit)
	if target_index < 0:
		return false
	var target_sim_time: float = SimulationState.sim_time + timewarp_selector.get_selected_time_seconds(prediction_step_seconds)
	var target_ship_pos: Vector3 = SimulationState.planet_pos + solution.ship_points[target_index]
	var target_ship_vel: Vector3 = SimulationState.ship_vel
	if target_index < solution.ship_velocities.size():
		target_ship_vel = solution.ship_velocities[target_index]

	var path_positions: Array[Vector3] = [SimulationState.ship_pos]
	var path_velocities: Array[Vector3] = [SimulationState.ship_vel]
	for i in range(timewarp_selector.reference_index + 1, target_index + 1):
		path_positions.append(SimulationState.planet_pos + solution.ship_points[i])
		if i < solution.ship_velocities.size():
			path_velocities.append(solution.ship_velocities[i])
		else:
			path_velocities.append(target_ship_vel)

	return SimulationState.begin_targeted_warp_to_path(
		target_sim_time,
		path_positions,
		path_velocities,
		prediction_step_seconds
	)

func cancel_warp_selection() -> void:
	if not timewarp_selector.enabled:
		_mark_visual_dirty()
		return
	if SimulationState.is_targeted_warp_active():
		SimulationState.cancel_targeted_warp()
	else:
		var point_limit: int = _get_timewarp_point_limit()
		_clamp_timewarp_selector_indices(point_limit)
		timewarp_selector.cancel_selection(point_limit, is_timewarp_prediction_stale())
	_mark_visual_dirty()

func _get_selection_step_size(coarse: bool) -> int:
	return timewarp_selector.get_selection_step_size(
		solution.display_duration_used,
		prediction_step_seconds,
		timewarp_fine_step_fraction_of_horizon,
		timewarp_coarse_step_fraction_of_horizon,
		coarse
	)

func _get_selection_step_seconds(coarse: bool) -> int:
	return timewarp_selector.get_selection_step_seconds(
		solution.display_duration_used,
		prediction_step_seconds,
		timewarp_fine_step_fraction_of_horizon,
		timewarp_coarse_step_fraction_of_horizon,
		coarse
	)

func _draw_selection_box(pos: Vector2, color: Color) -> void:
	var size: float = 11.0
	draw_rect(Rect2(pos - Vector2(size, size), Vector2(size * 2.0, size * 2.0)), Color(color.r, color.g, color.b, 0.18), true)
	draw_rect(Rect2(pos - Vector2(size, size), Vector2(size * 2.0, size * 2.0)), color, false, 2.0)
	draw_circle(pos, 3.0, color)

func _get_selected_screen_point(center: Vector2, focused_child_rel_planet: Vector3) -> Dictionary:
	var point_limit: int = _get_timewarp_point_limit()
	if timewarp_selector.selection_index < 0 or solution.ship_points.is_empty() or point_limit <= 0:
		return {
			"valid": false
		}

	if timewarp_selector.selection_index == 0:
		return {
			"valid": true,
			"screen": _to_screen(SimulationState.ship_pos - SimulationState.planet_pos, center)
		}

	var target_index: int = timewarp_selector.get_target_index(point_limit)
	if target_index < 0 or target_index >= solution.ship_points.size() or target_index >= point_limit:
		return {
			"valid": false
		}

	var selected_world: Vector3 = solution.ship_points[target_index]
	var selected_screen: Vector2 = _to_screen(selected_world, center)

	if center_mode == CenterMode.MOON:
		var moon_view_screen: Dictionary = _get_moon_view_screen_point_for_source_index(target_index, center, focused_child_rel_planet)
		if moon_view_screen.get("valid", false):
			selected_screen = moon_view_screen.get("screen", selected_screen)

	return {
		"valid": true,
		"screen": selected_screen
	}

func _get_moon_view_screen_point_for_source_index(source_index: int, center: Vector2, focused_child_rel_planet: Vector3) -> Dictionary:
	if source_index < 0:
		return {"valid": false}

	var active_local_points: Array[Vector3] = _get_active_local_points()
	var active_local_source_indices: Array[int] = _get_active_local_source_indices()
	for i in range(active_local_source_indices.size()):
		if active_local_source_indices[i] != source_index:
			continue
		if i >= active_local_points.size():
			break
		return {
			"valid": true,
			"screen": _to_screen(active_local_points[i] + focused_child_rel_planet, center)
		}

	return {"valid": false}

func _draw_timewarp_legend(rect_size: Vector2, color: Color) -> void:
	if not _supports_timewarp_display_mode() or not focus_active:
		return

	var font := ThemeDB.fallback_font
	var font_size := 18
	var line_spacing: float = 24.0

	var lines: Array[String] = []
	var prediction_stale: bool = is_timewarp_prediction_stale()
	if prediction_stale:
		lines.append("TIME WARP: OFF: NEEDS REFRESH")
	elif timewarp_selector.enabled:
		lines.append("TIME WARP: ON : 'T'")
		var default_step_seconds: int = _get_selection_step_seconds(false)
		var coarse_step_seconds: int = _get_selection_step_seconds(true)
		var current_step_seconds: int = coarse_step_seconds if Input.is_key_pressed(KEY_SHIFT) else default_step_seconds
		var selected_time: float = timewarp_selector.get_selected_time_seconds(prediction_step_seconds)

		lines.append("TARGET: T+%.0f s" % selected_time)
		lines.append("AHEAD %d s : ']'" % current_step_seconds)
		lines.append("BACK  %d s : '['" % current_step_seconds)
		lines.append("SHIFT: STEP x5")
		lines.append("ENTER: WARP   ESC: STOP")
	else:
		lines.append("TIME WARP: OFF: 'T'")

	var max_width: float = 0.0
	for line in lines:
		var line_size: Vector2 = font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		max_width = max(max_width, line_size.x)

	var left_x: float
	var line_y: float
	if display_mode == DisplayMode.INCLINATION:
		left_x = 60.0
		line_y = 58.0
	else:
		left_x = rect_size.x - max_width - 60.0
		line_y = rect_size.y - 28.0 - line_spacing * float(lines.size() - 1)

	for i in range(lines.size()):
		draw_string(
			font,
			Vector2(left_x, line_y + line_spacing * float(i)),
			lines[i],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			color
		)

func _draw_marker_distance_toggle_hint(rect_size: Vector2, color: Color) -> void:
	if not focus_active:
		return
	var font := ThemeDB.fallback_font
	var font_size: int = 16
	var state_text: String = "ON" if show_marker_distance_labels else "OFF"
	var hint_text: String = "DIST LABELS: %s : 'R'" % state_text
	var text_size: Vector2 = font.get_string_size(hint_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	draw_string(
		font,
		Vector2(rect_size.x - text_size.x - 60.0, 46.0),
		hint_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		Color(color.r, color.g, color.b, 0.85)
	)

func _get_calculating_dot_count() -> int:
	var dot_interval: float = maxf(calculating_dot_interval_seconds, 0.01)
	var max_dots: int = max(0, calculating_max_dots)
	var cycle_size: int = max_dots + 1
	return int(floor(refresh_calc_elapsed / dot_interval)) % cycle_size

func _get_calculating_status_text() -> String:
	var dot_count: int = _get_calculating_dot_count()
	return "CALCULATING" + ".".repeat(dot_count)

func _draw_calculating_status_box(rect_size: Vector2) -> void:
	if not show_calculating_status_box:
		return
	if refresh_flow_state != RefreshFlowState.CALCULATING:
		return

	var font := ThemeDB.fallback_font
	var status_font_size: int = 28
	var box_size: Vector2 = Vector2(
		maxf(calculating_status_box_size.x, 160.0),
		maxf(calculating_status_box_size.y, 64.0)
	)
	var box_rect := Rect2(
		Vector2(
			rect_size.x * 0.5 - box_size.x * 0.5 + calculating_status_box_offset.x,
			rect_size.y * 0.5 - box_size.y * 0.5 + calculating_status_box_offset.y
		),
		box_size
	)
	draw_rect(box_rect, Color(0.03, 0.08, 0.03, 0.9), true)
	draw_rect(box_rect, Color(0.22, 0.7, 0.25, 0.95), false, 2.0)

	var status_text: String = _get_calculating_status_text()
	var status_size: Vector2 = font.get_string_size(status_text, HORIZONTAL_ALIGNMENT_LEFT, -1, status_font_size)
	var status_pos: Vector2 = Vector2(
		box_rect.position.x + (box_rect.size.x - status_size.x) * 0.5,
		box_rect.position.y + box_rect.size.y * 0.5 + status_size.y * 0.35
	)
	draw_string(
		font,
		status_pos,
		status_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		status_font_size,
		Color(0.45, 1.0, 0.45)
	)

func _resolve_refresh_sound_player() -> void:
	if refresh_sound_player != null:
		return
	if not refresh_audio_player_path.is_empty():
		refresh_sound_player = get_node_or_null(refresh_audio_player_path)
		if refresh_sound_player != null:
			return
	refresh_sound_player = get_tree().root.find_child("BeepPlayer3D", true, false)

func _resolve_reveal_sweep_player() -> void:
	if reveal_sweep_player != null:
		return
	if reveal_sweep_player_path.is_empty():
		return
	reveal_sweep_player = get_node_or_null(reveal_sweep_player_path)

func _set_audio_pitch_scale(player: Node, pitch_scale_value: float) -> void:
	if player is AudioStreamPlayer3D:
		(player as AudioStreamPlayer3D).pitch_scale = pitch_scale_value
	elif player is AudioStreamPlayer:
		(player as AudioStreamPlayer).pitch_scale = pitch_scale_value

func _resolve_impact_sound_player() -> void:
	if impact_sound_player != null:
		return
	if impact_sound_player_path.is_empty():
		return
	impact_sound_player = get_node_or_null(impact_sound_player_path)

func _play_timewarp_sound() -> void:
	_resolve_refresh_sound_player()
	if refresh_sound_player == null:
		return
	if not refresh_sound_player.has_method("start_refresh"):
		return

	var sound_duration: float = SimulationState.get_targeted_warp_real_duration_seconds()
	refresh_sound_player.start_refresh(max(sound_duration, 0.1))
	_set_audio_pitch_scale(refresh_sound_player, 1.0)

func _play_refresh_sound(duration: float) -> void:
	_resolve_refresh_sound_player()
	if refresh_sound_player == null:
		return
	if not refresh_sound_player.has_method("start_refresh"):
		return

	refresh_sound_player.start_refresh(max(duration, 0.1))

func _stop_timewarp_sound() -> void:
	_resolve_refresh_sound_player()
	if refresh_sound_player == null:
		return
	if refresh_sound_player.has_method("stop_refresh"):
		refresh_sound_player.stop_refresh()
	_set_audio_pitch_scale(refresh_sound_player, 1.0)

func _start_calculating_sound() -> void:
	_resolve_refresh_sound_player()
	if refresh_sound_player == null:
		return
	if refresh_sound_player.has_method("start_refresh"):
		refresh_sound_player.start_refresh(60.0)
	_set_audio_pitch_scale(refresh_sound_player, 1.0)

func _stop_calculating_sound() -> void:
	_resolve_refresh_sound_player()
	if refresh_sound_player == null:
		return
	if refresh_sound_player.has_method("stop_refresh"):
		refresh_sound_player.stop_refresh()
	_set_audio_pitch_scale(refresh_sound_player, 1.0)

func _start_reveal_sweep_sound() -> void:
	_resolve_reveal_sweep_player()
	if reveal_sweep_player != null:
		if reveal_sweep_player.has_method("play"):
			reveal_sweep_player.play()
		_set_audio_pitch_scale(reveal_sweep_player, reveal_sweep_low_pitch_scale)
		return

	_play_refresh_sound(max(reveal_duration, 0.1))
	_set_audio_pitch_scale(refresh_sound_player, reveal_sweep_low_pitch_scale)

func _update_reveal_sweep_pitch() -> void:
	if not is_revealing:
		return
	var reveal_ratio: float = 1.0 if reveal_duration <= 0.0 else clampf(reveal_elapsed / reveal_duration, 0.0, 1.0)
	var sweep_pitch: float = lerpf(reveal_sweep_low_pitch_scale, reveal_sweep_high_pitch_scale, reveal_ratio)
	if reveal_sweep_player != null:
		_set_audio_pitch_scale(reveal_sweep_player, sweep_pitch)
	else:
		_set_audio_pitch_scale(refresh_sound_player, sweep_pitch)

func _stop_reveal_sweep_sound() -> void:
	_resolve_reveal_sweep_player()
	if reveal_sweep_player != null:
		if reveal_sweep_player.has_method("stop"):
			reveal_sweep_player.stop()
		_set_audio_pitch_scale(reveal_sweep_player, 1.0)
		return

	_resolve_refresh_sound_player()
	if refresh_sound_player == null:
		return
	if refresh_sound_player.has_method("stop_refresh"):
		refresh_sound_player.stop_refresh()
	_set_audio_pitch_scale(refresh_sound_player, 1.0)

func _play_impact_sound() -> void:
	_resolve_impact_sound_player()
	if impact_sound_player == null:
		return
	if impact_sound_player.has_method("play"):
		impact_sound_player.play()

func _draw_dashed_polyline(points: Array[Vector2], color: Color, width: float, dash_length: int, gap_length: int, max_count: int) -> void:
	if points.size() < 2:
		return

	var visible_count: int = min(max_count, points.size())

	var i: int = 0
	while i < visible_count - 1:
		var dash_end: int = min(i + dash_length, visible_count - 1)

		for j in range(i, dash_end):
			draw_line(points[j], points[j + 1], color, width)

		i += dash_length + gap_length

func _get_target_view_offset() -> Vector2:
	return body_focus_projection.get_target_view_offset(center_mode, SimulationState.ship_pos, _get_selected_focused_child_body_name())

func _project_planet_frame(world_planet_frame: Vector3) -> Vector2:
	return body_focus_projection.project_planet_frame(world_planet_frame)

func _to_screen(world_planet_frame: Vector3, center: Vector2) -> Vector2:
	return body_focus_projection.to_screen(world_planet_frame, center, current_view_offset, pixels_per_unit)

func _draw_marker_square(pos: Vector2, marker_size: float, color: Color) -> void:
	var half := marker_size * 0.5
	draw_rect(
		Rect2(pos - Vector2(half, half), Vector2(marker_size, marker_size)),
		color,
		false,
		1.25
	)

func _draw_impact_marker(pos: Vector2, marker_size: float, color: Color) -> void:
	var half: float = marker_size * 0.5
	draw_line(pos + Vector2(-half, -half), pos + Vector2(half, half), Color(color.r, color.g, color.b, 0.2), 4.5)
	draw_line(pos + Vector2(-half, half), pos + Vector2(half, -half), Color(color.r, color.g, color.b, 0.2), 4.5)
	draw_line(pos + Vector2(-half, -half), pos + Vector2(half, half), color, 2.2)
	draw_line(pos + Vector2(-half, half), pos + Vector2(half, -half), color, 2.2)

func _draw_projected_arrow(start: Vector2, tip: Vector2, color: Color, width: float, head_length: float = 10.0, head_width: float = 8.0) -> void:
	var delta: Vector2 = tip - start
	var screen_length: float = delta.length()
	if screen_length <= 0.0001:
		return

	var direction: Vector2 = delta / screen_length
	var usable_head_length: float = min(head_length, screen_length * 0.45)
	if usable_head_length < 3.0:
		draw_line(start, tip, color, width)
		return

	var usable_head_width: float = min(head_width, usable_head_length * 0.9)
	var perpendicular: Vector2 = Vector2(-direction.y, direction.x)
	var head_base: Vector2 = tip - direction * usable_head_length
	draw_line(start, head_base, color, width)

	var arrow_points := PackedVector2Array([
		tip,
		head_base + perpendicular * (usable_head_width * 0.5),
		head_base - perpendicular * (usable_head_width * 0.5)
	])
	draw_colored_polygon(arrow_points, color)

func _find_first_nonzero_projected_delta(points: Array[Vector3], start_index: int) -> Vector2:
	var start_i: int = clampi(start_index, 0, max(points.size() - 1, 0))
	for i in range(start_i + 1, points.size()):
		var delta: Vector2 = _project_planet_frame(points[i] - points[start_i])
		if delta.length_squared() > 0.0001:
			return delta
	return Vector2.ZERO

func _find_arrow_start_index(points: PackedVector2Array, min_distance: float) -> int:
	if points.size() < 2:
		return -1

	var tip: Vector2 = points[points.size() - 1]
	for i in range(points.size() - 2, -1, -1):
		if tip.distance_to(points[i]) >= min_distance:
			return i
	return max(points.size() - 2, 0)

func _draw_marker_label(
	pos: Vector2,
	text_value: String,
	color: Color,
	reference_screen: Vector2,
	surface_distance: float = -1.0,
	allow_distance: bool = true
) -> void:
	var font := ThemeDB.fallback_font
	var font_size := 12

	var radial := pos - reference_screen
	if radial.length_squared() < 0.0001:
		radial = Vector2.RIGHT
	else:
		radial = radial.normalized()

	var distance_enabled: bool = allow_distance and show_marker_distance_labels
	var label_distance: float = 16.0
	if text_value == "CA" or text_value == "PE":
		label_distance = 24.0

	var distance_text: String = _format_marker_distance_nu(surface_distance) if distance_enabled else ""
	var draw_distance_on_second_line: bool = (text_value == "AP" or text_value == "PE" or text_value == "CA") and not distance_text.is_empty()

	if draw_distance_on_second_line:
		var title_size: Vector2 = font.get_string_size(text_value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var distance_size: Vector2 = font.get_string_size(distance_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var radial_distance_boost: float = clampf((distance_size.x - 48.0) * 0.22, 0.0, 18.0)
		var chosen_center: Vector2 = pos + radial * (label_distance + radial_distance_boost)
		var title_pos := chosen_center + Vector2(-title_size.x * 0.5, title_size.y * 0.35)
		var distance_pos := chosen_center + Vector2(-distance_size.x * 0.5, title_size.y + 4.0 + distance_size.y * 0.35)
		var distance_box_pad_x: float = 3.0
		var distance_box_pad_y: float = 2.0
		var distance_box_nudge_y: float = 4.0
		var distance_box_rect := Rect2(
			Vector2(
				distance_pos.x - distance_box_pad_x,
				distance_pos.y - distance_size.y - distance_box_pad_y + distance_box_nudge_y
			),
			Vector2(
				distance_size.x + distance_box_pad_x * 2.0,
				distance_size.y + distance_box_pad_y * 2.0
			)
		)
		draw_string(
			font,
			title_pos,
			text_value,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			color
		)
		draw_rect(distance_box_rect, Color(0.0, 0.0, 0.0, 0.62), true)
		draw_string(
			font,
			distance_pos,
			distance_text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			color
		)
		return

	var draw_text: String = text_value
	if not distance_text.is_empty():
		draw_text = "%s | %s" % [text_value, distance_text]

	var text_size: Vector2 = font.get_string_size(draw_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var chosen_center: Vector2 = pos + radial * label_distance
	if not distance_text.is_empty():
		var radial_distance_boost: float = clampf((text_size.x - 48.0) * 0.26, 0.0, 22.0)
		chosen_center = pos + radial * (label_distance + radial_distance_boost)
	var draw_pos := chosen_center + Vector2(-text_size.x * 0.5, text_size.y * 0.35)

	draw_string(
		font,
		draw_pos,
		draw_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		color
	)

func _handle_impact_reached_on_draw() -> void:
	if impact_sound_played:
		return
	_stop_reveal_sweep_sound()
	_stop_timewarp_sound()
	_play_impact_sound()
	impact_sound_played = true
	impact_sound_pending = false
	if is_revealing:
		is_revealing = false
		if refresh_flow_state == RefreshFlowState.DRAWING:
			refresh_flow_state = RefreshFlowState.IDLE
	_mark_visual_dirty()

func _compute_surface_distance_from_center_distance(center_distance: float, body_radius: float) -> float:
	if center_distance < 0.0 or body_radius < 0.0:
		return -1.0
	return maxf(center_distance - body_radius, 0.0)

func _compute_surface_distance_from_relative_point(relative_point: Vector3, body_radius: float) -> float:
	if body_radius < 0.0:
		return -1.0
	return _compute_surface_distance_from_center_distance(relative_point.length(), body_radius)

func _format_marker_distance_nu(surface_distance: float) -> String:
	if surface_distance < 0.0:
		return ""
	if surface_distance >= 1000.0:
		return "%.1f NU" % surface_distance
	if surface_distance >= 100.0:
		return "%.2f NU" % surface_distance
	return "%.3f NU" % surface_distance

func _invalidate_geometry_cache() -> void:
	geometry_cache_dirty = true
	_invalidate_child_orbit_track_cache()
	_invalidate_projected_render_cache()
	_mark_visual_dirty()

func _collapse_timewarp_if_stale() -> void:
	if not timewarp_selector.collapse_if_stale(is_timewarp_prediction_stale()):
		return
	if SimulationState.is_targeted_warp_active():
		SimulationState.cancel_targeted_warp()
	_mark_visual_dirty()

func _update_timewarp_selector() -> void:
	_update_timewarp_selector_reference_index_timebase()
	var point_limit: int = _get_timewarp_point_limit()
	_clamp_timewarp_selector_indices(point_limit)
	timewarp_selector.ensure_valid(point_limit, is_timewarp_prediction_stale())

func _update_timewarp_selector_reference_index_timebase() -> void:
	var point_count: int = solution.ship_points.size()
	if not timewarp_selector.enabled or is_timewarp_prediction_stale() or point_count <= 1:
		timewarp_selector.reference_index = 0
		return
	if SimulationState.is_targeted_warp_active():
		return

	var step_seconds: float = maxf(prediction_step_seconds, 0.0001)
	var elapsed_since_solution_start: float = maxf(SimulationState.sim_time - timewarp_solution_start_sim_time, 0.0)
	var timebase_index: int = int(floor(elapsed_since_solution_start / step_seconds))
	timewarp_selector.reference_index = clampi(timebase_index, 0, point_count - 1)

func _get_timewarp_point_limit() -> int:
	var horizon_point_limit: int = solution.ship_points.size()
	if solution.display_steps_used > 1:
		horizon_point_limit = min(horizon_point_limit, solution.display_steps_used)
	if solution.prediction_steps_used > 1:
		horizon_point_limit = min(horizon_point_limit, solution.prediction_steps_used)

	var point_limit: int = horizon_point_limit
	if point_limit <= 0:
		return 0

	var active_local_segment: Dictionary = _get_active_local_segment()
	var active_impact: Dictionary = _get_active_impact()
	var active_exit_index: int = active_local_segment.get("exit_index", -1)

	if center_mode == CenterMode.MOON and active_exit_index >= 0:
		point_limit = min(point_limit, active_exit_index + 1)
	elif center_mode == CenterMode.MOON and cached_focused_child_exit_index >= 0:
		point_limit = min(point_limit, cached_focused_child_exit_index + 1)

	if cached_ship_impact_found and cached_ship_impact_index >= 0:
		point_limit = min(point_limit, cached_ship_impact_index + 1)

	var active_impact_source_index: int = active_impact.get("source_index", -1)
	if active_impact.get("found", false) and active_impact_source_index >= 0:
		point_limit = min(point_limit, active_impact_source_index + 1)
	elif cached_focused_child_local_impact_found and cached_focused_child_local_impact_index >= 0 and cached_focused_child_local_impact_index < cached_focused_child_local_source_indices.size():
		point_limit = min(point_limit, cached_focused_child_local_source_indices[cached_focused_child_local_impact_index] + 1)

	return max(point_limit, 1)

func _clamp_timewarp_selector_indices(point_limit: int) -> void:
	if point_limit > 0:
		timewarp_selector.reference_index = clampi(timewarp_selector.reference_index, 0, point_limit - 1)
	else:
		timewarp_selector.reference_index = 0

func _ensure_projected_render_cache(
	center: Vector2,
	visible_count: int,
	main_visible_count: int,
	active_local_points: Array[Vector3],
	active_local_source_indices: Array[int],
	live_moon_anchor: Vector3
) -> void:
	var focused_child_name: StringName = _get_selected_focused_child_body_name()
	var needs_rebuild: bool = projected_render_dirty
	needs_rebuild = needs_rebuild or cached_projected_center != center
	needs_rebuild = needs_rebuild or cached_projected_view_offset != current_view_offset
	needs_rebuild = needs_rebuild or absf(cached_projected_pixels_per_unit - pixels_per_unit) > 0.000001
	needs_rebuild = needs_rebuild or cached_projected_visible_count != visible_count
	needs_rebuild = needs_rebuild or cached_projected_main_visible_count != main_visible_count
	needs_rebuild = needs_rebuild or cached_projected_center_mode != center_mode
	needs_rebuild = needs_rebuild or cached_projected_focused_child_body_name != focused_child_name
	needs_rebuild = needs_rebuild or cached_projected_local_anchor != live_moon_anchor

	if not needs_rebuild:
		debug_projection_cache_hits_since_log += 1
		return

	projected_render_dirty = false
	cached_projected_center = center
	cached_projected_view_offset = current_view_offset
	cached_projected_pixels_per_unit = pixels_per_unit
	cached_projected_visible_count = visible_count
	cached_projected_main_visible_count = main_visible_count
	cached_projected_center_mode = center_mode
	cached_projected_focused_child_body_name = focused_child_name
	cached_projected_local_anchor = live_moon_anchor
	cached_projected_ship_points = PackedVector2Array()
	cached_projected_ship_run_draws.clear()
	cached_projected_local_points = PackedVector2Array()
	cached_projected_local_run_draws.clear()
	cached_projected_child_ghosts.clear()

	var projected_points_built: int = 0

	var ship_render_path: Dictionary = _build_ship_render_path_for_visible_count(main_visible_count)
	var ship_render_points: Array[Vector3] = ship_render_path.get("points", [])
	var ship_render_runs: Array[Dictionary] = ship_render_path.get("runs", [])
	if ship_render_points.size() > 1:
		cached_projected_ship_points = _project_points_range(ship_render_points, 0, ship_render_points.size() - 1, center)
		projected_points_built += cached_projected_ship_points.size()
		cached_projected_ship_run_draws = _build_projected_run_cache(
			ship_render_points,
			ship_render_runs,
			center,
			ship_render_points.size(),
			Vector3.ZERO,
			false
		)
		for run in cached_projected_ship_run_draws:
			var projected: PackedVector2Array = run.get("points", PackedVector2Array())
			projected_points_built += projected.size()

	if center_mode == CenterMode.MOON:
		var visible_local_count: int = 0
		for source_index in active_local_source_indices:
			if source_index < visible_count:
				visible_local_count += 1
			else:
				break

		if visible_local_count > 1:
			cached_projected_local_points = _project_points_range(active_local_points, 0, visible_local_count - 1, center, live_moon_anchor)
			projected_points_built += cached_projected_local_points.size()
			var live_moon_world_points: Array[Vector3] = []
			for i in range(visible_local_count):
				live_moon_world_points.append(active_local_points[i] + live_moon_anchor)
			var live_moon_runs: Array[Dictionary] = _build_hidden_runs(live_moon_world_points)
			cached_projected_local_run_draws = _build_projected_run_cache(active_local_points, live_moon_runs, center, visible_local_count, live_moon_anchor)
			for run in cached_projected_local_run_draws:
				var projected: PackedVector2Array = run.get("points", PackedVector2Array())
				projected_points_built += projected.size()
	else:
		for child_body_name in _get_available_focused_child_body_names():
			var child_points: Array[Vector3] = solution.get_body_relative_points(child_body_name)
			if child_points.size() <= 1 or visible_count <= 1:
				continue
			var child_draw_points: PackedVector2Array = _project_points_range_decimated(
				child_points,
				0,
				min(visible_count - 1, child_points.size() - 1),
				center
			)
			if child_draw_points.size() > 1:
				cached_projected_child_ghosts[child_body_name] = child_draw_points
				projected_points_built += child_draw_points.size()

	debug_last_projected_points_built = projected_points_built
	debug_projection_cache_rebuilds_since_log += 1

func _rebuild_geometry_cache_if_needed() -> void:
	if not geometry_cache_dirty:
		return

	geometry_cache_dirty = false
	_invalidate_projected_render_cache()
	var currently_in_focused_child_dominance: bool = _is_currently_in_focused_child_dominance()

	var cache: Dictionary = trajectory_projection_cache.build_cache(
		solution,
		center_mode,
		_get_selected_focused_child_body_name(),
		currently_in_focused_child_dominance,
		local_orbit_markers,
		extrema_window_radius,
		closure_distance_ratio_tolerance,
		closure_scan_chunk_steps,
		closure_min_threshold_step_multiplier
	)
	_apply_geometry_cache_dictionary(cache, currently_in_focused_child_dominance)

func _apply_geometry_cache_dictionary(cache: Dictionary, default_dominance_state: bool) -> void:
	cached_ship_source_points.clear()
	cached_ship_display_points.clear()
	cached_ship_display_source_indices.clear()
	cached_ship_display_runs.clear()
	cached_ship_runs.clear()
	cached_main_visible_count = 0
	cached_ship_impact_found = false
	cached_ship_impact_index = -1
	cached_focused_child_body_name = &""
	cached_focused_child_draw_points.clear()
	cached_focused_child_local_points.clear()
	cached_focused_child_local_source_indices.clear()
	cached_focused_child_local_ca_index = -1
	cached_focused_child_local_pe_index = -1
	cached_focused_child_local_ap_index = -1
	cached_focused_child_local_impact_found = false
	cached_focused_child_local_impact_index = -1
	cached_show_focused_child_local_ca_marker = false
	cached_show_focused_child_escape_marker = false
	cached_focused_child_escape_marker_local_index = -1
	cached_focused_child_entry_index = -1
	cached_focused_child_exit_index = -1
	cached_currently_in_focused_child_dominance = default_dominance_state
	cached_focused_child_encounter = {}
	cached_active_body_encounter = {}

	var ship_source_points = cache.get("ship_source_points", [])
	var ship_runs = cache.get("ship_runs", [])
	var focused_child_draw_points = cache.get("focused_child_draw_points", [])
	var focused_child_local_points = cache.get("focused_child_local_points", [])
	var focused_child_local_source_indices = cache.get("focused_child_local_source_indices", [])

	for point in ship_source_points:
		cached_ship_source_points.append(point)
	for run in ship_runs:
		cached_ship_runs.append(run)
	cached_main_visible_count = cache.get("main_visible_count", 0)
	cached_ship_impact_found = cache.get("ship_impact_found", false)
	cached_ship_impact_index = cache.get("ship_impact_index", -1)
	cached_focused_child_body_name = cache.get("focused_child_body_name", &"")
	cached_focused_child_encounter = cache.get("focused_child_encounter", {}).duplicate(true)
	cached_active_body_encounter = cache.get("active_body_encounter", {}).duplicate(true)
	for point in focused_child_draw_points:
		cached_focused_child_draw_points.append(point)
	for point in focused_child_local_points:
		cached_focused_child_local_points.append(point)
	for source_index in focused_child_local_source_indices:
		cached_focused_child_local_source_indices.append(source_index)
	cached_focused_child_local_ca_index = cache.get("focused_child_local_ca_index", -1)
	cached_focused_child_local_pe_index = cache.get("focused_child_local_pe_index", -1)
	cached_focused_child_local_ap_index = cache.get("focused_child_local_ap_index", -1)
	cached_focused_child_local_impact_found = cache.get("focused_child_local_impact_found", false)
	cached_focused_child_local_impact_index = cache.get("focused_child_local_impact_index", -1)
	cached_show_focused_child_local_ca_marker = cache.get("show_focused_child_local_ca_marker", false)
	cached_show_focused_child_escape_marker = cache.get("show_focused_child_escape_marker", false)
	cached_focused_child_escape_marker_local_index = cache.get("focused_child_escape_marker_local_index", -1)
	cached_focused_child_entry_index = cache.get("focused_child_entry_index", -1)
	cached_focused_child_exit_index = cache.get("focused_child_exit_index", -1)
	cached_currently_in_focused_child_dominance = cache.get("currently_in_focused_child_dominance", cached_currently_in_focused_child_dominance)
	_rebuild_ship_display_cache()

	var has_impact_marker: bool = cached_ship_impact_found or cached_focused_child_local_impact_found
	if not impact_sound_played:
		impact_sound_pending = has_impact_marker
	_mark_visual_dirty()

func _update_impact_sound_trigger() -> void:
	if not impact_sound_pending or impact_sound_played:
		return
	if not _is_cached_impact_marker_visible():
		return
	_handle_impact_reached_on_draw()

func _is_cached_impact_marker_visible() -> bool:
	if display_mode != DisplayMode.TRAJECTORY:
		return false
	if solution.ship_points.size() <= 1:
		return false

	var ratio: float = clampf(reveal_elapsed / reveal_duration, 0.0, 1.0) if reveal_duration > 0.0 else 1.0
	var display_step_cap: int = min(solution.ship_points.size(), max(2, solution.display_steps_used))
	var visible_count: int = max(2, int(round((display_step_cap - 1) * ratio)) + 1)
	visible_count = min(visible_count, display_step_cap)

	if cached_ship_impact_found:
		var main_visible_count: int = visible_count
		var active_entry_index: int = _get_active_local_segment().get("entry_index", -1)
		if center_mode == CenterMode.MOON and active_entry_index >= 0 and active_entry_index < visible_count:
			main_visible_count = max(2, active_entry_index + 1)
		elif center_mode == CenterMode.MOON and cached_focused_child_entry_index >= 0 and cached_focused_child_entry_index < visible_count:
			main_visible_count = max(2, cached_focused_child_entry_index + 1)
		main_visible_count = min(main_visible_count, cached_ship_source_points.size())
		if cached_ship_impact_index >= 0 and cached_ship_impact_index < main_visible_count:
			return true

	var active_local_segment: Dictionary = _get_active_local_segment()
	var active_impact: Dictionary = _get_active_impact()
	if center_mode == CenterMode.MOON and active_impact.get("found", false) and active_local_segment.get("entry_index", -1) >= 0:
		var active_local_source_indices: Array[int] = _get_active_local_source_indices()
		var visible_local_count: int = 0
		for source_index in active_local_source_indices:
			if source_index < visible_count:
				visible_local_count += 1
			else:
				break
		if visible_local_count > 1 and active_impact.get("index", -1) >= 0 and active_impact.get("index", -1) < visible_local_count:
			return true

	if center_mode == CenterMode.MOON and cached_focused_child_local_impact_found and cached_focused_child_entry_index >= 0:
		var visible_local_count: int = 0
		for source_index in cached_focused_child_local_source_indices:
			if source_index < visible_count:
				visible_local_count += 1
			else:
				break
		if visible_local_count > 1 and cached_focused_child_local_impact_index >= 0 and cached_focused_child_local_impact_index < visible_local_count:
			return true

	return false

func _build_hidden_runs(points: Array[Vector3]) -> Array[Dictionary]:
	var runs: Array[Dictionary] = []
	if points.size() < 2:
		return runs

	var current_hidden: bool = false
	var current_start: int = 0
	var initialized: bool = false

	for i in range(points.size() - 1):
		var mid_3d: Vector3 = (points[i] + points[i + 1]) * 0.5
		var projected_r: float = Vector2(mid_3d.x, mid_3d.z).length()
		var hidden: bool = projected_r < SimulationState.planet_radius and mid_3d.y < 0.0

		if not initialized:
			current_hidden = hidden
			current_start = i
			initialized = true
			continue

		if hidden != current_hidden:
			runs.append({
				"start": current_start,
				"end": i,
				"hidden": current_hidden
			})
			current_start = i
			current_hidden = hidden

	if initialized:
		runs.append({
			"start": current_start,
			"end": points.size() - 1,
			"hidden": current_hidden
		})

	return runs

func _add_ship_display_anchor_index(anchor_flags: Dictionary, source_index: int, point_count: int) -> void:
	if source_index < 0 or source_index >= point_count:
		return
	anchor_flags[source_index] = true

func _add_ship_display_anchor_window(anchor_flags: Dictionary, center_index: int, radius: int, point_count: int) -> void:
	if center_index < 0 or center_index >= point_count:
		return
	var start_index: int = max(0, center_index - max(radius, 0))
	var end_index: int = min(point_count - 1, center_index + max(radius, 0))
	for i in range(start_index, end_index + 1):
		anchor_flags[i] = true

func _collect_ship_display_anchor_indices(point_count: int) -> Dictionary:
	var anchor_flags: Dictionary = {}
	if point_count <= 0:
		return anchor_flags

	_add_ship_display_anchor_index(anchor_flags, 0, point_count)
	_add_ship_display_anchor_index(anchor_flags, point_count - 1, point_count)
	_add_ship_display_anchor_index(anchor_flags, solution.predicted_periapsis_index, point_count)
	_add_ship_display_anchor_index(anchor_flags, solution.predicted_apoapsis_index, point_count)
	_add_ship_display_anchor_index(anchor_flags, cached_ship_impact_index, point_count)
	_add_ship_display_anchor_index(anchor_flags, cached_focused_child_entry_index, point_count)
	_add_ship_display_anchor_index(anchor_flags, cached_focused_child_exit_index, point_count)
	_add_ship_display_anchor_window(anchor_flags, solution.predicted_periapsis_index, 12, point_count)
	_add_ship_display_anchor_window(anchor_flags, solution.predicted_apoapsis_index, 12, point_count)
	_add_ship_display_anchor_window(anchor_flags, cached_ship_impact_index, 8, point_count)
	_add_ship_display_anchor_window(anchor_flags, cached_focused_child_entry_index, 8, point_count)
	_add_ship_display_anchor_window(anchor_flags, cached_focused_child_exit_index, 8, point_count)

	for body_key in solution.body_closest_approaches.keys():
		var body_ca: Dictionary = solution.body_closest_approaches.get(body_key, {})
		var body_ca_index: int = int(body_ca.get("index", -1))
		_add_ship_display_anchor_index(anchor_flags, body_ca_index, point_count)
		_add_ship_display_anchor_window(anchor_flags, body_ca_index, 6, point_count)

	for run in cached_ship_runs:
		_add_ship_display_anchor_index(anchor_flags, int(run.get("start", -1)), point_count)
		_add_ship_display_anchor_index(anchor_flags, int(run.get("end", -1)), point_count)

	if timewarp_selector.selection_index > 0:
		var point_limit: int = _get_timewarp_point_limit()
		if point_limit > 0:
			var target_index: int = timewarp_selector.get_target_index(point_limit)
			_add_ship_display_anchor_window(anchor_flags, target_index, 8, point_count)

	return anchor_flags

func _point_to_segment_distance_2d(point: Vector2, segment_start: Vector2, segment_end: Vector2) -> float:
	var segment_delta: Vector2 = segment_end - segment_start
	var segment_length_squared: float = segment_delta.length_squared()
	if segment_length_squared <= 0.00000001:
		return point.distance_to(segment_start)

	var t: float = clampf((point - segment_start).dot(segment_delta) / segment_length_squared, 0.0, 1.0)
	var closest_point: Vector2 = segment_start + segment_delta * t
	return point.distance_to(closest_point)

func _build_ship_display_segment_error(
	start_index: int,
	end_index: int,
	screen_points: Array[Vector2],
	importance_weights: Array[float]
) -> Dictionary:
	if end_index - start_index <= 1:
		return {"valid": false}

	var segment_start: Vector2 = screen_points[start_index]
	var segment_end: Vector2 = screen_points[end_index]
	var best_split_index: int = -1
	var best_weighted_error: float = 0.0

	for i in range(start_index + 1, end_index):
		var raw_error: float = _point_to_segment_distance_2d(screen_points[i], segment_start, segment_end)
		var weighted_error: float = raw_error * importance_weights[i]
		if weighted_error > best_weighted_error:
			best_weighted_error = weighted_error
			best_split_index = i

	return {
		"valid": best_split_index >= 0,
		"start": start_index,
		"end": end_index,
		"split_index": best_split_index,
		"weighted_error": best_weighted_error,
	}

func _build_ship_display_source_indices_adaptive(point_count: int, anchor_flags: Dictionary) -> Array[int]:
	var selected_flags: Dictionary = {}
	for source_index_raw in anchor_flags.keys():
		var source_index: int = int(source_index_raw)
		if source_index >= 0 and source_index < point_count:
			selected_flags[source_index] = true
	selected_flags[0] = true
	selected_flags[point_count - 1] = true

	var mandatory_indices: Array[int] = []
	for source_index_raw in selected_flags.keys():
		mandatory_indices.append(int(source_index_raw))
	mandatory_indices.sort()

	if mandatory_indices.size() <= 1:
		return [0]

	var target_max_points: int = max(MAX_DISPLAY_SHIP_POINTS, mandatory_indices.size())
	var screen_points: Array[Vector2] = []
	var importance_weights: Array[float] = []
	screen_points.resize(point_count)
	importance_weights.resize(point_count)
	var planet_radius: float = max(SimulationState.planet_radius, 0.001)

	for i in range(point_count):
		screen_points[i] = _project_planet_frame(cached_ship_source_points[i]) * pixels_per_unit

		var radial_distance: float = cached_ship_source_points[i].length()
		var radial_ratio: float = radial_distance / planet_radius
		var importance_weight: float = 1.0
		if i < 220:
			importance_weight += 0.9
		elif i < 640:
			importance_weight += 0.35
		if radial_ratio <= 2.5:
			importance_weight += 1.0
		elif radial_ratio <= 5.0:
			importance_weight += 0.55
		importance_weights[i] = importance_weight

	var segments: Array[Dictionary] = []
	for i in range(mandatory_indices.size() - 1):
		var segment: Dictionary = _build_ship_display_segment_error(
			mandatory_indices[i],
			mandatory_indices[i + 1],
			screen_points,
			importance_weights
		)
		if segment.get("valid", false):
			segments.append(segment)

	var error_threshold_px: float = 1.35
	var selected_count: int = mandatory_indices.size()
	while selected_count < target_max_points and not segments.is_empty():
		var best_segment_position: int = -1
		var best_segment_error: float = error_threshold_px
		for i in range(segments.size()):
			var weighted_error: float = float(segments[i].get("weighted_error", 0.0))
			if weighted_error > best_segment_error:
				best_segment_error = weighted_error
				best_segment_position = i

		if best_segment_position < 0:
			break

		var best_segment: Dictionary = segments[best_segment_position]
		segments.remove_at(best_segment_position)
		var split_index: int = int(best_segment.get("split_index", -1))
		var segment_start_index: int = int(best_segment.get("start", -1))
		var segment_end_index: int = int(best_segment.get("end", -1))
		if split_index <= segment_start_index or split_index >= segment_end_index:
			continue
		if selected_flags.has(split_index):
			continue

		selected_flags[split_index] = true
		selected_count += 1

		var left_segment: Dictionary = _build_ship_display_segment_error(
			segment_start_index,
			split_index,
			screen_points,
			importance_weights
		)
		if left_segment.get("valid", false):
			segments.append(left_segment)

		var right_segment: Dictionary = _build_ship_display_segment_error(
			split_index,
			segment_end_index,
			screen_points,
			importance_weights
		)
		if right_segment.get("valid", false):
			segments.append(right_segment)

	var selected_indices: Array[int] = []
	for source_index_raw in selected_flags.keys():
		selected_indices.append(int(source_index_raw))
	selected_indices.sort()
	return selected_indices

func _get_ship_run_properties_for_source_index(source_index: int, source_runs: Array[Dictionary]) -> Dictionary:
	for run in source_runs:
		var run_start: int = int(run.get("start", -1))
		var run_end: int = int(run.get("end", -1))
		if source_index >= run_start and source_index < run_end:
			return {
				"hidden": bool(run.get("hidden", false)),
				"color": run.get("color", Color(0.6, 1.0, 0.7)),
			}
	return {
		"hidden": false,
		"color": Color(0.6, 1.0, 0.7),
	}

func _build_ship_display_runs_from_source_runs() -> void:
	cached_ship_display_runs.clear()
	if cached_ship_display_source_indices.size() < 2:
		return
	if cached_ship_runs.is_empty():
		cached_ship_display_runs.append({
			"start": 0,
			"end": cached_ship_display_source_indices.size() - 1,
			"hidden": false,
			"color": Color(0.6, 1.0, 0.7),
		})
		return

	var current_start: int = 0
	var current_hidden: bool = false
	var current_color: Color = Color(0.6, 1.0, 0.7)
	var initialized: bool = false

	for display_index in range(cached_ship_display_source_indices.size() - 1):
		var source_index: int = cached_ship_display_source_indices[display_index]
		var run_props: Dictionary = _get_ship_run_properties_for_source_index(source_index, cached_ship_runs)
		var seg_hidden: bool = bool(run_props.get("hidden", false))
		var seg_color: Color = run_props.get("color", Color(0.6, 1.0, 0.7))

		if not initialized:
			current_start = display_index
			current_hidden = seg_hidden
			current_color = seg_color
			initialized = true
			continue

		if seg_hidden != current_hidden or seg_color != current_color:
			cached_ship_display_runs.append({
				"start": current_start,
				"end": display_index,
				"hidden": current_hidden,
				"color": current_color,
			})
			current_start = display_index
			current_hidden = seg_hidden
			current_color = seg_color

	if initialized:
		cached_ship_display_runs.append({
			"start": current_start,
			"end": cached_ship_display_source_indices.size() - 1,
			"hidden": current_hidden,
			"color": current_color,
		})

func _rebuild_ship_display_cache() -> void:
	cached_ship_display_points.clear()
	cached_ship_display_source_indices.clear()
	cached_ship_display_runs.clear()

	var point_count: int = cached_ship_source_points.size()
	if point_count <= 0:
		return

	var selected_source_indices: Array[int] = []
	if point_count <= MAX_DISPLAY_SHIP_POINTS:
		for source_index in range(point_count):
			selected_source_indices.append(source_index)
	else:
		var anchor_flags: Dictionary = _collect_ship_display_anchor_indices(point_count)
		var reveal_prefix_count: int = min(point_count, 128)
		for source_index in range(reveal_prefix_count):
			anchor_flags[source_index] = true
		selected_source_indices = _build_ship_display_source_indices_adaptive(point_count, anchor_flags)

	for source_index in selected_source_indices:
		cached_ship_display_source_indices.append(source_index)
		cached_ship_display_points.append(cached_ship_source_points[source_index])

	_build_ship_display_runs_from_source_runs()

func _build_ship_render_path_for_visible_count(main_visible_count: int) -> Dictionary:
	var render_points: Array[Vector3] = []
	var render_runs: Array[Dictionary] = []
	if main_visible_count <= 1 or cached_ship_source_points.size() <= 1:
		return {
			"points": render_points,
			"runs": render_runs,
		}

	var source_limit: int = min(main_visible_count, cached_ship_source_points.size())
	var selected_flags: Dictionary = {}
	for source_index in cached_ship_display_source_indices:
		if source_index < source_limit:
			selected_flags[source_index] = true
		else:
			break

	var frontier_start_index: int = max(0, source_limit - REVEAL_FRONTIER_DENSE_STEPS)
	for source_index in range(frontier_start_index, source_limit):
		selected_flags[source_index] = true
	selected_flags[0] = true
	selected_flags[source_limit - 1] = true

	var render_source_indices: Array[int] = []
	for source_index_raw in selected_flags.keys():
		var source_index: int = int(source_index_raw)
		if source_index >= 0 and source_index < source_limit:
			render_source_indices.append(source_index)
	render_source_indices.sort()

	for source_index in render_source_indices:
		render_points.append(cached_ship_source_points[source_index])

	if render_source_indices.size() >= 2:
		var current_start: int = 0
		var current_hidden: bool = false
		var current_color: Color = Color(0.6, 1.0, 0.7)
		var initialized: bool = false

		for render_index in range(render_source_indices.size() - 1):
			var source_index: int = render_source_indices[render_index]
			var run_props: Dictionary = _get_ship_run_properties_for_source_index(source_index, cached_ship_runs)
			var seg_hidden: bool = bool(run_props.get("hidden", false))
			var seg_color: Color = run_props.get("color", Color(0.6, 1.0, 0.7))

			if not initialized:
				current_start = render_index
				current_hidden = seg_hidden
				current_color = seg_color
				initialized = true
				continue

			if seg_hidden != current_hidden or seg_color != current_color:
				render_runs.append({
					"start": current_start,
					"end": render_index,
					"hidden": current_hidden,
					"color": current_color,
				})
				current_start = render_index
				current_hidden = seg_hidden
				current_color = seg_color

		if initialized:
			render_runs.append({
				"start": current_start,
				"end": render_source_indices.size() - 1,
				"hidden": current_hidden,
				"color": current_color,
			})

	return {
		"points": render_points,
		"runs": render_runs,
	}

func _project_points_range(points: Array[Vector3], start_index: int, end_index: int, center: Vector2, anchor: Vector3 = Vector3.ZERO) -> PackedVector2Array:
	var projected := PackedVector2Array()
	if points.is_empty():
		return projected

	var start_i: int = clampi(start_index, 0, points.size() - 1)
	var end_i: int = clampi(end_index, 0, points.size() - 1)
	if end_i < start_i:
		return projected

	for i in range(start_i, end_i + 1):
		projected.append(_to_screen(points[i] + anchor, center))

	return projected

func _project_points_range_decimated(points: Array[Vector3], start_index: int, end_index: int, center: Vector2, anchor: Vector3 = Vector3.ZERO) -> PackedVector2Array:
	var projected := PackedVector2Array()
	if points.is_empty():
		return projected

	var start_i: int = clampi(start_index, 0, points.size() - 1)
	var end_i: int = clampi(end_index, 0, points.size() - 1)
	if end_i < start_i:
		return projected

	var stride: int = _get_projected_draw_stride(points, start_i, end_i, anchor)
	for i in range(start_i, end_i + 1, stride):
		projected.append(_to_screen(points[i] + anchor, center))

	if projected.is_empty() or projected[projected.size() - 1] != _to_screen(points[end_i] + anchor, center):
		projected.append(_to_screen(points[end_i] + anchor, center))

	return projected

func _get_projected_draw_stride(points: Array[Vector3], start_index: int, end_index: int, anchor: Vector3 = Vector3.ZERO) -> int:
	if points.is_empty():
		return 1

	var start_i: int = clampi(start_index, 0, points.size() - 1)
	var end_i: int = clampi(end_index, 0, points.size() - 1)
	if end_i <= start_i:
		return 1

	var max_radius: float = 0.0
	var sample_step: int = max(1, int(ceil(float(end_i - start_i + 1) / 96.0)))
	for i in range(start_i, end_i + 1, sample_step):
		max_radius = max(max_radius, (points[i] + anchor).length())
	max_radius = max(max_radius, (points[end_i] + anchor).length())

	var body_radius_scale: float = max(SimulationState.planet_radius, 1.0)
	var orbit_scale: float = max_radius / body_radius_scale
	if orbit_scale <= 3.0:
		return 1

	var normalized_scale: float = orbit_scale / 3.0
	var stride: int = int(round(pow(normalized_scale, 1.6)))
	return clampi(stride, 1, 100)

func _draw_projected_runs(points: Array[Vector3], runs: Array[Dictionary], center: Vector2, max_points: int, line_width: float, dash_length: int = 8, gap_length: int = 5, anchor: Vector3 = Vector3.ZERO) -> void:
	if points.size() < 2 or max_points < 2:
		return

	var point_limit: int = min(points.size(), max_points)
	for run in runs:
		var run_start: int = int(run.get("start", 0))
		var run_end: int = int(run.get("end", 0))
		if run_start >= point_limit - 1:
			continue

		run_end = min(run_end, point_limit - 1)
		if run_end <= run_start:
			continue

		var projected: PackedVector2Array = _project_points_range_decimated(points, run_start, run_end, center, anchor)
		if projected.size() < 2:
			continue

		var run_color: Color = run.get("color", Color(0.6, 1.0, 0.7))
		if bool(run.get("hidden", false)):
			_draw_dashed_polyline(projected, run_color, line_width, dash_length, gap_length, projected.size())
		else:
			draw_polyline(projected, run_color, line_width)

func _build_projected_run_cache(
	points: Array[Vector3],
	runs: Array[Dictionary],
	center: Vector2,
	max_points: int,
	anchor: Vector3 = Vector3.ZERO,
	decimate: bool = true
) -> Array[Dictionary]:
	var projected_runs: Array[Dictionary] = []
	if points.size() < 2 or max_points < 2:
		return projected_runs

	var point_limit: int = min(points.size(), max_points)
	for run in runs:
		var run_start: int = int(run.get("start", 0))
		var run_end: int = int(run.get("end", 0))
		if run_start >= point_limit - 1:
			continue

		run_end = min(run_end, point_limit - 1)
		if run_end <= run_start:
			continue

		var projected: PackedVector2Array = _project_points_range_decimated(points, run_start, run_end, center, anchor) if decimate else _project_points_range(points, run_start, run_end, center, anchor)
		if projected.size() < 2:
			continue

		projected_runs.append({
			"points": projected,
			"color": run.get("color", Color(0.6, 1.0, 0.7)),
			"hidden": bool(run.get("hidden", false))
		})

	return projected_runs

func _draw_projected_run_cache(projected_runs: Array[Dictionary], line_width: float, dash_length: int = 8, gap_length: int = 5) -> void:
	for run in projected_runs:
		var projected: PackedVector2Array = run.get("points", PackedVector2Array())
		if projected.size() < 2:
			continue
		var run_color: Color = run.get("color", Color(0.6, 1.0, 0.7))
		if bool(run.get("hidden", false)):
			_draw_dashed_polyline(projected, run_color, line_width, dash_length, gap_length, projected.size())
		else:
			draw_polyline(projected, run_color, line_width)

func _get_reference_body_pos() -> Vector3:
	return _get_reference_body_state().get("pos", Vector3.ZERO)

func _get_reference_body_vel() -> Vector3:
	return _get_reference_body_state().get("vel", Vector3.ZERO)

func _get_reference_body_up() -> Vector3:
	return _get_reference_body_state().get("up", Vector3.UP)

func _get_reference_frame_origin_pos() -> Vector3:
	return _get_reference_body_state().get("frame_origin_pos", _get_reference_body_pos())

func _get_reference_frame_origin_vel() -> Vector3:
	return _get_reference_body_state().get("frame_origin_vel", _get_reference_body_vel())

func _get_reference_plane_normal() -> Vector3:
	var plane_normal: Vector3 = _get_reference_body_state().get("plane_normal", _get_reference_body_up())
	if plane_normal.length_squared() > 0.0001:
		return plane_normal.normalized()
	return Vector3.UP

func _get_reference_body_radius() -> float:
	return _get_reference_body_state().get("radius", 0.0)

func _get_reference_body_state() -> Dictionary:
	return _get_equator_reference_context()

func _is_currently_in_moon_dominance() -> bool:
	return SimulationState.is_ship_in_moon_dominance()

func _draw_glow_line(a: Vector2, b: Vector2, color: Color, width: float) -> void:
	draw_line(a, b, Color(color.r, color.g, color.b, 0.12), width + 6.0)
	draw_line(a, b, Color(color.r, color.g, color.b, 0.22), width + 3.0)
	draw_line(a, b, color, width)

func _draw_angle_ticks(center: Vector2, radius: float, start_angle: float, end_angle: float, tick_step_deg: float, color: Color) -> void:
	if tick_step_deg <= 0.0:
		return

	var a0: float = start_angle
	var a1: float = end_angle

	if a1 < a0:
		var temp: float = a0
		a0 = a1
		a1 = temp

	var step: float = deg_to_rad(tick_step_deg)
	var angle: float = ceil(a0 / step) * step

	while angle < a1 - 0.0001:
		var outer: Vector2 = center + Vector2(cos(angle), sin(angle)) * radius
		var inner: Vector2 = center + Vector2(cos(angle), sin(angle)) * (radius - 6.0)
		draw_line(inner, outer, color, 1.0)
		angle += step

func _build_inclination_projection_context(rect_size: Vector2, center: Vector2) -> Dictionary:
	var side: float = rect_size.y * 0.985
	var outer_radius: float = side * 0.43
	var reference_context: Dictionary = _get_reference_body_state()
	return {
		"center": center,
		"outer_radius": outer_radius,
		"line_extent": outer_radius - 12.0,
		"frame_origin_pos": reference_context.get("frame_origin_pos", Vector3.ZERO),
		"frame_origin_vel": reference_context.get("frame_origin_vel", Vector3.ZERO),
		"reference_plane_normal": _get_reference_plane_normal(),
		"reference_body_name": reference_context.get("name", PRIMARY_BODY_NAME),
		"frame_body_name": reference_context.get("frame_reference_body_name", reference_context.get("name", PRIMARY_BODY_NAME)),
		"stable_phase_basis": _get_equator_stable_phase_basis(reference_context),
		"coplanar_threshold_rad": deg_to_rad(equator_coplanar_threshold_degrees),
	}

func _project_relative_state_to_inclination_line(
	relative_pos: Vector3,
	relative_vel: Vector3,
	context: Dictionary,
	line_basis: Dictionary = {}
) -> Dictionary:
	var reference_plane_normal: Vector3 = context.get("reference_plane_normal", Vector3.UP)
	var inst_center: Vector2 = context.get("center", Vector2.ZERO)
	var line_extent: float = context.get("line_extent", 0.0)
	var coplanar_threshold_rad: float = float(context.get("coplanar_threshold_rad", deg_to_rad(0.5)))
	var stable_phase_basis: Dictionary = context.get("stable_phase_basis", {})

	var r: Vector3 = relative_pos
	var v: Vector3 = relative_vel
	var line_basis_locked: bool = bool(line_basis.get("valid", false))
	if r.length_squared() < 0.0001:
		return {"valid": false}
	var live_plane_normal: Vector3 = SimulationState.get_orbital_plane_normal_from_relative_state(r, v)
	if not line_basis_locked and live_plane_normal.length_squared() <= 0.0001:
		return {"valid": false}

	var hhat: Vector3 = live_plane_normal if live_plane_normal.length_squared() > 0.0001 else Vector3.UP
	var inc_display_rad: float = 0.0
	var plane_angle: float = 0.0
	var plane_dir: Vector2 = Vector2.RIGHT
	var node_hat: Vector3 = Vector3.ZERO
	var q_hat: Vector3 = Vector3.ZERO
	var node_defined: bool = false
	var plane_alignment_dot: float = 1.0
	var same_direction: bool = true

	if line_basis_locked:
		hhat = line_basis.get("hhat", reference_plane_normal).normalized()
		inc_display_rad = float(line_basis.get("inc_display_rad", 0.0))
		plane_angle = float(line_basis.get("plane_angle", 0.0))
		plane_dir = line_basis.get("plane_dir", Vector2.RIGHT)
		if plane_dir.length_squared() > 0.0001:
			plane_dir = plane_dir.normalized()
		else:
			plane_dir = Vector2.RIGHT
		node_hat = line_basis.get("node_hat", Vector3.ZERO)
		q_hat = line_basis.get("q_hat", Vector3.ZERO)
		node_defined = bool(line_basis.get("node_defined", false))
		plane_alignment_dot = float(line_basis.get("plane_alignment_dot", 1.0))
		same_direction = bool(line_basis.get("same_direction", true))
	else:
		plane_alignment_dot = clampf(hhat.dot(reference_plane_normal), -1.0, 1.0)
		same_direction = plane_alignment_dot >= 0.0
		inc_display_rad = acos(abs(plane_alignment_dot))
		# The tilt is intentionally unsigned magnitude only. Direction-sensitive
		# cues come from vertical motion, next-node timing, and same-direction state.
		plane_angle = -inc_display_rad
		plane_dir = Vector2(cos(plane_angle), sin(plane_angle)).normalized()

		if inc_display_rad > coplanar_threshold_rad:
			var node_vec: Vector3 = reference_plane_normal.cross(hhat)
			if node_vec.length_squared() > 0.0001:
				node_hat = node_vec.normalized()
				q_hat = hhat.cross(node_hat).normalized()
				node_defined = q_hat.length_squared() > 0.0001

		if not node_defined and bool(stable_phase_basis.get("valid", false)):
			node_hat = stable_phase_basis.get("node_hat", Vector3.ZERO)
			q_hat = stable_phase_basis.get("q_hat", Vector3.ZERO)
			node_defined = node_hat.length_squared() > 0.0001 and q_hat.length_squared() > 0.0001

	var line_displacement: float = 0.0
	var ship_marker: Vector2 = inst_center
	if node_defined:
		var u: float = atan2(r.dot(q_hat), r.dot(node_hat))
		if u < 0.0:
			u += TAU
		line_displacement = clampf(sin(u) * line_extent, -line_extent, line_extent)
		ship_marker = inst_center + plane_dir * line_displacement
	var vertical_rate: float = v.dot(reference_plane_normal)
	var coplanar: bool = inc_display_rad <= coplanar_threshold_rad

	return {
		"valid": true,
		"screen": ship_marker,
		"plane_angle": plane_angle,
		"plane_dir": plane_dir,
		"line_displacement": line_displacement,
		"inc_display_rad": inc_display_rad,
		"inc_display_deg": rad_to_deg(inc_display_rad),
		"vertical_rate": vertical_rate,
		"coplanar": coplanar,
		"node_defined": node_defined,
		"plane_alignment_dot": plane_alignment_dot,
		"same_direction": same_direction,
		"retrograde": not same_direction,
		"line_basis": {
			"valid": true,
			"hhat": hhat,
			"inc_display_rad": inc_display_rad,
			"plane_angle": plane_angle,
			"plane_dir": plane_dir,
			"node_hat": node_hat,
			"q_hat": q_hat,
			"node_defined": node_defined,
			"plane_alignment_dot": plane_alignment_dot,
			"same_direction": same_direction,
		}
	}

func _project_state_to_inclination_line(
	ship_world_pos: Vector3,
	ship_world_vel: Vector3,
	context: Dictionary,
	line_basis: Dictionary = {}
) -> Dictionary:
	var frame_origin_pos: Vector3 = context.get("frame_origin_pos", Vector3.ZERO)
	var frame_origin_vel: Vector3 = context.get("frame_origin_vel", Vector3.ZERO)
	return _project_relative_state_to_inclination_line(
		ship_world_pos - frame_origin_pos,
		ship_world_vel - frame_origin_vel,
		context,
		line_basis
	)

func _get_inclination_frame_origin_body_name() -> StringName:
	var reference_state: Dictionary = _get_reference_body_state()
	var default_origin_body_name: StringName = reference_state.get("name", PRIMARY_BODY_NAME)
	return reference_state.get("frame_reference_body_name", default_origin_body_name)

func _get_inclination_frame_origin_relative_points(frame_origin_body_name: StringName) -> Array[Vector3]:
	if frame_origin_body_name == PRIMARY_BODY_NAME or frame_origin_body_name == &"":
		var empty_points: Array[Vector3] = []
		return empty_points
	return solution.get_body_relative_points(frame_origin_body_name)

func _get_inclination_source_time(source_index: int) -> float:
	return timewarp_solution_start_sim_time + float(source_index) * maxf(prediction_step_seconds, 0.001)

func _get_inclination_relative_state_for_source_index(
	source_index: int,
	frame_origin_body_name: StringName,
	frame_origin_relative_points: Array[Vector3]
) -> Dictionary:
	if (
		source_index < 0
		or source_index >= solution.ship_points.size()
		or source_index >= solution.ship_velocities.size()
	):
		return {"valid": false}

	var ship_rel_planet: Vector3 = solution.ship_points[source_index]
	var ship_world_vel: Vector3 = solution.ship_velocities[source_index]
	var source_time: float = _get_inclination_source_time(source_index)
	if frame_origin_body_name == PRIMARY_BODY_NAME or frame_origin_body_name == &"":
		var primary_state: Dictionary = SimulationState.get_body_state_at_time(PRIMARY_BODY_NAME, source_time)
		var primary_world_vel: Vector3 = primary_state.get("vel", SimulationState.get_body_velocity(PRIMARY_BODY_NAME))
		return {
			"valid": true,
			"pos": ship_rel_planet,
			"vel": ship_world_vel - primary_world_vel
		}

	if source_index >= frame_origin_relative_points.size():
		return {"valid": false}

	var frame_origin_state: Dictionary = SimulationState.get_body_state_at_time(frame_origin_body_name, source_time)
	var frame_origin_world_vel: Vector3 = frame_origin_state.get("vel", SimulationState.get_body_velocity(frame_origin_body_name))
	return {
		"valid": true,
		"pos": ship_rel_planet - frame_origin_relative_points[source_index],
		"vel": ship_world_vel - frame_origin_world_vel
	}

func _get_selected_inclination_screen_point(rect_size: Vector2, center: Vector2) -> Dictionary:
	var point_limit: int = _get_timewarp_point_limit()
	if timewarp_selector.selection_index < 0 or solution.ship_points.is_empty() or point_limit <= 0:
		return {"valid": false}

	var projection_context: Dictionary = _build_inclination_projection_context(rect_size, center)
	var base_projection: Dictionary = _project_state_to_inclination_line(
		SimulationState.ship_pos,
		SimulationState.ship_vel,
		projection_context
	)
	if not base_projection.get("valid", false):
		return {"valid": false}

	if timewarp_selector.selection_index <= 0:
		return {
			"valid": true,
			"screen": base_projection.get("screen", Vector2.ZERO),
		}

	var target_index: int = timewarp_selector.get_target_index(point_limit)
	if target_index < 0 or target_index >= solution.ship_points.size() or target_index >= point_limit:
		return {"valid": false}

	var frame_origin_body_name: StringName = _get_inclination_frame_origin_body_name()
	var frame_origin_relative_points: Array[Vector3] = _get_inclination_frame_origin_relative_points(frame_origin_body_name)
	var target_relative_state: Dictionary = _get_inclination_relative_state_for_source_index(
		target_index,
		frame_origin_body_name,
		frame_origin_relative_points
	)
	if not target_relative_state.get("valid", false):
		return {"valid": false}

	# Project the future instantaneous relative state onto the current basis
	# rather than pretending the whole instrument has already rotated forward.
	var target_projection: Dictionary = _project_relative_state_to_inclination_line(
		target_relative_state.get("pos", Vector3.ZERO),
		target_relative_state.get("vel", Vector3.ZERO),
		projection_context,
		base_projection.get("line_basis", {})
	)
	if not target_projection.get("valid", false):
		return {"valid": false}

	return {
		"valid": true,
		"screen": target_projection.get("screen", Vector2.ZERO),
	}

func _get_next_inclination_node_info() -> Dictionary:
	var point_limit: int = _get_timewarp_point_limit()
	if point_limit <= 1 or solution.ship_points.size() <= 1:
		return {}

	var frame_origin_body_name: StringName = _get_inclination_frame_origin_body_name()
	var frame_origin_relative_points: Array[Vector3] = _get_inclination_frame_origin_relative_points(frame_origin_body_name)
	var reference_plane_normal: Vector3 = _get_reference_plane_normal()
	if reference_plane_normal.length_squared() <= 0.0001:
		return {}

	var start_index: int = clampi(timewarp_selector.reference_index, 0, point_limit - 1)
	var prev_state: Dictionary = _get_inclination_relative_state_for_source_index(
		start_index,
		frame_origin_body_name,
		frame_origin_relative_points
	)
	if not prev_state.get("valid", false):
		return {}

	var prev_pos: Vector3 = prev_state.get("pos", Vector3.ZERO)
	var prev_height: float = prev_pos.dot(reference_plane_normal)
	for i in range(start_index + 1, point_limit):
		var curr_state: Dictionary = _get_inclination_relative_state_for_source_index(
			i,
			frame_origin_body_name,
			frame_origin_relative_points
		)
		if not curr_state.get("valid", false):
			break

		var curr_pos: Vector3 = curr_state.get("pos", Vector3.ZERO)
		var curr_height: float = curr_pos.dot(reference_plane_normal)
		var crossed: bool = (
			(prev_height <= 0.0 and curr_height > 0.0)
			or (prev_height >= 0.0 and curr_height < 0.0)
		)
		if crossed:
			var denom: float = maxf(absf(prev_height) + absf(curr_height), 0.000001)
			var t: float = clampf(absf(prev_height) / denom, 0.0, 1.0)
			var samples_ahead: float = float(i - 1 - start_index) + t
			var time_seconds: float = maxf(samples_ahead * maxf(prediction_step_seconds, 0.001), 0.0)
			return {
				"valid": true,
				"label": "AN" if curr_height > prev_height else "DN",
				"time_seconds": time_seconds
			}

		prev_height = curr_height

	return {}

func _get_next_inclination_node_metric_text() -> String:
	var node_info: Dictionary = _get_next_inclination_node_info()
	if node_info.is_empty() or not node_info.get("valid", false):
		return ""

	var node_label: String = String(node_info.get("label", "AN"))
	var node_time_seconds: int = max(0, int(round(float(node_info.get("time_seconds", 0.0)))))
	return "%s IN: T+%ds" % [node_label, node_time_seconds]

func _log_equator_debug_if_needed(
	reference_context: Dictionary,
	ship_plane_normal: Vector3,
	reference_plane_normal: Vector3,
	plane_error_deg: float,
	same_direction: bool
) -> void:
	if not debug_equator_instrument:
		return
	var frame_count: int = Engine.get_process_frames()
	if frame_count % 30 != 0:
		return
	print(
		"EQUATOR | ref=%s | frame=%s | source=%s | ship_n=%s | ref_n=%s | err=%.3f | same_dir=%s"
		% [
			String(reference_context.get("name", PRIMARY_BODY_NAME)),
			String(reference_context.get("frame_reference_body_name", PRIMARY_BODY_NAME)),
			String(reference_context.get("plane_source", "unknown")),
			ship_plane_normal,
			reference_plane_normal,
			plane_error_deg,
			"yes" if same_direction else "no"
		]
	)

func _draw_inclination_instrument(rect_size: Vector2, center: Vector2) -> void:
	var side: float = rect_size.y * 0.985
	var inst_center: Vector2 = center

	var outer_radius: float = side * 0.43
	
	var line_half: float = outer_radius
	var body_radius_px: float = side * 0.085

	var equator_color: Color = Color(0.15, 0.45, 0.2)
	var body_color: Color = Color(0.2, 0.8, 0.35)
	var plane_color: Color = Color(0.4, 1.0, 0.6)
	var node_color: Color = Color(0.3, 0.9, 1.0)
	var theta_color: Color = Color(1.0, 0.8, 0.35)
	var ship_color: Color = Color(0.95, 0.95, 0.95)
	var text_green: Color = Color(0.75, 1.0, 0.2)
	var center_label_color: Color = Color.BLACK
	var outer_circle_color: Color = Color(0.75, 1.0, 0.2)

	var reference_context: Dictionary = _get_reference_body_state()
	var projection_context: Dictionary = _build_inclination_projection_context(rect_size, center)
	var frame_origin_pos: Vector3 = projection_context.get("frame_origin_pos", Vector3.ZERO)
	var frame_origin_vel: Vector3 = projection_context.get("frame_origin_vel", Vector3.ZERO)
	var reference_plane_normal: Vector3 = projection_context.get("reference_plane_normal", Vector3.UP)

	var r: Vector3 = SimulationState.ship_pos - frame_origin_pos
	var v: Vector3 = SimulationState.ship_vel - frame_origin_vel
	var ship_plane_normal: Vector3 = SimulationState.get_orbital_plane_normal_from_relative_state(r, v)

	var font := ThemeDB.fallback_font
	var font_size := 14
	var big_font_size := 30
	var title_text: String = "EQUATOR"
	var title_size: Vector2 = font.get_string_size(title_text, HORIZONTAL_ALIGNMENT_LEFT, -1, big_font_size)
	draw_string(
		font,
		Vector2(inst_center.x - title_size.x * 0.5, 36.0),
		title_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		big_font_size,
		Color(0.35, 1.0, 0.35)
	)
	# Outer circle
	draw_arc(inst_center, outer_radius, 0.0, TAU, 128, outer_circle_color, 2.0)

	# Hash marks all around outer circle
	var tick_step_deg: float = 5.0
	var tick_step_rad: float = deg_to_rad(tick_step_deg)
	var tick_angle: float = 0.0
	while tick_angle < TAU - 0.0001:
		var outer: Vector2 = inst_center + Vector2(cos(tick_angle), sin(tick_angle)) * outer_radius
		var inner: Vector2 = inst_center + Vector2(cos(tick_angle), sin(tick_angle)) * (outer_radius - 7.0)
		draw_line(inner, outer, Color(0.35, 0.75, 0.2, 0.9), 1.0)
		tick_angle += tick_step_rad

	# Equator line
	var eq_a: Vector2 = inst_center + Vector2(-line_half, 0.0)
	var eq_b: Vector2 = inst_center + Vector2(line_half, 0.0)
	_draw_glow_line(eq_a, eq_b, equator_color, 2.0)

	# Body
	draw_circle(inst_center, body_radius_px, body_color)

	if r.length_squared() < 0.0001 or v.length_squared() < 0.0001 or ship_plane_normal.length_squared() < 0.0001:
		var reference_text_empty: String = "Reference: " + get_reference_body_text().capitalize()
		var ref_size_empty: Vector2 = font.get_string_size(reference_text_empty, HORIZONTAL_ALIGNMENT_LEFT, -1, big_font_size)
		draw_string(
			font,
			Vector2(60.0, rect_size.y - 28.0),
			"ASCENDING...",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			big_font_size,
			text_green
		)

		draw_string(
			font,
			Vector2(rect_size.x - ref_size_empty.x - 60.0, rect_size.y - 28.0),
			reference_text_empty,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			big_font_size,
			text_green
		)
		return

	var inclination_projection: Dictionary = _project_state_to_inclination_line(
		SimulationState.ship_pos,
		SimulationState.ship_vel,
		projection_context
	)
	if not inclination_projection.get("valid", false):
		return
	if inclination_projection.get("node_defined", false) and not inclination_projection.get("coplanar", false):
		_store_equator_stable_phase_basis(reference_context, inclination_projection.get("line_basis", {}))

	var inc_display_deg: float = inclination_projection.get("inc_display_deg", 0.0)
	var plane_angle: float = inclination_projection.get("plane_angle", 0.0)
	var plane_dir: Vector2 = inclination_projection.get("plane_dir", Vector2.RIGHT)
	var same_direction: bool = bool(inclination_projection.get("same_direction", true))
	_log_equator_debug_if_needed(
		reference_context,
		ship_plane_normal,
		reference_plane_normal,
		inc_display_deg,
		same_direction
	)

	# Two connected half-segments
	var plane_end_pos: Vector2 = inst_center + plane_dir * (outer_radius - 6.0)
	var plane_end_neg: Vector2 = inst_center - plane_dir * (outer_radius - 6.0)

	_draw_glow_line(inst_center, plane_end_pos, plane_color, 2.5)
	_draw_glow_line(inst_center, plane_end_neg, plane_color, 2.5)

	var vertical_rate: float = inclination_projection.get("vertical_rate", 0.0)
	var node_defined: bool = bool(inclination_projection.get("node_defined", false))
	var coplanar: bool = bool(inclination_projection.get("coplanar", false))
	var motion_text: String = "ASCENDING..."
	if vertical_rate < 0.0:
		motion_text = "DESCENDING..."

	if coplanar:
		motion_text = "COPLANAR"

	var ship_marker: Vector2 = inclination_projection.get("screen", inst_center)
	var next_node_info: Dictionary = _get_next_inclination_node_info()
	var next_node_label: String = ""
	if node_defined and not coplanar and next_node_info.get("valid", false):
		next_node_label = String(next_node_info.get("label", ""))

	# Center node marker and readable label
	draw_circle(inst_center, 4.5, node_color)
	if not next_node_label.is_empty():
		var center_label_size: Vector2 = font.get_string_size(next_node_label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		draw_string(
			font,
			inst_center + Vector2(-center_label_size.x * 0.5, center_label_size.y * 0.35),
			next_node_label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			center_label_color
		)

	# Ship marker
	draw_circle(ship_marker, 6.5, Color(1,1,1,0.08))
	draw_circle(ship_marker, 5.0, Color(1,1,1,0.15))
	draw_circle(ship_marker, 3.5, Color.WHITE)

	# Theta arc moved outward near outer circle edge
	var arc_radius: float = outer_radius - 16.0
	draw_arc(inst_center, arc_radius, plane_angle, 0.0, 48, theta_color, 2.5)
	

	var mid_angle: float = plane_angle * 0.5
	var theta_text_pos: Vector2 = inst_center + Vector2(cos(mid_angle), sin(mid_angle)) * (arc_radius - 18.0)

	var theta_text := "%.1f°" % inc_display_deg
	var theta_text_size: Vector2 = font.get_string_size(theta_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	draw_string(
		font,
		theta_text_pos + Vector2(-theta_text_size.x * 0.5, theta_text_size.y * 0.35),
		theta_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		theta_color
	)

	var next_node_metric_text: String = ""
	if not coplanar:
		next_node_metric_text = _get_next_inclination_node_metric_text()
	if not next_node_metric_text.is_empty():
		var metric_font_size: int = 18
		var metric_size: Vector2 = font.get_string_size(next_node_metric_text, HORIZONTAL_ALIGNMENT_LEFT, -1, metric_font_size)
		draw_string(
			font,
			Vector2(rect_size.x - metric_size.x - 60.0, 58.0),
			next_node_metric_text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			metric_font_size,
			text_green
		)

	# Bottom left status text
	draw_string(
		font,
		Vector2(60.0, rect_size.y - 28.0),
		motion_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		big_font_size,
		text_green
	)

	# Bottom right reference text
	var reference_text: String = "Reference: " + get_reference_body_text().capitalize()
	var ref_size: Vector2 = font.get_string_size(reference_text, HORIZONTAL_ALIGNMENT_LEFT, -1, big_font_size)
	draw_string(
		font,
		Vector2(rect_size.x - ref_size.x - 60.0, rect_size.y - 28.0),
		reference_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		big_font_size,
		text_green
	)

func _draw() -> void:
	debug_draw_calls_since_log += 1
	var rect_size: Vector2 = get_viewport_rect().size
	var center: Vector2 = rect_size * 0.5
	var font := ThemeDB.fallback_font
	var big_font_size := 30
	var text_green := Color(0.35, 1.0, 0.35)
	var rendered_visible_count: int = 0
	var rendered_main_visible_count: int = 0
	var rendered_ghost_alpha: float = _get_current_ghost_alpha()
	
	draw_rect(Rect2(Vector2.ZERO, rect_size), Color(0.02, 0.04, 0.02), true)

	if display_mode == DisplayMode.INCLINATION:
		_draw_inclination_instrument(rect_size, center)
		if is_timewarp_selection_available() and timewarp_selector.selection_index >= 0:
			var selected_inclination_point: Dictionary = _get_selected_inclination_screen_point(rect_size, center)
			if selected_inclination_point.get("valid", false):
				_draw_selection_box(selected_inclination_point["screen"], Color(1.0, 0.82, 0.25))
		_draw_timewarp_legend(rect_size, text_green)
		_draw_calculating_status_box(rect_size)
		_record_draw_state(0, 0, rendered_ghost_alpha)
		return
	var plan_title: String = "BENDING TIME..." if SimulationState.is_targeted_warp_active() else "PLAN"
	var plan_title_size: Vector2 = font.get_string_size(plan_title, HORIZONTAL_ALIGNMENT_LEFT, -1, big_font_size)
	draw_string(
		font,
		Vector2(center.x - plan_title_size.x * 0.5, 46.0),
		plan_title,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		big_font_size,
		text_green
	)
	var view_text: String = "VIEW: " + get_center_mode_text()
	draw_string(
		font,
		Vector2(60.0, 46.0),
		view_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		big_font_size - 8,
		text_green
	)
	draw_line(Vector2(center.x, 0.0), Vector2(center.x, rect_size.y), Color(0.05, 0.12, 0.05), 1.0)
	draw_line(Vector2(0.0, center.y), Vector2(rect_size.x, center.y), Color(0.05, 0.12, 0.05), 1.0)

	var focused_child_name: StringName = _get_selected_focused_child_body_name()
	var planet_world := Vector3.ZERO
	var planet_screen := _to_screen(planet_world, center)
	var planet_radius_px: float = SimulationState.planet_radius * pixels_per_unit

	for r in [250.0, 1000.0, 2500.0]:
		draw_arc(planet_screen, r * pixels_per_unit, 0.0, TAU, 96, Color(0.08, 0.22, 0.08), 1.0)

	draw_line(planet_screen + Vector2(-10.0, 0.0), planet_screen + Vector2(10.0, 0.0), Color(0.1, 0.45, 0.1), 1.0)
	draw_line(planet_screen + Vector2(0.0, -10.0), planet_screen + Vector2(0.0, 10.0), Color(0.1, 0.45, 0.1), 1.0)

	draw_circle(planet_screen, planet_radius_px, Color(0.2, 0.65, 1.0))
	var focused_child_rel_planet: Vector3 = Vector3.ZERO
	var focused_child_screen: Vector2 = planet_screen
	var show_child_plan_markers: bool = center_mode == CenterMode.PLANET or center_mode == CenterMode.SHIP
	for child_body_name in _get_available_focused_child_body_names():
		var child_rel_planet: Vector3 = SimulationState.get_body_position(child_body_name) - SimulationState.get_body_position(PRIMARY_BODY_NAME)
		var child_screen: Vector2 = _to_screen(child_rel_planet, center)
		var orbit_color: Color = Color(0.5, 0.5, 0.8)
		var body_color: Color = Color(0.8, 0.8, 0.95)
		var track_data: Dictionary = _sample_child_orbit_track_data(center, child_body_name)
		if child_body_name == focused_child_name:
			orbit_color = Color(0.65, 0.75, 1.0)
			body_color = Color(0.92, 0.92, 1.0)
			focused_child_rel_planet = child_rel_planet
			focused_child_screen = child_screen
		_draw_child_orbit_track(track_data, orbit_color)
		draw_circle(child_screen, SimulationState.get_body_radius(child_body_name) * pixels_per_unit, body_color)
		if show_child_plan_markers:
			_draw_selected_child_plan_markers(track_data, planet_screen, planet_radius_px)

	var ship_rel_planet: Vector3 = SimulationState.ship_pos - SimulationState.planet_pos
	var ship_screen := _to_screen(ship_rel_planet, center)

	var reference_body_pos: Vector3 = SimulationState.get_ship_reference_body_pos()
	var reference_body_vel: Vector3 = SimulationState.get_ship_reference_body_vel()
	var body_up: Vector3 = SimulationState.get_ship_reference_body_up()
	var r3: Vector3 = SimulationState.ship_pos - reference_body_pos
	var v3: Vector3 = SimulationState.ship_vel - reference_body_vel

	var vel: float = v3.length()
	var vel_text: String = "VEL: %.3f NU/s" % vel

	var body_radius: float = SimulationState.get_body_radius(SimulationState.get_ship_reference_body_name())
	var altitude: float = r3.length() - body_radius
	var r_text: String = "ALT: %.3f NU" % altitude

	var h3: Vector3 = r3.cross(v3)
	var inc: float = 0.0
	if h3.length_squared() > 0.0001:
		var orbit_normal: Vector3 = (-h3).normalized()
		# PLAN INC convention: 0 = prograde coplanar, 180 = retrograde coplanar, 90 = polar.
		inc = rad_to_deg(acos(clampf(orbit_normal.dot(body_up.normalized()), -1.0, 1.0)))

	var inc_text: String = "INC: %.2f°" % inc
	draw_string(
		font,
		Vector2(60.0, rect_size.y - 30.0),
		inc_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		big_font_size - 6,
		text_green
	)
	draw_string(
		font,
		Vector2(60.0, rect_size.y - 60.0),
		r_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		big_font_size - 6,
		text_green
	)
	draw_string(
		font,
		Vector2(60.0, rect_size.y - 90.0),
		vel_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		big_font_size - 6,
		text_green
	)
	draw_circle(ship_screen, 4.0, Color.WHITE)

	var vel_world: Vector3 = v3
	if vel_world.length() > 0.001:
		var vel_tip_world: Vector3 = ship_rel_planet + vel_world.normalized() * (40.0 / pixels_per_unit)
		var vel_tip_screen: Vector2 = _to_screen(vel_tip_world, center)
		var vel_screen_delta: Vector2 = vel_tip_screen - ship_screen

		if vel_screen_delta.length_squared() > 0.0001:
			_draw_projected_arrow(ship_screen, vel_tip_screen, Color.YELLOW, 2.0, 10.0, 8.0)

	if ship != null:
		var facing_world: Vector3 = (ship.global_transform.basis.z).normalized()
		var facing_tip_world: Vector3 = ship_rel_planet + facing_world * (30.0 / pixels_per_unit)

		var facing_tip_screen: Vector2 = _to_screen(facing_tip_world, center)
		var facing_screen_delta: Vector2 = facing_tip_screen - ship_screen

		if facing_screen_delta.length_squared() > 0.0001:
			_draw_projected_arrow(ship_screen, facing_tip_screen, Color(0.75, 1.0, 1.0), 2.0, 10.0, 8.0)

	if solution.ship_points.size() > 1:
		var focused_child_relative_points: Array[Vector3] = _get_focused_child_relative_points()
		var focused_child_closest_approach: Dictionary = _get_focused_child_closest_approach()
		var active_local_segment: Dictionary = _get_active_local_segment()
		var active_markers: Dictionary = _get_active_markers()
		var active_impact: Dictionary = _get_active_impact()
		var active_local_points: Array[Vector3] = _get_active_local_points()
		var active_local_source_indices: Array[int] = _get_active_local_source_indices()
		var focused_child_closest_approach_index: int = focused_child_closest_approach.get("index", -1)
		var focused_child_radius: float = SimulationState.get_body_radius(focused_child_name)
		var focused_child_ca_surface_distance: float = _compute_surface_distance_from_center_distance(
			focused_child_closest_approach.get("distance", -1.0),
			focused_child_radius
		)
		var ratio: float = clampf(reveal_elapsed / reveal_duration, 0.0, 1.0) if reveal_duration > 0.0 else 1.0
		var display_step_cap: int = min(solution.ship_points.size(), max(2, solution.display_steps_used))
		var visible_count: int = max(2, int(round((display_step_cap - 1) * ratio)) + 1)
		visible_count = min(visible_count, display_step_cap)
		var ghost_alpha: float = _get_current_ghost_alpha()
		var reveal_complete: bool = (not is_revealing) and visible_count >= display_step_cap
		var moon_entry_index: int = active_local_segment.get("entry_index", cached_focused_child_entry_index)
		var moon_exit_index: int = active_local_segment.get("exit_index", cached_focused_child_exit_index)
		var currently_in_focused_child_dominance: bool = _is_currently_in_focused_child_dominance()
		var copied_ca_screen: Vector2 = Vector2.ZERO
		var copied_ca_valid: bool = false
		var main_visible_count: int = visible_count
		if center_mode == CenterMode.MOON and moon_entry_index >= 0 and moon_entry_index < visible_count:
			main_visible_count = max(2, moon_entry_index + 1)
		main_visible_count = min(main_visible_count, cached_ship_source_points.size())
		_ensure_projected_render_cache(
			center,
			visible_count,
			main_visible_count,
			active_local_points,
			active_local_source_indices,
			focused_child_rel_planet
		)
		rendered_visible_count = visible_count
		rendered_main_visible_count = main_visible_count
		rendered_ghost_alpha = ghost_alpha
		_draw_projected_run_cache(cached_projected_ship_run_draws, 2.0)

		var drew_moon_orbit_markers: bool = false
		if center_mode == CenterMode.MOON and moon_entry_index >= 0:
			var moon_intercept_color: Color = Color(1.0, 0.92, 0.72)
			var moon_escape_color: Color = Color(0.55, 0.95, 1.0)
			var moon_escape_marker_color: Color = Color(1.0, 0.82, 0.25)
			var moon_intercept_width: float = 1.6
			var live_moon_anchor: Vector3 = focused_child_rel_planet
			var visible_local_count: int = 0
			for source_index in active_local_source_indices:
				if source_index < visible_count:
					visible_local_count += 1
				else:
					break

			if visible_local_count > 1:
				_draw_projected_run_cache(cached_projected_local_run_draws, moon_intercept_width, 8, 5)
				var moon_pts: PackedVector2Array = cached_projected_local_points

				if active_markers.get("show_escape_marker", cached_show_focused_child_escape_marker) and not active_impact.get("found", cached_focused_child_local_impact_found):
					var local_exit_index: int = min(
						active_markers.get("escape_marker_local_index", cached_focused_child_escape_marker_local_index) if active_markers.get("escape_marker_local_index", cached_focused_child_escape_marker_local_index) >= 0 else visible_local_count - 1,
						min(visible_local_count - 1, moon_pts.size() - 1)
					)
					if local_exit_index >= 0 and local_exit_index < moon_pts.size():
						var moon_exit_screen: Vector2 = moon_pts[local_exit_index]
						_draw_marker_square(moon_exit_screen, 6.0, moon_escape_marker_color)
						_draw_marker_label(moon_exit_screen, "ESC", moon_escape_marker_color, focused_child_screen)
				if (
					reveal_complete
					and not active_impact.get("found", cached_focused_child_local_impact_found)
					and moon_exit_index >= 0
					and moon_exit_index < visible_count
				):
					var tail_start_index: int = moon_exit_index
					var tail_end_index: int = min(visible_count - 1, moon_exit_index + moon_escape_tail_steps)
					if tail_end_index > tail_start_index and tail_start_index < focused_child_relative_points.size():
						var moon_escape_tail_screen := PackedVector2Array()
						for i in range(tail_start_index, tail_end_index + 1):
							if i >= solution.ship_points.size() or i >= focused_child_relative_points.size():
								break
							var ship_rel_moon: Vector3 = solution.ship_points[i] - focused_child_relative_points[i]
							moon_escape_tail_screen.append(_to_screen(ship_rel_moon + live_moon_anchor, center))
						if moon_escape_tail_screen.size() > 1:
							draw_polyline(moon_escape_tail_screen, moon_escape_color, 1.6)
							var arrow_start_index: int = _find_arrow_start_index(moon_escape_tail_screen, 12.0)
							if arrow_start_index >= 0 and arrow_start_index < moon_escape_tail_screen.size() - 1:
								_draw_projected_arrow(
									moon_escape_tail_screen[arrow_start_index],
									moon_escape_tail_screen[moon_escape_tail_screen.size() - 1],
								moon_escape_color,
								1.6,
								10.0,
								8.0
							)
				elif (
					reveal_complete
					and moon_exit_index < 0
					and not active_impact.get("found", cached_focused_child_local_impact_found)
					and active_markers.get("show_escape_marker", cached_show_focused_child_escape_marker)
					and moon_pts.size() > 1
				):
					var fallback_tail_tip: Vector2 = moon_pts[moon_pts.size() - 1]
					var fallback_tail_start: Vector2 = moon_pts[max(0, moon_pts.size() - 2)]
					var fallback_delta: Vector2 = fallback_tail_tip - fallback_tail_start
					if fallback_delta.length_squared() > 0.0001:
						var fallback_dir: Vector2 = fallback_delta.normalized()
						var fallback_tip: Vector2 = fallback_tail_tip + fallback_dir * 36.0
						draw_line(fallback_tail_tip, fallback_tip, moon_escape_color, 1.6)
						_draw_projected_arrow(
							fallback_tail_tip,
							fallback_tip,
							moon_escape_color,
							1.6,
							10.0,
							8.0
						)

				var local_ca_index: int = active_markers.get("local_ca_index", cached_focused_child_local_ca_index)
				if active_markers.get("show_local_ca_marker", cached_show_focused_child_local_ca_marker) and local_ca_index >= 0 and local_ca_index < moon_pts.size():
					copied_ca_screen = moon_pts[local_ca_index]
					copied_ca_valid = true

				var local_pe_index: int = active_markers.get("local_pe_index", cached_focused_child_local_pe_index)
				var local_ap_index: int = active_markers.get("local_ap_index", cached_focused_child_local_ap_index)
				if local_pe_index >= 0 and local_pe_index < moon_pts.size():
					var moon_pe_screen: Vector2 = moon_pts[local_pe_index]
					_draw_marker_square(moon_pe_screen, 6.0, Color(0.892, 1.0, 0.35))
					var moon_pe_surface_distance: float = -1.0
					if local_pe_index < active_local_points.size():
						moon_pe_surface_distance = _compute_surface_distance_from_relative_point(active_local_points[local_pe_index], focused_child_radius)
					_draw_marker_label(moon_pe_screen, "PE", Color(0.892, 1.0, 0.35), focused_child_screen, moon_pe_surface_distance)
					drew_moon_orbit_markers = true

				if local_ap_index >= 0 and local_ap_index < moon_pts.size():
					var moon_ap_screen: Vector2 = moon_pts[local_ap_index]
					_draw_marker_square(moon_ap_screen, 6.0, Color(0.35, 0.75, 1.0))
					var moon_ap_surface_distance: float = -1.0
					if local_ap_index < active_local_points.size():
						moon_ap_surface_distance = _compute_surface_distance_from_relative_point(active_local_points[local_ap_index], focused_child_radius)
					_draw_marker_label(moon_ap_screen, "AP", Color(0.35, 0.75, 1.0), focused_child_screen, moon_ap_surface_distance)
					drew_moon_orbit_markers = true

				var local_impact_index: int = active_impact.get("index", cached_focused_child_local_impact_index)
				if active_impact.get("found", cached_focused_child_local_impact_found) and local_impact_index >= 0 and local_impact_index < moon_pts.size():
					_draw_impact_marker(moon_pts[local_impact_index], 10.0, Color(1.0, 0.25, 0.25))
					_handle_impact_reached_on_draw()

		if center_mode != CenterMode.MOON:
			var child_body_names: Array[StringName] = _get_available_focused_child_body_names()
			for child_index in range(child_body_names.size()):
				var child_body_name: StringName = child_body_names[child_index]
				var child_draw_points: PackedVector2Array = cached_projected_child_ghosts.get(child_body_name, PackedVector2Array())
				if child_draw_points.size() <= 1:
					continue

				var is_selected_child: bool = child_body_name == focused_child_name
				var ghost_color: Color = _get_child_ghost_color(child_index, child_body_names.size(), is_selected_child)
				var ghost_line_color: Color = ghost_color
				ghost_line_color.a = ghost_alpha
				var ghost_dot_outer: Color = Color(0.02, 0.02, 0.08, ghost_alpha * 0.9)
				var ghost_dot_inner: Color = ghost_color
				ghost_dot_inner.a = ghost_alpha
				var ghost_line_width: float = 2.8 if is_selected_child else 2.2

				var dash_i: int = 0
				while dash_i < child_draw_points.size() - 1:
					var dash_end: int = min(dash_i + ghost_dash_length, child_draw_points.size() - 1)
					for j in range(dash_i, dash_end):
						draw_line(child_draw_points[j], child_draw_points[j + 1], ghost_line_color, ghost_line_width)
					dash_i += ghost_dash_length + ghost_gap_length

				var moving_child_dot: Vector2 = child_draw_points[child_draw_points.size() - 1]
				draw_circle(moving_child_dot, 8.0 if is_selected_child else 7.0, ghost_dot_outer)
				draw_circle(moving_child_dot, 5.0 if is_selected_child else 4.0, ghost_dot_inner)

		var moon_intercept: bool = moon_entry_index >= 0 and moon_entry_index < visible_count

		if moon_intercept and focused_child_closest_approach_index >= 0 and focused_child_closest_approach_index < visible_count:
			var ca_color: Color = Color(1.0, 0.55, 0.15)
			if center_mode == CenterMode.MOON and copied_ca_valid and not drew_moon_orbit_markers:
				draw_circle(copied_ca_screen, 4.0, ca_color)
				_draw_marker_label(
					copied_ca_screen,
					"CA",
					ca_color,
					focused_child_screen,
					focused_child_ca_surface_distance,
					true
				)
			elif not currently_in_focused_child_dominance:
				if focused_child_closest_approach_index >= 0 and focused_child_closest_approach_index < main_visible_count and focused_child_closest_approach_index < cached_ship_source_points.size():
					var ca_screen: Vector2 = _to_screen(cached_ship_source_points[focused_child_closest_approach_index], center)
					draw_circle(ca_screen, 4.0, ca_color)
					_draw_marker_label(
						ca_screen,
						"CA",
						ca_color,
						focused_child_screen,
						focused_child_ca_surface_distance,
						true
					)

		if (
			not cached_ship_impact_found
			and not (center_mode == CenterMode.MOON and moon_entry_index >= 0 and moon_entry_index < visible_count)
			and solution.predicted_periapsis_index >= 0
			and solution.predicted_periapsis_index < main_visible_count
			and solution.predicted_periapsis_index < cached_ship_source_points.size()
		):
			var pe_point: Vector3 = cached_ship_source_points[solution.predicted_periapsis_index]
			var pe_screen: Vector2 = _to_screen(pe_point, center)
			var pe_proj_r: float = Vector2(pe_point.x, pe_point.z).length()
			var pe_hidden: bool = pe_proj_r < SimulationState.planet_radius and pe_point.y < 0.0

			if pe_hidden:
				var pe_dir: Vector2 = pe_screen - planet_screen
				if pe_dir.length_squared() < 0.0001:
					pe_dir = Vector2.RIGHT
				else:
					pe_dir = pe_dir.normalized()

				pe_screen = planet_screen + pe_dir * (planet_radius_px + 8.0)

			_draw_marker_square(pe_screen, 6.0, Color(0.892, 1.0, 0.35, 1.0))
			_draw_marker_label(
				pe_screen,
				"PE",
				Color(0.892, 1.0, 0.35),
				planet_screen,
				_compute_surface_distance_from_relative_point(pe_point, SimulationState.planet_radius),
				true
			)

		if not cached_ship_impact_found and not (center_mode == CenterMode.MOON and moon_entry_index >= 0 and moon_entry_index < visible_count) and solution.orbit_classification != "ESCAPE" and solution.orbit_classification != "IMPACT":
			if (
				solution.predicted_apoapsis_index >= 0
				and solution.predicted_apoapsis_index < main_visible_count
				and solution.predicted_apoapsis_index < cached_ship_source_points.size()
			):
				var ap_point: Vector3 = cached_ship_source_points[solution.predicted_apoapsis_index]
				var ap_screen: Vector2 = _to_screen(ap_point, center)
				var ap_proj_r: float = Vector2(ap_point.x, ap_point.z).length()
				var ap_hidden: bool = ap_proj_r < SimulationState.planet_radius and ap_point.y < 0.0

				if ap_hidden:
					var ap_dir: Vector2 = ap_screen - planet_screen
					if ap_dir.length_squared() < 0.0001:
						ap_dir = Vector2.LEFT
					else:
						ap_dir = ap_dir.normalized()

					ap_screen = planet_screen + ap_dir * (planet_radius_px + 8.0)

				_draw_marker_square(ap_screen, 6.0, Color(0.35, 0.75, 1.0))
				_draw_marker_label(
					ap_screen,
					"AP",
					Color(0.35, 0.75, 1.0),
					planet_screen,
					_compute_surface_distance_from_relative_point(ap_point, SimulationState.planet_radius),
					true
				)

		if cached_ship_impact_found and cached_ship_impact_index >= 0:
			if cached_ship_impact_index < main_visible_count and cached_ship_impact_index < cached_ship_source_points.size():
				var impact_screen: Vector2 = _to_screen(cached_ship_source_points[cached_ship_impact_index], center)
				_draw_impact_marker(impact_screen, 10.0, Color(1.0, 0.25, 0.25))
				_handle_impact_reached_on_draw()

		if is_timewarp_selection_available() and timewarp_selector.selection_index >= 0:
			var selected_point: Dictionary = _get_selected_screen_point(center, focused_child_rel_planet)
			if selected_point.get("valid", false):
				_draw_selection_box(selected_point["screen"], Color(1.0, 0.82, 0.25))

	_draw_timewarp_legend(rect_size, text_green)
	_draw_marker_distance_toggle_hint(rect_size, text_green)
	_draw_calculating_status_box(rect_size)
	_record_draw_state(rendered_visible_count, rendered_main_visible_count, rendered_ghost_alpha)
