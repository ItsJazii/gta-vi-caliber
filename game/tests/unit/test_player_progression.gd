extends RefCounted
## Unit tests for PlayerProgression (see tests/run_tests.gd: test_* return true
## to pass). Curve: leaving level L costs 100*L; cumulative reach(L) is the
## triangular sum 100*(L-1)*L/2.


func test_starts_at_level_one_zero_xp() -> bool:
	var p := PlayerProgression.new()
	return p.level() == 1 and p.xp() == 0 and p.total_xp() == 0


func test_xp_below_threshold_raises_progress_not_level() -> bool:
	var p := PlayerProgression.new()
	p.add_xp(60)
	return p.level() == 1 and p.xp_into_level() == 60


func test_total_xp_tracks_lifetime() -> bool:
	var p := PlayerProgression.new()
	p.add_xp(60)
	p.add_xp(20)
	return p.total_xp() == 80


func test_crossing_threshold_levels_up_with_leftover() -> bool:
	var p := PlayerProgression.new()
	# Leaving L1 costs 100; 150 -> level 2 with 50 carried in.
	p.add_xp(150)
	return p.level() == 2 and p.xp_into_level() == 50


func test_exact_threshold_levels_up_clean() -> bool:
	var p := PlayerProgression.new()
	p.add_xp(100)
	return p.level() == 2 and p.xp_into_level() == 0


func test_big_payout_multi_levels_with_remainder() -> bool:
	var p := PlayerProgression.new()
	# 700: -100 (L2) -200 (L3) -300 (L4) leaves 100 < 400.
	p.add_xp(700)
	return p.level() == 4 and p.xp_into_level() == 100


func test_xp_for_next_follows_curve() -> bool:
	var p := PlayerProgression.new()
	var at1 := p.xp_for_next()
	p.add_xp(100)
	var at2 := p.xp_for_next()
	p.add_xp(200)
	var at3 := p.xp_for_next()
	return at1 == 100 and at2 == 200 and at3 == 300


func test_level_progress_fraction() -> bool:
	var p := PlayerProgression.new()
	p.add_xp(25)
	# 25 of the 100 needed to leave level 1.
	return is_equal_approx(p.level_progress(), 0.25)


func test_level_progress_in_unit_range() -> bool:
	var p := PlayerProgression.new()
	p.add_xp(99)
	var lo := p.level_progress()
	p.reset()
	p.add_xp(1)
	var hi := p.level_progress()
	return lo >= 0.0 and lo <= 1.0 and hi >= 0.0 and hi <= 1.0


func test_xp_to_reach_curve() -> bool:
	return (
		PlayerProgression.xp_to_reach(1) == 0
		and PlayerProgression.xp_to_reach(2) == 100
		and PlayerProgression.xp_to_reach(3) == 300
		and PlayerProgression.xp_to_reach(4) == 600
	)


func test_xp_to_reach_matches_add_xp() -> bool:
	var p := PlayerProgression.new()
	# Exactly enough cumulative respect to sit at the start of level 5.
	p.add_xp(PlayerProgression.xp_to_reach(5))
	return p.level() == 5 and p.xp_into_level() == 0


func test_unlocks_at_returns_features() -> bool:
	var at5 := PlayerProgression.unlocks_at(5)
	return at5.has("sports_car") and at5.has("ammo_discount")


func test_unlocks_at_empty_when_none() -> bool:
	return PlayerProgression.unlocks_at(3).is_empty()


func test_is_unlocked_locked_below_gate() -> bool:
	var p := PlayerProgression.new()
	# Level 1: pistol_slot (gate 2) not yet earned.
	return not p.is_unlocked("pistol_slot")


func test_is_unlocked_flips_at_gate() -> bool:
	var p := PlayerProgression.new()
	p.add_xp(PlayerProgression.xp_to_reach(2))
	return p.is_unlocked("pistol_slot")


func test_is_unlocked_cumulative() -> bool:
	var p := PlayerProgression.new()
	p.add_xp(PlayerProgression.xp_to_reach(10))
	# Higher level still keeps lower-gate unlocks.
	return p.is_unlocked("pistol_slot") and p.is_unlocked("smg_slot")


func test_max_level_caps() -> bool:
	var p := PlayerProgression.new()
	p.add_xp(10_000_000)
	return (
		p.level() == PlayerProgression.MAX_LEVEL
		and p.is_max_level()
		and p.xp_for_next() == 0
		and is_equal_approx(p.level_progress(), 1.0)
	)


func test_xp_at_max_does_not_overflow_level() -> bool:
	var p := PlayerProgression.new()
	p.add_xp(10_000_000)
	var before := p.level()
	p.add_xp(500)
	# Surplus respect at cap is dropped; level holds, into-level stays 0.
	return p.level() == before and p.xp_into_level() == 0


func test_negative_xp_ignored() -> bool:
	var p := PlayerProgression.new()
	p.add_xp(-500)
	return p.level() == 1 and p.xp_into_level() == 0 and p.total_xp() == 0


func test_reset_restores_start() -> bool:
	var p := PlayerProgression.new()
	p.add_xp(5000)
	p.reset()
	return p.level() == 1 and p.xp_into_level() == 0 and p.total_xp() == 0


func test_tracker_save_round_trip_replays_curve() -> bool:
	# ProgressionTracker persists lifetime XP only; restoring replays it
	# through the curve, reconstructing level and within-level progress.
	var tracker := ProgressionTracker.new()
	tracker.restore({"total_xp": 1730})
	var reference := PlayerProgression.new()
	reference.add_xp(1730)
	var ok := (
		tracker.total_xp() == 1730
		and tracker.level() == reference.level()
		and absf(tracker.level_progress() - reference.level_progress()) < 0.0001
		and int(tracker.serialize().get("total_xp", 0)) == 1730
	)
	tracker.free()
	return ok


func test_tracker_restore_garbage_resets_clean() -> bool:
	var tracker := ProgressionTracker.new()
	tracker.restore({"total_xp": 990})
	tracker.restore({"total_xp": "junk"})
	var ok := tracker.total_xp() == 0 and tracker.level() == 1
	tracker.free()
	return ok
