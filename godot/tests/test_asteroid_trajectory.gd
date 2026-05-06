extends "res://tests/framework.gd"
## Asteroid trajectory tests. Pure-math: an asteroid is just an
## MassCenterOrbit whose periapsis is below MassCenter's surface. The Satellite
## entity keys ground-impact off the same propagator, so verifying the
## trajectory crosses the surface here covers the gameplay rule.

const MassCenterOrbit = preload("res://scripts/mass_center_orbit.gd")


func _make_inbound() -> MassCenterOrbit:
	# 5000 km altitude, 4 km/s radially inward, 0.5 km/s tangential.
	# Periapsis ~ tens of km — well below the surface.
	var r0 := Vector3(MassCenterOrbit.MASS_CENTER_RADIUS_KM + 5000.0, 0.0, 0.0)
	var v0 := Vector3(-4.0, 0.5, 0.0)
	return MassCenterOrbit.new(r0, v0)


func test_initial_state_valid() -> void:
	var o := _make_inbound()
	assert_true(o.is_state_valid())
	assert_finite(o.norm_r)


func test_periapsis_below_surface() -> void:
	# The defining property of an asteroid trajectory: closer approach
	# than MassCenter's radius, so propagation must eventually impact.
	var o := _make_inbound()
	assert_true(o.r_p < MassCenterOrbit.MASS_CENTER_RADIUS_KM)


func test_propagation_reaches_ground() -> void:
	var o := _make_inbound()
	var hit := false
	# 60 s steps, up to two hours. The trajectory's full period is ~106
	# minutes; we start past apoapsis on the inbound branch so impact
	# lands well inside this window.
	for _i in range(120):
		if not o.propagate(60.0):
			break
		if o.norm_r <= MassCenterOrbit.MASS_CENTER_RADIUS_KM:
			hit = true
			break
	assert_true(hit, "asteroid never crossed MassCenter surface")


func test_surface_crossing_anomaly_lies_on_ellipse() -> void:
	# The trajectory renderer needs to know at what true anomaly the
	# orbit dips through MassCenter's surface. r(nu) = p_slr / (1 + e*cos(nu))
	# evaluated at that nu must equal MASS_CENTER_RADIUS_KM exactly.
	var o := _make_inbound()
	var cos_nu_surf := (o.p_slr / MassCenterOrbit.MASS_CENTER_RADIUS_KM - 1.0) / o.ecc
	assert_true(cos_nu_surf >= -1.0 and cos_nu_surf <= 1.0)
	var nu_surf := acos(cos_nu_surf)
	var r_at := o.p_slr / (1.0 + o.ecc * cos(nu_surf))
	assert_close(r_at, MassCenterOrbit.MASS_CENTER_RADIUS_KM, 1.0e-3)


func test_inbound_nu_is_before_surface_nu() -> void:
	# Renderer assumes the body's current nu (negative for inbound,
	# branch-folded if needed) is "before" the surface-crossing nu —
	# i.e. nu_target = -nu_surf is greater than nu0. If this ordering
	# breaks the lerp would sweep the wrong arc.
	var o := _make_inbound()
	var nu0: float = o.nu
	if nu0 > 0.0:
		nu0 -= TAU
	var cos_nu_surf := (o.p_slr / MassCenterOrbit.MASS_CENTER_RADIUS_KM - 1.0) / o.ecc
	var nu_target := -acos(cos_nu_surf)
	assert_true(nu_target > nu0,
		"nu0=%f vs nu_target=%f" % [nu0, nu_target])


func test_tangential_only_does_not_impact() -> void:
	# Sanity check: a circular-ish orbit at the same altitude must NOT
	# trip the impact condition — we only want sub-orbital trajectories
	# to be flagged as asteroids.
	var radius := MassCenterOrbit.MASS_CENTER_RADIUS_KM + 5000.0
	var v_circ := sqrt(MassCenterOrbit.MU / radius)
	var o := MassCenterOrbit.new(
		Vector3(radius, 0.0, 0.0),
		Vector3(0.0, v_circ, 0.0),
	)
	for _i in range(60):
		assert_true(o.propagate(60.0))
		assert_true(o.norm_r > MassCenterOrbit.MASS_CENTER_RADIUS_KM)


func test_clamp_velocity_for_periapsis_pulls_flyby_into_impact() -> void:
	# Construction that mimics the asteroid spawner's worst case:
	# 50,000 km altitude, mostly inward, but with a tangential share
	# big enough to lift periapsis above the surface (a hyperbolic
	# flyby — the bug the clamp is here to fix).
	var pos := Vector3(MassCenterOrbit.MASS_CENTER_RADIUS_KM + 50000.0, 0.0, 0.0)
	var vel := Vector3(-5.0, 1.5, 0.3)
	var bad := MassCenterOrbit.new(pos, vel)
	assert_true(bad.r_p > MassCenterOrbit.MASS_CENTER_RADIUS_KM,
		"setup expected periapsis above surface, got r_p=%f" % bad.r_p)

	var target := MassCenterOrbit.MASS_CENTER_RADIUS_KM * 0.9
	var fixed_vel := MassCenterOrbit.clamp_velocity_for_periapsis(pos, vel, target)
	var fixed := MassCenterOrbit.new(pos, fixed_vel)
	assert_true(fixed.r_p <= target + 1.0e-3,
		"clamp left r_p=%f above target %f" % [fixed.r_p, target])
	# Radial component is preserved; only tangential is shrunk.
	var pos_hat := pos.normalized()
	assert_close(fixed_vel.dot(pos_hat), vel.dot(pos_hat), 1.0e-6)


func test_clamp_velocity_is_a_noop_when_already_below_target() -> void:
	# Already an asteroid (r_p well below surface) — clamp must not
	# perturb the orbit.
	var pos := Vector3(MassCenterOrbit.MASS_CENTER_RADIUS_KM + 50000.0, 0.0, 0.0)
	var vel := Vector3(-6.0, 0.4, 0.0)
	var before := MassCenterOrbit.new(pos, vel)
	assert_true(before.r_p < MassCenterOrbit.MASS_CENTER_RADIUS_KM)
	var clamped := MassCenterOrbit.clamp_velocity_for_periapsis(
		pos, vel, MassCenterOrbit.MASS_CENTER_RADIUS_KM * 0.9
	)
	assert_vec_close(clamped, vel, 1.0e-9)
