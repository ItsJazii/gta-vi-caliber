extends RefCounted
## Unit tests for RoadKeepout — the pedestrian off-the-road math (see
## tests/run_tests.gd for the runner contract: test_* methods return true to
## pass). A single straight road down the Z axis at x=0 makes every expected
## distance just |x|, so the assertions read off by hand.


# A straight road along Z at x=0, from z=-50 to z=50 — nearest-centreline
# distance for any nearby point is simply its |x|.
func _straight_road() -> RoadNetwork:
	var net := RoadNetwork.new(2.0)
	net.add_polyline(PackedVector3Array([Vector3(0, 0, -50), Vector3(0, 0, 50)]))
	net.build_spatial_index()
	return net


func _keepout(clearance: float = 7.0) -> RoadKeepout:
	return RoadKeepout.new(_straight_road(), clearance)


func test_nearest_dist_is_planar() -> bool:
	# y is ignored — distance is the XZ gap to the centreline (|x| here).
	return is_equal_approx(_keepout().nearest_dist(Vector3(4.0, 9.0, 10.0)), 4.0)


func test_clear_far_from_road() -> bool:
	return _keepout(7.0).is_clear(Vector3(12.0, 0.0, 0.0))


func test_not_clear_on_road() -> bool:
	return not _keepout(7.0).is_clear(Vector3(3.0, 0.0, 0.0))


func test_clear_exactly_at_clearance() -> bool:
	# >= clearance counts as clear (a point sitting on the keep-out line is fine).
	return _keepout(7.0).is_clear(Vector3(7.0, 0.0, 0.0))


func test_push_clear_moves_out_to_band_edge() -> bool:
	var out := _keepout(7.0).push_clear(Vector3(3.0, 0.0, 5.0))
	# Pushed to clearance + margin (7.5) on the same (+x) side, z preserved.
	return is_equal_approx(out.x, 7.5) and is_equal_approx(out.z, 5.0)


func test_push_clear_preserves_side() -> bool:
	# A point on the -x side is pushed further -x, never flung across the road.
	return _keepout(7.0).push_clear(Vector3(-2.0, 0.0, 0.0)).x < 0.0


func test_push_clear_preserves_height() -> bool:
	return is_equal_approx(_keepout(7.0).push_clear(Vector3(3.0, 8.0, 0.0)).y, 8.0)


func test_push_clear_noop_when_already_clear() -> bool:
	var p := Vector3(10.0, 0.0, 0.0)
	return _keepout(7.0).push_clear(p).is_equal_approx(p)


func test_deflect_blocks_straight_into_road() -> bool:
	# Walking straight at the road from inside the band leaves no legal motion.
	var d := _keepout(7.0).deflect(Vector3(3.0, 0.0, 0.0), Vector3(-1.0, 0.0, 0.0))
	return d.length() < 0.0001


func test_deflect_allows_along_road() -> bool:
	# Parallel to the road is untouched — peds walk the kerb freely.
	var d := _keepout(7.0).deflect(Vector3(3.0, 0.0, 0.0), Vector3(0.0, 0.0, 1.0))
	return d.is_equal_approx(Vector3(0.0, 0.0, 1.0))


func test_deflect_slides_diagonal_along_kerb() -> bool:
	# A diagonal heading into the road loses its roadward component and keeps the
	# along-road component, renormalised to the original speed (1).
	var dir := Vector3(-1.0, 0.0, 1.0).normalized()
	var d := _keepout(7.0).deflect(Vector3(3.0, 0.0, 0.0), dir)
	return absf(d.x) < 0.0001 and is_equal_approx(d.z, 1.0)


func test_deflect_noop_when_clear() -> bool:
	var dir := Vector3(-1.0, 0.0, 0.0)
	return _keepout(7.0).deflect(Vector3(10.0, 0.0, 0.0), dir).is_equal_approx(dir)


func test_origin_offset_maps_scene_to_graph() -> bool:
	# With the world shifted +100x, a scene point at x=103 maps to graph x=3.
	var k := _keepout(7.0)
	k.set_origin_offset(Vector3(100.0, 0.0, 0.0))
	var scene_pt := Vector3(103.0, 0.0, 0.0)
	var dist_ok := is_equal_approx(k.nearest_dist(scene_pt), 3.0)
	var blocked := not k.is_clear(scene_pt)
	var pushed := is_equal_approx(k.push_clear(scene_pt).x, 107.5)
	return dist_ok and blocked and pushed


func test_no_network_treats_everywhere_as_clear() -> bool:
	var k := RoadKeepout.new(null, 7.0)
	var p := Vector3(0.0, 0.0, 0.0)
	var dir := Vector3(1.0, 0.0, 0.0)
	return (
		k.nearest_dist(p) == INF
		and k.is_clear(p)
		and k.push_clear(p).is_equal_approx(p)
		and k.deflect(p, dir).is_equal_approx(dir)
	)
