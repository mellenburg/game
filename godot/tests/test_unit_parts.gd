extends "res://tests/framework.gd"
## Catalog + UnitConfig coverage for the parts / chassis system.
## Locks in the contract SpawnDirector relies on: every catalog id
## resolves, advanced parts are exactly 2× their default-tier facet,
## and resizing a unit's slot row preserves operator-picked parts up
## to the new chassis' slot count.

const UnitChassis = preload("res://scripts/unit_chassis.gd")
const UnitPart = preload("res://scripts/unit_part.gd")
const UnitConfig = preload("res://scripts/unit_config.gd")
const Satellite = preload("res://scripts/satellite.gd")
const LaserWeapon = preload("res://scripts/weapons/laser_weapon.gd")
const RailgunWeapon = preload("res://scripts/weapons/railgun_weapon.gd")


func test_default_chassis_has_one_slot_per_kind() -> void:
	var c := UnitChassis.get_by_id(UnitChassis.ID_DEFAULT)
	assert_eq(c.weapon_slots, 1)
	assert_eq(c.cooling_system_slots, 1)
	assert_eq(c.energy_storage_slots, 1)
	assert_eq(c.reactor_slots, 1)


func test_heavy_chassis_doubles_weapons_and_cooling() -> void:
	var c := UnitChassis.get_by_id(UnitChassis.ID_HEAVY)
	assert_eq(c.weapon_slots, 2)
	assert_eq(c.cooling_system_slots, 2)
	assert_eq(c.energy_storage_slots, 1)
	assert_eq(c.reactor_slots, 1)


func test_advanced_parts_double_default_facet() -> void:
	# Pair every default-tier id with its advanced sibling and confirm
	# the advanced part's multiplier is exactly 2× the default's. This
	# is the spec the rest of the system trusts when scaling damage,
	# cool rate, energy_max, and energy_rate.
	var pairs: Array = [
		["laser_default", "laser_advanced"],
		["railgun_default", "railgun_advanced"],
		["cooling_system_default", "cooling_system_advanced"],
		["energy_storage_default", "energy_storage_advanced"],
		["reactor_default", "reactor_advanced"],
	]
	for pair in pairs:
		var d := UnitPart.get_by_id(pair[0])
		var a := UnitPart.get_by_id(pair[1])
		assert_close(d.multiplier, 1.0)
		assert_close(a.multiplier, 2.0 * d.multiplier)


func test_set_chassis_pads_slots_with_default_part() -> void:
	# Fresh unit on the default chassis ⇒ one part per kind, all default
	# tier.
	var u := UnitConfig.make_default("U-1", "T-01")
	assert_eq(u.weapon_part_ids.size(), 1)
	assert_eq(u.weapon_part_ids[0], "laser_default")
	assert_eq(u.cooling_system_part_ids[0], "cooling_system_default")
	assert_eq(u.energy_storage_part_ids[0], "energy_storage_default")
	assert_eq(u.reactor_part_ids[0], "reactor_default")


func test_set_chassis_preserves_existing_picks() -> void:
	# Pick an advanced laser, swap to heavy chassis, verify slot 0 keeps
	# the advanced laser and the new slot 1 picks up the default. This
	# is the behaviour the menu relies on so a chassis swap doesn't
	# wipe the operator's earlier choices.
	var u := UnitConfig.make_default("U-1", "T-01")
	u.set_part_id(UnitPart.KIND_WEAPON, 0, "laser_advanced")
	u.set_chassis(UnitChassis.ID_HEAVY)
	assert_eq(u.weapon_part_ids.size(), 2)
	assert_eq(u.weapon_part_ids[0], "laser_advanced")
	assert_eq(u.weapon_part_ids[1], "laser_default")


func test_total_multiplier_sums_across_slots() -> void:
	# Heavy chassis with two advanced cooling systems ⇒ total cooling
	# multiplier 4.0 (two slots × 2.0 each). SpawnDirector multiplies
	# this through Satellite.DEFAULT_COOLING_POWER_W so the test pins
	# the aggregation rule SpawnDirector consumes.
	var u := UnitConfig.make_default("U-1", "T-01")
	u.set_chassis(UnitChassis.ID_HEAVY)
	u.set_part_id(UnitPart.KIND_COOLING_SYSTEM, 0, "cooling_system_advanced")
	u.set_part_id(UnitPart.KIND_COOLING_SYSTEM, 1, "cooling_system_advanced")
	assert_close(u.total_multiplier_for_kind(UnitPart.KIND_COOLING_SYSTEM), 4.0)


func test_summary_stats_default_unit_matches_baseline_constants() -> void:
	# Default chassis with default-tier parts in every slot ⇒ stats
	# track the un-multiplied weapon constants and the satellite's
	# default joule pool / watt reactor. Pinning this here so a future
	# tweak to the default tier (or to the constants those defaults
	# derive from) is loud rather than silent.
	var u := UnitConfig.make_default("U-1", "T-01")
	var s := u.summary_stats()
	assert_close(float(s["hp"]), Satellite.MAX_HP)
	# Default chassis ships a single laser slot — no railgun magazine —
	# so wet mass collapses to dry + propellant.
	assert_close(
		float(s["mass_kg"]),
		Satellite.DEFAULT_DRY_MASS_KG + Satellite.DEFAULT_PROPELLANT_KG,
	)
	assert_eq(int(s["laser_count"]), 1)
	assert_close(
		float(s["laser_dps_total"]),
		LaserWeapon.base_damage_per_second_at_zero_range(),
	)
	assert_close(float(s["laser_max_range"]), LaserWeapon.MAX_RANGE_KM)
	assert_eq(int(s["railgun_count"]), 0)
	assert_close(float(s["energy_storage"]), Satellite.DEFAULT_ENERGY_MAX_J)
	assert_close(
		float(s["energy_production"]), Satellite.DEFAULT_REACTOR_POWER_W,
	)


func test_summary_stats_advanced_parts_double_facets() -> void:
	# Advanced laser, advanced storage, advanced reactor ⇒ DPS,
	# capacity, and regen all 2× their default-tier values. This is
	# the spec the menu's Unit Summary panel renders, and it's the
	# spec SpawnDirector implements when scaling Satellite fields.
	var u := UnitConfig.make_default("U-1", "T-01")
	u.set_part_id(UnitPart.KIND_WEAPON, 0, "laser_advanced")
	u.set_part_id(UnitPart.KIND_ENERGY_STORAGE, 0, "energy_storage_advanced")
	u.set_part_id(UnitPart.KIND_REACTOR, 0, "reactor_advanced")
	var s := u.summary_stats()
	# Tolerance scaled to the GJ pool — assert_close's 1e-6 default
	# can't measure 20 GJ vs 20 GJ + 1 J.
	assert_close(
		float(s["laser_dps_total"]),
		2.0 * LaserWeapon.base_damage_per_second_at_zero_range(),
	)
	assert_close(
		float(s["energy_storage"]),
		2.0 * Satellite.DEFAULT_ENERGY_MAX_J, 1.0,
	)
	assert_close(
		float(s["energy_production"]),
		2.0 * Satellite.DEFAULT_REACTOR_POWER_W, 1.0,
	)


func test_summary_stats_railgun_cooldown_scales_with_cooling() -> void:
	# Default railgun + advanced cooling system ⇒ cooling power
	# doubles, so the reported sole-demander cooldown halves. Verifies
	# the cooling complement flows through to the weapon's cooldown
	# stat — the same value SpawnDirector writes to
	# Satellite.cooling_power_w at spawn.
	var u := UnitConfig.make_default("U-1", "T-01")
	u.set_part_id(UnitPart.KIND_WEAPON, 0, "railgun_default")
	u.set_part_id(UnitPart.KIND_COOLING_SYSTEM, 0, "cooling_system_advanced")
	var s := u.summary_stats()
	assert_eq(int(s["railgun_count"]), 1)
	assert_close(
		float(s["railgun_damage_total"]),
		RailgunWeapon.base_damage_per_shot(),
	)
	# heat_capacity / (DEFAULT_COOLING_POWER × 2) is the sole-demander
	# recovery time at the advanced tier.
	var expected: float = RailgunWeapon.HEAT_CAPACITY_J / (
		2.0 * Satellite.DEFAULT_COOLING_POWER_W
	)
	assert_close(float(s["railgun_cooldown_sec"]), expected, 1.0e-3)


func test_summary_stats_railgun_physical_fields() -> void:
	# Pins the new physical readouts the Hangar's RAILGUNS section
	# renders: slug mass, muzzle velocity, slug KE, wall-plug energy
	# per shot, magazine size, and the recoil Δv against full wet mass.
	# All independent of the weapon's tier multiplier (which only
	# scales damage), so a default-tier railgun pins the bare physics.
	var u := UnitConfig.make_default("U-1", "T-01")
	u.set_part_id(UnitPart.KIND_WEAPON, 0, "railgun_default")
	var s := u.summary_stats()
	assert_close(
		float(s["railgun_slug_mass_kg"]), RailgunWeapon.SLUG_MASS_KG,
	)
	assert_close(
		float(s["railgun_muzzle_velocity_m_s"]),
		RailgunWeapon.MUZZLE_VELOCITY_M_S,
	)
	assert_close(
		float(s["railgun_slug_ke_j"]), RailgunWeapon.SLUG_MUZZLE_KE_J, 1.0,
	)
	assert_close(
		float(s["railgun_energy_per_shot_j"]),
		RailgunWeapon.ENERGY_PER_SHOT_J, 1.0,
	)
	assert_eq(
		int(s["railgun_magazine_size"]), RailgunWeapon.MAGAZINE_SIZE,
	)
	assert_close(
		float(s["railgun_target_coupling"]),
		RailgunWeapon.TARGET_COUPLING_DEFAULT,
	)
	# Recoil Δv = momentum / wet_mass. Default railgun magazine adds
	# 20 t to the 1 t airframe ⇒ ~21 t wet, so 400 kg·km/s of
	# momentum lands as ~19 m/s of recoil per shot. Asserted against
	# the analytic value rather than a hard-coded number so a future
	# thruster / chassis tweak doesn't silently shift the assertion.
	var ammo_mass: float = (
		float(RailgunWeapon.MAGAZINE_SIZE) * RailgunWeapon.SLUG_MASS_KG
	)
	var wet: float = (
		Satellite.DEFAULT_DRY_MASS_KG
		+ Satellite.DEFAULT_PROPELLANT_KG
		+ ammo_mass
	)
	var expected_recoil := (
		RailgunWeapon.SLUG_MOMENTUM_KG_KM_S * 1000.0 / wet
	)
	assert_close(float(s["railgun_recoil_dv_ms"]), expected_recoil, 1.0e-6)


func test_summary_stats_laser_physical_fields() -> void:
	# Pins the new physical readouts the Hangar's LASERS section
	# renders: radiated power, pool draw, wall-plug efficiency, and
	# target coupling. Tier-independent (the multiplier only scales
	# damage), so a default-tier laser is the right fixture for the
	# bare physics constants.
	var u := UnitConfig.make_default("U-1", "T-01")
	u.set_part_id(UnitPart.KIND_WEAPON, 0, "laser_default")
	var s := u.summary_stats()
	assert_close(
		float(s["laser_radiated_power_w"]), LaserWeapon.RADIATED_POWER_W, 1.0,
	)
	assert_close(
		float(s["laser_pool_draw_w"]), LaserWeapon.POOL_DRAIN_W, 1.0,
	)
	assert_close(
		float(s["laser_wallplug_efficiency"]),
		LaserWeapon.WALLPLUG_EFFICIENCY,
	)
	assert_close(
		float(s["laser_target_coupling"]),
		LaserWeapon.TARGET_COUPLING_DEFAULT,
	)


func test_summary_stats_no_cooling_yields_infinite_cooldown() -> void:
	# Strip the cooling-system slot's part. With cooling driven entirely
	# by the cooling complement, an empty row means weapons couldn't
	# recover after firing — the summary surfaces this as INF so the
	# operator can see the unit is inert.
	var u := UnitConfig.make_default("U-1", "T-01")
	u.set_part_id(UnitPart.KIND_COOLING_SYSTEM, 0, "")
	var s := u.summary_stats()
	assert_false(is_finite(float(s["laser_cooldown_sec"])))
	assert_false(is_finite(float(s["railgun_cooldown_sec"])))
	assert_close(float(s["cooling_power_w"]), 0.0)


func test_summary_stats_heavy_dual_weapon_sums_damage() -> void:
	# Heavy chassis with both weapon slots filled by lasers ⇒ DPS sums
	# across the two slots (6 advanced + 5 default = 11 base DPS-units
	# at default ranges). This is the visible balance dial the
	# Hangar's right column surfaces, so a regression here shows up
	# loud.
	var u := UnitConfig.make_default("U-1", "T-01")
	u.set_chassis(UnitChassis.ID_HEAVY)
	u.set_part_id(UnitPart.KIND_WEAPON, 0, "laser_advanced")
	u.set_part_id(UnitPart.KIND_WEAPON, 1, "laser_default")
	var s := u.summary_stats()
	assert_eq(int(s["laser_count"]), 2)
	assert_close(
		float(s["laser_dps_total"]),
		LaserWeapon.base_damage_per_second_at_zero_range() * (2.0 + 1.0),
	)


func test_unknown_part_id_resolves_to_zero_multiplier() -> void:
	# A unit with an unknown part id (e.g. a save file from a future
	# build that has since been retired) shouldn't crash spawn — it
	# should just contribute zero to the aggregate. Pinning that here
	# so the fallback in UnitPart.get_by_id can't silently change.
	var p := UnitPart.get_by_id("not_a_real_part")
	assert_close(p.multiplier, 0.0)
