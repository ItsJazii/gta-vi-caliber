extends RefCounted
## Unit tests for RadioModel (see tests/run_tests.gd for the runner contract:
## test_* methods return true to pass). Covers station tuning, per-station track
## cycling, and the deterministic seam-free synthesis.

const RATE: int = 22050


func test_station_count_positive() -> bool:
	return RadioModel.station_count() >= 2


func test_every_station_has_a_track() -> bool:
	for s in RadioModel.station_count():
		if RadioModel.track_count(s) < 1:
			return false
	return true


func test_tune_next_advances() -> bool:
	return RadioModel.tune(0, 1) == 1


func test_tune_wraps_forward() -> bool:
	return RadioModel.tune(RadioModel.station_count() - 1, 1) == 0


func test_tune_wraps_backward() -> bool:
	return RadioModel.tune(0, -1) == RadioModel.station_count() - 1


func test_cycle_track_wraps_forward() -> bool:
	# Station 0 has >= 2 tracks; cycling past the last wraps to 0.
	var last := RadioModel.track_count(0) - 1
	return RadioModel.cycle_track(0, last, 1) == 0


func test_cycle_track_wraps_backward() -> bool:
	return RadioModel.cycle_track(0, 0, -1) == RadioModel.track_count(0) - 1


func test_cycle_track_single_track_station_stays() -> bool:
	# Find a station with exactly one track and confirm cycling is a no-op.
	for s in RadioModel.station_count():
		if RadioModel.track_count(s) == 1:
			return RadioModel.cycle_track(s, 0, 1) == 0
	return true  # Vacuously true if every station has multiple tracks.


func test_note_hz_octave_doubles() -> bool:
	return absf(RadioModel.note_hz(220.0, 12) - 440.0) < 0.5


func test_default_track_argument_matches_track_zero() -> bool:
	# The 2-arg call (used by older callers) must equal explicit track 0.
	return RadioModel.loop_frames(RATE, 1) == RadioModel.loop_frames(RATE, 1, 0)


func test_loop_length_matches_pattern() -> bool:
	var frames := RadioModel.loop_frames(RATE, 0, 0)
	var notes_n := (RadioModel.STATIONS[0]["tracks"][0]["notes"] as Array).size()
	return frames.size() > 0 and frames.size() % notes_n == 0


func test_loop_bounded() -> bool:
	var frames := RadioModel.loop_frames(RATE, 1, 0)
	for v in frames:
		if absf(v) > 1.0:
			return false
	return true


func test_loop_starts_and_ends_near_silence() -> bool:
	# Attack from 0 and a release taper keep the seam click-free.
	var frames := RadioModel.loop_frames(RATE, 0, 0)
	return absf(frames[0]) < 0.001 and absf(frames[frames.size() - 1]) < 0.05


func test_loop_deterministic() -> bool:
	var first := RadioModel.loop_frames(RATE, 0, 1)
	var second := RadioModel.loop_frames(RATE, 0, 1)
	return first == second


func test_stations_differ() -> bool:
	return RadioModel.loop_frames(RATE, 0, 0) != RadioModel.loop_frames(RATE, 2, 0)


func test_tracks_within_station_differ() -> bool:
	return RadioModel.loop_frames(RATE, 0, 0) != RadioModel.loop_frames(RATE, 0, 1)


func test_loop_station_index_clamps() -> bool:
	# Out-of-range station must not crash; clamps to a valid station.
	return RadioModel.loop_frames(RATE, 99, 0).size() > 0


func test_loop_track_index_clamps() -> bool:
	return RadioModel.loop_frames(RATE, 0, 99).size() > 0


func test_loop_frames_clamps_low_sample_rate() -> bool:
	# A sub-1000 sample_rate must clamp (not crash) and stay bounded.
	var frames := RadioModel.loop_frames(10, 0, 0)
	if frames.is_empty():
		return false
	for v in frames:
		if absf(v) > 1.0:
			return false
	return true


func test_track_play_seconds_is_loop_times_repeats() -> bool:
	var loop := RadioModel.loop_seconds(0, 0)
	var repeats := float(RadioModel.STATIONS[0]["tracks"][0]["repeats"])
	var play := RadioModel.track_play_seconds(0, 0)
	return play > 0.0 and absf(play - loop * repeats) < 0.001


func test_station_and_track_names_non_empty() -> bool:
	return RadioModel.station_name(0).length() > 0 and RadioModel.track_title(0, 0).length() > 0


func test_wav16_two_bytes_per_frame() -> bool:
	var frames := RadioModel.loop_frames(RATE, 0, 0)
	return RadioModel.frames_to_wav16(frames).size() == frames.size() * 2
