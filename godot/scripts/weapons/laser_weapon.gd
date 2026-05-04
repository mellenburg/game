class_name LaserWeapon
extends "res://scripts/weapons/weapon.gd"
## Continuous-fire energy beam. Damage and energy drain are per
## simulated second; firing dumps waste heat (heat_fraction × pool draw)
## into the weapon's heat_j until heat_capacity_j is reached, at which
## point the overheat latch trips and the weapon refuses to fire until
## the cooling system bleeds it back to zero. Range-limited via
## diffraction: a beam from an aperture D at wavelength λ stays
## collimated out to the Rayleigh range L₀ = D²/λ (full intensity), then
## spreads as a ~constant solid angle so on-target intensity falls as
## (L₀ / L)² past that boundary. MAX_RANGE_KM caps engagement at the
## ~1% intensity radius (10·L₀); the engagement envelope additionally
## rejects targets beyond the attacker's engagement_range_km cap so
## operators can save energy by holding fire until enemies are inside
## an optimal-damage band.

const LosCheck = preload("res://scripts/los_check.gd")

# Targeting modes. Stored as ints on Satellite.targeting_mode and read
# by pick_target() to rank in-envelope candidates. Definitions live on
# the weapon (the strategy that consumes them) rather than the
# satellite (which just carries the operator setting); HUD and
# EarthSystem reference them via LaserWeapon.* so toggling and
# rendering stay aligned with the weapon's semantics.
const TARGETING_MAX_DAMAGE: int = 0
const TARGETING_MAX_DANGER: int = 1

# Beam radiated power (watts) at the emitter aperture. 100 MW is in
# the "advanced spacecraft" band — three orders above fielded DEWs
# (LaWS / HELIOS at 30-150 kW), but consistent with what a fission-
# powered orbital platform could plausibly support. This is the
# energy-per-sim-second deposited at zero range; per-target damage
# falls out of (radiated × coupling / Weapon.J_PER_HP).
const RADIATED_POWER_W: float = 1.0e8
# Pool→radiated conversion. Real fiber lasers run ~30-40% wall-plug
# efficient; the rest is heat dumped through the cooling stack. 30%
# is the conservative end and means the laser draws ~333 MW from the
# bus while firing — sized so a 1 GW reactor can sustain ~3 lasers
# concurrent before draining the pool.
const WALLPLUG_EFFICIENCY: float = 0.3
# Default beam-on-armour absorption: ~40% of the radiated beam
# becomes absorbed damage; the rest reflects (most for shiny metal,
# less for blackened armour) or scatters off the tracking error
# cone. Per-target overrides land here later via target_coupling_for().
const TARGET_COUPLING_DEFAULT: float = 0.4
# Joules drawn from the shared pool per simulated second of fire.
# Pre-derived so the hot fire() path doesn't redo the divide.
const POOL_DRAIN_W: float = RADIATED_POWER_W / WALLPLUG_EFFICIENCY
# Fraction of pool draw that becomes waste heat in the emitter — the
# inverse of wall-plug efficiency by definition. Surfaced as its own
# constant (rather than recomputed on the fly) so a future tweak to
# the heat model can override one without disturbing the other.
const HEAT_FRACTION: float = 1.0 - WALLPLUG_EFFICIENCY
# Sim-seconds of sustained fire before heat reaches capacity. 40 sec
# matches the legacy ready_fraction model's overheat budget so
# existing balance assumptions hold across the refactor.
const HEAT_BUDGET_SEC: float = 40.0
# Heat capacity in joules: how much waste heat the emitter can hold
# before the overheat latch trips. Sized so HEAT_BUDGET_SEC of
# continuous fire fully fills it.
const HEAT_CAPACITY_J: float = POOL_DRAIN_W * HEAT_FRACTION * HEAT_BUDGET_SEC
# Emitter aperture diameter (m). Beam divergence — and therefore
# range — is set by D and λ together via the Rayleigh range L₀ = D²/λ.
# 1.4 m is the design "sweet spot" (Capital lasers go up to ~3 m for
# spinal mounts; PD/light lasers down to ~0.5 m). Doubling D
# quadruples L₀ — and quadruples every range band the weapon engages
# in — so this is the single biggest balance lever on the laser.
const APERTURE_DIAMETER_M: float = 1.4
# Beam wavelength (m). 1 μm is near-IR, the band where high-power
# fiber lasers actually live. Range scales as 1/λ — UV (0.25 μm) would
# 4× every range band, CO₂ (10 μm) would cut them tenfold. Held at the
# baseline so the calibration table in the design doc applies directly.
const WAVELENGTH_M: float = 1.0e-6
# Rayleigh range (km): the near-field/far-field boundary. Inside this
# distance the beam is effectively collimated and dumps full intensity
# on the target; past it the spot grows as (L/L₀) and on-target
# intensity falls as (L₀/L)². Pre-derived so the hot fire() path
# doesn't redo the divide every tick.
const RAYLEIGH_RANGE_KM: float = (
	APERTURE_DIAMETER_M * APERTURE_DIAMETER_M / WAVELENGTH_M / 1000.0
)
# Distance at which on-target intensity drops to ~1% (the
# "harassment-irrelevant" threshold from the design table). Hard cap
# on engagement; targets past this radius are rejected by the envelope
# check and the on-plane fire-control circle can never render larger
# than this physics-level kill envelope. With D=1.4 m and λ=1 μm this
# lands at ~19 600 km — comfortably outside opposite-side-of-Earth
# LEO (~14 000 km) but well inside the high meteorite spawn shell
# (40–70 000 km altitude), which is the band where missiles and
# kinetics are supposed to take over.
const MAX_RANGE_KM: float = 10.0 * RAYLEIGH_RANGE_KM
# Floor on a satellite's user-set engagement range. Pulling it below
# this would let an operator effectively disable fire control.
const MIN_ENGAGEMENT_RANGE_KM: float = 500.0

# Damage tier multiplier wired up by SpawnDirector when the unit is
# built. Default 1.0 keeps every existing call site (and every unit
# test that constructs a bare `LaserWeapon.new()`) on the original
# numbers; SpawnDirector overrides it from the weapon part's tier.
# Heat capacity / fraction stay tier-independent — the same shot
# loads the same thermal energy; the cooling system (which feeds
# Satellite.cooling_power_w) only flushes it faster.
var damage_mult: float = 1.0


func _init() -> void:
	heat_capacity_j = HEAT_CAPACITY_J
	heat_fraction = HEAT_FRACTION
	wallplug_efficiency = WALLPLUG_EFFICIENCY
	target_coupling_default = TARGET_COUPLING_DEFAULT


func display_name() -> String:
	return "Laser"


## Class-level "what's the per-second damage of an un-tiered laser
## against a default-coupling target at zero range?" — used by the
## Hangar summary to report a tier-baseline DPS without instantiating
## a weapon. Reads the same physics constants the live fire() path
## does, so the panel stays honest if power / coupling is retuned.
static func base_damage_per_second_at_zero_range() -> float:
	return RADIATED_POWER_W * TARGET_COUPLING_DEFAULT / J_PER_HP


## Per-instance DPS at zero range, including this weapon's tier
## multiplier. Range falloff is multiplied in by the caller.
func damage_per_second(target = null) -> float:
	var coupling: float = target_coupling_for(target)
	return RADIATED_POWER_W * coupling / J_PER_HP * damage_mult


func pool_draw_w() -> float:
	return POOL_DRAIN_W


func can_fire(attacker) -> bool:
	if attacker == null:
		return false
	if overheated:
		return false
	return attacker.energy > 0.0


## Diffraction-limited damage scaling. Inside the Rayleigh range the
## beam is collimated and intensity is full (1.0); past it the spot
## grows linearly and intensity falls as (L₀ / L)². Hard-clamped to 0.0
## past MAX_RANGE_KM so the engagement envelope and the falloff curve
## agree on the cutoff. Pure function — exposed so HUD / tests can
## predict expected damage without re-deriving the curve.
static func range_factor(distance_km: float) -> float:
	if distance_km <= RAYLEIGH_RANGE_KM:
		return 1.0
	if distance_km >= MAX_RANGE_KM:
		return 0.0
	var ratio: float = RAYLEIGH_RANGE_KM / distance_km
	return ratio * ratio


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
	var max_by_energy: float = attacker.energy / POOL_DRAIN_W
	var heat_per_sec: float = POOL_DRAIN_W * heat_fraction
	var max_by_heat: float = INF
	if heat_per_sec > 0.0:
		max_by_heat = (heat_capacity_j - heat_j) / heat_per_sec
	var dt: float = minf(sim_delta, minf(max_by_energy, max_by_heat))
	if dt <= 0.0:
		return false
	var distance: float = (target.orbit.r - attacker.orbit.r).length()
	var dmg_scale: float = range_factor(distance)
	target.take_damage(damage_per_second(target) * dt * dmg_scale, attacker)
	attacker.energy = maxf(attacker.energy - POOL_DRAIN_W * dt, 0.0)
	heat_j = clampf(heat_j + heat_per_sec * dt, 0.0, heat_capacity_j)
	if heat_j >= heat_capacity_j:
		overheated = true
	return true
