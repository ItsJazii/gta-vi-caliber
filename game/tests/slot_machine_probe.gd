extends SceneTree
## Runtime probe for the live SlotMachine in miami.tscn. Boots the map, asserts the
## machine joined the `interactables` group and answers the interact contract, then
## plays a seeded run of spins through the live PlayerStats wallet and asserts the
## wallet moves by exactly the sum of the per-spin nets (bet charged, payout paid).
## Self-contained (no miami_wiring_probe touch).
##   godot --headless --path game --script res://tests/slot_machine_probe.gd

const SCENE_PATH: String = "res://scenes/world/miami.tscn"
const WARMUP_FRAMES: int = 90
const SPINS: int = 12

var _scene: Node = null
var _frames: int = 0
var _plays: int = 0
var _net_sum: int = 0


func _on_played(_reels: Array, net: int) -> void:
	_plays += 1
	_net_sum += net


func _initialize() -> void:
	var packed: PackedScene = load(SCENE_PATH)
	if packed == null:
		push_error("slot machine probe: scene failed to load")
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
		print("slot machine probe: OK (%d spins, net %d)" % [_plays, _net_sum])
		quit(0)
	else:
		push_error("slot machine probe FAIL: " + err)
		quit(1)
	return true


func _verify() -> String:
	var slot := _scene.find_child("SlotMachine", true, false) as SlotMachine
	if slot == null:
		return "SlotMachine not present in miami.tscn"
	if not slot.is_in_group("interactables") or not slot.has_method("interact"):
		return "SlotMachine is not a live interactable (group/contract missing)"
	var stats := get_first_node_in_group("player_stats") as PlayerStats
	if stats == null:
		return "no live player_stats"
	slot.set_seed(20260613)
	slot.slot_played.connect(_on_played)
	stats.add_money(100000)  # cover the wager run regardless of starting balance
	var before: int = int(stats.money)
	var player := get_first_node_in_group("player")
	for _i in range(SPINS):
		slot.interact(player)
	if _plays != SPINS:
		return "expected %d spins, got %d (bet not affordable?)" % [SPINS, _plays]
	if int(stats.money) - before != _net_sum:
		return "wallet moved %d, sum of nets was %d" % [int(stats.money) - before, _net_sum]
	return ""
