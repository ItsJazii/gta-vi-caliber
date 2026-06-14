extends RefCounted
## Unit tests for MeleeImpactAudioModel (see tests/run_tests.gd for the runner
## contract: test_* methods return true to pass). Deterministic, no asserts.

const RATE: int = 22050


func _peak(frames: PackedFloat32Array) -> float:
	var p := 0.0
	for v in frames:
		p = maxf(p, absf(v))
	return p


func test_params_unknown_falls_back_to_jab() -> bool:
	var bogus := MeleeImpactAudioModel.params_for_strike(999, false)
	var jab := MeleeImpactAudioModel.params_for_strike(MeleeCombat.Strike.JAB, false)
	return bogus == jab


func test_frame_length_matches_duration() -> bool:
	var dur: float = float(
		MeleeImpactAudioModel.params_for_strike(MeleeCombat.Strike.KICK, false)["duration"]
	)
	var frames := MeleeImpactAudioModel.impact_frames(RATE, MeleeCombat.Strike.KICK, false, 1)
	return frames.size() == int(float(RATE) * dur)


func test_frames_bounded() -> bool:
	for strike in [
		MeleeCombat.Strike.JAB,
		MeleeCombat.Strike.CROSS,
		MeleeCombat.Strike.KICK,
		MeleeCombat.Strike.HEAVY,
	]:
		for killed in [false, true]:
			for v in MeleeImpactAudioModel.impact_frames(RATE, strike, killed, 5):
				if absf(v) > 1.0:
					return false
	return true


func test_peak_matches_amp() -> bool:
	# Normalisation drives the peak to the voicing's amp (heavy ~0.9), proving a
	# real signal and the amplitude target.
	var amp: float = float(
		MeleeImpactAudioModel.params_for_strike(MeleeCombat.Strike.HEAVY, false)["amp"]
	)
	var frames := MeleeImpactAudioModel.impact_frames(RATE, MeleeCombat.Strike.HEAVY, false, 3)
	return absf(_peak(frames) - amp) < 0.01


func test_amplitude_rises_jab_to_heavy() -> bool:
	var jab := _peak(MeleeImpactAudioModel.impact_frames(RATE, MeleeCombat.Strike.JAB, false, 2))
	var cross := _peak(
		MeleeImpactAudioModel.impact_frames(RATE, MeleeCombat.Strike.CROSS, false, 2)
	)
	var kick := _peak(MeleeImpactAudioModel.impact_frames(RATE, MeleeCombat.Strike.KICK, false, 2))
	var heavy := _peak(
		MeleeImpactAudioModel.impact_frames(RATE, MeleeCombat.Strike.HEAVY, false, 2)
	)
	return jab < cross and cross < kick and kick < heavy


func test_duration_rises_jab_to_heavy() -> bool:
	var jab := MeleeImpactAudioModel.impact_frames(RATE, MeleeCombat.Strike.JAB, false, 2).size()
	var cross := (
		MeleeImpactAudioModel.impact_frames(RATE, MeleeCombat.Strike.CROSS, false, 2).size()
	)
	var kick := MeleeImpactAudioModel.impact_frames(RATE, MeleeCombat.Strike.KICK, false, 2).size()
	var heavy := (
		MeleeImpactAudioModel.impact_frames(RATE, MeleeCombat.Strike.HEAVY, false, 2).size()
	)
	return jab < cross and cross < kick and kick < heavy


func test_kill_is_meatiest() -> bool:
	# A kill is the lowest, longest, loudest impact: louder peak, more frames, and
	# a lower body pitch than even a non-kill heavy.
	var heavy_f := MeleeImpactAudioModel.impact_frames(RATE, MeleeCombat.Strike.HEAVY, false, 4)
	var kill_f := MeleeImpactAudioModel.impact_frames(RATE, MeleeCombat.Strike.HEAVY, true, 4)
	var heavy_hz: float = float(
		MeleeImpactAudioModel.params_for_strike(MeleeCombat.Strike.HEAVY, false)["thud_hz"]
	)
	var kill_hz: float = float(
		MeleeImpactAudioModel.params_for_strike(MeleeCombat.Strike.HEAVY, true)["thud_hz"]
	)
	return _peak(kill_f) > _peak(heavy_f) and kill_f.size() > heavy_f.size() and kill_hz < heavy_hz


func test_deterministic_for_seed() -> bool:
	var a := MeleeImpactAudioModel.impact_frames(RATE, MeleeCombat.Strike.KICK, false, 42)
	var b := MeleeImpactAudioModel.impact_frames(RATE, MeleeCombat.Strike.KICK, false, 42)
	return a == b


func test_strikes_differ_in_timbre() -> bool:
	var jab := MeleeImpactAudioModel.impact_frames(RATE, MeleeCombat.Strike.JAB, false, 7)
	var heavy := MeleeImpactAudioModel.impact_frames(RATE, MeleeCombat.Strike.HEAVY, false, 7)
	return jab != heavy


func test_wav16_packs_two_bytes_per_frame() -> bool:
	var frames := MeleeImpactAudioModel.impact_frames(RATE, MeleeCombat.Strike.CROSS, false, 9)
	return MeleeImpactAudioModel.frames_to_wav16(frames).size() == frames.size() * 2


func test_wav16_clamps_out_of_range() -> bool:
	var bytes := MeleeImpactAudioModel.frames_to_wav16(PackedFloat32Array([2.0, -2.0]))
	return bytes.decode_s16(0) == 32767 and bytes.decode_s16(2) == -32767
