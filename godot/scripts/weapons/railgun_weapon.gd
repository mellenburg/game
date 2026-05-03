class_name RailgunWeapon
extends "res://scripts/weapons/weapon.gd"
## Single-shot kinetic weapon — physical mass-driver. Each shot fires
## a SLUG_MASS_KG slug at MUZZLE_VELOCITY_M_S. Slug travel time is
## ignored: on fire the shooter receives a recoil Δv and the target
## receives an opposite-sign Δv along the attacker→target ray, both
## scaled by 1/mass. Damage is the slug's muzzle KE coupled into the
## target through `target_coupling_for(target)` and converted to HP at
## the global Weapon.J_PER_HP rate.
##
## Each weapon ships with a fixed magazine of MAGAZINE_SIZE rounds.
## Ammo dominates the unit's wet-mass budget — 1000 × 20 kg = 20 t,
## an order of magnitude heavier than the airframe — so as the
## magazine empties the shooter's mass falls and recoil per shot
## climbs. An empty magazine refuses fire: the weapon's still cool but
## there's nothing to launch.
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

# Slug physics. 20 kg at 20 km/s ⇒ 400 kg·km/s of momentum and 4 GJ
# of muzzle KE. 20 km/s is ~8× a real Navy railgun and ~80% of solar
# escape from LEO; fast enough that slug travel can be ignored at
# engagement ranges *and* the damage / recoil chain reads as a
# heavy-hitter weapon (one shot one-kills a default-HP target,
# recoil per shot on a fully-loaded 21 t hull is ~19 m/s).
const SLUG_MASS_KG: float = 20.0
const MUZZLE_VELOCITY_M_S: float = 20000.0
# Pre-derived for callers that want either side of the conversion
# without redoing the multiplication. Keeping these as constants makes
# it loud if someone changes one without the other.
const SLUG_MUZZLE_KE_J: float = (
	0.5 * SLUG_MASS_KG * MUZZLE_VELOCITY_M_S * MUZZLE_VELOCITY_M_S
)
# Momentum in km/s units to match orbit.v's km/s convention. Multiply
# the SI product by 1e-3 once here so the recoil math (in km/s) reads
# cleanly without per-call unit conversion.
const SLUG_MOMENTUM_KG_KM_S: float = SLUG_MASS_KG * MUZZLE_VELOCITY_M_S * 1.0e-3
# Magazine: how many rounds the unit ships with. Fixed across all
# tiers in the MVP; advanced railguns hit harder via damage_mult, not
# bigger magazines.
const MAGAZINE_SIZE: int = 1000
# Pool→slug-KE conversion. Real EM launchers run ~30-50% wall-plug
# efficient; the rest is heat in the rails / capacitor losses. 30% is
# the conservative end and makes the per-shot pool draw a meaningful
# bite (one shot ≈ 33% of a default 10 GJ pool).
const WALLPLUG_EFFICIENCY: float = 0.3
# Joules drawn from the shared pool per shot. Independent of damage
# coupling — the wall plug doesn't know how absorbent the target is.
const ENERGY_PER_SHOT_J: float = SLUG_MUZZLE_KE_J / WALLPLUG_EFFICIENCY
# Default kinetic-on-armour coupling: ~50% of slug KE transfers to
# absorbed damage; the rest fragments / passes through / spalls off
# the back face. Per-target overrides land here later via the base
# class's target_coupling_for() hook.
const TARGET_COUPLING_DEFAULT: float = 0.5
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

# Damage tier multiplier — see laser_weapon.gd for the rationale.
# Cooldown is now sourced from the radiator complement via the base
# class's cool_rate field; advanced railguns just hit harder. Slug
# physics + ammo capacity stay the same across tiers.
var damage_mult: float = 1.0
# Remaining rounds in the magazine. Decremented on every successful
# fire; can_fire refuses once it hits zero. Initial value is the
# magazine size — spawners that want to start a unit with a
# pre-depleted magazine can override after construction.
var ammo_count: int = MAGAZINE_SIZE


# Bare construction defaults cool_rate to the per-class baseline so
# tests that build a RailgunWeapon without a unit still cool at the
# pre-parts rate. SpawnDirector overwrites this at spawn time.
func _init() -> void:
	cool_rate = COOL_PER_SEC
	wallplug_efficiency = WALLPLUG_EFFICIENCY
	target_coupling_default = TARGET_COUPLING_DEFAULT


## Class-level "what's the per-shot damage of an un-tiered railgun
## against a default-coupling target?" — used by the Hangar summary to
## report a tier-baseline number without instantiating a weapon. Reads
## the same physics constants the live fire() path does, so the panel
## stays honest if either KE or coupling is retuned.
static func base_damage_per_shot() -> float:
	return SLUG_MUZZLE_KE_J * TARGET_COUPLING_DEFAULT / J_PER_HP


## Per-instance damage including this weapon's tier multiplier and
## (eventually) the target's coupling override. Today the coupling
## lookup ignores the target and returns the per-class default; the
## hook is here so a future per-target armour value just slots in.
func damage_per_shot(target = null) -> float:
	var coupling: float = target_coupling_for(target)
	return SLUG_MUZZLE_KE_J * coupling / J_PER_HP * damage_mult


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
	if ammo_count <= 0:
		return false
	return attacker.energy >= ENERGY_PER_SHOT_J


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


## Apply only the shooter-side effects of a successful shot: recoil,
## energy drain, ammo decrement, cooldown latch. Returns a Dictionary
## describing the pending impact (target_dv, damage) the caller can
## apply immediately (synchronous fire) or hand to the slug renderer
## as an on_arrival callback (delayed fire). Returns null when the
## shot is refused for any reason — the caller should treat that as
## "this tick the weapon cools instead of firing".
##
## Splitting this from apply_impact lets the slug-render path defer
## the visible consequences (target push + HP damage + flash) to the
## moment the slug visually arrives, so a one-shot kill doesn't pop
## the target off-screen before the tracer has crossed the sky.
func prepare_shot(attacker, target, sim_delta: float):
	if sim_delta <= 0.0:
		return null
	if not can_fire(attacker):
		return null
	if not is_target_in_engagement_envelope(attacker, target):
		return null
	if not is_shot_safe_for_attacker(attacker, target):
		return null
	if target.mass <= 0.0:
		return null

	var to_target: Vector3 = target.orbit.r - attacker.orbit.r
	var dist_sq: float = to_target.length_squared()
	if dist_sq <= 0.0:
		return null
	var dir: Vector3 = to_target / sqrt(dist_sq)
	var attacker_dv: Vector3 = -dir * (SLUG_MOMENTUM_KG_KM_S / attacker.mass)
	# Pre-compute target push at fire-time geometry. Even when delayed,
	# the push direction is "from where the shot was launched" —
	# consistent with what the operator saw when they pulled the trigger.
	var target_dv: Vector3 = dir * (SLUG_MOMENTUM_KG_KM_S / target.mass)

	# Apply shooter recoil through orbit.maneuver(t=0) so the orbit's
	# derived elements (r_p, r_a, period, …) get recomputed atomically.
	# A successful safety check should mean the shooter's maneuver is
	# always valid; we still guard so a numerical edge case doesn't
	# leave the attacker in a partially-mutated state.
	if not attacker.orbit.maneuver(attacker_dv, 0.0):
		return null
	attacker.invalidate_impact_cache()

	attacker.energy = maxf(attacker.energy - ENERGY_PER_SHOT_J, 0.0)
	# Pop the slug out of the magazine and drop the shooter's wet
	# mass by one slug-mass. recompute_mass() pulls dry + propellant
	# + remaining ammo into one number, so the next shot's recoil
	# divides momentum by a slightly lower mass — the "magazine empties
	# means recoil grows" mechanic.
	ammo_count -= 1
	if attacker.has_method("recompute_mass"):
		attacker.recompute_mass()
	# Latch cooldown: ready falls to 0, overheated locks out can_fire
	# until ready climbs back to 1.0 via base Weapon.tick(). Mirrors
	# the laser's overheat semantics so the HUD bar reads consistently.
	ready_fraction = 0.0
	overheated = true
	return {
		"target_dv": target_dv,
		"damage": damage_per_shot(target),
	}


## Apply the target-side effects of a shot: momentum push and HP
## damage. Safe to call on a freed / dead target — both branches
## tolerate it (a kill from another weapon mid-flight just turns this
## into a no-op). `attacker` may be null when the shooter died
## between fire and arrival; in that case damage attribution is
## dropped but the impact still lands.
func apply_impact(attacker, target, pending: Dictionary) -> void:
	if target == null:
		return
	if target is Object and not is_instance_valid(target):
		return
	if not target.alive:
		return
	var target_dv: Vector3 = pending["target_dv"]
	var damage: float = pending["damage"]
	# Target's resulting orbit can be anything (including sub-orbital);
	# advance_time will catch a sub-surface trajectory next tick. If
	# the propagator rejects the maneuver outright, mark the target's
	# orbit dead so the renderer doesn't see NaN.
	if not target.orbit.maneuver(target_dv, 0.0):
		target.orbit_alive = false
	target.invalidate_impact_cache()
	target.take_damage(damage, attacker)


## Synchronous fire: shooter effects + immediate target effects.
## Used by the BeamRenderer-mode path (and by every existing test).
## The slug-render path calls prepare_shot directly and defers
## apply_impact to slug arrival.
func fire(attacker, target, sim_delta: float) -> bool:
	var pending = prepare_shot(attacker, target, sim_delta)
	if pending == null:
		return false
	apply_impact(attacker, target, pending)
	return true
