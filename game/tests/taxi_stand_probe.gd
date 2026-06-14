extends SceneTree
## Runtime wiring + fast-travel probe for the live TaxiStand in miami.tscn.
##
## Boots the real map, asserts the stand is present and registered as an
## interactable (so the player can walk up and press to ride), tops up the LIVE
## player_stats wallet so the fare is affordable, then drives interact() twice.
## After the first ride it asserts the player landed on destinations[0] (within a
## small epsilon) and the wallet dropped by exactly `fare`; after the second it
## asserts the cursor advanced to destinations[1] — proving the teleport, the fare
## debit through the real wallet, and the cycling cursor all flow end to end.
## Self-contained. Run headless:
##   godot --headless --path game --script res://tests/taxi_stand_probe.gd

const SCENE_PATH: String = "res://scenes/world/miami.tscn"
const WARMUP_FRAMES: int = 90
## Big top-up so the fares are always affordable regardless of starting cash.
const WALLET_TOPUP: int = 1_000_000
## Teleport landing tolerance (m): the move is a hard set, so this is generous.
const EPSILON: float = 0.01

var _scene: Node = null
var _frames: int = 0


func _initialize() -> void:
	var packed: PackedScene = load(SCENE_PATH)
	if packed == null:
		push_error("taxi stand probe: scene failed to load")
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
		print("taxi stand probe: OK (2 rides, cycling drop-offs)")
		quit(0)
	else:
		push_error("taxi stand probe FAIL: " + err)
		quit(1)
	return true


func _verify() -> String:
	var stand := _scene.find_child("TaxiStand", true, false) as TaxiStand
	if stand == null:
		return "TaxiStand not present in miami.tscn"
	if not stand.is_in_group("interactables"):
		return "TaxiStand not registered as an interactable"
	if stand.destinations.size() < 2:
		return "TaxiStand needs >=2 destinations to test cycling"
	var stats := get_first_node_in_group("player_stats") as PlayerStats
	var player := get_first_node_in_group("player") as Node3D
	if stats == null or player == null:
		return "no live player / player_stats node"
	return _run_rides(stand, stats, player)


## Top up the wallet, ride twice, and assert the landing + fare for each leg.
func _run_rides(stand: TaxiStand, stats: PlayerStats, player: Node3D) -> String:
	stats.add_money(WALLET_TOPUP)
	var money_before: int = int(stats.money)
	stand.interact(player)
	if player.global_position.distance_to(stand.destinations[0]) > EPSILON:
		return "first ride landed at %s, not destinations[0]" % player.global_position
	if int(stats.money) != money_before - stand.fare:
		return "fare drift: expected -%d, wallet now %d" % [stand.fare, int(stats.money)]
	stand.interact(player)
	if player.global_position.distance_to(stand.destinations[1]) > EPSILON:
		return "second ride did not cycle to destinations[1]"
	return ""
