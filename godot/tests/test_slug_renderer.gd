extends "res://tests/framework.gd"
## SlugRenderer kinematics. The visual side (cube transforms,
## materials) isn't testable headlessly, but the muzzle-velocity
## constant and the empty-state lifecycle contract are pure data, so
## pin them here.

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


func test_empty_renderer_lifecycle() -> void:
	# Fresh renderer reports zero active slugs; clear_all on empty is
	# a safe no-op; tick on empty returns without touching anything.
	# register_fire requires real Satellite objects (it dereferences
	# orbit.r through the typed param) so isn't exercised here —
	# integration coverage lives in the live combat path.
	var sr := SlugRenderer.new()
	assert_eq(sr.active_slug_count(), 0)
	sr.clear_all()
	assert_eq(sr.active_slug_count(), 0)
	sr.tick(1.0)
	assert_eq(sr.active_slug_count(), 0)
