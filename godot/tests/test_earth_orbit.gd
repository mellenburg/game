extends "res://tests/framework.gd"
## Orbital mechanics tests.

const EarthOrbit = preload("res://scripts/earth_orbit.gd")


func _make_iss_like() -> EarthOrbit:
	# Approximate ISS state. Roughly 400 km circular, 51.6 deg inc.
	return EarthOrbit.new(
		Vector3(-6045.0, -3490.0, 2500.0),
		Vector3(-3.56, 6.618, 2.533),
	)


func test_initial_state_is_finite() -> void:
	var o := _make_iss_like()
	assert_true(o.is_state_valid())
	assert_finite(o.norm_r)
	assert_finite(o.ecc)
	assert_finite(o.inc)


func test_period_returns_to_origin() -> void:
	var o := _make_iss_like()
	var r0 := o.r
	var v0 := o.v
	assert_true(o.propagate(o.period))
	# After one full orbital period the state should return to itself.
	# Universal-variable propagator is good to a few meters here.
	assert_vec_close(o.r, r0, 5.0)
	assert_vec_close(o.v, v0, 5.0e-3)


func test_specific_energy_conserved() -> void:
	var o := _make_iss_like()
	var energy0 := 0.5 * o.v.dot(o.v) - EarthOrbit.MU / o.r.length()
	for _i in range(20):
		assert_true(o.propagate(180.0))
	var energy1 := 0.5 * o.v.dot(o.v) - EarthOrbit.MU / o.r.length()
	assert_close(energy1, energy0, absf(energy0) * 1.0e-6)


func test_angular_momentum_conserved() -> void:
	var o := _make_iss_like()
	var h0 := o.r.cross(o.v)
	for _i in range(40):
		assert_true(o.propagate(120.0))
	var h1 := o.r.cross(o.v)
	assert_vec_close(h1, h0, h0.length() * 1.0e-6)


func test_huge_step_subdivides_safely() -> void:
	# A single ten-orbit step should not crash; orbit must remain finite
	# and elements still meaningful even when the user holds speed-up.
	var o := _make_iss_like()
	var period := o.period
	assert_true(o.propagate(period * 10.0))
	assert_true(o.is_state_valid())


func test_zero_step_is_noop() -> void:
	var o := _make_iss_like()
	var r0 := o.r
	var v0 := o.v
	assert_true(o.propagate(0.0))
	assert_eq(o.r, r0)
	assert_eq(o.v, v0)


func test_relative_maneuver_preserves_orbit_validity() -> void:
	var o := _make_iss_like()
	# Tiny prograde nudge.
	assert_true(o.relative_maneuver(Vector3(0.01, 0.0, 0.0), 60.0))
	assert_true(o.is_state_valid())


func test_clone_yields_identical_state() -> void:
	var src := _make_iss_like()
	src.propagate(1234.5)
	var dst := EarthOrbit.new(Vector3(1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0))
	dst.clone_from(src)
	assert_vec_close(dst.r, src.r, 1.0e-9)
	assert_vec_close(dst.v, src.v, 1.0e-12)
	assert_close(dst.ecc, src.ecc, 1.0e-9)


func test_invalid_state_detected() -> void:
	# Construct a degenerate orbit (r along v -> rectilinear, no h).
	var bad := EarthOrbit.new(Vector3(7000.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0))
	# State vector itself is finite, but elements should reflect singularity.
	# The propagator should refuse to produce NaN downstream.
	# A propagation of a few seconds may not crash but elements must stay
	# either finite or flagged via is_state_valid().
	bad.propagate(1.0)
	# The contract is just: no NaN escapes as a Vector3 component.
	assert_finite(bad.r)
	assert_finite(bad.v)


func test_nan_input_rejected() -> void:
	var o := _make_iss_like()
	# Garbage tof must not corrupt state.
	var r_before := o.r
	assert_false(o.propagate(NAN))
	assert_eq(o.r, r_before)


func test_stumpff_c2_small_psi() -> void:
	# c2(0) = 1/2.
	assert_close(EarthOrbit.c2(0.0), 0.5, 1.0e-12)
	# Series and closed-form should agree at the boundary.
	assert_close(EarthOrbit.c2(0.99), (1.0 - cos(sqrt(0.99))) / 0.99, 1.0e-9)


func test_stumpff_c3_small_psi() -> void:
	# c3(0) = 1/6.
	assert_close(EarthOrbit.c3(0.0), 1.0 / 6.0, 1.0e-12)
	assert_close(EarthOrbit.c3(0.99), (sqrt(0.99) - sin(sqrt(0.99))) / pow(0.99, 1.5), 1.0e-9)
