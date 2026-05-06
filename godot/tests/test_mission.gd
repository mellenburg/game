extends "res://tests/framework.gd"
## Mission scheduler tests. Pure-state RefCounted so every wave-unit
## timing edge can be checked without booting a SceneTree. Mission
## resolves a ReconSettings into a concrete emission timeline at
## start_from_settings; the schedule is locked from there until the
## next launch.

const Mission = preload("res://scripts/mission.gd")
const ReconSettings = preload("res://scripts/recon_settings.gd")
const WaveComposition = preload("res://scripts/wave_composition.gd")
const WaveUnitClass = preload("res://scripts/wave_unit_class.gd")


func _seeded_rng(seed_value: int = 1) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


# Build a deterministic WaveComposition (min==max ranges) so timing
# tests can assert exact timestamps. Mission resolves the random
# ranges through `sample_*` helpers; equal min/max collapses to a
# fixed value, which is what the default ReconSettings ships with.
# `duration` and `delay` here are passed in *sim-seconds* — the test
# helper converts to the editor's hour units so the assertions can stay
# in raw seconds without having to think about the boundary.
const SECONDS_PER_HOUR: float = 3600.0


func _wave(
	alpha_n: int,
	beta_n: int,
	gamma_n: int,
	duration_sec: float,
	randomized: bool,
	delay_sec: float,
) -> WaveComposition:
	var w := WaveComposition.new()
	w.alpha_units = alpha_n
	w.beta_units = beta_n
	w.gamma_units = gamma_n
	w.duration_min = duration_sec / SECONDS_PER_HOUR
	w.duration_max = duration_sec / SECONDS_PER_HOUR
	w.randomized = randomized
	w.delay_min = delay_sec / SECONDS_PER_HOUR
	w.delay_max = delay_sec / SECONDS_PER_HOUR
	return w


func _drain(m: Mission, total_seconds: float, step: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var n := int(total_seconds / step)
	for _i in range(n):
		var r := m.tick(step)
		for e: Dictionary in r:
			out.append(e)
	return out


# Game-time spans that comfortably cover the default 5-wave mission.
# The default schedule (hours: 0.5 / 3.0 / 3.0 / 4.0 / 4.0 between
# waves, 0.25–0.6 spawn windows) wraps inside ~15 hours = 54000
# sim-seconds; 60000 is the round-up that keeps "drain to completion"
# tests robust if a future balance pass pushes the last wave a bit later.
const FULL_DRAIN_SEC: float = 60000.0
# Tick step for the drain helper. 30 sim-sec is fine for emission-
# count tests (they only care that everything fired before the drain
# ends); finer granularity is not worth the iteration cost.
const DRAIN_STEP_SEC: float = 30.0


func test_idle_mission_emits_nothing() -> void:
	var m := Mission.new()
	# State stays IDLE because start_from_settings was never called.
	assert_eq(m.tick(1000.0).size(), 0)


func test_default_settings_total_emissions() -> void:
	# Default ReconSettings ships 5 waves: 1 + 2 + 2 + 4 + 3 = 12
	# wave-units. The schedule was thinned to ~1/3 of the legacy 36
	# when the asteroid mass bands jumped from kg-class fodder up
	# to Gg / Tg / Pg-class threats — same wave-count escalation,
	# fewer wave-units per wave so the fleet's defences keep up.
	var s := ReconSettings.default_settings()
	var m := Mission.new()
	m.start_from_settings(s, _seeded_rng())
	var emissions := _drain(m, FULL_DRAIN_SEC, DRAIN_STEP_SEC)
	assert_eq(emissions.size(), 12)
	assert_eq(m.total_wave_units(), 12)


func test_default_first_wave_fires_at_half_hour() -> void:
	# Default first-wave delay is 0.5 game-time hours = 1800 sim-seconds.
	# Mission tick is fed sim-seconds, so the threshold is the absolute
	# sim-time elapsed since mission start.
	var s := ReconSettings.default_settings()
	var m := Mission.new()
	m.start_from_settings(s, _seeded_rng())
	var early := m.tick(1799.99)
	assert_eq(early.size(), 0)
	var ready := m.tick(0.02)
	assert_eq(ready.size(), 1)
	assert_eq(int(ready[0]["wave_id"]), 0)
	assert_true(bool(ready[0].get("first_in_wave", false)))


func test_first_in_wave_set_once_per_wave() -> void:
	var s := ReconSettings.default_settings()
	var m := Mission.new()
	m.start_from_settings(s, _seeded_rng())
	var emissions := _drain(m, FULL_DRAIN_SEC, DRAIN_STEP_SEC)
	var firsts: Dictionary = {}
	for e: Dictionary in emissions:
		var wid := int(e["wave_id"])
		if bool(e.get("first_in_wave", false)):
			firsts[wid] = int(firsts.get(wid, 0)) + 1
	assert_eq(firsts.size(), 5)
	for wid_v in firsts:
		assert_eq(int(firsts[wid_v]), 1, "wave %s flag count" % wid_v)


func test_emission_size_class_counts_match_settings() -> void:
	# Each emission is tagged with the size_class that drove it; the
	# total per class must equal the per-wave sum across the settings.
	var s := ReconSettings.default_settings()
	var m := Mission.new()
	m.start_from_settings(s, _seeded_rng())
	var emissions := _drain(m, FULL_DRAIN_SEC, DRAIN_STEP_SEC)
	var counts: Dictionary = {}
	for e: Dictionary in emissions:
		var sc := int(e["size_class"])
		counts[sc] = int(counts.get(sc, 0)) + 1
	var expected_alpha := 0
	var expected_beta := 0
	var expected_gamma := 0
	for w: WaveComposition in s.waves:
		expected_alpha += w.alpha_units
		expected_beta += w.beta_units
		expected_gamma += w.gamma_units
	assert_eq(int(counts.get(ReconSettings.SIZE_ALPHA, 0)), expected_alpha)
	assert_eq(int(counts.get(ReconSettings.SIZE_BETA, 0)), expected_beta)
	assert_eq(int(counts.get(ReconSettings.SIZE_GAMMA, 0)), expected_gamma)


func test_evenly_spaced_wave_emits_on_grid() -> void:
	# 1 wave, 4 wave-units (mixed classes) over 6.0s evenly distributed
	# with no inter-wave delay before the first emission. Expected
	# timestamps: 0, 2, 4, 6.
	var s := ReconSettings.new()
	s.waves = [_wave(2, 1, 1, 6.0, false, 0.0)]
	var m := Mission.new()
	m.start_from_settings(s, _seeded_rng())
	var emissions := m.tick(10.0)
	assert_eq(emissions.size(), 4)
	var ts: Array[float] = []
	for e: Dictionary in emissions:
		ts.append(float(e["t"]))
	for i in range(4):
		assert_close(ts[i], 2.0 * float(i), 1.0e-6,
			"even-spacing emission %d" % i)


func test_randomized_wave_stays_in_window() -> void:
	# 1 wave, 8 wave-units randomised over a 4s window starting at
	# t=10. All emissions must land in [10, 14] and remain monotonic
	# (Mission sorts random draws so first_in_wave still tags the
	# earliest unit).
	var s := ReconSettings.new()
	s.waves = [_wave(8, 0, 0, 4.0, true, 10.0)]
	var m := Mission.new()
	m.start_from_settings(s, _seeded_rng())
	var emissions := m.tick(20.0)
	assert_eq(emissions.size(), 8)
	var prev := -1.0
	for e: Dictionary in emissions:
		var t := float(e["t"])
		assert_true(t >= 10.0 - 1.0e-6 and t <= 14.0 + 1.0e-6,
			"random emission at %f outside [10, 14]" % t)
		assert_true(t >= prev,
			"random emissions should be monotonic; %f < %f" % [t, prev])
		prev = t


func test_single_wave_unit_fires_at_zero_offset() -> void:
	# A 1-unit wave shouldn't divide-by-zero the linspace step; both
	# even and randomised paths should fire at t=delay.
	var s := ReconSettings.new()
	s.waves = [_wave(1, 0, 0, 3.0, false, 7.0)]
	var m := Mission.new()
	m.start_from_settings(s, _seeded_rng())
	var emissions := m.tick(20.0)
	assert_eq(emissions.size(), 1)
	assert_close(float(emissions[0]["t"]), 7.0, 1.0e-6)


func test_empty_settings_drains_immediately() -> void:
	var s := ReconSettings.new()
	s.waves = []
	var m := Mission.new()
	m.start_from_settings(s, _seeded_rng())
	assert_true(m.all_waves_spawned())
	assert_eq(m.tick(1000.0).size(), 0)


func test_null_settings_yields_empty_schedule() -> void:
	# Defensive: Mission.start_from_settings(null) should arm to an
	# empty schedule rather than crash. The controller may pass null
	# during direct main.tscn boot or if the autoload is unavailable.
	var m := Mission.new()
	m.start_from_settings(null, _seeded_rng())
	assert_true(m.all_waves_spawned())
	assert_eq(m.tick(1000.0).size(), 0)


func test_no_emissions_after_drained() -> void:
	var s := ReconSettings.default_settings()
	var m := Mission.new()
	m.start_from_settings(s, _seeded_rng())
	m.tick(FULL_DRAIN_SEC)
	assert_true(m.all_waves_spawned())
	assert_eq(m.tick(FULL_DRAIN_SEC).size(), 0)


func test_all_waves_spawned_only_after_last_emission() -> void:
	# Default schedule's last wave-unit fires below FULL_DRAIN_SEC; the
	# midpoint at half that span must still have unfired wave-units left.
	var s := ReconSettings.default_settings()
	var m := Mission.new()
	m.start_from_settings(s, _seeded_rng())
	assert_false(m.all_waves_spawned())
	m.tick(FULL_DRAIN_SEC * 0.5)
	assert_false(m.all_waves_spawned())
	m.tick(FULL_DRAIN_SEC)
	assert_true(m.all_waves_spawned())


func test_mark_complete_blocks_further_emissions() -> void:
	var s := ReconSettings.default_settings()
	var m := Mission.new()
	m.start_from_settings(s, _seeded_rng())
	m.mark_complete()
	assert_true(m.is_complete())
	# A completed mission's tick() must not emit anything regardless
	# of how much time is fed in — the controller has decided we're done.
	assert_eq(m.tick(FULL_DRAIN_SEC).size(), 0)


func test_total_waves_counts_distinct_wave_ids() -> void:
	# Default ships 5 waves; the schedule's distinct wave_id count
	# is what the HUD's denominator reads off.
	var s := ReconSettings.default_settings()
	var m := Mission.new()
	m.start_from_settings(s, _seeded_rng())
	assert_eq(m.total_waves(), 5)


func test_current_wave_number_starts_at_zero() -> void:
	# Before any wave-unit fires, the tracker reads 0 — the HUD shows
	# "Current wave: 0/5" so the operator knows the schedule armed
	# but no wave has begun yet.
	var s := ReconSettings.default_settings()
	var m := Mission.new()
	m.start_from_settings(s, _seeded_rng())
	assert_eq(m.current_wave_number(), 0)


func test_current_wave_number_advances_with_first_in_wave() -> void:
	# Step the mission forward through each wave's first wave-unit
	# and confirm current_wave_number bumps to that wave's 1-based id.
	# Wave delays in the default schedule (sim-seconds): 1800, 12600,
	# 23400, 37800, 52200.
	var s := ReconSettings.default_settings()
	var m := Mission.new()
	m.start_from_settings(s, _seeded_rng())
	m.tick(1801.0)
	assert_eq(m.current_wave_number(), 1)
	m.tick(12600.0 - 1801.0 + 1.0)
	assert_eq(m.current_wave_number(), 2)
	# Drain the rest.
	m.tick(FULL_DRAIN_SEC)
	assert_eq(m.current_wave_number(), 5)


func test_current_wave_number_persists_after_drain() -> void:
	# Once every wave has fired, the tracker should stick at the
	# final wave number rather than reverting to 0 — the HUD reads
	# "Current wave: 5/5" until the run ends.
	var s := ReconSettings.default_settings()
	var m := Mission.new()
	m.start_from_settings(s, _seeded_rng())
	m.tick(FULL_DRAIN_SEC)
	assert_true(m.all_waves_spawned())
	assert_eq(m.current_wave_number(), 5)


func test_emissions_carry_baked_object_count() -> void:
	# Mission resolves WaveUnitClass.sample_count at schedule build so
	# the per-wave 250-body cap can be enforced across siblings; every
	# emission must carry a positive `object_count` for SpawnDirector
	# to honour as an override.
	var s := ReconSettings.default_settings()
	var m := Mission.new()
	m.start_from_settings(s, _seeded_rng())
	var emissions := _drain(m, FULL_DRAIN_SEC, DRAIN_STEP_SEC)
	assert_true(emissions.size() > 0)
	for e: Dictionary in emissions:
		var c := int(e.get("object_count", 0))
		assert_true(c >= 1, "emission object_count should be >= 1, got %d" % c)
		assert_true(c <= WaveUnitClass.COUNT_MAX,
			"emission object_count %d exceeds class cap %d" % [c, WaveUnitClass.COUNT_MAX])


func test_per_wave_object_total_capped_at_250() -> void:
	# Build a synthetic wave whose default-sampled count would
	# blow past 250 (e.g. 10 wave-units × ~40 each = ~400) and
	# confirm the schedule scales each wave-unit down so the total
	# stays at or under MAX_WAVE_OBJECT_COUNT.
	var s := ReconSettings.new()
	# Saturate the gamma class to its cap so the raw total is large.
	s.gamma_class.count_min = 50
	s.gamma_class.count_max = 50
	var w := WaveComposition.new()
	w.gamma_units = 10
	# 5 sim-second window (≈0.0014 h); single tick below covers it.
	w.duration_min = 5.0 / SECONDS_PER_HOUR
	w.duration_max = 5.0 / SECONDS_PER_HOUR
	w.delay_min = 0.0
	w.delay_max = 0.0
	s.waves = [w]

	var m := Mission.new()
	m.start_from_settings(s, _seeded_rng())
	var emissions := m.tick(20.0)
	assert_eq(emissions.size(), 10)
	var total := 0
	for e: Dictionary in emissions:
		total += int(e.get("object_count", 0))
	assert_true(total <= Mission.MAX_WAVE_OBJECT_COUNT,
		"wave total %d should be capped at %d" % [
			total, Mission.MAX_WAVE_OBJECT_COUNT
		])
	# After scaling, every wave-unit still carries at least one body
	# (the scale floor is 1) so no emission silently zero-outs.
	for e: Dictionary in emissions:
		assert_true(int(e["object_count"]) >= 1)


func test_per_wave_total_unchanged_when_already_under_cap() -> void:
	# A wave whose raw sampled total fits inside MAX_WAVE_OBJECT_COUNT
	# should pass through unscaled — only oversize waves get scaled.
	var s := ReconSettings.new()
	s.alpha_class.count_min = 10
	s.alpha_class.count_max = 10
	var w := WaveComposition.new()
	w.alpha_units = 5
	# 2 sim-sec window — enough granularity for the 5-unit test, well
	# inside the single tick below.
	w.duration_min = 2.0 / SECONDS_PER_HOUR
	w.duration_max = 2.0 / SECONDS_PER_HOUR
	w.delay_min = 0.0
	w.delay_max = 0.0
	s.waves = [w]

	var m := Mission.new()
	m.start_from_settings(s, _seeded_rng())
	var emissions := m.tick(20.0)
	assert_eq(emissions.size(), 5)
	# Each emission should still carry the original sampled count
	# (10 each) — the wave's total of 50 is well under 250.
	for e: Dictionary in emissions:
		assert_eq(int(e["object_count"]), 10)


func test_seeded_rng_produces_stable_timeline() -> void:
	# Same seed → same emission timestamps and same size-class order
	# across runs, even with randomised waves and shuffled classes.
	var sa := ReconSettings.default_settings()
	var sb := ReconSettings.default_settings()
	var ma := Mission.new()
	var mb := Mission.new()
	ma.start_from_settings(sa, _seeded_rng(99))
	mb.start_from_settings(sb, _seeded_rng(99))
	var ea := _drain(ma, FULL_DRAIN_SEC, DRAIN_STEP_SEC)
	var eb := _drain(mb, FULL_DRAIN_SEC, DRAIN_STEP_SEC)
	assert_eq(ea.size(), eb.size())
	for i in range(ea.size()):
		assert_close(float(ea[i]["t"]), float(eb[i]["t"]), 1.0e-9)
		assert_eq(int(ea[i]["size_class"]), int(eb[i]["size_class"]))
		assert_eq(int(ea[i]["wave_id"]), int(eb[i]["wave_id"]))
