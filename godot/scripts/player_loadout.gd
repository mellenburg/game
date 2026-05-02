extends Node
## Autoload singleton (registered as `PlayerLoadout` in project.godot)
## holding the pre-game player choices the menu tabs configure:
##   - selected_stage_id  — which campaign stage Launch will deploy.
##   - units              — per-unit loadout + initial orbit.
##   - launched           — set true on Launch; SpawnDirector reads this
##                          to decide whether to honour `units` or fall
##                          back to its built-in default fleet (so the
##                          existing test path that boots the scene
##                          standalone keeps working).
##
## Persistent across scene changes since autoloads live on /root.
## Reset between runs of the menu via reset_units() (handled by the
## menu's _ready when launched is false).

const UnitConfig = preload("res://scripts/unit_config.gd")
const SurfaceUnitConfig = preload("res://scripts/surface_unit_config.gd")

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
var units: Array[UnitConfig] = []
# Surface installations placed by the player on the Surface Ops tab.
# Empty by default — surface units are entirely opt-in, so a player who
# never opens that tab launches with the legacy orbital-only roster.
var surface_units: Array[SurfaceUnitConfig] = []
var launched: bool = false


func _ready() -> void:
	if units.is_empty():
		reset_units()


# Repopulate `units` with the default 3-unit roster. Called once on
# autoload init and any time the menu wants a clean slate (e.g. the
# player returns to the main menu after a run).
func reset_units() -> void:
	units.clear()
	for i in range(DEFAULT_UNIT_COUNT):
		units.append(UnitConfig.make(i))


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
	return not stage.is_empty() and bool(stage.get("playable", false))
