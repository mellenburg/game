extends "res://tests/framework.gd"
## Decaying-orbit enemy tests. Pure-math: verify the spawn geometry
## (near apogee, descending) and the analytical perigee-burn that
## halves r_a. The Satellite-side detection (perigee crossing → burn)
## is exercised indirectly through the orbit it produces.

const MassCenterOrbit = preload("res://scripts/mass_center_orbit.gd")
const OrbitalPath = preload("res://scripts/orbital_path.gd")

const APOGEE_ALT_KM: float = 50000.0
const PERIGEE_ALT_KM: float = 500.0
const INITIAL_NU_FROM_APOGEE_DEG: float = 15.0


# Build the same spawn orbit MassCenterSystem uses. RAAN = inc = argp = 0
# so the perifocal frame coincides with ECI x/y, keeping the geometry
# test-introspectable without dragging in the rotation matrices.
func _make_decaying() -> MassCenterOrbit:
	var r_p := MassCenterOrbit.MASS_CENTER_RADIUS_KM + PERIGEE_ALT_KM
	var r_a := MassCenterOrbit.MASS_CENTER_RADIUS_KM + APOGEE_ALT_KM
	var a := 0.5 * (r_p + r_a)
	var e := (r_a - r_p) / (r_a + r_p)
	var p_slr := a * (1.0 - e * e)
	var nu := PI + deg_to_rad(INITIAL_NU_FROM_APOGEE_DEG)
	var r_at := p_slr / (1.0 + e * cos(nu))
	var pos := Vector3(r_at * cos(nu), r_at * sin(nu), 0.0)
	var v_mag := sqrt(MassCenterOrbit.MU / p_slr)
	var vel := Vector3(-v_mag * sin(nu), v_mag * (e + cos(nu)), 0.0)
	return MassCenterOrbit.new(pos, vel)


func test_apogee_matches_spec() -> void:
	var o := _make_decaying()
	assert_close(o.r_a, MassCenterOrbit.MASS_CENTER_RADIUS_KM + APOGEE_ALT_KM, 1.0e-2)


func test_perigee_matches_spec() -> void:
	var o := _make_decaying()
	assert_close(o.r_p, MassCenterOrbit.MASS_CENTER_RADIUS_KM + PERIGEE_ALT_KM, 1.0e-2)


func test_spawn_is_near_apogee() -> void:
	# 15° past apogee on a highly eccentric ellipse leaves the body deep
	# in the upper half of the orbit — well above perigee, well above
	# the surface, so the player has visible time to engage before the
	# first perigee burn.
	var o := _make_decaying()
	assert_true(
		o.norm_r > MassCenterOrbit.MASS_CENTER_RADIUS_KM + 0.5 * APOGEE_ALT_KM,
		"spawn r=%f, expected near apogee" % o.norm_r
	)


func test_spawn_is_descending() -> void:
	# Body must be moving inward toward perigee at spawn — the perigee-
	# burn detector keys off the descending → ascending r·v sign flip,
	# so an ascending spawn would never trigger the first burn.
	var o := _make_decaying()
	assert_true(o.r.dot(o.v) < 0.0, "spawn r·v=%f, expected < 0" % o.r.dot(o.v))


func _step_to_perigee(o: MassCenterOrbit, dt: float) -> bool:
	# Step until r·v flips from negative (descending) to positive
	# (ascending) — the perigee-crossing condition the satellite-side
	# burn detector uses. Bound by ~2 orbital periods.
	var bound := int(o.period / dt) * 2 + 5
	for _i in range(bound):
		var rdv_before: float = o.r.dot(o.v)
		if not o.propagate(dt):
			return false
		if rdv_before < 0.0 and o.r.dot(o.v) > 0.0:
			return true
	return false


func test_propagation_reaches_perigee() -> void:
	var o := _make_decaying()
	assert_true(_step_to_perigee(o, 20.0), "descending body never crossed perigee")


func test_perigee_burn_halves_apogee() -> void:
	# Analytical scale factor v_new/v_old = sqrt((r_p+r_a)/(2r_p+r_a))
	# at perigee, derived from vis-viva. Apply it and check the new
	# orbit's r_a ≈ r_a_old/2.
	var o := _make_decaying()
	assert_true(_step_to_perigee(o, 20.0))
	var r_a_before := o.r_a
	var r_p := o.r_p
	var k := sqrt((r_p + r_a_before) / (2.0 * r_p + r_a_before))
	# maneuver(dv, t=0) → v += dv, recompute elements. Same call site
	# Satellite._perigee_decay_burn uses.
	assert_true(o.maneuver(o.v * (k - 1.0), 0.0))
	# Tolerance loose because we burn a step's worth past exact perigee
	# — velocity has a small radial component, so post-burn r_a drifts
	# a few tens of km off the analytic target.
	assert_close(o.r_a, r_a_before * 0.5, 50.0)


func test_perigee_preserved_through_burn() -> void:
	# Retrograde tangential burn at perigee preserves the perigee point;
	# only the trailing apsis (apogee) shrinks. This is the property
	# that lets the spiral-in unfold over multiple cycles instead of
	# scrambling both apsides at once.
	var o := _make_decaying()
	assert_true(_step_to_perigee(o, 20.0))
	var r_p_before := o.r_p
	var k := sqrt((r_p_before + o.r_a) / (2.0 * r_p_before + o.r_a))
	assert_true(o.maneuver(o.v * (k - 1.0), 0.0))
	# Same loose tolerance: the burn is at near-perigee, not exact, so
	# the new perigee drifts a touch from the old.
	assert_close(o.r_p, r_p_before, 50.0)


func test_repeated_burns_eventually_drive_orbit_into_surface() -> void:
	# Spiral-in invariant: with apogee 50000 km and perigee 500 km,
	# halving r_a four times brings the orbit down through the surface
	# (the fourth burn flips orientation: the body's burn-point becomes
	# the new orbit's apogee and the trailing apsis ends up below R).
	var o := _make_decaying()
	for cycle in range(6):
		if not _step_to_perigee(o, 20.0):
			break
		var k := sqrt((o.r_p + o.r_a) / (2.0 * o.r_p + o.r_a))
		assert_true(o.maneuver(o.v * (k - 1.0), 0.0))
		# Either apsis dipping below the impact-altitude radius counts as
		# terminal — advance_time kills the body at the ablation floor
		# (safe_alt - 90 km), not the bare surface.
		var impact_r: float = (
			MassCenterOrbit.MASS_CENTER_RADIUS_KM
			+ maxf(MassCenterOrbit.SAFE_ORBIT_ALT_KM - 90.0, 0.0)
		)
		if (
			(is_finite(o.r_p) and o.r_p < impact_r)
			or (is_finite(o.r_a) and o.r_a < impact_r)
		):
			return
	fail("orbit never spiraled below the impact altitude after 6 perigee burns")


func test_spiral_segment_count_for_default_orbit() -> void:
	# Apogee 50000 km, perigee 500 km: r_a halves to 28186 → 14093 →
	# 7046 above r_p, then the fourth burn flips orientation and the
	# trailing apsis lands below ground. Initial inbound arc + three
	# full ellipses + final inbound arc = five segments.
	var o := _make_decaying()
	var segs: Array = OrbitalPath._build_decaying_segments(o)
	assert_eq(segs.size(), 5)


func test_spiral_first_segment_runs_to_perigee() -> void:
	# Spawn nu is just past apogee on the descending leg (negative,
	# wrapped). Initial segment must sweep forward to the next perigee
	# at nu = 0.
	var o := _make_decaying()
	var segs: Array = OrbitalPath._build_decaying_segments(o)
	var s0: Dictionary = segs[0]
	assert_close(s0["nu_start"], o.nu, 1.0e-6)
	assert_close(s0["nu_end"], 0.0, 1.0e-6)


func test_spiral_middle_segments_are_full_revolutions() -> void:
	# Every segment between the initial inbound arc and the final
	# impact arc covers a full revolution.
	var o := _make_decaying()
	var segs: Array = OrbitalPath._build_decaying_segments(o)
	assert_true(segs.size() >= 3, "expected at least 3 segments")
	for i in range(1, segs.size() - 1):
		var seg: Dictionary = segs[i]
		var sweep: float = seg["nu_end"] - seg["nu_start"]
		assert_close(sweep, TAU, 1.0e-9)


func test_spiral_final_segment_meets_impact_altitude() -> void:
	# r evaluated at the final segment's end nu must equal the impact-altitude
	# radius (MASS_CENTER_RADIUS + 60 km for MassCenter defaults) — that is where the
	# renderer truncates the arc and where advance_time terminates the body.
	var o := _make_decaying()
	var segs: Array = OrbitalPath._build_decaying_segments(o)
	var last: Dictionary = segs[-1]
	var e: float = last["e"]
	var p_slr: float = last["p_slr"]
	var r_at_end: float = p_slr / (1.0 + e * cos(last["nu_end"]))
	var expected_impact_r: float = (
		MassCenterOrbit.MASS_CENTER_RADIUS_KM + maxf(MassCenterOrbit.SAFE_ORBIT_ALT_KM - 90.0, 0.0)
	)
	assert_close(r_at_end, expected_impact_r, 1.0e-3)


func test_spiral_segments_nest_inward() -> void:
	# Each successive full-ellipse segment must have a smaller apogee
	# than the previous — that's the literal "spiral in" property.
	var o := _make_decaying()
	var segs: Array = OrbitalPath._build_decaying_segments(o)
	var prev_r_a := INF
	for i in range(segs.size() - 1):  # exclude final partial
		var seg: Dictionary = segs[i]
		var a: float = seg["p_slr"] / (1.0 - seg["e"] * seg["e"])
		var r_a: float = a * (1.0 + seg["e"])
		assert_true(r_a <= prev_r_a + 1.0e-3,
			"segment %d r_a=%f exceeded previous %f" % [i, r_a, prev_r_a])
		prev_r_a = r_a


func test_decaying_eta_is_finite() -> void:
	# The whole point of the spiral-aware predictor: a decaying body that
	# the segmenter resolves to ground impact must report a finite ETA,
	# not INF. MassCenterOrbit.time_to_impact alone would return INF here
	# because the current orbit's r_p sits 500 km above the surface.
	var o := _make_decaying()
	var eta := OrbitalPath.decaying_time_to_impact(o)
	assert_finite(eta)
	assert_true(eta > 0.0, "expected positive ETA, got %f" % eta)


func test_decaying_eta_exceeds_initial_period() -> void:
	# Default decaying orbit takes 5 segments (initial inbound + 3 full
	# revs + final). The three middle segments are full revolutions of
	# successively smaller (faster) orbits, so the total ETA must comfort-
	# ably exceed the period of the very first orbit alone.
	var o := _make_decaying()
	var eta := OrbitalPath.decaying_time_to_impact(o)
	assert_true(eta > o.period,
		"expected eta=%f > initial period=%f" % [eta, o.period])


func test_decaying_eta_shrinks_after_perigee_burn() -> void:
	# A perigee burn collapses one full-revolution segment off the spiral,
	# so the spiral-aware ETA must drop monotonically with each burn.
	# This is what makes the path-color gradient ramp red as the body
	# closes on impact.
	var o := _make_decaying()
	var eta_before := OrbitalPath.decaying_time_to_impact(o)
	assert_true(_step_to_perigee(o, 20.0))
	var k := sqrt((o.r_p + o.r_a) / (2.0 * o.r_p + o.r_a))
	assert_true(o.maneuver(o.v * (k - 1.0), 0.0))
	var eta_after := OrbitalPath.decaying_time_to_impact(o)
	assert_finite(eta_after)
	assert_true(eta_after < eta_before,
		"expected post-burn eta=%f < pre-burn eta=%f" % [eta_after, eta_before])


func test_decaying_eta_matches_brute_force_propagation() -> void:
	# Cross-check the segment-walk ETA against a brute-force replay that
	# propagates the orbit forward in small steps and fires a burn at
	# every detected perigee crossing — same dynamics Satellite.advance_
	# time runs at simulation time. The two answers won't agree exactly:
	# each brute-force burn fires up to one step past true perigee with
	# a small residual radial velocity, scaling non-tangentially and
	# shifting the resulting orbit's geometry slightly. Across 4 burns
	# the drift compounds to ~1% of the total ETA. The Kepler sum
	# remains the right model for the path-color gradient — it tells
	# the operator "roughly when this thing impacts" — and the test
	# guards against gross errors (wrong segment count, missed cycle,
	# integration sign flip) rather than millisecond agreement.
	var o := _make_decaying()
	var eta_pred := OrbitalPath.decaying_time_to_impact(o)
	assert_finite(eta_pred)
	var sim := MassCenterOrbit.new(o.r, o.v)
	var dt := 1.0
	var elapsed := 0.0
	var horizon := eta_pred + 2.0 * o.period
	while elapsed < horizon:
		var rdv_before: float = sim.r.dot(sim.v)
		if not sim.propagate(dt):
			fail("brute-force propagation failed at t=%f" % elapsed)
			return
		elapsed += dt
		if rdv_before < 0.0 and sim.r.dot(sim.v) > 0.0:
			var k := sqrt((sim.r_p + sim.r_a) / (2.0 * sim.r_p + sim.r_a))
			if not sim.maneuver(sim.v * (k - 1.0), 0.0):
				fail("brute-force perigee burn failed at t=%f" % elapsed)
				return
		var impact_r: float = (
			MassCenterOrbit.MASS_CENTER_RADIUS_KM
			+ maxf(MassCenterOrbit.SAFE_ORBIT_ALT_KM - 90.0, 0.0)
		)
		if sim.norm_r <= impact_r:
			break
		var crossed := rdv_before < 0.0 and sim.r.dot(sim.v) > 0.0
		var sub_impact := (
			is_finite(sim.r_p) and sim.r_p <= impact_r
		)
		if crossed and sub_impact:
			break
	# 2% relative tolerance (with a 60 s floor for short ETAs) covers
	# the compounded geometric drift across the spiral's perigee burns
	# — the agreement is "same trajectory, ~1% wall-clock skew", which
	# is well inside what the gradient color needs.
	var tol: float = maxf(60.0, eta_pred * 0.02)
	assert_close(eta_pred, elapsed, tol)
