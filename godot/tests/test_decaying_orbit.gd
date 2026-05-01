extends "res://tests/framework.gd"
## Decaying-orbit enemy tests. Pure-math: verify the spawn geometry
## (near apogee, descending) and the analytical perigee-burn that
## halves r_a. The Satellite-side detection (perigee crossing → burn)
## is exercised indirectly through the orbit it produces.

const EarthOrbit = preload("res://scripts/earth_orbit.gd")

const APOGEE_ALT_KM: float = 50000.0
const PERIGEE_ALT_KM: float = 500.0
const INITIAL_NU_FROM_APOGEE_DEG: float = 15.0


# Build the same spawn orbit EarthSystem uses. RAAN = inc = argp = 0
# so the perifocal frame coincides with ECI x/y, keeping the geometry
# test-introspectable without dragging in the rotation matrices.
func _make_decaying() -> EarthOrbit:
	var r_p := EarthOrbit.EARTH_RADIUS_KM + PERIGEE_ALT_KM
	var r_a := EarthOrbit.EARTH_RADIUS_KM + APOGEE_ALT_KM
	var a := 0.5 * (r_p + r_a)
	var e := (r_a - r_p) / (r_a + r_p)
	var p_slr := a * (1.0 - e * e)
	var nu := PI + deg_to_rad(INITIAL_NU_FROM_APOGEE_DEG)
	var r_at := p_slr / (1.0 + e * cos(nu))
	var pos := Vector3(r_at * cos(nu), r_at * sin(nu), 0.0)
	var v_mag := sqrt(EarthOrbit.MU / p_slr)
	var vel := Vector3(-v_mag * sin(nu), v_mag * (e + cos(nu)), 0.0)
	return EarthOrbit.new(pos, vel)


func test_apogee_matches_spec() -> void:
	var o := _make_decaying()
	assert_close(o.r_a, EarthOrbit.EARTH_RADIUS_KM + APOGEE_ALT_KM, 1.0e-2)


func test_perigee_matches_spec() -> void:
	var o := _make_decaying()
	assert_close(o.r_p, EarthOrbit.EARTH_RADIUS_KM + PERIGEE_ALT_KM, 1.0e-2)


func test_spawn_is_near_apogee() -> void:
	# 15° past apogee on a highly eccentric ellipse leaves the body deep
	# in the upper half of the orbit — well above perigee, well above
	# the surface, so the player has visible time to engage before the
	# first perigee burn.
	var o := _make_decaying()
	assert_true(
		o.norm_r > EarthOrbit.EARTH_RADIUS_KM + 0.5 * APOGEE_ALT_KM,
		"spawn r=%f, expected near apogee" % o.norm_r
	)


func test_spawn_is_descending() -> void:
	# Body must be moving inward toward perigee at spawn — the perigee-
	# burn detector keys off the descending → ascending r·v sign flip,
	# so an ascending spawn would never trigger the first burn.
	var o := _make_decaying()
	assert_true(o.r.dot(o.v) < 0.0, "spawn r·v=%f, expected < 0" % o.r.dot(o.v))


func _step_to_perigee(o: EarthOrbit, dt: float) -> bool:
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
		# Either apsis dipping below the surface counts as terminal —
		# update_trajectory in OrbitalPath kicks in for the inbound
		# leg, and Satellite.advance_time kills the body on the
		# surface crossing.
		if (
			(is_finite(o.r_p) and o.r_p < EarthOrbit.EARTH_RADIUS_KM)
			or (is_finite(o.r_a) and o.r_a < EarthOrbit.EARTH_RADIUS_KM)
		):
			return
	fail("orbit never spiraled below the surface after 6 perigee burns")
