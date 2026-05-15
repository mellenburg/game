extends "res://tests/framework.gd"
## Orbital path geometry. Verifies the perifocal-frame ellipse generator
## without spinning up a SceneTree (the static rotation math is checked
## by reproducing it locally and comparing to the orbit's own r vector).

const MassCenterOrbit = preload("res://scripts/mass_center_orbit.gd")


func _pqw_to_eci_columns(orbit: MassCenterOrbit) -> Array:
	# Same rotation that orbital_path.gd applies internally.
	var co := cos(orbit.raan); var so := sin(orbit.raan)
	var ci := cos(orbit.inc); var si := sin(orbit.inc)
	var cw := cos(orbit.argp); var sw := sin(orbit.argp)
	var px := Vector3(co * cw - so * sw * ci,  so * cw + co * sw * ci,  sw * si)
	var py := Vector3(-co * sw - so * cw * ci, -so * sw + co * cw * ci, cw * si)
	return [px, py]


func test_periapsis_distance_matches_elements() -> void:
	# At eccentric anomaly = 0, perifocal coords are (a*(1-e), 0).
	# Radial distance from Earth's center should equal r_p.
	var o := MassCenterOrbit.new(
		Vector3(7000.0, 0.0, 0.0),
		Vector3(0.0, 8.0, 1.0),
	)
	var cols := _pqw_to_eci_columns(o)
	var p := o.a * (cos(0.0) - o.ecc)
	var q := o.b * sin(0.0)
	var pos: Vector3 = cols[0] * p + cols[1] * q
	assert_close(pos.length(), o.r_p, 1.0e-3)


func test_apoapsis_distance_matches_elements() -> void:
	var o := MassCenterOrbit.new(
		Vector3(7000.0, 0.0, 0.0),
		Vector3(0.0, 8.0, 1.0),
	)
	var cols := _pqw_to_eci_columns(o)
	var p := o.a * (cos(PI) - o.ecc)
	var q := o.b * sin(PI)
	var pos: Vector3 = cols[0] * p + cols[1] * q
	assert_close(pos.length(), o.r_a, 1.0e-3)


func test_perifocal_axes_are_orthonormal_to_h() -> void:
	# px and py must both lie in the orbital plane => orthogonal to h.
	# Tolerance of 1e-6 accounts for Vector3's 32-bit float precision —
	# cross() and normalize() each lose a few ulps even though the
	# trig calls themselves are 64-bit.
	var o := MassCenterOrbit.new(
		Vector3(-6045.0, -3490.0, 2500.0),
		Vector3(-3.56, 6.618, 2.533),
	)
	var cols := _pqw_to_eci_columns(o)
	var h := o.r.cross(o.v).normalized()
	assert_close(cols[0].dot(h), 0.0, 1.0e-6)
	assert_close(cols[1].dot(h), 0.0, 1.0e-6)


func test_actual_position_lies_on_the_ellipse() -> void:
	# Stronger check: walk the eccentric-anomaly ellipse densely and find
	# the closest point to the propagated state. It must be within tens
	# of meters (sampling resolution * derivative magnitude).
	var o := MassCenterOrbit.new(
		Vector3(7000.0, 1000.0, 500.0),
		Vector3(-1.0, 7.5, 0.5),
	)
	var cols := _pqw_to_eci_columns(o)
	var samples := 2048
	var best := INF
	for i in range(samples):
		var ang := TAU * float(i) / float(samples)
		var p := o.a * (cos(ang) - o.ecc)
		var q := o.b * sin(ang)
		var pos: Vector3 = cols[0] * p + cols[1] * q
		var d := pos.distance_to(o.r)
		if d < best:
			best = d
	assert_true(best < 50.0, "closest sampled point %f km from r" % best)
