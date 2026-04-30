class_name LaserWeapon
extends "res://scripts/weapons/weapon.gd"
## Energy weapon. Cooldown is per-weapon; energy is drawn from the
## attacker's shared reservoir so two lasers on the same hull starve
## each other rather than firing in lockstep. LOS-only: any unblocked
## enemy is in envelope, no max range.

const LosCheck = preload("res://scripts/los_check.gd")

const DAMAGE: float = 25.0
# Fraction of the attacker's full reservoir consumed per shot. Halved
# from 0.5 — the laser is now affordable enough that a satellite can
# fire several shots in succession before energy gates further fire.
const ENERGY_PER_SHOT: float = 0.25
# Sim-seconds the weapon is locked out for after firing.
const COOLDOWN_SIM_SEC: float = 1800.0


func cost_per_shot() -> float:
	return ENERGY_PER_SHOT


func cooldown_max() -> float:
	return COOLDOWN_SIM_SEC


func can_fire(attacker) -> bool:
	if attacker == null:
		return false
	return cooldown_remaining <= 0.0 and attacker.energy >= ENERGY_PER_SHOT


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


func fire(attacker, target) -> bool:
	if not can_fire(attacker):
		return false
	if not is_target_in_engagement_envelope(attacker, target):
		return false
	target.take_damage(DAMAGE)
	attacker.energy = maxf(attacker.energy - ENERGY_PER_SHOT, 0.0)
	cooldown_remaining = COOLDOWN_SIM_SEC
	return true
