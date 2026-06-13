class_name TestInteraction
extends GdUnitTestSuite
## Unit tests for Interaction.nearest, the pure pick-the-target-in-reach math
## behind the player's context-sensitive interact key.


func test_no_points_gives_none() -> void:
	assert_int(Interaction.nearest(PackedVector3Array(), Vector3.ZERO, 3.0)).is_equal(
		Interaction.NONE
	)


func test_point_out_of_reach_is_ignored() -> void:
	var points := PackedVector3Array([Vector3(10, 0, 0)])
	assert_int(Interaction.nearest(points, Vector3.ZERO, 3.0)).is_equal(Interaction.NONE)


func test_point_within_reach_is_selected() -> void:
	var points := PackedVector3Array([Vector3(2, 0, 0)])
	assert_int(Interaction.nearest(points, Vector3.ZERO, 3.0)).is_equal(0)


func test_nearest_of_several_wins() -> void:
	var points := PackedVector3Array([Vector3(2.5, 0, 0), Vector3(1.0, 0, 0), Vector3(2.0, 0, 0)])
	assert_int(Interaction.nearest(points, Vector3.ZERO, 3.0)).is_equal(1)


func test_reach_boundary_is_inclusive() -> void:
	var points := PackedVector3Array([Vector3(3, 0, 0)])
	assert_int(Interaction.nearest(points, Vector3.ZERO, 3.0)).is_equal(0)


func test_ties_resolve_to_lower_index() -> void:
	var points := PackedVector3Array([Vector3(2, 0, 0), Vector3(0, 0, 2)])
	assert_int(Interaction.nearest(points, Vector3.ZERO, 3.0)).is_equal(0)


func test_non_positive_reach_selects_nothing() -> void:
	var points := PackedVector3Array([Vector3(0, 0, 0)])
	assert_int(Interaction.nearest(points, Vector3.ZERO, 0.0)).is_equal(Interaction.NONE)
