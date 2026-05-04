class_name CelestialBody
extends RefCounted
## Single source of truth for a mass-centre's per-mission parameters:
## physics (μ, radius, mass, surface gravity), display (sidereal day,
## axial tilt, fallback colour), and the texture set the shared planet
## shader binds. Adding a new body is one new factory method, one
## entry in `for_stage`, one entry in `PlayerLoadout.STAGES`, and a
## directory of textures under `resources/3D/<id>/`.
##
## Consumers (EarthSystem, Earth, ImpactMap, SurfacePlacementMap,
## Menu's brief panel) ask the body for whatever they need rather than
## holding their own per-body switch. That keeps "what's different
## about Mars" in this file instead of smeared across the codebase.
##
## μ values use km^3/s^2 so they slot directly into EarthOrbit's
## propagator without unit conversion. Surface gravity is stored in
## Earth-g for the mission brief; it's redundant with (μ, radius) but
## the headline value reads more naturally than a recomputed m/s².
##
## Pure RefCounted — no scene dependencies — so this file is safely
## loadable from the menu, the in-game system, and headless tests.

const EarthOrbit = preload("res://scripts/earth_orbit.gd")

# IDs match the corresponding entry in PlayerLoadout.STAGES so a stage
# selection trivially looks up its body. Adding a body means appending
# an ID here AND a `make_<id>()` factory below AND a match arm in
# `for_stage` — keeping the three in one file is intentional so the
# wiring is auditable in one place.
const ID_EARTH := "earth"
const ID_MARS := "mars"

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
	body.fallback_color = Color(0.82, 0.40, 0.28)
	# NASA PIA02066 cylindrical mosaic, south pole filled in via mirror —
	# see resources/3D/mars/CREDITS.md.
	body.albedo_path = "res://resources/3D/mars/2304_mars.jpg"
	body.night_path = ""
	body.normal_path = ""
	body.clouds_path = ""
	return body


# Look up a body record by stage id. Falls back to Earth when the id
# doesn't match a known body — keeps the legacy debug-boot path (no
# PlayerLoadout) on Earth defaults.
static func for_stage(stage_id: String) -> CelestialBody:
	match stage_id:
		ID_MARS:
			return make_mars()
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


# Apply this body's μ and radius to the static EarthOrbit fields so
# every orbital propagation downstream of this call uses the matching
# physics. Idempotent; called from EarthSystem._ready before any
# satellite spawn / propagation work.
func apply_to_propagator() -> void:
	EarthOrbit.MU = mu_km3_s2
	EarthOrbit.EARTH_RADIUS_KM = radius_km


# Convenience for the impact-map / surface-placement-map basemaps:
# both want the equirectangular albedo as a Texture2D, and both fall
# back to a solid `fallback_color` if the asset is missing (headless /
# asset-stripped runs). Keeping the loader here means consumers don't
# repeat the ResourceLoader.exists check.
func load_albedo_texture() -> Texture2D:
	if albedo_path == "" or not ResourceLoader.exists(albedo_path):
		return null
	return load(albedo_path) as Texture2D
