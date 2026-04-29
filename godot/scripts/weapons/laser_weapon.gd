class_name LaserWeapon
extends "res://scripts/weapons/weapon.gd"
## Energy weapon. Charges at a fixed rate of simulated time so that
## holding speed-up genuinely speeds the weapon up (per the original
## design intent — "1% per game tick"). LOS-only: any unblocked enemy
## is in envelope, no max range.

const LosCheck = preload("res://scripts/los_check.gd")

const DAMAGE: float = 25.0
# Fraction of full charge gained per simulated second. 0.00007 → full
# charge takes ~14_286 sim-seconds (~28 real seconds at the default
# time_factor=500). Time-factor scales sim_delta upstream, so holding
# speed-up shortens the charge the same way it shortens orbital motion.
const ENERGY_RATE_PER_SIM_SEC: float = 0.00007
# Fraction of full charge consumed per shot. Half a tank means a freshly
# off-cooldown weapon that's been sitting at full charge can in principle
# fire twice — but the cooldown below is the dominant gate during play.
const ENERGY_PER_SHOT: float = 0.5
# Seconds of simulated time the weapon is locked out after firing. Like
# the charge rate, this is in sim-seconds — at time_factor=500 a 1800 s
# cooldown corresponds to 3.6 real seconds.
const COOLDOWN_SIM_SEC: float = 1800.0


func can_fire() -> bool:
	return energy >= FULL_ENERGY and cooldown_remaining <= 0.0


func charge(sim_delta: float) -> void:
	if sim_delta <= 0.0:
		return
	energy = clampf(energy + ENERGY_RATE_PER_SIM_SEC * sim_delta, 0.0, FULL_ENERGY)
	cooldown_remaining = maxf(cooldown_remaining - sim_delta, 0.0)


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
	energy = maxf(energy - ENERGY_PER_SHOT, 0.0)
	cooldown_remaining = COOLDOWN_SIM_SEC
	return true
