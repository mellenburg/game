extends "res://tests/framework.gd"
## MeteoriteWave timer-queue tests. Pure-state RefCounted, so the
## spawn-distribution logic is covered without booting a SceneTree.

const MeteoriteWave = preload("res://scripts/meteorite_wave.gd")


func test_populate_count_and_bounds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var wave := MeteoriteWave.new()
	wave.populate(rng, 50, 10.0, 6000.0, 3000.0, 0.8)
	assert_eq(wave.pending.size(), 50)
	assert_eq(wave.duration_sec, 10.0)
	assert_eq(wave.lateral_spread_km, 6000.0)
	for entry in wave.pending:
		var t: float = entry["t"]
		assert_true(
			t >= 0.0 and t <= 10.0,
			"spawn time %f outside [0, 10]" % t,
		)
		var lat: Vector2 = entry["lateral"]
		assert_true(
			lat.length() <= 6000.0 + 1e-3,
			"lateral magnitude %f outside spread" % lat.length(),
		)
		var alt: float = entry["alt_offset"]
		assert_true(
			alt >= -3000.0 and alt <= 3000.0,
			"alt offset %f outside jitter band" % alt,
		)
		var jit: Vector3 = entry["vel_jitter"]
		assert_true(
			absf(jit.x) <= 0.8 and absf(jit.y) <= 0.8 and absf(jit.z) <= 0.8,
			"velocity jitter %s outside band" % jit,
		)


func test_tick_spawns_only_expired_timers() -> void:
	var wave := MeteoriteWave.new()
	wave.pending = [_spec(0.5), _spec(1.5), _spec(2.5)]
	var spawned := wave.tick(1.0)
	assert_eq(spawned.size(), 1)
	assert_eq(wave.pending.size(), 2)
	assert_false(wave.is_complete())


func test_tick_drains_queue_after_full_window() -> void:
	var wave := MeteoriteWave.new()
	wave.pending = [_spec(0.5), _spec(1.5), _spec(9.5)]
	var spawned := wave.tick(10.0)
	assert_eq(spawned.size(), 3)
	assert_true(wave.is_complete())


func test_total_spawn_count_matches_population() -> void:
	# Drive the wave with many small ticks; the sum of all spawned
	# bodies must equal the populated count and the queue must drain.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var wave := MeteoriteWave.new()
	wave.populate(rng, 50, 10.0, 6000.0, 3000.0, 0.8)
	var total := 0
	for _i in range(200):  # 200 * 0.1s = 20s — well past the window
		total += wave.tick(0.1).size()
	assert_eq(total, 50)
	assert_true(wave.is_complete())


func test_no_spawn_before_any_timer_expires() -> void:
	var wave := MeteoriteWave.new()
	wave.pending = [_spec(0.5), _spec(1.5), _spec(2.5)]
	assert_eq(wave.tick(0.1).size(), 0)
	assert_eq(wave.pending.size(), 3)


# Minimal spec used by the timer-only tests above. Lateral / altitude /
# velocity fields are zero so the tests focus on the countdown logic.
func _spec(t: float) -> Dictionary:
	return {
		"t": t,
		"lateral": Vector2.ZERO,
		"alt_offset": 0.0,
		"vel_jitter": Vector3.ZERO,
	}
