extends Control
## 2D top-down preview of the per-unit initial orbits configured on the
## Orbital Ops tab. Renders one ellipse per UnitConfig (projected from
## RAAN+inclination onto the equatorial plane), plus a marker at the
## true-anomaly position so the operator sees where each unit will spawn.
##
## Pure visual feedback: no input handling, no edit affordances. The
## sliders mutate PlayerLoadout.units; the menu calls refresh() after
## each change so this Control redraws.

const UnitConfig = preload("res://scripts/unit_config.gd")
const EarthOrbit = preload("res://scripts/earth_orbit.gd")

const COLOR_BG := Color(0.04, 0.05, 0.07)
const COLOR_GRID := Color(0.18, 0.20, 0.24, 0.5)
const COLOR_PLANET := Color(0.18, 0.30, 0.42)
const COLOR_PLANET_RING := Color(0.55, 0.58, 0.64, 0.6)
const COLOR_ORBIT := Color(1.0, 0.706, 0.329, 0.85)
const COLOR_ORBIT_DIM := Color(0.55, 0.58, 0.64, 0.65)
const COLOR_MARKER := Color(1.0, 0.706, 0.329)
const COLOR_LABEL := Color(0.86, 0.88, 0.92)

# Per-unit colour cycle so the three default orbits are visually
# distinguishable. Cycled modulo unit count; lengths beyond the table
# wrap (the menu tops out at 3 units today).
const ORBIT_COLORS: Array[Color] = [
	Color(1.0, 0.706, 0.329),     # amber
	Color(0.40, 0.85, 0.55),      # green
	Color(0.55, 0.85, 0.95),      # cyan
]


func _ready() -> void:
	custom_minimum_size = Vector2(280, 280)


# Recompute and redraw. Called by the menu after any slider value
# change. Cheap — just an invalidation; the actual geometry is laid
# out in _draw using the current UnitConfig values.
func refresh() -> void:
	queue_redraw()


func _draw() -> void:
	var rect := get_rect()
	var center := rect.size * 0.5
	var span: float = minf(rect.size.x, rect.size.y) * 0.45
	if span <= 0.0:
		return

	# World scale: pick the largest (Earth radius + altitude) across
	# the configured units so the most distant orbit just fits in the
	# control's bounds. Min ceiling so an empty roster still renders
	# at a sensible scale.
	var max_world_km: float = EarthOrbit.EARTH_RADIUS_KM
	for unit in PlayerLoadout.units:
		max_world_km = maxf(
			max_world_km,
			EarthOrbit.EARTH_RADIUS_KM + unit.altitude_km,
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

	# Per-unit orbits
	for i in range(PlayerLoadout.units.size()):
		var unit: UnitConfig = PlayerLoadout.units[i]
		var color := ORBIT_COLORS[i % ORBIT_COLORS.size()]
		_draw_orbit(unit, center, px_per_km, color)
		_draw_label(unit, i, center, px_per_km, color)


# Project the unit's circular orbit onto the screen-plane:
#   r(θ) in 3D = R3z(Ω) · R1x(i) · [cos θ, sin θ, 0] · a
# Then drop the z component to render the on-plane footprint. RAAN
# rotates the line of nodes; inclination tilts the plane so the orbit
# foreshortens into an ellipse from the top-down view.
func _draw_orbit(
	unit: UnitConfig, center: Vector2, px_per_km: float, color: Color
) -> void:
	var a_km: float = EarthOrbit.EARTH_RADIUS_KM + unit.altitude_km
	var i_rad: float = deg_to_rad(unit.inclination_deg)
	var raan_rad: float = deg_to_rad(unit.raan_deg)
	var cos_raan: float = cos(raan_rad)
	var sin_raan: float = sin(raan_rad)
	var cos_i: float = cos(i_rad)

	const SEGMENTS: int = 64
	var points := PackedVector2Array()
	points.resize(SEGMENTS + 1)
	for k in range(SEGMENTS + 1):
		var theta: float = (TAU * float(k)) / float(SEGMENTS)
		var x_perifocal: float = cos(theta) * a_km
		var y_perifocal: float = sin(theta) * a_km
		# After inclination tilt + RAAN spin, the screen-plane (x,y)
		# components are:
		var x: float = (
			x_perifocal * cos_raan
			- y_perifocal * cos_i * sin_raan
		)
		var y: float = (
			x_perifocal * sin_raan
			+ y_perifocal * cos_i * cos_raan
		)
		# Screen y inverts so +y world points up on screen.
		points[k] = center + Vector2(x, -y) * px_per_km
	draw_polyline(points, color, 1.6, true)

	# Spawn marker at the configured true anomaly
	var nu_rad: float = deg_to_rad(unit.true_anomaly_deg)
	var x_perifocal_nu: float = cos(nu_rad) * a_km
	var y_perifocal_nu: float = sin(nu_rad) * a_km
	var marker_x: float = (
		x_perifocal_nu * cos_raan
		- y_perifocal_nu * cos_i * sin_raan
	)
	var marker_y: float = (
		x_perifocal_nu * sin_raan
		+ y_perifocal_nu * cos_i * cos_raan
	)
	var marker_pos: Vector2 = (
		center + Vector2(marker_x, -marker_y) * px_per_km
	)
	draw_circle(marker_pos, 4.0, color)


# Draw the unit's name to the right of its spawn marker.
func _draw_label(
	unit: UnitConfig,
	_i: int,
	center: Vector2,
	px_per_km: float,
	color: Color,
) -> void:
	var a_km: float = EarthOrbit.EARTH_RADIUS_KM + unit.altitude_km
	var i_rad: float = deg_to_rad(unit.inclination_deg)
	var raan_rad: float = deg_to_rad(unit.raan_deg)
	var nu_rad: float = deg_to_rad(unit.true_anomaly_deg)
	var x_perifocal: float = cos(nu_rad) * a_km
	var y_perifocal: float = sin(nu_rad) * a_km
	var x: float = (
		x_perifocal * cos(raan_rad)
		- y_perifocal * cos(i_rad) * sin(raan_rad)
	)
	var y: float = (
		x_perifocal * sin(raan_rad)
		+ y_perifocal * cos(i_rad) * cos(raan_rad)
	)
	var marker_pos: Vector2 = center + Vector2(x, -y) * px_per_km
	var font := get_theme_default_font()
	if font == null:
		return
	draw_string(
		font, marker_pos + Vector2(8, 4),
		unit.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, color,
	)
