extends RefCounted
## Unit tests for WeightTransfer (see tests/run_tests.gd: test_* methods return
## true to pass). Reference figures: 300 kg car, 0.5 m CG height, 2.9 m wheelbase.

const MASS := 300.0
const CG_HEIGHT := 0.5
const WHEELBASE := 2.9

# --- longitudinal_shift ------------------------------------------------------


func test_no_shift_without_acceleration() -> bool:
	return is_equal_approx(WeightTransfer.longitudinal_shift(MASS, 0.0, CG_HEIGHT, WHEELBASE), 0.0)


func test_acceleration_shifts_load_rearward() -> bool:
	return WeightTransfer.longitudinal_shift(MASS, 8.0, CG_HEIGHT, WHEELBASE) > 0.0


func test_braking_shifts_load_forward() -> bool:
	return WeightTransfer.longitudinal_shift(MASS, -8.0, CG_HEIGHT, WHEELBASE) < 0.0


func test_shift_matches_closed_form() -> bool:
	var expected := MASS * 8.0 * CG_HEIGHT / WHEELBASE
	return is_equal_approx(
		WeightTransfer.longitudinal_shift(MASS, 8.0, CG_HEIGHT, WHEELBASE), expected
	)


func test_shift_scales_with_cg_height() -> bool:
	# A taller CG transfers more weight — why sports cars sit low.
	var low := WeightTransfer.longitudinal_shift(MASS, 8.0, 0.3, WHEELBASE)
	var high := WeightTransfer.longitudinal_shift(MASS, 8.0, 0.6, WHEELBASE)
	return high > low


func test_shift_inverse_with_wheelbase() -> bool:
	# A longer wheelbase transfers less — why long cars feel planted.
	var short := WeightTransfer.longitudinal_shift(MASS, 8.0, CG_HEIGHT, 2.0)
	var long := WeightTransfer.longitudinal_shift(MASS, 8.0, CG_HEIGHT, 4.0)
	return short > long


func test_shift_safe_with_zero_wheelbase() -> bool:
	return is_equal_approx(WeightTransfer.longitudinal_shift(MASS, 8.0, CG_HEIGHT, 0.0), 0.0)


# --- axle_load ---------------------------------------------------------------


func test_axle_load_adds_transfer() -> bool:
	return is_equal_approx(WeightTransfer.axle_load(1600.0, 400.0), 2000.0)


func test_axle_load_subtracts_on_dive() -> bool:
	return is_equal_approx(WeightTransfer.axle_load(1600.0, -400.0), 1200.0)


func test_axle_load_floors_at_zero() -> bool:
	# An unloaded axle lifts; it never goes negative.
	return is_equal_approx(WeightTransfer.axle_load(1000.0, -5000.0), 0.0)
