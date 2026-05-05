extends "res://tests/framework.gd"
## ImpactTracker tests. Pure-math: ECI → mesh-local → UV → (lon, lat),
## plus the bounding-box region classifier and the ocean-pixel
## heuristic. Headless-safe — no SceneTree needed.

const ImpactTracker = preload("res://scripts/impact_tracker.gd")


func test_uv_to_latlon_corners() -> void:
	# Texture corners: (0, 0) is the upper-left pixel — north pole at
	# the dateline. (1, 1) is the lower-right — south pole at the
	# eastern dateline. (0.5, 0.5) is the equator at Greenwich.
	var nw := ImpactTracker.uv_to_latlon(Vector2(0.0, 0.0))
	assert_close(nw.x, -180.0, 1.0e-6)
	assert_close(nw.y, 90.0, 1.0e-6)
	var center := ImpactTracker.uv_to_latlon(Vector2(0.5, 0.5))
	assert_close(center.x, 0.0, 1.0e-6)
	assert_close(center.y, 0.0, 1.0e-6)
	var se := ImpactTracker.uv_to_latlon(Vector2(1.0, 1.0))
	assert_close(se.x, 180.0, 1.0e-6)
	assert_close(se.y, -90.0, 1.0e-6)


func test_mesh_local_uv_seam_and_pole() -> void:
	# UV seam runs through mesh-local +Z (u=0). +X is at u=0.25.
	# +Y is the north pole (v=0). Sanity-check those landmarks so a
	# regression in the conversion shows up immediately.
	var seam := ImpactTracker.mesh_local_to_uv(Vector3(0.0, 0.0, 1.0))
	assert_close(seam.x, 0.0, 1.0e-6)
	assert_close(seam.y, 0.5, 1.0e-6)
	var east := ImpactTracker.mesh_local_to_uv(Vector3(1.0, 0.0, 0.0))
	assert_close(east.x, 0.25, 1.0e-6)
	assert_close(east.y, 0.5, 1.0e-6)
	var north := ImpactTracker.mesh_local_to_uv(Vector3(0.0, 1.0, 0.0))
	assert_close(north.y, 0.0, 1.0e-6)


func test_eci_to_latlon_consistent_under_daily_rotation() -> void:
	# A single fixed mesh-local point — the impact spot — should
	# produce the same (lat, lon) regardless of how far Earth has
	# rotated, provided we feed the world ECI vector that places the
	# spot at the same body-fixed direction. We synthesize that ECI
	# vector by running the forward Earth basis on the mesh-local
	# point, then check the inverse pipeline rebuilds the original.
	var mesh_pt := Vector3(0.3, 0.5, 0.8).normalized() * 6371.0
	var phases: Array[float] = [0.0, 0.5, 1.7, TAU - 0.1]
	for phase in phases:
		var daily := Basis(Vector3(0.0, 0.0, 1.0), phase)
		var basis := ImpactTracker.AXIAL_TILT * daily * ImpactTracker.POLE_ALIGN
		var world := basis * mesh_pt
		var roundtrip := ImpactTracker.eci_to_mesh_local(world, phase)
		# Single-precision Basis math can drift on the order of a
		# millimeter per multiply at this magnitude; 1e-2 km is well
		# above that floor and well below any meaningful surface
		# resolution, so the test stays stable on CI.
		assert_vec_close(roundtrip, mesh_pt, 1.0e-2)
		# The (lat, lon) should likewise match the mesh-local UV.
		var direct_uv := ImpactTracker.mesh_local_to_uv(mesh_pt)
		var via_world := ImpactTracker.mesh_local_to_uv(roundtrip)
		assert_close(via_world.x, direct_uv.x, 1.0e-5)
		assert_close(via_world.y, direct_uv.y, 1.0e-5)


func test_classify_region_known_points() -> void:
	# Hand-checked spots inside the bounding-box table. Picked away
	# from box edges so the test isn't sensitive to ±1° calibration.
	assert_eq(
		ImpactTracker.classify_region(-100.0, 39.0, false),
		"United States",
	)
	assert_eq(
		ImpactTracker.classify_region(2.0, 48.5, false),
		"France",
	)
	assert_eq(
		ImpactTracker.classify_region(78.0, 21.0, false),
		"India",
	)
	assert_eq(
		ImpactTracker.classify_region(135.0, -25.0, false),
		"Australia",
	)


func test_classify_region_ocean_hint_skips_land() -> void:
	# A point inside the United States bounding box, but the caller
	# tells us the albedo sample looked like ocean — the region table
	# should serve up an ocean label (Gulf of Mexico is the closest
	# ocean entry that actually contains that point's lat/lon).
	var ocean_label := ImpactTracker.classify_region(-90.0, 27.0, true)
	assert_eq(ocean_label, "Gulf of Mexico")


func test_classify_region_open_ocean_fallback() -> void:
	# A point in the middle of the South Atlantic that happens to fall
	# inside the bounding-box table — the explicit ocean entry wins.
	var label := ImpactTracker.classify_region(-30.0, -20.0, true)
	assert_eq(label, "South Atlantic Ocean")


func test_record_impact_appends_entry() -> void:
	var t := ImpactTracker.new()
	t.tick(123.0)
	# A position above mesh-local +X (after applying basis at phase=0)
	# — the recorded entry should at least be finite and on the
	# surface. Don't assert the lat/lon exactly: that's covered by
	# the earlier UV tests; here we're checking the bookkeeping.
	var basis := (
		ImpactTracker.AXIAL_TILT
		* Basis(Vector3(0.0, 0.0, 1.0), 0.0)
		* ImpactTracker.POLE_ALIGN
	)
	var world := basis * Vector3(7000.0, 0.0, 0.0)
	var entry := t.record_impact(world, 0.0, false)
	assert_eq(t.impacts.size(), 1)
	assert_close(entry["sim_time"], 123.0, 1.0e-6)
	assert_true(entry["lat"] >= -90.0 and entry["lat"] <= 90.0)
	assert_true(entry["lon"] >= -180.0 and entry["lon"] <= 180.0)
	assert_false(entry["is_ocean"])
	# Default HP is 0.0 when the caller doesn't pass a value — the
	# minimap treats that as "use the floor scale".
	assert_close(float(entry["hp"]), 0.0, 1.0e-6)


func test_record_impact_stores_hp() -> void:
	var t := ImpactTracker.new()
	var basis := (
		ImpactTracker.AXIAL_TILT
		* Basis(Vector3(0.0, 0.0, 1.0), 0.0)
		* ImpactTracker.POLE_ALIGN
	)
	var world := basis * Vector3(7000.0, 0.0, 0.0)
	var entry := t.record_impact(world, 0.0, false, 250.0)
	assert_close(float(entry["hp"]), 250.0, 1.0e-6)
	# Negative HP would imply over-killed bookkeeping; the tracker
	# clamps at zero so the minimap math stays well-defined.
	var entry_neg := t.record_impact(world, 0.0, false, -5.0)
	assert_close(float(entry_neg["hp"]), 0.0, 1.0e-6)


func test_record_impact_stores_physical_fields() -> void:
	# Mass / density / composition are routed straight through onto the
	# entry so the impact-map overlay can size the damage circles and
	# render the latest-impact composition tag without re-deriving.
	var t := ImpactTracker.new()
	var basis := (
		ImpactTracker.AXIAL_TILT
		* Basis(Vector3(0.0, 0.0, 1.0), 0.0)
		* ImpactTracker.POLE_ALIGN
	)
	var world := basis * Vector3(7000.0, 0.0, 0.0)
	var entry := t.record_impact(world, 0.0, false, 0.0, 1.5e6, 3.4, 1)
	assert_close(float(entry["mass_kg"]), 1.5e6, 1.0e-3)
	assert_close(float(entry["density_g_cm3"]), 3.4, 1.0e-6)
	assert_eq(int(entry["composition"]), 1)
	# Default call (no physical fields) leaves them at zero / -1 so
	# legacy callers still produce a well-formed entry.
	var legacy := t.record_impact(world, 0.0, false)
	assert_close(float(legacy["mass_kg"]), 0.0, 1.0e-9)
	assert_eq(int(legacy["composition"]), -1)


func test_is_ocean_pixel_blue_dominant() -> void:
	# Saturated mid-blue → ocean. Saturated red → not ocean. Snow-
	# bright white → not ocean (so polar caps stay land). Dark almost-
	# black → not ocean (under-exposed pixels shouldn't be misread).
	assert_true(ImpactTracker.is_ocean_pixel(Color(0.10, 0.20, 0.45)))
	assert_false(ImpactTracker.is_ocean_pixel(Color(0.55, 0.30, 0.20)))
	assert_false(ImpactTracker.is_ocean_pixel(Color(0.95, 0.95, 0.97)))
	assert_false(ImpactTracker.is_ocean_pixel(Color(0.02, 0.02, 0.05)))
