extends RefCounted
## Unit tests for SwimMotion (see tests/run_tests.gd for the runner contract:
## test_* methods return true to pass).


func test_submersion_zero_above_water() -> bool:
	# Feet a metre above the surface: not submerged at all.
	return SwimMotion.submersion(1.0, 0.0, 1.8) == 0.0


func test_submersion_half_at_chest() -> bool:
	# Surface at 0.9 with feet at 0 over a 1.8 body == half submerged.
	return absf(SwimMotion.submersion(0.0, 0.9, 1.8) - 0.5) < 0.0001


func test_submersion_clamps_when_fully_under() -> bool:
	return SwimMotion.submersion(-5.0, 0.0, 1.8) == 1.0


func test_submersion_safe_with_zero_height() -> bool:
	return SwimMotion.submersion(0.0, 1.0, 0.0) == 0.0


func test_is_swimming_starts_when_chest_deep() -> bool:
	return SwimMotion.is_swimming(0.6, false, 0.6, 0.45)


func test_is_swimming_not_yet_when_shallow() -> bool:
	return not SwimMotion.is_swimming(0.5, false, 0.6, 0.45)


func test_is_swimming_holds_through_small_dip() -> bool:
	# Already swimming and only down to 0.5: stay swimming (above exit).
	return SwimMotion.is_swimming(0.5, true, 0.6, 0.45)


func test_is_swimming_leaves_at_wading_depth() -> bool:
	return not SwimMotion.is_swimming(0.4, true, 0.6, 0.45)


func test_vertical_axis_up_down_and_none() -> bool:
	var up := SwimMotion.vertical_axis(true, false) == 1.0
	var down := SwimMotion.vertical_axis(false, true) == -1.0
	var none := SwimMotion.vertical_axis(false, false) == 0.0
	var both := SwimMotion.vertical_axis(true, true) == 0.0
	return up and down and none and both


func test_target_velocity_maps_axes() -> bool:
	var v := SwimMotion.target_velocity(Vector3(1.0, 0.0, 0.0), 4.0, 1.0, 3.0)
	return v.is_equal_approx(Vector3(4.0, 3.0, 0.0))


func test_buoyancy_rises_when_too_deep() -> bool:
	# Submerged past neutral: positive (upward) speed.
	return SwimMotion.buoyancy(0.9, 0.62, 6.0, 1.5) > 0.0


func test_buoyancy_sinks_when_too_high() -> bool:
	return SwimMotion.buoyancy(0.4, 0.62, 6.0, 1.5) < 0.0


func test_buoyancy_clamps_to_max_speed() -> bool:
	return SwimMotion.buoyancy(1.0, 0.0, 100.0, 1.5) == 1.5


func test_head_underwater_true_past_threshold() -> bool:
	return SwimMotion.head_underwater(0.95, 0.9) and not SwimMotion.head_underwater(0.8, 0.9)


func test_oxygen_drains_underwater() -> bool:
	# 1 second under with a 10 s breath drains 0.1.
	return absf(SwimMotion.next_oxygen(1.0, true, 10.0, 0.5, 1.0) - 0.9) < 0.0001


func test_oxygen_refills_at_surface() -> bool:
	return absf(SwimMotion.next_oxygen(0.5, false, 10.0, 0.5, 1.0) - 1.0) < 0.0001


func test_oxygen_never_below_zero() -> bool:
	return SwimMotion.next_oxygen(0.05, true, 10.0, 0.5, 1.0) == 0.0


func test_oxygen_never_above_one() -> bool:
	return SwimMotion.next_oxygen(0.95, false, 10.0, 5.0, 1.0) == 1.0


func test_oxygen_degenerate_breath_empties() -> bool:
	return SwimMotion.next_oxygen(1.0, true, 0.0, 0.5, 0.016) == 0.0
