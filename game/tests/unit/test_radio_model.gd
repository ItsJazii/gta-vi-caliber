extends RefCounted
## Unit tests for RadioModel (see tests/run_tests.gd for the runner contract:
## test_* methods return true to pass).

const RATE: int = 22050


func test_station_count_positive() -> bool:
	return RadioModel.station_count() >= 2


func test_tune_next_advances() -> bool:
	return RadioModel.tune(0, 1) == 1


func test_tune_wraps_forward() -> bool:
	return RadioModel.tune(RadioModel.station_count() - 1, 1) == 0


func test_tune_wraps_backward() -> bool:
	return RadioModel.tune(0, -1) == RadioModel.station_count() - 1


func test_note_hz_octave_doubles() -> bool:
	return absf(RadioModel.note_hz(220.0, 12) - 440.0) < 0.5


func test_loop_length_matches_pattern() -> bool:
	# Loop length = steps * notes; just assert it's a positive whole multiple.
	var frames := RadioModel.loop_frames(RATE, 0)
	return frames.size() > 0 and frames.size() % RadioModel.STATIONS[0]["notes"].size() == 0


func test_loop_bounded() -> bool:
	var frames := RadioModel.loop_frames(RATE, 1)
	for v in frames:
		if absf(v) > 1.0:
			return false
	return true


func test_loop_deterministic() -> bool:
	var first := RadioModel.loop_frames(RATE, 0)
	var second := RadioModel.loop_frames(RATE, 0)
	return first == second


func test_stations_differ() -> bool:
	return RadioModel.loop_frames(RATE, 0) != RadioModel.loop_frames(RATE, 2)


func test_loop_index_clamps() -> bool:
	# Out-of-range index must not crash; clamps to a valid station.
	return RadioModel.loop_frames(RATE, 99).size() > 0


func test_wav16_two_bytes_per_frame() -> bool:
	var frames := RadioModel.loop_frames(RATE, 0)
	return RadioModel.frames_to_wav16(frames).size() == frames.size() * 2
