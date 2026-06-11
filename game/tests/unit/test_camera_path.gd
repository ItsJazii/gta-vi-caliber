extends RefCounted
## Unit tests for CameraPath — Catmull-Rom flythrough math. It must pass through
## every control point and stay continuous, or the trailer camera judders.

var _pts := [Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(10, 0, 10), Vector3(0, 0, 10)]


func test_starts_at_first_point() -> bool:
	return CameraPath.sample(_pts, 0.0).is_equal_approx(Vector3(0, 0, 0))


func test_ends_at_last_point() -> bool:
	return CameraPath.sample(_pts, 1.0).is_equal_approx(Vector3(0, 0, 10))


func test_passes_through_interior_point() -> bool:
	# With 4 points (3 segments), t = 1/3 lands exactly on points[1].
	return CameraPath.sample(_pts, 1.0 / 3.0).is_equal_approx(Vector3(10, 0, 0))


func test_straight_run_advances_monotonically() -> bool:
	# Along a collinear path, x must increase steadily from 0 to 4 (no backtrack).
	var line := [Vector3(0, 0, 0), Vector3(2, 0, 0), Vector3(4, 0, 0)]
	var prev := -INF
	var t := 0.0
	while t <= 1.0:
		var x := CameraPath.sample(line, t).x
		if x < prev - 0.001:
			return false
		prev = x
		t += 0.1
	return true


func test_empty_and_single_are_safe() -> bool:
	return (
		CameraPath.sample([], 0.5) == Vector3.ZERO
		and CameraPath.sample([Vector3(3, 4, 5)], 0.7) == Vector3(3, 4, 5)
	)


func test_is_continuous_no_jumps() -> bool:
	# Tiny steps in t must produce tiny steps in position (no segment seam jumps).
	var prev := CameraPath.sample(_pts, 0.0)
	var t := 0.02
	while t <= 1.0:
		var cur := CameraPath.sample(_pts, t)
		if prev.distance_to(cur) > 1.5:  # each 0.02 step is well under a unit hop
			return false
		prev = cur
		t += 0.02
	return true
