class_name CelestialBody
extends RefCounted
## Per-mission planetary parameters: gravitational parameter (μ),
## physical radius, mass, sidereal rotation period, axial tilt, and
## the surface-texture set the planet shader binds. EarthSystem looks
## up the entry for the player's selected stage and applies it before
## any orbital math runs.
##
## μ values use km^3/s^2 so they slot directly into EarthOrbit's
## existing propagator without unit conversion. Surface gravity is
## stored in Earth-g for the mission brief; it's redundant with
## (mass, radius) but keeping the headline value explicit avoids the
## brief recomputing it every refresh.
##
## Pure RefCounted — no scene dependencies — so this file is safely
## loadable from the menu, the in-game system, and headless tests.

const EarthOrbit = preload("res://scripts/earth_orbit.gd")

# IDs match the corresponding entry in PlayerLoadout.STAGES so a stage
# selection trivially looks up its body.
const ID_EARTH := "earth"
const ID_MARS := "mars"

# Texture-set identifier. The "earth" set drives Earth's day/night/
# normal/clouds JPEGs from resources/3D/earth/; "mars" drives the
# single global Mars albedo (NASA Photojournal PIA02066) shipped under
# resources/3D/mars/. Both bind to the shared planet.gdshader. Other
# bodies can be added by extending the binding logic in earth.gd.
const TEXTURES_EARTH := "earth"
const TEXTURES_MARS := "mars"

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
# spin so the day/night terminator on Mars cycles at ~24.6 h, not 24 h.
var sidereal_day_s: float
# Obliquity of the body's spin axis relative to its orbital plane.
var axial_tilt_rad: float
# Texture set the planet shader should bind. See TEXTURES_* above.
var texture_set: String
# Hint colour the system map / orbit preview / fallback material can
# tint to when no texture is available.
var fallback_color: Color


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
	body.texture_set = TEXTURES_EARTH
	body.fallback_color = Color(0.36, 0.58, 0.92)
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
	body.texture_set = TEXTURES_MARS
	body.fallback_color = Color(0.82, 0.40, 0.28)
	return body


# Look up a body record by stage id. Falls back to Earth when the id
# doesn't match a known body — keeps the legacy debug-boot path
# (no PlayerLoadout) on Earth defaults.
static func for_stage(stage_id: String) -> CelestialBody:
	match stage_id:
		ID_MARS:
			return make_mars()
		_:
			return make_earth()


# Apply this body's μ and radius to the static EarthOrbit fields so
# every orbital propagation downstream of this call uses the matching
# physics. Idempotent; called from EarthSystem._ready before any
# satellite spawn / propagation work.
func apply_to_propagator() -> void:
	EarthOrbit.MU = mu_km3_s2
	EarthOrbit.EARTH_RADIUS_KM = radius_km
