class_name Earth
extends MeshInstance3D
## Rotating Earth globe. Loads textures via Godot's import pipeline
## (compressed, mipmapped, GPU-resident) instead of decoding 4K JPEGs at
## runtime — that alone consumed ~200 MB of VRAM in the previous port.

const EARTH_RADIUS_KM: float = 6371.0
const SCENE_SCALE: float = 1.0 / 1000.0
const VISUAL_RADIUS: float = EARTH_RADIUS_KM * SCENE_SCALE  # ~6.371 units

# Sidereal day in seconds.
const SIDEREAL_DAY_SECONDS: float = 86164.0

@export var albedo_path: String = "res://resources/3D/earth/4096_earth.jpg"
@export var night_path: String = "res://resources/3D/earth/4096_night_lights.jpg"
@export var normal_path: String = "res://resources/3D/earth/4096_normal.jpg"
@export var clouds_path: String = "res://resources/3D/earth/4096_clouds.jpg"

var earth_phase: float = 0.0
var rotation_rate: float

# SphereMesh's poles sit on local Y, but the world is Z-up (the
# orbital-mechanics convention used throughout the project). This basis
# rotates the mesh once so its north pole points at +Z; daily rotation is
# then composed on top of it.
const POLE_ALIGN := Basis(Vector3(1.0, 0.0, 0.0), PI / 2.0)

# Earth's axial tilt (obliquity of the ecliptic): 23.5° away from the
# world Z axis. Applied last so the daily spin happens about the tilted
# pole, while the sun direction (a shader uniform) stays unchanged —
# the asymmetric illumination this produces is the seasonal effect.
const AXIAL_TILT_RAD: float = 23.5 * PI / 180.0
const AXIAL_TILT := Basis(Vector3(1.0, 0.0, 0.0), AXIAL_TILT_RAD)


func _ready() -> void:
	rotation_rate = TAU / SIDEREAL_DAY_SECONDS

	var sphere := SphereMesh.new()
	sphere.radius = VISUAL_RADIUS
	sphere.height = VISUAL_RADIUS * 2.0
	sphere.radial_segments = 64
	sphere.rings = 32
	mesh = sphere

	transform.basis = AXIAL_TILT * POLE_ALIGN
	_setup_material()


func _setup_material() -> void:
	var shader := load("res://shaders/planet.gdshader") as Shader
	if shader == null:
		# Fall back to a plain unshaded material if the shader is missing
		# (e.g. running headless tests without resources imported).
		var fallback := StandardMaterial3D.new()
		fallback.albedo_color = Color(0.2, 0.4, 0.8)
		material_override = fallback
		return

	var mat := ShaderMaterial.new()
	mat.shader = shader

	var albedo := _load_texture(albedo_path)
	var night := _load_texture(night_path)
	var normal_map := _load_texture(normal_path)
	var clouds := _load_texture(clouds_path)

	if albedo:
		mat.set_shader_parameter("albedo_texture", albedo)
	if night:
		mat.set_shader_parameter("night_texture", night)
	if normal_map:
		mat.set_shader_parameter("normal_texture", normal_map)
	if clouds:
		mat.set_shader_parameter("clouds_texture", clouds)
	mat.set_shader_parameter("sun_direction", Vector3(1.0, 0.0, 0.0))

	material_override = mat


func _load_texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		push_warning("Texture not found: %s" % path)
		return null
	return load(path) as Texture2D


func advance_phase(sim_delta: float) -> void:
	earth_phase = fposmod(earth_phase + rotation_rate * sim_delta, TAU)
	# Composition order (right-to-left): align mesh poles to local Z,
	# spin daily about that local Z, then tilt the whole thing 23.5° so
	# the spin axis tilts away from world Z but the sun direction
	# (world frame) is untouched.
	var daily := Basis(Vector3(0.0, 0.0, 1.0), earth_phase)
	transform.basis = AXIAL_TILT * daily * POLE_ALIGN
