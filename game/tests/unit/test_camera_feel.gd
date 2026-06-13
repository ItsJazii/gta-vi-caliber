class_name TestCameraFeel
extends GdUnitTestSuite
## Unit tests for CameraFeel.

const VECTOR_EPSILON := Vector3.ONE * 0.0001


func test_blend_is_zero_at_walk_speed() -> void:
	assert_float(CameraFeel.sprint_blend(5.0, 5.0, 8.5)).is_equal(0.0)


func test_blend_is_one_at_sprint_speed() -> void:
	assert_float(CameraFeel.sprint_blend(8.5, 5.0, 8.5)).is_equal(1.0)


func test_blend_is_clamped_above_sprint_speed() -> void:
	assert_float(CameraFeel.sprint_blend(20.0, 5.0, 8.5)).is_equal(1.0)


func test_blend_is_clamped_below_walk_speed() -> void:
	assert_float(CameraFeel.sprint_blend(0.0, 5.0, 8.5)).is_equal(0.0)


func test_blend_is_proportional_between_speeds() -> void:
	var blend := CameraFeel.sprint_blend(6.75, 5.0, 8.5)
	assert_float(blend).is_equal_approx(0.5, 0.0001)


func test_blend_handles_degenerate_speed_range() -> void:
	assert_float(CameraFeel.sprint_blend(10.0, 5.0, 5.0)).is_equal(0.0)


func test_fov_adds_full_kick_at_full_blend() -> void:
	assert_float(CameraFeel.fov_for_blend(75.0, 9.0, 1.0)).is_equal_approx(84.0, 0.0001)


func test_fov_is_base_at_zero_blend() -> void:
	assert_float(CameraFeel.fov_for_blend(75.0, 9.0, 0.0)).is_equal_approx(75.0, 0.0001)


func test_smoothing_converges_to_target() -> void:
	var fov := 75.0
	for _i in range(200):
		fov = CameraFeel.exp_smoothed(fov, 84.0, 8.0, 0.016)
	assert_float(fov).is_equal_approx(84.0, 0.01)


func test_smoothing_is_frame_rate_independent() -> void:
	# Two half-steps must land exactly where one full step does.
	var one_step := CameraFeel.exp_smoothed(75.0, 84.0, 8.0, 0.032)
	var half := CameraFeel.exp_smoothed(75.0, 84.0, 8.0, 0.016)
	var two_steps := CameraFeel.exp_smoothed(half, 84.0, 8.0, 0.016)
	assert_float(one_step).is_equal_approx(two_steps, 0.0001)


func test_smoothing_never_overshoots() -> void:
	var fov := CameraFeel.exp_smoothed(75.0, 84.0, 100.0, 1.0)
	assert_float(fov).is_less_equal(84.0)


func test_recenter_yaw_forward_is_zero() -> void:
	# Moving "forward" (-Z) at yaw 0 keeps the camera where it is.
	assert_float(CameraFeel.recenter_yaw(0.0, -1.0)).is_equal_approx(0.0, 0.0001)


func test_recenter_yaw_matches_motion_convention() -> void:
	# The recenter yaw must reproduce the travel direction through PlayerMotion.
	var yaw := CameraFeel.recenter_yaw(1.0, 0.0)
	var dir := PlayerMotion.direction_from_input(Vector2(0, -1), yaw)
	assert_vector(dir).is_equal_approx(Vector3(1, 0, 0), VECTOR_EPSILON)


func test_recenter_yaw_zero_velocity_safe() -> void:
	assert_float(CameraFeel.recenter_yaw(0.0, 0.0)).is_equal(0.0)


func test_approach_angle_steps_toward() -> void:
	assert_float(CameraFeel.approach_angle(0.0, 1.0, 0.25)).is_equal_approx(0.25, 0.0001)


func test_approach_angle_clamps_to_target() -> void:
	assert_float(CameraFeel.approach_angle(0.0, 0.1, 0.25)).is_equal_approx(0.1, 0.0001)


func test_approach_angle_takes_short_arc_over_wrap() -> void:
	# From 3.0 toward -3.0 the short way is across the ±PI wrap (increasing),
	# not the long -6.0 sweep.
	assert_float(CameraFeel.approach_angle(3.0, -3.0, 0.1)).is_greater(3.0)


func test_turn_roll_is_zero_at_zero_speed() -> void:
	# No bank when stationary even if the yaw rate is high.
	assert_float(CameraFeel.turn_roll(2.0, 0.0, 0.05, 0.08)).is_equal_approx(0.0, 0.0001)


func test_turn_roll_banks_opposite_to_yaw() -> void:
	# A positive yaw rate (left turn) rolls negative (into the corner).
	assert_float(CameraFeel.turn_roll(1.0, 1.0, 0.05, 0.08)).is_equal_approx(-0.05, 0.0001)


func test_turn_roll_is_capped() -> void:
	# A huge yaw rate cannot exceed max_roll.
	assert_float(CameraFeel.turn_roll(100.0, 1.0, 0.05, 0.08)).is_equal_approx(-0.08, 0.0001)


func test_turn_roll_scales_with_blend() -> void:
	# Half speed blend halves the roll.
	assert_float(CameraFeel.turn_roll(1.0, 0.5, 0.05, 0.08)).is_equal_approx(-0.025, 0.0001)
