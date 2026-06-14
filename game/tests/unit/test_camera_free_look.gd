class_name TestCameraFreeLook
extends GdUnitTestSuite
## Unit tests for CameraFeel's driving free-look helpers (look_offset / look_return).
## Split out from TestCameraFeel to keep each suite under the public-method cap.


func test_look_offset_mouse_right_turns_view_right() -> void:
	# Positive mouse-x (moving right) yields negative yaw, matching OrbitCamera.
	var look := CameraFeel.look_offset(Vector2.ZERO, Vector2(50.0, 0.0), 0.003, PI, -0.5, 0.5)
	assert_float(look.x).is_less(0.0)


func test_look_offset_mouse_down_pitches_down() -> void:
	# Positive mouse-y (moving down) yields negative pitch (look down).
	var look := CameraFeel.look_offset(Vector2.ZERO, Vector2(0.0, 50.0), 0.003, PI, -0.5, 0.5)
	assert_float(look.y).is_less(0.0)


func test_look_offset_clamps_yaw_to_limit() -> void:
	# A huge sweep cannot spin past the yaw limit (straight behind the car).
	# Vector2 stores 32-bit floats, so compare PI approximately.
	var look := CameraFeel.look_offset(Vector2.ZERO, Vector2(-100000.0, 0.0), 0.003, PI, -0.5, 0.5)
	assert_float(look.x).is_equal_approx(PI, 0.0001)


func test_look_offset_clamps_pitch_to_range() -> void:
	var up := CameraFeel.look_offset(Vector2.ZERO, Vector2(0.0, -100000.0), 0.003, PI, -0.5, 0.5)
	assert_float(up.y).is_equal(0.5)
	var down := CameraFeel.look_offset(Vector2.ZERO, Vector2(0.0, 100000.0), 0.003, PI, -0.5, 0.5)
	assert_float(down.y).is_equal(-0.5)


func test_look_offset_accumulates_from_current() -> void:
	# Each call adds onto the prior offset rather than resetting it.
	var look := CameraFeel.look_offset(
		Vector2(0.4, 0.1), Vector2(-100.0, 0.0), 0.003, PI, -0.5, 0.5
	)
	assert_float(look.x).is_equal_approx(0.7, 0.0001)


func test_look_return_eases_each_axis_toward_zero() -> void:
	# rate 2.0 * delta 0.1 = a 0.2 step on each axis, toward zero.
	var look := CameraFeel.look_return(Vector2(1.0, -0.4), 2.0, 0.1)
	assert_float(look.x).is_equal_approx(0.8, 0.0001)
	assert_float(look.y).is_equal_approx(-0.2, 0.0001)


func test_look_return_settles_at_zero() -> void:
	assert_vector(CameraFeel.look_return(Vector2.ZERO, 5.0, 0.1)).is_equal(Vector2.ZERO)
