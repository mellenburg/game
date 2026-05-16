extends "res://tests/framework.gd"
## CombatController-level invariants. Most weapon math is covered by
## the per-weapon unit tests; this file pins the cross-weapon
## scheduling rules — currently the railgun anti-overkill reservation
## that prevents fleet-wide dogpiling on a target the first slug is
## already on its way to one-kill.
##
## CombatController extends Node, so we instantiate it bare (no scene
## tree) and only exercise paths that don't depend on a live tree.
## Reservation tracking is one such path: it's pure dictionary
## bookkeeping driven by closures the controller hands to SlugRenderer.

const CombatController = preload("res://scripts/combat_controller.gd")
const SlugRenderer = preload("res://scripts/slug_renderer.gd")
const BeamRenderer = preload("res://scripts/beam_renderer.gd")
const HUD = preload("res://scripts/hud.gd")
const Satellite = preload("res://scripts/satellite.gd")
const RailgunWeapon = preload("res://scripts/weapons/railgun_weapon.gd")
const MissileWeapon = preload("res://scripts/weapons/missile_weapon.gd")
const MissileSpawner = preload("res://scripts/missile_spawner.gd")
const MassCenterOrbit = preload("res://scripts/mass_center_orbit.gd")

# MassCenterOrbit.BODY_RADIUS_KM is now a runtime-mutable static var (each
# mission may set its own body's radius), so a const initialiser can't
# read it. The tests run on the Earth defaults; pin the literal here.
const BODY_RADIUS_KM: float = 6371.0
# Energy budget large enough to cover several railgun shots (one shot
# is ~1.7 TJ at the current wall-plug efficiency).
const STARTING_ENERGY_J: float = 1.0e14


# Build a bare controller wired to bare renderers + hud. Each
# component is constructed with `.new()` only — `_ready()` is invoked
# manually on the slug renderer because its `_shared_mesh` is created
# there and `register_fire` would crash without it.
func _make_controller() -> Array:
	var sr := SlugRenderer.new()
	sr._ready()
	var br := BeamRenderer.new()
	var h := HUD.new()
	var cc := CombatController.new()
	cc.setup(h, br, sr)
	return [cc, sr, br, h]


func _free_controller(parts: Array) -> void:
	# Free in reverse-construction order. The slug renderer may still
	# own MeshInstance3D children from any active slug; queue_free'ing
	# the renderer takes them down too.
	for p in parts:
		if p != null and is_instance_valid(p):
			p.queue_free()


# Player-team satellite at a clean circular orbit. Position + velocity
# are tangent so a transverse railgun shot doesn't trip the safety
# check. Team / energy / weapons reset to known values so default-
# loadout assumptions don't bleed across tests.
func _make_attacker(radius: float, team: int) -> Satellite:
	var s := Satellite.new()
	s.team = team
	s.alive = true
	s.orbit_alive = true
	s.energy = STARTING_ENERGY_J
	var v_circ: float = sqrt(MassCenterOrbit.MU / radius)
	s.orbit = MassCenterOrbit.new(
		Vector3(radius, 0.0, 0.0), Vector3(0.0, v_circ, 0.0)
	)
	# Wipe the default 2-laser-1-railgun loadout and install a single
	# railgun so the reservation flow isn't muddied by laser fire.
	s.weapons = [RailgunWeapon.new()]
	s.recompute_mass()
	return s


# Enemy at a position offset laterally so LOS clears the planet and
# a railgun shot from a player at +x lands cleanly on it. Velocity
# tangent in the y-z plane to keep the orbit physical.
func _make_enemy(pos: Vector3, team: int) -> Satellite:
	var s := Satellite.new()
	s.team = team
	s.alive = true
	s.orbit_alive = true
	var radius: float = pos.length()
	var v_circ: float = sqrt(MassCenterOrbit.MU / radius)
	s.orbit = MassCenterOrbit.new(pos, Vector3(0.0, 0.0, v_circ))
	s.weapons = []
	s.hp = 1.0e6  # massive HP so the shot never lethals during tests
	s.recompute_mass()
	return s


func test_initial_reservation_count_is_zero() -> void:
	var parts := _make_controller()
	var cc: CombatController = parts[0]
	assert_eq(cc.reserved_target_count(), 0)
	_free_controller(parts)


func test_exclude_reserved_drops_only_reserved_target_ids() -> void:
	# Pure-function check: feed two satellites to the candidate
	# filter, mark one as reserved, and confirm only the un-reserved
	# one survives. Doesn't go through the slug renderer at all.
	var parts := _make_controller()
	var cc: CombatController = parts[0]
	var a := _make_attacker(BODY_RADIUS_KM + 5000.0, 1)
	var b := _make_attacker(BODY_RADIUS_KM + 5000.0, 1)
	cc._reserved_target_iids[b.get_instance_id()] = true
	var cands: Array[Satellite] = [a, b]
	var filtered: Array[Satellite] = cc._exclude_reserved(cands)
	assert_eq(filtered.size(), 1)
	assert_eq(filtered[0], a)
	a.queue_free()
	b.queue_free()
	_free_controller(parts)


func test_railgun_fire_reserves_target_then_releases_on_slug_arrival() -> void:
	# The end-to-end shape of the fix: firing a slug-mode railgun
	# adds the target to the reservation map; ticking the slug
	# renderer until the slug arrives drains the map back to zero.
	# Uses a single shooter and a single far-side enemy so the only
	# bookkeeping in play is this one shot's reservation.
	var parts := _make_controller()
	var cc: CombatController = parts[0]
	var sr: SlugRenderer = parts[1]
	var attacker := _make_attacker(BODY_RADIUS_KM + 5000.0, 0)
	# Place enemy 3000 km laterally — well outside Earth's 6371 km
	# disc relative to the attacker, so LOS is clear and the recoil
	# stays within the safety envelope.
	var enemy := _make_enemy(
		Vector3(BODY_RADIUS_KM + 5000.0, 3000.0, 0.0), 1
	)
	var weapon: RailgunWeapon = attacker.weapons[0]
	assert_true(weapon.can_fire(attacker))
	assert_true(cc._fire_railgun_with_slug(attacker, weapon, enemy, 1.0))
	assert_eq(cc.reserved_target_count(), 1)
	# Tick the slug renderer with enough sim-time that the slug
	# crosses the ~3000 km gap. At MUZZLE_VELOCITY_KMS = 20 km/s a
	# single sim-second only advances 20 km, so derive the required
	# tick from the constant rather than guessing — any future bump
	# to muzzle velocity or test distance keeps the assertion honest.
	var arrival_tick: float = (4000.0 / SlugRenderer.MUZZLE_VELOCITY_KMS)
	sr.tick(arrival_tick)
	assert_eq(sr.active_slug_count(), 0)
	assert_eq(cc.reserved_target_count(), 0)
	attacker.queue_free()
	enemy.queue_free()
	_free_controller(parts)


func test_railgun_reservation_released_on_attacker_death() -> void:
	# Attacker dying mid-flight drops the slug without firing on_arrival.
	# Without the on_drop hook the target's iid would stay reserved
	# forever, locking it out from every other railgun in the fleet.
	# This pins the leak shut.
	var parts := _make_controller()
	var cc: CombatController = parts[0]
	var sr: SlugRenderer = parts[1]
	var attacker := _make_attacker(BODY_RADIUS_KM + 5000.0, 0)
	var enemy := _make_enemy(
		Vector3(BODY_RADIUS_KM + 5000.0, 3000.0, 0.0), 1
	)
	var weapon: RailgunWeapon = attacker.weapons[0]
	cc._fire_railgun_with_slug(attacker, weapon, enemy, 1.0)
	assert_eq(cc.reserved_target_count(), 1)
	# Kill the attacker before the slug reaches its target. The next
	# slug-renderer tick should detect the dead shooter, fire on_drop,
	# and despawn the slug without touching the enemy.
	attacker.alive = false
	# Use a very small sim_delta so the slug doesn't *also* arrive in
	# the same tick — we want the attacker-dead branch to be the
	# release path, not on_arrival. 1e-6 seconds advances travel by
	# 0.02 km, well under the 3000 km gap.
	sr.tick(1.0e-6)
	assert_eq(sr.active_slug_count(), 0)
	assert_eq(cc.reserved_target_count(), 0)
	attacker.queue_free()
	enemy.queue_free()
	_free_controller(parts)


func test_second_railgun_skips_reserved_target() -> void:
	# Two attackers, one enemy: first attacker fires, the enemy gets
	# reserved, the second attacker's pick_target is fed the
	# excluded candidate list and finds nothing to shoot at. This is
	# the user-visible bug the fix is here to address.
	var parts := _make_controller()
	var cc: CombatController = parts[0]
	var attacker_a := _make_attacker(BODY_RADIUS_KM + 5000.0, 0)
	var attacker_b := _make_attacker(BODY_RADIUS_KM + 5000.0, 0)
	var enemy := _make_enemy(
		Vector3(BODY_RADIUS_KM + 5000.0, 3000.0, 0.0), 1
	)
	var weapon_a: RailgunWeapon = attacker_a.weapons[0]
	var weapon_b: RailgunWeapon = attacker_b.weapons[0]
	# A's railgun would happily pick the enemy on its own — confirm
	# the bare picker works before the reservation gate is in play.
	var pre_pick = weapon_a.pick_target(
		attacker_a, [attacker_a, attacker_b, enemy], 0.0
	)
	assert_eq(pre_pick, enemy)
	# A fires; the reservation now blocks B from picking the same
	# body even though the candidate list is otherwise identical.
	cc._fire_railgun_with_slug(attacker_a, weapon_a, enemy, 1.0)
	assert_eq(cc.reserved_target_count(), 1)
	var filtered: Array[Satellite] = cc._exclude_reserved(
		[attacker_a, attacker_b, enemy] as Array[Satellite]
	)
	var pick_b = weapon_b.pick_target(attacker_b, filtered, 0.0)
	assert_eq(pick_b, null)
	attacker_a.queue_free()
	attacker_b.queue_free()
	enemy.queue_free()
	_free_controller(parts)


func test_clear_all_releases_reservations() -> void:
	# Operator toggles slug-render off mid-flight: clear_all routes
	# every pending slug through on_drop, which drains the
	# reservation map. Without this, a toggle off then back on would
	# leave railguns permanently locked off any in-flight target.
	var parts := _make_controller()
	var cc: CombatController = parts[0]
	var sr: SlugRenderer = parts[1]
	var attacker := _make_attacker(BODY_RADIUS_KM + 5000.0, 0)
	var enemy := _make_enemy(
		Vector3(BODY_RADIUS_KM + 5000.0, 3000.0, 0.0), 1
	)
	var weapon: RailgunWeapon = attacker.weapons[0]
	cc._fire_railgun_with_slug(attacker, weapon, enemy, 1.0)
	assert_eq(cc.reserved_target_count(), 1)
	sr.clear_all()
	assert_eq(sr.active_slug_count(), 0)
	assert_eq(cc.reserved_target_count(), 0)
	attacker.queue_free()
	enemy.queue_free()
	_free_controller(parts)


# --- missile integration ----------------------------------------------------


# Same as _make_controller but also wires a MissileSpawner.
func _make_missile_controller() -> Array:
	var sr := SlugRenderer.new()
	sr._ready()
	var br := BeamRenderer.new()
	var h := HUD.new()
	var ms := MissileSpawner.new()
	var cc := CombatController.new()
	cc.setup(h, br, sr, ms)
	return [cc, sr, br, h, ms]


# Attacker rigged with a single MissileWeapon — strips the default
# laser+laser+railgun loadout so the test isolates the missile fire path.
func _make_missile_attacker(radius: float, team: int) -> Satellite:
	var s := _make_attacker(radius, team)
	s.weapons = [MissileWeapon.new()]
	s.recompute_mass()
	return s


# Coplanar circular enemy for missile tests. _make_enemy's polar
# orbit is fine for railgun (instant-shot, no orbital match needed)
# but forces a 90° plane change on missiles, which exceeds the 4 km/s
# dv budget. This helper keeps the enemy in the attacker's x-y plane
# so a normal phasing transfer suffices.
func _make_coplanar_enemy(radius_km: float, true_anom_rad: float, team: int) -> Satellite:
	var s := Satellite.new()
	s.team = team
	s.alive = true
	s.orbit_alive = true
	# Position + tangent velocity in the x-y plane.
	var pos: Vector3 = Vector3(
		radius_km * cos(true_anom_rad), radius_km * sin(true_anom_rad), 0.0
	)
	var v_circ: float = sqrt(MassCenterOrbit.MU / radius_km)
	var vel: Vector3 = Vector3(
		-v_circ * sin(true_anom_rad), v_circ * cos(true_anom_rad), 0.0
	)
	s.orbit = MassCenterOrbit.new(pos, vel)
	s.weapons = []
	s.hp = 1.0e6
	s.recompute_mass()
	return s


func test_process_combat_does_not_auto_fire_missiles() -> void:
	# Missiles are manual-fire only — every shot is a 100 MT warhead
	# off a small magazine, so the auto-fire loop deliberately skips
	# MissileWeapons. process_combat with a missile-armed attacker
	# and a reachable enemy must leave the magazine untouched; the
	# operator's button click / Z key is what spends the warhead.
	var parts := _make_missile_controller()
	var cc: CombatController = parts[0]
	var ms: MissileSpawner = parts[4]
	var attacker := _make_missile_attacker(BODY_RADIUS_KM + 5000.0, 0)
	var enemy := _make_coplanar_enemy(BODY_RADIUS_KM + 5100.0, PI / 6.0, 1)
	var fleet: Array[Satellite] = [attacker, enemy]
	cc.process_combat(fleet, 0.0, 0.1)
	assert_eq(ms.active_missile_count(), 0, "auto-fire must not spawn missiles")
	var w: MissileWeapon = attacker.weapons[0]
	assert_eq(w.ammo_count, MissileWeapon.MAGAZINE_SIZE)
	attacker.queue_free()
	enemy.queue_free()
	for p in parts:
		if p != null and is_instance_valid(p):
			p.queue_free()


func test_try_fire_missile_spawns_missile_and_reserves_target() -> void:
	# Manual-fire entry point: try_fire_missile_for picks a reachable
	# enemy and spawns one missile. The HUD button / Z key route
	# through this same method.
	var parts := _make_missile_controller()
	var cc: CombatController = parts[0]
	var ms: MissileSpawner = parts[4]
	var attacker := _make_missile_attacker(BODY_RADIUS_KM + 5000.0, 0)
	# Coplanar enemy 30° ahead, 100 km higher. Within budget at ~1.7 km/s.
	var enemy := _make_coplanar_enemy(BODY_RADIUS_KM + 5100.0, PI / 6.0, 1)
	var fleet: Array[Satellite] = [attacker, enemy]
	var fired: bool = cc.try_fire_missile_for(attacker, fleet, 0.0, 0.1)
	assert_true(fired, "manual fire should succeed on reachable enemy")
	assert_eq(ms.active_missile_count(), 1)
	assert_eq(ms.reserved_target_count(), 1)
	assert_true(ms.has_reservation(enemy.get_instance_id()))
	# Attacker bookkeeping: ammo decremented, energy drained, weapon
	# overheated (so the next try_fire refuses to re-fire).
	var w: MissileWeapon = attacker.weapons[0]
	assert_eq(w.ammo_count, MissileWeapon.MAGAZINE_SIZE - 1)
	assert_true(w.overheated)
	attacker.queue_free()
	enemy.queue_free()
	for p in parts:
		if p != null and is_instance_valid(p):
			p.queue_free()


func test_try_fire_missile_blocks_when_target_already_reserved() -> void:
	# Two attackers, one enemy: first manual fire spawns a missile,
	# the reservation locks the target out so a second try_fire on
	# the other attacker finds no eligible target.
	var parts := _make_missile_controller()
	var cc: CombatController = parts[0]
	var ms: MissileSpawner = parts[4]
	var attacker_a := _make_missile_attacker(BODY_RADIUS_KM + 5000.0, 0)
	var attacker_b := _make_missile_attacker(BODY_RADIUS_KM + 5000.0, 0)
	var enemy := _make_coplanar_enemy(BODY_RADIUS_KM + 5100.0, PI / 6.0, 1)
	var fleet: Array[Satellite] = [attacker_a, attacker_b, enemy]
	assert_true(cc.try_fire_missile_for(attacker_a, fleet, 0.0, 0.1))
	assert_false(
		cc.try_fire_missile_for(attacker_b, fleet, 0.0, 0.1),
		"reservation must block the second launcher"
	)
	assert_eq(ms.active_missile_count(), 1)
	attacker_a.queue_free()
	attacker_b.queue_free()
	enemy.queue_free()
	for p in parts:
		if p != null and is_instance_valid(p):
			p.queue_free()


func test_try_fire_missile_skipped_without_spawner() -> void:
	# Backward-compat: a controller wired without a MissileSpawner
	# (old scenes, tests with no missile setup) must not crash on
	# try_fire_missile_for — _fire_missile silently returns false.
	var parts := _make_controller()  # NO missile spawner
	var cc: CombatController = parts[0]
	var attacker := _make_missile_attacker(BODY_RADIUS_KM + 5000.0, 0)
	var enemy := _make_coplanar_enemy(BODY_RADIUS_KM + 5100.0, PI / 6.0, 1)
	var fleet: Array[Satellite] = [attacker, enemy]
	assert_false(cc.try_fire_missile_for(attacker, fleet, 0.0, 0.1))
	var w: MissileWeapon = attacker.weapons[0]
	assert_eq(w.ammo_count, MissileWeapon.MAGAZINE_SIZE)
	attacker.queue_free()
	enemy.queue_free()
	_free_controller(parts)
