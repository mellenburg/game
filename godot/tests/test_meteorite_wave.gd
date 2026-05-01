extends "res://tests/framework.gd"
## MeteoriteWave timer-queue tests. Pure-state RefCounted, so the
## spawn-distribution logic is covered without booting a SceneTree.

const MeteoriteWave = preload("res://scripts/meteorite_wave.gd")


func test_populate_random_times_count_and_bounds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var wave := MeteoriteWave.new()
	wave.populate_random_times(rng, 50, 10.0)
	assert_eq(wave.pending_times.size(), 50)
	for t in wave.pending_times:
		assert_true(
			t >= 0.0 and t <= 10.0,
			"spawn time %f outside [0, 10]" % t,
		)


func test_tick_spawns_only_expired_timers() -> void:
	var wave := MeteoriteWave.new()
	wave.pending_times = [0.5, 1.5, 2.5]
	var spawned := wave.tick(1.0)
	assert_eq(spawned, 1)
	assert_eq(wave.pending_times.size(), 2)
	assert_false(wave.is_complete())


func test_tick_drains_queue_after_full_window() -> void:
	var wave := MeteoriteWave.new()
	wave.pending_times = [0.5, 1.5, 9.5]
	var spawned := wave.tick(10.0)
	assert_eq(spawned, 3)
	assert_true(wave.is_complete())


func test_total_spawn_count_matches_population() -> void:
	# Drive the wave with many small ticks; the sum of all spawned
	# bodies must equal the populated count and the queue must drain.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var wave := MeteoriteWave.new()
	wave.populate_random_times(rng, 50, 10.0)
	var total := 0
	for _i in range(200):  # 200 * 0.1s = 20s — well past the window
		total += wave.tick(0.1)
	assert_eq(total, 50)
	assert_true(wave.is_complete())


func test_no_spawn_before_any_timer_expires() -> void:
	var wave := MeteoriteWave.new()
	wave.pending_times = [0.5, 1.5, 2.5]
	assert_eq(wave.tick(0.1), 0)
	assert_eq(wave.pending_times.size(), 3)
