class_name UnitPart
extends RefCounted
## Catalog of buildable parts. Every part falls into one of four kinds
## (weapon / radiator / energy storage / reactor); each kind has a
## "default" tier whose facet matches the previously hardcoded numbers
## and an "advanced" tier with twice the facet. SpawnDirector reads
## these multipliers when materialising a Satellite from a UnitConfig:
## weapon damage scales on the weapon's own multiplier, radiator
## multipliers feed each weapon's cool-rate, and energy-storage /
## reactor multipliers feed the satellite's energy_max / energy_rate.

const KIND_WEAPON: int = 0
const KIND_RADIATOR: int = 1
const KIND_ENERGY_STORAGE: int = 2
const KIND_REACTOR: int = 3

const KIND_LABELS: Array[String] = [
	"Weapon", "Radiator", "Energy Storage", "Reactor",
]

# Weapon classes only mean something when kind == KIND_WEAPON. Stored as
# strings so adding a new weapon is one new catalog entry, not a new
# enum value threaded through every consumer.
const WCLASS_LASER: String = "laser"
const WCLASS_RAILGUN: String = "railgun"

# Tier labels — purely cosmetic, drives the dropdown text.
const TIER_DEFAULT: String = "default"
const TIER_ADVANCED: String = "advanced"

var id: String
var kind: int
var label: String
# Tier multiplier on the part's facet. 1.0 = default tier (matches the
# pre-existing hardcoded numbers), 2.0 = advanced tier. Spawn-time
# materialisation multiplies the relevant facet by this value:
#   weapon  → damage_per_second / damage_per_shot
#   radiator → weapon cool_rate
#   energy   → satellite.energy_max
#   reactor  → satellite.energy_rate
var multiplier: float = 1.0
# Empty string for non-weapon parts. WCLASS_* otherwise.
var weapon_class: String = ""


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


# Catalog is rebuilt on each call. Eight entries — the cost is trivial
# and avoids static-init ordering hazards.
static func catalog() -> Array[UnitPart]:
	var out: Array[UnitPart] = []
	out.append(make("laser_default", KIND_WEAPON, "Laser", 1.0, WCLASS_LASER))
	out.append(make("laser_advanced", KIND_WEAPON, "Laser (Advanced)", 2.0, WCLASS_LASER))
	out.append(make("railgun_default", KIND_WEAPON, "Railgun", 1.0, WCLASS_RAILGUN))
	out.append(make("railgun_advanced", KIND_WEAPON, "Railgun (Advanced)", 2.0, WCLASS_RAILGUN))
	out.append(make("radiator_default", KIND_RADIATOR, "Radiator", 1.0))
	out.append(make("radiator_advanced", KIND_RADIATOR, "Radiator (Advanced)", 2.0))
	out.append(make("energy_storage_default", KIND_ENERGY_STORAGE, "Energy Storage", 1.0))
	out.append(make("energy_storage_advanced", KIND_ENERGY_STORAGE, "Energy Storage (Advanced)", 2.0))
	out.append(make("reactor_default", KIND_REACTOR, "Reactor", 1.0))
	out.append(make("reactor_advanced", KIND_REACTOR, "Reactor (Advanced)", 2.0))
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
		KIND_RADIATOR:
			return "radiator_default"
		KIND_ENERGY_STORAGE:
			return "energy_storage_default"
		KIND_REACTOR:
			return "reactor_default"
	return ""
