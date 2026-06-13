extends RefCounted
## Unit tests for StuntScore (see tests/run_tests.gd for the runner contract:
## test_* methods return true to pass).
##
## Includes a PlayerProgression composition test: a banked combo's respect payout
## grants XP.


func test_fresh_is_empty() -> bool:
	var s := StuntScore.new()
	return (
		not s.has_combo()
		and s.combo_count() == 0
		and is_equal_approx(s.multiplier(), 1.0)
		and s.pending_score() == 0
		and s.total_score() == 0
	)


func test_trick_kinds_present() -> bool:
	var s := StuntScore.new()
	return s.trick_kinds().has("flip") and s.trick_kinds().has("near_miss")


func test_add_trick_scores_points() -> bool:
	var s := StuntScore.new()
	var pts := s.add_trick("jump", 2.0)  # 50 * 2 = 100
	return pts == 100 and s.combo_count() == 1 and s.pending_score() == 100


func test_add_trick_rejects_bad_input() -> bool:
	var s := StuntScore.new()
	return s.add_trick("moonwalk", 1.0) == 0 and s.add_trick("jump", 0.0) == 0 and not s.has_combo()


func test_multiplier_grows_with_combo() -> bool:
	var s := StuntScore.new()
	s.add_trick("jump", 2.0)  # count 1 -> mult 1.0
	var m1 := s.multiplier()
	s.add_trick("flip", 1.0)  # count 2 -> mult 1.5
	return is_equal_approx(m1, 1.0) and is_equal_approx(s.multiplier(), 1.5)


func test_pending_applies_multiplier() -> bool:
	var s := StuntScore.new()
	s.add_trick("jump", 2.0)  # 100
	s.add_trick("flip", 1.0)  # +250 -> 350 raw, mult 1.5
	return s.pending_score() == 525


func test_multiplier_caps() -> bool:
	var s := StuntScore.new()
	for _i in range(20):
		s.add_trick("wheelie", 1.0)
	return is_equal_approx(s.multiplier(), StuntScore.MAX_MULT)


func test_bank_banks_and_resets() -> bool:
	var s := StuntScore.new()
	s.add_trick("jump", 2.0)
	s.add_trick("flip", 1.0)  # pending 525
	var banked := s.bank()
	return banked == 525 and s.total_score() == 525 and not s.has_combo() and s.pending_score() == 0


func test_wipe_forfeits_and_resets() -> bool:
	var s := StuntScore.new()
	s.add_trick("jump", 2.0)  # pending 100
	var lost := s.wipe()
	return lost == 100 and s.total_score() == 0 and not s.has_combo()


func test_total_and_best_accumulate() -> bool:
	var s := StuntScore.new()
	s.add_trick("flip", 1.0)  # 250
	s.bank()
	s.add_trick("jump", 2.0)  # 100
	s.add_trick("spin", 1.0)  # +150 -> 250 raw, mult 1.5 -> 375
	s.bank()
	return s.total_score() == 625 and s.best_combo() == 375


func test_reward_helpers() -> bool:
	return StuntScore.cash_for(500) == 500 and StuntScore.respect_for(500) == 50


func test_banked_combo_grants_progression_respect() -> bool:
	# Composition: a clean landing's respect payout feeds PlayerProgression.
	var s := StuntScore.new()
	s.add_trick("flip", 2.0)  # 500
	s.add_trick("spin", 2.0)  # +300 -> 800 raw, mult 1.5 -> 1200
	var banked := s.bank()
	var prog := PlayerProgression.new()
	prog.add_xp(StuntScore.respect_for(banked))
	return banked == 1200 and prog.total_xp() == 120
