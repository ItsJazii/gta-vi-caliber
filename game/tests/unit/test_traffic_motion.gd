extends RefCounted
## Unit tests for TrafficMotion (see tests/run_tests.gd for the runner contract:
## test_* methods return true to pass).


func test_planar_distance_ignores_height() -> bool:
	return is_equal_approx(TrafficMotion.planar_distance(Vector3(0, 9, 0), Vector3(3, -2, 4)), 5.0)


func test_planar_dir_is_unit_and_flat() -> bool:
	var d := TrafficMotion.planar_dir(Vector3(0, 0, 0), Vector3(3, 7, 4))
	return is_equal_approx(d.length(), 1.0) and is_equal_approx(d.y, 0.0)


func test_turn_toward_snaps_when_within_step() -> bool:
	var h := Vector3(1, 0, 0)
	var desired := Vector3(0, 0, 1)
	# max_step larger than the 90° gap → snap straight to desired.
	var out := TrafficMotion.turn_toward(h, desired, PI)
	return out.is_equal_approx(desired)


func test_turn_toward_is_capped() -> bool:
	var h := Vector3(1, 0, 0)
	var desired := Vector3(-1, 0, 0)  # 180° away
	var out := TrafficMotion.turn_toward(h, desired, deg_to_rad(10.0))
	# Should have rotated only ~10°, so still close to the original heading.
	var moved := rad_to_deg(acos(clampf(h.dot(out), -1.0, 1.0)))
	return absf(moved - 10.0) < 0.5 and is_equal_approx(out.length(), 1.0)


func test_turn_toward_holds_on_zero_desired() -> bool:
	var h := Vector3(0, 0, 1)
	return TrafficMotion.turn_toward(h, Vector3.ZERO, 1.0).is_equal_approx(h)


func test_step_advances_along_heading() -> bool:
	# Target straight ahead: car moves forward by speed*delta, heading unchanged.
	var r := TrafficMotion.step(Vector3.ZERO, Vector3(0, 0, 1), Vector3(0, 0, 100), 10.0, 5.0, 0.1)
	var p: Vector3 = r["position"]
	return is_equal_approx(p.z, 1.0) and is_equal_approx(p.x, 0.0)


func test_step_preserves_y() -> bool:
	var r := TrafficMotion.step(
		Vector3(0, 4, 0), Vector3(1, 0, 0), Vector3(50, 4, 0), 8.0, 4.0, 0.25
	)
	return is_equal_approx((r["position"] as Vector3).y, 4.0)


func test_step_heading_stays_unit() -> bool:
	var r := TrafficMotion.step(Vector3.ZERO, Vector3(1, 0, 0), Vector3(0, 0, 9), 6.0, 2.0, 0.1)
	return is_equal_approx((r["heading"] as Vector3).length(), 1.0)


func test_advance_waypoint_skips_reached() -> bool:
	var wp := PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(20, 0, 0)])
	# Standing on waypoint 0 within tolerance → cursor moves past 0 and 1? Only 0:
	# we're at origin, wp1 is 1 m away (within tol 1.5) so it skips both 0 and 1.
	return TrafficMotion.advance_waypoint(Vector3(0, 0, 0), wp, 0, 1.5) == 2


func test_advance_waypoint_holds_when_far() -> bool:
	var wp := PackedVector3Array([Vector3(10, 0, 0), Vector3(20, 0, 0)])
	return TrafficMotion.advance_waypoint(Vector3(0, 0, 0), wp, 0, 1.0) == 0


func test_advance_waypoint_finishes_route() -> bool:
	var wp := PackedVector3Array([Vector3(0, 0, 0)])
	return TrafficMotion.advance_waypoint(Vector3(0, 0, 0), wp, 0, 1.0) == 1


func test_corner_speed_full_when_aligned() -> bool:
	# Heading straight at the target → no slow-down.
	return absf(TrafficMotion.corner_speed_scale(Vector3(1, 0, 0), Vector3(1, 0, 0)) - 1.0) < 0.01


func test_corner_speed_floors_on_right_angle() -> bool:
	# 90° off → clamp to the minimum so the car crawls through the tight arc.
	return (
		absf(TrafficMotion.corner_speed_scale(Vector3(1, 0, 0), Vector3(0, 0, 1), 0.4) - 0.4) < 0.01
	)


func test_corner_speed_floors_on_reverse() -> bool:
	return (
		absf(TrafficMotion.corner_speed_scale(Vector3(1, 0, 0), Vector3(-1, 0, 0), 0.4) - 0.4)
		< 0.01
	)


func test_corner_speed_holds_on_zero_desired() -> bool:
	return is_equal_approx(TrafficMotion.corner_speed_scale(Vector3(1, 0, 0), Vector3.ZERO), 1.0)
