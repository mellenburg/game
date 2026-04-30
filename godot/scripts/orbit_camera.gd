class_name OrbitCamera
extends Camera3D
## Camera driven by WASD along a default orbital path around Earth.
##
##   A / D            rotate clockwise / counterclockwise along the path
##                    (clockwise as viewed from world +Z).
##   W / S            decrease / increase the path's radius.
##   Shift+W / Shift+D
##                    temporarily increase / decrease the orbit's
##                    inclination, pivoting the camera out of plane about
##                    its current position (the line of nodes). After
##                    INCLINATION_RETURN_DELAY seconds without
##                    inclination input, the offset eases back to zero.
##
## All rates are tied to wall-clock delta — sim time_factor must not
## influence camera motion. The camera always looks at the origin.

const EARTH_RADIUS_KM: float = 6371.0
const SCENE_SCALE: float = 1.0 / 1000.0
const DEFAULT_ORBIT_RADIUS: float = 6.0 * EARTH_RADIUS_KM * SCENE_SCALE
const MIN_ORBIT_RADIUS: float = 1.5 * EARTH_RADIUS_KM * SCENE_SCALE
const MAX_ORBIT_RADIUS: float = 18.0 * EARTH_RADIUS_KM * SCENE_SCALE
const ORBIT_TILT_DEG: float = 20.0

const ANGULAR_RATE: float = TAU / 30.0  # rad/s of phase travel under hold
const RADIUS_RATE: float = 0.3 * DEFAULT_ORBIT_RADIUS  # scene units / s
const INCLINATION_RATE_DEG: float = 45.0  # deg/s while shift+W/D held
const MAX_INCLINATION_DEG: float = 60.0
const INCLINATION_RETURN_DELAY: float = 2.0
const INCLINATION_BLEND_RATE: float = 3.0  # exponential approach (1/s)

var world_up := Vector3(0.0, 0.0, 1.0)

var _orbit_phase: float = 0.0
var _orbit_radius: float = DEFAULT_ORBIT_RADIUS
var _inclination_offset: float = 0.0
var _inclination_idle_time: float = INCLINATION_RETURN_DELAY


func _ready() -> void:
	near = 0.3
	far = 700.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_update_pose()


func process_movement(delta: float) -> void:
	var shift := Input.is_key_pressed(KEY_SHIFT)
	var incl_step := deg_to_rad(INCLINATION_RATE_DEG) * delta
	var inclination_input := false

	if Input.is_action_pressed("move_left"):
		_orbit_phase -= ANGULAR_RATE * delta
	if Input.is_action_pressed("move_right"):
		if shift:
			_inclination_offset -= incl_step
			inclination_input = true
		else:
			_orbit_phase += ANGULAR_RATE * delta
	if Input.is_action_pressed("move_forward"):
		if shift:
			_inclination_offset += incl_step
			inclination_input = true
		else:
			_orbit_radius -= RADIUS_RATE * delta
	if Input.is_action_pressed("move_backward"):
		_orbit_radius += RADIUS_RATE * delta

	_orbit_phase = fposmod(_orbit_phase, TAU)
	_orbit_radius = clampf(_orbit_radius, MIN_ORBIT_RADIUS, MAX_ORBIT_RADIUS)
	var incl_max := deg_to_rad(MAX_INCLINATION_DEG)
	_inclination_offset = clampf(_inclination_offset, -incl_max, incl_max)

	if inclination_input:
		_inclination_idle_time = 0.0
	else:
		_inclination_idle_time += delta
		if _inclination_idle_time >= INCLINATION_RETURN_DELAY:
			var t := clampf(INCLINATION_BLEND_RATE * delta, 0.0, 1.0)
			_inclination_offset = lerpf(_inclination_offset, 0.0, t)

	_update_pose()


func _orbit_position() -> Vector3:
	var tilt := deg_to_rad(ORBIT_TILT_DEG)
	var c := cos(_orbit_phase)
	var s := sin(_orbit_phase)
	var p_base := Vector3(
		c * _orbit_radius,
		s * _orbit_radius * cos(tilt),
		s * _orbit_radius * sin(tilt),
	)
	if absf(_inclination_offset) < 1.0e-6:
		return p_base
	# Rotate the camera about the orbital tangent through the origin —
	# treating its current location as the line of nodes, this tilts the
	# orbit plane while preserving the camera-to-Earth distance. Negate
	# the angle so a positive offset lifts the camera toward world +Z.
	var tangent := Vector3(-s, c * cos(tilt), c * sin(tilt)).normalized()
	return p_base.rotated(tangent, -_inclination_offset)


func _update_pose() -> void:
	position = _orbit_position()
	if position.length_squared() < 1.0e-6:
		return
	var up := world_up
	# look_at degenerates if the up vector is parallel to the view
	# direction. Pick a fallback when the camera is near the world pole.
	if absf(position.normalized().dot(up)) > 0.999:
		up = Vector3(1.0, 0.0, 0.0)
	look_at(Vector3.ZERO, up)
