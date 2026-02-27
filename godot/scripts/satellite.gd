class_name Satellite
extends Node3D
## A spacecraft with orbital mechanics, visual marker, and orbit path.
## Port of satellite.cpp/h.

const SCALE: float = 1.0 / 1000.0  # km to scene units
const DEFAULT_R := Vector3(-6045.0, -3490.0, 2500.0)
const DEFAULT_V := Vector3(-3.56, 6.618, 2.533)
const DELTA_V: float = 0.050

var orbit: EarthOrbit
var selected: bool = false
var raw_maneuver := Vector3.ZERO
var did_maneuver: bool = false

var marker: MeshInstance3D
var path_visual: OrbitalPath


func _init() -> void:
	orbit = EarthOrbit.new(DEFAULT_R, DEFAULT_V)


func _ready() -> void:
	# Create cube marker for satellite position
	marker = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.15, 0.15, 0.15)
	marker.mesh = box
	add_child(marker)

	# Create orbital path visualization
	path_visual = OrbitalPath.new()
	add_child(path_visual)

	_update_visuals()


func select() -> void:
	selected = true
	_update_color()


func unselect() -> void:
	selected = false
	_update_color()


func set_maneuver(input: Vector3) -> void:
	did_maneuver = true
	raw_maneuver = input


func get_current_maneuver() -> Vector3:
	return DELTA_V * raw_maneuver


func get_r() -> Vector3:
	return orbit.r


func get_v() -> Vector3:
	return orbit.v


func get_r_scaled() -> Vector3:
	return orbit.r * SCALE


func advance_time(delta_time: float) -> void:
	if did_maneuver and raw_maneuver.length() == 0.0:
		did_maneuver = false
	if did_maneuver:
		orbit.relative_maneuver(get_current_maneuver(), delta_time)
	else:
		orbit.propagate(delta_time)
	did_maneuver = false
	_update_visuals()


func render_orbit(show_path: bool) -> void:
	if path_visual:
		path_visual.visible = show_path
		if show_path:
			path_visual.color = Color.GREEN if selected else Color.BLUE
			path_visual.update_orbit(orbit)


func clone_from(other: Satellite) -> void:
	orbit.clone_from(other.orbit)
	selected = other.selected
	raw_maneuver = other.raw_maneuver
	did_maneuver = other.did_maneuver
	_update_visuals()


func _update_visuals() -> void:
	if marker:
		marker.position = orbit.r * SCALE
	_update_color()


func _update_color() -> void:
	if not marker:
		return
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color.GREEN if selected else Color.BLUE
	marker.material_override = mat
