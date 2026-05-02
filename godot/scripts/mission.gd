class_name Mission
extends RefCounted
## Pure-state wave scheduler for the MVP campaign mission. Holds a list
## of wave definitions and an elapsed real-time clock; each tick(delta)
## returns the wave specs that crossed their start threshold this frame.
## EarthSystem feeds those specs to SpawnDirector.start_mission_wave so
## the actual MeteoriteWave bodies are generated lazily — Mission itself
## owns no scene state and never touches the satellite list.
##
## Each wave's `delay_after_prev_start` is measured from when the
## previous wave began emitting its first body, not from when its last
## body landed. So a wave with 8 bodies at 0.5 s spacing (3.5 s total
## emission) followed by a wave with delay_after_prev_start=30 starts
## 30 s after the previous wave's first body, leaving ~26.5 s of
## breathing room between the last body of wave N and the first of N+1.
##
## Pure RefCounted so the timing can be unit-tested without a SceneTree.
## Built once per mission start; the scheduler is single-shot — once
## every wave has fired, all_waves_spawned() returns true and the
## controller is responsible for transitioning the mission to complete
## once the playfield clears (the mission has no view onto living
## satellites and so cannot detect "all enemies destroyed" itself).

const STATE_IDLE: int = 0
const STATE_RUNNING: int = 1
const STATE_COMPLETE: int = 2

# Wave definition Dictionary keys:
#   delay_after_prev_start : float, seconds from the previous wave's
#                            spawn-trigger to this wave's. The first
#                            wave's value is measured from start().
#   count                  : int, number of wave units to spawn.
#   spacing                : float, seconds between consecutive units
#                            (only used when randomized=false).
#   randomized             : bool, true → unit timers are drawn
#                            uniformly across [0, random_duration],
#                            false → unit i fires at i * spacing.
#   random_duration        : float, window for randomized waves only.
var waves: Array[Dictionary] = []
var elapsed: float = 0.0
var state: int = STATE_IDLE

# Cursor into `waves`: index of the next wave that has not yet been
# emitted by tick(). When this reaches waves.size(), all waves have
# been handed off to the spawn director.
var _next_wave_idx: int = 0
# Absolute mission-elapsed time at which `_next_wave_idx` should fire.
# Recomputed when each wave fires by adding the next wave's
# delay_after_prev_start. Sentinel INF when no more waves remain.
var _next_wave_at: float = 0.0


# Build the MVP mission's wave schedule. Pulled out as a class function
# so the scheduler is reusable for tests / future stage variants without
# duplicating the cumulative-delay layout.
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


func start() -> void:
	state = STATE_RUNNING
	elapsed = 0.0
	_next_wave_idx = 0
	if waves.is_empty():
		_next_wave_at = INF
	else:
		_next_wave_at = float(waves[0].get("delay_after_prev_start", 0.0))


# Advance the mission clock and return any wave definitions that should
# be handed to the spawn director this tick. Multiple waves can fire in
# the same tick if delta is very large or two waves are scheduled close
# together — the loop drains every ready wave so we never silently drop
# one because the frame was slow.
func tick(delta: float) -> Array[Dictionary]:
	var ready: Array[Dictionary] = []
	if state != STATE_RUNNING:
		return ready
	elapsed += delta
	while _next_wave_idx < waves.size() and elapsed >= _next_wave_at:
		ready.append(waves[_next_wave_idx])
		_next_wave_idx += 1
		if _next_wave_idx < waves.size():
			_next_wave_at += float(
				waves[_next_wave_idx].get("delay_after_prev_start", 0.0)
			)
		else:
			_next_wave_at = INF
	return ready


# True once tick() has emitted every defined wave. The controller
# combines this with "no living enemies + no in-flight wave bodies" to
# decide that the mission is finally over.
func all_waves_spawned() -> bool:
	return _next_wave_idx >= waves.size()


func mark_complete() -> void:
	state = STATE_COMPLETE


func is_complete() -> bool:
	return state == STATE_COMPLETE
