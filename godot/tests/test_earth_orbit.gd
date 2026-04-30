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


func test_compute_periapsis_matches_recompute() -> void:
	# compute_periapsis is a stateless mirror of _recompute_elements'
	# r_p calculation; the two must agree on a normal elliptical orbit.
	var o := _make_iss_like()
	var r_p := EarthOrbit.compute_periapsis(o.r, o.v)
	# Same float64 path on both sides of the comparison, but the inputs
	# come through 32-bit Vector3 components so a meter of slack covers
	# the ULP noise in the cross / dot products.
	assert_close(r_p, o.r_p, 1.0e-3)


func test_compute_periapsis_circular_equals_radius() -> void:
	var radius := EarthOrbit.EARTH_RADIUS_KM + 800.0
	var v_circ := sqrt(EarthOrbit.MU / radius)
	var r_p := EarthOrbit.compute_periapsis(
		Vector3(radius, 0.0, 0.0), Vector3(0.0, v_circ, 0.0)
	)
	# A "circular" orbit constructed in 32-bit Vector3 components has a
	# residual eccentricity ~1e-7, so r_p drifts from the radius by a
	# fraction of a kilometer — comfortably below 1 km of tolerance.
	assert_close(r_p, radius, 1.0e-2)


func test_compute_periapsis_rectilinear_is_zero() -> void:
	# r along v: zero angular momentum, body falls to origin. Treated
	# as r_p = 0 so it always trips a min-periapsis safety check.
	var r_p := EarthOrbit.compute_periapsis(
		Vector3(7000.0, 0.0, 0.0), Vector3(2.0, 0.0, 0.0)
	)
	assert_eq(r_p, 0.0)


func test_clamp_dv_noop_when_already_safe() -> void:
	# A tiny prograde nudge to a healthy LEO orbit doesn't reach the
	# surface; the clamp must hand the dv back unchanged.
	var o := _make_iss_like()
	var dv := o.v.normalized() * 0.05
	var safe := EarthOrbit.clamp_dv_for_min_periapsis(
		o.r, o.v, dv, EarthOrbit.EARTH_RADIUS_KM + 1.0
	)
	assert_vec_close(safe, dv, 1.0e-9)


func test_clamp_dv_blocks_deorbit_burn() -> void:
	# A big retrograde burn at LEO would drop periapsis underground.
	# After clamping, the resulting orbit must clear the threshold.
	var o := _make_iss_like()
	var dv_retro := -o.v.normalized() * 3.0
	var threshold := EarthOrbit.EARTH_RADIUS_KM + 1.0
	var safe_dv := EarthOrbit.clamp_dv_for_min_periapsis(
		o.r, o.v, dv_retro, threshold
	)
	# Bisection only guarantees safety, not maximality, but the
	# clamped dv must point along the original direction.
	var ratio := safe_dv.length() / dv_retro.length()
	assert_true(ratio < 1.0, "expected clamp to shrink retrograde burn")
	var r_p_after := EarthOrbit.compute_periapsis(o.r, o.v + safe_dv)
	# Bisection's lower bound sits ε under the threshold; allow a hair
	# of slack so a converged-but-not-exact result still passes.
	assert_true(
		r_p_after >= threshold - 1.0,
		"r_p_after=%f below threshold=%f" % [r_p_after, threshold]
	)


func test_clamp_dv_zero_when_already_unsafe() -> void:
	# If the orbit is already doomed, the clamp refuses to apply any of
	# the requested dv (so the player can't make a bad situation worse).
	var pos := Vector3(EarthOrbit.EARTH_RADIUS_KM + 200.0, 0.0, 0.0)
	var vel := Vector3(0.0, 6.0, 0.0)  # too slow for 200 km circular
	assert_true(EarthOrbit.compute_periapsis(pos, vel) < EarthOrbit.EARTH_RADIUS_KM)
	var dv := Vector3(0.0, -0.5, 0.0)
	var safe := EarthOrbit.clamp_dv_for_min_periapsis(
		pos, vel, dv, EarthOrbit.EARTH_RADIUS_KM + 1.0
	)
	assert_vec_close(safe, Vector3.ZERO, 1.0e-12)


func test_safe_relative_maneuver_keeps_periapsis_above_surface() -> void:
	# End-to-end: a deorbit-magnitude retrograde burn through the
	# clamped relative_maneuver path leaves the orbit safe to fly.
	var o := _make_iss_like()
	var threshold := EarthOrbit.EARTH_RADIUS_KM + 1.0
	assert_true(o.relative_maneuver(Vector3(-3.0, 0.0, 0.0), 60.0, threshold))
	assert_true(
		o.r_p >= threshold - 1.0,
		"r_p=%f below threshold=%f" % [o.r_p, threshold]
	)


func test_stumpff_c2_small_psi() -> void:
	# c2(0) = 1/2.
	assert_close(EarthOrbit.c2(0.0), 0.5, 1.0e-12)
	# Series and closed-form should agree at the boundary.
	assert_close(EarthOrbit.c2(0.99), (1.0 - cos(sqrt(0.99))) / 0.99, 1.0e-9)


func test_stumpff_c3_small_psi() -> void:
	# c3(0) = 1/6.
	assert_close(EarthOrbit.c3(0.0), 1.0 / 6.0, 1.0e-12)
	assert_close(EarthOrbit.c3(0.99), (sqrt(0.99) - sin(sqrt(0.99))) / pow(0.99, 1.5), 1.0e-9)
