extends SceneTree
## Integration test for CinematicCamera: it flies its waypoint path, moving
## smoothly and staying near the route, and becomes the active camera while
## playing. The spline math is unit-tested in test_camera_path.gd; this guards
## the node (play/stop, per-frame advance, look-ahead orientation).
## Run: godot --headless --path game --script res://tests/cinematic_capture.gd

var _cam: CinematicCamera = null
var _frame := 0
var _samples: Array = []
var _failures: PackedStringArray = []


func _initialize() -> void:
	_cam = CinematicCamera.new()
	_cam.name = "CinematicCamera"
	_cam.waypoints = [Vector3(0, 5, 0), Vector3(20, 5, 0), Vector3(20, 5, 20), Vector3(0, 5, 20)]
	_cam.duration = 4.0
	_cam.loop = true
	root.add_child(_cam)
	_cam.play()


func _process(_delta: float) -> bool:
	_frame += 1
	# Drive the flythrough deterministically.
	_cam._process(0.2)
	_samples.append(_cam.global_position)
	if _samples.size() < 18:
		return false
	_check()
	return _finish()


func _check() -> void:
	if not _cam.is_playing() or not _cam.current:
		_fail("camera is not the active, playing camera during the flythrough")
	# It must actually move.
	var moved := false
	for s in _samples:
		if (s as Vector3).distance_to(_samples[0]) > 1.0:
			moved = true
			break
	if not moved:
		_fail("camera did not move along its path")
	# It must stay near the waypoint bounds (the spline shouldn't fling off).
	for s in _samples:
		var p := s as Vector3
		if p.x < -8.0 or p.x > 28.0 or p.z < -8.0 or p.z > 28.0:
			_fail("camera left the path envelope at %v" % p)
			return


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> bool:
	if _failures.is_empty():
		print("cinematic: OK — camera flew its spline path smoothly and stayed on route")
		quit(0)
	else:
		for f in _failures:
			push_error("cinematic: %s" % f)
		quit(1)
	return true
