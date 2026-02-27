class_name Earth
extends MeshInstance3D
## Rotating Earth globe with day/night textures.

const EARTH_RADIUS_KM: float = 6371.0
# Godot scene units: 1 unit = 1000 km for comfortable camera ranges
const SCALE_FACTOR: float = 1.0 / 1000.0
const VISUAL_RADIUS: float = EARTH_RADIUS_KM * SCALE_FACTOR  # ~6.371 units

var earth_phase: float = 0.0
var rotation_rate: float  # rad per sim-second


func _ready() -> void:
	# Earth rotates once per sidereal day (~86164 seconds)
	rotation_rate = TAU / 86164.0

	# Create sphere mesh
	var sphere := SphereMesh.new()
	sphere.radius = VISUAL_RADIUS
	sphere.height = VISUAL_RADIUS * 2.0
	sphere.radial_segments = 64
	sphere.rings = 32
	mesh = sphere

	_setup_material()


func _setup_material() -> void:
	var mat := ShaderMaterial.new()
	var shader := load("res://shaders/planet.gdshader") as Shader
	mat.shader = shader

	# Load textures from the existing resources
	var albedo := _load_texture("res://resources/3D/earth/4096_earth.jpg")
	var night := _load_texture("res://resources/3D/earth/4096_night_lights.jpg")
	var normal_map := _load_texture("res://resources/3D/earth/4096_normal.jpg")

	if albedo:
		mat.set_shader_parameter("albedo_texture", albedo)
	if night:
		mat.set_shader_parameter("night_texture", night)
	if normal_map:
		mat.set_shader_parameter("normal_texture", normal_map)

	mat.set_shader_parameter("normal_scale", 1.0)
	mat.set_shader_parameter("sun_direction", Vector3(1.0, 0.0, 0.0))

	material_override = mat


func _load_texture(path: String) -> ImageTexture:
	if not FileAccess.file_exists(path):
		push_warning("Texture not found: " + path)
		return null
	var img := Image.load_from_file(path)
	if img == null:
		push_warning("Failed to load texture: " + path)
		return null
	return ImageTexture.create_from_image(img)


func advance_phase(sim_delta: float) -> void:
	earth_phase += rotation_rate * sim_delta
	if earth_phase > TAU:
		earth_phase -= TAU
	rotation.y = earth_phase
