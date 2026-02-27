extends Node3D
## Main game controller — port of EarthSystem from earth.cpp.
## Manages satellites, input, simulation time, and planning mode.

const TIME_RESOLUTION: float = 1.0 / 30.0  # base tick rate

var time_factor: int = 500
var dt: int = 0
var planning_mode: bool = false

var real_satellites: Array[Satellite] = []
var planning_satellites: Array[Satellite] = []
var selected_ship: int = 0
var planning_selected: int = 0

var planning_maneuver := Vector3.ZERO

# Node references
@onready var earth: MeshInstance3D = $Earth
@onready var camera: Camera3D = $OrbitCamera
@onready var hud: Control = $CanvasLayer/HUD
@onready var satellite_container: Node3D = $Satellites
@onready var planning_container: Node3D = $PlanningSatellites
@onready var sun_light: DirectionalLight3D = $SunLight

# Expose satellites array for HUD access
var satellites: Array[Satellite]:
	get: return planning_satellites if planning_mode else real_satellites


func _ready() -> void:
	add_satellite()
	real_satellites[0].select()


func _process(delta: float) -> void:
	# Camera movement
	camera.process_movement(delta)

	# Simulation step
	var sim_delta := time_factor * TIME_RESOLUTION
	earth.advance_phase(sim_delta)

	# Process input
	_process_input()

	# Advance real satellites
	for sat in real_satellites:
		sat.advance_time(sim_delta)
		sat.render_orbit(true)

	# Planning mode rendering
	if planning_mode:
		for i in range(planning_satellites.size()):
			planning_satellites[i].advance_time(float(dt))
			var show_path := (i == planning_selected)
			planning_satellites[i].render_orbit(show_path)
		for sat in planning_satellites:
			sat.visible = true
	else:
		for sat in planning_satellites:
			sat.visible = false

	# Update HUD
	hud.update_hud(self, planning_mode, time_factor, dt)
	hud.draw_target_lines(self, camera)


func _process_input() -> void:
	# Thrust input
	var thrust := Vector3.ZERO
	if Input.is_action_pressed("thrust_prograde"):
		thrust.x += 1.0
	if Input.is_action_pressed("thrust_retrograde"):
		thrust.x -= 1.0
	if Input.is_action_pressed("thrust_left"):
		thrust.y += 1.0
	if Input.is_action_pressed("thrust_right"):
		thrust.y -= 1.0
	if Input.is_action_pressed("thrust_up"):
		thrust.z += 1.0
	if Input.is_action_pressed("thrust_down"):
		thrust.z -= 1.0

	# Time controls
	if Input.is_action_pressed("speed_up"):
		time_factor += 1
	if Input.is_action_pressed("speed_down") and time_factor > 0:
		time_factor -= 1
	if Input.is_action_pressed("planning_advance"):
		dt += 1
	if Input.is_action_pressed("planning_retard") and dt > 0:
		dt -= 1

	# Apply thrust
	if planning_mode:
		planning_maneuver = thrust
		if not planning_satellites.is_empty():
			planning_satellites[planning_selected].set_maneuver(thrust)
	else:
		if not real_satellites.is_empty():
			real_satellites[selected_ship].set_maneuver(thrust)

	# One-shot actions
	if Input.is_action_just_pressed("select_next"):
		select_next_ship()
	if Input.is_action_just_pressed("add_satellite"):
		add_satellite()
	if Input.is_action_just_pressed("remove_satellite"):
		remove_satellite()
	if Input.is_action_just_pressed("toggle_planning"):
		_toggle_planning()


func add_satellite() -> void:
	var sat := Satellite.new()
	satellite_container.add_child(sat)
	# Unselect current
	if not real_satellites.is_empty():
		real_satellites[selected_ship].unselect()
	real_satellites.append(sat)
	selected_ship = real_satellites.size() - 1
	sat.select()


func remove_satellite() -> void:
	if real_satellites.size() <= 1:
		return
	var sat := real_satellites[selected_ship]
	real_satellites.remove_at(selected_ship)
	satellite_container.remove_child(sat)
	sat.queue_free()
	selected_ship = 0
	if not real_satellites.is_empty():
		real_satellites[selected_ship].select()


func select_next_ship() -> void:
	if real_satellites.is_empty():
		return
	real_satellites[selected_ship].unselect()
	selected_ship = (selected_ship + 1) % real_satellites.size()
	real_satellites[selected_ship].select()

	if planning_mode:
		if not planning_satellites.is_empty():
			planning_satellites[planning_selected].unselect()
		planning_selected = selected_ship % planning_satellites.size()
		if not planning_satellites.is_empty():
			planning_satellites[planning_selected].select()


func _toggle_planning() -> void:
	if not planning_mode:
		# Enter planning mode: clone real satellites
		_clear_planning()
		for sat in real_satellites:
			var clone := Satellite.new()
			planning_container.add_child(clone)
			# Wait a frame for _ready to fire, then clone data
			clone.clone_from(sat)
			planning_satellites.append(clone)
		planning_selected = selected_ship
		if not planning_satellites.is_empty():
			planning_satellites[planning_selected].select()
		planning_mode = true
	else:
		planning_mode = false
		_clear_planning()


func _clear_planning() -> void:
	for sat in planning_satellites:
		planning_container.remove_child(sat)
		sat.queue_free()
	planning_satellites.clear()
