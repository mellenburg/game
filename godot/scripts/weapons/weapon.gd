class_name Weapon
extends RefCounted
## Base class for satellite weapons. Strategy interface so adding a new
## weapon type (kinetic, missile, ...) is one new file rather than a
## match cascade in Satellite. Pure RefCounted — no SceneTree dependency,
## so weapon math can be unit-tested headlessly.
##
## Energy lives on the attacker (Satellite) — multiple weapons share one
## reservoir. Heat is per-weapon, in joules: firing dumps a fraction
## (heat_fraction) of the pool draw into the weapon's heat_j; the
## attacker's cooling system removes joules per second, split evenly
## across weapons whose heat_j > 0. A weapon whose heat hits its
## heat_capacity_j latches `overheated` and refuses to fire until heat
## drains all the way back to zero.

# Global default fraction of pool draw that becomes waste heat. Real
# fiber lasers and rail launchers run ~30% wall-plug efficient → ~70%
# of input energy is heat. Single configurable knob so the operator can
# rebalance every weapon's heat output at once; per-weapon overrides
# (set via `heat_fraction` in the subclass _init) take precedence.
const HEAT_FRACTION_DEFAULT: float = 0.7

# Current waste-heat load (joules) and capacity (joules). Heat climbs
# while firing, drains while the cooling system has spare capacity.
# Hitting heat_capacity_j latches overheated; the latch clears only
# when heat_j drops back to 0.
var heat_j: float = 0.0
var heat_capacity_j: float = 0.0
# Latched at heat_capacity_j; cleared when heat_j returns to 0. Locks
# the weapon out of fire() for the entire dump window so brief cooling
# bursts don't let the operator dribble out shots before the rad stack
# has fully cleared.
var overheated: bool = false
# Fraction of pool draw that becomes heat. Subclasses overwrite in
# _init to match their own efficiency (typically 1 - wallplug_efficiency).
var heat_fraction: float = HEAT_FRACTION_DEFAULT
# Two-stage energy → damage conversion every weapon shares:
#   pool_drained_J × wallplug_efficiency → output energy delivered
#     toward the target (slug muzzle KE for kinetic, radiated beam
#     energy for laser).
#   delivered_J × target_coupling_for(target) → energy actually
#     absorbed as damage; the rest fragments / reflects / scatters.
# Concrete weapons set their defaults in _init. target_coupling_for()
# is a virtual hook so future per-target overrides (e.g. armoured
# targets resisting kinetics differently than lasers) drop in without
# touching the fire() math.
var wallplug_efficiency: float = 1.0
var target_coupling_default: float = 1.0


## Effective coupling for the given target. Default returns the
## weapon's own per-class default; subclasses can override.
func target_coupling_for(_target) -> float:
	return target_coupling_default


## Pool draw (joules per simulated second) at full continuous fire.
## Concrete continuous-fire weapons override. Impulse weapons leave
## this at 0 and report `energy_per_shot_j()` instead.
func pool_draw_w() -> float:
	return 0.0


# Global damage-scaling constants. Lives on the Weapon base class
# (rather than Satellite) because every weapon needs to convert
# delivered joules to HP, and putting these here avoids the circular
# preload that satellite.gd ↔ weapon-subclass would otherwise create
# (Satellite preloads each concrete weapon to construct its default
# loadout in _init).
#
# 5 MJ/HP is a balance pick: a 1 GJ railgun slug coupled at 50% drops
# 100 HP per shot — one-shotting a default 100-HP target. Re-tuning
# weapon power / coupling shifts the curve; re-tuning MJ_PER_HP shifts
# the whole game's TTK. See the design discussion in CLAUDE.md.
const MJ_PER_HP: float = 5.0
const J_PER_HP: float = MJ_PER_HP * 1.0e6


## True iff the weapon has accumulated heat that the cooling system
## should bleed off this tick. CombatController uses this to count
## active demanders and split the unit's cooling power evenly across
## them — a sole demander gets 100% of the cooling, two share 50/50.
func demands_cooling() -> bool:
	return heat_j > 0.0


## 0.0 = just overheated, 1.0 = fully cool. Mirror of heat_j vs.
## heat_capacity_j so HUD code reads a stable progress accessor that
## stays valid even if a subclass changes its capacity.
func ready_progress() -> float:
	if heat_capacity_j <= 0.0:
		return 1.0
	return clampf(1.0 - heat_j / heat_capacity_j, 0.0, 1.0)


## Apply `cooling_power_w` watts of heat removal for `sim_delta` sim-
## seconds. Called from CombatController once per physics tick after
## per-tick cooling allocation across the unit's demanding weapons.
## Clears the overheated latch when heat reaches zero.
func cool(cooling_power_w: float, sim_delta: float) -> void:
	if sim_delta <= 0.0 or cooling_power_w <= 0.0:
		return
	heat_j = maxf(heat_j - cooling_power_w * sim_delta, 0.0)
	if overheated and heat_j <= 0.0:
		overheated = false


## Whether the weapon can fire right now given the attacker's state
## (overheat lock cleared, some energy in the shared pool).
func can_fire(_attacker) -> bool:
	return false


## Whether `target` is a valid engagement candidate for `attacker` right
## now. Concrete weapons check team, range, and line-of-sight here.
func is_target_in_engagement_envelope(_attacker, _target) -> bool:
	return false


## Apply the weapon's effect to `target` over `sim_delta` simulated
## seconds. Returns true if any fire actually took place this tick
## (caller can use that to drive feedback and to skip cooling).
func fire(_attacker, _target, _sim_delta: float) -> bool:
	return false


## Pick which of the prefiltered `candidates` this weapon should fire at
## this tick. Concrete weapons override — the laser ranks by attacker
## targeting_mode (closest / soonest impact), the railgun picks
## randomly from in-envelope LOS candidates. Returning null means
## "nothing to fire at"; the caller treats that as a cool tick.
##
## `candidates` is the controller's universal alive-and-orbit-alive
## list (no team filter). Weapons that need other invariants must
## verify them via their own is_target_in_engagement_envelope().
func pick_target(_attacker, _candidates: Array, _sim_time: float):
	return null


## Short label used by the HUD's weapon-row text (e.g. "Laser 1  85%",
## "Railgun  COOLDOWN 50%"). Concrete weapons override.
func display_name() -> String:
	return "Weapon"
