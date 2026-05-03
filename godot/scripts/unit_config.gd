class_name UnitConfig
extends RefCounted
## A buildable unit definition: chassis (slot layout) plus the chosen
## part for each slot. Lives in the player's unit pool until a Launch
## references it. Pure data — no SceneTree dependency, no per-frame
## state. SpawnDirector consumes both this and a Launch when the player
## confirms LAUNCH on the menu.

const UnitChassis = preload("res://scripts/unit_chassis.gd")
const UnitPart = preload("res://scripts/unit_part.gd")
const Satellite = preload("res://scripts/satellite.gd")
const LaserWeapon = preload("res://scripts/weapons/laser_weapon.gd")
const RailgunWeapon = preload("res://scripts/weapons/railgun_weapon.gd")
const Propulsion = preload("res://scripts/propulsion.gd")

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
var thruster_part_ids: Array[String] = []


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
	thruster_part_ids = _resize_part_ids(thruster_part_ids, UnitPart.KIND_THRUSTER)


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
		UnitPart.KIND_THRUSTER:
			return thruster_part_ids
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


# Sum of thrust across every thruster slot, in newtons. Empty / unknown
# parts contribute 0. SpawnDirector copies this onto Satellite.thrust_n.
func total_thrust_n() -> float:
	var total: float = 0.0
	for part_id in thruster_part_ids:
		total += UnitPart.get_by_id(part_id).thrust_n
	return total


# Sum of propellant-tank capacity across every thruster slot, in kg.
# Drives the satellite's max_propellant_kg / starting propellant_kg.
func total_propellant_capacity_kg() -> float:
	var total: float = 0.0
	for part_id in thruster_part_ids:
		total += UnitPart.get_by_id(part_id).propellant_capacity_kg
	return total


# Total mass (kg) of railgun ammo a fully-loaded unit ships with.
# Each filled railgun slot contributes MAGAZINE_SIZE × SLUG_MASS_KG;
# laser slots contribute zero. Surfaced separately from
# total_propellant_capacity_kg so the launch-cost path can include
# ammo in the booster's payload calculation without re-walking the
# weapon row.
func total_ammo_mass_kg() -> float:
	var total: float = 0.0
	for part_id in weapon_part_ids:
		var part := UnitPart.get_by_id(part_id)
		if part.weapon_class == UnitPart.WCLASS_RAILGUN:
			total += float(RailgunWeapon.MAGAZINE_SIZE) * RailgunWeapon.SLUG_MASS_KG
	return total


# Wet mass at launch: dry structure + propellant tank + ammo
# magazine. Used by the launch-cost path so the booster's
# rocket-equation propellant draw counts the railgun magazine — a
# 20 t magazine on a 1 t airframe is too big to silently ignore.
func wet_mass_kg() -> float:
	return (
		Satellite.DEFAULT_DRY_MASS_KG
		+ total_propellant_capacity_kg()
		+ total_ammo_mass_kg()
	)


# Capacity-weighted Isp across the unit's thruster slots. Mixing
# thrusters of different Isp is unusual but well-defined: a stage
# carrying a hydrolox + kerolox tank pair, burned in sequence, delivers
# the same propellant-weighted average as if mass-weighted. Returns 0
# (not NaN) when no thruster carries propellant — caller treats that
# as "this unit has no usable propulsion" and skips the burn cost
# gating entirely.
func effective_isp_s() -> float:
	var capacity_sum: float = 0.0
	var weighted: float = 0.0
	for part_id in thruster_part_ids:
		var p := UnitPart.get_by_id(part_id)
		capacity_sum += p.propellant_capacity_kg
		weighted += p.propellant_capacity_kg * p.isp_s
	if capacity_sum <= 0.0:
		return 0.0
	return weighted / capacity_sum


# Predicted satellite stats for the unit's current chassis + parts,
# returned as a Dictionary the Hangar tab's summary panel renders. The
# numbers here are the spec SpawnDirector implements: weapon damage
# scales on the weapon part's tier; cool rate (and therefore the
# weapon's cooldown duration) is supplied by the unit's radiator
# complement; energy_max / energy_rate scale on the storage / reactor
# rows. Units stay raw — the menu does its own formatting.
#
# Keys:
#   "hp"               — initial / max hit points
#   "mass_kg"          — wet mass: dry structure + onboard propellant
#                        (railgun recoil math reads this)
#   "dry_mass_kg"      — structural mass alone (Tsiolkovsky's m_f)
#   "laser_count"      — number of laser slots filled
#   "laser_dps_total"  — sum of laser damage_per_second at full pool
#   "laser_max_range"  — laser engagement ceiling, km
#   "laser_cooldown_sec" — sim-sec for an overheated laser to fully
#                          cool back to ready. INF when the unit has
#                          no radiator (the weapon could never recover).
#   "railgun_count"    — number of railgun slots filled
#   "railgun_damage_total"  — sum of per-shot damage across railguns
#   "railgun_cooldown_sec" — sim-sec between railgun shots. INF when
#                            the unit has no radiator.
#   "railgun_slug_mass_kg"      — mass of one slug
#   "railgun_muzzle_velocity_m_s" — slug exit velocity
#   "railgun_slug_ke_j"         — slug kinetic energy on exit
#                                  (½·m·v² — independent of damage scale)
#   "railgun_energy_per_shot_j" — joules drawn from the bus per shot
#                                  (slug KE / wall-plug efficiency)
#   "railgun_magazine_size"     — rounds per magazine (per gun)
#   "railgun_recoil_dv_ms"      — Δv (m/s) the shooter takes per shot
#                                  at full wet mass; recoil grows as
#                                  ammo depletes since mass shrinks
#   "railgun_target_coupling"   — fraction of slug KE that becomes
#                                  absorbed damage (default 0.5).
#                                  Momentum transfer is full Newton's-
#                                  third — the target gets the slug's
#                                  full momentum vector regardless of
#                                  this number.
#   "energy_storage"   — pool capacity, joules
#   "energy_production" — reactor output, watts (joules per sim-second)
#   "thrust_n"         — total thruster thrust in newtons
#   "isp_s"            — capacity-weighted specific impulse in seconds
#   "propellant_capacity_kg" — total propellant tank size, kg
#   "delta_v_capacity_ms" — Δv pool the unit can spend in-game, m/s
func summary_stats() -> Dictionary:
	var radiator_mult := total_multiplier_for_kind(UnitPart.KIND_RADIATOR)
	var storage_mult := total_multiplier_for_kind(UnitPart.KIND_ENERGY_STORAGE)
	var reactor_mult := total_multiplier_for_kind(UnitPart.KIND_REACTOR)

	var laser_count: int = 0
	var laser_dps_total: float = 0.0
	var railgun_count: int = 0
	var railgun_damage_total: float = 0.0
	for part_id in weapon_part_ids:
		var part := UnitPart.get_by_id(part_id)
		match part.weapon_class:
			UnitPart.WCLASS_LASER:
				laser_count += 1
				laser_dps_total += (
					LaserWeapon.base_damage_per_second_at_zero_range()
					* part.multiplier
				)
			UnitPart.WCLASS_RAILGUN:
				railgun_count += 1
				railgun_damage_total += (
					RailgunWeapon.base_damage_per_shot() * part.multiplier
				)

	# Cooldown duration is the inverse of the radiator-supplied cool
	# rate (per-class baseline × aggregate radiator multiplier). With
	# no radiator the rate is zero and the cooldown is infinite — the
	# weapon would fire once and never recover. Surface that directly
	# so the operator can't ship a unit whose guns can't sustain fire.
	var laser_cooldown: float = INF
	var railgun_cooldown: float = INF
	if radiator_mult > 0.0:
		laser_cooldown = 1.0 / (LaserWeapon.COOL_PER_SEC * radiator_mult)
		railgun_cooldown = 1.0 / (RailgunWeapon.COOL_PER_SEC * radiator_mult)

	# Propulsion summary: thrust (N), Isp (s), propellant capacity (kg),
	# and the resulting Δv pool (m/s) under Tsiolkovsky at the unit's
	# wet mass (DEFAULT_DRY_MASS_KG + propellant capacity). The Δv
	# number is the headline figure for the operator — same currency
	# the launch budget and per-unit maneuvers spend, so the menu can
	# render "this unit has 1200 m/s on tap" directly. Zero across all
	# four when the thruster row is empty / unknown.
	var thrust_n := total_thrust_n()
	var isp_s := effective_isp_s()
	var propellant_kg := total_propellant_capacity_kg()
	# Wet mass tracks the unit's actual launch mass: dry structure +
	# propellant + ammo. Ammo only contributes when a railgun slot is
	# filled (1000 rounds × 20 kg = 20 t, dwarfing the airframe), so
	# the menu's mass readout has to count it or the operator's "this
	# unit weighs X kg" reading will silently skip the magazine.
	var ammo_mass_kg: float = total_ammo_mass_kg()
	var wet_mass: float = (
		Satellite.DEFAULT_DRY_MASS_KG + propellant_kg + ammo_mass_kg
	)
	# Δv capacity is independent of ammo mass: Tsiolkovsky's m_f /
	# m_0 ratio is bound by dry vs. dry+propellant, and ammo doesn't
	# burn off during a thrust burn — it just sits there raising both
	# numerator and denominator equally. Operators read Δv to plan
	# orbital changes; they read mass to plan recoil.
	var dv_capacity_ms := Propulsion.dv_capacity_ms(
		propellant_kg, Satellite.DEFAULT_DRY_MASS_KG + ammo_mass_kg, isp_s
	)

	return {
		"hp": Satellite.MAX_HP,
		"mass_kg": wet_mass,
		"dry_mass_kg": Satellite.DEFAULT_DRY_MASS_KG,
		"laser_count": laser_count,
		"laser_dps_total": laser_dps_total,
		"laser_max_range": LaserWeapon.MAX_RANGE_KM,
		"laser_cooldown_sec": laser_cooldown,
		"railgun_count": railgun_count,
		"railgun_damage_total": railgun_damage_total,
		"railgun_cooldown_sec": railgun_cooldown,
		"railgun_slug_mass_kg": RailgunWeapon.SLUG_MASS_KG,
		"railgun_muzzle_velocity_m_s": RailgunWeapon.MUZZLE_VELOCITY_M_S,
		"railgun_slug_ke_j": RailgunWeapon.SLUG_MUZZLE_KE_J,
		"railgun_energy_per_shot_j": RailgunWeapon.ENERGY_PER_SHOT_J,
		"railgun_magazine_size": RailgunWeapon.MAGAZINE_SIZE,
		# Recoil at the unit's *current* full wet mass — what the operator
		# pays in Δv on the very first shot of an engagement. As the
		# magazine empties this number climbs (mass shrinks); the menu
		# only shows the full-load value since that's the floor.
		# RailgunWeapon.SLUG_MOMENTUM_KG_KM_S is in km/s, so multiply by
		# 1000 to land back in m/s for the operator's existing mental model.
		"railgun_recoil_dv_ms": (
			RailgunWeapon.SLUG_MOMENTUM_KG_KM_S * 1000.0 / wet_mass
			if wet_mass > 0.0 else 0.0
		),
		"railgun_target_coupling": RailgunWeapon.TARGET_COUPLING_DEFAULT,
		"energy_storage": Satellite.DEFAULT_ENERGY_MAX_J * storage_mult,
		"energy_production": Satellite.DEFAULT_REACTOR_POWER_W * reactor_mult,
		"thrust_n": thrust_n,
		"isp_s": isp_s,
		"propellant_capacity_kg": propellant_kg,
		"delta_v_capacity_ms": dv_capacity_ms,
	}


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
		UnitPart.KIND_THRUSTER,
	]:
		for part_id in part_ids_for_kind(kind):
			parts.append(UnitPart.get_by_id(part_id).label)
	return "%s · %s" % [chassis.label, " + ".join(parts)]
