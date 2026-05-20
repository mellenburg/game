extends Node
## Autoload singleton (registered as `Research` in project.godot) holding
## the player's research progress: a pool of research points and a set
## of unlocked research nodes. The Research tab on the menu spends
## points to unlock nodes; other tabs query Research to gate which
## parts the Hangar offers, how many launches the Orbital Ops tab can
## schedule, and how many surface installations the Surface Ops tab can
## place.
##
## Linear progressions only: each chain is a list of tiers and unlocking
## tier N requires tier N-1 to already be unlocked. Tier 0 in every
## chain is the player's starting unlock (cost 0) — `_ready()` seeds the
## unlocked set with those, and `reset()` returns to that baseline.
##
## Pure data + dictionary state — no SceneTree dependency beyond being
## an autoload. Tests instantiate the script directly via `.new()`.

const UnitPart = preload("res://scripts/unit_part.gd")

# Starting research point pool. Generous on purpose: while the rest of
# the gameplay loop (waves, salvage, mission rewards) isn't wired up,
# 6000 lets the operator unlock the entire current tree (≈5450 RP)
# with headroom and exercise every gated UI path during playtesting.
const STARTING_POINTS: int = 6000

# Component chains. Each entry has a category label (drives the
# Research tab's column header), a `stat_template` used to render the
# tier's effect line in the description panel ("%.1f×" gets the part's
# multiplier), a `shape` hint the graph view uses to pick a polygon,
# and a `tiers` list. A tier carries the stable id used to record the
# unlock, the player-facing label, the point cost, the catalog part_id
# this tier grants access to in the Hangar, and a short flavor sentence
# the description panel surfaces.
const COMPONENT_CHAINS: Array = [
	{
		"category": "Lasers",
		"shape": "hex",
		"stat_template": "%.1fx damage per second",
		"tiers": [
			{"id": "laser_basic", "label": "Basic Laser", "cost": 0, "part_id": "laser_default", "flavor": "Standard pulse laser. Reliable, well-understood, slow to dissipate heat."},
			{"id": "laser_advanced", "label": "Advanced Laser", "cost": 200, "part_id": "laser_advanced", "flavor": "Beam coherence holds at higher pulse-repetition rates."},
			{"id": "laser_elite", "label": "Elite Laser", "cost": 500, "part_id": "laser_elite", "flavor": "Adaptive optics steer the beam past atmospheric distortion."},
		],
	},
	{
		"category": "Railguns",
		"shape": "hex",
		"stat_template": "%.1fx damage per shot",
		"tiers": [
			{"id": "railgun_basic", "label": "Basic Railgun", "cost": 0, "part_id": "railgun_default", "flavor": "Conventional electromagnetic accelerator. Slugs depart at orbital velocity."},
			{"id": "railgun_advanced", "label": "Advanced Railgun", "cost": 200, "part_id": "railgun_advanced", "flavor": "Tighter rail tolerances let us push the slug faster without arcing."},
			{"id": "railgun_elite", "label": "Elite Railgun", "cost": 500, "part_id": "railgun_elite", "flavor": "Plasma-armature railgun. The slug arrives before the recoil wave."},
		],
	},
	{
		"category": "Missiles",
		"shape": "hex",
		"stat_template": "%.1fx warhead yield",
		"tiers": [
			{"id": "missile_basic", "label": "Basic Missile Launcher", "cost": 0, "part_id": "missile_default", "flavor": "Storable-bipropellant interceptor with a 100 MT thermonuclear warhead. The Lambert burn computer handles the orbit-matching the operator can't."},
			{"id": "missile_advanced", "label": "Advanced Missile Launcher", "cost": 250, "part_id": "missile_advanced", "flavor": "Enhanced fission primary boosts warhead yield. Same magazine, more dead satellites per shot."},
			{"id": "missile_elite", "label": "Elite Missile Launcher", "cost": 600, "part_id": "missile_elite", "flavor": "Tritium-boosted secondary. The X-ray pulse outshines the sun at lethal range."},
		],
	},
	{
		"category": "Cooling Systems",
		"shape": "hex",
		"stat_template": "%.1fx weapon cooling power",
		"tiers": [
			{"id": "cooling_system_basic", "label": "Basic Cooling System", "cost": 0, "part_id": "cooling_system_default", "flavor": "Folded panel array. Sheds excess heat to vacuum."},
			{"id": "cooling_system_advanced", "label": "Advanced Cooling System", "cost": 150, "part_id": "cooling_system_advanced", "flavor": "Phase-change loop in a graphene substrate."},
			{"id": "cooling_system_elite", "label": "Elite Cooling System", "cost": 400, "part_id": "cooling_system_elite", "flavor": "Liquid-droplet radiator — orders of magnitude more emissive area per kilogram."},
		],
	},
	{
		"category": "Energy Storage",
		"shape": "hex",
		"stat_template": "%.1fx energy capacity",
		"tiers": [
			{"id": "storage_basic", "label": "Basic Storage", "cost": 0, "part_id": "energy_storage_default", "flavor": "Lithium-ion bank. Familiar chemistry, modest energy density."},
			{"id": "storage_advanced", "label": "Advanced Storage", "cost": 150, "part_id": "energy_storage_advanced", "flavor": "Supercapacitor stack with carbon-aerogel electrodes."},
			{"id": "storage_elite", "label": "Elite Storage", "cost": 400, "part_id": "energy_storage_elite", "flavor": "Compact superconducting magnetic energy storage."},
		],
	},
	{
		"category": "Reactors",
		"shape": "hex",
		"stat_template": "%.1fx power generation",
		"tiers": [
			{"id": "reactor_basic", "label": "Basic Reactor", "cost": 0, "part_id": "reactor_default", "flavor": "Solar panel array. Trickle output, but it lasts forever."},
			{"id": "reactor_advanced", "label": "Advanced Reactor", "cost": 150, "part_id": "reactor_advanced", "flavor": "Beta-voltaic isotope battery — longer half-life, higher specific power."},
			{"id": "reactor_elite", "label": "Elite Reactor", "cost": 400, "part_id": "reactor_elite", "flavor": "Fusion-fragment reactor. The future is here, and it's grumbling."},
		],
	},
]

# Number of orbital launches the operator can schedule. `value` is the
# cap when this tier is the highest one unlocked.
const LAUNCH_CAPACITY_CHAIN: Dictionary = {
	"category": "Launch Capacity",
	"shape": "diamond",
	"stat_template": "Plan up to %d simultaneous launches",
	"tiers": [
		{"id": "launch_capacity_15", "label": "Launch Capacity I", "cost": 0, "value": 15, "flavor": "Fifteen orbits per stage. A three-plane laser shell on the Cartesian axes plus a kinetic picket."},
		{"id": "launch_capacity_18", "label": "Launch Capacity II", "cost": 200, "value": 18, "flavor": "Eighteen orbits. Room to thicken the picket without cracking the shell."},
		{"id": "launch_capacity_21", "label": "Launch Capacity III", "cost": 400, "value": 21, "flavor": "Twenty-one orbits. Layered shells start to pay dividends."},
		{"id": "launch_capacity_24", "label": "Launch Capacity IV", "cost": 800, "value": 24, "flavor": "Twenty-four orbits. Operations on this scale used to require a coalition."},
	],
}

# Maximum number of ground defense stations the operator can place on
# the Surface Ops map. Same shape as launch capacity.
const GROUND_DEFENSE_CHAIN: Dictionary = {
	"category": "Ground Defense",
	"shape": "octagon",
	"stat_template": "Place up to %d surface emplacement(s)",
	"tiers": [
		{"id": "ground_defense_1", "label": "Ground Defense I", "cost": 0, "value": 1, "flavor": "One ground emplacement. A single anchor of fire support."},
		{"id": "ground_defense_2", "label": "Ground Defense II", "cost": 300, "value": 2, "flavor": "Two emplacements. Crossfire becomes possible."},
		{"id": "ground_defense_3", "label": "Ground Defense III", "cost": 700, "value": 3, "flavor": "Three emplacements. Continuous coverage along likely re-entry paths."},
	],
}

# Lead time the wave radar gets before each body actually enters play.
# `value` is in *game-time hours* — radar visibility scales with
# time_factor automatically because the wave preroll counter ticks in
# sim-seconds. The starting tier reproduces (roughly) the legacy 10-real-
# second window at the previous time_factor=500 default (5000 sim-sec
# ≈ 1.4 h); upgrades extend that lead so a forewarned operator can
# pre-position units long before impact.
const WAVE_WARNING_CHAIN: Dictionary = {
	"category": "Early Warning",
	"shape": "diamond",
	"stat_template": "%.1f h advance warning",
	"tiers": [
		{"id": "warning_1h", "label": "Early Warning I", "cost": 0, "value": 1.0, "flavor": "Standard radar suite. Roughly an hour of warning before bodies enter play."},
		{"id": "warning_2h", "label": "Early Warning II", "cost": 200, "value": 2.0, "flavor": "Wider-aperture phased array. Doubles the radar lead time."},
		{"id": "warning_4h", "label": "Early Warning III", "cost": 500, "value": 4.0, "flavor": "Deep-space sensor mesh. Four hours' notice on every incoming wave."},
	],
}

var research_points: int = STARTING_POINTS
# node_id (String) → true. Absence means locked. Use `is_unlocked`
# rather than indexing directly so callers don't depend on the dict
# default-value contract.
var unlocked: Dictionary = {}


func _ready() -> void:
	if unlocked.is_empty():
		reset()


# Drop all unlocks and refund the starting pool. Re-seeds tier 0 of
# every chain (the cost-0 starting unlocks the player begins with).
# Exposed so tests can reset between cases and so a future "new run"
# button on the menu has a single entry point.
func reset() -> void:
	research_points = STARTING_POINTS
	unlocked.clear()
	for tiers in _all_tier_lists():
		if tiers.is_empty():
			continue
		var first: Dictionary = tiers[0]
		unlocked[String(first["id"])] = true


func is_unlocked(node_id: String) -> bool:
	return bool(unlocked.get(node_id, false))


# Look up a tier by its node id. Empty Dictionary means "no such node"
# — callers should treat that as locked / inert rather than crashing.
func node_for(node_id: String) -> Dictionary:
	for tiers in _all_tier_lists():
		for tier in tiers:
			if String(tier.get("id", "")) == node_id:
				return tier
	return {}


# Id of the tier directly preceding `node_id` in its chain. Empty
# string when `node_id` is the chain's first tier (cost-0 starter) or
# isn't in any chain.
func prereq_for(node_id: String) -> String:
	for tiers in _all_tier_lists():
		for i in range(tiers.size()):
			if String(tiers[i].get("id", "")) == node_id:
				if i == 0:
					return ""
				return String(tiers[i - 1].get("id", ""))
	return ""


# True when the node exists, isn't already unlocked, has its prereq
# satisfied, and the operator has enough points to pay the cost.
func can_unlock(node_id: String) -> bool:
	if is_unlocked(node_id):
		return false
	var node := node_for(node_id)
	if node.is_empty():
		return false
	var prereq := prereq_for(node_id)
	if prereq != "" and not is_unlocked(prereq):
		return false
	return research_points >= int(node.get("cost", 0))


# Spend the cost and mark the node unlocked. Returns false (no-op) when
# `can_unlock` would refuse — the menu uses the return value to decide
# whether a refresh is needed.
func unlock(node_id: String) -> bool:
	if not can_unlock(node_id):
		return false
	var node := node_for(node_id)
	research_points -= int(node.get("cost", 0))
	unlocked[node_id] = true
	return true


# True iff the supplied catalog part_id is reachable by the player. An
# empty / unknown part_id resolves to true so empty slots and unknown
# ids (e.g. removed parts in old saves) don't get filtered out of the
# Hangar dropdowns by accident.
func is_part_unlocked(part_id: String) -> bool:
	if part_id == "":
		return true
	for chain_def in COMPONENT_CHAINS:
		for tier in chain_def["tiers"]:
			if String(tier.get("part_id", "")) == part_id:
				return is_unlocked(String(tier["id"]))
	return true


# Highest unlocked launch-capacity value, or 0 when nothing is unlocked
# yet. The starting unlock guarantees ≥ 3 in normal play.
func launch_capacity() -> int:
	return _capacity_from_chain(LAUNCH_CAPACITY_CHAIN["tiers"])


func ground_defense_capacity() -> int:
	return _capacity_from_chain(GROUND_DEFENSE_CHAIN["tiers"])


# Highest unlocked early-warning tier in *game-time hours*. SpawnDirector
# multiplies by 3600 to set the per-wave preroll window; the starter
# tier (1.0 h) is unlocked at reset() so the radar always has at least
# that much lead time.
func wave_warning_hours() -> float:
	var hours: float = 0.0
	for tier in WAVE_WARNING_CHAIN["tiers"]:
		if is_unlocked(String(tier["id"])):
			hours = maxf(hours, float(tier.get("value", 0.0)))
	return hours


func wave_warning_seconds() -> float:
	return wave_warning_hours() * 3600.0


# Aggregate the catalog into the order the Research tab renders. Every
# entry exposes `category`, `shape`, `stat_template`, and `tiers` so a
# single render loop in the graph view handles components and
# capacity chains uniformly.
func all_chains() -> Array:
	var out: Array = []
	for cat in COMPONENT_CHAINS:
		out.append(cat)
	out.append(LAUNCH_CAPACITY_CHAIN)
	out.append(GROUND_DEFENSE_CHAIN)
	out.append(WAVE_WARNING_CHAIN)
	return out


# Internal: flat list of every chain's tier-array. Used by reset /
# node_for / prereq_for, none of which need the surrounding category
# metadata.
func _all_tier_lists() -> Array:
	var out: Array = []
	for chain in all_chains():
		out.append(chain["tiers"])
	return out


# Build the description-panel payload for a single node. Returns an
# empty Dictionary when `node_id` doesn't match any tier (callers
# should treat that as "nothing selected"). Keys:
#   "id", "label", "category", "cost", "stats", "flavor",
#   "is_unlocked", "can_unlock", "prereq_label"
# `prereq_label` is empty when the node is a chain's first tier or
# when the prereq is already unlocked — the panel only renders it
# when it represents a still-locked dependency.
func describe(node_id: String) -> Dictionary:
	for chain in all_chains():
		var tiers: Array = chain["tiers"]
		for tier in tiers:
			if String(tier["id"]) != node_id:
				continue
			var stats := _stats_for(chain, tier)
			var prereq_id := prereq_for(node_id)
			var prereq_label := ""
			if prereq_id != "" and not is_unlocked(prereq_id):
				prereq_label = String(node_for(prereq_id).get("label", ""))
			return {
				"id": node_id,
				"label": String(tier["label"]),
				"category": String(chain["category"]),
				"cost": int(tier.get("cost", 0)),
				"stats": stats,
				"flavor": String(tier.get("flavor", "")),
				"is_unlocked": is_unlocked(node_id),
				"can_unlock": can_unlock(node_id),
				"prereq_label": prereq_label,
			}
	return {}


# Render the per-tier stat string. Component chains plug the part's
# multiplier into the chain's `stat_template`; capacity chains plug
# the tier's `value`. Both fall back to an empty string if the
# template / source is missing so a malformed entry doesn't crash the
# panel.
func _stats_for(chain: Dictionary, tier: Dictionary) -> String:
	var template := String(chain.get("stat_template", ""))
	if template == "":
		return ""
	if tier.has("part_id"):
		var part := UnitPart.get_by_id(String(tier["part_id"]))
		return template % part.multiplier
	if tier.has("value"):
		# Pass the raw Variant through — `%` adapts to int (%d) and float
		# (%.1f) templates without us needing to know which the chain
		# uses. Capacity chains store ints, the warning chain stores hours
		# as floats; both render correctly off the chain's own template.
		return template % tier["value"]
	return ""


# Internal: scan a capacity chain's tier list and return the largest
# `value` whose id has been unlocked.
func _capacity_from_chain(tiers: Array) -> int:
	var cap: int = 0
	for tier in tiers:
		if is_unlocked(String(tier["id"])):
			cap = max(cap, int(tier.get("value", 0)))
	return cap
