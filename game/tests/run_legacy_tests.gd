extends SceneTree
## Runs the legacy unit suites: every res://tests/unit/test_*.gd that predates
## the gdUnit4 port (issue #3) — plain RefCounted scripts whose contract is
## `func test_*() -> bool`. gdUnit4's discoverer only picks up GdUnitTestSuite
## scripts, so without this runner the legacy suites (the bulk of the project's
## tests) silently stop gating CI.
## Run: godot --headless --path game --script res://tests/run_legacy_tests.gd

const UNIT_DIR := "res://tests/unit"

var _failures: PackedStringArray = []
var _suites: int = 0
var _cases: int = 0


func _initialize() -> void:
	for path in _suite_paths(UNIT_DIR):
		_run_suite(path)
	if _failures.is_empty():
		print("legacy unit tests: OK (%d suites, %d cases)" % [_suites, _cases])
		quit(0)
	else:
		for failure in _failures:
			push_error("legacy unit tests FAIL :: %s" % failure)
		print(
			(
				"legacy unit tests: %d failure(s) across %d suites, %d cases"
				% [_failures.size(), _suites, _cases]
			)
		)
		quit(1)


func _run_suite(path: String) -> void:
	var script: GDScript = load(path)
	if script == null:
		_failures.append("%s: failed to load" % path)
		return
	var instance: Object = script.new()
	if instance is GdUnitTestSuite:
		# gdUnit4 owns these (tests/run_tests.gd); don't double-run them.
		(instance as Node).free()
		return
	_suites += 1
	for method_info in script.get_script_method_list():
		var method_name: String = method_info["name"]
		if not method_name.begins_with("test_"):
			continue
		if not (method_info["args"] as Array).is_empty():
			continue
		_cases += 1
		var result: Variant = instance.call(method_name)
		if typeof(result) != TYPE_BOOL or not bool(result):
			_failures.append("%s :: %s" % [path, method_name])
	if instance is Node:
		(instance as Node).free()


## All test_*.gd scripts under `dir_path`, recursively, sorted for stable order.
func _suite_paths(dir_path: String) -> PackedStringArray:
	var found: PackedStringArray = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			if not entry.begins_with("."):
				found.append_array(_suite_paths(full))
		elif entry.begins_with("test_") and entry.ends_with(".gd"):
			found.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	found.sort()
	return found
