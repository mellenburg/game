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

# Stage catalogue. `id` is the stable key the menu writes to
# selected_stage_id; only entries with playable=true permit Launch.
# The current MVP ships exactly one playable stage — the rest are
# placeholders so the campaign tab has a list to render against.
const STAGES: Array = [
	{
		"id": "luna",
		"name": "Lunar L1",
		"code": "CMP-001",
		"difficulty": "EASY",
		"waves": 4,
		"playable": true,
		"summary": "Defend the Earth-Moon L1 station from light drone harassment.",
	},
	{
		"id": "ceres",
		"name": "Ceres Belt Picket",
		"code": "CMP-003",
		"difficulty": "HARD",
		"waves": 12,
		"playable": false,
		"summary": "Picket the Belt interior anchor against sustained hostile waves.",
	},
	{
		"id": "europa",
		"name": "Europa Survey",
		"code": "CMP-004",
		"difficulty": "HARD",
		"waves": 10,
		"playable": false,
		"summary": "Survey escort under Jovian radiation. (Locked)",
	},
	{
		"id": "saturn",
		"name": "Saturn · Hyperion",
		"code": "CMP-005",
		"difficulty": "BRUTAL",
		"waves": 16,
		"playable": false,
		"summary": "Capital-ship engagement at Hyperion. (Locked)",
	},
]

const DEFAULT_UNIT_COUNT: int = 3

var selected_stage_id: String = "luna"
var unit_pool: Array[UnitConfig] = []
var launches: Array[Launch] = []
# Surface installations placed by the player on the Surface Ops tab.
# Empty by default — surface units are entirely opt-in, so a player who
# never opens that tab launches with the legacy orbital-only roster.
var surface_units: Array[SurfaceUnitConfig] = []
var launched: bool = false

# Monotonic id counters — used to produce stable per-unit ids so a
# launch's unit_id reference survives the operator reordering /
# renaming the pool. The ints are private state; callers don't need to
# look at them.
var _next_unit_seq: int = 1
var _next_launch_seq: int = 1


func _ready() -> void:
	if unit_pool.is_empty():
		reset_units()


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
	for i in range(DEFAULT_UNIT_COUNT):
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
	var launch := Launch.make(launches.size())
	launch.name = "L-%02d" % _next_launch_seq
	_next_launch_seq += 1
	launches.append(launch)
	return launch


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
	var cfg := SurfaceUnitConfig.make(surface_units.size(), lat_deg, lon_deg)
	surface_units.append(cfg)
	return cfg


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
	return has_assigned_launches()


func _make_unit_with_id(unit_name: String) -> UnitConfig:
	var unit := UnitConfig.make_default("U-%d" % _next_unit_seq, unit_name)
	_next_unit_seq += 1
	return unit


func _next_unit_name() -> String:
	return "T-%02d" % _next_unit_seq
