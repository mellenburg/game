extends "res://tests/framework.gd"
## Laser weapon unit tests. Uses a duck-typed FakeSat so the test
## doesn't need a SceneTree (Satellite is a Node3D).
##
## The laser is now an impulse weapon: damage and energy drain are
## per simulated second, and a heat budget (`ready_fraction`) ticks
## down while firing and back up while idle. Hitting 0% latches the
## `overheated` flag, which only clears once the bar climbs back to
## 100%.

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


func test_cool_rate_is_quarter_of_heat_rate() -> void:
	# Core invariant of the impulse model: heating outruns cooling 4:1.
	var w := LaserWeapon.new()
	assert_close(w.heat_rate(), 4.0 * w.cool_rate())


func test_idle_weapon_is_ready() -> void:
	var w := LaserWeapon.new()
	assert_close(w.ready_fraction, 1.0)
	assert_false(w.overheated)


func test_cannot_fire_with_no_energy() -> void:
	var w := LaserWeapon.new()
	var attacker := _make_player()
	attacker.energy = 0.0
	var target := _make_enemy(Vector3(EARTH_RADIUS_KM + 500.0, 1000.0, 0.0))
	assert_false(w.can_fire(attacker))
	assert_false(w.fire(attacker, target, 1.0))
	assert_close(target.hp, 100.0)


func test_fire_applies_damage_and_drains_energy_per_second() -> void:
	var w := LaserWeapon.new()
	var attacker := _make_player()
	attacker.energy = 1.0
	var target := _make_enemy(Vector3(EARTH_RADIUS_KM + 500.0, 1000.0, 0.0))
	# Fire for 2 sim-sec → 2 * DPS damage, 2 * cost drain, 2 * heat consumed.
	assert_true(w.fire(attacker, target, 2.0))
	assert_close(target.hp, 100.0 - 2.0 * LaserWeapon.DAMAGE_PER_SEC)
	assert_close(attacker.energy, 1.0 - 2.0 * LaserWeapon.ENERGY_PER_SEC)
	assert_close(w.ready_fraction, 1.0 - 2.0 * LaserWeapon.HEAT_PER_SEC)
	assert_false(w.overheated)


func test_idle_tick_cools_at_quarter_rate() -> void:
	var w := LaserWeapon.new()
	# Burn the bar down by firing for some time, then verify cool() climbs
	# back at exactly 1/4 the heat rate.
	var attacker := _make_player()
	attacker.energy = 1.0
	var target := _make_enemy(Vector3(EARTH_RADIUS_KM + 500.0, 1000.0, 0.0))
	assert_true(w.fire(attacker, target, 4.0))
	var after_fire := w.ready_fraction
	w.tick(4.0)
	assert_close(w.ready_fraction, after_fire + 4.0 * LaserWeapon.COOL_PER_SEC)


func test_continuous_fire_overheats_eventually() -> void:
	# Sustained fire should trip the overheat lockout once ready hits 0.
	# Use a giant energy pool by repeatedly topping up so heat is the
	# only limiter under test.
	var w := LaserWeapon.new()
	var attacker := _make_player()
	var target := _make_enemy(Vector3(EARTH_RADIUS_KM + 500.0, 1000.0, 0.0))
	target.hp = 1.0e9  # large so it survives the burn
	# Sim-seconds to fully overheat = 1 / HEAT_PER_SEC; pad slightly so
	# the final tick crosses zero.
	var burn := 1.0 / LaserWeapon.HEAT_PER_SEC + 1.0
	attacker.energy = burn * LaserWeapon.ENERGY_PER_SEC * 2.0
	assert_true(w.fire(attacker, target, burn))
	assert_close(w.ready_fraction, 0.0)
	assert_true(w.overheated)
	assert_false(w.can_fire(attacker))


func test_overheated_weapon_refuses_to_fire_until_fully_cool() -> void:
	# Latch behavior: once overheated, even a partial tick of cooling
	# must not let the weapon fire again until ready hits 1.0.
	var w := LaserWeapon.new()
	var attacker := _make_player()
	var target := _make_enemy(Vector3(EARTH_RADIUS_KM + 500.0, 1000.0, 0.0))
	target.hp = 1.0e9
	var burn := 1.0 / LaserWeapon.HEAT_PER_SEC + 1.0
	attacker.energy = burn * LaserWeapon.ENERGY_PER_SEC * 2.0
	w.fire(attacker, target, burn)
	assert_true(w.overheated)

	# Cool halfway back. Bar is at 50%, but lockout is still latched.
	var half_recover := 0.5 / LaserWeapon.COOL_PER_SEC
	w.tick(half_recover)
	assert_close(w.ready_fraction, 0.5, 1.0e-4)
	assert_true(w.overheated)
	attacker.energy = 1.0
	assert_false(w.can_fire(attacker))
	assert_false(w.fire(attacker, target, 1.0))

	# Finish cooling. Lockout clears as ready_fraction hits 1.0.
	w.tick(half_recover + 1.0)
	assert_close(w.ready_fraction, 1.0)
	assert_false(w.overheated)
	assert_true(w.can_fire(attacker))


func test_fire_does_not_overshoot_remaining_energy() -> void:
	# A long sim_delta with little energy should fire only as long as
	# the energy lasts — no negative-energy artifacts.
	var w := LaserWeapon.new()
	var attacker := _make_player()
	attacker.energy = 0.5 * LaserWeapon.ENERGY_PER_SEC  # 0.5 sim-sec budget
	var target := _make_enemy(Vector3(EARTH_RADIUS_KM + 500.0, 1000.0, 0.0))
	assert_true(w.fire(attacker, target, 10.0))
	assert_close(attacker.energy, 0.0)
	assert_close(target.hp, 100.0 - 0.5 * LaserWeapon.DAMAGE_PER_SEC)


func test_does_not_engage_same_team() -> void:
	var w := LaserWeapon.new()
	var attacker := _make_player()
	attacker.energy = 1.0
	var ally := _make_player(Vector3(EARTH_RADIUS_KM + 500.0, 1000.0, 0.0))
	assert_false(w.is_target_in_engagement_envelope(attacker, ally))
	assert_false(w.fire(attacker, ally, 1.0))
	assert_close(ally.hp, 100.0)
	assert_close(attacker.energy, 1.0)


func test_does_not_engage_when_los_blocked() -> void:
	var w := LaserWeapon.new()
	var attacker := _make_player(Vector3(EARTH_RADIUS_KM + 500.0, 0.0, 0.0))
	attacker.energy = 1.0
	var enemy := _make_enemy(Vector3(-(EARTH_RADIUS_KM + 500.0), 0.0, 0.0))
	assert_false(w.is_target_in_engagement_envelope(attacker, enemy))
	assert_false(w.fire(attacker, enemy, 1.0))
	assert_close(enemy.hp, 100.0)


func test_does_not_engage_dead_target() -> void:
	var w := LaserWeapon.new()
	var attacker := _make_player()
	attacker.energy = 1.0
	var enemy := _make_enemy(Vector3(EARTH_RADIUS_KM + 500.0, 1000.0, 0.0))
	enemy.alive = false
	assert_false(w.is_target_in_engagement_envelope(attacker, enemy))
	assert_false(w.fire(attacker, enemy, 1.0))


func test_tick_ignores_zero_or_negative_delta() -> void:
	var w := LaserWeapon.new()
	# Fire briefly to push ready below 1.0 so cooling has somewhere to
	# go; then verify a no-op tick really is a no-op.
	var attacker := _make_player()
	attacker.energy = 1.0
	var target := _make_enemy(Vector3(EARTH_RADIUS_KM + 500.0, 1000.0, 0.0))
	w.fire(attacker, target, 1.0)
	var ready_before := w.ready_fraction
	w.tick(0.0)
	assert_close(w.ready_fraction, ready_before)
	w.tick(-5.0)
	assert_close(w.ready_fraction, ready_before)


func test_fire_ignores_zero_or_negative_delta() -> void:
	var w := LaserWeapon.new()
	var attacker := _make_player()
	attacker.energy = 1.0
	var target := _make_enemy(Vector3(EARTH_RADIUS_KM + 500.0, 1000.0, 0.0))
	assert_false(w.fire(attacker, target, 0.0))
	assert_false(w.fire(attacker, target, -1.0))
	assert_close(target.hp, 100.0)
	assert_close(attacker.energy, 1.0)
	assert_close(w.ready_fraction, 1.0)
