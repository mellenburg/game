class_name Weapon
extends RefCounted
## Base class for satellite weapons. Strategy interface so adding a new
## weapon type (kinetic, missile, ...) is one new file rather than a
## match cascade in Satellite. Pure RefCounted — no SceneTree dependency,
## so weapon math can be unit-tested headlessly.
##
## Energy lives on the attacker (Satellite) — multiple weapons share one
## reservoir. Cooldown is per-weapon so two lasers on the same hull
## recover independently.

# Sim-seconds remaining until this weapon is off cooldown. The HUD also
# reads this to drive the per-weapon recovery bar; concrete weapons that
# don't use cooldowns just leave it at 0.0.
var cooldown_remaining: float = 0.0


## Cost in `attacker.energy` fractions to fire one shot. Concrete
## weapons override; the default of 0 means a free-to-fire weapon
## (none of those exist yet, but the strategy interface allows it).
func cost_per_shot() -> float:
	return 0.0


## Maximum cooldown after a shot, in sim-seconds. The HUD divides
## cooldown_remaining by this to draw the recovery bar.
func cooldown_max() -> float:
	return 0.0


## 0.0 = just fired, 1.0 = ready. Returns 1.0 if the weapon doesn't
## have a cooldown concept, so the HUD bar renders as full/READY.
func cooldown_progress() -> float:
	var m := cooldown_max()
	if m <= 0.0:
		return 1.0
	return clampf(1.0 - cooldown_remaining / m, 0.0, 1.0)


## Advance per-weapon state by `sim_delta`. Default behaviour is just
## the cooldown countdown; concrete weapons may extend.
func tick(sim_delta: float) -> void:
	if sim_delta <= 0.0:
		return
	cooldown_remaining = maxf(cooldown_remaining - sim_delta, 0.0)


## Whether the weapon can fire right now given the attacker's state
## (cooldown clear, enough energy in the shared pool).
func can_fire(_attacker) -> bool:
	return false


## Whether `target` is a valid engagement candidate for `attacker` right
## now. Concrete weapons check team, range, and line-of-sight here.
func is_target_in_engagement_envelope(_attacker, _target) -> bool:
	return false


## Apply the weapon's effect to `target` if eligible. Returns true if a
## shot was actually taken (caller can use that to drive feedback).
func fire(_attacker, _target) -> bool:
	return false
