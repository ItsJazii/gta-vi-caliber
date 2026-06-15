extends RefCounted
## Unit tests for TrafficJunctions — the pure junction-selection + approach maths
## behind the ambient-traffic signal layer (issue #61). test_* methods return
## true to pass (see tests/run_tests.gd).


## A plus-shaped crossing of two two-way streets meeting at the origin.
func _cross_network() -> RoadNetwork:
	var net := RoadNetwork.new(2.0)
	net.add_polyline(PackedVector3Array([Vector3(-10, 0, 0), Vector3(0, 0, 0), Vector3(10, 0, 0)]))
	net.add_polyline(PackedVector3Array([Vector3(0, 0, -10), Vector3(0, 0, 0), Vector3(0, 0, 10)]))
	return net


func test_find_signalled_picks_the_crossing() -> bool:
	var found := TrafficJunctions.find_signalled(_cross_network(), 4, 5.0)
	return found.size() == 1 and (found[0]["pos"] as Vector3).is_equal_approx(Vector3.ZERO)


func test_find_signalled_ignores_a_straight_road() -> bool:
	var net := RoadNetwork.new(2.0)
	# Interior vertices of one polyline have degree 2 (next + prev) — not junctions.
	net.add_polyline(PackedVector3Array([Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(20, 0, 0)]))
	return TrafficJunctions.find_signalled(net, 4, 5.0).is_empty()


func test_find_signalled_skips_a_t_junction() -> bool:
	var net := RoadNetwork.new(2.0)
	# A straight street with a side road teeing in: the tee node has 3 arms (the
	# through road's two + the side road's one) — a T-junction, NOT a 4-way crossing.
	# Only real crossroads get a light, so this yields nothing.
	net.add_polyline(PackedVector3Array([Vector3(-10, 0, 0), Vector3(0, 0, 0), Vector3(10, 0, 0)]))
	net.add_polyline(PackedVector3Array([Vector3(0, 0, 0), Vector3(0, 0, 10)]))
	return TrafficJunctions.find_signalled(net, 4, 5.0).is_empty()


func test_find_signalled_respects_max_and_spacing() -> bool:
	var net := _cross_network()
	# A second crossing 8 m away.
	net.add_polyline(PackedVector3Array([Vector3(-2, 0, 8), Vector3(8, 0, 8), Vector3(18, 0, 8)]))
	net.add_polyline(PackedVector3Array([Vector3(8, 0, -2), Vector3(8, 0, 8), Vector3(8, 0, 18)]))
	# Two junctions exist, but a 20 m spacing floor admits only the first.
	var spaced := TrafficJunctions.find_signalled(net, 4, 20.0)
	# And a max_count of 1 caps it regardless of spacing.
	var capped := TrafficJunctions.find_signalled(net, 1, 1.0)
	return spaced.size() == 1 and capped.size() == 1


func test_junction_frame_offsets_pole_off_the_carriageway() -> bool:
	# A plus crossing: roads along X and Z, so the kerb corner sits diagonally
	# 5 m along each axis from the centre — never on the roadway.
	var net := _cross_network()
	var found := TrafficJunctions.find_signalled(net, 4, 5.0)
	if found.is_empty():
		return false
	var frame := TrafficJunctions.junction_frame(net, found[0]["node"], 5.0)
	var corner: Vector3 = frame["corner_offset"]
	return (
		(frame["center"] as Vector3).is_equal_approx(Vector3.ZERO)
		and is_equal_approx(absf(corner.x), 5.0)
		and is_equal_approx(absf(corner.z), 5.0)
	)


func test_axis_for_classifies_ns_and_ew() -> bool:
	return (
		TrafficJunctions.axis_for(Vector3(0, 0, -1)) == TrafficSignal.Axis.NS
		and TrafficJunctions.axis_for(Vector3(1, 0, 0)) == TrafficSignal.Axis.EW
		and TrafficJunctions.axis_for(Vector3(0.1, 0, 0.9)) == TrafficSignal.Axis.NS
		and TrafficJunctions.axis_for(Vector3(0.9, 0, 0.1)) == TrafficSignal.Axis.EW
	)


func test_should_hold_stops_on_red_but_not_green() -> bool:
	var j := Vector3.ZERO
	var car := Vector3(0, 0, 10)  # 10 m south of the junction
	var heading := Vector3(0, 0, -1)  # driving north, into the junction
	var on_red := TrafficJunctions.should_hold(
		j, car, heading, 8.0, TrafficSignal.Light.RED, 16.0, 6.0, 6.0
	)
	var on_green := TrafficJunctions.should_hold(
		j, car, heading, 8.0, TrafficSignal.Light.GREEN, 16.0, 6.0, 6.0
	)
	return on_red and not on_green


func test_should_hold_ignores_car_in_box_or_leaving() -> bool:
	var j := Vector3.ZERO
	# Already inside the stop line (4 m < 6 m): let it clear, never freeze.
	var in_box := TrafficJunctions.should_hold(
		j, Vector3(0, 0, 4), Vector3(0, 0, -1), 8.0, TrafficSignal.Light.RED, 16.0, 6.0, 6.0
	)
	# Heading away from the junction: not our approach.
	var leaving := TrafficJunctions.should_hold(
		j, Vector3(0, 0, 10), Vector3(0, 0, 1), 8.0, TrafficSignal.Light.RED, 16.0, 6.0, 6.0
	)
	# Beyond the watch zone (24 m > 16 m): too far to care yet.
	var too_far := TrafficJunctions.should_hold(
		j, Vector3(0, 0, 24), Vector3(0, 0, -1), 8.0, TrafficSignal.Light.RED, 16.0, 6.0, 6.0
	)
	return not in_box and not leaving and not too_far
