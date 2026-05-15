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

# Direction from Earth toward the sun, in world (ECI) coordinates.
# Must match `planet.gdshader`'s sun_direction.
const WORLD_DIRECTION := Vector3(1.0, 0.0, 0.0)

# Distance in scene units (1 unit = 1000 km). Held inside the camera's
# 700-unit far plane so the billboard always renders.
const DISTANCE: float = 600.0

# Visual size of the quad (scene units). The shader confines the bright
# region to the inner ~50% so the quad edges fade to black cleanly.
const QUAD_SIZE: float = 80.0

@export var core_color: Color = Color(1.0, 0.97, 0.85)
@export var corona_color: Color = Color(1.0, 0.65, 0.25)

var _quad: MeshInstance3D


func _ready() -> void:
	position = WORLD_DIRECTION.normalized() * DISTANCE

	var quad := QuadMesh.new()
	quad.size = Vector2(QUAD_SIZE, QUAD_SIZE)

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
