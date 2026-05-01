class_name MeteoriteWave
extends RefCounted
## Pending meteorite wave: a shared entry nexus and a queue of pre-sampled
## per-body specs (countdown timer + lateral offset + altitude jitter +
## velocity jitter). Each frame the owning system calls tick(delta) and
## spawns one body for every spec whose timer expired this frame, reusing
## the shared nexus parameters.
##
## Pre-sampling per-body randomness up front (rather than at spawn time)
## lets the radar overlay project pending bodies onto its 2-D screen
## before they enter play — the operator sees the same lateral spread
## the spawn will produce, not a fresh roll.
##
## Pure-state RefCounted so the timer logic is testable without a
## SceneTree. Construction is two-phase — set the nexus fields, then
## populate the queue — so the EarthSystem keeps ownership of random
## distributions.
##
## Per-body spec layout (Dictionary keys):
##   t            : float, seconds until spawn (decreases each tick)
##   lateral      : Vector2, in-plane offset (x along tangent, y along
##                  bitangent), in km. Magnitude <= lateral_spread_km.
##   alt_offset   : float, altitude jitter in km, signed
##   vel_jitter   : Vector3, per-axis velocity jitter in km/s

var pending: Array[Dictionary] = []
var r_hat: Vector3 = Vector3.ZERO
var tangent: Vector3 = Vector3.ZERO
var base_altitude: float = 0.0
var base_velocity: Vector3 = Vector3.ZERO

# Wave-shape metadata kept around so renderers (the radar overlay) can
# normalise per-body specs into [-1, 1] / [0, 1] screen space without
# reaching into EarthSystem's constants.
var duration_sec: float = 0.0
var lateral_spread_km: float = 0.0


## Fill the queue with `count` independent pre-sampled per-body specs.
## Each spec carries an independent uniform spawn delay in
## [0, duration_sec], a uniform-angle / uniform-radius lateral offset
## inside `lateral_spread`, signed altitude jitter, and per-axis velocity
## jitter. Order is irrelevant; tick() walks the whole array each frame.
func populate(
	rng: RandomNumberGenerator,
	count: int,
	duration: float,
	lateral_spread: float,
	altitude_jitter: float,
	vel_jitter: float,
) -> void:
	pending.clear()
	duration_sec = duration
	lateral_spread_km = lateral_spread
	for _i in range(count):
		var ang := rng.randf_range(0.0, TAU)
		var dist := rng.randf_range(0.0, lateral_spread)
		pending.append({
			"t": rng.randf_range(0.0, duration),
			"lateral": Vector2(cos(ang) * dist, sin(ang) * dist),
			"alt_offset": rng.randf_range(-altitude_jitter, altitude_jitter),
			"vel_jitter": Vector3(
				rng.randf_range(-vel_jitter, vel_jitter),
				rng.randf_range(-vel_jitter, vel_jitter),
				rng.randf_range(-vel_jitter, vel_jitter),
			),
		})


## Decrement every pending timer by `delta`; return the specs that
## crossed zero this tick (and remove them from the queue).
func tick(delta: float) -> Array[Dictionary]:
	var ready: Array[Dictionary] = []
	var i := 0
	while i < pending.size():
		var entry: Dictionary = pending[i]
		var t: float = float(entry["t"]) - delta
		if t <= 0.0:
			ready.append(entry)
			pending.remove_at(i)
		else:
			entry["t"] = t
			pending[i] = entry
			i += 1
	return ready


func is_complete() -> bool:
	return pending.is_empty()
