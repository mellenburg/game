class_name Earth
extends MeshInstance3D
## Rotating planet globe. Originally Earth-only; now drives whichever
## body the player picked on the Campaign tab. The class name is
## retained for the rest of the codebase (which references `$Earth`),
## but the radius, sidereal day, axial tilt, and texture set all come
## from the active CelestialBody record — adding a new body needs no
## changes to this script.
##
## All bodies feed planet.gdshader. The texture binder iterates the
## body's albedo / night / normal / clouds paths; any path the body
## leaves blank gets a 1×1 black placeholder so the corresponding
## branch in the shared shader (city lights, cloud overlay) collapses
## to no contribution.

const EarthOrbit = preload("res://scripts/earth_orbit.gd")
const CelestialBody = preload("res://scripts/celestial_body.gd")

# Scene-units-per-km. Sun.gd reads this to convert km offsets into the
# scene's display scale, so it stays public.
const SCENE_SCALE: float = 1.0 / 1000.0

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
	body = CelestialBody.active(get_tree())
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
	_bind_planet_textures(mat)
	mat.set_shader_parameter("sun_direction", Vector3(1.0, 0.0, 0.0))
	material_override = mat


# Walk the body's four texture paths and bind each to the matching
# shader sampler. An empty string means "this body has no such map";
# we substitute a 1×1 black placeholder so the shader's corresponding
# branch contributes nothing (no city lights on Mars, no cloud band on
# bodies without an atmosphere). Adding a new body therefore requires
# zero changes to this method — it just reads what the body record
# provides.
func _bind_planet_textures(mat: ShaderMaterial) -> void:
	var slots := [
		["albedo_texture", body.albedo_path],
		["night_texture", body.night_path],
		["normal_texture", body.normal_path],
		["clouds_texture", body.clouds_path],
	]
	var black: ImageTexture = null
	for slot in slots:
		var sampler: String = slot[0]
		var path: String = slot[1]
		var tex: Texture2D = null
		if path != "" and ResourceLoader.exists(path):
			tex = load(path) as Texture2D
		if tex == null:
			if black == null:
				black = _make_solid_texture(Color(0.0, 0.0, 0.0))
			tex = black
		mat.set_shader_parameter(sampler, tex)


func _make_solid_texture(color: Color) -> ImageTexture:
	var img := Image.create(1, 1, false, Image.FORMAT_RGB8)
	img.set_pixel(0, 0, color)
	return ImageTexture.create_from_image(img)


func advance_phase(sim_delta: float) -> void:
	earth_phase = fposmod(earth_phase + rotation_rate * sim_delta, TAU)
	# Composition order (right-to-left): align mesh poles to local Z,
	# spin daily about that local Z, then tilt the whole thing by the
	# body's obliquity so the spin axis tilts away from world Z but
	# the sun direction (world frame) is untouched.
	var daily := Basis(Vector3(0.0, 0.0, 1.0), earth_phase)
	transform.basis = _axial_tilt_basis() * daily * POLE_ALIGN
