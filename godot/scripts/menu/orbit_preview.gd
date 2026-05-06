extends Control
## 2D top-down preview of every assigned launch's initial orbit.
## Renders one ellipse per Launch (projected from RAAN+inclination
## onto the equatorial plane), plus a marker at the true-anomaly
## position so the operator sees where each unit will spawn.
##
## Normal view: two concentric arcs around each laser-armed unit's spawn
## marker — the inner arc is the Rayleigh range (100% damage zone) and
## the outer arc is MAX_RANGE_KM (~1% damage boundary).
##
## Coverage Analysis mode (toggled by the button in menu.gd): replaces
## the per-unit arcs with a rasterised DPS heatmap.  For every point in
## the equatorial-plane projection the heatmap shows the accumulated DPS
## a target there would receive from all laser-armed units over one full
## orbit, normalised so the hottest cell is always at full brightness.
##
## Pure visual feedback: no input handling, no edit affordances. The
## sliders mutate PlayerLoadout.launches; the menu calls refresh()
## after each change so this Control redraws.

const Launch = preload("res://scripts/launch.gd")
const EarthOrbit = preload("res://scripts/earth_orbit.gd")
const LaserWeapon = preload("res://scripts/weapons/laser_weapon.gd")
const UnitConfig = preload("res://scripts/unit_config.gd")
const UnitPart = preload("res://scripts/unit_part.gd")

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

# Internal resolution of the coverage heatmap grid (pixels × pixels).
# 80×80 is a good balance between visual smoothness and GDScript speed.
const COVERAGE_GRID: int = 80
# Number of true-anomaly samples around one orbit for the DPS integral.
const COVERAGE_ORBIT_SAMPLES: int = 72

var _coverage_mode: bool = false
var _coverage_texture: ImageTexture = null
var _coverage_dirty: bool = true
# Track the parameters the texture was built for so we can detect when
# a resize or orbit-parameter change requires a rebuild.
var _coverage_px_per_km: float = 0.0
var _coverage_rect_size: Vector2 = Vector2.ZERO


func _ready() -> void:
	custom_minimum_size = Vector2(280, 280)


# Recompute and redraw. Called by the menu after any slider value
# change. Cheap — just an invalidation; the actual geometry is laid
# out in _draw using the current Launch values.
func refresh() -> void:
	_coverage_dirty = true
	queue_redraw()


# Toggle between the normal laser-range-circle view and the DPS
# coverage heatmap overlay.  Called by the menu's Coverage Analysis
# button.
func set_coverage_mode(enabled: bool) -> void:
	_coverage_mode = enabled
	_coverage_dirty = true
	queue_redraw()


func _draw() -> void:
	var rect := get_rect()
	var center := rect.size * 0.5
	var span: float = minf(rect.size.x, rect.size.y) * 0.45
	if span <= 0.0:
		return

	# World scale: pick the largest apogee across the configured
	# launches so even a highly eccentric orbit fits inside the control.
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

	# Coverage heatmap sits between the planet fill and the orbit lines
	# so orbit ellipses and markers remain legible on top.
	if _coverage_mode:
		_draw_coverage_heatmap(center, rect.size, px_per_km)

	draw_arc(center, planet_r, 0.0, TAU, 64, COLOR_PLANET_RING, 1.0)

	# Per-launch orbit ellipses and spawn markers
	for i in range(PlayerLoadout.launches.size()):
		var launch: Launch = PlayerLoadout.launches[i]
		var color := ORBIT_COLORS[i % ORBIT_COLORS.size()]
		if not launch.has_unit():
			color = Color(color.r, color.g, color.b, 0.35)
		_draw_orbit(launch, center, px_per_km, color)

	# Laser range circles in normal view (skipped in coverage mode
	# because the heatmap already encodes the same information as a
	# spatial density integral rather than per-unit rings).
	if not _coverage_mode:
		_draw_laser_ranges(center, px_per_km)

	# Labels on top of everything so they're always readable
	for i in range(PlayerLoadout.launches.size()):
		var launch: Launch = PlayerLoadout.launches[i]
		var color := ORBIT_COLORS[i % ORBIT_COLORS.size()]
		if not launch.has_unit():
			color = Color(color.r, color.g, color.b, 0.35)
		_draw_label(launch, center, px_per_km, color)


# Sum of laser DPS (at zero range) for the unit assigned to this launch.
# Returns 0.0 when the launch is unassigned or has no laser weapons.
func _launch_laser_dps(launch: Launch) -> float:
	if not launch.has_unit():
		return 0.0
	var unit: UnitConfig = PlayerLoadout.unit_for_id(launch.unit_id)
	if unit == null:
		return 0.0
	var dps: float = 0.0
	for part_id: String in unit.weapon_part_ids:
		var part: UnitPart = UnitPart.get_by_id(part_id)
		if part.weapon_class == UnitPart.WCLASS_LASER:
			dps += LaserWeapon.base_damage_per_second_at_zero_range() * part.multiplier
	return dps


# Project a position on launch's orbit at true anomaly theta_rad to
# 2D screen coordinates.  Same perifocal→equatorial pipeline as
# _draw_orbit so that range-circle centres track the spawn markers
# exactly.
func _project_orbit_point(
	launch: Launch,
	theta_rad: float,
	center: Vector2,
	px_per_km: float,
) -> Vector2:
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
	var r_km: float = p_km / (1.0 + e * cos(theta_rad))
	var px: float = r_km * cos(theta_rad)
	var py: float = r_km * sin(theta_rad)
	var qx: float = px * cos_w - py * sin_w
	var qy: float = px * sin_w + py * cos_w
	var x: float = qx * cos_raan - qy * cos_i * sin_raan
	var y: float = qx * sin_raan + qy * cos_i * cos_raan
	return center + Vector2(x, -y) * px_per_km


# Draw near-field and far-field laser engagement arcs around each
# laser-armed unit's spawn marker.
#
#   Inner arc  — Rayleigh range (RAYLEIGH_RANGE_KM): beam is collimated
#                here; target takes 100% of radiated intensity.
#   Outer arc  — MAX_RANGE_KM (10 × Rayleigh): on-target intensity has
#                fallen to ~1%; hard engagement ceiling.
#
# Both arcs may extend beyond the control's visible area; Godot clips
# them to the Control's rect, showing only the portion inside the view.
func _draw_laser_ranges(center: Vector2, px_per_km: float) -> void:
	for i in range(PlayerLoadout.launches.size()):
		var launch: Launch = PlayerLoadout.launches[i]
		if _launch_laser_dps(launch) <= 0.0:
			continue
		var color := ORBIT_COLORS[i % ORBIT_COLORS.size()]
		var nu_rad: float = deg_to_rad(launch.true_anomaly_deg)
		var marker: Vector2 = _project_orbit_point(launch, nu_rad, center, px_per_km)
		var near_r: float = LaserWeapon.RAYLEIGH_RANGE_KM * px_per_km
		var far_r: float = LaserWeapon.MAX_RANGE_KM * px_per_km
		# Near-field circle: solid, medium opacity — the full-damage zone
		draw_arc(
			marker, near_r, 0.0, TAU, 64,
			Color(color.r, color.g, color.b, 0.55), 1.5,
		)
		# Far-field circle: dim, thin — the 1% damage / engagement ceiling
		draw_arc(
			marker, far_r, 0.0, TAU, 96,
			Color(color.r, color.g, color.b, 0.20), 1.0,
		)


# Rebuild the cached heatmap texture when inputs have changed, then
# blit it over the view at full control size.
func _draw_coverage_heatmap(
	center: Vector2, rect_size: Vector2, px_per_km: float,
) -> void:
	if (
		_coverage_dirty
		or _coverage_px_per_km != px_per_km
		or _coverage_rect_size != rect_size
	):
		_coverage_texture = _compute_coverage(center, rect_size, px_per_km)
		_coverage_dirty = false
		_coverage_px_per_km = px_per_km
		_coverage_rect_size = rect_size
	if _coverage_texture != null:
		draw_texture_rect(
			_coverage_texture, Rect2(Vector2.ZERO, rect_size), false,
		)


# Integrate laser DPS contributions across one full orbit for every
# laser-armed launch and rasterise the result to COVERAGE_GRID×COVERAGE_GRID.
#
# For each orbit sample of a laser satellite at projected screen position
# (sx, sy), every grid cell receives a contribution of:
#
#   laser_dps × range_factor(d_km)
#
# where d_km is the distance from (sx, sy) to the cell centre in km.
# range_factor = 1.0 inside RAYLEIGH_RANGE_KM, then (L₀/L)² — so it
# can be expressed as near_px² / d_px² entirely in pixel² space,
# avoiding all square-root calls in the hot loop.
#
# Returns null when no laser DPS is configured (nothing to draw).
func _compute_coverage(
	center: Vector2, rect_size: Vector2, px_per_km: float,
) -> ImageTexture:
	var G: int = COVERAGE_GRID
	var grid := PackedFloat32Array()
	grid.resize(G * G)
	grid.fill(0.0)

	# Pre-square the range thresholds so the inner loop is pure multiply/compare.
	var near_px: float = LaserWeapon.RAYLEIGH_RANGE_KM * px_per_km
	var far_px: float = LaserWeapon.MAX_RANGE_KM * px_per_km
	var near_px_sq: float = near_px * near_px
	var far_px_sq: float = far_px * far_px

	for launch: Launch in PlayerLoadout.launches:
		var laser_dps: float = _launch_laser_dps(launch)
		if laser_dps <= 0.0:
			continue

		# Pre-compute orbital rotation constants once per launch so the
		# inner orbit-sample loop is just trig + perifocal projection.
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

		for k in range(COVERAGE_ORBIT_SAMPLES):
			var theta: float = TAU * float(k) / float(COVERAGE_ORBIT_SAMPLES)
			var r_km: float = p_km / (1.0 + e * cos(theta))
			var opx: float = r_km * cos(theta)
			var opy: float = r_km * sin(theta)
			var qx: float = opx * cos_w - opy * sin_w
			var qy: float = opx * sin_w + opy * cos_w
			# Projected screen position of this orbit sample
			var sx: float = (
				center.x + (qx * cos_raan - qy * cos_i * sin_raan) * px_per_km
			)
			var sy: float = (
				center.y - (qx * sin_raan + qy * cos_i * cos_raan) * px_per_km
			)

			# Splat DPS contribution onto all grid cells within range.
			# Row-level early exit: if the entire row is outside MAX_RANGE_KM
			# in the y-axis alone we can skip it without checking columns.
			for gi in range(G):
				var cy: float = (float(gi) + 0.5) / float(G) * rect_size.y
				var d_gy: float = cy - sy
				var d_gy_sq: float = d_gy * d_gy
				if d_gy_sq >= far_px_sq:
					continue
				for gj in range(G):
					var cx: float = (float(gj) + 0.5) / float(G) * rect_size.x
					var d_gx: float = cx - sx
					var d_sq: float = d_gx * d_gx + d_gy_sq
					if d_sq >= far_px_sq:
						continue
					var rf: float
					if d_sq <= near_px_sq:
						rf = 1.0
					else:
						# (L₀/L)² expressed in pixel² — no sqrt required
						rf = near_px_sq / d_sq
					grid[gi * G + gj] += laser_dps * rf

	# Normalise so the peak cell is always full brightness regardless of
	# absolute DPS values.  This makes the display "relatively scaled to
	# however much DPS is currently being displayed" as intended.
	var max_val: float = 0.0
	for idx in range(G * G):
		if grid[idx] > max_val:
			max_val = grid[idx]
	if max_val <= 0.0:
		return null

	var inv_max: float = 1.0 / max_val
	var img := Image.create(G, G, false, Image.FORMAT_RGBA8)
	for gi in range(G):
		for gj in range(G):
			var t: float = grid[gi * G + gj] * inv_max
			img.set_pixel(gj, gi, _heatmap_color(t))

	return ImageTexture.create_from_image(img)


# Map a normalised coverage value [0, 1] to a fire-palette RGBA colour.
# Alpha is transparent at zero (planet / orbits visible) and climbs to
# ~0.82 at peak so the overlay never completely drowns the orbit lines.
func _heatmap_color(t: float) -> Color:
	if t <= 0.0:
		return Color(0.0, 0.0, 0.0, 0.0)
	var alpha: float = clampf(t * 2.5, 0.0, 0.82)
	if t < 0.35:
		var s: float = t / 0.35
		return Color(s * 0.75, 0.0, 0.0, alpha)
	elif t < 0.65:
		var s: float = (t - 0.35) / 0.30
		return Color(0.75 + s * 0.25, s * 0.45, 0.0, alpha)
	else:
		var s: float = (t - 0.65) / 0.35
		return Color(1.0, 0.45 + s * 0.55, s * 0.70, alpha)


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
