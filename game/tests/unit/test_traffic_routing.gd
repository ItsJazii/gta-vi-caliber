extends RefCounted
## Unit tests for TrafficRouting — destination routing that keeps ambient cars on
## real streets, in the right lane.


func _grid() -> RoadNetwork:
	var net := RoadNetwork.new(1.0)
	# A connected lattice: three E-W streets and three N-S streets, 40 m apart.
	for z in [0.0, 40.0, 80.0]:
		net.add_polyline(
			PackedVector3Array([Vector3(0, 0, z), Vector3(40, 0, z), Vector3(80, 0, z)])
		)
	for x in [0.0, 40.0, 80.0]:
		net.add_polyline(
			PackedVector3Array([Vector3(x, 0, 0), Vector3(x, 0, 40), Vector3(x, 0, 80)])
		)
	net.build_spatial_index()
	return net


func test_right_of_north_is_east() -> bool:
	# Driving north (-Z), the right lane is east (+X) — right-hand traffic.
	return TrafficRouting.right_of(Vector3(0, 0, -1)).is_equal_approx(Vector3(1, 0, 0))


func test_right_of_east_is_south() -> bool:
	return TrafficRouting.right_of(Vector3(1, 0, 0)).is_equal_approx(Vector3(0, 0, 1))


func test_route_to_reaches_the_goal() -> bool:
	# Route from one corner toward the far corner; the last waypoint lands at the
	# goal (within a lane offset + a step).
	var pts := TrafficRouting.route_to(
		_grid(), Vector3(5, 0, 0), Vector3(80, 0, 80), Vector3(1, 0, 0), 2.0
	)
	if pts.size() < 2:
		return false
	var last := pts[pts.size() - 1]
	return Vector2(last.x, last.z).distance_to(Vector2(80, 80)) < 12.0


func test_route_to_waypoints_hug_the_streets() -> bool:
	var net := _grid()
	var pts := TrafficRouting.route_to(
		net, Vector3(5, 0, 0), Vector3(80, 0, 40), Vector3(1, 0, 0), 2.0
	)
	# A half-lane offset plus the rounding of a junction turn arc — never the wild
	# off-road excursions cars used to take.
	for p in pts:
		if float(net.nearest_point(p)["dist"]) > 4.0:
			return false
	return pts.size() >= 2


func test_route_turns_are_smooth() -> bool:
	# A route that must turn (east, then north): consecutive waypoint steps never
	# reverse direction. The turn is a smooth arc, not a sharp kink — the very
	# weave/circle bug this routing fixes (no jumping a lane to corner, then back).
	var pts := TrafficRouting.route_to(
		_grid(), Vector3(5, 0, 0), Vector3(40, 0, 80), Vector3(1, 0, 0), 2.0
	)
	if pts.size() < 3:
		return false
	var prev := Vector3.ZERO
	for i in range(1, pts.size()):
		var step := pts[i] - pts[i - 1]
		step.y = 0.0
		if step.length() < 0.001:
			continue
		step = step.normalized()
		if prev != Vector3.ZERO and prev.dot(step) < 0.25:
			return false
		prev = step
	return true


func test_route_keeps_right_and_does_not_cross_oncoming() -> bool:
	# Driving east along z=0 in the right lane sits at z>0 (south side). Every
	# waypoint up to the turn must stay on that side — never dip to z<0 (the
	# oncoming westbound lane) the way the old per-edge offset did at junctions.
	var pts := TrafficRouting.route_to(
		_grid(), Vector3(5, 0, 0), Vector3(40, 0, 80), Vector3(1, 0, 0), 2.0
	)
	for p in pts:
		# Before the x=40 junction, the car is on the east-west street: keep south.
		if p.x < 38.0 and p.z < -0.5:
			return false
	return pts.size() >= 2


func test_route_to_starts_forward() -> bool:
	# Heading east from near the origin, the first waypoint is east of the start.
	var pts := TrafficRouting.route_to(
		_grid(), Vector3(5, 0, 0), Vector3(80, 0, 0), Vector3(1, 0, 0), 0.0
	)
	return pts.size() >= 2 and pts[0].x >= 5.0 - 0.001


func test_route_to_empty_on_blank_network() -> bool:
	var net := RoadNetwork.new(1.0)
	return (
		TrafficRouting.route_to(net, Vector3.ZERO, Vector3(50, 0, 0), Vector3(1, 0, 0), 2.0).size()
		== 0
	)
