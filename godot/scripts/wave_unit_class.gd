class_name WaveUnitClass
extends Resource
## One wave-unit "size class" (small / medium / large). Each class
## carries the parameters that govern what gets sampled when the spawn
## director materialises a wave-unit of that class:
##   * `count_min` / `count_max`  : range from which the per-unit
##                                  object count is drawn at spawn.
##                                  Equal min/max collapses to a fixed
##                                  count.
##   * `decaying_ratio_min/max`   : range from which the decaying-orbit
##                                  share is drawn (0.0 = none, 1.0 =
##                                  every object spirals in).
##   * `size_small/medium/large`  : barycentric weights summing to 1.0
##                                  governing how the wave-unit's
##                                  objects split across small / medium
##                                  / large mass bands. (Distinct from
##                                  the *wave-unit's* own size class —
##                                  a "large wave-unit" can still be
##                                  composed mostly of small objects.)
##
## Pure data Resource so the Recon editor can mutate fields in place
## and the spawn path consumes them at sample time. Fields are kept on
## one Resource (rather than three separate range objects) to keep the
## inspector / save-shape flat.

# Range bounds enforced by the editor. Floor at 1 because a wave-unit
# with zero objects has no meaningful effect; cap at 50 — above that
# a single wave-unit's burst overwhelms the satellite container fast
# enough that frame pacing suffers (and the per-wave 250-object cap
# in Mission gates aggregate damage anyway).
const COUNT_MIN: int = 1
const COUNT_MAX: int = 50

# Spatial spread of a wave-unit's objects, expressed as the arc
# (degrees) along an equatorial slice of the sky over which they
# scatter. 15° = a tight cluster (the legacy default); 180° = bodies
# arrive from anywhere on the entry hemisphere. The minimum is
# non-zero so even a "no spread" tuning still has visible variation;
# all-zero spread would have every body in a wave-unit at one point.
const ARC_MIN_DEG: float = 15.0
const ARC_MAX_DEG: float = 180.0

# Temporal spread, in *game-time minutes*, over which a wave-unit's
# objects appear in play. Independent of the radar preroll — that lead
# time is added on top so the radar overlay has the same window to
# scroll incoming blips into view regardless of how short the spawn
# burst itself is. Minutes (rather than seconds) because the spawn
# director's wave tick advances in sim-seconds and a 1-second burst
# at the default time_factor compresses into a few wall-clock ms;
# minutes give the editor a natural scale to author meaningful spread.
const TIME_SPREAD_MIN_MIN: float = 1.0
const TIME_SPREAD_MAX_MIN: float = 60.0
const SECONDS_PER_MINUTE: float = 60.0

@export var count_min: int = 20
@export var count_max: int = 20
@export var decaying_ratio_min: float = 0.2
@export var decaying_ratio_max: float = 0.4
@export var size_small: float = 0.7
@export var size_medium: float = 0.25
@export var size_large: float = 0.05
@export var location_arc_deg: float = 30.0
@export var time_spread_min: float = 10.0


# Sample a concrete object count for one wave-unit instance. Range
# convention: [count_min, count_max] inclusive; equal min/max yields
# the constant value.
func sample_count(rng: RandomNumberGenerator) -> int:
	var lo := mini(count_min, count_max)
	var hi := maxi(count_min, count_max)
	return rng.randi_range(lo, hi)


# Sample a decaying-orbit ratio in [decaying_ratio_min, decaying_ratio_max].
# Caller multiplies by the sampled count and rounds to get the integer
# decaying-body slot count.
func sample_decaying_ratio(rng: RandomNumberGenerator) -> float:
	var lo := minf(decaying_ratio_min, decaying_ratio_max)
	var hi := maxf(decaying_ratio_min, decaying_ratio_max)
	return rng.randf_range(lo, hi)


# Allocate `count` objects into (small, medium, large) integer counts
# from the barycentric weights. Uses largest-remainder rounding so the
# three integers always sum to `count` exactly — naive `round(count *
# w)` can over- or under-count by up to 1 each, leaving gaps in the
# spec list the spawn director would otherwise fail to fill.
func sample_object_size_counts(count: int) -> Dictionary:
	var weights: Array[float] = normalized_weights()
	var raw: Array[float] = [
		float(count) * weights[0],
		float(count) * weights[1],
		float(count) * weights[2],
	]
	var floors: Array[int] = [int(raw[0]), int(raw[1]), int(raw[2])]
	var remainder: int = count - (floors[0] + floors[1] + floors[2])
	# Largest-remainder: hand the leftover units to whichever weights
	# had the biggest fractional part. Stable tie-break by lower index
	# (we sort descending on fractional part; equal fracs preserve
	# original order via the indexed pairs).
	var fracs: Array = [
		[raw[0] - float(floors[0]), 0],
		[raw[1] - float(floors[1]), 1],
		[raw[2] - float(floors[2]), 2],
	]
	fracs.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	for i in range(remainder):
		var idx: int = int(fracs[i][1])
		floors[idx] += 1
	return {"small": floors[0], "medium": floors[1], "large": floors[2]}


# Normalised (s, m, l) tuple. Always sums to 1.0; if all three weights
# are zero we fall back to even thirds so the editor can't hand the
# spawner a degenerate (0, 0, 0) and starve the wave-unit.
func normalized_weights() -> Array[float]:
	var s := maxf(size_small, 0.0)
	var m := maxf(size_medium, 0.0)
	var l := maxf(size_large, 0.0)
	var total := s + m + l
	if total <= 0.0:
		return [1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0]
	return [s / total, m / total, l / total]


# In-place barycentric clamp. Clears negatives and rescales so the
# three weights sum to 1.0. Called by the editor after a triangle-
# picker drag to keep the stored values consistent with what the user
# sees.
func normalize_weights_in_place() -> void:
	var n := normalized_weights()
	size_small = n[0]
	size_medium = n[1]
	size_large = n[2]


# Clamp count_min <= count_max into the allowed band. Called by the
# range-slider after a drag; the slider tracks the two handles
# independently and we tidy on commit.
func clamp_count_range() -> void:
	count_min = clampi(count_min, COUNT_MIN, COUNT_MAX)
	count_max = clampi(count_max, COUNT_MIN, COUNT_MAX)
	if count_min > count_max:
		var tmp := count_min
		count_min = count_max
		count_max = tmp


func clamp_decaying_range() -> void:
	decaying_ratio_min = clampf(decaying_ratio_min, 0.0, 1.0)
	decaying_ratio_max = clampf(decaying_ratio_max, 0.0, 1.0)
	if decaying_ratio_min > decaying_ratio_max:
		var tmp := decaying_ratio_min
		decaying_ratio_min = decaying_ratio_max
		decaying_ratio_max = tmp


func clamp_location_arc() -> void:
	location_arc_deg = clampf(location_arc_deg, ARC_MIN_DEG, ARC_MAX_DEG)


func clamp_time_spread() -> void:
	time_spread_min = clampf(
		time_spread_min, TIME_SPREAD_MIN_MIN, TIME_SPREAD_MAX_MIN
	)


# Sim-second view of the spread for spawn director consumption — the
# wave timers tick in sim-seconds, so the editor's minute value gets
# multiplied here at the boundary.
func time_spread_sec() -> float:
	return time_spread_min * SECONDS_PER_MINUTE


# Approximate lateral spread in km equivalent to the configured arc,
# given the wave-unit's spawn altitude. SpawnDirector hands MeteoriteWave
# this value so the existing tangent / bitangent body placement keeps
# working unchanged. altitude * sin(arc/2) gives the chord half-length
# the arc subtends; for arc=180° this maxes at the full altitude (so
# bodies wrap across a full hemisphere's worth of sky), for arc=15° it
# matches the legacy ~6500 km cluster radius.
func lateral_spread_for_altitude(altitude_km: float) -> float:
	var rad: float = deg_to_rad(location_arc_deg) * 0.5
	return absf(altitude_km) * sin(rad)


# Default factory for the three wave-unit class progression. Tunes
# escalate in object count, decaying share, and heavy-object weight as
# you move alpha → beta → gamma — alpha reads as "scattered fast
# impactors", beta as "mixed bag with some decaying threats", gamma as
# "heavyweight assault with lots of decaying spirals". The Greek
# names disambiguate them from the *object* mass bands (small / medium
# / large) that drive composition inside a single wave-unit.
# Spread defaults run inversely to size: alpha is the "scattered
# swarm" archetype (broad arc, slow drip), gamma is the "tight strike"
# archetype (narrow arc, sharp burst). Counts and decaying share
# still escalate alpha → gamma so the heavyweight class stays the
# bigger threat per wave-unit even though it takes up less sky.
static func default_alpha() -> WaveUnitClass:
	var c := WaveUnitClass.new()
	c.count_min = 3
	c.count_max = 5
	c.decaying_ratio_min = 0.0
	c.decaying_ratio_max = 0.20
	c.size_small = 0.80
	c.size_medium = 0.15
	c.size_large = 0.05
	c.location_arc_deg = 120.0
	c.time_spread_min = 25.0
	return c


static func default_beta() -> WaveUnitClass:
	var c := WaveUnitClass.new()
	c.count_min = 4
	c.count_max = 6
	c.decaying_ratio_min = 0.20
	c.decaying_ratio_max = 0.35
	c.size_small = 0.45
	c.size_medium = 0.40
	c.size_large = 0.15
	c.location_arc_deg = 60.0
	c.time_spread_min = 20.0
	return c


static func default_gamma() -> WaveUnitClass:
	var c := WaveUnitClass.new()
	c.count_min = 5
	c.count_max = 8
	c.decaying_ratio_min = 0.40
	c.decaying_ratio_max = 0.60
	c.size_small = 0.20
	c.size_medium = 0.40
	c.size_large = 0.40
	c.location_arc_deg = 25.0
	c.time_spread_min = 15.0
	return c


func duplicate_class() -> WaveUnitClass:
	var c := WaveUnitClass.new()
	c.count_min = count_min
	c.count_max = count_max
	c.decaying_ratio_min = decaying_ratio_min
	c.decaying_ratio_max = decaying_ratio_max
	c.size_small = size_small
	c.size_medium = size_medium
	c.size_large = size_large
	c.location_arc_deg = location_arc_deg
	c.time_spread_min = time_spread_min
	return c
