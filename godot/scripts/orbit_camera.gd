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
##   F (held)         FPS-style free-look while held. Mouse is a
##                    cursor at all other times so the operator can
##                    click on HUD tiles / panels without first having
##                    to release a captured cursor.
##
## Each modality has its own idle timer; after RETURN_DELAY seconds with
## no input on that modality, the offset eases back to the default
## (radius → DEFAULT_ORBIT_RADIUS, inclination → 0, look angles → look-at-
## Earth). The phase keeps advancing on its own at AUTO_ORBIT_RATE
## whenever the player isn't pushing it, so the camera always drifts
## around Earth when left alone. All rates use wall-clock delta — sim
## time_factor must not influence camera motion.

const MassCenterOrbit = preload("res://scripts/mass_center_orbit.gd")
const CelestialBody = preload("res://scripts/celestial_body.gd")

# Camera radius bands scale with the active body so a gas-giant stage
# doesn't bury the camera inside the planet at the Earth-scaled
# defaults. The original Earth-pegged constants are now per-body fields
# on CelestialBody (camera_default_radii / camera_min_radii /
# camera_max_radii), expressed as multiples of the body's surface
# radius. Resolved into instance vars in _ready below; everything
# downstream reads the vars, not the constants.
const SCENE_SCALE: float = 1.0 / 1000.0
const ORBIT_TILT_DEG: float = 20.0

# Earth-scale defaults — used when CelestialBody isn't reachable (e.g.
# direct-boot tests). These are the legacy const values and stay at
# Earth's radius × the legacy multipliers so the headless test path
# observes the historical numbers.
const DEFAULT_ORBIT_RADIUS_FALLBACK: float = 7.8 * 6371.0 * SCENE_SCALE
const MIN_ORBIT_RADIUS_FALLBACK: float = 1.5 * 6371.0 * SCENE_SCALE
const MAX_ORBIT_RADIUS_FALLBACK: float = 18.0 * 6371.0 * SCENE_SCALE

var default_orbit_radius: float = DEFAULT_ORBIT_RADIUS_FALLBACK
var min_orbit_radius: float = MIN_ORBIT_RADIUS_FALLBACK
var max_orbit_radius: float = MAX_ORBIT_RADIUS_FALLBACK
# Translation rate for W/S held — sized so the operator can sweep from
# default to MIN or to MAX in roughly two seconds.
var radius_rate: float = 0.6 * DEFAULT_ORBIT_RADIUS_FALLBACK

const AUTO_ORBIT_RATE: float = TAU / 90.0  # rad/s, slow ambient drift
const USER_ANGULAR_RATE: float = TAU / 15.0  # rad/s while A/D held
const INCLINATION_RATE_DEG: float = 90.0  # deg/s while shift+W/S held
const MAX_INCLINATION_DEG: float = 60.0
const MOUSE_SENSITIVITY: float = 0.15

const RETURN_DELAY: float = 2.0
const RETURN_BLEND_RATE: float = 3.0  # exponential approach (1/s)

var world_up := Vector3(0.0, 0.0, 1.0)
# Free-look gate. False by default — the cursor stays visible so the
# operator can click HUD tiles. Held-F flips this on for the duration
# of the press; mouse motion only feeds yaw/pitch while it's true.
var mouse_captured: bool = false

var yaw: float = 0.0
var pitch: float = 0.0

var _orbit_phase: float = 0.0
var _orbit_radius: float = DEFAULT_ORBIT_RADIUS_FALLBACK
var _inclination_offset: float = 0.0

var _radius_idle: float = RETURN_DELAY
var _inclination_idle: float = RETURN_DELAY
var _look_idle: float = RETURN_DELAY


func _ready() -> void:
	# Pull the active body's radius and resolve every camera-band
	# constant against it. Direct-boot / headless paths get Earth's
	# radius via CelestialBody.active(...) so the legacy numbers fall
	# out unchanged when no menu is in front of us.
	var body: CelestialBody = CelestialBody.active(get_tree())
	var body_radius_units: float = body.radius_km * SCENE_SCALE
	default_orbit_radius = body.camera_default_radii * body_radius_units
	min_orbit_radius = body.camera_min_radii * body_radius_units
	max_orbit_radius = body.camera_max_radii * body_radius_units
	radius_rate = 0.6 * default_orbit_radius
	_orbit_radius = default_orbit_radius
	# Far plane scales with the camera's max standoff so a Saturn stage
	# (max ≈ 720 scene units) keeps the planet, the rings, and the sun
	# billboard inside the frustum. The 1.6× headroom holds the sun a
	# comfortable distance past the camera's apex; near stays at 0.3
	# (close enough to look at the surface from inside the ring plane,
	# far enough that z-buffer precision survives the wider far span).
	near = 0.3
	far = maxf(700.0, max_orbit_radius * 1.6)
	position = _orbit_position()
	var yp := _yaw_pitch_facing_origin(position)
	yaw = yp.x
	pitch = yp.y
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_apply_look()


func _unhandled_input(event: InputEvent) -> void:
	# Free-look toggle: capture the cursor while F is held, release it
	# the moment F is let go. Press / release are picked up via the
	# `freelook` action so the binding can be remapped without touching
	# this code.
	if event.is_action_pressed("freelook"):
		mouse_captured = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if event.is_action_released("freelook"):
		mouse_captured = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return

	if event is InputEventMouseMotion and mouse_captured:
		var motion := event as InputEventMouseMotion
		if motion.relative != Vector2.ZERO:
			yaw += motion.relative.x * MOUSE_SENSITIVITY
			pitch -= motion.relative.y * MOUSE_SENSITIVITY
			pitch = clampf(pitch, -89.0, 89.0)
			_look_idle = 0.0
		return


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
			_orbit_radius -= radius_rate * delta
			radius_input = true
	if Input.is_action_pressed("move_backward"):
		if shift:
			_inclination_offset -= incl_step
			inclination_input = true
		else:
			_orbit_radius += radius_rate * delta
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
			_orbit_radius = lerpf(_orbit_radius, default_orbit_radius, t)
	_orbit_radius = clampf(_orbit_radius, min_orbit_radius, max_orbit_radius)

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
