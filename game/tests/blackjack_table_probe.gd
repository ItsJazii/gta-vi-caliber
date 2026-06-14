extends SceneTree
## Runtime wiring + economy probe for the live BlackjackTable in miami.tscn.
##
## Boots the real map, asserts the table is present and registered as an
## interactable (so the player can walk up and press to play), seeds its deal for
## a deterministic run, tops up the LIVE player_stats wallet so the bets are
## affordable, then drives ~12 hands through interact(). Each hand emits
## blackjack_played(player_value, dealer_value, net); the probe sums the emitted
## nets and asserts the wallet moved by exactly that sum — proving the bet debit
## and any winnings flow through the real wallet with no leakage. Self-contained.
## Run headless:
##   godot --headless --path game --script res://tests/blackjack_table_probe.gd

const SCENE_PATH: String = "res://scenes/world/miami.tscn"
const WARMUP_FRAMES: int = 90
const HAND_COUNT: int = 12
const SEED_VALUE: int = 20260613
## Big top-up so a string of losses can never make a bet unaffordable mid-run.
const WALLET_TOPUP: int = 1_000_000

var _scene: Node = null
var _frames: int = 0
var _nets: Array[int] = []


func _initialize() -> void:
	var packed: PackedScene = load(SCENE_PATH)
	if packed == null:
		push_error("blackjack table probe: scene failed to load")
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
		print("blackjack table probe: OK (%d hands, net sum %d)" % [HAND_COUNT, _sum_nets()])
		quit(0)
	else:
		push_error("blackjack table probe FAIL: " + err)
		quit(1)
	return true


func _verify() -> String:
	var table := _scene.find_child("BlackjackTable", true, false) as BlackjackTable
	if table == null:
		return "BlackjackTable not present in miami.tscn"
	if not table.is_in_group("interactables"):
		return "BlackjackTable not registered as an interactable"
	var stats := get_first_node_in_group("player_stats") as PlayerStats
	var player := get_first_node_in_group("player")
	if stats == null or player == null:
		return "no live player / player_stats node"
	return _run_loop(table, stats, player)


## Seed the deal, top up the wallet, run the hands, and assert the wallet moved
## by exactly the sum of the emitted per-hand nets.
func _run_loop(table: BlackjackTable, stats: PlayerStats, player: Node) -> String:
	table.set_seed(SEED_VALUE)
	table.blackjack_played.connect(_on_played)
	stats.add_money(WALLET_TOPUP)
	var money_before: int = int(stats.money)
	for _i in HAND_COUNT:
		table.interact(player)
	if _nets.size() != HAND_COUNT:
		return "expected %d hands, got %d" % [HAND_COUNT, _nets.size()]
	var expected: int = money_before + _sum_nets()
	if int(stats.money) != expected:
		return "wallet drift: expected %d, got %d" % [expected, int(stats.money)]
	return ""


func _on_played(_player_value: int, _dealer_value: int, net: int) -> void:
	_nets.append(net)


func _sum_nets() -> int:
	var total: int = 0
	for net in _nets:
		total += net
	return total
