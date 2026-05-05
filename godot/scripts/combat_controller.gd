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
const LaserWeapon = preload("res://scripts/weapons/laser_weapon.gd")
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
# Set of target instance_ids with a railgun slug currently in flight.
# While a target is in this set no other railgun will pick it — the
# first slug's damage hasn't landed yet, so without the gate every
# railgun in the fleet would dump a round at the same body the first
# shot is about to one-kill. Population happens in
# `_fire_railgun_with_slug`; the slug renderer's on_arrival /
# on_drop callbacks erase the entry when the round either applies
# damage or is dropped (attacker died, slug-render toggled off).
# Sync (beam-mode) railguns and lasers don't reserve: their damage
# lands on the same tick, so the next attacker's envelope check
# already sees the dead body. Stored as a Dictionary because
# GDScript lacks a Set primitive — values are unused.
var _reserved_target_iids: Dictionary = {}


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
## (BeamRenderer's lasers tick down on their own). clear_all routes
## each pending slug through on_drop, which empties the reservation
## map naturally — no separate reservation-clear is needed here.
func set_slug_render_enabled(enabled: bool) -> void:
	if _slug_render_enabled == enabled:
		return
	_slug_render_enabled = enabled
	if not enabled and _slug_renderer != null:
		_slug_renderer.clear_all()


func is_slug_render_enabled() -> bool:
	return _slug_render_enabled


# Charge each satellite's energy pool, drain heat through the cooling
# stack, then either fire each weapon at the closest valid enemy or
# leave it idle. Lasers are continuous-fire: the same call applies
# dt-scaled damage, energy drain, and heating. Tower-defense: no
# player input needed.
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
		# Phase 1: cooling. Split the unit's cooling power evenly across
		# every weapon currently above zero heat; a sole demander gets
		# 100%, two share 50/50, etc. Cool BEFORE firing so a weapon that
		# has just cleared the overheat latch can pick up a target this
		# same tick (rather than skipping a beat).
		_distribute_cooling(sat, sim_delta)
		for w_idx in range(sat.weapons.size()):
			var w: Weapon = sat.weapons[w_idx]
			if not w.can_fire(sat):
				continue
			# Targeting is the weapon's responsibility — laser ranks
			# in-envelope candidates by attacker.targeting_mode, the
			# railgun picks randomly across LOS-clear safe shots.
			# Slug-mode railguns get a candidate list pre-filtered to
			# exclude bodies that already have an in-flight slug
			# headed their way; the gate prevents fleet-wide overkill
			# where the first slug is already a one-shot kill but
			# every other railgun queues a round before the damage
			# lands. Lasers and beam-mode railguns see the full list:
			# their damage applies synchronously, so the next
			# attacker's envelope check naturally skips a freshly
			# dead body.
			var weapon_candidates: Array = candidates
			if (
				w is RailgunWeapon
				and _slug_render_enabled
				and not _reserved_target_iids.is_empty()
			):
				weapon_candidates = _exclude_reserved(candidates)
			var target: Satellite = w.pick_target(
				sat, weapon_candidates, sim_time
			)
			if target == null:
				continue
			# Two paths: slug-render railguns split shooter and target
			# effects so the visible damage waits for the tracer to
			# arrive (otherwise a one-shot kill pops the body off-screen
			# mid-flight). Lasers and beam-mode railguns stay
			# synchronous — the legacy fire() applies everything at once.
			if w is RailgunWeapon and _slug_render_enabled:
				_fire_railgun_with_slug(sat, w as RailgunWeapon, target, sim_delta)
			elif w.fire(sat, target, sim_delta):
				_hud.register_hit(sat, target)
				var style: String = (
					BeamRenderer.STYLE_LASER
					if w is LaserWeapon
					else BeamRenderer.STYLE_KINETIC
				)
				_beam_renderer.register_fire(sat, w_idx, target, style)


func _distribute_cooling(sat: Satellite, sim_delta: float) -> void:
	if sat.cooling_power_w <= 0.0 or sim_delta <= 0.0:
		return
	var demanding: Array[Weapon] = []
	for w: Weapon in sat.weapons:
		if w.demands_cooling():
			demanding.append(w)
	if demanding.is_empty():
		return
	var per_weapon: float = sat.cooling_power_w / float(demanding.size())
	for w in demanding:
		w.cool(per_weapon, sim_delta)


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
	# Reserve the target before the slug spawns: any subsequent
	# railgun in this same tick (or later ticks until arrival)
	# that consults `_exclude_reserved` will skip this body. Both
	# the on_arrival and on_drop callbacks erase the entry, so the
	# reservation lives for exactly the slug's flight.
	_reserved_target_iids[target_iid] = true
	var reserved := _reserved_target_iids
	var on_arrival := func() -> void:
		# Release the reservation before applying damage. Doing it
		# first means a downstream take_damage path (which can
		# call into Satellite kill bookkeeping and reorder
		# satellites in the fleet array) never observes a stale
		# reservation pointing at a freed instance id.
		reserved.erase(target_iid)
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
	# on_drop fires when the slug stops existing without arriving
	# (attacker died, operator toggled slug-render off). Damage is
	# forfeited, but the reservation must release or the target
	# stays locked out of every railgun for the rest of the run.
	var on_drop := func() -> void:
		reserved.erase(target_iid)
	_slug_renderer.register_fire(attacker, target, on_arrival, on_drop)
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


# Drop already-reserved bodies from the candidate list so a railgun
# in slug mode never picks a target that another railgun's slug is
# already on its way to strike. Allocating a new array each call is
# cheap (the candidate list is tens of entries at most, and the
# branch in the caller skips this entirely when the reservation
# map is empty).
func _exclude_reserved(cands: Array[Satellite]) -> Array[Satellite]:
	var out: Array[Satellite] = []
	for c in cands:
		if c == null:
			continue
		if not _reserved_target_iids.has(c.get_instance_id()):
			out.append(c)
	return out


## Test affordance: how many target bodies currently have an
## in-flight railgun slug reserved against them. Lets unit tests
## verify reservation lifecycle without poking the private
## dictionary directly.
func reserved_target_count() -> int:
	return _reserved_target_iids.size()


