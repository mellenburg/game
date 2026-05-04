class_name Earth
extends MeshInstance3D
## Rotating planet globe. Originally Earth-only; now drives whichever
## body the player picked on the Campaign tab. The class name is
## retained for the rest of the codebase (which references `$Earth`),
## but the textures, radius, sidereal day, and axial tilt all come
## from the active CelestialBody.
##
## Both Earth and Mars feed planet.gdshader. The albedo set comes off
## disk via Godot's import pipeline: Earth ships day / night / normal /
## clouds JPEGs in resources/3D/earth/, Mars ships a single global
## albedo (NASA Photojournal PIA02066) in resources/3D/mars/. The
## night-lights / clouds / normal samplers are bound to a 1×1 black
## image on Mars so the shader's day/night/cloud branches collapse to
## pure day-side albedo (Mars has no city lights, no Earth-class cloud
## bands, and the source map already has its terrain detail baked in).

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
# Mars albedo. No companion night / clouds / normal — Mars has no city
# lights, its atmosphere is too thin for an Earth-style cloud band,
# and the source map already bakes in shaded relief.
const MARS_ALBEDO_PATH := "res://resources/3D/mars/2304_mars.jpg"

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
	var shader := load("res://shaders/planet.gdshader") as Shader
	if shader == null:
		# Fall back to a plain unshaded material if the shader is missing
		# (e.g. running headless tests without resources imported).
		var fallback := StandardMaterial3D.new()
		fallback.albedo_color = body.fallback_color
		material_override = fallback
		return

	var mat := ShaderMaterial.new()
	mat.shader = shader
	match body.texture_set:
		CelestialBody.TEXTURES_MARS:
			_bind_mars_textures(mat)
		_:
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


# Mars: bind the NASA albedo to the day-side sampler, and a 1×1 black
# placeholder to the night and clouds samplers so those branches in the
# shared planet shader add nothing (no city lights to draw, no Earth-
# style cloud band to overlay). The normal_texture sampler is declared
# in the shader but never sampled in the current planet.gdshader, so
# leaving it unbound is safe.
func _bind_mars_textures(mat: ShaderMaterial) -> void:
	var albedo := _load_texture(MARS_ALBEDO_PATH)
	if albedo:
		mat.set_shader_parameter("albedo_texture", albedo)
	var black := _make_solid_texture(Color(0.0, 0.0, 0.0))
	mat.set_shader_parameter("night_texture", black)
	mat.set_shader_parameter("clouds_texture", black)


func _make_solid_texture(color: Color) -> ImageTexture:
	var img := Image.create(1, 1, false, Image.FORMAT_RGB8)
	img.set_pixel(0, 0, color)
	return ImageTexture.create_from_image(img)


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
