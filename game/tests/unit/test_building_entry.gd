class_name TestBuildingEntry
extends GdUnitTestSuite
## Unit tests for BuildingEntry, the pure recentre/placement math behind walking
## into a building interior.

const EPSILON := Vector2.ONE * 0.0001


func test_centroid_of_unit_square_is_centre() -> void:
	var square := PackedVector2Array([Vector2(0, 0), Vector2(4, 0), Vector2(4, 4), Vector2(0, 4)])
	assert_vector(BuildingEntry.centroid(square)).is_equal_approx(Vector2(2, 2), EPSILON)


func test_centroid_of_empty_is_zero() -> void:
	assert_vector(BuildingEntry.centroid(PackedVector2Array())).is_equal(Vector2.ZERO)


func test_recenter_moves_centroid_to_origin() -> void:
	var square := PackedVector2Array(
		[Vector2(10, 10), Vector2(14, 10), Vector2(14, 14), Vector2(10, 14)]
	)
	var centred := BuildingEntry.recenter(square, BuildingEntry.centroid(square))
	assert_vector(BuildingEntry.centroid(centred)).is_equal_approx(Vector2.ZERO, EPSILON)


func test_entry_pulls_inward_from_door_by_inset() -> void:
	# Door 5 m out along +x, inset 1.5 m -> player at 3.5 m out.
	var entry := BuildingEntry.entry_offset(Vector2(5, 0), 1.5)
	assert_vector(entry).is_equal_approx(Vector2(3.5, 0), EPSILON)


func test_entry_never_overshoots_centre() -> void:
	# Inset larger than the door distance clamps to the centre, not past it.
	var entry := BuildingEntry.entry_offset(Vector2(1, 0), 5.0)
	assert_vector(entry).is_equal_approx(Vector2.ZERO, EPSILON)


func test_entry_of_zero_door_is_zero() -> void:
	assert_vector(BuildingEntry.entry_offset(Vector2.ZERO, 1.5)).is_equal(Vector2.ZERO)


func test_entry_keeps_door_direction() -> void:
	# Diagonal door: the inward point stays on the same ray from the centre.
	var door := Vector2(3, 4)  # length 5
	var entry := BuildingEntry.entry_offset(door, 2.0)  # length should be 3
	assert_float(entry.length()).is_equal_approx(3.0, 0.0001)
	assert_float(entry.angle()).is_equal_approx(door.angle(), 0.0001)
