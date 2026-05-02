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

# Targeting modes. Stored as ints on Satellite.targeting_mode and read
# by pick_target() to rank in-envelope candidates. Definitions live on
# the weapon (the strategy that consumes them) rather than the
# satellite (which just carries the operator setting); HUD and
# EarthSystem reference them via LaserWeapon.* so toggling and
# rendering stay aligned with the weapon's semantics.
const TARGETING_MAX_DAMAGE: int = 0
const TARGETING_MAX_DANGER: int = 1

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

# Tier multipliers wired up by SpawnDirector when the unit is built.
# Default 1.0 keeps every existing call site (and every unit test that
# constructs a bare `LaserWeapon.new()`) on the original numbers.
# `damage_mult` scales DAMAGE_PER_SEC; `cool_mult` scales COOL_PER_SEC
# so radiator parts can speed up cooldown without touching heat
# accumulation. Heat accumulation is intrinsic to the emitter and
# stays unmultiplied — the same shot still loads the same thermal
# energy; the radiator only flushes it faster.
var damage_mult: float = 1.0
var cool_mult: float = 1.0


func display_name() -> String:
	return "Laser"


func damage_per_second() -> float:
	return DAMAGE_PER_SEC * damage_mult


func cost_per_second() -> float:
	return ENERGY_PER_SEC


func heat_rate() -> float:
	return HEAT_PER_SEC


func cool_rate() -> float:
	return COOL_PER_SEC * cool_mult


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


## Two-key lexicographic ranking. In MAX_DAMAGE mode the primary key is
## distance² (closest wins, so range-falloff damage is highest). In
## MAX_DANGER mode the primary key is predicted time-to-impact (soonest
## threat to Earth wins), with distance² as a tiebreaker so non-impacting
## candidates fall back to the same closest-target rule rather than
## leaving the weapon idle when nothing is currently inbound. Time-to-
## impact is computed only when MAX_DANGER is active — the propagation
## clone is cheap but not free, so MAX_DAMAGE keeps the original tight
## loop. Returns null when no candidate is in envelope this tick.
func pick_target(attacker, candidates: Array, sim_time: float):
	if attacker == null:
		return null
	var max_danger: bool = attacker.targeting_mode == TARGETING_MAX_DANGER
	var best = null
	var best_t := INF
	var best_d2 := INF
	for other in candidates:
		if other == attacker:
			continue
		if other.team == attacker.team:
			continue
		if not is_target_in_engagement_envelope(attacker, other):
			continue
		var d2: float = (other.orbit.r - attacker.orbit.r).length_squared()
		var t := INF
		if max_danger:
			# Absolute impact time, not relative — a smaller value still
			# means "more urgent" and ordering is identical, so we save
			# a per-satellite subtraction in the targeting hot loop.
			t = other.predict_impact_sim_time(sim_time)
		var better := false
		if max_danger:
			if t < best_t:
				better = true
			elif t == best_t and d2 < best_d2:
				better = true
		else:
			if d2 < best_d2:
				better = true
		if better:
			best_t = t
			best_d2 = d2
			best = other
	return best


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
	target.take_damage(damage_per_second() * dt * dmg_scale)
	attacker.energy = maxf(attacker.energy - ENERGY_PER_SEC * dt, 0.0)
	ready_fraction = clampf(ready_fraction - HEAT_PER_SEC * dt, 0.0, 1.0)
	if ready_fraction <= 0.0:
		overheated = true
	return true
