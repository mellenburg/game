class_name AsteroidWave
extends RefCounted
## Pending asteroid wave: a shared entry nexus and a queue of pre-sampled
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
##   mass         : float, body mass in kg. Drives HP (10 kg = 1 HP),
##                  3D marker scale (mass^(1/3)), and radar blip size
##                  (mass^(2/3)). Defaults to Satellite.DEFAULT_MASS_KG
##                  when populate() is called without a mass band.
##   is_decaying  : bool, true if this spec should spawn as a decaying-
##                  orbit body (highly eccentric, perigee burns) rather
##                  than a sub-orbital asteroid. Decaying specs use
##                  their own random orbital plane and ignore the wave's
##                  shared nexus (r_hat / tangent / base_velocity); the
##                  lateral / alt / vel jitter fields are still sampled
##                  so the radar blip preview has a position to render.

const DEFAULT_BODY_MASS_KG: float = 1000.0

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

# Radar warning lead time (sim-seconds) the operator gets before each
# body actually enters play — every spec's `t` was sampled as
# (uniform-in-duration + warning_window_sec), so the body becomes
# visible on the radar exactly when t crosses below this value and
# scrolls down to t = 0 over `warning_window_sec` of sim-time.
# Set by SpawnDirector at wave creation time, read by RadarMap to
# decouple radar visibility from the spawn duration.
var warning_window_sec: float = 0.0


## Fill the queue with `count` independent pre-sampled per-body specs.
## Each spec carries an independent uniform spawn delay in
## [preroll, preroll + duration_sec], a uniform-angle / uniform-radius
## lateral offset inside `lateral_spread`, signed altitude jitter, and
## per-axis velocity jitter. `preroll` shifts every timer forward so
## the wave doesn't begin spawning until that many seconds have elapsed
## — the radar overlay uses the gap to scroll bodies in from above
## rather than painting the full distribution at once. Order is
## irrelevant; tick() walks the whole array each frame.
func populate(
	rng: RandomNumberGenerator,
	count: int,
	duration: float,
	lateral_spread: float,
	altitude_jitter: float,
	vel_jitter: float,
	preroll: float = 0.0,
) -> void:
	pending.clear()
	duration_sec = duration
	lateral_spread_km = lateral_spread
	for _i in range(count):
		var ang := rng.randf_range(0.0, TAU)
		var dist := rng.randf_range(0.0, lateral_spread)
		pending.append({
			"t": rng.randf_range(0.0, duration) + preroll,
			"lateral": Vector2(cos(ang) * dist, sin(ang) * dist),
			"alt_offset": rng.randf_range(-altitude_jitter, altitude_jitter),
			"vel_jitter": Vector3(
				rng.randf_range(-vel_jitter, vel_jitter),
				rng.randf_range(-vel_jitter, vel_jitter),
				rng.randf_range(-vel_jitter, vel_jitter),
			),
			"mass": DEFAULT_BODY_MASS_KG,
			"is_decaying": false,
		})


## Replace the queue with a pre-built list of specs. Used by the mixed
## wave path (size classes + decaying-orbit subset), where SpawnDirector
## composes the mass/decaying mix up front and just hands the wave the
## finished list. `duration` and `lateral_spread` are stored so the
## radar overlay can normalise blip positions without reaching back into
## the spawn director's constants.
func set_specs(
	specs: Array[Dictionary], duration: float, lateral_spread: float
) -> void:
	pending = specs
	duration_sec = duration
	lateral_spread_km = lateral_spread


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
