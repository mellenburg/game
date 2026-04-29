class_name LensFlare
extends ColorRect
## Screen-space lens flare overlay. Each frame, projects the world `Sun`
## to UV space and hands the result to a canvas-item shader, which
## additively draws the flare ghosts/streaks along the line from the
## sun to screen center. Earth occludes the flare via `Sun.is_occluded`.
##
## Kept frame-rate independent: target intensity is computed each frame,
## then eased toward over `fade_speed` so the flare doesn't pop on/off
## as the sun crosses the horizon.

const Sun = preload("res://scripts/sun.gd")

@export var fade_speed: float = 6.0  # 1/seconds

var _camera: Camera3D
var _sun: Sun
var _shader_mat: ShaderMaterial
var _intensity: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# ColorRect's own color must be transparent — the shader does all
	# the drawing additively on top of nothing.
	color = Color(0.0, 0.0, 0.0, 0.0)

	var shader := load("res://shaders/lens_flare.gdshader") as Shader
	if shader == null:
		# Headless fallback: leave the rect transparent and never update.
		return
	_shader_mat = ShaderMaterial.new()
	_shader_mat.shader = shader
	_shader_mat.set_shader_parameter("intensity", 0.0)
	material = _shader_mat


func bind(camera: Camera3D, sun: Sun) -> void:
	_camera = camera
	_sun = sun


func _process(delta: float) -> void:
	if _shader_mat == null or _camera == null or _sun == null:
		return

	var viewport_size := get_viewport_rect().size
	var target_intensity := 0.0
	var sun_world := _sun.global_position

	if (
		viewport_size.x > 0.0
		and viewport_size.y > 0.0
		and not _camera.is_position_behind(sun_world)
	):
		var screen := _camera.unproject_position(sun_world)
		var uv := Vector2(screen.x / viewport_size.x, screen.y / viewport_size.y)
		# Soft cutoff once the sun drifts well off-screen, so we don't
		# render a flare anchored to a point the user can't see.
		var off := maxf(absf(uv.x - 0.5), absf(uv.y - 0.5))
		var on_screen := 1.0 - smoothstep(0.6, 1.3, off)
		var blocked := _sun.is_occluded(_camera.global_position)
		target_intensity = 0.0 if blocked else on_screen
		_shader_mat.set_shader_parameter("sun_uv", uv)
		_shader_mat.set_shader_parameter("aspect", viewport_size.x / viewport_size.y)

	var t := clampf(fade_speed * delta, 0.0, 1.0)
	_intensity = lerpf(_intensity, target_intensity, t)
	_shader_mat.set_shader_parameter("intensity", _intensity)
