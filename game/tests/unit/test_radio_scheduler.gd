extends RefCounted
## Unit tests for RadioScheduler (see tests/run_tests.gd: test_* methods return
## true to pass). All randomness is seeded for determinism.

const SONGS: Array = ["s1", "s2", "s3", "s4", "s5"]
const ADS: Array = ["ad_burger", "ad_lawyer"]
const STATION_ID: String = "WAVE 87.4"


func _rng(seed_value: int = 1) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _scheduler() -> RadioScheduler:
	return RadioScheduler.new(SONGS, ADS, STATION_ID)


# --- next_segment ------------------------------------------------------------


func test_next_segment_song_early() -> bool:
	var sch := _scheduler()
	var rng := _rng()
	return (
		sch.next_segment(0, rng) == RadioScheduler.Segment.SONG
		and sch.next_segment(1, rng) == RadioScheduler.Segment.SONG
		and sch.next_segment(3, rng) == RadioScheduler.Segment.SONG
	)


func test_next_segment_forces_break() -> bool:
	var sch := _scheduler()
	var seg := sch.next_segment(RadioScheduler.BREAK_AFTER_SONGS, _rng())
	return seg != RadioScheduler.Segment.SONG


func test_next_segment_deterministic() -> bool:
	var a := _scheduler().next_segment(RadioScheduler.BREAK_AFTER_SONGS, _rng(42))
	var b := _scheduler().next_segment(RadioScheduler.BREAK_AFTER_SONGS, _rng(42))
	return a == b


func test_next_segment_empty_pool_is_break() -> bool:
	var sch := RadioScheduler.new([], ADS, STATION_ID)
	# Even at counter 0 with an empty song pool it must not ask for a song.
	return sch.next_segment(0, _rng()) != RadioScheduler.Segment.SONG


# --- pick_song ---------------------------------------------------------------


func test_pick_song_non_empty() -> bool:
	var picked := _scheduler().pick_song(_rng(), [])
	return SONGS.has(picked)


func test_pick_song_avoids_recent() -> bool:
	var sch := _scheduler()
	var recent: Array = ["s1", "s2", "s3", "s4"]
	# Only s5 is fresh, so it must be chosen across several seeds.
	var ok := true
	for s in range(1, 8):
		if sch.pick_song(_rng(s), recent) != "s5":
			ok = false
	return ok


func test_pick_song_falls_back_when_all_recent() -> bool:
	var sch := _scheduler()
	var picked := sch.pick_song(_rng(), SONGS)
	return SONGS.has(picked)


func test_pick_song_empty_pool() -> bool:
	var sch := RadioScheduler.new([], ADS, STATION_ID)
	return sch.pick_song(_rng(), []) == ""


func test_pick_song_deterministic() -> bool:
	var first := _scheduler().pick_song(_rng(7), [])
	var second := _scheduler().pick_song(_rng(7), [])
	return first == second


# --- pick_ad -----------------------------------------------------------------


func test_pick_ad_valid() -> bool:
	return ADS.has(_scheduler().pick_ad(_rng()))


func test_pick_ad_empty_pool() -> bool:
	return RadioScheduler.new(SONGS, [], STATION_ID).pick_ad(_rng()) == ""


# --- advance / runner --------------------------------------------------------


func test_advance_starts_with_song() -> bool:
	var sch := _scheduler()
	var step := sch.advance(_rng())
	return step["segment"] == RadioScheduler.Segment.SONG and SONGS.has(step["id"])


func test_advance_counter_increments() -> bool:
	var sch := _scheduler()
	var rng := _rng()
	sch.advance(rng)
	sch.advance(rng)
	return sch.songs_since_break() == 2


func test_advance_hits_break_after_n_songs() -> bool:
	var sch := _scheduler()
	var rng := _rng(3)
	var saw_break := false
	for i in range(RadioScheduler.BREAK_AFTER_SONGS + 1):
		var step := sch.advance(rng)
		if step["segment"] != RadioScheduler.Segment.SONG:
			saw_break = true
	return saw_break


func test_advance_resets_counter_after_break() -> bool:
	var sch := _scheduler()
	var rng := _rng(3)
	# Drive past the break, then confirm the counter went back to 0 on it.
	var reset_seen := false
	for i in range(RadioScheduler.BREAK_AFTER_SONGS + 2):
		var step := sch.advance(rng)
		if step["segment"] != RadioScheduler.Segment.SONG:
			reset_seen = sch.songs_since_break() == 0
			break
	return reset_seen


func test_advance_avoids_immediate_song_repeat() -> bool:
	# Two-song pool: consecutive songs must alternate (recent history blocks repeats).
	var sch := RadioScheduler.new(["a", "b"], ADS, STATION_ID)
	var rng := _rng(5)
	var last := ""
	var ok := true
	for i in range(3):
		var step := sch.advance(rng)
		if step["segment"] == RadioScheduler.Segment.SONG:
			if step["id"] == last:
				ok = false
			last = step["id"]
	return ok


func test_now_playing_tracks_last_advance() -> bool:
	var sch := _scheduler()
	var rng := _rng()
	var step := sch.advance(rng)
	return sch.now_playing() == step


func test_now_playing_empty_before_advance() -> bool:
	return _scheduler().now_playing().is_empty()


func test_advance_empty_song_pool_safe() -> bool:
	# DJ/AD/ID/NEWS only; never crashes, never claims to play a song.
	var sch := RadioScheduler.new([], ADS, STATION_ID)
	var rng := _rng()
	var ok := true
	for i in range(6):
		var step := sch.advance(rng)
		if step["segment"] == RadioScheduler.Segment.SONG:
			ok = false
	return ok and sch.songs_since_break() == 0


func test_id_segment_uses_station_id() -> bool:
	var sch := RadioScheduler.new([], [], STATION_ID)
	# With empty ads, breaks are DJ/NEWS/ID; find an ID and check its payload.
	var rng := _rng(2)
	var found := false
	for i in range(60):
		var step := sch.advance(rng)
		if step["segment"] == RadioScheduler.Segment.ID:
			found = step["id"] == STATION_ID
			break
	return found


# --- segment_name ------------------------------------------------------------


func test_segment_name_mapping() -> bool:
	var sch := _scheduler()
	return (
		sch.segment_name(RadioScheduler.Segment.SONG) == "SONG"
		and sch.segment_name(RadioScheduler.Segment.DJ) == "DJ"
		and sch.segment_name(RadioScheduler.Segment.AD) == "AD"
		and sch.segment_name(RadioScheduler.Segment.NEWS) == "NEWS"
		and sch.segment_name(RadioScheduler.Segment.ID) == "ID"
	)


func test_segment_name_unknown() -> bool:
	return _scheduler().segment_name(99) == "UNKNOWN"
