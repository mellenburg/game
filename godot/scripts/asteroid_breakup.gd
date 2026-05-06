class_name AsteroidBreakup
extends RefCounted
## Pure math for the asteroid breakup mechanic. No Node, no SceneTree —
## fully unit-testable. The caller (CombatController) owns the probability
## gate and the RNG seed; this class only handles momentum-conserving
## fragment distribution.
##
## Fragment assignment for N children:
##   k = 1 .. N-2  random mass fraction (0.5–1.0 × remaining), velocity
##                 direction deflected from the parent axis by a random
##                 angle ≤ deflection_rad, speed = |parent_velocity|.
##   k = N-1       random mass fraction (0.5–1.0 × remaining), velocity
##                 set so that the cumulative momentum of k = 1 .. N-1
##                 exactly equals the parent momentum (momentum-correction
##                 fragment). The "deflect from opposite of N-2" direction
##                 from the design spec informs the mass sampling context
##                 only; the actual velocity is determined by conservation.
##   k = N         remaining mass, velocity from whatever momentum is still
##                 outstanding after k = N-1's correction (zero after a
##                 single momentum-correction step, so this fragment is
##                 effectively at rest in the ECI frame and free-falls).
##
## Special cases:
##   N = 1 → single fragment inherits parent mass + velocity unchanged.
##   N = 2 → k=1 is deflected, k=2 is the momentum-balance fragment.
##            The N-1 special case is skipped (N-1 == 1, which is k=1).


## Compute N momentum-conserving fragment states from a parent body.
##
## parent_mass   kg, must be > 0.
## parent_velocity  km/s, in whatever frame the orbit uses (ECI km/s).
## n             number of fragments (≥ 1).
## deflection_rad  maximum half-angle deviation for fragments k = 1..N-2.
##                Must be ≥ 0.
## rng           caller-supplied RNG so tests can seed deterministically.
##
## Returns Array[Dictionary], one entry per fragment:
##   { "mass": float (kg), "velocity": Vector3 (km/s) }
##
## Invariants:
##   Σ mass_i   = parent_mass
##   Σ mass_i × velocity_i  = parent_mass × parent_velocity
static func compute_children(
	n: int,
	parent_mass: float,
	parent_velocity: Vector3,
	deflection_rad: float,
	rng: RandomNumberGenerator,
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if n <= 0 or parent_mass <= 0.0:
		return result

	if n == 1:
		result.append({"mass": parent_mass, "velocity": parent_velocity})
		return result

	var parent_speed: float = parent_velocity.length()
	var parent_dir: Vector3 = (
		parent_velocity / parent_speed
		if parent_speed > 1.0e-10
		else Vector3.FORWARD
	)

	var remaining_mass: float = parent_mass
	var remaining_momentum: Vector3 = parent_mass * parent_velocity
	var last_dir: Vector3 = parent_dir

	for k: int in range(1, n + 1):
		var mass: float
		var velocity: Vector3

		if k == n:
			# Last fragment: consume all remaining mass and leftover momentum.
			mass = remaining_mass
			velocity = (
				remaining_momentum / mass
				if mass > 1.0e-10
				else Vector3.ZERO
			)

		elif k == n - 1 and n >= 3:
			# Penultimate fragment: mass sampled normally; velocity overridden
			# to the exact vector that brings cumulative momentum = parent
			# momentum (so the final fragment receives zero net momentum).
			var frac: float = rng.randf_range(0.5, 1.0)
			mass = frac * remaining_mass
			velocity = (
				remaining_momentum / mass
				if mass > 1.0e-10
				else Vector3.ZERO
			)
			remaining_mass -= mass
			remaining_momentum -= mass * velocity
			# Track direction for N-1's "opposite of N-2" context even though
			# the velocity here is momentum-driven, not direction-driven.
			last_dir = (
				velocity.normalized()
				if velocity.length() > 1.0e-10
				else -last_dir
			)

		else:
			# Fragments k = 1 .. N-2: deflect from parent axis, keep speed.
			var frac: float = rng.randf_range(0.5, 1.0)
			mass = frac * remaining_mass
			var dir: Vector3 = _random_cone_direction(parent_dir, deflection_rad, rng)
			velocity = dir * parent_speed
			remaining_mass -= mass
			remaining_momentum -= mass * velocity
			last_dir = dir

		result.append({"mass": mass, "velocity": velocity})

	return result


## Rotate base_dir by a random angle drawn uniformly from the spherical cap
## of half-angle max_angle_rad. Cosine-weighted sampling in the polar
## direction ensures the distribution is uniform over solid angle (avoids
## the pole-clustering bias of naïve uniform-θ sampling).
static func _random_cone_direction(
	base_dir: Vector3,
	max_angle_rad: float,
	rng: RandomNumberGenerator,
) -> Vector3:
	if max_angle_rad <= 0.0:
		return base_dir.normalized()

	# Draw cos(θ) uniformly from [cos(max_angle), 1] — uniform over the cap.
	var cos_max: float = cos(max_angle_rad)
	var cos_theta: float = rng.randf_range(cos_max, 1.0)
	var sin_theta: float = sqrt(maxf(0.0, 1.0 - cos_theta * cos_theta))
	var phi: float = rng.randf_range(0.0, TAU)

	# Build an orthonormal frame with base_dir as the Z-axis. The cross
	# products are arbitrary in azimuth; phi covers the full circle so
	# the frame orientation doesn't matter.
	var bn: Vector3 = base_dir.normalized()
	var up: Vector3 = (
		Vector3.UP
		if abs(bn.dot(Vector3.UP)) < 0.9
		else Vector3.RIGHT
	)
	var x_axis: Vector3 = bn.cross(up).normalized()
	var y_axis: Vector3 = bn.cross(x_axis)  # Already unit: bn ⊥ x_axis, both unit.

	return (
		x_axis * (sin_theta * cos(phi))
		+ y_axis * (sin_theta * sin(phi))
		+ bn * cos_theta
	).normalized()
