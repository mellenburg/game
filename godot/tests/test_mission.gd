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
func _wave(
	small_n: int,
	medium_n: int,
	large_n: int,
	duration: float,
	randomized: bool,
	delay: float,
) -> WaveComposition:
	var w := WaveComposition.new()
	w.small_units = small_n
	w.medium_units = medium_n
	w.large_units = large_n
	w.duration_min = duration
	w.duration_max = duration
	w.randomized = randomized
	w.delay_min = delay
	w.delay_max = delay
	return w


func _drain(m: Mission, total_seconds: float, step: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var n := int(total_seconds / step)
	for _i in range(n):
		var r := m.tick(step)
		for e: Dictionary in r:
			out.append(e)
	return out


func test_idle_mission_emits_nothing() -> void:
	var m := Mission.new()
	# State stays IDLE because start_from_settings was never called.
	assert_eq(m.tick(1000.0).size(), 0)


func test_default_settings_total_emissions() -> void:
	# Default ReconSettings ships 5 waves: 3 + 5 + 8 + 10 + 10 = 36
	# wave-units. The brief sums match the previous hardcoded
	# schedule, which the editor's default reproduces.
	var s := ReconSettings.default_settings()
	var m := Mission.new()
	m.start_from_settings(s, _seeded_rng())
	var emissions := _drain(m, 200.0, 0.05)
	assert_eq(emissions.size(), 36)
	assert_eq(m.total_wave_units(), 36)


func test_default_first_wave_fires_at_three_seconds() -> void:
	var s := ReconSettings.default_settings()
	var m := Mission.new()
	m.start_from_settings(s, _seeded_rng())
	var early := m.tick(2.99)
	assert_eq(early.size(), 0)
	var ready := m.tick(0.02)
	assert_eq(ready.size(), 1)
	assert_eq(int(ready[0]["wave_id"]), 0)
	assert_true(bool(ready[0].get("first_in_wave", false)))


func test_first_in_wave_set_once_per_wave() -> void:
	var s := ReconSettings.default_settings()
	var m := Mission.new()
	m.start_from_settings(s, _seeded_rng())
	var emissions := _drain(m, 200.0, 0.05)
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
	var emissions := _drain(m, 200.0, 0.05)
	var counts: Dictionary = {}
	for e: Dictionary in emissions:
		var sc := int(e["size_class"])
		counts[sc] = int(counts.get(sc, 0)) + 1
	var expected_small := 0
	var expected_medium := 0
	var expected_large := 0
	for w: WaveComposition in s.waves:
		expected_small += w.small_units
		expected_medium += w.medium_units
		expected_large += w.large_units
	assert_eq(int(counts.get(ReconSettings.SIZE_SMALL, 0)), expected_small)
	assert_eq(int(counts.get(ReconSettings.SIZE_MEDIUM, 0)), expected_medium)
	assert_eq(int(counts.get(ReconSettings.SIZE_LARGE, 0)), expected_large)


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
	m.tick(500.0)
	assert_true(m.all_waves_spawned())
	assert_eq(m.tick(500.0).size(), 0)


func test_all_waves_spawned_only_after_last_emission() -> void:
	var s := ReconSettings.default_settings()
	var m := Mission.new()
	m.start_from_settings(s, _seeded_rng())
	assert_false(m.all_waves_spawned())
	m.tick(112.5)
	assert_false(m.all_waves_spawned())
	m.tick(20.0)
	assert_true(m.all_waves_spawned())


func test_mark_complete_blocks_further_emissions() -> void:
	var s := ReconSettings.default_settings()
	var m := Mission.new()
	m.start_from_settings(s, _seeded_rng())
	m.mark_complete()
	assert_true(m.is_complete())
	# A completed mission's tick() must not emit anything regardless
	# of how much time is fed in — the controller has decided we're done.
	assert_eq(m.tick(500.0).size(), 0)


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
	var s := ReconSettings.default_settings()
	var m := Mission.new()
	m.start_from_settings(s, _seeded_rng())
	# Wave 1 fires at t=3.
	m.tick(3.5)
	assert_eq(m.current_wave_number(), 1)
	# Wave 2 fires at t=28 (delay 25 from wave 1's first unit).
	m.tick(25.0)
	assert_eq(m.current_wave_number(), 2)
	# Drain the rest.
	m.tick(500.0)
	assert_eq(m.current_wave_number(), 5)


func test_current_wave_number_persists_after_drain() -> void:
	# Once every wave has fired, the tracker should stick at the
	# final wave number rather than reverting to 0 — the HUD reads
	# "Current wave: 5/5" until the run ends.
	var s := ReconSettings.default_settings()
	var m := Mission.new()
	m.start_from_settings(s, _seeded_rng())
	m.tick(500.0)
	assert_true(m.all_waves_spawned())
	assert_eq(m.current_wave_number(), 5)


func test_seeded_rng_produces_stable_timeline() -> void:
	# Same seed → same emission timestamps and same size-class order
	# across runs, even with randomised waves and shuffled classes.
	var sa := ReconSettings.default_settings()
	var sb := ReconSettings.default_settings()
	var ma := Mission.new()
	var mb := Mission.new()
	ma.start_from_settings(sa, _seeded_rng(99))
	mb.start_from_settings(sb, _seeded_rng(99))
	var ea := _drain(ma, 200.0, 0.05)
	var eb := _drain(mb, 200.0, 0.05)
	assert_eq(ea.size(), eb.size())
	for i in range(ea.size()):
		assert_close(float(ea[i]["t"]), float(eb[i]["t"]), 1.0e-9)
		assert_eq(int(ea[i]["size_class"]), int(eb[i]["size_class"]))
		assert_eq(int(ea[i]["wave_id"]), int(eb[i]["wave_id"]))
