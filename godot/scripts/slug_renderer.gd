class_name SlugRenderer
extends Node3D
## 3D railgun-slug visuals — a moving projectile, in contrast to the
## BeamRenderer's instant attacker→target line. Spawned by
## CombatController on a successful railgun fire when the operator has
## slug-render enabled (toggle: `U`); when disabled the railgun routes
## back to BeamRenderer so the visual matches the laser.
##
## Each slug travels in *sim time* at the weapon's muzzle velocity
## (RailgunWeapon.MUZZLE_VELOCITY_M_S) along the straight line between
## the *current* shooter and the *current* target. Both endpoints are
## sampled fresh every tick — the slug effectively homes on its
## target, which is non-physical (a real slug would carry on along its
## launch ray) but the simulation has already applied damage at fire-
## time, so the visual is purely cosmetic and the homing keeps the
## tracer pointed at something the operator can recognise.
##
## Lifecycle:
##   - register_fire spawns a slug stamped with the fire sim-time and
##     refs to the live attacker / target.
##   - Each tick, advance traveled_km by sim_delta × muzzle velocity.
##     Despawn once traveled_km exceeds the *current* attacker→target
##     distance (the slug "arrived").
##   - Attacker dying despawns its slugs immediately.
##   - Target dying freezes the endpoint at the target's last known
##     position so the slug still completes its arc to a fixed point.
##
## A single BoxMesh is shared across every slug; per-slug
## StandardMaterial3D is allocated once at spawn so _process only
## mutates transform + alpha (see CLAUDE.md "cache meshes and
## materials").

const Satellite = preload("res://scripts/satellite.gd")
const RailgunWeapon = preload("res://scripts/weapons/railgun_weapon.gd")

# Slug muzzle velocity in km / sim-second. Stored as a Satellite-frame
# constant so the kinematic helpers below don't need to know about
# RailgunWeapon's m/s convention. Equal to MUZZLE_VELOCITY_M_S × 1e-3.
const MUZZLE_VELOCITY_KMS: float = RailgunWeapon.MUZZLE_VELOCITY_M_S * 1.0e-3

# Visual: a small unshaded white cube at the slug's current position.
# 0.05 scene units (= 50 km equivalent at 1 unit / 1000 km) reads as
# a small but unmistakeable bead at the camera's typical 38-unit
# orbit — about 4-5 px on screen.
const SLUG_SIZE_SCENE: float = 0.05
const SLUG_COLOR := Color(1.0, 1.0, 1.0)

var _shared_mesh: BoxMesh
# key "<attacker_iid>:<seq>" → _Slug. seq increments per-attacker so
# rapid back-to-back shots don't collide on the dictionary key.
var _slugs: Dictionary = {}
var _next_seq: int = 0


class _Slug:
	var attacker: Satellite = null
	var target: Satellite = null
	# Distance traveled (km) since fire. Advanced each tick by
	# sim_delta × muzzle velocity; compared against the current
	# attacker→target distance to detect arrival.
	var traveled_km: float = 0.0
	# Last known target position (ECI km). Refreshed each tick while
	# the target is alive; frozen once it dies so the slug still has
	# a fixed endpoint to glide toward.
	var last_target_eci: Vector3 = Vector3.ZERO
	var inst: MeshInstance3D = null
	var mat: StandardMaterial3D = null


func _ready() -> void:
	_shared_mesh = BoxMesh.new()
	# Unit cube; per-slug transform scales each axis by SLUG_SIZE_SCENE.
	# Single shared mesh across every slug — see CLAUDE.md "cache
	# meshes and materials".
	_shared_mesh.size = Vector3.ONE


## Spawn a slug from `attacker` aimed at `target`. CombatController
## calls this when railgun fire() succeeded *and* slug-render is
## enabled. Both endpoints stay live — the slug homes on the target
## each frame rather than freezing direction at fire time, so a
## tracer always reads as pointed at something recognisable.
func register_fire(attacker: Satellite, target: Satellite, _sim_time: float) -> void:
	if attacker == null or target == null:
		return
	var slug := _Slug.new()
	slug.attacker = attacker
	slug.target = target
	slug.last_target_eci = target.orbit.r
	slug.mat = _make_material()
	slug.inst = _make_instance(slug.mat)
	var key := "%d:%d" % [attacker.get_instance_id(), _next_seq]
	_next_seq += 1
	_slugs[key] = slug
	# Place once on spawn so the first frame doesn't render a stale
	# transform (the cube defaults to the origin until oriented).
	_orient_slug(slug, attacker.orbit.r)


## Advance every slug's position by `sim_delta` of simulated travel.
## EarthSystem calls this from _physics_process so slug motion uses
## the same clock the simulation runs on — at high time_factor the
## slug whips across visibly fast; at time_factor=1 it crawls at
## literal 10 km/s.
func tick(sim_delta: float) -> void:
	if _slugs.is_empty() or sim_delta <= 0.0:
		return
	var advance_km := sim_delta * MUZZLE_VELOCITY_KMS
	var stale: Array[String] = []
	for key: String in _slugs.keys():
		var slug: _Slug = _slugs[key]
		# Attacker freed / dead ⇒ no muzzle to fly out of. Drop the
		# slug; the kill flash on the attacker is the relevant feedback.
		if (
			slug.attacker == null
			or not is_instance_valid(slug.attacker)
			or not slug.attacker.alive
		):
			stale.append(key)
			continue
		# Refresh the live endpoint while the target's alive; freeze
		# once it dies so the slug still has somewhere to glide to
		# (otherwise the line collapses to the attacker, which would
		# pop the slug back to the muzzle on the death frame).
		if (
			slug.target != null
			and is_instance_valid(slug.target)
			and slug.target.alive
			and slug.target.orbit_alive
		):
			slug.last_target_eci = slug.target.orbit.r
		slug.traveled_km += advance_km
		var attacker_eci: Vector3 = slug.attacker.orbit.r
		var to_target: Vector3 = slug.last_target_eci - attacker_eci
		var distance: float = to_target.length()
		if distance <= 0.0 or slug.traveled_km >= distance:
			# Arrived — pop the slug. No fade: the impact already
			# flashed via Satellite.flash_hit when fire() ran, and a
			# fade tail would smear the streak past the visual hit
			# point, which reads worse than a clean snap-off here.
			stale.append(key)
			continue
		var pos: Vector3 = attacker_eci + (to_target / distance) * slug.traveled_km
		_orient_slug(slug, pos)
	for key: String in stale:
		_despawn(key)


## Currently-active slug count. Test affordance — the visual side
## is hard to assert in headless runs, but the lifecycle bookkeeping
## isn't.
func active_slug_count() -> int:
	return _slugs.size()


## Drop every slug. Called when the operator toggles slug-render
## off, so a magazine-empty trail of slugs doesn't linger on a
## disabled visual surface. Safe to call when empty.
func clear_all() -> void:
	for key: String in _slugs.keys():
		_despawn(key)
	_slugs.clear()


func _make_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = SLUG_COLOR
	# Don't write depth so a slug behind another slug (or the kill
	# flash on the same target) doesn't fight for the depth buffer.
	# Depth-test still applies, so Earth still occludes a slug behind
	# the planet.
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return mat


func _make_instance(mat: StandardMaterial3D) -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	inst.mesh = _shared_mesh
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.scale = Vector3.ONE * SLUG_SIZE_SCENE
	add_child(inst)
	return inst


func _orient_slug(slug: _Slug, pos_eci: Vector3) -> void:
	# Cube has no orientation requirement (it's a uniform marker), so
	# just plant it at the scene-scaled ECI position. Scale was set
	# once at spawn; mutating only translation keeps _process cheap.
	if slug.inst == null:
		return
	slug.inst.position = pos_eci * Satellite.SCENE_SCALE


func _despawn(key: String) -> void:
	var slug: _Slug = _slugs.get(key)
	if slug == null:
		return
	if slug.inst != null:
		slug.inst.queue_free()
	_slugs.erase(key)
