class_name CombatController
extends Node
## Tower-defense combat scheduler. Each physics tick the controller
## charges per-satellite energy and delegates target selection + fire
## to each weapon's strategy methods (`pick_target`, `fire`). Weapons
## that don't fire this tick cool toward ready instead. Pure
## scheduling — no input, no spawning, no planning-mode logic.
## Splitting this out of EarthSystem makes the hot loop profileable in
## isolation and gives the eventual server-authoritative refactor a
## clean seam.

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
				# Targeting is the weapon's responsibility — laser ranks
				# in-envelope candidates by attacker.targeting_mode, the
				# railgun picks randomly across LOS-clear safe shots.
				var target: Satellite = w.pick_target(sat, candidates, sim_time)
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


