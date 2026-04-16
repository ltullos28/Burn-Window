extends Label3D

@export var trajectory_map_path: NodePath

var trajectory_map: Node

func _ready() -> void:
	trajectory_map = get_node_or_null(trajectory_map_path)

func _process(_delta: float) -> void:
	if trajectory_map == null:
		text = "FLIGHT COMPUTER\nNO LINK"
		return

	var status: String = _call_or_default("get_status_text", "NO DATA")
	var display_mode: String = _call_or_default("get_display_mode_text", "TRAJECTORY")
	var reference_body: String = _call_or_default("get_reference_body_text", "PLANET")
	var center_mode: String = _call_or_default("get_center_mode_text", "PLANET")
	var primary_body_label: String = _call_or_default("get_primary_body_label_text", "PLANET")
	var classification: String = _call_or_default("get_classification", "UNRESOLVED")

	var pe: float = _call_or_default("get_periapsis", -1.0)
	var ap: float = _call_or_default("get_apoapsis", -1.0)
	var ecc: float = _call_or_default("get_eccentricity", -1.0)
	var sma: float = _call_or_default("get_semi_major_axis", -1.0)
	var period: float = _call_or_default("get_orbital_period", -1.0)

	var ca_planet: float = _call_or_default("get_closest_approach_distance", -1.0)
	var tca_planet: float = _call_or_default("get_closest_approach_time", -1.0)

	var focused_child_label: String = _call_or_default("get_focused_child_label_text", "MOON")
	var ca_child: float = _call_or_default("get_focused_child_closest_approach_distance", _call_or_default("get_moon_closest_approach_distance", -1.0))
	var tca_child: float = _call_or_default("get_focused_child_closest_approach_time", _call_or_default("get_moon_closest_approach_time", -1.0))
	var vrel_child: float = _call_or_default("get_focused_child_relative_speed_at_closest_approach", _call_or_default("get_moon_relative_speed_at_closest_approach", -1.0))

	var alt: float = _call_or_default("get_ship_altitude", -1.0)
	var vel: float = _call_or_default("get_ship_speed", -1.0)
	var vrad: float = _call_or_default("get_ship_radial_velocity", -1.0)
	var vtan: float = _call_or_default("get_ship_tangential_velocity", -1.0)

	var zoom_value: float = _call_or_default("get_zoom_value", -1.0)

	text = _build_readout(
		status,
		display_mode,
		reference_body,
		center_mode,
		classification,
		pe,
		ap,
		ecc,
		sma,
		period,
		ca_planet,
		tca_planet,
		primary_body_label,
		focused_child_label,
		ca_child,
		tca_child,
		vrel_child,
		alt,
		vel,
		vrad,
		vtan,
		zoom_value
	)

func _call_or_default(method_name: String, default_value):
	if trajectory_map != null and trajectory_map.has_method(method_name):
		return trajectory_map.call(method_name)
	return default_value

func _fmt_nu(value: float) -> String:
	if value < 0.0:
		return "---"

	if abs(value) >= 1000.0:
		return "%.0f NU" % value
	if abs(value) >= 100.0:
		return "%.1f NU" % value
	return "%.2f NU" % value

func _fmt_speed(value: float) -> String:
	if value < 0.0:
		return "---"

	if abs(value) >= 100.0:
		return "%.1f NU/s" % value
	return "%.2f NU/s" % value

func _fmt_time(value: float) -> String:
	if value < 0.0:
		return "---"

	if value >= 1000.0:
		return "%.0f s" % value
	if value >= 100.0:
		return "%.1f s" % value
	return "%.2f s" % value

func _fmt_scalar(value: float) -> String:
	if value < 0.0:
		return "---"
	return "%.3f" % value

func _fmt_zoom(value: float) -> String:
	if value < 0.0:
		return "---"
	return "%.3f" % value

func _build_readout(
	status: String,
	display_mode: String,
	reference_body: String,
	center_mode: String,
	classification: String,
	pe: float,
	ap: float,
	ecc: float,
	sma: float,
	period: float,
	ca_planet: float,
	tca_planet: float,
	primary_body_label: String,
	focused_child_label: String,
	ca_child: float,
	tca_child: float,
	vrel_child: float,
	alt: float,
	vel: float,
	vrad: float,
	vtan: float,
	zoom_value: float
) -> String:
	var lines: PackedStringArray = []

	lines.append("FLIGHT COMPUTER")
	lines.append("----------------")
	lines.append("STATUS   " + status)
	lines.append("VIEW     " + display_mode)
	lines.append("REF      " + reference_body)
	lines.append("CENTER   " + center_mode)
	lines.append("")

	lines.append("ORBIT SOLUTION")
	lines.append("--------------")
	lines.append("TYPE     " + classification)
	lines.append("PE       " + _fmt_nu(pe))
	lines.append("AP       " + _fmt_nu(ap))
	lines.append("ECC      " + _fmt_scalar(ecc))
	lines.append("SMA      " + _fmt_nu(sma))
	lines.append("PERIOD   " + _fmt_time(period))
	lines.append("")

	lines.append(primary_body_label + " ENCOUNTER")
	lines.append("----------------")
	lines.append("CA       " + _fmt_nu(ca_planet))
	lines.append("TCA      " + _fmt_time(tca_planet))
	lines.append("")

	lines.append(focused_child_label + " ENCOUNTER")
	lines.append("--------------")
	lines.append("CA       " + _fmt_nu(ca_child))
	lines.append("TCA      " + _fmt_time(tca_child))
	lines.append("VREL     " + _fmt_speed(vrel_child))
	lines.append("")

	lines.append("SHIP STATE")
	lines.append("----------")
	lines.append("ALT      " + _fmt_nu(alt))
	lines.append("VEL      " + _fmt_speed(vel))
	lines.append("VRAD     " + _fmt_speed(vrad))
	lines.append("VTAN     " + _fmt_speed(vtan))
	lines.append("")

	lines.append("MAP")
	lines.append("---")
	lines.append("ZOOM     " + _fmt_zoom(zoom_value))

	return "\n".join(lines)
