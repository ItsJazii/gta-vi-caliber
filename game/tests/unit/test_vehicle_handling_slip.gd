extends RefCounted
## Unit tests for VehicleHandling.slip_for_grip — the handbrake's grip factor to
## VehicleWheel3D.friction_slip mapping. Split from test_vehicle_handling.gd,
## which sits at the linter's public-method cap; same legacy runner contract
## (test_* methods return true to pass). Pure deterministic math.

# --- slip_for_grip (handbrake -> wheel friction slip) -------------------------


func test_slip_for_grip_full_grip_is_base() -> bool:
	# No grip cut (handbrake released) leaves the wheel at its authored slip.
	return is_equal_approx(VehicleHandling.slip_for_grip(1.0, 0.4, 3.0), 3.0)


func test_slip_for_grip_zero_grip_is_floor() -> bool:
	# A full slide drops the wheel to the slid floor, not below.
	return is_equal_approx(VehicleHandling.slip_for_grip(0.0, 0.4, 3.0), 0.4)


func test_slip_for_grip_interpolates() -> bool:
	# Half grip lands halfway between floor and base: 0.4 + 0.5*(3.0-0.4)=1.7.
	return is_equal_approx(VehicleHandling.slip_for_grip(0.5, 0.4, 3.0), 1.7)


func test_slip_for_grip_clamps_out_of_range() -> bool:
	# Grip outside [0,1] cannot push slip past either endpoint.
	var over := VehicleHandling.slip_for_grip(5.0, 0.4, 3.0)
	var under := VehicleHandling.slip_for_grip(-5.0, 0.4, 3.0)
	return is_equal_approx(over, 3.0) and is_equal_approx(under, 0.4)
