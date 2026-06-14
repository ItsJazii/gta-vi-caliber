extends SceneTree
## Runtime wiring + economy probe for the live BrokerageTerminal in miami.tscn.
##
## Boots the real map, asserts the terminal is a registered interactable owning a
## StockMarket, then drives the trade loop against the LIVE player_stats wallet:
## interact once to BUY a lot (wallet drops by the buy cost, position opens), drift
## the market deterministically so the price moves, interact again to SELL the whole
## position (wallet credited by the proceeds, position back to flat). Asserts the
## full buy->hold->sell round-trip moves the wallet coherently with no leakage.
## Self-contained. Run:
##   godot --headless --path game --script res://tests/brokerage_terminal_probe.gd

const SCENE_PATH: String = "res://scenes/world/miami.tscn"
const WARMUP_FRAMES: int = 90
## Deterministic drift seed for the terminal's price walk.
const SEED: int = 1337
## Cash fronted so the probe exercises the buy path, not the can't-afford branch.
const FRONT_MONEY: int = 200000
## Real-time drift steps applied between buy and sell so the price wanders.
const DRIFT_STEPS: int = 12

var _scene: Node = null
var _frames: int = 0


func _initialize() -> void:
	var packed: PackedScene = load(SCENE_PATH)
	if packed == null:
		push_error("brokerage terminal probe: scene failed to load")
		quit(1)
		return
	_scene = packed.instantiate()
	root.add_child(_scene)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < WARMUP_FRAMES:
		return false
	var err := _verify()
	if err.is_empty():
		quit(0)
	else:
		push_error("brokerage terminal probe FAIL: " + err)
		quit(1)
	return true


func _verify() -> String:
	var term := _scene.find_child("BrokerageTerminal", true, false) as BrokerageTerminal
	if term == null:
		print("BrokerageTerminal not present in miami.tscn")
		return "BrokerageTerminal not present in miami.tscn"
	var wiring_err := _verify_wiring(term)
	if not wiring_err.is_empty():
		return wiring_err
	return _verify_loop(term)


## The terminal is live, owns a market, is a registered interactable, starts flat.
func _verify_wiring(term: BrokerageTerminal) -> String:
	if term.market == null:
		return "BrokerageTerminal / its market not present in miami.tscn"
	if not term.is_in_group("interactables"):
		return "terminal not in group 'interactables'"
	if not term.has_method("interact") or not term.has_method("interact_prompt"):
		return "terminal does not answer the interactable contract"
	if term.position() != 0:
		return "terminal starts already holding a position (should buy on first interact)"
	return ""


## buy -> drift -> sell round trip against the live wallet, no leakage.
func _verify_loop(term: BrokerageTerminal) -> String:
	var player := get_first_node_in_group("player")
	var stats := get_first_node_in_group("player_stats")
	if player == null or stats == null or not ("money" in stats):
		return "no live player / player_stats node"
	if stats.has_method("add_money"):
		stats.add_money(FRONT_MONEY)
	term.set_seed(SEED)

	var money0: int = int(stats.money)
	var buy_unit: int = term.market.price(term.stock_id)
	term.interact(player)
	if term.position() <= 0:
		return "buy did not open a position (position %d)" % term.position()
	var after_buy: int = int(stats.money)
	var leak := _verify_buy_charge(term, money0, after_buy, buy_unit)
	if not leak.is_empty():
		return leak

	for _i in range(DRIFT_STEPS):
		term.tick_market(term.drift_seconds)
	# Guarantee a price move regardless of the random walk's direction.
	term.market.apply_company_event(term.stock_id, 0.5)
	return _verify_sell(term, player, stats, after_buy)


## The buy debit equals price * lot_size exactly (wallet drops, no extra leak).
func _verify_buy_charge(
	term: BrokerageTerminal, money0: int, after_buy: int, buy_unit: int
) -> String:
	var expected_cost: int = buy_unit * term.position()
	var charged: int = money0 - after_buy
	if charged != expected_cost or charged <= 0:
		return "buy charge mismatch (charged %d, expected %d)" % [charged, expected_cost]
	return ""


## Selling the full position empties it and credits the wallet by the proceeds.
func _verify_sell(term: BrokerageTerminal, player: Node, stats: Node, after_buy: int) -> String:
	var held: int = term.position()
	var sell_unit: int = term.market.price(term.stock_id)
	var expected_proceeds: int = sell_unit * held
	term.interact(player)
	if term.position() != 0:
		return "sell did not close the position (position %d)" % term.position()
	var credited: int = int(stats.money) - after_buy
	if credited != expected_proceeds or credited <= 0:
		return "sell credit mismatch (credited %d, expected %d)" % [credited, expected_proceeds]
	print(
		(
			"brokerage terminal probe: OK (bought %d %s, wallet -> %d, sold for %d, wallet -> %d)"
			% [held, term.stock_id, after_buy, credited, int(stats.money)]
		)
	)
	return ""
