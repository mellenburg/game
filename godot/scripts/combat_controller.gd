class_name CombatController
extends Node
## Tower-defense combat scheduler. Each physics tick the controller
## charges per-satellite energy, picks a target for every armed weapon
## (closest in-envelope under MAX_DAMAGE; soonest predicted ground
## impact under MAX_DANGER, with distance² as a tiebreaker), and
## applies dt-scaled damage / drain / heating. Weapons that don't fire
## this tick cool toward ready instead. Pure scheduling — no input,
## no spawning, no planning-mode logic. Splitting this out of
## EarthSystem makes the hot loop profileable in isolation and gives
## the eventual server-authoritative refactor a clean seam.

const Satellite = preload("res://scripts/satellite.gd")
const Weapon = preload("res://scripts/weapons/weapon.gd")
const HUD = preload("res://scripts/hud.gd")
const BeamRenderer = preload("res://scripts/beam_renderer.gd")

var _hud: HUD = null
var _beam_renderer: BeamRenderer = null


func setup(hud: HUD, beam_renderer: BeamRenderer) -> void:
	_hud = hud
	_beam_renderer = beam_renderer


# Charge each satellite's energy pool, then either fire each weapon
# at the closest valid enemy or let it cool. Lasers are continuous-
# fire: the same call applies dt-scaled damage, energy drain, and
# heating; weapons that don't fire this tick cool toward ready instead.
# Tower-defense: no player input needed.
func process_combat(
	satellites: Array[Satellite], sim_time: float, sim_delta: float
) -> void:
	# One alive-and-orbit-alive scan per tick instead of one per weapon —
	# the cheap pre-filter shared across every targeting query collapses
	# the inner loop's work to envelope-distance + LOS, which is what
	# actually depends on the attacker.
	var candidates := _collect_targetable(satellites)
	for sat in satellites:
		if not sat.alive:
			continue
		sat.tick_combat(sim_delta)
		for w_idx in range(sat.weapons.size()):
			var w: Weapon = sat.weapons[w_idx]
			var fired := false
			if w.can_fire(sat):
				var target := _pick_target_for_weapon(sat, w, candidates, sim_time)
				if target != null and w.fire(sat, target, sim_delta):
					fired = true
					_hud.register_hit(sat, target)
					_beam_renderer.register_fire(sat, w_idx, target)
			if not fired:
				w.tick(sim_delta)


# Bodies that can plausibly be shot at this tick. The team check is
# left to the per-attacker pass (an attacker's valid targets are the
# bodies on the *opposing* team) but everything else — alive flags,
# orbit_alive, dead-but-not-yet-swept entries — is universal and gets
# filtered once here so each weapon's inner loop touches a smaller
# array.
func _collect_targetable(satellites: Array[Satellite]) -> Array[Satellite]:
	var out: Array[Satellite] = []
	for sat in satellites:
		if sat.alive and sat.orbit_alive:
			out.append(sat)
	return out


func _pick_target_for_weapon(
	attacker: Satellite,
	w: Weapon,
	candidates: Array[Satellite],
	sim_time: float,
) -> Satellite:
	# Two-key lexicographic ranking. In MAX_DAMAGE mode the primary key is
	# distance² (closest wins, so range-falloff damage is highest). In
	# MAX_DANGER mode the primary key is predicted time-to-impact (soonest
	# threat to Earth wins), with distance² as a tiebreaker so non-impacting
	# candidates fall back to the same closest-target rule rather than
	# leaving the weapon idle when nothing is currently inbound. Time-to-
	# impact is computed only when MAX_DANGER is active — the propagation
	# clone is cheap but not free, so MAX_DAMAGE keeps the original tight
	# loop.
	var max_danger := attacker.targeting_mode == Satellite.TARGETING_MAX_DANGER
	var best: Satellite = null
	var best_t := INF
	var best_d2 := INF
	for other in candidates:
		if other == attacker:
			continue
		if other.team == attacker.team:
			continue
		if not w.is_target_in_engagement_envelope(attacker, other):
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
