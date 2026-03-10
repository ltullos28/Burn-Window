extends Label3D

@export var trajectory_map_path: NodePath

var trajectory_map: Node

func _ready() -> void:
	trajectory_map = get_node_or_null(trajectory_map_path)

func _process(_delta: float) -> void:
	if trajectory_map == null:
		text = "NO DATA"
		return

	var status: String = "NO DATA"
	var classification: String = "UNRESOLVED"
	var ca: float = 0.0
	var tca: float = 0.0
	var pe: float = -1.0
	var ap: float = -1.0
	var zoom_value: float = 0.0

	if trajectory_map.has_method("get_status_text"):
		status = trajectory_map.get_status_text()

	if trajectory_map.has_method("get_classification"):
		classification = trajectory_map.get_classification()

	if trajectory_map.has_method("get_closest_approach_distance"):
		ca = trajectory_map.get_closest_approach_distance()

	if trajectory_map.has_method("get_closest_approach_time"):
		tca = trajectory_map.get_closest_approach_time()

	if trajectory_map.has_method("get_periapsis"):
		pe = trajectory_map.get_periapsis()

	if trajectory_map.has_method("get_apoapsis"):
		ap = trajectory_map.get_apoapsis()

	if trajectory_map.has_method("get_zoom_value"):
		zoom_value = trajectory_map.get_zoom_value()

	text = ""
	text += "FLIGHT SOLUTION\n"
	text += "STATUS: %s\n" % status
	text += "CLASS: %s\n" % classification
	text += "CA: %.2f\n" % ca
	text += "TCA: %.1fs\n" % tca

	if pe >= 0.0:
		text += "PE: %.2f\n" % pe
	else:
		text += "PE: ---\n"

	if ap >= 0.0:
		text += "AP: %.2f\n" % ap
	else:
		text += "AP: ---\n"

	text += "ZOOM: %.2f" % zoom_value
