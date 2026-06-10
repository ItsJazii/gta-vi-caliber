extends RefCounted
## Unit tests for RoadNetwork — the graph traffic drives on.


func _line(a: Vector3, b: Vector3) -> PackedVector3Array:
	return PackedVector3Array([a, b])


func test_single_segment_is_two_way() -> bool:
	var net := RoadNetwork.new(1.0)
	net.add_polyline(_line(Vector3(0, 0, 0), Vector3(10, 0, 0)))
	# 2 nodes, 2 directed segments (a→b and b→a).
	return net.node_count() == 2 and net.segment_count() == 2


func test_shared_endpoints_merge_into_junction() -> bool:
	var net := RoadNetwork.new(1.0)
	net.add_polyline(_line(Vector3(0, 0, 0), Vector3(10, 0, 0)))
	net.add_polyline(_line(Vector3(10, 0, 0), Vector3(10, 0, 10)))
	# Shared point (10,0,0) → 3 nodes, 4 directed segments.
	return net.node_count() == 3 and net.segment_count() == 4


func test_close_points_snap_together() -> bool:
	var net := RoadNetwork.new(2.0)
	net.add_polyline(_line(Vector3(0, 0, 0), Vector3(10, 0, 0)))
	# Endpoint 0.5 m away from a node snaps onto it (within 2 m grid).
	net.add_polyline(_line(Vector3(10.5, 0, 0.2), Vector3(20, 0, 0)))
	return net.node_count() == 3


func test_segments_from_junction() -> bool:
	var net := RoadNetwork.new(1.0)
	net.add_polyline(_line(Vector3(0, 0, 0), Vector3(10, 0, 0)))
	net.add_polyline(_line(Vector3(10, 0, 0), Vector3(10, 0, 10)))
	# From the central junction there are outgoing segments back and onward.
	var junction := -1
	for i in net.node_count():
		if net.nodes[i].is_equal_approx(Vector3(10, 0, 0)):
			junction = i
	return junction != -1 and net.segments_from(junction).size() == 2


func test_point_on_segment_endpoints_and_midpoint() -> bool:
	var net := RoadNetwork.new(1.0)
	net.add_polyline(_line(Vector3(0, 0, 0), Vector3(10, 0, 0)))
	var start: Dictionary = net.point_on_segment(0, 0.0)
	var mid: Dictionary = net.point_on_segment(0, 5.0)
	var done: Dictionary = net.point_on_segment(0, 10.0)
	return (
		(start["pos"] as Vector3).is_equal_approx(Vector3(0, 0, 0))
		and (mid["pos"] as Vector3).is_equal_approx(Vector3(5, 0, 0))
		and (done["pos"] as Vector3).is_equal_approx(Vector3(10, 0, 0))
	)


func test_heading_is_unit_along_segment() -> bool:
	var net := RoadNetwork.new(1.0)
	net.add_polyline(_line(Vector3(0, 0, 0), Vector3(0, 0, 8)))
	var h: Vector3 = net.point_on_segment(0, 2.0)["heading"]
	return absf(h.length() - 1.0) < 0.001 and h.is_equal_approx(Vector3(0, 0, 1))


func test_offset_clamps_past_segment_end() -> bool:
	var net := RoadNetwork.new(1.0)
	net.add_polyline(_line(Vector3(0, 0, 0), Vector3(10, 0, 0)))
	var p: Vector3 = net.point_on_segment(0, 999.0)["pos"]
	return p.is_equal_approx(Vector3(10, 0, 0))
