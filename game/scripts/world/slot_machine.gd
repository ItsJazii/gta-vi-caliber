class_name SlotMachine
extends Node3D
## A walk-up casino slot machine: face it and press the interact key to bet
## `bet_amount` and spin. Self-contained — joins group `interactables` and answers
## the interact contract (cf. Shop), consumes the tested CasinoGames model, and
## pays/charges the live PlayerStats wallet. No UI dependency: the wallet swing IS
## the outcome, and `slot_played` carries the reels + net for any HUD/bark to show.
## Interact-gated, so you only ever gamble on purpose. Wiring exercised by
## tests/slot_machine_probe.gd.

## Emitted on each spin: the reel symbols and the net wallet change (payout - bet).
signal slot_played(reels: Array, net: int)

## Chips wagered per spin.
@export var bet_amount: int = 100

var _rng: RandomNumberGenerator


func _init() -> void:
	_rng = RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("interactables")
	_rng.randomize()


## Seed the spin RNG for deterministic tests/replays.
func set_seed(seed_value: int) -> void:
	_rng.seed = seed_value


## Interact-contract: the on-screen prompt.
func interact_prompt() -> String:
	return "Play Slots ($%d)" % bet_amount


## Interact-contract: bet and spin once. No-op if the player can't cover the bet.
func interact(_player: Node) -> void:
	var stats := get_tree().get_first_node_in_group("player_stats") as PlayerStats
	if stats == null:
		return
	if not stats.spend_money(bet_amount):
		return
	var reels: Array = CasinoGames.slot_spin(_rng)
	var payout: int = CasinoGames.slot_payout(reels, bet_amount)
	if payout > 0:
		stats.add_money(payout)
	slot_played.emit(reels, payout - bet_amount)
