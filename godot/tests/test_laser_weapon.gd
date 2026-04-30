extends "res://tests/framework.gd"
## Laser weapon unit tests. Uses a duck-typed FakeSat so the test
## doesn't need a SceneTree (Satellite is a Node3D).
##
## Energy lives on the attacker now (Satellite owns the shared pool),
## so each test sets attacker.energy explicitly rather than calling a
## charge() method on the weapon.

const LaserWeapon = preload("res://scripts/weapons/laser_weapon.gd")
const EARTH_RADIUS_KM: float = 6371.0


class FakeOrbit extends RefCounted:
	var r: Vector3 = Vector3(6871.0, 0.0, 0.0)  # 6371 + 500


# Minimal stand-in for Satellite — exposes only the fields the weapon
# reads (orbit.r, team, alive, orbit_alive, energy, hp). RefCounted so
# we don't leak across tests.
class FakeSat extends RefCounted:
	var orbit: FakeOrbit
	var team: int = 0
	var alive: bool = true
	var orbit_alive: bool = true
	var hp: float = 100.0
	var energy: float = 0.0

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


func test_cannot_fire_below_one_shot_cost() -> void:
	var w := LaserWeapon.new()
	var attacker := _make_player()
	attacker.energy = LaserWeapon.ENERGY_PER_SHOT - 0.01
	var target := _make_enemy(Vector3(EARTH_RADIUS_KM + 500.0, 1000.0, 0.0))
	assert_false(w.can_fire(attacker))
	assert_false(w.fire(attacker, target))
	assert_eq(target.hp, 100.0)


func test_fires_as_soon_as_one_shot_is_affordable() -> void:
	# Fire-when-affordable: the laser shouldn't sit idle on a partial
	# reservoir while a target is in sights — it should engage as soon
	# as energy reaches the per-shot cost.
	var w := LaserWeapon.new()
	var attacker := _make_player()
	attacker.energy = LaserWeapon.ENERGY_PER_SHOT
	var target := _make_enemy(Vector3(EARTH_RADIUS_KM + 500.0, 1000.0, 0.0))
	assert_true(w.can_fire(attacker))
	assert_true(w.fire(attacker, target))
	assert_close(target.hp, 75.0)
	assert_close(attacker.energy, 0.0)


func test_fires_and_drains_attacker_energy() -> void:
	var w := LaserWeapon.new()
	var attacker := _make_player()
	attacker.energy = 1.0
	var target := _make_enemy(Vector3(EARTH_RADIUS_KM + 500.0, 1000.0, 0.0))
	assert_true(w.fire(attacker, target))
	assert_close(target.hp, 75.0)
	assert_close(attacker.energy, 1.0 - LaserWeapon.ENERGY_PER_SHOT)
	assert_close(w.cooldown_remaining, LaserWeapon.COOLDOWN_SIM_SEC)


func test_cooldown_blocks_immediate_followup_shot() -> void:
	# Even with energy left over, cooldown gates the next shot until
	# the locked-out window passes.
	var w := LaserWeapon.new()
	var attacker := _make_player()
	attacker.energy = 1.0
	var target := _make_enemy(Vector3(EARTH_RADIUS_KM + 500.0, 1000.0, 0.0))
	assert_true(w.fire(attacker, target))
	assert_false(w.can_fire(attacker))  # energy is fine; cooldown isn't
	assert_false(w.fire(attacker, target))
	assert_close(target.hp, 75.0)


func test_can_fire_again_after_cooldown_clears() -> void:
	var w := LaserWeapon.new()
	var attacker := _make_player()
	attacker.energy = 1.0
	var target := _make_enemy(Vector3(EARTH_RADIUS_KM + 500.0, 1000.0, 0.0))
	assert_true(w.fire(attacker, target))
	# Burn off the entire cooldown in one tick — caller-provided sim
	# time can dwarf the cooldown when time_factor is high.
	w.tick(LaserWeapon.COOLDOWN_SIM_SEC + 1.0)
	assert_close(w.cooldown_remaining, 0.0)
	assert_close(w.cooldown_progress(), 1.0)
	assert_true(w.can_fire(attacker))
	assert_true(w.fire(attacker, target))
	assert_close(target.hp, 50.0)


func test_cooldown_progress_grows_with_tick() -> void:
	var w := LaserWeapon.new()
	var attacker := _make_player()
	attacker.energy = 1.0
	var target := _make_enemy(Vector3(EARTH_RADIUS_KM + 500.0, 1000.0, 0.0))
	assert_close(w.cooldown_progress(), 1.0)  # idle weapon: ready
	assert_true(w.fire(attacker, target))
	assert_close(w.cooldown_progress(), 0.0)  # just fired
	w.tick(LaserWeapon.COOLDOWN_SIM_SEC * 0.5)
	assert_close(w.cooldown_progress(), 0.5)


func test_does_not_engage_same_team() -> void:
	var w := LaserWeapon.new()
	var attacker := _make_player()
	attacker.energy = 1.0
	var ally := _make_player(Vector3(EARTH_RADIUS_KM + 500.0, 1000.0, 0.0))
	assert_false(w.is_target_in_engagement_envelope(attacker, ally))
	assert_false(w.fire(attacker, ally))
	assert_close(ally.hp, 100.0)
	assert_close(attacker.energy, 1.0)


func test_does_not_engage_when_los_blocked() -> void:
	var w := LaserWeapon.new()
	var attacker := _make_player(Vector3(EARTH_RADIUS_KM + 500.0, 0.0, 0.0))
	attacker.energy = 1.0
	var enemy := _make_enemy(Vector3(-(EARTH_RADIUS_KM + 500.0), 0.0, 0.0))
	assert_false(w.is_target_in_engagement_envelope(attacker, enemy))
	assert_false(w.fire(attacker, enemy))
	assert_close(enemy.hp, 100.0)


func test_does_not_engage_dead_target() -> void:
	var w := LaserWeapon.new()
	var attacker := _make_player()
	attacker.energy = 1.0
	var enemy := _make_enemy(Vector3(EARTH_RADIUS_KM + 500.0, 1000.0, 0.0))
	enemy.alive = false
	assert_false(w.is_target_in_engagement_envelope(attacker, enemy))
	assert_false(w.fire(attacker, enemy))


func test_kills_after_four_hits() -> void:
	var attacker := _make_player()
	var enemy := _make_enemy(Vector3(EARTH_RADIUS_KM + 500.0, 1000.0, 0.0))
	for _i in range(4):
		var w := LaserWeapon.new()  # fresh weapon each shot to skip cooldown
		attacker.energy = 1.0
		assert_true(w.fire(attacker, enemy))
	assert_close(enemy.hp, 0.0)
	assert_false(enemy.alive)


func test_tick_ignores_zero_or_negative_delta() -> void:
	var w := LaserWeapon.new()
	var attacker := _make_player()
	attacker.energy = 1.0
	var target := _make_enemy(Vector3(EARTH_RADIUS_KM + 500.0, 1000.0, 0.0))
	assert_true(w.fire(attacker, target))
	var cd := w.cooldown_remaining
	w.tick(0.0)
	assert_close(w.cooldown_remaining, cd)
	w.tick(-5.0)
	assert_close(w.cooldown_remaining, cd)
