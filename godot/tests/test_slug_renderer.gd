extends "res://tests/framework.gd"
## SlugRenderer kinematics. The visual side (cylinder transforms,
## materials) isn't testable headlessly, but the sim-time → distance
## math and the arrival predicate that drives despawn are pure
## helpers, so pin them here. Constants line up with the design:
## 10 km/sim-sec muzzle velocity ⇒ 10 km of travel per simulated
## second of elapsed time.

const SlugRenderer = preload("res://scripts/slug_renderer.gd")
const RailgunWeapon = preload("res://scripts/weapons/railgun_weapon.gd")


func test_muzzle_velocity_constant_matches_railgun() -> void:
	# SlugRenderer caches muzzle velocity in km / sim-sec for the
	# kinematic helpers; RailgunWeapon stores it in m/s for the
	# physics chain. Pin the conversion so a future tweak to either
	# constant doesn't desync the visual from the simulation.
	assert_close(
		SlugRenderer.MUZZLE_VELOCITY_KMS,
		RailgunWeapon.MUZZLE_VELOCITY_M_S * 1.0e-3,
	)


func test_traveled_km_at_t_zero() -> void:
	# Fired right now ⇒ zero progress. No timer drift, no negative
	# distances on the first frame.
	assert_close(SlugRenderer.traveled_km(10.0, 10.0), 0.0)


func test_traveled_km_scales_linearly_with_elapsed_sim_time() -> void:
	# 1 sim-sec at 10 km/s ⇒ 10 km. 50 sim-sec ⇒ 500 km. Linear
	# scaling is the whole contract; pin the slope.
	assert_close(SlugRenderer.traveled_km(11.0, 10.0), 10.0)
	assert_close(SlugRenderer.traveled_km(60.0, 10.0), 500.0)


func test_traveled_km_clamps_to_zero_for_negative_gap() -> void:
	# Sim time only advances, but defensive zero-floor here means a
	# stale cache reading (or a paused-sim register_fire ordering quirk)
	# never produces a negative distance — which would invert the
	# slug's direction and ship it off into space.
	assert_close(SlugRenderer.traveled_km(5.0, 10.0), 0.0)


func test_has_arrived_pre_and_post_arrival() -> void:
	# Default-shot geometry: 5000 km gap (typical inter-LEO sat
	# spacing). At 10 km/sim-sec ⇒ 500 sim-sec to arrive. Verify the
	# predicate flips at the boundary, not before.
	var fire_t := 0.0
	var distance := 5000.0
	assert_false(SlugRenderer.has_arrived(499.0, fire_t, distance))
	assert_true(SlugRenderer.has_arrived(500.0, fire_t, distance))
	assert_true(SlugRenderer.has_arrived(10000.0, fire_t, distance))


func test_register_and_clear_lifecycle() -> void:
	# Rendering side requires a SceneTree, so don't add the renderer
	# to one — instead exercise just the bookkeeping API
	# (active_slug_count + clear_all). register_fire requires real
	# Satellite objects (it reads orbit.r through the typed param);
	# building those is heavier than the value here, so this test
	# stops at the empty-state contract: a fresh renderer reports
	# zero active slugs, and clear_all on empty is a safe no-op.
	var sr := SlugRenderer.new()
	assert_eq(sr.active_slug_count(), 0)
	sr.clear_all()
	assert_eq(sr.active_slug_count(), 0)
