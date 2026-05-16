extends "res://tests/framework.gd"
## Missile entity unit tests. The tick logic (propagate, distance
## check, detonation, target-attribution) is independent of the
## visual layer, so tests skip the scene tree: Missile.new() is
## constructed but never added to a tree, so _ready() never fires and
## the body / path mesh nodes stay null. The tick code explicitly
## tolerates that (see _sync_body_position null-check). free() the
## missile at the end of each test to avoid leaks across the suite.

const Missile = preload("res://scripts/missile.gd")
const MassCenterOrbit = preload("res://scripts/mass_center_orbit.gd")


# Minimal target stub. Mirrors the fields Missile reads: alive,
# orbit_alive, orbit, plus take_damage. RefCounted so it cleans up
# automatically when the test method exits.
class FakeTarget extends RefCounted:
	var orbit: MassCenterOrbit
	var alive: bool = true
	var orbit_alive: bool = true
	var hp: float = 100.0
	var last_damage: float = 0.0
	var last_attacker = null

	func take_damage(amount: float, attacker = null) -> bool:
		last_damage = amount
		last_attacker = attacker
		hp = maxf(hp - amount, 0.0)
		if hp <= 0.0:
			alive = false
			return true
		return false


# Minimal attacker stub; only the instance id is used by the missile.
class FakeAttacker extends RefCounted:
	var alive: bool = true


func _make_target_at(r: Vector3, v: Vector3) -> FakeTarget:
	var t := FakeTarget.new()
	t.orbit = MassCenterOrbit.new(r, v)
	return t


# Detonation path: missile starts very close to the target with
# matching velocity (zero relative motion). First tick already has
# d < blast_radius → detonation.
func test_detonates_in_blast_radius_immediately() -> void:
	var target_r := Vector3(7000.0, 0.0, 0.0)
	var v_circ: float = sqrt(MassCenterOrbit.MU / 7000.0)
	var target_v := Vector3(0.0, v_circ, 0.0)
	var target := _make_target_at(target_r, target_v)
	# Missile spawns 1 km away with the same velocity — closing rate
	# is zero but it's already inside the 5 km blast radius.
	var attacker := FakeAttacker.new()
	var missile := Missile.new()
	var orbit := MassCenterOrbit.new(target_r + Vector3(1.0, 0.0, 0.0), target_v)
	missile.configure(orbit, target, attacker, 5.0, 75.0, 0.0, 100.0)
	var alive: bool = missile.tick(0.1, 0.0)
	assert_false(alive, "missile should detonate inside blast radius")
	assert_eq(missile.last_termination, Missile.TERM_DETONATED)
	assert_close(target.last_damage, 75.0)
	assert_close(target.hp, 25.0)
	missile.free()


# Miss path: missile flies past the target outside the blast radius,
# closest approach passes, no damage.
func test_misses_target_outside_blast_radius() -> void:
	# Both on circular orbits at different radii so the geometry
	# doesn't conspire to detonate. Target at 7000 km, missile at
	# 7500 km going in the opposite direction — they will approach
	# closest at some point and then separate. Closest approach is
	# ~500 km, well outside the 5 km blast.
	var v_target := sqrt(MassCenterOrbit.MU / 7000.0)
	var v_missile := sqrt(MassCenterOrbit.MU / 7500.0)
	var target := _make_target_at(
		Vector3(7000.0, 0.0, 0.0), Vector3(0.0, v_target, 0.0)
	)
	var attacker := FakeAttacker.new()
	var missile := Missile.new()
	var missile_orbit := MassCenterOrbit.new(
		Vector3(7500.0, 0.0, 0.0), Vector3(0.0, -v_missile, 0.0)
	)
	missile.configure(missile_orbit, target, attacker, 5.0, 75.0, 0.0, 100000.0)
	# Propagate for a long time — half an orbit's worth — to ensure
	# closest approach is reached.
	var alive: bool = true
	var elapsed: float = 0.0
	var step: float = 30.0
	while alive and elapsed < 5000.0:
		alive = missile.tick(step, elapsed)
		elapsed += step
	assert_false(alive, "missile must terminate within 5000 s")
	assert_eq(missile.last_termination, Missile.TERM_MISSED)
	assert_close(target.hp, 100.0, 1.0e-6, "no damage on miss")
	missile.free()


# Expiry path: missile's expiry deadline elapses without detonation.
func test_expires_when_deadline_passes() -> void:
	var target := _make_target_at(
		Vector3(7000.0, 0.0, 0.0),
		Vector3(0.0, sqrt(MassCenterOrbit.MU / 7000.0), 0.0)
	)
	var attacker := FakeAttacker.new()
	var missile := Missile.new()
	# Missile far from target with no approach geometry.
	var v_missile := sqrt(MassCenterOrbit.MU / 8000.0)
	var orbit := MassCenterOrbit.new(
		Vector3(8000.0, 0.0, 0.0), Vector3(0.0, v_missile, 0.0)
	)
	missile.configure(orbit, target, attacker, 5.0, 75.0, 0.0, 100.0)
	# Tick once into the expiry deadline.
	var alive: bool = missile.tick(1.0, 101.0)
	assert_false(alive)
	assert_eq(missile.last_termination, Missile.TERM_EXPIRED)
	missile.free()


# Sub-surface impact: missile's orbit decays into the Earth.
func test_subsurface_impact_terminates() -> void:
	var target := _make_target_at(
		Vector3(7000.0, 0.0, 0.0),
		Vector3(0.0, sqrt(MassCenterOrbit.MU / 7000.0), 0.0)
	)
	var attacker := FakeAttacker.new()
	var missile := Missile.new()
	# Construct an orbit that's already below the surface threshold.
	# norm_r < BODY_RADIUS_KM triggers the subsurface branch on the
	# very first propagate.
	var sub_r := Vector3(MassCenterOrbit.BODY_RADIUS_KM - 100.0, 0.0, 0.0)
	var orbit := MassCenterOrbit.new(sub_r, Vector3(0.0, 7.7, 0.0))
	missile.configure(orbit, target, attacker, 5.0, 75.0, 0.0, 100000.0)
	var alive: bool = missile.tick(0.1, 0.0)
	assert_false(alive)
	assert_eq(missile.last_termination, Missile.TERM_SUBSURFACE)
	missile.free()


# Target lost: target dies between spawn and detonation. Missile
# terminates with TERM_TARGET_LOST instead of detonating.
func test_target_lost_terminates_without_damage() -> void:
	var target := _make_target_at(
		Vector3(7000.0, 0.0, 0.0),
		Vector3(0.0, sqrt(MassCenterOrbit.MU / 7000.0), 0.0)
	)
	var attacker := FakeAttacker.new()
	var missile := Missile.new()
	var orbit := MassCenterOrbit.new(
		Vector3(7001.0, 0.0, 0.0),
		Vector3(0.0, sqrt(MassCenterOrbit.MU / 7001.0), 0.0)
	)
	missile.configure(orbit, target, attacker, 5.0, 75.0, 0.0, 100000.0)
	# Kill the target before the missile ticks.
	target.alive = false
	var alive: bool = missile.tick(0.1, 0.0)
	assert_false(alive)
	assert_eq(missile.last_termination, Missile.TERM_TARGET_LOST)
	assert_close(target.last_damage, 0.0)
	missile.free()


# on_terminate callback fires exactly once on termination.
func test_on_terminate_fires_once() -> void:
	var target := _make_target_at(
		Vector3(7000.0, 0.0, 0.0),
		Vector3(0.0, sqrt(MassCenterOrbit.MU / 7000.0), 0.0)
	)
	var attacker := FakeAttacker.new()
	var missile := Missile.new()
	var orbit := MassCenterOrbit.new(
		Vector3(7001.0, 0.0, 0.0),
		Vector3(0.0, sqrt(MassCenterOrbit.MU / 7001.0), 0.0)
	)
	missile.configure(orbit, target, attacker, 5.0, 75.0, 0.0, 100.0)
	var fires := [0]
	missile.on_terminate = func() -> void:
		fires[0] += 1
	# Force an immediate termination via expiry.
	missile.tick(1.0, 200.0)
	assert_eq(fires[0], 1, "on_terminate should fire exactly once")
	# Subsequent ticks on a terminated missile must NOT re-fire the
	# callback or double-apply damage.
	missile.tick(1.0, 201.0)
	assert_eq(fires[0], 1, "on_terminate should not re-fire")
	missile.free()


# Attacker death path: missile is mid-flight when the launcher dies.
# Damage still applies to the target (the warhead doesn't need the
# launcher), but attacker attribution is dropped.
func test_attacker_death_still_applies_damage() -> void:
	var target_r := Vector3(7000.0, 0.0, 0.0)
	var v_circ: float = sqrt(MassCenterOrbit.MU / 7000.0)
	var target := _make_target_at(target_r, Vector3(0.0, v_circ, 0.0))
	var attacker := FakeAttacker.new()
	var missile := Missile.new()
	var orbit := MassCenterOrbit.new(
		target_r + Vector3(1.0, 0.0, 0.0), Vector3(0.0, v_circ, 0.0)
	)
	missile.configure(orbit, target, attacker, 5.0, 75.0, 0.0, 100.0)
	# Drop the only reference to attacker so is_instance_valid returns
	# false on the missile's _live_attacker lookup.
	attacker = null
	var alive: bool = missile.tick(0.1, 0.0)
	assert_false(alive)
	assert_eq(missile.last_termination, Missile.TERM_DETONATED)
	assert_close(target.last_damage, 75.0)
	assert_eq(target.last_attacker, null, "no attribution when attacker freed")
	missile.free()


# configure() resets prev_distance_km / last_termination / _terminated
# even when called on a previously-used missile (test reuse pattern).
func test_configure_resets_state() -> void:
	var target := _make_target_at(
		Vector3(7000.0, 0.0, 0.0),
		Vector3(0.0, sqrt(MassCenterOrbit.MU / 7000.0), 0.0)
	)
	var attacker := FakeAttacker.new()
	var missile := Missile.new()
	var orbit := MassCenterOrbit.new(
		Vector3(7001.0, 0.0, 0.0),
		Vector3(0.0, sqrt(MassCenterOrbit.MU / 7001.0), 0.0)
	)
	missile.configure(orbit, target, attacker, 5.0, 75.0, 0.0, 100.0)
	# Terminate via expiry.
	missile.tick(1.0, 200.0)
	assert_eq(missile.last_termination, Missile.TERM_EXPIRED)
	# Reconfigure with fresh state.
	var orbit2 := MassCenterOrbit.new(
		Vector3(7100.0, 0.0, 0.0),
		Vector3(0.0, sqrt(MassCenterOrbit.MU / 7100.0), 0.0)
	)
	missile.configure(orbit2, target, attacker, 5.0, 75.0, 1000.0, 10000.0)
	assert_eq(missile.last_termination, -1)
	assert_true(missile.prev_distance_km == INF, "prev_distance_km must reset to INF")
	missile.free()
