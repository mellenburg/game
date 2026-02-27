class_name OrbitCamera
extends Camera3D
## Euler-angle free-look camera — port of camera.h.
## WASD moves, mouse rotates. Z-up coordinate system.

const SPEED: float = 15.0  # scene units/sec (was 15000 km/s, now /1000)
const SENSITIVITY: float = 0.15

var yaw: float = 180.0
var pitch: float = 0.0
var cam_front := Vector3(-1.0, 0.0, 0.0)
var cam_right := Vector3.ZERO
var cam_up := Vector3.ZERO
var world_up := Vector3(0.0, 0.0, 1.0)

var mouse_captured: bool = true


func _ready() -> void:
	# Position at 3x Earth radius (~19.1 scene units)
	position = Vector3(3.0 * 6.371, 0.0, 0.0)
	_update_vectors()

	# Near/far planes for orbital scale
	near = 0.3
	far = 700.0

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _update_vectors() -> void:
	var front := Vector3.ZERO
	front.x = cos(deg_to_rad(yaw)) * cos(deg_to_rad(pitch))
	front.z = sin(deg_to_rad(pitch))
	front.y = sin(-deg_to_rad(yaw)) * cos(deg_to_rad(pitch))
	cam_front = front.normalized()
	cam_right = cam_front.cross(world_up).normalized()
	cam_up = cam_right.cross(cam_front).normalized()

	# Apply to Godot's camera via look_at
	var target := position + cam_front
	if target.distance_to(position) > 0.001:
		look_at(target, world_up)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and mouse_captured:
		yaw += event.relative.x * SENSITIVITY
		pitch -= event.relative.y * SENSITIVITY
		pitch = clampf(pitch, -89.0, 89.0)
		_update_vectors()

	if event is InputEventKey:
		if event.keycode == KEY_ESCAPE and event.pressed:
			mouse_captured = not mouse_captured
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if mouse_captured else Input.MOUSE_MODE_VISIBLE


func process_movement(delta: float) -> void:
	var velocity := SPEED * delta
	if Input.is_action_pressed("move_forward"):
		position += cam_front * velocity
	if Input.is_action_pressed("move_backward"):
		position -= cam_front * velocity
	if Input.is_action_pressed("move_left"):
		position -= cam_right * velocity
	if Input.is_action_pressed("move_right"):
		position += cam_right * velocity
	_update_vectors()
