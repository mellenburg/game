class_name SpawnDirector
extends Node
## Owns the PvE spawn behaviours — starting fleet, random enemy drops,
## meteorite storms, time-distributed meteorite waves, and the
## decaying-orbit enemy. EarthSystem wires this with the satellite
## container and the shared real_satellites array at _ready, then routes
## input-bound spawn requests through it. Pure spawn logic; no combat,
## no input handling, no planning-mode concerns. Splitting these out of
## EarthSystem makes the eventual server-authoritative refactor a clean
## seam — only this node's spawn calls need to move to the server side.

const Satellite = preload("res://scripts/satellite.gd")
const EarthOrbit = preload("res://scripts/earth_orbit.gd")
const MeteoriteWave = preload("res://scripts/meteorite_wave.gd")
const ThreatAlert = preload("res://scripts/threat_alert.gd")

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
const METEORITE_LATERAL_SPREAD_KM: float = 6000.0
const METEORITE_ALT_JITTER_KM: float = 3000.0
const METEORITE_VELOCITY_JITTER: float = 0.8
const METEORITE_HP: float = 25.0

# Wave mode: 20 meteorites from a single shared nexus, arrival times
# distributed uniformly across a 10-second wall-clock window so the
# player has continuous incoming traffic rather than a single burst.
# A preroll alert window precedes the spawn window so the operator
# gets time to react — bodies "scroll into" the radar from the top
# during the preroll, then begin entering play once it elapses.
const METEORITE_WAVE_COUNT: int = 20
const METEORITE_WAVE_DURATION_SEC: float = 10.0
const METEORITE_WAVE_PREROLL_SEC: float = 10.0

# Decaying-orbit enemy: spawned just past apogee on a highly
# eccentric ellipse — perigee 500 km, apogee 50000 km, e ≈ 0.78.
# Body falls toward perigee, where each crossing fires a retrograde
# burn that halves r_a. The orbit progressively shrinks (spirals
# in) until the burn drives the OTHER apsis below Earth's surface,
# at which point the body impacts on its next descending leg.
const DECAYING_APOGEE_ALT_KM: float = 50000.0
const DECAYING_PERIGEE_ALT_KM: float = 500.0
# True anomaly at spawn, measured past apogee on the descending
# leg (180° + 15° → orbit.nu wraps to ~-165° in (-π, π]). Body is
# already heading inbound, so the very first observed motion is
# "falling toward Earth" — sets the spiral-in narrative immediately.
const DECAYING_INITIAL_NU_FROM_APOGEE_DEG: float = 15.0
const DECAYING_HP: float = 200.0

# Active meteorite waves. Each carries its own nexus + queue of pending
# spawn delays; ticked from the controller's _process so the spawn
# window is real-time and independent of time_factor (so pausing the
# sim doesn't pause an in-flight wave). The radar overlay binds to this
# array directly, so any new wave appended here is visible without an
# extra wiring step.
var meteorite_waves: Array[MeteoriteWave] = []

var _rng := RandomNumberGenerator.new()
var _satellite_container: Node3D = null
var _satellites: Array[Satellite] = []
var _threat_alert: ThreatAlert = null


func setup(
	satellite_container: Node3D,
	satellites: Array[Satellite],
	threat_alert: ThreatAlert,
) -> void:
	_satellite_container = satellite_container
	_satellites = satellites
	_threat_alert = threat_alert
	_rng.randomize()


# Spawn the starting fleet — three player satellites in 500 km circular
# orbits with independent inclinations under the cap, random RAANs, and
# true anomalies separated by a random gap so the formation fans out.
# Selection is left to the caller so the standard "select index 0"
# pattern in EarthSystem._ready stays in one place.
func spawn_starting_fleet() -> void:
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
		_satellite_container.add_child(sat)
		_satellites.append(sat)
		nu = fposmod(nu + _rng.randf_range(gap_min, gap_max), TAU)


# Spawn a fixed batch of unarmed enemies in random circular orbits.
# Circular keeps them stable (no decay, no escape) so they're easy
# tower-defense fodder; random altitude + orientation gives variety
# without relying on hand-authored elements.
func add_enemies(count: int = ENEMIES_PER_SPAWN) -> void:
	for _i in range(count):
		var sat := _make_enemy_in_random_orbit()
		_satellite_container.add_child(sat)
		_satellites.append(sat)


# Spawn a cluster of meteorites all incoming from one random direction
# — sub-orbital, unarmed, fragile. The cluster shares an entry point
# and base velocity, jittered per body so they arrive separated by a
# few hundred km. Lasers can pick them off in transit; any survivors
# self-terminate on ground impact.
func add_meteorite_storm(count: int = METEORITES_PER_STORM) -> void:
	var wave := _build_meteorite_wave_at_random_nexus()
	for _i in range(count):
		var spec := _sample_meteorite_spec(
			METEORITE_LATERAL_SPREAD_KM,
			METEORITE_ALT_JITTER_KM,
			METEORITE_VELOCITY_JITTER,
		)
		var sat := _make_meteorite(
			wave.r_hat, wave.tangent, wave.base_altitude, wave.base_velocity, spec
		)
		_satellite_container.add_child(sat)
		_satellites.append(sat)


# Begin a 10-second wave: N meteorites all sharing one random nexus,
# their individual spawn delays drawn uniformly across the window so
# arrivals are spread out rather than bursty. Multiple waves can overlap
# (the player presses "i" again before the previous wave finishes) —
# each is a separate entry in meteorite_waves with its own nexus.
func start_meteorite_wave(
	count: int = METEORITE_WAVE_COUNT,
	duration_sec: float = METEORITE_WAVE_DURATION_SEC,
	preroll_sec: float = METEORITE_WAVE_PREROLL_SEC,
) -> void:
	var wave := _build_meteorite_wave_at_random_nexus()
	wave.populate(
		_rng,
		count,
		duration_sec,
		METEORITE_LATERAL_SPREAD_KM,
		METEORITE_ALT_JITTER_KM,
		METEORITE_VELOCITY_JITTER,
		preroll_sec,
	)
	meteorite_waves.append(wave)
	if _threat_alert != null:
		_threat_alert.trigger()


# Spawn a single decaying-orbit enemy. Highly eccentric, spawned just
# past apogee on the descending leg. The body falls toward perigee,
# gets a retrograde momentum kick at each perigee that halves r_a (the
# orbit spirals inward), and eventually one of those kicks pushes the
# trailing apsis below the surface — body impacts on its next descent.
func add_decaying_enemy() -> void:
	var sat := _make_decaying_enemy()
	_satellite_container.add_child(sat)
	_satellites.append(sat)


# Advance every active wave's spawn timers by real-time delta. Spawns
# any bodies whose timer expired this frame and drops completed waves.
func tick_waves(delta: float) -> void:
	if meteorite_waves.is_empty():
		return
	var i := 0
	while i < meteorite_waves.size():
		var wave := meteorite_waves[i]
		var ready_specs: Array[Dictionary] = wave.tick(delta)
		for spec: Dictionary in ready_specs:
			var sat := _make_meteorite(
				wave.r_hat,
				wave.tangent,
				wave.base_altitude,
				wave.base_velocity,
				spec,
			)
			_satellite_container.add_child(sat)
			_satellites.append(sat)
		if wave.is_complete():
			meteorite_waves.remove_at(i)
		else:
			i += 1


func has_active_waves() -> bool:
	return not meteorite_waves.is_empty()


# Sample a fresh nexus (entry direction, in-plane tangent, altitude,
# base velocity) for a meteorite cluster. Shared between the
# instantaneous storm (m) and the time-distributed wave (i) so both
# spawn paths use the same physics setup.
func _build_meteorite_wave_at_random_nexus() -> MeteoriteWave:
	var wave := MeteoriteWave.new()
	wave.r_hat = _random_unit_vector()
	wave.tangent = _random_perpendicular_unit(wave.r_hat)
	wave.base_altitude = _rng.randf_range(
		METEORITE_ALT_MIN_KM, METEORITE_ALT_MAX_KM
	)
	var radial_speed := _rng.randf_range(
		METEORITE_RADIAL_SPEED_MIN, METEORITE_RADIAL_SPEED_MAX
	)
	var tangential_speed := _rng.randf_range(
		METEORITE_TANGENTIAL_SPEED_MIN, METEORITE_TANGENTIAL_SPEED_MAX
	)
	wave.base_velocity = (
		-wave.r_hat * radial_speed + wave.tangent * tangential_speed
	)
	return wave


func _make_meteorite(
	r_hat: Vector3,
	tangent: Vector3,
	base_altitude: float,
	base_velocity: Vector3,
	spec: Dictionary,
) -> Satellite:
	var sat := Satellite.new()
	sat.team = Satellite.TEAM_ENEMY
	sat.weapons.clear()
	sat.is_meteorite = true
	sat.max_hp = METEORITE_HP
	sat.hp = METEORITE_HP

	# Lateral offset uses the in-plane basis (tangent + bitangent); the
	# bitangent is just r_hat × tangent so the offset stays in the plane
	# perpendicular to the entry vector. The lateral / altitude / vel-
	# jitter values come pre-sampled in `spec` so the radar overlay can
	# preview the same numbers before the body actually spawns.
	var bitangent := r_hat.cross(tangent).normalized()
	var lateral: Vector2 = spec["lateral"]
	var alt_offset: float = spec["alt_offset"]
	var vel_jitter: Vector3 = spec["vel_jitter"]
	var altitude := base_altitude + alt_offset
	var pos := r_hat * (EarthOrbit.EARTH_RADIUS_KM + altitude) + (
		tangent * lateral.x + bitangent * lateral.y
	)
	var vel := base_velocity + vel_jitter
	vel = EarthOrbit.clamp_velocity_for_periapsis(
		pos, vel, METEORITE_PERIAPSIS_TARGET_KM
	)
	sat.orbit = EarthOrbit.new(pos, vel)
	return sat


# Roll a single meteorite spec. Used by the instantaneous storm path,
# which (unlike the time-distributed wave) has no pre-populated queue
# to draw from. Mirrors the per-body sampling done in
# MeteoriteWave.populate so both spawn paths produce the same kind of
# spread for the same lateral / altitude / velocity bands.
func _sample_meteorite_spec(
	lateral_spread: float,
	altitude_jitter: float,
	vel_jitter: float,
) -> Dictionary:
	var ang := _rng.randf_range(0.0, TAU)
	var dist := _rng.randf_range(0.0, lateral_spread)
	return {
		"t": 0.0,
		"lateral": Vector2(cos(ang) * dist, sin(ang) * dist),
		"alt_offset": _rng.randf_range(-altitude_jitter, altitude_jitter),
		"vel_jitter": Vector3(
			_rng.randf_range(-vel_jitter, vel_jitter),
			_rng.randf_range(-vel_jitter, vel_jitter),
			_rng.randf_range(-vel_jitter, vel_jitter),
		),
	}


func _make_decaying_enemy() -> Satellite:
	var sat := Satellite.new()
	sat.team = Satellite.TEAM_ENEMY
	sat.weapons.clear()
	sat.is_decaying = true
	sat.max_hp = DECAYING_HP
	sat.hp = DECAYING_HP

	var r_p := EarthOrbit.EARTH_RADIUS_KM + DECAYING_PERIGEE_ALT_KM
	var r_a := EarthOrbit.EARTH_RADIUS_KM + DECAYING_APOGEE_ALT_KM
	var a := 0.5 * (r_p + r_a)
	var e := (r_a - r_p) / (r_a + r_p)
	var p_slr := a * (1.0 - e * e)
	# 180° + offset → just past apogee, descending toward perigee.
	var nu := PI + deg_to_rad(DECAYING_INITIAL_NU_FROM_APOGEE_DEG)

	# Random orbital plane: pick an inclination/RAAN/argp triple so each
	# spawn comes in from a different direction. Build perifocal-frame
	# state (perigee along +x_pqw) at the requested true anomaly, then
	# rotate into ECI with the standard 3-1-3 sequence.
	var inc := _rng.randf_range(0.0, PI)
	var raan := _rng.randf_range(0.0, TAU)
	var argp := _rng.randf_range(0.0, TAU)
	var co := cos(raan); var so := sin(raan)
	var ci := cos(inc); var si := sin(inc)
	var cw := cos(argp); var sw := sin(argp)
	var pqw_x := Vector3(co * cw - so * sw * ci,  so * cw + co * sw * ci,  sw * si)
	var pqw_y := Vector3(-co * sw - so * cw * ci, -so * sw + co * cw * ci, cw * si)

	var r_at := p_slr / (1.0 + e * cos(nu))
	var pos := pqw_x * (r_at * cos(nu)) + pqw_y * (r_at * sin(nu))
	# Perifocal velocity from the conic identities: v_p = sqrt(μ/p) * -sin(ν),
	# v_q = sqrt(μ/p) * (e + cos(ν)). Same prograde sense as a normal
	# orbit — at nu just past apogee that means inbound (r·v < 0).
	var v_mag := sqrt(EarthOrbit.MU / p_slr)
	var vel := pqw_x * (-v_mag * sin(nu)) + pqw_y * (v_mag * (e + cos(nu)))
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
