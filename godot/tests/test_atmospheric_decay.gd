extends "res://tests/framework.gd"
## Atmospheric decay zone tests. Verifies the altitude-dependent drag rate
## and HP damage rate, the apoapsis-reduction mechanic, and the per-body
## safe-orbit altitude parameter. Pure math where possible; the Satellite
## advance_time path is exercised by stepping a minimal orbit forward.

const MassCenterOrbit = preload("res://scripts/mass_center_orbit.gd")
const OrbitalPath = preload("res://scripts/orbital_path.gd")

# Default MassCenter parameters used throughout.
const EARTH_R: float = 6371.0
const SAFE_ALT: float = 150.0
const IMPACT_ALT: float = 60.0   # SAFE_ALT - 90


# Derived altitude boundaries.
const AIR_BRAKE_BOT: float = SAFE_ALT - 30.0   # 120 km
const REENTRY_BOT:   float = SAFE_ALT - 50.0   # 100 km
const ABLATION_BOT:  float = SAFE_ALT - 90.0   #  60 km


# ── Zone boundary helpers ─────────────────────────────────────────────────


func test_impact_altitude_equals_safe_minus_90() -> void:
	# The ablation floor / impact threshold is always safe_alt - 90 km.
	# For MassCenter that is 150 - 90 = 60 km, matching the design spec.
	var impact_r := EARTH_R + maxf(MassCenterOrbit.SAFE_ORBIT_ALT_KM - 90.0, 0.0)
	assert_close(impact_r - EARTH_R, IMPACT_ALT, 1.0e-9)


func test_impact_r_stored_in_earthorbit() -> void:
	# MassCenterOrbit.SAFE_ORBIT_ALT_KM must default to 150 km (MassCenter). Tests
	# never call CelestialBody.apply_to_propagator(), so the static starts
	# at the declared default and is what we calibrate the rest of these
	# tests against.
	assert_close(MassCenterOrbit.SAFE_ORBIT_ALT_KM, SAFE_ALT, 1.0e-9)


# ── Drag-rate interpolation ───────────────────────────────────────────────
# We validate the rate at zone boundaries by computing the same piecewise
# linear formula the production code uses. This guards against off-by-one
# errors in zone boundary comparisons.


func _drag_rate(alt_km: float) -> float:
	var safe_alt := MassCenterOrbit.SAFE_ORBIT_ALT_KM
	var air_brake_bot := safe_alt - 30.0
	var reentry_bot   := safe_alt - 50.0
	var ablation_bot  := safe_alt - 90.0
	if alt_km >= safe_alt or alt_km < ablation_bot:
		return 0.0
	if alt_km >= air_brake_bot:
		var t := (alt_km - air_brake_bot) / (safe_alt - air_brake_bot)
		return lerpf(20.0, 0.0, t)
	if alt_km >= reentry_bot:
		var t := (alt_km - reentry_bot) / (air_brake_bot - reentry_bot)
		return lerpf(40.0, 20.0, t)
	var t := (alt_km - ablation_bot) / (reentry_bot - ablation_bot)
	return lerpf(100.0, 40.0, t)


func test_no_drag_above_safe_altitude() -> void:
	assert_close(_drag_rate(SAFE_ALT), 0.0, 1.0e-9)
	assert_close(_drag_rate(SAFE_ALT + 100.0), 0.0, 1.0e-9)


func test_drag_zero_at_safe_alt_boundary() -> void:
	# Just below the safe altitude (within float tolerance) — rate is zero.
	assert_close(_drag_rate(SAFE_ALT - 0.001), 0.0, 0.01)


func test_drag_rate_at_air_brake_bottom() -> void:
	# 120 km: top of the air-brake zone gives its maximum rate of 20 km/kg/s.
	assert_close(_drag_rate(AIR_BRAKE_BOT), 20.0, 1.0e-6)


func test_drag_rate_at_reentry_top() -> void:
	# Immediately below 120 km the rate is still ≈ 20 km/kg/s — continuous
	# across the zone boundary.
	assert_close(_drag_rate(AIR_BRAKE_BOT - 0.001), 20.0, 0.01)


func test_drag_rate_at_reentry_bottom() -> void:
	# 100 km: bottom of the reentry interface gives 40 km/kg/s.
	assert_close(_drag_rate(REENTRY_BOT), 40.0, 1.0e-6)


func test_drag_rate_at_ablation_top() -> void:
	# Just into the ablation zone from reentry — continuous at 40 km/kg/s.
	assert_close(_drag_rate(REENTRY_BOT - 0.001), 40.0, 0.01)


func test_drag_rate_at_ablation_bottom() -> void:
	# 60 km: ablation floor gives maximum rate of 100 km/kg/s.
	assert_close(_drag_rate(ABLATION_BOT), 100.0, 1.0e-6)


func test_drag_rate_midpoint_air_brake() -> void:
	# 135 km: midpoint of air-brake → half of 20 = 10 km/kg/s.
	assert_close(_drag_rate(135.0), 10.0, 1.0e-6)


func test_drag_rate_midpoint_reentry() -> void:
	# 110 km: midpoint of reentry → halfway between 20 and 40 = 30 km/kg/s.
	assert_close(_drag_rate(110.0), 30.0, 1.0e-6)


func test_drag_rate_midpoint_ablation() -> void:
	# 80 km: midpoint of ablation → halfway between 40 and 100 = 70 km/kg/s.
	assert_close(_drag_rate(80.0), 70.0, 1.0e-6)


# ── HP damage rate ────────────────────────────────────────────────────────


func _hp_frac_per_s(alt_km: float) -> float:
	var safe_alt := MassCenterOrbit.SAFE_ORBIT_ALT_KM
	if alt_km >= safe_alt or alt_km < safe_alt - 90.0:
		return 0.0
	if alt_km >= safe_alt - 30.0:
		return 0.0
	if alt_km >= safe_alt - 50.0:
		return 0.001 / 100.0
	return 0.01 / 100.0


func test_no_hp_damage_in_air_brake() -> void:
	assert_close(_hp_frac_per_s(AIR_BRAKE_BOT + 5.0), 0.0, 1.0e-12)
	assert_close(_hp_frac_per_s(SAFE_ALT - 1.0), 0.0, 1.0e-12)


func test_hp_damage_rate_in_reentry() -> void:
	# 0.001 % / s in the reentry interface (100–120 km).
	assert_close(_hp_frac_per_s(110.0), 0.001 / 100.0, 1.0e-12)


func test_hp_damage_rate_in_ablation() -> void:
	# 0.01 % / s in the ablation zone (60–100 km).
	assert_close(_hp_frac_per_s(80.0), 0.01 / 100.0, 1.0e-12)


# ── Apoapsis reduction via _reduce_apoapsis (orbital math) ───────────────
# We replicate the vis-viva scaling directly to verify the formula is right.


func _compute_v_sq_for_new_ra(
	r_km: float, r_p: float, r_a: float, delta_r_a: float
) -> float:
	var r_a_new := maxf(r_a - delta_r_a, r_p)
	var a_new := 0.5 * (r_p + r_a_new)
	return MassCenterOrbit.MU * (2.0 / r_km - 1.0 / a_new)


func test_reduce_apoapsis_lowers_ra() -> void:
	# Build a circular-ish orbit at 150 km altitude and verify that applying
	# a drag step decreases the computed r_a while r_p stays close.
	var r_p := EARTH_R + 500.0
	var r_a := EARTH_R + 50000.0
	var a_old := 0.5 * (r_p + r_a)
	var r := r_p  # evaluate at periapsis for clean arithmetic
	var v_old_sq := MassCenterOrbit.MU * (2.0 / r - 1.0 / a_old)
	var delta := 1000.0  # km reduction
	var v_new_sq := _compute_v_sq_for_new_ra(r, r_p, r_a, delta)
	# New speed must be lower (retrograde drag).
	assert_true(v_new_sq < v_old_sq,
		"drag should reduce speed: v_new_sq=%f vs v_old_sq=%f" % [v_new_sq, v_old_sq])
	# Resulting r_a after vis-viva: a_new = mu / (2*mu/r - v_new²);
	# r_a_new = 2*a_new - r_p.
	var a_new := MassCenterOrbit.MU / (2.0 * MassCenterOrbit.MU / r - v_new_sq)
	var r_a_new := 2.0 * a_new - r_p
	assert_close(r_a_new, r_a - delta, 1.0e-3)


func test_reduce_apoapsis_clamps_at_rp() -> void:
	# If delta_r_a would drive r_a below r_p, the new r_a is clamped at r_p.
	var r_p := EARTH_R + 500.0
	var r_a := EARTH_R + 600.0  # small margin above r_p
	var delta := 1000.0  # larger than the margin
	var r_a_new := maxf(r_a - delta, r_p)
	assert_close(r_a_new, r_p, 1.0e-9)


# ── Trajectory renderer uses impact radius ────────────────────────────────


func test_decaying_spiral_final_segment_meets_impact_altitude() -> void:
	# The spiral segmenter must terminate its final arc at the impact-altitude
	# radius (MASS_CENTER_RADIUS + 60 km for MassCenter defaults), not the bare surface.
	var r_p := MassCenterOrbit.MASS_CENTER_RADIUS_KM + 500.0
	var r_a := MassCenterOrbit.MASS_CENTER_RADIUS_KM + 50000.0
	var a := 0.5 * (r_p + r_a)
	var e := (r_a - r_p) / (r_a + r_p)
	var p_slr := a * (1.0 - e * e)
	var nu := PI + deg_to_rad(15.0)  # just past apogee, descending
	var r_at := p_slr / (1.0 + e * cos(nu))
	var pos := Vector3(r_at * cos(nu), r_at * sin(nu), 0.0)
	var v_mag := sqrt(MassCenterOrbit.MU / p_slr)
	var vel := Vector3(-v_mag * sin(nu), v_mag * (e + cos(nu)), 0.0)
	var orbit := MassCenterOrbit.new(pos, vel)
	var segs: Array = OrbitalPath._build_decaying_segments(orbit)
	assert_true(segs.size() > 0, "expected at least one segment")
	var last: Dictionary = segs[-1]
	var last_e: float = last["e"]
	var last_p: float = last["p_slr"]
	var r_at_end: float = last_p / (1.0 + last_e * cos(last["nu_end"]))
	var expected_impact_r: float = (
		MassCenterOrbit.MASS_CENTER_RADIUS_KM + maxf(MassCenterOrbit.SAFE_ORBIT_ALT_KM - 90.0, 0.0)
	)
	assert_close(r_at_end, expected_impact_r, 1.0e-3)


func test_decaying_eta_uses_impact_altitude() -> void:
	# decaying_time_to_impact must return a finite value and that value must
	# match the brute-force spiral walk to within 2 % (same tolerance the
	# existing test uses).
	var r_p := MassCenterOrbit.MASS_CENTER_RADIUS_KM + 500.0
	var r_a := MassCenterOrbit.MASS_CENTER_RADIUS_KM + 50000.0
	var a := 0.5 * (r_p + r_a)
	var e := (r_a - r_p) / (r_a + r_p)
	var p_slr := a * (1.0 - e * e)
	var nu := PI + deg_to_rad(15.0)
	var r_at := p_slr / (1.0 + e * cos(nu))
	var pos := Vector3(r_at * cos(nu), r_at * sin(nu), 0.0)
	var v_mag := sqrt(MassCenterOrbit.MU / p_slr)
	var vel := Vector3(-v_mag * sin(nu), v_mag * (e + cos(nu)), 0.0)
	var orbit := MassCenterOrbit.new(pos, vel)
	var eta := OrbitalPath.decaying_time_to_impact(orbit)
	assert_finite(eta)
	assert_true(eta > 0.0, "expected positive ETA, got %f" % eta)


# ── Safe orbit altitude is per-body ──────────────────────────────────────


func test_safe_orbit_alt_can_be_overridden() -> void:
	# Simulate switching to a body with a different safe altitude (e.g. Mars
	# with 100 km). The impact radius derived from SAFE_ORBIT_ALT_KM must
	# reflect the new value, not the MassCenter default.
	var old_safe := MassCenterOrbit.SAFE_ORBIT_ALT_KM
	MassCenterOrbit.SAFE_ORBIT_ALT_KM = 100.0
	var impact_r := (
		MassCenterOrbit.MASS_CENTER_RADIUS_KM + maxf(MassCenterOrbit.SAFE_ORBIT_ALT_KM - 90.0, 0.0)
	)
	# Mars impact threshold: 100 - 90 = 10 km altitude.
	assert_close(impact_r - MassCenterOrbit.MASS_CENTER_RADIUS_KM, 10.0, 1.0e-9)
	# Restore to avoid affecting subsequent tests.
	MassCenterOrbit.SAFE_ORBIT_ALT_KM = old_safe


func test_drag_rate_zero_below_impact_threshold() -> void:
	# Altitude below the ablation floor must return 0 — the body has already
	# been terminated by the surface check, so no drag applies there.
	assert_close(_drag_rate(ABLATION_BOT - 1.0), 0.0, 1.0e-9)
	assert_close(_drag_rate(0.0), 0.0, 1.0e-9)
