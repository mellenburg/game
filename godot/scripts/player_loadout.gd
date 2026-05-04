extends Node
## Autoload singleton (registered as `PlayerLoadout` in project.godot)
## holding the pre-game player choices the menu tabs configure:
##   - selected_stage_id  — which campaign stage Launch will deploy.
##   - unit_pool          — units the player has built. The Hangar tab
##                          mutates this list; the Orbital Ops tab
##                          assigns these to launches.
##   - launches           — scheduled launches. A launch with no
##                          assigned unit is dropped on Launch press
##                          (purge_unassigned_launches).
##   - launched           — set true on Launch; SpawnDirector reads this
##                          to decide whether to honour `launches` or
##                          fall back to its built-in default fleet (so
##                          the existing test path that boots the scene
##                          standalone keeps working).
##
## Persistent across scene changes since autoloads live on /root.

const UnitConfig = preload("res://scripts/unit_config.gd")
const SurfaceUnitConfig = preload("res://scripts/surface_unit_config.gd")
const Launch = preload("res://scripts/launch.gd")
const Satellite = preload("res://scripts/satellite.gd")
const ReconSettings = preload("res://scripts/recon_settings.gd")

# Pre-game launch capacity, in propellant kg. Each scheduled launch
# debits the budget by Tsiolkovsky-weighted propellant — heavier units
# in higher / more-inclined orbits cost more, equatorial-LEO launches
# cost zero. The fleet won't launch if the cumulative debit exceeds
# this number; the menu's LAUNCH button gates on can_launch().
#
# 50 000 kg fits the new default 3-unit roster (T-01..T-03 at 0°/25°/
# 50° inclination, all 500 km circular). The railgun magazine now
# dominates wet mass (1000 × 20 kg = 20 t per gun ≫ 700 kg airframe),
# which pushes T-03's draw to ~17.8 t alone; total fleet draw lands
# near 18.4 t. The remaining ~32 t of headroom lets the player add
# another railgun unit, tilt a launch into a polar slot, or push one
# unit out to GEO without busting the cap. Loading every slot with a
# railgun and pushing them all to high-inclination GEO will still run
# the budget out — that's the intended tension.
const LAUNCH_PROPELLANT_BUDGET_KG: float = 50000.0

# Stage catalogue. `id` is the stable key the menu writes to
# selected_stage_id; only entries with playable=true permit Launch.
# The current MVP ships exactly one playable stage — the rest are
# placeholders so the campaign tab has a list to render against.
#
# Layout fields (`orbit_radius`, `angle_deg`, `body_radius`, `color`)
# drive the stylized System Map widget on the Campaign tab. They are
# not physically meaningful — orbits are spaced for legibility, with
# Ceres seated visually in the asteroid belt between Mars and Jupiter.
const STAGES: Array = [
	{
		"id": "mercury",
		"name": "Mercury",
		"code": "CMP-001",
		"difficulty": "—",
		"waves": 0,
		"playable": false,
		"summary": "Sun-skimming relay survey. (Locked)",
		"orbit_radius": 0.10,
		"angle_deg": 40.0,
		"body_radius": 5.0,
		"color": Color(0.62, 0.58, 0.55),
	},
	{
		"id": "venus",
		"name": "Venus",
		"code": "CMP-002",
		"difficulty": "—",
		"waves": 0,
		"playable": false,
		"summary": "Cloud-layer aerostat defence. (Locked)",
		"orbit_radius": 0.18,
		"angle_deg": 200.0,
		"body_radius": 8.0,
		"color": Color(0.93, 0.82, 0.55),
	},
	{
		"id": "earth",
		"name": "Earth",
		"code": "CMP-003",
		"difficulty": "EASY",
		"waves": 4,
		"playable": true,
		"summary": "Defend the Earth-Moon L1 station from light drone harassment.",
		"orbit_radius": 0.27,
		"angle_deg": 110.0,
		"body_radius": 9.0,
		"color": Color(0.36, 0.58, 0.92),
	},
	{
		"id": "mars",
		"name": "Mars",
		"code": "CMP-004",
		"difficulty": "MEDIUM",
		"waves": 4,
		"playable": true,
		"summary": (
			"Defend the Phobos staging hold. Lower gravity stretches "
			+ "orbits and turns recoil maneuvers into longer arcs — "
			+ "fleet positioning carries more weight than over Earth."
		),
		"orbit_radius": 0.36,
		"angle_deg": 305.0,
		"body_radius": 7.0,
		"color": Color(0.82, 0.40, 0.28),
	},
	{
		"id": "ceres",
		"name": "Ceres",
		"code": "CMP-005",
		"difficulty": "—",
		"waves": 0,
		"playable": false,
		"summary": "Picket the Belt interior anchor. (Locked)",
		"orbit_radius": 0.46,
		"angle_deg": 60.0,
		"body_radius": 4.0,
		"color": Color(0.78, 0.74, 0.66),
	},
	{
		"id": "jupiter",
		"name": "Jupiter",
		"code": "CMP-006",
		"difficulty": "—",
		"waves": 0,
		"playable": false,
		"summary": "Survey escort under Jovian radiation. (Locked)",
		"orbit_radius": 0.58,
		"angle_deg": 230.0,
		"body_radius": 16.0,
		"color": Color(0.86, 0.70, 0.50),
	},
	{
		"id": "saturn",
		"name": "Saturn",
		"code": "CMP-007",
		"difficulty": "—",
		"waves": 0,
		"playable": false,
		"summary": "Capital-ship engagement at Hyperion. (Locked)",
		"orbit_radius": 0.70,
		"angle_deg": 145.0,
		"body_radius": 14.0,
		"color": Color(0.90, 0.82, 0.60),
	},
	{
		"id": "uranus",
		"name": "Uranus",
		"code": "CMP-008",
		"difficulty": "—",
		"waves": 0,
		"playable": false,
		"summary": "Cold-orbit ice picket. (Locked)",
		"orbit_radius": 0.82,
		"angle_deg": 20.0,
		"body_radius": 11.0,
		"color": Color(0.62, 0.84, 0.88),
	},
	{
		"id": "neptune",
		"name": "Neptune",
		"code": "CMP-009",
		"difficulty": "—",
		"waves": 0,
		"playable": false,
		"summary": "Outer-system blockade run. (Locked)",
		"orbit_radius": 0.94,
		"angle_deg": 270.0,
		"body_radius": 11.0,
		"color": Color(0.30, 0.46, 0.88),
	},
]

const DEFAULT_UNIT_COUNT: int = 3


# Look up the current launch cap from Research. Wrapped in a helper so
# `reset_units` and `add_launch` agree on the cap source even when the
# autoload isn't registered (early editor load) — in that case we fall
# back to DEFAULT_UNIT_COUNT so the menu still works.
func _launch_cap() -> int:
	var node := get_node_or_null("/root/Research")
	if node == null:
		return DEFAULT_UNIT_COUNT
	return int(node.launch_capacity())


func _surface_cap() -> int:
	var node := get_node_or_null("/root/Research")
	if node == null:
		return 0
	return int(node.ground_defense_capacity())

var selected_stage_id: String = "earth"
var unit_pool: Array[UnitConfig] = []
var launches: Array[Launch] = []
# Surface installations placed by the player on the Surface Ops tab.
# Empty by default — surface units are entirely opt-in, so a player who
# never opens that tab launches with the legacy orbital-only roster.
var surface_units: Array[SurfaceUnitConfig] = []
var launched: bool = false

# Wave / wave-unit configuration the player edits via the Recon tab in
# the pre-game menu and the Settings panel in the in-game pause menu.
# Mission.start consumes this once per run; live edits queue for the
# next launch rather than rerolling the running schedule.
var recon_settings: ReconSettings = ReconSettings.default_settings()

# Monotonic id counters — used to produce stable per-unit ids so a
# launch's unit_id reference survives the operator reordering /
# renaming the pool. The ints are private state; callers don't need to
# look at them.
var _next_unit_seq: int = 1
var _next_launch_seq: int = 1


func _ready() -> void:
	if unit_pool.is_empty():
		reset_units()
	if recon_settings == null:
		recon_settings = ReconSettings.default_settings()


# Restore wave / wave-unit settings to the shipped defaults. Bound to
# the Recon editor's "Reset" affordance so the player can drop a tuning
# experiment without restarting the process.
func reset_recon_settings() -> void:
	recon_settings = ReconSettings.default_settings()


# Repopulate the unit pool and launch list with the default 3-unit
# roster, with each launch pre-assigned to a unit so a player who
# clicks LAUNCH without touching either tab gets the same starting
# fleet behaviour the previous build shipped with. Two units carry the
# default laser, the third carries the default railgun — matching the
# legacy starting-fleet split.
func reset_units() -> void:
	unit_pool.clear()
	launches.clear()
	_next_unit_seq = 1
	_next_launch_seq = 1
	# Seed at most as many launches as the current research tier
	# permits — a player who's somehow lost capacity since the last run
	# shouldn't end up with launches that immediately fail to schedule.
	var seed_count: int = mini(DEFAULT_UNIT_COUNT, _launch_cap())
	for i in range(seed_count):
		var unit := _make_unit_with_id("T-%02d" % (i + 1))
		# Default loadout mirrors the previous starting fleet: T-01 and
		# T-02 carry a laser, T-03 carries a railgun. set_chassis() has
		# already populated weapon slot 0 with laser_default — flip the
		# third unit to railgun_default so the legacy behaviour holds.
		if i >= 2:
			unit.set_part_id(0, 0, "railgun_default")  # KIND_WEAPON, slot 0
		unit_pool.append(unit)
		var launch := add_launch()
		launch.unit_id = unit.id
		launch.altitude_km = 500.0
		launch.inclination_deg = float(i) * 25.0
		launch.raan_deg = float(i) * 60.0
		launch.true_anomaly_deg = float(i) * 120.0


# Allocate a fresh unit and append it to the pool. Returns the new unit
# so the menu can immediately select it for editing.
func add_unit() -> UnitConfig:
	var unit := _make_unit_with_id(_next_unit_name())
	unit_pool.append(unit)
	return unit


# Remove a unit from the pool by id. Any launches that referenced it
# revert to "unassigned" — they're left in the launch list so the
# operator can pick a replacement, and only get culled on the next
# purge_unassigned_launches() call.
func remove_unit(unit_id: String) -> void:
	for i in range(unit_pool.size() - 1, -1, -1):
		if unit_pool[i].id == unit_id:
			unit_pool.remove_at(i)
	for launch in launches:
		if launch.unit_id == unit_id:
			launch.unit_id = ""


func unit_for_id(unit_id: String) -> UnitConfig:
	for unit in unit_pool:
		if unit.id == unit_id:
			return unit
	return null


# Append a fresh launch with a default orbit. Unassigned by default so
# the operator's first interaction with a new launch is "pick a unit"
# rather than "untangle which preassigned unit got stolen from another
# launch row".
func add_launch() -> Launch:
	# Refuse silently when the operator is at the research-gated cap.
	# Returning null lets the menu treat "couldn't add" as a no-op
	# without reaching into Research itself; callers that don't care
	# about the gate (tests) still see a non-null launch when capacity
	# allows.
	if launches.size() >= _launch_cap():
		return null
	var launch := Launch.make(launches.size())
	launch.name = "L-%02d" % _next_launch_seq
	_next_launch_seq += 1
	launches.append(launch)
	return launch


func can_add_launch() -> bool:
	return launches.size() < _launch_cap()


func remove_launch(index: int) -> void:
	if index < 0 or index >= launches.size():
		return
	launches.remove_at(index)


# Drop launches that aren't carrying a unit. Called when the operator
# presses LAUNCH (and exposed for the menu to call when navigating away
# from the Orbital Ops tab so the orbit preview doesn't keep rendering
# stale rows).
func purge_unassigned_launches() -> void:
	for i in range(launches.size() - 1, -1, -1):
		if not launches[i].has_unit():
			launches.remove_at(i)


# True when the player has at least one launch with a unit assigned.
# SpawnDirector still tolerates an empty list (falls back to its
# legacy random fleet), but the LAUNCH button gates on this so the
# operator can't accidentally start a run with no units.
func has_assigned_launches() -> bool:
	for launch in launches:
		if launch.has_unit():
			return true
	return false


# Append a fresh surface unit at the supplied (lat, lon). Index in the
# returned name is one past the current size, so consecutive presses on
# the Surface Ops map produce S-01, S-02, S-03 …. Caller (the menu)
# refreshes its list display from `surface_units` after this returns.
func add_surface_unit(lat_deg: float, lon_deg: float) -> SurfaceUnitConfig:
	# Same gating story as add_launch: refuse silently when the player
	# is at the ground-defense cap so the placement map's click handler
	# can swallow the no-op without bypassing Research.
	if surface_units.size() >= _surface_cap():
		return null
	var cfg := SurfaceUnitConfig.make(surface_units.size(), lat_deg, lon_deg)
	surface_units.append(cfg)
	return cfg


func can_add_surface_unit() -> bool:
	return surface_units.size() < _surface_cap()


# Remove a surface unit by its index in `surface_units`. Out-of-range
# indices are silently ignored — the menu may double-fire a remove
# button against a stale row while it's rebuilding the list view.
func remove_surface_unit(index: int) -> void:
	if index < 0 or index >= surface_units.size():
		return
	surface_units.remove_at(index)


# Look up a stage record by id. Returns an empty Dictionary when no
# stage matches — callers should treat that as "no selection / not
# launchable" rather than special-casing missing ids.
func stage_for_id(id: String) -> Dictionary:
	for stage in STAGES:
		if stage.get("id", "") == id:
			return stage
	return {}


func selected_stage() -> Dictionary:
	return stage_for_id(selected_stage_id)


func can_launch() -> bool:
	var stage := selected_stage()
	if stage.is_empty() or not bool(stage.get("playable", false)):
		return false
	if not has_assigned_launches():
		return false
	# Budget gate: cumulative propellant draw across assigned launches
	# must fit inside the pre-game capacity. Each launch's draw is
	# Tsiolkovsky-weighted by the assigned unit's wet mass, so the same
	# orbit costs more for a heavier unit — exactly the pressure the
	# operator feels when they overload a single launch.
	return total_launch_propellant_used_kg() <= LAUNCH_PROPELLANT_BUDGET_KG


# Sum of per-launch propellant draws across every assigned launch,
# in kg. Unassigned launches contribute zero (they get purged on
# Launch press anyway). Drives both the budget gate in can_launch()
# and the menu's "Launch budget X / Y kg" readout.
func total_launch_propellant_used_kg() -> float:
	var total: float = 0.0
	for launch in launches:
		if not launch.has_unit():
			continue
		var unit := unit_for_id(launch.unit_id)
		if unit == null:
			continue
		# Wet mass includes the railgun magazine — a 20 t ammo load on a
		# 1 t airframe dwarfs propellant and dominates the booster's
		# rocket-equation draw. unit.wet_mass_kg() is the single source
		# of truth for "how heavy is this unit at launch".
		total += launch.propellant_cost_kg(unit.wet_mass_kg())
	return total


# Convenience for the menu: kg of propellant still available after
# the currently-assigned launches' draws. Negative when over budget;
# the LAUNCH button is gated on can_launch() so a negative number is
# the operator's signal to drop a launch or pick a cheaper orbit.
func launch_propellant_remaining_kg() -> float:
	return LAUNCH_PROPELLANT_BUDGET_KG - total_launch_propellant_used_kg()


func _make_unit_with_id(unit_name: String) -> UnitConfig:
	var unit := UnitConfig.make_default("U-%d" % _next_unit_seq, unit_name)
	_next_unit_seq += 1
	return unit


func _next_unit_name() -> String:
	return "T-%02d" % _next_unit_seq
