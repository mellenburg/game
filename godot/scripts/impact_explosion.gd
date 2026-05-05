class_name ImpactExplosion
extends Node3D
## Short-lived yellow-orange sphere that grows then shrinks to mark a
## meteorite ground impact. Self-frees when the animation completes.
##
## Spawned per impact (rare event — at most a handful per storm), so
## the per-instance mesh + material allocation is fine here. Position
## is set in world ECI coordinates and not parented to the rotating
## Earth: the visual is brief enough that planet rotation is invisible.

const Satellite = preload("res://scripts/satellite.gd")
const MeteorPhysics = preload("res://scripts/meteor_physics.gd")

# Wall-clock duration. Kept short so high time_factor doesn't let the
# explosion drift visibly off the rotating surface.
const DURATION: float = 0.5
# Peak sphere radius is now derived from the impacting body's mass via
# MeteorPhysics.damage_radii_km — the moderate-tier blast radius
# anchors the visual so the 3D explosion roughly matches the
# corresponding ring on the impact map. Multiplied by VISUAL_GAIN
# because real-world km radii (Tunguska ~60 km moderate) are tiny
# next to Earth's 6371 km, and a faithful-scale explosion would be
# invisible from the default camera distance.
const VISUAL_GAIN: float = 4.0
# Floor / ceiling on the peak radius so a sub-threshold impact
# (which shouldn't render in the first place — EarthSystem gates
# spawn) still produces a recognisable speck if it ever leaks
# through, and an extinction-class impactor doesn't fill the entire
# globe with a single white ball.
const MIN_RADIUS_KM: float = 80.0
const MAX_RADIUS_KM: float = 4000.0
const COLOR_CORE := Color(1.0, 0.7, 0.15)

# Per-instance peak radius, set by the spawner before _ready so callers
# can size each explosion to the impacting body's mass.
var peak_radius_km: float = MIN_RADIUS_KM

var _elapsed: float = 0.0
var _mesh_inst: MeshInstance3D
var _mat: StandardMaterial3D


## Map an impactor's mass (kg) onto a peak-radius value, using the
## moderate-tier damage radius from MeteorPhysics scaled for visual
## readability against Earth.
static func mass_to_peak_radius_km(mass_kg: float) -> float:
	var radii := MeteorPhysics.damage_radii_km(mass_kg)
	var raw := float(radii["moderate"]) * VISUAL_GAIN
	return clampf(raw, MIN_RADIUS_KM, MAX_RADIUS_KM)


func _ready() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 16
	sphere.rings = 8

	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = COLOR_CORE
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED

	_mesh_inst = MeshInstance3D.new()
	_mesh_inst.mesh = sphere
	_mesh_inst.material_override = _mat
	_mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh_inst.scale = Vector3.ZERO
	add_child(_mesh_inst)


## Set the world ECI position (in km) at which the impact is rendered.
func set_impact_position(eci_km: Vector3) -> void:
	position = eci_km * Satellite.SCENE_SCALE


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= DURATION:
		queue_free()
		return
	var t := _elapsed / DURATION
	# Bell-curve pulse: 0 → 1 → 0 over the lifetime.
	var pulse := sin(t * PI)
	var radius_units: float = peak_radius_km * Satellite.SCENE_SCALE * pulse
	_mesh_inst.scale = Vector3(radius_units, radius_units, radius_units)
	var color := COLOR_CORE
	color.a = pulse
	_mat.albedo_color = color
