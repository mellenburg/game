class_name Earth
extends MeshInstance3D
## Rotating planet globe. Originally Earth-only; now drives whichever
## body the player picked on the Campaign tab. The class name is
## retained for the rest of the codebase (which references `$Earth`),
## but the textures, radius, sidereal day, and axial tilt all come
## from the active CelestialBody.
##
## Earth uses Godot's import pipeline for the day / night / normal /
## clouds JPEGs against planet.gdshader. Mars has no on-disk textures
## (the build environment is offline and the repo ships no Mars set);
## its surface is rendered by mars_planet.gdshader, which paints the
## globe in-fragment from layered noise. Both shaders share the same
## sun_direction uniform contract so the SunLight node doesn't care
## which body is up.

const EarthOrbit = preload("res://scripts/earth_orbit.gd")
const CelestialBody = preload("res://scripts/celestial_body.gd")

# Scene-units-per-km. Sun.gd reads this to convert km offsets into the
# scene's display scale, so it stays public.
const SCENE_SCALE: float = 1.0 / 1000.0

# Earth texture paths used when body.texture_set is TEXTURES_EARTH.
@export var albedo_path: String = "res://resources/3D/earth/4096_earth.jpg"
@export var night_path: String = "res://resources/3D/earth/4096_night_lights.jpg"
@export var normal_path: String = "res://resources/3D/earth/4096_normal.jpg"
@export var clouds_path: String = "res://resources/3D/earth/4096_clouds.jpg"

var earth_phase: float = 0.0
var rotation_rate: float
# Active body. Resolved in _ready from the menu's stage selection;
# defaults to Earth when no PlayerLoadout autoload is reachable.
var body: CelestialBody

# SphereMesh's poles sit on local Y, but the world is Z-up (the
# orbital-mechanics convention used throughout the project). This basis
# rotates the mesh once so its north pole points at +Z; daily rotation is
# then composed on top of it.
const POLE_ALIGN := Basis(Vector3(1.0, 0.0, 0.0), PI / 2.0)


func _ready() -> void:
	body = _resolve_body()
	rotation_rate = TAU / body.sidereal_day_s

	var visual_radius := body.radius_km * SCENE_SCALE
	var sphere := SphereMesh.new()
	sphere.radius = visual_radius
	sphere.height = visual_radius * 2.0
	sphere.radial_segments = 64
	sphere.rings = 32
	mesh = sphere

	transform.basis = _axial_tilt_basis() * POLE_ALIGN
	_setup_material()


# Pull the active CelestialBody from the player's stage selection.
# Returns Earth when PlayerLoadout isn't reachable (headless tests,
# direct main-scene boot from the editor).
func _resolve_body() -> CelestialBody:
	var tree := get_tree()
	if tree == null:
		return CelestialBody.make_earth()
	var loadout := tree.root.get_node_or_null("PlayerLoadout")
	if loadout == null:
		return CelestialBody.make_earth()
	var stage_id: String = String(loadout.selected_stage_id)
	return CelestialBody.for_stage(stage_id)


func _axial_tilt_basis() -> Basis:
	# Compose tilt about the world X axis the same way the original
	# Earth code did — only the magnitude changes per body. Applied
	# last so the daily spin happens about the tilted pole, while the
	# sun direction (a shader uniform) stays unchanged.
	return Basis(Vector3(1.0, 0.0, 0.0), body.axial_tilt_rad)


func _setup_material() -> void:
	# Pick the shader and bindings keyed off the active body. Earth's
	# day-side, night-lights, normal, and cloud JPEGs feed planet.gdshader;
	# Mars uses the procedural mars_planet.gdshader (the build environment
	# is offline and the repo has no Mars textures, so the surface is
	# painted in-fragment from layered noise) and binds nothing.
	var shader_path := "res://shaders/planet.gdshader"
	if body.texture_set == CelestialBody.TEXTURES_MARS_PROCEDURAL:
		shader_path = "res://shaders/mars_planet.gdshader"
	var shader := load(shader_path) as Shader
	if shader == null:
		# Fall back to a plain unshaded material if the shader is missing
		# (e.g. running headless tests without resources imported).
		var fallback := StandardMaterial3D.new()
		fallback.albedo_color = body.fallback_color
		material_override = fallback
		return

	var mat := ShaderMaterial.new()
	mat.shader = shader
	if body.texture_set == CelestialBody.TEXTURES_EARTH:
		_bind_earth_textures(mat)
	mat.set_shader_parameter("sun_direction", Vector3(1.0, 0.0, 0.0))
	material_override = mat


func _bind_earth_textures(mat: ShaderMaterial) -> void:
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


func _load_texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		push_warning("Texture not found: %s" % path)
		return null
	return load(path) as Texture2D


func advance_phase(sim_delta: float) -> void:
	earth_phase = fposmod(earth_phase + rotation_rate * sim_delta, TAU)
	# Composition order (right-to-left): align mesh poles to local Z,
	# spin daily about that local Z, then tilt the whole thing by the
	# body's obliquity so the spin axis tilts away from world Z but
	# the sun direction (world frame) is untouched.
	var daily := Basis(Vector3(0.0, 0.0, 1.0), earth_phase)
	transform.basis = _axial_tilt_basis() * daily * POLE_ALIGN
