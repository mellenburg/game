class_name Weapon
extends RefCounted
## Base class for satellite weapons. Strategy interface so adding a new
## weapon type (kinetic, missile, ...) is one new file rather than a
## match cascade in Satellite. Pure RefCounted — no SceneTree dependency,
## so weapon math can be unit-tested headlessly.

const FULL_ENERGY: float = 1.0

var energy: float = 0.0
# Sim-seconds the weapon is locked out for after firing. Lives on the
# base so consumers (HUD, future targeting AI) can read it without
# downcasting; concrete weapons that don't use cooldowns just leave
# it at 0.0.
var cooldown_remaining: float = 0.0


## Return true once the weapon has accumulated enough energy to fire.
func can_fire() -> bool:
	return energy >= FULL_ENERGY


## Advance internal energy state by sim_delta simulated seconds. Time
## factor scales sim_delta upstream, so holding speed-up shortens the
## charge time the same way it shortens any other in-sim duration.
func charge(_sim_delta: float) -> void:
	pass


## Whether `target` is a valid engagement candidate for `attacker` right
## now. Concrete weapons check team, range, and line-of-sight here.
func is_target_in_engagement_envelope(_attacker, _target) -> bool:
	return false


## Apply the weapon's effect to `target` if eligible. Returns true if a
## shot was actually taken (caller can use that to drive feedback later).
func fire(_attacker, _target) -> bool:
	return false
