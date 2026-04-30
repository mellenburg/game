class_name LaserWeapon
extends "res://scripts/weapons/weapon.gd"
## Continuous-fire energy beam. Damage and energy drain are per
## simulated second; firing heats the emitter (ready_fraction drops),
## idling cools it. Heat saturates 4x faster than it dissipates, so a
## sustained beam earns a long lockout. LOS-only: any unblocked enemy
## is in envelope, no max range.

const LosCheck = preload("res://scripts/los_check.gd")

# Damage applied to target.hp per sim-second of beam contact.
const DAMAGE_PER_SEC: float = 5.0
# Fraction of attacker.energy drained per sim-second of fire.
const ENERGY_PER_SEC: float = 0.005
# Fraction of ready_fraction consumed per sim-second of fire. 0.025
# means 40 sim-sec of continuous fire takes the weapon from full
# ready to overheated.
const HEAT_PER_SEC: float = 0.025
# Recovery per sim-second of idle. 4x slower than heat by design —
# 160 sim-sec to fully cool from overheated.
const COOL_PER_SEC: float = HEAT_PER_SEC / 4.0


func damage_per_second() -> float:
	return DAMAGE_PER_SEC


func cost_per_second() -> float:
	return ENERGY_PER_SEC


func heat_rate() -> float:
	return HEAT_PER_SEC


func cool_rate() -> float:
	return COOL_PER_SEC


func can_fire(attacker) -> bool:
	if attacker == null:
		return false
	if overheated:
		return false
	return attacker.energy > 0.0


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


func fire(attacker, target, sim_delta: float) -> bool:
	if sim_delta <= 0.0:
		return false
	if not can_fire(attacker):
		return false
	if not is_target_in_engagement_envelope(attacker, target):
		return false
	# Cap effective fire duration by whichever runs out first this
	# tick: requested sim_delta, remaining energy, or remaining heat
	# headroom. Whatever slack is left over is just lost — at our
	# physics-tick granularity the rounding is negligible.
	var max_by_energy: float = attacker.energy / ENERGY_PER_SEC
	var max_by_heat: float = ready_fraction / HEAT_PER_SEC
	var dt: float = minf(sim_delta, minf(max_by_energy, max_by_heat))
	if dt <= 0.0:
		return false
	target.take_damage(DAMAGE_PER_SEC * dt)
	attacker.energy = maxf(attacker.energy - ENERGY_PER_SEC * dt, 0.0)
	ready_fraction = clampf(ready_fraction - HEAT_PER_SEC * dt, 0.0, 1.0)
	if ready_fraction <= 0.0:
		overheated = true
	return true
