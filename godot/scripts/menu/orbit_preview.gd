extends Control
## 2D top-down preview of every assigned launch's initial orbit.
## Renders one ellipse per Launch (projected from RAAN+inclination
## onto the equatorial plane), plus a marker at the true-anomaly
## position so the operator sees where each unit will spawn.
##
## Pure visual feedback: no input handling, no edit affordances. The
## sliders mutate PlayerLoadout.launches; the menu calls refresh()
## after each change so this Control redraws.
##
## Two display modes:
##   - Default: each laser-armed unit gets two range circles (Rayleigh
##     near-field at full damage, MAX_RANGE_KM far-field at ~1%) drawn
##     around its spawn marker.
##   - Coverage analysis: a heatmap of time-averaged potential laser
##     DPS over one full orbital period, summed across all assigned
##     laser units, normalised to the current peak so the colour scale
##     stays meaningful as the fleet's footprint shrinks or grows.

const Launch = preload("res://scripts/launch.gd")
const EarthOrbit = preload("res://scripts/earth_orbit.gd")
const LaserWeapon = preload("res://scripts/weapons/laser_weapon.gd")
const UnitConfig = preload("res://scripts/unit_config.gd")
const UnitPart = preload("res://scripts/unit_part.gd")

const COLOR_BG := Color(0.04, 0.05, 0.07)
const COLOR_GRID := Color(0.18, 0.20, 0.24, 0.5)
const COLOR_PLANET := Color(0.18, 0.30, 0.42)
const COLOR_PLANET_RING := Color(0.55, 0.58, 0.64, 0.6)

# Range-circle colours. Inner ring (full-damage Rayleigh range) is
# brighter and slightly thicker so it reads as the "kill zone"; outer
# ring (1% damage threshold) is dimmer to communicate "edge of useful
# fire" without overwhelming the orbit lines.
const COLOR_RANGE_INNER := Color(0.95, 0.45, 0.30, 0.85)
const COLOR_RANGE_OUTER := Color(0.95, 0.45, 0.30, 0.30)

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

# Coverage-analysis grid resolution. 80×80 = 6400 cells; with ~64
# orbital samples per laser unit and a handful of units this is
# well under a millisecond per refresh on a Chromebook (no per-frame
# allocation — refresh() only fires on slider events).
const COVERAGE_GRID: int = 80
# Mean-anomaly samples per orbit. 64 is enough resolution that even
# highly eccentric orbits (where most of the period is spent near
# apogee) produce a smooth heatmap.
const COVERAGE_SAMPLES: int = 64
# Newton-Raphson iterations for Kepler's equation. 8 converges to
# float precision for e < 0.95, well past the operator's slider cap.
const KEPLER_ITERATIONS: int = 8

var coverage_mode: bool = false


func _ready() -> void:
	custom_minimum_size = Vector2(280, 280)


# Recompute and redraw. Called by the menu after any slider value
# change. Cheap — just an invalidation; the actual geometry is laid
# out in _draw using the current Launch values.
func refresh() -> void:
	queue_redraw()


# Toggle the heatmap. Idempotent — a no-op when the value matches the
# current mode so the menu's button can call this unconditionally
# from its toggled signal without worrying about extra repaints.
func set_coverage_mode(enabled: bool) -> void:
	if coverage_mode == enabled:
		return
	coverage_mode = enabled
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

	# Heatmap goes underneath everything else so the orbit lines and
	# spawn markers stay legible on top of it.
	if coverage_mode:
		_draw_coverage_heatmap(rect, center, px_per_km)

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
		# Range circles only render in the default mode — in coverage
		# mode the heatmap already encodes the same information, and
		# stacked rings on top of a heatmap is just visual noise.
		if not coverage_mode:
			_draw_laser_range(launch, center, px_per_km)
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
	var marker_pos: Vector2 = _project_at_true_anomaly(
		launch, deg_to_rad(launch.true_anomaly_deg),
		center, px_per_km,
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
	var marker_pos: Vector2 = _project_at_true_anomaly(
		launch, deg_to_rad(launch.true_anomaly_deg),
		center, px_per_km,
	)
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


# Project a single (true_anomaly) sample on the launch's orbit into
# screen space. Shared by the spawn marker, the label position, and
# the heatmap sampling loop so all three stay perfectly aligned even
# when eccentricity / argp rotate the perigee off the line of nodes.
func _project_at_true_anomaly(
	launch: Launch,
	nu_rad: float,
	center: Vector2,
	px_per_km: float,
) -> Vector2:
	var r_p_km: float = EarthOrbit.EARTH_RADIUS_KM + launch.altitude_km
	var e: float = clampf(launch.eccentricity, 0.0, 0.999)
	var p_km: float = r_p_km * (1.0 + e)
	var r_nu: float = p_km / (1.0 + e * cos(nu_rad))
	var px: float = r_nu * cos(nu_rad)
	var py: float = r_nu * sin(nu_rad)
	var argp_rad: float = deg_to_rad(launch.argp_deg)
	var qx: float = px * cos(argp_rad) - py * sin(argp_rad)
	var qy: float = px * sin(argp_rad) + py * cos(argp_rad)
	var i_rad: float = deg_to_rad(launch.inclination_deg)
	var raan_rad: float = deg_to_rad(launch.raan_deg)
	var x: float = qx * cos(raan_rad) - qy * cos(i_rad) * sin(raan_rad)
	var y: float = qx * sin(raan_rad) + qy * cos(i_rad) * cos(raan_rad)
	return center + Vector2(x, -y) * px_per_km


# Solve Kepler's equation E - e·sin(E) = M for the eccentric anomaly.
# Newton-Raphson with E_0 = M; converges to float precision in well
# under KEPLER_ITERATIONS for e < ~0.95. Pure helper — no Satellite /
# SceneTree dependency.
func _kepler_solve(mean_anomaly: float, e: float) -> float:
	var ea: float = mean_anomaly
	for _i in range(KEPLER_ITERATIONS):
		var f: float = ea - e * sin(ea) - mean_anomaly
		var fp: float = 1.0 - e * cos(ea)
		if fp == 0.0:
			break
		ea -= f / fp
	return ea


# Convert eccentric anomaly to true anomaly using the half-angle form,
# which is numerically stable through the full ν ∈ [0, 2π] range.
func _eccentric_to_true(ea: float, e: float) -> float:
	var s: float = sqrt(1.0 + e) * sin(ea * 0.5)
	var c: float = sqrt(1.0 - e) * cos(ea * 0.5)
	return 2.0 * atan2(s, c)


# Range-circle pair (Rayleigh near-field, max-range far-field) drawn
# around the spawn marker for any launch whose assigned unit has at
# least one laser. Skipped silently for unassigned launches and for
# laser-less loadouts so the preview stays uncluttered when those
# launches are using railguns or no weapon at all.
func _draw_laser_range(
	launch: Launch, center: Vector2, px_per_km: float
) -> void:
	if not launch.has_unit():
		return
	if not _launch_has_laser(launch):
		return
	var marker_pos: Vector2 = _project_at_true_anomaly(
		launch, deg_to_rad(launch.true_anomaly_deg),
		center, px_per_km,
	)
	var inner_r: float = LaserWeapon.RAYLEIGH_RANGE_KM * px_per_km
	var outer_r: float = LaserWeapon.MAX_RANGE_KM * px_per_km
	# draw_arc with a high segment count keeps the rings smooth at
	# preview-tab resolutions without the per-frame mesh allocations
	# the in-world RangeCircle takes pains to avoid (this control
	# only repaints on slider events, not on a physics tick).
	draw_arc(marker_pos, outer_r, 0.0, TAU, 96, COLOR_RANGE_OUTER, 1.0)
	draw_arc(marker_pos, inner_r, 0.0, TAU, 96, COLOR_RANGE_INNER, 1.4)


# True iff the launch's assigned unit has at least one laser slot
# filled. Read straight off the UnitConfig's weapon_part_ids — no
# need to materialise a full summary_stats() dictionary just to count
# lasers.
func _launch_has_laser(launch: Launch) -> bool:
	var unit: UnitConfig = PlayerLoadout.unit_for_id(launch.unit_id)
	if unit == null:
		return false
	for part_id in unit.weapon_part_ids:
		if UnitPart.get_by_id(part_id).weapon_class == UnitPart.WCLASS_LASER:
			return true
	return false


# Per-launch zero-range laser DPS, summed across the unit's filled
# laser slots and scaled by each part's tier multiplier so an Elite-
# tier loadout shows up brighter on the heatmap than a Default one.
# Returns 0.0 for unassigned / laser-less launches so the heatmap
# loop can blindly call this without a guard.
func _launch_laser_dps(launch: Launch) -> float:
	var unit: UnitConfig = PlayerLoadout.unit_for_id(launch.unit_id)
	if unit == null:
		return 0.0
	var dps: float = 0.0
	var base: float = LaserWeapon.base_damage_per_second_at_zero_range()
	for part_id in unit.weapon_part_ids:
		var part := UnitPart.get_by_id(part_id)
		if part.weapon_class == UnitPart.WCLASS_LASER:
			dps += base * part.multiplier
	return dps


# Time-averaged potential-DPS heatmap. For each laser-armed launch we
# sample COVERAGE_SAMPLES positions at equal mean-anomaly intervals
# (which are equal time intervals — Kepler's M is linear in t), then
# at every grid cell within MAX_RANGE_KM we accumulate
#   dps · range_factor(distance)
# averaged over the orbit. Final values are normalised to the peak
# across the grid so the colour scale always stretches across the
# meaningful dynamic range; raising every laser's range proportionally
# brightens the whole map but the relative shape stays stable.
func _draw_coverage_heatmap(
	rect: Rect2, center: Vector2, px_per_km: float
) -> void:
	if px_per_km <= 0.0:
		return
	var grid := PackedFloat32Array()
	grid.resize(COVERAGE_GRID * COVERAGE_GRID)
	var max_dps: float = 0.0
	var any_laser: bool = false
	var cell_w: float = rect.size.x / float(COVERAGE_GRID)
	var cell_h: float = rect.size.y / float(COVERAGE_GRID)

	for launch: Launch in PlayerLoadout.launches:
		if not _launch_has_laser(launch):
			continue
		any_laser = true
		var dps: float = _launch_laser_dps(launch)
		if dps <= 0.0:
			continue
		var e: float = clampf(launch.eccentricity, 0.0, 0.999)
		# Sample positions equally spaced in mean anomaly (i.e. time).
		# Pre-project all samples to screen space once so the inner cell
		# loop just does a 2D distance per (sample, cell) pair.
		var sample_pts := PackedVector2Array()
		sample_pts.resize(COVERAGE_SAMPLES)
		for s in range(COVERAGE_SAMPLES):
			var m: float = TAU * float(s) / float(COVERAGE_SAMPLES)
			var ea: float = _kepler_solve(m, e)
			var nu: float = _eccentric_to_true(ea, e)
			sample_pts[s] = _project_at_true_anomaly(
				launch, nu, center, px_per_km,
			)
		var max_range_px: float = LaserWeapon.MAX_RANGE_KM * px_per_km
		var inv_samples: float = 1.0 / float(COVERAGE_SAMPLES)
		for s in range(COVERAGE_SAMPLES):
			var sp: Vector2 = sample_pts[s]
			# Cell-index window: only touch cells whose centre could
			# possibly land inside the laser's MAX range. Saves the
			# range_factor() call on the vast majority of the grid.
			var cx_min: int = int(floor((sp.x - max_range_px) / cell_w))
			var cx_max: int = int(floor((sp.x + max_range_px) / cell_w))
			var cy_min: int = int(floor((sp.y - max_range_px) / cell_h))
			var cy_max: int = int(floor((sp.y + max_range_px) / cell_h))
			cx_min = max(cx_min, 0)
			cy_min = max(cy_min, 0)
			cx_max = min(cx_max, COVERAGE_GRID - 1)
			cy_max = min(cy_max, COVERAGE_GRID - 1)
			for cy in range(cy_min, cy_max + 1):
				var cell_centre_y: float = (float(cy) + 0.5) * cell_h
				for cx in range(cx_min, cx_max + 1):
					var cell_centre_x: float = (float(cx) + 0.5) * cell_w
					var dx: float = cell_centre_x - sp.x
					var dy: float = cell_centre_y - sp.y
					var dist_px: float = sqrt(dx * dx + dy * dy)
					var dist_km: float = dist_px / px_per_km
					var rf: float = LaserWeapon.range_factor(dist_km)
					if rf <= 0.0:
						continue
					var idx: int = cy * COVERAGE_GRID + cx
					grid[idx] += dps * rf * inv_samples

	if not any_laser:
		_draw_coverage_legend(rect, 0.0, false)
		return
	for i in range(grid.size()):
		var v: float = grid[i]
		if v > max_dps:
			max_dps = v
	if max_dps <= 0.0:
		_draw_coverage_legend(rect, 0.0, true)
		return

	var inv_max: float = 1.0 / max_dps
	for cy in range(COVERAGE_GRID):
		for cx in range(COVERAGE_GRID):
			var v: float = grid[cy * COVERAGE_GRID + cx]
			if v <= 0.0:
				continue
			var t: float = clampf(v * inv_max, 0.0, 1.0)
			var col: Color = _heat_color(t)
			draw_rect(
				Rect2(
					Vector2(float(cx) * cell_w, float(cy) * cell_h),
					Vector2(cell_w + 1.0, cell_h + 1.0),  # +1 closes seams
				),
				col, true,
			)
	_draw_coverage_legend(rect, max_dps, true)


# Two-stop heat ramp: black → deep red → orange → yellow → white.
# Alpha climbs with intensity so the planet / orbit overlays stay
# visible through the dim regions of the map.
func _heat_color(t: float) -> Color:
	var r: float = clampf(t * 1.6, 0.0, 1.0)
	var g: float = clampf(t * 1.6 - 0.5, 0.0, 1.0)
	var b: float = clampf(t * 1.6 - 0.9, 0.0, 1.0)
	var a: float = 0.15 + 0.55 * t
	return Color(r, g, b, a)


# Top-left readout in coverage mode — labels what the operator's
# looking at and prints the current peak DPS so they can compare two
# loadouts quantitatively, not just by colour.
func _draw_coverage_legend(
	rect: Rect2, peak_dps: float, has_lasers: bool
) -> void:
	var font := get_theme_default_font()
	if font == null:
		return
	var origin := Vector2(8, 16)
	draw_string(
		font, origin,
		"Coverage Analysis (avg DPS over one orbit)",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.95, 0.95, 0.95, 0.9),
	)
	var second: String
	if not has_lasers:
		second = "No assigned lasers — assign a laser unit to populate."
	else:
		second = "peak ≈ %.1f DPS  ·  white = peak, black = 0" % peak_dps
	draw_string(
		font, origin + Vector2(0, 14),
		second,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.85, 0.85, 0.85, 0.8),
	)
