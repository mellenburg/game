extends "res://tests/framework.gd"
## Laser weapon unit tests. Uses a duck-typed FakeSat so the test
## doesn't need a SceneTree (Satellite is a Node3D).
##
## The laser is a continuous-fire energy weapon: pool joules drain at
## POOL_DRAIN_W per sim-sec while firing, and waste heat (joules)
## accumulates at POOL_DRAIN_W × HEAT_FRACTION while firing. Hitting
## HEAT_CAPACITY_J latches the `overheated` flag, which only clears
## once the cooling system bleeds heat back to zero. Damage is
## computed from radiated power × target coupling / J_PER_HP — physical
## units rather than the abstract DPS the previous balance pass used.

const LaserWeapon = preload("res://scripts/weapons/laser_weapon.gd")
const Weapon = preload("res://scripts/weapons/weapon.gd")
const EARTH_RADIUS_KM: float = 6371.0


class FakeOrbit extends RefCounted:
	var r: Vector3 = Vector3(6871.0, 0.0, 0.0)  # 6371 + 500


# Minimal stand-in for Satellite — exposes only the fields the weapon
# reads (orbit.r, team, alive, orbit_alive, energy, hp,
# engagement_range_km). RefCounted so we don't leak across tests.
# Energy default scales to a full default-class pool so tests that
# don't explicitly seed energy can still fire for several seconds
# before running dry.
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
	# Inert-asteroid flag: when true, the weapon's envelope check
	# treats this target as "atmosphere will finish it" and refuses to
	# engage. Tests that exercise the burn-up skip flip this to true.
	var inert: bool = false

	func is_inert_asteroid() -> bool:
		return inert

	func _init() -> void:
		orbit = FakeOrbit.new()

	func take_damage(amount: float, _attacker = null) -> bool:
		hp = maxf(hp - amount, 0.0)
		if hp <= 0.0:
			alive = false
			return true
		return false


# Convenience: the per-instance DPS at zero range against a
# default-coupling target (no tier multiplier). Most tests assert HP
# losses against multiples of this number, so naming it once here
# keeps the assertions readable.
const ZERO_RANGE_DPS: float = (
	LaserWeapon.RADIATED_POWER_W * LaserWeapon.TARGET_COUPLING_DEFAULT
	/ Weapon.J_PER_HP
)
# Heat-per-sim-sec while firing, in joules. Tests assert against this
# directly so the new heat-in-joules invariants stay legible.
const HEAT_PER_SEC_W: float = LaserWeapon.POOL_DRAIN_W * LaserWeapon.HEAT_FRACTION
# Pool seed for tests that just need "enough energy to fire for a few
# seconds without going dry". 40 TJ buys ~120 sec of continuous fire
# at the 333 GW pool draw rate — far more than any of these tests
# burn through, so heat and time become the gating constraints. Tests
# that specifically exercise the energy-budget cap (or the empty-pool
# refusal) seed `energy` directly to a tighter number.
const STARTING_ENERGY_J: float = 4.0e13


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


func test_heat_fraction_matches_wallplug_inverse() -> void:
	# Heat = waste energy, so heat_fraction must be 1 - wallplug efficiency.
	# Pinning so a future tweak to either constant doesn't silently break
	# energy conservation in the heat model.
	var w := LaserWeapon.new()
	assert_close(w.heat_fraction, 1.0 - LaserWeapon.WALLPLUG_EFFICIENCY)
	assert_close(LaserWeapon.HEAT_FRACTION, 0.7)


func test_idle_weapon_is_ready() -> void:
	var w := LaserWeapon.new()
	assert_close(w.heat_j, 0.0)
	assert_close(w.heat_capacity_j, LaserWeapon.HEAT_CAPACITY_J, 1.0)
	assert_close(w.ready_progress(), 1.0)
	assert_false(w.overheated)
	# Idle weapon doesn't demand cooling — cooling power is freed up
	# for whichever sibling gun is hot. This is the field
	# CombatController polls when splitting cooling power across
	# multiple weapons on the same hull.
	assert_false(w.demands_cooling())


func test_demands_cooling_after_fire() -> void:
	# Any non-zero heat means the weapon wants cooling this tick.
	# Pinning so the controller's "split evenly across demanders" rule
	# stays consistent with what fire() leaves behind.
	var w := LaserWeapon.new()
	var attacker := _make_player()
	attacker.energy = STARTING_ENERGY_J
	var target := _make_enemy(Vector3(EARTH_RADIUS_KM + 500.0, 1000.0, 0.0))
	w.fire(attacker, target, 1.0)
	assert_true(w.heat_j > 0.0)
	assert_true(w.demands_cooling())
	# Drain back to zero ⇒ no demand.
	w.cool(w.heat_j, 1.0)
	assert_close(w.heat_j, 0.0)
	assert_false(w.demands_cooling())


func test_cannot_fire_with_no_energy() -> void:
	var w := LaserWeapon.new()
	var attacker := _make_player()
	attacker.energy = 0.0
	var target := _make_enemy(Vector3(EARTH_RADIUS_KM + 500.0, 1000.0, 0.0))
	assert_false(w.can_fire(attacker))
	assert_false(w.fire(attacker, target, 1.0))
	assert_close(target.hp, 100.0)


func test_fire_applies_damage_drains_energy_and_adds_heat() -> void:
	var w := LaserWeapon.new()
	var attacker := _make_player()
	attacker.energy = STARTING_ENERGY_J
	var target := _make_enemy(Vector3(EARTH_RADIUS_KM + 500.0, 1000.0, 0.0))
	# Bump HP above the per-burn damage so we can verify the exact
	# subtraction rather than asserting the take_damage clamp at zero.
	target.hp = 1.0e9
	# Fire for 2 sim-sec → 2 * DPS * range_factor(d) damage, 2 * cost
	# drain, 2 * heat-per-sec joules of heat. Distance is 1000 km so the
	# falloff factor is non-trivial (~0.95) and shows up in the assertion.
	var dist: float = (target.orbit.r - attacker.orbit.r).length()
	var rf: float = LaserWeapon.range_factor(dist)
	var hp_before := target.hp
	assert_true(w.fire(attacker, target, 2.0))
	assert_close(target.hp, hp_before - 2.0 * ZERO_RANGE_DPS * rf, 1.0e-3)
	# Energy and heat costs are flat in time — distance only modulates
	# damage, not the per-second burn. Tolerance scaled to the pool
	# size — assert_close's 1e-6 default is meaningless against billions
	# of joules.
	assert_close(
		attacker.energy,
		STARTING_ENERGY_J - 2.0 * LaserWeapon.POOL_DRAIN_W,
		1.0,
	)
	assert_close(w.heat_j, 2.0 * HEAT_PER_SEC_W, 1.0)
	assert_false(w.overheated)


func test_cool_drains_heat_at_supplied_power() -> void:
	# Burn the bar down by firing for some time, then verify cool() pulls
	# heat down at exactly the supplied power × dt.
	var w := LaserWeapon.new()
	var attacker := _make_player()
	attacker.energy = STARTING_ENERGY_J
	var target := _make_enemy(Vector3(EARTH_RADIUS_KM + 500.0, 1000.0, 0.0))
	assert_true(w.fire(attacker, target, 4.0))
	var heat_after_fire: float = w.heat_j
	# 100 MW of cooling for 1 sec drains 100 MJ of heat.
	w.cool(1.0e8, 1.0)
	assert_close(w.heat_j, heat_after_fire - 1.0e8, 1.0)


func test_continuous_fire_overheats_at_capacity() -> void:
	# Sustained fire should trip the overheat lockout once heat hits
	# capacity. Use a giant energy pool so heat is the only limiter.
	var w := LaserWeapon.new()
	var attacker := _make_player()
	var target := _make_enemy(Vector3(EARTH_RADIUS_KM + 500.0, 1000.0, 0.0))
	target.hp = 1.0e9  # large so it survives the burn
	# Sim-sec to fully overheat = HEAT_CAPACITY_J / heat-per-sec; pad
	# slightly so the final tick crosses zero.
	var burn := LaserWeapon.HEAT_CAPACITY_J / HEAT_PER_SEC_W + 1.0
	attacker.energy = burn * LaserWeapon.POOL_DRAIN_W * 2.0
	assert_true(w.fire(attacker, target, burn))
	assert_close(w.heat_j, LaserWeapon.HEAT_CAPACITY_J, 1.0)
	assert_true(w.overheated)
	assert_false(w.can_fire(attacker))


func test_overheated_weapon_refuses_to_fire_until_fully_cool() -> void:
	# Latch behavior: once overheated, even a partial cool tick must not
	# let the weapon fire again until heat hits 0.
	var w := LaserWeapon.new()
	var attacker := _make_player()
	var target := _make_enemy(Vector3(EARTH_RADIUS_KM + 500.0, 1000.0, 0.0))
	target.hp = 1.0e9
	var burn := LaserWeapon.HEAT_CAPACITY_J / HEAT_PER_SEC_W + 1.0
	attacker.energy = burn * LaserWeapon.POOL_DRAIN_W * 2.0
	w.fire(attacker, target, burn)
	assert_true(w.overheated)

	# Cool halfway back. Heat is at 50%, but lockout is still latched.
	# Use a 10 MW cooler running for whatever time drains exactly half.
	var half := LaserWeapon.HEAT_CAPACITY_J * 0.5
	w.cool(half, 1.0)  # 1 sec at 'half' watts ⇒ removes exactly half
	assert_close(w.heat_j, half, 1.0)
	assert_true(w.overheated)
	# Re-fill the pool — refusal to fire must come from the lockout,
	# not an empty reservoir.
	attacker.energy = STARTING_ENERGY_J
	assert_false(w.can_fire(attacker))
	assert_false(w.fire(attacker, target, 1.0))

	# Finish cooling. Lockout clears as heat hits 0.
	w.cool(half * 1.1, 1.0)
	assert_close(w.heat_j, 0.0)
	assert_false(w.overheated)
	assert_true(w.can_fire(attacker))


func test_fire_does_not_overshoot_remaining_energy() -> void:
	# A long sim_delta with little energy should fire only as long as
	# the energy lasts — no negative-energy artifacts.
	var w := LaserWeapon.new()
	var attacker := _make_player()
	attacker.energy = 0.5 * LaserWeapon.POOL_DRAIN_W  # 0.5 sim-sec budget
	var target := _make_enemy(Vector3(EARTH_RADIUS_KM + 500.0, 1000.0, 0.0))
	# HP big enough that 0.5 sec of zero-range fire leaves a residual
	# rather than clamping at the take_damage floor.
	target.hp = 1.0e9
	var dist: float = (target.orbit.r - attacker.orbit.r).length()
	var rf: float = LaserWeapon.range_factor(dist)
	var hp_before := target.hp
	assert_true(w.fire(attacker, target, 10.0))
	# Pool is in joules, so the residual after a balanced drain may
	# carry a few cents of float noise — 1 J is well below the
	# 333 GJ/s drain rate.
	assert_close(attacker.energy, 0.0, 1.0)
	assert_close(target.hp, hp_before - 0.5 * ZERO_RANGE_DPS * rf, 1.0e-3)


func test_does_not_engage_same_team() -> void:
	var w := LaserWeapon.new()
	var attacker := _make_player()
	attacker.energy = STARTING_ENERGY_J
	var ally := _make_player(Vector3(EARTH_RADIUS_KM + 500.0, 1000.0, 0.0))
	assert_false(w.is_target_in_engagement_envelope(attacker, ally))
	assert_false(w.fire(attacker, ally, 1.0))
	assert_close(ally.hp, 100.0)
	assert_close(attacker.energy, STARTING_ENERGY_J)


func test_does_not_engage_when_los_blocked() -> void:
	var w := LaserWeapon.new()
	var attacker := _make_player(Vector3(EARTH_RADIUS_KM + 500.0, 0.0, 0.0))
	attacker.energy = STARTING_ENERGY_J
	var enemy := _make_enemy(Vector3(-(EARTH_RADIUS_KM + 500.0), 0.0, 0.0))
	assert_false(w.is_target_in_engagement_envelope(attacker, enemy))
	assert_false(w.fire(attacker, enemy, 1.0))
	assert_close(enemy.hp, 100.0)


func test_does_not_engage_inert_asteroid() -> void:
	# An asteroid that's been chipped down past the atmospheric burn-up
	# threshold reports `is_inert_asteroid() == true`. Lasers should
	# disengage so they re-allocate fire to remaining live threats
	# rather than burning energy on a body the atmosphere will finish.
	var w := LaserWeapon.new()
	var attacker := _make_player()
	attacker.energy = STARTING_ENERGY_J
	var enemy := _make_enemy(Vector3(EARTH_RADIUS_KM + 500.0, 1000.0, 0.0))
	enemy.inert = true
	assert_false(w.is_target_in_engagement_envelope(attacker, enemy))


func test_does_not_engage_dead_target() -> void:
	var w := LaserWeapon.new()
	var attacker := _make_player()
	attacker.energy = STARTING_ENERGY_J
	var enemy := _make_enemy(Vector3(EARTH_RADIUS_KM + 500.0, 1000.0, 0.0))
	enemy.alive = false
	assert_false(w.is_target_in_engagement_envelope(attacker, enemy))
	assert_false(w.fire(attacker, enemy, 1.0))


func test_cool_ignores_zero_or_negative_inputs() -> void:
	var w := LaserWeapon.new()
	# Fire briefly to push heat above 0 so cooling has somewhere to go.
	var attacker := _make_player()
	attacker.energy = STARTING_ENERGY_J
	var target := _make_enemy(Vector3(EARTH_RADIUS_KM + 500.0, 1000.0, 0.0))
	w.fire(attacker, target, 1.0)
	var heat_before := w.heat_j
	w.cool(0.0, 1.0)
	assert_close(w.heat_j, heat_before)
	w.cool(1.0e7, 0.0)
	assert_close(w.heat_j, heat_before)
	w.cool(-1.0e7, 1.0)
	assert_close(w.heat_j, heat_before)


func test_fire_ignores_zero_or_negative_delta() -> void:
	var w := LaserWeapon.new()
	var attacker := _make_player()
	attacker.energy = STARTING_ENERGY_J
	var target := _make_enemy(Vector3(EARTH_RADIUS_KM + 500.0, 1000.0, 0.0))
	assert_false(w.fire(attacker, target, 0.0))
	assert_false(w.fire(attacker, target, -1.0))
	assert_close(target.hp, 100.0)
	assert_close(attacker.energy, STARTING_ENERGY_J)
	assert_close(w.heat_j, 0.0)


func test_range_factor_follows_diffraction_curve() -> void:
	# Near field (≤ Rayleigh range) is full damage; far field falls as
	# (L₀/L)². MAX_RANGE_KM is fixed at 10·L₀, so the cutoff lands at
	# the 1% intensity radius — verified directly against the curve.
	var l0: float = LaserWeapon.RAYLEIGH_RANGE_KM
	# Endpoints and inside the near field collapse to 1.0.
	assert_close(LaserWeapon.range_factor(0.0), 1.0)
	assert_close(LaserWeapon.range_factor(l0 * 0.5), 1.0)
	assert_close(LaserWeapon.range_factor(l0), 1.0)
	# Far field: intensity = (L₀/L)². 2·L₀ → 25%, 5·L₀ → 4%.
	assert_close(LaserWeapon.range_factor(l0 * 2.0), 0.25)
	assert_close(LaserWeapon.range_factor(l0 * 5.0), 0.04)
	# Hard cap at MAX_RANGE_KM. The 1% boundary lands exactly at the
	# cap by construction (10·L₀); past it the envelope and the falloff
	# both report zero.
	assert_close(LaserWeapon.range_factor(LaserWeapon.MAX_RANGE_KM), 0.0)
	assert_close(LaserWeapon.range_factor(LaserWeapon.MAX_RANGE_KM * 2.0), 0.0)
	# Negative inputs clamp to full damage; this guards against a
	# regression where a degenerate distance leaks negative damage.
	assert_close(LaserWeapon.range_factor(-100.0), 1.0)


func test_rayleigh_range_matches_aperture_and_wavelength() -> void:
	# L₀ = D² / λ, expressed in km. Pinning so a future tweak to
	# aperture or wavelength updates the engagement bands consistently
	# (everything downstream — MAX_RANGE_KM, near-field damage band,
	# the menu's "Full-damage range" row — is derived from this number).
	var expected_m: float = (
		LaserWeapon.APERTURE_DIAMETER_M
		* LaserWeapon.APERTURE_DIAMETER_M
		/ LaserWeapon.WAVELENGTH_M
	)
	assert_close(LaserWeapon.RAYLEIGH_RANGE_KM, expected_m / 1000.0)
	# Cap is the 1% intensity radius — exactly 10·L₀.
	assert_close(LaserWeapon.MAX_RANGE_KM, 10.0 * LaserWeapon.RAYLEIGH_RANGE_KM)


func test_damage_scales_with_distance() -> void:
	# Two attackers at different distances from their (separate) target
	# should deal damage in the ratio of their range_factors. A short
	# stationary target setup keeps LOS clear in both cases.
	var w_near := LaserWeapon.new()
	var w_far := LaserWeapon.new()
	var atk_near := _make_player(Vector3(EARTH_RADIUS_KM + 500.0, 0.0, 0.0))
	var atk_far := _make_player(Vector3(EARTH_RADIUS_KM + 500.0, 0.0, 0.0))
	atk_near.energy = STARTING_ENERGY_J
	atk_far.energy = STARTING_ENERGY_J
	# 2000 km vs 8000 km lateral offset — both well clear of LOS
	# blockage at this altitude, both well inside MAX_RANGE_KM.
	var tgt_near := _make_enemy(Vector3(EARTH_RADIUS_KM + 500.0, 2000.0, 0.0))
	var tgt_far := _make_enemy(Vector3(EARTH_RADIUS_KM + 500.0, 8000.0, 0.0))
	# HP large enough that a 1-sec zero-range burn leaves a measurable
	# residue at both ranges instead of clamping at zero.
	tgt_near.hp = 1.0e9
	tgt_far.hp = 1.0e9
	var hp_before := tgt_near.hp
	assert_true(w_near.fire(atk_near, tgt_near, 1.0))
	assert_true(w_far.fire(atk_far, tgt_far, 1.0))
	var dmg_near: float = hp_before - tgt_near.hp
	var dmg_far: float = hp_before - tgt_far.hp
	assert_true(dmg_near > dmg_far, "near hit should damage more than far hit")
	# Ratio should match the analytic falloff curve.
	var d_near: float = (tgt_near.orbit.r - atk_near.orbit.r).length()
	var d_far: float = (tgt_far.orbit.r - atk_far.orbit.r).length()
	var rf_near: float = LaserWeapon.range_factor(d_near)
	var rf_far: float = LaserWeapon.range_factor(d_far)
	assert_close(dmg_near, ZERO_RANGE_DPS * rf_near, 1.0e-3)
	assert_close(dmg_far, ZERO_RANGE_DPS * rf_far, 1.0e-3)


func test_does_not_engage_beyond_max_range() -> void:
	# A target past MAX_RANGE_KM is out of envelope regardless of
	# engagement_range_km — physics ceiling caps the operator setting.
	var w := LaserWeapon.new()
	var attacker := _make_player(Vector3(EARTH_RADIUS_KM + 500.0, 0.0, 0.0))
	attacker.energy = STARTING_ENERGY_J
	var far := LaserWeapon.MAX_RANGE_KM + 1000.0
	var enemy := _make_enemy(
		Vector3(EARTH_RADIUS_KM + 500.0, far, 10000.0)
	)
	assert_false(w.is_target_in_engagement_envelope(attacker, enemy))
	assert_false(w.fire(attacker, enemy, 1.0))
	assert_close(enemy.hp, 100.0)
	assert_close(attacker.energy, STARTING_ENERGY_J)


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
	attacker.energy = STARTING_ENERGY_J
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
	attacker.energy = STARTING_ENERGY_J
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
