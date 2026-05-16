extends "res://tests/framework.gd"
## MissileSpawner unit tests. The reservation map and active-missile
## tracking are the primary contracts — spawn/tick/terminate must
## release a reservation exactly once even under unusual termination
## paths (target lost, expiry, miss). queue_free inside tick doesn't
## actually free in headless tests (no idle frames), so nodes leak;
## the leak is bounded by the test count and process-lifetime, so
## it's acceptable — same pattern as test_slug_renderer.gd.

const MissileSpawner = preload("res://scripts/missile_spawner.gd")
const Missile = preload("res://scripts/missile.gd")
const MassCenterOrbit = preload("res://scripts/mass_center_orbit.gd")


class FakeTarget extends RefCounted:
	var orbit: MassCenterOrbit
	var alive: bool = true
	var orbit_alive: bool = true
	var hp: float = 100.0

	func take_damage(amount: float, _attacker = null) -> bool:
		hp = maxf(hp - amount, 0.0)
		if hp <= 0.0:
			alive = false
			return true
		return false


class FakeAttacker extends RefCounted:
	var alive: bool = true


func _make_pending(launch_r: Vector3, launch_v: Vector3, target: Object, attacker: Object) -> Dictionary:
	# Construct the same pending Dict shape that MissileWeapon.prepare_shot
	# returns, so the spawner doesn't have to know about weapons.
	return {
		"launch_r": launch_r,
		"launch_v": launch_v,
		"target_iid": target.get_instance_id() if target != null else 0,
		"attacker_iid": attacker.get_instance_id() if attacker != null else 0,
		"tof": 120.0,
		"blast_radius_km": 5.0,
		"damage_hp": 75.0,
		"spawn_sim_time": 0.0,
		"expiry_sim_time": 300.0,
	}


func _make_target() -> FakeTarget:
	var t := FakeTarget.new()
	var r := Vector3(7000.0, 0.0, 0.0)
	var v := Vector3(0.0, sqrt(MassCenterOrbit.MU / 7000.0), 0.0)
	t.orbit = MassCenterOrbit.new(r, v)
	return t


func test_empty_spawner_has_no_missiles_or_reservations() -> void:
	var sp := MissileSpawner.new()
	assert_eq(sp.active_missile_count(), 0)
	assert_eq(sp.reserved_target_count(), 0)
	# tick on empty spawner is a no-op.
	assert_eq(sp.tick(1.0, 0.0), 0)


func test_spawn_adds_missile_and_reserves_target() -> void:
	var sp := MissileSpawner.new()
	var target := _make_target()
	var attacker := FakeAttacker.new()
	var pending := _make_pending(
		Vector3(7100.0, 0.0, 0.0),
		Vector3(0.0, sqrt(MassCenterOrbit.MU / 7100.0), 0.0),
		target, attacker
	)
	var m: Missile = sp.spawn(attacker, target, pending, 0.0)
	assert_true(m != null)
	assert_eq(sp.active_missile_count(), 1)
	assert_eq(sp.reserved_target_count(), 1)
	assert_true(sp.has_reservation(target.get_instance_id()))


func test_reservation_blocks_double_check() -> void:
	# has_reservation is the gate CombatController uses to prevent
	# double-shooting; verify it correctly reports membership.
	var sp := MissileSpawner.new()
	var target := _make_target()
	var attacker := FakeAttacker.new()
	var pending := _make_pending(
		Vector3(7100.0, 0.0, 0.0),
		Vector3(0.0, sqrt(MassCenterOrbit.MU / 7100.0), 0.0),
		target, attacker
	)
	assert_false(sp.has_reservation(target.get_instance_id()))
	sp.spawn(attacker, target, pending, 0.0)
	assert_true(sp.has_reservation(target.get_instance_id()))
	# A different target should not be flagged.
	var other := _make_target()
	assert_false(sp.has_reservation(other.get_instance_id()))


func test_tick_releases_reservation_when_missile_terminates() -> void:
	var sp := MissileSpawner.new()
	var target := _make_target()
	var attacker := FakeAttacker.new()
	# Spawn the missile right on top of the target so tick(0.1, 0.0)
	# detonates immediately.
	var pending := _make_pending(
		target.orbit.r + Vector3(1.0, 0.0, 0.0),
		target.orbit.v,
		target, attacker
	)
	sp.spawn(attacker, target, pending, 0.0)
	assert_eq(sp.active_missile_count(), 1)
	assert_eq(sp.reserved_target_count(), 1)

	var terminated: int = sp.tick(0.1, 0.0)
	assert_eq(terminated, 1, "tick should report one termination")
	assert_eq(sp.active_missile_count(), 0, "active list must drop terminated")
	assert_eq(sp.reserved_target_count(), 0, "reservation must release")


func test_tick_reservation_releases_on_expiry() -> void:
	# Missile pointed away from target with a short expiry. The
	# expiry path should still release the reservation.
	var sp := MissileSpawner.new()
	var target := _make_target()
	var attacker := FakeAttacker.new()
	var pending := _make_pending(
		Vector3(15000.0, 0.0, 0.0),
		Vector3(0.0, sqrt(MassCenterOrbit.MU / 15000.0), 0.0),
		target, attacker
	)
	pending.expiry_sim_time = 50.0  # short expiry
	sp.spawn(attacker, target, pending, 0.0)
	assert_eq(sp.reserved_target_count(), 1)
	# Tick past the expiry deadline.
	sp.tick(60.0, 60.0)
	assert_eq(sp.reserved_target_count(), 0)
	assert_eq(sp.active_missile_count(), 0)


func test_clear_all_drops_every_missile_and_reservation() -> void:
	var sp := MissileSpawner.new()
	var attacker := FakeAttacker.new()
	# Spawn three missiles at three different targets.
	for i in range(3):
		var t := _make_target()
		var pending := _make_pending(
			Vector3(10000.0 + 100.0 * i, 0.0, 0.0),
			Vector3(0.0, sqrt(MassCenterOrbit.MU / (10000.0 + 100.0 * i)), 0.0),
			t, attacker
		)
		sp.spawn(attacker, t, pending, 0.0)
	assert_eq(sp.active_missile_count(), 3)
	assert_eq(sp.reserved_target_count(), 3)
	sp.clear_all()
	assert_eq(sp.active_missile_count(), 0)
	assert_eq(sp.reserved_target_count(), 0)


func test_two_missiles_independent_reservations() -> void:
	# Two targets, two missiles — both reservations stand simultaneously.
	var sp := MissileSpawner.new()
	var attacker := FakeAttacker.new()
	var t1 := _make_target()
	var t2 := _make_target()
	sp.spawn(attacker, t1, _make_pending(
		Vector3(7500.0, 0.0, 0.0),
		Vector3(0.0, sqrt(MassCenterOrbit.MU / 7500.0), 0.0),
		t1, attacker
	), 0.0)
	sp.spawn(attacker, t2, _make_pending(
		Vector3(8000.0, 0.0, 0.0),
		Vector3(0.0, sqrt(MassCenterOrbit.MU / 8000.0), 0.0),
		t2, attacker
	), 0.0)
	assert_eq(sp.reserved_target_count(), 2)
	assert_true(sp.has_reservation(t1.get_instance_id()))
	assert_true(sp.has_reservation(t2.get_instance_id()))
