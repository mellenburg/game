extends "res://tests/framework.gd"
## Railgun weapon unit tests. Uses real EarthOrbit instances on the
## fakes (rather than a duck-typed FakeOrbit like the laser tests)
## because the railgun's safety check actually cares about post-recoil
## orbital geometry — substituting it with a stub would defeat the
## point.

const RailgunWeapon = preload("res://scripts/weapons/railgun_weapon.gd")
const EarthOrbit = preload("res://scripts/earth_orbit.gd")

const EARTH_RADIUS_KM: float = EarthOrbit.EARTH_RADIUS_KM


# Minimal stand-in for Satellite — exposes only the fields the railgun
# reads (orbit, team, alive, orbit_alive, energy, hp, mass,
# max_orbital_radius_km, railgun_enabled). RefCounted so we don't leak
# across tests.
class FakeSat extends RefCounted:
	var orbit: EarthOrbit
	var team: int = 0
	var alive: bool = true
	var orbit_alive: bool = true
	var hp: float = 100.0
	var energy: float = 1.0
	var mass: float = 1000.0
	var max_orbital_radius_km: float = 50000.0
	var railgun_enabled: bool = true

	func take_damage(amount: float) -> bool:
		hp = maxf(hp - amount, 0.0)
		if hp <= 0.0:
			alive = false
			return true
		return false

	func invalidate_impact_cache() -> void:
		pass


# Player satellite at 500 km circular orbit, oriented along +x.
func _make_player(radius: float = EARTH_RADIUS_KM + 500.0) -> FakeSat:
	var s := FakeSat.new()
	s.team = 0
	var v_circ := sqrt(EarthOrbit.MU / radius)
	s.orbit = EarthOrbit.new(
		Vector3(radius, 0.0, 0.0), Vector3(0.0, v_circ, 0.0)
	)
	return s


# Enemy at the given position, on a circular-ish orbit at that radius
# in the y-z plane (so it's not co-linear with the player and LOS is
# clear).
func _make_enemy(pos: Vector3) -> FakeSat:
	var s := FakeSat.new()
	s.team = 1
	var radius := pos.length()
	var v_circ := sqrt(EarthOrbit.MU / radius)
	# Tangent in the y-z plane.
	s.orbit = EarthOrbit.new(pos, Vector3(0.0, 0.0, v_circ))
	return s


func test_idle_railgun_is_ready() -> void:
	var w := RailgunWeapon.new()
	assert_close(w.ready_fraction, 1.0)
	assert_false(w.overheated)


func test_cannot_fire_when_disabled() -> void:
	# X toggles railgun_enabled off → can_fire must refuse regardless
	# of energy / cooldown / target geometry.
	var w := RailgunWeapon.new()
	var attacker := _make_player()
	attacker.railgun_enabled = false
	assert_false(w.can_fire(attacker))


func test_cannot_fire_with_low_energy() -> void:
	var w := RailgunWeapon.new()
	var attacker := _make_player()
	attacker.energy = RailgunWeapon.ENERGY_PER_SHOT * 0.5
	assert_false(w.can_fire(attacker))


func test_fire_applies_damage_and_drains_energy_and_locks_cooldown() -> void:
	# Successful shot: target HP drops by DAMAGE_PER_SHOT, attacker
	# energy drops by ENERGY_PER_SHOT, cooldown latch trips.
	var w := RailgunWeapon.new()
	var attacker := _make_player()
	# Place target ~3000 km away laterally, well clear of LOS and
	# inside the safe-orbit envelope so the recoil is fine.
	var target := _make_enemy(Vector3(EARTH_RADIUS_KM + 500.0, 3000.0, 0.0))
	var energy_before := attacker.energy
	assert_true(w.fire(attacker, target, 1.0))
	assert_close(target.hp, 100.0 - RailgunWeapon.DAMAGE_PER_SHOT)
	assert_close(attacker.energy, energy_before - RailgunWeapon.ENERGY_PER_SHOT)
	assert_close(w.ready_fraction, 0.0)
	assert_true(w.overheated)
	# Locked: even with full energy, can't fire again until cool.
	attacker.energy = 1.0
	assert_false(w.can_fire(attacker))


func test_cooldown_recovers_at_design_rate() -> void:
	# Tick the weapon for COOLDOWN_SEC sim-seconds and verify the bar
	# climbs back to 1.0 and the lockout clears.
	var w := RailgunWeapon.new()
	var attacker := _make_player()
	var target := _make_enemy(Vector3(EARTH_RADIUS_KM + 500.0, 3000.0, 0.0))
	w.fire(attacker, target, 1.0)
	assert_true(w.overheated)
	w.tick(RailgunWeapon.COOLDOWN_SEC)
	assert_close(w.ready_fraction, 1.0)
	assert_false(w.overheated)


func test_recoil_and_target_push_conserve_momentum() -> void:
	# The whole point of the kinetic model: momentum delivered to
	# attacker (recoil) equals momentum delivered to target, with
	# opposite sign. m_a · Δv_a + m_t · Δv_t == 0 to numerical noise.
	var w := RailgunWeapon.new()
	var attacker := _make_player()
	var target := _make_enemy(Vector3(EARTH_RADIUS_KM + 500.0, 3000.0, 0.0))
	# Different masses to stress the asymmetric Δv distribution.
	attacker.mass = 1000.0
	target.mass = 500.0
	var v_a_before := attacker.orbit.v
	var v_t_before := target.orbit.v
	assert_true(w.fire(attacker, target, 1.0))
	var dv_a: Vector3 = attacker.orbit.v - v_a_before
	var dv_t: Vector3 = target.orbit.v - v_t_before
	var p_total: Vector3 = dv_a * attacker.mass + dv_t * target.mass
	assert_close(p_total.length(), 0.0, 1.0e-6)
	# Target's Δv should be 2× attacker's (mass ratio inverse), and
	# anti-parallel to the attacker's recoil (Newton's third law).
	assert_close(dv_t.length(), 2.0 * dv_a.length(), 1.0e-6)
	var unit_t := dv_t.normalized()
	var unit_a := dv_a.normalized()
	assert_close(unit_a.dot(unit_t), -1.0, 1.0e-6)


func test_does_not_engage_same_team() -> void:
	var w := RailgunWeapon.new()
	var attacker := _make_player()
	var ally := FakeSat.new()
	ally.team = 0
	var radius: float = EARTH_RADIUS_KM + 500.0
	var v_circ: float = sqrt(EarthOrbit.MU / radius)
	ally.orbit = EarthOrbit.new(
		Vector3(radius, 3000.0, 0.0), Vector3(0.0, 0.0, v_circ)
	)
	assert_false(w.is_target_in_engagement_envelope(attacker, ally))
	assert_false(w.fire(attacker, ally, 1.0))


func test_does_not_engage_when_los_blocked() -> void:
	# Target on the opposite side of Earth — segment from attacker to
	# target intersects the planet, so LOS is blocked and the railgun
	# should refuse fire.
	var w := RailgunWeapon.new()
	var attacker := _make_player(EARTH_RADIUS_KM + 500.0)
	var enemy := _make_enemy(Vector3(-(EARTH_RADIUS_KM + 500.0), 0.0, 0.0))
	assert_false(w.is_target_in_engagement_envelope(attacker, enemy))
	assert_false(w.fire(attacker, enemy, 1.0))


func test_refuses_shot_that_exceeds_max_orbital_radius() -> void:
	# Set the operator cap below the attacker's current circular
	# orbit. Any shot pushing apoapsis past the cap (which is what
	# any retrograde recoil would do here) must be refused; the
	# attacker's orbit must remain unchanged.
	var w := RailgunWeapon.new()
	var attacker := _make_player(EARTH_RADIUS_KM + 500.0)
	# Tighten cap to barely-above-current-radius so any recoil that
	# raises apoapsis trips the safety check. Target placed prograde
	# so the slug fires forward → recoil is retrograde → apoapsis
	# raises... wait, retrograde recoil at this position lowers
	# apoapsis. So flip: target retrograde so recoil is prograde →
	# apoapsis raises.
	# Player is at +x with v=+y. To produce a +y recoil (raising
	# apoapsis on this circular orbit), target must be at -y (the
	# slug fires in -y, recoil in +y). Place target so direction
	# from attacker to target is -y.
	attacker.max_orbital_radius_km = EARTH_RADIUS_KM + 510.0
	var enemy := FakeSat.new()
	enemy.team = 1
	var ey := EARTH_RADIUS_KM + 500.0
	enemy.orbit = EarthOrbit.new(
		Vector3(ey, -3000.0, 0.0),
		Vector3(0.0, 0.0, sqrt(EarthOrbit.MU / ey))
	)
	var v_before := attacker.orbit.v
	assert_false(RailgunWeapon.is_shot_safe_for_attacker(attacker, enemy))
	assert_false(w.fire(attacker, enemy, 1.0))
	# Attacker orbit untouched.
	assert_vec_close(attacker.orbit.v, v_before, 1.0e-9)


func test_refuses_shot_that_would_drop_periapsis_below_floor() -> void:
	# Aim so the recoil drives periapsis below the 100 km altitude
	# floor. From a circular orbit, prograde slug-fire produces
	# retrograde recoil that lowers periapsis. With huge slug
	# momentum (small attacker mass), we can drive periapsis under
	# the floor; the safety check must refuse.
	var w := RailgunWeapon.new()
	var attacker := _make_player(EARTH_RADIUS_KM + 500.0)
	# Modest mass cut so the recoil produces a periapsis-crash without
	# also exceeding escape velocity (which would hit the apoapsis-INF
	# branch first and never test the periapsis floor).
	attacker.mass = 10.0
	# Target prograde of attacker (+y direction) so slug fires +y →
	# recoil is -y → orbital velocity drops → periapsis crashes.
	var enemy := FakeSat.new()
	enemy.team = 1
	var ey := EARTH_RADIUS_KM + 500.0
	enemy.orbit = EarthOrbit.new(
		Vector3(ey, 3000.0, 0.0),
		Vector3(0.0, 0.0, sqrt(EarthOrbit.MU / ey))
	)
	assert_false(RailgunWeapon.is_shot_safe_for_attacker(attacker, enemy))
	assert_false(w.fire(attacker, enemy, 1.0))


func test_refuses_shot_that_would_cause_escape_velocity() -> void:
	# Same setup as the apoapsis test but with the cap at infinity —
	# the only failure mode left is escape. Tiny attacker mass
	# guarantees the prograde recoil exceeds escape velocity.
	var w := RailgunWeapon.new()
	var attacker := _make_player(EARTH_RADIUS_KM + 500.0)
	attacker.mass = 1.0
	attacker.max_orbital_radius_km = 1.0e12  # effectively no cap
	# Target retrograde → slug fires -y → recoil is +y → speeds up.
	var enemy := FakeSat.new()
	enemy.team = 1
	var ey := EARTH_RADIUS_KM + 500.0
	enemy.orbit = EarthOrbit.new(
		Vector3(ey, -3000.0, 0.0),
		Vector3(0.0, 0.0, sqrt(EarthOrbit.MU / ey))
	)
	assert_false(RailgunWeapon.is_shot_safe_for_attacker(attacker, enemy))
	assert_false(w.fire(attacker, enemy, 1.0))


func test_pick_target_does_not_gate_on_enabled_flag() -> void:
	# pick_target filters by envelope + shot safety; the enabled gate
	# is enforced by can_fire in the combat loop. The two layers are
	# decoupled so target prediction stays cheap regardless of toggle
	# state.
	var w := RailgunWeapon.new()
	var attacker := _make_player()
	attacker.railgun_enabled = false
	var enemy := _make_enemy(Vector3(EARTH_RADIUS_KM + 500.0, 3000.0, 0.0))
	var pick = w.pick_target(attacker, [attacker, enemy], 0.0)
	assert_eq(pick, enemy)


func test_pick_target_skips_unsafe_shots() -> void:
	# Two candidates: one would produce a safe shot, one would push
	# the shooter past max_orbital_radius. pick_target should always
	# return the safe one.
	var w := RailgunWeapon.new()
	var attacker := _make_player(EARTH_RADIUS_KM + 500.0)
	attacker.max_orbital_radius_km = EARTH_RADIUS_KM + 510.0
	# Safe enemy: target at +y (retrograde-of-velocity slug → recoil
	# drops orbital speed → apoapsis stays close to current radius
	# or below, periapsis drops slightly but stays above the floor).
	var safe_enemy := _make_enemy(
		Vector3(EARTH_RADIUS_KM + 500.0, 3000.0, 0.0)
	)
	# Unsafe enemy: at -y → recoil is +y → orbital speed rises →
	# apoapsis raises past the tight cap.
	var unsafe_enemy := FakeSat.new()
	unsafe_enemy.team = 1
	var ey := EARTH_RADIUS_KM + 500.0
	unsafe_enemy.orbit = EarthOrbit.new(
		Vector3(ey, -3000.0, 0.0),
		Vector3(0.0, 0.0, sqrt(EarthOrbit.MU / ey))
	)
	# Sanity: confirm the two are correctly classified.
	assert_true(RailgunWeapon.is_shot_safe_for_attacker(attacker, safe_enemy))
	assert_false(RailgunWeapon.is_shot_safe_for_attacker(attacker, unsafe_enemy))
	var pick = w.pick_target(
		attacker, [attacker, safe_enemy, unsafe_enemy], 0.0
	)
	assert_eq(pick, safe_enemy)


func test_fire_ignores_zero_or_negative_delta() -> void:
	var w := RailgunWeapon.new()
	var attacker := _make_player()
	var target := _make_enemy(Vector3(EARTH_RADIUS_KM + 500.0, 3000.0, 0.0))
	assert_false(w.fire(attacker, target, 0.0))
	assert_false(w.fire(attacker, target, -1.0))
	assert_close(target.hp, 100.0)
	assert_close(w.ready_fraction, 1.0)
