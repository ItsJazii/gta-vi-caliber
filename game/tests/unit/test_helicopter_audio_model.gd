extends RefCounted
## Unit tests for HelicopterAudioModel (see tests/run_tests.gd for the runner
## contract: test_* methods return true to pass). Deterministic synthesis, so
## the loops are checked structurally: length, normalization, seam continuity,
## pulse decay and sweep cycle count.

const RATE := 22050


func test_rotor_loop_length_holds_whole_pulses() -> bool:
	var frames := HelicopterAudioModel.rotor_loop_frames(RATE, 17.3)
	var expected := int(round(float(RATE) * HelicopterAudioModel.ROTOR_LOOP_PULSES / 17.3))
	return frames.size() == expected


func test_rotor_loop_normalized_and_finite() -> bool:
	var frames := HelicopterAudioModel.rotor_loop_frames(RATE)
	var peak := 0.0
	for s in frames:
		if not is_finite(s):
			return false
		peak = maxf(peak, absf(s))
	return peak > 0.5 and peak <= 0.901


func test_rotor_pulse_front_louder_than_tail() -> bool:
	# The thump envelope decays across each blade pass: the first quarter of a
	# pulse must carry more energy than the last quarter (averaged over loop).
	var hz := HelicopterAudioModel.DEFAULT_PULSE_HZ
	var frames := HelicopterAudioModel.rotor_loop_frames(RATE, hz)
	var period := float(RATE) / hz
	var front := 0.0
	var tail := 0.0
	var n := 0
	for p in HelicopterAudioModel.ROTOR_LOOP_PULSES:
		var base := int(float(p) * period)
		var quarter := int(period * 0.25)
		for i in quarter:
			if base + int(period) >= frames.size():
				break
			front += absf(frames[base + i])
			tail += absf(frames[base + int(period * 0.75) + i])
			n += 1
	return n > 0 and front > tail * 1.5


func test_rotor_deterministic() -> bool:
	var a := HelicopterAudioModel.rotor_loop_frames(RATE)
	var b := HelicopterAudioModel.rotor_loop_frames(RATE)
	return a == b


func test_siren_seam_is_phase_continuous() -> bool:
	# Total phase is an exact whole cycle count, so wrapping from the last
	# sample to the first is just one more carrier step — the seam jump must
	# not exceed the largest step inside the loop (no click on repeat).
	var frames := HelicopterAudioModel.siren_loop_frames(RATE)
	var max_step := 0.0
	for i in range(1, frames.size()):
		max_step = maxf(max_step, absf(frames[i] - frames[i - 1]))
	var seam := absf(frames[0] - frames[frames.size() - 1])
	return seam <= max_step * 1.05 + 0.001


func test_siren_sweep_cycle_count_matches_design() -> bool:
	var lo := HelicopterAudioModel.SIREN_LOW_HZ
	var hi := HelicopterAudioModel.SIREN_HIGH_HZ
	var frames := HelicopterAudioModel.siren_loop_frames(RATE, lo, hi, 0.55)
	var crossings := 0
	for i in range(1, frames.size()):
		if (frames[i - 1] < 0.0) != (frames[i] < 0.0):
			crossings += 1
	# Two zero crossings per carrier cycle; cycles = round(avg / sweep).
	var cycles := int(round((lo + hi) * 0.5 / 0.55))
	return absi(crossings - cycles * 2) <= 6


func test_siren_normalized() -> bool:
	var frames := HelicopterAudioModel.siren_loop_frames(RATE)
	var peak := 0.0
	for s in frames:
		peak = maxf(peak, absf(s))
	return peak > 0.5 and peak <= 0.95


func test_siren_degenerate_inputs_survive() -> bool:
	# Swapped/equal bounds and absurd sweep rates must still produce a loop.
	var swapped := HelicopterAudioModel.siren_loop_frames(RATE, 1250.0, 620.0, 0.55)
	var flat := HelicopterAudioModel.siren_loop_frames(RATE, 700.0, 700.0, 0.55)
	var fast := HelicopterAudioModel.siren_loop_frames(8000, 620.0, 1250.0, 5000.0)
	return swapped.size() > 0 and flat.size() > 0 and fast.size() > 0
