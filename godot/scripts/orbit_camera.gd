class_name OrbitCamera
extends Camera3D
## Camera that slowly orbits Earth at a fixed altitude, always facing it.
## WASD and mouse let the player break away for free-look; after
## RETURN_DELAY seconds of inactivity the view smoothly drifts back into
## the auto orbit. The orbit's angular rate is tied to wall-clock time —
## *not* the simulation's time_factor — so speeding up the sim must not
## spin the camera.

const EARTH_RADIUS_KM: float = 6371.0
const SCENE_SCALE: float = 1.0 / 1000.0
const ORBIT_RADIUS: float = 6.0 * EARTH_RADIUS_KM * SCENE_SCALE  # ~38.2 units
const ORBIT_PERIOD_SEC: float = 90.0
const ORBIT_TILT_DEG: float = 20.0
const RETURN_DELAY: float = 2.0
const RETURN_BLEND_RATE: float = 3.0  # exponential approach rate (1/sec)

const MOVE_SPEED: float = 15.0  # scene units / second
const SENSITIVITY: float = 0.15

var yaw: float = 0.0
var pitch: float = 0.0
var cam_front := Vector3(-1.0, 0.0, 0.0)
var cam_right := Vector3.ZERO
var cam_up := Vector3.ZERO
var world_up := Vector3(0.0, 0.0, 1.0)

var mouse_captured: bool = true

var _orbit_phase: float = 0.0
var _idle_time: float = RETURN_DELAY


func _ready() -> void:
	near = 0.3
	far = 700.0
	_snap_to_orbit()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and mouse_captured:
		var motion := event as InputEventMouseMotion
		if motion.relative != Vector2.ZERO:
			_idle_time = 0.0
			yaw += motion.relative.x * SENSITIVITY
			pitch -= motion.relative.y * SENSITIVITY
			pitch = clampf(pitch, -89.0, 89.0)
			_update_vectors_from_yaw_pitch()
		return

	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and key.keycode == KEY_ESCAPE:
			mouse_captured = not mouse_captured
			Input.mouse_mode = (
				Input.MOUSE_MODE_CAPTURED if mouse_captured
				else Input.MOUSE_MODE_VISIBLE
			)


func process_movement(delta: float) -> void:
	# The auto-orbit phase advances with wall-clock delta only — sim
	# time_factor must not influence camera motion.
	_orbit_phase = fposmod(_orbit_phase + TAU * delta / ORBIT_PERIOD_SEC, TAU)

	var step := MOVE_SPEED * delta
	var moved := false
	if Input.is_action_pressed("move_forward"):
		position += cam_front * step; moved = true
	if Input.is_action_pressed("move_backward"):
		position -= cam_front * step; moved = true
	if Input.is_action_pressed("move_left"):
		position -= cam_right * step; moved = true
	if Input.is_action_pressed("move_right"):
		position += cam_right * step; moved = true

	if moved:
		_idle_time = 0.0
	else:
		_idle_time += delta

	if _idle_time >= RETURN_DELAY:
		_blend_to_orbit(delta)
	else:
		_update_vectors_from_yaw_pitch()


func _orbit_position() -> Vector3:
	# Tilted circular path: rotate the unit circle (X,Y,0) by ORBIT_TILT_DEG
	# about the X axis so the orbit plane is offset from the equator.
	var tilt := deg_to_rad(ORBIT_TILT_DEG)
	var c := cos(_orbit_phase)
	var s := sin(_orbit_phase)
	return Vector3(
		c * ORBIT_RADIUS,
		s * ORBIT_RADIUS * cos(tilt),
		s * ORBIT_RADIUS * sin(tilt),
	)


func _yaw_pitch_facing_origin(pos: Vector3) -> Vector2:
	# Yaw/pitch (in degrees) such that cam_front per _update_vectors_from_yaw_pitch
	# points from `pos` toward the origin.
	if pos.length_squared() < 1.0e-12:
		return Vector2(yaw, pitch)
	var f := -pos.normalized()
	var p_deg := rad_to_deg(asin(clampf(f.z, -1.0, 1.0)))
	var y_deg := rad_to_deg(atan2(-f.y, f.x))
	return Vector2(y_deg, p_deg)


func _snap_to_orbit() -> void:
	position = _orbit_position()
	var yp := _yaw_pitch_facing_origin(position)
	yaw = yp.x
	pitch = yp.y
	_update_vectors_from_yaw_pitch()


func _blend_to_orbit(delta: float) -> void:
	var target_pos := _orbit_position()
	var t := clampf(RETURN_BLEND_RATE * delta, 0.0, 1.0)
	position = position.lerp(target_pos, t)
	# Re-derive the look-at-origin yaw/pitch from the *current* position
	# each frame so the camera tracks Earth smoothly throughout the blend
	# rather than aiming at where it'll be when fully snapped.
	var yp := _yaw_pitch_facing_origin(position)
	var yaw_rad := lerp_angle(deg_to_rad(yaw), deg_to_rad(yp.x), t)
	yaw = rad_to_deg(yaw_rad)
	pitch = lerpf(pitch, yp.y, t)
	_update_vectors_from_yaw_pitch()


func _update_vectors_from_yaw_pitch() -> void:
	var yr := deg_to_rad(yaw)
	var pr := deg_to_rad(pitch)
	cam_front = Vector3(
		cos(yr) * cos(pr),
		sin(-yr) * cos(pr),
		sin(pr),
	).normalized()
	cam_right = cam_front.cross(world_up).normalized()
	cam_up = cam_right.cross(cam_front).normalized()
	var target := position + cam_front
	if position.distance_to(target) > 1.0e-4:
		look_at(target, world_up)
