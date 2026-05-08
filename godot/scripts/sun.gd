class_name Sun
extends Node3D
## Visible sun anchored at the world's lighting direction. Renders an
## additive billboard (bright core + soft corona) on a QuadMesh, and
## exposes the world-space sun direction so other systems
## (planet shader, lens flare overlay) stay in sync.
##
## The planet shader's `sun_direction` uniform is the source of truth
## for "which way is the light coming from"; this node mirrors that
## constant so a single edit moves both the lit hemisphere and the
## visible disc.

const MassCenter = preload("res://scripts/mass_center.gd")
const LosCheck = preload("res://scripts/los_check.gd")
const CelestialBody = preload("res://scripts/celestial_body.gd")

# Direction from Earth toward the sun, in world (ECI) coordinates.
# Must match `planet.gdshader`'s sun_direction.
const WORLD_DIRECTION := Vector3(1.0, 0.0, 0.0)

# Earth-scale distance in scene units (1 unit = 1000 km). Held inside
# the camera's 700-unit far plane so the billboard always renders. For
# bodies whose camera band pushes past this number (Saturn at ~720
# scene units MAX) we scale the distance up in _ready so the sun stays
# beyond the operator's pull-back.
const DISTANCE: float = 600.0

# Visual size of the quad (scene units). Earth-scale; we scale this in
# _ready alongside the distance so the apparent angular size of the
# sun stays the same when standing at the body's default camera radius.
const QUAD_SIZE: float = 80.0

@export var core_color: Color = Color(1.0, 0.97, 0.85)
@export var corona_color: Color = Color(1.0, 0.65, 0.25)

var _quad: MeshInstance3D


func _ready() -> void:
	# Distance / quad both grow with the active body's max-camera
	# standoff so a Saturn stage doesn't render the sun billboard
	# inside the camera's default radius (then have it clipped against
	# the camera's far plane the moment we widen the camera band).
	# Earth's legacy numbers (600 / 80) fall out as the floor when the
	# body's max-camera fits inside them.
	var body: CelestialBody = CelestialBody.active(get_tree())
	var max_camera_units: float = body.radius_km * 0.001 * body.camera_max_radii
	var distance: float = maxf(DISTANCE, max_camera_units * 1.4)
	# Keep apparent angular size constant by scaling the quad by the
	# same factor. distance / DISTANCE collapses to 1.0 for Earth-scale
	# bodies (where the floor is hit) so the legacy quad-size is
	# preserved exactly.
	var size_scale: float = distance / DISTANCE
	position = WORLD_DIRECTION.normalized() * distance

	var quad := QuadMesh.new()
	quad.size = Vector2(QUAD_SIZE * size_scale, QUAD_SIZE * size_scale)

	_quad = MeshInstance3D.new()
	_quad.mesh = quad

	var shader := load("res://shaders/sun.gdshader") as Shader
	if shader != null:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("core_color", core_color)
		mat.set_shader_parameter("corona_color", corona_color)
		_quad.material_override = mat
	else:
		# Headless / missing-resource fallback so tests don't fail to load.
		var fallback := StandardMaterial3D.new()
		fallback.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fallback.albedo_color = core_color
		_quad.material_override = fallback

	add_child(_quad)


## True if the Earth's bounding sphere occludes the segment from
## `viewer_scene_pos` (scene units) to this sun. Used by the lens-flare
## overlay to fade ghosts when the sun goes behind the planet.
func is_occluded(viewer_scene_pos: Vector3) -> bool:
	var to_km := 1.0 / MassCenter.SCENE_SCALE
	return LosCheck.is_blocked(viewer_scene_pos * to_km, position * to_km)
