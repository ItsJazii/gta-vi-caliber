extends RefCounted
## Unit tests for CameraShake (see tests/run_tests.gd for the runner contract:
## test_* methods return true to pass).


func test_add_accumulates() -> bool:
	return absf(CameraShake.add(0.2, 0.3) - 0.5) < 0.0001


func test_add_clamps_to_one() -> bool:
	return CameraShake.add(0.8, 0.5) == 1.0


func test_decay_reduces_over_time() -> bool:
	return absf(CameraShake.decay(1.0, 2.0, 0.1) - 0.8) < 0.0001


func test_decay_never_negative() -> bool:
	return CameraShake.decay(0.1, 5.0, 0.1) == 0.0


func test_shake_amount_is_power() -> bool:
	return absf(CameraShake.shake_amount(0.5, 2.0) - 0.25) < 0.0001


func test_shake_amount_clamps_exponent() -> bool:
	# Exponent < 1 would amplify small trauma; floor it at linear.
	return absf(CameraShake.shake_amount(0.5, 0.2) - 0.5) < 0.0001


func test_zero_trauma_gives_zero_offset() -> bool:
	var off := CameraShake.angular_offset(0.0, 2.0, Vector3(0.1, 0.1, 0.1), Vector3(1, 1, 1))
	return off == Vector3.ZERO


func test_offset_scales_with_axis_and_noise() -> bool:
	# Full trauma, unit noise on yaw only: offset.y == max_angles.y, others 0.
	var off := CameraShake.angular_offset(1.0, 2.0, Vector3(0.05, 0.08, 0.03), Vector3(0, 1, 0))
	return absf(off.y - 0.08) < 0.0001 and off.x == 0.0 and off.z == 0.0


func test_offset_respects_noise_sign() -> bool:
	var off := CameraShake.angular_offset(1.0, 2.0, Vector3(0.1, 0.1, 0.1), Vector3(-1, 0, 0))
	return off.x < 0.0


func test_offset_grows_with_trauma() -> bool:
	var low := CameraShake.angular_offset(0.4, 2.0, Vector3(0.1, 0.1, 0.1), Vector3(1, 0, 0))
	var high := CameraShake.angular_offset(0.9, 2.0, Vector3(0.1, 0.1, 0.1), Vector3(1, 0, 0))
	return high.x > low.x


func test_impact_silent_below_min() -> bool:
	return CameraShake.trauma_from_impact(3.0, 5.0, 18.0, 0.8) == 0.0


func test_impact_full_at_max() -> bool:
	return absf(CameraShake.trauma_from_impact(18.0, 5.0, 18.0, 0.8) - 0.8) < 0.0001


func test_impact_clamps_above_max() -> bool:
	return absf(CameraShake.trauma_from_impact(99.0, 5.0, 18.0, 0.8) - 0.8) < 0.0001


func test_impact_interpolates_midrange() -> bool:
	# Halfway between 5 and 18 (=11.5) → half of max_trauma.
	return absf(CameraShake.trauma_from_impact(11.5, 5.0, 18.0, 0.8) - 0.4) < 0.0001


func test_impact_degenerate_range_safe() -> bool:
	return CameraShake.trauma_from_impact(10.0, 5.0, 5.0, 0.8) == 0.0
