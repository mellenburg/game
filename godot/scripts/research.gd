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

# Starting research point pool. Generous on purpose: while the rest of
# the gameplay loop (waves, salvage, mission rewards) isn't wired up,
# 1000 lets the operator unlock the entire current tree and exercise
# every gated UI path during playtesting.
const STARTING_POINTS: int = 1000

# Component chains. Each entry has a category label (drives the
# Research tab's column header) and a `tiers` list. A tier carries the
# stable id used to record the unlock, the player-facing label, the
# point cost, and the catalog part_id this tier grants access to in the
# Hangar.
const COMPONENT_CHAINS: Array = [
	{
		"category": "Lasers",
		"tiers": [
			{"id": "laser_basic", "label": "Basic Laser", "cost": 0, "part_id": "laser_default"},
			{"id": "laser_advanced", "label": "Advanced Laser", "cost": 200, "part_id": "laser_advanced"},
			{"id": "laser_elite", "label": "Elite Laser", "cost": 500, "part_id": "laser_elite"},
		],
	},
	{
		"category": "Railguns",
		"tiers": [
			{"id": "railgun_basic", "label": "Basic Railgun", "cost": 0, "part_id": "railgun_default"},
			{"id": "railgun_advanced", "label": "Advanced Railgun", "cost": 200, "part_id": "railgun_advanced"},
			{"id": "railgun_elite", "label": "Elite Railgun", "cost": 500, "part_id": "railgun_elite"},
		],
	},
	{
		"category": "Radiators",
		"tiers": [
			{"id": "radiator_basic", "label": "Basic Radiator", "cost": 0, "part_id": "radiator_default"},
			{"id": "radiator_advanced", "label": "Advanced Radiator", "cost": 150, "part_id": "radiator_advanced"},
			{"id": "radiator_elite", "label": "Elite Radiator", "cost": 400, "part_id": "radiator_elite"},
		],
	},
	{
		"category": "Energy Storage",
		"tiers": [
			{"id": "storage_basic", "label": "Basic Storage", "cost": 0, "part_id": "energy_storage_default"},
			{"id": "storage_advanced", "label": "Advanced Storage", "cost": 150, "part_id": "energy_storage_advanced"},
			{"id": "storage_elite", "label": "Elite Storage", "cost": 400, "part_id": "energy_storage_elite"},
		],
	},
	{
		"category": "Reactors",
		"tiers": [
			{"id": "reactor_basic", "label": "Basic Reactor", "cost": 0, "part_id": "reactor_default"},
			{"id": "reactor_advanced", "label": "Advanced Reactor", "cost": 150, "part_id": "reactor_advanced"},
			{"id": "reactor_elite", "label": "Elite Reactor", "cost": 400, "part_id": "reactor_elite"},
		],
	},
]

# Number of orbital launches the operator can schedule. `value` is the
# cap when this tier is the highest one unlocked.
const LAUNCH_CAPACITY_CHAIN: Array = [
	{"id": "launch_capacity_3", "label": "Launch Capacity I", "cost": 0, "value": 3},
	{"id": "launch_capacity_5", "label": "Launch Capacity II", "cost": 200, "value": 5},
	{"id": "launch_capacity_8", "label": "Launch Capacity III", "cost": 400, "value": 8},
	{"id": "launch_capacity_12", "label": "Launch Capacity IV", "cost": 800, "value": 12},
]

# Maximum number of ground defense stations the operator can place on
# the Surface Ops map. Same shape as launch capacity.
const GROUND_DEFENSE_CHAIN: Array = [
	{"id": "ground_defense_1", "label": "Ground Defense I", "cost": 0, "value": 1},
	{"id": "ground_defense_2", "label": "Ground Defense II", "cost": 300, "value": 2},
	{"id": "ground_defense_3", "label": "Ground Defense III", "cost": 700, "value": 3},
]

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
	for chain in _all_chains():
		if chain.is_empty():
			continue
		var first: Dictionary = chain[0]
		unlocked[String(first["id"])] = true


func is_unlocked(node_id: String) -> bool:
	return bool(unlocked.get(node_id, false))


# Look up a tier by its node id. Empty Dictionary means "no such node"
# — callers should treat that as locked / inert rather than crashing.
func node_for(node_id: String) -> Dictionary:
	for chain in _all_chains():
		for tier in chain:
			if String(tier.get("id", "")) == node_id:
				return tier
	return {}


# Id of the tier directly preceding `node_id` in its chain. Empty
# string when `node_id` is the chain's first tier (cost-0 starter) or
# isn't in any chain.
func prereq_for(node_id: String) -> String:
	for chain in _all_chains():
		for i in range(chain.size()):
			if String(chain[i].get("id", "")) == node_id:
				if i == 0:
					return ""
				return String(chain[i - 1].get("id", ""))
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
	return _capacity_from_chain(LAUNCH_CAPACITY_CHAIN)


func ground_defense_capacity() -> int:
	return _capacity_from_chain(GROUND_DEFENSE_CHAIN)


# Internal: scan a capacity chain and return the largest `value` whose
# id has been unlocked.
func _capacity_from_chain(chain: Array) -> int:
	var cap: int = 0
	for tier in chain:
		if is_unlocked(String(tier["id"])):
			cap = max(cap, int(tier.get("value", 0)))
	return cap


# Iterate every chain (component chains plus the two capacity chains)
# in a single sequence. Returned as Variant arrays because GDScript's
# strict typing won't let us mix Array[Dictionary] (the component
# tiers) with the capacity chains in one typed return.
func _all_chains() -> Array:
	var out: Array = []
	for cat in COMPONENT_CHAINS:
		out.append(cat["tiers"])
	out.append(LAUNCH_CAPACITY_CHAIN)
	out.append(GROUND_DEFENSE_CHAIN)
	return out
