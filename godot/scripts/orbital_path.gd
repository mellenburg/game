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
