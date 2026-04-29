extends "res://tests/framework.gd"
## Laser weapon unit tests. Uses a duck-typed FakeSat so the test
## doesn't need a SceneTree (Satellite is a Node3D).

const LaserWeapon = preload("res://scripts/weapons/laser_weapon.gd")
const EARTH_RADIUS_KM: float = 6371.0


class FakeOrbit extends RefCounted:
	var r: Vector3 = Vector3(6871.0, 0.0, 0.0)  # 6371 + 500


# Minimal stand-in for Satellite — exposes only the fields the weapon
# reads (orbit.r, team, alive, orbit_alive). RefCounted so we don't
# leak across tests.
class FakeSat extends RefCounted:
	var orbit: FakeOrbit
	var team: int = 0
	var alive: bool = true
	var orbit_alive: bool = true
	var hp: float = 100.0

	func _init() -> void:
		orbit = FakeOrbit.new()

	func take_damage(amount: float) -> bool:
		hp = maxf(hp - amount, 0.0)
		if hp <= 0.0:
			alive = false
			return true
		return false


func _make_player(pos: Vector3 = Vector3(EARTH_RADIUS_KM + 500.0, 0.0, 0.0)) -> FakeSat:
	var s := FakeSat.new()
	s.team = 0
	s.orbit.r = pos
	return s


func _make_enemy(pos: Vector3) -> FakeSat:
	var s := FakeSat.new()
	s.team = 1
	s.orbit.r = pos
	return s


func test_charge_accumulates_with_sim_delta() -> void:
	var w := LaserWeapon.new()
	assert_close(w.energy, 0.0)
	w.charge(10.0)  # 10 sim seconds * 0.01 = 0.1
	assert_close(w.energy, 0.1)
	w.charge(50.0)
	assert_close(w.energy, 0.6)


func test_charge_clamps_at_full() -> void:
	var w := LaserWeapon.new()
	w.charge(10000.0)
	assert_close(w.energy, 1.0)
	assert_true(w.can_fire())


func test_cannot_fire_below_full() -> void:
	var w := LaserWeapon.new()
	w.charge(50.0)  # 50%
	var attacker := _make_player()
	var target := _make_enemy(Vector3(EARTH_RADIUS_KM + 500.0, 1000.0, 0.0))
	assert_false(w.can_fire())
	assert_false(w.fire(attacker, target))
	assert_eq(target.hp, 100.0)


func test_fires_and_resets_energy() -> void:
	var w := LaserWeapon.new()
	w.charge(10000.0)
	var attacker := _make_player()
	var target := _make_enemy(Vector3(EARTH_RADIUS_KM + 500.0, 1000.0, 0.0))
	assert_true(w.fire(attacker, target))
	assert_close(target.hp, 75.0)
	assert_close(w.energy, 0.0)


func test_does_not_engage_same_team() -> void:
	var w := LaserWeapon.new()
	w.charge(10000.0)
	var attacker := _make_player()
	var ally := _make_player(Vector3(EARTH_RADIUS_KM + 500.0, 1000.0, 0.0))
	assert_false(w.is_target_in_engagement_envelope(attacker, ally))
	assert_false(w.fire(attacker, ally))
	assert_close(ally.hp, 100.0)
	assert_close(w.energy, 1.0)


func test_does_not_engage_when_los_blocked() -> void:
	var w := LaserWeapon.new()
	w.charge(10000.0)
	# Antipodal: ray passes through Earth.
	var attacker := _make_player(Vector3(EARTH_RADIUS_KM + 500.0, 0.0, 0.0))
	var enemy := _make_enemy(Vector3(-(EARTH_RADIUS_KM + 500.0), 0.0, 0.0))
	assert_false(w.is_target_in_engagement_envelope(attacker, enemy))
	assert_false(w.fire(attacker, enemy))
	assert_close(enemy.hp, 100.0)


func test_does_not_engage_dead_target() -> void:
	var w := LaserWeapon.new()
	w.charge(10000.0)
	var attacker := _make_player()
	var enemy := _make_enemy(Vector3(EARTH_RADIUS_KM + 500.0, 1000.0, 0.0))
	enemy.alive = false
	assert_false(w.is_target_in_engagement_envelope(attacker, enemy))
	assert_false(w.fire(attacker, enemy))


func test_kills_after_four_hits() -> void:
	var attacker := _make_player()
	var enemy := _make_enemy(Vector3(EARTH_RADIUS_KM + 500.0, 1000.0, 0.0))
	for _i in range(4):
		var w := LaserWeapon.new()
		w.charge(10000.0)
		assert_true(w.fire(attacker, enemy))
	assert_close(enemy.hp, 0.0)
	assert_false(enemy.alive)


func test_charge_ignores_zero_or_negative_delta() -> void:
	var w := LaserWeapon.new()
	w.charge(0.0)
	assert_close(w.energy, 0.0)
	w.charge(-5.0)
	assert_close(w.energy, 0.0)
