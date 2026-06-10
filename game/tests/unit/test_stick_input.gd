extends RefCounted
## Unit tests for StickInput (see tests/run_tests.gd for the runner contract:
## test_* methods return true to pass).


func test_inside_deadzone_is_zero() -> bool:
	return StickInput.radial_deadzone(Vector2(0.1, 0.05), 0.2) == Vector2.ZERO


func test_deadzone_edge_eases_from_zero() -> bool:
	# Just past the threshold the output magnitude should be near zero, not a
	# sudden step up to the raw magnitude (no snap).
	var out := StickInput.radial_deadzone(Vector2(0.21, 0.0), 0.2)
	return out.x > 0.0 and out.x < 0.05


func test_deadzone_preserves_direction() -> bool:
	var raw := Vector2(0.6, 0.8)  # length 1.0, pointing up-right
	var out := StickInput.radial_deadzone(raw, 0.2)
	return out.normalized().is_equal_approx(raw.normalized())


func test_full_deflection_reaches_unit_magnitude() -> bool:
	var out := StickInput.radial_deadzone(Vector2(1.0, 0.0), 0.2)
	return absf(out.length() - 1.0) < 0.0001


func test_overrange_magnitude_is_clamped() -> bool:
	# A diagonal raw vector can exceed length 1; output must not.
	var out := StickInput.radial_deadzone(Vector2(1.0, 1.0), 0.2)
	return out.length() <= 1.0 + 0.0001


func test_response_curve_softens_centre() -> bool:
	# With exponent > 1, a mid-range input shrinks (finer control near centre).
	var shaped := StickInput.apply_response(Vector2(0.5, 0.0), 2.0)
	return absf(shaped.x - 0.25) < 0.0001


func test_response_linear_when_exponent_one() -> bool:
	var shaped := StickInput.apply_response(Vector2(0.5, 0.0), 1.0)
	return absf(shaped.x - 0.5) < 0.0001


func test_response_preserves_direction() -> bool:
	var v := Vector2(0.3, 0.4)
	var shaped := StickInput.apply_response(v, 3.0)
	return shaped.normalized().is_equal_approx(v.normalized())


func test_response_clamps_exponent_below_one() -> bool:
	# Exponents < 1 would boost the centre and risk overshoot; clamp to linear.
	var shaped := StickInput.apply_response(Vector2(0.5, 0.0), 0.2)
	return absf(shaped.x - 0.5) < 0.0001


func test_look_delta_scales_with_delta() -> bool:
	var raw := Vector2(1.0, 0.0)
	var a := StickInput.look_delta(raw, 0.15, 1.5, 2.0, 0.01)
	var b := StickInput.look_delta(raw, 0.15, 1.5, 2.0, 0.02)
	return absf(b.x - a.x * 2.0) < 0.0001


func test_look_delta_zero_inside_deadzone() -> bool:
	return StickInput.look_delta(Vector2(0.05, 0.05), 0.2, 1.5, 2.0, 0.016) == Vector2.ZERO
