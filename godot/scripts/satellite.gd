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

const SCENE_SCALE: float = 1.0 / 1000.0
const DEFAULT_R := Vector3(-6045.0, -3490.0, 2500.0)
const DEFAULT_V := Vector3(-3.56, 6.618, 2.533)
const DELTA_V_MAGNITUDE: float = 0.050
const COLOR_SELECTED := Color(0.2, 1.0, 0.2)
const COLOR_PLAYER := Color(0.4, 0.6, 1.0)
const COLOR_ENEMY := Color(1.0, 0.35, 0.35)

const MAX_HP: float = 100.0

var orbit: EarthOrbit
var selected: bool = false
var raw_maneuver := Vector3.ZERO
var did_maneuver: bool = false
var orbit_alive: bool = true

var team: int = TEAM_PLAYER
var hp: float = MAX_HP
var alive: bool = true
var weapon: Weapon = null  # Null for unarmed units (e.g. enemies).

var _marker: MeshInstance3D
var _marker_mat: StandardMaterial3D
var path_visual: OrbitalPath


func _init() -> void:
	orbit = EarthOrbit.new(DEFAULT_R, DEFAULT_V)
	weapon = LaserWeapon.new()


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


func select() -> void:
	selected = true
	_apply_color()


func unselect() -> void:
	selected = false
	_apply_color()


func set_maneuver(input: Vector3) -> void:
	raw_maneuver = input
	did_maneuver = input.length_squared() > 0.0


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
	var ok: bool
	if did_maneuver:
		ok = orbit.relative_maneuver(get_current_maneuver(), delta_time)
	else:
		ok = orbit.propagate(delta_time)
	did_maneuver = false
	raw_maneuver = Vector3.ZERO
	if not ok:
		orbit_alive = false
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
	path_visual.update_orbit(orbit)


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
	hp = other.hp
	alive = other.alive
	# Mirror armed-vs-unarmed so the planning HUD doesn't show an
	# energy bar for an enemy preview (clones get a fresh weapon in
	# _init that we'd otherwise leave dangling).
	if other.weapon == null:
		weapon = null
	if is_inside_tree():
		_apply_color()
		_sync_marker_position()


func _sync_marker_position() -> void:
	if _marker == null:
		return
	_marker.position = orbit.r * SCENE_SCALE


func _base_color() -> Color:
	return COLOR_ENEMY if team == TEAM_ENEMY else COLOR_PLAYER


func _apply_color() -> void:
	if _marker_mat == null:
		return
	_marker_mat.albedo_color = COLOR_SELECTED if selected else _base_color()


func _hide_visuals() -> void:
	if _marker:
		_marker.visible = false
	if path_visual:
		path_visual.visible = false
