class_name Missile
extends Node3D
## An in-flight guided missile. Owns its own Keplerian orbit (set
## once at spawn from a Lambert-solved launch state) and propagates
## passively each physics tick. Detonates when it enters
## blast_radius_km of its target, when closest approach has passed
## with a sub-blast distance, when its expiry deadline elapses, or
## when its orbit decays below the body surface.
##
## Distinct from Satellite — a missile has no HP / weapons / planning
## state / surface logic. It's a lightweight entity owned by the
## MissileSpawner; CombatController doesn't see it as a targetable
## body. Anti-missile defenses (railguns / lasers shooting incoming
## missiles) are a Phase-2 extension that would surface missiles as
## targets in CombatController._collect_targetable.
##
## Lifetime: spawned by MissileSpawner; ticks once per physics frame;
## reports back true / false from tick() to indicate whether to keep
## it alive. Termination invokes the optional on_terminate callable
## so the spawner can release its target reservation.

const MassCenterOrbit = preload("res://scripts/mass_center_orbit.gd")
const OrbitalPath = preload("res://scripts/orbital_path.gd")
const SCENE_SCALE: float = 1.0 / 1000.0  # km -> scene units (matches Satellite)

# Visual constants. The missile body is rendered as a small bright
# unshaded cube so it reads against the dark scene without competing
# with satellite markers. The cube is deliberately oversized — about
# 150 km equivalent at this scene scale, far larger than a real
# missile's tens-of-metres airframe — so the operator can find an
# in-flight missile against the busy 3D scene without zooming.
# Flashing red / white at FLASH_PERIOD_SEC keeps the operator's eye
# on it; the wall-clock-driven flash also tracks consistently
# regardless of time_factor (a 1000× speed-up wouldn't strobe it
# into invisibility).
const BODY_SIDE_SCENE: float = 0.15
const BODY_COLOR_RED := Color(1.0, 0.10, 0.10)
const BODY_COLOR_WHITE := Color(1.0, 1.0, 1.0)
const FLASH_PERIOD_SEC: float = 0.2
const PATH_COLOR := Color(1.0, 0.6, 0.15, 0.7)
const PATH_LINE_WIDTH_PX: float = 1.2

# Termination reasons — surface them so tests and the spawner can
# distinguish the cases without parsing strings.
const TERM_DETONATED: int = 0
const TERM_MISSED: int = 1
const TERM_EXPIRED: int = 2
const TERM_SUBSURFACE: int = 3
const TERM_TARGET_LOST: int = 4
const TERM_PROPAGATION_FAILED: int = 5


# Orbital state. Owned by the missile; nothing else writes to it.
var orbit: MassCenterOrbit
# Weakrefs by instance_id: attacker / target may queue_free between
# spawn and detonation; we resolve to live nodes per tick.
var target_iid: int = 0
var attacker_iid: int = 0
var blast_radius_km: float = 5.0
var damage_hp: float = 100.0
var spawn_sim_time: float = 0.0
var expiry_sim_time: float = INF
# Tracks the previous tick's distance for closest-approach detection.
# INF on spawn so the first tick's "is distance growing?" check is
# always false.
var prev_distance_km: float = INF
# Last termination reason, for tests / debugging. -1 = still alive.
var last_termination: int = -1
# Optional callback fired when the missile terminates (detonate,
# expire, subsurface, target lost). Used by MissileSpawner to release
# the target-reservation map and despawn the node. Always fires
# exactly once per missile lifetime — guarded by _terminated below.
var on_terminate: Callable = Callable()
var _terminated: bool = false

# Visual children — allocated in _ready when the missile enters the
# scene tree. Stay null in headless tests that never add the missile
# to a tree; the tick / proximity / damage paths null-check before
# touching them.
var _body: MeshInstance3D = null
var _body_mat: StandardMaterial3D = null
var _path: OrbitalPath = null


func _ready() -> void:
	# Body: small unshaded cube. One MeshInstance3D + one
	# StandardMaterial3D allocated once at spawn — within CLAUDE.md's
	# "no per-frame allocation" rule, since each missile lives many
	# physics ticks.
	_body = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE * BODY_SIDE_SCENE
	_body.mesh = box
	_body_mat = StandardMaterial3D.new()
	_body_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_body_mat.albedo_color = BODY_COLOR_RED
	_body.material_override = _body_mat
	add_child(_body)

	_path = OrbitalPath.new()
	add_child(_path)
	# _path uses a setter so the assignment goes through the
	# ShaderMaterial uniform once it's ready.
	_path.color = PATH_COLOR
	_path.line_width_px = PATH_LINE_WIDTH_PX
	if orbit != null:
		_path.update_orbit(orbit)
		_sync_body_position()


# Flashing red / white driven by wall-clock time so the colour cycle
# stays consistent regardless of time_factor — at 1000× speed the
# missile would otherwise strobe so fast it'd look static. Wall-clock
# also means the cycle survives planning-mode pause: the operator
# still sees the missile threatening even while the sim is frozen.
func _process(_delta: float) -> void:
	if _terminated or _body_mat == null:
		return
	var phase: int = int(Time.get_ticks_msec() / int(FLASH_PERIOD_SEC * 1000.0))
	_body_mat.albedo_color = (
		BODY_COLOR_WHITE if (phase % 2) == 0 else BODY_COLOR_RED
	)


## Configure missile state at spawn time. Call BEFORE add_child() so
## _ready picks up the right orbit and renders the initial path. The
## spawner does it that way; tests can also call this on an
## un-added Missile and just inspect orbit / state without rendering.
##
## target / attacker typed as Object so both Satellite (Node3D) and
## test stubs (RefCounted) can flow in. get_instance_id lives on
## Object, so the iid resolution path doesn't care which.
func configure(
	new_orbit: MassCenterOrbit,
	target: Object,
	attacker: Object,
	blast_radius: float,
	damage: float,
	sim_time: float,
	expiry: float,
) -> void:
	orbit = new_orbit
	target_iid = target.get_instance_id() if target != null else 0
	attacker_iid = attacker.get_instance_id() if attacker != null else 0
	blast_radius_km = blast_radius
	damage_hp = damage
	spawn_sim_time = sim_time
	expiry_sim_time = expiry
	prev_distance_km = INF
	last_termination = -1
	_terminated = false


## Advance one physics tick. Returns true to remain alive, false if
## the missile terminated (detonated, missed, expired, target lost,
## sub-surface, or propagator failure). On false, on_terminate has
## already fired and the spawner should despawn the node.
func tick(sim_delta: float, sim_time: float) -> bool:
	if _terminated:
		return false
	if orbit == null:
		terminate(TERM_PROPAGATION_FAILED)
		return false

	if not orbit.propagate(sim_delta):
		terminate(TERM_PROPAGATION_FAILED)
		return false

	# Sub-surface: missile flew into the body. No damage to target
	# (it's far away); just terminate.
	if orbit.norm_r < MassCenterOrbit.BODY_RADIUS_KM:
		terminate(TERM_SUBSURFACE)
		return false

	# Expiry: TOF + slack window elapsed without detonation. Means
	# the Lambert solution didn't materialise an intercept (target
	# may have maneuvered or been killed mid-flight) — give up.
	if sim_time >= expiry_sim_time:
		terminate(TERM_EXPIRED)
		return false

	var target = _live_target()
	if target == null:
		terminate(TERM_TARGET_LOST)
		return false

	var d: float = (target.orbit.r - orbit.r).length()

	# Primary detonation: inside the proximity fuze radius.
	if d < blast_radius_km:
		_apply_damage(target)
		terminate(TERM_DETONATED)
		return false

	# Secondary detonation: closest approach has passed (distance is
	# now increasing). If the previous tick was already inside the
	# blast radius this should have been caught above, but the
	# closest-approach-passed check is a backstop for the rare case
	# where the minimum distance occurs between physics ticks.
	if d > prev_distance_km:
		if prev_distance_km < blast_radius_km:
			_apply_damage(target)
			terminate(TERM_DETONATED)
		else:
			terminate(TERM_MISSED)
		return false

	prev_distance_km = d
	_sync_body_position()
	return true


## Resolve the target instance from its iid. Returns null if the
## target was queue_free'd, killed (`alive == false`), or had its
## orbit invalidated mid-flight.
func _live_target():
	if target_iid == 0:
		return null
	var t = instance_from_id(target_iid)
	if t == null or not is_instance_valid(t):
		return null
	if not t.alive:
		return null
	if not t.orbit_alive:
		return null
	return t


func _live_attacker():
	if attacker_iid == 0:
		return null
	var a = instance_from_id(attacker_iid)
	if a == null or not is_instance_valid(a):
		return null
	return a


func _apply_damage(target) -> void:
	if target == null or not target.has_method("take_damage"):
		return
	target.take_damage(damage_hp, _live_attacker())


func _sync_body_position() -> void:
	if _body == null:
		return
	_body.position = orbit.r * SCENE_SCALE


## Mark this missile as terminated. Called internally from tick when
## an end condition fires; can also be called externally (by tests or
## by MissileSpawner.clear_all) to force a quiet termination without
## damage application. Fires on_terminate exactly once — subsequent
## calls are no-ops, so the spawner can defensively call this on
## already-terminated entries.
func terminate(reason: int) -> void:
	if _terminated:
		return
	_terminated = true
	last_termination = reason
	if on_terminate.is_valid():
		on_terminate.call()
