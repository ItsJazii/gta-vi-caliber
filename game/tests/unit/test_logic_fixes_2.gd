class_name TestLogicFixes2
extends GdUnitTestSuite
## Regression tests for two more correctness fixes from the bug-hunt backlog:
##   - PlayerStats.add_money flooring the wallet at zero (was able to go negative)
##   - NpcSteering.separation preserving inverse-falloff magnitude (a lone distant
##     neighbour used to shove exactly as hard as one at the elbow)


func test_add_money_floors_at_zero() -> void:
	var stats: PlayerStats = auto_free(PlayerStats.new())
	add_child(stats)  # _ready seeds money = starting_money (1500)
	stats.add_money(-5000)  # a fine larger than the balance
	assert_int(stats.money).is_equal(0)


func test_add_money_still_adds_normally() -> void:
	var stats: PlayerStats = auto_free(PlayerStats.new())
	add_child(stats)
	var before := stats.money
	stats.add_money(500)
	assert_int(stats.money).is_equal(before + 500)


func test_separation_magnitude_falls_off_with_distance() -> void:
	# A neighbour at the elbow must push harder than one at arm's length; the old
	# normalize()*max_speed made both identical.
	var near := NpcSteering.separation(Vector3.ZERO, [Vector3(1.0, 0.0, 0.0)], 5.0, 4.0)
	var far := NpcSteering.separation(Vector3.ZERO, [Vector3(4.9, 0.0, 0.0)], 5.0, 4.0)
	assert_float(near.length()).is_greater(far.length())


func test_separation_clamps_dense_crowd_to_max_speed() -> void:
	# Several close crowders on the SAME side sum to ~3.5 (> max_speed 2), so the
	# result must clamp to exactly max_speed.
	var crowd := [
		Vector3(0.3, 0.0, 0.0),
		Vector3(0.5, 0.0, 0.0),
		Vector3(0.7, 0.0, 0.0),
		Vector3(0.9, 0.0, 0.0),
	]
	var push := NpcSteering.separation(Vector3.ZERO, crowd, 5.0, 2.0)
	assert_float(push.length()).is_equal_approx(2.0, 0.001)
