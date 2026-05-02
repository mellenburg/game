extends Control
## 2D top-down preview of every assigned launch's initial orbit.
## Renders one ellipse per Launch (projected from RAAN+inclination
## onto the equatorial plane), plus a marker at the true-anomaly
## position so the operator sees where each unit will spawn.
##
## Pure visual feedback: no input handling, no edit affordances. The
## sliders mutate PlayerLoadout.launches; the menu calls refresh()
## after each change so this Control redraws.

const Launch = preload("res://scripts/launch.gd")
const EarthOrbit = preload("res://scripts/earth_orbit.gd")

const COLOR_BG := Color(0.04, 0.05, 0.07)
const COLOR_GRID := Color(0.18, 0.20, 0.24, 0.5)
const COLOR_PLANET := Color(0.18, 0.30, 0.42)
const COLOR_PLANET_RING := Color(0.55, 0.58, 0.64, 0.6)

# Per-row colour cycle so a handful of launches are visually
# distinguishable. Cycles modulo launch count; lengths beyond the
# table wrap.
const ORBIT_COLORS: Array[Color] = [
	Color(1.0, 0.706, 0.329),     # amber
	Color(0.40, 0.85, 0.55),      # green
	Color(0.55, 0.85, 0.95),      # cyan
	Color(0.95, 0.55, 0.85),      # pink
	Color(0.95, 0.95, 0.55),      # yellow
]


func _ready() -> void:
	custom_minimum_size = Vector2(280, 280)


# Recompute and redraw. Called by the menu after any slider value
# change. Cheap — just an invalidation; the actual geometry is laid
# out in _draw using the current Launch values.
func refresh() -> void:
	queue_redraw()


func _draw() -> void:
	var rect := get_rect()
	var center := rect.size * 0.5
	var span: float = minf(rect.size.x, rect.size.y) * 0.45
	if span <= 0.0:
		return

	# World scale: pick the largest apogee across the configured
	# launches so even a highly eccentric orbit fits inside the control.
	# Apogee = perigee · (1+e)/(1-e); collapses to perigee for ecc==0
	# so circular orbits scale identically to the pre-eccentricity
	# build. Min ceiling so an empty roster still renders sensibly.
	var max_world_km: float = EarthOrbit.EARTH_RADIUS_KM
	for launch: Launch in PlayerLoadout.launches:
		max_world_km = maxf(
			max_world_km,
			EarthOrbit.EARTH_RADIUS_KM + launch.apogee_altitude_km(),
		)
	max_world_km *= 1.10  # 10% padding so labels don't crop on the rim
	var px_per_km: float = span / max_world_km

	# Background fill
	draw_rect(Rect2(Vector2.ZERO, rect.size), COLOR_BG, true)

	# Equator + meridian crosshair
	draw_line(
		Vector2(0, center.y), Vector2(rect.size.x, center.y),
		COLOR_GRID, 1.0,
	)
	draw_line(
		Vector2(center.x, 0), Vector2(center.x, rect.size.y),
		COLOR_GRID, 1.0,
	)

	# Planet
	var planet_r: float = EarthOrbit.EARTH_RADIUS_KM * px_per_km
	draw_circle(center, planet_r, COLOR_PLANET)
	draw_arc(center, planet_r, 0.0, TAU, 64, COLOR_PLANET_RING, 1.0)

	# Per-launch orbits
	for i in range(PlayerLoadout.launches.size()):
		var launch: Launch = PlayerLoadout.launches[i]
		var color := ORBIT_COLORS[i % ORBIT_COLORS.size()]
		# Dim unassigned launches so the operator can see them but they
		# don't visually compete with the assigned rows that will
		# actually spawn.
		if not launch.has_unit():
			color = Color(color.r, color.g, color.b, 0.35)
		_draw_orbit(launch, center, px_per_km, color)
		_draw_label(launch, center, px_per_km, color)


# Project the launch's orbit (circular or elliptical) onto the screen
# plane. Position at true anomaly θ in the perifocal frame:
#   r(θ) = p / (1 + e·cos θ),   p = r_p · (1 + e)
#   x_pqw = r·cos θ,  y_pqw = r·sin θ
# Then rotate by argp in-plane, tilt by inc, and rotate by RAAN around
# z; we drop the z component for the top-down view. For e==0 and
# argp==0 this collapses to the prior circular projection bit-for-bit.
func _draw_orbit(
	launch: Launch, center: Vector2, px_per_km: float, color: Color
) -> void:
	var r_p_km: float = EarthOrbit.EARTH_RADIUS_KM + launch.altitude_km
	var e: float = clampf(launch.eccentricity, 0.0, 0.999)
	var p_km: float = r_p_km * (1.0 + e)
	var i_rad: float = deg_to_rad(launch.inclination_deg)
	var raan_rad: float = deg_to_rad(launch.raan_deg)
	var argp_rad: float = deg_to_rad(launch.argp_deg)
	var cos_raan: float = cos(raan_rad)
	var sin_raan: float = sin(raan_rad)
	var cos_i: float = cos(i_rad)
	var cos_w: float = cos(argp_rad)
	var sin_w: float = sin(argp_rad)

	const SEGMENTS: int = 96
	var points := PackedVector2Array()
	points.resize(SEGMENTS + 1)
	for k in range(SEGMENTS + 1):
		var theta: float = (TAU * float(k)) / float(SEGMENTS)
		var r_at: float = p_km / (1.0 + e * cos(theta))
		# Perifocal frame: perigee along +x_pqw.
		var px: float = r_at * cos(theta)
		var py: float = r_at * sin(theta)
		# Rotate by argp inside the orbital plane (line of nodes
		# perpendicular to perigee for non-zero argp).
		var qx: float = px * cos_w - py * sin_w
		var qy: float = px * sin_w + py * cos_w
		# Tilt by inclination (foreshorten the y-axis) and rotate by
		# RAAN around the z-axis. Z component is dropped for the
		# top-down projection.
		var x: float = qx * cos_raan - qy * cos_i * sin_raan
		var y: float = qx * sin_raan + qy * cos_i * cos_raan
		points[k] = center + Vector2(x, -y) * px_per_km
	draw_polyline(points, color, 1.6, true)

	# Spawn marker at the configured true anomaly. Same projection
	# pipeline; just one sample.
	var nu_rad: float = deg_to_rad(launch.true_anomaly_deg)
	var r_nu: float = p_km / (1.0 + e * cos(nu_rad))
	var px_nu: float = r_nu * cos(nu_rad)
	var py_nu: float = r_nu * sin(nu_rad)
	var qx_nu: float = px_nu * cos_w - py_nu * sin_w
	var qy_nu: float = px_nu * sin_w + py_nu * cos_w
	var marker_x: float = qx_nu * cos_raan - qy_nu * cos_i * sin_raan
	var marker_y: float = qx_nu * sin_raan + qy_nu * cos_i * cos_raan
	var marker_pos: Vector2 = (
		center + Vector2(marker_x, -marker_y) * px_per_km
	)
	draw_circle(marker_pos, 4.0, color)


# Draw the launch's name to the right of its spawn marker. Same
# projection pipeline as the spawn marker in _draw_orbit so the label
# tracks the dot exactly even for eccentric / argp-rotated orbits.
func _draw_label(
	launch: Launch,
	center: Vector2,
	px_per_km: float,
	color: Color,
) -> void:
	var r_p_km: float = EarthOrbit.EARTH_RADIUS_KM + launch.altitude_km
	var e: float = clampf(launch.eccentricity, 0.0, 0.999)
	var p_km: float = r_p_km * (1.0 + e)
	var i_rad: float = deg_to_rad(launch.inclination_deg)
	var raan_rad: float = deg_to_rad(launch.raan_deg)
	var argp_rad: float = deg_to_rad(launch.argp_deg)
	var nu_rad: float = deg_to_rad(launch.true_anomaly_deg)
	var r_nu: float = p_km / (1.0 + e * cos(nu_rad))
	var px_nu: float = r_nu * cos(nu_rad)
	var py_nu: float = r_nu * sin(nu_rad)
	var qx: float = px_nu * cos(argp_rad) - py_nu * sin(argp_rad)
	var qy: float = px_nu * sin(argp_rad) + py_nu * cos(argp_rad)
	var x: float = (
		qx * cos(raan_rad) - qy * cos(i_rad) * sin(raan_rad)
	)
	var y: float = (
		qx * sin(raan_rad) + qy * cos(i_rad) * cos(raan_rad)
	)
	var marker_pos: Vector2 = center + Vector2(x, -y) * px_per_km
	var font := get_theme_default_font()
	if font == null:
		return
	var text: String = launch.name
	if not launch.has_unit():
		text += " · (no unit)"
	draw_string(
		font, marker_pos + Vector2(8, 4),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, color,
	)
