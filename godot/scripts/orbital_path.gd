class_name OrbitalPath
extends MeshInstance3D
## Static orbit path renderer. Builds a single ArrayMesh once and rewrites
## its vertex buffer in place when the orbit changes — avoids the per-frame
## ImmediateMesh / StandardMaterial3D allocation that crashed the previous
## port after ~1 minute.

const EarthOrbit = preload("res://scripts/earth_orbit.gd")
const POINTS: int = 360
const SCENE_SCALE: float = 1.0 / 1000.0  # km -> scene units

var _array_mesh: ArrayMesh
var _material: StandardMaterial3D
var _points: PackedVector3Array
var _colors: PackedColorArray
var _last_signature := Vector4(NAN, NAN, NAN, NAN)
var _last_inc := NAN
var _last_argp := NAN
var _last_color := Color.TRANSPARENT
var color := Color.BLUE


func _ready() -> void:
	_array_mesh = ArrayMesh.new()
	mesh = _array_mesh

	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	_material.albedo_color = color
	material_override = _material

	_points = PackedVector3Array()
	_points.resize(POINTS + 1)
	_colors = PackedColorArray()
	_colors.resize(POINTS + 1)


## Recompute orbit geometry only when elements have actually changed past a
## small tolerance, then upload the vertex buffer to the cached ArrayMesh.
func update_orbit(orbit: EarthOrbit) -> void:
	if not orbit.is_state_valid():
		_array_mesh.clear_surfaces()
		return
	if not is_finite(orbit.a) or not is_finite(orbit.ecc) or orbit.a <= 0.0:
		_array_mesh.clear_surfaces()
		return

	var sig := Vector4(orbit.a, orbit.ecc, orbit.raan, orbit.inc)
	# Skip rebuild if nothing meaningful changed.
	if (
		_last_color == color
		and _signature_close(sig, _last_signature)
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
	_last_color = color
	_material.albedo_color = color


## Build orbit points in the perifocal (PQW) frame and rotate into ECI.
## Uses eccentric anomaly so points are evenly distributed around the
## ellipse — the previous port chained four separate Transform3Ds and did
## a Vector4 helper to recover the same geometry.
func _compute_points(orbit: EarthOrbit) -> void:
	var a := orbit.a
	var b := orbit.b
	var e := orbit.ecc

	# Perifocal-to-ECI rotation (Vallado eq. 3-29, Z-up celestial frame).
	var co := cos(orbit.raan); var so := sin(orbit.raan)
	var ci := cos(orbit.inc); var si := sin(orbit.inc)
	var cw := cos(orbit.argp); var sw := sin(orbit.argp)

	var pqw_x := Vector3(co * cw - so * sw * ci,  so * cw + co * sw * ci,  sw * si)
	var pqw_y := Vector3(-co * sw - so * cw * ci, -so * sw + co * cw * ci, cw * si)

	for i in range(POINTS + 1):
		var ang := TAU * float(i % POINTS) / float(POINTS)
		var p := a * (cos(ang) - e)
		var q := b * sin(ang)
		var pos := (pqw_x * p + pqw_y * q) * SCENE_SCALE
		_points[i] = pos
		_colors[i] = color


## Render the inbound arc of a sub-orbital trajectory: from the body's
## current true anomaly forward in motion until the orbit dips below
## Earth's surface. Unlike update_orbit, the line truncates at the
## impact point — the segment that would tunnel through the planet is
## omitted, so the visual matches the gameplay rule (meteorites exit
## play on ground contact). Caller must keep `color` in sync; we don't
## cache anything here because the body's nu changes every tick.
func update_trajectory(orbit: EarthOrbit) -> void:
	if not orbit.is_state_valid():
		_array_mesh.clear_surfaces()
		return
	var e := orbit.ecc
	var p_slr := orbit.p_slr
	if not is_finite(e) or not is_finite(p_slr) or p_slr <= 0.0 or e <= 0.0:
		_array_mesh.clear_surfaces()
		return
	# Surface-crossing true anomaly: r(nu) = p_slr / (1 + e*cos(nu)) = R.
	# Two solutions ±nu_surf bracket the inbound and outbound crossings;
	# we want the one ahead of the body in its current direction of
	# motion.
	var cos_nu_surf := (p_slr / EarthOrbit.EARTH_RADIUS_KM - 1.0) / e
	if cos_nu_surf > 1.0 or cos_nu_surf < -1.0:
		# Periapsis is above the surface — not a meteorite trajectory.
		# Fall through to the regular orbit renderer.
		_array_mesh.clear_surfaces()
		return
	var nu_surf := acos(clampf(cos_nu_surf, -1.0, 1.0))
	# Body is inbound iff r·v < 0 (radius decreasing). The descending
	# branch has nu in (-π, 0), and we want the surface crossing also
	# on that branch, so nu_target = -nu_surf.
	var r_dot_v := orbit.r.dot(orbit.v)
	if r_dot_v >= 0.0:
		_array_mesh.clear_surfaces()
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
		_array_mesh.clear_surfaces()
		return

	# Same perifocal-to-ECI rotation as _compute_points.
	var co := cos(orbit.raan); var so := sin(orbit.raan)
	var ci := cos(orbit.inc); var si := sin(orbit.inc)
	var cw := cos(orbit.argp); var sw := sin(orbit.argp)
	var pqw_x := Vector3(co * cw - so * sw * ci,  so * cw + co * sw * ci,  sw * si)
	var pqw_y := Vector3(-co * sw - so * cw * ci, -so * sw + co * cw * ci, cw * si)

	for i in range(POINTS + 1):
		var t := float(i) / float(POINTS)
		var nu := lerpf(nu0, nu_target, t)
		var r_at := p_slr / (1.0 + e * cos(nu))
		var p_local := r_at * cos(nu)
		var q_local := r_at * sin(nu)
		var pos := (pqw_x * p_local + pqw_y * q_local) * SCENE_SCALE
		_points[i] = pos
		_colors[i] = color

	_upload_surface()
	_material.albedo_color = color
	# Trajectory geometry changes every tick (nu0 sweeps); invalidate
	# the orbit-cache signature so a later switch back to update_orbit
	# triggers a rebuild instead of trusting stale cached state.
	_last_signature = Vector4(NAN, NAN, NAN, NAN)
	_last_color = color


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
func update_decaying_spiral(orbit: EarthOrbit) -> void:
	if not orbit.is_state_valid():
		_array_mesh.clear_surfaces()
		return
	var ecc0 := orbit.ecc
	var p0 := orbit.p_slr
	if (
		not is_finite(ecc0) or not is_finite(p0)
		or p0 <= 0.0 or ecc0 <= 0.0
	):
		_array_mesh.clear_surfaces()
		return

	var segs := _build_decaying_segments(orbit)
	if segs.is_empty():
		_array_mesh.clear_surfaces()
		return

	var total_sweep := 0.0
	for seg in segs:
		total_sweep += seg["nu_end"] - seg["nu_start"]
	if total_sweep <= 0.0:
		_array_mesh.clear_surfaces()
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

	# Resize the cached buffers so the spiral writes in place — no per-
	# frame Vector3Array allocation, matching the rest of this file.
	if _points.size() != total_pts:
		_points.resize(total_pts)
		_colors.resize(total_pts)

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
			var pos := (
				pqw_x * (r_at * cos(nu)) + pqw_y * (r_at * sin(nu))
			) * SCENE_SCALE
			_points[write_idx] = pos
			_colors[write_idx] = color
			write_idx += 1

	_upload_surface()
	_material.albedo_color = color
	# Spiral geometry changes every tick (nu0 of segment 0 sweeps with
	# the body, segments compress after each burn); invalidate the
	# orbit-cache signature so update_orbit rebuilds correctly if ever
	# called on a former decaying body.
	_last_signature = Vector4(NAN, NAN, NAN, NAN)
	_last_color = color


# Forward-simulate the perigee-burn sequence and return one dictionary
# per spiral segment with (e, p_slr, argp, nu_start, nu_end). raan and
# inc are taken straight off `orbit` by the caller — in-plane burns
# don't perturb them. Static so headless tests can exercise the
# segmentation without instantiating a Node.
static func _build_decaying_segments(orbit: EarthOrbit) -> Array:
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
	# perigee already sits below ground, so the body won't reach a
	# next "perigee" — it impacts first. Render only the inbound arc
	# from the current nu to the surface crossing, no further burns.
	if cur_r_p < EarthOrbit.EARTH_RADIUS_KM:
		var nu_end_impact := _next_surface_crossing(cur_p, cur_e, nu0)
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

		if new_r_p < EarthOrbit.EARTH_RADIUS_KM:
			# Final segment: arc from start nu forward to the surface
			# crossing on the descending leg. r(ν) = p / (1 + e cos ν)
			# = R_earth → cos(ν) = (p/R − 1)/e, taking the descending
			# solution at nu = TAU − acos(...).
			var cos_surf: float = (
				new_p / EarthOrbit.EARTH_RADIUS_KM - 1.0
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
# orbit's radius equals EARTH_RADIUS. Returns NAN if the orbit's
# r_p is above the surface (no real crossing). Used to truncate the
# spiral's final inbound arc at the impact point.
static func _next_surface_crossing(
	p_slr: float, e: float, nu_start: float
) -> float:
	if e <= 0.0 or p_slr <= 0.0:
		return NAN
	var cos_surf := (p_slr / EarthOrbit.EARTH_RADIUS_KM - 1.0) / e
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


func _upload_surface() -> void:
	_array_mesh.clear_surfaces()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _points
	arrays[Mesh.ARRAY_COLOR] = _colors
	_array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINE_STRIP, arrays)
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
