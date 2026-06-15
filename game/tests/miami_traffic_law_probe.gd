extends SceneTree
## Integration probe for the ambient-traffic signal layer (issue #61, LC4): boots
## miami.tscn, waits for the TrafficSignalField to build, then asserts real
## signalled junctions exist and that a live light actually gates an approaching
## car — held on red, released on green. The phase maths is unit-tested in
## test_traffic_signal/test_traffic_junctions; this proves the wiring in the
## playable scene. Run headless:
##   godot --headless --path game --script res://tests/miami_traffic_law_probe.gd

const SCENE_PATH: String = "res://scenes/world/miami.tscn"
const WARMUP_FRAMES: int = 120
## The field builds its road graphs on a worker thread, so wait (wall-clock, up
## to this long) for the junctions to appear — headless races through frames
## faster than the worker finishes, so a fixed frame count would check too early.
const MAX_WAIT_MSEC: int = 20000

var _scene: Node = null
var _frames: int = 0
var _started_msec: int = 0
var _failures: PackedStringArray = []


func _initialize() -> void:
	var packed: PackedScene = load(SCENE_PATH)
	if packed == null:
		push_error("miami traffic law probe: scene failed to load")
		quit(1)
		return
	_scene = packed.instantiate()
	root.add_child(_scene)
	_started_msec = Time.get_ticks_msec()


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < WARMUP_FRAMES:
		return false
	# Wait for the field's threaded road-graph build to finish before asserting.
	var field := get_first_node_in_group("traffic_signal_field") as TrafficSignalField
	if (
		field != null
		and field.junction_count() == 0
		and Time.get_ticks_msec() - _started_msec < MAX_WAIT_MSEC
	):
		return false
	_run_checks()
	return _finish()


func _run_checks() -> void:
	var field := get_first_node_in_group("traffic_signal_field") as TrafficSignalField
	if field == null:
		_failures.append("no TrafficSignalField in the scene")
		return
	if field.junction_count() == 0:
		_failures.append("TrafficSignalField built no signalled junctions")
		return

	# Force every junction to a known phase: NS green, EW red.
	field.reset_all()
	var c := field.junction_center(0)

	# A car approaching along NS (driving north, -Z) on green must NOT be held.
	if field.must_hold(c + Vector3(0.0, 0.0, 10.0), Vector3(0, 0, -1), 8.0):
		_failures.append("car held on green (NS) — should pass")

	# A car approaching along EW (driving east, +X) on red MUST be held.
	if not field.must_hold(c + Vector3(-10.0, 0.0, 0.0), Vector3(1, 0, 0), 8.0):
		_failures.append("car not held on red (EW) — should stop")

	# All-red clearance: between the NS and EW greens every approach is held for a
	# beat so the box empties. From the reset NS-green, step through NS green + yellow
	# into the all-red interval and assert BOTH a NS-bound and an EW-bound car hold.
	field.reset_all()
	field.advance_all(field.green_time + field.yellow_time + 0.5 * field.all_red_time)
	if not field.must_hold(c + Vector3(0.0, 0.0, 10.0), Vector3(0, 0, -1), 8.0):
		_failures.append("car not held during all-red (NS) — box should be clearing")
	if not field.must_hold(c + Vector3(-10.0, 0.0, 0.0), Vector3(1, 0, 0), 8.0):
		_failures.append("car not held during all-red (EW) — box should be clearing")

	# Timings must clear before the director's stuck cull: a car can stop at the start
	# of its yellow and then wait its yellow + the cross green + cross yellow + both
	# all-reds before its own green. If that worst-case standstill reaches the cull
	# timeout, a car waiting out a normal cycle gets despawned mid-wait. Guard the LIVE
	# field's actual exports so a future retune past the budget fails here.
	var stuck_timeout := 10.0  # mirror of TrafficDirector.stuck_timeout
	var restart_slack := 1.0  # release-to-first-qualifying-move tail before stuck resets
	var worst_wait := field.green_time + 2.0 * field.yellow_time + 2.0 * field.all_red_time
	if worst_wait >= stuck_timeout - restart_slack:
		_failures.append(
			(
				"signal worst-case wait %.2fs too close to the %.0fs stuck cull"
				% [worst_wait, stuck_timeout]
			)
		)


func _finish() -> bool:
	if _failures.is_empty():
		var field := get_first_node_in_group("traffic_signal_field") as TrafficSignalField
		var n := field.junction_count() if field != null else 0
		print("miami traffic law probe: OK (%d signalled junctions, red holds / green passes)" % n)
		quit(0)
	else:
		for failure in _failures:
			push_error("miami traffic law probe FAIL :: %s" % failure)
		print("miami traffic law probe: %d failure(s)" % _failures.size())
		quit(1)
	return true
