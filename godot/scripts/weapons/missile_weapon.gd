class_name MissileWeapon
extends "res://scripts/weapons/weapon.gd"
## Guided-intercept missile weapon. Each shot spawns a Missile entity
## that flies a Lambert-solved Keplerian intercept arc to the target
## and detonates inside its proximity-fuze blast radius. Missiles are
## slow (TOFs of minutes), expensive (per-shot propellant + dv
## budget), and have a fixed magazine — distinct gameplay shape from
## the laser (continuous-fire) and railgun (impulse with travel time).
##
## See `docs/missiles.md` for the cross-cutting reference — physics
## calibration (100 MT yield, lethal radius derivation), end-to-end
## fire sequence, reservation lifecycle, design tradeoffs (manual fire,
## auto-target picking, deferred damage), and refactor playbook. Touch
## that doc whenever you retune the constants in this file so the
## physics rationale stays in sync with the code.
##
## The actual orbital-mechanics solve runs in pick_target via
## LambertSolver.find_best_intercept. The result is cached per
## (target_iid → expiry) so subsequent ticks reuse it; CACHE_TTL_SEC
## bounds the staleness. is_target_in_engagement_envelope stays cheap
## (no Lambert call) so the base-class signature isn't violated.
##
## Fire path differs from the other weapons: there is no synchronous
## fire() — CombatController calls prepare_shot directly and hands the
## pending Dict to MissileSpawner, which owns the in-flight missile
## entity and its termination lifecycle. This mirrors the railgun-slug
## delayed-effect pattern but the slug renderer's "damage already
## applied" optimisation doesn't apply: the missile decides whether to
## detonate based on real geometry at arrival time.

const MassCenterOrbit = preload("res://scripts/mass_center_orbit.gd")
const LambertSolver = preload("res://scripts/lambert_solver.gd")
const Propulsion = preload("res://scripts/propulsion.gd")

# Magazine: total missiles the launcher ships with. Smaller than the
# railgun magazine (1000) by two orders of magnitude — missiles are
# strategic shots, not sustained fire. Tier multipliers scale damage,
# not magazine.
const MAGAZINE_SIZE: int = 8

# Per-missile mass budget. 100 kg dry structure + 150 kg propellant ⇒
# ~4 km/s dv via Tsiolkovsky at MISSILE_ISP_S=450. Enough to reach
# most LEO-band targets within the TOF window; not enough to escape
# Earth or chase a high-energy target.
const MISSILE_DRY_MASS_KG: float = 100.0
const PROPELLANT_PER_MISSILE_KG: float = 150.0
# Vacuum-optimised storable bipropellant Isp. Slightly conservative
# vs MMH/NTO (~330s) or LOX/methane (~370s) because missiles run cold
# from storage rather than tuned for max performance.
const MISSILE_ISP_S: float = 450.0

# Proximity-fuze trigger radius — also the warhead's lethal envelope.
# Calibrated for a 100 MT thermonuclear yield (4.184 × 10^17 J)
# detonated in vacuum:
#
#   * ~75% of yield emits as soft X-rays at the speed of light. No
#     atmospheric shock wave in space, so the X-ray pulse is the
#     dominant kill mechanism at range.
#   * Inverse-square fluence at radius R:  F = E_x / (4π R²).
#   * Damage threshold for typical (unhardened) satellite skin —
#     vaporises solar panels, sensors, exposed structure: ≈ 1 kJ/cm²
#     = 10^7 J/m². Hardened military comsats survive ~10× higher
#     fluence; light commercial sensor platforms die at ~10× lower.
#   * Solving for the unhardened-target lethal radius:
#         R = sqrt(0.75 · 4.184e17 / (4π · 10^7)) ≈ 50 km.
#
# Set to 50 km accordingly. The proximity fuze trigger equals the
# damage radius so a missile that enters the X-ray-lethal envelope
# detonates and applies full damage; outside, the falloff branch in
# Missile.gd applies scaled damage out to 2× this radius (≈100 km
# kill-zone for damaged-but-alive outcomes). This calibration is
# order-of-magnitude; nuclear-effects modelling is approximate by
# design. Tune if balance changes — and document the physics if so.
const BLAST_RADIUS_KM: float = 50.0

# Time-of-flight search bounds for the Lambert intercept.
const MIN_TOF_SEC: float = 30.0
const MAX_TOF_SEC: float = 1800.0  # 30 min

# Bus draw at launch (release pulse, FCS init, IMU spin-up). Drained
# off the attacker's energy pool the same way the railgun draws.
const ENERGY_PER_LAUNCH_J: float = 1.0e10  # 10 GJ
# Coupling: 100% — the proximity-fuze warhead deposits its full yield
# regardless of target armour. Phase-2 hook for per-target overrides
# via target_coupling_for().
const TARGET_COUPLING_DEFAULT: float = 1.0
# Wall-plug efficiency for missile launches is moot (the energy is
# the FCS pulse, not the warhead yield), so the heat-bookkeeping
# constant is decoupled from the kinetic budget here.
const WALLPLUG_EFFICIENCY: float = 1.0
# Heat dumped per launch — sized so a missile launcher dumps the
# launcher's whole heat capacity in one shot. The overheat latch then
# holds until cooling clears it, throttling fire cadence (matches the
# railgun's one-shot-then-cool design).
const HEAT_CAPACITY_J: float = ENERGY_PER_LAUNCH_J * 0.3
const HEAT_FRACTION: float = 0.3
# Per-shot damage (HP, not joules — the warhead's yield is a fixed
# property of the missile, not a derived energy quantity). For the
# 100 MT yield calibrated above, the lethal-radius X-ray fluence
# vapourises every exposed surface; HP-wise this should one-shot
# any reasonable target inside the blast radius with margin for
# future hardened targets. 500 HP one-shots a default 100-HP
# satellite at 5× overkill — a tier-3 (~3× hp_mult) heavy still
# dies, a hypothetical future 1000-HP capital ship survives with
# half hp. Out-of-radius falloff in Missile.gd scales this by
# (blast_radius / distance) so a near miss deals proportional
# damage out to 2× the radius before terminating as a miss.
const DAMAGE_HP: float = 500.0

# How long a cached Lambert solution stays valid. Five sim-seconds is
# a balance between staleness (attacker may have drifted, target may
# have shifted) and avoiding a Lambert solve on every physics tick.
const CACHE_TTL_SEC: float = 5.0

# Cheap reachability heuristic: distance below which we always try
# Lambert. Above this, the cheap distance gate rejects without solving.
# Derived from "missile can travel at most dv_budget * MAX_TOF" plus a
# generous slack factor; recomputed lazily.
static func _max_reach_km() -> float:
	var dv_kms: float = dv_budget_per_missile_kms()
	# Slack ×3: the missile's ballistic arc covers more ground than a
	# straight-line dv*tof estimate suggests, especially when the
	# transfer ellipse cooperates with the target's own orbital motion.
	return dv_kms * MAX_TOF_SEC * 3.0


var ammo_count: int = MAGAZINE_SIZE
var damage_mult: float = 1.0
# Cache: target_iid (int) → {expires_at: float, reachable: bool,
#                            dv: Vector3, dv_mag: float,
#                            tof: float, v1: Vector3}
var _intercept_cache: Dictionary = {}


func _init() -> void:
	heat_capacity_j = HEAT_CAPACITY_J
	heat_fraction = HEAT_FRACTION
	wallplug_efficiency = WALLPLUG_EFFICIENCY
	target_coupling_default = TARGET_COUPLING_DEFAULT


## Δv (km/s) a single missile can deliver, via Tsiolkovsky on the
## per-missile mass budget. Static so the Hangar / loadout panels can
## report it without instantiating the weapon. Returns km/s to match
## the orbit-state convention used everywhere else; Propulsion's
## dv_capacity_ms returns m/s, so divide by 1000.
static func dv_budget_per_missile_kms() -> float:
	return Propulsion.dv_capacity_ms(
		PROPELLANT_PER_MISSILE_KG, MISSILE_DRY_MASS_KG, MISSILE_ISP_S
	) * 1.0e-3


## Total missile mass including propellant, for the satellite's wet-
## mass accounting (mirrors RailgunWeapon.SLUG_MASS_KG × ammo_count).
static func wet_mass_per_missile_kg() -> float:
	return MISSILE_DRY_MASS_KG + PROPELLANT_PER_MISSILE_KG


## Damage delivered by one hit at default coupling, for the Hangar
## panel's tier summary.
static func base_damage_per_shot() -> float:
	return DAMAGE_HP * TARGET_COUPLING_DEFAULT


## Per-instance damage including tier multiplier and target coupling.
func damage_per_shot(target = null) -> float:
	return DAMAGE_HP * target_coupling_for(target) * damage_mult


func display_name() -> String:
	return "Missile"


func can_fire(attacker) -> bool:
	if attacker == null:
		return false
	if overheated:
		return false
	if heat_j > 0.0:
		return false
	if ammo_count <= 0:
		return false
	# Surface-anchored launchers could in principle fire (a missile
	# leaves its rail rather than recoiling onto the launcher), but the
	# surface-position update path overwrites orbit each tick so the
	# missile-spawn launch-state would be inconsistent. Refuse for
	# now; surface missile silos are a Phase-2 expansion.
	if attacker.is_surface:
		return false
	return attacker.energy >= ENERGY_PER_LAUNCH_J


## Cheap envelope filter. The expensive Lambert check happens in
## pick_target. Keeping this cheap means HUD / debug callers that ask
## "is X a missile target?" don't pay the per-call Lambert cost.
func is_target_in_engagement_envelope(attacker, target) -> bool:
	if attacker == null or target == null:
		return false
	if not attacker.alive or not target.alive:
		return false
	if attacker.team == target.team:
		return false
	if not attacker.orbit_alive or not target.orbit_alive:
		return false
	if target.has_method("is_inert_asteroid") and target.is_inert_asteroid():
		return false
	# Cheap distance gate: ranges far beyond the missile's reachable
	# horizon get rejected without running Lambert. The 3× slack
	# inside _max_reach_km is generous enough to keep marginal
	# candidates inside.
	var sep: float = (target.orbit.r - attacker.orbit.r).length()
	if sep > _max_reach_km():
		return false
	return true


## Iterate candidates, run (cached) Lambert for each, pick the one
## with the lowest dv that fits the missile's per-shot budget.
## Targets already reserved by an in-flight missile from any launcher
## should be filtered upstream by the CombatController — this method
## doesn't know about that reservation map.
func pick_target(attacker, candidates: Array, sim_time: float):
	if attacker == null:
		return null
	# Sweep expired entries so the cache doesn't grow unbounded over
	# long sessions. Cheap because the cache is O(candidates) ~ tens
	# of entries.
	_evict_expired(sim_time)

	var dv_budget: float = dv_budget_per_missile_kms()
	var best = null
	var best_dv_mag: float = INF
	for other in candidates:
		if other == attacker:
			continue
		if not is_target_in_engagement_envelope(attacker, other):
			continue
		var entry: Dictionary = _ensure_cache_entry(attacker, other, sim_time, dv_budget)
		if not entry.reachable:
			continue
		if entry.dv_mag > dv_budget:
			continue
		if entry.dv_mag < best_dv_mag:
			best_dv_mag = entry.dv_mag
			best = other
	return best


## Build the pending Dict that MissileSpawner consumes to materialise
## the in-flight missile. Mirrors RailgunWeapon.prepare_shot but does
## NOT mutate the attacker's orbit (missile leaves a rail, no recoil).
## Returns null on any failure — caller treats that as "no fire this
## tick".
##
## sim_time is required: the spawned missile expires at
## sim_time + expiry_tof_buffer, and the freshness window is keyed
## off it.
##
## Lambert is re-solved here even when the cache has a fresh entry,
## because the cache may be a few sim-seconds old and the attacker's
## launch state has drifted since. The fire-time solution is bound to
## the attacker's *current* orbit.r / orbit.v so the spawned missile
## actually intercepts where it's predicted to.
func prepare_shot(attacker, target, sim_delta: float, sim_time: float):
	if sim_delta <= 0.0:
		return null
	if not can_fire(attacker):
		return null
	if not is_target_in_engagement_envelope(attacker, target):
		return null

	var dv_budget: float = dv_budget_per_missile_kms()
	# Cheap pre-check: if the cache says unreachable at all, fall
	# through without firing. (A reachable target with a stale cache
	# still gets a fresh solve below.)
	if _intercept_cache.has(target.get_instance_id()):
		var cached: Dictionary = _intercept_cache[target.get_instance_id()]
		if not cached.reachable:
			return null

	var solution: Dictionary = LambertSolver.find_best_intercept(
		attacker.orbit.r, attacker.orbit.v,
		target.orbit,
		MIN_TOF_SEC, MAX_TOF_SEC,
		12, 6,
		dv_budget,
		BLAST_RADIUS_KM * 4.0
	)
	if not solution.ok:
		return null
	if (solution.dv as Vector3).length() > dv_budget:
		return null

	# Decrement ammo and bookkeeping FIRST so a no-op caller can't
	# spam-fire by virtue of can_fire still returning true post-call.
	# The pending Dict carries the launch state to the spawner.
	ammo_count -= 1
	attacker.energy = maxf(attacker.energy - ENERGY_PER_LAUNCH_J, 0.0)
	heat_j = heat_capacity_j
	overheated = true
	# Removing the missile's wet mass off the launcher mirrors how the
	# railgun pulls slug mass out of the magazine. recompute_mass
	# pulls dry + propellant + (railgun ammo × slug mass + missile
	# ammo × missile mass) into the satellite's wet mass, so the
	# total_ammo_mass_kg helper on the satellite needs to include
	# missile contributions (handled in the Satellite patch).
	if attacker.has_method("recompute_mass"):
		attacker.recompute_mass()
	# Drop the cache entry — it was for a missile already inbound;
	# reusing it would let two missiles spawn against the same launch.
	_intercept_cache.erase(target.get_instance_id())

	return {
		"launch_r": attacker.orbit.r,
		"launch_v": solution.v1,
		"target_iid": target.get_instance_id(),
		"attacker_iid": attacker.get_instance_id(),
		"tof": solution.tof,
		"blast_radius_km": BLAST_RADIUS_KM,
		"damage_hp": damage_per_shot(target),
		"spawn_sim_time": sim_time,
		# Expiry: TOF + 30s slack — the missile self-destructs if the
		# detonation hasn't happened by then. 30 s catches numerical
		# drift in the propagator and any missed-by-a-tick proximity
		# events.
		"expiry_sim_time": sim_time + solution.tof + 30.0,
	}


## Synchronous fire path is unsupported: missile damage applies on
## arrival, not at fire time. CombatController must call prepare_shot
## directly and hand the pending Dict to MissileSpawner. Returning
## false here keeps the base-class contract honest (no fire happened
## this tick from the perspective of the laser-style branch).
func fire(_attacker, _target, _sim_delta: float) -> bool:
	return false


## Number of intercept solutions currently cached. Test affordance —
## lets the missile-weapon tests verify the cache reuse path without
## poking at the private dictionary directly.
func cache_size() -> int:
	return _intercept_cache.size()


# --- internals -------------------------------------------------------------


func _ensure_cache_entry(
	attacker, target, sim_time: float, dv_budget: float
) -> Dictionary:
	var tid: int = target.get_instance_id()
	if _intercept_cache.has(tid):
		var cached: Dictionary = _intercept_cache[tid]
		if sim_time < cached.expires_at:
			return cached
	# Cache miss / expired. Solve.
	var result: Dictionary = LambertSolver.find_best_intercept(
		attacker.orbit.r, attacker.orbit.v,
		target.orbit,
		MIN_TOF_SEC, MAX_TOF_SEC,
		12, 6,
		dv_budget,
		# Round-trip miss tolerance: be generous in the solver (give
		# any Lambert solution a chance), and let the missile's own
		# proximity fuze handle the actual engagement at run time.
		BLAST_RADIUS_KM * 4.0
	)
	var entry: Dictionary
	if result.ok:
		entry = {
			"expires_at": sim_time + CACHE_TTL_SEC,
			"reachable": true,
			"dv": result.dv,
			"dv_mag": (result.dv as Vector3).length(),
			"tof": result.tof,
			"v1": result.v1,
		}
	else:
		entry = {
			"expires_at": sim_time + CACHE_TTL_SEC,
			"reachable": false,
			"dv": Vector3.ZERO,
			"dv_mag": INF,
			"tof": 0.0,
			"v1": Vector3.ZERO,
		}
	_intercept_cache[tid] = entry
	return entry


func _evict_expired(sim_time: float) -> void:
	# Build a key-list to avoid mutating the dictionary mid-iteration.
	var dead: Array[int] = []
	for key in _intercept_cache.keys():
		var k: int = key
		var e: Dictionary = _intercept_cache[k]
		if sim_time >= e.expires_at:
			dead.append(k)
	for k in dead:
		_intercept_cache.erase(k)
