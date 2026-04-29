extends SceneTree
## Headless test runner. Discovers every `tests/test_*.gd` file, loads it,
## instantiates a TestCase, and runs its `test_*` methods. Exits with a
## non-zero code if any assertion fails so CI can gate on it.
##
## Run with: godot --headless --quit --script res://tests/run_tests.gd
## (the SceneTree subclass form auto-quits after _initialize() returns
## once we call quit() ourselves).

const TESTS_DIR := "res://tests/"


func _initialize() -> void:
	var test_files := _discover_tests()
	test_files.sort()
	var total_ran := 0
	var total_failed := 0
	var all_failures: PackedStringArray = PackedStringArray()

	print("== Running %d test file(s) ==" % test_files.size())
	for path in test_files:
		var script: GDScript = load(path) as GDScript
		if script == null:
			push_error("Failed to load test script: %s" % path)
			total_failed += 1
			all_failures.append("LOAD FAILED: %s" % path)
			continue
		var tc = script.new()
		if tc == null:
			push_error("Failed to instantiate: %s" % path)
			total_failed += 1
			all_failures.append("INSTANTIATE FAILED: %s" % path)
			continue
		var result: Array = tc.run()
		var ran: int = result[0]
		var failures: Array = result[1]
		total_ran += ran
		total_failed += failures.size()
		var status := "OK" if failures.is_empty() else "FAIL"
		print("  [%s] %s — %d test(s)" % [status, path.get_file(), ran])
		for f in failures:
			all_failures.append(f)

	print("")
	if all_failures.is_empty():
		print("== %d test(s) passed ==" % total_ran)
		quit(0)
		return
	print("== %d FAILED of %d ==" % [total_failed, total_ran])
	for f in all_failures:
		print("  - %s" % f)
	quit(1)


func _discover_tests() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var dir := DirAccess.open(TESTS_DIR)
	if dir == null:
		push_error("Could not open tests dir: %s" % TESTS_DIR)
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if (
			not dir.current_is_dir()
			and entry.begins_with("test_")
			and entry.ends_with(".gd")
		):
			out.append(TESTS_DIR + entry)
		entry = dir.get_next()
	dir.list_dir_end()
	return out
