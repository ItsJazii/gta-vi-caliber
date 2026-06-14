extends RefCounted
## Unit tests for CasinoGames (see tests/run_tests.gd: test_* methods return true
## to pass). All randomness uses a seeded RandomNumberGenerator so spins are
## deterministic.


func _seeded(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


# --- Roulette ----------------------------------------------------------------


func test_roulette_straight_pays_35_to_1() -> bool:
	# 35:1 means a 10 stake returns 360 total (stake + 350).
	return CasinoGames.roulette_payout("straight", 17, 10) == 360


func test_roulette_red_win_and_loss() -> bool:
	# 1 is red (returns 100 on a 50 stake); 2 is black, so red loses.
	return (
		CasinoGames.roulette_payout("red", 1, 50) == 100
		and CasinoGames.roulette_payout("red", 2, 50) == 0
	)


func test_roulette_even_and_odd() -> bool:
	return (
		CasinoGames.roulette_payout("even", 4, 10) == 20
		and CasinoGames.roulette_payout("even", 5, 10) == 0
		and CasinoGames.roulette_payout("odd", 5, 10) == 20
	)


func test_roulette_dozen_pays_2_to_1() -> bool:
	# 13 is in dozen2: a 10 stake returns 30; outside dozen2 loses.
	return (
		CasinoGames.roulette_payout("dozen2", 13, 10) == 30
		and CasinoGames.roulette_payout("dozen2", 5, 10) == 0
	)


func test_roulette_zero_loses_outside_bets() -> bool:
	return (
		CasinoGames.roulette_payout("even", 0, 10) == 0
		and CasinoGames.roulette_payout("red", 0, 10) == 0
		and CasinoGames.roulette_payout("dozen1", 0, 10) == 0
	)


func test_roulette_spin_in_range_and_reproducible() -> bool:
	var rng := _seeded(2024)
	for _i in range(200):
		var n: int = CasinoGames.roulette_spin(rng)
		if n < 0 or n > 36:
			return false
	# Same seed -> same first pocket (two independent generators).
	var first: int = CasinoGames.roulette_spin(_seeded(99))
	var again: int = CasinoGames.roulette_spin(_seeded(99))
	return first == again


# --- Slots -------------------------------------------------------------------


func test_slot_three_of_a_kind_pays_by_symbol() -> bool:
	# Three sevens at 100x and three cherries at 5x on a 10 stake.
	return (
		CasinoGames.slot_payout(["seven", "seven", "seven"], 10) == 1000
		and CasinoGames.slot_payout(["cherry", "cherry", "cherry"], 10) == 50
	)


func test_slot_two_of_a_kind_partial() -> bool:
	# Any pair pays the flat 2x: 10 stake returns 20.
	return CasinoGames.slot_payout(["bell", "bell", "seven"], 10) == 20


func test_slot_no_match_returns_zero() -> bool:
	return CasinoGames.slot_payout(["cherry", "bell", "seven"], 10) == 0


func test_slot_spin_count_symbols_reproducible() -> bool:
	var result: Array = CasinoGames.slot_spin(_seeded(7), 3)
	if result.size() != 3:
		return false
	for symbol in result:
		if not CasinoGames.SLOT_SYMBOLS.has(symbol):
			return false
	# Same seed -> identical reel result (two independent generators).
	var spin_a: Array = CasinoGames.slot_spin(_seeded(55), 3)
	var spin_b: Array = CasinoGames.slot_spin(_seeded(55), 3)
	return spin_a == spin_b


# --- Blackjack ---------------------------------------------------------------


func test_hand_value_hard_and_soft_ace() -> bool:
	# 10 + 7 = hard 17; Ace + 6 = soft 17 (ace as 11).
	return CasinoGames.hand_value([10, 7]) == 17 and CasinoGames.hand_value(["A", 6]) == 17


func test_hand_value_aces_demote_to_avoid_bust() -> bool:
	# Ace + 6 + 10 = 17 (ace drops to 1); A + A + 9 = 21 (one 11, one 1).
	return (
		CasinoGames.hand_value(["A", 6, 10]) == 17 and CasinoGames.hand_value(["A", "A", 9]) == 21
	)


func test_hand_value_face_cards_are_ten() -> bool:
	# K + Q = 20.
	return CasinoGames.hand_value(["K", "Q"]) == 20


func test_is_blackjack() -> bool:
	return (
		CasinoGames.is_blackjack(["A", "K"])
		and not CasinoGames.is_blackjack([7, 7, 7])
		and not CasinoGames.is_blackjack(["A", 5, 5])
	)


func test_is_bust_and_dealer_should_hit() -> bool:
	# Bust over 21; dealer hits 16, stands 17.
	return (
		CasinoGames.is_bust(22)
		and not CasinoGames.is_bust(21)
		and CasinoGames.dealer_should_hit(16)
		and not CasinoGames.dealer_should_hit(17)
	)


func test_blackjack_settle_win_and_natural() -> bool:
	# 20 beats 18 -> 200; player 21 (natural, default 2 cards) vs 20 -> 2.5x = 250.
	return (
		CasinoGames.blackjack_settle(20, 18, 100) == 200
		and CasinoGames.blackjack_settle(21, 20, 100) == 250
	)


func test_blackjack_multicard_21_is_not_a_natural() -> bool:
	# A 21 built from THREE cards is an ordinary win (2x), not the 2.5x natural;
	# a two-card 21 still pays the natural bonus.
	return (
		CasinoGames.blackjack_settle(21, 20, 100, 3) == 200
		and CasinoGames.blackjack_settle(21, 20, 100, 2) == 250
	)


func test_blackjack_settle_push() -> bool:
	# Equal totals push: stake of 100 returned.
	return CasinoGames.blackjack_settle(18, 18, 100) == 100


func test_blackjack_settle_loss_and_bust() -> bool:
	return (
		CasinoGames.blackjack_settle(17, 20, 100) == 0
		and CasinoGames.blackjack_settle(23, 18, 100) == 0
	)


# --- Bankroll ----------------------------------------------------------------


func test_bankroll_starts_with_chips() -> bool:
	var bank := CasinoGames.new(500)
	return bank.chips() == 500 and not bank.is_broke()


func test_place_bet_rejects_over_chips() -> bool:
	var bank := CasinoGames.new(100)
	return not bank.place_bet(150) and bank.chips() == 100


func test_place_bet_deducts_and_win_adds() -> bool:
	var bank := CasinoGames.new(100)
	if not bank.place_bet(40) or bank.chips() != 60:
		return false
	bank.win(80)
	return bank.chips() == 140


func test_is_broke_after_losing_all() -> bool:
	var bank := CasinoGames.new(50)
	bank.place_bet(50)
	return bank.is_broke() and bank.chips() == 0


func test_reset_restores_starting_chips() -> bool:
	var bank := CasinoGames.new(200)
	bank.place_bet(120)
	bank.reset()
	return bank.chips() == 200


func test_house_edge_documented() -> bool:
	return (
		is_equal_approx(CasinoGames.house_edge("roulette"), 0.027)
		and CasinoGames.house_edge("unknown") == 0.0
	)
