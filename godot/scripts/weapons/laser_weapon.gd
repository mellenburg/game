class_name LaserWeapon
extends "res://scripts/weapons/weapon.gd"
## Continuous-fire energy beam. Damage and energy drain are per
## simulated second; firing heats the emitter (ready_fraction drops),
## idling cools it. Heat saturates 4x faster than it dissipates, so a
## sustained beam earns a long lockout. Range-limited: damage scales
## linearly from full at zero distance to zero at MAX_RANGE_KM, and the
## engagement envelope rejects targets beyond the attacker's
## engagement_range_km cap (so operators can save energy by holding
## fire until enemies are inside an optimal-damage band).

const LosCheck = preload("res://scripts/los_check.gd")

# Damage applied to target.hp per sim-second of beam contact at zero
# range. Effective damage is scaled by range_factor(distance).
const DAMAGE_PER_SEC: float = 5.0
# Fraction of attacker.energy drained per sim-second of fire. The
# drain is constant — energy cost doesn't scale with damage, so
# firing at long range really does waste the reservoir.
const ENERGY_PER_SEC: float = 0.005
# Fraction of ready_fraction consumed per sim-second of fire. 0.025
# means 40 sim-sec of continuous fire takes the weapon from full
# ready to overheated.
const HEAT_PER_SEC: float = 0.025
# Recovery per sim-second of idle. 4x slower than heat by design —
# 160 sim-sec to fully cool from overheated.
const COOL_PER_SEC: float = HEAT_PER_SEC / 4.0
# Distance at which damage drops to zero. Linear falloff between 0 km
# (full damage) and MAX_RANGE_KM (no damage). 40 000 km ≈ 6.3 Earth
# radii — wide enough that two LEO satellites on opposite sides of
# Earth (~14 000 km, ~0.65× damage) still hit usefully, while keeping
# a clear penalty against the high meteorite spawn shell (40–70 000
# km altitude). Doubles as the hard cap on the operator's
# engagement_range_km, so the on-plane fire-control circle can never
# render larger than the physics-level kill envelope.
const MAX_RANGE_KM: float = 40000.0
# Floor on a satellite's user-set engagement range. Pulling it below
# this would let an operator effectively disable fire control.
const MIN_ENGAGEMENT_RANGE_KM: float = 500.0


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


## Linear damage scaling: 1.0 at zero distance, 0.0 at MAX_RANGE_KM,
## clamped outside that band. Pure function — exposed so HUD / tests
## can predict expected damage without re-deriving the curve.
static func range_factor(distance_km: float) -> float:
	if distance_km <= 0.0:
		return 1.0
	if distance_km >= MAX_RANGE_KM:
		return 0.0
	return 1.0 - distance_km / MAX_RANGE_KM


func is_target_in_engagement_envelope(attacker, target) -> bool:
	if attacker == null or target == null:
		return false
	if not attacker.alive or not target.alive:
		return false
	if attacker.team == target.team:
		return false
	if not attacker.orbit_alive or not target.orbit_alive:
		return false
	# Physics ceiling always applies — past MAX_RANGE_KM the falloff
	# already drives damage to zero. The operator's engagement_range_km
	# only narrows that envelope while fire control is active; turning
	# fire control off restores default behaviour (fire at any LOS
	# enemy out to MAX_RANGE_KM) without forcing the operator to widen
	# the slider back up first.
	var distance: float = (target.orbit.r - attacker.orbit.r).length()
	var cap: float = MAX_RANGE_KM
	if attacker.fire_control_active:
		cap = minf(cap, attacker.engagement_range_km)
	if distance >= cap:
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
	var distance: float = (target.orbit.r - attacker.orbit.r).length()
	var dmg_scale: float = range_factor(distance)
	target.take_damage(DAMAGE_PER_SEC * dt * dmg_scale)
	attacker.energy = maxf(attacker.energy - ENERGY_PER_SEC * dt, 0.0)
	ready_fraction = clampf(ready_fraction - HEAT_PER_SEC * dt, 0.0, 1.0)
	if ready_fraction <= 0.0:
		overheated = true
	return true
