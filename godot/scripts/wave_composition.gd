class_name WaveComposition
extends Resource
## One row in the campaign's wave list. Defines a single mission "wave"
## as a tight cluster of N wave-units of mixed size classes:
##   * `small_units` / `medium_units` / `large_units` — integer counts
##     of how many wave-units of each size class spawn in this wave.
##   * `duration_min` / `duration_max` — range from which the spawn
##     window is drawn at start. `randomized=false` distributes wave-
##     units evenly across the window; `true` draws each timestamp
##     uniformly inside it.
##   * `delay_min` / `delay_max` — range from which the gap to the
##     previous wave's first wave-unit is drawn. The first wave's
##     delay is measured from mission start.
##
## Pure data Resource, mutated by the Recon editor and consumed once at
## Mission.start to fix the schedule for the run. Per-spec, edits made
## while the mission is running don't re-roll — they queue for the next
## launch.

@export var small_units: int = 0
@export var medium_units: int = 0
@export var large_units: int = 0
@export var duration_min: float = 4.0
@export var duration_max: float = 4.0
@export var randomized: bool = false
@export var delay_min: float = 25.0
@export var delay_max: float = 25.0


func unit_count() -> int:
	return small_units + medium_units + large_units


# Sample a concrete duration in seconds. Equal min/max collapses to a
# constant; the floor at 0.001 keeps `_build_schedule`'s even-spacing
# division safe when the user explicitly authors a near-instant wave.
func sample_duration(rng: RandomNumberGenerator) -> float:
	var lo := minf(duration_min, duration_max)
	var hi := maxf(duration_min, duration_max)
	return maxf(rng.randf_range(lo, hi), 0.001)


func sample_delay(rng: RandomNumberGenerator) -> float:
	var lo := minf(delay_min, delay_max)
	var hi := maxf(delay_min, delay_max)
	return maxf(rng.randf_range(lo, hi), 0.0)


func clamp_unit_counts() -> void:
	small_units = maxi(small_units, 0)
	medium_units = maxi(medium_units, 0)
	large_units = maxi(large_units, 0)


func clamp_duration() -> void:
	duration_min = maxf(duration_min, 0.0)
	duration_max = maxf(duration_max, 0.0)
	if duration_min > duration_max:
		var tmp := duration_min
		duration_min = duration_max
		duration_max = tmp


func clamp_delay() -> void:
	delay_min = maxf(delay_min, 0.0)
	delay_max = maxf(delay_max, 0.0)
	if delay_min > delay_max:
		var tmp := delay_min
		delay_min = delay_max
		delay_max = tmp


func duplicate_composition() -> WaveComposition:
	var c := WaveComposition.new()
	c.small_units = small_units
	c.medium_units = medium_units
	c.large_units = large_units
	c.duration_min = duration_min
	c.duration_max = duration_max
	c.randomized = randomized
	c.delay_min = delay_min
	c.delay_max = delay_max
	return c
