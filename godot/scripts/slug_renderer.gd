class_name SlugRenderer
extends Node3D
## 3D railgun-slug visuals — a moving projectile, in contrast to the
## BeamRenderer's instant attacker→target line. Spawned by
## CombatController on a successful railgun fire when the operator has
## slug-render enabled (toggle: `U`); when disabled the railgun routes
## back to BeamRenderer so the visual matches the laser.
##
## Each slug travels in *sim time* at the weapon's muzzle velocity
## (RailgunWeapon.MUZZLE_VELOCITY_M_S) — physics-honest motion, so a
## 500 km LEO engagement at default time_factor=500 reads as a quick
## tracer flash, while a 50 000 km cross-shell shot stretches into a
## visible glide. The simulation has already applied damage at fire-
## time; the slug visual is purely cosmetic.
##
## Lifecycle:
##   - register_fire spawns a slug with origin / direction / distance
##     captured at the moment of fire.
##   - Each tick, advance the slug by (sim_time - fire_sim_time) ×
##     muzzle velocity. Despawn once the slug has covered its launch
##     distance (it would have arrived).
##   - Attacker dying despawns its slugs immediately (the simulation
##     side has no follow-up shots to render).
##
## A single CylinderMesh is shared across every slug; per-slug
## StandardMaterial3D is allocated once at spawn so _process only
## mutates transform + alpha (see CLAUDE.md "cache meshes and
## materials").

const Satellite = preload("res://scripts/satellite.gd")
const RailgunWeapon = preload("res://scripts/weapons/railgun_weapon.gd")

# Slug muzzle velocity in km / sim-second. Stored as a Satellite-frame
# constant so the kinematic helpers below don't need to know about
# RailgunWeapon's m/s convention. Equal to MUZZLE_VELOCITY_M_S × 1e-3.
const MUZZLE_VELOCITY_KMS: float = RailgunWeapon.MUZZLE_VELOCITY_M_S * 1.0e-3

# Visual: a short cylindrical streak whose leading edge is the slug's
# current sim-time position. The trail length is in scene units
# (1 unit = 1000 km), sized so even a fast tracer reads as a streak
# rather than a point — at the camera's typical 38-unit orbit, 0.6
# units spans ~25 px, comparable to a tracer round on a war film.
const TRAIL_LENGTH_SCENE: float = 0.6
const SLUG_RADIUS_SCENE: float = 0.04
# Hot orange-yellow with a brighter core. The unshaded material reads
# as self-luminous against dark space; against the lit Earth surface
# it stands out by its saturation.
const SLUG_COLOR := Color(1.0, 0.85, 0.45)
# Wall-clock fade once the slug "arrives" at its target so the streak
# doesn't snap off mid-screen. Short — the impact already flashed via
# Satellite.flash_hit when fire() ran.
const FADE_SECONDS: float = 0.08

var _shared_mesh: CylinderMesh
# key "<attacker_iid>:<seq>" → _Slug. seq increments per-attacker so
# rapid back-to-back shots don't collide on the dictionary key.
var _slugs: Dictionary = {}
var _next_seq: int = 0
# Latest sim-time the renderer was ticked with. Updated each
# `_process_at_sim_time` call so register_fire can stamp new slugs
# with the same clock the existing fleet runs on.
var _sim_time: float = 0.0


class _Slug:
	var attacker_iid: int = 0
	# ECI km — captured at fire time. The origin doesn't track the
	# attacker because a slug has left the barrel: it carries on
	# along its launch ray regardless of subsequent attacker motion.
	var origin_eci: Vector3 = Vector3.ZERO
	# Unit vector in ECI km. Same reason as origin — frozen at fire.
	var direction_eci: Vector3 = Vector3.ZERO
	# Total km the slug must cover to "arrive". Computed at fire time
	# from the snapshot target position; the slug despawns once it
	# has covered this distance.
	var distance_km: float = 0.0
	var fire_sim_time: float = 0.0
	# Wall-clock instant at which the slug "arrived" (started fading).
	# 0.0 until arrival; once non-zero the slug fades over FADE_SECONDS
	# wall and then despawns.
	var arrived_wall: float = 0.0
	var inst: MeshInstance3D = null
	var mat: StandardMaterial3D = null


func _ready() -> void:
	_shared_mesh = CylinderMesh.new()
	# Unit cylinder: per-slug transform stretches Y to TRAIL_LENGTH and
	# X/Z to SLUG_RADIUS. Same shared-mesh pattern as BeamRenderer.
	_shared_mesh.height = 1.0
	_shared_mesh.top_radius = 1.0
	_shared_mesh.bottom_radius = 1.0
	_shared_mesh.radial_segments = 8
	_shared_mesh.rings = 1


## Distance (km) the slug has traveled since fire, given the current
## sim-clock reading. Pure helper for tests + the per-frame placement.
## Negative gaps clamp to zero (paranoia — sim_time only advances).
static func traveled_km(now_sim_time: float, fire_sim_time: float) -> float:
	return maxf(0.0, (now_sim_time - fire_sim_time) * MUZZLE_VELOCITY_KMS)


## Whether a slug fired at `fire_sim_time` over `distance_km` has
## arrived at its target by `now_sim_time`. Used to gate the "stop
## advancing, start fading" transition.
static func has_arrived(
	now_sim_time: float, fire_sim_time: float, distance_km: float,
) -> bool:
	return traveled_km(now_sim_time, fire_sim_time) >= distance_km


## Spawn a slug from `attacker` aimed at `target`. CombatController
## calls this when railgun fire() succeeded *and* slug-render is
## enabled. Origin / direction / distance freeze at this instant —
## the slug carries on along its launch ray regardless of subsequent
## attacker motion, which is what a real kinetic projectile does.
func register_fire(attacker: Satellite, target: Satellite, sim_time: float) -> void:
	if attacker == null or target == null:
		return
	var origin: Vector3 = attacker.orbit.r
	var to_target: Vector3 = target.orbit.r - origin
	var distance: float = to_target.length()
	if distance <= 0.0:
		return
	var slug := _Slug.new()
	slug.attacker_iid = attacker.get_instance_id()
	slug.origin_eci = origin
	slug.direction_eci = to_target / distance
	slug.distance_km = distance
	slug.fire_sim_time = sim_time
	slug.mat = _make_material()
	slug.inst = _make_instance(slug.mat)
	var key := "%d:%d" % [slug.attacker_iid, _next_seq]
	_next_seq += 1
	_slugs[key] = slug
	# Place once on spawn so the first frame doesn't render a stale
	# transform (the cylinder defaults to the origin until oriented).
	_orient_slug(slug, 0.0, 1.0)


## Advance every slug's position to `sim_time`. EarthSystem calls
## this from _physics_process so slug motion uses the same clock the
## simulation runs on — at high time_factor the slug whips across
## visibly fast; at time_factor=1 it crawls at literal 10 km/s.
func tick(sim_time: float) -> void:
	_sim_time = sim_time
	if _slugs.is_empty():
		return
	var now_wall := _wall_now()
	var stale: Array[String] = []
	for key: String in _slugs.keys():
		var slug: _Slug = _slugs[key]
		# Attacker freed / dead ⇒ no follow-up shots to render. Fading
		# isn't worth tracking here because the kill flash on the
		# attacker is the relevant feedback.
		var attacker := instance_from_id(slug.attacker_iid) as Satellite
		if attacker == null or not is_instance_valid(attacker) or not attacker.alive:
			stale.append(key)
			continue
		var traveled := traveled_km(sim_time, slug.fire_sim_time)
		var progress := clampf(traveled / slug.distance_km, 0.0, 1.0)
		var alpha := 1.0
		if traveled >= slug.distance_km:
			# Arrived — start the fade. Stamp arrival wall-time once so
			# subsequent frames use a stable reference for the fade ramp.
			if slug.arrived_wall <= 0.0:
				slug.arrived_wall = now_wall
			var since_arrived := now_wall - slug.arrived_wall
			if since_arrived >= FADE_SECONDS:
				stale.append(key)
				continue
			alpha = 1.0 - (since_arrived / FADE_SECONDS)
			progress = 1.0
		_orient_slug(slug, progress, alpha)
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
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Don't write depth so overlapping slugs don't fight each other.
	# Depth-test still applies, so Earth still occludes a slug behind
	# the planet.
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return mat


func _make_instance(mat: StandardMaterial3D) -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	inst.mesh = _shared_mesh
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(inst)
	return inst


func _orient_slug(slug: _Slug, progress: float, alpha: float) -> void:
	# Leading edge: where the slug currently is. The trail extends
	# TRAIL_LENGTH_SCENE units behind the lead along the launch ray.
	# Both ends are drawn even when the trail would clip behind the
	# origin (early frames) — visually the streak just grows out of
	# the muzzle, which reads as a launch flash.
	var lead_eci: Vector3 = slug.origin_eci + slug.direction_eci * (
		progress * slug.distance_km
	)
	var lead := lead_eci * Satellite.SCENE_SCALE
	var tail := lead - slug.direction_eci * TRAIL_LENGTH_SCENE
	var center := (lead + tail) * 0.5
	var dir := lead - tail
	var length := dir.length()
	if length < 1.0e-6:
		slug.inst.visible = false
		return
	slug.inst.visible = true
	# CylinderMesh is local-Y aligned; same transform pattern as
	# BeamRenderer._orient_beam — build a basis whose Y column is the
	# slug direction, then stretch each axis by the desired scale.
	var y_axis := dir / length
	var ref_axis: Vector3 = (
		Vector3.UP if absf(y_axis.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	)
	var x_axis := ref_axis.cross(y_axis).normalized()
	var z_axis := x_axis.cross(y_axis).normalized()
	slug.inst.transform = Transform3D(
		Basis(
			x_axis * SLUG_RADIUS_SCENE,
			y_axis * length,
			z_axis * SLUG_RADIUS_SCENE,
		),
		center,
	)
	var c := SLUG_COLOR
	c.a = alpha
	slug.mat.albedo_color = c


func _despawn(key: String) -> void:
	var slug: _Slug = _slugs.get(key)
	if slug == null:
		return
	if slug.inst != null:
		slug.inst.queue_free()
	_slugs.erase(key)


func _wall_now() -> float:
	return Time.get_ticks_msec() / 1000.0
