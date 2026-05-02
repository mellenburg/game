extends "res://tests/framework.gd"
## Mission scheduler tests. Pure-state RefCounted, so every wave-unit
## timing edge can be checked without booting a SceneTree. The mission
## emits one entry per wave-unit (each wave-unit later becomes a 20-body
## meteorite wave downstream), so a 5-wave mission with the brief's
## 3 / 5 / 8 / 10 / 10 counts produces a 36-entry timeline.

const Mission = preload("res://scripts/mission.gd")


# Reusable seeded RNG so randomized waves produce a stable timeline
# inside tests. Without this, the wave-5 emissions would drift on every
# CI run and the bracket-only assertions would be the only thing we can
# write — the seeded path lets us also assert exact ordering.
func _seeded_rng(seed_value: int = 1) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _drain(m: Mission, total_seconds: float, step: float) -> Array[Dictionary]:
	# Drive the mission clock forward in fixed-size ticks and collect
	# every emission produced. Tick-size matters for the timing-edge
	# assertions below: the test tolerance is exactly one `step`.
	var out: Array[Dictionary] = []
	var n := int(total_seconds / step)
	for _i in range(n):
		var r := m.tick(step)
		for e: Dictionary in r:
			out.append(e)
	return out


func test_start_resets_state() -> void:
	var m := Mission.default_mission()
	m.elapsed = 99.0
	m._next_idx = 3
	m.state = Mission.STATE_COMPLETE
	m.start(_seeded_rng())
	assert_eq(m.state, Mission.STATE_RUNNING)
	assert_eq(m.elapsed, 0.0)
	assert_eq(m._next_idx, 0)
	assert_false(m.all_waves_spawned())


func test_idle_mission_emits_nothing() -> void:
	var m := Mission.default_mission()
	# State stays IDLE because start() was never called — tick must be
	# a no-op, the schedule waits for an explicit start.
	var ready := m.tick(1000.0)
	assert_eq(ready.size(), 0)


func test_total_emission_count_matches_brief() -> void:
	# Brief: 3 + 5 + 8 + 10 + 10 = 36 wave-units across the five waves.
	var m := Mission.default_mission()
	m.start(_seeded_rng())
	var emissions := _drain(m, 200.0, 0.05)
	assert_eq(emissions.size(), 36)


func test_first_wave_unit_fires_at_three_seconds() -> void:
	var m := Mission.default_mission()
	m.start(_seeded_rng())
	# Just before threshold — nothing yet.
	var early := m.tick(2.99)
	assert_eq(early.size(), 0)
	# Crossing the threshold yields the wave-1 first wave-unit.
	var ready := m.tick(0.02)
	assert_eq(ready.size(), 1)
	assert_eq(int(ready[0]["wave_id"]), 0)
	assert_true(bool(ready[0].get("first_in_wave", false)))


func test_first_four_waves_have_deterministic_timestamps() -> void:
	# Walk the schedule out and check each wave-unit lands on the
	# brief's grid: wave 1 at 3/4/5, wave 2 at 28..32, wave 3 at
	# 53.0/53.5/.../56.5, wave 4 at 83.0/83.5/.../87.5. Wave 5 is
	# randomized so it gets its own bracket-only test below.
	var m := Mission.default_mission()
	m.start(_seeded_rng())
	var step := 0.05
	# Track the elapsed time at which each emission fires by ticking
	# step-by-step rather than draining.
	var fire_at: Array[float] = []
	var emissions: Array[Dictionary] = []
	var t := 0.0
	for _i in range(int(200.0 / step)):
		t += step
		var r := m.tick(step)
		for e: Dictionary in r:
			fire_at.append(t)
			emissions.append(e)
	# Wave 0: indices 0..2, t = 3, 4, 5
	for i in range(3):
		assert_eq(int(emissions[i]["wave_id"]), 0, "wave 0 unit %d" % i)
		assert_close(fire_at[i], 3.0 + float(i), step + 1.0e-6)
	# Wave 1: indices 3..7, t = 28, 29, 30, 31, 32
	for i in range(5):
		assert_eq(int(emissions[3 + i]["wave_id"]), 1, "wave 1 unit %d" % i)
		assert_close(fire_at[3 + i], 28.0 + float(i), step + 1.0e-6)
	# Wave 2: indices 8..15, t = 53.0, 53.5, ..., 56.5
	for i in range(8):
		assert_eq(int(emissions[8 + i]["wave_id"]), 2, "wave 2 unit %d" % i)
		assert_close(fire_at[8 + i], 53.0 + 0.5 * float(i), step + 1.0e-6)
	# Wave 3: indices 16..25, t = 83.0, 83.5, ..., 87.5
	for i in range(10):
		assert_eq(int(emissions[16 + i]["wave_id"]), 3, "wave 3 unit %d" % i)
		assert_close(fire_at[16 + i], 83.0 + 0.5 * float(i), step + 1.0e-6)


func test_wave_five_is_randomized_inside_four_second_window() -> void:
	# Wave 5: 10 wave-units randomly scattered across [113, 117]. We
	# assert only the bracket — exact timestamps depend on the RNG seed.
	var m := Mission.default_mission()
	m.start(_seeded_rng())
	var step := 0.05
	var fire_at: Array[float] = []
	var emissions: Array[Dictionary] = []
	var t := 0.0
	for _i in range(int(200.0 / step)):
		t += step
		var r := m.tick(step)
		for e: Dictionary in r:
			fire_at.append(t)
			emissions.append(e)
	for i in range(10):
		var idx := 26 + i
		assert_eq(int(emissions[idx]["wave_id"]), 4,
			"wave 4 unit %d wave_id" % i)
		var ft := fire_at[idx]
		assert_true(
			ft >= 113.0 - step - 1.0e-6 and ft <= 117.0 + step + 1.0e-6,
			"wave 5 unit %d fired at %f, outside [113, 117]" % [i, ft],
		)


func test_first_in_wave_is_set_exactly_once_per_wave() -> void:
	# Every wave should have exactly one wave-unit flagged
	# first_in_wave; the rest are unflagged.
	var m := Mission.default_mission()
	m.start(_seeded_rng())
	var emissions := _drain(m, 200.0, 0.05)
	var firsts_per_wave: Dictionary = {}
	for e: Dictionary in emissions:
		var wid := int(e["wave_id"])
		if bool(e.get("first_in_wave", false)):
			firsts_per_wave[wid] = int(firsts_per_wave.get(wid, 0)) + 1
	assert_eq(firsts_per_wave.size(), 5)
	for wid_v in firsts_per_wave:
		assert_eq(int(firsts_per_wave[wid_v]), 1,
			"wave %s should have exactly one first_in_wave" % wid_v)


func test_multiple_emissions_in_one_large_tick() -> void:
	# A 200 s delta after start() should drain every wave-unit in one
	# shot — the loop must not silently drop emissions when delta
	# exceeds an inter-emission gap.
	var m := Mission.default_mission()
	m.start(_seeded_rng())
	var ready := m.tick(200.0)
	assert_eq(ready.size(), 36)


func test_all_waves_spawned_only_after_last_emission() -> void:
	var m := Mission.default_mission()
	m.start(_seeded_rng())
	assert_false(m.all_waves_spawned())
	# Past wave 4's last unit (87.5 s) but before wave 5's earliest
	# possible start (113 s) — definitely not done.
	m.tick(112.5)
	assert_false(m.all_waves_spawned())
	# Cross past the latest possible wave-5 emission (117 s).
	m.tick(20.0)
	assert_true(m.all_waves_spawned())


func test_no_emissions_after_all_waves_spawned() -> void:
	var m := Mission.default_mission()
	m.start(_seeded_rng())
	m.tick(500.0)
	assert_true(m.all_waves_spawned())
	# Subsequent ticks should be empty — once every wave-unit has fired,
	# the scheduler is exhausted and never emits again.
	var ready := m.tick(500.0)
	assert_eq(ready.size(), 0)


func test_mark_complete_transitions_state() -> void:
	var m := Mission.default_mission()
	m.start(_seeded_rng())
	assert_false(m.is_complete())
	m.mark_complete()
	assert_true(m.is_complete())
	# A completed mission's tick() must not emit anything regardless of
	# how much time is fed in — the controller has decided we're done.
	var ready := m.tick(500.0)
	assert_eq(ready.size(), 0)


func test_empty_mission_is_immediately_drained() -> void:
	var m := Mission.new()
	m.waves = []
	m.start(_seeded_rng())
	assert_true(m.all_waves_spawned())
	var ready := m.tick(1000.0)
	assert_eq(ready.size(), 0)


func test_default_wave_count_and_spacing_match_brief() -> void:
	# Spot-check the schedule against the mission brief: 3 / 5 / 8 / 10
	# / 10 wave-units at 1 / 1 / 0.5 / 0.5 / random spacing.
	var m := Mission.default_mission()
	var counts: Array[int] = [3, 5, 8, 10, 10]
	var spacings: Array[float] = [1.0, 1.0, 0.5, 0.5, 0.0]
	for i in range(5):
		var w: Dictionary = m.waves[i]
		assert_eq(int(w["count"]), counts[i],
			"wave %d count" % (i + 1))
		if i < 4:
			assert_close(float(w["spacing"]), spacings[i],
				1.0e-9, "wave %d spacing" % (i + 1))
		else:
			assert_true(bool(w.get("randomized", false)),
				"wave 5 should be randomized")
			assert_close(float(w.get("random_duration", 0.0)), 4.0)


func test_default_wave_delays_match_brief() -> void:
	var m := Mission.default_mission()
	var delays: Array[float] = [3.0, 25.0, 25.0, 30.0, 30.0]
	for i in range(5):
		assert_close(
			float(m.waves[i]["delay_after_prev_start"]),
			delays[i],
			1.0e-9,
			"wave %d delay" % (i + 1),
		)


func test_seeded_rng_produces_stable_wave_five_timeline() -> void:
	# Regression: the same seed should produce the same wave-5 emission
	# timestamps, so the test bracket above is reliably tightenable
	# later if we ever want to.
	var ma := Mission.default_mission()
	ma.start(_seeded_rng(99))
	var mb := Mission.default_mission()
	mb.start(_seeded_rng(99))
	var ea := _drain(ma, 200.0, 0.05)
	var eb := _drain(mb, 200.0, 0.05)
	assert_eq(ea.size(), eb.size())
	for i in range(ea.size()):
		assert_close(
			float(ea[i]["t"]),
			float(eb[i]["t"]),
			1.0e-9,
			"emission %d t mismatch under same seed" % i,
		)
