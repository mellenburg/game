extends "res://tests/framework.gd"
## Line-of-sight ray-vs-Earth-sphere tests.

const LosCheck = preload("res://scripts/los_check.gd")
const R := 6371.0  # km


func test_clear_above_planet() -> void:
	# Two satellites side-by-side on the same hemisphere.
	var a := Vector3(R + 400.0, 0.0, 0.0)
	var b := Vector3(R + 400.0, 1000.0, 0.0)
	assert_false(LosCheck.is_blocked(a, b))


func test_blocked_through_planet() -> void:
	# Antipodal satellites: line passes through Earth's center.
	var a := Vector3(R + 400.0, 0.0, 0.0)
	var b := Vector3(-(R + 400.0), 0.0, 0.0)
	assert_true(LosCheck.is_blocked(a, b))


func test_grazing_far_above_planet() -> void:
	# Tangent ray well clear of the planet.
	var a := Vector3(0.0, R + 1000.0, 0.0)
	var b := Vector3(0.0, R + 1000.0, 5000.0)
	assert_false(LosCheck.is_blocked(a, b))


func test_short_segment_misses_far_planet() -> void:
	# Segment lies entirely outside the bounding sphere; intersections
	# (if any) are along the infinite line, not within [0, 1].
	var a := Vector3(R + 1000.0, 0.0, 0.0)
	var b := Vector3(R + 1000.0, 0.0, 100.0)
	assert_false(LosCheck.is_blocked(a, b))


func test_segment_starts_inside_planet_is_blocked() -> void:
	# Pathological: one endpoint is below the surface.
	var a := Vector3(0.0, 0.0, 0.0)
	var b := Vector3(R + 1000.0, 0.0, 0.0)
	assert_true(LosCheck.is_blocked(a, b))


func test_zero_length_outside_planet_is_clear() -> void:
	var a := Vector3(R + 400.0, 0.0, 0.0)
	assert_false(LosCheck.is_blocked(a, a))


func test_zero_length_inside_planet_is_blocked() -> void:
	assert_true(LosCheck.is_blocked(Vector3.ZERO, Vector3.ZERO))
