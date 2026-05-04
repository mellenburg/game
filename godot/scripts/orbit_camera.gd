class_name OrbitCamera
extends Camera3D
## Camera that follows a default orbital path around Earth and lets the
## player override it. Layout:
##
##   A / D            rotate clockwise / counterclockwise along the path
##                    (clockwise as viewed from world +Z).
##   W / S            decrease / increase the path's radius.
##   Shift+W / Shift+S
##                    temporarily increase / decrease the orbit's
##                    inclination, pivoting the camera out of plane about
##                    its current location (the line of nodes).
##   Mouse            FPS-style free-look (when captured). ESC toggles
##                    mouse capture.
##
## Each modality has its own idle timer; after RETURN_DELAY seconds with
## no input on that modality, the offset eases back to the default
## (radius → DEFAULT_ORBIT_RADIUS, inclination → 0, look angles → look-at-
## Earth). The phase keeps advancing on its own at AUTO_ORBIT_RATE
## whenever the player isn't pushing it, so the camera always drifts
## around Earth when left alone. All rates use wall-clock delta — sim
## time_factor must not influence camera motion.

const EarthOrbit = preload("res://scripts/earth_orbit.gd")

# Camera radius bands are pegged to Earth-scale so the camera distance
# feels consistent regardless of the active body — a Mars stage doesn't
# halve the camera's standoff just because Mars is half Earth's radius.
const REFERENCE_RADIUS_KM: float = 6371.0
const SCENE_SCALE: float = 1.0 / 1000.0
const DEFAULT_ORBIT_RADIUS: float = 7.8 * REFERENCE_RADIUS_KM * SCENE_SCALE
const MIN_ORBIT_RADIUS: float = 1.5 * REFERENCE_RADIUS_KM * SCENE_SCALE
const MAX_ORBIT_RADIUS: float = 18.0 * REFERENCE_RADIUS_KM * SCENE_SCALE
const ORBIT_TILT_DEG: float = 20.0

const AUTO_ORBIT_RATE: float = TAU / 90.0  # rad/s, slow ambient drift
const USER_ANGULAR_RATE: float = TAU / 15.0  # rad/s while A/D held
const RADIUS_RATE: float = 0.6 * DEFAULT_ORBIT_RADIUS  # units/s while W/S
const INCLINATION_RATE_DEG: float = 90.0  # deg/s while shift+W/S held
const MAX_INCLINATION_DEG: float = 60.0
const MOUSE_SENSITIVITY: float = 0.15

const RETURN_DELAY: float = 2.0
const RETURN_BLEND_RATE: float = 3.0  # exponential approach (1/s)

var world_up := Vector3(0.0, 0.0, 1.0)
var mouse_captured: bool = true

var yaw: float = 0.0
var pitch: float = 0.0

var _orbit_phase: float = 0.0
var _orbit_radius: float = DEFAULT_ORBIT_RADIUS
var _inclination_offset: float = 0.0

var _radius_idle: float = RETURN_DELAY
var _inclination_idle: float = RETURN_DELAY
var _look_idle: float = RETURN_DELAY


func _ready() -> void:
	near = 0.3
	far = 700.0
	position = _orbit_position()
	var yp := _yaw_pitch_facing_origin(position)
	yaw = yp.x
	pitch = yp.y
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_apply_look()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and mouse_captured:
		var motion := event as InputEventMouseMotion
		if motion.relative != Vector2.ZERO:
			yaw += motion.relative.x * MOUSE_SENSITIVITY
			pitch -= motion.relative.y * MOUSE_SENSITIVITY
			pitch = clampf(pitch, -89.0, 89.0)
			_look_idle = 0.0
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
	# Detect Shift via both keycode and physical-key polling so the
	# modifier is picked up regardless of layout / left-vs-right key.
	var shift := (
		Input.is_key_pressed(KEY_SHIFT)
		or Input.is_physical_key_pressed(KEY_SHIFT)
	)
	var incl_step := deg_to_rad(INCLINATION_RATE_DEG) * delta

	var phase_input := false
	var radius_input := false
	var inclination_input := false

	if Input.is_action_pressed("move_left"):
		_orbit_phase -= USER_ANGULAR_RATE * delta
		phase_input = true
	if Input.is_action_pressed("move_right"):
		_orbit_phase += USER_ANGULAR_RATE * delta
		phase_input = true
	if Input.is_action_pressed("move_forward"):
		if shift:
			_inclination_offset += incl_step
			inclination_input = true
		else:
			_orbit_radius -= RADIUS_RATE * delta
			radius_input = true
	if Input.is_action_pressed("move_backward"):
		if shift:
			_inclination_offset -= incl_step
			inclination_input = true
		else:
			_orbit_radius += RADIUS_RATE * delta
			radius_input = true

	# Phase auto-advances unless the player is actively scrubbing it.
	if not phase_input:
		_orbit_phase += AUTO_ORBIT_RATE * delta
	_orbit_phase = fposmod(_orbit_phase, TAU)

	# Radius: hold user-set value briefly, then ease back to default.
	if radius_input:
		_radius_idle = 0.0
	else:
		_radius_idle += delta
		if _radius_idle >= RETURN_DELAY:
			var t := clampf(RETURN_BLEND_RATE * delta, 0.0, 1.0)
			_orbit_radius = lerpf(_orbit_radius, DEFAULT_ORBIT_RADIUS, t)
	_orbit_radius = clampf(_orbit_radius, MIN_ORBIT_RADIUS, MAX_ORBIT_RADIUS)

	# Inclination offset: same idle/return treatment.
	if inclination_input:
		_inclination_idle = 0.0
	else:
		_inclination_idle += delta
		if _inclination_idle >= RETURN_DELAY:
			var t := clampf(RETURN_BLEND_RATE * delta, 0.0, 1.0)
			_inclination_offset = lerpf(_inclination_offset, 0.0, t)
	var max_incl := deg_to_rad(MAX_INCLINATION_DEG)
	_inclination_offset = clampf(_inclination_offset, -max_incl, max_incl)

	position = _orbit_position()

	# Look angles: blend yaw/pitch back to look-at-Earth after the player
	# has stopped moving the mouse for RETURN_DELAY seconds. Until then
	# the user's free-look stays put.
	_look_idle += delta
	if _look_idle >= RETURN_DELAY:
		var target_yp := _yaw_pitch_facing_origin(position)
		var t := clampf(RETURN_BLEND_RATE * delta, 0.0, 1.0)
		var yaw_rad := lerp_angle(deg_to_rad(yaw), deg_to_rad(target_yp.x), t)
		yaw = rad_to_deg(yaw_rad)
		pitch = lerpf(pitch, target_yp.y, t)

	_apply_look()


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
	# Rotate about the orbital tangent through the origin — the camera's
	# current location acts as the line of nodes, so |position| stays
	# constant. Negate the angle so a positive offset lifts toward +Z.
	var tangent := Vector3(-s, c * cos(tilt), c * sin(tilt)).normalized()
	return p_base.rotated(tangent, -_inclination_offset)


func _yaw_pitch_facing_origin(pos: Vector3) -> Vector2:
	if pos.length_squared() < 1.0e-12:
		return Vector2(yaw, pitch)
	var f := -pos.normalized()
	var p_deg := rad_to_deg(asin(clampf(f.z, -1.0, 1.0)))
	var y_deg := rad_to_deg(atan2(-f.y, f.x))
	return Vector2(y_deg, p_deg)


func _apply_look() -> void:
	var yr := deg_to_rad(yaw)
	var pr := deg_to_rad(pitch)
	var front := Vector3(
		cos(yr) * cos(pr),
		sin(-yr) * cos(pr),
		sin(pr),
	).normalized()
	var up := world_up
	if absf(front.dot(up)) > 0.999:
		up = Vector3(1.0, 0.0, 0.0)
	var target := position + front
	if position.distance_to(target) > 1.0e-4:
		look_at(target, up)
