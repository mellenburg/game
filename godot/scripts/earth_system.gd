class_name EarthSystem
extends Node3D
## Top-level controller. Simulation runs in _physics_process at a fixed
## tick rate so the orbit math is frame-rate independent. _process is
## reserved for camera + HUD.

const Satellite = preload("res://scripts/satellite.gd")
const Earth = preload("res://scripts/earth.gd")
const HUD = preload("res://scripts/hud.gd")
const OrbitCamera = preload("res://scripts/orbit_camera.gd")

const TIME_FACTOR_MIN: int = 0
const TIME_FACTOR_MAX: int = 5000
const TIME_FACTOR_RATE: int = 60       # changes per second while held
const PLANNING_DT_MAX: int = 86400 * 7  # one week of plan window

@export var time_factor: int = 500
var planning_dt: int = 0
var planning_mode: bool = false

var real_satellites: Array[Satellite] = []
var planning_satellites: Array[Satellite] = []
var selected_ship: int = 0
var planning_selected: int = 0

var _time_factor_accum: float = 0.0
var _planning_dt_accum: float = 0.0

@onready var earth: Earth = $Earth as Earth
@onready var camera: OrbitCamera = $OrbitCamera as OrbitCamera
@onready var hud: HUD = $CanvasLayer/HUD as HUD
@onready var satellite_container: Node3D = $Satellites as Node3D
@onready var planning_container: Node3D = $PlanningSatellites as Node3D

var satellites: Array[Satellite]:
	get: return planning_satellites if planning_mode else real_satellites


func _ready() -> void:
	add_satellite()
	if not real_satellites.is_empty():
		real_satellites[0].select()


func _process(delta: float) -> void:
	camera.process_movement(delta)
	_process_continuous_input(delta)
	_process_one_shot_input()
	hud.update_hud(self, planning_mode, time_factor, planning_dt)
	hud.draw_target_lines(self, camera)


func _physics_process(delta: float) -> void:
	# Convert wall-clock seconds to simulated seconds.
	var sim_delta := float(time_factor) * delta
	earth.advance_phase(sim_delta)
	for sat in real_satellites:
		sat.advance_time(sim_delta)
		sat.render_orbit(true)

	if planning_mode:
		_sync_planning_to_reality()
		var window := float(planning_dt)
		for i in range(planning_satellites.size()):
			# Snap orbit-state from reality but keep the operator's queued
			# maneuver. Then advance by planning_dt so the path shows
			# "where this satellite would be after planning_dt seconds
			# given the queued thrust".
			var plan_sat := planning_satellites[i]
			plan_sat.clone_orbit_from(real_satellites[i])
			if plan_sat.orbit_alive and window > 0.0:
				plan_sat.advance_time(window)
			plan_sat.render_orbit(i == planning_selected)
			plan_sat.visible = true
	else:
		for sat in planning_satellites:
			sat.visible = false


func _process_continuous_input(delta: float) -> void:
	var thrust := Vector3.ZERO
	if Input.is_action_pressed("thrust_prograde"):  thrust.x += 1.0
	if Input.is_action_pressed("thrust_retrograde"): thrust.x -= 1.0
	if Input.is_action_pressed("thrust_left"):       thrust.y += 1.0
	if Input.is_action_pressed("thrust_right"):      thrust.y -= 1.0
	if Input.is_action_pressed("thrust_up"):         thrust.z += 1.0
	if Input.is_action_pressed("thrust_down"):       thrust.z -= 1.0

	# Time factor: rate-scaled by frame delta, clamped. The previous port
	# incremented per frame which made the rate framerate-dependent and
	# unbounded; that drove orbit propagation into NaN within ~30 seconds
	# of holding Q.
	var rate := float(TIME_FACTOR_RATE) * delta
	_time_factor_accum += rate * (
		(1.0 if Input.is_action_pressed("speed_up") else 0.0)
		- (1.0 if Input.is_action_pressed("speed_down") else 0.0)
	)
	var step_int := int(_time_factor_accum)
	if step_int != 0:
		time_factor = clampi(time_factor + step_int, TIME_FACTOR_MIN, TIME_FACTOR_MAX)
		_time_factor_accum -= float(step_int)

	_planning_dt_accum += rate * (
		(1.0 if Input.is_action_pressed("planning_advance") else 0.0)
		- (1.0 if Input.is_action_pressed("planning_retard") else 0.0)
	)
	var dt_step := int(_planning_dt_accum)
	if dt_step != 0:
		planning_dt = clampi(planning_dt + dt_step, 0, PLANNING_DT_MAX)
		_planning_dt_accum -= float(dt_step)

	# Apply thrust to whichever satellite is "hot".
	var target_satellites: Array[Satellite] = (
		planning_satellites if planning_mode else real_satellites
	)
	var idx := planning_selected if planning_mode else selected_ship
	if not target_satellites.is_empty() and idx >= 0 and idx < target_satellites.size():
		target_satellites[idx].set_maneuver(thrust)


func _process_one_shot_input() -> void:
	if Input.is_action_just_pressed("select_next"):
		select_next_ship()
	if Input.is_action_just_pressed("add_satellite"):
		add_satellite()
	if Input.is_action_just_pressed("remove_satellite"):
		remove_satellite()
	if Input.is_action_just_pressed("toggle_planning"):
		toggle_planning()


func add_satellite() -> void:
	var sat := Satellite.new()
	satellite_container.add_child(sat)
	if not real_satellites.is_empty() and selected_ship < real_satellites.size():
		real_satellites[selected_ship].unselect()
	real_satellites.append(sat)
	selected_ship = real_satellites.size() - 1
	sat.select()


func remove_satellite() -> void:
	if real_satellites.size() <= 1:
		return
	var sat := real_satellites[selected_ship]
	real_satellites.remove_at(selected_ship)
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
	if planning_mode and not planning_satellites.is_empty():
		planning_satellites[planning_selected].unselect()
		planning_selected = selected_ship % planning_satellites.size()
		planning_satellites[planning_selected].select()


func toggle_planning() -> void:
	if planning_mode:
		planning_mode = false
		_clear_planning()
		return
	_clear_planning()
	for sat in real_satellites:
		var clone := Satellite.new()
		planning_container.add_child(clone)
		clone.clone_from(sat)
		planning_satellites.append(clone)
	planning_selected = clampi(selected_ship, 0, maxi(planning_satellites.size() - 1, 0))
	if not planning_satellites.is_empty():
		planning_satellites[planning_selected].select()
	planning_mode = true


func _clear_planning() -> void:
	for sat in planning_satellites:
		sat.queue_free()
	planning_satellites.clear()
	planning_dt = 0


# Keep planning_satellites length matched to real_satellites. add/remove
# of real ships during planning would otherwise leave the arrays
# misaligned and the HUD/selection logic indexing past the planning end.
func _sync_planning_to_reality() -> void:
	while planning_satellites.size() < real_satellites.size():
		var clone := Satellite.new()
		planning_container.add_child(clone)
		clone.clone_from(real_satellites[planning_satellites.size()])
		planning_satellites.append(clone)
	while planning_satellites.size() > real_satellites.size():
		var sat: Satellite = planning_satellites.pop_back()
		sat.queue_free()
	if planning_satellites.is_empty():
		planning_selected = 0
	else:
		planning_selected = clampi(planning_selected, 0, planning_satellites.size() - 1)
