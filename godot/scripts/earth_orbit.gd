class_name EarthOrbit
extends RefCounted
## Keplerian orbital mechanics. Universal-variable propagator with
## Newton-Raphson iteration on the Kepler equation. Pure RefCounted so
## it can be unit-tested headlessly without a SceneTree.

const MU: float = 398600.4415       # Earth gravitational parameter (km^3/s^2)
const EARTH_RADIUS_KM: float = 6371.0
const NUM_ITER: int = 50
const RTOL: float = 1.0e-10
# Cap how long a single propagate() step is allowed to be. Larger steps are
# subdivided so the Newton-Raphson stays inside its convergence basin even
# when the user holds the speed-up key.
const MAX_STEP_SECONDS: float = 600.0

# State (ECI, km and km/s)
var r: Vector3
var v: Vector3

# Derived classical elements
var r_p: float
var r_a: float
var ecc: float
var p_slr: float        # semi-latus rectum (named to avoid GDScript keyword)
var a: float
var b: float
var inc: float
var raan: float
var argp: float
var nu: float
var norm_r: float
var norm_v: float
var period: float


func _init(r_in: Vector3, v_in: Vector3) -> void:
	r = r_in
	v = v_in
	_recompute_elements()


func clone_from(other: EarthOrbit) -> void:
	r = other.r
	v = other.v
	r_p = other.r_p
	r_a = other.r_a
	ecc = other.ecc
	p_slr = other.p_slr
	a = other.a
	b = other.b
	inc = other.inc
	raan = other.raan
	argp = other.argp
	nu = other.nu
	norm_r = other.norm_r
	norm_v = other.norm_v
	period = other.period


## Whether the orbit state vector is finite and non-degenerate.
## Callers should check this after propagate() / maneuver() and refuse to
## render or mutate the orbit if it has gone pathological.
func is_state_valid() -> bool:
	if not _vec_is_finite(r) or not _vec_is_finite(v):
		return false
	if norm_r <= 1.0:
		return false
	if not is_finite(a) or not is_finite(ecc) or ecc < 0.0:
		return false
	return true


## Propagate by tof seconds. Subdivides large steps to keep Newton-Raphson
## inside its convergence basin. Returns true on success, false if the
## state went non-finite (caller should treat the orbit as dead).
func propagate(tof: float) -> bool:
	if tof == 0.0:
		return is_state_valid()
	if not is_finite(tof):
		return false
	var steps := int(ceil(absf(tof) / MAX_STEP_SECONDS))
	steps = maxi(steps, 1)
	var sub := tof / float(steps)
	for _i in range(steps):
		if not _propagate_step(sub):
			return false
	_recompute_elements()
	return is_state_valid()


## Apply a delta-v in the ECI frame after propagating by t seconds.
## When `min_periapsis_km > 0`, the dv is shrunk along its own direction
## just enough to keep the post-thrust orbit's periapsis at or above the
## threshold — used to guarantee player thrust can't drive a satellite
## into the surface. Defaults to 0 (no clamping) so other callers retain
## the original semantics.
func maneuver(dv: Vector3, t: float, min_periapsis_km: float = 0.0) -> bool:
	if not propagate(t):
		return false
	var applied_dv := dv
	if min_periapsis_km > 0.0 and dv.length_squared() > 0.0:
		applied_dv = clamp_dv_for_min_periapsis(r, v, dv, min_periapsis_km)
	v += applied_dv
	_recompute_elements()
	return is_state_valid()


## Clamp the perpendicular (tangential) component of `vel` so an orbit
## starting at `pos, vel` is guaranteed to have periapsis at or below
## `max_r_p`. Solves r_p ≤ max_r_p analytically by holding the radial
## component of velocity fixed and shrinking the tangential component
## the minimum amount needed. Caller passes a value strictly less than
## the surface radius for some impact margin.
##
## Used by the meteorite spawner: lateral position spread plus per-axis
## velocity jitter pump enough angular momentum into the orbit that
## periapsis can lift above Earth's surface, turning the trajectory
## into a hyperbolic flyby that never impacts and that the trajectory
## renderer correctly refuses to draw — so without this clamp, "some
## meteorites have no arc" and "some meteorites never hit the ground".
static func clamp_velocity_for_periapsis(
	pos: Vector3, vel: Vector3, max_r_p: float
) -> Vector3:
	var r := pos.length()
	if r <= max_r_p or max_r_p <= 0.0:
		return vel
	var pos_hat := pos / r
	var v_radial_mag := vel.dot(pos_hat)
	var v_perp := vel - pos_hat * v_radial_mag
	# Plug p = (r·v_t)²/μ and e² = 1 + 2(½v² − μ/r)·p/μ² into r_p ≤ R':
	#   v_t² ≤ 2 R' μ / (r (r + R'))  +  R'² v_r² / (r² − R'²)
	var v_t_max_sq := (
		2.0 * max_r_p * MU / (r * (r + max_r_p))
		+ max_r_p * max_r_p * v_radial_mag * v_radial_mag
		/ (r * r - max_r_p * max_r_p)
	)
	var v_t_max := sqrt(maxf(v_t_max_sq, 0.0))
	var v_t_now := v_perp.length()
	if v_t_now <= v_t_max:
		return vel
	return pos_hat * v_radial_mag + v_perp * (v_t_max / v_t_now)


## Apply a delta-v in the local prograde/radial/normal frame. See
## `maneuver` for the meaning of `min_periapsis_km`.
func relative_maneuver(
	dv_local: Vector3, t: float, min_periapsis_km: float = 0.0
) -> bool:
	var i_hat := v.normalized()
	var k_hat := r.cross(v).normalized()
	# Right-handed; j_hat completes the basis (radial-out positive).
	var j_hat := k_hat.cross(i_hat).normalized()
	var dv_eci := i_hat * dv_local.x + j_hat * dv_local.y + k_hat * dv_local.z
	return maneuver(dv_eci, t, min_periapsis_km)


## Build a circular orbit at altitude `alt_km` above the surface with
## the given inclination, RAAN, and true anomaly (all in radians).
## Argument of periapsis is degenerate for a circle, so true anomaly is
## measured from the ascending node. Used by the starting fleet spawner
## (and any future "drop a ship in this orbital slot" gameplay code) so
## the conversion from elements to ECI state lives in one tested place.
static func make_circular(
	alt_km: float, inc: float, raan: float, nu: float
) -> EarthOrbit:
	var radius := EARTH_RADIUS_KM + alt_km
	var v_mag := sqrt(MU / radius)
	var cn := cos(nu)
	var sn := sin(nu)
	var ci := cos(inc)
	var si := sin(inc)
	var co := cos(raan)
	var so := sin(raan)
	# Perifocal-frame state (with the ascending node along +x), tilted
	# about the line of nodes by `inc`, then rotated about Z by `raan`.
	# Carried through algebraically so we never construct an intermediate
	# Vector3 that would discard precision through 32-bit components.
	var pos := Vector3(
		radius * (cn * co - sn * ci * so),
		radius * (cn * so + sn * ci * co),
		radius * sn * si,
	)
	var vel := Vector3(
		v_mag * (-sn * co - cn * ci * so),
		v_mag * (-sn * so + cn * ci * co),
		v_mag * cn * si,
	)
	return EarthOrbit.new(pos, vel)


## Periapsis radius for the orbit defined by (r, v). Uses the
## conic-section identity r_p = p / (1+e), which is well-defined for all
## eccentricities (elliptic, parabolic, hyperbolic). Returns 0 for a
## degenerate (rectilinear) state — a body with no angular momentum
## falls straight through the origin, so any min-periapsis test should
## treat it as an impact.
static func compute_periapsis(pos: Vector3, vel: Vector3) -> float:
	var r_len := pos.length()
	if r_len == 0.0:
		return 0.0
	var h := pos.cross(vel)
	var norm_h := h.length()
	if norm_h == 0.0:
		return 0.0
	var v_sq := vel.dot(vel)
	var e_vec := pos * ((v_sq - MU / r_len) / MU) + vel * (-pos.dot(vel) / MU)
	var ecc := e_vec.length()
	var p_slr := h.dot(h) / MU
	return p_slr / (1.0 + ecc)


## Shrink `dv` along its own direction to the largest fraction α ∈ [0,1]
## such that (vel + α·dv) defines an orbit with periapsis ≥ min_r_p.
## Bisection — the safety predicate is monotone in α along the dv ray
## near the unsafe boundary in every realistic player-thrust case, and
## even when it isn't, returning a fraction that is *safe* is enough for
## the gameplay rule. Returns Vector3.ZERO if the pre-thrust orbit is
## already unsafe (refusing to amplify a doomed trajectory rather than
## silently letting the player make it worse).
static func clamp_dv_for_min_periapsis(
	pos: Vector3, vel: Vector3, dv: Vector3, min_r_p: float
) -> Vector3:
	if min_r_p <= 0.0 or dv.length_squared() == 0.0:
		return dv
	if compute_periapsis(pos, vel + dv) >= min_r_p:
		return dv
	if compute_periapsis(pos, vel) < min_r_p:
		return Vector3.ZERO
	var lo := 0.0
	var hi := 1.0
	for _i in range(24):
		var mid := 0.5 * (lo + hi)
		if compute_periapsis(pos, vel + dv * mid) >= min_r_p:
			lo = mid
		else:
			hi = mid
	return dv * lo


# --- internals -------------------------------------------------------------

func _propagate_step(tof: float) -> bool:
	var r0 := r
	var v0 := v
	var dot_r0v0 := r0.dot(v0)
	var nr0 := r0.length()
	if nr0 == 0.0:
		return false
	var sqrt_mu := sqrt(MU)
	var alpha := (2.0 / nr0) - (v0.dot(v0) / MU)

	var xi_new: float
	if alpha > 1.0e-6:
		xi_new = sqrt_mu * tof * alpha
	elif alpha < -1.0e-6:
		var s := signf(tof)
		var arg := (-2.0 * MU * alpha * tof) / (
			dot_r0v0 + s * sqrt(-MU / alpha) * (1.0 - nr0 * alpha)
		)
		if arg <= 0.0 or not is_finite(arg):
			return false
		xi_new = s * sqrt(-1.0 / alpha) * log(arg)
	else:
		xi_new = sqrt_mu * tof / nr0

	var xi := xi_new
	var psi := 0.0
	var c2_psi := 0.5
	var c3_psi := 1.0 / 6.0
	var nr := nr0
	for _i in range(NUM_ITER):
		xi = xi_new
		psi = xi * xi * alpha
		c2_psi = c2(psi)
		c3_psi = c3(psi)
		nr = (
			xi * xi * c2_psi
			+ dot_r0v0 / sqrt_mu * xi * (1.0 - psi * c3_psi)
			+ nr0 * (1.0 - psi * c2_psi)
		)
		if nr <= 0.0 or not is_finite(nr):
			return false
		var delta := (
			sqrt_mu * tof
			- xi * xi * xi * c3_psi
			- dot_r0v0 / sqrt_mu * xi * xi * c2_psi
			- nr0 * xi * (1.0 - psi * c3_psi)
		) / nr
		xi_new = xi + delta
		if absf(delta) < RTOL:
			break

	if not is_finite(xi_new) or not is_finite(nr):
		return false

	var f := 1.0 - (xi * xi) / nr0 * c2_psi
	var g := tof - (xi * xi * xi) / sqrt_mu * c3_psi
	var gdot := 1.0 - (xi * xi) / nr * c2_psi
	var fdot := sqrt_mu / (nr * nr0) * xi * (psi * c3_psi - 1.0)

	var r_new := r0 * f + v0 * g
	var v_new := r0 * fdot + v0 * gdot
	if not _vec_is_finite(r_new) or not _vec_is_finite(v_new):
		return false
	r = r_new
	v = v_new
	return true


func _recompute_elements() -> void:
	var z := Vector3(0.0, 0.0, 1.0)
	var h := r.cross(v)
	var norm_h := h.length()
	var r_len := r.length()

	norm_r = r_len
	norm_v = v.length()

	if norm_h == 0.0 or r_len == 0.0:
		# Rectilinear or singular state. Leave most elements undefined but
		# do not propagate NaN — set sentinels the caller can detect.
		ecc = NAN
		a = NAN
		return

	var n := z.cross(h) / norm_h
	var v_sq := v.dot(v)
	var e_vec := r * ((v_sq - MU / r_len) / MU) + v * (-r.dot(v) / MU)
	ecc = e_vec.length()

	p_slr = h.dot(h) / MU
	var one_minus_e2 := 1.0 - ecc * ecc
	if absf(one_minus_e2) < 1.0e-12:
		a = INF
		b = INF
	else:
		a = p_slr / one_minus_e2
		b = a * sqrt(maxf(1.0 - ecc * ecc, 0.0))

	inc = acos(clampf(h.z / norm_h, -1.0, 1.0))

	var tol := 1.0e-8
	var equatorial := absf(inc) < tol or absf(inc - PI) < tol
	var circular := ecc < tol

	if equatorial and circular:
		raan = 0.0
		argp = 0.0
		nu = atan2(r.y, r.x)
	elif equatorial and not circular:
		raan = 0.0
		argp = atan2(e_vec.y, e_vec.x)
		var e_cross_r := e_vec.cross(r) / norm_h
		nu = atan2(h.dot(e_cross_r), r.dot(e_vec))
	elif circular and not equatorial:
		raan = atan2(n.y, n.x)
		argp = 0.0
		nu = atan2(r.dot(h.cross(n) / norm_h), r.dot(n))
	else:
		raan = atan2(n.y, n.x)
		argp = atan2(e_vec.dot(h.cross(n) / norm_h), e_vec.dot(n))
		nu = atan2(r.dot(h.cross(e_vec) / norm_h), r.dot(e_vec))

	r_p = a * (1.0 - ecc) if is_finite(a) else NAN
	r_a = a * (1.0 + ecc) if is_finite(a) else NAN
	period = TAU * sqrt(pow(absf(a), 3) / MU) if is_finite(a) and a > 0.0 else INF


# Stumpff functions. Bounded iteration count + relative epsilon termination
# (the original `while res + delta != res` loop terminated by IEEE equality
# which is fragile under denormals).
const _STUMPFF_MAX_ITER: int = 60
const _STUMPFF_EPS: float = 1.0e-15

static func c2(psi: float) -> float:
	if psi > 1.0:
		var sp := sqrt(psi)
		return (1.0 - cos(sp)) / psi
	if psi < -1.0:
		var sn := sqrt(-psi)
		return (cosh(sn) - 1.0) / (-psi)
	# Taylor series for small |psi|.
	var res := 0.5
	var term := 1.0 / 2.0
	for k in range(1, _STUMPFF_MAX_ITER):
		term *= -psi / float((2 * k + 1) * (2 * k + 2))
		res += term
		if absf(term) < _STUMPFF_EPS * absf(res) + _STUMPFF_EPS:
			return res
	return res


static func c3(psi: float) -> float:
	if psi > 1.0:
		var sp := sqrt(psi)
		return (sp - sin(sp)) / pow(psi, 1.5)
	if psi < -1.0:
		var sn := sqrt(-psi)
		return (sinh(sn) - sn) / (-psi * sn)
	var res := 1.0 / 6.0
	var term := 1.0 / 6.0
	for k in range(1, _STUMPFF_MAX_ITER):
		term *= -psi / float((2 * k + 2) * (2 * k + 3))
		res += term
		if absf(term) < _STUMPFF_EPS * absf(res) + _STUMPFF_EPS:
			return res
	return res


static func _vec_is_finite(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)
