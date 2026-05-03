extends "res://tests/framework.gd"
## Energy / ammo / mass coverage for the joule-and-watt weapon model.
## Pins the physical constants the design discussion settled on so a
## drift in any of them shows up loud in CI:
##   * MJ_PER_HP = 5 (single global damage scale)
##   * Slug: 20 kg @ 10 km/s ⇒ 1 GJ KE, 200 kg·km/s momentum, 1000-round
##     magazine ⇒ 20 t of ammo at full load
##   * Laser: 100 MW radiated, 30% wall-plug, 40% target coupling
##   * Default sat: 10 GJ pool, 1 GW reactor

const Weapon = preload("res://scripts/weapons/weapon.gd")
const RailgunWeapon = preload("res://scripts/weapons/railgun_weapon.gd")
const LaserWeapon = preload("res://scripts/weapons/laser_weapon.gd")
const Satellite = preload("res://scripts/satellite.gd")
const EarthOrbit = preload("res://scripts/earth_orbit.gd")

const EARTH_RADIUS_KM: float = EarthOrbit.EARTH_RADIUS_KM


# Same fake-satellite shape the railgun test uses. Energy starts at a
# full default pool; mass is loaded explicitly per test (the no-method
# guard in RailgunWeapon.fire keeps the fake's mass static, which is
# what the per-shot Δv tests want).
class FakeSat extends RefCounted:
	var orbit: EarthOrbit
	var team: int = 0
	var alive: bool = true
	var orbit_alive: bool = true
	var hp: float = 100.0
	var energy: float = 1.0e10
	var mass: float = 1000.0
	var max_orbital_radius_km: float = 50000.0
	var railgun_enabled: bool = true
	var is_surface: bool = false

	func take_damage(amount: float, _attacker = null) -> bool:
		hp = maxf(hp - amount, 0.0)
		if hp <= 0.0:
			alive = false
			return true
		return false

	func invalidate_impact_cache() -> void:
		pass


func _make_player() -> FakeSat:
	var s := FakeSat.new()
	s.team = 0
	var radius: float = EARTH_RADIUS_KM + 5000.0
	var v_circ := sqrt(EarthOrbit.MU / radius)
	s.orbit = EarthOrbit.new(
		Vector3(radius, 0.0, 0.0), Vector3(0.0, v_circ, 0.0),
	)
	return s


func _make_enemy() -> FakeSat:
	var s := FakeSat.new()
	s.team = 1
	var radius: float = EARTH_RADIUS_KM + 5000.0
	var v_circ := sqrt(EarthOrbit.MU / radius)
	s.orbit = EarthOrbit.new(
		Vector3(radius, 3000.0, 0.0), Vector3(0.0, 0.0, v_circ),
	)
	return s


func test_global_mj_per_hp_is_five() -> void:
	# The single damage scaling knob the design discussion fixed at 5
	# MJ/HP. Pinning it here so a future tweak is loud (every weapon
	# rebalances against this).
	assert_close(Weapon.MJ_PER_HP, 5.0)
	assert_close(Weapon.J_PER_HP, 5.0e6)


func test_slug_kinetic_energy_matches_design() -> void:
	# 20 kg slug at 10 km/s ⇒ ½·m·v² = 0.5 × 20 × 10000² = 10^9 J.
	# Pinning so a future muzzle-velocity tweak shows up as a test
	# regression rather than silent rebalancing of every weapon's
	# damage curve.
	assert_close(RailgunWeapon.SLUG_MASS_KG, 20.0)
	assert_close(RailgunWeapon.MUZZLE_VELOCITY_M_S, 10000.0)
	assert_close(RailgunWeapon.SLUG_MUZZLE_KE_J, 1.0e9, 1.0)
	# Momentum is the SI product divided by 1000 to match the orbit
	# layer's km/s convention. 200 kg·km/s is the same number the
	# pre-physical balance pass shipped with — recoil gameplay is
	# preserved across the unit conversion.
	assert_close(RailgunWeapon.SLUG_MOMENTUM_KG_KM_S, 200.0)


func test_railgun_default_damage_matches_physics() -> void:
	# damage = KE × coupling / J_PER_HP = 1e9 × 0.5 / 5e6 = 100 HP.
	# A default-tier shot one-shots a default 100-HP target, which is
	# the user-confirmed design intent (kinetics are the alpha-strike).
	assert_close(RailgunWeapon.base_damage_per_shot(), 100.0)


func test_railgun_default_pool_draw_is_three_point_three_gj() -> void:
	# Wall-plug: KE / 0.3 = ~3.33 GJ. One shot drains a third of a
	# default 10 GJ pool — the energy-budget mechanic the design hinges
	# on. Tolerance is 1 J against billions, comfortably tight.
	assert_close(RailgunWeapon.ENERGY_PER_SHOT_J, 1.0e9 / 0.3, 1.0)


func test_railgun_default_magazine_is_one_thousand() -> void:
	assert_eq(RailgunWeapon.MAGAZINE_SIZE, 1000)
	var w := RailgunWeapon.new()
	assert_eq(w.ammo_count, 1000)


func test_laser_default_dps_at_zero_range_matches_physics() -> void:
	# 100 MW × 0.4 / 5e6 = 8 HP/sec. The "lasers are the slow attrition
	# weapon" balance the design discussion picked.
	assert_close(
		LaserWeapon.base_damage_per_second_at_zero_range(), 8.0, 1.0e-6,
	)


func test_laser_default_pool_drain_is_three_hundred_thirty_three_mw() -> void:
	# 100 MW radiated / 0.3 wall-plug = ~333 MW drawn from the bus.
	# A 1 GW reactor sustains roughly three lasers concurrent.
	assert_close(LaserWeapon.POOL_DRAIN_W, 1.0e8 / 0.3, 1.0)


func test_satellite_default_pool_and_reactor_match_design() -> void:
	# 10 GJ / 1 GW: from the design discussion. Refill from empty
	# takes 10 sim-sec — ~3 railgun shots' worth of energy bookkeeping.
	assert_close(Satellite.DEFAULT_ENERGY_MAX_J, 1.0e10, 1.0)
	assert_close(Satellite.DEFAULT_REACTOR_POWER_W, 1.0e9, 1.0)


func test_railgun_refuses_fire_when_magazine_empty() -> void:
	# Drain the magazine to zero and confirm can_fire / fire both
	# refuse. The cool / energy gates are independent of ammo, so this
	# isolates the "no rounds in the chamber" refusal.
	var w := RailgunWeapon.new()
	w.ammo_count = 0
	var attacker := _make_player()
	assert_false(w.can_fire(attacker))
	var target := _make_enemy()
	assert_false(w.fire(attacker, target, 1.0))


func test_railgun_fire_decrements_ammo() -> void:
	var w := RailgunWeapon.new()
	var attacker := _make_player()
	var target := _make_enemy()
	var ammo_before := w.ammo_count
	assert_true(w.fire(attacker, target, 1.0))
	assert_eq(w.ammo_count, ammo_before - 1)


func test_satellite_full_loadout_mass_includes_ammo() -> void:
	# Default Satellite._init builds [Laser, Laser, Railgun] and calls
	# recompute_mass(). With a default 700 kg dry + 300 kg propellant
	# + 20 t magazine the wet mass is 21 t, dominated by ammo. Pins
	# the "ammo dominates the wet-mass budget" design choice.
	var sat := Satellite.new()
	var expected: float = (
		Satellite.DEFAULT_DRY_MASS_KG
		+ Satellite.DEFAULT_PROPELLANT_KG
		+ float(RailgunWeapon.MAGAZINE_SIZE) * RailgunWeapon.SLUG_MASS_KG
	)
	assert_close(sat.mass, expected, 1.0e-6)
	# No-railgun unit ⇒ no ammo contribution. recompute_mass after
	# clearing weapons drops the magazine entirely.
	sat.weapons.clear()
	sat.recompute_mass()
	assert_close(
		sat.mass,
		Satellite.DEFAULT_DRY_MASS_KG + Satellite.DEFAULT_PROPELLANT_KG,
		1.0e-6,
	)


func test_satellite_total_ammo_mass_kg() -> void:
	# Helper directly: an unarmed sat reports zero, a railgun-armed
	# sat reports magazine × slug-mass. Confirms the helper the recoil
	# math reads is consistent with what the designers expect.
	var sat := Satellite.new()
	assert_close(
		sat.total_ammo_mass_kg(),
		float(RailgunWeapon.MAGAZINE_SIZE) * RailgunWeapon.SLUG_MASS_KG,
		1.0e-6,
	)
	sat.weapons.clear()
	assert_close(sat.total_ammo_mass_kg(), 0.0, 1.0e-6)


func test_target_coupling_default_returns_per_class_value() -> void:
	# Per-target overrides land later via target_coupling_for(target);
	# today the default subclasses just return their per-class value.
	# Locks the contract so a future per-target hook doesn't silently
	# drift the default coupling.
	var rg := RailgunWeapon.new()
	assert_close(
		rg.target_coupling_for(null), RailgunWeapon.TARGET_COUPLING_DEFAULT,
	)
	var laser := LaserWeapon.new()
	assert_close(
		laser.target_coupling_for(null), LaserWeapon.TARGET_COUPLING_DEFAULT,
	)


func test_satellite_tick_combat_charges_pool_in_joules() -> void:
	# Pool fill rate is now reactor_power_w joules/sec (was a fraction
	# /sec). One sim-sec of charge from a 1 GW reactor adds 1 GJ;
	# ten sim-sec from empty fills a default 10 GJ pool exactly. The
	# clamp at energy_max kicks in on the eleventh second.
	var sat := Satellite.new()
	sat.energy = 0.0
	sat.tick_combat(1.0)
	assert_close(sat.energy, 1.0e9, 1.0)
	sat.tick_combat(100.0)  # would overshoot 10 GJ; clamp holds.
	assert_close(sat.energy, sat.energy_max, 1.0)
