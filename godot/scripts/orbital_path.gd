class_name OrbitalPath
extends MeshInstance3D
## Static orbit path renderer. Builds a single ArrayMesh once and rewrites
## its vertex buffer in place when the orbit changes — avoids the per-frame
## ImmediateMesh / StandardMaterial3D allocation that crashed the previous
## port after ~1 minute.
##
## The ribbon is rendered as a billboarded triangle strip: each of the N
## base ring points expands to two vertices (left / right side), and a
## custom shader offsets them perpendicular to the line direction in
## screen space so width is uniform pixels regardless of camera zoom.
## Width and color (with alpha) are ShaderMaterial uniforms so the
## owning Satellite can drive thickness from initial HP and tint from
## impact-proximity without ever rebuilding geometry.

const MassCenterOrbit = preload("res://scripts/mass_center_orbit.gd")
const POINTS: int = 360
const SCENE_SCALE: float = 1.0 / 1000.0  # km -> scene units
const _LINE_SHADER: Shader = preload("res://shaders/orbit_line.gdshader")

var _array_mesh: ArrayMesh
var _material: ShaderMaterial
# Base ring points in scene units. One Vector3 per ring; the ribbon's
# two-sided expansion happens at upload time.
var _points: PackedVector3Array
# Expanded ribbon buffers, cached across uploads. Asteroid / spiral
# trajectories re-upload every orbit-render tick, and allocating three
# fresh Packed arrays per body per tick is measurable GC pressure in a
# 250-body wave — resize-in-place instead.
var _verts: PackedVector3Array
var _normals: PackedVector3Array
var _uvs: PackedVector2Array
var _last_signature := Vector4(NAN, NAN, NAN, NAN)
var _last_inc := NAN
var _last_argp := NAN

# Public uniforms — mirrored to the ShaderMaterial via setters so a
# caller can just write `path.color = ...` and the GPU sees it next
# frame without touching geometry.
var color := Color.BLUE:
	set(v):
		if v == color:
			return
		color = v
		if _material != null:
			_material.set_shader_parameter("line_color", v)
var line_width_px: float = 1.5:
	set(v):
		var clamped: float = maxf(v, 0.1)
		if absf(clamped - line_width_px) < 1.0e-3:
			return
		line_width_px = clamped
		if _material != null:
			_material.set_shader_parameter("line_width_px", clamped)


func _ready() -> void:
	_array_mesh = ArrayMesh.new()
	mesh = _array_mesh

	_material = ShaderMaterial.new()
	_material.shader = _LINE_SHADER
	_material.set_shader_parameter("line_color", color)
	_material.set_shader_parameter("line_width_px", line_width_px)
	material_override = _material

	_points = PackedVector3Array()
	_points.resize(POINTS + 1)


## Recompute orbit geometry only when elements have actually changed past a
## small tolerance, then upload the vertex buffer to the cached ArrayMesh.
func update_orbit(orbit: MassCenterOrbit) -> void:
	if not orbit.is_state_valid():
		_clear_surfaces()
		return
	if not is_finite(orbit.a) or not is_finite(orbit.ecc) or orbit.a <= 0.0:
		_clear_surfaces()
		return

	var sig := Vector4(orbit.a, orbit.ecc, orbit.raan, orbit.inc)
	# Skip rebuild if nothing meaningful changed. Color / width changes
	# are uniform-only and don't invalidate the cached geometry.
	if (
		_signature_close(sig, _last_signature)
		and _angle_close(orbit.argp, _last_argp)
		and _angle_close(orbit.inc, _last_inc)
		and _array_mesh.get_surface_count() > 0
	):
		return

	_compute_points(orbit)
	_upload_surface()

	_last_signature = sig
	_last_argp = orbit.argp
	_last_inc = orbit.inc


## Build orbit points in the perifocal (PQW) frame and rotate into ECI.
## Uses eccentric anomaly so points are evenly distributed around the
## ellipse — the previous port chained four separate Transform3Ds and did
## a Vector4 helper to recover the same geometry.
func _compute_points(orbit: MassCenterOrbit) -> void:
	var a := orbit.a
	var b := orbit.b
	var e := orbit.ecc

	# Perifocal-to-ECI rotation (Vallado eq. 3-29, Z-up celestial frame).
	var co := cos(orbit.raan); var so := sin(orbit.raan)
	var ci := cos(orbit.inc); var si := sin(orbit.inc)
	var cw := cos(orbit.argp); var sw := sin(orbit.argp)

	var pqw_x := Vector3(co * cw - so * sw * ci,  so * cw + co * sw * ci,  sw * si)
	var pqw_y := Vector3(-co * sw - so * cw * ci, -so * sw + co * cw * ci, cw * si)

	if _points.size() != POINTS + 1:
		_points.resize(POINTS + 1)
	for i in range(POINTS + 1):
		var ang := TAU * float(i % POINTS) / float(POINTS)
		var p := a * (cos(ang) - e)
		var q := b * sin(ang)
		_points[i] = (pqw_x * p + pqw_y * q) * SCENE_SCALE


## Render the inbound arc of a sub-orbital trajectory: from the body's
## current true anomaly forward in motion until the orbit dips below
## Earth's surface. Unlike update_orbit, the line truncates at the
## impact point — the segment that would tunnel through the planet is
## omitted, so the visual matches the gameplay rule (asteroids exit
## play on ground contact). Caller must keep `color` in sync; we don't
## cache anything here because the body's nu changes every tick.
func update_trajectory(orbit: MassCenterOrbit) -> void:
	if not orbit.is_state_valid():
		_clear_surfaces()
		return
	var e := orbit.ecc
	var p_slr := orbit.p_slr
	if not is_finite(e) or not is_finite(p_slr) or p_slr <= 0.0 or e <= 0.0:
		_clear_surfaces()
		return
	# Impact-crossing true anomaly: r(nu) = p_slr / (1 + e·cos(nu)) = R_impact.
	# Asteroid bodies are terminated at the ablation floor (safe_alt − 90 km,
	# 60 km for Earth) rather than the physical surface, so the trajectory arc
	# ends there instead of tunnelling through the planet.
	var impact_r: float = (
		MassCenterOrbit.BODY_RADIUS_KM + maxf(MassCenterOrbit.SAFE_ORBIT_ALT_KM - 90.0, 0.0)
	)
	var cos_nu_surf := (p_slr / impact_r - 1.0) / e
	if cos_nu_surf > 1.0 or cos_nu_surf < -1.0:
		# Periapsis is above the surface — not an asteroid trajectory.
		# Fall through to the regular orbit renderer.
		_clear_surfaces()
		return
	var nu_surf := acos(clampf(cos_nu_surf, -1.0, 1.0))
	# Body is inbound iff r·v < 0 (radius decreasing). The descending
	# branch has nu in (-π, 0), and we want the surface crossing also
	# on that branch, so nu_target = -nu_surf.
	var r_dot_v := orbit.r.dot(orbit.v)
	if r_dot_v >= 0.0:
		_clear_surfaces()
		return
	var nu0: float = orbit.nu
	# orbit.nu is wrapped to (-π, π]; the inbound branch crosses the
	# wrap right at apoapsis. Force nu0 negative so the lerp toward
	# nu_target sweeps the actual descending arc rather than going the
	# long way around.
	if nu0 > 0.0:
		nu0 -= TAU
	var nu_target: float = -nu_surf
	if nu_target <= nu0:
		# Body is already past the surface crossing on the descending
		# branch — should have been killed; render nothing.
		_clear_surfaces()
		return

	# Same perifocal-to-ECI rotation as _compute_points.
	var co := cos(orbit.raan); var so := sin(orbit.raan)
	var ci := cos(orbit.inc); var si := sin(orbit.inc)
	var cw := cos(orbit.argp); var sw := sin(orbit.argp)
	var pqw_x := Vector3(co * cw - so * sw * ci,  so * cw + co * sw * ci,  sw * si)
	var pqw_y := Vector3(-co * sw - so * cw * ci, -so * sw + co * cw * ci, cw * si)

	if _points.size() != POINTS + 1:
		_points.resize(POINTS + 1)
	for i in range(POINTS + 1):
		var t := float(i) / float(POINTS)
		var nu := lerpf(nu0, nu_target, t)
		var r_at := p_slr / (1.0 + e * cos(nu))
		var p_local := r_at * cos(nu)
		var q_local := r_at * sin(nu)
		_points[i] = (pqw_x * p_local + pqw_y * q_local) * SCENE_SCALE

	_upload_surface()
	# Trajectory geometry changes every tick (nu0 sweeps); invalidate
	# the orbit-cache signature so a later switch back to update_orbit
	# triggers a rebuild instead of trusting stale cached state.
	_last_signature = Vector4(NAN, NAN, NAN, NAN)


## Render a hyperbolic escape trajectory from the body's current position
## out to DEFLECT_BOUNDARY_KM (50 000 km). Used for deflected asteroid
## fragments — bodies on unbound orbits that won't return to Earth.
## The arc sweeps from the current true anomaly forward to the angle
## corresponding to the boundary distance, stopping just short of the
## hyperbolic asymptote if the boundary exceeds that limit.
## Caller must keep `color` in sync (set once via the line_color setter).
const DEFLECT_BOUNDARY_KM: float = 50000.0

func update_escape_trajectory(orbit: MassCenterOrbit) -> void:
	if not orbit.is_state_valid():
		_clear_surfaces()
		return
	var e := orbit.ecc
	var p_slr := orbit.p_slr
	if not is_finite(e) or not is_finite(p_slr) or p_slr <= 0.0 or e < 1.0:
		_clear_surfaces()
		return

	# Asymptotic limit: r → ∞ as nu → ±nu_max = acos(-1/e).
	var nu_max: float = acos(clampf(-1.0 / e, -1.0, 1.0))

	# Angle at which r reaches the deflection boundary.
	# r(nu) = p / (1 + e·cos(nu)) = DEFLECT_BOUNDARY_KM
	# cos(nu_end) = (p/R - 1) / e
	var cos_nu_end: float = (p_slr / DEFLECT_BOUNDARY_KM - 1.0) / e
	var nu_end: float
	if cos_nu_end <= -1.0:
		# Boundary beyond the asymptote — stop 2% short of it.
		nu_end = nu_max * 0.98
	else:
		nu_end = acos(clampf(cos_nu_end, -1.0, 1.0))

	# Clamp current nu to the valid open interval (-nu_max, nu_max).
	var nu0: float = clampf(orbit.nu, -nu_max * 0.9999, nu_max * 0.9999)
	if nu0 >= nu_end:
		_clear_surfaces()
		return

	var co := cos(orbit.raan); var so := sin(orbit.raan)
	var ci := cos(orbit.inc);  var si := sin(orbit.inc)
	var cw := cos(orbit.argp); var sw := sin(orbit.argp)
	var pqw_x := Vector3(co * cw - so * sw * ci,  so * cw + co * sw * ci,  sw * si)
	var pqw_y := Vector3(-co * sw - so * cw * ci, -so * sw + co * cw * ci, cw * si)

	if _points.size() != POINTS + 1:
		_points.resize(POINTS + 1)
	for i in range(POINTS + 1):
		var t := float(i) / float(POINTS)
		var nu := lerpf(nu0, nu_end, t)
		var r_at := p_slr / (1.0 + e * cos(nu))
		_points[i] = (pqw_x * r_at * cos(nu) + pqw_y * r_at * sin(nu)) * SCENE_SCALE

	_upload_surface()
	_last_signature = Vector4(NAN, NAN, NAN, NAN)


# Maximum number of perigee-burn segments to walk before giving up. Real
# spirals settle in ~4 cycles before an apsis falls below the surface;
# the bound is a safety net against numerical pathologies.
const _DECAYING_MAX_SEGMENTS: int = 8
# Floor on points per segment so even a tiny final-impact arc still
# reads as a curve rather than collapsing to a single line segment.
const _DECAYING_MIN_PTS_PER_SEG: int = 8


## Render a decaying-orbit enemy's full predicted future trajectory as
## a multi-segment spiral: the inbound arc to its next perigee, then a
## full ellipse for each post-burn orbit, ending with the inbound arc
## that intersects Earth's surface. Each perigee-burn halves r_a, so
## the orbits visibly nest inward — the rendered spiral is the player's
## window into "how many cycles before this thing impacts".
func update_decaying_spiral(orbit: MassCenterOrbit) -> void:
	if not orbit.is_state_valid():
		_clear_surfaces()
		return
	var ecc0 := orbit.ecc
	var p0 := orbit.p_slr
	if (
		not is_finite(ecc0) or not is_finite(p0)
		or p0 <= 0.0 or ecc0 <= 0.0
	):
		_clear_surfaces()
		return

	var segs := _build_decaying_segments(orbit)
	if segs.is_empty():
		_clear_surfaces()
		return

	var total_sweep := 0.0
	for seg in segs:
		total_sweep += seg["nu_end"] - seg["nu_start"]
	if total_sweep <= 0.0:
		_clear_surfaces()
		return

	# Allocate points proportional to nu sweep, with a floor per segment
	# so short final arcs aren't visually collapsed.
	var per_radian := float(POINTS) / total_sweep
	var counts: PackedInt32Array = PackedInt32Array()
	counts.resize(segs.size())
	var total_pts := 0
	for i in range(segs.size()):
		var s: Dictionary = segs[i]
		var sweep: float = s["nu_end"] - s["nu_start"]
		var n := maxi(_DECAYING_MIN_PTS_PER_SEG, int(round(sweep * per_radian)))
		counts[i] = n
		total_pts += n

	# Resize the cached buffer so the spiral writes in place — no per-
	# frame Vector3Array allocation, matching the rest of this file.
	if _points.size() != total_pts:
		_points.resize(total_pts)

	# Plane (raan, inc) is invariant across in-plane perigee burns; only
	# argp flips when a halving over-shoots r_p (the orientation flip).
	# Cache the raan/inc trig once and recompute argp trig per segment.
	var co := cos(orbit.raan); var so := sin(orbit.raan)
	var ci := cos(orbit.inc); var si := sin(orbit.inc)

	var write_idx := 0
	for i in range(segs.size()):
		var seg: Dictionary = segs[i]
		var seg_e: float = seg["e"]
		var seg_p: float = seg["p_slr"]
		var seg_argp: float = seg["argp"]
		var nu_a: float = seg["nu_start"]
		var nu_b: float = seg["nu_end"]
		var n: int = counts[i]
		var cw := cos(seg_argp); var sw := sin(seg_argp)
		var pqw_x := Vector3(
			co * cw - so * sw * ci,
			so * cw + co * sw * ci,
			sw * si,
		)
		var pqw_y := Vector3(
			-co * sw - so * cw * ci,
			-so * sw + co * cw * ci,
			cw * si,
		)
		for j in range(n):
			var t: float = (
				0.0 if n <= 1 else float(j) / float(n - 1)
			)
			var nu := lerpf(nu_a, nu_b, t)
			var r_at: float = seg_p / (1.0 + seg_e * cos(nu))
			_points[write_idx] = (
				pqw_x * (r_at * cos(nu)) + pqw_y * (r_at * sin(nu))
			) * SCENE_SCALE
			write_idx += 1

	_upload_surface()
	# Spiral geometry changes every tick (nu0 of segment 0 sweeps with
	# the body, segments compress after each burn); invalidate the
	# orbit-cache signature so update_orbit rebuilds correctly if ever
	# called on a former decaying body.
	_last_signature = Vector4(NAN, NAN, NAN, NAN)


# Forward-simulate the perigee-burn sequence and return one dictionary
# per spiral segment with (e, p_slr, argp, nu_start, nu_end). raan and
# inc are taken straight off `orbit` by the caller — in-plane burns
# don't perturb them. Static so headless tests can exercise the
# segmentation without instantiating a Node.
static func _build_decaying_segments(orbit: MassCenterOrbit) -> Array:
	var segs: Array = []
	var cur_e: float = orbit.ecc
	var cur_p: float = orbit.p_slr
	var cur_argp: float = orbit.argp
	var cur_r_p: float = orbit.r_p
	var cur_r_a: float = orbit.r_a
	if not is_finite(cur_r_p) or not is_finite(cur_r_a):
		return segs

	var nu0: float = orbit.nu

	# Final-descent shortcut: after the over-shooting burn the orbit's
	# perigee already sits below the impact threshold, so the body won't
	# reach a next "perigee" — it impacts first. Render only the inbound arc
	# from the current nu to the impact crossing, no further burns.
	var impact_r: float = (
		MassCenterOrbit.BODY_RADIUS_KM + maxf(MassCenterOrbit.SAFE_ORBIT_ALT_KM - 90.0, 0.0)
	)
	if cur_r_p < impact_r:
		var nu_end_impact := _next_surface_crossing(cur_p, cur_e, nu0, impact_r)
		if is_finite(nu_end_impact) and nu_end_impact > nu0:
			segs.append({
				"e": cur_e, "p_slr": cur_p, "argp": cur_argp,
				"nu_start": nu0, "nu_end": nu_end_impact,
			})
		return segs

	# Normal case: initial segment runs from the body's current true
	# anomaly forward in motion to the next perigee. orbit.nu wraps to
	# (-π, π]; forward motion sweeps nu monotonically upward, so the
	# next perigee is at nu = 0 if currently negative (descending) or
	# nu = TAU if currently positive (already past perigee, full
	# revolution to the next).
	var initial_end: float = 0.0 if nu0 <= 0.0 else TAU
	segs.append({
		"e": cur_e, "p_slr": cur_p, "argp": cur_argp,
		"nu_start": nu0, "nu_end": initial_end,
	})

	for _cycle in range(_DECAYING_MAX_SEGMENTS):
		# Halve r_a. If r_a/2 falls below r_p, the burn over-shoots:
		# the burn point becomes the new orbit's apogee and the trailing
		# apsis (= old r_a/2) becomes the new perigee.
		var halved: float = cur_r_a * 0.5
		var new_r_p: float = minf(cur_r_p, halved)
		var new_r_a: float = maxf(cur_r_p, halved)
		var flipped: bool = halved < cur_r_p
		var new_argp: float = (
			fposmod(cur_argp + PI, TAU) if flipped else cur_argp
		)
		var new_a: float = 0.5 * (new_r_p + new_r_a)
		var denom: float = new_r_a + new_r_p
		if denom <= 0.0:
			break
		var new_e: float = (new_r_a - new_r_p) / denom
		var new_p: float = new_a * (1.0 - new_e * new_e)
		if new_p <= 0.0:
			break
		# Body's nu in the new orbit: at perigee (nu = 0) when not
		# flipped, at apogee (nu = π) when flipped. Rendering sweeps
		# forward from there.
		var seg_nu_start: float = PI if flipped else 0.0

		if new_r_p < impact_r:
			# Final segment: arc from start nu forward to the impact-altitude
			# crossing on the descending leg. r(ν) = p / (1 + e cos ν)
			# = R_impact → cos(ν) = (p/R_impact − 1)/e, taking the descending
			# solution at nu = TAU − acos(...).
			var cos_surf: float = (
				new_p / impact_r - 1.0
			) / new_e
			if cos_surf > 1.0 or cos_surf < -1.0:
				break
			var nu_surf: float = acos(clampf(cos_surf, -1.0, 1.0))
			var nu_end_final: float = TAU - nu_surf
			# When flipped the body starts at nu=π (apogee), so the
			# arc to nu = TAU − nu_surf is the inbound leg. When not
			# flipped (rare — would require cur_r_p already below R,
			# which the spiral's growth pattern doesn't reach in
			# practice), keep the same impact target — it's still the
			# next descending crossing.
			segs.append({
				"e": new_e, "p_slr": new_p, "argp": new_argp,
				"nu_start": seg_nu_start, "nu_end": nu_end_final,
			})
			break

		# Otherwise the segment is a full revolution starting from the
		# body's location in the new orbit.
		segs.append({
			"e": new_e, "p_slr": new_p, "argp": new_argp,
			"nu_start": seg_nu_start,
			"nu_end": seg_nu_start + TAU,
		})

		cur_e = new_e
		cur_p = new_p
		cur_argp = new_argp
		cur_r_p = new_r_p
		cur_r_a = new_r_a

	return segs


# Smallest unwrapped nu strictly greater than `nu_start` at which the
# orbit's radius equals `target_r` (defaults to the impact-altitude radius
# for the current body). Returns NAN if the orbit's r_p is above that
# radius (no real crossing). Used to truncate the spiral's final inbound
# arc at the impact point.
static func _next_surface_crossing(
	p_slr: float, e: float, nu_start: float,
	target_r: float = -1.0
) -> float:
	if e <= 0.0 or p_slr <= 0.0:
		return NAN
	if target_r < 0.0:
		target_r = (
			MassCenterOrbit.BODY_RADIUS_KM
			+ maxf(MassCenterOrbit.SAFE_ORBIT_ALT_KM - 90.0, 0.0)
		)
	var cos_surf := (p_slr / target_r - 1.0) / e
	if cos_surf > 1.0 or cos_surf < -1.0:
		return NAN
	var nu_surf := acos(clampf(cos_surf, -1.0, 1.0))
	# In unwrapped form, descending surface crossings live at
	# −nu_surf + 2πk for integer k. Pick the smallest one strictly
	# greater than nu_start.
	var candidate := -nu_surf
	while candidate <= nu_start:
		candidate += TAU
	return candidate


## Predicted time-to-impact (seconds) for a decaying-orbit body that
## walks the perigee-burn spiral the renderer already models. Sums
## Kepler time-of-flight across each segment update_decaying_spiral
## would draw, so the ETA accounts for every burn the body will perform
## — not just the current orbit, which sits well above the surface
## right up until the over-shoot cycle. Required so the path-color
## gradient (and any other ETA-keyed UI) reflects "time until ground
## contact", not "time until current orbit decays" (which is INF).
## Returns INF if the segmenter couldn't resolve a final impact arc.
static func decaying_time_to_impact(orbit: MassCenterOrbit) -> float:
	if not orbit.is_state_valid():
		return INF
	var segs := _build_decaying_segments(orbit)
	if segs.is_empty():
		return INF
	# The last segment must end at the impact-altitude radius; if the
	# segmenter ran out of cycles without resolving an impact, treat the
	# prediction as "beyond horizon" rather than understating the ETA.
	var impact_r: float = (
		MassCenterOrbit.BODY_RADIUS_KM + maxf(MassCenterOrbit.SAFE_ORBIT_ALT_KM - 90.0, 0.0)
	)
	var last: Dictionary = segs[-1]
	var last_e: float = last["e"]
	var last_p: float = last["p_slr"]
	var r_at_end: float = last_p / (1.0 + last_e * cos(last["nu_end"]))
	if absf(r_at_end - impact_r) > 1.0:
		return INF
	var total := 0.0
	for seg: Dictionary in segs:
		var dt := _segment_tof_seconds(seg)
		if not is_finite(dt) or dt < 0.0:
			return INF
		total += dt
	return total


# Time-of-flight (seconds) along an elliptical segment from nu_start to
# nu_end via Kepler's equation. nu_end is expected ≥ nu_start; multi-
# revolution sweeps (the full-period middle segments) are handled by
# tracking the cycle count when unwrapping mean anomaly. Pure math so
# the headless test suite can exercise it without a SceneTree.
static func _segment_tof_seconds(seg: Dictionary) -> float:
	var e: float = seg["e"]
	var p: float = seg["p_slr"]
	var nu_a: float = seg["nu_start"]
	var nu_b: float = seg["nu_end"]
	if not is_finite(e) or e < 0.0 or e >= 1.0 or p <= 0.0:
		return INF
	var a := p / (1.0 - e * e)
	if a <= 0.0:
		return INF
	var n := sqrt(MassCenterOrbit.MU / (a * a * a))
	if n <= 0.0:
		return INF
	var m_a := _mean_anomaly_unwrapped(nu_a, e)
	var m_b := _mean_anomaly_unwrapped(nu_b, e)
	return (m_b - m_a) / n


# Mean anomaly that preserves the cycle count of `nu` rather than
# wrapping into a single (-π, π] window — required so the time-of-
# flight across a full-revolution segment integrates to a full period
# instead of zero. Standard nu→E→M chain inside one cycle, plus a
# TAU·k offset matching the source nu's turn count.
static func _mean_anomaly_unwrapped(nu: float, e: float) -> float:
	var cycles: float = floor((nu + PI) / TAU)
	var nu_w: float = nu - cycles * TAU
	var ecc_anom := 2.0 * atan2(
		sqrt(1.0 - e) * sin(nu_w * 0.5),
		sqrt(1.0 + e) * cos(nu_w * 0.5),
	)
	var m := ecc_anom - e * sin(ecc_anom)
	return m + cycles * TAU


func _clear_surfaces() -> void:
	_array_mesh.clear_surfaces()


# Ribbon expansion: each base ring point becomes two vertices (left/right
# side), drawn as a triangle strip whose triangles are (v_2i, v_2i+1,
# v_2i+2) and (v_2i+2, v_2i+1, v_2i+3). The shader offsets each pair
# perpendicular to the line direction in screen space, so width is
# uniform pixels regardless of camera zoom. Tangent direction stored in
# ARRAY_NORMAL — we don't need its magnitude (the shader normalises in
# screen space), and unshaded materials don't read NORMAL for lighting,
# so oct-encoding's loss of length is harmless.
func _upload_surface() -> void:
	var ring_count := _points.size()
	if ring_count < 2:
		_clear_surfaces()
		return
	var vert_count := ring_count * 2

	if _verts.size() != vert_count:
		_verts.resize(vert_count)
		_normals.resize(vert_count)
		_uvs.resize(vert_count)

	# Last ring inherits the previous segment's tangent so the ribbon
	# doesn't pinch shut at endpoints (open trajectories) or at the
	# closing seam of an ellipse.
	for i in range(ring_count):
		var here: Vector3 = _points[i]
		var tangent: Vector3
		if i + 1 < ring_count:
			tangent = _points[i + 1] - here
		else:
			tangent = here - _points[i - 1]
		# Guard against duplicate consecutive points collapsing the
		# tangent. Shader handles a zero-length screen delta gracefully,
		# but feeding NaN through oct-encoding would corrupt the buffer.
		if tangent.length_squared() < 1.0e-20:
			tangent = Vector3(1.0, 0.0, 0.0)
		var left_idx := i * 2
		var right_idx := left_idx + 1
		_verts[left_idx] = here
		_verts[right_idx] = here
		_normals[left_idx] = tangent
		_normals[right_idx] = tangent
		_uvs[left_idx] = Vector2(-1.0, 0.0)
		_uvs[right_idx] = Vector2(1.0, 0.0)

	# Always rebuild the surface from scratch. The per-vertex layout
	# (vertex + normal + uv) doesn't lend itself to surface_update_*
	# in-place writes — both the vertex and the attribute buffers
	# would need region updates whose byte layouts depend on Godot's
	# internal vertex compression, and the rebuild is cheap at the
	# 15 Hz orbit-render cadence (a few hundred vertices per call).
	_array_mesh.clear_surfaces()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	_array_mesh.add_surface_from_arrays(
		Mesh.PRIMITIVE_TRIANGLE_STRIP, arrays
	)
	_array_mesh.surface_set_material(0, _material)


static func _signature_close(a: Vector4, b: Vector4) -> bool:
	if not is_finite(b.x):
		return false
	# Relative tolerance for a/ecc, absolute for angles. Mostly a guard
	# against rebuilding for sub-millimeter drift while propagating.
	if absf(a.x - b.x) > maxf(1.0, absf(b.x)) * 1.0e-4: return false
	if absf(a.y - b.y) > 1.0e-5: return false
	if not _angle_close(a.z, b.z): return false
	if not _angle_close(a.w, b.w): return false
	return true


static func _angle_close(a: float, b: float) -> bool:
	if not is_finite(b):
		return false
	var d := fposmod(a - b + PI, TAU) - PI
	return absf(d) < 1.0e-4
