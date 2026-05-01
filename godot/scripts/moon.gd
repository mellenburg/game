class_name Moon
extends MeshInstance3D
## Decorative moon. Pure cosmetic — the moon does NOT perturb satellite
## orbits. Position is parametric in sim time (circular Keplerian
## approximation in a fixed inclined plane), independent of the
## propagator. When cislunar gameplay matters, swap this for a real
## third-body term inside EarthOrbit; nothing here is load-bearing.
##
## Texture is the NASA SVS "CGI Moon Kit" LROC color shaded relief
## (public domain, https://svs.gsfc.nasa.gov/4720). 1k is plenty: the
## moon subtends ~0.5° from camera distance, same as the real sky.

const SCENE_SCALE: float = 1.0 / 1000.0

# Mean lunar parameters. Distance is the Earth-Moon centre-to-centre
# semimajor axis; period is the sidereal month. Inclination is taken
# vs. the ecliptic — in this world frame the sun sits on +X with no Z
# component, so the xy-plane *is* the ecliptic; a 5.145° tilt about
# world X reproduces the moon's actual orbital plane.
const MOON_RADIUS_KM: float = 1737.4
const MOON_SEMIMAJOR_KM: float = 384400.0
const MOON_SIDEREAL_PERIOD_SEC: float = 27.321661 * 86400.0
const MOON_INCLINATION_DEG: float = 5.145

const VISUAL_RADIUS: float = MOON_RADIUS_KM * SCENE_SCALE
const ORBIT_RADIUS: float = MOON_SEMIMAJOR_KM * SCENE_SCALE

# SphereMesh poles are local Y; world is Z-up. Same alignment trick as
# Earth, but no axial tilt or daily spin separate from the orbit:
# the moon is tidally locked, so the spin period equals the orbital
# period and we just compose a single yaw about local Z.
const POLE_ALIGN := Basis(Vector3(1.0, 0.0, 0.0), PI / 2.0)

@export var albedo_path: String = "res://resources/3D/moon/1k_moon.jpg"
@export var initial_phase_rad: float = 0.0
@export var randomize_phase: bool = true

var phase: float = 0.0
var angular_rate: float
var _orbit_basis: Basis


func _ready() -> void:
	angular_rate = TAU / MOON_SIDEREAL_PERIOD_SEC
	_orbit_basis = Basis(Vector3(1.0, 0.0, 0.0), deg_to_rad(MOON_INCLINATION_DEG))
	phase = (
		randf() * TAU if randomize_phase
		else fposmod(initial_phase_rad, TAU)
	)

	var sphere := SphereMesh.new()
	sphere.radius = VISUAL_RADIUS
	sphere.height = VISUAL_RADIUS * 2.0
	sphere.radial_segments = 32
	sphere.rings = 16
	mesh = sphere

	_setup_material()
	_apply_phase()


func _setup_material() -> void:
	var mat := StandardMaterial3D.new()
	mat.roughness = 1.0
	mat.metallic = 0.0
	if ResourceLoader.exists(albedo_path):
		mat.albedo_texture = load(albedo_path) as Texture2D
	else:
		push_warning("Moon texture not found: %s" % albedo_path)
		mat.albedo_color = Color(0.72, 0.72, 0.7)
	material_override = mat


func advance_phase(sim_delta: float) -> void:
	phase = fposmod(phase + angular_rate * sim_delta, TAU)
	_apply_phase()


func _apply_phase() -> void:
	var planar := Vector3(cos(phase), sin(phase), 0.0) * ORBIT_RADIUS
	position = _orbit_basis * planar
	# Tidally locked: same face always toward Earth. The yaw matches
	# the orbital phase so the near-side hemisphere tracks the origin.
	var face := Basis(Vector3(0.0, 0.0, 1.0), phase)
	transform.basis = _orbit_basis * face * POLE_ALIGN
