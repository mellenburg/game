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


func test_make_circular_altitude_and_eccentricity() -> void:
	# A circle at 500 km should report eccentricity essentially zero
	# and a radius matching the requested altitude on both r and r_p.
	var alt := 500.0
	var o := EarthOrbit.make_circular(alt, 0.0, 0.0, 0.0)
	assert_close(o.norm_r, EarthOrbit.EARTH_RADIUS_KM + alt, 1.0e-3)
	assert_close(o.r_p, EarthOrbit.EARTH_RADIUS_KM + alt, 1.0e-2)
	assert_true(o.ecc < 1.0e-6, "ecc=%f not circular" % o.ecc)


func test_make_circular_inclination_matches() -> void:
	# Inclination read back from the propagator must match what we
	# asked for (within Vector3 noise).
	var inc := deg_to_rad(35.0)
	var o := EarthOrbit.make_circular(500.0, inc, 0.0, 0.0)
	assert_close(o.inc, inc, 1.0e-5)


func test_make_circular_altitude_invariant_under_propagation() -> void:
	# The defining property of a circular orbit: altitude is constant.
	# Step through a full period and watch norm_r stay pinned.
	var alt := 500.0
	var radius := EarthOrbit.EARTH_RADIUS_KM + alt
	var o := EarthOrbit.make_circular(alt, deg_to_rad(45.0), 0.0, 0.0)
	for _i in range(40):
		assert_true(o.propagate(120.0))
		assert_close(o.norm_r, radius, 1.0e-2)


func test_make_circular_distinct_true_anomalies_distinct_positions() -> void:
	# Same plane, different nu → different positions on the same circle.
	var a := EarthOrbit.make_circular(500.0, 0.0, 0.0, 0.0)
	var b := EarthOrbit.make_circular(500.0, 0.0, 0.0, deg_to_rad(120.0))
	assert_true(
		(a.r - b.r).length() > 1000.0,
		"expected sats 120° apart to be > 1000 km apart"
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


# ---- time_to_impact ------------------------------------------------------


func test_time_to_impact_circular_orbit_never_hits() -> void:
	# A circular 500 km orbit has r_p == r > EARTH_RADIUS. The short-
	# circuit on r_p > EARTH_RADIUS_KM should return INF without
	# spinning the propagator.
	var o := EarthOrbit.make_circular(500.0, 0.0, 0.0, 0.0)
	assert_eq(o.time_to_impact(1800.0, 30.0), INF)


func test_time_to_impact_underground_returns_zero() -> void:
	# Already inside Earth — the function returns 0 immediately so
	# callers ranking by impact urgency see the most urgent possible
	# value.
	var o := EarthOrbit.new(
		Vector3(EarthOrbit.EARTH_RADIUS_KM * 0.5, 0.0, 0.0),
		Vector3(0.0, 5.0, 0.0),
	)
	assert_close(o.time_to_impact(1800.0, 30.0), 0.0)


func test_time_to_impact_inbound_drop() -> void:
	# Highly eccentric inbound trajectory from 8000 km radius. Velocity
	# is dominantly inward but with a small tangential component so the
	# orbit isn't rectilinear (a pure-radial state has h = 0 which the
	# propagator's element pipeline rejects). The sub-surface periapsis
	# guarantees the body crosses the surface inside the horizon.
	var o := EarthOrbit.new(
		Vector3(8000.0, 0.0, 0.0),
		Vector3(-1.0, 1.0, 0.0),
	)
	var t := o.time_to_impact(1800.0, 10.0)
	assert_true(is_finite(t), "expected finite time-to-impact for inbound drop")
	assert_true(t > 0.0)
	assert_true(t < 1800.0)
	# Verify the receiver is unchanged — time_to_impact must not
	# mutate `self`. Compare the radius only; floating-point mod work
	# inside _recompute_elements would shift derived elements but r
	# itself shouldn't drift.
	assert_close(o.r.x, 8000.0)
	assert_close(o.r.y, 0.0)


func test_time_to_impact_capped_by_horizon() -> void:
	# A barely-inbound body whose impact lies past the requested
	# horizon should report INF (caller's "no current threat" answer)
	# rather than running propagation forever. We use an inbound
	# trajectory whose r_p sits just below the surface but with so
	# little radial velocity that the surface crossing won't happen
	# inside the short horizon we pass in.
	var o := EarthOrbit.new(
		Vector3(40000.0, 0.0, 0.0),
		Vector3(-0.05, 0.5, 0.0),
	)
	# 60 seconds is far too short for a body 33000 km up at 50 m/s
	# inward to reach the surface — confirm we get INF.
	assert_eq(o.time_to_impact(60.0, 30.0), INF)


func test_time_to_impact_orders_two_asteroids_by_urgency() -> void:
	# Two inbound bodies at the same radius but different speeds: the
	# faster-falling one should report a smaller time-to-impact. This
	# is the property the laser "max danger" targeting depends on.
	# Tangential component is identical so h ≠ 0 in both — only the
	# radial inflow rate differs.
	var slow := EarthOrbit.new(
		Vector3(10000.0, 0.0, 0.0), Vector3(-1.0, 1.0, 0.0)
	)
	var fast := EarthOrbit.new(
		Vector3(10000.0, 0.0, 0.0), Vector3(-3.0, 1.0, 0.0)
	)
	var t_slow := slow.time_to_impact(1800.0, 10.0)
	var t_fast := fast.time_to_impact(1800.0, 10.0)
	assert_true(is_finite(t_slow))
	assert_true(is_finite(t_fast))
	assert_true(t_fast < t_slow, "faster inbound should impact sooner")


func test_compute_apoapsis_circular_orbit_equals_radius() -> void:
	# Circular orbit: e ≈ 0, so r_a = r_p = r. Tolerance is 1e-2 km
	# rather than 1e-6 because Vector3 components are 32-bit; the
	# stored v_circ rounds enough to put |e| in the 1e-7 range, which
	# scaled against r ~ 7000 km lands around 1 mm of deviation.
	var radius := 6371.0 + 500.0
	var v_circ := sqrt(EarthOrbit.MU / radius)
	var pos := Vector3(radius, 0.0, 0.0)
	var vel := Vector3(0.0, v_circ, 0.0)
	assert_close(EarthOrbit.compute_apoapsis(pos, vel), radius, 1.0e-2)
	assert_close(EarthOrbit.compute_periapsis(pos, vel), radius, 1.0e-2)


func test_compute_apoapsis_elliptic_matches_orbit_elements() -> void:
	# Build a clearly elliptical orbit and check apoapsis matches the
	# r_a stored on the EarthOrbit. Two independent code paths should
	# produce the same answer; if they diverge the safety check is
	# computing a different ellipse than the propagator believes in.
	var pos := Vector3(8000.0, 0.0, 0.0)
	var vel := Vector3(0.0, 8.5, 0.0)  # tangential, clearly bound
	var orb := EarthOrbit.new(pos, vel)
	assert_true(orb.is_state_valid())
	assert_close(EarthOrbit.compute_apoapsis(pos, vel), orb.r_a, 1.0e-3)
	assert_close(EarthOrbit.compute_periapsis(pos, vel), orb.r_p, 1.0e-3)


func test_compute_apoapsis_returns_inf_for_unbound_trajectory() -> void:
	# Any clearly-unbound (parabolic+) trajectory must report INF
	# rather than a wildly large finite r_a — otherwise the railgun
	# safety check would let an escape-velocity shot pass as long as
	# the operator's max-radius slider was high enough. The exact
	# escape-velocity boundary itself is float-fragile (32-bit
	# Vector3 component truncation can flip the sign of specific
	# orbital energy), so the assertion is only on velocities past
	# the boundary by a clear margin.
	var radius := 8000.0
	var v_esc := sqrt(2.0 * EarthOrbit.MU / radius)
	var pos := Vector3(radius, 0.0, 0.0)
	# 0.1 % past escape — energy positive but small.
	var hyper_just_past := Vector3(0.0, v_esc * 1.001, 0.0)
	assert_eq(EarthOrbit.compute_apoapsis(pos, hyper_just_past), INF)
	# Well past escape — strictly hyperbolic.
	var hyper_well_past := Vector3(0.0, v_esc * 1.5, 0.0)
	assert_eq(EarthOrbit.compute_apoapsis(pos, hyper_well_past), INF)


func test_compute_apoapsis_returns_inf_for_radial_state() -> void:
	# Rectilinear (no angular momentum): apoapsis is undefined as a
	# turning radius for the conic. We return INF so any "would
	# this orbit stay below max radius?" guard treats the case as
	# unsafe.
	var pos := Vector3(8000.0, 0.0, 0.0)
	var vel := Vector3(1.0, 0.0, 0.0)  # purely radial, h = 0
	assert_eq(EarthOrbit.compute_apoapsis(pos, vel), INF)
