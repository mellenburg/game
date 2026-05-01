class_name Satellite
extends Node3D
## A spacecraft: orbital state, marker mesh, orbit path, hit points, and
## an optional weapon. Marker mesh and material are created once in
## _ready(); selection / damage just toggles the cached material's
## albedo_color.

const EarthOrbit = preload("res://scripts/earth_orbit.gd")
const OrbitalPath = preload("res://scripts/orbital_path.gd")
const Weapon = preload("res://scripts/weapons/weapon.gd")
const LaserWeapon = preload("res://scripts/weapons/laser_weapon.gd")

const TEAM_PLAYER: int = 0
const TEAM_ENEMY: int = 1

# Laser targeting modes. MAX_DAMAGE picks the closest in-envelope target
# (current-distance scoring, so range-falloff damage is highest);
# MAX_DANGER picks the in-envelope target with the smallest predicted
# time-to-impact-on-Earth, falling back to closest distance when no
# candidate is on a current-trajectory impact path. Stored on the
# satellite so each ship can carry its own setting; toggled per-unit
# (L) or fleet-wide (Shift+L).
const TARGETING_MAX_DAMAGE: int = 0
const TARGETING_MAX_DANGER: int = 1

const SCENE_SCALE: float = 1.0 / 1000.0
const DEFAULT_R := Vector3(-6045.0, -3490.0, 2500.0)
const DEFAULT_V := Vector3(-3.56, 6.618, 2.533)
const DELTA_V_MAGNITUDE: float = 0.050
const COLOR_SELECTED := Color(0.2, 1.0, 0.2)
const COLOR_PLAYER := Color(0.4, 0.6, 1.0)
const COLOR_ENEMY := Color(1.0, 0.35, 0.35)
const COLOR_METEORITE := Color(1.0, 0.85, 0.4)
const COLOR_DECAYING := Color(0.95, 0.45, 0.95)
const COLOR_HIT := Color(1.0, 0.25, 0.05)

const MAX_HP: float = 100.0
# Player thrust is clamped each tick so the resulting orbit's periapsis
# stays at or above this radius. Sits a hair above EARTH_RADIUS_KM so
# floating-point slop in the propagator can't tip the body across the
# surface termination check.
const SAFE_PERIAPSIS_KM: float = EarthOrbit.EARTH_RADIUS_KM + 1.0
const ENERGY_MAX: float = 1.0
# Fraction of the energy pool gained per simulated second. Doubled
# from the prior 0.00007 to compensate for the halved per-shot cost
# and the fact that two lasers share one reservoir.
const ENERGY_RATE_PER_SIM_SEC: float = 0.00014

var orbit: EarthOrbit
var selected: bool = false
var raw_maneuver := Vector3.ZERO
var did_maneuver: bool = false
var orbit_alive: bool = true

var team: int = TEAM_PLAYER
# Per-instance HP cap. Defaults to MAX_HP for player / standard enemy
# satellites; threat-spawning paths (meteorite, decaying-orbit body)
# override it with their own cap and seed `hp` to the same value.
var max_hp: float = MAX_HP
var hp: float = MAX_HP
var alive: bool = true
# Sub-orbital trajectory (a meteorite) — its periapsis is below Earth's
# surface by construction, so it impacts ground in finite time. Used to
# suppress the orbit-path visual (a meaningless ellipse clipping through
# Earth) and to terminate the entity on ground contact.
var is_meteorite: bool = false
# Decaying-orbit enemy: spawned just past apogee on a highly eccentric
# ellipse, descending. Each perigee crossing fires a retrograde burn
# that halves r_a, so the orbit spirals inward; once the burn drops
# the trailing apsis below the surface the body impacts on its next
# descending leg. Drives both the burn step in advance_time and the
# render dispatch (full ellipse while r_p ≥ R, truncated trajectory
# once r_p dips below the surface).
var is_decaying: bool = false
# Shared energy reservoir, drained by every weapon's fire(). Charges
# at ENERGY_RATE_PER_SIM_SEC per simulated second so time_factor
# scales it the same as everything else.
var energy: float = 0.0
# Empty for unarmed units (e.g. enemies in the MVP). Player satellites
# spawn with two lasers; weapons fire independently but share energy.
var weapons: Array[Weapon] = []
# Operator-set cap on weapon engagement distance (km). Honored by the
# laser only while fire_control_active is true — turning fire control
# off restores default "fire at any LOS enemy out to MAX_RANGE_KM"
# behaviour without forcing the operator to widen the slider back up
# first. Defaults to LaserWeapon.MAX_RANGE_KM so a freshly-toggled-on
# fire control mode doesn't immediately silence the weapon.
var engagement_range_km: float = LaserWeapon.MAX_RANGE_KM
# Fire-control mode toggle. While active, the operator can adjust
# engagement_range_km (Shift+Up/Down), see the range circle (Shift),
# and the laser obeys the cap. Toggled off, the cap is dropped and
# the weapon reverts to default LOS-only firing — but the saved
# engagement_range_km value is preserved so re-toggling fire control
# brings the same setting back.
var fire_control_active: bool = false
# Per-ship laser targeting mode. Honored by EarthSystem._pick_target_for_weapon
# when selecting which in-envelope enemy each weapon will fire at this tick.
# Cloned across planning satellites so the planning view shows the same
# auto-targeting choice the live simulation will make.
var targeting_mode: int = TARGETING_MAX_DAMAGE

# Wall-clock timestamp at which the orange "I got hit" tint reverts to
# the team color. Wall-clock so the pulse is visible regardless of how
# compressed time_factor makes sim seconds.
var _flash_until: float = 0.0

var _marker: MeshInstance3D
var _marker_mat: StandardMaterial3D
var path_visual: OrbitalPath


func _init() -> void:
	orbit = EarthOrbit.new(DEFAULT_R, DEFAULT_V)
	weapons = [LaserWeapon.new(), LaserWeapon.new()]


## Charge the shared energy pool. Per-weapon cooling is driven by
## EarthSystem._process_combat — only weapons that did NOT fire this
## tick get their tick() called, since fire() handles its own heat
## bookkeeping.
func tick_combat(sim_delta: float) -> void:
	if sim_delta <= 0.0:
		return
	energy = clampf(energy + ENERGY_RATE_PER_SIM_SEC * sim_delta, 0.0, ENERGY_MAX)


func _ready() -> void:
	_marker = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.15, 0.15, 0.15)
	_marker.mesh = box

	_marker_mat = StandardMaterial3D.new()
	_marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker_mat.albedo_color = _base_color()
	_marker.material_override = _marker_mat
	add_child(_marker)

	path_visual = OrbitalPath.new()
	add_child(path_visual)

	_apply_color()
	_sync_marker_position()


func _process(_delta: float) -> void:
	# Revert the hit-flash tint once its wall-clock window passes. Cheap
	# enough to do every frame; the alternative (HUD driving it) couples
	# the visual back into the controller.
	if _flash_until > 0.0 and _wall_now() >= _flash_until:
		_flash_until = 0.0
		_apply_color()


## Tint the 3D orbit marker orange for `duration` wall-clock seconds.
## HUD calls this when a weapon successfully fires at this satellite,
## so the marker pulses regardless of game time-factor compression.
func flash_hit(duration: float) -> void:
	if duration <= 0.0:
		return
	_flash_until = _wall_now() + duration
	if _marker_mat != null:
		_marker_mat.albedo_color = COLOR_HIT


func _wall_now() -> float:
	return Time.get_ticks_msec() / 1000.0


func select() -> void:
	selected = true
	_apply_color()


func unselect() -> void:
	selected = false
	_apply_color()


func set_maneuver(input: Vector3) -> void:
	raw_maneuver = input
	did_maneuver = input.length_squared() > 0.0


## Flip the fire-control mode. Only meaningful on armed units; unarmed
## satellites (enemies, meteorites) keep the flag at false but caller
## still gets the no-op behavior right because their weapons array is
## empty.
func toggle_fire_control() -> void:
	fire_control_active = not fire_control_active


## Flip the laser targeting mode between MAX_DAMAGE (closest target) and
## MAX_DANGER (target whose trajectory impacts Earth soonest). Only
## meaningful on armed units; on unarmed bodies the flag is harmless but
## ignored by the combat loop.
func toggle_targeting_mode() -> void:
	if targeting_mode == TARGETING_MAX_DAMAGE:
		targeting_mode = TARGETING_MAX_DANGER
	else:
		targeting_mode = TARGETING_MAX_DAMAGE


## Clamp + assign the operator-set engagement range. The lower bound
## is the weapon's minimum so the operator can't disable fire control
## by accident; the upper bound is the physics-level max so anything
## past it is dead-on-arrival anyway.
func set_engagement_range(km: float) -> void:
	engagement_range_km = clampf(
		km,
		LaserWeapon.MIN_ENGAGEMENT_RANGE_KM,
		LaserWeapon.MAX_RANGE_KM,
	)


func get_current_maneuver() -> Vector3:
	return DELTA_V_MAGNITUDE * raw_maneuver


## Apply damage. Returns true if this hit took the satellite to 0 HP.
## Only kills once — repeated calls on a dead satellite are no-ops, so
## stray late shots from concurrent attackers don't double-fire the
## death transition.
func take_damage(amount: float) -> bool:
	if not alive or amount <= 0.0:
		return false
	hp = maxf(hp - amount, 0.0)
	if hp <= 0.0:
		alive = false
		_hide_visuals()
		return true
	return false


## Step the orbit forward. If the orbit goes pathological (NaN, escape
## that the propagator can't resolve), mark this satellite dead so the
## game controller can skip it instead of bringing the renderer down.
func advance_time(delta_time: float) -> void:
	if not orbit_alive or not alive:
		return
	# Sample r·v before propagating so we can detect periapsis crossings
	# the end-of-step radius sample alone would miss — a body on a near-
	# radial trajectory can dive through periapsis and back out above
	# the surface inside one step at high time_factor.
	var r_dot_v_before: float = orbit.r.dot(orbit.v)
	var ok: bool
	if did_maneuver:
		# Player thrust is the only caller of relative_maneuver; clamp
		# it so it can't drive periapsis below the surface. Meteorites
		# never enter this branch (no operator).
		ok = orbit.relative_maneuver(
			get_current_maneuver(), delta_time, SAFE_PERIAPSIS_KM
		)
	else:
		ok = orbit.propagate(delta_time)
	did_maneuver = false
	raw_maneuver = Vector3.ZERO
	if not ok:
		orbit_alive = false
		_hide_visuals()
		return
	# Decaying-orbit perigee burn. Descending → ascending transition
	# (r·v flips negative to positive) marks the perigee crossing;
	# scale velocity along its current direction to halve r_a. The
	# orbit shrinks toward circular, then — once r_a/2 drops below
	# r_p — the burn flips orientation: the body's current location
	# becomes the new orbit's apogee and the trailing apsis ends up
	# below the surface, so the surface-cross check in the rest of
	# this function terminates the body on its descent.
	if (
		is_decaying
		and r_dot_v_before < 0.0
		and orbit.r.dot(orbit.v) > 0.0
	):
		_perigee_decay_burn()
	# Any satellite whose trajectory crosses the surface exits play. The
	# Keplerian propagator is happy to push a body straight through the
	# planet and out the other side, so we kill on either (a) the post-
	# step radius being inside the surface, or (b) an inbound→outbound
	# transition during the step combined with a sub-surface periapsis
	# (the body just tunneled through ground inside one tick).
	var crossed_periapsis := r_dot_v_before < 0.0 and orbit.r.dot(orbit.v) > 0.0
	var sub_surface_periapsis := (
		is_finite(orbit.r_p) and orbit.r_p <= EarthOrbit.EARTH_RADIUS_KM
	)
	if (
		orbit.norm_r <= EarthOrbit.EARTH_RADIUS_KM
		or (crossed_periapsis and sub_surface_periapsis)
	):
		alive = false
		_hide_visuals()
		return
	_sync_marker_position()


func render_orbit(show_path: bool) -> void:
	if not is_inside_tree() or path_visual == null:
		return
	if not orbit_alive or not alive:
		path_visual.visible = false
		return
	path_visual.visible = show_path
	if not show_path:
		return
	path_visual.color = COLOR_SELECTED if selected else _base_color()
	# Meteorites get the truncated-trajectory renderer: the same line
	# style as a regular orbit, but cut off at the surface so the part
	# that would tunnel through Earth isn't drawn.
	if is_decaying:
		# Render the body's entire predicted future trajectory as a
		# multi-segment spiral: current arc to next perigee, then a
		# full ellipse for each remaining post-burn orbit, then the
		# truncated final inbound leg to the surface. The spiral
		# tells the player how many cycles are left before impact.
		path_visual.update_decaying_spiral(orbit)
	elif is_meteorite:
		path_visual.update_trajectory(orbit)
	else:
		path_visual.update_orbit(orbit)


# Halve r_a by scaling the velocity vector along its own direction.
# At (or near) perigee the velocity is tangential, so shrinking it
# preserves r_p and pulls r_a in by the analytic factor that falls
# out of the vis-viva identity at perigee:
#   v_p² = 2μ r_a / (r_p·(r_p + r_a))
# Same factor as the apogee mirror with r_p ↔ r_a swapped — once
# the requested r_a/2 drops below r_p the burn over-shoots and the
# body's current point becomes the new orbit's apogee, with the
# trailing apsis ending up below ground; that's the impact case.
func _perigee_decay_burn() -> void:
	var r_p := orbit.r_p
	var r_a := orbit.r_a
	if (
		not is_finite(r_p) or not is_finite(r_a)
		or r_p <= 0.0 or r_a <= 0.0
	):
		return
	var k := sqrt((r_p + r_a) / (2.0 * r_p + r_a))
	# maneuver(dv, t=0) skips propagation and applies the velocity delta,
	# then recomputes derived elements — equivalent to "set v" without
	# touching the propagator's private API.
	var dv := orbit.v * (k - 1.0)
	if not orbit.maneuver(dv, 0.0):
		orbit_alive = false
		_hide_visuals()


## Full clone — orbital state and operator-queued maneuver intent.
## Use on planning-mode entry, where you want the plan to start identical
## to reality.
func clone_from(other: Satellite) -> void:
	clone_orbit_from(other)
	raw_maneuver = other.raw_maneuver
	did_maneuver = other.did_maneuver


## Clone only the orbital state (r, v, derived elements). Use this every
## physics tick during planning so the plan's snapshot tracks reality
## without nuking any maneuver the user has queued in the planning UI.
func clone_orbit_from(other: Satellite) -> void:
	orbit.clone_from(other.orbit)
	selected = other.selected
	orbit_alive = other.orbit_alive
	team = other.team
	max_hp = other.max_hp
	hp = other.hp
	alive = other.alive
	is_meteorite = other.is_meteorite
	is_decaying = other.is_decaying
	# Mirror armed-vs-unarmed so the planning HUD doesn't show an
	# energy bar for an enemy preview (clones get fresh weapons in
	# _init that we'd otherwise leave dangling).
	energy = other.energy
	engagement_range_km = other.engagement_range_km
	fire_control_active = other.fire_control_active
	targeting_mode = other.targeting_mode
	if other.weapons.is_empty():
		weapons.clear()
	if is_inside_tree():
		_apply_color()
		_sync_marker_position()


func _sync_marker_position() -> void:
	if _marker == null:
		return
	_marker.position = orbit.r * SCENE_SCALE


func _base_color() -> Color:
	if is_meteorite:
		return COLOR_METEORITE
	if is_decaying:
		return COLOR_DECAYING
	return COLOR_ENEMY if team == TEAM_ENEMY else COLOR_PLAYER


func _apply_color() -> void:
	if _marker_mat == null:
		return
	# Hit-flash overrides selection / team while it's active so the
	# pulse reads as a damage indicator even on the currently selected
	# unit. _process reverts via _apply_color when the window expires.
	if _flash_until > 0.0 and _wall_now() < _flash_until:
		_marker_mat.albedo_color = COLOR_HIT
		return
	_marker_mat.albedo_color = COLOR_SELECTED if selected else _base_color()


func _hide_visuals() -> void:
	if _marker:
		_marker.visible = false
	if path_visual:
		path_visual.visible = false
