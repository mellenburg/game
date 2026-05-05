extends "res://tests/framework.gd"
## ReconSettings / WaveUnitClass / WaveComposition pure-data tests.
## Range sampling, barycentric normalisation, and largest-remainder
## rounding live on these Resources; the editor and the spawn director
## both lean on them so a regression here ripples into both UI and sim.

const ReconSettings = preload("res://scripts/recon_settings.gd")
const WaveUnitClass = preload("res://scripts/wave_unit_class.gd")
const WaveComposition = preload("res://scripts/wave_composition.gd")


func _seeded_rng(seed_value: int = 1) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


# ---------- WaveUnitClass ----------

func test_default_classes_have_distinct_progression() -> void:
	# Alpha / beta / gamma defaults should escalate in count, in
	# decaying ratio, and in heavy-object share. If a balance pass
	# blurs that ordering the test will catch it.
	var a := WaveUnitClass.default_alpha()
	var b := WaveUnitClass.default_beta()
	var g := WaveUnitClass.default_gamma()
	assert_true(b.count_max >= a.count_max,
		"beta count cap should not regress below alpha")
	assert_true(g.count_max >= b.count_max,
		"gamma count cap should not regress below beta")
	assert_true(b.decaying_ratio_max > a.decaying_ratio_max,
		"beta decaying share should exceed alpha")
	assert_true(g.decaying_ratio_max > b.decaying_ratio_max,
		"gamma decaying share should exceed beta")
	assert_true(b.size_large >= a.size_large,
		"beta should have at least as many large objects as alpha")
	assert_true(g.size_large >= b.size_large,
		"gamma should have the most large-object share")


func test_sample_count_returns_value_in_range() -> void:
	var c := WaveUnitClass.new()
	c.count_min = 4
	c.count_max = 9
	var rng := _seeded_rng()
	for _i in range(50):
		var n := c.sample_count(rng)
		assert_true(n >= 4 and n <= 9, "sampled count %d outside [4, 9]" % n)


func test_sample_count_collapses_when_min_equals_max() -> void:
	var c := WaveUnitClass.new()
	c.count_min = 7
	c.count_max = 7
	var rng := _seeded_rng()
	for _i in range(20):
		assert_eq(c.sample_count(rng), 7)


func test_sample_decaying_ratio_in_range() -> void:
	var c := WaveUnitClass.new()
	c.decaying_ratio_min = 0.1
	c.decaying_ratio_max = 0.6
	var rng := _seeded_rng()
	for _i in range(50):
		var r := c.sample_decaying_ratio(rng)
		assert_true(r >= 0.1 - 1.0e-9 and r <= 0.6 + 1.0e-9,
			"sampled ratio %f outside [0.1, 0.6]" % r)


func test_object_size_counts_sum_to_total() -> void:
	# Largest-remainder rounding must yield four integers summing to
	# the requested count exactly; a naive `round(count * w)` would
	# leave a 0/+1/-1 gap on some splits.
	var c := WaveUnitClass.new()
	c.size_small = 0.40
	c.size_medium = 0.30
	c.size_large = 0.20
	c.size_extra_large = 0.10
	for n in [1, 5, 7, 13, 20, 100, 999]:
		var counts := c.sample_object_size_counts(n)
		var total := (
			int(counts["small"])
			+ int(counts["medium"])
			+ int(counts["large"])
			+ int(counts["extra_large"])
		)
		assert_eq(total, n,
			"size-band total %d != input %d for split %s" % [
				total, n, [
					counts["small"], counts["medium"],
					counts["large"], counts["extra_large"],
				]
			])


func test_object_size_counts_handles_zero_weights_gracefully() -> void:
	# All-zero weights should still produce a well-formed split via
	# the normalize-on-degenerate fallback (1/4 each across the four
	# size classes), not a crash.
	var c := WaveUnitClass.new()
	c.size_small = 0.0
	c.size_medium = 0.0
	c.size_large = 0.0
	c.size_extra_large = 0.0
	var counts := c.sample_object_size_counts(9)
	var total := (
		int(counts["small"])
		+ int(counts["medium"])
		+ int(counts["large"])
		+ int(counts["extra_large"])
	)
	assert_eq(total, 9)


func test_normalized_weights_sum_to_one() -> void:
	var c := WaveUnitClass.new()
	c.size_small = 2.0
	c.size_medium = 3.0
	c.size_large = 4.0
	c.size_extra_large = 1.0
	var n := c.normalized_weights()
	assert_close(n[0] + n[1] + n[2] + n[3], 1.0, 1.0e-6)
	assert_close(n[0], 0.2, 1.0e-6)
	assert_close(n[1], 0.3, 1.0e-6)
	assert_close(n[2], 0.4, 1.0e-6)
	assert_close(n[3], 0.1, 1.0e-6)


func test_normalize_in_place_mutates_fields() -> void:
	var c := WaveUnitClass.new()
	c.size_small = 4.0
	c.size_medium = 4.0
	c.size_large = 4.0
	c.size_extra_large = 4.0
	c.normalize_weights_in_place()
	assert_close(c.size_small, 0.25, 1.0e-6)
	assert_close(c.size_medium, 0.25, 1.0e-6)
	assert_close(c.size_large, 0.25, 1.0e-6)
	assert_close(c.size_extra_large, 0.25, 1.0e-6)


func test_clamp_count_range_swaps_inverted_handles() -> void:
	var c := WaveUnitClass.new()
	c.count_min = 50
	c.count_max = 10
	c.clamp_count_range()
	assert_eq(c.count_min, 10)
	assert_eq(c.count_max, 50)


func test_clamp_decaying_range_clamps_to_unit_interval() -> void:
	var c := WaveUnitClass.new()
	c.decaying_ratio_min = -0.5
	c.decaying_ratio_max = 1.5
	c.clamp_decaying_range()
	assert_close(c.decaying_ratio_min, 0.0, 1.0e-9)
	assert_close(c.decaying_ratio_max, 1.0, 1.0e-9)


func test_duplicate_class_makes_independent_copy() -> void:
	var c := WaveUnitClass.default_beta()
	var d := c.duplicate_class()
	d.count_min = 999
	d.location_arc_deg = 1.0
	d.time_spread_min = 1.0
	assert_true(c.count_min != d.count_min,
		"mutation on duplicate must not bleed to source")
	assert_true(c.location_arc_deg != d.location_arc_deg,
		"location arc duplicate independence")
	assert_true(c.time_spread_min != d.time_spread_min,
		"time spread duplicate independence")


func test_clamp_location_arc_keeps_within_band() -> void:
	var c := WaveUnitClass.new()
	c.location_arc_deg = 5.0
	c.clamp_location_arc()
	assert_close(c.location_arc_deg, WaveUnitClass.ARC_MIN_DEG, 1.0e-9)
	c.location_arc_deg = 999.0
	c.clamp_location_arc()
	assert_close(c.location_arc_deg, WaveUnitClass.ARC_MAX_DEG, 1.0e-9)


func test_clamp_time_spread_keeps_within_band() -> void:
	var c := WaveUnitClass.new()
	c.time_spread_min = 0.1
	c.clamp_time_spread()
	assert_close(c.time_spread_min, WaveUnitClass.TIME_SPREAD_MIN_MIN, 1.0e-9)
	c.time_spread_min = 9999.0
	c.clamp_time_spread()
	assert_close(c.time_spread_min, WaveUnitClass.TIME_SPREAD_MAX_MIN, 1.0e-9)


func test_time_spread_sec_converts_minutes_to_seconds() -> void:
	# Editor edits in minutes; spawn director consumes seconds. The
	# helper is the boundary — pin the conversion here so a future tweak
	# to the unit doesn't silently slip past the wave timing tests.
	var c := WaveUnitClass.new()
	c.time_spread_min = 5.0
	assert_close(c.time_spread_sec(), 300.0, 1.0e-6)


func test_lateral_spread_for_altitude_scales_with_arc() -> void:
	# Wider arc → larger lateral chord at the same altitude. The
	# legacy 15° arc at the default 50000 km altitude reads ~6500 km
	# (the number SpawnDirector's old constant landed on); 180° at
	# the same altitude saturates at the altitude itself.
	var c := WaveUnitClass.new()
	c.location_arc_deg = 15.0
	var narrow := c.lateral_spread_for_altitude(50000.0)
	c.location_arc_deg = 180.0
	var wide := c.lateral_spread_for_altitude(50000.0)
	assert_true(wide > narrow,
		"180° arc should yield a wider chord than 15° at same altitude")
	assert_close(wide, 50000.0, 1.0e-3,
		"180° arc saturates at altitude")
	assert_true(narrow > 0.0,
		"15° arc should still produce a positive chord")


func test_count_max_capped_at_fifty() -> void:
	# The editor enforces COUNT_MAX = 50 for performance reasons; the
	# constant is the source of truth, so a regression here breaks the
	# slider's top end without anyone noticing.
	assert_eq(WaveUnitClass.COUNT_MAX, 50)


# ---------- WaveComposition ----------

func test_composition_unit_count_sums_classes() -> void:
	var w := WaveComposition.new()
	w.alpha_units = 3
	w.beta_units = 2
	w.gamma_units = 1
	assert_eq(w.unit_count(), 6)


func test_composition_sample_duration_in_range() -> void:
	# Editor edits hours; sample returns sim-seconds. A 2-5 hour range
	# yields samples in [7200, 18000] sim-sec.
	var w := WaveComposition.new()
	w.duration_min = 2.0
	w.duration_max = 5.0
	var rng := _seeded_rng()
	for _i in range(30):
		var d := w.sample_duration(rng)
		assert_true(d >= 7200.0 - 1.0e-6 and d <= 18000.0 + 1.0e-6,
			"duration %f outside [7200, 18000] sim-sec" % d)


func test_composition_sample_delay_in_range() -> void:
	# Same hours-to-seconds boundary as duration. A 1-3 hour delay
	# yields samples in [3600, 10800] sim-sec.
	var w := WaveComposition.new()
	w.delay_min = 1.0
	w.delay_max = 3.0
	var rng := _seeded_rng()
	for _i in range(30):
		var d := w.sample_delay(rng)
		assert_true(d >= 3600.0 - 1.0e-6 and d <= 10800.0 + 1.0e-6,
			"delay %f outside [3600, 10800] sim-sec" % d)


func test_composition_clamp_swaps_inverted_handles() -> void:
	var w := WaveComposition.new()
	w.duration_min = 9.0
	w.duration_max = 3.0
	w.clamp_duration()
	assert_close(w.duration_min, 3.0, 1.0e-9)
	assert_close(w.duration_max, 9.0, 1.0e-9)


# ---------- ReconSettings ----------

func test_default_settings_has_five_waves() -> void:
	var s := ReconSettings.default_settings()
	assert_eq(s.waves.size(), 5)


func test_default_settings_total_unit_counts() -> void:
	# Sum of alpha/beta/gamma unit counts across all five default
	# waves: 7 alpha (1+2+1+2+1), 3 beta (0+0+1+1+1), 2 gamma
	# (0+0+0+1+1). Thinned to ~1/3 of the legacy 20/11/5 totals when
	# the meteorite mass bands moved up to Gg / Tg / Pg-class threats.
	var s := ReconSettings.default_settings()
	var totals := {"alpha": 0, "beta": 0, "gamma": 0}
	for w in s.waves:
		totals["alpha"] += w.alpha_units
		totals["beta"] += w.beta_units
		totals["gamma"] += w.gamma_units
	assert_eq(int(totals["alpha"]), 7)
	assert_eq(int(totals["beta"]), 3)
	assert_eq(int(totals["gamma"]), 2)


func test_class_for_dispatches_by_size_class() -> void:
	var s := ReconSettings.default_settings()
	assert_eq(s.class_for(ReconSettings.SIZE_ALPHA), s.alpha_class)
	assert_eq(s.class_for(ReconSettings.SIZE_BETA), s.beta_class)
	assert_eq(s.class_for(ReconSettings.SIZE_GAMMA), s.gamma_class)


func test_add_wave_appends_to_end() -> void:
	var s := ReconSettings.default_settings()
	var prev := s.waves.size()
	var added := s.add_wave()
	assert_eq(s.waves.size(), prev + 1)
	assert_eq(s.waves[prev], added)


func test_remove_wave_at_drops_row() -> void:
	var s := ReconSettings.default_settings()
	var prev := s.waves.size()
	s.remove_wave_at(0)
	assert_eq(s.waves.size(), prev - 1)


func test_remove_wave_at_ignores_out_of_range() -> void:
	var s := ReconSettings.default_settings()
	var prev := s.waves.size()
	s.remove_wave_at(-1)
	s.remove_wave_at(prev + 5)
	assert_eq(s.waves.size(), prev)


func test_duplicate_settings_makes_independent_copy() -> void:
	var s := ReconSettings.default_settings()
	var d := s.duplicate_settings()
	d.alpha_class.count_min = 999
	d.waves[0].alpha_units = 999
	assert_true(s.alpha_class.count_min != 999,
		"duplicate's class mutation must not bleed to source")
	assert_true(s.waves[0].alpha_units != 999,
		"duplicate's wave mutation must not bleed to source")
