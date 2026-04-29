class_name LaserWeapon
extends "res://scripts/weapons/weapon.gd"
## Energy weapon. Charges at a fixed rate of simulated time so that
## holding speed-up genuinely speeds the weapon up (per the original
## design intent — "1% per game tick"). LOS-only: any unblocked enemy
## is in envelope, no max range.

const LosCheck = preload("res://scripts/los_check.gd")

const DAMAGE: float = 25.0
# Fraction of full charge gained per simulated second. With time_factor
# at the default ~500, this fully charges in ~0.2 real seconds; at
# real-time (time_factor=1) it takes 100 s, matching the "100 ticks at
# 1%" framing.
const ENERGY_RATE_PER_SIM_SEC: float = 0.01


func charge(sim_delta: float) -> void:
	if sim_delta <= 0.0:
		return
	energy = clampf(energy + ENERGY_RATE_PER_SIM_SEC * sim_delta, 0.0, FULL_ENERGY)


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
	if not can_fire():
		return false
	if not is_target_in_engagement_envelope(attacker, target):
		return false
	target.take_damage(DAMAGE)
	energy = 0.0
	return true
