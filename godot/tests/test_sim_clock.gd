extends "res://tests/framework.gd"
## SimClock formatter coverage. The clock is a thin wrapper around
## Godot's Time API that adds an in-fiction epoch (April 24th, 2116) to
## sim_time and renders the result as a UTC string. The tests pin the
## epoch and verify hour / minute progression so a future tweak to the
## formatter or the epoch is loud.

const SimClock = preload("res://scripts/sim_clock.gd")


func test_zero_sim_time_renders_as_epoch() -> void:
	var s := SimClock.format_utc(0.0)
	assert_eq(s, "2116-04-24 00:00:00 UTC")


func test_one_hour_sim_time_advances_clock() -> void:
	var s := SimClock.format_utc(3600.0)
	assert_eq(s, "2116-04-24 01:00:00 UTC")


func test_one_day_sim_time_advances_date() -> void:
	# 86400 sim-sec = exactly 24 hours; clock rolls into April 25.
	var s := SimClock.format_utc(86400.0)
	assert_eq(s, "2116-04-25 00:00:00 UTC")


func test_negative_sim_time_clamps_to_epoch() -> void:
	# Defensive: planning_dt previews / tests can produce negative
	# offsets relative to mission start. The formatter must not display
	# pre-epoch dates — those would confuse the operator about the
	# in-fiction timeline.
	var s := SimClock.format_utc(-100.0)
	assert_eq(s, "2116-04-24 00:00:00 UTC")


func test_epoch_unix_seconds_stable_across_calls() -> void:
	# The cache lives on a static var; two calls must agree exactly.
	var a := SimClock.epoch_unix_seconds()
	var b := SimClock.epoch_unix_seconds()
	assert_eq(a, b)
