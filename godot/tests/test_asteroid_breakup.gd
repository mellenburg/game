extends "res://tests/framework.gd"
## AsteroidBreakup unit tests. Pure RefCounted module — no SceneTree needed.
## Verifies the two fundamental invariants for every N:
##   Σ mass_i              = parent_mass
##   Σ mass_i × velocity_i = parent_mass × parent_velocity
## Plus per-child deflection angle and edge-case guards.

const AsteroidBreakup = preload("res://scripts/asteroid_breakup.gd")

# Realistic medium-asteroid parameters. 1 Gg is solidly in the Tunguska
# class — measurable threat, tractable momentum values.
const PARENT_MASS: float  = 1.0e6   # 1 Gg
const PARENT_V := Vector3(2.5, -1.0, 0.8)  # km/s
const DEFLECTION_DEG: float = 20.0
const DEFLECTION_RAD: float = DEFLECTION_DEG * PI / 180.0

# Tolerance notes:
#   Mass (float64): GDScript floats are 64-bit, so mass arithmetic has
#     ~1e-10 relative error. MASS_TOL = 1e-6 is far above this.
#   Momentum (Vector3 = float32): at |p| ≈ 2.5e6 kg·km/s the float32
#     ULP is ≈ 0.3 per component. MOMENTUM_TOL = 10.0 gives 33× headroom
#     while still failing if the algorithm has a real bug.
#   Cosine (dot product of unit vectors, float32): 1e-5 is ≈ 100× ULP.
const MASS_TOL: float = 1.0e-6
const MOMENTUM_TOL: float = 10.0
const COS_TOL: float = 1.0e-5


func _make_rng(seed: int = 42) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	return r


# ----- invariant helpers ----------------------------------------------------

func _check_mass_conservation(
	children: Array[Dictionary],
	parent_mass: float,
	label: String,
) -> void:
	var total: float = 0.0
	for c: Dictionary in children:
		total += float(c["mass"])
	assert_close(total, parent_mass, MASS_TOL, label + " mass conservation")


func _check_momentum_conservation(
	children: Array[Dictionary],
	parent_mass: float,
	parent_velocity: Vector3,
	label: String,
) -> void:
	var p_total: Vector3 = parent_mass * parent_velocity
	var p_sum := Vector3.ZERO
	for c: Dictionary in children:
		var m: float = float(c["mass"])
		var v: Vector3 = c["velocity"]
		p_sum += m * v
	# Component-wise check so the failure message pins the axis that drifted.
	assert_close(p_sum.x, p_total.x, MOMENTUM_TOL, label + " px")
	assert_close(p_sum.y, p_total.y, MOMENTUM_TOL, label + " py")
	assert_close(p_sum.z, p_total.z, MOMENTUM_TOL, label + " pz")


# ----- N = 1 -----------------------------------------------------------------

func test_single_child_passthrough() -> void:
	var children := AsteroidBreakup.compute_children(
		1, PARENT_MASS, PARENT_V, DEFLECTION_RAD, _make_rng()
	)
	assert_eq(children.size(), 1, "one child returned")
	assert_close(float(children[0]["mass"]), PARENT_MASS, MASS_TOL, "mass")
	assert_vec_close(children[0]["velocity"], PARENT_V, 1.0e-5, "velocity")


# ----- N = 2 -----------------------------------------------------------------

func test_two_children_count() -> void:
	var children := AsteroidBreakup.compute_children(
		2, PARENT_MASS, PARENT_V, DEFLECTION_RAD, _make_rng()
	)
	assert_eq(children.size(), 2)


func test_two_children_mass_conservation() -> void:
	var children := AsteroidBreakup.compute_children(
		2, PARENT_MASS, PARENT_V, DEFLECTION_RAD, _make_rng()
	)
	_check_mass_conservation(children, PARENT_MASS, "N=2")


func test_two_children_momentum_conservation() -> void:
	var children := AsteroidBreakup.compute_children(
		2, PARENT_MASS, PARENT_V, DEFLECTION_RAD, _make_rng()
	)
	_check_momentum_conservation(children, PARENT_MASS, PARENT_V, "N=2")


func test_two_children_first_child_at_parent_speed() -> void:
	# Child 1 is deflected but keeps the parent's speed magnitude.
	var children := AsteroidBreakup.compute_children(
		2, PARENT_MASS, PARENT_V, DEFLECTION_RAD, _make_rng()
	)
	var speed1: float = (children[0]["velocity"] as Vector3).length()
	assert_close(speed1, PARENT_V.length(), 1.0e-5, "child 1 speed = parent speed")


func test_two_children_first_child_within_deflection() -> void:
	for seed: int in [0, 7, 42, 99, 123]:
		var children := AsteroidBreakup.compute_children(
			2, PARENT_MASS, PARENT_V, DEFLECTION_RAD, _make_rng(seed)
		)
		var v1: Vector3 = children[0]["velocity"]
		var cos_angle: float = v1.normalized().dot(PARENT_V.normalized())
		assert_true(
			cos_angle >= cos(DEFLECTION_RAD) - COS_TOL,
			"N=2 seed=%d child 1 within deflection cone" % seed
		)


func test_two_children_first_mass_in_valid_range() -> void:
	# Child 1 mass fraction must be in [0.5, 1.0] of parent_mass.
	for seed: int in range(10):
		var children := AsteroidBreakup.compute_children(
			2, PARENT_MASS, PARENT_V, DEFLECTION_RAD, _make_rng(seed)
		)
		var m0: float = float(children[0]["mass"])
		assert_true(m0 >= 0.5 * PARENT_MASS - MASS_TOL,
			"seed=%d child 1 mass >= 0.5 * parent" % seed)
		assert_true(m0 <= PARENT_MASS + MASS_TOL,
			"seed=%d child 1 mass <= parent" % seed)


# ----- N = 3 -----------------------------------------------------------------

func test_three_children_count() -> void:
	var children := AsteroidBreakup.compute_children(
		3, PARENT_MASS, PARENT_V, DEFLECTION_RAD, _make_rng()
	)
	assert_eq(children.size(), 3)


func test_three_children_mass_conservation() -> void:
	for seed: int in [0, 1, 7, 42, 123]:
		var children := AsteroidBreakup.compute_children(
			3, PARENT_MASS, PARENT_V, DEFLECTION_RAD, _make_rng(seed)
		)
		_check_mass_conservation(children, PARENT_MASS, "N=3 seed=%d" % seed)


func test_three_children_momentum_conservation() -> void:
	for seed: int in [0, 1, 7, 42, 123]:
		var children := AsteroidBreakup.compute_children(
			3, PARENT_MASS, PARENT_V, DEFLECTION_RAD, _make_rng(seed)
		)
		_check_momentum_conservation(
			children, PARENT_MASS, PARENT_V, "N=3 seed=%d" % seed
		)


func test_three_children_child1_at_parent_speed() -> void:
	# k=1 is in the 1..N-2 = 1..1 range — deflected, parent speed.
	var children := AsteroidBreakup.compute_children(
		3, PARENT_MASS, PARENT_V, DEFLECTION_RAD, _make_rng()
	)
	var speed1: float = (children[0]["velocity"] as Vector3).length()
	assert_close(speed1, PARENT_V.length(), 1.0e-5, "N=3 child 1 speed = parent speed")


func test_three_children_child1_within_deflection() -> void:
	for seed: int in [0, 1, 7, 42, 123, 999]:
		var children := AsteroidBreakup.compute_children(
			3, PARENT_MASS, PARENT_V, DEFLECTION_RAD, _make_rng(seed)
		)
		var v1: Vector3 = children[0]["velocity"]
		var cos_angle: float = v1.normalized().dot(PARENT_V.normalized())
		assert_true(
			cos_angle >= cos(DEFLECTION_RAD) - COS_TOL,
			"N=3 seed=%d child 1 within deflection" % seed
		)


# ----- N = 4 -----------------------------------------------------------------

func test_four_children_mass_conservation() -> void:
	for seed: int in [0, 1, 7, 42, 123]:
		var children := AsteroidBreakup.compute_children(
			4, PARENT_MASS, PARENT_V, DEFLECTION_RAD, _make_rng(seed)
		)
		_check_mass_conservation(children, PARENT_MASS, "N=4 seed=%d" % seed)


func test_four_children_momentum_conservation() -> void:
	for seed: int in [0, 1, 7, 42, 123]:
		var children := AsteroidBreakup.compute_children(
			4, PARENT_MASS, PARENT_V, DEFLECTION_RAD, _make_rng(seed)
		)
		_check_momentum_conservation(
			children, PARENT_MASS, PARENT_V, "N=4 seed=%d" % seed
		)


func test_four_children_first_two_at_parent_speed() -> void:
	# Children k=1 and k=2 are both in the 1..N-2 range for N=4.
	var children := AsteroidBreakup.compute_children(
		4, PARENT_MASS, PARENT_V, DEFLECTION_RAD, _make_rng()
	)
	var parent_speed: float = PARENT_V.length()
	assert_close(
		(children[0]["velocity"] as Vector3).length(), parent_speed, 1.0e-5,
		"N=4 child 1 speed"
	)
	assert_close(
		(children[1]["velocity"] as Vector3).length(), parent_speed, 1.0e-5,
		"N=4 child 2 speed"
	)


func test_four_children_first_two_within_deflection() -> void:
	for seed: int in [0, 1, 7, 42, 123]:
		var children := AsteroidBreakup.compute_children(
			4, PARENT_MASS, PARENT_V, DEFLECTION_RAD, _make_rng(seed)
		)
		var parent_dir: Vector3 = PARENT_V.normalized()
		for idx: int in [0, 1]:
			var v: Vector3 = children[idx]["velocity"]
			var cos_angle: float = v.normalized().dot(parent_dir)
			assert_true(
				cos_angle >= cos(DEFLECTION_RAD) - COS_TOL,
				"N=4 seed=%d child %d within deflection" % [seed, idx + 1]
			)


# ----- Edge cases -----------------------------------------------------------

func test_zero_children_returns_empty() -> void:
	var children := AsteroidBreakup.compute_children(
		0, PARENT_MASS, PARENT_V, DEFLECTION_RAD, _make_rng()
	)
	assert_eq(children.size(), 0, "n=0 → empty")


func test_negative_children_returns_empty() -> void:
	var children := AsteroidBreakup.compute_children(
		-1, PARENT_MASS, PARENT_V, DEFLECTION_RAD, _make_rng()
	)
	assert_eq(children.size(), 0, "n=-1 → empty")


func test_zero_mass_returns_empty() -> void:
	var children := AsteroidBreakup.compute_children(
		2, 0.0, PARENT_V, DEFLECTION_RAD, _make_rng()
	)
	assert_eq(children.size(), 0, "mass=0 → empty")


func test_zero_velocity_parent_mass_conserved() -> void:
	# Zero-velocity parent: mass conservation still holds; all velocities
	# are zero (orbit validity is the caller's concern, not this class).
	var children := AsteroidBreakup.compute_children(
		2, PARENT_MASS, Vector3.ZERO, DEFLECTION_RAD, _make_rng()
	)
	assert_eq(children.size(), 2, "two children produced")
	_check_mass_conservation(children, PARENT_MASS, "zero-vel N=2")
	_check_momentum_conservation(children, PARENT_MASS, Vector3.ZERO, "zero-vel N=2")


func test_zero_deflection_child1_collinear() -> void:
	# deflection = 0 → child 1's velocity direction is exactly the parent's.
	var children := AsteroidBreakup.compute_children(
		3, PARENT_MASS, PARENT_V, 0.0, _make_rng()
	)
	var v0: Vector3 = children[0]["velocity"]
	assert_close(
		v0.normalized().dot(PARENT_V.normalized()), 1.0, COS_TOL,
		"zero deflection → child 1 collinear with parent"
	)


func test_fuzz_mass_and_momentum_n3() -> void:
	# Verify invariants across many independent seeds.
	for seed: int in range(25):
		var children := AsteroidBreakup.compute_children(
			3, PARENT_MASS, PARENT_V, DEFLECTION_RAD, _make_rng(seed)
		)
		_check_mass_conservation(children, PARENT_MASS, "fuzz seed=%d" % seed)
		_check_momentum_conservation(
			children, PARENT_MASS, PARENT_V, "fuzz seed=%d" % seed
		)


func test_fuzz_mass_and_momentum_n2() -> void:
	for seed: int in range(25):
		var children := AsteroidBreakup.compute_children(
			2, PARENT_MASS, PARENT_V, DEFLECTION_RAD, _make_rng(seed)
		)
		_check_mass_conservation(children, PARENT_MASS, "N=2 fuzz seed=%d" % seed)
		_check_momentum_conservation(
			children, PARENT_MASS, PARENT_V, "N=2 fuzz seed=%d" % seed
		)


func test_all_children_masses_positive() -> void:
	for n: int in [1, 2, 3, 4]:
		for seed: int in range(10):
			var children := AsteroidBreakup.compute_children(
				n, PARENT_MASS, PARENT_V, DEFLECTION_RAD, _make_rng(seed)
			)
			for i: int in range(children.size()):
				assert_true(
					float(children[i]["mass"]) >= 0.0,
					"N=%d seed=%d child %d mass >= 0" % [n, seed, i]
				)
