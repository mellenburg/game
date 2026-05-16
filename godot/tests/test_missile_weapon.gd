extends "res://tests/framework.gd"
## MissileWeapon unit tests. Uses real MassCenterOrbit on fakes (the
## Lambert solver cares about the actual orbital state); satellites
## themselves stay as RefCounted stubs so we don't drag Node lifetime
## into headless tests.

const MissileWeapon = preload("res://scripts/weapons/missile_weapon.gd")
const MassCenterOrbit = preload("res://scripts/mass_center_orbit.gd")

const STARTING_ENERGY_J: float = 1.0e13
const MISSILE_LAUNCHER_MASS_KG: float = 5000.0


# Minimal Satellite stand-in. RefCounted so it doesn't survive tests.
# Exposes the fields MissileWeapon reads: orbit, team, alive,
# orbit_alive, energy, hp, mass, is_surface, propellant_kg, dry_mass_kg.
# recompute_mass is a no-op stub; tests assert ammo / energy changes
# directly.
class FakeSat extends RefCounted:
	var orbit: MassCenterOrbit
	var team: int = 0
	var alive: bool = true
	var orbit_alive: bool = true
	var hp: float = 100.0
	var energy: float = STARTING_ENERGY_J
	var mass: float = MISSILE_LAUNCHER_MASS_KG
	var is_surface: bool = false
	var inert: bool = false
	var dry_mass_kg: float = MISSILE_LAUNCHER_MASS_KG
	var propellant_kg: float = 0.0
	var recompute_mass_calls: int = 0

	func is_inert_asteroid() -> bool:
		return inert

	func recompute_mass() -> void:
		recompute_mass_calls += 1


func _make_sat_circular(radius_km: float, true_anom_rad: float, team: int = 0) -> FakeSat:
	var s := FakeSat.new()
	s.team = team
	s.orbit = MassCenterOrbit.make_circular(radius_km - 6371.0, 0.0, 0.0, true_anom_rad)
	return s


func test_envelope_rejects_same_team() -> void:
	var attacker := _make_sat_circular(7000.0, 0.0, 0)
	var target := _make_sat_circular(7000.0, PI * 0.5, 0)  # same team
	var w := MissileWeapon.new()
	assert_false(w.is_target_in_engagement_envelope(attacker, target))


func test_envelope_rejects_dead_target() -> void:
	var attacker := _make_sat_circular(7000.0, 0.0, 0)
	var target := _make_sat_circular(7000.0, PI * 0.5, 1)
	target.alive = false
	var w := MissileWeapon.new()
	assert_false(w.is_target_in_engagement_envelope(attacker, target))


func test_envelope_accepts_opposing_team_in_range() -> void:
	var attacker := _make_sat_circular(7000.0, 0.0, 0)
	var target := _make_sat_circular(7000.0, PI * 0.5, 1)
	var w := MissileWeapon.new()
	assert_true(w.is_target_in_engagement_envelope(attacker, target))


func test_envelope_rejects_target_beyond_max_reach() -> void:
	var attacker := _make_sat_circular(7000.0, 0.0, 0)
	# Target on a 1e8 km orbit (effectively infinity for a missile).
	var target := _make_sat_circular(1.0e8, 0.0, 1)
	var w := MissileWeapon.new()
	assert_false(w.is_target_in_engagement_envelope(attacker, target))


func test_can_fire_requires_ammo() -> void:
	var attacker := _make_sat_circular(7000.0, 0.0, 0)
	var w := MissileWeapon.new()
	assert_true(w.can_fire(attacker))
	w.ammo_count = 0
	assert_false(w.can_fire(attacker))


func test_can_fire_requires_energy() -> void:
	var attacker := _make_sat_circular(7000.0, 0.0, 0)
	attacker.energy = 0.0
	var w := MissileWeapon.new()
	assert_false(w.can_fire(attacker))


func test_can_fire_refuses_overheated() -> void:
	var attacker := _make_sat_circular(7000.0, 0.0, 0)
	var w := MissileWeapon.new()
	w.overheated = true
	assert_false(w.can_fire(attacker))


func test_can_fire_refuses_surface_units() -> void:
	var attacker := _make_sat_circular(7000.0, 0.0, 0)
	attacker.is_surface = true
	var w := MissileWeapon.new()
	assert_false(w.can_fire(attacker))


func test_pick_target_returns_null_with_no_candidates() -> void:
	var attacker := _make_sat_circular(7000.0, 0.0, 0)
	var w := MissileWeapon.new()
	assert_eq(w.pick_target(attacker, [], 0.0), null)


func test_pick_target_returns_null_with_only_friendlies() -> void:
	var attacker := _make_sat_circular(7000.0, 0.0, 0)
	var friend := _make_sat_circular(7000.0, PI * 0.5, 0)
	var w := MissileWeapon.new()
	assert_eq(w.pick_target(attacker, [friend], 0.0), null)


func test_pick_target_picks_reachable_enemy() -> void:
	var attacker := _make_sat_circular(7000.0, 0.0, 0)
	var enemy := _make_sat_circular(7100.0, PI * 0.5, 1)
	var w := MissileWeapon.new()
	var picked = w.pick_target(attacker, [enemy], 0.0)
	assert_eq(picked, enemy)


func test_pick_target_prefers_lowest_dv() -> void:
	var attacker := _make_sat_circular(7000.0, 0.0, 0)
	# Two enemies at the same radius but different phases. The closer
	# one in phase should require less dv to intercept.
	var near := _make_sat_circular(7100.0, PI * 0.3, 1)
	var far := _make_sat_circular(7100.0, PI * 0.9, 1)
	var w := MissileWeapon.new()
	var picked = w.pick_target(attacker, [near, far], 0.0)
	# Should pick the lower-phase-difference target. If the solver
	# accidentally picks the far one, dv-ordering is broken.
	assert_eq(picked, near, "pick_target must prefer lower-dv intercept")


func test_pick_target_caches_solution() -> void:
	var attacker := _make_sat_circular(7000.0, 0.0, 0)
	var enemy := _make_sat_circular(7100.0, PI * 0.5, 1)
	var w := MissileWeapon.new()
	# First call populates cache.
	w.pick_target(attacker, [enemy], 0.0)
	var size_after_first: int = w.cache_size()
	assert_true(size_after_first >= 1, "first call should cache one entry")
	# Second call within TTL reuses cache — size doesn't grow.
	w.pick_target(attacker, [enemy], 1.0)
	assert_eq(w.cache_size(), size_after_first, "cache must reuse, not grow")


func test_cache_evicts_after_ttl() -> void:
	var attacker := _make_sat_circular(7000.0, 0.0, 0)
	var enemy := _make_sat_circular(7100.0, PI * 0.5, 1)
	var w := MissileWeapon.new()
	w.pick_target(attacker, [enemy], 0.0)
	var pre_size: int = w.cache_size()
	assert_true(pre_size >= 1)
	# Step beyond the TTL window. _evict_expired is called inside
	# pick_target before iteration; with no fresh resolve afterwards
	# the dead entry would be evicted and re-populated. We test the
	# eviction by calling pick_target with an empty candidate list,
	# which exercises the eviction without re-populating.
	w.pick_target(attacker, [], MissileWeapon.CACHE_TTL_SEC + 1.0)
	assert_eq(w.cache_size(), 0, "expired entries must be swept")


func test_prepare_shot_decrements_ammo_and_energy() -> void:
	var attacker := _make_sat_circular(7000.0, 0.0, 0)
	var enemy := _make_sat_circular(7100.0, PI * 0.5, 1)
	var w := MissileWeapon.new()
	# Populate cache.
	w.pick_target(attacker, [enemy], 0.0)
	var energy_before: float = attacker.energy
	var ammo_before: int = w.ammo_count
	var pending = w.prepare_shot(attacker, enemy, 0.1, 0.0)
	assert_true(pending != null, "prepare_shot returned null with cached reachable")
	assert_eq(w.ammo_count, ammo_before - 1)
	assert_close(
		energy_before - attacker.energy, MissileWeapon.ENERGY_PER_LAUNCH_J, 1.0
	)
	# Overheat latch trips so the next can_fire() refuses.
	assert_true(w.overheated)
	assert_false(w.can_fire(attacker))


func test_prepare_shot_pending_dict_is_well_formed() -> void:
	var attacker := _make_sat_circular(7000.0, 0.0, 0)
	var enemy := _make_sat_circular(7100.0, PI * 0.5, 1)
	var w := MissileWeapon.new()
	w.pick_target(attacker, [enemy], 0.0)
	var pending: Dictionary = w.prepare_shot(attacker, enemy, 0.1, 0.0)
	assert_true(pending != null)
	# Required keys for the spawner.
	for k in ["launch_r", "launch_v", "target_iid", "attacker_iid",
	          "tof", "blast_radius_km", "damage_hp",
	          "spawn_sim_time", "expiry_sim_time"]:
		assert_true(pending.has(k), "pending dict missing key: %s" % k)
	assert_true(pending.tof >= MissileWeapon.MIN_TOF_SEC)
	assert_true(pending.tof <= MissileWeapon.MAX_TOF_SEC)
	assert_close(pending.blast_radius_km, MissileWeapon.BLAST_RADIUS_KM)
	assert_eq(pending.damage_hp, MissileWeapon.DAMAGE_HP)
	assert_true(pending.expiry_sim_time > pending.spawn_sim_time + pending.tof)
	assert_finite((pending.launch_v as Vector3).length())


func test_prepare_shot_refuses_when_ammo_empty() -> void:
	var attacker := _make_sat_circular(7000.0, 0.0, 0)
	var enemy := _make_sat_circular(7100.0, PI * 0.5, 1)
	var w := MissileWeapon.new()
	w.pick_target(attacker, [enemy], 0.0)
	w.ammo_count = 0
	var pending = w.prepare_shot(attacker, enemy, 0.1, 0.0)
	assert_eq(pending, null)


func test_prepare_shot_recompute_mass_called() -> void:
	var attacker := _make_sat_circular(7000.0, 0.0, 0)
	var enemy := _make_sat_circular(7100.0, PI * 0.5, 1)
	var w := MissileWeapon.new()
	w.pick_target(attacker, [enemy], 0.0)
	w.prepare_shot(attacker, enemy, 0.1, 0.0)
	assert_true(attacker.recompute_mass_calls >= 1)


func test_dv_budget_is_finite_and_reasonable() -> void:
	var dv: float = MissileWeapon.dv_budget_per_missile_kms()
	assert_finite(dv)
	# Sanity bounds: a 250-kg missile burning 150 kg of Isp-450
	# propellant should deliver ~4 km/s. Allow a generous 2..8 window
	# in case constants are tuned later.
	assert_true(dv > 2.0 and dv < 8.0, "dv budget out of range: %f" % dv)


func test_fire_returns_false() -> void:
	# Synchronous fire() is not supported on MissileWeapon —
	# CombatController must use prepare_shot directly.
	var attacker := _make_sat_circular(7000.0, 0.0, 0)
	var enemy := _make_sat_circular(7100.0, PI * 0.5, 1)
	var w := MissileWeapon.new()
	assert_false(w.fire(attacker, enemy, 0.1))
