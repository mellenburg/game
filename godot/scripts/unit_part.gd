class_name UnitPart
extends RefCounted
## Catalog of buildable parts. Every part falls into one of four kinds
## (weapon / cooling system / energy storage / reactor); each kind has
## three tiers — default (1.0× facet, the pre-existing hardcoded
## numbers), advanced (2.0× facet), and elite (3.0× facet). The Research
## autoload decides which tiers the player can equip at any given time;
## this file just publishes the catalog. SpawnDirector reads the
## multipliers when materialising a Satellite from a UnitConfig: weapon
## damage scales on the weapon's own multiplier, cooling-system
## multipliers feed the satellite's cooling_power_w (split across
## active weapons each tick), and energy-storage / reactor multipliers
## feed the satellite's energy_max / energy_rate.

const KIND_WEAPON: int = 0
const KIND_COOLING_SYSTEM: int = 1
const KIND_ENERGY_STORAGE: int = 2
const KIND_REACTOR: int = 3
const KIND_THRUSTER: int = 4

const KIND_LABELS: Array[String] = [
	"Weapon", "Cooling System", "Energy Storage", "Reactor", "Thruster",
]

# Weapon classes only mean something when kind == KIND_WEAPON. Stored as
# strings so adding a new weapon is one new catalog entry, not a new
# enum value threaded through every consumer.
const WCLASS_LASER: String = "laser"
const WCLASS_RAILGUN: String = "railgun"
const WCLASS_MISSILE: String = "missile"

# Tier labels — purely cosmetic, drives the dropdown text.
const TIER_DEFAULT: String = "default"
const TIER_ADVANCED: String = "advanced"
const TIER_ELITE: String = "elite"

var id: String
var kind: int
var label: String
# Tier multiplier on the part's facet. 1.0 = default tier (matches the
# pre-existing hardcoded numbers), 2.0 = advanced, 3.0 = elite. Spawn-time
# materialisation multiplies the relevant facet by this value:
#   weapon         → damage_per_second / damage_per_shot
#   cooling system → satellite.cooling_power_w
#   energy         → satellite.energy_max
#   reactor        → satellite.energy_rate
var multiplier: float = 1.0
# Empty string for non-weapon parts. WCLASS_* otherwise.
var weapon_class: String = ""
# Propulsion facets — only meaningful when kind == KIND_THRUSTER. Kept
# as plain fields rather than another multiplier because a thruster has
# three independent dials (thrust, Isp, propellant capacity) that don't
# all scale together: an advanced thruster might bump Isp without
# changing tank size, etc. Default zeros mean "this part contributes
# nothing to propulsion", which is the correct behaviour for every
# non-thruster part.
var thrust_n: float = 0.0
var isp_s: float = 0.0
var propellant_capacity_kg: float = 0.0


static func make(
	part_id: String,
	kind: int,
	label: String,
	multiplier: float,
	weapon_class: String = "",
) -> UnitPart:
	var p := UnitPart.new()
	p.id = part_id
	p.kind = kind
	p.label = label
	p.multiplier = multiplier
	p.weapon_class = weapon_class
	return p


# Thruster catalog factory. Carries the three propulsion facets the
# spawner needs to seed a Satellite — multiplier stays on the part for
# total_multiplier_for_kind() consistency, but the actual propulsion
# numbers come from the explicit fields below.
static func make_thruster(
	part_id: String,
	label: String,
	multiplier: float,
	thrust_n: float,
	isp_s: float,
	propellant_capacity_kg: float,
) -> UnitPart:
	var p := UnitPart.new()
	p.id = part_id
	p.kind = KIND_THRUSTER
	p.label = label
	p.multiplier = multiplier
	p.thrust_n = thrust_n
	p.isp_s = isp_s
	p.propellant_capacity_kg = propellant_capacity_kg
	return p


# Catalog is rebuilt on each call. Cost is trivial and avoids
# static-init ordering hazards. Three tiers per non-thruster kind
# (default / advanced / elite) — Research gates which tiers the
# operator can actually equip in the Hangar. Thrusters keep the
# default + advanced split for now; an elite thruster needs balance
# work alongside the propellant budget before it lands here.
static func catalog() -> Array[UnitPart]:
	var out: Array[UnitPart] = []
	out.append(make("laser_default", KIND_WEAPON, "Laser", 1.0, WCLASS_LASER))
	out.append(make("laser_advanced", KIND_WEAPON, "Laser (Advanced)", 2.0, WCLASS_LASER))
	out.append(make("laser_elite", KIND_WEAPON, "Laser (Elite)", 3.0, WCLASS_LASER))
	out.append(make("railgun_default", KIND_WEAPON, "Railgun", 1.0, WCLASS_RAILGUN))
	out.append(make("railgun_advanced", KIND_WEAPON, "Railgun (Advanced)", 2.0, WCLASS_RAILGUN))
	out.append(make("railgun_elite", KIND_WEAPON, "Railgun (Elite)", 3.0, WCLASS_RAILGUN))
	out.append(make("cooling_system_default", KIND_COOLING_SYSTEM, "Cooling System", 1.0))
	out.append(make("cooling_system_advanced", KIND_COOLING_SYSTEM, "Cooling System (Advanced)", 2.0))
	out.append(make("cooling_system_elite", KIND_COOLING_SYSTEM, "Cooling System (Elite)", 3.0))
	out.append(make("energy_storage_default", KIND_ENERGY_STORAGE, "Energy Storage", 1.0))
	out.append(make("energy_storage_advanced", KIND_ENERGY_STORAGE, "Energy Storage (Advanced)", 2.0))
	out.append(make("energy_storage_elite", KIND_ENERGY_STORAGE, "Energy Storage (Elite)", 3.0))
	out.append(make("reactor_default", KIND_REACTOR, "Reactor", 1.0))
	out.append(make("reactor_advanced", KIND_REACTOR, "Reactor (Advanced)", 2.0))
	out.append(make("reactor_elite", KIND_REACTOR, "Reactor (Elite)", 3.0))
	# Default thruster: kerolox-class — 20 kN, Isp 300 s, 300 kg of
	# propellant. Advanced: hydrolox-class — 40 kN, Isp 450 s, 600 kg
	# tank. Both numbers picked to land delta-v capacity in the
	# few-hundred-m/s range at the satellite's default 700 kg dry mass,
	# which feels like a healthy in-game maneuver budget without making
	# orbit changes free.
	out.append(make_thruster(
		"thruster_default", "Thruster", 1.0, 20000.0, 300.0, 300.0
	))
	out.append(make_thruster(
		"thruster_advanced", "Thruster (Advanced)", 2.0, 40000.0, 450.0, 600.0
	))
	return out


static func get_by_id(part_id: String) -> UnitPart:
	for p in catalog():
		if p.id == part_id:
			return p
	# Empty placeholder so callers can identify "missing/unknown part"
	# without having to null-check. Multiplier 0.0 means "contributes
	# nothing" — a unit with a zeroed slot just doesn't get that facet.
	return make("", KIND_WEAPON, "(empty)", 0.0)


static func parts_of_kind(kind: int) -> Array[UnitPart]:
	var out: Array[UnitPart] = []
	for p in catalog():
		if p.kind == kind:
			out.append(p)
	return out


static func default_part_id_for_kind(kind: int) -> String:
	match kind:
		KIND_WEAPON:
			return "laser_default"
		KIND_COOLING_SYSTEM:
			return "cooling_system_default"
		KIND_ENERGY_STORAGE:
			return "energy_storage_default"
		KIND_REACTOR:
			return "reactor_default"
		KIND_THRUSTER:
			return "thruster_default"
	return ""
