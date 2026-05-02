extends "res://tests/framework.gd"
## Coverage for the Propulsion pure-math module and the propulsion-aware
## bookkeeping layered onto Satellite, Launch, UnitConfig, and
## PlayerLoadout. Pins the rocket-science contract the rest of the game
## relies on:
##   * Tsiolkovsky round-trips between propellant kg and Δv m/s.
##   * Inclination changes cost ~135 m/s/deg at LEO.
##   * Hohmann LEO→GEO totals ~3.9 km/s.
##   * Equatorial-LEO baseline launch is free.
##   * Heavier units debit the launch budget more for the same orbit.

const Propulsion = preload("res://scripts/propulsion.gd")
const Satellite = preload("res://scripts/satellite.gd")
const EarthOrbit = preload("res://scripts/earth_orbit.gd")
const UnitConfig = preload("res://scripts/unit_config.gd")
const UnitPart = preload("res://scripts/unit_part.gd")
const Launch = preload("res://scripts/launch.gd")


func test_tsiolkovsky_round_trip() -> void:
	# Burn enough propellant to deliver a known Δv, then ask the
	# capacity helper how much Δv the *remaining* tank still has — it
	# should equal the unspent portion. Catches a sign/log error in
	# either helper without needing a separate analytic check.
	var dry := 700.0
	var prop := 300.0
	var isp := 300.0
	var total_dv := Propulsion.dv_capacity_ms(prop, dry, isp)
	var burn_dv := 0.4 * total_dv
	var burned := Propulsion.propellant_for_dv_kg(burn_dv, dry + prop, isp)
	assert_close(
		Propulsion.dv_capacity_ms(prop - burned, dry, isp),
		total_dv - burn_dv,
		1.0e-4,
	)


func test_dv_capacity_zero_when_tank_empty() -> void:
	assert_close(Propulsion.dv_capacity_ms(0.0, 700.0, 300.0), 0.0)


func test_propellant_capped_at_wet_mass() -> void:
	# A Δv request that exceeds Isp · g0 · ln(∞) is physically
	# impossible — the propellant helper saturates at wet mass rather
	# than returning more fuel than the stage carries.
	var huge_dv := 1.0e9
	var wet := 1500.0
	var burned := Propulsion.propellant_for_dv_kg(huge_dv, wet, 300.0)
	assert_true(burned <= wet)
	assert_close(burned, wet, 1.0e-3)


func test_inclination_change_per_degree_at_leo() -> void:
	# At ~7.61 km/s (500 km LEO), one degree of plane change costs
	# ~133 m/s. Tolerance is generous because the analytic formula is
	# exact but small-angle approximations differ by < 1%.
	var v_leo := Propulsion.circular_speed_kms(
		EarthOrbit.EARTH_RADIUS_KM + 500.0
	)
	var dv := Propulsion.inclination_change_dv_ms(deg_to_rad(1.0), v_leo)
	assert_close(dv, 133.0, 2.0)


func test_hohmann_leo_to_geo_total_dv() -> void:
	# LEO 200 km → GEO 35786 km. Wikipedia tables this at ~3.9 km/s
	# total (~2.44 km/s perigee + ~1.47 km/s apogee). Tolerance allows
	# small drift across the gravitational-parameter convention.
	var r_leo := EarthOrbit.EARTH_RADIUS_KM + 200.0
	var r_geo := EarthOrbit.EARTH_RADIUS_KM + 35786.0
	var dv := Propulsion.hohmann_dv_ms(r_leo, r_geo)
	assert_close(dv, 3900.0, 50.0)


func test_hohmann_symmetric() -> void:
	var r_low := EarthOrbit.EARTH_RADIUS_KM + 500.0
	var r_high := EarthOrbit.EARTH_RADIUS_KM + 20000.0
	assert_close(
		Propulsion.hohmann_dv_ms(r_low, r_high),
		Propulsion.hohmann_dv_ms(r_high, r_low),
	)


func test_baseline_equatorial_leo_launch_is_free() -> void:
	# A launch at exactly the baseline orbit costs zero — equatorial
	# LEO is the "free" reference state for the launch budget.
	assert_close(
		Propulsion.launch_setup_dv_ms(Propulsion.BASELINE_LEO_ALT_KM, 0.0),
		0.0,
	)


func test_polar_leo_costs_only_inclination() -> void:
	# Polar at the baseline altitude pays only the plane-change
	# component (Hohmann to the same radius is zero). Cross-checks
	# that launch_setup_dv_ms decomposes correctly.
	var pure_inc := Propulsion.launch_setup_dv_ms(
		Propulsion.BASELINE_LEO_ALT_KM, deg_to_rad(90.0)
	)
	var v_base := Propulsion.circular_speed_kms(
		EarthOrbit.EARTH_RADIUS_KM + Propulsion.BASELINE_LEO_ALT_KM
	)
	var expected := Propulsion.inclination_change_dv_ms(
		deg_to_rad(90.0), v_base
	)
	assert_close(pure_inc, expected)


func test_launch_propellant_scales_with_unit_mass() -> void:
	# Same orbit, two stages of different wet mass: heavier stage
	# debits more propellant. Specifically the rocket equation is
	# linear in wet mass, so doubling the stage doubles the cost
	# (within rounding).
	var setup_dv := Propulsion.launch_setup_dv_ms(
		Propulsion.BASELINE_LEO_ALT_KM, deg_to_rad(30.0)
	)
	var light := Propulsion.propellant_for_dv_kg(
		setup_dv, 1000.0, Propulsion.REF_LAUNCH_ISP_S
	)
	var heavy := Propulsion.propellant_for_dv_kg(
		setup_dv, 2000.0, Propulsion.REF_LAUNCH_ISP_S
	)
	assert_close(heavy, 2.0 * light, 1.0e-6)


func test_unit_config_thruster_summary() -> void:
	# Default chassis with the default thruster part exposes the
	# catalog's facets through the summary stats Dictionary the menu
	# renders. Pinning these here so a future tweak to the default
	# tier is visible.
	var u := UnitConfig.make_default("U-1", "T-01")
	var s := u.summary_stats()
	assert_close(float(s["thrust_n"]), 20000.0)
	assert_close(float(s["isp_s"]), 300.0)
	assert_close(float(s["propellant_capacity_kg"]), 300.0)
	# Δv capacity = Isp · g0 · ln((dry + prop) / dry).
	# For dry=700, prop=300, Isp=300: 300 · 9.80665 · ln(1000/700)
	# ≈ 1049 m/s. Tolerance generous to absorb constant tweaks.
	assert_close(float(s["delta_v_capacity_ms"]), 1049.0, 5.0)


func test_unit_config_advanced_thruster_doubles_capacity() -> void:
	var u := UnitConfig.make_default("U-1", "T-01")
	u.set_part_id(UnitPart.KIND_THRUSTER, 0, "thruster_advanced")
	var s := u.summary_stats()
	assert_close(float(s["thrust_n"]), 40000.0)
	assert_close(float(s["isp_s"]), 450.0)
	assert_close(float(s["propellant_capacity_kg"]), 600.0)


func test_satellite_burn_consumes_propellant() -> void:
	# Queue a maneuver, advance one tick, verify propellant dropped
	# by the Tsiolkovsky-predicted amount and `mass` tracked it. The
	# DELTA_V_MAGNITUDE constant (50 m/s per tick) lands well below
	# the default tank's capacity, so the burn applies in full and
	# we can predict the exact debit.
	var sat: Satellite = Satellite.new()
	var initial_prop: float = sat.propellant_kg
	var initial_mass: float = sat.mass
	# Pure prograde (+x in the local frame).
	sat.set_maneuver(Vector3(1.0, 0.0, 0.0))
	sat.advance_time(0.0)  # zero-duration tick still applies the burn
	var dv_ms: float = Satellite.DELTA_V_MAGNITUDE * 1000.0
	var expected_burn := Propulsion.propellant_for_dv_kg(
		dv_ms, initial_mass, sat.isp_s
	)
	assert_close(sat.propellant_kg, initial_prop - expected_burn, 1.0e-4)
	assert_close(sat.mass, sat.dry_mass_kg + sat.propellant_kg, 1.0e-6)
	sat.queue_free()


func test_satellite_clamps_burn_when_tank_empty() -> void:
	# A satellite whose tank is empty should not move when the
	# operator holds thrust — the maneuver branch zeros out the
	# applied dv rather than letting it through unpaid.
	var sat: Satellite = Satellite.new()
	sat.propellant_kg = 0.0
	sat.mass = sat.dry_mass_kg
	var v_before := sat.orbit.v
	sat.set_maneuver(Vector3(1.0, 0.0, 0.0))
	sat.advance_time(0.0)
	# v unchanged — relative_maneuver was called with Vector3.ZERO
	# (or skipped entirely on the early-return path).
	assert_vec_close(sat.orbit.v, v_before, 1.0e-9)
	assert_close(sat.propellant_kg, 0.0)
	sat.queue_free()


func test_launch_setup_dv_helpers() -> void:
	# Pinning the Launch class's own helpers as the surface external
	# callers (PlayerLoadout, the menu) will use. setup_dv_ms() should
	# match Propulsion.launch_setup_dv_ms() exactly; propellant_cost
	# should match Tsiolkovsky for the supplied wet mass.
	var l := Launch.new()
	l.altitude_km = 1000.0
	l.inclination_deg = 30.0
	var dv := l.setup_dv_ms()
	assert_close(
		dv,
		Propulsion.launch_setup_dv_ms(1000.0, deg_to_rad(30.0)),
	)
	var cost := l.propellant_cost_kg(1500.0)
	assert_close(
		cost,
		Propulsion.propellant_for_dv_kg(
			dv, 1500.0, Propulsion.REF_LAUNCH_ISP_S
		),
	)
