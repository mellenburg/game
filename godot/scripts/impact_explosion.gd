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

# Wall-clock duration. Kept short so high time_factor doesn't let the
# explosion drift visibly off the rotating surface.
const DURATION: float = 0.5
# Peak sphere radius, in km, for an impact at the reference HP. Big
# enough to read against Earth's 6371 km radius globe at typical camera
# distance, small enough to look like a point impact rather than a
# continent. The actual peak radius scales with the impactor's HP at
# the moment of contact (see hp_to_peak_radius_km below) so a glancing
# hit by a battered fragment reads visibly smaller than a fresh boss.
const PEAK_RADIUS_KM: float = 300.0
# HP scaling envelope. Same log-scale idiom Satellite uses for enemy-
# path styling — HP_REF_MIN anchors the smallest meteorite mass class
# at 1.0x and HP_LOG_DECADES sets the high end (HP_REF_MIN * 10^N maps
# to MAX_SCALE). Floor + ceiling chosen so a 1-HP straggler still
# reads as a recognisable splash and a 10000-HP boss feels distinct
# without flooding the globe.
const HP_REF_MIN: float = 10.0
const HP_LOG_DECADES: float = 3.0
const MIN_SCALE: float = 0.4
const MAX_SCALE: float = 2.0
const COLOR_CORE := Color(1.0, 0.7, 0.15)

# Per-instance peak radius, set by the spawner before _ready so callers
# can size each explosion to the impacting body's remaining HP.
var peak_radius_km: float = PEAK_RADIUS_KM

var _elapsed: float = 0.0
var _mesh_inst: MeshInstance3D
var _mat: StandardMaterial3D


## Map an impactor's HP at the moment of contact onto a peak-radius
## value, using the same log-decade envelope as the enemy-path styling.
static func hp_to_peak_radius_km(hp: float) -> float:
	var ratio := maxf(hp, HP_REF_MIN) / HP_REF_MIN
	var hp_norm := clampf(
		log(ratio) / log(pow(10.0, HP_LOG_DECADES)), 0.0, 1.0
	)
	return PEAK_RADIUS_KM * lerpf(MIN_SCALE, MAX_SCALE, hp_norm)


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
