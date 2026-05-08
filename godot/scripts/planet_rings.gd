class_name PlanetRings
extends MeshInstance3D
## Flat annular disc that sits in a body's equatorial plane. Built once
## per stage from the active CelestialBody's ring radii; the shader
## handles ring-strip texturing, hemisphere lighting, and the body's
## umbra projected onto the disc.
##
## The disc is added as a child of MassCenterSystem (not MassCenter)
## because the rings should inherit the body's axial tilt but NOT its
## daily spin — Saturn's rings hold their inertial orientation while
## the planet rotates underneath them. We bake the axial tilt into this
## node's transform once at _ready and leave it alone thereafter.
##
## The shader references planet.gdshader's `sun_direction` constant via
## its own uniform — both shaders read the same world-space direction
## so the planet's terminator and the disc's shadow stay aligned.

const CelestialBody = preload("res://scripts/celestial_body.gd")

# Density of the angular tessellation. 256 segments gives sub-pixel
# silhouette quality at typical camera distances without dragging the
# vertex count above what a Compatibility-renderer mobile GPU can chew
# in a single draw call. Two triangles per segment × 256 segments =
# 512 tris, well under any per-frame budget.
const ANGULAR_SEGMENTS: int = 256
# Radial subdivision. Rings are flat in the radial direction (no
# elevation), but having a few radial rows lets the shader's UV
# resolution stay tight at the inner edge where the ring strip's most
# detail lives. Two rows is the minimum to avoid degenerate triangles.
const RADIAL_SEGMENTS: int = 2

# Scene-units-per-km. Mirrors Satellite.SCENE_SCALE / MassCenter.SCENE_SCALE
# rather than importing one of those — keeps PlanetRings importable
# from headless tests without dragging the full scene tree along.
const SCENE_SCALE: float = 1.0 / 1000.0


func setup(body: CelestialBody) -> void:
	if not body.has_rings:
		queue_free()
		return
	mesh = _build_ring_mesh(body)
	material_override = _build_ring_material(body)
	# Axial tilt about world X — same axis the body's transform uses.
	# We do NOT compose the daily spin (POLE_ALIGN + rotation_phase)
	# because the rings are inertially fixed; only the body underneath
	# them rotates.
	transform.basis = Basis(
		Vector3(1.0, 0.0, 0.0), body.axial_tilt_rad + body.ring_tilt_offset_rad
	)


func _build_ring_mesh(body: CelestialBody) -> ArrayMesh:
	var inner: float = body.ring_inner_km * SCENE_SCALE
	var outer: float = body.ring_outer_km * SCENE_SCALE
	if outer <= inner:
		return ArrayMesh.new()

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	# Pre-allocate to keep allocations off the per-vertex loop. Vertex
	# count = (RADIAL_SEGMENTS+1) × (ANGULAR_SEGMENTS+1); we close the
	# angular loop with a duplicate vertex column so UV.x stays
	# continuous instead of wrapping back to 0 at the seam.
	var n_radial := RADIAL_SEGMENTS + 1
	var n_angular := ANGULAR_SEGMENTS + 1
	verts.resize(n_radial * n_angular)
	normals.resize(n_radial * n_angular)
	uvs.resize(n_radial * n_angular)

	var two_pi := TAU
	for ri in range(n_radial):
		var u: float = float(ri) / float(RADIAL_SEGMENTS)
		var r: float = lerpf(inner, outer, u)
		for ai in range(n_angular):
			var ang := two_pi * float(ai) / float(ANGULAR_SEGMENTS)
			var i := ri * n_angular + ai
			verts[i] = Vector3(r * cos(ang), r * sin(ang), 0.0)
			# Disc normal sits on +Z (the body's spin axis after
			# axial-tilt). cull_disabled in the shader handles the
			# back-face; the dot(N, sun) hemisphere-lighting term in
			# the fragment uses |N| as the magnitude so flipping at
			# the back face is automatic.
			normals[i] = Vector3(0.0, 0.0, 1.0)
			uvs[i] = Vector2(u, 0.5)

	# Two triangles per (radial, angular) cell. Wind CCW from the +Z
	# face so the normal we wrote above matches.
	indices.resize(RADIAL_SEGMENTS * ANGULAR_SEGMENTS * 6)
	var idx := 0
	for ri in range(RADIAL_SEGMENTS):
		for ai in range(ANGULAR_SEGMENTS):
			var i00 := ri * n_angular + ai
			var i01 := ri * n_angular + ai + 1
			var i10 := (ri + 1) * n_angular + ai
			var i11 := (ri + 1) * n_angular + ai + 1
			indices[idx + 0] = i00
			indices[idx + 1] = i10
			indices[idx + 2] = i11
			indices[idx + 3] = i00
			indices[idx + 4] = i11
			indices[idx + 5] = i01
			idx += 6

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var arr_mesh := ArrayMesh.new()
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return arr_mesh


func _build_ring_material(body: CelestialBody) -> Material:
	var shader := load("res://shaders/planet_rings.gdshader") as Shader
	if shader == null:
		# Fallback to an opaque solid colour so headless tests don't
		# fail — the shader compile is the only thing that depends on
		# the asset pipeline being warm.
		var fallback := StandardMaterial3D.new()
		fallback.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fallback.cull_mode = BaseMaterial3D.CULL_DISABLED
		fallback.albedo_color = body.fallback_color
		return fallback
	var mat := ShaderMaterial.new()
	mat.shader = shader
	if body.ring_texture_path != "" and ResourceLoader.exists(body.ring_texture_path):
		var tex := load(body.ring_texture_path) as Texture2D
		if tex != null:
			mat.set_shader_parameter("ring_texture", tex)
	mat.set_shader_parameter("sun_direction", Vector3(1.0, 0.0, 0.0))
	mat.set_shader_parameter("body_radius_scene", body.radius_km * SCENE_SCALE)
	# Penumbra width as a small fraction of the body radius — at
	# Saturn's distance from the sun the angular size of the sun is
	# ~3.4 arcmin, which projects to a tiny penumbra against the body
	# (~1.5% of body radius); the visual effect is mostly to soften
	# aliasing on the umbra edge rather than to render true penumbra
	# physics.
	mat.set_shader_parameter("penumbra_scene", body.radius_km * SCENE_SCALE * 0.025)
	return mat
