extends "res://tests/framework.gd"
## Mission scheduler tests. Pure-state RefCounted, so every wave-timing
## edge can be checked without booting a SceneTree.

const Mission = preload("res://scripts/mission.gd")


func test_start_resets_state() -> void:
	var m := Mission.default_mission()
	m.elapsed = 99.0
	m._next_wave_idx = 3
	m.state = Mission.STATE_COMPLETE
	m.start()
	assert_eq(m.state, Mission.STATE_RUNNING)
	assert_eq(m.elapsed, 0.0)
	assert_eq(m._next_wave_idx, 0)
	assert_false(m.all_waves_spawned())


func test_idle_mission_emits_nothing() -> void:
	var m := Mission.default_mission()
	# State stays IDLE because start() was never called — tick should be
	# a no-op, the schedule must wait for an explicit start.
	var ready := m.tick(1000.0)
	assert_eq(ready.size(), 0)


func test_first_wave_fires_at_three_seconds() -> void:
	var m := Mission.default_mission()
	m.start()
	# Just before threshold — nothing yet.
	var early := m.tick(2.99)
	assert_eq(early.size(), 0)
	# Crossing the threshold yields exactly the first wave def.
	var ready := m.tick(0.02)
	assert_eq(ready.size(), 1)
	assert_eq(int(ready[0]["count"]), 3)
	assert_close(float(ready[0]["spacing"]), 1.0)
	assert_false(bool(ready[0].get("randomized", false)))


func test_default_schedule_cumulative_offsets() -> void:
	# Collect (elapsed_at_fire, wave_def) pairs by ticking in 50 ms
	# steps for 200 s and noting which tick each wave landed on. The
	# expected absolute times are cumulative sums of the per-wave
	# delay_after_prev_start values: 3, 28, 53, 83, 113.
	var m := Mission.default_mission()
	m.start()
	var fire_times: Array[float] = []
	var fire_counts: Array[int] = []
	var t := 0.0
	var step := 0.05
	for _i in range(int(200.0 / step)):
		t += step
		var ready := m.tick(step)
		for w: Dictionary in ready:
			fire_times.append(t)
			fire_counts.append(int(w.get("count", 0)))
	assert_eq(fire_times.size(), 5)
	var expected_t: Array[float] = [3.0, 28.0, 53.0, 83.0, 113.0]
	var expected_count: Array[int] = [3, 5, 8, 10, 10]
	for i in range(5):
		# Tolerance one tick — tick boundaries don't land exactly on the
		# threshold; the wave fires on the first tick that crosses it.
		assert_close(fire_times[i], expected_t[i], step + 1.0e-6,
			"wave %d fire time" % i)
		assert_eq(fire_counts[i], expected_count[i],
			"wave %d unit count" % i)


func test_wave_five_is_randomized_with_four_second_window() -> void:
	# Walk all five waves out and confirm the final one is the randomized
	# burst (the other four are evenly spaced).
	var m := Mission.default_mission()
	m.start()
	var collected: Array[Dictionary] = []
	for _i in range(4000):
		var ready := m.tick(0.05)
		for w: Dictionary in ready:
			collected.append(w)
	assert_eq(collected.size(), 5)
	for i in range(4):
		assert_false(bool(collected[i].get("randomized", false)),
			"wave %d should be evenly spaced" % i)
	var last := collected[4]
	assert_true(bool(last.get("randomized", false)))
	assert_close(float(last.get("random_duration", 0.0)), 4.0)
	assert_eq(int(last.get("count", 0)), 10)


func test_multiple_waves_in_one_large_tick() -> void:
	# A 200 s delta after start() should drain every wave in one shot
	# — the loop must not silently drop waves when delta exceeds an
	# inter-wave gap.
	var m := Mission.default_mission()
	m.start()
	var ready := m.tick(200.0)
	assert_eq(ready.size(), 5)


func test_all_waves_spawned_only_after_last_emission() -> void:
	var m := Mission.default_mission()
	m.start()
	assert_false(m.all_waves_spawned())
	m.tick(112.5)  # past wave 4, before wave 5 (which fires at t=113)
	assert_false(m.all_waves_spawned())
	m.tick(1.0)   # crosses 113 — wave 5 fires
	assert_true(m.all_waves_spawned())


func test_no_emissions_after_all_waves_spawned() -> void:
	var m := Mission.default_mission()
	m.start()
	m.tick(500.0)
	assert_true(m.all_waves_spawned())
	# Subsequent ticks should be empty — once every wave has fired, the
	# scheduler is exhausted and never emits again.
	var ready := m.tick(500.0)
	assert_eq(ready.size(), 0)


func test_mark_complete_transitions_state() -> void:
	var m := Mission.default_mission()
	m.start()
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
	m.start()
	assert_true(m.all_waves_spawned())
	var ready := m.tick(1000.0)
	assert_eq(ready.size(), 0)


func test_first_wave_unit_count_and_spacing_match_brief() -> void:
	# Spot-check the schedule against the mission brief: 3 / 5 / 8 / 10
	# / 10 units at 1 / 1 / 0.5 / 0.5 / random spacing.
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
