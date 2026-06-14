class_name BlackjackTable
extends Node3D
## A walk-up blackjack table the player can use. Mirrors the storefront Shop
## interactable shape (self-wires into the "interactables" group, exposes
## interact_prompt()/interact()), but drives the unit-tested CasinoGames blackjack
## helpers instead of a shop catalogue. Completes the casino floor alongside the
## slot machine and roulette table.
##
## One press = one hand: the fixed bet is debited from the live PlayerStats wallet
## (the guarded spend_money path), the player and dealer are dealt from a node-owned
## RandomNumberGenerator, then play out by the house rules baked into CasinoGames
## (player stands on 17, dealer hits while dealer_should_hit). CasinoGames.blackjack_settle
## returns the TOTAL chips coming back (stake included, 0 on a loss). Any winnings are
## credited via add_money and blackjack_played(player_value, dealer_value, net) fires
## with the wallet delta for this hand (net = payout - bet).
##
## Cards are plain int ranks 1..13 (ace == 1), the format CasinoGames._card_rank
## reads directly, so hand_value/is_blackjack/dealer_should_hit need no conversion.
## Outcomes are drawn from a node-owned RandomNumberGenerator so a test can seed the
## table (set_seed) and replay a deterministic run; gameplay leaves it on its random
## default. Asset-agnostic like Shop: just drop it at the table and go.

## Fired after a resolved hand: the final player/dealer totals and the net change
## to the wallet for this hand (positive on a win, negative on a loss/no-pay).
signal blackjack_played(player_value: int, dealer_value: int, net: int)

## The total at or above which the player stands (house-style fixed strategy).
const PLAYER_STAND: int = 17

## Chips staked per press (debited up-front; only deals if affordable).
@export var bet_amount: int = 50

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("interactables")


## HUD prompt shown when the player faces the table.
func interact_prompt() -> String:
	return "Play Blackjack ($%d)" % bet_amount


## One press: place the fixed bet, deal and play out a hand, pay any winnings,
## announce the net.
func interact(_player: Node) -> void:
	var stats := get_tree().get_first_node_in_group("player_stats") as PlayerStats
	if stats == null:
		return
	if not stats.spend_money(bet_amount):
		return
	var player_hand := _play_player_hand()
	var dealer_hand := _play_dealer_hand()
	var player_value := CasinoGames.hand_value(player_hand)
	var dealer_value := CasinoGames.hand_value(dealer_hand)
	var payout := CasinoGames.blackjack_settle(player_value, dealer_value, bet_amount)
	if payout > 0:
		stats.add_money(payout)
	blackjack_played.emit(player_value, dealer_value, payout - bet_amount)


## Seed the deal RNG so a test can replay a deterministic sequence of hands.
func set_seed(seed_value: int) -> void:
	_rng.seed = seed_value


## Draw a single card as an int rank 1..13 (ace == 1), the format hand_value reads.
func _draw_card() -> int:
	return _rng.randi_range(1, 13)


## Deal the player two cards, then hit while under PLAYER_STAND and not bust.
func _play_player_hand() -> Array:
	var hand: Array = [_draw_card(), _draw_card()]
	while CasinoGames.hand_value(hand) < PLAYER_STAND:
		hand.append(_draw_card())
	return hand


## Deal the dealer two cards, then hit while dealer_should_hit on the running total.
func _play_dealer_hand() -> Array:
	var hand: Array = [_draw_card(), _draw_card()]
	while CasinoGames.dealer_should_hit(CasinoGames.hand_value(hand)):
		hand.append(_draw_card())
	return hand
