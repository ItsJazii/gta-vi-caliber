extends RefCounted
## Unit tests for HeistCrew (see tests/run_tests.gd for the runner contract:
## test_* methods return true to pass). All rolls use a seeded rng.


func test_starts_empty() -> bool:
	var crew := HeistCrew.new()
	return (
		crew.member_count() == 0
		and is_equal_approx(crew.total_cut(), 0.0)
		and is_equal_approx(crew.crew_skill(), 0.0)
	)


func test_add_member_succeeds() -> bool:
	var crew := HeistCrew.new(3)
	var ok := crew.add_member("driver", 0.7, 0.2)
	return ok and crew.member_count() == 1 and crew.roles() == ["driver"]


func test_add_up_to_max_then_fails() -> bool:
	var crew := HeistCrew.new(2)
	var a := crew.add_member("driver", 0.5, 0.1)
	var b := crew.add_member("hacker", 0.5, 0.1)
	var c := crew.add_member("gunman", 0.5, 0.1)
	return a and b and not c and crew.member_count() == 2


func test_duplicate_role_rejected() -> bool:
	var crew := HeistCrew.new(3)
	crew.add_member("driver", 0.5, 0.1)
	var dup := crew.add_member("driver", 0.9, 0.1)
	return not dup and crew.member_count() == 1


func test_empty_role_rejected() -> bool:
	var crew := HeistCrew.new(3)
	return not crew.add_member("", 0.5, 0.1) and crew.member_count() == 0


func test_cut_over_one_hundred_percent_rejected() -> bool:
	var crew := HeistCrew.new(3)
	var a := crew.add_member("driver", 0.5, 0.6)
	var b := crew.add_member("hacker", 0.5, 0.5)
	return a and not b and is_equal_approx(crew.total_cut(), 0.6)


func test_total_cut_sums_members() -> bool:
	var crew := HeistCrew.new(3)
	crew.add_member("driver", 0.5, 0.2)
	crew.add_member("hacker", 0.5, 0.3)
	return is_equal_approx(crew.total_cut(), 0.5)


func test_player_share_is_remainder() -> bool:
	var crew := HeistCrew.new(3)
	crew.add_member("driver", 0.5, 0.2)
	crew.add_member("hacker", 0.5, 0.3)
	return is_equal_approx(crew.player_share(), 0.5)


func test_player_share_full_when_empty() -> bool:
	var crew := HeistCrew.new(3)
	# no crew -> player keeps the whole take
	return is_equal_approx(crew.player_share(), 1.0) and crew.payout(8000, true) == 8000


func test_crew_skill_is_average() -> bool:
	var crew := HeistCrew.new(3)
	crew.add_member("driver", 0.4, 0.1)
	crew.add_member("hacker", 0.8, 0.1)
	return is_equal_approx(crew.crew_skill(), 0.6)


func test_crew_skill_zero_when_empty() -> bool:
	var crew := HeistCrew.new(3)
	return is_equal_approx(crew.crew_skill(), 0.0)


func test_success_chance_pro_vs_empty() -> bool:
	var pro := HeistCrew.new(1)
	pro.add_member("ace", 1.0, 0.2)
	var empty := HeistCrew.new(1)
	# pro: 0.5 - 0.25 + 1.0*0.6 = 0.85 ; empty: 0.5 - 0.25 = 0.25
	return (
		is_equal_approx(pro.success_chance(0.5), 0.85)
		and is_equal_approx(empty.success_chance(0.5), 0.25)
	)


func test_success_chance_rises_with_skill() -> bool:
	var weak := HeistCrew.new(1)
	weak.add_member("rookie", 0.2, 0.1)
	var strong := HeistCrew.new(1)
	strong.add_member("ace", 0.9, 0.1)
	return strong.success_chance(0.5) > weak.success_chance(0.5)


func test_success_chance_falls_with_difficulty() -> bool:
	var crew := HeistCrew.new(1)
	crew.add_member("ace", 0.6, 0.1)
	return crew.success_chance(0.3) < crew.success_chance(0.8)


func test_success_chance_clamped() -> bool:
	var pro := HeistCrew.new(1)
	pro.add_member("ace", 1.0, 0.1)
	var empty := HeistCrew.new(1)
	# pro: 1.0 - 0.25 + 0.6 = 1.35 -> 1.0 ; empty at 0 difficulty: -0.25 -> 0.0
	return (
		is_equal_approx(pro.success_chance(1.0), 1.0)
		and is_equal_approx(empty.success_chance(0.0), 0.0)
	)


func test_attempt_deterministic_same_seed() -> bool:
	var crew := HeistCrew.new(1)
	crew.add_member("ace", 0.5, 0.2)
	var a := crew.attempt(0.5, HeistCrew.make_rng(42))
	var b := crew.attempt(0.5, HeistCrew.make_rng(42))
	# a null rng never rolls a success
	return a == b and not crew.attempt(0.5, null)


func test_attempt_near_certain_succeeds() -> bool:
	var crew := HeistCrew.new(1)
	crew.add_member("ace", 1.0, 0.1)
	# chance clamps to 1.0, so randf() < 1.0 always true
	return crew.attempt(1.0, HeistCrew.make_rng(7))


func test_attempt_hopeless_fails() -> bool:
	var crew := HeistCrew.new(1)
	# empty crew at zero difficulty: chance 0.0, randf() < 0.0 always false
	return not crew.attempt(0.0, HeistCrew.make_rng(7))


func test_payout_on_success() -> bool:
	var crew := HeistCrew.new(2)
	crew.add_member("driver", 0.5, 0.2)
	crew.add_member("hacker", 0.5, 0.3)
	# share 0.5 of 10000 = 5000
	return crew.payout(10000, true) == 5000


func test_payout_zero_on_failure() -> bool:
	var crew := HeistCrew.new(2)
	crew.add_member("driver", 0.5, 0.2)
	return crew.payout(10000, false) == 0


func test_payout_non_negative_and_zero_take() -> bool:
	var crew := HeistCrew.new(1)
	crew.add_member("driver", 0.5, 0.2)
	return crew.payout(0, true) == 0 and crew.payout(-100, true) == 0


func test_expected_payout_matches_hand_calc() -> bool:
	var crew := HeistCrew.new(1)
	crew.add_member("ace", 1.0, 0.2)
	# chance(0.5)=0.85, share=0.8, take=10000 -> 0.85*10000*0.8 = 6800
	return is_equal_approx(crew.expected_payout(10000, 0.5), 6800.0)


func test_expected_payout_zero_take() -> bool:
	var crew := HeistCrew.new(1)
	crew.add_member("ace", 1.0, 0.2)
	return is_equal_approx(crew.expected_payout(0, 0.5), 0.0)


func test_remove_member() -> bool:
	var crew := HeistCrew.new(3)
	crew.add_member("driver", 0.5, 0.2)
	crew.add_member("hacker", 0.5, 0.3)
	var removed := crew.remove_member("driver")
	return (
		removed
		and crew.member_count() == 1
		and crew.roles() == ["hacker"]
		and is_equal_approx(crew.total_cut(), 0.3)
	)


func test_remove_missing_member_returns_false() -> bool:
	var crew := HeistCrew.new(3)
	crew.add_member("driver", 0.5, 0.2)
	return not crew.remove_member("ghost") and crew.member_count() == 1
