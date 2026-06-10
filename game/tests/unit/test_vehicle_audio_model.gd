extends RefCounted
## Unit tests for VehicleAudioModel — the pure math behind engine/tire/impact
## audio. Synthesis must be deterministic, normalized, and seam-free.


func test_pitch_tracks_rpm_linearly() -> bool:
	return absf(VehicleAudioModel.pitch_for_rpm(3000.0, 1500.0) - 2.0) < 0.001


func test_pitch_is_clamped_both_ends() -> bool:
	var low := VehicleAudioModel.pitch_for_rpm(0.0, 1500.0)
	var high := VehicleAudioModel.pitch_for_rpm(99000.0, 1500.0)
	return absf(low - 0.5) < 0.001 and absf(high - 3.0) < 0.001


func test_pitch_handles_zero_base_rpm() -> bool:
	return absf(VehicleAudioModel.pitch_for_rpm(2000.0, 0.0) - 1.0) < 0.001


func test_engine_volume_rises_with_throttle() -> bool:
	var idle := VehicleAudioModel.engine_volume_db(0.0, 850.0, 850.0, 6500.0)
	var full := VehicleAudioModel.engine_volume_db(1.0, 850.0, 850.0, 6500.0)
	return full > idle


func test_engine_volume_rises_with_rpm_when_coasting() -> bool:
	var low := VehicleAudioModel.engine_volume_db(0.0, 850.0, 850.0, 6500.0)
	var high := VehicleAudioModel.engine_volume_db(0.0, 6500.0, 850.0, 6500.0)
	return high > low


func test_engine_volume_never_exceeds_unity() -> bool:
	return VehicleAudioModel.engine_volume_db(1.0, 9999.0, 850.0, 6500.0) <= 0.001


func test_skid_silent_at_full_grip() -> bool:
	return VehicleAudioModel.skid_volume_db(0.0) <= VehicleAudioModel.SILENT_DB


func test_skid_silent_below_threshold() -> bool:
	var s := VehicleAudioModel.SKID_SILENCE_SLIP - 0.01
	return VehicleAudioModel.skid_volume_db(s) <= VehicleAudioModel.SILENT_DB


func test_skid_full_slip_is_unity() -> bool:
	return absf(VehicleAudioModel.skid_volume_db(1.0)) < 0.001


func test_skid_monotonic_above_threshold() -> bool:
	var a := VehicleAudioModel.skid_volume_db(0.4)
	var b := VehicleAudioModel.skid_volume_db(0.7)
	return b > a


func test_impact_silent_below_threshold() -> bool:
	return VehicleAudioModel.impact_volume_db(5.0, 6.0, 20.0) <= VehicleAudioModel.SILENT_DB


func test_impact_saturates_at_full_dv() -> bool:
	return absf(VehicleAudioModel.impact_volume_db(25.0, 6.0, 20.0)) < 0.001


func test_impact_degenerate_range_is_silent() -> bool:
	return VehicleAudioModel.impact_volume_db(10.0, 6.0, 6.0) <= VehicleAudioModel.SILENT_DB


func test_engine_loop_is_normalized() -> bool:
	var frames := VehicleAudioModel.engine_loop_frames(22050, 50.0)
	var peak := 0.0
	for f in frames:
		peak = maxf(peak, absf(f))
	return absf(peak - 0.9) < 0.01


func test_engine_loop_seam_is_continuous() -> bool:
	# Whole cycles ⇒ wrapping from last back to first frame must not jump.
	var frames := VehicleAudioModel.engine_loop_frames(22050, 50.0)
	var step := absf(frames[0] - frames[frames.size() - 1])
	var typical := absf(frames[1] - frames[0])
	return step < typical * 3.0 + 0.01


func test_engine_loop_length_matches_cycles() -> bool:
	var frames := VehicleAudioModel.engine_loop_frames(22050, 50.0)
	var expected := int(round(22050.0 * VehicleAudioModel.ENGINE_LOOP_CYCLES / 50.0))
	return frames.size() == expected


func test_noise_is_deterministic_per_seed() -> bool:
	var a := VehicleAudioModel.noise_loop_frames(22050, 0.1, 42)
	var b := VehicleAudioModel.noise_loop_frames(22050, 0.1, 42)
	return a == b


func test_noise_differs_across_seeds() -> bool:
	var a := VehicleAudioModel.noise_loop_frames(22050, 0.1, 1)
	var b := VehicleAudioModel.noise_loop_frames(22050, 0.1, 2)
	return a != b


func test_noise_stays_in_range() -> bool:
	for f in VehicleAudioModel.noise_loop_frames(22050, 0.2, 7):
		if absf(f) > 0.95:
			return false
	return true


func test_wav16_is_two_bytes_per_frame() -> bool:
	var frames := PackedFloat32Array([0.0, 0.5, -0.5, 1.0])
	return VehicleAudioModel.frames_to_wav16(frames).size() == 8


func test_wav16_clamps_overdrive() -> bool:
	var bytes := VehicleAudioModel.frames_to_wav16(PackedFloat32Array([2.0, -2.0]))
	return bytes.decode_s16(0) == 32767 and bytes.decode_s16(2) == -32767
