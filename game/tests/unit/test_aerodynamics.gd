extends RefCounted
## Unit tests for Aerodynamics (see tests/run_tests.gd: test_* methods return
## true to pass). Reference figures are a small saloon: Cd·A ≈ 0.7 m², a touch of
## downforce, in sea-level air.

const DRAG_AREA := 0.7
const LIFT_AREA := 0.4
const RHO := 1.225

# --- drag_force --------------------------------------------------------------


func test_drag_zero_at_standstill() -> bool:
	return is_equal_approx(Aerodynamics.drag_force(0.0, DRAG_AREA, RHO), 0.0)


func test_drag_quadruples_with_double_speed() -> bool:
	var slow := Aerodynamics.drag_force(10.0, DRAG_AREA, RHO)
	var fast := Aerodynamics.drag_force(20.0, DRAG_AREA, RHO)
	return is_equal_approx(fast, slow * 4.0)


func test_drag_scales_linearly_with_area() -> bool:
	var small := Aerodynamics.drag_force(30.0, DRAG_AREA, RHO)
	var big := Aerodynamics.drag_force(30.0, DRAG_AREA * 2.0, RHO)
	return is_equal_approx(big, small * 2.0)


func test_drag_matches_closed_form() -> bool:
	var expected := 0.5 * RHO * DRAG_AREA * 25.0 * 25.0
	return is_equal_approx(Aerodynamics.drag_force(25.0, DRAG_AREA, RHO), expected)


func test_drag_unsigned_speed() -> bool:
	# Direction of travel doesn't change drag magnitude.
	return is_equal_approx(
		Aerodynamics.drag_force(-18.0, DRAG_AREA, RHO),
		Aerodynamics.drag_force(18.0, DRAG_AREA, RHO)
	)


func test_drag_safe_with_zero_area() -> bool:
	return is_equal_approx(Aerodynamics.drag_force(40.0, 0.0, RHO), 0.0)


# --- downforce ---------------------------------------------------------------


func test_downforce_zero_at_standstill() -> bool:
	return is_equal_approx(Aerodynamics.downforce(0.0, LIFT_AREA, RHO), 0.0)


func test_downforce_grows_with_speed_squared() -> bool:
	var slow := Aerodynamics.downforce(15.0, LIFT_AREA, RHO)
	var fast := Aerodynamics.downforce(45.0, LIFT_AREA, RHO)
	return is_equal_approx(fast, slow * 9.0)


func test_downforce_safe_with_zero_air() -> bool:
	return is_equal_approx(Aerodynamics.downforce(40.0, LIFT_AREA, 0.0), 0.0)


# --- terminal_speed ----------------------------------------------------------


func test_terminal_speed_balances_drag() -> bool:
	# At the returned speed, drag should equal the drive force that produced it.
	var force := 3000.0
	var v := Aerodynamics.terminal_speed(force, DRAG_AREA, RHO)
	return is_equal_approx(Aerodynamics.drag_force(v, DRAG_AREA, RHO), force)


func test_terminal_speed_rises_with_force() -> bool:
	var low := Aerodynamics.terminal_speed(1000.0, DRAG_AREA, RHO)
	var high := Aerodynamics.terminal_speed(4000.0, DRAG_AREA, RHO)
	return high > low


func test_terminal_speed_safe_without_drag() -> bool:
	return is_equal_approx(Aerodynamics.terminal_speed(3000.0, 0.0, RHO), 0.0)


func test_terminal_speed_safe_without_force() -> bool:
	return is_equal_approx(Aerodynamics.terminal_speed(0.0, DRAG_AREA, RHO), 0.0)
