class_name CelestialBody
extends RefCounted
## Single source of truth for a mass-centre's per-mission parameters:
## physics (μ, radius, mass, surface gravity), display (sidereal day,
## axial tilt, fallback colour), and the texture set the shared planet
## shader binds. Adding a new body is one new factory method, one
## entry in `for_stage`, one entry in `PlayerLoadout.STAGES`, and a
## directory of textures under `resources/3D/<id>/`.
##
## Consumers (MassCenterSystem, MassCenter, ImpactMap, SurfacePlacementMap,
## Menu's brief panel) ask the body for whatever they need rather than
## holding their own per-body switch. That keeps "what's different
## about Mars" in this file instead of smeared across the codebase.
##
## μ values use km^3/s^2 so they slot directly into MassCenterOrbit's
## propagator without unit conversion. Surface gravity is stored in
## Earth-g for the mission brief; it's redundant with (μ, radius) but
## the headline value reads more naturally than a recomputed m/s².
##
## Pure RefCounted — no scene dependencies — so this file is safely
## loadable from the menu, the in-game system, and headless tests.

const MassCenterOrbit = preload("res://scripts/mass_center_orbit.gd")

# IDs match the corresponding entry in PlayerLoadout.STAGES so a stage
# selection trivially looks up its body. Adding a body means appending
# an ID here AND a `make_<id>()` factory below AND a match arm in
# `for_stage` — keeping the three in one file is intentional so the
# wiring is auditable in one place.
const ID_EARTH := "earth"
const ID_MARS := "mars"
const ID_SATURN := "saturn"

# Physics ------------------------------------------------------------
var id: String
var display_name: String
# Mean equatorial radius (km).
var radius_km: float
# Mass (kg). Stored alongside μ for the mission brief — μ alone drives
# the propagator, but exposing the headline mass number lets the brief
# read like an almanac entry.
var mass_kg: float
# Standard gravitational parameter (km^3/s^2). The orbital propagator
# reads this one; mass / G is implicit.
var mu_km3_s2: float
# Surface gravity expressed as a multiple of Earth's g₀. Cached for the
# mission brief; recomputable from (μ, radius) but redundant on purpose.
var surface_gravity_g: float
# Sidereal rotation period in seconds — drives the Earth node's daily
# spin so the day/night terminator cycles at the body's actual day
# length (Mars's 24.6 h, etc.) instead of always Earth's 24 h.
var sidereal_day_s: float
# Obliquity of the body's spin axis relative to its orbital plane.
var axial_tilt_rad: float
# Altitude (km above surface) below which the atmosphere meaningfully
# affects an orbiting body. Asteroid/decaying threats entering this zone
# begin losing apoapsis continuously; the ablation floor (impact
# threshold) is derived as safe_orbit_altitude_km - 90 km.
var safe_orbit_altitude_km: float

# Rendering ----------------------------------------------------------
# Hint colour the system map / orbit preview / fallback material can
# tint to when no texture is available.
var fallback_color: Color
# Equirectangular albedo source. Bound to the planet shader's day-side
# sampler and to the Surface Ops / impact-map basemaps. Required.
var albedo_path: String
# Optional companion textures. Empty string == "this body doesn't have
# one"; the planet shader's corresponding branch collapses to a 1×1
# black placeholder. Earth ships all four; Mars has only albedo.
var night_path: String
var normal_path: String
var clouds_path: String

# Default starting-fleet orbital geometry. The pre-game menu seeds the
# laser shell at `default_laser_alt_km` and the railguns at
# `default_railgun_perigee_km`; both are scaled to the body so a tiny
# rocky world doesn't get the same 5 000 km shell as a gas giant
# 10× Earth's radius. Earth defaults reproduce the legacy numbers.
var default_laser_alt_km: float = 5000.0
var default_railgun_perigee_km: float = 8000.0

# Ring system. Real radii in km from the body's centre — the ring mesh
# scales these by Satellite.SCENE_SCALE, the same conversion the rest
# of the renderer uses. Empty ring_texture_path == "this body has no
# ring system"; the SaturnRings node is only instantiated when the path
# resolves. ring_tilt_offset_rad lets a body's rings sit at a different
# obliquity than the body's spin axis — Saturn's rings sit in the
# equatorial plane (offset = 0) but the field exists so future bodies
# (e.g. Uranus's ring system) can decouple ring tilt from axial tilt.
var has_rings: bool = false
var ring_inner_km: float = 0.0
var ring_outer_km: float = 0.0
var ring_texture_path: String = ""
var ring_tilt_offset_rad: float = 0.0

# Camera radius band, expressed in body-radii. The OrbitCamera reads
# these to size DEFAULT / MIN / MAX standoff from the active body so a
# Saturn stage doesn't bury the camera inside the planet at the Earth-
# scaled defaults. Values match the legacy Earth band when left at the
# defaults below.
var camera_default_radii: float = 7.8
var camera_min_radii: float = 1.5
var camera_max_radii: float = 18.0


static func make_earth() -> CelestialBody:
	var body := CelestialBody.new()
	body.id = ID_EARTH
	body.display_name = "Earth"
	body.radius_km = 6371.0
	body.mass_kg = 5.972e24
	body.mu_km3_s2 = 398600.4415
	body.surface_gravity_g = 1.0
	body.sidereal_day_s = 86164.0
	body.axial_tilt_rad = 23.5 * PI / 180.0
	body.safe_orbit_altitude_km = 150.0
	body.fallback_color = Color(0.36, 0.58, 0.92)
	body.albedo_path = "res://resources/3D/earth/4096_earth.jpg"
	body.night_path = "res://resources/3D/earth/4096_night_lights.jpg"
	body.normal_path = "res://resources/3D/earth/4096_normal.jpg"
	body.clouds_path = "res://resources/3D/earth/4096_clouds.jpg"
	return body


static func make_mars() -> CelestialBody:
	# Mars constants from the NASA Planetary Fact Sheet:
	#   radius        = 3389.5 km (mean)
	#   mass          = 6.4171e23 kg
	#   μ             = 42828.37 km^3/s^2
	#   surface g     = 3.721 m/s^2 → 0.3794 g
	#   sidereal day  = 88642.66 s (24h 37m 22.66s)
	#   axial tilt    = 25.19° from orbital normal
	var body := CelestialBody.new()
	body.id = ID_MARS
	body.display_name = "Mars"
	body.radius_km = 3389.5
	body.mass_kg = 6.4171e23
	body.mu_km3_s2 = 42828.37
	body.surface_gravity_g = 0.3794
	body.sidereal_day_s = 88642.66
	body.axial_tilt_rad = 25.19 * PI / 180.0
	body.safe_orbit_altitude_km = 100.0
	body.fallback_color = Color(0.82, 0.40, 0.28)
	# NASA PIA02066 cylindrical mosaic, south pole filled in via mirror —
	# see resources/3D/mars/CREDITS.md.
	body.albedo_path = "res://resources/3D/mars/2304_mars.jpg"
	body.night_path = ""
	body.normal_path = ""
	body.clouds_path = ""
	return body


static func make_saturn() -> CelestialBody:
	# Saturn constants from the NASA Planetary Fact Sheet:
	#   equatorial radius = 60268 km
	#   mass              = 5.6834e26 kg
	#   μ                 = 37931187.0 km^3/s^2
	#   surface gravity   = 10.44 m/s^2 → 1.065 g (1-bar reference)
	#   sidereal day      = 38362.4 s (~10h 39m 22s, Voyager radio period)
	#   axial tilt        = 26.73° from orbital normal
	# Ring extents track the canonical Cassini geometry:
	#   D-ring inner edge ≈ 66 900 km from centre
	#   F-ring outer edge ≈ 140 220 km from centre
	# safe_orbit_altitude is generous because Saturn lacks a hard
	# surface — the value gates atmospheric-decay logic and isn't a
	# physical altitude in the rocky-planet sense; 1 000 km is the
	# rough "above the visible cloud deck plus a bit" buffer.
	var body := CelestialBody.new()
	body.id = ID_SATURN
	body.display_name = "Saturn"
	body.radius_km = 60268.0
	body.mass_kg = 5.6834e26
	body.mu_km3_s2 = 37931187.0
	body.surface_gravity_g = 1.065
	body.sidereal_day_s = 38362.4
	body.axial_tilt_rad = 26.73 * PI / 180.0
	body.safe_orbit_altitude_km = 1000.0
	body.fallback_color = Color(0.93, 0.85, 0.62)
	# Default starting orbits live well outside the F ring (~80 000 km
	# altitude) so the seeded fleet doesn't spawn in the middle of the
	# ring system. Railgun perigee sits closer to the body so the
	# Tsiolkovsky budget still reads as "long elliptical arc" rather
	# than "circular outside the rings".
	body.default_laser_alt_km = 90000.0
	body.default_railgun_perigee_km = 110000.0
	# Camera band scaled down a touch from the Earth multipliers — at
	# 7.8 body-radii Saturn's apparent-disc still dominates the view
	# but the rings would clip the standoff; 4.5 keeps the rings inside
	# the frame at the default radius.
	body.camera_default_radii = 4.5
	body.camera_min_radii = 1.05
	body.camera_max_radii = 12.0
	# Procedurally generated banded surface map with the Cassini-era
	# hexagonal vortex baked in over the north polar cap. See
	# resources/3D/saturn/CREDITS.md for the bake-script details.
	body.albedo_path = "res://resources/3D/saturn/2048_saturn.jpg"
	body.night_path = ""
	body.normal_path = ""
	body.clouds_path = ""
	body.has_rings = true
	body.ring_inner_km = 66900.0
	body.ring_outer_km = 140220.0
	body.ring_texture_path = "res://resources/3D/saturn/2048_rings.png"
	body.ring_tilt_offset_rad = 0.0
	return body


# Look up a body record by stage id. Falls back to Earth when the id
# doesn't match a known body — keeps the legacy debug-boot path (no
# PlayerLoadout) on Earth defaults.
static func for_stage(stage_id: String) -> CelestialBody:
	match stage_id:
		ID_MARS:
			return make_mars()
		ID_SATURN:
			return make_saturn()
		_:
			return make_earth()


# Resolve the body the player is currently configuring / playing. Single
# entry point so callers don't repeat the get_tree → get_node_or_null
# dance — they just call CelestialBody.active() and get a body record
# they can read texture paths / radius / display_name off. Falls back
# to Earth when PlayerLoadout isn't reachable (headless tests, direct
# main.tscn boots) so the legacy entry path keeps working.
static func active(tree: SceneTree) -> CelestialBody:
	if tree == null:
		return make_earth()
	var loadout := tree.root.get_node_or_null("PlayerLoadout")
	if loadout == null:
		return make_earth()
	return for_stage(String(loadout.selected_stage_id))


# Apply this body's μ and radius to the static MassCenterOrbit fields so
# every orbital propagation downstream of this call uses the matching
# physics. Idempotent; called from MassCenterSystem._ready before any
# satellite spawn / propagation work.
func apply_to_propagator() -> void:
	MassCenterOrbit.MU = mu_km3_s2
	MassCenterOrbit.BODY_RADIUS_KM = radius_km
	MassCenterOrbit.SAFE_ORBIT_ALT_KM = safe_orbit_altitude_km


# Convenience for the impact-map / surface-placement-map basemaps:
# both want the equirectangular albedo as a Texture2D, and both fall
# back to a solid `fallback_color` if the asset is missing (headless /
# asset-stripped runs). Keeping the loader here means consumers don't
# repeat the ResourceLoader.exists check.
func load_albedo_texture() -> Texture2D:
	if albedo_path == "" or not ResourceLoader.exists(albedo_path):
		return null
	return load(albedo_path) as Texture2D
