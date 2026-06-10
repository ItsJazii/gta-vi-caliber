extends RefCounted
## Unit tests for Powertrain (see tests/run_tests.gd: test_* methods return true
## to pass). Reference numbers are a ~2.0 L street car: torque peaking at
## 4000 rpm, 6500 redline, a 5-speed box on a 3.7 final drive, 0.34 m wheels.

const IDLE := 850.0
const PEAK_RPM := 4000.0
const REDLINE := 6500.0
const PEAK_TORQUE := 250.0
const FINAL := 3.7
const RADIUS := 0.34
const FIRST := 3.40
const TOP := 0.85
const EFFICIENCY := 0.9

# --- engine_rpm --------------------------------------------------------------


func test_rpm_rises_with_speed() -> bool:
	var slow := Powertrain.engine_rpm(5.0, FIRST, FINAL, RADIUS, IDLE, REDLINE)
	var fast := Powertrain.engine_rpm(15.0, FIRST, FINAL, RADIUS, IDLE, REDLINE)
	return fast > slow


func test_rpm_idles_at_standstill() -> bool:
	return is_equal_approx(Powertrain.engine_rpm(0.0, FIRST, FINAL, RADIUS, IDLE, REDLINE), IDLE)


func test_rpm_clamps_to_redline() -> bool:
	var rpm := Powertrain.engine_rpm(200.0, FIRST, FINAL, RADIUS, IDLE, REDLINE)
	return is_equal_approx(rpm, REDLINE)


func test_rpm_higher_in_lower_gear() -> bool:
	# At one road speed a taller-ratio (lower) gear spins the engine faster.
	var low_gear := Powertrain.engine_rpm(20.0, FIRST, FINAL, RADIUS, IDLE, REDLINE)
	var high_gear := Powertrain.engine_rpm(20.0, TOP, FINAL, RADIUS, IDLE, REDLINE)
	return low_gear > high_gear


func test_rpm_safe_with_zero_radius() -> bool:
	return is_equal_approx(Powertrain.engine_rpm(20.0, FIRST, FINAL, 0.0, IDLE, REDLINE), IDLE)


func test_rpm_uses_gear_ratio_magnitude() -> bool:
	# A reverse (negative) ratio spins the engine the same as its magnitude.
	var forward := Powertrain.engine_rpm(8.0, 3.6, FINAL, RADIUS, IDLE, REDLINE)
	var reverse := Powertrain.engine_rpm(8.0, -3.6, FINAL, RADIUS, IDLE, REDLINE)
	return is_equal_approx(forward, reverse)


# --- engine_torque -----------------------------------------------------------


func test_torque_peaks_at_peak_rpm() -> bool:
	return is_equal_approx(
		Powertrain.engine_torque(PEAK_RPM, PEAK_TORQUE, IDLE, PEAK_RPM, REDLINE), PEAK_TORQUE
	)


func test_torque_below_peak_at_idle() -> bool:
	var at_idle := Powertrain.engine_torque(IDLE, PEAK_TORQUE, IDLE, PEAK_RPM, REDLINE)
	return at_idle < PEAK_TORQUE and at_idle > 0.0


func test_torque_below_peak_at_redline() -> bool:
	var at_redline := Powertrain.engine_torque(REDLINE, PEAK_TORQUE, IDLE, PEAK_RPM, REDLINE)
	return at_redline < PEAK_TORQUE and at_redline > 0.0


func test_torque_never_exceeds_peak() -> bool:
	for i in range(0, 40):
		var rpm := lerpf(IDLE, REDLINE, float(i) / 39.0)
		if (
			Powertrain.engine_torque(rpm, PEAK_TORQUE, IDLE, PEAK_RPM, REDLINE)
			> PEAK_TORQUE + 0.001
		):
			return false
	return true


func test_torque_respects_minimum_floor() -> bool:
	# Even clamped past redline, torque stays at the floor, never zero.
	var floor_value := PEAK_TORQUE * Powertrain.MIN_TORQUE_FRACTION
	var at_redline := Powertrain.engine_torque(REDLINE, PEAK_TORQUE, IDLE, PEAK_RPM, REDLINE)
	return at_redline >= floor_value - 0.001


func test_torque_rises_toward_peak() -> bool:
	# Climbing from idle to the peak, torque is monotonically non-decreasing.
	var prev := -1.0
	for i in range(0, 20):
		var rpm := lerpf(IDLE, PEAK_RPM, float(i) / 19.0)
		var torque := Powertrain.engine_torque(rpm, PEAK_TORQUE, IDLE, PEAK_RPM, REDLINE)
		if torque < prev - 0.001:
			return false
		prev = torque
	return true


# --- wheel_force -------------------------------------------------------------


func test_force_zero_without_throttle() -> bool:
	return is_equal_approx(
		Powertrain.wheel_force(PEAK_TORQUE, 0.0, FIRST, FINAL, RADIUS, EFFICIENCY), 0.0
	)


func test_force_scales_with_throttle() -> bool:
	var half := Powertrain.wheel_force(PEAK_TORQUE, 0.5, FIRST, FINAL, RADIUS, EFFICIENCY)
	var full := Powertrain.wheel_force(PEAK_TORQUE, 1.0, FIRST, FINAL, RADIUS, EFFICIENCY)
	return is_equal_approx(full, half * 2.0)


func test_force_greater_in_lower_gear() -> bool:
	# Same torque multiplies up more through a taller (lower) gear: launch grunt.
	var first := Powertrain.wheel_force(PEAK_TORQUE, 1.0, FIRST, FINAL, RADIUS, EFFICIENCY)
	var top := Powertrain.wheel_force(PEAK_TORQUE, 1.0, TOP, FINAL, RADIUS, EFFICIENCY)
	return first > top


func test_force_reverses_with_reverse_gear() -> bool:
	var reverse := Powertrain.wheel_force(PEAK_TORQUE, 1.0, -3.6, FINAL, RADIUS, EFFICIENCY)
	return reverse < 0.0


func test_force_safe_with_zero_radius() -> bool:
	return is_equal_approx(
		Powertrain.wheel_force(PEAK_TORQUE, 1.0, FIRST, FINAL, 0.0, EFFICIENCY), 0.0
	)


func test_force_clamps_negative_throttle() -> bool:
	# A negative pedal is treated as lift-off (no drive), not engine braking here.
	return is_equal_approx(
		Powertrain.wheel_force(PEAK_TORQUE, -1.0, FIRST, FINAL, RADIUS, EFFICIENCY), 0.0
	)


# --- select_gear -------------------------------------------------------------


func test_gear_upshifts_above_threshold() -> bool:
	return Powertrain.select_gear(2, 6200.0, 6000.0, 2500.0, 5) == 3


func test_gear_downshifts_below_threshold() -> bool:
	return Powertrain.select_gear(3, 2000.0, 6000.0, 2500.0, 5) == 2


func test_gear_holds_within_band() -> bool:
	# RPM between the shift points: stay put, no hunting.
	return Powertrain.select_gear(3, 4000.0, 6000.0, 2500.0, 5) == 3


func test_gear_clamps_at_top() -> bool:
	return Powertrain.select_gear(5, 6500.0, 6000.0, 2500.0, 5) == 5


func test_gear_clamps_at_first() -> bool:
	return Powertrain.select_gear(1, 500.0, 6000.0, 2500.0, 5) == 1


func test_gear_steps_one_at_a_time() -> bool:
	# Even far past redline, only a single upshift happens per call.
	return Powertrain.select_gear(1, 99999.0, 6000.0, 2500.0, 5) == 2
