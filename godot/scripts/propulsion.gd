class_name Propulsion
extends RefCounted
## Pure rocket-science math: Tsiolkovsky and friends. RefCounted so it
## stays unit-testable without a SceneTree.
##
## Sign convention and units:
##   * Delta-v values returned by the cost / capacity helpers are in m/s,
##     because the orbital-mechanics literature tabulates manoeuvre costs
##     in m/s and the in-game player budget is denominated the same way.
##   * Propellant masses are in kg.
##   * Specific impulse Isp is in seconds.
##   * Internally, orbital radii are in km / km·s — same as EarthOrbit —
##     so this module reads EarthOrbit.MU and EarthOrbit.EARTH_RADIUS_KM
##     directly rather than redeclaring them.
##
## The two equations the rest of the game leans on:
##   1. Tsiolkovsky:           Δv = Isp · g0 · ln(m_wet / m_dry)
##      → propellant_for_dv_kg, dv_capacity_ms.
##   2. Plane change cost:     Δv = 2 v · sin(Δi/2)
##      → inclination_change_dv_ms.
##   plus the standard Hohmann transfer between two circular orbits.
##
## A "launch" in this module is the cost of placing a unit on its target
## orbit, *measured against the equatorial-LEO baseline*. Surface →
## equatorial-LEO at BASELINE_LEO_ALT_KM is treated as free; player pays
## only for inclination change and altitude differential. That keeps the
## launch budget intuitive (tilted / high orbits cost more) without
## charging the player for the ~9 km/s gravity-loss tax that every real
## payload pays the same way.

const EarthOrbit = preload("res://scripts/earth_orbit.gd")

# Standard gravity. Only ever appears as the "Isp · g0 → exhaust velocity"
# unit conversion; identical to the value Wikipedia and every aerospace
# textbook print so the rocket equation reads as expected.
const G0: float = 9.80665

# Free-launch baseline. Equatorial circular orbit at this altitude is the
# game's "you get this for free" reference state — Launch's setup cost
# is measured against it, so a launch configured at exactly (alt, inc) =
# (BASELINE_LEO_ALT_KM, 0) draws zero from the player's budget.
# 500 km matches SpawnDirector.STARTING_SAT_ALT_KM.
const BASELINE_LEO_ALT_KM: float = 500.0

# Reference Isp for the launch vehicle that places units in their
# starting orbit. Distinct from the unit's own onboard-thruster Isp:
# the launch budget pays for the ground-to-orbit booster, not the
# satellite's station-keeping engines. Kerolox-class so heavier units
# debit visibly more propellant from the budget than light ones.
const REF_LAUNCH_ISP_S: float = 350.0


# Circular-orbit speed at radius `radius_km`, in km/s. Returns 0 for a
# non-positive radius rather than NaN so callers can blindly multiply.
static func circular_speed_kms(radius_km: float) -> float:
	if radius_km <= 0.0:
		return 0.0
	return sqrt(EarthOrbit.MU / radius_km)


# Total Δv (m/s) for a Hohmann transfer between two circular orbits of
# radii r1_km and r2_km. Symmetric — caller doesn't have to put the
# smaller radius first; the formula sums the absolute burn magnitudes
# at each apsis. Returns 0 when the two radii match.
static func hohmann_dv_ms(r1_km: float, r2_km: float) -> float:
	if r1_km <= 0.0 or r2_km <= 0.0 or r1_km == r2_km:
		return 0.0
	var a_t := 0.5 * (r1_km + r2_km)
	var v1 := sqrt(EarthOrbit.MU / r1_km)
	var v2 := sqrt(EarthOrbit.MU / r2_km)
	var v_peri := sqrt(EarthOrbit.MU * (2.0 / r1_km - 1.0 / a_t))
	var v_apo := sqrt(EarthOrbit.MU * (2.0 / r2_km - 1.0 / a_t))
	# km/s -> m/s. The two burns are along (or against) the velocity
	# vector at each apsis, so the magnitudes add even when one of the
	# burns is a deceleration (transferring inward).
	return (absf(v_peri - v1) + absf(v2 - v_apo)) * 1000.0


# Cost (m/s) of a plane change of |delta_inc_rad| at orbital speed
# v_kms. Analytic: Δv = 2 v sin(Δi/2). Apex of the "inclination changes
# are expensive" rule the game wants the player to feel — at LEO speed
# (~7.7 km/s) a single degree costs ~135 m/s.
static func inclination_change_dv_ms(
	delta_inc_rad: float, v_kms: float
) -> float:
	return 2.0 * v_kms * sin(0.5 * absf(delta_inc_rad)) * 1000.0


# Total Δv (m/s) the launch budget owes for placing a unit at
# (target_alt_km, target_inc_rad), measured against the free
# equatorial-LEO baseline. Inclination is paid at the baseline orbital
# speed (the more expensive choice — combining plane change with the
# Hohmann apogee burn would be cheaper but adds a layer of physics the
# player doesn't need to reason about); altitude differential via
# Hohmann. The two costs sum: a polar GEO launch pays plane-change at
# LEO speed *plus* the LEO→GEO transfer.
static func launch_setup_dv_ms(
	target_alt_km: float, target_inc_rad: float
) -> float:
	var r_base := EarthOrbit.EARTH_RADIUS_KM + BASELINE_LEO_ALT_KM
	var r_target := EarthOrbit.EARTH_RADIUS_KM + target_alt_km
	var v_base := circular_speed_kms(r_base)
	var inc_dv := inclination_change_dv_ms(target_inc_rad, v_base)
	var alt_dv := hohmann_dv_ms(r_base, r_target)
	return inc_dv + alt_dv


# Tsiolkovsky propellant cost: kg of propellant burned to deliver
# `dv_ms` of delta-v to a stage with current wet mass `wet_mass_kg`,
# burning at exhaust velocity Isp · g0. Caps at wet_mass_kg — a Δv
# request that would require infinite mass ratio returns the entire
# wet mass (caller treats that as "tank empties before the burn
# completes" and clamps the achieved Δv accordingly).
static func propellant_for_dv_kg(
	dv_ms: float, wet_mass_kg: float, isp_s: float
) -> float:
	if dv_ms <= 0.0 or wet_mass_kg <= 0.0 or isp_s <= 0.0:
		return 0.0
	var v_e := isp_s * G0
	# 1 - exp(-x) clamps to 1 from below as x → ∞, so the result is
	# always ≤ wet_mass_kg.
	return wet_mass_kg * (1.0 - exp(-dv_ms / v_e))


# Inverse of propellant_for_dv_kg: Δv (m/s) a stage carrying
# `propellant_kg` of fuel above `dry_mass_kg` of structure can deliver
# at exhaust velocity Isp · g0. Returns 0 when any input is degenerate
# so callers can blindly compare to a desired Δv.
static func dv_capacity_ms(
	propellant_kg: float, dry_mass_kg: float, isp_s: float
) -> float:
	if propellant_kg <= 0.0 or dry_mass_kg <= 0.0 or isp_s <= 0.0:
		return 0.0
	var v_e := isp_s * G0
	return v_e * log((dry_mass_kg + propellant_kg) / dry_mass_kg)
