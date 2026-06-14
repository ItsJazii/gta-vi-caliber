class_name CasinoGames
extends RefCounted
## Pure casino gambling model — blackjack, slots, and roulette payout/odds math
## plus a small stateful chip bankroll for a session.
##
## No nodes, no scene access. The static helpers are pure odds/payout functions;
## every spin/deal takes a caller-supplied RandomNumberGenerator so outcomes are
## reproducible in tests (tests/unit/test_casino_games.gd); never the global
## randf/randi. The only state is the per-session bankroll (chips) created via
## _init; a table node owns one CasinoGames and drives it.
##
## Payout helpers return the TOTAL chips returned to the player (stake included),
## or 0 on a loss — so a winning even-money 1:1 bet of 10 returns 20.

# --- Roulette -----------------------------------------------------------------

## European single-zero wheel: pockets 0..36.
const ROULETTE_POCKETS: int = 37

## bet_type values accepted by roulette_payout:
##   "straight" — single number (number_landed must equal the bet's target;
##                this helper assumes the caller already matched the number, see
##                roulette_payout's contract); pays 35:1.
##   "red" / "black"   — colour bets, pay 1:1.
##   "even" / "odd"    — parity bets, pay 1:1.
##   "low" / "high"    — 1-18 / 19-36, pay 1:1.
##   "dozen1"/"dozen2"/"dozen3" — 1-12 / 13-24 / 25-36, pay 2:1.
## 0 wins none of the even-money or dozen bets (house pocket).

## Red numbers on a European roulette wheel.
const ROULETTE_RED: Array = [1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36]

# --- Slots --------------------------------------------------------------------

## Symbol ids on a reel, weakest to strongest. Index doubles as the symbol id.
const SLOT_SYMBOLS: Array = ["cherry", "lemon", "bell", "bar", "seven"]

## Three-of-a-kind payout multiplier per symbol id (applied to the bet amount).
const SLOT_TRIPLE_MULT: Dictionary = {
	"cherry": 5,
	"lemon": 10,
	"bell": 20,
	"bar": 50,
	"seven": 100,
}

## Two-of-a-kind (partial) pays this multiple of the bet, regardless of symbol.
const SLOT_PARTIAL_MULT: int = 2

# --- Blackjack ----------------------------------------------------------------

## Dealer stands on 17 and above, hits below.
const DEALER_STAND: int = 17

## A blackjack pays 3:2 — total returned is 2.5x the stake.
const BLACKJACK_RETURN_MULT: float = 2.5

# --- Bankroll state -----------------------------------------------------------

var _starting_chips: int = 0
var _chips: int = 0


func _init(starting_chips: int = 1000) -> void:
	_starting_chips = maxi(starting_chips, 0)
	_chips = _starting_chips


# === Roulette =================================================================


## Spin the wheel: a uniform pocket in 0..36, drawn from rng.
static func roulette_spin(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(0, ROULETTE_POCKETS - 1)


## True when the landed number is a red pocket.
static func roulette_is_red(number_landed: int) -> bool:
	return ROULETTE_RED.has(number_landed)


## Total chips returned for a resolved roulette bet (0 on a loss).
##
## For "straight" the caller passes the number they bet on as number_landed only
## when it hit; this helper decides the win from bet_type vs number_landed:
## straight wins iff number_landed is in 1..36 or 0 (any valid pocket the caller
## already confirmed matched), paying 35:1. For colour/parity/range/dozen bets
## the win is derived purely from number_landed.
static func roulette_payout(bet_type: String, number_landed: int, bet_amount: int) -> int:
	var stake := maxi(bet_amount, 0)
	if stake == 0:
		return 0
	if number_landed < 0 or number_landed >= ROULETTE_POCKETS:
		return 0
	if bet_type == "straight":
		return stake * 36
	# 0 loses every outside bet.
	if number_landed == 0:
		return 0
	var won := false
	match bet_type:
		"red":
			won = roulette_is_red(number_landed)
		"black":
			won = not roulette_is_red(number_landed)
		"even":
			won = number_landed % 2 == 0
		"odd":
			won = number_landed % 2 == 1
		"low":
			won = number_landed >= 1 and number_landed <= 18
		"high":
			won = number_landed >= 19 and number_landed <= 36
		"dozen1":
			return stake * 3 if number_landed <= 12 else 0
		"dozen2":
			return stake * 3 if number_landed >= 13 and number_landed <= 24 else 0
		"dozen3":
			return stake * 3 if number_landed >= 25 else 0
		_:
			return 0
	return stake * 2 if won else 0


# === Slots ====================================================================


## Spin `reels` reels; returns an Array of symbol ids drawn from rng.
static func slot_spin(rng: RandomNumberGenerator, reels: int = 3) -> Array:
	var out: Array = []
	for _i in range(maxi(reels, 1)):
		out.append(SLOT_SYMBOLS[rng.randi_range(0, SLOT_SYMBOLS.size() - 1)])
	return out


## Total chips returned for a slot result (0 on a loss).
## Three-of-a-kind pays by symbol; any two matching reels pay a flat partial;
## otherwise nothing.
static func slot_payout(result: Array, bet_amount: int) -> int:
	var stake := maxi(bet_amount, 0)
	if stake == 0 or result.is_empty():
		return 0
	var counts: Dictionary = {}
	for symbol in result:
		counts[symbol] = int(counts.get(symbol, 0)) + 1
	var best := 0
	for symbol in counts:
		var n: int = counts[symbol]
		if n >= 3 and SLOT_TRIPLE_MULT.has(symbol):
			best = maxi(best, stake * int(SLOT_TRIPLE_MULT[symbol]))
		elif n == 2:
			best = maxi(best, stake * SLOT_PARTIAL_MULT)
	return best


# === Blackjack ================================================================


## Value of a hand; aces count as 11 then drop to 1 as needed to avoid a bust.
## Cards are ranks 1..13 (or the strings "A","J","Q","K"); 10/J/Q/K all = 10.
static func hand_value(cards: Array) -> int:
	var total := 0
	var aces := 0
	for card in cards:
		var rank := _card_rank(card)
		if rank == 1:
			aces += 1
			total += 11
		elif rank >= 10:
			total += 10
		else:
			total += rank
	while total > 21 and aces > 0:
		total -= 10
		aces -= 1
	return total


## A natural blackjack: exactly two cards totalling 21.
static func is_blackjack(cards: Array) -> bool:
	return cards.size() == 2 and hand_value(cards) == 21


## A hand value over 21 is a bust.
static func is_bust(value: int) -> bool:
	return value > 21


## Dealer hits on any total below 17 (stands on 17+).
static func dealer_should_hit(value: int) -> bool:
	return value < DEALER_STAND


## Total chips returned settling player vs dealer for the given stake.
## A NATURAL blackjack — 21 on the first two cards — returns 2.5x; an ordinary
## win (including a multi-card 21) returns 2x; a push returns the stake (1x); a
## loss returns 0. A player bust always loses. `player_card_count` defaults to 2
## (the freshly-dealt hand) so a bare 21 reads as a natural; pass the real count
## (3+) for a hit-to-21 hand so it is paid as an ordinary win, not a natural.
static func blackjack_settle(
	player_value: int, dealer_value: int, bet: int, player_card_count: int = 2
) -> int:
	var stake := maxi(bet, 0)
	if stake == 0:
		return 0
	if is_bust(player_value):
		return 0
	# A natural is 21 on exactly two cards; a 21 built from three+ cards is just a
	# strong ordinary win and must not collect the 3:2 natural bonus.
	var player_natural := player_value == 21 and player_card_count == 2
	if is_bust(dealer_value):
		return _natural_or_even(player_natural, stake)
	if player_value > dealer_value:
		return _natural_or_even(player_natural, stake)
	if player_value == dealer_value:
		return stake
	return 0


# === Bankroll =================================================================


## Reserve `amount` chips for a bet; false (no change) if it exceeds the balance
## or is non-positive.
func place_bet(amount: int) -> bool:
	if amount <= 0 or amount > _chips:
		return false
	_chips -= amount
	return true


## Credit winnings (non-negative) back to the bankroll.
func win(amount: int) -> void:
	_chips += maxi(amount, 0)


## Current chip balance.
func chips() -> int:
	return _chips


## True when the bankroll is empty.
func is_broke() -> bool:
	return _chips <= 0


## Restore the bankroll to its starting amount.
func reset() -> void:
	_chips = _starting_chips


# === Info =====================================================================


## Documented nominal house edge per game (fraction the house keeps long-run).
## Informational only — not used by the payout math. Unknown game returns 0.0.
static func house_edge(game: String) -> float:
	match game:
		"roulette":
			return 0.027  # European single-zero: 1/37.
		"slots":
			return 0.08  # Typical modelled slot hold.
		"blackjack":
			return 0.005  # Basic-strategy ballpark.
		_:
			return 0.0


# === Internals ================================================================


## Returns 2.5x for a natural blackjack, else 2x (even-money win).
static func _natural_or_even(player_natural: bool, stake: int) -> int:
	if player_natural:
		return int(stake * BLACKJACK_RETURN_MULT)
	return stake * 2


## Normalise a card to its blackjack rank 1..13 (ace == 1).
static func _card_rank(card: Variant) -> int:
	if card is int:
		return clampi(card, 1, 13)
	var name := str(card).to_upper()
	match name:
		"A", "ACE":
			return 1
		"J", "JACK":
			return 11
		"Q", "QUEEN":
			return 12
		"K", "KING":
			return 13
		_:
			return clampi(int(name), 1, 13)
