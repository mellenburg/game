extends "res://tests/framework.gd"
## Railgun weapon unit tests. Uses real EarthOrbit instances on the
## fakes (rather than a duck-typed FakeOrbit like the laser tests)
## because the railgun's safety check actually cares about post-recoil
## orbital geometry — substituting it with a stub would defeat the
## point.

const RailgunWeapon = preload("res://scripts/weapons/railgun_weapon.gd")
const EarthOrbit = preload("res://scripts/earth_orbit.gd")

const EARTH_RADIUS_KM: float = EarthOrbit.EARTH_RADIUS_KM
# Pool seed for tests that just need "enough energy to fire a shot"
# — a single railgun shot draws ~13.3 GJ from the bus, so the fake's
# pool has to comfortably exceed that. 40 GJ leaves headroom for ~3
# shots before the energy gate kicks in, which is enough for every
# test that doesn't specifically exercise pool exhaustion. Tests
# exercising the empty-pool refusal seed `energy` directly.
const STARTING_ENERGY_J: float = 4.0e10


# Minimal stand-in for Satellite — exposes only the fields the railgun
# reads (orbit, team, alive, orbit_alive, energy, hp, mass,
# max_orbital_radius_km, railgun_enabled, is_surface). RefCounted so
# we don't leak across tests.
class FakeSat extends RefCounted:
	var orbit: EarthOrbit
	var team: int = 0
	var alive: bool = true
	var orbit_alive: bool = true
	var hp: float = 100.0
	# Default to a full 10 GJ pool so most tests can fire without
	# explicitly seeding energy. Tests exercising the energy-budget
	# refusal seed this directly to a tighter number.
	var energy: float = 4.0e10
	var mass: float = 1000.0
	var max_orbital_radius_km: float = 50000.0
	var railgun_enabled: bool = true
	# Railgun.can_fire refuses surface-anchored attackers; default false
	# matches the orbital path the existing tests exercise.
	var is_surface: bool = false

	func take_damage(amount: float, _attacker = null) -> bool:
		hp = maxf(hp - amount, 0.0)
		if hp <= 0.0:
			alive = false
			return true
		return false

	func invalidate_impact_cache() -> void:
		pass


# Player satellite at a circular orbit oriented along +x. Default
# altitude 5000 km (radius ~11 371 km) is comfortably above the
# safety floor + margin for the design SLUG_MOMENTUM: 200 m/s
# retrograde recoil from this altitude drops periapsis to ~10 000
# km, well clear of the 6 471 km floor. Refusal-case tests pass
# `R+500` explicitly to deliberately set up the LEO geometry where
# the same recoil tips the shooter's orbit unsafe.
func _make_player(radius: float = EARTH_RADIUS_KM + 5000.0) -> FakeSat:
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
	assert_close(w.heat_j, 0.0)
	assert_close(w.heat_capacity_j, RailgunWeapon.HEAT_CAPACITY_J, 1.0)
	assert_close(w.ready_progress(), 1.0)
	assert_false(w.overheated)


func test_heat_capacity_equals_one_shot_of_heat() -> void:
	# Per the design spec: the railgun's heat capacity must be exactly
	# one shot. Firing once fully fills it; the overheat latch then
	# refuses to fire again until the cooling system has bled every
	# joule. Pinning the equality here so a future tweak can't silently
	# let the rails fire twice before tripping.
	assert_close(
		RailgunWeapon.HEAT_CAPACITY_J,
		RailgunWeapon.HEAT_PER_SHOT_J,
		1.0,
	)
	# The heat dump is the wallplug waste of one shot.
	assert_close(
		RailgunWeapon.HEAT_PER_SHOT_J,
		RailgunWeapon.ENERGY_PER_SHOT_J * (1.0 - RailgunWeapon.WALLPLUG_EFFICIENCY),
		1.0,
	)


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
	attacker.energy = RailgunWeapon.ENERGY_PER_SHOT_J * 0.5
	assert_false(w.can_fire(attacker))


func test_cannot_fire_from_surface_unit() -> void:
	# Surface installations are mechanically anchored and can't absorb
	# the recoil sensibly — the railgun refuses to fire from them
	# regardless of energy / cooldown / safety geometry.
	var w := RailgunWeapon.new()
	var attacker := _make_player()
	attacker.is_surface = true
	assert_false(w.can_fire(attacker))


func test_fire_applies_damage_and_drains_energy_and_locks_cooldown() -> void:
	# Successful shot: target HP drops by base_damage_per_shot(),
	# attacker energy drops by ENERGY_PER_SHOT_J (joules now, not a
	# pool fraction), cooldown latch trips, and the magazine pops a
	# round. Damage / energy units are physical — see the design
	# discussion in CLAUDE.md and weapon.gd's J_PER_HP comment.
	var w := RailgunWeapon.new()
	var attacker := _make_player()
	# Place target ~3000 km away laterally, well clear of LOS and
	# inside the safe-orbit envelope so the recoil is fine. Bumped HP
	# above the per-shot damage so we can verify the exact subtraction
	# rather than asserting the take_damage clamp at zero — the
	# default 100 HP is one-shotted by a 400-HP railgun round.
	var target := _make_enemy(Vector3(EARTH_RADIUS_KM + 500.0, 3000.0, 0.0))
	target.hp = 1000.0
	var energy_before := attacker.energy
	var ammo_before := w.ammo_count
	assert_true(w.fire(attacker, target, 1.0))
	assert_close(target.hp, 1000.0 - RailgunWeapon.base_damage_per_shot())
	# 1 J tolerance is well below the 3.3 GJ per-shot draw — assert_close
	# defaults to 1e-6 which can't measure a number this large.
	assert_close(
		attacker.energy, energy_before - RailgunWeapon.ENERGY_PER_SHOT_J, 1.0,
	)
	assert_eq(w.ammo_count, ammo_before - 1)
	assert_close(w.heat_j, RailgunWeapon.HEAT_CAPACITY_J, 1.0)
	assert_true(w.overheated)
	# Locked: even with full energy, can't fire again until cool.
	attacker.energy = STARTING_ENERGY_J
	assert_false(w.can_fire(attacker))


func test_cool_clears_overheat_when_heat_hits_zero() -> void:
	# Apply enough cooling power × dt to drain the rail's full heat
	# capacity and verify the lockout clears.
	var w := RailgunWeapon.new()
	var attacker := _make_player()
	var target := _make_enemy(Vector3(EARTH_RADIUS_KM + 500.0, 3000.0, 0.0))
	w.fire(attacker, target, 1.0)
	assert_true(w.overheated)
	# Drain in one tick by applying the full capacity worth of cooling
	# in 1 sim-sec. cool() clamps at 0.
	w.cool(RailgunWeapon.HEAT_CAPACITY_J, 1.0)
	assert_close(w.heat_j, 0.0)
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
	# Tolerance is 1e-3 (kg·km/s) rather than 1e-6 because the
	# components in play are ~200 kg·km/s, and 32-bit Vector3
	# precision on values that size leaves noise around 1e-5 per
	# component — comfortably below 1e-3, comfortably above 1e-6.
	assert_close(p_total.length(), 0.0, 1.0e-3)
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
	# branch first and never test the periapsis floor). Sized against
	# the current SLUG_MOMENTUM: 200 kg·km/s / 50 kg = 4 km/s recoil,
	# which on a 7.6 km/s circular orbit drops periapsis below the
	# 100 km altitude floor while staying clearly bound.
	attacker.mass = 50.0
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
	# Two candidates: one would produce a safe shot, one would drop
	# the shooter's periapsis below the 100 km altitude floor.
	# pick_target should always return the safe one.
	var w := RailgunWeapon.new()
	var attacker := _make_player(EARTH_RADIUS_KM + 500.0)
	# Generous cap so the apoapsis ceiling never trips — the test is
	# specifically about the periapsis floor refusing the unsafe
	# shot, not about the operator's max-radius slider.
	attacker.max_orbital_radius_km = 12000.0
	# Safe enemy: laterally offset from the attacker's orbital plane
	# (+z direction). Recoil is purely perpendicular to the
	# attacker's velocity, so the orbit barely changes and both
	# r_p and r_a stay comfortably inside bounds.
	var sr := EARTH_RADIUS_KM + 500.0
	var safe_enemy := FakeSat.new()
	safe_enemy.team = 1
	safe_enemy.orbit = EarthOrbit.new(
		Vector3(sr, 0.0, 3000.0),
		Vector3(0.0, sqrt(EarthOrbit.MU / sr), 0.0)
	)
	# Unsafe enemy: prograde of attacker (+y). Slug fires +y →
	# recoil is -y (retrograde) → orbital velocity drops →
	# periapsis falls below the floor and the shot is refused.
	var unsafe_enemy := _make_enemy(Vector3(sr, 3000.0, 0.0))
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
	assert_close(w.heat_j, 0.0)
