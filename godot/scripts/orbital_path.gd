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
