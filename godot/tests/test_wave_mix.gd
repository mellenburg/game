extends "res://tests/framework.gd"
## Wave size-class + decaying-orbit composition tests. SpawnDirector's
## start_meteorite_wave now mixes 20 bodies across small / medium /
## large mass bands with a 4-8 decaying-orbit subset drawn from the
## medium / large slots; these tests pin down each invariant the wave
## generator is supposed to honour. Driven through the public API with
## a seeded RNG so the exact spec list is reproducible.

const SpawnDirector = preload("res://scripts/spawn_director.gd")
const Satellite = preload("res://scripts/satellite.gd")
const MeteoriteWave = preload("res://scripts/meteorite_wave.gd")


func _make_director(rng_seed: int) -> Array:
	var container := Node3D.new()
	var sats: Array[Satellite] = []
	var sd := SpawnDirector.new()
	sd.setup(container, sats, null)
	# Override the randomized seed so the spec composition is
	# deterministic across this test's invocations.
	sd._rng.seed = rng_seed
	return [sd, container]


func _classify(mass: float) -> int:
	if mass <= SpawnDirector.SMALL_MASS_MAX_KG:
		return SpawnDirector.SIZE_SMALL
	if mass <= SpawnDirector.MEDIUM_MASS_MAX_KG:
		return SpawnDirector.SIZE_MEDIUM
	if mass <= SpawnDirector.LARGE_MASS_MAX_KG:
		return SpawnDirector.SIZE_LARGE
	return SpawnDirector.SIZE_EXTRA_LARGE


# Drive a spread of seeds so the bands — not a single roll — are what
# actually gets covered. 32 seeds × 20 bodies is plenty to land hits on
# each (large=0..3, decaying=4..8) combination at least once.
const TRIAL_COUNT: int = 32


func test_wave_total_count_is_20() -> void:
	var bundle := _make_director(1)
	var sd: SpawnDirector = bundle[0]
	sd.start_meteorite_wave()
	var wave: MeteoriteWave = sd.meteorite_waves[0]
	assert_eq(wave.pending.size(), 20)
	bundle[1].queue_free()


func test_size_class_counts_within_bands_across_seeds() -> void:
	# Per-trial bands mirror the SpawnDirector constants — every roll
	# must land inside the declared 4-class bracket and the four
	# counts must sum to METEORITE_WAVE_COUNT.
	for s in range(TRIAL_COUNT):
		var bundle := _make_director(s + 1)
		var sd: SpawnDirector = bundle[0]
		sd.start_meteorite_wave()
		var wave: MeteoriteWave = sd.meteorite_waves[0]
		var n_small := 0
		var n_medium := 0
		var n_large := 0
		var n_extra_large := 0
		for entry: Dictionary in wave.pending:
			var m: float = entry["mass"]
			var cls := _classify(m)
			if cls == SpawnDirector.SIZE_SMALL:
				n_small += 1
			elif cls == SpawnDirector.SIZE_MEDIUM:
				n_medium += 1
			elif cls == SpawnDirector.SIZE_LARGE:
				n_large += 1
			else:
				n_extra_large += 1
		assert_eq(n_small + n_medium + n_large + n_extra_large, 20,
			"seed %d totals don't sum to 20" % s)
		assert_true(
			n_small >= SpawnDirector.WAVE_SMALL_COUNT_MIN
			and n_small <= SpawnDirector.WAVE_SMALL_COUNT_MAX,
			"seed %d small=%d outside [%d,%d]" % [
				s, n_small,
				SpawnDirector.WAVE_SMALL_COUNT_MIN,
				SpawnDirector.WAVE_SMALL_COUNT_MAX,
			])
		assert_true(
			n_medium >= SpawnDirector.WAVE_MEDIUM_COUNT_MIN
			and n_medium <= SpawnDirector.WAVE_MEDIUM_COUNT_MAX,
			"seed %d medium=%d outside [%d,%d]" % [
				s, n_medium,
				SpawnDirector.WAVE_MEDIUM_COUNT_MIN,
				SpawnDirector.WAVE_MEDIUM_COUNT_MAX,
			])
		assert_true(
			n_large >= SpawnDirector.WAVE_LARGE_COUNT_MIN
			and n_large <= SpawnDirector.WAVE_LARGE_COUNT_MAX,
			"seed %d large=%d outside [%d,%d]" % [
				s, n_large,
				SpawnDirector.WAVE_LARGE_COUNT_MIN,
				SpawnDirector.WAVE_LARGE_COUNT_MAX,
			])
		assert_true(
			n_extra_large >= SpawnDirector.WAVE_EXTRA_LARGE_COUNT_MIN
			and n_extra_large <= SpawnDirector.WAVE_EXTRA_LARGE_COUNT_MAX,
			"seed %d extra_large=%d outside [%d,%d]" % [
				s, n_extra_large,
				SpawnDirector.WAVE_EXTRA_LARGE_COUNT_MIN,
				SpawnDirector.WAVE_EXTRA_LARGE_COUNT_MAX,
			])
		bundle[1].queue_free()


func test_mass_within_class_band() -> void:
	# Every body's sampled mass lands inside the declared band for its
	# size class — no overlap, no out-of-range values. Ceiling is the
	# extra-large band's max (the heaviest class); floor is the small
	# band's min.
	var bundle := _make_director(7)
	var sd: SpawnDirector = bundle[0]
	sd.start_meteorite_wave()
	var wave: MeteoriteWave = sd.meteorite_waves[0]
	for entry: Dictionary in wave.pending:
		var m: float = entry["mass"]
		assert_true(m >= SpawnDirector.SMALL_MASS_MIN_KG,
			"mass %f below smallest band floor" % m)
		assert_true(m <= SpawnDirector.EXTRA_LARGE_MASS_MAX_KG,
			"mass %f above largest band ceiling" % m)
	bundle[1].queue_free()


func test_decaying_count_in_band_and_only_heavy() -> void:
	# 4-8 decaying bodies per wave; every decaying spec must be on a
	# medium or large body (small bodies are always plain meteorites).
	for s in range(TRIAL_COUNT):
		var bundle := _make_director(s + 100)
		var sd: SpawnDirector = bundle[0]
		sd.start_meteorite_wave()
		var wave: MeteoriteWave = sd.meteorite_waves[0]
		var d_count := 0
		for entry: Dictionary in wave.pending:
			var is_dec: bool = entry.get("is_decaying", false)
			if is_dec:
				d_count += 1
				var m: float = entry["mass"]
				var cls := _classify(m)
				assert_true(cls != SpawnDirector.SIZE_SMALL,
					"seed %d decaying spec on small mass %f" % [s, m])
		assert_true(d_count >= 4 and d_count <= 8,
			"seed %d decaying count %d outside [4,8]" % [s, d_count])
		bundle[1].queue_free()


func test_wave_specs_carry_density_and_composition() -> void:
	# Every spec the wave generator emits should ship a sampled density
	# and composition class. The impact-map readout / per-body HP both
	# depend on these being populated up front.
	const MeteorPhysics = preload("res://scripts/meteor_physics.gd")
	var bundle := _make_director(13)
	var sd: SpawnDirector = bundle[0]
	sd.start_meteorite_wave()
	var wave: MeteoriteWave = sd.meteorite_waves[0]
	for entry: Dictionary in wave.pending:
		assert_true(entry.has("density"), "spec missing density")
		assert_true(entry.has("composition"), "spec missing composition")
		var d: float = float(entry["density"])
		var comp: int = int(entry["composition"])
		assert_true(d > 0.0, "density %f not positive" % d)
		assert_true(
			comp >= 0 and comp < MeteorPhysics.COMP_TABLE.size(),
			"composition %d out of range" % comp,
		)
	bundle[1].queue_free()


func test_wave_metadata_is_set() -> void:
	# duration_sec / lateral_spread_km must be populated so the radar
	# overlay can normalise blip positions without reaching back into
	# spawn_director's constants.
	var bundle := _make_director(11)
	var sd: SpawnDirector = bundle[0]
	sd.start_meteorite_wave()
	var wave: MeteoriteWave = sd.meteorite_waves[0]
	assert_true(wave.duration_sec > 0.0)
	assert_true(wave.lateral_spread_km > 0.0)
	bundle[1].queue_free()


# Extra-large is a guaranteed presence in every wave (count_min == 1),
# so a single seed is enough — no need to sweep TRIAL_COUNT here.
func test_every_wave_contains_at_least_one_extra_large() -> void:
	for s in range(TRIAL_COUNT):
		var bundle := _make_director(s + 200)
		var sd: SpawnDirector = bundle[0]
		sd.start_meteorite_wave()
		var wave: MeteoriteWave = sd.meteorite_waves[0]
		var n_xl := 0
		for entry: Dictionary in wave.pending:
			var m: float = entry["mass"]
			if _classify(m) == SpawnDirector.SIZE_EXTRA_LARGE:
				n_xl += 1
		assert_true(n_xl >= 1,
			"seed %d produced wave without an extra-large body" % s)
		bundle[1].queue_free()


# The XL band is disjoint from large; pin the floor and ceiling so a
# constant tweak that overlaps the bands gets caught immediately.
func test_extra_large_mass_band_is_disjoint_from_large() -> void:
	const MeteorPhysics = preload("res://scripts/meteor_physics.gd")
	# LARGE ceiling and XL floor share the same value (they butt up
	# against each other on the log axis); the ranges themselves don't
	# overlap because each sampler is exclusive on the relevant side.
	assert_close(
		MeteorPhysics.LARGE_MASS_MAX_KG,
		MeteorPhysics.EXTRA_LARGE_MASS_MIN_KG,
		1.0e-3,
		"large band ceiling and xl floor must meet exactly",
	)
	assert_true(
		MeteorPhysics.EXTRA_LARGE_MASS_MAX_KG
		> MeteorPhysics.EXTRA_LARGE_MASS_MIN_KG,
		"xl ceiling must exceed xl floor",
	)


# A heavy body that falls inside the XL band must come out of the
# `_sample_mass_for_class(SIZE_EXTRA_LARGE)` path. Sampling many times
# with a seeded RNG covers the log-uniform spread without flaking.
func test_sample_mass_for_extra_large_class_lands_in_band() -> void:
	var bundle := _make_director(42)
	var sd: SpawnDirector = bundle[0]
	for _i in range(64):
		var m: float = sd._sample_mass_for_class(SpawnDirector.SIZE_EXTRA_LARGE)
		assert_true(
			m >= SpawnDirector.EXTRA_LARGE_MASS_MIN_KG
			and m <= SpawnDirector.EXTRA_LARGE_MASS_MAX_KG,
			"xl mass %f outside [%f, %f]" % [
				m,
				SpawnDirector.EXTRA_LARGE_MASS_MIN_KG,
				SpawnDirector.EXTRA_LARGE_MASS_MAX_KG,
			],
		)
	bundle[1].queue_free()


# Decaying-orbit slots must be drawn only from medium/large/xl bodies —
# small impactors are always plain meteorites. Coverage piggybacks on
# the same `_classify` upgrade that distinguishes XL: a regression that
# routed XL into the small bin would break the existing decaying test
# but a regression that flagged a small body as decaying needs its own
# explicit guard.
func test_decaying_never_lands_on_small_or_outside_heavy_set() -> void:
	for s in range(TRIAL_COUNT):
		var bundle := _make_director(s + 300)
		var sd: SpawnDirector = bundle[0]
		sd.start_meteorite_wave()
		var wave: MeteoriteWave = sd.meteorite_waves[0]
		for entry: Dictionary in wave.pending:
			if not entry.get("is_decaying", false):
				continue
			var m: float = entry["mass"]
			var cls := _classify(m)
			assert_true(
				cls == SpawnDirector.SIZE_MEDIUM
				or cls == SpawnDirector.SIZE_LARGE
				or cls == SpawnDirector.SIZE_EXTRA_LARGE,
				"seed %d decaying spec on non-heavy mass %f (cls=%d)" % [
					s, m, cls
				],
			)
		bundle[1].queue_free()
