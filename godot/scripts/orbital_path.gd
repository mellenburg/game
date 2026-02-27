class_name OrbitalPath
extends MeshInstance3D
## Draws a 3D elliptical orbit path as a line loop.
## Port of ellipse_3d.cpp — generates orbit geometry from orbital elements.

const POINTS: int = 1000
const SCALE: float = 1.0 / 1000.0  # km to scene units

var color := Color.BLUE
var periapsis_pos := Vector3.ZERO
var apoapsis_pos := Vector3.ZERO


func update_orbit(orbit: EarthOrbit) -> void:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)

	var a_val := orbit.a
	var ecc_val := orbit.ecc
	var r_p_val := orbit.r_p
	var inc_val := orbit.inc
	var raan_val := orbit.raan
	var argp_val := orbit.argp

	var b_val := a_val * sqrt(1.0 - ecc_val * ecc_val)

	# Build transformation matrices matching the C++ version
	# Translate so planet is at focus
	var trans_argp := Transform3D.IDENTITY
	trans_argp.origin = Vector3(r_p_val - a_val, 0.0, 0.0) * SCALE

	# Rotate for inclination
	var rot_inc := Transform3D.IDENTITY
	rot_inc = rot_inc.rotated(Vector3(0.0, -1.0, 0.0), inc_val)

	# Rotate for RAAN
	var foo: float = 1.0 if inc_val <= PI else -1.0
	var rot_raan := Transform3D.IDENTITY
	rot_raan = rot_raan.rotated(Vector3(0.0, 0.0, 1.0), raan_val + foo * PI / 2.0)

	# Compute transformed basis vectors
	var u := Vector4(a_val * SCALE, 0.0, 0.0, 1.0)
	var v := Vector4(0.0, b_val * SCALE, 0.0, 1.0)

	var u_t := _transform_vec4(rot_raan * rot_inc * trans_argp, u)
	var v_t := _transform_vec4(rot_raan * rot_inc, v)

	# Find argp rotation axis
	var u_t3 := Vector3(u_t.x, u_t.y, u_t.z)
	var v_t3 := Vector3(v_t.x, v_t.y, v_t.z)
	var argp_axis := u_t3.cross(v_t3).normalized()

	# Apply argp rotation
	var rot_argp := Transform3D.IDENTITY
	rot_argp = rot_argp.rotated(argp_axis, argp_val - foo * PI / 2.0)

	# Final transformed vectors
	var u_final := _transform_vec4(rot_argp * rot_raan * rot_inc * trans_argp, u)
	var v_final := _transform_vec4(rot_argp * rot_raan * rot_inc * trans_argp, v)

	var u3 := Vector3(u_final.x, u_final.y, u_final.z)
	var v3 := Vector3(v_final.x, v_final.y, v_final.z)

	# Compute semi-axes and displacement
	var A := a_val * SCALE * u3.normalized()
	var delta := u3 - A
	var B := b_val * SCALE * (v3 - delta).normalized()

	var div := TAU / POINTS
	for i in range(POINTS + 1):
		var angle := div * float(i % POINTS)
		var point := cos(angle) * A + sin(angle) * B + delta
		im.surface_set_color(color)
		im.surface_add_vertex(point)
		if i == 0:
			periapsis_pos = point
		elif i == POINTS / 2:
			apoapsis_pos = point

	im.surface_end()
	mesh = im

	# Set material
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.vertex_color_use_as_albedo = true
	material_override = mat


func _transform_vec4(t: Transform3D, v4: Vector4) -> Vector4:
	var v3 := Vector3(v4.x, v4.y, v4.z)
	var result := t * v3
	return Vector4(result.x, result.y, result.z, v4.w)
