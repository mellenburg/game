class_name RailgunWeapon
extends "res://scripts/weapons/weapon.gd"
## Single-shot kinetic weapon — pure abstract momentum transfer. The
## slug's travel time is ignored: on fire, the shooter receives a
## recoil Δv and the target receives an opposite-sign Δv along the
## attacker→target ray, both scaled by 1/mass. Damage to the target is
## a fixed per-shot value; the slug itself is never simulated.
##
## Pre-fire safety check refuses any shot whose recoil would (a) drive
## the shooter onto an escape trajectory, (b) push apoapsis past the
## operator-set max_orbital_radius_km, or (c) drop periapsis below the
## hard-coded SAFE_PERIAPSIS_KM atmospheric floor. The fleet-wide
## railgun_enabled gate is checked separately in can_fire — turning it
## off via X silences every railgun in the fleet without disturbing
## laser fire.
##
## Targeting is random across LOS-clear opposing-team candidates: the
## railgun has no range falloff, so picking the closest enemy would
## produce repetitive engagements. Random-pick keeps each fleet
## engagement visually distinct without complicating the AI.

const LosCheck = preload("res://scripts/los_check.gd")
const EarthOrbit = preload("res://scripts/earth_orbit.gd")

# Slug momentum (kg·km/s). 200 kg·km/s on a 1 t satellite ⇒ 200 m/s
# Δv per shot, ~2.6% of LEO orbital velocity — small enough that a
# single shot doesn't immediately doom the shooter, large enough that
# the orbit visibly shifts in the next render tick. Symmetric on the
# target side, so a meteorite (1 t) deflects by 200 m/s along the
# shot ray, plenty to nudge it off an impact path with a few hits.
const SLUG_MOMENTUM_KG_KM_S: float = 200.0
# Energy fraction drained per shot. With ENERGY_RATE_PER_SIM_SEC at
# 0.00014 the reservoir takes ~24 minutes of sim time to refill from
# empty, so a sustained railgun engagement is energy-bound.
const ENERGY_PER_SHOT: float = 0.20
# Damage per shot. Three shots kill a 100 HP enemy sat — enough that
# the railgun reads as a heavy weapon, not a peashooter.
const DAMAGE_PER_SHOT: float = 35.0
# Sim-seconds for the cooldown bar to climb from 0 (just-fired) back
# to 1 (ready). At the default time_factor=500 that's ~1.2 seconds
# of wall-clock — comparable to the laser's full overheat-cool cycle
# but felt as a single discrete beat between shots rather than a
# saturation lockout. Sized far slower than the original 12 sim-sec
# value, which compressed to a near-instant strobe at high
# time_factor.
const COOLDOWN_SEC: float = 600.0
const COOL_PER_SEC: float = 1.0 / COOLDOWN_SEC
# Hard floor on the shooter's post-recoil periapsis: 100 km clearance
# above Earth's surface, per the design spec. Lives on the weapon (the
# code that consumes it) so the safety predicate is self-contained.
const SAFE_PERIAPSIS_KM: float = EarthOrbit.EARTH_RADIUS_KM + 100.0


func cool_rate() -> float:
	return COOL_PER_SEC


func display_name() -> String:
	return "Railgun"


func can_fire(attacker) -> bool:
	if attacker == null:
		return false
	if not attacker.railgun_enabled:
		return false
	# Surface installations are mechanically anchored to Earth — applying
	# a recoil Δv to a static structure has no clean physical analogue,
	# and fire() would mutate orbit.v in a state the next physics tick
	# overwrites from update_surface_position anyway. Refuse outright so
	# the shot never leaves the barrel.
	if attacker.is_surface:
		return false
	# Single-shot: must be fully cool. Locked out for the entire window
	# so partial cools don't drip fractional shots.
	if ready_fraction < 1.0:
		return false
	return attacker.energy >= ENERGY_PER_SHOT


## Envelope for the railgun is purely "is this a live opposing-team
## body with clear LOS?" — there is no range cap. The shooter-safety
## predicate (orbit-shape preservation) is checked separately in
## fire(), since it depends on the actual geometry of the picked shot.
func is_target_in_engagement_envelope(attacker, target) -> bool:
	if attacker == null or target == null:
		return false
	if not attacker.alive or not target.alive:
		return false
	if attacker.team == target.team:
		return false
	if not attacker.orbit_alive or not target.orbit_alive:
		return false
	return not LosCheck.is_blocked(attacker.orbit.r, target.orbit.r)


## Predict whether firing along the attacker→target ray would keep the
## shooter's resulting orbit inside [SAFE_PERIAPSIS, max_orbital_radius]
## and below escape velocity. Pure function on (attacker.orbit.r,
## attacker.orbit.v, attacker.mass, attacker.max_orbital_radius_km,
## SAFE_PERIAPSIS, target direction) — no mutation, used both as the
## fire() gate and (indirectly via test coverage) as the spec for the
## "refuse to escape Earth" rule.
static func is_shot_safe_for_attacker(attacker, target) -> bool:
	if attacker == null or target == null or attacker.mass <= 0.0:
		return false
	# Explicit Vector3 / float annotations: attacker / target flow in as
	# untyped Variants (the weapon base class can't preload Satellite),
	# so ':=' inference would land on Variant and trip the strict
	# inference_on_variant warning. The arithmetic still runs through
	# Variant at compile time; the typed locals just pin the result.
	var to_target: Vector3 = target.orbit.r - attacker.orbit.r
	var dist_sq: float = to_target.length_squared()
	if dist_sq <= 0.0:
		return false
	var dir: Vector3 = to_target / sqrt(dist_sq)
	# Shooter recoils opposite the slug's flight direction. Mass
	# divides momentum into Δv directly — that's the whole point of
	# tracking unit mass separately from HP.
	var recoil_dv: Vector3 = -dir * (SLUG_MOMENTUM_KG_KM_S / attacker.mass)
	var new_v: Vector3 = attacker.orbit.v + recoil_dv
	var r_a: float = EarthOrbit.compute_apoapsis(attacker.orbit.r, new_v)
	if not is_finite(r_a):
		return false
	if r_a > attacker.max_orbital_radius_km:
		return false
	var r_p: float = EarthOrbit.compute_periapsis(attacker.orbit.r, new_v)
	if r_p < SAFE_PERIAPSIS_KM:
		return false
	return true


## Random pick across in-envelope opposing-team candidates. Ignores
## attacker.targeting_mode entirely — the laser owns that setting; a
## railgun engagement with no range falloff has no analogous "pick
## closest" preference. Returns null when no candidate is in envelope
## OR when none of the in-envelope candidates would produce a safe
## shot (so a railgun staring down a single high-orbit target it
## cannot safely shoot doesn't fire wildly at off-screen bodies — it
## just holds fire).
func pick_target(attacker, candidates: Array, _sim_time: float):
	if attacker == null:
		return null
	var pool: Array = []
	for other in candidates:
		if other == attacker:
			continue
		if other.team == attacker.team:
			continue
		if not is_target_in_engagement_envelope(attacker, other):
			continue
		if not is_shot_safe_for_attacker(attacker, other):
			continue
		pool.append(other)
	if pool.is_empty():
		return null
	return pool[randi() % pool.size()]


func fire(attacker, target, sim_delta: float) -> bool:
	if sim_delta <= 0.0:
		return false
	if not can_fire(attacker):
		return false
	if not is_target_in_engagement_envelope(attacker, target):
		return false
	if not is_shot_safe_for_attacker(attacker, target):
		return false
	if target.mass <= 0.0:
		return false

	var to_target: Vector3 = target.orbit.r - attacker.orbit.r
	var dist_sq: float = to_target.length_squared()
	if dist_sq <= 0.0:
		return false
	var dir: Vector3 = to_target / sqrt(dist_sq)
	var attacker_dv: Vector3 = -dir * (SLUG_MOMENTUM_KG_KM_S / attacker.mass)
	var target_dv: Vector3 = dir * (SLUG_MOMENTUM_KG_KM_S / target.mass)

	# Apply impulses through orbit.maneuver(t=0) so the orbit's derived
	# elements (r_p, r_a, period, …) get recomputed atomically. A
	# successful safety check should mean the shooter's maneuver is
	# always valid; we still guard so a numerical edge case doesn't
	# leave the attacker in a partially-mutated state.
	if not attacker.orbit.maneuver(attacker_dv, 0.0):
		return false
	attacker.invalidate_impact_cache()
	# Target's resulting orbit can be anything (including sub-orbital);
	# advance_time will catch a sub-surface trajectory next tick. If
	# the propagator rejects the maneuver outright, mark the target's
	# orbit dead so the renderer doesn't see NaN.
	if not target.orbit.maneuver(target_dv, 0.0):
		target.orbit_alive = false
	target.invalidate_impact_cache()

	target.take_damage(DAMAGE_PER_SHOT)
	attacker.energy = maxf(attacker.energy - ENERGY_PER_SHOT, 0.0)
	# Latch cooldown: ready falls to 0, overheated locks out can_fire
	# until ready climbs back to 1.0 via base Weapon.tick(). Mirrors
	# the laser's overheat semantics so the HUD bar reads consistently.
	ready_fraction = 0.0
	overheated = true
	return true
