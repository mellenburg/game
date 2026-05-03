class_name Satellite
extends Node3D
## A spacecraft: orbital state, marker mesh, orbit path, hit points, and
## an optional weapon. Marker mesh and material are created once in
## _ready(); selection / damage just toggles the cached material's
## albedo_color.

const EarthOrbit = preload("res://scripts/earth_orbit.gd")
const OrbitalPath = preload("res://scripts/orbital_path.gd")
const Weapon = preload("res://scripts/weapons/weapon.gd")
const LaserWeapon = preload("res://scripts/weapons/laser_weapon.gd")
const RailgunWeapon = preload("res://scripts/weapons/railgun_weapon.gd")
const SurfacePosition = preload("res://scripts/surface_position.gd")
const Propulsion = preload("res://scripts/propulsion.gd")

const TEAM_PLAYER: int = 0
const TEAM_ENEMY: int = 1

const SCENE_SCALE: float = 1.0 / 1000.0
# Base side length (in scene units) of the cube marker used for a
# DEFAULT_MASS_KG body. Heavier bodies scale this by mass^(1/3) so the
# rendered volume tracks mass linearly; lighter bodies shrink the same
# way. Sized to match the historical 0.15-cube look at the default
# 1000 kg reference.
const MARKER_BASE_SIZE: float = 0.15
const MARKER_REFERENCE_MASS_KG: float = 1000.0
const DEFAULT_R := Vector3(-6045.0, -3490.0, 2500.0)
const DEFAULT_V := Vector3(-3.56, 6.618, 2.533)
const DELTA_V_MAGNITUDE: float = 0.050
const COLOR_SELECTED := Color(0.2, 1.0, 0.2)
const COLOR_PLAYER := Color(0.4, 0.6, 1.0)
const COLOR_ENEMY := Color(1.0, 0.35, 0.35)
const COLOR_METEORITE := Color(1.0, 0.85, 0.4)
const COLOR_DECAYING := Color(0.95, 0.45, 0.95)
const COLOR_HIT := Color(1.0, 0.25, 0.05)
# Enemy orbit-line gradient endpoints. Yellow when the body is far from
# (or never going to make) ground impact; red when impact is imminent.
# The marker still uses the team / type colors above — only the orbital
# path is affected so a glance at the line conveys urgency without
# re-tinting the body itself.
const COLOR_ENEMY_PATH_FAR := Color(1.0, 0.95, 0.25)
const COLOR_ENEMY_PATH_NEAR := Color(1.0, 0.2, 0.15)
# ETA bounds for the enemy-path gradient. <= NEAR seconds reads as full
# red; >= FAR seconds (or non-impacting orbits, where eta == INF) reads
# as full yellow. The window between is square-rooted to bias the color
# toward red — meteorites spawn 40-70k km out with naive ttf running
# 5000-8000 s, so a linear ramp would leave them visually yellow for
# the entire descent. The sqrt curve lifts mid-flight bodies into
# orange / red while still leaving stable orbits (eta == INF) at full
# yellow and decaying threats yellow → red across their multi-hour
# spiral.
const ENEMY_PATH_ETA_RED_S: float = 60.0
const ENEMY_PATH_ETA_YELLOW_S: float = 7200.0
# HP-driven path-style envelope. The line's *initial* thickness and
# opacity are baked from max_hp at spawn (or clone) time and never
# updated as the body takes damage — by design, per the original spec.
# Values picked so a small meteorite (~10 HP) is barely-visible-thin
# and a large decaying threat (~1000 HP) draws as a solid bold ribbon.
const ENEMY_PATH_HP_LOG_BASE: float = 1000.0
const ENEMY_PATH_WIDTH_MIN_PX: float = 0.75
const ENEMY_PATH_WIDTH_MAX_PX: float = 5.0
const ENEMY_PATH_ALPHA_MIN: float = 0.2
const ENEMY_PATH_ALPHA_MAX: float = 1.0
# Player paths don't carry HP semantics on the line — players read HP
# off their own roster. Use a constant readable thickness + full
# opacity so the operator's own orbits stay legible.
const PLAYER_PATH_WIDTH_PX: float = 1.5
# Surface installations: yellow-green tint, distinct from the orbital
# blue + selected green so a glance at the 3D view (or the in-game HUD
# roster) tells the player which units are anchored to the ground.
const COLOR_SURFACE := Color(0.85, 1.0, 0.30)
# Antenna offset above the Earth radius, in km. A few-km cushion keeps
# the LOS check (which fails closed when start.length²==EARTH_RADIUS²
# due to a degenerate quadratic) from refusing every shot a surface
# unit could legitimately make. Same scale as SAFE_PERIAPSIS_KM's 1 km
# margin — small enough to read as "on the ground", large enough that
# the LOS-vs-sphere math has clear room to work in.
const SURFACE_UNIT_ALTITUDE_KM: float = 5.0
# Finite-difference epsilon (in earth_phase radians) for surface-unit
# velocity sampling. 1e-4 rad ≈ 1.4 s of sidereal rotation — small
# enough that the difference is a faithful tangent, large enough that
# 32-bit Vector3 component precision in (pos_next - pos) doesn't
# collapse the result to zero.
const SURFACE_PHASE_EPS: float = 1.0e-4
const SURFACE_SIDEREAL_DAY_SEC: float = 86164.0

const MAX_HP: float = 100.0
# Default unit mass (kg). Distinct from hit points — used by the
# railgun's momentum-transfer math: the impulse delivered to shooter
# (recoil) and target (push) is fixed in (kg·km/s) and divided by the
# unit's mass to yield the resulting Δv. Player satellites and unarmed
# enemy sats default to a wet mass of DEFAULT_DRY_MASS_KG +
# DEFAULT_PROPELLANT_KG, which sums to this value; meteorite / decaying
# spawners set their own mass via spawn_director.
const DEFAULT_MASS_KG: float = 1000.0
# Dry-mass / propellant split for the default unit. Sums to
# DEFAULT_MASS_KG so railgun recoil math (which reads `mass`)
# preserves its existing balance for a fully-fueled unit. As the unit
# burns propellant, `mass` drops toward DEFAULT_DRY_MASS_KG, which is
# physically correct (lighter rockets recoil more).
const DEFAULT_DRY_MASS_KG: float = 700.0
const DEFAULT_PROPELLANT_KG: float = 300.0
# Specific impulse and thrust of the default thruster part — kept in
# sync with UnitPart.make_thruster's "thruster_default" entry so a unit
# spawned through the legacy fallback path (no UnitConfig) and one
# spawned via the menu loadout end up with identical propulsion.
const DEFAULT_ISP_S: float = 300.0
const DEFAULT_THRUST_N: float = 20000.0
# Default operator-set cap on the shooter's post-recoil orbital radius.
# 50 000 km matches the design spec: large enough that a few shots
# barely shift orbit, small enough that a long railgun engagement
# eventually self-limits before the shooter drifts out to GEO+. Pure
# game-balance number; players can tune it in flight.
const DEFAULT_MAX_ORBITAL_RADIUS_KM: float = 50000.0
# Player thrust is clamped each tick so the resulting orbit's periapsis
# stays at or above this radius. Sits a hair above EARTH_RADIUS_KM so
# floating-point slop in the propagator can't tip the body across the
# surface termination check.
const SAFE_PERIAPSIS_KM: float = EarthOrbit.EARTH_RADIUS_KM + 1.0
# Defaults for the energy reservoir + reactor regen. Per-instance
# `energy_max` and `energy_rate_per_sim_sec` start at these values and
# are scaled at spawn time by the unit's energy-storage / reactor parts
# (advanced parts double the corresponding facet). Constants kept on
# the class so existing tests / callers that read the default still
# resolve cleanly.
const ENERGY_MAX: float = 1.0
# Fraction of the energy pool gained per simulated second. Doubled
# from the prior 0.00007 to compensate for the halved per-shot cost
# and the fact that two lasers share one reservoir.
const ENERGY_RATE_PER_SIM_SEC: float = 0.00014

var orbit: EarthOrbit
var selected: bool = false
var raw_maneuver := Vector3.ZERO
var did_maneuver: bool = false
var orbit_alive: bool = true

var team: int = TEAM_PLAYER
# Operator-facing display name. Set by SpawnDirector at spawn time
# (mirroring the Hangar's UnitConfig.name); the HUD roster renders this
# in the unit box and the end-of-run summary keys per-unit stats by
# it. Empty string for unnamed bodies (enemies, meteorites, decaying
# threats) so the HUD knows to skip the name row.
var unit_name: String = ""
# Per-instance HP cap. Defaults to MAX_HP for player / standard enemy
# satellites; threat-spawning paths (meteorite, decaying-orbit body)
# override it with their own cap and seed `hp` to the same value.
var max_hp: float = MAX_HP
var hp: float = MAX_HP
# Cumulative damage this satellite has dealt across the run. Updated
# when an attacker's weapon successfully fires — take_damage attributes
# the actual applied amount to the attacker passed in. The end-of-run
# summary reads this directly.
var damage_dealt: float = 0.0
# Number of enemies this satellite has finished off (dealt the killing
# blow against). Incremented by take_damage when the attacker's hit
# brings the target to 0 HP. Surface units and orbital ships share the
# same counter — both count as "kills" for the unit summary.
var kills: int = 0
# Per-instance mass (kg). Tracks the unit's *wet* mass — dry structure
# plus current propellant — and is updated downward as burns drain
# propellant_kg. Used by the railgun's momentum-transfer math (a lighter
# stage recoils more, which is physically correct) and by Tsiolkovsky
# when computing per-burn propellant cost. Spawners override for
# heavier (decaying-orbit) or fragile (meteorite) bodies, which never
# enter the propellant-aware maneuver branch and so don't track
# dry/propellant separately.
var mass: float = DEFAULT_MASS_KG
# Dry mass and onboard propellant. Player thrust debits propellant_kg
# per burn via Tsiolkovsky; once it hits zero the maneuver branch
# clamps the requested Δv down to whatever the remaining tank can
# deliver (often zero). Non-player bodies keep these at their defaults
# but never use them — only the did_maneuver path reads propellant_kg.
var dry_mass_kg: float = DEFAULT_DRY_MASS_KG
var propellant_kg: float = DEFAULT_PROPELLANT_KG
var max_propellant_kg: float = DEFAULT_PROPELLANT_KG
# Onboard thruster facets. isp_s feeds Tsiolkovsky; thrust_n is the
# instantaneous force the unit can apply, surfaced on the HUD and
# reserved for future TWR-gated abilities (surface launch, fast
# intercept). Defaults match UnitPart.make_thruster's "thruster_default".
var isp_s: float = DEFAULT_ISP_S
var thrust_n: float = DEFAULT_THRUST_N
var alive: bool = true
# Sub-orbital trajectory (a meteorite) — its periapsis is below Earth's
# surface by construction, so it impacts ground in finite time. Used to
# suppress the orbit-path visual (a meaningless ellipse clipping through
# Earth) and to terminate the entity on ground contact.
var is_meteorite: bool = false
# Decaying-orbit enemy: spawned just past apogee on a highly eccentric
# ellipse, descending. Each perigee crossing fires a retrograde burn
# that halves r_a, so the orbit spirals inward; once the burn drops
# the trailing apsis below the surface the body impacts on its next
# descending leg. Drives both the burn step in advance_time and the
# render dispatch (full ellipse while r_p ≥ R, truncated trajectory
# once r_p dips below the surface).
var is_decaying: bool = false
# Surface installation: anchored to a point on Earth's surface, rotating
# with the planet's daily phase rather than following Keplerian motion.
# EarthSystem detects the flag in _physics_process and skips advance_time
# in favour of update_surface_position(earth_phase) — orbit.r is
# rewritten each tick from (lat, lon) so combat / LOS / range queries
# (which all read attacker.orbit.r) keep working without any additional
# special-casing in the weapon strategies.
var is_surface: bool = false
var surface_lat_deg: float = 0.0
var surface_lon_deg: float = 0.0
# Shared energy reservoir, drained by every weapon's fire(). Charges
# at energy_rate_per_sim_sec per simulated second so time_factor
# scales it the same as everything else. `energy_max` and
# `energy_rate_per_sim_sec` are overridden at spawn time per-unit by
# SpawnDirector based on the operator's chosen energy-storage and
# reactor parts.
var energy: float = 0.0
var energy_max: float = ENERGY_MAX
var energy_rate_per_sim_sec: float = ENERGY_RATE_PER_SIM_SEC
# Empty for unarmed units (e.g. enemies in the MVP). Player satellites
# spawn with two lasers; weapons fire independently but share energy.
var weapons: Array[Weapon] = []
# Operator-set cap on weapon engagement distance (km). Honored by the
# laser only while fire_control_active is true — turning fire control
# off restores default "fire at any LOS enemy out to MAX_RANGE_KM"
# behaviour without forcing the operator to widen the slider back up
# first. Defaults to LaserWeapon.MAX_RANGE_KM so a freshly-toggled-on
# fire control mode doesn't immediately silence the weapon.
var engagement_range_km: float = LaserWeapon.MAX_RANGE_KM
# Fire-control mode toggle. While active, the operator can adjust
# engagement_range_km (Shift+Up/Down), see the range circle (Shift),
# and the laser obeys the cap. Toggled off, the cap is dropped and
# the weapon reverts to default LOS-only firing — but the saved
# engagement_range_km value is preserved so re-toggling fire control
# brings the same setting back.
var fire_control_active: bool = false
# Per-ship laser targeting mode. Honored by LaserWeapon.pick_target
# when selecting which in-envelope enemy each weapon will fire at this
# tick. Cloned across planning satellites so the planning view shows
# the same auto-targeting choice the live simulation will make. Stored
# on the satellite (not the weapon) because all of a ship's lasers
# share the same operator setting, even though the constants live on
# LaserWeapon as the strategy that consumes them.
var targeting_mode: int = LaserWeapon.TARGETING_MAX_DAMAGE
# Operator-set cap on the shooter's post-recoil apoapsis (km). The
# railgun's pre-fire safety check refuses any shot whose recoil would
# push apoapsis past this radius; floor is hard-coded at
# RailgunWeapon.SAFE_PERIAPSIS_KM (no slider) to keep the post-shot
# orbit above the upper atmosphere. Adjusted in-flight via
# Shift+Left/Right.
var max_orbital_radius_km: float = DEFAULT_MAX_ORBITAL_RADIUS_KM
# Fleet-wide (toggled together via X) gate on whether the railgun is
# allowed to fire at all. Default on so a fresh game has railguns
# active; press X to silence the entire fleet's railguns when the
# operator wants to preserve momentum / energy. Stored per-satellite so
# the weapon strategy (which only sees its attacker) can read a single
# field; EarthSystem._toggle_railgun_on_all keeps the flag consistent
# across player units.
var railgun_enabled: bool = true

# Cached absolute simulated time at which this body's current
# trajectory crosses Earth's surface. NAN means "unknown — compute on
# next access"; INF means "no impact within the propagator's horizon"
# (which collapses to "never" for an orbit that won't be perturbed);
# any finite value is in the same sim-clock frame EarthSystem.sim_time
# advances. Storing the *absolute* impact time means free propagation
# never has to update it — the body moves through time but the
# impact instant doesn't. Maneuvers / perigee burns invalidate it
# because they actually change the orbit.
#
# Horizon at cache fill is generous (one day) so meteorites spawned at
# the high end of the storm shell — where naive ttf can run > 7000 sec
# — still resolve to a real number rather than INF. The propagation is
# paid once per spawn (or per maneuver); in normal play each body
# computes its impact time exactly once before being shot down or
# impacting.
const IMPACT_CACHE_HORIZON_SEC: float = 86400.0
const IMPACT_CACHE_STEP_SEC: float = 60.0
var impact_sim_time: float = NAN

# Wall-clock timestamp at which the orange "I got hit" tint reverts to
# the team color. Wall-clock so the pulse is visible regardless of how
# compressed time_factor makes sim seconds.
var _flash_until: float = 0.0

var _marker: MeshInstance3D
var _marker_mat: StandardMaterial3D
var path_visual: OrbitalPath
# Initial-HP-derived alpha for the orbit ribbon. Set once at spawn (or
# clone) in _apply_path_style and read by _path_color so per-tick tint
# updates don't drift the opacity. Stored separately from the
# material's color uniform because selection (which forces full-alpha
# green) would otherwise overwrite it.
var _path_alpha: float = 1.0


func _init() -> void:
	orbit = EarthOrbit.new(DEFAULT_R, DEFAULT_V)
	# Player loadout: two lasers (continuous-fire) plus a single railgun
	# (impulse, momentum-conserving). Lasers sit first so their HUD
	# bars line up with prior screenshots; the railgun bar tails the
	# strip. Spawners that build unarmed enemies clear the array.
	weapons = [LaserWeapon.new(), LaserWeapon.new(), RailgunWeapon.new()]


## Charge the shared energy pool. Per-weapon cooling is driven by
## CombatController.process_combat — only weapons that did NOT fire this
## tick get their tick() called, since fire() handles its own heat
## bookkeeping.
func tick_combat(sim_delta: float) -> void:
	if sim_delta <= 0.0:
		return
	energy = clampf(
		energy + energy_rate_per_sim_sec * sim_delta, 0.0, energy_max,
	)


func _ready() -> void:
	_marker = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = _marker_box_size()
	_marker.mesh = box

	_marker_mat = StandardMaterial3D.new()
	_marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker_mat.albedo_color = _base_color()
	_marker.material_override = _marker_mat
	add_child(_marker)

	path_visual = OrbitalPath.new()
	add_child(path_visual)

	_apply_color()
	_apply_path_style()
	_sync_marker_position()


func _process(_delta: float) -> void:
	# Revert the hit-flash tint once its wall-clock window passes. Cheap
	# enough to do every frame; the alternative (HUD driving it) couples
	# the visual back into the controller.
	if _flash_until > 0.0 and _wall_now() >= _flash_until:
		_flash_until = 0.0
		_apply_color()


## Tint the 3D orbit marker orange for `duration` wall-clock seconds.
## HUD calls this when a weapon successfully fires at this satellite,
## so the marker pulses regardless of game time-factor compression.
func flash_hit(duration: float) -> void:
	if duration <= 0.0:
		return
	_flash_until = _wall_now() + duration
	if _marker_mat != null:
		_marker_mat.albedo_color = COLOR_HIT


func _wall_now() -> float:
	return Time.get_ticks_msec() / 1000.0


func select() -> void:
	selected = true
	_apply_color()


func unselect() -> void:
	selected = false
	_apply_color()


func set_maneuver(input: Vector3) -> void:
	raw_maneuver = input
	did_maneuver = input.length_squared() > 0.0


## Flip the fire-control mode. Only meaningful on armed units; unarmed
## satellites (enemies, meteorites) keep the flag at false but caller
## still gets the no-op behavior right because their weapons array is
## empty.
func toggle_fire_control() -> void:
	fire_control_active = not fire_control_active


## Absolute simulated time at which this body's current trajectory
## crosses Earth, computed lazily on first access against the current
## sim-clock. Subsequent accesses return the stored value as-is — the
## impact *instant* is invariant under free propagation, so neither the
## caller nor advance_time has to nudge it each tick. INF is returned
## (and stored) for orbits whose periapsis stays above the surface or
## whose impact is past the propagator's horizon.
func predict_impact_sim_time(current_sim_time: float) -> float:
	if is_nan(impact_sim_time):
		var eta := orbit.time_to_impact(
			IMPACT_CACHE_HORIZON_SEC, IMPACT_CACHE_STEP_SEC
		)
		# eta == INF flows through as INF (current_sim_time + INF == INF),
		# so non-impacting orbits don't need a separate branch.
		impact_sim_time = current_sim_time + eta
	return impact_sim_time


## Mark the cached impact time stale so the next access recomputes it.
## Called by every code path that mutates `orbit.v` outside of free
## propagation — player thrust, the decaying-orbit perigee burn, and
## state cloning between real and planning satellites.
func invalidate_impact_cache() -> void:
	impact_sim_time = NAN


## Flip the laser targeting mode between MAX_DAMAGE (closest target) and
## MAX_DANGER (target whose trajectory impacts Earth soonest). Only
## meaningful on armed units; on unarmed bodies the flag is harmless but
## ignored by the combat loop.
func toggle_targeting_mode() -> void:
	if targeting_mode == LaserWeapon.TARGETING_MAX_DAMAGE:
		targeting_mode = LaserWeapon.TARGETING_MAX_DANGER
	else:
		targeting_mode = LaserWeapon.TARGETING_MAX_DAMAGE


## Clamp + assign the operator-set engagement range. The lower bound
## is the weapon's minimum so the operator can't disable fire control
## by accident; the upper bound is the physics-level max so anything
## past it is dead-on-arrival anyway.
func set_engagement_range(km: float) -> void:
	engagement_range_km = clampf(
		km,
		LaserWeapon.MIN_ENGAGEMENT_RANGE_KM,
		LaserWeapon.MAX_RANGE_KM,
	)


## Clamp + assign the operator-set max orbital radius (railgun safety
## cap). Lower bound is the hard-coded periapsis floor so the slider
## can't be driven below the planet; upper bound is unbounded in
## principle, but capped at INF/2 to dodge any future "infinite +
## infinite" arithmetic landmines. The shooter is still independently
## refused fire if any individual shot would put it on an escape
## trajectory regardless of where this slider sits.
func set_max_orbital_radius(km: float) -> void:
	max_orbital_radius_km = maxf(km, RailgunWeapon.SAFE_PERIAPSIS_KM)


## Flip the railgun-enabled gate. Like toggle_fire_control this is
## per-instance; EarthSystem keeps the whole fleet in sync via X.
func toggle_railgun() -> void:
	railgun_enabled = not railgun_enabled


## Whether this satellite carries at least one laser. Drives every
## laser-specific UI surface and input gate (the targeting-mode toggle,
## fire-control toggle, engagement-range slider, and their HUD
## readouts). A railgun-only ship returns false and is silently
## skipped by all of those — pressing L on it does nothing, the HUD
## doesn't render a TGT or FC line, and the range slider stays put.
func has_laser() -> bool:
	for w: Weapon in weapons:
		if w is LaserWeapon:
			return true
	return false


## Whether this satellite carries at least one railgun. Mirrors
## has_laser(); used by the HUD to decide whether to render the RG
## status line.
func has_railgun() -> bool:
	for w: Weapon in weapons:
		if w is RailgunWeapon:
			return true
	return false


func get_current_maneuver() -> Vector3:
	return DELTA_V_MAGNITUDE * raw_maneuver


## Delta-v (m/s) the unit can still spend, given current propellant,
## dry mass, and Isp. Read by the HUD; the maneuver branch in
## advance_time consults the same helper to clamp burns when the tank
## runs low.
func delta_v_remaining_ms() -> float:
	return Propulsion.dv_capacity_ms(propellant_kg, dry_mass_kg, isp_s)


## Apply damage. Returns true if this hit took the satellite to 0 HP.
## Only kills once — repeated calls on a dead satellite are no-ops, so
## stray late shots from concurrent attackers don't double-fire the
## death transition.
##
## When `attacker` is non-null, the actual applied damage (capped at
## current HP so overkill doesn't inflate the counter) is added to
## `attacker.damage_dealt`, and on a finishing blow `attacker.kills`
## is bumped. The end-of-run summary reads both counters directly off
## each player satellite, so per-shot crediting here is the single
## source of truth.
func take_damage(amount: float, attacker: Satellite = null) -> bool:
	if not alive or amount <= 0.0:
		return false
	var applied: float = minf(amount, hp)
	hp = maxf(hp - amount, 0.0)
	if attacker != null:
		attacker.damage_dealt += applied
	if hp <= 0.0:
		alive = false
		if attacker != null:
			attacker.kills += 1
		_hide_visuals()
		return true
	return false


## Step the orbit forward. If the orbit goes pathological (NaN, escape
## that the propagator can't resolve), mark this satellite dead so the
## game controller can skip it instead of bringing the renderer down.
func advance_time(delta_time: float) -> void:
	if not orbit_alive or not alive:
		return
	# Sample r·v before propagating so we can detect periapsis crossings
	# the end-of-step radius sample alone would miss — a body on a near-
	# radial trajectory can dive through periapsis and back out above
	# the surface inside one step at high time_factor.
	var r_dot_v_before: float = orbit.r.dot(orbit.v)
	var ok: bool
	if did_maneuver:
		# Player thrust is the only caller of relative_maneuver; clamp
		# it so it can't drive periapsis below the surface. Meteorites
		# never enter this branch (no operator). Invalidate the impact
		# cache before stepping — the new velocity makes the prior
		# prediction stale.
		invalidate_impact_cache()
		# Charge propellant for the requested burn via Tsiolkovsky. If
		# the tank can't cover the full Δv (raw_maneuver is per-tick so
		# at high time_factor a held key can run a unit dry quickly),
		# scale the applied burn down to whatever the remaining
		# propellant can deliver and let the rest of the tick be free
		# propagation. Burns at 0 km/s (idle thrust input) skip the
		# whole gauntlet — the maneuver vector is already zero so
		# relative_maneuver is a no-op against the orbit.
		var requested := get_current_maneuver()
		var dv_kms := requested.length()
		var applied := requested
		if dv_kms > 0.0:
			# Convert to m/s for the Tsiolkovsky helpers, clamp against
			# the tank's remaining capacity, then scale the directional
			# burn vector back down. Orbital math stays in km/s.
			var requested_ms := dv_kms * 1000.0
			var have_ms := delta_v_remaining_ms()
			var applied_ms := minf(requested_ms, have_ms)
			if applied_ms <= 0.0:
				applied = Vector3.ZERO
			else:
				applied = requested * (applied_ms / requested_ms)
				var burned := Propulsion.propellant_for_dv_kg(
					applied_ms, mass, isp_s
				)
				propellant_kg = maxf(propellant_kg - burned, 0.0)
				mass = dry_mass_kg + propellant_kg
		ok = orbit.relative_maneuver(applied, delta_time, SAFE_PERIAPSIS_KM)
	else:
		# Free propagation leaves the orbit shape (and therefore the
		# absolute impact time) unchanged, so the cache stays valid
		# without any per-tick bookkeeping.
		ok = orbit.propagate(delta_time)
	did_maneuver = false
	raw_maneuver = Vector3.ZERO
	if not ok:
		orbit_alive = false
		_hide_visuals()
		return
	# Decaying-orbit perigee burn. Descending → ascending transition
	# (r·v flips negative to positive) marks the perigee crossing;
	# scale velocity along its current direction to halve r_a. The
	# orbit shrinks toward circular, then — once r_a/2 drops below
	# r_p — the burn flips orientation: the body's current location
	# becomes the new orbit's apogee and the trailing apsis ends up
	# below the surface, so the surface-cross check in the rest of
	# this function terminates the body on its descent.
	if (
		is_decaying
		and r_dot_v_before < 0.0
		and orbit.r.dot(orbit.v) > 0.0
	):
		_perigee_decay_burn()
	# Any satellite whose trajectory crosses the surface exits play. The
	# Keplerian propagator is happy to push a body straight through the
	# planet and out the other side, so we kill on either (a) the post-
	# step radius being inside the surface, or (b) an inbound→outbound
	# transition during the step combined with a sub-surface periapsis
	# (the body just tunneled through ground inside one tick).
	var crossed_periapsis := r_dot_v_before < 0.0 and orbit.r.dot(orbit.v) > 0.0
	var sub_surface_periapsis := (
		is_finite(orbit.r_p) and orbit.r_p <= EarthOrbit.EARTH_RADIUS_KM
	)
	if (
		orbit.norm_r <= EarthOrbit.EARTH_RADIUS_KM
		or (crossed_periapsis and sub_surface_periapsis)
	):
		alive = false
		_hide_visuals()
		return
	_sync_marker_position()


func render_orbit(show_path: bool, current_sim_time: float = 0.0) -> void:
	if not is_inside_tree() or path_visual == null:
		return
	if not orbit_alive or not alive:
		path_visual.visible = false
		return
	# Surface installations don't follow a Keplerian arc — they ride
	# Earth's daily rotation. Drawing an "orbit" here would be both
	# meaningless and (because orbit.v is just the surface tangential
	# speed) numerically ill-conditioned, so we hide the path entirely.
	if is_surface:
		path_visual.visible = false
		return
	path_visual.color = _path_color(current_sim_time)
	# Meteorites get the truncated-trajectory renderer: the same line
	# style as a regular orbit, but cut off at the surface so the part
	# that would tunnel through Earth isn't drawn.
	if is_decaying:
		# Render the body's entire predicted future trajectory as a
		# multi-segment spiral: current arc to next perigee, then a
		# full ellipse for each remaining post-burn orbit, then the
		# truncated final inbound leg to the surface. The spiral
		# tells the player how many cycles are left before impact.
		path_visual.update_decaying_spiral(orbit)
	elif is_meteorite:
		path_visual.update_trajectory(orbit)
	else:
		path_visual.update_orbit(orbit)


# Halve r_a by scaling the velocity vector along its own direction.
# At (or near) perigee the velocity is tangential, so shrinking it
# preserves r_p and pulls r_a in by the analytic factor that falls
# out of the vis-viva identity at perigee:
#   v_p² = 2μ r_a / (r_p·(r_p + r_a))
# Same factor as the apogee mirror with r_p ↔ r_a swapped — once
# the requested r_a/2 drops below r_p the burn over-shoots and the
# body's current point becomes the new orbit's apogee, with the
# trailing apsis ending up below ground; that's the impact case.
func _perigee_decay_burn() -> void:
	var r_p := orbit.r_p
	var r_a := orbit.r_a
	if (
		not is_finite(r_p) or not is_finite(r_a)
		or r_p <= 0.0 or r_a <= 0.0
	):
		return
	var k := sqrt((r_p + r_a) / (2.0 * r_p + r_a))
	# maneuver(dv, t=0) skips propagation and applies the velocity delta,
	# then recomputes derived elements — equivalent to "set v" without
	# touching the propagator's private API.
	var dv := orbit.v * (k - 1.0)
	# Burn changes the orbit shape; the cached impact ETA was computed
	# against the pre-burn trajectory, so it's stale now.
	invalidate_impact_cache()
	if not orbit.maneuver(dv, 0.0):
		orbit_alive = false
		_hide_visuals()


## Full clone — orbital state and operator-queued maneuver intent.
## Use on planning-mode entry, where you want the plan to start identical
## to reality.
func clone_from(other: Satellite) -> void:
	clone_orbit_from(other)
	raw_maneuver = other.raw_maneuver
	did_maneuver = other.did_maneuver


## Clone only the orbital state (r, v, derived elements). Use this every
## physics tick during planning so the plan's snapshot tracks reality
## without nuking any maneuver the user has queued in the planning UI.
func clone_orbit_from(other: Satellite) -> void:
	orbit.clone_from(other.orbit)
	selected = other.selected
	orbit_alive = other.orbit_alive
	team = other.team
	unit_name = other.unit_name
	max_hp = other.max_hp
	hp = other.hp
	damage_dealt = other.damage_dealt
	kills = other.kills
	alive = other.alive
	is_meteorite = other.is_meteorite
	is_decaying = other.is_decaying
	is_surface = other.is_surface
	surface_lat_deg = other.surface_lat_deg
	surface_lon_deg = other.surface_lon_deg
	# Mirror armed-vs-unarmed so the planning HUD doesn't show an
	# energy bar for an enemy preview (clones get fresh weapons in
	# _init that we'd otherwise leave dangling).
	energy = other.energy
	energy_max = other.energy_max
	energy_rate_per_sim_sec = other.energy_rate_per_sim_sec
	engagement_range_km = other.engagement_range_km
	fire_control_active = other.fire_control_active
	targeting_mode = other.targeting_mode
	mass = other.mass
	dry_mass_kg = other.dry_mass_kg
	propellant_kg = other.propellant_kg
	max_propellant_kg = other.max_propellant_kg
	isp_s = other.isp_s
	thrust_n = other.thrust_n
	max_orbital_radius_km = other.max_orbital_radius_km
	railgun_enabled = other.railgun_enabled
	# Mirror the cache so the planning preview's HUD ranking matches
	# the real fleet's. The stored value is an absolute sim-time, so
	# the planning sat — which lives on the same sim clock as reality
	# — can reuse it as-is until a maneuver invalidates it.
	impact_sim_time = other.impact_sim_time
	if other.weapons.is_empty():
		weapons.clear()
	if is_inside_tree():
		_apply_color()
		_apply_marker_size()
		_apply_path_style()
		_sync_marker_position()


func _sync_marker_position() -> void:
	if _marker == null:
		return
	_marker.position = orbit.r * SCENE_SCALE


# Mesh side length (uniform cube) derived from mass^(1/3) so the
# rendered volume tracks mass linearly. A default 1000 kg unit yields
# the historical 0.15-unit cube; smaller / larger bodies scale around
# that reference. maxf(mass, 1.0) is a paranoia floor so a zero or
# negative mass — should one slip through — doesn't collapse the cube
# to a point.
func _marker_box_size() -> Vector3:
	var side := MARKER_BASE_SIZE * pow(
		maxf(mass, 1.0) / MARKER_REFERENCE_MASS_KG, 1.0 / 3.0
	)
	return Vector3(side, side, side)


# Re-derive and apply the cube size from the current mass. Called from
# clone_orbit_from after the planning satellite copies real-side mass,
# since the BoxMesh was already sized at _ready under the planning
# clone's default mass.
func _apply_marker_size() -> void:
	if _marker == null:
		return
	var box := _marker.mesh as BoxMesh
	if box == null:
		return
	box.size = _marker_box_size()


func _base_color() -> Color:
	if is_meteorite:
		return COLOR_METEORITE
	if is_decaying:
		return COLOR_DECAYING
	if is_surface:
		return COLOR_SURFACE
	return COLOR_ENEMY if team == TEAM_ENEMY else COLOR_PLAYER


## Recompute orbit.r for a surface installation at the given Earth
## phase. Called from EarthSystem._physics_process for every is_surface
## sat in lieu of advance_time — the body never propagates, it just
## rides the planet's daily rotation. orbit.v is set to the local
## tangential velocity so any code path that reads it (currently the
## railgun's safety check, which we still expect to refuse fire) sees
## a kinematically consistent state rather than a static-snapshot zero.
func update_surface_position(earth_phase: float) -> void:
	if not is_surface:
		return
	var radius := EarthOrbit.EARTH_RADIUS_KM + SURFACE_UNIT_ALTITUDE_KM
	var pos := SurfacePosition.latlon_to_eci(
		surface_lat_deg, surface_lon_deg, earth_phase, radius
	)
	# Sample velocity by finite-difference across a small phase delta —
	# avoids re-deriving the analytical tangent in the AXIAL_TILT * daily
	# * POLE_ALIGN frame. dt = phase / (TAU / sidereal_day).
	var pos_next := SurfacePosition.latlon_to_eci(
		surface_lat_deg, surface_lon_deg,
		earth_phase + SURFACE_PHASE_EPS, radius,
	)
	var dt: float = SURFACE_PHASE_EPS * SURFACE_SIDEREAL_DAY_SEC / TAU
	orbit.r = pos
	orbit.v = (pos_next - pos) / dt
	orbit.norm_r = pos.length()
	orbit.norm_v = orbit.v.length()
	if not is_inside_tree():
		return
	_sync_marker_position()


func _apply_color() -> void:
	if _marker_mat == null:
		return
	# Hit-flash overrides selection / team while it's active so the
	# pulse reads as a damage indicator even on the currently selected
	# unit. _process reverts via _apply_color when the window expires.
	if _flash_until > 0.0 and _wall_now() < _flash_until:
		_marker_mat.albedo_color = COLOR_HIT
		return
	_marker_mat.albedo_color = COLOR_SELECTED if selected else _base_color()


# Tint for the orbit ribbon. Player paths keep the team / selection
# color exactly as before. Enemy paths interpolate yellow → red against
# predicted time-to-impact so a glance at the line conveys urgency:
# stable enemy orbits read full yellow, an inbound meteorite seconds
# from impact reads full red, decaying spirals slide between the two
# as their final perigee approaches. Selection still wins on either
# side — the green flash marks "this one's selected" regardless of
# threat color.
func _path_color(current_sim_time: float) -> Color:
	var base: Color
	if selected:
		base = COLOR_SELECTED
	elif team != TEAM_ENEMY:
		base = COLOR_PLAYER
	else:
		base = _enemy_path_gradient_color(current_sim_time)
	# Apply the spawn-baked opacity (HP-derived for enemies, 1.0 for
	# player paths). _path_alpha is set once in _apply_path_style and
	# never updated as HP drops during play, by design.
	base.a = _path_alpha
	return base


func _enemy_path_gradient_color(current_sim_time: float) -> Color:
	var eta := predict_impact_sim_time(current_sim_time) - current_sim_time
	if not is_finite(eta) or eta <= 0.0:
		# Past-impact (eta <= 0) shouldn't normally render — the body
		# would've been killed already — but guard anyway: full red
		# matches "as close to impact as it gets".
		var t_full: float = 1.0 if eta <= 0.0 else 0.0
		return COLOR_ENEMY_PATH_FAR.lerp(COLOR_ENEMY_PATH_NEAR, t_full)
	var span := ENEMY_PATH_ETA_YELLOW_S - ENEMY_PATH_ETA_RED_S
	var t_linear := clampf(
		(ENEMY_PATH_ETA_YELLOW_S - eta) / span, 0.0, 1.0
	)
	# sqrt bias — see ENEMY_PATH_ETA_*_S. Pulls the ramp toward red so
	# a 60-min ETA meteorite reads ~70% red rather than the 50% a
	# linear interpolation would give.
	var t := sqrt(t_linear)
	return COLOR_ENEMY_PATH_FAR.lerp(COLOR_ENEMY_PATH_NEAR, t)


# Bake the orbit-line's thickness and opacity from initial HP. Called
# from _ready (initial spawn) and clone_orbit_from (planning preview
# pickup) — never per-tick. Player paths get a constant readable style;
# enemy paths log-scale max_hp into the (width, alpha) envelope so a
# 10-HP meteorite renders as a thin near-transparent thread and a
# 1000-HP decaying ship as a bold opaque ribbon. The alpha lives on
# the path material's color uniform; we re-set the uniform here using
# the existing `path_visual.color` tint so subsequent per-tick color
# updates inherit the same alpha (see _path_color).
func _apply_path_style() -> void:
	if path_visual == null:
		return
	var width: float
	var alpha: float
	if team == TEAM_ENEMY:
		var hp_norm := clampf(
			log(maxf(max_hp, 1.0)) / log(ENEMY_PATH_HP_LOG_BASE),
			0.0, 1.0,
		)
		width = lerpf(
			ENEMY_PATH_WIDTH_MIN_PX, ENEMY_PATH_WIDTH_MAX_PX, hp_norm
		)
		alpha = lerpf(
			ENEMY_PATH_ALPHA_MIN, ENEMY_PATH_ALPHA_MAX, hp_norm
		)
	else:
		width = PLAYER_PATH_WIDTH_PX
		alpha = 1.0
	path_visual.line_width_px = width
	_path_alpha = alpha
	# Seed the material's alpha immediately so the path renders with
	# the right opacity on the first tick — render_orbit re-applies it
	# every frame after that via _path_color.
	var tint := path_visual.color
	tint.a = alpha
	path_visual.color = tint


func _hide_visuals() -> void:
	if _marker:
		_marker.visible = false
	if path_visual:
		path_visual.visible = false
