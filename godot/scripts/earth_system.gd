class_name EarthSystem
extends Node3D
## Top-level controller. Simulation runs in _physics_process at a fixed
## tick rate so the orbit math is frame-rate independent. _process is
## reserved for camera + HUD.

const Satellite = preload("res://scripts/satellite.gd")
const Earth = preload("res://scripts/earth.gd")
const HUD = preload("res://scripts/hud.gd")
const OrbitCamera = preload("res://scripts/orbit_camera.gd")
const EarthOrbit = preload("res://scripts/earth_orbit.gd")
const Weapon = preload("res://scripts/weapons/weapon.gd")

const TIME_FACTOR_MIN: int = 0
const TIME_FACTOR_MAX: int = 5000
const TIME_FACTOR_RATE: int = 60       # changes per second while held
const PLANNING_DT_MAX: int = 86400 * 7  # one week of plan window

const ENEMIES_PER_SPAWN: int = 3
const ENEMY_ALT_MIN_KM: float = 600.0
const ENEMY_ALT_MAX_KM: float = 2000.0

# Meteorite storms: many fragile, sub-orbital incoming bodies. They're
# spawned high enough to give the player a window to engage, with the
# tangential component small enough that periapsis lands well below
# Earth's surface — guaranteeing impact (and exit-from-play) within a
# few minutes of sim time.
const METEORITES_PER_STORM: int = 8
const METEORITE_ALT_MIN_KM: float = 4000.0
const METEORITE_ALT_MAX_KM: float = 10000.0
const METEORITE_RADIAL_SPEED_MIN: float = 2.0
const METEORITE_RADIAL_SPEED_MAX: float = 5.0
const METEORITE_TANGENTIAL_SPEED_MIN: float = 0.1
const METEORITE_TANGENTIAL_SPEED_MAX: float = 0.8
# Meteorites are softer than orbital enemies — one laser hit removes them.
const METEORITE_HP: float = 25.0

@export var time_factor: int = 500
var planning_dt: int = 0
var planning_mode: bool = false

var real_satellites: Array[Satellite] = []
var planning_satellites: Array[Satellite] = []
var selected_ship: int = 0
var planning_selected: int = 0

var _time_factor_accum: float = 0.0
var _planning_dt_accum: float = 0.0
var _rng := RandomNumberGenerator.new()

@onready var earth: Earth = $Earth as Earth
@onready var camera: OrbitCamera = $OrbitCamera as OrbitCamera
@onready var hud: HUD = $CanvasLayer/HUD as HUD
@onready var satellite_container: Node3D = $Satellites as Node3D
@onready var planning_container: Node3D = $PlanningSatellites as Node3D

var satellites: Array[Satellite]:
	get: return planning_satellites if planning_mode else real_satellites


func _ready() -> void:
	_rng.randomize()
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
	_process_combat(sim_delta)
	_remove_dead_satellites()
	for sat in real_satellites:
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
			if plan_sat.orbit_alive and plan_sat.alive and window > 0.0:
				plan_sat.advance_time(window)
			plan_sat.render_orbit(i == planning_selected)
			plan_sat.visible = true
	else:
		for sat in planning_satellites:
			sat.visible = false


# Charge each satellite's energy pool, tick every weapon's cooldown,
# then let any armed satellite auto-fire on the closest valid enemy
# (LOS clear, opposing team, both alive). Tower-defense: no player
# input needed.
func _process_combat(sim_delta: float) -> void:
	for sat in real_satellites:
		if not sat.alive:
			continue
		sat.tick_combat(sim_delta)
		for w in sat.weapons:
			if not w.can_fire(sat):
				continue
			var target := _pick_target_for_weapon(sat, w)
			if target != null and w.fire(sat, target):
				hud.register_hit(sat, target)


func _pick_target_for_weapon(attacker: Satellite, w: Weapon) -> Satellite:
	var best: Satellite = null
	var best_d2 := INF
	for other in real_satellites:
		if other == attacker:
			continue
		if not w.is_target_in_engagement_envelope(attacker, other):
			continue
		var d2: float = (other.orbit.r - attacker.orbit.r).length_squared()
		if d2 < best_d2:
			best_d2 = d2
			best = other
	return best


func _remove_dead_satellites() -> void:
	var i := 0
	while i < real_satellites.size():
		var sat := real_satellites[i]
		if sat.alive and sat.orbit_alive:
			i += 1
			continue
		# Mirror removal in planning so indices stay aligned.
		if i < planning_satellites.size():
			var plan_sat: Satellite = planning_satellites[i]
			planning_satellites.remove_at(i)
			plan_sat.queue_free()
		real_satellites.remove_at(i)
		sat.queue_free()
		if i < selected_ship:
			selected_ship -= 1
		if i < planning_selected:
			planning_selected -= 1
	if real_satellites.is_empty():
		selected_ship = 0
		planning_selected = 0
		return
	selected_ship = clampi(selected_ship, 0, real_satellites.size() - 1)
	planning_selected = clampi(planning_selected, 0, maxi(planning_satellites.size() - 1, 0))
	# Picking a fresh selection above can leave the new ship un-highlighted.
	if not real_satellites[selected_ship].selected:
		real_satellites[selected_ship].select()


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

	# Apply thrust to whichever satellite is "hot". Enemies are not
	# operator-controlled, so refuse thrust input on them; a stale
	# selection pointing at an enemy after a player ship died just means
	# the keys do nothing this frame.
	var target_satellites: Array[Satellite] = (
		planning_satellites if planning_mode else real_satellites
	)
	var idx := planning_selected if planning_mode else selected_ship
	if not target_satellites.is_empty() and idx >= 0 and idx < target_satellites.size():
		var sat := target_satellites[idx]
		if sat.team == Satellite.TEAM_PLAYER:
			sat.set_maneuver(thrust)


func _process_one_shot_input() -> void:
	if Input.is_action_just_pressed("select_next"):
		select_next_ship()
	if Input.is_action_just_pressed("add_satellite"):
		add_satellite()
	if Input.is_action_just_pressed("remove_satellite"):
		remove_satellite()
	if Input.is_action_just_pressed("toggle_planning"):
		toggle_planning()
	if Input.is_action_just_pressed("add_enemies"):
		add_enemies()
	if Input.is_action_just_pressed("add_meteorites"):
		add_meteorite_storm()


func add_satellite() -> void:
	var sat := Satellite.new()
	satellite_container.add_child(sat)
	if not real_satellites.is_empty() and selected_ship < real_satellites.size():
		real_satellites[selected_ship].unselect()
	real_satellites.append(sat)
	selected_ship = real_satellites.size() - 1
	sat.select()


# Spawn a fixed batch of unarmed enemies in random circular orbits.
# Circular keeps them stable (no decay, no escape) so they're easy
# tower-defense fodder; random altitude + orientation gives variety
# without relying on hand-authored elements.
func add_enemies(count: int = ENEMIES_PER_SPAWN) -> void:
	for _i in range(count):
		var sat := _make_enemy_in_random_orbit()
		satellite_container.add_child(sat)
		real_satellites.append(sat)


# Spawn a batch of meteorites — sub-orbital, unarmed, fragile. Each is
# on a highly eccentric trajectory whose periapsis is below Earth's
# surface, so they impact and exit play on their own. Lasers can pick
# them off in transit.
func add_meteorite_storm(count: int = METEORITES_PER_STORM) -> void:
	for _i in range(count):
		var sat := _make_meteorite()
		satellite_container.add_child(sat)
		real_satellites.append(sat)


func _make_meteorite() -> Satellite:
	var sat := Satellite.new()
	sat.team = Satellite.TEAM_ENEMY
	sat.weapons.clear()
	sat.is_meteorite = true
	sat.hp = METEORITE_HP

	var altitude := _rng.randf_range(METEORITE_ALT_MIN_KM, METEORITE_ALT_MAX_KM)
	var radius := EarthOrbit.EARTH_RADIUS_KM + altitude
	var r_hat := _random_unit_vector()
	var tangent := _random_perpendicular_unit(r_hat)
	var radial_speed := _rng.randf_range(
		METEORITE_RADIAL_SPEED_MIN, METEORITE_RADIAL_SPEED_MAX
	)
	var tangential_speed := _rng.randf_range(
		METEORITE_TANGENTIAL_SPEED_MIN, METEORITE_TANGENTIAL_SPEED_MAX
	)
	sat.orbit = EarthOrbit.new(
		r_hat * radius,
		-r_hat * radial_speed + tangent * tangential_speed,
	)
	return sat


func _make_enemy_in_random_orbit() -> Satellite:
	var sat := Satellite.new()
	sat.team = Satellite.TEAM_ENEMY
	sat.weapons.clear()  # Enemies are unarmed in the MVP.

	var altitude := _rng.randf_range(ENEMY_ALT_MIN_KM, ENEMY_ALT_MAX_KM)
	var radius := EarthOrbit.EARTH_RADIUS_KM + altitude
	var r_hat := _random_unit_vector()
	var v_hat := _random_perpendicular_unit(r_hat)
	var v_mag := sqrt(EarthOrbit.MU / radius)

	sat.orbit = EarthOrbit.new(r_hat * radius, v_hat * v_mag)
	return sat


func _random_unit_vector() -> Vector3:
	# Marsaglia: uniform on the sphere via two uniforms, no rejection.
	var z := _rng.randf_range(-1.0, 1.0)
	var theta := _rng.randf_range(0.0, TAU)
	var r_xy := sqrt(maxf(1.0 - z * z, 0.0))
	return Vector3(r_xy * cos(theta), r_xy * sin(theta), z)


func _random_perpendicular_unit(axis: Vector3) -> Vector3:
	# Build an arbitrary tangent in the plane perpendicular to `axis`,
	# rotated through a random angle. Picks a stable seed direction
	# that's never near-parallel to axis.
	var seed_axis := Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var u := axis.cross(seed_axis).normalized()
	var w := axis.cross(u).normalized()
	var phi := _rng.randf_range(0.0, TAU)
	return (u * cos(phi) + w * sin(phi)).normalized()


func remove_satellite() -> void:
	if real_satellites.size() <= 1:
		return
	var sat := real_satellites[selected_ship]
	real_satellites.remove_at(selected_ship)
	sat.queue_free()
	selected_ship = 0
	if not real_satellites.is_empty():
		real_satellites[selected_ship].select()


# Cycle through *player* ships only — enemies aren't operator-targets.
func select_next_ship() -> void:
	if real_satellites.is_empty():
		return
	var n := real_satellites.size()
	var start := selected_ship
	for offset in range(1, n + 1):
		var i: int = (start + int(offset)) % n
		if real_satellites[i].team == Satellite.TEAM_PLAYER:
			real_satellites[selected_ship].unselect()
			selected_ship = i
			real_satellites[selected_ship].select()
			break
	if planning_mode and not planning_satellites.is_empty():
		planning_satellites[planning_selected].unselect()
		planning_selected = clampi(selected_ship, 0, planning_satellites.size() - 1)
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
