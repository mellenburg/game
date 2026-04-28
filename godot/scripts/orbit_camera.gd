class_name OrbitCamera
extends Camera3D
## Free-look camera in a Z-up world. WASD pans, mouse rotates.
## Movement is rate-scaled by frame delta so it's frame-independent.

const MOVE_SPEED: float = 15.0  # scene units / second
const SENSITIVITY: float = 0.15

var yaw: float = 180.0
var pitch: float = 0.0
var cam_front := Vector3(-1.0, 0.0, 0.0)
var cam_right := Vector3.ZERO
var cam_up := Vector3.ZERO
var world_up := Vector3(0.0, 0.0, 1.0)

var mouse_captured: bool = true


func _ready() -> void:
	position = Vector3(3.0 * 6.371, 0.0, 0.0)
	near = 0.3
	far = 700.0
	_update_vectors()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and mouse_captured:
		var motion := event as InputEventMouseMotion
		yaw += motion.relative.x * SENSITIVITY
		pitch -= motion.relative.y * SENSITIVITY
		pitch = clampf(pitch, -89.0, 89.0)
		_update_vectors()
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
		_update_vectors()


func _update_vectors() -> void:
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
