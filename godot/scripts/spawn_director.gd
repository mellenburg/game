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
const Weapon = preload("res://scripts/weapons/weapon.gd")
const LaserWeapon = preload("res://scripts/weapons/laser_weapon.gd")
const RailgunWeapon = preload("res://scripts/weapons/railgun_weapon.gd")
const UnitConfig = preload("res://scripts/unit_config.gd")
const SurfaceUnitConfig = preload("res://scripts/surface_unit_config.gd")
const SurfacePosition = preload("res://scripts/surface_position.gd")
const UnitPart = preload("res://scripts/unit_part.gd")
const Launch = preload("res://scripts/launch.gd")
const WaveUnitClass = preload("res://scripts/wave_unit_class.gd")

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

# Mass-to-HP conversion: 10 kg = 1 HP (i.e. 0.1 HP per kg). Used to
# derive max_hp from a body's spawned mass for both wave meteorites and
# wave-borne decaying-orbit threats so a single dial governs both
# difficulty (HP) and physical scale (3D marker + radar blip).
const HP_PER_KG: float = 0.1

# Size-class mass bands, in kg. The bands are non-overlapping at the
# class boundaries (small max == medium min) so a body's class is a
# function of where its mass was sampled, never an independent label.
const SMALL_MASS_MIN_KG: float = 100.0
const SMALL_MASS_MAX_KG: float = 500.0
const MEDIUM_MASS_MIN_KG: float = 500.0
const MEDIUM_MASS_MAX_KG: float = 1000.0
const LARGE_MASS_MIN_KG: float = 1000.0
const LARGE_MASS_MAX_KG: float = 10000.0

const SIZE_SMALL: int = 0
const SIZE_MEDIUM: int = 1
const SIZE_LARGE: int = 2

# Per-class count bands within a single 20-body wave. The constraint
# that the three counts sum to METEORITE_WAVE_COUNT means the medium
# count is bracketed by the residual after picking large; see
# _sample_size_class_counts for the derivation.
const WAVE_SMALL_COUNT_MIN: int = 8
const WAVE_SMALL_COUNT_MAX: int = 16
const WAVE_MEDIUM_COUNT_MIN: int = 2
const WAVE_MEDIUM_COUNT_MAX: int = 5
const WAVE_LARGE_COUNT_MIN: int = 0
const WAVE_LARGE_COUNT_MAX: int = 3

# Of the medium / large bodies in a wave, this many become decaying-
# orbit threats (highly eccentric, perigee-burn spiral) rather than
# sub-orbital meteorites. Small bodies are always plain meteorites.
const WAVE_DECAYING_COUNT_MIN: int = 4
const WAVE_DECAYING_COUNT_MAX: int = 8

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
# Default mass (kg) for a standalone decaying-orbit spawn — i.e. the
# legacy single-body "add decaying enemy" entry point that the player
# triggers outside of a wave. Sits at the medium / large boundary so
# the body reads as a meaningful threat without overshooting into the
# heaviest large-class band the wave path can produce. Wave-borne
# decaying threats sample their own mass from the medium / large band.
const DECAYING_DEFAULT_MASS_KG: float = 1000.0

# Half-angle of the cone within which a single mission wave's wave-
# units cluster around its base entry direction. ~20° gives a "broad,
# lumpy" group while still reading as one arrival from one quadrant of
# the sky. Each wave-unit is itself a 20-body meteorite wave with its
# own ~7° internal lateral spread, so the visible footprint of a wave
# on radar covers roughly 50° of arc — wide, but unmistakeably one
# coordinated assault rather than scattered noise.
const MISSION_NEXUS_CONE_HALF_ANGLE_DEG: float = 20.0

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


# Spawn the starting fleet. When `launches` is non-empty the player
# configured launches via the pre-game menu — honour each launch's
# assigned unit + orbit. When empty (scene booted directly, no menu)
# fall back to the legacy randomised three-ship spread so existing
# entry points keep working.
#
# Loadout is differentiated per slot so the player has to think about
# fleet composition rather than treating ships as identical; the
# default fallback gives slots 0 and 1 a laser and slot 2 a railgun,
# matching the composition the game shipped with before the menu.
# Replaces Satellite._init's default [Laser, Laser, Railgun] mix on
# the spawned units; the freshly-allocated weapon instances dropped
# here are RefCounted and freed when the array is reassigned.
func spawn_starting_fleet(
	launches: Array[Launch] = [],
	pool: Array[UnitConfig] = [],
) -> void:
	if not launches.is_empty():
		_spawn_from_launches(launches, pool)
		return
	var inc_max := deg_to_rad(STARTING_SAT_INC_MAX_DEG)
	var gap_min := deg_to_rad(STARTING_SAT_NU_GAP_MIN_DEG)
	var gap_max := deg_to_rad(STARTING_SAT_NU_GAP_MAX_DEG)
	var nu := _rng.randf_range(0.0, TAU)
	for i in range(STARTING_SAT_COUNT):
		var sat := Satellite.new()
		sat.unit_name = "T-%02d" % (i + 1)
		sat.orbit = EarthOrbit.make_circular(
			STARTING_SAT_ALT_KM,
			_rng.randf_range(0.0, inc_max),
			_rng.randf_range(0.0, TAU),
			nu,
		)
		sat.weapons = _default_loadout_for(i)
		# Loadout was just reassigned, so the wet-mass total (dry +
		# propellant + ammo) needs a refresh — slot 2's railgun adds
		# a 20 t magazine that Satellite._init's earlier compute has
		# already accounted for, but slots 0/1 (lasers only) need
		# their mass dropped back to the no-ammo case.
		sat.recompute_mass()
		_satellite_container.add_child(sat)
		_satellites.append(sat)
		nu = fposmod(nu + _rng.randf_range(gap_min, gap_max), TAU)


# Materialise the player's scheduled launches. Each Launch references a
# unit by id; we resolve that against the pool and use the unit's
# parts to build the satellite's weapons + tune its energy_max,
# energy_rate, and per-weapon cool multipliers. Launches without an
# assigned unit are skipped — PlayerLoadout.purge_unassigned_launches()
# is expected to have already dropped them, but defensive skip-on-miss
# means a stale/unmatched id won't crash the run.
func _spawn_from_launches(
	launches: Array[Launch], pool: Array[UnitConfig]
) -> void:
	for launch in launches:
		if not launch.has_unit():
			continue
		var unit := _find_unit(pool, launch.unit_id)
		if unit == null:
			continue
		var sat := Satellite.new()
		# Eccentricity-aware: the legacy menu only exposed circular
		# orbits, but the Launch struct now carries `eccentricity` and
		# `argp_deg` so the spawner builds an ellipse when the operator
		# dials them up. Passing ecc=0 / argp=0 reproduces make_circular
		# exactly, which is what every pre-eccentricity save resolves to.
		sat.orbit = EarthOrbit.make_elliptical(
			launch.altitude_km,
			launch.eccentricity,
			deg_to_rad(launch.inclination_deg),
			deg_to_rad(launch.raan_deg),
			deg_to_rad(launch.argp_deg),
			deg_to_rad(launch.true_anomaly_deg),
		)
		_apply_unit_to_satellite(sat, unit)
		_satellite_container.add_child(sat)
		_satellites.append(sat)


func _find_unit(pool: Array[UnitConfig], unit_id: String) -> UnitConfig:
	for unit in pool:
		if unit.id == unit_id:
			return unit
	return null


# Translate a UnitConfig (chassis + parts) into the satellite's
# spawn-time fields:
#   * weapons: one Weapon per filled weapon slot, with damage / cool
#     multipliers driven by that weapon's tier and the satellite's
#     aggregate radiator multiplier.
#   * energy_max: storage parts' total multiplier × default
#     DEFAULT_ENERGY_MAX_J (default tier with one slot ⇒ 1× default;
#     advanced tier ⇒ 2×).
#   * reactor_power_w: same logic against the reactor row.
# A unit whose storage / reactor row is empty contributes zero to that
# facet, which is intentional: a unit with no reactor cannot recharge.
func _apply_unit_to_satellite(sat: Satellite, unit: UnitConfig) -> void:
	var radiator_mult := unit.total_multiplier_for_kind(UnitPart.KIND_RADIATOR)
	var storage_mult := unit.total_multiplier_for_kind(UnitPart.KIND_ENERGY_STORAGE)
	var reactor_mult := unit.total_multiplier_for_kind(UnitPart.KIND_REACTOR)
	sat.unit_name = unit.name
	sat.energy_max = Satellite.DEFAULT_ENERGY_MAX_J * storage_mult
	sat.reactor_power_w = Satellite.DEFAULT_REACTOR_POWER_W * reactor_mult
	sat.weapons = _build_weapons(unit, radiator_mult)
	# Propulsion: seed thrust / Isp / propellant from the unit's
	# thruster row. Units with an empty thruster row (saved from a
	# pre-thruster build) collapse to zero capacity, which leaves the
	# satellite unable to maneuver — by design; the operator should
	# fit a thruster part to make the unit mobile. Wet mass is
	# dry + propellant + ammo so railgun recoil math sees the same
	# number a fully-fueled, fully-loaded unit carries into orbit.
	sat.thrust_n = unit.total_thrust_n()
	sat.isp_s = unit.effective_isp_s()
	sat.max_propellant_kg = unit.total_propellant_capacity_kg()
	sat.propellant_kg = sat.max_propellant_kg
	sat.dry_mass_kg = Satellite.DEFAULT_DRY_MASS_KG
	sat.recompute_mass()


# Translate the unit's weapon-slot row into a Weapon array, applying
# the satellite's aggregate radiator multiplier to each weapon's
# cool_mult so the cooldown speedup is felt by every gun the unit
# carries. Empty / unknown weapon parts are skipped — a slot the player
# explicitly left unfilled stays unfilled.
func _build_weapons(unit: UnitConfig, radiator_mult: float) -> Array[Weapon]:
	var out: Array[Weapon] = []
	for part_id in unit.weapon_part_ids:
		var part := UnitPart.get_by_id(part_id)
		if part.kind != UnitPart.KIND_WEAPON or part.weapon_class == "":
			continue
		var w: Weapon = null
		match part.weapon_class:
			UnitPart.WCLASS_LASER:
				var laser := LaserWeapon.new()
				laser.damage_mult = part.multiplier
				# Radiator complement defines the weapon's cooling rate
				# directly. Per-class baseline × aggregate radiator mult
				# means a unit with one default radiator cools at the
				# pre-parts speed; an advanced radiator (or two) cools
				# proportionally faster.
				laser.cool_rate = LaserWeapon.COOL_PER_SEC * radiator_mult
				w = laser
			UnitPart.WCLASS_RAILGUN:
				var railgun := RailgunWeapon.new()
				railgun.damage_mult = part.multiplier
				railgun.cool_rate = RailgunWeapon.COOL_PER_SEC * radiator_mult
				w = railgun
		if w != null:
			out.append(w)
	return out


# Per-slot weapon loadout for the legacy randomised starting fleet.
# Slots 0 and 1 get a laser, slot 2 gets a railgun. Returning a fresh
# array per call so every ship gets independent weapon instances
# (cooldown / heat state is per-weapon, not shared).
func _default_loadout_for(index: int) -> Array[Weapon]:
	if index >= 2:
		return [RailgunWeapon.new()] as Array[Weapon]
	return [LaserWeapon.new()] as Array[Weapon]


# Spawn the player's configured surface installations. `earth_phase`
# at spawn time is taken from the EarthSystem so the very first frame
# already has the units sitting on the right ECI position; subsequent
# frames are driven by Satellite.update_surface_position from the
# physics tick. Empty `configs` is a no-op — surface units are entirely
# opt-in and the legacy direct-boot path leaves them empty.
func spawn_surface_units(
	configs: Array[SurfaceUnitConfig], earth_phase: float
) -> void:
	for cfg in configs:
		var sat := Satellite.new()
		sat.team = Satellite.TEAM_PLAYER
		sat.is_surface = true
		sat.unit_name = cfg.name
		sat.surface_lat_deg = cfg.lat_deg
		sat.surface_lon_deg = cfg.lon_deg
		sat.max_hp = cfg.max_hp
		sat.hp = cfg.max_hp
		sat.mass = cfg.mass_kg
		sat.weapons = _surface_weapons_for_kind(cfg.weapon_kind)
		# Seed orbit with the spawn-tick surface position so the first
		# render frame draws the marker on the ground rather than at
		# Satellite._init's DEFAULT_R far above LEO. update_surface_position
		# overwrites this each physics tick.
		var radius := EarthOrbit.EARTH_RADIUS_KM + Satellite.SURFACE_UNIT_ALTITUDE_KM
		var pos := SurfacePosition.latlon_to_eci(
			cfg.lat_deg, cfg.lon_deg, earth_phase, radius
		)
		sat.orbit = EarthOrbit.new(pos, Vector3(0.0, 0.0, 1.0e-3))
		_satellite_container.add_child(sat)
		_satellites.append(sat)


# Surface installations are laser-only in the MVP (see
# SurfaceUnitConfig comments for why). Returns a fresh array per call
# so each unit gets its own per-weapon heat / overheat state. The
# laser is built bare — surface units don't carry a parts loadout, so
# damage / cooling stay at the LaserWeapon class baselines.
func _surface_weapons_for_kind(weapon_kind: int) -> Array[Weapon]:
	# SurfaceUnitConfig.WEAPON_LASER == 0; the match is here so adding
	# a second surface weapon kind later is a one-line edit.
	match weapon_kind:
		_:
			return [LaserWeapon.new()] as Array[Weapon]


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


# Begin a 10-second wave: 20 meteorites all sharing one random sub-
# orbital nexus, individual spawn delays drawn uniformly across the
# window so arrivals are spread out rather than bursty. Each body's
# size class (small / medium / large) and mass are sampled up front
# per _sample_wave_specs; 4-8 of the medium / large slots are flipped
# to decaying-orbit threats, which spawn on their own random elliptical
# planes when their timer expires (the wave nexus only governs the
# sub-orbital meteorite path). Multiple waves can overlap; each gets
# its own MeteoriteWave entry.
func start_meteorite_wave(
	count: int = METEORITE_WAVE_COUNT,
	duration_sec: float = METEORITE_WAVE_DURATION_SEC,
	preroll_sec: float = METEORITE_WAVE_PREROLL_SEC,
) -> void:
	_emit_meteorite_wave(_random_unit_vector(), count, duration_sec, preroll_sec)


# Begin a meteorite wave whose entry direction is jittered around a
# caller-supplied base. The base is the per-mission-wave anchor; the
# perturbation is sampled inside MISSION_NEXUS_CONE_HALF_ANGLE so every
# wave-unit in a single mission wave lands inside one solid-angle
# patch — the "broad lumpy group from one quadrant of the sky" the
# brief calls for. Composition / preroll / spawn-window match the
# default `start_meteorite_wave` so each wave-unit is a full 20-body
# burst, indistinguishable from one the I keybind would produce.
func start_meteorite_wave_clustered(base_r_hat: Vector3) -> void:
	var perturbed := _perturb_unit_vector(
		base_r_hat, deg_to_rad(MISSION_NEXUS_CONE_HALF_ANGLE_DEG)
	)
	_emit_meteorite_wave(
		perturbed,
		METEORITE_WAVE_COUNT,
		METEORITE_WAVE_DURATION_SEC,
		METEORITE_WAVE_PREROLL_SEC,
	)


# Sample a uniform-on-sphere unit vector. Public so the mission scheduler
# in EarthSystem can fix a fresh per-wave base direction without having
# to mint its own RNG — keeps every wave-related random draw on the one
# seeded RNG this director owns.
func sample_unit_vector() -> Vector3:
	return _random_unit_vector()


# Begin a meteorite wave driven by a WaveUnitClass: object count, the
# decaying-orbit ratio, the per-object size mix, the time spread, and
# the location-arc spread all come from the class's range / barycentric
# fields. `count_override` lets Mission pre-sample and cap object
# counts (so the per-wave 250-body ceiling holds across siblings); a
# negative value keeps the legacy behaviour of resampling from the
# class's count range here. Preroll stays fixed at the class's lead-
# time default — the radar overlay needs the 10 s scroll-in window
# regardless of how short the spawn burst itself is.
func start_wave_unit_clustered(
	base_r_hat: Vector3,
	unit_class: WaveUnitClass,
	count_override: int = -1,
) -> void:
	if unit_class == null:
		start_meteorite_wave_clustered(base_r_hat)
		return
	var perturbed := _perturb_unit_vector(
		base_r_hat, deg_to_rad(MISSION_NEXUS_CONE_HALF_ANGLE_DEG)
	)
	var count: int
	if count_override >= 0:
		count = count_override
	else:
		count = unit_class.sample_count(_rng)
	var decaying_ratio := unit_class.sample_decaying_ratio(_rng)
	var wave := _build_meteorite_wave_at_nexus(perturbed)
	var spread_km := unit_class.lateral_spread_for_altitude(wave.base_altitude)
	var duration_sec := unit_class.time_spread_sec
	var specs := _sample_class_wave_specs(
		count,
		decaying_ratio,
		unit_class,
		duration_sec,
		METEORITE_WAVE_PREROLL_SEC,
		spread_km,
	)
	wave.set_specs(specs, duration_sec, spread_km)
	meteorite_waves.append(wave)
	if _threat_alert != null:
		_threat_alert.trigger()


# Build per-object specs for a class-driven wave-unit. Object size
# bands come from the class's barycentric weights (largest-remainder
# rounded so the three counts always sum to `count` exactly); the
# decaying-orbit subset is a uniform-random pick of `round(count *
# decaying_ratio)` slots across the *whole* spec list — unlike the
# legacy 20-body wave (which restricted decaying to medium/large), a
# class-driven wave can pour decaying threats onto any size.
func _sample_class_wave_specs(
	count: int,
	decaying_ratio: float,
	unit_class: WaveUnitClass,
	duration_sec: float,
	preroll_sec: float,
	lateral_spread_km: float,
) -> Array[Dictionary]:
	var specs: Array[Dictionary] = []
	if count <= 0:
		return specs
	var bands := unit_class.sample_object_size_counts(count)
	var sizes: Array[int] = []
	for _i in range(int(bands["small"])):
		sizes.append(SIZE_SMALL)
	for _i in range(int(bands["medium"])):
		sizes.append(SIZE_MEDIUM)
	for _i in range(int(bands["large"])):
		sizes.append(SIZE_LARGE)
	_shuffle_int_array(sizes)
	# Decaying-slot picks are independent of size — the class's
	# decaying ratio governs the overall share, not the heavy-body
	# subset like the legacy wave did.
	var n_decaying := clampi(
		int(round(float(count) * decaying_ratio)), 0, count
	)
	var indices: Array[int] = []
	for i in range(count):
		indices.append(i)
	_shuffle_int_array(indices)
	var decaying_set := {}
	for i in range(n_decaying):
		decaying_set[indices[i]] = true
	for i in range(count):
		var size_class: int = sizes[i]
		var mass := _sample_mass_for_class(size_class)
		specs.append(_make_wave_spec(
			mass, decaying_set.has(i), duration_sec, preroll_sec,
			lateral_spread_km,
		))
	return specs


# Internal: shared body of `start_meteorite_wave` (random nexus) and
# `start_meteorite_wave_clustered` (caller-supplied + jittered nexus).
# The two paths only differ in how `r_hat` is chosen; the rest of the
# wave construction (mass mix, decaying-orbit subset, threat alert) is
# identical so both produce the same wave shape downstream.
func _emit_meteorite_wave(
	r_hat: Vector3, count: int, duration_sec: float, preroll_sec: float
) -> void:
	var wave := _build_meteorite_wave_at_nexus(r_hat)
	var specs := _sample_wave_specs(count, duration_sec, preroll_sec)
	wave.set_specs(specs, duration_sec, METEORITE_LATERAL_SPREAD_KM)
	meteorite_waves.append(wave)
	if _threat_alert != null:
		_threat_alert.trigger()


# Rotate `base` by a uniform random angle in [0, max_angle_rad] around
# a uniform random axis perpendicular to it. The result is a unit vector
# inside the spherical cap of half-angle `max_angle_rad` centered on
# `base`. Uniform-in-angle (rather than uniform-in-solid-angle) is
# intentional: the bias toward the cone's edge reads visually as a
# "lumpy" cluster — wave-units pile near the rim of the patch — which
# is the look the mission brief asks for.
func _perturb_unit_vector(base: Vector3, max_angle_rad: float) -> Vector3:
	var axis := _random_perpendicular_unit(base.normalized())
	var angle := _rng.randf_range(0.0, max_angle_rad)
	return base.normalized().rotated(axis, angle).normalized()


# Build the full 20-spec mix for a single wave: pick the size-class
# count distribution, allocate decaying-orbit slots from the medium /
# large indices, then sample per-body fields (timer, lateral, mass).
# Returns a typed array of pending dicts ready to drop into
# MeteoriteWave.set_specs.
func _sample_wave_specs(
	count: int, duration_sec: float, preroll_sec: float
) -> Array[Dictionary]:
	var counts := _sample_size_class_counts(count)
	var n_small: int = counts["small"]
	var n_medium: int = counts["medium"]
	var n_large: int = counts["large"]
	var sizes: Array[int] = []
	for _i in range(n_small):
		sizes.append(SIZE_SMALL)
	for _i in range(n_medium):
		sizes.append(SIZE_MEDIUM)
	for _i in range(n_large):
		sizes.append(SIZE_LARGE)
	_shuffle_int_array(sizes)

	# Flag a random subset of the medium / large indices as decaying.
	# Small bodies are always plain meteorites (per the design), so the
	# decaying picks are restricted to the heavier slots.
	var heavy_indices: Array[int] = []
	for i in range(sizes.size()):
		if sizes[i] != SIZE_SMALL:
			heavy_indices.append(i)
	_shuffle_int_array(heavy_indices)
	var d_max := mini(WAVE_DECAYING_COUNT_MAX, heavy_indices.size())
	var d_min := mini(WAVE_DECAYING_COUNT_MIN, heavy_indices.size())
	var d_count := _rng.randi_range(d_min, d_max)
	var decaying_set := {}
	for i in range(d_count):
		decaying_set[heavy_indices[i]] = true

	var specs: Array[Dictionary] = []
	for i in range(sizes.size()):
		var size_class: int = sizes[i]
		var mass := _sample_mass_for_class(size_class)
		specs.append(_make_wave_spec(
			mass, decaying_set.has(i), duration_sec, preroll_sec
		))
	return specs


# Pick a (small, medium, large) triple summing to `total`, with each
# count constrained to its WAVE_*_COUNT_MIN/MAX band. Derivation:
#   small = total - medium - large
#   small ∈ [SMIN, SMAX]
#     ⇒ medium + large ∈ [total - SMAX, total - SMIN]
# Pick large first inside its own band, then medium inside the
# residual band intersected with its own. With the design constants
# (8..16 / 2..5 / 0..3 / total=20) this always has a non-empty
# medium range; the maxi/mini are belt-and-braces in case the bands
# are retuned later.
func _sample_size_class_counts(total: int) -> Dictionary:
	var large := _rng.randi_range(WAVE_LARGE_COUNT_MIN, WAVE_LARGE_COUNT_MAX)
	var med_min := maxi(WAVE_MEDIUM_COUNT_MIN, total - WAVE_SMALL_COUNT_MAX - large)
	var med_max := mini(WAVE_MEDIUM_COUNT_MAX, total - WAVE_SMALL_COUNT_MIN - large)
	if med_max < med_min:
		med_max = med_min
	var medium := _rng.randi_range(med_min, med_max)
	var small := total - medium - large
	return {"small": small, "medium": medium, "large": large}


func _sample_mass_for_class(size_class: int) -> float:
	match size_class:
		SIZE_SMALL:
			return _rng.randf_range(SMALL_MASS_MIN_KG, SMALL_MASS_MAX_KG)
		SIZE_MEDIUM:
			return _rng.randf_range(MEDIUM_MASS_MIN_KG, MEDIUM_MASS_MAX_KG)
		_:
			return _rng.randf_range(LARGE_MASS_MIN_KG, LARGE_MASS_MAX_KG)


# Build a single pending spec. Lateral / altitude / velocity jitter are
# sampled the same way as the legacy populate() path so the meteorite
# branch keeps producing the same kind of cluster spread; decaying
# specs get the same fields just so the radar overlay has a position
# to plot for them while the spawn-time geometry uses an independent
# random plane per body (see _make_decaying_enemy).
func _make_wave_spec(
	mass: float,
	is_decaying: bool,
	duration_sec: float,
	preroll_sec: float,
	lateral_spread_km: float = METEORITE_LATERAL_SPREAD_KM,
) -> Dictionary:
	var ang := _rng.randf_range(0.0, TAU)
	var dist := _rng.randf_range(0.0, lateral_spread_km)
	return {
		"t": _rng.randf_range(0.0, duration_sec) + preroll_sec,
		"lateral": Vector2(cos(ang) * dist, sin(ang) * dist),
		"alt_offset": _rng.randf_range(
			-METEORITE_ALT_JITTER_KM, METEORITE_ALT_JITTER_KM
		),
		"vel_jitter": Vector3(
			_rng.randf_range(-METEORITE_VELOCITY_JITTER, METEORITE_VELOCITY_JITTER),
			_rng.randf_range(-METEORITE_VELOCITY_JITTER, METEORITE_VELOCITY_JITTER),
			_rng.randf_range(-METEORITE_VELOCITY_JITTER, METEORITE_VELOCITY_JITTER),
		),
		"mass": mass,
		"is_decaying": is_decaying,
	}


# Fisher-Yates shuffle driven by the spawn director's seeded RNG so
# wave layouts are reproducible from the same seed. Array.shuffle()
# uses Godot's process-global RNG, which would defeat that property.
func _shuffle_int_array(arr: Array[int]) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp: int = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


# Spawn a single decaying-orbit enemy. Highly eccentric, spawned just
# past apogee on the descending leg. The body falls toward perigee,
# gets a retrograde momentum kick at each perigee that halves r_a (the
# orbit spirals inward), and eventually one of those kicks pushes the
# trailing apsis below the surface — body impacts on its next descent.
func add_decaying_enemy() -> void:
	var sat := _make_decaying_enemy(DECAYING_DEFAULT_MASS_KG)
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
			var mass: float = spec.get("mass", Satellite.DEFAULT_MASS_KG)
			var sat: Satellite
			if spec.get("is_decaying", false):
				# Decaying-orbit threats live on their own random
				# elliptical plane; the wave's shared sub-orbital nexus
				# doesn't apply to them. Lateral / vel-jitter from the
				# spec is only consumed by the radar preview.
				sat = _make_decaying_enemy(mass)
			else:
				sat = _make_meteorite(
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
	return _build_meteorite_wave_at_nexus(_random_unit_vector())


# Build a meteorite wave whose entry direction is the supplied unit
# vector. Tangent / altitude / velocity remain randomised — the caller
# only locks the radial axis of the cluster, not its in-plane shape.
func _build_meteorite_wave_at_nexus(r_hat: Vector3) -> MeteoriteWave:
	var wave := MeteoriteWave.new()
	wave.r_hat = r_hat.normalized()
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
	# Mass drives both HP (10 kg = 1 HP) and the visual scale (3D
	# marker, radar blip), keeping difficulty and physical size on a
	# single dial. Specs from the legacy storm path don't carry mass;
	# fall back to the satellite's default to keep that branch working.
	var mass: float = spec.get("mass", Satellite.DEFAULT_MASS_KG)
	sat.mass = mass
	sat.max_hp = mass * HP_PER_KG
	sat.hp = sat.max_hp

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
# spread for the same lateral / altitude / velocity bands. Storm bodies
# fall in the small mass class — the storm is the cheap-and-cheerful
# threat; the wave path is where heavier meteorites and decaying-orbit
# bodies show up.
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
		"mass": _sample_mass_for_class(SIZE_SMALL),
		"is_decaying": false,
	}


func _make_decaying_enemy(mass: float) -> Satellite:
	var sat := Satellite.new()
	sat.team = Satellite.TEAM_ENEMY
	sat.weapons.clear()
	sat.is_decaying = true
	# Mass-driven HP keeps the spiral-in threat consistent with the rest
	# of the wave: a heavier body soaks more shots before going down.
	sat.mass = mass
	sat.max_hp = mass * HP_PER_KG
	sat.hp = sat.max_hp

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
