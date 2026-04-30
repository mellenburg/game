class_name RangeCircle
extends MeshInstance3D
## Engagement-range visual: a wire circle drawn in the earth-sun
## orbital plane (XY in the project's Z-up convention) and translated
## to the satellite's scene position. Surfaces while the operator is
## holding shift on a fire-control-active satellite so they can read
## off the configured engagement distance against neighbouring units.
##
## Cached ArrayMesh + StandardMaterial3D — same pattern as OrbitalPath
## (CLAUDE.md: "Cache meshes and materials"). The vertex buffer is
## only rewritten when the radius changes; per-tick repositioning is
## done via `position` so a moving satellite doesn't trigger a buffer
## upload every physics step.

const SCENE_SCALE: float = 1.0 / 1000.0  # km -> scene units
const POINTS: int = 96

var _array_mesh: ArrayMesh
var _material: StandardMaterial3D
var _points: PackedVector3Array
var _last_radius_km: float = -1.0
var color := Color(0.4, 0.95, 0.55, 0.85)


func _ready() -> void:
	_array_mesh = ArrayMesh.new()
	mesh = _array_mesh

	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.albedo_color = color
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Keep the ring readable when it crosses the dark side of Earth or
	# the bright sun — drop depth writes so overlapping geometry doesn't
	# fight it for visibility, but keep depth test so the planet does
	# still occlude when the ring sinks into it.
	_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material_override = _material

	_points = PackedVector3Array()
	_points.resize(POINTS + 1)
	visible = false


## Update the ring's radius and recenter it on `center_km` (ECI). The
## vertex buffer is only rebuilt when radius drifts past a half-km;
## position is rewritten unconditionally because the satellite moves
## every physics tick.
func update_circle(center_km: Vector3, radius_km: float) -> void:
	position = center_km * SCENE_SCALE
	if absf(radius_km - _last_radius_km) < 0.5 and _array_mesh.get_surface_count() > 0:
		return
	var r := radius_km * SCENE_SCALE
	for i in range(POINTS + 1):
		var ang := TAU * float(i % POINTS) / float(POINTS)
		_points[i] = Vector3(cos(ang) * r, sin(ang) * r, 0.0)
	_array_mesh.clear_surfaces()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _points
	_array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINE_STRIP, arrays)
	_array_mesh.surface_set_material(0, _material)
	_last_radius_km = radius_km
