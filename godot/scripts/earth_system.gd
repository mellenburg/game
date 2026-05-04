class_name EarthSystem
extends Node3D
## Top-level controller. Simulation runs in _physics_process at a fixed
## tick rate so the orbit math is frame-rate independent. _process is
## reserved for camera + HUD.
##
## Spawn behaviours live in SpawnDirector and the combat scheduler in
## CombatController; this node owns shared simulation state (the
## real / planning satellite arrays, sim_time, selection) and routes
## input through to the right service.

const Satellite = preload("res://scripts/satellite.gd")
const Earth = preload("res://scripts/earth.gd")
const HUD = preload("res://scripts/hud.gd")
const OrbitCamera = preload("res://scripts/orbit_camera.gd")
const EarthOrbit = preload("res://scripts/earth_orbit.gd")
const BeamRenderer = preload("res://scripts/beam_renderer.gd")
const SlugRenderer = preload("res://scripts/slug_renderer.gd")
const ImpactTracker = preload("res://scripts/impact_tracker.gd")
const ImpactMap = preload("res://scripts/impact_map.gd")
const RadarMap = preload("res://scripts/radar_map.gd")
const ThreatAlert = preload("res://scripts/threat_alert.gd")
const ImpactExplosion = preload("res://scripts/impact_explosion.gd")
const RangeCircle = preload("res://scripts/range_circle.gd")
const SpawnDirector = preload("res://scripts/spawn_director.gd")
const CombatController = preload("res://scripts/combat_controller.gd")
const Mission = preload("res://scripts/mission.gd")
const EndGameOverlay = preload("res://scripts/end_game_overlay.gd")
const ReconSettings = preload("res://scripts/recon_settings.gd")
const WaveUnitClass = preload("res://scripts/wave_unit_class.gd")
const LaserWeapon = preload("res://scripts/weapons/laser_weapon.gd")
const RailgunWeapon = preload("res://scripts/weapons/railgun_weapon.gd")
const UnitConfig = preload("res://scripts/unit_config.gd")
const SurfaceUnitConfig = preload("res://scripts/surface_unit_config.gd")
const Launch = preload("res://scripts/launch.gd")

const TIME_FACTOR_MIN: int = 0
const TIME_FACTOR_MAX: int = 5000
const TIME_FACTOR_RATE: int = 60       # changes per second while held
const PLANNING_DT_MAX: int = 86400 * 7  # one week of plan window

# Engagement-range adjustment rate while shift+up/down is held. Sized
# so an operator can sweep the full settable band (MIN_ENGAGEMENT_RANGE
# to MAX_RANGE) in roughly four seconds — fast enough to feel
# responsive, slow enough to land on a chosen ring.
const RANGE_RATE_KM_PER_SEC: float = 10000.0
# Max-orbital-radius adjustment rate while shift+left/right is held.
# Faster than the engagement-range knob because the railgun cap covers
# a much wider band (100 km up to GEO+ and beyond) — sweeping at 10
# k/s would feel sluggish at the high end. 25 k/s lets the operator
# move from a tight 1 000 km cap to the default 50 000 km in ~2 s.
const MAX_RADIUS_RATE_KM_PER_SEC: float = 25000.0

@export var time_factor: int = 300
var planning_dt: int = 0
var planning_mode: bool = false

# Simulated seconds elapsed since the scene came up. Advanced in
# _physics_process by sim_delta — same units satellites use for orbital
# propagation. Read by Satellite.predict_impact_sim_time() to stamp
# fresh impact-cache entries in absolute time, so subsequent ranking
# lookups don't need to renormalise relative ETAs every tick.
var sim_time: float = 0.0

var real_satellites: Array[Satellite] = []
var planning_satellites: Array[Satellite] = []
var selected_ship: int = 0
var planning_selected: int = 0

# Running tallies of how each enemy left play. Driven from the dead-
# satellite sweep so it counts every termination once, regardless of
# whether the cause was a weapon hit or a sub-orbital impact.
var enemies_shot_down: int = 0
var meteorites_impacted: int = 0
# Sum of HP each impacting body still carried at ground contact —
# i.e. the damage total Earth ate. Counted from the dead-sat sweep so
# every impact flows through one place. Surfaced on the end-of-run
# summary alongside per-unit damage / kills.
var total_impact_hp: float = 0.0
# Snapshots of player satellites that died during the run. Each entry
# is a Dictionary { "unit_name", "damage_dealt", "kills" } captured at
# the moment of death so the end-of-run summary can credit a unit
# whose satellite never survived to the final tick. Live satellites
# are read directly from real_satellites at summary time.
var dead_player_stats: Array[Dictionary] = []

var _time_factor_accum: float = 0.0
var _planning_dt_accum: float = 0.0
# Latches the fleet-wide engagement-range adjustment mode (Shift+C+Up/Down).
# Goes true on the rising edge of arrow input while Shift+C is held — that
# edge is when we snap every armed player sat to the fleet's average range
# so subsequent ticks just nudge a single shared value. Cleared as soon as
# the arrow / Shift / C combination breaks so the next press re-snaps.
var _fleet_range_adjusting: bool = false
# Tracks whether any wave was inbound on the previous tick. Edge-
# triggered map-mode switching uses this — radar auto-selects on
# rising edge, surface map auto-selects on falling edge — so manual K
# presses during a live wave aren't yanked back every frame.
var _wave_inbound_prev: bool = false
var impact_tracker := ImpactTracker.new()
# Day-side albedo loaded once as an Image so we can sample it at an
# impact's UV without an editor-only Texture readback. Lazily filled
# in _ready; null-safe — if the texture's missing, ocean classification
# falls back to the bounding-box table alone.
var _albedo_image: Image = null

var spawn_director: SpawnDirector
var combat_controller: CombatController

# Mission wave scheduler. Non-null when the player launched from the
# pre-game menu (PlayerLoadout.launched). Null on direct main-scene
# boot so the existing debug entry path keeps its quiet sandbox — the
# operator can still trigger waves manually via the I/J/M keys.
var mission: Mission = null
# Latches that the mission summary has already been opened so we only
# trigger the overlay once. Without this, the post-clear tick would
# call show_summary() every frame.
var _mission_summary_shown: bool = false
# Per-wave base entry directions. Filled the first time the mission
# emits a wave-unit for a given wave_id; reused for every subsequent
# wave-unit in that wave so the cluster lands inside one solid-angle
# patch. Indexed by int wave_id, value is a unit Vector3.
var _mission_wave_bases: Dictionary = {}
# Snapshot of ReconSettings the active mission was started against.
# Mid-mission edits land on PlayerLoadout but don't rebuild this; we
# snapshot at start so a wave-unit emission still resolves to the
# class config the player intended at launch time.
var _mission_settings: ReconSettings = null

@onready var earth: Earth = $Earth as Earth
@onready var camera: OrbitCamera = $OrbitCamera as OrbitCamera
@onready var hud: HUD = $CanvasLayer/HUD as HUD
@onready var satellite_container: Node3D = $Satellites as Node3D
@onready var planning_container: Node3D = $PlanningSatellites as Node3D
@onready var beam_renderer: BeamRenderer = $BeamRenderer as BeamRenderer
@onready var slug_renderer: SlugRenderer = $SlugRenderer as SlugRenderer
@onready var range_circle: RangeCircle = $RangeCircle as RangeCircle
@onready var impact_map: ImpactMap = $CanvasLayer/HUD/ImpactMap as ImpactMap
@onready var radar_map: RadarMap = $CanvasLayer/HUD/RadarMap as RadarMap
@onready var threat_alert: ThreatAlert = (
	$CanvasLayer/HUD/ThreatAlert as ThreatAlert
)
@onready var end_game_overlay: EndGameOverlay = (
	$CanvasLayer/EndGameOverlay as EndGameOverlay
)

# Lower-right overlay cycle: surface impact map → wave radar → off → ...
# Driven by the "toggle_impact_map" input (K). Indices into MAP_MODES.
const MAP_MODE_SURFACE: int = 0
const MAP_MODE_RADAR: int = 1
const MAP_MODE_OFF: int = 2
const MAP_MODE_COUNT: int = 3
var map_mode: int = MAP_MODE_SURFACE

# Wall-clock cadence at which orbit visuals get rebuilt. Decoupled from
# the physics tick: the orbit/trajectory mesh doesn't need to refresh
# at 60 Hz — at high time_factor the orbit shape is cached anyway, and
# meteorite/decaying-spiral geometry that *does* rebuild per tick is
# visually indistinguishable above ~15 Hz. Rebuilding at this rate
# avoids 1200+ surface re-allocations per second during a 20-body wave.
const ORBIT_RENDER_INTERVAL: float = 1.0 / 15.0
var _orbit_render_accum: float = ORBIT_RENDER_INTERVAL

var satellites: Array[Satellite]:
	get: return planning_satellites if planning_mode else real_satellites


func _ready() -> void:
	_albedo_image = _load_albedo_image()
	if impact_map != null:
		impact_map.tracker = impact_tracker
		# Bound by reference, so the minimap reflects every spawn /
		# destruction of a surface installation without explicit refresh.
		impact_map.satellites = real_satellites
	_apply_map_mode()

	spawn_director = SpawnDirector.new()
	add_child(spawn_director)
	spawn_director.setup(satellite_container, real_satellites, threat_alert)

	combat_controller = CombatController.new()
	add_child(combat_controller)
	combat_controller.setup(hud, beam_renderer, slug_renderer)

	if radar_map != null:
		radar_map.waves = spawn_director.meteorite_waves

	var launches := _player_loadout_launches()
	var pool := _player_loadout_pool()
	spawn_director.spawn_starting_fleet(launches, pool)
	spawn_director.spawn_surface_units(
		_player_loadout_surface_units(), earth.earth_phase
	)
	# Position surface units immediately so the very first render frame
	# already shows them on the ground — _physics_process won't run until
	# after _ready completes, and without this seed the markers would
	# briefly sit at orbit.r's spawn placeholder.
	for sat in real_satellites:
		if sat.is_surface:
			sat.update_surface_position(earth.earth_phase)
	if not real_satellites.is_empty():
		selected_ship = _first_orbital_player_index()
		real_satellites[selected_ship].select()

	# Only auto-arm the mission scheduler when the player came in via
	# the menu's Launch button. Direct main.tscn boot keeps the legacy
	# sandbox where waves are only triggered by the debug keybinds.
	if _player_loadout_is_launched():
		_mission_settings = _player_loadout_recon_settings()
		mission = Mission.new()
		mission.start_from_settings(_mission_settings)


# Pull the player's wave configuration off PlayerLoadout. Falls back
# to the shipped default settings if the autoload is missing or has
# never been initialised — direct main.tscn boots take this branch.
func _player_loadout_recon_settings() -> ReconSettings:
	var tree := get_tree()
	if tree == null:
		return ReconSettings.default_settings()
	var loadout := tree.root.get_node_or_null("PlayerLoadout")
	if loadout == null or loadout.recon_settings == null:
		return ReconSettings.default_settings()
	# Snapshot a copy so live edits to PlayerLoadout.recon_settings can
	# never mutate the running mission's config out from under it.
	return loadout.recon_settings.duplicate_settings()


# Tighter check than `_player_loadout_launches`: we want a true / false
# answer for "did the player launch through the menu?" without copying
# the launches array. Mirrors the same null-safe lookup the launch / pool
# helpers do so all four agree on the gating condition.
func _player_loadout_is_launched() -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	var loadout := tree.root.get_node_or_null("PlayerLoadout")
	if loadout == null:
		return false
	return bool(loadout.launched)


# Pull the launches the pre-game menu set into PlayerLoadout, if the
# autoload is present and the player launched from the menu. Empty
# array otherwise — SpawnDirector treats that as "use the legacy
# randomised fleet", which keeps direct-boot of main.tscn working for
# debugging and any future smoke tests.
func _player_loadout_launches() -> Array[Launch]:
	var empty: Array[Launch] = []
	var tree := get_tree()
	if tree == null:
		return empty
	var loadout := tree.root.get_node_or_null("PlayerLoadout")
	if loadout == null or not loadout.launched:
		return empty
	var launches: Array[Launch] = loadout.launches
	return launches


# Companion lookup for the unit pool — SpawnDirector resolves each
# launch's unit_id against this list so the chassis + parts are
# available at materialisation time. Empty when no menu / not launched
# (matches `_player_loadout_launches`'s shape).
func _player_loadout_pool() -> Array[UnitConfig]:
	var empty: Array[UnitConfig] = []
	var tree := get_tree()
	if tree == null:
		return empty
	var loadout := tree.root.get_node_or_null("PlayerLoadout")
	if loadout == null or not loadout.launched:
		return empty
	var pool: Array[UnitConfig] = loadout.unit_pool
	return pool


# Same gate as _player_loadout_units but for surface installations
# placed via the menu's Surface Ops tab. Empty array means the player
# never opened that tab (or booted main.tscn directly), so no surface
# units spawn.
func _player_loadout_surface_units() -> Array[SurfaceUnitConfig]:
	var empty: Array[SurfaceUnitConfig] = []
	var tree := get_tree()
	if tree == null:
		return empty
	var loadout := tree.root.get_node_or_null("PlayerLoadout")
	if loadout == null:
		return empty
	if not loadout.launched:
		return empty
	var configs: Array[SurfaceUnitConfig] = loadout.surface_units
	return configs


# Default-select the first orbital player satellite rather than blindly
# picking index 0, which after spawn_starting_fleet + spawn_surface_units
# could be any team / kind. Surface installations don't accept thrust
# input, and selecting one as the active ship would silently make every
# arrow key a no-op until the operator pressed Tab.
func _first_orbital_player_index() -> int:
	for i in range(real_satellites.size()):
		var sat := real_satellites[i]
		if sat.team == Satellite.TEAM_PLAYER and not sat.is_surface:
			return i
	return 0


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
	# Mission scheduler and wave preroll/spawn timers tick in
	# *sim-time*, not wall-clock — that way a wave's UTC arrival time
	# is locked to the schedule's absolute sim-second offset and stays
	# put even if the operator later changes time_factor. Pausing the
	# sim (time_factor=0) likewise pauses the mission clock.
	var sim_delta := float(time_factor) * delta
	_tick_mission(sim_delta)
	spawn_director.tick_waves(sim_delta)
	_check_mission_complete()
	_auto_switch_map_mode()
	_update_range_circle()
	_render_orbits(delta)
	hud.update_hud(self, planning_mode, time_factor, planning_dt, sim_time)
	hud.draw_target_lines(self, camera)


# Drain any wave-unit emissions whose start threshold elapsed this
# tick and hand each off to the spawn director as one full meteorite
# wave. Wave-units sharing a wave_id reuse the same per-wave base
# entry direction (sampled fresh on the first emission of each wave),
# so the cluster of bursts lands inside one solid-angle patch rather
# than scattering across the sky. Keyed off real-time delta to match
# the existing wave-spawn cadence — pausing the sim (time_factor=0)
# doesn't pause the mission clock, and the fully-spawned wave bodies
# still ride the same _process tick_waves loop downstream.
func _tick_mission(delta: float) -> void:
	if mission == null:
		return
	var ready: Array[Dictionary] = mission.tick(delta)
	for emission: Dictionary in ready:
		var wave_id := int(emission.get("wave_id", -1))
		if not _mission_wave_bases.has(wave_id):
			_mission_wave_bases[wave_id] = spawn_director.sample_unit_vector()
		var base: Vector3 = _mission_wave_bases[wave_id]
		var size_class := int(emission.get("size_class", ReconSettings.SIZE_ALPHA))
		var unit_class: WaveUnitClass = null
		if _mission_settings != null:
			unit_class = _mission_settings.class_for(size_class)
		# Mission baked the per-wave-unit object count into the spec at
		# schedule-build time so the per-wave 250-body cap can be
		# enforced across siblings; pass it through as an override so
		# SpawnDirector doesn't resample.
		var count_override := int(emission.get("object_count", -1))
		spawn_director.start_wave_unit_clustered(
			base, unit_class, count_override
		)


# Once every wave has been handed to the spawn director, the in-flight
# wave queue has drained, and no live enemy satellites remain, the
# mission is over. Mark complete (so we don't re-fire) and pop the
# end-of-run summary, which pauses the tree and routes the operator
# back to the menu on acknowledge.
func _check_mission_complete() -> void:
	if mission == null or _mission_summary_shown:
		return
	if mission.is_complete():
		return
	if not mission.all_waves_spawned():
		return
	if spawn_director.has_active_waves():
		return
	if _any_live_enemies():
		return
	mission.mark_complete()
	_mission_summary_shown = true
	if end_game_overlay != null:
		end_game_overlay.show_summary()


func _any_live_enemies() -> bool:
	for sat in real_satellites:
		if sat.team == Satellite.TEAM_ENEMY and sat.alive:
			return true
	return false


func _physics_process(delta: float) -> void:
	# Convert wall-clock seconds to simulated seconds.
	var sim_delta := float(time_factor) * delta
	sim_time += sim_delta
	earth.advance_phase(sim_delta)
	impact_tracker.tick(sim_delta)
	for sat in real_satellites:
		if sat.is_surface:
			# Surface installations ride Earth's daily rotation rather
			# than propagating Keplerian motion — orbit.r is rewritten
			# from (lat, lon, earth_phase) so combat queries that read
			# attacker.orbit.r still work.
			sat.update_surface_position(earth.earth_phase)
		else:
			sat.advance_time(sim_delta)
	combat_controller.process_combat(real_satellites, sim_time, sim_delta)
	# Advance any in-flight railgun slugs by the same sim-delta the
	# combat tick just used. The slug homes on its target's *current*
	# position each frame — non-physical but the tracer stays pointed
	# at something the operator can recognise.
	slug_renderer.tick(sim_delta)
	_remove_dead_satellites()

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
				if plan_sat.is_surface:
					# Surface installation — extrapolate the planet's
					# rotation rather than the orbit so the planning
					# preview shows the unit's future ECI position.
					var future_phase: float = (
						earth.earth_phase + earth.rotation_rate * window
					)
					plan_sat.update_surface_position(future_phase)
				else:
					plan_sat.advance_time(window)
			plan_sat.visible = true
	else:
		for sat in planning_satellites:
			sat.visible = false


# Throttled orbit-visual rebuild. Lives in _process so the cadence is
# wall-clock and time_factor-independent — the underlying orbit math
# already advanced this frame in _physics_process; we just refresh the
# line strip(s) at human-perceptual rates.
func _render_orbits(delta: float) -> void:
	_orbit_render_accum += delta
	if _orbit_render_accum < ORBIT_RENDER_INTERVAL:
		return
	_orbit_render_accum = 0.0
	for sat in real_satellites:
		sat.render_orbit(true, sim_time)
	if planning_mode:
		for i in range(planning_satellites.size()):
			planning_satellites[i].render_orbit(
				i == planning_selected, sim_time
			)


func _remove_dead_satellites() -> void:
	var i := 0
	while i < real_satellites.size():
		var sat := real_satellites[i]
		if sat.alive and sat.orbit_alive:
			i += 1
			continue
		# Tally enemy terminations by cause: HP gone -> shot down by a
		# weapon; sub-orbital body (meteorite or post-burn decaying
		# enemy) still has HP -> ground impact (advance_time kills it
		# on surface crossing without touching hp).
		if sat.team == Satellite.TEAM_ENEMY:
			if sat.hp <= 0.0:
				enemies_shot_down += 1
			elif sat.is_meteorite or sat.is_decaying:
				meteorites_impacted += 1
				# HP at the moment of impact is the un-reduced threat
				# Earth absorbed. Tally it before the satellite is
				# freed so the end-of-run summary can show "total HP
				# of impactors", not just a count.
				total_impact_hp += maxf(sat.hp, 0.0)
				_record_meteorite_impact(sat)
		elif sat.team == Satellite.TEAM_PLAYER and sat.unit_name != "":
			# Snapshot the dying player unit's tallies so the summary
			# still credits its damage / kills even though the live
			# Satellite is about to be freed.
			dead_player_stats.append({
				"unit_name": sat.unit_name,
				"damage_dealt": sat.damage_dealt,
				"kills": sat.kills,
			})
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


# Build the end-of-run report. Combines live player-satellite tallies
# (read directly from each Satellite) with the dead_player_stats
# snapshots captured in _remove_dead_satellites, so a unit whose ship
# was lost mid-run still gets credit for what it did. The end-game
# overlay renders this dictionary directly; storing it as a struct
# rather than a formatted string keeps the formatting concern in the
# overlay where it belongs.
func end_game_summary() -> Dictionary:
	var per_unit: Array[Dictionary] = []
	for sat in real_satellites:
		if sat.team != Satellite.TEAM_PLAYER:
			continue
		if sat.unit_name == "":
			continue
		per_unit.append({
			"unit_name": sat.unit_name,
			"damage_dealt": sat.damage_dealt,
			"kills": sat.kills,
			"alive": sat.alive,
		})
	for dead in dead_player_stats:
		per_unit.append({
			"unit_name": String(dead.get("unit_name", "")),
			"damage_dealt": float(dead.get("damage_dealt", 0.0)),
			"kills": int(dead.get("kills", 0)),
			"alive": false,
		})
	return {
		"per_unit": per_unit,
		"total_impacts": meteorites_impacted,
		"total_impact_hp": total_impact_hp,
	}


func _process_continuous_input(delta: float) -> void:
	# Shift gates the arrow keys onto the engagement-range adjustment
	# axis so we only have to bind one set of keys. With shift held the
	# thrust block is suppressed entirely — otherwise releasing shift
	# mid-press would briefly inject thrust on the same arrow tap.
	var shift_held := Input.is_key_pressed(KEY_SHIFT)
	var thrust := Vector3.ZERO
	var range_input := 0.0
	var radius_input := 0.0
	if shift_held:
		# Shift gates the arrow keys onto two adjustment axes: up/down
		# nudge the laser engagement range, left/right nudge the railgun
		# max-orbital-radius cap. Thrust is suppressed in this branch so
		# releasing shift mid-press doesn't dribble unintended thrust.
		if Input.is_action_pressed("thrust_prograde"):  range_input += 1.0
		if Input.is_action_pressed("thrust_retrograde"): range_input -= 1.0
		if Input.is_action_pressed("thrust_right"):      radius_input += 1.0
		if Input.is_action_pressed("thrust_left"):       radius_input -= 1.0
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
		# Surface installations are anchored to Earth's surface — thrust
		# inputs are silently ignored on them, otherwise the queued Δv
		# would land in raw_maneuver and confuse the planning preview.
		if sat.team == Satellite.TEAM_PLAYER and not sat.is_surface:
			sat.set_maneuver(thrust)

	# Engagement-range nudge. Always written to the *real* satellite —
	# the planning clone is overwritten from reality every physics tick
	# (clone_orbit_from copies engagement_range_km), so mutating the
	# planning sat would be visually invisible the next frame.
	#
	# Two modes share the same arrow-while-Shift gesture:
	#   * Shift + arrows  → adjusts the selected ship only.
	#   * Shift + C + arrows → snaps every armed player ship to the fleet
	#     average on the press edge, then drives the shared value as long
	#     as the keys stay held. Snap-on-edge keeps the operator from
	#     having to manually equalise ranges before commanding the fleet.
	var fleet_range_mode := shift_held and Input.is_key_pressed(KEY_C)
	var fleet_adjusting_now := false
	if range_input != 0.0 and fleet_range_mode and not real_satellites.is_empty():
		# Engagement range only governs the laser. Shift+C+arrows
		# snaps every laser-armed ship to the fleet average and
		# nudges from there; railgun-only ships are skipped.
		var laser_armed := _laser_armed_player_sats()
		if not laser_armed.is_empty():
			if not _fleet_range_adjusting:
				var sum := 0.0
				for sat in laser_armed:
					sum += sat.engagement_range_km
				var avg := sum / float(laser_armed.size())
				for sat in laser_armed:
					sat.set_engagement_range(avg)
			var step_km := range_input * RANGE_RATE_KM_PER_SEC * delta
			for sat in laser_armed:
				sat.set_engagement_range(sat.engagement_range_km + step_km)
			fleet_adjusting_now = true
	elif range_input != 0.0 and not real_satellites.is_empty():
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
	_fleet_range_adjusting = fleet_adjusting_now

	# Railgun max-orbital-radius nudge. Same write-to-real-not-planning
	# pattern as the engagement-range slider, since clone_orbit_from
	# overwrites the planning copy each tick. Gated on the selected
	# ship carrying a railgun — the cap is read only by the railgun's
	# safety check, so adjusting it on a laser-only ship would mutate
	# a value nothing ever reads.
	if radius_input != 0.0 and not real_satellites.is_empty():
		var real_idx := planning_selected if planning_mode else selected_ship
		if real_idx >= 0 and real_idx < real_satellites.size():
			var rsat := real_satellites[real_idx]
			if rsat.team == Satellite.TEAM_PLAYER and rsat.has_railgun():
				rsat.set_max_orbital_radius(
					rsat.max_orbital_radius_km
					+ radius_input * MAX_RADIUS_RATE_KM_PER_SEC * delta
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
		spawn_director.add_enemies()
	if Input.is_action_just_pressed("add_meteorites"):
		spawn_director.add_meteorite_storm()
	if Input.is_action_just_pressed("start_meteorite_wave"):
		spawn_director.start_meteorite_wave()
	if Input.is_action_just_pressed("add_decaying_enemy"):
		spawn_director.add_decaying_enemy()
	hud.los_visible = Input.is_action_pressed("toggle_los")
	if Input.is_action_just_pressed("toggle_impact_map"):
		_cycle_map_mode()
	if Input.is_action_just_pressed("toggle_fire_control"):
		if Input.is_key_pressed(KEY_SHIFT):
			_toggle_fire_control_on_all()
		else:
			_toggle_fire_control_on_selected()
	if Input.is_action_just_pressed("toggle_laser_targeting"):
		if Input.is_key_pressed(KEY_SHIFT):
			_toggle_targeting_mode_on_all()
		else:
			_toggle_targeting_mode_on_selected()
	if Input.is_action_just_pressed("toggle_railgun"):
		_toggle_railgun_on_all()
	if Input.is_action_just_pressed("toggle_slug_render"):
		# Visual-only toggle — the simulation has already applied damage
		# at fire-time. Off ⇒ railguns route through the laser-style
		# beam visual (less busy when many guns are firing); On ⇒
		# moving slug projectiles. CombatController owns the flag so
		# the routing decision stays where the visuals are dispatched.
		combat_controller.set_slug_render_enabled(
			not combat_controller.is_slug_render_enabled()
		)


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
	# Fire control adjusts the laser's engagement-range cap; on a
	# railgun-only ship it would toggle a flag nothing reads. Silently
	# no-op so the input doesn't produce confusing HUD blink.
	if sat.team != Satellite.TEAM_PLAYER or not sat.has_laser():
		return
	sat.toggle_fire_control()


# Toggle fire-control mode across every laser-armed player satellite
# at once (Shift+C). Same "consensus then flip" pattern as the
# targeting / railgun toggles. Railgun-only and unarmed ships skip:
# fire control only governs the laser's engagement_range_km cap.
func _toggle_fire_control_on_all() -> void:
	var laser_armed := _laser_armed_player_sats()
	if laser_armed.is_empty():
		return
	var any_off := false
	for sat in laser_armed:
		if not sat.fire_control_active:
			any_off = true
			break
	var target := any_off
	for sat in laser_armed:
		if sat.fire_control_active != target:
			sat.toggle_fire_control()


# Toggle targeting mode on the active player satellite. Targeting
# (MAX DAMAGE / MAX DANGER) is laser-only — the railgun ignores it
# and picks randomly from in-envelope LOS targets — so we silently
# no-op on railgun-only and unarmed ships rather than flipping a
# flag the weapon strategy doesn't read.
func _toggle_targeting_mode_on_selected() -> void:
	if real_satellites.is_empty():
		return
	var idx := planning_selected if planning_mode else selected_ship
	if idx < 0 or idx >= real_satellites.size():
		return
	var sat := real_satellites[idx]
	if sat.team != Satellite.TEAM_PLAYER or not sat.has_laser():
		return
	sat.toggle_targeting_mode()


# Fleet-wide targeting toggle (Shift+L). Same "consensus then flip"
# pattern as the other fleet toggles, but only over laser-armed
# ships — the railgun has no targeting_mode of its own.
func _toggle_targeting_mode_on_all() -> void:
	var laser_armed := _laser_armed_player_sats()
	if laser_armed.is_empty():
		return
	var any_max_damage := false
	for sat in laser_armed:
		if sat.targeting_mode == LaserWeapon.TARGETING_MAX_DAMAGE:
			any_max_damage = true
			break
	var target_mode := (
		LaserWeapon.TARGETING_MAX_DANGER if any_max_damage
		else LaserWeapon.TARGETING_MAX_DAMAGE
	)
	for sat in laser_armed:
		if sat.targeting_mode != target_mode:
			sat.toggle_targeting_mode()


# Fleet-wide railgun gate (X). If any railgun-armed player ship
# currently has it on, snap the whole fleet off; otherwise snap them
# all on. Laser-only and unarmed ships skip — railgun_enabled is
# meaningless on them.
func _toggle_railgun_on_all() -> void:
	var rg_armed := _railgun_armed_player_sats()
	if rg_armed.is_empty():
		return
	var any_on := false
	for sat in rg_armed:
		if sat.railgun_enabled:
			any_on = true
			break
	var target := not any_on
	for sat in rg_armed:
		if sat.railgun_enabled != target:
			sat.toggle_railgun()


func _armed_player_sats() -> Array[Satellite]:
	var out: Array[Satellite] = []
	for sat in real_satellites:
		if (
			sat.team == Satellite.TEAM_PLAYER
			and not sat.weapons.is_empty()
		):
			out.append(sat)
	return out


# Player ships that carry at least one laser. Drives the laser-only
# fleet toggles (Shift+L targeting, Shift+C fire control) and the
# fleet-wide engagement-range adjustment under Shift+C+arrows.
func _laser_armed_player_sats() -> Array[Satellite]:
	var out: Array[Satellite] = []
	for sat in real_satellites:
		if sat.team == Satellite.TEAM_PLAYER and sat.has_laser():
			out.append(sat)
	return out


# Player ships that carry at least one railgun. Drives the fleet-wide
# X toggle for the railgun on/off gate.
func _railgun_armed_player_sats() -> Array[Satellite]:
	var out: Array[Satellite] = []
	for sat in real_satellites:
		if sat.team == Satellite.TEAM_PLAYER and sat.has_railgun():
			out.append(sat)
	return out


# Cycle the lower-right overlay between surface map / wave radar / off.
# Both Control nodes share the same anchor slot, so flipping visibility
# is enough to swap them — there's no transition state to manage.
func _cycle_map_mode() -> void:
	map_mode = (map_mode + 1) % MAP_MODE_COUNT
	_apply_map_mode()


func _apply_map_mode() -> void:
	if impact_map != null:
		impact_map.visible = (map_mode == MAP_MODE_SURFACE)
	if radar_map != null:
		radar_map.visible = (map_mode == MAP_MODE_RADAR)


# Auto-switch the lower-right overlay around incoming-wave transitions.
# Radar selects on rising edge (a wave just appeared in the queue),
# surface map selects on falling edge (the last wave just drained).
# Edge-triggered so a manual K press during a live wave doesn't keep
# snapping the panel back to radar every frame.
func _auto_switch_map_mode() -> void:
	var inbound := spawn_director.has_active_waves()
	if inbound and not _wave_inbound_prev:
		map_mode = MAP_MODE_RADAR
		_apply_map_mode()
	elif not inbound and _wave_inbound_prev:
		map_mode = MAP_MODE_SURFACE
		_apply_map_mode()
	_wave_inbound_prev = inbound


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
	# HP at impact drives both the 3D explosion radius and the minimap
	# marker size — a fresh boss leaves a much bigger crater visual
	# than a fragment that's been chewed down by point defence.
	var impact_hp: float = maxf(sat.hp, 0.0)
	impact_tracker.record_impact(sat.orbit.r, phase, ocean_hint, impact_hp)
	_spawn_impact_explosion(surface_pos, impact_hp)


func _spawn_impact_explosion(surface_pos: Vector3, hp: float) -> void:
	var explosion := ImpactExplosion.new()
	explosion.peak_radius_km = ImpactExplosion.hp_to_peak_radius_km(hp)
	add_child(explosion)
	explosion.set_impact_position(surface_pos)


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
