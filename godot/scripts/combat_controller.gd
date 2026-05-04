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
const RailgunWeapon = preload("res://scripts/weapons/railgun_weapon.gd")
const HUD = preload("res://scripts/hud.gd")
const BeamRenderer = preload("res://scripts/beam_renderer.gd")
const SlugRenderer = preload("res://scripts/slug_renderer.gd")

var _hud: HUD = null
var _beam_renderer: BeamRenderer = null
var _slug_renderer: SlugRenderer = null
# Operator-toggled (U): when true, railgun fires spawn moving slug
# projectiles via SlugRenderer; when false, railguns route through
# BeamRenderer like lasers do (the legacy instant-beam visual). Lasers
# always go through BeamRenderer regardless of this flag.
var _slug_render_enabled: bool = true


func setup(
	hud: HUD,
	beam_renderer: BeamRenderer,
	slug_renderer: SlugRenderer,
) -> void:
	_hud = hud
	_beam_renderer = beam_renderer
	_slug_renderer = slug_renderer


## Operator toggle: route railgun fires through SlugRenderer (true) or
## fall back to BeamRenderer (false). Dropping out of slug-mode
## clears any in-flight slugs so they don't linger after the visual
## surface is silenced; the inverse transition has nothing to clear
## (BeamRenderer's lasers tick down on their own).
func set_slug_render_enabled(enabled: bool) -> void:
	if _slug_render_enabled == enabled:
		return
	_slug_render_enabled = enabled
	if not enabled and _slug_renderer != null:
		_slug_renderer.clear_all()


func is_slug_render_enabled() -> bool:
	return _slug_render_enabled


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
				if target != null:
					# Two paths: slug-render railguns split shooter and
					# target effects so the visible damage waits for
					# the tracer to arrive (otherwise a one-shot kill
					# pops the body off-screen mid-flight). Lasers and
					# beam-mode railguns stay synchronous — the legacy
					# fire() applies everything at once.
					if w is RailgunWeapon and _slug_render_enabled:
						fired = _fire_railgun_with_slug(
							sat, w as RailgunWeapon, target, sim_delta,
						)
					elif w.fire(sat, target, sim_delta):
						fired = true
						_hud.register_hit(sat, target)
						_beam_renderer.register_fire(sat, w_idx, target)
			if not fired:
				w.tick(sim_delta)


# Slug-mode railgun fire: shooter effects apply now (recoil, ammo,
# energy, cooldown), target effects defer to slug arrival via the
# on_arrival callable.
#
# Closure captures instance_ids (ints) rather than Satellite refs:
# the simulation queue_free's dead satellites, and a slug can be in
# flight for many sim-seconds, so capturing the Node directly trips
# Godot's "lambda capture was freed" warning the moment the target
# (or attacker) is cleaned up. instance_from_id returns null for a
# freed id, which is_instance_valid then catches cleanly. Weapon
# (RefCounted) and the captured `pending` Dictionary are safe by
# value; _hud is read off self at call time so it tracks live state
# without a capture.
func _fire_railgun_with_slug(
	attacker: Satellite,
	weapon: RailgunWeapon,
	target: Satellite,
	sim_delta: float,
) -> bool:
	var pending = weapon.prepare_shot(attacker, target, sim_delta)
	if pending == null:
		return false
	var attacker_iid: int = attacker.get_instance_id()
	var target_iid: int = target.get_instance_id()
	var on_arrival := func() -> void:
		var t = instance_from_id(target_iid)
		if t == null or not is_instance_valid(t) or not t.alive:
			return
		var a = instance_from_id(attacker_iid)
		var attacker_for_credit = a if a != null and is_instance_valid(a) else null
		weapon.apply_impact(attacker_for_credit, t, pending)
		# HUD flash fires on arrival (not at trigger pull) so the
		# roster red flash lines up with the slug visually striking
		# the box. Drop the flash if the impact actually killed the
		# attribution path — the kill happened, but there's no live
		# shooter to credit.
		if attacker_for_credit != null:
			_hud.register_hit(attacker_for_credit, t)
	_slug_renderer.register_fire(attacker, target, on_arrival)
	return true


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


