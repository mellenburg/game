extends "res://tests/framework.gd"
## Decaying-orbit enemy tests. Pure-math: verify the geometry of the
## spawn orbit and the analytical apogee-burn that halves r_p. The
## Satellite-side detection (apogee crossing → burn) is exercised
## indirectly through the orbit it produces.

const EarthOrbit = preload("res://scripts/earth_orbit.gd")

const APOGEE_ALT_KM: float = 500.0
const PERIGEE_ALT_KM: float = 100.0
const INITIAL_NU_DEG: float = 15.0


# Build the same perifocal-state spawn orbit that EarthSystem uses.
# Equatorial / RAAN=0 / argp=0 to keep the geometry test-introspectable
# without dragging the rotation matrices in.
func _make_decaying() -> EarthOrbit:
	var r_p := EarthOrbit.EARTH_RADIUS_KM + PERIGEE_ALT_KM
	var r_a := EarthOrbit.EARTH_RADIUS_KM + APOGEE_ALT_KM
	var a := 0.5 * (r_p + r_a)
	var e := (r_a - r_p) / (r_a + r_p)
	var p_slr := a * (1.0 - e * e)
	var nu := deg_to_rad(INITIAL_NU_DEG)
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


func test_spawn_is_above_surface() -> void:
	# 15° past perigee with these altitudes leaves the spawn point well
	# above ground — if the constants are ever cranked toward higher
	# eccentricity, this guard catches a sub-surface spawn before it
	# becomes a soft crash in the propagator.
	var o := _make_decaying()
	assert_true(
		o.norm_r > EarthOrbit.EARTH_RADIUS_KM,
		"spawn r=%f below surface=%f" % [o.norm_r, EarthOrbit.EARTH_RADIUS_KM]
	)


func test_spawn_is_ascending() -> void:
	# Body must be moving outward toward apogee at spawn — otherwise the
	# apogee-burn detector (r·v sign flip) never fires.
	var o := _make_decaying()
	assert_true(o.r.dot(o.v) > 0.0, "spawn r·v=%f, expected > 0" % o.r.dot(o.v))


func test_spawn_true_anomaly_matches() -> void:
	var o := _make_decaying()
	assert_close(o.nu, deg_to_rad(INITIAL_NU_DEG), 1.0e-5)


func test_propagation_reaches_apogee() -> void:
	# Step through half a period; r·v must cross from positive to
	# negative once apogee is reached. A successful crossing detection
	# is the precondition for the satellite-side burn trigger.
	var o := _make_decaying()
	var crossed := false
	var dt := 10.0
	for _i in range(int(o.period / dt) + 5):
		var rdv_before: float = o.r.dot(o.v)
		assert_true(o.propagate(dt))
		var rdv_after: float = o.r.dot(o.v)
		if rdv_before > 0.0 and rdv_after < 0.0:
			crossed = true
			break
	assert_true(crossed, "ascending body never crossed apogee")


func test_apogee_burn_halves_perigee() -> void:
	# Analytical scale factor v_new/v_old = sqrt((r+r_p)/(2r+r_p)) at
	# apogee. Apply it and check the new orbit's r_p ≈ r_p/2.
	var o := _make_decaying()
	# Roll forward to apogee. r·v sign flip terminates the loop; using
	# a small step keeps us within ~ a step's worth of true anomaly past
	# the exact apogee point, where the analytic scaling is still valid.
	var dt := 5.0
	for _i in range(int(o.period / dt) + 5):
		var rdv_before: float = o.r.dot(o.v)
		assert_true(o.propagate(dt))
		if rdv_before > 0.0 and o.r.dot(o.v) < 0.0:
			break
	var r_p_before := o.r_p
	var r := o.norm_r
	var k := sqrt((r + r_p_before) / (2.0 * r + r_p_before))
	# maneuver(dv, t=0) → v += dv, recompute elements. Same call site
	# Satellite._apogee_decay_burn uses.
	assert_true(o.maneuver(o.v * (k - 1.0), 0.0))
	# Tolerance is loose because we burn slightly past apogee — the
	# velocity has a tiny radial component, so post-burn r_p is within
	# a few km of r_p/2 rather than exact.
	assert_close(o.r_p, r_p_before * 0.5, 5.0)


func test_post_burn_perigee_below_surface() -> void:
	# With apogee 500 km and perigee 100 km, halving r_p drops it to
	# ~3236 km — well below the surface, so the body's next perigee
	# pass impacts. Locks the gameplay invariant: one apogee burn is
	# enough for the body to leave play.
	var o := _make_decaying()
	var dt := 5.0
	for _i in range(int(o.period / dt) + 5):
		var rdv_before: float = o.r.dot(o.v)
		assert_true(o.propagate(dt))
		if rdv_before > 0.0 and o.r.dot(o.v) < 0.0:
			break
	var r_p_before := o.r_p
	var r := o.norm_r
	var k := sqrt((r + r_p_before) / (2.0 * r + r_p_before))
	assert_true(o.maneuver(o.v * (k - 1.0), 0.0))
	assert_true(
		o.r_p < EarthOrbit.EARTH_RADIUS_KM,
		"post-burn r_p=%f still above surface=%f" % [
			o.r_p, EarthOrbit.EARTH_RADIUS_KM
		]
	)
