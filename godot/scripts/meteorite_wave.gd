class_name MeteoriteWave
extends RefCounted
## Pending meteorite wave: a shared entry nexus and a queue of countdown
## timers for the bodies that haven't spawned yet. Each frame the owning
## system calls tick(delta) and spawns one body for every timer that
## expired this frame, reusing the shared nexus parameters.
##
## Pure-state RefCounted so the timer logic is testable without a
## SceneTree. Construction is two-phase — set the nexus fields, then
## populate the timer queue — so the EarthSystem keeps ownership of
## random distributions.

var pending_times: Array[float] = []
var r_hat: Vector3 = Vector3.ZERO
var tangent: Vector3 = Vector3.ZERO
var base_altitude: float = 0.0
var base_velocity: Vector3 = Vector3.ZERO


## Fill the queue with `count` independent uniformly-distributed spawn
## delays in [0, duration_sec]. Order is irrelevant; tick() walks the
## whole array each frame.
func populate_random_times(
	rng: RandomNumberGenerator, count: int, duration_sec: float
) -> void:
	pending_times.clear()
	for _i in range(count):
		pending_times.append(rng.randf_range(0.0, duration_sec))


## Decrement every pending timer by `delta`; return how many crossed
## zero this tick (and remove them from the queue).
func tick(delta: float) -> int:
	var ready := 0
	var i := 0
	while i < pending_times.size():
		var t: float = pending_times[i] - delta
		if t <= 0.0:
			ready += 1
			pending_times.remove_at(i)
		else:
			pending_times[i] = t
			i += 1
	return ready


func is_complete() -> bool:
	return pending_times.is_empty()
