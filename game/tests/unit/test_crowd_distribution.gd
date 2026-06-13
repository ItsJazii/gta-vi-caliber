extends RefCounted
## Unit tests for CrowdDistribution (see tests/run_tests.gd for the runner
## contract: test_* methods return true to pass).


func test_spawn_offset_inside_annulus() -> bool:
	# Every sample across the unit square must land within [min, max] of origin.
	for i in range(0, 11):
		for j in range(0, 11):
			var o := CrowdDistribution.spawn_offset(18.0, 32.0, float(i) / 10.0, float(j) / 10.0)
			var r := Vector2(o.x, o.z).length()
			if r < 18.0 - 0.001 or r > 32.0 + 0.001:
				return false
	return true


func test_spawn_offset_is_planar() -> bool:
	return is_equal_approx(CrowdDistribution.spawn_offset(5.0, 10.0, 0.7, 0.3).y, 0.0)


func test_spawn_offset_inner_edge_at_u_zero() -> bool:
	var r := (
		Vector2(
			CrowdDistribution.spawn_offset(20.0, 40.0, 0.0, 0.25).x,
			CrowdDistribution.spawn_offset(20.0, 40.0, 0.0, 0.25).z
		)
		. length()
	)
	return is_equal_approx(r, 20.0)


func test_spawn_offset_outer_edge_at_u_one() -> bool:
	var o := CrowdDistribution.spawn_offset(20.0, 40.0, 1.0, 0.6)
	return is_equal_approx(Vector2(o.x, o.z).length(), 40.0)


func test_spawn_offset_area_uniform_midpoint() -> bool:
	# u = 0.5 should fall at the equal-area radius sqrt((lo^2+hi^2)/2), which is
	# beyond the arithmetic midpoint — proving the area-uniform weighting.
	var o := CrowdDistribution.spawn_offset(0.0, 10.0, 0.5, 0.0)
	return is_equal_approx(Vector2(o.x, o.z).length(), sqrt(50.0))


func test_should_despawn_beyond_cull() -> bool:
	return CrowdDistribution.should_despawn(45.0, 44.0)


func test_should_not_despawn_within_cull() -> bool:
	return not CrowdDistribution.should_despawn(40.0, 44.0)


func test_spawn_count_fills_deficit_within_budget() -> bool:
	return CrowdDistribution.spawn_count(5, 12, 3) == 3


func test_spawn_count_caps_at_deficit() -> bool:
	return CrowdDistribution.spawn_count(10, 12, 5) == 2


func test_spawn_count_zero_when_full() -> bool:
	return CrowdDistribution.spawn_count(12, 12, 3) == 0


func test_spawn_count_zero_when_over_target() -> bool:
	return CrowdDistribution.spawn_count(15, 12, 3) == 0


func test_citizen_slot_zero_fraction_never() -> bool:
	for slot in 50:
		if CrowdDistribution.is_citizen_slot(slot, 0.0):
			return false
	return true


func test_citizen_slot_full_fraction_always() -> bool:
	for slot in 50:
		if not CrowdDistribution.is_citizen_slot(slot, 1.0):
			return false
	return true


func test_citizen_slot_hits_exact_fraction_over_run() -> bool:
	var citizens := 0
	for slot in 100:
		if CrowdDistribution.is_citizen_slot(slot, 0.35):
			citizens += 1
	return citizens == 35


func test_citizen_slot_half_fraction_alternates() -> bool:
	# f = 0.5 should yield exactly one citizen per consecutive pair.
	for pair in 10:
		var a := CrowdDistribution.is_citizen_slot(pair * 2, 0.5)
		var b := CrowdDistribution.is_citizen_slot(pair * 2 + 1, 0.5)
		if int(a) + int(b) != 1:
			return false
	return true
