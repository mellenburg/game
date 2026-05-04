class_name SimClock
extends RefCounted
## UTC clock for the simulation. The game starts at a fixed in-fiction
## epoch (2116-04-24 00:00:00 UTC); EarthSystem's `sim_time` is the
## number of simulated seconds since that epoch. Anything that wants to
## display a wall-clock-looking timestamp adds sim_time to the epoch
## and asks Godot's Time API to format the result.
##
## Pure RefCounted so the formatting logic is unit-testable without a
## SceneTree. Stateless — every call is a function of the supplied
## sim_time, so callers don't have to thread a clock instance around.

# In-fiction mission start. Twenty-second-century date deliberately so
# the readout doesn't look like a real-world current event; otherwise
# arbitrary, picked once and then never changed so the schedule's
# absolute UTC times are stable across runs.
const EPOCH_YEAR: int = 2116
const EPOCH_MONTH: int = 4
const EPOCH_DAY: int = 24


# Cached: Godot's Time API rejects pre-1970 dates on some platforms but
# happily roundtrips far-future ones, so the mission epoch lives well
# inside the supported range. Computed once at first call rather than at
# load-time because RefCounted classes don't have static init hooks.
static var _epoch_unix: int = -1


static func epoch_unix_seconds() -> int:
	if _epoch_unix < 0:
		_epoch_unix = int(Time.get_unix_time_from_datetime_dict({
			"year": EPOCH_YEAR,
			"month": EPOCH_MONTH,
			"day": EPOCH_DAY,
			"hour": 0,
			"minute": 0,
			"second": 0,
		}))
	return _epoch_unix


# Format `sim_seconds` as a UTC date-time string. Godot's
# get_datetime_string_from_unix_time returns ISO 8601 ("2116-04-24T00:00:00");
# we replace the T separator with a space for the in-game readout because
# the strict ISO form reads as a logfile timestamp rather than an in-
# fiction wall clock. Negative sim_seconds (defensive: tests, planning
# mode) clamp to the epoch so the readout never displays a date prior
# to mission start.
static func format_utc(sim_seconds: float) -> String:
	var t := maxi(int(sim_seconds), 0) + epoch_unix_seconds()
	var iso := Time.get_datetime_string_from_unix_time(t, true)
	return iso.replace("T", " ") + " UTC"
