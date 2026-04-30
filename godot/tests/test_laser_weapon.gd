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
# reads (orbit.r, team, alive, orbit_alive, energy, hp,
# engagement_range_km). RefCounted so we don't leak across tests.
class FakeSat extends RefCounted:
	var orbit: FakeOrbit
	var team: int = 0
	var alive: bool = true
	var orbit_alive: bool = true
	var hp: float = 100.0
	var energy: float = 0.0
	# Default to MAX_RANGE_KM so unconfigured fakes behave like a fresh
	# Satellite: the engagement cap doesn't narrow the envelope unless
	# a test explicitly tightens it.
	var engagement_range_km: float = LaserWeapon.MAX_RANGE_KM
	# Fire control off by default. The cap is only enforced while the
	# operator has fire control on — tests that exercise the cap must
	# flip this to true.
	var fire_control_active: bool = false

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
	# Fire for 2 sim-sec → 2 * DPS * range_factor(d) damage, 2 * cost
	# drain, 2 * heat consumed. Distance is 1000 km so the falloff
	# factor is non-trivial (~0.95) and shows up in the assertion.
	var dist: float = (target.orbit.r - attacker.orbit.r).length()
	var rf: float = LaserWeapon.range_factor(dist)
	assert_true(w.fire(attacker, target, 2.0))
	assert_close(target.hp, 100.0 - 2.0 * LaserWeapon.DAMAGE_PER_SEC * rf)
	# Energy and heat costs are flat in time — distance only modulates
	# damage, not the per-second burn. That's a deliberate design call
	# (see laser_weapon.gd) so long-range potshots cost as much as they
	# would point-blank.
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
	var dist: float = (target.orbit.r - attacker.orbit.r).length()
	var rf: float = LaserWeapon.range_factor(dist)
	assert_true(w.fire(attacker, target, 10.0))
	assert_close(attacker.energy, 0.0)
	assert_close(target.hp, 100.0 - 0.5 * LaserWeapon.DAMAGE_PER_SEC * rf)


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


func test_range_factor_is_linear_with_distance() -> void:
	# Endpoints clamp; middle is the linear interpolation.
	assert_close(LaserWeapon.range_factor(0.0), 1.0)
	assert_close(LaserWeapon.range_factor(LaserWeapon.MAX_RANGE_KM), 0.0)
	assert_close(
		LaserWeapon.range_factor(LaserWeapon.MAX_RANGE_KM * 0.5), 0.5
	)
	# Negative or beyond-max inputs both clamp; this guards against a
	# regression where a degenerate distance leaks negative damage.
	assert_close(LaserWeapon.range_factor(-100.0), 1.0)
	assert_close(LaserWeapon.range_factor(LaserWeapon.MAX_RANGE_KM * 2.0), 0.0)


func test_damage_scales_with_distance() -> void:
	# Two attackers at different distances from their (separate) target
	# should deal damage in the ratio of their range_factors. A short
	# stationary target setup keeps LOS clear in both cases.
	var w_near := LaserWeapon.new()
	var w_far := LaserWeapon.new()
	var atk_near := _make_player(Vector3(EARTH_RADIUS_KM + 500.0, 0.0, 0.0))
	var atk_far := _make_player(Vector3(EARTH_RADIUS_KM + 500.0, 0.0, 0.0))
	atk_near.energy = 1.0
	atk_far.energy = 1.0
	# 2000 km vs 8000 km lateral offset — both well clear of LOS
	# blockage at this altitude, both well inside MAX_RANGE_KM.
	var tgt_near := _make_enemy(Vector3(EARTH_RADIUS_KM + 500.0, 2000.0, 0.0))
	var tgt_far := _make_enemy(Vector3(EARTH_RADIUS_KM + 500.0, 8000.0, 0.0))
	assert_true(w_near.fire(atk_near, tgt_near, 1.0))
	assert_true(w_far.fire(atk_far, tgt_far, 1.0))
	var dmg_near: float = 100.0 - tgt_near.hp
	var dmg_far: float = 100.0 - tgt_far.hp
	assert_true(dmg_near > dmg_far, "near hit should damage more than far hit")
	# Ratio should match the analytic falloff curve.
	var d_near: float = (tgt_near.orbit.r - atk_near.orbit.r).length()
	var d_far: float = (tgt_far.orbit.r - atk_far.orbit.r).length()
	var rf_near: float = LaserWeapon.range_factor(d_near)
	var rf_far: float = LaserWeapon.range_factor(d_far)
	assert_close(dmg_near, LaserWeapon.DAMAGE_PER_SEC * rf_near)
	assert_close(dmg_far, LaserWeapon.DAMAGE_PER_SEC * rf_far)


func test_does_not_engage_beyond_max_range() -> void:
	# A target past MAX_RANGE_KM is out of envelope regardless of
	# engagement_range_km — physics ceiling caps the operator setting.
	var w := LaserWeapon.new()
	var attacker := _make_player(Vector3(EARTH_RADIUS_KM + 500.0, 0.0, 0.0))
	attacker.energy = 1.0
	var far := LaserWeapon.MAX_RANGE_KM + 1000.0
	var enemy := _make_enemy(
		Vector3(EARTH_RADIUS_KM + 500.0, far, 10000.0)
	)
	assert_false(w.is_target_in_engagement_envelope(attacker, enemy))
	assert_false(w.fire(attacker, enemy, 1.0))
	assert_close(enemy.hp, 100.0)
	assert_close(attacker.energy, 1.0)


func test_engagement_range_gates_fire_only_with_fire_control_on() -> void:
	# A target inside MAX_RANGE_KM but outside the operator's
	# engagement_range_km is rejected ONLY while fire control is on —
	# otherwise the saved cap is ignored and the weapon fires at any
	# LOS enemy. This is the "toggle off restores defaults" contract
	# (a player who tightens the cap, then disables fire control,
	# expects their lasers to fire freely again without first having
	# to widen the slider).
	var w := LaserWeapon.new()
	var attacker := _make_player(Vector3(EARTH_RADIUS_KM + 500.0, 0.0, 0.0))
	attacker.energy = 1.0
	# Place enemy 6000 km away laterally.
	var enemy := _make_enemy(Vector3(EARTH_RADIUS_KM + 500.0, 6000.0, 0.0))
	# Tighten engagement to 3000 km. With fire control off the cap is
	# silently ignored — the laser still fires at the 6000 km enemy.
	attacker.engagement_range_km = 3000.0
	attacker.fire_control_active = false
	assert_true(w.is_target_in_engagement_envelope(attacker, enemy))
	# Now turn fire control on — same engagement_range_km, but the cap
	# is now honored and the enemy falls outside.
	attacker.fire_control_active = true
	assert_false(w.is_target_in_engagement_envelope(attacker, enemy))
	assert_false(w.fire(attacker, enemy, 1.0))
	assert_close(enemy.hp, 100.0)
	# Open the cap past the actual distance and the fire goes through.
	attacker.engagement_range_km = 10000.0
	assert_true(w.is_target_in_engagement_envelope(attacker, enemy))
	assert_true(w.fire(attacker, enemy, 1.0))
	assert_true(enemy.hp < 100.0)


func test_toggling_fire_control_off_restores_default_engagement() -> void:
	# Regression: previously the engagement_range_km cap was enforced
	# unconditionally, so toggling fire control off after tightening
	# the slider left the laser silently refusing to engage targets
	# beyond the saved cap. The fix gates the cap behind
	# fire_control_active; the saved value persists so toggling back
	# on restores the operator's chosen ring.
	var w := LaserWeapon.new()
	var attacker := _make_player(Vector3(EARTH_RADIUS_KM + 500.0, 0.0, 0.0))
	attacker.energy = 1.0
	var enemy := _make_enemy(Vector3(EARTH_RADIUS_KM + 500.0, 6000.0, 0.0))
	# Operator opens fire control, dials the cap below the enemy.
	attacker.fire_control_active = true
	attacker.engagement_range_km = 1000.0
	assert_false(w.is_target_in_engagement_envelope(attacker, enemy))
	# Operator toggles fire control off — the saved cap remains
	# (preserved across toggles) but is no longer enforced.
	attacker.fire_control_active = false
	assert_close(attacker.engagement_range_km, 1000.0)
	assert_true(w.is_target_in_engagement_envelope(attacker, enemy))
	assert_true(w.fire(attacker, enemy, 1.0))
