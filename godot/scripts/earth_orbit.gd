class_name EarthOrbit
## Keplerian orbital mechanics engine.
## Direct port of orbit.cpp — uses universal variable formulation
## with Lagrange coefficients and Newton-Raphson iteration.

const MU: float = 398600.4415  # Earth gravitational parameter (km^3/s^2)
const NUM_ITER: int = 35
const RTOL: float = 1e-10

# State vectors (ECI frame, km and km/s)
var r: Vector3
var v: Vector3

# Classical orbital elements
var r_p: float   # periapsis radius
var r_a: float   # apoapsis radius
var ecc: float   # eccentricity
var p: float     # semi-latus rectum
var a: float     # semi-major axis
var b: float     # semi-minor axis
var inc: float   # inclination (rad)
var raan: float  # right ascension of ascending node (rad)
var argp: float  # argument of periapsis (rad)
var nu: float    # true anomaly (rad)
var norm_r: float
var norm_v: float
var period: float


func _init(r_in: Vector3, v_in: Vector3) -> void:
	r = r_in
	v = v_in
	rv2coe()


func clone_from(other: EarthOrbit) -> void:
	r = other.r
	v = other.v
	r_p = other.r_p
	r_a = other.r_a
	ecc = other.ecc
	p = other.p
	a = other.a
	b = other.b
	inc = other.inc
	raan = other.raan
	argp = other.argp
	nu = other.nu
	norm_r = other.norm_r
	norm_v = other.norm_v
	period = other.period


## Stumpff function c2(psi)
static func c2(psi: float) -> float:
	if psi > 1.0:
		return (1.0 - cos(sqrt(psi))) / psi
	elif psi < -1.0:
		return (cosh(sqrt(-psi)) - 1.0) / (-psi)
	else:
		# Taylor series expansion
		var res: float = 0.5
		var k: int = 1
		var delta: float = (-psi) / _factorial(4)
		while res + delta != res:
			res += delta
			k += 1
			delta = pow(-psi, k) / _factorial(2 * k + 2)
		return res


## Stumpff function c3(psi)
static func c3(psi: float) -> float:
	if psi > 1.0:
		return (sqrt(psi) - sin(sqrt(psi))) / pow(psi, 1.5)
	elif psi < -1.0:
		return (sinh(sqrt(-psi)) - sqrt(-psi)) / (-psi * sqrt(-psi))
	else:
		# Taylor series expansion
		var res: float = 1.0 / 6.0
		var k: int = 1
		var delta: float = (-psi) / _factorial(5)
		while res + delta != res:
			res += delta
			k += 1
			delta = pow(-psi, k) / _factorial(2 * k + 3)
		return res


## Compute factorial (used instead of tgamma to avoid the infinite loop bug)
static func _factorial(n: int) -> float:
	var result: float = 1.0
	for i in range(2, n + 1):
		result *= i
	return result


## Convert position/velocity to classical orbital elements
func rv2coe() -> void:
	var z := Vector3(0.0, 0.0, 1.0)
	var h := r.cross(v)
	var norm_h := h.length()

	var z_cross_h := z.cross(h)
	var n := z_cross_h / norm_h

	var r_len := r.length()
	var v_sq := v.dot(v)
	var e_r := r * ((v_sq - MU / r_len) / MU)
	var e_v := v * ((-r.dot(v)) / MU)
	var e := e_r + e_v
	ecc = e.length()

	p = h.dot(h) / MU
	a = p / (1.0 - ecc * ecc)
	b = a * sqrt(1.0 - ecc * ecc)
	inc = acos(clampf(h.z / norm_h, -1.0, 1.0))

	var h_cross_n := h.cross(n) / norm_h
	var tol := 1.0e-8
	var equatorial := absf(inc) < tol
	var circular := ecc < tol

	if equatorial and not circular:
		raan = 0.0
		argp = atan2(e.y, e.x)
		var e_cross_r := e.cross(r)
		var between := e_cross_r / norm_h
		nu = atan2(h.dot(between), r.dot(e))
	elif not equatorial and circular:
		raan = atan2(n.y, n.x)
		argp = 0.0
		nu = atan2(r.dot(h_cross_n), r.dot(n))
	elif equatorial and circular:
		raan = 0.0
		argp = 0.0
		nu = atan2(r.y, r.x)
	else:
		raan = atan2(n.y, n.x)
		var h_cross_e := h.cross(e) / norm_h
		argp = atan2(e.dot(h_cross_n), e.dot(n))
		nu = atan2(r.dot(h_cross_e), r.dot(e))

	r_a = a * (1.0 + ecc)
	r_p = a * (1.0 - ecc)
	period = TAU * sqrt(pow(a, 3) / MU)
	norm_r = r.length()
	norm_v = v.length()


## Propagate orbit forward by time-of-flight (seconds) using universal variables
func propagate(tof: float) -> void:
	var r0 := r
	var v0 := v
	var dot_r0v0 := r0.dot(v0)
	var norm_r0 := r0.length()
	var sqrt_mu := sqrt(MU)
	var alpha := (2.0 / norm_r0) - (v0.dot(v0) / MU)

	# Initial guess for universal variable
	var xi_new: float
	if alpha > 0.0:
		# Elliptical
		xi_new = sqrt_mu * tof * alpha
	elif alpha < 0.0:
		# Hyperbolic
		xi_new = sqrt(-1.0 / alpha) * log(
			(-2.0 * MU * alpha * tof) /
			(dot_r0v0 + sqrt(-MU / alpha) * (1.0 - norm_r0 * alpha))
		)
	else:
		# Parabolic
		xi_new = sqrt_mu * tof / norm_r0

	# Newton-Raphson iteration on the Kepler equation
	var xi: float
	var psi: float
	var c2_psi: float
	var c3_psi: float
	var nr: float  # norm_r during iteration

	for _i in range(NUM_ITER):
		xi = xi_new
		psi = xi * xi * alpha
		c2_psi = c2(psi)
		c3_psi = c3(psi)
		nr = (xi * xi * c2_psi +
			dot_r0v0 / sqrt_mu * xi * (1.0 - psi * c3_psi) +
			norm_r0 * (1.0 - psi * c2_psi))
		xi_new = xi + (sqrt_mu * tof - xi * xi * xi * c3_psi -
			dot_r0v0 / sqrt_mu * xi * xi * c2_psi -
			norm_r0 * xi * (1.0 - psi * c3_psi)) / nr
		if absf(xi_new - xi) < RTOL or (absf(xi_new) > 0.0 and absf((xi_new - xi) / xi_new) < RTOL):
			break

	var f := 1.0 - (xi * xi) / norm_r0 * c2_psi
	var g := tof - (xi * xi * xi) / sqrt_mu * c3_psi
	var gdot := 1.0 - (xi * xi) / nr * c2_psi
	var fdot := sqrt_mu / (nr * norm_r0) * xi * (psi * c3_psi - 1.0)

	r = r0 * f + v0 * g
	v = r0 * fdot + v0 * gdot
	rv2coe()


## Apply a delta-v maneuver in the ECI frame after propagating by dv.w seconds
func maneuver(dv: Vector3, t: float) -> void:
	propagate(t)
	v += dv
	rv2coe()


## Apply a delta-v in the local orbital frame (prograde/radial/normal)
func relative_maneuver(dv: Vector3, t: float) -> void:
	var i_hat := v.normalized()
	var r_cross_v := r.cross(v)
	var k_hat := r_cross_v.normalized()
	var j_hat := -(i_hat.cross(k_hat)).normalized()

	var dv_eci := i_hat * dv.x + j_hat * dv.y + k_hat * dv.z
	maneuver(dv_eci, t)
