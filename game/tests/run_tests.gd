extends SceneTree
## Minimal dependency-free unit-test runner. Run via:
##   godot --headless --path game --script res://tests/run_tests.gd
##
## Discovers res://tests/unit/test_*.gd. Each test script extends RefCounted;
## every zero-argument method whose name starts with "test_" is executed and
## passes iff it returns true. (Roadmap: replace with vendored gdUnit4.)

const UNIT_DIR: String = "res://tests/unit"


func _initialize() -> void:
	var passed := 0
	var failed := 0

	var dir := DirAccess.open(UNIT_DIR)
	if dir == null:
		push_error("test runner: cannot open %s" % UNIT_DIR)
		quit(1)
		return

	for file in dir.get_files():
		if not (file.begins_with("test_") and file.ends_with(".gd")):
			continue
		var script: GDScript = load("%s/%s" % [UNIT_DIR, file])
		if script == null or not script.can_instantiate():
			# A parse error would otherwise abort _initialize before quit(),
			# hanging the headless run — count it and keep going instead.
			failed += 1
			push_error("FAIL %s :: does not load/compile" % file)
			continue
		var suite: RefCounted = script.new()
		for method in script.get_script_method_list():
			var method_name: String = method["name"]
			if not method_name.begins_with("test_") or method["args"].size() > 0:
				continue
			if suite.call(method_name) == true:
				passed += 1
			else:
				failed += 1
				push_error("FAIL %s :: %s" % [file, method_name])

	print("unit tests: %d passed, %d failed" % [passed, failed])
	if failed > 0 or passed == 0:
		quit(1)
	else:
		quit(0)
