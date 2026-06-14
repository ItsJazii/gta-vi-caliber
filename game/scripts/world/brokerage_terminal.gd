class_name BrokerageTerminal
extends Node3D
## A walk-up stock-trading terminal: face it, press interact, and the first press
## BUYS a lot of one company's shares (charged to PlayerStats); every later press
## SELLS the whole position back at the live price (proceeds credited to
## PlayerStats). Between presses the terminal drifts the market over real time so a
## held position gains or loses value — surfacing the unit-tested StockMarket model
## to the player for the first time. Mirrors BusinessVentureHub's "owns a RefCounted
## model, drives it in _process, resolves the wallet by group" economy pattern.
##
## The Interactable contract (see Interaction): joins group "interactables" and
## answers interact_prompt() + interact(player). All money is resolved against the
## live wallet; StockMarket itself never touches PlayerStats — we apply its returned
## cost/proceeds ourselves via the guarded spend_money()/add_money() paths.

## Fired when the player opens a position (company id, shares bought, cost charged).
signal shares_bought(id: String, qty: int, cost: int)
## Fired when the player closes a position (company id, total proceeds credited).
signal shares_sold(id: String, proceeds: int)

## StockMarket company id this terminal trades (must exist in the roster).
@export var stock_id: String = "bittn_tech"
## Shares bought per "open position" press.
@export var lot_size: int = 10
## Real seconds between small random market drifts (a living, wandering price).
@export var drift_seconds: float = 5.0
## Std-dev of each drift's signed price nudge — small so prices wander both ways.
@export var drift_magnitude: float = 0.04

## The live equities model. Public so a trade/HUD UI can read prices + the portfolio.
var market: StockMarket

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _drift_clock: float = 0.0
var _stats: Node = null


func _init() -> void:
	market = StockMarket.new()


func _ready() -> void:
	add_to_group("interactables")


## Drive the owned market forward in real time so a held position has live P&L.
func _process(delta: float) -> void:
	tick_market(delta)


## HUD hint: the company, its live price, and whether the next press buys or sells.
func interact_prompt() -> String:
	var held := position()
	if held > 0:
		return "Sell %d %s @ $%d" % [held, stock_id, market.price(stock_id)]
	return "Buy %d %s @ $%d" % [lot_size, stock_id, market.price(stock_id)]


## First press opens a position; every later press closes it.
func interact(_player: Node) -> void:
	if position() > 0:
		_sell()
	else:
		_buy()


## Buy lot_size shares at the live price, charge the returned cost to the wallet.
## No-op if the wallet is absent or the buy is unaffordable.
func _buy() -> void:
	var stats := _player_stats()
	if stats == null or not ("money" in stats):
		return
	var result: Dictionary = market.buy(stock_id, lot_size, int(stats.money))
	if not result.get("success", false) or not stats.has_method("spend_money"):
		return
	var cost: int = int(result["cost"])
	if not stats.spend_money(cost):
		return
	shares_bought.emit(stock_id, lot_size, cost)


## Sell the whole held position at the live price and bank the proceeds.
func _sell() -> void:
	var held := position()
	if held <= 0:
		return
	var result: Dictionary = market.sell(stock_id, held)
	if not result.get("success", false):
		return
	var proceeds: int = int(result["proceeds"])
	var stats := _player_stats()
	if proceeds <= 0 or stats == null or not stats.has_method("add_money"):
		return
	stats.add_money(proceeds)
	shares_sold.emit(stock_id, proceeds)


## Advance the market by a real-time span: every drift_seconds, nudge this company's
## price by a small signed random move so holding/selling has real P&L. Exposed so a
## probe can advance prices deterministically without waiting real seconds.
func tick_market(delta: float) -> void:
	if delta <= 0.0 or drift_seconds <= 0.0:
		return
	_drift_clock += delta
	while _drift_clock >= drift_seconds:
		_drift_clock -= drift_seconds
		market.apply_company_event(stock_id, _rng.randfn(0.0, drift_magnitude))


## Shares currently held in this terminal's company (0 if flat), for a HUD readout.
func position() -> int:
	return market.shares_held(stock_id) if market != null else 0


## Seed the drift rng so a probe gets a deterministic market walk.
func set_seed(seed_value: int) -> void:
	_rng.seed = seed_value


func _player_stats() -> Node:
	if _stats == null or not is_instance_valid(_stats):
		_stats = get_tree().get_first_node_in_group("player_stats")
	return _stats
