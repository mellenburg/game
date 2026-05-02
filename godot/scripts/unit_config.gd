class_name UnitConfig
extends RefCounted
## A buildable unit definition: chassis (slot layout) plus the chosen
## part for each slot. Lives in the player's unit pool until a Launch
## references it. Pure data — no SceneTree dependency, no per-frame
## state. SpawnDirector consumes both this and a Launch when the player
## confirms LAUNCH on the menu.

const UnitChassis = preload("res://scripts/unit_chassis.gd")
const UnitPart = preload("res://scripts/unit_part.gd")

var id: String = ""
var name: String = "T-01"
var chassis_id: String = UnitChassis.ID_DEFAULT
# One entry per slot, holding the catalog id of the chosen part. The
# arrays' lengths track the chassis' slot counts; set_chassis() resizes
# them and pads with the default part for that kind so a freshly-built
# unit is always fully kitted.
var weapon_part_ids: Array[String] = []
var radiator_part_ids: Array[String] = []
var energy_storage_part_ids: Array[String] = []
var reactor_part_ids: Array[String] = []


# Build a fresh unit on the default chassis with default-tier parts in
# every slot. Used by the menu's "Build Unit" button and by
# PlayerLoadout.reset_units() to seed the starting pool.
static func make_default(unit_id: String, unit_name: String) -> UnitConfig:
	var u := UnitConfig.new()
	u.id = unit_id
	u.name = unit_name
	u.set_chassis(UnitChassis.ID_DEFAULT)
	return u


# Resize each part-id array to match the chassis' slot count, padding
# new slots with the default part for that kind. Existing entries are
# preserved up to the new slot count so swapping chassis doesn't lose
# already-picked parts when the new layout has the same or more slots.
func set_chassis(new_chassis_id: String) -> void:
	chassis_id = new_chassis_id
	weapon_part_ids = _resize_part_ids(weapon_part_ids, UnitPart.KIND_WEAPON)
	radiator_part_ids = _resize_part_ids(radiator_part_ids, UnitPart.KIND_RADIATOR)
	energy_storage_part_ids = _resize_part_ids(
		energy_storage_part_ids, UnitPart.KIND_ENERGY_STORAGE,
	)
	reactor_part_ids = _resize_part_ids(reactor_part_ids, UnitPart.KIND_REACTOR)


func _resize_part_ids(current: Array[String], kind: int) -> Array[String]:
	var slots: int = UnitChassis.slot_count_for_kind(chassis_id, kind)
	var default_id := UnitPart.default_part_id_for_kind(kind)
	var out: Array[String] = []
	for i in range(slots):
		if i < current.size() and current[i] != "":
			out.append(current[i])
		else:
			out.append(default_id)
	return out


func part_ids_for_kind(kind: int) -> Array[String]:
	match kind:
		UnitPart.KIND_WEAPON:
			return weapon_part_ids
		UnitPart.KIND_RADIATOR:
			return radiator_part_ids
		UnitPart.KIND_ENERGY_STORAGE:
			return energy_storage_part_ids
		UnitPart.KIND_REACTOR:
			return reactor_part_ids
	return [] as Array[String]


func set_part_id(kind: int, slot_index: int, part_id: String) -> void:
	var arr := part_ids_for_kind(kind)
	if slot_index < 0 or slot_index >= arr.size():
		return
	arr[slot_index] = part_id


# Sum of multipliers across every slot of the given kind. Slots holding
# an unknown / empty part contribute 0 (UnitPart.get_by_id falls back to
# multiplier 0.0). Used by SpawnDirector to compute the satellite's
# energy_max and energy_rate from the whole storage / reactor row at
# once.
func total_multiplier_for_kind(kind: int) -> float:
	var total: float = 0.0
	for part_id in part_ids_for_kind(kind):
		total += UnitPart.get_by_id(part_id).multiplier
	return total


# Short single-line summary, e.g. "Default · Laser + Radiator + Storage
# + Reactor". Used in the unit pool's list rows so the player can pick
# units by silhouette without opening the editor.
func summary() -> String:
	var chassis := UnitChassis.get_by_id(chassis_id)
	var parts: Array[String] = []
	for kind in [
		UnitPart.KIND_WEAPON,
		UnitPart.KIND_RADIATOR,
		UnitPart.KIND_ENERGY_STORAGE,
		UnitPart.KIND_REACTOR,
	]:
		for part_id in part_ids_for_kind(kind):
			parts.append(UnitPart.get_by_id(part_id).label)
	return "%s · %s" % [chassis.label, " + ".join(parts)]
