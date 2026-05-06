class_name ImpactTracker
extends RefCounted
## Records asteroid ground impacts and resolves them to a (lat, lon)
## on Earth's surface plus a coarse region label.
##
## Pure-RefCounted so the conversion logic can be unit-tested
## headlessly. The Earth basis used here is the same composition
## (AXIAL_TILT * daily * POLE_ALIGN) the renderer applies to the
## SphereMesh — invert it and the world point falls into the mesh's
## local frame, where +Y is the north pole. From there we go to UV
## (matching Godot's SphereMesh UV generation) and on to (lon, lat).
##
## Region naming is intentionally approximate: a small bounding-box
## table scored in priority order, with an optional ocean/land hint
## passed in from the caller (e.g. an albedo-texture sample). This
## keeps the file dependency-free while leaving room to swap in a
## proper country raster later — `classify_region` is the single
## seam to replace.

const EarthOrbit = preload("res://scripts/earth_orbit.gd")

const POLE_ALIGN := Basis(Vector3(1.0, 0.0, 0.0), PI / 2.0)
const AXIAL_TILT_RAD: float = 23.5 * PI / 180.0
const AXIAL_TILT := Basis(Vector3(1.0, 0.0, 0.0), AXIAL_TILT_RAD)

# Bounding-box region table. Format: [lon_min, lat_min, lon_max, lat_max].
# Listed roughly in priority order — first containing entry wins for a
# given (lon, lat). Tighter / smaller polities go before continent-scale
# fallbacks so e.g. Korea isn't swallowed by the China box. Designed for
# fun, not diplomacy: borders are heavily simplified rectangles.
const LAND_REGIONS: Array[Dictionary] = [
	{ "name": "Iceland",            "box": [-25.0,  63.0,  -13.0,  67.0] },
	{ "name": "United Kingdom",     "box": [-11.0,  49.5,    2.0,  61.0] },
	{ "name": "Ireland",            "box": [-10.5,  51.4,   -5.5,  55.5] },
	{ "name": "Japan",              "box": [129.0,  30.0,  146.0,  46.0] },
	{ "name": "Korean Peninsula",   "box": [124.0,  33.0,  131.0,  43.0] },
	{ "name": "Madagascar",         "box": [ 43.0, -26.0,   51.0, -11.0] },
	{ "name": "New Zealand",        "box": [165.0, -48.0,  179.0, -34.0] },
	{ "name": "Cuba",               "box": [-85.0,  19.0,  -74.0,  24.0] },
	{ "name": "Italy",              "box": [  6.5,  36.5,   18.5,  47.0] },
	{ "name": "Iberian Peninsula",  "box": [-10.0,  36.0,    3.5,  44.0] },
	{ "name": "France",             "box": [ -5.0,  42.0,    8.5,  51.5] },
	{ "name": "Germany",            "box": [  5.5,  47.0,   15.5,  55.5] },
	{ "name": "Scandinavia",        "box": [  4.0,  55.0,   31.0,  71.5] },
	{ "name": "Eastern Europe",     "box": [ 15.5,  44.0,   40.0,  56.0] },
	{ "name": "Turkey",             "box": [ 25.5,  36.0,   45.0,  42.5] },
	{ "name": "Middle East",        "box": [ 34.0,  12.0,   63.0,  40.0] },
	{ "name": "India",              "box": [ 68.0,   6.0,   97.5,  36.0] },
	{ "name": "Southeast Asia",     "box": [ 92.0, -11.0,  141.0,  29.0] },
	{ "name": "China",              "box": [ 73.0,  18.0,  135.0,  53.5] },
	{ "name": "Mongolia & Siberia", "box": [ 60.0,  45.0,  180.0,  78.0] },
	{ "name": "Central Asia",       "box": [ 46.0,  35.0,   88.0,  56.0] },
	{ "name": "Russia (European)",  "box": [ 19.0,  41.0,   60.0,  78.0] },
	{ "name": "North Africa",       "box": [-18.0,  15.0,   38.0,  37.5] },
	{ "name": "Sub-Saharan Africa", "box": [-18.0, -36.0,   52.0,  18.0] },
	{ "name": "Greenland",          "box": [-74.0,  59.0,  -11.0,  84.0] },
	{ "name": "Canada",             "box": [-141.0, 49.0,  -52.0,  72.0] },
	{ "name": "Alaska",             "box": [-170.0, 53.0, -130.0,  72.0] },
	{ "name": "United States",      "box": [-125.0, 24.0,  -67.0,  49.5] },
	{ "name": "Mexico",             "box": [-118.0, 14.5,  -86.0,  33.0] },
	{ "name": "Central America",    "box": [ -93.0,  7.0,  -77.0,  18.5] },
	{ "name": "Brazil",             "box": [ -74.0, -34.0, -34.0,   5.5] },
	{ "name": "Andean South America","box":[ -82.0, -56.0, -66.0,  12.5] },
	{ "name": "Argentina",          "box": [ -74.0, -55.0, -53.5, -22.0] },
	{ "name": "Australia",          "box": [113.0, -39.0,  154.0, -10.5] },
	{ "name": "Antarctica",         "box": [-180.0,-90.0,  180.0, -65.0] },
]

const OCEAN_REGIONS: Array[Dictionary] = [
	{ "name": "Arctic Ocean",          "box": [-180.0,  66.0, 180.0,  90.0] },
	{ "name": "Southern Ocean",        "box": [-180.0, -90.0, 180.0, -55.0] },
	{ "name": "Mediterranean Sea",     "box": [  -6.0,  30.0,  37.0,  46.0] },
	{ "name": "Caribbean Sea",         "box": [ -89.0,   9.0, -60.0,  23.0] },
	{ "name": "Gulf of Mexico",        "box": [ -98.0,  18.0, -81.0,  31.0] },
	{ "name": "North Atlantic Ocean",  "box": [ -80.0,   0.0,  20.0,  66.0] },
	{ "name": "South Atlantic Ocean",  "box": [ -70.0, -55.0,  20.0,   0.0] },
	{ "name": "Indian Ocean",          "box": [  20.0, -55.0, 120.0,  30.0] },
	{ "name": "North Pacific Ocean",   "box": [ 120.0,   0.0, 180.0,  66.0] },
	{ "name": "North Pacific Ocean",   "box": [-180.0,   0.0,-100.0,  66.0] },
	{ "name": "South Pacific Ocean",   "box": [ 140.0, -55.0, 180.0,   0.0] },
	{ "name": "South Pacific Ocean",   "box": [-180.0, -55.0, -70.0,   0.0] },
]

# Public list of recorded impacts. Each entry is a Dictionary with:
#   "lat": float, "lon": float, "region": String, "is_ocean": bool,
#   "uv": Vector2, "sim_time": float
# Append-only; the HUD just iterates it for the Mercator overlay.
var impacts: Array[Dictionary] = []
var sim_time: float = 0.0


## Bump the simulation clock so impacts are timestamped against game
## time, not wall-clock. Driven by EarthSystem._physics_process.
func tick(sim_delta: float) -> void:
	if sim_delta <= 0.0:
		return
	sim_time += sim_delta


## Convert an ECI position (Z-up world frame, km) into a position in
## the Earth mesh's local frame. The mesh's local frame is what UV
## generation operates in: +Y is the north pole.
static func eci_to_mesh_local(p_world: Vector3, earth_phase: float) -> Vector3:
	var daily := Basis(Vector3(0.0, 0.0, 1.0), earth_phase)
	var basis := AXIAL_TILT * daily * POLE_ALIGN
	return basis.inverse() * p_world


## Mesh-local position to equirectangular UV. Matches the UV that
## Godot's SphereMesh assigns to a vertex at the same point: u=0
## seam runs through mesh-local +Z, sweeping toward +X as u grows;
## v=0 at the +Y pole, v=1 at -Y.
static func mesh_local_to_uv(p_local: Vector3) -> Vector2:
	var n := p_local.normalized()
	var v := acos(clampf(n.y, -1.0, 1.0)) / PI
	var u := fposmod(atan2(n.x, n.z) / TAU, 1.0)
	return Vector2(u, v)


## Equirectangular UV to (lon, lat) in degrees. Texture U=0.5 (image
## center) is treated as lon=0; this matches the standard NASA Blue
## Marble layout the project's albedo texture is derived from.
static func uv_to_latlon(uv: Vector2) -> Vector2:
	var lon := (uv.x - 0.5) * 360.0
	var lat := 90.0 - uv.y * 180.0
	return Vector2(lon, lat)


static func eci_to_latlon(p_world: Vector3, earth_phase: float) -> Vector2:
	return uv_to_latlon(mesh_local_to_uv(eci_to_mesh_local(p_world, earth_phase)))


## Resolve (lon, lat) to a coarse region label. `is_ocean_hint` lets
## the caller bias the lookup toward water bodies (e.g. from sampling
## the day-side albedo texture); when true we skip land entries.
static func classify_region(lon: float, lat: float, is_ocean_hint: bool) -> String:
	var lon_wrapped := lon
	# Normalize to [-180, 180] before testing — paranoia in case a
	# caller hands us a longitude in [0, 360].
	while lon_wrapped > 180.0:
		lon_wrapped -= 360.0
	while lon_wrapped < -180.0:
		lon_wrapped += 360.0
	if not is_ocean_hint:
		var land_match := _match(LAND_REGIONS, lon_wrapped, lat)
		if land_match != "":
			return land_match
	var ocean_match := _match(OCEAN_REGIONS, lon_wrapped, lat)
	if ocean_match != "":
		return ocean_match
	# Final fallback: if the land scan was suppressed by the ocean hint
	# but no ocean box matched either, try land before declaring it
	# unidentified — better an approximate continent than "Unknown".
	if is_ocean_hint:
		var fallback_land := _match(LAND_REGIONS, lon_wrapped, lat)
		if fallback_land != "":
			return fallback_land
	return "Open Ocean" if is_ocean_hint else "Uncharted Land"


static func _match(table: Array[Dictionary], lon: float, lat: float) -> String:
	for entry in table:
		var box: Array = entry["box"]
		var lon_min: float = box[0]
		var lat_min: float = box[1]
		var lon_max: float = box[2]
		var lat_max: float = box[3]
		if lon >= lon_min and lon <= lon_max and lat >= lat_min and lat <= lat_max:
			return entry["name"]
	return ""


## Record one asteroid impact. `p_world` is the satellite's last ECI
## position; we project it radially to the Earth surface so an entry
## that stepped slightly past the ground still maps to a clean (lat,
## lon). `is_ocean_hint` should come from sampling the day-side
## albedo texture at the resulting UV — pass `false` to skip the hint.
## `hp` is the impactor's remaining HP at the moment of contact;
## `mass_kg` and `density_g_cm3` carry the body's physical
## parameters so the minimap can render the three-tier damage
## circles via AsteroidPhysics.damage_radii_km. `composition` is a
## AsteroidPhysics.COMP_* index used cosmetically by the latest-impact
## panel; -1 leaves it unset for legacy callers.
func record_impact(
	p_world: Vector3,
	earth_phase: float,
	is_ocean_hint: bool,
	hp: float = 0.0,
	mass_kg: float = 0.0,
	density_g_cm3: float = 0.0,
	composition: int = -1,
) -> Dictionary:
	var surface := p_world.normalized() * EarthOrbit.EARTH_RADIUS_KM
	var local := eci_to_mesh_local(surface, earth_phase)
	var uv := mesh_local_to_uv(local)
	var ll := uv_to_latlon(uv)
	var region := classify_region(ll.x, ll.y, is_ocean_hint)
	var entry := {
		"lat": ll.y,
		"lon": ll.x,
		"uv": uv,
		"region": region,
		"is_ocean": is_ocean_hint,
		"sim_time": sim_time,
		"hp": maxf(hp, 0.0),
		"mass_kg": maxf(mass_kg, 0.0),
		"density_g_cm3": maxf(density_g_cm3, 0.0),
		"composition": composition,
	}
	impacts.append(entry)
	return entry


## Cheap heuristic: classify an albedo pixel as ocean. Tuned for the
## NASA-style Blue Marble texture in resources/3D/earth/ — water is
## blue-dominant and not extremely bright; land has more red/green
## or is very bright (snow / desert). Used by EarthSystem at impact
## time to pick land vs. ocean entries from the region table.
static func is_ocean_pixel(c: Color) -> bool:
	# Snow and ice can be very blue but also extremely bright. Bail
	# out before the blue-dominance test so polar caps register as
	# land (Antarctica / Greenland rather than Arctic Ocean).
	if c.r > 0.78 and c.g > 0.78 and c.b > 0.78:
		return false
	if c.b <= 0.12:
		return false
	return c.b > c.r + 0.04 and c.b > c.g - 0.02
