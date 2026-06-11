extends RefCounted
## Unit tests for VehicleMotion (runner contract: test_* methods return true).


func test_full_throttle_at_standstill_gives_max_force() -> bool:
	return absf(VehicleMotion.engine_force(1.0, 2600.0, 0.0, 38.0) - 2600.0) < 0.0001


func test_force_tapers_to_zero_at_top_speed() -> bool:
	return absf(VehicleMotion.engine_force(1.0, 2600.0, 38.0, 38.0)) < 0.0001


func test_force_is_half_at_half_top_speed() -> bool:
	return absf(VehicleMotion.engine_force(1.0, 2600.0, 19.0, 38.0) - 1300.0) < 0.0001


func test_reverse_throttle_gives_negative_force() -> bool:
	return VehicleMotion.engine_force(-1.0, 2600.0, 0.0, 38.0) < 0.0


func test_throttle_is_clamped() -> bool:
	return absf(VehicleMotion.engine_force(5.0, 2600.0, 0.0, 38.0) - 2600.0) < 0.0001


func test_degenerate_top_speed_gives_no_force() -> bool:
	return VehicleMotion.engine_force(1.0, 2600.0, 10.0, 0.0) == 0.0


func test_steer_limit_is_full_lock_when_parked() -> bool:
	return absf(VehicleMotion.steer_limit(0.0, 0.55, 12.0) - 0.55) < 0.0001


func test_steer_limit_halves_at_falloff_speed() -> bool:
	return absf(VehicleMotion.steer_limit(12.0, 0.55, 12.0) - 0.275) < 0.0001


func test_steer_target_scales_input() -> bool:
	return absf(VehicleMotion.steer_target(0.5, 0.0, 0.55, 12.0) - 0.275) < 0.0001


func test_steer_target_clamps_input() -> bool:
	return absf(VehicleMotion.steer_target(3.0, 0.0, 0.55, 12.0) - 0.55) < 0.0001


func test_upright_torque_opposes_tilt() -> bool:
	# Tilted positive with no roll rate: torque must push negative.
	return VehicleMotion.upright_torque(0.5, 0.0, 90.0, 12.0) < 0.0


func test_upright_torque_damps_roll_rate() -> bool:
	# Upright but rolling: torque must oppose the roll.
	return VehicleMotion.upright_torque(0.0, 2.0, 90.0, 12.0) < 0.0


func test_upright_torque_is_zero_at_rest_upright() -> bool:
	return VehicleMotion.upright_torque(0.0, 0.0, 90.0, 12.0) == 0.0


func test_upright_torque_scales_with_stiffness() -> bool:
	var soft := VehicleMotion.upright_torque(0.5, 0.0, 45.0, 12.0)
	var stiff := VehicleMotion.upright_torque(0.5, 0.0, 90.0, 12.0)
	return absf(stiff - 2.0 * soft) < 0.0001


func test_rollover_limit_is_unconstrained_when_parked() -> bool:
	return VehicleMotion.rollover_steer_limit(0.0, 1.7, 0.3, 2.9, 0.8) >= TAU


func test_rollover_limit_tightens_with_speed() -> bool:
	var slow := VehicleMotion.rollover_steer_limit(10.0, 1.7, 0.3, 2.9, 0.8)
	var fast := VehicleMotion.rollover_steer_limit(30.0, 1.7, 0.3, 2.9, 0.8)
	return fast < slow


func test_rollover_limit_widens_with_lower_cg() -> bool:
	var tall := VehicleMotion.rollover_steer_limit(20.0, 1.7, 0.6, 2.9, 0.8)
	var low := VehicleMotion.rollover_steer_limit(20.0, 1.7, 0.3, 2.9, 0.8)
	return low > tall


func test_rollover_limit_widens_with_wider_track() -> bool:
	var narrow := VehicleMotion.rollover_steer_limit(20.0, 1.0, 0.3, 2.9, 0.8)
	var wide := VehicleMotion.rollover_steer_limit(20.0, 1.7, 0.3, 2.9, 0.8)
	return wide > narrow


func test_rollover_limit_scales_with_margin() -> bool:
	var cautious := VehicleMotion.rollover_steer_limit(20.0, 1.7, 0.3, 2.9, 0.5)
	var confident := VehicleMotion.rollover_steer_limit(20.0, 1.7, 0.3, 2.9, 1.0)
	return confident > cautious


func test_rollover_limit_degenerate_cg_is_unconstrained() -> bool:
	return VehicleMotion.rollover_steer_limit(20.0, 1.7, 0.0, 2.9, 0.8) >= TAU
