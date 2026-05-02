class_name Launch
extends RefCounted
## A scheduled launch: an orbit (altitude / inclination / RAAN / true
## anomaly) plus the unit assigned to it. Lives in PlayerLoadout.launches
## while the player configures the run; SpawnDirector materialises one
## satellite per launch when the player presses LAUNCH.
##
## A launch with no assigned unit is a "nullified" launch — visible in
## the menu so the operator can assign one, but discarded by
## PlayerLoadout.purge_unassigned_launches() before the run begins.

const Propulsion = preload("res://scripts/propulsion.gd")

# Bounds for the orbit sliders. Match what the menu's pre-existing
# Orbital Ops tab shipped with so the operator's mental model carries
# over from the previous build.
const ALT_MIN_KM: float = 300.0
const ALT_MAX_KM: float = 40000.0
const INC_MIN_DEG: float = 0.0
const INC_MAX_DEG: float = 90.0
const RAAN_MIN_DEG: float = 0.0
const RAAN_MAX_DEG: float = 360.0
const NU_MIN_DEG: float = 0.0
const NU_MAX_DEG: float = 360.0

var name: String = "L-01"
# Empty string ⇒ unit not assigned ⇒ launch will be discarded on purge.
var unit_id: String = ""
var altitude_km: float = 500.0
var inclination_deg: float = 0.0
var raan_deg: float = 0.0
var true_anomaly_deg: float = 0.0


static func make(idx: int) -> Launch:
	var l := Launch.new()
	l.name = "L-%02d" % (idx + 1)
	l.altitude_km = 500.0
	# Spread the trio across inclination + RAAN + true anomaly so the
	# default formation fans out in 3D rather than stacking on one
	# ground-track. Mirrors the previous default fleet's spread.
	l.inclination_deg = float(idx) * 25.0
	l.raan_deg = float(idx) * 60.0
	l.true_anomaly_deg = float(idx) * 120.0
	return l


func has_unit() -> bool:
	return unit_id != ""


# Δv (m/s) needed to place a unit on this launch's configured orbit,
# measured against the free equatorial-LEO baseline. Used by
# PlayerLoadout to compute each launch's propellant draw against the
# pre-game budget. Zero for a launch parked at exactly
# Propulsion.BASELINE_LEO_ALT_KM and zero inclination.
func setup_dv_ms() -> float:
	return Propulsion.launch_setup_dv_ms(
		altitude_km, deg_to_rad(inclination_deg)
	)


# Propellant cost (kg) to fly this launch with a stage of the given
# wet mass. Rocket-equation-weighted: heavier units debit more from
# the budget for the same target orbit, lighter units less. Caller
# supplies the wet mass (dry + onboard propellant); the launch budget
# itself is paid against REF_LAUNCH_ISP_S — the booster's Isp,
# distinct from the unit's onboard thrusters.
func propellant_cost_kg(unit_wet_mass_kg: float) -> float:
	return Propulsion.propellant_for_dv_kg(
		setup_dv_ms(), unit_wet_mass_kg, Propulsion.REF_LAUNCH_ISP_S
	)
