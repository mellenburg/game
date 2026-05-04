class_name UnitChassis
extends RefCounted
## Catalog of buildable chassis. A chassis fixes the slot count for each
## of the four part kinds; the player's "Build Unit" GUI only lets the
## operator swap parts within those counts. Pure data — no scene-tree
## dependency, no per-frame state — so the menu can clone or sample
## these freely.

const UnitPart = preload("res://scripts/unit_part.gd")

const ID_DEFAULT: String = "default"
const ID_HEAVY: String = "heavy"

var id: String
var label: String
# Number of slots of each kind. The default chassis has one of each;
# heavy doubles weapons + cooling systems (more guns, more cooling) and
# keeps energy storage + reactor at one each.
var weapon_slots: int
var cooling_system_slots: int
var energy_storage_slots: int
var reactor_slots: int
var thruster_slots: int


static func make(
	chassis_id: String,
	label: String,
	weapon_slots: int,
	cooling_system_slots: int,
	energy_storage_slots: int,
	reactor_slots: int,
	thruster_slots: int = 1,
) -> UnitChassis:
	var c := UnitChassis.new()
	c.id = chassis_id
	c.label = label
	c.weapon_slots = weapon_slots
	c.cooling_system_slots = cooling_system_slots
	c.energy_storage_slots = energy_storage_slots
	c.reactor_slots = reactor_slots
	c.thruster_slots = thruster_slots
	return c


# Catalog is rebuilt on each call. Cheap (four allocations) and avoids
# any module-load ordering pitfalls a static const dictionary would hit.
static func catalog() -> Array[UnitChassis]:
	var out: Array[UnitChassis] = []
	out.append(make(ID_DEFAULT, "Default", 1, 1, 1, 1, 1))
	out.append(make(ID_HEAVY, "Heavy", 2, 2, 1, 1, 1))
	return out


static func get_by_id(chassis_id: String) -> UnitChassis:
	for c in catalog():
		if c.id == chassis_id:
			return c
	# Fall back to the default chassis rather than null so callers don't
	# have to special-case a missing id (e.g. a save file from an older
	# build that referenced a chassis that's since been retired).
	return make(ID_DEFAULT, "Default", 1, 1, 1, 1, 1)


static func slot_count_for_kind(chassis_id: String, kind: int) -> int:
	var c := get_by_id(chassis_id)
	match kind:
		UnitPart.KIND_WEAPON:
			return c.weapon_slots
		UnitPart.KIND_COOLING_SYSTEM:
			return c.cooling_system_slots
		UnitPart.KIND_ENERGY_STORAGE:
			return c.energy_storage_slots
		UnitPart.KIND_REACTOR:
			return c.reactor_slots
		UnitPart.KIND_THRUSTER:
			return c.thruster_slots
	return 0
