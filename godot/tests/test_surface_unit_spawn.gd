extends "res://tests/framework.gd"
## Smoke-test the surface-unit spawn pipeline end-to-end. Walks the
## same path EarthSystem._ready does — instantiate a SpawnDirector,
## hand it a satellite container + an array, call spawn_surface_units
## with a couple of SurfaceUnitConfigs — and verifies the resulting
## Satellite instances carry the expected fields. Exercising this in
## unit tests catches regressions in the `is_surface` flag, lat/lon
## propagation, and the seed orbit position without booting the full
## stage scene.

const SpawnDirector = preload("res://scripts/spawn_director.gd")
const Satellite = preload("res://scripts/satellite.gd")
const SurfaceUnitConfig = preload("res://scripts/surface_unit_config.gd")
const EarthOrbit = preload("res://scripts/earth_orbit.gd")
const SurfacePosition = preload("res://scripts/surface_position.gd")


func _make_director() -> Array:
	# SpawnDirector expects a Node3D to parent the spawned satellites
	# under and an Array[Satellite] to append into. Both are throwaway
	# scaffolding here; the test just inspects the satellites.
	var container := Node3D.new()
	var sats: Array[Satellite] = []
	var sd := SpawnDirector.new()
	sd.setup(container, sats, null)
	return [sd, container, sats]


func test_spawn_surface_unit_writes_expected_fields() -> void:
	var bundle := _make_director()
	var sd: SpawnDirector = bundle[0]
	var sats: Array[Satellite] = bundle[2]
	var configs: Array[SurfaceUnitConfig] = [
		SurfaceUnitConfig.make(0, 35.0, -75.0),
	]
	sd.spawn_surface_units(configs, 0.0)
	assert_eq(sats.size(), 1)
	var sat := sats[0]
	assert_true(sat.is_surface, "is_surface flag")
	assert_eq(sat.team, Satellite.TEAM_PLAYER)
	assert_close(sat.surface_lat_deg, 35.0)
	assert_close(sat.surface_lon_deg, -75.0)
	assert_eq(sat.weapons.size(), 1)
	# Marker / orbit-path nodes are created in _ready, which we don't
	# enter without a SceneTree — but the orbit itself is set in
	# spawn_surface_units' seed step and should sit at Earth's surface.
	var expected := SurfacePosition.latlon_to_eci(
		35.0, -75.0, 0.0,
		EarthOrbit.EARTH_RADIUS_KM + Satellite.SURFACE_UNIT_ALTITUDE_KM,
	)
	assert_vec_close(sat.orbit.r, expected, 1.0e-2)
	# Free the throwaway parent so the per-test queue stays clean.
	bundle[1].queue_free()


func test_spawn_multiple_surface_units() -> void:
	var bundle := _make_director()
	var sd: SpawnDirector = bundle[0]
	var sats: Array[Satellite] = bundle[2]
	var configs: Array[SurfaceUnitConfig] = [
		SurfaceUnitConfig.make(0, 0.0, 0.0),
		SurfaceUnitConfig.make(1, -45.0, 120.0),
		SurfaceUnitConfig.make(2, 60.0, -30.0),
	]
	sd.spawn_surface_units(configs, 0.5)
	assert_eq(sats.size(), 3)
	for i in range(3):
		assert_true(sats[i].is_surface)
		assert_close(sats[i].surface_lat_deg, configs[i].lat_deg)
		assert_close(sats[i].surface_lon_deg, configs[i].lon_deg)
		assert_eq(sats[i].max_hp, SurfaceUnitConfig.DEFAULT_HP)
		assert_eq(sats[i].mass, SurfaceUnitConfig.DEFAULT_MASS_KG)
	bundle[1].queue_free()


func test_update_surface_position_tracks_earth_phase() -> void:
	# Surface position should advance with earth_phase: a unit at lat=0,
	# lon=0 sampled at phase=0 vs phase=PI/4 must shift by a non-zero
	# distance matching the rotation arc.
	var bundle := _make_director()
	var sd: SpawnDirector = bundle[0]
	var sats: Array[Satellite] = bundle[2]
	var configs: Array[SurfaceUnitConfig] = [
		SurfaceUnitConfig.make(0, 0.0, 0.0),
	]
	sd.spawn_surface_units(configs, 0.0)
	var sat := sats[0]
	var p0 := sat.orbit.r
	sat.update_surface_position(PI * 0.5)
	var p1 := sat.orbit.r
	# Magnitudes preserved (still on the surface), positions perpendicular.
	assert_close(p0.length(), p1.length(), 1.0e-2)
	assert_close(p0.dot(p1) / (p0.length() * p1.length()), 0.0, 1.0e-3)
	# Velocity should be non-zero — Earth rotation has us moving.
	assert_true(sat.orbit.v.length() > 0.0)
	bundle[1].queue_free()
