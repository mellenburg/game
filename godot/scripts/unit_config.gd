class_name UnitConfig
extends RefCounted
## Per-unit pre-game configuration: display name, weapon loadout choice,
## and initial-orbit elements. Owned by PlayerLoadout, mutated by the
## menu tabs (Hangar / Orbital Ops), consumed by SpawnDirector when
## the player launches a stage. Pure data — no SceneTree dependency,
## no per-frame state.

# Weapon kinds the Hangar tab lets the player pick. Each maps to a
# fixed slot composition that SpawnDirector materialises into Weapon
# instances when the satellite is spawned. Kept as ints (not enums)
# so the menu's OptionButton index lines up directly.
const WEAPON_LASER: int = 0
const WEAPON_RAILGUN: int = 1
const WEAPON_MIXED: int = 2

const WEAPON_LABELS: Array[String] = ["Laser", "Railgun", "Laser + Railgun"]

# Bounds for the Orbital Ops sliders. Lower altitude bound stays
# above the atmosphere so a freshly-launched unit isn't already
# decaying; upper bound matches the GEO-ish band used elsewhere.
const ALT_MIN_KM: float = 300.0
const ALT_MAX_KM: float = 40000.0
const INC_MIN_DEG: float = 0.0
const INC_MAX_DEG: float = 90.0
const RAAN_MIN_DEG: float = 0.0
const RAAN_MAX_DEG: float = 360.0
const NU_MIN_DEG: float = 0.0
const NU_MAX_DEG: float = 360.0

var name: String = "T-01"
var weapon_kind: int = WEAPON_LASER
var altitude_km: float = 500.0
var inclination_deg: float = 0.0
var raan_deg: float = 0.0
var true_anomaly_deg: float = 0.0


static func make(idx: int) -> UnitConfig:
	var u := UnitConfig.new()
	u.name = "T-%02d" % (idx + 1)
	# Default loadout mirrors SpawnDirector's legacy starting fleet so
	# a player who clicks LAUNCH without touching the Hangar tab gets
	# the same composition the game shipped with: two lasers + one
	# railgun across slots 0..2.
	u.weapon_kind = WEAPON_RAILGUN if idx >= 2 else WEAPON_LASER
	u.altitude_km = 500.0
	# Spread the trio across inclinations and true anomalies so the
	# default formation fans out in 3D rather than stacking on a
	# single ground-track.
	u.inclination_deg = float(idx) * 25.0
	u.raan_deg = float(idx) * 60.0
	u.true_anomaly_deg = float(idx) * 120.0
	return u
