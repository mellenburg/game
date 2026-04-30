extends "res://tests/framework.gd"
## Meteorite trajectory tests. Pure-math: a meteorite is just an
## EarthOrbit whose periapsis is below Earth's surface. The Satellite
## entity keys ground-impact off the same propagator, so verifying the
## trajectory crosses the surface here covers the gameplay rule.

const EarthOrbit = preload("res://scripts/earth_orbit.gd")


func _make_inbound() -> EarthOrbit:
	# 5000 km altitude, 4 km/s radially inward, 0.5 km/s tangential.
	# Periapsis ~ tens of km — well below the surface.
	var r0 := Vector3(EarthOrbit.EARTH_RADIUS_KM + 5000.0, 0.0, 0.0)
	var v0 := Vector3(-4.0, 0.5, 0.0)
	return EarthOrbit.new(r0, v0)


func test_initial_state_valid() -> void:
	var o := _make_inbound()
	assert_true(o.is_state_valid())
	assert_finite(o.norm_r)


func test_periapsis_below_surface() -> void:
	# The defining property of a meteorite trajectory: closer approach
	# than Earth's radius, so propagation must eventually impact.
	var o := _make_inbound()
	assert_true(o.r_p < EarthOrbit.EARTH_RADIUS_KM)


func test_propagation_reaches_ground() -> void:
	var o := _make_inbound()
	var hit := false
	# 60 s steps, up to two hours. The trajectory's full period is ~106
	# minutes; we start past apoapsis on the inbound branch so impact
	# lands well inside this window.
	for _i in range(120):
		if not o.propagate(60.0):
			break
		if o.norm_r <= EarthOrbit.EARTH_RADIUS_KM:
			hit = true
			break
	assert_true(hit, "meteorite never crossed Earth surface")


func test_tangential_only_does_not_impact() -> void:
	# Sanity check: a circular-ish orbit at the same altitude must NOT
	# trip the impact condition — we only want sub-orbital trajectories
	# to be flagged as meteorites.
	var radius := EarthOrbit.EARTH_RADIUS_KM + 5000.0
	var v_circ := sqrt(EarthOrbit.MU / radius)
	var o := EarthOrbit.new(
		Vector3(radius, 0.0, 0.0),
		Vector3(0.0, v_circ, 0.0),
	)
	for _i in range(60):
		assert_true(o.propagate(60.0))
		assert_true(o.norm_r > EarthOrbit.EARTH_RADIUS_KM)
