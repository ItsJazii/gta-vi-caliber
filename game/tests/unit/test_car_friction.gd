class_name TestCarFriction
extends GdUnitTestSuite
## Regression tests for the friction-circle axle-share fix: cornering force must
## be charged per-driven-axle, not for the whole car's mass, or a normal corner
## spuriously eats the drive grip.


func test_cornering_force_uses_axle_share() -> void:
	# rear-axle cornering force = mass * share * |speed * yaw|, not full mass.
	assert_float(Traction.cornering_force(300.0, 0.55, 20.0, 0.4)).is_equal_approx(1320.0, 0.001)


func test_cornering_force_floors_and_clamps_inputs() -> void:
	assert_float(Traction.cornering_force(-5.0, 0.55, 20.0, 0.4)).is_equal(0.0)  # mass floored
	assert_float(Traction.cornering_force(300.0, 2.0, 20.0, 0.4)).is_equal_approx(2400.0, 0.001)  # share clamped to 1


func test_normal_corner_keeps_drive_grip() -> void:
	# A default-car corner (rear grip ~2676 N). Old full-mass lateral (2400 N) left
	# only ~1184 N to drive; the axle-share lateral (1320 N) leaves ~2328 N.
	var grip := 2676.0
	var lateral := Traction.cornering_force(300.0, 0.55, 20.0, 0.4)
	var available := Traction.longitudinal_grip(grip, lateral)
	assert_float(available).is_greater(2000.0)
