class_name Weapon
extends RefCounted
## Base class for satellite weapons. Strategy interface so adding a new
## weapon type (kinetic, missile, ...) is one new file rather than a
## match cascade in Satellite. Pure RefCounted — no SceneTree dependency,
## so weapon math can be unit-tested headlessly.
##
## Energy lives on the attacker (Satellite) — multiple weapons share one
## reservoir. Heat is per-weapon: each weapon owns a `ready_fraction`
## that drops while firing and recovers while idle, so two lasers on the
## same hull manage their thermal budgets independently.

# 1.0 = fully ready, 0.0 = overheated. Drops while firing at the
# weapon's heat_rate, climbs while cooling at cool_rate. The HUD reads
# this directly to draw the per-weapon recovery bar.
var ready_fraction: float = 1.0
# Latched when ready_fraction reaches 0; cleared only when it returns
# to 1.0. Locks the weapon out of fire() for the entire cool window so
# brief ready upticks don't let the operator dribble out shots.
var overheated: bool = false


## Cost in `attacker.energy` fractions per simulated second of fire.
## Concrete weapons override; default 0 means a free-to-fire weapon
## (none of those exist yet, but the strategy interface allows it).
func cost_per_second() -> float:
	return 0.0


## Heat applied to ready_fraction per sim-second of fire. Concrete
## weapons override.
func heat_rate() -> float:
	return 0.0


## Recovery applied to ready_fraction per sim-second of cooling.
## By convention 4x slower than heat_rate for energy weapons.
func cool_rate() -> float:
	return 0.0


## 0.0 = just overheated, 1.0 = ready. Mirror of ready_fraction so
## HUD code reads a stable progress accessor.
func ready_progress() -> float:
	return ready_fraction


## Cool the weapon by cool_rate * sim_delta. Called from EarthSystem
## once per physics tick, but ONLY when the weapon did not fire this
## tick — firing already mutates ready_fraction itself.
func tick(sim_delta: float) -> void:
	if sim_delta <= 0.0:
		return
	ready_fraction = clampf(ready_fraction + cool_rate() * sim_delta, 0.0, 1.0)
	if overheated and ready_fraction >= 1.0:
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
