class_name MissileSpawner
extends Node3D
## Owns the in-flight Missile entities and their lifecycle. Spawned
## by MassCenterSystem at scene boot; consulted by CombatController
## both to spawn new missiles (after a MissileWeapon.prepare_shot
## succeeds) and to gate target-reservation (one inbound missile per
## target, fleet-wide).
##
## Mirrors the role SlugRenderer plays for railgun slugs, but with
## the simulation side carrying more weight: SlugRenderer is purely
## visual (damage already applied at fire-time); MissileSpawner owns
## the missile's whole tick path because the proximity-fuze decision
## happens at run time inside Missile.tick.
##
## Reservation map lives here rather than on CombatController because
## the missile's lifetime is the authority on when the reservation
## releases (detonate / miss / expire). The on_terminate closure on
## each Missile erases its entry, regardless of termination cause.

const Missile = preload("res://scripts/missile.gd")
const MassCenterOrbit = preload("res://scripts/mass_center_orbit.gd")
const ImpactExplosion = preload("res://scripts/impact_explosion.gd")

# Visual radius (km) of the detonation sphere. Calibrated for a
# 100 MT yield: the physics-grounded lethal X-ray radius is ~50 km
# (see MissileWeapon.BLAST_RADIUS_KM rationale), but at scene scale
# 1 unit = 1000 km that's a 5-pixel speck. ImpactExplosion's
# VISUAL_GAIN bumps asteroid impacts ~4× for the same readability
# problem; missiles use a fixed exaggerated value so every
# detonation reads as a dramatic event regardless of the geometry
# that triggered it. 2500 km sits well below the MAX_RADIUS_KM
# (4000) cap and roughly matches the asteroid-explosion size for a
# large impactor — the operator's eye sees them as comparable
# energy-scale events.
const DETONATION_RADIUS_KM: float = 2500.0

# Active missiles. The list is the only owner of the Missile Node3D
# references — when a missile terminates, queue_free runs and we drop
# it from this array on the next tick.
var _missiles: Array[Missile] = []
# target_iid (int) → true. Membership-only; values unused.
var _reserved_target_iids: Dictionary = {}


## True if a missile is currently inbound on the target with this
## instance id. CombatController consults this before picking a
## missile target so two launchers don't double-spend on the same body.
func has_reservation(target_iid: int) -> bool:
	return _reserved_target_iids.has(target_iid)


## Materialise a missile from the MissileWeapon's pending Dict. Adds
## it as a child of self (so its scene transform is at world origin —
## OrbitalPath's _compute_points already scales km→scene-units
## internally) and registers the reservation. Returns the Missile
## reference for tests / callers that need it; nothing in the live
## game has to capture it (the spawner owns the lifetime).
##
## pending Dict must contain (mirrors MissileWeapon.prepare_shot
## output): launch_r, launch_v, target_iid, attacker_iid, tof,
## blast_radius_km, damage_hp, spawn_sim_time, expiry_sim_time.
func spawn(attacker: Object, target: Object, pending: Dictionary, _sim_time: float) -> Missile:
	var missile := Missile.new()
	# Configure BEFORE add_child so _ready picks up orbit and renders
	# the initial path immediately. We don't need most of the
	# pending Dict here — Missile holds its own copies — but the
	# launch state has to flow in via the constructed orbit.
	var orbit := MassCenterOrbit.new(pending.launch_r, pending.launch_v)
	missile.configure(
		orbit,
		target,
		attacker,
		pending.blast_radius_km,
		pending.damage_hp,
		pending.spawn_sim_time,
		pending.expiry_sim_time,
	)

	var tid: int = pending.target_iid
	_reserved_target_iids[tid] = true
	# Erase the reservation when the missile terminates (any cause).
	# Capture by value: tid is an int, the dictionary is by-reference,
	# both safe across the missile's flight.
	var reserved: Dictionary = _reserved_target_iids
	missile.on_terminate = func() -> void:
		reserved.erase(tid)

	_missiles.append(missile)
	add_child(missile)
	return missile


## Advance every active missile by sim_delta. Sweeps terminated
## missiles out of the active list, queue_free's them so the scene
## tree drops the visuals at the end of the physics tick. Returns
## the count terminated this tick (test affordance — also surfaces
## via active_missile_count).
func tick(sim_delta: float, sim_time: float) -> int:
	if _missiles.is_empty():
		return 0
	var alive: Array[Missile] = []
	var terminated_count: int = 0
	for m in _missiles:
		if m == null or not is_instance_valid(m):
			terminated_count += 1
			continue
		if m.tick(sim_delta, sim_time):
			alive.append(m)
		else:
			terminated_count += 1
			# Detonation visual: spawn an exaggerated explosion sphere
			# at the missile's final position. Only on TERM_DETONATED
			# — miss / expiry / subsurface terminations get no boom
			# (no warhead actually went off). The sphere parents to
			# the spawner so it inherits world-origin transform; it
			# self-frees after ImpactExplosion.DURATION.
			if m.last_termination == Missile.TERM_DETONATED:
				_spawn_detonation(m.orbit.r)
			# queue_free runs at the end of the physics tick. The
			# Missile's on_terminate has already fired inside tick
			# (releases the reservation), so by the time the node is
			# physically freed the spawner state is already coherent.
			m.queue_free()
	_missiles = alive
	return terminated_count


func _spawn_detonation(pos_km: Vector3) -> void:
	var explosion := ImpactExplosion.new()
	explosion.peak_radius_km = DETONATION_RADIUS_KM
	add_child(explosion)
	explosion.set_impact_position(pos_km)


## Drop every active missile without applying damage. Used by tests
## and by MassCenterSystem when tearing the scene down between
## missions. Reservation map is cleared as a side effect of each
## missile's on_terminate.
func clear_all() -> void:
	for m in _missiles:
		if m != null and is_instance_valid(m):
			# Force-terminate as MISSED so the on_terminate closure
			# fires and releases the reservation. queue_free follows.
			m.terminate(Missile.TERM_MISSED)
			m.queue_free()
	_missiles.clear()
	# Belt-and-braces: explicit clear so the dictionary is empty even
	# if any termination closure misbehaved.
	_reserved_target_iids.clear()


## Number of missiles currently in flight. Test affordance — also
## useful for HUD counters in Phase 2.
func active_missile_count() -> int:
	return _missiles.size()


## Number of target reservations currently held. Test affordance for
## verifying the spawn → on_terminate lifecycle.
func reserved_target_count() -> int:
	return _reserved_target_iids.size()
