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
	assert_eq(c.radiator_slots, 1)
	assert_eq(c.energy_storage_slots, 1)
	assert_eq(c.reactor_slots, 1)


func test_heavy_chassis_doubles_weapons_and_radiators() -> void:
	var c := UnitChassis.get_by_id(UnitChassis.ID_HEAVY)
	assert_eq(c.weapon_slots, 2)
	assert_eq(c.radiator_slots, 2)
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
		["radiator_default", "radiator_advanced"],
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
	assert_eq(u.radiator_part_ids[0], "radiator_default")
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
	# Heavy chassis with two advanced radiators ⇒ total radiator
	# multiplier 4.0 (two slots × 2.0 each). SpawnDirector multiplies
	# this through to each weapon's cool_mult so the test pins the
	# aggregation rule SpawnDirector consumes.
	var u := UnitConfig.make_default("U-1", "T-01")
	u.set_chassis(UnitChassis.ID_HEAVY)
	u.set_part_id(UnitPart.KIND_RADIATOR, 0, "radiator_advanced")
	u.set_part_id(UnitPart.KIND_RADIATOR, 1, "radiator_advanced")
	assert_close(u.total_multiplier_for_kind(UnitPart.KIND_RADIATOR), 4.0)


func test_summary_stats_default_unit_matches_baseline_constants() -> void:
	# Default chassis with default-tier parts in every slot ⇒ stats
	# track the un-multiplied weapon constants and the satellite's
	# legacy ENERGY_MAX / ENERGY_RATE_PER_SIM_SEC. Pinning this here so
	# a future tweak to the default tier (or to the constants those
	# defaults derive from) is loud rather than silent.
	var u := UnitConfig.make_default("U-1", "T-01")
	var s := u.summary_stats()
	assert_close(float(s["hp"]), Satellite.MAX_HP)
	assert_close(float(s["mass_kg"]), Satellite.DEFAULT_MASS_KG)
	assert_eq(int(s["laser_count"]), 1)
	assert_close(float(s["laser_dps_total"]), LaserWeapon.DAMAGE_PER_SEC)
	assert_close(float(s["laser_max_range"]), LaserWeapon.MAX_RANGE_KM)
	assert_eq(int(s["railgun_count"]), 0)
	assert_close(float(s["energy_storage"]), Satellite.ENERGY_MAX)
	assert_close(
		float(s["energy_production"]), Satellite.ENERGY_RATE_PER_SIM_SEC,
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
	assert_close(
		float(s["laser_dps_total"]), 2.0 * LaserWeapon.DAMAGE_PER_SEC,
	)
	assert_close(float(s["energy_storage"]), 2.0 * Satellite.ENERGY_MAX)
	assert_close(
		float(s["energy_production"]),
		2.0 * Satellite.ENERGY_RATE_PER_SIM_SEC,
	)


func test_summary_stats_railgun_fire_rate_scales_with_radiator() -> void:
	# Default railgun + advanced radiator ⇒ cool_rate doubles, so the
	# reported fire rate doubles. Verifies the radiator multiplier
	# flows through to the railgun's cooldown stat (the same mult
	# SpawnDirector applies to RailgunWeapon.cool_mult at spawn).
	var u := UnitConfig.make_default("U-1", "T-01")
	u.set_part_id(UnitPart.KIND_WEAPON, 0, "railgun_default")
	u.set_part_id(UnitPart.KIND_RADIATOR, 0, "radiator_advanced")
	var s := u.summary_stats()
	assert_eq(int(s["railgun_count"]), 1)
	assert_close(
		float(s["railgun_damage_total"]), RailgunWeapon.DAMAGE_PER_SHOT,
	)
	assert_close(
		float(s["railgun_fire_rate"]), 2.0 * RailgunWeapon.COOL_PER_SEC,
	)


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
		LaserWeapon.DAMAGE_PER_SEC * (2.0 + 1.0),
	)


func test_unknown_part_id_resolves_to_zero_multiplier() -> void:
	# A unit with an unknown part id (e.g. a save file from a future
	# build that has since been retired) shouldn't crash spawn — it
	# should just contribute zero to the aggregate. Pinning that here
	# so the fallback in UnitPart.get_by_id can't silently change.
	var p := UnitPart.get_by_id("not_a_real_part")
	assert_close(p.multiplier, 0.0)
