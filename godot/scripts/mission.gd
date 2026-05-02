class_name Mission
extends RefCounted
## Pure-state wave scheduler driven by a player-edited ReconSettings.
## Each "wave" is a tight cluster of N wave-units of mixed size classes
## (small / medium / large); each wave-unit is one full meteorite-wave
## burst of objects whose count / decaying ratio / per-object size mix
## come from the relevant WaveUnitClass. Mission resolves the player's
## ranges (count / duration / delay) into concrete timestamps once at
## start so the schedule is stable across ticks; the controller walks
## the schedule and dispatches each entry to the spawn director.
##
## Live-edit policy: edits made while the mission is running queue for
## the *next* launch. Mission never re-reads its source ReconSettings
## after start(); EarthSystem rebuilds a fresh Mission from the latest
## settings when the player launches again.
##
## Pure RefCounted, no SceneTree dependency, so the timing logic is
## unit-tested directly.

const WaveUnitClass = preload("res://scripts/wave_unit_class.gd")
const WaveComposition = preload("res://scripts/wave_composition.gd")
const ReconSettings = preload("res://scripts/recon_settings.gd")

const STATE_IDLE: int = 0
const STATE_RUNNING: int = 1
const STATE_COMPLETE: int = 2

# Pre-built emission timeline. Each entry:
#   t             : float, absolute mission elapsed time at which this
#                   wave-unit fires.
#   wave_id       : int, index into the original wave list. Used by the
#                   controller to look up / cache a per-wave base nexus
#                   so every wave-unit in one wave clusters together.
#   first_in_wave : bool, true exactly once per wave (the earliest
#                   wave-unit). Lets the controller distinguish "fresh
#                   wave starting" from "another wave-unit in the
#                   ongoing wave".
#   size_class    : int, ReconSettings.SIZE_SMALL / MEDIUM / LARGE —
#                   the WaveUnitClass to drive object sampling for
#                   this wave-unit.
# Sorted by t. tick() walks it monotonically.
var _schedule: Array[Dictionary] = []
var _next_idx: int = 0
var elapsed: float = 0.0
var state: int = STATE_IDLE


# Resolve a ReconSettings into a concrete emission timeline and arm
# the scheduler. `rng` consumes count / duration / delay ranges and
# the wave-unit ordering shuffle; pass an explicit seeded RNG for
# reproducible tests, or omit it for a fresh randomization at runtime.
func start_from_settings(
	settings: ReconSettings, rng: RandomNumberGenerator = null
) -> void:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	_schedule.clear()
	_next_idx = 0
	elapsed = 0.0
	state = STATE_RUNNING
	if settings == null:
		return
	_build_schedule(settings, rng)


# Resolve every wave's per-wave-unit relative timings into absolute
# mission times. Within a wave, wave-units of different size classes
# are interleaved in random order so a "5 small / 3 medium / 2 large"
# wave doesn't always emit small-first then escalate; the player gets
# a more dynamic mix that still lands inside the same time window.
func _build_schedule(
	settings: ReconSettings, rng: RandomNumberGenerator
) -> void:
	var wave_start := 0.0
	for wi in range(settings.waves.size()):
		var w: WaveComposition = settings.waves[wi]
		wave_start += w.sample_delay(rng)
		var size_classes := _shuffled_size_class_list(w, rng)
		var n := size_classes.size()
		if n == 0:
			continue
		var duration := w.sample_duration(rng)
		var times := _resolve_wave_unit_times(n, duration, w.randomized, rng)
		# `times` is monotonic by construction (linspace for even,
		# sorted draw for randomised) — first emission is index 0.
		for i in range(n):
			_schedule.append({
				"t": wave_start + times[i],
				"wave_id": wi,
				"first_in_wave": i == 0,
				"size_class": size_classes[i],
			})


# Build the size-class array for a wave (small_units of SMALL, etc.)
# and shuffle in place so the arrival order isn't stratified by class.
func _shuffled_size_class_list(
	w: WaveComposition, rng: RandomNumberGenerator
) -> Array[int]:
	var out: Array[int] = []
	for _i in range(maxi(w.small_units, 0)):
		out.append(ReconSettings.SIZE_SMALL)
	for _i in range(maxi(w.medium_units, 0)):
		out.append(ReconSettings.SIZE_MEDIUM)
	for _i in range(maxi(w.large_units, 0)):
		out.append(ReconSettings.SIZE_LARGE)
	# Fisher-Yates against the supplied RNG keeps shuffle reproducible
	# under a seeded run; Array.shuffle() uses the global RNG.
	for i in range(out.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := out[i]
		out[i] = out[j]
		out[j] = tmp
	return out


# Pick the n relative timestamps for a wave's wave-units. Even mode:
# linearly spaced across [0, duration]. Random mode: n independent
# uniform draws, then sorted so the "first_in_wave" flag still
# corresponds to the earliest emission. A 1-unit wave fires at t=0.
func _resolve_wave_unit_times(
	n: int, duration: float, randomized: bool, rng: RandomNumberGenerator
) -> Array[float]:
	var out: Array[float] = []
	if n <= 0:
		return out
	if n == 1:
		out.append(0.0)
		return out
	if randomized:
		for _i in range(n):
			out.append(rng.randf_range(0.0, duration))
		out.sort()
	else:
		var step := duration / float(n - 1)
		for i in range(n):
			out.append(float(i) * step)
	return out


# Advance the mission clock and return any wave-unit emissions whose
# timestamp crossed `elapsed` this tick. Multiple wave-units can fire
# in one call when delta exceeds an inter-emission gap or the frame
# stalled — the loop drains every ready entry so we never silently
# drop one to a slow frame.
func tick(delta: float) -> Array[Dictionary]:
	var ready: Array[Dictionary] = []
	if state != STATE_RUNNING:
		return ready
	elapsed += delta
	while (
		_next_idx < _schedule.size()
		and elapsed >= float(_schedule[_next_idx]["t"])
	):
		ready.append(_schedule[_next_idx])
		_next_idx += 1
	return ready


# True once tick() has emitted every scheduled wave-unit. The
# controller combines this with "no in-flight meteorite waves + no
# living enemies" to decide that the mission has finally cleared.
func all_waves_spawned() -> bool:
	return _next_idx >= _schedule.size()


# Total emissions in the resolved schedule. Surfaced for HUD readouts
# and for the test suite — Mission resolves count/duration/delay
# ranges at start, so the number of wave-units is locked once the
# mission begins.
func total_wave_units() -> int:
	return _schedule.size()


func mark_complete() -> void:
	state = STATE_COMPLETE


func is_complete() -> bool:
	return state == STATE_COMPLETE
