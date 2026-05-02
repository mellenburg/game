class_name SurfacePosition
extends RefCounted
## Pure-math helper for converting (lat, lon) on Earth's rotating
## surface to an ECI position. Inverse of ImpactTracker.eci_to_latlon —
## kept in its own RefCounted so the surface-unit spawner can fire-and-
## forget without dragging in a SceneTree, and so the round-trip
## identity is unit-testable.
##
## The basis composition mirrors Earth.gd's render transform exactly —
## ECI = AXIAL_TILT * daily(earth_phase) * POLE_ALIGN * mesh_local.
## Mesh-local conventions match SphereMesh's UV layout (u=0 seam runs
## through +Z, +Y is the north pole), so a satellite spawned via this
## helper draws on the globe at the same lat/lon the menu picker
## placed it.

const POLE_ALIGN := Basis(Vector3(1.0, 0.0, 0.0), PI / 2.0)
const AXIAL_TILT_RAD: float = 23.5 * PI / 180.0
const AXIAL_TILT := Basis(Vector3(1.0, 0.0, 0.0), AXIAL_TILT_RAD)


## Mesh-local unit vector for a (lat, lon) on the Earth surface. Matches
## the inverse of ImpactTracker.mesh_local_to_uv: lat=0, lon=0 lands at
## (0, 0, -1); lat=90 at the +Y pole; lon=+90 along +X (cos_lat) etc.
static func latlon_to_mesh_local(lat_deg: float, lon_deg: float) -> Vector3:
	var lat_rad := deg_to_rad(lat_deg)
	var phi := deg_to_rad(lon_deg + 180.0)
	var cos_lat := cos(lat_rad)
	return Vector3(cos_lat * sin(phi), sin(lat_rad), cos_lat * cos(phi))


## ECI position (km) of a surface point at (lat_deg, lon_deg) at the
## given Earth phase. `radius_km` is typically EARTH_RADIUS plus a
## small antenna offset so the position is strictly above the LOS-
## blocking sphere.
static func latlon_to_eci(
	lat_deg: float, lon_deg: float, earth_phase: float, radius_km: float
) -> Vector3:
	var local := latlon_to_mesh_local(lat_deg, lon_deg)
	var daily := Basis(Vector3(0.0, 0.0, 1.0), earth_phase)
	var basis := AXIAL_TILT * daily * POLE_ALIGN
	return (basis * local) * radius_km
