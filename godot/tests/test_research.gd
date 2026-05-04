extends "res://tests/framework.gd"
## Coverage for the Research autoload's pure logic: starting unlocks
## seed correctly, prereq gating refuses out-of-order unlocks, costs
## decrement the pool, and the capacity queries return the highest
## unlocked tier value.
##
## Tests instantiate the script directly (`Research.new()`) — the
## headless test runner is a SceneTree subclass so the autoload isn't
## available as a singleton at this layer.

const ResearchScript = preload("res://scripts/research.gd")
const UnitPart = preload("res://scripts/unit_part.gd")


# Helper: produce a fresh Research instance with reset() applied. The
# script isn't added to a tree — Research only relies on dictionary
# state, so bare instantiation is enough. Typed via the preloaded
# script class so member access (e.g. r.research_points) resolves
# concretely instead of through Variant — strict warnings flag the
# latter as an error.
func _make_research() -> ResearchScript:
	var r: ResearchScript = ResearchScript.new()
	r.reset()
	return r


func test_reset_seeds_starting_tier_only_for_each_chain() -> void:
	var r := _make_research()
	# Tier 0 of every chain is unlocked, tier 1+ is not.
	assert_true(r.is_unlocked("laser_basic"))
	assert_true(r.is_unlocked("railgun_basic"))
	assert_true(r.is_unlocked("cooling_system_basic"))
	assert_true(r.is_unlocked("storage_basic"))
	assert_true(r.is_unlocked("reactor_basic"))
	assert_true(r.is_unlocked("launch_capacity_3"))
	assert_true(r.is_unlocked("ground_defense_1"))
	assert_false(r.is_unlocked("laser_advanced"))
	assert_false(r.is_unlocked("launch_capacity_5"))
	assert_false(r.is_unlocked("ground_defense_2"))


func test_starting_pool_matches_constant() -> void:
	var r := _make_research()
	assert_eq(r.research_points, ResearchScript.STARTING_POINTS)


func test_starting_capacities_are_first_tier_values() -> void:
	var r := _make_research()
	assert_eq(r.launch_capacity(), 3)
	assert_eq(r.ground_defense_capacity(), 1)


func test_can_unlock_refuses_when_prereq_missing() -> void:
	var r := _make_research()
	# Tier 2 is gated behind tier 1 even with points to spare.
	assert_false(r.can_unlock("laser_elite"))
	assert_false(r.can_unlock("launch_capacity_8"))


func test_can_unlock_refuses_when_already_unlocked() -> void:
	var r := _make_research()
	assert_false(r.can_unlock("laser_basic"))


func test_unlock_decrements_pool_and_marks_node() -> void:
	var r := _make_research()
	var before := r.research_points
	assert_true(r.unlock("laser_advanced"))
	assert_true(r.is_unlocked("laser_advanced"))
	assert_eq(r.research_points, before - 200)


func test_unlock_refuses_without_enough_points() -> void:
	var r := _make_research()
	r.research_points = 10
	assert_false(r.unlock("laser_advanced"))
	assert_false(r.is_unlocked("laser_advanced"))
	assert_eq(r.research_points, 10)


func test_chain_unlock_promotes_capacity() -> void:
	var r := _make_research()
	assert_true(r.unlock("launch_capacity_5"))
	assert_eq(r.launch_capacity(), 5)
	assert_true(r.unlock("launch_capacity_8"))
	assert_eq(r.launch_capacity(), 8)
	assert_true(r.unlock("launch_capacity_12"))
	assert_eq(r.launch_capacity(), 12)


func test_ground_defense_chain_promotes_capacity() -> void:
	var r := _make_research()
	assert_true(r.unlock("ground_defense_2"))
	assert_eq(r.ground_defense_capacity(), 2)
	assert_true(r.unlock("ground_defense_3"))
	assert_eq(r.ground_defense_capacity(), 3)


func test_part_unlocked_tracks_component_chain() -> void:
	var r := _make_research()
	# Default-tier parts are reachable from the start.
	assert_true(r.is_part_unlocked("laser_default"))
	assert_true(r.is_part_unlocked("cooling_system_default"))
	# Advanced / elite gated until their tier is unlocked.
	assert_false(r.is_part_unlocked("laser_advanced"))
	assert_false(r.is_part_unlocked("laser_elite"))
	assert_true(r.unlock("laser_advanced"))
	assert_true(r.is_part_unlocked("laser_advanced"))
	assert_false(r.is_part_unlocked("laser_elite"))


func test_part_unlocked_treats_empty_and_unknown_as_unlocked() -> void:
	# Empty slots and ids that aren't in any chain shouldn't get
	# filtered out of the Hangar dropdowns. Pinning the contract here
	# so future refactors don't accidentally reject empty strings.
	var r := _make_research()
	assert_true(r.is_part_unlocked(""))
	assert_true(r.is_part_unlocked("not_a_real_part"))


func test_node_for_returns_empty_for_unknown_id() -> void:
	var r := _make_research()
	assert_true(r.node_for("not_a_node_id").is_empty())


func test_prereq_for_returns_empty_for_first_tier() -> void:
	var r := _make_research()
	assert_eq(r.prereq_for("laser_basic"), "")
	assert_eq(r.prereq_for("laser_advanced"), "laser_basic")
	assert_eq(r.prereq_for("laser_elite"), "laser_advanced")


func test_wave_warning_starts_at_one_hour() -> void:
	# Tier 0 of the early-warning chain is unlocked at reset() and
	# corresponds to one hour of game-time radar lead. The seconds
	# helper is what SpawnDirector reads, so pin the conversion here.
	var r := _make_research()
	assert_close(r.wave_warning_hours(), 1.0)
	assert_close(r.wave_warning_seconds(), 3600.0)


func test_wave_warning_promotes_with_tiers() -> void:
	var r := _make_research()
	assert_true(r.unlock("warning_2h"))
	assert_close(r.wave_warning_hours(), 2.0)
	assert_close(r.wave_warning_seconds(), 7200.0)
	assert_true(r.unlock("warning_4h"))
	assert_close(r.wave_warning_hours(), 4.0)
	assert_close(r.wave_warning_seconds(), 14400.0)


func test_wave_warning_chain_listed_in_all_chains() -> void:
	# The Research tab renders chains off `all_chains`; if the warning
	# chain isn't appended there, the editor never surfaces it.
	var r := _make_research()
	var found := false
	for chain in r.all_chains():
		if String(chain.get("category", "")) == "Early Warning":
			found = true
			break
	assert_true(found, "wave warning chain missing from all_chains()")


func test_elite_part_catalog_multipliers() -> void:
	# Elite-tier facets are 3× the default; pin the contract here so a
	# future tweak to the elite multiplier is loud, the same way the
	# advanced-tier test pins 2×.
	var pairs: Array = [
		["laser_default", "laser_elite"],
		["railgun_default", "railgun_elite"],
		["cooling_system_default", "cooling_system_elite"],
		["energy_storage_default", "energy_storage_elite"],
		["reactor_default", "reactor_elite"],
	]
	for pair in pairs:
		var d := UnitPart.get_by_id(pair[0])
		var e := UnitPart.get_by_id(pair[1])
		assert_close(d.multiplier, 1.0)
		assert_close(e.multiplier, 3.0 * d.multiplier)
