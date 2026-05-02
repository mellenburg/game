extends "res://tests/framework.gd"
## Verify the lat/lon ↔ ECI round-trip for surface installations. The
## SurfacePosition helper drives surface-unit spawning and per-tick
## position updates; if its basis composition diverges from
## ImpactTracker's inverse, surface markers on the minimap won't line
## up with where the units sit on the globe.

const SurfacePosition = preload("res://scripts/surface_position.gd")
const ImpactTracker = preload("res://scripts/impact_tracker.gd")
const EarthOrbit = preload("res://scripts/earth_orbit.gd")


func _round_trip(lat_deg: float, lon_deg: float, phase: float) -> Vector2:
	var radius := EarthOrbit.EARTH_RADIUS_KM
	var eci := SurfacePosition.latlon_to_eci(lat_deg, lon_deg, phase, radius)
	return ImpactTracker.eci_to_latlon(eci, phase)


func test_round_trip_equator_prime_meridian() -> void:
	var ll := _round_trip(0.0, 0.0, 0.0)
	assert_close(ll.x, 0.0, 1.0e-4, "lon")
	assert_close(ll.y, 0.0, 1.0e-4, "lat")


func test_round_trip_off_axis_zero_phase() -> void:
	var ll := _round_trip(35.0, -75.0, 0.0)
	assert_close(ll.x, -75.0, 1.0e-3, "lon")
	assert_close(ll.y, 35.0, 1.0e-3, "lat")


func test_round_trip_with_earth_phase() -> void:
	# Mid-rotation phase exercises the full daily * POLE_ALIGN composition.
	var phase := 1.234
	var ll := _round_trip(-22.5, 140.0, phase)
	assert_close(ll.x, 140.0, 1.0e-3, "lon")
	assert_close(ll.y, -22.5, 1.0e-3, "lat")


func test_north_pole_round_trips() -> void:
	# Latitude is well-defined at the pole; longitude collapses, so we
	# only check the lat coordinate. Tests the boundary case where
	# mesh_local_to_uv's atan2 is fed (0, 0).
	var radius := EarthOrbit.EARTH_RADIUS_KM
	var phase := 0.0
	var eci := SurfacePosition.latlon_to_eci(90.0, 0.0, phase, radius)
	var ll := ImpactTracker.eci_to_latlon(eci, phase)
	assert_close(ll.y, 90.0, 1.0e-3, "lat")


func test_radius_scales_position() -> void:
	# Doubling the radius should double the ECI vector's magnitude.
	var p1 := SurfacePosition.latlon_to_eci(10.0, 20.0, 0.5, 6371.0)
	var p2 := SurfacePosition.latlon_to_eci(10.0, 20.0, 0.5, 12742.0)
	assert_vec_close(p2, p1 * 2.0, 1.0e-3)


func test_earth_phase_rotates_position() -> void:
	# At lat=0, lon=0 the surface point sits in the equatorial plane;
	# advancing earth_phase should sweep it through that plane such
	# that two phases TAU/4 apart yield perpendicular position vectors.
	var radius := EarthOrbit.EARTH_RADIUS_KM
	var p0 := SurfacePosition.latlon_to_eci(0.0, 0.0, 0.0, radius)
	var p1 := SurfacePosition.latlon_to_eci(0.0, 0.0, PI * 0.5, radius)
	# Both magnitudes equal radius, dot product / radius² is cos of angle.
	assert_close(p0.length(), radius, 1.0e-3)
	assert_close(p1.length(), radius, 1.0e-3)
	assert_close(p0.dot(p1) / (radius * radius), 0.0, 1.0e-4)
