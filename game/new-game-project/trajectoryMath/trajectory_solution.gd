class_name TrajectorySolution
extends RefCounted

var ship_points: Array[Vector3] = []
var ship_velocities: Array[Vector3] = []

var closest_approach_distance: float = -1.0
var closest_approach_time: float = -1.0

var orbit_classification: String = "UNRESOLVED"
var periapsis_distance: float = -1.0
var apoapsis_distance: float = -1.0
var eccentricity_value: float = -1.0
var semi_major_axis_value: float = -1.0
var orbital_period_value: float = -1.0

var is_bound_orbit: bool = false
var specific_energy: float = 0.0

var predicted_periapsis_distance: float = -1.0
var predicted_apoapsis_distance: float = -1.0
var predicted_periapsis_time: float = -1.0
var predicted_apoapsis_time: float = -1.0
var predicted_periapsis_index: int = -1
var predicted_apoapsis_index: int = -1

var prediction_steps_used: int = 0
var prediction_duration_used: float = 0.0
var display_steps_used: int = 0
var display_duration_used: float = 0.0

var body_relative_points: Dictionary = {}
var body_dominance_masks: Dictionary = {}
var body_closest_approaches: Dictionary = {}
var body_encounters: Dictionary = {}

func set_body_relative_points(body_name: StringName, points: Array[Vector3]) -> void:
	var body_key: String = String(body_name)
	var stored_points: Array[Vector3] = points.duplicate()
	body_relative_points[body_key] = stored_points
	var encounter: Dictionary = _get_or_create_body_encounter(body_name)
	encounter["relative_points"] = stored_points
	body_encounters[body_key] = encounter

func get_body_relative_points(body_name: StringName) -> Array[Vector3]:
	var points: Array[Vector3] = body_relative_points.get(String(body_name), [])
	return points.duplicate()

func set_body_dominance_mask(body_name: StringName, dominance: Array[bool]) -> void:
	var body_key: String = String(body_name)
	var stored_dominance: Array[bool] = dominance.duplicate()
	body_dominance_masks[body_key] = stored_dominance
	var encounter: Dictionary = _get_or_create_body_encounter(body_name)
	encounter["dominance_mask"] = stored_dominance
	body_encounters[body_key] = encounter

func get_body_dominance_mask(body_name: StringName) -> Array[bool]:
	var dominance: Array[bool] = body_dominance_masks.get(String(body_name), [])
	return dominance.duplicate()

func set_body_closest_approach(
	body_name: StringName,
	distance: float,
	time: float,
	relative_speed: float,
	index: int
) -> void:
	body_closest_approaches[String(body_name)] = {
		"distance": distance,
		"time": time,
		"relative_speed": relative_speed,
		"index": index,
	}
	var encounter: Dictionary = _get_or_create_body_encounter(body_name)
	encounter["closest_approach"] = {
		"distance": distance,
		"time": time,
		"relative_speed": relative_speed,
		"index": index,
	}
	body_encounters[String(body_name)] = encounter

func get_body_closest_approach(body_name: StringName) -> Dictionary:
	return body_closest_approaches.get(String(body_name), {
		"distance": -1.0,
		"time": -1.0,
		"relative_speed": -1.0,
		"index": -1,
	})

func set_body_parent_name(body_name: StringName, parent_body_name: StringName) -> void:
	var encounter: Dictionary = _get_or_create_body_encounter(body_name)
	encounter["parent_body_name"] = parent_body_name
	body_encounters[String(body_name)] = encounter

func get_body_encounter(body_name: StringName) -> Dictionary:
	var encounter: Dictionary = body_encounters.get(String(body_name), {}).duplicate(true)
	if encounter.is_empty():
		encounter = _build_default_body_encounter(body_name)
	if not encounter.has("body_name"):
		encounter["body_name"] = body_name
	return encounter

func set_body_encounter_details(
	body_name: StringName,
	local_segment: Dictionary,
	markers: Dictionary,
	impact: Dictionary,
	state: String
) -> void:
	var encounter: Dictionary = _get_or_create_body_encounter(body_name)
	encounter["local_segment"] = local_segment.duplicate(true)
	encounter["markers"] = markers.duplicate(true)
	encounter["impact"] = impact.duplicate(true)
	encounter["state"] = state
	body_encounters[String(body_name)] = encounter

func _get_or_create_body_encounter(body_name: StringName) -> Dictionary:
	var body_key: String = String(body_name)
	var encounter: Dictionary = body_encounters.get(body_key, {})
	if encounter.is_empty():
		encounter = _build_default_body_encounter(body_name)
		body_encounters[body_key] = encounter
	return encounter

func _build_default_body_encounter(body_name: StringName) -> Dictionary:
	return {
		"body_name": body_name,
		"parent_body_name": &"",
		"relative_points": [],
		"dominance_mask": [],
		"closest_approach": {
			"distance": -1.0,
			"time": -1.0,
			"relative_speed": -1.0,
			"index": -1,
		},
		"local_segment": {
			"entry_index": -1,
			"exit_index": -1,
			"points": [],
			"source_indices": [],
		},
		"markers": {
			"local_ca_index": -1,
			"local_pe_index": -1,
			"local_ap_index": -1,
			"show_local_ca_marker": false,
			"show_escape_marker": false,
			"escape_marker_local_index": -1,
		},
		"impact": {
			"found": false,
			"index": -1,
			"source_index": -1,
		},
		"state": "NONE",
	}
