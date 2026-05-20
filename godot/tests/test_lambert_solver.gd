extends "res://tests/framework.gd"
## Lambert solver unit tests. Universal-variable formulation, so the
## tolerance budget is bounded by the bisection residual + Vector3
## float32 storage (~40 cm at LEO scale, ~5 km after a full-period
## propagation per the existing MassCenterOrbit test budget).

const LambertSolver = preload("res://scripts/lambert_solver.gd")
const MassCenterOrbit = preload("res://scripts/mass_center_orbit.gd")
const Propulsion = preload("res://scripts/propulsion.gd")


func _circ_state(radius_km: float) -> Array:
	# Return [r1, v_circ] at (radius_km, 0, 0) on an equatorial circular orbit.
	var v_circ: float = sqrt(MassCenterOrbit.MU / radius_km)
	return [Vector3(radius_km, 0.0, 0.0), Vector3(0.0, v_circ, 0.0)]


# Self-consistency: propagate a known circular orbit forward by some
# TOF, then ask Lambert to recover the velocity at (r1, r2, TOF). The
# recovered v1 must match the propagator's input velocity.
func test_self_consistency_quarter_period() -> void:
	var setup := _circ_state(7000.0)
	var r1: Vector3 = setup[0]
	var v0: Vector3 = setup[1]
	var orbit := MassCenterOrbit.new(r1, v0)
	var quarter: float = orbit.period * 0.25
	var ref := MassCenterOrbit.new(r1, v0)
	assert_true(ref.propagate(quarter))
	var r2: Vector3 = ref.r
	var v2_ref: Vector3 = ref.v
	var sol := LambertSolver.solve(r1, r2, quarter, true)
	assert_true(sol.ok, "solver returned ok=false")
	# Tolerance budget: propagator drift over a quarter period
	# (a few hundred meters of position) divides into v as
	# drift / tof ≈ 1 m/s. 5 m/s gives 5× headroom for the float32
	# storage on r2 (~40 cm at 7 km).
	assert_vec_close(sol.v1, v0, 5.0e-3, "v1 recovery")
	assert_vec_close(sol.v2, v2_ref, 5.0e-3, "v2 recovery")


# Same shape, smaller TOF — exercises a different region of the
# bisection bracket without crossing periapsis.
func test_self_consistency_short_tof() -> void:
	var setup := _circ_state(8500.0)
	var r1: Vector3 = setup[0]
	var v0: Vector3 = setup[1]
	var orbit := MassCenterOrbit.new(r1, v0)
	var tof: float = orbit.period * 0.1  # ~10% of period
	var ref := MassCenterOrbit.new(r1, v0)
	assert_true(ref.propagate(tof))
	var sol := LambertSolver.solve(r1, ref.r, tof, true)
	assert_true(sol.ok)
	assert_vec_close(sol.v1, v0, 5.0e-3)


# Propagate the recovered v1 forward by TOF and verify we land on r2
# within sub-km tolerance. This is the integration test that catches
# sign errors and bracket-direction bugs.
func test_round_trip_propagate() -> void:
	var r1 := Vector3(7100.0, 0.0, 0.0)
	# Slightly elliptical orbit so r and v are not orthogonal — guards
	# against tests passing only on the circular special case.
	var v0 := Vector3(0.5, 7.7, 0.3)
	var orbit := MassCenterOrbit.new(r1, v0)
	var tof: float = 800.0
	assert_true(orbit.propagate(tof))
	var r2: Vector3 = orbit.r
	var sol := LambertSolver.solve(r1, r2, tof, true)
	assert_true(sol.ok)
	# Now propagate (r1, sol.v1) forward by tof and check we land at r2.
	var verify := MassCenterOrbit.new(r1, sol.v1)
	assert_true(verify.propagate(tof))
	# 0.5 km tolerance: bisection residual (1 ms × 7.7 km/s ≈ 8 m) +
	# Vector3 float32 (~40 cm) + propagator drift (~m) — well below 1 km.
	assert_vec_close(verify.r, r2, 0.5, "round-trip landing")


# Inclined transfer: r1 and r2 are in different planes. The Lambert
# transfer should still recover the right velocity, including the
# out-of-plane (z) component.
func test_inclined_transfer() -> void:
	var r1 := Vector3(7000.0, 0.0, 0.0)
	# Velocity with a z component → orbit inclined ~21°.
	var v0 := Vector3(0.0, 7.0, 2.7)
	var ref := MassCenterOrbit.new(r1, v0)
	var tof: float = 500.0
	assert_true(ref.propagate(tof))
	var sol := LambertSolver.solve(r1, ref.r, tof, true)
	assert_true(sol.ok)
	assert_vec_close(sol.v1, v0, 5.0e-3)


# Degenerate 180-degree transfer: r1 and r2 antipodal. The transfer
# plane is undefined — solver must return ok=false rather than NaN.
func test_180_degree_transfer_rejected() -> void:
	var r1 := Vector3(7000.0, 0.0, 0.0)
	var r2 := Vector3(-7000.0, 0.0, 0.0)
	var sol := LambertSolver.solve(r1, r2, 1500.0, true)
	assert_false(sol.ok, "antipodal r1/r2 must be rejected")


# Non-physical inputs: TOF zero or negative, r1 or r2 zero-length.
func test_invalid_inputs_rejected() -> void:
	var r1 := Vector3(7000.0, 0.0, 0.0)
	var r2 := Vector3(0.0, 7000.0, 0.0)
	assert_false(LambertSolver.solve(r1, r2, 0.0, true).ok, "zero TOF")
	assert_false(LambertSolver.solve(r1, r2, -100.0, true).ok, "negative TOF")
	assert_false(LambertSolver.solve(Vector3.ZERO, r2, 100.0, true).ok, "zero r1")
	assert_false(LambertSolver.solve(r1, Vector3.ZERO, 100.0, true).ok, "zero r2")
	assert_false(
		LambertSolver.solve(Vector3(NAN, 0, 0), r2, 100.0, true).ok, "NaN r1"
	)


# Search wrapper: a target offset 90° ahead of the attacker on a
# circular orbit. There's a wide TOF window over which intercept is
# cheap; the search must find one within budget.
func test_search_finds_intercept() -> void:
	var setup_a := _circ_state(7000.0)
	var launch_r: Vector3 = setup_a[0]
	var launch_v: Vector3 = setup_a[1]
	# Target on the same circular orbit, 90° ahead. Same radius, same
	# speed magnitude, but a different position → intercept needs an
	# orbital phase change.
	var v_circ: float = sqrt(MassCenterOrbit.MU / 7000.0)
	var target_r := Vector3(0.0, 7000.0, 0.0)
	var target_v := Vector3(-v_circ, 0.0, 0.0)
	var target_orbit := MassCenterOrbit.new(target_r, target_v)
	var best := LambertSolver.find_best_intercept(
		launch_r, launch_v, target_orbit,
		60.0, 1800.0, 12, 6, INF, 10.0
	)
	assert_true(best.ok, "search returned no intercept")
	assert_true(best.tof >= 60.0 and best.tof <= 1800.0, "tof out of window")
	assert_finite(best.dv.length())
	# A 90° phase change at LEO is on the order of a few km/s — far
	# below 10 km/s. This is the sanity-check upper bound, not a
	# physics-derived limit.
	assert_true(best.dv.length() < 10.0, "dv suspiciously large: %f" % best.dv.length())


# When dv_budget is zero, every solution exceeds budget → ok=false.
# Guards against the search accidentally returning ok=true when no
# solution can satisfy the constraint.
func test_search_rejects_when_budget_zero() -> void:
	var setup_a := _circ_state(7000.0)
	var target_orbit := MassCenterOrbit.new(
		Vector3(0.0, 7000.0, 0.0),
		Vector3(-sqrt(MassCenterOrbit.MU / 7000.0), 0.0, 0.0)
	)
	var best := LambertSolver.find_best_intercept(
		setup_a[0], setup_a[1], target_orbit,
		60.0, 1800.0, 12, 6, 0.0, 10.0
	)
	assert_false(best.ok, "search must reject when dv_budget = 0")


# When blast_radius is zero, the round-trip miss-distance check (which
# is non-zero by float32 / iteration tolerance) will reject every
# candidate → ok=false.
func test_search_rejects_when_blast_radius_zero() -> void:
	var setup_a := _circ_state(7000.0)
	var target_orbit := MassCenterOrbit.new(
		Vector3(0.0, 7000.0, 0.0),
		Vector3(-sqrt(MassCenterOrbit.MU / 7000.0), 0.0, 0.0)
	)
	var best := LambertSolver.find_best_intercept(
		setup_a[0], setup_a[1], target_orbit,
		60.0, 1800.0, 12, 6, INF, 0.0
	)
	assert_false(best.ok, "blast_radius=0 must reject every candidate")


# Lower-radius target should be reachable with finite dv; an absurdly
# distant target (1e6 km — beyond geostationary, beyond Lambert
# reachability in 30 minutes) must report ok=false rather than return
# nonsense.
func test_search_rejects_unreachable_target() -> void:
	var setup_a := _circ_state(7000.0)
	var far := Vector3(1.0e6, 0.0, 0.0)
	var far_v := Vector3(0.0, sqrt(MassCenterOrbit.MU / 1.0e6), 0.0)
	var target_orbit := MassCenterOrbit.new(far, far_v)
	var best := LambertSolver.find_best_intercept(
		setup_a[0], setup_a[1], target_orbit,
		60.0, 1800.0, 12, 6, 4.0, 10.0  # 4 km/s budget can't reach 1e6 km in 30 min
	)
	assert_false(best.ok, "1e6 km target inside 4 km/s budget must be rejected")


# Bad search args.
func test_search_invalid_args() -> void:
	var setup_a := _circ_state(7000.0)
	var target_orbit := MassCenterOrbit.new(
		Vector3(0.0, 7000.0, 0.0),
		Vector3(-sqrt(MassCenterOrbit.MU / 7000.0), 0.0, 0.0)
	)
	assert_false(LambertSolver.find_best_intercept(
		setup_a[0], setup_a[1], target_orbit, -10.0, 100.0
	).ok, "negative tof_min")
	assert_false(LambertSolver.find_best_intercept(
		setup_a[0], setup_a[1], target_orbit, 100.0, 100.0
	).ok, "tof_max <= tof_min")
	assert_false(LambertSolver.find_best_intercept(
		setup_a[0], setup_a[1], null, 60.0, 1800.0
	).ok, "null target_orbit")
