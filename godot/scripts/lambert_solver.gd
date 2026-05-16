class_name LambertSolver
extends RefCounted
## Lambert's problem: given two position vectors and a time of flight,
## find the velocity vectors of a conic arc connecting them. Pure
## RefCounted so the math can be unit-tested headlessly.
##
## Algorithm: Vallado universal-variable Lambert with bisection on
## psi = xi^2 / alpha (Vallado, "Fundamentals of Astrodynamics and
## Applications", 4th ed., Algorithm 5.2). Universal variables match
## the existing MassCenterOrbit propagator's style and stay numerically
## stable across elliptic, parabolic, and hyperbolic transfer regimes.
## Reuses MassCenterOrbit.c2 / c3 Stumpff functions and MU default.
##
## Used by MissileWeapon to compute single-burn intercept trajectories.
## Returns dict results rather than throwing on failure; CombatController-
## scale loops must not raise.
##
## The 180-degree transfer (Δν = π exactly) is degenerate — the
## transfer plane is undefined since r1 × r2 = 0. We detect this and
## return ok=false rather than guess a plane. In practice the
## intercept-search wrapper samples multiple TOFs, so a single
## degenerate TOF is harmless — neighbouring TOFs almost always
## resolve.

const MassCenterOrbit = preload("res://scripts/mass_center_orbit.gd")

# Bisection loop ceiling. Vallado quotes 10-20 iterations as typical
# for ordinary transfers; 100 covers pathological geometries (very
# short or very long TOF near the parabolic boundary) without giving
# the solver a chance to spin forever.
const MAX_ITER: int = 100
# Time-of-flight residual tolerance (seconds). 1 ms is well below the
# physics tick (typically 1/60 s) so the recovered v1 is accurate to
# better than the propagator can resolve.
const TOL_TIME: float = 1.0e-3
# Bisection bracket on psi. The square root in (2π)^2 corresponds to
# one full rev — we deliberately exclude multi-rev solutions in the
# single-rev solver. Multi-rev support is a Phase-2 extension; see
# the plan file.
const PSI_LOW_INIT: float = -4.0 * PI * PI
const PSI_UP_INIT: float = 4.0 * PI * PI
# When y < 0 with A > 0 (prograde, short way, large transfer angle),
# we push psi up in fixed steps until y crosses zero. Step size is a
# trade-off between convergence cost and risk of overshoot — 0.1
# resolves every realistic geometry inside a handful of iterations.
const Y_PUSH_STEP: float = 0.1
# Cap on the y-push loop. Past this many steps the geometry is
# degenerate (or we drifted past psi_up) — bail rather than spin.
const Y_PUSH_MAX_ITER: int = 200
# Minimum dot-product-derived |cos(Δν) - (-1)| to consider a transfer
# non-degenerate. 1e-6 corresponds to ~1.4e-3 rad ≈ 0.08° — well below
# any TOF resolution the search wrapper samples.
const COLLINEAR_EPS: float = 1.0e-6


## Solve Lambert's problem for a single TOF.
##
## r1, r2     — position vectors (km, ECI)
## tof        — time of flight from r1 to r2 (seconds)
## prograde   — true for the short-way (dm=+1) solution, false for
##              long-way (dm=-1). Missile intercepts almost always
##              want the short way; the long-way solution exists for
##              completeness and is used by tests.
## mu         — gravitational parameter (km³/s²). Negative means
##              "use MassCenterOrbit.MU". Exposed so callers can solve
##              Lambert on bodies other than Earth (Phase-2 multi-body
##              support).
##
## Returns Dictionary {ok: bool, v1: Vector3, v2: Vector3, iters: int}.
## On ok=false the v1/v2 entries may be absent — callers must check
## ok first.
static func solve(
	r1: Vector3, r2: Vector3, tof: float,
	prograde: bool = true, mu: float = -1.0
) -> Dictionary:
	if mu < 0.0:
		mu = MassCenterOrbit.MU
	if tof <= 0.0 or not is_finite(tof):
		return {"ok": false}
	if not _vec_is_finite(r1) or not _vec_is_finite(r2):
		return {"ok": false}

	var r1_norm: float = r1.length()
	var r2_norm: float = r2.length()
	if r1_norm == 0.0 or r2_norm == 0.0:
		return {"ok": false}

	var cos_dnu: float = clampf(r1.dot(r2) / (r1_norm * r2_norm), -1.0, 1.0)
	# Degenerate transfer plane: r1 and r2 antipodal (Δν = π). No
	# unique short-way solution; bail. Search wrappers sample multiple
	# TOFs so a single degenerate one is invisible.
	if absf(cos_dnu + 1.0) < COLLINEAR_EPS:
		return {"ok": false}

	var dm: float = 1.0 if prograde else -1.0
	# A is the "chord scale" coefficient in the universal-variable
	# formulation. Sign tracks the direction of motion. When cos_dnu
	# is near +1 (very small transfer angle) A is small and positive;
	# the y-push branch below handles that regime.
	var A: float = dm * sqrt(r1_norm * r2_norm * (1.0 + cos_dnu))
	if A == 0.0:
		return {"ok": false}

	var sqrt_mu: float = sqrt(mu)
	var psi_low: float = PSI_LOW_INIT
	var psi_up: float = PSI_UP_INIT
	var psi: float = 0.0
	var c2_psi: float = 0.5
	var c3_psi: float = 1.0 / 6.0
	var y: float = 0.0
	var iters: int = 0
	var converged: bool = false
	# Minimum bracket width before we declare bisection has stalled.
	# Catches the post-y-push deadlock where psi_low gets pushed up to
	# match psi_up — geometry then has no elliptic solution at this TOF
	# and we must bail rather than spin.
	var bracket_tol: float = 1.0e-10

	for i in range(MAX_ITER):
		iters = i + 1
		y = r1_norm + r2_norm + A * (psi * c3_psi - 1.0) / sqrt(c2_psi)
		# y < 0 with A > 0 means psi is too low for this geometry — the
		# elliptic transfer requires a higher psi (lazier ellipse). Push
		# psi up until y >= 0; raise psi_low to the pushed value so
		# bisection cannot retreat back below.
		if A > 0.0 and y < 0.0:
			var pushed: int = 0
			while y < 0.0:
				pushed += 1
				if pushed > Y_PUSH_MAX_ITER:
					return {"ok": false}
				psi += Y_PUSH_STEP
				if psi >= psi_up:
					return {"ok": false}
				c2_psi = MassCenterOrbit.c2(psi)
				c3_psi = MassCenterOrbit.c3(psi)
				if c2_psi <= 0.0:
					return {"ok": false}
				y = r1_norm + r2_norm + A * (psi * c3_psi - 1.0) / sqrt(c2_psi)
			psi_low = psi

		if y < 0.0 or c2_psi <= 0.0:
			return {"ok": false}

		var chi: float = sqrt(y / c2_psi)
		var t_iter: float = (chi * chi * chi * c3_psi + A * sqrt(y)) / sqrt_mu
		if not is_finite(t_iter):
			return {"ok": false}

		if absf(t_iter - tof) < TOL_TIME:
			converged = true
			break

		# Bisection update. t_iter is monotone increasing in psi for
		# the single-rev branch, so the bracket stays valid.
		if t_iter <= tof:
			psi_low = psi
		else:
			psi_up = psi

		# Bracket-collapse detection: if the window has shrunk to
		# nothing without converging, no single-rev solution exists at
		# this TOF.
		if absf(psi_up - psi_low) < bracket_tol:
			return {"ok": false}

		psi = 0.5 * (psi_low + psi_up)
		c2_psi = MassCenterOrbit.c2(psi)
		c3_psi = MassCenterOrbit.c3(psi)

	if not converged:
		return {"ok": false}

	# Lagrange f, g, gdot for state recovery from r1, r2, y at the
	# converged psi.
	var f: float = 1.0 - y / r1_norm
	var g: float = A * sqrt(y / mu)
	var g_dot: float = 1.0 - y / r2_norm
	if g == 0.0 or not is_finite(g):
		return {"ok": false}

	var v1: Vector3 = (r2 - r1 * f) / g
	var v2: Vector3 = (r2 * g_dot - r1) / g
	if not _vec_is_finite(v1) or not _vec_is_finite(v2):
		return {"ok": false}

	return {
		"ok": true,
		"v1": v1,
		"v2": v2,
		"iters": iters,
	}


## Best-of-N Lambert intercept search.
##
## Samples TOFs log-spaced across [tof_min, tof_max], propagates a
## clone of target_orbit to each TOF to get r2, solves Lambert for
## the (launch_r, r2, tof) triple, picks the lowest-|dv| solution
## within dv_budget_kms and with miss-distance below
## blast_radius_km. The miss-distance check is a round-trip
## propagation safety net — Lambert is exact in theory, but the
## search wrapper double-checks by propagating the resulting orbit
## forward and measuring closest approach to the propagated target.
##
## Two-pass: a coarse n_coarse-sample sweep, then a fine n_fine
## sweep around the coarse minimum. log-spaced sampling concentrates
## attention near the cheap (slow-transfer) end of the TOF window.
##
## Returns {ok, tof, dv: Vector3, v1, v2, miss_distance_km}.
static func find_best_intercept(
	launch_r: Vector3, launch_v: Vector3,
	target_orbit: MassCenterOrbit,
	tof_min: float, tof_max: float,
	n_coarse: int = 12, n_fine: int = 6,
	dv_budget_kms: float = INF,
	blast_radius_km: float = 5.0,
	mu: float = -1.0
) -> Dictionary:
	if mu < 0.0:
		mu = MassCenterOrbit.MU
	if tof_min <= 0.0 or tof_max <= tof_min:
		return {"ok": false}
	if not _vec_is_finite(launch_r) or not _vec_is_finite(launch_v):
		return {"ok": false}
	if target_orbit == null:
		return {"ok": false}

	var coarse: Dictionary = _sweep_tofs(
		launch_r, launch_v, target_orbit,
		tof_min, tof_max, n_coarse,
		dv_budget_kms, blast_radius_km, mu
	)
	if not coarse.ok:
		return {"ok": false}

	# Fine pass: narrow window centred on the coarse winner. Width
	# scales with the coarse grid spacing so we don't oversample.
	var grid_step: float = (tof_max - tof_min) / float(maxi(n_coarse - 1, 1))
	var fine_min: float = maxf(tof_min, coarse.tof - grid_step)
	var fine_max: float = minf(tof_max, coarse.tof + grid_step)
	if fine_max <= fine_min or n_fine <= 1:
		return coarse

	var fine: Dictionary = _sweep_tofs(
		launch_r, launch_v, target_orbit,
		fine_min, fine_max, n_fine,
		dv_budget_kms, blast_radius_km, mu
	)
	if not fine.ok:
		return coarse
	if fine.dv.length() < coarse.dv.length():
		return fine
	return coarse


# --- internals -------------------------------------------------------------


# Sweep a TOF range, return the best (lowest-dv) intercept found.
# Linear sampling within [t_lo, t_hi]; the outer caller controls log-
# vs-linear by choosing the brackets.
static func _sweep_tofs(
	launch_r: Vector3, launch_v: Vector3,
	target_orbit: MassCenterOrbit,
	t_lo: float, t_hi: float, n: int,
	dv_budget_kms: float, blast_radius_km: float, mu: float
) -> Dictionary:
	var best: Dictionary = {"ok": false}
	var best_dv_mag: float = INF
	if n < 1:
		return best
	for i in range(n):
		var t: float
		if n == 1:
			t = t_lo
		else:
			t = t_lo + (t_hi - t_lo) * float(i) / float(n - 1)
		var probe: Dictionary = _evaluate_tof(
			launch_r, launch_v, target_orbit, t, mu
		)
		if not probe.ok:
			continue
		var dv_mag: float = probe.dv.length()
		if dv_mag > dv_budget_kms:
			continue
		if probe.miss_distance_km > blast_radius_km:
			continue
		if dv_mag < best_dv_mag:
			best_dv_mag = dv_mag
			best = probe
	return best


# Evaluate a single TOF: propagate target, solve Lambert, propagate
# missile, measure closest approach. Returns {ok, tof, dv, v1, v2,
# miss_distance_km}.
static func _evaluate_tof(
	launch_r: Vector3, launch_v: Vector3,
	target_orbit: MassCenterOrbit, tof: float, mu: float
) -> Dictionary:
	# new(r, v) already recomputes elements from the state vector, and
	# propagate() recomputes them again — no need for a clone_from here.
	var target_probe := MassCenterOrbit.new(target_orbit.r, target_orbit.v)
	if not target_probe.propagate(tof):
		return {"ok": false}
	var sol: Dictionary = solve(launch_r, target_probe.r, tof, true, mu)
	if not sol.ok:
		return {"ok": false}
	var v1: Vector3 = sol.v1
	var v2: Vector3 = sol.v2
	var dv: Vector3 = v1 - launch_v
	# Round-trip safety check: propagate the missile's solved orbit by
	# tof and measure how far off r2 we land. Lambert is exact in
	# infinite precision; float32 / iteration tolerance bound the
	# real residual to a few km.
	var missile_probe := MassCenterOrbit.new(launch_r, v1)
	if not missile_probe.propagate(tof):
		return {"ok": false}
	var miss: float = (missile_probe.r - target_probe.r).length()
	return {
		"ok": true,
		"tof": tof,
		"dv": dv,
		"v1": v1,
		"v2": v2,
		"miss_distance_km": miss,
	}


static func _vec_is_finite(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)
