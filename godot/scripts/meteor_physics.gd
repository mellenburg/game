class_name MeteorPhysics
extends RefCounted
## Game-side meteor physics: atmospheric burn-up threshold, density
## sampling, HP-from-mass formula, and the three damage-radius bands
## (light / moderate / heavy) that drive both the 3D impact explosion
## and the impact-map overlay.
##
## Pure RefCounted so the math is unit-testable headlessly. Real-world
## research is summarised in docs/asteroid_facts.md; the constants
## below are tuned from that research, but the formulas are
## game-loose: blast radii scale as the cube root of mass (which falls
## out of constant-velocity kinetic energy * constant blast-energy
## density), with coefficients calibrated against:
##   * Tunguska (~1 Tg): ~25 km flatten radius -> moderate band ~60 km
##   * Didymos (~500 Tg): heavy-damage radius ~150 km, light ~1100 km
##   * Chicxulub-class (Pg+): country-to-continent annihilation
##
## Below the burn-up threshold (10 metric tons / 10 Mg / 1e4 kg) bodies
## are treated as fully ablating in the atmosphere and never produce
## a recorded surface impact. EarthSystem._record_meteorite_impact
## reads `is_burn_up()` to gate that branch.

# Below this mass (kg) a body is assumed to fully burn up in the
# atmosphere and reach the ground only as harmless dust. Real-world
# threshold for retaining cosmic velocity through atmospheric entry
# is around 10^4 kg (10 metric tons / 10 Mg). Bodies below this floor
# are still simulated to a notional surface "impact" point so the
# Keplerian propagator's surface-cross logic stays uniform, but the
# game records no damage and paints no map marker.
const BURN_UP_THRESHOLD_KG: float = 1.0e4

# Mass bands in kg. Resized from the legacy 100-10000 kg range to
# meaningful asteroid scales:
#   small:  10 Mg .. 10 Gg   (sub-Tunguska, city-block-class threats)
#   medium: 10 Gg .. 10 Tg   (Tunguska to small-region-class)
#   large:  10 Tg .. 500 Tg  (Didymos to regional-annihilation class)
# Bands are non-overlapping at the boundaries so a body's class is a
# function of where its mass was sampled, not an independent label.
const SMALL_MASS_MIN_KG: float = 1.0e4
const SMALL_MASS_MAX_KG: float = 1.0e7
const MEDIUM_MASS_MIN_KG: float = 1.0e7
const MEDIUM_MASS_MAX_KG: float = 1.0e10
const LARGE_MASS_MIN_KG: float = 1.0e10
const LARGE_MASS_MAX_KG: float = 5.0e11

# HP-from-mass coefficient. HP = HP_PER_KG_PER_DENSITY * mass * density,
# so a 10 Mg stony (~3.4 g/cm^3) body has ~1000 HP and a 1 Tg stony
# Tunguska-class body has ~10^7 HP — comfortably beyond what a single
# laser can chew through in flight, by design. Tuned downward from a
# naive 0.1 HP/kg so the smallest-band bodies stay killable in-flight.
const HP_PER_KG_PER_DENSITY: float = 0.003

# Composition classes, modeled on the dominant asteroid taxonomic
# bins. Densities are bulk values in g/cm^3, ranges drawn from the
# meteoritics literature (carbonaceous chondrites, ordinary
# chondrites, stony-iron, iron). Weights approximate the near-Earth
# population: stony dominates; iron is rare but heavy.
const COMP_C_TYPE: int = 0     # carbonaceous chondrite (~15%)
const COMP_S_TYPE: int = 1     # stony / ordinary chondrite (~70%)
const COMP_SI_TYPE: int = 2    # stony-iron (~10%)
const COMP_M_TYPE: int = 3     # iron (~5%)

const COMP_NAMES: Array[String] = ["C-type", "S-type", "Stony-iron", "M-type"]

# (weight, density_min, density_max) per class. Densities in g/cm^3.
const COMP_TABLE: Array = [
	[0.15, 1.6, 2.5],   # carbonaceous
	[0.70, 3.0, 4.0],   # stony
	[0.10, 4.5, 6.5],   # stony-iron
	[0.05, 7.0, 8.0],   # iron
]

# Damage-radius coefficients (km / kg^(1/3)). Three concentric tiers:
#   heavy:    near-instant lethality / vaporisation zone
#   moderate: severe blast / structural collapse zone
#   light:    overpressure, broken windows, second-degree burns
# Cube-root-of-mass scaling matches a constant-velocity kinetic-energy
# model where blast volume tracks energy linearly. Coefficients tuned
# so a 1 Tg Tunguska impact yields heavy ~20 km, moderate ~60 km,
# light ~150 km — close to the observed ~25 km flatten radius and
# ~100 km felt radius of the historical event.
const HEAVY_RADIUS_COEFF: float = 0.020
const MODERATE_RADIUS_COEFF: float = 0.060
const LIGHT_RADIUS_COEFF: float = 0.150

# Damage tiers reported by `damage_tier_for_mass` — a coarse "what
# does this impact look like on the world map?" classifier the impact
# map and explosion code use to decide which circles to draw.
const TIER_NONE: int = 0       # body burned up — no impact recorded
const TIER_LIGHT: int = 1      # outer yellow circle only (smallest visible dot)
const TIER_MODERATE: int = 2   # yellow + orange visible
const TIER_HEAVY: int = 3      # all three circles visible


## True when a body of this mass burns up in the atmosphere and
## should not produce a recorded impact on the surface map.
static func is_burn_up(mass_kg: float) -> bool:
	return mass_kg < BURN_UP_THRESHOLD_KG


## HP for a given mass and density. `density_g_cm3` is the body's
## bulk density; HP scales linearly with both mass and density so an
## iron rock soaks more shots than a carbonaceous one of the same
## mass.
static func hp_for(mass_kg: float, density_g_cm3: float) -> float:
	return HP_PER_KG_PER_DENSITY * maxf(mass_kg, 0.0) * maxf(density_g_cm3, 0.0)


## Inverse of `hp_for`: the mass corresponding to a given HP and
## density. Used by the live-damage path on Satellite to keep
## meteorite mass coupled to HP — chip away an asteroid's hit points
## and its physical mass shrinks proportionally, which feeds back
## into impact damage radius (smaller) and railgun deflection
## efficiency (larger Δv per slug as the rock gets lighter).
## Returns 0.0 when density is non-positive so a misconfigured body
## doesn't divide by zero.
static func mass_for_hp(hp: float, density_g_cm3: float) -> float:
	if density_g_cm3 <= 0.0 or HP_PER_KG_PER_DENSITY <= 0.0:
		return 0.0
	return maxf(hp, 0.0) / (HP_PER_KG_PER_DENSITY * density_g_cm3)


## Damage radii in km for an impactor of the given mass. Returns a
## dictionary with keys "light", "moderate", "heavy" — all three are
## populated regardless of tier so callers can decide which to render.
## Cube-root scaling means a 1000x mass increase grows radii by 10x.
static func damage_radii_km(mass_kg: float) -> Dictionary:
	var m := maxf(mass_kg, 0.0)
	var cbrt := pow(m, 1.0 / 3.0)
	return {
		"light": LIGHT_RADIUS_COEFF * cbrt,
		"moderate": MODERATE_RADIUS_COEFF * cbrt,
		"heavy": HEAVY_RADIUS_COEFF * cbrt,
	}


## Coarse damage tier for the impact map's drawing logic. Bodies
## below the burn-up threshold get TIER_NONE and should be skipped
## entirely. Above that, the tier escalates with mass: small bodies
## just above the threshold get TIER_LIGHT (a single yellow dot),
## medium bodies show all three rings stacked.
static func damage_tier_for_mass(mass_kg: float) -> int:
	if is_burn_up(mass_kg):
		return TIER_NONE
	# Tier thresholds chosen so the lightest visible impacts paint a
	# yellow-only marker, Tunguska-scale impacts include the orange
	# moderate ring, and Tg+ class impacts paint all three.
	if mass_kg >= 1.0e8:
		return TIER_HEAVY
	if mass_kg >= 1.0e6:
		return TIER_MODERATE
	return TIER_LIGHT


## Sample a composition class index using the COMP_TABLE weights.
static func sample_composition(rng: RandomNumberGenerator) -> int:
	var roll := rng.randf()
	var acc := 0.0
	for i in range(COMP_TABLE.size()):
		acc += float(COMP_TABLE[i][0])
		if roll <= acc:
			return i
	return COMP_TABLE.size() - 1


## Sample a bulk density in g/cm^3 for the given composition class.
static func sample_density_for_composition(
	rng: RandomNumberGenerator, comp: int
) -> float:
	var idx := clampi(comp, 0, COMP_TABLE.size() - 1)
	var lo := float(COMP_TABLE[idx][1])
	var hi := float(COMP_TABLE[idx][2])
	return rng.randf_range(lo, hi)


## Convenience: sample a (composition, density) pair in one call.
static func sample_density(rng: RandomNumberGenerator) -> Dictionary:
	var comp := sample_composition(rng)
	return {
		"composition": comp,
		"density": sample_density_for_composition(rng, comp),
	}


## Human-readable name for a composition class. Used by HUD readouts
## and the impact-map latest-impact panel.
static func composition_name(comp: int) -> String:
	if comp < 0 or comp >= COMP_NAMES.size():
		return "unknown"
	return COMP_NAMES[comp]
