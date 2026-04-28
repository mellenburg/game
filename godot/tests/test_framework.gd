class_name TestCase
extends RefCounted
## Tiny assertion harness. Each test file extends this class and adds
## test_* methods; run_tests.gd discovers them by name. Keeping it small
## and dependency-free so CI doesn't need to pull a third-party addon.

var _failures: PackedStringArray = PackedStringArray()
var _ran: int = 0
var _current_test: String = ""


func test_file_name() -> String:
	return get_script().resource_path.get_file().get_basename()


## Discover and invoke every method whose name starts with "test_".
## Returns [ran_count, failure_messages].
func run() -> Array:
	_failures.clear()
	_ran = 0
	for m in get_method_list():
		var n: String = m.name
		if not n.begins_with("test_"):
			continue
		_ran += 1
		_current_test = n
		callv(n, [])
	_current_test = ""
	return [_ran, Array(_failures)]


func fail(msg: String) -> void:
	_failures.append(msg)
	push_error(msg)


func assert_true(cond: bool, msg: String = "") -> void:
	if not cond:
		fail("%s: expected true%s" % [_caller_test(), _suffix(msg)])


func assert_false(cond: bool, msg: String = "") -> void:
	if cond:
		fail("%s: expected false%s" % [_caller_test(), _suffix(msg)])


func assert_eq(actual, expected, msg: String = "") -> void:
	if actual != expected:
		fail("%s: %s != %s%s" % [_caller_test(), str(actual), str(expected), _suffix(msg)])


func assert_close(actual: float, expected: float, tol: float = 1.0e-6, msg: String = "") -> void:
	if not is_finite(actual) or not is_finite(expected):
		fail("%s: non-finite (%s vs %s)%s" % [_caller_test(), actual, expected, _suffix(msg)])
		return
	if absf(actual - expected) > tol:
		fail("%s: %.10g vs %.10g (tol %g)%s" % [
			_caller_test(), actual, expected, tol, _suffix(msg)
		])


func assert_vec_close(actual: Vector3, expected: Vector3, tol: float = 1.0e-6, msg: String = "") -> void:
	if not _vec_finite(actual) or not _vec_finite(expected):
		fail("%s: non-finite vector%s" % [_caller_test(), _suffix(msg)])
		return
	if (actual - expected).length() > tol:
		fail("%s: %s vs %s (tol %g)%s" % [
			_caller_test(), actual, expected, tol, _suffix(msg)
		])


func assert_finite(value, msg: String = "") -> void:
	var ok := false
	if value is float:
		ok = is_finite(value)
	elif value is Vector3:
		ok = _vec_finite(value)
	else:
		fail("%s: assert_finite called with unsupported type%s" % [_caller_test(), _suffix(msg)])
		return
	if not ok:
		fail("%s: not finite (%s)%s" % [_caller_test(), str(value), _suffix(msg)])


func _suffix(msg: String) -> String:
	return "" if msg == "" else " - " + msg


func _caller_test() -> String:
	if _current_test == "":
		return test_file_name()
	return "%s::%s" % [test_file_name(), _current_test]


static func _vec_finite(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)
