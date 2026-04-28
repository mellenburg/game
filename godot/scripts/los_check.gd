class_name LosCheck
extends RefCounted
## Earth line-of-sight ray test. Pulled into its own RefCounted so the
## geometric core can be unit-tested without spinning up a SceneTree.

const EARTH_RADIUS_KM: float = 6371.0
const EARTH_RADIUS_SQ: float = EARTH_RADIUS_KM * EARTH_RADIUS_KM


## Returns true if the segment from `start` to `end` (km, ECI) intersects
## the Earth's bounding sphere — i.e. line of sight is blocked.
static func is_blocked(start: Vector3, end: Vector3) -> bool:
	var dir := end - start
	var a := dir.dot(dir)
	if a == 0.0:
		# Degenerate segment: blocked iff the point is inside the planet.
		return start.length_squared() < EARTH_RADIUS_SQ
	var b := 2.0 * dir.dot(start)
	var c := start.dot(start) - EARTH_RADIUS_SQ
	var discr := b * b - 4.0 * a * c
	if discr < 0.0:
		return false
	var sqrt_d := sqrt(discr)
	# Numerically stable quadratic roots.
	var q := -0.5 * (b + (sqrt_d if b >= 0.0 else -sqrt_d))
	var t0 := q / a
	var t1 := c / q if q != 0.0 else INF
	if t0 > t1:
		var tmp := t0; t0 = t1; t1 = tmp
	if t1 < 0.0:
		return false  # entire intersection is behind 'start'
	if t0 > 1.0:
		return false  # entire intersection is past 'end'
	# Some portion of [t0, t1] overlaps [0, 1]: blocked.
	return true
