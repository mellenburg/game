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
const BeamRenderer = preload("res://scripts/beam_renderer.gd")
const ImpactTracker = preload("res://scripts/impact_tracker.gd")
const ImpactMap = preload("res://scripts/impact_map.gd")
const ImpactExplosion = preload("res://scripts/impact_explosion.gd")
const RangeCircle = preload("res://scripts/range_circle.gd")

const TIME_FACTOR_MIN: int = 0
const TIME_FACTOR_MAX: int = 5000
const TIME_FACTOR_RATE: int = 60       # changes per second while held
const PLANNING_DT_MAX: int = 86400 * 7  # one week of plan window

# Engagement-range adjustment rate while shift+up/down is held. Sized
# so an operator can sweep the full settable band (MIN_ENGAGEMENT_RANGE
# to MAX_RANGE) in roughly four seconds — fast enough to feel
# responsive, slow enough to land on a chosen ring.
const RANGE_RATE_KM_PER_SEC: float = 10000.0

const ENEMIES_PER_SPAWN: int = 3
const ENEMY_ALT_MIN_KM: float = 600.0
const ENEMY_ALT_MAX_KM: float = 2000.0

# Starting fleet: three player satellites in 500 km circular orbits.
# Inclinations are drawn independently below the cap so the planes
# differ; RAAN is uniformly random per ship; consecutive true anomalies
# are separated by a random gap inside [NU_GAP_MIN_DEG, NU_GAP_MAX_DEG]
# so the ships fan out along their orbits instead of bunching at launch.
const STARTING_SAT_COUNT: int = 3
const STARTING_SAT_ALT_KM: float = 500.0
const STARTING_SAT_INC_MAX_DEG: float = 60.0
const STARTING_SAT_NU_GAP_MIN_DEG: float = 80.0
const STARTING_SAT_NU_GAP_MAX_DEG: float = 160.0

# Meteorite storms: a small cluster of fragile, sub-orbital bodies all
# incoming from one random direction. Spawned high enough to give the
# player a window to engage, with the per-body velocity post-clamped
# (see _make_meteorite) to guarantee a sub-surface periapsis — so every
# storm body genuinely impacts within a few minutes of sim time.
const METEORITES_PER_STORM: int = 3
const METEORITE_ALT_MIN_KM: float = 40000.0
const METEORITE_ALT_MAX_KM: float = 70000.0
# Inward radial dominates; the tangential share is small but non-zero so
# the trajectories fan out over time. After spawn, each body's velocity
# is clamped (EarthOrbit.clamp_velocity_for_periapsis) to guarantee
# periapsis below the surface — without that clamp, lateral spread and
# per-axis jitter can pump enough angular momentum into the orbit to
# lift periapsis above ground, which both removes the trajectory arc
# from the renderer and breaks the impact-on-ground gameplay rule.
const METEORITE_RADIAL_SPEED_MIN: float = 4.0
const METEORITE_RADIAL_SPEED_MAX: float = 7.0
const METEORITE_TANGENTIAL_SPEED_MIN: float = 0.4
const METEORITE_TANGENTIAL_SPEED_MAX: float = 1.6
# Margin: target r_p strictly less than EARTH_RADIUS so impact is
# unambiguous under propagator step-size (the surface-cross termination
# samples r at step boundaries and via the perihelion-cross detector).
const METEORITE_PERIAPSIS_TARGET_KM: float = (
	EarthOrbit.EARTH_RADIUS_KM * 0.9
)
# Cluster scatter relative to the storm's nominal entry point. Thousands
# of km of lateral offset + altitude jitter so the three trajectory
# lines fan out clearly on screen rather than overlapping; per-axis
# velocity jitter peels each path further apart over time.
const METEORITE_LATERAL_SPREAD_KM: float = 3000.0
const METEORITE_ALT_JITTER_KM: float = 1500.0
const METEORITE_VELOCITY_JITTER: float = 0.4
const METEORITE_HP: float = 100.0

@export var time_factor: int = 500
var planning_dt: int = 0
var planning_mode: bool = false

var real_satellites: Array[Satellite] = []
var planning_satellites: Array[Satellite] = []
var selected_ship: int = 0
var planning_selected: int = 0

# Running tallies of how each enemy left play. Driven from the dead-
# satellite sweep so it counts every termination once, regardless of
# whether the cause was a weapon hit or a sub-orbital impact.
var enemies_shot_down: int = 0
var meteorites_impacted: int = 0

var _time_factor_accum: float = 0.0
var _planning_dt_accum: float = 0.0
var _rng := RandomNumberGenerator.new()
var impact_tracker := ImpactTracker.new()
# Day-side albedo loaded once as an Image so we can sample it at an
# impact's UV without an editor-only Texture readback. Lazily filled
# in _ready; null-safe — if the texture's missing, ocean classification
# falls back to the bounding-box table alone.
var _albedo_image: Image = null

@onready var earth: Earth = $Earth as Earth
@onready var camera: OrbitCamera = $OrbitCamera as OrbitCamera
@onready var hud: HUD = $CanvasLayer/HUD as HUD
@onready var satellite_container: Node3D = $Satellites as Node3D
@onready var planning_container: Node3D = $PlanningSatellites as Node3D
@onready var beam_renderer: BeamRenderer = $BeamRenderer as BeamRenderer
@onready var range_circle: RangeCircle = $RangeCircle as RangeCircle
@onready var impact_map: ImpactMap = $CanvasLayer/HUD/ImpactMap as ImpactMap

var satellites: Array[Satellite]:
	get: return planning_satellites if planning_mode else real_satellites


func _ready() -> void:
	_rng.randomize()
	_albedo_image = _load_albedo_image()
	if impact_map != null:
		impact_map.tracker = impact_tracker
	_spawn_starting_fleet()
	if not real_satellites.is_empty():
		selected_ship = 0
		real_satellites[0].select()


# Pull the day-side albedo into an Image once. Sampling at impact time
# is then a single pixel read — no GPU readback, no per-impact load.
func _load_albedo_image() -> Image:
	const path := "res://resources/3D/earth/4096_earth.jpg"
	if not ResourceLoader.exists(path):
		return null
	var tex := load(path) as Texture2D
	if tex == null:
		return null
	return tex.get_image()


func _process(delta: float) -> void:
	camera.process_movement(delta)
	_process_continuous_input(delta)
	_process_one_shot_input()
	_update_range_circle()
	hud.update_hud(self, planning_mode, time_factor, planning_dt)
	hud.draw_target_lines(self, camera)


func _physics_process(delta: float) -> void:
	# Convert wall-clock seconds to simulated seconds.
	var sim_delta := float(time_factor) * delta
	earth.advance_phase(sim_delta)
	impact_tracker.tick(sim_delta)
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


# Charge each satellite's energy pool, then either fire each weapon
# at the closest valid enemy or let it cool. Lasers are continuous-
# fire now: the same call applies dt-scaled damage, energy drain, and
# heating; weapons that don't fire this tick cool toward ready instead.
# Tower-defense: no player input needed.
func _process_combat(sim_delta: float) -> void:
	for sat in real_satellites:
		if not sat.alive:
			continue
		sat.tick_combat(sim_delta)
		for w_idx in range(sat.weapons.size()):
			var w: Weapon = sat.weapons[w_idx]
			var fired := false
			if w.can_fire(sat):
				var target := _pick_target_for_weapon(sat, w)
				if target != null and w.fire(sat, target, sim_delta):
					fired = true
					hud.register_hit(sat, target)
					beam_renderer.register_fire(sat, w_idx, target)
			if not fired:
				w.tick(sim_delta)


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
		# Tally enemy terminations by cause: HP gone -> shot down by a
		# weapon; meteorite still has HP -> ground impact (advance_time
		# kills it on surface crossing without touching hp).
		if sat.team == Satellite.TEAM_ENEMY:
			if sat.hp <= 0.0:
				enemies_shot_down += 1
			elif sat.is_meteorite:
				meteorites_impacted += 1
				_record_meteorite_impact(sat)
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
	# Shift gates the arrow keys onto the engagement-range adjustment
	# axis so we only have to bind one set of keys. With shift held the
	# thrust block is suppressed entirely — otherwise releasing shift
	# mid-press would briefly inject thrust on the same arrow tap.
	var shift_held := Input.is_key_pressed(KEY_SHIFT)
	var thrust := Vector3.ZERO
	var range_input := 0.0
	if shift_held:
		if Input.is_action_pressed("thrust_prograde"):  range_input += 1.0
		if Input.is_action_pressed("thrust_retrograde"): range_input -= 1.0
	else:
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

	# Engagement-range nudge. Always written to the *real* satellite —
	# the planning clone is overwritten from reality every physics tick
	# (clone_orbit_from copies engagement_range_km), so mutating the
	# planning sat would be visually invisible the next frame.
	if range_input != 0.0 and not real_satellites.is_empty():
		var real_idx := planning_selected if planning_mode else selected_ship
		if real_idx >= 0 and real_idx < real_satellites.size():
			var rsat := real_satellites[real_idx]
			if (
				rsat.team == Satellite.TEAM_PLAYER
				and rsat.fire_control_active
				and not rsat.weapons.is_empty()
			):
				rsat.set_engagement_range(
					rsat.engagement_range_km
					+ range_input * RANGE_RATE_KM_PER_SEC * delta
				)


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
	if Input.is_action_just_pressed("toggle_los"):
		hud.los_visible = not hud.los_visible
	if Input.is_action_just_pressed("toggle_impact_map"):
		if impact_map != null:
			impact_map.visible = not impact_map.visible
	if Input.is_action_just_pressed("toggle_fire_control"):
		_toggle_fire_control_on_selected()


# Toggle fire-control mode on the active player satellite. Mutates
# the *real* sat (planning clone gets resync'd next physics tick).
# Unarmed units silently no-op so the user gets no feedback for a
# meaningless toggle on an enemy or meteorite.
func _toggle_fire_control_on_selected() -> void:
	if real_satellites.is_empty():
		return
	var idx := planning_selected if planning_mode else selected_ship
	if idx < 0 or idx >= real_satellites.size():
		return
	var sat := real_satellites[idx]
	if sat.team != Satellite.TEAM_PLAYER or sat.weapons.is_empty():
		return
	sat.toggle_fire_control()


# Engagement-range visual. Renders a circle in the ecliptic plane
# centered on the active satellite while the operator holds shift, so
# they can eyeball the configured engagement distance against
# neighbouring units. Hidden whenever the operator isn't holding
# shift, fire control is off, or there's no valid selection.
func _update_range_circle() -> void:
	if range_circle == null:
		return
	var sats: Array[Satellite] = (
		planning_satellites if planning_mode else real_satellites
	)
	var idx := planning_selected if planning_mode else selected_ship
	var visible_now := false
	if (
		Input.is_key_pressed(KEY_SHIFT)
		and idx >= 0
		and idx < sats.size()
	):
		var sat: Satellite = sats[idx]
		if (
			sat.team == Satellite.TEAM_PLAYER
			and sat.fire_control_active
			and sat.alive
			and sat.orbit_alive
			and not sat.weapons.is_empty()
		):
			range_circle.update_circle(sat.orbit.r, sat.engagement_range_km)
			visible_now = true
	range_circle.visible = visible_now


func add_satellite() -> void:
	var sat := Satellite.new()
	satellite_container.add_child(sat)
	if not real_satellites.is_empty() and selected_ship < real_satellites.size():
		real_satellites[selected_ship].unselect()
	real_satellites.append(sat)
	selected_ship = real_satellites.size() - 1
	sat.select()


# Spawn the starting fleet — three player satellites in 500 km circular
# orbits with independent inclinations under the cap, random RAANs, and
# true anomalies separated by a random gap so the formation fans out.
# Selection is left to the caller so the standard "select index 0"
# pattern in _ready stays in one place.
func _spawn_starting_fleet() -> void:
	var inc_max := deg_to_rad(STARTING_SAT_INC_MAX_DEG)
	var gap_min := deg_to_rad(STARTING_SAT_NU_GAP_MIN_DEG)
	var gap_max := deg_to_rad(STARTING_SAT_NU_GAP_MAX_DEG)
	var nu := _rng.randf_range(0.0, TAU)
	for i in range(STARTING_SAT_COUNT):
		var sat := Satellite.new()
		sat.orbit = EarthOrbit.make_circular(
			STARTING_SAT_ALT_KM,
			_rng.randf_range(0.0, inc_max),
			_rng.randf_range(0.0, TAU),
			nu,
		)
		satellite_container.add_child(sat)
		real_satellites.append(sat)
		nu = fposmod(nu + _rng.randf_range(gap_min, gap_max), TAU)


# Spawn a fixed batch of unarmed enemies in random circular orbits.
# Circular keeps them stable (no decay, no escape) so they're easy
# tower-defense fodder; random altitude + orientation gives variety
# without relying on hand-authored elements.
func add_enemies(count: int = ENEMIES_PER_SPAWN) -> void:
	for _i in range(count):
		var sat := _make_enemy_in_random_orbit()
		satellite_container.add_child(sat)
		real_satellites.append(sat)


# Spawn a cluster of meteorites all incoming from one random direction
# — sub-orbital, unarmed, fragile. The cluster shares an entry point
# and base velocity, jittered per body so they arrive separated by a
# few hundred km. Lasers can pick them off in transit; any survivors
# self-terminate on ground impact.
func add_meteorite_storm(count: int = METEORITES_PER_STORM) -> void:
	var r_hat := _random_unit_vector()
	var tangent := _random_perpendicular_unit(r_hat)
	var base_altitude := _rng.randf_range(
		METEORITE_ALT_MIN_KM, METEORITE_ALT_MAX_KM
	)
	var radial_speed := _rng.randf_range(
		METEORITE_RADIAL_SPEED_MIN, METEORITE_RADIAL_SPEED_MAX
	)
	var tangential_speed := _rng.randf_range(
		METEORITE_TANGENTIAL_SPEED_MIN, METEORITE_TANGENTIAL_SPEED_MAX
	)
	var base_velocity := -r_hat * radial_speed + tangent * tangential_speed
	for _i in range(count):
		var sat := _make_meteorite(r_hat, tangent, base_altitude, base_velocity)
		satellite_container.add_child(sat)
		real_satellites.append(sat)


# Capture the impact coordinates of a meteorite that just terminated
# on ground contact. Pulls the body's last ECI position, samples the
# day-side albedo at the resulting UV to flag ocean vs land, and hands
# the record to the tracker. Robust to a missing albedo image — we
# just skip the ocean hint in that case and let the bounding-box
# fallback in classify_region pick a label.
func _record_meteorite_impact(sat: Satellite) -> void:
	if sat == null or sat.orbit == null:
		return
	var phase: float = earth.earth_phase if earth != null else 0.0
	var surface_pos: Vector3 = sat.orbit.r.normalized() * EarthOrbit.EARTH_RADIUS_KM
	var local := ImpactTracker.eci_to_mesh_local(surface_pos, phase)
	var uv := ImpactTracker.mesh_local_to_uv(local)
	var ocean_hint := false
	if _albedo_image != null:
		var w := _albedo_image.get_width()
		var h := _albedo_image.get_height()
		if w > 0 and h > 0:
			var px := clampi(int(uv.x * float(w)), 0, w - 1)
			var py := clampi(int(uv.y * float(h)), 0, h - 1)
			ocean_hint = ImpactTracker.is_ocean_pixel(_albedo_image.get_pixel(px, py))
	impact_tracker.record_impact(sat.orbit.r, phase, ocean_hint)
	_spawn_impact_explosion(surface_pos)


func _spawn_impact_explosion(surface_pos: Vector3) -> void:
	var explosion := ImpactExplosion.new()
	add_child(explosion)
	explosion.set_impact_position(surface_pos)


func _make_meteorite(
	r_hat: Vector3,
	tangent: Vector3,
	base_altitude: float,
	base_velocity: Vector3,
) -> Satellite:
	var sat := Satellite.new()
	sat.team = Satellite.TEAM_ENEMY
	sat.weapons.clear()
	sat.is_meteorite = true
	sat.hp = METEORITE_HP

	# Lateral offset uses the in-plane basis (tangent + bitangent); the
	# bitangent is just r_hat × tangent so the offset stays in the plane
	# perpendicular to the entry vector.
	var bitangent := r_hat.cross(tangent).normalized()
	var lateral_angle := _rng.randf_range(0.0, TAU)
	var lateral_dist := _rng.randf_range(0.0, METEORITE_LATERAL_SPREAD_KM)
	var altitude := base_altitude + _rng.randf_range(
		-METEORITE_ALT_JITTER_KM, METEORITE_ALT_JITTER_KM
	)
	var pos := r_hat * (EarthOrbit.EARTH_RADIUS_KM + altitude) + (
		tangent * cos(lateral_angle) + bitangent * sin(lateral_angle)
	) * lateral_dist
	# Velocity jitter as a small fraction of the base; same direction
	# basis so all bodies remain inbound rather than scattering randomly.
	var jitter := METEORITE_VELOCITY_JITTER
	var vel := base_velocity + Vector3(
		_rng.randf_range(-jitter, jitter),
		_rng.randf_range(-jitter, jitter),
		_rng.randf_range(-jitter, jitter),
	)
	vel = EarthOrbit.clamp_velocity_for_periapsis(
		pos, vel, METEORITE_PERIAPSIS_TARGET_KM
	)
	sat.orbit = EarthOrbit.new(pos, vel)
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
