class_name Mission
extends RefCounted
## Pure-state wave scheduler for the MVP campaign mission. The mission
## defines a sequence of "waves"; each wave is a tight cluster of N
## "wave-units", where one wave-unit is a single 20-body meteorite wave
## (i.e. the same shape the I keybind triggers). EarthSystem walks the
## emissions this scheduler produces and hands each one to SpawnDirector
## as one fresh meteorite wave, sharing a per-wave entry direction so
## the cluster lands inside one solid-angle patch of the sky.
##
## Each wave's `delay_after_prev_start` is measured from when the
## previous wave's first wave-unit fired, not from when its last one
## landed. So an 8-unit / 0.5 s spacing wave (3.5 s of emissions)
## followed by a wave with delay_after_prev_start=30 starts 30 s after
## the previous wave's first wave-unit, leaving ~26.5 s of breathing
## room between the last wave-unit of wave N and the first of N+1.
##
## start() pre-builds the full emission timeline so the schedule is
## stable across ticks (randomized waves resolve their timestamps
## once at start, not on every tick). RefCounted, no SceneTree
## dependency, so the timing logic is unit-tested directly.

const STATE_IDLE: int = 0
const STATE_RUNNING: int = 1
const STATE_COMPLETE: int = 2

# Wave definition Dictionary keys:
#   delay_after_prev_start : float, seconds from the previous wave's
#                            first wave-unit emission to this wave's.
#                            The first wave's value is measured from
#                            start().
#   count                  : int, number of wave-units in this wave.
#   spacing                : float, seconds between consecutive wave-
#                            units (only used when randomized=false).
#   randomized             : bool, true → wave-unit timers drawn
#                            uniformly across [0, random_duration],
#                            false → unit i fires at i * spacing.
#   random_duration        : float, randomized window length.
var waves: Array[Dictionary] = []
var elapsed: float = 0.0
var state: int = STATE_IDLE

# Pre-built emission timeline produced at start(). Each entry:
#   t             : float, absolute mission elapsed time at which this
#                   wave-unit fires.
#   wave_id       : int, index into `waves`. Used by the controller to
#                   look up / cache a per-wave base nexus direction so
#                   every wave-unit in the same wave clusters together.
#   first_in_wave : bool, true exactly once per wave (the earliest
#                   wave-unit). Lets the controller distinguish "fresh
#                   wave starting" from "another wave-unit in the
#                   ongoing wave" without scanning history.
# Sorted by t. tick() walks it monotonically.
var _schedule: Array[Dictionary] = []
var _next_idx: int = 0


# Build the MVP mission's wave schedule. Five waves, each a cluster of
# meteorite-wave wave-units; difficulty escalates by wave-unit count
# and tightens by wave-unit spacing as the mission progresses, with
# the final wave arriving as a randomized burst rather than a metronome.
static func default_mission() -> Mission:
	var m := Mission.new()
	m.waves = [
		{
			"delay_after_prev_start": 3.0,
			"count": 3, "spacing": 1.0, "randomized": false,
		},
		{
			"delay_after_prev_start": 25.0,
			"count": 5, "spacing": 1.0, "randomized": false,
		},
		{
			"delay_after_prev_start": 25.0,
			"count": 8, "spacing": 0.5, "randomized": false,
		},
		{
			"delay_after_prev_start": 30.0,
			"count": 10, "spacing": 0.5, "randomized": false,
		},
		{
			"delay_after_prev_start": 30.0,
			"count": 10, "randomized": true, "random_duration": 4.0,
		},
	]
	return m


# Resolve the mission to a concrete emission timeline and arm the
# scheduler. Randomized waves consume `rng` to fix their per-wave-unit
# timestamps once at start; deterministic waves don't touch `rng` at
# all. Pass an explicit RNG to make the schedule reproducible (tests);
# omit it for a fresh randomization.
func start(rng: RandomNumberGenerator = null) -> void:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	_build_schedule(rng)
	state = STATE_RUNNING
	elapsed = 0.0
	_next_idx = 0


# Resolve every wave's per-wave-unit relative timings into absolute
# mission times. Randomized waves sort their drawn times so
# `first_in_wave` reliably tags the earliest emission. Deterministic
# waves are already in order. Across waves the timeline is sorted by
# construction because each `wave_start` is strictly later than the
# previous wave's last emission (the design constants leave at least
# ~26 s of gap between wave N's last unit and wave N+1's first).
func _build_schedule(rng: RandomNumberGenerator) -> void:
	_schedule.clear()
	var wave_start := 0.0
	for wi in range(waves.size()):
		var w: Dictionary = waves[wi]
		wave_start += float(w.get("delay_after_prev_start", 0.0))
		var count := int(w.get("count", 0))
		if count <= 0:
			continue
		var times: Array[float] = []
		if bool(w.get("randomized", false)):
			var dur := float(w.get("random_duration", 0.0))
			for _i in range(count):
				times.append(rng.randf_range(0.0, dur))
			times.sort()
		else:
			var spacing := float(w.get("spacing", 1.0))
			for i in range(count):
				times.append(float(i) * spacing)
		for i in range(count):
			_schedule.append({
				"t": wave_start + times[i],
				"wave_id": wi,
				"first_in_wave": i == 0,
			})


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


func mark_complete() -> void:
	state = STATE_COMPLETE


func is_complete() -> bool:
	return state == STATE_COMPLETE
