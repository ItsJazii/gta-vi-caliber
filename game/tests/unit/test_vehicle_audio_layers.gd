extends RefCounted
## Unit tests for VehicleAudioModel's added layers: the exhaust note, the
## gear-shift volume dip, the handbrake/tyre screech, and the crash thud. Split
## from test_vehicle_audio_model.gd so each suite stays under the lint cap.


func test_exhaust_volume_rises_with_throttle() -> bool:
	var off := VehicleAudioModel.exhaust_volume_db(0.0, 2000.0, 850.0, 6500.0)
	var on := VehicleAudioModel.exhaust_volume_db(1.0, 2000.0, 850.0, 6500.0)
	return on > off


func test_exhaust_overrun_burbles_off_throttle_at_high_rpm() -> bool:
	# Lifting off at high rpm must stay louder than lifting off near idle.
	var low := VehicleAudioModel.exhaust_volume_db(0.0, 1000.0, 850.0, 6500.0)
	var high := VehicleAudioModel.exhaust_volume_db(0.0, 6500.0, 850.0, 6500.0)
	return high > low


func test_exhaust_volume_never_exceeds_unity() -> bool:
	return VehicleAudioModel.exhaust_volume_db(1.0, 6500.0, 850.0, 6500.0) <= 0.001


func test_shift_dip_is_full_at_shift_instant() -> bool:
	return absf(VehicleAudioModel.shift_dip_db(0.0, -9.0, 0.28) - (-9.0)) < 0.001


func test_shift_dip_recovers_to_zero() -> bool:
	return is_equal_approx(VehicleAudioModel.shift_dip_db(0.28, -9.0, 0.28), 0.0)


func test_shift_dip_eases_back_monotonically() -> bool:
	var early := VehicleAudioModel.shift_dip_db(0.05, -9.0, 0.28)
	var late := VehicleAudioModel.shift_dip_db(0.20, -9.0, 0.28)
	# Both are negative offsets; later is closer to 0 (louder again).
	return late > early and early < 0.0


func test_shift_dip_handles_negative_and_degenerate() -> bool:
	var negative := VehicleAudioModel.shift_dip_db(-1.0, -9.0, 0.28)
	var degenerate := VehicleAudioModel.shift_dip_db(0.1, -9.0, 0.0)
	return is_zero_approx(negative) and is_zero_approx(degenerate)


func test_handbrake_silent_below_threshold() -> bool:
	var d := VehicleAudioModel.DRIFT_SILENCE - 0.01
	return VehicleAudioModel.handbrake_screech_db(d) <= VehicleAudioModel.SILENT_DB


func test_handbrake_screech_rises_with_drift() -> bool:
	var a := VehicleAudioModel.handbrake_screech_db(0.4)
	var b := VehicleAudioModel.handbrake_screech_db(0.9)
	return b > a and a > VehicleAudioModel.SILENT_DB


func test_tire_mix_takes_the_louder_source() -> bool:
	# Pure handbrake (no grip loss) ⇒ handbrake screech; pure grip loss ⇒ skid.
	var drift_only := VehicleAudioModel.tire_mix_db(0.0, 1.0)
	var slip_only := VehicleAudioModel.tire_mix_db(1.0, 0.0)
	return (
		is_equal_approx(drift_only, VehicleAudioModel.handbrake_screech_db(1.0))
		and is_equal_approx(slip_only, VehicleAudioModel.skid_volume_db(1.0))
	)


func test_skid_pitch_rises_with_intensity_and_clamps() -> bool:
	var low := VehicleAudioModel.skid_pitch_scale(-1.0)
	var mid := VehicleAudioModel.skid_pitch_scale(0.5)
	var high := VehicleAudioModel.skid_pitch_scale(2.0)
	return absf(low - 0.9) < 0.001 and absf(high - 1.4) < 0.001 and mid > low and mid < high


func test_impact_pitch_deeper_for_bigger_hit() -> bool:
	var small := VehicleAudioModel.impact_pitch_scale(7.0, 6.0, 20.0)
	var big := VehicleAudioModel.impact_pitch_scale(20.0, 6.0, 20.0)
	return small > big


func test_impact_pitch_degenerate_range_is_unity() -> bool:
	return absf(VehicleAudioModel.impact_pitch_scale(10.0, 6.0, 6.0) - 1.0) < 0.001


func test_exhaust_loop_is_normalized() -> bool:
	var frames := VehicleAudioModel.exhaust_loop_frames(22050, 50.0)
	var peak := 0.0
	for f in frames:
		peak = maxf(peak, absf(f))
	return absf(peak - 0.9) < 0.01


func test_exhaust_loop_seam_is_continuous() -> bool:
	var frames := VehicleAudioModel.exhaust_loop_frames(22050, 50.0)
	var step := absf(frames[0] - frames[frames.size() - 1])
	var typical := absf(frames[1] - frames[0])
	return step < typical * 3.0 + 0.01


func test_exhaust_loop_is_deterministic() -> bool:
	var a := VehicleAudioModel.exhaust_loop_frames(22050, 50.0)
	var b := VehicleAudioModel.exhaust_loop_frames(22050, 50.0)
	return a == b


func test_exhaust_loop_length_matches_cycles() -> bool:
	# Independently recompute the expected count from the sub frequency (base/2).
	var frames := VehicleAudioModel.exhaust_loop_frames(22050, 50.0)
	var sub_freq := 50.0 * 0.5
	var expected := int(round(22050.0 * VehicleAudioModel.EXHAUST_LOOP_CYCLES / sub_freq))
	return frames.size() == expected


func test_synth_clamps_degenerate_inputs() -> bool:
	# base_freq <= 0, seconds == 0, and a sub-1000 sample_rate must clamp rather
	# than crash, still returning at least one in-range frame.
	var exhaust := VehicleAudioModel.exhaust_loop_frames(100, 0.0)
	var crash := VehicleAudioModel.crash_loop_frames(100, 0.0, 0)
	if exhaust.is_empty() or crash.is_empty():
		return false
	for f in exhaust:
		if absf(f) > 1.0:
			return false
	for f in crash:
		if absf(f) > 1.0:
			return false
	return true


func test_crash_loop_is_normalized() -> bool:
	var frames := VehicleAudioModel.crash_loop_frames(22050, 0.3, 99)
	var peak := 0.0
	for f in frames:
		peak = maxf(peak, absf(f))
	return absf(peak - 0.9) < 0.01


func test_crash_loop_is_deterministic_per_seed() -> bool:
	var a := VehicleAudioModel.crash_loop_frames(22050, 0.2, 5)
	var b := VehicleAudioModel.crash_loop_frames(22050, 0.2, 5)
	return a == b


func test_crash_loop_differs_across_seeds() -> bool:
	var a := VehicleAudioModel.crash_loop_frames(22050, 0.2, 1)
	var b := VehicleAudioModel.crash_loop_frames(22050, 0.2, 2)
	return a != b


func test_crash_loop_stays_in_range() -> bool:
	for f in VehicleAudioModel.crash_loop_frames(22050, 0.2, 3):
		if absf(f) > 0.95:
			return false
	return true
