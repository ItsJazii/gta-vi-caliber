extends RefCounted
## Unit tests for Locomotion (see tests/run_tests.gd for the runner contract:
## test_* methods return true to pass).

const WALK := 5.0
const RUN := 8.5


func test_idle_when_barely_moving() -> bool:
	return Locomotion.state_for(0.05, true, 0.0, false, WALK, RUN) == Locomotion.State.IDLE


func test_walk_state_at_walk_speed() -> bool:
	return Locomotion.state_for(WALK, true, 0.0, false, WALK, RUN) == Locomotion.State.WALK


func test_run_state_above_gate() -> bool:
	return Locomotion.state_for(RUN, true, 0.0, false, WALK, RUN) == Locomotion.State.RUN


func test_walk_holds_just_over_walk_speed() -> bool:
	# Just above walk_speed but below the run gate stays WALK (no flicker).
	return Locomotion.state_for(WALK + 0.5, true, 0.0, false, WALK, RUN) == Locomotion.State.WALK


func test_jump_when_rising_airborne() -> bool:
	return Locomotion.state_for(3.0, false, 2.0, false, WALK, RUN) == Locomotion.State.JUMP


func test_fall_when_descending_airborne() -> bool:
	return Locomotion.state_for(3.0, false, -2.0, false, WALK, RUN) == Locomotion.State.FALL


func test_climb_overrides_everything() -> bool:
	return Locomotion.state_for(0.0, false, -5.0, true, WALK, RUN) == Locomotion.State.CLIMB


func test_move_blend_zero_when_still() -> bool:
	return is_equal_approx(Locomotion.move_blend(0.0, WALK, RUN), 0.0)


func test_move_blend_half_at_walk_speed() -> bool:
	return is_equal_approx(Locomotion.move_blend(WALK, WALK, RUN), 0.5)


func test_move_blend_one_at_run_speed() -> bool:
	return is_equal_approx(Locomotion.move_blend(RUN, WALK, RUN), 1.0)


func test_move_blend_clamps_above_run() -> bool:
	return is_equal_approx(Locomotion.move_blend(RUN * 2.0, WALK, RUN), 1.0)


func test_move_blend_is_monotonic() -> bool:
	var prev := -1.0
	for i in range(0, 20):
		var speed := float(i) * 0.6
		var blend := Locomotion.move_blend(speed, WALK, RUN)
		if blend < prev:
			return false
		prev = blend
	return true


func test_phase_advances_with_speed() -> bool:
	var phase := Locomotion.advance_phase(0.0, WALK, 0.1)
	return phase > 0.0


func test_phase_does_not_advance_when_stationary() -> bool:
	return is_equal_approx(Locomotion.advance_phase(0.0, 0.0, 0.1), 0.0)


func test_phase_wraps_to_tau() -> bool:
	# A huge step must stay within [0, TAU).
	var phase := Locomotion.advance_phase(0.0, 1000.0, 1.0)
	return phase >= 0.0 and phase < TAU


func test_phase_advance_scales_with_distance() -> bool:
	# Twice the speed over the same time advances twice as far (before wrap).
	var slow := Locomotion.advance_phase(0.0, 1.0, 0.05)
	var fast := Locomotion.advance_phase(0.0, 2.0, 0.05)
	return is_equal_approx(fast, slow * 2.0)


func test_limbs_counter_swing() -> bool:
	# Opposite limbs (phase offset by PI) swing in opposite directions.
	var left := Locomotion.limb_swing(0.5, 0.6)
	var right := Locomotion.limb_swing(0.5 + PI, 0.6)
	return is_equal_approx(left, -right)


func test_limb_swing_peaks_at_amplitude() -> bool:
	return is_equal_approx(Locomotion.limb_swing(PI / 2.0, 0.6), 0.6)


func test_vertical_bob_never_positive() -> bool:
	for i in range(0, 16):
		var phase := float(i) / 16.0 * TAU
		if Locomotion.vertical_bob(phase, 0.08) > 0.0:
			return false
	return true


func test_vertical_bob_double_frequency() -> bool:
	# Bob dips at both phase 0.5PI and 1.5PI (twice per stride cycle).
	var first := Locomotion.vertical_bob(PI / 2.0, 0.08)
	var second := Locomotion.vertical_bob(3.0 * PI / 2.0, 0.08)
	return is_equal_approx(first, second) and first < 0.0


func test_secondary_body_motion_tracks_stride_side() -> bool:
	var left := Locomotion.lateral_sway(PI / 2.0, 0.03)
	var right := Locomotion.lateral_sway(3.0 * PI / 2.0, 0.03)
	var phase := PI / 2.0
	return (
		left > 0.0
		and right < 0.0
		and is_equal_approx(left, -right)
		and Locomotion.pelvis_roll(phase, 0.05) < 0.0
		and Locomotion.shoulder_counter_roll(phase, 0.04) > 0.0
		and Locomotion.torso_twist(phase, 0.05) < 0.0
		and is_equal_approx(
			Locomotion.torso_twist(phase, 0.05), -Locomotion.torso_twist(phase + PI, 0.05)
		)
		and Locomotion.head_step_pitch(phase, 0.02) < 0.0
		and Locomotion.head_counter_roll(phase, 0.03) < 0.0
	)


func test_lean_forward_on_acceleration() -> bool:
	return Locomotion.lean_angle(30.0, 30.0, 0.25) > 0.0


func test_lean_back_on_braking() -> bool:
	return Locomotion.lean_angle(-30.0, 30.0, 0.25) < 0.0


func test_lean_clamps_to_max() -> bool:
	return is_equal_approx(Locomotion.lean_angle(100.0, 30.0, 0.25), 0.25)


func test_lean_zero_reference_is_safe() -> bool:
	return is_equal_approx(Locomotion.lean_angle(30.0, 0.0, 0.25), 0.0)
