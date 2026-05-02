class_name SurfaceUnitConfig
extends RefCounted
## Per-surface-unit pre-game configuration: display name, lat/lon
## placement, mass + HP stats, and weapon kind. Mirrors UnitConfig in
## intent but for fixed installations on Earth's surface rather than
## orbital satellites. Owned by PlayerLoadout, mutated by the menu's
## Surface Ops tab, consumed by SpawnDirector.spawn_surface_units when
## the player launches a stage.
##
## Pure data — no SceneTree dependency, no per-frame state. Lives in
## its own file (rather than being a Dictionary on PlayerLoadout) so
## the menu and spawner can lean on the type system to catch typos.

# Surface units are laser-only in the MVP. The railgun's recoil math
# (impulse divided by mass yields a Δv applied to the shooter's orbit)
# doesn't translate cleanly to a body that's mechanically anchored to
# the rotating Earth, so RailgunWeapon.can_fire refuses surface-unit
# shooters. Keeping the enum entry around so the Hangar-style picker in
# the menu has a stable index for future surface railgun support.
const WEAPON_LASER: int = 0

const WEAPON_LABELS: Array[String] = ["Laser"]

const NAME_PREFIX: String = "S-"
# Default fixed-installation mass. Higher than an orbital satellite
# (10 t vs. 1 t) so the railgun safety check, if surface units are
# ever allowed to mount one, would naturally clamp the recoil-induced
# Δv to a barely-perceptible nudge.
const DEFAULT_MASS_KG: float = 10000.0
# Larger HP cap than orbital sats: a ground emplacement is a harder
# target than a thin-skinned satellite. 200 matches the decaying-orbit
# threat ceiling so the bottom-row HUD area math stays stable.
const DEFAULT_HP: float = 200.0

const LAT_MIN_DEG: float = -85.0
const LAT_MAX_DEG: float = 85.0
const LON_MIN_DEG: float = -180.0
const LON_MAX_DEG: float = 180.0

var name: String = "S-01"
var lat_deg: float = 0.0
var lon_deg: float = 0.0
var weapon_kind: int = WEAPON_LASER
var mass_kg: float = DEFAULT_MASS_KG
var max_hp: float = DEFAULT_HP


static func make(idx: int, lat_deg: float, lon_deg: float) -> SurfaceUnitConfig:
	var u := SurfaceUnitConfig.new()
	u.name = "%s%02d" % [NAME_PREFIX, idx + 1]
	u.lat_deg = clampf(lat_deg, LAT_MIN_DEG, LAT_MAX_DEG)
	u.lon_deg = clampf(lon_deg, LON_MIN_DEG, LON_MAX_DEG)
	return u
