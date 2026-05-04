extends "res://tests/framework.gd"
## MeteorPhysics tests. Pure RefCounted module: burn-up threshold,
## HP-from-mass formula, damage-radius bands, density / composition
## sampling. Headless-safe — no SceneTree needed.

const MeteorPhysics = preload("res://scripts/meteor_physics.gd")


func test_burn_up_threshold() -> void:
	# Bodies under the burn-up floor never reach the surface intact.
	assert_true(MeteorPhysics.is_burn_up(0.0))
	assert_true(MeteorPhysics.is_burn_up(1.0))
	assert_true(MeteorPhysics.is_burn_up(MeteorPhysics.BURN_UP_THRESHOLD_KG - 1.0))
	# At and above the threshold the body counts as making it through.
	assert_false(MeteorPhysics.is_burn_up(MeteorPhysics.BURN_UP_THRESHOLD_KG))
	assert_false(MeteorPhysics.is_burn_up(1.0e9))


func test_hp_scales_linearly_with_mass_and_density() -> void:
	# HP_for is exactly HP_PER_KG_PER_DENSITY * mass * density. Doubling
	# either factor doubles HP; both at zero zeroes HP.
	var hp_a := MeteorPhysics.hp_for(1.0e6, 3.0)
	var hp_double_mass := MeteorPhysics.hp_for(2.0e6, 3.0)
	var hp_double_density := MeteorPhysics.hp_for(1.0e6, 6.0)
	assert_close(hp_double_mass, hp_a * 2.0, 1.0e-3)
	assert_close(hp_double_density, hp_a * 2.0, 1.0e-3)
	assert_close(MeteorPhysics.hp_for(0.0, 3.0), 0.0, 1.0e-9)
	assert_close(MeteorPhysics.hp_for(1.0e6, 0.0), 0.0, 1.0e-9)


func test_damage_radii_cube_root_scaling() -> void:
	# Cube-root-of-mass scaling: a 1000x mass increase grows every
	# tier's radius by exactly 10x. Check at the calibration point
	# (1 Tg ≈ Tunguska) for plausible absolute values too.
	var r_small := MeteorPhysics.damage_radii_km(1.0e6)
	var r_big := MeteorPhysics.damage_radii_km(1.0e9)
	for tier in ["light", "moderate", "heavy"]:
		var ratio: float = float(r_big[tier]) / float(r_small[tier])
		assert_close(ratio, 10.0, 1.0e-3)
	# Tunguska-scale heavy radius lands in the 15-25 km neighbourhood
	# (real-world flatten radius ~25 km — coefficient was tuned to
	# bracket that). Light > moderate > heavy by construction.
	assert_true(float(r_big["heavy"]) > 15.0 and float(r_big["heavy"]) < 30.0)
	assert_true(float(r_big["light"]) > float(r_big["moderate"]))
	assert_true(float(r_big["moderate"]) > float(r_big["heavy"]))


func test_damage_tier_progression() -> void:
	# Sub-threshold → TIER_NONE; the lightest qualifying impacts paint
	# the yellow ring only; bigger ones unlock orange and finally red.
	assert_eq(
		MeteorPhysics.damage_tier_for_mass(1.0e3),
		MeteorPhysics.TIER_NONE,
	)
	assert_eq(
		MeteorPhysics.damage_tier_for_mass(MeteorPhysics.BURN_UP_THRESHOLD_KG),
		MeteorPhysics.TIER_LIGHT,
	)
	assert_eq(
		MeteorPhysics.damage_tier_for_mass(1.0e7),
		MeteorPhysics.TIER_MODERATE,
	)
	assert_eq(
		MeteorPhysics.damage_tier_for_mass(1.0e9),
		MeteorPhysics.TIER_HEAVY,
	)


func test_composition_sample_in_range() -> void:
	# Whichever composition rolls, the sampled density falls inside
	# the table's [lo, hi] band for that class.
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for _i in range(200):
		var s := MeteorPhysics.sample_density(rng)
		var comp: int = int(s["composition"])
		var d: float = float(s["density"])
		assert_true(comp >= 0 and comp < MeteorPhysics.COMP_TABLE.size())
		var lo: float = float(MeteorPhysics.COMP_TABLE[comp][1])
		var hi: float = float(MeteorPhysics.COMP_TABLE[comp][2])
		assert_true(
			d >= lo - 1.0e-6 and d <= hi + 1.0e-6,
			"density %f outside class %d band [%f, %f]" % [d, comp, lo, hi],
		)


func test_composition_weights_sum_to_one() -> void:
	# Sanity: the COMP_TABLE weights sum to 1.0 so sample_composition
	# never falls off the end of the table.
	var total := 0.0
	for row in MeteorPhysics.COMP_TABLE:
		total += float(row[0])
	assert_close(total, 1.0, 1.0e-6)


func test_composition_name_known() -> void:
	assert_eq(MeteorPhysics.composition_name(MeteorPhysics.COMP_S_TYPE), "S-type")
	assert_eq(MeteorPhysics.composition_name(MeteorPhysics.COMP_M_TYPE), "M-type")
	assert_eq(MeteorPhysics.composition_name(-1), "unknown")
	assert_eq(MeteorPhysics.composition_name(99), "unknown")


func test_mass_for_hp_inverts_hp_for() -> void:
	# Round-trip: mass_for_hp(hp_for(m, ρ), ρ) == m. Lets the live-damage
	# path on Satellite recompute mass cleanly from current HP without
	# carrying a separate spawn-mass field.
	for m in [1.0e4, 1.0e7, 1.0e10]:
		for d in [1.6, 3.4, 8.0]:
			var hp := MeteorPhysics.hp_for(m, d)
			var roundtrip := MeteorPhysics.mass_for_hp(hp, d)
			assert_close(roundtrip, m, m * 1.0e-6)
	# Edge cases: zero / negative density returns zero (no divide).
	assert_close(MeteorPhysics.mass_for_hp(100.0, 0.0), 0.0, 1.0e-9)
	assert_close(MeteorPhysics.mass_for_hp(100.0, -1.0), 0.0, 1.0e-9)
	# Negative HP clamps at zero so a damage-overshoot bug can't drive
	# mass negative.
	assert_close(MeteorPhysics.mass_for_hp(-50.0, 3.4), 0.0, 1.0e-9)
